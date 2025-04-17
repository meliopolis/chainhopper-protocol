// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {ISettler} from "../../src/interfaces/ISettler.sol";
import {MigrationId, MigrationIdLibrary} from "../../src/types/MigrationId.sol";
import {MigrationMode, MigrationModes} from "../../src/types/MigrationMode.sol";
import {MockSettler} from "../mocks/MockSettler.sol";
import {TestContext} from "../utils/TestContext.sol";
import {RejectingRecipient} from "../mocks/MockRejectingRecipient.sol";

contract SettlerTest is TestContext {
    string constant CHAIN_NAME = "BASE";

    MockSettler settler;

    function setUp() public {
        _loadChain(CHAIN_NAME);

        settler = new MockSettler(owner);

        vm.startPrank(owner);
        settler.setProtocolFeeRecipient(owner);
        settler.setProtocolShareBps(100);
        settler.setProtocolShareOfSenderFeePct(10);
        vm.stopPrank();
    }

    // other than single or dual routes

    function test_selfSettle_fails_ifNotSelf() public {
        vm.expectRevert(abi.encodeWithSelector(ISettler.NotSelf.selector), address(settler));
        settler.selfSettle(address(0), 0, "");
    }

    function test_selfSettle_fails_ifMissingAmount() public {
        vm.expectRevert(abi.encodeWithSelector(ISettler.MissingAmount.selector, address(0)), address(settler));
        vm.prank(address(settler));
        settler.selfSettle(address(0), 0, "");
    }

    function test_selfSettle_fails_ifUnsupportedMode() public {
        MigrationId migrationId = MigrationIdLibrary.from(0, address(0), MigrationMode.wrap(type(uint8).max), 0);
        bytes memory data =
            abi.encode(migrationId, abi.encode(ISettler.SettlementParams(address(0), 0, address(0), "")));

        vm.expectRevert(abi.encodeWithSelector(ISettler.UnsupportedMode.selector, type(uint8).max), address(settler));
        vm.prank(address(settler));
        settler.selfSettle(address(0), 100, data);
    }

    function test_fuzz_withdraw(bool isNative, bool isRecipient) public {
        MigrationId migrationId = MigrationId.wrap(0);
        address token;
        if (isNative) {
            deal(address(settler), 100);
        } else {
            token = weth;
            deal(token, address(settler), 100);
        }

        settler.setSettlementCache(migrationId, isRecipient ? user : owner, token, 100, "");

        if (!isRecipient) {
            vm.expectRevert(abi.encodeWithSelector(ISettler.NotRecipient.selector), address(settler));
        } else {
            if (!isNative) {
                vm.expectEmit(true, true, true, true);
                emit IERC20.Transfer(address(settler), user, 100);
            } else {
                vm.expectEmit(true, true, true, true);
                emit ISettler.Refund(migrationId, user, address(0), 100);
            }
        }

        vm.prank(user);
        settler.withdraw(migrationId);
    }

    function test_fuzz_exposeTransfer(bool isNative, bool useRejectingRecipient) public {
        address token;
        if (isNative) {
            deal(address(settler), 100);
            token = address(0);
        } else {
            deal(weth, address(settler), 100);
            token = weth;
        }

        address recipient;
        if (useRejectingRecipient) {
            recipient = address(new RejectingRecipient());
        } else {
            recipient = user;
        }

        if (isNative) {
            if (useRejectingRecipient) {
                vm.expectRevert(abi.encodeWithSelector(ISettler.NativeTokenTransferFailed.selector, recipient, 100));
            }
        } else {
            vm.expectEmit(true, true, true, true);
            emit IERC20.Transfer(address(settler), recipient, 100);
        }

        vm.prank(address(settler));
        settler.exposeTransfer(token, recipient, 100);
    }

    // single token

    function test_fuzz_selfSettle_singleRoute(ISettler.SettlementParams memory params, bool isTokenNative) public {
        vm.assume(params.senderShareBps < type(uint16).max - settler.protocolShareBps());
        MigrationId migrationId = MigrationIdLibrary.from(0, address(0), MigrationModes.SINGLE, 0);
        bytes memory data = abi.encode(migrationId, abi.encode(params));

        address token;
        if (isTokenNative) {
            deal(address(settler), 100);
        } else {
            token = weth;
            deal(token, address(settler), 100);
        }

        if (params.senderShareBps + settler.protocolShareBps() > settler.MAX_SHARE_BPS()) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    ISettler.MaxFeeExceeded.selector, settler.protocolShareBps(), params.senderShareBps
                ),
                address(settler)
            );
        } else {
            vm.expectEmit(true, true, true, true);
            emit ISettler.Settlement(migrationId, params.recipient, 0);
        }

        vm.prank(address(settler));
        settler.selfSettle(token, 100, data);
    }

    // dual tokens

    function test_fuzz_selfSettle_dualRoute(
        ISettler.SettlementParams memory params,
        bool hasSettlementCache,
        bool isToken0Native,
        bool isToken1Native,
        bool isDataMatching
    ) public {
        vm.assume(params.senderShareBps < type(uint16).max - settler.protocolShareBps());
        MigrationId migrationId = MigrationIdLibrary.from(0, address(0), MigrationModes.DUAL, 0);
        bytes memory data = abi.encode(migrationId, abi.encode(params));

        address token0;
        if (isToken0Native) {
            deal(address(settler), 100);
        } else {
            token0 = weth;
            deal(token0, address(settler), 100);
        }

        address token1;
        if (isToken1Native) {
            deal(address(settler), 100);
        } else {
            token1 = weth;
            deal(token1, address(settler), 100);
        }

        if (hasSettlementCache) {
            settler.setSettlementCache(migrationId, params.recipient, token1, 200, isDataMatching ? data : bytes(""));
        }

        if (hasSettlementCache) {
            if (!isDataMatching) {
                vm.expectRevert(abi.encodeWithSelector(ISettler.MismatchingData.selector), address(settler));
            } else if (params.senderShareBps + settler.protocolShareBps() > settler.MAX_SHARE_BPS()) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        ISettler.MaxFeeExceeded.selector, settler.protocolShareBps(), params.senderShareBps
                    ),
                    address(settler)
                );
            } else {
                vm.expectEmit(true, true, true, true);
                emit ISettler.Settlement(migrationId, params.recipient, 0);
            }
        }

        vm.prank(address(settler));
        settler.selfSettle(token0, 100, data);
    }
}
