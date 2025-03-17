// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AcrossSettler} from "./base/AcrossSettler.sol";
import {Settler} from "./base/Settler.sol";
import {V3Settler} from "./base/V3Settler.sol";

contract AcrossV3Settler is AcrossSettler, V3Settler {
    constructor(
        uint24 _protocolFeeBps,
        uint8 _protocolShareOfSenderFeeInPercent,
        address _protocolFeeRecipient,
        address _spokePool,
        address _positionManager,
        address _universalRouter
    )
        Settler(_protocolFeeBps, _protocolShareOfSenderFeeInPercent, _protocolFeeRecipient)
        AcrossSettler(_spokePool)
        V3Settler(_positionManager, _universalRouter)
    {}
}
