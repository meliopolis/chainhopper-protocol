// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IWETH9} from "../../src/interfaces/external/IWETH9.sol";
import {IDirectMigrator} from "../../src/interfaces/IDirectMigrator.sol";
import {IDirectSettler} from "../../src/interfaces/IDirectSettler.sol";
import {IMigrator} from "../../src/interfaces/IMigrator.sol";
import {ISettler} from "../../src/interfaces/ISettler.sol";
import {MigrationData} from "../../src/types/MigrationData.sol";
import {MigrationModes} from "../../src/types/MigrationMode.sol";
import {MockDirectMigrator} from "../mocks/MockDirectMigrator.sol";
import {MockDirectSettler} from "../mocks/MockDirectSettler.sol";
import {TestContext} from "../utils/TestContext.sol";
import {IUniswapV3Settler} from "../../src/interfaces/IUniswapV3Settler.sol";

contract DirectMigratorTest is TestContext {
    string public constant SRC_CHAIN_NAME = "BASE";
    string public constant DEST_CHAIN_NAME = "";

    MockDirectMigrator internal directMigrator;
    MockDirectSettler internal directSettler;

    function setUp() public {
        _loadChain(SRC_CHAIN_NAME, DEST_CHAIN_NAME);

        directSettler = new MockDirectSettler(owner);
        directMigrator = new MockDirectMigrator(owner, weth);

        vm.startPrank(owner);
        directSettler.setProtocolFeeRecipient(owner);
        directSettler.setProtocolShareBps(100);
        directSettler.setProtocolShareOfSenderFeePct(10);
        vm.stopPrank();
    }

    function test_matchTokenWithRoute_success() public {
        address token = weth;
        IMigrator.TokenRoute memory tokenRoute = IMigrator.TokenRoute(weth, 100, "");
        bool isMatch = directMigrator.matchTokenWithRoute(token, tokenRoute);
        assertTrue(isMatch);
    }

    function test_matchTokenWithRoute_fails() public {
        address token = weth;
        IMigrator.TokenRoute memory tokenRoute = IMigrator.TokenRoute(usdc, 100, "");
        bool isMatch = directMigrator.matchTokenWithRoute(token, tokenRoute);
        assertFalse(isMatch);
    }

    function test_isAmountSufficient_success() public {
        uint256 amount = 150;
        IMigrator.TokenRoute memory tokenRoute = IMigrator.TokenRoute(weth, 100, "");
        bool isSufficient = directMigrator.isAmountSufficient(amount, tokenRoute);
        assertTrue(isSufficient);
    }

    function test_isAmountSufficient_fails() public {
        uint256 amount = 50;
        IMigrator.TokenRoute memory tokenRoute = IMigrator.TokenRoute(weth, 100, "");
        bool isSufficient = directMigrator.isAmountSufficient(amount, tokenRoute);
        assertFalse(isSufficient);
    }

    function test_isAmountSufficient_exactAmount() public {
        uint256 amount = 100;
        IMigrator.TokenRoute memory tokenRoute = IMigrator.TokenRoute(weth, 100, "");
        bool isSufficient = directMigrator.isAmountSufficient(amount, tokenRoute);
        assertTrue(isSufficient);
    }

    function test_getOutputToken() public {
        address expectedToken = weth;
        IMigrator.TokenRoute memory tokenRoute = IMigrator.TokenRoute(expectedToken, 100, "");
        address outputToken = directMigrator.getOutputToken(tokenRoute);
        assertEq(outputToken, expectedToken);
    }

    function test_fuzz_matchTokenWithRoute(address token, address routeToken) public {
        IMigrator.TokenRoute memory tokenRoute = IMigrator.TokenRoute(routeToken, 100, "");
        bool isMatch = directMigrator.matchTokenWithRoute(token, tokenRoute);
        assertEq(isMatch, token == routeToken);
    }

    function test_fuzz_isAmountSufficient(uint256 amount, uint256 minAmount) public {
        vm.assume(amount < type(uint256).max && minAmount < type(uint256).max);
        IMigrator.TokenRoute memory tokenRoute = IMigrator.TokenRoute(weth, minAmount, "");
        bool isSufficient = directMigrator.isAmountSufficient(amount, tokenRoute);
        assertEq(isSufficient, amount >= minAmount);
    }

    function test_bridge_fails_ifCrossChainMigration() public {
        uint256 differentChainId = block.chainid + 1;
        address settler = address(directSettler);
        address token = weth;
        uint256 amount = 100;
        bytes memory data = "";

        vm.expectRevert(abi.encodeWithSelector(IDirectMigrator.CrossChainNotSupported.selector));
        directMigrator.bridge(
            address(0), // sender
            differentChainId,
            settler,
            token,
            amount,
            address(0), // inputToken
            "", // routeData
            data
        );
    }

    function test_bridge_success_erc20Token() public {
        uint256 chainId = block.chainid;
        address settler = address(directSettler);
        address token = usdc;
        uint256 amount = 100;

        ISettler.SettlementParams memory params = ISettler.SettlementParams({
            recipient: user,
            senderShareBps: 0,
            senderFeeRecipient: address(0),
            mintParams: abi.encode(
                IUniswapV3Settler.MintParams({
                    token0: token,
                    token1: token,
                    fee: 0,
                    sqrtPriceX96: 0,
                    tickLower: 0,
                    tickUpper: 0,
                    swapAmountInMilliBps: 0,
                    amount0Min: 0,
                    amount1Min: 0
                })
            )
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
        bytes memory data = abi.encode(migrationId, migrationData);

        // Fund the migrator
        deal(token, address(directMigrator), amount);

        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(directMigrator), settler, amount);

        directMigrator.bridge(
            address(0), // sender
            chainId,
            settler,
            token,
            amount,
            address(0), // inputToken
            "", // routeData
            data
        );
    }

    function test_bridge_success_nativeToken() public {
        uint256 chainId = block.chainid;
        address settler = address(directSettler);
        address token = address(0); // Native token
        uint256 amount = 100;

        ISettler.SettlementParams memory params = ISettler.SettlementParams({
            recipient: user,
            senderShareBps: 0,
            senderFeeRecipient: address(0),
            mintParams: abi.encode(
                IUniswapV3Settler.MintParams({
                    token0: token,
                    token1: token,
                    fee: 0,
                    sqrtPriceX96: 0,
                    tickLower: 0,
                    tickUpper: 0,
                    swapAmountInMilliBps: 0,
                    amount0Min: 0,
                    amount1Min: 0
                })
            )
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
        bytes memory data = abi.encode(migrationId, migrationData);

        // Fund the migrator with native tokens
        vm.deal(address(directMigrator), amount);

        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(directMigrator), settler, amount);

        directMigrator.bridge(
            address(0), // sender
            chainId,
            settler,
            token,
            amount,
            address(0), // inputToken
            "", // routeData
            data
        );
    }

    function test_bridge_fails_ifSettlerCallFails() public {
        uint256 chainId = block.chainid;
        address settler = address(directSettler);
        address token = usdc;
        uint256 amount = 100;
        bytes memory data = "";

        // Fund the migrator
        deal(token, address(directMigrator), amount);

        // Approve the migrator to spend tokens
        // vm.prank(address(directMigrator));
        // IERC20(token).approve(address(directMigrator), amount);

        vm.expectRevert();
        directMigrator.bridge(
            address(0), // sender
            chainId,
            settler,
            token,
            amount,
            address(0), // inputToken
            "", // routeData
            "" // settlementData
        );
    }

    function test_bridge_withDifferentTokens() public {
        address[] memory tokens = new address[](3);
        tokens[0] = weth;
        tokens[1] = usdc;
        tokens[2] = usdt;
        uint256 chainId = block.chainid;
        address settler = address(directSettler);

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 amount = 100 * (i + 1);
            ISettler.SettlementParams memory params = ISettler.SettlementParams({
                recipient: user,
                senderShareBps: 0,
                senderFeeRecipient: address(0),
                mintParams: abi.encode(
                    IUniswapV3Settler.MintParams({
                        token0: token,
                        token1: token,
                        fee: 0,
                        sqrtPriceX96: 0,
                        tickLower: 0,
                        tickUpper: 0,
                        swapAmountInMilliBps: 0,
                        amount0Min: 0,
                        amount1Min: 0
                    })
                )
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
            bytes memory data = abi.encode(migrationId, migrationData);
            deal(token, address(directMigrator), amount);
            vm.prank(address(directMigrator));
            // IERC20(token).approve(address(directMigrator), amount);
            // vm.expectEmit(true, true, true, true);
            // emit IERC20.Transfer(address(directMigrator), settler, amount);
            directMigrator.bridge(
                address(0), // sender
                chainId,
                settler,
                token,
                amount,
                address(0), // inputToken
                "", // routeData
                data
            );
        }
    }

    function test_bridge_fails_ifZeroAmount() public {
        uint256 chainId = block.chainid;
        address settler = address(directSettler);
        address token = usdc;
        uint256 amount = 0;
        bytes memory data = "";

        vm.expectRevert();
        directMigrator.bridge(
            address(0), // sender
            chainId,
            settler,
            token,
            amount,
            address(0), // inputToken
            "", // routeData
            data
        );
    }
}
