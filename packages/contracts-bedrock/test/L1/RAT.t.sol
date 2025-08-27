// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing utilities
import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";

// Target contract
import { RAT } from "src/L1/RAT.sol";

// Libraries
import { GameId, LibGameId, GameTypes, Timestamp } from "src/dispute/lib/Types.sol";

// Interfaces
import { IDisputeGameFactory } from "interfaces/dispute/IDisputeGameFactory.sol";

/// @title RAT_Initialize_Test
/// @notice Tests initialization of the RAT contract
contract RAT_Initialize_Test is Test {
    RAT public rat;
    IDisputeGameFactory public mockFactory;
    
    address public constant ADMIN = address(0x1234);
    uint256 public constant SLASH_AMOUNT = 1 ether;
    uint256 public constant EVIDENCE_PERIOD = 100;
    uint256 public constant MIN_STAKING = 2 ether;

    function setUp() public {
        mockFactory = IDisputeGameFactory(address(0x5678));
        rat = new RAT();
        
        vm.prank(ADMIN);
        rat.initialize(
            mockFactory,
            SLASH_AMOUNT,
            EVIDENCE_PERIOD,
            MIN_STAKING
        );
    }

    /// @notice Tests successful initialization
    function test_initialize_succeeds() public {
        assertEq(address(rat.disputeGameFactory()), address(mockFactory));
        assertEq(rat.perTestSlashingAmount(), SLASH_AMOUNT);
        assertEq(rat.evidenceSubmissionPeriod(), EVIDENCE_PERIOD);
        assertEq(rat.minimumStakingBalance(), MIN_STAKING);
        assertEq(rat.challengerCounter(), 0);
        assertEq(rat.getValidChallengerCount(), 0);
        assertEq(rat.getInvalidChallengerCount(), 0);
    }

    /// @notice Tests version string
    function test_version() public {
        assertEq(rat.version(), "1.0.0-beta.1");
    }
}

/// @title RAT_Staking_Test
/// @notice Tests challenger staking functionality
contract RAT_Staking_Test is Test {
    RAT public rat;
    IDisputeGameFactory public mockFactory;
    
    address public constant ADMIN = address(0x1234);
    address public constant CHALLENGER_1 = address(0x2345);
    address public constant CHALLENGER_2 = address(0x3456);
    uint256 public constant SLASH_AMOUNT = 1 ether;
    uint256 public constant EVIDENCE_PERIOD = 100;
    uint256 public constant MIN_STAKING = 2 ether;

    event ChallengerStaked(address indexed challenger, uint256 amount, uint256 totalStaking);

    function setUp() public {
        mockFactory = IDisputeGameFactory(address(0x5678));
        rat = new RAT();
        
        vm.prank(ADMIN);
        rat.initialize(
            mockFactory,
            SLASH_AMOUNT,
            EVIDENCE_PERIOD,
            MIN_STAKING
        );

        // Fund test accounts
        vm.deal(CHALLENGER_1, 10 ether);
        vm.deal(CHALLENGER_2, 10 ether);
    }

    /// @notice Tests successful staking below minimum
    function test_stake_belowMinimum_succeeds() public {
        uint256 stakeAmount = 1 ether;
        
        vm.expectEmit(true, false, false, true);
        emit ChallengerStaked(CHALLENGER_1, stakeAmount, stakeAmount);
        
        vm.prank(CHALLENGER_1);
        rat.stake{value: stakeAmount}();

        RAT.ChallengerInfo memory info = rat.getChallengerInfo(CHALLENGER_1);
        assertEq(info.id, 1);
        assertEq(info.challenger, CHALLENGER_1);
        assertEq(info.stakingAmount, stakeAmount);
        assertEq(info.slashedAmount, 0);
        assertFalse(info.isValid);
        assertEq(rat.challengerCounter(), 1);
        assertEq(rat.getValidChallengerCount(), 0);
        assertEq(rat.getInvalidChallengerCount(), 0);
    }

    /// @notice Tests successful staking above minimum becomes valid challenger
    function test_stake_aboveMinimum_becomesValid() public {
        uint256 stakeAmount = 3 ether;
        
        vm.expectEmit(true, false, false, true);
        emit ChallengerStaked(CHALLENGER_1, stakeAmount, stakeAmount);
        
        vm.prank(CHALLENGER_1);
        rat.stake{value: stakeAmount}();

        RAT.ChallengerInfo memory info = rat.getChallengerInfo(CHALLENGER_1);
        assertEq(info.id, 1);
        assertEq(info.challenger, CHALLENGER_1);
        assertEq(info.stakingAmount, stakeAmount);
        assertEq(info.slashedAmount, 0);
        assertTrue(info.isValid);
        assertEq(rat.challengerCounter(), 1);
        assertEq(rat.getValidChallengerCount(), 1);
        assertEq(rat.getInvalidChallengerCount(), 0);
    }

    /// @notice Tests multiple stakings from same challenger
    function test_stake_multiple_succeeds() public {
        vm.prank(CHALLENGER_1);
        rat.stake{value: 1 ether}();

        // Second stake should reach minimum
        vm.prank(CHALLENGER_1);
        rat.stake{value: 1.5 ether}();

        RAT.ChallengerInfo memory info = rat.getChallengerInfo(CHALLENGER_1);
        assertEq(info.id, 1);
        assertEq(info.stakingAmount, 2.5 ether);
        assertTrue(info.isValid);
        assertEq(rat.challengerCounter(), 1);
        assertEq(rat.getValidChallengerCount(), 1);
    }

    /// @notice Tests staking with zero value reverts
    function test_stake_zeroValue_reverts() public {
        vm.prank(CHALLENGER_1);
        vm.expectRevert("Must stake positive amount");
        rat.stake{value: 0}();
    }

    /// @notice Tests multiple challengers
    function test_stake_multipleChallengeers_succeeds() public {
        vm.prank(CHALLENGER_1);
        rat.stake{value: 3 ether}();

        vm.prank(CHALLENGER_2);
        rat.stake{value: 2 ether}();

        assertEq(rat.challengerCounter(), 2);
        assertEq(rat.getValidChallengerCount(), 2);
        
        RAT.ChallengerInfo memory info1 = rat.getChallengerInfo(CHALLENGER_1);
        RAT.ChallengerInfo memory info2 = rat.getChallengerInfo(CHALLENGER_2);
        
        assertEq(info1.id, 1);
        assertEq(info2.id, 2);
        assertTrue(info1.isValid);
        assertTrue(info2.isValid);
    }
}

