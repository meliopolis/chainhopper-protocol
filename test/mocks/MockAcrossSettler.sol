// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AcrossSettler} from "../../src/base/AcrossSettler.sol";
import {Settler} from "../../src/base/Settler.sol";
import {MigrationId, MigrationIdLibrary} from "../../src/types/MigrationId.sol";
import {MigrationModes} from "../../src/types/MigrationMode.sol";

contract MockAcrossSettler is AcrossSettler {
    bool private shouldSettleRevert;

    constructor(address initialOwner, address spokePool) Settler(initialOwner) AcrossSettler(spokePool) {}

    function setSettlementCache(MigrationId migrationId, SettlementCache memory cache) external {
        settlementCaches[migrationId] = cache;
    }

    function setShouldSettleRevert(bool shouldRevert) external {
        shouldSettleRevert = shouldRevert;
    }

    function selfSettle(address, uint256, bytes memory) external view override returns (MigrationId, address) {
        if (shouldSettleRevert) revert();
        return (MigrationIdLibrary.from(uint32(block.chainid), address(2), MigrationModes.DUAL, 1), address(2));
    }

    function _mintPosition(address token, uint256 amount, address recipient, bytes memory data)
        internal
        override
        returns (uint256 positionId)
    {}

    function _mintPosition(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        address recipient,
        bytes memory data
    ) internal override returns (uint256 positionId) {}

    // add this to be excluded from coverage report
    function test() public {}
}
