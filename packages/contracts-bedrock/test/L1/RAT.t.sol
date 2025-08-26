// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing
import { CommonTest } from "test/setup/CommonTest.sol";

// Contracts
import { RAT } from "src/L1/RAT.sol";
import { Proxy } from "src/universal/Proxy.sol";

// Libraries
import { GameId, Claim, Position, GameType, Timestamp } from "src/dispute/lib/Types.sol";
import { LibGameId } from "src/dispute/lib/LibUDT.sol";

// Interfaces
import { IFaultDisputeGame } from "interfaces/dispute/IFaultDisputeGame.sol";

/// @title RAT_TestInit
/// @notice Base contract that sets up the testing environment for RAT tests.
contract RAT_TestInit is CommonTest {
    RAT public rat;
    address public mockDisputeGameFactory;
    address public mockFaultDisputeGame;
    uint256 public constant SLASH_BOND_AMOUNT = 1 ether;
    uint256 public constant EVIDENCE_SUBMISSION_PERIOD = 100;
    uint256 public constant MINIMUM_STAKE_AMOUNT = 0.1 ether;

    event ChallengerStaked(address indexed challenger, uint256 amount, uint256 challengerId);
    event AttentionTriggered(GameId indexed gameId, Claim stateRoot, uint256 l2BlockNumber, address indexed challengerAddress);
    event CorrectEvidenceSubmitted(GameId indexed gameId, address indexed sender, uint256 restoredAmount);
    event IncorrectEvidenceSubmitted(GameId indexed gameId, Claim indexed claim, uint256 bondAmount);
    event ChallengerResolved(GameId indexed gameId, address indexed challengerAddress, uint256 addedAmount);
    event MinimumStakeAmountUpdated(uint256 indexed newMinimumStakeAmount);

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
            abi.encodeWithSelector(
                RAT.initialize.selector,
                mockDisputeGameFactory,
                SLASH_BOND_AMOUNT,
                EVIDENCE_SUBMISSION_PERIOD,
                MINIMUM_STAKE_AMOUNT
            )
        );
    }
}

/// @title RAT_Version_Test
/// @notice Test contract for the `version` function.
contract RAT_Version_Test is RAT_TestInit {
    /// @notice Tests that the `version` function returns the expected version string.
    function test_version_succeeds() public view {
        assertEq(rat.version(), "1.0.0-beta.1");
    }
}

/// @title RAT_Initialize_Test
/// @notice Test contract for the `initialize` function.
contract RAT_Initialize_Test is RAT_TestInit {
    /// @notice Tests that the initialize function sets the correct values.
    function test_initialize_succeeds() public view {
        assertEq(rat.disputeGameFactory(), mockDisputeGameFactory);
        assertEq(rat.slashBondAmount(), SLASH_BOND_AMOUNT);
        assertEq(rat.evidenceSubmissionPeriod(), EVIDENCE_SUBMISSION_PERIOD);
        assertEq(rat.minimumStakeAmount(), MINIMUM_STAKE_AMOUNT);
        assertEq(rat.challengerIdCounter(), 1);
    }

    /// @notice Tests that initialize can only be called by proxy admin owner.
    function test_initialize_onlyProxyAdminOwner() public {
        Proxy ratProxy = new Proxy(address(1));
        RAT newRat = RAT(payable(address(ratProxy)));

        // Should revert when called by non-proxy admin owner
        vm.expectRevert();
        newRat.initialize(mockDisputeGameFactory, SLASH_BOND_AMOUNT, EVIDENCE_SUBMISSION_PERIOD, MINIMUM_STAKE_AMOUNT);
    }
}

