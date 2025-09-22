# RAT E2E Testing Guide

This guide provides comprehensive instructions for running RAT (Randomized Attention Test) E2E tests in the Optimism system.

## Overview

RAT E2E tests validate the complete dispute game mechanism and state root correction system by running full blockchain deployments with real geth nodes, challenging processes, and system integration.

**⚠️ Note**: E2E tests take 5-10 minutes each due to full blockchain deployment requirements.

## Prerequisites

- Optimism development environment set up
- Go 1.21+ installed
- Docker available for blockchain deployments

## Test Cache Management

Go caches test results when code hasn't changed. To see actual execution time instead of `(cached)`:

```bash
# Clear test cache before running tests
go clean -testcache
```

## Available E2E Tests

### Core RAT E2E Tests

```bash
# From project root
go clean -testcache

# Individual test scenarios
go test -v ./op-e2e/faultproofs -run "TestRATSuccessScenarioE2E"        # Success scenario
go test -v ./op-e2e/faultproofs -run "TestRATFailureScenarioE2E"        # Failure scenario
go test -v ./op-e2e/faultproofs -run "TestRATSimpleE2E"                 # Simple verification
go test -v ./op-e2e/faultproofs -run "TestRATDisputeGameVictoryE2E"     # 🆕 Complete victory scenario
go test -v ./op-e2e/faultproofs -run "TestRATUnitTests"                 # RAT unit tests (fast)
go test -v ./op-e2e/faultproofs -run "TestRATMockWorkflow"              # RAT mock workflow test (fast)

# All RAT E2E tests
go test -v ./op-e2e/faultproofs -run "TestRAT.*"
```

### 🆕 TestRATDisputeGameVictoryE2E: Complete Victory Scenario

**Status**: ✅ Production-Ready (8 phases implemented)
**Location**: `op-e2e/faultproofs/rat_e2e_test.go:437`
**Execution Time**: ~5-10 minutes

**Full Scenario**: Invalid Proposer State Root → RAT Triggers → Challenger Selection → Dispute Game Victory → Bond Recovery → Withdrawal Rejection

#### 8-Phase Complete Victory Workflow

**Phase 1: System Deployment Verification**
- Verifies RAT contract is properly deployed and configured
- Validates integration between RAT, DisputeGameFactory, and OptimismPortal
- Confirms all system components are operational and ready

**Phase 2: Challenger Qualification Setup**
- Stakes 5 ETH to RAT contract for challenger qualification
- Ensures sufficient balance for both game participation and RAT bond requirements
- Records initial challenger state and validates eligibility

**Phase 3: Shallow Invalid State Root Creation**
- Creates obviously invalid root claim (`0x01`) for guaranteed output-level resolution
- Uses TestOutputCannonGame proven success pattern to avoid VM execution issues
- Starts dispute game at Block 4 with invalid claim, triggering RAT attention mechanism

**Phase 4: RAT Attention Test Activation & Verification**
- RAT automatically detects invalid root and triggers attention test
- Confirms RAT selected correct challenger (`require.Equal`)
- Verifies exact bond amount was deducted from challenger stake
- Validates 3 core RAT functions: detection, selection, and bond management

**Phase 5: RAT Core Functionality Summary Confirmation**
- Confirms the 3 core RAT functions completed successfully in Phase 4
- Summary verification step ensuring attention test mechanism worked correctly
- No new verification, just confirms previous phase completions

**Phase 6: Challenge Period Management**
- Advances time through 20-minute challenge period (fast dispute game setting)
- Uses time travel mechanism to skip wait period for test efficiency
- Transitions game to resolution-ready state

**Phase 7: Actual Dispute Game Resolution**
- Resolves dispute game to `CHALLENGER_WINS` status through proper mechanism
- Shallow invalid root claim automatically loses, challenger wins
- FaultDisputeGame resolution automatically triggers RAT.ResolveClaim() callback

**Phase 7.5: Withdrawal Rejection Verification**
- Tests OptimismPortal withdrawal rejection for CHALLENGER_WINS games
- Verifies that invalid state root based withdrawals are blocked by the system
- Confirms the core security mechanism: preventing fraudulent withdrawals

**Phase 8: Bond Recovery & System Readiness**
- Verifies automatic RAT bond restoration through game resolution callback
- Confirms challenger remains valid for future disputes and system readiness
- Tests system preparedness for next dispute cycle

#### Key Features

