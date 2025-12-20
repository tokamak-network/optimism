// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { GameId } from "src/dispute/lib/Types.sol";
import { IProxyAdminOwnedBase } from "interfaces/L1/IProxyAdminOwnedBase.sol";
import { IReinitializableBase } from "interfaces/universal/IReinitializableBase.sol";

/// @title IRAT
/// @notice Interface for the Randomized Attention Test contract
interface IRAT is IProxyAdminOwnedBase, IReinitializableBase {
    /// @notice Challenger information structure
    /// @dev Packed to minimize storage slots
    struct ChallengerInfo {
        uint256 stakingAmount;      // Slot 1: 32 bytes
        uint256 slashedAmount;      // Slot 2: 32 bytes
        uint32 validatorIndex;      // Slot 3: 4 bytes
        bool isValid;               // Slot 3: 1 byte (packed)
    }

    /// @notice Attention test information structure
    /// @dev Packed to minimize storage slots
    struct AttentionInfo {
        bytes32 outputRoot;              // Slot 1: 32 bytes (the OutputRoot being challenged)
        uint96 bondAmount;               // Slot 2: 12 bytes (packed with challengerAddress)
        address challengerAddress;       // Slot 2: 20 bytes (packed with bondAmount)
        uint64 submissionDeadlineBlock;  // Slot 3: 8 bytes (L1 block deadline for evidence)
        uint64 l2BlockNumber;            // Slot 3: 8 bytes (L2 block number for proof data)
        bool evidenceSubmitted;          // Slot 3: 1 byte (packed)
    }

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

    /// @notice Allows challengers to stake ETH
    function stake() external payable;

    /// @notice Gets challenger information
    /// @param _challenger Address of the challenger
    /// @return Challenger information
    function getChallengerInfo(address _challenger) external view returns (ChallengerInfo memory);



    /// @notice Gets number of valid challengers
    /// @return Number of valid challengers
    function getValidChallengerCount() external view returns (uint256);

    /// @notice Gets number of invalid challengers
    /// @return Number of invalid challengers
    function getInvalidChallengerCount() external view returns (uint256);

    /// @notice Triggers attention test (called by DisputeGameFactory)
    /// @param _gameAddress Game contract address
    /// @param _outputRoot Output root to be verified
    /// @param _blockHash Block hash for validator selection
    /// @param _l2BlockNumber L2 block number used to generate the output root
    function triggerAttentionTest(address _gameAddress, bytes32 _outputRoot, bytes32 _blockHash, uint64 _l2BlockNumber) external;

    /// @notice Submits correct evidence for attention test
    /// @param _gameAddress Game contract address
    /// @param _version Version of the output root (always 0)
    /// @param _stateTrieNodeRLP Raw RLP-encoded state trie root node
    /// @param _messagePasserStorageRoot Root of the message passer storage trie
    /// @param _latestBlockhash Hash of the block this output was generated from
    function submitCorrectEvidence(
        address _gameAddress,
        bytes32 _version,
        bytes memory _stateTrieNodeRLP,
        bytes32 _messagePasserStorageRoot,
        bytes32 _latestBlockhash
    ) external;

    /// @notice Called when a claim is resolved in FaultDisputeGame
    /// @param _claimant Address receiving the bond refund
    function resolveClaim(address _claimant) external;

    /// @notice Sets the per-test slashing amount
    /// @param _amount New slashing amount
    function setPerTestSlashingAmount(uint256 _amount) external;

    /// @notice Sets the evidence submission period
    /// @param _period New submission period in blocks
    function setEvidenceSubmissionPeriod(uint256 _period) external;

    /// @notice Sets the minimum staking balance
    /// @param _balance New minimum staking balance
    function setMinimumStakingBalance(uint256 _balance) external;

    /// @notice Returns the version
    function version() external view returns (string memory);
}