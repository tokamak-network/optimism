# Asterisc & Asterisc-Kona E2E Tests

## 개요

이 디렉토리에는 Asterisc (GameType 2)와 Asterisc-Kona (GameType 3) fault proof 시스템을 위한 E2E 테스트가 포함되어 있습니다.

## 테스트 파일

### 1. `output_asterisc_test.go` - Asterisc (GameType 2)
RISC-V 기반 fault proof VM을 사용하는 기본 Asterisc 게임 테스트

### 2. `output_asterisc_kona_test.go` - Asterisc-Kona (GameType 3)
Kona 클라이언트와 통합된 RISC-V fault proof VM 테스트

## 테스트 케이스

각 파일은 다음 테스트 케이스를 포함합니다:

### 기본 게임 테스트
- `TestOutputAsteriscGame` / `TestOutputAsteriscKonaGame`
  - 기본 게임 플레이 흐름 테스트
  - Honest actor vs Dishonest actor 시나리오

- `TestOutputAsterisc_ChallengeAllZeroClaim`
  - 모든 클레임이 제로인 경우 챌린지 테스트

- `TestOutputAsterisc_PublishRootClaim`
  - 다양한 L2 블록 번호에서 루트 클레임 발행 테스트

### 분쟁 게임 테스트
- `TestOutputAsteriscDisputeGame`
  - StepFirst: 첫 번째 스텝에서 방어
  - StepMiddle: 중간 depth에서 방어
  - StepInExtension: 확장 depth에서 방어

- `TestOutputAsteriscDefendStep`
  - Honest challenger의 방어 스텝 테스트

### 프리이미지 테스트
- `TestOutputAsteriscStepWithLargePreimage`
  - 큰 프리이미지 로드 및 검증

- `TestOutputAsteriscStepWithPreimage_nonExistingPreimage`
  - Keccak256 및 SHA256 프리이미지 타입 테스트

- `TestOutputAsteriscStepWithPreimage_nonExistingBlobPreimage`
  - Blob 프리이미지의 다양한 offset과 skip count 조합 테스트

- `TestOutputAsteriscStepWithPreimage_existingPreimage`
  - 기존 프리이미지 재사용 테스트

### 유효성 검증 테스트
- `TestOutputAsteriscProposedOutputRootValid`
  - 올바른 output root에 대한 공격/방어 테스트

- `TestOutputAsteriscPoisonedPostState`
  - 손상된 포스트 스테이트 처리 테스트

## 실행 방법

### 전체 Asterisc 테스트 실행
```bash
go test ./op-e2e/faultproofs -run TestOutputAsterisc -v
```

### 전체 Asterisc-Kona 테스트 실행
```bash
go test ./op-e2e/faultproofs -run TestOutputAsteriscKona -v
```

### 특정 테스트만 실행
```bash
# 기본 게임 테스트만
go test ./op-e2e/faultproofs -run TestOutputAsteriscGame -v

# 프리이미지 테스트만
go test ./op-e2e/faultproofs -run TestOutputAsteriscStepWithPreimage -v
```

### VM 타입별 실행 (ALLOCATOR_TYPE)
테스트는 `RunTestAcrossVmTypes`를 사용하여 여러 allocator 타입에 걸쳐 실행됩니다:
```bash
# 특정 allocator로 테스트
OP_E2E_ALLOC_TYPE=basic go test ./op-e2e/faultproofs -run TestOutputAsteriscGame -v
```

## 사전 요구사항

### 1. 모든 필수 바이너리 한번에 빌드 (권장)
```bash
cd /Users/zena/tokamak-projects/optimism/op-challenger/scripts
./build-binaries-for-challenger.sh --asterisc
```

이 스크립트는 다음을 자동으로 빌드합니다:
- `cannon/bin/cannon` - Cannon VM
- `op-program/bin/op-program` - Oracle 서버 (Cannon & Asterisc 공통)
- `op-program/bin/prestate.bin.gz` - Cannon prestate
- `asterisc/bin/asterisc` - Asterisc VM
- `op-program/bin/prestate-asterisc.json` - Asterisc prestate

### 2. 필수 바이너리 확인
```bash
# Cannon
ls -la cannon/bin/cannon
ls -la op-program/bin/op-program

# Asterisc
ls -la asterisc/bin/asterisc
ls -la op-program/bin/prestate-asterisc.json
```

**중요**: Asterisc는 `op-program`을 **Cannon과 동일하게 사용**합니다!
- ❌ `op-program-rv64`는 존재하지 않습니다
- ✅ Asterisc는 `op-program`을 그대로 사용

### 4. Kona (Asterisc-Kona 전용)
```bash
# Kona 저장소 클론 및 빌드
git clone https://github.com/ethereum-optimism/kona.git
cd kona

# Asterisc 타겟으로 빌드
make build-asterisc

# 바이너리 확인
ls -la ./target/riscv64gc-unknown-linux-gnu/release/kona-host
```

## 테스트 환경 설정

### Challenger 옵션
테스트는 다음 challenger 옵션을 사용합니다:

```go
// Asterisc 게임용
challenger.WithAsterisc(t, system)
challenger.WithFactoryAddress(factoryAddr)
challenger.WithGameAddress(gameAddr)

// Asterisc-Kona 게임용
challenger.WithAsteriscKona(t, system)
```

### 게임 생성
```go
// Asterisc 게임 시작
game := disputeGameFactory.StartOutputAsteriscGame(
    ctx,
    "sequencer",  // L2 노드 이름
    blockNumber,  // L2 블록 번호
    rootClaim,    // 루트 클레임
)

// Asterisc-Kona 게임 시작
game := disputeGameFactory.StartOutputAsteriscKonaGame(
    ctx,
    "sequencer",
    blockNumber,
    rootClaim,
)
```

