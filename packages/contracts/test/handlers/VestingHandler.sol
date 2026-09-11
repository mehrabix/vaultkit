// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {VestingWallet} from "../../src/VestingWallet.sol";
import {IVestingWallet} from "../../src/interfaces/IVestingWallet.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @notice Drives a single VestingWallet through arbitrary claim / revoke / reassign / time
///         sequences for invariant testing. `returned` tracks tokens sent back to the creator.
contract VestingHandler is Test {
    VestingWallet public immutable wallet;
    MockERC20 public immutable token;
    address public immutable creator;
    uint256 public immutable total;

    address public currentBeneficiary;
    uint256 public returned;

    constructor(
        VestingWallet wallet_,
        MockERC20 token_,
        address creator_,
        address beneficiary_,
        uint256 total_
    ) {
        wallet = wallet_;
        token = token_;
        creator = creator_;
        total = total_;
        currentBeneficiary = beneficiary_;
    }

    function claim() external {
        if (wallet.claimableAmount() == 0) return;
        vm.prank(currentBeneficiary);
        wallet.claim();
    }

    function revoke() external {
        IVestingWallet.Schedule memory s = wallet.schedule();
        if (s.revoked || !s.revocable) return;

        uint256 before = token.balanceOf(creator);
        vm.prank(creator);
        wallet.revoke();
        returned += token.balanceOf(creator) - before;
    }

    function advanceTime(uint256 seconds_) external {
        vm.warp(block.timestamp + bound(seconds_, 0, 30 days));
    }

    function reassign(uint256 seed) external {
        if (wallet.schedule().revoked) return;

        address to = address(uint160(bound(seed, 1, type(uint160).max)));
        vm.prank(creator);
        wallet.reassignBeneficiary(to);
        currentBeneficiary = to;
    }
}
