// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

type MigrationMode is uint8;

using {equals as ==} for MigrationMode global;

function equals(MigrationMode a, MigrationMode b) pure returns (bool) {
    return MigrationMode.unwrap(a) == MigrationMode.unwrap(b);
}

library MigrationModes {
    MigrationMode constant SINGLE = MigrationMode.wrap(1);
    MigrationMode constant DUAL = MigrationMode.wrap(2);
}
