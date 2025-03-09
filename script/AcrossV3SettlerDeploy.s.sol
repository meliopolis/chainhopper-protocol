// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "@forge-std/Script.sol";
import {AcrossV3Settler} from "../src/AcrossV3Settler.sol";

/* Example command to run the script:
// deploy on arbitrum sepolia
forge script script/AcrossV3SettlerDeploy.s.sol:AcrossV3SettlerDeployScript \
    --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --etherscan-api-key $ARBITRUM_ETHERSCAN_API_KEY \
    -vvvvv \
    --slow \
    --verify \
    --broadcast \
    --sig 'run(address,address,uint24,uint8,address,address)' \
    $ARBITRUM_SEPOLIA_SPOKE_POOL $PUBLIC_KEY 10 20 $ARBITRUM_SEPOLIA_SWAP_ROUTER $ARBITRUM_SEPOLIA_NFT_POSITION_MANAGER

// deploy on baseSepolia
forge script script/AcrossV3SettlerDeploy.s.sol:AcrossV3SettlerDeployScript \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --etherscan-api-key $BASE_ETHERSCAN_API_KEY \
    -vvvvv \
    --slow \
    --verify \
    --broadcast \
    --sig 'run(address,address,uint24,uint8,address,address)' \
    $BASE_SEPOLIA_SPOKE_POOL $PUBLIC_KEY 10 20 $BASE_SEPOLIA_SWAP_ROUTER $BASE_SEPOLIA_NFT_POSITION_MANAGER

// deploy on base mainnet (note broadcast is missing from the command intentionally)
forge script script/AcrossV3SettlerDeploy.s.sol:AcrossV3SettlerDeployScript \
    --rpc-url $BASE_MAINNET_RPC_URL \
    --private-key $PRIVATE_KEY \
    --etherscan-api-key $BASE_ETHERSCAN_API_KEY \
    -vvvvv \
    --slow \
    --verify \
    --sig 'run(address,address,uint24,uint8,address,address)' \
    $BASE_SPOKE_POOL $PUBLIC_KEY 10 20 $BASE_SWAP_ROUTER $BASE_NFT_POSITION_MANAGER

// deploy on arbitrum mainnet (note broadcast is missing from the command intentionally)
forge script script/AcrossV3SettlerDeploy.s.sol:AcrossV3SettlerDeployScript \
    --rpc-url $ARBITRUM_MAINNET_RPC_URL \
    --private-key $PRIVATE_KEY \
    --etherscan-api-key $ARBITRUM_ETHERSCAN_API_KEY \
    -vvvvv \
    --slow \
    --verify \
    --verifier-url $ARBITRUM_ETHERSCAN_API_URL \
    --sig 'run(address,address,uint24,uint8,address,address)' \
    $ARBITRUM_SPOKE_POOL $PUBLIC_KEY 10 20 $ARBITRUM_SWAP_ROUTER $ARBITRUM_NFT_POSITION_MANAGER

// deploy on unichain (note broadcast is missing from the command intentionally)
forge script script/AcrossV3SettlerDeploy.s.sol:AcrossV3SettlerDeployScript \
    --rpc-url $UNICHAIN_MAINNET_RPC_URL \
    --private-key $PRIVATE_KEY \
    --verifier-url $UNICHAIN_ETHERSCAN_API_URL \
    --verifier-api-key $UNICHAIN_ETHERSCAN_API_KEY \
    -vvvvv \
    --slow \
    --verify \
    --sig 'run(address,address,uint24,uint8,address,address)' \
    $UNICHAIN_SPOKE_POOL $PUBLIC_KEY 10 20 $UNICHAIN_SWAP_ROUTER $UNICHAIN_NFT_POSITION_MANAGER
*/

contract AcrossV3SettlerDeployScript is Script {
    function run(
        address spokePool,
        address protocolFeeRecipient,
        uint24 protocolFeeBps,
        uint8 protocolShareOfSenderFeeInPercent,
        address swapRouter,
        address positionManager
    ) public {
        vm.startBroadcast(vm.envAddress("PUBLIC_KEY"));
        AcrossV3Settler settler = new AcrossV3Settler(
            spokePool,
            protocolFeeRecipient,
            protocolFeeBps,
            protocolShareOfSenderFeeInPercent,
            swapRouter,
            positionManager
        );
        console.log("AcrossV3Settler deployed at:", address(settler));
        vm.stopBroadcast();
    }

    // add this to be excluded from coverage report
    function test() public {}
}
