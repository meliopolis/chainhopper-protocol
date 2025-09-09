// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DirectSettler} from "./base/DirectSettler.sol";
import {Settler} from "./base/Settler.sol";
import {UniswapV4Settler} from "./base/UniswapV4Settler.sol";

/// @title UniswapV4DirectSettler
/// @notice A settler that settles migrations on Uniswap V4
contract UniswapV4DirectSettler is UniswapV4Settler, DirectSettler {
    /// @notice Constructor
    /// @param initialOwner The initial owner of the settler
    /// @param positionManager The position manager
    /// @param universalRouter The universal router
    /// @param permit2 The permit2 contract
    /// @param weth The WETH address
    constructor(address initialOwner, address positionManager, address universalRouter, address permit2, address weth)
        UniswapV4Settler(positionManager, universalRouter, permit2, weth)
        DirectSettler()
        Settler(initialOwner)
    {}
}
