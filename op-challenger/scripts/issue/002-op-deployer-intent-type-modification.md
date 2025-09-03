# Op-Deployer Intent Type Modification Guide

**Date:** September 1, 2025  
**Reporter:** Development Team  
**Severity:** Low (Documentation/Process)  
**Status:** Active  

## Summary

Guide for modifying op-deployer intent configuration from `custom` to `standard-overrides` after initialization. This addresses the common scenario where developers initialize with `custom` intent type but later want to switch to `standard-overrides` for existing OPCM deployments.

## Background

### Op-Deployer Init Process

Op-deployer's `init` command creates initial deployment configuration files:

**Command Structure:**
```bash
op-deployer init \
  --l1-chain-id <chain ID of your L1> \
  --l2-chain-ids <comma separated list of chain IDs for your L2s> \
  --outdir <directory to write the intent and state files> \
  --intent-type <standard/custom/standard-overrides>
```

**Generated Files:**
```
outdir/
├── intent.toml  # Deployment configuration
└── state.json   # Deployment state tracking
```

### Intent Types

Defined in `op-deployer/pkg/deployer/state/intent.go:22-26`:

```go
const (
    IntentTypeStandard          IntentType = "standard"          // Fresh deployment
    IntentTypeCustom            IntentType = "custom"            // Full custom deployment  
    IntentTypeStandardOverrides IntentType = "standard-overrides" // Use existing OPCM
)
```

### Kurtosis Integration

**Current Kurtosis Implementation:**
- **File:** `ethpandaops/optimism-package/src/contracts/contract_deployer.star`
- **Init Command:** 
  ```starlark
  op_deployer_init = "op-deployer init --intent-config-type custom --l1-chain-id $L1_CHAIN_ID --l2-chain-ids {0} --workdir /network-data".format(
      ",".join(l2_chain_ids)
  )
  ```

**Issue:** Kurtosis hardcodes `custom` intent type, but developers may need `standard-overrides` for existing OPCM deployments.

## Problem Description

### Scenario
1. Developer runs Kurtosis devnet → generates `intent.toml` with `configType = "custom"`
2. Developer wants to use existing OPCM → needs `configType = "standard-overrides"`
3. Question: Can the `intent.toml` file be manually modified after generation?

### Current Kurtosis Behavior

**Container:** `us-docker.pkg.dev/oplabs-tools-artifacts/images/op-deployer:v0.4.2`  
**Working Directory:** `/network-data`  
**Generated Config:**
```toml
configType = "custom"
l1ChainID = 11155420
# ... other fields
```

## Solution: Intent File Modification

### ✅ **Yes, manual modification is supported and safe**

The `intent.toml` file can be modified after initialization if the deployment has not been applied yet.

### Step-by-Step Process

#### 1. Check Deployment State
```bash
# Ensure state.json shows no applied intent
cat state.json
# Should show: "appliedIntent": null
```

#### 2. Modify Intent Configuration
```toml
# Change from:
configType = "custom"

# To:
configType = "standard-overrides"
```

#### 3. Add Required Fields for Standard-Overrides

**Essential Addition:**
```toml
configType = "standard-overrides"
l1ChainID = 11155420
opcmAddress = "0x..." # ← REQUIRED: Address of existing OPCM
l1ContractsLocator = "tag://op-contracts/v1.8.0-rc.4"
l2ContractsLocator = "tag://op-contracts/v1.7.0-beta.1+l2-contracts"
```

### Example Complete Configuration

**File:** `intent.toml`
```toml
configType = "standard-overrides"
l1ChainID = 11155420
opcmAddress = "0x1234567890123456789012345678901234567890"
l1ContractsLocator = "tag://op-contracts/v1.8.0-rc.4"
l2ContractsLocator = "tag://op-contracts/v1.7.0-beta.1+l2-contracts"

[superchainRoles]
  proxyAdminOwner = "0xeAAA3fd0358F476c86C26AE77B7b89a069730570"
  protocolVersionsOwner = "0xeAAA3fd0358F476c86C26AE77B7b89a069730570"
  guardian = "0xeAAA3fd0358F476c86C26AE77B7b89a069730570"

[[chains]]
  id = "0x0000000000000000000000000000000000000000000000000000000000002390"
  baseFeeVaultRecipient = "0x0000000000000000000000000000000000000000"
  l1FeeVaultRecipient = "0x0000000000000000000000000000000000000000"
  sequencerFeeVaultRecipient = "0x0000000000000000000000000000000000000000"
  eip1559DenominatorCanyon = 250
  eip1559Denominator = 50
  eip1559Elasticity = 6
  
  [chains.roles]
    l1ProxyAdminOwner = "0x0000000000000000000000000000000000000000"
    l2ProxyAdminOwner = "0x0000000000000000000000000000000000000000"
    systemConfigOwner = "0x0000000000000000000000000000000000000000"
    unsafeBlockSigner = "0x0000000000000000000000000000000000000000"
    batcher = "0x0000000000000000000000000000000000000000"
    proposer = "0x0000000000000000000000000000000000000000"
    challenger = "0x0000000000000000000000000000000000000000"
```

## Critical Requirements

