# Randomized Attention Test (RAT) PoC

This repository contains a Proof of Concept (PoC) implementation for Randomized Attention Test (RAT) system to test whether challengers are monitoring diligently in the Optimism ecosystem.

## Current Development Scope

### ✅ Completed Development

**1. Contract Development**
- **RAT Contract** (`packages/contracts-bedrock/src/L1/RAT.sol`): Core attention test contract with staking, slashing, and evidence submission
- **DisputeGameFactory Upgrade** (`packages/contracts-bedrock/src/dispute/DisputeGameFactory.sol`): Enhanced with RAT integration for CANNON games
- **FaultDisputeGame Upgrade** (`packages/contracts-bedrock/src/dispute/FaultDisputeGame.sol`): Added RAT address support and resolve integration
- **Interface Updates**: All necessary interfaces updated for RAT integration

**2. Documentation**
- **`gas_cost_analysis_methods.md`**: Documentation explaining gas cost analysis methodology and measurement criteria for the RAT contract
- **`test_results_summary-script.md`**: Ready-to-use test execution scripts with actual gas measurements for individual RAT functions
- **`test_results_summary.md`**: Gas usage measurement results and test case summary for each RAT contract function

**3. Testing Infrastructure**
- **RAT Test Suite** (`packages/contracts-bedrock/test/L1/RAT.t.sol`): Comprehensive test coverage including:
  - **RAT_Initialize_Test**: Contract initialization and version verification
  - **RAT_Staking_Test**: Staking functionality (minimum amount validation, multiple staking)
  - **RAT_TriggerAttentionTest_Test**: Attention trigger mechanism and challenger validation
  - **RAT_Evidence_Test**: Evidence submission (correct/incorrect proofs, challenger validation)
  - **RAT_ResolveClaim_Test**: Claim resolution and bond refunding
  - **RAT_Admin_Test**: Admin functions (perTestBondAmount, evidenceSubmissionPeriod, minimumStakingBalance)
- **RAT Gas Tests** (`packages/contracts-bedrock/test/L1/RAT_GasTest.sol`): Comprehensive gas measurement for all RAT functions including:
  - Staking operations (valid/invalid challengers)
  - Attention trigger mechanism (various probability scenarios)
  - Evidence submission (correct/incorrect proofs, different challengers)
  - Claim resolution and bond refunding
  - Information query functions (challenger info, valid challenger count)
  - Admin functions (probability settings)
- **DisputeGameFactory Gas Tests** (`packages/contracts-bedrock/test/L1/DisputeGameFactory_GasTest.sol`): Gas measurement for dispute game creation scenarios:
  - Game creation without RAT integration
  - Game creation with RAT (not triggered)
  - Game creation with RAT (triggered, single/multiple challengers)

**4. RAT Test Verification**
- ✅ `forge compile`: RAT contracts compile successfully
- ✅ `forge test --match-contract RAT`: All RAT tests pass (18/18 tests)
- ✅ RAT functionality verified:
  - Contract initialization and version verification
  - Staking mechanism (minimum amount validation, multiple staking)
  - Attention trigger mechanism (probability-based selection)
  - Evidence submission (correct/incorrect proofs, challenger validation)
  - Claim resolution and bond refunding
  - Admin functions (parameter updates)
- ✅ Gas measurement tests completed for all RAT functions
- ✅ Integration with DisputeGameFactory verified

**5. Gas Analysis & Measurement**
Ready-to-use scripts for measuring gas costs in specific scenarios:

```bash
# Run all RAT tests
forge test --match-contract RAT -vv

# Run individual function tests with gas measurement
forge test --match-test test_stake_gas_measurement -vv
forge test --match-test test_triggerAttentionTest_gas_measurement -vv
forge test --match-test test_submitCorrectEvidence_gas_measurement -vv
forge test --match-test test_resolveClaim_gas_measurement -vv
```

**Detailed Analysis Documents:**
- **`gas_cost_analysis_methods.md`**: 📊 **Comprehensive gas analysis** with 5 scenarios, complete function breakdown, and efficiency evaluation
- **`test_results_summary.md`**: Complete gas usage results and test case summary for each RAT function
- **`test_results_summary-script.md`**: Ready-to-use execution scripts with actual gas measurements

**Key Findings from Analysis:**
- **5 Scenario Analysis**: Complete gas cost comparison across all RAT scenarios
- **Function-level Breakdown**: Detailed gas usage for each RAT function (stake, triggerAttentionTest, submitCorrectEvidence, resolveClaim)
- **Efficiency Metrics**: RAT vs non-RAT comparison with actual network costs
- **Optimization Results**: Storage packing, conditional execution, gas-efficient operations
- **Real-world Costs**: Test environment vs actual network gas cost analysis

> **💡 Purpose**: These scripts and analysis documents provide comprehensive gas cost analysis and measurement across different RAT scenarios.

## Overview

The RAT system is designed to:
- Randomly select challengers for attention tests
- Verify challenger monitoring diligence
- Automatically slash bonds for non-responsive challengers
- Restore bonds for correct evidence submission
- Integrate with existing dispute game infrastructure
- Optimize gas usage through conditional execution and storage optimization

## Prerequisites

