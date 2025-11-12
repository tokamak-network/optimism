# Build Local Network

## Overview

This guide helps you set up a local Optimism devnet environment for challenger testing and development. The complete workflow includes:

- **Local L1/L2 blockchain networks** with fast 20-minute dispute games
- **OP-Challenger service** for testing dispute game resolution
- **RAT (Randomized Attention Test)** comprehensive testing framework
- **Automated verification tools** for post-deployment testing
- **Complete toolchain** for contract development and testing
- **Continuous monitoring** for devnet management


**🔄 Development Workflow**: Clone → Install → Configure → Compile → Test → Deploy → Verify → Monitor

---

## Step 0: Clone Repository and Checkout Branch

```bash
# Clone the Optimism repository
git clone https://github.com/tokamak-network/optimism.git
cd optimism

# Checkout the feature branch for local development
git checkout feature/challenger-game-type-check
```

**💡 Note**: This guide assumes you're working with the `feature/local-setup-rat` branch which contains the latest local development setup improvements.

## Step 1: Install System Tools
```bash
cd /optimism/op-challenger/scripts
./install-tools.sh
```
This installs Docker, Go, Kurtosis, and all required tools automatically.

## Step 2: Pre-download Required Docker Images
```bash
./pre-download-images.sh
```

스크립트는 Kurtosis devnet 및 챌린저 실행에 필요한 **핵심 이미지 + GameType 0/1/2/3용 VM 이미지**를 한 번에 내려받습니다.
사전에 캐시해두면 배포 중 발생할 수 있는 네트워크 타임아웃을 크게 줄일 수 있습니다.

**Core Images (항상 포함)**
- `protolambda/eth2-val-tools:latest`
- `consensys/teku:25.7.0`
- `ethereum/client-go:latest`
- `python:3.12-alpine`
- `us-docker.pkg.dev/oplabs-tools-artifacts/images/proxyd:v4.14.5`

**VM Images (기본 포함, GameType 0/1/2/3)**
- `vm-cannon`, `vm-op-program`, `op-challenger`, `op-node`, `op-batcher`, `op-proposer`
- `vm-asterisc` (GameType 2)
- `vm-kona-client` (GameType 3)

**옵션 / 환경변수**
- `VM_REGISTRY`, `VM_IMAGE_TAG` 환경변수를 지정하면 기본 레지스트리/태그를 변경할 수 있습니다.
- `--registry`, `--tag` 옵션으로도 덮어쓸 수 있습니다.
- GameType 2/3이 필요 없으면 `--skip-asterisc`, `--skip-kona` 옵션으로 제외할 수 있습니다.

```bash
# 사설 레지스트리/태그 사용 예시
VM_REGISTRY=ghcr.io/tokamak-network VM_IMAGE_TAG=dev ./pre-download-images.sh

# ASTERISC 이미지만 제외
./pre-download-images.sh --skip-asterisc
```

⚠️ **참고**: Private 레지스트리를 사용할 경우 사전에 `docker login`을 수행해야 합니다.

## Step 3: Compile Contracts and Create Artifacts
```bash
cd /optimism/packages/contracts-bedrock
forge build --force

cd /optimism/op-challenger/scripts
./build-contract-artifacts.sh
./build-binaries-for-challenger.sh --force --asterisc
```

### Contract Build Options

The binary builder supports different modes:

```bash
# Build only if binaries don't exist (default)
./build-binaries-for-challenger.sh

# Force rebuild even if binaries exist (recommended after contract changes)
./build-binaries-for-challenger.sh --force

# Include ASTERISC(GameType 2) assets at the same time
./build-binaries-for-challenger.sh --force --asterisc

# Show help and options
./build-binaries-for-challenger.sh --help
```

**💡 Important**: Always use `--force` after modifying contracts to ensure cannon/prestate files are regenerated with your changes.
Use `--asterisc` alongside `--force` when you also need ASTERISC VM assets for GameType 2 testing.

## Step 4: Configure Devnet Settings

Edit `simple.yaml` to configure testing-optimized settings:

```bash
cd /optimism/kurtosis-devnet
vi simple.yaml  # or your preferred editor
```

**Required Configuration Checks and Edits:**

1. **L1 Account Funding** - Find and verify `ethereum_package` section:
   ```yaml
   ethereum_package:
     network_params:
       prefunded_accounts: '{"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266": {"balance": "1000ETH"}}'
   ```
   **If missing**: Add this section to ensure test accounts have ETH for transactions.

2. **20-Minute Dispute Games** - Find and add `overrides` section:
   ```yaml
   overrides:
     deployer:
       faultGameMaxClockDuration: 1200
       faultGameClockExtension: 300
   ```
   **If missing**: Add this section to enable fast 20-minute dispute games instead of 3.5-day games.

