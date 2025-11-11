# Proposer State Root Challenge Tests Documentation

## 📋 개요

이 문서는 Optimism의 fault proof 시스템에서 proposer가 잘못된 state root를 제출하고 challenger가 이를 감지하고 수정하는 테스트 시나리오들을 설명합니다.

## 🎯 테스트 목적

- **Proposer 검증**: Proposer가 올바른 state root를 제출하는지 확인
- **Challenger 동작**: 잘못된 state root를 감지하고 수정하는 challenger의 동작 검증
- **게임 메커니즘**: Dispute game의 정상적인 동작과 결과 검증
- **보안성**: 잘못된 state root가 최종적으로 승인되지 않음을 보장

## 🧪 주요 테스트 시나리오

### A. Solidity 단위 테스트 (Contract Level)

#### 1. Static 1v1 Dishonest Root 테스트

**파일**: `packages/contracts-bedrock/test/dispute/FaultDisputeGame.t.sol`, `SuperFaultDisputeGame.t.sol`

**목적**: 부정직한 proposer가 잘못된 L2 output을 제출하고 honest challenger가 이를 수정하는 기본 시나리오

```solidity
function test_static_1v1dishonestRoot_succeeds() public {
    // ✅ Honest L2 outputs: [1, 16] (올바른 값)
    uint256[] memory honestL2Outputs = new uint256[](16);
    for (uint256 i; i < honestL2Outputs.length; i++) {
        honestL2Outputs[i] = i + 1;
    }

    // ✅ Honest trace: bytes [0, 255] (올바른 실행 트레이스)
    bytes memory honestTrace = new bytes(256);
    for (uint256 i; i < honestTrace.length; i++) {
        honestTrace[i] = bytes1(uint8(i));
    }

    // ❌ Dishonest L2 outputs: [2, 17] (잘못된 값 - 1씩 오프셋)
    uint256[] memory dishonestL2Outputs = new uint256[](16);
    for (uint256 i; i < dishonestL2Outputs.length; i++) {
        dishonestL2Outputs[i] = i + 2;
    }

    // ❌ Dishonest trace: all zeros (잘못된 실행 트레이스)
    bytes memory dishonestTrace = new bytes(256);

    // 게임 실행 및 결과 검증
    _actorTest({
        _rootClaim: 17,
        _absolutePrestateData: 0,
        _honestTrace: honestTrace,
        _honestL2Outputs: honestL2Outputs,
        _dishonestTrace: dishonestTrace,
        _dishonestL2Outputs: dishonestL2Outputs,
        _expectedStatus: GameStatus.DEFENDER_WINS  // Honest challenger 승리
    });
}
```

**핵심 시나리오**:
- **Honest Outputs**: `[1, 2, 3, ..., 16]` (올바른 L2 블록 출력)
- **Dishonest Outputs**: `[2, 3, 4, ..., 17]` (1씩 오프셋된 잘못된 출력)
- **결과**: `GameStatus.DEFENDER_WINS` (Honest challenger가 승리)

#### 2. Genesis Absolute Prestate 테스트

```solidity
function test_static_1v1dishonestRootGenesisAbsolutePrestate_succeeds() public {
    // 동일한 패턴이지만 Genesis absolute prestate에서 시작
    // _absolutePrestateData: 0 (Genesis 상태)
}
```

#### 3. Halfway Dishonest Root 테스트

```solidity
function test_static_1v1dishonestRootHalfWay_succeeds() public {
    // ✅ Honest L2 outputs: [1, 16]
    uint256[] memory honestL2Outputs = new uint256[](16);
    for (uint256 i; i < honestL2Outputs.length; i++) {
        honestL2Outputs[i] = i + 1;
    }

    // ❌ Dishonest L2 outputs: 절반은 올바름, 절반은 잘못됨
    uint256[] memory dishonestL2Outputs = new uint256[](16);
    for (uint256 i; i < dishonestL2Outputs.length; i++) {
        dishonestL2Outputs[i] = i > 7 ? 0xFF : i + 1;  // 8번째부터 0xFF
    }
}
```

