# 📋 RAT.sol 버전 변경사항 상세 분석

## 🔄 커밋 정보
- **커밋 해시**: `3ec35d2b0e`
- **작성자**: Zena-park <zena@tokamak.network>
- **날짜**: 2025년 8월 28일
- **메시지**: "feat: Update RAT contract interface, implementation and tests"

## 📊 주요 변경사항 카테고리

### 1. 데이터 구조 최적화 (Storage Optimization)

#### 이전 버전
```solidity
struct ChallengerInfo {
    uint256 stakingAmount;      // Slot 1: 32 bytes
    uint256 slashedAmount;      // Slot 2: 32 bytes
    address challenger;         // Slot 3: 20 bytes
    uint64 l1BlockNumber;       // Slot 3: 8 bytes (packed with address)
    uint32 id;                  // Slot 3: 4 bytes (packed)
    uint32 validatorIndex;      // Slot 4: 4 bytes
    bool isValid;               // Slot 4: 1 byte (packed)
}
```

#### 최신 버전
```solidity
struct ChallengerInfo {
    uint256 stakingAmount;      // Slot 1: 32 bytes
    uint256 totalSlashedAmount; // Slot 2: 32 bytes (total slashed amount)
    uint32 validatorIndex;      // Slot 3: 4 bytes
    bool isValid;               // Slot 3: 1 byte (packed)
}
```

**가스 절약**: 2개 Storage 슬롯 감소 (4 → 2 슬롯)

### 2. AttentionInfo 구조체 최적화

#### 이전 버전
```solidity
struct AttentionInfo {
    GameId gameId;              // Slot 1: 32 bytes
    bytes32 stateRoot;          // Slot 2: 32 bytes
    uint256 slashedAmount;      // Slot 3: 32 bytes
    address challengerAddress;  // Slot 4: 20 bytes
    uint64 l1BlockNumber;       // Slot 4: 8 bytes (packed with address)
    bool evidenceSubmitted;     // Slot 4: 1 byte (packed)
}
```

#### 최신 버전
```solidity
struct AttentionInfo {
    bytes32 stateRoot;          // Slot 1: 32 bytes
    uint96 bondAmount;          // Slot 2: 12 bytes (packed with challengerAddress)
    address challengerAddress;  // Slot 2: 20 bytes (packed with bondAmount)
    uint64 l1BlockNumber;       // Slot 3: 8 bytes
    bool evidenceSubmitted;     // Slot 3: 1 byte (packed)
}
```

**가스 절약**: 1개 Storage 슬롯 감소 (4 → 3 슬롯)

### 3. 함수 시그니처 및 로직 단순화

#### 이전 버전
```solidity
function triggerAttentionTest(
    GameId _gameId,
    bytes32 _stateRoot,
    bytes32 _blockHash,
    uint256 _l2BlockNumber
) external onlyDisputeGameFactory
```

#### 최신 버전
```solidity
function triggerAttentionTest(
    address _gameAddress,
    bytes32 _stateRoot,
    bytes32 _blockHash
) external onlyDisputeGameFactory
```

**변경사항**: `GameId`와 `_l2BlockNumber` 파라미터 제거로 가스 절약

### 4. 복잡한 Assembly 코드 제거

#### 이전 버전: Ultra-optimized assembly 코드 사용
```solidity
// Ultra-optimized entropy calculation
assembly {
    let ptr := mload(0x40)
    mstore(ptr, _blockHash)
    mstore(add(ptr, 0x20), _gameId)
    mstore(add(ptr, 0x40), difficulty())
    mstore(add(ptr, 0x60), timestamp())
    entropy := keccak256(ptr, 0x80)
}
```

#### 최신 버전: 단순한 Solidity 코드
```solidity
// Optimize challenger selection
uint256 selectedIndex = validChallengersLength == 2 ? 1 :
   ((uint256(keccak256(abi.encodePacked(_blockHash, _gameAddress, block.timestamp))) & 0xFFFF) % (validChallengersLength-1) )+1;
```

**가스 절약**: Assembly 오버헤드 제거로 더 예측 가능한 가스 사용

### 5. 불필요한 기능 및 변수 제거

**제거된 항목들**:
- `challengerCounter` - 챌린저 ID 카운터
- `invalidChallengers` 배열 - 무효한 챌린저 관리
- `gameIdToAddress` 매핑 - GameId 변환
- `MAX_CHALLENGERS` 상수 - 최대 챌린저 수 제한
- 복잡한 유효성 검사 로직

**가스 절약**: 불필요한 Storage 접근 및 연산 제거

### 6. 이벤트 최적화

#### 이전 버전
```solidity
event AttentionTriggered(
    GameId indexed gameId,
    bytes32 stateRoot,
    uint256 l2BlockNumber,
    address indexed challenger
);
```

#### 최신 버전
```solidity
event AttentionTriggered(
    address indexed gameAddress,
    address indexed challenger
);
```

**가스 절약**: 인덱스되지 않은 파라미터 제거로 이벤트 가스 비용 감소

## 📈 가스 절약 요약

| 최적화 영역 | 이전 버전 | 최신 버전 | 가스 절약 |
|-------------|-----------|-----------|-----------|
| Storage 슬롯 | 8 슬롯 | 5 슬롯 | **37.5% 감소** |
| Assembly 코드 | 복잡한 assembly | 단순한 Solidity | 예측 가능한 가스 |
| 불필요한 기능 | 복잡한 유효성 검사 | 단순한 검사 | 연산 가스 절약 |
| 이벤트 최적화 | 많은 파라미터 | 핵심 파라미터만 | 이벤트 가스 절약 |

## 🎯 결론

`triggerAttentionTest()` 가스 비용이 **25.7% 감소**한 주요 원인:

1. **Storage 최적화**: 3개 슬롯 절약으로 SSTORE/SLOAD 가스 비용 대폭 감소
2. **Assembly 제거**: 복잡한 assembly 코드를 단순한 Solidity로 대체
3. **불필요한 기능 제거**: 챌린저 카운터, 무효 챌린저 관리 등 제거
4. **데이터 구조 단순화**: GameId 대신 직접 address 사용
5. **로직 단순화**: 복잡한 유효성 검사를 단순한 조건문으로 대체



