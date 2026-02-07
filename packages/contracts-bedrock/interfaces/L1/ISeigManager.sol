// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ISeigManager
/// @notice Interface for TON Staking V3 SeigManager contract
/// @dev Used by OptimismPortal to notify Bridged TON changes
interface ISeigManager {
    /// @notice Called when Bridged TON balance changes (Type 3 only)
    /// @dev Called by OptimismPortal after TON deposit/withdrawal
    ///      SeigManager automatically queries rollupConfig from msg.sender (OptimismPortal)
    ///      via L1BridgeRegistry.rollupConfigWithPortal()
    ///      This is a trigger function - uses early return instead of revert
    function onBridgedTonChange() external;
}
