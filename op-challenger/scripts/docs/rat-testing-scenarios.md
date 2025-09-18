# RAT (Refund Address Tracker) Testing Scenarios

## 📋 개요

이 문서는 RAT(Refund Address Tracker) 컨트랙트에 대한 다양한 테스트 시나리오를 제안합니다. 현재 Solidity 단위 테스트는 구현되어 있지만, 추가적인 테스트 레벨들을 통해 더 포괄적인 검증을 할 수 있습니다.

## 🎯 RAT 컨트랙트 개요

RAT는 challenger 모니터링 및 테스트를 위한 컨트랙트로, 다음과 같은 주요 기능을 제공합니다:

- **Challenger Staking**: Challenger들이 stake를 걸고 참여
- **Attention Test Triggering**: DisputeGameFactory에서 attention test 트리거
- **Evidence Submission**: Challenger들이 올바른 증거 제출
- **Bond Refunding**: 성공적인 증거 제출 시 bond 반환

## 🧪 현재 구현된 테스트

### A. Solidity 단위 테스트 (✅ 구현됨)

**파일**: `packages/contracts-bedrock/test/L1/RAT.t.sol`

**현재 커버리지**:
- ✅ 초기화 테스트 (`RAT_Initialize_Test`)
- ✅ Staking 기능 테스트 (`RAT_Staking_Test`)
- ✅ Attention Test 트리거 테스트 (`RAT_Attention_Test`)
- ✅ Evidence 제출 테스트 (`RAT_Evidence_Test`)
- ✅ Bond 반환 테스트 (`RAT_Refund_Test`)
- ✅ Admin 기능 테스트 (`RAT_Admin_Test`)

## 🚀 제안하는 새로운 테스트 시나리오

### B. Go 통합 테스트 (Integration Tests)

#### 1. RAT-Challenger 통합 테스트

**목적**: RAT 컨트랙트와 op-challenger 서비스 간의 통합 동작 검증

```go
// op-challenger/game/fault/rat_integration_test.go
func TestRATChallengerIntegration(t *testing.T) {
    // 1. RAT 컨트랙트 배포 및 초기화
    ratContract := deployRATContract(t)

    // 2. Challenger 서비스 시작
    challenger := startChallengerService(t, ratContract.Address())

    // 3. Challenger가 RAT에 stake
    challenger.StakeToRAT(2.5 ether)

    // 4. Dispute game 생성 (잘못된 state root)
    game := createDisputeGameWithIncorrectRoot(t)

    // 5. RAT attention test 트리거
    ratContract.TriggerAttentionTest(game.Address(), incorrectStateRoot, blockHash)

    // 6. Challenger가 자동으로 evidence 제출하는지 확인
    waitForEvidenceSubmission(t, challenger, game.Address())

    // 7. Bond 반환 확인
    assertBondRefunded(t, challenger, expectedRefundAmount)
}
```

#### 2. RAT-Multiple Challengers 테스트

**목적**: 여러 challenger가 동시에 RAT에 참여하는 시나리오

```go
func TestRATMultipleChallengers(t *testing.T) {
    // 1. 여러 challenger 생성
    challengers := []*Challenger{
        createChallenger(t, "challenger1"),
        createChallenger(t, "challenger2"),
        createChallenger(t, "challenger3"),
    }

    // 2. 모든 challenger가 RAT에 stake
    for _, challenger := range challengers {
        challenger.StakeToRAT(2.5 ether)
    }

    // 3. Dispute game 생성
    game := createDisputeGameWithIncorrectRoot(t)

    // 4. RAT attention test 트리거
    ratContract.TriggerAttentionTest(game.Address(), incorrectStateRoot, blockHash)

    // 5. 선택된 challenger만 evidence 제출하는지 확인
    selectedChallenger := getSelectedChallenger(t, ratContract, game.Address())

    // 6. 다른 challenger들은 evidence 제출하지 않는지 확인
    for _, challenger := range challengers {
        if challenger.Address() != selectedChallenger.Address() {
            assertNoEvidenceSubmission(t, challenger, game.Address())
        }
    }
}
```

#### 3. RAT-Probability 테스트

**목적**: RAT trigger probability 설정에 따른 동작 검증