/// @title RAT_AttentionTest_Test
/// @notice Tests attention test triggering functionality
contract RAT_AttentionTest_Test is Test {
    RAT public rat;
    address public mockFactory;
    
    address public constant ADMIN = address(0x1234);
    address public constant CHALLENGER_1 = address(0x2345);
    address public constant CHALLENGER_2 = address(0x3456);
    uint256 public constant SLASH_AMOUNT = 1 ether;
    uint256 public constant EVIDENCE_PERIOD = 100;
    uint256 public constant MIN_STAKING = 2 ether;

    event AttentionTriggered(GameId indexed gameId, bytes32 stateRoot, uint256 l2BlockNumber, address indexed challenger);

    function setUp() public {
        mockFactory = address(0x5678);
        rat = new RAT();
        
        vm.prank(ADMIN);
        rat.initialize(
            IDisputeGameFactory(mockFactory),
            SLASH_AMOUNT,
            EVIDENCE_PERIOD,
            MIN_STAKING
        );

        // Setup valid challengers
        vm.deal(CHALLENGER_1, 10 ether);
        vm.deal(CHALLENGER_2, 10 ether);
        
        vm.prank(CHALLENGER_1);
        rat.stake{value: 3 ether}();
        
        vm.prank(CHALLENGER_2);
        rat.stake{value: 2 ether}();
    }

    /// @notice Tests successful attention test trigger
    function test_triggerAttentionTest_succeeds() public {
        GameId gameId = LibGameId.pack(GameTypes.CANNON, Timestamp.wrap(uint64(block.timestamp)), address(0x9999));
        bytes32 stateRoot = keccak256("test state root");
        bytes32 blockHash = keccak256("test block hash");

        vm.prank(mockFactory);
        rat.triggerAttentionTest(gameId, stateRoot, blockHash, 12345);

        // Verify attention test was created
        (GameId returnedGameId, bytes32 returnedStateRoot, uint256 returnedSlashedAmount, address returnedChallengerAddress, uint64 returnedL1BlockNumber, bool returnedEvidenceSubmitted) = rat.attentionTests(address(0x9999));
        assertEq(GameId.unwrap(returnedGameId), GameId.unwrap(gameId));
        assertEq(returnedStateRoot, stateRoot);
        assertEq(returnedL1BlockNumber, block.number);
        assertFalse(returnedEvidenceSubmitted);
        
        // Verify GameId mapping
        assertEq(rat.gameIdToAddress(gameId), address(0x9999));
    }

    /// @notice Tests non-factory caller reverts
    function test_triggerAttentionTest_notFactory_reverts() public {
        GameId gameId = LibGameId.pack(GameTypes.CANNON, Timestamp.wrap(uint64(block.timestamp)), address(0x9999));
        bytes32 stateRoot = keccak256("test state root");
        bytes32 blockHash = keccak256("test block hash");

        vm.expectRevert(RAT.NotDisputeGameFactory.selector);
        rat.triggerAttentionTest(gameId, stateRoot, blockHash, 12345);
    }

    /// @notice Tests trigger with no valid challengers reverts
    function test_triggerAttentionTest_noValidChallengers_reverts() public {
        // Create new RAT with no challengers
        RAT emptyRat = new RAT();
        vm.prank(ADMIN);
        emptyRat.initialize(
            IDisputeGameFactory(mockFactory),
            SLASH_AMOUNT,
            EVIDENCE_PERIOD,
            MIN_STAKING
        );

        GameId gameId = LibGameId.pack(GameTypes.CANNON, Timestamp.wrap(uint64(block.timestamp)), address(0x9999));
        bytes32 stateRoot = keccak256("test state root");
        bytes32 blockHash = keccak256("test block hash");

        vm.prank(mockFactory);
        vm.expectRevert("No valid challengers available");
        emptyRat.triggerAttentionTest(gameId, stateRoot, blockHash, 12345);
    }
}

