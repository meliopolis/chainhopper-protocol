// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IUniswapV3Settler} from "../interfaces/IUniswapV3Settler.sol";
import {UniswapV3Proxy} from "../libraries/UniswapV3Proxy.sol";
import {Settler} from "./Settler.sol";

/// @title UniswapV3Settler
/// @notice Contract for settling migrations on Uniswap V3
abstract contract UniswapV3Settler is IUniswapV3Settler, Settler {
    using SafeERC20 for IERC20;

    /// @notice The Uniswap V3 proxy
    UniswapV3Proxy private proxy;

    /// @notice Constructor for the UniswapV3Settler contract
    /// @param positionManager The position manager address
    /// @param universalRouter The universal router address
    /// @param permit2 The permit2 address
    constructor(address positionManager, address universalRouter, address permit2) {
        proxy.initialize(positionManager, universalRouter, permit2);
    }

    /// @notice Function to mint a position
    /// @param token The token to mint
    /// @param amount The amount to mint
    /// @param recipient The recipient of the minted token
    /// @param data mint params
    function _mintPosition(address token, uint256 amount, address recipient, bytes memory data)
        internal
        override
        returns (uint256 positionId)
    {
        MintParams memory mintParams = abi.decode(data, (MintParams));
        if (token != mintParams.token0 && token != mintParams.token1) revert UnusedToken(token);

        // get token out and amount in
        address tokenOut = token == mintParams.token0 ? mintParams.token1 : mintParams.token0;
        uint256 amountIn = (amount * mintParams.swapAmountInMilliBps) / UNIT_IN_MILLI_BASIS_POINTS;

        // swap tokens if needed
        uint256 amountOut;
        if (amountIn > 0) amountOut = proxy.swap(token, tokenOut, mintParams.fee, amountIn, 0, address(this));

        return _mintPosition(token, tokenOut, amount - amountIn, amountOut, recipient, data);
    }

    /// @notice Internal function to mint a position
    /// @param tokenA The first token
    /// @param tokenB The second token
    /// @param amountA The amount of the first token
    /// @param amountB The amount of the second token
    /// @param recipient The recipient of the minted token
    /// @param data mint params
    function _mintPosition(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        address recipient,
        bytes memory data
    ) internal override returns (uint256 positionId) {
        MintParams memory mintParams = abi.decode(data, (MintParams));
        if (tokenA != mintParams.token0 && tokenA != mintParams.token1) revert UnusedToken(tokenA);
        if (tokenB != mintParams.token0 && tokenB != mintParams.token1) revert UnusedToken(tokenB);

        // align amounts to tokens
        (uint256 amount0, uint256 amount1) = tokenA == mintParams.token0 ? (amountA, amountB) : (amountB, amountA);

        // create and initialize pool if necessary
        proxy.createAndInitializePoolIfNecessary(
            mintParams.token0, mintParams.token1, mintParams.fee, mintParams.sqrtPriceX96
        );

        // mint position
        uint256 amount0Used;
        uint256 amount1Used;
        (positionId,, amount0Used, amount1Used) = proxy.mintPosition(
            mintParams.token0,
            mintParams.token1,
            mintParams.fee,
            mintParams.tickLower,
            mintParams.tickUpper,
            amount0,
            amount1,
            mintParams.amount0Min,
            mintParams.amount1Min,
            recipient
        );

        // refund surplus tokens
        if (amount0 > amount0Used) IERC20(mintParams.token0).safeTransfer(recipient, amount0 - amount0Used);
        if (amount1 > amount1Used) IERC20(mintParams.token1).safeTransfer(recipient, amount1 - amount1Used);
    }
}
