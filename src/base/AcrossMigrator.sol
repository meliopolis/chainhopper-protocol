// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC721Receiver} from "@openzeppelin/token/ERC721/IERC721Receiver.sol";
import {V3SpokePoolInterface} from "@across/interfaces/V3SpokePoolInterface.sol";
import {Migrator} from "./Migrator.sol";
import {AcrossV3Library} from "../libraries/AcrossV3Library.sol";

abstract contract AcrossMigrator is Migrator {
    V3SpokePoolInterface internal immutable spokePool;

    using AcrossV3Library for V3SpokePoolInterface;

    constructor(address _positionManager, address _spokePool) Migrator(_positionManager) {
        spokePool = V3SpokePoolInterface(_spokePool);
    }
}
