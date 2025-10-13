# Optimism Challenger 검증 시스템 완벽 해부 - 동영상 스크립트

## 동영상 개요
- **제목**: "Optimism Challenger: 게임 발견부터 Anchor 업데이트까지 완벽 가이드"
- **길이**: 약 23-24분 (DEFENDER_WINS vs CHALLENGER_WINS 비교 포함)
- **대상**: Optimism 개발자, 블록체인 엔지니어, 시스템 관리자
- **목표**:
  - Challenger의 전체 동작 플로우를 Phase 1~6까지 완벽 이해
  - closeGame()의 critical한 중요성 깨닫기
  - DEFENDER_WINS vs CHALLENGER_WINS의 차이와 재제출 프로세스 이해
  - Progressive Anchoring과 Self-Healing System 개념 파악

---

## 파트 1: 인트로 및 등장인물 소개 (0:00-3:30)

### 장면 1: 오프닝 (0:00-0:30)

**내레이션**:
"안녕하세요! 오늘은 Optimism Challenger 시스템의 전체 동작 과정을 처음부터 끝까지 완벽하게 파헤쳐보겠습니다. 새로운 Dispute Game이 생성되는 순간부터 Challenger가 어떻게 게임을 발견하고, 검증하고, 참여하는지 모든 단계를 따라가보죠."

**화면**:
- Optimism 로고 애니메이션
- "Challenger End-to-End Journey" 타이틀
- 전체 시스템 개요 이미지

---

### 장면 2: 등장인물 소개 - 시스템 아키텍처 (0:30-2:00)

**내레이션**:
"본격적으로 시작하기 전에, 이 시스템에 등장하는 주요 컴포넌트들을 먼저 소개하겠습니다. 마치 영화의 등장인물처럼, 각자의 역할이 명확히 나뉘어 있습니다."

**화면**:
- 3계층 아키텍처 다이어그램 (L1 / Off-Chain / L2)

```
┌─────────────────────────────────────────────────────────────┐
│                         L1 (Ethereum)                        │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  📜 DisputeGameFactory                                       │
│  └─ 역할: 새로운 Dispute Game 생성                          │
│  └─ Proposer가 여기에 트랜잭션 제출                         │
│                                                               │
│  📜 FaultDisputeGame (여러 개)                               │
│  └─ 역할: 개별 게임 상태 관리                                │
│  └─ Root claim, claims, counters 저장                        │
│  └─ 상태: IN_PROGRESS → DEFENDER_WINS / CHALLENGER_WINS     │
│                                                               │
│  📜 AnchorStateRegistry                                      │
│  └─ 역할: 게임 시작점(anchor) 관리                          │
│  └─ anchorGame: 최근 완료된 게임 참조                       │
│  └─ Cold Starting 문제의 근원                                │
│                                                               │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                      Off-Chain (Actors)                      │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  👤 Proposer                                                 │
│  └─ 역할: L2 output root 제안 (Root claim 제출)             │
│  └─ "Block 200의 상태는 0xdef456...입니다"                  │
│                                                               │
│  🛡️ Challenger                                               │
│  └─ 역할: Proposer의 주장 검증 및 반박                      │
│  └─ 구성:                                                    │
│     ├─ Scheduler: L1 모니터링, 새 게임 발견                 │
│     ├─ Coordinator: Player 생성 및 검증 조율                │
│     ├─ GamePlayer: 실제 게임 참여 로직                      │
│     ├─ Validator: 사전 검증 (게임 참여 가능 여부)           │
│     └─ Agent: 게임 진행 중 액션 실행                        │
│                                                               │
│  📁 Fileserver                                               │
│  └─ 역할: VM prestate 파일 제공                             │
│  └─ 0x03a1a135....bin.gz 등                                 │
│                                                               │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                      L2 (Optimism Chain)                     │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  🌐 L2 Node (Archive Mode)                                   │
│  └─ 역할: 모든 과거 블록 상태 제공                          │
│  └─ API: rollupClient.OutputAtBlock(blockNumber)            │
│  └─ Example: Block 500일 때 Block 100 조회 가능             │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

**핵심 설명**:

**L1 Contract들**:
- **DisputeGameFactory**: 게임 생성 공장. Proposer가 새 게임을 만드는 곳
- **FaultDisputeGame**: 개별 게임 인스턴스. 상태와 claim들을 저장
- **AnchorStateRegistry**: 게임 시작점을 관리. Cold Starting 문제와 연관

**Off-Chain 참여자**:
- **Proposer**: "이 블록의 상태는 이렇습니다"라고 주장하는 쪽
- **Challenger**: "그게 틀렸습니다"라고 검증하고 반박하는 쪽 (우리의 주인공!)
  - Scheduler: 감시자
  - Coordinator: 조율자
  - Validator: 사전 검사관
  - GamePlayer + Agent: 실제 전투원

**L2 시스템**:
- **L2 Archive Node**: 과거 블록 데이터를 제공하는 진실의 원천

**상호작용**:
```
1. Proposer → L1 Contract
   └─ 게임 생성

2. Challenger.Scheduler → L1 Contract
   └─ 게임 발견

3. Challenger.Validator → L2 Node + Fileserver
   └─ 사전 검증

4. Challenger.Agent → L1 Contract
   └─ Counter claim 제출

5. 모든 검증 → L2 Node
   └─ 진실 확인
```

---

### 장면 3: Challenger의 생명주기 - 큰 그림 (2:00-3:30)

**내레이션**:
"Challenger의 동작은 크게 6단계로 나뉩니다. 첫째, Proposer가 L1에 새로운 게임을 생성합니다. 둘째, Scheduler가 이 게임을 발견합니다. 셋째, playerCreator가 Validators와 GamePlayer를 생성합니다. 넷째, ValidatePrestate가 실행되어 실제 검증을 수행합니다. 중요한 점은, 이 검증에 실패해도 L1 Contract의 게임 상태는 변하지 않습니다. 다섯째, 검증을 통과하면 ProgressGame이 주기적으로 호출되어 모든 claim을 검증하고 반박합니다. 마지막으로 여섯째, 게임이 종료되면 resolve와 closeGame을 통해 AnchorStateRegistry를 업데이트합니다."

**화면**:
- 전체 플로우 다이어그램 (6단계)
```
Phase 1: 게임 생성 (Proposer → L1 Contract)
    ↓
Phase 2: 게임 발견 (Scheduler Monitor)
    ↓
Phase 3: Player 생성 (playerCreator → Validators + GamePlayer)
    ↓
Phase 4: 사전 검증 실행 (ValidatePrestate)
    ↓
Phase 5: 게임 진행 (ProgressGame 주기적 호출)
    ↓
Phase 6: 게임 종료 및 Anchor 업데이트 (resolve → closeGame) ⭐
```

**핵심 포인트**:
- Phase 3에서 Validator와 GamePlayer가 함께 생성되지만 아직 검증 안 함
- Phase 4에서 ValidatePrestate()가 실행되어 실제 검증 수행
- 검증은 두 단계로 나뉨: 사전 검증(Phase 4) vs 게임 중 검증(Phase 5)

**게임 상태**:
```
L1 Contract 게임 상태:
├─ Phase 1 (게임 생성): IN_PROGRESS ✅
├─ Phase 4 (검증 실패): IN_PROGRESS ✅ (변화 없음!)
└─ Phase 5 (게임 진행): IN_PROGRESS ✅

⚠️ ValidatePrestate 실패해도:
   - L1 Contract 상태는 변경되지 않음
   - 이 Challenger만 로컬에서 게임 스킵
   - 다른 Challenger들은 여전히 참여 가능
   - 게임은 L1에 그대로 존재
```

---

## 파트 2: Phase 1-2 게임 생성과 발견 (3:30-5:30)

### 장면 4: Phase 1 - Proposer가 게임 생성 (3:30-4:30)

**내레이션**:
"모든 것은 Proposer가 DisputeGameFactory에 새로운 게임을 생성하면서 시작됩니다. Proposer는 특정 L2 블록의 output root를 제안하고, 이것이 맞다고 주장하는 claim을 제출합니다."

**화면**:
- L1 블록체인 애니메이션
- DisputeGameFactory.create() 호출 시각화
- 게임 초기화 과정

**코드 플로우**:
```
T=0: Proposer 트랜잭션
├─ DisputeGameFactory.create()
│  ├─ gameType: 0 (CANNON)
│  ├─ rootClaim: 0xdef456... (Block 200 주장)
│  └─ extraData: Block 200
├─ FaultDisputeGame 생성
└─ AnchorStateRegistry.getAnchorRoot() 호출
   ├─ anchorGame 확인
   └─ startingOutputRoot 설정
      ├─ Cold: 0xdead... (잘못된 값) ❌
      └─ Warm: 0xabc123... (유효한 값) ✅
