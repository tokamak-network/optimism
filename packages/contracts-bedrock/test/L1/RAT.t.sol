// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing utilities
import { CommonTest } from "test/setup/CommonTest.sol";
import { Proxy } from "src/universal/Proxy.sol";

// Target contract
import { RAT } from "src/L1/RAT.sol";
import { TestableRAT } from "test/mocks/TestableRAT.sol";

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
    uint256 public constant MINIMUM_STAKE_AMOUNT = 2 ether; // Must be > perTestBondAmount (1 ether)
    uint256 public constant OFFLINE_PENALTY_RATE = 5000; // 50%

    event ChallengerStaked(address indexed challenger, uint256 amount);

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
                    OFFLINE_PENALTY_RATE,
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
        assertEq(rat.version(), "2.0.0-beta.1");
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
        bytes32 version = bytes32(0);
        bytes32 stateRoot = keccak256("test_state_root");
        bytes32 messagePasserRoot = keccak256("msgPasserRoot");
        bytes32 blockHash = keccak256("blockHash");
        bytes32 outputRoot = keccak256(abi.encode(version, stateRoot, messagePasserRoot, blockHash));
        (, , address gameAddress) = LibGameId.unpack(gameId);

        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, outputRoot, bytes32(0), uint64(block.number));

        // Check that attention test was created
        RAT.AttentionInfo memory info = rat.getAttentionTest(gameAddress);

        assertEq(info.outputRoot, outputRoot);
        assertTrue(info.challengerAddress == CHALLENGER_1 || info.challengerAddress == CHALLENGER_2);
        assertEq(info.status, rat.STATUS_PENDING());
        assertTrue(info.bondAmount > 0);

        // Verify challenger was slashed
        RAT.ChallengerInfo memory challengerInfo = rat.getChallengerInfo(info.challengerAddress);
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
            abi.encodeCall(
                RAT.initialize,
                (
                    IDisputeGameFactory(mockDisputeGameFactory),
                    SLASH_BOND_AMOUNT,
                    EVIDENCE_SUBMISSION_PERIOD,
                    MINIMUM_STAKE_AMOUNT,
                    100000,
                    OFFLINE_PENALTY_RATE,
                    address(1)
                )
            )
        );

        GameId gameId = LibGameId.pack(GameTypes.CANNON, Timestamp.wrap(uint64(block.timestamp)), mockFaultDisputeGame);
        bytes32 version = bytes32(0);
        bytes32 stateRoot = keccak256("test_state_root");
        bytes32 messagePasserRoot = keccak256("msgPasserRoot");
        bytes32 blockHash = keccak256("blockHash");
        bytes32 outputRoot = keccak256(abi.encode(version, stateRoot, messagePasserRoot, blockHash));

        // Function should return early without reverting when no valid challengers
        (, , address gameAddress) = LibGameId.unpack(gameId);
        vm.prank(mockDisputeGameFactory);
        emptyRat.triggerAttentionTest(gameAddress, outputRoot, bytes32(0), uint64(block.number));

        // No assertion needed - function should complete without reverting
    }

    /// @notice Tests trigger by non-factory reverts
    function test_triggerAttentionTest_nonFactory_reverts() public {
        GameId gameId = LibGameId.pack(GameTypes.CANNON, Timestamp.wrap(uint64(block.timestamp)), mockFaultDisputeGame);
        bytes32 version = bytes32(0);
        bytes32 stateRoot = keccak256("test_state_root");
        bytes32 messagePasserRoot = keccak256("msgPasserRoot");
        bytes32 blockHash = keccak256("blockHash");
        bytes32 outputRoot = keccak256(abi.encode(version, stateRoot, messagePasserRoot, blockHash));

        vm.expectRevert(RAT.NotDisputeGameFactory.selector);

        (, , address gameAddress) = LibGameId.unpack(gameId);
        vm.prank(CHALLENGER_1); // Not the factory
        rat.triggerAttentionTest(gameAddress, outputRoot, bytes32(0), uint64(block.number));
    }
}

