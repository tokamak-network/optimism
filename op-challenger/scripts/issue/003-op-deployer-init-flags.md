# Op-Deployer Init Flags Documentation

**Date:** September 1, 2025  
**Reporter:** Development Team  
**Type:** Documentation  
**Status:** Active  

## Summary

Documentation for op-deployer init command flags and their usage based on code analysis.

## Op-Deployer Init Command Structure

### CLI Command Definition
**File:** `op-deployer/cmd/op-deployer/main.go:37-43`

```go
{
    Name:   "init",
    Usage:  "initializes a chain intent and state file",
    Flags:  cliapp.ProtectFlags(deployer.InitFlags),
    Action: deployer.InitCLI(),
}
```

### Init Flags Array
**File:** `op-deployer/pkg/deployer/flags.go:158-163`

```go
var InitFlags = []cli.Flag{
    L1ChainIDFlag,
    L2ChainIDsFlag,
    WorkdirFlag,
    IntentTypeFlag,
}
```

## Flag Definitions

Based on the InitFlags array, the op-deployer init command accepts these 4 flags:

### 1. L1ChainIDFlag
- **Purpose:** Specifies the L1 chain ID
- **Required:** Yes (validated in init.go:26-28)
- **Type:** uint64
- **Usage:** `--l1-chain-id <chain_id>`

### 2. L2ChainIDsFlag  
- **Purpose:** Comma-separated list of L2 chain IDs
- **Required:** Yes (validated in init.go:34-36)
- **Type:** string (parsed to []common.Hash)
- **Usage:** `--l2-chain-ids <id1,id2,id3>`

### 3. WorkdirFlag
- **Purpose:** Output directory for intent.toml and state.json
- **Required:** Yes (validated in init.go:30-32)
- **Type:** string
- **Usage:** `--workdir <directory>`
- **Note:** Also referenced as `--outdir` in some documentation

### 4. IntentTypeFlag
- **Purpose:** Type of deployment intent
- **Required:** Yes
- **Type:** string
- **Valid Values:** 
  - `"standard"` - Fresh standard deployment
  - `"custom"` - Full custom deployment  
  - `"standard-overrides"` - Use existing OPCM
- **Usage:** `--intent-type <type>`

## Command Examples

### Basic Standard Deployment
```bash
op-deployer init \
  --l1-chain-id 11155420 \
  --l2-chain-ids 2151908 \
  --workdir ./deployment \
  --intent-type standard
```

### Multiple L2 Chains
```bash
op-deployer init \
  --l1-chain-id 1 \
  --l2-chain-ids 10,8453,7777777 \
  --workdir ./multi-chain \
  --intent-type custom
```

### Standard Overrides (Existing OPCM)
```bash
op-deployer init \
  --l1-chain-id 11155420 \
  --l2-chain-ids 2151908 \
  --workdir ./override-deployment \
  --intent-type standard-overrides
```

### Kurtosis Current Usage
**File:** `ethpandaops/optimism-package/src/contracts/contract_deployer.star`

```starlark
op_deployer_init = "op-deployer init --intent-config-type custom --l1-chain-id $L1_CHAIN_ID --l2-chain-ids {0} --workdir /network-data".format(
    ",".join(l2_chain_ids)
)
```

**Note:** Kurtosis uses `--intent-config-type` which appears to be an older flag name. Current code shows `--intent-type`.

## Configuration Processing

### InitConfig Struct
**File:** `op-deployer/pkg/deployer/init.go:18-23`

```go
type InitConfig struct {
    IntentType state.IntentType  // From IntentTypeFlag
    L1ChainID  uint64            // From L1ChainIDFlag
    Outdir     string            // From WorkdirFlag
    L2ChainIDs []common.Hash     // From L2ChainIDsFlag (parsed)
}
```

### CLI Processing
**File:** `op-deployer/pkg/deployer/init.go:41-67`

```go
func InitCLI() func(ctx *cli.Context) error {
    return func(ctx *cli.Context) error {
        l1ChainID := ctx.Uint64(L1ChainIDFlagName)         // --l1-chain-id
        outdir := ctx.String(OutdirFlagName)               // --workdir  
        l2ChainIDsRaw := ctx.String(L2ChainIDsFlagName)    // --l2-chain-ids
        intentType := ctx.String(IntentTypeFlagName)       // --intent-type
        
        // Parse comma-separated L2 chain IDs
        l2ChainIDsStr := strings.Split(strings.TrimSpace(l2ChainIDsRaw), ",")
        l2ChainIDs := make([]common.Hash, len(l2ChainIDsStr))
        for i, idStr := range l2ChainIDsStr {
            id, err := op_service.Parse256BitChainID(idStr)
            if err != nil {
                return fmt.Errorf("invalid L2 chain ID '%s': %w", idStr, err)
            }
            l2ChainIDs[i] = id
        }
        
        // Create and execute init
        err := Init(InitConfig{
            IntentType: state.IntentType(intentType),
            L1ChainID:  l1ChainID,
            Outdir:     outdir,
            L2ChainIDs: l2ChainIDs,
        })
        
        return err
    }
}
```

