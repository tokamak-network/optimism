# RAT (Randomized Attention Test) Testing Scenarios

## 📋 개요

이 문서는 RAT(Randomized Attention Test) 컨트랙트에 대한 포괄적인 테스트 시나리오를 정의합니다. RAT는 challenger의 활성도와 정확성을 검증하는 핵심 보안 메커니즘으로, 경제적 인센티브를 통해 시스템의 무결성을 보장합니다.

## 🎯 RAT 컨트랙트 개요

RAT는 challenger 모니터링 및 검증을 위한 경제적 보안 메커니즘으로, 다음과 같은 핵심 기능을 제공합니다:

- **Challenger Staking**: Challenger들이 최소 요구 금액 이상을 stake하여 시스템 참여
- **Randomized Selection**: 확률적으로 challenger를 선택하여 attention test 실시
- **Economic Constraints**: Bond 차감을 통한 경제적 자격 요건 적용
- **Evidence Verification**: 암호학적 증거 검증 및 올바른 제출 시 bond 복원
- **Automatic Validation**: Stake 수준에 따른 challenger 자격 자동 관리

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

## 🧬 핵심 경제적 메커니즘

### 💰 Stake 및 Bond 관리
- **Minimum Staking Balance**: Challenger가 유효하려면 최소 stake 유지 필요
- **Per-Test Bond Amount**: 각 attention test마다 stake에서 bond 차감
- **Dynamic Validation**: Stake이 minimum 미만이 되면 자동으로 invalid 처리
- **Bond Restoration**: 올바른 증거 제출 시 해당 test의 bond만 복원

### 🎲 확률적 선택 메커니즘
- **Trigger Probability**: 설정 가능한 확률로 attention test 활성화
- **Random Selection**: 유효한 challenger 중 랜덤 선택 (더미 제외)
- **Multiple Selection**: 동일 challenger가 여러 test에 동시 참여 가능
- **Availability**: 경제적 자격 요건을 만족하는 challenger만 선택 가능

## 🚀 구현된 테스트 시나리오

### B. Go 통합 테스트 (✅ 구현됨)

#### 1. RAT-Challenger 기본 통합 테스트 (`TestRATChallengerIntegration`)

**목적**: RAT 컨트랙트의 핵심 워크플로우 검증

**시나리오**:
1. **RAT 배포**: Proxy 패턴으로 배포 및 초기화
2. **Challenger Staking**: 2.5 ETH stake (minimum 2 ETH 이상)
3. **Attention Test 트리거**: 잘못된 state root로 첫 번째 테스트
4. **Bond 차감 검증**: 1 ETH bond 차감으로 1.5 ETH 잔여
5. **올바른 증거 제출**: 두 번째 테스트에서 정확한 증거 제출
6. **Bond 복원 확인**: 해당 테스트 bond만 복원

**핵심 학습**:
- 각 attention test는 독립적으로 bond 관리
- 여러 test에 동시 참여 가능하지만 각각 bond 차감
- 올바른 암호학적 증거 검증: `keccak256(abi.encodePacked(proofLV, proofRV))`

#### 2. 다중 Challenger 테스트 (`TestRATMultipleChallengers`)

**목적**: 여러 challenger 환경에서의 선택 및 격리 메커니즘 검증

**시나리오**:
1. **4명의 Challenger 생성**: 각각 2.5 ETH stake
2. **랜덤 선택 검증**: attention test에서 1명만 선택됨을 확인
3. **격리 확인**: 선택되지 않은 challenger들은 영향 없음
4. **Bond 차감 검증**: 선택된 challenger만 bond 차감

**핵심 학습**:
- 공정한 랜덤 선택 메커니즘
- Challenger 간 경제적 격리
- 시스템의 확장성 검증

#### 3. 확률적 트리거 테스트 (`TestRATTriggerProbability`)

**목적**: RAT trigger 확률 메커니즘과 경제적 제약사항 검증

**시나리오**:
1. **10% 확률 테스트**: 30회 시도로 통계적 검증
2. **100% 확률 테스트**: 모든 가능한 선택 검증
3. **경제적 고갈**: Stake 부족으로 선택 불가능한 상황
4. **0% 확률 테스트**: 완전히 비활성화된 상태

**핵심 학습**:
- 확률적 메커니즘의 정확성
- 경제적 자격 요건의 중요성
- Challenger가 multiple test로 인한 stake 고갈 현상

#### 4. 잘못된 증거 제출 테스트 (`TestRATIncorrectEvidenceSubmission`) ✅ 구현됨

**목적**: 잘못된 증거 제출 시 RAT 계약의 거부 메커니즘 검증

