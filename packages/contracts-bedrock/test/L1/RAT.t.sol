// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing utilities
import { CommonTest } from "test/setup/CommonTest.sol";
import { Proxy } from "src/universal/Proxy.sol";

// Target contract
import { RAT } from "src/L1/RAT.sol";

// Libraries
import { GameId, LibGameId, GameTypes, Timestamp, Claim } from "src/dispute/lib/Types.sol";

// Interfaces
import { IDisputeGameFactory } from "interfaces/dispute/IDisputeGameFactory.sol";

/// @notice Base contract that sets up the testing environment for RAT tests.
contract RAT_TestInit is CommonTest {
    RAT public rat;
    address public mockDisputeGameFactory;
    address public mockFaultDisputeGame;
    uint256 public constant SLASH_BOND_AMOUNT = 1 ether;
    uint256 public constant EVIDENCE_SUBMISSION_PERIOD = 100;
    uint256 public constant MINIMUM_STAKE_AMOUNT = 2 ether; // Must be > perTestSlashingAmount (1 ether)

    event ChallengerStaked(address indexed challenger, uint256 amount);
    event AttentionTriggered(GameId indexed gameId, address indexed challenger);
    event CorrectEvidenceSubmitted(GameId indexed gameId, address indexed challenger, bytes32 proofLV, bytes32 proofRV, uint256 restoredAmount);
    event BondRefunded(GameId indexed gameId, address indexed challenger, uint256 refundedAmount);

    function setUp() public virtual override {
        super.setUp();

        // Create mock addresses
        mockDisputeGameFactory = makeAddr("mockDisputeGameFactory");
        mockFaultDisputeGame = makeAddr("mockFaultDisputeGame");

        // Deploy RAT implementation
        RAT ratImpl = new RAT();

        // Deploy RAT proxy
        Proxy ratProxy = new Proxy(address(1));

        // Cast proxy to RAT interface
        rat = RAT(payable(address(ratProxy)));

        // Initialize proxy with implementation
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
                    100000, // 100% probability for testing
                    address(1) // manager address
                )
            )
        );
    }
}

/// @title RAT_Initialize_Test
/// @notice Tests initialization of the RAT contract
contract RAT_Initialize_Test is RAT_TestInit {

    /// @notice Tests successful initialization
    function test_initialize_succeeds() public view {
        assertEq(address(rat.disputeGameFactory()), mockDisputeGameFactory);
        assertEq(rat.perTestBondAmount(), SLASH_BOND_AMOUNT);
        assertEq(rat.evidenceSubmissionPeriod(), EVIDENCE_SUBMISSION_PERIOD);
        assertEq(rat.minimumStakingBalance(), MINIMUM_STAKE_AMOUNT);
        // challengerCounter removed
        assertEq(rat.getValidChallengerCount(), 1); // 1 because of dummy address(0) in initialize()
    }

    /// @notice Tests version string
    function test_version() public view {
        assertEq(rat.version(), "1.0.0-beta.1");
    }
}

/// @title RAT_Staking_Test
/// @notice Tests challenger staking functionality
contract RAT_Staking_Test is RAT_TestInit {
    address public constant CHALLENGER_1 = address(0x2345);
    address public constant CHALLENGER_2 = address(0x3456);

    function setUp() public override {
        super.setUp();
        // Fund test accounts
        vm.deal(CHALLENGER_1, 10 ether);
        vm.deal(CHALLENGER_2, 10 ether);
    }

    /// @notice Tests successful staking below minimum
    function test_stake_belowMinimum_succeeds() public {
        uint256 stakeAmount = 0.05 ether; // Below MINIMUM_STAKE_AMOUNT

        vm.expectEmit(true, false, false, true);
        emit ChallengerStaked(CHALLENGER_1, stakeAmount);

        vm.prank(CHALLENGER_1);
        rat.stake{value: stakeAmount}();

        RAT.ChallengerInfo memory info = rat.getChallengerInfo(CHALLENGER_1);
        // id field removed
        // challenger field removed - address is available from mapping key
        assertEq(info.stakingAmount, stakeAmount);
        assertEq(info.totalSlashedAmount, 0);
        assertFalse(info.isValid); // Below perTestBondAmount, should be invalid
        assertEq(rat.getValidChallengerCount(), 1); // 1 because of dummy address(0) in initialize()
    }

    /// @notice Tests successful staking above minimum
    function test_stake_aboveMinimum_succeeds() public {
        uint256 stakeAmount = 2.5 ether; // Above perTestBondAmount (1 ether)

        vm.expectEmit(true, false, false, true);
        emit ChallengerStaked(CHALLENGER_1, stakeAmount);

        vm.prank(CHALLENGER_1);
        uint256 gasStart = gasleft();
        rat.stake{value: stakeAmount}();
        uint256 gasUsed = gasStart - gasleft();
        emit log_named_uint("RAT stake() gas used", gasUsed);

        RAT.ChallengerInfo memory info = rat.getChallengerInfo(CHALLENGER_1);
        // id field removed
        // challenger field removed - address is available from mapping key
        assertEq(info.stakingAmount, stakeAmount);
        assertEq(info.totalSlashedAmount, 0);
        assertTrue(info.isValid); // Above perTestBondAmount (1 ether), should be valid
        assertEq(rat.getValidChallengerCount(), 2); // 1 dummy + 1 challenger
    }
}