```

**중요 포인트**:
- 게임 생성 시 **snapshot**이 중요
- AnchorStateRegistry의 상태가 게임에 고정됨
- Cold Starting vs Warm 상태 결정

---

### 장면 5: Phase 2 - Challenger가 게임 발견 (4:30-5:30)

**내레이션**:
"Challenger는 L1 블록체인을 지속적으로 모니터링합니다. Scheduler가 새로운 게임을 감지하면 즉시 반응하지만, 바로 참여하지는 않습니다. 먼저 이 게임이 참여할 가치가 있는지 검증해야 합니다."

**화면**:
- Scheduler 모니터링 애니메이션
- 새 게임 이벤트 감지
- GamePlayer 생성 트리거

**코드 플로우**:
```
T=5분: Challenger 발견
├─ Scheduler: "New game detected 0xGame123..."
├─ Event listener: GameCreated
└─ playerCreator() 함수 트리거
   └─ 다음 단계: 사전 검증
```

---

## 파트 3: Phase 3 - Player 생성 단계 (5:30-11:30)

### 장면 6: Player 생성 개요 및 준비 (5:30-6:30)

**내레이션**:
"이제 핵심 단계입니다. Scheduler가 createPlayer를 호출하면 playerCreator 함수가 실행됩니다. 이 함수는 Contract 정보를 조회하고, 두 개의 Validator를 생성하며, 최종적으로 GamePlayer 객체를 만듭니다. 중요한 점은 이 단계에서는 Validator를 생성만 하고 아직 검증을 실행하지는 않는다는 것입니다."

**화면**:
- 검증 준비 단계 다이어그램
- Contract 정보 조회
- Validator 생성 과정

**단계**:
```
coordinator.createPlayer() 호출:
  └─ playerCreator() 실행 (register_task.go:292-340)

     1. Contract 연결
        └─ FaultDisputeGameContract 생성

     2. Contract에서 정보 조회
        ├─ GetAbsolutePrestateHash()
        │  → 0x03a1a135...
        ├─ GetGameRange()
        │  → prestateBlock = 100
        │  → poststateBlock = 200
        └─ GetStartingRootHash()
           → 0xdead... (Cold) or 0xabc123... (Warm)

     3. Provider 생성
        ├─ vmPrestateProvider (파일서버용)
        └─ prestateProvider (L2 RPC용)

     4. Validator 생성 (Line 335-339)
        ├─ Validator 1: VM Prestate
        └─ Validator 2: Output Root
        ⚠️ 주의: 생성만 하고 아직 실행 안 함!

     5. NewGamePlayer() 호출 (Line 340)
        └─ GamePlayer 반환 (validators 포함)
```

---

### 장면 7: skipPrestateValidation 플래그 (6:30-7:30)

**내레이션**:
"잠깐, 모든 게임이 검증을 거치는 건 아닙니다. skipPrestateValidation 플래그가 true면 검증을 건너뜁니다. Permissioned 게임처럼 신뢰할 수 있는 참여자만 있는 경우나, Cold Starting 문제를 회피해야 할 때 사용됩니다."

**화면**:
- 게임 타입별 분기
- 플래그 결정 로직

**코드**:
```go
// register_task.go:336
if !e.skipPrestateValidation {
    validators = append(validators, ...)
} else {
    // 검증 없이 바로 게임 참여!
}

// 플래그 설정
skipPrestateValidation:
  gameType == PermissionedGameType ||
  gameType == SuperPermissionedGameType
```

---

### 장면 8: Validator 1 - VM Prestate 검증 상세 (7:30-9:00)

**내레이션**:
"첫 번째 Validator는 VM의 absolutePrestate를 검증합니다. 이는 Cannon VM의 초기 메모리 상태, 레지스터 값, 프로그램 카운터 등 모든 초기 상태의 해시입니다. 이것이 Fault Proof의 시작점을 정의합니다."

**화면**:
- VM 메모리 구조 다이어그램
- 파일서버 통신 애니메이션
- 해시 비교 프로세스

**검증 단계**:
```
Step 1: Contract 값 조회
└─ contract.GetAbsolutePrestateHash()
   → 0x03a1a135...

Step 2: Provider 값 계산
├─ 로컬 캐시 확인
│  ~/datadir/0x03a1a135....bin.gz
│  └─ 있으면 사용 ✅
│  └─ 없으면 다음 단계
├─ 파일서버 다운로드
│  GET http://fileserver/0x03a1a135....bin.gz
│  └─ 우선순위: .bin.gz → .json.gz → .json
└─ 해시 계산
   → 0x03a1a135...

Step 3: 비교
Contract: 0x03a1a135...
Provider: 0x03a1a135...
→ ✅ PASS (보통 성공)
```

**왜 중요한가?**:
- Trace Bisection의 기준점
- 모든 challenger가 동일한 VM 시작 상태 보장
- 잘못되면 부정직한 증명 가능

---

### 장면 9: Validator 2 - Starting Output Root 검증 상세 (9:00-11:00)

**내레이션**:
"두 번째 Validator는 더 복잡합니다. 게임의 starting block output root를 검증하는데, 여기서 핵심은 L2 RPC를 통한 과거 블록 조회입니다. 현재 L2가 Block 500에 있어도 Block 100의 데이터를 조회할 수 있습니다. 이것이 Archive Node의 힘입니다."

**화면**:
- L2 블록체인 타임라인
- 과거 블록 조회 메커니즘
- Archive Node 역할 설명

**검증 단계**:
```
Step 1: Contract에서 블록 정보
├─ prestateBlock = 100
└─ startingRootHash
   ├─ Cold: 0xdead... ❌
   └─ Warm: 0xabc123... ✅

Step 2: PrestateProvider 생성
└─ NewPrestateProvider(rollupClient, 100)
   → prestateBlock = 100 저장

Step 3: L2 RPC 호출 (핵심!)
├─ prestateProvider.AbsolutePreStateCommitment()
└─ rollupClient.OutputAtBlock(ctx, 100)
   ├─ 현재 L2 = Block 500
   ├─ 요청: Block 100 (400 블록 전!)
   └─ Archive Node: 과거 데이터 반환
      → 0xabc123...

Step 4: 비교
Cold Starting:
  Contract: 0xdead...
  Provider: 0xabc123...
  → ❌ FAIL → 게임 스킵

Warm 상태:
  Contract: 0xabc123...
  Provider: 0xabc123...
  → ✅ PASS → 게임 참여
```

**과거 블록 조회가 가능한 이유**:
- 블록체인의 불변성
- Archive Node가 모든 과거 상태 저장
- 시간 독립적 검증 가능

---

### 장면 9: Cold Starting 문제 심층 분석 (9:30-10:30)

**내레이션**:
"Cold Starting은 AnchorStateRegistry가 처음 배포될 때 발생합니다. anchorGame이 address(0)이면 startingAnchorRoot를 사용하는데, 이것이 0xdead로 시작하는 placeholder 값입니다. 이 상태에서 생성된 모든 게임은 검증에 실패합니다."

**화면**:
- AnchorStateRegistry 상태 다이어그램
- Cold vs Warm 비교
- 문제 발생 시나리오

**시나리오**:
```
═══════ Cold Starting 상태 ═══════

AnchorStateRegistry:
├─ anchorGame = address(0) ❌
└─ startingAnchorRoot = 0xdead...

Game 생성 시:
└─ getAnchorRoot()
   └─ anchorGame == address(0)?
      └─ YES → 0xdead... 반환 ❌

Validator 2 검증:
├─ Contract: 0xdead... ❌
├─ Provider: 0xabc123... ✅ (실제 값)
└─ 비교 → FAIL ❌

결과:
└─ 모든 게임 스킵
   └─ "output root absolute prestate does not match"