```go
func TestRATTriggerProbability(t *testing.T) {
    // 1. 낮은 probability로 RAT 설정 (10%)
    ratContract := deployRATContract(t, 10000) // 10% probability

    // 2. 여러 dispute game 생성
    games := make([]*DisputeGame, 10)
    for i := 0; i < 10; i++ {
        games[i] = createDisputeGameWithIncorrectRoot(t)
    }

    // 3. 모든 game에 대해 attention test 트리거 시도
    triggeredCount := 0
    for _, game := range games {
        if ratContract.TriggerAttentionTest(game.Address(), incorrectStateRoot, blockHash) {
            triggeredCount++
        }
    }

    // 4. 약 10% 정도만 트리거되는지 확인 (통계적 검증)
    assertProbabilityWithinRange(t, triggeredCount, 10, 0.1, 0.2) // 10-20% 범위
}
```

### C. E2E 테스트 (End-to-End Tests)

#### 1. RAT-Full Workflow E2E 테스트

**목적**: RAT를 포함한 전체 fault proof 워크플로우 검증

```go
// op-e2e/faultproofs/rat_e2e_test.go
func TestRATFullWorkflowE2E(t *testing.T) {
    // 1. Devnet 배포 (RAT 포함)
    sys := deployDevnetWithRAT(t)

    // 2. Challenger 서비스 시작
    challenger := startChallengerWithRAT(t, sys)

    // 3. Proposer가 잘못된 state root 제출
    proposer := sys.Proposer
    proposer.SubmitIncorrectStateRoot(t, incorrectRoot)

    // 4. Dispute game 자동 생성 확인
    game := waitForDisputeGameCreation(t, sys)

    // 5. RAT attention test 자동 트리거 확인
    waitForRATAttentionTest(t, sys.RATContract, game.Address())

    // 6. Challenger가 자동으로 evidence 제출하는지 확인
    waitForEvidenceSubmission(t, challenger, game.Address())

    // 7. Game resolution 및 bond 반환 확인
    waitForGameResolution(t, game, GameStatusChallengerWon)
    assertBondRefunded(t, challenger, expectedRefundAmount)
}
```

#### 2. RAT-Stress 테스트

**목적**: RAT 시스템의 부하 및 성능 검증

```go
func TestRATStressTest(t *testing.T) {
    // 1. 대량의 challenger 생성
    challengers := createMultipleChallengers(t, 100)

    // 2. 모든 challenger가 RAT에 stake
    for _, challenger := range challengers {
        challenger.StakeToRAT(2.5 ether)
    }

    // 3. 동시에 여러 dispute game 생성
    games := createMultipleDisputeGames(t, 50)

    // 4. 모든 game에 대해 attention test 트리거
    for _, game := range games {
        go func(g *DisputeGame) {
            ratContract.TriggerAttentionTest(g.Address(), incorrectStateRoot, blockHash)
        }(game)
    }

    // 5. 시스템이 안정적으로 동작하는지 확인
    waitForAllGamesResolved(t, games)
    assertAllBondsRefunded(t, challengers)
}
```

### D. 성능 테스트 (Performance Tests)

#### 1. RAT-Gas Optimization 테스트

**목적**: RAT 컨트랙트의 가스 사용량 최적화 검증

```go
func TestRATGasOptimization(t *testing.T) {
    // 1. 기본 RAT 배포
    ratContract := deployRATContract(t)

    // 2. 각 함수의 가스 사용량 측정
    gasTests := []struct {
        name string
        test func() error
    }{
        {"stake", func() error { return ratContract.Stake(2.5 ether) }},
        {"triggerAttentionTest", func() error { return ratContract.TriggerAttentionTest(gameAddr, stateRoot, blockHash) }},
        {"submitCorrectEvidence", func() error { return ratContract.SubmitCorrectEvidence(gameAddr, proofLV, proofRV) }},
    }

    // 3. 가스 사용량 검증
    for _, test := range gasTests {
        gasUsed := measureGasUsage(t, test.test)
        assertGasUsageWithinLimit(t, test.name, gasUsed, expectedGasLimit)
    }
}
```

#### 2. RAT-Scalability 테스트

**목적**: RAT 시스템의 확장성 검증