/// @title RAT_EvidenceSubmission_Test
/// @notice Tests evidence submission functionality
contract RAT_EvidenceSubmission_Test is Test {
    RAT public rat;
    address public mockFactory;
    
    address public constant ADMIN = address(0x1234);
    address public constant CHALLENGER_1 = address(0x2345);
    address public constant GAME_ADDRESS = address(0x9999);
    uint256 public constant SLASH_AMOUNT = 1 ether;
    uint256 public constant EVIDENCE_PERIOD = 100;
    uint256 public constant MIN_STAKING = 2 ether;

    event CorrectEvidenceSubmitted(
        GameId indexed gameId,
        address indexed challenger,
        bytes32 proofLV,
        bytes32 proofRV,
        uint256 restoredAmount
    );

    function setUp() public {
        mockFactory = address(0x5678);
        rat = new RAT();
        
        vm.prank(ADMIN);
        rat.initialize(
            IDisputeGameFactory(mockFactory),
            SLASH_AMOUNT,
            EVIDENCE_PERIOD,
            MIN_STAKING
        );

        // Setup challenger and trigger attention test
        vm.deal(CHALLENGER_1, 10 ether);
        vm.prank(CHALLENGER_1);
        rat.stake{value: 3 ether}();

        GameId gameId = LibGameId.pack(GameTypes.CANNON, Timestamp.wrap(uint64(block.timestamp)), GAME_ADDRESS);
        bytes32 stateRoot = keccak256(abi.encodePacked(bytes32("left"), bytes32("right")));
        bytes32 blockHash = bytes32(uint256(0)); // Ensures CHALLENGER_1 is selected

        vm.prank(mockFactory);
        rat.triggerAttentionTest(gameId, stateRoot, blockHash, 12345);
    }

    /// @notice Tests successful evidence submission
    function test_submitCorrectEvidence_succeeds() public {
        bytes32 leftValue = bytes32("left");
        bytes32 rightValue = bytes32("right");
        
        GameId gameId = LibGameId.pack(GameTypes.CANNON, Timestamp.wrap(uint64(block.timestamp)), GAME_ADDRESS);
        
        vm.expectEmit(true, true, false, true);
        emit CorrectEvidenceSubmitted(gameId, CHALLENGER_1, leftValue, rightValue, SLASH_AMOUNT);

        vm.prank(CHALLENGER_1);
        rat.submitCorrectEvidence(GAME_ADDRESS, leftValue, rightValue);

        // Verify evidence was accepted
        (GameId returnedGameId, bytes32 returnedStateRoot, uint256 returnedSlashedAmount, address returnedChallengerAddress, uint64 returnedL1BlockNumber, bool returnedEvidenceSubmitted) = rat.attentionTests(GAME_ADDRESS);
        assertTrue(returnedEvidenceSubmitted);
        
        // Verify slashed amount was restored
        RAT.ChallengerInfo memory challenger = rat.getChallengerInfo(CHALLENGER_1);
        assertEq(challenger.stakingAmount, 3 ether); // Should be restored to original
    }

    /// @notice Tests wrong challenger submitting evidence reverts
    function test_submitCorrectEvidence_wrongChallenger_reverts() public {
        address wrongChallenger = address(0x4567);
        bytes32 leftValue = bytes32("left");
        bytes32 rightValue = bytes32("right");

        vm.expectRevert(RAT.InvalidChallengerAddress.selector);
        vm.prank(wrongChallenger);
        rat.submitCorrectEvidence(GAME_ADDRESS, leftValue, rightValue);
    }

    /// @notice Tests wrong proof reverts
    function test_submitCorrectEvidence_wrongProof_reverts() public {
        bytes32 leftValue = bytes32("wrong");
        bytes32 rightValue = bytes32("proof");

        vm.expectRevert(RAT.ProofVerificationFailed.selector);
        vm.prank(CHALLENGER_1);
        rat.submitCorrectEvidence(GAME_ADDRESS, leftValue, rightValue);
    }

    /// @notice Tests submitting evidence twice reverts
    function test_submitCorrectEvidence_alreadySubmitted_reverts() public {
        bytes32 leftValue = bytes32("left");
        bytes32 rightValue = bytes32("right");
        
        vm.prank(CHALLENGER_1);
        rat.submitCorrectEvidence(GAME_ADDRESS, leftValue, rightValue);

        vm.expectRevert(RAT.EvidenceAlreadySubmitted.selector);
        vm.prank(CHALLENGER_1);
        rat.submitCorrectEvidence(GAME_ADDRESS, leftValue, rightValue);
    }

    /// @notice Tests submitting evidence after period expires reverts
    function test_submitCorrectEvidence_expired_reverts() public {
        bytes32 leftValue = bytes32("left");
        bytes32 rightValue = bytes32("right");
        
        // Fast forward past evidence period
        vm.warp(block.number + EVIDENCE_PERIOD + 1);

        vm.expectRevert(RAT.EvidenceSubmissionExpired.selector);
        vm.prank(CHALLENGER_1);
        rat.submitCorrectEvidence(GAME_ADDRESS, leftValue, rightValue);
    }

    /// @notice Tests nonexistent attention test reverts
    function test_submitCorrectEvidence_nonexistentTest_reverts() public {
        address nonexistentGame = address(0x1111);
        bytes32 leftValue = bytes32("left");
        bytes32 rightValue = bytes32("right");

        vm.expectRevert(RAT.AttentionTestNotExists.selector);
        vm.prank(CHALLENGER_1);
        rat.submitCorrectEvidence(nonexistentGame, leftValue, rightValue);
    }
}

