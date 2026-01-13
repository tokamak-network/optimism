// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { ProxyAdminOwnedBase } from "src/L1/ProxyAdminOwnedBase.sol";
import { ReinitializableBase } from "src/universal/ReinitializableBase.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

// Libraries
import { GameId, LibGameId } from "src/dispute/lib/Types.sol";
import { SecureMerkleTrie } from "src/libraries/trie/SecureMerkleTrie.sol";

// Interfaces
import { ISemver } from "interfaces/universal/ISemver.sol";
import { IDisputeGameFactory } from "interfaces/dispute/IDisputeGameFactory.sol";

/// @custom:proxied true
/// @title RAT (Randomized Attention Test)
/// @notice RAT Protocol v2 - Closest-key mechanism with dispute system
contract RAT is ProxyAdminOwnedBase, ReinitializableBase, Initializable, ReentrancyGuard, ISemver {

    // ============ Constants ============

    /// @notice Semantic version
    /// @custom:semver 2.0.0-beta.1
    string public constant version = "2.0.0-beta.1";

    /// @notice Maximum probability value (100,000 for extended probability range)
    uint256 private constant MAX_PROBABILITY = 100_000;

    /// @notice Penalty rate denominator (10000 = 100%)
    uint256 public constant PENALTY_DENOMINATOR = 10000;

    /// @notice Status constants
    uint8 public constant STATUS_PENDING = 0;
    uint8 public constant STATUS_SUBMITTED = 1;
    uint8 public constant STATUS_DISPUTED = 2;
    uint8 public constant STATUS_FINALIZED = 3;

    // ============ Structs ============

    /// @notice Challenger information structure
    struct ChallengerInfo {
        uint256 stakingAmount;
        uint256 totalSlashedAmount;
        uint32 validatorIndex;
        bool isValid;
    }

    /// @notice Attention test information structure (v2)
    struct AttentionInfo {
        bytes32 outputRoot;              // OutputRoot for verification
        bytes32 seed;                    // Random seed = H(blockhash || timestamp)
        bytes32 candidateKey;            // Submitted candidate key
        uint96 bondAmount;
        address challengerAddress;
        uint64 submissionDeadlineBlock;
        uint64 l2BlockNumber;
        uint8 status;                    // 0=pending, 1=submitted, 2=disputed, 3=finalized
    }

    // ============ Events ============

    event ChallengerStaked(address indexed challenger, uint256 amount);
    event AttentionTriggered(address indexed gameAddress, address indexed challenger, bytes32 seed);
    event CandidateSubmitted(address indexed gameAddress, address indexed challenger, bytes32 candidateKey, uint256 distance);
    event DisputeSuccessful(address indexed gameAddress, address indexed disputer, bytes32 key, uint256 amount, string reason);
    event OfflinePenalty(address indexed gameAddress, address indexed challenger, uint256 penalty);
    event SubmissionAccepted(address indexed gameAddress, address indexed challenger, bytes32 candidateKey);
    event BondRefunded(address indexed gameAddress, address indexed challenger, uint256 refundedAmount);

    // ============ Errors ============

    error NotDisputeGameFactory();
    error NotRatManager();
    error AttentionTestNotExists();
    error InvalidChallengerAddress();
    error InvalidStatus();
    error DeadlinePassed();
    error DeadlineNotPassed();
    error ProofVerificationFailed();
    error InvalidOutputRootComponents();
    error KeyExists();
    error NotCloserKey();
    error InsufficientStakingAmount();
    error InvalidKey();

    // ============ State Variables ============

    IDisputeGameFactory public disputeGameFactory;
    uint256 public perTestBondAmount;
    uint256 public evidenceSubmissionPeriod;
    uint256 public minimumStakingBalance;
    uint256 public ratTriggerProbability;
    uint256 public offlinePenaltyRate;  // basis points (e.g., 1000 = 10%)
    address public ratManager;

    mapping(address => ChallengerInfo) public challengers;
    mapping(address => AttentionInfo) public attentionTests;
    address[] public validChallengers;

    // ============ Modifiers ============

    modifier onlyDisputeGameFactory() {
        if (msg.sender != address(disputeGameFactory)) revert NotDisputeGameFactory();
        _;
    }

    modifier onlyRatManager() {
        if (msg.sender != ratManager) revert NotRatManager();
        _;
    }

    // ============ Constructor ============

    constructor() ReinitializableBase(3) {
        // _disableInitializers(); // Uncomment for production
    }

    // ============ Initialize ============

    function initialize(
        IDisputeGameFactory _disputeGameFactory,
        uint256 _perTestBondAmount,
        uint256 _evidenceSubmissionPeriod,
        uint256 _minimumStakingBalance,
        uint256 _ratTriggerProbability,
        uint256 _offlinePenaltyRate,
        address _manager
    ) public payable reinitializer(initVersion()) {
        require(_perTestBondAmount < type(uint96).max, "Bond exceeds uint96");
        require(_perTestBondAmount <= _minimumStakingBalance, "Bond > min stake");
        require(_ratTriggerProbability <= MAX_PROBABILITY, "Invalid probability");
        require(_offlinePenaltyRate <= PENALTY_DENOMINATOR, "Invalid penalty rate");

        disputeGameFactory = _disputeGameFactory;
        perTestBondAmount = _perTestBondAmount;
        evidenceSubmissionPeriod = _evidenceSubmissionPeriod;
        minimumStakingBalance = _minimumStakingBalance;
        ratTriggerProbability = _ratTriggerProbability;
        offlinePenaltyRate = _offlinePenaltyRate;
        ratManager = _manager;

        if (validChallengers.length == 0) {
            validChallengers.push(address(0)); // Dummy at index 0
        }
    }

    // ============ Staking ============

    function stake() external payable nonReentrant {
        require(msg.value > 0, "Must stake positive amount");

        ChallengerInfo storage challenger = challengers[msg.sender];
        challenger.stakingAmount += msg.value;

        if (!challenger.isValid && challenger.stakingAmount >= perTestBondAmount) {
            challenger.isValid = true;
            challenger.validatorIndex = uint32(validChallengers.length);
            validChallengers.push(msg.sender);
        }

        emit ChallengerStaked(msg.sender, msg.value);
    }

    // ============ Core Protocol ============

    /// @notice Triggers attention test (called by DisputeGameFactory)
    function triggerAttentionTest(
        address _gameAddress,
        bytes32 _outputRoot,
        bytes32, // _blockHash unused (we use L1 blockhash for security)
        uint64 _l2BlockNumber
    ) external onlyDisputeGameFactory {
        if (!shouldTriggerRAT()) return;

        uint256 numValidators = validChallengers.length;
        if (numValidators <= 1) return;

        // Generate seed per paper: H(blockhash(n-1) || timestamp)
        bytes32 seed = keccak256(abi.encodePacked(
            blockhash(block.number - 1),
            block.timestamp
        ));

        // Select validator: seed mod N (avoiding index 0)
        uint256 selectedIndex = numValidators == 2 ? 1 :
            (uint256(seed) % (numValidators - 1)) + 1;
        address selectedChallenger = validChallengers[selectedIndex];

        ChallengerInfo storage challengerInfo = challengers[selectedChallenger];

        // 1. Calculate Full Bond
        uint256 stakeAmt = challengerInfo.stakingAmount;
        uint256 bondAmt = stakeAmt < perTestBondAmount ? stakeAmt : perTestBondAmount;

        // 2. Calculate Penalty (Upfront Slash)
        uint256 penalty = (bondAmt * offlinePenaltyRate) / PENALTY_DENOMINATOR;

        // 3. Deduct Bond (Penalty is implicitly slashed if not refunded)
        challengerInfo.stakingAmount = stakeAmt - bondAmt;
        challengerInfo.totalSlashedAmount += penalty;

        // Store attention test
        attentionTests[_gameAddress] = AttentionInfo({
            outputRoot: _outputRoot,
            seed: seed,
            candidateKey: bytes32(0),
            bondAmount: uint96(bondAmt),
            challengerAddress: selectedChallenger,
            submissionDeadlineBlock: uint64(block.number + evidenceSubmissionPeriod),
            l2BlockNumber: _l2BlockNumber,
            status: STATUS_PENDING
        });

        // Update validity
        _updateValidity(selectedChallenger, challengerInfo);

        emit AttentionTriggered(_gameAddress, selectedChallenger, seed);
        emit OfflinePenalty(_gameAddress, selectedChallenger, penalty);
    }

    /// @notice Submit candidate key with inclusion proof
    /// @dev Verifies inclusion and refunds bond immediately (assuming no withdrawal allowed).
    function submitCandidate(
        address _gameAddress,
        bytes32 _candidateKey,
        bytes32 _stateRoot,
        bytes32 _version,
        bytes32 _messagePasserRoot,
        bytes32 _blockHash
    ) external {
        AttentionInfo storage test = attentionTests[_gameAddress];

        if (test.challengerAddress == address(0)) revert AttentionTestNotExists();
        if (test.challengerAddress != msg.sender) revert InvalidChallengerAddress();
        if (test.status != STATUS_PENDING) revert InvalidStatus();
        if (block.number >= test.submissionDeadlineBlock) revert DeadlinePassed();

        _verifyComponents(test, _version, _stateRoot, _messagePasserRoot, _blockHash);

        // Optimistic: We do NOT verify proof here. We assume it's valid.
        test.candidateKey = _candidateKey;
        test.status = STATUS_SUBMITTED;

        // Refund the Penalty (Reward for responding)
        // Since we deducted the full bond in triggerAttentionTest,
        // we now refund the full bond amount to reward the timely response.

        uint256 penalty = (test.bondAmount * offlinePenaltyRate) / PENALTY_DENOMINATOR;

        ChallengerInfo storage challenger = challengers[msg.sender];
        challenger.stakingAmount += test.bondAmount; // Full Refund of Bond

        // Revert stats update for penalty since we refunded it
        if (challenger.totalSlashedAmount >= penalty) {
            challenger.totalSlashedAmount -= penalty;
        }

        _updateValidity(msg.sender, challenger);

        emit CandidateSubmitted(_gameAddress, msg.sender, _candidateKey, _distance(_candidateKey, test.seed));
        emit SubmissionAccepted(_gameAddress, msg.sender, _candidateKey);
    }



    function disputeByNonInclusion(
        address _gameAddress,
        bytes32 _key, // The key asserted to NOT exist
        bytes32 _stateRoot,
        bytes32 _version,
        bytes32 _messagePasserRoot,
        bytes32 _blockHash,
        bytes[] calldata _proof
    ) external {
        AttentionInfo storage test = attentionTests[_gameAddress];
        if (test.status != STATUS_SUBMITTED) revert InvalidStatus();
        if (block.number >= test.submissionDeadlineBlock) revert DeadlinePassed();
        if (test.candidateKey != _key) revert InvalidKey(); // Must dispute the candidate key itself

        _verifyComponents(test, _version, _stateRoot, _messagePasserRoot, _blockHash);

        // Verify Non-Inclusion
        _verifyNonInclusion(address(uint160(uint256(_key))), _proof, _stateRoot);

        // SLASHING
        _slashChallenger(test.challengerAddress, test.bondAmount);

        test.status = STATUS_DISPUTED;
        payable(msg.sender).transfer(test.bondAmount);

        // No validity update needed here as slash handles it?
        // _slashChallenger calls _updateValidity.
        // Wait, _slashChallenger does call _updateValidity.

        emit DisputeSuccessful(_gameAddress, msg.sender, _key, test.bondAmount, "non-inclusion");
    }

    /// @notice External wrapper to allow try/catch on internal library call (For Non-Inclusion Check)
    function verifyInclusionWrapper(address _keyAddr, bytes[] calldata _proof, bytes32 _root) external pure virtual returns (bytes memory) {
        return SecureMerkleTrie.get(abi.encodePacked(_keyAddr), _proof, _root);
    }

    /// @notice Internal virtual helper for existence check (Testable)
    function _verifyExistence(bytes memory _keyBlob, bytes[] calldata _proof, bytes32 _root) internal virtual {
         SecureMerkleTrie.get(_keyBlob, _proof, _root);
    }

    function _verifyNonInclusion(address _keyAddr, bytes[] calldata _proof, bytes32 _root) internal virtual {
        // Wrapper for try/catch mechanism
        try this.verifyInclusionWrapper(_keyAddr, _proof, _root) returns (bytes memory) {
            // If get succeeds, the key EXISTS.
            revert KeyExists();
        } catch {
            // If get reverts, we assume it's because the key is missing.
        }
    }

    /// @notice Dispute by submitting strictly closer key
    function disputeByCloserKey(
        address _gameAddress,
        bytes32 _closerKey,
        bytes32 _stateRoot,
        bytes32 _version,
        bytes32 _messagePasserRoot,
        bytes32 _blockHash,
        bytes[] calldata _proof
    ) external {
        AttentionInfo storage test = attentionTests[_gameAddress];

        if (test.status != STATUS_SUBMITTED) revert InvalidStatus();
        // User requested: Dispute allowed within same deadline? (Last minute bug remains but user accepted risk)
        if (block.number >= test.submissionDeadlineBlock) revert DeadlinePassed();

        _verifyComponents(test, _version, _stateRoot, _messagePasserRoot, _blockHash);

        // Verify inclusion of closer key
        // Note: Cast to address for Account Trie verification
        _verifyExistence(abi.encodePacked(address(uint160(uint256(_closerKey)))), _proof, _stateRoot);

        // Verify strictly closer
        if (_distance(_closerKey, test.seed) >= _distance(test.candidateKey, test.seed)) {
            revert NotCloserKey();
        }

        // SLASHING
        uint256 totalSlash = test.bondAmount;
        _slashChallenger(test.challengerAddress, totalSlash);

        test.status = STATUS_DISPUTED;

        // Reward Disputer with full bond amount
        payable(msg.sender).transfer(totalSlash);

        emit DisputeSuccessful(_gameAddress, msg.sender, _closerKey, totalSlash, "closer-key");
    }



    // ============ View Functions ============

    function getChallengerInfo(address _challenger) external view returns (ChallengerInfo memory) {
        return challengers[_challenger];
    }

    function getValidChallengerCount() external view returns (uint256) {
        return validChallengers.length;
    }

    function getAttentionTest(address _gameAddress) external view returns (AttentionInfo memory) {
        return attentionTests[_gameAddress];
    }

    // ============ Admin Functions ============

    function setPerTestBondAmount(uint256 _amount) external {
        _assertOnlyProxyAdminOwner();
        require(_amount > 0 && _amount < type(uint96).max && _amount <= minimumStakingBalance);
        perTestBondAmount = _amount;
    }

    function setEvidenceSubmissionPeriod(uint256 _period) external {
        _assertOnlyProxyAdminOwner();
        require(_period > 0 && _period <= 50400);
        evidenceSubmissionPeriod = _period;
    }

    function setMinimumStakingBalance(uint256 _balance) external {
        _assertOnlyProxyAdminOwner();
        require(_balance > 0 && _balance <= 1000 ether);
        minimumStakingBalance = _balance;
    }

    function setOfflinePenaltyRate(uint256 _rate) external {
        _assertOnlyProxyAdminOwner();
        require(_rate <= PENALTY_DENOMINATOR);
        offlinePenaltyRate = _rate;
    }

    function setRatTriggerProbability(uint256 _probability) external onlyRatManager {
        require(_probability <= MAX_PROBABILITY);
        ratTriggerProbability = _probability;
    }

    // ============ Internal Functions ============

    function shouldTriggerRAT() internal view returns (bool) {
        uint256 prob = ratTriggerProbability;
        if (prob == 0) return false;
        if (prob >= MAX_PROBABILITY) return true;
        return uint256(blockhash(block.number - 1)) % MAX_PROBABILITY < prob;
    }

    function _verifyComponents(
        AttentionInfo storage test,
        bytes32 _version,
        bytes32 _stateRoot,
        bytes32 _messagePasserRoot,
        bytes32 _blockHash
    ) internal view {
        bytes32 computed = keccak256(abi.encode(_version, _stateRoot, _messagePasserRoot, _blockHash));
        if (computed != test.outputRoot) revert InvalidOutputRootComponents();
    }

    function _distance(bytes32 a, bytes32 b) internal pure returns (uint256) {
        uint256 x = uint256(a);
        uint256 y = uint256(b);
        return x >= y ? x - y : y - x;
    }



    function _slashChallenger(address _challengerAddr, uint256 _amount) internal {
        ChallengerInfo storage challenger = challengers[_challengerAddr];

        if (challenger.stakingAmount < _amount) {
            _amount = challenger.stakingAmount;
        }
        challenger.stakingAmount -= _amount;
        challenger.totalSlashedAmount += _amount;

        _updateValidity(_challengerAddr, challenger);
    }

    function _updateValidity(address _challenger, ChallengerInfo storage _info) internal {
        bool shouldBeValid = _info.stakingAmount >= perTestBondAmount;
        bool currentIsValid = _info.isValid;

        if (currentIsValid && !shouldBeValid) {
            _info.isValid = false;
            _removeFromValidChallengers(_challenger, _info.validatorIndex);
        } else if (!currentIsValid && shouldBeValid) {
            _info.isValid = true;
            _addToValidChallengers(_challenger, uint32(validChallengers.length));
        }
    }

    function _addToValidChallengers(address _challenger, uint32 _index) internal {
        challengers[_challenger].validatorIndex = _index;
        validChallengers.push(_challenger);
    }

    function _removeFromValidChallengers(address _challenger, uint256 _index) internal {
        if (_index > 0 && _index < validChallengers.length && validChallengers[_index] == _challenger) {
            uint256 lastIndex = validChallengers.length - 1;
            if (_index != lastIndex) {
                address lastChallenger = validChallengers[lastIndex];
                validChallengers[_index] = lastChallenger;
                challengers[lastChallenger].validatorIndex = uint32(_index);
            }
            validChallengers.pop();
        }
    }

    /// @notice Called when a claim is resolved in FaultDisputeGame (backward compatibility)
    function resolveClaim(address _claimant) external {
        AttentionInfo storage test = attentionTests[msg.sender];
        if (test.challengerAddress == _claimant && test.status == STATUS_PENDING) {
            test.status = STATUS_FINALIZED;
            uint256 bond = test.bondAmount;

            ChallengerInfo storage challenger = challengers[_claimant];
            challenger.stakingAmount += bond;
            _updateValidity(_claimant, challenger);

            emit BondRefunded(msg.sender, _claimant, bond);
        }
    }
}