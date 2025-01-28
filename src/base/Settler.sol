// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {ISettler} from "../interfaces/ISettler.sol";

abstract contract Settler is ISettler {
    function _settle(address token, uint256 amount, bytes memory message) internal virtual;
}
