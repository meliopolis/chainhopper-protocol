// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IDualTokensV3V4Migrator {
    struct MigrationParams {
        uint256 destinationChainId;
        address recipient;
        // destination pool
        address token0;
        address token1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
        // destination position
        int24 tickLower;
        int24 tickUpper;
        // others
        uint256 minOutputAmount0;
        uint256 minOutputAmount1;
        uint32 fillDeadlineOffset;
    }
}
