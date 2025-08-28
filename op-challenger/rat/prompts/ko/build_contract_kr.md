# Randomized Attention Test (RAT) Contracts - Build Guide

RAT은 챌린저들이 성실히 모니터링을 하고 있는지 챌린저 attention 테스트하기 위해 설계되었습니다.

**기존 존재하는 코드는 아래 기재한 코드 외에는 수정해서는 안됩니다.**

## 구현 요소

### RAT 컨트랙트

1. **파일 위치**: `packages/contracts-bedrock/src/L1/RAT.sol`

2. **상속 구조**
   ```solidity
   contract RAT is ProxyAdminOwnedBase, ReinitializableBase, Initializable, ReentrancyGuard, ISemver
   ```

3. **스토리지 구조**

   #### ChallengerInfo 구조체
   ```solidity
   struct ChallengerInfo {
       uint256 stakingAmount;      // Slot 1: 32 bytes
       uint256 totalSlashedAmount; // Slot 2: 32 bytes (total slashed amount for this challenger)
       uint32 validatorIndex;      // Slot 3: 4 bytes
       bool isValid;               // Slot 3: 1 byte (packed)
   }
   ```

   #### AttentionInfo 구조체
   ```solidity
   struct AttentionInfo {
       bytes32 stateRoot;          // Slot 1: 32 bytes
       uint96 bondAmount;          // Slot 2: 12 bytes (packed with challengerAddress)
       address challengerAddress;  // Slot 2: 20 bytes (packed with bondAmount)
       uint64 l1BlockNumber;       // Slot 3: 8 bytes
       bool evidenceSubmitted;     // Slot 3: 1 byte (packed)
   }
   ```

4. **상태 변수**
   ```solidity
   /// @notice Semantic version
   /// @custom:semver 1.0.0-beta.1
   string public constant version = "1.0.0-beta.1";

   /// @notice DisputeGameFactory contract address
   IDisputeGameFactory public disputeGameFactory;

   /// @notice Bond amount per attention test
   uint256 public perTestBondAmount;

   /// @notice Evidence submission period in blocks
   uint256 public evidenceSubmissionPeriod;

   /// @notice Minimum staking balance required
   uint256 public minimumStakingBalance;

   /// @notice Mapping from challenger address to challenger info
   mapping(address => ChallengerInfo) public challengers;

   /// @notice Mapping from FaultDisputeGame address to attention info
   mapping(address => AttentionInfo) public attentionTests;

   /// @notice Array of valid challengers (index 0 is reserved for "not found")
   address[] public validChallengers;
   ```

5. **이벤트**
   ```solidity
   /// @notice Emitted when a challenger stakes ETH
   event ChallengerStaked(address indexed challenger, uint256 amount);

   /// @notice Emitted when attention test is triggered
   event AttentionTriggered(address indexed gameAddress, address indexed challenger);

   /// @notice Emitted when correct evidence is submitted
   event CorrectEvidenceSubmitted(
       address indexed gameAddress,
       address indexed challenger,
       uint256 restoredAmount
   );

   /// @notice Emitted when bonded amount is refunded through claim resolution
   event BondRefunded(address indexed gameAddress, address indexed challenger, uint256 refundedAmount);
   ```

6. **커스텀 에러**
   ```solidity
   /// @notice Error thrown when caller is not the DisputeGameFactory
   error NotDisputeGameFactory();

   /// @notice Error thrown when challenger does not exist
   error ChallengerNotExists();

   /// @notice Error thrown when evidence submission period has expired
   error EvidenceSubmissionExpired();

   /// @notice Error thrown when evidence has already been submitted
   error EvidenceAlreadySubmitted();

   /// @notice Error thrown when caller is not the correct challenger
   error InvalidChallengerAddress();

   /// @notice Error thrown when proof verification fails
   error ProofVerificationFailed();

   /// @notice Error thrown when attention test does not exist
   error AttentionTestNotExists();

   /// @notice Error thrown when insufficient staking amount
   error InsufficientStakingAmount();

   /// @notice Error thrown when there are no valid challengers available
   error NoValidChallengers();
   ```

