// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title VaultKitRegistry
/// @notice Append-only list of factory versions (`v1`, `v2`, …) so the SDK and indexer can
///         enumerate factories without hardcoding one address per chain. Registering is a one-way
///         door: entries are never removed or edited.
contract VaultKitRegistry is Ownable {
    struct FactoryVersion {
        uint256 version;
        address factory;
        string label;
        uint64 addedAt;
    }

    FactoryVersion[] private _factories;

    /// @notice True for every factory address registered.
    mapping(address factory => bool) public isFactory;

    error ZeroAddress();
    error DuplicateFactory();

    event FactoryRegistered(uint256 indexed version, address indexed factory, string label);

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Register a new factory version. Owner-only.
    /// @param factory Factory contract address.
    /// @param label   Human label, e.g. `"v1"`.
    /// @return version 1-indexed version number.
    function registerFactory(address factory, string calldata label)
        external
        onlyOwner
        returns (uint256 version)
    {
        if (factory == address(0)) revert ZeroAddress();
        if (isFactory[factory]) revert DuplicateFactory();

        version = _factories.length + 1;
        _factories.push(
            FactoryVersion({
                version: version,
                factory: factory,
                label: label,
                // uint64 holds unix seconds until the year ~584 billion; the cast is safe.
                // forge-lint: disable-next-line(unsafe-typecast)
                addedAt: uint64(block.timestamp)
            })
        );
        isFactory[factory] = true;

        emit FactoryRegistered(version, factory, label);
    }

    /// @notice Number of registered factories.
    function factoryCount() external view returns (uint256) {
        return _factories.length;
    }

    /// @notice Factory version at `index`.
    function factoryAt(uint256 index) external view returns (FactoryVersion memory) {
        return _factories[index];
    }

    /// @notice Most recently registered factory, or the zero address if none.
    function latestFactory() external view returns (address) {
        uint256 length = _factories.length;
        return length == 0 ? address(0) : _factories[length - 1].factory;
    }

    /// @notice Every registered factory, oldest first.
    function allFactories() external view returns (FactoryVersion[] memory) {
        return _factories;
    }
}
