# Build Local Network

## Overview

This guide helps you set up a local Optimism devnet environment for challenger testing and development. The complete workflow includes:

- **Local L1/L2 blockchain networks** with fast 20-minute dispute games
- **OP-Challenger service** for testing dispute game resolution
- **RAT (Randomized Attention Test)** comprehensive testing framework
- **Automated verification tools** for post-deployment testing
- **Complete toolchain** for contract development and testing
- **Continuous monitoring** for devnet management


**🔄 Development Workflow**: Install → Configure → Compile → Test → Deploy → Verify → Monitor

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

cd op-deployer && tar -cvzf ./pkg/deployer/artifacts/forge-artifacts/artifacts.tgz -C                              │
│   ../packages/contracts-bedrock/forge-artifacts --exclude="*.t.sol" .


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

## Step 3.5: 🧪 RAT Testing (Optional)

**🔄 Development Workflow**: After compiling contracts, test them before deploying to devnet.

### Overview

RAT (Randomized Attention Test) provides comprehensive testing for dispute game mechanisms and state root correction. Run these tests to verify your contract changes before devnet deployment.

### Quick Test Commands

#### 🔧 Test Cache Management

Go caches test results when code hasn't changed. To see actual execution time instead of `(cached)`:

```bash
# Clear test cache before running tests
go clean -testcache
```

#### Phase 1: Unit Tests (SimulatedBackend)

```bash
# Clear cache first
go clean -testcache
```

#### Phase 2: E2E Tests (Full System)

**⚠️ Note**: E2E tests take 5-10 minutes each (full blockchain deployment)

```bash
# From project root
go clean -testcache

# Individual test scenarios
go test -v ./op-e2e/faultproofs -run "TestRATSuccessScenarioE2E"        # Success scenario
go test -v ./op-e2e/faultproofs -run "TestRATFailureScenarioE2E"        # Failure scenario
go test -v ./op-e2e/faultproofs -run "TestRATSimpleE2E"                 # Simple verification
go test -v ./op-e2e/faultproofs -run "TestRATDisputeGameVictoryE2E"     # 🆕 Complete victory scenario (with withdrawal rejection)
go test -v ./op-e2e/faultproofs -run "TestRATUnitTests"                 # RAT unit tests (fast)
go test -v ./op-e2e/faultproofs -run "TestRATMockWorkflow"              # RAT mock workflow test (fast)

# All E2E tests
go test -v ./op-e2e/faultproofs -run "TestRAT.*"
```

#### 🆕 TestRATDisputeGameVictoryE2E: Complete Victory Scenario

**Test**: `TestRATDisputeGameVictoryE2E()` at `op-e2e/faultproofs/rat_e2e_test.go:437`
**Status**: ✅ Production-Ready (8 phases implemented)

**Full Scenario**: Invalid Proposer State Root → RAT Triggers → Challenger Selection → Dispute Game Victory → Bond Recovery → Withdrawal Rejection

##### Implementation Overview

**8-Phase Complete Victory Workflow**:

**Phase 1: System Deployment Verification**
- Verifies RAT contract is properly deployed and configured
- Validates integration between RAT, DisputeGameFactory, and OptimismPortal
- Confirms all system components are operational and ready

**Phase 2: Challenger Qualification Setup**
- Stakes 5 ETH to RAT contract for challenger qualification
- Ensures sufficient balance for both game participation and RAT bond requirements
- Records initial challenger state and validates eligibility

**Phase 3: Shallow Invalid State Root Creation**
- Creates obviously invalid root claim (`0x01`) for guaranteed output-level resolution
- Uses TestOutputCannonGame proven success pattern to avoid VM execution issues
- Starts dispute game at Block 4 with invalid claim, triggering RAT attention mechanism

**Phase 4: RAT Attention Test Activation & Verification**
- RAT automatically detects invalid root claim and triggers attention test
- Selects eligible challenger from staked pool using randomized selection
- Automatically deducts challenger bond for dispute game participation
- **Verification**: Confirms RAT selected correct challenger (`require.Equal`)
- **Bond Check**: Verifies exact bond amount was deducted from challenger stake

**Phase 5: RAT Core Functionality Summary Confirmation**
- **Confirms 3 core RAT functions completed successfully**:
  1. ✅ Detected the invalid root claim (Phase 3-4)
  2. ✅ Selected the correct challenger (Phase 4)
  3. ✅ Deducted the bond correctly (Phase 4)
- **Strategy**: Summarizes RAT functionality tests without running complex VM execution
- **Purpose**: Validates core RAT mechanism works before proceeding to dispute resolution

**Phase 6: Challenge Period Wait**
- Advances time through 20-minute challenge period (fast dispute game setting)
- Uses time travel mechanism to skip wait period for test efficiency
- Transitions game to resolution-ready state

**Phase 7: Actual Dispute Game Resolution**
- Resolves dispute game to `CHALLENGER_WINS` status through proper mechanism
- Shallow invalid root claim automatically loses, challenger wins
- FaultDisputeGame resolution automatically triggers RAT.ResolveClaim() callback

**Phase 7.5: Withdrawal Rejection Verification**
- Tests OptimismPortal withdrawal rejection for CHALLENGER_WINS games
- Verifies that invalid state root based withdrawals are blocked by the system
- Confirms the core security mechanism: preventing fraudulent withdrawals

**Phase 8: Bond Recovery & System Readiness**
- Verifies automatic RAT bond restoration through game resolution callback
- Confirms challenger remains valid for future disputes and system readiness
- Tests system preparedness for next dispute cycle

**Key Features**:
- **Shallow Resolution**: Uses `common.Hash{0x01}` to avoid VM execution complexity
- **Real Game Resolution**: Proper FaultDisputeGame resolution (not simulation)
- **Automatic Callbacks**: Game resolution triggers RAT.ResolveClaim() automatically
- **Security Validation**: Withdrawal rejection from CHALLENGER_WINS games

```bash
# Run complete victory scenario (5-10 minutes)
go test -v ./op-e2e/faultproofs -run "TestRATDisputeGameVictoryE2E"
```

### Important Configuration for Challenger Testing

#### AllowInvalidPrestate Setting

When testing dispute games with invalid root claims (like in `TestRATDisputeGameVictoryE2E`), the challenger needs to be configured to participate in games even when the prestate doesn't match expected values.

**Default Behavior**:
- `AllowInvalidPrestate = false`: Challenger refuses to participate if prestate validation fails
- Game remains stuck with no challenger activity

**Test Environment Configuration**:
- `AllowInvalidPrestate = true`: Challenger participates despite prestate mismatches
- Allows testing scenarios with intentionally invalid root claims

**In Code** (automatically set in E2E helper):
```go
// op-e2e/e2eutils/challenger/helper.go:185
cfg.AllowInvalidPrestate = true
```

**For Manual Challenger Setup**:
```bash
# Command line flag
--unsafe-allow-invalid-prestate
```

**For Kurtosis Devnet (simple.yaml)**:
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

**💡 When to Use**:
- ✅ **Testing scenarios** with invalid root claims
- ✅ **Development environments** with mismatched prestates
- ❌ **Production environments** (security risk)

#### Prestate Validation Process

1. **Challenger starts** → `ValidatePrestate()` called
2. **Validation fails** → Error: "absolute prestate does not match"
3. **With AllowInvalidPrestate=false** → Challenger exits
4. **With AllowInvalidPrestate=true** → Warning logged, challenger continues

### Test Documentation

**📋 Implementation Status**: [RAT Testing Implementation Plan](./docs/rat-testing-implementation-plan.md) - Complete test coverage and progress tracking

---

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

## Step 6: Monitoring and Management

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