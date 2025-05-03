// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IPermit2} from "@uniswap-permit2/interfaces/IPermit2.sol";
import {IUniversalRouter} from "@uniswap-universal-router/interfaces/IUniversalRouter.sol";
import {IHooks} from "@uniswap-v4-core/interfaces/IHooks.sol";
import {Currency} from "@uniswap-v4-core/types/Currency.sol";
import {PoolKey} from "@uniswap-v4-core/types/PoolKey.sol";
import {IPositionManager} from "@uniswap-v4-periphery/interfaces/IPositionManager.sol";
import {IWETH9} from "../interfaces/external/IWETH9.sol";
import {IUniswapV4Settler} from "../interfaces/IUniswapV4Settler.sol";
import {UniswapV4Library} from "../libraries/UniswapV4Library.sol";
import {Settler} from "./Settler.sol";

/// @title UniswapV4Settler
/// @notice Contract for settling migrations on Uniswap V4
abstract contract UniswapV4Settler is IUniswapV4Settler, Settler {
    IPositionManager private immutable positionManager;
    IUniversalRouter private immutable universalRouter;
    IPermit2 private immutable permit2;
    IWETH9 private immutable weth;
    mapping(Currency => bool) isPermit2Approved;

    /// @notice Constructor for the UniswapV4Settler contract
    /// @param _positionManager The position manager address
    /// @param _universalRouter The universal router address
    /// @param _permit2 The permit2 address
    /// @param _weth The WETH address
    constructor(address _positionManager, address _universalRouter, address _permit2, address _weth) {
        positionManager = IPositionManager(_positionManager);
        universalRouter = IUniversalRouter(_universalRouter);
        permit2 = IPermit2(_permit2);
        weth = IWETH9(_weth);
    }

    /// @notice Function to mint a position
    function _mintPosition(address token, uint256 amount, address recipient, bytes memory data)
        internal
        override
        returns (uint256 positionId)
    {
        MintParams memory mintParams = abi.decode(data, (MintParams));

        // try unwrap token if native token is expected, and token is not token1
        if (mintParams.token0 == address(0) && token != mintParams.token1) {
            token = _unwrapIfWeth(token, amount);
        }
        // now token must match either token0 or token1
        if (token != mintParams.token0 && token != mintParams.token1) revert UnusedToken(token);

        // compute pool key, swap direction, and amount in
        PoolKey memory poolKey = PoolKey(
            Currency.wrap(mintParams.token0),
            Currency.wrap(mintParams.token1),
            mintParams.fee,
            mintParams.tickSpacing,
            IHooks(mintParams.hooks)
        );
        bool zeroForOne = token == Currency.unwrap(poolKey.currency0);
        uint256 amountIn = (amount * mintParams.swapAmountInMilliBps) / 10_000_000;

        // swap tokens if needed
        uint256 amountOut;
        if (amountIn > 0) {
            amountOut = UniswapV4Library.swap(
                universalRouter, permit2, isPermit2Approved, poolKey, zeroForOne, amountIn, 0, address(this)
            );
        }

        address tokenOut = Currency.unwrap(zeroForOne ? poolKey.currency1 : poolKey.currency0);
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

        // try unwrap tokenA or tokenB if native token is expected, they are guaranteed to not be the same
        if (mintParams.token0 == address(0) && tokenA != address(0) && tokenB != address(0)) {
            tokenA = _unwrapIfWeth(tokenA, amountA);
            tokenB = _unwrapIfWeth(tokenB, amountB);
        }
        // now tokenA and tokenB must match token0 and token1, in any order
        if (tokenA != mintParams.token0 && tokenA != mintParams.token1) revert UnusedToken(tokenA);
        if (tokenB != mintParams.token0 && tokenB != mintParams.token1) revert UnusedToken(tokenB);

        // compute pool key
        PoolKey memory poolKey = PoolKey(
            Currency.wrap(mintParams.token0),
            Currency.wrap(mintParams.token1),
            mintParams.fee,
            mintParams.tickSpacing,
            IHooks(mintParams.hooks)
        );

        // align amounts to currencies
        (uint256 amount0, uint256 amount1) =
            tokenA == Currency.unwrap(poolKey.currency0) ? (amountA, amountB) : (amountB, amountA);

        // initialize pool if haven't already
        if (UniswapV4Library.getPoolSqrtPriceX96(positionManager, poolKey) == 0) {
            UniswapV4Library.initializePool(positionManager, poolKey, mintParams.sqrtPriceX96);
        }

        // mint position
        uint256 amount0Used;
        uint256 amount1Used;
        (positionId,, amount0Used, amount1Used) = UniswapV4Library.mintPosition(
            positionManager,
            permit2,
            isPermit2Approved,
            poolKey,
            mintParams.tickLower,
            mintParams.tickUpper,
            amount0,
            amount1,
            mintParams.amount0Min,
            mintParams.amount1Min,
            recipient
        );

        // refund surplus tokens
        if (amount0 > amount0Used) {
            uint256 amount = amount0 - amount0Used;
            address token = _wrapIfEth(Currency.unwrap(poolKey.currency0), amount);

            Currency.wrap(token).transfer(recipient, amount);
        }

        if (amount0 > amount0Used) poolKey.currency0.transfer(recipient, amount0 - amount0Used);
        if (amount1 > amount1Used) poolKey.currency1.transfer(recipient, amount1 - amount1Used);
    }

    /// @notice Internal function to unwrap WETH to native token
    /// @param token The token to unwrap
    /// @param amount The amount of the token to unwrap
    /// @return The address of the unwrapped token
    function _unwrapIfWeth(address token, uint256 amount) internal returns (address) {
        if (token == address(weth)) {
            weth.withdraw(amount);
            return address(0);
        }

        return token;
    }

    /// @notice Internal function to wrap native token to WETH
    /// @param token The token to wrap
    /// @param amount The amount of the token to wrap
    /// @return The address of the wrapped token
    function _wrapIfEth(address token, uint256 amount) internal returns (address) {
        if (token == address(0)) {
            weth.deposit{value: amount}();
            return address(weth);
        }

        return token;
    }

    receive() external payable {}
}
