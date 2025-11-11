# build-binaries-for-challenger.sh 상세 설명

## 📌 개요

`build-binaries-for-challenger.sh`는 Optimism Challenger가 동작하는데 필요한 모든 바이너리 파일들을 자동으로 빌드하는 스크립트입니다.

**위치**: `/optimism/op-challenger/scripts/build-binaries-for-challenger.sh`

---

## 🎯 스크립트의 역할

Challenger가 Fault Proof를 검증하려면 다음이 필요합니다:
- **Cannon VM**: MIPS 명령어를 실행하는 가상 머신
- **op-program**: L2 상태 전환을 증명하는 프로그램
- **Prestate Files**: VM 초기 상태 (absolute prestate)

이 스크립트는 이 3가지를 자동으로 빌드합니다.

---

## 💡 MIPS란? (배경 지식)

### MIPS (Microprocessor without Interlocked Pipeline Stages)

**MIPS는 RISC 아키텍처의 CPU 명령어 세트**입니다.

```
┌─────────────────────────────────────────┐
│ CPU 아키텍처 종류                       │
├─────────────────────────────────────────┤
│ CISC (복잡)                             │
│ └─ x86, x86_64 (Intel, AMD)            │
│    ├─ 명령어 수: 수백~수천 개           │
│    └─ 복잡한 명령어 (여러 작업 동시)   │
│                                         │
│ RISC (단순) ⭐                          │
│ └─ MIPS, ARM, RISC-V                   │
│    ├─ 명령어 수: ~100개                 │
│    └─ 단순한 명령어 (한 번에 하나)     │
└─────────────────────────────────────────┘
```

### 왜 Optimism은 MIPS를 선택했나?

Fault Proof에서는 **온체인에서 단일 명령어 실행을 증명**해야 합니다.

**1. 단순성** ✅
```
MIPS: add $t0, $t1, $t2      # 레지스터 두 개 더하기
x86:  add eax, [ebx+ecx*4+8] # 메모리 계산 + 더하기 + 복잡함
```
- MIPS는 명령어가 단순해서 증명하기 쉬움
- x86은 한 명령어가 여러 작업을 해서 증명 복잡

**2. 결정론적 (Deterministic)** ✅
```
같은 입력 → 항상 같은 출력
```
- MIPS: 명령어 실행 결과가 항상 예측 가능
- 부수 효과 (side effect) 최소화
- 온체인 검증에 필수!

**3. 명령어 수가 적음** ✅
```
MIPS:  ~100개 명령어
x86:   수천 개 명령어
```
- 적은 명령어 = 작은 VM 구현
- Cannon VM 코드가 간결함
- 감사 (audit) 및 검증 용이

**4. 고정 길이 명령어** ✅
```
MIPS: 모든 명령어가 32bit (4byte)
x86:  명령어 길이 가변 (1~15byte)
```
- 고정 길이 = 파싱 단순
- Program Counter 계산 쉬움
- 상태 추적 용이

**5. 작은 상태 (State)** ✅
```
MIPS VM 상태:
├─ 32개 레지스터 (각 32bit)
├─ Program Counter (32bit)
├─ 메모리 (필요한 만큼)
└─ 몇 가지 제어 레지스터
```
- 작은 상태 = 온체인 검증 가능
- Gas 비용 절감

### MIPS 명령어 예시

```assembly
# 1. 산술 연산
add  $t0, $t1, $t2    # $t0 = $t1 + $t2
sub  $t0, $t1, $t2    # $t0 = $t1 - $t2
mul  $t0, $t1, $t2    # $t0 = $t1 * $t2

# 2. 메모리 접근
lw   $t0, 0($sp)      # $t0 = Memory[$sp + 0]  (Load Word)
sw   $t0, 4($sp)      # Memory[$sp + 4] = $t0  (Store Word)

# 3. 분기/점프
beq  $t0, $t1, label  # if ($t0 == $t1) goto label
j    label            # goto label

# 4. 시스템 호출
syscall               # 시스템 콜 (I/O 등)
```

### Cannon VM이 하는 일

```
┌─────────────────────────────────────────┐
│ Cannon VM (MIPS 에뮬레이터)             │
├─────────────────────────────────────────┤
│ 1. MIPS 명령어를 하나씩 읽음            │
│ 2. 명령어를 해석 (decode)               │
│ 3. 레지스터/메모리 업데이트             │
│ 4. Program Counter 증가                 │
│ 5. 다음 명령어로 이동                   │
└─────────────────────────────────────────┘
```

**step() 호출 시**:
```go
// Cannon VM이 단일 MIPS 명령어 실행 증명

입력:
├─ Prestate (현재 VM 상태)
├─ 실행할 명령어 주소
└─ 메모리/레지스터 값

실행:
└─ 명령어 하나만 실행 (예: add $t0, $t1, $t2)

출력:
├─ Poststate (실행 후 VM 상태)
└─ 상태 해시 (Keccak256)

온체인 검증:
└─ "Prestate + 명령어 → Poststate" 맞는지 확인
```

---

### ⚠️ 중요: Prestate에는 트랜잭션 데이터가 없다!

**질문**: Prestate는 초기 상태인데, 새로운 L2 트랜잭션들은 어떻게 처리하나?

**답**: Prestate는 **op-program 바이너리만** 포함하고, **실제 데이터는 Preimage Oracle을 통해 실행 시 제공**됩니다!

```
┌─────────────────────────────────────────────────────┐
│ Prestate (초기 상태) - 고정됨                       │
├─────────────────────────────────────────────────────┤
│ ✅ op-program 바이너리 (MIPS 코드)                  │
│ ✅ 초기 메모리/레지스터 상태                        │
│ ✅ VM 설정                                          │
│                                                     │
│ ❌ L2 블록 데이터 (없음!)                           │
│ ❌ 트랜잭션 데이터 (없음!)                          │
│ ❌ State Root (없음!)                               │
└─────────────────────────────────────────────────────┘
         ↓
    실행 시 필요한 데이터는?
         ↓
┌─────────────────────────────────────────────────────┐
│ Preimage Oracle (실행 시 데이터 제공)               │
├─────────────────────────────────────────────────────┤
│ ✅ L1 블록 헤더                                     │
│ ✅ L2 블록 데이터                                   │
│ ✅ 트랜잭션 목록                                    │
│ ✅ State Trie 노드                                  │
│ ✅ Receipt 데이터                                   │
└─────────────────────────────────────────────────────┘
```

---

### 🔍 step() 실행의 실제 과정

#### 시나리오: 특정 L2 블록(#1000)의 Output Root 검증

**1. 게임 시작 (Bisection 단계)**:
```
Proposer: "블록 #1000의 Output Root는 0xABCD..."
Challenger: "틀렸다! 증명해봐!"

→ Bisection 진행 (MaxDepth까지)
→ 최종적으로 단일 MIPS 명령어까지 좁혀짐
```

**2. step() 호출 직전**:
```
게임 상태:
├─ 분쟁 지점: 명령어 #12,345,678
├─ 이 명령어는 블록 #1000의 트랜잭션 #5를 처리 중
└─ op-program이 실행 중인 상태
```

**3. 필요한 데이터 준비 (Preimage Upload)**:

Challenger는 step() 호출 전에 필요한 Preimage를 L1 Contract에 업로드합니다.

```go
// op-challenger/game/fault/responder/responder.go

func (r *FaultResponder) PerformAction(ctx context.Context, action types.Action) error {
    // step() 전에 OracleData가 있으면 업로드
    if action.OracleData != nil {
        var preimageExists bool
        var err error

        // Global preimage인지 확인
        if !action.OracleData.IsLocal {
            preimageExists, err = r.oracle.GlobalDataExists(ctx, action.OracleData)
            if err != nil {
                return fmt.Errorf("failed to check if preimage exists: %w", err)
            }
        }

        // Local preimage는 항상 업로드, Global은 없을 때만
        if !preimageExists {
            // Preimage 업로드!
            err := r.uploader.UploadPreimage(ctx,
                uint64(action.ParentClaim.ContractIndex),
                action.OracleData)
            if err != nil {
                return fmt.Errorf("failed to upload preimage: %w", err)
            }
        }
    }

    // 이후 실제 step() 호출
    switch action.Type {
    case types.ActionTypeStep:
        candidate, err = r.contract.StepTx(
            uint64(action.ParentClaim.ContractIndex),
            action.IsAttack,
            action.PreState,
            action.ProofData)
    }
    return r.sender.SendAndWaitSimple("perform action", candidate)
}
```

