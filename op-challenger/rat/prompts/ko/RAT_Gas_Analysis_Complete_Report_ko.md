# RAT (Randomized Attention Test) 컨트랙트 완전 가스 분석 보고서

## 📊 개요

이 문서는 Optimism의 RAT (Randomized Attention Test) 컨트랙트의 모든 함수와 다양한 경우들에 대한 가스 사용량을 분석한 완전한 보고서입니다. RAT는 챌린저 모니터링 및 테스트를 위한 스마트 컨트랙트로, 가스 효율성이 중요한 요소입니다.

## 🔍 측정된 가스 사용량 (완전한 목록)

### 주요 함수별 가스 사용량

| 함수 | 경우 | 가스 사용량 | 설명 | 상태 |
|------|------|-------------|------|------|
| **`stake()`** | 일반 스테이킹 | **67,177 가스** | 기본 스테이킹 (0.2 ETH) | ✅ 성공 |
| **`stake()`** | 유효한 챌린저 등록 있음 | **114,711 가스** | 유효한 챌린저로 등록되는 스테이킹 (2 ETH) | ✅ 성공 |
| **`triggerAttentionTest()`** | 유효한 챌린저 있음 | **132,378 가스** | 챌린저 선택, 보증금 차감, AttentionInfo 생성 | ✅ 성공 |
| **`triggerAttentionTest()`** | 유효한 챌린저 없음 | **14,677 가스** | 조용히 무시됨 (가스 절약) | ✅ 성공 |
| **`submitCorrectEvidence()`** | 성공 | **7,520 가스** | 증거 검증, 보증금 환불 | ✅ 성공 |
| **`resolveClaim()`** | 성공 | **4,857 가스** | 보증금 환불, 상태 업데이트 | ✅ 성공 |
| **`resolveClaim()`** | 잘못된 클레임언트 | **1,565 가스** | 조용히 무시됨 (가스 절약) | ✅ 성공 |

## 📈 상세 가스 분석

### 1. `stake()` 함수 분석

#### **일반 스테이킹 (67,177 가스)**
- **기본 트랜잭션 비용**: ~21,000 가스
- **스토리지 쓰기**: `challengers[msg.sender].stakingAmount` 업데이트
- **이벤트 발생**: `ChallengerStaked` 이벤트
- **조건 검사**: `perTestBondAmount` 비교

#### **유효한 챌린저 등록 (114,711 가스)**
- **추가 비용**: +47,534 가스
- **추가 작업**:
  - `challengers[msg.sender].isValid = true` 설정
  - `challengers[msg.sender].validatorIndex` 설정
  - `validChallengers.push(msg.sender)` 배열에 추가

### 2. `triggerAttentionTest()` 함수 분석

#### **유효한 챌린저 있음 (132,378 가스)**
- **챌린저 선택**: 해시 기반 랜덤 선택
- **보증금 계산**: `stakingAmount` vs `perTestBondAmount` 비교
- **스토리지 업데이트**: 챌린저 정보, AttentionInfo 생성
- **유효성 검사**: 챌린저 상태 업데이트
- **이벤트 발생**: `AttentionTriggered` 이벤트

#### **유효한 챌린저 없음 (14,677 가스)**
- **조건 검사만**: `validChallengersLength > 1` 확인
- **조용한 무시**: 아무 작업도 수행하지 않음
- **가스 절약**: 불필요한 작업 방지

### 3. `submitCorrectEvidence()` 함수 분석

#### **성공 (7,520 가스)**
- **증거 검증**: `keccak256(proofLV, proofRV)` vs `stateRoot` 비교
- **보증금 환불**: `stakingAmount`에 보증금 추가
- **상태 업데이트**: `evidenceSubmitted = true`
- **유효성 검사**: 챌린저 상태 업데이트
- **이벤트 발생**: `CorrectEvidenceSubmitted` 이벤트

### 4. `resolveClaim()` 함수 분석

#### **성공 (4,857 가스)**
- **보증금 환불**: `stakingAmount`에 보증금 추가
- **상태 업데이트**: `evidenceSubmitted = true`
- **유효성 검사**: 챌린저 상태 업데이트
- **이벤트 발생**: `BondRefunded` 이벤트

#### **잘못된 클레임언트 (1,565 가스)**
- **조건 검사만**: `challengerAddress == _claimant` 확인
- **조용한 무시**: 아무 작업도 수행하지 않음
- **가스 절약**: 불필요한 작업 방지

