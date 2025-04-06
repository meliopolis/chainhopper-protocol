// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MigrationId} from "../types/MigrationId.sol";

interface IAcrossSettler {
    error NotSpokePool();

    event Receipt(MigrationId indexed migrationId, address indexed recipient, address indexed token, uint256 amount);
}
