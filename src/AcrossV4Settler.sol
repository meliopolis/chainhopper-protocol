// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AcrossSettler} from "./base/AcrossSettler.sol";
import {Settler} from "./base/Settler.sol";
import {V4Settler} from "./base/V4Settler.sol";

contract AcrossV4Settler is AcrossSettler, V4Settler {
    constructor(
        uint24 _protocolFeeBps,
        uint8 _protocolShareOfSenderFeeInPercent,
        address _protocolFeeRecipient,
        address _spokePool,
        address _positionManager,
        address _universalRouter,
        address _permit2
    )
        Settler(_protocolFeeBps, _protocolShareOfSenderFeeInPercent, _protocolFeeRecipient)
        AcrossSettler(_spokePool)
        V4Settler(_positionManager, _universalRouter, _permit2)
    {}
}
