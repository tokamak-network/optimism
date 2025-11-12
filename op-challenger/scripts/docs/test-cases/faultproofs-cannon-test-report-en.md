# Fault Proofs Cannon Test Report

## Overview

This document captures the manual execution results for the `op-e2e/faultproofs` Go test suite. Each entry lists:

- **Purpose**: what the test validates
- **Command**: the exact invocation that was used
- **Result & Duration**: outcome plus an approximate runtime
- **Notes**: noteworthy behaviour observed in the logs

All commands were executed from the repository root (`/Users/zena/tokamak-projects/optimism`).

## Test Runs

### TestBenchmarkCannonFPP

- **Purpose:** placeholder benchmark that will compare witness sizes and VM page allocation once implemented.
- **Command:** `go test -v ./op-e2e/faultproofs -run "TestBenchmarkCannonFPP"`
- **Result & Duration:** SKIP (per the existing TODO), ~5 seconds.
- **Notes:**
  - Emits the expected `TODO(client-pod#906)` message.
  - No infrastructure bootstrapping or state changes occur.

**Execution Flow:**
1. The benchmark prepares the lock-step harness.
2. The TODO guard triggers immediately and calls `t.Skip`.

**Key Coverage:**
- Confirms the benchmark skeleton still builds and can be executed.

---

### TestChallengeLargePreimages_ChallengeFirst

- **Purpose:** ensure the challenger attacks an incorrect preimage at the first opportunity in the dispute tree.
- **Command:** `go test -v ./op-e2e/faultproofs -run "TestChallengeLargePreimages_ChallengeFirst"`
- **Result & Duration:** PASS, ~10 seconds.
- **Notes:** standard deployment logs followed by a clean challenger win; only the usual gas-tip adjustments appear in the logs.

**Execution Flow:**
1. Boot the L1/L2 dev chains and core services (sequencer, batcher, challenger).
2. Deploy contracts and submit the dishonest root claim.
3. Challenger detects the tampered preimage during the first split round and responds immediately.
4. Game resolves to `Challenger Won`; services shut down.

**Key Coverage:**
- `PreimageHelper.UploadLargePreimage` injects a tampered commitment (index 0 → `0xaa`).
- `StartChallenger(...WithPrivKey(Alice))` verifies the challenger can challenge on the first round.
- Confirms factory + preimage helper initialisation paths.

---

### TestChallengeLargePreimages_ChallengeMiddle

- **Purpose:** validate challenging a tampered preimage that only appears at a middle depth.
- **Command:** `go test -v ./op-e2e/faultproofs -run "TestChallengeLargePreimages_ChallengeMiddle"`
- **Result & Duration:** PASS, ~10 seconds.
- **Notes:** similar log flow to the "first" variant, but demonstrates waiting until a deeper split branch.

**Execution Flow:**
1. Devnet boot and dishonest root submission.
2. Challenger waits until the tampered node is reached in the bisection tree.
3. Issues the challenge at the selected depth and invalidates the branch.
4. Game resolves in favour of the challenger.

**Key Coverage:**
- `UploadLargePreimage(...WithReplacedCommitment(10, 0xaa))` mutates only the 10th commitment.
- `WaitForChallenged` confirms mid-depth challenges succeed.
- Uses a different signer (`Mallory`) to prove multi-key flows work.

---

### TestChallengeLargePreimages_ChallengeLast

- **Purpose:** confirm the challenger still wins even if the tampered preimage is discovered at the deepest level.
- **Command:** `go test -v ./op-e2e/faultproofs -run "TestChallengeLargePreimages_ChallengeLast"`
- **Result & Duration:** PASS, ~10 seconds.
- **Notes:** emits a harmless `panic during flush` warning after teardown while flushing logs.

**Execution Flow:**
1. Challenger pushes through every split until the maximum depth is reached.
2. Detects the tampered last commitment and issues the challenge.
3. The game resolves without further steps.

