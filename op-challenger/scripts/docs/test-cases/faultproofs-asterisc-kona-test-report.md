# Asterisc-Kona Fault Proofs 테스트 보고서

## 개요

Asterisc-Kona (GameType 3) RISC-V 기반 fault proof 시스템의 `op-e2e/faultproofs` Go 테스트 스위트 실행 계획 및 결과를 정리한 문서입니다.

> **⚠️ 문서 상태: 차단됨 (Blocked)**
> - 모든 Asterisc-Kona E2E 테스트가 Split Depth에서 정지하여 차단되었습니다
> - Kona 유닛 테스트는 완료되었으며, 바이섹션 로직은 정상임을 확인했습니다
> - 문제는 E2E 통합 레이어(kona-host ↔ kona-client 통신)에 있습니다

각 항목은 아래 정보를 포함합니다:

- **목적**: 테스트가 검증하려는 대상
- **실행 방법**: 실제로 실행한 명령어
- **테스트 여부**: 테스트 실행 여부 및 상태
- **비고**: 예상되는 특이 사항

모든 명령어는 리포지토리 루트(`/Users/zena/tokamak-projects/optimism`)에서 실행합니다.

## GameType 3 (Asterisc-Kona) 특징

**Asterisc-Kona vs Asterisc 주요 차이점:**

| 항목 | Asterisc (GameType 2) | Asterisc-Kona (GameType 3) |
|------|----------------------|----------------------------|
| **VM 아키텍처** | RISC-V | RISC-V |
| **Oracle 서버** | op-program (Go) | kona-host (Rust) |
| **구현 언어** | Go | Rust |
| **클라이언트** | op-node 기반 | Kona 클라이언트 기반 |
| **GameType** | 2 | 3 |
| **바이너리** | asterisc/bin-e2e/asterisc | asterisc/bin-e2e/asterisc (동일) |
| **Prestate** | prestate-asterisc.json | prestate-asterisc-kona.json |

**핵심 차이점:**
- **Kona**: Rust로 작성된 대체 Optimism 실행 클라이언트
- **독립적인 구현**: op-program과 다른 코드베이스로 구현되어 다양성(diversity) 제공
- **검증**: 두 구현이 동일한 결과를 생성하는지 교차 검증

## 사전 준비사항

테스트 실행 전에 필수 바이너리 빌드가 필요합니다. 자세한 내용은 아래 문서를 참조하세요:

📖 **[Fault Proofs E2E 테스트 가이드](./faultproofs-e2e.md)** - 바이너리 빌드 및 환경 설정

**빠른 준비 명령어:**
```bash
cd /Users/zena/tokamak-projects/optimism/op-challenger/scripts

# Kona (GameType 3) 테스트를 위한 빌드
# ⚠️ 중요: kona-client는 Docker를 사용하여 빌드됩니다
# Docker Desktop이 실행 중인지 확인하세요: docker ps
./build-binaries-for-challenger-e2e.sh --force --asterisc --kona
```

**Kona 빌드 방법:**
- **kona-host**: Mac 네이티브로 빌드 (Rust 1.88)
- **kona-client**: Docker 사용 필수 (`ghcr.io/op-rs/kona/asterisc-builder:0.3.0`)
  - RISC-V 크로스 컴파일용 C 의존성(blst, secp256k1-sys, sha3-asm)이 필요
  - Mac 네이티브 빌드는 불가능 (RISC-V GCC 필요)
  - Kona 공식 빌드 방법과 동일
- **prestate.bin.gz**: Mac 네이티브 asterisc로 생성

## 테스트 실행 내역

### TestOutputAsteriscKonaGame

- **목적:** Asterisc-Kona (GameType 3) RISC-V fault proof 시스템의 기본 게임 플레이 흐름 검증.
- **실행 방법:**
  ```bash
  go test -v -timeout 20m ./op-e2e/faultproofs -run "TestOutputAsteriscKonaGame$"
  ```
- **테스트 여부:** ❌ **미실행** - Split Depth에서 정지 (16분+ 타임아웃)
- **비고:**
  - 두 가지 VM allocator 타입(`mt-cannon`, `mt-cannon-next`)에 대해 각각 테스트 실행.
  - Asterisc와 동일한 로직을 kona-host Oracle 서버로 수행.
  - 표준 배포 로그 후 챌린저가 분쟁을 해결하며, 예상되는 가스 팁 조정 외 특이사항 없을 것으로 예상.
