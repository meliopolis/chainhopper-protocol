// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Test.sol";
import {TestContext} from "./TestContext.sol";

contract AcrossHelpers is TestContext {
    error LogNotFound();

    function findFundsDepositedEvent(Vm.Log[] memory logs) public view returns (Vm.Log memory) {
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(acrossSpokePool)) {
                return logs[i];
            }
        }
        revert LogNotFound();
    }

    function parseFundsDepositedEvent(bytes memory data)
        public
        pure
        returns (bytes32 inputToken, bytes32 outputToken, uint256 inputAmount, uint256 outputAmount)
    {
        (inputToken, outputToken, inputAmount, outputAmount) =
        // uint256 destinationChainId,
        // uint256 depositId,
        // uint32 quoteTimestamp,
        // uint32 fillDeadline,
        // uint32 exclusivityDeadline,
        // bytes32 depositor,
        // bytes32 recipient,
        // bytes32 exclusiveRelayer,
        // bytes memory message
         abi.decode(data, (bytes32, bytes32, uint256, uint256));
        // uint256,
        // uint256,
        // uint32,
        // uint32,
        // uint32,
        // bytes32,
        // bytes32,
        // bytes32,
        // bytes
    }
}
