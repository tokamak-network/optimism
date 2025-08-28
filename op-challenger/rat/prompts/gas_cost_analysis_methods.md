# RAT Gas Cost Analysis Methods and Results

## 📊 Overview

This document is a comprehensive report analyzing gas usage for all functions and various scenarios of the RAT (Randomized Attention Test) contract in Optimism. RAT is a smart contract for challenger monitoring and testing, where gas efficiency is a critical factor.

## 🔬 Gas Measurement Methodology

### Measurement Environment
- **Test Framework**: Foundry
- **Measurement Method**: Internal function call simulation using `vm.prank()`
- **Gas Measurement Code**:
```solidity
uint256 gasStart = gasleft();
functionCall();
uint256 gasUsed = gasStart - gasleft();
```

### ⚠️ Important: Gas Cost Interpretation
**All gas costs reported in this document are measured in the Foundry test environment and do not include intrinsic gas (21,000 gas).**

- **Test Environment Gas Cost**: Gas cost of function logic only
- **Actual Network Gas Cost**: Test value + 21,000 gas (intrinsic gas)

### Total Gas Cost Calculation in Actual Network
```
Actual Total Gas Cost = Document Gas Cost + 21,000 gas
```

Examples:
- `resolveClaim()` (ignored): 1,565 + 21,000 = **22,565 gas**
- `submitCorrectEvidence()`: 7,520 + 21,000 = **28,520 gas**
- `DisputeGameFactory.create()`: 163,991 + 21,000 = **184,991 gas**

## Analysis Target Scenarios

To analyze gas cost changes due to the introduction of RAT (Reactive Attention Test), we measure the following five scenarios:

// Chart

## 📊 Complete Scenario Gas Cost Summary Table

| Scenario | Role | Function | Case | Test Gas Usage | Actual Network Gas | Description | Status |
|----------|------|----------|------|----------------|-------------------|-------------|--------|
| **1** | Proposer | `DisputeGameFactory.create()` | No RAT | **163,991 gas** | **184,991 gas** | Game creation with game type without RAT | ✅ Success |
| **2** | Proposer | `DisputeGameFactory.create()` | RAT deployed, not triggered | **~163,991 gas** | **~184,991 gas** | RAT is deployed but not called | 🔄 Expected |
| **3a** | Proposer | `DisputeGameFactory.create()` + `triggerAttentionTest()` | Valid challengers exist | **~296,369 gas** | **~317,369 gas** | Game creation + challenger selection, bond deduction | 🔄 Expected |
| **3b** | Proposer | `DisputeGameFactory.create()` + `triggerAttentionTest()` | No valid challengers | **~178,668 gas** | **~199,668 gas** | Game creation + condition check only, silently ignored | 🔄 Expected |
| **4** | Validator | `submitCorrectEvidence()` | Success | **7,520 gas** | **28,520 gas** | Evidence verification, bond refund | ✅ Success |
| **5a** | Validator | `resolveClaim()` | AttentionTest participant | **4,857 gas** | **25,857 gas** | Bond refund, state update | ✅ Success |
| **5b** | Validator | `resolveClaim()` | Not AttentionTest participant | **1,565 gas** | **22,565 gas** | Condition check only, silently ignored | ✅ Success |

### 📈 Gas Cost Comparison Analysis

| Comparison Item | Scenario | Test Gas Cost | Actual Network Gas Cost | Difference |
|-----------------|----------|---------------|------------------------|------------|
| **Game Creation** | No RAT vs RAT deployed | 163,991 vs ~163,991 | 184,991 vs ~184,991 | Same |
| **RAT Trigger** | Execute (valid challengers exist) vs Skip (condition check only) | 132,378 vs 14,677 | 153,378 vs 35,677 | 4.3x difference |
| **Evidence Submission** | submitCorrectEvidence | 7,520 | 28,520 | Very efficient |
| **Game Resolution** | (Attention test) participant vs (Attention test) non-participant | 4,857 vs 1,565 | 25,857 vs 22,565 | 1.15x difference |

### 🎯 Key Conclusions

1. **Game creation overhead due to RAT introduction**: Minimized (conditional execution)
2. **Gas efficiency**: All functions optimized with conditional execution
3. **Error handling**: Gas savings through silent ignore
4. **Scalability**: Flexible design capable of handling various scenarios
5. **Actual operational cost**: Still efficient even with intrinsic gas included

