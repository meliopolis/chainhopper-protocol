// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.24;

// import {Migrator} from "../../src/base/Migrator.sol";
// import {UniswapV3Migrator} from "../../src/base/UniswapV3Migrator.sol";

// contract MockUniswapV3Migrator is UniswapV3Migrator {
//     event NoOp();

//     constructor(address initialOwner, address positionManager, address universalRouter, address permit2)
//         Migrator(initialOwner)
//         UniswapV3Migrator(positionManager, universalRouter, permit2)
//     {}

//     function _bridge(
//         address sender,
//         uint32 chainId,
//         address settler,
//         address token,
//         uint256 amount,
//         address inputToken,
//         bytes memory route,
//         bytes memory data
//     ) internal override {}

//     function _migrate(address, uint256, bytes memory) internal override {
//         emit NoOp();
//     }

//     function _matchTokenWithRoute(address token, TokenRoute memory tokenRoute) internal view override returns (bool) {}

//     function _isAmountSufficient(uint256 amount, TokenRoute memory tokenRoute) internal view override returns (bool) {}

//     function liquidate(uint256 positionId) public returns (address, address, uint256, uint256, bytes memory) {
//         return _liquidate(positionId);
//     }

//     function swap(bytes memory poolInfo, bool zeroForOne, uint256 amountIn) public returns (uint256) {
//         return _swap(poolInfo, zeroForOne, amountIn);
//     }
//     // add this to be excluded from coverage report

//     function test() public {}
// }
