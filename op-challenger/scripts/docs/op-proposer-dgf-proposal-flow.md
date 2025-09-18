# op-proposer DisputeGameFactory 모드 제안 제출 흐름

## 개요

이 문서는 op-proposer의 DisputeGameFactory 모드에서 L2 Output 제안을 제출하는 상세한 코드 흐름과 구현을 분석합니다.

**⚠️ 중요**: DisputeGameFactory 모드는 게임 타입에 따라 다른 RPC를 사용합니다:
- **게임 타입 0**: DisputeGameFactory + Rollup RPC
- **게임 타입 4,5**: DisputeGameFactory + Supervisor RPC

## 🎯 핵심 제안 제출 코드 위치

### 1. 메인 제안 제출 로직

**파일**: `proposer/driver.go`
**함수**: `sendTransaction` (376-416라인)

```go
// sendTransaction creates & sends transactions through the underlying transaction manager.
func (l *L2OutputSubmitter) sendTransaction(ctx context.Context, output source.Proposal) error {
    l.Log.Info("Proposing output root", "output", output.Root, "block", output.SequenceNum)
    var receipt *types.Receipt

    // DisputeGameFactory 모드인지 확인
    if l.Cfg.DisputeGameFactoryAddr != nil {
        // DGF 모드: 트랜잭션 후보 생성
        candidate, err := l.ProposeL2OutputDGFTxCandidate(ctx, output)
        if err != nil {
            return err
        }
        // 트랜잭션 전송
        receipt, err = l.Txmgr.Send(ctx, candidate)
        if err != nil {
            return err
        }
    } else {
        // L2OutputOracle 모드 (기존 방식)
        err := l.waitForL1Head(ctx, output.Legacy.HeadL1.Number+1)
        if err != nil {
            return err
        }
        data, err := l.ProposeL2OutputTxData(output)
        if err != nil {
            return err
        }
        receipt, err = l.Txmgr.Send(ctx, txmgr.TxCandidate{
            TxData:   data,
            To:       l.Cfg.L2OutputOracleAddr,
            GasLimit: 0,
        })
        if err != nil {
            return err
        }
    }

    if receipt.Status == types.ReceiptStatusFailed {
        l.Log.Error("Proposer tx successfully published but reverted", "tx_hash", receipt.TxHash)
    } else {
        l.Log.Info("Proposer tx successfully published",
            "tx_hash", receipt.TxHash,
            "l1blocknum", output.CurrentL1.Number,
            "l1blockhash", output.CurrentL1.Hash)
    }
    return nil
}
```

### 2. DGF 트랜잭션 후보 생성

**파일**: `proposer/driver.go`
**함수**: `ProposeL2OutputDGFTxCandidate` (341-345라인)

```go
func (l *L2OutputSubmitter) ProposeL2OutputDGFTxCandidate(ctx context.Context, output source.Proposal) (txmgr.TxCandidate, error) {
    cCtx, cancel := context.WithTimeout(ctx, l.Cfg.NetworkTimeout)
    defer cancel()
    // DisputeGameFactory 컨트랙트의 ProposalTx 메서드 호출
    return l.dgfContract.ProposalTx(cCtx, l.Cfg.DisputeGameType, output.Root, output.SequenceNum)
}
```

### 3. 실제 트랜잭션 생성

**파일**: `contracts/disputegamefactory.go`
**함수**: `ProposalTx` (97-112라인)

**Output 파라미터가 트랜잭션 생성에 사용되는 과정:**
```go
func (f *DisputeGameFactory) ProposalTx(ctx context.Context, gameType uint32, outputRoot common.Hash, l2BlockNum uint64) (txmgr.TxCandidate, error) {
    // outputRoot = output.Root (L2 상태 루트)
    // l2BlockNum = output.SequenceNum (L2 블록 번호)

    // 1. 초기 보증금 조회
    result, err := f.caller.SingleCall(cCtx, rpcblock.Latest, f.contract.Call(methodInitBonds, gameType))
    initBond := result.GetBigInt(0)

    // 2. create 함수 호출을 위한 트랜잭션 생성
    // create(gameType, outputRoot, l2BlockNumBytes)
    call := f.contract.Call(methodCreateGame, gameType, outputRoot, common.BigToHash(big.NewInt(int64(l2BlockNum))).Bytes())
    candidate, err := call.ToTxCandidate()

    // 3. 초기 보증금 설정
    candidate.Value = initBond
    return candidate, err
}
```

**생성되는 트랜잭션 데이터:**
```go
// ABI 인코딩된 create 함수 호출
// create(uint32 gameType, bytes32 rootClaim, bytes extraData)
// 파라미터:
// - gameType: 4 (예: FaultDisputeGame)
// - rootClaim: output.Root (L2 상태 루트)
// - extraData: output.SequenceNum (L2 블록 번호를 32바이트로 변환)
```

