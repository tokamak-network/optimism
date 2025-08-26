# Game Related Knowledge Points

## 1. Claim Type

**Meaning:**
- Claim is simply a wrapper type for `bytes32`
- Represents MPT (Merkle Patricia Trie) root
- Hash value representing the state of the fault proof program

```solidity
type Claim is bytes32;
```

## 2. ClaimData

**Meaning:**
- Contains more metadata including Claim type
- Additional information such as relationships in the game, bonds, time, etc.

```solidity
struct ClaimData {
    uint32 parentIndex;      // Index of the parent claim
    address counteredBy;     // Address that countered this claim
    address claimant;        // Address that submitted the claim
    uint128 bond;           // Bond amount
    Claim claim;            // Claim value (hash)
    Position position;      // Position in the game
    Clock clock;            // Chess clock information
}
```

**Usage Example:**
```solidity
// In Solidity
function getClaimData(uint256 index) external view returns (ClaimData memory) {
    return claimData[index];
}

ClaimData memory claim = ClaimData({
    parentIndex: 0,
    counteredBy: address(0),
    claimant: msg.sender,
    bond: 1000000,
    claim: Claim.wrap(keccak256("some state")),  // Using Claim type
    position: Position.wrap(1),
    clock: Clock.wrap(0)
});
```

## 3. Position

```solidity
/// @notice A `Position` represents a position of a claim within the game tree.
/// @dev This is represented as a "generalized index" where the high-order bit
/// is the level in the tree and the remaining bits is a unique bit pattern, allowing
/// a unique identifier for each node in the tree. Mathematically, it is calculated
/// as 2^{depth} + indexAtDepth.
type Position is uint128;

/// @notice The global root claim's position is always at gindex 1.
Position internal constant ROOT_POSITION = Position.wrap(1);
```

```solidity
/// @notice Computes a generalized index (2^{depth} + indexAtDepth).
/// @param _depth The depth of the position.
/// @param _indexAtDepth The index at the depth of the position.
/// @return position_ The computed generalized index.
function wrap(uint8 _depth, uint128 _indexAtDepth) internal pure returns (Position position_) {
    assembly {
        // gindex = 2^{_depth} + _indexAtDepth
        position_ := add(shl(_depth, 1), _indexAtDepth)
    }
}
```

**Unique identifier in the entire tree:**
- Position: `gindex = 2^depth + indexAtDepth`
- This combines depth and indexAtDepth to represent the exact position in the game tree.

## 4. Attack and Defense Positions in the Game

```solidity
// Attack: left child
Position attackPos = parentPos.move(true);   // depth+1, indexAtDepth*2

// Defense: right child
Position defendPos = parentPos.move(false);  // depth+1, indexAtDepth*2+1
```

## 5. Bond Calculation Method When Calling attack() or defend() Functions in FaultDisputeGame

### 5.1. Function Call
```solidity
// In FaultDisputeGame contract
function getRequiredBond(Position _position) public view returns (uint256 requiredBond_)
```

### 5.2. Bond Calculation from Root
```solidity
Position attackPos = Position.wrap(2);
function getRequiredBond(Position attackPos) public view returns (uint256 requiredBond_)
```

## 6. GameId

```solidity
/// @notice A `GameId` represents a packed 4 byte game ID, a 8 byte timestamp, and a 20 byte address.
/// @dev The packed layout of this type is as follows:
/// ┌───────────┬───────────┐
/// │   Bits    │   Value   │
/// ├───────────┼───────────┤
/// │ [0, 32)   │ Game Type │
/// │ [32, 96)  │ Timestamp │
/// │ [96, 256) │ Address   │
/// └───────────┴───────────┘
type GameId is bytes32;
```

```solidity
/// @title LibGameId
/// @notice Utility functions for packing and unpacking GameIds.
library LibGameId {
    /// @notice Packs values into a 32 byte GameId type.
    /// @param _gameType The game type.
    /// @param _timestamp The timestamp of the game's creation.
    /// @param _gameProxy The game proxy address.
    /// @return gameId_ The packed GameId.
    function pack(
        GameType _gameType,
        Timestamp _timestamp,
        address _gameProxy
    )
        internal
        pure
        returns (GameId gameId_)
    {
        assembly {
            gameId_ := or(or(shl(224, _gameType), shl(160, _timestamp)), _gameProxy)
        }
    }

    /// @notice Unpacks values from a 32 byte GameId type.
    /// @param _gameId The packed GameId.
    /// @return gameType_ The game type.
    /// @return timestamp_ The timestamp of the game's creation.
    /// @return gameProxy_ The game proxy address.
    function unpack(GameId _gameId)
        internal
        pure
        returns (GameType gameType_, Timestamp timestamp_, address gameProxy_)
    {
        assembly {
            gameType_ := shr(224, _gameId)
            timestamp_ := and(shr(160, _gameId), 0xFFFFFFFFFFFFFFFF)
            gameProxy_ := and(_gameId, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }
    }
}
