// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.28;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IUniswapV3PositionManager} from "../interfaces/external/IUniswapV3.sol";

library UniswapV3Library {
    using SafeERC20 for IERC20;

    function mintPosition(
        IUniswapV3PositionManager self,
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        address recipient
    ) internal returns (uint256 positionId, uint128 liquidity, uint256 amount0, uint256 amount1) {
        IERC20(token0).safeIncreaseAllowance(address(self), amount0Desired);
        IERC20(token1).safeIncreaseAllowance(address(self), amount1Desired);

        (positionId, liquidity, amount0, amount1) = self.mint(
            IUniswapV3PositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: fee,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                recipient: recipient,
                deadline: block.timestamp
            })
        );

        IERC20(token0).safeDecreaseAllowance(address(self), amount0Desired - amount0);
        IERC20(token1).safeDecreaseAllowance(address(self), amount1Desired - amount1);
    }
}