## 🎯 **DisputeGameFactory.create 함수 파라미터 상세 분석**

### **Solidity 함수 시그니처:**
```solidity
function create(
    GameType _gameType,        // uint32
    Claim _rootClaim,          // bytes32
    bytes calldata _extraData  // bytes
) external payable returns (IDisputeGame proxy_)
```

### **파라미터 1: `_gameType` (uint32)**
```go
// op-proposer에서 전달되는 값
gameType := l.Cfg.DisputeGameType  // 설정에서 가져온 값 (예: 4, 5)

// Solidity에서의 처리
IDisputeGame impl = gameImpls[_gameType];  // 게임 타입별 구현체 조회
if (address(impl) == address(0)) revert NoImplementation(_gameType);
```

**게임 타입별 의미:**
- **0, 1, 2, 3**: Pre-interop 게임 타입 (**Rollup RPC 필요**)
- **4, 5**: Post-interop 게임 타입 (Supervisor RPC 필요)
- **6, 254, 255, 1337**: 기타 게임 타입

**⚠️ 중요: 게임 타입 0 사용 시**
- **DisputeGameFactory 사용**: ✅ (DisputeGameFactory.create 호출)
- **RPC 모드**: Rollup RPC (Supervisor RPC 아님)
- **ProposalSource**: `RollupProposalSource` 사용
- **Output 타입**: `eth.OutputResponse` (Super Root 아님)
- **OutputRoot**: 단일 L2 체인의 Output Root
- **코드 검증**: `preInteropGameTypes = []uint32{0, 1, 2, 3, 6, 254, 255, 1337}`

**🔍 핵심 포인트:**
- **DisputeGameFactory ≠ Supervisor RPC**
- 게임 타입 0은 DisputeGameFactory를 사용하지만 Rollup RPC로 데이터를 가져옴
- 이는 Pre-interop와 Post-interop의 차이점

### **파라미터 2: `_rootClaim` (bytes32)**
```go
// op-proposer에서 전달되는 값
rootClaim := output.Root  // Output Root 또는 Super Root

// 게임 타입 0 (Rollup RPC 모드)에서:
// output.Root = OutputResponse.OutputRoot
// = Keccak256(version + stateRoot + messagePasserStorageRoot)

// 게임 타입 4,5 (Supervisor RPC 모드)에서:
// output.Root = SuperRootResponse.SuperRoot
// = Keccak256(SuperV1.Marshal())
// = Keccak256(timestamp + [chainID, outputRoot] 쌍들)
```

**rootClaim의 의미 (게임 타입별):**
- **게임 타입 0**: 단일 L2 체인의 Output Root
  - **구성**: `Keccak256(version + stateRoot + messagePasserStorageRoot)`
  - **검증 대상**: 특정 L2 블록의 상태 루트
- **게임 타입 4,5**: 여러 L2 체인의 Super Root
  - **구성**: `Keccak256(timestamp + [chainID1, outputRoot1] + [chainID2, outputRoot2] + ...)`
  - **검증 대상**: 여러 L2 체인의 통합 상태

### **파라미터 3: `_extraData` (bytes)**
```go
// op-proposer에서 전달되는 값
extraData := common.BigToHash(big.NewInt(int64(l2BlockNum))).Bytes()
// = output.SequenceNum을 32바이트로 변환

// 게임 타입 0 (Rollup RPC 모드)에서:
// output.SequenceNum = OutputResponse.BlockRef.Number
// = L2 블록 번호

// 게임 타입 4,5 (Supervisor RPC 모드)에서:
// output.SequenceNum = SuperRootResponse.Timestamp
// = 요청된 타임스탬프
```

**extraData의 의미 (게임 타입별):**
- **게임 타입 0**: L2 블록 번호
  - **값**: `output.SequenceNum` (L2 블록 번호)
  - **32바이트**: `common.BigToHash()`로 변환된 블록 번호
  - **용도**: Dispute Game에서 참조할 L2 블록 정보
- **게임 타입 4,5**: 타임스탬프
  - **값**: `output.SequenceNum` (타임스탬프)
  - **32바이트**: `common.BigToHash()`로 변환된 타임스탬프
  - **용도**: Dispute Game에서 참조할 시간 정보

### **파라미터 4: `msg.value` (payable)**
```go
// op-proposer에서 전달되는 값
candidate.Value = initBond  // 초기 보증금

// initBond 조회 과정:
result, err := f.caller.SingleCall(cCtx, rpcblock.Latest, f.contract.Call(methodInitBonds, gameType))
initBond := result.GetBigInt(0)  // initBonds[gameType]
```

**보증금의 의미:**
- **경제적 인센티브**: 잘못된 제안 시 페널티
- **게임 타입별 차등**: `initBonds[gameType]`에서 조회
- **검증 완료 시 반환**: 올바른 제안이면 보증금 반환

