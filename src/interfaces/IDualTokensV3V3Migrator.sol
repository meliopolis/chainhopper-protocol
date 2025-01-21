// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IDualTokensV3V3Migrator {
    struct MigrationParams {
        uint256 destinationChainId;
        address recipient;
        // destination pool
        address token0; // assumes token0 < token1
        address token1;
        uint24 fee;
        // destination position
        int24 tickLower;
        int24 tickUpper;
        bool tokensFlipped; // if token0 and token1 are flipped on dest
        // others
        uint256 minOutputAmount0;
        uint256 minOutputAmount1;
        uint32 fillDeadlineOffset;
    }
}
