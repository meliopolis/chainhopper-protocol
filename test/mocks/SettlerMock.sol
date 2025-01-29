// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Settler} from "../../src/base/Settler.sol";

contract SettlerMock is Settler {
    constructor(uint24 _protocolFeeBps, address _protocolFeeRecipient, uint8 _protocolShareOfSenderFeeInPercent)
        Settler(_protocolFeeBps, _protocolFeeRecipient, _protocolShareOfSenderFeeInPercent)
    {}

    function _settle(address token, uint256 amount, bytes memory message)
        internal
        pure
        override
        returns (uint256 tokenId)
    {
        return 1;
    }

    function _getSenderFees(bytes memory message) internal pure override returns (uint24, address) {
        (uint24 senderFeeBps, address senderFeeRecipient) = abi.decode(message, (uint24, address));
        return (senderFeeBps, senderFeeRecipient);
    }

    function _getRecipient(bytes memory message) internal pure override returns (address) {
        return address(0);
    }
}
