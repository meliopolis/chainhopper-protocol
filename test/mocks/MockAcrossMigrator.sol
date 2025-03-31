// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AcrossMigrator} from "../../src/base/AcrossMigrator.sol";
import {Migrator} from "../../src/base/Migrator.sol";

contract MockAcrossMigrator is AcrossMigrator {
    constructor(address _spokePool) AcrossMigrator(_spokePool) Migrator(msg.sender) {}

    function mockBridge(
        address sender,
        uint32 chainId,
        address settler,
        address token,
        uint256 amount,
        bytes memory route,
        bytes memory data
    ) external {
        _bridge(sender, chainId, settler, token, amount, route, data);
    }

    function _liquidate(uint256, uint256, uint256)
        internal
        override
        returns (address, address, uint256, uint256, bytes memory)
    {}

    function _swap(bytes memory, bool, uint256, uint256) internal override returns (uint256) {}

    // add this to be excluded from coverage report
    function test() public {}
}
