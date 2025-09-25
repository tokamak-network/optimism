# CANNON Prestate File Issue Analysis

**Last Updated**: September 25, 2025
**Version**: 1.0
**Target**: CANNON dispute game prestate resolution

## Issue Overview

When deploying Optimism devnet with CANNON game type (`--game-type=0`), the challenger service consistently fails to participate in dispute games due to missing prestate files.

**Error Pattern**:
```
required prestate 0x038512e02c4c3f7bdaec27d00edf55b7155e0905301e1a88083e4e0a6764d54c not available
```

**Impact**:
- Dispute games proceed without challenger participation
- All games resolve as `DEFENDER_WINS` after maxClockDuration (20 minutes)
- Fault-proof system cannot be fully tested

## Current Status Analysis

### ✅ **Working Components**
- RAT system deployment successful
- Dispute games created correctly with CANNON type (0)
- Proposer submits correct Output Roots
- Game timing configuration proper (20min/5min)
- L1/L2 chains operating normally

### ❌ **Failing Component**
- Challenger cannot participate due to missing CANNON prestate files
- Required prestate hash: `0x038512e02c4c3f7bdaec27d00edf55b7155e0905301e1a88083e4e0a6764d54c`

## Technical Background

### What are CANNON Prestate Files?

CANNON prestate files contain the initial VM state required for fault-proof execution. These files include:

1. **VM Memory State**: Initial memory layout for MIPS VM
2. **Register State**: Initial CPU register values
3. **Program Counter**: Starting execution address
4. **Syscall State**: System call interface state

### How Prestate Files are Used

```
Challenger Process:
1. Monitor dispute games
2. Detect invalid state transitions
3. Load required prestate file for VM execution
4. Execute fault-proof to generate challenges
5. Submit challenge transactions to dispute game
```

### Prestate Hash Calculation

The prestate hash `0x038512e...` is calculated as:
```
keccak256(prestate_binary_data)
```

## Investigation Areas

### 1. **Prestate Generation Process**

**Files to investigate**:
- `op-program/` - CANNON program implementation
- `cannon/` - CANNON VM implementation
- Prestate generation scripts in build process

**Questions**:
- How are prestate files generated during build?
- Where should they be stored in devnet environment?
- Are they included in Docker images or uploaded separately?

### 2. **Challenger Configuration**

**Files to investigate**:
- `op-challenger/` - Challenger implementation
- Challenger configuration in `simple.yaml`
- Prestate loading logic

**Questions**:
- How does challenger locate prestate files?
- What configuration parameters control prestate paths?
- Are prestate URLs configured correctly?

### 3. **Kurtosis Devnet Setup**

**Files to investigate**:
- `kurtosis-devnet/simple.yaml` - Devnet configuration
- `optimism-package` - Kurtosis deployment logic
- Artifact upload process

**Questions**:
- Are prestate files included in artifacts?
- Do prestate URLs point to correct locations?
- Is prestate distribution working in Kurtosis?

## Error Log Analysis

### Challenger Log Pattern
```
t=2025-09-25T04:02:26+0000 lvl=warn msg="Failed to create solver" game=0xcdAcbBe06CBBfb31c2a5B613Aa266A19a851AB24 err="required prestate 0x038512e02c4c3f7bdaec27d00edf55b7155e0905301e1a88083e4e0a6764d54c not available"
```

### Game State Results
- **Games Created**: 6 total
- **DEFENDER_WINS**: 4 games (no challenger participation)
- **IN_PROGRESS**: 2 games (waiting for timeout)
- **All games**: Same prestate error

## Potential Solutions

### 1. **Build Process Enhancement**

```bash
# Potential build steps to add:
make cannon-prestate    # Generate prestate files
make prestate-upload    # Include in artifacts
```

### 2. **Configuration Updates**

Update `simple.yaml` to include prestate file paths:
```yaml
op_challenger_params:
  prestate_url: "artifact://prestate-files"
  prestate_hash: "0x038512e..."
```

### 3. **Docker Image Updates**

Include prestate files in challenger Docker image:
```dockerfile
COPY prestate/ /app/prestate/
```

## Investigation Plan

### Phase 1: Understand Prestate Generation
1. Research how prestate files are generated in op-program
2. Identify where prestate files should be stored
3. Check if build-devnet.sh includes prestate generation

### Phase 2: Fix Distribution
1. Ensure prestate files are included in build artifacts
2. Update Kurtosis configuration to distribute prestate files
3. Verify challenger can access prestate files

### Phase 3: Test Resolution
1. Deploy devnet with prestate files available
2. Verify challenger participates in dispute games
3. Confirm fault-proof system works end-to-end

## Related Issues

### Similar Problems in Other Contexts
- Asterisc prestate files (game type 2)
- Missing cannon binaries in CI/CD
- Prestate version mismatches

### Documentation Gaps
- Prestate file generation process
- CANNON VM setup requirements
- Fault-proof system architecture

## References

- **[RAT Development History](rat-development-history.md)**: Context of current implementation
- **[Post-deployment Verification Guide](post-deployment-verification-guide.md)**: How to verify prestate availability
- **[Build Process Documentation](build-devnet-process.md)**: Current build process analysis

---

*This document tracks the CANNON prestate file availability issue and potential resolution approaches.*