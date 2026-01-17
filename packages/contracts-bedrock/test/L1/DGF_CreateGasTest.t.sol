// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { DisputeGameFactory } from "src/dispute/DisputeGameFactory.sol";
import { RAT } from "src/L1/RAT.sol";
import { Proxy } from "src/universal/Proxy.sol";

import { IDisputeGame } from "interfaces/dispute/IDisputeGame.sol";
import { IDisputeGameFactory } from "interfaces/dispute/IDisputeGameFactory.sol";
import { Timestamp, GameStatus, GameType, Claim, Hash, GameTypes } from "src/dispute/lib/Types.sol";

contract MockDisputeGame is IDisputeGame {
    // minimal init hooks
    function initialize() external payable override {}
    function initialize(address) external payable override {}

    // required interface fns (mostly unused by gas test)
    function createdAt() external view override returns (Timestamp) { return Timestamp.wrap(uint64(block.timestamp)); }
    function resolvedAt() external view override returns (Timestamp) { return Timestamp.wrap(0); }
    function status() external view override returns (GameStatus) { return GameStatus.IN_PROGRESS; }
    function gameType() external pure override returns (GameType gameType_) { return GameTypes.CANNON; }

    function gameCreator() external pure override returns (address creator_) { return address(0); }
    function rootClaim() external pure override returns (Claim rootClaim_) { return Claim.wrap(bytes32(0)); }
    function l1Head() external pure override returns (Hash l1Head_) { return Hash.wrap(bytes32(0)); }
    function l2SequenceNumber() external pure override returns (uint256 l2SequenceNumber_) { return 0; }
    function extraData() external pure override returns (bytes memory extraData_) { return ""; }

    function resolve() external override returns (GameStatus status_) { return GameStatus.IN_PROGRESS; }
    function gameData() external view override returns (GameType gameType_, Claim rootClaim_, bytes memory extraData_) {
        return (GameTypes.CANNON, Claim.wrap(bytes32(0)), "");
    }
    function wasRespectedGameTypeWhenCreated() external view override returns (bool) { return true; }
}

contract DGF_CreateGasTest is Test {
    DisputeGameFactory dgf;
    RAT rat;

    function setUp() public {
        // Deploy DGF behind a Proxy (implementation disables initializers).
        DisputeGameFactory dgfImpl = new DisputeGameFactory();
        Proxy dgfProxy = new Proxy(address(this));
        dgfProxy.upgradeToAndCall(
            address(dgfImpl),
            abi.encodeCall(DisputeGameFactory.initialize, (address(this)))
        );
        dgf = DisputeGameFactory(address(dgfProxy));

        MockDisputeGame impl = new MockDisputeGame();
        dgf.setImplementation(GameTypes.CANNON, IDisputeGame(address(impl)));
        dgf.setInitBond(GameTypes.CANNON, 0);

        // Deploy RAT behind a Proxy to match production shape.
        RAT ratImpl = new RAT();
        Proxy ratProxy = new Proxy(address(this));
        ratProxy.upgradeToAndCall(
            address(ratImpl),
            abi.encodeCall(
                RAT.initialize,
                (
                    IDisputeGameFactory(address(dgf)),
                    0.1 ether, // bond
                    3,         // period
                    1 ether,   // min stake
                    0,         // trigger prob (set per test)
                    0,
                    address(this)
                )
            )
        );
        rat = RAT(payable(address(ratProxy)));

        // Add 2 validators so RAT can trigger deterministically.
        vm.deal(address(0xA11CE), 10 ether);
        vm.prank(address(0xA11CE));
        rat.stake{ value: 1.2 ether }();
        vm.deal(address(0xB0B), 10 ether);
        vm.prank(address(0xB0B));
        rat.stake{ value: 1.2 ether }();
    }

    function _createOnce() internal returns (uint256 gasUsed) {
        Claim root = Claim.wrap(keccak256("root"));
        bytes memory extra = abi.encodePacked(bytes32(uint256(1234)), bytes32(uint256(5678))); // 64B
        uint256 start = gasleft();
        dgf.create(GameTypes.CANNON, root, extra);
        return start - gasleft();
    }

    /// Baseline: RAT not applied at all (rat==0 so no external call).
    function test_gas_create_baseline_noRAT() public {
        dgf.setRAT(address(0));
        uint256 g = _createOnce();
        console.log("create() baseline (no RAT):", g);
    }

    /// RAT applied but not triggered: external call happens, but RAT returns immediately (prob=0).
    function test_gas_create_withRAT_notTriggered() public {
        rat.setRatTriggerProbability(0);
        dgf.setRAT(address(rat));
        uint256 g = _createOnce();
        console.log("create() with RAT (not triggered):", g);
    }

    /// RAT applied and triggered: prob=100000 -> deterministic trigger path.
    function test_gas_create_withRAT_triggered() public {
        rat.setRatTriggerProbability(100000);
        dgf.setRAT(address(rat));
        uint256 g = _createOnce();
        console.log("create() with RAT (triggered):", g);
    }
}

