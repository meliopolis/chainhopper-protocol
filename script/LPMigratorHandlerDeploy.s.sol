// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {LPMigrationSingleTokenHandler} from "../src/LPMigrationSingleTokenHandler.sol";

/* Example command to run the script:
// deploy on arbitrum sepolia
forge script script/LPMigratorHandlerDeploy.s.sol:LPMigratorHandlerDeployScript \
    --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --etherscan-api-key $ARBITRUM_ETHERSCAN_API_KEY \
    -vvvvv \
    --slow \
    --verify \
    --broadcast \
    --sig 'run(address,address,address,address)' \
    $ARBITRUM_SEPOLIA_NFT_POSITION_MANAGER $ARBITRUM_SEPOLIA_WETH $ARBITRUM_SEPOLIA_SWAP_ROUTER $ARBITRUM_SEPOLIA_SPOKE_POOL

// deploy on baseSepolia
forge script script/LPMigratorHandlerDeploy.s.sol:LPMigratorHandlerDeployScript \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --etherscan-api-key $BASE_ETHERSCAN_API_KEY \
    -vvvvv \
    --slow \
    --verify \
    --broadcast \
    --sig 'run(address,address,address,address)' \
    $BASE_SEPOLIA_NFT_POSITION_MANAGER $BASE_SEPOLIA_WETH $BASE_SEPOLIA_SWAP_ROUTER $BASE_SEPOLIA_SPOKE_POOL

// deploy on baseVirtualFork
forge script script/LPMigratorHandlerDeploy.s.sol:LPMigratorHandlerDeployScript \
    --rpc-url $BASE_VIRTUAL_RPC_URL \
    --private-key $PRIVATE_KEY \
    -vvvvv \
    --slow \
    --broadcast \
    --sig 'run(address,address,address,address)' \
    $BASE_NFT_POSITION_MANAGER $BASE_WETH $BASE_SWAP_ROUTER $BASE_SPOKE_POOL

// deploy on base mainnet (note broadcast is missing from the command intentionally)
forge script script/LPMigratorHandlerDeploy.s.sol:LPMigratorHandlerDeployScript \
    --rpc-url $BASE_MAINNET_RPC_URL \
    --private-key $PRIVATE_KEY \
    --etherscan-api-key $BASE_ETHERSCAN_API_KEY \
    -vvvvv \
    --slow \
    --verify \
    --sig 'run(address,address,address,address)' \
    $BASE_NFT_POSITION_MANAGER $BASE_WETH $BASE_SWAP_ROUTER $BASE_SPOKE_POOL

// deploy on arbitrum mainnet (note broadcast is missing from the command intentionally)
forge script script/LPMigratorHandlerDeploy.s.sol:LPMigratorHandlerDeployScript \
    --rpc-url $ARBITRUM_MAINNET_RPC_URL \
    --private-key $PRIVATE_KEY \
    --etherscan-api-key $ARBITRUM_ETHERSCAN_API_KEY \
    -vvvvv \
    --slow \
    --verify \
    --verifier-url $ARBITRUM_ETHERSCAN_API_URL \
    --sig 'run(address,address,address,address)' \
    $ARBITRUM_NFT_POSITION_MANAGER $ARBITRUM_WETH $ARBITRUM_SWAP_ROUTER $ARBITRUM_SPOKE_POOL
*/

contract LPMigratorHandlerDeployScript is Script {
    function run(address nftPositionManager, address weth, address swapRouter, address spokePool) public {
        vm.startBroadcast(vm.envAddress("PUBLIC_KEY"));
        LPMigrationSingleTokenHandler migrator =
            new LPMigrationSingleTokenHandler(nftPositionManager, weth, swapRouter, spokePool);
        console.log("LPMigrationSingleTokenHandler deployed at:", address(migrator));
        vm.stopBroadcast();
    }
}