/// @title RAT_Stake_Test
/// @notice Test contract for the `stake` function.
contract RAT_Stake_Test is RAT_TestInit {
    /// @notice Tests successful staking with sufficient amount.
    function test_stake_sufficient_succeeds() public {
        uint256 stakeAmount = 2 ether;

        vm.expectEmit(true, true, true, true);
        emit ChallengerStaked(alice, stakeAmount, 1);

        vm.deal(alice, stakeAmount);
        vm.prank(alice);
        rat.stake{value: stakeAmount}();

        RAT.ChallengerInfo memory info = rat.getChallengerInfo(alice);
        assertEq(info.id, 1);
        assertEq(info.challengerAddress, alice);
        assertEq(info.stakedAmount, stakeAmount);
        assertEq(info.slashedAmount, 0);

        // Should be added to valid challengers
        assertEq(rat.getValidChallengersCount(), 1);
        assertEq(rat.getInvalidChallengersCount(), 0);
    }

    /// @notice Tests staking with amount below minimum but above zero.
    function test_stake_belowMinimum_reverts() public {
        uint256 stakeAmount = 0.05 ether; // Less than MINIMUM_STAKE_AMOUNT

        vm.deal(alice, stakeAmount);
        vm.prank(alice);
        vm.expectRevert("RAT: total stake below minimum required");
        rat.stake{value: stakeAmount}();
    }

    /// @notice Tests staking with sufficient minimum amount but below slash bond amount.
    function test_stake_sufficientMinimumButBelowSlash_succeeds() public {
        uint256 stakeAmount = 0.5 ether; // Above MINIMUM_STAKE_AMOUNT but below SLASH_BOND_AMOUNT

        vm.expectEmit(true, true, true, true);
        emit ChallengerStaked(alice, stakeAmount, 1);

        vm.deal(alice, stakeAmount);
        vm.prank(alice);
        rat.stake{value: stakeAmount}();

        RAT.ChallengerInfo memory info = rat.getChallengerInfo(alice);
        assertEq(info.stakedAmount, stakeAmount);

        // Should be added to invalid challengers (can't be slashed)
        assertEq(rat.getValidChallengersCount(), 0);
        assertEq(rat.getInvalidChallengersCount(), 1);
    }

    /// @notice Tests that staking fails with zero amount.
    function test_stake_zero_reverts() public {
        vm.prank(alice);
        vm.expectRevert("RAT: stake amount must be greater than 0");
        rat.stake{value: 0}();
    }

    /// @notice Tests multiple staking by same challenger.
    function test_stake_multiple_succeeds() public {
        uint256 firstStake = 0.2 ether;
        uint256 secondStake = 0.3 ether;

        vm.deal(alice, firstStake + secondStake);
        
        // First stake
        vm.expectEmit(true, true, true, true);
        emit ChallengerStaked(alice, firstStake, 1);
        vm.prank(alice);
        rat.stake{value: firstStake}();

        RAT.ChallengerInfo memory info = rat.getChallengerInfo(alice);
        assertEq(info.stakedAmount, firstStake);
        assertEq(info.id, 1);

        // Second stake should succeed and add to existing
        vm.expectEmit(true, true, true, true);
        emit ChallengerStaked(alice, secondStake, 1); // Same ID
        vm.prank(alice);
        rat.stake{value: secondStake}();

        info = rat.getChallengerInfo(alice);
        assertEq(info.stakedAmount, firstStake + secondStake);
        assertEq(info.id, 1); // Same challenger ID

        // Should still be only 1 challenger total
        assertEq(rat.getTotalChallengers(), 1);
    }
}

