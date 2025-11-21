# Fault Game Clock Configuration Guide

## 문제 상황

devnet에서 dispute game 배포 시 `InvalidClockExtension` 에러가 발생하며 다음과 같은 panic이 발생:

```
lvl=warn msg=Revert addr=0x... label=DeployDisputeGame err="execution reverted" revertData=0x8d77ecac
panic
```

## 원인 분석

### 검증 로직

`FaultDisputeGame.sol` 생성자에서 다음 검증을 수행:

```solidity
// 최대 클럭 확장 계산
uint256 splitDepthExtension = uint256(_params.clockExtension.raw()) * 2;
uint256 maxGameDepthExtension =
    uint256(_params.clockExtension.raw()) + uint256(_params.vm.oracle().challengePeriod());
uint256 maxClockExtension = Math.max(splitDepthExtension, maxGameDepthExtension);

// 검증 실패 조건
if (uint64(maxClockExtension) > _params.maxClockDuration.raw()) revert InvalidClockExtension();
```

### 계산 공식

```
maxClockExtension = max(
    clockExtension * 2,
    clockExtension + challengePeriod
)

조건: maxClockExtension ≤ maxClockDuration
```

## 설정 예시

### ❌ 실패하는 설정

```yaml
# simple.yaml
overrides:
  faultGameClockExtension: 300      # 5분
  faultGameMaxClockDuration: 600    # 10분
```

**계산:**
- challengePeriod = 86400 (1일) 인 경우
- maxClockExtension = max(300*2, 300+86400) = 86700
- 86700 > 600 → 실패

### ✅ 성공하는 설정

```yaml
# simple.yaml
overrides:
  faultGameClockExtension: 300      # 5분
  faultGameMaxClockDuration: 900    # 15분
```

**계산:**
- challengePeriod = 300 (5분) 인 경우
- maxClockExtension = max(300*2, 300+300) = 600
- 600 ≤ 900 → 성공

## 권장 설정

### 빠른 테스트용 (15분)
```yaml
overrides:
  faultGameClockExtension: 300      # 5분
  faultGameMaxClockDuration: 900    # 15분
```

### 안전한 설정 (24시간+)
```yaml
overrides:
  faultGameClockExtension: 300      # 5분
  faultGameMaxClockDuration: 87000  # 24시간 + 여유
```

## 트러블슈팅

1. **challengePeriod 확인**: PreimageOracle의 challengePeriod 값 확인
2. **계산 검증**: maxClockExtension이 maxClockDuration보다 작은지 확인
3. **로그 확인**: `revertData=0x8d77ecac`는 `InvalidClockExtension` 에러

## 실제 게임 해결 시간

- **maxClockDuration**: 시스템이 허용하는 최대 시간 (안전 장치)
- **실제 해결 시간**: clockExtension 설정에 따라 결정됨
- 예: clockExtension=300이면 대부분의 게임은 5분 후 해결 가능

## 코드 위치

- 검증 로직: `packages/contracts-bedrock/src/dispute/FaultDisputeGame.sol:256-265`
- 설정 적용: `optimism-package/src/contracts/contract_deployer.star:194-195`
- 사용자 설정: `kurtosis-devnet/simple.yaml`