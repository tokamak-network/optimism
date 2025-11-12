# Fault Proofs E2E Test Guide

This document summarizes the preparation steps required before running the `op-e2e/faultproofs` end-to-end tests (e.g. the scenarios documented in `faultproofs-cannon-test-report.md`). The workflow now covers GameType 0/1 (Cannon) as well as the upcoming GameType 2 (Asterisc) and GameType 3 (Kona) flows.

---

## 1. Required VM Assets (GameTypes 0/1/2/3)

**Important:** the E2E tests use dedicated directories that are different from the production build outputs.

The E2E runs **execute local binaries and prestate files directly instead of Docker images**. The fastest way to prepare everything is:

```bash
cd /Users/zena/tokamak-projects/optimism/op-challenger/scripts

# Recommended: prepare Cannon + Asterisc (GameType 2) E2E assets in one shot
./build-binaries-for-challenger-e2e.sh --force --asterisc
```

### E2E vs Production Binary Layout

**E2E runs (macOS arm64):**
- `cannon/bin-e2e/cannon`
- `op-program/bin-e2e/op-program`
- `op-program/bin-e2e/prestate.bin.gz`
- `asterisc/bin-e2e/asterisc`
- `op-program/bin-e2e/prestate-asterisc.json` (deployment / verification)
- `op-program/bin-e2e/prestate-asterisc.bin.gz` (runtime prestate consumed by the challenger)

**Production builds (Linux x86-64):**
- `cannon/bin/cannon`
- `op-program/bin/op-program`
- `op-program/bin/prestate.bin.gz`
- `asterisc/bin/asterisc`
- `op-program/bin/prestate-asterisc.json` (deployment / verification)
- `op-program/bin/prestate-asterisc.bin.gz` (runtime prestate consumed by the challenger)

The helper script performs the following:
- Builds the macOS-native `cannon` binary into `cannon/bin-e2e/`.
- Builds the macOS-native `op-program` binary and its prestates into `op-program/bin-e2e/`.
- Builds the macOS-native ASTERISC VM from the external `asterisc` repository and copies it into `asterisc/bin-e2e/`.
- Places all relevant prestate files inside the E2E-only directories.
- Emits warnings when files are missing or stale; `--force` guarantees a fresh rebuild.

After the script finishes you should see these files inside the E2E directories:

| File | Purpose |
|------|---------|
| `cannon/bin-e2e/cannon` | Cannon VM binary (macOS arm64) |
| `op-program/bin-e2e/op-program` | op-program server (macOS arm64) |
| `op-program/bin-e2e/prestate.bin.gz` | Cannon absolute prestate |
| `asterisc/bin-e2e/asterisc` | ASTERISC VM binary (macOS arm64) |
| `asterisc/bin-e2e/prestate-proof.json` | ASTERISC deployment / verification proof |
| `op-program/bin-e2e/prestate-asterisc.json` | ASTERISC prestate consumed by the challenger |
| `op-program/bin-e2e/prestate-asterisc.bin.gz` | ASTERISC runtime prestate archive |

Verify the files with `ls cannon/bin-e2e/`, `ls op-program/bin-e2e/`, `ls asterisc/bin-e2e/`. Without these assets the tests will fail with “binary not found” style errors.

## 2. Checklist Before Running Tests

1. **Binary / prestate availability**
   - Cannon: `cannon/bin-e2e/cannon`, `op-program/bin-e2e/op-program`, `op-program/bin-e2e/prestate.bin.gz`
   - ASTERISC: `asterisc/bin-e2e/asterisc`, `asterisc/bin-e2e/prestate-proof.json`, `op-program/bin-e2e/prestate-asterisc.json`
   - Optional: `op-program/bin-e2e/prestate-asterisc.bin.gz`

2. **Binary architecture sanity check**
   ```bash
   file cannon/bin-e2e/cannon
   # Output: cannon/bin-e2e/cannon: Mach-O 64-bit executable arm64

   file asterisc/bin-e2e/asterisc
   # Output: asterisc/bin-e2e/asterisc: Mach-O 64-bit executable arm64
   ```

## 3. Example Commands

```bash
# Cannon single test
go test -v ./op-e2e/faultproofs -run "TestChallengeLargePreimages_ChallengeFirst"

# Comprehensive Cannon regression
go test -v ./op-e2e/faultproofs -run "TestChallengerCompleteExhaustiveDisputeGame"

# ASTERISC (GameType 2) tests
go test -v -timeout 20m ./op-e2e/faultproofs -run "TestOutputAsteriscGame"
go test -v ./op-e2e/faultproofs -run "TestOutputAsterisc_ChallengeAllZeroClaim"
go test -v ./op-e2e/faultproofs -run "TestOutputAsterisc_PublishAsteriscRootClaim"
go test -v ./op-e2e/faultproofs -run "TestOutputAsteriscDisputeGame"
go test -v ./op-e2e/faultproofs -run "TestOutputAsteriscDefendStep"
```

For detailed logs and analysis refer to:
- Cannon report: [`faultproofs-cannon-test-report-en.md`](./faultproofs-cannon-test-report-en.md)
- Asterisc report: [`faultproofs-asterisc-test-report-en.md`](./faultproofs-asterisc-test-report-en.md)