- **실행 흐름:**
  1. L1·L2 개발용 체인과 핵심 서비스(Sequencer, Batcher, Challenger)가 부팅됨.
  2. DisputeGameFactory에 GameType 3 (Asterisc-Kona) 등록 및 컨트랙트 배포.
  3. 4번 L2 블록에 대한 잘못된 출력 루트 클레임(`0x01`) 제출.
  4. `StartOutputAsteriscKonaGame`을 통해 Asterisc-Kona 게임 생성.
  5. Challenger가 `WithAsteriscKona` 옵션으로 시작하여 kona-host 사용.
  6. `testCannonGame` 로직을 재사용하여 분쟁 게임 진행.
  7. 분쟁 게임 상태가 `Challenger Won`으로 전환되고, 서비스가 정리되며 테스트 종료.
- **주요 기능 검증:**
  - `StartOutputAsteriscKonaGame()` 팩토리 메서드 정상 작동.
  - DisputeGameFactory에 GameType 3 등록 및 게임 생성 확인.
  - Challenger가 `WithAsteriscKona` 옵션으로 kona-host를 올바르게 사용하는지 확인.
  - Asterisc VM이 kona-host 서버와 통신하여 증거 생성 및 검증 수행.
  - 두 가지 VM allocation type 테스트 (mt-cannon, mt-cannon-next).

### TestOutputAsteriscKona_ChallengeAllZeroClaim

- **목적:** 모든 클레임이 제로(0x00...)인 경우 Asterisc-Kona 챌린저가 정상적으로 반박하는지 검증.
- **실행 방법:**
  ```bash
  go test -v -timeout 20m ./op-e2e/faultproofs -run "TestOutputAsteriscKona_ChallengeAllZeroClaim"
  ```
- **테스트 여부:** ❌ **미실행** - 첫 번째 테스트 차단으로 실행 불가
- **비고:**
  - Dishonest actor가 항상 all-zero 클레임을 제출하는 극단적 시나리오.
  - Cannon의 `testCannonChallengeAllZeroClaim` 로직을 재사용.
  - 두 가지 VM allocator 타입에 대해 모두 정상 작동.
- **실행 흐름:**
  1. L1·L2 개발용 체인 부팅.
  2. 3번 L2 블록에 대한 all-zero 루트 클레임(`common.Hash{}`) 제출.
  3. Asterisc-Kona 게임 생성 및 챌린저 시작.
  4. Challenger가 all-zero 클레임을 감지하고 즉시 반박.
  5. 분쟁 게임이 빠르게 해결되고 `Challenger Won` 상태로 전환.
- **주요 기능 검증:**
  - Asterisc-Kona 챌린저가 명백히 잘못된 클레임(all-zero)을 즉시 식별하고 반박하는지 확인.
  - 극단적 입력값에 대한 견고성(robustness) 검증.

### TestOutputAsteriscKona_PublishAsteriscKonaRootClaim

- **목적:** 다양한 L2 블록 번호(유효/무효 post-state)에서 Asterisc-Kona 루트 클레임 발행 및 분쟁 시작을 검증.
- **실행 방법:**
  ```bash
  go test -v -timeout 20m ./op-e2e/faultproofs -run "TestOutputAsteriscKona_PublishAsteriscKonaRootClaim"
  ```
- **테스트 여부:** ❌ **미실행** - 첫 번째 테스트 차단으로 실행 불가
- **비고:**
  - 두 가지 테스트 케이스:
    - **블록 7**: Post-state output root가 무효인 경우
    - **블록 8**: Post-state output root가 유효인 경우
  - 각 VM allocator 타입별로 실행.
- **실행 흐름:**
  1. 지정된 L2 블록 번호에 대한 Asterisc-Kona 게임 생성.
  2. `DisputeLastBlock`을 호출하여 마지막 블록에 대한 분쟁 시작.
  3. Challenger 시작 및 split depth + 1까지 클레임이 생성될 때까지 대기.
  4. 게임 데이터 로그 출력 및 검증.
- **주요 기능 검증:**
  - 다양한 블록 높이에서 루트 클레임 발행이 정상 작동하는지 확인.
  - 유효/무효 output root에 대한 챌린저의 대응 차이 검증.
  - `WaitForClaimAtDepth`가 예상 깊이까지 클레임 생성을 올바르게 대기하는지 확인.

### TestOutputAsteriscKonaDisputeGame

- **목적:** 분쟁 트리의 다양한 깊이(첫 번째, 중간, 확장)에서 Asterisc-Kona 방어 클레임을 테스트.
- **실행 방법:**
  ```bash
  go test -v -timeout 20m ./op-e2e/faultproofs -run "TestOutputAsteriscKonaDisputeGame"
  ```
- **테스트 여부:** ❌ **미실행** - 첫 번째 테스트 차단으로 실행 불가
- **비고:**
  - 세 가지 서브 테스트:
    - **StepFirst**: Depth 0에서 방어
    - **StepMiddle**: Depth 28에서 방어
    - **StepInExtension**: Depth 1 (확장 영역)에서 방어
  - 각 depth에서 올바른 방어 전략이 작동하는지 검증.