/// @title RAT_TriggerAttentionTest_Test
/// @notice Tests triggerAttentionTest functionality
contract RAT_TriggerAttentionTest_Test is RAT_TestInit {
    address public constant CHALLENGER_1 = address(0x2345);
    address public constant CHALLENGER_2 = address(0x3456);

    function setUp() public override {
        super.setUp();

        // Fund and stake challengers above minimum
        vm.deal(CHALLENGER_1, 10 ether);
        vm.deal(CHALLENGER_2, 10 ether);

        vm.prank(CHALLENGER_1);
        rat.stake{value: 2.5 ether}(); // Must be >= perTestBondAmount (1 ether)

        vm.prank(CHALLENGER_2);
        rat.stake{value: 3.0 ether}(); // Must be >= perTestBondAmount (1 ether)
    }

    /// @notice Tests successful attention trigger
    function test_triggerAttentionTest_succeeds() public {
        GameId gameId = LibGameId.pack(GameTypes.CANNON, Timestamp.wrap(uint64(block.timestamp)), mockFaultDisputeGame);
        bytes32 stateRoot = keccak256("test_state_root");
        bytes32 blockHash = blockhash(block.number - 1);
        (, , address gameAddress) = LibGameId.unpack(gameId);

        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, stateRoot, blockHash);

        // Check that attention test was created
        (bytes32 attentionStateRoot, uint256 attentionBondAmount, address attentionChallengerAddress, , bool attentionEvidenceSubmitted) = rat.attentionTests(gameAddress);

        assertEq(attentionStateRoot, stateRoot);
        assertTrue(attentionChallengerAddress == CHALLENGER_1 || attentionChallengerAddress == CHALLENGER_2);
        assertFalse(attentionEvidenceSubmitted);
        assertTrue(attentionBondAmount > 0);

        // Verify challenger was slashed
        RAT.ChallengerInfo memory challengerInfo = rat.getChallengerInfo(attentionChallengerAddress);
        assertTrue(challengerInfo.totalSlashedAmount > 0);
    }

    /// @notice Tests trigger with no valid challengers returns early
    function test_triggerAttentionTest_noValidChallengers_returns() public {
        // Create empty RAT for test
        RAT ratImpl2 = new RAT();
        Proxy emptyRatProxy = new Proxy(address(1));
        RAT emptyRat = RAT(payable(address(emptyRatProxy)));
        vm.prank(address(1));
        emptyRatProxy.upgradeToAndCall(
            address(ratImpl2),
            abi.encodeCall(RAT.initialize, (IDisputeGameFactory(mockDisputeGameFactory), SLASH_BOND_AMOUNT, EVIDENCE_SUBMISSION_PERIOD, MINIMUM_STAKE_AMOUNT, 100000, address(1)))
        );

        GameId gameId = LibGameId.pack(GameTypes.CANNON, Timestamp.wrap(uint64(block.timestamp)), mockFaultDisputeGame);
        bytes32 stateRoot = keccak256("test_state_root");
        bytes32 blockHash = blockhash(block.number - 1);

        // Function should return early without reverting when no valid challengers
        (, , address gameAddress) = LibGameId.unpack(gameId);
        vm.prank(mockDisputeGameFactory);
        emptyRat.triggerAttentionTest(gameAddress, stateRoot, blockHash);

        // No assertion needed - function should complete without reverting
    }

    /// @notice Tests trigger by non-factory reverts
    function test_triggerAttentionTest_nonFactory_reverts() public {
        GameId gameId = LibGameId.pack(GameTypes.CANNON, Timestamp.wrap(uint64(block.timestamp)), mockFaultDisputeGame);
        bytes32 stateRoot = keccak256("test_state_root");
        bytes32 blockHash = blockhash(block.number - 1);

        vm.expectRevert(RAT.NotDisputeGameFactory.selector);

        (, , address gameAddress) = LibGameId.unpack(gameId);
        vm.prank(CHALLENGER_1); // Not the factory
        rat.triggerAttentionTest(gameAddress, stateRoot, blockHash);
    }
}

