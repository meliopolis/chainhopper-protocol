// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ISingleTokenV3V3Migrator {
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
        address outputToken;
        uint256 minOutputAmount;
        uint32 fillDeadlineOffset;
    }
}
