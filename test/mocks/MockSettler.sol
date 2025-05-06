// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Settler} from "../../src/base/Settler.sol";

contract MockSettler is Settler {
    constructor(address initialOwner) Settler(initialOwner) {}

    function getSettlementCache(bytes32 migrationHash)
        external
        view
        returns (address recipient, address token, uint256 amount)
    {
        SettlementCache memory cache = settlementCaches[migrationHash];
        return (cache.recipient, cache.token, cache.amount);
    }

    function setSettlementCache(bytes32 migrationHash, address recipient, address token, uint256 amount) external {
        settlementCaches[migrationHash] = SettlementCache(recipient, token, amount);
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
