// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {V3SpokePoolInterface as IAcrossSpokePool} from "@across/interfaces/V3SpokePoolInterface.sol";
import {IAcrossMigrator} from "../interfaces/IAcrossMigrator.sol";
import {Migrator} from "./Migrator.sol";

abstract contract AcrossMigrator is IAcrossMigrator, Migrator {
    IAcrossSpokePool private immutable spokePool;

    constructor(address _spokePool) {
        spokePool = IAcrossSpokePool(_spokePool);
    }

    function _migrate(
        address sender,
        uint32 destinationChainId,
        address destinationSettler,
        TokenRoute memory tokenRoute,
        uint256 amount,
        bytes memory message
    ) internal override {
        Route memory route = abi.decode(tokenRoute.route, (Route));

        spokePool.depositV3(
            sender,
            destinationSettler,
            route.inputToken,
            route.outputToken,
            amount,
            amount - route.maxFees,
            destinationChainId,
            route.exclusiveRelayer,
            route.quoteTimestamp,
            uint32(block.timestamp) + route.fillDeadlineOffset,
            route.exclusivityDeadline,
            message
        );
    }
}
