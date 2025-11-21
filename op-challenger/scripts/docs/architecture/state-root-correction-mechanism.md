# 스테이트루트 정정 메커니즘 (State Root Correction Mechanism)

## 개요

Optimism의 fault proof 시스템에서 **스테이트루트 정정**은 잘못된 스테이트루트를 시스템적으로 거부하고, 올바른 스테이트루트만 사용할 수 있도록 강제하는 메커니즘입니다.

## 🔄 전체 메커니즘 흐름

### 1️⃣ 정상적인 withdrawal 과정
```
프로포저가 올바른 스테이트루트 제출
    ↓
DisputeGame 생성 (valid root claim)
    ↓
챌린저들이 검증 → 문제 없음
    ↓
게임 상태: DEFENDER_WINS (또는 uncontested)
    ↓
사용자 withdrawal 시도 → ✅ 허용
```

### 2️⃣ 잘못된 스테이트루트 정정 과정
```
프로포저가 잘못된 스테이트루트 제출
    ↓
DisputeGame 생성 (invalid root claim)
    ↓
RAT이 챌린저 선택 및 bond 차감
    ↓
챌린저가 dispute game에서 증명 및 승리
    ↓
게임 상태: CHALLENGER_WINS (invalid root 확정)
    ↓
사용자가 이 게임으로 withdrawal 시도 → ❌ 거부
    ↓
새로운 올바른 스테이트루트 기반 게임 필요
```

## 🔒 핵심 보안 메커니즘

### OptimismPortal2의 검증 로직
```solidity
// Game must not have resolved in favor of the Challenger (invalid root claim).
if (_disputeGameProxy.status() == GameStatus.CHALLENGER_WINS) {
    revert OptimismPortal_InvalidDisputeGame();
}
```

**의미**:
- `CHALLENGER_WINS` = 챌린저가 이겼다 = 원래 root claim이 잘못되었다
- 잘못된 스테이트루트 기반 withdrawal은 **시스템적으로 거부**
- 올바른 스테이트루트 기반 withdrawal만 **허용**

## 🎯 "스테이트루트 정정"의 실제 의미

### ❌ 잘못된 이해
- 기존 dispute game의 root claim이 직접 수정됨
- 컨트랙트 내에서 스테이트루트 값이 변경됨

### ✅ 올바른 이해
- **시스템적 거부**: 잘못된 스테이트루트를 사용 불가능하게 만듦
- **올바른 경로 강제**: 올바른 스테이트루트로만 withdrawal 가능
- **자동 보안**: 시스템이 자동으로 올바른 상태를 강제

## 🔧 RAT과 스테이트루트 정정의 연동

### 1. RAT의 역할
- 잘못된 스테이트루트 감지
- 적절한 챌린저 선택
- Bond 메커니즘으로 참여 유도

### 2. DisputeGame의 역할
- 실제 증명 과정 진행
- 승부 결정 (`CHALLENGER_WINS` vs `DEFENDER_WINS`)
- 결과에 따른 bond 배분

### 3. OptimismPortal의 역할
- Withdrawal 시 게임 상태 검증
- 잘못된 게임 기반 withdrawal 거부
- 올바른 게임으로만 withdrawal 허용

## 📊 게임 상태별 withdrawal 처리

| 게임 상태 | 의미 | Withdrawal 가능 여부 |
|-----------|------|---------------------|
| `IN_PROGRESS` | 아직 해결 중 | ❌ 대기 필요 |
| `DEFENDER_WINS` | 프로포저가 승리 (올바른 root) | ✅ 허용 |
| `CHALLENGER_WINS` | 챌린저가 승리 (잘못된 root) | ❌ 거부 |

## 🧪 테스트 시나리오

### Phase 1: RAT 트리거
```typescript
// 1. 잘못된 스테이트루트로 게임 생성
invalidRootClaim = 0xdeadbeef
game = disputeGameFactory.StartOutputCannonGame(ctx, "sequencer", 3, invalidRootClaim)

// 2. RAT이 챌린저 선택
attentionTest = ratHelper.WaitForAttentionTest(ctx, gameAddr, 30*time.Second)
require.NotNil(attentionTest)
```

### Phase 2: 챌린저 승리
```typescript
// 3. 챌린저가 dispute game에서 승리 (시뮬레이션)
// 실제로는 bisection과 fault proof 과정을 통해 증명

// 4. 게임 해결
tx, err := ratContract.ResolveClaim(gameAuth, challengerAddr)
require.NoError(err)
```

### Phase 3: 스테이트루트 정정 확인
```typescript
// 5. 게임 상태 확인
gameStatus, err := disputeGameContract.Status(&bind.CallOpts{Context: ctx})
require.Equal(GameStatus.CHALLENGER_WINS, gameStatus)

// 6. Withdrawal 거부 확인
// 이 게임으로는 withdrawal 불가능
// OptimismPortal에서 OptimismPortal_InvalidDisputeGame 에러 발생

// 7. 올바른 스테이트루트로 새 게임 생성 필요
correctRootClaim = crypto.Keccak256Hash(correctProofLV.Bytes(), correctProofRV.Bytes())
newGame = disputeGameFactory.StartOutputCannonGame(ctx, "sequencer", 4, correctRootClaim)
// 이 게임으로는 withdrawal 가능
```

## 🔄 resolveClaim과 Bond 환불 메커니즘

### FaultDisputeGame → RAT 연동
```solidity
// FaultDisputeGame.sol
function resolveClaim(address bondRecipient) internal {
    _distributeBond(bondRecipient, subgameRootClaim);
    resolveClaimRat(bondRecipient);  // RAT 호출
}

function resolveClaimRat(address claimant) internal {
    if (rat != address(0)) {
        try IRAT(rat).resolveClaim(claimant) { } catch { }
    }
}
```

### RAT의 자동 처리
```solidity
// RAT.sol
function resolveClaim(address _claimant) external {
    address challengerAddress = attentionTests[msg.sender].challengerAddress;
    if (challengerAddress == _claimant) {
        // 자동으로 evidence 제출 처리
        attentionTest.evidenceSubmitted = true;
        // 자동으로 bond 환불
        challengerInfo.stakingAmount += bond;
    }
}
```

## 📝 요약

**스테이트루트 정정**은 다음과 같은 방식으로 작동합니다:

1. **감지**: RAT이 잘못된 스테이트루트를 감지하고 챌린저 선택
2. **증명**: 챌린저가 dispute game에서 잘못된 스테이트루트임을 증명
3. **무효화**: 해당 게임을 `CHALLENGER_WINS`로 표시하여 사용 불가능하게 만듦
4. **강제**: OptimismPortal이 해당 게임 기반 withdrawal을 거부
5. **유도**: 올바른 스테이트루트 기반 새로운 게임 생성을 유도

이를 통해 시스템은 **자동으로 올바른 스테이트루트만 사용하도록 강제**하며, 잘못된 스테이트루트는 **시스템적으로 배제**됩니다.

## 📚 관련 문서

- [RAT Testing Implementation Plan](./rat-testing-implementation-plan.md)
- [RAT Contract Documentation](../../../packages/contracts-bedrock/src/L1/RAT.sol)
- [FaultDisputeGame Documentation](../../../packages/contracts-bedrock/src/dispute/FaultDisputeGame.sol)
- [OptimismPortal2 Documentation](../../../packages/contracts-bedrock/src/L1/OptimismPortal2.sol)