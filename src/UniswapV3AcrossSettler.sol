// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AcrossSettler} from "./base/AcrossSettler.sol";
import {Settler} from "./base/Settler.sol";
import {UniswapV3Settler} from "./base/UniswapV3Settler.sol";

/// @title UniswapV3AcrossSettler
/// @notice A settler that settles migrations on Uniswap V3 and Across
contract UniswapV3AcrossSettler is UniswapV3Settler, AcrossSettler {
    /// @notice Constructor
    /// @param initialOwner The initial owner of the settler
    /// @param positionManager The position manager
    /// @param universalRouter The universal router
    /// @param permit2 The permit2 contract
    constructor(
        address initialOwner,
        address positionManager,
        address universalRouter,
        address permit2,
        address spokePool
    ) UniswapV3Settler(positionManager, universalRouter, permit2) AcrossSettler(spokePool) Settler(initialOwner) {}
}
