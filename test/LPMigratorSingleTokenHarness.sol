// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ILPMigrator} from "../src/interfaces/ILPMigrator.sol";

import {LPMigratorSingleToken} from "../src/LPMigratorSingleToken.sol";

contract LPMigratorSingleTokenHarness is LPMigratorSingleToken {
    constructor(address _nonfungiblePositionManager, address _token, address _swapRouter, address _spokePool)
        LPMigratorSingleToken(_nonfungiblePositionManager, _token, _swapRouter, _spokePool)
    {}

    function exposed_migratePosition(address from, uint256 tokenId, ILPMigrator.MigrationParams memory migrationParams)
        public
    {
        _migratePosition(from, tokenId, migrationParams);
    }

    function onERC721Received(address, address, uint256, bytes memory) external virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
