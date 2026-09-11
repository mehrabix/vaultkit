// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IVestingWallet
/// @notice Interface for a single VaultKit vesting schedule. One schedule = one clone = one token
///         balance. Deployed by `VaultKitFactory`, never upgraded.
interface IVestingWallet {
    struct Schedule {
        address token;
        address beneficiary;
        address creator;
        uint64 start;
        uint64 cliff;
        uint64 duration;
        uint256 totalAmount;
        uint256 claimed;
        bool revocable;
        bool revoked;
        uint64 revokedAt;
    }

    /// @notice One-time initialization, called by the factory immediately after cloning.
    function initialize(
        address token,
        address beneficiary,
        address creator,
        uint64 start,
        uint64 cliff,
        uint64 duration,
        uint256 totalAmount,
        bool revocable
    ) external;

    /// @notice Full schedule record.
    function schedule() external view returns (Schedule memory);

    /// @notice Amount vested at an arbitrary timestamp (capped at the revoke time if revoked).
    function vestedAmount(uint64 timestamp) external view returns (uint256);

    /// @notice Amount vested at the current timestamp.
    function vestedAmount() external view returns (uint256);

    /// @notice `vested - claimed` at the current timestamp. Zero if nothing is claimable.
    function claimableAmount() external view returns (uint256);

    /// @notice Beneficiary-only. Transfers all currently claimable tokens.
    function claim() external;

    /// @notice Creator-only, revocable schedules only. Returns the unvested remainder to the creator.
    function revoke() external;

    /// @notice Creator-only, before revocation. Reassigns the beneficiary position.
    function reassignBeneficiary(address newBeneficiary) external;

    event Claimed(address indexed beneficiary, uint256 amount);
    event Revoked(address indexed creator, uint256 unvestedReturned);
    event BeneficiaryReassigned(
        address indexed previousBeneficiary, address indexed newBeneficiary
    );
}
