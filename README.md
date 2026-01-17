# RAT Protocol - Reference Implementation & Reproduction

## Overview
This repository hosts a reference implementation of the **Randomized Attention Test (RAT) Protocol** and a reproducible workflow to validate its behavior and costs.
RAT uses a closest-key mechanism: a challenged validator submits a candidate key cheaply, and independent watchdogs can dispute it on-chain with verifiable evidence (non-inclusion / closer-key).

Verification is organized into two layers:
1.  **Logic verification (Foundry)**: deterministic, self-contained validation of the protocol scenarios.
2.  **Dynamic E2E (Kurtosis)**: run the protocol against a live Optimism Bedrock devnet and exercise proof-driven disputes.

---

## Environment

### Recommended minimum versions
- OS: Ubuntu 22.04+ (or any modern Linux/macOS with Docker)
- Git: 2.30+
- Make: 4.3+
- Foundry (forge/cast): 1.2.0+
- Node.js: 18+
- Python: 3.10+ (only needed for the staking/validity graph)
- Docker Engine: 24+
- Kurtosis CLI: 1.15.0+
- jq: 1.6+ (required for the default E2E helper script output parsing)

> Side note: Go is not required for the RAT verification flows described in this README, but it may be required for running broader Optimism tooling/tests in this monorepo.

## Part 1: Logic Verification (Foundry)

The unified verification script (`RAT_Paper_Verification.t.sol`) simulates the state indexer and validates the protocol's core logic.

### Scenarios Verified
1.  **Happy Path**: Low-cost submission + Optimistic Refund.
2.  **Dispute: Suboptimal Key**: watchdog slashes an incorrect submission using numeric distance.
3.  **Dispute: Non-existent Key**: watchdog proves non-inclusion of a fake key.

### Execution
```bash
cd packages/contracts-bedrock
forge test --match-contract RAT_Paper_Verification -vv
```

---

## Part 2: Dynamic E2E Verification (Kurtosis)

This procedure validates the protocol on a live L2 network using **Kurtosis** to spin up an ephemeral Optimism Devnet.
In other words, it is an **end-to-end workflow** validation of:
`DisputeGameFactory.create()` → (optional) `RAT.triggerAttentionTest()` → `submitCandidate()` → (optional) disputes → stake/prize effects,
executed against a real devnet (L1 receipts + L2 trie proofs).
Concretely, the scripts execute real L1 transactions (and real L2 `eth_getProof` inputs) end-to-end and verify:
- that the factory hook wiring is correct (`create()` → RAT),
- that disputes succeed/fail as expected under real proofs,
- and that the resulting stake/prize accounting matches the protocol rules.

### Prerequisites
- Docker Engine
- Kurtosis CLI
- Node.js (for discovery scripts)
- Foundry (`forge`, `cast`)

### Recommended: Fully automated run
This is the intended way to run the paper’s empirical demo. It spins up the devnet, deploys RAT, triggers tests, runs discovery, executes disputes, validates success/failure, and cleans up.

```bash
scripts/cleanup_kurtosis.sh
kurtosis run github.com/ethpandaops/optimism-package
scripts/run_kurtosis_scenario.sh
```

### Optional: overrides + debugging (same script, different intent)
The automation is **always** done by `scripts/run_kurtosis_scenario.sh`. This section exists only to document
environment overrides for debugging or when you already have a devnet running.

```bash
export PRIVATE_KEY="<FUNDED_KEY>"
# Optional overrides (auto-discovered by default):
# export L1_RPC="http://127.0.0.1:<L1_PORT>"
# export L2_RPC="http://127.0.0.1:<L2_PORT>"
# export RAT_ADDR="<RAT_ADDR>"
# export GAME_ADDR="<GAME_ADDR>"
# export OUTPUT_ROOT="<OUTPUT_ROOT>"
# export L2_BLOCK="<L2_BLOCK>"
scripts/run_kurtosis_scenario.sh
```
*Requires `jq` for log parsing.*

#### What the helper script verifies (default)
By default (opt-out), the script runs:
- **Auto-cleanup**: cleans Kurtosis enclaves/engine on exit (success or failure).
- **E2E dispute matrix (4 cases)** using real MPT proofs from L2:
  - **Non-inclusion**: success (missing addr) + failure (existing addr → revert)
  - **Closer-key**: success (closer exists) + failure (not closer → revert)

#### Why we use debug RPC (intentional, not an “excuse”)
The “closest-key discovery” step requires access to state information that is typically **not available via public RPC**. In this design, a validator is expected to either:
- run its own node with debug APIs enabled, or
- work closely with an entity that operates such a node.

This is an intentional assumption: if a validator relies on *another* validator’s node to provide the closest-key result, it cannot efficiently verify that result is truly closest (without equivalent access), and submitting a non-closest key can lead to slashing. This makes efficient collusion unattractive in practice.

#### Useful flags
- `AUTO_CLEANUP=0`: opt-out of cleanup (keep enclave for debugging)
- `AUTO_E2E_DISPUTE_CHECKS=0`: opt-out of the 4-case dispute matrix
- `PRINT_PROOFS=1`: print proof summaries (eth_getProof fields + accountProof node preview)

### Round-based experiment: randomized disputes + staking/validity graph
If you want a more “natural” experiment (multiple rounds, roles, and stake evolution), use:

