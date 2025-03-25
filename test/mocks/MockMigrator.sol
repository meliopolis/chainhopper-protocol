// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Migrator} from "../../src/base/Migrator.sol";

contract MockMigrator is Migrator {
    address private token0;
    address private token1;
    uint256 private amount0;
    uint256 private amount1;

    function dealLiquidity(address _token0, address _token1, uint256 _amount0, uint256 _amount1) external {
        token0 = _token0;
        token1 = _token1;
        amount0 = _amount0;
        amount1 = _amount1;
    }

    function migrate(address sender, uint256 positionId, bytes memory data) external {
        _migrate(sender, positionId, data);
    }

    function _liquidate(uint256) internal view override returns (address, address, uint256, uint256, bytes memory) {
        return (token0, token1, amount0, amount1, "");
    }

    function _swap(bytes memory, bool, uint256, uint256) internal override returns (uint256) {
        // do nothing
    }

    function _bridge(address, uint32, address, TokenRoute memory, uint256, bytes memory) internal override {
        // do nothing
    }

    // add this to be excluded from coverage report
    function test() public {}
}
