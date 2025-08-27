// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { ProxyAdminOwnedBase } from "src/L1/ProxyAdminOwnedBase.sol";
import { ReinitializableBase } from "src/universal/ReinitializableBase.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

// Libraries
import { GameId, LibGameId } from "src/dispute/lib/Types.sol";

// Interfaces
import { ISemver } from "interfaces/universal/ISemver.sol";
import { IDisputeGameFactory } from "interfaces/dispute/IDisputeGameFactory.sol";

/// @custom:proxied true
/// @title RAT_1 (Original Version)
/// @notice Randomized Attention Test contract for challenger monitoring and testing - Original Implementation
contract RAT_1 is ProxyAdminOwnedBase, ReinitializableBase, Initializable, ReentrancyGuard, ISemver {
    /// @notice Challenger information structure
    /// @dev Packed to minimize storage slots
    struct ChallengerInfo {
        uint256 stakingAmount;      // Slot 1: 32 bytes
        uint256 slashedAmount;      // Slot 2: 32 bytes
        address challenger;         // Slot 3: 20 bytes
        uint64 l1BlockNumber;       // Slot 3: 8 bytes (packed with address)
        uint32 id;                  // Slot 3: 4 bytes (packed)
        uint32 validatorIndex;      // Slot 4: 4 bytes
        bool isValid;               // Slot 4: 1 byte (packed)
    }

    /// @notice Attention test information structure
    /// @dev Packed to minimize storage slots
    struct AttentionInfo {
        GameId gameId;              // Slot 1: 32 bytes
        bytes32 stateRoot;          // Slot 2: 32 bytes
        uint256 slashedAmount;      // Slot 3: 32 bytes
        address challengerAddress;  // Slot 4: 20 bytes
        uint64 l1BlockNumber;       // Slot 4: 8 bytes (packed with address)
        bool evidenceSubmitted;     // Slot 4: 1 byte (packed)
    }

    /// @notice Emitted when a challenger stakes ETH
    event ChallengerStaked(address indexed challenger, uint256 amount, uint256 totalStaking);

    /// @notice Emitted when attention test is triggered
    event AttentionTriggered(GameId indexed gameId, bytes32 stateRoot, uint256 l2BlockNumber, address indexed challenger);

    /// @notice Emitted when correct evidence is submitted
    event CorrectEvidenceSubmitted(
        GameId indexed gameId,
        address indexed challenger,
        bytes32 proofLV,
        bytes32 proofRV,
        uint256 restoredAmount
    );

    /// @notice Emitted when bonded amount is refunded through claim resolution
    event BondRefunded(GameId indexed gameId, address indexed challenger, uint256 refundedAmount);

    /// @notice Semantic version
    /// @custom:semver 1.0.0-beta.1
    string public constant version = "1.0.0-beta.1";

    /// @notice DisputeGameFactory contract address
    IDisputeGameFactory public disputeGameFactory;

    /// @notice Slashing bond amount per attention test
    uint256 public perTestSlashingAmount;

    /// @notice Evidence submission period in blocks
    uint256 public evidenceSubmissionPeriod;

    /// @notice Minimum staking balance required
    uint256 public minimumStakingBalance;

    /// @notice Counter for challenger IDs (uint32 saves gas)
    uint32 public challengerCounter;

    /// @notice Mapping from challenger address to challenger info
    mapping(address => ChallengerInfo) public challengers;

    /// @notice Mapping from FaultDisputeGame address to attention info
    mapping(address => AttentionInfo) public attentionTests;

    /// @notice Mapping from GameId to FaultDisputeGame address
    mapping(GameId => address) public gameIdToAddress;

    /// @notice Array of valid challengers
    address[] public validChallengers;

    /// @notice Array of invalid challengers
    address[] public invalidChallengers;

    /// @notice Maximum number of challengers to prevent DOS attacks
    uint256 public constant MAX_CHALLENGERS = 10000;

    /// @notice Mapping from challenger address to index in validChallengers array
    mapping(address => uint256) public validChallengerIndex;

    /// @notice Mapping from challenger address to index in invalidChallengers array
    mapping(address => uint256) public invalidChallengerIndex;

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

    /// @notice Modifier to restrict access to DisputeGameFactory only
    modifier onlyDisputeGameFactory() {
        if (msg.sender != address(disputeGameFactory)) revert NotDisputeGameFactory();
        _;
    }

    /// @notice Constructs the RAT contract
    constructor() ReinitializableBase(2) {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    /// @param _disputeGameFactory Address of the DisputeGameFactory contract
    /// @param _perTestSlashingAmount Slashing amount per attention test
    /// @param _evidenceSubmissionPeriod Evidence submission period in blocks
    /// @param _minimumStakingBalance Minimum staking balance required
    function initialize(
        IDisputeGameFactory _disputeGameFactory,
        uint256 _perTestSlashingAmount,
        uint256 _evidenceSubmissionPeriod,
        uint256 _minimumStakingBalance
    )
        public
        payable
        reinitializer(initVersion())
    {

        disputeGameFactory = _disputeGameFactory;
        perTestSlashingAmount = _perTestSlashingAmount;
        evidenceSubmissionPeriod = _evidenceSubmissionPeriod;
        minimumStakingBalance = _minimumStakingBalance;
    }

    /// @notice Allows challengers to stake ETH
    function stake() external payable nonReentrant {
        require(msg.value > 0, "Must stake positive amount");

        ChallengerInfo storage challenger = challengers[msg.sender];

        if (challenger.challenger == address(0)) {
            require(challengerCounter < MAX_CHALLENGERS, "Max challengers reached");
            require(block.number <= type(uint64).max, "Block number too large");

            challengerCounter++;
            challenger.id = challengerCounter;
            challenger.challenger = msg.sender;
            challenger.l1BlockNumber = uint64(block.number);
        }

        challenger.stakingAmount += msg.value;

        // Check if challenger meets minimum staking requirement
        if (challenger.stakingAmount >= minimumStakingBalance) {
            if (!challenger.isValid) {
                // Add to valid challengers list
                challenger.isValid = true;
                challenger.validatorIndex = uint32(validChallengers.length);
                validChallengers.push(msg.sender);

                // Remove from invalid challengers list if exists
                uint256 invalidIndex = invalidChallengerIndex[msg.sender];
                if (invalidIndex < invalidChallengers.length && invalidChallengers[invalidIndex] == msg.sender) {
                    _removeFromInvalidChallengers(msg.sender);
                }
            }
        }

        emit ChallengerStaked(msg.sender, msg.value, challenger.stakingAmount);
    }

    /// @notice Gets challenger information
    /// @param _challenger Address of the challenger
    /// @return Challenger information
    function getChallengerInfo(address _challenger) external view returns (ChallengerInfo memory) {
        return challengers[_challenger];
    }

    /// @notice Gets total number of challengers
    /// @return Total number of challengers
    function getTotalChallengers() external view returns (uint256) {
        return challengerCounter;
    }

    /// @notice Gets number of valid challengers
    /// @return Number of valid challengers
    function getValidChallengerCount() external view returns (uint256) {
        return validChallengers.length;
    }

    /// @notice Gets number of invalid challengers
    /// @return Number of invalid challengers
    function getInvalidChallengerCount() external view returns (uint256) {
        return invalidChallengers.length;
    }

    /// @notice Triggers attention test (called by DisputeGameFactory)
    /// @param _gameId Game ID
    /// @param _stateRoot State root to be verified
    /// @param _blockHash Block hash for validator selection
    /// @param _l2BlockNumber L2 block number
    function triggerAttentionTest(
        GameId _gameId,
        bytes32 _stateRoot,
        bytes32 _blockHash,
        uint256 _l2BlockNumber
    )
        external
        onlyDisputeGameFactory
    {
        require(validChallengers.length > 0, "No valid challengers available");

        // Select validator using block hash with additional entropy (anti-front-running)
        uint256 entropy = uint256(keccak256(abi.encodePacked(_blockHash, _gameId, block.difficulty, block.timestamp)));
        uint256 compressed = entropy & 0xFFFF; // Use lower 16 bits for gas efficiency
        uint256 selectedIndex = compressed % validChallengers.length;
        address selectedChallenger = validChallengers[selectedIndex];

        ChallengerInfo storage challengerInfo = challengers[selectedChallenger];

        // Calculate slashing amount (gas-optimized)
        uint256 stakingAmount = challengerInfo.stakingAmount;
        uint256 slashAmount = stakingAmount < perTestSlashingAmount ? stakingAmount : perTestSlashingAmount;

        // Slash the challenger
        challengerInfo.stakingAmount = stakingAmount - slashAmount;
        challengerInfo.slashedAmount += slashAmount;

        // Extract game address from GameId
        (, , address gameAddress) = LibGameId.unpack(_gameId);

        // Store attention test info with overflow protection
        require(block.number <= type(uint64).max, "Block number too large");
        attentionTests[gameAddress] = AttentionInfo({
            gameId: _gameId,
            challengerAddress: selectedChallenger,
            stateRoot: _stateRoot,
            slashedAmount: slashAmount,
            l1BlockNumber: uint64(block.number),
            evidenceSubmitted: false
        });

        // Map GameId to game address
        gameIdToAddress[_gameId] = gameAddress;

        // Check if challenger is still valid
        _updateChallengerValidity(selectedChallenger);

        emit AttentionTriggered(_gameId, _stateRoot, _l2BlockNumber, selectedChallenger);
    }

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

        if (attentionTest.challengerAddress == address(0)) revert AttentionTestNotExists();
        if (attentionTest.challengerAddress != msg.sender) revert InvalidChallengerAddress();
        if (attentionTest.evidenceSubmitted) revert EvidenceAlreadySubmitted();

        // Enhanced time validation with overflow protection
        uint256 submissionDeadline = attentionTest.l1BlockNumber + evidenceSubmissionPeriod;
        if (submissionDeadline < attentionTest.l1BlockNumber) revert("Deadline overflow");
        if (block.number >= submissionDeadline) revert EvidenceSubmissionExpired();

        // Verify proof
        bytes32 calculatedRoot = keccak256(abi.encodePacked(_proofLV, _proofRV));
        if (calculatedRoot != attentionTest.stateRoot) revert ProofVerificationFailed();

        // Mark evidence as submitted and refund slashed amount
        attentionTest.evidenceSubmitted = true;
        ChallengerInfo storage challengerInfo = challengers[msg.sender];
        challengerInfo.stakingAmount += attentionTest.slashedAmount;

        // Update challenger validity
        _updateChallengerValidity(msg.sender);

        emit CorrectEvidenceSubmitted(
            attentionTest.gameId,
            msg.sender,
            _proofLV,
            _proofRV,
            attentionTest.slashedAmount
        );
    }

    /// @notice Called when a claim is resolved in FaultDisputeGame
    /// @param _claimant Address receiving the bond refund
    function resolveClaim(address _claimant) external {
        AttentionInfo storage attentionTest = attentionTests[msg.sender];

        if (attentionTest.challengerAddress != address(0) &&
            attentionTest.challengerAddress == _claimant &&
            !attentionTest.evidenceSubmitted) {

            // Mark evidence as submitted and refund slashed amount
            attentionTest.evidenceSubmitted = true;
            ChallengerInfo storage challengerInfo = challengers[_claimant];
            challengerInfo.stakingAmount += attentionTest.slashedAmount;

            // Update challenger validity
            _updateChallengerValidity(_claimant);

            emit BondRefunded(attentionTest.gameId, _claimant, attentionTest.slashedAmount);
        }
    }

    /// @notice Sets the per-test slashing amount (only proxy admin owner)
    /// @param _amount New slashing amount
    function setPerTestSlashingAmount(uint256 _amount) external {
        _assertOnlyProxyAdminOwner();
        require(_amount > 0, "Slashing amount must be positive");
        require(_amount <= 100 ether, "Slashing amount too large");
        perTestSlashingAmount = _amount;
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

    /// @notice Internal function to update challenger validity
    /// @param _challenger Address of the challenger
    function _updateChallengerValidity(address _challenger) internal {
        ChallengerInfo storage challengerInfo = challengers[_challenger];
        bool shouldBeValid = challengerInfo.stakingAmount >= minimumStakingBalance;

        if (challengerInfo.isValid && !shouldBeValid) {
            // Move from valid to invalid
            challengerInfo.isValid = false;
            _removeFromValidChallengers(_challenger);
            _addToInvalidChallengers(_challenger);
        } else if (!challengerInfo.isValid && shouldBeValid) {
            // Move from invalid to valid
            challengerInfo.isValid = true;
            _removeFromInvalidChallengers(_challenger);
            _addToValidChallengers(_challenger);
        }
    }

    /// @notice Internal function to add challenger to valid list
    /// @param _challenger Address of the challenger
    function _addToValidChallengers(address _challenger) internal {
        ChallengerInfo storage challengerInfo = challengers[_challenger];
        challengerInfo.validatorIndex = uint32(validChallengers.length);
        validChallengers.push(_challenger);
    }

    /// @notice Internal function to remove challenger from valid list
    /// @param _challenger Address of the challenger
    function _removeFromValidChallengers(address _challenger) internal {
        uint256 index = challengers[_challenger].validatorIndex;
        if (index < validChallengers.length && validChallengers[index] == _challenger) {
            // Replace with last element and pop (gas-optimized)
            uint256 lastIndex = validChallengers.length - 1;
            if (index != lastIndex) {
                address lastChallenger = validChallengers[lastIndex];
                validChallengers[index] = lastChallenger;
                challengers[lastChallenger].validatorIndex = uint32(index);
            }
            validChallengers.pop();
        }
    }

    /// @notice Internal function to add challenger to invalid list
    /// @param _challenger Address of the challenger
    function _addToInvalidChallengers(address _challenger) internal {
        invalidChallengerIndex[_challenger] = invalidChallengers.length;
        invalidChallengers.push(_challenger);
    }

    /// @notice Internal function to remove challenger from invalid list
    /// @param _challenger Address of the challenger
    function _removeFromInvalidChallengers(address _challenger) internal {
        uint256 index = invalidChallengerIndex[_challenger];
        if (index < invalidChallengers.length && invalidChallengers[index] == _challenger) {
            // Replace with last element and pop
            if (index != invalidChallengers.length - 1) {
                address lastChallenger = invalidChallengers[invalidChallengers.length - 1];
                invalidChallengers[index] = lastChallenger;
                invalidChallengerIndex[lastChallenger] = index;
            }
            invalidChallengers.pop();
            delete invalidChallengerIndex[_challenger];
        }
    }
}