```go
// op-challenger/game/fault/contracts/faultdisputegame.go

// Preimage를 L1 Contract에 업로드하는 트랜잭션 생성
func (f *FaultDisputeGameContractLatest) UpdateOracleTx(
    ctx context.Context,
    claimIdx uint64,
    data *types.PreimageOracleData) (txmgr.TxCandidate, error) {

    // Local vs Global 구분
    if data.IsLocal {
        return f.addLocalDataTx(claimIdx, data)
    }
    return f.addGlobalDataTx(ctx, data)
}

// Local Preimage (게임별 데이터)
func (f *FaultDisputeGameContractLatest) addLocalDataTx(
    claimIdx uint64,
    data *types.PreimageOracleData) (txmgr.TxCandidate, error) {

    // FaultDisputeGame.addLocalData() 호출
    call := f.contract.Call(
        methodAddLocalData,           // "addLocalData"
        data.GetIdent(),               // Preimage Key
        new(big.Int).SetUint64(claimIdx), // Claim Index
        new(big.Int).SetUint64(uint64(data.OracleOffset)), // Offset
    )
    return call.ToTxCandidate()
}

// Global Preimage (공통 데이터 - L1 블록 등)
func (f *FaultDisputeGameContractLatest) addGlobalDataTx(
    ctx context.Context,
    data *types.PreimageOracleData) (txmgr.TxCandidate, error) {

    oracle, err := f.GetOracle(ctx)
    if err != nil {
        return txmgr.TxCandidate{}, err
    }
    // PreimageOracle.loadKeccak256PreimagePart() 등 호출
    return oracle.AddGlobalDataTx(data)
}
```

**실제 트랜잭션 예시**:
```solidity
// Local Preimage (게임별)
FaultDisputeGame.addLocalData(
  ident: keccak256(블록 #1000 데이터)[1:],  // 첫 바이트(KeyType) 제외
  claimIdx: 42,                             // 어느 claim에서 필요한지
  offset: 0                                 // 데이터 offset
)

// Global Preimage (공통)
PreimageOracle.loadKeccak256PreimagePart(
  offset: 0,
  data: 블록 #1000의 실제 데이터 (RLP 인코딩)
)
```

**⚠️ 왜 첫 바이트를 제외?**

Preimage Key 구조:
```
[32 bytes total]
├─ Byte 0:    KeyType (1=Local, 2=Keccak256, 4=Sha256, etc.)
└─ Byte 1-31: 실제 해시 값 (31 bytes)

예시: [0x02, 0xab, 0xc1, ..., 0xef]
       ↑     ↑──────────────────┘
    KeyType      Hash (31 bytes)
```

첫 바이트 제외 이유:
```
1. Contract는 이미 KeyType을 알고 있음
   ├─ addLocalData() → Local (KeyType = 1)
   └─ loadKeccak256PreimagePart() → Keccak256 (KeyType = 2)

2. 중복 저장 방지 (가스 절약)
   └─ 함수명이 KeyType 역할

3. Contract는 31바이트 식별자만 필요
   └─ GetIdent() = OracleKey[1:]
```

---

## 🔐 보안: 악의적인 Preimage 업로드 방어

### ❓ 질문: 아무나 Preimage를 업로드할 수 있는가?

**답: 네, 아무나 업로드 가능합니다 (Permissionless).**

하지만 **악의적 데이터는 무용지물**입니다!

### 🛡️ 자기 증명 (Self-Proving) 메커니즘

```solidity
// PreimageOracle.sol:loadKeccak256PreimagePart()

function loadKeccak256PreimagePart(uint256 _partOffset, bytes calldata _preimage) external {
    uint256 size;
    bytes32 key;
    bytes32 part;
    assembly {
        // 업로드된 데이터의 크기 읽기
        size := calldataload(0x44)

        let ptr := 0x80
        // 길이 접두사 추가 (8 bytes)
        mstore(ptr, shl(192, size))
        ptr := add(ptr, 0x08)

        // 업로드된 데이터 복사
        calldatacopy(ptr, _preimage.offset, size)

        // ⭐ 핵심: 업로드된 데이터를 해싱해서 Key 생성!
        let h := keccak256(ptr, size)

        // KeyType 접두사 추가 (0x02)
        key := or(and(h, not(shl(248, 0xFF))), shl(248, 0x02))
    }

    // ⭐ 자동 생성된 Key로 저장!
    preimagePartOk[key][_partOffset] = true;
    preimageParts[key][_partOffset] = part;
    preimageLengths[key] = size;
}
```

### 🎯 작동 원리:

```
┌─────────────────────────────────────────────────────┐
│ 시나리오 1: 정직한 데이터 업로드                    │
├─────────────────────────────────────────────────────┤
│ Challenger 업로드:                                  │
│ ├─ 데이터: 블록 #1000 (올바른 RLP)                 │
│ ├─ Contract가 자동 해싱: keccak256(데이터)         │
│ └─ Key 생성: 0x02abc123...                         │
│                                                     │
│ 저장:                                               │
│ └─ preimagePartOk[0x02abc123...][0] = true         │
│ └─ preimageParts[0x02abc123...][0] = 데이터        │
│                                                     │
│ Cannon VM 실행 (step):                             │
│ ├─ "블록 #1000 필요!" → Key 계산: 0x02abc123...   │
│ ├─ preimagePartOk[0x02abc123...] 조회              │
│ └─ 데이터 발견! ✅ 사용                             │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ 시나리오 2: 악의적인 데이터 업로드 시도 ❌          │
├─────────────────────────────────────────────────────┤
│ 공격자 업로드:                                      │
│ ├─ 데이터: "가짜 블록 #1000" (잘못된 데이터)       │
│ ├─ Contract가 자동 해싱: keccak256(가짜 데이터)    │
│ └─ Key 생성: 0x02def456... ← 다른 Key!             │
│                                                     │
│ 저장:                                               │
│ └─ preimagePartOk[0x02def456...][0] = true         │
│ └─ preimageParts[0x02def456...][0] = 가짜 데이터   │
│                                                     │
│ Cannon VM 실행 (step):                             │
│ ├─ "블록 #1000 필요!" → Key 계산: 0x02abc123...   │
│ │  (올바른 블록의 해시)                            │
│ ├─ preimagePartOk[0x02abc123...] 조회              │
│ └─ 데이터 없음! ❌ step() 실패                      │
│                                                     │
│ 결과:                                               │
│ └─ 악의적 데이터(0x02def456...)는 무시됨!          │
│ └─ 올바른 Key(0x02abc123...)만 유효!               │
└─────────────────────────────────────────────────────┘
```

### 💡 핵심 메커니즘:

**1. Key는 데이터의 해시**
```
Key = KeyType (1 byte) + keccak256(data)[1:31] (31 bytes)

데이터가 다르면 → Key가 다름
Key가 다르면 → VM이 찾지 못함
```

**2. VM은 정확한 Key를 요청**
```
op-program 실행 중:
"블록 #1000 데이터 필요!"
→ Key = keccak256(올바른 블록 #1000)
→ PreimageOracle.get(Key)
→ 그 Key에 저장된 데이터만 반환
```

**3. 잘못된 데이터는 다른 Key로 저장됨**
```
정직한 데이터: Key = 0x02aaa...
악의적 데이터: Key = 0x02bbb...

VM이 0x02aaa...를 요청
→ 0x02bbb...는 무시됨!
```

### 🎯 실전 예시:

```
공격 시나리오:
├─ 공격자: "내가 잘못된 데이터를 올려서 Challenger를 방해하자!"
├─ 업로드: keccak256("가짜") = 0x02def...
└─ 저장: preimagePartOk[0x02def...] = true

step() 실행:
├─ Cannon VM: "블록 #1000 데이터 주세요"
├─ 필요한 Key 계산: keccak256("진짜 블록 #1000") = 0x02abc...
├─ 조회: preimagePartOk[0x02abc...] ?
├─ 결과: 없음! (공격자는 0x02def...에 저장)
└─ step() 실패! ❌

공격 실패 이유:
└─ VM은 "올바른 데이터의 해시"를 Key로 요청
└─ "잘못된 데이터의 해시"는 다른 Key
└─ 악의적 데이터는 접근조차 안 됨!
```