3. **CANNON Game Type** - Find and verify `proposer_params` section:
   ```yaml
   proposer_params:
     game_type: 0
   ```
   **If missing or different**: Set `game_type: 0` to use CANNON dispute games.

4. **Challenger Configuration** - Find and add `challengers` section:
   ```yaml
   challengers:
     challenger:
       enabled: true
       image: {{ localDockerImage "op-challenger" }}
       participants: "*"
       cannon_prestates_url: {{ localPrestate.URL }}
       cannon_trace_types: ["cannon"]
       extra_params: ["--unsafe-allow-invalid-prestate"]
   ```
   **Purpose**: The `--unsafe-allow-invalid-prestate` flag allows challenger to participate in dispute games even when prestate validation fails. This is essential for RAT testing scenarios where invalid root claims are intentionally tested.

   **⚠️ Security Note**: Only use in development/testing environments. Never use in production.

**Verification**: Check that all four sections exist in your `simple.yaml` before proceeding to Step 4.

**📖 Complete Setup Guide**: [Fast Dispute Game Setup Guide](./docs/fast-dispute-game-setup.md) - Detailed configuration instructions and troubleshooting

**Supported Game Types:**
| Type | Name | Purpose | Status |
|------|------|---------|--------|
| **0** | CANNON | Complete fault proof | ✅ **recommended** |
| **1** | PERMISSIONED | Fast development/testing | ✅ working |
| **2** | ASTERISC | Asterisc VM | ⚠️ needs testing |

## Step 4.5: 🧪 RAT Testing (Optional)

**Quick Start**:
```bash
go clean -testcache
go test -v ./op-e2e/faultproofs -run "TestRATDisputeGameVictoryE2E"
```

**📖 Complete Guide**: [RAT E2E Testing Guide](./docs/rat-e2e-testing-guide.md)
**📋 Implementation Status**: [RAT Testing Implementation Plan](./docs/rat-testing-implementation-plan.md)

---

## Step 5: Build Devnet Environment

### Using build-devnet.sh (Recommended)

The `build-devnet.sh` script provides an automated way to build and deploy the devnet with comprehensive error handling and verification:

```bash
# Basic deployment (uses game_type from simple.yaml)
./build-devnet.sh

# Deploy with specific game type
./build-devnet.sh --game-type=0  # CANNON (complete fault proof)
./build-devnet.sh --game-type=1  # PERMISSIONED (development mode, default)
./build-devnet.sh --game-type=2  # ASTERISC (asterisc VM)

# Show help
./build-devnet.sh --help
```

**📖 [build-devnet.sh Process Documentation](./docs/build-devnet-process.md)** - Detailed execution steps and technical specifications

### Alternative: Manual Deployment

If you prefer manual control or need to troubleshoot:

```bash
# For normal cleanup
LOG_LEVEL=debug AUTOFIX=true just simple-devnet

# For complete reset (use when code is changed and recompiled)
LOG_LEVEL=debug AUTOFIX=nuke just simple-devnet
```

### Autofix Mode (Manual Deployment)

Autofix mode helps recover from failed devnet deployments by automatically cleaning up the environment:

1. **Normal Mode** (`AUTOFIX=true`)
   - Sets up the correct shell and updates dependencies
   - Cleans up dangling networks and stopped devnets
   - Preserves other running enclaves
   - Good for fixing minor deployment issues

2. **Nuke Mode** (`AUTOFIX=nuke`)
   - Sets up the correct shell and updates dependencies
   - Completely resets the Kurtosis environment
   - Removes all networks and containers
   - Use when you need a fresh start

## Step 6: Status Check and Monitoring

### Quick Status Check Scripts

```bash
# Check overall system health
./health-check.sh

# Monitor challenger activity and game participation
./monitor-challenger.sh              # Full dashboard
./monitor-challenger.sh config       # System configuration
./monitor-challenger.sh games        # Game activity only
./monitor-challenger.sh logs         # Live log tail
./monitor-challenger.sh sync         # Sync status
./monitor-challenger.sh errors       # Error analysis
```

**What these scripts check:**
- ✅ Container status and uptime
- ✅ RPC connectivity (L1, L2, Rollup)
- ✅ Block synchronization status
- ✅ Challenger activity and game participation
- ✅ GameType configuration and deployment
- ✅ Error analysis and troubleshooting

## Step 7: Post-Deployment Verification

**🚀 Quick Post-Deployment Check**: [Post-Deployment Verification Guide](./docs/post-deployment-verification-guide-en.md) - Complete automated verification process with scripts

**What the verification guide includes:**
- ✅ Automated contract configuration verification
- ✅ Complete game status monitoring
- ✅ Auto-resolve dispute game testing
- ✅ Step-by-step troubleshooting

