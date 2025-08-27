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

    /// @notice Allows challengers to stake ETH
    function stake() external payable;

    /// @notice Gets challenger information
    /// @param _challenger Address of the challenger
    /// @return Challenger information
    function getChallengerInfo(address _challenger) external view returns (ChallengerInfo memory);

    /// @notice Gets total number of challengers
    /// @return Total number of challengers
    function getTotalChallengers() external view returns (uint256);

    /// @notice Gets number of valid challengers
    /// @return Number of valid challengers
    function getValidChallengerCount() external view returns (uint256);

    /// @notice Gets number of invalid challengers
    /// @return Number of invalid challengers
    function getInvalidChallengerCount() external view returns (uint256);

    /// @notice Triggers attention test (called by DisputeGameFactory)
    /// @param _gameId Game ID
    /// @param _stateRoot State root to be verified
    /// @param _blockHash Block hash for validator selection
    /// @param _l2BlockNumber L2 block number
    function triggerAttentionTest(GameId _gameId, bytes32 _stateRoot, bytes32 _blockHash, uint256 _l2BlockNumber) external;

    /// @notice Submits correct evidence for attention test
    /// @param _gameAddress Game contract address
    /// @param _proofLV Left child state value
    /// @param _proofRV Right child state value
    function submitCorrectEvidence(address _gameAddress, bytes32 _proofLV, bytes32 _proofRV) external;

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