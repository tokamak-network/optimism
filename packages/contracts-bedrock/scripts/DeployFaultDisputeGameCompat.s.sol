// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import { FaultDisputeGame } from "src/dispute/FaultDisputeGame.sol";
import { IFaultDisputeGame } from "interfaces/dispute/IFaultDisputeGame.sol";

/// @notice Deploy a FaultDisputeGame implementation using constructor params copied from an existing implementation.
///         This is intended for devnet runtime upgrades where we need a byte-for-byte compatible configuration
///         with small code changes (e.g., extraData length handling).
contract DeployFaultDisputeGameCompat is Script {
    function run() public {
        address existingAddr = vm.envAddress("EXISTING_FDG_IMPL");
        IFaultDisputeGame existing = IFaultDisputeGame(existingAddr);

        FaultDisputeGame.GameConstructorParams memory p = FaultDisputeGame.GameConstructorParams({
            gameType: existing.gameType(),
            absolutePrestate: existing.absolutePrestate(),
            maxGameDepth: existing.maxGameDepth(),
            splitDepth: existing.splitDepth(),
            clockExtension: existing.clockExtension(),
            maxClockDuration: existing.maxClockDuration(),
            vm: existing.vm(),
            weth: existing.weth(),
            anchorStateRegistry: existing.anchorStateRegistry(),
            l2ChainId: existing.l2ChainId()
        });

        vm.startBroadcast();
        FaultDisputeGame deployed = new FaultDisputeGame(p);
        vm.stopBroadcast();

        console2.log("FaultDisputeGameCompat deployed at:", address(deployed));
        console2.log("Copied from existing impl:", existingAddr);
    }
}

