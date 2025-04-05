// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {Settler} from "../../src/base/Settler.sol";
import {IAcrossSettler} from "../../src/interfaces/IAcrossSettler.sol";
import {ISettler} from "../../src/interfaces/ISettler.sol";
import {MigrationId, MigrationIdLibrary} from "../../src/types/MigrationId.sol";
import {MigrationModes} from "../../src/types/MigrationMode.sol";
import {MockAcrossSettler} from "../mocks/MockAcrossSettler.sol";
import {TestContext} from "../utils/TestContext.sol";

contract AcrossSettlerTest is TestContext {
    string constant CHAIN_NAME = "BASE";

    MockAcrossSettler private settler;

    function setUp() public {
        _loadChain(CHAIN_NAME);

        settler = new MockAcrossSettler(owner, acrossSpokePool);
    }

    function test_handleV3AcrossMessage_fails_ifNotSpokePool() public {
        vm.expectRevert(IAcrossSettler.NotSpokePool.selector, address(settler));

        vm.prank(user);
        settler.handleV3AcrossMessage(address(0), 0, address(0), "");
    }

    function test_fuzz_handleV3AcrossMessage(bool hasSettlementCache, bool shouldSettleRevert) public {
        bytes memory data = "";

        if (shouldSettleRevert) {
            settler.setShouldSettleRevert(shouldSettleRevert);
            deal(weth, address(settler), 100);

            MigrationId migrationId = MigrationIdLibrary.from(0, address(0), MigrationModes.DUAL, 0);
            data = abi.encode(migrationId, ISettler.SettlementParams(user, 0, address(0), ""));

            if (hasSettlementCache) {
                settler.setSettlementCache(migrationId, Settler.SettlementCache(user, usdc, 200, ""));
                deal(usdc, address(settler), 200);
            }

            vm.expectEmit(true, true, true, true, weth);
            emit IERC20.Transfer(address(settler), user, 100);

            if (hasSettlementCache) {
                vm.expectEmit(true, true, true, true, usdc);
                emit IERC20.Transfer(address(settler), user, 200);
            }
        }

        vm.prank(acrossSpokePool);
        settler.handleV3AcrossMessage(weth, 100, address(0), data);
    }
}