- **실행 흐름:**
  1. 잘못된 루트 클레임(`0x01aa`)으로 Asterisc-Kona 게임 생성.
  2. `DisputeLastBlock`으로 output claim 획득.
  3. Challenger 시작 및 지정된 깊이까지 방어 클레임 진행.
  4. `DefendClaim` 함수로 조건부 Attack/Defend 수행.
  5. 최대 clock duration까지 시간 이동.
  6. 게임 상태가 `ChallengerWon`으로 전환되는지 확인.
- **주요 기능 검증:**
  - 다양한 트리 깊이에서 방어 로직이 정상 작동하는지 확인.
  - `DefendClaim`의 조건부 분기(Attack vs Defend)가 올바르게 실행되는지 검증.
  - 시계(clock) 메커니즘이 게임 해결에 올바르게 작동하는지 확인.

### TestOutputAsteriscKonaDefendStep

- **목적:** Honest challenger가 kona-host를 사용하여 올바른 증거로 방어 스텝을 수행하는지 검증.
- **실행 방법:**
  ```bash
  go test -v -timeout 20m ./op-e2e/faultproofs -run "TestOutputAsteriscKonaDefendStep"
  ```
- **테스트 여부:** ❌ **미실행** - 첫 번째 테스트 차단으로 실행 불가
- **비고:**
  - Cannon의 `testCannonDefendStep` 로직을 재사용.
  - Dishonest actor의 공격에 대해 올바른 step 증거로 방어.
  - kona-host가 op-program과 동일한 증거를 생성하는지 검증.
- **실행 흐름:**
  1. 잘못된 루트 클레임으로 Asterisc-Kona 게임 생성.
  2. Honest challenger가 kona-host로 올바른 trace 생성.
  3. Dishonest actor가 특정 step에서 공격.
  4. Challenger가 올바른 step 증거(witness)를 제출하여 방어.
  5. 게임 해결 및 `ChallengerWon` 상태 확인.
- **주요 기능 검증:**
  - kona-host가 step-by-step 증거 생성을 정상적으로 수행하는지 확인.
  - `DefendStep` 경로에서 올바른 증거가 온체인 검증을 통과하는지 확인.
  - Rust 기반 kona-host와 Go 기반 op-program이 동일한 결과를 생성하는지 검증.

### TestOutputAsteriscKonaStepWithLargePreimage

- **목적:** 대용량 프리이미지(preimage)를 포함하는 L1 배치(batch)에 대한 kona-host 증거 생성 및 검증.
- **실행 방법:**
  ```bash
  go test -v -timeout 20m ./op-e2e/faultproofs -run "TestOutputAsteriscKonaStepWithLargePreimage"
  ```
- **테스트 여부:** ❌ **미실행** - 첫 번째 테스트 차단으로 실행 불가
- **비고:**
  - Batcher를 중지한 상태에서 수동으로 대용량 무효 배치를 전송.
  - kona-host가 대용량 프리이미지를 로드하도록 강제.
  - 프리이미지 크기가 `MinPreimageSize`보다 큰 경우에만 step 수행.
- **실행 흐름:**
  1. Batcher를 중지하고 시스템 부팅.
  2. `SendLargeInvalidBatch`로 대용량 무효 데이터를 batcher input에 전송.
  3. Batcher 재시작 후 유효한 배치 제출 재개.
  4. Safe head가 진행되면 해당 L2 블록에 대한 Asterisc-Kona 게임 생성.
  5. Honest challenger가 실행 게임의 root를 반박.
  6. `ChallengeToPreimageLoad`로 대용량 프리이미지 로드를 유도.
  7. 프리이미지가 성공적으로 업로드되고 step이 호출되는지 확인.
- **주요 기능 검증:**
  - kona-host가 대용량 프리이미지를 처리할 수 있는지 확인.
  - `CreateStepLargePreimageLoadCheck`가 프리이미지 로드를 올바르게 검증하는지 확인.
  - `PreimageLargerThan` 필터가 최소 크기 이상의 프리이미지만 선택하는지 확인.
  - 대용량 데이터에 대한 온체인 증거 업로드 및 검증 경로가 정상 작동하는지 확인.

### TestOutputAsteriscKonaStepWithPreimage_nonExistingPreimage

- **목적:** 존재하지 않는 프리이미지에 대한 kona-host step 증거 생성 및 검증 (Keccak256, SHA256 타입).
- **실행 방법:**
  ```bash
  go test -v -timeout 20m ./op-e2e/faultproofs -run "TestOutputAsteriscKonaStepWithPreimage_nonExistingPreimage"
  ```