### ✅ 결론:

| 질문 | 답변 |
|------|------|
| **아무나 업로드 가능?** | ✅ 네, Permissionless |
| **악의적 데이터 업로드 가능?** | ✅ 네, 업로드는 가능 |
| **악의적 데이터가 사용됨?** | ❌ 아니오, 절대 사용 안 됨 |
| **이유는?** | Key = Hash(데이터)<br/>잘못된 데이터 = 다른 Key<br/>VM은 올바른 Key만 요청 |

**보안 원리**:
```
Self-Proving (자기 증명):
├─ 데이터 자체가 Key를 결정
├─ Key가 데이터의 무결성을 증명
└─ 암호학적으로 안전 (keccak256)
```

**누구나 업로드 가능하지만, 올바른 데이터만 사용됩니다!** 🔐

**4. step() 실행 과정**:
```go
// FaultDisputeGame.step() 호출

입력:
├─ Prestate Hash: 0x03a1a135... (고정된 초기 상태)
├─ Claim Position: 게임 트리에서의 위치
└─ State Witness: 증명 데이터

Cannon VM 내부 동작:
┌─────────────────────────────────────────┐
│ 1. Prestate로 VM 초기화                 │
│    └─ op-program 바이너리 로드          │
│                                         │
│ 2. op-program 실행 (MIPS로)             │
│    └─ 블록 #1000 처리 시작              │
│                                         │
│ 3. op-program이 데이터 요청 (syscall)   │
│    "블록 #1000 데이터 주세요!"          │
│    └─ Preimage Oracle에 요청            │
│       key = keccak256("block#1000")     │
│                                         │
│ 4. Preimage Oracle 응답                 │
│    └─ L1 Contract에서 데이터 읽기       │
│    └─ 블록 #1000 데이터 반환            │
│                                         │
│ 5. op-program 계속 실행                 │
│    └─ 트랜잭션 #5 처리                  │
│    └─ State 업데이트                    │
│                                         │
│ 6. 단일 MIPS 명령어 실행                │
│    예: lw $t0, 0($sp)                   │
│    (메모리에서 트랜잭션 데이터 로드)    │
│                                         │
│ 7. Poststate 생성                       │
│    └─ 명령어 실행 후 VM 상태            │
│    └─ 해시 계산                         │
└─────────────────────────────────────────┘

출력:
└─ Poststate Hash: 0x5678abcd...

온체인 검증:
├─ Prestate Hash (0x03a1a135...) ✅
├─ 명령어 (#12,345,678) ✅
├─ Preimage (블록 #1000 데이터) ✅
└─ Poststate Hash 일치? → 검증 완료!
```

**관련 코드 위치**:
```
1. FaultDisputeGame.step() 검증 로직
   └─ packages/contracts-bedrock/src/dispute/FaultDisputeGame.sol:393-471

2. Cannon VM 실행 (MIPS)
   └─ packages/contracts-bedrock/src/cannon/MIPS64.sol:126-136

3. Asterisc VM 실행 (RISC-V)
   └─ packages/contracts-bedrock/src/vendor/asterisc/RISCV.sol:26-27

4. IBigStepper 인터페이스
   └─ packages/contracts-bedrock/interfaces/dispute/IBigStepper.sol:35-41

5. PreimageOracle 데이터 제공
   └─ packages/contracts-bedrock/src/cannon/PreimageOracle.sol:212-245
```

**step() 온체인 검증 코드**:
```solidity
// FaultDisputeGame.sol:393-471

function step(
    uint256 _claimIndex,
    bool _isAttack,
    bytes calldata _stateData,
    bytes calldata _proof
) public virtual {
    // 1️⃣ 게임 상태 확인
    if (status != GameStatus.IN_PROGRESS) revert GameNotInProgress();

    // 2️⃣ Claim 정보 가져오기
    ClaimData storage parent = claimData[_claimIndex];
    Position parentPos = parent.position;
    Position stepPos = parentPos.move(_isAttack);

    // 3️⃣ MaxDepth 확인
    if (stepPos.depth() != MAX_GAME_DEPTH + 1) revert InvalidParent();

    // 4️⃣ Prestate/Poststate Claim 결정
    Claim preStateClaim;
    ClaimData storage postState;
    if (_isAttack) {
        // Attack: Absolute Prestate 또는 게임 트리의 이전 Claim
        preStateClaim = (stepPos.indexAtDepth() % (1 << (MAX_GAME_DEPTH - SPLIT_DEPTH))) == 0
            ? ABSOLUTE_PRESTATE  // ← Validator 1에서 검증한 값!
            : _findTraceAncestor(...).claim;
        postState = parent;
    } else {
        // Defend: 부모가 Prestate, 다음이 Poststate
        preStateClaim = parent.claim;
        postState = _findTraceAncestor(...);
    }

    // 5️⃣ ⭐ Prestate 검증: _stateData가 preStateClaim의 preimage인지 확인
    if (keccak256(_stateData) << 8 != preStateClaim.raw() << 8) {
        revert InvalidPrestate();
    }
    // → 잘못된 _stateData를 넣으면 여기서 Revert!
                                                                                                                                                                                                                                                        
    // 6️⃣ Local Context 계산 (Preimage Key 접두사)
    Hash uuid = _findLocalContext(_claimIndex);

    // 7️⃣ ⭐ VM 실행: 단일 MIPS/RISC-V 명령어 실행
    bool validStep = VM.step(_stateData, _proof, uuid.raw()) == postState.claim.raw();
    // → VM.step() 내부에서 Preimage Oracle 조회!
    // → 악의적 Preimage는 Key가 달라서 찾지 못함!

    // 8️⃣ 검증 결과 확인
    bool parentPostAgree = (parentPos.depth() - postState.position.depth()) % 2 == 0;
    if (parentPostAgree == validStep) revert ValidStep();
    // → Poststate가 일치하지 않으면 여기서 Revert!

    // 9️⃣ Claim countered 설정
    parent.counteredBy = msg.sender;
}
```

**VM.step() 구현 (MIPS64.sol)**:
```solidity
// MIPS64.sol:126-136

function step(
    bytes calldata _stateData,
    bytes calldata _proof,
    bytes32 _localContext
) public returns (bytes32 postState_) {
    // 실제 MIPS 명령어 실행
    postState_ = doStep(_stateData, _proof, _localContext);

    // Poststate 검증
    assertPostStateChecks();
}
```

**doStep() 내부 (간략)**:
```solidity
function doStep(...) internal returns (bytes32) {
    // 1. State 로드
    State memory state;
    assembly {
        // _stateData를 메모리에 로드
        ...
    }

    // 2. 명령어 읽기
    uint32 insn = readMemory(state.pc);

    // 3. 명령어 실행 (MIPS)
    if (insn == ADD) {
        state.registers[rd] = state.registers[rs] + state.registers[rt];
    }
    // ... 100개 이상의 MIPS 명령어 처리

    // 4. Syscall 처리 (Preimage 요청)
    if (insn == SYSCALL && state.registers[v0] == SYS_READ_PREIMAGE) {
        // ⭐ Preimage Oracle Contract 직접 조회! (온체인)
        bytes32 key = computePreimageKey(_localContext, ...);

        // ⭐ PreimageOracle Contract 호출 (external call!)
        (bytes32 value, uint256 length) = oracle.readPreimage(key, offset);
        // → oracle은 IPreimageOracle 인터페이스
        // → 실제 PreimageOracle.sol contract 호출
        // → Key가 없으면 "pre-image must exist" Revert!
        // → 악의적 데이터는 다른 Key에 있어서 못 찾음!

        // VM 메모리에 데이터 쓰기
        state.memory[addr] = value;
    }

    // 5. Poststate Hash 계산
    return keccak256(abi.encode(state));
}
```

