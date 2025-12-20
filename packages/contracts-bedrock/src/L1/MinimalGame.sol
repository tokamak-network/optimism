// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "src/dispute/lib/Types.sol";

/// @notice A fake clone used for testing.
contract MinimalGame {
    function initialize() external payable {
        // noop
    }

    function extraData() external pure returns (bytes memory) {
        return hex"FF0420";
    }

    function parentHash() external pure returns (bytes32) {
        return bytes32(0);
    }

    function rootClaim() external pure returns (Claim) {
        return Claim.wrap(bytes32(0));
    }
}