### **실제 트랜잭션 생성 과정:**
```go
// 1. 초기 보증금 조회
result, err := f.caller.SingleCall(cCtx, rpcblock.Latest, f.contract.Call(methodInitBonds, gameType))
initBond := result.GetBigInt(0)

// 2. create 함수 호출 트랜잭션 생성
call := f.contract.Call(methodCreateGame, gameType, outputRoot, common.BigToHash(big.NewInt(int64(l2BlockNum))).Bytes())
candidate, err := call.ToTxCandidate()

// 3. 보증금 설정
candidate.Value = initBond

// 최종 TxCandidate:
// - To: DisputeGameFactory 주소
// - Data: ABI 인코딩된 create(gameType, rootClaim, extraData)
// - Value: initBond (보증금)
```

### **Solidity 컨트랙트에서의 처리:**
```solidity
function create(GameType _gameType, Claim _rootClaim, bytes calldata _extraData) external payable {
    // 1. 구현체 확인
    IDisputeGame impl = gameImpls[_gameType];

    // 2. 보증금 검증
    if (msg.value != initBonds[_gameType]) revert IncorrectBondAmount();

    // 3. 부모 블록 해시 수집
    bytes32 parentHash = blockhash(block.number - 1);

    // 4. 게임 컨트랙트 클론 및 초기화
    // CWIA Calldata Layout:
    // [0, 20): Game creator address
    // [20, 52): Root claim (rootClaim)
    // [52, 84): Parent block hash
    // [84, 116): Extra data (extraData)

    // 5. DisputeGameCreated 이벤트 발생
    emit DisputeGameCreated(proxy_, _gameType, _rootClaim);
}
```

### **파라미터 요약:**

| 파라미터 | 타입 | 게임 타입 0 | 게임 타입 4,5 | 의미 |
|---------|------|-------------|---------------|------|
| `_gameType` | uint32 | 0 | 4, 5 | Dispute Game 타입 |
| `_rootClaim` | bytes32 | Output Root | Super Root | 검증할 상태 루트 |
| `_extraData` | bytes | L2 블록 번호 | 타임스탬프 | 참조 정보 |
| `msg.value` | uint256 | initBond | initBond | 초기 보증금 |

**핵심 포인트:**
- **게임 타입 0**: DisputeGameFactory + Rollup RPC
  - **rootClaim**: Rollup RPC에서 생성된 Output Root
  - **extraData**: L2 블록 번호
- **게임 타입 4,5**: DisputeGameFactory + Supervisor RPC
  - **rootClaim**: Supervisor RPC에서 생성된 Super Root
  - **extraData**: 타임스탬프
- **보증금**: 게임 타입별로 다른 초기 보증금
- **결과**: 새로운 Dispute Game 컨트랙트 생성

```go
func (f *DisputeGameFactory) ProposalTx(ctx context.Context, gameType uint32, outputRoot common.Hash, l2BlockNum uint64) (txmgr.TxCandidate, error) {
    cCtx, cancel := context.WithTimeout(ctx, f.networkTimeout)
    defer cancel()

    // 1. 초기 보증금(init bond) 조회
    result, err := f.caller.SingleCall(cCtx, rpcblock.Latest, f.contract.Call(methodInitBonds, gameType))
    if err != nil {
        return txmgr.TxCandidate{}, fmt.Errorf("failed to fetch init bond: %w", err)
    }
    initBond := result.GetBigInt(0)

    // 2. createGame 트랜잭션 생성
    call := f.contract.Call(methodCreateGame, gameType, outputRoot, common.BigToHash(big.NewInt(int64(l2BlockNum))).Bytes())
    candidate, err := call.ToTxCandidate()
    if err != nil {
        return txmgr.TxCandidate{}, err
    }

    // 3. 초기 보증금 설정
    candidate.Value = initBond
    return candidate, err
}
```

## 🔄 전체 제안 제출 흐름

### 0. Output 생성 과정 (Proposal 데이터 추출)

**Output이 생성되는 과정:**

#### **Rollup RPC 모드 (L2OutputOracle용)**
- --rollup-rpc 사용
- optimism_outputAtBlock 호출
- OutputRoot: L2 상태 루트 (Keccak256 해시)
- SequenceNum: L2 블록 번호
- Legacy 데이터: 포함 (HeadL1, SafeL2, FinalizedL2 등)

```go
// 1. FetchOutput 호출
func (l *L2OutputSubmitter) FetchOutput(ctx context.Context, block uint64) (source.Proposal, error) {
    output, err := l.ProposalSource.ProposalAtSequenceNum(ctx, block)
    // ...
}

// 2. RollupProposalSource.ProposalAtSequenceNum
func (r *RollupProposalSource) ProposalAtSequenceNum(ctx context.Context, blockNum uint64) (Proposal, error) {
    client, err := r.provider.RollupClient(ctx)
    output, err := client.OutputAtBlock(ctx, blockNum)  // RPC 호출

    return Proposal{
        Root:        common.Hash(output.OutputRoot),     // L2 상태 루트
        SequenceNum: output.BlockRef.Number,             // L2 블록 번호
        CurrentL1:   output.Status.CurrentL1.ID(),       // 현재 L1 블록
        Legacy: LegacyProposalData{
            HeadL1:      output.Status.HeadL1,
            SafeL2:      output.Status.SafeL2,
            FinalizedL2: output.Status.FinalizedL2,
            BlockRef:    output.BlockRef,
        },
    }, nil
}
```