```bash
# Start the devnet first (or reuse an existing enclave).
kurtosis run github.com/ethpandaops/optimism-package

# Run 30 rounds with 5 validators:
# - 1 byzantine (offline): never submits
# - 1 byzantine (distance): submits a far key
# - 1 byzantine (non-existence): submits a key for a likely-nonexistent account
# - 2 honest validators
# Honest validators additionally attempt random (incorrect) disputes that must revert (negative testing).
scripts/run_rounds_experiment.sh
```

Outputs:
- **CSV**: `results/<run-id>/staking.csv`
- **Graph (PDF)**: `results/<run-id>/staking.pdf`
- **Roles**: `results/<run-id>/roles.json` (used to annotate the legend)

The graph includes:
- a **horizontal validity threshold** at `minimumStakingBalance`
- an **“invalid” marker** at the round where a validator’s `isValid` flips to `false`.
- a **dashed line per validator** showing **cumulative dispute prize** (from successful disputes)
- a **round 0** snapshot so initial stakes are visible even if someone is slashed on round 1.
- per-validator **markers** (to stay readable in grayscale printouts) and a tight, title-free PDF for easy IEEE inclusion.

Defaults:
- `TRIGGER_PROBABILITY=50000` (50% of 100000)

Common knobs (env vars):
- `L2_TX_PER_ROUND`: number of random L2 transfers per round to perturb the state trie (default: 5)
- `MIN_STAKE_WEI`, `BOND_WEI`: validity threshold and per-test bond (also the per-missed-submit liveness loss in this experiment)
- `STAKE_OFFLINE_WEI`, `STAKE_BYZ_WEI`, `STAKE_HONEST_WEI`: initial stakes per role

Safety-penalty note (experiment setting):
- In the round-based experiment, a **successful safety dispute confiscates the challenger's entire current stake** and pays it to the disputer.

This script uses a Python venv at `.venv` and installs `matplotlib` automatically.

---

## Part 3: Gas Analysis

Gas costs are reported in two complementary ways:
- **Unit-test gas (Foundry `--gas-report`)**: deterministic, comparable, and fast. Best for tracking code changes.
- **E2E receipt gas (`gasUsed`)**: measured from real L1 transactions that include real trie proofs from L2. Best for understanding proof-driven dispute costs and proof-depth scaling.

### Unit-test gas (deterministic)
From `forge test --match-path "test/L1/RAT_GasTest.t.sol" --gas-report`:

These numbers measure the **RAT contract functions themselves** (called directly), not the full `create()` path.
In particular, `triggerAttentionTest` can be noticeably higher in unit tests when the selected validator’s stake crosses
`minimumStakingBalance`, because validity set maintenance (`validChallengers` updates) adds extra SSTORE/array work.

| Function | Measured (Avg) | Notes |
|----------|---------------:|-------|
| `triggerAttentionTest` | 184,529 | Upfront bond+penalty accounting + automatic validity refresh. |
| `submitCandidate` | 68,912 | Optimistic submission + refund + automatic validity refresh. The increase vs older ~30k measurements is dominated by the refund `SSTORE` and validity set maintenance. |

### `DisputeGameFactory.create()` gas (baseline vs. RAT-hooked)
Measured from `forge test --match-path "test/L1/DGF_CreateGasTest.t.sol" -vv` (printed from `gasleft()` deltas):

These numbers measure the **full `create()` transaction**, including game clone/initialization and factory bookkeeping.
To isolate the RAT-hook overhead, compare deltas vs. the baseline.

| Scenario | create() gas |
|----------|-------------:|
| baseline (no RAT) | 161,110 |
| RAT hooked, not triggered (prob=0) | 165,081 |
| RAT hooked, triggered (prob=100%) | 304,417 |

**How the Avg is computed:** This value is taken from Foundry’s `--gas-report` **Avg** column, which is the arithmetic mean over the actual number of calls executed in the gas test suite.
For example, `submitCandidate` is executed **3 times** in `RAT_GasTest.t.sol` (once in each of `test_gas_OptimisticFlow`, `test_gas_DisputeByCloserKey`, and `test_gas_DisputeByNonInclusion`), and the reported Avg is the mean of those three runs.

### E2E dispute gas (proof-driven)
Measured from L1 transaction receipts during the default E2E dispute matrix, with **`accountProofNodes=4`** (state trie path length as returned by L2 `eth_getProof`):

| Dispute | Outcome | gasUsed | accountProofNodes |
|---------|---------|--------:|------------------:|
| `disputeByNonInclusion` | success | 209,395 | 4 |
| `disputeByNonInclusion` | failure | 175,914 | 4 |
| `disputeByCloserKey` | success | 225,476 | 4 |
| `disputeByCloserKey` | failure | 176,788 | 4 |

**Depth scaling expectation:** verification cost is dominated by per-node hashing/RLP decoding over the proof nodes, so gas should grow **approximately linearly with `accountProofNodes`** (and node byte sizes). Expect a noticeable increase as depth grows; use `PRINT_PROOFS=1` to record proof node counts alongside `gasUsed` for your runs.

---

## Implementation Details
- **Numeric Distance**: The protocol uses absolute numeric difference (`|a - b|`) to determine key proximity.
- **Optimistic Refund**: Bond is refunded immediately upon submission. Disputes recover this bond via explicit slashing.
- **Key domain**: keys are treated as addresses encoded into `bytes32` (low 20 bytes), so closest-key discovery and disputes operate over the address space.