- **Shallow Resolution**: Uses `common.Hash{0x01}` to avoid VM execution complexity
- **Real Game Resolution**: Proper FaultDisputeGame resolution (not simulation)
- **Automatic Callbacks**: Game resolution triggers RAT.ResolveClaim() automatically
- **Security Validation**: Withdrawal rejection from CHALLENGER_WINS games

```bash
# Run complete victory scenario (5-10 minutes)
go test -v ./op-e2e/faultproofs -run "TestRATDisputeGameVictoryE2E"
```

## Important Configuration for Challenger Testing

### AllowInvalidPrestate Setting

When testing dispute games with invalid root claims (like in `TestRATDisputeGameVictoryE2E`), the challenger needs to be configured to participate in games even when the prestate doesn't match expected values.

**Default Behavior**:
- `AllowInvalidPrestate = false`: Challenger refuses to participate if prestate validation fails
- Game remains stuck with no challenger activity

**Required for RAT Testing**:
- `AllowInvalidPrestate = true`: Challenger participates despite prestate mismatches
- Enables testing with intentionally invalid root claims

**In Code** (automatically set in E2E helper):
```go
// op-e2e/e2eutils/challenger/helper.go:185
cfg.AllowInvalidPrestate = true
```

**For Manual Challenger Setup**:
```bash
# Command line flag
--unsafe-allow-invalid-prestate
```

**For Kurtosis Devnet (simple.yaml)**:
```yaml
challengers:
  challenger:
    enabled: true
    image: {{ localDockerImage "op-challenger" }}
    participants: "*"
    cannon_prestates_url: {{ localPrestate.URL }}
    cannon_trace_types: ["cannon"]
    extra_params: ["--unsafe-allow-invalid-prestate"]
```

**💡 When to Use**:
- ✅ **Testing scenarios** with invalid root claims
- ✅ **Development environments** with mismatched prestates
- ❌ **Production environments** (security risk)

### Prestate Validation Process

1. **Challenger starts** → `ValidatePrestate()` called
2. **Validation fails** → Error: "absolute prestate does not match"
3. **With AllowInvalidPrestate=false** → Challenger exits
4. **With AllowInvalidPrestate=true** → Warning logged, challenger continues

## Test Output Interpretation

### Successful Test Output Example

```
=== RUN   TestRATDisputeGameVictoryE2E
Phase 1: Verifying full system deployment
Phase 2: Setting up challenger qualification
Phase 3: Creating shallow invalid state root
Phase 4: Waiting for RAT to trigger attention test
Phase 5: RAT core functionality summary confirmation
Phase 6: Waiting for challenge period to elapse
Phase 7: Resolving dispute game to CHALLENGER_WINS
Phase 7.5: Testing withdrawal rejection for invalid state root
Phase 8: Verifying system is ready for next dispute cycle
=== RAT-DisputeGame Complete Victory Scenario PASSED ===
--- PASS: TestRATDisputeGameVictoryE2E (XXXs)
```

### Common Issues and Solutions

**1. Test Timeout**
- **Symptom**: Test runs for 5+ minutes and times out
- **Cause**: System startup delays or network issues
- **Solution**: Retry test, check Docker resources

**2. VM Execution Errors**
- **Symptom**: "signal: killed" errors during dispute resolution
- **Cause**: Complex execution trace generation
- **Solution**: Tests use shallow resolution (`0x01` hash) to avoid this

**3. Prestate Validation Failures**
- **Symptom**: Challenger exits early with prestate errors
- **Cause**: `AllowInvalidPrestate` not set
- **Solution**: Verify E2E helper sets the flag correctly

## Performance Tips

1. **Docker Resources**: Ensure sufficient CPU/memory for multiple blockchain nodes
2. **Test Isolation**: Run tests individually for clearer output
3. **Cache Management**: Use `go clean -testcache` for accurate timing
4. **Parallel Execution**: Avoid running multiple E2E tests simultaneously

## Related Documentation

- [RAT Testing Implementation Plan](./rat-testing-implementation-plan.md) - Complete test coverage and progress tracking
- [Main README](../README.md) - Full development setup guide
- [Code Implementation](../../op-e2e/faultproofs/rat_e2e_test.go) - Source code

## Troubleshooting

If tests fail consistently:

1. **Check Prerequisites**: Ensure development environment is properly set up
2. **Verify Docker**: Confirm Docker daemon is running and has sufficient resources
3. **Clean State**: Run `go clean -testcache` and retry
4. **Check Logs**: Review test output for specific error messages
5. **Resource Constraints**: Close other resource-intensive applications

For implementation details and code-level documentation, see the [RAT Testing Implementation Plan](./rat-testing-implementation-plan.md).