═══════ Warm 상태 (해결 후) ═══════

AnchorStateRegistry:
├─ anchorGame = 0xGame1... ✅
└─ 유효한 게임 참조

Game 생성 시:
└─ getAnchorRoot()
   └─ anchorGame.rootClaim() ✅

Validator 2 검증:
├─ Contract: 0xabc123... ✅
├─ Provider: 0xabc123... ✅
└─ 비교 → PASS ✅

결과:
└─ 게임 참여 가능 ✅
```

**해결 방법 (중요!)**:
```bash
# 완전한 3단계 프로세스
1. resolve() - 첫 게임 완료
2. 대기 - finality delay 경과
3. closeGame() - anchorGame 업데이트 ← 핵심!
```

---

## 파트 4: Phase 4 - 사전 검증 실행 (12:00-13:30)

### 장면 11: ValidatePrestate() 실행 (12:00-13:00)

**내레이션**:
"GamePlayer가 생성되었습니다. 이제 coordinator가 player.ValidatePrestate를 호출합니다. 이 함수가 Phase 3에서 생성된 두 Validator를 실제로 실행하는 순간입니다. 두 검증을 순차적으로 수행하며, 하나라도 실패하면 즉시 중단되고 게임을 스킵합니다."

**화면**:
- ValidatePrestate 함수 실행
- 순차적 검증 과정
- 성공/실패 분기

**실제 호출 위치**:
```go
// coordinator.go:133-143
if state.player == nil {
    // 1. Player 생성 (Phase 3)
    player, err := c.createPlayer(game, c.disk.DirForGame(game.Proxy))
    if err != nil {
        return nil, fmt.Errorf("failed to create game player: %w", err)
    }

    // 2. 🔥 검증 실행 (Phase 4 - 지금!)
    if err := player.ValidatePrestate(ctx); err != nil {
        if !c.allowInvalidPrestate || !errors.Is(err, types.ErrInvalidPrestate) {
            return nil, fmt.Errorf("failed to validate prestate: %w", err)
        }
        c.logger.Error("Invalid prestate", "game", game.Proxy, "err", err)
    }

    state.player = player
}
```

**ValidatePrestate 내부**:
```go
// player.go:165-171
func (g *GamePlayer) ValidatePrestate(ctx context.Context) error {
    for _, validator := range g.prestateValidators {
        if err := validator.Validate(ctx); err != nil {
            return err  // 즉시 실패!
        }
    }
    return nil  // 모두 통과!
}
```

**검증 순서**:
```
1. Validator 1 실행 (VM Prestate)
   ├─ contract.GetAbsolutePrestateHash() 호출
   ├─ vmPrestateProvider.AbsolutePreStateCommitment() 호출
   └─ PASS → 다음으로 / FAIL → 게임 스킵 ❌

2. Validator 2 실행 (Output Root)
   ├─ contract.GetStartingRootHash() 호출
   ├─ prestateProvider.AbsolutePreStateCommitment() 호출
   │  └─ rollupClient.OutputAtBlock(prestateBlock) 🔥
   └─ PASS → Phase 5로 ✅ / FAIL → 게임 스킵 ❌
```

**검증 실패 시 상태 변화**:
```
검증 실패 (Cold Starting 등):
├─ L1 Contract 상태: IN_PROGRESS ✅ (변화 없음!)
├─ coordinator 처리:
│  ├─ return nil, error
│  ├─ state.player = nil 유지
│  └─ job 생성 안 됨
├─ 이 Challenger: 게임 스킵
└─ 다른 노드들: 독립적으로 참여 가능

검증 성공:
├─ L1 Contract 상태: IN_PROGRESS ✅ (동일)
├─ coordinator 처리:
│  ├─ state.player에 저장
│  └─ newJob(player) 생성
└─ 이 Challenger: Phase 5로 진행
```

---

## 파트 5: Phase 5 - 게임 진행 (13:30-17:00)

### 장면 12: GamePlayer 구조 리캡 (13:30-14:00)

**내레이션**:
"검증을 통과했습니다! 이미 Phase 3에서 생성된 GamePlayer의 내부 구조를 다시 살펴보죠. TraceAccessor, Agent, Responder 등 게임에 필요한 모든 컴포넌트가 이미 초기화되어 있습니다. 이제 이 Player가 실제로 게임을 진행할 준비가 완료되었습니다."

**화면**:
- GamePlayer 컴포넌트 다이어그램
- 각 컴포넌트 역할 설명
- 연결 관계

**GamePlayer 구조 (Phase 3에서 이미 생성됨)**:
```
NewGamePlayer() 생성 (player.go:88-162):

1. TraceAccessor 생성 (중요!)
   ├─ OutputTraceProvider
   │  └─ 이것이 TraceProvider.Get() 제공
   └─ 게임 중 블록 검증에 사용

2. Oracle & Preimage Uploader
   ├─ DirectPreimageUploader
   └─ LargePreimageUploader

3. Responder 생성
   └─ FaultResponder
      └─ Claim 제출 담당

4. Agent 생성 (핵심!)
   ├─ accessor (TraceProvider)
   ├─ responder (Claim 제출기)
   └─ solver (액션 계산)

5. GamePlayer 반환
   ├─ act: agent.Act  ← 실제 게임 로직
   ├─ prestateValidators
   └─ loader, logger 등
```

---

### 장면 13: ProgressGame() - 게임 진행 시작 (14:00-14:45)

**내레이션**:
"검증을 통과한 GamePlayer는 state에 저장되고, coordinator가 job을 생성합니다. 이제 worker가 이 job을 받아 ProgressGame을 주기적으로 호출합니다. 이 함수가 agent.Act를 실행하며, 실제 게임 로직이 시작됩니다."

**화면**:
- 주기적 호출 애니메이션
- ProgressGame 플로우
- agent.Act 트리거

**전체 플로우**:
```
coordinator.createJob():
  ├─ createPlayer() (Phase 3)
  ├─ ValidatePrestate() (Phase 4)
  └─ newJob(player) 생성
     └─ job을 queue에 추가

worker:
  └─ job 받아서 처리
     └─ player.ProgressGame() 호출 🔥
```

**ProgressGame 코드**:
```go
// player.go:178-207
func (g *GamePlayer) ProgressGame(ctx context.Context) GameStatus {
    // 게임 종료 확인
    if g.status != GameStatusInProgress {
        return g.status
    }

    // 동기화 확인
    if err := g.syncValidator.ValidateNodeSynced(ctx, g.gameL1Head); ... {
        return g.status
    }

    // 🔥 실제 게임 액션!
    if err := g.act(ctx); err != nil {
        g.logger.Error("Error when acting on game", "err", err)
    }
    // g.act = agent.Act (Phase 3에서 설정됨)

    // 상태 업데이트
    status, err := g.loader.GetStatus(ctx)
    g.status = status
    return status
}
```

---

### 장면 14: agent.Act() - 실제 게임 로직 (14:45-15:30)

**내레이션**:
"Agent.Act는 게임의 심장부입니다. 먼저 Contract에서 현재 게임 상태를 가져오고, Solver에게 다음 액션을 계산하도록 요청합니다. 이 과정에서 TraceProvider.Get이 호출되며, 모든 중간 블록들이 검증됩니다."

**화면**:
- agent.Act 실행 플로우
- Contract 조회
- Solver 액션 계산

**코드 플로우**:
```go
// agent.go:79-112
func (a *Agent) Act(ctx context.Context) error {
    // 1. Resolve 시도
    if a.tryResolve(ctx) {
        return nil
    }

    // 2. L2 block number challenge 확인
    if challenged, err := a.loader.IsL2BlockNumberChallenged(...); ... {
        return nil
    }

    // 3. 🔥 게임 상태 로드
    game, err := a.newGameFromContracts(ctx)
    // → 모든 claims 가져오기

    // 4. 🔥 액션 계산 (핵심!)
    actions, err := a.solver.CalculateNextActions(ctx, game)
    // → 여기서 모든 블록 검증!

    // 5. 🔥 액션 실행 (병렬)
    var wg sync.WaitGroup
    for _, action := range actions {
        go a.performAction(ctx, &wg, action)
    }
    wg.Wait()

    return nil
}
```

---

### 장면 15: solver.CalculateNextActions() - 모든 블록 검증 (15:30-16:15)

**내레이션**:
"여기가 바로 마법이 일어나는 곳입니다. Solver는 게임의 모든 claim을 순회하며 각각에 대해 TraceProvider.Get을 호출합니다. 이때 L2 RPC를 통해 실제 블록 값을 조회하고, Proposer의 주장과 비교합니다."

**화면**:
- Bisection 과정 애니메이션
- TraceProvider.Get 호출
- 블록별 검증 시각화

**검증 프로세스**:
```
solver.CalculateNextActions():

