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
import { IDisputeGame } from "interfaces/dispute/IDisputeGame.sol";

contract RAT_GasComparison_Complete_Test is CommonTest {
    RAT public rat;
    address public mockDisputeGameFactory;
    address public mockFaultDisputeGame;
    address public constant CHALLENGER_1 = address(0x1111);
    address public constant CHALLENGER_2 = address(0x2222);
    address public constant CHALLENGER_3 = address(0x3333);
    address public constant CHALLENGER_4 = address(0x4444);

    uint256 public constant SLASH_BOND_AMOUNT = 1 ether;
    uint256 public constant EVIDENCE_SUBMISSION_PERIOD = 100;
    uint256 public constant MINIMUM_STAKE_AMOUNT = 2 ether;

    // Test data
    bytes32 constant STATE_ROOT = bytes32(uint256(0x1234567890abcdef));
    bytes32 constant BLOCK_HASH = bytes32(uint256(0xfedcba0987654321));
    bytes32 constant PROOF_LV = bytes32(uint256(0x1111111111111111));
    bytes32 constant PROOF_RV = bytes32(uint256(0x2222222222222222));

    // Gas measurement variables
    uint256 gasUsed;

        function setUp() public override {
        super.setUp();

        // Use actual disputeGameFactory from CommonTest
        mockDisputeGameFactory = address(disputeGameFactory);
        mockFaultDisputeGame = makeAddr("mockFaultDisputeGame");

        // Set up game implementation for CANNON game type
        // This is needed to avoid NoImplementation(0) error
        vm.prank(disputeGameFactory.owner());
        disputeGameFactory.setImplementation(GameTypes.CANNON, IDisputeGame(mockFaultDisputeGame));

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
                    100000 // 100% default probability (MAX_PROBABILITY)
                )
            )
        );

        // Set probability to 100% to ensure RAT always triggers
        vm.prank(address(1)); // proxy admin owner
        rat.setRatTriggerProbability(100000); // MAX_PROBABILITY

        // Fund test accounts
        vm.deal(CHALLENGER_1, 10 ether);
        vm.deal(CHALLENGER_2, 10 ether);
        vm.deal(CHALLENGER_3, 10 ether);
        vm.deal(CHALLENGER_4, 10 ether);
    }

                // Scenario 1: Original OP Mainnet (DisputeGameFactory.create() 함수 호출)
    function test_gas_original_op_mainnet() public {
        emit log_string("=== Scenario 1: Original OP Mainnet ===");

        // DisputeGameFactory.create() 함수 호출 시 가스 비용 측정
        bytes32 rootClaim = keccak256("test_root_claim");
        bytes memory extraData = abi.encode(uint256(1000));

        uint256 gasStart = gasleft();

        // 실제 게임 생성
        IDisputeGame game = disputeGameFactory.create(
            GameTypes.CANNON,
            Claim.wrap(rootClaim),
            extraData
        );

        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("Original OP Mainnet game creation gas cost", gasUsed);
        emit log_string("Function: DisputeGameFactory.create()");
        emit log_named_address("Created game address", address(game));
        emit log_string("");
    }

        // Scenario 2: RAT Triggered but No Valid Challengers
    function test_gas_rat_triggered_no_valid_challengers() public {
        emit log_string("=== Scenario 2: RAT Triggered but No Valid Challengers ===");

        // No challengers staked, so no valid challengers
        // This simulates the case where RAT is triggered but no valid challengers exist

        // DisputeGameFactory.create() 함수 호출 시 가스 비용 측정
        bytes32 rootClaim = keccak256("test_root_claim_no_valid_challengers");
        bytes memory extraData = abi.encode(uint256(2000));

        uint256 gasStart = gasleft();

        // 실제 게임 생성 (RAT이 트리거되지만 유효한 챌린저가 없는 경우)
        IDisputeGame game = disputeGameFactory.create(
            GameTypes.CANNON,
            Claim.wrap(rootClaim),
            extraData
        );

        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("RAT (not triggered) propose gas cost", gasUsed);
        emit log_string("Function: DisputeGameFactory.create() (RAT triggered but no valid challengers)");
        emit log_named_address("Created game address", address(game));
        emit log_string("");
    }

        // Scenario 3a: RAT Triggered with Valid Challengers (챌린저 유효 상태 유지)
    function test_gas_rat_triggered_valid_challenger_stays_valid() public {
        emit log_string("=== Scenario 3a: RAT Triggered with Valid Challengers (challenger stays valid) ===");

        // Stake challengers with enough amount to stay valid after slashing
        vm.prank(CHALLENGER_1);
        rat.stake{value: 2.5 ether}(); // 2.5 ether - 1 ether = 1.5 ether (still >= 1 ether)

        vm.prank(CHALLENGER_2);
        rat.stake{value: 3.0 ether}(); // 3.0 ether - 1 ether = 2.0 ether (still >= 1 ether)

        // Create game first
        bytes32 rootClaim = keccak256("rat_triggered_state_root");
        bytes memory extraData = abi.encode(uint256(3000));

        // DisputeGameFactory.create() 호출
        IDisputeGame game = disputeGameFactory.create(
            GameTypes.CANNON,
            Claim.wrap(rootClaim),
            extraData
        );

        // Then trigger RAT attention test
        GameId gameId = LibGameId.pack(GameTypes.CANNON, Timestamp.wrap(uint64(block.timestamp)), address(game));
        bytes32 stateRoot = keccak256("rat_triggered_state_root");
        bytes32 blockHash = blockhash(block.number - 1);

        uint256 gasStart = gasleft();

        (, , address gameAddress) = LibGameId.unpack(gameId);
        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, stateRoot, blockHash);

        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("RAT triggerAttentionTest gas cost (challenger stays valid)", gasUsed);
        emit log_string("Function: triggerAttentionTest (RAT triggered, challenger stays valid after slashing)");
        emit log_string("Challenger staking: 2.5 ether, 3.0 ether");
        emit log_named_address("Game address", address(game));
        emit log_string("");
    }

        // Scenario 3b: RAT Triggered with Valid Challengers (챌린저 유효 상태 변경)
    function test_gas_rat_triggered_valid_challenger_becomes_invalid() public {
        emit log_string("=== Scenario 3b: RAT Triggered with Valid Challengers (challenger becomes invalid) ===");

        // Stake challengers with amount that will make them invalid after slashing
        vm.prank(CHALLENGER_1);
        rat.stake{value: 1.5 ether}(); // 1.5 ether - 1 ether = 0.5 ether (< 1 ether, becomes invalid)

        vm.prank(CHALLENGER_2);
        rat.stake{value: 1.8 ether}(); // 1.8 ether - 1 ether = 0.8 ether (< 1 ether, becomes invalid)

        // Create game first
        bytes32 rootClaim = keccak256("rat_triggered_invalid_state_root");
        bytes memory extraData = abi.encode(uint256(4000));

        // DisputeGameFactory.create() 호출
        IDisputeGame game = disputeGameFactory.create(
            GameTypes.CANNON,
            Claim.wrap(rootClaim),
            extraData
        );

        // Then trigger RAT attention test
        GameId gameId = LibGameId.pack(GameTypes.CANNON, Timestamp.wrap(uint64(block.timestamp)), address(game));
        bytes32 stateRoot = keccak256("rat_triggered_invalid_state_root");
        bytes32 blockHash = blockhash(block.number - 1);

        uint256 gasStart = gasleft();

        (, , address gameAddress) = LibGameId.unpack(gameId);
        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, stateRoot, blockHash);

        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("RAT triggerAttentionTest gas cost (challenger becomes invalid)", gasUsed);
        emit log_string("Function: triggerAttentionTest (RAT triggered, challenger becomes invalid after slashing)");
        emit log_string("Challenger staking: 1.5 ether, 1.8 ether");
        emit log_named_address("Game address", address(game));
        emit log_string("");
    }

    // Scenario 4a: Validator Evidence (유효한 챌린저 환급)
    function test_gas_validator_evidence_valid_challenger_refund() public {
        emit log_string("=== Scenario 4a: Validator Evidence (valid challenger refund) ===");

        // Setup: Create attention test first
        vm.prank(CHALLENGER_1);
        rat.stake{value: 2.5 ether}();

        vm.prank(CHALLENGER_2);
        rat.stake{value: 3.0 ether}();

        // Trigger attention test
        GameId gameId = LibGameId.pack(GameTypes.CANNON, Timestamp.wrap(uint64(block.timestamp)), mockFaultDisputeGame);
        bytes32 stateRoot = keccak256("validator_evidence_state_root");
        bytes32 blockHash = blockhash(block.number - 1);

        // Get game address and selected challenger
        (, , address gameAddress) = LibGameId.unpack(gameId);
        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, stateRoot, blockHash);
        (, , address selectedChallenger, , ) = rat.attentionTests(gameAddress);
        require(selectedChallenger != address(0), "No challenger selected");

        // Submit correct evidence (refund while staying valid)
        vm.prank(selectedChallenger);

        uint256 gasStart = gasleft();
        rat.submitCorrectEvidence(gameAddress, PROOF_LV, PROOF_RV);
        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("Validator evidence submission (valid challenger) gas cost", gasUsed);
        emit log_string("Function: submitCorrectEvidence (refund while staying valid)");
        emit log_named_address("Selected challenger", selectedChallenger);
        emit log_string("");
    }

    // Scenario 4b: Validator Evidence (유효하지 않은 챌린저가 유효한 상태가 됨)
    function test_gas_validator_evidence_invalid_challenger_becomes_valid() public {
        emit log_string("=== Scenario 4b: Validator Evidence (invalid challenger becomes valid) ===");

        // Setup: Stake challenger with amount that makes them invalid after slashing
        vm.prank(CHALLENGER_1);
        rat.stake{value: 1.5 ether}(); // Will become invalid after slashing

        // Trigger attention test
        GameId gameId = LibGameId.pack(GameTypes.CANNON, Timestamp.wrap(uint64(block.timestamp)), mockFaultDisputeGame);
        bytes32 stateRoot = keccak256("validator_evidence_invalid_state_root");
        bytes32 blockHash = blockhash(block.number - 1);

        // Get game address and selected challenger
        (, , address gameAddress) = LibGameId.unpack(gameId);
        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, stateRoot, blockHash);
        (, , address selectedChallenger, , ) = rat.attentionTests(gameAddress);
        require(selectedChallenger != address(0), "No challenger selected");

        // Submit correct evidence (refund and become valid)
        vm.prank(selectedChallenger);

        uint256 gasStart = gasleft();
        rat.submitCorrectEvidence(gameAddress, PROOF_LV, PROOF_RV);
        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("Validator evidence submission (invalid becomes valid) gas cost", gasUsed);
        emit log_string("Function: submitCorrectEvidence (refund and become valid)");
        emit log_named_address("Selected challenger", selectedChallenger);
        emit log_string("");
    }

    // Run all gas comparison tests
    function test_gas_comparison_all_scenarios() public {
        emit log_string("=== RAT Gas Cost Analysis - All Scenarios ===");
        emit log_string("");

        test_gas_original_op_mainnet();
        test_gas_rat_triggered_no_valid_challengers();
        test_gas_rat_triggered_valid_challenger_stays_valid();
        test_gas_rat_triggered_valid_challenger_becomes_invalid();
        test_gas_validator_evidence_valid_challenger_refund();
        test_gas_validator_evidence_invalid_challenger_becomes_valid();

        emit log_string("=== Gas Cost Summary ===");
        emit log_string("Note: Actual gas costs will be displayed when tests are run");
        emit log_string("Compare the gas costs to understand RAT overhead");
    }
}
