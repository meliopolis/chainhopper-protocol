// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DirectSettler} from "./base/DirectSettler.sol";
import {Settler} from "./base/Settler.sol";
import {UniswapV3Settler} from "./base/UniswapV3Settler.sol";

/// @title UniswapV3DirectSettler
/// @notice A settler that settles migrations on Uniswap V3
contract UniswapV3DirectSettler is UniswapV3Settler, DirectSettler {
    /// @notice Constructor
    /// @param initialOwner The initial owner of the settler
    /// @param positionManager The position manager
    /// @param universalRouter The universal router
    /// @param permit2 The permit2 contract
    constructor(address initialOwner, address positionManager, address universalRouter, address permit2)
        UniswapV3Settler(positionManager, universalRouter, permit2)
        DirectSettler()
        Settler(initialOwner)
    {}
}
