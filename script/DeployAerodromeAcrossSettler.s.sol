// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "@forge-std/Script.sol";
import {AerodromeAcrossSettler} from "../src/AerodromeAcrossSettler.sol";

/*  
    forge script script/DeployAerodromeAcrossSettler.s.sol:DeployAerodromeAcrossSettler \
    --rpc-url <rpc_endpoints> \
    --etherscan-api-key <etherscan_api_key> \
    --broadcast \
    --verify \
    --sig 'run(string,address)' <ENV> <initialOwner>
*/

contract DeployAerodromeAcrossSettler is Script {
    function run(string memory env, address initialOwner) public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        AerodromeAcrossSettler settler = new AerodromeAcrossSettler(
            initialOwner,
            vm.envAddress(string(abi.encodePacked(env, "_AERODROME_POSITION_MANAGER"))),
            vm.envAddress(string(abi.encodePacked(env, "_AERODROME_UNIVERSAL_ROUTER"))),
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_PERMIT2"))),
            vm.envAddress(string(abi.encodePacked(env, "_ACROSS_SPOKE_POOL")))
        );

        // set protocol fee recipient
        address protocolFeeRecipient = vm.envAddress("DEPLOY_PROTOCOL_FEE_RECIPIENT");
        if (protocolFeeRecipient != address(0) && protocolFeeRecipient != initialOwner) {
            settler.setProtocolFeeRecipient(protocolFeeRecipient);
        }

        // set protocol share bps
        uint16 protocolShareBps = uint16(vm.envUint("DEPLOY_PROTOCOL_SHARE_BPS"));
        if (protocolShareBps > 0) {
            settler.setProtocolShareBps(protocolShareBps);
        }
        // set protocol share of sender fee pct
        uint8 protocolShareOfSenderFeePct = uint8(vm.envUint("DEPLOY_PROTOCOL_SHARE_OF_SENDER_FEE_PCT"));
        if (protocolShareOfSenderFeePct > 0) {
            settler.setProtocolShareOfSenderFeePct(protocolShareOfSenderFeePct);
        }

        // set a new owner if needed
        address finalOwner = vm.envAddress("DEPLOY_FINAL_OWNER");
        if (finalOwner != address(0) && finalOwner != initialOwner) {
            settler.transferOwnership(finalOwner);
        }

        console.log("AerodromeAcrossSettler deployed at:", address(settler));

        vm.stopBroadcast();
    }

    // add this to be excluded from coverage report
    function test() public {}
}
