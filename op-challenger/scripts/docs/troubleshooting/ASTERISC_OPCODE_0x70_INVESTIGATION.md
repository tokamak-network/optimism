# Asterisc Opcode 0x70 Error Investigation

## 문제 요약

**에러 메시지:**
```
error: failed at step 324429495 (PC: 016cb928): revert f001c0de: revert: unknown instruction opcode: 112
```

**핵심 정보:**
- Step: 324,429,495 (약 3.24억 단계) - 실제 로그에서 확인된 값
- PC (Program Counter): 0x016cb928
- Instruction: 0x00371f70
- Opcode: 112 (0x70) - RISC-V에 존재하지 않는 무효한 명령어
- Error Code: 0xf001c0de (ErrUnknownOpCode)
- Proof Position: 34,359,738,367 (2^35-1, MAX_GAME_DEPTH)

## 챌린저 코드 흐름 분석

### 1. 전체 실행 흐름

```
1. game_solver.go:CalculateNextActions() (Line 92)
   └─> claim 14를 처리하기 위해 game.Claims() 순회 (Line 127)

2. game_solver.go:calculateMove() (Line 169)
   └─> claimSolver.NextMove() 호출하여 다음 move 계산 (Line 170)

3. [claimSolver 내부] trace.Get() 호출하여 claim의 값 가져오기

4. asterisc/provider.go:Get() (Line 57)
   └─> pos.TraceIndex(gameDepth) 계산 -> 34,359,738,367
   └─> loadProof(ctx, 34359738367) 호출 (Line 62)

5. asterisc/provider.go:loadProof() (Line 104)
   └─> proof 파일이 없으면:
   └─> generator.GenerateProof(ctx, dir, i) 호출 (Line 121)
       └─> 에러 발생 시: "generate asterisc trace with proof at %v"

6. executor.go:GenerateProof() (Line 129)
   └─> DoGenerateProof(ctx, dir, i, i) 호출 (begin=i, end=i)

7. executor.go:DoGenerateProof() (Line 135)
   └─> Line 150: "--proof-at", "=" + strconv.FormatUint(end, 10)
   └─> 여기서 "--proof-at=34359738367" 설정!
   └─> Asterisc VM 실행

8. Asterisc VM 실행:
   - Step 320,000,000에서 시작 (스냅샷 로드)
   - Step 324,429,495에서 opcode 0x70 (무효한 명령어) 만남
   - 실행 중단, exit code 1
```

### 2. 챌린저가 proof를 요청하는 이유

- `34,359,738,367` (2^35-1)은 `MAX_GAME_DEPTH`의 마지막 step
- 챌린저가 claim 14에 반박하려면 이 position의 state proof가 필요
- VM이 step 324,429,495에서 멈추기 때문에 목표 step까지 실행 불가

## 로그 분석 (디버깅 로그 기반)

### 실제 에러 발생 시점 상세 정보

**에러 발생 시점 (Step 324,429,496):**
```
Step: 324429496
PC: 0x016cb928
Instruction: 0x00371f70
Opcode: 0x70 (112) - 무효한 RISC-V 명령어
Previous PC would be: 0x016cb924
Next PC would be: 0x016cb92c
```

### 메모리 주변 분석 (PC 주변)

**메모리 덤프:**
```
0x016cb918: 0x001a8650
0x016cb91c: 0x00000000
0x016cb920: 0x001a86b0
0x016cb924: 0x00000000  ← Previous PC 위치 (NULL!)
0x016cb928: 0x00371f70  ← 현재 PC (문제 발생 지점)
0x016cb92c: 0x00000000  ← Next PC 위치
0x016cb930: 0x0036d618
0x016cb934: 0x00000000
0x016cb938: 0x00372020
```

**중요한 발견:**
- **Previous PC (0x016cb924)의 값이 0x00000000** - 매우 의심스러움!
- 메모리 패턴이 4바이트 단위로 0이 반복되는 패턴
- Instruction 0x00371f70의 opcode가 0x70 (하위 7비트)

