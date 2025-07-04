// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AcrossSettler} from "../../src/base/AcrossSettler.sol";
import {Settler} from "../../src/base/Settler.sol";
import {MigrationData} from "../../src/types/MigrationData.sol";

contract MockAcrossSettler is AcrossSettler {
    bytes4 private errorSelector;

    event Log(string message);

    constructor(address initialOwner, address spokePool) Settler(initialOwner) AcrossSettler(spokePool) {}

    function setErrorSelector(bytes4 selector) external {
        errorSelector = selector;
    }

    function selfSettle(bytes32, address, uint256, MigrationData memory) external view override returns (bool) {
        bytes4 selector = errorSelector;

        if (errorSelector != bytes4(0)) {
            assembly ("memory-safe") {
                let ptr := mload(0x40)
                mstore(ptr, selector)
                revert(ptr, 4)
            }
        }
        return true;
    }

    function _refund(bytes32, bool) internal override {
        emit Log("refund");
    }

    function _mintPosition(address token, uint256 amount, address recipient, bytes memory data)
        internal
        override
        returns (uint256 positionId)
    {}

    function _mintPosition(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        address recipient,
        bytes memory data
    ) internal override returns (uint256 positionId) {}

    // add this to be excluded from coverage report
    function test() public {}
}
