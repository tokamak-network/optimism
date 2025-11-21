# Op-Program 두 프로젝트 간 코드 차이 비교

## 비교 대상

1. **Optimism 공식**: `/Users/zena/tokamak-projects/optimism/op-program`
2. **Asterisc 프로젝트**: `/Users/zena/tokamak-projects-work/asterisc/rvsol/lib/optimism/op-program`

---

## 1. 주요 차이점 요약

### 1.1 디렉토리 구조 차이

| 항목 | Optimism 공식 | Asterisc 프로젝트 |
|------|--------------|------------------|
| **host/common/** | ✅ 있음 | ❌ 없음 |
| **host/prefetcher/reexec.go** | ✅ 있음 | ❌ 없음 |
| **host/prefetcher/l2_sources.go** | ✅ 있음 | ❌ 없음 |
| **host/subcmds/** | ✅ 있음 | ❌ 없음 |
| **client/interop/** | ✅ 있음 | ❌ 없음 |

**결론**: Asterisc 버전이 더 단순화되어 있음 (일부 기능 제거)

---

## 2. 파일별 상세 차이점

### 2.1 `host/kvstore/directory.go`

#### Optimism 공식 버전
```go
func (d *directoryKV) Get(k common.Hash) ([]byte, error) {
	d.RLock()
	defer d.RUnlock()

	targetFile := d.pathKey(k)  // 변수 사용

	f, err := os.OpenFile(targetFile, os.O_RDONLY, filePermission)
	// ...
	dat, err := io.ReadAll(f)
	// ...
	decoded, err := hex.DecodeString(string(dat))  // 변수 사용
	return decoded, err
}
```

#### Asterisc 버전
```go
func (d *directoryKV) Get(k common.Hash) ([]byte, error) {
	d.RLock()
	defer d.RUnlock()
	f, err := os.OpenFile(d.pathKey(k), os.O_RDONLY, filePermission)  // 인라인
	// ...
	dat, err := io.ReadAll(f)
	// ...
	return hex.DecodeString(string(dat))  // 직접 반환
}
```

**차이점**:
- 코드 스타일만 다름 (변수 제거, 인라인 사용)
- **핵심 로직은 동일**: `io.ReadAll()` + `hex.DecodeString(string(dat))`
- **문제점도 동일**: 메모리 비효율성

### 2.2 `host/kvstore/file.go`

**차이점**: 없음 (완전히 동일)

### 2.3 `host/kvstore/local.go`

**차이점**: 파일 내용이 다름 (상세 내용 확인 필요)

### 2.4 `host/kvstore/pebble.go`

**차이점**: 파일 내용이 다름 (상세 내용 확인 필요)

---

## 3. `host/prefetcher/prefetcher.go` - 큰 차이

### 3.1 Import 차이

#### Optimism 공식 버전
```go
import (
	"encoding/json"
	clientTypes "github.com/ethereum-optimism/optimism/op-program/client/interop/types"
	hostcommon "github.com/ethereum-optimism/optimism/op-program/host/common"
	hosttypes "github.com/ethereum-optimism/optimism/op-program/host/types"
	// ...
)
```

#### Asterisc 버전
```go
import (
	// encoding/json 제거
	// client/interop/types 제거
	// host/common 제거
	// host/types 제거
	// ...
)
```

### 3.2 Prefetcher 구조체 차이

#### Optimism 공식 버전
```go
type Prefetcher struct {
	logger         log.Logger
	l1Fetcher      L1Source
	l1BlobFetcher  L1BlobSource
	defaultChainID eth.ChainID
	l2Sources      hosttypes.L2Sources  // 복잡한 타입
	lastHint       string
	lastBulkHint   string
	kvStore        kvstore.KV
	l2Head         common.Hash
	executor       ProgramExecutor      // Native execution 지원
	agreedPrestate []byte               // Interop 지원
}
```

#### Asterisc 버전
```go
type Prefetcher struct {
	logger        log.Logger
	l1Fetcher     L1Source
	l1BlobFetcher L1BlobSource
	l2Fetcher     L2Source              // 단순한 인터페이스
	lastHint      string
	kvStore       kvstore.KV
	// lastBulkHint 제거
	// executor 제거
	// agreedPrestate 제거
}
```

**차이점**:
- Asterisc 버전이 **훨씬 단순함**
- Interop 기능 제거
- Native block execution 제거
- Multi-chain 지원 제거

### 3.3 NewPrefetcher 함수 차이

#### Optimism 공식 버전
```go
func NewPrefetcher(
	logger log.Logger,
	l1Fetcher L1Source,
	l1BlobFetcher L1BlobSource,
	defaultChainID eth.ChainID,
	l2Sources hosttypes.L2Sources,
	kvStore kvstore.KV,
	executor ProgramExecutor,
	l2Head common.Hash,
	agreedPrestate []byte,
) *Prefetcher {
	// 복잡한 초기화
}
```

#### Asterisc 버전
```go
func NewPrefetcher(
	logger log.Logger,
	l1Fetcher L1Source,
	l1BlobFetcher L1BlobSource,
	l2Fetcher L2Source,
	kvStore kvstore.KV,
) *Prefetcher {
	// 단순한 초기화
}
```

### 3.4 Accelerated Precompiles 차이

#### Optimism 공식 버전
```go
var acceleratedPrecompiles = []common.Address{
	common.BytesToAddress([]byte{0x1}),  // ecrecover
	common.BytesToAddress([]byte{0x8}),  // bn256Pairing
	common.BytesToAddress([]byte{0x0a}), // KZG Point Evaluation
	common.BytesToAddress([]byte{0x0b}), // BLS12-381 G1 add
	common.BytesToAddress([]byte{0x0c}), // BLS12-381 G1 multi-scalar-multiply
	common.BytesToAddress([]byte{0x0d}), // BLS12-381 G2 add
	common.BytesToAddress([]byte{0x0e}), // BLS12-381 G2 multi-scalar-multiply
	common.BytesToAddress([]byte{0x0f}), // BLS12-381 pairing check
	common.BytesToAddress([]byte{0x10}), // BLS12-381 hash-to-g1
	common.BytesToAddress([]byte{0x11}), // BLS12-381 hash-to-g2
}
```

#### Asterisc 버전
```go
var acceleratedPrecompiles = []common.Address{
	common.BytesToAddress([]byte{0x1}),  // ecrecover
	common.BytesToAddress([]byte{0x8}),  // bn256Pairing
	common.BytesToAddress([]byte{0x0a}), // KZG Point Evaluation
	// BLS12-381 precompiles 제거
}
```

**차이점**: Asterisc 버전은 BLS12-381 precompiles 지원 없음

### 3.5 Hint 처리 차이

#### Optimism 공식 버전
```go
func (p *Prefetcher) Hint(hint string) error {
	// ...
	if hintType == l2.HintL2BlockData {
		return p.prefetch(context.Background(), hint)
	}
	// bulk hint 지원
	if err == nil && (hintType == l2.HintL2AccountProof || hintType == l2.HintL2PayloadWitness) {
		p.lastBulkHint = hint
	} else {
		p.lastHint = hint
	}
	return nil
}
```

#### Asterisc 버전
```go
func (p *Prefetcher) Hint(hint string) error {
	// ...
	// bulk hint 지원 없음
	p.lastHint = hint
	return nil
}
```

### 3.6 GetPreimage 차이

#### Optimism 공식 버전
```go
func (p *Prefetcher) GetPreimage(ctx context.Context, key common.Hash) ([]byte, error) {
	pre, err := p.kvStore.Get(key)
	// 복잡한 retry 로직
	for errors.Is(err, kvstore.ErrNotFound) && p.lastHint != "" {
		hint := p.lastHint
		if err := p.prefetch(ctx, hint); err != nil && !errors.Is(err, hostcommon.ErrExperimentalPrefetchFailed) {
			return nil, fmt.Errorf("prefetch failed: %w", err)
		}
		pre, err = p.kvStore.Get(key)
		// ...
	}
	return pre, err
}
```

#### Asterisc 버전
```go
func (p *Prefetcher) GetPreimage(ctx context.Context, key common.Hash) ([]byte, error) {
	pre, err := p.kvStore.Get(key)
	// 단순한 retry 로직
	for errors.Is(err, kvstore.ErrNotFound) && p.lastHint != "" {
		hint := p.lastHint
		if err := p.prefetch(ctx, hint); err != nil {
			return nil, fmt.Errorf("prefetch failed: %w", err)
		}
		pre, err = p.kvStore.Get(key)
		// ...
	}
	return pre, err
}
```

**차이점**: Experimental prefetch 실패 처리 제거

---

## 4. 누락된 기능 (Asterisc 버전)

### 4.1 Interop 기능
- `client/interop/` 폴더 없음
- `agreedPrestate` 지원 없음
- Multi-chain 지원 없음

### 4.2 Native Block Execution
- `prefetcher/reexec.go` 없음
- `ProgramExecutor` 인터페이스 없음
- `HintL2BlockData` 처리 없음

### 4.3 Advanced Features
- Bulk hint 지원 없음 (`lastBulkHint` 제거)
- BLS12-381 precompiles 지원 없음
- Experimental prefetch 실패 처리 없음

### 4.4 Common 모듈
- `host/common/` 폴더 없음
- `host/common/common.go`의 `FaultProofProgram` 함수 없음
- `host/common/l2_sources.go` 없음

---

## 5. 핵심 차이점 요약

| 항목 | Optimism 공식 | Asterisc 버전 |
|------|--------------|--------------|
| **복잡도** | 높음 (모든 기능 포함) | 낮음 (핵심 기능만) |
| **Interop 지원** | ✅ 있음 | ❌ 없음 |
| **Native Execution** | ✅ 있음 | ❌ 없음 |
| **Multi-chain** | ✅ 있음 | ❌ 없음 |
| **BLS12-381** | ✅ 있음 | ❌ 없음 |
| **KV Store Get()** | 동일한 문제점 | 동일한 문제점 |
| **코드 스타일** | 변수 사용 | 인라인 사용 |

---

## 6. 결론

### 6.1 공통 문제점
- **두 버전 모두 `directory.go`의 `Get()` 메서드에 동일한 문제점 존재**
  - `io.ReadAll()` 사용
  - `hex.DecodeString(string(dat))` 사용
  - 메모리 비효율성

### 6.2 주요 차이
- **Asterisc 버전은 단순화된 버전**
  - Interop 기능 제거
  - Native execution 제거
  - Multi-chain 지원 제거
  - BLS12-381 precompiles 제거

### 6.3 권장 사항
1. **KV Store 문제는 두 버전 모두 수정 필요**
2. **Asterisc 버전은 단순화되어 있어 디버깅이 더 쉬울 수 있음**
3. **하지만 일부 기능이 없어서 호환성 문제 가능**

---

## 날짜

작성: 2025-01-21
목적: Optimism 공식 op-program과 Asterisc 프로젝트의 op-program 코드 차이 분석

