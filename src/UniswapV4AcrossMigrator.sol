// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AcrossMigrator} from "./base/AcrossMigrator.sol";
import {UniswapV4Migrator} from "./base/UniswapV4Migrator.sol";
import {Migrator} from "./base/Migrator.sol";

contract UniswapV4AcrossMigrator is UniswapV4Migrator, AcrossMigrator {
    constructor(
        address initialOwner,
        address positionManager,
        address universalRouter,
        address permit2,
        address spokePool,
        address weth
    )
        Migrator(initialOwner)
        UniswapV4Migrator(positionManager, universalRouter, permit2)
        AcrossMigrator(spokePool, weth)
    {}
}
