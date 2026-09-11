// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {VestingWallet} from "../src/VestingWallet.sol";
import {VaultKitFactory} from "../src/VaultKitFactory.sol";
import {VaultKitRegistry} from "../src/VaultKitRegistry.sol";

/// @notice Deploys the VestingWallet implementation, a factory, and a registry, then registers the
///         factory as version `v1`.
///
///   forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast --verify
///
/// Requires PRIVATE_KEY in the environment.
contract Deploy is Script {
    function run()
        external
        returns (VestingWallet implementation, VaultKitFactory factory, VaultKitRegistry registry)
    {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        implementation = new VestingWallet();
        factory = new VaultKitFactory(address(implementation), deployer);
        registry = new VaultKitRegistry(deployer);
        registry.registerFactory(address(factory), "v1");

        vm.stopBroadcast();

        console2.log("VestingWallet implementation:", address(implementation));
        console2.log("VaultKitFactory:            ", address(factory));
        console2.log("VaultKitRegistry:           ", address(registry));
        console2.log("Owner:                      ", deployer);
    }
}
