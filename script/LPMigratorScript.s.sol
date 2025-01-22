// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {LPMigratorSingleToken} from "../src/LPMigratorSingleToken.sol";
import {ISwapRouter} from "../src/interfaces/external/ISwapRouter.sol";
import {IWETH} from "../src/interfaces/external/IWETH.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {INonfungiblePositionManager} from "../src/interfaces/external/INonfungiblePositionManager.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILPMigrationHandler} from "../src/interfaces/ILPMigrationHandler.sol";

// Not meant to run directly. Contains helper functions to be used in other scripts.
abstract contract LPMigratorScript is Script {
    using SafeERC20 for IERC20;

    // creates an LP position and returns the tokenId
    function createLPPosition(
        address publicKey,
        address swapRouter,
        address nftPositionManager,
        address baseToken,
        address otherToken
    ) public returns (uint256) {
        vm.startBroadcast(publicKey);
        uint256 amountToken1 = 1 ether;
        // wrap one ETH
        IWETH(baseToken).deposit{value: amountToken1}();
        uint256 baseTokenBalancePre = IERC20(baseToken).balanceOf(publicKey);
        // get the balance of the other token
        // uint256 otherTokenBalancePre = IERC20(otherToken).balanceOf(publicKey);

        // approve swap router to use weth
        IERC20(baseToken).approve(swapRouter, baseTokenBalancePre * 1000);
        // takes weth, trades it for some USDC
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: baseToken,
            tokenOut: otherToken,
            fee: 500,
            recipient: publicKey,
            amountIn: 1000000000000000,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        // mainnet {"tokenIn":"0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", "tokenOut":"0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48","fee":"500", "recipient":"0x4bD047CA72fa05F0B89ad08FE5Ba5ccdC07DFFBF","amountIn":"1000000000000000"}
        // base {"tokenIn":"0x4200000000000000000000000000000000000006", "tokenOut":"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913","fee":"500", "recipient":"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266","amountIn":"1000000000000000"}
        uint256 amountOut = ISwapRouter(swapRouter).exactInputSingle(params);
        // verify the trade
        uint256 otherTokenBalancePost = IERC20(otherToken).balanceOf(publicKey);

        // need to approve the nonfungible position manager to use the other token
        IERC20(otherToken).approve(nftPositionManager, otherTokenBalancePost * 1000);
        IERC20(baseToken).approve(nftPositionManager, baseTokenBalancePre * 1000);

        // create an LP position
        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams({
            token0: baseToken,
            token1: otherToken,
            fee: 500,
            tickLower: -800000,
            tickUpper: 800000,
            amount0Desired: 1000000000000000,
            amount1Desired: amountOut,
            amount0Min: 0,
            amount1Min: 0,
            recipient: publicKey,
            deadline: block.timestamp + 6000000000
        });
        (uint256 tokenId,,,) = INonfungiblePositionManager(nftPositionManager).mint(mintParams);
        console.log("tokenId created", tokenId);
        vm.stopBroadcast();
        return tokenId;
    }

    // sends a message to the migrator handler to trigger receiving the token and creating the LP position
    function sendMessageToHandler(
        address migrationHandler,
        address spokePool,
        address publicKey,
        address baseToken,
        address otherToken
    ) public {
        console.log("sending message to handler");
        // first send the token to the Handler contract
        uint256 baseTokenBalancePre = IERC20(baseToken).balanceOf(publicKey);
        console.log("baseTokenBalancePre", baseTokenBalancePre);
        vm.prank(publicKey);
        IERC20(baseToken).safeTransferFrom(publicKey, address(migrationHandler), 1e18);
        // wrap the token
        // IWETH(baseToken).deposit{value: 1 ether}();
        // send the message to the Handler contract
        // first we construct the data
        address token0 = baseToken;
        address token1 = otherToken;
        uint24 fee = 500;
        int24 tickLower = -800000;
        int24 tickUpper = 800000;
        uint256 amount0Min = 1_000_000_000_000_000;
        uint256 amount1Min = 1_000_000_000_000_000;
        address recipient = publicKey;
        bytes memory data = abi.encode(token0, token1, fee, tickLower, tickUpper, amount0Min, amount1Min, recipient);
        vm.prank(spokePool);
        ILPMigrationHandler(migrationHandler).handleV3AcrossMessage(baseToken, 1 ether, publicKey, data);
    }

    // sends a message to the migrator handler to trigger receiving the token and creating the LP position
    function sendPreEncodedMessageToHandler(
        address migrationHandler,
        address spokePool,
        address publicKey,
        address baseToken,
        bytes memory data
    ) public {
        console.log("sending message to handler");
        // first send the token to the Handler contract
        uint256 baseTokenBalancePre = IERC20(baseToken).balanceOf(publicKey);
        console.log("baseTokenBalancePre", baseTokenBalancePre);
        vm.prank(publicKey);
        IERC20(baseToken).safeTransferFrom(publicKey, address(migrationHandler), 1e18);
        vm.prank(spokePool);
        ILPMigrationHandler(migrationHandler).handleV3AcrossMessage(baseToken, 1 ether, publicKey, data);
    }
}

/*

{
"tokenIn": "0x4200000000000000000000000000000000000006",
"tokenOut": "0x4200000000000000000000000000000000000006",
"fee": 500,
"recipient": "0x0E028A7813DB6AAD0df7A50Fde525EA7B8B2160f",
"amountIn": "999000000000000000",
"amountOutMinimum": 0,
"sqrtPriceLimitX96": 0
}
*/
