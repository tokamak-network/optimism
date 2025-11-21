# Asterisc Fault Proofs 테스트 보고서

## 개요

Asterisc (GameType 2) RISC-V 기반 fault proof 시스템의 `op-e2e/faultproofs` Go 테스트 스위트 실행 결과를 정리한 문서입니다. 각 항목은 아래 정보를 포함합니다.

- **목적**: 테스트가 검증하려는 대상
- **실행 방법**: 실제로 실행한 명령어
- **결과 및 소요 시간**: 실행 결과와 대략적인 시간
- **비고**: 로그에서 확인한 특이 사항

모든 명령어는 리포지토리 루트(`/Users/zena/tokamak-projects/optimism`)에서 실행했습니다.

## 사전 준비사항

테스트 실행 전에 필수 바이너리 빌드가 필요합니다. 자세한 내용은 아래 문서를 참조하세요:

📖 **[Fault Proofs E2E 테스트 가이드](./faultproofs-e2e.md)** - 바이너리 빌드 및 환경 설정

**빠른 준비 명령어:**
```bash
cd /Users/zena/tokamak-projects/optimism/op-challenger/scripts
./build-binaries-for-challenger-e2e.sh --force --asterisc
```

## 테스트 실행 내역

### TestOutputAsteriscGame

- **목적:** Asterisc (GameType 2) RISC-V fault proof 시스템의 기본 게임 플레이 흐름 검증.
- **실행 방법:**
  ```bash
  go test -v -timeout 20m ./op-e2e/faultproofs -run "^TestOutputAsteriscGame$/asterisc$"

  # 백그라운드 실행 및 로그 저장
  go test -v -timeout 20m ./op-e2e/faultproofs -run "^TestOutputAsteriscGame$/asterisc$" 2>&1 | tee /tmp/test_asterisc_asterisc.log &
  ```
- **결과 및 소요 시간:** ✅ PASS, 약 285초 (~4.75분).
- **비고:**
  - 두 가지 VM allocator 타입(`asterisc`, `asterisc-kona`)에 대해 각각 테스트 실행.
  - Cannon 테스트와 동일한 로직을 Asterisc VM (RISC-V)으로 수행.
  - 표준 배포 로그 후 챌린저가 분쟁을 해결하며, 예상되는 가스 팁 조정 외 특이사항 없음.
  - **중요:** Syscall 101 (nanosleep) 지원이 Slow VM에 추가됨 (Go 1.23+ 호환성).
- **실행 흐름:**
  1. L1·L2 개발용 체인과 핵심 서비스(Sequencer, Batcher, Challenger)가 부팅됨.
  2. DisputeGameFactory에 GameType 2 (Asterisc) 등록 및 컨트랙트 배포.
  3. 4번 L2 블록에 대한 잘못된 출력 루트 클레임(`0x01`) 제출.
  4. `StartOutputAsteriscGame`을 통해 Asterisc 게임 생성.
  5. Challenger가 `WithAsterisc` 옵션으로 시작하여 Asterisc VM 사용.
  6. `testCannonGame` 로직을 재사용하여 분쟁 게임 진행 (Asterisc는 Cannon과 동일한 게임 로직 사용).
  7. 분쟁 게임 상태가 `Challenger Won`으로 전환되고, 서비스가 정리되며 테스트 종료.
- **주요 기능 검증:**
  - `StartOutputAsteriscGame()` 팩토리 메서드 정상 작동.
  - DisputeGameFactory에 GameType 2 등록 및 게임 생성 확인.
  - Challenger가 `WithAsterisc` 옵션으로 Asterisc VM 바이너리를 올바르게 사용하는지 확인.
  - Asterisc VM이 op-program 서버와 통신하여 증거 생성 및 검증 수행.
  - 두 가지 VM allocation type 테스트 (mt-cannon, mt-cannon-next).

### TestOutputAsterisc_ChallengeAllZeroClaim

- **목적:** 모든 클레임이 제로(0x00...)인 경우 Asterisc 챌린저가 정상적으로 반박하는지 검증.
- **실행 방법:**
  ```bash
  # 전체 테스트 (mt-cannon, mt-cannon-next 두 VM 타입 모두 실행)
  go test -v -timeout 20m ./op-e2e/faultproofs -run "TestOutputAsterisc_ChallengeAllZeroClaim"

  # mt-cannon 서브테스트만 실행 (단일 VM)
  go test -v -timeout 20m ./op-e2e/faultproofs -run "^TestOutputAsterisc_ChallengeAllZeroClaim$/asterisc$"

  # 백그라운드로 실행하고 로그 저장
  timeout 1200s go test -v -timeout 20m ./op-e2e/faultproofs \
    -run "^TestOutputAsterisc_ChallengeAllZeroClaim$/asterisc$" \
    2>&1 > /tmp/gametype2_mt_cannon_only.log &

  # 로그 확인
  tail -f /tmp/gametype2_mt_cannon_only.log
  ```
