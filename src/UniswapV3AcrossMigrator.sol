// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AcrossMigrator} from "./base/AcrossMigrator.sol";
import {UniswapV3Migrator} from "./base/UniswapV3Migrator.sol";

contract UniswapV3AcrossMigrator is UniswapV3Migrator, AcrossMigrator {
    constructor(address positionManager, address universalRouter, address permit2, address spokePool, address weth)
        UniswapV3Migrator(positionManager, universalRouter, permit2)
        AcrossMigrator(spokePool, weth)
    {}
}
