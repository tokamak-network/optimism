# Post-Deployment Verification Guide

**Last Updated**: September 17, 2025
**Version**: 1.0
**Target**: Optimism Devnet Developers

## Overview

This guide explains the automated verification process to be performed after Optimism devnet deployment. It verifies that the 20-minute dispute game configuration has been correctly applied and automates actual dispute game resolution testing.

## Automated Verification Sequence

### Step 1: Deploy New Devnet

```bash
# Deploy devnet in clean environment
cd /optimism/kurtosis-devnet
AUTOFIX=true just simple-devnet
```

**Verification points**:
- ✅ Kurtosis engine startup and enclave creation
- ✅ Contract bundle build completion
- ✅ Prestate build completion (for CANNON)
- ✅ 6 Docker image builds (op-faucet, op-node, op-proposer, op-challenger, op-deployer, op-batcher)

### Step 2: Check Devnet Service Status

```bash
# Verify all services are in RUNNING state
kurtosis enclave inspect simple-devnet

# Expected result: All services in RUNNING state
# - L1 services: el-1-geth-teku, cl-1-teku-geth
# - L2 services: op-el-*-node0-op-geth, op-cl-*-node0-op-node
# - OP Stack services: op-batcher-*, op-proposer-*, op-challenger-*
# - Other services: op-faucet
```

**Expected output**:
```
Name:            simple-devnet
UUID:            [UUID]
Status:          RUNNING
Creation Time:   [timestamp]

========================================== User Services ==========================================
UUID   Name                                    Ports   Status
...    el-1-geth-teku                         ...     RUNNING
...    cl-1-teku-geth                         ...     RUNNING
...    op-el-*-node0-op-geth                  ...     RUNNING
...    op-cl-*-node0-op-node                  ...     RUNNING
...    op-batcher-*                           ...     RUNNING
...    op-proposer-*                          ...     RUNNING
...    op-challenger-*                        ...     RUNNING
...    op-faucet                              ...     RUNNING
```

### Step 3: Auto-fix Traefik Network Errors

```bash
# Check and auto-fix Traefik network issues
cd /optimism/kurtosis-devnet
just fix-traefik
```

**Fixed issues**:
- Traefik reverse proxy container restart
- Docker network ID mismatch resolution

### Step 4: Contract Configuration Verification

**🚀 Using Automated Script (Recommended)**

```bash
cd /Users/zena/tokamak-projects/optimism/op-challenger/scripts
./verify-contract-settings.sh
```

**⚠️ Kurtosis Version Compatibility Issues**

If you encounter the following error:
```
ERRO[2025-09-25T12:25:10+09:00] The engine server API version that the CLI expects, '1.8', doesn't match the running engine server API version, '1.11'
```

**Solution:**
```bash
# Method 1: Use latest kurtosis (recommended)
export PATH="/usr/local/bin:$PATH"
./verify-contract-settings.sh

# Method 2: Install latest version with mise
mise install kurtosis@1.11.1
mise use kurtosis@1.11.1

# Method 3: Execute with absolute path
/usr/local/bin/kurtosis version  # Check version first
# Use absolute path in script
```

**💡 Cause**: Version mismatch between old kurtosis(1.8.1) installed by `mise` and running engine(1.11.1)

**Verification items:**
- ✅ L1 RPC connection status
- ✅ Contract address extraction and verification
- ✅ Actual created game type (CANNON verification)
- ✅ Dispute Game timing configuration (20min/5min)
- ✅ Test account balance
- ✅ Contract version

**💡 For detailed manual verification**: See [Contract Verification Detailed Guide](contract-verification-detailed.md).

**⚠️ Important: Pre-deployment Configuration Check**

For testing, verify the following configurations are properly set:

- **L1 Account Funding**: `prefunded_accounts` setting in `simple.yaml`
- **20-Minute Dispute Games**: Timing overrides setting in `simple.yaml`
- **CANNON Game Type**: `proposer_params.game_type: 0` setting

**Detailed configuration method**: See [Fast Dispute Game Setup Guide](fast-dispute-game-setup.md).

### Step 5: Overall Game Status Check

After contract configuration is successfully verified, check the status of all currently created games.

**🔍 Overall Game Status Check:**

```bash
cd /Users/zena/tokamak-projects/optimism/op-challenger/scripts

# Check current status of all games
./check-all-games.sh

# Check games in specific enclave
./check-all-games.sh my-devnet
```

**Verification items:**
- ✅ Total number of games and latest game status
- ✅ Which games are in IN_PROGRESS state (resolution targets)
- ✅ Creation time and elapsed time
- ✅ Game statistics (in-progress/resolved ratio)

### Step 6: Specific Game Auto-Resolve Execution

Select an IN_PROGRESS game identified in Step 5 and execute automatic resolution.

**🚀 Using Auto-resolve Script:**

```bash
cd /Users/zena/tokamak-projects/optimism/op-challenger/scripts

# Use game address identified in Step 5
# Example: ./auto-resolve-game.sh [GAME_ADDRESS] 20 [L1_RPC] [PRIVATE_KEY]
./auto-resolve-game.sh 0xf4601FF6867301F0496baCe8F108e76C5e1969a8 20 http://127.0.0.1:64046 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

**💡 For detailed auto-resolve usage**: See [Auto-Resolve Script Guide](auto-resolve-script-guide.md).

### Step 7: Resolution Result Verification

Verify that the game was successfully resolved after auto-resolve execution.

**🔍 Check Resolved Games:**

```bash
cd /Users/zena/tokamak-projects/optimism/op-challenger/scripts

# Re-check overall game status (verify statistics update)
./check-all-games.sh

# Check detailed results of specific game
./check-game-state.sh [RESOLVED_GAME_ADDRESS]
```

**Verification items:**
- ✅ Game status changed to DEFENDER_WINS
- ✅ Resolution completion time and total duration
- ✅ Increase in resolved game count in game statistics
- ✅ Root claim and final result

**Expected results:**
- 🟢 **DEFENDER_WINS**: Normal result when no challenger exists
- ⏰ **Duration**: Approximately 20 minutes (maxClockDuration)
- 📊 **Statistics**: Resolved game count +1

## Post-Deployment Verification Result Interpretation

### Successful Deployment Indicators

| Item | Expected Value | Meaning |
|------|----------------|---------|
| `Actual Game Type` | `0` | Using CANNON type dispute game |
| `getDeploymentVersion()` | `"v2.0-fixed-disputeGameType"` | Modified contract deployed (optional) |
| `maxClockDuration` | `1200` | 20-minute dispute game configuration |
| `clockExtension` | `300` | 5-minute extension time configuration |
| Account Balance | `> 0 ETH` | Test accounts properly funded |
| Game Status | `0` (IN_PROGRESS) | Game normally created and in progress |

**Note**: `respectedGameType` being 1 is also normal. What matters is verifying that the actual created game type is 0 (CANNON).

## Related Documentation

- [Contract Configuration Detailed Verification Guide](contract-verification-detailed.md) - Detailed contract configuration verification methods
- [Fast Dispute Game Setup Guide](fast-dispute-game-setup.md) - 20-minute dispute game configuration guide
- [Auto-Resolve Script Guide](auto-resolve-script-guide.md) - Auto-resolve script usage guide
- **[Output Root vs State Root Detailed Explanation](output-root-vs-state-root-explanation.md)** - Explanation of differences between proposer submission values and L2 state root

---

*This guide provides a systematic method to verify that all configurations have been correctly applied after Optimism devnet deployment.*