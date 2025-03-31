// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AcrossSettler} from "./base/AcrossSettler.sol";
import {Settler} from "./base/Settler.sol";
import {V3Settler} from "./base/V3Settler.sol";

contract AcrossV3Settler is AcrossSettler, V3Settler {
    constructor(
        address _initialOwner,
        address _positionManager,
        address _universalRouter,
        address _permit2,
        address _spokePool
    ) Settler(_initialOwner) AcrossSettler(_spokePool) V3Settler(_positionManager, _universalRouter, _permit2) {}
}
