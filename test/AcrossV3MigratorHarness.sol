// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {AcrossV3Migrator} from "../src/AcrossV3Migrator.sol";

contract AcrossV3MigratorHarness is AcrossV3Migrator {
    constructor(address _nonfungiblePositionManager, address _spokePool, address _swapRouter)
        AcrossV3Migrator(_nonfungiblePositionManager, _spokePool, _swapRouter)
    {}

    function exposed_migrate(address from, uint256 tokenId, bytes memory data) public {
        _migrate(from, tokenId, data);
    }

    function onERC721Received(address, address, uint256, bytes memory) external virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // add this to be excluded from coverage report
    function test() public {}
}
