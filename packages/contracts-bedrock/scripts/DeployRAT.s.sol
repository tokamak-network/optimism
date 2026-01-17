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
        address factory = vm.envOr("RAT_FACTORY", deployer);
        uint256 probability = vm.envOr("RAT_TRIGGER_PROBABILITY", uint256(50000));

        // 1. Deploy Implementation
        RAT ratImpl = new RAT();
        console2.log("RAT Implementation deployed at:", address(ratImpl));

        // 2. Deploy Proxy
        // Set deployer as admin to allow upgrade
        Proxy proxy = new Proxy(deployer);
        console2.log("Proxy deployed at:", address(proxy));

        // 3. Initialize Data
        // By default we use 'deployer' as a fake DisputeGameFactory for ad-hoc testing.
        // For E2E integration, set RAT_FACTORY=<DisputeGameFactoryProxy>.
        bytes memory initData = abi.encodeWithSelector(
            RAT.initialize.selector,
            IDisputeGameFactory(factory),
            0.1 ether,                     // Bond Amount
            60,                            // Period (blocks)
            1 ether,                       // Min Stake
            probability,                   // Probability
            5000,                          // Offline Penalty Rate (50%)
            deployer                       // Manager
        );

        // 4. Upgrade and Initialize
        proxy.upgradeToAndCall(address(ratImpl), initData);
        console2.log("RAT Proxy initialized and ready at:", address(proxy));

        vm.stopBroadcast();
    }
}
