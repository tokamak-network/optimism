# Phase 1 Challenger Network


## 🚀 Quick Installation (Recommended)

### Local Devnet Development Environment

```bash

# Step 1: Install system tools
cd op-challenger/scripts
./install-tools.sh


# Step 2: 컨트랙 컴파일 & 아티팩트 만들기
cd /optimism/packages/contracts-bedrock
forge build
cd /optimism/op-challenger/scripts
./build-contract-artifacts.sh


# Step 3: Build Devnet Environment

./build-devnet.sh                      # Build with default game type (PERMISSIONED)
./build-devnet.sh --game-type=0        # Build with CANNON game type
./build-devnet.sh --game-type=1        # Build with PERMISSIONED game type

### Supported Game Types
| Type | Name | Purpose | Challenger Config | Status |
|------|------|---------|-------------------|--------|
| **0** | CANNON | Complete fault proof | Auto uses `cannon` | ⚠️ needs testing |
| **1** | PERMISSIONED | Fast development/testing | Auto uses `permissioned` | ✅ **working** |
| **2** | ASTERISC | Asterisc VM | Auto uses `asterisc` | ⚠️ needs testing |

**📝 Current Status**: Only game type 1 (PERMISSIONED) is confirmed to be working.

# Step 4: Run Challenger
./run-challenger-devnet.sh
```

**📖 Detailed Configuration Guide**: [Rollup Configuration Guide](./deployment/rollup-configuration-guide.md)

**🔍 Deployment Monitoring**: [로그 모니터링 가이드](./operations/monitoring-deployment-logs.md) - devnet 배포 중 실시간 로그 확인 방법


## ⏱️ Expected Build Times (Step 2)

### Local Contracts Build (~1-3 minutes)
- **First time**: 2-3 minutes (no cache)
- **Subsequent builds**: 30 seconds - 1 minute (with cache)
- **Components**: Optimism contracts built from local source using Foundry

### Docker Image Build (~3-7 minutes)
- **First time**: 5-7 minutes (no cache)
- **Subsequent builds**: 2-3 minutes (with cache)
- **Components**: op-node, op-batcher, op-proposer, op-faucet, op-challenger, op-deployer

### Devnet Deployment (~5-15 minutes)
The deployment process consists of 6 main steps:

| Step | Component | Expected Time | Description |
|------|-----------|---------------|-------------|
| 1/6 | Local Contracts | ~1-3 minutes | Building contracts from local source |
| 2/6 | Docker Images | ~2-3 minutes | Preparing container infrastructure |
| 3/6 | L1 + Contracts | ~5-8 minutes | **Longest step**: L1 chain startup + local contract deployments |
| 4/6 | Service Verification | ~2-3 minutes | Checking all services are running |
| 5/6 | RPC Testing | ~1 minute | Testing L1/L2 RPC endpoints |
| 6/6 | Final Setup | ~30 seconds | Completing devnet setup |

**⚠️ Note**: Step 3/6 (L1 + Contracts) takes the longest time as it involves:
- Starting the L1 Ethereum chain
- Deploying all L2 smart contracts (using local artifacts)
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

## OP-Challenger Execution

### Basic Usage
```bash
# Step 3: Run Challenger (after completing Step 2 above)
./run-challenger-devnet.sh
```

### Management Commands
```bash
# Check status
docker ps | grep challenger

# Check logs
docker logs op-challenger

# Stop/Remove
docker stop op-challenger
docker rm op-challenger

# Run health check
./challenger-healthcheck.sh
```

### 📚 Detailed Documentation

#### 🎯 Configuration & Setup
- **[Devnet Configuration Guide](./devnet/devnet-configurations-guide.md)** - ⭐ Simple/Interop/Isthmus configuration selection guide
- **[Rollup Configuration Guide](./deployment/rollup-configuration-guide.md)** - Game Type, Proposal Interval and other core settings
- **[Game Types vs Trace Types](./dispute-games/game-types.md)** - Concept distinction and relationships
- **[Game Type Configuration](./dispute-games/dispute-game-configuration-guide.md)** - Configuration mismatch resolution

#### 🚀 Execution & Operations
- **[OP-Challenger Execution Guide](./challenger/challenger-guide.md)** - Script functionality and usage
- **[Challenger Parameters](./challenger/challenger-parameters.md)** - All configuration options explained
- **[Challenger Feature Testing Guide](./challenger/challenger-testing.md)** - Test scenarios and methods

#### 🛟 Troubleshooting
- **[Troubleshooting Guide](./operations/troubleshooting-guide.md)** - Common problem resolution methods

## Troubleshooting

### Quick Solutions

**For common issues, refer to the [Troubleshooting Guide](./operations/troubleshooting-guide.md).**

#### Build Error Checklist
1. Docker service is running
2. Go version is 1.23+
3. All required tools are installed via `./install-tools.sh`
4. Check build logs: `cat /tmp/devnet-build.log`

#### Frequently Occurring Issues
- **Devnet not running**: Run `./build-devnet.sh` first
- **Docker image not found**: Rebuild images with `./build-devnet.sh`
- **Binary files missing**: Build cannon/op-program binaries

### Important Notes

⚠️ **For development and testing purposes only**
- Mnemonics and keys are for testing, do not use in production
- Network settings are configured for local devnet




