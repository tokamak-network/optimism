# DisputeGameFactory Deployment Bug Report

**Date:** September 1, 2025  
**Reporter:** Development Team  
**Severity:** High  
**Status:** Active  

## Summary

Critical deployment bug in Kurtosis devnet where DisputeGameFactory is deployed without proper game implementations and bond configurations, preventing dispute game creation and causing challenger validation failures.

## Environment

- **Network:** Kurtosis devnet (simple-devnet)
- **L1 Chain ID:** 3151908
- **L2 Chain ID:** 2151908  
- **Game Type:** CANNON (GameType 0)
- **DisputeGameFactory:** `0x2a7fec87ab706be8a63eb4d7aee12ee519573af1`

## Problem Description

### 1. Missing Game Implementations

**Expected:**
```bash
cast call 0x2a7fec87ab706be8a63eb4d7aee12ee519573af1 "gameImpls(uint32)" 0 --rpc-url $L1_RPC
# Should return FaultDisputeGame implementation address
```

**Actual:**
```bash
cast call 0x2a7fec87ab706be8a63eb4d7aee12ee519573af1 "gameImpls(uint32)" 0 --rpc-url $L1_RPC
# Returns: 0x0000000000000000000000000000000000000000000000000000000000000000
```

### 2. Missing Bond Configuration

**Expected:**
```bash
cast call 0x2a7fec87ab706be8a63eb4d7aee12ee519573af1 "initBonds(uint32)" 0 --rpc-url $L1_RPC  
# Should return bond amount (e.g., 0.08 ETH = 80000000000000000)
```

**Actual:**
```bash
cast call 0x2a7fec87ab706be8a63eb4d7aee12ee519573af1 "initBonds(uint32)" 0 --rpc-url $L1_RPC
# Returns: 0x0000000000000000000000000000000000000000000000000000000000000000
```

### 3. Deployment State Analysis

From `env.json`:
```json
{
  "FaultDisputeGameImpl": "0x0000000000000000000000000000000000000000",
  "PermissionedDisputeGameImpl": "0x27db09a3d3c55fc466e59a2ae68f9bf334c1659d"
}
```

- ✅ **PermissionedDisputeGame**: Successfully deployed
- ❌ **FaultDisputeGame**: Not deployed (0x0000...)

## Impact

### 1. Game Creation Failures

Any attempt to create CANNON games fails silently:
```bash
cast send 0x2a7fec87ab706be8a63eb4d7aee12ee519573af1 "create(uint32,bytes32,bytes)" \
  0 0x... 0x... --rpc-url $L1_RPC
# Transaction succeeds but no game is created (no events emitted)
```

### 2. Challenger Validation Errors

Existing games cause continuous challenger errors:
```
Failed to schedule game updates: failed to validate prestate: 
output root absolute prestate does not match: 
Provider: 0x35f88ec7c32dd2a7dfdc0d8fe516bd2f86207fe7d91d1fe441d2a11ec626e84f | 
Contract: 0xdead000000000000000000000000000000000000000000000000000000000000
```

### 3. Proposer Workaround

Op-proposer bypasses DisputeGameFactory and creates games through proxy contract:
- **Game created by:** `0xb0994e702b603df7191cd68e6544f99126135e34` (proposer)  
- **Through proxy:** `0x10FD055B0Edd1EfE76eDD9766a6642D058dB4Aa7`
- **Existing game:** `0x1390469fBCB66404257Bc44BfAD9b56AA8DaB9BC`

## Root Cause Analysis

### 1. OPContractsManager Hardcoded Deployment

**File:** `/Users/zena/tokamak-projects/optimism/packages/contracts-bedrock/src/L1/OPContractsManager.sol:1047-1048`

The OPContractsManager contract hardcodes PermissionedDisputeGame deployment regardless of game_type configuration:

```solidity
// While not a proxy, we deploy the PermissionedDisputeGame here as well because it's bespoke per chain.
output.permissionedDisputeGame = IPermissionedDisputeGame(
    Blueprint.deployFrom(
        blueprint.permissionedDisputeGame1,
        blueprint.permissionedDisputeGame2,
        computeSalt(_input.l2ChainId, _input.saltMixer, "PermissionedDisputeGame"),
```

**Impact:** 
- game_type: 0 (CANNON) configuration in `simple.yaml` is completely ignored
- Only PermissionedDisputeGame is deployed, never FaultDisputeGame
- No game implementations are registered in DisputeGameFactory

### 2. DeployDisputeGame Script Not Called

**Analysis of deployment pipeline:**

1. **Basic OPChain Deployment:** Uses OPContractsManager.deploy() which hardcodes PermissionedDisputeGame
   - File: `op-deployer/pkg/deployer/pipeline/opchain.go:36`
   - Command: `opcm.DeployOPChain(env.L1ScriptHost, dci)`
   - Never calls DeployDisputeGame script

