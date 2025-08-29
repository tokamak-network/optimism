# Proper Configuration Pipeline Fix

## 🎯 Problem Statement

**Current Issue**: Configuration pipeline has two major problems:
1. **Kurtosis ignores simple.yaml**: Intent.yaml generation doesn't respect user's `game_type` setting
2. **op-deployer uses hardcoded values**: Deployment ignores user configuration and uses `standard.DisputeGameType = 1`

**Required Fix**: Make the entire pipeline respect user's initial `simple.yaml` configuration.

## 📋 Current Broken Pipeline

```
simple.yaml               intent.yaml              op-deployer              Deployment
game_type: 1      ❌     respectedGameType: 0     ❌     Uses hardcoded 1     ✅ respectedGameType: 1
     ↑                          ↑                         ↑                           ↑
User Config           Kurtosis Ignores           Ignores File             Accidental Success
```

## 🔧 Required Fixes

### 1. Fix Kurtosis Intent Generation

**Problem Location**: External `optimism-package` template
**Required Change**: Make Kurtosis read `simple.yaml` and generate correct `intent.yaml`

```yaml
# simple.yaml (User Input)
proposer_params:
  game_type: 1              # User wants Permissioned games

# intent.yaml (Should be Generated)  
dangerousAdditionalDisputeGames:
  - respectedGameType: 1    # ← Should match simple.yaml game_type
    makeRespected: true     # ← Should enable this game type  
    vmType: PERMISSIONED    # ← Should match game type
```

### 2. Fix op-deployer Hardcoded Behavior

**Problem Location**: `op-deployer/pkg/deployer/pipeline/opchain.go:78`
**Current Code**:
```go
DisputeGameType: standard.DisputeGameType,  // ❌ Always uses hardcoded 1
```

**Required Change**: Read from intent.yaml instead of hardcoded value
```go
DisputeGameType: thisIntent.GetRespectedGameType(),  // ✅ Use user configuration
```

## 🏗️ Detailed Implementation Plan

### Phase 1: Fix Intent Generation (Kurtosis)

**Files to Modify**: External optimism-package template logic

**Implementation**:
```starlark
# Pseudo-code for Kurtosis template fix
def generate_intent(simple_config):
    proposer_game_type = simple_config.optimism_package.chains.op_kurtosis.proposer_params.game_type
    
    # Map game type to VM type
    vm_type = "CANNON" if proposer_game_type == 0 else "PERMISSIONED"
    
    intent_config = {
        "dangerousAdditionalDisputeGames": [{
            "respectedGameType": proposer_game_type,    # Match user setting
            "makeRespected": True,                      # Enable this type
            "vmType": vm_type,                          # Correct VM type
            # ... other settings
        }]
    }
    return intent_config
```

### Phase 2: Fix op-deployer Hardcoding

**File**: `op-deployer/pkg/deployer/pipeline/opchain.go`

**Current Implementation** (Line 75-84):
```go
func makeDCI(intent *state.Intent, thisIntent *state.ChainIntent, chainID common.Hash, st *state.State) (opcm.DeployOPChainInput, error) {
    proofParams, err := jsonutil.MergeJSON(
        state.ChainProofParams{
            DisputeGameType:         standard.DisputeGameType, ← ❌ HARDCODED
            DisputeAbsolutePrestate: standard.DisputeAbsolutePrestate,
            // ... other params
        },
```

**Required Fix**:
```go
func makeDCI(intent *state.Intent, thisIntent *state.ChainIntent, chainID common.Hash, st *state.State) (opcm.DeployOPChainInput, error) {
    // Extract game type from user configuration
    gameType := extractGameTypeFromIntent(thisIntent)
    if gameType == 0 {
        // Fallback to standard only if not specified
        gameType = standard.DisputeGameType
    }
    
    proofParams, err := jsonutil.MergeJSON(
        state.ChainProofParams{
            DisputeGameType:         gameType, ← ✅ USE USER CONFIG
            DisputeAbsolutePrestate: getPresrateForGameType(gameType),
            // ... other params adapt to game type
        },
```

**Helper Functions to Add**:
```go
func extractGameTypeFromIntent(intent *state.ChainIntent) uint32 {
    if len(intent.AdditionalDisputeGames) > 0 {
        // Find the game marked as respected
        for _, game := range intent.AdditionalDisputeGames {
            if game.MakeRespected {
                return game.DisputeGameType
            }
        }
    }
    return 0 // Not specified, use fallback
}

func getPresrateForGameType(gameType uint32) common.Hash {
    switch gameType {
    case 0: // Cannon
        return standard.DisputeAbsolutePrestate
    case 1: // Permissioned  
        return standard.DisputeAbsolutePrestate // Same for now
    default:
        return standard.DisputeAbsolutePrestate
    }
}
```

