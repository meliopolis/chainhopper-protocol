// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AcrossSettler} from "./base/AcrossSettler.sol";
import {Settler} from "./base/Settler.sol";
import {V4Settler} from "./base/V4Settler.sol";

contract AcrossV4Settler is AcrossSettler, V4Settler {
    constructor(
        address _spoke,
        uint24 _protocolFeeBps,
        uint8 _protocolShareOfSenderFeeInPercent,
        address _protocolFeeRecipient,
        address _positionManager,
        address _universalRouter
    )
        AcrossSettler(_spoke)
        Settler(_protocolFeeBps, _protocolShareOfSenderFeeInPercent, _protocolFeeRecipient)
        V4Settler(_positionManager, _universalRouter)
    {}
}