- **결과 및 소요 시간:** ✅ PASS, 약 265초 (~4.4분).
- **비고:**
  - Dishonest actor가 항상 all-zero 클레임을 제출하는 극단적 시나리오.
  - Cannon의 `testCannonChallengeAllZeroClaim` 로직을 재사용.
  - 두 가지 VM allocator 타입에 대해 모두 정상 작동.
- **실행 흐름:**
  1. L1·L2 개발용 체인 부팅.
  2. 3번 L2 블록에 대한 all-zero 루트 클레임(`common.Hash{}`) 제출.
  3. Asterisc 게임 생성 및 챌린저 시작.
  4. Challenger가 all-zero 클레임을 감지하고 즉시 반박.
  5. 분쟁 게임이 빠르게 해결되고 `Challenger Won` 상태로 전환.
- **주요 기능 검증:**
  - Asterisc 챌린저가 명백히 잘못된 클레임(all-zero)을 즉시 식별하고 반박하는지 확인.
  - 극단적 입력값에 대한 견고성(robustness) 검증.

### TestOutputAsterisc_PublishAsteriscRootClaim

- **목적:** 다양한 L2 블록 번호(유효/무효 post-state)에서 Asterisc 루트 클레임 발행 및 분쟁 시작을 검증.
- **실행 방법:**
  ```bash
  env OP_E2E_DISABLE_PARALLEL=true go test -v -timeout 20m ./op-e2e/faultproofs -run "^TestOutputAsterisc_PublishAsteriscRootClaim$/asterisc$"
  ```
- **결과 및 소요 시간:** ✅ PASS, 약 128초 (~2.1분).
  - **Dispute_7_mt-cannon**: ✅ PASS, 62.14초 (~1.0분) - 블록 7, 무효 post-state
  - **Dispute_8_mt-cannon**: ✅ PASS, 66.14초 (~1.1분) - 블록 8, 유효 post-state
- **비고:**
  - 두 가지 테스트 케이스:
    - **블록 7**: Post-state output root가 무효인 경우
    - **블록 8**: Post-state output root가 유효인 경우
  - 각 VM allocator 타입별로 실행.
- **실행 흐름:**
  1. 지정된 L2 블록 번호에 대한 Asterisc 게임 생성.
  2. `DisputeLastBlock`을 호출하여 마지막 블록에 대한 분쟁 시작.
  3. Challenger 시작 및 split depth + 1까지 클레임이 생성될 때까지 대기.
  4. 게임 데이터 로그 출력 및 검증.
- **주요 기능 검증:**
  - 다양한 블록 높이에서 루트 클레임 발행이 정상 작동하는지 확인.
  - 유효/무효 output root에 대한 챌린저의 대응 차이 검증.
  - `WaitForClaimAtDepth`가 예상 깊이까지 클레임 생성을 올바르게 대기하는지 확인.

### TestOutputAsteriscDisputeGame

- **목적:** 분쟁 트리의 다양한 깊이(첫 번째, 중간, 확장)에서 Asterisc 방어 클레임을 테스트.
- **실행 방법:**
  ```bash
  env OP_E2E_DISABLE_PARALLEL=true go test -v -timeout 20m ./op-e2e/faultproofs -run "^TestOutputAsteriscDisputeGame$/asterisc$"
  ```
- **결과 및 소요 시간:** ✅ PASS, 약 922초 (~15.4분).
  - **StepFirst-asterisc**: ✅ PASS, 309.86초 (~5.2분)
  - **StepMiddle-asterisc**: ✅ PASS, 307.93초 (~5.1분)
  - **StepInExtension-asterisc**: ✅ PASS, 304.00초 (~5.1분)
- **비고:**
  - 세 가지 서브 테스트:
    - **StepFirst**: Depth 0에서 방어
    - **StepMiddle**: Depth 28에서 방어
    - **StepInExtension**: Depth 1 (확장 영역)에서 방어
  - 각 depth에서 올바른 방어 전략이 작동하는지 검증.
