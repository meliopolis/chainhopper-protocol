// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AcrossMigrator} from "./base/AcrossMigrator.sol";
import {V3Migrator} from "./base/V3Migrator.sol";

contract AcrossV3Migrator is AcrossMigrator, V3Migrator {
    constructor(address _positionManager, address _universalRouter, address _permit2, address _spokePool)
        AcrossMigrator(_spokePool)
        V3Migrator(_positionManager, _universalRouter, _permit2)
    {}
}
