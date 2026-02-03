# TON Staking V3 - Optimism Integration Documentation

TON Staking V3와 Optimism의 통합 관련 문서 모음입니다.

---

## 📚 문서 목록

### 1. RAT Integration
- **[RAT_INTEGRATION.md](./RAT_INTEGRATION.md)** - RAT and Optimism DisputeGame integration

### 2. Fast Withdrawal Integration
- **[RAT_FAST_WITHDRAWAL_INTEGRATION.md](./RAT_FAST_WITHDRAWAL_INTEGRATION.md)** ⭐
  - **Start here for Fast Withdrawal integration**
  - OptimismPortal2 modifications (with file locations)
  - RAT Contract reference
  - Deployment steps
  - Verification checklist

### 3. Archive (Reference)
- **[archive/](./archive/)** 📦
  - Portal integration details (not yet implemented)
  - RAT implementation details (already implemented)
  - Reference for future Portal integration projects

---

## 🚀 빠른 시작

### Fast Withdrawal이란?

일반 Optimism 출금은 **7일 대기** 필요 (Challenge Period)  
Fast Withdrawal은 RAT 검증자들의 BLS 서명으로 **즉시 출금** 가능

```
일반 출금: 7일 대기
Fast 출금: ~3분 (수수료 지불)
```

### 기본 흐름

```
1. 사용자 → Portal.proveAndRequestFastWithdrawal() + 수수료
   ↓
2. 검증자들 → BLS 서명 생성 (오프체인)
   ↓
3. Aggregator → RAT.verifyAndExecuteFastWithdrawal()
   ↓
4. RAT → Portal.setRATWithdrawalVerified() (검증 완료 ✅)
   ↓
5. 사용자 → Portal.fastWithdrawalFinalize() (출금 실행 💰)
```

---

## 🔑 핵심 개념

### 역할 분리

| 역할 | 책임 | 보안 이점 |
|-----|------|----------|
| **RAT** | 검증만 수행 | 자산 전송 권한 없음 |
| **Portal** | 출금 실행 | 기존 보안 메커니즘 활용 |
| **사용자** | 출금 시작 & 완료 | 명확한 의도 표현 |
| **Aggregator** | 서명 수집 | 수수료 인센티브 |

### 접근 제어

| 함수 | 호출자 | 제약 |
|-----|-------|------|
| `proveAndRequestFastWithdrawal` | 누구나 | 수수료 필요 |
| `setRATWithdrawalVerified` | RAT만 | `OptimismPortal_OnlyRAT` |
| `fastWithdrawalFinalize` | 누구나 | 검증 완료 필요 |
| `verifyAndExecuteFastWithdrawal` | 누구나 | 유효한 BLS 서명 필요 |

---

## 💰 수수료 구조

```
사용자 지불: 0.01 ETH (예시)
├─ Aggregator: 10% (0.001 ETH)
└─ 검증자들: 90% (0.009 ETH)
```

**인센티브 정렬:**
- Aggregator는 서명 수집 인센티브
- 검증자는 BLS 서명 제공 인센티브
- 사용자는 7일 → 3분 단축 이득

---

## 🌐 Custom Gas Token 지원

OptimismPortal2는 Native ETH와 Custom Gas Token 모두 지원:

| 체인 타입 | Gas Token | Fast Withdrawal 수수료 |
|----------|-----------|----------------------|
| Native ETH | ETH | 0.01 ETH |
| CGT | WTON | 10 WTON |
| CGT | USDC | 10 USDC |

**자동 감지:**
```solidity
address gasToken = systemConfig.gasPayingToken();
if (gasToken == address(0)) {
    // Native ETH 체인
} else {
    // Custom Gas Token 체인
}
```

---

## 🔒 보안 특징

### 1. 이중 출금 방지
- `finalizedWithdrawals` 매핑 사용
- 일반 출금과 Fast 출금 경로 모두 체크

### 2. 100% 합의 요구
- N-of-N 서명 필요 (전체 검증자 동의)
- 1명이라도 누락 시 일반 출금으로 fallback

### 3. BLS 서명 검증
- BLS12-381 집계 서명 사용
- Gas 효율적 검증 (~130k gas)

### 4. 인접 리프 증명
- State Root가 유효한 Trie임을 증명
- 검증자가 전체 L2 상태를 보유함을 증명

### 5. Reentrancy 방지
- `l2Sender` 변수 활용 (기존 메커니즘)
- `ifFree` modifier (RAT)

---

## ⏱️ Fallback 시나리오

### Case 1: 타임아웃 (10분)
```
검증자 응답 없음 → 일반 출금으로 자동 전환 → 7일 대기
```

### Case 2: 검증 실패
```
100% 합의 실패 → 일반 출금으로 전환 → 7일 대기
```

**결론:** Fast Withdrawal 실패 시에도 자금은 안전 (7일 대기로 복귀)

---

## 📖 Quick Start

### For Layer2 Integration
1. **Read:** [RAT_FAST_WITHDRAWAL_INTEGRATION.md](./RAT_FAST_WITHDRAWAL_INTEGRATION.md) ⭐
2. **Reference:** [RAT_INTEGRATION.md](./RAT_INTEGRATION.md) (for DisputeGame integration)
3. **Deploy:** Follow the deployment steps in RAT_FAST_WITHDRAWAL_INTEGRATION.md

### What You'll Find
- **RAT_FAST_WITHDRAWAL_INTEGRATION.md** - Complete Fast Withdrawal integration guide
- **RAT_INTEGRATION.md** - RAT and DisputeGame integration patterns
- **archive/** - Detailed reference documentation

---

## 🔧 구현 체크리스트

### OptimismPortal2

- [ ] `proveAndRequestFastWithdrawal()` 구현
- [ ] `setRATWithdrawalVerified()` 구현 (RAT only)
- [ ] `fastWithdrawalFinalize()` 구현 (Public)
- [ ] `ratVerifiedWithdrawals` 매핑 추가
- [ ] `ratContract` 스토리지 추가
- [ ] `fastWithdrawalResponsePeriod` 스토리지 추가
- [ ] Custom Gas Token 지원
- [ ] 이벤트 추가 (4개): `FastWithdrawalRequested`, `RATWithdrawalVerified`, `FastWithdrawalFinalized`, `RATContractUpdated`
- [ ] 에러 추가 (2개): `OptimismPortal_NotVerifiedByRAT`, `OptimismPortal_OnlyRAT`
- [ ] 기존 `finalizedWithdrawals` 재사용 (추가 매핑 불필요)

### RAT Contract

- [ ] `verifyAndExecuteFastWithdrawal()` 구현
- [ ] BLS 서명 검증 로직
- [ ] 인접 리프 증명 검증
- [ ] `setOptimismPortal()` 관리자 함수
- [ ] `processedWithdrawals` 재실행 방지
- [ ] 수수료 분배 로직
- [ ] 100% 합의 체크
- [ ] 이벤트 추가 (4개)
- [ ] 에러 추가 (8개)

### 라이브러리

- [ ] BLS12381.sol - BLS 서명 검증
- [ ] AdjacentLeavesVerifier.sol - 인접 리프 증명 검증
- [ ] RATFastWithdrawalLib.sol - Fast Withdrawal 로직

---

## 📝 업데이트 이력

- **2026-02-03**: 최초 작성
  - Fast Withdrawal 전체 문서화
  - 접근 제어 명확화 (사용자가 finalize 호출)
  - Custom Gas Token 지원 추가

---

## 🤝 기여

문서 개선 제안이나 버그 발견 시:
1. 이슈 생성
2. PR 제출
3. 문서 업데이트

---

*Last Updated: 2026-02-03*
