// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { GameId, Claim } from "src/dispute/lib/Types.sol";

/// @title IRAT
/// @notice Interface for the RAT (Randomized Attention Test) contract.
interface IRAT {
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

    /// @notice Allows challengers to stake ETH
    function stake() external payable;

    /// @notice Gets challenger information
    /// @param _challenger Address of the challenger
    /// @return Challenger information
    function getChallengerInfo(address _challenger) external view returns (ChallengerInfo memory);

    /// @notice Gets total number of challengers
    /// @return Total number of challengers
    function getTotalChallengers() external view returns (uint256);

    /// @notice Gets the number of valid challengers
    /// @return Number of valid challengers
    function getValidChallengersCount() external view returns (uint256);

    /// @notice Gets the number of invalid challengers
    /// @return Number of invalid challengers
    function getInvalidChallengersCount() external view returns (uint256);

    /// @notice Gets attention information for a game
    /// @param _gameId The GameId to get attention info for
    /// @return Attention information
    function getAttentionInfo(GameId _gameId) external view returns (AttentionInfo memory);

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
    ) external;

    /// @notice Submit evidence that the state root is correct
    /// @param _gameAddress Address of the FaultDisputeGame
    /// @param _proofLV Left value for state root calculation
    /// @param _proofRV Right value for state root calculation
    function submitCorrectEvidence(
        address _gameAddress,
        bytes32 _proofLV,
        bytes32 _proofRV
    ) external;

    /// @notice Submit evidence that the state root is incorrect by starting a fault dispute game
    /// @param _gameAddress Address of the FaultDisputeGame
    /// @param _claim The claim at the relative attack position
    function submitIncorrectEvidence(
        address _gameAddress,
        Claim _claim
    ) external payable;

    /// @notice Resolve function called when challenger wins a game
    function resolve() external;
}