/// @title RAT_Evidence_Test
/// @notice Tests evidence submission functionality
contract RAT_Evidence_Test is RAT_TestInit {
    address public constant CHALLENGER_1 = address(0x2345);

    GameId public gameId;
    bytes32 public stateRoot;
    bytes32 public proofLV;
    bytes32 public proofRV;
    address public gameAddress;

    function setUp() public override {
        super.setUp();

        // Fund test account
        vm.deal(CHALLENGER_1, 10 ether);

        // Stake challenger with sufficient amount
        vm.prank(CHALLENGER_1);
        rat.stake{value: 2.5 ether}();

        // Setup test data
        proofLV = keccak256("left_value");
        proofRV = keccak256("right_value");
        stateRoot = keccak256(abi.encodePacked(proofLV, proofRV));

        gameId = LibGameId.pack(GameTypes.CANNON, Timestamp.wrap(uint64(block.timestamp)), mockFaultDisputeGame);
        (, , gameAddress) = LibGameId.unpack(gameId);
    }

    /// @notice Tests successful correct evidence submission
    function test_submitCorrectEvidence_succeeds() public {
        // Trigger attention test
        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, stateRoot, blockhash(block.number - 1));

        // Get selected challenger and game address
        (bytes32 attentionStateRoot, uint256 bondAmount, address selectedChallenger, , ) = rat.attentionTests(gameAddress);

        vm.prank(selectedChallenger);
        rat.submitCorrectEvidence(gameAddress, proofLV, proofRV);

        // Verify evidence was submitted
        (bytes32 verifyStateRoot, uint256 verifyBondAmount, address challenger, , bool evidenceSubmitted) = rat.attentionTests(gameAddress);
        assertTrue(evidenceSubmitted);
    }

    /// @notice Tests evidence submission with wrong proof fails
    function test_submitCorrectEvidence_wrongProof_reverts() public {
        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, stateRoot, blockhash(block.number - 1));

        (, , address selectedChallenger, , ) = rat.attentionTests(gameAddress);

        bytes32 wrongProofLV = keccak256("wrong_left");
        bytes32 wrongProofRV = keccak256("wrong_right");

        vm.expectRevert(RAT.ProofVerificationFailed.selector);

        vm.prank(selectedChallenger);
        rat.submitCorrectEvidence(gameAddress, wrongProofLV, wrongProofRV);
    }

    /// @notice Tests evidence submission by wrong challenger fails
    function test_submitCorrectEvidence_wrongChallenger_reverts() public {
        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, stateRoot, blockhash(block.number - 1));

        address wrongChallenger = address(0x9999);

        vm.expectRevert(RAT.InvalidChallengerAddress.selector);

        vm.prank(wrongChallenger);
        rat.submitCorrectEvidence(gameAddress, proofLV, proofRV);
    }

    /// @notice Tests evidence submission for non-existent attention test fails
    function test_submitCorrectEvidence_nonExistentTest_reverts() public {
        address nonExistentGame = address(0x8888);

        vm.expectRevert(RAT.AttentionTestNotExists.selector);

        vm.prank(CHALLENGER_1);
        rat.submitCorrectEvidence(nonExistentGame, proofLV, proofRV);
    }

    /// @notice Tests double evidence submission fails
    function test_submitCorrectEvidence_alreadySubmitted_reverts() public {
        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, stateRoot, blockhash(block.number - 1));

        (, , address selectedChallenger, , ) = rat.attentionTests(gameAddress);

        // Submit evidence first time
        vm.prank(selectedChallenger);
        rat.submitCorrectEvidence(gameAddress, proofLV, proofRV);

        // Try to submit again
        vm.expectRevert(RAT.EvidenceAlreadySubmitted.selector);

        vm.prank(selectedChallenger);
        rat.submitCorrectEvidence(gameAddress, proofLV, proofRV);
    }

    /// @notice Tests evidence submission after deadline expires
    function test_submitCorrectEvidence_expired_reverts() public {
        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, stateRoot, blockhash(block.number - 1));

        (, , address selectedChallenger, , ) = rat.attentionTests(gameAddress);

        // Move forward beyond the submission period
        vm.roll(block.number + EVIDENCE_SUBMISSION_PERIOD + 1);

        vm.expectRevert(RAT.EvidenceSubmissionExpired.selector);

        vm.prank(selectedChallenger);
        rat.submitCorrectEvidence(gameAddress, proofLV, proofRV);
    }
}

