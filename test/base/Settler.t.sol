// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {ISettler} from "../../src/interfaces/ISettler.sol";
import {MigrationData} from "../../src/types/MigrationData.sol";
import {MigrationMode, MigrationModes} from "../../src/types/MigrationMode.sol";
import {MockSettler} from "../mocks/MockSettler.sol";
import {TestContext} from "../utils/TestContext.sol";
// import {RejectingRecipient} from "../mocks/MockRejectingRecipient.sol";

contract SettlerTest is TestContext {
    string public constant SRC_CHAIN_NAME = "BASE";
    string public constant DEST_CHAIN_NAME = "";

    MockSettler internal settler;

    function setUp() public {
        _loadChain(SRC_CHAIN_NAME, DEST_CHAIN_NAME);

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
        bytes memory settlementParams = abi.encode(ISettler.SettlementParams(address(0), 0, address(0), ""));
        MigrationData memory migrationData =
            MigrationData(0, address(0), 0, MigrationMode.wrap(type(uint8).max), "", settlementParams);
        bytes memory data = abi.encode(migrationData.toHash(), migrationData);

        vm.expectRevert(abi.encodeWithSelector(ISettler.UnsupportedMode.selector, type(uint8).max), address(settler));
        vm.prank(address(settler));
        settler.selfSettle(address(0), 100, data);
    }

    function test_fuzz_withdraw(bool isRecipient) public {
        address token = weth;
        bytes32 messageHash = keccak256("");

        deal(token, address(settler), 100);

        settler.setSettlementCache(messageHash, isRecipient ? user : owner, token, 100);

        if (!isRecipient) {
            vm.expectRevert(abi.encodeWithSelector(ISettler.NotRecipient.selector), address(settler));
        } else {
            vm.expectEmit(true, true, true, true);
            emit IERC20.Transfer(address(settler), user, 100);

            vm.expectEmit(true, true, true, true);
            emit ISettler.Refund(messageHash, user, token, 100);
        }

        vm.prank(user);
        settler.withdraw(messageHash);
    }

    function test_selfSettle_fails_ifInvalidMigration() public {
        bytes memory data = abi.encode(bytes32(0), MigrationData(0, address(0), 0, MigrationModes.SINGLE, "", ""));

        vm.expectRevert(abi.encodeWithSelector(ISettler.InvalidMigration.selector), address(settler));

        vm.prank(address(settler));
        settler.selfSettle(weth, 100, data);
    }

    // single token

    function test_fuzz_selfSettle_singleRoute(ISettler.SettlementParams memory params) public {
        vm.assume(params.senderShareBps < type(uint16).max - settler.protocolShareBps());

        address token = weth;
        MigrationData memory migrationData =
            MigrationData(0, address(0), 0, MigrationModes.SINGLE, "", abi.encode(params));
        bytes memory data = abi.encode(migrationData.toHash(), migrationData);

        deal(token, address(settler), 100);

        if (params.senderShareBps + settler.protocolShareBps() > settler.MAX_SHARE_BPS()) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    ISettler.MaxFeeExceeded.selector, settler.protocolShareBps(), params.senderShareBps
                ),
                address(settler)
            );
        } else {
            vm.expectEmit(true, true, true, true);
            emit ISettler.Settlement(migrationData.toHash(), params.recipient, 0);
        }

        vm.prank(address(settler));
        settler.selfSettle(token, 100, data);
    }

    // dual tokens

    function test_fuzz_selfSettle_dualRoute(ISettler.SettlementParams memory params, bool hasSettlementCache) public {
        vm.assume(params.senderShareBps < type(uint16).max - settler.protocolShareBps());

        address token0 = weth < usdc ? weth : usdc;
        address token1 = weth < usdc ? usdc : weth;
        bytes memory rouatesData = abi.encode(token0, token1, 100, 200);
        MigrationData memory migrationData =
            MigrationData(0, address(0), 0, MigrationModes.DUAL, rouatesData, abi.encode(params));
        bytes memory data = abi.encode(migrationData.toHash(), migrationData);

        deal(token0, address(settler), 100);
        deal(token1, address(settler), 200);

        bool isRevert;
        if (hasSettlementCache) {
            settler.setSettlementCache(migrationData.toHash(), params.recipient, token1, 200);

            if (params.senderShareBps + settler.protocolShareBps() > settler.MAX_SHARE_BPS()) {
                isRevert = true;
                vm.expectRevert(
                    abi.encodeWithSelector(
                        ISettler.MaxFeeExceeded.selector, settler.protocolShareBps(), params.senderShareBps
                    ),
                    address(settler)
                );
            } else {
                vm.expectEmit(true, true, true, true);
                emit ISettler.Settlement(migrationData.toHash(), params.recipient, 0);
            }
        }

        vm.prank(address(settler));
        settler.selfSettle(token0, 100, data);

        (,, uint256 amount) = settler.getSettlementCache(migrationData.toHash());
        if (hasSettlementCache != isRevert) {
            vm.assertEq(amount, 0);
        } else {
            vm.assertGt(amount, 0);
        }
    }

    function test_selfSettle_dualRoute_fails_ifSameToken() public {
        address token0 = weth < usdc ? weth : usdc;
        address token1 = weth < usdc ? usdc : weth;
        MigrationData memory migrationData = MigrationData(
            0,
            address(0),
            0,
            MigrationModes.DUAL,
            abi.encode(token0, token1, 100, 100),
            abi.encode(ISettler.SettlementParams(address(0), 0, address(0), ""))
        );
        bytes memory data = abi.encode(migrationData.toHash(), migrationData);

        deal(token1, address(settler), 100);

        settler.setSettlementCache(migrationData.toHash(), address(0), token1, 100);

        vm.expectRevert(abi.encodeWithSelector(ISettler.SameToken.selector), address(settler));

        vm.prank(address(settler));
        settler.selfSettle(token1, 100, data);
    }

    function test_selfSettle_dualRoute_fails_ifUnexpectedToken() public {
        address token0 = weth < usdc ? weth : usdc;
        address token1 = weth < usdc ? usdc : weth;
        MigrationData memory migrationData = MigrationData(
            0,
            address(0),
            0,
            MigrationModes.DUAL,
            abi.encode(token0, token1, 100, 200),
            abi.encode(ISettler.SettlementParams(address(0), 0, address(0), ""))
        );
        bytes memory data = abi.encode(migrationData.toHash(), migrationData);

        vm.expectRevert(abi.encodeWithSelector(ISettler.UnexpectedToken.selector, usdt), address(settler));

        vm.prank(address(settler));
        settler.selfSettle(usdt, 100, data);
    }

    function test_selfSettle_dualRoute_fails_ifAmount0TooLow() public {
        address token0 = weth < usdc ? weth : usdc;
        address token1 = weth < usdc ? usdc : weth;
        MigrationData memory migrationData = MigrationData(
            0,
            address(0),
            0,
            MigrationModes.DUAL,
            abi.encode(token0, token1, type(uint256).max, 200),
            abi.encode(ISettler.SettlementParams(address(0), 0, address(0), ""))
        );
        bytes memory data = abi.encode(migrationData.toHash(), migrationData);

        vm.expectRevert(
            abi.encodeWithSelector(ISettler.AmountTooLow.selector, token0, 100, type(uint256).max), address(settler)
        );

        vm.prank(address(settler));
        settler.selfSettle(token0, 100, data);
    }

    function test_selfSettle_dualRoute_fails_ifAmount1TooLow() public {
        address token0 = weth < usdc ? weth : usdc;
        address token1 = weth < usdc ? usdc : weth;
        MigrationData memory migrationData = MigrationData(
            0,
            address(0),
            0,
            MigrationModes.DUAL,
            abi.encode(token0, token1, 100, type(uint256).max),
            abi.encode(ISettler.SettlementParams(address(0), 0, address(0), ""))
        );
        bytes memory data = abi.encode(migrationData.toHash(), migrationData);

        vm.expectRevert(
            abi.encodeWithSelector(ISettler.AmountTooLow.selector, token1, 200, type(uint256).max), address(settler)
        );

        vm.prank(address(settler));
        settler.selfSettle(token1, 200, data);
    }

    // function test_fuzz_selfSettle_dualRoute(
    //     ISettler.SettlementParams memory params,
    //     bool isToken0Sufficient,
    //     bool isToken1Sufficient,
    //     bool isSameToken,
    //     bool isUnexpectedToken,
    //     bool hasSettlementCache
    // ) public {
    //     vm.assume(!(isSameToken && isUnexpectedToken));

    //     address unexpectedToken = usdt;

    //     if (hasSettlementCache) {
    //     }

    //
    //     if (isUnexpectedToken) {
    //         isRevert = true;
    //         vm.expectRevert(
    //             abi.encodeWithSelector(ISettler.UnexpectedToken.selector, unexpectedToken), address(settler)
    //         );
    //     } else if (isToken0Sufficient) {
    //         isRevert = true;
    //         vm.expectRevert(
    //             abi.encodeWithSelector(ISettler.AmountTooLow.selector, token0, 100, type(uint256).max), address(settler)
    //         );
    //     } else if (isToken1Sufficient) {
    //         isRevert = true;
    //         vm.expectRevert(
    //             abi.encodeWithSelector(ISettler.AmountTooLow.selector, token1, 200, type(uint256).max), address(settler)
    //         );
    //     } else
    //     }

    // }
}
