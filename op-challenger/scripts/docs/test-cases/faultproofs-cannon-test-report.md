# Fault Proofs 테스트 보고서

## 개요

2025년 11월 11일에 `op-e2e/faultproofs` Go 테스트 스위트를 수동으로 실행한 결과를 정리한 문서입니다. 각 항목은 아래 정보를 포함합니다.

- **목적**: 테스트가 검증하려는 대상
- **실행 방법**: 실제로 실행한 명령어
- **결과 및 소요 시간**: 실행 결과와 대략적인 시간
- **비고**: 로그에서 확인한 특이 사항

모든 명령어는 리포지토리 루트(`/Users/zena/tokamak-projects/optimism`)에서 실행했습니다.

## 테스트 실행 내역

### TestBenchmarkCannonFPP

- **목적:** 캐논 Fault Proof 프로그램에서 증인(witness) 크기와 VM 페이지 할당을 비교하는 벤치마크(현재는 자리 채움 용도).
- **실행 방법:**
  `go test -v ./op-e2e/faultproofs -run "TestBenchmarkCannonFPP"`
- **결과 및 소요 시간:** SKIP (기존 TODO에 따라건너뜀), 약 5초.
- **비고:** `TODO(client-pod#906)` 메시지를 남기고 의도적으로 스킵되며, 오류는 없음.
- **실행 흐름:**
  1. 테스트가 Lock-step 벤치마크 준비 단계를 호출하지만, TODO 플래그를 확인하고 바로 `t.Skip` 처리.
  2. 추가적인 서비스 부팅이나 상태 변경 없음.
- **주요 기능 검증:** 현재는 향후 벤치마크 구현을 위한 스켈레톤만 제공하며, 실제 성능 측정은 수행되지 않음.

### TestChallengeLargePreimages_ChallengeFirst

- **목적:** 대규모 프리이미지 분쟁에서 첫 기회에 부정확한 프리이미지를 공격하는 시나리오 검증.
- **실행 방법:**
  `go test -v ./op-e2e/faultproofs -run "TestChallengeLargePreimages_ChallengeFirst"`
- **결과 및 소요 시간:** PASS, 약 10초.
- **비고:** 표준 배포 로그 후 챌린저가 분쟁을 해결. 예상되는 가스 팁 조정 외 특이사항 없음.
- **실행 흐름:**
  1. L1·L2 개발용 체인과 핵심 서비스(Sequencer, Batcher, Challenger)가 부팅됨.
  2. 콘트랙트 배포 및 초기화 후, 공격자 역할의 루트 클레임이 제출됨.
  3. Challenger가 첫 번째 분할 라운드에서 잘못된 프리이미지를 감지하고 즉시 반박 트랜잭션 전송.
  4. 분쟁 게임 상태가 `Challenger Won`으로 전환되고, 서비스가 정리되며 테스트 종료.
- **주요 기능 검증:**
  - `PreimageHelper.UploadLargePreimage`가 업로드한 거대 프리이미지의 첫 번째 커밋(인덱스 0)을 의도적으로 `0xaa`로 변조하는지 확인.
  - `StartChallenger(...WithPrivKey(Alice))`로 기동한 챌린저가 첫 검증 라운드에서 변조된 커밋을 탐지하고 `WaitForChallenged` 조건을 만족시키는지 확인.
  - 분쟁 게임 팩토리 및 프리이미지 헬퍼 초기화 경로가 정상 동작하는지 점검.

### TestChallengeLargePreimages_ChallengeMiddle

- **목적:** 분할(bisection) 트리 중간 단계에서 부정확한 프리이미지를 반박하는 흐름 검증.
- **실행 방법:**
  `go test -v ./op-e2e/faultproofs -run "TestChallengeLargePreimages_ChallengeMiddle"`
- **결과 및 소요 시간:** PASS, 약 10초.
- **비고:** 첫 번째 변형과 유사한 로그 흐름. 중간 단계 반박에도 정상적으로 승리 확인.
- **실행 흐름:**
  1. 기본 개발 네트워크와 서비스가 기동되며, 루트 클레임 이후 정상적인 분할 라운드가 진행됨.
  2. Challenger는 초기 라운드에서는 대기하고, 중간 깊이에서 잘못된 프리이미지를 찾을 때까지 분기 탐색을 계속함.
  3. 해당 깊이에서 반박 트랜잭션을 제출하고, 추가 분할 라운드를 거쳐 모든 클레임을 무효화.
  4. 게임 상태가 승리로 갱신되고 Clean-up 시퀀스가 실행되어 테스트 종료.
