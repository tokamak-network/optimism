# Challenger-VM 통신 인터페이스 완전 정리

## 아키텍처 개요

```
┌──────────────────────────────────────────┐
│  op-challenger (Host)                    │
│  - Preimage 데이터 관리                   │
│  - Hint 처리                             │
│  - VM 프로세스 관리                       │
└──────────┬───────────────────────────────┘
           │
           │ Unix Socket (Preimage Oracle)
           │ Pipes (stdout/stderr/hint)
           │
┌──────────▼───────────────────────────────┐
│  Asterisc VM (RISC-V Interpreter)       │
│  - ECALL (0x73) intercept               │
│  - Syscall number in register a7 (x17)  │
│  - FD-based communication                │
└──────────┬───────────────────────────────┘
           │ Memory space
           │
┌──────────▼───────────────────────────────┐
│  op-program (Guest Binary)               │
│  - ECALL 명령어 실행                      │
│  - File descriptor read/write            │
└──────────────────────────────────────────┘
```

---

## 1. RISC-V Syscall 메커니즘

### 1.1 ECALL 명령어
```
RISC-V Instruction: ECALL
Opcode: 0x73
Funct3: 0x0

op-program이 ECALL을 실행하면:
1. VM이 intercept
2. a7 레지스터(x17)에서 syscall 번호 읽기
3. a0-a5 레지스터(x10-x15)에서 인자 읽기
4. 처리 후 a0(x10)에 결과, a1(x11)에 에러코드 저장
```

### 1.2 레지스터 규약
```go
// Syscall Arguments (ABI)
a0 (x10) - 1st arg / return value
a1 (x11) - 2nd arg / error code
a2 (x12) - 3rd arg
a3 (x13) - 4th arg
a4 (x14) - 5th arg
a5 (x15) - 6th arg
a6 (x16) - 7th arg
a7 (x17) - Syscall number
```

---

## 2. Syscall 번호 (코드: asterisc/rvgo/riscv/constants.go)

### 2.1 프로세스 관리
| Syscall | 번호 | 설명 | 구현 상태 |
|---------|------|------|----------|
| `SysExit` | 93 | 프로그램 종료 | ✅ 구현 |
| `SysExitGroup` | 94 | 프로세스 그룹 종료 | ✅ 구현 |
| `SysClone` | 220 | 스레드 생성 (미지원) | ⚠️ 반환: pid=1 |
| `SysGettid` | 178 | 스레드 ID 조회 | ✅ 구현 |

### 2.2 메모리 관리
| Syscall | 번호 | 설명 | 구현 상태 |
|---------|------|------|----------|
| `SysBrk` | 214 | Program break 설정 | ✅ 구현 (1GB 고정) |
| `SysMmap` | 222 | 메모리 매핑 | ✅ 구현 (익명 매핑만) |
| `SysMunmap` | 215 | 메모리 해제 | ✅ 구현 |
| `SysMadvise` | 233 | 메모리 조언 | ✅ 구현 |

### 2.3 파일 I/O
| Syscall | 번호 | 설명 | 구현 상태 |
|---------|------|------|----------|
| `SysRead` | 63 | 파일 읽기 | ✅ 구현 (FD별 처리) |
| `SysWrite` | 64 | 파일 쓰기 | ✅ 구현 (FD별 처리) |
| `SysFcntl` | 25 | 파일 제어 | ✅ 구현 (F_GETFD/F_GETFL) |
| `SysOpenat` | 56 | 파일 열기 | ❌ EACCES 반환 |
| `SysReadlinnkat` | 78 | 심볼릭 링크 읽기 | ✅ 구현 |
| `SysNewfstatat` | 79 | 파일 정보 조회 | ✅ 구현 |
| `SysPipe2` | 59 | 파이프 생성 | ✅ 구현 |

### 2.4 시간/동기화
| Syscall | 번호 | 설명 | 구현 상태 |
|---------|------|------|----------|
| `SysClockGettime` | 113 | 시간 조회 | ✅ 구현 (1337s+42ns 고정) |
| `SysNanosleep` | 101 | Sleep | ✅ No-op (즉시 반환) |
| `SysFutex` | 422 | Fast Userspace Mutex | ❌ Unsupported |

### 2.5 시스템 정보
| Syscall | 번호 | 설명 | 구현 상태 |
|---------|------|------|----------|
| `SysNewuname` | 160 | 시스템 정보 | ✅ 구현 |
| `SysGetrlimit` | 163 | 리소스 제한 조회 | ✅ 구현 |
| `SysPrlimit64` | 261 | 리소스 제한 (64bit) | ❌ Unsupported |
| `SysGetRandom` | 278 | 난수 생성 | ✅ 구현 |