```go
func TestRATScalability(t *testing.T) {
    // 1. 다양한 challenger 수로 테스트
    challengerCounts := []int{10, 50, 100, 500}

    for _, count := range challengerCounts {
        t.Run(fmt.Sprintf("challengers_%d", count), func(t *testing.T) {
            // 2. 지정된 수의 challenger 생성
            challengers := createMultipleChallengers(t, count)

            // 3. 모든 challenger가 stake
            for _, challenger := range challengers {
                challenger.StakeToRAT(2.5 ether)
            }

            // 4. 성능 측정
            start := time.Now()

            // 5. Dispute game 생성 및 처리
            game := createDisputeGameWithIncorrectRoot(t)
            ratContract.TriggerAttentionTest(game.Address(), incorrectStateRoot, blockHash)
            waitForEvidenceSubmission(t, challengers[0], game.Address())

            // 6. 처리 시간 검증
            duration := time.Since(start)
            assertProcessingTimeWithinLimit(t, count, duration, expectedTimeLimit)
        })
    }
}
```

### E. 보안 테스트 (Security Tests)

#### 1. RAT-Access Control 테스트

**목적**: RAT 컨트랙트의 접근 제어 검증

```go
func TestRATAccessControl(t *testing.T) {
    // 1. RAT 컨트랙트 배포
    ratContract := deployRATContract(t)

    // 2. 권한이 없는 사용자로 함수 호출 시도
    unauthorizedUser := createAccount(t)

    // 3. 각 함수에 대한 접근 제어 테스트
    accessTests := []struct {
        name string
        test func() error
    }{
        {"triggerAttentionTest", func() error { return ratContract.TriggerAttentionTest(gameAddr, stateRoot, blockHash) }},
        {"setPerTestBondAmount", func() error { return ratContract.SetPerTestBondAmount(1 ether) }},
        {"setEvidenceSubmissionPeriod", func() error { return ratContract.SetEvidenceSubmissionPeriod(3600) }},
    }

    for _, test := range accessTests {
        t.Run(test.name, func(t *testing.T) {
            // 4. 권한이 없는 사용자로 호출 시 revert 확인
            err := test.test()
            assertRevertWithMessage(t, err, "AccessControl: account")
        })
    }
}
```

#### 2. RAT-Reentrancy 테스트

**목적**: RAT 컨트랙트의 재진입 공격 방어 검증

```go
func TestRATReentrancyProtection(t *testing.T) {
    // 1. 재진입 공격을 시도하는 악성 컨트랙트 배포
    maliciousContract := deployMaliciousContract(t)

    // 2. RAT 컨트랙트 배포
    ratContract := deployRATContract(t)

    // 3. 악성 컨트랙트가 RAT에 stake
    maliciousContract.StakeToRAT(2.5 ether)

    // 4. 재진입 공격 시도
    err := maliciousContract.AttemptReentrancyAttack(ratContract.Address())

    // 5. 공격이 실패하는지 확인
    assertRevertWithMessage(t, err, "ReentrancyGuard: reentrant call")
}
```

### F. 모니터링 테스트 (Monitoring Tests)

#### 1. RAT-Metrics 테스트

**목적**: RAT 관련 메트릭스 수집 및 모니터링 검증

```go
func TestRATMetrics(t *testing.T) {
    // 1. 메트릭스 서버 시작
    metricsServer := startMetricsServer(t)

    // 2. RAT 컨트랙트 배포
    ratContract := deployRATContract(t)

    // 3. Challenger stake
    challenger := createChallenger(t)
    challenger.StakeToRAT(2.5 ether)

    // 4. 메트릭스 확인
    metrics := getRATMetrics(t, metricsServer)
    assertMetricValue(t, "rat_challenger_count", metrics.ChallengerCount, 1)
    assertMetricValue(t, "rat_total_staked", metrics.TotalStaked, 2.5 ether)

    // 5. Attention test 트리거 후 메트릭스 업데이트 확인
    game := createDisputeGameWithIncorrectRoot(t)
    ratContract.TriggerAttentionTest(game.Address(), incorrectStateRoot, blockHash)

    updatedMetrics := getRATMetrics(t, metricsServer)
    assertMetricValue(t, "rat_attention_tests_triggered", updatedMetrics.AttentionTestsTriggered, 1)
}
```

