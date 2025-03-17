// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AcrossMigrator} from "./base/AcrossMigrator.sol";
import {Migrator} from "./base/Migrator.sol";
import {V4Migrator} from "./base/V4Migrator.sol";

contract AcrossV4Migrator is AcrossMigrator, V4Migrator {
    constructor(address _positionManager, address _spokePool, address _universalRouter)
        Migrator(_positionManager)
        AcrossMigrator(_spokePool)
        V4Migrator(_universalRouter)
    {}
}
