// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Settler} from "../../src/base/Settler.sol";
import {MigrationId} from "../../src/types/MigrationId.sol";

contract MockSettler is Settler {
    constructor(address initialOwner) Settler(initialOwner) {}

    function setSettlementCache(MigrationId migrationId, address recipient, address token, uint256 amount) external {
        settlementCaches[migrationId] = SettlementCache(recipient, token, amount, "");
    }

    function wrappedSettle(address token, uint256 amount, bytes memory data) external {
        this.settle(token, amount, data);
    }

    function calculateFees(uint256 amount, uint16 senderShareBps)
        external
        view
        returns (uint256 protocolFee, uint256 senderFee)
    {
        return _calculateFees(amount, senderShareBps);
    }

    function payFees(address token, uint256 protocolFee, uint256 senderFee) external {
        _payFees(token, protocolFee, senderFee, address(0));
    }

    function transfer(address token, address recipient, uint256 amount) external {
        _transfer(token, recipient, amount);
    }

    function refund(MigrationId migrationId, bool onlyRecipient) external {
        _refund(migrationId, onlyRecipient);
    }

    function _settleSingle(address, uint256, bytes memory) internal override returns (uint256) {}

    function _settleDual(address, address, uint256, uint256, bytes memory) internal override returns (uint256) {}

    // add this to be excluded from coverage report
    function test() public {}
}