### 2.6 스케줄링
| Syscall | 번호 | 설명 | 구현 상태 |
|---------|------|------|----------|
| `SysSchedGetaffinity` | 123 | CPU affinity 조회 | ✅ 구현 |
| `SysSchedYield` | 124 | CPU 양보 | ✅ 구현 |

### 2.7 시그널
| Syscall | 번호 | 설명 | 구현 상태 |
|---------|------|------|----------|
| `SysRtSigprocmask` | 135 | 시그널 마스크 | ✅ 구현 |
| `SysSigaltstack` | 132 | 시그널 스택 | ✅ 구현 |
| `SysRtSigaction` | 134 | 시그널 핸들러 | ✅ 구현 |

### 2.8 I/O 멀티플렉싱
| Syscall | 번호 | 설명 | 구현 상태 |
|---------|------|------|----------|
| `SysEpollCreate1` | 20 | epoll 생성 | ✅ 구현 |
| `SysEpollCtl` | 21 | epoll 제어 | ✅ 구현 |

---

## 3. 파일 디스크립터 (FD) 인터페이스

### 3.1 FD 번호 정의
```go
// 코드: asterisc/rvgo/riscv/constants.go:34-40
const (
    FdStdin         = 0  // 표준 입력
    FdStdout        = 1  // 표준 출력
    FdStderr        = 2  // 표준 에러
    FdHintRead      = 3  // Hint 응답 읽기
    FdHintWrite     = 4  // Hint 요청 쓰기
    FdPreimageRead  = 5  // Preimage 데이터 읽기
    FdPreimageWrite = 6  // Preimage 키 쓰기
)
```

### 3.2 FD별 Read 동작 (SysRead = 63)
```go
// 코드: asterisc/rvgo/slow/vm.go:622-644
case riscv.SysRead:
    fd := a0    // File descriptor
    addr := a1  // Buffer address
    count := a2 // Byte count

    switch fd {
    case FdStdin:         // 0
        return 0          // 항상 0 바이트 (EOF)

    case FdHintRead:      // 3
        return count      // Hint ACK 완료 (실제 읽기 없음)

    case FdPreimageRead:  // 5
        // Host에서 제공한 preimage 데이터 읽기
        n = readPreimageValue(addr, count)
        return n

    default:
        return -1, EBADF  // 잘못된 FD
    }
```

### 3.3 FD별 Write 동작 (SysWrite = 64)
```go
// 코드: asterisc/rvgo/slow/vm.go:645-669
case riscv.SysWrite:
    fd := a0    // File descriptor
    addr := a1  // Buffer address
    count := a2 // Byte count

    switch fd {
    case FdStdout:        // 1
        // stdout로 출력 (Host가 수집)
        return count

    case FdStderr:        // 2
        // stderr로 출력 (Host가 수집)
        return count

    case FdHintWrite:     // 4
        // Hint 전송 (Host에게 데이터 요청 알림)
        return count

    case FdPreimageWrite: // 6
        // Preimage 키 설정
        n = writePreimageKey(addr, count)
        return n

    default:
        return -1, EBADF  // 잘못된 FD
    }
```

---

## 4. Preimage Oracle 프로토콜

### 4.1 Hint-Write (FD 4)
**목적**: Host에게 필요한 데이터를 미리 알림

```
op-program              VM                   Host (challenger)
    │                   │                          │
    │──(1) write(4)───→│                          │
    │   Hint 데이터      │                          │
    │                   │──(2) Hint 전달─────────→│
    │                   │                          │ (데이터 준비)
    │                   │                          │
```

**Hint 형식**:
```go
// op-program/client/l1/hints.go
type BlobHint struct {
    BlobHash [32]byte  // Blob 해시
    Index    uint64    // Blob 인덱스
    Timestamp uint64   // L1 블록 타임스탬프
}
```

### 4.2 Preimage-Write (FD 6)
**목적**: Preimage 키 설정 (최대 32바이트)

```go
// 코드: asterisc/rvgo/slow/vm.go:483-509
func writePreimageKey(addr, count uint64) uint64 {
    // 메모리에서 최대 32바이트 읽기
    data := readMemory(addr, min(count, 32))

    // Preimage 키 누적 (bit-shift로 연결)
    currentKey = (currentKey << (count * 8)) | data

    // Preimage 오프셋 초기화
    preimageOffset = 0

    return count
}
```

