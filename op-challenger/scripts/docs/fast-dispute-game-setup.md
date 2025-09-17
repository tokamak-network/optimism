# Fast Dispute Game Setup Guide

**Last Updated**: September 16, 2025
**Version**: 1.0
**Target**: Optimism Devnet Developers

## Overview

This guide explains how to configure Optimism devnet with accelerated dispute game durations for fast testing and development. By default, dispute games run for 3.5 days (302400 seconds), which is impractical for development cycles. This configuration reduces game duration to 20 minutes while maintaining full functionality.

## Quick Setup

### 1. Configure Fast Dispute Games

Edit your `simple.yaml` configuration:

```yaml
op_contract_deployer_params:
  image: {{ localDockerImage "op-deployer" }}
  l1_artifacts_locator: {{ localContractArtifacts "l1" }}
  l2_artifacts_locator: {{ localContractArtifacts "l2" }}
  overrides:
    deployer:
      faultGameAbsolutePrestate: {{ localPrestate.Hashes.prestate_mt64 }}
      faultGameMaxClockDuration: 1200    # 20 minutes instead of 3.5 days
      faultGameClockExtension: 300       # 5 minutes extension per move
      preimageOracleChallengePeriod: 300 # 5 minutes challenge period
      vmType: "CANNON"
```

### 2. Update Template Configuration

Ensure your `devnet.yaml` template includes the global deploy overrides:

```yaml
op_contract_deployer_params:
  global_deploy_overrides:
    faultGameAbsolutePrestate: {{ dig "overrides" "deployer" "prestate" (localPrestate.Hashes.prestate_mt64) $context }}
{{- range $key, $value := dig "overrides" "deployer" (dict) $context }}
    {{ $key }}: {{ $value }}
{{- end }}
```

### 3. Deploy Devnet

```bash
cd /optimism/kurtosis-devnet
LOG_LEVEL=debug AUTOFIX=true just simple-devnet
```

### 4. Auto-Resolve Games

Use the provided script to automatically resolve games after the duration expires:

```bash
cd /optimism/op-challenger/scripts
./auto-resolve-game.sh 0x<GAME_ADDRESS>
```

## Key Configuration Parameters

### Timing Parameters

| Parameter | Default | Fast Config | Purpose |
|-----------|---------|-------------|---------|
| `faultGameMaxClockDuration` | 302400s (3.5 days) | 1200s (20 min) | Maximum total time per player |
| `faultGameClockExtension` | 10800s (3 hours) | 300s (5 min) | Time added per move |
| `preimageOracleChallengePeriod` | 86400s (24 hours) | 300s (5 min) | Challenge window for preimages |

### Validation Logic

The configuration must satisfy the constraint:
```
maxClockExtension ≤ maxClockDuration
```

Where:
```
maxClockExtension = max(clockExtension * 2, clockExtension + challengePeriod)
maxClockExtension = max(300 * 2, 300 + 300) = 600
```

Our configuration: `600 ≤ 1200` ✅

## Game Lifecycle

### 1. Game Creation (Automatic)
- Proposer creates games every 10 minutes
- Each game proposes a new L2 state root
- Game duration: 20 minutes

### 2. Challenge Period (Optional)
- Challengers have 20 minutes to dispute
- If no challenges: Game resolves as DEFENDER_WINS
- If challenged: Bisection game begins

### 3. Game Resolution (Manual)
- After 20 minutes, anyone can call `resolve()`
- Winning state root updates AnchorStateRegistry
- New games use updated root as checkpoint

## Auto-Resolve Script Usage

### Basic Usage
```bash
# Auto-resolve specific game
./auto-resolve-game.sh 0xb153c997C491E8E0e8eCe951f15449fe7a0Ea40E

# Custom timing (10 minutes)
./auto-resolve-game.sh 0xb153c997C491E8E0e8eCe951f15449fe7a0Ea40E 10

# Custom RPC endpoint
./auto-resolve-game.sh 0xb153c997C491E8E0e8eCe951f15449fe7a0Ea40E 20 http://127.0.0.1:8545
```

### Script Features
- ✅ Automatic game timing detection
- ✅ Status validation (prevents double-resolution)
- ✅ Background execution with PID tracking
- ✅ Transaction confirmation and status reporting
- ✅ Built-in safety buffer (30 seconds)

## Verification