**Key Coverage:**
- `UploadLargePreimage(...WithLastCommitment(0xaa))` affects only the deepest leaf.
- Verifies the dispute loop works even when the error is discovered at the end.
- `WaitForChallenged` still triggers after the long dispute loop.

---

### TestChallengerCompleteExhaustiveDisputeGame

- **Purpose:** full regression covering both correct and incorrect output roots.
- **Command:** `go test -v ./op-e2e/faultproofs -run "TestChallengerCompleteExhaustiveDisputeGame"`
- **Result & Duration:** PASS, ~187 seconds across the `RootCorrect` and `RootIncorrect` sub-tests.
- **Notes:** expected RPC warnings during intensive trace generation; final `player.go` warning about cancelled context is benign.

**Execution Flow:**
1. **RootCorrect:** challenger simply observes, no dispute.
2. **RootIncorrect:** challenger explores the full dispute tree, harvesting claims and executing steps.
3. Final `ResolveClaim` / `Resolve` complete the game; credits settle and services shut down gracefully.

**Key Coverage:**
- `StartOutputAlphabetGameWithCorrectRoot` vs `StartOutputAlphabetGame` show defender / challenger paths.
- `game.StartChallenger(...WithAlphabet(), WithPollInterval)` instruments all claim responses.
- Exercises `WaitForClaimAtDepth`, `WaitForInactivity`, `TimeTravelClock`, credit settlement, and WETH refunds.

---

### TestOutputCannonBondCostMeasurement

- **Purpose:** measure the bond costs when an honest challenger responds to a malicious proposer in GameType 0 (Cannon), progressing through the full dispute game tree to maximum depth.
- **Command:** `go test -v ./op-e2e/faultproofs -run "TestOutputCannonBondCostMeasurement"`
- **Result & Duration:** PASS, 361.41 seconds (~6 minutes).
- **Notes:** demonstrates exponential bond escalation from depth 0 to 50, requiring ~483.18 ETH total bonds from both parties.
- **Related Documentation:** [Bond Cost Measurement Report](./bond-cost-measurement-report-en.md)

**Execution Flow:**
1. **First Game (Cold Start):** creates invalid root claim to establish initial game state and prestate.
   - Challenger responds and wins
   - Time advances past game duration
   - Game closed and resolved as Challenger Won
2. **Second Game (Bond Measurement):** creates invalid root claim that triggers full dispute.
   - Honest challenger (Alice) attacks the invalid claim
   - Malicious proposer (Bob) actively defends each claim
   - Game progresses through:
     - Output Bisection Phase (depth 0-14): bisecting L2 output roots
     - Execution Trace Phase (depth 15-50): bisecting VM execution trace
   - Total 51 claims created (depth 0-50)
   - Time advances past game duration
   - Game closed and resolved as Challenger Won
3. Detailed bond analysis logged for each claim at every depth level
4. Final cost report showing bonds, gas costs, and net results for both parties

**Key Coverage:**
- `DefendClaim` with recursive defense strategy reaches maximum depth (50)
- `WithoutWaitingForStep()` option skips STEP function execution (focuses on bond measurement)
- Bond escalation: ~14.17% increase per depth level
- Total bonds required: Challenger 225.62 ETH + Proposer 257.56 ETH = 483.18 ETH
- Gas price tracking and accurate gwei display
- `CloseGame` and game resolution after time advancement
- Bond calculation using hardcoded values (Big Bonds v1.5 spec) independent of actual gas prices
- Comprehensive logging of all claims with claimant addresses, bonds, and position data

---

## Summary

All Cannon + large-preimage regression tests completed successfully. The benchmark remains intentionally skipped until the associated TODO is implemented. Re-run any scenario by invoking the listed command from the repo root. No additional configuration is required as long as the standard devnet environment is available.

For detailed bond cost analysis and game mechanics, see the [Bond Cost Measurement Report](./bond-cost-measurement-report-en.md).

