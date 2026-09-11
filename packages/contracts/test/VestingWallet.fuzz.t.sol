// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {VestingWallet} from "../src/VestingWallet.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @notice Fuzz the vesting math against its own closed form, and assert the core bounds
///         `claimable <= vested <= total` hold for every input.
contract VestingWalletFuzzTest is Test {
    VestingWallet internal implementation;
    VestingWallet internal wallet;
    MockERC20 internal token;

    address internal creator = makeAddr("creator");
    address internal beneficiary = makeAddr("beneficiary");

    uint64 internal constant START = 1_700_000_000;
    uint64 internal constant CLIFF = 180 days;
    uint64 internal constant DURATION = 730 days;
    uint256 internal constant TOTAL = 1_000_000 ether;

    function setUp() public {
        implementation = new VestingWallet();
        token = new MockERC20("Mock", "MCK", 18);

        wallet = VestingWallet(Clones.clone(address(implementation)));
        token.mint(address(this), TOTAL);
        token.approve(address(wallet), TOTAL);
        wallet.initialize(address(token), beneficiary, creator, START, CLIFF, DURATION, TOTAL, true);
        token.transfer(address(wallet), TOTAL);
    }

    function testFuzz_Vested_NeverExceedsTotal(uint256 timestamp) public view {
        timestamp = bound(timestamp, 0, uint256(START) + 100 * 365 days);
        assertLe(wallet.vestedAmount(uint64(timestamp)), TOTAL);
    }

    function testFuzz_Vested_IsMonotonic(uint256 t1, uint256 t2) public view {
        uint256 maxTime = uint256(START) + 100 * 365 days;
        t1 = bound(t1, 0, maxTime);
        t2 = bound(t2, 0, maxTime);
        if (t1 > t2) (t1, t2) = (t2, t1);

        assertLe(wallet.vestedAmount(uint64(t1)), wallet.vestedAmount(uint64(t2)));
    }

    function testFuzz_Vested_MatchesClosedForm(uint256 elapsed) public view {
        elapsed = bound(elapsed, 0, DURATION);

        uint256 expected = elapsed < CLIFF ? 0 : Math.mulDiv(TOTAL, elapsed, DURATION);
        assertEq(wallet.vestedAmount(START + uint64(elapsed)), expected);
    }

    function testFuzz_Claimable_NeverExceedsVested(uint256 elapsed) public {
        vm.warp(START + uint64(bound(elapsed, 0, DURATION * 2)));

        uint256 vested = wallet.vestedAmount();
        uint256 claimable = wallet.claimableAmount();

        assertLe(claimable, vested);
        assertLe(vested, TOTAL);
    }

    function testFuzz_Claim_TransfersExactlyClaimable(uint256 elapsed) public {
        vm.warp(START + uint64(bound(elapsed, 0, DURATION)));

        uint256 claimable = wallet.claimableAmount();
        if (claimable == 0) return;

        vm.prank(beneficiary);
        wallet.claim();

        assertEq(token.balanceOf(beneficiary), claimable);
        assertEq(wallet.schedule().claimed, claimable);
        assertLe(wallet.schedule().claimed, TOTAL);
        assertEq(wallet.claimableAmount(), 0);
    }

    function testFuzz_Revoke_ReturnsExactlyUnvested(uint256 elapsed) public {
        vm.warp(START + uint64(bound(elapsed, 0, DURATION)));

        uint256 vested = wallet.vestedAmount();
        vm.prank(creator);
        wallet.revoke();

        assertEq(token.balanceOf(creator), TOTAL - vested);
        assertEq(token.balanceOf(address(wallet)), vested);
        assertEq(wallet.vestedAmount(), vested);
    }
}
