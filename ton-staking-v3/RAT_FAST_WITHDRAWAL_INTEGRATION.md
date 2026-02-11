# RAT Fast Withdrawal - Layer2 Integration Guide

This document describes the contract modifications required for Layer2 projects to integrate RAT Fast Withdrawal.

**Goal:** Reduce 7-day withdrawal delay → Instant withdrawal (RAT validator signatures)

---

## Modified/Created Files

### Optimism Portal

| File | Changes |
|------|---------|
| `src/L1/OptimismPortal2.sol` | Added Fast Withdrawal functions and storage |

### RAT Contract (Already Implemented)

| File | Status |
|------|--------|
| `ton-staking-v2/src/validator/RATFastWithdrawal.sol` | ✅ Implemented |
| `ton-staking-v2/src/libraries/RATFastWithdrawalLib.sol` | ✅ Implemented |

---

## 1. OptimismPortal2 Modifications

**File:** `packages/contracts-bedrock/src/L1/OptimismPortal2.sol`

### 1.1 Added Storage

**Location:** After existing storage variables (around line 100)

```solidity
// ============================================================
// Fast Withdrawal Storage (RAT Integration)
// ============================================================

/// @notice RAT contract address for Fast Withdrawal verification
address public ratContract;

/// @notice RAT-verified withdrawals that can bypass the 7-day delay
mapping(bytes32 => bool) public ratVerifiedWithdrawals;

/// @notice Fast Withdrawal response period (default: 10 minutes)
uint256 public fastWithdrawalResponsePeriod;
```

**Storage Reuse:**
```solidity
/// @notice Existing mapping - reuse for both regular and fast withdrawals
mapping(bytes32 => bool) public finalizedWithdrawals;
```

### 1.2 Added Events

**Location:** With existing events (around line 150)

```solidity
/// @notice Emitted when a fast withdrawal is requested
event FastWithdrawalRequested(
    bytes32 indexed withdrawalHash,
    address indexed user,
    uint256 amount,
    bytes32 stateRoot,
    uint256 feePaid,
    uint256 deadline
);

/// @notice Emitted when a withdrawal is verified by RAT
event RATWithdrawalVerified(bytes32 indexed withdrawalHash);

/// @notice Emitted when a fast withdrawal is finalized
event FastWithdrawalFinalized(bytes32 indexed withdrawalHash, bool success);

/// @notice Emitted when the RAT contract address is updated
event RATContractUpdated(address indexed oldRatContract, address indexed newRatContract);
```

### 1.3 Added Errors

**Location:** With existing errors (around line 200)

```solidity
/// @notice Thrown when a withdrawal has not been verified by RAT
error OptimismPortal_NotVerifiedByRAT();

/// @notice Thrown when the caller is not the RAT contract
error OptimismPortal_OnlyRAT();
```

**Error Reuse:**
```solidity
/// @notice Existing error - reuse for both regular and fast withdrawals
error OptimismPortal_AlreadyFinalized();
```

### 1.4 Added Functions

#### A. proveAndRequestFastWithdrawal()

**Location:** Add as new external function (around line 400)

```solidity
/// @notice Prove withdrawal and request fast withdrawal
/// @param _tx Withdrawal transaction
/// @param _disputeGameIndex Index of dispute game
/// @param _outputRootProof Output root proof
/// @param _withdrawalProof Withdrawal proof
function proveAndRequestFastWithdrawal(
    Types.WithdrawalTransaction memory _tx,
    uint256 _disputeGameIndex,
    Types.OutputRootProof calldata _outputRootProof,
    bytes[] calldata _withdrawalProof
) external payable {
    // Call existing proveWithdrawalTransaction
    proveWithdrawalTransaction(_tx, _disputeGameIndex, _outputRootProof, _withdrawalProof);
    
    // Emit Fast Withdrawal request
    bytes32 withdrawalHash = Hashing.hashWithdrawal(_tx);
    emit FastWithdrawalRequested(
        withdrawalHash,
        msg.sender,
        _tx.value,
        _outputRootProof.stateRoot,
        msg.value,
        block.timestamp + fastWithdrawalResponsePeriod
    );
}
```

