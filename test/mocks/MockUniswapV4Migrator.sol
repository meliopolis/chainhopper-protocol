// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Migrator} from "../../src/base/Migrator.sol";
import {UniswapV4Migrator} from "../../src/base/UniswapV4Migrator.sol";

contract MockUniswapV4Migrator is UniswapV4Migrator {
    constructor(address initialOwner, address positionManager, address universalRouter, address permit2)
        Migrator(initialOwner)
        UniswapV4Migrator(positionManager, universalRouter, permit2)
    {}

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

    function _matchTokenWithRoute(address token, TokenRoute memory tokenRoute) internal view override returns (bool) {}

    function _isAmountSufficient(uint256 amount, TokenRoute memory tokenRoute) internal view override returns (bool) {}

    // add this to be excluded from coverage report
    function test() public {}
}