/// @title RAT_Evidence_Test
/// @notice Tests evidence submission functionality
contract RAT_Evidence_Test is RAT_TestInit {
    address public constant CHALLENGER_1 = address(0x2345);

    GameId public gameId;
    bytes32 public outputRoot;
    bytes32 public version;
    bytes32 public stateRoot;
    bytes32 public messagePasserStorageRoot;
    bytes32 public latestBlockhash;
    address public gameAddress;

    function setUp() public override {
        super.setUp();

        // Fund test account
        vm.deal(CHALLENGER_1, 10 ether);

        // Stake challenger with sufficient amount
        vm.prank(CHALLENGER_1);
        rat.stake{value: 2.5 ether}();

        // Setup test data for OutputRoot verification
        version = bytes32(0);
        stateRoot = keccak256("stateRoot");
        messagePasserStorageRoot = keccak256("msgPasserRoot");
        latestBlockhash = keccak256("blockHash");

        outputRoot = keccak256(abi.encode(version, stateRoot, messagePasserStorageRoot, latestBlockhash));

        gameId = LibGameId.pack(GameTypes.CANNON, Timestamp.wrap(uint64(block.timestamp)), mockFaultDisputeGame);
        (, , gameAddress) = LibGameId.unpack(gameId);
    }

    /// @notice Tests successful candidate submission
    function test_submitCandidate_succeeds() public {
        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, outputRoot, bytes32(0), uint64(block.number));

        RAT.AttentionInfo memory info = rat.getAttentionTest(gameAddress);
        address selectedChallenger = info.challengerAddress;
        bytes32 candidateKey = bytes32(uint256(uint160(address(0x1234))));

        vm.prank(selectedChallenger);
        rat.submitCandidate(gameAddress, candidateKey, stateRoot, version, messagePasserStorageRoot, latestBlockhash);

        info = rat.getAttentionTest(gameAddress);
        assertEq(info.status, rat.STATUS_SUBMITTED());
        assertEq(info.candidateAddr, address(uint160(uint256(candidateKey))));
    }

    /// @notice Non-inclusion disputes must require a valid MPT proof (empty proof must not pass).
    function test_disputeByNonInclusion_emptyProof_reverts() public {
        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, outputRoot, bytes32(0), uint64(block.number));

        RAT.AttentionInfo memory info = rat.getAttentionTest(gameAddress);
        address selectedChallenger = info.challengerAddress;
        bytes32 candidateKey = bytes32(uint256(uint160(address(0x1234))));

        vm.prank(selectedChallenger);
        rat.submitCandidate(gameAddress, candidateKey, stateRoot, version, messagePasserStorageRoot, latestBlockhash);

        bytes[] memory emptyProof = new bytes[](0);
        vm.expectRevert();
        rat.disputeByNonInclusion(
            gameAddress, candidateKey, stateRoot, version, messagePasserStorageRoot, latestBlockhash, emptyProof
        );
    }

    /// @notice Tests candidate submission with wrong components fails
    function test_submitCandidate_wrongComponents_reverts() public {
        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, outputRoot, bytes32(0), uint64(block.number));

        RAT.AttentionInfo memory info = rat.getAttentionTest(gameAddress);
        bytes32 candidateKey = bytes32(uint256(uint160(address(0x1234))));

        vm.expectRevert(RAT.InvalidOutputRootComponents.selector);

        vm.prank(info.challengerAddress);
        rat.submitCandidate(gameAddress, candidateKey, keccak256("wrongRoot"), version, messagePasserStorageRoot, latestBlockhash);
    }

    /// @notice Tests candidate submission by wrong challenger fails
    function test_submitCandidate_wrongChallenger_reverts() public {
        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, outputRoot, bytes32(0), uint64(block.number));

        address wrongChallenger = address(0x9999);

        vm.expectRevert(RAT.InvalidChallengerAddress.selector);

        vm.prank(wrongChallenger);
        rat.submitCandidate(gameAddress, bytes32(uint256(1)), stateRoot, version, messagePasserStorageRoot, latestBlockhash);
    }

    /// @notice Tests candidate submission for non-existent attention test fails
    function test_submitCandidate_nonExistentTest_reverts() public {
        address nonExistentGame = address(0x8888);

        vm.expectRevert(RAT.AttentionTestNotExists.selector);

        vm.prank(CHALLENGER_1);
        rat.submitCandidate(nonExistentGame, bytes32(uint256(1)), stateRoot, version, messagePasserStorageRoot, latestBlockhash);
    }

    /// @notice Tests double candidate submission fails
    function test_submitCandidate_alreadySubmitted_reverts() public {
        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, outputRoot, bytes32(0), uint64(block.number));

        RAT.AttentionInfo memory info = rat.getAttentionTest(gameAddress);
        bytes32 candidateKey = bytes32(uint256(uint160(address(0x1234))));

        vm.prank(info.challengerAddress);
        rat.submitCandidate(gameAddress, candidateKey, stateRoot, version, messagePasserStorageRoot, latestBlockhash);

        vm.expectRevert(RAT.InvalidStatus.selector);

        vm.prank(info.challengerAddress);
        rat.submitCandidate(gameAddress, candidateKey, stateRoot, version, messagePasserStorageRoot, latestBlockhash);
    }

    /// @notice Tests candidate submission after deadline expires
    function test_submitCandidate_expired_reverts() public {
        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, outputRoot, bytes32(0), uint64(block.number));

        RAT.AttentionInfo memory info = rat.getAttentionTest(gameAddress);

        vm.roll(block.number + EVIDENCE_SUBMISSION_PERIOD + 1);

        vm.expectRevert(RAT.DeadlinePassed.selector);

        vm.prank(info.challengerAddress);
        rat.submitCandidate(gameAddress, bytes32(uint256(1)), stateRoot, version, messagePasserStorageRoot, latestBlockhash);
    }
}