#### B. setRATWithdrawalVerified() - RAT Only

**Location:** Add as new external function (around line 430)

```solidity
/// @notice Mark a withdrawal as verified by RAT (RAT only)
/// @param _withdrawalHash Hash of the withdrawal transaction
function setRATWithdrawalVerified(bytes32 _withdrawalHash) external {
    require(msg.sender == ratContract, OptimismPortal_OnlyRAT());
    
    ratVerifiedWithdrawals[_withdrawalHash] = true;
    
    emit RATWithdrawalVerified(_withdrawalHash);
}
```

#### C. fastWithdrawalFinalize()

**Location:** Add as new external function (around line 450)

```solidity
/// @notice Finalize a fast withdrawal (bypass 7-day delay)
/// @param _tx Withdrawal transaction
function fastWithdrawalFinalize(Types.WithdrawalTransaction memory _tx) external {
    bytes32 withdrawalHash = Hashing.hashWithdrawal(_tx);
    
    // Check RAT verification
    require(ratVerifiedWithdrawals[withdrawalHash], OptimismPortal_NotVerifiedByRAT());
    
    // Check not already finalized (reuse existing mapping)
    require(!finalizedWithdrawals[withdrawalHash], OptimismPortal_AlreadyFinalized());
    
    // Transfer assets (using existing Portal logic)
    _transferAssets(_tx);
    
    // Mark as finalized (reuse existing mapping)
    finalizedWithdrawals[withdrawalHash] = true;
    
    emit FastWithdrawalFinalized(withdrawalHash, true);
}
```

#### D. Admin Functions

**Location:** With existing admin functions (around line 500)

```solidity
/// @notice Set RAT contract address (Owner only)
function setRATContract(address _ratContract) external {
    require(msg.sender == guardian(), "OptimismPortal: only guardian");
    
    address oldRatContract = ratContract;
    ratContract = _ratContract;
    
    emit RATContractUpdated(oldRatContract, _ratContract);
}

/// @notice Set fast withdrawal response period (Owner only)
function setFastWithdrawalResponsePeriod(uint256 _period) external {
    require(msg.sender == guardian(), "OptimismPortal: only guardian");
    
    fastWithdrawalResponsePeriod = _period;
}
```

---

## 2. RAT Contract (Already Implemented)

**File:** `ton-staking-v2/src/validator/RATFastWithdrawal.sol`

### 2.1 Core Function

**Location:** Line 330 (already implemented)

```solidity
/// @notice Verify and execute fast withdrawal
/// @param _tx Withdrawal transaction
/// @param input Fast withdrawal input (stateRoot, proofs, signatures, etc.)
/// @param _aggregatedSignature BLS aggregated signature from validators
function verifyAndExecuteFastWithdrawal(
    Types.WithdrawalTransaction calldata _tx,
    RATFastWithdrawalLib.FastWithdrawalInput calldata input,
    bytes calldata _aggregatedSignature
) external payable ifFree whenNotPaused {
    // 1. Validate preconditions (withdrawalHash, systemConfig, etc.)
    address portal = _validateFastWithdrawalPreconditions(input, _tx);
    
    // 2. Check game claims (block if dispute exists)
    if (input.gameAddress != address(0)) {
        uint256 claimCount = IDisputeGame(input.gameAddress).claimDataLen();
        if (claimCount > 0) revert FastWithdrawalGameHasClaimsError();
    }
    
    // 3. Check minimum validators
    uint256 validatorCount = validatorPools[input.systemConfig].activeCount;
    if (validatorCount < minValidatorsForFastWithdrawal) {
        revert FastWithdrawalInsufficientValidatorsError();
    }
    
    // 4. Check unanimous consensus (100% validators)
    if (input.validatorBitmap != (1 << validatorCount) - 1) {
        revert FastWithdrawalNotUnanimousError();
    }
    
    // 5. Verify BLS aggregated signature
    RATFastWithdrawalLib.verifyBLSSignature(input, _aggregatedSignature, aggregatedPubKey);
    
    // 6. Verify adjacent leaves proof
    RATFastWithdrawalLib.verifyAdjacentLeaves(input);
    
    // 7. Notify Portal
    IOptimismPortal2(portal).setRATWithdrawalVerified(input.withdrawalHash);
    
    // 8. Distribute fees to validators and aggregator
    _distributeFees(input.systemConfig, msg.sender);
}
```