7. **Modifier**
   ```solidity
   /// @notice Modifier to restrict access to DisputeGameFactory only
   modifier onlyDisputeGameFactory() {
       if (msg.sender != address(disputeGameFactory)) revert NotDisputeGameFactory();
       _;
   }
   ```

8. **생성자**
   ```solidity
   /// @notice Constructs the RAT contract
   constructor() ReinitializableBase(2) {
       _disableInitializers();
   }
   ```

9. **초기화 함수**
   ```solidity
   /// @notice Initializes the contract
   /// @param _disputeGameFactory Address of the DisputeGameFactory contract
   /// @param _perTestBondAmount Bond amount per attention test
   /// @param _evidenceSubmissionPeriod Evidence submission period in blocks
   /// @param _minimumStakingBalance Minimum staking balance required
   function initialize(
       IDisputeGameFactory _disputeGameFactory,
       uint256 _perTestBondAmount,
       uint256 _evidenceSubmissionPeriod,
       uint256 _minimumStakingBalance
   )
       public
       payable
       reinitializer(initVersion())
   {
       require(_perTestBondAmount < type(uint96).max, "Bond amount exceeds uint96 maximum");
       require(_perTestBondAmount <= _minimumStakingBalance, "Bond amount cannot exceed minimum staking balance");
       disputeGameFactory = _disputeGameFactory;
       perTestBondAmount = _perTestBondAmount;
       evidenceSubmissionPeriod = _evidenceSubmissionPeriod;
       minimumStakingBalance = _minimumStakingBalance;

       // Initialize validChallengers with a dummy element at index 0
       validChallengers.push(address(0));
   }
   ```

10. **스테이킹 함수**
    ```solidity
    /// @notice Allows challengers to stake ETH
    function stake() external payable nonReentrant {
        require(msg.value > 0, "Must stake positive amount");

        ChallengerInfo storage challenger = challengers[msg.sender];

        challenger.stakingAmount += msg.value;
        // Check if challenger meets per-test bond requirement
        if (!challenger.isValid && (challenger.stakingAmount >= perTestBondAmount)) {
            challenger.isValid = true;
            challenger.validatorIndex = uint32(validChallengers.length);
            validChallengers.push(msg.sender);
        }

        emit ChallengerStaked(msg.sender, msg.value);
    }
    ```

11. **뷰 함수들**
    ```solidity
    /// @notice Gets challenger information
    /// @param _challenger Address of the challenger
    /// @return Challenger information
    function getChallengerInfo(address _challenger) external view returns (ChallengerInfo memory) {
        return challengers[_challenger];
    }

    /// @notice Gets number of valid challengers
    /// @return Number of valid challengers
    function getValidChallengerCount() external view returns (uint256) {
        return validChallengers.length;
    }
    ```

