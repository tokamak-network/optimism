# Issue 005: Dispute Game Duration Configuration

**Date**: September 2, 2025
**Status**: RESOLVED
**Priority**: MEDIUM
**Component**: op-deployer, dispute games

## Issue Summary

The default dispute game duration is 302400 seconds (3.5 days), which is too long for development and testing environments. Need to make the game duration configurable via deployment settings.

## Background

### Current Behavior
- **Default Game Duration**: 302400 seconds (3.5 days)
- **Chess Clock Mechanism**: Each player gets time to make moves
- **Configuration**: Hardcoded in deployment standards

### Problem
- 3.5 days is too long for development testing
- Unable to test complete game lifecycle quickly
- Slows down development and debugging cycles

## Analysis

### Code Investigation
The game duration is controlled by `DisputeMaxClockDuration` parameter:

**File**: `/Users/zena/tokamak-projects/optimism/op-deployer/pkg/deployer/standard/standard.go:33`
```go
DisputeMaxClockDuration uint64 = 302400  // 3.5 days (84 hours)
```

**File**: `/Users/zena/tokamak-projects/optimism/op-deployer/pkg/deployer/manage/flags.go:77-82`
```go
DisputeMaxClockDurationFlag = &cli.Uint64Flag{
    Name:    "dispute-max-clock-duration",
    Usage:   "Maximum clock duration in seconds for dispute game timing. Defaults to the standard value.",
    EnvVars: deployer.PrefixEnvVar("DISPUTE_MAX_CLOCK_DURATION"),
    Value:   standard.DisputeMaxClockDuration,
}
```

### Configuration Path
The parameter can be overridden through:
1. **Command Line**: `--dispute-max-clock-duration`
2. **Environment Variable**: `OP_DEPLOYER_DISPUTE_MAX_CLOCK_DURATION`
3. ⚠ Kurtosis `simple.yaml` overrides do not support this key; only `faultGameAbsolutePrestate` and `vmType` are allowed.

## Solution

### Configuration Method
Use `op-deployer` CLI or environment variable when not deploying via Kurtosis:

```bash
op-deployer deploy-chain \
  --dispute-max-clock-duration 600
```

Or via environment variable:

```bash
export OP_DEPLOYER_DISPUTE_MAX_CLOCK_DURATION=600
op-deployer deploy-chain
```

### Recommended Values by Environment

| Environment | Duration | Seconds | Use Case |
|-------------|----------|---------|-----------|
| **Testing** | 2 minutes | `120` | Quick unit/integration tests |
| **Development** | 10 minutes | `600` | Development debugging |
| **Staging** | 30 minutes | `1800` | Pre-production testing |
| **Production** | 3.5 days | `302400` | Live network (default) |

### Implementation Details

**Parameter Mapping**:
- **YAML Key**: `faultGameMaxClockDuration`
- **Go Struct**: `DisputeMaxClockDuration`
- **Contract Parameter**: Maximum chess clock duration per player

**Code Reference**: `/Users/zena/tokamak-projects/optimism/op-deployer/pkg/deployer/integration_test/apply_test.go:271`
```go
{
    "faultGameMaxClockDuration",
    uint64Caster,
    chainState.PermissionedDisputeGameImpl,
},
```

### Processing Flow
1. **YAML Parsing**: `simple.yaml` → `GlobalDeployOverrides`
2. **Override Merging**: Combined with standard values
3. **Contract Deployment**: Applied during game contract deployment
4. **Runtime Behavior**: All new games use the configured duration

## Example Configurations

### Development Configuration
```bash
op-deployer deploy-chain --dispute-max-clock-duration 600
```

### Testing Configuration
```bash
op-deployer deploy-chain --dispute-max-clock-duration 120
```

### Multiple Overrides
```bash
op-deployer deploy-chain \
  --dispute-max-clock-duration 600 \
  --dispute-max-game-depth 73 \
  --dispute-split-depth 30 \
  --dispute-clock-extension 10800
```

## Verification

### 1. Check Deployment Configuration
```bash
# Verify CLI flag/env var used during deployment (check deployer logs)
grep -i "dispute-max-clock-duration" -r /tmp/devnet-desc/ || true
```

### 2. Query Contract State
```bash
# Check deployed game contract for duration setting
L1_RPC="http://127.0.0.1:50514"
GAME="0x9311252E0e9474382b48fFaAC144DB7E8AccD507"
cast call --rpc-url "$L1_RPC" "$GAME" "maxClockDuration() returns (uint64)"
```

### 3. Test Game Lifecycle
```bash
# Create and monitor game with shorter duration
# Game should resolve within configured time limit
```

## Important Notes

### 1. Deployment Requirement
- **Full Redeploy**: Changes require complete devnet redeployment
- **Not Hot-Swappable**: Cannot change duration of existing games
- **All Games Affected**: Setting applies to all newly created games

### 2. Security Considerations
- **Minimum Duration**: Should allow reasonable time for legitimate disputes
- **Maximum Duration**: Prevents games from running indefinitely
- **Production Values**: Use standard values for live networks

### 3. Testing Impact
- **Shorter Durations**: Enable faster test cycles
- **Coverage**: Test both timeout and normal resolution paths
- **Edge Cases**: Verify behavior at duration boundaries

## Related Configuration Parameters

### Chess Clock Settings
```bash
op-deployer deploy-chain \
  --dispute-max-clock-duration 600 \
  --dispute-clock-extension 10800
```

### Game Structure Settings
```bash
op-deployer deploy-chain \
  --dispute-max-game-depth 73 \
  --dispute-split-depth 30
```

## Files Modified

### Configuration Files
- `/Users/zena/tokamak-projects/optimism/kurtosis-devnet/simple.yaml`

### Reference Code
- `/Users/zena/tokamak-projects/optimism/op-deployer/pkg/deployer/standard/standard.go:33`
- `/Users/zena/tokamak-projects/optimism/op-deployer/pkg/deployer/manage/flags.go:77-82`
- `/Users/zena/tokamak-projects/optimism/op-deployer/pkg/deployer/integration_test/apply_test.go:271`

## Resolution Status
✅ **RESOLVED** - Dispute game duration is configurable via `op-deployer` CLI/env; Kurtosis `simple.yaml` supports only `faultGameAbsolutePrestate` and `vmType`.

## Usage Instructions

1. **Edit Configuration**: Add `faultGameMaxClockDuration` to `simple.yaml`
2. **Redeploy Network**: Run `just simple-devnet` to apply changes
3. **Verify Setting**: Check deployed contracts for correct duration
4. **Test Games**: Create games and verify they respect new duration