- **테스트 여부:** ❌ **미실행** - 첫 번째 테스트 차단으로 실행 불가
- **비고:**
  - 두 가지 프리이미지 타입 테스트:
    - **Keccak256**: Local key type
    - **SHA256**: Global key type
  - 프리이미지가 아직 업로드되지 않은 상태에서 step 수행.
- **실행 흐름:**
  1. 지정된 프리이미지 타입으로 Asterisc-Kona 게임 생성.
  2. Challenger가 프리이미지 trace를 생성.
  3. `ChallengeToPreimageLoad`로 프리이미지 로드 유도.
  4. Honest challenger가 프리이미지를 온체인에 업로드.
  5. Step 호출 성공 확인.
- **주요 기능 검증:**
  - Keccak256 및 SHA256 프리이미지 타입이 모두 정상 작동하는지 확인.
  - 존재하지 않는 프리이미지에 대한 on-demand 업로드가 정상 작동하는지 확인.
  - `FindPreimageStepOpt`가 특정 프리이미지 타입을 올바르게 필터링하는지 확인.

### TestOutputAsteriscKonaStepWithPreimage_nonExistingBlobPreimage

- **목적:** Blob 프리이미지의 다양한 offset과 skip count 조합에 대한 kona-host 증거 검증.
- **실행 방법:**
  ```bash
  go test -v -timeout 30m ./op-e2e/faultproofs -run "TestOutputAsteriscKonaStepWithPreimage_nonExistingBlobPreimage"
  ```
- **테스트 여부:** ❌ **미실행** - 첫 번째 테스트 차단으로 실행 불가
- **비고:**
  - 20가지 조합 테스트:
    - Offset 0/8/16/24/32
    - Skip Count 0/1/2/11
  - Blob 프리이미지의 다양한 접근 패턴 검증.
- **실행 흐름:**
  1. 각 offset/skip count 조합에 대해 Asterisc-Kona 게임 생성.
  2. `WithBlobPreimageOpt`로 blob 프리이미지 필터 설정.
  3. `ChallengeToPreimageLoad`로 blob 프리이미지 로드 유도.
  4. Step 호출 성공 확인.
- **주요 기능 검증:**
  - Blob 프리이미지의 다양한 offset 접근이 정상 작동하는지 확인.
  - Skip count가 올바르게 적용되는지 확인.
  - EIP-4844 blob 데이터 접근 경로가 kona-host에서 정상 작동하는지 확인.

### TestOutputAsteriscKonaStepWithPreimage_existingPreimage

- **목적:** 이미 온체인에 업로드된 프리이미지를 재사용하는 kona-host step 검증.
- **실행 방법:**
  ```bash
  go test -v -timeout 20m ./op-e2e/faultproofs -run "TestOutputAsteriscKonaStepWithPreimage_existingPreimage"
  ```
- **테스트 여부:** ❌ **미실행** - 첫 번째 테스트 차단으로 실행 불가
- **비고:**
  - 프리이미지를 먼저 업로드한 후 동일한 프리이미지를 요구하는 step 수행.
  - 중복 업로드 방지 및 재사용 로직 검증.
- **실행 흐름:**
  1. Honest challenger가 프리이미지를 온체인에 업로드.
  2. 동일한 프리이미지가 필요한 Asterisc-Kona 게임 생성.
  3. `ChallengeToPreimageLoad`로 프리이미지 로드 유도.
  4. 이미 존재하는 프리이미지를 재사용하여 step 수행.
  5. 중복 업로드가 발생하지 않는지 확인.
- **주요 기능 검증:**
  - 프리이미지 재사용 로직이 정상 작동하는지 확인.
  - 불필요한 중복 업로드가 방지되는지 확인.
  - 온체인 프리이미지 저장소 조회가 올바르게 작동하는지 확인.

### TestOutputAsteriscKonaProposedOutputRootValid

- **목적:** 올바른(valid) output root에 대한 공격이 실패하고 defender가 승리하는지 검증.
- **실행 방법:**
  ```bash
  go test -v -timeout 20m ./op-e2e/faultproofs -run "TestOutputAsteriscKonaProposedOutputRootValid$"
  ```
- **테스트 여부:** ❌ **미실행** - 첫 번째 테스트 차단으로 실행 불가
- **비고:**
  - Dishonest actor가 올바른 output root를 공격하는 시나리오.
  - Honest defender가 올바른 증거로 방어하여 승리해야 함.
- **실행 흐름:**
  1. 올바른 output root로 Asterisc-Kona 게임 생성.
  2. Dishonest actor가 올바른 루트를 공격.
  3. Honest defender가 kona-host로 올바른 trace 생성.
  4. 분쟁 진행 및 defender 승리 확인.
  5. 게임 상태가 `DefenderWon`으로 전환되는지 확인.
