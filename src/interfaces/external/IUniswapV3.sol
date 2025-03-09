// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.0;

// interface IUniswapV3Pool {
//     function slot0()
//         external
//         view
//         returns (
//             uint160 sqrtPriceX96,
//             int24 tick,
//             uint16 observationIndex,
//             uint16 observationCardinality,
//             uint16 observationCardinalityNext,
//             uint8 feeProtocol,
//             bool unlocked
//         );
// }

// interface IUniswapV3PositionManager {
//     struct MintParams {
//         address token0;
//         address token1;
//         uint24 fee;
//         int24 tickLower;
//         int24 tickUpper;
//         uint256 amount0Desired;
//         uint256 amount1Desired;
//         uint256 amount0Min;
//         uint256 amount1Min;
//         address recipient;
//         uint256 deadline;
//     }

//     function mint(MintParams calldata params)
//         external
//         payable
//         returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

//     struct DecreaseLiquidityParams {
//         uint256 tokenId;
//         uint128 liquidity;
//         uint256 amount0Min;
//         uint256 amount1Min;
//         uint256 deadline;
//     }

//     function decreaseLiquidity(DecreaseLiquidityParams calldata params)
//         external
//         payable
//         returns (uint256 amount0, uint256 amount1);

//     struct CollectParams {
//         uint256 tokenId;
//         address recipient;
//         uint128 amount0Max;
//         uint128 amount1Max;
//     }

//     function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);

//     function burn(uint256 tokenId) external payable;

//     function balanceOf(address owner) external view returns (uint256);

//     function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);

//     function positions(uint256 tokenId)
//         external
//         view
//         returns (
//             uint96 nonce,
//             address operator,
//             address token0,
//             address token1,
//             uint24 fee,
//             int24 tickLower,
//             int24 tickUpper,
//             uint128 liquidity,
//             uint256 feeGrowthInside0LastX128,
//             uint256 feeGrowthInside1LastX128,
//             uint128 tokensOwed0,
//             uint128 tokensOwed1
//         );

//     function factory() external view returns (address);
// }

// // TODO: replace with Universal Router
// interface ISwapRouter {
//     struct ExactInputSingleParams {
//         address tokenIn;
//         address tokenOut;
//         uint24 fee;
//         address recipient;
//         uint256 amountIn;
//         uint256 amountOutMinimum;
//         uint160 sqrtPriceLimitX96;
//     }

//     function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
// }
