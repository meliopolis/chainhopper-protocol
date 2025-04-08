// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IUniswapV4Migrator} from "../../src/interfaces/IUniswapV4Migrator.sol";
import {TestContext} from "../utils/TestContext.sol";
import {MockUniswapV4Migrator} from "../mocks/MockUniswapV4Migrator.sol";

contract UniswapV4MigratorTest is TestContext {
    MockUniswapV4Migrator migrator;

    function setUp() public {
        _loadChain("BASE");

        migrator = new MockUniswapV4Migrator(owner, v4PositionManager, universalRouter, permit2);
    }

    function test_onERC721Received_fails_ifNotPositionManager() public {
        vm.expectRevert(IUniswapV4Migrator.NotPositionManager.selector);

        vm.prank(user);
        migrator.onERC721Received(address(0), address(0), 0, "");
    }
}
