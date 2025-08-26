// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { ProxyAdminOwnedBase } from "src/L1/ProxyAdminOwnedBase.sol";
import { ReinitializableBase } from "src/universal/ReinitializableBase.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// Libraries
import { GameId, Claim, Position } from "src/dispute/lib/Types.sol";
import { LibGameId } from "src/dispute/lib/LibUDT.sol";

// Interfaces
import { ISemver } from "interfaces/universal/ISemver.sol";
import { IDisputeGame } from "interfaces/dispute/IDisputeGame.sol";
import { IFaultDisputeGame } from "interfaces/dispute/IFaultDisputeGame.sol";

/// @custom:proxied true
/// @title RAT (Randomized Attention Test)
/// @notice RAT tests challenger attention by randomly selecting challengers and requiring them to provide evidence
contract RAT is ProxyAdminOwnedBase, ReinitializableBase, Initializable, ISemver {
    /// @notice Challenger information structure
    struct ChallengerInfo {
        uint256 id;
        address challengerAddress;
        uint256 stakedAmount;
        uint256 slashedAmount;
    }

    /// @notice Attention challenge information structure
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

    /// @notice Emitted when a challenger stakes ETH
    event ChallengerStaked(address indexed challenger, uint256 amount, uint256 challengerId);

    /// @notice Emitted when attention is triggered for a challenger
    event AttentionTriggered(GameId indexed gameId, Claim stateRoot, uint256 l2BlockNumber, address indexed challengerAddress);

    /// @notice Emitted when correct evidence is submitted
    event CorrectEvidenceSubmitted(GameId indexed gameId, address indexed sender, uint256 restoredAmount);

    /// @notice Emitted when incorrect evidence is submitted (game started)
    event IncorrectEvidenceSubmitted(GameId indexed gameId, Claim indexed claim, uint256 bondAmount);

    /// @notice Emitted when a challenger is resolved after winning a game
    event ChallengerResolved(GameId indexed gameId, address indexed challengerAddress, uint256 addedAmount);

    /// @notice Emitted when minimum stake amount is updated
    event MinimumStakeAmountUpdated(uint256 indexed newMinimumStakeAmount);

    /// @notice Semantic version
    /// @custom:semver 1.0.0-beta.1
    string public constant version = "1.0.0-beta.1";

    /// @notice DisputeGameFactory contract address
    address public disputeGameFactory;

    /// @notice Bond amount to be slashed per attention challenge
    uint256 public slashBondAmount;

    /// @notice Evidence submission period in blocks
    uint256 public evidenceSubmissionPeriod;

    /// @notice Minimum staking balance required for challengers
    uint256 public minimumStakeAmount;

    /// @notice Counter for challenger IDs
    uint256 public challengerIdCounter;

    /// @notice Mapping from challenger address to challenger info
    mapping(address => ChallengerInfo) public challengers;

    /// @notice Mapping from GameId to attention info
    mapping(GameId => AttentionInfo) public attentionMapping;

    /// @notice Mapping from FaultDisputeGame address to GameId
    mapping(address => GameId) public gameMapping;

    /// @notice Array of valid challenger addresses
    address[] public validChallengers;

    /// @notice Mapping from challenger address to index in validChallengers array
    mapping(address => uint256) public validChallengerIndex;

    /// @notice Array of invalid challenger addresses
    address[] public invalidChallengers;

    /// @notice Mapping from challenger address to index in invalidChallengers array
    mapping(address => uint256) public invalidChallengerIndex;

    /// @notice Constructor sets the initialization version to 2 following Optimism patterns
    constructor() ReinitializableBase(2) {
        _disableInitializers();
    }

    /// @notice Initializes the RAT contract
    /// @param _disputeGameFactory Address of the DisputeGameFactory contract
    /// @param _slashBondAmount Amount to be slashed per attention challenge
    /// @param _evidenceSubmissionPeriod Evidence submission period in blocks
    /// @param _minimumStakeAmount Minimum staking balance required for challengers
    function initialize(
        address _disputeGameFactory,
        uint256 _slashBondAmount,
        uint256 _evidenceSubmissionPeriod,
        uint256 _minimumStakeAmount
    ) external reinitializer(initVersion()) {
        // Initialization transactions must come from the ProxyAdmin or its owner
        _assertOnlyProxyAdminOrProxyAdminOwner();

        disputeGameFactory = _disputeGameFactory;
        slashBondAmount = _slashBondAmount;
        evidenceSubmissionPeriod = _evidenceSubmissionPeriod;
        minimumStakeAmount = _minimumStakeAmount;
        challengerIdCounter = 1;
    }

    /// @notice Allows challengers to stake ETH
    function stake() external payable {
        require(msg.value > 0, "RAT: stake amount must be greater than 0");

        bool isNewChallenger = challengers[msg.sender].challengerAddress == address(0);
        uint256 challengerId;

        if (isNewChallenger) {
            // New challenger
            challengerId = challengerIdCounter++;
            challengers[msg.sender] = ChallengerInfo({
                id: challengerId,
                challengerAddress: msg.sender,
                stakedAmount: msg.value,
                slashedAmount: 0
            });
        } else {
            // Existing challenger - add to existing stake
            challengerId = challengers[msg.sender].id;
            challengers[msg.sender].stakedAmount += msg.value;
        }

        // Check if total staked amount meets minimum requirement
        uint256 totalStaked = challengers[msg.sender].stakedAmount;
        require(totalStaked >= minimumStakeAmount, "RAT: total stake below minimum required");

        // Update valid/invalid challenger lists based on current stake
        bool isCurrentlyValid = _isValidChallenger(msg.sender);
        bool shouldBeValid = totalStaked >= slashBondAmount;

        if (!isCurrentlyValid && shouldBeValid) {
            // Move from invalid to valid (or add to valid if new)
            if (!isNewChallenger) {
                _removeInvalidChallenger(msg.sender);
            }
            _addValidChallenger(msg.sender);
        } else if (isCurrentlyValid && !shouldBeValid) {
            // Move from valid to invalid (shouldn't happen with minimum stake check)
            _removeValidChallenger(msg.sender);
            _addInvalidChallenger(msg.sender);
        } else if (isNewChallenger) {
            // New challenger - add to appropriate list
            if (shouldBeValid) {
                _addValidChallenger(msg.sender);
            } else {
                _addInvalidChallenger(msg.sender);
            }
        }

        emit ChallengerStaked(msg.sender, msg.value, challengerId);
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
        return challengerIdCounter - 1;
    }

    /// @notice Gets the number of valid challengers
    /// @return Number of valid challengers
    function getValidChallengersCount() external view returns (uint256) {
        return validChallengers.length;
    }

    /// @notice Gets the number of invalid challengers
    /// @return Number of invalid challengers
    function getInvalidChallengersCount() external view returns (uint256) {
        return invalidChallengers.length;
    }

    /// @notice Gets attention information for a game
    /// @param _gameId The GameId to get attention info for
    /// @return Attention information
    function getAttentionInfo(GameId _gameId) external view returns (AttentionInfo memory) {
        return attentionMapping[_gameId];
    }

    /// @notice Sets the minimum stake amount (only proxy admin owner can call)
    /// @param _minimumStakeAmount New minimum stake amount
    function setMinimumStakeAmount(uint256 _minimumStakeAmount) external {
        _assertOnlyProxyAdminOrProxyAdminOwner();
        minimumStakeAmount = _minimumStakeAmount;
        emit MinimumStakeAmountUpdated(_minimumStakeAmount);
    }

    /// @notice Attention trigger function - only callable by DisputeGameFactory
    /// @param _gameId The GameId of the dispute game
    /// @param _stateRoot The state root claim
    /// @param _l2BlockNumber The L2 block number
    /// @param _blockHash The block hash for randomization
    function attentionTrigger(
        GameId _gameId,
        Claim _stateRoot,
        uint256 _l2BlockNumber,
        bytes32 _blockHash
    ) external {
        require(msg.sender == disputeGameFactory, "RAT: only DisputeGameFactory can call");
        require(validChallengers.length > 0, "RAT: no valid challengers");

        // Select challenger using block hash
        uint256 challengerIndex = uint256(_blockHash) % validChallengers.length;
        address selectedChallenger = validChallengers[challengerIndex];

        // Check if challenger has sufficient stake
        if (challengers[selectedChallenger].stakedAmount < slashBondAmount) {
            // Remove from valid challengers and try again
            _removeValidChallenger(selectedChallenger);
            _addInvalidChallenger(selectedChallenger);

            // Retry with updated valid challengers list
            if (validChallengers.length > 0) {
                challengerIndex = uint256(_blockHash) % validChallengers.length;
                selectedChallenger = validChallengers[challengerIndex];
            } else {
                return; // No valid challengers left
            }
        }

        // Slash the challenger's stake
        challengers[selectedChallenger].stakedAmount -= slashBondAmount;
        challengers[selectedChallenger].slashedAmount += slashBondAmount;

        // Move to invalid challengers if stake becomes insufficient
        if (challengers[selectedChallenger].stakedAmount < slashBondAmount) {
            _removeValidChallenger(selectedChallenger);
            _addInvalidChallenger(selectedChallenger);
        }

        // Store attention information
        attentionMapping[_gameId] = AttentionInfo({
            gameId: _gameId,
            challengerAddress: selectedChallenger,
            stateRoot: _stateRoot,
            l2BlockNumber: _l2BlockNumber,
            blockHash: _blockHash,
            slashedBondAmount: slashBondAmount,
            l1Block: block.number,
            evidenceSubmitted: false
        });

        // Store game mapping
        // Note: We need to get the game address from the GameId
        (, , address gameProxy) = LibGameId.unpack(_gameId);
        gameMapping[gameProxy] = _gameId;

        emit AttentionTriggered(_gameId, _stateRoot, _l2BlockNumber, selectedChallenger);
    }

    /// @notice Submit evidence that the state root is correct
    /// @param _gameAddress Address of the FaultDisputeGame
    /// @param _proofLV Left value for state root calculation
    /// @param _proofRV Right value for state root calculation
    function submitCorrectEvidence(
        address _gameAddress,
        bytes32 _proofLV,
        bytes32 _proofRV
    ) external {
        GameId gameId = gameMapping[_gameAddress];
        require(GameId.unwrap(gameId) != bytes32(0), "RAT: game not found");

        AttentionInfo storage info = attentionMapping[gameId];
        require(info.challengerAddress == msg.sender, "RAT: only selected challenger can submit");
        require(!info.evidenceSubmitted, "RAT: evidence already submitted");
        require(block.number < info.l1Block + evidenceSubmissionPeriod, "RAT: submission period expired");

        // Verify proof matches state root
        bytes32 calculatedRoot = keccak256(abi.encodePacked(_proofLV, _proofRV));
        require(Claim.unwrap(info.stateRoot) == calculatedRoot, "RAT: invalid proof");

        // Mark evidence as submitted and restore stake
        info.evidenceSubmitted = true;
        challengers[msg.sender].stakedAmount += info.slashedBondAmount;
        challengers[msg.sender].slashedAmount -= info.slashedBondAmount;

        emit CorrectEvidenceSubmitted(gameId, msg.sender, info.slashedBondAmount);
    }

    /// @notice Submit evidence that the state root is incorrect by starting a fault dispute game
    /// @param _gameAddress Address of the FaultDisputeGame
    /// @param _claim The claim at the relative attack position
    function submitIncorrectEvidence(
        address _gameAddress,
        Claim _claim
    ) external payable {
        GameId gameId = gameMapping[_gameAddress];
        require(GameId.unwrap(gameId) != bytes32(0), "RAT: game not found");

        AttentionInfo storage info = attentionMapping[gameId];
        require(info.challengerAddress == msg.sender, "RAT: only selected challenger can submit");
        require(!info.evidenceSubmitted, "RAT: evidence already submitted");
        require(block.number < info.l1Block + evidenceSubmissionPeriod, "RAT: submission period expired");

        IFaultDisputeGame game = IFaultDisputeGame(_gameAddress);

        // Get required bond amount for attack position 2
        Position attackPos = Position.wrap(2);
        uint256 requiredBond = game.getRequiredBond(attackPos);
        require(msg.value == requiredBond, "RAT: incorrect bond amount");

        // Attack the root claim
        game.attack{ value: msg.value }(info.stateRoot, 0, _claim);

        emit IncorrectEvidenceSubmitted(gameId, _claim, msg.value);
    }

    /// @notice Resolve function called when challenger wins a game
    function resolve() external {
        GameId gameId = gameMapping[msg.sender];
        require(GameId.unwrap(gameId) != bytes32(0), "RAT: game not found");

        AttentionInfo storage info = attentionMapping[gameId];
        require(info.challengerAddress != address(0), "RAT: invalid attention info");
        require(!info.evidenceSubmitted, "RAT: evidence already submitted");

        // Mark evidence as submitted and restore stake
        info.evidenceSubmitted = true;
        challengers[info.challengerAddress].stakedAmount += info.slashedBondAmount;
        challengers[info.challengerAddress].slashedAmount -= info.slashedBondAmount;

        // Move to valid challengers if stake becomes sufficient
        if (challengers[info.challengerAddress].stakedAmount >= slashBondAmount &&
            !_isValidChallenger(info.challengerAddress)) {
            _removeInvalidChallenger(info.challengerAddress);
            _addValidChallenger(info.challengerAddress);
        }

        emit ChallengerResolved(gameId, info.challengerAddress, info.slashedBondAmount);
    }

    /// @notice Internal function to remove challenger from valid challengers list
    /// @param _challenger Address of the challenger to remove
    function _removeValidChallenger(address _challenger) internal {
        uint256 index = validChallengerIndex[_challenger];
        uint256 lastIndex = validChallengers.length - 1;

        if (index != lastIndex) {
            address lastChallenger = validChallengers[lastIndex];
            validChallengers[index] = lastChallenger;
            validChallengerIndex[lastChallenger] = index;
        }

        validChallengers.pop();
        delete validChallengerIndex[_challenger];
    }

    /// @notice Internal function to add challenger to valid challengers list
    /// @param _challenger Address of the challenger to add
    function _addValidChallenger(address _challenger) internal {
        validChallengers.push(_challenger);
        validChallengerIndex[_challenger] = validChallengers.length - 1;
    }

    /// @notice Internal function to remove challenger from invalid challengers list
    /// @param _challenger Address of the challenger to remove
    function _removeInvalidChallenger(address _challenger) internal {
        uint256 index = invalidChallengerIndex[_challenger];
        uint256 lastIndex = invalidChallengers.length - 1;

        if (index != lastIndex) {
            address lastChallenger = invalidChallengers[lastIndex];
            invalidChallengers[index] = lastChallenger;
            invalidChallengerIndex[lastChallenger] = index;
        }

        invalidChallengers.pop();
        delete invalidChallengerIndex[_challenger];
    }

    /// @notice Internal function to add challenger to invalid challengers list
    /// @param _challenger Address of the challenger to add
    function _addInvalidChallenger(address _challenger) internal {
        invalidChallengers.push(_challenger);
        invalidChallengerIndex[_challenger] = invalidChallengers.length - 1;
    }

    /// @notice Check if challenger is in valid challengers list
    /// @param _challenger Address of the challenger
    /// @return True if challenger is valid
    function _isValidChallenger(address _challenger) internal view returns (bool) {
        if (validChallengers.length == 0) return false;
        uint256 index = validChallengerIndex[_challenger];
        return index < validChallengers.length && validChallengers[index] == _challenger;
    }
}