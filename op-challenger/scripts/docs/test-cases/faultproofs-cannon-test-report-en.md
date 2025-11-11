# Fault Proofs Cannon Test Report

## Overview

This document captures the manual execution results for the `op-e2e/faultproofs` Go test suite run on 11 November 2025. Each entry lists:

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

## Summary

All Cannon + large-preimage regression tests completed successfully. The benchmark remains intentionally skipped until the associated TODO is implemented. Re-run any scenario by invoking the listed command from the repo root. No additional configuration is required as long as the standard devnet environment is available.

