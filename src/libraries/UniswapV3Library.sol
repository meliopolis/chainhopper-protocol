// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.28;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IUniswapV3Pool, IUniswapV3PositionManager, ISwapRouter} from "../interfaces/external/IUniswapV3.sol";

library UniswapV3Library {
    using SafeERC20 for IERC20;

    bytes32 private constant POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

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

    function liquidatePosition(IUniswapV3PositionManager self, uint256 positionId, address recipient)
        internal
        returns (address token0, address token1, uint24 fee, uint256 amount0, uint256 amount1)
    {
        // get position info
        uint128 liquidity;
        (,, token0, token1, fee,,, liquidity,,,,) = self.positions(positionId);

        // burn all liquidity
        self.decreaseLiquidity(
            IUniswapV3PositionManager.DecreaseLiquidityParams({
                tokenId: positionId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        // collect all tokens
        (amount0, amount1) = self.collect(
            IUniswapV3PositionManager.CollectParams({
                tokenId: positionId,
                recipient: recipient,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        // good hygiene
        self.burn(positionId);
    }

    function getCurrentSqrtPriceAndTick(IUniswapV3PositionManager self, address token0, address token1, uint24 fee)
        internal
        view
        returns (uint160 sqrtPriceX96, int24 tick)
    {
        address pool = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff", self.factory(), keccak256(abi.encode(token0, token1, fee)), POOL_INIT_CODE_HASH
                        )
                    )
                )
            )
        );

        (sqrtPriceX96, tick,,,,,) = IUniswapV3Pool(pool).slot0();
    }

    function swap(
        ISwapRouter self,
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) internal returns (uint256 amountOut) {
        IERC20(tokenIn).safeIncreaseAllowance(address(self), amountIn);

        amountOut = self.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: sqrtPriceLimitX96
            })
        );
    }
}
