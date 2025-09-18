// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Test } from "forge-std/Test.sol";
import { RAT } from "src/L1/RAT.sol";

contract CompileTest is Test {
    function test_compiles() public {
        RAT rat = new RAT();
        assertTrue(address(rat) != address(0));
    }
}