**실제 코드 (MIPS64Syscalls.sol:259-286)**:
```solidity
// packages/contracts-bedrock/src/cannon/libraries/MIPS64Syscalls.sol

function handleSysRead(SysReadParams memory _args) internal view returns (...) {
    // pre-image oracle read
    if (_args.a0 == FD_PREIMAGE_READ) {
        uint64 effAddr = _args.a1 & arch.ADDRESS_MASK;

        // 메모리 검증
        uint64 mem = MIPS64Memory.readMem(_args.memRoot, effAddr, _args.proofOffset);

        // Local Key면 localize (게임별 context 추가)
        if (uint8(_args.preimageKey[0]) == 1) {
            _args.preimageKey = PreimageKeyLib.localize(_args.preimageKey, _args.localContext);
        }

        // ⭐⭐⭐ PreimageOracle Contract 직접 호출! ⭐⭐⭐
        (bytes32 dat, uint256 datLen) = _args.oracle.readPreimage(_args.preimageKey, _args.preimageOffset);
        // → _args.oracle = IPreimageOracle (Contract 주소)
        // → 온체인 Storage 조회!

        // 데이터를 VM 메모리에 쓰기
        // ... (메모리 업데이트 로직)
    }
}
```

**PreimageOracle.readPreimage() 구현**:
```solidity
// PreimageOracle.sol:134-147

function readPreimage(bytes32 _key, uint256 _offset)
    external
    view
    returns (bytes32 dat_, uint256 datLen_)
{
    // ⭐ Storage 조회!
    require(preimagePartOk[_key][_offset], "pre-image must exist");
    // → Key가 없으면 여기서 Revert!
    // → 악의적 데이터는 다른 Key라 찾지 못함!

    // 데이터 길이 계산
    datLen_ = 32;
    uint256 length = preimageLengths[_key];
    if (_offset + 32 >= length + 8) {
        datLen_ = length + 8 - _offset;
    }

    // ⭐ Storage에서 Preimage 데이터 읽기
    dat_ = preimageParts[_key][_offset];
    // → 업로드된 데이터 반환
}
```

### 🎯 온체인 실행 흐름:

```
⚠️ 중요: 모든 단계가 **온체인(L1)**에서 실행됩니다!

1. FaultDisputeGame.step() 호출 (L1 트랜잭션 시작) 🌐
   ├─ 위치: L1 Blockchain (Ethereum)
   ├─ 언어: Solidity
   └─ 입력: _stateData, _proof

2. VM.step() 호출 (MIPS64.sol) 🌐
   ├─ 위치: L1 Blockchain (같은 트랜잭션 내부!)
   ├─ 언어: Solidity (MIPS VM이 Solidity로 구현됨!)
   └─ doStep(_stateData, _proof, _localContext)

3. MIPS 명령어 실행 중 🌐
   ├─ 위치: L1 Blockchain (같은 트랜잭션!)
   ├─ 언어: Solidity (MIPS 에뮬레이터)
   └─ syscall (SYS_READ_PREIMAGE)

4. handleSysRead() 호출 (MIPS64Syscalls.sol) 🌐
   ├─ 위치: L1 Blockchain (같은 트랜잭션!)
   ├─ 언어: Solidity
   └─ _args.oracle.readPreimage(key, offset)

5. ⭐ PreimageOracle.readPreimage() 호출 (external call) 🌐
   ├─ 위치: L1 Blockchain (같은 트랜잭션!)
   ├─ 언어: Solidity
   ├─ Storage 조회: preimagePartOk[key][offset]
   ├─ 없으면: Revert "pre-image must exist"
   └─ 있으면: preimageParts[key][offset] 반환

6. VM 메모리에 데이터 쓰기 🌐
   ├─ 위치: L1 Blockchain (같은 트랜잭션!)
   └─ state.memory[addr] = value

7. 명령어 실행 완료 🌐
   ├─ 위치: L1 Blockchain (같은 트랜잭션!)
   └─ Poststate Hash 반환

🎯 모든 것이 하나의 L1 트랜잭션 안에서 실행됩니다!
```

### ⚠️ 핵심 오해 정정:

**오해**: "2번은 로컬에서 실행하고, 검증하려고 로컬에서 다시 돌린다"

**실제**:
```
❌ Off-chain (로컬):
   └─ 없음! (step() 시에는)

✅ On-chain (L1 트랜잭션):
   ├─ FaultDisputeGame.step()
   ├─ VM.step() (MIPS64.sol) ← Solidity로 작성!
   ├─ doStep() ← Solidity로 작성!
   ├─ handleSysRead() ← Solidity로 작성!
   └─ PreimageOracle.readPreimage() ← Solidity

   모두 하나의 L1 트랜잭션 안에서 실행!
```

### 💡 Cannon VM = Solidity로 작성된 MIPS 에뮬레이터

```
Off-chain Cannon (로컬):
├─ cannon/bin/cannon (Go 바이너리)
├─ 용도: Challenger가 로컬에서 계산
└─ 결과: 정직한 Claim 값, StepData 생성

On-chain Cannon (L1 Contract):
├─ MIPS64.sol (Solidity 코드)
├─ 용도: L1에서 단일 명령어 검증
└─ 결과: Poststate Hash (온체인 검증)
```

**핵심**:
- **같은 MIPS VM**이 두 가지 구현으로 존재
- **Off-chain (Go)**: 빠른 계산, Challenger 사용
- **On-chain (Solidity)**: 느림, 하지만 검증 가능!

### 📊 전체 그림:

```
┌─────────────────────────────────────────┐
│ Off-chain (Challenger 로컬)             │
├─────────────────────────────────────────┤
│ 1. L2 Node 동기화                       │
│ 2. Bisection 계산 (cannon/bin/cannon)  │
│ 3. StepData 생성                        │
│ 4. Preimage 수집 (L1/L2 RPC)           │
│ 5. Preimage 업로드 (L1 TX)             │
└────────┬────────────────────────────────┘
         │
         ↓ (6. step() 트랜잭션 전송)
         │
┌────────┴────────────────────────────────┐
│ On-chain (L1 Blockchain) 🌐             │
├─────────────────────────────────────────┤
│ ⭐ 하나의 트랜잭션 안에서:               │
│                                         │
│ 7. FaultDisputeGame.step()             │
│    └─ Solidity 실행                     │
│                                         │
│ 8. VM.step() (MIPS64.sol)              │
│    └─ Solidity로 작성된 MIPS VM!        │
│                                         │
│ 9. doStep()                            │
│    └─ MIPS 명령어 실행 (Solidity)       │
│                                         │
│ 10. handleSysRead()                    │
│     └─ Preimage 요청 (Solidity)        │
│                                         │
│ 11. PreimageOracle.readPreimage()      │
│     └─ Storage 조회 (Solidity)         │
│                                         │
│ 12. Poststate Hash 계산                │
│     └─ 검증 완료! ✅                    │
└─────────────────────────────────────────┘
```

**결론**:
- 1-6단계: Off-chain (Challenger 로컬)
- 7-12단계: **On-chain (모두 L1 트랜잭션 안에서!)**
- VM도, Preimage 조회도, 모두 **Solidity**로 실행!

이것이 Fault Proof의 핵심입니다! 🚀

**결론**:
- ✅ 네, **PreimageOracle Contract를 직접 조회**합니다!
- ✅ **External call** (`view` 함수)
- ✅ **Storage 읽기** (`preimagePartOk`, `preimageParts`)
- ✅ 모든 것이 **온체인에서 실행**됩니다!

---

### 🎯 핵심 포인트

**1. Prestate는 "프로그램"만 포함**:
```
Prestate = op-program 바이너리 + 초기 VM 상태

NOT 포함:
- 블록 데이터 ❌
- 트랜잭션 ❌
- State Root ❌
```

**2. 실제 데이터는 Preimage로 제공**:
```
op-program 실행 중:
"블록 #1000 데이터 필요!" → Preimage Oracle 조회 → 데이터 획득
"트랜잭션 #5 필요!" → Preimage Oracle 조회 → 데이터 획득
"State Trie 노드 필요!" → Preimage Oracle 조회 → 데이터 획득
```

**3. Preimage는 양측이 동의한 데이터**:
```
Preimage 제공 방식:
├─ Local Preimage (게임별 데이터)
│  ├─ Challenger가 L1에 업로드
│  ├─ step() 전에 미리 업로드해야 함
│  └─ 예: 특정 블록 데이터
│
└─ Global Preimage (공통 데이터)
   ├─ L1 블록 헤더 (L1에 이미 존재)
   ├─ 모든 게임에서 공유
   └─ 별도 업로드 불필요
```

