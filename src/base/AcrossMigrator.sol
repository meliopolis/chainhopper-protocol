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
        uint32 chainId,
        address settler,
        address token,
        uint256 amount,
        bool isTokenNative,
        bytes memory route,
        bytes memory data
    ) internal override {
        Route memory _route = abi.decode(route, (Route));

        if (amount - _route.maxFees < _route.minAmountOut) revert TokenAmountInsufficient();

        // this appears to be needed even if sending native token
        IERC20(token).safeIncreaseAllowance(address(spokePool), amount);
        uint256 value = isTokenNative ? amount : 0;

        // initiate migration via the spoke pool
        spokePool.depositV3{value: value}(
            sender,
            settler,
            token,
            _route.outputToken,
            amount,
            amount - _route.maxFees,
            chainId,
            _route.exclusiveRelayer,
            _route.quoteTimestamp,
            uint32(block.timestamp) + _route.fillDeadlineOffset,
            _route.exclusivityDeadline,
            data
        );
    }
}
