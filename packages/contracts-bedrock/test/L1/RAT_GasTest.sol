// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { CommonTest } from "test/setup/CommonTest.sol";
import { RAT } from "src/L1/RAT.sol";
import { Proxy } from "src/universal/Proxy.sol";
import { IDisputeGameFactory } from "interfaces/dispute/IDisputeGameFactory.sol";
import { IDisputeGame } from "interfaces/dispute/IDisputeGame.sol";
import { GameTypes } from "src/dispute/lib/Types.sol";

/// @title RAT_GasTest
/// @notice Gas measurement tests for RAT contract
contract RAT_GasTest is CommonTest {
    RAT public rat;
    address public mockDisputeGameFactory;
    address public mockFaultDisputeGame;

    uint256 public constant SLASH_BOND_AMOUNT = 1 ether;
    uint256 public constant EVIDENCE_SUBMISSION_PERIOD = 100;
    uint256 public constant MINIMUM_STAKE_AMOUNT = 2 ether; // Must be >= SLASH_BOND_AMOUNT (1 ether)

    function setUp() public override {
        super.setUp(); // CommonTest의 setUp()을 먼저 호출

        // Use actual disputeGameFactory from CommonTest
        mockDisputeGameFactory = address(disputeGameFactory);
        mockFaultDisputeGame = makeAddr("mockFaultDisputeGame");

        // Set up game implementation for CANNON game type
        // This is needed to avoid NoImplementation(0) error
        vm.prank(disputeGameFactory.owner());
        disputeGameFactory.setImplementation(GameTypes.CANNON, IDisputeGame(mockFaultDisputeGame));

        // Deploy RAT implementation
        RAT ratImpl = new RAT();

        // Deploy RAT proxy with address(1) as admin (same as RAT.t.sol)
        Proxy ratProxy = new Proxy(address(1));

        // Cast proxy to RAT interface
        rat = RAT(payable(address(ratProxy)));

        // Initialize proxy with implementation (same as RAT.t.sol)
        vm.prank(address(1));
        ratProxy.upgradeToAndCall(
            address(ratImpl),
            abi.encodeCall(
                RAT.initialize,
                (
                    IDisputeGameFactory(mockDisputeGameFactory),
                    SLASH_BOND_AMOUNT,
                    EVIDENCE_SUBMISSION_PERIOD,
                    MINIMUM_STAKE_AMOUNT,
                    100000, // 100% default probability (MAX_PROBABILITY)
                    address(1) // manager address
                )
            )
        );

        // Set probability to 100% to ensure RAT always triggers
        vm.prank(address(1)); // proxy admin owner
        rat.setRatTriggerProbability(100000); // MAX_PROBABILITY
    }

    /// @notice Test stake() function gas usage
    function test_stake_gas_measurement() public {
        address challenger = address(0x1234);
        uint256 stakeAmount = 0.2 ether;

        vm.deal(challenger, 10 ether);

        vm.prank(challenger);
        uint256 gasStart = gasleft();
        rat.stake{value: stakeAmount}();
        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("RAT stake() gas used", gasUsed);

        // Verify the stake was successful
        RAT.ChallengerInfo memory info = rat.getChallengerInfo(challenger);
        assertEq(info.stakingAmount, stakeAmount);
    }

    /// @notice Test stake() function gas usage for valid challenger
    function test_stake_valid_challenger_gas_measurement() public {
        address challenger = address(0x1234);
        uint256 stakeAmount = 2 ether; // Above perTestSlashingAmount

        vm.deal(challenger, 10 ether);

        vm.prank(challenger);
        uint256 gasStart = gasleft();
        rat.stake{value: stakeAmount}();
        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("RAT stake() valid challenger gas used", gasUsed);

        // Verify the challenger is valid
        RAT.ChallengerInfo memory info = rat.getChallengerInfo(challenger);
        assertTrue(info.isValid);
    }

    /// @notice Test triggerAttentionTest() function gas usage
    function test_triggerAttentionTest_gas_measurement() public {
        // Setup challenger first
        address challenger = address(0x1234);
        vm.deal(challenger, 10 ether);
        vm.prank(challenger);
        rat.stake{value: 2 ether}(); // Make challenger valid

        // Set probability to 100% to ensure trigger
        vm.prank(address(1)); // proxy admin owner
        rat.setRatTriggerProbability(100000); // MAX_PROBABILITY

        // Test triggerAttentionTest
        address gameAddress = address(0x5678);
        bytes32 stateRoot = keccak256("test_state_root");
        bytes32 blockHash = blockhash(block.number - 1);

        vm.prank(mockDisputeGameFactory);
        uint256 gasStart = gasleft();
        rat.triggerAttentionTest(gameAddress, stateRoot, blockHash, uint64(block.number));
        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("RAT triggerAttentionTest() gas used", gasUsed);

        // Verify attention test was created
        (bytes32 storedStateRoot, , , , ) = rat.attentionTests(gameAddress);
        assertEq(storedStateRoot, stateRoot);
    }

    /// @notice Test triggerAttentionTest() with no valid challengers (should be ignored)
    function test_triggerAttentionTest_no_valid_challengers_gas_measurement() public {
        // Don't setup any challengers - only dummy address(0) exists

        // Test triggerAttentionTest with no valid challengers
        address gameAddress = address(0x5678);
        bytes32 stateRoot = keccak256("test_state_root");
        bytes32 blockHash = blockhash(block.number - 1);

        vm.prank(mockDisputeGameFactory);
        uint256 gasStart = gasleft();
        rat.triggerAttentionTest(gameAddress, stateRoot, blockHash, uint64(block.number));
        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("RAT triggerAttentionTest() no valid challengers gas used", gasUsed);

        // Verify no attention test was created (should be ignored)
        (bytes32 storedStateRoot, , , , ) = rat.attentionTests(gameAddress);
        assertEq(storedStateRoot, bytes32(0)); // Should be empty
    }

    /// @notice Test submitCorrectEvidence() function gas usage
    function test_submitCorrectEvidence_gas_measurement() public {
        // Setup challenger and trigger attention test
        address challenger = address(0x1234);
        vm.deal(challenger, 10 ether);
        vm.prank(challenger);
        rat.stake{value: 2 ether}();

        // Set probability to 100% to ensure trigger
        vm.prank(address(1)); // proxy admin owner
        rat.setRatTriggerProbability(100000); // MAX_PROBABILITY

        // Setup OutputRoot verification data
        address gameAddress = address(0x5678);
        bytes32 version = bytes32(0);
        bytes memory stateTrieNodeRLP = hex"f8918080a0abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234a0ef561234ef561234ef561234ef561234ef561234ef561234ef561234ef5612348080808080808080808080";
        bytes32 messagePasserStorageRoot = keccak256("msgPasserRoot");
        bytes32 latestBlockhash = keccak256("blockHash");

        bytes32 stateRoot = keccak256(stateTrieNodeRLP);
        bytes32 outputRoot = keccak256(abi.encode(version, stateRoot, messagePasserStorageRoot, latestBlockhash));

        vm.prank(mockDisputeGameFactory);
        uint256 gasStart1 = gasleft();
        rat.triggerAttentionTest(gameAddress, outputRoot, blockhash(block.number - 1, uint64(block.number)));
        uint256 gasUsed1 = gasStart1 - gasleft();

        emit log_named_uint("RAT triggerAttentionTest() gas used", gasUsed1);

        // Check challenger balance before evidence submission
        uint256 balanceBefore = challenger.balance;
        RAT.ChallengerInfo memory infoBefore = rat.getChallengerInfo(challenger);

        // Test submitCorrectEvidence
        vm.prank(challenger);
        uint256 gasStart2 = gasleft();
        rat.submitCorrectEvidence(gameAddress, version, stateTrieNodeRLP, messagePasserStorageRoot, latestBlockhash);
        uint256 gasUsed2 = gasStart2 - gasleft();

        emit log_named_uint("RAT submitCorrectEvidence() gas used", gasUsed2);

        // Check challenger balance after evidence submission
        uint256 balanceAfter = challenger.balance;
        RAT.ChallengerInfo memory infoAfter = rat.getChallengerInfo(challenger);

        // // Log bond refund information
        // emit log_named_uint("Challenger balance before", balanceBefore);
        // emit log_named_uint("Challenger balance after", balanceAfter);
        // emit log_named_uint("Balance difference", balanceAfter - balanceBefore);
        // emit log_named_uint("Staking amount before", infoBefore.stakingAmount);
        // emit log_named_uint("Staking amount after", infoAfter.stakingAmount);

        // Verify evidence was submitted
        (, , , , , bool evidenceSubmitted) = rat.attentionTests(gameAddress);
        assertTrue(evidenceSubmitted);

        // Verify bond was refunded to staking amount (not as ETH)
        assertEq(infoAfter.stakingAmount, infoBefore.stakingAmount + SLASH_BOND_AMOUNT, "Bond should be added to staking amount");
        assertEq(balanceAfter, balanceBefore, "Balance should remain unchanged (bond refunded to staking)");
    }

    /// @notice Test resolveClaim() function gas usage
    function test_resolveClaim_gas_measurement() public {
        // Setup challenger and trigger attention test
        address challenger = address(0x1234);
        vm.deal(challenger, 10 ether);
        vm.prank(challenger);
        rat.stake{value: 2 ether}();

        // Set probability to 100% to ensure trigger
        vm.prank(address(1)); // proxy admin owner
        rat.setRatTriggerProbability(100000); // MAX_PROBABILITY

        address gameAddress = address(0x5678);
        bytes32 stateRoot = keccak256("test_state_root");

        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, stateRoot, blockhash(block.number - 1, uint64(block.number)));

        // Test resolveClaim
        vm.prank(gameAddress);
        uint256 gasStart = gasleft();
        rat.resolveClaim(challenger);
        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("RAT resolveClaim() gas used", gasUsed);

        // Verify claim was resolved
        (, , , , , bool evidenceSubmitted) = rat.attentionTests(gameAddress);
        assertTrue(evidenceSubmitted);
    }

    /// @notice Test resolveClaim() with wrong claimant (should be ignored)
    function test_resolveClaim_wrong_claimant_gas_measurement() public {
        // Setup challenger and trigger attention test
        address challenger = address(0x1234);
        vm.deal(challenger, 10 ether);
        vm.prank(challenger);
        rat.stake{value: 2 ether}();

        address gameAddress = address(0x5678);
        bytes32 stateRoot = keccak256("test_state_root");

        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, stateRoot, blockhash(block.number - 1, uint64(block.number)));

        // Test resolveClaim with wrong claimant
        address wrongClaimant = address(0x9999);
        vm.prank(gameAddress);
        uint256 gasStart = gasleft();
        rat.resolveClaim(wrongClaimant);
        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("RAT resolveClaim() wrong claimant gas used", gasUsed);

        // Verify nothing changed (should be ignored)
        (, , , , , bool evidenceSubmitted) = rat.attentionTests(gameAddress);
        assertFalse(evidenceSubmitted);
    }

    /// @notice Test submitCorrectEvidence() with wrong proof (should revert)
    function test_submitCorrectEvidence_wrong_proof_gas_measurement() public {
        // Setup challenger and trigger attention test
        address challenger = address(0x1234);
        vm.deal(challenger, 10 ether);
        vm.prank(challenger);
        rat.stake{value: 2 ether}();

        // Set probability to 100% to ensure trigger
        vm.prank(address(1)); // proxy admin owner
        rat.setRatTriggerProbability(100000); // MAX_PROBABILITY

        // Setup OutputRoot verification data
        address gameAddress = address(0x5678);
        bytes32 version = bytes32(0);
        bytes memory stateTrieNodeRLP = hex"f8918080a0abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234a0ef561234ef561234ef561234ef561234ef561234ef561234ef561234ef5612348080808080808080808080";
        bytes32 messagePasserStorageRoot = keccak256("msgPasserRoot");
        bytes32 latestBlockhash = keccak256("blockHash");

        bytes32 stateRoot = keccak256(stateTrieNodeRLP);
        bytes32 outputRoot = keccak256(abi.encode(version, stateRoot, messagePasserStorageRoot, latestBlockhash));

        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, outputRoot, blockhash(block.number - 1, uint64(block.number)));

        // Test submitCorrectEvidence with wrong proof
        bytes memory wrongStateTrieNodeRLP = hex"f891809999";

        vm.prank(challenger);
        uint256 gasStart = gasleft();
        try rat.submitCorrectEvidence(gameAddress, version, wrongStateTrieNodeRLP, messagePasserStorageRoot, latestBlockhash) {
            fail();
        } catch {
            uint256 gasUsed = gasStart - gasleft();
            emit log_named_uint("RAT submitCorrectEvidence() wrong proof gas used (revert)", gasUsed);
        }
    }

    /// @notice Test submitCorrectEvidence() with wrong challenger (should revert)
    function test_submitCorrectEvidence_wrong_challenger_gas_measurement() public {
        // Setup challenger and trigger attention test
        address challenger = address(0x1234);
        vm.deal(challenger, 10 ether);
        vm.prank(challenger);
        rat.stake{value: 2 ether}();

        // Set probability to 100% to ensure trigger
        vm.prank(address(1)); // proxy admin owner
        rat.setRatTriggerProbability(100000); // MAX_PROBABILITY

        // Setup OutputRoot verification data
        address gameAddress = address(0x5678);
        bytes32 version = bytes32(0);
        bytes memory stateTrieNodeRLP = hex"f8918080a0abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234a0ef561234ef561234ef561234ef561234ef561234ef561234ef561234ef5612348080808080808080808080";
        bytes32 messagePasserStorageRoot = keccak256("msgPasserRoot");
        bytes32 latestBlockhash = keccak256("blockHash");

        bytes32 stateRoot = keccak256(stateTrieNodeRLP);
        bytes32 outputRoot = keccak256(abi.encode(version, stateRoot, messagePasserStorageRoot, latestBlockhash));

        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, outputRoot, blockhash(block.number - 1, uint64(block.number)));

        // Test submitCorrectEvidence with wrong challenger
        address wrongChallenger = address(0x9999);
        vm.prank(wrongChallenger);
        uint256 gasStart = gasleft();
        try rat.submitCorrectEvidence(gameAddress, version, stateTrieNodeRLP, messagePasserStorageRoot, latestBlockhash) {
            fail();
        } catch {
            uint256 gasUsed = gasStart - gasleft();
            emit log_named_uint("RAT submitCorrectEvidence() wrong challenger gas used (revert)", gasUsed);
        }
    }

    /// @notice Test submitCorrectEvidence() for non-existent test (should revert)
    function test_submitCorrectEvidence_nonexistent_test_gas_measurement() public {
        // Setup challenger
        address challenger = address(0x1234);
        vm.deal(challenger, 10 ether);
        vm.prank(challenger);
        rat.stake{value: 2 ether}();

        // Test submitCorrectEvidence for non-existent game
        address nonExistentGame = address(0x8888);
        bytes32 version = bytes32(0);
        bytes memory stateTrieNodeRLP = hex"f8918080a0abcd1234";
        bytes32 messagePasserStorageRoot = keccak256("msgPasserRoot");
        bytes32 latestBlockhash = keccak256("blockHash");

        vm.prank(challenger);
        uint256 gasStart = gasleft();
        try rat.submitCorrectEvidence(nonExistentGame, version, stateTrieNodeRLP, messagePasserStorageRoot, latestBlockhash) {
            fail();
        } catch {
            uint256 gasUsed = gasStart - gasleft();
            emit log_named_uint("RAT submitCorrectEvidence() non-existent test gas used (revert)", gasUsed);
        }
    }

    /// @notice Test getChallengerInfo() function gas usage (view function)
    function test_getChallengerInfo_gas_measurement() public {
        // Setup challenger first
        address challenger = address(0x1234);
        vm.deal(challenger, 10 ether);
        vm.prank(challenger);
        rat.stake{value: 2 ether}();

        // Test getChallengerInfo - view functions don't consume gas in the same way
        RAT.ChallengerInfo memory info = rat.getChallengerInfo(challenger);

        emit log_named_uint("RAT getChallengerInfo() - view function (no gas cost)", 0);

        // Verify info is correct
        assertEq(info.stakingAmount, 2 ether);
        assertTrue(info.isValid);
    }

    /// @notice Test getValidChallengerCount() function gas usage (view function)
    function test_getValidChallengerCount_gas_measurement() public {
        // Setup challenger first
        address challenger = address(0x1234);
        vm.deal(challenger, 10 ether);
        vm.prank(challenger);
        rat.stake{value: 2 ether}();

        // Test getValidChallengerCount - view functions don't consume gas in the same way
        uint256 count = rat.getValidChallengerCount();

        emit log_named_uint("RAT getValidChallengerCount() - view function (no gas cost)", 0);

        // Verify count is correct
        assertEq(count, 2); // 1 for dummy address(0) + 1 for challenger
    }

    /// @notice Test triggerAttentionTest() with probability = 0 (never trigger)
    function test_triggerAttentionTest_probability_zero_gas_measurement() public {
        // Setup challenger first
        address challenger = address(0x1234);
        vm.deal(challenger, 10 ether);
        vm.prank(challenger);
        rat.stake{value: 2 ether}();

        // Set probability to 0 (never trigger)
        vm.prank(address(1)); // proxy admin owner
        rat.setRatTriggerProbability(0);

        // Test triggerAttentionTest with probability 0
        address gameAddress = address(0x5678);
        bytes32 stateRoot = keccak256("test_state_root");
        bytes32 blockHash = blockhash(block.number - 1);

        vm.prank(mockDisputeGameFactory);
        uint256 gasStart = gasleft();
        rat.triggerAttentionTest(gameAddress, stateRoot, blockHash, uint64(block.number));
        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("RAT triggerAttentionTest() probability=0 gas used", gasUsed);

        // Verify no attention test was created (probability check failed)
        (bytes32 storedStateRoot, , , , ) = rat.attentionTests(gameAddress);
        assertEq(storedStateRoot, bytes32(0)); // Should be empty
    }

    /// @notice Test triggerAttentionTest() with probability = MAX_PROBABILITY (always trigger)
    function test_triggerAttentionTest_probability_max_gas_measurement() public {
        // Setup challenger first
        address challenger = address(0x1234);
        vm.deal(challenger, 10 ether);
        vm.prank(challenger);
        rat.stake{value: 2 ether}();

        // Set probability to MAX_PROBABILITY (always trigger)
        vm.prank(address(1)); // proxy admin owner
        rat.setRatTriggerProbability(100000); // MAX_PROBABILITY

        // Test triggerAttentionTest with probability MAX_PROBABILITY
        address gameAddress = address(0x5678);
        bytes32 stateRoot = keccak256("test_state_root");
        bytes32 blockHash = blockhash(block.number - 1);

        vm.prank(mockDisputeGameFactory);
        uint256 gasStart = gasleft();
        rat.triggerAttentionTest(gameAddress, stateRoot, blockHash, uint64(block.number));
        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("RAT triggerAttentionTest() probability=MAX gas used", gasUsed);

        // Verify attention test was created (probability check passed)
        (bytes32 storedStateRoot, , , , ) = rat.attentionTests(gameAddress);
        assertEq(storedStateRoot, stateRoot);
    }

    /// @notice Test setRatTriggerProbability() function gas usage
    function test_setRatTriggerProbability_gas_measurement() public {
        uint256 newProbability = 1000; // 1% (1000/100000)

        vm.prank(address(1)); // proxy admin owner
        uint256 gasStart = gasleft();
        rat.setRatTriggerProbability(newProbability);
        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("RAT setRatTriggerProbability() gas used", gasUsed);

        // Verify probability was set
        assertEq(rat.ratTriggerProbability(), newProbability);
    }

    /// @notice Test shouldTriggerRAT() logic with different probabilities
    function test_shouldTriggerRAT_different_probabilities_gas_measurement() public {
        // Test with various probabilities to measure gas cost of shouldTriggerRAT()
        uint256[5] memory probabilities = [uint256(0), 1, 50000, 99999, 100000]; // 0%, 0.001%, 50%, 99.999%, 100%

        // Setup challenger for consistent test environment
        address challenger = address(0x1234);
        vm.deal(challenger, 10 ether);
        vm.prank(challenger);
        rat.stake{value: 2 ether}();

        address gameAddress = address(0x5678);
        bytes32 stateRoot = keccak256("test_state_root");
        bytes32 blockHash = blockhash(block.number - 1);

        for (uint i = 0; i < probabilities.length; i++) {
            // Set probability
            vm.prank(address(1)); // proxy admin owner
            rat.setRatTriggerProbability(probabilities[i]);

            // Test triggerAttentionTest
            vm.prank(mockDisputeGameFactory);
            uint256 gasStart = gasleft();
            rat.triggerAttentionTest(gameAddress, stateRoot, blockHash, uint64(block.number));
            uint256 gasUsed = gasStart - gasleft();

            emit log_named_uint(
                string(abi.encodePacked("RAT triggerAttentionTest() probability=", _toString(probabilities[i]), " gas used", uint64(block.number))),
                gasUsed
            );

            // Use different game address for next test
            gameAddress = address(uint160(gameAddress) + 1);
        }
    }

    /// @notice Helper function to convert uint to string for logging
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";

        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }

        return string(buffer);
    }
}
