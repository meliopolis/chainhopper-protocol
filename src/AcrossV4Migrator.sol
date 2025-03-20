// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AcrossMigrator} from "./base/AcrossMigrator.sol";
import {V4Migrator} from "./base/V4Migrator.sol";

contract AcrossV4Migrator is AcrossMigrator, V4Migrator {
    constructor(address _positionManager, address _spokePool, address _universalRouter, address _permit2)
        AcrossMigrator(_spokePool)
        V4Migrator(_positionManager, _universalRouter, _permit2)
    {}
}
