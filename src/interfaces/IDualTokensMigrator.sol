// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IDualTokensMigrator {
    struct NPMPermitParams {
        uint256 positionId;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct MigrationOrder {
        address depositor;
        uint256 positionId;
        uint256 bondAmount0;
        uint256 bondAmount1;
        uint256 feePercentage0;
        uint256 feePercentage1;
        uint256 destinationChainId;
        address recipient;
        address exclusiveRelayer;
        uint256 fillDeadlineBuffer;
    }

    struct MigrationMessage {
        uint256 migrationId;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        address recipient;
    }
}
