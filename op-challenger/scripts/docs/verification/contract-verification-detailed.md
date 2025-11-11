# 컨트랙트 설정 상세 검증 가이드

**Last Updated**: September 17, 2025
**Version**: 1.0
**Target**: Optimism Devnet Developers

## 개요

이 문서는 Optimism devnet 배포 후 컨트랙트 설정을 상세하게 검증하는 방법을 설명합니다. 자동화된 스크립트와 수동 검증 방법을 모두 제공합니다.

## 🚀 빠른 검증 (권장)

### 자동화 스크립트 실행

```bash
cd /Users/zena/tokamak-projects/optimism/op-challenger/scripts
./verify-contract-settings.sh [enclave_name]
```

**예시:**
```bash
# 기본 enclave (simple-devnet) 검증
./verify-contract-settings.sh

# 특정 enclave 검증
./verify-contract-settings.sh my-devnet
```

**스크립트가 확인하는 항목:**
- ✅ L1 RPC 연결 상태
- ✅ 컨트랙트 주소 추출
- ✅ 실제 생성된 게임 타입 (CANNON 여부)
- ✅ Dispute Game 타이밍 설정 (20분/5분)
- ✅ 테스트 계정 잔고
- ✅ 컨트랙트 버전

## 📋 수동 검증 방법

스크립트 실행이 어렵거나 더 자세한 분석이 필요한 경우 사용합니다.

### 1. 환경 설정

```bash
# 환경 파일 다운로드
kurtosis files download simple-devnet devnet-descriptor-0 /tmp/devnet-desc

# 주요 변수 설정
L1_RPC=$(jq -r '.l1.nodes[0].services.el.endpoints.rpc.port' /tmp/devnet-desc/env.json)
L1_RPC="http://127.0.0.1:${L1_RPC_PORT}"
OP_PORTAL=$(jq -r '.l2[0].l1_addresses.OptimismPortalProxy' /tmp/devnet-desc/env.json)
DISPUTE_GAME_FACTORY=$(jq -r '.l2[0].l1_addresses.DisputeGameFactoryProxy' /tmp/devnet-desc/env.json)
```

### 2. OptimismPortal 설정 확인

```bash
# respectedGameType 확인 (참고용)
RESPECTED_GAME_TYPE=$(cast call $OP_PORTAL "respectedGameType()(uint32)" --rpc-url $L1_RPC)
echo "respectedGameType: $RESPECTED_GAME_TYPE"
```

### 3. 실제 생성된 게임 확인

```bash
# 생성된 게임 수
GAME_COUNT=$(cast call $DISPUTE_GAME_FACTORY "gameCount()(uint256)" --rpc-url $L1_RPC)
echo "생성된 게임 수: $GAME_COUNT"

# 최신 게임 정보
if [ "$GAME_COUNT" != "0" ]; then
    LATEST_GAME_INDEX=$((GAME_COUNT - 1))
    LATEST_GAME_INFO=$(cast call $DISPUTE_GAME_FACTORY "gameAtIndex(uint256)(uint32,uint64,address)" $LATEST_GAME_INDEX --rpc-url $L1_RPC)

    ACTUAL_GAME_TYPE=$(echo "$LATEST_GAME_INFO" | head -1)
    LATEST_GAME_ADDR=$(echo "$LATEST_GAME_INFO" | tail -1)

    echo "최신 게임 타입: $ACTUAL_GAME_TYPE (0=CANNON)"
    echo "최신 게임 주소: $LATEST_GAME_ADDR"
fi
```

### 4. Dispute Game 타이밍 검증

```bash
# 게임별 타이밍 설정
if [ -n "$LATEST_GAME_ADDR" ]; then
    MAX_CLOCK_DURATION=$(cast call $LATEST_GAME_ADDR "maxClockDuration() returns (uint64)" --rpc-url $L1_RPC)
    CLOCK_EXTENSION=$(cast call $LATEST_GAME_ADDR "clockExtension() returns (uint64)" --rpc-url $L1_RPC)
    GAME_STATUS=$(cast call $LATEST_GAME_ADDR "status() returns (uint8)" --rpc-url $L1_RPC)

    echo "maxClockDuration: ${MAX_CLOCK_DURATION}초 (예상: 1200)"
    echo "clockExtension: ${CLOCK_EXTENSION}초 (예상: 300)"
    echo "게임 상태: $GAME_STATUS (0=IN_PROGRESS, 1=CHALLENGER_WINS, 2=DEFENDER_WINS)"
fi
```

