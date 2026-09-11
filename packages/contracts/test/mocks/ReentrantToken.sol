// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev A token that attempts to re-enter `claim()` on its `target` while tokens are being
///      transferred out of it. Records whether the re-entrant call was rejected.
contract ReentrantToken is ERC20 {
    address public target;

    /// @notice True once the token observed a re-entrant `claim()` being rejected.
    bool public reentryBlocked;

    bool private _attacking;

    constructor() ERC20("Reentrant", "RE") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Prime the token to attack `target` on its next outbound transfer.
    function arm(address target_) external {
        target = target_;
        reentryBlocked = false;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (target != address(0) && !_attacking && from == target) {
            _attacking = true;
            (bool ok,) = target.call(abi.encodeWithSignature("claim()"));
            reentryBlocked = !ok;
            _attacking = false;
        }
        super._update(from, to, value);
    }
}
