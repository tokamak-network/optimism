# Asterisc Opcode 0x70 에러 분석 및 VM 아키텍처 비교

## 1. 에러 개요

### 1.1 발생한 문제
- **테스트**: `TestOutputAsteriscStepWithPreimage_existingPreimage`
- **에러 메시지**: `error: failed at step 324407790 (PC: 016cb928): revert f001c0de: unknown instruction opcode: 112`
- **발생 시점**: proof=34,359,738,367 (2^35 - 1, 최대 증명 스텝)
- **실행 컨텍스트**: Asterisc VM이 324,407,790 스텝을 성공적으로 실행 후 실패

### 1.2 증상
```
"t=2025-11-21T17:32:42+0900 lvl=info msg=\"Shutting down\"" role=Challenger proof=34,359,738,367
error: failed at step 324407790 (PC: 016cb928): revert f001c0de: revert: unknown instruction opcode: 112
```

- VM은 3억 2천만 스텝 이상 정상 실행
- PC 0x016cb928에서 opcode 112 (0x70) 발견
- ErrUnknownOpCode (0xf001c0de)로 revert

---

## 2. RISC-V 명령어 집합 분석 (Asterisc)

### 2.1 RISC-V 명령어 인코딩 구조
```
RISC-V 32-bit instruction format:
[31:25] [24:20] [19:15] [14:12] [11:7] [6:0]
funct7  rs2     rs1     funct3  rd     opcode (7 bits)
```

**핵심**: RISC-V는 하위 7비트를 opcode로 사용

### 2.2 Asterisc VM에서 구현된 유효 opcodes
코드 위치: `/Users/zena/tokamak-projects/asterisc/rvgo/slow/vm.go:783-1196`

```go
switch opcode.val() {
case 0x03: // 000_0011: memory loading (LB, LH, LW, LD, LBU, LHU, LWU)
case 0x23: // 010_0011: memory storing (SB, SH, SW, SD)
case 0x63: // 110_0011: branching (BEQ, BNE, BLT, BGE, BLTU, BGEU)
case 0x13: // 001_0011: immediate arithmetic and logic (ADDI, SLTI, ANDI, etc.)
case 0x33: // 011_0011: register arithmetic and logic (ADD, SUB, SLL, SRL, etc.)
case 0x37: // 011_0111: LUI = Load upper immediate
case 0x17: // 001_0111: AUIPC = Add upper immediate to PC
case 0x6f: // 110_1111: JAL = Jump and link
case 0x67: // 110_0111: JALR = Jump and link register
case 0x73: // 111_0011: SYSTEM (ECALL, EBREAK, CSR instructions)
case 0x0f: // 000_1111: FENCE operations
case 0x1b: // 001_1011: 64-bit immediate arithmetic (ADDIW, SLLIW, SRLIW, etc.)
case 0x3b: // 011_1011: 64-bit register arithmetic (ADDW, SUBW, SLLW, SRLW, etc.)
case 0x2f: // 010_1111: Atomic operations (LR, SC, AMOADD, AMOSWAP, etc.)
default:
    revertWithCode(riscv.ErrUnknownOpCode,
        fmt.Errorf("unknown instruction opcode: %d", opcode))
}
```

### 2.3 opcode 0x70 분석
```
0x70 = 0b01110000 (binary)
Lower 7 bits = 0b1110000 = 0x70
```

**결론**: **0x70은 RISC-V 표준 명령어 집합에 존재하지 않는 opcode**

---

## 3. MIPS64 명령어 집합 분석 (Cannon)

### 3.1 MIPS64 명령어 인코딩 구조
```
MIPS 32-bit instruction format:
[31:26] [25:21] [20:16] [15:11] [10:6] [5:0]
opcode  rs      rt      rd      shamt  funct (R-type)
(6 bits)

[31:26] [25:21] [20:16] [15:0]
opcode  rs      rt      immediate (I-type)
(6 bits)
```

**핵심**: MIPS는 상위 6비트를 opcode로 사용

### 3.2 Cannon VM에서 구현된 opcode 처리
코드 위치: `/Users/zena/tokamak-projects/optimism/cannon/mipsevm/exec/mips_instructions.go`