#### 4. Final Instruction 테스트

```solidity
function test_static_1v1dishonestRootFinalInstruction_succeeds() public {
    // 마지막 instruction에서만 잘못된 값 사용
    // 대부분의 trace는 올바르지만 최종 instruction에서 차이
}
```

#### 5. Fuzz 테스트

```solidity
function testFuzz_outputBisection1v1honestRoot_succeeds(
    uint256 _divergeOutput,
    uint256 _divergeStep
) public {
    // 랜덤한 지점에서 divergence 발생
    uint256 divergeAtOutput = bound(_divergeOutput, 0, 15);
    uint256 divergeAtStep = bound(_divergeStep, 0, 7);

    // 특정 지점부터 잘못된 값 사용
    uint256[] memory dishonestL2Outputs = new uint256[](16);
    for (uint256 i; i < dishonestL2Outputs.length; i++) {
        dishonestL2Outputs[i] = i >= divergeAtOutput ? 0xFF : i + 1;
    }
}
```

### B. Go E2E 테스트 (Integration Level)

#### 1. Cannon Game 테스트 (`testCannonGame`)

**파일**: `op-e2e/faultproofs/dispute_tests.go`

**목적**: 잘못된 proposal root를 challenger가 수정하는 기본 시나리오

```go
func testCannonGame(t *testing.T, ctx context.Context, arena gameArena, game *disputegame.SplitGameHelper) {
    // ✅ 잘못된 proposal root가 있는지 확인
    require.True(t, !rootIsCorrect(t, ctx, arena, game), "This test must be run with an incorrect proposal root")

    // Challenger 생성
    arena.CreateChallenger(ctx)

    // Challenger가 잘못된 output root를 counter
    claim := game.RootClaim(ctx)
    for claim.IsOutputRoot(ctx) && !claim.IsOutputRootLeaf(ctx) {
        if claim.AgreesWithOutputRoot() {
            // 올바른 challenger가 counter
            claim = claim.WaitForCounterClaim(ctx)
            claim.RequireCorrectOutputRoot(ctx)
        } else {
            // 잘못된 claim을 attack
            claim = claim.Attack(ctx, common.Hash{0xaa})
        }
    }

    // 최종적으로 challenger가 승리
    game.WaitForGameStatus(ctx, gameTypes.GameStatusChallengerWon)
}
```

**테스트 단계**:
1. 잘못된 proposal root 확인
2. Honest challenger 생성
3. Output root bisection을 통해 잘못된 claim 식별
4. Cannon trace로 이동하여 상세 검증
5. Challenger 승리 확인

### 2. Dispute Block 테스트 (`DisputeBlock`)

**파일**: `op-e2e/e2eutils/disputegame/split_game_helper.go`

**목적**: 특정 블록부터 잘못된 값 사용하여 dispute 생성

```go
func (g *SplitGameHelper) DisputeBlock(ctx context.Context, disputeBlockNum uint64) *ClaimHelper {
    dishonestValue := g.GetClaimValue(ctx, 0)
    correctRootClaim := g.correctClaimValue(ctx, types.NewPositionFromGIndex(big.NewInt(1)))
    rootIsValid := dishonestValue == correctRootClaim

    if rootIsValid {
        // ✅ 잘못된 root를 강제로 생성
        dishonestValue = common.Hash{0xff, 0xff, 0xff}
    }

    // 특정 블록부터 잘못된 값 사용
    getClaimValue := func(parentClaim *ClaimHelper, claimPos types.Position) common.Hash {
        claimBlockNum, err := g.ClaimedL2SequenceNumber(claimPos)
        if claimBlockNum < disputeBlockNum {
            // 이전 블록들은 올바른 값 사용
            return g.correctClaimValue(ctx, claimPos)
        }
        if rootIsValid == parentClaim.AgreesWithOutputRoot() {
            // ✅ 잘못된 값 사용 (dishonest)
            return dishonestValue
        } else {
            // 올바른 값 사용 (honest)
            return g.correctClaimValue(ctx, claimPos)
        }
    }
}
```

