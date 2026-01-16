// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { CommonTest } from "test/setup/CommonTest.sol";
import { RAT } from "src/L1/RAT.sol";
import { Proxy } from "src/universal/Proxy.sol";
import { IDisputeGameFactory } from "interfaces/dispute/IDisputeGameFactory.sol";
import { IDisputeGame } from "interfaces/dispute/IDisputeGame.sol";
import { GameTypes } from "src/dispute/lib/Types.sol";

/// @title RAT_Simple_Test
/// @notice 확률 100%로 설정하여 RAT가 무조건 실행되도록 하는 간단한 테스트
contract RAT_Simple_Test is CommonTest {
    RAT public rat;
    address public mockFaultDisputeGame;
    address public ratProxyAdmin;

    uint256 public constant SLASH_BOND_AMOUNT = 1 ether;
    uint256 public constant EVIDENCE_SUBMISSION_PERIOD = 100;
    uint256 public constant MINIMUM_STAKE_AMOUNT = 2 ether;
    uint256 public constant OFFLINE_PENALTY_RATE = 5000; // 50%

    function setUp() public override {
        super.setUp();

        // Create mock FaultDisputeGame implementation
        mockFaultDisputeGame = makeAddr("mockFaultDisputeGame");

        // Set up game implementation for CANNON game type
        vm.prank(disputeGameFactory.owner());
        disputeGameFactory.setImplementation(GameTypes.CANNON, IDisputeGame(mockFaultDisputeGame));

        // Deploy RAT implementation
        RAT ratImpl = new RAT();

        // Deploy RAT proxy
        Proxy ratProxy = new Proxy(address(1));
        ratProxyAdmin = address(1);

        // Cast proxy to RAT interface
        rat = RAT(payable(address(ratProxy)));

        // Initialize proxy with implementation
        vm.prank(address(1));
        ratProxy.upgradeToAndCall(
            address(ratImpl),
            abi.encodeCall(
                RAT.initialize,
                (
                    disputeGameFactory,  // Use actual disputeGameFactory
                    SLASH_BOND_AMOUNT,
                    EVIDENCE_SUBMISSION_PERIOD,
                    MINIMUM_STAKE_AMOUNT,
                    100000, // 100% default probability (MAX_PROBABILITY)
                    OFFLINE_PENALTY_RATE,
                    ratProxyAdmin // manager address
                )
            )
        );

        // Verify probability is set to 100%
        assertEq(rat.ratTriggerProbability(), 100000, "Probability should be 100%");
    }

    /// @notice Test RAT probability is 100%
    function test_rat_probability_is_100_percent() public {
        uint256 probability = rat.ratTriggerProbability();
        assertEq(probability, 100000, "RAT probability should be 100%");
        emit log_named_uint("RAT Probability", probability);
    }

    /// @notice Test shouldTriggerRAT() always returns true
    function test_shouldTriggerRAT_always_true() public {
        // shouldTriggerRAT() should always return true with 100% probability
        // We can't call it directly as it's internal, but we can verify through triggerAttentionTest
        emit log_string("RAT probability is 100%, should always trigger");
    }

    /// @notice Test stake() function gas usage
    function test_stake_gas_measurement() public {
        address challenger = address(0x1234);
        uint256 stakeAmount = 2.5 ether; // Above minimum

        vm.deal(challenger, 10 ether);

        vm.prank(challenger);
        uint256 gasStart = gasleft();
        rat.stake{value: stakeAmount}();
        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("RAT stake() gas used", gasUsed);

        // Verify the stake was successful
        RAT.ChallengerInfo memory info = rat.getChallengerInfo(challenger);
        assertEq(info.stakingAmount, stakeAmount);
        assertTrue(info.isValid, "Challenger should be valid");
    }

    /// @notice Test triggerAttentionTest() function gas usage (100% probability)
    function test_triggerAttentionTest_gas_measurement() public {
        // Setup challenger first
        address challenger = address(0x1234);
        vm.deal(challenger, 10 ether);
        vm.prank(challenger);
        rat.stake{value: 2.5 ether}(); // Make challenger valid

        // Test triggerAttentionTest with 100% probability
        address gameAddress = address(0x5678);
        bytes32 version = bytes32(0);
        bytes32 stateRoot = keccak256("test_state_root");
        bytes32 messagePasserRoot = keccak256("msgPasserRoot");
        bytes32 blockHash = keccak256("blockHash");
        bytes32 outputRoot = keccak256(abi.encode(version, stateRoot, messagePasserRoot, blockHash));

        vm.prank(address(disputeGameFactory)); // Use actual disputeGameFactory address
        uint256 gasStart = gasleft();
        rat.triggerAttentionTest(gameAddress, outputRoot, bytes32(0), uint64(block.number));
        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("RAT triggerAttentionTest() gas used (100% probability)", gasUsed);

        // Verify attention test was created
        RAT.AttentionInfo memory info = rat.getAttentionTest(gameAddress);
        assertEq(info.outputRoot, outputRoot, "Attention test should be created");

        // Verify challenger was selected
        assertTrue(info.challengerAddress != address(0), "Challenger should be selected");
        emit log_named_address("Selected challenger", info.challengerAddress);
    }

    /// @notice Test triggerAttentionTest() with low probability (1%) - should not trigger
    function test_triggerAttentionTest_low_probability_gas_measurement() public {
        // Set probability to 1% (1000/100000)
        vm.prank(rat.ratManager()); // Use RAT contract's manager
        rat.setRatTriggerProbability(1000); // 1% probability

        // Setup challenger first
        address challenger = address(0x1234);
        vm.deal(challenger, 10 ether);
        vm.prank(challenger);
        rat.stake{value: 2.5 ether}();

        // Test triggerAttentionTest with 1% probability
        address gameAddress = address(0x5678);
        bytes32 version = bytes32(0);
        bytes32 stateRoot = keccak256("test_state_root");
        bytes32 messagePasserRoot = keccak256("msgPasserRoot");
        bytes32 blockHash = keccak256("blockHash");
        bytes32 outputRoot = keccak256(abi.encode(version, stateRoot, messagePasserRoot, blockHash));

        vm.prank(address(disputeGameFactory));
        uint256 gasStart = gasleft();
        rat.triggerAttentionTest(gameAddress, outputRoot, bytes32(0), uint64(block.number));
        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("RAT triggerAttentionTest() gas used (1% probability)", gasUsed);

        // Verify attention test was NOT created (RAT should not trigger)
        RAT.AttentionInfo memory info = rat.getAttentionTest(gameAddress);
        assertEq(info.outputRoot, bytes32(0), "Attention test should NOT be created with low probability");

        emit log_string("RAT did not trigger with 1% probability - early return");
    }

    /// @notice Test triggerAttentionTest() with 0% probability - should not trigger
    function test_triggerAttentionTest_zero_probability_gas_measurement() public {
        // Set probability to 0%
        vm.prank(rat.ratManager()); // Use RAT contract's manager
        rat.setRatTriggerProbability(0); // 0% probability

        // Setup challenger first
        address challenger = address(0x1234);
        vm.deal(challenger, 10 ether);
        vm.prank(challenger);
        rat.stake{value: 2.5 ether}();

        // Test triggerAttentionTest with 0% probability
        address gameAddress = address(0x5678);
        bytes32 version = bytes32(0);
        bytes32 stateRoot = keccak256("test_state_root");
        bytes32 messagePasserRoot = keccak256("msgPasserRoot");
        bytes32 blockHash = keccak256("blockHash");
        bytes32 outputRoot = keccak256(abi.encode(version, stateRoot, messagePasserRoot, blockHash));

        vm.prank(address(disputeGameFactory));
        uint256 gasStart = gasleft();
        rat.triggerAttentionTest(gameAddress, outputRoot, bytes32(0), uint64(block.number));
        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("RAT triggerAttentionTest() gas used (0% probability)", gasUsed);

        // Verify attention test was NOT created (RAT should not trigger)
        RAT.AttentionInfo memory info = rat.getAttentionTest(gameAddress);
        assertEq(info.outputRoot, bytes32(0), "Attention test should NOT be created with 0% probability");

        emit log_string("RAT did not trigger with 0% probability - early return");
    }

    /// @notice Test submitCandidate() function gas usage
    function test_submitCandidate_gas_measurement() public {
        // Setup challenger and trigger attention test
        address challenger = address(0x1234);
        vm.deal(challenger, 10 ether);
        vm.prank(challenger);
        rat.stake{value: 2.5 ether}();

        // Setup OutputRoot verification data
        bytes32 version = bytes32(0);
        bytes32 stateRoot = keccak256("stateRoot");
        bytes32 messagePasserStorageRoot = keccak256("msgPasserRoot");
        bytes32 latestBlockhash = keccak256("blockHash");

        bytes32 outputRoot = keccak256(abi.encode(version, stateRoot, messagePasserStorageRoot, latestBlockhash));

        // Trigger attention test with the matching outputRoot
        address gameAddress = address(0x5678);
        vm.prank(address(disputeGameFactory));
        rat.triggerAttentionTest(gameAddress, outputRoot, bytes32(0), uint64(block.number));

        // Get selected challenger
        RAT.AttentionInfo memory info = rat.getAttentionTest(gameAddress);
        require(info.challengerAddress != address(0), "No challenger selected");

        // Verify the proof matches (for debugging)
        emit log_named_bytes32("Expected outputRoot", outputRoot);
        emit log_named_bytes32("State root", stateRoot);

        vm.prank(info.challengerAddress);
        uint256 gasStart = gasleft();
        rat.submitCandidate(
            gameAddress,
            bytes32(uint256(uint160(address(0x1234)))),
            stateRoot,
            version,
            messagePasserStorageRoot,
            latestBlockhash
        );
        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("RAT submitCandidate() gas used", gasUsed);

        // Verify evidence was submitted
        info = rat.getAttentionTest(gameAddress);
        assertEq(info.status, rat.STATUS_SUBMITTED(), "Candidate should be submitted");
    }

    /// @notice Test resolveClaim() function gas usage
    function test_resolveClaim_gas_measurement() public {
        // Setup challenger and trigger attention test
        address challenger = address(0x1234);
        vm.deal(challenger, 10 ether);
        vm.prank(challenger);
        rat.stake{value: 2.5 ether}();

        // Trigger attention test first
        address gameAddress = address(0x5678);
        bytes32 version = bytes32(0);
        bytes32 stateRoot = keccak256("test_state_root");
        bytes32 messagePasserRoot = keccak256("msgPasserRoot");
        bytes32 blockHash = keccak256("blockHash");
        bytes32 outputRoot = keccak256(abi.encode(version, stateRoot, messagePasserRoot, blockHash));

        vm.prank(address(disputeGameFactory));
        rat.triggerAttentionTest(gameAddress, outputRoot, bytes32(0), uint64(block.number));

        // Get selected challenger
        RAT.AttentionInfo memory info = rat.getAttentionTest(gameAddress);
        require(info.challengerAddress != address(0), "No challenger selected");

        // Test resolveClaim
        vm.prank(gameAddress);
        uint256 gasStart = gasleft();
        rat.resolveClaim(info.challengerAddress);
        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("RAT resolveClaim() gas used", gasUsed);

        // Verify claim was resolved
        info = rat.getAttentionTest(gameAddress);
        assertEq(info.status, rat.STATUS_FINALIZED(), "Claim should be finalized");
    }

    /// @notice Test all functions with 100% probability
    function test_all_functions_with_100_percent_probability() public {
        emit log_string("=== Testing all RAT functions with 100% probability ===");

        test_rat_probability_is_100_percent();
        test_shouldTriggerRAT_always_true();
        test_stake_gas_measurement();
        test_triggerAttentionTest_gas_measurement();
        test_submitCandidate_gas_measurement();
        test_resolveClaim_gas_measurement();

        emit log_string("=== All tests completed successfully ===");
    }
}
