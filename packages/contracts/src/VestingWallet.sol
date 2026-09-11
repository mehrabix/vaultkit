// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IVestingWallet} from "./interfaces/IVestingWallet.sol";

/// @title VestingWallet
/// @notice One vesting schedule, one address, one token balance. Deployed as an EIP-1167 minimal
///         proxy clone by `VaultKitFactory`; the implementation is init-disabled in its constructor
///         so it can never be hijacked.
///
/// @dev Vesting math is linear with a cliff. The cliff gates *when* vesting begins, but once it is
///      passed the beneficiary receives credit for all time elapsed since `start`:
///
///          t <  start + cliff   -> 0
///          t >= start + duration -> total
///          otherwise            -> total * (t - start) / duration   (floor)
contract VestingWallet is IVestingWallet, Initializable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IVestingWallet.Schedule private _schedule;

    error ZeroAddress();
    error ZeroAmount();
    error InvalidDuration();
    error CliffExceedsDuration();
    error NotBeneficiary();
    error NotCreator();
    error NotRevocable();
    error AlreadyRevoked();
    error NothingToClaim();

    /// @dev The implementation contract (the one deployed, not cloned) must not be usable.
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IVestingWallet
    function initialize(
        address token_,
        address beneficiary_,
        address creator_,
        uint64 start_,
        uint64 cliff_,
        uint64 duration_,
        uint256 totalAmount_,
        bool revocable_
    ) external initializer {
        if (token_ == address(0) || beneficiary_ == address(0) || creator_ == address(0)) {
            revert ZeroAddress();
        }
        if (totalAmount_ == 0) revert ZeroAmount();
        if (duration_ == 0) revert InvalidDuration();
        // A cliff longer than the schedule would make the linear branch unreachable and the
        // accounting ambiguous. Reject it.
        if (cliff_ > duration_) revert CliffExceedsDuration();

        // No `__ReentrancyGuard_init()`: OZ v5.5+ `ReentrancyGuard` is stateless (ERC-7201 slot,
        // never 0 == "entered"), so it is safe in a clone whose constructor never ran.
        _schedule = IVestingWallet.Schedule({
            token: token_,
            beneficiary: beneficiary_,
            creator: creator_,
            start: start_,
            cliff: cliff_,
            duration: duration_,
            totalAmount: totalAmount_,
            claimed: 0,
            revocable: revocable_,
            revoked: false,
            revokedAt: 0
        });
    }

    /// @dev `block.timestamp` cannot exceed `uint64` for ~584 billion years; the cast is safe.
    function _now() private view returns (uint64) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint64(block.timestamp);
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    /// @inheritdoc IVestingWallet
    function schedule() external view returns (IVestingWallet.Schedule memory) {
        return _schedule;
    }

    /// @inheritdoc IVestingWallet
    /// @dev Once revoked, vesting freezes at `revokedAt`: already-vested-but-unclaimed tokens stay
    ///      claimable, and nothing vests after the revoke.
    function vestedAmount(uint64 timestamp) public view returns (uint256) {
        IVestingWallet.Schedule storage s = _schedule;

        if (s.revoked && timestamp > s.revokedAt) {
            timestamp = s.revokedAt;
        }

        uint256 start = s.start;
        if (timestamp < start + s.cliff) {
            return 0;
        }

        uint256 end = start + s.duration;
        if (timestamp >= end) {
            return s.totalAmount;
        }

        // Full-precision `total * elapsed / duration`, immune to intermediate overflow.
        return Math.mulDiv(s.totalAmount, timestamp - start, s.duration);
    }

    /// @inheritdoc IVestingWallet
    function vestedAmount() external view returns (uint256) {
        return vestedAmount(_now());
    }

    /// @inheritdoc IVestingWallet
    function claimableAmount() public view returns (uint256) {
        return vestedAmount(_now()) - _schedule.claimed;
    }

    /// @notice The token this schedule vests.
    function token() external view returns (address) {
        return _schedule.token;
    }

    /// @notice The current beneficiary of this schedule.
    function beneficiary() external view returns (address) {
        return _schedule.beneficiary;
    }

    /// @notice The address that funded the schedule and holds revoke/reassign rights.
    function creator() external view returns (address) {
        return _schedule.creator;
    }

    // ---------------------------------------------------------------------
    // Actions
    // ---------------------------------------------------------------------

    /// @inheritdoc IVestingWallet
    function claim() external nonReentrant {
        IVestingWallet.Schedule storage s = _schedule;

        if (msg.sender != s.beneficiary) revert NotBeneficiary();

        uint256 amount = claimableAmount();
        if (amount == 0) revert NothingToClaim();

        // State before transfer — the reentrancy guard is a second line of defence.
        s.claimed += amount;

        IERC20(s.token).safeTransfer(s.beneficiary, amount);

        emit Claimed(s.beneficiary, amount);
    }

    /// @inheritdoc IVestingWallet
    function revoke() external nonReentrant {
        IVestingWallet.Schedule storage s = _schedule;

        if (msg.sender != s.creator) revert NotCreator();
        if (!s.revocable) revert NotRevocable();
        if (s.revoked) revert AlreadyRevoked();

        s.revoked = true;
        s.revokedAt = _now();

        // Freeze vesting, then return only the unvested remainder. Vested-but-unclaimed tokens stay
        // in the wallet and remain claimable by the beneficiary forever.
        uint256 unvested = s.totalAmount - vestedAmount(_now());
        if (unvested > 0) {
            IERC20(s.token).safeTransfer(s.creator, unvested);
        }

        emit Revoked(s.creator, unvested);
    }

    /// @inheritdoc IVestingWallet
    function reassignBeneficiary(address newBeneficiary) external {
        IVestingWallet.Schedule storage s = _schedule;

        if (msg.sender != s.creator) revert NotCreator();
        if (s.revoked) revert AlreadyRevoked();
        if (newBeneficiary == address(0)) revert ZeroAddress();

        emit BeneficiaryReassigned(s.beneficiary, newBeneficiary);

        s.beneficiary = newBeneficiary;
    }
}
