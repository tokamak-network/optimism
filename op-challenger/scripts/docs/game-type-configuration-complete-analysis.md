# OP Stack Game Type Configuration: Complete Analysis and Solution

## Summary

This document provides a comprehensive analysis of the OP Stack game type configuration system, the issues discovered during investigation, and the proposed simplified solution.

## Game Type System Overview

### Game Type Definitions
Based on `/Users/zena/tokamak-projects/optimism/op-challenger/game/fault/types/types.go:29-41`:

```go
const (
    CannonGameType            GameType = 0  // Fault Game with Cannon VM
    PermissionedGameType      GameType = 1  // Restricted participant dispute game
)
```

- **Type 0 (Cannon)**: Standard fault proof game using Cannon VM
- **Type 1 (Permissioned)**: Dispute game with restricted participants

### Current Configuration Pipeline

```
rollup-config.json → simple.yaml → Kurtosis → intent.yaml → op-deployer → deployed contracts
```

## Issues Discovered

### 1. Configuration Mismatch
- **simple.yaml** sets `game_type: 1` for OP-Proposer
- **Kurtosis** generates `intent.yaml` with hardcoded `respectedGameType: 0`
- **op-deployer** uses hardcoded `standard.DisputeGameType = 1`

### 2. Hardcoded Values Override Configuration
Location: `/Users/zena/tokamak-projects/optimism/op-deployer/pkg/deployer/standard/standard.go:29`
```go
DisputeGameType uint32 = 1 // PERMISSIONED game type
```

Used in: `/Users/zena/tokamak-projects/optimism/op-deployer/pkg/deployer/pipeline/opchain.go:78`
```go
DisputeGameType: standard.DisputeGameType,
```

### 3. System Works Accidentally
Despite configuration mismatches, the system functions because:
- op-deployer ignores intent.yaml's `respectedGameType: 0`
- Uses hardcoded `DisputeGameType = 1` instead
- Results in correct deployment but misleading configuration files

## Current Configuration Files Analysis

### simple.yaml Configuration
```yaml
proposer_params:
  game_type: 1  # Sets proposer to use Permissioned game type
```

### Generated intent.yaml (Incorrect)
```yaml
respectedGameType: 0  # BUG: Should be 1, hardcoded by Kurtosis
```

### rollup-config.json (Current)
```json
{
  "genesis": { ... },
  "block_time": 2,
  "l1_chain_id": 3151908,
  "l2_chain_id": 2151908,
  // No game type configuration currently
}
```

## Proposed Solution: Simplified Configuration

### 1. Add Single Game Type Field to rollup-config.json

```json
{
  "genesis": { ... },
  "block_time": 2,
  "l1_chain_id": 3151908,
  "l2_chain_id": 2151908,
  "game_type": 1,
  "_comment": "Game Type: 0=Cannon, 1=Permissioned"
}
```

### 2. Configuration Flow Changes

```
rollup-config.json (game_type) → All components use this single source of truth
├── simple.yaml (proposer_params.game_type)
├── intent.yaml (respectedGameType) 
└── op-deployer (removes hardcoded value)
```

### 3. Component Updates Required

1. **Kurtosis Package**: Read `game_type` from rollup-config.json when generating intent.yaml
2. **op-deployer**: Remove hardcoded `standard.DisputeGameType`, use value from intent.yaml
3. **simple.yaml**: Reference rollup-config.json value instead of hardcoded `game_type: 1`

## Implementation Benefits

### Unified Configuration
- Single source of truth for game type across all components
- Eliminates configuration mismatches
- Clear documentation of network's dispute game type

### Simplified Management
- One value instead of multiple scattered configurations
- Easier to understand and modify
- Reduces chance of configuration errors

### Maintainable System
- No more hardcoded overrides
- Configuration files accurately reflect deployed state
- Proper separation between configuration and implementation

## Technical Implementation Steps

### Step 1: Update rollup-config.json Schema
Add `game_type` field with validation:
```json
{
  "game_type": 1,
  "_comment": "Dispute game type: 0=Cannon, 1=Permissioned"
}
```

### Step 2: Update Kurtosis Package
Modify template generation to read `game_type` from rollup-config.json:
```yaml
# In generated intent.yaml
respectedGameType: {{ .GameType }}  # From rollup-config.json
```

### Step 3: Update op-deployer
Replace hardcoded constant with intent.yaml value:
```go
// Remove: DisputeGameType uint32 = 1
// Use: intent.RespectedGameType
```

### Step 4: Update simple.yaml Template
Reference rollup-config value:
```yaml
proposer_params:
  game_type: {{ .GameType }}  # From rollup-config.json
```

## Current State vs. Desired State

| Component | Current | Desired |
|-----------|---------|---------|
| rollup-config.json | No game type | `game_type: 1` |
| simple.yaml | Hardcoded `game_type: 1` | Template `{{ .GameType }}` |
| intent.yaml | Hardcoded `respectedGameType: 0` | Dynamic `respectedGameType: 1` |
| op-deployer | Hardcoded `DisputeGameType = 1` | Read from intent.yaml |
| Deployed Contract | `respectedGameType: 1` | `respectedGameType: 1` (same) |

## Validation and Testing

### Pre-deployment Validation
1. Verify rollup-config.json contains valid `game_type` (0 or 1)
2. Check all generated configurations match rollup-config value
3. Confirm op-deployer uses correct game type without hardcoding

### Post-deployment Verification
1. Query deployed contract's `respectedGameType`
2. Verify matches rollup-config.json `game_type`
3. Test challenger can handle the configured game type

## Migration Path

### For Existing Networks
1. Document current hardcoded game type in rollup-config.json
2. Update configuration pipeline to use documented value
3. Verify no behavioral changes after migration

### For New Networks
1. Specify desired game type in rollup-config.json
2. All components automatically use specified value
3. No manual configuration required

## Conclusion

The current game type configuration system has multiple points of failure due to hardcoded values and configuration mismatches. The proposed solution centralizes game type configuration in rollup-config.json, providing a single source of truth that all components can reference. This eliminates configuration drift, improves maintainability, and ensures deployed contracts match documented configuration.

The key insight is that each network needs only one game type, so a single `game_type` field is sufficient rather than complex arrays or mappings. This simplified approach reduces complexity while solving the core configuration management issues.