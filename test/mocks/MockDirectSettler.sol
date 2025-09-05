// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {DirectSettler} from "../../src/base/DirectSettler.sol";
import {Settler} from "../../src/base/Settler.sol";
import {MigrationData} from "../../src/types/MigrationData.sol";

contract MockDirectSettler is DirectSettler {
    constructor(address initialOwner) Settler(initialOwner) {}

    function getSettlementCache(bytes32 migrationId)
        external
        view
        returns (address recipient, address token, uint256 amount)
    {
        SettlementCache memory cache = settlementCaches[migrationId];
        return (cache.recipient, cache.token, cache.amount);
    }

    function setSettlementCache(bytes32 migrationId, address recipient, address token, uint256 amount) external {
        settlementCaches[migrationId] = SettlementCache(recipient, token, amount);
    }

    function _mintPosition(address token, uint256 amount, address recipient, bytes memory data)
        internal
        pure
        override
        returns (uint256 positionId)
    {
        // Mock implementation - return a dummy position ID
        positionId = uint256(keccak256(abi.encodePacked(token, amount, recipient, data)));
    }

    function _mintPosition(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        address recipient,
        bytes memory data
    ) internal pure override returns (uint256 positionId) {
        // Mock implementation - return a dummy position ID
        positionId = uint256(keccak256(abi.encodePacked(tokenA, tokenB, amountA, amountB, recipient, data)));
    }

    // add this to be excluded from coverage report
    function test() public {}
}