/// @title RAT_Dispute_Logic_Test
/// @notice Verifies both success and failure cases for disputes (unit-testable proofs).
contract RAT_Dispute_Logic_Test is CommonTest {
    TestableRAT public rat;
    address public mockDisputeGameFactory;
    address public mockGame;

    uint256 public constant BOND = 1 ether;
    uint256 public constant PERIOD = 100;
    uint256 public constant MIN_STAKE = 2 ether;

    address public constant CHALLENGER_1 = address(0x2345);
    address public constant CHALLENGER_2 = address(0x3456);
    address public constant DISPUTER = address(0x9999);

    function setUp() public override {
        super.setUp();

        mockDisputeGameFactory = makeAddr("mockDisputeGameFactory");
        mockGame = makeAddr("mockGame");

        // Deploy TestableRAT behind proxy (same pattern as other tests).
        TestableRAT impl = new TestableRAT();
        Proxy proxy = new Proxy(address(1));
        rat = TestableRAT(payable(address(proxy)));

        vm.prank(address(1));
        proxy.upgradeToAndCall(
            address(impl),
            abi.encodeCall(
                RAT.initialize,
                (IDisputeGameFactory(mockDisputeGameFactory), BOND, PERIOD, MIN_STAKE, 100000, 5000, address(1))
            )
        );

        vm.deal(CHALLENGER_1, 10 ether);
        vm.deal(CHALLENGER_2, 10 ether);
        vm.deal(DISPUTER, 10 ether);

        vm.prank(CHALLENGER_1);
        rat.stake{ value: 2.5 ether }();
        vm.prank(CHALLENGER_2);
        rat.stake{ value: 2.5 ether }();
    }

    function _components()
        internal
        view
        returns (bytes32 version, bytes32 stateRoot, bytes32 msgPasserRoot, bytes32 blockHash, bytes32 outputRoot)
    {
        version = bytes32(0);
        stateRoot = keccak256("stateRoot");
        msgPasserRoot = keccak256("msgPasserRoot");
        blockHash = keccak256("blockHash");
        outputRoot = keccak256(abi.encode(version, stateRoot, msgPasserRoot, blockHash));
    }

    function _triggerAndSubmit(bytes32 candidateKey)
        internal
        returns (bytes32 version, bytes32 stateRoot, bytes32 msgPasserRoot, bytes32 blockHash)
    {
        bytes32 outputRoot;
        (version, stateRoot, msgPasserRoot, blockHash, outputRoot) = _components();

        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(mockGame, outputRoot, bytes32(0), uint64(block.number));

        address selected = rat.getAttentionTest(mockGame).challengerAddress;
        vm.prank(selected);
        rat.submitCandidate(mockGame, candidateKey, stateRoot, version, msgPasserRoot, blockHash);
    }

    function test_disputeByNonInclusion_validProof_succeeds_and_invalidProof_fails() public {
        bytes32 candidateKey = bytes32(uint256(1));
        (bytes32 v, bytes32 sr, bytes32 mpr, bytes32 bh) = _triggerAndSubmit(candidateKey);

        // invalid: "EXISTS" should revert KeyExists
        bytes[] memory existsProof = new bytes[](1);
        existsProof[0] = abi.encodePacked("EXISTS");
        vm.expectRevert(RAT.KeyExists.selector);
        rat.disputeByNonInclusion(mockGame, candidateKey, sr, v, mpr, bh, existsProof);

        // valid: "MISSING" should succeed and pay out bond (and mark disputed)
        bytes[] memory missingProof = new bytes[](1);
        missingProof[0] = abi.encodePacked("MISSING");

        uint256 disputerBalBefore = DISPUTER.balance;
        address selected = rat.getAttentionTest(mockGame).challengerAddress;
        uint256 expectedPayout = rat.getChallengerInfo(selected).stakingAmount;
        vm.prank(DISPUTER);
        rat.disputeByNonInclusion(mockGame, candidateKey, sr, v, mpr, bh, missingProof);
        assertEq(rat.getAttentionTest(mockGame).status, rat.STATUS_DISPUTED());
        assertEq(DISPUTER.balance, disputerBalBefore + expectedPayout);
    }

    function test_disputeByCloserKey_validCloserKey_succeeds_and_notCloser_fails() public {
        // Pick a candidateKey that is "far" and a closerKey that is "closer" to the seed.
        (bytes32 v, bytes32 sr, bytes32 mpr, bytes32 bh, bytes32 outputRoot) = _components();
        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(mockGame, outputRoot, bytes32(0), uint64(block.number));

        // NOTE: keys are restricted to the low 160-bit "address" domain (high bits are zero).
        // Avoid extra locals to prevent stack-too-deep.
        bytes32 farKey = bytes32(uint256(uint160(uint256(rat.getAttentionTest(mockGame).seed))) + 1);
        bytes32 closeKey = bytes32(uint256(uint160(uint256(rat.getAttentionTest(mockGame).seed))) + 100);

        vm.prank(rat.getAttentionTest(mockGame).challengerAddress);
        rat.submitCandidate(mockGame, farKey, sr, v, mpr, bh);

        // proof that closer key exists
        bytes[] memory existsProof = new bytes[](1);
        existsProof[0] = abi.encodePacked("EXISTS");

        // invalid: not closer (use farKey again)
        vm.prank(DISPUTER);
        vm.expectRevert(RAT.NotCloserKey.selector);
        rat.disputeByCloserKey(mockGame, farKey, sr, v, mpr, bh, existsProof);

        // valid: closer key wins
        uint256 disputerBalBefore = DISPUTER.balance;
        uint256 expectedPayout = rat.getChallengerInfo(rat.getAttentionTest(mockGame).challengerAddress).stakingAmount;
        vm.prank(DISPUTER);
        rat.disputeByCloserKey(mockGame, closeKey, sr, v, mpr, bh, existsProof);
        assertEq(rat.getAttentionTest(mockGame).status, rat.STATUS_DISPUTED());
        assertEq(DISPUTER.balance, disputerBalBefore + expectedPayout);
    }
}

