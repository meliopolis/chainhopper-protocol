// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Settler} from "../../src/base/Settler.sol";

contract SettlerMock is Settler {
    constructor(uint24 _protocolFeeBps, address _protocolFeeRecipient, uint8 _protocolShareOfSenderFeeInPercent)
        Settler(_protocolFeeBps, _protocolFeeRecipient, _protocolShareOfSenderFeeInPercent)
    {}

    function _settle(address, uint256 amount, bytes memory) internal pure override returns (uint256) {
        return amount;
    }

    function _getSenderFees(bytes memory message) internal pure override returns (uint24, address) {
        (, uint24 senderFeeBps, address senderFeeRecipient) = abi.decode(message, (bytes32, uint24, address));
        return (senderFeeBps, senderFeeRecipient);
    }

    function _getRecipient(bytes memory) internal pure override returns (address) {
        return address(111);
    }

    function exposed_calculateFees(uint256 amount, bytes memory message) public view returns (uint256, uint256) {
        return _calculateFees(amount, message);
    }

    function _refund(bytes32) internal pure override {
        return;
    }

    function test() public {}
}
