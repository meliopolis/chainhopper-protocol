// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC721Receiver} from "@openzeppelin/token/ERC721/IERC721Receiver.sol";
import {IAcrossV3SpokePool} from "../interfaces/external/IAcrossV3.sol";
import {Migrator} from "./Migrator.sol";
import {AcrossV3Library} from "../libraries/AcrossV3Library.sol";

abstract contract AcrossMigrator is Migrator {
    IAcrossV3SpokePool internal immutable spokePool;

    using AcrossV3Library for IAcrossV3SpokePool;

    constructor(address _positionManager, address _spokePool) Migrator(_positionManager) {
        spokePool = IAcrossV3SpokePool(_spokePool);
    }
}