**RPC 호출 체인:**
```go
// op-service/sources/rollupclient.go
func (r *RollupClient) OutputAtBlock(ctx context.Context, blockNum uint64) (*eth.OutputResponse, error) {
    var output *eth.OutputResponse
    err := r.rpc.CallContext(ctx, &output, "optimism_outputAtBlock", hexutil.Uint64(blockNum))
    return output, err
}
```

**op-node의 optimism_outputAtBlock 구현:**
```go
// op-node/node/api.go
func (n *nodeAPI) OutputAtBlock(ctx context.Context, number hexutil.Uint64) (*eth.OutputResponse, error) {
    ref, status, err := n.dr.BlockRefWithStatus(ctx, uint64(number))

    // L2 블록의 OutputV0 생성
    output, err := n.client.OutputV0AtBlock(ctx, ref.Hash)

    return &eth.OutputResponse{
        Version:               output.Version(),                    // "0x0000..."
        OutputRoot:            eth.OutputRoot(output),              // Keccak256(마샬된 데이터)
        BlockRef:              ref,                                 // L2 블록 참조
        WithdrawalStorageRoot: common.Hash(output.MessagePasserStorageRoot),
        StateRoot:             common.Hash(output.StateRoot),       // L2 상태 루트
        Status:                status,                              // 동기화 상태
    }, nil
}
```

**OutputV0 구조체:**
```go
// op-service/eth/output.go
type OutputV0 struct {
    StateRoot                Bytes32     // L2 상태 루트
    MessagePasserStorageRoot Bytes32     // 출금 컨트랙트 스토리지 루트
    BlockHash                common.Hash // L2 블록 해시
}

// OutputRoot 계산
func OutputRoot(output Output) Bytes32 {
    marshaled := output.Marshal()  // [version(32) + stateRoot(32) + messagePasserStorageRoot(32)]
    return Bytes32(crypto.Keccak256Hash(marshaled))  // Keccak256 해시
}
```

#### **DisputeGameFactory 모드 (게임 타입별 RPC 분기)**

**게임 타입 0 (Pre-interop):**
- **RPC**: Rollup RPC (--rollup-rpc 사용)
- **ProposalSource**: RollupProposalSource
- **호출**: OutputAtBlock
- **Root**: Output Root (단일 L2 체인)
- **SequenceNum**: L2 블록 번호
- **Legacy 데이터**: 있음 (L2OutputOracle 호환)

**게임 타입 4,5 (Post-interop):**
- **RPC**: Supervisor RPC (--supervisor-rpcs 사용)
- **ProposalSource**: SupervisorProposalSource
- **호출**: SuperRootAtTimestamp
- **Root**: Super Root (여러 L2 체인 통합)
- **SequenceNum**: 타임스탬프
- **Legacy 데이터**: 없음 (빈 구조체)

**공통점:**
- 둘 다 DisputeGameFactory의 create 함수를 호출
- 둘 다 fault-proof 시스템의 새로운 아키텍처
- 게임 타입에 따라 다른 RPC와 데이터 소스 사용

```go
// SupervisorProposalSource.ProposalAtSequenceNum
func (s *SupervisorProposalSource) ProposalAtSequenceNum(ctx context.Context, timestamp uint64) (Proposal, error) {
    for i, client := range s.clients {
        output, err := client.SuperRootAtTimestamp(ctx, hexutil.Uint64(timestamp))
        if err != nil {
            continue
        }
        return Proposal{
            Root:        common.Hash(output.SuperRoot),  // Super Root (타임스탬프 기반)
            SequenceNum: output.Timestamp,               // 타임스탬프
            CurrentL1:   output.CrossSafeDerivedFrom,    // L1 블록 참조
            Legacy: LegacyProposalData{},                // Supervisor는 Legacy 데이터 없음
        }, nil
    }
}
```

**SuperRootAtTimestamp 함수 상세 분석:**

```go
// op-service/sources/supervisor_client.go
func (cl *SupervisorClient) SuperRootAtTimestamp(ctx context.Context, timestamp hexutil.Uint64) (result eth.SuperRootResponse, err error) {
    // RPC 호출: supervisor_superRootAtTimestamp
    err = cl.client.CallContext(ctx, &result, "supervisor_superRootAtTimestamp", timestamp)
    if isNotFound(err) {
        err = fmt.Errorf("%w: %v", ethereum.NotFound, err.Error())
        return result, err
    }
    return result, err
}
```

