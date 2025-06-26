// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IAerodromeMigrator} from "../../src/interfaces/IAerodromeMigrator.sol";
import {TestContext} from "../utils/TestContext.sol";
import {MockAerodromeMigrator} from "../mocks/MockAerodromeMigrator.sol";
import {AerodromeHelpers} from "../utils/AerodromeHelpers.sol";
import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/token/ERC721/IERC721Receiver.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IAerodromeNonfungiblePositionManager} from "../../src/interfaces/external/IAerodromeNonfungiblePositionManager.sol";

contract AerodromeMigratorTest is TestContext, AerodromeHelpers {
    string public constant SRC_CHAIN_NAME = "BASE";
    string public constant DEST_CHAIN_NAME = "";

    MockAerodromeMigrator migrator;
    address private aerodromePositionManager;
    int24 private tickSpacing = 100; // Default tick spacing for Aerodrome
    uint160 private sqrtPriceX96 = 79228162514264337593543950336; // 1:1 price ratio

    function setUp() public {
        _loadChain(SRC_CHAIN_NAME, DEST_CHAIN_NAME);

        // Set up Aerodrome position manager
        aerodromePositionManager = vm.envAddress(string(abi.encodePacked(SRC_CHAIN_NAME, "_AERODROME_POSITION_MANAGER")));

        migrator = new MockAerodromeMigrator(
            owner, 
            aerodromePositionManager, 
            address(universalRouter), 
            address(permit2)
        );
    }

    function test_onERC721Received_fails_ifNotPositionManager() public {
        vm.expectRevert(IAerodromeMigrator.NotAerodromePositionManager.selector);

        vm.prank(user);
        migrator.onERC721Received(address(0), address(0), 0, "");
    }

    function test_fuzz_onERC721Received(address from, uint256 tokenId, bytes memory data) public {
        vm.prank(aerodromePositionManager);
        bytes4 selector = migrator.onERC721Received(address(0), from, tokenId, data);
        assertEq(selector, IERC721Receiver.onERC721Received.selector);
    }

    function test_liquidate() public {
        (uint256 positionId,,) = mintAerodromePosition(
            aerodromePositionManager, 
            user, 
            weth, 
            usdc, 
            -300000, 
            200000, 
            tickSpacing,
            0
        );
        vm.prank(user);
        IERC721(aerodromePositionManager).approve(address(migrator), positionId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IAerodromeNonfungiblePositionManager.DecreaseLiquidity(positionId, 0, 0, 0);

        // collect
        vm.expectEmit(true, false, false, false);
        emit IAerodromeNonfungiblePositionManager.Collect(positionId, address(0), 0, 0);

        migrator.liquidate(positionId);
    }

    function test_fuzz_swap(bool zeroForOne) public {
        (address token0, address token1) = weth < usdc ? (weth, usdc) : (usdc, weth);
        address token = zeroForOne ? token0 : token1;
        deal(token, address(migrator), 1 ether);

        bytes memory poolInfo = abi.encode(token0, token1, tickSpacing);

        uint256 amountOut = migrator.swap(poolInfo, zeroForOne, 1 ether);

        assertEq(IERC20(token).balanceOf(address(migrator)), 0);
        assertGt(amountOut, 0);
    }

    function test_liquidate_returnsCorrectPoolInfo() public {
        (uint256 positionId,,) = mintAerodromePosition(
            aerodromePositionManager, 
            user, 
            weth, 
            usdc, 
            -300000, 
            200000, 
            tickSpacing,
            0
        );
        vm.prank(user);
        IERC721(aerodromePositionManager).approve(address(migrator), positionId);

        (address token0, address token1, uint256 amount0, uint256 amount1, bytes memory poolInfo) = migrator.liquidate(positionId);

        assertEq(token0, weth < usdc ? weth : usdc, "Token0 should match");
        assertEq(token1, weth < usdc ? usdc : weth, "Token1 should match");
        assertGt(amount0, 0, "Amount0 should be greater than 0");
        assertGt(amount1, 0, "Amount1 should be greater than 0");
        
        // Decode pool info
        (address poolToken0, address poolToken1, int24 poolTickSpacing) = abi.decode(poolInfo, (address, address, int24));
        assertEq(poolToken0, token0, "Pool token0 should match");
        assertEq(poolToken1, token1, "Pool token1 should match");
        assertEq(poolTickSpacing, tickSpacing, "Pool tick spacing should match");
    }

    function test_swap_differentDirections() public {
        (address token0, address token1) = weth < usdc ? (weth, usdc) : (usdc, weth);
        
        // Test swap in both directions
        deal(token0, address(migrator), 2 ether);
        deal(token1, address(migrator), 2 ether);

        bytes memory poolInfo = abi.encode(token0, token1, tickSpacing);

        uint256 amountOut1 = migrator.swap(poolInfo, true, 1 ether);  // token0 -> token1
        uint256 amountOut2 = migrator.swap(poolInfo, false, 1 ether); // token1 -> token0

        assertGt(amountOut1, 0, "Amount out from token0 to token1 should be greater than 0");
        assertGt(amountOut2, 0, "Amount out from token1 to token0 should be greater than 0");
    }

    function test_swap_differentAmounts() public {
        (address token0, address token1) = weth < usdc ? (weth, usdc) : (usdc, weth);
        address token = token0;
        
        deal(token, address(migrator), 10 ether);

        bytes memory poolInfo = abi.encode(token0, token1, tickSpacing);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 0.1 ether;  // Small amount
        amounts[1] = 1 ether;    // Medium amount
        amounts[2] = 5 ether;    // Large amount

        for (uint i = 0; i < amounts.length; i++) {
            uint256 amountOut = migrator.swap(poolInfo, true, amounts[i]);
            assertGt(amountOut, 0, "Amount out should be greater than 0");
        }
    }

    function test() public virtual override(AerodromeHelpers, TestContext) {}
} 