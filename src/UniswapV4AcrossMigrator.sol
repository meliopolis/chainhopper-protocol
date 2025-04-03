// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AcrossMigrator} from "./base/AcrossMigrator.sol";
import {UniswapV4Migrator} from "./base/UniswapV4Migrator.sol";

contract UniswapV4AcrossMigrator is UniswapV4Migrator, AcrossMigrator {
    constructor(address positionManager, address universalRouter, address permit2, address spokePool, address weth)
        UniswapV4Migrator(positionManager, universalRouter, permit2)
        AcrossMigrator(spokePool, weth)
    {}
}