**op-supervisor의 supervisor_superRootAtTimestamp 구현:**

```go
// op-supervisor/supervisor/backend/backend.go
func (su *SupervisorBackend) SuperRootAtTimestamp(ctx context.Context, timestamp hexutil.Uint64) (eth.SuperRootResponse, error) {
    // 1. 모든 체인 정보 수집
    chains := su.cfgSet.Chains()
    chainInfos := make([]eth.ChainRootInfo, len(chains))
    superRootChains := make([]eth.ChainIDAndOutput, len(chains))

    var crossSafeSource eth.BlockID

    // 2. 각 체인별로 OutputV0 생성
    for i, chainID := range chains {
        src, ok := su.syncSources.Get(chainID)

        // 3. 해당 타임스탬프의 OutputV0 가져오기
        output, err := src.OutputV0AtTimestamp(ctx, uint64(timestamp))
        pending, err := src.PendingOutputV0AtTimestamp(ctx, uint64(timestamp))

        // 4. OutputRoot 계산
        canonicalRoot := eth.OutputRoot(output)

        chainInfos[i] = eth.ChainRootInfo{
            ChainID:   chainID,
            Canonical: canonicalRoot,
            Pending:   pending.Marshal(),
        }
        superRootChains[i] = eth.ChainIDAndOutput{ChainID: chainID, Output: canonicalRoot}

        // 5. L1 소스 블록 정보 수집
        ref, err := src.L2BlockRefByTimestamp(ctx, uint64(timestamp))
        source, err := su.chainDBs.CrossDerivedToSource(chainID, ref.ID())

        if crossSafeSource.Number == 0 || crossSafeSource.Number < source.Number {
            crossSafeSource = source.ID()
        }
    }

    // 6. SuperV1 생성
    super := eth.SuperV1{
        Timestamp: uint64(timestamp),
        Chains:    superRootChains,
    }

    // 7. SuperRoot 계산 (Keccak256 해시)
    superRoot := eth.SuperRoot(&super)

    return eth.SuperRootResponse{
        CrossSafeDerivedFrom: crossSafeSource,
        Timestamp:            uint64(timestamp),
        SuperRoot:            superRoot,
        Version:              super.Version(),
        Chains:               chainInfos,
    }, nil
}
```

**SuperRootResponse 구조체:**
```go
// op-service/eth/super_root.go
type SuperRootResponse struct {
    CrossSafeDerivedFrom BlockID        // L1 소스 블록
    Timestamp            uint64         // 요청된 타임스탬프
    SuperRoot            Bytes32        // Super Root (Keccak256 해시)
    Version              byte           // 버전 (SuperRootVersionV1)
    Chains               []ChainRootInfo // 각 체인의 루트 정보
}

type SuperV1 struct {
    Timestamp uint64                // 타임스탬프
    Chains    []ChainIDAndOutput    // [체인ID, OutputRoot] 쌍들
}

// SuperRoot 계산
func SuperRoot(super Super) Bytes32 {
    marshaled := super.Marshal()  // SuperV1 마샬링
    return Bytes32(crypto.Keccak256Hash(marshaled))  // Keccak256 해시
}
```

**Output 데이터 구조:**
```go
type Proposal struct {
    Root        common.Hash  // 제안할 루트 (L2OutputRoot 또는 SuperRoot)
    SequenceNum uint64       // 시퀀스 번호 (L2 블록 번호 또는 타임스탬프)
    CurrentL1   eth.BlockID  // 현재 L1 블록 정보

    Legacy LegacyProposalData  // Rollup RPC에서만 사용
}

type LegacyProposalData struct {
    HeadL1      eth.L1BlockRef  // L1 헤드
    SafeL2      eth.L2BlockRef  // L2 Safe 블록
    FinalizedL2 eth.L2BlockRef  // L2 Finalized 블록
    BlockRef    eth.L2BlockRef  // L2 블록 참조
}
```

### 1. 메인 루프에서 모드 분기

**파일**: `proposer/driver.go`
**함수**: `loop` (420-460라인)

**SupervisorProposalSource.ProposalAtSequenceNum 호출 체인:**