- **주요 기능 검증:**
  - `UploadLargePreimage(...WithReplacedCommitment(10, 0xaa))` 옵션이 10번째 커밋에서만 변조를 적용하는지 확인.
  - 챌린저가 여러 분할 단계 중 중간 깊이에서 반박을 수행할 수 있는지(=중간까지 진행되는 분쟁 루프가 정상 동작하는지) `WaitForChallenged`로 검증.
  - 다른 서명 키(`Mallory`)를 사용하는 챌린저도 동일한 분쟁 경로를 수행할 수 있는지 확인.

### TestChallengeLargePreimages_ChallengeLast

- **목적:** 마지막 분할 단계에서 부정확한 프리이미지를 반박해도 챌린저가 승리하는지 확인.
- **실행 방법:**
  `go test -v ./op-e2e/faultproofs -run "TestChallengeLargePreimages_ChallengeLast"`
- **결과 및 소요 시간:** PASS, 약 10초.
- **비고:** 챌린저 승리 및 게임 데이터 덤프 출력. 테스트 종료 후 `panic during flush` 경고는 서비스 종료 시점의 로그 플러시와 관련된 무해한 메시지.
- **실행 흐름:**
  1. 분쟁 게임이 최대 깊이까지 전개될 때까지 Challenger가 모든 분할 단계에 대응.
  2. 마지막 분할 지점에서 부정확한 프리이미지를 발견하고 반박 트랜잭션을 생성.
  3. 추가적인 스텝 호출 없이 루트 클레임이 정리되고, `Challenger Won` 상태로 전환.
  4. 게임 데이터 요약 로그가 출력된 뒤 서비스가 정상 종료.
- **주요 기능 검증:**
  - `UploadLargePreimage(...WithLastCommitment(0xaa))`가 마지막 커밋에만 변조를 적용하고 나머지는 정합성을 유지하는지 확인.
  - 챌린저의 분할 경로가 최악의 경우(최대 깊이)까지 도달한 후에도 변조 커밋을 식별·반박할 수 있는지 확인.
  - 긴 분쟁 루프 이후에도 `WaitForChallenged`가 정상적으로 분쟁 완료를 감지하는지 테스트.

### TestChallengerCompleteExhaustiveDisputeGame

- **목적:** 올바른 출력(root)과 잘못된 출력을 모두 다루는 포괄적 분쟁 시나리오 회귀 테스트.
- **실행 방법:**
  `go test -v ./op-e2e/faultproofs -run "TestChallengerCompleteExhaustiveDisputeGame"`
- **결과 및 소요 시간:** PASS, 총 약 187초(`RootCorrect`와 `RootIncorrect` 서브 테스트 포함).
- **비고:**
  - 두 서브 테스트 모두 성공적으로 완료.
  - 챌린저가 분쟁 트리를 진행하는 동안 단계(step) 재시도, nonce 재조정 등 예상된 RPC 경고 발생.
  - 종료 시점 로그에서 `player.go`가 컨텍스트 취소 이후 상태 조회 실패 경고를 남기지만, 성공적인 PASS에는 영향 없음.
- **실행 흐름:**
  1. `RootCorrect` 서브 테스트: 정당한 루트에 대해 Challenger가 분쟁 없이 확인 절차만 수행하고 종료.
  2. `RootIncorrect` 서브 테스트:
     - 잘못된 루트를 제출한 후, Challenger가 전체 분할 트리를 순회하며 반박을 준비.
     - 각 분할 단계에서 증거 수집과 스텝 호출을 반복하면서 모든 클레임을 반박.
     - 최종적으로 `ResolveClaim` 및 `Resolve` 트랜잭션을 실행하여 게임을 종료하고 승리 상태 확인.
  3. 테스트 종료 시 모든 서비스가 순차적으로 정리되며, 일부 RPC 호출이 컨텍스트 취소로 실패했다는 경고 로그를 남김 (테스트 결과에는 영향 없음).
