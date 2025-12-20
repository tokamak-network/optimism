// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import { RAT } from "../src/L1/RAT.sol";
import { Proxy } from "../src/universal/Proxy.sol";
import { IDisputeGameFactory } from "../interfaces/dispute/IDisputeGameFactory.sol";

contract DeployRAT is Script {
    function run() public {
        vm.startBroadcast();

        address deployer = msg.sender;

        // 1. Deploy Implementation
        RAT ratImpl = new RAT();
        console2.log("RAT Implementation deployed at:", address(ratImpl));

        // 2. Deploy Proxy
        // Set deployer as admin to allow upgrade
        Proxy proxy = new Proxy(deployer);
        console2.log("Proxy deployed at:", address(proxy));

        // 3. Initialize Data
        // We use 'deployer' as the Fake DisputeGameFactory to allow manual testing
        bytes memory initData = abi.encodeWithSelector(
            RAT.initialize.selector,
            IDisputeGameFactory(deployer), // Fake Factory
            0.1 ether,                     // Bond Amount
            60,                            // Period (blocks)
            1 ether,                       // Min Stake
            50000,                         // Probability (50%)
            deployer                       // Manager
        );

        // 4. Upgrade and Initialize
        proxy.upgradeToAndCall(address(ratImpl), initData);
        console2.log("RAT Proxy initialized and ready at:", address(proxy));

        vm.stopBroadcast();
    }
}
