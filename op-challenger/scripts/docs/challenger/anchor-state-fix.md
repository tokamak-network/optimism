# AnchorStateRegistry Fix Guide

## Game Types Overview

### CANNON Mode (game_type: 0) - Permissionless
- **L2OutputOracle**: Not used (address set to 0x0000...)
- **Output Root Source**: Provided directly when creating dispute games
- **Proposer**: Anyone can create games with any output root
- **Challenger**: Must validate output roots independently
- **Trust Model**: Fully permissionless, relies on economic incentives
- **Use Case**: Production networks, decentralized dispute resolution

### PERMISSIONED Mode (game_type: 1) - Semi-Centralized
- **L2OutputOracle**: Required and actively used
- **Output Root Source**: Fetched from L2OutputOracle contract
- **Proposer**: Centralized proposer submits L2 output roots to L2OutputOracle
- **Challenger**: Validates against roots stored in L2OutputOracle
- **Trust Model**: Trusted proposer + permissionless challenges
- **Use Case**: Testing, staging environments, gradual decentralization

## Problem

The AnchorStateRegistry is initialized with a default value of `0xdead000000000000000000000000000000000000000000000000000000000000` for the `startingAnchorRoot`. This is intentional behavior, but it causes all new FaultDisputeGame instances to fail validation because they inherit this invalid anchor root.

This is a "cold start" problem - the system expects the first valid game to be manually resolved to set a proper anchor state, after which subsequent games work correctly.

## Diagnosis

You can check the current anchor state using the diagnostic script:

```bash
# Check current anchor state
ANCHOR_STATE_REGISTRY=$(grep -o '"AnchorStateRegistryProxy": *"[^"]*"' /tmp/devnet-desc/env.json | cut -d'"' -f4)
CURRENT_ANCHOR=$(cast call $ANCHOR_STATE_REGISTRY "getAnchorRoot()" --rpc-url http://127.0.0.1:58524)
CURRENT_ROOT=$(echo $CURRENT_ANCHOR | cut -c1-66)

if [[ "$CURRENT_ROOT" == "0xdead000000000000000000000000000000000000000000000000000000000000" ]]; then
    echo "⚠️  AnchorStateRegistry is using default 0xdead value!"
    echo "💡 This needs to be fixed by:"
    echo "   1. Deploying a valid FaultDisputeGame with the correct output root"
    echo "   2. Resolving that game to trigger setAnchorState()"
    echo ""
    echo "🎯 Alternatively, we can create a simple dispute game and resolve it:"
    echo "   Output root to use: [VALID_OUTPUT_ROOT]"
    echo "   L2 block number: [L2_BLOCK_NUMBER]"
else
    echo "✅ AnchorStateRegistry already has a valid anchor state"
fi
```

## Solution Methods

### Method 1: Resolve First Valid Game (Recommended for CANNON mode)

Since CANNON mode (game_type: 0) doesn't use L2OutputOracle, you need to manually create and resolve a dispute game:

1. **Get L2 genesis or latest state root**:
   ```bash
   # For genesis state (safest for cold start)
   L2_RPC="http://op-el-2151908-node0-op-geth:8545"  # Adjust based on your setup
   GENESIS_ROOT=$(cast call 0x0000000000000000000000000000000000000001 "" --rpc-url $L2_RPC --block 0)

   # Or get latest block state root
   LATEST_ROOT=$(cast call 0x0000000000000000000000000000000000000001 "" --rpc-url $L2_RPC --block latest)
   ```

2. **Create a dispute game with correct root**:
   ```bash
   DISPUTE_GAME_FACTORY=$(grep -o '"DisputeGameFactoryProxy": *"[^"]*"' /tmp/devnet-desc/env.json | cut -d'"' -f4)
   GAME_TYPE=0  # CANNON
   ROOT_CLAIM="[VALID_ROOT_FROM_STEP_1]"
   L2_BLOCK_NUM=0  # For genesis, or appropriate block number
   EXTRA_DATA=$(printf "0x%064x" $L2_BLOCK_NUM)

   # Create the game
   cast send $DISPUTE_GAME_FACTORY "create(uint32,bytes32,bytes)" \
     $GAME_TYPE $ROOT_CLAIM $EXTRA_DATA \
     --rpc-url http://127.0.0.1:58524 \
     --private-key [ADMIN_PRIVATE_KEY]
   ```