/// @title RAT_ResolveClaim_Test
/// @notice Tests resolveClaim functionality
contract RAT_ResolveClaim_Test is RAT_TestInit {
    address public constant CHALLENGER_1 = address(0x2345);

    GameId public gameId;
    bytes32 public stateRoot;
    address public gameAddress;

    function setUp() public override {
        super.setUp();

        // Fund and stake challenger
        vm.deal(CHALLENGER_1, 10 ether);
        vm.prank(CHALLENGER_1);
        rat.stake{value: 2.5 ether}();

        // Setup test data
        gameId = LibGameId.pack(GameTypes.CANNON, Timestamp.wrap(uint64(block.timestamp)), mockFaultDisputeGame);
        stateRoot = keccak256("test_state_root");

        // Trigger attention test
        (, , gameAddress) = LibGameId.unpack(gameId);
        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, stateRoot, blockhash(block.number - 1));
    }

    /// @notice Tests successful claim resolution
    function test_resolveClaim_succeeds() public {
        (, , address selectedChallenger, , ) = rat.attentionTests(gameAddress);

        // Call from game contract
        vm.prank(gameAddress);
        rat.resolveClaim(selectedChallenger);

        // Call from game contract
        vm.prank(gameAddress);
        rat.resolveClaim(selectedChallenger);

        // Verify evidence was marked as submitted
        (, , , , bool evidenceSubmitted) = rat.attentionTests(gameAddress);
        assertTrue(evidenceSubmitted);

        // Verify challenger's balance was restored
        RAT.ChallengerInfo memory challenger = rat.getChallengerInfo(selectedChallenger);
        assertTrue(challenger.stakingAmount >= MINIMUM_STAKE_AMOUNT); // Should be restored
    }

    /// @notice Tests resolve claim for wrong claimant is ignored
    function test_resolveClaim_wrongClaimant_ignored() public {
        (, , address challengerBefore, , ) = rat.attentionTests(gameAddress);
        address wrongClaimant = address(0x9999);

        // Get challenger balance before
        uint256 challengerBalanceBefore = rat.getChallengerInfo(challengerBefore).stakingAmount;

        // This should not revert but should do nothing
        vm.prank(gameAddress);
        rat.resolveClaim(wrongClaimant);

        // Verify nothing changed
        (, , , , bool evidenceSubmitted) = rat.attentionTests(gameAddress);
        assertFalse(evidenceSubmitted);

        // Verify challenger balance unchanged
        uint256 challengerBalanceAfter = rat.getChallengerInfo(challengerBefore).stakingAmount;
        assertEq(challengerBalanceAfter, challengerBalanceBefore);
    }
}

/// @title RAT_Admin_Test
/// @notice Tests for RAT admin functions
contract RAT_Admin_Test is RAT_TestInit {
    /// @notice Tests setting bond amount with non-admin caller should revert
    function test_setPerTestBondAmount_notAdmin_reverts() public {
        uint256 newAmount = 0.2 ether;

        vm.expectRevert();
        vm.prank(address(0x999)); // Not admin
        rat.setPerTestBondAmount(newAmount);
    }

    /// @notice Tests setting evidence submission period with non-admin caller should revert
    function test_setEvidenceSubmissionPeriod_notAdmin_reverts() public {
        uint256 newPeriod = 3600;

        vm.expectRevert();
        vm.prank(address(0x999)); // Not admin
        rat.setEvidenceSubmissionPeriod(newPeriod);
    }

    /// @notice Tests setting minimum staking balance with non-admin caller should revert
    function test_setMinimumStakingBalance_notAdmin_reverts() public {
        uint256 newBalance = 2 ether;

        vm.expectRevert();
        vm.prank(address(0x999)); // Not admin
        rat.setMinimumStakingBalance(newBalance);
    }
}