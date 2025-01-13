// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IHooks {}

interface IPositionManager {
    function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable;
}