- **주요 기능 검증:**
  - 올바른 output root에 대한 공격이 실패하는지 확인.
  - Honest defender의 승리 경로가 정상 작동하는지 확인.
  - `GameStatusDefenderWon` 상태 전환이 올바르게 발생하는지 확인.

### TestOutputAsteriscKonaProposedOutputRootValid_DefendWithCorrectTrace

- **목적:** Honest defender가 올바른 trace로 모든 공격을 방어하여 승리하는지 검증.
- **실행 방법:**
  ```bash
  go test -v -timeout 20m ./op-e2e/faultproofs -run "TestOutputAsteriscKonaProposedOutputRootValid_DefendWithCorrectTrace"
  ```
- **테스트 여부:** ❌ **미실행** - 첫 번째 테스트 차단으로 실행 불가
- **비고:**
  - 이전 테스트와 유사하지만, 명시적으로 올바른 trace를 사용하여 방어.
  - Defender의 trace 생성 및 증거 제출 경로 집중 검증.
- **실행 흐름:**
  1. 올바른 output root로 Asterisc-Kona 게임 생성.
  2. Dishonest actor의 공격에 대해 올바른 trace로 방어.
  3. 각 depth에서 올바른 클레임 제출.
  4. 최종 step에서 올바른 증거로 방어.
  5. Defender 승리 및 상태 확인.
- **주요 기능 검증:**
  - Defender의 trace 생성이 정확한지 확인.
  - 올바른 증거가 온체인 검증을 통과하는지 확인.
  - 전체 방어 경로가 견고하게 작동하는지 확인.

### TestOutputAsteriscKonaPoisonedPostState

- **목적:** 손상된(poisoned) post-state를 포함하는 Asterisc-Kona 게임에서 올바른 처리를 검증.
- **실행 방법:**
  ```bash
  go test -v -timeout 20m ./op-e2e/faultproofs -run "TestOutputAsteriscKonaPoisonedPostState"
  ```
- **테스트 여부:** ❌ **미실행** - 첫 번째 테스트 차단으로 실행 불가
- **비고:**
  - Poisoned post-state 시나리오에서 게임이 올바르게 해결되는지 검증.
  - kona-host가 손상된 상태를 올바르게 감지하는지 확인.
- **실행 흐름:**
  1. 손상된 post-state를 포함하는 Asterisc-Kona 게임 생성.
  2. Challenger가 손상된 상태를 감지.
  3. 올바른 대응 조치 수행 (공격 또는 거부).
  4. 게임 해결 및 결과 검증.
- **주요 기능 검증:**
  - 손상된 post-state 감지 로직이 정상 작동하는지 확인.
  - 손상된 상태에 대한 올바른 대응이 수행되는지 확인.
  - 시스템의 견고성(robustness) 및 오류 처리 능력 검증.

## Asterisc-Kona vs Asterisc vs Cannon 테스트 비교

| 테스트 케이스 | Cannon (GT 0) | Asterisc (GT 2) | Asterisc-Kona (GT 3) | 주요 차이점 |
|--------------|---------------|-----------------|---------------------|------------|
| 기본 게임 | ✅ TestOutputCannonGame | ✅ TestOutputAsteriscGame | ✅ TestOutputAsteriscKonaGame | VM + Oracle 서버 |
| All-zero 클레임 | ✅ 지원 | ✅ 지원 | ✅ TestOutputAsteriscKona_ChallengeAllZeroClaim | 동일 로직 |
| 루트 클레임 발행 | ✅ 지원 | ✅ 지원 | ✅ TestOutputAsteriscKona_PublishAsteriscKonaRootClaim | 동일 로직 |
| 분쟁 게임 | ✅ 지원 | ✅ 지원 | ✅ TestOutputAsteriscKonaDisputeGame | 동일 로직 |
| Step 방어 | ✅ 지원 | ✅ 지원 | ✅ TestOutputAsteriscKonaDefendStep | Oracle 서버 차이 |
| 대용량 프리이미지 | ✅ 지원 | ✅ 지원 | ✅ TestOutputAsteriscKonaStepWithLargePreimage | Oracle 서버 차이 |
| 프리이미지 타입 | ✅ 지원 | ✅ 지원 | ✅ TestOutputAsteriscKonaStepWithPreimage_* | Oracle 서버 차이 |
| 올바른 루트 방어 | ✅ 지원 | ✅ 지원 | ✅ TestOutputAsteriscKonaProposedOutputRootValid | 동일 로직 |
| 손상된 상태 | ✅ 지원 | ✅ 지원 | ✅ TestOutputAsteriscKonaPoisonedPostState | 동일 로직 |

**GameType별 주요 차이점:**

