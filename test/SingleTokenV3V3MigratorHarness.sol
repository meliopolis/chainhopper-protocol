// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ISingleTokenV3V3Migrator} from "../src/interfaces/ISingleTokenV3V3Migrator.sol";

import {SingleTokenV3V3Migrator} from "../src/SingleTokenV3V3Migrator.sol";

contract SingleTokenV3V3MigratorHarness is SingleTokenV3V3Migrator {
    constructor(address _nonfungiblePositionManager, address _token, address _swapRouter, address _spokePool)
        SingleTokenV3V3Migrator(_nonfungiblePositionManager, _token, _swapRouter, _spokePool)
    {}

    function exposed_migratePosition(
        address from,
        uint256 tokenId,
        ISingleTokenV3V3Migrator.MigrationParams memory migrationParams
    ) public {
        _migratePosition(from, tokenId, migrationParams);
    }

    function onERC721Received(address, address, uint256, bytes memory) external virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // add this to be excluded from coverage report
    function test() public {}
}
