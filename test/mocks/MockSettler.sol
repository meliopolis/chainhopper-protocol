// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {MigrationId} from "../../src/types/MigrationId.sol";
import {Settler} from "../../src/base/Settler.sol";

contract MockSettler is Settler {
    constructor(address initialOwner) Settler(initialOwner) {}

    function setSettlementCache(
        MigrationId migrationId,
        address recipient,
        address token,
        uint256 amount,
        bytes memory data
    ) external {
        settlementCaches[migrationId] = SettlementCache(recipient, token, amount, data);
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

    function exposeTransfer(address token, address recipient, uint256 amount) external {
        _transfer(token, recipient, amount);
    }
    // add this to be excluded from coverage report

    function test() public {}
}
