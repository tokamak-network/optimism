# AnchorGame Update Complete Guide

## Overview

This guide explains the complete process of how `anchorGame` gets updated from Cold Starting state (0xdead...) to a valid state, including the critical role of the `closeGame()` function.

## Table of Contents

- [Understanding the Problem](#understanding-the-problem)
- [The Complete Update Process](#the-complete-update-process)
- [Why closeGame() is Critical](#why-closegame-is-critical)
- [What Happens if closeGame() is NOT Called](#what-happens-if-closegame-is-not-called)
- [Code References](#code-references)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

## Understanding the Problem

### Cold Starting State

When AnchorStateRegistry is first deployed, it initializes with a placeholder value:

```solidity
// In AnchorStateRegistry.initialize()
startingAnchorRoot = Proposal({
    root: Hash.wrap(0xdead000000000000000000000000000000000000000000000000000000000000),
    l2SequenceNumber: 0
});

anchorGame = address(0);  // No anchor game set yet
```

### Why This is a Problem

```solidity
// When a new game initializes...
function initialize() {
    // Gets anchor root from AnchorStateRegistry
    (Hash root, uint256 rootBlockNumber) = ANCHOR_STATE_REGISTRY.getAnchorRoot();

    // Since anchorGame == address(0), returns startingAnchorRoot
    // root = 0xdead000000...  ❌ Invalid!

    startingOutputRoot = Proposal({
        l2SequenceNumber: rootBlockNumber,
        root: root  // ❌ Using invalid 0xdead... value!
    });
}
```

**Result**: All new games start with invalid starting root → Challenger validation fails!

## The Complete Update Process

### Phase 1: Game Creation and Resolution

```bash
# 1. Create a dispute game with valid output root
DISPUTE_GAME_FACTORY="0x..."
GAME_TYPE=0  # CANNON type
ROOT_CLAIM="0x..."  # Valid L2 output root
EXTRA_DATA="0x0000000000000000000000000000000000000000000000000000000000000000"

cast send $DISPUTE_GAME_FACTORY "create(uint32,bytes32,bytes)" \
  $GAME_TYPE $ROOT_CLAIM $EXTRA_DATA \
  --rpc-url $L1_RPC \
  --private-key $PRIVATE_KEY

# 2. Get game address
GAME_ADDRESS=$(cast call $DISPUTE_GAME_FACTORY \
  "games(uint32,bytes32,bytes)(address,uint64)" \
  $GAME_TYPE $ROOT_CLAIM $EXTRA_DATA \
  --rpc-url $L1_RPC | head -1)

echo "Game created at: $GAME_ADDRESS"

# 3. Resolve the game (after game concludes)
cast send $GAME_ADDRESS "resolve()" \
  --rpc-url $L1_RPC \
  --private-key $PRIVATE_KEY

# 4. Check game status
GAME_STATUS=$(cast call $GAME_ADDRESS "status()(uint8)" --rpc-url $L1_RPC)
# 0=IN_PROGRESS, 1=CHALLENGER_WINS, 2=DEFENDER_WINS

echo "Game status: $GAME_STATUS"
```

### Phase 2: Finality Delay Wait

```bash
# 5. Check finality delay requirement
ANCHOR_STATE_REGISTRY="0x..."
DELAY=$(cast call $ANCHOR_STATE_REGISTRY \
  "disputeGameFinalityDelaySeconds()(uint256)" \
  --rpc-url $L1_RPC)

echo "⏳ Finality delay: $DELAY seconds"

# Production: typically 604800 seconds (7 days)
# Devnet: typically 30-60 seconds

# 6. Wait for finality delay to pass
echo "Waiting for finality delay..."
sleep $DELAY

# 7. Verify game is finalized
IS_FINALIZED=$(cast call $ANCHOR_STATE_REGISTRY \
  "isGameFinalized(address)(bool)" $GAME_ADDRESS \
  --rpc-url $L1_RPC)

if [ "$IS_FINALIZED" == "true" ]; then
    echo "✅ Game is finalized"
else
    echo "❌ Game not finalized yet"
    exit 1
fi
```

### Phase 3: closeGame() Call (🔥 CRITICAL!)

```bash
# 8. Call closeGame() to update anchorGame
echo "🎯 Calling closeGame() to update anchorGame..."

cast send $GAME_ADDRESS "closeGame()" \
  --rpc-url $L1_RPC \
  --private-key $PRIVATE_KEY

echo "✅ closeGame() transaction sent"
```

### Phase 4: Verification

```bash
# 9. Verify anchorGame is now set
ANCHOR_GAME=$(cast call $ANCHOR_STATE_REGISTRY \
  "anchorGame()(address)" \
  --rpc-url $L1_RPC)

if [ "$ANCHOR_GAME" != "0x0000000000000000000000000000000000000000" ]; then
    echo "✅ anchorGame updated to: $ANCHOR_GAME"

    # 10. Verify new anchor root
    ANCHOR_ROOT=$(cast call $ANCHOR_STATE_REGISTRY \
      "getAnchorRoot()(bytes32,uint256)" \
      --rpc-url $L1_RPC | head -1)

    echo "✅ New anchor root: $ANCHOR_ROOT"

    if [[ "$ANCHOR_ROOT" != "0xdead"* ]]; then
        echo "🎉 Cold Starting state resolved!"
        echo "🎉 All new games will now use valid starting root"
    fi
else
    echo "⚠️  anchorGame not updated"
    echo "💡 This may happen if:"
    echo "   - Another game is already the anchor"
    echo "   - This game doesn't meet anchor requirements"
    echo "   - Game is not DEFENDER_WINS"
fi
```

## Why closeGame() is Critical

### Code Flow in FaultDisputeGame.sol

```solidity
// Line 1046-1097: closeGame() function
function closeGame() public {
    // 1. Check if already closed
    if (bondDistributionMode == BondDistributionMode.REFUND ||
        bondDistributionMode == BondDistributionMode.NORMAL) {
        return;  // Already processed
    }

    // 2. Validation checks
    if (ANCHOR_STATE_REGISTRY.paused()) revert GamePaused();
    if (resolvedAt.raw() == 0) revert GameNotResolved();

    // 3. Check finality
    bool finalized = ANCHOR_STATE_REGISTRY.isGameFinalized(IDisputeGame(address(this)));
    if (!finalized) revert GameNotFinalized();

    // 4. 🔥 THE CRITICAL LINE: Update anchorGame!
    // Line 1082
    try ANCHOR_STATE_REGISTRY.setAnchorState(IDisputeGame(address(this))) { } catch { }

    // 5. Determine bond distribution mode
    bool properGame = ANCHOR_STATE_REGISTRY.isGameProper(IDisputeGame(address(this)));
    bondDistributionMode = properGame ? BondDistributionMode.NORMAL : BondDistributionMode.REFUND;

    emit GameClosed(bondDistributionMode);
}
```

### Why Line 1082 is the Key

```solidity
try ANCHOR_STATE_REGISTRY.setAnchorState(IDisputeGame(address(this))) { } catch { }
```

This single line:
1. Calls `AnchorStateRegistry.setAnchorState()`
2. Updates `anchorGame` from `address(0)` to this game's address
3. Changes `getAnchorRoot()` to return valid root instead of 0xdead...
4. Fixes Cold Starting state for ALL future games

### Two Ways to Trigger closeGame()

#### Option A: Direct Call (Recommended)

```bash
cast send $GAME_ADDRESS "closeGame()" --rpc-url $L1_RPC --private-key $KEY
```

**Advantages**:
- ✅ Immediate anchorGame update
- ✅ No dependency on bond claims
- ✅ Predictable timing
- ✅ Best for production environments

#### Option B: Automatic via claimCredit()

```bash
cast send $GAME_ADDRESS "claimCredit(address)" $RECIPIENT --rpc-url $L1_RPC --private-key $KEY
```

**How it works**:
```solidity
// Line 1004-1008: claimCredit() automatically calls closeGame()
function claimCredit(address _recipient) external {
    closeGame();  // Automatic call!

    // ... bond claiming logic ...
}
```

**Disadvantages**:
- ❌ Depends on someone claiming bonds
- ❌ Unpredictable timing
- ❌ May never happen if no one claims

## What Happens if closeGame() is NOT Called

### Short-Term: No Immediate Impact

| Function | Works? | Notes |
|----------|--------|-------|
| resolve() | ✅ Yes | Game resolves normally |
| Bond claiming (via claimCredit) | ✅ Yes | Auto-calls closeGame() |
| Withdrawal | ✅ Yes | Only checks game status |

### Long-Term: System Stays Broken

```
Game 1 (resolved, finalized)
├─ closeGame() NOT called ❌
├─ anchorGame = address(0)
└─ Cold Starting continues...

           ↓

Game 2 created
├─ getAnchorRoot() → 0xdead... ❌
├─ startingOutputRoot = 0xdead... ❌
└─ Challenger validation FAILS ❌

           ↓

Game 3 created
├─ Same problem repeats ❌
├─ getAnchorRoot() → 0xdead... ❌
└─ System remains in Cold Starting state 🔥

           ↓

All subsequent games FAIL validation!
```

### Impact Summary

| Area | Impact | Severity |
|------|--------|----------|
| **anchorGame update** | ❌ Never updates | 🔴 Critical |
| **New game starting roots** | ❌ Continue using 0xdead... | 🔴 Critical |
| **Challenger validation** | ❌ All validations fail | 🔴 Critical |
| **System state** | ❌ Permanent Cold Starting | 🔴 Critical |
| **Bond claiming** | ✅ Still works (auto-fixes) | 🟢 OK |
| **Withdrawals** | ✅ Still work | 🟢 OK |

## Code References

### FaultDisputeGame.sol

```
packages/contracts-bedrock/src/dispute/FaultDisputeGame.sol

Key Lines:
- Line 740-756:   resolve()        → Resolves game
- Line 1004-1042: claimCredit()    → Claims bonds (calls closeGame)
- Line 1046-1097: closeGame()      → Updates anchorGame (Line 1082!)
- Line 1082:      setAnchorState() → THE CRITICAL LINE
```

### AnchorStateRegistry.sol

```
packages/contracts-bedrock/src/dispute/AnchorStateRegistry.sol

Key Lines:
- Line 168-176:  getAnchorRoot()    → Returns current anchor
- Line 273-289:  isGameFinalized()  → Checks finality delay
- Line 291-316:  isGameClaimValid() → Validates game for anchor
- Line 318-342:  setAnchorState()   → Actually updates anchorGame
```

## Best Practices

### 1. Always Call closeGame() After Finality Delay

```bash
#!/bin/bash
# best-practice-resolve.sh

GAME_ADDRESS="$1"
L1_RPC="$2"
PRIVATE_KEY="$3"

# Step 1: Resolve
echo "1. Resolving game..."
cast send $GAME_ADDRESS "resolve()" --rpc-url $L1_RPC --private-key $PRIVATE_KEY

# Step 2: Wait for finality
echo "2. Waiting for finality delay..."
ANCHOR_STATE_REGISTRY=$(get_anchor_registry)
DELAY=$(cast call $ANCHOR_STATE_REGISTRY "disputeGameFinalityDelaySeconds()(uint256)" --rpc-url $L1_RPC)
sleep $DELAY

# Step 3: Call closeGame() immediately
echo "3. Calling closeGame()..."
cast send $GAME_ADDRESS "closeGame()" --rpc-url $L1_RPC --private-key $PRIVATE_KEY

echo "✅ Complete! anchorGame should be updated"
```

### 2. Monitor anchorGame Status

```bash
#!/bin/bash
# monitor-anchor-game.sh

ANCHOR_STATE_REGISTRY="$1"
L1_RPC="$2"

while true; do
    ANCHOR_GAME=$(cast call $ANCHOR_STATE_REGISTRY "anchorGame()(address)" --rpc-url $L1_RPC)

    if [ "$ANCHOR_GAME" == "0x0000000000000000000000000000000000000000" ]; then
        echo "⚠️  $(date): Still in Cold Starting state"
    else
        ANCHOR_ROOT=$(cast call $ANCHOR_STATE_REGISTRY "getAnchorRoot()(bytes32,uint256)" --rpc-url $L1_RPC | head -1)
        echo "✅ $(date): anchorGame=$ANCHOR_GAME, root=$ANCHOR_ROOT"
    fi

    sleep 60
done
```

### 3. Automated closeGame() Caller

```bash
#!/bin/bash
# auto-close-finalized-games.sh

DISPUTE_GAME_FACTORY="$1"
ANCHOR_STATE_REGISTRY="$2"
L1_RPC="$3"
PRIVATE_KEY="$4"

echo "🤖 Auto-closing finalized games..."

# Get total game count
GAME_COUNT=$(cast call $DISPUTE_GAME_FACTORY "gameCount()(uint256)" --rpc-url $L1_RPC)

for ((i=0; i<$GAME_COUNT; i++)); do
    # Get game address
    GAME_INFO=$(cast call $DISPUTE_GAME_FACTORY "gameAtIndex(uint256)(uint32,uint64,address)" $i --rpc-url $L1_RPC)
    GAME_ADDRESS=$(echo "$GAME_INFO" | tail -1)

    # Check if finalized
    IS_FINALIZED=$(cast call $ANCHOR_STATE_REGISTRY "isGameFinalized(address)(bool)" $GAME_ADDRESS --rpc-url $L1_RPC)

    if [ "$IS_FINALIZED" == "true" ]; then
        # Check if already closed
        BOND_MODE=$(cast call $GAME_ADDRESS "bondDistributionMode()(uint8)" --rpc-url $L1_RPC)

        if [ "$BOND_MODE" == "0" ]; then  # UNDECIDED
            echo "🎯 Closing game $GAME_ADDRESS..."
            cast send $GAME_ADDRESS "closeGame()" --rpc-url $L1_RPC --private-key $PRIVATE_KEY
        fi
    fi
done

echo "✅ Auto-close complete"
```

## Troubleshooting

### Problem: closeGame() Reverts

```bash
# Diagnosis
cast call $GAME_ADDRESS "resolvedAt()(uint64)" --rpc-url $L1_RPC
# If returns 0, game not resolved yet

cast call $ANCHOR_STATE_REGISTRY "isGameFinalized(address)(bool)" $GAME_ADDRESS --rpc-url $L1_RPC
# If false, finality delay not passed yet

cast call $ANCHOR_STATE_REGISTRY "paused()(bool)" --rpc-url $L1_RPC
# If true, system is paused
```

### Problem: anchorGame Not Updated After closeGame()

```bash
# Check if game meets anchor requirements
cast call $ANCHOR_STATE_REGISTRY "isGameClaimValid(address)(bool)" $GAME_ADDRESS --rpc-url $L1_RPC

# Must be DEFENDER_WINS
GAME_STATUS=$(cast call $GAME_ADDRESS "status()(uint8)" --rpc-url $L1_RPC)
if [ "$GAME_STATUS" != "2" ]; then
    echo "❌ Game must be DEFENDER_WINS (status=2), current: $GAME_STATUS"
fi

# Must be newer than current anchor
CURRENT_ANCHOR=$(cast call $ANCHOR_STATE_REGISTRY "anchorGame()(address)" --rpc-url $L1_RPC)
if [ "$CURRENT_ANCHOR" != "0x0000000000000000000000000000000000000000" ]; then
    echo "💡 Another game is already anchor: $CURRENT_ANCHOR"
    echo "💡 This game must be newer to replace it"
fi
```

### Problem: Validation Still Failing After Update

```bash
# Verify anchor root is actually updated
ANCHOR_ROOT=$(cast call $ANCHOR_STATE_REGISTRY "getAnchorRoot()(bytes32,uint256)" --rpc-url $L1_RPC | head -1)

if [[ "$ANCHOR_ROOT" == "0xdead"* ]]; then
    echo "❌ Anchor root still using placeholder"
    echo "💡 Run the complete update process again"
else
    echo "✅ Anchor root is valid: $ANCHOR_ROOT"
    echo "💡 Problem may be elsewhere (check challenger logs)"
fi
```

## Related Documentation

- [anchor-state-fix.md](../challenger/anchor-state-fix.md) - Step-by-step fix guide
- [challenger-prestate-validation.md](../challenger/challenger-prestate-validation.md) - Validation process details
- [troubleshooting-guide.md](../operations/troubleshooting-guide.md) - General troubleshooting
