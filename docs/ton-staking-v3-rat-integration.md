# TON Staking V3 RAT Integration - Completion Report

## Overview

Removed existing RAT implementation from Optimism and modified to integrate with TON Staking V3's RAT system.

**Status**: ✅ Complete (2024-12-12)

**Test Results**: All 307 dispute tests passed

---

## Modified Files

### Solidity Contracts

| File | Action | Status |
|------|--------|--------|
| `interfaces/L1/IRAT.sol` | Modified interface (TON Staking V3 signature) | ✅ Done |
| `interfaces/L1/IOPContractsManager.sol` | Removed Blueprints.rat field | ✅ Done |
| `interfaces/dispute/IDisputeGameFactory.sol` | Added systemConfig getter/setter | ✅ Done |
| `src/dispute/DisputeGameFactory.sol` | Added systemConfig, zero address check | ✅ Done |
| `src/L1/OPContractsManager.sol` | Removed RAT deployment, added auto-config | ✅ Done |
| `src/L1/RAT.sol` | Deleted | ✅ Done |
| `scripts/deploy/ChainAssertions.sol` | Removed RAT references | ✅ Done |
| `scripts/deploy/DeployImplementations.s.sol` | Removed RAT deployment logic | ✅ Done |
| `scripts/deploy/DeployOPChain.s.sol` | Removed RAT configuration | ✅ Done |
| `scripts/libraries/Types.sol` | Removed RAT fields | ✅ Done |

### Test Files

| File | Action | Status |
|------|--------|--------|
| `test/L1/RAT.t.sol` | Deleted | ✅ Done |
| `test/L1/RAT_GasTest.sol` | Deleted | ✅ Done |
| `test/L1/RAT_Simple_Test.sol` | Deleted | ✅ Done |
| `test/L1/DisputeGameFactory_GasTest.sol` | Deleted | ✅ Done |

### Go Files

| File | Action | Status |
|------|--------|--------|
| `op-deployer/pkg/deployer/opcm/implementations.go` | Removed RATImpl | ✅ Done |
| `op-deployer/pkg/deployer/opcm/opchain.go` | Removed RATProxy | ✅ Done |
| `op-deployer/pkg/deployer/pipeline/implementations.go` | Removed RATImpl | ✅ Done |
| `op-deployer/pkg/deployer/pipeline/opchain.go` | Removed RAT config | ✅ Done |
| `op-chain-ops/interopgen/deployments.go` | Removed RAT fields | ✅ Done |
| `op-chain-ops/addresses/contracts.go` | Removed RAT fields | ✅ Done |
| `op-e2e/faultproofs/rat_simple_test.go` | Deleted | ✅ Done |
| `op-e2e/faultproofs/rat_e2e_test.go` | Deleted | ✅ Done |
| `op-e2e/faultproofs/rat_unit_test.go` | Deleted | ✅ Done |
| `op-e2e/bindings/rat.go` | Deleted | ✅ Done |
| `op-challenger/game/fault/contracts/rat.go` | Deleted | ✅ Done |

### Documentation

| File | Action | Status |
|------|--------|--------|
| `op-challenger/scripts/docs/rat/` | Entire directory deleted | ✅ Done |
| `op-challenger/scripts/README.md` | Removed RAT references | ✅ Done |

---

## Key Changes

### 1. IRAT Interface Modification

**File**: `packages/contracts-bedrock/interfaces/L1/IRAT.sol`

```solidity
// Matches TON Staking V2 IRAT interface
// gameAddress removed - RAT identifies via msg.sender context
function triggerAttentionTest(
    address systemConfig,
    uint32 batchIndex,
    bytes32 batchHash,
    bytes32 blockHash
) external;

// systemConfig not needed - RAT identifies game via msg.sender
function resolveClaim(address claimant) external;
```

**Note**:
- `triggerAttentionTest`: RAT identifies DisputeGameFactory via `msg.sender`
- `resolveClaim`: RAT identifies FaultDisputeGame via `msg.sender`

---

### 2. DisputeGameFactory Modifications

**File**: `packages/contracts-bedrock/src/dispute/DisputeGameFactory.sol`

#### Added State Variables (lines 74-78)
```solidity
/// @notice RAT contract address (TON Staking V3 RAT)
address public rat;

/// @notice SystemConfig address for RAT L2 identification
address public systemConfig;
```

#### Zero Address Check Added (lines 180-185)
```solidity
// Initialize with RAT address if CANNON game type and RAT is configured
if (_gameType.raw() == GameTypes.CANNON.raw() && rat != address(0)) {
    IInitializable(address(proxy_)).initialize{ value: msg.value }(rat);
} else {
    proxy_.initialize{ value: msg.value }();
}
```

#### RAT Trigger Call (lines 201-210)
```solidity
// Trigger RAT attention test if RAT contract is set and game type is CANNON
// RAT identifies the game via msg.sender (this factory) and batchIndex
if (rat != address(0) && _gameType.raw() == GameTypes.CANNON.raw()) {
    try IRAT(rat).triggerAttentionTest(
        systemConfig,
        uint32(_disputeGameList.length - 1),
        Claim.unwrap(_rootClaim),
        parentHash
    ) { } catch { }
}
```

#### Setter Functions (lines 306-318)
```solidity
/// @notice Sets the RAT contract address.
function setRAT(address _rat) external onlyOwner {
    rat = _rat;
}

/// @notice Sets the SystemConfig address for RAT L2 identification.
function setSystemConfig(address _systemConfig) external onlyOwner {
    systemConfig = _systemConfig;
}
```