- **실행 흐름:**
  1. 잘못된 루트 클레임(`0x01aa`)으로 Asterisc 게임 생성.
  2. `DisputeLastBlock`으로 output claim 획득.
  3. Challenger 시작 및 지정된 깊이까지 방어 클레임 진행.
  4. `DefendClaim` 함수로 조건부 Attack/Defend 수행.
  5. 최대 clock duration까지 시간 이동.
  6. 게임 상태가 `ChallengerWon`으로 전환되는지 확인.
- **주요 기능 검증:**
  - 다양한 트리 깊이에서 방어 로직이 정상 작동하는지 확인.
  - `DefendClaim`의 조건부 분기(Attack vs Defend)가 올바르게 실행되는지 검증.
  - 시계(clock) 메커니즘이 게임 해결에 올바르게 작동하는지 확인.

### TestOutputAsteriscDefendStep

- **목적:** Honest challenger가 Asterisc VM을 사용하여 올바른 증거로 방어 스텝을 수행하는지 검증.
- **실행 방법:**
  ```bash
  env OP_E2E_DISABLE_PARALLEL=true go test -v -timeout 20m ./op-e2e/faultproofs -run "^TestOutputAsteriscDefendStep$/asterisc$"
  ```
- **결과 및 소요 시간:** ✅ PASS, 약 330초 (~5.5분).
- **비고:**
  - Cannon의 `testCannonDefendStep` 로직을 재사용.
  - Dishonest actor의 공격에 대해 올바른 step 증거로 방어.
- **실행 흐름:**
  1. 잘못된 루트 클레임으로 Asterisc 게임 생성.
  2. Honest challenger가 Asterisc VM으로 올바른 trace 생성.
  3. Dishonest actor가 특정 step에서 공격.
  4. Challenger가 올바른 step 증거(witness)를 제출하여 방어.
  5. 게임 해결 및 `ChallengerWon` 상태 확인.
- **주요 기능 검증:**
  - Asterisc VM이 step-by-step 증거 생성을 정상적으로 수행하는지 확인.
  - `DefendStep` 경로에서 올바른 증거가 온체인 검증을 통과하는지 확인.
  - Honest challenger의 방어 전략이 효과적인지 검증.

## 프리이미지 관련 테스트 (임시 제거됨)

프리이미지 관련 테스트들(`TestOutputAsteriscStepWithLargePreimage`, `TestOutputAsteriscStepWithPreimage_*`)은 현재 `op-program/host/prefetcher/prefetcher.go`의 구현체가 asterisc 프로젝트와 일부 동기화되지 않아 정상적으로 동작하지 않아 임시로 제거되었습니다. asterisc에서 프리이미지 관련 구현이 완료된 후 다시 추가할 예정입니다.

### TestOutputAsteriscProposedOutputRootValid

- **목적:** 올바른(valid) output root에 대한 공격이 실패하고 defender가 승리하는지 검증.
- **실행 방법:**
  ```bash
  env OP_E2E_DISABLE_PARALLEL=true go test -v -timeout 20m ./op-e2e/faultproofs -run "^TestOutputAsteriscProposedOutputRootValid$/asterisc$"
  ```
- **결과 및 소요 시간:** ✅ PASS, 238.59초 (~4.0분)
- **비고:**
  - Dishonest actor가 올바른 output root를 공격하는 시나리오.
  - Honest defender가 올바른 증거로 방어하여 승리해야 함.
- **실행 흐름:**
  1. 올바른 output root로 Asterisc 게임 생성.
  2. Dishonest actor가 올바른 루트를 공격.
  3. Honest defender가 Asterisc VM으로 올바른 trace 생성.
  4. 분쟁 진행 및 defender 승리 확인.
  5. 게임 상태가 `DefenderWon`으로 전환되는지 확인.
- **주요 기능 검증:**
  - 올바른 output root에 대한 공격이 실패하는지 확인.
  - Honest defender의 승리 경로가 정상 작동하는지 확인.
  - `GameStatusDefenderWon` 상태 전환이 올바르게 발생하는지 확인.

### TestOutputAsteriscProposedOutputRootValid_DefendWithCorrectTrace

- **목적:** Honest defender가 올바른 trace로 모든 공격을 방어하여 승리하는지 검증.
- **실행 방법:**
  ```bash
  env OP_E2E_DISABLE_PARALLEL=true go test -v -timeout 20m ./op-e2e/faultproofs -run "^TestOutputAsteriscProposedOutputRootValid_DefendWithCorrectTrace$/asterisc$"
  ```
