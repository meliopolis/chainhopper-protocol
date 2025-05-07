// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IAcrossSettler} from "../../src/interfaces/IAcrossSettler.sol";
import {ISettler} from "../../src/interfaces/ISettler.sol";
import {MigrationData} from "../../src/types/MigrationData.sol";
import {IAcrossSettler} from "../../src/interfaces/IAcrossSettler.sol";
import {MigrationModes} from "../../src/types/MigrationMode.sol";
import {MockAcrossSettler} from "../mocks/MockAcrossSettler.sol";
import {TestContext} from "../utils/TestContext.sol";

contract AcrossSettlerTest is TestContext {
    string public constant SRC_CHAIN_NAME = "BASE";
    string public constant DEST_CHAIN_NAME = "";

    MockAcrossSettler private settler;

    function setUp() public {
        _loadChain(SRC_CHAIN_NAME, DEST_CHAIN_NAME);

        settler = new MockAcrossSettler(owner, address(acrossSpokePool));
    }

    function test_handleV3AcrossMessage_fails_ifNotSpokePool() public {
        vm.expectRevert(IAcrossSettler.NotSpokePool.selector, address(settler));

        vm.prank(user);
        settler.handleV3AcrossMessage(address(0), 0, address(0), "");
    }

    function test_fuzz_handleV3AcrossMessage(
        bool hasSettlementCache,
        bool shouldSelfSettleRevert,
        bool shouldHandleMessageRevert
    ) public {
        ISettler.SettlementParams memory settlementParams = ISettler.SettlementParams(user, 0, address(0), "");
        MigrationData memory migrationData =
            MigrationData(block.chainid, address(0), 1, MigrationModes.DUAL, "", abi.encode(settlementParams));
        bytes memory data = abi.encode(migrationData.toHash(), migrationData);

        if (shouldSelfSettleRevert) {
            if (shouldHandleMessageRevert) {
                settler.setErrorSelector(ISettler.InvalidMigration.selector);

                vm.expectRevert();
            } else {
                deal(weth, address(settler), 100);
                settler.setErrorSelector(bytes4(uint32(1)));

                vm.expectEmit(true, true, true, true, weth);
                emit IERC20.Transfer(address(settler), user, 100);

                if (hasSettlementCache) {
                    vm.expectEmit(true, true, true, true, address(settler));
                    emit MockAcrossSettler.Log("refund");
                }
            }
        } else {
            vm.expectEmit(true, false, false, false);
            emit IAcrossSettler.Receipt(migrationData.toHash(), address(2), weth, 100);
        }

        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(weth, 100, address(0), data);
    }
}