**핵심 로직**:
- **이전 블록**: 올바른 state root 사용
- **Dispute 블록부터**: 잘못된 state root 사용 (`0xff, 0xff, 0xff`)
- **게임 진행**: 특정 지점에서 honest/dishonest 행동 분기

### 3. Poisoned Post State 테스트 (`testCannonPoisonedPostState`)

**파일**: `op-e2e/faultproofs/dispute_tests.go`

**목적**: 중간에 잘못된 claim을 삽입하여 게임 복잡성 테스트

```go
func testCannonPoisonedPostState(t *testing.T, ctx context.Context, arena gameArena, game *disputegame.SplitGameHelper) {
    require.True(t, !rootIsCorrect(t, ctx, arena, game), "This test must be run with an incorrect proposal root")
    correctTrace := arena.CreateHonestActor(ctx)

    // Honest first attack at "honest" level
    claim := correctTrace.AttackClaim(ctx, game.RootClaim(ctx))

    // Honest defense at "dishonest" level
    claim = correctTrace.DefendClaim(ctx, claim)

    // ✅ Dishonest attack at "honest" level - honest move would be to ignore
    claimToIgnore1 := claim.Attack(ctx, common.Hash{0x03, 0xaa})

    // Honest attack at "dishonest" level - honest move would be to ignore
    claimToIgnore2 := correctTrace.AttackClaim(ctx, claimToIgnore1)

    // Start the honest challenger
    arena.CreateChallenger(ctx)

    // Challenger가 poisoned claim을 무시하는지 확인
    claimToIgnore1.RequireOnlyCounteredBy(ctx, claimToIgnore2)
    claimToIgnore2.RequireOnlyCounteredBy(ctx /* nothing */)
}
```

**특징**:
- **Poisoned Claims**: 의도적으로 잘못된 claim 삽입
- **Ignore Strategy**: Honest challenger가 poisoned claim을 무시
- **Game Integrity**: 게임의 무결성 유지

### 4. Root Change Claimed Root 테스트 (`testDisputeRootChangeClaimedRoot`)

**파일**: `op-e2e/faultproofs/dispute_tests.go`

**목적**: Root claim 변경 시나리오 테스트

```go
func testDisputeRootChangeClaimedRoot(t *testing.T, ctx context.Context, arena gameArena, game *disputegame.SplitGameHelper) {
    require.True(t, !rootIsCorrect(t, ctx, arena, game), "This test must be run with an incorrect proposal root")
    correctTrace := arena.CreateHonestActor(ctx)

    // Start the honest challenger
    arena.CreateChallenger(ctx)

    claim := game.RootClaim(ctx)
    // Wait for the honest challenger to counter the root
    claim = claim.WaitForCounterClaim(ctx)

    // Then attack every claim until the leaf of output root bisection
    for {
        claim = claim.Attack(ctx, common.Hash{0xbb})
        claim = claim.WaitForCounterClaim(ctx)
        if claim.Depth() == game.SplitDepth(ctx)-1 {
            // Post the correct output root as the leaf
            claim = correctTrace.AttackClaim(ctx, claim)
            // Challenger should post the first cannon trace
            claim = claim.WaitForCounterClaim(ctx)
            break
        }
    }
}
```

**핵심 동작**:
- **Root Counter**: Challenger가 잘못된 root를 즉시 counter
- **Bisection**: Output root bisection을 통해 문제 지점 식별
- **Correct Root**: 올바른 output root를 leaf에 배치

### 5. Interop Unsafe Proposal 테스트

**파일**: `op-e2e/actions/interop/proofs_test.go`

**목적**: Interop 환경에서 unsafe proposal 테스트