### build-devnet.sh Verification

If you used `build-devnet.sh`, the script already performs basic verification:

- ✅ L1/L2 chain services running
- ✅ RPC connections tested (L1, L2, Rollup RPC)
- ✅ Service status verification
- ✅ Connection information provided

The script will display connection information upon successful completion:
```
=== Connection Information ===
L1 RPC: http://localhost:53620
L2 RPC: http://localhost:56781
Rollup RPC: http://localhost:57029
```

## Step 8: Real-time Log Monitoring and Management

### Real-time Log Monitoring

#### L1 (Ethereum)
- **EL**: `kurtosis service logs simple-devnet el-1-geth-teku`
- **CL**: `kurtosis service logs simple-devnet cl-1-teku-geth`

#### L2 (OP Stack)
- **EL**: `kurtosis service logs simple-devnet op-el-2151908-node0-op-geth`
- **CL**: `kurtosis service logs simple-devnet op-cl-2151908-node0-op-node`
- **Batcher**: `kurtosis service logs simple-devnet op-batcher-2151908-op-kurtosis`
- **Proposer**: `kurtosis service logs simple-devnet op-proposer-2151908-op-kurtosis`

#### Other Services
- **Challenger**: `kurtosis service logs simple-devnet op-challenger-challenger-2151908`
- **Faucet**: `kurtosis service logs simple-devnet op-faucet`

### Comprehensive Management

**📖 [Devnet Management Guide](./docs/devnet-management.md)** - Complete operations and monitoring guide

**What the management guide includes:**
- ✅ Service status monitoring and health checks
- ✅ Real-time log monitoring for all services (L1, L2, Challenger, etc.)
- ✅ Standard and deep cleanup procedures
- ✅ Advanced log filtering and analysis
- ✅ Resource monitoring and metrics access
- ✅ Quick reference commands for daily operations

**📊 [Deployment Log Monitoring](./docs/monitoring-deployment-logs.md)** - Detailed guide for monitoring deployment progress


# 🛠️ System Tools Auto Installation

## What the Auto-Installation Script Does

### Check Status
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

# 🏗️ Devnet Management

For comprehensive devnet management operations including monitoring, cleanup, and log analysis:

**📖 [Devnet Management Guide](./docs/devnet-management.md)**

**What the management guide includes:**
- ✅ Service status monitoring and health checks
- ✅ Real-time log monitoring for all services (L1, L2, Challenger, etc.)
- ✅ Standard and deep cleanup procedures
- ✅ Advanced log filtering and analysis
- ✅ Resource monitoring and metrics access
- ✅ Quick reference commands for daily operations

**📊 [Deployment Log Monitoring](./docs/monitoring-deployment-logs.md)** - Detailed guide for monitoring deployment progress

# 📚 Key Documentation

**📖 Essential Guides**:
- [Fast Dispute Game Setup](./docs/fast-dispute-game-setup.md) - 20-minute game configuration
- [Post-Deployment Verification](./docs/post-deployment-verification-guide-en.md) - Automated testing
- [Devnet Management](./docs/devnet-management.md) - Operations and monitoring
- [Proposer State Root Challenge Tests](./docs/proposer-state-root-challenge-tests.md) - Test scenarios for dishonest proposer detection
- [State Root Correction Mechanism](./docs/state-root-correction-mechanism.md) - How invalid state roots are detected and corrected

# 🔧 Troubleshooting

For common deployment issues and solutions, see the comprehensive troubleshooting guide:

**📖 [Devnet Troubleshooting Guide](./docs/devnet-troubleshooting.md)**

**Common issues covered:**
- ✅ Docker registry timeout errors
- ✅ Traefik network configuration issues
- ✅ AnchorStateRegistry cold start problems
- ✅ Resource and port conflicts
- ✅ Kurtosis engine connection issues
- ✅ Complete environment reset procedures


## 📖 Additional Documentation

For comprehensive understanding of the fault proof system and testing:

**🧪 Testing & Development**:
- [Proposer State Root Challenge Tests](./docs/proposer-state-root-challenge-tests.md) - Complete guide to dishonest proposer detection and correction scenarios
  - Solidity unit tests for contract-level validation
  - Go E2E tests for integration-level validation
  - Test patterns for creating dishonest state roots
  - Game resolution verification methods

**🔒 Security & Mechanisms**:
- [State Root Correction Mechanism](./docs/state-root-correction-mechanism.md) - Comprehensive guide to how Optimism's fault proof system detects and corrects invalid state roots
  - Complete workflow from invalid proposal to correction
  - RAT (Randomized Attention Test) integration
  - OptimismPortal withdrawal validation
  - Game status verification and bond mechanisms

**🎉 Happy Challenging!**