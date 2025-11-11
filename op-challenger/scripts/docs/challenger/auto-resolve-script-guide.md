# Auto-Resolve Script Guide


## Overview

The `auto-resolve-game.sh` script provides **complete automated resolution** of dispute games, including:
- ✅ Step 1: `resolveClaim(0,0)` - Resolve root claim
- ✅ Step 2: `resolve()` - Resolve entire game
- ✅ Step 3: `closeGame()` - Update anchorGame (🔥 NEW!)

This eliminates the manual steps and **automatically resolves Cold Starting state** by updating anchorGame after finality delay.

## Location

```
/optimism/op-challenger/scripts/auto-resolve-game.sh
```

## Quick Start

### Basic Usage
```bash
cd /optimism/op-challenger/scripts
chmod +x auto-resolve-game.sh

# Auto-resolve a specific game (20-minute default)
./auto-resolve-game.sh 0xb153c997C491E8E0e8eCe951f15449fe7a0Ea40E
```

### Find Game Address
```bash
# Get game address from challenger logs
GAME_ADDRESS=$(kurtosis service logs simple-devnet op-challenger-challenger-2151908 | grep -o "0x[a-fA-F0-9]\{40\}" | head -1)

# Use it with the script
./auto-resolve-game.sh $GAME_ADDRESS
```

## Command Line Options

### Syntax
```bash
./auto-resolve-game.sh <game_address> [wait_minutes] [l1_rpc_url] [private_key]
```

### Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `game_address` | ✅ Yes | - | Contract address of the dispute game |
| `wait_minutes` | ❌ No | `20` | Minutes to wait before resolution |
| `l1_rpc_url` | ❌ No | `http://127.0.0.1:57834` | L1 RPC endpoint |
| `private_key` | ❌ No | Test key | Private key for sending transactions |

### Examples

```bash
# Basic usage (20-minute wait)
./auto-resolve-game.sh 0xb153c997C491E8E0e8eCe951f15449fe7a0Ea40E

# Custom wait time (10 minutes)
./auto-resolve-game.sh 0xb153c997C491E8E0e8eCe951f15449fe7a0Ea40E 10

# Custom RPC URL
./auto-resolve-game.sh 0xb153c997C491E8E0e8eCe951f15449fe7a0Ea40E 20 http://127.0.0.1:8545

# Full customization
./auto-resolve-game.sh 0xb153c997... 15 http://127.0.0.1:8545 0x1234...
```

## Features

### ✅ Smart Timing Detection
- Automatically reads game creation time from contract
- Calculates exact wait time based on game duration
- Adds 30-second safety buffer to avoid timing issues

### ✅ Status Validation
- Checks current game status before scheduling
- Exits early if game is already resolved
- Prevents double-resolution attempts

### ✅ Complete Resolution Process (3 Steps)
1. **resolveClaim(0,0)** - Resolves root claim
2. **resolve()** - Resolves entire game
3. **closeGame()** - Updates anchorGame (🔥 NEW!)

### 🔥 NEW: Automatic anchorGame Update
- Detects AnchorStateRegistry automatically
- Waits for finality delay (e.g., 7 days production, 30-60s devnet)
- Calls `closeGame()` to update anchorGame
- Verifies Cold Starting state resolution
- Confirms anchor root changed from 0xdead...

### ✅ Background Execution
- Runs resolution in background process
- Provides process PID for monitoring
- Non-blocking operation - continue other work
- **Process automatically terminates** after all steps complete

### ✅ Transaction Management
- Sends all transactions with proper error handling
- Confirms transaction success/failure
- Reports final game status and anchorGame status
- Shows detailed verification results

### ✅ Error Handling
- Validates all input parameters
- Handles RPC connection errors
- Gracefully handles missing AnchorStateRegistry
- Provides clear error messages and usage help
- Falls back to manual instructions if needed

## Script Output