/// @title RAT_AttentionTrigger_Test
/// @notice Test contract for the `attentionTrigger` function.
contract RAT_AttentionTrigger_Test is RAT_TestInit {
    GameId testGameId;
    Claim testStateRoot;
    uint256 testL2BlockNumber;
    bytes32 testBlockHash;

    function setUp() public virtual override {
        super.setUp();

        // Setup test data
        testGameId = LibGameId.pack(
            GameType.wrap(0),
            Timestamp.wrap(uint64(block.timestamp)),
            mockFaultDisputeGame
        );
        testStateRoot = Claim.wrap(keccak256("test_state_root"));
        testL2BlockNumber = 12345;
        testBlockHash = keccak256("test_block_hash");

        // Add a valid challenger
        vm.deal(alice, 2 ether);
        vm.prank(alice);
        rat.stake{value: 2 ether}();
    }

    /// @notice Tests successful attention trigger.
    function test_attentionTrigger_succeeds() public {
        vm.expectEmit(true, true, true, true);
        emit AttentionTriggered(testGameId, testStateRoot, testL2BlockNumber, alice);

        vm.prank(mockDisputeGameFactory);
        rat.attentionTrigger(testGameId, testStateRoot, testL2BlockNumber, testBlockHash);

        // Check challenger's stake was slashed
        RAT.ChallengerInfo memory info = rat.getChallengerInfo(alice);
        assertEq(info.stakedAmount, 1 ether); // 2 - 1 = 1
        assertEq(info.slashedAmount, 1 ether);

        // Check attention info was stored
        RAT.AttentionInfo memory attentionInfo = rat.getAttentionInfo(testGameId);
        assertEq(GameId.unwrap(attentionInfo.gameId), GameId.unwrap(testGameId));
        assertEq(attentionInfo.challengerAddress, alice);
        assertEq(Claim.unwrap(attentionInfo.stateRoot), Claim.unwrap(testStateRoot));
        assertEq(attentionInfo.l2BlockNumber, testL2BlockNumber);
        assertEq(attentionInfo.blockHash, testBlockHash);
        assertEq(attentionInfo.slashedBondAmount, SLASH_BOND_AMOUNT);
        assertEq(attentionInfo.l1Block, block.number);
        assertFalse(attentionInfo.evidenceSubmitted);
    }

    /// @notice Tests that only DisputeGameFactory can call attentionTrigger.
    function test_attentionTrigger_onlyDisputeGameFactory() public {
        vm.prank(alice);
        vm.expectRevert("RAT: only DisputeGameFactory can call");
        rat.attentionTrigger(testGameId, testStateRoot, testL2BlockNumber, testBlockHash);
    }

    /// @notice Tests that attentionTrigger fails with no valid challengers.
    function test_attentionTrigger_noValidChallengers() public {
        // Create RAT with no valid challengers
        RAT ratImpl = new RAT();
        Proxy ratProxy = new Proxy(address(1));
        RAT newRat = RAT(payable(address(ratProxy)));

        vm.prank(address(1));
        ratProxy.upgradeToAndCall(
            address(ratImpl),
            abi.encodeWithSelector(
                RAT.initialize.selector,
                mockDisputeGameFactory,
                SLASH_BOND_AMOUNT,
                EVIDENCE_SUBMISSION_PERIOD,
                MINIMUM_STAKE_AMOUNT
            )
        );

        vm.prank(mockDisputeGameFactory);
        vm.expectRevert("RAT: no valid challengers");
        newRat.attentionTrigger(testGameId, testStateRoot, testL2BlockNumber, testBlockHash);
    }
}