**시나리오**:
1. **Challenger Staking**: 3 ETH stake으로 충분한 여유 확보
2. **Attention Test 생성**: 올바른 state root로 테스트 트리거
3. **잘못된 증거 제출**: 의도적으로 부정확한 proof 값 제출
4. **거부 확인**: `execution reverted` 오류로 거부됨 검증
5. **상태 불변성**: Challenger 상태가 변경되지 않음 확인
6. **올바른 증거로 복구**: 정상적인 증거 제출로 시스템 작동 확인

**핵심 학습**:
- RAT 계약의 암호학적 검증 정확성
- 잘못된 증거 제출 시 penalty 없이 단순 거부
- 시스템의 보안성과 복구 가능성

## 🔄 제안하는 추가 테스트 시나리오

### C. 실제 Challenge 성공 시나리오 (🚧 구현 필요)

#### 1. 잘못된 State Root Challenge 성공 테스트
**목적**: 실제 dispute game에서 잘못된 state root를 발견하고 challenge해서 bond를 회수하는 완전한 워크플로우 검증

**시나리오**:
```go
func TestRATSuccessfulChallenge(t *testing.T) {
    // 1. Challenger가 RAT에 충분한 stake (5 ETH)
    challenger.StakeToRAT(5 ETH)

    // 2. 악의적/잘못된 proposer가 잘못된 state root로 dispute game 생성
    maliciousGame := createDisputeGameWithIncorrectStateRoot(t, "incorrect_root_123")

    // 3. DisputeGameFactory가 RAT attention test 자동 트리거
    // 4. RAT가 challenger를 선택하고 bond 차감 (1 ETH)
    // 5. Challenger가 올바른 증거로 잘못된 state root 반박

    correctProofLV := generateCorrectLeftValue(t, maliciousGame)
    correctProofRV := generateCorrectRightValue(t, maliciousGame)

    // 6. RAT에 증거 제출
    challenger.SubmitCorrectEvidence(maliciousGame.Address(), correctProofLV, correctProofRV)

    // 7. Challenge 성공으로 bond 복원 + 추가 보상 확인
    finalBalance := challenger.GetStakingAmount()
    expectedBalance := initialBalance + challengeReward  // Bond 복원 + 보상
    require.Equal(t, expectedBalance, finalBalance)

    // 8. 잘못된 proposer 처벌 확인
    assertProposerSlashed(t, maliciousGame.Proposer())
}
```

**핵심 학습**:
- 실제 state root 검증 메커니즘
- Challenge 성공 시 경제적 인센티브 구조
- 악의적 행동에 대한 처벌 시스템

#### 2. 여러 Challenger 경쟁 시나리오 테스트
**목적**: 동일한 잘못된 state root에 대해 여러 challenger가 경쟁하는 상황

**시나리오**:
```go
func TestRATMultipleChallengerCompetition(t *testing.T) {
    // 1. 3명의 challenger 각각 3 ETH stake
    // 2. 잘못된 dispute game 생성
    // 3. RAT가 1명만 선택하지만, 다른 challenger들도 독립적으로 challenge 가능한지 확인
    // 4. 첫 번째 성공한 challenger만 보상 받는지 확인
    // 5. 나머지 challenger들의 bond 처리 방식 확인
}
```

### D. 경제적 Edge Cases 테스트 (🚧 구현 필요)

#### 3. Stake 고갈 시나리오 테스트
**목적**: 경제적 제약으로 인한 시스템 동작 검증

**시나리오**:
```go
func TestRATStakeDepletion(t *testing.T) {
    // 1. 최소 stake로 challenger 등록 (2 ETH)
    // 2. 연속적인 attention test로 stake 고갈
    // 3. Invalid 상태 전환 확인
    // 4. 추가 staking으로 복구 검증
}
```

#### 2. 동시다발적 Attention Test 테스트
**목적**: 높은 부하 상황에서의 bond 관리 검증

**시나리오**:
```go
func TestRATConcurrentAttentionTests(t *testing.T) {
    // 1. 10개의 simultaneous dispute games 생성
    // 2. 동일 challenger가 여러 test에 선택됨
    // 3. 각 test의 독립적 bond 관리 확인
    // 4. 부분적 evidence 제출 시나리오
}
```

#### 3. Bond Amount Edge Cases 테스트
**목적**: 다양한 bond 크기에서의 시스템 동작 검증

**시나리오**:
```go
func TestRATBondAmountVariations(t *testing.T) {
    // 1. Per-test bond > stake 인 경우
    // 2. Stake == minimum balance 정확히 일치하는 경우
    // 3. 극소량 stake으로 한계 테스트
}
```