```go
func TestInteropFaultProofs_UnsafeProposal(gt *testing.T) {
    tests := []*transitionTest{
        {
            name:               "ProposedUnsafeBlock-NotValid",
            agreedClaim:        agreedClaim,
            disputedClaim:      disputedClaim,  // 잘못된 claim
            disputedTraceIndex: disputedTraceIndex,
            proposalTimestamp:  proposalTimestamp,
            expectValid:        false,  // ✅ 잘못된 proposal이므로 false
        },
        {
            name:               "ProposedUnsafeBlock-ShouldBeInvalid",
            agreedClaim:        agreedClaim,
            disputedClaim:      interop.InvalidTransition,  // ✅ 명시적으로 잘못된 transition
            disputedTraceIndex: disputedTraceIndex,
            proposalTimestamp:  proposalTimestamp,
            expectValid:        true,  // ✅ 잘못된 것이 맞으므로 true
        },
    }
}
```

**검증 로직**:
```go
if test.expectValid {
    require.Equal(t, test.disputedClaim, disputedClaim, "Claim is correct so should match challenger's opinion")
} else {
    require.NotEqual(t, test.disputedClaim, disputedClaim, "Claim is incorrect so should not match challenger's opinion")
}
```

## 🔧 테스트 도구 및 헬퍼

### 1. Game Arena
- **`arena.CreateChallenger(ctx)`**: Honest challenger 생성
- **`arena.CreateHonestActor(ctx)`**: Honest actor 생성
- **`arena.AdvanceTime()`**: 시간 진행

### 2. Claim Helper
- **`claim.Attack(ctx, value)`**: Claim을 attack
- **`claim.Defend(ctx, value)`**: Claim을 defend
- **`claim.WaitForCounterClaim(ctx)`**: Counter claim 대기
- **`claim.RequireCorrectOutputRoot(ctx)`**: 올바른 output root 확인

### 3. Game Status
- **`game.WaitForGameStatus(ctx, status)`**: 게임 상태 대기
- **`gameTypes.GameStatusChallengerWon`**: Challenger 승리
- **`gameTypes.GameStatusDefenderWon`**: Defender 승리

## 🎮 잘못된 State Root 생성 방법

### A. Solidity 테스트에서 사용하는 패턴

#### 1. 오프셋 패턴 (Offset Pattern)
```solidity
// ✅ Honest: [1, 2, 3, ..., 16]
uint256[] memory honestL2Outputs = new uint256[](16);
for (uint256 i; i < honestL2Outputs.length; i++) {
    honestL2Outputs[i] = i + 1;
}

// ❌ Dishonest: [2, 3, 4, ..., 17] (1씩 오프셋)
uint256[] memory dishonestL2Outputs = new uint256[](16);
for (uint256 i; i < dishonestL2Outputs.length; i++) {
    dishonestL2Outputs[i] = i + 2;
}
```

#### 2. 절반 패턴 (Halfway Pattern)
```solidity
// ❌ 절반은 올바름, 절반은 잘못됨
uint256[] memory dishonestL2Outputs = new uint256[](16);
for (uint256 i; i < dishonestL2Outputs.length; i++) {
    dishonestL2Outputs[i] = i > 7 ? 0xFF : i + 1;  // 8번째부터 0xFF
}
```

#### 3. 특정 지점 패턴 (Divergence Point Pattern)
```solidity
// ❌ 특정 지점부터 잘못된 값 사용
uint256[] memory dishonestL2Outputs = new uint256[](16);
for (uint256 i; i < dishonestL2Outputs.length; i++) {
    dishonestL2Outputs[i] = i >= divergeAtOutput ? 0xFF : i + 1;
}
```

#### 4. Trace 패턴 (Execution Trace Pattern)
```solidity
// ✅ Honest trace: bytes [0, 255]
bytes memory honestTrace = new bytes(256);
for (uint256 i; i < honestTrace.length; i++) {
    honestTrace[i] = bytes1(uint8(i));
}

// ❌ Dishonest trace: all zeros
bytes memory dishonestTrace = new bytes(256);

// ❌ Dishonest trace: all 0xFF
bytes memory dishonestTrace = new bytes(256);
for (uint256 i; i < dishonestTrace.length; i++) {
    dishonestTrace[i] = bytes1(0xFF);
}
```

### B. Go E2E 테스트에서 사용하는 패턴