### 레지스터 상태

**Key Registers:**
```
ra (x1): 0x000000000008f91c  (Return Address)
sp (x2): 0x000000c0003bfe70  (Stack Pointer)
gp (x3): 0x0000000000000000  (Global Pointer)
tp (x4): 0x0000000000000000  (Thread Pointer)
```

**관찰:**
- Return Address (ra)가 매우 작은 값 (0x8f91c) - 정상적인 코드 영역인지 확인 필요
- Stack Pointer는 정상 범위 (0xc0003bfe70)
- Global/Thread Pointer는 0

### VM 실행 패턴

로그에서 반복적으로 다음 패턴 확인:
1. Step 320M 스냅샷 로드
2. 약 4.4M 단계 실행 (320M → 324.4M)
3. PC 0x016cb928에서 opcode 0x70 만남
4. 실행 실패 후 재시도
5. 매 2초마다 동일한 실패 반복

## 기술적 분석

### Opcode 0x70의 의미

**RISC-V 명령어 세트:**
- 유효한 opcode 범위: 0x00-0x7F (특정 패턴만)
- 0x70은 RISC-V 표준에서 정의되지 않음
- Syscall (ECALL)은 0x73 사용

**가능한 원인 (로그 분석 기반):**

1. **NULL Pointer Dereference (가장 유력)**
   - Previous PC 위치 (0x016cb924)의 값이 0x00000000
   - 이전 명령어가 NULL 포인터를 반환하거나 잘못된 점프 발생
   - PC가 데이터 영역(초기화되지 않은 메모리)을 가리키게 됨
   - **증거**: 메모리 패턴이 4바이트 단위로 0이 반복

2. **메모리 손상**
   - PC가 데이터 영역을 가리키고 있을 가능성
   - 데이터 (0x00371f70)를 코드로 해석하여 실행
   - Instruction의 하위 7비트가 0x70으로 해석됨

3. **잘못된 점프/분기**
   - 이전 명령어가 잘못된 주소로 점프
   - PC: 0x00178558 → 0x016cb928로 변경됨
   - Return address (ra: 0x8f91c)가 매우 작은 값 - 의심스러움

4. **스택 오버플로우**
   - 스택이 코드 영역을 덮어씀
   - Return address 손상
   - Stack pointer (0xc0003bfe70)는 정상 범위

5. **초기화되지 않은 메모리**
   - PC가 초기화되지 않은 영역 실행
   - 메모리 패턴 (0x00000000 반복)이 이를 시사

6. **컴파일 문제**
   - RISC-V 크로스 컴파일 중 오류
   - 잘못된 명령어 생성

## 게임 상태

**Claim 정보:**
- Total claims: 15
- 챌린저가 응답 시도 중: Claim 14
- 게임 상태: In Progress
- 실패 원인: "failed to determine response to claim 14"

**Split Game Tree:**
```
Claim 0 (Root) -> Depth: 0
  └─> Claim 1 (ATTACK) -> Depth: 1, TraceIndex: 562949953421311
      └─> Claim 2 (ATTACK) -> Depth: 2, TraceIndex: 281474976710655
          └─> ... (계속 ATTACK)
              └─> Claim 14 -> Depth: 14 (Split Depth 도달)
```

Split Depth = 14에서 실제 VM execution 증명 필요

## 파일 정보

**ELF 바이너리:**
- 경로: `/Users/zena/tokamak-projects/optimism/op-program/bin-riscv/op-program-client-riscv.elf`
- 타입: ELF 64-bit LSB executable, RISC-V
- ABI: double-float ABI
- 링킹: statically linked
- 빌드: Go BuildID=BNn6I9KeW0IcC8tUhL1P/...
- 디버그 정보: 포함 (with debug_info, not stripped)

**문제 주소:**
- PC 0x016cb928 = 23,902,504 (decimal)
- 이 주소가 .text 영역인지, 데이터 영역인지 확인 필요

