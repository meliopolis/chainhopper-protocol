// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IDirectSettler} from "../../src/interfaces/IDirectSettler.sol";
import {ISettler} from "../../src/interfaces/ISettler.sol";
import {IUniswapV3Settler} from "../../src/interfaces/IUniswapV3Settler.sol";
import {MigrationData} from "../../src/types/MigrationData.sol";
import {MigrationMode, MigrationModes} from "../../src/types/MigrationMode.sol";
import {MockDirectSettler} from "../mocks/MockDirectSettler.sol";
import {TestContext} from "../utils/TestContext.sol";

contract DirectSettlerTest is TestContext {
    string public constant SRC_CHAIN_NAME = "BASE";
    string public constant DEST_CHAIN_NAME = "";

    MockDirectSettler internal directSettler;

    function setUp() public {
        _loadChain(SRC_CHAIN_NAME, DEST_CHAIN_NAME);

        directSettler = new MockDirectSettler(owner);

        vm.startPrank(owner);
        directSettler.setProtocolFeeRecipient(owner);
        directSettler.setProtocolShareBps(10);
        directSettler.setProtocolShareOfSenderFeePct(10);
        vm.stopPrank();
    }

    function test_handleDirectTransfer_fails_ifAmountZero() public {
        address token = weth;
        uint256 amount = 0;
        bytes memory message = abi.encode(
            bytes32(0),
            MigrationData({
                sourceChainId: 0,
                migrator: address(0),
                nonce: 1,
                mode: MigrationModes.SINGLE,
                routesData: "",
                settlementData: ""
            })
        );

        vm.expectRevert(abi.encodeWithSelector(IDirectSettler.MissingAmount.selector, token));
        directSettler.handleDirectTransfer(token, amount, message);
    }

    function test_handleDirectTransfer_fails_ifInvalidMigration() public {
        address token = weth;
        uint256 amount = 100;

        // Create migration data with mismatched migrationId
        bytes32 wrongMigrationId = bytes32(uint256(1));
        MigrationData memory migrationData = MigrationData({
            sourceChainId: 0,
            migrator: address(0),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 correctMigrationId = migrationData.toId();

        // Encode with wrong migrationId
        bytes memory message = abi.encode(wrongMigrationId, migrationData);

        vm.expectRevert(abi.encodeWithSelector(IDirectSettler.InvalidMigration.selector));
        directSettler.handleDirectTransfer(token, amount, message);
    }

    function test_handleDirectTransfer_success_singleRoute() public {
        address token = weth;
        uint256 amount = 100;
        ISettler.SettlementParams memory params = ISettler.SettlementParams({
            recipient: user,
            senderShareBps: 0,
            senderFeeRecipient: address(0),
            mintParams: ""
        });
        MigrationData memory migrationData = MigrationData({
            sourceChainId: 0,
            migrator: address(0),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: abi.encode(params)
        });
        bytes32 migrationId = migrationData.toId();
        bytes memory message = abi.encode(migrationId, migrationData);
        deal(token, address(directSettler), amount);
        vm.expectEmit(true, true, true, true);
        emit ISettler.Receipt(migrationId, token, amount);
        vm.expectEmit(true, true, false, false);
        emit ISettler.Settlement(migrationId, user, 0);
        directSettler.handleDirectTransfer(token, amount, message);
    }

    function test_handleDirectTransfer_success_dualRoute() public {
        address token0 = weth;
        address token1 = usdc;
        uint256 amount = 100;
        ISettler.SettlementParams memory params = ISettler.SettlementParams({
            recipient: user,
            senderShareBps: 500,
            senderFeeRecipient: address(0),
            mintParams: ""
        });
        bytes memory routesData = abi.encode(token0, token1, 100, 200);
        MigrationData memory migrationData = MigrationData({
            sourceChainId: 0,
            migrator: address(0),
            nonce: 1,
            mode: MigrationModes.DUAL,
            routesData: routesData,
            settlementData: abi.encode(params)
        });
        bytes32 migrationId = migrationData.toId();
        bytes memory message = abi.encode(migrationId, migrationData);
        deal(token0, address(directSettler), amount);
        deal(token1, address(directSettler), 200);
        vm.expectEmit(true, true, true, true);
        emit ISettler.Receipt(migrationId, token0, amount);
        directSettler.handleDirectTransfer(token0, amount, message);
    }

    function test_handleDirectTransfer_fails_ifSelfSettleReverts() public {
        address token = weth;
        uint256 amount = 100;

        // Create migration data with unsupported mode to cause selfSettle to revert
        MigrationData memory migrationData = MigrationData({
            sourceChainId: 0,
            migrator: address(0),
            nonce: 1,
            mode: MigrationMode.wrap(type(uint8).max), // Unsupported mode
            routesData: "",
            settlementData: ""
        });

        bytes32 migrationId = migrationData.toId();
        bytes memory message = abi.encode(migrationId, migrationData);

        // Fund the settler
        deal(token, address(directSettler), amount);

        vm.expectEmit(true, true, true, true);
        emit ISettler.Receipt(migrationId, token, amount);

        // Should revert when selfSettle fails
        vm.expectRevert();
        directSettler.handleDirectTransfer(token, amount, message);
    }

    function test_fuzz_handleDirectTransfer(uint256 amount, uint256 nonce) public {
        vm.assume(amount > 0 && amount < type(uint128).max);

        address token = weth;

        ISettler.SettlementParams memory params = ISettler.SettlementParams({
            recipient: user,
            senderShareBps: 0,
            senderFeeRecipient: address(0),
            mintParams: ""
        });

        MigrationData memory migrationData = MigrationData({
            sourceChainId: 0,
            migrator: address(0),
            nonce: nonce,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: abi.encode(params)
        });

        bytes32 migrationId = migrationData.toId();
        bytes memory message = abi.encode(migrationId, migrationData);

        // Fund the settler
        deal(token, address(directSettler), amount);

        vm.expectEmit(true, true, true, true);
        emit ISettler.Receipt(migrationId, token, amount);

        vm.expectEmit(true, true, false, false);
        emit ISettler.Settlement(migrationId, user, 0);

        directSettler.handleDirectTransfer(token, amount, message);
    }

    function test_handleDirectTransfer_withDifferentTokens() public {
        address[] memory tokens = new address[](3);
        tokens[0] = weth;
        tokens[1] = usdc;
        tokens[2] = usdt;
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 amount = 100 * (i + 1);
            ISettler.SettlementParams memory params = ISettler.SettlementParams({
                recipient: user,
                senderShareBps: 0,
                senderFeeRecipient: address(0),
                mintParams: ""
            });
            MigrationData memory migrationData = MigrationData({
                sourceChainId: 0,
                migrator: address(0),
                nonce: i + 1,
                mode: MigrationModes.SINGLE,
                routesData: "",
                settlementData: abi.encode(params)
            });
            bytes32 migrationId = migrationData.toId();
            bytes memory message = abi.encode(migrationId, migrationData);
            deal(token, address(directSettler), amount);
            vm.expectEmit(true, true, true, true);
            emit ISettler.Receipt(migrationId, token, amount);
            vm.expectEmit(true, true, false, false);
            emit ISettler.Settlement(migrationId, user, 0);
            directSettler.handleDirectTransfer(token, amount, message);
        }
    }

    function test_handleDirectTransfer_revertsOnInvalidMessageDecoding() public {
        address token = weth;
        uint256 amount = 100;

        // Invalid message that can't be decoded
        bytes memory invalidMessage = "invalid message";

        vm.expectRevert();
        directSettler.handleDirectTransfer(token, amount, invalidMessage);
    }
}
