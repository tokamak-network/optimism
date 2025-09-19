// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

/// @title TestContract
/// @notice A simple test contract to verify artifact inclusion in op-deployer
/// @dev Updated to trigger rebuild
contract TestContract {
    string public message;

    constructor(string memory _message) {
        message = _message;
    }

    function setMessage(string memory _message) external {
        message = _message;
    }

    function getMessage() external view returns (string memory) {
        return message;
    }

    function getVersion() external pure returns (string memory) {
        return "v1.0.0";
    }
}
