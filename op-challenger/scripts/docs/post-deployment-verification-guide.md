# 배포후 자동 점검 가이드

**Last Updated**: September 16, 2025
**Version**: 1.0
**Target**: Optimism Devnet Developers

## 개요

이 가이드는 Optimism devnet 배포 후 수행해야 할 자동 점검 절차를 설명합니다. 20분 dispute game 설정이 올바르게 적용되었는지 확인하고, 실제 dispute game resolve 테스트를 자동화합니다.

## 자동 점검 순서

### 1단계: 새로운 devnet 배포

```bash
# 깨끗한 환경에서 devnet 배포
cd /optimism/kurtosis-devnet
AUTOFIX=true just simple-devnet
```

**확인사항**:
- ✅ Kurtosis 엔진 시작 및 enclave 생성
- ✅ 컨트랙트 번들 빌드 완료
- ✅ Prestate 빌드 완료 (CANNON용)
- ✅ 6개 Docker 이미지 빌드 (op-faucet, op-node, op-proposer, op-challenger, op-deployer, op-batcher)

### 2단계: Devnet 서비스 상태 확인

```bash
# 모든 서비스가 RUNNING 상태인지 확인
kurtosis enclave inspect simple-devnet

# 기대 결과: 모든 서비스가 RUNNING 상태
# - L1 서비스: el-1-geth-teku, cl-1-teku-geth
# - L2 서비스: op-el-*-node0-op-geth, op-cl-*-node0-op-node
# - OP Stack 서비스: op-batcher-*, op-proposer-*, op-challenger-*
# - 기타 서비스: op-faucet
```

**예상 출력**:
```
Name:            simple-devnet
UUID:            [UUID]
Status:          RUNNING
Creation Time:   [timestamp]

========================================== User Services ==========================================
UUID   Name                                    Ports   Status
...    el-1-geth-teku                         ...     RUNNING
...    cl-1-teku-geth                         ...     RUNNING
...    op-el-*-node0-op-geth                  ...     RUNNING
...    op-cl-*-node0-op-node                  ...     RUNNING
...    op-batcher-*                           ...     RUNNING
...    op-proposer-*                          ...     RUNNING
...    op-challenger-*                        ...     RUNNING
...    op-faucet                              ...     RUNNING
```

### 3단계: Traefik 네트워크 에러 자동 수정

```bash
# Traefik 네트워크 문제가 있는지 확인하고 자동 수정
cd /optimism/kurtosis-devnet
just fix-traefik
```

**수정 내용**:
- Traefik reverse proxy 컨테이너 재시작
- Docker 네트워크 ID 불일치 문제 해결

### 4단계: 컨트랙트 설정 검증

**🚀 자동화 스크립트 사용 (권장)**

```bash
cd /Users/zena/tokamak-projects/optimism/op-challenger/scripts
./verify-contract-settings.sh
```

**검증 항목:**
- ✅ L1 RPC 연결 상태
- ✅ 컨트랙트 주소 추출 및 확인
- ✅ 실제 생성된 게임 타입 (CANNON 여부)
- ✅ Dispute Game 타이밍 설정 (20분/5분)
- ✅ 테스트 계정 잔고
- ✅ 컨트랙트 버전

**💡 상세한 수동 검증이 필요한 경우:** [컨트랙트 설정 상세 검증 가이드](contract-verification-detailed.md)를 참조하세요.

**⚠️ 중요: 배포 전 설정 확인**

테스트를 위해 다음 설정이 올바르게 되어 있는지 확인하세요:

- **L1 계정 자금 조달**: `simple.yaml`에 `prefunded_accounts` 설정
- **20분 Dispute Game**: `simple.yaml`에 타이밍 overrides 설정
- **CANNON 게임 타입**: `proposer_params.game_type: 0` 설정

**자세한 설정 방법**: [Fast Dispute Game Setup Guide](fast-dispute-game-setup.md)를 참조하세요.


### 5단계: 전체 게임 현황 확인