### Startup Information
```
🎮 Auto Resolve Dispute Game
================================
📍 Game Address: 0xb153c997C491E8E0e8eCe951f15449fe7a0Ea40E
⏰ Wait Duration: 20 minutes
🌐 L1 RPC: http://127.0.0.1:57834
🔑 Private Key: 0x59c6995e...

🔍 Checking game status...
📅 Game created at: 2025-09-16 18:27:39
🕐 Current time: 2025-09-16 18:40:15
⏳ Elapsed time: 756 seconds (12m 36s)
⏳ Time until resolution: 444 seconds (7m 24s)
🟡 Game Status: IN_PROGRESS

⏰ Scheduling resolution for: 2025-09-16 18:48:09 (+30s buffer)
🤖 Waiting 474 seconds...
🚀 Background process started (PID: 12345)
📝 You can monitor progress or kill with: kill 12345
```

### Resolution Execution
```
🎯 Step 1: Resolving root claim (index 0)...
✅ resolveClaim successful: 0x1234...
⏳ Waiting 2 seconds before resolve()...

🎯 Step 2: Resolving entire game...
✅ Resolve transaction sent!
📄 Transaction hash: 0xabcd1234...
⏳ Waiting for transaction confirmation...

🎯 Resolution Results:
====================
🟢 Final Status: DEFENDER_WINS
⏰ Resolution completed at: Mon Sep 16 18:48:09 KST 2025
🕐 Total duration: 1200 seconds (20m 0s)

📊 Game Details:
   🌳 Total claims: 1
   🎯 Root claim: 0xabc...
   📦 L2 block: 100

✅ Step 2 completed: Game resolved!

🔥 Step 3: Preparing to call closeGame()...
=========================================
✅ AnchorStateRegistry found: 0xdef...
⏳ Finality delay: 60 seconds (1 minutes)
⏰ Waiting for finality delay...
✅ Game is finalized, calling closeGame()...
✅ closeGame() successful!
📄 Transaction: 0x5678...

🎉 SUCCESS: anchorGame updated!
   New anchorGame: 0xb153c997...
   ✅ This game is now the anchor!
   ✅ Anchor root is valid: 0x03a1a13511403f20...

🎊 Cold Starting state resolved!
🎊 All new games will now use valid starting root

🎉 Auto-resolve completed successfully!
```

## Game Status Codes

| Code | Status | Description |
|------|--------|-------------|
| `0` | `IN_PROGRESS` | Game is running, resolution not yet possible |
| `1` | `CHALLENGER_WINS` | Challenger successfully disputed the claim |
| `2` | `DEFENDER_WINS` | Original claim was correct (no successful challenge) |

## Background Process Management

### Process Lifecycle
- **Automatic termination**: Background process automatically terminates after resolution completes
- **No manual cleanup needed**: Process exits cleanly with success/failure status
- **Monitor while running**: Use PID to check status during waiting period

### Monitor Progress
```bash
# Check if process is still running
ps aux | grep 12345

# Kill background process if needed (only during waiting period)
kill 12345

# Check all auto-resolve processes
ps aux | grep auto-resolve-game
```

### Multiple Games
```bash
# Schedule multiple games simultaneously
./auto-resolve-game.sh 0xgame1... 20 &
./auto-resolve-game.sh 0xgame2... 20 &
./auto-resolve-game.sh 0xgame3... 20 &

# Monitor all background jobs
jobs
```

## Integration Examples

### Development Workflow
```bash
#!/bin/bash
# Complete dispute game testing workflow

# 1. Deploy devnet
cd /optimism/kurtosis-devnet
AUTOFIX=true just simple-devnet

# 2. Wait for first game creation
sleep 60

# 3. Get game address and schedule auto-resolve
GAME_ADDRESS=$(kurtosis service logs simple-devnet op-challenger-challenger-2151908 | grep -o "0x[a-fA-F0-9]\{40\}" | head -1)
cd /optimism/op-challenger/scripts
./auto-resolve-game.sh $GAME_ADDRESS

# 4. Continue with other testing while game resolves in background
echo "Game $GAME_ADDRESS scheduled for auto-resolution"
echo "Continuing with other tests..."
```

