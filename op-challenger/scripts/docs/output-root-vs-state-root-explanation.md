# Output Root vs State Root 상세 설명

## 개요

Optimism fault-proof 시스템에서 **Output Root**와 **State Root**는 서로 다른 개념이며, 이 차이점을 정확히 이해하는 것이 중요합니다. 특히 dispute game 분석 시 혼동하기 쉬운 부분입니다.

**핵심 요약:**
- **State Root**: L2 블록의 단일 상태 해시 (32바이트)
- **Output Root**: 여러 해시 값들의 복합 해시 (32바이트)
- **DisputeGameFactory**에서 프로포저가 제출하는 `rootClaim`은 **Output Root**입니다

## 🎯 핵심 차이점

### State Root
```
- 정의: L2 블록의 account state를 나타내는 Merkle Patricia Tree의 루트 해시
- 크기: 32바이트 (bytes32)
- 용도: L2 블록의 상태 검증
- 예시: 0x5589280545fddd46ef2a0b4792f9118bdcb1d44ec82cdbeeb592d582a24eb57d
```

### Output Root
```
- 정의: 여러 해시 값들을 조합한 복합 해시
- 크기: 32바이트 (bytes32)
- 용도: Fault proof system에서 L2 상태 전체를 검증
- 예시: 0xf11ed3e5a8556be57fc3edf178b9809264bf15ac6dd31bef857cd02f867da77a
```

## 🔧 Output Root 구성 요소

### OutputV0 구조체 (op-service/eth/output.go)

```go
type OutputV0 struct {
    StateRoot                Bytes32     // L2 상태 루트
    MessagePasserStorageRoot Bytes32     // 출금 컨트랙트 스토리지 루트
    BlockHash                common.Hash // L2 블록 해시
}
```

### Output Root 계산 공식

```go
// 1. OutputV0 마샬링 (96바이트)
marshaled := [version(32) + stateRoot(32) + messagePasserStorageRoot(32)]

// 2. Keccak256 해시 적용
OutputRoot = Keccak256(marshaled)
```

**상세 과정:**
1. **Version**: `0x0000...0000` (32바이트, 현재는 모두 0)
2. **StateRoot**: L2 블록의 상태 루트 (32바이트)
3. **MessagePasserStorageRoot**: L2ToL1MessagePasser 컨트랙트의 스토리지 루트 (32바이트)
4. **총 96바이트**를 연결하여 Keccak256 해시 적용

## 🚀 실제 코드에서 확인

### op-node에서 Output Root 생성

**파일**: `op-node/node/api.go`
```go
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

### Output Root 계산 함수

**파일**: `op-service/eth/output.go`
```go
func OutputRoot(output Output) Bytes32 {
    marshaled := output.Marshal()  // [version(32) + stateRoot(32) + messagePasserStorageRoot(32)]
    return Bytes32(crypto.Keccak256Hash(marshaled))  // Keccak256 해시
}

func (o OutputV0) Marshal() []byte {
    var buf [96]byte
    copy(buf[0:32], o.Version().Bytes())              // Version (32바이트)
    copy(buf[32:64], o.StateRoot[:])                  // StateRoot (32바이트)
    copy(buf[64:96], o.MessagePasserStorageRoot[:])   // MessagePasserStorageRoot (32바이트)
    return buf[:]
}
```

## 📊 DisputeGameFactory에서의 사용

### 프로포저가 제출하는 rootClaim

**파일**: `proposer/driver.go`
```go
func (l *L2OutputSubmitter) ProposeL2OutputDGFTxCandidate(ctx context.Context, output source.Proposal) (txmgr.TxCandidate, error) {
    // output.Root = Output Root (복합 해시)
    // output.SequenceNum = L2 블록 번호
    return l.dgfContract.ProposalTx(cCtx, l.Cfg.DisputeGameType, output.Root, output.SequenceNum)
}
```

### DisputeGameFactory.create 함수 파라미터

```solidity
function create(
    GameType _gameType,        // 게임 타입 (예: 0 = CANNON)
    Claim _rootClaim,          // ← 여기가 Output Root!
    bytes calldata _extraData  // L2 블록 번호
) external payable returns (IDisputeGame proxy_)
```

**중요:** `_rootClaim` 파라미터는 **Output Root**이지 State Root가 아닙니다!

## 🔍 실제 예시 분석

### 게임 0x55567A6D1E39b24dA0bd13F50d4f9D780f113791 사례

**이전 의문:**
- 프로포저 제출값: `0xf11ed3e5a8556be57fc3edf178b9809264bf15ac6dd31bef857cd02f867da77a`
- L2 블록 12 State Root: `0x5589280545fddd46ef2a0b4792f9118bdcb1d44ec82cdbeeb592d582a24eb57d`
- "왜 다르지?"

**정답:**
- 프로포저 제출값은 **Output Root** (복합 해시)
- L2 블록 State Root는 Output Root의 **구성 요소 중 하나**
- 둘이 다른 것이 **정상**입니다!

### 검증 과정

**op-node RPC로 확인:**
```bash
# optimism_outputAtBlock 호출
curl -X POST http://127.0.0.1:53046 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"optimism_outputAtBlock","params":["0xc"],"id":1}'