**4. 왜 이렇게 설계했나?**:
```
✅ 장점:
├─ Prestate Hash 고정 → 재현 가능
├─ 다른 블록 검증 시 같은 Prestate 재사용
├─ 온체인 저장 공간 절약
└─ 필요한 데이터만 제공

만약 Prestate에 모든 데이터 포함 시:
❌ 블록마다 다른 Prestate Hash
❌ 재현 불가능
❌ 온체인 저장 폭발
```

---

### 📝 실제 코드 예시

**op-program이 데이터를 요청하는 방식**:
```go
// op-program/client/l2/oracle.go

// 블록 데이터 요청
func (o *Oracle) GetBlock(blockHash common.Hash) (*types.Block, error) {
    // Preimage Oracle에 데이터 요청
    key := crypto.Keccak256Hash(blockHash.Bytes())

    // syscall을 통해 Cannon VM에 요청
    // Cannon VM은 Preimage Oracle에서 데이터 가져옴
    data := o.preimageOracle.Get(key)

    // 블록 디코딩
    var block types.Block
    rlp.DecodeBytes(data, &block)
    return &block, nil
}
```

**Cannon VM이 Preimage를 처리하는 방식**:
```go
// cannon/mipsevm/oracle.go

// MIPS syscall 처리
func (m *MIPS) HandleSyscall() {
    syscallNum := m.registers[2] // $v0

    if syscallNum == SYS_READ_PREIMAGE {
        key := m.registers[4] // $a0 (preimage key)

        // Preimage Oracle에서 데이터 읽기
        data := m.preimageOracle.ReadPreimage(key)

        // 메모리에 데이터 쓰기
        m.memory.Write(addr, data)
    }
}
```

**Challenger가 Preimage를 업로드**:
```go
// op-challenger/game/fault/trace/cannon/executor.go

// step() 호출 전 Preimage 업로드
func (e *Executor) DoStep(ctx context.Context, pos Position) error {
    // 1. 필요한 Preimage 수집
    preimages := e.collectRequiredPreimages(pos)

    // 2. L1에 업로드
    for _, preimage := range preimages {
        tx := e.contract.UpdateOracleTx(
            preimage.Key,
            preimage.Data,
        )
        e.sendTransaction(ctx, tx)
    }

    // 3. step() 호출
    tx := e.contract.StepTx(pos, stateWitness)
    return e.sendTransaction(ctx, tx)
}
```

---

## 🔑 Preimage 생성 및 업로드 상세

### 누가 Preimage를 올리는가?

**답: step()을 호출하는 쪽이 올립니다** (보통 Challenger)

```
┌─────────────────────────────────────────┐
│ Fault Proof 게임 참여자                 │
├─────────────────────────────────────────┤
│ Proposer (OP-Proposer)                  │
│ └─ Output Root 제안                     │
│ └─ Preimage 업로드 안 함 (보통)         │
│                                         │
│ Challenger (OP-Challenger) ⭐           │
│ └─ Output Root 검증                     │
│ └─ step() 호출                          │
│ └─ Preimage 업로드 필수!                │
└─────────────────────────────────────────┘

이유:
├─ Challenger가 정직한 계산을 증명하려면
├─ 온체인에서 검증 가능한 데이터 필요
└─ step() 전에 필요한 모든 데이터를 미리 업로드
```

### Preimage는 어떻게 만들어지나?

**1단계: 데이터 소스 식별**

```
Challenger는 두 가지 데이터 소스를 가짐:

┌─────────────────────────────────────────┐
│ L1 Node (Ethereum)                      │
├─────────────────────────────────────────┤
│ - L1 블록 헤더                          │
│ - L1 트랜잭션                           │
│ - L1 Receipt                            │
│ - Deposit 트랜잭션 (L1→L2)              │
└─────────────────────────────────────────┘
         ↓
    RPC 조회
         ↓
┌─────────────────────────────────────────┐
│ L2 Node (Optimism)                      │
├─────────────────────────────────────────┤
│ - L2 블록 헤더                          │
│ - L2 트랜잭션                           │
│ - L2 Receipt                            │
│ - L2 State Trie                         │
│ - L2 Storage                            │
└─────────────────────────────────────────┘
```

**2단계: 필요한 Preimage 결정**

```go
// op-challenger가 게임 트리 분석

게임 위치 → 어떤 블록? → 어떤 트랜잭션? → 어떤 State?

예: Position 12345
├─ 블록 번호: #1000 계산
├─ 트랜잭션 인덱스: #5 계산
├─ State 접근: 0x123...addr 계산
└─ 필요한 Preimage 목록 생성
   ├─ 블록 #1000 헤더
   ├─ 트랜잭션 #5 데이터
   └─ State Trie 노드 3개
```

**3단계: 데이터 수집 (RPC)**

```go
// Challenger가 L1/L2 Node에서 데이터 가져오기

// L1 데이터
l1Block := l1Client.BlockByNumber(ctx, blockNum)
l1Header := l1Block.Header()
l1Txs := l1Block.Transactions()

// L2 데이터
l2Block := l2Client.BlockByNumber(ctx, blockNum)
l2Header := l2Block.Header()
l2Txs := l2Block.Transactions()

// State 데이터
proof := l2Client.GetProof(ctx, address, keys, blockNum)
// → Merkle Proof 포함 State Trie 노드들
```

**4단계: Preimage 포맷 생성**

```go
// Key-Value 형식으로 변환

type Preimage struct {
    Key  [32]byte  // Keccak256 해시
    Data []byte    // 실제 데이터 (RLP 인코딩)
}

// 예: L2 블록 헤더
blockRLP := rlp.Encode(l2Header)
key := crypto.Keccak256Hash(blockRLP)

preimage := Preimage{
    Key:  key,
    Data: blockRLP,
}
```

**5단계: L1 Contract에 업로드**

```solidity
// PreimageOracle.sol

function addLocalData(
    bytes32 _key,
    bytes calldata _data,
    uint256 _offset
) external {
    // 데이터 저장
    localPreimages[_key] = _data;
}
```

---

### 📊 Preimage 생성 전체 흐름

```
┌────────────────────────────────────────────────────┐
│ 1. 게임 진행 중 (Challenger)                       │
├────────────────────────────────────────────────────┤
│ - Bisection으로 분쟁 지점 좁힘                     │
│ - MaxDepth 도달: step() 필요                       │
│ - Position: 12345 (블록 #1000, TX #5)             │
└────────────────────────────────────────────────────┘
         ↓
┌────────────────────────────────────────────────────┐
│ 2. 필요한 데이터 분석                              │
├────────────────────────────────────────────────────┤
│ Trace Provider (Cannon/Asterisc)                   │
│ └─ Position → 실행 단계 매핑                       │
│ └─ 어떤 데이터 필요한지 계산                       │
│                                                    │
│ 필요 목록:                                         │
│ ├─ L1 블록 #500 헤더                               │
│ ├─ L2 블록 #1000 헤더                              │
│ ├─ L2 블록 #1000 트랜잭션 목록                     │
│ ├─ 트랜잭션 #5 데이터                              │
│ └─ State Trie 노드 (address 0x123...)             │
└────────────────────────────────────────────────────┘
         ↓
┌────────────────────────────────────────────────────┐
│ 3. L1/L2 Node에서 데이터 가져오기 (RPC)            │
├────────────────────────────────────────────────────┤
│ L1 Node:                                           │
│ └─ eth_getBlockByNumber(500)                       │
│ └─ eth_getTransactionByHash(...)                   │
│                                                    │
│ L2 Node:                                           │
│ └─ eth_getBlockByNumber(1000)                      │
│ └─ eth_getTransactionByHash(...)                   │
│ └─ eth_getProof(0x123..., [...], 1000)            │
│    └─ Returns: Merkle Proof + Trie Nodes          │
└────────────────────────────────────────────────────┘
         ↓
┌────────────────────────────────────────────────────┐
│ 4. Preimage 포맷 변환                              │
├────────────────────────────────────────────────────┤
│ For each data:                                     │
│ 1. RLP 인코딩                                      │
│    data_rlp = rlp.Encode(blockHeader)              │
│                                                    │
│ 2. Key 계산                                        │
│    key = Keccak256(data_rlp)                       │
│                                                    │
│ 3. Preimage 생성                                   │
│    {                                               │
│      key: 0xabcd1234...,                           │
│      data: data_rlp,                               │
│      size: len(data_rlp)                           │
│    }                                               │
└────────────────────────────────────────────────────┘
         ↓
┌────────────────────────────────────────────────────┐
│ 5. 크기별 업로드 전략 선택                         │
├────────────────────────────────────────────────────┤
│ Small (< 4KB):                                     │
│ └─ DirectPreimageUploader                          │
│ └─ 한 트랜잭션에 전체 데이터 업로드                │
│                                                    │
│ Large (≥ 4KB):                                     │
│ └─ LargePreimageUploader                           │
│ └─ 데이터를 청크로 분할                            │
│ └─ 여러 트랜잭션으로 업로드                        │
│                                                    │
│ Auto:                                              │
│ └─ SplitPreimageUploader                           │
│ └─ 크기에 따라 자동 선택                           │
└────────────────────────────────────────────────────┘
         ↓
┌────────────────────────────────────────────────────┐
│ 6. L1 Contract에 업로드 (트랜잭션)                 │
├────────────────────────────────────────────────────┤
│ Small Data:                                        │
│ TX1: PreimageOracle.addLocalData(                  │
│        key: 0xabcd1234...,                         │
│        data: [full data],                          │
│        offset: 0                                   │
│      )                                             │
│                                                    │
│ Large Data:                                        │
│ TX1: PreimageOracle.initLargePreimage(             │
│        key, size                                   │
│      )                                             │
│ TX2: PreimageOracle.addLeaf(key, chunk1, ...)     │
│ TX3: PreimageOracle.addLeaf(key, chunk2, ...)     │
│ ...                                                │
│ TXn: PreimageOracle.squeeze(key, ...)              │
└────────────────────────────────────────────────────┘
         ↓
┌────────────────────────────────────────────────────┐
│ 7. step() 호출                                     │
├────────────────────────────────────────────────────┤
│ TX(n+1): FaultDisputeGame.step(                    │
│            claimIndex,                             │
│            isAttack,                               │
│            stateData,                              │
│            proof                                   │
│          )                                         │
│                                                    │
│ 내부에서:                                          │
│ └─ Cannon VM 실행                                  │
│ └─ Preimage Oracle 조회                            │
│ └─ 업로드된 데이터 사용                            │
│ └─ 단일 명령어 실행 증명                           │
└────────────────────────────────────────────────────┘
```