### Continuous Testing
```bash
#!/bin/bash
# Monitor and auto-resolve all new games

while true; do
    # Find new IN_PROGRESS games
    GAMES=$(kurtosis service logs simple-devnet op-challenger-challenger-2151908 --tail 100 | grep -o "0x[a-fA-F0-9]\{40\}" | sort -u)

    for game in $GAMES; do
        # Check if already being monitored
        if ! ps aux | grep -q "$game"; then
            echo "Scheduling auto-resolve for new game: $game"
            ./auto-resolve-game.sh $game &
        fi
    done

    sleep 300  # Check every 5 minutes
done
```

## Troubleshooting

### Common Issues

1. **"Game address is required" Error**
   ```bash
   # Ensure game address is provided
   ./auto-resolve-game.sh 0x...  # ✅ Correct
   ./auto-resolve-game.sh        # ❌ Missing address
   ```

2. **"Could not fetch game creation time" Error**
   ```bash
   # Check RPC connection and game address
   cast call --rpc-url http://127.0.0.1:57834 0xGAME_ADDRESS "createdAt() returns (uint256)"
   ```

3. **"Game is already resolved" Warning**
   ```bash
   # Normal behavior - script exits safely
   # Check game status manually:
   cast call --rpc-url http://127.0.0.1:57834 0xGAME_ADDRESS "status() returns (uint8)"
   ```

4. **Transaction Fails**
   ```bash
   # Check account has ETH for gas
   cast balance 0xYOUR_ADDRESS --rpc-url http://127.0.0.1:57834

   # Verify game is ready for resolution
   # (20+ minutes after creation)
   ```

### Debug Mode
```bash
# Add debug output to script
bash -x ./auto-resolve-game.sh 0xGAME_ADDRESS
```

## Security Notes

### Private Keys
- Script uses test private key by default
- **Never use in production environments**
- Private key corresponds to funded test account in devnet

### Default Test Key
```
Private Key: 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
Address: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
```

This account is pre-funded in standard devnet configurations.

## Technical Implementation

### Key Functions

1. **Time Calculation**
   ```bash
   CREATED_AT=$(cast call --rpc-url "$L1_RPC" "$GAME_ADDRESS" "createdAt() returns (uint256)")
   REMAINING=$((CREATED_AT + WAIT_SECONDS - CURRENT_TIME))
   ```

2. **Status Check**
   ```bash
   GAME_STATUS=$(cast call --rpc-url "$L1_RPC" "$GAME_ADDRESS" "status() returns (uint8)")
   ```

3. **Resolution Transaction**
   ```bash
   cast send --rpc-url "$L1_RPC" --private-key "$PRIVATE_KEY" "$GAME_ADDRESS" "resolve()"
   ```

### Safety Features
- Input validation for all parameters
- Status verification before scheduling
- 30-second buffer to ensure resolution window is open
- Transaction confirmation with retry logic

## Post-Resolution Verification

### Check Game Status
```bash
# Basic game status after resolution
cast call --rpc-url $L1_RPC $GAME_ADDRESS "status() returns (uint8)"
# 0=IN_PROGRESS, 1=CHALLENGER_WINS, 2=DEFENDER_WINS

# Game creation and resolution timing
cast call --rpc-url $L1_RPC $GAME_ADDRESS "createdAt() returns (uint64)"
cast call --rpc-url $L1_RPC $GAME_ADDRESS "resolvedAt() returns (uint64)"
```

### ✅ Automatic closeGame() Execution

**🎉 Good News**: The script now **automatically** calls `closeGame()` after finality delay!

The script will:
1. ✅ Detect AnchorStateRegistry address from game contract
2. ✅ Query finality delay setting
3. ✅ Wait for finality delay to pass
4. ✅ Verify game is finalized
5. ✅ Call `closeGame()` automatically
6. ✅ Verify anchorGame updated
7. ✅ Confirm Cold Starting state resolved

**No manual intervention needed!** The script handles everything.

### Manual closeGame() (If Script Fails to Auto-Detect)

If the script cannot detect AnchorStateRegistry, it will show:
```
⚠️  Could not auto-detect AnchorStateRegistry address
💡 You may need to manually call closeGame() after finality delay

Manual steps:
  1. Wait for finality delay (check with AnchorStateRegistry.disputeGameFinalityDelaySeconds())
  2. Call: cast send $GAME_ADDRESS "closeGame()" --rpc-url $L1_RPC --private-key $PRIVATE_KEY
```

