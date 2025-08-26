# Randomized Attention Test (RAT) Contracts Implementation

RAT 시스템은 챌린저들이 성실히 모니터링을 하고 있는지 테스트하기 위해 설계된 시스템입니다. 이 문서는 실제 구현된 컨트랙트들의 구체적인 내용을 정리합니다.

## 구현된 컨트랙트 개요

### 1. RAT 컨트랙트 (`/packages/contracts-bedrock/src/L1/RAT.sol`)

#### 상속 구조
```solidity
contract RAT is ProxyAdminOwnedBase, ReinitializableBase, Initializable, ISemver
```

#### 주요 구조체
```solidity
struct ChallengerInfo {
    uint256 id;
    address challengerAddress;
    uint256 stakedAmount;
    uint256 slashedAmount;
}

struct AttentionInfo {
    GameId gameId;
    address challengerAddress;
    Claim stateRoot;
    uint256 l2BlockNumber;
    bytes32 blockHash;
    uint256 slashedBondAmount;
    uint256 l1Block;
    bool evidenceSubmitted;
}
```

#### 상태 변수
```solidity
string public constant version = "1.0.0-beta.1";
address public disputeGameFactory;
uint256 public slashBondAmount;
uint256 public evidenceSubmissionPeriod;
uint256 public minimumStakeAmount;
uint256 public challengerIdCounter;
mapping(address => ChallengerInfo) public challengers;
mapping(GameId => AttentionInfo) public attentionMapping;
mapping(address => GameId) public gameMapping;
address[] public validChallengers;
mapping(address => uint256) public validChallengerIndex;
address[] public invalidChallengers;
mapping(address => uint256) public invalidChallengerIndex;
```

#### 이벤트
```solidity
event ChallengerStaked(address indexed challenger, uint256 amount, uint256 challengerId);
event AttentionTriggered(GameId indexed gameId, Claim stateRoot, uint256 l2BlockNumber, address indexed challengerAddress);
event CorrectEvidenceSubmitted(GameId indexed gameId, address indexed sender, uint256 restoredAmount);
event IncorrectEvidenceSubmitted(GameId indexed gameId, Claim indexed claim, uint256 bondAmount);
event ChallengerResolved(GameId indexed gameId, address indexed challengerAddress, uint256 addedAmount);
event MinimumStakeAmountUpdated(uint256 indexed newMinimumStakeAmount);
```

#### 주요 함수

**초기화 함수**
```solidity
function initialize(
    address _disputeGameFactory,
    uint256 _slashBondAmount,
    uint256 _evidenceSubmissionPeriod,
    uint256 _minimumStakeAmount
) external reinitializer(initVersion())
```

**스테이킹 함수 (다중 스테이킹 지원)**
```solidity
function stake() external payable
```
- 여러번 스테이킹 가능
- 최소 스테이킹 금액 검증
- 유효/무효 챌린저 리스트 자동 관리

**어텐션 트리거 함수**
```solidity
function attentionTrigger(
    GameId _gameId,
    Claim _stateRoot,
    uint256 _l2BlockNumber,
    bytes32 _blockHash
) external
```
- DisputeGameFactory만 호출 가능
- 블록 해시를 이용한 랜덤 챌린저 선택
- 자동 슬래싱 및 챌린저 상태 관리

**올바른 증거 제출 함수**
```solidity
function submitCorrectEvidence(
    address _gameAddress,
    bytes32 _proofLV,
    bytes32 _proofRV
) external
```
- 제출 기간 내 증거 검증
- 슬래시된 보증금 복구

**틀린 증거 제출 함수**
```solidity
function submitIncorrectEvidence(
    address _gameAddress,
    Claim _claim
) external payable
```
- FaultDisputeGame 공격 시작
- 필요 보증금 자동 계산 및 검증

**해결 함수**
```solidity
function resolve() external
```
- 챌린저 승리 시 보증금 복구
- 유효 챌린저 상태 복원

**관리자 함수**
```solidity
function setMinimumStakeAmount(uint256 _minimumStakeAmount) external
```

**뷰 함수들**
```solidity
function getChallengerInfo(address _challenger) external view returns (ChallengerInfo memory);
function getTotalChallengers() external view returns (uint256);
function getValidChallengersCount() external view returns (uint256);
function getInvalidChallengersCount() external view returns (uint256);
function getAttentionInfo(GameId _gameId) external view returns (AttentionInfo memory);
```

### 2. DisputeGameFactory 컨트랙트 업그레이드 (`/packages/contracts-bedrock/src/dispute/DisputeGameFactory.sol`)

#### 추가된 상태 변수
```solidity
address public rat;
```

#### 수정된 create 함수
```solidity
function create(
    GameType _gameType,
    Claim _rootClaim,
    bytes calldata _extraData
) external payable returns (IDisputeGame proxy_)
```

**CANNON 게임 타입 조건부 초기화**
```solidity
// Only pass RAT address for CANNON game type, others use no parameter
if (_gameType.raw() == GameTypes.CANNON.raw()) {
    proxy_.initialize{ value: msg.value }(rat);
} else {
    proxy_.initialize{ value: msg.value }();
}
```