For each claim in game:

  1. TraceProvider.Get(position) 호출
     └─ HonestBlockNumber(position)
        → 블록 번호 계산

  2. 🔥 L2 RPC 호출
     └─ rollupClient.OutputAtBlock(ctx, blockNumber)
        Example:
        ├─ OutputAtBlock(100) ← Block 100 조회
        ├─ OutputAtBlock(125) ← Block 125 조회
        ├─ OutputAtBlock(150) ← Block 150 조회
        ├─ OutputAtBlock(175) ← Block 175 조회
        └─ OutputAtBlock(200) ← Block 200 조회

  3. Proposer claim vs Honest value 비교
     ├─ 일치 → Agree, 액션 불필요
     └─ 불일치 → Disagree, Attack/Defend 필요

  4. 필요한 액션 생성
     └─ Action{
          Type: ActionTypeMove,
          IsAttack: true,
          ParentClaim: claim,
          Value: honestValue,
        }
```

**실제 시나리오**:
```
Game: Block 100 → 200 검증

Round 1: Root Claim (Block 200)
├─ TraceProvider.Get(RootPosition)
├─ OutputAtBlock(200) ← 🔥 L2 RPC
└─ 비교: rootClaim == honestValue?
   └─ Agree → 액션 없음

Round 2: Mid Claim (Block 150)
├─ TraceProvider.Get(MidPosition)
├─ OutputAtBlock(150) ← 🔥 L2 RPC
└─ 비교 및 액션 결정

Round 3: Block 125
├─ OutputAtBlock(125) ← 🔥 L2 RPC
└─ 계속 bisection...

Result: 모든 중간 블록이 검증됨!
```

---

### 장면 16: Validator vs Game Logic - 역할 분리 (16:15-17:00) ⚠️ 삭제 가능

**내레이션**:
"이제 큰 그림이 보입니다. Validator는 '이 게임에 참여해도 되나?'라는 질문에 답하며, 단 1개 블록만 체크합니다. 반면 Game Logic은 '모든 주장이 맞나?'라는 질문에 답하며, 범위 내 모든 블록을 검증합니다. 이 두 단계가 결합되어 완벽한 보안을 제공합니다."

**화면**:
- 역할 분리 다이어그램
- 검증 범위 비교
- 효율성 vs 보안성

**비교표**:
```
┌──────────────────────────────────────────────────┐
│ Stage 1: Validator (게임 참여 전)                 │
└──────────────────────────────────────────────────┘

목적: 참여 조건 확인
검증: Block 100 (starting point만)
횟수: 1회
시점: 게임 발견 직후
실패 시: 게임 스킵

┌──────────────────────────────────────────────────┐
│ Stage 2: Game Logic (게임 진행 중)                │
└──────────────────────────────────────────────────┘

목적: 모든 주장 완전 검증
검증: Block 100~200 사이 모든 블록
      (100, 125, 137, 150, 162, 175, 187, 193, 200...)
횟수: 수십~수백 회 (bisection마다)
시점: 게임 진행 전체
실패 시: Counter claim 제출

결론: 둘 다 필수!
├─ Validator: 빠른 사전 체크
└─ Game Logic: 철저한 완전 검증
```

**왜 이렇게 설계했나?**:
```
효율성:
└─ Validator가 모든 블록 체크하면
   → 100개 블록 × 모든 게임
   → 너무 느림 ❌

현재 설계:
├─ Validator: 1개 블록 체크
│  └─ 빠른 참여 결정 ✅
└─ Game Logic: 필요한 것만
   └─ Bisection으로 효율적 ✅

보안성:
└─ 두 단계 모두 완벽히 검증
   → 문제 있으면 반드시 발견 ✅
```

---

## 파트 6: Phase 6 - 게임 종료 및 Anchor 업데이트 (17:00-20:00)

### 장면 16: 게임 종료 - resolve()와 그 한계 (17:00-17:45)

**내레이션**:
"7일간의 긴 게임이 끝났습니다. Challenger가 Proposer의 잘못된 주장을 성공적으로 반박했고, 모든 claim이 검증되었습니다. Agent가 자동으로 tryResolve를 호출하여 게임을 종료합니다. 하지만 여기서 중요한 진실! resolve()는 게임 상태만 변경할 뿐, anchorGame을 업데이트하지는 않습니다. 많은 사람들이 놓치는 부분입니다."

**화면**:
- agent.tryResolve() 실행 플로우
- resolve() 트랜잭션 시각화
- ⚠️ anchorGame 미업데이트 경고

**Agent의 자동 Resolve**:
```go
// agent.go:153-172
func (a *Agent) tryResolve(ctx context.Context) bool {
    // 1. 개별 claim들을 먼저 resolve
    if err := a.resolveClaims(ctx); err != nil {
        a.log.Error("Failed to resolve claims", "err", err)
        return false
    }

    // 2. Selective mode 체크
    if a.selective {
        // Bond 회수 못하므로 resolve 안 함
        return false
    }

    // 3. 게임 resolve 가능한지 확인
    status, err := a.responder.CallResolve(ctx)
    if err != nil || status == gameTypes.GameStatusInProgress {
        return false
    }

    // 4. 🔥 게임 resolve 실행
    a.log.Info("Resolving game")
    if err := a.responder.Resolve(); err != nil {
        a.log.Error("Failed to resolve the game", "err", err)
    }
    return true
}
```

**resolve() 트랜잭션**:
```solidity
// FaultDisputeGame.sol:740-756
function resolve() external returns (GameStatus) {
    // 게임이 아직 진행 중인지 확인
    if (status != GameStatus.IN_PROGRESS) revert GameNotInProgress();

    // Chess clock 만료 확인
    if (getChallengerDuration(Timestamp.wrap(uint64(block.timestamp)))
        .raw() <= MAX_CLOCK_DURATION.raw()) {
        revert ClockNotExpired();
    }

    // 최종 승자 결정
    GameStatus finalStatus = _determineWinner();

    // 🔥 상태 업데이트 (여기가 전부!)
    status = finalStatus;  // DEFENDER_WINS or CHALLENGER_WINS
    resolvedAt = Timestamp.wrap(uint64(block.timestamp));

    // ⚠️ 주목: setAnchorState() 호출 없음!

    emit Resolved(status);
    return status;
}
```

**중요: resolve()가 하는 것 vs 안 하는 것**:
```
✅ resolve()가 하는 것:
├─ 게임 상태 변경 (IN_PROGRESS → DEFENDER_WINS)
├─ resolvedAt 타임스탬프 기록
├─ Bond claiming 가능하게 만듦
└─ Withdrawal 허용

❌ resolve()가 안 하는 것:
├─ anchorGame 업데이트 안 함!
├─ AnchorStateRegistry.setAnchorState() 호출 안 함!
└─ Cold Starting 해결 안 함!

→ closeGame()을 추가로 호출해야 함!
```

**타임라인**:
```
T=7일      Agent.Act() → tryResolve() → resolve()
           ├─ Game Status: DEFENDER_WINS ✅
           ├─ resolvedAt: 기록됨 ✅
           └─ anchorGame: 여전히 address(0) ⚠️

T=7일+1초  다른 게임 생성 시도
           ├─ getAnchorRoot() → 여전히 0xdead... ❌
           ├─ Challenger validation: FAIL ❌
           └─ Cold Starting 지속! ❌

