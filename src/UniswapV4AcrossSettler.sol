// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AcrossSettler} from "./base/AcrossSettler.sol";
import {Settler} from "./base/Settler.sol";
import {UniswapV4Settler} from "./base/UniswapV4Settler.sol";

contract UniswapV4AcrossSettler is UniswapV4Settler, AcrossSettler {
    constructor(
        address positionManager,
        address universalRouter,
        address permit2,
        address spokePool,
        address weth,
        address initialOwner
    )
        UniswapV4Settler(positionManager, universalRouter, permit2, weth)
        AcrossSettler(spokePool)
        Settler(initialOwner)
    {}
}