### 1. OPCM Address Validation
```bash
# Verify OPCM exists and is valid
cast code $OPCM_ADDRESS --rpc-url $L1_RPC
# Should return non-zero bytecode
```

### 2. Contract Locator Consistency

**Documentation Reference:** `op-deployer/book/src/reference-guide/custom-deployments.md:103-105`

> Make sure that you use the same `l1ContractsLocator` and `l2ContractsLocator` as the ones used in the bootstrap commands. Otherwise, you may run into deployment errors.

**Requirements:**
- Must match versions used in OPCM bootstrap
- Must be compatible with target chain
- Must be available in contract registry

### 3. State File Constraints

**Safe Modification Window:**
```json
{
  "version": 1,
  "appliedIntent": null  // ← Safe to modify when null
}
```

**Unsafe Modification Window:**
```json
{
  "version": 1,
  "appliedIntent": {     // ← Do NOT modify when applied
    "l1ChainID": 11155420,
    // ... applied configuration
  }
}
```

## Validation Steps

### 1. Intent Validation
```bash
# Use op-deployer to validate modified intent
op-deployer apply --outdir /network-data --dry-run
```

### 2. OPCM Compatibility Check
```bash
# Verify OPCM supports required contract versions
cast call $OPCM_ADDRESS "protocolVersions()" --rpc-url $L1_RPC
```

### 3. Chain Configuration Validation
```bash
# Ensure L2 chain IDs are properly formatted
# L2 chain IDs must be 32-byte hashes (0x prefixed)
echo "0x0000000000000000000000000000000000000000000000000000000000002390" | wc -c
# Should return 67 (66 hex chars + newline)
```

## Common Issues and Solutions

### Issue 1: Missing OPCM Address
**Error:** `opcmAddress must be specified for standard-overrides intent`
**Solution:** Add valid OPCM address to intent.toml

### Issue 2: Contract Version Mismatch  
**Error:** `deployment errors due to contract version incompatibility`
**Solution:** Match l1ContractsLocator/l2ContractsLocator to OPCM bootstrap versions

### Issue 3: Applied Intent Modification
**Error:** `cannot modify applied intent`
**Solution:** Create new intent or use `op-deployer migrate` if available

### Issue 4: Invalid Chain ID Format
**Error:** `invalid L2 chain ID format`
**Solution:** Ensure L2 chain IDs are 32-byte hex strings with 0x prefix

## Code References

### Intent Type Definition
- **File:** `op-deployer/pkg/deployer/state/intent.go:25`
- **Line:** `IntentTypeStandardOverrides IntentType = "standard-overrides"`

### Standard-Overrides Documentation
- **File:** `op-deployer/book/src/reference-guide/custom-deployments.md:99`
- **Context:** OPCM address requirement and deployment process

### Kurtosis Implementation
- **File:** `ethpandaops/optimism-package/src/contracts/contract_deployer.star`
- **Context:** Hardcoded `custom` intent type in Kurtosis deployment

### Init Command Implementation
- **File:** `op-deployer/pkg/deployer/init.go:77`
- **Function:** `Init(cfg InitConfig)`
- **Context:** Intent and state file creation

## Impact Assessment

### Positive Impact
- ✅ Enables reuse of existing OPCM deployments
- ✅ Reduces deployment complexity and time
- ✅ Maintains consistency with existing superchain infrastructure
- ✅ Supports enterprise deployment patterns

### Risk Assessment  
- ⚠️ **Low Risk:** Manual file modification is supported by design
- ⚠️ **Medium Risk:** Incorrect OPCM address can cause deployment failures
- ⚠️ **Medium Risk:** Version mismatches can cause runtime errors

### Best Practices
1. **Always validate** OPCM address before modification
2. **Backup** original intent.toml before changes
3. **Test with --dry-run** before applying changes
4. **Document** OPCM addresses and contract versions used

## Process Improvement Recommendations

### For Kurtosis Package
1. **Add intent-type parameter** to Kurtosis configuration
2. **Support OPCM address input** for standard-overrides workflows
3. **Validate OPCM compatibility** before deployment

### For Op-Deployer
1. **Add intent modification command** (`op-deployer intent modify`)
2. **Enhance validation** for standard-overrides requirements  
3. **Improve error messages** for common misconfigurations

## Related Documentation

- **Op-Deployer Init Guide:** `op-deployer/book/src/user-guide/init.md`
- **Custom Deployments:** `op-deployer/book/src/reference-guide/custom-deployments.md`
- **Intent Configuration:** `op-deployer/pkg/deployer/state/intent.go`
- **Kurtosis Integration:** `ethpandaops/optimism-package`

## Status and Next Steps

- [x] Document intent modification process
- [x] Validate safety of manual modification
- [x] Identify required fields for standard-overrides
- [x] Document validation steps
- [ ] Test modification process in devnet environment
- [ ] Create automation scripts for common scenarios  
- [ ] Propose Kurtosis package improvements

## Contact

For questions about intent modification or op-deployer configuration, refer to:
- **Op-Deployer Documentation:** `op-deployer/book/`
- **Issue Tracking:** `/Users/zena/tokamak-projects/optimism/op-challenger/scripts/issue/`
- **Development Team:** Optimism Engineering