```go
// 1. 메인 루프 시작 (PollInterval마다 실행, 기본 12초)
func (l *L2OutputSubmitter) loop() {
    ticker := time.NewTicker(l.Cfg.PollInterval)  // 기본 12초
    for {
        select {
        case <-ticker.C:
            // 2. DGF 모드 확인
            if l.dgfContract == nil {
                proposal, shouldPropose, err = l.FetchL2OOOutput(ctx)
            } else {
                proposal, shouldPropose, err = l.FetchDGFOutput(ctx)  // DGF 모드
            }
        }
    }
}

// 3. FetchDGFOutput 호출
func (l *L2OutputSubmitter) FetchDGFOutput(ctx context.Context) (source.Proposal, bool, error) {
    // 제안 조건 확인 후...
    currentBlockNumber, err := l.FetchCurrentBlockNumber(ctx)

    // 4. FetchOutput 호출
    output, err := l.FetchOutput(ctx, currentBlockNumber)
    // ...
}

// 5. FetchOutput에서 ProposalSource.ProposalAtSequenceNum 호출
func (l *L2OutputSubmitter) FetchOutput(ctx context.Context, block uint64) (source.Proposal, error) {
    output, err := l.ProposalSource.ProposalAtSequenceNum(ctx, block)  // 여기서 호출!
    // ...
}

// 6. SupervisorProposalSource.ProposalAtSequenceNum 실행
func (s *SupervisorProposalSource) ProposalAtSequenceNum(ctx context.Context, timestamp uint64) (Proposal, error) {
    for i, client := range s.clients {
        output, err := client.SuperRootAtTimestamp(ctx, hexutil.Uint64(timestamp))
        // ...
    }
}
```

**호출 시점:**
- **주기**: `PollInterval`마다 (기본 12초)
- **조건**: DGF 모드 (`l.dgfContract != nil`)
- **트리거**: 제안 간격이 지났고, 출력 루트가 변경된 경우

```go
// L2OO 또는 DGF 모드에 따라 제안 가져오기
var proposal source.Proposal
var shouldPropose bool
var err error

if l.dgfContract == nil {
    proposal, shouldPropose, err = l.FetchL2OOOutput(ctx)
} else {
    proposal, shouldPropose, err = l.FetchDGFOutput(ctx)
}

if err != nil {
    l.Log.Warn("Error getting proposal", "err", err)
    continue
} else if !shouldPropose {
    continue
}

l.proposeOutput(ctx, proposal)
```

### 2. DGF 모드 제안 가져오기

**파일**: `proposer/driver.go`
**함수**: `FetchDGFOutput` (262-298라인)

**Output이 DGF 모드에서 사용되는 과정:**
```go
// 1. 현재 L2 헤드 가져오기
currentBlockNumber, err := l.FetchCurrentBlockNumber(ctx)

// 2. 해당 블록의 Output 생성 (위의 Output 생성 과정 참조)
output, err := l.FetchOutput(ctx, currentBlockNumber)
// output.Root = L2 상태 루트 (Keccak256 해시)
// output.SequenceNum = L2 블록 번호
// output.CurrentL1 = 현재 L1 블록 정보

// 3. 이 output이 ProposeL2OutputDGFTxCandidate로 전달됨
candidate, err := l.ProposeL2OutputDGFTxCandidate(ctx, output)
```

```go
func (l *L2OutputSubmitter) FetchDGFOutput(ctx context.Context) (source.Proposal, bool, error) {
    // 1. 최근 제안 확인
    cutoff := time.Now().Add(-l.Cfg.ProposalInterval)
    proposedRecently, proposalTime, claim, err := l.dgfContract.HasProposedSince(
        ctx, l.Txmgr.From(), cutoff, l.Cfg.DisputeGameType)
    if err != nil {
        return source.Proposal{}, false, fmt.Errorf("could not check for recent proposal: %w", err)
    }

    if proposedRecently {
        l.Log.Debug("Duration since last game not past proposal interval", "duration", time.Since(proposalTime))
        return source.Proposal{}, false, nil
    }

    // 2. 현재 L2 헤드 가져오기
    currentBlockNumber, err := l.FetchCurrentBlockNumber(ctx)
    if err != nil {
        return source.Proposal{}, false, fmt.Errorf("could not fetch current block number: %w", err)
    }

    if currentBlockNumber == 0 {
        l.Log.Info("Skipping proposal for genesis block")
        return source.Proposal{}, false, nil
    }

    // 3. 출력 가져오기
    output, err := l.FetchOutput(ctx, currentBlockNumber)
    if err != nil {
        return source.Proposal{}, false, fmt.Errorf("could not fetch output at current block number %d: %w", currentBlockNumber, err)
    }

    // 4. 출력 루트 변경 확인
    if claim == output.Root {
        l.Log.Debug("Skipping proposal: output root unchanged since last proposed game",
            "last_proposed_root", claim, "output_root", output.Root)
        return source.Proposal{}, false, nil
    }

    l.Log.Info("No proposals found for at least proposal interval, submitting proposal now",
        "proposalInterval", l.Cfg.ProposalInterval)

    return output, true, nil
}
```

### 3. 제안 출력 처리

**파일**: `proposer/driver.go`
**함수**: `proposeOutput` (481-503라인)

