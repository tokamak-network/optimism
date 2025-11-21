# Dispute Game Types Guide

## Overview

The Optimism fault proof system supports different game types that determine how output roots are sourced and validated. Understanding these differences is crucial for proper challenger configuration and troubleshooting.

## Game Type Comparison

| Aspect | CANNON (type: 0) | PERMISSIONED_CANNON (type: 1) |
|--------|------------------|-------------------------------|
| **Trust Model** | Fully permissionless | Role-based permissions |
| **Participation** | Anyone can create games | Only authorized proposer/challenger |
| **Game Creation** | Anyone can call `move()` | Only PROPOSER/CHALLENGER can call `move()` |
| **L2OutputOracle** | Not used (0x0000...) | May be used |
| **Economic Security** | Pure incentive-based | Role-based + incentive-based |
| **Code Reference** | `FaultDisputeGame.sol:457` | `PermissionedDisputeGame.sol:73-85` |

## CANNON Mode (game_type: 0) - Permissionless

**Code Reference**: `GameTypes.CANNON = GameType.wrap(0)` (Types.sol:53)

### Characteristics
- **Fully Permissionless**: Anyone can participate in the dispute game
- **No Access Control**: The `move()` function has no authorization restrictions
- **Economic Incentives**: Relies purely on bonds and economic penalties

### Code Evidence
```solidity
// FaultDisputeGame.sol:457 - No access control modifiers
function move(Claim _disputed, uint256 _challengeIndex, Claim _claim, bool _isAttack) 
    public payable virtual {
    // Anyone can call this function
}
```

### How it Works
1. **Game Creation**: Anyone can create games through DisputeGameFactory
2. **Participation**: Anyone can make moves (`attack`/`defend`) without restrictions  
3. **Challenger Behavior**: 
   - **Monitors** all dispute games continuously
   - **Selectively challenges** only games with incorrect root claims
   - **Does NOT automatically challenge** every game (would be economically wasteful)
   - **Code Reference**: Challenger only acts when detecting invalid claims

### Economic Model
- Challenger only challenges when confident of winning
- Correct games remain unchallenged → resolve as DEFENDER_WINS
- Incorrect games get challenged → challenger wins the bond

### Configuration Example
```bash
# Devnet configuration shows L2OutputOracle as 0x0000...
"L2OutputOracleProxy": "0x0000000000000000000000000000000000000000"

# Challenger works with MultiPrestateProvider (no --cannon-prestate parameter)
op-challenger --game-type=0 ...
```

### Use Cases
- **Production networks** requiring maximum decentralization
- **Mainnet deployments** where trust minimization is critical
- **Long-term vision** for fully permissionless rollups

## PERMISSIONED_CANNON Mode (game_type: 1) - Role-Based

**Code Reference**: `GameTypes.PERMISSIONED_CANNON = GameType.wrap(1)` (Types.sol:56)

### Characteristics
- **Role-Based Access**: Only authorized proposer and challenger can participate
- **Access Control**: The `move()` function requires `onlyAuthorized` modifier
- **Fallback Mechanism**: Used as backup when permissionless system has issues

### Code Evidence
```solidity
// PermissionedDisputeGame.sol:27-31
modifier onlyAuthorized() {
    if (!(msg.sender == PROPOSER || msg.sender == CHALLENGER)) {
        revert BadAuth();
    }
    _;
}

// PermissionedDisputeGame.sol:73-85 - Access controlled move function
function move(Claim _disputed, uint256 _challengeIndex, Claim _claim, bool _isAttack)
    public payable override onlyAuthorized  // Only PROPOSER or CHALLENGER
{
    super.move(_disputed, _challengeIndex, _claim, _isAttack);
}
```

### How it Works
1. **Authorized Roles**: Only pre-defined PROPOSER and CHALLENGER addresses can participate
2. **Game Moves**: All `attack`/`defend` moves require authorization check
3. **Purpose**: "way for networks to support fault proof without fully permissionless system" (PermissionedDisputeGame.sol:15-16)

### Trust Model
- Relies on trusted PROPOSER to create valid games
- Relies on trusted CHALLENGER to dispute invalid games  
- Reduces "costs that certain networks may not wish to support" (PermissionedDisputeGame.sol:16-17)

### Configuration Example
```bash
# L2OutputOracle is deployed and active (in some configurations)
"L2OutputOracleProxy": "0x123abc..." # Real contract address

# Challenger works with MultiPrestateProvider (no --cannon-prestate parameter)
op-challenger --game-type=1 ...
```

### Use Cases
- **Testing environments** where some centralization is acceptable
- **Staging networks** for development and integration testing
- **Migration period** during transition to full decentralization

## Technical Implications

### For Challengers

**Game Discovery Method - Universal for All Game Types**:

The challenger uses **polling** instead of event subscription for game discovery:

**Code Reference**: `op-challenger/game/fault/contracts/gamefactory.go:89-128`
```go
// Challenger polls DisputeGameFactory periodically
func (f *DisputeGameFactoryContract) GetGamesAtOrAfter(ctx context.Context, blockHash common.Hash, earliestTimestamp uint64) ([]types.GameMetadata, error) {
    count, err := f.GetGameCount(ctx, blockHash)  // Query game count
    // ... batch load games using gameAtIndex(i)
}
```

