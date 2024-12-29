// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IV3V3Migrator {
    struct MigrationParams {
        uint256 destinationChainId;
        address recipient;
        // destination pool
        address token0;
        address token1;
        uint24 fee;
        // destination position
        int24 tickLower;
        int24 tickUpper;
        // others
        address baseToken;
        uint256 minOutputAmount0;
        uint256 minOutputAmount1;
        uint32 fillDeadlineOffset;
    }
}
