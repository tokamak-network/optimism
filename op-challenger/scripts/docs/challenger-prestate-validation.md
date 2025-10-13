# Challenger Prestate 및 State Root 검증 과정

## 개요

op-challenger가 dispute game에 참여할 때 prestate와 state root를 어떻게 검증하는지에 대한 상세한 분석입니다.

## 검증 과정 개요

챌린저는 두 가지 핵심 값을 검증합니다:
1. **absolutePrestate**: VM의 절대 prestate 해시
2. **startingRootHash**: L2 output root (starting state root)

## 전체 검증 플로우차트

```
┌─────────────────────────────────────────────────────────────┐
│ Challenger가 새로운 Dispute Game 발견                         │
│ (op-challenger/game/scheduler.go)                           │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ GamePlayer 생성                                              │
│ (op-challenger/game/fault/register_task.go:292-340)         │
└─────────────────────────────────────────────────────────────┘
                        ↓
        ┌───────────────┴───────────────┐
        ↓                               ↓
┌──────────────────┐          ┌──────────────────┐
│ skipPrestateValidation?     │                  │
│ (Line 336)                  │                  │
└──────────────────┘          │                  │
        ↓                     │                  │
       Yes                    No                 │
        ↓                     ↓                  │
┌──────────────────┐   ┌──────────────────────┐ │
│ Validation SKIP  │   │ Validator 생성       │ │
│ (Permissioned    │   │ (Line 337-338)       │ │
│  게임)           │   └──────────────────────┘ │
└──────────────────┘            ↓               │
                        ┌───────┴───────┐       │
                        ↓               ↓       │
              ┌──────────────┐  ┌──────────────┐
              │ Validator 1  │  │ Validator 2  │
              │ (VM prestate)│  │ (Output root)│
              └──────────────┘  └──────────────┘
                        ↓               ↓
                        └───────┬───────┘
                                ↓
                    ┌──────────────────────┐
                    │ 두 검증 모두 통과?    │
                    └──────────────────────┘
                            ↓
                    ┌───────┴───────┐
                    ↓               ↓
                  Yes              No
                    ↓               ↓
        ┌──────────────────┐  ┌──────────────────┐
        │ ✅ Challenger    │  │ ❌ Error 로그     │
        │    게임 참여     │  │    게임 스킵     │
        └──────────────────┘  └──────────────────┘
```

### skipPrestateValidation이란?

**목적**: 특정 게임 타입에서 prestate validation을 건너뛰는 플래그

**언제 true인가?**
```go
// op-challenger/game/fault/register_task.go
skipPrestateValidation: gameType == faultTypes.PermissionedGameType
skipPrestateValidation: gameType == faultTypes.SuperPermissionedGameType
```

**왜 필요한가?**
1. **Permissioned 게임**: 신뢰할 수 있는 참여자만 참여
   - Prestate validation 불필요 (신뢰 기반)
   - Cold Starting 문제 회피
   - 빠른 개발/테스트

2. **Cold Starting 상태**:
   - 0xdead... 값으로 인한 validation 실패 회피
   - 임시 해결책으로 사용

**동작**:
```go
if !e.skipPrestateValidation {
    // false면 → Validator 생성 ✅
    validators = append(validators, ...)
} else {
    // true면 → Validator 생성 안 함 ❌
    // 검증 없이 바로 게임 참여!
}
```

**적용 게임 타입**:
- ✅ Skip: `PermissionedGameType` (Type 1)
- ✅ Skip: `SuperPermissionedGameType` (Type 255)
- ❌ Skip 안 함: `CannonGameType` (Type 0)
- ❌ Skip 안 함: `SuperCannonGameType` (Type 254)