**Key Points**:
- ❌ **NO event subscription**: No `WatchOutputProposed` or `WatchDisputeGameCreated` usage
- ✅ **State polling**: Directly queries `gameCount()` and `gameAtIndex()` from DisputeGameFactory
- ✅ **Game type agnostic**: Same discovery mechanism for CANNON and PERMISSIONED_CANNON
- ✅ **L2OutputOracle independent**: Works regardless of oracle deployment

**CANNON Mode Requirements**:
- Must have access to L2 state for output root computation
- Uses MultiPrestateProvider for hash-based prestate file lookup
- Polls DisputeGameFactory for new games

**PERMISSIONED_CANNON Mode Requirements**:
- Only authorized addresses can participate in games
- Uses MultiPrestateProvider for hash-based prestate file lookup  
- Polls DisputeGameFactory for new games (same as CANNON)

### For Output Root Calculation

**Both CANNON and PERMISSIONED_CANNON**:
- Use the same underlying `FaultDisputeGame` mechanics
- Both reference L2 block numbers for output root calculation
- The difference is **who can participate**, not **how roots are calculated**

**Code Evidence**:
```solidity
// Both inherit from FaultDisputeGame.sol:641-649
/// @notice The l2BlockNumber of the disputed output root
function l2BlockNumber() public pure returns (uint256 l2BlockNumber_) {
    l2BlockNumber_ = _getArgUint256(84);  // Same for both types
}
```

### Proposer Integration Differences

**Code Reference**: `op-proposer/proposer/config.go:99-104`

The proposer can operate in two modes:
1. **L2OutputOracle Mode**: Proposer submits to L2OutputOracle contract
2. **DisputeGameFactory Mode**: Proposer creates dispute games directly

```go
// Proposer config validation - must choose one mode
if c.DGFAddress == "" && c.L2OOAddress == "" {
    return errors.New("neither the `DisputeGameFactory` nor `L2OutputOracle` address was provided")
}
if c.DGFAddress != "" && c.L2OOAddress != "" {
    return errors.New("both the `DisputeGameFactory` and `L2OutputOracle` addresses were provided") 
}
```

**Current Devnet Configuration** (typically PERMISSIONED mode):
- respectedGameType: 1 (PERMISSIONED_CANNON)
- L2OutputOracle may or may not be deployed
- Proposer creates dispute games through DisputeGameFactory
- Challenger polls DisputeGameFactory for game discovery

**Current Devnet Example**:
```json
{
  "L2OutputOracleProxy": "0x..." or "0x0000000000000000000000000000000000000000",
  "DisputeGameFactoryProxy": "0x...", // Supports both game types  
  "AnchorStateRegistryProxy": "0x...", // Works with both types
}
```

**Why This Works Without L2OutputOracle Events**:
- Challenger doesn't subscribe to `OutputProposed` events
- Challenger doesn't subscribe to `DisputeGameCreated` events  
- Challenger only polls `gameCount()` and `gameAtIndex()` from DisputeGameFactory
- **Result**: L2OutputOracle deployment is optional for challenger operation

## Migration Path

The typical progression is:
1. **PERMISSIONED** → Testing with trusted proposer
2. **CANNON** → Full decentralization for production

This allows teams to:
- Test dispute mechanisms with simpler validation
- Gradually increase decentralization
- Maintain compatibility during transitions

## Troubleshooting

### Common Issues by Game Type

**CANNON Mode**:
- ❌ "Provider: 0x... | Contract: 0xdead..." → AnchorStateRegistry cold start issue
- ❌ Output root mismatch → Challenger computation vs game claim mismatch
- ❌ Missing prestate → Cannon binary/state sync issues

**PERMISSIONED_CANNON Mode**:
- ❌ "BadAuth" error → Unauthorized address trying to make moves (PermissionedDisputeGame.sol:29)
- ❌ No challenger participation → Only authorized CHALLENGER can dispute
- ❌ Proposer issues → Only authorized PROPOSER can create proper games

### Diagnostic Commands

```bash
# Check what game types are supported
GAME_IMPLS=$(cast call $DISPUTE_GAME_FACTORY "gameImpls(uint32)" 0 --rpc-url $L1_RPC)
echo "CANNON (type 0) implementation: $GAME_IMPLS"

GAME_IMPLS=$(cast call $DISPUTE_GAME_FACTORY "gameImpls(uint32)" 1 --rpc-url $L1_RPC) 
echo "PERMISSIONED_CANNON (type 1) implementation: $GAME_IMPLS"

# Check if specific game has access control
# PERMISSIONED games will have PROPOSER/CHALLENGER roles
PROPOSER=$(cast call $GAME_ADDRESS "PROPOSER()" --rpc-url $L1_RPC 2>/dev/null)
if [[ $? -eq 0 ]]; then
  echo "PERMISSIONED_CANNON game detected (has PROPOSER role)"
else 
  echo "CANNON game detected (no role restrictions)"
fi
```