### 5. 컨트랙트 구현체 확인

```bash
# 게임 타입별 구현체
echo "게임 타입 0 (CANNON): $(cast call $DISPUTE_GAME_FACTORY "gameImpls(uint32)(address)" 0 --rpc-url $L1_RPC)"
echo "게임 타입 1: $(cast call $DISPUTE_GAME_FACTORY "gameImpls(uint32)(address)" 1 --rpc-url $L1_RPC)"

# CANNON 게임 설정
CANNON_IMPL=$(cast call $DISPUTE_GAME_FACTORY "gameImpls(uint32)(address)" 0 --rpc-url $L1_RPC)
echo "CANNON maxClockDuration: $(cast call $CANNON_IMPL "maxClockDuration() returns (uint64)" --rpc-url $L1_RPC)초"
echo "CANNON clockExtension: $(cast call $CANNON_IMPL "clockExtension() returns (uint64)" --rpc-url $L1_RPC)초"
```

### 6. 계정 잔고 확인

```bash
# 주요 테스트 계정들
ACCOUNTS=(
    "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"  # Account 0
    "0x70997970C51812dc3A010C7d01b50e0d17dc79c8"  # Account 1
    "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"  # Account 2
)

echo "테스트 계정 잔고:"
for i in "${!ACCOUNTS[@]}"; do
    ACCOUNT=${ACCOUNTS[$i]}
    BALANCE=$(cast balance $ACCOUNT --rpc-url $L1_RPC)
    BALANCE_ETH=$(cast --to-unit $BALANCE ether)
    echo "  계정 $i ($ACCOUNT): ${BALANCE_ETH} ETH"
done
```

## 📊 검증 기준

### ✅ 정상 상태 기준

| 항목 | 기대값 | 설명 |
|------|--------|------|
| 실제 게임 타입 | `0` | CANNON 타입 dispute game |
| maxClockDuration | `1200` | 20분 dispute game |
| clockExtension | `300` | 5분 확장 시간 |
| 계정 잔고 | `> 0 ETH` | 테스트 계정 자금 확인 |
| 게임 상태 | `0` | IN_PROGRESS 상태 |

### ⚠️ 주의사항

- **respectedGameType**: 1이어도 정상 (실제 게임 타입이 중요)
- **게임 생성**: 10분 interval이므로 시간이 필요할 수 있음
- **컨트랙트 버전**: 선택사항 (OPCM이 배포된 경우만)

## 🔧 문제 해결

### 게임이 생성되지 않는 경우

```bash
# Proposer 로그 확인
kurtosis service logs simple-devnet op-proposer-*-op-kurtosis

# Proposer 상태 확인
kurtosis service inspect simple-devnet op-proposer-*-op-kurtosis
```

### 잘못된 게임 타입인 경우

1. `simple.yaml` 설정 확인:
   ```yaml
   proposer_params:
     game_type: 0  # 이 값이 0인지 확인
   ```

2. 재배포 필요:
   ```bash
   kurtosis clean -a
   AUTOFIX=true just simple-devnet
   ```

### 타이밍 설정이 틀린 경우

1. `simple.yaml` overrides 확인:
   ```yaml
   overrides:
     deployer:
       faultGameMaxClockDuration: 1200
       faultGameClockExtension: 300
   ```

2. 컨트랙트 재빌드 후 재배포

### 계정 잔고가 0인 경우

1. `simple.yaml` prefunded_accounts 설정 확인:
   ```yaml
   ethereum_package:
     network_params:
       prefunded_accounts: '{"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266": {"balance": "1000ETH"}}'
   ```

## 🔗 관련 문서

- [배포후 자동 점검 가이드](post-deployment-verification-guide.md) - 메인 검증 가이드
- [Fast Dispute Game Setup Guide](fast-dispute-game-setup.md) - 20분 dispute game 설정
- [Auto-Resolve Script Guide](auto-resolve-script-guide.md) - 자동 resolve 사용법

---

*이 문서는 컨트랙트 설정의 상세한 검증 방법을 제공합니다. 일반적인 사용에는 자동화 스크립트를 권장합니다.*