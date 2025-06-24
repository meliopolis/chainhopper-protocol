// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DirectTransferMigrator} from "./base/DirectTransferMigrator.sol";
import {UniswapV3Migrator} from "./base/UniswapV3Migrator.sol";
import {Migrator} from "./base/Migrator.sol";

/// @title UniswapV3AcrossMigrator
/// @notice A migrator that migrates positions between Uniswap V3 and Across
contract UniswapV3DTMigrator is UniswapV3Migrator, DirectTransferMigrator {
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
        address weth
    )
        Migrator(initialOwner)
        UniswapV3Migrator(positionManager, universalRouter, permit2)
        DirectTransferMigrator()
    {}
}