### 2.2 Input Structure

**File:** `ton-staking-v2/src/libraries/RATFastWithdrawalLib.sol`  
**Location:** Line 23 (already implemented)

```solidity
struct FastWithdrawalInput {
    bytes32 withdrawalHash;
    address systemConfig;
    address gameAddress;      // For dispute check
    bytes32 stateRoot;
    uint256 validatorBitmap;  // Signed validators bitmap
    bytes32 leafA;            // Adjacent leaf A
    bytes32 leafB;            // Adjacent leaf B
    bytes[] proofsA;          // Merkle proof for leaf A
    bytes[] proofsB;          // Merkle proof for leaf B
}
```

---

## 3. Integration Flow

### Call Sequence

```
User → Portal.proveAndRequestFastWithdrawal()
    ↓ emit FastWithdrawalRequested
Validators → Generate BLS signatures (offchain)
    ↓
Aggregator → RAT.verifyAndExecuteFastWithdrawal()
    ↓ verify BLS signatures + adjacent leaves
RAT → Portal.setRATWithdrawalVerified()
    ↓
User → Portal.fastWithdrawalFinalize()
    ↓ transfer assets
Done (3 minutes vs 7 days)
```

### Access Control

| Function | Caller | Restriction |
|----------|--------|-------------|
| `proveAndRequestFastWithdrawal` | Anyone | Fee required |
| `setRATWithdrawalVerified` | **RAT only** | `OptimismPortal_OnlyRAT` |
| `fastWithdrawalFinalize` | Anyone | RAT verification required |
| `verifyAndExecuteFastWithdrawal` | Anyone (Aggregator) | Valid BLS signature required |

---

## 4. Key Security Features

### 4.1 Access Control

```solidity
// CRITICAL: Only RAT can mark withdrawal as verified
require(msg.sender == ratContract, OptimismPortal_OnlyRAT());
```

### 4.2 Double Withdrawal Prevention

```solidity
// Reuse existing mapping - prevents both regular and fast withdrawal replay
require(!finalizedWithdrawals[withdrawalHash], OptimismPortal_AlreadyFinalized());
```

### 4.3 Game Claim Check

```solidity
// Block fast withdrawal if dispute exists
if (claimCount > 0) revert FastWithdrawalGameHasClaimsError();
```

### 4.4 Unanimous Consensus

```solidity
// All validators must sign (N-of-N)
if (validatorBitmap != (1 << validatorCount) - 1) {
    revert FastWithdrawalNotUnanimousError();
}
```

---

## 5. Deployment Steps

### Step 1: Deploy/Configure RAT

```bash
# Set minimum validators
cast send $RAT "setMinValidatorsForFastWithdrawal(uint256)" 3

# Set aggregator fee rate (10%)
cast send $RAT "setAggregatorFeeRate(uint256)" 1e26
```

### Step 2: Upgrade OptimismPortal2

```bash
# Deploy new implementation with Fast Withdrawal functions
forge script script/UpgradePortal.s.sol --broadcast
```

### Step 3: Connect Portal and RAT

