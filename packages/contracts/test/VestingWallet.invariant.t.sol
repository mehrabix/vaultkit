// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {VestingWallet} from "../src/VestingWallet.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {VestingHandler} from "./handlers/VestingHandler.sol";

/// @notice Invariants that must hold across *any* sequence of claim / revoke / reassign / time.
contract VestingWalletInvariantTest is Test {
    VestingWallet internal implementation;
    VestingWallet internal wallet;
    MockERC20 internal token;
    VestingHandler internal handler;

    address internal creator = makeAddr("creator");
    address internal beneficiary = makeAddr("beneficiary");

    uint64 internal constant START = 1_700_000_000;
    uint64 internal constant CLIFF = 90 days;
    uint64 internal constant DURATION = 365 days;
    uint256 internal constant TOTAL = 1_000_000 ether;

    function setUp() public {
        vm.warp(START);

        implementation = new VestingWallet();
        token = new MockERC20("Mock", "MCK", 18);
        wallet = VestingWallet(Clones.clone(address(implementation)));

        token.mint(creator, TOTAL);
        vm.startPrank(creator);
        token.approve(address(wallet), TOTAL);
        wallet.initialize(address(token), beneficiary, creator, START, CLIFF, DURATION, TOTAL, true);
        token.transfer(address(wallet), TOTAL);
        vm.stopPrank();

        handler = new VestingHandler(wallet, token, creator, beneficiary, TOTAL);
        targetContract(address(handler));
    }

    /// @dev Solvency: tokens still held + tokens claimed + tokens returned to the creator always
    ///      equals the amount originally funded. Nothing is ever minted or lost.
    function invariant_Solvency() public view {
        uint256 accounted =
            token.balanceOf(address(wallet)) + wallet.schedule().claimed + handler.returned();
        assertEq(accounted, TOTAL);
    }

    function invariant_ClaimedNeverExceedsTotal() public view {
        assertLe(wallet.schedule().claimed, TOTAL);
    }

    /// @dev `claimable <= vested <= total`, the property the whole contract exists to guarantee.
    function invariant_VestedWithinBounds() public view {
        uint256 vested = wallet.vestedAmount();
        assertLe(vested, TOTAL);
        assertLe(wallet.claimableAmount(), vested);
    }
}
