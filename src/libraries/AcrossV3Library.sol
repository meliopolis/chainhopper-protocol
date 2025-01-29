// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IAcrossV3SpokePool} from "../interfaces/external/IAcrossV3.sol";

library AcrossV3Library {
    using SafeERC20 for IERC20;

    function bridge(
        IAcrossV3SpokePool self,
        address sender,
        uint256 destinationChainId,
        address recipient,
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint32 quoteTimestamp,
        uint32 deadlineOffset,
        address exclusiveRelayer,
        uint32 exclusivityDeadline,
        bytes memory message
    ) internal {
        IERC20(tokenIn).safeIncreaseAllowance(address(self), amountIn);

        self.depositV3(
            sender,
            recipient,
            tokenIn,
            tokenOut,
            amountIn,
            minAmountOut,
            destinationChainId,
            exclusiveRelayer,
            quoteTimestamp,
            deadlineOffset,
            exclusivityDeadline,
            message
        );
    }

    // function migrate(
    //     IAcrossV3SpokePool self,
    //     address sender,
    //     uint256 destinationChainId,
    //     address recipient,
    //     address tokenIn,
    //     uint256 amountIn,
    //     address tokenOut,
    //     uint256 minAmountOut,
    //     uint32 deadlineOffset,
    //     address exclusiveRelayer,
    //     uint32 exclusivityDeadline,
    //     bytes memory message
    // ) internal {
    //     IERC20(tokenIn).safeIncreaseAllowance(address(self), amountIn);

    //     self.depositV3Now(
    //         sender,
    //         recipient,
    //         tokenIn,
    //         tokenOut,
    //         amountIn,
    //         minAmountOut,
    //         destinationChainId,
    //         exclusiveRelayer,
    //         deadlineOffset,
    //         exclusivityDeadline,
    //         message
    //     );
    // }
}
