// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Vm, console} from "forge-std/Test.sol";

library AcrossHelpers {
    error LogNotFound();

    function findFundsDepositedEvent(Vm.Log[] memory logs) public view returns (Vm.Log memory) {
        Vm.Log[] memory events = findFundsDepositedEvents(logs);
        if (events.length == 0) {
            revert LogNotFound();
        }
        return events[0];
    }

    function findFundsDepositedEvents(Vm.Log[] memory logs) public view returns (Vm.Log[] memory) {
        bytes32 topic0 = keccak256(
            "FundsDeposited(bytes32,bytes32,uint256,uint256,uint256,uint256,uint32,uint32,uint32,bytes32,bytes32,bytes32,bytes)"
        );
        Vm.Log[] memory events = new Vm.Log[](2); // never expect more than 2 events
        uint256 eventIndex = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            // skip events emitted by this contract
            if (logs[i].topics[0] == topic0 && logs[i].emitter != address(this)) {
                events[eventIndex] = logs[i];
                eventIndex++;
            }
        }
        return events;
    }

    function parseFundsDepositedEvent(bytes memory data)
        public
        pure
        returns (
            bytes32 inputToken,
            bytes32 outputToken,
            uint256 inputAmount,
            uint256 outputAmount,
            bytes memory message
        )
    {
        (inputToken, outputToken, inputAmount, outputAmount,,,,,, message) =
            abi.decode(data, (bytes32, bytes32, uint256, uint256, uint32, uint32, uint32, bytes32, bytes32, bytes));
    }
}
