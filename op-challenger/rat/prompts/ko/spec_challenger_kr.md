

### 게임 시작 흐름
1. Monitor → 게임 감지
   ↓
2. Scheduler → 작업 큐에 등록
   ↓
3. Worker(챌린저) → 작업 할당받음 (j := <-in)
   ↓
4. GamePlayer.ProgressGame() → 게임 진행
   ↓
5. Agent.Act() → 액션 계산 및 실행
   ↓
6. performAction() → 실제 블록체인 트랜잭션 전송
   ↓
7. Responder.PerformAction() → 컨트랙트 호출


### 챌린저가 루트 클래임의 참/거직을 확인하는 흐름
1. Agent.Act() → 게임 액션 시작
   ↓
2. GameSolver.CalculateNextActions() → 다음 액션 계산
   ↓
3. GameSolver.AgreeWithRootClaim() → 루트 클레임 확인
   ↓
4. claimSolver.agreeWithClaim() → 클레임 값 비교
   ↓
5. TraceProvider.Get() → 실제 실행 트레이스로 값 계산
   ↓
6. bytes.Equal(ourValue, claim.Value) → 참/거짓 판단

'''
// op-challenger/game/fault/solver/game_solver.go
func (s *GameSolver) CalculateNextActions(ctx context.Context, game types.Game) ([]types.Action, error) {
    // 🔥 루트 클레임이 올바른지 확인
	agreeWithRootClaim, err := s.AgreeWithRootClaim(ctx, game)
	if err != nil {
		return nil, fmt.Errorf("failed to determine if root claim is correct: %w", err)
	}

	// Challenging the L2 block number will only work if we have the same output root as the claim
	// Otherwise our output root preimage won't match. We can just proceed and invalidate the output root by disputing claims instead.
	if agreeWithRootClaim {
         // 루트가 올바르면 → L2 블록 번호 챌린지 시도
		if challenge, err := s.claimSolver.trace.GetL2BlockNumberChallenge(ctx, game); errors.Is(err, types.ErrL2BlockNumberValid) {
			// We agree with the L2 block number, proceed to processing claims
		} else if err != nil {
			// Failed to check L2 block validity
			return nil, fmt.Errorf("failed to determine L2 block validity: %w", err)
		} else {
			return []types.Action{
				{
					Type:                          types.ActionTypeChallengeL2BlockNumber,
					InvalidL2BlockNumberChallenge: challenge,
				},
			}, nil
		}
	}

    // 루트가 틀렸으면 → 클레임들을 하나씩 공격/방어
	var actions []types.Action
	agreedClaims := newHonestClaimTracker()
	if agreeWithRootClaim {
		agreedClaims.AddHonestClaim(types.Claim{}, game.Claims()[0])
	}
	for _, claim := range game.Claims() {
		var action *types.Action
		if claim.Depth() == game.MaxDepth() {
			action, err = s.calculateStep(ctx, game, claim, agreedClaims)
		} else {
			action, err = s.calculateMove(ctx, game, claim, agreedClaims)
		}
		if err != nil {
			// Unable to continue iterating claims safely because we may not have tracked the required honest moves
			// for this claim which affects the response to later claims.
			// Any actions we've already identified are still safe to apply.
			return actions, fmt.Errorf("failed to determine response to claim %v: %w", claim.ContractIndex, err)
		}
		if action == nil {
			continue
		}
		actions = append(actions, *action)
	}
	return actions, nil
}

'''

## agreeWithClaim 함수의 동작과정  -> 클래임이 올바른지 여부 판단
1.VM 실행: s.trace.Get(ctx, game, claim, claim.Position)를 호출하여
해당 포지션에서 VM(Cannon/Asterisc)을 실행
올바른 상태값(ourValue)을 계산

2. 값 비교: bytes.Equal(ourValue[:], claim.Value[:])로
VM이 계산한 올바른 값과
클레임에서 제시한 값을 비교

3. 결과 반환:
true: 클레임이 올바름 (VM 계산값과 일치)
false: 클레임이 틀림 (VM 계산값과 불일치)


## 필요한 기능 : 클래임이 올바른지 여부와 자식노드(L,R)를 리턴하는 함수

- agreeWithClaimReturnLR

// ClaimValidationResult 클레임 검증 결과와 자식 노드 정보를 포함
type ClaimValidationResult struct {
    IsCorrect    bool           // 클레임이 올바른지 여부
    LeftChild    *types.Claim   // 왼쪽 자식 클레임 (Attack)
    RightChild   *types.Claim   // 오른쪽 자식 클레임 (Defend)
    LeftValue    common.Hash    // 왼쪽 자식의 상태값
    RightValue   common.Hash    // 오른쪽 자식의 상태값
}

