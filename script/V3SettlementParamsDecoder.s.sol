// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console.sol";

import {IV3Settler} from "../src/interfaces/IV3Settler.sol";

contract V3SettlementParamsDecoderScript is Script {
    bytes settleMessageFromMigrator =
        hex"00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000140000000000000000000000000DD1D28E5BEDBD000A0539A3BF0ED558F4B721A840000000000000000000000004200000000000000000000000000000000000006000000000000000000000000833589FCD6EDB6E08F4C7C32D4F71B54BDA0291300000000000000000000000000000000000000000000000000000000000001F4FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFCFA40FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFD15520000000000000000000000000000000000000000000000000067655D9DA5DDA00000000000000000000000000000000000000000000000000000000000B4885900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
    bytes settleMessageInSimulator =
        hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000140000000000000000000000000dd1d28e5bedbd000a0539a3bf0ed558f4b721a840000000000000000000000004200000000000000000000000000000000000006000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda0291300000000000000000000000000000000000000000000000000000000000001f4fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffcfa40fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffd15520000000000000000000000000000000000000000000000000067655d9da5dda00000000000000000000000000000000000000000000000000000000000b4885900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

    function decodeV3SettlementParams(bytes memory message) public {
        (bytes32 migrationId, bytes memory settlementMessage) = abi.decode(message, (bytes32, bytes));
        (IV3Settler.V3SettlementParams memory settlementParams) =
            abi.decode(settlementMessage, (IV3Settler.V3SettlementParams));
        console.logBytes32(migrationId);
        console.log(settlementParams.amount0Min);
        console.log(settlementParams.amount1Min);
        console.log(settlementParams.token0);
        console.log(settlementParams.token1);
    }

    function decodeSettleCall(bytes memory message) public returns (bytes memory) {
        (bytes32 migrationId, bytes memory messageInside) = abi.decode(message, (bytes32, bytes));
        console.logBytes32(migrationId);
        console.logBytes(messageInside);
        (IV3Settler.V3SettlementParams memory settlementParams) =
            abi.decode(messageInside, (IV3Settler.V3SettlementParams));
        console.log(settlementParams.amount0Min);
        console.log(settlementParams.amount1Min);
        console.log(settlementParams.token0);
        console.log(settlementParams.token1);
        return messageInside;
    }

    function decodeMigratorMessageToSettler(bytes memory message) public {
        (bytes32 migrationId, bytes memory messageInside) = abi.decode(message, (bytes32, bytes));
        console.logBytes32(migrationId);
        console.logBytes(messageInside);
        (bytes memory messageInside2) = abi.decode(messageInside, (bytes));
        console.logBytes(messageInside2);
        (IV3Settler.V3SettlementParams memory settlementParams) =
            abi.decode(messageInside2, (IV3Settler.V3SettlementParams));
        console.log(settlementParams.amount0Min);
        console.log(settlementParams.amount1Min);
        console.log(settlementParams.token0);
        console.log(settlementParams.token1);
    }

    function run() public {
        console.log("Simulated");
        try this.decodeSettleCall(settleMessageInSimulator) {
            console.log("Simulated decoded successfully");
        } catch (bytes memory reason) {
            console.log("Simulated decoding failed");
        }
        console.log("\nActual");
        try this.decodeSettleCall(settleMessageFromMigrator) {
            console.log("Migrator decoded successfully");
        } catch (bytes memory reason) {
            console.log("Actual decoding failed");
        }
        // decodeV3SettlementParams(settleMessage);
        decodeMigratorMessageToSettler(settleMessageFromMigrator);
    }

    function test() public {}
}