- **주요 기능 검증:**
  - `StartOutputAlphabetGameWithCorrectRoot` 및 `StartOutputAlphabetGame` 경로가 각각 올바른/잘못된 루트를 배포하고 동작하는지 확인.
  - `game.StartChallenger(...WithAlphabet(), WithPollInterval)` 옵션이 모든 클레임에 대해 자동으로 응답하며, `CreateDishonestHelper`가 전 탐색을 수행하는지 검증.
  - `WaitForClaimAtDepth`, `WaitForInactivity`, `TimeTravelClock` 등을 활용해 분쟁 시계(clock)와 가용 크레딧, WETH 언락 대기, 크레딧 정산 등의 전체 흐름을 확인.
  - `GameStatusChallengerWon` / `DefenderWon` 전환, 채권(credit) 회수 및 2차 분쟁 대비 상태 검증까지 포함해 종단 간 분쟁 메커니즘을 점검.

### TestOutputCannonBondCostMeasurement

- **목적:** GameType 0 (Cannon)에서 정직한 챌린저가 악의적인 프로포저에 대응할 때 발생하는 본드 비용을 측정하며, 최대 깊이까지 전체 분쟁 게임 트리를 진행.
- **실행 방법:** `go test -v ./op-e2e/faultproofs -run "TestOutputCannonBondCostMeasurement"`
- **결과 및 소요 시간:** PASS, 361.41초 (약 6분).
- **비고:** 깊이 0부터 50까지 지수적 본드 증가를 보여주며, 양측에서 총 약 483.18 ETH의 본드가 필요함.
- **관련 문서:** [본드 비용 측정 보고서](./bond-cost-measurement-report.md)

**실행 흐름:**
1. **첫 번째 게임 (Cold Start):** 초기 게임 상태와 prestate를 설정하기 위해 잘못된 루트 클레임 생성.
   - 챌린저가 대응하여 승리
   - 게임 기간을 넘기도록 시간 진행
   - 게임 종료 및 Challenger Won으로 해결
2. **두 번째 게임 (본드 측정):** 전체 분쟁을 유발하는 잘못된 루트 클레임 생성.
   - 정직한 챌린저 (Alice)가 잘못된 클레임 공격
   - 악의적인 프로포저 (Bob)가 각 클레임을 적극적으로 방어
   - 게임 진행:
     - Output Bisection Phase (깊이 0-14): L2 출력 루트 이분 탐색
     - Execution Trace Phase (깊이 15-50): VM 실행 트레이스 이분 탐색
   - 총 51개 클레임 생성 (깊이 0-50)
   - 게임 기간을 넘기도록 시간 진행
   - 게임 종료 및 Challenger Won으로 해결
3. 모든 깊이 레벨에서 각 클레임의 상세 본드 분석 로깅
4. 양측의 본드, 가스 비용, 순 결과를 보여주는 최종 비용 보고서

**주요 기능 검증:**
- 재귀적 방어 전략을 사용하는 `DefendClaim`이 최대 깊이(50)에 도달
- `WithoutWaitingForStep()` 옵션으로 STEP 함수 실행 생략 (본드 측정에 집중)
- 본드 증가: 깊이당 약 14.17% 증가
- 총 필요 본드: 챌린저 225.62 ETH + 프로포저 257.56 ETH = 483.18 ETH
- 가스 가격 추적 및 정확한 gwei 표시
- 시간 진행 후 `CloseGame` 및 게임 해결
- 실제 가스 가격과 독립적인 하드코딩된 값을 사용한 본드 계산 (Big Bonds v1.5 사양)
- 클레임 주소, 본드, 위치 데이터를 포함한 모든 클레임의 포괄적 로깅

---

## 요약

캐논 및 대규모 프리이미지 관련 회귀 테스트는 모두 실패 없이 완료되었습니다. 벤치마크 케이스는 현재 정책대로 스킵 처리됩니다. 별도의 추가 조치 없이 기재한 명령어만으로 재현 가능합니다.

본드 비용 분석 및 게임 메커니즘에 대한 상세 내용은 [본드 비용 측정 보고서](./bond-cost-measurement-report.md)를 참조하세요.


