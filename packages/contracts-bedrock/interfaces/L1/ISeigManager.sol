// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ISeigManager
/// @notice Interface for TON Staking V3 SeigManager contract
/// @dev Used by L1StandardBridge/OptimismPortal to notify Bridged TON changes
interface ISeigManager {
    /// @notice Called when Bridged TON balance changes
    /// @dev Called by L1StandardBridge/OptimismPortal after TON deposit/withdrawal
    /// @param rollupConfig L2's SystemConfig address (L2 identifier)
    /// @param totalTONTVL Total TON amount in the bridge
    function onBridgedTONChange(address rollupConfig, uint256 totalTONTVL) external;
}