12. **어텐션 테스트 트리거 함수**
    ```solidity
    /// @notice Triggers attention test (called by DisputeGameFactory)
    /// @param _gameAddress Game contract address
    /// @param _stateRoot State root to be verified
    /// @param _blockHash Block hash for validator selection
    function triggerAttentionTest(
        address _gameAddress,
        bytes32 _stateRoot,
        bytes32 _blockHash
    )
        external
        onlyDisputeGameFactory
    {
        uint256 validChallengersLength = validChallengers.length;
        if (validChallengersLength > 1) {
            // Optimize challenger selection
            uint256 selectedIndex = validChallengersLength == 2 ? 1 :
               ((uint256(keccak256(abi.encodePacked(_blockHash, _gameAddress, block.timestamp))) & 0xFFFF) % (validChallengersLength-1) )+1; // -1 to exclude the dummy address(0)

            address selectedChallenger = validChallengers[selectedIndex];

            ChallengerInfo storage challengerInfo = challengers[selectedChallenger];

            // Calculate bond amount and update challenger (gas-optimized)
            uint256 stakingAmount = challengerInfo.stakingAmount;
            uint256 bondAmount = stakingAmount < perTestBondAmount ? stakingAmount : perTestBondAmount;
            uint256 newStakingAmount = stakingAmount - bondAmount;

            // Bond the challenger
            challengerInfo.stakingAmount = newStakingAmount;
            challengerInfo.totalSlashedAmount += bondAmount;

            // Validate block number
            require(block.number <= type(uint64).max, "Block number too large");

            // Store attention test info
            attentionTests[_gameAddress] = AttentionInfo({
                stateRoot: _stateRoot,
                bondAmount: uint96(bondAmount),
                challengerAddress: selectedChallenger,
                l1BlockNumber: uint64(block.number),
                evidenceSubmitted: false
            });

            // Check if challenger is still valid (gas-optimized)
            bool shouldBeValid = newStakingAmount >= perTestBondAmount;
            bool currentIsValid = challengerInfo.isValid;

            if (currentIsValid != shouldBeValid) {
                if (shouldBeValid) {
                    // invalid → valid
                    challengerInfo.isValid = true;
                    _addToValidChallengers(selectedChallenger, uint32(validChallengers.length));
                } else {
                    // valid → invalid
                    challengerInfo.isValid = false;
                    _removeFromValidChallengers(selectedChallenger, challengerInfo.validatorIndex);
                }
            }

            emit AttentionTriggered(_gameAddress, selectedChallenger);
        }
    }
    ```

13. **증거 제출 함수**
    ```solidity
    /// @notice Submits correct evidence for attention test
    /// @param _gameAddress Game contract address
    /// @param _proofLV Left child state value
    /// @param _proofRV Right child state value
    function submitCorrectEvidence(
        address _gameAddress,
        bytes32 _proofLV,
        bytes32 _proofRV
    )
        external
    {
        AttentionInfo storage attentionTest = attentionTests[_gameAddress];

        // Early validation with cached values (gas optimization)
        address challengerAddress = attentionTest.challengerAddress;
        if (challengerAddress == address(0)) revert AttentionTestNotExists();
        if (challengerAddress != msg.sender) revert InvalidChallengerAddress();
        if (attentionTest.evidenceSubmitted) revert EvidenceAlreadySubmitted();

        // Time validation with overflow protection (gas optimized)
        uint256 submissionDeadline = attentionTest.l1BlockNumber + evidenceSubmissionPeriod;
        if (submissionDeadline < attentionTest.l1BlockNumber) revert("Deadline overflow");
        if (block.number >= submissionDeadline) revert EvidenceSubmissionExpired();

        // Verify proof (gas optimized - single hash operation)
        if (keccak256(abi.encodePacked(_proofLV, _proofRV)) != attentionTest.stateRoot) revert ProofVerificationFailed();

        // Cache values for gas optimization
        uint256 bond = uint256(attentionTest.bondAmount);
        attentionTest.evidenceSubmitted = true;

        // Update challenger staking amount
        ChallengerInfo storage challengerInfo = challengers[msg.sender];
        challengerInfo.stakingAmount += bond;

        // Update challenger validity (gas optimized)
        bool currentIsValid = challengerInfo.isValid;
        bool shouldBeValid = challengerInfo.stakingAmount >= perTestBondAmount;

        if (!currentIsValid && shouldBeValid) {
            // invalid → valid
            challengerInfo.isValid = true;
            _addToValidChallengers(msg.sender, uint32(validChallengers.length));
        } else if (currentIsValid && !shouldBeValid) {
            // valid → invalid
            challengerInfo.isValid = false;
            _removeFromValidChallengers(msg.sender, challengerInfo.validatorIndex);
        }

        emit CorrectEvidenceSubmitted(
            _gameAddress,
            challengerAddress,
            bond
        );
    }
    ```