```bash
# Portal: Set RAT address
cast send $PORTAL "setRATContract(address)" $RAT

# Portal: Set response period (10 minutes)
cast send $PORTAL "setFastWithdrawalResponsePeriod(uint256)" 600
```

### Step 4: Register Validators

```bash
# Each validator registers BLS public key
cast send $RAT "registerValidator(address)" $SYSTEM_CONFIG
cast send $RAT "registerBLSPublicKey(address,bytes,bytes)" \
  $SYSTEM_CONFIG $BLS_PUBKEY $BLS_SIGNATURE
```

---

## 6. Verification Checklist

### OptimismPortal2

- [ ] `ratContract` storage added
- [ ] `ratVerifiedWithdrawals` mapping added
- [ ] `fastWithdrawalResponsePeriod` storage added
- [ ] `proveAndRequestFastWithdrawal()` implemented
- [ ] `setRATWithdrawalVerified()` implemented with RAT-only access control
- [ ] `fastWithdrawalFinalize()` implemented
- [ ] Admin functions implemented
- [ ] 4 events added
- [ ] 2 errors added

### RAT Integration

- [ ] RAT contract deployed
- [ ] Portal.setRATContract() called
- [ ] Portal.setFastWithdrawalResponsePeriod() called
- [ ] RAT.setMinValidatorsForFastWithdrawal() called
- [ ] Validators registered with BLS keys

### Testing

- [ ] Normal fast withdrawal flow
- [ ] Access control (only RAT can verify)
- [ ] Double withdrawal prevention
- [ ] Game claim check

---

## 7. Implementation Notes

### Storage Optimization

- ✅ Reuse existing `finalizedWithdrawals` mapping for both regular and fast withdrawals
- ✅ Reuse existing error `OptimismPortal_AlreadyFinalized` for both types
- ✅ Only 3 new storage variables needed (`ratContract`, `ratVerifiedWithdrawals`, `fastWithdrawalResponsePeriod`)

### Custom Gas Token Support

OptimismPortal2 already supports both Native ETH and Custom Gas Token.  
Fast Withdrawal uses the existing asset transfer logic - no additional changes needed.

---

## 8. Gas Costs

| Operation | Gas | Notes |
|-----------|-----|-------|
| `proveAndRequestFastWithdrawal` | ~80k | Existing prove + event |
| `verifyAndExecuteFastWithdrawal` | ~280k | BLS + adjacent leaves verification |
| `fastWithdrawalFinalize` | ~50k | Asset transfer + state update |
| **Total** | **~410k** | vs 7 days wait |

---

## 9. op-proposer Gas Limit Fix

### Problem

`DisputeGameFactory.create()`에서 `IRAT.triggerAttentionTest()`가 try-catch로 감싸져 있어,
RAT 호출이 가스 부족으로 실패해도 트랜잭션은 성공합니다.
이로 인해 op-proposer의 `eth_estimateGas`가 RAT에 필요한 가스를 제외한 최소값만 반환합니다.

| 시나리오 | gasLimit | gasUsed | RAT 결과 |
|----------|----------|---------|----------|
| eth_estimateGas (수정 전) | ~475,000 | ~468,000 | out of gas (try-catch로 무시됨) |
| 명시적 설정 (수정 후) | 1,500,000 | ~943,000 | AttentionTestTriggered 성공 |

### Fix

**File:** `op-proposer/contracts/disputegamefactory.go` - `ProposalTx` 함수

```go
candidate.Value = initBond
// Set explicit gas limit to ensure sufficient gas for RAT triggerAttentionTest
// called via try-catch in DGF.create(). eth_estimateGas underestimates because
// the try-catch makes the tx succeed even when RAT call runs out of gas.
candidate.GasLimit = 1_500_000
return candidate, err
```

### Why 1,500,000?

- 게임 생성 기본 가스: ~506,000
- RAT triggerAttentionTest 추가 가스: ~437,000
- 합계: ~943,000
- 여유분 포함: 1,500,000

