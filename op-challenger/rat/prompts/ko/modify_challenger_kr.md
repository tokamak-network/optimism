
# Randomized Attention Test (RAT) Challenger

RAT은 챌리저들이 성실히 모니터링을 하고 있는지 챌린저 attention 테스트하기 위해 설계되었습니다.

**컨트랙 관련사항은 build_contracts_draft-v2.md를 참고한다.**

## 구현 방향

### 1. 최소 스테이킹 조건 충족
- 챌린저 실행시, 스테이킹 금액을 확인해서, 최소 스테이킹금액보다 작으면 최소 스테이킹 이상되도록 스테이킹한다.

### 2. game_solver.go 수정
- **파일**: `op-challenger/game/fault/solver/game_solver.go`

#### 2.1. 어텐션 올바른 증거제출 함수 submitCorrectEvidence 추가
- 루트 클래임이 올바르다고 판단된 경우 실행되는 함수입니다.
- **RAT 컨트랙트 함수 시그니처**:
```solidity
function submitCorrectEvidence(
    address _gameAddress,       // 게임주소
    bytes32 _proofLV,           // 왼쪽 자식의 상태값
    bytes32 _proofRV            // 오른쪽 자식의 상태값
) external
```

- **동작**:
  - RAT 컨트랙에서 _gameAddress 게임주소를 이용하여, 어텐션 정보를 조회합니다.
  - (어텐션정보.챌린저주소 == 워커(챌린저) 주소) && (어텐션정보.증거제출완료여부 == false) 이면,
    - RAT컨트랙."참이라는 어텐션증거 제출 함수" 를 호출합니다.

- **Go 구현**:
```go
func (s *GameSolver) submitCorrectEvidence(ctx context.Context, game types.Game) error {
    // 1. 루트 클레임의 자식 노드 값들을 계산
    rootClaim := game.Claims()[0]

    // 2. 왼쪽 자식 (Attack) 위치와 값 계산
    leftPosition := rootClaim.Position.Attack()
    leftValue, err := s.claimSolver.trace.Get(ctx, game, rootClaim, leftPosition)
    if err != nil {
        return fmt.Errorf("failed to get left child value: %w", err)
    }

    // 3. 오른쪽 자식 (Defend) 위치와 값 계산
    rightPosition := rootClaim.Position.Defend()
    rightValue, err := s.claimSolver.trace.Get(ctx, game, rootClaim, rightPosition)
    if err != nil {
        return fmt.Errorf("failed to get right child value: %w", err)
    }

    // 4. RAT 컨트랙트 호출
    return s.callRATSubmitCorrectEvidence(ctx, game.Addr(), leftValue, rightValue)
}
```

#### 2.2. CalculateNextActions 함수 변경
- 챌린저가 루트 클래임의 참/거짓 확인시 어텐션 조건에 따른 '(2.1)어텐션 올바른 증거제출 함수' 실행
- 루트 클래임도 올바르고, L2 블록번호도 올바르다면, '(2.1)어텐션 올바른 증거제출 함수' 함수를 호출합니다.

- **수정할 코드 위치**:
```go
func (s *GameSolver) CalculateNextActions(ctx context.Context, game types.Game) ([]types.Action, error) {
    agreeWithRootClaim, err := s.AgreeWithRootClaim(ctx, game)
    if err != nil {
        return nil, fmt.Errorf("failed to determine if root claim is correct: %w", err)
    }

    if agreeWithRootClaim {
        if challenge, err := s.claimSolver.trace.GetL2BlockNumberChallenge(ctx, game); errors.Is(err, types.ErrL2BlockNumberValid) {
            // We agree with the L2 block number, proceed to processing claims

            // RAT 어텐션 테스트 증거 제출
            if err := s.submitCorrectEvidence(ctx, game); err != nil {
                log.Error("RAT: Failed to submit correct evidence", "error", err)
            }

        } else if err != nil {
            // Failed to check L2 block validity
            return nil, fmt.Errorf("failed to determine L2 block validity: %w", err)
        } else {
            return []types.Action{
                {
                    Type: types.ActionTypeChallengeL2BlockNumber,
                    InvalidL2BlockNumberChallenge: challenge,
                },
            }, nil
        }
    }

    // ... 나머지 기존 코드 ...
}
```

### 3. GameSolver 구조체 수정
- **필요한 필드 추가**:
```go
type GameSolver struct {
    claimSolver    *claimSolver
    ratAddress     common.Address      // RAT 컨트랙트 주소
    client         *ethclient.Client  // 이더리움 클라이언트
    challengerAddr common.Address     // 챌린저 주소
}
```

### 4. RAT 컨트랙트 호출 함수 추가
```go
func (s *GameSolver) callRATSubmitCorrectEvidence(ctx context.Context, gameAddr common.Address, leftValue, rightValue common.Hash) error {
    // RAT 컨트랙트 바인딩 및 함수 호출 구현
    // 트랜잭션 전송 및 에러 처리
    return nil
}
```

### 5. 단위 테스트 코드 작성
- **경로**: `op-challenger/game/fault/solver/game_solver_test.go`
- RAT 어텐션 테스트 로직에 대한 단위 테스트 추가