14. **클레임 해결 함수**
    ```solidity
    /// @notice Called when a claim is resolved in FaultDisputeGame
    /// @param _claimant Address receiving the bond refund
    function resolveClaim(address _claimant) external {
        // Early validation with caching
        address challengerAddress = attentionTests[msg.sender].challengerAddress;
        if (challengerAddress != address(0) && challengerAddress == _claimant) {
            // bool evidenceSubmitted = attentionTests[msg.sender].evidenceSubmitted;
            if (!attentionTests[msg.sender].evidenceSubmitted) {
                AttentionInfo storage attentionTest = attentionTests[msg.sender];

                // Mark evidence as submitted and refund bond amount
                attentionTest.evidenceSubmitted = true;
                uint256 bond = uint256(attentionTest.bondAmount);

                ChallengerInfo storage challengerInfo = challengers[_claimant];
                challengerInfo.stakingAmount += bond;

                // Update challenger validity
                bool currentIsValid = challengerInfo.isValid;
                bool shouldBeValid = challengerInfo.stakingAmount >= perTestBondAmount;

                if (!currentIsValid && shouldBeValid) {
                    // invalid → valid
                    challengerInfo.isValid = true;
                    _addToValidChallengers(_claimant, uint32(validChallengers.length));
                } else if (currentIsValid && !shouldBeValid) {
                    // valid → invalid
                    challengerInfo.isValid = false;
                    _removeFromValidChallengers(_claimant, challengerInfo.validatorIndex);
                }

                emit BondRefunded(msg.sender, challengerAddress, bond);
            }
        }
    }
    ```

15. **관리자 함수들**
    ```solidity
    /// @notice Sets the per-test bond amount (only proxy admin owner)
    /// @param _amount New bond amount
    function setPerTestBondAmount(uint256 _amount) external {
        _assertOnlyProxyAdminOwner();
        require(_amount > 0, "Bond amount must be positive");
        require(_amount <= type(uint96).max, "Bond amount exceeds uint96 maximum");
        require(_amount <= minimumStakingBalance, "Bond amount cannot exceed minimum staking balance");
        perTestBondAmount = _amount;
    }

    /// @notice Sets the evidence submission period (only proxy admin owner)
    /// @param _period New submission period in blocks
    function setEvidenceSubmissionPeriod(uint256 _period) external {
        _assertOnlyProxyAdminOwner();
        require(_period > 0, "Period must be positive");
        require(_period <= 50400, "Period too long");
        evidenceSubmissionPeriod = _period;
    }

    /// @notice Sets the minimum staking balance (only proxy admin owner)
    /// @param _balance New minimum staking balance
    function setMinimumStakingBalance(uint256 _balance) external {
        _assertOnlyProxyAdminOwner();
        require(_balance > 0, "Balance must be positive");
        require(_balance <= 1000 ether, "Balance too large");
        minimumStakingBalance = _balance;
    }
    ```

16. **내부 함수들**
    ```solidity
    /// @notice Internal function to add challenger to valid list
    /// @param _challenger Address of the challenger
    /// @param _index Index to assign to the challenger
    function _addToValidChallengers(address _challenger, uint32 _index) internal {
        challengers[_challenger].validatorIndex = _index;
        validChallengers.push(_challenger);
    }

    /// @notice Internal function to remove challenger from valid list
    /// @param _challenger Address of the challenger
    /// @param _index Index of the challenger in validChallengers array
    function _removeFromValidChallengers(address _challenger, uint256 _index) internal {
        if (_index > 0 && _index < validChallengers.length && validChallengers[_index] == _challenger) {
            // Replace with last element and pop (gas-optimized)
            uint256 lastIndex = validChallengers.length - 1;
            if (_index != lastIndex) {
                address lastChallenger = validChallengers[lastIndex];
                validChallengers[_index] = lastChallenger;
                challengers[lastChallenger].validatorIndex = uint32(_index);
            }
            validChallengers.pop();
        }
    }
    ```

### DisputeGameFactory 컨트랙트 업그레이드

1. **파일**: `packages/contracts-bedrock/src/dispute/DisputeGameFactory.sol`

2. **RAT 주소 스토리지 추가**
   ```solidity
   /// @notice RAT contract address
   address public rat;
   ```

