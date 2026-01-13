# RAT Protocol - Verification Suite

## Overview
This repository hosts the reference implementation and verification suite for the **Randomized Attention Test (RAT) Protocol**, which implements an **Optimistic Closest-Key Mechanism** to secure L2 state validation with minimal gas costs.
Verification is conducted in two stages:
1.  **Logic Verification (Foundry)**: Deterministic validation of all scenarios (honest submission, and two disputes).
2.  **Dynamic E2E (Kurtosis)**: Live integration testing on a containerized Optimism Bedrock network.

---

## Part 1: Logic Verification (Foundry)

The unified verification script (`RAT_Paper_Verification.t.sol`) simulates the state indexer and validates the protocol's core logic.

### Scenarios Verified
1.  **Happy Path**: Low-cost submission + Optimistic Refund.
2.  **Dispute: Suboptimal Key Liar**: Watchdog slashes a lazy validator using Numeric Distance logic.
3.  **Dispute: Fake Key Liar**: Watchdog proves non-inclusion of a fake key.

### Execution
```bash
forge test --match-contract RAT_Paper_Verification -vv
```

---

## Part 2: Dynamic E2E Verification (Kurtosis)

This procedure validates the protocol on a live L2 network using **Kurtosis** to spin up an ephemeral Optimism Devnet.

### Prerequisites
- Docker Engine
- Kurtosis CLI (`brew install kurtosis-tech/kurtosis/kurtosis`)
- Node.js (for discovery scripts)
- Foundry (`forge`, `cast`)

### Procedure

#### 1. Start Network
Launch a local Optimism Devnet with L1 and L2 nodes.
```bash
kurtosis run github.com/ethpandaops/optimism-package
```
*Note the RPC mapping ports from the output (e.g., L1: `:32xxx`, L2: `:32yyy`).*

#### 2. Deploy Contracts
Deploy the RAT contract to L1.
```bash
# Export L1 RPC and Private Key
export ETH_RPC_URL="http://127.0.0.1:<L1_PORT>"
export PRIVATE_KEY="<FUNDED_KEY>"

# Run Deployment Script
forge script scripts/DeployRAT.s.sol:DeployRAT --broadcast --sender <ADDRESS>
```

#### 3. Execute Scenario: "Lazy Validator Dispute"

**Step A: Trigger RAT**
The factory (or admin) triggers a test.
```bash
cast send <RAT_ADDR> "triggerAttentionTest(address,bytes32,bytes32,uint64)" <GAME_ADDR> <ROOT> <HASH> <BLOCK> --private-key $PRIVATE_KEY
```

**Step B: Watchdog Discovery**
The Watchdog runs the discovery script to find the closest key to the generated `Seed`.
```bash
# This script dumps the L2 state and calculates numeric distances
node scripts/find_closest_key.js --rpc http://127.0.0.1:<L2_PORT> --seed <SEED_FROM_EVENT>
```
*Output: Found Closest Key: `0x123...` (Distance: 100)*

**Step C: Lazy Submission (Victim)**
The Victim submits a suboptimal key (farther distance).
```bash
cast send <RAT_ADDR> "submitCandidate(address,bytes32,bytes32,bytes32,bytes32,bytes32)" ... --private-key <VICTIM_KEY>
```

**Step D: Dispute (Watchdog)**
The Watchdog disputes using the key found in Step B.
```bash
# Generate Proof (using standard L1/L2 proving tools or mock for devnet)
# Call disputeByCloserKey
cast send <RAT_ADDR> "disputeByCloserKey(address,bytes32,...)" <GAME_ADDR> <CLOSER_KEY> ... --private-key <WATCHDOG_KEY>
```

**Step E: Verification**
Check the event logs to confirm the dispute was successful.
```bash
cast events --address <RAT_ADDR> "DisputeSuccessful(address,address,bytes32,uint256,string)"
```

---

## Part 3: Gas Analysis

The protocol's efficiency is validated by measuring the operational gas costs of key functions using a dedicated test suite.

### Execution
Run the gas measurement tests:
```bash
forge test --match-contract RAT_GasTest -vv
```

### Reference Costs
| Function | Gas Cost (Est) | Notes |
|----------|----------------|-------|
| `submitCandidate` | **~28,837** | **Optimistic (No Proof)** + Refund. |
| `disputeByCloserKey` | ~97,805 | Proof Verify + Slashing. |
| `disputeByNonInclusion` | ~97,733 | Proof of "Other Key" (Vacancy) + Slashing. |

---

## Implementation Details
- **Numeric Distance**: The protocol uses absolute numeric difference (`|a - b|`) to determine key proximity.
- **Optimistic Refund**: Bond is refunded immediately upon submission. Disputes recover this bond via explicit slashing.