### Phase 3: Update ChainIntent Structure

**File**: `op-deployer/pkg/deployer/state/chain_intent.go`

**Add Helper Method**:
```go
func (c *ChainIntent) GetRespectedGameType() uint32 {
    for _, game := range c.AdditionalDisputeGames {
        if game.MakeRespected {
            return game.DisputeGameType  
        }
    }
    // Fallback to standard if not configured
    return standard.DisputeGameType
}
```

## 🧪 Testing the Fix

### Test Case 1: Cannon Configuration
```yaml  
# simple.yaml
proposer_params:
  game_type: 0

# Expected Results:
# - intent.yaml: respectedGameType: 0
# - Deployment: respectedGameType: 0  
# - OP-Proposer: --game-type=0
```

### Test Case 2: Permissioned Configuration
```yaml
# simple.yaml 
proposer_params:
  game_type: 1

# Expected Results:
# - intent.yaml: respectedGameType: 1
# - Deployment: respectedGameType: 1
# - OP-Proposer: --game-type=1
```

### Verification Commands
```bash
# 1. Check simple.yaml setting
grep "game_type:" /Users/zena/tokamak-projects/optimism/kurtosis-devnet/simple.yaml

# 2. Check generated intent.yaml matches
grep "respectedGameType:" /tmp/current-devnet-config/intent.yaml

# 3. Check deployed contract matches
cast call 0x92b92fbfdb9c688d204062900de9d1fb624540a4 \
  "respectedGameType()(uint32)" --rpc-url http://localhost:65502

# 4. Check OP-Proposer matches  
docker inspect $(docker ps | grep proposer | awk '{print $1}') \
  --format='{{.Config.Cmd}}' | grep game-type

# All should show the same value!
```

## 📊 Before vs After Comparison

### Current (Broken) Pipeline
| Stage | Configuration Source | Value | Status |
|-------|---------------------|-------|--------|
| User Input | `simple.yaml` | `game_type: 1` | ✅ User intent |
| Intent Generation | Hardcoded | `respectedGameType: 0` | ❌ Ignores user |
| Deployment | Hardcoded | `DisputeGameType: 1` | ❌ Ignores files |
| Final Result | Accidental | `respectedGameType: 1` | ⚠️ Lucky match |

### Fixed Pipeline
| Stage | Configuration Source | Value | Status |
|-------|---------------------|-------|--------|
| User Input | `simple.yaml` | `game_type: 1` | ✅ User intent |
| Intent Generation | Read from simple.yaml | `respectedGameType: 1` | ✅ Respects user |
| Deployment | Read from intent.yaml | `DisputeGameType: 1` | ✅ Follows config |
| Final Result | Consistent | `respectedGameType: 1` | ✅ Intentional match |

## 🎯 Implementation Priority

### High Priority (Critical)
1. **Fix op-deployer hardcoding** - Can be done locally
2. **Add configuration validation** - Ensure consistency
3. **Update documentation** - Reflect new behavior

### Medium Priority (External Dependency)
1. **Fix Kurtosis intent generation** - Requires external optimism-package update
2. **Add integration tests** - Prevent regression

### Low Priority (Enhancement)  
1. **Support additional game types** - Future extensibility
2. **Better error messages** - User experience

## 🔧 Immediate Action Items

### For Local Development
```bash
# 1. Create local fix branch
git checkout -b fix/respect-user-game-type-configuration

# 2. Modify op-deployer to read from intent.yaml instead of hardcoded
# Edit: op-deployer/pkg/deployer/pipeline/opchain.go

# 3. Add helper functions for game type extraction
# Edit: op-deployer/pkg/deployer/state/chain_intent.go

# 4. Test with both game types (0 and 1)
./build-devnet.sh
# Verify all components use consistent values

# 5. Update documentation to reflect proper behavior
```

### For Kurtosis Fix (External)
```bash
# File issue or PR to optimism-package repository
# Request: Make intent.yaml generation respect simple.yaml game_type setting
```

## ✅ Success Criteria

### Configuration Consistency
- [ ] `simple.yaml` game_type setting propagates through entire pipeline
- [ ] `intent.yaml` respectedGameType matches simple.yaml game_type  
- [ ] op-deployer uses intent.yaml values instead of hardcoded constants
- [ ] Deployed contracts reflect user's original configuration
- [ ] OP-Proposer and contracts use identical game types

### System Behavior
- [ ] Challenger processes games without "unsupported type" errors
- [ ] All game types (0, 1) work correctly with proper configuration
- [ ] Configuration changes in simple.yaml propagate to all components

---
**Solution Type**: Architectural fix for proper configuration pipeline  
**Scope**: Both local op-deployer changes and external Kurtosis package updates required  
**Result**: True configuration-driven deployment instead of accidental hardcoded success