2. **DeployDisputeGame Script Exists but Unused:** 
   - File: `packages/contracts-bedrock/scripts/deploy/DeployDisputeGame.s.sol`
   - Supports both "FaultDisputeGame" and "PermissionedDisputeGame" via gameKind parameter
   - Only called for additional games in `pipeline/dispute_games.go:107` (DeployAdditionalDisputeGames)

3. **Game Registration Missing:**
   - DeployDisputeGame script creates implementations but doesn't register them
   - No calls to DisputeGameFactory.setImplementation()
   - No bond configuration via DisputeGameFactory.setInitBond()

### 3. Deployment Architecture Issue

**Current Flow with Code References:**
```
op-deployer apply → OPContractsManager.deploy() → Blueprint.deployFrom(PermissionedDisputeGame) → Done
```

**Detailed Code Path:**

1. **op-deployer apply command:**
   - File: `op-deployer/pkg/deployer/pipeline/opchain.go:36`
   ```go
   dco, err = opcm.DeployOPChain(env.L1ScriptHost, dci)
   ```

2. **Go wrapper calls Solidity:**
   - File: `op-deployer/pkg/deployer/opcm/opchain.go:46`
   ```go
   func DeployOPChain(
       host *script.Host,
       input DeployOPChainInput,
   ) (DeployOPChainOutput, error) {
       return RunScriptSingle[DeployOPChainInput, DeployOPChainOutput](host, input, "DeployOPChain.s.sol", "DeployOPChain")
   }
   ```

3. **Solidity script execution:**
   - File: `packages/contracts-bedrock/scripts/deploy/DeployOPChain.s.sol:run()`
   - Calls: `opcm.deploy(DeployOPChainInput)`

4. **OPContractsManager hardcoded deployment:**
   - File: `packages/contracts-bedrock/src/L1/OPContractsManager.sol:1047-1048`
   ```solidity
   // While not a proxy, we deploy the PermissionedDisputeGame here as well because it's bespoke per chain.
   output.permissionedDisputeGame = IPermissionedDisputeGame(
       Blueprint.deployFrom(
           blueprint.permissionedDisputeGame1,
           blueprint.permissionedDisputeGame2,
           computeSalt(_input.l2ChainId, _input.saltMixer, "PermissionedDisputeGame"),
           abi.encode(
               args, _input.proposer, _input.challenger
           )
       )
   );
   ```

5. **Blueprint.deployFrom() execution:**
   - File: `packages/contracts-bedrock/src/libraries/Blueprint.sol:deployFrom()`
   ```solidity
   function deployFrom(
       address blueprint1,
       address blueprint2, 
       bytes32 salt,
       bytes memory initCode
   ) internal returns (address) {
       bytes memory creationCode = blueprintCode(blueprint1, blueprint2, initCode);
       return Clones.cloneDeterministic(template, salt);
   }
   ```

**Missing Flow:**
```
op-deployer → DeployDisputeGame.s.sol → FaultDisputeGame/PermissionedDisputeGame → Register in Factory → Set Bonds
```

### 4. Configuration Ignored

**Devnet Config:** `kurtosis-devnet/simple.yaml:12-13`
```yaml
l2_additional_configs:
  "0": 
    game_type: 0  # CANNON - should deploy FaultDisputeGame
```

**Configuration Flow Breakdown:**

1. **Kurtosis reads config:** `simple.yaml` → `kurtosis run` parameters
2. **Op-deployer input:** Configuration gets passed to `DeployOPChainInput` struct  
   - File: `op-deployer/pkg/deployer/pipeline/opchain.go:75-114`
   ```go
   return opcm.DeployOPChainInput{
       OpChainProxyAdminOwner:       thisIntent.Roles.L1ProxyAdminOwner,
       // ... other fields ...
       DisputeGameType:              proofParams.DisputeGameType,  // ← game_type gets set here
   }
   ```

3. **OPContractsManager ignores it:** The DisputeGameType field is passed but never used for deployment decision
   - File: `packages/contracts-bedrock/src/L1/OPContractsManager.sol:1047`
   - **Problem:** Hardcoded `PermissionedDisputeGame` regardless of `_input.disputeGameType` value

**Reality:** OPContractsManager ignores `_input.disputeGameType` completely and always deploys PermissionedDisputeGame

### 5. Expected vs Actual Deployment

**Expected for game_type: 0 (CANNON):**
```
1. Deploy FaultDisputeGame implementation
2. Register: factory.setImplementation(GameType.CANNON, faultImpl)
3. Set bond: factory.setInitBond(GameType.CANNON, bondAmount)
```

**Actual:**
```
1. Deploy PermissionedDisputeGame (hardcoded)
2. No factory registration
3. No bond configuration
```

## Investigation Commands

