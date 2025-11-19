# Fault Proofs E2E Test Cases Documentation

This directory contains comprehensive documentation for Optimism's fault proof system E2E tests, covering multiple VM types (Cannon, Asterisc) and detailed test analysis reports.

## 📑 Document Overview

### Test Reports

#### Cannon (GameType 0 - MIPS-based)
- **[Test Report](./faultproofs-cannon-test-report-en.md)** - Cannon VM test execution results

#### Asterisc (GameType 2 - RISC-V-based)
- **[Test Report](./faultproofs-asterisc-test-report-en.md)** - Asterisc VM test execution results

#### Asterisc-Kona (GameType 3 - RISC-V with Kona Client)
- **[Test Report](./faultproofs-asterisc-kona-test-report.md)** - Asterisc-Kona VM test execution results

#### General E2E Tests
- **[Test Guide](./faultproofs-e2e-en.md)** - General fault proofs E2E test guide

### Analysis Reports

#### Bond Cost Measurement
- **[Bond Cost Analysis Report](./bond-cost-measurement-report.md)** - Detailed analysis of bond costs in dispute games
  - Exponential bond escalation mechanism
  - Economic security design rationale
  - Hardcoded vs dynamic gas pricing comparison
  - Simplified formula explanation

## 🎯 Test Categories

### 1. Cannon Tests (MIPS VM)

**Test File**: `op-e2e/faultproofs/output_cannon_test.go`

**Key Tests**:
- Large preimage challenges (first, middle, last)
- Complete exhaustive dispute game
- Bond cost measurement

**Documentation**: See [Cannon Test Report](./faultproofs-cannon-test-report-en.md)

### 2. Asterisc Tests (RISC-V VM - GameType 2)

**Test File**: `op-e2e/faultproofs/output_asterisc_test.go`

**Key Tests**:
- Basic game flow
- Dispute games (StepFirst, StepMiddle, StepInExtension)
- Large preimage handling
- Blob preimage tests
- Valid/invalid output root handling

**Documentation**: See [Asterisc Test Report](./faultproofs-asterisc-test-report-en.md)

### 3. Asterisc-Kona Tests (RISC-V VM with Kona - GameType 3)

**Test File**: `op-e2e/faultproofs/output_asterisc_kona_test.go`

**Oracle Server**: kona-host (Rust-based replacement for op-program)

**Key Tests**:
- Basic game flow with kona-host
- Dispute games (StepFirst, StepMiddle, StepInExtension, StepAttackDummyClaim)
- Large preimage handling
- Blob preimage tests
- Valid/invalid output root handling
- Game clock and timeout tests
- Withdraw claim tests

**Documentation**: See [Asterisc-Kona Test Report](./faultproofs-asterisc-kona-test-report.md)

### 4. Bond Cost Measurement

**Test**: `TestOutputCannonBondCostMeasurement`

**Purpose**: Measures bond costs when honest challenger responds to malicious proposer

**Key Findings**:
- Total bonds locked: ~483 ETH (at depth 50)
- Bond escalation: ~14% per depth level
- Demonstrates economic security mechanism

**Documentation**: See [Bond Cost Analysis Report](./bond-cost-measurement-report.md)

## 🚀 Quick Start