/// @title RAT_ResolveClaim_Test
/// @notice Tests resolveClaim functionality
contract RAT_ResolveClaim_Test is RAT_TestInit {
    address public constant CHALLENGER_1 = address(0x2345);

    GameId public gameId;
    bytes32 public outputRoot;
    address public gameAddress;

    function setUp() public override {
        super.setUp();

        // Fund and stake challenger
        vm.deal(CHALLENGER_1, 10 ether);
        vm.prank(CHALLENGER_1);
        rat.stake{value: 2.5 ether}();

        // Setup test data
        gameId = LibGameId.pack(GameTypes.CANNON, Timestamp.wrap(uint64(block.timestamp)), mockFaultDisputeGame);
        outputRoot = keccak256("test_output_root");

        // Trigger attention test
        (, , gameAddress) = LibGameId.unpack(gameId);
        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, outputRoot, bytes32(0), uint64(block.number));
    }

    /// @notice Tests successful claim resolution
    function test_resolveClaim_succeeds() public {
        RAT.AttentionInfo memory info = rat.getAttentionTest(gameAddress);
        address selectedChallenger = info.challengerAddress;

        // Call from game contract
        vm.prank(gameAddress);
        rat.resolveClaim(selectedChallenger);

        // Call from game contract
        vm.prank(gameAddress);
        rat.resolveClaim(selectedChallenger);

        // Verify status was finalized
        info = rat.getAttentionTest(gameAddress);
        assertEq(info.status, rat.STATUS_FINALIZED());

        // Verify challenger's balance was restored
        RAT.ChallengerInfo memory challenger = rat.getChallengerInfo(selectedChallenger);
        assertTrue(challenger.stakingAmount >= MINIMUM_STAKE_AMOUNT); // Should be restored
    }

    /// @notice Tests resolve claim for wrong claimant is ignored
    function test_resolveClaim_wrongClaimant_ignored() public {
        RAT.AttentionInfo memory info = rat.getAttentionTest(gameAddress);
        address challengerBefore = info.challengerAddress;
        address wrongClaimant = address(0x9999);

        // Get challenger balance before
        uint256 challengerBalanceBefore = rat.getChallengerInfo(challengerBefore).stakingAmount;

        // This should not revert but should do nothing
        vm.prank(gameAddress);
        rat.resolveClaim(wrongClaimant);

        // Verify nothing changed
        info = rat.getAttentionTest(gameAddress);
        assertEq(info.status, rat.STATUS_PENDING());

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