#### 1. 고정된 잘못된 값
```go
dishonestValue = common.Hash{0xff, 0xff, 0xff}
```

#### 2. 특정 패턴 값
```go
claim = claim.Attack(ctx, common.Hash{0xaa})
claim = claim.Attack(ctx, common.Hash{0xbb})
claim = claim.Attack(ctx, common.Hash{0x00, 0xcc})
```

#### 3. Invalid Transition
```go
disputedClaim = interop.InvalidTransition
```

## 📊 테스트 결과 검증

### 1. 게임 규칙 검증 (`verifyGameRules`)
```go
func verifyGameRules(t *testing.T, game types.Game, rootClaimCorrect bool) {
    actualResult, claimTree, resolvedGame := gameResult(game)

    verifyExpectedGameResult(t, rootClaimCorrect, actualResult)
    verifyNoChallengerClaimsWereSuccessfullyCountered(t, resolvedGame)
    verifyChallengerAlwaysWinsParentBond(t, resolvedGame)
    verifyChallengerNeverCountersAClaimTwice(t, claimTree)
}
```

### 2. 예상 결과 검증
```go
func verifyExpectedGameResult(t *testing.T, rootClaimCorrect bool, actualResult gameTypes.GameStatus) {
    expectedResult := gameTypes.GameStatusChallengerWon
    if rootClaimCorrect {
        expectedResult = gameTypes.GameStatusDefenderWon
    }
    require.Equalf(t, expectedResult, actualResult, "Game should resolve correctly")
}
```

## 🎮 잘못된 State Root 생성 방법

### 1. 고정된 잘못된 값
```go
dishonestValue = common.Hash{0xff, 0xff, 0xff}
```

### 2. 특정 패턴 값
```go
claim = claim.Attack(ctx, common.Hash{0xaa})
claim = claim.Attack(ctx, common.Hash{0xbb})
claim = claim.Attack(ctx, common.Hash{0x00, 0xcc})
```

### 3. Invalid Transition
```go
disputedClaim = interop.InvalidTransition
```

## 🔍 테스트 실행 방법

### A. Solidity 단위 테스트 실행

#### 1. 개별 테스트 실행
```bash
# FaultDisputeGame 테스트
cd packages/contracts-bedrock
forge test --match-contract "FaultDisputeGame" --match-test "test_static_1v1dishonestRoot"

# SuperFaultDisputeGame 테스트
forge test --match-contract "SuperFaultDisputeGame" --match-test "test_static_1v1dishonestRoot"

# Fuzz 테스트
forge test --match-test "testFuzz_outputBisection1v1honestRoot"
```

#### 2. 전체 dispute 테스트
```bash
cd packages/contracts-bedrock
forge test --match-path "test/dispute/*"
```

#### 3. 특정 패턴 테스트
```bash
# 모든 dishonest root 테스트
forge test --match-test "*dishonestRoot*"

# Genesis 관련 테스트
forge test --match-test "*Genesis*"
```

### B. Go E2E 테스트 실행

#### 1. 개별 테스트 실행
```bash
# Cannon game 테스트
go test -v ./op-e2e/faultproofs -run TestCannonGame

# Interop 테스트
go test -v ./op-e2e/actions/interop -run TestInteropFaultProofs_UnsafeProposal
```

#### 2. 전체 fault proof 테스트
```bash
go test -v ./op-e2e/faultproofs
```

#### 3. 특정 시나리오 테스트
```bash
go test -v ./op-e2e/faultproofs -run "testCannon.*Incorrect"
```

## 📈 테스트 커버리지

### A. Solidity 단위 테스트 커버리지