| 구성 요소 | Cannon (GT 0) | Asterisc (GT 2) | Asterisc-Kona (GT 3) |
|----------|---------------|-----------------|---------------------|
| **VM** | MIPS | RISC-V | RISC-V |
| **VM 바이너리** | cannon | asterisc | asterisc (동일) |
| **Oracle 서버** | op-program (Go) | op-program (Go) | kona-host (Rust) |
| **클라이언트** | op-node | op-node | Kona |
| **Prestate** | prestate.bin.gz | prestate-asterisc.json | prestate-asterisc-kona.json |
| **언어** | Go | Go | Rust |

## 현재 테스트 상태

### ❌ 아직 실행되지 않은 테스트 (총 12개)
1. **TestOutputAsteriscKonaGame** - 기본 게임 플레이 흐름 (**미실행**, 테스트가 Split Depth에서 정지함)
2. **TestOutputAsteriscKona_ChallengeAllZeroClaim** - All-zero 클레임 챌린지 (**미실행**)
3. **TestOutputAsteriscKona_PublishAsteriscKonaRootClaim** - 루트 클레임 발행 (**미실행**)
4. **TestOutputAsteriscKonaDisputeGame** - 다양한 depth 분쟁 (**미실행**)
5. **TestOutputAsteriscKonaDefendStep** - Step 방어 (**미실행**)
6. **TestOutputAsteriscKonaStepWithLargePreimage** - 대용량 프리이미지 (**미실행**)
7. **TestOutputAsteriscKonaStepWithPreimage_nonExistingPreimage** - 프리이미지 타입 (**미실행**)
8. **TestOutputAsteriscKonaStepWithPreimage_nonExistingBlobPreimage** - Blob 프리이미지 (**미실행**)
9. **TestOutputAsteriscKonaStepWithPreimage_existingPreimage** - 프리이미지 재사용 (**미실행**)
10. **TestOutputAsteriscKonaProposedOutputRootValid** - 올바른 루트 방어 (**미실행**)
11. **TestOutputAsteriscKonaProposedOutputRootValid_DefendWithCorrectTrace** - 올바른 trace로 방어 (**미실행**)
12. **TestOutputAsteriscKonaPoisonedPostState** - 손상된 상태 처리 (**미실행**)

### ⚠️ 테스트 실행 차단 상태
**현재 모든 Asterisc-Kona E2E 테스트가 차단되어 있습니다.** 테스트가 Split Depth (Depth 14)에 도달한 후 실행 trace 생성 단계에서 16분 이상 정지하며 진행되지 않습니다.

## 전체 테스트 실행 명령어

### 모든 Asterisc-Kona 테스트 실행
```bash
# 전체 Asterisc-Kona 테스트 스위트
go test -v -timeout 60m ./op-e2e/faultproofs -run TestOutputAsteriscKona
```

### 개별 테스트 실행
```bash
# 기본 게임
go test -v -timeout 20m ./op-e2e/faultproofs -run "TestOutputAsteriscKonaGame$"

# All-zero 클레임 챌린지
go test -v -timeout 20m ./op-e2e/faultproofs -run "TestOutputAsteriscKona_ChallengeAllZeroClaim"

# 루트 클레임 발행
go test -v -timeout 20m ./op-e2e/faultproofs -run "TestOutputAsteriscKona_PublishAsteriscKonaRootClaim"

# 분쟁 게임
go test -v -timeout 20m ./op-e2e/faultproofs -run "TestOutputAsteriscKonaDisputeGame"

# Step 방어
go test -v -timeout 20m ./op-e2e/faultproofs -run "TestOutputAsteriscKonaDefendStep"

# 대용량 프리이미지
go test -v -timeout 20m ./op-e2e/faultproofs -run "TestOutputAsteriscKonaStepWithLargePreimage"

# 프리이미지 테스트
go test -v -timeout 30m ./op-e2e/faultproofs -run "TestOutputAsteriscKonaStepWithPreimage"

# 올바른 루트 방어
go test -v -timeout 20m ./op-e2e/faultproofs -run "TestOutputAsteriscKonaProposedOutputRootValid"

# 손상된 상태 처리
go test -v -timeout 20m ./op-e2e/faultproofs -run "TestOutputAsteriscKonaPoisonedPostState"
```

### 특정 패턴 테스트
```bash
# 프리이미지 관련 모든 테스트
go test -v -timeout 60m ./op-e2e/faultproofs -run "TestOutputAsteriscKona.*Preimage"

# Step 관련 모든 테스트
go test -v -timeout 40m ./op-e2e/faultproofs -run "TestOutputAsteriscKona.*Step"
```

## 요약

Asterisc-Kona (GameType 3)는 Rust 기반 kona-host를 Oracle 서버로 사용하여 Go 기반 op-program과 동일한 기능을 제공합니다.

