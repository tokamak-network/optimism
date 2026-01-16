// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { CommonTest } from "test/setup/CommonTest.sol";
import { RAT } from "src/L1/RAT.sol";
import { Proxy } from "src/universal/Proxy.sol";
import { IDisputeGameFactory } from "interfaces/dispute/IDisputeGameFactory.sol";
import { IDisputeGame } from "interfaces/dispute/IDisputeGame.sol";
import { GameTypes } from "src/dispute/lib/Types.sol";

/// @title RAT_GasTest_Legacy
/// @notice Legacy gas tests (not used in README)
contract RAT_GasTest_Legacy is CommonTest {
    RAT public rat;
    address public mockDisputeGameFactory;
    address public mockFaultDisputeGame;

    uint256 public constant SLASH_BOND_AMOUNT = 1 ether;
    uint256 public constant EVIDENCE_SUBMISSION_PERIOD = 100;
    uint256 public constant MINIMUM_STAKE_AMOUNT = 2 ether;
    uint256 public constant OFFLINE_PENALTY_RATE = 5000; // 50%

    function setUp() public override {
        super.setUp();

        mockDisputeGameFactory = address(disputeGameFactory);
        mockFaultDisputeGame = makeAddr("mockFaultDisputeGame");

        vm.prank(disputeGameFactory.owner());
        disputeGameFactory.setImplementation(GameTypes.CANNON, IDisputeGame(mockFaultDisputeGame));

        RAT ratImpl = new RAT();
        Proxy ratProxy = new Proxy(address(1));
        rat = RAT(payable(address(ratProxy)));

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
                    100000,
                    OFFLINE_PENALTY_RATE,
                    address(1)
                )
            )
        );

        vm.prank(address(1));
        rat.setRatTriggerProbability(100000);
    }

    function test_stake_gas_measurement() public {
        address challenger = address(0x1234);
        uint256 stakeAmount = 0.2 ether;
        vm.deal(challenger, 10 ether);

        vm.prank(challenger);
        uint256 gasStart = gasleft();
        rat.stake{value: stakeAmount}();
        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("RAT stake() gas used", gasUsed);
        RAT.ChallengerInfo memory info = rat.getChallengerInfo(challenger);
        assertEq(info.stakingAmount, stakeAmount);
    }

    function test_triggerAttentionTest_gas_measurement() public {
        address challenger = address(0x1234);
        vm.deal(challenger, 10 ether);
        vm.prank(challenger);
        rat.stake{value: 2 ether}();

        address gameAddress = address(0x5678);
        bytes32 version = bytes32(0);
        bytes32 stateRoot = keccak256("test_state_root");
        bytes32 messagePasserRoot = keccak256("msgPasserRoot");
        bytes32 blockHash = keccak256("blockHash");
        bytes32 outputRoot = keccak256(abi.encode(version, stateRoot, messagePasserRoot, blockHash));

        vm.prank(mockDisputeGameFactory);
        uint256 gasStart = gasleft();
        rat.triggerAttentionTest(gameAddress, outputRoot, bytes32(0), uint64(block.number));
        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("RAT triggerAttentionTest() gas used", gasUsed);

        RAT.AttentionInfo memory info = rat.getAttentionTest(gameAddress);
        assertEq(info.outputRoot, outputRoot);
        assertEq(info.status, rat.STATUS_PENDING());
    }

    function test_submitCandidate_gas_measurement() public {
        address challenger = address(0x1234);
        vm.deal(challenger, 10 ether);
        vm.prank(challenger);
        rat.stake{value: 2 ether}();

        address gameAddress = address(0x5678);
        bytes32 version = bytes32(0);
        bytes32 stateRoot = keccak256("test_state_root");
        bytes32 messagePasserRoot = keccak256("msgPasserRoot");
        bytes32 blockHash = keccak256("blockHash");
        bytes32 outputRoot = keccak256(abi.encode(version, stateRoot, messagePasserRoot, blockHash));

        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, outputRoot, bytes32(0), uint64(block.number));

        RAT.AttentionInfo memory info = rat.getAttentionTest(gameAddress);
        bytes32 candidateKey = bytes32(uint256(uint160(address(0x1234))));

        vm.prank(info.challengerAddress);
        uint256 gasStart = gasleft();
        rat.submitCandidate(gameAddress, candidateKey, stateRoot, version, messagePasserRoot, blockHash);
        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("RAT submitCandidate() gas used", gasUsed);
    }

    function test_disputeByNonInclusion_gas_measurement() public {
        address challenger = address(0x1234);
        vm.deal(challenger, 10 ether);
        vm.prank(challenger);
        rat.stake{value: 2 ether}();

        address gameAddress = address(0x5678);
        bytes32 version = bytes32(0);
        bytes32 stateRoot = keccak256("test_state_root");
        bytes32 messagePasserRoot = keccak256("msgPasserRoot");
        bytes32 blockHash = keccak256("blockHash");
        bytes32 outputRoot = keccak256(abi.encode(version, stateRoot, messagePasserRoot, blockHash));

        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, outputRoot, bytes32(0), uint64(block.number));

        RAT.AttentionInfo memory info = rat.getAttentionTest(gameAddress);
        bytes32 candidateKey = bytes32(uint256(1));

        vm.prank(info.challengerAddress);
        rat.submitCandidate(gameAddress, candidateKey, stateRoot, version, messagePasserRoot, blockHash);

        bytes[] memory proof;
        uint256 gasStart = gasleft();
        try rat.disputeByNonInclusion(gameAddress, candidateKey, stateRoot, version, messagePasserRoot, blockHash, proof) {
            // noop
        } catch {
            // ignore revert in gas estimate path
        }
        uint256 gasUsed = gasStart - gasleft();
        emit log_named_uint("RAT disputeByNonInclusion() gas used", gasUsed);
    }

    function test_disputeByCloserKey_gas_measurement() public {
        address challenger = address(0x1234);
        vm.deal(challenger, 10 ether);
        vm.prank(challenger);
        rat.stake{value: 2 ether}();

        address gameAddress = address(0x5678);
        bytes32 version = bytes32(0);
        bytes32 stateRoot = keccak256("test_state_root");
        bytes32 messagePasserRoot = keccak256("msgPasserRoot");
        bytes32 blockHash = keccak256("blockHash");
        bytes32 outputRoot = keccak256(abi.encode(version, stateRoot, messagePasserRoot, blockHash));

        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, outputRoot, bytes32(0), uint64(block.number));

        RAT.AttentionInfo memory info = rat.getAttentionTest(gameAddress);
        bytes32 candidateKey = bytes32(uint256(2));

        vm.prank(info.challengerAddress);
        rat.submitCandidate(gameAddress, candidateKey, stateRoot, version, messagePasserRoot, blockHash);

        bytes[] memory proof;
        uint256 gasStart = gasleft();
        try rat.disputeByCloserKey(gameAddress, bytes32(uint256(1)), stateRoot, version, messagePasserRoot, blockHash, proof) {
            // noop
        } catch {
            // ignore revert in gas estimate path
        }
        uint256 gasUsed = gasStart - gasleft();
        emit log_named_uint("RAT disputeByCloserKey() gas used", gasUsed);
    }

    function test_resolveClaim_gas_measurement() public {
        address challenger = address(0x1234);
        vm.deal(challenger, 10 ether);
        vm.prank(challenger);
        rat.stake{value: 2 ether}();

        address gameAddress = address(0x5678);
        bytes32 version = bytes32(0);
        bytes32 stateRoot = keccak256("test_state_root");
        bytes32 messagePasserRoot = keccak256("msgPasserRoot");
        bytes32 blockHash = keccak256("blockHash");
        bytes32 outputRoot = keccak256(abi.encode(version, stateRoot, messagePasserRoot, blockHash));

        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, outputRoot, bytes32(0), uint64(block.number));

        RAT.AttentionInfo memory info = rat.getAttentionTest(gameAddress);
        uint256 gasStart = gasleft();
        vm.prank(gameAddress);
        rat.resolveClaim(info.challengerAddress);
        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("RAT resolveClaim() gas used", gasUsed);
    }
}
