// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { CommonTest } from "../setup/CommonTest.sol";
import { DisputeGameFactory } from "src/dispute/DisputeGameFactory.sol";
import { RAT } from "src/L1/RAT.sol";
import { Proxy } from "src/universal/Proxy.sol";
import { GameType, Claim, Timestamp, Hash, LibGameId, GameTypes } from "src/dispute/lib/Types.sol";
import { NoImplementation, IncorrectBondAmount, GameAlreadyExists } from "src/dispute/lib/Errors.sol";
import { IDisputeGame } from "interfaces/dispute/IDisputeGame.sol";
import { DisputeGameFactory_FakeClone_Harness } from "../dispute/DisputeGameFactory.t.sol";

/// @notice A fake clone used for testing the `DisputeGameFactory` contract's `create` function with RAT support.
contract DisputeGameFactory_FakeClone_Harness_RAT {
    function initialize() external payable {
        // noop
    }

    function initialize(address _rat) external payable {
        // noop - RAT address is ignored for testing
    }

    function extraData() external pure returns (bytes memory) {
        return hex"FF0420";
    }

    function parentHash() external pure returns (bytes32) {
        return bytes32(0);
    }

    function rootClaim() external pure returns (Claim) {
        return Claim.wrap(bytes32(0));
    }
}

contract DisputeGameFactory_GasTest is CommonTest {
    RAT public rat;

    uint256 constant INIT_BOND = 1 ether;
    uint256 constant MINIMUM_STAKE_AMOUNT = 2 ether;
    uint256 constant PER_TEST_BOND_AMOUNT = 1 ether;
    uint64 constant EVIDENCE_SUBMISSION_PERIOD = 1 hours;

    address public challenger = address(0x123);
    address public proposer = address(0x456);

    function setUp() public override {
        super.setUp();

        // Deploy RAT
        RAT ratImpl = new RAT();
        Proxy ratProxy = new Proxy(address(1));
        vm.prank(address(1));
        ratProxy.upgradeToAndCall(
            address(ratImpl),
            abi.encodeWithSelector(
                RAT.initialize.selector,
                address(disputeGameFactory), // Use existing disputeGameFactory
                PER_TEST_BOND_AMOUNT,
                EVIDENCE_SUBMISSION_PERIOD,
                MINIMUM_STAKE_AMOUNT,
                100000, // ratTriggerProbability (100%)
                address(1) // manager
            )
        );
        rat = RAT(address(ratProxy));

        // Transfer ownership of the factory to the test contract
        vm.prank(disputeGameFactory.owner());
        disputeGameFactory.transferOwnership(address(this));

        // Set RAT address in factory
        vm.prank(address(this));
        disputeGameFactory.setRAT(address(rat));

        // Set up fake game implementations for testing
        DisputeGameFactory_FakeClone_Harness fakeClone1 = new DisputeGameFactory_FakeClone_Harness();
        DisputeGameFactory_FakeClone_Harness_RAT fakeCloneCannon = new DisputeGameFactory_FakeClone_Harness_RAT();
        vm.prank(address(this));
        disputeGameFactory.setImplementation(GameType.wrap(1), IDisputeGame(address(fakeClone1)));
        vm.prank(address(this));
        disputeGameFactory.setImplementation(GameTypes.CANNON, IDisputeGame(address(fakeCloneCannon)));

        // Stake challenger
        vm.deal(challenger, 10 ether);
        vm.prank(challenger);
        rat.stake{value: MINIMUM_STAKE_AMOUNT}();

        // Deal ETH to proposer
        vm.deal(proposer, 10 ether);
    }

        function test_create_game_without_rat_gas_measurement() public {
        // Create game without RAT (different game type)
        GameType gameType = GameType.wrap(1); // Non-CANNON game type
        Claim rootClaim = Claim.wrap(bytes32(uint256(0x123)));
        bytes memory extraData = "";

        // Set bond for this game type
        uint256 bond = disputeGameFactory.initBonds(gameType);
        if (bond == 0) {
            // Set a default bond if none is set
            vm.prank(address(this));
            disputeGameFactory.setInitBond(gameType, INIT_BOND);
            bond = INIT_BOND;
        }

        uint256 gasBefore = gasleft();
        vm.prank(proposer);
        disputeGameFactory.create{value: bond}(gameType, rootClaim, extraData);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("create() without RAT", gasUsed);
    }

        function test_create_game_with_rat_not_triggered_gas_measurement() public {
        // Create CANNON game but RAT not triggered (no valid challengers)
        GameType gameType = GameTypes.CANNON;
        Claim rootClaim = Claim.wrap(bytes32(uint256(0x123)));
        bytes memory extraData = "";

        // Set bond for CANNON game type
        uint256 bond = disputeGameFactory.initBonds(gameType);
        if (bond == 0) {
            // Set a default bond if none is set
            vm.prank(address(this));
            disputeGameFactory.setInitBond(gameType, INIT_BOND);
            bond = INIT_BOND;
        }

        // Remove challenger by setting RAT to zero address
        vm.prank(address(this));
        disputeGameFactory.setRAT(address(0));

        uint256 gasBefore = gasleft();
        vm.prank(proposer);
        disputeGameFactory.create{value: bond}(gameType, rootClaim, extraData);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("create() with RAT not triggered", gasUsed);
    }

        function test_create_game_with_rat_triggered_gas_measurement() public {
        // Create CANNON game with RAT triggered (valid challengers exist)
        GameType gameType = GameTypes.CANNON;
        Claim rootClaim = Claim.wrap(bytes32(uint256(0x123)));
        bytes memory extraData = "";

        // Set bond for CANNON game type
        uint256 bond = disputeGameFactory.initBonds(gameType);
        if (bond == 0) {
            // Set a default bond if none is set
            vm.prank(address(this));
            disputeGameFactory.setInitBond(gameType, INIT_BOND);
            bond = INIT_BOND;
        }

        uint256 gasBefore = gasleft();
        vm.prank(proposer);
        disputeGameFactory.create{value: bond}(gameType, rootClaim, extraData);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("create() with RAT triggered", gasUsed);
    }

        function test_create_game_with_rat_triggered_multiple_challengers_gas_measurement() public {
        // Create CANNON game with multiple valid challengers
        GameType gameType = GameTypes.CANNON;
        Claim rootClaim = Claim.wrap(bytes32(uint256(0x123)));
        bytes memory extraData = "";

        // Set bond for CANNON game type
        uint256 bond = disputeGameFactory.initBonds(gameType);
        if (bond == 0) {
            // Set a default bond if none is set
            vm.prank(address(this));
            disputeGameFactory.setInitBond(gameType, INIT_BOND);
            bond = INIT_BOND;
        }

        // Add more challengers
        address challenger2 = address(0x789);
        address challenger3 = address(0xABC);

        vm.deal(challenger2, 10 ether);
        vm.deal(challenger3, 10 ether);

        vm.prank(challenger2);
        rat.stake{value: MINIMUM_STAKE_AMOUNT}();

        vm.prank(challenger3);
        rat.stake{value: MINIMUM_STAKE_AMOUNT}();

        uint256 gasBefore = gasleft();
        vm.prank(proposer);
        disputeGameFactory.create{value: bond}(gameType, rootClaim, extraData);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("create() with RAT triggered (multiple challengers)", gasUsed);
    }
}
