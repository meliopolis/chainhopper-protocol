// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IUniswapV3Migrator} from "../../src/interfaces/IUniswapV3Migrator.sol";
import {TestContext} from "../utils/TestContext.sol";
import {MockUniswapV3Migrator} from "../mocks/MockUniswapV3Migrator.sol";
import {UniswapV3Helpers} from "../utils/UniswapV3Helpers.sol";
import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";
import {INonfungiblePositionManager} from "../../src/interfaces/external/INonfungiblePositionManager.sol";

contract UniswapV3MigratorTest is TestContext, UniswapV3Helpers {
    MockUniswapV3Migrator migrator;

    function setUp() public {
        _loadChain("BASE");

        migrator = new MockUniswapV3Migrator(owner, v3PositionManager, universalRouter, permit2);
    }

    function test_onERC721Received_fails_ifNotPositionManager() public {
        vm.expectRevert(IUniswapV3Migrator.NotPositionManager.selector);

        vm.prank(user);
        migrator.onERC721Received(address(0), address(0), 0, "");
    }

    function test_liquidate() public {
        uint256 positionId = mintV3Position(v3PositionManager, user, weth, usdc, -300000, 200000, 500);
        vm.prank(user);
        IERC721(v3PositionManager).approve(address(migrator), positionId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit INonfungiblePositionManager.DecreaseLiquidity(positionId, 0, 0, 0);

        // collect
        vm.expectEmit(true, false, false, false);
        emit INonfungiblePositionManager.Collect(positionId, address(0), 0, 0);

        migrator.liquidate(positionId);
    }

    function test() public virtual override(UniswapV3Helpers, TestContext) {}
}
