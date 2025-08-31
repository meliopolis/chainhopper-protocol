// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AcrossMigrator} from "./base/AcrossMigrator.sol";
import {AerodromeMigrator} from "./base/AerodromeMigrator.sol";
import {Migrator} from "./base/Migrator.sol";

/// @title AerodromeAcrossMigrator
/// @notice A migrator that migrates positions between Aerodrome and Across
contract AerodromeAcrossMigrator is AerodromeMigrator, AcrossMigrator {
    /// @notice Constructor
    /// @param initialOwner The initial owner of the migrator
    /// @param positionManager The position manager
    /// @param universalRouter The universal router
    /// @param permit2 The permit2 contract
    constructor(
        address initialOwner,
        address positionManager,
        address universalRouter,
        address permit2,
        address spokePool,
        address weth
    )
        Migrator(initialOwner)
        AerodromeMigrator(positionManager, universalRouter, permit2)
        AcrossMigrator(spokePool, weth)
    {}
}
