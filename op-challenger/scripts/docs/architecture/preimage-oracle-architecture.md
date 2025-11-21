# Preimage Oracle Architecture

## Overview

This document explains how the Preimage Oracle system works in Optimism's Fault Proof system, detailing the communication mechanism between the VM (Asterisc/Cannon) and the Host (op-program host).

## Table of Contents

1. [System Architecture](#system-architecture)
2. [Communication Channels](#communication-channels)
3. [Prestate Concepts](#prestate-concepts)
4. [Game Type to VM Mapping](#game-type-to-vm-mapping)
5. [Hint and Preimage Flow](#hint-and-preimage-flow)
6. [Data Storage](#data-storage)
7. [Complete Flow Diagram](#complete-flow-diagram)

---

## System Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Asterisc VM (RISC-V) / Cannon VM (MIPS)               │
│  - Executes op-program client                           │
│  - Communicates with Host via File Descriptors          │
├─────────────────────────────────────────────────────────┤
│  File Descriptors (Pipes):                              │
│  - FD 3: Hint Reader  (VM → Host)                       │
│  - FD 4: Hint Writer  (VM ← Host)                       │
│  - FD 5: Preimage Reader (VM ← Host)                    │
│  - FD 6: Preimage Writer (VM → Host)                    │
├─────────────────────────────────────────────────────────┤
│  Host (op-program host)                                 │
│  ├─ Preimage Server (goroutine)                         │
│  │   └─ Prefetcher                                      │
│  │       └─ kvStore (directory.go)                      │
│  └─ Hint Router (goroutine)                             │
│      └─ Prefetcher.Hint()                               │
└─────────────────────────────────────────────────────────┘
```

### Components

#### 1. VM (Virtual Machine)
- **Asterisc**: RISC-V VM for executing op-program
- **Cannon**: MIPS VM for executing op-program
- Runs as a separate process
- Communicates with Host via Unix pipes

#### 2. Host (op-program host)
- **Preimage Server**: Handles preimage requests from VM
- **Hint Router**: Processes hints from VM
- **Prefetcher**: Fetches data from L1/L2
- **kvStore**: Disk-backed storage for preimages

---

## Communication Channels

### Pipe Creation

**Location**: `op-program/host/common/common.go:97-110`

```go
// Create bidirectional channels
pClientRW, pHostRW, err := preimage.CreateBidirectionalChannel()
// pClientRW: Used by VM (FD 5, 6)
// pHostRW: Used by Host

hClientRW, hHostRW, err := preimage.CreateBidirectionalChannel()
// hClientRW: Used by VM (FD 3, 4)
// hHostRW: Used by Host
```

### File Descriptor Assignment

**Location**: `op-program/host/common/common.go:56-73`

```go
cmd := exec.CommandContext(ctx, cfg.ExecCmd)  // asterisc or cannon
cmd.ExtraFiles = make([]*os.File, cl.MaxFd-3)
cmd.ExtraFiles[cl.HClientRFd-3] = hClientRW.Reader()  // FD 3: Hint Read
cmd.ExtraFiles[cl.HClientWFd-3] = hClientRW.Writer()  // FD 4: Hint Write
cmd.ExtraFiles[cl.PClientRFd-3] = pClientRW.Reader()  // FD 5: Preimage Read
cmd.ExtraFiles[cl.PClientWFd-3] = pClientRW.Writer()  // FD 6: Preimage Write
```

### File Descriptors Summary

| FD | Direction | Purpose | Used By |
|----|-----------|---------|---------|
| 3  | VM → Host | Hint Request | HintReader |
| 4  | Host → VM | Hint Response | HintWriter |
| 5  | Host → VM | Preimage Response | PreimageReader |
| 6  | VM → Host | Preimage Request | PreimageWriter |

---

## Prestate Concepts

### Two Types of Prestate

#### 1. Absolute Prestate (VM Level)

**File**: `prestate-mt64.bin.gz` (for Asterisc)

**Purpose**: VM's initial memory state
- Contains RISC-V/MIPS memory layout
- Includes op-program binary loaded
- Same for all games of the same type
- Never changes

**Usage**:
```bash
asterisc run --input prestate-mt64.bin.gz ...
```

**Location in Code**: `op-challenger/game/fault/register_task.go:140`

```go
cfg.AsteriscAbsolutePreState  // Path to prestate-mt64.bin.gz
```

#### 2. L2 Output Root Prestate (Application Level)

**Purpose**: Starting point for L2 block range
- Output root from previously finalized L2 block
- Different for each game
- Updates as chain progresses

**Example**:
```
Game for Block 3000:
  Prestate: Output Root B (from Block 2000)
  Prove: Blocks 2000 → 3000
  Poststate: Output Root C
```

**Location in Code**: `op-challenger/game/fault/trace/outputs/prestateProvider.go`

```go
type PrestateProvider struct {
    rollupClient  outputs.OutputRollupClient
    prestateBlock uint64  // Last agreed L2 block number
}
```

### Why Both Are Needed

```
Absolute Prestate: Like a game executable
  └─ Boots up the VM
  └─ Loads op-program binary
  └─ Always required

L2 Output Root: Like a save file
  └─ "Start from Level 10"
  └─ Logical starting point
  └─ Varies per game
```

### Scaling Strategy

Without anchoring:
```
Day 1:   Block 0 → 100      (100 blocks)
Day 365: Block 0 → 3,650,000 (3.6M blocks) ❌ Too long!
```

With anchoring:
```
Game 1: Root_0 + Blocks[0→1000]     → Root_1000
Game 2: Root_1000 + Blocks[1000→2000] → Root_2000
Game 3: Root_2000 + Blocks[2000→3000] → Root_3000
```

Each game proves a **fixed block range** (e.g., ~1000 blocks).

---

## Game Type to VM Mapping

### Game Types

**Location**: `op-challenger/game/fault/types/types.go:27-42`

```go
const (
    CannonGameType            GameType = 0  // MIPS
    PermissionedGameType      GameType = 1  // MIPS (permissioned)
    AsteriscGameType          GameType = 2  // RISC-V (op-program)
    AsteriscKonaGameType      GameType = 3  // RISC-V (kona)
    SuperCannonGameType       GameType = 4  // MIPS (interop)
    SuperPermissionedGameType GameType = 5  // MIPS (interop, permissioned)
    OPSuccinctGameType        GameType = 6  // ZK proof
    SuperAsteriscKonaGameType GameType = 7  // RISC-V (kona, interop)
    FastGameType              GameType = 254
    AlphabetGameType          GameType = 255
)
```

### RegisterTask Mapping

**Location**: `op-challenger/game/fault/register.go`

Each game type is registered with its own configuration:

```go
// Asterisc (GameType 2) - Uses op-program
if cfg.TraceTypeEnabled(faultTypes.TraceTypeAsterisc) {
    registerTasks = append(registerTasks,
        NewAsteriscRegisterTask(
            faultTypes.AsteriscGameType,
            cfg, m,
            vm.NewOpProgramServerExecutor(logger),  // ← op-program executor
            l2HeaderSource, rollupClient, syncValidator))
}

// Asterisc Kona (GameType 3) - Uses kona
if cfg.TraceTypeEnabled(faultTypes.TraceTypeAsteriscKona) {
    registerTasks = append(registerTasks,
        NewAsteriscKonaRegisterTask(
            faultTypes.AsteriscKonaGameType,
            cfg, m,
            vm.NewKonaExecutor(),  // ← kona executor
            l2HeaderSource, rollupClient, syncValidator))
}
```

### VM Configuration

**Location**: `op-challenger/game/fault/trace/vm/executor.go:42-62`

```go
type Config struct {
    VmType          types.TraceType  // "asterisc" or "asterisc-kona"
    VmBin           string            // Path to VM executable
    SnapshotFreq    uint
    InfoFreq        uint
    DebugInfo       bool
    BinarySnapshots bool

    // Oracle server configuration
    L1                string
    L1Beacon          string
    L2s               []string
    Server            string  // Path to op-program or kona
    Networks          []string
    RollupConfigPaths []string
    L2GenesisPaths    []string
}
```

### Game Type Selection Flow

```
On-chain Game Creation:
├─ GameType = 2 (AsteriscGameType)
├─ absolutePrestate = hash(prestate-mt64.bin.gz)
└─ extraData = game metadata

Challenger Detects Game:
├─ Lookup GameType 2 in RegisterTask registry
├─ Use configuration from NewAsteriscRegisterTask
│   ├─ VM Config: cfg.Asterisc
│   │   ├─ VmBin = asterisc binary path
│   │   └─ Server = op-program binary path
│   ├─ Prestate = prestate-mt64.bin.gz
│   └─ StateConverter = Asterisc-specific
│
└─ Generate Trace:
    ├─ executor = OpProgramServerExecutor
    ├─ Run Asterisc VM
    │   └─ --input prestate-mt64.bin.gz
    └─ Run op-program (oracle server)
        └─ Process hints
            └─ Prefetcher
                └─ kvStore (directory.go)
```

---

## Hint and Preimage Flow

### Hint Types

#### L1 Hints

**Location**: `op-program/client/l1/hints.go`

```go
const (
    HintL1BlockHeader  = "l1-block-header"   // L1 block header
    HintL1Transactions = "l1-transactions"   // L1 transactions
    HintL1Receipts     = "l1-receipts"       // L1 receipts
    HintL1Blob         = "l1-blob"           // L1 blob (EIP-4844)
    HintL1Precompile   = "l1-precompile"     // Precompile result
)
```

#### L2 Hints

**Location**: `op-program/client/l2/hints.go`

```go
const (
    HintL2BlockHeader    = "l2-block-header"
    HintL2Transactions   = "l2-transactions"
    HintL2Receipts       = "l2-receipts"
    HintL2Code           = "l2-code"          // Contract code
    HintL2StateNode      = "l2-state-node"    // State trie node
    HintL2Output         = "l2-output"        // Output root
    HintL2BlockData      = "l2-block-data"    // Block execution data
    HintAgreedPrestate   = "agreed-pre-state" // Agreed prestate
    HintL2AccountProof   = "l2-account-proof" // Account proof
    HintL2PayloadWitness = "l2-payload-witness" // Execution witness
)
```

### Hint Processing

**Location**: `op-program/host/prefetcher/prefetcher.go:102-119`

```go
func (p *Prefetcher) Hint(hint string) error {
    p.logger.Trace("Received hint", "hint", hint)

    hintType, _, err := parseHint(hint)

    // Special case: Force block execution
    if hintType == l2.HintL2BlockData {
        return p.prefetch(context.Background(), hint)
    }

    // Bulk hints (multiple preimages at once)
    if hintType == l2.HintL2AccountProof || hintType == l2.HintL2PayloadWitness {
        p.lastBulkHint = hint
    } else {
        p.lastHint = hint  // Store for later use
    }
    return nil
}
```

### Preimage Request Processing

**Location**: `op-program/host/prefetcher/prefetcher.go:121-139`

```go
func (p *Prefetcher) GetPreimage(ctx context.Context, key common.Hash) ([]byte, error) {
    p.logger.Trace("Pre-image requested", "key", key)

    // Try to get from kvStore first
    pre, err := p.kvStore.Get(key)  // ← directory.go Get()

    // If not found, prefetch using the last hint
    for errors.Is(err, kvstore.ErrNotFound) && p.lastHint != "" {
        hint := p.lastHint

        // Fetch data based on hint type
        if err := p.prefetch(ctx, hint); err != nil {
            return nil, fmt.Errorf("prefetch failed: %w", err)
        }

        // Try again
        pre, err = p.kvStore.Get(key)
        if err != nil {
            p.logger.Error("Fetched pre-images for last hint but did not find required key",
                          "hint", hint, "key", key)
        }
    }
    return pre, err
}
```

### L1 Blob Prefetch Example

**Location**: `op-program/host/prefetcher/prefetcher.go:319-360`

```go
case l1.HintL1Blob:
    // Hint format: "l1-blob {versionHash}{index}{timestamp}"
    if len(hintBytes) != 48 {
        return fmt.Errorf("invalid blob hint: %x", hint)
    }

    blobVersionHash := common.Hash(hintBytes[:32])
    blobHashIndex := binary.BigEndian.Uint64(hintBytes[32:40])
    refTimestamp := binary.BigEndian.Uint64(hintBytes[40:48])

    // 1. Fetch blob sidecar from Beacon API
    indexedBlobHash := eth.IndexedBlobHash{
        Hash:  blobVersionHash,
        Index: blobHashIndex,
    }
    sidecars, err := p.l1BlobFetcher.GetBlobSidecars(ctx,
        eth.L1BlockRef{Time: refTimestamp},
        []eth.IndexedBlobHash{indexedBlobHash})

    // 2. Store KZG Commitment (SHA256)
    err = p.kvStore.Put(
        preimage.Sha256Key(blobVersionHash).PreimageKey(),
        sidecar.KZGCommitment[:])

    // 3. Store 4096 field elements
    blobKey := make([]byte, 80)
    copy(blobKey[:48], sidecar.KZGCommitment[:])

    for i := 0; i < 4096; i++ {  // params.BlobTxFieldElementsPerBlob
        rootOfUnity := l1.RootsOfUnity[i].Bytes()
        copy(blobKey[48:], rootOfUnity[:])
        blobKeyHash := crypto.Keccak256Hash(blobKey)

        // Store key
        p.kvStore.Put(
            preimage.Keccak256Key(blobKeyHash).PreimageKey(),
            blobKey)

        // Store blob data (32 bytes each)
        p.kvStore.Put(
            preimage.BlobKey(blobKeyHash).PreimageKey(),
            sidecar.Blob[i<<5:(i+1)<<5])
    }
```

---

## Data Storage

### Directory Structure

**Location**: `op-program/host/kvstore/directory.go`

```go
type directoryKV struct {
    sync.RWMutex
    path string  // Base directory path
}
```

#### Path Structure

```
{cfg.Datadir}/                           # Base directory from config
└── asterisc-trace/                      # VM type specific
    └── {localContext.Hex()}/            # Game context hash
        └── preimages/                   # Preimage directory
            ├── 0abc/                    # First 4 chars of key
            │   └── def1234...890.txt    # Rest of key + .txt
            └── ...
```

#### Example Path

```
/var/folders/pw/.../TestOutputAsteriscStepWithPreimage.../
└── asterisc-trace/
    └── 0x1954368326fc4f933bf1aa66f684ac722f9b167d49b0494b6a9c14eb44807fdd/
        └── preimages/
            └── 0abc/
                └── def1234567890abcdef.txt
```

### Storage Operations

#### Put Operation

**Location**: `op-program/host/kvstore/directory.go:39-65`

```go
func (d *directoryKV) Put(k common.Hash, v []byte) error {
    d.Lock()
    defer d.Unlock()

    log.Printf("💾 Saving preimage to disk: key=%s, size=%d bytes, path=%s",
               k.String()[:10]+"...", len(v), d.path)

    // Create temp file
    f, err := openTempFile(d.path, k.String()+".txt.*")
    if err != nil {
        return fmt.Errorf("failed to open temp file for pre-image %s: %w", k, err)
    }
    defer os.Remove(f.Name())

    // Write hex-encoded data
    if _, err := f.Write([]byte(hex.EncodeToString(v))); err != nil {
        _ = f.Close()
        return fmt.Errorf("failed to write pre-image %s to disk: %w", k, err)
    }
    if err := f.Close(); err != nil {
        return fmt.Errorf("failed to close temp pre-image %s file: %w", k, err)
    }

    // Create directory structure
    targetFile := d.pathKey(k)
    if err := os.MkdirAll(path.Dir(targetFile), 0777); err != nil {
        return fmt.Errorf("failed to create parent directory for pre-image %s: %w", f.Name(), err)
    }

    // Atomic rename
    if err := os.Rename(f.Name(), targetFile); err != nil {
        return fmt.Errorf("failed to move temp file %v to final destination %v: %w",
                         f.Name(), targetFile, err)
    }

    log.Printf("✅ Preimage saved successfully: %s", targetFile)
    return nil
}
```

#### Get Operation

**Location**: `op-program/host/kvstore/directory.go:67-83`

```go
func (d *directoryKV) Get(k common.Hash) ([]byte, error) {
    d.RLock()
    defer d.RUnlock()

    f, err := os.OpenFile(d.pathKey(k), os.O_RDONLY, filePermission)
    if err != nil {
        if errors.Is(err, os.ErrNotExist) {
            return nil, ErrNotFound
        }
        return nil, fmt.Errorf("failed to open pre-image file %s: %w", k, err)
    }
    defer f.Close()

    dat, err := io.ReadAll(f)
    if err != nil {
        return nil, fmt.Errorf("failed to read pre-image from file %s: %w", k, err)
    }

    // Decode hex-encoded data
    return hex.DecodeString(string(dat))
}
```

#### Path Key Generation

**Location**: `op-program/host/kvstore/directory.go:33-37`

```go
func (d *directoryKV) pathKey(k common.Hash) string {
    key := k.String()  // "0xabcdef1234567890..."
    dir, name := key[2:6], key[6:]  // Skip "0x", split into dir and name
    return path.Join(d.path, dir, name+".txt")
}
```

Example:
```
Key: 0xabcdef1234567890...
Dir: abcd
Name: ef1234567890...
Path: {path}/abcd/ef1234567890....txt
```

---

## Complete Flow Diagram

### Step-by-Step Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. VM Execution: op-program needs external data                │
│    └─ L1 blob, L2 state, etc.                                  │
└─────────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│ 2. VM → Host: Send Hint                                         │
│    hint = "l1-blob 0xabc...{index}{timestamp}"                 │
│    └─ Write to FD 4 (Hint Writer)                              │
└─────────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│ 3. Host: routeHints goroutine receives                          │
│    └─ Read from FD 3 (Hint Reader)                             │
│    └─ prefetcher.Hint("l1-blob 0xabc...")                      │
│        └─ Store in p.lastHint                                   │
└─────────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│ 4. VM → Host: Request Preimage                                  │
│    preimageOracle.Get(0xabc...)                                │
│    └─ Write key to FD 6 (Preimage Writer)                      │
└─────────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│ 5. Host: launchOracleServer goroutine receives                  │
│    └─ Read from FD 6 (Preimage Reader)                         │
│    └─ prefetcher.GetPreimage(0xabc...)                         │
│        ├─ kvStore.Get(0xabc...)                                │
│        │   └─ directory.go Get()                               │
│        │       └─ ErrNotFound                                   │
│        │                                                        │
│        ├─ prefetch(lastHint)                                    │
│        │   └─ Parse hint type: "l1-blob"                       │
│        │   └─ Fetch from Beacon API                            │
│        │   └─ kvStore.Put(0xabc..., blobData)                  │
│        │       └─ directory.go Put()                           │
│        │           ├─ Create temp file                         │
│        │           ├─ Write hex-encoded data                   │
│        │           ├─ Create directory structure               │
│        │           └─ Atomic rename to final path              │
│        │               💾 Saved to disk!                        │
│        │                                                        │
│        └─ kvStore.Get(0xabc...)                                │
│            └─ ✅ Found!                                         │
└─────────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│ 6. Host → VM: Send Preimage Data                               │
│    └─ Write data to FD 5 (Preimage Writer)                     │
└─────────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│ 7. VM: Receive Preimage Data                                    │
│    └─ Read from FD 5 (Preimage Reader)                         │
│    └─ Continue trace execution                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Key Connection Points

**Location**: `op-program/host/common/common.go:196-206`

```go
if prefetch != nil {
    // Use prefetcher for fetching
    getPreimage = func(key common.Hash) ([]byte, error) {
        return prefetch.GetPreimage(ctx, key)
    }
    hinter = prefetch.Hint
} else {
    // Offline mode: use kvStore directly
    getPreimage = kv.Get
    hinter = func(hint string) error { return nil }
}
```

This is the **critical connection** that links:
- VM's preimage requests (via FD 6)
- Host's Prefetcher
- Disk storage (directory.go)

### Server Goroutines

**Location**: `op-program/host/common/common.go:238-239`

```go
// Start two goroutines
serverDone = launchOracleServer(logger, preimageChannel, preimageGetter)
hinterDone = routeHints(logger, hintChannel, hinter)
```

These goroutines continuously process:
1. **launchOracleServer**: Preimage requests from VM
2. **routeHints**: Hint messages from VM

---

## Summary

### Key Takeaways

1. **Separation of Concerns**
   - VM: Executes trace, sends hints/requests
   - Host: Fetches data, manages storage

2. **Communication via Pipes**
   - 4 file descriptors for bidirectional communication
   - Asynchronous processing with goroutines

3. **Two Types of Prestate**
   - Absolute: VM initialization (prestate-mt64.bin.gz)
   - L2 Output Root: Logical starting point

4. **Anchoring Strategy**
   - Each game proves fixed block range
   - Prevents unbounded growth of proof time

5. **Storage Strategy**
   - Disk-backed key-value store
   - Directory structure for organization
   - Hex-encoded data in text files
   - Atomic writes for consistency

6. **Hint-Driven Prefetching**
   - VM sends hints before requesting data
   - Host prefetches based on hints
   - Lazy loading on actual request

### File References

| Component | File Path |
|-----------|-----------|
| Preimage Oracle | `op-program/host/common/common.go` |
| Prefetcher | `op-program/host/prefetcher/prefetcher.go` |
| Disk Storage | `op-program/host/kvstore/directory.go` |
| L1 Hints | `op-program/client/l1/hints.go` |
| L2 Hints | `op-program/client/l2/hints.go` |
| Game Types | `op-challenger/game/fault/types/types.go` |
| VM Registration | `op-challenger/game/fault/register.go` |
| VM Executor | `op-challenger/game/fault/trace/vm/executor.go` |

---

## Debugging Tips

### Logging Points

1. **Hint Reception**
   ```
   Host log: "Kona-Host -> Host: Hint request"
   Location: common.go:211
   ```

2. **Preimage Request**
   ```
   Host log: "Kona-Host -> Host: Preimage request"
   Location: common.go:224
   ```

3. **Disk Write**
   ```
   Host log: "💾 Saving preimage to disk"
   Location: directory.go:42
   ```

4. **Disk Read**
   ```
   Host log: (Check for ErrNotFound)
   Location: directory.go:72-73
   ```

### Common Issues

1. **Preimage Not Found**
   - Check if hint was sent before request
   - Verify datadir path exists
   - Check file permissions

2. **VM Hangs**
   - Check if preimage server goroutines are running
   - Verify FD connections are open
   - Check for deadlocks in prefetcher

3. **Wrong VM Type**
   - Verify GameType matches RegisterTask
   - Check VmBin path in config
   - Verify absolute prestate hash