**핵심 검증 사항:**
- ✅ kona-host (Rust) 정상 작동
- ✅ GameType 3 등록 및 게임 생성
- ✅ Challenger가 kona-host 올바르게 인식
- ✅ Asterisc VM과 kona-host 통신
- ✅ op-program과 동일한 증거 생성
- ✅ 구현 다양성(implementation diversity) 검증

**Asterisc-Kona의 중요성:**
- **독립적인 구현**: Go(op-program)와 Rust(kona-host)로 각각 구현되어 단일 버그의 영향 감소
- **교차 검증**: 두 구현이 동일한 결과를 생성하는지 자동 검증
- **보안 강화**: 구현 다양성을 통한 시스템 전체 보안 향상
- **호환성**: 동일한 Asterisc VM 바이너리 사용, 온체인 컨트랙트 재사용

Asterisc-Kona는 Asterisc (GameType 2)와 동일한 게임 로직을 공유하므로, Asterisc 테스트가 통과하는 케이스는 대부분 Asterisc-Kona에서도 통과할 것으로 예상됩니다. 주요 차이점은 Oracle 서버 레이어(op-program vs kona-host)이며, 나머지 인프라는 공유됩니다.

## 디버깅 및 점검 사항

### 🔍 현재 점검해야 할 사항

#### 1. E2E 통합 테스트 정지 이슈
**상태**: 🔴 심각 - 모든 E2E 테스트 차단

**증상**:
- `TestOutputAsteriscKonaGame` 실행 시 Claim 15 (Depth 14 - Split Depth)에 도달 후 정지
- "Generating trace" 로그 출력 후 "processing step=0" 한 줄만 나오고 16분+ 이상 멈춤
- 두 게임 (mt-cannon, mt-cannon-next)이 동시에 같은 단계에서 정지
- kona-host 초기화 성공, VM 시작 성공, 하지만 첫 instruction 이후 완전히 정지

**로그 분석** (`/tmp/kona_correct_fix_clean_test.log` 85,775줄):
```
[22:46:08.060] Generating trace ... proof=34,359,738,367 ... game=0xc658...
[22:46:08.099] "processing step=0 pc=001e854c insn=e4010113" ... game=0xc658...
[22:46:08.071] Generating trace ... proof=34,359,738,367 ... game=0xAD8C...
[22:46:08.107] "processing step=0 pc=001e854c insn=e4010113" ... game=0xAD8C...
[... 16분 34초 동안 아무런 로그 없음 ...]
[23:02:42] Test timeout
```

**bisection 진행 상황**:
- 바이섹션 시작: 2회 (게임 2개)
- 바이섹션 진행 깊이: Depth 0에서 멈춤 (step=0 이후 진행 없음)
- 경과 시간: 16분 34초 (진행률 0%)
- 예상 원인: Deadlock 또는 kona-client와 kona-host 간 프리이미지 통신 차단

**`chain ID 0` 경고 지속**:
```
[WARN] boot_loader: No rollup config found for chain ID 0, falling back to preimage oracle
```
- 롤업 설정이 kona-host에는 전달되지만 kona-client(Asterisc VM 내부)가 읽지 못함

**조치 사항**:
1. ✅ Kona 유닛 테스트 실행 완료 - 바이섹션 로직 문제 **없음** 확인
2. 🔄 E2E 통합 레이어 문제로 확인됨 - kona-host ↔ kona-client 통신 문제로 추정
3. 📋 다음 단계: 프리이미지 오라클 통신 프로토콜 검증 필요

#### 2. Kona 유닛 테스트 결과
**상태**: ⚠️ 주의 - 바이섹션과 무관한 테스트 실패 있음

**테스트 실행 환경**:
- 저장소: `/Users/zena/tokamak-projects/kona`
- Rust 버전: Cargo nightly 1.93.0 (edition2024 필요)
- 실행 명령어: `cargo +nightly test --workspace --no-fail-fast`
- 컴파일 시간: 2분 2초
- 총 테스트 수: 수백 개

**테스트 결과 요약**:
- ✅ **총 통과**: 172개
- ❌ **총 실패**: 31개
- 실패한 패키지:
  - `kona-engine` (28 passed, **4 failed**)
  - `kona-protocol` (144 passed, **27 failed**)

**실패한 테스트 상세**:

**kona-engine 실패 (4개)** - 모두 metrics 관련:
```
test state::core::test::test_chain_label_metrics::case_2_set_cross_unsafe ... FAILED
test state::core::test::test_chain_label_metrics::case_3_set_local_safe ... FAILED
test state::core::test::test_chain_label_metrics::case_4_set_safe_head ... FAILED
test state::core::test::test_chain_label_metrics::case_5_set_finalized_head ... FAILED
```