> **Note:** RAT 검증자가 없는 경우에도 이 가스 리밋이 적용되지만,
> 실제 가스는 ~506,000만 소비되므로 추가 비용은 없습니다 (미사용 가스는 환불됨).

---

## 10. RAT Client (Validator) Configuration

### rat-client-type3 Configuration Fix

**Repository:** `ton-staking-v2/clients/rat-client-type3/`

The RAT validator client monitors `AttentionTestTriggered` events and submits evidence (adjacent leaves proof) within the deadline. Two critical configuration parameters affect evidence submission success:

#### Problem

The original configuration prevented evidence submission:
- `DeadlineBuffer` was set to 600 seconds (= `evidenceSubmissionPeriod`)
- By the time the client detected an event, less than 600s remained before deadline
- The client always rejected with: `"deadline too close: N seconds remaining"`

#### Fix

**File: `pkg/client/config.go`**

| Parameter | Before | After | Description |
|-----------|--------|-------|-------------|
| `Confirmations` | 2 | **1** | L1 blocks to wait before treating events as final |
| `DeadlineBuffer` | 10 min | **2 min** | Safety margin before deadline to stop submission attempts |

```go
// Default config changes
Confirmations:  1,                    // Detect events faster (was 2)
DeadlineBuffer: 2 * time.Minute,      // Submit up to 2 min before deadline (was 10 min)
```

**File: `pkg/client/service_adjacent.go`**

- Added `deadlineBuffer` field to `RATClientAdjacentService` struct
- Replaced hardcoded `600s` deadline check with configurable buffer from config

```go
// Before (hardcoded):
if timeRemaining < 600 {
    return fmt.Errorf("deadline too close: %d seconds remaining", timeRemaining)
}

// After (configurable):
bufferSeconds := int64(s.deadlineBuffer.Seconds())
if timeRemaining < bufferSeconds {
    return fmt.Errorf("deadline too close: %d seconds remaining (buffer=%ds)", timeRemaining, bufferSeconds)
}
```

**File: `cmd/main.go`**

- Added `DeadlineBuffer` passthrough from config to `AdjacentServiceConfig`

#### Evidence Submission Flow

```
L1: AttentionTestTriggered event emitted
  ↓ (wait Confirmations blocks)
Client: Detect event via FilterLogs
  ↓ (check deadline - buffer)
Client: Query L2 state via debug_accountRange
  ↓
Client: Generate adjacent leaves proof via eth_getProof
  ↓
Client: Submit evidence tx to L1 RAT contract
```

#### L2 RPC Requirements

The validator client requires the following L2 RPC methods:

| Method | Purpose | Namespace |
|--------|---------|-----------|
| `debug_accountRange` | Iterate state trie to find adjacent account leaves | `debug` |
| `eth_getProof` | Generate Merkle proofs for adjacent leaves | `eth` |
| `eth_getBlockByNumber` | Fetch block header for StateRoot | `eth` |

> **Important:** The L2 node (op-geth) must have `debug` API enabled:
> `--http.api=eth,net,web3,debug,txpool,miner`

---

## 11. References

### Current Implementation

- RAT Fast Withdrawal: `ton-staking-v2/src/validator/RATFastWithdrawal.sol`
- Fast Withdrawal Library: `ton-staking-v2/src/libraries/RATFastWithdrawalLib.sol`
- BLS Library: `ton-staking-v2/src/libraries/BLS12381.sol`
- Adjacent Leaves Verifier: `ton-staking-v2/src/libraries/AdjacentLeavesVerifier.sol`
- Game Claim Check: `ton-staking-v2/docs/rat-fast-withdrawal/GAME_CLAIM_CHECK.md`

### Optimism Base

- OptimismPortal2: `optimism/packages/contracts-bedrock/src/L1/OptimismPortal2.sol`
- Types: `optimism/packages/contracts-bedrock/src/libraries/Types.sol`

---

*Last Updated: 2026-02-09*
