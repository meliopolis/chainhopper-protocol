// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AcrossMigrator} from "./base/AcrossMigrator.sol";
import {Migrator} from "./base/Migrator.sol";
import {V4Migrator} from "./base/V4Migrator.sol";

contract AcrossV4Migrator is AcrossMigrator, V4Migrator {
    constructor(
        address _initialOwner,
        address _positionManager,
        address _universalRouter,
        address _permit2,
        address _spokePool
    ) Migrator(_initialOwner) AcrossMigrator(_spokePool) V4Migrator(_positionManager, _universalRouter, _permit2) {}
}
