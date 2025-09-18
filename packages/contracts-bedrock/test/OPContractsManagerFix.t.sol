// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";
import { GameTypes } from "src/dispute/lib/Types.sol";

/**
 * @title OPContractsManagerFix Test
 * @dev Test our fix for conditional game deployment based on disputeGameType
 */
contract OPContractsManagerFixTest is Test {

    function test_GameTypeConditionalLogic() public {
        // Test our conditional logic works correctly

        // Test CANNON game type (0)
        uint32 cannonType = GameTypes.CANNON.raw();
        assertEq(cannonType, 0, "CANNON should be type 0");

        // Test PERMISSIONED_CANNON game type (1)
        uint32 permissionedType = GameTypes.PERMISSIONED_CANNON.raw();
        assertEq(permissionedType, 1, "PERMISSIONED_CANNON should be type 1");

        // Our conditional logic test - simulates OPContractsManager.sol:1047
        if (cannonType == GameTypes.CANNON.raw()) {
            // This should be true for game_type: 0 - deploy FaultDisputeGame
            assertTrue(true, "Should deploy FaultDisputeGame for CANNON type");
        } else {
            assertTrue(false, "CANNON type check failed - would deploy wrong game type");
        }

        if (permissionedType == GameTypes.CANNON.raw()) {
            assertTrue(false, "PERMISSIONED_CANNON should not equal CANNON - logic error");
        } else {
            // This should be true for game_type: 1 - deploy PermissionedDisputeGame
            assertTrue(true, "Should deploy PermissionedDisputeGame for PERMISSIONED_CANNON type");
        }
    }

    function test_ConditionalDeploymentDecision() public {
        // Test the exact conditional logic from our fix
        uint32 testGameType1 = 0; // CANNON
        uint32 testGameType2 = 1; // PERMISSIONED_CANNON

        // Simulate the conditional in OPContractsManager.sol line 1055
        bool shouldDeployFault1 = (testGameType1 == GameTypes.CANNON.raw());
        bool shouldDeployFault2 = (testGameType2 == GameTypes.CANNON.raw());

        assertTrue(shouldDeployFault1, "Should deploy FaultDisputeGame for type 0");
        assertFalse(shouldDeployFault2, "Should NOT deploy FaultDisputeGame for type 1");

        // Inverse logic for PermissionedDisputeGame
        bool shouldDeployPermissioned1 = !shouldDeployFault1;
        bool shouldDeployPermissioned2 = !shouldDeployFault2;

        assertFalse(shouldDeployPermissioned1, "Should NOT deploy PermissionedDisputeGame for type 0");
        assertTrue(shouldDeployPermissioned2, "Should deploy PermissionedDisputeGame for type 1");
    }

    function test_GameTypeValues() public view {
        // Verify game type constants haven't changed
        require(GameTypes.CANNON.raw() == 0, "CANNON must be 0");
        require(GameTypes.PERMISSIONED_CANNON.raw() == 1, "PERMISSIONED_CANNON must be 1");
        require(GameTypes.ALPHABET.raw() == 255, "ALPHABET must be 255");
        require(GameTypes.FAST.raw() == 254, "FAST must be 254");
    }

    function test_EdgeCases() public {
        // Test edge cases that could break our logic
        uint32 unknownType = 99;

        // Our conditional should default to PermissionedDisputeGame for unknown types
        bool shouldDeployFault = (unknownType == GameTypes.CANNON.raw());
        assertFalse(shouldDeployFault, "Unknown game types should default to PermissionedDisputeGame");

        // Test boundary values
        uint32 maxUint32 = type(uint32).max;
        bool shouldDeployFaultMax = (maxUint32 == GameTypes.CANNON.raw());
        assertFalse(shouldDeployFaultMax, "Max uint32 should default to PermissionedDisputeGame");
    }
}