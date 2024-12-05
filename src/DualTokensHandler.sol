// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IDualTokenHandler} from "./interfaces/IDualTokenHandler.sol";

contract DualTokensHandler is IDualTokenHandler {
    function handleV3AcrossMessage(address tokenSent, uint256 amount, address relayer, bytes memory message) external {
        // TODO:
    }
}

