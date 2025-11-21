# Optimism op-program VM 통신 및 바이너리 선택 분석

## 목차
1. [VM 아키텍처 개요](#vm-아키텍처-개요)
2. [GameType과 VM 매핑](#gametype과-vm-매핑)
3. [바이너리 선택 메커니즘](#바이너리-선택-메커니즘)
4. [Client-Host 통신 구조](#client-host-통신-구조)
5. [Preimage Oracle 시스템](#preimage-oracle-시스템)
6. [Blob 데이터 처리](#blob-데이터-처리)
7. [트러블슈팅 가이드](#트러블슈팅-가이드)

---

## VM 아키텍처 개요

Optimism의 Fault Proof 시스템은 다음 VM들을 지원합니다:

### VM 종류 및 GameType 매핑

```go
// op-e2e/e2eutils/disputegame/helper.go:47-54
const (
    cannonGameType            uint32 = 0  // MIPS (32-bit)
    permissionedGameType      uint32 = 1  // MIPS (permissioned)
    asteriscGameType          uint32 = 2  // RISC-V 64-bit
    asteriscKonaGameType      uint32 = 3  // RISC-V 64-bit (Kona)
    superCannonGameType       uint32 = 4  // Super Cannon
    superPermissionedGameType uint32 = 5  // Super Cannon (permissioned)
    alphabetGameType          uint32 = 255 // Alphabet (테스트용)
)
```

### VM별 특징

| VM | GameType | 아키텍처 | op-program 바이너리 | 용도 |
|---|---|---|---|---|
| **Cannon** | 0 | MIPS 32-bit | `op-program-client.elf` | 프로덕션 (기존) |
| **Asterisc** | 2 | RISC-V 64-bit | `op-program-client-riscv.elf` | 프로덕션 (신규) |
| **Asterisc Kona** | 3 | RISC-V 64-bit | `op-program-client-riscv.elf` | Kona 클라이언트 |

---

## GameType과 VM 매핑

### 1. 게임 생성 시 GameType 지정

테스트에서 게임을 생성할 때 GameType이 결정됩니다:

```go
// op-e2e/e2eutils/disputegame/helper.go:198-199
func (h *FactoryHelper) StartOutputAsteriscGame(ctx context.Context, l2Node string,
    l2BlockNumber uint64, rootClaim common.Hash, opts ...GameOpt) *OutputCannonGameHelper {
    return h.startOutputCannonGameOfType(ctx, l2Node, l2BlockNumber, rootClaim, asteriscGameType, opts...)
}
```

### 2. VM 옵션 자동 선택

GameType에 따라 올바른 VM이 자동으로 선택됩니다:

```go
// op-e2e/e2eutils/disputegame/helper.go:253-263
// Determine the appropriate VM option based on game type
var vmOption challenger.Option
switch gameType {
case asteriscGameType: // GameType 2
    vmOption = challenger.WithAsterisc(h.T, h.System)
case asteriscKonaGameType: // GameType 3
    vmOption = challenger.WithAsteriscKona(h.T, h.System)
default: // Cannon or others
    vmOption = challenger.WithCannon(h.T, h.System)
}

return NewOutputCannonGameHelperWithOptions(h.T, h.Client, h.Opts, h.PrivKey,
    game, h.FactoryAddr, createdEvent.DisputeProxy, provider, h.System, vmOption)
```

**핵심**: GameType을 통해 VM이 결정되므로, 테스트 실행 시 올바른 GameType의 게임을 생성해야 합니다.

---

## 바이너리 선택 메커니즘

### 1. Challenger VM 설정

각 VM 옵션은 특정 바이너리 경로를 지정합니다:

#### Cannon VM 설정
```go
// op-e2e/e2eutils/challenger/helper.go (예상)
func WithCannon(t *testing.T, sys DisputeSystem) Option {
    return func(c *Config) {
        c.TraceTypes = []config.TraceType{types.TraceTypeCannon}
        c.CannonBin = sys.RollupCfg().CannonBinaryPath
        // 예: "cannon/bin-e2e/cannon"
        c.CannonServer = sys.RollupCfg().CannonServerPath
        // op-program: "op-program/bin-e2e/op-program-client.elf"
    }
}
```

#### Asterisc VM 설정
```go
// op-e2e/e2eutils/challenger/helper.go (예상)
func WithAsterisc(t *testing.T, sys DisputeSystem) Option {
    return func(c *Config) {
        c.TraceTypes = []config.TraceType{types.TraceTypeAsterisc}
        c.AsteriscBin = sys.RollupCfg().AsteriscBinaryPath
        // 예: "asterisc/bin-e2e/asterisc"
        c.AsteriscServer = sys.RollupCfg().AsteriscServerPath
        // op-program: "op-program/bin-e2e/op-program-client-riscv.elf"
    }
}
```

### 2. 바이너리 빌드 위치

빌드 스크립트(`build-binaries-for-challenger-e2e.sh`)는 다음 위치에 바이너리를 배치합니다:

```
optimism/
├── cannon/
│   └── bin-e2e/
│       └── cannon                          # Cannon VM (MIPS)
├── asterisc/
│   └── bin-e2e/
│       └── asterisc                        # Asterisc VM (RISC-V)
└── op-program/
    └── bin-e2e/
        ├── op-program-client.elf           # MIPS 32-bit (Cannon용)
        ├── op-program-client-riscv.elf     # RISC-V 64-bit (Asterisc용)
        └── prestate-asterisc.bin.gz        # Asterisc prestate
```

### 3. 바이너리 매칭 검증

**중요**: VM 바이너리와 op-program 바이너리는 반드시 동일한 코드베이스에서 함께 빌드되어야 합니다.

```bash
# 올바른 빌드 방법
/Users/zena/tokamak-projects/optimism/op-challenger/scripts/build-binaries-for-challenger-e2e.sh \
    --force --asterisc

# 이 스크립트는 다음을 보장합니다:
# 1. op-program-client-riscv.elf 빌드 (최신 코드)
# 2. 해당 바이너리로부터 prestate 생성
# 3. Asterisc VM 바이너리 빌드 (매칭되는 버전)
```

---

## Client-Host 통신 구조

### 1. 아키텍처 다이어그램

```
┌─────────────────────────────────────────────┐
│            Fault Dispute Game               │
│  (L1 Smart Contract - GameType 지정됨)      │
└──────────────────┬──────────────────────────┘
                   │
                   ├─ GameType 2 → Asterisc Helper 선택
                   │
┌──────────────────▼──────────────────────────┐
│         Challenger (Host Process)           │
│                                              │
│  ┌────────────────────────────────────────┐ │
│  │   Preimage Prefetcher                  │ │
│  │   - L1 데이터 가져오기                  │ │
│  │   - Blob 다운로드 (Beacon API)         │ │
│  │   - KV Store에 저장                    │ │
│  └────────────────────────────────────────┘ │
│                                              │
│  ┌────────────────────────────────────────┐ │
│  │   VM Runner                             │ │
│  │   - asterisc run --server ...          │ │
│  │   - RIPC socket 통신 (stdin/stdout)    │ │
│  └────────────────────────────────────────┘ │
└──────────────────┬──────────────────────────┘
                   │ RIPC Protocol
                   │ (Preimage 요청/응답)
                   │
┌──────────────────▼──────────────────────────┐
│      Asterisc VM (Guest Process)            │
│                                              │
│  ┌────────────────────────────────────────┐ │
│  │   op-program-client-riscv.elf          │ │
│  │   (RISC-V 64-bit ELF)                  │ │
│  │                                          │ │
│  │   ┌──────────────────────────────────┐ │ │
│  │   │  L1 Oracle (client/l1/oracle.go) │ │ │
│  │   │  - GetBlob() 호출                │ │ │
│  │   │  - ref.Time 전송 (타임스탬프)    │ │ │
│  │   └──────────────────────────────────┘ │ │
│  └────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

### 2. 통신 흐름: Blob Preimage 예시

#### Step 1: Client가 Blob 요청

```go
// op-program/client/l1/oracle.go:102-107
func (p *PreimageOracle) GetBlob(ref eth.L1BlockRef, blobHash eth.IndexedBlobHash) *eth.Blob {
    // Hint 생성: blob hash + index + timestamp
    blobReqMeta := make([]byte, 16)
    binary.BigEndian.PutUint64(blobReqMeta[0:8], blobHash.Index)
    binary.BigEndian.PutUint64(blobReqMeta[8:16], ref.Time)  // ⭐ ref.Time 사용

    p.hint.Hint(BlobHint(append(blobHash.Hash[:], blobReqMeta...)))
    // 형식: l1-blob <32 bytes hash><8 bytes index><8 bytes timestamp>
```

#### Step 2: Host가 Hint 수신 및 Blob 가져오기

```go
// op-program/host/prefetcher/prefetcher.go:319-334
case l1.HintL1Blob:
    blobVersionHash := common.Hash(hintBytes[:32])
    blobHashIndex := binary.BigEndian.Uint64(hintBytes[32:40])
    refTimestamp := binary.BigEndian.Uint64(hintBytes[40:48])  // ⭐ Client가 보낸 ref.Time

    indexedBlobHash := eth.IndexedBlobHash{
        Hash:  blobVersionHash,
        Index: blobHashIndex,
    }

    // Beacon API 호출 (타임스탬프로 slot 계산)
    sidecars, err := p.l1BlobFetcher.GetBlobSidecars(
        ctx,
        eth.L1BlockRef{Time: refTimestamp},  // ⭐ Client와 동일한 타임스탬프 사용
        []eth.IndexedBlobHash{indexedBlobHash}
    )
```

#### Step 3: Host가 Blob 데이터를 KV Store에 저장

```go
// op-program/host/prefetcher/prefetcher.go:340-359
// 1. KZG Commitment 저장
p.kvStore.Put(preimage.Sha256Key(blobVersionHash).PreimageKey(), sidecar.KZGCommitment[:])

// 2. 각 Field Element 저장 (4096개)
blobKey := make([]byte, 80)
copy(blobKey[:48], sidecar.KZGCommitment[:])
for i := 0; i < params.BlobTxFieldElementsPerBlob; i++ {
    rootOfUnity := l1.RootsOfUnity[i].Bytes()
    copy(blobKey[48:], rootOfUnity[:])
    blobKeyHash := crypto.Keccak256Hash(blobKey)

    // Key 저장
    p.kvStore.Put(preimage.Keccak256Key(blobKeyHash).PreimageKey(), blobKey)
    // Field element 저장
    p.kvStore.Put(preimage.BlobKey(blobKeyHash).PreimageKey(), sidecar.Blob[i<<5:(i+1)<<5])
}
```

#### Step 4: Client가 Preimage 요청 및 Blob 재구성

```go
// op-program/client/l1/oracle.go:109-123
commitment := p.oracle.Get(preimage.Sha256Key(blobHash.Hash))

// 4096 field elements로 blob 재구성
blob := eth.Blob{}
fieldElemKey := make([]byte, 80)
copy(fieldElemKey[:48], commitment)
for i := 0; i < params.BlobTxFieldElementsPerBlob; i++ {
    rootOfUnity := RootsOfUnity[i].Bytes()
    copy(fieldElemKey[48:], rootOfUnity[:])

    // Host가 저장한 데이터 요청
    fieldElement := p.oracle.Get(preimage.BlobKey(crypto.Keccak256(fieldElemKey)))

    copy(blob[i<<5:(i+1)<<5], fieldElement[:])
}

return &blob
```

### 3. 타임스탬프 동기화의 중요성

**핵심 원칙**: Client와 Host는 동일한 타임스탬프를 사용해야 합니다.

```
Client (oracle.go):
  ref.Time (예: 1234567890)
       ↓ Hint로 전송

Host (prefetcher.go):
  refTimestamp ← Hint에서 추출 (1234567890)
       ↓
  Beacon API 호출 (슬롯 변환: 1234567890 → slot 12345)
       ↓
  Blob 다운로드
       ↓
  Key 생성: hash(commitment + rootOfUnity)
       ↓
  KV Store 저장

Client (oracle.go):
  동일한 Key 생성: hash(commitment + rootOfUnity)
       ↓
  Preimage 요청
       ↓
  ✅ 매칭 성공!
```

**잘못된 경우**:
```
Client: ref.Time (1234567890)
Host:   actualTime (1234567999)  ← 다른 타임스탬프!
       ↓
Client Key: hash(commitment_at_1234567890 + rootOfUnity)
Host Key:   hash(commitment_at_1234567999 + rootOfUnity)
       ↓
❌ Key 불일치 → "did not find required key" 오류
```

---

## Preimage Oracle 시스템

### 1. Preimage Key 타입

```go
// op-preimage/key.go (예상)
const (
    LocalKeyType       byte = 1  // 로컬 데이터
    Keccak256KeyType   byte = 2  // Keccak256 해시
    GlobalGenericKeyType byte = 3  // 글로벌 generic
    Sha256KeyType      byte = 4  // SHA256 해시
    BlobKeyType        byte = 5  // Blob field element
    PrecompileKeyType  byte = 6  // Precompile 결과
)
```

### 2. Key 생성 규칙

```go
// Keccak256 Key
func Keccak256Key(hash common.Hash) Key {
    return Key{
        Type: Keccak256KeyType,
        Data: hash[:],
    }
}

// Blob Key
func BlobKey(hash common.Hash) Key {
    return Key{
        Type: BlobKeyType,
        Data: hash[:],
    }
}

// SHA256 Key
func Sha256Key(hash common.Hash) Key {
    return Key{
        Type: Sha256KeyType,
        Data: hash[:],
    }
}
```

### 3. Hint 타입

```go
// op-program/client/l1/hints.go (예상)
const (
    HintL1BlockHeader  = "l1-block-header"
    HintL1Transactions = "l1-transactions"
    HintL1Receipts     = "l1-receipts"
    HintL1Blob         = "l1-blob"  // Blob hint
    HintL1Precompile   = "l1-precompile-v2"
)

// Blob Hint 생성
func BlobHint(data []byte) string {
    return fmt.Sprintf("%s %x", HintL1Blob, data)
}
```

---

## Blob 데이터 처리

### 1. EIP-4844 Blob 구조

```
Blob (128 KB)
├── Field Element 0  (32 bytes)
├── Field Element 1  (32 bytes)
├── ...
└── Field Element 4095 (32 bytes)

총 4096 field elements × 32 bytes = 131,072 bytes
```

### 2. KZG Polynomial Commitment

Blob은 KZG polynomial로 표현되며, 특정 evaluation point에서 평가됩니다:

```go
// op-program/client/l1/oracle.go:138-184
var RootsOfUnity *[4096]fr.Element  // BLS12-381 field

// 4096개의 bit-reversed roots of unity
// Field element i는 polynomial을 ith root of unity에서 평가한 값
func generateRootsOfUnity() *[4096]fr.Element {
    rootsOfUnity := new([4096]fr.Element)

    // Primitive root of unity (order 2^32)
    var rootOfUnity fr.Element
    rootOfUnity.SetString("10238227357739495823651030575849232062558860180284477541189508159991286009131")

    // Generator for subgroup of order 4096
    logx := uint64(bits.TrailingZeros64(4096))  // log2(4096) = 12
    expo := uint64(1 << (32 - logx))            // 2^20

    var generator fr.Element
    generator.Exp(rootOfUnity, big.NewInt(int64(expo)))

    // Generate all 4096 roots
    current := fr.One()
    for i := uint64(0); i < 4096; i++ {
        rootsOfUnity[i] = current
        current.Mul(&current, &generator)
    }

    // Bit-reversal permutation
    for i := uint64(0); i < 4096; i++ {
        irev := bits.Reverse64(i) >> (64 - 12)
        if irev > i {
            rootsOfUnity[i], rootsOfUnity[irev] = rootsOfUnity[irev], rootsOfUnity[i]
        }
    }

    return rootsOfUnity
}
```

### 3. Blob Key 계산 과정

```go
// Field Element Key 계산
blobKey = commitment (48 bytes) + rootOfUnity (32 bytes) = 80 bytes
blobKeyHash = keccak256(blobKey)
key = preimage.BlobKey(blobKeyHash)

// 예시:
// commitment: 0x1234...abcd (48 bytes)
// rootOfUnity[0]: 0x0000...0001 (32 bytes)
// blobKey: 0x1234...abcd0000...0001 (80 bytes)
// blobKeyHash: keccak256(blobKey) = 0x5678...ef01 (32 bytes)
// Final key: [BlobKeyType | 0x5678...ef01]
```

---

## 트러블슈팅 가이드

### 문제 1: "did not find required key" 오류

#### 증상
```
Fetched pre-images for last hint but did not find required key
hint="l1-blob 0x012d4267c34201cfa1c83c2ed4353f3b71d4c97dfd664d54a9b0732ded189404..."
key=0x055bfa4089eea315463dea928c7491ccfe5c12feecc9138498f5083b9082335f
```

#### 원인
- **타임스탬프 불일치**: Client와 Host가 다른 타임스탬프를 사용
- **잘못된 코드 수정**: `oracle.go`에서 `ref.Time` 대신 `actualTimestamp` 사용

#### 해결 방법
```go
// ❌ 잘못된 코드
header := p.headerByBlockHash(ref.Hash)
actualTimestamp := header.Time
binary.BigEndian.PutUint64(blobReqMeta[8:16], actualTimestamp)

// ✅ 올바른 코드
binary.BigEndian.PutUint64(blobReqMeta[8:16], ref.Time)
```

#### 검증
```bash
# 1. oracle.go 확인
grep -A 3 "GetBlob.*L1BlockRef" op-program/client/l1/oracle.go

# 2. ref.Time 사용 확인
grep "ref.Time" op-program/client/l1/oracle.go

# 3. 재빌드
./op-challenger/scripts/build-binaries-for-challenger-e2e.sh --force --asterisc

# 4. 테스트
env OP_E2E_DISABLE_PARALLEL=true go test -v -timeout 40m \
  ./op-e2e/faultproofs -run "^TestOutputAsteriscStepWithPreimage_existingPreimage$/asterisc$"
```

### 문제 2: 잘못된 VM 바이너리 사용

#### 증상
- Opcode 오류 (예: Unknown opcode 0x70)
- VM이 실행되지 않음
- Prestate 불일치

#### 원인
- **바이너리 불일치**: Asterisc VM과 MIPS op-program 혼용
- **오래된 바이너리**: 코드 수정 후 재빌드 안 함

#### 해결 방법
```bash
# 1. 모든 바이너리 재빌드 (Asterisc)
cd /Users/zena/tokamak-projects/optimism
./op-challenger/scripts/build-binaries-for-challenger-e2e.sh --force --asterisc

# 2. 빌드된 바이너리 확인
ls -lh op-program/bin-e2e/op-program-client-riscv.elf
ls -lh asterisc/bin-e2e/asterisc
file op-program/bin-e2e/op-program-client-riscv.elf  # RISC-V 64-bit 확인

# 3. 테스트 실행 (GameType 2 = Asterisc)
env OP_E2E_DISABLE_PARALLEL=true go test -v -timeout 40m \
  ./op-e2e/faultproofs -run "^TestOutputAsteriscStepWithPreimage.*$/asterisc$"
```

### 문제 3: Prestate 파일 불일치

#### 증상
- "Invalid prestate" 오류
- VM이 초기 상태에서 실패

#### 원인
- 코드 수정 후 prestate 재생성 안 함
- 다른 프로젝트의 prestate 복사

#### 해결 방법
```bash
# Prestate는 반드시 현재 코드베이스에서 재생성해야 함
# 빌드 스크립트가 자동으로 처리:
./op-challenger/scripts/build-binaries-for-challenger-e2e.sh --force --asterisc

# Prestate 파일 위치:
# - op-program/bin-e2e/prestate-asterisc.bin.gz (E2E 테스트용)
# - asterisc/rvgo/bin/prestate.bin.gz (빌드 중간 산물)
```

### 문제 4: GameType과 VM 불일치

#### 증상
- 테스트가 잘못된 VM을 사용
- GameType 관련 오류

#### 원인
- 테스트 함수명과 실제 사용되는 VM이 불일치
- GameType을 명시적으로 지정하지 않음

#### 해결 방법
```go
// ✅ Asterisc 테스트 (GameType 2)
func TestOutputAsteriscStepWithPreimage_existingPreimage(t *testing.T) {
    // ...
    game := helper.StartOutputAsteriscGame(ctx, "sequencer", l2BlockNumber, ...)
    // ↑ asteriscGameType (2) 사용
}

// ✅ Cannon 테스트 (GameType 0)
func TestOutputCannonStepWithPreimage_existingPreimage(t *testing.T) {
    // ...
    game := helper.StartOutputCannonGame(ctx, "sequencer", l2BlockNumber, ...)
    // ↑ cannonGameType (0) 사용
}
```

### 문제 5: Binary Size 차이

#### 증상
- 바이너리 크기가 예상과 다름 (49MB vs 42MB)

#### 원인
- 다른 빌드 방법 사용
- MIPS 바이너리 포함 여부

#### 확인 방법
```bash
# RISC-V만 빌드
cd op-program
make op-program-client-riscv

# 크기 확인
ls -lh bin/op-program-client-riscv.elf

# 아키텍처 확인
file bin/op-program-client-riscv.elf
# 출력: ELF 64-bit LSB executable, RISC-V, version 1 (SYSV)...
```

---

## 빌드 프로세스 상세

### 전체 빌드 플로우

```bash
build-binaries-for-challenger-e2e.sh --force --asterisc
    ↓
[1] Clean
    ├─ op-program/bin 삭제
    └─ asterisc/rvgo/bin 정리
    ↓
[2] Build op-program RISC-V
    ├─ cd op-program
    └─ make op-program-client-riscv
        → bin/op-program-client-riscv.elf
    ↓
[3] Generate Cannon Prestate (Docker)
    ├─ docker buildx build
    ├─ mt64 prestate 생성
    └─ prestate-mt64.bin.gz 복사
    ↓
[4] Build Asterisc VM (Mac native)
    ├─ cd $ASTERISC_REPO
    └─ make build
        → asterisc/bin/asterisc
    ↓
[5] Generate Asterisc Prestate
    ├─ cd $ASTERISC_REPO
    ├─ make prestate MONOREPO_ROOT=...
    │   ├─ asterisc load-elf
    │   │   → rvgo/bin/prestate.bin.gz
    │   └─ asterisc run --proof-at '=0' --stop-at '=1'
    │       → rvgo/bin/prestate-proof.json
    └─ Copy to op-program/bin-e2e/prestate-asterisc.bin.gz
    ↓
[6] Copy binaries to E2E directories
    ├─ asterisc → optimism/asterisc/bin-e2e/
    └─ op-program-client-riscv.elf → op-program/bin-riscv/
    ↓
✅ 완료
```

### 주요 Make 타겟

```makefile
# op-program/Makefile

# RISC-V 바이너리만 빌드
op-program-client-riscv:
	env GO111MODULE=on GOOS=linux GOARCH=riscv64 \
	  go build -v -gcflags="all=-d=softfloat" \
	  -ldflags "$(PC_LDFLAGSSTRING)" \
	  -o ./bin/op-program-client-riscv.elf ./client/cmd/main.go

# 모든 아키텍처 빌드 (MIPS + RISC-V)
op-program: \
    op-program-host \
    op-program-client \
    op-program-client-mips
```

```makefile
# asterisc/Makefile

# Mac native 바이너리
build:
	cd rvgo && make build
	# → bin/asterisc

# Prestate 생성
prestate:
	make -C ./rvgo build
	rm -rf $(OP_PROGRAM_BIN_RISCV) $(OP_PROGRAM_BIN)
	make -C $(MONOREPO_ROOT)/op-program op-program-client-riscv
	mv $(OP_PROGRAM_BIN) $(OP_PROGRAM_BIN_RISCV)
	./rvgo/bin/asterisc load-elf \
	  --path $(OP_PROGRAM_BIN_RISCV)/op-program-client-riscv.elf \
	  --out ./rvgo/bin/prestate.bin.gz \
	  --meta ./rvgo/bin/meta.json
	./rvgo/bin/asterisc run \
	  --proof-at '=0' --stop-at '=1' \
	  --input ./rvgo/bin/prestate.bin.gz \
	  --meta ./rvgo/bin/meta.json \
	  --proof-fmt './rvgo/bin/%d.json' \
	  --output ""
```

---

## 테스트 실행 가이드

### Asterisc 테스트 실행

```bash
# 환경 설정
cd /Users/zena/tokamak-projects/optimism

# 병렬 실행 비활성화 (안정성)
export OP_E2E_DISABLE_PARALLEL=true

# 특정 테스트 실행
go test -v -timeout 40m ./op-e2e/faultproofs \
  -run "^TestOutputAsteriscStepWithPreimage_existingPreimage$/asterisc$"

# 모든 Asterisc 테스트 실행
go test -v -timeout 60m ./op-e2e/faultproofs \
  -run "TestOutputAsterisc"

# 특정 GameType만
go test -v -timeout 40m ./op-e2e/faultproofs \
  -run "^TestOutputAsteriscStepWithPreimage$/asterisc$"
```

### Cannon vs Asterisc 비교 테스트

```bash
# Cannon (GameType 0)
go test -v -timeout 40m ./op-e2e/faultproofs \
  -run "^TestOutputCannonStepWithPreimage_existingPreimage$/cannon$"

# Asterisc (GameType 2)
go test -v -timeout 40m ./op-e2e/faultproofs \
  -run "^TestOutputAsteriscStepWithPreimage_existingPreimage$/asterisc$"
```

### 로그 분석

```bash
# Blob 관련 로그 확인
grep -i "blob\|l1-blob" /tmp/test.log

# GameType 확인
grep "GameType\|game type" /tmp/test.log

# VM 실행 확인
grep "asterisc\|cannon" /tmp/test.log

# 에러 확인
grep -i "error\|fail\|panic" /tmp/test.log
```

---

## 요약

### 핵심 포인트

1. **GameType이 VM을 결정합니다**
   - GameType 2 = Asterisc (RISC-V)
   - GameType 0 = Cannon (MIPS)

2. **바이너리는 함께 빌드되어야 합니다**
   - VM 바이너리 (asterisc)
   - op-program 바이너리 (op-program-client-riscv.elf)
   - Prestate 파일

3. **타임스탬프는 동기화되어야 합니다**
   - Client: `ref.Time` 전송
   - Host: Hint에서 추출한 `refTimestamp` 사용
   - 불일치 시 "did not find required key" 오류

4. **빌드 스크립트를 사용하세요**
   ```bash
   ./op-challenger/scripts/build-binaries-for-challenger-e2e.sh --force --asterisc
   ```

5. **테스트 함수명과 VM 매칭 확인**
   - `TestOutputAsteriscXxx` → Asterisc VM 사용
   - `TestOutputCannonXxx` → Cannon VM 사용

### 체크리스트

빌드/테스트 전:
- [ ] oracle.go에서 `ref.Time` 사용 확인
- [ ] 빌드 스크립트로 전체 재빌드
- [ ] 바이너리 아키텍처 확인 (`file` 명령)
- [ ] Prestate 파일 생성 확인
- [ ] 테스트 함수명과 VM 타입 일치 확인
- [ ] GameType이 올바른지 확인

문제 발생 시:
- [ ] 빌드 로그 확인
- [ ] 테스트 로그에서 blob 에러 검색
- [ ] GameType 로그 확인
- [ ] VM 실행 로그 확인
- [ ] Key 불일치 오류 확인

---

*문서 생성일: 2025-11-22*
*코드베이스: /Users/zena/tokamak-projects/optimism*