---

### 💻 실제 코드 예시

#### Preimage 수집 (Challenger)

```go
// op-challenger/game/fault/trace/cannon/provider.go

type CannonTraceProvider struct {
    l1Client *ethclient.Client
    l2Client *ethclient.Client
}

// 필요한 Preimage 수집
func (p *CannonTraceProvider) GetStepData(ctx context.Context, pos Position) (*StepData, error) {
    // 1. Position에서 블록 번호 계산
    blockNum := p.PositionToBlockNumber(pos)

    // 2. L2 블록 가져오기
    l2Block, err := p.l2Client.BlockByNumber(ctx, blockNum)
    if err != nil {
        return nil, err
    }

    // 3. Preimage 생성
    preimages := []Preimage{}

    // L2 블록 헤더
    headerRLP, _ := rlp.EncodeToBytes(l2Block.Header())
    preimages = append(preimages, Preimage{
        Key:  crypto.Keccak256Hash(headerRLP),
        Data: headerRLP,
    })

    // L2 트랜잭션들
    for _, tx := range l2Block.Transactions() {
        txRLP, _ := tx.MarshalBinary()
        preimages = append(preimages, Preimage{
            Key:  crypto.Keccak256Hash(txRLP),
            Data: txRLP,
        })
    }

    // State Proof
    proof, err := p.l2Client.GetProof(ctx, address, keys, blockNum)
    for _, node := range proof.StorageProof {
        preimages = append(preimages, Preimage{
            Key:  crypto.Keccak256Hash(node),
            Data: node,
        })
    }

    return &StepData{
        Preimages: preimages,
    }, nil
}
```

#### Preimage 업로드 (3가지 전략)

```go
// op-challenger/game/fault/preimages/

// 1. Direct Uploader (작은 데이터)
type DirectPreimageUploader struct {
    contract *bindings.PreimageOracle
}

func (u *DirectPreimageUploader) UploadPreimage(ctx context.Context, preimage Preimage) error {
    // 한 트랜잭션에 전체 업로드
    tx, err := u.contract.AddLocalData(
        preimage.Key,
        preimage.Data,
        0, // offset
    )
    return u.sendTx(ctx, tx)
}

// 2. Large Uploader (큰 데이터)
type LargePreimageUploader struct {
    contract *bindings.PreimageOracle
}

func (u *LargePreimageUploader) UploadPreimage(ctx context.Context, preimage Preimage) error {
    // 1. 초기화
    tx1, _ := u.contract.InitLargePreimage(
        preimage.Key,
        uint64(len(preimage.Data)),
    )
    u.sendTx(ctx, tx1)

    // 2. 청크로 분할 업로드
    chunkSize := 4096
    for i := 0; i < len(preimage.Data); i += chunkSize {
        end := i + chunkSize
        if end > len(preimage.Data) {
            end = len(preimage.Data)
        }

        chunk := preimage.Data[i:end]
        tx, _ := u.contract.AddLeaf(
            preimage.Key,
            uint64(i),
            chunk,
        )
        u.sendTx(ctx, tx)
    }

    // 3. 완료
    tx3, _ := u.contract.Squeeze(
        preimage.Key,
        preimage.Key, // commit
    )
    return u.sendTx(ctx, tx3)
}

// 3. Split Uploader (자동 선택)
type SplitPreimageUploader struct {
    direct *DirectPreimageUploader
    large  *LargePreimageUploader
}

func (u *SplitPreimageUploader) UploadPreimage(ctx context.Context, preimage Preimage) error {
    // 크기에 따라 선택
    if len(preimage.Data) < 4096 {
        return u.direct.UploadPreimage(ctx, preimage)
    } else {
        return u.large.UploadPreimage(ctx, preimage)
    }
}
```

#### L1/L2 Node 연결 설정

```go
// op-challenger/config/config.go

type Config struct {
    // L1 Node (Ethereum)
    L1EthRpc string // "https://eth-mainnet.g.alchemy.com/v2/..."

    // L2 Node (Optimism)
    L2EthRpc string // "https://mainnet.optimism.io"

    // Rollup Node (OP-Node)
    RollupRpc string // "http://localhost:9545"
}

// Challenger 실행 시
challenger := NewChallenger(config)
challenger.l1Client = ethclient.Dial(config.L1EthRpc)
challenger.l2Client = ethclient.Dial(config.L2EthRpc)
```

---

### 🎯 핵심 정리

**누가 올리나?**
```
Challenger (step()을 호출하는 쪽)
└─ Proposer의 잘못된 Output Root를 증명하기 위해
└─ 정직한 계산에 필요한 모든 데이터를 제공
```

**어떻게 만들어지나?**
```
1. L1/L2 Node에서 RPC로 데이터 가져오기
   ├─ eth_getBlockByNumber
   ├─ eth_getTransactionByHash
   └─ eth_getProof

2. RLP 인코딩
   └─ 표준 Ethereum 직렬화

3. Key 계산
   └─ Keccak256(RLP 데이터)

4. L1 Contract에 업로드
   ├─ 작은 데이터: 한 번에
   └─ 큰 데이터: 청크로 분할
```

**언제 올리나?**
```
step() 호출 직전!
└─ step() 실행 시 Preimage가 이미 L1에 있어야 함
└─ 없으면 step() 실패
```

**비용은?**
```
L1 가스 비용 발생!
├─ 작은 데이터: ~50,000 gas
├─ 큰 데이터: ~수백만 gas
└─ Challenger가 부담 (나중에 Bond로 회수)
```

### Optimism의 VM 선택지

```
┌──────────────────────────────────────────┐
│ Fault Proof VM 옵션                      │
├──────────────────────────────────────────┤
│ 1. Cannon (MIPS) ⭐                      │
│    ├─ 기본 VM                            │
│    ├─ 안정적                             │
│    └─ GameType = 0                       │
│                                          │
│ 2. Asterisc (RISC-V)                     │
│    ├─ 차세대 VM                          │
│    ├─ 더 현대적인 아키텍처               │
│    └─ GameType = 1                       │
│                                          │
│ 3. OP-Program                            │
│    ├─ Go로 작성된 L2 상태 전환 프로그램  │
│    └─ Cannon/Asterisc VM 내에서 실행     │
└──────────────────────────────────────────┘
```