컨트랙트 설정이 정상적으로 검증되었다면, 현재 생성된 모든 게임의 상태를 확인합니다.

**🔍 전체 게임 상태 확인:**

```bash
cd /Users/zena/tokamak-projects/optimism/op-challenger/scripts

# 모든 게임의 현재 상태 확인
./check-all-games.sh

# 특정 enclave의 게임 확인
./check-all-games.sh my-devnet
```

**확인 항목:**
- ✅ 전체 게임 수 및 최신 게임들 상태
- ✅ 어떤 게임이 IN_PROGRESS 상태인지 (해결 대상)
- ✅ 생성 시간 및 경과 시간
- ✅ 게임 통계 (진행중/해결완료 비율)

### 6단계: 특정 게임 Auto-Resolve 실행

5단계에서 확인한 IN_PROGRESS 게임을 선택하여 자동 해결을 실행합니다.

**🚀 자동 resolve 스크립트 사용:**

```bash
cd /Users/zena/tokamak-projects/optimism/op-challenger/scripts

# 5단계에서 확인한 게임 주소 사용
# 예시: ./auto-resolve-game.sh [GAME_ADDRESS] 20 [L1_RPC] [PRIVATE_KEY]
./auto-resolve-game.sh 0xf4601FF6867301F0496baCe8F108e76C5e1969a8 20 http://127.0.0.1:64046 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

**💡 자세한 auto-resolve 사용법:** [Auto-Resolve Script Guide](auto-resolve-script-guide.md)를 참조하세요.

### 7단계: 해결 결과 확인

Auto-resolve 실행 후 게임이 성공적으로 해결되었는지 확인합니다.

**🔍 해결된 게임 확인:**

```bash
cd /Users/zena/tokamak-projects/optimism/op-challenger/scripts

# 전체 게임 상태 재확인 (통계 업데이트 확인)
./check-all-games.sh

# 특정 게임 상세 결과 확인
./check-game-state.sh [RESOLVED_GAME_ADDRESS]
```

**확인 항목:**
- ✅ 게임 상태가 DEFENDER_WINS로 변경되었는지
- ✅ 해결 완료 시간 및 총 소요 시간
- ✅ 게임 통계에서 해결 완료 게임 수 증가
- ✅ Root claim 및 최종 결과

**예상 결과:**
- 🟢 **DEFENDER_WINS**: Challenger가 없는 경우 정상 결과
- ⏰ **소요 시간**: 약 20분 (maxClockDuration)
- 📊 **통계**: 해결 완료 게임 수 +1

## 배포후 검증 결과 해석

### 성공적인 배포의 지표

| 항목 | 예상 값 | 의미 |
|------|---------|------|
| `실제 게임 타입` | `0` | CANNON 타입 dispute game 사용 |
| `getDeploymentVersion()` | `"v2.0-fixed-disputeGameType"` | 수정된 컨트랙트 배포됨 (선택사항) |
| `maxClockDuration` | `1200` | 20분 dispute game 설정 |
| `clockExtension` | `300` | 5분 확장 시간 설정 |
| 계정 잔고 | `> 0 ETH` | 테스트 계정이 정상적으로 자금 조달됨 |
| 게임 상태 | `0` (IN_PROGRESS) | 게임이 정상적으로 생성되어 진행 중 |

**참고**: `respectedGameType`은 1이어도 정상입니다. 중요한 것은 실제 생성된 게임의 타입이 0 (CANNON)인지 확인하는 것입니다.

## 관련 문서

- [컨트랙트 설정 상세 검증 가이드](contract-verification-detailed.md) - 컨트랙트 설정 상세 검증 방법
- [Fast Dispute Game Setup Guide](fast-dispute-game-setup.md) - 20분 dispute game 설정 가이드
- [Auto-Resolve Script Guide](auto-resolve-script-guide.md) - 자동 resolve 스크립트 사용법

---

*이 가이드는 Optimism devnet 배포 후 모든 설정이 올바르게 적용되었는지 체계적으로 확인하는 방법을 제공합니다.*