| 테스트 시나리오 | 파일 | 커버리지 | 목적 |
|----------------|------|----------|------|
| **Static 1v1 Dishonest Root** | `FaultDisputeGame.t.sol` | ✅ | 기본적인 잘못된 root challenge |
| **Genesis Absolute Prestate** | `FaultDisputeGame.t.sol` | ✅ | Genesis 상태에서의 dispute |
| **Halfway Dishonest Root** | `FaultDisputeGame.t.sol` | ✅ | 절반 올바름, 절반 잘못됨 |
| **Final Instruction** | `FaultDisputeGame.t.sol` | ✅ | 마지막 instruction에서 차이 |
| **Fuzz Output Bisection** | `FaultDisputeGame.t.sol` | ✅ | 랜덤 지점에서 divergence |
| **Super Fault Dispute** | `SuperFaultDisputeGame.t.sol` | ✅ | Super chain 환경에서의 dispute |
| **Gas Optimization** | `FaultDisputeGame.t.sol` | ✅ | 가스 최적화 테스트 |

### B. Go E2E 테스트 커버리지

| 테스트 시나리오 | 파일 | 커버리지 | 목적 |
|----------------|------|----------|------|
| **Basic Challenge** | `dispute_tests.go` | ✅ | 기본적인 잘못된 root challenge |
| **Block-specific Dispute** | `split_game_helper.go` | ✅ | 특정 블록부터 잘못된 값 사용 |
| **Poisoned Claims** | `dispute_tests.go` | ✅ | 중간에 잘못된 claim 삽입 |
| **Root Change** | `dispute_tests.go` | ✅ | Root claim 변경 시나리오 |
| **Interop Unsafe** | `proofs_test.go` | ✅ | Interop 환경에서 unsafe proposal |
| **Multiple Rounds** | `dispute_tests.go` | ✅ | 다중 라운드 게임 |
| **Output Alphabet** | `output_alphabet_test.go` | ✅ | Alphabet 게임 타입 테스트 |

## 🚨 주의사항

### 1. 테스트 전제조건
- **잘못된 Root**: `!rootIsCorrect()` 확인 필수
- **Challenger 설정**: Honest challenger 생성 필수
- **시간 설정**: 충분한 게임 시간 확보

### 2. 테스트 안정성
- **비동기 처리**: `WaitForCounterClaim` 사용
- **타임아웃**: 적절한 타임아웃 설정
- **상태 확인**: 각 단계별 상태 검증

### 3. 디버깅
- **게임 로그**: `game.LogGameData(ctx)` 사용
- **Claim 추적**: 각 claim의 상태 모니터링
- **에러 처리**: 명확한 에러 메시지 확인

## 🎯 핵심 테스트 시나리오 요약

### Solidity vs Go 테스트 비교

| 측면 | Solidity 단위 테스트 | Go E2E 테스트 |
|------|---------------------|---------------|
| **레벨** | Contract Level | Integration Level |
| **범위** | 개별 함수/로직 | 전체 시스템 |
| **속도** | 빠름 (단위 테스트) | 느림 (통합 테스트) |
| **실제성** | 모의 데이터 | 실제 네트워크 |
| **디버깅** | 쉬움 | 복잡함 |
| **커버리지** | 세밀한 로직 | 전체 플로우 |

### 주요 Dishonest 패턴

1. **오프셋 패턴**: `[1,2,3...]` → `[2,3,4...]` (1씩 오프셋)
2. **절반 패턴**: 앞쪽은 올바름, 뒤쪽은 `0xFF`
3. **특정 지점 패턴**: 랜덤 지점부터 잘못된 값
4. **Trace 패턴**: 실행 트레이스 자체를 잘못된 값으로 설정

### 게임 결과 검증

- **`GameStatus.DEFENDER_WINS`**: Honest challenger 승리 (잘못된 proposer 패배)
- **`GameStatus.CHALLENGER_WINS`**: Challenger 승리 (올바른 proposer 승리)
- **Bond 손실**: 잘못된 proposer는 bond를 잃음
- **상태 수정**: 올바른 state root가 최종 확정

## 🔗 관련 문서

- [op-proposer 분석](./op-proposer-analysis.md)
- [DisputeGameFactory 제안 플로우](./op-proposer-dgf-proposal-flow.md)
- [RAT 배포 구현](../rat/rat-deployment-implementation.md)
- [Post-Deployment 검증 가이드](../verification/post-deployment-verification-guide-en.md)