## 🔧 테스트 구현 가이드

### 1. 테스트 환경 설정

```go
// test_setup.go
type RATTestEnvironment struct {
    L1Client     *ethclient.Client
    L2Client     *ethclient.Client
    RATContract  *RATContract
    Challenger   *ChallengerService
    Proposer     *ProposerService
    GameFactory  *DisputeGameFactory
}

func setupRATTestEnvironment(t *testing.T) *RATTestEnvironment {
    // 1. L1/L2 네트워크 설정
    l1Client := setupL1Network(t)
    l2Client := setupL2Network(t)

    // 2. RAT 컨트랙트 배포
    ratContract := deployRATContract(t, l1Client)

    // 3. Challenger 서비스 시작
    challenger := startChallengerService(t, ratContract.Address())

    // 4. Proposer 서비스 시작
    proposer := startProposerService(t)

    return &RATTestEnvironment{
        L1Client:    l1Client,
        L2Client:    l2Client,
        RATContract: ratContract,
        Challenger:  challenger,
        Proposer:    proposer,
    }
}
```

### 2. 테스트 헬퍼 함수

```go
// test_helpers.go
func createDisputeGameWithIncorrectRoot(t *testing.T, env *RATTestEnvironment) *DisputeGame {
    // 1. 잘못된 state root 생성
    incorrectRoot := generateIncorrectStateRoot(t)

    // 2. Proposer가 잘못된 root 제출
    env.Proposer.SubmitStateRoot(t, incorrectRoot)

    // 3. Dispute game 생성 대기
    game := waitForDisputeGameCreation(t, env.GameFactory)

    return game
}

func waitForEvidenceSubmission(t *testing.T, challenger *ChallengerService, gameAddr common.Address) {
    // 1. Evidence 제출 대기
    timeout := time.After(30 * time.Second)
    ticker := time.NewTicker(1 * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-timeout:
            t.Fatal("Timeout waiting for evidence submission")
        case <-ticker.C:
            if challenger.HasSubmittedEvidence(gameAddr) {
                return
            }
        }
    }
}
```

## 📊 테스트 실행 방법

### 1. Go 통합 테스트 실행

```bash
# RAT 통합 테스트 실행
cd op-challenger
go test -v ./game/fault -run "TestRAT.*"

# 특정 테스트 실행
go test -v ./game/fault -run "TestRATChallengerIntegration"
```

### 2. E2E 테스트 실행

```bash
# RAT E2E 테스트 실행
cd op-e2e
go test -v ./faultproofs -run "TestRAT.*"

# 전체 RAT 워크플로우 테스트
go test -v ./faultproofs -run "TestRATFullWorkflowE2E"
```

### 3. 성능 테스트 실행

```bash
# RAT 성능 테스트 실행
go test -v ./game/fault -run "TestRAT.*Performance" -bench=.

# 가스 최적화 테스트
go test -v ./game/fault -run "TestRATGasOptimization"
```

## 🎯 테스트 우선순위

### Phase 1: 핵심 기능 테스트
1. **RAT-Challenger 통합 테스트** - 기본 워크플로우 검증
2. **RAT-Multiple Challengers 테스트** - 다중 challenger 시나리오
3. **RAT-Full Workflow E2E 테스트** - 전체 시스템 통합

### Phase 2: 고급 기능 테스트
4. **RAT-Probability 테스트** - 확률적 트리거 검증
5. **RAT-Stress 테스트** - 부하 및 성능 검증
6. **RAT-Scalability 테스트** - 확장성 검증

### Phase 3: 보안 및 모니터링 테스트
7. **RAT-Access Control 테스트** - 접근 제어 검증
8. **RAT-Reentrancy 테스트** - 보안 검증
9. **RAT-Metrics 테스트** - 모니터링 검증

## 🔗 관련 문서

- [Proposer State Root Challenge Tests](./proposer-state-root-challenge-tests.md) - 기본 fault proof 테스트
- [RAT 배포 구현](./rat-deployment-implementation.md) - RAT 컨트랙트 배포 가이드
- [Post-Deployment 검증 가이드](./post-deployment-verification-guide-en.md) - 배포 후 검증
