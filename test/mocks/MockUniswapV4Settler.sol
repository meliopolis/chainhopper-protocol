// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.24;

// import {Settler} from "../../src/base/Settler.sol";
// import {UniswapV4Settler} from "../../src/base/UniswapV4Settler.sol";

// contract MockUniswapV4Settler is UniswapV4Settler {
//     constructor(address initialOwner, address positionManager, address universalRouter, address permit2, address weth)
//         Settler(initialOwner)
//         UniswapV4Settler(positionManager, universalRouter, permit2, weth)
//     {}

//     function mintPosition(address token, uint256 amount, address recipient, bytes memory data)
//         external
//         returns (uint256)
//     {
//         return _mintPosition(token, amount, recipient, data);
//     }

//     function mintPosition(
//         address tokenA,
//         address tokenB,
//         uint256 amountA,
//         uint256 amountB,
//         address recipient,
//         bytes memory data
//     ) external returns (uint256) {
//         return _mintPosition(tokenA, tokenB, amountA, amountB, recipient, data);
//     }

//     // add this to be excluded from coverage report
//     function test() public {}
// }