### Check Game Configuration
```bash
# Get game address from logs
GAME_ADDRESS=$(kurtosis service logs simple-devnet op-challenger-challenger-2151908 | grep -o "0x[a-fA-F0-9]\{40\}" | head -1)

# Verify timing configuration
L1_RPC="http://127.0.0.1:57834"
cast call --rpc-url "$L1_RPC" "$GAME_ADDRESS" "maxClockDuration() returns (uint64)"  # Should be 1200
cast call --rpc-url "$L1_RPC" "$GAME_ADDRESS" "clockExtension() returns (uint64)"    # Should be 300
```

### Check AnchorStateRegistry Updates
```bash
# Check current anchor state
RPC_URL="http://127.0.0.1:57834" ADDR_FILE="/tmp/devnet-desc/env.json" ./check-anchor.sh

# Before first resolution: 0xdead
# After first resolution: Actual state root hash
```

## Performance Benefits

### Development Speed
- **Before**: 3.5 days per game cycle
- **After**: 20 minutes per game cycle
- **Speedup**: 252x faster iteration

### Testing Scenarios
- Complete game lifecycle testing in 20 minutes
- Multiple game scenarios per hour
- Rapid state root progression validation
- Fast withdrawal finalization testing

## Troubleshooting

### Common Issues

1. **InvalidClockExtension Error**
   ```
   ERROR: InvalidClockExtension() (revert data: 0x8d77ecac)
   ```
   **Solution**: Verify configuration satisfies `maxClockExtension ≤ maxClockDuration`

2. **Template Override Not Applied**
   ```
   Game still uses 302400s duration
   ```
   **Solution**: Check `devnet.yaml` template includes global_deploy_overrides section

3. **Game Never Resolves**
   ```
   Game stays IN_PROGRESS after 20 minutes
   ```
   **Solution**: Call `resolve()` manually or use auto-resolve script

### Debug Commands
```bash
# Check challenger logs
kurtosis service logs simple-devnet op-challenger-challenger-2151908 --tail 50

# Check proposer logs
kurtosis service logs simple-devnet op-proposer-2151908-op-kurtosis --tail 20

# Monitor game status
watch -n 10 "cast call --rpc-url http://127.0.0.1:57834 $GAME_ADDRESS 'status() returns (uint8)'"
```

## Files Modified

This setup required changes to the following files:

### Configuration Files
- `/optimism/kurtosis-devnet/simple.yaml` - Added fast timing parameters
- `/optimism/kurtosis-devnet/templates/devnet.yaml` - Updated override merging logic

### Scripts Created
- `/optimism/op-challenger/scripts/auto-resolve-game.sh` - Automated game resolution
- `/optimism/op-challenger/scripts/check-anchor.sh` - State root verification

### Build System
- `/optimism/kurtosis-devnet/justfile` - Added `--progress=plain` for Docker build visibility

## Technical Background

### Clock Extension Calculation
The system calculates maximum clock extension as:
```solidity
uint256 splitDepthExtension = clockExtension * 2;  // Bisection phase
uint256 maxGameDepthExtension = clockExtension + challengePeriod;  // Execution phase
uint256 maxClockExtension = Math.max(splitDepthExtension, maxGameDepthExtension);
```

### State Root Progression
1. **Genesis**: AnchorStateRegistry = `0xdead` (placeholder)
2. **First Game**: Proposes actual state root
3. **Resolution**: Updates AnchorStateRegistry to winning root
4. **Future Games**: Use confirmed root as starting point

This creates a checkpoint system where past state roots don't need re-validation.

## Best Practices

### Development Workflow
1. Deploy devnet with fast configuration
2. Let first game auto-resolve (establishes checkpoint)
3. Test scenarios with 20-minute game cycles
4. Use auto-resolve script for hands-free testing

### Production Notes
- Never use fast timing in production
- Standard 3.5-day duration provides security
- Fast config is for development/testing only

## References

- [Dispute Game Configuration Guide](dispute-game-configuration-guide.md)
- [Issue 005: Duration Configuration](../issue/005-dispute-game-duration-configuration.md)
- [Auto-Resolve Script](../auto-resolve-game.sh)
- [Anchor State Fix Guide](anchor-state-fix.md)

---

*This configuration enables rapid iteration on Optimism dispute game development while maintaining full system functionality.*