### 4.3 Preimage-Read (FD 5)
**목적**: Preimage 데이터 읽기

```go
// 코드: asterisc/rvgo/slow/vm.go:511-559
func readPreimageValue(addr, count uint64) uint64 {
    offset := getPreimageOffset()

    // Host에서 preimage 데이터 가져오기
    // (실제로는 VM 상태의 preimage 필드에서)
    data := getPreimageData()[offset:offset+count]

    // 메모리에 쓰기
    writeMemory(addr, data)

    // 오프셋 증가
    setPreimageOffset(offset + count)

    return count
}
```

### 4.4 완전한 Preimage 요청 흐름

```
op-program              VM                   Host
    │                   │                      │
    │──(1) write(4)───→│                      │
    │   Hint: "blob X"  │──(2) Hint─────────→│
    │                   │                      │ (Blob 로드)
    │                   │                      │
    │──(3) write(6)───→│                      │
    │   Key: hash(X)    │                      │
    │                   │                      │
    │──(4) read(5)────→│                      │
    │   want 32 bytes   │                      │
    │                   │──(5) 데이터 요청───→│
    │                   │                      │
    │                   │←─(6) Blob 데이터───│
    │←──(7) 32 bytes──│                      │
    │                   │                      │
    │──(8) read(5)────→│ (offset += 32)       │
    │   want more...    │                      │
```

---

## 5. 실제 사용 예시

### 5.1 op-program에서 Blob 가져오기
```go
// 코드: op-program/client/l1/oracle.go
func (p *PreimageOracle) GetBlob(ref eth.L1BlockRef, blobHash eth.IndexedBlobHash) *eth.Blob {
    // (1) Hint 전송
    blobReqMeta := make([]byte, 16)
    binary.BigEndian.PutUint64(blobReqMeta[0:8], blobHash.Index)
    binary.BigEndian.PutUint64(blobReqMeta[8:16], timestamp)

    p.hint.Hint(BlobHint(append(blobHash.Hash[:], blobReqMeta...)))
    // → VM이 intercept → Host에게 전달

    // (2) Preimage 키 설정 + 데이터 읽기
    data := p.oracle.Get(preimage.Keccak256Key(blobHash))
    // → write(FD 6, hash)  → VM이 키 저장
    // → read(FD 5, buffer) → VM이 데이터 반환

    return data
}
```

### 5.2 VM에서의 실제 처리
```go
// asterisc/rvgo/slow/vm.go:1093-1098
case 0x73: // ECALL
    if funct3 == 0 { // ECALL
        sysCall()  // → Line 564
    }

// Line 645-663: SysWrite 처리
case riscv.SysWrite:
    switch fd {
    case FdHintWrite:  // 4
        // Host의 hint channel로 전송
        hintData := readMemory(addr, count)
        sendToHost(hintData)
        return count

    case FdPreimageWrite:  // 6
        // Preimage 키 설정
        keyData := readMemory(addr, count)
        setPreimageKey(keyData)
        return count
    }

// Line 622-644: SysRead 처리
case riscv.SysRead:
    switch fd {
    case FdPreimageRead:  // 5
        // Host에서 데이터 가져오기
        data := requestPreimageFromHost(currentKey, offset, count)
        writeMemory(addr, data)
        return len(data)
    }
```

---

## 6. 에러 코드

### 6.1 VM 내부 에러
```go
// 코드: asterisc/rvgo/riscv/constants.go:42-58
const (
    ErrUnrecognizedResource           = 0xf0012      // 알 수 없는 리소스
    ErrUnknownAtomicOperation         = 0xf001a70    // 알 수 없는 Atomic 연산
    ErrUnknownOpCode                  = 0xf001c0de   // ⚠️ opcode 0x70 에러!
    ErrInvalidSyscall                 = 0xf001ca11   // 지원하지 않는 syscall
    ErrInvalidRegister                = 0xbad4e9     // 잘못된 레지스터
    ErrNotAlignedAddr                 = 0xbad10ad0   // 정렬되지 않은 주소
    ErrLoadExceeds8Bytes              = 0xbad512e0   // Load 크기 초과
    ErrStoreExceeds8Bytes             = 0xbad512e8   // Store 크기 초과
    ErrStoreExceeds32Bytes            = 0xbad512e1   // 32바이트 Store 초과
    ErrUnexpectedRProofLoad           = 0xbad22220   // 예상치 못한 R증명
    ErrUnexpectedRProofStoreUnaligned = 0xbad22221   // 증명 정렬 오류
    ErrUnexpectedRProofStore          = 0xbad2222f   // R증명 Store 오류
    ErrIllegalInstruction             = 0xbadc0de    // 불법 명령어
    ErrBadAMOSize                     = 0xbada70     // Atomic 크기 오류
    ErrFailToReadPreimage             = 0xbadf00d0   // Preimage 읽기 실패
    ErrBadMemoryProof                 = 0xbadf00d1   // 메모리 증명 오류
)
```