// agreeWithClaimAndGetChildren 클레임 검증과 함께 자식 노드 정보 반환
func (s *claimSolver) agreeWithClaimAndGetChildren(ctx context.Context, game types.Game, claim types.Claim) (*ClaimValidationResult, error) {
    // 1. 기존 agreeWithClaim 로직
    ourValue, err := s.trace.Get(ctx, game, claim, claim.Position)
    if err != nil {
        return nil, err
    }
    isCorrect := bytes.Equal(ourValue[:], claim.Value[:])

    // 2. 자식 노드 위치 계산
    leftPosition := claim.Position.Attack()   // 왼쪽 자식 (Attack)
    rightPosition := claim.Position.Defend()  // 오른쪽 자식 (Defend)

    // 3. 자식 노드 상태값 계산
    leftValue, err := s.trace.Get(ctx, game, claim, leftPosition)
    if err != nil {
        return nil, fmt.Errorf("failed to get left child value: %w", err)
    }

    rightValue, err := s.trace.Get(ctx, game, claim, rightPosition)
    if err != nil {
        return nil, fmt.Errorf("failed to get right child value: %w", err)
    }

    // 4. 자식 클레임 객체 생성
    leftChild := &types.Claim{
        ClaimData: types.ClaimData{
            Value:    leftValue,
            Position: leftPosition,
        },
        ParentContractIndex: claim.ContractIndex,
    }

    rightChild := &types.Claim{
        ClaimData: types.ClaimData{
            Value:    rightValue,
            Position: rightPosition,
        },
        ParentContractIndex: claim.ContractIndex,
    }

    return &ClaimValidationResult{
        IsCorrect:  isCorrect,
        LeftChild:  leftChild,
        RightChild: rightChild,
        LeftValue:  leftValue,
        RightValue: rightValue,
    }, nil
}

## 모니터링 이벤트

1. 이벤트 처리 흐름
L1 블록 헤드 변경 감지 → onNewL1Head 호출
새로운 게임 확인 → GetGamesAtOrAfter 호출
게임 스케줄링 → scheduler.Schedule 호출
게임 플레이어 생성 → 각 게임에 대한 플레이어 생성
게임 상태 모니터링 → 정기적으로 게임 상태 체크

2. 주요 특징
실시간 구독: L1 블록 헤드 변경만 실시간 구독
폴링 기반: 대부분의 게임 상태는 정기적 폴링으로 확인
재구독 메커니즘: 연결 실패 시 자동 재구독
배치 처리: 여러 게임을 배치로 처리하여 효율성 증대
챌린저는 주로 L1 블록 헤드 이벤트를 실시간으로 구독하고, 나머지 게임 관련 정보는 정기적 폴링을 통해 수집합니다.


## 게임 시작 과정 (폴링 기반)

1. L1 블록 헤드 이벤트 구독 (트리거)
// op-challenger/game/monitor.go
'''
// op-challenger/game/monitor.go
func (m *gameMonitor) onNewL1Head(ctx context.Context, sig eth.L1BlockRef) {
    m.clock.SetTime(sig.Time)
    // 새로운 L1 블록마다 게임 진행 상태 체크
    if err := m.progressGames(ctx, sig.Hash, sig.Number); err != nil {
        m.logger.Error("Failed to progress games", "err", err)
    }
}
'''
L1 블록 헤드 변경 이벤트 구독
새로운 블록마다 onNewL1Head 호출

2. 게임 데이터 폴링 (GetGamesAtOrAfter)
'''
// op-challenger/game/monitor.go
func (m *gameMonitor) progressGames(ctx context.Context, blockHash common.Hash, blockNumber uint64) error {
    // 1. 최소 타임스탬프 계산 (게임 윈도우 기반)
    minGameTimestamp := clock.MinCheckedTimestamp(m.clock, m.gameWindow)

    // 2. 폴링으로 게임 목록 수집
    games, err := m.source.GetGamesAtOrAfter(ctx, blockHash, minGameTimestamp)

    // 3. 허용된 게임만 필터링
    var gamesToPlay []types.GameMetadata
    for _, game := range games {
        if !m.allowedGame(game.Proxy) {
            continue
        }
        gamesToPlay = append(gamesToPlay, game)
    }

    // 4. 게임 스케줄링
    if err := m.scheduler.Schedule(gamesToPlay, blockNumber); err != nil {
        return fmt.Errorf("failed to schedule games: %w", err)
    }
}

'''
GetGamesAtOrAfter 호출로 최근 게임 목록 수집
타임스탬프 기반 필터링 (게임 윈도우 내 게임만)
허용된 게임만 필터링

