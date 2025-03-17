// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IAcrossMigrator {
    error NotPositionManager();

    struct Route {
        address inputToken;
        address outputToken;
        uint256 maxFees;
        uint32 quoteTimestamp;
        uint32 fillDeadlineOffset;
        address exclusiveRelayer;
        uint32 exclusivityDeadline;
    }
}
