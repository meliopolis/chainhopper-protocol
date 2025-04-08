// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Migrator} from "../../src/base/Migrator.sol";

contract MockMigrator is Migrator {
    address private token0;
    address private token1;
    uint256 private amount0;
    uint256 private amount1;

    uint256 private tokenRouteMatchCounter;
    bool[2] private doTokenAndRouteMatch;
    uint256 private isAmountSufficientCounter;
    bool[2] private isAmountSufficient;

    event Log(string message);

    constructor(address initialOwner) Migrator(initialOwner) {}

    function setLiquidity(address _token0, address _token1, uint256 _amount0, uint256 _amount1) external {
        token0 = _token0;
        token1 = _token1;
        amount0 = _amount0;
        amount1 = _amount1;
    }

    function setDoTokenAndRouteMatch(bool[2] memory matches) external {
        doTokenAndRouteMatch = matches;
    }

    function setIsAmountSufficient(bool[2] memory amounts) external {
        isAmountSufficient = amounts;
    }

    function migrate(address sender, uint256 positionId, bytes memory data) public {
        _migrate(sender, positionId, data);
    }

    function _bridge(address, uint32, address, address, uint256, address, bytes memory, bytes memory)
        internal
        override
    {
        emit Log("bridge");
    }

    function _liquidate(uint256) internal view override returns (address, address, uint256, uint256, bytes memory) {
        return (token0, token1, amount0, amount1, "");
    }

    function _swap(bytes memory, bool, uint256 amountIn) internal pure override returns (uint256) {
        return amountIn;
    }

    function _matchTokenWithRoute(address, TokenRoute memory) internal override returns (bool) {
        return doTokenAndRouteMatch[tokenRouteMatchCounter++];
    }

    function _isAmountSufficient(uint256, TokenRoute memory) internal override returns (bool) {
        return isAmountSufficient[isAmountSufficientCounter++];
    }

    // add this to be excluded from coverage report
    function test() public {}
}