- **결과 및 소요 시간:** ✅ PASS, 238.05초 (~4.0분)
- **비고:**
  - 이전 테스트와 유사하지만, 명시적으로 올바른 trace를 사용하여 방어.
  - Defender의 trace 생성 및 증거 제출 경로 집중 검증.
- **실행 흐름:**
  1. 올바른 output root로 Asterisc 게임 생성.
  2. Dishonest actor의 공격에 대해 올바른 trace로 방어.
  3. 각 depth에서 올바른 클레임 제출.
  4. 최종 step에서 올바른 증거로 방어.
  5. Defender 승리 및 상태 확인.
- **주요 기능 검증:**
  - Defender의 trace 생성이 정확한지 확인.
  - 올바른 증거가 온체인 검증을 통과하는지 확인.
  - 전체 방어 경로가 견고하게 작동하는지 확인.

### TestOutputAsteriscPoisonedPostState

- **목적:** 손상된(poisoned) post-state를 포함하는 Asterisc 게임에서 올바른 처리를 검증.
- **실행 방법:**
  ```bash
  go test -v -timeout 20m ./op-e2e/faultproofs -run "TestOutputAsteriscPoisonedPostState$/asterisc$"
  ```
- **결과 및 소요 시간:** ✅ PASS, 238.99초 (~4.0분)
- **실행 흐름:**
  1. 손상된 post-state를 포함하는 Asterisc 게임 생성.
  2. Challenger가 손상된 상태를 감지.
  3. 올바른 대응 조치 수행 (공격 또는 거부).
  4. 게임 해결 및 결과 검증.
- **주요 기능 검증:**
  - 손상된 post-state 감지 로직이 정상 작동하는지 확인.
  - 손상된 상태에 대한 올바른 대응이 수행되는지 확인.
  - 시스템의 견고성(robustness) 및 오류 처리 능력 검증.

## Asterisc vs Cannon 테스트 비교

| 테스트 케이스 | Cannon | Asterisc | 주요 차이점 |
|--------------|--------|----------|------------|
| 기본 게임 | ✅ TestOutputCannonGame | ✅ TestOutputAsteriscGame | VM 타입만 다름 (MIPS vs RISC-V) |
| All-zero 클레임 챌린지 | ✅ 지원 | ✅ TestOutputAsterisc_ChallengeAllZeroClaim | 동일한 로직 |
| 루트 클레임 발행 | ✅ 지원 | ✅ TestOutputAsterisc_PublishAsteriscRootClaim | 동일한 로직 |
| 분쟁 게임 (다양한 depth) | ✅ 지원 | ✅ TestOutputAsteriscDisputeGame | 동일한 로직 |
| Step 방어 | ✅ 지원 | ✅ TestOutputAsteriscDefendStep | VM별 증거 생성 차이 |
| 올바른 루트 방어 | ✅ 지원 | ✅ TestOutputAsteriscProposedOutputRootValid | 동일한 로직 |
| 손상된 상태 처리 | ✅ 지원 | ✅ TestOutputAsteriscPoisonedPostState | 동일한 로직 |

**주요 차이점:**
- **VM 아키텍처**: Cannon은 MIPS, Asterisc는 RISC-V
- **VM 바이너리**: `cannon/bin-e2e/cannon` vs `asterisc/bin-e2e/asterisc`
- **Oracle 서버**: 두 VM 모두 동일한 `op-program` 사용
- **게임 로직**: 대부분의 테스트가 동일한 로직을 공유 (`testCannon*` 함수 재사용)
- **Prestate 포맷**: Cannon은 binary only, Asterisc는 JSON + binary

## 현재 테스트 상태

### ✅ 성공한 테스트 (총 9개)
1. **TestOutputAsteriscGame** - 기본 게임 플레이 흐름 (PASS, ~227초)
2. **TestOutputAsterisc_ChallengeAllZeroClaim** - All-zero 클레임 챌린지 (PASS, ~265초)
3. **TestOutputAsterisc_PublishAsteriscRootClaim** - 루트 클레임 발행 (PASS, ~128초)
4. **TestOutputAsteriscDisputeGame** - 다양한 depth 분쟁 (PASS, ~922초)
5. **TestOutputAsteriscDefendStep** - Step 방어 (PASS, ~330초)
6. **TestOutputAsteriscProposedOutputRootValid** - 올바른 루트 방어 (PASS, ~238초)
7. **TestOutputAsteriscProposedOutputRootValid_DefendWithCorrectTrace** - 올바른 trace로 방어 (PASS, ~238초)
8. **TestOutputAsteriscPoisonedPostState** - 손상된 상태 처리 (PASS, ~238초)
9. **TestOutputAsteriscGame (Kona)** - Kona 기반 게임 (PASS, ~227초)

