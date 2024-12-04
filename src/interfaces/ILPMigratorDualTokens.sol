// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ILPMigratorDualTokens {
    struct NPMPermitParams {
        uint256 positionId;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct LPMigrationOrder {
        address depositor;
        address recipient;
        uint256 positionId;
        uint256 bondAmount0;
        uint256 bondAmount1;
        uint256 feePercentage0;
        uint256 feePercentage1;
        uint256 destinationChainId;
        address exclusiveRelayer;
        uint256 fillDeadlineBuffer;
    }

    struct LPMigrationMessage {
        uint256 migrationId;
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0;
        uint256 amount1;
    }
}