3. **create 함수 수정**
   ```solidity
   function create(
       GameType _gameType,
       Claim _rootClaim,
       bytes calldata _extraData
   )
       external
       payable
       returns (IDisputeGame proxy_)
   {
       // Grab the implementation contract for the given `GameType`.
       IDisputeGame impl = gameImpls[_gameType];

       // If there is no implementation to clone for the given `GameType`, revert.
       if (address(impl) == address(0)) revert NoImplementation(_gameType);

       // If the required initialization bond is not met, revert.
       if (msg.value != initBonds[_gameType]) revert IncorrectBondAmount();

       // Get the hash of the parent block.
       bytes32 parentHash = blockhash(block.number - 1);

       // Clone the implementation contract and initialize it with the given parameters.
       proxy_ = IDisputeGame(address(impl).clone(abi.encodePacked(msg.sender, _rootClaim, parentHash, _extraData)));

       // Initialize with RAT address if CANNON game type
       if (_gameType.raw() == GameTypes.CANNON.raw()) {
           IInitializable(address(proxy_)).initialize{ value: msg.value }(rat);
       } else {
           proxy_.initialize{ value: msg.value }();
       }

       // Compute the unique identifier for the dispute game.
       Hash uuid = getGameUUID(_gameType, _rootClaim, _extraData);

       // If a dispute game with the same UUID already exists, revert.
       if (GameId.unwrap(_disputeGames[uuid]) != bytes32(0)) revert GameAlreadyExists(uuid);

       // Pack the game ID.
       GameId id = LibGameId.pack(_gameType, Timestamp.wrap(uint64(block.timestamp)), address(proxy_));

       // Store the dispute game id in the mapping & emit the `DisputeGameCreated` event.
       _disputeGames[uuid] = id;
       _disputeGameList.push(id);
       emit DisputeGameCreated(address(proxy_), _gameType, _rootClaim);

       // Trigger RAT attention test if RAT contract is set and game type is CANNON
       if (rat != address(0) && _gameType.raw() == GameTypes.CANNON.raw()) {
           (, , address gameAddress) = id.unpack();
           try IRAT(rat).triggerAttentionTest(gameAddress, Claim.unwrap(_rootClaim), parentHash) {} catch {}
       }
   }
   ```

4. **setRAT 함수 추가**
   ```solidity
   /// @notice Sets the RAT contract address.
   /// @dev May only be called by the `owner`.
   /// @param _rat The RAT contract address.
   function setRAT(address _rat) external onlyOwner {
       rat = _rat;
   }
   ```

### FaultDisputeGame 컨트랙트 업그레이드

1. **파일**: `packages/contracts-bedrock/src/dispute/FaultDisputeGame.sol`

2. **RAT 주소 스토리지 추가**
   ```solidity
   address public rat;
   ```

