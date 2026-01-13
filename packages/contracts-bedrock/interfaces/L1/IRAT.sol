// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IProxyAdminOwnedBase } from "interfaces/L1/IProxyAdminOwnedBase.sol";
import { IReinitializableBase } from "interfaces/universal/IReinitializableBase.sol";

/// @title IRAT
/// @notice Interface for the Randomized Attention Test contract (v2)
interface IRAT is IProxyAdminOwnedBase, IReinitializableBase {

    // ============ Structs ============

    struct ChallengerInfo {
        uint256 stakingAmount;
        uint256 totalSlashedAmount;
        uint32 validatorIndex;
        bool isValid;
    }

    struct AttentionInfo {
        bytes32 outputRoot;
        bytes32 seed;
        bytes32 candidateKey;
        uint96 bondAmount;
        address challengerAddress;
        uint64 submissionDeadlineBlock;
        uint64 l2BlockNumber;
        uint8 status;
    }

    // ============ Events ============

    event ChallengerStaked(address indexed challenger, uint256 amount);
    event AttentionTriggered(address indexed gameAddress, address indexed challenger, bytes32 seed);
    event CandidateSubmitted(address indexed gameAddress, address indexed challenger, bytes32 candidateKey, uint256 distance);
    event DisputeSuccessful(address indexed gameAddress, address indexed disputer, bytes32 key, uint256 amount, string reason);
    event OfflinePenalty(address indexed gameAddress, address indexed challenger, uint256 penalty);
    event SubmissionAccepted(address indexed gameAddress, address indexed challenger, bytes32 candidateKey);
    event BondRefunded(address indexed gameAddress, address indexed challenger, uint256 refundedAmount);

    // ============ Core Functions ============

    function stake() external payable;

    function triggerAttentionTest(
        address _gameAddress,
        bytes32 _outputRoot,
        bytes32 _blockHash,
        uint64 _l2BlockNumber
    ) external;

    function submitCandidate(
        address _gameAddress,
        bytes32 _candidateKey,
        bytes32 _stateRoot,
        bytes32 _version,
        bytes32 _messagePasserRoot,
        bytes32 _blockHash
    ) external;

    function disputeByNonInclusion(
        address _gameAddress,
        bytes32 _provenKey,
        bytes32 _stateRoot,
        bytes32 _version,
        bytes32 _messagePasserRoot,
        bytes32 _blockHash,
        bytes[] calldata _proof
    ) external;



    function disputeByCloserKey(
        address _gameAddress,
        bytes32 _closerKey,
        bytes32 _stateRoot,
        bytes32 _version,
        bytes32 _messagePasserRoot,
        bytes32 _blockHash,
        bytes[] calldata _proof
    ) external;



    function resolveClaim(address _claimant) external;

    // ============ View Functions ============

    function getChallengerInfo(address _challenger) external view returns (ChallengerInfo memory);
    function getValidChallengerCount() external view returns (uint256);
    function getAttentionTest(address _gameAddress) external view returns (AttentionInfo memory);
    function version() external view returns (string memory);

    // ============ Admin Functions ============

    function setPerTestBondAmount(uint256 _amount) external;
    function setEvidenceSubmissionPeriod(uint256 _period) external;
    function setMinimumStakingBalance(uint256 _balance) external;
    function setOfflinePenaltyRate(uint256 _rate) external;
    function setRatTriggerProbability(uint256 _probability) external;
}