# 응답에서 outputRoot 확인
"outputRoot": "0xf11ed3e5a8556be57fc3edf178b9809264bf15ac6dd31bef857cd02f867da77a"  # ← 프로포저 제출값과 일치!
```

## 🎯 게임 타입별 차이점

### 게임 타입 0 (Pre-interop)
```
- RPC: Rollup RPC (optimism_outputAtBlock)
- rootClaim: Output Root (단일 L2 체인)
- 구성: version + stateRoot + messagePasserStorageRoot
- 용도: 특정 L2 블록의 상태 검증
```

### 게임 타입 4,5 (Post-interop)
```
- RPC: Supervisor RPC (supervisor_superRootAtTimestamp)
- rootClaim: Super Root (여러 L2 체인 통합)
- 구성: Keccak256(timestamp + [chainID, outputRoot] 쌍들)
- 용도: 여러 L2 체인의 통합 상태 검증
```

## ⚠️ 일반적인 혼동 사례

### 혼동 1: "프로포저가 잘못된 State Root 제출"
```
❌ 잘못된 생각: rootClaim이 State Root와 다르므로 문제가 있다
✅ 올바른 이해: rootClaim은 애초에 Output Root이므로 State Root와 달라야 정상
```

### 혼동 2: "블록이 불변인데 왜 해시가 다르지?"
```
❌ 잘못된 생각: 블록은 불변이므로 모든 해시가 같아야 한다
✅ 올바른 이해: State Root는 불변이지만, Output Root는 다른 요소들도 포함하는 복합 해시
```

### 혼동 3: "체인 재구성(reorg)이 발생했나?"
```
❌ 잘못된 생각: 해시가 다르니까 reorg가 발생했을 것이다
✅ 올바른 이해: 애초에 다른 종류의 해시이므로 reorg와 무관
```

## 🛠️ 디버깅 가이드

### Output Root 검증 방법

1. **op-node RPC 호출**
   ```bash
   curl -X POST http://127.0.0.1:53046 \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","method":"optimism_outputAtBlock","params":["0x' + BLOCK_HEX + '"],"id":1}'
   ```

2. **응답 분석**
   ```json
   {
     "outputRoot": "0x...",      # ← 이것이 프로포저가 제출해야 할 값
     "stateRoot": "0x...",       # ← L2 블록의 실제 State Root
     "withdrawalStorageRoot": "0x...",
     "blockRef": {...}
   }
   ```

3. **DisputeGame rootClaim과 비교**
   ```bash
   # 게임 컨트랙트에서 rootClaim 조회
   cast call GAME_ADDRESS "rootClaim()(bytes32)" --rpc-url L1_RPC

   # outputRoot와 일치하는지 확인
   ```

### 수동 계산으로 검증

```javascript
// OutputV0 구성 요소 준비 (각각 32바이트)
const version = "0x0000000000000000000000000000000000000000000000000000000000000000";
const stateRoot = "0x5589280545fddd46ef2a0b4792f9118bdcb1d44ec82cdbeeb592d582a24eb57d";
const messagePasserStorageRoot = "0x..."; // L2ToL1MessagePasser 스토리지 루트

// 96바이트로 연결
const marshaled = version + stateRoot.slice(2) + messagePasserStorageRoot.slice(2);

// Keccak256 해시 계산
const outputRoot = ethers.utils.keccak256("0x" + marshaled);
```

## 📚 관련 문서

- **[op-proposer-analysis.md](op-proposer-analysis.md)**: op-proposer 전체 구조
- **[op-proposer-dgf-proposal-flow.md](op-proposer-dgf-proposal-flow.md)**: DGF 모드 제안 제출 흐름
- **[post-deployment-verification-guide.md](post-deployment-verification-guide.md)**: 배포 후 검증 가이드

## 💡 핵심 요약

1. **Output Root ≠ State Root**: 둘은 서로 다른 개념
2. **프로포저 제출값**: DisputeGameFactory의 rootClaim은 Output Root
3. **정상 동작**: Output Root와 State Root가 다른 것이 맞음
4. **검증 방법**: op-node RPC의 `optimism_outputAtBlock` 사용
5. **디버깅**: 항상 Output Root 관점에서 분석

**기억하세요**: Dispute game 분석 시 **Output Root 기준**으로 생각해야 합니다!

---

*이 문서는 Optimism fault-proof 시스템의 Output Root vs State Root 개념 차이를 명확히 설명하기 위해 작성되었습니다.*