### 1. Proposer: Gas cost to post L2 state root in the original version (current OP mainnet)

**Analysis Method:**
- Measure gas cost when calling `DisputeGameFactory.create()` function (without RAT)

**Measurement Points:**
- Gas cost for `DisputeGameFactory.create()` function call (game creation)
- Event emission cost

**Actual Measurement Results:**
- **Gas Usage**: 163,991 gas
- **Description**: Gas cost for game creation with game type without RAT

### 2. Proposer: Gas cost to post L2 state root in RAT when RAT is not triggered

**Analysis Method:**
- Case where RAT is deployed but `triggerAttentionTest` is not called
- Case where RAT call is not made in `DisputeGameFactory.create()` function

**Measurement Points:**
- Gas cost for `DisputeGameFactory.create()` function execution (no RAT call)
- Game creation cost

**Expected Results:**
- **Gas Usage**: ~163,991 gas (no RAT call)
- **Description**: Case where RAT is deployed but not actually called

### 3. Proposer: Gas cost to post L2 state root in RAT when RAT is triggered

**Analysis Method:**
- Case where RAT is deployed and `triggerAttentionTest` is triggered
- Distinguish between cases with and without valid challengers

**Measurement Points:**
- Gas cost for `DisputeGameFactory.create()` function execution
- Gas cost for RAT's `triggerAttentionTest()` function call

**Detailed Scenarios:**
- **3a. When valid challengers exist**: Challenger selection, bond deduction, AttentionInfo creation
- **3b. When no valid challengers exist**: RAT called but execution logic skipped

**Expected Results:**
- **3a. Valid challengers exist**: ~163,991 + 132,378 = ~296,369 gas
- **3b. No valid challengers**: ~163,991 + 14,677 = ~178,668 gas

### 4. Validator: Gas cost to submit a correct solution (Lv, Rv) in RAT

**Analysis Method:**
- Case where challenger submits correct evidence to receive refund of slashed amount
- Gas cost when calling `submitCorrectEvidence()` function

**Measurement Points:**
- Gas cost for `submitCorrectEvidence()` function execution
- Evidence verification cost (keccak256 hash calculation)
- Challenger information update (stakingAmount increase)
- Validity state change logic

**Actual Measurement Results:**
- **Gas Usage**: 7,520 gas
- **Description**: Evidence verification, bond refund

### 5. Validator: Gas cost for resolveClaim in different scenarios

**Analysis Method:**
- Case where challenger participating in game receives bond through `resolveClaim()`
- Analysis of two cases based on RAT attention test participation

**Measurement Points:**
- Gas cost for `resolveClaim()` function execution
- Challenger state update cost
- Bond refund processing cost

**Detailed Scenarios:**

#### **5a. RAT attention test participant case**
- **Situation**: Challenger participated in RAT's attention test and had bond deducted
- **Processing**: Receives both bond and attention bond refund when `resolveClaim()` is called
- **Actual Measurement Results**: **Gas Usage**: 4,857 gas
- **Description**: Bond refund, state update, event emission

#### **5b. Challenger not participating in the specific attention test case**
- **Situation**: Challenger did not participate in RAT's attention test, so `attentionTests[msg.sender].challengerAddress` is different
- **Processing**: `resolveClaim()` call is silently ignored at the first condition
- **Actual Measurement Results**: **Gas Usage**: 1,565 gas (condition check only)
- **Description**: Only condition check performed and silently ignored (gas savings)


## 🔍 Measured Gas Usage (Complete List)

### Gas Usage by Major Function

| Function | Case | Gas Usage | Description | Status |
|----------|------|-----------|-------------|--------|
| **`DisputeGameFactory.create()`** | No RAT | **163,991 gas** | Game creation with game type without RAT | ✅ Success |
| **`stake()`** | General staking | **67,177 gas** | Basic staking (0.2 ETH) | ✅ Success |
| **`stake()`** | Valid challenger registration | **114,711 gas** | Staking that registers as valid challenger (2 ETH) | ✅ Success |
| **`triggerAttentionTest()`** | Valid challengers exist | **132,378 gas** | Challenger selection, bond deduction, AttentionInfo creation | ✅ Success |
| **`triggerAttentionTest()`** | No valid challengers | **14,677 gas** | Silently ignored (gas savings) | ✅ Success |
| **`submitCorrectEvidence()`** | Success | **7,520 gas** | Evidence verification, bond refund | ✅ Success |
| **`resolveClaim()`** | Success (attention test validator) | **4,857 gas** | Bond refund, state update | ✅ Success |
| **`resolveClaim()`** | Non-participant (not attention test validator) | **1,565 gas** | Condition check only, silently ignored | ✅ Success |

