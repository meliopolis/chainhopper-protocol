// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IDualTokensV3V4Migrator {
    event Migrate(
        bytes32 indexed migrationId,
        uint256 indexed positionId,
        uint256 indexed destinationChainId,
        // source
        address sender,
        address sourceToken0,
        address sourceToken1,
        uint256 sourceAmount0,
        uint256 sourceAmount1,
        // destination
        address settler,
        address recipient,
        address destinationToken0,
        address destinationToken1,
        uint256 destinationAmount0,
        uint256 destinationAmount1,
        uint24 fee,
        int24 tickSpacing,
        address hooks,
        int24 tickLower,
        int24 tickUpper
    );

    struct MigrationParams {
        uint256 destinationChainId;
        address recipient;
        // destination pool
        address token0; // assumes token0 < token1
        address token1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
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
