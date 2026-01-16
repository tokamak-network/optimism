// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { RAT } from "src/L1/RAT.sol";

/// @notice A RAT implementation that makes proof checks controllable in unit tests.
///         This allows us to test both "valid dispute succeeds" and "invalid dispute fails"
///         without needing to generate real MPT proofs in Foundry.
contract TestableRAT is RAT {
    bytes32 internal constant PROOF_EXISTS = keccak256("EXISTS");
    bytes32 internal constant PROOF_MISSING = keccak256("MISSING");

    function _verifyExistence(bytes memory, bytes[] calldata _proof, bytes32) internal pure override {
        if (_proof.length == 0) revert ProofVerificationFailed();
        if (keccak256(_proof[0]) != PROOF_EXISTS) revert ProofVerificationFailed();
    }

    function _verifyNonInclusion(address, bytes[] calldata _proof, bytes32) internal pure override {
        if (_proof.length == 0) revert ProofVerificationFailed();
        bytes32 tag = keccak256(_proof[0]);
        if (tag == PROOF_EXISTS) revert KeyExists();
        if (tag != PROOF_MISSING) revert ProofVerificationFailed();
    }
}