## 📈 Detailed Gas Analysis

### 1. `DisputeGameFactory.create()` Function Analysis

#### **Game Creation (No RAT) (163,991 gas)**
- **Test Environment Gas Cost**: 163,991 gas (intrinsic gas excluded)
- **Actual Network Gas Cost**: 184,991 gas (intrinsic gas included)
- **Game implementation clone creation**: Efficient clone creation using LibClone
- **Game initialization**: `initialize()` function call
- **Storage update**: Game information storage and mapping update
- **Event emission**: `DisputeGameCreated` event

### 2. `stake()` Function Analysis

#### **General Staking (67,177 gas)**
- **Test Environment Gas Cost**: 67,177 gas (intrinsic gas excluded)
- **Actual Network Gas Cost**: 88,177 gas (intrinsic gas included)
- **Storage write**: `challengers[msg.sender].stakingAmount` update
- **Event emission**: `ChallengerStaked` event
- **Condition check**: `perTestBondAmount` comparison

#### **Valid Challenger Registration (114,711 gas)**
- **Additional cost**: +47,534 gas
- **Additional work**:
  - Set `challengers[msg.sender].isValid = true`
  - Set `challengers[msg.sender].validatorIndex`
  - Add `msg.sender` to `validChallengers` array

### 3. `triggerAttentionTest()` Function Analysis

#### **Valid Challengers Exist (132,378 gas)**
- **Challenger selection**: Hash-based random selection
- **Bond calculation**: `stakingAmount` vs `perTestBondAmount` comparison
- **Storage update**: Challenger information, AttentionInfo creation
- **Validity check**: Challenger state update
- **Event emission**: `AttentionTriggered` event

#### **No Valid Challengers (14,677 gas)**
- **Condition check only**: `validChallengersLength > 1` verification
- **Silent ignore**: No work performed
- **Gas savings**: Prevents unnecessary work

### 4. `submitCorrectEvidence()` Function Analysis

#### **Success (7,520 gas)**
- **Evidence verification**: `keccak256(proofLV, proofRV)` vs `stateRoot` comparison
- **Bond refund**: Add bond to `stakingAmount`
- **State update**: `evidenceSubmitted = true`
- **Validity check**: Challenger state update
- **Event emission**: `CorrectEvidenceSubmitted` event

### 5. `resolveClaim()` Function Analysis

#### **Success (4,857 gas)**
- **Bond refund**: Add bond to `stakingAmount`
- **State update**: `evidenceSubmitted = true`
- **Validity check**: Challenger state update
- **Event emission**: `BondRefunded` event

#### **Wrong Claimant (1,565 gas)**
- **Condition check only**: `challengerAddress == _claimant` verification
- **Silent ignore**: No work performed
- **Gas savings**: Prevents unnecessary work

## 🎯 Various Cases for Each Function

### 1. `triggerAttentionTest()` Function Cases

#### **✅ Success Cases:**
- **When valid challengers exist**: `validChallengersLength > 1`
  - Challenger selection and bond deduction
  - AttentionInfo creation
  - Event emission

#### **⚠️ Ignored Cases:**
- **When no valid challengers exist**: `validChallengersLength <= 1`
  - No work performed (silently ignored)

### 2. `submitCorrectEvidence()` Function Cases

#### **✅ Success Cases:**
- **Normal evidence submission**: Correct challenger submits correct evidence

#### **❌ Failure Cases:**
1. **`AttentionTestNotExists()`**: Non-existent game address
2. **`InvalidChallengerAddress()`**: Wrong challenger submits evidence
3. **`EvidenceAlreadySubmitted()`**: Evidence already submitted
4. **`EvidenceSubmissionExpired()`**: Submission period expired
5. **`ProofVerificationFailed()`**: Wrong evidence (wrong proofLV/proofRV)

### 3. `resolveClaim()` Function Cases

#### **✅ Success Cases:**
- **Normal claim resolution**: Correct game contract calls for correct claimant

#### **⚠️ Ignored Cases:**
1. **Wrong claimant**: `challengerAddress != _claimant`
2. **Non-existent game**: `challengerAddress == address(0)`
3. **Already resolved claim**: `evidenceSubmitted == true`

