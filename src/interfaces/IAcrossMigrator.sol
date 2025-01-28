// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IMigrator} from "./IMigrator.sol";

interface IAcrossMigrator is IMigrator {
    error NoAcrossRoutesFound();
    error TooManyAcrossRoutes();
    error RouteInputTokenNotFound(uint8 routeIndex);
    error UnusedExtraRoute();

    struct AcrossRoute {
        address inputToken;
        address outputToken;
        uint256 maxFees;
        uint32 quoteTimestamp;
        uint32 fillDeadlineOffset;
        address exclusiveRelayer;
        uint32 exclusivityDeadline;
    }

    struct AcrossMigrationParams {
        IMigrator.BaseMigrationParams baseParams;
        AcrossRoute[] acrossRoutes;
    }

    event PositionSent(
        uint256 indexed positionId,
        uint256 indexed destinationChainId,
        address indexed recipient,
        bytes settlementParams
    );
}