```go
// Line 32: opcode 추출
insn, opcode, fun := GetInstructionDetails(pc, memory)
opcode = insn >> 26  // 상위 6비트 (bits 26-31)
fun = insn & 0x3f    // 하위 6비트 (bits 0-5)

// Line 42-51: J-type instructions
if opcode == 2 || opcode == 3 {  // j/jal
    // Jump instructions
}

// Line 90-93: Branch instructions
if (opcode >= 4 && opcode < 8) || opcode == 1 {
    // BEQ, BNE, BLEZ, BGTZ, BLTZ, BGEZ
}

// Line 99-116: Memory operations
if opcode >= 0x20 || opcode == OpLoadDoubleLeft || opcode == OpLoadDoubleRight {
    // LB, LH, LW, LD, LBU, LHU, LWU, SB, SH, SW, SD
}

// ExecuteMipsInstruction 함수에서 추가 opcode 처리:
- opcode 0: R-type (fun field로 구분)
- opcode 8-0xE: Arithmetic/Logic Immediate
- opcode 0x18-0x19: DADDI, DADDIU (64-bit)
- opcode 0x20-0x2F: Memory load/store
- opcode 0x30, 0x38, 0x34, 0x3c: LL/SC (Load-Linked/Store-Conditional)
```

### 3.3 MIPS에서 0x70은?
```
0x70 = 112 decimal = 0b01110000 (binary)
As MIPS opcode (top 6 bits): would be part of instruction word

MIPS는 opcode가 상위 6비트이므로:
- 0x70이 명령어 단어에 포함될 경우, opcode는 (0x70 >> 26) & 0x3F로 계산
- 실제로는 instruction word의 다른 부분일 가능성
```

**차이점**: MIPS와 RISC-V는 명령어 인코딩이 완전히 다르므로 직접 비교 불가

---

## 4. 아키텍처 비교표

| 항목 | Asterisc (RISC-V) | Cannon (MIPS64) |
|------|-------------------|-----------------|
| **명령어 길이** | 32-bit 고정 | 32-bit 고정 |
| **Opcode 위치** | 하위 7비트 [6:0] | 상위 6비트 [31:26] |
| **Opcode 크기** | 7 bits (128 가능) | 6 bits (64 가능) |
| **레지스터 개수** | 32개 (x0-x31) | 32개 (r0-r31) |
| **명령어 형식** | R, I, S, B, U, J 타입 | R, I, J 타입 |
| **Syscall opcode** | 0x73 (ECALL) | 0x0c (R-type fun) |
| **Atomic ops** | 0x2f (LR/SC/AMO) | 0x30, 0x38 (LL/SC) |
| **64-bit 확장** | 기본 통합 (RV64I) | 별도 명령어 (MIPS64) |
| **VM 구현체** | rvgo (Go) | mipsevm (Go) |
| **컴파일 타겟** | riscv64-linux-gnu | mips64-linux-gnuabi64 |

---

## 5. opcode 0x70 문제의 가능한 원인들

### 5.1 잘못된 메모리 실행 (Most Likely)
```
시나리오: PC가 잘못된 주소로 점프하여 데이터를 명령어로 실행
- 함수 포인터 손상
- Stack overflow
- Buffer overflow
- Return address 오염
```

### 5.2 컴파일러 버그 (Less Likely)
```
시나리오: RISC-V 크로스 컴파일러가 잘못된 명령어 생성
- GCC/LLVM 버전 문제
- 최적화 옵션 문제
- Target architecture 설정 오류
```

### 5.3 미구현 RISC-V 확장 명령어 (Possible)
```
시나리오: op-program이 Asterisc VM에서 미구현된 확장 명령어 사용
- RV64G 확장의 일부 명령어 누락
- Vector 확장 (V)
- Compressed 확장 (C)
- Floating-point 확장 (F/D)
```

### 5.4 Memory Corruption (Possible)
```
시나리오: 실행 중 메모리 손상
- 동시성 문제
- Pre-image 로딩 중 메모리 덮어쓰기
- VM 자체의 버그
```

---

## 6. 테스트 비교: Cannon vs Asterisc

### 6.1 동일 테스트 존재 여부

**Cannon 테스트**:
- `TestOutputCannonStepWithPreimage_existingPreimage` (output_cannon_test.go:238)
- 동일한 테스트 구조: blob batches, WaitForCounterClaim, preimage loading

**Asterisc 테스트**:
- `TestOutputAsteriscStepWithPreimage_existingPreimage` (output_asterisc_test.go)
- 동일한 테스트 구조 사용

### 6.2 차이점
```go
// Cannon test (output_cannon_test.go:270)
providerFunc := game.NewMemoizedCannonTraceProvider(ctx, ...)

// Asterisc test (output_asterisc_test.go)
providerFunc := game.NewMemoizedAsteriscTraceProvider(ctx, ...)
```

**핵심 차이**: 동일한 op-program 소스를 다른 아키텍처로 컴파일
- Cannon: MIPS64 binary in prestate
- Asterisc: RISC-V binary in prestate

---

## 7. 디버깅 전략

### 7.1 단기 조치 (Immediate)
1. **Cannon 테스트 실행하여 비교**
   ```bash
   go test -v -run "TestOutputCannonStepWithPreimage_existingPreimage" \
     ./op-e2e/faultproofs
   ```
   - Cannon에서도 실패하면 → op-program 문제
   - Cannon에서 성공하면 → Asterisc 특정 문제

