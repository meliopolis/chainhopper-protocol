// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {LPMigratorSingleToken} from "../src/LPMigratorSingleToken.sol";

/* Example command to run the script:
forge script script/LPMigratorSingleTokenDeploy.s.sol:LPMigratorSingleTokenDeployScript \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --etherscan-api-key $MAINNET_ETHERSCAN_API_KEY \
    -vvvvv \
    --slow \
    --verify \
    --sig 'run(address,address,address,address)' \
    $SEPOLIA_NFT_POSITION_MANAGER $SEPOLIA_WETH $SEPOLIA_SWAP_ROUTER $SEPOLIA_SPOKE_POOL

forge script script/LPMigratorSingleTokenDeploy.s.sol:LPMigratorSingleTokenDeployScript \
    --rpc-url $ARBITRUM_MAINNET_RPC_URL \
    --private-key $PRIVATE_KEY \
    --etherscan-api-key $ARBITRUM_ETHERSCAN_API_KEY \
    -vvvvv \
    --slow \
    --verify \
    --sig 'run(address,address,address,address)' \
    $ARBITRUM_NFT_POSITION_MANAGER $ARBITRUM_WETH $ARBITRUM_SWAP_ROUTER $ARBITRUM_SPOKE_POOL

forge script script/LPMigratorSingleTokenDeploy.s.sol:LPMigratorSingleTokenDeployScript \
    --rpc-url $BASE_MAINNET_RPC_URL \
    --private-key $PRIVATE_KEY \
    --etherscan-api-key $BASE_ETHERSCAN_API_KEY \
    -vvvvv \
    --slow \
    --verify \
    --sig 'run(address,address,address,address)' \
    $BASE_NFT_POSITION_MANAGER $BASE_WETH $BASE_SWAP_ROUTER $BASE_SPOKE_POOL
*/

contract LPMigratorSingleTokenDeployScript is Script {
    function run(
        address nftPositionManager,
        address weth,
        address swapRouter,
        address spokePool
    ) public {
        vm.startBroadcast(vm.envAddress("PUBLIC_KEY"));
        LPMigratorSingleToken migrator = new LPMigratorSingleToken(
            nftPositionManager,
            weth,
            swapRouter,
            spokePool
        );
        console.log("LPMigrationSingleToken deployed at:", address(migrator));
        vm.stopBroadcast();
    }
}
