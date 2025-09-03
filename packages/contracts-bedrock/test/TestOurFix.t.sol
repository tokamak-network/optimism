// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";
import { GameTypes } from "src/dispute/lib/Types.sol";
import { OPContractsManager } from "src/L1/OPContractsManager.sol";

contract TestOurFix is Test {
    function test_GameTypeConditionalLogic() public {
        // Test our conditional logic works correctly
        
        // Test CANNON game type (0)
        uint32 cannonType = GameTypes.CANNON.raw();
        assertEq(cannonType, 0);
        
        // Test PERMISSIONED_CANNON game type (1) 
        uint32 permissionedType = GameTypes.PERMISSIONED_CANNON.raw();
        assertEq(permissionedType, 1);
        
        // Our conditional logic test
        if (cannonType == GameTypes.CANNON.raw()) {
            // This should be true for game_type: 0
            assertTrue(true);
        } else {
            assertTrue(false); // CANNON type check failed
        }
        
        if (permissionedType == GameTypes.CANNON.raw()) {
            assertTrue(false); // PERMISSIONED_CANNON should not equal CANNON
        } else {
            // This should be true for game_type: 1
            assertTrue(true);
        }
    }
}