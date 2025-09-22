# RAT E2E Testing Guide

## Overview

This guide provides instructions on how to run RAT (Resource Allocation Table) E2E tests and effectively monitor logs.

## Prerequisites

Before running RAT E2E tests, ensure you have:

- **Optimism development environment** properly set up
- **Go 1.21+** installed
- **Docker** available for blockchain deployments
- Sufficient system resources (memory: 8GB+, disk space: 10GB+)

## Performance Tips

- **Clear test cache**: Run `go clean -testcache` before testing
- **Ensure sufficient Docker resources**: Increase Docker memory allocation to 8GB+
- **Run tests individually**: Avoid running multiple E2E tests simultaneously
- **Avoid parallel execution**: E2E tests should not run in parallel due to resource conflicts

## Key Configuration

### AllowInvalidPrestate Setting
This crucial configuration affects challenger behavior:

- **When `true`**: Allows challenger to participate despite prestate mismatches (recommended for testing)
- **When `false`**: Challenger exits if prestate validation fails

The RAT E2E tests automatically configure this setting appropriately for each test scenario.

## Complete RAT Test Execution

### Available Test Categories ✅

#### Phase 1: Go Integration Tests (SimulatedBackend) - Run from project root
```bash
# Individual integration tests
go test -v ./op-challenger/game/fault -run "TestRATChallengerIntegration"
go test -v ./op-challenger/game/fault -run "TestRATMultipleChallengers"
go test -v ./op-challenger/game/fault -run "TestRATIncorrectEvidenceSubmission"

# All integration tests
go test -v ./op-challenger/game/fault -run "TestRAT.*"
# Expected result: 3/3 tests PASS (~10 seconds total)
```

#### Phase 2: E2E Tests (Full System) - Run from project root
```bash
# ⚠️ Note: E2E tests take 5-10 minutes (build complete blockchain system)

# Individual E2E scenario tests
go test -v ./op-e2e/faultproofs -run "TestRATSuccessScenarioE2E"        # Success scenario
go test -v ./op-e2e/faultproofs -run "TestRATFailureScenarioE2E"        # Failure scenario
go test -v ./op-e2e/faultproofs -run "TestRATSimpleE2E"                 # Simple verification
go test -v ./op-e2e/faultproofs -run "TestRATDisputeGameVictoryE2E"     # ✅ Complete success! (~6-10 minutes)

# Unit and mock tests (faster)
go test -v ./op-e2e/faultproofs -run "TestRATUnitTests"                 # RAT unit tests
go test -v ./op-e2e/faultproofs -run "TestRATMockWorkflow"              # RAT mock workflow

# Stress testing
go test -v ./op-e2e/faultproofs -run "TestRATStressTest"                # Stress test

# All E2E tests (run in background, time-consuming)
go test -v ./op-e2e/faultproofs -run "TestRAT.*"
```

## Detailed: TestRATDisputeGameVictoryE2E Execution Guide

### Basic Execution (Screen Output Only)

```bash
cd /optimism
go test -v ./op-e2e/faultproofs -run "TestRATDisputeGameVictoryE2E"
```

### Recommended Method: Simultaneous Output to Screen and File using tee

```bash
cd /optimism

# Run with 10-minute timeout and save logs to file
timeout 600s go test -v ./op-e2e/faultproofs -run "TestRATDisputeGameVictoryE2E" -timeout 10m | tee rat_test_log.txt
```

### Logs with Timestamps

For more detailed log analysis, you can include timestamps:

```bash
cd /optimism

# Save logs with timestamps
timeout 1200s go test -v ./op-e2e/faultproofs -run "TestRATDisputeGameVictoryE2E" -timeout 20m | \
  while IFS= read -r line; do echo "$(date '+%Y-%m-%d %H:%M:%S') $line"; done | \
  tee rat_test_log_with_timestamp.txt
```

## Timeout Configuration

RAT E2E tests require sufficient time as they simulate complex blockchain environments:

- **Recommended Timeout**: 10 minutes (600 seconds) - for stable test completion
- **Command**: `timeout 600s` (system level) + `-timeout 10m` (Go test level)

## Test Phase-by-Phase Log Analysis

RAT E2E tests consist of the following phases:

### Phase 1: System Deployment Verification
- RAT contract deployment and verification
- Address and code length verification

### Phase 2: Challenger Setup
- Setting up challenger with sufficient stake

### Phase 3: Invalid State Root Generation
- Creating shallow invalid state root that ensures output-level resolution

### Phase 4: Waiting for RAT Attention Test Trigger
- Waiting for RAT's attention mechanism activation

