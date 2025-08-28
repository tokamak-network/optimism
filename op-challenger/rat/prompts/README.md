# Randomized Attention Test (RAT) PoC with LLM

This repository contains a Proof of Concept (PoC) implementation for Randomized Attention Test (RAT) system using Large Language Models (LLM) to test whether challengers are monitoring diligently in the Optimism ecosystem.

## Current Development Scope

### ✅ Completed Development

**1. Contract Development**
- **RAT Contract** (`packages/contracts-bedrock/src/L1/RAT.sol`): Core attention test contract with staking, slashing, and evidence submission
- **DisputeGameFactory Upgrade** (`packages/contracts-bedrock/src/dispute/DisputeGameFactory.sol`): Enhanced with RAT integration for CANNON games
- **FaultDisputeGame Upgrade** (`packages/contracts-bedrock/src/dispute/FaultDisputeGame.sol`): Added RAT address support and resolve integration
- **Interface Updates**: All necessary interfaces updated for RAT integration

**2. Documentation**
- **`spec_game.md`**: Game-related knowledge points (Claim types, Position, GameId, etc.)
- **`build_contract.md`**: Complete contract implementation details and build guide
- **`spec_challenge.md`**: Challenger architecture specification and game flow
- **`gas_cost_analysis_methods.md`**: Comprehensive gas cost analysis and optimization

**3. Testing Infrastructure**
- **RAT Test Suite** (`packages/contracts-bedrock/test/L1/RAT.t.sol`): Comprehensive test coverage including:
  - Initialization tests
  - Staking functionality (multiple staking, minimum amount validation)
  - Attention trigger mechanism
  - Evidence submission (correct/incorrect)
  - Information query functions
  - Admin functions
- **Gas Measurement Tests**: Detailed gas cost analysis for all functions and scenarios
- **DisputeGameFactory Gas Tests**: Gas measurement for game creation with RAT integration

**4. Build & Test Verification**
- ✅ `forge compile`: All contracts compile successfully
- ✅ `forge test`: All tests pass successfully
- ✅ Contract integration verified
- ✅ RAT system functionality confirmed
- ✅ Gas optimization verified
- ✅ Security vulnerabilities addressed

**5. Gas Analysis & Optimization**
- **Complete Gas Cost Analysis**: All functions measured and documented
- **Optimization Implemented**: Storage slot packing, conditional execution, gas-efficient operations
- **Scenario-based Analysis**: 5 different scenarios analyzed with actual measurements
- **Performance Comparison**: RAT vs non-RAT gas costs documented

### 🔄 In Progress

**1. Challenger Integration**
- LLM prompt integration for evidence generation
- RAT event monitoring in challenger
- Automatic staking validation
- Attention test response mechanism

**2. LLM Integration**
- Evidence generation using LLM
- Decision making for game actions
- Response validation and optimization

### 📋 Next Steps

**1. Immediate Tasks**
- Implement challenger modifications as per `spec_challenge.md`
- Create end-to-end testing scenarios
- Deploy and test on testnet

**2. Advanced Features**
- Advanced attention test scenarios
- Performance optimization
- Production deployment preparation

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

# Navigate to the contracts directory
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
# Compile all contracts
forge build

# Verify compilation success
forge build --sizes

# Build go-ffi (required for tests)
cd scripts/go-ffi && go build
```

### 4. Run Tests

```bash
# Run all tests
forge test

# Run specific RAT tests
forge test --match-contract RAT

forge test --match-path "packages/contracts-bedrock/test/L1/RAT.t.sol" -vv

# Detailed gas report
forge test --match-path "test/L1/RAT.t.sol" -vv --gas-report

# Run tests with verbose output
forge test -vvv

# Save test results to file
forge test --junit > test-results.xml
```

## LLM Integration Setup

### 1. LLM Prompt Configuration

The LLM prompts are located in `op-challenger/rat/prompts/`:

- `spec_challenge.md`: Challenger architecture specification and game flow
- `spec_game.md`: Game-related knowledge points (Claim types, Position, GameId, etc.)
- `build_contract.md`: Complete contract implementation details and build guide
- `gas_cost_analysis_methods.md`: Comprehensive gas cost analysis and optimization

### 2. Contract Implementation

Based on the documentation in `build_contract.md`, the following contracts have been implemented:

- **RAT Contract**: Core attention test functionality with gas optimization
- **DisputeGameFactory Upgrade**: RAT integration for CANNON games
- **FaultDisputeGame Upgrade**: RAT address support and resolve integration
- **Interface Updates**: All necessary interfaces for RAT integration

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

## Architecture

### Core Components

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

### LLM Integration Points

1. **Evidence Generation**: LLM analyzes game state and generates correct evidence
2. **Decision Making**: LLM determines optimal actions based on game context
3. **Response Validation**: LLM validates challenger responses for correctness

## Testing

### Manual Testing

**⚠️ To Be Implemented**

Manual testing procedures will be implemented in future updates:

```bash
# Deploy contracts to local network
anvil
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast

# Run integration tests
forge test --match-test "test_rat_integration" -vvv

# Test attention trigger
cast call $RAT_CONTRACT_ADDRESS "attentionTrigger(bytes32,bytes32,uint256,bytes32)" \
  $GAME_ID $STATE_ROOT $L2_BLOCK_NUMBER $BLOCK_HASH
```

### Automated Testing

```bash
# Run all tests with coverage
forge coverage

# Run specific test suite
forge test --match-contract RAT_Test -vvv

# Generate test report
forge test --junit > test-report.xml

# Run gas measurement tests
forge test --match-test test_.*_gas_measurement -vv
```

## Gas Analysis Results

### Key Performance Metrics

| Function | Gas Usage | Optimization |
|----------|-----------|--------------|
| `DisputeGameFactory.create()` | 163,991 gas | Base cost (RAT independent) |
| `triggerAttentionTest()` (success) | 132,378 gas | Full execution |
| `triggerAttentionTest()` (ignored) | 14,677 gas | Conditional execution |
| `submitCorrectEvidence()` | 7,520 gas | Very efficient |
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
  --event "AttentionTriggered(bytes32,bytes32,uint256,address)"

# Monitor evidence submissions
cast logs --from-block latest $RAT_CONTRACT_ADDRESS \
  --event "CorrectEvidenceSubmitted(bytes32,address,uint256)"
```
