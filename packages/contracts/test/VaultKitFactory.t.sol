// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {VestingWallet} from "../src/VestingWallet.sol";
import {VaultKitFactory} from "../src/VaultKitFactory.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {FeeOnTransferToken} from "./mocks/FeeOnTransferToken.sol";

contract VaultKitFactoryTest is Test {
    VestingWallet internal implementation;
    VaultKitFactory internal factory;
    MockERC20 internal token;

    address internal owner = makeAddr("owner");
    address internal creator = makeAddr("creator");
    address internal beneficiary = makeAddr("beneficiary");
    address internal other = makeAddr("other");
    address internal stranger = makeAddr("stranger");

    uint64 internal constant START = 1_700_000_000;
    uint64 internal constant CLIFF = 180 days;
    uint64 internal constant DURATION = 730 days;
    uint256 internal constant AMOUNT = 500_000 ether;

    event ScheduleCreated(
        address indexed wallet,
        address indexed token,
        address indexed beneficiary,
        address creator,
        uint256 amount,
        uint64 start,
        uint64 cliff,
        uint64 duration,
        bool revocable
    );

    function setUp() public {
        implementation = new VestingWallet();
        factory = new VaultKitFactory(address(implementation), owner);
        token = new MockERC20("Mock", "MCK", 18);

        token.mint(creator, AMOUNT * 10);
        vm.prank(creator);
        token.approve(address(factory), type(uint256).max);
    }

    function _create(address beneficiary_, uint64 cliff_, bool revocable_)
        internal
        returns (address)
    {
        vm.prank(creator);
        return factory.createVestingSchedule(
            address(token), beneficiary_, START, cliff_, DURATION, AMOUNT, revocable_
        );
    }

    // ---------------------------------------------------------------------
    // Construction
    // ---------------------------------------------------------------------

    function test_Constructor_SetsImplementationAndOwner() public view {
        assertEq(factory.implementation(), address(implementation));
        assertEq(factory.owner(), owner);
    }

    function test_Constructor_RevertsOnZeroImplementation() public {
        vm.expectRevert(VaultKitFactory.ZeroAddress.selector);
        new VaultKitFactory(address(0), owner);
    }

    // ---------------------------------------------------------------------
    // Creation
    // ---------------------------------------------------------------------

    function test_Create_DeploysInitializesAndFunds() public {
        vm.expectEmit(false, false, false, false, address(factory));
        emit ScheduleCreated(address(0), address(0), address(0), address(0), 0, 0, 0, 0, false);

        address wallet = _create(beneficiary, CLIFF, true);

        assertTrue(factory.isSchedule(wallet));
        assertEq(factory.scheduleCount(), 1);
        assertEq(token.balanceOf(wallet), AMOUNT);
        assertEq(token.balanceOf(creator), AMOUNT * 9);

        VestingWallet.Schedule memory s = VestingWallet(wallet).schedule();
        assertEq(s.token, address(token));
        assertEq(s.beneficiary, beneficiary);
        assertEq(s.creator, creator);
        assertEq(s.start, START);
        assertEq(s.cliff, CLIFF);
        assertEq(s.duration, DURATION);
        assertEq(s.totalAmount, AMOUNT);
        assertTrue(s.revocable);
    }

    function test_Create_RevertsOnZeroToken() public {
        vm.prank(creator);
        vm.expectRevert(VaultKitFactory.ZeroAddress.selector);
        factory.createVestingSchedule(address(0), beneficiary, START, CLIFF, DURATION, AMOUNT, true);
    }

    function test_Create_RevertsOnZeroBeneficiary() public {
        vm.prank(creator);
        vm.expectRevert(VaultKitFactory.ZeroAddress.selector);
        factory.createVestingSchedule(
            address(token), address(0), START, CLIFF, DURATION, AMOUNT, true
        );
    }

    function test_Create_RevertsOnZeroAmount() public {
        vm.prank(creator);
        vm.expectRevert(VaultKitFactory.ZeroAmount.selector);
        factory.createVestingSchedule(address(token), beneficiary, START, CLIFF, DURATION, 0, true);
    }

    function test_Create_RevertsOnZeroDuration() public {
        vm.prank(creator);
        vm.expectRevert(VaultKitFactory.InvalidDuration.selector);
        factory.createVestingSchedule(address(token), beneficiary, START, CLIFF, 0, AMOUNT, true);
    }

    function test_Create_RevertsWhenCliffExceedsDuration() public {
        vm.prank(creator);
        vm.expectRevert(VaultKitFactory.CliffExceedsDuration.selector);
        factory.createVestingSchedule(
            address(token), beneficiary, START, DURATION + 1, DURATION, AMOUNT, true
        );
    }

    function test_Create_RevertsOnFeeOnTransferToken() public {
        FeeOnTransferToken feeToken = new FeeOnTransferToken();
        feeToken.mint(creator, AMOUNT);
        vm.prank(creator);
        feeToken.approve(address(factory), AMOUNT);

        vm.prank(creator);
        vm.expectRevert(VaultKitFactory.InvalidFunding.selector);
        factory.createVestingSchedule(
            address(feeToken), beneficiary, START, CLIFF, DURATION, AMOUNT, true
        );

        assertEq(factory.scheduleCount(), 0);
        assertEq(feeToken.balanceOf(creator), AMOUNT);
    }

    // ---------------------------------------------------------------------
    // Isolation
    // ---------------------------------------------------------------------

    function test_SchedulesAreIsolated() public {
        address first = _create(beneficiary, 0, true);
        address second = _create(other, 0, false);

        vm.warp(START + DURATION / 2);
        vm.prank(creator);
        VestingWallet(first).revoke();

        // Revoking the first schedule returns its unvested half and leaves the second untouched.
        assertEq(token.balanceOf(first), AMOUNT / 2);
        assertEq(token.balanceOf(second), AMOUNT);
        assertEq(VestingWallet(second).vestedAmount(), Math.mulDiv(AMOUNT, DURATION / 2, DURATION));
        assertFalse(VestingWallet(second).schedule().revoked);
        assertEq(VestingWallet(second).claimableAmount(), AMOUNT / 2);
    }

    function test_CreatorOfEachScheduleIsTheCaller() public {
        address wallet = _create(beneficiary, CLIFF, true);
        assertEq(VestingWallet(wallet).schedule().creator, creator);
    }

    // ---------------------------------------------------------------------
    // Pause
    // ---------------------------------------------------------------------

    function test_Pause_OnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger)
        );
        factory.pause();
    }

    function test_Pause_BlocksNewSchedules() public {
        vm.prank(owner);
        factory.pause();

        vm.prank(creator);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        factory.createVestingSchedule(
            address(token), beneficiary, START, CLIFF, DURATION, AMOUNT, true
        );
    }

    function test_Unpause_RestoresCreation() public {
        vm.startPrank(owner);
        factory.pause();
        factory.unpause();
        vm.stopPrank();

        address wallet = _create(beneficiary, CLIFF, true);
        assertEq(token.balanceOf(wallet), AMOUNT);
    }

    function test_Pause_DoesNotBlockExistingSchedules() public {
        address wallet = _create(beneficiary, 0, true);

        vm.prank(owner);
        factory.pause();

        vm.warp(START + DURATION);
        vm.prank(beneficiary);
        VestingWallet(wallet).claim();
        assertEq(token.balanceOf(beneficiary), AMOUNT);
    }
}
