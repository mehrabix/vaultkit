// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {VaultKitRegistry} from "../src/VaultKitRegistry.sol";

contract VaultKitRegistryTest is Test {
    VaultKitRegistry internal registry;

    address internal owner = makeAddr("owner");
    address internal stranger = makeAddr("stranger");
    address internal factoryA = makeAddr("factoryA");
    address internal factoryB = makeAddr("factoryB");

    event FactoryRegistered(uint256 indexed version, address indexed factory, string label);

    function setUp() public {
        registry = new VaultKitRegistry(owner);
    }

    function test_Register_AppendsVersion() public {
        vm.expectEmit(true, true, false, true, address(registry));
        emit FactoryRegistered(1, factoryA, "v1");

        vm.prank(owner);
        uint256 version = registry.registerFactory(factoryA, "v1");

        assertEq(version, 1);
        assertEq(registry.factoryCount(), 1);
        assertTrue(registry.isFactory(factoryA));

        VaultKitRegistry.FactoryVersion memory entry = registry.factoryAt(0);
        assertEq(entry.version, 1);
        assertEq(entry.factory, factoryA);
        assertEq(entry.label, "v1");
        assertEq(entry.addedAt, block.timestamp);
    }

    function test_Register_IncrementsVersions() public {
        vm.startPrank(owner);
        registry.registerFactory(factoryA, "v1");
        uint256 second = registry.registerFactory(factoryB, "v2");
        vm.stopPrank();

        assertEq(second, 2);
        assertEq(registry.factoryCount(), 2);
        assertEq(registry.latestFactory(), factoryB);

        VaultKitRegistry.FactoryVersion[] memory all = registry.allFactories();
        assertEq(all.length, 2);
        assertEq(all[0].factory, factoryA);
        assertEq(all[1].factory, factoryB);
    }

    function test_Register_RevertsForNonOwner() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger)
        );
        registry.registerFactory(factoryA, "v1");
    }

    function test_Register_RevertsOnZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(VaultKitRegistry.ZeroAddress.selector);
        registry.registerFactory(address(0), "v1");
    }

    function test_Register_RevertsOnDuplicate() public {
        vm.startPrank(owner);
        registry.registerFactory(factoryA, "v1");
        vm.expectRevert(VaultKitRegistry.DuplicateFactory.selector);
        registry.registerFactory(factoryA, "v1-again");
        vm.stopPrank();
    }

    function test_LatestFactory_ZeroWhenEmpty() public view {
        assertEq(registry.factoryCount(), 0);
        assertEq(registry.latestFactory(), address(0));
    }
}
