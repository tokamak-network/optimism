# Prestate Synchronization Guide

## Problem Statement

When using `game_type: 0` (Cannon fault proof system), proposers and challengers may have different prestates, leading to validation errors:
- Challenger logs show "prestate validation failed"
- Games fail to register properly due to prestate hash mismatches
- **After local code changes**: Contract modifications require new prestate generation and synchronization

## Solution Methods

### Method 1: Automatic Fix (Recommended)

Use the AUTOFIX flag to automatically handle prestate synchronization:

```bash
# Automatically build prestates, sync, and deploy devnet
AUTOFIX=true just simple-devnet
```

**Benefits:**
- No manual prestate build/copy process needed
- Template processing automated
- Configuration automatically updated
- **Handles local code changes**: Automatically incorporates contract modifications
- Complete process in a single command

**Process:**
1. Required prestates automatically built with current local code state
2. Automatic deployment to fileserver with hash-based naming
3. Template processing and configuration generation
4. Automatic devnet deployment with synchronized prestates

**When to use:**
- After making local contract changes (e.g., adding TestContract.sol)
- When prestate validation errors occur
- For clean development environment setup

### Method 2: Manual Synchronization

If you need manual control over the prestate synchronization process:

#### 1. Build Fresh Prestates
```bash
# Create build directory and build prestates
mkdir -p ./prestate-build
just _prestate-build ./prestate-build

# Check generated hashes
cat ./prestate-build/prestate-proof-mt64.json | jq '.pre'
# -> "0x03a1a13511403f206bb2414e3bf974f8b4608ad8f7b37ee6642f6598dbe06195"
```

#### 2. Deploy to Fileserver
```bash
# Create directory structure
mkdir -p fileserver/static_files/proofs/op-program/cannon/

# Copy prestate files
cp ./prestate-build/*.json ./prestate-build/*.bin.gz fileserver/static_files/proofs/op-program/cannon/

# Hash-based files are automatically created during the build process
# No manual renaming needed - files are already generated with correct hash names
```

#### 3. Update Configuration
```bash
# Update simple.yaml configuration file
# Replace the faultGameAbsolutePrestate with the new hash
sed -i 's/faultGameAbsolutePrestate: .*/faultGameAbsolutePrestate: "0x03a1a13511403f206bb2414e3bf974f8b4608ad8f7b37ee6642f6598dbe06195"/' simple.yaml

# Verify cannon_prestates_url points to fileserver
grep "cannon_prestates_url" simple.yaml
# Should show: cannon_prestates_url: "http://fileserver:8080/proofs/op-program/cannon/"
```

**Or manually edit simple.yaml:**
```yaml
overrides:
  faultGameAbsolutePrestate: "0x03a1a13511403f206bb2414e3bf974f8b4608ad8f7b37ee6642f6598dbe06195"

challengers:
  challenger:
    cannon_prestates_url: {{ localPrestate.URL }}
    cannon_trace_types: ["cannon"]
```

## Key Points

1. **Prestate Consistency**: Proposer and challenger must use exactly the same prestate
2. **Hash-based Naming**: Prestate files are automatically generated with hash-based names
3. **Build Process**: Use `just _prestate-build` for reproducible prestate generation
4. **URL Synchronization**: Challenger automatically downloads correct prestate based on contract hash

## Verification

- Check challenger logs for successful prestate validation
- Ensure game registration proceeds without errors
- Verify no "prestate validation failed" messages in logs

## Local Code Changes and Prestate Synchronization

### Understanding the Relationship

**Key Insight**: Not all local code changes affect prestate hashes:

- **Contract changes** (like adding TestContract.sol): Usually **DO NOT** affect prestate
- **op-program changes**: **DO** affect prestate and require regeneration
- **Consensus logic changes**: **DO** affect prestate

### After Making Local Changes

#### Step 1: Determine if Prestate Changed
```bash
# Build new prestate with your local changes
cd /Users/zena/tokamak-projects/optimism
just _prestate-build

# Check the new prestate hash
cat op-program/bin/prestate-proof-mt64.json | grep '"pre"'
```

#### Step 2: Compare with Previous Hash
```bash
# If hash is the same as before (e.g., 0x03a1a13511403f206bb2414e3bf974f8b4608ad8f7b37ee6642f6598dbe06195)
# -> Contract changes don't affect prestate, safe to proceed

# If hash is different
# -> Core logic changed, need full redeployment
```

#### Step 3: Redeploy with Local Changes
```bash
# Always use AUTOFIX for local changes to ensure consistency
AUTOFIX=true just simple-devnet
```

### Fileserver Location and Modification

The fileserver runs as a Docker container but serves files from your local machine:

**File Location**: `/var/folders/[random]/T/simple-devnet[id]/proofs/op-program/cannon/`

**Structure**:
```
/var/folders/.../simple-devnet.../
└── proofs/
    └── op-program/
        └── cannon/
            ├── 0x03a1a13511403f206bb2414e3bf974f8b4608ad8f7b37ee6642f6598dbe06195.bin.gz
            ├── 0x03a1a13511403f206bb2414e3bf974f8b4608ad8f7b37ee6642f6598dbe06195.json
            ├── meta-mt64.json
            └── op-program-client64.elf
```

**You CAN modify these files manually**, but the recommended approach is to use `AUTOFIX=true just simple-devnet` which:
1. Builds fresh prestates with your local changes
2. Creates proper directory structure
3. Uses correct hash-based file naming
4. Updates all configuration automatically

## Troubleshooting

**Issue**: Challenger shows prestate validation errors after local changes
**Root Cause**: Game contract expects different prestate than what fileserver provides
**Solution**:
1. **Always use AUTOFIX** after local changes: `AUTOFIX=true just simple-devnet`
2. Verify deployment completed successfully without Docker daemon errors
3. Check challenger logs show no prestate validation errors

**Issue**: "Provider: 0x50c8... | Contract: 0xdead..." error
**Root Cause**: Mismatch between challenger's loaded prestate and game contract's expected prestate
**Solution**: Complete redeployment with `AUTOFIX=true just simple-devnet`

**Issue**: Template processing errors in configuration
**Solution**: Use the AUTOFIX method which handles template processing automatically

**Issue**: Game type 1 works but game type 0 (Cannon) fails
**Root Cause**: Different VM types have different prestate requirements
**Solution**: Ensure Cannon-specific prestates are built and deployed correctly