/// @title RAT_ResolveClaim_Test
/// @notice Tests claim resolution functionality
contract RAT_ResolveClaim_Test is Test {
    RAT public rat;
    address public mockFactory;
    
    address public constant ADMIN = address(0x1234);
    address public constant CHALLENGER_1 = address(0x2345);
    address public constant GAME_ADDRESS = address(0x9999);
    uint256 public constant SLASH_AMOUNT = 1 ether;
    uint256 public constant EVIDENCE_PERIOD = 100;
    uint256 public constant MIN_STAKING = 2 ether;

    event BondRefunded(GameId indexed gameId, address indexed challenger, uint256 refundedAmount);

    function setUp() public {
        mockFactory = address(0x5678);
        rat = new RAT();
        
        vm.prank(ADMIN);
        rat.initialize(
            IDisputeGameFactory(mockFactory),
            SLASH_AMOUNT,
            EVIDENCE_PERIOD,
            MIN_STAKING
        );

        // Setup challenger and trigger attention test
        vm.deal(CHALLENGER_1, 10 ether);
        vm.prank(CHALLENGER_1);
        rat.stake{value: 3 ether}();

        GameId gameId = LibGameId.pack(GameTypes.CANNON, Timestamp.wrap(uint64(block.timestamp)), GAME_ADDRESS);
        bytes32 stateRoot = keccak256("test state");
        bytes32 blockHash = bytes32(uint256(0)); // Ensures CHALLENGER_1 is selected

        vm.prank(mockFactory);
        rat.triggerAttentionTest(gameId, stateRoot, blockHash, 12345);
    }

    /// @notice Tests successful claim resolution refund
    function test_resolveClaim_succeeds() public {
        GameId gameId = LibGameId.pack(GameTypes.CANNON, Timestamp.wrap(uint64(block.timestamp)), GAME_ADDRESS);
        
        vm.expectEmit(true, true, false, true);
        emit BondRefunded(gameId, CHALLENGER_1, SLASH_AMOUNT);

        vm.prank(GAME_ADDRESS);
        rat.resolveClaim(CHALLENGER_1);

        // Verify bond was refunded
        RAT.ChallengerInfo memory challenger = rat.getChallengerInfo(CHALLENGER_1);
        assertEq(challenger.stakingAmount, 3 ether); // Should be restored
        
        // Verify evidence marked as submitted
        (GameId returnedGameId, bytes32 returnedStateRoot, uint256 returnedSlashedAmount, address returnedChallengerAddress, uint64 returnedL1BlockNumber, bool returnedEvidenceSubmitted) = rat.attentionTests(GAME_ADDRESS);
        assertTrue(returnedEvidenceSubmitted);
    }

    /// @notice Tests resolve claim for wrong challenger does nothing
    function test_resolveClaim_wrongChallenger_doesNothing() public {
        address wrongChallenger = address(0x4567);

        vm.prank(GAME_ADDRESS);
        rat.resolveClaim(wrongChallenger);

        // Verify nothing changed
        (GameId returnedGameId, bytes32 returnedStateRoot, uint256 returnedSlashedAmount, address returnedChallengerAddress, uint64 returnedL1BlockNumber, bool returnedEvidenceSubmitted) = rat.attentionTests(GAME_ADDRESS);
        assertFalse(returnedEvidenceSubmitted);
    }

    /// @notice Tests resolve claim already submitted does nothing
    function test_resolveClaim_alreadySubmitted_doesNothing() public {
        // Submit evidence first
        bytes32 leftValue = bytes32("left");
        bytes32 rightValue = bytes32("right");
        bytes32 correctStateRoot = keccak256(abi.encodePacked(leftValue, rightValue));
        
        // Update attention test with correct state root
        vm.prank(mockFactory);
        rat.triggerAttentionTest(
            LibGameId.pack(GameTypes.CANNON, Timestamp.wrap(uint64(block.timestamp)), address(0x8888)),
            correctStateRoot,
            bytes32(uint256(0)),
            12345
        );
        
        vm.prank(CHALLENGER_1);
        rat.submitCorrectEvidence(address(0x8888), leftValue, rightValue);
        
        uint256 stakingBefore = rat.getChallengerInfo(CHALLENGER_1).stakingAmount;

        vm.prank(address(0x8888));
        rat.resolveClaim(CHALLENGER_1);

        // Verify staking amount didn't change
        uint256 stakingAfter = rat.getChallengerInfo(CHALLENGER_1).stakingAmount;
        assertEq(stakingBefore, stakingAfter);
    }
}

