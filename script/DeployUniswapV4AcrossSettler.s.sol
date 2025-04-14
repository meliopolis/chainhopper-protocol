// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "@forge-std/Script.sol";
import {UniswapV4AcrossSettler} from "../src/UniswapV4AcrossSettler.sol";

/*
    forge script script/DeployUniswapV4AcrossSettler.s.sol:DeployUniswapV4AcrossSettler \
    --rpc-url <rpc_endpoints> \
    --etherscan-api-key <etherscan_api_key> \
    --broadcast \
    --verify \
    --sig 'run(string,address,string)' <ENV> <initialOwner> <file>
*/

contract DeployUniswapV4AcrossSettler is Script {
    function run(string memory env, address initialOwner, string memory file) public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        UniswapV4AcrossSettler settler = new UniswapV4AcrossSettler(
            initialOwner,
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_V4_POSITION_MANAGER"))),
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_UNIVERSAL_ROUTER"))),
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_PERMIT2"))),
            vm.envAddress(string(abi.encodePacked(env, "_ACROSS_SPOKE_POOL"))),
            vm.envAddress(string(abi.encodePacked(env, "_WETH")))
        );

        settler.setProtocolShareBps(uint16(vm.envUint("DEPLOY_PROTOCOL_SHARE_BPS")));
        settler.setProtocolShareOfSenderFeePct(uint8(vm.envUint("DEPLOY_PROTOCOL_SHARE_OF_SENDER_FEE_PCT")));
        settler.setProtocolFeeRecipient(vm.envAddress("DEPLOY_PROTOCOL_FEE_RECIPIENT"));

        bytes memory fileContent = vm.readFileBinary(file);
        bytes memory newContent = abi.encode(block.chainid, address(settler));
        vm.writeFileBinary(file, bytes.concat(fileContent, newContent));

        console.log("UniswapV4AcrossSettler deployed at:", address(settler));

        vm.stopBroadcast();
    }

    // add this to be excluded from coverage report
    function test() public {}
}