- **Git**: Latest version
- **Go**: 1.21 or later
- **Node.js**: 18 or later
- **Foundry**: Latest version (forge, cast, anvil)
- **Docker**: For containerized development (optional)

## Quick Start

### 1. Clone the Repository

```bash
# Clone the main Optimism repository
git clone https://github.com/tokamak-network/optimism.git
cd optimism

git branch
git checkout feature/op-challenger-with-rat

# Navigate to the contracts directory for building and testing
cd packages/contracts-bedrock
```

### 2. Install Dependencies

```bash
# 1. Mise trust setup (required before forge install)
mise trust

# 2. Install dependencies using mise
mise install

# 3. Install Foundry dependencies
forge install

# 4. Install Node.js dependencies (if needed)
npm install

# 5. Install Go dependencies
cd ../../op-challenger
go mod download

# 6. Return to contracts directory
cd ../packages/contracts-bedrock
```

### 3. Build Contracts

```bash
# All contract building and testing should be done in optimism/packages/contracts-bedrock
cd optimism/packages/contracts-bedrock

# Compile all contracts
forge build

# Verify compilation success
forge build --sizes

# Build go-ffi (required for tests)
cd scripts/go-ffi && go build
```

### 4. Run Tests

```bash
# All testing should be done in packages/contracts-bedrock
cd packages/contracts-bedrock

# Run all RAT tests (recommended)
forge test --match-contract RAT -vv

# Run specific RAT test file
forge test --match-path "test/L1/RAT.t.sol" -vv

# Run gas measurement tests
forge test --match-path "test/L1/RAT_GasTest.sol" -vv

# Run DisputeGameFactory gas tests
forge test --match-path "test/L1/DisputeGameFactory_GasTest.sol" -vv

# Detailed gas report for RAT tests
forge test --match-contract RAT --gas-report

# Run individual function tests (from test_results_summary-script.md)
forge test --match-test test_stake_gas_measurement -vv
forge test --match-test test_triggerAttentionTest_gas_measurement -vv
forge test --match-test test_submitCorrectEvidence_gas_measurement -vv
forge test --match-test test_resolveClaim_gas_measurement -vv
```

### 3. Gas Analysis

The `gas_cost_analysis_methods.md` document provides:
- Complete gas usage analysis for all functions
- Scenario-based gas cost comparison
- Optimization techniques and results
- Performance benchmarks

### 4. Start RAT System

**⚠️ Not Yet Implemented**

The RAT system integration with the challenger is currently under development. The following steps will be implemented in future updates:

```bash
# Navigate to op-challenger
cd ../../op-challenger

# Build the challenger
go build -o op-challenger ./cmd/op-challenger

# Run with RAT configuration
./op-challenger \
  --l1-eth-rpc $L1_RPC_URL \
  --l2-eth-rpc $L2_RPC_URL \
  --rat-contract-address $RAT_CONTRACT_ADDRESS \
  --minimum-stake-amount $MINIMUM_STAKE_AMOUNT \
  --slash-bond-amount $SLASH_BOND_AMOUNT
```

## Core Components

1. **RAT Contract** (`packages/contracts-bedrock/src/L1/RAT.sol`)
   - Manages challenger staking and slashing
   - Handles attention trigger events
   - Processes evidence submissions
   - Gas-optimized with storage slot packing

2. **DisputeGameFactory** (`packages/contracts-bedrock/src/dispute/DisputeGameFactory.sol`)
   - Creates dispute games with RAT integration
   - Triggers attention tests for CANNON games
   - Conditional execution for gas optimization

3. **FaultDisputeGame** (`packages/contracts-bedrock/src/dispute/FaultDisputeGame.sol`)
   - Enhanced with RAT address support
   - Calls RAT resolve on challenger wins
   - Safe integration with existing functionality

4. **Challenger** (`op-challenger/`)
   - Monitors dispute games
   - Responds to attention tests
   - Submits evidence when required


## Gas Analysis Results

### Key Performance Metrics

| Function | Gas Usage | Optimization |
|----------|-----------|--------------|
| `DisputeGameFactory.create()` | 163,991 gas | Base cost (RAT independent) |
| `triggerAttentionTest()` (success) | 98,375 gas | Full execution |
| `triggerAttentionTest()` (ignored) | 3,728 gas | Conditional execution |
| `submitCorrectEvidence()` | 7,526 gas | Very efficient |
| `resolveClaim()` (participant) | 4,857 gas | Bond refund |
| `resolveClaim()` (non-participant) | 1,565 gas | Condition check only |

### Optimization Features

1. **Conditional Execution**: Minimum gas overhead when no valid challengers
2. **Storage Slot Packing**: Efficient data structures
3. **Gas-efficient Operations**: Removal of unnecessary calculations
4. **Safe Integration**: No impact on existing functionality

## Monitoring

### Event Monitoring

Monitor RAT events for system health:

```bash
# Monitor attention triggers
cast logs --from-block latest $RAT_CONTRACT_ADDRESS \
  --event "AttentionTriggered(address,address)"

# Monitor evidence submissions
cast logs --from-block latest $RAT_CONTRACT_ADDRESS \
  --event "CorrectEvidenceSubmitted(address,address,uint256)"
```


