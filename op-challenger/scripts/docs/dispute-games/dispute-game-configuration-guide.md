# Dispute Game Configuration Guide

**Last Updated**: September 15, 2025
**Version**: 1.1
**Target**: Optimism Devnet Developers

## Overview

This guide explains how to configure dispute game parameters in Optimism devnet deployments using `simple.yaml`. These settings control the behavior and timing of fault dispute games.

> Important: When deploying via `kurtosis-devnet` using the `ethpandaops/optimism-package`, the `op_contract_deployer_params.overrides` currently only accepts two fields: `faultGameAbsolutePrestate` and `vmType`. Adding other keys like `faultGameMaxClockDuration`, `faultGameClockExtension`, `faultGameMaxDepth`, `faultGameSplitDepth`, or `respectedGameType` will fail with an error similar to:
>
> `Invalid parameter faultGameClockExtension for overrides. Allowed fields: ["faultGameAbsolutePrestate", "vmType"]`
>
> Workaround: keep only the allowed keys in `simple.yaml`. To tweak timing/depth parameters, run `op-deployer` directly (see "Command Line Equivalents") or use a package/version that exposes these settings.

## Configuration Location

All dispute game settings are configured in the `op_contract_deployer_params.overrides` section of `simple.yaml`:

```yaml
op_contract_deployer_params:
  image: {{ localDockerImage "op-deployer" }}
  l1_artifacts_locator: {{ localContractArtifacts "l1" }}
  l2_artifacts_locator: {{ localContractArtifacts "l2" }}
  overrides:
    # Dispute game parameters go here
    faultGameAbsolutePrestate: {{ localPrestate.Hashes.prestate_mt64 }}
    vmType: "CANNON"
```

## Core Parameters

### 1. Game Duration Settings

#### `faultGameMaxClockDuration`
- **Description**: Maximum total time (chess clock) each player has to make all their moves
- **Default**: `302400` seconds (3.5 days)
- **Format**: Integer (seconds)
- ⚠ Not available via Kurtosis `simple.yaml` overrides. Use `op-deployer` CLI when deploying outside Kurtosis:

```bash
op-deployer deploy-chain \
  --dispute-max-clock-duration 600
```

**Recommended Values**:
| Environment | Value | Duration | Use Case |
|-------------|-------|----------|-----------|
| Testing | `120` | 2 minutes | Rapid testing |
| Development | `600` | 10 minutes | Development debugging |
| Staging | `1800` | 30 minutes | Pre-production |
| Production | `302400` | 3.5 days | Live network |

#### `faultGameClockExtension`
- **Description**: Time added to a player's clock when they make a move
- **Default**: `10800` seconds (3 hours)
- **Format**: Integer (seconds)
- ⚠ Not available via Kurtosis `simple.yaml` overrides. Use `op-deployer` CLI when deploying outside Kurtosis:

```bash
op-deployer deploy-chain \
  --dispute-clock-extension 3600
```

### 2. Game Structure Settings

#### `faultGameMaxDepth`
- **Description**: Maximum depth of the dispute game tree
- **Default**: `73`
- **Format**: Integer
- ⚠ Not available via Kurtosis `simple.yaml` overrides. Use `op-deployer` CLI when deploying outside Kurtosis:

```bash
op-deployer deploy-chain \
  --dispute-max-game-depth 73
```

#### `faultGameSplitDepth`
- **Description**: Depth at which the game transitions from bisection to execution
- **Default**: `30`
- **Format**: Integer
- ⚠ Not available via Kurtosis `simple.yaml` overrides. Use `op-deployer` CLI when deploying outside Kurtosis:

```bash
op-deployer deploy-chain \
  --dispute-split-depth 30
```

### 3. VM and Prestate Settings

#### `faultGameAbsolutePrestate`
- **Description**: The absolute prestate hash for the dispute game
- **Default**: From prestate build
- **Format**: Hex hash (with 0x prefix)

```yaml
overrides:
  faultGameAbsolutePrestate: {{ localPrestate.Hashes.prestate_mt64 }}
```

#### `vmType`
- **Description**: Virtual machine type for dispute resolution
- **Default**: `"CANNON"`
- **Options**: `"CANNON"`, `"ALPHABET"`, `"CANNON-NEXT"`

```yaml
overrides:
  vmType: "CANNON"
```

### 4. Game Type Configuration

#### `respectedGameType`
- **Description**: The dispute game type that is respected by the system
- **Default**: `1` (PERMISSIONED)
- **Format**: Integer
- ⚠ Not available via Kurtosis `simple.yaml` overrides.

## Environment-Specific Configurations

### Development Environment
Optimized for fast iteration and debugging:

```yaml
op_contract_deployer_params:
  overrides:
    faultGameAbsolutePrestate: {{ localPrestate.Hashes.prestate_mt64 }}
    vmType: "CANNON"
```

If deploying without Kurtosis, set timing via CLI:

```bash
op-deployer deploy-chain \
  --dispute-max-clock-duration 600 \
  --dispute-clock-extension 300
```

### Testing Environment
Optimized for rapid test execution:

```yaml
op_contract_deployer_params:
  overrides:
    faultGameAbsolutePrestate: {{ localPrestate.Hashes.prestate_mt64 }}
    vmType: "CANNON"
```

If deploying without Kurtosis, set timing via CLI:

```bash
op-deployer deploy-chain \
  --dispute-max-clock-duration 120 \
  --dispute-clock-extension 60
```

### Staging Environment
Closer to production but faster for validation:

