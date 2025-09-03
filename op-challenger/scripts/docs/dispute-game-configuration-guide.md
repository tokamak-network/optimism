# Dispute Game Configuration Guide

**Last Updated**: September 2, 2025  
**Version**: 1.0  
**Target**: Optimism Devnet Developers

## Overview

This guide explains how to configure dispute game parameters in Optimism devnet deployments using `simple.yaml`. These settings control the behavior and timing of fault dispute games.

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

```yaml
overrides:
  faultGameMaxClockDuration: 600  # 10 minutes for development
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

```yaml
overrides:
  faultGameClockExtension: 3600  # 1 hour extension per move
```

### 2. Game Structure Settings

#### `faultGameMaxDepth`
- **Description**: Maximum depth of the dispute game tree
- **Default**: `73`
- **Format**: Integer

```yaml
overrides:
  faultGameMaxDepth: 73  # Standard depth
```

#### `faultGameSplitDepth`
- **Description**: Depth at which the game transitions from bisection to execution
- **Default**: `30`
- **Format**: Integer

```yaml
overrides:
  faultGameSplitDepth: 30  # Standard split depth
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

```yaml
overrides:
  respectedGameType: 1  # PERMISSIONED game type
```

## Environment-Specific Configurations

### Development Environment
Optimized for fast iteration and debugging:

```yaml
op_contract_deployer_params:
  overrides:
    faultGameAbsolutePrestate: {{ localPrestate.Hashes.prestate_mt64 }}
    vmType: "CANNON"
    faultGameMaxClockDuration: 600      # 10 minutes
    faultGameClockExtension: 300        # 5 minutes per move
    respectedGameType: 1
```

### Testing Environment
Optimized for rapid test execution:

```yaml
op_contract_deployer_params:
  overrides:
    faultGameAbsolutePrestate: {{ localPrestate.Hashes.prestate_mt64 }}
    vmType: "CANNON"
    faultGameMaxClockDuration: 120      # 2 minutes
    faultGameClockExtension: 60         # 1 minute per move
    respectedGameType: 1
```

### Staging Environment
Closer to production but faster for validation:

```yaml
op_contract_deployer_params:
  overrides:
    faultGameAbsolutePrestate: {{ localPrestate.Hashes.prestate_mt64 }}
    vmType: "CANNON"
    faultGameMaxClockDuration: 1800     # 30 minutes
    faultGameClockExtension: 900        # 15 minutes per move
    respectedGameType: 1
```

## Advanced Configuration

### Custom Dispute Parameters

For specialized testing scenarios:

```yaml
op_contract_deployer_params:
  overrides:
    # Standard parameters
    faultGameAbsolutePrestate: {{ localPrestate.Hashes.prestate_mt64 }}
    vmType: "CANNON"
    
    # Timing parameters
    faultGameMaxClockDuration: 300      # 5 minutes
    faultGameClockExtension: 60         # 1 minute per move
    
    # Structure parameters
    faultGameMaxDepth: 73
    faultGameSplitDepth: 30
    
    # Game type
    respectedGameType: 1
    
    # Additional proof parameters
    withdrawalDelaySeconds: 604800      # 1 week
    proofMaturityDelaySeconds: 604800   # 1 week
    disputeGameFinalityDelaySeconds: 302400  # 3.5 days
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
Update your `simple.yaml` file with desired parameters:

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

# Verify required parameters are present
grep -E "(faultGameMaxClockDuration|faultGameAbsolutePrestate|vmType)" simple.yaml
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
All YAML overrides can also be set via command line:

```bash
op-deployer deploy-chain \
  --dispute-max-clock-duration 600 \
  --dispute-clock-extension 300 \
  --dispute-max-game-depth 73 \
  --dispute-split-depth 30
```

### Environment Variables
Or via environment variables:

```bash
export OP_DEPLOYER_DISPUTE_MAX_CLOCK_DURATION=600
export OP_DEPLOYER_DISPUTE_CLOCK_EXTENSION=300
```

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-09-02 | Initial configuration guide |