// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {AcrossV3Migrator} from "../src/AcrossV3Migrator.sol";

/* Example command to run the script:
forge script script/AcrossV3MigratorDeploy.s.sol:AcrossV3MigratorDeployScript \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --etherscan-api-key $MAINNET_ETHERSCAN_API_KEY \
    -vvvvv \
    --slow \
    --verify \
    --sig 'run(address,address,address)' \
    $SEPOLIA_NFT_POSITION_MANAGER $SEPOLIA_SWAP_ROUTER $SEPOLIA_SPOKE_POOL

forge script script/AcrossV3MigratorDeploy.s.sol:AcrossV3MigratorDeployScript \
    --rpc-url $ARBITRUM_MAINNET_RPC_URL \
    --private-key $PRIVATE_KEY \
    --etherscan-api-key $ARBITRUM_ETHERSCAN_API_KEY \
    -vvvvv \
    --slow \
    --verify \
    --sig 'run(address,address,address)' \
    $ARBITRUM_NFT_POSITION_MANAGER $ARBITRUM_SWAP_ROUTER $ARBITRUM_SPOKE_POOL

forge script script/AcrossV3MigratorDeploy.s.sol:AcrossV3MigratorDeployScript \
    --rpc-url $BASE_MAINNET_RPC_URL \
    --private-key $PRIVATE_KEY \
    --etherscan-api-key $BASE_ETHERSCAN_API_KEY \
    -vvvvv \
    --slow \
    --verify \
    --sig 'run(address,address,address)' \
    $BASE_NFT_POSITION_MANAGER $BASE_SWAP_ROUTER $BASE_SPOKE_POOL
*/

contract AcrossV3MigratorDeployScript is Script {
    function run(address nftPositionManager, address swapRouter, address spokePool) public {
        vm.startBroadcast(vm.envAddress("PUBLIC_KEY"));
        AcrossV3Migrator migrator = new AcrossV3Migrator(nftPositionManager, swapRouter, spokePool);
        console.log("AcrossV3Migrator deployed at:", address(migrator));
        vm.stopBroadcast();
    }

    // add this to be excluded from coverage report
    function test() public {}
}