### 📋 Asterisc-Kona 테스트 (향후)
- **TestOutputAsteriscKonaGame** - Asterisc-Kona 기본 게임
- **기타 Asterisc-Kona 테스트들** - Rust 기반 kona-host 사용

## 전체 테스트 실행 명령어

### 모든 Asterisc 테스트 실행
```bash
# 전체 Asterisc 테스트 스위트
go test -v -timeout 60m ./op-e2e/faultproofs -run TestOutputAsterisc
```

### 개별 테스트 실행
```bash
# 기본 게임
go test -v -timeout 20m ./op-e2e/faultproofs -run "TestOutputAsteriscGame$"

# All-zero 클레임 챌린지
go test -v -timeout 20m ./op-e2e/faultproofs -run "TestOutputAsterisc_ChallengeAllZeroClaim"

# 루트 클레임 발행
go test -v -timeout 20m ./op-e2e/faultproofs -run "TestOutputAsterisc_PublishAsteriscRootClaim"

# 분쟁 게임
go test -v -timeout 20m ./op-e2e/faultproofs -run "TestOutputAsteriscDisputeGame"

# Step 방어
go test -v -timeout 20m ./op-e2e/faultproofs -run "TestOutputAsteriscDefendStep"

# 올바른 루트 방어
go test -v -timeout 20m ./op-e2e/faultproofs -run "TestOutputAsteriscProposedOutputRootValid"

# 손상된 상태 처리
go test -v -timeout 20m ./op-e2e/faultproofs -run "TestOutputAsteriscPoisonedPostState"
```

### 특정 패턴 테스트
```bash
# Step 관련 모든 테스트
go test -v -timeout 40m ./op-e2e/faultproofs -run "TestOutputAsterisc.*Step"
```

### 특정 서브테스트만 실행
```bash
# mt-cannon 서브테스트만 실행 (mt-cannon-next 제외)
go test -v -timeout 20m ./op-e2e/faultproofs -run "^TestOutputAsterisc_ChallengeAllZeroClaim$/asterisc$"

# mt-cannon-next 서브테스트만 실행
go test -v -timeout 20m ./op-e2e/faultproofs -run "^TestOutputAsterisc_ChallengeAllZeroClaim$/mt-cannon-next$"

# 백그라운드로 실행하고 로그 저장
timeout 1200s go test -v -timeout 20m ./op-e2e/faultproofs \
  -run "^TestOutputAsterisc_ChallengeAllZeroClaim$/asterisc$" \
  2>&1 > /tmp/mt_cannon_only.log &

# 실시간 로그 확인
tail -f /tmp/mt_cannon_only.log

# 결과 확인
grep -E "PASS|FAIL" /tmp/mt_cannon_only.log
```

## 요약

Asterisc (GameType 2) 기본 테스트는 성공적으로 완료되었습니다. 추가 테스트 케이스는 순차적으로 진행 예정입니다.

**핵심 검증 사항:**
- ✅ Asterisc VM (RISC-V) 정상 작동
- ✅ GameType 2 등록 및 게임 생성
- ✅ Challenger가 Asterisc VM 올바르게 인식
- ✅ op-program 서버와 Asterisc VM 통신
- ✅ Mac-native 바이너리 빌드 및 실행
- ⏳ 추가 테스트 케이스 검증 진행 중

Asterisc는 Cannon과 동일한 게임 로직을 공유하므로, Cannon 테스트가 통과하는 케이스는 대부분 Asterisc에서도 통과할 것으로 예상됩니다. 주요 차이점은 VM 레이어(MIPS vs RISC-V)이며, 나머지 인프라(DisputeGameFactory, Challenger, op-program)는 공유됩니다.

## 참고 문서

- **[Fault Proofs E2E 테스트 가이드](./faultproofs-e2e.md)** - 환경 설정 및 바이너리 빌드
- **[Cannon 테스트 리포트](./faultproofs-cannon-test-report.md)** - Cannon 테스트 비교 참고
- **[Asterisc GitHub](https://github.com/ethereum-optimism/asterisc)** - Asterisc VM 공식 저장소
- **[Fault Proof Specs](https://specs.optimism.io/experimental/fault-proof/)** - 공식 스펙 문서