```yaml
op_contract_deployer_params:
  overrides:
    faultGameAbsolutePrestate: {{ localPrestate.Hashes.prestate_mt64 }}
    vmType: "CANNON"
```

If deploying without Kurtosis, set timing via CLI:

```bash
op-deployer deploy-chain \
  --dispute-max-clock-duration 1800 \
  --dispute-clock-extension 900
```

## Advanced Configuration

### Custom Dispute Parameters

For specialized testing scenarios:

```yaml
op_contract_deployer_params:
  overrides:
    # Standard parameters (Kurtosis-allowed)
    faultGameAbsolutePrestate: {{ localPrestate.Hashes.prestate_mt64 }}
    vmType: "CANNON"
```

Then, when deploying without Kurtosis, pass timing/structure via CLI:

```bash
op-deployer deploy-chain \
  --dispute-max-clock-duration 300 \
  --dispute-clock-extension 60 \
  --dispute-max-game-depth 73 \
  --dispute-split-depth 30
```

### Multiple Game Types

To support multiple dispute game types:

```yaml
chains:
  - id: "op-kurtosis"
    additionalDisputeGames:
      - gameType: 255
        absolutePrestate: "0x..."
        maxGameDepth: 50
        splitDepth: 14
        clockExtension: 0
        maxClockDuration: 1200
```

## Deployment Process

### 1. Edit Configuration
Update your `simple.yaml` file with allowed overrides:

```bash
vim /Users/zena/tokamak-projects/optimism/kurtosis-devnet/simple.yaml
```

### 2. Deploy Network
Apply changes by redeploying the entire network:

```bash
cd /Users/zena/tokamak-projects/optimism/kurtosis-devnet
just simple-devnet
```

### 3. Verify Configuration
Check that parameters were applied correctly:

```bash
# Get L1 RPC and game address from devnet description
source <(cat /tmp/devnet-desc/env.json | jq -r 'to_entries | map("export " + .key + "=" + (.value | @sh)) | .[]')

# Query game contract for max clock duration
cast call --rpc-url "$L1_RPC" "$GAME_ADDRESS" "maxClockDuration() returns (uint64)"
```

## Validation and Testing

### Parameter Validation
Verify your configuration before deployment:

```bash
# Check YAML syntax
python -c "import yaml; yaml.safe_load(open('simple.yaml'))"

# Verify allowed override parameters are present
grep -E "(faultGameAbsolutePrestate|vmType)" simple.yaml
```

### Game Lifecycle Testing

1. **Create Test Game**: Deploy a dispute game with your settings
2. **Monitor Duration**: Verify game respects clock limits
3. **Test Resolution**: Ensure games resolve within expected timeframes

### Common Test Scenarios

```bash
# Test 1: Quick resolution (honest proposer)
# Expected: Game resolves without challenger participation

# Test 2: Dispute scenario (with challenger)
# Expected: Game duration respects maxClockDuration setting

# Test 3: Timeout scenario
# Expected: Game times out after maxClockDuration + extensions
```

## Troubleshooting

### Common Issues

1. **Configuration Not Applied**
   - Verify YAML syntax is correct
   - Ensure complete redeployment occurred
   - Check deployment logs for errors

2. **Games Running Too Long**
   - Verify `faultGameMaxClockDuration` is set correctly
   - Check if `faultGameClockExtension` is too large
   - Confirm no cached contracts are being used

3. **Invalid Prestate Errors**
   - Ensure `faultGameAbsolutePrestate` matches built prestate
   - Verify prestate files are accessible on fileserver
   - Check prestate build completed successfully

### Debug Commands

```bash
# Check deployed game configuration
cast call --rpc-url "$L1_RPC" "$GAME_ADDRESS" "maxClockDuration() returns (uint64)"
cast call --rpc-url "$L1_RPC" "$GAME_ADDRESS" "clockExtension() returns (uint64)"
cast call --rpc-url "$L1_RPC" "$GAME_ADDRESS" "absolutePrestate() returns (bytes32)"

# Check game factory settings
cast call --rpc-url "$L1_RPC" "$GAME_FACTORY_ADDRESS" "gameImpls(uint32) returns (address)" 1
```

## Best Practices

### Development Guidelines

1. **Start Conservative**: Begin with longer durations, then optimize
2. **Environment Consistency**: Use consistent settings across team
3. **Document Changes**: Keep track of configuration changes
4. **Test Thoroughly**: Validate changes don't break existing functionality

### Security Considerations

1. **Minimum Durations**: Ensure legitimate disputes have adequate time
2. **Maximum Limits**: Prevent games from running indefinitely
3. **Production Values**: Use well-tested values for live networks
4. **Prestate Validation**: Always verify prestate integrity

## Reference

### Related Files
- **Configuration**: `/Users/zena/tokamak-projects/optimism/kurtosis-devnet/simple.yaml`
- **Standards**: `/Users/zena/tokamak-projects/optimism/op-deployer/pkg/deployer/standard/standard.go`
- **Flags**: `/Users/zena/tokamak-projects/optimism/op-deployer/pkg/deployer/manage/flags.go`

### Command Line Equivalents
Timing/depth parameters are set via command line when not using Kurtosis:

```bash
op-deployer deploy-chain \
  --dispute-max-clock-duration 600 \
  --dispute-clock-extension 300 \
  --dispute-max-game-depth 73 \
  --dispute-split-depth 30
```

### Environment Variables
Or via environment variables when not using Kurtosis:

```bash
export OP_DEPLOYER_DISPUTE_MAX_CLOCK_DURATION=600
export OP_DEPLOYER_DISPUTE_CLOCK_EXTENSION=300
```

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-09-02 | Initial configuration guide |