3. **Resolve the game**:
   ```bash
   # Get the created game address
   GAME_ADDRESS=$(cast call $DISPUTE_GAME_FACTORY "games(uint32,bytes32,bytes)" \
     $GAME_TYPE $ROOT_CLAIM $EXTRA_DATA \
     --rpc-url http://127.0.0.1:58524)

   # Resolve the game
   cast send $GAME_ADDRESS "resolve()" \
     --rpc-url http://127.0.0.1:58524 \
     --private-key [ADMIN_PRIVATE_KEY]
   ```

   ⚠️ **Important**: `resolve()` alone does NOT update anchorGame!

4. **Wait for finality delay**:
   ```bash
   # Check finality delay setting (typically 7 days in production, shorter in devnet)
   ANCHOR_STATE_REGISTRY=$(grep -o '"AnchorStateRegistryProxy": *"[^"]*"' /tmp/devnet-desc/env.json | cut -d'"' -f4)
   DELAY=$(cast call $ANCHOR_STATE_REGISTRY \
     "disputeGameFinalityDelaySeconds()(uint256)" \
     --rpc-url http://127.0.0.1:58524)

   echo "⏳ Finality delay: $DELAY seconds"

   # For devnet testing, this is usually short (e.g., 30-60 seconds)
   # For production, this is typically 604800 seconds (7 days)
   sleep $DELAY

   # Verify game is finalized
   IS_FINALIZED=$(cast call $ANCHOR_STATE_REGISTRY \
     "isGameFinalized(address)(bool)" $GAME_ADDRESS \
     --rpc-url http://127.0.0.1:58524)

   if [ "$IS_FINALIZED" == "true" ]; then
     echo "✅ Game is finalized and ready for closeGame()"
   else
     echo "❌ Game not finalized yet, wait longer"
   fi
   ```

5. **Call closeGame() to update anchorGame**:
   ```bash
   # Option A: Direct closeGame() call (RECOMMENDED)
   echo "🎯 Calling closeGame() to update anchorGame..."
   cast send $GAME_ADDRESS "closeGame()" \
     --rpc-url http://127.0.0.1:58524 \
     --private-key [ADMIN_PRIVATE_KEY]

   # Option B: Call claimCredit() which automatically calls closeGame()
   # (Only if you need to claim bonds)
   # cast send $GAME_ADDRESS "claimCredit(address)" [RECIPIENT_ADDRESS] \
   #   --rpc-url http://127.0.0.1:58524 \
   #   --private-key [ADMIN_PRIVATE_KEY]
   ```

   💡 **Why closeGame() is critical**:
   - `closeGame()` calls `setAnchorState()` internally (Line 1082 in FaultDisputeGame.sol)
   - Without this call, `anchorGame` remains `address(0)`
   - All new games will continue using the invalid 0xdead... starting root
   - See [anchor-game-update-guide.md](../dispute-games/anchor-game-update-guide.md) for details

6. **Verify anchorGame updated**:
   ```bash
   # Check if anchorGame is now set
   ANCHOR_GAME=$(cast call $ANCHOR_STATE_REGISTRY \
     "anchorGame()(address)" \
     --rpc-url http://127.0.0.1:58524)

   if [ "$ANCHOR_GAME" != "0x0000000000000000000000000000000000000000" ]; then
     echo "✅ anchorGame successfully updated to: $ANCHOR_GAME"

     # Verify new anchor root
     NEW_ANCHOR_ROOT=$(cast call $ANCHOR_STATE_REGISTRY \
       "getAnchorRoot()(bytes32,uint256)" \
       --rpc-url http://127.0.0.1:58524 | head -1)
     echo "✅ New anchor root: $NEW_ANCHOR_ROOT"
   else
     echo "❌ anchorGame still not set"
     echo "💡 This may happen if another game is already the anchor"
     echo "💡 Or if the game doesn't meet anchor requirements"
   fi
   ```

