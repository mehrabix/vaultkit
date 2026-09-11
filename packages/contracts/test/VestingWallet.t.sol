// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {VestingWallet} from "../src/VestingWallet.sol";
import {IVestingWallet} from "../src/interfaces/IVestingWallet.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ReentrantToken} from "./mocks/ReentrantToken.sol";

contract VestingWalletTest is Test {
    VestingWallet internal implementation;
    VestingWallet internal wallet;
    MockERC20 internal token;

    address internal creator = makeAddr("creator");
    address internal beneficiary = makeAddr("beneficiary");
    address internal stranger = makeAddr("stranger");

    uint64 internal constant START = 1_700_000_000;
    uint64 internal constant CLIFF = 180 days;
    uint64 internal constant DURATION = 730 days;
    uint256 internal constant TOTAL = 1_000_000 ether;

    event Claimed(address indexed beneficiary, uint256 amount);
    event Revoked(address indexed creator, uint256 unvestedReturned);
    event BeneficiaryReassigned(
        address indexed previousBeneficiary, address indexed newBeneficiary
    );

    function setUp() public {
        implementation = new VestingWallet();
        token = new MockERC20("Mock", "MCK", 18);

        // A funded, revocable schedule with a cliff, funded by `creator`.
        wallet = _newSchedule(CLIFF, true);
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    function _newSchedule(uint64 cliff, bool revocable) internal returns (VestingWallet w) {
        w = VestingWallet(Clones.clone(address(implementation)));
        token.mint(address(this), TOTAL);
        token.approve(address(w), TOTAL);
        w.initialize(address(token), beneficiary, creator, START, cliff, DURATION, TOTAL, revocable);
        token.transfer(address(w), TOTAL);
    }

    function _freshClone() internal returns (VestingWallet) {
        return VestingWallet(Clones.clone(address(implementation)));
    }

    // ---------------------------------------------------------------------
    // Initialization
    // ---------------------------------------------------------------------

    function test_Initialize_StoresSchedule() public view {
        IVestingWallet.Schedule memory s = wallet.schedule();
        assertEq(s.token, address(token));
        assertEq(s.beneficiary, beneficiary);
        assertEq(s.creator, creator);
        assertEq(s.start, START);
        assertEq(s.cliff, CLIFF);
        assertEq(s.duration, DURATION);
        assertEq(s.totalAmount, TOTAL);
        assertEq(s.claimed, 0);
        assertTrue(s.revocable);
        assertFalse(s.revoked);
        assertEq(s.revokedAt, 0);
    }

    function test_Initialize_CannotRunTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        wallet.initialize(address(token), beneficiary, creator, START, CLIFF, DURATION, TOTAL, true);
    }

    function test_Implementation_IsInitDisabled() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(
            address(token), beneficiary, creator, START, CLIFF, DURATION, TOTAL, true
        );
    }

    function test_Initialize_RevertsOnZeroToken() public {
        VestingWallet w = _freshClone();
        vm.expectRevert(VestingWallet.ZeroAddress.selector);
        w.initialize(address(0), beneficiary, creator, START, CLIFF, DURATION, TOTAL, true);
    }

    function test_Initialize_RevertsOnZeroBeneficiary() public {
        VestingWallet w = _freshClone();
        vm.expectRevert(VestingWallet.ZeroAddress.selector);
        w.initialize(address(token), address(0), creator, START, CLIFF, DURATION, TOTAL, true);
    }

    function test_Initialize_RevertsOnZeroCreator() public {
        VestingWallet w = _freshClone();
        vm.expectRevert(VestingWallet.ZeroAddress.selector);
        w.initialize(address(token), beneficiary, address(0), START, CLIFF, DURATION, TOTAL, true);
    }

    function test_Initialize_RevertsOnZeroAmount() public {
        VestingWallet w = _freshClone();
        vm.expectRevert(VestingWallet.ZeroAmount.selector);
        w.initialize(address(token), beneficiary, creator, START, CLIFF, DURATION, 0, true);
    }

    function test_Initialize_RevertsOnZeroDuration() public {
        VestingWallet w = _freshClone();
        vm.expectRevert(VestingWallet.InvalidDuration.selector);
        w.initialize(address(token), beneficiary, creator, START, 0, 0, TOTAL, true);
    }

    function test_Initialize_RevertsWhenCliffExceedsDuration() public {
        VestingWallet w = _freshClone();
        vm.expectRevert(VestingWallet.CliffExceedsDuration.selector);
        w.initialize(
            address(token), beneficiary, creator, START, DURATION + 1, DURATION, TOTAL, true
        );
    }

    // ---------------------------------------------------------------------
    // Vesting math
    // ---------------------------------------------------------------------

    function test_Vested_ZeroBeforeStart() public view {
        assertEq(wallet.vestedAmount(START - 1), 0);
    }

    function test_Vested_ZeroJustBeforeCliff() public view {
        assertEq(wallet.vestedAmount(START + CLIFF - 1), 0);
    }

    function test_Vested_AtCliffCreditsElapsedTime() public view {
        // The cliff gates the *start* of vesting; past it, credit accrues from `start`.
        assertEq(wallet.vestedAmount(START + CLIFF), Math.mulDiv(TOTAL, CLIFF, DURATION));
    }

    function test_Vested_LinearAtMidpoint() public view {
        assertEq(wallet.vestedAmount(START + DURATION / 2), TOTAL / 2);
    }

    function test_Vested_FullAtDuration() public view {
        assertEq(wallet.vestedAmount(START + DURATION), TOTAL);
    }

    function test_Vested_FullAfterDuration() public view {
        assertEq(wallet.vestedAmount(START + DURATION + 10_000 days), TOTAL);
    }

    function test_Vested_ZeroCliffVestsFromStart() public {
        VestingWallet w = _newSchedule(0, true);
        assertEq(w.vestedAmount(START), 0);
        assertEq(w.vestedAmount(START + 1), Math.mulDiv(TOTAL, 1, DURATION));
        assertEq(w.vestedAmount(START + DURATION), TOTAL);
    }

    function test_Claimable_ZeroBeforeAnythingVests() public {
        vm.warp(START + CLIFF - 1);
        assertEq(wallet.claimableAmount(), 0);
    }

    // ---------------------------------------------------------------------
    // Claim
    // ---------------------------------------------------------------------

    function test_Claim_RevertsForNonBeneficiary() public {
        vm.warp(START + DURATION);
        vm.prank(stranger);
        vm.expectRevert(VestingWallet.NotBeneficiary.selector);
        wallet.claim();
    }

    function test_Claim_RevertsWhenNothingVested() public {
        vm.warp(START + CLIFF - 1);
        vm.prank(beneficiary);
        vm.expectRevert(VestingWallet.NothingToClaim.selector);
        wallet.claim();
    }

    function test_Claim_TransfersFullAmountAfterDuration() public {
        vm.warp(START + DURATION);

        vm.expectEmit(true, false, false, true, address(wallet));
        emit Claimed(beneficiary, TOTAL);

        vm.prank(beneficiary);
        wallet.claim();

        assertEq(token.balanceOf(beneficiary), TOTAL);
        assertEq(wallet.schedule().claimed, TOTAL);
        assertEq(wallet.claimableAmount(), 0);
        assertEq(token.balanceOf(address(wallet)), 0);
    }

    function test_Claim_MultipleClaimsAccumulate() public {
        vm.warp(START + CLIFF);
        uint256 vestedAtCliff = wallet.vestedAmount();

        vm.prank(beneficiary);
        wallet.claim();
        assertEq(token.balanceOf(beneficiary), vestedAtCliff);

        vm.warp(START + DURATION / 2);
        vm.prank(beneficiary);
        wallet.claim();

        assertEq(token.balanceOf(beneficiary), TOTAL / 2);
        assertEq(wallet.schedule().claimed, TOTAL / 2);
    }

    function test_Claim_NothingLeftReverts() public {
        vm.warp(START + DURATION);
        vm.prank(beneficiary);
        wallet.claim();

        vm.prank(beneficiary);
        vm.expectRevert(VestingWallet.NothingToClaim.selector);
        wallet.claim();
    }

    function test_Claim_ReentrantCallIsRejected() public {
        ReentrantToken reToken = new ReentrantToken();
        VestingWallet w = VestingWallet(Clones.clone(address(implementation)));

        reToken.mint(address(this), TOTAL);
        reToken.approve(address(w), TOTAL);
        // Beneficiary is the token itself, so a re-entrant call would pass authorization and only
        // the guard / claim accounting can stop it.
        w.initialize(address(reToken), address(reToken), creator, START, 0, DURATION, TOTAL, true);
        reToken.transfer(address(w), TOTAL);

        reToken.arm(address(w));
        vm.warp(START + DURATION);

        vm.prank(address(reToken));
        w.claim();

        assertTrue(reToken.reentryBlocked());
        assertEq(reToken.balanceOf(address(reToken)), TOTAL);
        assertEq(w.schedule().claimed, TOTAL);
    }

    // ---------------------------------------------------------------------
    // Revoke
    // ---------------------------------------------------------------------

    function test_Revoke_RevertsForNonCreator() public {
        vm.prank(stranger);
        vm.expectRevert(VestingWallet.NotCreator.selector);
        wallet.revoke();
    }

    function test_Revoke_RevertsWhenNotRevocable() public {
        VestingWallet w = _newSchedule(CLIFF, false);
        vm.prank(creator);
        vm.expectRevert(VestingWallet.NotRevocable.selector);
        w.revoke();
    }

    function test_Revoke_RevertsOnSecondCall() public {
        vm.warp(START + DURATION / 2);
        vm.startPrank(creator);
        wallet.revoke();
        vm.expectRevert(VestingWallet.AlreadyRevoked.selector);
        wallet.revoke();
        vm.stopPrank();
    }

    function test_Revoke_ReturnsOnlyUnvested() public {
        vm.warp(START + DURATION / 2);

        vm.expectEmit(true, false, false, true, address(wallet));
        emit Revoked(creator, TOTAL - TOTAL / 2);

        vm.prank(creator);
        wallet.revoke();

        assertEq(token.balanceOf(creator), TOTAL - TOTAL / 2);
        assertEq(token.balanceOf(address(wallet)), TOTAL / 2);
        assertTrue(wallet.schedule().revoked);
        assertEq(wallet.schedule().revokedAt, START + DURATION / 2);
    }

    function test_Revoke_VestedStaysClaimableForever() public {
        vm.warp(START + DURATION / 2);
        vm.prank(creator);
        wallet.revoke();

        // Long after the revoke, the vested half is still there for the beneficiary.
        vm.warp(START + DURATION * 5);
        vm.prank(beneficiary);
        wallet.claim();

        assertEq(token.balanceOf(beneficiary), TOTAL / 2);
        assertEq(token.balanceOf(address(wallet)), 0);
    }

    function test_Revoke_FreezesVesting() public {
        vm.warp(START + DURATION / 2);
        uint256 vestedAtRevoke = wallet.vestedAmount();

        vm.prank(creator);
        wallet.revoke();

        vm.warp(START + DURATION * 10);
        assertEq(wallet.vestedAmount(), vestedAtRevoke);
        assertEq(wallet.claimableAmount(), vestedAtRevoke);
    }

    function test_Revoke_BeforeCliffReturnsEverything() public {
        vm.warp(START + CLIFF - 1);
        vm.prank(creator);
        wallet.revoke();

        assertEq(token.balanceOf(creator), TOTAL);
        assertEq(token.balanceOf(address(wallet)), 0);
    }

    // ---------------------------------------------------------------------
    // Reassign
    // ---------------------------------------------------------------------

    function test_Reassign_RevertsForNonCreator() public {
        vm.prank(stranger);
        vm.expectRevert(VestingWallet.NotCreator.selector);
        wallet.reassignBeneficiary(stranger);
    }

    function test_Reassign_RevertsOnZeroAddress() public {
        vm.prank(creator);
        vm.expectRevert(VestingWallet.ZeroAddress.selector);
        wallet.reassignBeneficiary(address(0));
    }

    function test_Reassign_RevertsAfterRevoke() public {
        vm.prank(creator);
        wallet.revoke();

        vm.prank(creator);
        vm.expectRevert(VestingWallet.AlreadyRevoked.selector);
        wallet.reassignBeneficiary(stranger);
    }

    function test_Reassign_MovesClaimRights() public {
        address newBeneficiary = makeAddr("newBeneficiary");
        vm.warp(START + DURATION);

        vm.expectEmit(true, true, false, false, address(wallet));
        emit BeneficiaryReassigned(beneficiary, newBeneficiary);

        vm.prank(creator);
        wallet.reassignBeneficiary(newBeneficiary);
        assertEq(wallet.beneficiary(), newBeneficiary);

        vm.prank(beneficiary);
        vm.expectRevert(VestingWallet.NotBeneficiary.selector);
        wallet.claim();

        vm.prank(newBeneficiary);
        wallet.claim();
        assertEq(token.balanceOf(newBeneficiary), TOTAL);
    }
}
