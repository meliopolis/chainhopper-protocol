// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
// copied and modified from uniswap-v3-periphery, as the original had bad imports
import {INonfungiblePositionManager as IPositionManager} from "../interfaces/external/INonfungiblePositionManager.sol";

library UniswapV3Library {
    using SafeERC20 for IERC20;

    function mint(
        IPositionManager self,
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address recipient
    ) internal returns (uint256 positionId, uint256 amount0, uint256 amount1) {
        if (amount0Desired > 0) IERC20(token0).safeIncreaseAllowance(address(self), amount0Desired);
        if (amount1Desired > 0) IERC20(token1).safeIncreaseAllowance(address(self), amount1Desired);

        (positionId,, amount0, amount1) = self.mint(
            IPositionManager.MintParams(
                token0,
                token1,
                fee,
                tickLower,
                tickUpper,
                amount0Desired,
                amount1Desired,
                amount0Min,
                amount1Min,
                recipient,
                block.timestamp
            )
        );

        if (amount0 < amount0Desired) IERC20(token0).safeDecreaseAllowance(address(self), amount0Desired - amount0);
        if (amount1 < amount1Desired) IERC20(token1).safeDecreaseAllowance(address(self), amount1Desired - amount1);
    }
}
