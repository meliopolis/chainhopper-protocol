// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IHooks} from "@uniswap-v4-core/interfaces/IHooks.sol";
import {Currency} from "@uniswap-v4-core/types/Currency.sol";
import {PoolKey} from "@uniswap-v4-core/types/PoolKey.sol";
import {IWETH9} from "../interfaces/external/IWETH9.sol";
import {IUniswapV4Settler} from "../interfaces/IUniswapV4Settler.sol";
import {UniswapV4Proxy} from "../libraries/UniswapV4Proxy.sol";
import {Settler} from "./Settler.sol";

abstract contract UniswapV4Settler is IUniswapV4Settler, Settler {
    UniswapV4Proxy private proxy;
    IWETH9 private immutable weth;

    constructor(address positionManager, address universalRouter, address permit2, address _weth) {
        proxy.initialize(positionManager, universalRouter, permit2);
        weth = IWETH9(_weth);
    }

    /*
    assumptions:
    - token can't be native

    Cases to handle:
    - token is erc20; token0 and token1 are erc20; token can be either token0 or token1
    - token is WETH; token0 is native, token1 is erc20; token must be unwrapped for token0
    - all other cases should fail
    */

    function _mintPosition(address token, uint256 amount, address recipient, bytes memory data)
        internal
        override
        returns (uint256 positionId)
    {
        MintParams memory mintParams = abi.decode(data, (MintParams));
        if (
            (token != mintParams.token0 && token != mintParams.token1)
                && (mintParams.token0 != address(0) || token != address(weth))
        ) {
            revert UnusedToken(token);
        }

        // convert weth to native eth first if needed
        if (mintParams.token0 == address(0)) {
            token = _unwrapIfWeth(token, amount);
        }

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
        if (amountIn > 0) amountOut = proxy.swap(poolKey, zeroForOne, amountIn, 0, address(this));

        address tokenOut = Currency.unwrap(zeroForOne ? poolKey.currency1 : poolKey.currency0);
        return _mintPosition(token, tokenOut, amount - amountIn, amountOut, recipient, data);
    }

    /*
        can be called from _settleSingle or from settle()

        assumptions:
        - mintParams.token0 and mintParams.token1 ARE sorted
        - tokenA and tokenB may not be sorted
        - tokenB can't be native (because _mintPosition above will always have tokenOut as erc20 and onlySelfSettle doesn't unwrap any tokens)
        - mintParams.token1 can't be native (v4 only allows native tokens as currency0)

        Cases to handle:
        1. tokenA and tokenB are erc20; token0 and token1 are erc20
        2. tokenA is WETH and tokenB is erc20; token0 is native, token1 is erc20
        3. tokenA is erc20 and tokenB is WETH; token0 is native, token1 is erc20
        4. tokenA is native, tokenB is erc20; token0 is native and token1 is erc20
        5. all other cases should fail

        when called from _mintPosition() above:
        - only cases 1 and 4 are possible (case 2 is not possible because _mintPosition() above will unwrap to swap and send tokenA as native)

        when called from onlySelfSettle():
        - only cases 1, 2 and 3 are possible (case 4 is not possible because onlySelfSettle() won't unwrap tokenA)
    */

    function _mintPosition(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        address recipient,
        bytes memory data
    ) internal override returns (uint256 positionId) {
        MintParams memory mintParams = abi.decode(data, (MintParams));

        // determine if we pool has a native token
        bool isToken0Native = mintParams.token0 == address(0);

        // if token0 is not native, must be case 1
        if (!isToken0Native && (tokenA != mintParams.token0 && tokenA != mintParams.token1)) {
            revert UnusedToken(tokenA);
        }
        if (!isToken0Native && (tokenB != mintParams.token0 && tokenB != mintParams.token1)) {
            revert UnusedToken(tokenB);
        }

        // if token0 is native, must be one of case 2, 3, or 4
        if (
            (isToken0Native)
                && (
                    (
                        (tokenA != address(weth) || tokenB != mintParams.token1)
                            && (tokenB != address(weth) || tokenA != mintParams.token1)
                    ) // case 2 and 3
                        && (tokenA != mintParams.token0 || tokenB != mintParams.token1)
                ) // case 4
        ) {
            revert UnusedTokens(tokenA, tokenB);
        }
        
        // unwrap WETH if needed
        if (isToken0Native && tokenA != address(0)) {
            if (tokenA == address(weth)) {
                tokenA = _unwrapIfWeth(tokenA, amountA);
            } else {
                tokenB = _unwrapIfWeth(tokenB, amountB);
            }
        }

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
        (uint256 amount0, uint256 amount1) =
            tokenA == Currency.unwrap(poolKey.currency0) ? (amountA, amountB) : (amountB, amountA);

        // initialize pool if haven't already
        if (proxy.getPoolSqrtPriceX96(poolKey) == 0) {
            proxy.initializePool(poolKey, mintParams.sqrtPriceX96);
        }

        // mint position
        uint256 amount0Used;
        uint256 amount1Used;
        (positionId,, amount0Used, amount1Used) = proxy.mintPosition(
            poolKey,
            mintParams.tickLower,
            mintParams.tickUpper,
            amount0,
            amount1,
            mintParams.amount0Min,
            mintParams.amount1Min,
            address(this),
            recipient
        );

        // refund surplus tokens
        if (amount0 > amount0Used) poolKey.currency0.transfer(recipient, amount0 - amount0Used);
        if (amount1 > amount1Used) poolKey.currency1.transfer(recipient, amount1 - amount1Used);
    }

    function _unwrapIfWeth(address token, uint256 amount) internal returns (address) {
        if (token == address(weth)) {
            weth.withdraw(amount);
            return address(0);
        }

        return token;
    }

    receive() external payable {}
}