2. **PC 0x016cb928 주변 디스어셈블리 확인**
   ```bash
   riscv64-linux-gnu-objdump -d \
     /Users/zena/tokamak-projects/optimism/op-program/bin-e2e/op-program-client64.elf \
     | grep -A 10 -B 10 "16cb928"
   ```

3. **Step 324407790에서 메모리 상태 덤프**
   - Asterisc VM에 디버그 로깅 추가
   - 해당 스텝의 레지스터 상태 출력
   - 스택 상태 확인

### 7.2 중기 조치 (Short-term)
1. **RISC-V 명령어 확장 확인**
   ```bash
   riscv64-linux-gnu-readelf -h \
     /Users/zena/tokamak-projects/optimism/op-program/bin-e2e/op-program-client64.elf
   ```
   - ISA extensions 확인 (RV64IMAFDC?)

2. **컴파일 플래그 검증**
   ```bash
   # op-program/Makefile 확인
   - `-march=rv64g` 또는 더 제한적인 옵션 사용
   - 미구현 확장 비활성화
   ```

3. **Asterisc VM에 누락된 명령어 구현**
   - 0x70이 실제로 사용되어야 하는 명령어라면 구현
   - RISC-V spec 확인하여 0x70의 정의 찾기

### 7.3 장기 조치 (Long-term)
1. **VM 디버거 구현**
   - Step-by-step execution
   - Breakpoint 지원
   - Memory watch

2. **자동화된 테스트**
   - Cannon과 Asterisc 결과 비교
   - 모든 preimage 테스트에 대해 양쪽 VM 실행

3. **Formal Verification**
   - RISC-V instruction decoder 검증
   - Memory safety 증명

---

## 8. 다음 단계 (Next Steps)

### 8.1 즉시 실행 (Immediate Actions)
- [ ] Cannon 테스트 실행하여 op-program 문제인지 확인
- [ ] PC 0x016cb928의 바이너리 디스어셈블리 확인
- [ ] op-program-client64.elf의 ISA 확장 확인

### 8.2 조사 필요 (Investigation Needed)
- [ ] Step 324407790은 어떤 작업을 하는 시점인가?
- [ ] 해당 스텝에서 preimage 관련 작업이 있는가?
- [ ] 다른 Asterisc 테스트들은 통과하는가?

### 8.3 코드 수정 고려 (Potential Code Changes)
- [ ] Asterisc VM에 추가 opcode 구현 필요 여부 확인
- [ ] op-program 컴파일 옵션 수정 필요 여부 확인
- [ ] VM 에러 처리 개선 (더 자세한 디버그 정보)

---

## 9. 참고 자료

### 9.1 코드 위치
- **Asterisc VM**: `/Users/zena/tokamak-projects/asterisc/rvgo/slow/vm.go`
- **Cannon VM**: `/Users/zena/tokamak-projects/optimism/cannon/mipsevm/exec/mips_instructions.go`
- **테스트 파일**: `/Users/zena/tokamak-projects/optimism/op-e2e/faultproofs/`

### 9.2 관련 문서
- RISC-V ISA Specification: https://riscv.org/technical/specifications/
- MIPS64 Architecture: https://www.mips.com/products/architectures/mips64/
- OP Stack Fault Proofs: https://specs.optimism.io/experimental/fault-proof/index.html

### 9.3 관련 이슈
- Blob preimage timestamp 버그: ASTERISC_BLOB_BUG_FIX.md
- L1BlockRef.Time 불일치 문제 (해결됨)

---

## 10. 결론

### 10.1 현재 상황
- ✅ Blob timestamp 수정 성공: DEBUG 로그로 타임스탬프 일치 확인
- ✅ WaitForCounterClaim 통과: 이전 hang 문제 해결
- ❌ VM execution 실패: opcode 0x70으로 인한 실패

### 10.2 핵심 발견사항
1. **0x70은 RISC-V 표준 명령어 집합에 없음**
2. **3억+ 스텝 정상 실행 후 실패** → 초기화 문제 아님
3. **proof=2^35-1에서 발생** → 게임 트리의 최대 깊이
4. **PC 0x016cb928** → 특정 코드 위치에서 발생

### 10.3 우선순위가 높은 조사 방향
1. Cannon 테스트와 비교하여 op-program vs Asterisc VM 문제 구분
2. 해당 PC의 실제 바이너리 내용 확인
3. RISC-V 바이너리의 사용 ISA 확장 확인

---

*마지막 업데이트: 2025-11-21*
*작성자: Claude Code*
*관련 버그: ASTERISC_BLOB_BUG_FIX.md*
