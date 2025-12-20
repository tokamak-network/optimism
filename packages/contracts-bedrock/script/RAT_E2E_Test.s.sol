// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {Script, console2} from "forge-std/Script.sol";
import {RAT} from "src/L1/RAT.sol";
import {Proxy} from "src/universal/Proxy.sol";

/// @title RAT E2E Test Script
/// @notice Tests the 17-children branch node proof system on local Anvil
contract RATe2eTest is Script {
    RAT public rat;
    RAT public ratProxy;
    address public disputeGameFactory;
    address public challenger;

    function setUp() public {
        // Use Anvil default accounts
        disputeGameFactory = address(0x1234);
        challenger = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // Anvil account 0
    }

    function run() public {
        console2.log("=== RAT E2E Test with 17-Children Proof ===");

        // Deploy
        vm.startBroadcast();

        // Deploy RAT implementation
        RAT ratImpl = new RAT();
        console2.log("RAT Implementation deployed:", address(ratImpl));

        // Deploy Proxy
        Proxy proxy = new Proxy(msg.sender);
        console2.log("Proxy deployed:", address(proxy));

        // Initialize through proxy
        // RAT.initialize(IDisputeGameFactory, perTestBondAmount, evidenceSubmissionPeriod, minimumStakingBalance, ratTriggerProbability, manager)
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,uint256,uint256,uint256,uint256,address)",
            disputeGameFactory,   // _disputeGameFactory
            500,                  // _perTestBondAmount
            100,                  // _evidenceSubmissionPeriod (blocks)
            1000,                 // _minimumStakingBalance
            50000,                // _ratTriggerProbability (50%)
            msg.sender            // _manager
        );
        proxy.upgradeToAndCall(address(ratImpl), initData);

        ratProxy = RAT(address(proxy));
        console2.log("RAT Proxy initialized");

        // Stake as challenger
        ratProxy.stake{value: 0.01 ether}();
        console2.log("Challenger staked 0.01 ETH");

        // Create test data with 17 branch node children
        bytes32[17] memory stateTrieNode;
        for (uint i = 0; i < 17; i++) {
            stateTrieNode[i] = keccak256(abi.encode("state_trie_child", i));
        }
        bytes32 stateRoot = keccak256(abi.encodePacked(stateTrieNode));
        bytes32 version = bytes32(0);
        bytes32 storageRoot = keccak256("storage_root");
        // Safe blockhash calculation - use block.number if at genesis
        bytes32 blockHash = block.number > 0 ? blockhash(block.number - 1) : bytes32(uint256(1));
        bytes32 outputRoot = keccak256(abi.encode(version, stateRoot, storageRoot, blockHash));

        address gameAddress = address(0x5678);

        // Set probability to 100%
        ratProxy.setRatTriggerProbability(100000);

        vm.stopBroadcast();

        // Trigger attention test (as dispute game factory)
        vm.prank(disputeGameFactory);
        ratProxy.triggerAttentionTest(gameAddress, outputRoot, blockHash);
        console2.log("Attention test triggered for game:", gameAddress);

        // Get selected challenger
        (, , address selectedChallenger, , ) = ratProxy.attentionTests(gameAddress);
        console2.log("Selected challenger:", selectedChallenger);

        // Submit evidence
        vm.prank(selectedChallenger);
        uint256 gasBefore = gasleft();
        ratProxy.submitCorrectEvidence(gameAddress, version, stateTrieNode, storageRoot, blockHash);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("=== RESULTS ===");
        console2.log("Evidence submitted successfully!");
        console2.log("Gas used for submitCorrectEvidence:", gasUsed);

        // Verify
        (, , , , bool evidenceSubmitted) = ratProxy.attentionTests(gameAddress);
        require(evidenceSubmitted, "Evidence not marked as submitted");
        console2.log("Evidence verified: TRUE");

        console2.log("\n=== E2E TEST PASSED ===");
    }
}