### Phase 5: RAT Attention Mechanism Testing
- Testing RAT attention mechanism without full challenger execution

### Phase 6: Challenge Period Wait
- Waiting for challenge period to elapse until game resolution is possible

### Phase 7: Dispute Game Resolution
- **Active Resolution Required**: Game does not resolve automatically
- **Resolution Order**:
  1. `game.ResolveClaim(ctx, 0)` - Resolve root claim first
  2. `game.Resolve(ctx)` - Resolve entire game
- Final state: CHALLENGER_WINS

## Log File Locations

### Generated Log Files

1. **Main Test Log**: `rat_test_log.txt` (created with above command)
2. **Temporary Test Directory**: `/var/folders/.../TestRATDisputeGameVictoryE2E*/`
   - Separate directory created for each subtest
   - Contains blockchain state and database files
   - Binary files, not suitable for text log analysis

### Log File Monitoring

Real-time log monitoring:

```bash
# Monitor running test logs in real-time
tail -f rat_test_log.txt

# Filter and view specific phases only
grep "Phase [0-9]:" rat_test_log.txt

# Check for errors or failure messages
grep -E "(ERROR|FAIL|failed)" rat_test_log.txt

# Check test completion status
grep -E "(PASS|FAIL|Complete Victory)" rat_test_log.txt

# View phase progress summary
grep -E "(Phase [0-9]|Complete Victory|PASS.*TestRATDisputeGameVictoryE2E)" rat_test_log.txt

# Track test phase progress (actual log pattern)
grep -E "(Phase [0-9]|Complete Victory Scenario)" rat_test_log.txt
```

## Test Phase Progress Tracking

You can monitor test progress using these actual log patterns from the code:

```bash
# Expected phase-by-phase progress pattern:
=== RUN TestRATDisputeGameVictoryE2E
=== RAT-DisputeGame Complete Victory Scenario E2E ===
Phase 1: Verifying full system deployment
Phase 2: Setting up challenger with sufficient stake
Phase 3: Creating shallow invalid state root to guarantee output-level resolution
Phase 4: Waiting for RAT to trigger attention test
Phase 5: Testing RAT attention mechanism without full challenger execution
Phase 6: Waiting for challenge period to elapse...
Phase 7: Resolving dispute game to CHALLENGER_WINS...
Phase 7.5: Testing withdrawal rejection for invalid state root
Phase 8: Verifying system is ready for next dispute cycle
=== RAT-DisputeGame Complete Victory Scenario PASSED ===

# Quick phase tracking command:
grep -E "(Phase [0-9])" rat_test_log.txt

# Check completion status:
grep "Complete Victory Scenario PASSED" rat_test_log.txt
```

## Subtest Description

### mt-cannon vs mt-cannon-next

RAT E2E tests run two subtests in parallel:

- **mt-cannon**: Current CANNON fault proof system
- **mt-cannon-next**: Next-generation CANNON fault proof system

Both systems are verified to ensure RAT functionality works correctly.

## Troubleshooting

### When Timeout Occurs

1. **Increase Timeout Duration**: Extend from 20 to 30 minutes
   ```bash
   timeout 1800s go test -v ./op-e2e/faultproofs -run "TestRATDisputeGameVictoryE2E" -timeout 30m | tee rat_test_log.txt
   ```

2. **When Stuck at Specific Phase**: Check the last completed phase in logs
   ```bash
   grep "Phase [0-9]:" rat_test_log.txt | tail -5
   ```

3. **Resource Shortage**: Check and increase Docker memory allocation

### Log Analysis Tips

```bash
# Check test execution time
grep -E "=== (RUN|CONT)" rat_test_log.txt

# Extract only success/failure messages
grep -E "(✅|❌|ERROR|SUCCESS)" rat_test_log.txt

# Analyze time spent per phase (from timestamped logs)
grep "Phase [0-9]:" rat_test_log_with_timestamp.txt
```

## Additional Command Options

### Run Specific Subtests Only

```bash
# Test mt-cannon only
go test -v ./op-e2e/faultproofs -run "TestRATDisputeGameVictoryE2E/mt-cannon$" | tee rat_cannon_log.txt

# Test mt-cannon-next only
go test -v ./op-e2e/faultproofs -run "TestRATDisputeGameVictoryE2E/mt-cannon-next$" | tee rat_cannon_next_log.txt
```

### Include Detailed Debug Information

```bash
# Run with Go test detailed information
go test -v -x ./op-e2e/faultproofs -run "TestRATDisputeGameVictoryE2E" | tee rat_debug_log.txt
```

This guide enables you to effectively run and monitor RAT E2E tests.