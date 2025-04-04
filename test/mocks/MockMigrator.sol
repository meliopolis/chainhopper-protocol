// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Migrator} from "../../src/base/Migrator.sol";

contract MockMigrator is Migrator {
    constructor(address initialOwner) Migrator(initialOwner) {}

    function _bridge(
        address sender,
        uint32 chainId,
        address settler,
        address token,
        uint256 amount,
        address inputToken,
        bytes memory route,
        bytes memory data
    ) internal override {}

    function _liquidate(uint256 positionId)
        internal
        override
        returns (address token0, address token1, uint256 amount0, uint256 amount1, bytes memory poolInfo)
    {}

    function _swap(bytes memory poolInfo, bool zeroForOne, uint256 amountIn)
        internal
        override
        returns (uint256 amountOut)
    {}

    function _matchTokenWithRoute(address token, TokenRoute memory tokenRoute) internal view override returns (bool) {}

    function _isAmountSufficient(uint256 amount, TokenRoute memory tokenRoute) internal view override returns (bool) {}

    // add this to be excluded from coverage report
    function test() public {}
}
