// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/utils/math/SafeCast.sol";
import {IPermit2} from "@uniswap-permit2/interfaces/IPermit2.sol";
import {IUniversalRouter} from "@uniswap-universal-router/interfaces/IUniversalRouter.sol";
import {Commands} from "@uniswap-universal-router/libraries/Commands.sol";
// copied and modified from uniswap-v3-periphery, as the original had bad imports
import {INonfungiblePositionManager as IPositionManager} from "../interfaces/external/INonfungiblePositionManager.sol";

/// @title UniswapV3Library
/// @notice Library for Uniswap V3
library UniswapV3Library {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    /// @notice Create and initialize a pool if necessary
    /// @param positionManager The position manager
    /// @param token0 The first token
    /// @param token1 The second token
    /// @param fee The fee
    /// @param sqrtPriceX96 The sqrtPriceX96
    function createAndInitializePoolIfNecessary(
        IPositionManager positionManager,
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) internal {
        // create and initialize pool
        positionManager.createAndInitializePoolIfNecessary(token0, token1, fee, sqrtPriceX96);
    }

    /// @notice Mint a position
    /// @param positionManager The position manager
    /// @param token0 The first token
    /// @param token1 The second token
    /// @param fee The fee
    /// @param tickLower The tick lower
    /// @param tickUpper The tick upper
    function mintPosition(
        IPositionManager positionManager,
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
    ) internal returns (uint256 positionId, uint128 liquidity, uint256 amount0, uint256 amount1) {
        // approve token transfers
        if (amount0Desired > 0) IERC20(token0).forceApprove(address(positionManager), amount0Desired);
        if (amount1Desired > 0) IERC20(token1).forceApprove(address(positionManager), amount1Desired);

        // mint position
        (positionId, liquidity, amount0, amount1) = positionManager.mint(
            IPositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: fee,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                recipient: recipient,
                deadline: block.timestamp
            })
        );

        if (amount0Desired > amount0) IERC20(token0).forceApprove(address(positionManager), 0);
        if (amount1Desired > amount1) IERC20(token1).forceApprove(address(positionManager), 0);
    }

    /// @notice Liquidate a position
    /// @param positionManager The position manager
    /// @param positionId The position id
    /// @param amount0Min The minimum amount of token0
    /// @param amount1Min The minimum amount of token1
    function liquidatePosition(
        IPositionManager positionManager,
        uint256 positionId,
        uint256 amount0Min,
        uint256 amount1Min,
        address recipient
    ) internal returns (address token0, address token1, uint24 fee, uint256 amount0, uint256 amount1) {
        // get position info
        uint128 liquidity;
        (,, token0, token1, fee,,, liquidity,,,,) = positionManager.positions(positionId);

        // burn liquidity
        positionManager.decreaseLiquidity(
            IPositionManager.DecreaseLiquidityParams({
                tokenId: positionId,
                liquidity: liquidity,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                deadline: block.timestamp
            })
        );

        // collect tokens
        (amount0, amount1) = positionManager.collect(
            IPositionManager.CollectParams({
                tokenId: positionId,
                recipient: recipient,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        // burn position
        positionManager.burn(positionId);
    }

    /// @notice Swap tokens
    /// @param universalRouter The universal router
    /// @param permit2 The permit2
    /// @param isPermit2Approved The mapping of approved tokens
    /// @param tokenIn The input token
    /// @param tokenOut The output token
    /// @param fee The fee
    /// @param amountIn The amount of input tokens
    /// @param amountOutMin The minimum amount of output tokens
    function swap(
        IUniversalRouter universalRouter,
        IPermit2 permit2,
        mapping(address => bool) storage isPermit2Approved,
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint256 amountOutMin,
        address recipient
    ) internal returns (uint256 amountOut) {
        // cache balance before swap
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(recipient);

        // approve token transfer via permit2
        approve(permit2, isPermit2Approved, tokenIn, address(universalRouter), amountIn);

        // execute swap via universal router
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.V3_SWAP_EXACT_IN)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(recipient, amountIn, amountOutMin, abi.encodePacked(tokenIn, fee, tokenOut), true);
        universalRouter.execute(commands, inputs, block.timestamp);

        // calculate amount out
        amountOut = IERC20(tokenOut).balanceOf(recipient) - balanceBefore;
    }

    function approve(
        IPermit2 permit2,
        mapping(address => bool) storage isPermit2Approved,
        address token,
        address spender,
        uint256 amount
    ) internal {
        if (!isPermit2Approved[token]) {
            IERC20(token).forceApprove(address(permit2), type(uint256).max);
            isPermit2Approved[token] = true;
        }
        permit2.approve(token, spender, amount.toUint160(), uint48(block.timestamp));
    }
}