Then you can manually call:
```bash
# Get AnchorStateRegistry (if needed)
ANCHOR_STATE_REGISTRY="0x..."  # From deployment config

# Wait for finality delay
DELAY=$(cast call --rpc-url $L1_RPC $ANCHOR_STATE_REGISTRY "disputeGameFinalityDelaySeconds() returns (uint256)")
sleep $DELAY

# Call closeGame()
cast send --rpc-url $L1_RPC --private-key $PRIVATE_KEY $GAME_ADDRESS "closeGame()"
```

**Why closeGame() is critical**:
- `resolve()` only sets the game status
- `closeGame()` actually updates `anchorGame` in AnchorStateRegistry
- Without `closeGame()`, the system stays in Cold Starting state
- All new games will continue to use invalid 0xdead... starting root

**See Also**:
- [anchor-game-update-guide.md](../dispute-games/anchor-game-update-guide.md) - Complete update process
- [anchor-state-fix.md](./anchor-state-fix.md) - Cold Starting fix guide

### Check State Roots
```bash
# Root claim (disputed state root)
cast call --rpc-url $L1_RPC $GAME_ADDRESS "rootClaim() returns (bytes32)"

# Absolute prestate (starting point)
cast call --rpc-url $L1_RPC $GAME_ADDRESS "absolutePrestate() returns (bytes32)"

# L2 block number this game represents
cast call --rpc-url $L1_RPC $GAME_ADDRESS "l2BlockNumber() returns (uint256)"
```

### Check Game Tree State
```bash
# Number of claims in the dispute tree
cast call --rpc-url $L1_RPC $GAME_ADDRESS "claimDataLen() returns (uint256)"

# Get specific claim data (index 0 = root claim)
cast call --rpc-url $L1_RPC $GAME_ADDRESS "claimData(uint256) returns (uint32,address,uint128,uint128,bytes32,uint256,uint256)" 0
# Returns: parentIndex, claimant, bond, clock, claim, position, timestamp
```

### Complete Verification Script
```bash
#!/bin/bash
# check-game-state.sh <game_address> [l1_rpc]

GAME_ADDRESS=$1
L1_RPC=${2:-"http://127.0.0.1:57834"}

echo "🎮 Dispute Game Status Check"
echo "============================"
echo "Game: $GAME_ADDRESS"
echo "RPC: $L1_RPC"
echo ""

# Basic status
STATUS=$(cast call --rpc-url $L1_RPC $GAME_ADDRESS "status() returns (uint8)")
case $STATUS in
    0) echo "🟡 Status: IN_PROGRESS" ;;
    1) echo "🔴 Status: CHALLENGER_WINS" ;;
    2) echo "🟢 Status: DEFENDER_WINS" ;;
    *) echo "❓ Status: UNKNOWN ($STATUS)" ;;
esac

# Timing
CREATED_AT=$(cast call --rpc-url $L1_RPC $GAME_ADDRESS "createdAt() returns (uint64)")
echo "📅 Created: $(date -r $CREATED_AT '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo $CREATED_AT)"

# State information
ROOT_CLAIM=$(cast call --rpc-url $L1_RPC $GAME_ADDRESS "rootClaim() returns (bytes32)")
L2_BLOCK=$(cast call --rpc-url $L1_RPC $GAME_ADDRESS "l2BlockNumber() returns (uint256)")
CLAIM_COUNT=$(cast call --rpc-url $L1_RPC $GAME_ADDRESS "claimDataLen() returns (uint256)")

echo "🎯 Root Claim: $ROOT_CLAIM"
echo "📦 L2 Block: $L2_BLOCK"
echo "🌳 Claims: $CLAIM_COUNT"
```

## Related Documentation

- [Fast Dispute Game Setup](fast-dispute-game-setup.md)
- [Dispute Game Configuration Guide](dispute-game-configuration-guide.md)
- [Anchor State Fix Guide](anchor-state-fix.md)

---

*This script enables hands-free dispute game testing by automating the resolution process.*