// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {V3SpokePoolInterface as IAcrossSpokePool} from "@across/interfaces/V3SpokePoolInterface.sol";
import {IAcrossMigrator} from "../interfaces/IAcrossMigrator.sol";
import {Migrator} from "./Migrator.sol";

abstract contract AcrossMigrator is IAcrossMigrator, Migrator {
    using SafeERC20 for IERC20;

    IAcrossSpokePool private immutable spokePool;

    constructor(address _spokePool) {
        spokePool = IAcrossSpokePool(_spokePool);
    }

    function _bridge(
        address sender,
        uint32 destinationChainId,
        address destinationSettler,
        TokenRoute memory tokenRoute,
        uint256 amount,
        bytes memory data
    ) internal override {
        Route memory route = abi.decode(tokenRoute.route, (Route));
        IERC20(tokenRoute.token).safeIncreaseAllowance(address(spokePool), amount);

        // initiate migration via the spoke pool
        spokePool.depositV3(
            sender,
            destinationSettler,
            tokenRoute.token,
            route.outputToken,
            amount,
            amount - route.maxFees,
            destinationChainId,
            route.exclusiveRelayer,
            route.quoteTimestamp,
            uint32(block.timestamp) + route.fillDeadlineOffset,
            route.exclusivityDeadline,
            data
        );
    }
}