→ 문제: resolve()만으로는 해결 안 됨!
```

---

### 장면 17: Finality Delay - 안전 대기 기간 (17:45-18:30)

**내레이션**:
"게임이 resolve되었습니다. 그런데 바로 closeGame()을 호출할 수 있을까요? 아닙니다! Finality delay라는 대기 시간이 필요합니다. Production에서는 보통 7일, devnet에서는 30-60초입니다. 이 기간 동안 isGameFinalized()는 false를 반환하며, closeGame()을 호출하면 GameNotFinalized 에러로 revert됩니다. 이 함수는 게임이 resolve되었는지와 finality delay가 경과했는지만 체크합니다."

**화면**:
- Finality delay 타임라인
- isGameFinalized() 검증 로직
- Revert 시나리오 시각화

**isGameFinalized() 체크**:
```solidity
// AnchorStateRegistry.sol:276-289 (실제 코드)
function isGameFinalized(IDisputeGame _game) public view returns (bool) {
    // Game must be resolved.
    if (!isGameResolved(_game)) {
        return false;
    }

    // Game must be beyond the "airgap period" - time since resolution must be at least
    // "dispute game finality delay" seconds in the past.
    if (block.timestamp - _game.resolvedAt().raw() <= DISPUTE_GAME_FINALITY_DELAY_SECONDS) {
        return false;
    }

    return true;
}

// 참고: DEFENDER_WINS 체크는 isGameClaimValid()에서 수행됨
```

**isGameClaimValid() - DEFENDER_WINS 체크**:
```solidity
// AnchorStateRegistry.sol:294-316
function isGameClaimValid(IDisputeGame _game) public view returns (bool) {
    // Game must be a proper game.
    if (!isGameProper(_game)) {
        return false;
    }

    // Must be respected.
    if (!isGameRespected(_game)) {
        return false;
    }

    // Game must be finalized.
    if (!isGameFinalized(_game)) {
        return false;
    }

    // 🔥 Game must be resolved in favor of the defender.
    if (_game.status() != GameStatus.DEFENDER_WINS) {
        return false;  // CHALLENGER_WINS는 anchor 불가!
    }

    return true;
}
```

**Finality Delay 상수**:
```solidity
// AnchorStateRegistry.sol:31-32
/// @notice The dispute game finality delay in seconds.
uint256 internal immutable DISPUTE_GAME_FINALITY_DELAY_SECONDS;

// Line 79-83: Constructor에서 설정
constructor(uint256 _disputeGameFinalityDelaySeconds) ReinitializableBase(1) {
    DISPUTE_GAME_FINALITY_DELAY_SECONDS = _disputeGameFinalityDelaySeconds;
    _disableInitializers();
}

// Line 120-123: Getter 함수
function disputeGameFinalityDelaySeconds() external view returns (uint256) {
    return DISPUTE_GAME_FINALITY_DELAY_SECONDS;
}
```

**실제 시나리오**:
```bash
# Step 1: Resolve 직후
T=7일
cast call $ANCHOR_STATE_REGISTRY \
  "isGameFinalized(address)(bool)" $GAME_ADDRESS
→ false ❌

# Step 2: closeGame() 시도하면?
cast send $GAME_ADDRESS "closeGame()"
→ revert GameNotFinalized() ❌

# Step 3: Finality delay 확인
DELAY=$(cast call $ANCHOR_STATE_REGISTRY \
  "disputeGameFinalityDelaySeconds()(uint256)")
echo "Need to wait: $DELAY seconds"
# Production: 604800 (7일)
# Devnet: 30-60초

# Step 4: 대기 후
T=7일 + DELAY
cast call $ANCHOR_STATE_REGISTRY \
  "isGameFinalized(address)(bool)" $GAME_ADDRESS
→ true ✅

# Step 5: 이제 closeGame() 가능!
cast send $GAME_ADDRESS "closeGame()"
→ Success ✅
```

**타임라인 (Production vs Devnet)**:
```
Production 환경:
T=0       게임 생성
T=7일     resolve() 호출
          └─ resolvedAt 기록
T=7~14일  ⏳ Finality Delay (7일)
          ├─ isGameFinalized() → false
          └─ closeGame() 불가능
T=14일    closeGame() 가능 ✅
          └─ anchorGame 업데이트

Devnet 환경:
T=0       게임 생성
T=10분    resolve() 호출
T=10~11분 ⏳ Finality Delay (30-60초)
T=11분    closeGame() 가능 ✅
          └─ 빠른 테스트 사이클
```

**검증 체인 구조**:
```
closeGame() 호출 시 검증 순서:

1. closeGame() (FaultDisputeGame.sol:1046)
   └─ Line 1074: isGameFinalized() 체크
      └─ PASS → 계속

2. closeGame() (Line 1082)
   └─ setAnchorState() 시도

3. setAnchorState() (AnchorStateRegistry.sol:320)
   └─ Line 329: isGameClaimValid() 체크
      │
      ├─ isGameProper() ✅
      ├─ isGameRespected() ✅
      ├─ isGameFinalized() ✅ (다시 체크!)
      │  ├─ isGameResolved() ✅
      │  └─ finality delay 경과 ✅
      └─ status == DEFENDER_WINS ✅
         └─ ALL PASS → anchorGame 업데이트!

→ 다층 방어 (Defense in Depth)
```

**왜 Finality Delay가 필요한가?**:
```
보안 목적:
├─ 잘못된 게임이 즉시 anchor가 되는 것 방지
├─ 버그 발견 시 대응 시간 확보
├─ L1 Reorg에 대한 안전성
└─ 사회적 검토 기간 제공

비유:
"은행 송금의 취소 가능 기간"
└─ 문제 발견 시 되돌릴 수 있는 마지막 기회
```

---

### 장면 18: closeGame() - Line 1082의 마법 (18:30-19:30)

**내레이션**:
"드디어 finality delay가 지났습니다. 이제 closeGame()을 호출할 수 있습니다. 이 함수, 특히 Line 1082의 단 한 줄이 모든 것을 바꿉니다. setAnchorState()가 호출되는 유일한 순간입니다. 이 호출이 없으면 시스템은 영원히 Cold Starting 상태로 남습니다. 이것이 closeGame()이 critical한 이유입니다!"

**화면**:
- closeGame() 코드 하이라이트
- Line 1082 강조 효과
- setAnchorState() 실행 애니메이션

**closeGame() 완전 분석**:
```solidity
// FaultDisputeGame.sol:1046-1097
function closeGame() public {
    // 1. 이미 처리되었는지 확인
    if (bondDistributionMode == BondDistributionMode.REFUND ||
        bondDistributionMode == BondDistributionMode.NORMAL) {
        return;  // Already closed, skip
    }

    // 2. 기본 검증
    if (ANCHOR_STATE_REGISTRY.paused()) revert GamePaused();
    if (resolvedAt.raw() == 0) revert GameNotResolved();

    // 3. Finality 확인
    bool finalized = ANCHOR_STATE_REGISTRY.isGameFinalized(
        IDisputeGame(address(this))
    );
    if (!finalized) revert GameNotFinalized();

    // 4. 🔥🔥🔥 THE CRITICAL LINE 1082 🔥🔥🔥
    // 이 한 줄이 Cold Starting을 해결합니다!
    try ANCHOR_STATE_REGISTRY.setAnchorState(
        IDisputeGame(address(this))
    ) { } catch { }

    // 5. Bond distribution mode 설정
    bool properGame = ANCHOR_STATE_REGISTRY.isGameProper(
        IDisputeGame(address(this))
    );
    bondDistributionMode = properGame
        ? BondDistributionMode.NORMAL
        : BondDistributionMode.REFUND;

    emit GameClosed(bondDistributionMode);
}
```

**Line 1082이 하는 일**:
```solidity
// AnchorStateRegistry.sol:320-342 (실제 코드)
function setAnchorState(IDisputeGame _game) public {
    // Convert game to FaultDisputeGame.
    IFaultDisputeGame game = IFaultDisputeGame(address(_game));

    // 1. Check if the candidate game claim is valid.
    if (!isGameClaimValid(game)) {
        revert AnchorStateRegistry_InvalidAnchorGame();
    }
    // ☝️ isGameClaimValid()가 다음을 모두 체크:
    //    - isGameProper() ✅
    //    - isGameRespected() ✅
    //    - isGameFinalized() ✅ (finality delay!)
    //    - status == DEFENDER_WINS ✅

    // 2. Must be newer than the current anchor game.
    (, uint256 anchorL2BlockNumber) = getAnchorRoot();
    if (game.l2SequenceNumber() <= anchorL2BlockNumber) {
        revert AnchorStateRegistry_InvalidAnchorGame();
    }

    // 3. 🔥 THE MAGIC HAPPENS HERE!
    anchorGame = game;
    // address(0) → 0xGame123...
    // Cold → Warm!

    emit AnchorUpdated(game);
}
```

**전체 실행 시나리오**:
```bash
# Step 1: Resolve
echo "Step 1: Resolving game..."
cast send $GAME_ADDRESS "resolve()" \
  --rpc-url $L1_RPC --private-key $KEY
