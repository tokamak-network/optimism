// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IRAT
/// @notice Interface for TON Staking V3 RAT (Randomized Attention Test) contract
/// @dev Optimism uses this interface to interact with TON Staking V3 RAT
/// @dev Matches TON Staking V2 IRAT interface
interface IRAT {
    /// @notice Triggers attention test (called by DisputeGameFactory)
    /// @dev Called when a DisputeGame is created
    /// @dev RAT identifies the game via msg.sender (DisputeGameFactory) context
    /// @param systemConfig L2's SystemConfig address (L2 identifier)
    /// @param batchIndex Batch/game index
    /// @param batchHash Batch hash or Output Root
    /// @param blockHash Block hash (used for random validator selection)
    function triggerAttentionTest(
        address systemConfig,
        uint32 batchIndex,
        bytes32 batchHash,
        bytes32 blockHash
    ) external;

    /// @notice Called when a claim is resolved in FaultDisputeGame
    /// @dev RAT identifies the game via msg.sender (FaultDisputeGame address)
    /// @param claimant Address to receive the bond refund (game winner)
    function resolveClaim(address claimant) external;
}
