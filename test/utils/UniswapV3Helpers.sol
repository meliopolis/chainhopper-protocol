// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {INonfungiblePositionManager} from "../../src/interfaces/external/INonfungiblePositionManager.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

contract UniswapV3Helpers is Test {
    function mintV3Position(
        address nftPositionManager,
        address user,
        address token0,
        address token1,
        int24 tickLower,
        int24 tickUpper,
        uint24 fee
    ) public returns (uint256) {
        // give user eth and usdc
        deal(token0, user, 10_000_000_000_000_000_000_000);
        deal(token1, user, 10_000_000_000_000_000_000_000);
        // mint v3 position
        vm.prank(user);
        IERC20(token0).approve(nftPositionManager, 1_000_000_000_000_000_000_000);
        vm.prank(user);
        IERC20(token1).approve(nftPositionManager, 1000_000_000);

        vm.prank(user);
        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: 1_000_000_000_000_000_000_000,
            amount1Desired: 1000_000_000,
            amount0Min: 0,
            amount1Min: 0,
            recipient: user,
            deadline: block.timestamp
        });
        (uint256 tokenId,,,) = INonfungiblePositionManager(nftPositionManager).mint(mintParams);
        // return position id
        return tokenId;
    }

    function withdrawLiquidity(address nftPositionManager, address user, uint256 tokenId) public {
        (,,,,,,, uint128 liquidity,,,,) = INonfungiblePositionManager(nftPositionManager).positions(tokenId);
        vm.prank(user);
        INonfungiblePositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = INonfungiblePositionManager
            .DecreaseLiquidityParams({
            tokenId: tokenId,
            liquidity: liquidity,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });
        INonfungiblePositionManager(nftPositionManager).decreaseLiquidity(decreaseLiquidityParams);
    }

    // add this to be excluded from coverage report
    function test() public virtual {}
}
