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
    address private immutable weth;

    constructor(address _spokePool, address _weth) {
        spokePool = IAcrossSpokePool(_spokePool);
        weth = _weth;
    }

    function _bridge(
        address sender,
        uint32 chainId,
        address settler,
        address token,
        uint256 amount,
        bool isNativeTransfer,
        bytes memory routeData,
        bytes memory data
    ) internal override {
        Route memory route = abi.decode(routeData, (Route));

        // this appears to be needed even if sending native token
        IERC20(token).safeIncreaseAllowance(address(spokePool), amount);
        uint256 value = isNativeTransfer ? amount : 0;

        // initiate migration via the spoke pool
        spokePool.depositV3{value: value}(
            sender,
            settler,
            token,
            route.outputToken,
            amount,
            amount - route.maxFees,
            chainId,
            route.exclusiveRelayer,
            route.quoteTimestamp,
            uint32(block.timestamp) + route.fillDeadlineOffset,
            route.exclusivityDeadline,
            data
        );
    }

    function _matchTokenWithRoute(address token, TokenRoute memory tokenRoute) internal view override returns (bool) {
        return token == tokenRoute.token || (token == address(0) && tokenRoute.token == weth);
    }

    function _isAmountSufficient(uint256 amount, TokenRoute memory tokenRoute) internal pure override returns (bool) {
        Route memory route = abi.decode(tokenRoute.route, (Route));

        return amount >= tokenRoute.amountOutMin + route.maxFees;
    }
}
