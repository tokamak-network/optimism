// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { IWinningChallengerTracker } from "./IWinningChallengerTracker.sol";

/// @title WinningChallengerTracker
/// @notice Tracks winning challengers across multiple dispute games
/// @dev This contract is designed to be deployed once and used by multiple FaultDisputeGame instances
contract WinningChallengerTracker is IWinningChallengerTracker {
    /// @notice Mapping from game address to challenger address to winner status
    mapping(address => mapping(address => bool)) private _isWinner;

    /// @notice Mapping from game address to array of winning challengers
    mapping(address => address[]) private _winners;

    /// @notice Emitted when a winning challenger is recorded
    /// @param game The dispute game address
    /// @param winner The winning challenger address
    event WinnerRecorded(address indexed game, address indexed winner);

    /// @inheritdoc IWinningChallengerTracker
    function recordWinner(address game, address winner, address gameCreator) external override {
        // Only the game contract itself can record winners
        require(msg.sender == game, "WinningChallengerTracker: caller must be the game");

        // Game creator (Proposer) is excluded from winners
        if (winner == gameCreator) return;

        // Skip if already recorded (no duplicates)
        if (_isWinner[game][winner]) return;

        // Record the winner
        _isWinner[game][winner] = true;
        _winners[game].push(winner);

        emit WinnerRecorded(game, winner);
    }

    /// @inheritdoc IWinningChallengerTracker
    function getWinningChallengers(address game) external view override returns (address[] memory) {
        return _winners[game];
    }

    /// @inheritdoc IWinningChallengerTracker
    function getWinningChallengersCount(address game) external view override returns (uint256) {
        return _winners[game].length;
    }

    /// @inheritdoc IWinningChallengerTracker
    function isWinningChallenger(address game, address challenger) external view override returns (bool) {
        return _isWinner[game][challenger];
    }
}
