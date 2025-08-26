# Randomized Attention Test (RAT) PoC with LLM

This repository contains a Proof of Concept (PoC) implementation for Randomized Attention Test (RAT) system using Large Language Models (LLM) to test whether challengers are monitoring diligently in the Optimism ecosystem.

## Current Development Scope

### ✅ Completed Development

**1. Contract Development**
- **RAT Contract** (`src/L1/RAT.sol`): Core attention test contract with staking, slashing, and evidence submission
- **DisputeGameFactory Upgrade** (`src/dispute/DisputeGameFactory.sol`): Enhanced with RAT integration for CANNON games
- **FaultDisputeGame Upgrade** (`src/dispute/FaultDisputeGame.sol`): Added RAT address support and resolve integration
- **Interface Updates**: All necessary interfaces updated for RAT integration

**2. Documentation**
- **`spec_game.md`**: Game-related knowledge points (Claim types, Position, GameId, etc.)
- **`build_contracts.md`**: Complete contract implementation details
- **`spec_challenge.md`**: Challenger architecture specification
- **`modify_challenger.md`**: Challenger modification guide for RAT integration

**3. Testing Infrastructure**
- **RAT Test Suite** (`test/L1/RAT.t.sol`): Comprehensive test coverage including:
  - Initialization tests
  - Staking functionality (multiple staking, minimum amount validation)
  - Attention trigger mechanism
  - Evidence submission (correct/incorrect)
  - Information query functions
  - Admin functions

**4. Build & Test Verification**
- ✅ `forge compile`: All contracts compile successfully
- ✅ `forge test`: All tests pass successfully
- ✅ Contract integration verified
- ✅ RAT system functionality confirmed

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
- Implement challenger modifications as per `modify_challenger.md`
- Create end-to-end testing scenarios

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

# Run tests with verbose output
forge test -vvv

# Save test results to file
forge test --junit > test-results.xml
```

## LLM Integration Setup

### 1. LLM Prompt Configuration

The LLM prompts are located in `op-challenger/rat/prompts/`:

- `spec_challenge.md`: Challenger architecture specification
- `spec_game.md`: Game-related knowledge points
- `build_contracts.md`: Contract implementation details
- `modify_challenger.md`: Challenger modification guide

### 3. Start RAT System

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

1. **RAT Contract** (`src/L1/RAT.sol`)
   - Manages challenger staking and slashing
   - Handles attention trigger events
   - Processes evidence submissions

2. **DisputeGameFactory** (`src/dispute/DisputeGameFactory.sol`)
   - Creates dispute games with RAT integration
   - Triggers attention tests for CANNON games

3. **FaultDisputeGame** (`src/dispute/FaultDisputeGame.sol`)
   - Enhanced with RAT address support
   - Calls RAT resolve on challenger wins

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
```

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

### Metrics

Key metrics to monitor:
- Attention trigger frequency
- Evidence submission success rate
- Bond slashing events
- Challenger response times

## Troubleshooting

### Common Issues

1. **Compilation Errors**
   ```bash
   # Clean and rebuild
   forge clean
   forge build
   ```

2. **Test Failures**
   ```bash
   # Run with verbose output
   forge test -vvvv

   # Check specific test
   forge test --match-test "test_name" -vvv
   ```

3. **Network Issues**
   ```bash
   # Check RPC connectivity
   cast block-number --rpc-url $L1_RPC_URL
   cast block-number --rpc-url $L2_RPC_URL
   ```

### Debug Mode

Enable debug logging:

```bash
export OP_CHALLENGER_LOG_LEVEL=debug
./op-challenger --log.level debug
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

### Code Style

- Solidity: Follow Solidity Style Guide
- Go: Use `gofmt` and `golint`
- Tests: Maintain >90% coverage

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For questions and support:
- Create an issue in this repository
- Join the Optimism Discord
- Check the documentation in `docs/` directory

## References

- [Optimism Documentation](https://docs.optimism.io/)
- [Foundry Book](https://book.getfoundry.sh/)
- [RAT Specification](op-challenger/rat/prompts/spec_challenge.md)
- [Contract Implementation](op-challenger/rat/prompts/build_contracts.md)
