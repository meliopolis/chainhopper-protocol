// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IHooks {}

interface IPositionManager {
    function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable;

    function nextTokenId() external view returns (uint256);

    function getPositionLiquidity(uint256 tokenId) external view returns (uint128 liquidity);
}
