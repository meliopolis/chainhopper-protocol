// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AcrossSettler} from "./base/AcrossSettler.sol";
import {Settler} from "./base/Settler.sol";
import {V4Settler} from "./base/V4Settler.sol";

contract AcrossV4Settler is AcrossSettler, V4Settler {
    constructor(
        address _initialOwner,
        address _positionManager,
        address _universalRouter,
        address _permit2,
        address _spokePool,
        address _weth
    ) Settler(_initialOwner) AcrossSettler(_spokePool) V4Settler(_positionManager, _universalRouter, _permit2, _weth) {}
}