echo "✅ Game resolved: DEFENDER_WINS"

# Step 2: Check finality delay
echo "Step 2: Checking finality delay..."
DELAY=$(cast call $ANCHOR_STATE_REGISTRY \
  "disputeGameFinalityDelaySeconds()(uint256)" \
  --rpc-url $L1_RPC)
echo "⏳ Need to wait: $DELAY seconds"

# Step 3: Wait
echo "Step 3: Waiting..."
sleep $DELAY

# Step 4: Verify finalized
IS_FINALIZED=$(cast call $ANCHOR_STATE_REGISTRY \
  "isGameFinalized(address)(bool)" $GAME_ADDRESS \
  --rpc-url $L1_RPC)
if [ "$IS_FINALIZED" != "true" ]; then
    echo "❌ Not finalized yet, wait longer"
    exit 1
fi
echo "✅ Game is finalized"

# Step 5: 🔥 Call closeGame() - THE CRITICAL STEP!
echo "Step 5: Calling closeGame()..."
cast send $GAME_ADDRESS "closeGame()" \
  --rpc-url $L1_RPC --private-key $KEY
echo "✅ closeGame() executed"

# Step 6: Verify anchorGame updated
echo "Step 6: Verifying anchorGame update..."
ANCHOR_GAME=$(cast call $ANCHOR_STATE_REGISTRY \
  "anchorGame()(address)" --rpc-url $L1_RPC)

if [ "$ANCHOR_GAME" != "0x0000000000000000000000000000000000000000" ]; then
    echo "🎉 SUCCESS! anchorGame updated to: $ANCHOR_GAME"

    NEW_ROOT=$(cast call $ANCHOR_STATE_REGISTRY \
      "getAnchorRoot()(bytes32,uint256)" \
      --rpc-url $L1_RPC | head -1)
    echo "🎉 New anchor root: $NEW_ROOT"
    echo "🎉 Cold Starting RESOLVED!"
else
    echo "⚠️ anchorGame not updated"
fi
```

**상태 전환 Before/After**:
```
══════════════════════════════════════════════════
Before closeGame() - Cold Starting 지속
══════════════════════════════════════════════════

AnchorStateRegistry:
├─ anchorGame = 0x0000...0000 ❌
└─ getAnchorRoot() returns:
   └─ startingAnchorRoot.root = 0xdead... ❌

Game 2 생성:
├─ startingOutputRoot.root = 0xdead... ❌
└─ Validation: FAIL ❌

Game 3 생성:
├─ startingOutputRoot.root = 0xdead... ❌
└─ Validation: FAIL ❌

══════════════════════════════════════════════════
After closeGame() - Warm State 전환!
══════════════════════════════════════════════════

AnchorStateRegistry:
├─ anchorGame = 0xGame1... ✅
└─ getAnchorRoot() returns:
   └─ anchorGame.rootClaim() = 0xabc123... ✅

Game 2 생성:
├─ startingOutputRoot.root = 0xabc123... ✅
└─ Validation: PASS ✅

Game 3 생성:
├─ startingOutputRoot.root = 0xabc123... ✅
└─ Validation: PASS ✅

→ 모든 후속 게임 성공!
```

Challenger 검증:
├─ Contract: 0xdead...
├─ Provider: 0xabc123... (실제 값)
└─ 불일치! → 게임 스킵 ❌

════════════════════════════════════════════════════
After closeGame() (Warm 상태)
════════════════════════════════════════════════════

AnchorStateRegistry:
├─ anchorGame: 0xGame123... ✅
└─ 유효한 게임 참조!

새 게임 생성 시:
└─ getAnchorRoot()
   └─ returns anchorGame.rootClaim()
   └─ returns 0xabc123... ✅

Challenger 검증:
├─ Contract: 0xabc123...
├─ Provider: 0xabc123...
└─ 일치! → 게임 참여 ✅

결과: 정상 작동! 🎉
```

---

### 장면 19: DEFENDER_WINS vs CHALLENGER_WINS - 운명의 갈림길 (19:30-20:45)

**내레이션**:
"잠깐! 여기서 중요한 질문입니다. DEFENDER_WINS일 때만 anchor를 업데이트한다고요? 그럼 Challenger가 이긴 게 아니라 Defender, 즉 Proposer가 이긴 건가요? 맞습니다! 그리고 이게 핵심입니다. DEFENDER_WINS는 Proposer의 주장이 정확했다는 뜻이고, 그래서 그 상태를 다음 게임의 시작점으로 안전하게 사용할 수 있다는 의미입니다. 반대로 CHALLENGER_WINS면 어떻게 될까요? 시스템이 멈출까요? 아닙니다! Permissionless 시스템이므로 누구나 다시 올바른 값을 제출할 수 있습니다!"

**화면**:
- DEFENDER_WINS vs CHALLENGER_WINS 분기 다이어그램
- Progressive Anchoring 애니메이션
- 재제출 프로세스 시각화

**용어 정리**:
```
DEFENDER = Proposer (제안자)
├─ L2 output root를 제안한 사람
└─ "Block 100의 상태는 0xABC..."라고 주장

CHALLENGER = 검증자
├─ Proposer의 주장을 검증
└─ 틀리면 반박
```

**DEFENDER_WINS vs CHALLENGER_WINS**:
```
┌────────────────────────────────────────────────────────┐
│ Case 1: DEFENDER_WINS (Proposer가 이김) ✅             │
└────────────────────────────────────────────────────────┘

의미:
├─ Proposer의 주장이 **정확했다**! ✅
├─ 제출한 output root가 **유효하다**! ✅
├─ 7일 challenge period 동안 문제 없음! ✅
└─ 이 상태를 **anchor로 사용해도 안전**! ✅

결과:
├─ ✅ anchorGame 업데이트!
├─ ✅ 다음 게임의 starting point로 사용
├─ ✅ Proposer는 bond 회수
└─ ✅ Progressive Anchoring 진행!

예시:
Game 5: Block 400 → 500
├─ Proposer: "Block 500 = 0xABC123..."
├─ 7일 challenge period
├─ Challenger 검증: "맞네! 정확해!"
├─ Result: DEFENDER_WINS ✅
└─ 🔥 anchorGame = Game 5
   └─ 이제 Block 500까지 검증됨!

┌────────────────────────────────────────────────────────┐
│ Case 2: CHALLENGER_WINS (Challenger가 이김) ❌         │
└────────────────────────────────────────────────────────┘

의미:
├─ Proposer의 주장이 **틀렸다**! ❌
├─ 제출한 output root가 **부정확**! ❌
├─ Challenger가 문제 발견! ✅
└─ 이 게임은 **무효**! ❌

결과:
├─ ❌ anchorGame 업데이트 안 됨!
├─ ❌ 이전 anchor 유지
├─ ✅ Proposer는 bond 손실
├─ ✅ Challenger는 bond 획득
└─ ⚠️  해당 블록 범위는 미검증 상태!

예시:
Game 6: Block 500 → 600
├─ Proposer: "Block 600 = 0xBAD456..." ❌ 틀림!
├─ Challenger 검증: "아니야! 실제로는 0xGOOD789..."
├─ Bisection으로 문제 발견
├─ Result: CHALLENGER_WINS ✅
└─ ❌ 이 게임은 무효화
   └─ anchorGame = Game 5 유지 (Block 500)
   └─ Block 600은 여전히 미검증!
```