---

### 3. IOPContractsManager Fix (Critical Bug Fix)

**File**: `packages/contracts-bedrock/interfaces/L1/IOPContractsManager.sol`

**Problem**: `Blueprints` struct still had `address rat;` field causing ABI encoding mismatch (CHECK-OPCM-50 error)

**Solution**: Removed `address rat;` field

```solidity
struct Blueprints {
    address addressManager;
    address proxy;
    address proxyAdmin;
    address l1ChugSplashProxy;
    address resolvedDelegateProxy;
    address permissionedDisputeGame1;
    address permissionedDisputeGame2;
    address permissionlessDisputeGame1;
    address permissionlessDisputeGame2;
    address superPermissionedDisputeGame1;
    address superPermissionedDisputeGame2;
    address superPermissionlessDisputeGame1;
    address superPermissionlessDisputeGame2;
    // NOTE: rat blueprint removed - RAT is deployed separately by TON Staking V3
}
```

---

## Parameter Mapping

### triggerAttentionTest (called by DisputeGameFactory)

| TON Staking V2 Parameter | Value from Optimism |
|--------------------------|---------------------|
| `msg.sender` | DisputeGameFactory address (for identifying the L2) |
| `systemConfig` | `DisputeGameFactory.systemConfig` state variable |
| `batchIndex` | `uint32(_disputeGameList.length - 1)` |
| `batchHash` | `Claim.unwrap(_rootClaim)` |
| `blockHash` | `parentHash` (`blockhash(block.number - 1)`) |

### resolveClaim (called by FaultDisputeGame)

| TON Staking V2 Parameter | Value from Optimism |
|--------------------------|---------------------|
| `msg.sender` | FaultDisputeGame address (for identifying the game) |
| `claimant` | Bond recipient address (winner) |

---

## Deployment & Configuration

### Automatic Configuration (OPContractsManager)

When deploying via OPContractsManager with `DeployInput.ratAddress` set:

**File**: `packages/contracts-bedrock/src/L1/OPContractsManager.sol` (lines 1169-1175)

```solidity
// Configure RAT and SystemConfig on DisputeGameFactory
// RAT is deployed separately by TON Staking V3, address comes from DeployInput
// SystemConfig is created during this deployment
if (_input.ratAddress != address(0)) {
    IDisputeGameFactory(address(output.disputeGameFactoryProxy)).setRAT(_input.ratAddress);
    IDisputeGameFactory(address(output.disputeGameFactoryProxy)).setSystemConfig(address(output.systemConfigProxy));
}
```

### Deployment Order

1. **Deploy TON Staking V3 RAT** (separate project) → Get RAT address
2. **Deploy Optimism L2** with `DeployInput.ratAddress` set
   - SystemConfig is created automatically
   - `setRAT()` and `setSystemConfig()` are called automatically before ownership transfer
3. **Done** - No manual configuration needed

### Manual Configuration (if needed)

If RAT was not configured during deployment:
```solidity
DisputeGameFactory.setRAT(tonStakingV3RatAddress);
DisputeGameFactory.setSystemConfig(systemConfigAddress);
```

---

## Zero Address Behavior

When `ratAddress` is zero address (`address(0)`):
- `DisputeGameFactory.create()`:
  - Uses regular `initialize()` even for CANNON game type
  - Skips RAT `triggerAttentionTest()` call
- `FaultDisputeGame.resolveClaimRat()`:
  - Skips RAT `resolveClaim()` call

---

## Test Results

```
Ran 82 test suites in 24.62s (142.69s CPU time): 307 tests passed, 0 failed, 0 skipped (307 total tests)
```

All dispute-related tests passed:
- FaultDisputeGame tests
- PermissionedDisputeGame tests
- SuperFaultDisputeGame tests
- DisputeGameFactory tests
- AnchorStateRegistry tests
- DelayedWETH tests

---

## Important Notes

1. **Deployment Order**: TON Staking V3 RAT must be deployed first, then set via `DeployInput.ratAddress`
2. **Automatic Config**: When using OPContractsManager, RAT and SystemConfig are set automatically
3. **RAT Not Configured**: If RAT address is 0, all RAT-related calls are safely skipped
4. **Backward Compatibility**: External code using the old IRAT interface must be updated

---

## Event Flow for Validators

### Game Creation Flow
```
DisputeGameFactory.create()
    │
    ├─► Creates FaultDisputeGame
    │
    └─► IRAT.triggerAttentionTest(systemConfig, batchIndex, batchHash, blockHash)
            │                      // msg.sender = DisputeGameFactory
            │
            └─► TON Staking V2 RAT emits:
                event AttentionTestTriggered(
                    bytes32 indexed testId,
                    address indexed validator,
                    address indexed systemConfig,  // ← L2 identifier
                    uint32 batchIndex,
                    uint256 deadline
                )
```

### Claim Resolution Flow
```
FaultDisputeGame.resolveClaim()
    │
    └─► IRAT.resolveClaim(claimant)
            │              // msg.sender = FaultDisputeGame
            │
            └─► TON Staking V2 RAT processes reward/penalty
```

Validators monitor `AttentionTestTriggered` event to:
1. Check `systemConfig` to identify which L2 chain
2. Verify if `validator` matches their address
3. Get `batchIndex` to know which batch to verify
4. Submit evidence before `deadline`