### 왜 Go 프로그램을 MIPS로 컴파일?

```
op-program (Go) → MIPS 바이너리 → Cannon VM 실행

이유:
1. Go는 MIPS로 컴파일 가능
   └─ GOOS=linux GOARCH=mips go build

2. 온체인 검증 가능
   └─ MIPS는 단순해서 Solidity로 검증 가능

3. 결정론적 실행 보장
   └─ 같은 MIPS 바이너리 = 항상 같은 결과
```

### 실제 사용 예시

```bash
# 1. op-program을 MIPS로 컴파일
GOOS=linux GOARCH=mips64 go build -o op-program-mips ./cmd/op-program

# 2. MIPS 바이너리를 Cannon VM에 로드
cannon load-elf --type=mips64 --path=op-program-mips

# 3. Cannon이 MIPS 명령어를 하나씩 실행
cannon run --proof-at=12345 --proof-fmt=json

# 4. 단일 명령어 실행 증명 생성 (step)
cannon step --state=prestate.json --output=poststate.json
```

---

## 🔧 내부 동작 상세

### 1️⃣ Cannon 바이너리 빌드

```bash
# 실행 위치: /optimism/cannon
make cannon
```

**생성 파일**:
- `cannon/bin/cannon` - Cannon VM 실행 파일

**Cannon의 역할**:
- MIPS 명령어 실행
- 단일 instruction proof 생성 (step() 호출용)
- Fault Proof Game의 최종 검증 단계

**빌드 과정**:
```go
// Go로 작성된 MIPS VM 빌드
1. cannon/main.go 컴파일
2. mipsevm 패키지 링크
3. 실행 파일 생성
```

**실패 시**:
- Go 버전 확인 (1.21+ 필요)
- Makefile 존재 확인
- 디스크 공간 확인

---

### 2️⃣ op-program 바이너리 빌드

```bash
# 실행 위치: /optimism/op-program
make op-program
```

**생성 파일**:
- `op-program/bin/op-program` - L2 상태 전환 프로그램

**op-program의 역할**:
- L2 블록의 상태 전환 계산
- Output Root 검증
- Cannon VM 내에서 실행됨

**빌드 과정**:
```go
// Go로 작성된 L2 상태 전환 프로그램
1. op-program/main.go 컴파일
2. op-node, op-service 패키지 링크
3. 실행 파일 생성
```

---

### 3️⃣ Prestate 파일 생성 ⚠️ 중요!

```bash
# 실행 위치: /optimism/op-program
make reproducible-prestate
```

**생성 파일들**:
- `prestate-mt64.bin.gz` - MT64 (MultiThreaded 64) VM용 prestate
- `prestate-mt64Next.bin.gz` - 차세대 MT64 VM용 prestate
- `prestate-proof-mt64.json` - Prestate 검증 데이터

**Prestate란?**:
```
Prestate = VM의 초기 상태 스냅샷

┌─────────────────────────────────────┐
│ Prestate (absolute prestate)        │
├─────────────────────────────────────┤
│ - 초기 메모리 상태                  │
│ - 초기 레지스터 값                  │
│ - op-program 바이너리 로드          │
│ - VM 설정                           │
└─────────────────────────────────────┘
         ↓
    Cannon VM 실행
         ↓
    Output Root 계산
```

**Prestate의 역할**:
1. **ValidatePrestate()** 시 비교:
   ```
   Challenger의 Prestate Hash
   vs
   L1 Contract의 Prestate Hash

   → 일치해야 게임 참여 가능!
   ```

2. **step() 호출** 시 사용:
   ```
   Prestate → Cannon VM 로드 → 단일 instruction 실행 → 결과 증명
   ```

**빌드 과정**:
```bash
1. op-program 바이너리를 Cannon VM에 로드
2. 초기 상태 캡처
3. 해시 계산 (Keccak256)
4. Gzip 압축
5. JSON 메타데이터 생성
```

**Reproducible (재현 가능)**:
- 같은 코드 = 같은 Prestate Hash
- 컨트랙트 배포 시 이 해시를 사용
- Challenger도 같은 해시로 빌드해야 검증 가능

---

### 4️⃣ Prestate 파일 리네임 🔑 핵심!

```bash
# 실행 위치: /optimism/op-program/bin
mv prestate-mt64.bin.gz prestate.bin.gz
```

**왜 이름을 바꾸나?**:

Challenger 설정에서 Prestate 파일을 다음과 같이 지정:
```bash
--cannon-prestate /path/to/prestate.bin.gz
```

하지만 빌드 시 생성되는 파일명:
```
prestate-mt64.bin.gz        ← MT64 VM용
prestate-mt64Next.bin.gz    ← 차세대 VM용
```

**해결책**:
- 기본 VM (MT64)용 파일을 `prestate.bin.gz`로 리네임
- Challenger가 자동으로 찾을 수 있게 함

**우선순위**:
```bash
if prestate-mt64.bin.gz exists:
    rename to prestate.bin.gz
elif prestate-mt64Next.bin.gz exists:
    rename to prestate.bin.gz
else:
    warning (but continue)
```

---

## 📂 생성되는 파일 구조

```
/optimism/
├─ cannon/bin/
│  └─ cannon                    # Cannon VM 실행 파일
│
└─ op-program/bin/
   ├─ op-program                # L2 상태 전환 프로그램
   ├─ prestate.bin.gz          # ⭐ Prestate (리네임됨)
   └─ prestate-proof-mt64.json # Prestate 검증 데이터
```

**파일 크기 (참고)**:
- `cannon`: ~30-50 MB
- `op-program`: ~80-100 MB
- `prestate.bin.gz`: ~5-10 MB (압축됨)

---

## 🚀 사용 방법

### 기본 사용 (누락된 파일만 빌드)

```bash
cd /optimism/op-challenger/scripts
./build-binaries-for-challenger.sh
```

**동작**:
1. `cannon/bin/cannon` 존재 확인
2. `op-program/bin/op-program` 존재 확인
3. `op-program/bin/prestate.bin.gz` 존재 확인
4. 없는 것만 빌드

**결과**:
```
[INFO] Checking required binary files...
✅ cannon binary found
✅ op-program binary found
✅ prestate file found
🎉 All required binaries are already built!
```

---

### 강제 재빌드 (--force)

```bash
./build-binaries-for-challenger.sh --force
```

**사용 시기**:
1. **Contract 변경 후**:
   - `FaultDisputeGame.sol` 수정
   - `PreimageOracle.sol` 수정
   - → Prestate Hash가 변경될 수 있음!

2. **op-program 코드 변경 후**:
   - `op-program/client/*.go` 수정
   - → Prestate 재생성 필요

3. **Prestate 불일치 오류 시**:
   ```
   ERROR: output root absolute prestate does not match
   Provider: 0x03a1a135...
   Contract: 0xdead0000...
   ```
   → Prestate를 재빌드해야 함

4. **VM 타입 변경 시**:
   - Cannon → Asterisc
   - MT64 → MT64Next
   → 다른 Prestate 필요

**동작**:
```
[INFO] Force rebuild enabled
🔄 cannon binary exists but forcing rebuild
🔄 op-program/prestate exists but forcing rebuild
[INFO] Building missing binaries...
✅ cannon binary built successfully
✅ op-program binary built successfully
✅ prestate files generated successfully
✅ Renamed prestate-mt64.bin.gz -> prestate.bin.gz
🎉 All required binaries are now ready!
```

---

### 도움말 보기

```bash
./build-binaries-for-challenger.sh --help
```

---

## 🔍 검증 방법

### 1. 바이너리 파일 확인

```bash
# Cannon 확인
ls -lh /optimism/cannon/bin/cannon
file /optimism/cannon/bin/cannon
# → ELF 64-bit executable

# op-program 확인
ls -lh /optimism/op-program/bin/op-program
file /optimism/op-program/bin/op-program
# → ELF 64-bit executable

# Prestate 확인
ls -lh /optimism/op-program/bin/prestate.bin.gz
file /optimism/op-program/bin/prestate.bin.gz
# → gzip compressed data
```

---

### 2. Prestate Hash 확인

```bash
cd /optimism/op-program/bin

# Prestate Hash 계산
gunzip -c prestate.bin.gz | sha256sum

# JSON 메타데이터 확인
cat prestate-proof-mt64.json | jq .
```