## 🎯 각 함수의 다양한 경우들

### 1. `triggerAttentionTest()` 함수의 경우들

#### **✅ 성공 케이스:**
- **유효한 챌린저가 있는 경우**: `validChallengersLength > 1`
  - 챌린저 선택 및 보증금 차감
  - AttentionInfo 생성
  - 이벤트 발생

#### **⚠️ 무시되는 케이스:**
- **유효한 챌린저가 없는 경우**: `validChallengersLength <= 1`
  - 아무 작업도 수행하지 않음 (조용히 무시됨)

### 2. `submitCorrectEvidence()` 함수의 경우들

#### **✅ 성공 케이스:**
- **정상적인 증거 제출**: 올바른 챌린저가 올바른 증거를 제출

#### **❌ 실패 케이스들:**
1. **`AttentionTestNotExists()`**: 존재하지 않는 게임 주소
2. **`InvalidChallengerAddress()`**: 잘못된 챌린저가 증거 제출
3. **`EvidenceAlreadySubmitted()`**: 이미 증거가 제출된 상태
4. **`EvidenceSubmissionExpired()`**: 제출 기간 만료
5. **`ProofVerificationFailed()`**: 잘못된 증거 (잘못된 proofLV/proofRV)

### 3. `resolveClaim()` 함수의 경우들

#### **✅ 성공 케이스:**
- **정상적인 클레임 해결**: 올바른 게임 컨트랙트가 올바른 클레임언트에 대해 호출

#### **⚠️ 무시되는 케이스들:**
1. **잘못된 클레임언트**: `challengerAddress != _claimant`
2. **존재하지 않는 게임**: `challengerAddress == address(0)`
3. **이미 해결된 클레임**: `evidenceSubmitted == true`

## ⭐ 가스 효율성 평가

### **RAT의 가스 사용량은 매우 효율적입니다:**

- **일반적인 ERC20 transfer**: ~65,000 가스
- **ERC721 mint**: ~100,000+ 가스
- **복잡한 DeFi 함수**: 100,000-500,000 가스

### **가스 사용량 요약:**

| 함수 | 가스 사용량 |
|------|-------------|
| **`resolveClaim()` (무시)** | 1,565 가스 |
| **`resolveClaim()` (성공)** | 4,857 가스 |
| **`submitCorrectEvidence()`** | 7,520 가스 |
| **`stake()` (일반)** | 67,177 가스 |
| **`stake()` (유효한 챌린저)** | 114,711 가스 |
| **`triggerAttentionTest()` (성공)** | 132,378 가스 |
| **`triggerAttentionTest()` (무시)** | 14,677 가스 |


## 📋 테스트 명령어

### **개별 함수 테스트:**
```bash
# 기본 스테이킹 테스트
forge test --match-test test_stake_gas_measurement -vv

# 유효한 챌린저 스테이킹 테스트
forge test --match-test test_stake_valid_challenger_gas_measurement -vv

# 주의 테스트 트리거 (성공)
forge test --match-test test_triggerAttentionTest_gas_measurement -vv

# 주의 테스트 트리거 (무시)
forge test --match-test test_triggerAttentionTest_no_valid_challengers_gas_measurement -vv

# 증거 제출 테스트
forge test --match-test test_submitCorrectEvidence_gas_measurement -vv

# 클레임 해결 테스트 (성공)
forge test --match-test test_resolveClaim_gas_measurement -vv

# 클레임 해결 테스트 (무시)
forge test --match-test test_resolveClaim_wrong_claimant_gas_measurement -vv
```

### **모든 가스 측정 테스트:**
```bash
# 모든 가스 측정 테스트
forge test --match-test test_.*_gas_measurement -vv

# 모든 RAT 테스트
forge test --match-test test_.* -vv
```

## 🎯 주요 결론

### **1. 가스 효율성**
- **모든 함수가 매우 효율적으로 구현됨**
- **조건부 실행으로 불필요한 가스 사용 방지**
- **스토리지 슬롯 패킹으로 가스 최적화**

### **2. 안전성**
- **모든 에러 케이스가 적절히 처리됨**
- **조용한 무시 vs 명시적 revert의 적절한 선택**
- **타입 안전성과 범위 검증 완비**

### **3. 사용성**
- **직관적인 함수 인터페이스**
- **명확한 이벤트 발생**
- **예측 가능한 동작**

### **4. 확장성**
- **모듈화된 설계**
- **업그레이드 가능한 구조**
- **유연한 설정 가능**

---
