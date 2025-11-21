# Optimism Monorepo 코드 분석 문서

> 경로: `/Users/zena/tokamak-projects-work/asterisc/rvsol/lib/optimism`
> 분석 대상: Optimism OP Stack 핵심 컴포넌트
> 분석 일자: 2025-11-22

---

## 목차

1. [프로젝트 개요](#1-프로젝트-개요)
2. [디렉토리 구조](#2-디렉토리-구조)
3. [핵심 컴포넌트 분석](#3-핵심-컴포넌트-분석)
4. [op-program 심층 분석](#4-op-program-심층-분석)
5. [Fault Proof 시스템](#5-fault-proof-시스템)
6. [Preimage Oracle 시스템](#6-preimage-oracle-시스템)
7. [빌드 및 배포](#7-빌드-및-배포)

---

## 1. 프로젝트 개요

### 1.1 Optimism이란?

**Optimism**은 Ethereum의 확장성 문제를 해결하기 위한 Layer 2 솔루션입니다. OP Stack이라는 모듈식 소프트웨어 스택을 통해 scalable blockchain을 구축합니다.

**핵심 원칙:**
- **Impact = Profit**: 긍정적 영향을 준 개인에게 보상
- **Aggressively Open-Source**: 완전 오픈소스로 누구나 수정/확장 가능
- **Modular Design**: 각 컴포넌트가 독립적으로 작동

### 1.2 이 저장소의 목적

이 코드베이스는 **Asterisc 프로젝트의 RISC-V Fault Proof 시스템**에서 사용되는 Optimism 모노레포의 특정 버전입니다. 주로:
- **op-program**: RISC-V로 컴파일되어 Fault Proof VM에서 실행
- **op-challenger**: Dispute game 처리
- **op-service**: 공통 유틸리티 라이브러리

---

## 2. 디렉토리 구조

```
optimism/
├── cannon/              # MIPS 64-bit Fault Proof VM (Cannon)
├── op-program/          # ⭐ Fault Proof Program (L2 state 검증)
├── op-challenger/       # Dispute Game Challenge Agent
├── op-node/             # Rollup Consensus Layer Client
├── op-batcher/          # L2 Batch를 L1에 제출
├── op-proposer/         # L2 Output을 L1에 제출
├── op-service/          # 공통 유틸리티 코드베이스
├── op-preimage/         # Preimage Oracle Go Bindings
├── op-e2e/              # End-to-End 테스트
├── op-chain-ops/        # State Surgery 유틸리티
├── packages/            # Smart Contracts (contracts-bedrock)
└── specs/               # Bedrock 스펙 문서
```

---

## 3. 핵심 컴포넌트 분석

### 3.1 op-program (Fault Proof Program)

**목적:**
L1 입력에서 L2 출력을 검증하는 fault proof 프로그램. 분쟁 발생 시 온체인 VM에서 실행됩니다.

**주요 특징:**
- **Deterministic Execution**: 동일 입력 → 동일 출력 + 동일 실행 트레이스
- **Multi-Architecture Support**:
  - Native (x86_64 / ARM64)
  - MIPS64 (Cannon VM)
  - RISC-V 64-bit (Asterisc VM)

**디렉토리 구조:**
```
op-program/
├── client/          # VM 내에서 실행되는 클라이언트 코드
│   ├── l1/          # L1 데이터 처리 (oracle.go - Blob 처리 포함)
│   ├── l2/          # L2 데이터 처리
│   ├── cmd/         # Client 진입점
│   └── interopcmd/  # Interop 클라이언트
├── host/            # VM 외부에서 실행되는 호스트 코드
│   ├── prefetcher/  # Preimage 데이터 prefetch
│   ├── cmd/         # Host 진입점
│   └── kvstore/     # Key-Value 저장소
├── bin/             # 빌드된 바이너리
├── bin-riscv/       # RISC-V 전용 바이너리
└── verify/          # 검증 스크립트
```

### 3.2 op-challenger

**목적:**
Dispute game에서 잘못된 claim에 도전하는 에이전트.

**주요 기능:**
- Fault Dispute Game 모니터링
- 잘못된 주장 감지 및 반박
- Trace Provider 관리 (Cannon, Asterisc)

### 3.3 op-service

**공통 유틸리티 모듈:**
- `eth/`: Ethereum 타입 정의 (Block, Blob, Transaction 등)
- `sources/`: L1/L2 데이터 소스 (Beacon Client, L1 Client 등)
- `txmgr/`: Transaction 관리
- `client/`: RPC 클라이언트
- `metrics/`: 메트릭 수집

---

## 4. op-program 심층 분석

### 4.1 아키텍처 개요

```
┌─────────────────────────────────────────────────┐
│            Fault Proof VM (Asterisc)            │
│  ┌───────────────────────────────────────────┐  │
│  │       op-program-client-riscv.elf         │  │
│  │  ┌─────────────────────────────────────┐  │  │
│  │  │   L2 State Transition Verification  │  │  │
│  │  │  • Preimage Oracle (client/l1/*)    │  │  │
│  │  │  • Derivation (client/l2/*)         │  │  │
│  │  │  • Hint System                      │  │  │
│  │  └─────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
                      ↕ Preimage Requests
┌─────────────────────────────────────────────────┐
│         op-program-host (Native Binary)         │
│  ┌───────────────────────────────────────────┐  │
│  │            Prefetcher                     │  │
│  │  • L1 Block/Tx/Receipt Fetch             │  │
│  │  • Blob Sidecar Fetch (EIP-4844)         │  │
│  │  • L2 State/Code Fetch                   │  │
│  │  • KV Store Management                   │  │
│  └───────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
                      ↕ RPC Calls
┌─────────────────────────────────────────────────┐
│              L1/L2 Ethereum Nodes               │
└─────────────────────────────────────────────────┘
```

### 4.2 Client vs Host

| 구분 | Client | Host |
|------|--------|------|
| **실행 환경** | VM 내부 (RISC-V/MIPS) | Native (x86_64/ARM64) |
| **역할** | L2 상태 전환 검증 | Preimage 데이터 제공 |
| **주요 코드** | `client/` | `host/` |
| **바이너리** | `op-program-client-riscv.elf` | `op-program` |
| **입력** | Preimage Oracle | L1/L2 RPC |
| **출력** | L2 Output Root | Preimage Data |

### 4.3 핵심 파일 분석

#### 4.3.1 `client/l1/oracle.go`

**Preimage Oracle 구현:**

```go
type PreimageOracle struct {
    oracle preimage.Oracle  // Preimage 데이터 요청 인터페이스
    hint   preimage.Hinter  // Hint 전송 인터페이스
}
```

**주요 메서드:**

1. **`HeaderByBlockHash`**: L1 블록 헤더 가져오기
   ```go
   func (p *PreimageOracle) HeaderByBlockHash(blockHash common.Hash) eth.BlockInfo
   ```

2. **`GetBlob`**: EIP-4844 Blob 데이터 재구성
   ```go
   func (p *PreimageOracle) GetBlob(ref eth.L1BlockRef, blobHash eth.IndexedBlobHash) *eth.Blob
   ```
   - **중요 포인트**: `ref.Time`을 사용하여 Host와 동기화
   - Blob을 4096개의 Field Element로 재구성
   - KZG Commitment 검증

3. **`Precompile`**: EVM Precompile 호출 결과 가져오기
   ```go
   func (p *PreimageOracle) Precompile(address common.Address, input []byte, requiredGas uint64) ([]byte, bool)
   ```

#### 4.3.2 `host/prefetcher/prefetcher.go`

**Prefetcher 구현:**

```go
type Prefetcher struct {
    logger         log.Logger
    l1Fetcher      L1Source
    l1BlobFetcher  L1BlobSource
    l2Sources      hosttypes.L2Sources
    kvStore        kvstore.KV
}
```

**Hint 처리 흐름:**

```go
func (p *Prefetcher) Hint(hint string) error
    → parseHint(hint) // "l1-blob 0x..." 파싱
    → prefetch(ctx, hint) // Hint 타입별 처리
    → switch hintType:
        case l1.HintL1Blob:
            → GetBlobSidecars(ctx, eth.L1BlockRef{Time: refTimestamp}, ...)
            → Store blob field elements to kvStore
```

**Blob Preimage 저장 방식:**

```go
// Blob Commitment → SHA256 Key
preimage.Sha256Key(blobHash).PreimageKey()

// Field Element → Blob Key
// Key = keccak256(commitment || rootOfUnity[i])
blobKey = commitment[48] + rootOfUnity[32]
blobKeyHash = crypto.Keccak256Hash(blobKey)
preimage.BlobKey(blobKeyHash).PreimageKey()
```

#### 4.3.3 `host/cmd/main.go`

**Host 진입점:**

```go
func main() {
    args := os.Args
    if err := run(args, host.Main); err != nil {
        log.Crit("Application failed", "err", err)
    }
}
```

**설정 플래그:**
- `--l1`: L1 RPC URL
- `--l1.beacon`: L1 Beacon API URL
- `--l2`: L2 RPC URL
- `--datadir`: Preimage 데이터 저장 경로

---

## 5. Fault Proof 시스템

### 5.1 Fault Proof 프로세스

```
1. Proposer가 L2 Output을 L1에 제출
   ↓
2. Challenger가 의심스러운 Output 감지
   ↓
3. Dispute Game 시작 (FaultDisputeGame.sol)
   ↓
4. Bisection Protocol로 disagreement 위치 좁히기
   ↓
5. Single-step Verification
   - Challenger가 op-program을 VM에서 실행
   - Asterisc VM이 RISC-V 명령어 단위로 검증
   ↓
6. 승자 결정 및 Bond 분배
```

### 5.2 Prestate 생성

**Reproducible Prestate:**

Docker를 사용하여 재현 가능한 초기 상태 생성:

```bash
make reproducible-prestate
```

**생성 파일:**
- `prestate.bin.gz`: 압축된 초기 VM 상태
- `prestate-proof.json`: 초기 상태 해시 포함
- `meta.json`: 메타데이터

**Prestate Hash:**
- 스마트 컨트랙트에 배포되는 절대 초기 상태 해시
- 모든 Fault Proof 검증의 시작점

---

## 6. Preimage Oracle 시스템

### 6.1 Preimage 타입

| Type | Key Type | Description |
|------|----------|-------------|
| `Keccak256` | `0x01` | Block Header, Transaction, Receipt, State Node |
| `Sha256` | `0x02` | Blob KZG Commitment |
| `Blob` | `0x03` | Blob Field Element |
| `Precompile` | `0x04` | EVM Precompile 결과 |

### 6.2 Hint System

**Hint 타입:**

```go
const (
    HintL1BlockHeader   = "l1-block-header"
    HintL1Transactions  = "l1-transactions"
    HintL1Receipts      = "l1-receipts"
    HintL1Blob          = "l1-blob"
    HintL1Precompile    = "l1-precompile-v2"
)
```

**Hint 프로토콜:**

```
Client:  "l1-blob <blobHash(32)><index(8)><timestamp(8)>"
         ↓
Host:    1. Parse hint
         2. Fetch blob sidecar from Beacon API
         3. Store blob commitment (SHA256 key)
         4. Store 4096 field elements (Blob keys)
         ↓
Client:  oracle.Get(preimage.BlobKey(...))
```

### 6.3 Blob Preimage 처리 (EIP-4844)

**Client 측 (`client/l1/oracle.go:102-124`):**

```go
func (p *PreimageOracle) GetBlob(ref eth.L1BlockRef, blobHash eth.IndexedBlobHash) *eth.Blob {
    // 1. Hint 전송
    blobReqMeta := make([]byte, 16)
    binary.BigEndian.PutUint64(blobReqMeta[0:8], blobHash.Index)
    binary.BigEndian.PutUint64(blobReqMeta[8:16], ref.Time)  // ⭐ ref.Time 사용
    p.hint.Hint(BlobHint(append(blobHash.Hash[:], blobReqMeta...)))

    // 2. Commitment 가져오기
    commitment := p.oracle.Get(preimage.Sha256Key(blobHash.Hash))

    // 3. Blob 재구성 (4096 field elements)
    blob := eth.Blob{}
    for i := 0; i < params.BlobTxFieldElementsPerBlob; i++ {
        fieldElemKey := commitment[48] + RootsOfUnity[i][32]
        fieldElement := p.oracle.Get(preimage.BlobKey(crypto.Keccak256(fieldElemKey)))
        copy(blob[i<<5:(i+1)<<5], fieldElement[:])
    }
    return &blob
}
```

**Host 측 (`host/prefetcher/prefetcher.go:319-360`):**

```go
case l1.HintL1Blob:
    // 1. Hint 파싱
    blobVersionHash := common.Hash(hintBytes[:32])
    blobHashIndex := binary.BigEndian.Uint64(hintBytes[32:40])
    refTimestamp := binary.BigEndian.Uint64(hintBytes[40:48])  // ⭐ Client의 ref.Time

    // 2. Blob Sidecar 가져오기
    sidecars, err := p.l1BlobFetcher.GetBlobSidecars(
        ctx,
        eth.L1BlockRef{Time: refTimestamp},  // ⭐ 동일한 timestamp 사용
        []eth.IndexedBlobHash{indexedBlobHash},
    )

    // 3. Commitment 저장
    p.kvStore.Put(preimage.Sha256Key(blobVersionHash).PreimageKey(), sidecar.KZGCommitment[:])

    // 4. Field Elements 저장
    for i := 0; i < params.BlobTxFieldElementsPerBlob; i++ {
        rootOfUnity := l1.RootsOfUnity[i].Bytes()
        blobKey := commitment[48] + rootOfUnity[32]
        blobKeyHash := crypto.Keccak256Hash(blobKey)

        // Field element 저장
        p.kvStore.Put(
            preimage.BlobKey(blobKeyHash).PreimageKey(),
            sidecar.Blob[i<<5:(i+1)<<5],
        )
    }
```

**⚠️ 중요 포인트:**

- **Timestamp 동기화**: Client와 Host가 동일한 `ref.Time` 사용 필수
- **Beacon API**: `GetBlobSidecars`는 timestamp를 slot으로 변환하여 조회
- **Field Element Evaluation**: KZG polynomial을 Roots of Unity에서 평가

---

## 7. 빌드 및 배포

### 7.1 빌드 명령어

```bash
# Native 바이너리 (Host + Client)
make op-program

# RISC-V 바이너리 (Asterisc용)
make op-program-client-riscv

# MIPS64 바이너리 (Cannon용)
# op-program Makefile에 포함

# Reproducible Prestate
make reproducible-prestate
```

### 7.2 빌드 출력

**Native Build:**
- `bin/op-program`: Host 바이너리
- `bin/op-program-client`: Native Client 바이너리

**RISC-V Build:**
- `bin-riscv/op-program-client-riscv.elf`: RISC-V ELF 바이너리
- **Compiler Flags**: `-gcflags="all=-d=softfloat"` (소프트웨어 부동소수점)

**MIPS64 Build:**
- `bin/op-program-client64.elf`: MIPS64 ELF 바이너리

### 7.3 Asterisc Prestate 생성

```bash
# Asterisc 프로젝트에서
make prestate MONOREPO_ROOT=/path/to/optimism OP_PROGRAM_PATH=/path/to/op-program-client-riscv.elf

# 출력
# - rvgo/bin/prestate.bin.gz
# - rvgo/bin/prestate-proof.json
```

---

## 8. 핵심 데이터 흐름

### 8.1 L2 Output Verification Flow

```
1. L1 Block Header Fetch
   Client: HeaderByBlockHash(blockHash)
   → Hint: "l1-block-header <blockHash>"
   → Host: Fetch header from L1 RPC
   → Store: Keccak256(header RLP)

2. L1 Transactions Fetch
   Client: TransactionsByBlockHash(blockHash)
   → Hint: "l1-transactions <blockHash>"
   → Host: Fetch transactions, build MPT
   → Store: Keccak256(MPT nodes)

3. Blob Fetch (if blob batches exist)
   Client: GetBlob(ref, blobHash)
   → Hint: "l1-blob <blobHash><index><timestamp>"
   → Host: Fetch blob from Beacon API
   → Store: SHA256(commitment), BlobKey(field elements)

4. L2 State Derivation
   Client: Process batches, apply transactions
   → Fetch L2 state nodes, code, receipts
   → Compute L2 output root

5. Output Verification
   Compare computed output vs claimed output
```

### 8.2 Preimage Key 계산 흐름

```go
// Block Header
headerRLP := rlp.Encode(header)
key := preimage.Keccak256Key(crypto.Keccak256Hash(headerRLP)).PreimageKey()

// Blob Commitment
commitment := sidecar.KZGCommitment[48]
key := preimage.Sha256Key(crypto.SHA256Hash(blobHash)).PreimageKey()

// Blob Field Element
fieldElemKey := commitment[48] + rootOfUnity[32]
blobKeyHash := crypto.Keccak256Hash(fieldElemKey)
key := preimage.BlobKey(blobKeyHash).PreimageKey()

// Precompile Result
hintBytes := address[20] + requiredGas[8] + input
inputHash := crypto.Keccak256Hash(hintBytes)
key := preimage.PrecompileKey(inputHash).PreimageKey()
```

---

## 9. 테스트

### 9.1 Unit Tests

```bash
cd op-program
make test
```

### 9.2 E2E Tests

```bash
cd op-e2e
# Asterisc with existing preimage
go test -v ./faultproofs -run TestOutputAsteriscStepWithPreimage_existingPreimage
```

### 9.3 주요 테스트 케이스

| 테스트 | 설명 |
|--------|------|
| `TestOutputAsteriscStepWithPreimage_existingPreimage` | Blob batch가 있는 경우 Asterisc Fault Proof 테스트 |
| `TestOutputCannonStepWithPreimage_existingPreimage` | Blob batch가 있는 경우 Cannon Fault Proof 테스트 |
| `TestOutputAsteriscStepWithPreimage` | 일반 Asterisc Fault Proof 테스트 |

---

## 10. 문제 해결

### 10.1 Blob Preimage 에러

**증상:**
```
Fetched pre-images for last hint but did not find required key
```

**원인:**
- Client와 Host의 timestamp 불일치
- `actualTimestamp` 사용 대신 `ref.Time` 사용해야 함

**해결:**
```go
// ❌ 잘못된 코드
header := p.headerByBlockHash(ref.Hash)
actualTimestamp := header.Time
binary.BigEndian.PutUint64(blobReqMeta[8:16], actualTimestamp)

// ✅ 올바른 코드
binary.BigEndian.PutUint64(blobReqMeta[8:16], ref.Time)
```

### 10.2 Binary Size 차이

**증상:**
- 49MB vs 42MB 바이너리 크기 차이

**원인:**
- `make op-program`이 MIPS 바이너리도 함께 빌드
- RISC-V 전용 빌드 필요

**해결:**
```bash
# RISC-V만 빌드
make op-program-client-riscv
```

---

## 11. 참고 자료

### 11.1 공식 문서

- [Optimism Docs](https://docs.optimism.io)
- [OP Stack Specs](https://github.com/ethereum-optimism/specs)
- [Fault Proof Specs](https://specs.optimism.io/fault-proof/index.html)

### 11.2 관련 EIP

- [EIP-4844](https://eips.ethereum.org/EIPS/eip-4844): Proto-Danksharding (Blob Transactions)
- [EIP-4788](https://eips.ethereum.org/EIPS/eip-4788): Beacon Block Root in EVM

### 11.3 주요 파일 경로

```
op-program/
├── client/l1/oracle.go              # L1 Preimage Oracle (Blob 처리)
├── client/l2/oracle.go              # L2 Preimage Oracle
├── host/prefetcher/prefetcher.go    # Preimage Prefetcher (Blob Fetch)
├── host/cmd/main.go                 # Host 진입점
├── client/cmd/main.go               # Client 진입점
└── Dockerfile.repro                 # Reproducible Build

op-service/
├── sources/l1_beacon_client.go      # Beacon API Client (Blob Sidecar Fetch)
├── eth/blobs_api.go                 # Blob API 타입 정의
└── client/                          # RPC Client

op-challenger/
├── game/fault/                      # Fault Dispute Game Logic
└── cmd/main.go                      # Challenger 진입점
```

---

## 12. 요약

이 Optimism 코드베이스는 **Fault Proof 기반 L2 Rollup**의 핵심 구현입니다. 특히:

1. **op-program**은 L2 state transition을 검증하는 deterministic program
2. **Preimage Oracle**을 통해 L1/L2 데이터를 안전하게 VM에 제공
3. **EIP-4844 Blob** 지원으로 대용량 배치 데이터 처리
4. **Multi-VM Support** (MIPS, RISC-V)로 다양한 Fault Proof VM 지원
5. **Reproducible Build**로 초기 상태 검증 가능

**Asterisc 프로젝트**는 이 코드를 RISC-V로 컴파일하여 RISC-V 기반 Fault Proof 시스템을 구현합니다.

---

**작성자**: Claude
**최종 수정**: 2025-11-22