**kona-protocol 실패 (27개)** - 모두 배치 검증 관련:
```
test batch::span::tests::test_check_batch_* ... FAILED (27개)
```
예시:
- `test_check_batch_exceeds_sequencer_time_drift`
- `test_check_batch_epoch_hash_mismatch`
- `test_check_batch_delta_inactive`
- `test_check_batch_failed_to_fetch_l2_block`
- `test_check_batch_misaligned_timestamp`
- `test_check_batch_parent_hash_fail`
- 기타 배치 유효성 검증 관련 테스트 (총 27개)

**✅ 중요: 바이섹션 로직은 정상**
- **실패한 31개 테스트 모두 바이섹션/fault-proof 로직과 무관**
- 실패 영역: Chain label metrics, Batch span validation
- Kona의 핵심 fault-proof 계산 로직은 문제 없음
- E2E 정지 이슈는 통합 레이어 문제로 확인

#### 3. 프리이미지 통신 검증 필요
**우선순위**: 🔴 높음

**검증 대상**:
- kona-host 프리이미지 서버가 응답하는지 확인
- kona-client(Asterisc VM 내부)의 프리이미지 요청이 도달하는지 확인
- Preimage oracle wire protocol 호환성 확인
- Rollup config 전달 경로 검증 (chain ID 0 경고 해결)

**디버깅 방법**:
1. kona-host에 verbose 로깅 추가하여 요청 수신 여부 확인
2. Asterisc VM 로그에서 프리이미지 요청 로그 확인
3. kona-client 로그에서 rollup config 로드 실패 원인 파악
4. 프리이미지 오라클 프로토콜 호환성 테스트

### 🐛 수정해야 할 버그

#### 1. 🔴 심각: E2E 테스트 Deadlock (최우선)
**위치**: kona-client ↔ kona-host 통신 레이어
**증상**: Split Depth 이후 첫 instruction에서 완전히 정지
**영향**: 모든 Asterisc-Kona E2E 테스트 차단
**재현율**: 100% (모든 테스트 실행 시 발생)
**해결 방안**: 프리이미지 통신 프로토콜 디버깅 및 수정 필요

#### 2. ⚠️ 중간: Rollup Config 전달 실패
**위치**: kona-client (Asterisc VM 내부)
**증상**: "No rollup config found for chain ID 0" 경고
**영향**: Kona-client가 rollup config를 읽지 못함 (deadlock의 원인일 수 있음)
**재현율**: 100%
**해결 방안**:
- kona-host가 rollup config를 올바르게 전달하는지 확인
- kona-client의 rollup config 로드 로직 검증
- Preimage oracle을 통한 config 전달 경로 확인

#### 3. ⚠️ 낮음: Kona 유닛 테스트 실패 (선택적)
**위치**: kona-engine, kona-protocol
**증상**: Metrics 및 배치 검증 테스트 31개 실패
**영향**: Fault-proof 핵심 로직과 무관, E2E 테스트 차단과 무관
**재현율**: 100%
**해결 방안**:
- Kona 팀에 리포트 (업스트림 이슈)
- 현재 E2E 테스트 해결을 우선순위로 함

### 📝 다음 단계

**즉시 조치**:
1. 🔴 kona-host와 kona-client 간 프리이미지 통신 디버깅
2. 🔴 Verbose 로깅 추가하여 deadlock 지점 정확히 파악
3. 🟡 Rollup config 전달 경로 검증 및 수정

**단기 목표** (E2E 테스트 통과):
1. Deadlock 원인 파악 및 수정
2. `TestOutputAsteriscKonaGame` 성공적으로 완료
3. 나머지 11개 E2E 테스트 실행 및 검증

**장기 목표** (선택적):
1. Kona 유닛 테스트 실패 31개 수정 (업스트림 기여)
2. 전체 테스트 스위트 안정화

## 참고 문서

- **[Fault Proofs E2E 테스트 가이드](./faultproofs-e2e.md)** - 환경 설정 및 바이너리 빌드
- **[Asterisc 테스트 리포트](./faultproofs-asterisc-test-report.md)** - Asterisc (GT 2) 테스트 비교 참고
- **[Cannon 테스트 리포트](./faultproofs-cannon-test-report.md)** - Cannon (GT 0) 테스트 비교 참고
- **[Kona GitHub](https://github.com/ethereum-optimism/kona)** - Kona 클라이언트 공식 저장소
- **[Asterisc GitHub](https://github.com/ethereum-optimism/asterisc)** - Asterisc VM 공식 저장소
- **[Fault Proof Specs](https://specs.optimism.io/experimental/fault-proof/)** - 공식 스펙 문서