## 구현 세부사항

### Helper 메서드 (helper.go)
다음 메서드들이 `FactoryHelper`에 추가되었습니다:

```go
// Asterisc 게임 시작 메서드
func (h *FactoryHelper) StartOutputAsteriscGameWithCorrectRoot(...)
func (h *FactoryHelper) StartOutputAsteriscGame(...)

// Asterisc-Kona 게임 시작 메서드
func (h *FactoryHelper) StartOutputAsteriscKonaGameWithCorrectRoot(...)
func (h *FactoryHelper) StartOutputAsteriscKonaGame(...)
```

### 게임 타입 상수
```go
const (
    cannonGameType            uint32 = 0
    permissionedGameType      uint32 = 1
    asteriscGameType          uint32 = 2   // ⭐ 추가
    asteriscKonaGameType      uint32 = 3   // ⭐ 추가
    superCannonGameType       uint32 = 4
    superPermissionedGameType uint32 = 5
    alphabetGameType          uint32 = 255
)
```

### Trace Provider
현재는 `NewMemoizedCannonTraceProvider`를 재사용하지만, 향후 Asterisc 전용 trace provider 구현이 필요할 수 있습니다:

```go
// 현재 구현 (Cannon trace provider 재사용)
providerFunc := game.NewMemoizedCannonTraceProvider(
    ctx,
    "sequencer",
    outputRootClaim,
    challenger.WithPrivKey(sys.Cfg.Secrets.Alice),
)

// 향후 개선 (Asterisc 전용)
// providerFunc := game.NewMemoizedAsteriscTraceProvider(...)
```

## 알려진 제약사항

1. **Trace Provider 재사용**
   - 현재 Cannon trace provider를 재사용하고 있습니다
   - Asterisc 특화 기능을 사용하려면 별도 구현 필요

2. **Binary Snapshots**
   - Optimism 최신 버전의 binary snapshot 기능은 미구현
   - 성능 최적화를 위해 향후 추가 권장

3. **State Converter**
   - Optimism의 `stateConverter` 필드가 누락
   - VM 추상화 개선을 위해 추가 권장

## 향후 개선사항

### 우선순위 높음
1. ✅ Binary Snapshots 지원 추가
   - 증명 생성 성능 향상
   - Optimism commit `984bd412c` 참조

2. ✅ Asterisc 전용 Trace Provider
   - `NewMemoizedAsteriscTraceProvider` 구현
   - RISC-V 특화 최적화

3. ✅ State Converter 통합
   - VM 추상화 개선
   - Cannon과 코드 공유

### 우선순위 중간
4. ❓ Kona 클라이언트 검증
   - Asterisc-Kona 테스트 실제 실행 검증
   - Kona 바이너리 통합 테스트

5. ❓ 온체인 컨트랙트 테스트
   - RISCV.sol 배포 및 검증
   - 가스 최적화 측정

### 우선순위 낮음
6. ❌ Super Asterisc-Kona (GameType 7)
   - L2 scaling이 필요한 경우만
   - 현재는 불필요

## 참고 문서

### Optimism 공식 문서
- [Fault Proof Specs](https://specs.optimism.io/experimental/fault-proof/)
- [Asterisc GitHub](https://github.com/ethereum-optimism/asterisc)
- [Kona GitHub](https://github.com/ethereum-optimism/kona)

### 내부 문서
- [Asterisc 비교 분석](/op-challenger/docs/research/asterisc-comparison-optimism-vs-tokamak-ko.md)
- [RISC-V 가이드](/op-challenger/docs/research/asterisc-riscv-guide-ko.md)

### 관련 코드
- [op-challenger/game/fault/types/types.go](/op-challenger/game/fault/types/types.go) - GameType 정의
- [op-challenger/game/fault/register.go](/op-challenger/game/fault/register.go) - 게임 등록
- [op-e2e/e2eutils/disputegame/helper.go](/op-e2e/e2eutils/disputegame/helper.go) - 헬퍼 메서드

## 트러블슈팅

### 컴파일 오류
```bash
# 의존성 업데이트
go mod tidy

# 캐시 클리어
go clean -cache
go clean -testcache
```

### 테스트 실행 오류
```bash
# 바이너리 경로 확인
export OP_CHALLENGER_ASTERISC_BIN=/path/to/asterisc
export OP_CHALLENGER_ASTERISC_SERVER=/path/to/op-program-rv64
export OP_CHALLENGER_ASTERISC_PRESTATE=/path/to/prestate-rv64.json

# 디버그 모드로 실행
go test -v -run TestOutputAsteriscGame ./op-e2e/faultproofs
```

### 타임아웃 오류
```bash
# 타임아웃 증가
go test -timeout 30m -run TestOutputAsterisc ./op-e2e/faultproofs
```

## 기여 가이드

### 새 테스트 추가
1. 기존 테스트 케이스 참조 (`output_cannon_test.go`)
2. Asterisc 특화 시나리오 작성
3. `RunTestAcrossVmTypes` 활용
4. 문서 업데이트

### 코드 리뷰 체크리스트
- [ ] 모든 테스트 케이스가 Cannon과 동등한가?
- [ ] Asterisc 특화 기능을 테스트하는가?
- [ ] VM 타입별로 올바르게 실행되는가?
- [ ] 문서가 최신 상태인가?

## 라이선스

MIT License - Optimism 프로젝트와 동일

## 작성 정보

- **작성일**: 2025-01-21
- **최종 수정**: 2025-01-21
- **버전**: 1.0.0
- **작성자**: Claude Code
- **리뷰**: 필요