### 6.2 POSIX 에러 코드
```go
const (
    EBADF  = 0x4d  // Bad file descriptor
    EACCES = 0xd   // Permission denied
    EINVAL = 0x16  // Invalid argument
)
```

---

## 7. 통신 프로토콜 요약

### 7.1 데이터 흐름 방향
```
┌─────────────┬──────────────┬──────────────────────┐
│ Direction   │ FD           │ Purpose              │
├─────────────┼──────────────┼──────────────────────┤
│ → Host      │ 1 (stdout)   │ 로그/디버그 출력      │
│ → Host      │ 2 (stderr)   │ 에러 출력            │
│ → Host      │ 4 (hint-w)   │ Preimage 요청 알림    │
│ → VM state  │ 6 (pre-w)    │ Preimage 키 설정     │
│ ← Host      │ 3 (hint-r)   │ Hint ACK 확인        │
│ ← Host      │ 5 (pre-r)    │ Preimage 데이터 수신 │
│ ← Never     │ 0 (stdin)    │ 사용 안 함 (EOF)     │
└─────────────┴──────────────┴──────────────────────┘
```

### 7.2 Syscall 빈도 (추정)
```
가장 많이 사용:
- SysRead (63)        - Preimage 읽기
- SysWrite (64)       - Hint/Preimage 쓰기, 로그
- SysMmap (222)       - 메모리 할당
- SysBrk (214)        - Heap 관리

중간:
- SysFcntl (25)       - FD 정보 조회
- SysClockGettime     - 타임스탬프

드물게:
- SysExit (93)        - 프로그램 종료
- SysClone (220)      - Go runtime 호출
- SysNanosleep (101)  - Go runtime 호출
```

---

## 8. opcode 0x70 문제와의 연관성

**중요**: opcode 0x70 에러는 **syscall 인터페이스 문제가 아닙니다!**

```
오류 발생 지점:
- ECALL (0x73) → ✅ 정상 작동
- PC 0x016cb928의 0x70 → ❌ 유효하지 않은 명령어

0x70은:
- RISC-V instruction opcode가 아님
- Syscall 번호도 아님
- 데이터 또는 잘못된 코드일 가능성
```

---

## 9. 디버깅 팁

### 9.1 Syscall 로깅
```go
// VM 코드 수정하여 로깅 추가
sysCall := func() {
    a7 := getRegister(byteToU64(17))
    fmt.Fprintf(os.Stderr, "[SYSCALL] num=%d PC=0x%x\n", a7.val(), getPC())
    switch a7.val() {
    // ...
    }
}
```

### 9.2 Preimage 통신 추적
```go
// FdPreimageRead에 로깅 추가
case riscv.FdPreimageRead:
    fmt.Fprintf(os.Stderr, "[PREIMAGE-READ] offset=%d count=%d key=%x\n",
        getPreimageOffset(), count, getPreimageKey())
    n = readPreimageValue(addr, count)
```

### 9.3 FD 사용 통계
```bash
# 로그에서 FD 사용 빈도 확인
grep "SysWrite.*fd=" vm_log.txt | cut -d'=' -f2 | cut -d' ' -f1 | sort | uniq -c
```

---

## 10. 참고 자료

### 10.1 코드 위치
- **Syscall 정의**: `asterisc/rvgo/riscv/constants.go`
- **Syscall 구현**: `asterisc/rvgo/slow/vm.go:564-761`
- **Preimage Oracle**: `asterisc/rvgo/slow/vm.go:480-559`
- **op-program 사용**: `op-program/client/l1/oracle.go`

### 10.2 관련 문서
- RISC-V Syscall ABI: https://github.com/riscv-non-isa/riscv-elf-psabi-doc
- Linux Syscall Reference: https://syscalls.mebeim.net/?table=riscv/64
- OP Stack Preimage Oracle: https://specs.optimism.io/experimental/fault-proof/index.html

---

*마지막 업데이트: 2025-11-21*
*작성자: Claude Code*
*관련: ASTERISC_OPCODE_0x70_ANALYSIS.md*
