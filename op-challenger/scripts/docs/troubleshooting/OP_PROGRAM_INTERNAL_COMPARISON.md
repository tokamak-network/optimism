# Op-Program 내부 코드 비교 분석

## 비교 대상

1. **KV Store 구현들**: `mem.go`, `directory.go`, `file.go`, `pebble.go`
2. **Client vs Host 구조**

---

## 1. KV Store 구현 비교

### 1.1 전체 비교표

| 구현 | 파일 | 저장 방식 | Get() 메서드 | 장점 | 단점 | 사용 시나리오 |
|------|------|----------|-------------|------|------|-------------|
| **MemKV** | `mem.go` | 메모리 (Go map) | 직접 map 접근 | 빠름, 파일 I/O 없음 | 메모리 제한 | 테스트, 짧은 실행 |
| **DirectoryKV** | `directory.go` | 디스크 (서브디렉토리) | `io.ReadAll` + `hex.DecodeString` | 많은 파일 처리 효율적 | 파일 I/O, 메모리 복사 | 많은 preimage |
| **FileKV** | `file.go` | 디스크 (단일 디렉토리) | `io.ReadAll` + `hex.DecodeString` | 단순한 구조 | 파일 I/O, 메모리 복사 | 적은 preimage |
| **PebbleKV** | `pebble.go` | 디스크 (PebbleDB) | `db.Get()` + `copy()` | 최적화된 DB, 캐싱 | 의존성 필요 | 프로덕션 |

### 1.2 Get() 메서드 구현 비교

#### MemKV (메모리)
```go
func (m *MemKV) Get(k common.Hash) ([]byte, error) {
	m.RLock()
	defer m.RUnlock()
	v, ok := m.m[k]
	if !ok {
		return nil, ErrNotFound
	}
	return slices.Clone(v), nil  // ✅ 메모리 직접 접근, 빠름
}
```
**특징**: 파일 I/O 없음, 메모리 직접 접근, 가장 빠름

#### DirectoryKV / FileKV (디스크 파일)
```go
func (d *directoryKV) Get(k common.Hash) ([]byte, error) {
	// ...
	dat, err := io.ReadAll(f)  // ⚠️ 전체 파일을 메모리에 로드
	decoded, err := hex.DecodeString(string(dat))  // ⚠️ []byte -> string 변환
	return decoded, err
}
```
**특징**:
- 파일 I/O 필요
- `io.ReadAll()`: 전체 파일을 메모리에 로드
- `string(dat)` 변환: 불필요한 메모리 복사
- **동일한 문제점 공유**

#### PebbleKV (PebbleDB)
```go
func (d *pebbleKV) Get(k common.Hash) ([]byte, error) {
	d.RLock()
	defer d.RUnlock()

	dat, closer, err := d.db.Get(k.Bytes())  // ✅ DB에서 직접 읽기
	if err != nil {
		if errors.Is(err, pebble.ErrNotFound) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	defer closer.Close()

	ret := make([]byte, len(dat))
	copy(ret, dat)  // ✅ 효율적인 복사
	return ret, nil
}
```
**특징**:
- 최적화된 DB 엔진 사용
- 캐싱 지원 (32MB)
- 압축 지원 (Snappy)
- **가장 효율적인 디스크 저장소**

### 1.3 선택 로직

**위치**: `op-program/host/common/common.go:174-186`

```go
if cfg.DataDir == "" {
	logger.Info("Using in-memory storage")
	kv = kvstore.NewMemKV()  // ✅ 메모리 사용
} else {
	// ...
	store, err := kvstore.NewDiskKV(logger, cfg.DataDir, cfg.DataFormat)
	// NewDiskKV는 format.go에서 format에 따라 선택:
	// - DataFormatFile → newFileKV()
	// - DataFormatDirectory → newDirectoryKV()
	// - DataFormatPebble → newPebbleKV()
	kv = store
}
```

---

## 2. Client vs Host 구조 비교

### 2.1 역할 분리

| 컴포넌트 | 위치 | 역할 | 실행 환경 |
|---------|------|------|----------|
| **Client** | `op-program/client/` | VM 내에서 실행되는 프로그램 | RISC-V/MIPS VM |
| **Host** | `op-program/host/` | VM을 실행하고 preimage 제공 | 호스트 머신 |

### 2.2 Client 구조

**주요 파일**:
- `client/program.go`: 프로그램 진입점
- `client/l1/`: L1 데이터 처리
- `client/l2/`: L2 데이터 처리
- `client/tasks/`: Derivation 작업

