// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AcrossMigrator} from "../../src/base/AcrossMigrator.sol";

contract MockAcrossMigrator is AcrossMigrator {
    constructor(address _spokePool) AcrossMigrator(_spokePool) {}

    function mockBridge(
        address sender,
        uint32 destinationChainId,
        address destinationSettler,
        TokenRoute memory tokenRoute,
        uint256 amount,
        bytes memory data
    ) external {
        _bridge(sender, destinationChainId, destinationSettler, tokenRoute, amount, data);
    }

    function _liquidate(uint256) internal view override returns (address, address, uint256, uint256, bytes memory) {
        // do nothing
    }

    function _swap(bytes memory, bool, uint256, uint256) internal override returns (uint256) {
        // do nothing
    }

    // add this to be excluded from coverage report
    function test() public {}
}