## 다음 조사 방향 (우선순위)

### 즉시 확인 필요

1. **Previous PC (0x016cb924) 분석**
   - 왜 이 위치의 값이 0x00000000인지 확인
   - 이전 명령어가 무엇이었는지 추적
   - NULL pointer dereference 발생 지점 찾기

2. **PC 0x016cb928 메모리 영역 확인**
   - ELF 바이너리에서 이 주소가 어떤 세그먼트인지 확인
   - .text 영역인지, .data/.bss 영역인지 판단
   - `readelf -l` 또는 `objdump -h`로 확인

3. **실행 추적 (Backtrace)**
   - Step 324,429,490 ~ 324,429,496 사이의 PC 변화 추적
   - PC가 0x00178558에서 0x016cb928로 어떻게 변경되었는지
   - 점프/분기 명령어 추적

4. **Return Address (ra: 0x8f91c) 검증**
   - 이 주소가 유효한 코드 영역인지 확인
   - 함수 호출 스택이 손상되었는지 확인

### 추가 조사

5. **메모리 맵 확인**
   - 0x016cb928이 정상적인 코드 영역인지
   - ELF 세그먼트 매핑 확인
   - 메모리 보호 설정 확인

6. **Cannon 비교**
   - 같은 테스트에서 Cannon(MIPS64)은 통과하는지
   - RISC-V 특유의 문제인지 확인

7. **Go 런타임 분석**
   - Go의 RISC-V 백엔드 문제 가능성
   - goroutine 스택 관련 문제 체크
   - GC 관련 메모리 이슈

8. **Blob preimage 관련성**
   - 최근 수정한 blob timestamp 코드와 연관성
   - Large preimage 처리 중 메모리 이슈

## 임시 해결 방안 (검토 필요)

1. **MAX_GAME_DEPTH 조정**
   - 현재 35 depth가 너무 깊을 가능성
   - 실제 필요한 depth 재검토

2. **스냅샷 빈도 증가**
   - 320M 이후 더 자주 스냅샷 생성
   - 문제 지점에 더 가까운 시작점 확보

3. **메모리 제한 확인**
   - 49.7 MiB at step 320M
   - 추가 4.4M step 실행 중 메모리 부족 가능성

4. **RISC-V 컴파일 옵션 검토**
   - 최적화 레벨 조정
   - ISA extension 제한

## 참고 문서

- [ASTERISC_OPCODE_0x70_ANALYSIS.md](./ASTERISC_OPCODE_0x70_ANALYSIS.md)
- [CHALLENGER_VM_COMMUNICATION_INTERFACE.md](./CHALLENGER_VM_COMMUNICATION_INTERFACE.md)
- [ASTERISC_BLOB_BUG_FIX.md](/Users/zena/tokamak-projects/optimism/ASTERISC_BLOB_BUG_FIX.md)

## 로그 분석 요약

**디버깅 로그 분석 결과 (2025-11-21):**

1. **핵심 발견**: Previous PC 위치 (0x016cb924)의 값이 **0x00000000** - NULL pointer dereference 가능성 높음
2. **메모리 패턴**: 4바이트 단위로 0이 반복되는 패턴 - 초기화되지 않은 메모리 영역
3. **Instruction 분석**: 0x00371f70의 opcode가 0x70으로 해석됨 - 데이터를 코드로 잘못 해석
4. **Return Address**: ra 레지스터 값 (0x8f91c)이 매우 작음 - 함수 호출 스택 손상 가능성

**가장 유력한 원인:**
- NULL pointer dereference로 인한 잘못된 메모리 접근
- PC가 데이터 영역을 가리키게 되어 데이터를 코드로 해석
- 이전 명령어가 NULL을 반환하거나 잘못된 점프 발생

## 날짜

작성: 2025-11-21
최종 업데이트: 2025-11-21 (디버깅 로그 분석 완료)
조사 중: Opcode 0x70 에러의 근본 원인 - NULL pointer dereference 가능성 높음
