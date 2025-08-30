# Phase 1 Challenger Network


## 🚀 Quick Installation (Recommended)

### Local Devnet Development Environment

```bash
# Step 0: Configure Game Type (선택사항)
# simple.yaml에서 game_type 설정 확인/변경
# 자세한 내용은 아래 "초기 설정" 섹션 참조

# Step 1: Install system tools
cd op-challenger/scripts
./install-tools.sh

# Step 2: Build Devnet Environment
# game-type = 0 : CANNON (⚠️ 테스트 필요)
# game-type = 1 : PERMISSIONED (✅ 정상동작)
./build-devnet.sh --game-type=1  # 현재 정상동작하는 게임타입

# Step 3: Run Challenger
./run-challenger-devnet.sh
```



## ⚙️ 초기 설정 (중요)

devnet을 처음 실행하기 전에 **게임 타입**을 확인하고 설정해야 합니다.

### Game Type 설정 확인
```bash
# 현재 설정 확인
grep "game_type:" /Users/zena/tokamak-projects/optimism/kurtosis-devnet/simple.yaml
```

### 지원되는 Game Types
| 타입 | 이름 | 용도 | Challenger 설정 |
|------|------|------|----------------|
| **0** | CANNON | 완전한 fault proof | 자동으로 `cannon` 사용 |
| **1** | PERMISSIONED | 빠른 개발/테스트 | 자동으로 `permissioned` 사용 |
| **2** | ASTERISC | Asterisc VM | 자동으로 `asterisc` 사용 |

### 설정 변경이 필요한 경우
```bash
# 1. simple.yaml 편집
vim /Users/zena/tokamak-projects/optimism/kurtosis-devnet/simple.yaml

# 2. proposer_params.game_type 값 변경
proposer_params:
  game_type: 1    # 원하는 타입으로 변경

# 3. 기존 devnet 정리 후 재빌드
kurtosis enclave rm --force simple-devnet
./build-devnet.sh
```

**📖 자세한 설정 가이드**: [롤업 설정 가이드](./docs/rollup-configuration-guide.md)


## ⏱️ Expected Build Times (Step 2)

### Docker Image Build (~3-7 minutes)
- **First time**: 5-7 minutes (no cache)
- **Subsequent builds**: 2-3 minutes (with cache)
- **Components**: op-node, op-batcher, op-proposer, op-faucet, op-challenger, op-deployer

### Devnet Deployment (~5-15 minutes)
The deployment process consists of 6 main steps:

| Step | Component | Expected Time | Description |
|------|-----------|---------------|-------------|
| 1/6 | Configuration | ~30 seconds | Creating devnet configuration files |
| 2/6 | Docker Images | ~2-3 minutes | Preparing container infrastructure |
| 3/6 | L1 + Contracts | ~5-8 minutes | **Longest step**: L1 chain startup + contract deployments |
| 4/6 | Service Verification | ~2-3 minutes | Checking all services are running |
| 5/6 | RPC Testing | ~1 minute | Testing L1/L2 RPC endpoints |
| 6/6 | Final Setup | ~30 seconds | Completing devnet setup |

**⚠️ Note**: Step 3/6 (L1 + Contracts) takes the longest time as it involves:
- Starting the L1 Ethereum chain
- Deploying all L2 smart contracts
- Initializing cross-chain bridges
- Setting up validator networks

## System Tools Auto Installation

### What the auto-installation script does:

```bash
# Install system tools only
./install-tools.sh
```

✅ Automatic system status verification
✅ Auto-installation of missing tools
✅ Go 1.23+ auto-installation
✅ Docker, Mise, Kurtosis, Just auto-installation
✅ Optimized installation order (considering dependencies)
✅ User confirmation before installation

## Devnet Management

### Check Devnet Status
```bash
# Check Devnet running status
kurtosis enclave inspect simple-devnet

# Check challenger status
docker ps | grep challenger
```

### Clean Up Running Devnet
```bash
# Clean up Kurtosis enclave
kurtosis enclave rm --force simple-devnet

# Clean up Docker containers (if any remain)
docker stop $(docker ps -q) 2>/dev/null || true
docker rm $(docker ps -aq) 2>/dev/null || true

# Clean up Docker volumes (optional)
docker volume prune -f
```

## Connection Information

Once the devnet is running, you can access:

- **L1 RPC**: http://localhost:53620
- **L2 RPC**: http://localhost:56781
- **Rollup RPC**: http://localhost:57029

## OP-Challenger 실행

### 기본 사용법
```bash
# Step 3: Run Challenger (위의 Step 2 완료 후)
./run-challenger-devnet.sh
```

### 관리 명령어
```bash
# 상태 확인
docker ps | grep challenger

# 로그 확인
docker logs op-challenger

# 중지/제거
docker stop op-challenger
docker rm op-challenger

# 헬스체크 실행
./challenger-healthcheck.sh
```

### 📚 상세 문서

#### 🎯 설정 및 구성
- **[Devnet 설정 가이드](./docs/devnet-configurations-guide.md)** - ⭐ Simple/Interop/Isthmus 설정 선택 가이드
- **[롤업 설정 가이드](./docs/rollup-configuration-guide.md)** - Game Type, Proposal Interval 등 핵심 설정
- **[Game Types vs Trace Types](./docs/game-types-vs-trace-types.md)** - 개념 구분 및 상호관계
- **[Game Type Configuration](./docs/game-type-configuration.md)** - 설정 불일치 해결 방법

#### 🚀 실행 및 운영
- **[OP-Challenger 실행 가이드](./docs/challenger-guide.md)** - 스크립트 기능 및 사용법
- **[Challenger Parameters](./docs/challenger-parameters.md)** - 모든 설정 옵션 설명
- **[챌린저 기능 테스트 가이드](./docs/challenger-testing.md)** - 테스트 시나리오 및 방법

#### 🛟 문제 해결
- **[트러블슈팅 가이드](./docs/troubleshooting.md)** - 일반적인 문제 해결 방법

## Troubleshooting

### 빠른 해결방법

**일반적인 문제들은 [트러블슈팅 가이드](./docs/troubleshooting.md)를 참조하세요.**

#### 빌드 오류 시 확인사항
1. Docker service is running
2. Go version is 1.23+
3. All required tools are installed via `./install-tools.sh`
4. Check build logs: `cat /tmp/devnet-build.log`

#### 자주 발생하는 문제
- **Devnet not running**: `./build-devnet.sh` 먼저 실행
- **Docker image not found**: `./build-devnet.sh`로 이미지 재빌드
- **Binary files missing**: cannon/op-program 빌드 필요

### 주의사항

⚠️ **개발 및 테스트 목적으로만 사용하세요**
- 니모닉과 키는 테스트용이므로 프로덕션에서 사용하지 마세요
- 네트워크 설정은 로컬 devnet에 맞춰져 있습니다