**특징**:
```go
// client/program.go:54-68
func RunProgram(logger log.Logger, preimageOracle io.ReadWriter, ...) {
	pClient := preimage.NewOracleClient(preimageOracle)  // Preimage 요청
	hClient := preimage.NewHintWriter(preimageHinter)    // Hint 전송

	l1PreimageOracle := l1.NewCachingOracle(...)
	l2PreimageOracle := l2.NewCachingOracle(...)

	// VM 내에서 실행되는 로직
	return RunPreInteropProgram(...)
}
```

### 2.3 Host 구조

**주요 파일**:
- `host/common/common.go`: Preimage server 실행
- `host/prefetcher/`: Preimage prefetching
- `host/kvstore/`: Preimage 저장소
- `host/cmd/main.go`: CLI 진입점

**특징**:
```go
// host/common/common.go:38-82
func FaultProofProgram(ctx context.Context, logger log.Logger, cfg *config.Config, ...) {
	// 1. Preimage server 시작
	preimageServer, err := StartPreimageServer(ctx, logger, cfg, ...)

	// 2. VM 실행 (ExecCmd가 있으면 별도 프로세스, 없으면 in-process)
	if cfg.ExecCmd != "" {
		cmd := exec.CommandContext(ctx, cfg.ExecCmd)  // VM 프로세스
		cmd.ExtraFiles[...] = hClientRW.Reader()      // FD 3, 4, 5, 6 설정
		cmd.Start()
		cmd.Wait()
	} else {
		// In-process 실행
		return cl.RunProgram(logger, pClientRW, hClientRW, clientCfg)
	}
}
```

### 2.4 통신 방식

```
┌─────────────────┐
│  Host (호스트)   │
│  - Preimage 제공 │
│  - KV Store      │
└────────┬────────┘
         │ File Descriptors (FD 3,4,5,6)
         │ Unix Pipes
┌────────▼────────┐
│  Client (VM)    │
│  - 실행 로직     │
│  - Preimage 요청 │
└─────────────────┘
```

---

## 3. 핵심 차이점 요약

### 3.1 KV Store 구현 차이

| 항목 | MemKV | DirectoryKV/FileKV | PebbleKV |
|------|-------|-------------------|----------|
| **성능** | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐ |
| **메모리 사용** | 높음 | 중간 | 낮음 (캐싱) |
| **파일 I/O** | 없음 | 있음 | 있음 (최적화) |
| **Get() 효율성** | 매우 높음 | 낮음 (`io.ReadAll`) | 높음 (DB) |
| **사용 시나리오** | 테스트 | 간단한 디스크 저장 | 프로덕션 |

### 3.2 Client vs Host 차이

| 항목 | Client | Host |
|------|--------|------|
| **실행 환경** | VM 내부 | 호스트 머신 |
| **역할** | 프로그램 실행 | VM 관리 + Preimage 제공 |
| **Preimage 접근** | 요청만 (FD 통신) | 제공 (KV Store) |
| **의존성** | 최소화 (VM 제약) | 전체 기능 사용 가능 |

---

## 4. 문제점 분석

### 4.1 DirectoryKV/FileKV의 문제

**공통 문제점**:
1. `io.ReadAll(f)`: 전체 파일을 메모리에 로드
2. `hex.DecodeString(string(dat))`: 불필요한 메모리 복사
3. 파일 I/O 오류 처리 부족
4. 매우 긴 실행 시 파일 손상 가능

**해결책**:
- PebbleKV 사용 (최적화된 DB)
- 또는 `Get()` 메서드 개선 (버퍼링된 읽기, `hex.Decode()` 사용)

### 4.2 op-e2e vs op-challenger 차이

| 항목 | op-e2e | op-challenger |
|------|--------|---------------|
| **KV Store** | MemKV 가능 | 항상 DiskKV |
| **실행 시간** | 짧음 | 매우 김 (수억 단계) |
| **문제 발생** | 낮음 | 높음 (파일 I/O) |

---

## 5. 권장 사항

### 5.1 KV Store 선택

1. **테스트/짧은 실행**: `MemKV` 사용 (`DataDir == ""`)
2. **프로덕션/긴 실행**: `PebbleKV` 사용 (`DataFormatPebble`)
3. **간단한 저장**: `DirectoryKV` 또는 `FileKV` (하지만 `Get()` 개선 필요)

### 5.2 개선 방안

1. **DirectoryKV/FileKV 개선**:
   - `io.ReadAll()` → 버퍼링된 읽기
   - `hex.DecodeString(string(dat))` → `hex.Decode(dat, ...)`

2. **PebbleKV 기본 사용**:
   - 더 효율적이고 안정적
   - 캐싱 및 압축 지원

3. **op-challenger 개선**:
   - 짧은 실행 시 MemKV 옵션 제공
   - 긴 실행 시 PebbleKV 사용

---

## 날짜

작성: 2025-01-21
목적: op-program 내부의 KV store 구현 및 Client/Host 구조 비교 분석

