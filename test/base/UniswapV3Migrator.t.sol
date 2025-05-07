// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IUniswapV3Migrator} from "../../src/interfaces/IUniswapV3Migrator.sol";
import {TestContext} from "../utils/TestContext.sol";
import {MockUniswapV3Migrator} from "../mocks/MockUniswapV3Migrator.sol";
import {UniswapV3Helpers} from "../utils/UniswapV3Helpers.sol";
import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/token/ERC721/IERC721Receiver.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {INonfungiblePositionManager} from "../../src/interfaces/external/INonfungiblePositionManager.sol";

contract UniswapV3MigratorTest is TestContext, UniswapV3Helpers {
    string public constant SRC_CHAIN_NAME = "BASE";
    string public constant DEST_CHAIN_NAME = "";

    MockUniswapV3Migrator migrator;

    function setUp() public {
        _loadChain(SRC_CHAIN_NAME, DEST_CHAIN_NAME);

        migrator =
            new MockUniswapV3Migrator(owner, address(v3PositionManager), address(universalRouter), address(permit2));
    }

    function test_onERC721Received_fails_ifNotPositionManager() public {
        vm.expectRevert(IUniswapV3Migrator.NotPositionManager.selector);

        vm.prank(user);
        migrator.onERC721Received(address(0), address(0), 0, "");
    }

    function test_fuzz_onERC721Received(address from, uint256 tokenId, bytes memory data) public {
        vm.prank(address(v3PositionManager));
        bytes4 selector = migrator.onERC721Received(address(0), from, tokenId, data);
        assertEq(selector, IERC721Receiver.onERC721Received.selector);
    }

    function test_liquidate() public {
        (uint256 positionId,,) = mintV3Position(address(v3PositionManager), user, weth, usdc, -300000, 200000, 500);
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

    function test_fuzz_swap(bool zeroForOne) public {
        (address token0, address token1) = weth < usdc ? (weth, usdc) : (usdc, weth);
        address token = zeroForOne ? token0 : token1;
        deal(token, address(migrator), 1 ether);

        bytes memory poolInfo = abi.encode(token0, token1, 500);

        uint256 amountOut = migrator.swap(poolInfo, zeroForOne, 1 ether);

        assertEq(IERC20(token).balanceOf(address(migrator)), 0);
        assertGt(amountOut, 0);
    }

    function test() public virtual override(UniswapV3Helpers, TestContext) {}
}
