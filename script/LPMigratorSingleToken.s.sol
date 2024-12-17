// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {LPMigratorSingleToken} from "../src/LPMigratorSingleToken.sol";
import {ISwapRouter} from "../src/interfaces/external/ISwapRouter.sol";
import {IWETH} from "../src/interfaces/external/IWETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {INonfungiblePositionManager} from "../src/interfaces/external/INonfungiblePositionManager.sol";
import {LPMigrationSingleTokenHandler} from "../src/LPMigrationSingleTokenHandler.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LPMigratorScript} from "./LPMigratorScript.s.sol";

// run with:
// forge script LPMigratorSingleTokenScript --rpc-url $BASE_SEPOLIA_VIRTUAL_RPC_URL --private-key $PRIVATE_KEY -vvvvv --slow --via-ir

contract LPMigratorSingleTokenScript is LPMigratorScript {
    using SafeERC20 for IERC20;

    LPMigratorSingleToken public migrator;
    address publicKey = vm.envAddress("PUBLIC_KEY");
    address swapRouter = vm.envAddress("BASE_SEPOLIA_SWAP_ROUTER");
    address nftPositionManager = vm.envAddress("BASE_SEPOLIA_NFT_POSITION_MANAGER");
    address baseToken = vm.envAddress("BASE_SEPOLIA_WETH");
    address otherToken = vm.envAddress("BASE_SEPOLIA_USDC");
    address spokePool = vm.envAddress("BASE_SEPOLIA_SPOKE_POOL");


    function run() public {
        // create the LP position and get the tokenId
        // uint256 tokenId = createLPPosition();

        // vm.startBroadcast(publicKey);

        // // deploys migrator
        // migrator = new LPMigratorSingleToken(nftPositionManager, baseToken, swapRouter, spokePool);

        // // create mintParams
        // uint32 fillDeadlineBuffer = 7000;
        // bytes memory data = abi.encode(
        //     publicKey,
        //     fillDeadlineBuffer,
        //     uint256(100), // fee percentage
        //     address(0), // exclusiveRelayer
        //     uint256(42161), // destinationChainId
        //     "0x"
        // );
        // // move the LP position to the migrator
        // // INonfungiblePositionManager(nftPositionManager).safeTransferFrom(publicKey, address(migrator), tokenId, data);

        LPMigrationSingleTokenHandler migrationHandler =
            new LPMigrationSingleTokenHandler(nftPositionManager, baseToken, swapRouter, spokePool);

        vm.prank(publicKey);
        IWETH(baseToken).deposit{value: 1 ether}();
        this.sendMessageToHandler(address(migrationHandler), spokePool, publicKey, baseToken, otherToken);

        // vm.stopBroadcast();
    }
}

// 0x
// 00000000000000000000000017f5110cd1412047d2a84f8d40c0716bc5cde0cd
// 00000000000000000000000000000000000000000000000000000000675c5ea4
// 0000000000000000000000000000000000000000000000000000000000000bb8
// 0000000000000000000000000000000000000000000000000031e5af166927a5
// 0000000000000000000000000000000000000000000000000000000000000000
// 0000000000000000000000000000000000000000000000000000000000000000
// 0000000000000000000000000000000000000000000000000000000000014a34
// 0x000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001800000000000000000000000004200000000000000000000000000000000000006000000000000000000000000036cbd53842c5426634e7929541ec2318f3dcf7e00000000000000000000000000000000000000000000000000000000000001f400000000000000000000000000000000000000000000000000000000000290b80000000000000000000000000000000000000000000000000000000000029eaa000000000000000000000000000000000000000000000000000000000de8b9a3000000000000000000000000000000000000000000000000001d76e8f68a3792000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004bd047ca72fa05f0b89ad08fe5ba5ccdc07dffbf00000000000000000000000000000000000000000000000000000193c5fd74ae0000000000000000000000000000000000000000000000000000000000001388