**CHALLENGER_WINS 후 재제출 프로세스**:
```
T=0:    Game 6 생성 (Block 500 → 600)
        └─ 부정직한 Proposer: "Block 600 = 0xBAD..."

T=7일:  Challenge period 종료
        ├─ Challenger 반박 성공
        └─ Result: CHALLENGER_WINS ✅

        결과:
        ├─ anchorGame = Game 5 유지 (변화 없음)
        ├─ Game 6 무효화
        ├─ Proposer: Bond 손실 💸
        └─ Block 500-600: 여전히 미검증 ⚠️

T=8일:  Game 7 생성 (Block 500 → 600)
        └─ 정직한 Proposer (또는 다른 누군가):
           "Block 600 = 0xGOOD..." ✅

        💡 시스템은 Permissionless!
           누구나 새 게임 제출 가능!

T=15일: Challenge period 종료
        ├─ 문제 없음 확인
        └─ Result: DEFENDER_WINS ✅

        결과:
        ├─ 🔥 anchorGame = Game 7 업데이트!
        ├─ anchor root = Block 600 output root
        └─ Block 600까지 검증 완료! ✅

→ 시스템 정상화!
```

**Progressive Anchoring (점진적 앵커링)**:
```
Game 1: Block 0 → 100
├─ DEFENDER_WINS ✅
└─ anchorGame = Game 1 (Block 100 검증됨)

        ↓ Block 100이 이제 검증된 시작점!

Game 2: Block 100 → 200
├─ Starting: Block 100 ✅ (Game 1에서 검증됨!)
├─ 새로 검증: Block 101~200
├─ DEFENDER_WINS ✅
└─ anchorGame = Game 2 (Block 200 검증됨)

        ↓ Block 200이 이제 검증된 시작점!

Game 3: Block 200 → 300
├─ Starting: Block 200 ✅ (Game 2에서 검증됨!)
├─ DEFENDER_WINS ✅
└─ anchorGame = Game 3

→ 마치 건물을 층층이 쌓듯이!
  검증된 상태를 기반으로 새로운 검증을 쌓아나감!
```

**경제적 인센티브 - 게임 이론**:
```
Proposer 입장:
├─ 정직하게 행동 (올바른 값 제출)
│  ├─ DEFENDER_WINS 기대 ✅
│  ├─ Bond 회수 ✅
│  └─ 수수료/보상 받음 ✅
│  └─ 비용 < 보상 → 이득!
│
└─ 부정직하게 행동 (틀린 값 제출)
   ├─ CHALLENGER_WINS 당함 ❌
   ├─ Bond 손실 ❌
   ├─ 명성 하락 ❌
   └─ 손실만 있고 이득 없음!

Challenger 입장:
├─ 부정직한 주장 발견 & 반박
│  ├─ 반박 성공 → CHALLENGER_WINS ✅
│  ├─ 상대 Bond 획득 ✅
│  └─ 시스템 보호 기여 ✅
│
└─ 정직한 주장에 잘못 반박
   ├─ 반박 실패 → DEFENDER_WINS ❌
   ├─ 내 Bond 손실 ❌
   └─ 손실만 있음!

→ 경제적으로 정직하게 행동하는 게 합리적!
  (Game Theory: Dominant Strategy)
```

**Self-Healing System**:
```
잘못된 게임 발생:
├─ CHALLENGER_WINS로 차단 ✅
├─ 하지만 시스템은 멈추지 않음!
│  └─ Permissionless: 누구나 재제출 가능
│  └─ 올바른 값으로 재제출
│  └─ DEFENDER_WINS → 정상화
└─ 경제적 인센티브가 정직성 보장

핵심:
├─ 잘못된 게임은 자동으로 걸러짐
├─ 올바른 게임만 anchor가 됨
└─ 자가 치유되는 시스템!
```

---

### 장면 20: Phase 6의 중요성 - 생태계 순환 (20:45-21:15)

**내레이션**:
"이제 전체 그림이 완성되었습니다. Phase 6 없이는 시스템이 영구적으로 Cold Starting 상태에 갇히게 됩니다. 첫 게임이 완료되어도 closeGame을 호출하지 않으면 다음 게임들도 모두 검증에 실패합니다. 이것이 바로 게임 생태계의 순환 구조입니다."

**화면**:
- 순환 다이어그램
- 게임 체인 시각화
- 생태계 건강성

**게임 체인 (Game Chain)**:
```
Game 1 (Genesis)
├─ 생성: Cold Starting 상태 ❌
├─ Challenger: skipPrestateValidation=true 필요
├─ 결과: DEFENDER_WINS
└─ 🔥 closeGame() 호출 필수!
   └─ anchorGame = Game1

       ↓

Game 2
├─ 생성: Warm 상태 ✅
├─ startingOutputRoot = Game1.rootClaim
├─ Challenger: 정상 검증 가능 ✅
├─ 결과: DEFENDER_WINS
└─ closeGame() 호출
   └─ anchorGame = Game2

       ↓

Game 3
├─ 생성: Warm 상태 ✅
├─ startingOutputRoot = Game2.rootClaim
└─ 계속 순환...

지속 가능한 생태계! ♻️
```

**closeGame을 호출하지 않으면?**:
```
Game 1 완료 (resolve만 호출)
├─ Status: DEFENDER_WINS ✅
├─ 게임은 종료됨
└─ ❌ closeGame() 호출 안 함!

AnchorStateRegistry:
└─ anchorGame: 여전히 address(0) ❌

Game 2 생성:
├─ startingOutputRoot: 0xdead... ❌
└─ Challenger: 검증 실패, 게임 스킵 ❌

Game 3, 4, 5... 모두 동일:
└─ 영구적으로 검증 실패 ❌

시스템 마비! 🚨
```

**운영 체크리스트 (중요!)**:
```
✅ 1. 첫 게임 생성
   └─ skipPrestateValidation=true 설정

✅ 2. 첫 게임 완료 대기 (7일)
   └─ resolve() 호출

✅ 3. Finality delay 대기 (3.5일)
   └─ 총 10.5일 대기

✅ 4. 🔥 closeGame() 호출! (절대 잊지 말 것!)
   └─ AnchorStateRegistry 업데이트

✅ 5. 이후 게임들 자동화
   └─ 주기적으로 closeGame() 호출
```

---

## 파트 7: 마무리 및 핵심 요약 (20:00-22:00)

### 장면 20: 전체 플로우 리캡 (20:00-21:00)

**내레이션**:
"전체 과정을 다시 정리해보죠. Proposer가 게임을 생성하면 Challenger가 이를 발견합니다. 두 개의 Validator가 VM prestate와 output root를 검증합니다. 검증을 통과하면 GamePlayer가 생성되고, Agent가 주기적으로 모든 claim을 검증하며 필요한 반박을 제출합니다. 마지막으로, 게임이 종료되면 resolve와 closeGame을 통해 AnchorStateRegistry를 업데이트하여 다음 게임들이 정상적으로 작동할 수 있게 만듭니다!"

**화면**:
- 전체 플로우 애니메이션 (빠른 속도로)
- 각 단계 하이라이트
- 타임라인 시각화

**시간순 요약**:
```
T=0      Phase 1: Proposer가 게임 생성
         └─ AnchorStateRegistry 스냅샷

T=5분    Phase 2: Scheduler가 게임 발견
         └─ coordinator.createJob() 호출

T=5분05초 Phase 3: Player 생성 시작
         ├─ coordinator.createPlayer()
         │  └─ playerCreator() 실행
         ├─ Contract 정보 조회
         ├─ Validators 생성 (실행 안 함!)
         ├─ GamePlayer 생성
         └─ Agent, TraceAccessor 초기화

T=5분10초 Phase 4: 검증 실행
         ├─ player.ValidatePrestate() 호출
         ├─ Validator 1: VM Prestate
         │  └─ 파일서버 검증 ✅
         └─ Validator 2: Output Root
            └─ L2 RPC 과거 블록 조회
            └─ Cold: FAIL ❌ / Warm: PASS ✅

T=5분20초 검증 결과 처리
         ├─ PASS → state.player에 저장
         └─ newJob(player) 생성

T=6분~   Phase 5: 게임 진행
         ├─ worker가 job 처리
         ├─ player.ProgressGame() 주기적 호출
         ├─ agent.Act() 실행
         ├─ 모든 claim 검증
         ├─ Counter claim 제출
         └─ Bisection 진행

T=7일    Phase 6: 게임 종료 및 Anchor 업데이트
         ├─ resolve() 호출
         │  └─ Status: CHALLENGER_WINS / DEFENDER_WINS
         ├─ Finality delay 대기
         │  └─ DISPUTE_GAME_FINALITY_DELAY_SECONDS
         │     (Production: 7일, Devnet: 30-60초)
         └─ 🔥 closeGame() 호출!
            └─ anchorGame 업데이트 ← Cold → Warm 전환!
```