```go
func (l *L2OutputSubmitter) proposeOutput(ctx context.Context, output source.Proposal) {
    cCtx, cancel := context.WithTimeout(ctx, 10*time.Minute)
    defer cancel()

    if err := l.sendTransaction(cCtx, output); err != nil {
        logCtx := []interface{}{
            "err", err,
            "l1blocknum", output.CurrentL1.Number,
            "l1blockhash", output.CurrentL1.Hash,
        }
        // Add legacy data only if available
        if output.Legacy.HeadL1 != (eth.L1BlockRef{}) {
            logCtx = append(logCtx, "l1head", output.Legacy.HeadL1.Number)
        }
        l.Log.Error("Failed to send proposal transaction", logCtx...)
        return
    }
    l.Metr.RecordL2Proposal(output.SequenceNum)
    if output.Legacy.BlockRef != (eth.L2BlockRef{}) {
        // Record legacy metrics when available
        l.Metr.RecordL2BlocksProposed(output.Legacy.BlockRef)
    }
}
```

## 🎯 핵심 차이점: L2OO vs DGF 모드

### L2OutputOracle 모드
```go
// 직접 트랜잭션 데이터 생성
data, err := l.ProposeL2OutputTxData(output)
receipt, err = l.Txmgr.Send(ctx, txmgr.TxCandidate{
    TxData:   data,
    To:       l.Cfg.L2OutputOracleAddr,
    GasLimit: 0,
})
```

### DisputeGameFactory 모드
```go
// 컨트랙트를 통해 트랜잭션 후보 생성
candidate, err := l.ProposeL2OutputDGFTxCandidate(ctx, output)
receipt, err = l.Txmgr.Send(ctx, candidate)
```

## 🔍 DisputeGameFactory 컨트랙트 상호작용

### 1. HasProposedSince 메서드

**파일**: `contracts/disputegamefactory.go`
**함수**: `HasProposedSince` (69-95라인)

```go
func (f *DisputeGameFactory) HasProposedSince(ctx context.Context, proposer common.Address, cutoff time.Time, gameType uint32) (bool, time.Time, common.Hash, error) {
    gameCount, err := f.gameCount(ctx)
    if err != nil {
        return false, time.Time{}, common.Hash{}, fmt.Errorf("failed to get dispute game count: %w", err)
    }
    if gameCount == 0 {
        return false, time.Time{}, common.Hash{}, nil
    }

    // 최신 게임부터 역순으로 검색
    for idx := gameCount - 1; ; idx-- {
        game, err := f.gameAtIndex(ctx, idx)
        if err != nil {
            return false, time.Time{}, common.Hash{}, fmt.Errorf("failed to get dispute game %d: %w", idx, err)
        }

        if game.Timestamp.Before(cutoff) {
            // 컷오프 시간 이전 게임에 도달
            return false, time.Time{}, common.Hash{}, nil
        }

        if game.GameType == gameType && game.Proposer == proposer {
            // 매칭되는 제안 발견
            return true, game.Timestamp, game.Claim, nil
        }

        if idx == 0 {
            // 모든 게임을 확인했지만 매칭되지 않음
            return false, time.Time{}, common.Hash{}, nil
        }
    }
}
```

### 2. 게임 메타데이터 조회

**파일**: `contracts/disputegamefactory.go`
**함수**: `gameAtIndex` (124-153라인)

```go
func (f *DisputeGameFactory) gameAtIndex(ctx context.Context, idx uint64) (gameMetadata, error) {
    cCtx, cancel := context.WithTimeout(ctx, f.networkTimeout)
    defer cancel()

    // 게임 기본 정보 조회
    result, err := f.caller.SingleCall(cCtx, rpcblock.Latest, f.contract.Call(methodGameAtIndex, new(big.Int).SetUint64(idx)))
    if err != nil {
        return gameMetadata{}, fmt.Errorf("failed to load game %v: %w", idx, err)
    }

    gameType := result.GetUint32(0)
    timestamp := result.GetUint64(1)
    address := result.GetAddress(2)

    // 게임 컨트랙트에서 클레임 정보 조회
    gameContract := batching.NewBoundContract(f.gameABI, address)
    cCtx, cancel = context.WithTimeout(ctx, f.networkTimeout)
    defer cancel()
    result, err = f.caller.SingleCall(cCtx, rpcblock.Latest, gameContract.Call(methodClaim, big.NewInt(0)))
    if err != nil {
        return gameMetadata{}, fmt.Errorf("failed to load root claim of game %v: %w", idx, err)
    }

    // 클레임 데이터에서 proposer와 claim 추출
    claimant := result.GetAddress(2)  // proposer
    claim := result.GetHash(4)        // output root

    return gameMetadata{
        GameType:  gameType,
        Timestamp: time.Unix(int64(timestamp), 0),
        Address:   address,
        Proposer:  claimant,
        Claim:     claim,
    }, nil
}
```

## 📋 트랜잭션 생성 과정

### 1. 초기 보증금 조회
```go
// methodInitBonds = "initBonds"
result, err := f.caller.SingleCall(cCtx, rpcblock.Latest, f.contract.Call(methodInitBonds, gameType))
initBond := result.GetBigInt(0)
```