3. **initialize(address _rat) 함수 추가**
   ```solidity
   /// @notice Initializes the contract with RAT address.
   /// @dev This function may only be called once.
   function initialize(address _rat) public payable virtual {
       _initialize(_rat);
   }

   /// @notice Initializes the contract.
   /// @dev This function may only be called once.
   function _initialize(address _rat) public virtual {
       // SAFETY: Any revert in this function will bubble up to the DisputeGameFactory and
       // prevent the game from being created.
       //
       // Implicit assumptions:
       // - The `gameStatus` state variable defaults to 0, which is `GameStatus.IN_PROGRESS`
       // - The dispute game factory will enforce the required bond to initialize the game.
       //
       // Explicit checks:
       // - The game must not have already been initialized.
       // - An output root cannot be proposed at or before the starting block number.

       // INVARIANT: The game must not have already been initialized.
       if (initialized) revert AlreadyInitialized();

       // Grab the latest anchor root.
       (Hash root, uint256 rootBlockNumber) = ANCHOR_STATE_REGISTRY.getAnchorRoot();

       // Should only happen if this is a new game type that hasn't been set up yet.
       if (root.raw() == bytes32(0)) revert AnchorRootNotFound();

       // Set the starting proposal.
       startingOutputRoot = Proposal({ l2SequenceNumber: rootBlockNumber, root: root });

       // Revert if the calldata size is not the expected length.
       //
       // This is to prevent adding extra or omitting bytes from to `extraData` that result in a different game UUID
       // in the factory, but are not used by the game, which would allow for multiple dispute games for the same
       // output proposal to be created.
       //
       // Expected length: 154 bytes
       // - 4 bytes selector
       // - 20 bytes creator address
       // - 32 bytes root claim
       // - 32 bytes l1 head
       // - 32 bytes extraData
       // - 2 bytes CWIA length
       if (msg.data.length != 122) revert BadExtraData();

       // Do not allow the game to be initialized if the root claim corresponds to a block at or before the
       // configured starting block number.
       if (l2BlockNumber() <= rootBlockNumber) revert UnexpectedRootClaim(rootClaim());

       // Set the root claim
       claimData.push(
           ClaimData({
               parentIndex: type(uint32).max,
               counteredBy: address(0),
               claimant: gameCreator(),
               bond: uint128(msg.value),
               claim: rootClaim(),
               position: ROOT_POSITION,
               clock: LibClock.wrap(Duration.wrap(0), Timestamp.wrap(uint64(block.timestamp)))
           })
       );

       // Set the game as initialized.
       initialized = true;

       // Deposit the bond.
       refundModeCredit[gameCreator()] += msg.value;
       WETH.deposit{ value: msg.value }();

       // Set the game's starting timestamp
       createdAt = Timestamp.wrap(uint64(block.timestamp));

       // Set whether the game type was respected when the game was created.
       wasRespectedGameTypeWhenCreated =
           GameType.unwrap(ANCHOR_STATE_REGISTRY.respectedGameType()) == GameType.unwrap(GAME_TYPE);

       if(_rat != address(0)) rat = _rat;
   }
   ```

4. **initialize() 함수 변경**
   ```solidity
   /// @notice Initializes the contract without RAT.
   /// @dev This function may only be called once.
   function initialize() public payable virtual {
       _initialize(address(0));
   }
   ```

5. **gameDataWithRat() 함수 추가**
   ```solidity
   /// @notice A compliant implementation of this interface should return the components of the
   ///         game UUID's preimage provided in the cwia payload. The preimage of the UUID is
   ///         constructed as `keccak256(gameType . rootClaim . extraData)` where `.` denotes
   ///         concatenation.
   /// @return gameType_ The type of proof system being used.
   /// @return rootClaim_ The root claim of the DisputeGame.
   /// @return extraData_ Any extra data supplied to the dispute game contract by the creator.
   /// @return ratAddress_ The address of the RAT contract.
   function gameDataWithRat() external view returns (GameType gameType_, Claim rootClaim_, bytes memory extraData_, address ratAddress_) {
       gameType_ = gameType();
       rootClaim_ = rootClaim();
       extraData_ = extraData();
       ratAddress_ = rat;
   }
   ```

6. **resolveClaimRat() 함수 추가**
   ```solidity
   /// @notice Calls RAT resolveClaim function safely
   /// @param claimant Address receiving the bond
   function resolveClaimRat(address claimant) internal {
       if (rat != address(0)) {
           try IRAT(rat).resolveClaim(claimant) {} catch {}
       }
   }
   ```

7. **resolveClaim() 함수 수정**
   - `_distributeBond` 함수 호출 후 `resolveClaimRat()` 함수 호출 추가
   ```solidity
   function resolveClaim(uint256 _claimIndex, uint256 _numToResolve) external {
       // ... existing code ...

       _distributeBond(recipient, subgameRootClaim);
       resolveClaimRat(recipient);

       // ... existing code ...

       _distributeBond(challenger, subgameRootClaim);
       resolveClaimRat(challenger);

       // ... existing code ...
       _distributeBond(countered == address(0) ? subgameRootClaim.claimant : countered, subgameRootClaim);
       resolveClaimRat(countered == address(0) ? subgameRootClaim.claimant : countered);

       // ... existing code ...
   }
   ```

## 인터페이스 수정

### IDisputeGameFactory 수정

1. **파일**: `packages/contracts-bedrock/interfaces/dispute/IDisputeGameFactory.sol`

