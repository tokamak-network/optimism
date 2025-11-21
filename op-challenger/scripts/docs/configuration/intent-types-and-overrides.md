# OP-Deployer Intent Types and Global Deploy Overrides

## Overview
This document explains the different Intent types available in op-deployer and how to customize deployments using Global Deploy Overrides.

## Intent Types

### 1. `standard` Type
**Purpose**: Standard configuration for mainnet/testnet deployments

**Characteristics**:
- ✅ **Pre-deployed OPCM**: Uses predefined OPCM addresses per L1 chain
- ✅ **Standard contracts**: Uses official release contract artifacts
- ✅ **Auto-configured roles**: Automatically sets Challenger, ProxyAdmin addresses
- ✅ **Standard parameters**: Auto-configures EIP-1559, fees, etc.
- ❌ **Limited customization**: Only standard values, no modifications allowed

**Use case**: Production deployments on known networks

```bash
op-deployer init --intent-type standard --l1-chain-id 1 --l2-chain-ids 10 --outdir ./deployment
```

### 2. `custom` Type
**Purpose**: Fully customizable deployment

**Characteristics**:
- ❌ **All values empty**: User must manually configure everything
- ✅ **Complete freedom**: All addresses and parameters customizable
- ✅ **Development/testing**: Suitable for local dev or special requirements
- ⚠️ **Complex**: Requires manual configuration of all settings

**Use case**: Local development, testing, non-standard requirements

```bash
op-deployer init --intent-type custom --l1-chain-id 31337 --l2-chain-ids 901 --outdir ./deployment
```

### 3. `standard-overrides` Type
**Purpose**: Standard configuration with selective customization

**Characteristics**:
- ✅ **Standard baseline**: Same defaults as `standard` type
- ✅ **Selective overrides**: Can customize specific parts only
- ✅ **Balanced approach**: Safety + flexibility
- 🎯 **Recommended**: Ideal for most use cases

**Use case**: When you need standard setup with specific customizations

```bash
op-deployer init --intent-type standard-overrides --l1-chain-id 1 --l2-chain-ids 10 --outdir ./deployment
```

## Global Deploy Overrides

### What are Global Deploy Overrides?
Global Deploy Overrides allow you to customize deployment parameters across all chains in your intent without modifying the source code.

### How to Use Global Deploy Overrides

1. **Initialize with `standard-overrides` type**:
```bash
op-deployer init --intent-type standard-overrides --l1-chain-id 31337 --l2-chain-ids 901 --outdir ./deployment
```

2. **Edit the generated `intent.toml` file**:
```toml
configType = "standard-overrides"
l1ChainID = 31337
fundDevAccounts = true

# Add global deploy overrides section
[globalDeployOverrides]
respectedGameType = 0  # Override to CANNON type
dangerouslyAllowCustomDisputeParameters = true
faultGameAbsolutePrestate = "0x03a1a13511403f206bb2414e3bf974f8b4608ad8f7b37ee6642f6598dbe06195"

[[chains]]
id = "0x000000000000000000000000000000000000000000000000000000000000385"
# ... chain configuration
```

3. **Apply the deployment**:
```bash
op-deployer apply --l1-rpc-url http://localhost:8545 --private-key 0x... --workdir ./deployment
```

### Common Override Parameters

| Parameter | Description | Default | Example Override |
|-----------|-------------|---------|------------------|
| `respectedGameType` | Dispute game type for AnchorStateRegistry | `1` (PERMISSIONED) | `0` (CANNON) |
| `faultGameAbsolutePrestate` | Prestate hash for fault proofs | Standard hash | Custom hash |
| `faultGameMaxDepth` | Maximum depth for dispute games | `73` | Custom depth |
| `faultGameSplitDepth` | Split depth for dispute games | `30` | Custom depth |
| `dangerouslyAllowCustomDisputeParameters` | Allow custom dispute parameters | `false` | `true` |

### Dispute Game Types

| Type | Value | Description |
|------|-------|-------------|
| `CANNON` | `0` | Standard fault proof system |
| `PERMISSIONED_CANNON` | `1` | Permissioned fault proof system |
| `ASTERISC` | `2` | Asterisc VM fault proof system |
| `ASTERISC_KONA` | `3` | Asterisc Kona variant |
| `FAST` | `254` | Fast dispute resolution (testing) |
| `ALPHABET` | `255` | Alphabet game (testing) |

## Troubleshooting Common Issues

### Issue: respectedGameType is 1 instead of 0
**Cause**: Default standard configuration uses PERMISSIONED_CANNON (1)
**Solution**: Use `standard-overrides` type and add `respectedGameType = 0` to globalDeployOverrides

### Issue: Custom prestate not recognized
**Cause**: Prestate hash doesn't match the generated prestate
**Solution**: Ensure `faultGameAbsolutePrestate` matches your actual prestate hash

### Issue: Dispute game parameters rejected
**Cause**: Custom parameters not allowed by default
**Solution**: Add `dangerouslyAllowCustomDisputeParameters = true` to globalDeployOverrides

## Examples

### Example 1: Cannon-based Devnet
```toml
configType = "standard-overrides"
l1ChainID = 31337
fundDevAccounts = true

[globalDeployOverrides]
respectedGameType = 0  # Use CANNON
faultGameAbsolutePrestate = "0x03a1a13511403f206bb2414e3bf974f8b4608ad8f7b37ee6642f6598dbe06195"
dangerouslyAllowCustomDisputeParameters = true

[[chains]]
id = "0x000000000000000000000000000000000000000000000000000000000000385"
# ... rest of configuration
```

### Example 2: Testing with Fast Dispute Games
```toml
configType = "standard-overrides"
l1ChainID = 31337
fundDevAccounts = true

[globalDeployOverrides]
respectedGameType = 254  # Use FAST for testing
dangerouslyAllowCustomDisputeParameters = true
faultGameMaxDepth = 10   # Shorter games for faster testing

[[chains]]
id = "0x000000000000000000000000000000000000000000000000000000000000385"
# ... rest of configuration
```

## References

- [OP-Deployer Documentation](../README.md)
- [Dispute Game Types Source Code](../../packages/contracts-bedrock/src/dispute/lib/Types.sol)
- [Standard Configuration Values](../../op-deployer/pkg/deployer/standard/standard.go)