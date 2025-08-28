# Randomized Attention Test (RAT) Contracts - Build Guide

RAT is designed to test whether challengers are diligently monitoring through attention tests.

**Existing code should not be modified except for the code specified below.**

## Implementation Components

### RAT Contract

1. **File Location**: `packages/contracts-bedrock/src/L1/RAT.sol`

2. **Inheritance Structure**
   ```solidity
   contract RAT is ProxyAdminOwnedBase, ReinitializableBase, Initializable, ReentrancyGuard, ISemver
   ```

3. **Storage Structure**

   #### ChallengerInfo Struct
   ```solidity
   struct ChallengerInfo {
       uint256 stakingAmount;      // Slot 1: 32 bytes
       uint256 totalSlashedAmount; // Slot 2: 32 bytes (total slashed amount for this challenger)
       uint32 validatorIndex;      // Slot 3: 4 bytes
       bool isValid;               // Slot 3: 1 byte (packed)
   }
   ```

   #### AttentionInfo Struct
   ```solidity
   struct AttentionInfo {
       bytes32 stateRoot;          // Slot 1: 32 bytes
       uint96 bondAmount;          // Slot 2: 12 bytes (packed with challengerAddress)
       address challengerAddress;  // Slot 2: 20 bytes (packed with bondAmount)
       uint64 l1BlockNumber;       // Slot 3: 8 bytes
       bool evidenceSubmitted;     // Slot 3: 1 byte (packed)
   }
   ```

4. **State Variables**
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

5. **Events**
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

6. **Custom Errors**
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

8. **Constructor**
   ```solidity
   /// @notice Constructs the RAT contract
   constructor() ReinitializableBase(2) {
       _disableInitializers();
   }
   ```

9. **Initialization Function**
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

10. **Staking Function**
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

11. **View Functions**
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

12. **Attention Test Trigger Function**
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

13. **Evidence Submission Function**
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

14. **Claim Resolution Function**
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

15. **Admin Functions**
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

16. **Internal Functions**
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

### DisputeGameFactory Contract Upgrade

1. **File**: `packages/contracts-bedrock/src/dispute/DisputeGameFactory.sol`

2. **Add RAT Address Storage**
   ```solidity
   /// @notice RAT contract address
   address public rat;
   ```

3. **Modify create Function**
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

4. **Add setRAT Function**
   ```solidity
   /// @notice Sets the RAT contract address.
   /// @dev May only be called by the `owner`.
   /// @param _rat The RAT contract address.
   function setRAT(address _rat) external onlyOwner {
       rat = _rat;
   }
   ```

### FaultDisputeGame Contract Upgrade

1. **File**: `packages/contracts-bedrock/src/dispute/FaultDisputeGame.sol`

2. **Add RAT Address Storage**
   ```solidity
   address public rat;
   ```

3. **Add initialize(address _rat) Function**
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

4. **Modify initialize() Function**
   ```solidity
   /// @notice Initializes the contract without RAT.
   /// @dev This function may only be called once.
   function initialize() public payable virtual {
       _initialize(address(0));
   }
   ```

5. **Add gameDataWithRat() Function**
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

6. **Add resolveClaimRat() Function**
   ```solidity
   /// @notice Calls RAT resolveClaim function safely
   /// @param claimant Address receiving the bond
   function resolveClaimRat(address claimant) internal {
       if (rat != address(0)) {
           try IRAT(rat).resolveClaim(claimant) {} catch {}
       }
   }
   ```

7. **Modify resolveClaim() Function**
   - Add `resolveClaimRat()` function call after `_distributeBond` function call
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

## Interface Modifications

### IDisputeGameFactory Modification

1. **File**: `packages/contracts-bedrock/interfaces/dispute/IDisputeGameFactory.sol`

2. **Add Functions**
   ```solidity
   function rat() external view returns (address);
   function setRAT(address _rat) external;
   ```

### IFaultDisputeGame Modification

1. **File**: `packages/contracts-bedrock/interfaces/dispute/IFaultDisputeGame.sol`

2. **Add Function**
   ```solidity
   function gameDataWithRat() external view returns (GameType gameType_, Claim rootClaim_, bytes memory extraData_, address ratAddress_);
   ```

### IInitializable Modification

1. **File**: `packages/contracts-bedrock/interfaces/dispute/IInitializable.sol`

2. **Add Function**
   ```solidity
   function initialize(address _rat) external payable;
   ```

## Test File Writing Guide

### RAT Test File

1. **File Location**: `packages/contracts-bedrock/test/L1/RAT.t.sol`

2. **Important Notes**:
   - **Inheritance Structure**: Inherit from `CommonTest` to utilize existing test environment
   - **Initialization**: Must call `super.setUp()`
   - **Proxy Setup**: Use `Proxy` contract to deploy RAT
   - **Gas Measurement**: Use `gasleft()` for accurate gas measurement
   - **Error Handling**: Use `vm.expectRevert()` for error case testing

3. **Test Case Structure**:
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

4. **Key Test Cases**:
   - Initialization test
   - Staking test
   - Attention test trigger test
   - Evidence submission test
   - Claim resolution test
   - Gas measurement test

### DisputeGameFactory Test File

1. **File Location**: `packages/contracts-bedrock/test/dispute/DisputeGameFactory.t.sol`

2. **Important Notes**:
   - **RAT Setup**: Set RAT address using `setRAT()` function
   - **Game Type**: RAT call only for `GameTypes.CANNON`
   - **Error Handling**: Verify that RAT call failures are silently ignored

### FaultDisputeGame Test File

1. **File Location**: `packages/contracts-bedrock/test/dispute/FaultDisputeGame.t.sol`

2. **Important Notes**:
   - **Initialization**: Test initialization with RAT address
   - **resolveClaim**: Verify RAT call is made correctly
   - **Error Handling**: Handle cases where RAT is not set

## Compilation and Deployment

1. **Compilation**:
   ```bash
   forge build
   ```

2. **Test Execution**:
   ```bash
   forge test
   ```

3. **Gas Measurement**:
   ```bash
   forge test --gas-report
   ```

## Important Notes

1. **Proxy Pattern**: RAT uses proxy pattern, so be careful with initialization
2. **Gas Optimization**: Gas optimization through storage slot packing and conditional execution
3. **Security**: Access control with `onlyDisputeGameFactory` modifier
4. **Error Handling**: Proper handling of all error cases
5. **Testing**: Test writing required for all functions and error cases
