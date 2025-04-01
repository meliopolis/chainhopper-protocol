// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IAcrossMigrator {
    struct Route {
        address outputToken;
        uint256 minAmountOut;
        uint256 maxFees;
        uint32 quoteTimestamp;
        uint32 fillDeadlineOffset;
        address exclusiveRelayer;
        uint32 exclusivityDeadline;
    }
}