2. **함수 추가**
   ```solidity
   function rat() external view returns (address);
   function setRAT(address _rat) external;
   ```

### IFaultDisputeGame 수정

1. **파일**: `packages/contracts-bedrock/interfaces/dispute/IFaultDisputeGame.sol`

2. **함수 추가**
   ```solidity
   function gameDataWithRat() external view returns (GameType gameType_, Claim rootClaim_, bytes memory extraData_, address ratAddress_);
   ```

### IInitializable 수정

1. **파일**: `packages/contracts-bedrock/interfaces/dispute/IInitializable.sol`

2. **함수 추가**
   ```solidity
   function initialize(address _rat) external payable;
   ```

## 테스트 파일 작성 가이드

### RAT 테스트 파일

1. **파일 위치**: `packages/contracts-bedrock/test/L1/RAT.t.sol`

2. **주의사항**:
   - **상속 구조**: `CommonTest`를 상속하여 기존 테스트 환경 활용
   - **초기화**: `super.setUp()` 호출 필수
   - **프록시 설정**: `Proxy` 컨트랙트 사용하여 RAT 배포
   - **가스 측정**: `gasleft()` 사용하여 정확한 가스 측정
   - **에러 처리**: `vm.expectRevert()` 사용하여 에러 케이스 테스트

3. **테스트 케이스 구조**:
   ```solidity
   contract RAT_TestInit is CommonTest {
       RAT public rat;

       function setUp() public {
           super.setUp();

           // Deploy RAT implementation
           RAT ratImpl = new RAT();

           // Deploy RAT proxy
           Proxy ratProxy = new Proxy(address(1));

           // Cast proxy to RAT interface
           rat = RAT(payable(address(ratProxy)));

           // Initialize RAT
           vm.prank(address(1));
           ratProxy.upgradeToAndCall(
               address(ratImpl),
               abi.encodeWithSelector(
                   RAT.initialize.selector,
                   address(disputeGameFactory),
                   PER_TEST_BOND_AMOUNT,
                   EVIDENCE_SUBMISSION_PERIOD,
                   MINIMUM_STAKE_AMOUNT
               )
           );
       }
   }
   ```

4. **주요 테스트 케이스**:
   - 초기화 테스트
   - 스테이킹 테스트
   - 어텐션 테스트 트리거 테스트
   - 증거 제출 테스트
   - 클레임 해결 테스트
   - 가스 측정 테스트

### DisputeGameFactory 테스트 파일

1. **파일 위치**: `packages/contracts-bedrock/test/dispute/DisputeGameFactory.t.sol`

2. **주의사항**:
   - **RAT 설정**: `setRAT()` 함수로 RAT 주소 설정
   - **게임 타입**: `GameTypes.CANNON`에 대해서만 RAT 호출
   - **에러 처리**: RAT 호출 실패 시 조용히 무시되는지 확인

### FaultDisputeGame 테스트 파일

1. **파일 위치**: `packages/contracts-bedrock/test/dispute/FaultDisputeGame.t.sol`

2. **주의사항**:
   - **초기화**: RAT 주소와 함께 초기화하는 경우 테스트
   - **resolveClaim**: RAT 호출이 올바르게 되는지 확인
   - **에러 처리**: RAT가 설정되지 않은 경우 처리

## 컴파일 및 배포

1. **컴파일**:
   ```bash
   forge build
   forge compile
   ```

2. **테스트 실행**:
   ```bash
   forge test
   ```

3. **가스 측정**:
   ```bash
   forge test --gas-report
   ```

## 주의사항

1. **프록시 패턴**: RAT는 프록시 패턴을 사용하므로 초기화 시 주의
2. **가스 최적화**: 스토리지 슬롯 패킹과 조건부 실행으로 가스 최적화
3. **보안**: `onlyDisputeGameFactory` modifier로 접근 제어
4. **에러 처리**: 모든 에러 케이스에 대한 적절한 처리
5. **테스트**: 모든 함수와 에러 케이스에 대한 테스트 작성 필수
