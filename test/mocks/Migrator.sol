// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Migrator} from "../../src/base/Migrator.sol";

contract BaseMigrator is Migrator {
    constructor(address _positionManager) Migrator(_positionManager) {}

    function _migrate(address sender, uint256 positionId, bytes memory data) internal override {
        // do nothing
    }

    // add this to be excluded from coverage report
    function test() public {}
}
