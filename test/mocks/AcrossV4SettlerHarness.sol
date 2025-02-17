// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {AcrossV4Settler} from "../../src/AcrossV4Settler.sol";

contract AcrossV4SettlerHarness is AcrossV4Settler {
    constructor(
        address _spokePool,
        address _protocolFeeRecipient,
        uint24 _protocolFeeBps,
        uint8 _protocolShareOfSenderFeeInPercent,
        address _universalRouter,
        address _positionManager,
        address _weth,
        address permit2
    )
        AcrossV4Settler(
            _spokePool,
            _protocolFeeRecipient,
            _protocolFeeBps,
            _protocolShareOfSenderFeeInPercent,
            _universalRouter,
            _positionManager,
            _weth,
            permit2
        )
    {}

    function exposed_getRecipient(bytes memory message) public view returns (address) {
        return _getRecipient(message);
    }

    function exposed_refund(bytes32 migrationId) public {
        _refund(migrationId);
    }

    function exposed_getSenderFees(bytes memory message) public view returns (uint24, address) {
        return _getSenderFees(message);
    }

    function exposed_settle(address baseToken, uint256 amount, bytes memory migrationIdAndSettlementParams) public {
        _settle(baseToken, amount, migrationIdAndSettlementParams);
    }
}