---

### 장면 21: 핵심 교훈과 베스트 프랙티스 (21:00-22:00)

**내레이션**:
"마지막으로 핵심을 정리하겠습니다. 첫째, Phase 3에서 Validator를 생성하고 Phase 4에서 실행합니다. 둘째, Phase 4의 사전 검증은 참여 가능 여부만 판단하고, Phase 5의 Game Logic이 실제 완전 검증을 담당합니다. 셋째, Phase 6이 가장 중요합니다! closeGame을 호출하지 않으면 시스템이 영구적으로 Cold Starting 상태에 갇힙니다. 넷째, 과거 블록 조회를 위해 Archive Node가 필수입니다."

**화면**:
- 핵심 메시지 카드
- 체크리스트
- "감사합니다!" 엔딩

**핵심 포인트**:
```
✅ 1. 6단계 Phase 구분 명확히
   Phase 1: 게임 생성 (Proposer → L1 Contract)
   Phase 2: 게임 발견 (Scheduler Monitor)
   Phase 3: Player 생성 (Validators + GamePlayer)
   Phase 4: ValidatePrestate 실행 (사전 검증!)
   Phase 5: ProgressGame (게임 진행 및 완전 검증)
   Phase 6: resolve + closeGame (🔥 Anchor 업데이트!) ⭐⭐⭐

✅ 2. 두 단계 검증
   Phase 4 Validator: 빠른 사전 체크 (starting point만)
   Phase 5 Game Logic: 완전한 검증 (모든 블록)

✅ 3. Phase 6 - closeGame()의 Critical한 중요성! 🚨
   ⚠️  resolve()만으로는 anchorGame 업데이트 안 됨!
   ⚠️  Line 1082: setAnchorState()는 closeGame()만 호출!
   ⚠️  closeGame() 없으면 영구 Cold Starting!

   완전한 3단계 프로세스:
   Step 1: resolve() 호출 → 게임 상태만 변경
   Step 2: Finality delay 대기
          Production: 7일 (DISPUTE_GAME_FINALITY_DELAY_SECONDS)
          Devnet: 30-60초 (빠른 테스트용)
   Step 3: closeGame() 호출 → anchorGame 업데이트! ✅

   💡 claimCredit()도 closeGame() 호출하지만,
      명시적 closeGame() 호출이 Production에 더 안전!

✅ 4. coordinator.go의 역할
   └─ createPlayer() → ValidatePrestate() 순서로 호출
   └─ 검증 통과하면 state.player에 저장
   └─ job 생성 후 worker에 전달

✅ 5. 두 단계 검증의 역할 분리
   Validator (Phase 4):
   └─ 1개 블록만 체크 (starting point)
   └─ 빠른 참여 가능 여부 판단

   Game Logic (Phase 5):
   └─ 모든 중간 블록 검증 (Bisection)
   └─ 완전한 보안 검증

✅ 6. 과거 블록 조회
   └─ Archive Node 필수
   └─ 블록체인 불변성 활용
   └─ Validator 2와 TraceProvider 모두 사용

✅ 7. TraceProvider 핵심
   └─ 모든 중간 블록 검증
   └─ Bisection마다 L2 RPC 호출
   └─ OutputAtBlock()으로 과거 블록 조회

✅ 7. Game Chain 순환
   └─ 각 게임이 다음 게임의 anchor가 됨
   └─ closeGame()으로 체인 유지 필수
```

**운영 체크리스트**:
```
초기 설정:
□ L2 Archive Node 실행 중
□ 파일서버 prestate 파일 준비
□ AnchorStateRegistry 올바르게 초기화
□ skipPrestateValidation 플래그 올바르게 설정

첫 게임 처리 (Genesis Game):
□ skipPrestateValidation=true로 설정
□ 게임 완료 대기 (7일)
□ resolve() 호출
□ Finality delay 대기 (3.5일)
□ 🔥 closeGame() 호출! ← 절대 잊지 말 것!

운영 자동화:
□ 게임 완료 시 자동 resolve
□ Finality delay 후 자동 closeGame
□ Challenger 로그 모니터링
□ AnchorStateRegistry 상태 주기적 확인
```

---

## 시각적 자료 목록

1. **시스템 아키텍처 다이어그램**: L1 Contract, Off-Chain Actors, L2 Node (3계층)
2. **전체 생명주기 다이어그램**: Phase 1~6 전체 플로우
3. **게임 생성 애니메이션**: Proposer → DisputeGameFactory
4. **Scheduler 모니터링**: 게임 발견 과정
5. **Validator 실행 플로우**: 두 검증의 순차 실행
6. **VM 메모리 구조**: Prestate 내부
7. **L2 블록체인 타임라인**: 과거 블록 조회 메커니즘
8. **AnchorStateRegistry 상태**: Cold vs Warm
9. **GamePlayer 컴포넌트**: 내부 구조
10. **Bisection 과정**: TraceProvider.Get 호출
11. **역할 분리 다이어그램**: Validator vs Game Logic
12. **게임 종료 타임라인**: resolve → finality delay → closeGame
13. **검증 체인 구조**: closeGame() → isGameFinalized() → isGameClaimValid()
14. **Cold → Warm 전환**: AnchorStateRegistry 업데이트 전후
15. **DEFENDER_WINS vs CHALLENGER_WINS**: 분기 다이어그램 ⭐ 신규!
16. **Progressive Anchoring**: 점진적 앵커링 애니메이션 ⭐ 신규!
17. **재제출 프로세스**: CHALLENGER_WINS 후 복구 과정 ⭐ 신규!
18. **경제적 인센티브**: 게임 이론 다이어그램 ⭐ 신규!
19. **게임 체인 순환**: Game1 → Game2 → Game3...
20. **시간순 타임라인**: 실제 시나리오 (Phase 1~6)
21. **핵심 요약 차트**: 주요 메시지

---

## 기술적 세부사항

- **프레임레이트**: 30fps
- **해상도**: 1920x1080
- **음성**: 한국어 내레이션 (또는 영어)
- **자막**: 한국어 + 영어 병기
- **애니메이션 스타일**:
  - 단계별 진행 강조
  - 코드 블록 하이라이트
  - 플로우 애니메이션
  - 성공/실패 시각화
- **색상 테마**:
  - Optimism 브랜드 컬러 (빨간색 #FF0420)
  - 성공: 초록색
  - 실패: 빨간색
  - 중립: 회색/파란색
- **속도 조절**:
  - 개요: 빠르게
  - 상세: 천천히
  - 리캡: 중간 속도

---

## 대상 청중별 추가 설명

### 개발자
- 코드 파일 경로 명시
- 함수 시그니처 포함
- Go 코드 스니펫 상세

### 시스템 관리자
- 운영 체크리스트
- 문제 해결 가이드
- 로그 메시지 예시

### 보안 연구자
- 공격 시나리오 분석
- 검증 메커니즘 깊이
- Byzantine 환경 고려사항

### 일반 사용자
- 전체 시스템 이해
- 왜 중요한가?
- 신뢰할 수 있는 이유

---

## 마지막 메시지

이 스크립트는 Challenger의 전체 동작을 처음부터 끝까지 6단계로 설명하며, 각 단계의 목적과 중요성을 명확히 전달합니다.

**특히 Phase 6 (게임 종료 및 Anchor 업데이트)은 시스템 운영에 필수적입니다:**
- 게임이 완료되어도 `closeGame()`을 호출하지 않으면 시스템이 영구적으로 Cold Starting 상태에 갇힙니다
- `resolve()` → finality delay 대기 → `closeGame()` 순서를 반드시 지켜야 합니다
- 이것이 게임 생태계의 순환 구조를 만들어 지속 가능한 시스템을 보장합니다

**핵심을 다시 한 번:**
1. Phase 1-2: 게임 생성과 발견
2. Phase 3-4: Player 생성 및 사전 검증 (참여 가능 여부 판단)
3. Phase 5: 게임 진행 (모든 claim 완전 검증)
4. **Phase 6: 게임 종료 및 Anchor 업데이트 (다음 게임을 위한 순환 구조)** ⭐

감사합니다!