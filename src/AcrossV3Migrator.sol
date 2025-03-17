// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AcrossMigrator} from "./base/AcrossMigrator.sol";
import {Migrator} from "./base/Migrator.sol";
import {V3Migrator} from "./base/V3Migrator.sol";

contract AcrossV3Migrator is AcrossMigrator, V3Migrator {
    constructor(address _positionManager, address _spokePool, address _universalRouter)
        Migrator(_positionManager)
        AcrossMigrator(_spokePool)
        V3Migrator(_universalRouter)
    {}
}