- 폴링 로직 상세 (GetGamesAtOrAfter)
'''

// op-challenger/game/fault/contracts/gamefactory.go
func (f *DisputeGameFactoryContract) GetGamesAtOrAfter(ctx context.Context, blockHash common.Hash, earliestTimestamp uint64) ([]types.GameMetadata, error) {
    // 1. 전체 게임 개수 가져오기
    count, err := f.GetGameCount(ctx, blockHash)

    // 2. 배치 단위로 게임 데이터 수집
    for {
        // 게임 인덱스별로 데이터 수집
        calls := make([]batching.Call, 0, rangeEnd-rangeStart)
        for i := rangeEnd - 1; ; i-- {
            calls = append(calls, f.contract.Call(methodGameAtIndex, new(big.Int).SetUint64(i)))
        }

        // 배치 호출로 게임 메타데이터 수집
        results, err := f.multiCaller.Call(ctx, rpcblock.ByHash(blockHash), calls...)

        // 3. 타임스탬프 필터링 (최근 게임만)
        for i, result := range results {
            game := f.decodeGame(idx, result)
            if game.Timestamp < earliestTimestamp {
                return games, nil  // 오래된 게임은 무시
            }
            games = append(games, game)
        }
    }
}

'''
수집된 게임들을 스케줄러에 전달
각 게임에 대해 플레이어 생성


3. 게임 스케줄링
'''
// op-challenger/game/scheduler/scheduler.go
func (s *Scheduler) Schedule(games []types.GameMetadata, blockNumber uint64) error {
    select {
    case s.scheduleQueue <- blockGames{blockNumber: blockNumber, games: games}:
        return nil
    default:
        return ErrBusy  // 스케줄러가 바쁘면 스킵
    }
}
'''
수집된 게임들을 스케줄러에 전달
각 게임에 대해 플레이어 생성


4. 게임 플레이어 생성 및 시작
'''
// op-challenger/game/scheduler/coordinator.go
func (c *coordinator) scheduleGames(ctx context.Context, games []types.GameMetadata) {
    for _, game := range games {
        // 각 게임에 대해 플레이어 생성
        player, err := c.createPlayer(game, c.disk)
        if err != nil {
            continue
        }

        // 게임 플레이어 시작
        c.startPlayer(ctx, player)
    }
}
'''
각 게임 플레이어가 실제 게임 로직 실행
클레임 분석, 응답 결정, 트랜잭션 전송


## 여러 컴퓨터에서 같은 게임에 동시 워커 진입

시나리오: 동일 게임에 대한 경합

게임 G 생성
↓
컴퓨터 A의 챌린저: 게임 G 감지 → 워커 1, 2, 3, 4 할당
컴퓨터 B의 챌린저: 게임 G 감지 → 워커 1, 2, 3, 4 할당
컴퓨터 C의 챌린저: 게임 G 감지 → 워커 1, 2, 3, 4 할당
↓
총 12개의 워커가 동시에 같은 게임 G를 처리 시도

1. 블록체인 레벨에서의 경합
'''
// 각 워커가 동시에 같은 액션을 트랜잭션으로 전송
func (a *Agent) performAction(ctx context.Context, wg *sync.WaitGroup, action types.Action) {
    // 12개 워커가 동시에 같은 액션을 계산
    tx, err := a.responder.PerformAction(ctx, action)
    // 첫 번째로 블록에 포함된 트랜잭션만 성공
    // 나머지 11개는 실패 (nonce 충돌, 상태 변경 등)
}

'''


- 중복 실행이 되지 않게 하는 메커니즘
'''
// 1. step 함수에서의 보호
if (parent.counteredBy != address(0)) revert DuplicateStep();
parent.counteredBy = msg.sender;

// 2. move 함수에서의 보호
Hash claimHash = _claim.hashClaimPos(nextPosition, _challengeIndex);
if (claims[claimHash]) revert ClaimAlreadyExists();
claims[claimHash] = true;

// 3. 게임 상태 보호
if (status != GameStatus.IN_PROGRESS) revert GameNotInProgress();
'''

-
게임 무결성: 하나의 claim에 대해 여러 번 step할 수 없음
첫 번째 우선: 가장 먼저 성공한 챌린저가 해당 claim을 "소유"
상태 일관성: 블록체인 상태의 일관성 보장


## 개별참여자의 보상금 분배 시스템 구조

- 크레딧 매핑
// 일반 모드 크레딧 (정상적인 게임에서의 보상)
mapping(address => uint256) public normalModeCredit;

// 환불 모드 크레딧 (게임이 무효화된 경우 원금 환불)
mapping(address => uint256) public refundModeCredit;