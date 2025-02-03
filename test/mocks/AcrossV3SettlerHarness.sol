// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {AcrossV3Settler} from "../../src/AcrossV3Settler.sol";

contract AcrossV3SettlerHarness is AcrossV3Settler {
    constructor(
        address _spokePool,
        address _protocolFeeRecipient,
        uint24 _protocolFeeBps,
        uint8 _protocolShareOfSenderFeeInPercent,
        address _swapRouter,
        address _positionManager
    )
        AcrossV3Settler(
            _spokePool,
            _protocolFeeRecipient,
            _protocolFeeBps,
            _protocolShareOfSenderFeeInPercent,
            _swapRouter,
            _positionManager
        )
    {}

    function exposed_settle(address baseToken, uint256 amount, bytes memory migrationIdAndSettlementParams) public {
        _settle(baseToken, amount, migrationIdAndSettlementParams);
    }

    function exposed_getSenderFees(bytes memory message) public view returns (uint24, address) {
        return _getSenderFees(message);
    }

    function exposed_getRecipient(bytes memory message) public view returns (address) {
        return _getRecipient(message);
    }

    function exposed_calculateFees(uint256 amount, bytes memory message) public view returns (uint256, uint256) {
        return _calculateFees(amount, message);
    }

    function exposed_refund(bytes32 migrationId) public {
        _refund(migrationId);
    }

    // add this to be excluded from coverage report
    function test() public {}
}
