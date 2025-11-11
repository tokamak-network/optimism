# Fault Proofs E2E 테스트 가이드

이 문서는 `op-e2e/faultproofs` 하위 E2E 테스트(예: `faultproofs-cannon-test-report.md`에 정리된 테스트들)를 실행하기 전에 필요한 준비 작업을 정리합니다.
GameType 0/1(캐논) 테스트뿐 아니라 향후 GameType 2(ASTERISC) 및 GameType 3(KONA) 시나리오를 염두에 둔 준비 절차를 포함합니다.

---

## 1. 필수 VM 자산 준비 (GameType 0/1/2/3 공통)

**중요: E2E 테스트는 프로덕션과 다른 디렉토리를 사용합니다!**

E2E 테스트는 **Docker 이미지를 사용하지 않고 로컬 바이너리와 프리스테이트 파일**을 직접 실행합니다.
가장 빠른 준비 방법은 아래 명령을 실행하는 것입니다.

```bash
cd /Users/zena/tokamak-projects/optimism/op-challenger/scripts

# 캐논 + ASTERISC(GameType 2) E2E 자산을 한 번에 준비 (추천)
./build-binaries-for-challenger-e2e.sh --force --asterisc
```

### E2E vs 프로덕션 바이너리 경로

**E2E 테스트용 (Mac arm64):**
- `cannon/bin-e2e/cannon`
- `op-program/bin-e2e/op-program`
- `op-program/bin-e2e/prestate.bin.gz`
- `asterisc/bin-e2e/asterisc`
- `op-program/bin-e2e/prestate-asterisc.json` (배포/검증용)
- `op-program/bin-e2e/prestate-asterisc.bin.gz` (실행용 - 챌린저가 사용)

**프로덕션용 (Linux x86-64):**
- `cannon/bin/cannon`
- `op-program/bin/op-program`
- `op-program/bin/prestate.bin.gz`
- `asterisc/bin/asterisc`
- `op-program/bin/prestate-asterisc.json` (배포/검증용)
- `op-program/bin/prestate-asterisc.bin.gz` (실행용 - 챌린저가 사용)

이 스크립트는 다음 작업을 수행합니다:
- Mac-native `cannon` 바이너리를 `cannon/bin-e2e/`에 빌드
- Mac-native `op-program` 바이너리와 prestates를 `op-program/bin-e2e/`에 생성
- 외부 `asterisc` 리포에서 Mac-native ASTERISC VM을 빌드하여 `asterisc/bin-e2e/`에 복사
- 모든 prestate 파일을 E2E 전용 디렉토리에 배치
- 파일이 없거나 오래되었을 때 경고를 출력하며, `--force`로 항상 최신 상태를 보장

스크립트가 완료되면 아래 파일들이 E2E 디렉토리에 생성되어 있어야 합니다:

| 파일 | 용도 |
|------|------|
| `cannon/bin-e2e/cannon` | 캐논 VM 실행 바이너리 (Mac arm64) |
| `op-program/bin-e2e/op-program` | op-program 서버 (Mac arm64) |
| `op-program/bin-e2e/prestate.bin.gz` | 캐논 절대 prestate |
| `asterisc/bin-e2e/asterisc` | ASTERISC VM 실행 바이너리 (Mac arm64) |
| `asterisc/bin-e2e/prestate-proof.json` | ASTERISC 배포/검증용 proof |
| `op-program/bin-e2e/prestate-asterisc.json` | ASTERISC용 prestate (챌린저가 참조) |
| `op-program/bin-e2e/prestate-asterisc.bin.gz` | ASTERISC 런타임용 prestate archive |

`ls cannon/bin-e2e/`, `ls op-program/bin-e2e/`, `ls asterisc/bin-e2e/`으로 파일이 있는지 확인하세요.
E2E 자산이 없으면 테스트 실행 시 바이너리를 찾을 수 없다는 오류가 발생합니다.


## 2. 테스트 실행 전에 확인 사항

1. **E2E 바이너리 / 프리스테이트 존재 여부**
   - Cannon: `cannon/bin-e2e/cannon`, `op-program/bin-e2e/op-program`, `op-program/bin-e2e/prestate.bin.gz`
   - ASTERISC: `asterisc/bin-e2e/asterisc`, `asterisc/bin-e2e/prestate-proof.json`, `op-program/bin-e2e/prestate-asterisc.json`
   - (선택) `op-program/bin-e2e/prestate-asterisc.bin.gz`

2. **바이너리 아키텍처 확인**
   ```bash
   file cannon/bin-e2e/cannon
   # 출력: cannon/bin-e2e/cannon: Mach-O 64-bit executable arm64

   file asterisc/bin-e2e/asterisc
   # 출력: asterisc/bin-e2e/asterisc: Mach-O 64-bit executable arm64
   ```



## 3. 예시 실행 명령어

```bash
# 캐논 관련 단일 테스트
go test -v ./op-e2e/faultproofs -run "TestChallengeLargePreimages_ChallengeFirst"

# 포괄적 캐논 회귀 테스트
go test -v ./op-e2e/faultproofs -run "TestChallengerCompleteExhaustiveDisputeGame"

# ASTERISC (GameType 2) 테스트
go test -v -timeout 20m ./op-e2e/faultproofs -run "TestOutputAsteriscGame"
go test -v ./op-e2e/faultproofs -run "TestOutputAsterisc_ChallengeAllZeroClaim"
go test -v ./op-e2e/faultproofs -run "TestOutputAsterisc_PublishAsteriscRootClaim"
go test -v ./op-e2e/faultproofs -run "TestOutputAsteriscDisputeGame"
go test -v ./op-e2e/faultproofs -run "TestOutputAsteriscDefendStep"
```

테스트 로그와 결과 분석은 다음 문서를 참고하세요:
- Cannon 테스트: `faultproofs-cannon-test-report.md`
- Asterisc 테스트: `faultproofs-asterisc-test-report.md`

