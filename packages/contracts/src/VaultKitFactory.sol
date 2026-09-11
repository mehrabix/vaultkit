// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IVestingWallet} from "./interfaces/IVestingWallet.sol";

/// @title VaultKitFactory
/// @notice Deploys one `VestingWallet` clone per schedule and funds it in the same transaction.
///         A schedule with no tokens cannot exist: `createVestingSchedule` pulls `amount` from the
///         caller and reverts unless the clone's balance increased by exactly `amount`.
///
/// @dev `Pausable` stops *new* schedules only. Existing schedules are unstoppable by design.
contract VaultKitFactory is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice The `VestingWallet` implementation that all clones point at.
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    address public immutable implementation;

    /// @notice Total number of schedules created by this factory.
    uint256 public scheduleCount;

    /// @notice True for every wallet this factory deployed.
    mapping(address wallet => bool) public isSchedule;

    error ZeroAddress();
    error ZeroAmount();
    error InvalidDuration();
    error CliffExceedsDuration();
    error InvalidFunding();

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

    constructor(address implementation_, address initialOwner) Ownable(initialOwner) {
        if (implementation_ == address(0)) revert ZeroAddress();
        implementation = implementation_;
    }

    /// @notice Create and fund a new vesting schedule.
    /// @param token          ERC-20 being vested.
    /// @param beneficiary    Address that will receive vested tokens.
    /// @param start          Unix timestamp at which vesting begins (may be in the past).
    /// @param cliff          Seconds after `start` before anything vests. Pass 0 for no cliff.
    /// @param duration       Seconds after `start` until fully vested. Must be > 0.
    /// @param amount         Tokens to fund the schedule with. Must be > 0.
    /// @param revocable      Whether the creator may later reclaim the unvested remainder.
    /// @return wallet        Address of the deployed clone.
    function createVestingSchedule(
        address token,
        address beneficiary,
        uint64 start,
        uint64 cliff,
        uint64 duration,
        uint256 amount,
        bool revocable
    ) external nonReentrant whenNotPaused returns (address wallet) {
        if (token == address(0) || beneficiary == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (duration == 0) revert InvalidDuration();
        if (cliff > duration) revert CliffExceedsDuration();

        wallet = Clones.clone(implementation);

        IVestingWallet(wallet)
            .initialize(token, beneficiary, msg.sender, start, cliff, duration, amount, revocable);

        // Pull from the creator and forward to the clone. Measure the wallet's balance delta so
        // fee-on-transfer / rebasing tokens that deliver less than `amount` are rejected here
        // rather than silently under-funding the schedule.
        uint256 balanceBefore = IERC20(token).balanceOf(wallet);
        IERC20(token).safeTransferFrom(msg.sender, wallet, amount);
        // Strict equality is the point: a fee-on-transfer or rebasing token that delivers anything
        // other than exactly `amount` must revert here rather than silently under-fund the schedule.
        // forge-lint: disable-next-line(incorrect-strict-equality)
        if (IERC20(token).balanceOf(wallet) - balanceBefore != amount) revert InvalidFunding();

        scheduleCount += 1;
        isSchedule[wallet] = true;

        // Emitted last so it only fires once funding is verified. `nonReentrant` prevents a
        // malicious token from reordering this through the transfer above.
        // forge-lint: disable-next-item(reentrancy-events)
        emit ScheduleCreated(
            wallet, token, beneficiary, msg.sender, amount, start, cliff, duration, revocable
        );
    }

    /// @notice Stop new schedule creation. Existing schedules are unaffected.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Resume schedule creation.
    function unpause() external onlyOwner {
        _unpause();
    }
}
