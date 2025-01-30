// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AcrossSettler} from "../../src/base/AcrossSettler.sol";
import {Settler} from "../../src/base/Settler.sol";

contract AcrossSettlerMock is AcrossSettler {
    constructor(address _spokePool) AcrossSettler(_spokePool) Settler(0, address(0), 0) {}

    function _settle(address, uint256, bytes memory) internal pure override returns (uint256) {
        return 0;
    }

    function _getRecipient(bytes memory) internal pure override returns (address) {
        return address(0);
    }

    function _getSenderFees(bytes memory) internal pure override returns (uint24, address) {
        return (0, address(0));
    }

    function settleOuter(address, uint256, bytes memory) external pure override returns (uint256) {
        return 123;
    }

    function test() public {}
}