**RAT 어텐션 트리거 호출**
```solidity
// Call RAT attention trigger if RAT address is set
if (rat != address(0)) {
    // Extract L2 block number from extraData (assuming 32-byte L2 block number)
    uint256 l2BlockNumber;
    if (_extraData.length >= 32) {
        assembly {
            l2BlockNumber := mload(add(_extraData.offset, 0x20))
        }
    }

    try IRAT(rat).attentionTrigger(id, _rootClaim, l2BlockNumber, parentHash) {} catch {
        // RAT attention trigger failed, but don't revert the game creation
    }
}
```

#### 추가된 관리자 함수
```solidity
function setRAT(address _rat) external onlyOwner {
    rat = _rat;
}
```

### 3. FaultDisputeGame 컨트랙트 업그레이드 (`/packages/contracts-bedrock/src/dispute/FaultDisputeGame.sol`)

#### 추가된 상태 변수
```solidity
address public rat;
```

#### 오버로드된 초기화 함수
```solidity
/// @notice Initializes the contract without RAT.
function initialize() public payable virtual {
    _initialize(address(0));
}

/// @notice Initializes the contract with RAT address.
function initialize(address _rat) public payable virtual {
    _initialize(_rat);
}
```

#### 내부 초기화 함수
```solidity
function _initialize(address _rat) internal {
    // ... 기존 초기화 로직 ...

    // RAT 주소 설정
    if (_rat != address(0)) rat = _rat;
}
```

#### 게임 데이터 조회 함수
```solidity
function gameDataWithRat() external view returns (GameType gameType_, Claim rootClaim_, bytes memory extraData_, address ratAddress_) {
    gameType_ = gameType();
    rootClaim_ = rootClaim();
    extraData_ = extraData();
    ratAddress_ = rat;
}
```

#### 수정된 resolve 함수
```solidity
function resolve() external returns (GameStatus status_) {
    // ... 기존 해결 로직 ...

    emit Resolved(status = status_);

    // RAT resolve 호출 (챌린저 승리 시)
    if (rat != address(0) && status_ == GameStatus.CHALLENGER_WINS) {
        try IRAT(rat).resolve() {} catch {}
    }
}
```

### 4. 인터페이스 업데이트

#### IDisputeGameFactory 인터페이스 (`/interfaces/dispute/IDisputeGameFactory.sol`)
```solidity
function rat() external view returns (address);
function setRAT(address _rat) external;
```
- RAT 주소 조회 및 설정을 위한 함수들 추가

#### IFaultDisputeGame 인터페이스 (`/interfaces/dispute/IFaultDisputeGame.sol`)
```solidity
function gameDataWithRat() external view returns (GameType gameType_, Claim rootClaim_, bytes memory extraData_, address ratAddress_);
function __constructor__(GameConstructorParams memory _params) external;
```
- RAT 주소를 포함한 게임 데이터 조회 함수 추가

#### IInitializable 인터페이스 (`/interfaces/dispute/IInitializable.sol`)
```solidity
interface IInitializable {
    function initialize() external payable;
    function initialize(address _rat) external payable;
}
```
- 기본 initialize 함수와 RAT 주소를 받는 오버로드 함수 추가

#### IRAT 인터페이스 (`/interfaces/L1/IRAT.sol`)
```solidity
interface IRAT {
    function attentionTrigger(GameId _gameId, Claim _stateRoot, uint256 _l2BlockNumber, bytes32 _blockHash) external;
    function resolve() external;
}
```
- RAT 컨트랙트의 핵심 함수들을 정의하는 인터페이스

### 5. 테스트 구현 (`/test/L1/RAT.t.sol`)

#### 테스트 컨트랙트들
- `RAT_TestInit`: 기본 테스트 설정
- `RAT_Version_Test`: 버전 테스트
- `RAT_Initialize_Test`: 초기화 테스트
- `RAT_Stake_Test`: 스테이킹 테스트 (다중 스테이킹, 최소 금액 검증 포함)
- `RAT_AttentionTrigger_Test`: 어텐션 트리거 테스트
- `RAT_SubmitCorrectEvidence_Test`: 올바른 증거 제출 테스트
- `RAT_GetChallengerInfo_Test`: 정보 조회 테스트
- `RAT_SetMinimumStakeAmount_Test`: 최소 스테이킹 금액 설정 테스트

#### 주요 테스트 상수
```solidity
uint256 public constant SLASH_BOND_AMOUNT = 1 ether;
uint256 public constant EVIDENCE_SUBMISSION_PERIOD = 100;
uint256 public constant MINIMUM_STAKE_AMOUNT = 0.1 ether;
```

## 주요 구현 특징

### 1. 보안 고려사항
- `onlyProxyAdminOwner` modifier 사용
- 재초기화 방지 (`ReinitializableBase` 버전 2)
- O(1) 배열 요소 제거를 위한 인덱스 매핑
- Try-catch를 통한 안전한 외부 호출

### 2. 가스 최적화
- 효율적인 챌린저 리스트 관리
- 인덱스 기반 배열 요소 제거
- 조건부 RAT 주소 전달

### 3. 확장성
- 다중 스테이킹 지원
- 관리자 제어 가능한 최소 스테이킹 금액
- 게임 타입별 조건부 RAT 적용

### 4. 이벤트 기반 모니터링
- 모든 중요한 액션에 대한 이벤트 발생
- 오프체인 모니터링 지원

이 구현은 원본 draft 문서의 모든 요구사항을 충족하며, 추가적으로 다중 스테이킹과 최소 스테이킹 금액 관리 기능을 포함하고 있습니다.