### D. 시간 기반 테스트 (🚧 구현 필요)

#### 4. Evidence Submission Period 테스트
**목적**: 시간 제한과 관련된 메커니즘 검증

**시나리오**:
```go
func TestRATEvidenceSubmissionTimeout(t *testing.T) {
    // 1. Evidence submission period 내 제출
    // 2. Period 초과 시 bond 손실 확인
    // 3. 기간 경과 후 새로운 test 가능성 검증
}
```

#### 5. 블록 진행과 함께하는 장기 테스트
**목적**: 블록체인 진행에 따른 시스템 안정성 검증

### E. 악의적 행동 테스트 (🚧 구현 필요)

#### 6. 잘못된 Evidence 제출 테스트
**목적**: 부정확한 증거 제출에 대한 처벌 메커니즘 검증

**시나리오**:
```go
func TestRATIncorrectEvidenceSubmission(t *testing.T) {
    // 1. 의도적으로 잘못된 proof 제출
    // 2. Bond 손실 확인
    // 3. Challenger 자격 박탈 검증
}
```

#### 7. Replay Attack 방어 테스트
**목적**: 동일한 evidence의 중복 사용 방지 검증

#### 8. Front-running 방어 테스트
**목적**: MEV 공격에 대한 시스템 보안성 검증

### F. 성능 및 가스 최적화 테스트 (🚧 구현 필요)

#### 9. 가스 소모량 분석 테스트
**목적**: 각 기능별 가스 효율성 측정 및 최적화 지점 식별

#### 10. 대규모 Challenger Pool 테스트
**목적**: 100+ challenger 환경에서의 선택 성능 검증

## 📊 테스트 우선순위

### 🔥 High Priority (즉시 구현 필요)
1. **잘못된 State Root Challenge 성공 테스트** - 핵심 비즈니스 로직 검증
2. **잘못된 Evidence 제출 테스트** - 보안 메커니즘 검증
3. **Stake 고갈 시나리오 테스트** - 경제적 안전성 핵심

### 🔸 Medium Priority (단기 구현)
4. **동시다발적 Attention Test 테스트** - 시스템 부하 검증
5. **Bond Amount Edge Cases 테스트** - 경계값 안정성
6. **Replay Attack 방어 테스트** - 보안 강화

### 🔹 Low Priority (중장기 구현)
7. **Front-running 방어 테스트** - MEV 보안
8. **가스 최적화 테스트** - 효율성 개선
9. **대규모 Pool 테스트** - 확장성 검증

## 🚀 실행 가이드

### 기존 테스트 실행
```bash
# 모든 RAT 통합 테스트 실행 (4개 테스트)
go test ./op-challenger/game/fault -run "TestRAT.*" -v

# 개별 테스트 실행 (모두 실제 계약 검증)
go test ./op-challenger/game/fault -run TestRATChallengerIntegration -v
go test ./op-challenger/game/fault -run TestRATMultipleChallengers -v
go test ./op-challenger/game/fault -run TestRATTriggerProbability -v
go test ./op-challenger/game/fault -run TestRATIncorrectEvidenceSubmission -v
```

### 테스트 실행 결과 예시
```
=== RUN   TestRATChallengerIntegration
    === RAT-Challenger Integration Test PASSED ===
=== RUN   TestRATMultipleChallengers
    === RAT Multiple Challengers Test PASSED ===
=== RUN   TestRATTriggerProbability
    === RAT Trigger Probability Test PASSED ===
=== RUN   TestRATIncorrectEvidenceSubmission
    === RAT Incorrect Evidence Submission Test PASSED ===
PASS
ok  	github.com/ethereum-optimism/optimism/op-challenger/game/fault	~0.5s
```

### 새로운 테스트 구현 가이드
1. **테스트 파일 생성**: `op-challenger/game/fault/rat_edge_cases_test.go`
2. **Helper 함수 활용**: `test/rat_helpers.go`의 기존 환경 설정
3. **Proxy 패턴 사용**: 실제 계약 배포 및 초기화
4. **경제적 제약 고려**: Minimum stake, bond amount 등 현실적 값 사용

## 📚 참고 자료

- **RAT Solidity Contract**: `packages/contracts-bedrock/src/L1/RAT.sol`
- **RAT Interface**: `packages/contracts-bedrock/interfaces/L1/IRAT.sol`
- **기존 Go Bindings**: `op-challenger/game/fault/contracts/rat.go`
- **Test Helpers**: `op-challenger/game/fault/test/rat_helpers.go`
