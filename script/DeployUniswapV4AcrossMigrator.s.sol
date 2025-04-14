// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "@forge-std/Script.sol";
import {UniswapV4AcrossMigrator} from "../src/UniswapV4AcrossMigrator.sol";

/*
    forge script script/DeployUniswapV4AcrossMigrator.s.sol:DeployUniswapV4AcrossMigrator \
    --rpc-url <rpc_endpoints> \
    --etherscan-api-key <etherscan_api_key> \
    --broadcast \
    --verify \
    --sig 'run(string,address,string)' <ENV> <initialOwner> <file>
*/

contract DeployUniswapV4AcrossMigrator is Script {
    function run(string memory env, address initialOwner, string memory file) public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        UniswapV4AcrossMigrator migrator = new UniswapV4AcrossMigrator(
            initialOwner,
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_V4_POSITION_MANAGER"))),
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_UNIVERSAL_ROUTER"))),
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_PERMIT2"))),
            vm.envAddress(string(abi.encodePacked(env, "_ACROSS_SPOKE_POOL"))),
            vm.envAddress(string(abi.encodePacked(env, "_WETH")))
        );

        bytes memory fileContent = vm.readFileBinary(file);
        uint256 count = fileContent.length / 64;
        uint32[] memory chainIds = new uint32[](count);
        address[] memory chainSettlers = new address[](count);
        bool[] memory values = new bool[](count);

        for (uint256 i = 0; i < fileContent.length; i += 64) {
            bytes memory chunk = new bytes(64);
            for (uint256 j = 0; j < 64; j++) {
                chunk[j] = fileContent[i + j];
            }

            (uint32 chainId, address settler) = abi.decode(chunk, (uint32, address));
            chainIds[i / 64] = chainId;
            chainSettlers[i / 64] = settler;
            values[i / 64] = true;
        }
        migrator.setChainSettlers(chainIds, chainSettlers, values);

        console.log("UniswapV4AcrossMigrator deployed at:", address(migrator));

        vm.stopBroadcast();
    }

    // add this to be excluded from coverage report
    function test() public {}
}
