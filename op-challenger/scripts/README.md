# Build Local Network

## Overview

This guide helps you set up a local Optimism devnet environment for challenger testing and development. The setup includes:

- **Local L1/L2 blockchain networks** with fast 20-minute dispute games
- **OP-Challenger service** for testing dispute game resolution
- **Automated verification tools** for post-deployment testing
- **Complete toolchain** for contract development and testing

**🎯 Quick Start**: Follow Steps 1-5 to deploy a fully functional devnet (initial setup: ~30-40 minutes, subsequent deployments: ~15-20 minutes).

**📚 Key Documentation**:
- [Fast Dispute Game Setup](./docs/fast-dispute-game-setup.md) - 20-minute game configuration
- [Post-Deployment Verification](./docs/post-deployment-verification-guide-en.md) - Automated testing
- [Devnet Management](./docs/devnet-management.md) - Operations and monitoring
- [Proposer State Root Challenge Tests](./docs/proposer-state-root-challenge-tests.md) - Test scenarios for dishonest proposer detection

---

## Step 1: Install System Tools
```bash
cd /optimism/op-challenger/scripts
./install-tools.sh
```
This installs Docker, Go, Kurtosis, and all required tools automatically.

## Step 2: Compile Contracts and Create Artifacts
```bash
cd /optimism/packages/contracts-bedrock
forge build --force

cd /optimism/op-challenger/scripts
./build-contract-artifacts.sh
./build-binaries-for-challenger.sh --force
```

### Contract Build Options

The binary builder supports different modes:

```bash
# Build only if binaries don't exist (default)
./build-binaries-for-challenger.sh

# Force rebuild even if binaries exist (recommended after contract changes)
./build-binaries-for-challenger.sh --force

# Show help and options
./build-binaries-for-challenger.sh --help
```

**💡 Important**: Always use `--force` after modifying contracts to ensure cannon/prestate files are regenerated with your changes.

## Step 3: Configure Devnet Settings

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

**Verification**: Check that all three sections exist in your `simple.yaml` before proceeding to Step 4.

**📖 Complete Setup Guide**: [Fast Dispute Game Setup Guide](./docs/fast-dispute-game-setup.md) - Detailed configuration instructions and troubleshooting

**Supported Game Types:**
| Type | Name | Purpose | Status |
|------|------|---------|--------|
| **0** | CANNON | Complete fault proof | ✅ **recommended** |
| **1** | PERMISSIONED | Fast development/testing | ✅ working |
| **2** | ASTERISC | Asterisc VM | ⚠️ needs testing |

## Step 4: Build Devnet Environment

**💡 Tips**: To avoid memory issues and speed up deployment, perform these tasks first and clean Docker cache after each:

```bash
# Pre-download consensys/teku:25.7.0 image
docker pull consensys/teku:25.7.0

# Clean unused cache only (safe)
docker builder prune
```

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

### build-devnet.sh Features

The script automatically handles:

1. **Docker Image Building**
   - Builds all required services: op-node, op-batcher, op-proposer, op-faucet, op-challenger, op-deployer
   - Handles Git commit information for reproducible builds
   - Provides detailed build progress and error reporting

2. **Devnet Deployment**
   - Uses `simple.yaml` configuration (includes RAT settings)
   - Deploys via `optimism-package-trampoline`
   - Includes retry logic for GRPC communication issues
   - 10-minute timeout with intelligent success detection

3. **Service Verification**
   - Verifies L1/L2 chain services are running
   - Tests RPC connections (L1, L2, Rollup RPC)
   - Provides connection information and management commands

4. **Error Recovery**
   - Automatic cleanup of failed deployments
   - Detailed logging to `/tmp/devnet-build.log`
   - Pre-deployment safety checks

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

## Step 5: Post-Deployment Verification

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

## Log Monitoring

### L1 (Ethereum)
- **EL**: `kurtosis service logs simple-devnet el-1-geth-teku`
- **CL**: `kurtosis service logs simple-devnet cl-1-teku-geth`

### L2 (OP Stack)
- **EL**: `kurtosis service logs simple-devnet op-el-2151908-node0-op-geth`
- **CL**: `kurtosis service logs simple-devnet op-cl-2151908-node0-op-node`
- **Batcher**: `kurtosis service logs simple-devnet op-batcher-2151908-op-kurtosis`
- **Proposer**: `kurtosis service logs simple-devnet op-proposer-2151908-op-kurtosis`

### Other Services
- **Challenger**: `kurtosis service logs simple-devnet op-challenger-challenger-2151908`
- **Faucet**: `kurtosis service logs simple-devnet op-faucet`

## Post-Deployment Verification

After deploying your devnet (using either `build-devnet.sh` or manual deployment), use the comprehensive automated verification process:

**🚀 Complete Verification**: [Post-Deployment Verification Guide](./docs/post-deployment-verification-guide-en.md)

**Quick automated commands:**
```bash
cd /optimism/op-challenger/scripts

# Verify all contract configurations
./verify-contract-settings.sh

# Check all dispute games status
./check-all-games.sh

# Auto-resolve specific dispute game
./auto-resolve-game.sh [GAME_ADDRESS]
```

The verification guide includes:
- ✅ Service status verification
- ✅ Contract configuration verification
- ✅ Account funding verification
- ✅ Dispute game creation and resolution testing
- ✅ Complete end-to-end workflow validation

### RAT Contract Verification

If you deployed with RAT enabled (included in `simple.yaml`), verify RAT deployment:

```bash
# Check RAT deployment logs
kurtosis enclave logs simple-devnet | grep -i rat

# Verify RAT contract initialization
cast call <RAT_PROXY_ADDRESS> "version()" --rpc-url http://localhost:53620
cast call <RAT_PROXY_ADDRESS> "perTestBondAmount()" --rpc-url http://localhost:53620
cast call <RAT_PROXY_ADDRESS> "manager()" --rpc-url http://localhost:53620
```

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

**🎉 Happy Challenging!**