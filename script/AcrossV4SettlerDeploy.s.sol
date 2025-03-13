// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {AcrossV4Settler} from "../src/AcrossV4Settler.sol";

/* Example command to run the script:
// deploy on arbitrum sepolia
forge script script/AcrossV4SettlerDeploy.s.sol:AcrossV4SettlerDeployScript \
    --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --etherscan-api-key $ARBITRUM_ETHERSCAN_API_KEY \
    -vvvvv \
    --slow \
    --verify \
    --broadcast \
    --sig 'run(address,address,uint24,uint8,address,address,address,address)' \
    $ARBITRUM_SEPOLIA_SPOKE_POOL $PUBLIC_KEY 10 20 $ARBITRUM_SEPOLIA_UNIVERSAL_ROUTER $ARBITRUM_SEPOLIA_V4_POSITION_MANAGER $ARBITRUM_SEPOLIA_WETH $ARBITRUM_SEPOLIA_PERMIT2

// deploy on baseSepolia
forge script script/AcrossV4SettlerDeploy.s.sol:AcrossV4SettlerDeployScript \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --etherscan-api-key $BASE_ETHERSCAN_API_KEY \
    -vvvvv \
    --slow \
    --verify \
    --broadcast \
    --sig 'run(address,address,uint24,uint8,address,address,address,address)' \
    $BASE_SEPOLIA_SPOKE_POOL $PUBLIC_KEY 10 20 $BASE_SEPOLIA_UNIVERSAL_ROUTER $BASE_SEPOLIA_V4_POSITION_MANAGER $BASE_SEPOLIA_WETH $BASE_SEPOLIA_PERMIT2

// deploy on base mainnet (note broadcast is missing from the command intentionally)
forge script script/AcrossV4SettlerDeploy.s.sol:AcrossV4SettlerDeployScript \
    --rpc-url $BASE_MAINNET_RPC_URL \
    --private-key $PRIVATE_KEY \
    --etherscan-api-key $BASE_ETHERSCAN_API_KEY \
    -vvvvv \
    --slow \
    --verify \
    --sig 'run(address,address,uint24,uint8,address,address,address,address)' \
    $BASE_SPOKE_POOL $PUBLIC_KEY 10 20 $BASE_UNIVERSAL_ROUTER $BASE_V4_POSITION_MANAGER $BASE_WETH $BASE_PERMIT2

// deploy on arbitrum mainnet (note broadcast is missing from the command intentionally)
forge script script/AcrossV4SettlerDeploy.s.sol:AcrossV4SettlerDeployScript \
    --rpc-url $ARBITRUM_MAINNET_RPC_URL \
    --private-key $PRIVATE_KEY \
    --etherscan-api-key $ARBITRUM_ETHERSCAN_API_KEY \
    -vvvvv \
    --slow \
    --verify \
    --verifier-url $ARBITRUM_ETHERSCAN_API_URL \
    --sig 'run(address,address,uint24,uint8,address,address,address,address)' \
    $ARBITRUM_SPOKE_POOL $PUBLIC_KEY 10 20 $ARBITRUM_UNIVERSAL_ROUTER $ARBITRUM_V4_POSITION_MANAGER $ARBITRUM_WETH $ARBITRUM_PERMIT2

// deploy on unichain (note broadcast is missing from the command intentionally)
forge script script/AcrossV4SettlerDeploy.s.sol:AcrossV4SettlerDeployScript \
    --rpc-url $UNICHAIN_MAINNET_RPC_URL \
    --private-key $PRIVATE_KEY \
    --verifier-url $UNICHAIN_ETHERSCAN_API_URL \
    --verifier-api-key $UNICHAIN_ETHERSCAN_API_KEY \
    -vvvvv \
    --slow \
    --verify \
    --sig 'run(address,address,uint24,uint8,address,address,address,address)' \
    $UNICHAIN_SPOKE_POOL $PUBLIC_KEY 10 20 $UNICHAIN_UNIVERSAL_ROUTER $UNICHAIN_V4_POSITION_MANAGER $UNICHAIN_WETH $UNICHAIN_PERMIT2
*/

contract AcrossV4SettlerDeployScript is Script {
    function run(
        address spokePool,
        address protocolFeeRecipient,
        uint24 protocolFeeBps,
        uint8 protocolShareOfSenderFeeInPercent,
        address swapRouter,
        address positionManager,
        address weth,
        address permit2
    ) public {
        vm.startBroadcast(vm.envAddress("PUBLIC_KEY"));
        AcrossV4Settler settler = new AcrossV4Settler(
            spokePool,
            protocolFeeRecipient,
            protocolFeeBps,
            protocolShareOfSenderFeeInPercent,
            swapRouter,
            positionManager,
            weth,
            permit2
        );
        console.log("AcrossV4Settler deployed at:", address(settler));
        vm.stopBroadcast();
    }

    // add this to be excluded from coverage report
    function test() public {}
}