## ⭐ Gas Efficiency Evaluation

### **RAT's gas usage is very efficient:**

**Note: The following comparison values are total gas costs from actual network transactions (including intrinsic gas):**

- **General ERC20 transfer**: ~65,000 gas (total network cost)
- **ERC721 mint**: ~100,000+ gas (total network cost)
- **Complex DeFi function**: 100,000-500,000 gas (total network cost)

**When comparing with RAT functions, use the "Actual Network Gas" column values for fair comparison.**

### **Gas Usage Summary:**

| Function | Test Gas Usage | Actual Network Gas |
|----------|----------------|-------------------|
| **`resolveClaim()` (ignored)** | 1,565 gas | 22,565 gas |
| **`resolveClaim()` (success)** | 4,857 gas | 25,857 gas |
| **`submitCorrectEvidence()`** | 7,520 gas | 28,520 gas |
| **`stake()` (general)** | 67,177 gas | 88,177 gas |
| **`stake()` (valid challenger)** | 114,711 gas | 135,711 gas |
| **`triggerAttentionTest()` (success)** | 132,378 gas | 153,378 gas |
| **`triggerAttentionTest()` (ignored)** | 14,677 gas | 35,677 gas |
| **`DisputeGameFactory.create()`** | 163,991 gas | 184,991 gas |


## 📋 Test Commands

### **Individual Function Tests:**
```bash
# Game creation (no RAT)
forge test --match-test test_create_game_without_rat_gas_measurement -vv

# Basic staking test
forge test --match-test test_stake_gas_measurement -vv

# Valid challenger staking test
forge test --match-test test_stake_valid_challenger_gas_measurement -vv

# Attention test trigger (success)
forge test --match-test test_triggerAttentionTest_gas_measurement -vv

# Attention test trigger (ignored)
forge test --match-test test_triggerAttentionTest_no_valid_challengers_gas_measurement -vv

# Evidence submission test
forge test --match-test test_submitCorrectEvidence_gas_measurement -vv

# Claim resolution test (success)
forge test --match-test test_resolveClaim_gas_measurement -vv

# Claim resolution test (ignored)
forge test --match-test test_resolveClaim_wrong_claimant_gas_measurement -vv
```

### **All Gas Measurement Tests:**
```bash
# All gas measurement tests
forge test --match-test test_.*_gas_measurement -vv

# All RAT tests
forge test --match-test test_.* -vv
```

## 🎯 Key Conclusions

### **1. Gas Efficiency**
- **All functions implemented very efficiently**
- **Prevents unnecessary gas usage through conditional execution**
- **Gas optimization through storage slot packing**

### **2. Safety**
- **All error cases properly handled**
- **Appropriate choice between silent ignore vs explicit revert**
- **Complete type safety and range validation**

### **3. Usability**
- **Intuitive function interface**
- **Clear event emission**
- **Predictable behavior**

### **4. Scalability**
- **Modular design**
- **Upgradeable structure**
- **Flexible configuration possible**

## Scenario-based Gas Cost Analysis

### **Scenario 1: Original OP Mainnet**
- **Gas Cost**: 163,991 gas
- **Description**: Game creation cost of current OP mainnet without RAT

### **Scenario 2: RAT Deployed, Not Triggered**
- **Expected Gas Cost**: ~163,991 gas
- **Description**: Case where RAT is deployed but not actually called

### **Scenario 3a: RAT Triggered (Valid Challengers Exist)**
- **Expected Gas Cost**: ~296,369 gas (163,991 + 132,378)
- **Included Work**:
  - Game creation (163,991 gas)
  - Challenger selection (hash-based random selection)
  - Bond calculation and deduction
  - AttentionInfo struct creation and storage
  - Challenger state update
  - Event emission

### **Scenario 3b: RAT Triggered (No Valid Challengers)**
- **Expected Gas Cost**: ~178,668 gas (163,991 + 14,677)
- **Included Work**:
  - Game creation (163,991 gas)
  - Condition check only (`validChallengersLength > 1`)
  - Silent ignore (gas savings)

### **Scenario 4: Validator Evidence Submission**
- **Gas Cost**: 7,520 gas (submitCorrectEvidence success)
- **Included Work**:
  - Evidence verification (keccak256 hash calculation)
  - Bond refund (stakingAmount increase)
  - State update (evidenceSubmitted = true)
  - Challenger validity check and update
  - Event emission

