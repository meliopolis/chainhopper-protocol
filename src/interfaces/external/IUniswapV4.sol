// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {PoolKey} from "../../libraries/UniswapV4Library.sol";

interface IHooks {}

interface IPoolManager {
    function extsload(bytes32 slot) external view returns (bytes32 value);
}

interface IPositionManager {
    function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable;

    function nextTokenId() external view returns (uint256);

    function getPositionLiquidity(uint256 tokenId) external view returns (uint128 liquidity);

    function poolManager() external view returns (IPoolManager);
}

interface IV4Router {
    struct ExactInputSingleParams {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 amountIn;
        uint128 amountOutMinimum;
        bytes hookData;
    }
}