**출력 예시**:
```json
{
  "pre": "0x03a1a1357e8f72c6892b3c4f4f3e6b0f8d5c7a9b...",
  "post": "0x...",
  "stateHash": "0x..."
}
```

---

### 3. Cannon 실행 테스트

```bash
cd /optimism/cannon

# Help 확인
./bin/cannon --help

# 버전 확인
./bin/cannon version
```

---

### 4. op-program 실행 테스트

```bash
cd /optimism/op-program

# Help 확인
./bin/op-program --help
```

---

## ⚠️ 문제 해결

### 문제 1: "Makefile not found"

**증상**:
```
[ERROR] Makefile not found in cannon directory
```

**원인**: 잘못된 디렉토리 구조

**해결**:
```bash
# Optimism 루트 확인
cd /optimism
ls cannon/Makefile
ls op-program/Makefile

# 없으면 git clone 다시
git clone https://github.com/ethereum-optimism/optimism.git
```

---

### 문제 2: "Failed to build cannon binary"

**증상**:
```
[ERROR] ❌ Failed to build cannon binary
```

**원인**:
1. Go 버전 부족
2. 의존성 없음
3. 디스크 공간 부족

**해결**:
```bash
# Go 버전 확인
go version
# → 1.21+ 필요

# 의존성 설치
cd /optimism/cannon
go mod download

# 디스크 공간 확인
df -h
```

---

### 문제 3: "Failed to generate prestate files"

**증상**:
```
⚠️  Failed to generate prestate files, but continuing
```

**원인**:
1. op-program 바이너리 없음
2. Cannon VM 문제
3. 메모리 부족

**해결**:
```bash
# 수동으로 prestate 생성
cd /optimism/op-program
make reproducible-prestate

# 로그 확인
make reproducible-prestate 2>&1 | tee prestate-build.log

# 메모리 확인
free -h
```

---

### 문제 4: "No MT64 prestate file found"

**증상**:
```
⚠️  No MT64 prestate file found for renaming
```

**원인**: Prestate 생성 실패했지만 계속 진행됨

**해결**:
```bash
# Prestate 수동 생성
cd /optimism/op-program
make reproducible-prestate

# 생성된 파일 확인
ls -la bin/prestate*.bin.gz

# 수동 리네임
cd bin
mv prestate-mt64.bin.gz prestate.bin.gz
```

---

### 문제 5: Permission Denied

**증상**:
```
make: cannon: Permission denied
```

**해결**:
```bash
# 실행 권한 부여
chmod +x /optimism/cannon/bin/cannon
chmod +x /optimism/op-program/bin/op-program

# 디렉토리 권한 확인
ls -la /optimism/cannon/bin/
ls -la /optimism/op-program/bin/
```

---

## 🔗 관련 파일

### 스크립트 내부에서 사용하는 Makefile

**`cannon/Makefile`**:
```makefile
cannon:
	go build -o bin/cannon ./cmd/cannon
```

**`op-program/Makefile`**:
```makefile
op-program:
	go build -o bin/op-program ./cmd/op-program

reproducible-prestate:
	./scripts/build-prestate.sh
```

---

### Prestate 빌드 스크립트

**`op-program/scripts/build-prestate.sh`**:
- op-program을 Cannon VM에 로드
- 초기 상태 캡처
- 해시 계산 및 압축
- JSON 메타데이터 생성

---

## 📊 빌드 시간 (참고)

| 항목 | 소요 시간 | 비고 |
|------|-----------|------|
| cannon 빌드 | ~30초 | Go 컴파일 |
| op-program 빌드 | ~1-2분 | 복잡한 의존성 |
| prestate 생성 | ~2-3분 | VM 실행 + 상태 캡처 |
| **전체** | **~4-6분** | 첫 빌드 기준 |
| 재빌드 (--force) | ~3-4분 | 캐시 사용 |

---

## 🎯 Challenger와의 연동

빌드된 파일들은 Challenger 실행 시 다음과 같이 사용됩니다:

```bash
op-challenger \
  --cannon-bin /optimism/cannon/bin/cannon \
  --cannon-server /optimism/op-program/bin/op-program \
  --cannon-prestate /optimism/op-program/bin/prestate.bin.gz \
  --cannon-network mainnet \
  ...
```

**각 파일의 역할**:
1. `--cannon-bin`: step() 호출 시 단일 instruction 실행
2. `--cannon-server`: 중간 상태 계산 (bisection)
3. `--cannon-prestate`: ValidatePrestate() 검증 + step() 초기 상태

---

## 📚 참고 문서

- `installation-guide.md` - 기본 사용법
- `troubleshooting-guide.md` - 문제 해결
- `prestate-hash-explanation.md` - Prestate 상세 설명
- `challenger_validation_script.md` - Prestate 검증 과정

---

## 🔄 업데이트 시나리오

### 시나리오 1: Contract 업그레이드

```bash
# 1. Contract 변경
cd /optimism/packages/contracts-bedrock
forge build

# 2. Prestate 재생성 (Hash가 변경될 수 있음!)
cd /optimism/op-challenger/scripts
./build-binaries-for-challenger.sh --force

# 3. 새 Prestate Hash 확인
cd /optimism/op-program/bin
gunzip -c prestate.bin.gz | keccak256sum

# 4. Devnet 재배포 (새 Hash로)
cd /optimism/kurtosis-devnet
kurtosis clean -a
kurtosis run --enclave optimism-devnet .
```

---

### 시나리오 2: op-program 코드 수정

```bash
# 1. op-program 수정
cd /optimism/op-program
vim client/l2_client.go

# 2. 재빌드
cd /optimism/op-challenger/scripts
./build-binaries-for-challenger.sh --force

# 3. Challenger 재시작
./run-challenger-devnet.sh
```

---

### 시나리오 3: VM 타입 변경 (Cannon → Asterisc)

```bash
# 1. Asterisc 빌드 (별도 스크립트)
cd /optimism/op-challenger/scripts
./build-asterisc-binaries.sh

# 2. Challenger 설정 변경
# --game-type=1 (Asterisc)

# 3. Devnet 재배포
cd /optimism/kurtosis-devnet
kurtosis run --enclave optimism-devnet . --args-file asterisc-config.yaml
```

---

## 💡 Best Practices

### 1. 빌드 전 체크리스트

```bash
# Go 버전
go version  # 1.21+

# 디스크 공간
df -h  # 최소 10GB 여유

# Git 상태
git status  # Clean working directory

# 의존성
cd /optimism && go mod download
```

---

### 2. 빌드 후 검증

```bash
# 1. 파일 존재 확인
test -f /optimism/cannon/bin/cannon && echo "✅ cannon"
test -f /optimism/op-program/bin/op-program && echo "✅ op-program"
test -f /optimism/op-program/bin/prestate.bin.gz && echo "✅ prestate"

# 2. 실행 가능 확인
/optimism/cannon/bin/cannon --help
/optimism/op-program/bin/op-program --help

# 3. Prestate Hash 확인
cd /optimism/op-program/bin
gunzip -c prestate.bin.gz | sha256sum
```

---

### 3. CI/CD 통합

```yaml
# .github/workflows/build-binaries.yml
name: Build Challenger Binaries

on:
  push:
    paths:
      - 'cannon/**'
      - 'op-program/**'
      - 'packages/contracts-bedrock/src/dispute/**'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Go
        uses: actions/setup-go@v4
        with:
          go-version: '1.21'

      - name: Build Binaries
        run: |
          cd op-challenger/scripts
          ./build-binaries-for-challenger.sh --force

      - name: Upload Artifacts
        uses: actions/upload-artifact@v3
        with:
          name: challenger-binaries
          path: |
            cannon/bin/cannon
            op-program/bin/op-program
            op-program/bin/prestate.bin.gz
```

---

## 🎓 요약

`build-binaries-for-challenger.sh`는:

✅ **빌드**:
- Cannon VM (MIPS 실행기)
- op-program (L2 상태 전환)
- Prestate (VM 초기 상태)

✅ **자동화**:
- 누락된 파일만 빌드 (기본)
- 강제 재빌드 (--force)
- Prestate 리네임 자동화

✅ **검증**:
- Makefile 존재 확인
- 빌드 성공/실패 체크
- 상세한 로그 출력

이 스크립트 하나로 Challenger 동작에 필요한 모든 바이너리를 준비할 수 있습니다! 🚀

