# Asterisc Blob Preimage Bug 수정

## 문제 요약

`TestOutputAsteriscStepWithPreimage_existingPreimage` 테스트가 `WaitForCounterClaim`에서 hang되는 버그를 발견했습니다.

### 근본 원인

**L1BlockRef의 Time 필드 불일치 문제**

- op-program이 blob을 요청할 때 사용하는 L1BlockRef가 **불일치하는 필드**를 가지고 있음
  - `Hash`: L1 block #4 (0xd6825fbd...) ✓ 올바름
  - `Time`: 1763648015 (L1 block #6의 timestamp) ✗ 잘못됨
  - **실제 L1 block #4의 timestamp**: 1763648011

### 결과

1. Blob이 L1 block #4에 포함되어 timestamp **1763648011**로 FakeBeacon에 저장됨
2. op-program이 blob hint를 생성할 때 timestamp **1763648015**를 사용함
3. **4초 차이**(2 블록)로 인해 BlobStore에서 blob을 찾을 수 없음!
4. Challenger가 trace를 생성하지 못하고 WaitForCounterClaim에서 무한 대기

## 상세 분석

### Blob 저장 과정
```
L1 Sequencer (job.go:190)
└─> slot = (ExecutionPayload.Timestamp - Genesis.Time) / blockTime
└─> FakeBeacon.StoreBlobsBundle(slot, bundle)
    └─> slotTimestamp = slot * blockTime + genesisTime  (blobs.go:167)
    └─> BlobStore.StoreBlob(slotTimestamp, hash, blob)
```

L1 block #4의 ExecutionPayload.Timestamp = **1763648011**로 blob 저장됨

### Blob 조회 과정
```
op-program/client derivation
└─> BlobFetcher.GetBlobs(ctx, L1BlockRef, hashes)  (blob_fetcher.go:29)
    └─> PreimageOracle.GetBlob(ref, blobHash)  (oracle.go:102)
        └─> blob hint 생성: ref.Time 사용  (oracle.go:106)

Prefetcher (host)
└─> blob hint 처리  (prefetcher.go:326)
    └─> refTimestamp = hint에서 추출한 timestamp
    └─> GetBlobSidecars(L1BlockRef{Time: refTimestamp}, ...)  (prefetcher.go:334)
        └─> BlobStore.GetBlobs(refTimestamp)  (blobs.go:35)
            └─> 키가 맞지 않아 NotFound!
```

### 코드 추적 결과

**L1BlockRef 구성:**
- `op-node/rollup/derive/l1_retrieval.go:51-57`에서 NextL1Block() 호출
- `eth.InfoToL1BlockRef()` 함수가 BlockInfo에서 모든 필드 복사
- **어디선가 BlockInfo의 Time 필드가 잘못 설정됨** (정확한 위치 미확인)

**Blob hint 생성:**
- `op-program/client/l1/oracle.go:106`에서 `ref.Time` 사용
- **여기서 잘못된 timestamp가 hint에 포함됨**

## 수정 사항

### 파일: `op-program/client/l1/oracle.go`

**변경 전:**
```go
func (p *PreimageOracle) GetBlob(ref eth.L1BlockRef, blobHash eth.IndexedBlobHash) *eth.Blob {
    // Send a hint for the blob commitment & blob field elements.
    blobReqMeta := make([]byte, 16)
    binary.BigEndian.PutUint64(blobReqMeta[0:8], blobHash.Index)
    binary.BigEndian.PutUint64(blobReqMeta[8:16], ref.Time)  // ❌ 잘못된 timestamp 사용
    p.hint.Hint(BlobHint(append(blobHash.Hash[:], blobReqMeta...)))
    // ...
}
```

**변경 후:**
```go
func (p *PreimageOracle) GetBlob(ref eth.L1BlockRef, blobHash eth.IndexedBlobHash) *eth.Blob {
    // Fetch the actual block header to get the correct timestamp.
    // The ref.Time may be incorrect due to how L1BlockRef is constructed in some scenarios.
    header := p.headerByBlockHash(ref.Hash)
    actualTimestamp := header.Time

    // Send a hint for the blob commitment & blob field elements.
    blobReqMeta := make([]byte, 16)
    binary.BigEndian.PutUint64(blobReqMeta[0:8], blobHash.Index)
    binary.BigEndian.PutUint64(blobReqMeta[8:16], actualTimestamp)  // ✅ 올바른 timestamp 사용
    p.hint.Hint(BlobHint(append(blobHash.Hash[:], blobReqMeta...)))
    // ...
}
```

### 수정 이유

1. **ref.Hash는 신뢰할 수 있음** - 실제 L1 block의 hash
2. **ref.Time은 신뢰할 수 없음** - derivation pipeline에서 잘못 구성될 수 있음
3. **headerByBlockHash()를 통해 정확한 timestamp 조회** - block header는 canonical한 정보

## 테스트 방법

```bash
# 수정 후 테스트 실행
go test -v -timeout 40m ./op-e2e/faultproofs -run "^TestOutputAsteriscStepWithPreimage_existingPreimage$/asterisc$"
```

**예상 결과:** 테스트가 성공적으로 완료되어야 함

## 추가 조사 필요 사항

1. **L1BlockRef.Time이 왜 잘못 설정되는가?**
   - `L1Retrieval.NextData()` → `NextL1Block()` 호출 체인
   - BlockInfo 생성 과정에서 Time 필드가 어떻게 설정되는지
   - 이것이 Asterisc에만 발생하는지, 아니면 일반적인 문제인지

2. **Cannon은 왜 성공하는가?**
   - Cannon과 Asterisc의 테스트 환경이 완전히 독립적
   - Cannon에서도 같은 버그가 있을 수 있지만 다른 타이밍으로 인해 우연히 성공했을 가능성

3. **Production 환경에서의 영향**
   - 실제 mainnet/testnet에서 이 버그가 발생할 가능성
   - Beacon API를 사용하는 경우 timestamp 불일치 문제가 있는지

## 날짜
2025-11-20

## 상태
- [x] 버그 발견 및 분석
- [x] 수정 구현
- [ ] 테스트 검증
- [ ] 추가 조사