/// @title RAT_SubmitCorrectEvidence_Test
/// @notice Test contract for the `submitCorrectEvidence` function.
contract RAT_SubmitCorrectEvidence_Test is RAT_TestInit {
    GameId testGameId;
    Claim testStateRoot;
    bytes32 proofLV = keccak256("proof_lv");
    bytes32 proofRV = keccak256("proof_rv");

    function setUp() public virtual override {
        super.setUp();

        // Setup challenger and trigger attention
        vm.deal(alice, 2 ether);
        vm.prank(alice);
        rat.stake{value: 2 ether}();

        testGameId = LibGameId.pack(
            GameType.wrap(0),
            Timestamp.wrap(uint64(block.timestamp)),
            mockFaultDisputeGame
        );

        // Create state root that matches the proof
        testStateRoot = Claim.wrap(keccak256(abi.encodePacked(proofLV, proofRV)));

        vm.prank(mockDisputeGameFactory);
        rat.attentionTrigger(testGameId, testStateRoot, 12345, keccak256("test_block_hash"));
    }

    /// @notice Tests successful correct evidence submission.
    function test_submitCorrectEvidence_succeeds() public {
        vm.expectEmit(true, true, true, true);
        emit CorrectEvidenceSubmitted(testGameId, alice, SLASH_BOND_AMOUNT);

        vm.prank(alice);
        rat.submitCorrectEvidence(mockFaultDisputeGame, proofLV, proofRV);

        // Check stake was restored
        RAT.ChallengerInfo memory info = rat.getChallengerInfo(alice);
        assertEq(info.stakedAmount, 2 ether); // Restored to original
        assertEq(info.slashedAmount, 0);

        // Check evidence was marked as submitted
        RAT.AttentionInfo memory attentionInfo = rat.getAttentionInfo(testGameId);
        assertTrue(attentionInfo.evidenceSubmitted);
    }

    /// @notice Tests that submitCorrectEvidence fails with wrong challenger.
    function test_submitCorrectEvidence_wrongChallenger_reverts() public {
        vm.prank(bob);
        vm.expectRevert("RAT: only selected challenger can submit");
        rat.submitCorrectEvidence(mockFaultDisputeGame, proofLV, proofRV);
    }

    /// @notice Tests that submitCorrectEvidence fails with invalid proof.
    function test_submitCorrectEvidence_invalidProof_reverts() public {
        vm.prank(alice);
        vm.expectRevert("RAT: invalid proof");
        rat.submitCorrectEvidence(mockFaultDisputeGame, keccak256("wrong_lv"), keccak256("wrong_rv"));
    }

    /// @notice Tests that submitCorrectEvidence fails after period expires.
    function test_submitCorrectEvidence_expired_reverts() public {
        // Move forward past the evidence submission period
        vm.roll(block.number + EVIDENCE_SUBMISSION_PERIOD + 1);

        vm.prank(alice);
        vm.expectRevert("RAT: submission period expired");
        rat.submitCorrectEvidence(mockFaultDisputeGame, proofLV, proofRV);
    }
}

/// @title RAT_GetChallengerInfo_Test
/// @notice Test contract for getter functions.
contract RAT_GetChallengerInfo_Test is RAT_TestInit {
    /// @notice Tests getting challenger info.
    function test_getChallengerInfo_succeeds() public {
        uint256 stakeAmount = 2 ether;

        vm.deal(alice, stakeAmount);
        vm.prank(alice);
        rat.stake{value: stakeAmount}();

        RAT.ChallengerInfo memory info = rat.getChallengerInfo(alice);
        assertEq(info.id, 1);
        assertEq(info.challengerAddress, alice);
        assertEq(info.stakedAmount, stakeAmount);
        assertEq(info.slashedAmount, 0);
    }

    /// @notice Tests getting total challengers count.
    function test_getTotalChallengers_succeeds() public {
        assertEq(rat.getTotalChallengers(), 0);

        vm.deal(alice, 2 ether);
        vm.prank(alice);
        rat.stake{value: 2 ether}();

        assertEq(rat.getTotalChallengers(), 1);

        vm.deal(bob, 2 ether);
        vm.prank(bob);
        rat.stake{value: 2 ether}();

        assertEq(rat.getTotalChallengers(), 2);
    }
}

/// @title RAT_SetMinimumStakeAmount_Test
/// @notice Test contract for the `setMinimumStakeAmount` function.
contract RAT_SetMinimumStakeAmount_Test is RAT_TestInit {
    /// @notice Tests successful minimum stake amount update by proxy admin owner.
    function test_setMinimumStakeAmount_succeeds() public {
        uint256 newMinimumStakeAmount = 0.2 ether;

        vm.expectEmit(true, true, true, true);
        emit MinimumStakeAmountUpdated(newMinimumStakeAmount);

        vm.prank(address(1)); // proxy admin owner
        rat.setMinimumStakeAmount(newMinimumStakeAmount);

        assertEq(rat.minimumStakeAmount(), newMinimumStakeAmount);
    }

    /// @notice Tests that setMinimumStakeAmount can only be called by proxy admin owner.
    function test_setMinimumStakeAmount_onlyProxyAdminOwner() public {
        uint256 newMinimumStakeAmount = 0.2 ether;

        vm.prank(alice);
        vm.expectRevert();
        rat.setMinimumStakeAmount(newMinimumStakeAmount);
    }
}