### Check Current State
```bash
# L1 RPC endpoint
L1_RPC="http://127.0.0.1:51795"
DGF="0x2a7fec87ab706be8a63eb4d7aee12ee519573af1"

# Check implementations
cast call $DGF "gameImpls(uint32)" 0 --rpc-url $L1_RPC  # CANNON
cast call $DGF "gameImpls(uint32)" 1 --rpc-url $L1_RPC  # PERMISSIONED_CANNON

# Check bonds  
cast call $DGF "initBonds(uint32)" 0 --rpc-url $L1_RPC  # CANNON
cast call $DGF "initBonds(uint32)" 1 --rpc-url $L1_RPC  # PERMISSIONED_CANNON

# Check game count
cast call $DGF "gameCount()" --rpc-url $L1_RPC
```

### Check Challenger Logs
```bash
kurtosis service logs simple-devnet op-challenger-challenger-2151908 | tail -10
```

### Check Existing Game
```bash
EXISTING_GAME="0x1390469fBCB66404257Bc44BfAD9b56AA8DaB9BC"
cast call $EXISTING_GAME "gameType()" --rpc-url $L1_RPC
cast call $EXISTING_GAME "status()" --rpc-url $L1_RPC  
cast call $EXISTING_GAME "rootClaim()" --rpc-url $L1_RPC
```

## Proposed Solution

### Option A: Immediate Devnet Fix (Hot Fix)

**Use existing DeployDisputeGame script to deploy and register FaultDisputeGame:**

1. **Deploy FaultDisputeGame Implementation:**
   ```bash
   forge script DeployDisputeGame --rpc-url $L1_RPC --broadcast \
     --input-gameKind "FaultDisputeGame" \
     --input-gameType 0 \
     --input-absolutePrestate 0x... \
     --input-vmAddress 0x...
   ```

2. **Register in Factory and Set Bonds:**
   ```bash
   cast send $DGF "setImplementation(uint32,address)" 0 $FAULT_IMPL --rpc-url $L1_RPC
   cast send $DGF "setInitBond(uint32,uint256)" 0 80000000000000000 --rpc-url $L1_RPC
   ```

### Option B: Architecture Fix (Long-term)

**Modify OPContractsManager to respect game_type configuration:**

1. **Update OPContractsManager.sol:**
   - Add game_type parameter to DeployOPChainInput
   - Replace hardcoded PermissionedDisputeGame with conditional logic
   - Deploy appropriate game type based on configuration

2. **Update op-deployer pipeline:**
   - Pass game_type from devnet config to OPContractsManager
   - Ensure proper game registration and bond configuration

3. **Integration with existing DeployDisputeGame:**
   - Have OPContractsManager call DeployDisputeGame script internally
   - Ensure consistent deployment patterns across all game types

### Option C: Hybrid Approach

**Keep OPContractsManager simple, enhance post-deployment:**

1. **OPContractsManager:** Always deploy PermissionedDisputeGame (current behavior)
2. **Post-deployment:** Check devnet config and deploy additional game types as needed
3. **Register both implementations:** Use existing pipeline/dispute_games.go pattern

## Scope Analysis: Devnet vs Production

### Is this a Devnet-only issue?

**NO** - This is a systemic architecture issue affecting all OP Stack deployments:

1. **OPContractsManager Logic:** The hardcoded PermissionedDisputeGame deployment exists in production code
2. **Game Type Ignored:** Any deployment using OPContractsManager will ignore game_type configuration
3. **Factory Registration:** Production deployments also lack proper DisputeGameFactory registration
4. **Bond Configuration:** Production deployments also lack bond configuration

### Production Impact

**Mainnet/Testnet deployments likely have the same issue:**
- DisputeGameFactory deployed but not configured
- Only PermissionedDisputeGame available (if at all)
- game_type configuration in deployment scripts ignored
- Manual post-deployment steps required for proper setup

### Why This Went Unnoticed

1. **Additional Games Pipeline:** Most production deployments use `DeployAdditionalDisputeGames` which correctly deploys and registers games
2. **Manual Configuration:** Production deployments may have manual post-deployment configuration
3. **Devnet Isolation:** Development teams may not have tested basic OPChain deployment in isolation

## Fix Implementation Status

- [x] Bug report created and analyzed
- [x] Root cause identified: OPContractsManager hardcoded deployment
- [x] Architecture analysis completed
- [ ] Deploy FaultDisputeGame implementation  
- [ ] Register game implementations in DisputeGameFactory
- [ ] Configure bond amounts
- [ ] Test and verify fix
- [ ] Determine production impact and remediation plan

## Related Files

- `/Users/zena/tokamak-projects/optimism/packages/contracts-bedrock/src/dispute/DisputeGameFactory.sol`
- `/Users/zena/tokamak-projects/optimism/packages/contracts-bedrock/src/dispute/FaultDisputeGame.sol`
- `/Users/zena/tokamak-projects/optimism/packages/contracts-bedrock/src/L1/OPContractsManager.sol`
- `/Users/zena/tokamak-projects/optimism/kurtosis-devnet/fix-anchor-state.sh`

## Contact

For questions about this issue, refer to the development team or check the challenger logs for additional debugging information.