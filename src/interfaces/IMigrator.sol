// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IMigrator {
    error NotPositionManager();
    error DestinationChainSettlerNotFound();

    struct BaseMigrationParams {
        uint256 destinationChainId;
        address recipient;
        bytes settlementParams; // can encode v3 or v4 params
    }
}