**상세 설명**: [해결 방안 섹션](#1-skipprestatevalidation-플래그-현재-구현) 참조

## Prestate 및 State Root Validation 과정

### 1. Validator 생성

**파일**: `/Users/zena/tokamak-projects/optimism/op-challenger/game/fault/register_task.go:336-338`

```go
if !e.skipPrestateValidation {
    validators = append(validators, NewPrestateValidator(e.gameType.String(), contract.GetAbsolutePrestateHash, vmPrestateProvider))
    validators = append(validators, NewPrestateValidator("output root", contract.GetStartingRootHash, prestateProvider))
}
```

두 개의 validator가 생성됩니다:

#### Validator 1: absolutePrestate Validator (VM Prestate)

**역할**: VM(Virtual Machine) 실행의 초기 상태 해시를 검증

**검증 대상**:
- Cannon/Asterisc VM의 초기 메모리 상태
- 초기 레지스터 값
- 초기 프로그램 카운터(PC)
- 이 모든 것의 해시: `absolutePrestate`

**데이터 소스**:
- **Contract**: FaultDisputeGame.absolutePrestate() 호출
- **Provider**: 파일서버에서 prestate 파일 다운로드 (vmPrestateProvider)

**왜 중요한가?**:
- 🎯 Fault Proof의 **시작점** 정의
- 🎯 Trace bisection이 어떤 VM 상태에서 시작하는지 결정
- 🎯 잘못된 prestate → 부정직한 증명 가능 → 보안 위험
- 🎯 모든 challenger가 동일한 VM 초기 상태 사용 보장

**검증 예시**:
```
Contract: "VM은 0x03a1a135... 상태에서 시작해야 해"
Provider: 파일서버의 prestate-mt64Next.bin.gz에서 계산 → 0x03a1a135...
비교: 같음 → ✅ 올바른 VM 초기 상태!
```

**실패 시 영향**:
- ❌ Challenger가 게임 참여 거부
- ❌ "VM prestate does not match" 에러
- ❌ Trace 검증 불가능

---

#### Validator 2: output root Validator (Starting State Root)

**역할**: L2 체인의 시작 블록 output root를 검증

**검증 대상**:
- 게임이 시작하는 L2 블록의 output root
- AnchorStateRegistry에서 온 값의 유효성
- 예: Block 100의 output root

**데이터 소스**:
- **Contract**: FaultDisputeGame.startingOutputRoot.root 호출
- **Provider**: L2 RPC를 통한 과거 블록 조회 (prestateProvider)

**동작 메커니즘**:
```go
// 1. Contract에서 블록 번호 가져오기
prestateBlock = game.startingOutputRoot.l2SequenceNumber  // 예: 100

// 2. L2 RPC에 과거 블록 요청
providerHash = rollupClient.OutputAtBlock(prestateBlock)
// → "Block 100의 output root 주세요" (현재 Block 500이어도)
// → Archive Node가 과거 데이터 반환

// 3. 비교
contractHash (0xdead... or valid) vs providerHash (valid)
```

**왜 중요한가?**:
- 🎯 Output Root Bisection의 **하한선** 정의
- 🎯 게임이 검증할 L2 블록 범위의 시작점
- 🎯 이전 유효한 게임과의 연결고리 (Progressive Anchoring)
- 🎯 모든 게임이 검증된 과거 상태에서 시작 보장

**검증 예시**:
```
Game 3 검증:
  Contract: "Block 100의 root는 0xabc123...이야"
  Provider: L2 RPC.OutputAtBlock(100) → 0xabc123...
  비교: 같음 → ✅ 올바른 starting point!

  → 이제 Block 100→300 범위를 안전하게 검증 가능
```

**Cold Starting 문제**:
```
Contract: "Block 100의 root는 0xdead...이야" ❌ (잘못된 값!)
Provider: L2 RPC.OutputAtBlock(100) → 0xabc123... ✅ (실제 값)
비교: 다름 → ❌ Validation FAIL!
```

**실패 시 영향**:
- ❌ Challenger가 게임 참여 거부
- ❌ "output root absolute prestate does not match" 에러
- ❌ Output bisection 시작 불가능
- ❌ Cold Starting 상태 지속

---

### 두 Validator의 상호 작용

**독립적 검증**:
- 각 validator는 독립적으로 실행
- 하나라도 실패하면 전체 실패
- 두 개 모두 통과해야 게임 참여 가능

**검증 순서**:
```
1. Validator 1 (VM Prestate) 실행
   └─ PASS → 다음으로
   └─ FAIL → 즉시 중단

2. Validator 2 (Output Root) 실행
   └─ PASS → 게임 참여 ✅
   └─ FAIL → 게임 스킵 ❌
```

**실제 시나리오**:
```
Cold Starting 상태:
  ├─ Validator 1: ✅ PASS (VM prestate 정상)
  └─ Validator 2: ❌ FAIL (0xdead... 문제)
  → 결과: 게임 참여 불가 ❌

Warm 상태:
  ├─ Validator 1: ✅ PASS (VM prestate 정상)
  └─ Validator 2: ✅ PASS (valid anchor root)
  → 결과: 게임 참여 가능 ✅
```

### 두 Validator 상세 비교표

| 특성 | Validator 1 (VM Prestate) | Validator 2 (Output Root) |
|------|--------------------------|---------------------------|
| **검증 대상** | VM 초기 메모리/레지스터 상태 | L2 블록의 output root |
| **Contract 값** | `absolutePrestate()` | `startingOutputRoot.root` |
| **Provider 타입** | `vmPrestateProvider` | `prestateProvider` (OutputPrestateProvider) |
| **데이터 소스** | 파일서버 (HTTP) | L2 RPC (Archive Node) |
| **조회 방법** | 파일 다운로드 (.bin.gz, .json.gz) | RPC 호출 (OutputAtBlock) |
| **블록 번호 필요?** | ❌ 불필요 (파일 해시로 조회) | ✅ 필요 (prestateBlock) |
| **과거 데이터 조회?** | ❌ 불필요 (정적 파일) | ✅ 필요 (과거 블록 조회) |
| **사용 단계** | Trace Bisection | Output Bisection |
| **변경 빈도** | 거의 없음 (VM 업그레이드 시만) | 자주 (anchor 업데이트마다) |
| **Cold Starting 영향** | ✅ 영향 없음 | ❌ 영향 큼 (0xdead... 문제) |
| **실패 메시지** | "VM prestate does not match" | "output root absolute prestate does not match" |

### 게임 진행 단계별 Validator 역할

```
┌────────────────────────────────────────────────────────────┐
│ Dispute Game 전체 구조                                      │
└────────────────────────────────────────────────────────────┘

1️⃣ Output Root Bisection (Validator 2가 기준 제공)
   ┌─────────────────────────────────────────┐
   │ Starting: Block 100 (Validator 2 검증)  │
   │    ↓                                    │
   │ Bisection: Block 100 → 200 → 300        │
   │    ↓                                    │
   │ Leaf: Block 299 vs Block 300            │
   └─────────────────────────────────────────┘
                    ↓
2️⃣ Trace Bisection (Validator 1이 기준 제공)
   ┌─────────────────────────────────────────┐
   │ VM Initial State (Validator 1 검증)     │
   │    ↓                                    │
   │ Bisection: Instruction 0 → 1000 → ...   │
   │    ↓                                    │
   │ Single Step: Instruction 54321          │
   └─────────────────────────────────────────┘

결론: 두 Validator 모두 필수!
- Validator 1 없이 → Trace 검증 불가능
- Validator 2 없이 → Output 검증 불가능
```

### 실제 값 예시

```
Game 3 검증 (L2 current = Block 500):

Validator 1 (VM Prestate):
  Contract Value:  0x03a1a13511403f206bb2414e3bf974f8b4608ad8f7b37ee6642f6598dbe06195
  Provider Value:  0x03a1a13511403f206bb2414e3bf974f8b4608ad8f7b37ee6642f6598dbe06195
  Source:          fileserver/prestate-mt64Next.bin.gz
  Result:          ✅ PASS

Validator 2 (Output Root):
  Contract Value:  0xdead000000... (Cold) or 0xabc123... (Warm)
  Provider Value:  0xabc123... (L2 RPC.OutputAtBlock(100))
  Source:          L2 Archive Node, Block 100 (400 블록 전)
  Result:          ❌ FAIL (Cold) or ✅ PASS (Warm)

Overall:
  Cold Starting: ❌ FAIL → 게임 스킵
  Warm State:    ✅ PASS → 게임 참여
```

## 🎯 중요: Validator vs Game Logic의 역할 분리

### 흔한 오해

**Q**: "Validator가 Block 100만 체크하면, 중간 Block 150, 175, 200에 문제가 있을 수 있는데 어떻게 믿고 통과하나?"

**A**: Validator는 "사전 체크"일 뿐입니다. 실제 검증은 Dispute Game Logic이 합니다!

### 검증의 두 단계

```
┌─────────────────────────────────────────────────────────────┐
│ Stage 1: Validator (게임 참여 전) - "참여 가능한가?"         │
└─────────────────────────────────────────────────────────────┘

목적: 게임의 시작 조건이 올바른지 확인
검증 범위: starting point만 (Block 100)
실패 시: 게임 참여 거부

Validator:
  ✅ Block 100의 starting root 확인
  ❌ Block 150, 175, 200은 확인 안 함!

이유: "이 게임에 참여해도 되는가?"만 판단
      실제 검증은 게임 로직이 할 것


┌─────────────────────────────────────────────────────────────┐
│ Stage 2: Dispute Game Logic (게임 진행 중) - "주장이 맞나?" │
└─────────────────────────────────────────────────────────────┘

목적: Proposer의 모든 주장을 완전히 검증
검증 범위: Block 100→200 사이의 모든 블록
실패 시: 틀린 claim에 반박

TraceProvider.Get(position):
  ✅ Block 100: L2 RPC.OutputAtBlock(100)
  ✅ Block 125: L2 RPC.OutputAtBlock(125)
  ✅ Block 150: L2 RPC.OutputAtBlock(150)
  ✅ Block 175: L2 RPC.OutputAtBlock(175)
  ✅ Block 200: L2 RPC.OutputAtBlock(200)

  → Bisection으로 모든 블록 검증!
```

### 실제 코드: TraceProvider.Get()

**파일**: `op-challenger/game/fault/trace/outputs/provider.go:88-94`

```go
func (o *OutputTraceProvider) Get(ctx context.Context, pos types.Position) (common.Hash, error) {
    // Position에서 블록 번호 계산
    outputBlock, err := o.HonestBlockNumber(ctx, pos)
    // 예: pos에 따라 100, 125, 150, 175, 200...

    // 🔥 해당 블록의 실제 값을 L2 RPC로 조회!
    return o.outputAtBlock(ctx, outputBlock)
    // → rollupClient.OutputAtBlock(ctx, outputBlock)
    // → 각 bisection 단계마다 호출됨!
}

func (o *OutputTraceProvider) outputAtBlock(ctx context.Context, block uint64) (common.Hash, error) {
    output, err := o.rollupProvider.OutputAtBlock(ctx, block)
    // ← 모든 중간 블록이 여기서 검증됨!
    return common.Hash(output.OutputRoot), nil
}
```

### Game 2 상세 검증 시나리오

```
═══════════════════════════════════════════════════════════════
Validator 단계 (1회, 게임 참여 전)
═══════════════════════════════════════════════════════════════

Validator 2:
  Check: Block 100 = 0xabc123... ✅
  Result: PASS → 게임 참여 가능

  💡 이 단계에서는 Block 100만 체크!

═══════════════════════════════════════════════════════════════
Dispute Game Logic (여러 번, 게임 진행 중)
═══════════════════════════════════════════════════════════════

Proposer의 rootClaim: "Block 200 = 0xdef456..."

Round 1 (Depth 0):
  Position: [100 ←→ 200]
  Challenger.Get(position) 호출
  → HonestBlockNumber() = 200
  → OutputAtBlock(200) ← 🔥 L2 RPC 호출!
  → 실제 값: 0xdef456...

  비교: rootClaim(0xdef456...) == Honest(0xdef456...)
  → ✅ Agree, 반박 안 함

Round 2 (Depth 1):
  Proposer가 중간값 제시: "Block 150 = 0xmid150..."

  Challenger.Get(position) 호출
  → HonestBlockNumber() = 150
  → OutputAtBlock(150) ← 🔥 L2 RPC 호출!
  → 실제 값: 0xmid150...

  비교: Proposer(0xmid150...) == Honest(0xmid150...)
  → ✅ Agree

Round 3 (Depth 2):
  Proposer: "Block 125 = 0xmid125..."

  Challenger.Get(position) 호출
  → OutputAtBlock(125) ← 🔥 L2 RPC 호출!
  → 비교 및 검증 ✅

... (계속 bisection)

Result: Block 100→200 사이의 모든 블록이 검증됨!
```

### 만약 Block 175에 문제가 있다면?

```
Round N: [150 ←→ 200] bisection
  Proposer: "Block 175 = 0xBAD175..." ❌ 잘못된 값!

  Challenger.Get(position):
  → OutputAtBlock(175) = 0xGOOD175... ✅ 실제 값

  비교: 0xBAD175... != 0xGOOD175...
  → ❌ Disagree!

  Challenger의 행동:
  → Attack claim 제출
  → 올바른 값 0xGOOD175... 제출
  → Bisection 계속
  → 최종적으로 Proposer의 잘못된 claim 증명
  → Challenger 승리!
```

## 📊 검증 범위 비교

| 단계 | 검증 블록 | 횟수 | 목적 |
|------|----------|------|------|
| **Validator** | Block 100 | 1회 | 참여 조건 확인 |
| **Game Logic** | Block 100, 125, 137, 150, 162, 175, 187, 193, 200... | 수십~수백 회 | 모든 블록 완전 검증 |

**결론**:
- Validator: "시작 조건만 체크" (1개 블록)
- Game Logic: "전체 범위 완전 검증" (모든 블록)
- 두 단계가 결합되어 완벽한 검증!

## 🔍 왜 이렇게 설계했나?

### 효율성

```
만약 Validator가 모든 블록을 체크한다면:
  → Block 100, 101, 102, ..., 200 (100개 블록)
  → 모든 게임마다 100번 RPC 호출
  → 게임 참여 전에 너무 오래 걸림 ❌

현재 설계:
  → Validator: Block 100만 (1번 RPC)
  → 빠르게 참여 가능 여부 판단
  → 실제 검증은 게임 중에 필요한 것만
  → 효율적! ✅
```

### 보안성

```
Validator가 Block 100만 체크해도:
  → Game Logic이 모든 블록 검증
  → Bisection으로 철저히 확인
  → 문제 있으면 반드시 발견
  → 안전함! ✅
```

## Validator 통과 후 게임 시작 전체 코드 흐름

### 코드 호출 체인

```
┌─────────────────────────────────────────────────────────────┐
│ 1. RegisterTask.Register()                                   │
│    (register_task.go:277-352)                                │
│    → playerCreator 함수 등록                                  │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. playerCreator() 호출                                      │
│    (register_task.go:292-341)                                │
│    → 새 게임 발견 시 자동 호출됨                              │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. NewGamePlayer()                                           │
│    (player.go:88-162)                                        │
│    → GamePlayer 객체 생성 (validators 포함)                  │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. ValidatePrestate()                                        │
│    (player.go:165-171)                                       │
│    → 🔥 여기서 Validators 실행!                               │
└─────────────────────────────────────────────────────────────┘
                        ↓
                 ┌──────┴──────┐
                 ↓             ↓
              PASS           FAIL
                 ↓             ↓
┌─────────────────────┐  ┌─────────────────────┐
│ 5. ProgressGame()   │  │ Error 반환          │
│    (player.go:178)  │  │ 게임 생성 실패      │
│    → 게임 참여 시작 │  │ 다른 게임 계속 확인 │
└─────────────────────┘  └─────────────────────┘
         ↓
┌─────────────────────────────────────────────────────────────┐
│ 6. agent.Act()                                               │
│    (agent.go:79-112)                                         │
│    → 실제 게임 로직 실행                                       │
│    → Claims 분석 및 Counter claim 제출                       │
└─────────────────────────────────────────────────────────────┘
```

### Step 1: playerCreator 함수 등록

**파일**: `op-challenger/game/fault/register_task.go:292-346`

```go
func (e *RegisterTask) Register(...) error {
    // playerCreator: 새 게임이 발견되면 이 함수가 호출됨
    playerCreator := func(game types.GameMetadata, dir string) (scheduler.GamePlayer, error) {
        // Contract 연결
        contract, err := contracts.NewFaultDisputeGameContract(ctx, m, game.Proxy, caller)

        // Prestate 준비
        requiredPrestatehash, err := contract.GetAbsolutePrestateHash(ctx)
        vmPrestateProvider, err := e.getBottomPrestateProvider(ctx, requiredPrestatehash)

        // 게임 범위 가져오기
        prestateBlock, poststateBlock, err := contract.GetGameRange(ctx)

        // Output prestate provider 생성
        prestateProvider, err := e.getTopPrestateProvider(ctx, prestateBlock)

        // TraceAccessor creator 함수
        creator := func(ctx context.Context, logger log.Logger, gameDepth faultTypes.Depth, dir string) (faultTypes.TraceAccessor, error) {
            accessor, err := e.newTraceAccessor(logger, m, prestateProvider, vmPrestateProvider, ...)
            return accessor, nil
        }

        // Line 335-339: 🔥 Validators 생성
        var validators []Validator
        if !e.skipPrestateValidation {
            validators = append(validators,
                NewPrestateValidator(e.gameType.String(), contract.GetAbsolutePrestateHash, vmPrestateProvider))
            validators = append(validators,
                NewPrestateValidator("output root", contract.GetStartingRootHash, prestateProvider))
        }

        // Line 340: GamePlayer 생성 (validators 전달!)
        return NewGamePlayer(ctx, systemClock, l1Clock, logger, m, dir, game.Proxy,
                            txSender, contract, e.syncValidator, validators,
                            creator, l1HeaderSource, selective, claimants)
    }

    // Line 346: playerCreator 등록
    registry.RegisterGameType(e.gameType, playerCreator)
    // → 이제 새 게임 발견 시 playerCreator가 자동 호출됨

    return nil
}
```

### Step 2: NewGamePlayer() - GamePlayer 생성

**파일**: `op-challenger/game/fault/player.go:88-162`

```go
func NewGamePlayer(
    ctx context.Context,
    // ... 파라미터들 ...
    validators []Validator,  // ← Validators 받음
    creator types.TraceAccessorGenerator,
    // ...
) (*GamePlayer, error) {
    logger = logger.New("game", addr)

    // 게임 상태 확인
    status, err := loader.GetStatus(ctx)
    if err != nil {
        return nil, fmt.Errorf("failed to fetch game status: %w", err)
    }

    // 이미 끝난 게임이면 간단한 player 반환
    if status != gameTypes.GameStatusInProgress {
        logger.Info("Game already resolved", "status", status)
        return &GamePlayer{
            logger:             logger,
            loader:             loader,
            prestateValidators: validators,
            status:             status,
            act:                actNoop,  // 아무것도 안 하는 함수
        }, nil
    }

    // 진행 중인 게임이면 본격적으로 준비

    // 게임 파라미터 로드
    maxClockDuration, err := loader.GetMaxClockDuration(ctx)
    gameDepth, err := loader.GetMaxGameDepth(ctx)

    // Line 121: 🔥 TraceAccessor 생성 (중요!)
    accessor, err := creator(ctx, logger, gameDepth, dir)
    // → OutputTraceProvider 생성
    // → 이 accessor가 TraceProvider.Get()을 제공
    // → Bisection 중 L2 RPC 호출에 사용됨!

    // Oracle, Preimage uploader 등 준비
    oracle, err := loader.GetOracle(ctx)
    direct := preimages.NewDirectPreimageUploader(logger, txSender, loader)
    large := preimages.NewLargePreimageUploader(logger, l1Clock, txSender, oracle)
    uploader := preimages.NewSplitPreimageUploader(direct, large, minLargePreimageSize)

    // Responder 생성 (claim 제출용)
    responder, err := responder.NewFaultResponder(logger, txSender, loader, uploader, oracle)

    // Line 153: 🔥 Agent 생성 (실제 게임 로직!)
    agent := NewAgent(m, systemClock, l1Clock, loader, gameDepth, maxClockDuration,
                     accessor,   // ← TraceProvider 포함
                     responder,  // ← Claim 제출기
                     logger, selective, claimants)

    // GamePlayer 반환
    return &GamePlayer{
        act:                agent.Act,  // ← 실제 게임 액션!
        loader:             loader,
        logger:             logger,
        status:             status,
        gameL1Head:         l1Head,
        syncValidator:      syncValidator,
        prestateValidators: validators,  // ← Validators 저장
    }, nil
}
```

### Step 3: ValidatePrestate() - 실제 검증 실행

**파일**: `op-challenger/game/fault/player.go:165-171`

```go
func (g *GamePlayer) ValidatePrestate(ctx context.Context) error {
    // 🔥 여기서 모든 Validators 실행!
    for _, validator := range g.prestateValidators {
        if err := validator.Validate(ctx); err != nil {
            // 하나라도 실패하면 즉시 에러 반환
            return fmt.Errorf("failed to validate prestate: %w", err)
            // → 게임 참여 불가!
        }
    }

    // 모두 통과하면 nil 반환
    return nil
    // → 게임 참여 가능!
}
```

**호출 위치**: Scheduler가 GamePlayer 생성 후 자동으로 호출

### Step 4: ProgressGame() - 게임 진행

**파일**: `op-challenger/game/fault/player.go:178-207`

```go
func (g *GamePlayer) ProgressGame(ctx context.Context) gameTypes.GameStatus {
    // 게임이 이미 끝났는지 확인
    if g.status != gameTypes.GameStatusInProgress {
        g.logger.Trace("Skipping completed game")
        return g.status
    }

    // 노드 동기화 상태 확인
    if err := g.syncValidator.ValidateNodeSynced(ctx, g.gameL1Head); errors.Is(err, types.ErrNotInSync) {
        g.logger.Warn("Local node not sufficiently up to date", "err", err)
        return g.status
    }

    // Line 191-194: 🔥 실제 게임 액션 실행!
    g.logger.Trace("Checking if actions are required")
    if err := g.act(ctx); err != nil {
        g.logger.Error("Error when acting on game", "err", err)
    }
    // g.act = agent.Act
    // → 게임 상태 분석
    // → 필요한 claim 제출
    // → TraceProvider.Get() 호출로 중간 블록들 검증!

    // 게임 상태 업데이트
    status, err := g.loader.GetStatus(ctx)
    if err != nil {
        g.logger.Error("Unable to retrieve game status", "err", err)
        return gameTypes.GameStatusInProgress
    }
    g.status = status

    return status
}
```

### Step 5: agent.Act() - 실제 게임 로직

**파일**: `op-challenger/game/fault/agent.go:79-112`

```go
func (a *Agent) Act(ctx context.Context) error {
    // Line 80-82: 게임 resolve 가능한지 먼저 시도
    if a.tryResolve(ctx) {
        return nil
    }

    // Line 89-94: L2 block number challenge 확인
    if challenged, err := a.loader.IsL2BlockNumberChallenged(ctx, rpcblock.Latest); ... {
        a.log.Debug("Skipping game with already challenged L2 block number")
        return nil
    }

    // Line 96-99: 🔥 Contract에서 게임 상태 가져오기
    game, err := a.newGameFromContracts(ctx)
    // → 모든 claims 로드
    // → 현재 게임 tree 구성

    // Line 101-104: 🔥 다음 액션 계산
    actions, err := a.solver.CalculateNextActions(ctx, game)
    // → GameSolver가 분석
    // → TraceProvider.Get() 호출로 각 claim 검증
    // → Block 150, 175, 200 등을 L2 RPC로 확인!
    // → 필요한 attack/defend 결정

    // Line 106-111: 🔥 모든 액션 병렬 실행
    var wg sync.WaitGroup
    wg.Add(len(actions))
    for _, action := range actions {
        go a.performAction(ctx, &wg, action)
        // → Move 제출 (attack/defend)
        // → Step 제출 (trace 증명)
    }
    wg.Wait()

    return nil
}
```

### Step 6: solver.CalculateNextActions() - 액션 계산

**파일**: `op-challenger/game/fault/solver/game_solver.go:92-127`

```go
func (s *GameSolver) CalculateNextActions(ctx context.Context, game types.Game) ([]types.Action, error) {
    // Root claim에 동의하는지 확인
    agreeWithRootClaim, err := s.AgreeWithRootClaim(ctx, game)
    // → s.trace.Get(ctx, RootPosition) 호출
    // → 🔥 여기서 L2 RPC.OutputAtBlock(200) 호출!
    // → rootClaim과 비교

    // 모든 claims에 대해 반복
    for _, claim := range game.Claims() {
        // 각 claim마다:
        // 1. TraceProvider.Get(position) 호출
        //    → L2 RPC로 해당 블록의 실제 값 조회
        //    → 예: Block 150, 175, 200...
        //
        // 2. Proposer의 claim과 비교
        //    → 일치: agree, 액션 불필요
        //    → 불일치: disagree, attack/defend 필요
        //
        // 3. 필요한 액션 리스트에 추가
        actions = append(actions, Action{
            Type: ActionTypeMove,
            IsAttack: true,
            ParentClaim: claim,
            Value: honestValue,
        })
    }

    return actions, nil
}
```

### 전체 시간순 플로우 (Validator 이후)

```
════════════════════════════════════════════════════════════════
Phase 1: Validator 검증 (게임 참여 전)
════════════════════════════════════════════════════════════════

T=0: Scheduler가 새 게임 발견
     └─ "Found game: 0xGame123..."

T=1: playerCreator() 호출
     ├─ Contract 준비
     ├─ Validators 생성
     └─ NewGamePlayer() 호출

T=2: NewGamePlayer() 실행
     ├─ TraceAccessor 생성
     ├─ Agent 생성
     └─ GamePlayer 객체 반환 (validators 포함)

T=3: ValidatePrestate() 호출
     ├─ Validator 1 실행: VM prestate 체크
     │  └─ ✅ PASS
     ├─ Validator 2 실행: Block 100 체크
     │  └─ ✅ PASS (Warm) or ❌ FAIL (Cold)
     └─ 결과:
        ├─ 모두 PASS → Phase 2로
        └─ 하나라도 FAIL → 게임 스킵

════════════════════════════════════════════════════════════════
Phase 2: 게임 참여 시작 (Validator 통과 후)
════════════════════════════════════════════════════════════════

T=4: ProgressGame() 호출 (주기적)
     └─ agent.Act() 실행

T=5: agent.Act() 실행
     ├─ newGameFromContracts(): Contract에서 게임 상태 로드
     │  └─ 모든 claims 가져오기
     │
     ├─ solver.CalculateNextActions(): 액션 계산
     │  └─ 🔥 여기서 TraceProvider.Get() 호출!
     │
     │  For each claim:
     │    1. TraceProvider.Get(position) 호출
     │       → OutputAtBlock(150) ← L2 RPC!
     │       → OutputAtBlock(175) ← L2 RPC!
     │       → OutputAtBlock(200) ← L2 RPC!
     │
     │    2. Proposer claim vs Honest value 비교
     │       → 일치: Skip
     │       → 불일치: Attack/Defend action 생성
     │
     └─ 필요한 actions 리스트 반환

T=6: performAction() - 액션 실행
     └─ 각 action을 병렬로 실행
        ├─ ActionTypeMove: move() 트랜잭션 제출
        ├─ ActionTypeStep: step() 트랜잭션 제출
        └─ ActionTypeChallengeL2BlockNumber: challengeRootL2Block() 제출

T=7~N: ProgressGame() 계속 호출 (주기적)
       └─ 게임이 resolve될 때까지 반복
```

### 핵심 코드 위치 정리

| 단계 | 파일 | 함수 | Line | 역할 |
|-----|------|------|------|------|
| **1. 등록** | register_task.go | Register() | 277-352 | playerCreator 등록 |
| **2. 생성** | register_task.go | playerCreator | 292-341 | Validators & GamePlayer 생성 |
| **3. 검증** | player.go | ValidatePrestate() | 165-171 | 🔥 Validators 실행 |
| **4. 진행** | player.go | ProgressGame() | 178-207 | 게임 진행 시작 |
| **5. 액션** | agent.go | Act() | 79-112 | 실제 게임 로직 |
| **6. 계산** | game_solver.go | CalculateNextActions() | 92-127 | 🔥 TraceProvider.Get() 호출 |
| **7. 실행** | agent.go | performAction() | 115-149 | Claim 제출 |

### 중요한 연결 고리

```go
// NewGamePlayer에서:
agent := NewAgent(m, systemClock, l1Clock, loader, gameDepth, maxClockDuration,
                 accessor,   // ← TraceProvider 포함!
                 responder,  // ← Claim 제출기
                 logger, selective, claimants)

return &GamePlayer{
    act: agent.Act,  // ← 이 함수가 실제 게임 로직!
    prestateValidators: validators,  // ← Validators 저장
}

// ProgressGame에서:
g.act(ctx)  // → agent.Act() 호출
            // → solver.CalculateNextActions() 호출
            // → TraceProvider.Get() 호출
            // → 🔥 모든 중간 블록 검증!
```

### 2. Contract에서 값 조회

#### GetAbsolutePrestateHash()
- FaultDisputeGame 컨트랙트의 `absolutePrestate()` 함수 호출
- 게임 생성 시 설정된 VM의 절대 prestate 해시 반환

#### GetStartingRootHash()
- FaultDisputeGame 컨트랙트의 `startingRootHash()` 함수 호출
- `startingOutputRoot.root` 값 반환
- 이 값은 게임 초기화 시 `AnchorStateRegistry.getAnchorRoot()`에서 가져온 값

### 3. Provider에서 값 계산

#### vmPrestateProvider (absolutePrestate)
- MultiPrestateProvider를 통해 prestate 파일 다운로드
- 파일에서 실제 prestate 해시 계산
- 파일서버에서 `{hash}.json.gz` 형태로 다운로드

#### prestateProvider (starting state root)

**파일**: `op-challenger/game/fault/register_task.go:312-324, 98-99`

**동작 원리**:

```go
// Line 312: Contract에서 게임의 블록 범위 가져오기
prestateBlock, poststateBlock, err := contract.GetGameRange(ctx)
// prestateBlock = game.startingOutputRoot.l2SequenceNumber
// 예: Game이 Block 100을 starting으로 사용하면 prestateBlock = 100

// Line 324: prestateBlock을 사용해서 PrestateProvider 생성
prestateProvider, err := e.getTopPrestateProvider(ctx, prestateBlock)

// Line 98-99: getTopPrestateProvider 구현
getTopPrestateProvider: func(ctx context.Context, prestateBlock uint64) (faultTypes.PrestateProvider, error) {
    return outputs.NewPrestateProvider(rollupClient, prestateBlock), nil
},
```

**핵심 기능**: L2 RPC를 통한 **과거 블록 조회**

**파일**: `op-challenger/game/fault/trace/outputs/prestate.go:14-34`

```go
type OutputPrestateProvider struct {
    prestateBlock uint64          // Contract에서 가져온 블록 번호
    rollupClient  OutputRollupClient  // L2 RPC 클라이언트
}

func (o *OutputPrestateProvider) AbsolutePreStateCommitment(ctx context.Context) (hash common.Hash, err error) {
    return o.outputAtBlock(ctx, o.prestateBlock)
}

func (o *OutputPrestateProvider) outputAtBlock(ctx context.Context, block uint64) (common.Hash, error) {
    // 🔥 핵심: L2 RPC에 과거 블록 요청!
    output, err := o.rollupClient.OutputAtBlock(ctx, block)
    // RPC 호출: "Block 100의 output root를 주세요" (현재가 Block 500이더라도)
    if err != nil {
        return common.Hash{}, fmt.Errorf("failed to fetch output at block %v: %w", block, err)
    }
    return common.Hash(output.OutputRoot), nil
}
```

**중요한 특징**:

1. **Contract에서 블록 번호 결정**:
   - `prestateBlock`은 Contract의 `startingOutputRoot.l2SequenceNumber`에서 가져옴
   - 각 게임은 자신의 starting block 번호를 가지고 있음

2. **L2 RPC의 과거 블록 조회 능력**:
   - L2 current block = 500이어도
   - `OutputAtBlock(100)` 호출 가능
   - Archive node가 모든 과거 블록 데이터 저장
   - 블록체인의 불변성 덕분에 가능

3. **각 게임마다 독립적 검증**:
   ```
   Game 2: prestateBlock = 100 → L2 RPC.OutputAtBlock(100) 요청
   Game 3: prestateBlock = 100 → L2 RPC.OutputAtBlock(100) 요청
   Game 5: prestateBlock = 200 → L2 RPC.OutputAtBlock(200) 요청
   ```

4. **시간 독립성**:
   - 게임 생성 시점과 검증 시점이 달라도 문제없음
   - L2가 Block 1000에 있어도 Block 100 데이터 조회 가능
   - 과거 데이터는 불변이므로 언제 조회해도 같은 결과

**검증 과정 예시**:

```
Game 3 검증 (생성 시점: L2 Block 300, 검증 시점: L2 Block 800)

1. Contract 값 조회:
   prestateBlock = 100
   contractHash = game.startingOutputRoot.root

2. Provider 값 계산:
   rollupClient.OutputAtBlock(100)  // ← Block 800에서 Block 100 데이터 요청!
   → L2 RPC: "Block 100? Archive에서 찾아드릴게요"
   → providerHash = 0xabc123...

3. 비교:
   contractHash vs providerHash
   → Cold Starting: 0xdead... != 0xabc123... ❌
   → Warm: 0xabc123... == 0xabc123... ✅
```

### 4. 검증 과정

**파일**: `op-challenger/game/fault/validator.go:36-50`

```go
func (v *PrestateValidator) Validate(ctx context.Context) error {
    // Contract에서 값 가져오기
    contractHash, err := v.contractGetter(ctx)

    // Provider에서 값 계산하기
    providerHash, err := v.prestateProvider.AbsolutePreStateCommitment(ctx)

    // 두 값 비교
    if contractHash != providerHash {
        return fmt.Errorf("%s absolute prestate does not match: Provider: %s | Contract: %s",
            v.name, calculatedProviderHash, contractHash)
    }
}
```

## Validator 1: VM Prestate 검증 상세 플로우

```
┌─────────────────────────────────────────────────────────────┐
│ Validator 1: absolutePrestate 검증                           │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ Step 1: Contract에서 값 가져오기                              │
│ contract.GetAbsolutePrestateHash()                          │
│ → FaultDisputeGame.absolutePrestate()                       │
│ → contractHash = 0x03a1a135...                              │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ Step 2: 파일서버에서 prestate 파일 찾기                       │
│ vmPrestateProvider.AbsolutePreStateCommitment()             │
│                                                              │
│ 2-1. 로컬 캐시 확인                                          │
│      ~/datadir/0x03a1a135...{.bin.gz|.json.gz|.json}       │
│      └─ 있으면 → 사용 ✅                                     │
│      └─ 없으면 → 2-2로                                       │
│                                                              │
│ 2-2. 파일서버에서 다운로드                                    │
│      GET http://fileserver/0x03a1a135....bin.gz            │
│      └─ 성공 → 저장 후 사용 ✅                               │
│      └─ 실패 → .json.gz 시도                                 │
│                                                              │
│ 2-3. 파일에서 해시 계산                                       │
│      providerHash = 0x03a1a135...                           │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ Step 3: 해시 비교                                            │
│ contractHash == providerHash?                               │
│                                                              │
│ YES: 0x03a1... == 0x03a1... → ✅ PASS                       │
│ NO:  0x03a1... != 0xffff... → ❌ FAIL                       │
└─────────────────────────────────────────────────────────────┘
```

## Validator 2: Starting State Root 검증 상세 플로우

```
┌─────────────────────────────────────────────────────────────┐
│ Validator 2: startingOutputRoot 검증                         │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ Step 1: Contract에서 게임 정보 가져오기                       │
│ contract.GetGameRange()                                     │
│ → prestateBlock = game.startingOutputRoot.l2SequenceNumber  │
│ → 예: prestateBlock = 100                                   │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ Step 2: Contract에서 starting root hash 가져오기             │
│ contract.GetStartingRootHash()                              │
│ → FaultDisputeGame.startingOutputRoot.root                  │
│ → AnchorStateRegistry.getAnchorRoot()에서 온 값             │
│                                                              │
│ Cold Starting: contractHash = 0xdead... ❌                  │
│ Warm 상태:     contractHash = 0xabc123... ✅                │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ Step 3: PrestateProvider 생성                                │
│ getTopPrestateProvider(prestateBlock)                       │
│ → outputs.NewPrestateProvider(rollupClient, 100)           │
│ → prestateBlock = 100 저장                                  │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ Step 4: L2 RPC에 과거 블록 요청                              │
│ prestateProvider.AbsolutePreStateCommitment()               │
│ → outputAtBlock(prestateBlock=100)                          │
│ → rollupClient.OutputAtBlock(ctx, 100)                      │
│                                                              │
│ 🔥 핵심: 과거 블록 조회!                                     │
│ - 현재 L2 = Block 500                                       │
│ - 요청: Block 100의 output root                             │
│ - L2 Archive Node가 과거 데이터 반환                         │
│ - providerHash = 0xabc123...                                │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ Step 5: 해시 비교                                            │
│ contractHash == providerHash?                               │
│                                                              │
│ Cold Starting:                                               │
│   0xdead... != 0xabc123... → ❌ FAIL                        │
│   Error: "output root absolute prestate does not match"     │
│                                                              │
│ Warm 상태:                                                   │
│   0xabc123... == 0xabc123... → ✅ PASS                      │
│   Validation 성공!                                           │
└─────────────────────────────────────────────────────────────┘
```

## 전체 통합 플로우 (시간순)

```
════════════════════════════════════════════════════════════════
Phase 1: 게임 생성 (L1 Blockchain)
════════════════════════════════════════════════════════════════

T=0: Proposer가 DisputeGameFactory.create() 호출
     ├─ Game Type: 0 (CANNON)
     ├─ Root Claim: 0xdef456... (Block 200 제안)
     └─ Extra Data: 0x00...C8 (Block 200 in hex)
                ↓
     FaultDisputeGame.initialize() 실행
     ├─ getAnchorRoot() 호출
     │  └─ anchorGame == address(0)?
     │      ├─ Yes → startingAnchorRoot (0xdead...) 반환
     │      └─ No  → anchorGame.rootClaim() 반환
     ├─ startingOutputRoot 설정
     │  ├─ l2SequenceNumber = 100
     │  └─ root = 0xdead... (Cold) or 0xabc123... (Warm)
     └─ Game 생성 완료!

════════════════════════════════════════════════════════════════
Phase 2: Challenger 발견 및 검증 준비
════════════════════════════════════════════════════════════════

T=5분: Challenger가 새 게임 감지
       └─ "Found new game: 0xGame123..."
                ↓
       GamePlayer 생성 시작
       ├─ contract.GetAbsolutePrestateHash()
       │  → requiredPrestatehash = 0x03a1a135...
       ├─ contract.GetGameRange()
       │  → prestateBlock = 100
       │  → poststateBlock = 200
       └─ contract.GetStartingRootHash()
          → startingRootHash = 0xdead... (Cold) or 0xabc123... (Warm)

════════════════════════════════════════════════════════════════
Phase 3: Validator 1 검증 (VM Prestate)
════════════════════════════════════════════════════════════════

       Validator 1 실행
       ├─ Contract: 0x03a1a135...
       ├─ File Server: GET /0x03a1a135....bin.gz
       │  └─ Download & calculate hash
       │  └─ Provider: 0x03a1a135...
       └─ 비교: 0x03a1a135... == 0x03a1a135...
          └─ ✅ PASS (보통 성공)

════════════════════════════════════════════════════════════════
Phase 4: Validator 2 검증 (Starting Output Root)
════════════════════════════════════════════════════════════════

       Validator 2 실행
       ├─ Contract: startingRootHash
       │  └─ Cold: 0xdead...
       │  └─ Warm: 0xabc123...
       │
       ├─ L2 RPC: OutputAtBlock(100)
       │  └─ RPC Call: optimism_outputAtBlock("0x64")
       │  └─ 현재 L2 Block = 500
       │  └─ Archive Node: "Block 100 찾았습니다"
       │  └─ Provider: 0xabc123...
       │
       └─ 비교:
          ├─ Cold: 0xdead... != 0xabc123... → ❌ FAIL
          └─ Warm: 0xabc123... == 0xabc123... → ✅ PASS

════════════════════════════════════════════════════════════════
Phase 5: 검증 결과 처리
════════════════════════════════════════════════════════════════

       검증 결과
       ├─ 두 Validator 모두 PASS?
       │  ├─ YES → ✅ Challenger 게임 참여
       │  │  └─ GamePlayer 생성
       │  │  └─ Claims 모니터링 시작
       │  │  └─ 필요시 counter claim 제출
       │  │
       │  └─ NO → ❌ 게임 스킵
       │     └─ ERROR 로그 출력
       │     └─ "Failed to validate prestate"
       │     └─ 다른 게임 계속 모니터링
```

## 각 단계별 코드 참조

### Phase 1: 게임 생성

```solidity
// packages/contracts-bedrock/src/dispute/FaultDisputeGame.sol:317-324
function _initialize(address _rat) internal virtual {
    // Line 318: 현재 anchor root 가져오기 (snapshot!)
    (Hash root, uint256 rootBlockNumber) = ANCHOR_STATE_REGISTRY.getAnchorRoot();

    // Line 324: 게임에 고정 저장 (이후 절대 변경 안 됨)
    startingOutputRoot = Proposal({
        l2SequenceNumber: rootBlockNumber,  // 100
        root: root                          // 0xdead... or 0xabc123...
    });
}
```

### Phase 2: 검증 준비

```go
// op-challenger/game/fault/register_task.go:292-340
func (e *RegisterTask) Register(...) error {
    playerCreator := func(game types.GameMetadata, dir string) (scheduler.GamePlayer, error) {
        // Line 293-296: Contract 생성
        contract, err := contracts.NewFaultDisputeGameContract(ctx, m, game.Proxy, caller)

        // Line 297-300: absolutePrestate 해시 가져오기
        requiredPrestatehash, err := contract.GetAbsolutePrestateHash(ctx)

        // Line 302-305: VM prestate provider 생성
        vmPrestateProvider, err := e.getBottomPrestateProvider(ctx, requiredPrestatehash)

        // Line 312-315: 게임 범위 가져오기
        prestateBlock, poststateBlock, err := contract.GetGameRange(ctx)

        // Line 324-327: Output prestate provider 생성
        prestateProvider, err := e.getTopPrestateProvider(ctx, prestateBlock)

        // Line 336-339: Validator 생성
        var validators []Validator
        if !e.skipPrestateValidation {
            validators = append(validators,
                NewPrestateValidator(e.gameType.String(),
                                   contract.GetAbsolutePrestateHash,
                                   vmPrestateProvider))
            validators = append(validators,
                NewPrestateValidator("output root",
                                   contract.GetStartingRootHash,
                                   prestateProvider))
        }

        // Line 340: GamePlayer 생성 (validators 포함)
        return NewGamePlayer(ctx, ..., validators, ...)
    }
}
```

### Phase 3: Validator 1 실행

```go
// op-challenger/game/fault/validator.go:36-49
func (v *PrestateValidator) Validate(ctx context.Context) error {
    // Step 1: Contract 값
    prestateHash, err := v.load(ctx)  // GetAbsolutePrestateHash()

    // Step 2: Provider 값
    prestateCommitment, err := v.provider.AbsolutePreStateCommitment(ctx)
    // → vm.PrestateProvider
    // → 파일에서 해시 계산

    // Step 3: 비교
    if !bytes.Equal(prestateCommitment[:], prestateHash[:]) {
        return fmt.Errorf("mismatch")
    }
}
```

### Phase 4: Validator 2 실행

```go
// op-challenger/game/fault/validator.go:36-49
func (v *PrestateValidator) Validate(ctx context.Context) error {
    // Step 1: Contract 값
    prestateHash, err := v.load(ctx)  // GetStartingRootHash()
    // → game.startingOutputRoot.root

    // Step 2: Provider 값 (과거 블록 조회!)
    prestateCommitment, err := v.provider.AbsolutePreStateCommitment(ctx)
    // → outputs.OutputPrestateProvider
    // → outputAtBlock(prestateBlock=100)
    // → rollupClient.OutputAtBlock(ctx, 100)  // ← L2 RPC 호출!

    // Step 3: 비교
    if !bytes.Equal(prestateCommitment[:], prestateHash[:]) {
        // Cold: 0xdead... != 0xabc123...
        return fmt.Errorf("output root absolute prestate does not match")
    }
}
```

### Phase 5: 검증 결과

```go
// op-challenger/game/fault/player.go
func NewGamePlayer(..., validators []Validator, ...) (*GamePlayer, error) {
    // 모든 validator 실행
    for _, validator := range validators {
        if err := validator.Validate(ctx); err != nil {
            // 하나라도 실패하면 에러 반환
            return nil, fmt.Errorf("failed to validate: %w", err)
        }
    }

    // 모두 통과하면 GamePlayer 생성
    return &GamePlayer{...}, nil
}
```

## 시간순 상세 플로우 (실제 시나리오)

```
T=0 (L2 Block 300):
┌────────────────────────────────────────────────────────┐
│ 1. Proposer: 새 게임 생성 (L2 Block 400 제안)           │
│    DisputeGameFactory.create(                          │
│      gameType: 0,                                      │
│      rootClaim: 0xdef456...,  // Block 400 주장        │
│      extraData: 0x190        // Block 400 in hex       │
│    )                                                   │
└────────────────────────────────────────────────────────┘
                        ↓
┌────────────────────────────────────────────────────────┐
│ 2. FaultDisputeGame.initialize() 실행 (L1 Block N)     │
│    getAnchorRoot() 호출                                │
│    └─ anchorGame 확인                                  │
│       ├─ address(0) → 0xdead... 반환 (Cold)           │
│       └─ Game 1 → Block 100 root 반환 (Warm)          │
│    startingOutputRoot 설정:                            │
│    ├─ l2SequenceNumber: 100                           │
│    └─ root: 0xdead... (Cold) or 0xabc123... (Warm)   │
└────────────────────────────────────────────────────────┘
                        ↓
T=5분 (L2 Block 350):
┌────────────────────────────────────────────────────────┐
│ 3. Challenger: 게임 발견 및 검증 시작                   │
│    "Found dispute game: 0xGame123..."                  │
└────────────────────────────────────────────────────────┘
                        ↓
┌────────────────────────────────────────────────────────┐
│ 4. Contract 정보 조회 (L1 최신 상태)                    │
│    - absolutePrestate: 0x03a1a135...                   │
│    - prestateBlock: 100                                │
│    - startingRootHash: 0xdead... or 0xabc123...       │
└────────────────────────────────────────────────────────┘
                        ↓
┌────────────────────────────────────────────────────────┐
│ 5. Validator 1 검증 (VM Prestate)                      │
│    파일서버 → 0x03a1a135....bin.gz 다운로드            │
│    Contract: 0x03a1a135...                            │
│    Provider: 0x03a1a135...                            │
│    → ✅ PASS                                           │
└────────────────────────────────────────────────────────┘
                        ↓
T=5분 10초 (L2 Block 360):
┌────────────────────────────────────────────────────────┐
│ 6. Validator 2 검증 (Starting Output Root)             │
│    L2 RPC 호출: OutputAtBlock(100)                     │
│    └─ "Block 100? 260 블록 전이네..."                  │
│    └─ Archive 검색 → Block 100 데이터 반환             │
│    └─ providerHash = 0xabc123...                       │
│                                                        │
│    비교:                                                │
│    Contract: 0xdead... (Cold)                         │
│    Provider: 0xabc123...                              │
│    → ❌ FAIL (Cold Starting)                           │
│                                                        │
│    OR                                                  │
│                                                        │
│    Contract: 0xabc123... (Warm)                       │
│    Provider: 0xabc123...                              │
│    → ✅ PASS                                           │
└────────────────────────────────────────────────────────┘
                        ↓
┌────────────────────────────────────────────────────────┐
│ 7. 검증 결과 처리                                       │
│    ├─ 두 검증 모두 PASS → Challenger 참여             │
│    └─ 하나라도 FAIL → 게임 스킵, 에러 로그            │
└────────────────────────────────────────────────────────┘
```

## MultiPrestateProvider 동작 과정

**파일**: `/Users/zena/tokamak-projects/optimism/op-challenger/game/fault/trace/prestates/multi.go`

### 1. 파일 다운로드 시도

```go
// PrestatePath 함수 (라인 40-65)
func (m *MultiPrestateProvider) PrestatePath(ctx context.Context, hash common.Hash) (string, error) {
    // 1. 로컬 캐시에서 찾기 (라인 42-50)
    for _, fileType := range supportedFileTypes {
        path := filepath.Join(m.dataDir, hash.Hex()+fileType)
        if _, err := os.Stat(path); errors.Is(err, os.ErrNotExist) {
            continue // File doesn't exist, try the next file type
        } else if err != nil {
            return "", fmt.Errorf("error checking for existing prestate %v in file %v: %w", hash, path, err)
        }
        return path, nil // Found an existing file so use it
    }

    // 2. 파일서버에서 다운로드 (라인 52-65)
    for _, fileType := range supportedFileTypes {
        path := filepath.Join(m.dataDir, hash.Hex()+fileType)
        if err := m.fetchPrestate(ctx, hash, fileType, path); errors.Is(err, ErrPrestateUnavailable) {
            combinedErr = errors.Join(combinedErr, err)
            continue // Didn't find prestate in this format, try the next
        } else if err != nil {
            return "", fmt.Errorf("error downloading prestate %v to file %v: %w", hash, path, err)
        }
        return path, nil // Successfully downloaded a prestate so use it
    }
    return "", errors.Join(ErrPrestateUnavailable, combinedErr)
}
```

### 2. 지원되는 파일 형식

**파일**: `/Users/zena/tokamak-projects/optimism/op-challenger/game/fault/trace/prestates/multi.go:23`

```go
// supportedFileTypes lists, in preferred order, the prestate file types to attempt to download
supportedFileTypes = []string{".bin.gz", ".json.gz", ".json"}
```

- `.bin.gz` (바이너리 압축) - 우선순위 1
- `.json.gz` (JSON 압축) - 우선순위 2
- `.json` (일반 JSON) - 우선순위 3

### 3. 파일서버 구조
```
http://fileserver/
├── 0x03a1a13511403f206bb2414e3bf974f8b4608ad8f7b37ee6642f6598dbe06195.json.gz
├── 0x0383d8cf3feb2989ac49ba58e92c69cbf26dd82ea6b650d09efbda7b9a1b29c7.json.gz
└── ...
```

## Cold Starting vs Warm Game 검증

### Cold Starting (AnchorStateRegistry 초기 상태)

**Cold Starting이란?**
- **Initial State**: AnchorStateRegistry가 처음 배포된 상태를 의미합니다
- **Empty State**: 아직 유효한 anchor state가 설정되지 않은 상태
- **0xdead Value**: `0xdeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddead` 같은 하드코딩된 임시값으로 초기화

**문제가 발생하는 핵심 이유:**
레지스트리가 초기에 유효하지 않거나 placeholder 값인 anchor state를 가지고 있기 때문입니다. challenger가 dispute game의 prestate를 검증하려고 할 때, 이 유효하지 않은 또는 0xdead 값을 마주치게 됩니다. challenger는 정당한 L2 state root를 예상하지만 대신 placeholder를 발견하여 prestate 검증 실패가 발생합니다.

**Cold Starting이라고 불리는 이유:**
- **Newly Deployed State**: 레지스트리가 새로 배포된 "cold" 상태로, 아직 실제 L2 상태에 연결되거나 반영하지 않음
- **First Game Required**: 유효한 dispute game이 시작되고 성공적으로 완료되어야 anchor state가 초기 placeholder에서 실제 L2 상태로 업데이트됨
- **Manual Intervention Needed**: 이것은 자동으로 해결되지 않으며, 종종 첫 번째 유효한 anchor state를 설정하기 위해 특정한 액션("warm-up" 게임이나 수동 개입)이 필요함

**결론적으로**, "Cold Starting"은 AnchorStateRegistry가 새로 배포되어 유효한 anchor state가 부족한 상태를 설명하며, 이것이 challenger의 prestate 검증 실패의 근본 원인입니다.

### 게임별 검증 결과

**Cold Starting 상태에서 생성된 모든 게임들:**
- AnchorStateRegistry가 0xdead... 값을 가지고 있음
- **동시에 여러 개의 게임이 생성될 수 있음** (실제로 2개 게임이 동시 생성된 경우 확인됨)
- 생성된 모든 dispute game들이 동일한 잘못된 값(0xdead...)을 startingRootHash로 사용
- **모든 게임에서 prestate validation 실패**
- 게임 1개든 2개든 n개든 상관없이 모든 게임이 같은 문제를 겪음
- 각 게임은 독립적이지만 모두 동일한 AnchorStateRegistry를 참조하므로 같은 결과

**Warm 상태 (첫 번째 유효한 게임 완료 후):**
- AnchorStateRegistry에 유효한 anchor game이 설정됨
- 그 이후 새로 생성되는 모든 게임들이 올바른 L2 state root를 startingRootHash로 사용
- **이후 생성되는 모든 게임에서 prestate validation 성공**

## AnchorStateRegistry와의 관계

### startingAnchorRoot 체크 로직 위치

**1. AnchorStateRegistry Contract 정의**
- **파일**: `/Users/zena/tokamak-projects/optimism/packages/contracts-bedrock/src/dispute/AnchorStateRegistry.sol:44`
- **정의**: `Proposal internal startingAnchorRoot;`
- **초기화**: `initialize()` 함수에서 설정 (라인 104)

**2. Challenger Validation 설정**
- **파일**: `/Users/zena/tokamak-projects/optimism/op-challenger/game/fault/register_task.go:336-338`
- **로직**: `skipPrestateValidation` 플래그에 따라 validator 생성
```go
if !e.skipPrestateValidation {
    validators = append(validators, NewPrestateValidator(e.gameType.String(), contract.GetAbsolutePrestateHash, vmPrestateProvider))
    validators = append(validators, NewPrestateValidator("output root", contract.GetStartingRootHash, prestateProvider))
}
```

**3. Contract 값 조회 구현**
- **파일**: `/Users/zena/tokamak-projects/optimism/op-challenger/game/fault/contracts/faultdisputegame.go:259-265`
- **함수**: `GetStartingRootHash()`
```go
func (f *FaultDisputeGameContract) GetStartingRootHash(ctx context.Context) (common.Hash, error) {
    defer f.metrics.StartContractRequest("GetStartingRootHash")()
    return f.multiCaller.SingleCall(ctx, rpcblock.Latest, f.contract.Call(methodStartingRootHash))
}
```

**4. AnchorStateRegistry getAnchorRoot() 동작**
- **파일**: `/Users/zena/tokamak-projects/optimism/packages/contracts-bedrock/src/dispute/AnchorStateRegistry.sol:168-176`
```solidity
function getAnchorRoot() public view returns (Hash, uint256) {
    // Return the starting anchor root if there is no anchor game.
    if (address(anchorGame) == address(0)) {
        return (startingAnchorRoot.root, startingAnchorRoot.l2SequenceNumber);
    }
    // Otherwise, return the anchor root.
    return (Hash.wrap(anchorGame.rootClaim().raw()), anchorGame.l2SequenceNumber());
}
```

### startingAnchorRoot 설정 과정

1. **게임 생성 시**: `FaultDisputeGame.initialize()`
2. **AnchorStateRegistry 조회**: `getAnchorRoot()` 호출
3. **fallback 값 사용**: anchorGame이 없으면 `startingAnchorRoot` 사용
4. **게임에 설정**: `startingOutputRoot = Proposal({...})`

### 현재 문제 상황

```solidity
// AnchorStateRegistry.getAnchorRoot()
if (address(anchorGame) == address(0)) {
    return (startingAnchorRoot.root, startingAnchorRoot.l2SequenceNumber);
    // ❌ startingAnchorRoot.root = 0xdead... (잘못된 값)
}
```

## 검증 실패 시나리오

### 1. absolutePrestate 검증
- **Contract**: `0x03a1a13511403f206bb2414e3bf974f8b4608ad8f7b37ee6642f6598dbe06195` ✅
- **Provider**: `0x03a1a13511403f206bb2414e3bf974f8b4608ad8f7b37ee6642f6598dbe06195` ✅
- **결과**: **성공**

### 2. starting state root 검증 (Cold Starting 상태)
- **Contract** (AnchorStateRegistry에서 가져온 값): `0xdead0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000` ❌
- **Provider** (실제 L2 genesis root): `0x03a1a13511403f206bb2414e3bf974f8b4608ad8f7b37ee6642f6598dbe06195` ✅
- **결과**: **실패** - "output root absolute prestate does not match"

## 해결 방안

### 1. skipPrestateValidation 플래그 (현재 구현)

**파일**: `/Users/zena/tokamak-projects/optimism/op-challenger/game/fault/register_task.go`

```go
// NewCannonRegisterTask 함수 (라인 97)
skipPrestateValidation: gameType == faultTypes.PermissionedGameType,

// NewSuperCannonRegisterTask 함수 (라인 58)
skipPrestateValidation: gameType == faultTypes.SuperPermissionedGameType,

// NewSuperAsteriscKonaRegisterTask 함수 (라인 200)
skipPrestateValidation: gameType == faultTypes.SuperPermissionedGameType,

// validator 생성 시 체크 (라인 336-338)
if !e.skipPrestateValidation {
    validators = append(validators, NewPrestateValidator(e.gameType.String(), contract.GetAbsolutePrestateHash, vmPrestateProvider))
    validators = append(validators, NewPrestateValidator("output root", contract.GetStartingRootHash, prestateProvider))
}
```

**현재 동작**:
- **PermissionedGameType**, **SuperPermissionedGameType**: prestate validation 건너뜀
- **기타 게임 타입**: prestate validation 수행

### 1-1. Cold Starting 기반 예외 처리 (제안된 개선 방안)
```go
// AnchorStateRegistry 상태 기반 예외 처리 (아직 구현되지 않음)
if anchorStateRegistry.isColdStarting() {
    skipPrestateValidation = true
}

// 또는 게임 생성 시점 기반
if gameStatus == InProgress && isNewlyCreatedGame {
    skipPrestateValidation = true
}
```

**참고**: `claimCount == 1` 조건은 개별 게임의 상태를 확인하는 것이지만, 실제로는 Cold Starting 상태에서 생성된 모든 게임(1개든 2개든)이 같은 문제를 겪습니다.

### 2. AnchorStateRegistry 수정 (근본적 해결 - 권장)

Cold Starting 상태를 완전히 벗어나려면 올바른 anchorGame을 설정해야 합니다.

#### 완전한 해결 프로세스

```bash
# Step 1: 첫 번째 유효한 게임이 DEFENDER_WINS로 resolve
cast send $GAME_ADDRESS "resolve()" --rpc-url $L1_RPC --private-key $KEY

# Step 2: Finality delay 대기 (예: 7일 또는 devnet에서 30-60초)
DELAY=$(cast call $ANCHOR_STATE_REGISTRY \
  "disputeGameFinalityDelaySeconds()(uint256)" --rpc-url $L1_RPC)
echo "⏳ Waiting $DELAY seconds..."
sleep $DELAY

# Step 3: 🔥 closeGame() 호출 - 이게 핵심!
cast send $GAME_ADDRESS "closeGame()" --rpc-url $L1_RPC --private-key $KEY

# Step 4: anchorGame 업데이트 확인
ANCHOR_GAME=$(cast call $ANCHOR_STATE_REGISTRY \
  "anchorGame()(address)" --rpc-url $L1_RPC)
echo "✅ anchorGame updated to: $ANCHOR_GAME"

# Step 5: 이후 모든 새 게임이 유효한 starting root 사용
```

#### ⚠️ 중요: closeGame() 필수!

**흔한 실수**:
```bash
# ❌ WRONG: resolve()만 호출
cast send $GAME_ADDRESS "resolve()"
# → anchorGame이 업데이트되지 않음!
```

**올바른 방법**:
```bash
# ✅ CORRECT: resolve() + finality delay + closeGame()
cast send $GAME_ADDRESS "resolve()"
sleep $DELAY
cast send $GAME_ADDRESS "closeGame()"  # ← 이것이 anchorGame을 업데이트!
```

#### closeGame()을 호출하지 않으면?

- ❌ anchorGame = address(0) 유지
- ❌ getAnchorRoot() → 계속 0xdead... 반환
- ❌ 모든 새 게임이 잘못된 starting root 사용
- ❌ Challenger validation 계속 실패
- ❌ Cold Starting 상태 영구화!

자세한 절차는 [anchor-state-fix.md](./anchor-state-fix.md)와
[anchor-game-update-guide.md](./anchor-game-update-guide.md) 참조.

### 3. --allow-invalid-prestate 플래그
- Cold Starting 상태에서 prestate validation을 우회
- 개발/테스트 환경에서만 사용 권장
- 근본적인 해결책은 아니며 임시 회피책

## 결론

Challenger는 두 가지 핵심 값을 검증합니다:

1. **VM absolutePrestate 검증**:
   - 파일서버에서 다운로드한 prestate 해시와 컨트랙트 값 비교
   - VM 실행의 초기 상태 검증

2. **Starting state root 검증**:
   - L2 genesis output root와 게임의 starting root 비교
   - 게임이 올바른 L2 상태에서 시작하는지 검증

**Cold Starting 상태**에서는 AnchorStateRegistry의 startingAnchorRoot가 0xdead... 같은 placeholder 값으로 설정되어 있어 모든 새로운 게임의 state root validation이 실패합니다. 이를 해결하려면 AnchorStateRegistry를 올바른 L2 genesis root 값으로 초기화하거나 재설정해야 합니다.