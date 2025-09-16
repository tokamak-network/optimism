# Randomized Attention Test (RAT) PoC

This repository contains a proof-of-concept smart contract and gas-cost measurements for the **Randomized Attention Test (RAT)** protocol. RAT probabilistically checks whether Optimistic Rollup validators are actively tracking L2 state transitions.

- **Branch:** `feature/rat-poc-v1`  
- **Origin:** Forked from [the official Optimism repository](https://github.com/ethereum-optimism/optimism)
- **Authors:** Suhyeon Lee, Yeongju Bak  
- **Paper Title:** *Looking for Attention: Randomized Attention Test Design for Validator Monitoring in Optimistic Rollups*  
- **PDF Link:** https://arxiv.org/pdf/2505.24393


## Table of Contents
- [Contract development](#contract-development)
- [Testing infrastructure](#testing-infrastructure)
- [Requirements & Quick start](#requirements--quick-start)
- [How to test](#how-to-test)
- [Expected result](#expected-result)
- [Future work](#future-work)
- [License & citation](#license--citation)
- [Contact](#contact)


## Contract development

- **RAT Contract** — `packages/contracts-bedrock/src/L1/RAT.sol`  
  Core attention-test logic: staking, slashing, evidence submission, settlement.
- **DisputeGameFactory Upgrade** — `packages/contracts-bedrock/src/dispute/DisputeGameFactory.sol`  
  RAT integration path for CANNON games (conditional trigger and wiring).
- **FaultDisputeGame Upgrade** — `packages/contracts-bedrock/src/dispute/FaultDisputeGame.sol`  
  RAT address support and `resolve`-path integration.
- **Interface updates**  
  All required interfaces updated to expose RAT configuration and calls.

## Testing infrastructure

- **RAT Test Suite** — `packages/contracts-bedrock/test/L1/RAT.t.sol`  
  - `RAT_Initialize_Test` — Initialization and version checks  
  - `RAT_Staking_Test` — Minimum amount validation, multiple staking  
  - `RAT_TriggerAttentionTest_Test` — Trigger mechanism and challenger validation  
  - `RAT_Evidence_Test` — Correct/incorrect proofs, challenger validation  
  - `RAT_ResolveClaim_Test` — Claim resolution and bond refunding  
  - `RAT_Admin_Test` — `perTestBondAmount`, `evidenceSubmissionPeriod`, `minimumStakingBalance`
- **RAT Gas Tests** — `packages/contracts-bedrock/test/L1/RAT_GasTest.sol`  
  - Staking (valid/invalid challengers)  
  - Attention trigger (various probability scenarios)  
  - Evidence submission (correct/incorrect, different challengers)  
  - Claim resolution & bond refunding  
  - Information queries (challenger info, valid challenger count)  
  - Admin functions (probability settings)
- **DisputeGameFactory Gas Tests** — `packages/contracts-bedrock/test/L1/DisputeGameFactory_GasTest.sol`  
  - Game creation without RAT  
  - Game creation with RAT (not triggered)  
  - Game creation with RAT (triggered; single/multiple challengers)

## Requirements & Quick start

### Prerequisites
- Git
- Node.js (≥ 18)
- Foundry (forge, cast, anvil)
- *(Optional)* Go (≥ 1.21) if using any Go FFI helpers

### Clone & checkout
```bash
git clone https://github.com/tokamak-network/optimism.git
cd optimism
git checkout feature/rat-poc-v1

# Navigate to the contracts directory for building and testing
cd packages/contracts-bedrock
```
### Install & Build
```
# install deps (adjust to your workspace layout)
forge install
npm install

# build contracts
forge build

# Build go-ffi (required for tests)
cd scripts/go-ffi && go build
```

## How to test
### Core Command (recommended)
```
# All testing should be done in packages/contracts-bedrock
cd packages/contracts-bedrock

# Run all RAT tests with gas report 
forge test --match-contract RAT -vv --gas-report
```

### Test separately (optional)
```
# Run specific RAT test file
forge test --match-path "test/L1/RAT.t.sol" -vv

# Run gas measurement tests
forge test --match-path "test/L1/RAT_GasTest.sol" -vv

# Run DisputeGameFactory gas tests
forge test --match-path "test/L1/DisputeGameFactory_GasTest.sol" -vv

# Detailed gas report for RAT tests
forge test --match-contract RAT --gas-report

# Run individual function tests
forge test --match-test test_stake_gas_measurement -vv
forge test --match-test test_triggerAttentionTest_gas_measurement -vv
forge test --match-test test_submitCorrectEvidence_gas_measurement -vv
forge test --match-test test_resolveClaim_gas_measurement -vv
```

## Expected result

- All tests pass.
- A gas report is printed for relevant functions and scenarios.

## Future work

- Integrate RAT response logic into the validator (Golang) code.
- Stand up nodes and operate RAT in a testnet environment to evaluate behavior and costs end-to-end.

## License & citation

- MIT License
- If you use this PoC or build on it, please cite the paper above and reference this repository/branch.

## Contact
- zena @ tokamak.network
- suhyeon @ tokamak.network
