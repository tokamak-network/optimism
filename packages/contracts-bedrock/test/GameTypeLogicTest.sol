// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { GameTypes } from "../src/dispute/lib/Types.sol";

/**
 * @title GameTypeLogicTest
 * @dev Simple test contract to verify our conditional game deployment logic
 */
contract GameTypeLogicTest {
    enum DeploymentType {
        FaultDisputeGame,
        PermissionedDisputeGame
    }

    function testConditionalLogic(uint32 disputeGameType) external pure returns (DeploymentType) {
        // This replicates the exact logic from our OPContractsManager fix
        if (disputeGameType == GameTypes.CANNON.raw()) {
            return DeploymentType.FaultDisputeGame;
        } else {
            return DeploymentType.PermissionedDisputeGame;
        }
    }

    function getGameTypes() external pure returns (uint32 cannon, uint32 permissioned) {
        cannon = GameTypes.CANNON.raw();
        permissioned = GameTypes.PERMISSIONED_CANNON.raw();
    }
}