> **Prerequisites**: Complete the [Setup Guide](#-setup-guide) first!

All commands below should be run from the **repository root** directory.

### Run All Cannon Tests

```bash
# From repository root: /path/to/optimism
pwd  # Verify you're in the right location

# Run all Cannon (MIPS VM) tests
go test -v ./op-e2e/faultproofs -run TestOutputCannon -timeout 30m

# Expected: Multiple tests pass, takes ~10-15 minutes total
```

### Run All Asterisc Tests (GameType 2)

```bash
# From repository root: /path/to/optimism
pwd  # Verify location

# Run all Asterisc (RISC-V VM) tests - excludes Kona tests
go test -v ./op-e2e/faultproofs -run TestOutputAsterisc -timeout 30m

# Expected: Multiple tests pass, takes ~15-20 minutes total
```

### Run All Asterisc-Kona Tests (GameType 3)

```bash
# From repository root: /path/to/optimism
pwd  # Verify location

# Run all Asterisc-Kona (RISC-V VM with Kona) tests
go test -v ./op-e2e/faultproofs -run TestOutputAsteriscKona -timeout 30m

# Expected: Multiple tests pass, takes ~15-20 minutes total
# Note: Requires kona-host binary built via build-binaries-for-challenger-e2e.sh --kona
```

### Run Bond Cost Measurement Test

```bash
# From repository root: /path/to/optimism
pwd  # Verify location

# Run bond cost analysis test
go test -v ./op-e2e/faultproofs -run TestOutputCannonBondCostMeasurement -timeout 10m

# Expected: Test passes in ~6 minutes
# Creates detailed bond cost report in test logs
```

### Run Specific Test

```bash
# From repository root: /path/to/optimism
pwd  # Verify location

# Example: Challenge large preimage at first position
go test -v ./op-e2e/faultproofs -run TestChallengeLargePreimages_ChallengeFirst -timeout 2m

# Example: Run only bond cost tests
go test -v ./op-e2e/faultproofs -run BondCost -timeout 10m

# Example: Run with more verbose output
go test -v -count=1 ./op-e2e/faultproofs -run TestYourTest -timeout 5m
```

### Common Test Patterns

```bash
# From repository root: /path/to/optimism

# Run all tests in faultproofs package
go test -v ./op-e2e/faultproofs -timeout 1h

# Run tests matching pattern "Preimage"
go test -v ./op-e2e/faultproofs -run Preimage -timeout 30m

# Run single test with detailed output
go test -v -count=1 ./op-e2e/faultproofs -run "^TestOutputCannonBondCostMeasurement$" -timeout 10m

# Run tests and save output to file
go test -v ./op-e2e/faultproofs -run TestOutputCannon -timeout 30m 2>&1 | tee test-output.log
```

## 📊 Test Structure

### Typical Test Flow

1. **Setup**: Boot L1/L2 chains, deploy contracts
2. **Game Creation**: Create dispute game with root claim
3. **Challenger Response**: Honest challenger detects and responds
4. **Bisection**: Claims exchanged through output bisection → execution trace
5. **Resolution**: Game resolves with winner determined
6. **Verification**: Bonds claimed, balances verified

### Game Phases

#### Phase 1: Output Bisection (Depth 0-14)
- Bisects L2 output roots to find disagreement point
- Relatively small bonds (0.08 - 0.51 ETH)

#### Phase 2: Execution Trace (Depth 15-50)
- Bisects VM execution trace to find specific instruction
- Exponentially increasing bonds (0.58 - 60 ETH)

#### Phase 3: Step Execution (at MAX_DEPTH)
- On-chain VM executes single instruction
- Proof verification determines winner

## 🔧 Setup Guide

### Prerequisites

Before starting, ensure you have these tools installed:

```bash
# Check required tools
go version        # Go 1.21 or higher
node --version    # Node 18 or higher
pnpm --version    # pnpm 8 or higher
forge --version   # Foundry (forge, cast, anvil)
```

**Install missing tools**:
- **Go**: [golang.org/dl](https://golang.org/dl/)
- **Node.js & pnpm**: [nodejs.org](https://nodejs.org/), then `npm install -g pnpm`
- **Foundry**: `curl -L https://foundry.paradigm.xyz | bash && foundryup`

---

### First Time Setup (Complete Guide)

Follow these steps if you're setting up the repository for the first time.

> 💡 **Tip**: Copy and paste each code block into your terminal. The `pwd` commands help you verify you're in the correct directory.

---

#### Step 1: Clone Repository

```bash
# Navigate to your projects directory
cd ~/projects  # or wherever you want to clone the repo

# Clone the Optimism repository
git clone https://github.com/ethereum-optimism/optimism.git

# Enter the repository
cd optimism

# Verify current location
pwd
# Should show: /Users/YOUR_USERNAME/projects/optimism

# Checkout to the feature branch with fault-proof tests
git checkout feature/challenger-game-type-check

# Verify branch
git branch
# Should show: * feature/challenger-game-type-check

# Verify you're on the correct branch
git status
# Should show: On branch feature/challenger-game-type-check
```

---

#### Step 1.5: Clone Kona Repository (Required for GameType 3)

> **Note**: This step is **required** if you plan to run Asterisc-Kona tests (GameType 3). The build script expects the Kona repository to be in the same parent directory as the Optimism repository.

```bash
# Navigate to parent directory of optimism
cd ~/projects  # Same directory where you cloned optimism

# Verify you're in the correct location
pwd
# Should show: /Users/YOUR_USERNAME/projects

# Clone the Kona repository
git clone https://github.com/ethereum-optimism/kona.git

# Verify both repositories exist
ls -d optimism kona
# Should show:
# kona
# optimism
```

**Directory structure**:
```
~/projects/
├── optimism/          # Optimism monorepo
└── kona/              # Kona repository (required for GameType 3)
```

---

#### Step 1.6: Apply Kona Patch (Known Issue Fix)

> **⚠️ Important**: There is a known issue in the official Kona repository where the `l2_chain_id` defaults to `0` when using `--rollup-config-path`, causing "chain ID 0" warnings and test failures. This patch fixes the issue.

**Issue**: When kona-host receives `--rollup-config-path` instead of `--l2-chain-id`, it should extract the chain ID from the rollup config file, but currently it defaults to `0`.

**Fix**: Apply the following patch to `kona/bin/host/src/single/local_kv.rs`:

```bash
# Navigate to kona repository
cd ~/projects/kona

# Verify current location
pwd
# Should show: /Users/YOUR_USERNAME/projects/kona

# Open the file for editing
# File: bin/host/src/single/local_kv.rs
# Location: Lines 37-39
```

**Find this code** (around line 37-39):
```rust
L2_CHAIN_ID_KEY => {
    Some(self.cfg.l2_chain_id.unwrap_or_default().to_be_bytes().to_vec())
}
```

**Replace with**:
```rust
L2_CHAIN_ID_KEY => {
    let chain_id = if let Some(chain_id) = self.cfg.l2_chain_id {
        chain_id
    } else {
        // If l2_chain_id is not provided, extract it from rollup config
        let rollup_config = self.cfg.read_rollup_config().ok()?;
        rollup_config.l2_chain_id.id()
    };
    Some(chain_id.to_be_bytes().to_vec())
}
```

**Quick patch using `sed`** (macOS/Linux):
```bash
# Navigate to kona repository
cd ~/projects/kona

# Create backup
cp bin/host/src/single/local_kv.rs bin/host/src/single/local_kv.rs.backup

# Apply patch (multi-line, copy all together)
cat > /tmp/kona_patch.txt << 'EOF'
            L2_CHAIN_ID_KEY => {
                let chain_id = if let Some(chain_id) = self.cfg.l2_chain_id {
                    chain_id
                } else {
                    // If l2_chain_id is not provided, extract it from rollup config
                    let rollup_config = self.cfg.read_rollup_config().ok()?;
                    rollup_config.l2_chain_id.id()
                };
                Some(chain_id.to_be_bytes().to_vec())
            }
EOF

# Note: Manual editing recommended for safety
# Use your preferred editor (vim, nano, VSCode, etc.):
vim bin/host/src/single/local_kv.rs
# or
code bin/host/src/single/local_kv.rs

# Return to optimism repository
cd ~/projects/optimism
```

**Verify the patch**:
```bash
# Check the file was modified
grep -A 8 "L2_CHAIN_ID_KEY" ~/projects/kona/bin/host/src/single/local_kv.rs

# Should show the new code with rollup_config.l2_chain_id.id()
```

**Why this patch is needed**:
- The build script uses the local Kona repository at `~/projects/kona`
- Without this patch, E2E tests will encounter "chain ID 0" warnings
- This causes test failures due to invalid chain configuration
- A PR will be submitted to fix this upstream

---

#### Step 1.7: Clone Asterisc Repository (Required for GameType 3)

> **Note**: This step is **required** if you plan to run Asterisc-Kona tests (GameType 3). The build script expects the Asterisc repository to be in the same parent directory as the Optimism repository.

```bash
# Navigate to parent directory of optimism
cd ~/projects  # Same directory where you cloned optimism and kona

# Verify you're in the correct location
pwd
# Should show: /Users/YOUR_USERNAME/projects

# Clone the Asterisc repository
git clone https://github.com/ethereum-optimism/asterisc.git

# Verify all required repositories exist
ls -d optimism kona asterisc
# Should show:
# asterisc
# kona
# optimism
```

**Directory structure**:
```
~/projects/
├── optimism/          # Optimism monorepo
├── kona/              # Kona repository (required for GameType 3)
└── asterisc/          # Asterisc RISC-V VM (required for GameType 3)
```

**Verify the repositories**:
```bash
# Check optimism
ls ~/projects/optimism/.git >/dev/null 2>&1 && echo "✅ optimism exists" || echo "❌ optimism missing"

# Check kona
ls ~/projects/kona/.git >/dev/null 2>&1 && echo "✅ kona exists" || echo "❌ kona missing"

# Check asterisc
ls ~/projects/asterisc/.git >/dev/null 2>&1 && echo "✅ asterisc exists" || echo "❌ asterisc missing"
```

**Why this repository is needed**:
- The build script `build-binaries-for-challenger-e2e.sh` expects Asterisc at `$(dirname "$OPTIMISM_ROOT")/asterisc`
- Asterisc is the RISC-V VM that executes the kona-client binary during fault proof games
- The build script compiles asterisc and uses it to generate prestate files

---

#### Step 2: Install Dependencies

```bash
# You should be in: /path/to/optimism
pwd  # Verify you're in repository root

# Install pnpm dependencies (for all packages including contracts)
pnpm install
# ⏱️ Takes ~2-3 minutes

# Download Go dependencies
go mod download
# ⏱️ Takes ~1-2 minutes
```

---

#### Step 3: Build Smart Contracts

```bash
# Navigate to contracts directory
cd packages/contracts-bedrock

# Verify current location
pwd
# Should show: /path/to/optimism/packages/contracts-bedrock

# Build contracts (generates forge-artifacts/)
pnpm build
# This internally runs: forge build
# ⏱️ Takes ~2-5 minutes (first time)

# Verify build artifacts exist
ls -la forge-artifacts/FaultDisputeGame.sol/FaultDisputeGame.json
# Should show a file of ~1.5MB

# Return to repository root
cd ../..
pwd
# Should show: /path/to/optimism
```

**Why?** E2E tests deploy contracts from compiled artifacts in the `forge-artifacts/` directory.

---

#### Step 4: Build VM Binaries

```bash
# You should be in: /path/to/optimism
pwd  # Verify you're in repository root

# Navigate to challenger scripts directory
cd op-challenger/scripts

# Verify current location
pwd
# Should show: /path/to/optimism/op-challenger/scripts

# Build VMs for E2E Testing
# Option 1: Cannon + Asterisc only (GameType 0, 2)
./build-binaries-for-challenger-e2e.sh --asterisc
# ⏱️ Takes ~5-10 minutes (first time)

# Option 2: All VMs including Kona (GameType 0, 2, 3) - RECOMMENDED
./build-binaries-for-challenger-e2e.sh --asterisc --kona
# ⏱️ Takes ~8-12 minutes (first time)
# This script builds:
#   - Cannon VM (MIPS) - GameType 0
#   - Asterisc VM (RISC-V) - GameType 2
#   - op-program (Oracle server for Cannon/Asterisc)
#   - kona-host (Oracle server for Kona) - GameType 3
#   - Prestate files for all VMs

# Return to repository root
cd ../..
pwd
# Should show: /path/to/optimism
```

**Verify binaries**:
```bash
# All paths are relative to repository root: /path/to/optimism

# Check Cannon VM
ls -lh cannon/bin/cannon
# Should show: ~80MB file

# Check Asterisc VM
ls -lh asterisc/bin/asterisc
# Should show: ~80MB file

# Check op-program
ls -lh op-program/bin/op-program
# Should show: ~80MB file

# Check Cannon prestate
ls -lh op-program/bin/prestate.bin.gz
# Should show: ~3KB file

# Check Asterisc prestate
ls -lh op-program/bin/prestate-asterisc.json
# Should show: ~10KB file

# Check kona-host (if built with --kona)
ls -lh kona/bin-e2e/kona-host
# Should show: ~25MB file

# Test binaries work
./cannon/bin/cannon --version
./asterisc/bin/asterisc --version
./kona/bin-e2e/kona-host --version  # if built with --kona
```

---

#### Step 5: Verify Setup

Run a quick test to verify everything is set up correctly:

```bash
# You should be in: /path/to/optimism
pwd  # Verify you're in repository root

# Run a simple test (should pass in ~30 seconds)
go test -v ./op-e2e/faultproofs -run TestChallengeLargePreimages_ChallengeFirst -timeout 2m

# Expected output:
# === RUN   TestChallengeLargePreimages_ChallengeFirst
# ...
# --- PASS: TestChallengeLargePreimages_ChallengeFirst (XX.XXs)
# PASS
```

**✅ If this test passes, your setup is complete!**

---

#### Quick Reference: Directory Structure

After setup, your directory should look like this:

```
optimism/                                          # Repository root
├── packages/
│   └── contracts-bedrock/
│       └── forge-artifacts/                       # Contract build artifacts
│           └── FaultDisputeGame.sol/
│               └── FaultDisputeGame.json          # ~1.5MB
├── cannon/
│   └── bin/
│       └── cannon                                 # ~80MB
├── asterisc/
│   └── bin/
│       └── asterisc                               # ~80MB
├── op-program/
│   └── bin/
│       ├── op-program                             # ~80MB
│       ├── prestate.bin.gz                        # ~3KB
│       └── prestate-asterisc.json                 # ~10KB
├── op-challenger/
│   └── scripts/
│       └── build-binaries-for-challenger.sh       # Build script
└── op-e2e/
    └── faultproofs/
        ├── output_cannon_test.go                  # Cannon tests
        ├── output_cannon_bond_test.go             # Bond cost tests
        └── output_asterisc_test.go                # Asterisc tests
```

---

### When to Rebuild

You only need to rebuild when you modify certain files:

#### Rebuild Contracts

**When**: You modified any `.sol` file in `packages/contracts-bedrock/src/`

```bash
# From repository root: /path/to/optimism
pwd  # Verify location

# Navigate to contracts directory
cd packages/contracts-bedrock

# Rebuild contracts
pnpm build
# ⏱️ Takes ~2-5 minutes

# Return to root
cd ../..
```

**Verify**:
```bash
ls -lh packages/contracts-bedrock/forge-artifacts/FaultDisputeGame.sol/FaultDisputeGame.json
# Should show ~1.5MB with recent timestamp
```

---

#### Rebuild VM Binaries

**When**: You modified code in:
- `cannon/` directory (Cannon VM)
- `asterisc/` directory (Asterisc VM)
- `op-program/` directory (Oracle server)

```bash
# From repository root: /path/to/optimism
pwd  # Verify location

# Navigate to scripts directory
cd op-challenger/scripts

# Force rebuild all VMs
./build-binaries-for-challenger.sh --asterisc --force
# ⏱️ Takes ~5-10 minutes

# Return to root
cd ../..
```

**Verify**:
```bash
# Check binary timestamps (should be recent)
ls -lh cannon/bin/cannon
ls -lh asterisc/bin/asterisc
ls -lh op-program/bin/op-program
```

---

#### Go Code

**When**: You modified any `.go` file

**Action**: **No manual build needed!** ✅

`go test` automatically compiles Go code before running tests.

```bash
# From repository root: /path/to/optimism
pwd  # Verify location

# Just run the test - Go builds automatically
go test -v ./op-e2e/faultproofs -run TestYourTest
```

If you want to verify compilation without running tests:
```bash
go build ./op-e2e/faultproofs
```

---

### Troubleshooting Setup

#### Problem: "forge: command not found"
```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

#### Problem: "pnpm: command not found"
```bash
npm install -g pnpm
```

#### Problem: Build fails with "out of memory"
```bash
# Increase Node memory limit
export NODE_OPTIONS="--max-old-space-size=8192"
pnpm build
```

#### Problem: VM binaries not found during tests
```bash
# Verify binaries exist
ls -la cannon/bin/cannon
ls -la asterisc/bin/asterisc

# If missing, rebuild
cd op-challenger/scripts
./build-binaries-for-challenger.sh --asterisc --force
```

## 📖 Documentation Structure

### For Test Execution
1. Start with appropriate test report:
   - [Cannon Test Report](./faultproofs-cannon-test-report-en.md) for MIPS-based tests
   - [Asterisc Test Report](./faultproofs-asterisc-test-report-en.md) for RISC-V-based tests
2. Follow execution commands and expected outcomes

### For Understanding Bond Mechanics
1. Read [Bond Cost Analysis Report](./bond-cost-measurement-report.md)
2. Understand exponential escalation formula
3. Learn why hardcoded values are used for security

### For General E2E Testing
1. See [E2E Test Guide](./faultproofs-e2e-en.md)
2. Learn about test infrastructure and helpers

## 🔍 Key Concepts

### Bond Escalation
```
Bond(depth) = 200 gwei × [400,000 × (1.1417)^depth]
```
- Increases ~14% per depth level
- Depth 0: 0.08 ETH → Depth 50: 60 ETH
- Total game: ~483 ETH locked

### Game Types
- **GameType 0**: Cannon (MIPS)
- **GameType 1**: Permissioned Cannon
- **GameType 2**: Asterisc (RISC-V)
- **GameType 3**: Asterisc-Kona (RISC-V with Kona client)
- **GameType 255**: Alphabet (test only)

### Economic Security
- Fixed bond values ensure predictable costs
- Independent of actual gas prices
- Prevents timing attacks during low gas periods
- Maintains security floor regardless of network conditions

## 🐛 Troubleshooting

### Compilation Errors
```bash
go mod tidy
go clean -cache
go clean -testcache
```

### Test Timeouts
```bash
# Increase timeout for long-running tests
go test -timeout 30m -run TestOutputCannon ./op-e2e/faultproofs
```

### Missing Binaries
```bash
# Rebuild all binaries
cd op-challenger/scripts
./build-binaries-for-challenger.sh --asterisc --force
```

### VM Type Issues
```bash
# Run with specific allocator type
OP_E2E_ALLOC_TYPE=basic go test -v ./op-e2e/faultproofs -run TestOutputAsteriscGame
```

## 📚 Related Resources

### Official Documentation
- [Optimism Fault Proof Specs](https://specs.optimism.io/experimental/fault-proof/)
- [Cannon GitHub](https://github.com/ethereum-optimism/cannon)
- [Asterisc GitHub](https://github.com/ethereum-optimism/asterisc)
- [Kona GitHub](https://github.com/ethereum-optimism/kona)

### Source Code
- [Game Type Definitions](../../../../op-challenger/game/fault/types/types.go)
- [Game Registration](../../../../op-challenger/game/fault/register.go)
- [Test Helpers](../../../../op-e2e/e2eutils/disputegame/helper.go)