### **Scenario 5a: RAT Attention Test Participant resolveClaim**
- **Gas Cost**: 4,857 gas
- **Included Work**:
  - Bond refund (add to stakingAmount)
  - Attention bond refund (add to stakingAmount)
  - State update (evidenceSubmitted = true)
  - Challenger validity check and update
  - Event emission (BondRefunded)

### **Scenario 5b: RAT Attention Test Non-participant resolveClaim**
- **Gas Cost**: 1,565 gas
- **Included Work**:
  - Condition check only (challengerAddress != claimant)
  - Silent ignore (gas savings)
  - No work performed


## Common Analysis Elements

### 1. Basic Gas Cost
- Basic execution cost for each function
- Function call overhead

### 2. Storage Cost
- **SSTORE**: 20,000 gas for storing new value (cold storage)
- **SLOAD**: 2,100 gas for storage read (cold storage)
- **SSTORE**: 5,000 gas for modifying existing value (warm storage)
- **SLOAD**: 100 gas for reading existing value (warm storage)

### 3. Computation Cost
- Hash calculation (keccak256): 30 gas + 6 gas per word
- Condition check and comparison operations
- Random number generation (using blockhash)

### 4. Event Cost
- Log emission cost
- 375 gas per topic
- 8 gas per data byte

### 5. External Call Cost
- Cost for calling other contract functions
- CALL opcode base cost: 2,600 gas

## Measurement Methods

### Using Foundry Tests
```solidity
// Gas measurement example
uint256 gasBefore = gasleft();
functionCall();
uint256 gasUsed = gasBefore - gasleft();
```

### Scenario-based Test Cases
1. **Game Creation (No RAT)**: Successful execution of `DisputeGameFactory.create()`
2. **RAT Trigger (Valid Challengers Exist)**: Successful execution of `triggerAttentionTest()`
3. **RAT Trigger (No Valid Challengers)**: `triggerAttentionTest()` ignored
4. **Validator Evidence Submission**: Successful execution of `submitCorrectEvidence()`
5. **Claim Resolution**: Success/failure cases of `resolveClaim()`

## Expected Results Analysis

### Gas Cost Increase Factors
1. **Basic Game Creation Cost**: 163,991 gas (regardless of RAT presence)
2. **RAT Function Call**: `triggerAttentionTest()` function call overhead
3. **RAT Logic Execution**: Challenger selection and slashing logic (only when valid challengers exist)
4. **Additional Storage**: AttentionInfo struct storage (only when valid challengers exist)
5. **Event Emission**: AttentionTriggered event (only when valid challengers exist)
6. **Conditional Execution**: Minimum overhead when no valid challengers (14,677 gas)

### Optimization Points
1. **Conditional Execution**: Minimum overhead when no valid challengers (14,677 gas)
2. **Storage Optimization**: Struct packing and efficient data structures
3. **Gas-efficient Operations**: Removal of unnecessary calculations
4. **Game Creation Optimization**: Integration optimization with existing game creation logic
5. **RAT Function Call Optimization**: RAT call optimization in DisputeGameFactory

## Conclusion

### Key Comparison Metrics
1. **Basic Game Creation Cost**: 163,991 gas (regardless of RAT presence)
2. **RAT Trigger Success vs Ignore**: 132,378 gas vs 14,677 gas (about 9x difference)
3. **Evidence Submission Efficiency**: Very efficient at 7,520 gas
4. **Claim Resolution Efficiency**: 4,857 gas (success) vs 1,565 gas (ignore)
5. **resolveClaim Participant vs Non-participant**: 4,857 gas vs 1,565 gas (about 3x difference) - Non-participants save gas with condition check only

### RAT System Efficiency
- **Conditional Execution**: Minimum gas overhead when no valid challengers
- **Gas Optimization**: All functions implemented efficiently
- **Safety**: All error cases properly handled
- **Game Creation Overhead**: Game creation cost increase due to RAT introduction is minimized
- **Actual Operational Efficiency**: Still efficient gas usage even with intrinsic gas included

### 📊 Test vs Actual Network Gas Cost Comparison
- **Test Environment**: Internal function call simulation using Foundry's `vm.prank()`
- **Actual Network**: Real transaction execution with intrinsic gas (21,000) added
- **Comparison Result**: Confirms that all functions operate efficiently even in actual network

Through this, we can understand the efficiency and optimization points of the RAT system and predict gas costs in actual operational environments.
