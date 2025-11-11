# Fault Proofs E2E 테스트 가이드

이 문서는 `op-e2e/faultproofs` 하위 E2E 테스트(예: `faultproofs-cannon-test-report.md`에 정리된 테스트들)를 실행하기 전에 필요한 준비 작업을 정리합니다.
GameType 0/1(캐논) 테스트뿐 아니라 향후 GameType 2(ASTERISC) 및 GameType 3(KONA) 시나리오를 염두에 둔 준비 절차를 포함합니다.

---

## 1. 필수 VM 자산 준비 (GameType 0/1/2/3 공통)

CANNON 기반 E2E 테스트는 **Docker 이미지를 사용하지 않고 로컬 바이너리와 프리스테이트 파일**을 직접 실행합니다.
가장 빠른 준비 방법은 아래 명령을 실행하는 것입니다.

```bash
cd /Users/zena/tokamak-projects/optimism/op-challenger/scripts

# 캐논 + ASTERISC(GameType 2) 자산을 한 번에 준비 (추천)
./build-binaries-for-challenger.sh --force --asterisc
```

이 스크립트는 다음 작업을 수행합니다.
- `cannon/bin/cannon` 재빌드
- `op-program/bin/op-program` 및 `op-program/bin/prestate.bin.gz` 재생성
- 외부 `asterisc` 리포(상위 디렉터리에 클론되어 있다고 가정)를 이용해 `asterisc` VM, `prestate-proof.json`, `prestate.bin.gz`를 생성 후 `optimism/asterisc/bin`과 `op-program/bin`에 복사
- 파일이 없거나 오래되었을 때 경고를 출력하며, `--force`로 항상 최신 상태를 보장

스크립트가 완료되면 아래 파일들이 생성되어 있어야 합니다.

| 파일 | 용도 |
|------|------|
| `cannon/bin/cannon` | 캐논 VM 실행 바이너리 |
| `op-program/bin/op-program` | 캐논이 호출하는 op-program 서버 |
| `op-program/bin/prestate.bin.gz` | 캐논 절대 prestate (압축된 VM 상태) |
| `asterisc/bin/asterisc` | ASTERISC VM 실행 바이너리 |
| `asterisc/bin/prestate-proof.json` | ASTERISC 배포/검증용 `.pre` 포맷 |
| `op-program/bin/prestate-asterisc.json` | ASTERISC용 `.pre` 포맷 (챌린저가 참조) |
| `op-program/bin/prestate-asterisc.bin.gz` | ASTERISC 런타임용 prestate (있다면 활용) |

`ls bin/`, `ls op-program/bin/`, `ls asterisc/bin/`으로 파일이 있는지 확인하세요.
캐논 자산이 없으면 테스트 실행 시 `cannon should be built. Make sure you've run make cannon-prestates` 오류가 발생합니다.


## 2. 테스트 실행 전에 확인 사항

1. **바이너리 / 프리스테이트 존재 여부**
   - Cannon: `cannon/bin/cannon`, `op-program/bin/op-program`, `op-program/bin/prestate.bin.gz`
   - ASTERISC: `asterisc/bin/asterisc`, `asterisc/bin/prestate-proof.json`, `op-program/bin/prestate-asterisc.json`
   - (선택) `op-program/bin/prestate-asterisc.bin.gz`



## 3. 예시 실행 명령어

```bash
# 캐논 관련 단일 테스트
go test -v ./op-e2e/faultproofs -run "TestChallengeLargePreimages_ChallengeFirst"

# 포괄적 캐논 회귀 테스트
go test -v ./op-e2e/faultproofs -run "TestChallengerCompleteExhaustiveDisputeGame"
```

테스트 로그와 결과 분석은 `faultproofs-cannon-test-report.md` 문서를 참고하세요.
추후 ASTERISC/KONA E2E 시나리오가 추가되면 이 문서를 확장하여 업데이트할 예정입니다.

