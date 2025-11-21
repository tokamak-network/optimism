# RAT Deployment Implementation History

**Last Updated**: September 25, 2025
**Version**: 1.0
**Target**: Historical record of RAT system development

## Overview

This document records the complete development history of the RAT (Random Access Test) deployment system implementation, including all challenges faced, solutions implemented, and lessons learned during the process.

## Development Timeline

### Phase 1: Initial RAT Implementation (September 24, 2025)

#### Completed Tasks ✅

1. **RAT Configuration Setup** - `simple-processed.yaml` RAT parameter configuration
   - `minimumStakingBalance: "1000000000000000000"` (1 ETH)
   - `perTestBondAmount: "100000000000000"` (0.0001 ETH)
   - `ratTriggerProbability: "100000"` (100%)
   - `deployRAT: true`

2. **JSON Serialization Type Conversion Issue Resolution**
   - `op-deployer/pkg/deployer/opcm/opchain.go:47-53` - Changed RAT fields from `*hexutil.Big` to `*big.Int`
   - `op-deployer/pkg/deployer/state/deploy_config.go:41-60` - Added `preprocessRATOverrides()` function to convert strings to *big.Int

3. **Docker Image Build Success** (7/7 services)
   - All services built successfully: op-node, op-batcher, op-proposer, op-faucet, op-challenger, op-deployer

4. **Artifact Generation and Upload**
   - l1-artifacts (384M), l2-artifacts (385M) generation completed
   - Integrated artifact upload logic into trampoline package

5. **Trampoline Package Configuration**
   - `kurtosis-devnet/optimism-package-trampoline/main.star` - Modified to use `github.com/tokamak-network/optimism-package`
   - `kurtosis-devnet/optimism-package-trampoline/kurtosis.yml` - Added dependencies

#### Issues Encountered ❌

1. **Step 3/6 Deployment Halt**
   - **Location**: L1 Chain & Contract Deployment stage
   - **Symptom**: op-deployer-apply service stopped after L1 database initialization
   - **Logs**: `"State snapshot generator is not found"`, `"Initialized path database"` followed by no response

2. **Artifact Missing Error Recurrence**
   ```
   Error while validating instruction get_files_artifact(name="l1-artifacts")
   Caused by: Files artifact 'l1-artifacts' required by 'get_files_artifact' instruction doesn't exist
   ```

3. **Multiple Background Processes**
   - 16 background build-devnet.sh and kurtosis run processes running in parallel
   - Potential for resource contention and enclave conflicts

#### Debugging Performed 🔍

1. **op-deployer Container Inspection**
   ```bash
   kurtosis service exec simple-devnet op-deployer-apply "ps aux"
   # Result: No actual deployment process, only tail process running
   ```

2. **Service Status Check**
   ```bash
   kurtosis enclave inspect simple-devnet
   # Result: L1 chain (Geth+Teku) running normally, op-deployer-apply RUNNING status but inactive
   ```

3. **Package Dependency Issue Check**
   - Resolved mismatch between `github.com/tokamak-network/optimism-package` vs `github.com/ethpandaops/optimism-package`

### Phase 2: Output Root vs State Root Investigation (September 25, 2025)

#### Major Discovery 🎯

**Issue**: Confusion about proposer submissions vs L2 block state roots
- **Problem**: Proposer submitted value `0xf11ed3e5a8556be57fc3edf178b9809264bf15ac6dd31bef857cd02f867da77a` differed from L2 block 12 State Root `0x5589280545fddd46ef2a0b4792f9118bdcb1d44ec82cdbeeb592d582a24eb57d`
- **Root Cause**: Fundamental misunderstanding of Optimism architecture
- **Solution**: Discovered that proposers submit **Output Root** (composite hash) not **State Root** (single block state)

#### Technical Resolution ✅

1. **Output Root Concept Clarification**
   - Output Root = Keccak256(version + stateRoot + messagePasserStorageRoot)
   - Verified using op-node RPC `optimism_outputAtBlock` method
   - Confirmed proposer was submitting correct Output Root

2. **Documentation Enhancement**
   - Created comprehensive `output-root-vs-state-root-explanation.md`
   - Updated existing documentation with cross-references
   - Added detailed technical explanations with code examples

### Phase 3: New Devnet Analysis (September 25, 2025)

#### Successful Deployment ✅

1. **New devnet deployment completed successfully**
2. **Challenger log analysis revealed consistent prestate issues**
3. **Verification that challenger logs matched actual game states**
4. **Final confirmation that RAT system is working correctly**

#### CANNON Prestate Issue Identified ⚠️

**Problem**: Challenger cannot participate in dispute games
- **Error**: `required prestate 0x038512e02c4c3f7bdaec27d00edf55b7155e0905301e1a88083e4e0a6764d54c not available`
- **Impact**: Games proceed to DEFENDER_WINS due to no challenger participation
- **Status**: Requires separate investigation and resolution

## File Changes History

### Core Implementation Files
- `op-deployer/pkg/deployer/opcm/opchain.go` - RAT field type changes
- `op-deployer/pkg/deployer/state/deploy_config.go` - String conversion functions
- `kurtosis-devnet/optimism-package-trampoline/main.star` - Package reference updates
- `kurtosis-devnet/optimism-package-trampoline/kurtosis.yml` - Dependency additions
- `kurtosis-devnet/simple-processed.yaml` - RAT configuration parameters

### Documentation Files
- `output-root-vs-state-root-explanation.md` (Created) - Comprehensive Output Root explanation
- `op-proposer-dgf-proposal-flow.md` (Modified) - Added Output Root warnings
- `op-proposer-analysis.md` (Modified) - Added cross-references
- `post-deployment-verification-guide.md` (Modified) - Added Output Root reference

## Lessons Learned

### Technical Insights
1. **Output Root ≠ State Root**: Critical architectural understanding for Optimism fault-proof system
2. **Prestate Requirements**: CANNON game type requires specific prestate files for challenger participation
3. **Documentation Importance**: Clear technical documentation prevents future confusion

### Development Process
1. **Systematic Investigation**: Step-by-step analysis leads to root cause discovery
2. **Cross-Reference Documentation**: Linking related documents improves maintainability
3. **Historical Recording**: Maintaining development history helps future debugging

## Current Status (September 25, 2025)

### ✅ **Successfully Resolved**
- RAT system deployment architecture
- Output Root vs State Root confusion
- Proposer submission validation
- Documentation gaps

### ⏸️ **Pending Investigation**
- CANNON prestate file availability
- Challenger participation in dispute games
- Prestate generation and distribution process

## Next Steps

1. **CANNON Prestate Investigation**: Research how to generate and provide required prestate files
2. **Challenger Enablement**: Enable full challenger participation in CANNON dispute games
3. **Production Readiness**: Prepare RAT system for production deployment

---

*This document serves as a historical record of RAT system development for future reference and troubleshooting.*