/// @title RAT_Admin_Test
/// @notice Tests administrative functionality
contract RAT_Admin_Test is Test {
    RAT public rat;
    address public mockFactory;
    
    address public constant ADMIN = address(0x1234);
    uint256 public constant SLASH_AMOUNT = 1 ether;
    uint256 public constant EVIDENCE_PERIOD = 100;
    uint256 public constant MIN_STAKING = 2 ether;

    function setUp() public {
        mockFactory = address(0x5678);
        rat = new RAT();
        
        vm.prank(ADMIN);
        rat.initialize(
            IDisputeGameFactory(mockFactory),
            SLASH_AMOUNT,
            EVIDENCE_PERIOD,
            MIN_STAKING
        );
    }

    /// @notice Tests admin can set per-test slashing amount
    function test_setPerTestSlashingAmount_succeeds() public {
        uint256 newAmount = 2 ether;
        
        vm.prank(ADMIN);
        rat.setPerTestSlashingAmount(newAmount);
        
        assertEq(rat.perTestSlashingAmount(), newAmount);
    }

    /// @notice Tests admin can set evidence submission period
    function test_setEvidenceSubmissionPeriod_succeeds() public {
        uint256 newPeriod = 200;
        
        vm.prank(ADMIN);
        rat.setEvidenceSubmissionPeriod(newPeriod);
        
        assertEq(rat.evidenceSubmissionPeriod(), newPeriod);
    }

    /// @notice Tests admin can set minimum staking balance
    function test_setMinimumStakingBalance_succeeds() public {
        uint256 newMinimum = 5 ether;
        
        vm.prank(ADMIN);
        rat.setMinimumStakingBalance(newMinimum);
        
        assertEq(rat.minimumStakingBalance(), newMinimum);
    }

    /// @notice Tests non-admin cannot set parameters
    function test_setParameters_nonAdmin_reverts() public {
        address nonAdmin = address(0x9999);
        
        vm.expectRevert(); // Should revert with access control error
        vm.prank(nonAdmin);
        rat.setPerTestSlashingAmount(2 ether);
        
        vm.expectRevert(); // Should revert with access control error
        vm.prank(nonAdmin);
        rat.setEvidenceSubmissionPeriod(200);
        
        vm.expectRevert(); // Should revert with access control error
        vm.prank(nonAdmin);
        rat.setMinimumStakingBalance(5 ether);
    }
}