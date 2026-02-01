// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

/// @title IWinningChallengerTracker
/// @notice Interface for tracking winning challengers in dispute games
interface IWinningChallengerTracker {
    /// @notice Records a winning challenger for a specific game
    /// @param game The address of the dispute game
    /// @param winner The address of the winning challenger
    /// @param gameCreator The address of the game creator (to exclude from winners)
    function recordWinner(address game, address winner, address gameCreator) external;

    /// @notice Returns all winning challengers for a specific game
    /// @param game The address of the dispute game
    /// @return Array of winning challenger addresses
    function getWinningChallengers(address game) external view returns (address[] memory);

    /// @notice Returns the count of winning challengers for a specific game
    /// @param game The address of the dispute game
    /// @return Number of winning challengers
    function getWinningChallengersCount(address game) external view returns (uint256);

    /// @notice Checks if an address is a winning challenger for a specific game
    /// @param game The address of the dispute game
    /// @param challenger The address to check
    /// @return True if the address is a winning challenger
    function isWinningChallenger(address game, address challenger) external view returns (bool);
}