### Method 2: Use OPContractsManager.updatePrestate()

This method deploys new game implementations with correct prestate:

1. **Prepare OpChainConfig**:
   ```solidity
   OPContractsManager.OpChainConfig memory config = OPContractsManager.OpChainConfig({
       systemConfigProxy: ISystemConfig([SYSTEM_CONFIG_ADDRESS]),
       proxyAdmin: IProxyAdmin([PROXY_ADMIN_ADDRESS]),
       absolutePrestate: Claim.wrap([CORRECT_PRESTATE_HASH])
   });
   ```

2. **Call updatePrestate**:
   ```solidity
   OPContractsManager.OpChainConfig[] memory configs = new OPContractsManager.OpChainConfig[](1);
   configs[0] = config;
   opcm.updatePrestate(configs);
   ```

## How AnchorStateRegistry Works

The `getAnchorRoot()` function behavior:

```solidity
function getAnchorRoot() public view returns (Hash, uint256) {
    // Return the starting anchor root if there is no anchor game.
    if (address(anchorGame) == address(0)) {
        return (startingAnchorRoot.root, startingAnchorRoot.l2SequenceNumber);  // Returns 0xdead...
    }

    // Otherwise, return the anchor root from the resolved game.
    return (Hash.wrap(anchorGame.rootClaim().raw()), anchorGame.l2SequenceNumber());
}
```

### ⚠️ Important: Game Resolution vs AnchorGame Update

**Common Misconception**: `resolve()` automatically updates anchorGame

**Reality**: The update happens in `closeGame()`, NOT in `resolve()`

```solidity
// ❌ WRONG: resolve() does NOT call setAnchorState()
function resolve() external returns (GameStatus) {
    // ... resolution logic ...
    // NO setAnchorState() call here!
}

// ✅ CORRECT: closeGame() calls setAnchorState()
function closeGame() public {
    // ... validation checks ...

    // Line 1082 in FaultDisputeGame.sol
    try ANCHOR_STATE_REGISTRY.setAnchorState(IDisputeGame(address(this))) { } catch { }

    // ... bond distribution logic ...
}
```

### Update Process

1. **resolve()** → Sets game status to DEFENDER_WINS or CHALLENGER_WINS
2. **Wait finality delay** → Typically 7 days (production) or 30-60 seconds (devnet)
3. **closeGame()** → Actually updates anchorGame via `setAnchorState()`

This updates `anchorGame` from `address(0)` to the resolved game, causing `getAnchorRoot()` to return the correct value instead of 0xdead.

### Ways to Trigger closeGame()

1. **Direct call** (Recommended):
   ```bash
   cast send $GAME_ADDRESS "closeGame()" --rpc-url $L1_RPC --private-key $KEY
   ```

2. **Automatic via claimCredit()**:
   ```bash
   cast send $GAME_ADDRESS "claimCredit(address)" $RECIPIENT --rpc-url $L1_RPC --private-key $KEY
   ```
   Note: `claimCredit()` calls `closeGame()` internally (Line 1008)

## Verification

After applying the fix, verify the anchor state is updated:

```bash
CURRENT_ANCHOR=$(cast call $ANCHOR_STATE_REGISTRY "getAnchorRoot()" --rpc-url http://127.0.0.1:58524)
CURRENT_ROOT=$(echo $CURRENT_ANCHOR | cut -c1-66)
echo "New anchor root: $CURRENT_ROOT"

if [[ "$CURRENT_ROOT" != "0xdead000000000000000000000000000000000000000000000000000000000000" ]]; then
    echo "✅ AnchorStateRegistry fix successful!"
else
    echo "❌ Fix failed - still using 0xdead value"
fi
```

## Integration with Devnet Deployment

Consider adding this fix as a post-deployment step in your devnet scripts to automatically resolve the cold start problem.