### 2. createGame 트랜잭션 생성
```go
// methodCreateGame = "create"
call := f.contract.Call(methodCreateGame, gameType, outputRoot, common.BigToHash(big.NewInt(int64(l2BlockNum))).Bytes())
candidate, err := call.ToTxCandidate()
```

### 3. 보증금 설정
```go
candidate.Value = initBond
```

## 🔧 설정 요구사항

### DGF 모드 필수 설정
- `--game-factory-address`: DisputeGameFactory 컨트랙트 주소
- `--game-type`: Dispute Game 타입 (예: 4, 5)
- `--proposal-interval`: 제안 간격 (예: 1h)

### 게임 타입별 RPC 요구사항
```go
// preInteropGameTypes: rollup RPC 필요
preInteropGameTypes = []uint32{0, 1, 2, 3, 6, 254, 255, 1337}

// postInteropGameTypes: supervisor RPC 필요
postInteropGameTypes = []uint32{4, 5}
```

## 🚀 실행 예시

### Supervisor RPC 사용 (게임 타입 4, 5)
```bash
go run ./op-proposer/cmd \
    --l1-eth-rpc http://l1:8545 \
    --supervisor-rpcs http://supervisor:8545 \
    --game-factory-address 0x... \
    --game-type 4 \
    --proposal-interval 1h \
    --poll-interval 12s
```

### Rollup RPC 사용 (게임 타입 0, 1, 2, 3)
```bash
go run ./op-proposer/cmd \
    --l1-eth-rpc http://l1:8545 \
    --rollup-rpc http://op-node:8545 \
    --game-factory-address 0x... \
    --game-type 0 \
    --proposal-interval 1h \
    --poll-interval 12s
```

## 🔒 보안 고려사항

### 1. 제안 간격 보장
- `ProposalInterval` 설정으로 과도한 제안 방지
- `HasProposedSince`로 최근 제안 확인

### 2. 출력 루트 변경 확인
- 동일한 출력 루트에 대한 중복 제안 방지
- `claim == output.Root` 체크

### 3. 초기 보증금
- 각 게임 타입별로 다른 초기 보증금 요구
- 잘못된 제안 시 보증금 몰수 위험

## 📊 로깅 및 모니터링

### 주요 로그 메시지
```go
// 제안 시작
l.Log.Info("Proposing output root", "output", output.Root, "block", output.SequenceNum)

// 제안 간격 미달
l.Log.Debug("Duration since last game not past proposal interval", "duration", time.Since(proposalTime))

// 출력 루트 미변경
l.Log.Debug("Skipping proposal: output root unchanged since last proposed game",
    "last_proposed_root", claim, "output_root", output.Root)

// 제안 제출
l.Log.Info("No proposals found for at least proposal interval, submitting proposal now",
    "proposalInterval", l.Cfg.ProposalInterval)

// 트랜잭션 성공
l.Log.Info("Proposer tx successfully published",
    "tx_hash", receipt.TxHash,
    "l1blocknum", output.CurrentL1.Number,
    "l1blockhash", output.CurrentL1.Hash)
```

### 메트릭스 기록
```go
l.Metr.RecordL2Proposal(output.SequenceNum)
l.Metr.RecordL2BlocksProposed(output.Legacy.BlockRef)
```

## 🎯 요약

DisputeGameFactory 모드의 제안 제출은 다음과 같은 단계로 이루어집니다:

1. **Output 생성**: L2 블록에서 상태 루트 추출
   - Rollup RPC: `optimism_outputAtBlock` 호출로 OutputV0 생성
   - Supervisor RPC: `SuperRootAtTimestamp` 호출로 SuperRoot 생성
   - OutputRoot = Keccak256(version + stateRoot + messagePasserStorageRoot)

2. **제안 조건 확인**: 제안 간격, 출력 루트 변경 확인

3. **트랜잭션 생성**:
   - 초기 보증금 조회 (`initBonds[gameType]`)
   - `create(gameType, outputRoot, l2BlockNum)` 트랜잭션 생성
   - 보증금을 포함한 완전한 TxCandidate 반환

4. **트랜잭션 전송**: TxManager를 통한 L1 트랜잭션 전송

5. **결과 처리**: 성공/실패 로깅 및 메트릭스 기록

**핵심 차이점:**
- **L2OutputOracle**: `proposeL2Output` 함수 호출 (단순 제안)
- **DisputeGameFactory**: `create` 함수 호출 (새로운 Dispute Game 생성)

이 과정은 L2OutputOracle 모드보다 복잡하지만, fault-proof 시스템의 검증 가능한 제안을 제공합니다.

---

이 문서는 op-proposer의 DisputeGameFactory 모드에서 제안 제출 과정을 상세히 분석한 것입니다. 실제 코드 위치와 함께 각 단계의 동작을 이해할 수 있도록 구성되었습니다.
