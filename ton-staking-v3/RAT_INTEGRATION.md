# TON Staking V3 RAT Integration

This document describes the implementation of TON Staking V3 RAT (Randomized Attention Test) integration in Optimism.

---

## Modified/Created Files

### New Interfaces

| File | Description |
|------|-------------|
| `interfaces/L1/IRAT.sol` | TON Staking V3 RAT interface |
| `interfaces/L1/ISeigManager.sol` | TON Staking V3 SeigManager interface |

### Modified Files

| File | Changes |
|------|---------|
| `src/dispute/DisputeGameFactory.sol` | Added RAT trigger call |
| `src/dispute/FaultDisputeGame.sol` | Added RAT callback call |
| `src/L1/L1StandardBridge.sol` | Added Bridged TON change notification |
| `interfaces/dispute/IFaultDisputeGame.sol` | Added `rat()` function |

---

## 1. IRAT Interface

```solidity
// interfaces/L1/IRAT.sol
interface IRAT {
    /// @notice Triggers attention test (called by DisputeGameFactory)
    /// @param gameAddress Newly created FaultDisputeGame address
    /// @param systemConfig L2's SystemConfig address (L2 identifier)
    /// @param batchIndex Batch/game index
    /// @param batchHash Batch hash or Output Root
    /// @param blockHash Block hash (for random validator selection)
    function triggerAttentionTest(
        address gameAddress,
        address systemConfig,
        uint32 batchIndex,
        bytes32 batchHash,
        bytes32 blockHash
    ) external;

    /// @notice Called when a claim is resolved (called by FaultDisputeGame)
    /// @param claimant Address that won the game
    function resolveClaim(address claimant) external;
}
```

---

## 2. DisputeGameFactory - RAT Trigger

### Added State Variables

```solidity
/// @notice RAT contract address (TON Staking V3 RAT)
address public rat;

/// @notice SystemConfig address for RAT L2 identification
address public systemConfig;
```

### Added Functions

```solidity
function setRAT(address _rat) external onlyOwner;
function setSystemConfig(address _systemConfig) external onlyOwner;
```

### RAT Trigger in create()

```solidity
// Trigger RAT after game creation
if (rat != address(0) && _gameType.raw() == GameTypes.CANNON.raw()) {
    try IRAT(rat).triggerAttentionTest(
        address(proxy_),                     // gameAddress
        systemConfig,                        // L2 identifier
        uint32(_disputeGameList.length - 1), // batchIndex
        Claim.unwrap(_rootClaim),            // batchHash
        parentHash                           // blockHash
    ) { } catch { }
}
```

---

## 3. FaultDisputeGame - RAT Callback

### Added State Variable

```solidity
/// @notice RAT contract address
address public rat;
```

### Initialization

```solidity
function initialize(address _rat) public payable virtual {
    _initialize(_rat);
}

function _initialize(address _rat) internal virtual {
    // ... existing logic ...
    if (_rat != address(0)) rat = _rat;
}
```

### RAT Callback in resolveClaim

```solidity
/// @notice Safely calls RAT resolveClaim
function resolveClaimRat(address claimant) internal {
    if (rat != address(0)) {
        try IRAT(rat).resolveClaim(claimant) { } catch { }
    }
}
```

Called when:
- Uncontested claim is resolved
- L2 block number challenge succeeds
- Normal claim resolution

---

## 4. ISeigManager Interface

```solidity
// interfaces/L1/ISeigManager.sol
interface ISeigManager {
    /// @notice Called when Bridged TON balance changes (Type 3 only)
    /// @dev SeigManager automatically queries rollupConfig from msg.sender (OptimismPortal)
    ///      via L1BridgeRegistry.rollupConfigWithPortal()
    function onBridgedTonChange() external;
}
```

---

## 5. L1StandardBridge - Bridged TON Notification

### Added State Variables

```solidity
/// @notice SeigManager contract address (TON Staking V3)
address public seigManager;

/// @notice TON token address for Bridged TON tracking
address public ton;
```

### Added Functions

```solidity
function setSeigManager(address _seigManager) external;
function setTON(address _ton) external;
```

### TON TVL Change Notification

```solidity
/// @notice Notifies SeigManager of Bridged TON balance change
function _notifySeigManager() internal {
    if (seigManager != address(0)) {
        // Low-level call to ensure this never reverts
        try ISeigManager(seigManager).onBridgedTonChange() {} catch {}
    }
}
```

### When Called

| Event | Function | Description |
|-------|----------|-------------|
| TON Deposit (L1→L2) | `_emitERC20BridgeInitiated` | After token transfer completes |
| TON Withdrawal (L2→L1) | `_emitERC20BridgeFinalized` | After token transfer completes |

---

## 6. Verification Flow

### RAT Game Verification

```
triggerAttentionTest(gameAddress, systemConfig, ...) time:
├── msg.sender = DisputeGameFactory
├── trustedFactories[systemConfig] == msg.sender verification
└── gameToTestId[gameAddress] = testId stored

resolveClaim(claimant) time:
├── msg.sender = FaultDisputeGame
└── gameToTestId[msg.sender] existence check
```

### Bridged TON Verification

```
onBridgedTonChange() time:
├── msg.sender = OptimismPortal
├── L1BridgeRegistry.rollupConfigWithPortal(msg.sender) → rollupConfig
└── Layer2Manager.getLayer2BySystemConfig(rollupConfig) → layer2
```

---

## 7. Deployment Configuration

### DisputeGameFactory Setup

```solidity
// Owner calls
disputeGameFactory.setRAT(ratAddress);
disputeGameFactory.setSystemConfig(systemConfigAddress);
```

### L1StandardBridge Setup

```solidity
// ProxyAdmin or Owner calls
l1StandardBridge.setSeigManager(seigManagerAddress);
l1StandardBridge.setTON(tonTokenAddress);
```

---

## 8. Safety

All external calls do not affect the original transaction on failure:

- `triggerAttentionTest`: Wrapped in try-catch
- `resolveClaim`: Wrapped in try-catch
- `onBridgedTonChange`: Wrapped in try-catch

If RAT/SeigManager is not set (zero address), calls are skipped.
