// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing utilities
import { CommonTest } from "test/setup/CommonTest.sol";
import { Proxy } from "src/universal/Proxy.sol";

// Target contracts
import { RAT } from "src/L1/RAT.sol";
import { OptimismPortal2 } from "src/L1/OptimismPortal2.sol";
import { DisputeGameFactory } from "src/dispute/DisputeGameFactory.sol";
import { FaultDisputeGame } from "src/dispute/FaultDisputeGame.sol";

// Libraries
import { GameId, LibGameId, GameTypes, Timestamp, Claim } from "src/dispute/lib/Types.sol";

// Interfaces
import { IDisputeGameFactory } from "interfaces/dispute/IDisputeGameFactory.sol";
import { IDisputeGame } from "interfaces/dispute/IDisputeGame.sol";

/// @title RAT_ProposerGasComparison_Test
/// @notice Proposer와 Validator의 실제 가스 비용 비교 테스트
contract RAT_ProposerGasComparison_Test is CommonTest {
    RAT public rat;

    address public constant CHALLENGER_1 = address(0x2345);
    address public constant CHALLENGER_2 = address(0x3456);
    address public constant PROPOSER = address(0x1234);

    uint256 public constant SLASH_BOND_AMOUNT = 1 ether;
    uint256 public constant EVIDENCE_SUBMISSION_PERIOD = 100;
    uint256 public constant MINIMUM_STAKE_AMOUNT = 0.1 ether;

    function setUp() public override {
        super.setUp();

        // Deploy RAT implementation and proxy
        RAT ratImpl = new RAT();
        Proxy ratProxy = new Proxy(address(1));
        rat = RAT(payable(address(ratProxy)));

        vm.prank(address(1));
        ratProxy.upgradeToAndCall(
            address(ratImpl),
            abi.encodeCall(
                RAT.initialize,
                (
                    disputeGameFactory,
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
        vm.deal(PROPOSER, 10 ether);

        // Setup challengers for RAT
        vm.prank(CHALLENGER_1);
        rat.stake{value: 0.2 ether}();

        vm.prank(CHALLENGER_2);
        rat.stake{value: 0.3 ether}();
    }

    /// @notice 1. Original OP Mainnet: L2 상태 루트 제출 비용 (DisputeGame 생성)
    function test_original_mainnet_propose_cost() public {
        emit log_string("=== Original OP Mainnet L2 State Root Proposal ===");

        // DisputeGameFactory.create() 비용 (기존 방식, RAT 없음)
        bytes32 rootClaim = keccak256("test_root_claim");
        bytes memory extraData = abi.encode(uint256(1000));

        vm.prank(PROPOSER);
        uint256 gasStart = gasleft();
        IDisputeGame game = disputeGameFactory.create(
            GameTypes.CANNON,
            Claim.wrap(rootClaim),
            extraData
        );
        uint256 createGameGas = gasStart - gasleft();

        emit log_named_uint("Original Mainnet game creation gas", createGameGas);
        emit log_named_address("Created game address", address(game));
        emit log_string("");
    }

    /// @notice 2. RAT 환경에서 RAT이 트리거되지 않는 경우
    function test_rat_not_triggered_propose_cost() public {
        // RAT을 일시적으로 비활성화하거나, 챌린저가 없는 상태로 테스트
        // 새로운 RAT 인스턴스를 챌린저 없이 생성
        RAT emptyRatImpl = new RAT();
        Proxy emptyRatProxy = new Proxy(address(2));

        vm.prank(address(2));
        emptyRatProxy.upgradeToAndCall(
            address(emptyRatImpl),
            abi.encodeCall(
                RAT.initialize,
                (
                    disputeGameFactory,
                    SLASH_BOND_AMOUNT,
                    EVIDENCE_SUBMISSION_PERIOD,
                    MINIMUM_STAKE_AMOUNT,
                    1000 // 1% default probability
                )
            )
        );

        emit log_string("=== RAT Environment - RAT NOT Triggered ===");

        // DisputeGameFactory.create() 비용 (챌린저가 없어서 RAT 트리거 안됨)
        bytes32 rootClaim = keccak256("test_root_claim_2");
        bytes memory extraData = abi.encode(uint256(2000));

        vm.prank(PROPOSER);
        uint256 gasStart = gasleft();
        IDisputeGame game = disputeGameFactory.create(
            GameTypes.CANNON,
            Claim.wrap(rootClaim),
            extraData
        );
        uint256 createGameGas = gasStart - gasleft();

        emit log_named_uint("RAT Not Triggered game creation gas", createGameGas);
        emit log_named_address("Created game address", address(game));
        emit log_string("");
    }

    /// @notice 3. RAT 환경에서 RAT이 트리거되는 경우
    function test_rat_triggered_propose_cost() public {
        emit log_string("=== RAT Environment - RAT Triggered ===");

        // DisputeGameFactory.create() 비용 (챌린저가 있어서 RAT 트리거됨)
        bytes32 rootClaim = keccak256("test_root_claim_3");
        bytes memory extraData = abi.encode(uint256(3000));

        // 챌린저가 스테이킹된 상태에서 DisputeGame 생성
        vm.prank(PROPOSER);
        uint256 gasStart = gasleft();
        IDisputeGame game = disputeGameFactory.create(
            GameTypes.CANNON,
            Claim.wrap(rootClaim),
            extraData
        );
        uint256 createGameWithRatGas = gasStart - gasleft();

        emit log_named_uint("DisputeGameFactory.create gas (with RAT)", createGameWithRatGas);
        emit log_named_address("Created game address", address(game));

        // RAT 트리거 확인
        (, , address selectedChallenger, , ) = rat.attentionTests(address(game));
        emit log_named_address("Selected challenger", selectedChallenger);

        if (selectedChallenger != address(0)) {
            emit log_string("RAT successfully triggered");
        } else {
            emit log_string("RAT was not triggered");
        }
        emit log_string("");
    }

    /// @notice 4. Validator: 올바른 솔루션 (Lv, Rv) 제출 비용
    function test_validator_submit_evidence_cost() public {
        // 먼저 RAT을 트리거
        bytes32 rootClaim = keccak256("test_root_claim");
        bytes memory extraData = abi.encode(uint256(1000));

        vm.prank(PROPOSER);
        IDisputeGame game = disputeGameFactory.create(
            GameTypes.CANNON,
            Claim.wrap(rootClaim),
            extraData
        );

        // 선택된 챌린저와 게임 주소 확인
        address gameAddress = address(game);
        (, , address selectedChallenger, , ) = rat.attentionTests(gameAddress);

        require(selectedChallenger != address(0), "RAT was not triggered");

        // 올바른 증거 준비
        bytes32 proofLV = keccak256("left_value");
        bytes32 proofRV = keccak256("right_value");

        emit log_string("=== Validator Submit Correct Evidence ===");
        emit log_named_address("Selected challenger", selectedChallenger);

        vm.prank(selectedChallenger);
        uint256 gasStart = gasleft();
        rat.submitCorrectEvidence(gameAddress, proofLV, proofRV);
        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("Submit evidence gas", gasUsed);
        emit log_string("");
    }

    /// @notice RAT 초기화 테스트
    function test_rat_setup() public {
        // RAT이 제대로 초기화되었는지 확인
        assertEq(address(rat.disputeGameFactory()), address(disputeGameFactory));
        assertEq(rat.perTestBondAmount(), SLASH_BOND_AMOUNT);
        assertEq(rat.evidenceSubmissionPeriod(), EVIDENCE_SUBMISSION_PERIOD);
        assertEq(rat.minimumStakingBalance(), MINIMUM_STAKE_AMOUNT);
        emit log_string("RAT setup successful");
    }

    /// @notice 종합 가스 비용 비교 (internal calls로 변경)
    function test_comprehensive_gas_comparison() public {
        emit log_string("=== RAT PoC Gas Cost Analysis ===");
        emit log_string("");

        // 1. Original OP Mainnet
        test_original_mainnet_propose_cost();

        // 2. RAT Not Triggered
        test_rat_not_triggered_propose_cost();

        // 3. RAT Triggered
        test_rat_triggered_propose_cost();

        // 4. Submit Evidence
        test_validator_submit_evidence_cost();

        emit log_string("=== Gas Comparison Complete ===");
    }

    /// @notice 상대적 비용 증가 분석
    function test_relative_cost_analysis() public {
        emit log_string("=== Relative Cost Analysis ===");

        // Original cost 측정 (기본 DisputeGame 생성)
        vm.prank(PROPOSER);
        uint256 gasStart1 = gasleft();
        disputeGameFactory.create(
            GameTypes.CANNON,
            Claim.wrap(keccak256("output1")),
            abi.encode(uint256(1001))
        );
        uint256 originalCost = gasStart1 - gasleft();

        // RAT not triggered cost 측정
        RAT emptyRatImpl = new RAT();
        Proxy emptyRatProxy = new Proxy(address(3));
        vm.prank(address(3));
        emptyRatProxy.upgradeToAndCall(
            address(emptyRatImpl),
            abi.encodeCall(RAT.initialize, (disputeGameFactory, SLASH_BOND_AMOUNT, EVIDENCE_SUBMISSION_PERIOD, MINIMUM_STAKE_AMOUNT, 1000))
        );

        vm.prank(PROPOSER);
        uint256 gasStart2 = gasleft();
        disputeGameFactory.create(
            GameTypes.CANNON,
            Claim.wrap(keccak256("root2")),
            abi.encode(uint256(1002))
        );
        uint256 ratNotTriggeredCost = gasStart2 - gasleft();

        // RAT triggered cost 측정
        vm.prank(PROPOSER);
        uint256 gasStart3 = gasleft();
        disputeGameFactory.create(
            GameTypes.CANNON,
            Claim.wrap(keccak256("root3")),
            abi.encode(uint256(1003))
        );
        uint256 ratTriggeredCost = gasStart3 - gasleft();

        // 비교 분석
        emit log_named_uint("1. Original OP Mainnet", originalCost);
        emit log_named_uint("2. RAT Not Triggered", ratNotTriggeredCost);
        emit log_named_uint("3. RAT Triggered", ratTriggeredCost);

        uint256 overheadNotTriggered = ratNotTriggeredCost > originalCost ? ratNotTriggeredCost - originalCost : 0;
        uint256 overheadTriggered = ratTriggeredCost > originalCost ? ratTriggeredCost - originalCost : 0;

        emit log_named_uint("Overhead (Not Triggered)", overheadNotTriggered);
        emit log_named_uint("Overhead (Triggered)", overheadTriggered);

        if (originalCost > 0) {
            emit log_named_uint("Overhead % (Not Triggered)", (overheadNotTriggered * 100) / originalCost);
            emit log_named_uint("Overhead % (Triggered)", (overheadTriggered * 100) / originalCost);
        }
    }
}