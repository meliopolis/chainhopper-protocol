// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {DualTokensV3Settler} from "../src/DualTokensV3Settler.sol";

/*
forge script script/DeployDualTokensV3Settler.s.sol:DeployDualTokensV3Settler \
    --sig "run(string)" {CHAIN_NAME} \
    --rpc-url {CHAIN_RPC_URL} \
    --broadcast \
    --via-ir \
    --slow \
    --verify \
    --etherscan-api-key {ETHERSCAN_API_KEY}
*/

contract DeployDualTokensV3Settler is Script {
    function run(string memory chain) public {
        address deployer = vm.envAddress("PUBLIC_KEY");
        address positionManager = vm.envAddress(string(abi.encodePacked(chain, "_NFT_POSITION_MANAGER")));
        address spokePool = vm.envAddress(string(abi.encodePacked(chain, "_SPOKE_POOL")));

        console.log("Deploying DualTokensV3Settler on", chain, "using", deployer);
        console.log("  -- PositionManager: ", positionManager);
        console.log("  -- SpokePool: ", spokePool);
        vm.startBroadcast(deployer);

        try new DualTokensV3Settler(positionManager, spokePool) returns (DualTokensV3Settler settler) {
            console.log("DualTokensV3Settler deployed at: ", address(settler));
        } catch {
            console.log("Failed to deploy DualTokensV3Settler");
        }

        vm.stopBroadcast();
        console.log();
    }
}
