// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DirectMigrator} from "./base/DirectMigrator.sol";
import {UniswapV4Migrator} from "./base/UniswapV4Migrator.sol";
import {Migrator} from "./base/Migrator.sol";

/// @title UniswapV4DirectMigrator
/// @notice A migrator that migrates positions between Uniswap V4 and Across
contract UniswapV4DirectMigrator is UniswapV4Migrator, DirectMigrator {
    /// @notice Constructor
    /// @param initialOwner The initial owner of the migrator
    /// @param positionManager The position manager
    /// @param universalRouter The universal router
    /// @param permit2 The permit2 contract
    /// @param weth The WETH address
    constructor(address initialOwner, address positionManager, address universalRouter, address permit2, address weth)
        Migrator(initialOwner)
        UniswapV4Migrator(positionManager, universalRouter, permit2)
        DirectMigrator(weth)
    {}
}
