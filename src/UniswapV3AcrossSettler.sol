// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AcrossSettler} from "./base/AcrossSettler.sol";
import {Settler} from "./base/Settler.sol";
import {UniswapV3Settler} from "./base/UniswapV3Settler.sol";

contract UniswapV3AcrossSettler is UniswapV3Settler, AcrossSettler {
    constructor(
        address positionManager,
        address universalRouter,
        address permit2,
        address spokePool,
        address initialOwner
    ) UniswapV3Settler(positionManager, universalRouter, permit2) AcrossSettler(spokePool) Settler(initialOwner) {}
}