## Validation Rules

### L1 Chain ID
- Must be > 0
- Standard Ethereum chain IDs supported

### L2 Chain IDs  
- Must provide at least one L2 chain ID
- Each ID parsed as 256-bit chain ID
- Comma-separated for multiple chains
- Format: decimal numbers (e.g., "10,8453")

### Working Directory
- Must be specified
- Created if doesn't exist (os.MkdirAll)
- Must be a directory if exists

### Intent Type
- Must be one of: "standard", "custom", "standard-overrides"
- Case-sensitive
- Defined in `op-deployer/pkg/deployer/state/intent.go:22-26`

## Generated Files

### Output Structure
```
<workdir>/
├── intent.toml   # Deployment configuration
└── state.json    # Deployment state tracking
```

### Intent File Creation
**File:** `op-deployer/pkg/deployer/init.go:102-104`

```go
if err := intent.WriteToFile(path.Join(cfg.Outdir, "intent.toml")); err != nil {
    return fmt.Errorf("failed to write intent to file: %w", err)
}
```

### State File Creation  
**File:** `op-deployer/pkg/deployer/init.go:105-107`

```go
if err := st.WriteToFile(path.Join(cfg.Outdir, "state.json")); err != nil {
    return fmt.Errorf("failed to write state to file: %w", err)
}
```

## Flag Name Constants

The actual flag names are defined as constants (need to locate these):
- `L1ChainIDFlagName` → likely `"l1-chain-id"`  
- `OutdirFlagName` → likely `"workdir"` or `"outdir"`
- `L2ChainIDsFlagName` → likely `"l2-chain-ids"`
- `IntentTypeFlagName` → likely `"intent-type"`

## Error Handling

### Common Errors
1. **Missing L1 Chain ID:** `"l1ChainID must be specified"`
2. **Missing Outdir:** `"outdir must be specified"`  
3. **No L2 Chains:** `"must specify at least one L2 chain ID"`
4. **Invalid L2 Chain ID:** `"invalid L2 chain ID '%s': %w"`
5. **Directory Creation Failed:** `"failed to create outdir: %w"`
6. **File Write Failed:** `"failed to write intent/state to file: %w"`

## Integration Points

### Kurtosis Integration
- **Container:** `us-docker.pkg.dev/oplabs-tools-artifacts/images/op-deployer:v0.4.2`
- **Working Directory:** `/network-data`
- **Current Command:** `op-deployer init --intent-config-type custom --l1-chain-id $L1_CHAIN_ID --l2-chain-ids {chain_ids} --workdir /network-data`

### Potential Issues
1. **Flag Name Mismatch:** Kurtosis uses `--intent-config-type`, code shows `--intent-type`
2. **Version Differences:** Container version may have different flag names
3. **Backward Compatibility:** Need to verify flag names across versions

## Code References

- **Main Command:** `op-deployer/cmd/op-deployer/main.go:37-43`
- **Flags Array:** `op-deployer/pkg/deployer/flags.go:158-163`  
- **CLI Handler:** `op-deployer/pkg/deployer/init.go:41-75`
- **Config Struct:** `op-deployer/pkg/deployer/init.go:18-23`
- **Init Function:** `op-deployer/pkg/deployer/init.go:77-109`
- **Intent Types:** `op-deployer/pkg/deployer/state/intent.go:22-26`

## Next Steps

- [ ] Locate actual flag name constants
- [ ] Verify Kurtosis flag compatibility  
- [ ] Test all intent types with sample configurations
- [ ] Document generated file formats
- [ ] Create example configurations for each intent type

## Contact

For questions about op-deployer init flags, refer to:
- **Op-Deployer Source:** `op-deployer/pkg/deployer/`
- **CLI Documentation:** `op-deployer/book/src/user-guide/init.md`
- **Issue Tracking:** `/Users/zena/tokamak-projects/optimism/op-challenger/scripts/issue/`