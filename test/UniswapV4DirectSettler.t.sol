// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {TestContext} from "./utils/TestContext.sol";
import {ISettler} from "../src/interfaces/ISettler.sol";
import {IUniswapV4Settler} from "../src/interfaces/IUniswapV4Settler.sol";
import {IDirectSettler} from "../src/interfaces/IDirectSettler.sol";
import {UniswapV4DirectSettlerHarness} from "./mocks/UniswapV4DirectSettlerHarness.sol";
import {UniswapV4Helpers} from "./utils/UniswapV4Helpers.sol";
import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {MigrationModes, MigrationMode} from "../src/types/MigrationMode.sol";
import {MigrationData} from "../src/types/MigrationData.sol";
import {SettlementHelpers} from "./utils/SettlementHelpers.sol";
import {PoolKey} from "@uniswap-v4-core/types/PoolKey.sol";
import {Currency} from "@uniswap-v4-core/types/Currency.sol";
import {IHooks} from "@uniswap-v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap-v4-core/interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "@uniswap-v4-core/types/PoolId.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {TickMath} from "@uniswap-v4-core/libraries/TickMath.sol";

contract UniswapV4DirectSettlerTest is TestContext, UniswapV4Helpers {
    string public constant CHAIN_NAME = "BASE";
    UniswapV4DirectSettlerHarness public settler;
    uint256 public tokenId = 36188;
    uint16 public protocolFee = 10;
    uint256 public wethAmount = 1 ether;
    uint256 public usdcAmount = 1_000_000_000;
    address public protocolFeeRecipient = address(0x123);
    uint8 public protocolShareOfSenderFeePct = 10;
    uint16 public senderShareBps = 20;

    uint16 public totalProtocolFeeBps = protocolFee + protocolShareOfSenderFeePct * senderShareBps / 100;
    uint16 public netSenderFeeBps = (100 - protocolShareOfSenderFeePct) * senderShareBps / 100;

    function setUp() public {
        _loadChain(CHAIN_NAME, "");

        vm.prank(owner);
        settler = new UniswapV4DirectSettlerHarness(
            owner, address(v4PositionManager), address(universalRouter), address(permit2), address(weth)
        );

        vm.prank(owner);
        settler.setProtocolFeeRecipient(protocolFeeRecipient);
        vm.prank(owner);
        settler.setProtocolShareBps(protocolFee);
        vm.prank(owner);
        settler.setProtocolShareOfSenderFeePct(protocolShareOfSenderFeePct);
    }

    function genSettlerData(PoolKey memory poolKey, SettlementHelpers.Range range, bool isToken0BaseToken)
        public
        view
        returns (bytes32 migrationId, bytes memory data)
    {
        int24 currentTick = UniswapV4Helpers.getCurrentTick(address(v4StateView), poolKey);
        (migrationId, data) = SettlementHelpers.generateSettlerData(
            SettlementHelpers.generateV4SettlementParamsUsingCurrentTick(
                user, poolKey, 0, currentTick, range, 0, 0, isToken0BaseToken, senderShareBps
            ),
            MigrationModes.SINGLE,
            ""
        );
        return (migrationId, data);
    }

    function genSettlerDataWithSqrtPriceX96(
        PoolKey memory poolKey,
        SettlementHelpers.Range range,
        bool isToken0BaseToken,
        uint160 sqrtPriceX96
    ) public view returns (bytes32 migrationId, bytes memory data) {
        int24 currentTick = 10000;
        (migrationId, data) = SettlementHelpers.generateSettlerData(
            SettlementHelpers.generateV4SettlementParamsUsingCurrentTick(
                user, poolKey, sqrtPriceX96, currentTick, range, 0, 0, isToken0BaseToken, senderShareBps
            ),
            MigrationModes.SINGLE,
            ""
        );
        return (migrationId, data);
    }

    function genSettlerDataWithAmounts(
        PoolKey memory poolKey,
        SettlementHelpers.Range range,
        bool isToken0BaseToken,
        uint256 amount0Min,
        uint256 amount1Min
    ) public view returns (bytes32 migrationId, bytes memory data) {
        int24 currentTick = UniswapV4Helpers.getCurrentTick(address(v4StateView), poolKey);
        (migrationId, data) = SettlementHelpers.generateSettlerData(
            SettlementHelpers.generateV4SettlementParamsUsingCurrentTick(
                user, poolKey, 0, currentTick, range, amount0Min, amount1Min, isToken0BaseToken, senderShareBps
            ),
            MigrationModes.SINGLE,
            ""
        );
        return (migrationId, data);
    }

    function genSettlerDataForDualToken(
        PoolKey memory poolKey,
        SettlementHelpers.Range range,
        bool isToken0BaseToken,
        uint256 routeMinAmount0,
        uint256 routeMinAmount1
    ) public view returns (bytes32 migrationId, bytes memory data) {
        int24 currentTick = UniswapV4Helpers.getCurrentTick(address(v4StateView), poolKey);
        // need to handle native token case
        address currency0 = Currency.unwrap(poolKey.currency0) == address(0) ? weth : Currency.unwrap(poolKey.currency0);
        (migrationId, data) = SettlementHelpers.generateSettlerData(
            SettlementHelpers.generateV4SettlementParamsUsingCurrentTick(
                user, poolKey, 0, currentTick, range, 0, 0, isToken0BaseToken, senderShareBps
            ),
            MigrationModes.DUAL,
            abi.encode(currency0, Currency.unwrap(poolKey.currency1), routeMinAmount0, routeMinAmount1)
        );
        return (migrationId, data);
    }

    function genSettlerDataForDualTokenWithSqrtPriceX96(
        PoolKey memory poolKey,
        SettlementHelpers.Range range,
        bool isToken0BaseToken,
        uint256 routeMinAmount0,
        uint256 routeMinAmount1,
        uint160 sqrtPriceX96
    ) public view returns (bytes32 migrationId, bytes memory data) {
        int24 currentTick = 10000;
        // need to handle native token case
        address currency0 = Currency.unwrap(poolKey.currency0) == address(0) ? weth : Currency.unwrap(poolKey.currency0);
        (migrationId, data) = SettlementHelpers.generateSettlerData(
            SettlementHelpers.generateV4SettlementParamsUsingCurrentTick(
                user, poolKey, sqrtPriceX96, currentTick, range, 0, 0, isToken0BaseToken, senderShareBps
            ),
            MigrationModes.DUAL,
            abi.encode(currency0, Currency.unwrap(poolKey.currency1), routeMinAmount0, routeMinAmount1)
        );
        return (migrationId, data);
    }

    function genSettlerDataForDualTokenWithAmounts(
        PoolKey memory poolKey,
        SettlementHelpers.Range range,
        bool isToken0BaseToken,
        uint256 routeMinAmount0,
        uint256 routeMinAmount1,
        uint256 amount0Min,
        uint256 amount1Min
    ) public view returns (bytes32 migrationId, bytes memory data) {
        int24 currentTick = UniswapV4Helpers.getCurrentTick(address(v4StateView), poolKey);
        // need to handle native token case
        address currency0 = Currency.unwrap(poolKey.currency0) == address(0) ? weth : Currency.unwrap(poolKey.currency0);
        (migrationId, data) = SettlementHelpers.generateSettlerData(
            SettlementHelpers.generateV4SettlementParamsUsingCurrentTick(
                user, poolKey, 0, currentTick, range, amount0Min, amount1Min, isToken0BaseToken, senderShareBps
            ),
            MigrationModes.DUAL,
            abi.encode(currency0, Currency.unwrap(poolKey.currency1), routeMinAmount0, routeMinAmount1)
        );
        return (migrationId, data);
    }

    function assertCorrectAmounts(
        Vm.Log[] memory entries,
        PoolKey memory poolKey,
        bool isToken0BaseToken,
        uint256 expectedAmount0,
        uint256 expectedAmount1
    ) public view {
        // check swap event
        Vm.Log[] memory swapEvents = findSwapEvents(entries);
        uint256 swapAmountIn = 0;
        uint256 swapAmountOut = 0;
        if (swapEvents.length > 0) {
            (swapAmountIn, swapAmountOut) = parseSwapEventForBothAmounts(swapEvents[0].data);
        }
        // check transfer events for minting, as ModifyLiquidity doesn't include amounts
        Vm.Log[] memory transferToPoolManagerEvents =
            findTransferToPoolEventsAfterModifyLiquidity(entries, address(v4PoolManager));
        uint256 mintAmount0 = 0;
        uint256 mintAmount1 = 0;
        if (transferToPoolManagerEvents.length > 0) {
            (mintAmount0, mintAmount1) = parseTransferToPoolManagerEvents(transferToPoolManagerEvents, poolKey);
        }
        // check fee payment events
        Vm.Log memory feePaymentEvent = SettlementHelpers.findFeePaymentEvent(entries);
        uint256 feePaymentAmount = 0;
        if (feePaymentEvent.data.length > 0) {
            feePaymentAmount = SettlementHelpers.parseFeePaymentEvent(feePaymentEvent.data);
        }
        // check transfer events
        Vm.Log[] memory transferEvents = SettlementHelpers.findTransferToUserEvents(entries, user);
        uint256 transferAmount0 = 0;
        uint256 transferAmount1 = 0;
        if (transferEvents.length > 0) {
            transferAmount0 = SettlementHelpers.parseTransferToUserEvent(transferEvents[0]);
        }
        if (transferEvents.length > 1) {
            transferAmount1 = SettlementHelpers.parseTransferToUserEvent(transferEvents[1]);
        }
        // verify amounts
        if (isToken0BaseToken) {
            assertEq(expectedAmount0, mintAmount0 + swapAmountIn + feePaymentAmount + transferAmount0);
            assertEq(expectedAmount1, mintAmount1 + transferAmount1 - swapAmountOut); // ordering important since it's uint256
        } else {
            assertEq(expectedAmount0, mintAmount0 + transferAmount0 - swapAmountOut);
            assertEq(expectedAmount1, mintAmount1 + swapAmountIn + feePaymentAmount + transferAmount1);
        }
    }

    function assertCorrectAmountsForNativeTokenPositions(
        Vm.Log[] memory entries,
        PoolKey memory poolKey,
        uint256 expectedAmount0,
        uint256 expectedAmount1
    ) public view {
        // check swap event
        Vm.Log[] memory swapEvents = findSwapEvents(entries);
        uint256 swapAmountIn = 0;
        uint256 swapAmountOut = 0;
        if (swapEvents.length > 0) {
            (swapAmountIn, swapAmountOut) = parseSwapEventForBothAmounts(swapEvents[0].data);
        }
        // check transfer events for minting, as ModifyLiquidity doesn't include amounts
        // this will only give ERC20 amounts, not native token amounts
        Vm.Log[] memory transferToPoolManagerEvents =
            findTransferToPoolEventsAfterModifyLiquidity(entries, address(v4PoolManager));
        uint256 mintAmount0 = 0;
        uint256 mintAmount1 = 0;
        if (transferToPoolManagerEvents.length > 0) {
            (mintAmount0, mintAmount1) = parseTransferToPoolManagerEvents(transferToPoolManagerEvents, poolKey);
        }
        // now get ModifyLiquidity events
        Vm.Log memory modifyLiquidityEvent = findModifyLiquidityEvent(entries);
        uint256 liquidity = 0;
        int24 tickLower = 0;
        int24 tickUpper = 0;
        if (modifyLiquidityEvent.data.length > 0) {
            (tickLower, tickUpper, liquidity) = parseModifyLiquidityEvent(modifyLiquidityEvent.data);
            uint256 amount0 = getAmount0(address(v4StateView), poolKey, tickLower, tickUpper, uint128(liquidity));
            mintAmount0 += amount0;
        }
        // check fee payment events
        Vm.Log memory feePaymentEvent = SettlementHelpers.findFeePaymentEvent(entries);
        uint256 feePaymentAmount = 0;
        if (feePaymentEvent.data.length > 0) {
            feePaymentAmount = SettlementHelpers.parseFeePaymentEvent(feePaymentEvent.data);
        }
        // check transfer events
        Vm.Log[] memory transferEvents = SettlementHelpers.findTransferToUserEvents(entries, user);
        uint256 transferAmount0 = 0;
        uint256 transferAmount1 = 0;
        if (transferEvents.length > 0) {
            transferAmount0 = SettlementHelpers.parseTransferToUserEvent(transferEvents[0]);
        }
        if (transferEvents.length > 1) {
            transferAmount1 = SettlementHelpers.parseTransferToUserEvent(transferEvents[1]);
        }
        // verify amounts
        assertEq(expectedAmount0, mintAmount0 + swapAmountIn + feePaymentAmount + transferAmount0);
        assertEq(expectedAmount1, mintAmount1 + transferAmount1 - swapAmountOut);
    }

    function assertCorrectAmountsDualToken(
        Vm.Log[] memory entries,
        PoolKey memory poolKey,
        bool didToken0ArriveFirst,
        uint256 expectedAmount0,
        uint256 expectedAmount1
    ) public view {
        // check transfer events for minting, as ModifyLiquidity doesn't include amounts
        Vm.Log[] memory transferToPoolManagerEvents =
            findTransferToPoolEventsAfterModifyLiquidity(entries, address(v4PoolManager));
        uint256 mintAmount0 = 0;
        uint256 mintAmount1 = 0;
        if (transferToPoolManagerEvents.length > 0) {
            (mintAmount0, mintAmount1) = parseTransferToPoolManagerEvents(transferToPoolManagerEvents, poolKey);
        }
        // check fee payment events
        Vm.Log[] memory feePaymentEvents = SettlementHelpers.findFeePaymentEvents(entries);
        uint256 feePaymentAmount0 = 0;
        uint256 feePaymentAmount1 = 0;
        if (feePaymentEvents.length > 0) {
            if (didToken0ArriveFirst) {
                feePaymentAmount1 = SettlementHelpers.parseFeePaymentEvent(feePaymentEvents[0].data);
            } else {
                feePaymentAmount0 = SettlementHelpers.parseFeePaymentEvent(feePaymentEvents[0].data);
            }
        }
        if (feePaymentEvents.length > 1) {
            if (didToken0ArriveFirst) {
                feePaymentAmount0 = SettlementHelpers.parseFeePaymentEvent(feePaymentEvents[1].data);
            } else {
                feePaymentAmount1 = SettlementHelpers.parseFeePaymentEvent(feePaymentEvents[1].data);
            }
        }
        // check transfer events
        Vm.Log[] memory transferEvents = SettlementHelpers.findTransferToUserEvents(entries, user);
        uint256 transferAmount0 = 0;
        uint256 transferAmount1 = 0;
        if (transferEvents.length > 0) {
            transferAmount0 = SettlementHelpers.parseTransferToUserEvent(transferEvents[0]);
        }
        if (transferEvents.length > 1) {
            transferAmount1 = SettlementHelpers.parseTransferToUserEvent(transferEvents[1]);
        }
        // verify amounts
        assertEq(expectedAmount0, mintAmount0 + feePaymentAmount0 + transferAmount0);
        assertEq(expectedAmount1, mintAmount1 + feePaymentAmount1 + transferAmount1);
    }

    function assertCorrectAmountsDualTokenForNativeTokenPositions(
        Vm.Log[] memory entries,
        PoolKey memory poolKey,
        bool didToken0ArriveFirst,
        uint256 expectedAmount0,
        uint256 expectedAmount1
    ) public view {
        // check transfer events for minting, as ModifyLiquidity doesn't include amounts
        // this will only give ERC20 amounts, not native token amounts
        Vm.Log[] memory transferToPoolManagerEvents =
            findTransferToPoolEventsAfterModifyLiquidity(entries, address(v4PoolManager));
        uint256 mintAmount0 = 0;
        uint256 mintAmount1 = 0;
        if (transferToPoolManagerEvents.length > 0) {
            (mintAmount0, mintAmount1) = parseTransferToPoolManagerEvents(transferToPoolManagerEvents, poolKey);
        }
        // now get ModifyLiquidity events
        Vm.Log memory modifyLiquidityEvent = findModifyLiquidityEvent(entries);
        uint256 liquidity = 0;
        int24 tickLower = 0;
        int24 tickUpper = 0;
        if (modifyLiquidityEvent.data.length > 0) {
            (tickLower, tickUpper, liquidity) = parseModifyLiquidityEvent(modifyLiquidityEvent.data);
            uint256 amount0 = getAmount0(address(v4StateView), poolKey, tickLower, tickUpper, uint128(liquidity));
            mintAmount0 += amount0;
        }
        // check fee payment events
        Vm.Log[] memory feePaymentEvents = SettlementHelpers.findFeePaymentEvents(entries);
        uint256 feePaymentAmount0 = 0;
        uint256 feePaymentAmount1 = 0;
        if (feePaymentEvents.length > 0) {
            if (didToken0ArriveFirst) {
                feePaymentAmount1 = SettlementHelpers.parseFeePaymentEvent(feePaymentEvents[0].data);
            } else {
                feePaymentAmount0 = SettlementHelpers.parseFeePaymentEvent(feePaymentEvents[0].data);
            }
        }
        if (feePaymentEvents.length > 1) {
            if (didToken0ArriveFirst) {
                feePaymentAmount0 = SettlementHelpers.parseFeePaymentEvent(feePaymentEvents[1].data);
            } else {
                feePaymentAmount1 = SettlementHelpers.parseFeePaymentEvent(feePaymentEvents[1].data);
            }
        }
        // check transfer events
        Vm.Log[] memory transferEvents = SettlementHelpers.findTransferToUserEvents(entries, user);
        uint256 transferAmount0 = 0;
        uint256 transferAmount1 = 0;
        if (transferEvents.length > 0) {
            transferAmount0 = SettlementHelpers.parseTransferToUserEvent(transferEvents[0]);
        }
        if (transferEvents.length > 1) {
            transferAmount1 = SettlementHelpers.parseTransferToUserEvent(transferEvents[1]);
        }
        // verify amounts
        assertEq(expectedAmount0, mintAmount0 + feePaymentAmount0 + transferAmount0);
        assertEq(expectedAmount1, mintAmount1 + feePaymentAmount1 + transferAmount1);
    }

    /**
     * MigrationId fails and is ignored
     */
    function test_handleDirectTransfer_failsHashAndIsIgnored() public {
        deal(weth, address(settler), wethAmount);
        vm.recordLogs();

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(weth),
            currency1: Currency.wrap(usdc),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });

        // generate data
        (bytes32 migrationId, bytes memory data) = genSettlerData(poolKey, SettlementHelpers.Range.InRange, true);
        (, MigrationData memory migrationData) = abi.decode(data, (bytes32, MigrationData));
        bytes32 fakeMigrationId = bytes32(abi.encode(bytes("fake")));
        bytes memory fakeData = abi.encode(fakeMigrationId, migrationData);

        // call handleDirectTransfer
        vm.expectRevert(IDirectSettler.InvalidMigration.selector);
        settler.handleDirectTransfer(weth, wethAmount, fakeData);

        // verify no amounts were transferred
        assertEq(IERC20(weth).balanceOf(address(settler)), wethAmount);
        assertEq(IERC20(usdc).balanceOf(address(settler)), 0);

        // verify settlement cache is not set
        assertEq(settler.checkSettlementCache(fakeMigrationId), false);
        assertEq(settler.checkSettlementCache(migrationId), false);
    }

    /**
     * SINGLE TOKEN PATHS - Native Token scenarios
     */
    function test_handleDirectTransfer_ST_NativeToken_failsAndRefunds() public {
        deal(weth, address(settler), wethAmount);
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(0)), // native token
            currency1: Currency.wrap(usdc),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });

        // generate data with high amount0Min and amount1Min so it'll fail to mint
        (bytes32 migrationId, bytes memory data) =
            genSettlerDataWithAmounts(poolKey, SettlementHelpers.Range.InRange, true, 1 ether, 1 ether);

        // Receipt
        vm.expectEmit(true, true, false, true);
        emit ISettler.Receipt(migrationId, weth, wethAmount);

        // expect the entire weth amount to be transferred to user
        vm.expectEmit(true, true, false, true, address(weth));
        emit IERC20.Transfer(address(settler), address(user), wethAmount);
        // expect a refund
        vm.expectEmit(true, true, true, true);
        emit ISettler.Refund(migrationId, address(user), weth, wethAmount);

        // call handleDirectTransfer
        settler.handleDirectTransfer(weth, wethAmount, data);
    }

    function test_handleDirectTransfer_ST_NativeToken_InRange() public {
        deal(weth, address(settler), wethAmount);
        vm.recordLogs();

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(0)), // native token
            currency1: Currency.wrap(usdc),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });

        // generate data
        (bytes32 migrationId, bytes memory data) = genSettlerData(poolKey, SettlementHelpers.Range.InRange, true);

        // Receipt
        vm.expectEmit(true, true, false, true);
        emit ISettler.Receipt(migrationId, weth, wethAmount);

        // Swap

        // ModifyLiquidity

        // Transfer Position from 0x0 to user
        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationId,
            weth,
            uint256(totalProtocolFeeBps) * wethAmount / 10000,
            uint256(netSenderFeeBps) * wethAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationId, user, tokenId);

        // call handleDirectTransfer
        settler.handleDirectTransfer(weth, wethAmount, data);

        assertCorrectAmountsForNativeTokenPositions(vm.getRecordedLogs(), poolKey, wethAmount, 0);
    }

    function test_handleDirectTransfer_ST_NativeToken_BelowCurrentTick() public {
        deal(weth, address(settler), wethAmount);
        vm.recordLogs();

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(0)), // native token
            currency1: Currency.wrap(usdc),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });

        // generate data; below tick means only token1 is needed
        (bytes32 migrationId, bytes memory data) = genSettlerData(poolKey, SettlementHelpers.Range.BelowTick, true);

        // Receipt
        vm.expectEmit(true, true, false, true);
        emit ISettler.Receipt(migrationId, weth, wethAmount);

        // Swap

        // ModifyLiquidity

        // Transfer Position from 0x0 to user
        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationId,
            weth,
            uint256(totalProtocolFeeBps) * wethAmount / 10000,
            uint256(netSenderFeeBps) * wethAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationId, user, tokenId);

        // call handleDirectTransfer
        settler.handleDirectTransfer(weth, wethAmount, data);

        assertCorrectAmountsForNativeTokenPositions(vm.getRecordedLogs(), poolKey, wethAmount, 0);
    }

    function test_handleDirectTransfer_ST_NativeToken_AboveCurrentTick() public {
        deal(weth, address(settler), wethAmount);
        vm.recordLogs();

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(0)), // native token
            currency1: Currency.wrap(usdc),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });

        // generate data; above tick means only token0 is needed
        (bytes32 migrationId, bytes memory data) = genSettlerData(poolKey, SettlementHelpers.Range.AboveTick, true);

        // Receipt
        vm.expectEmit(true, true, false, true);
        emit ISettler.Receipt(migrationId, weth, wethAmount);

        // No swap expected for above tick (only token0 needed)

        // ModifyLiquidity

        // Transfer Position from 0x0 to user
        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationId,
            weth,
            uint256(totalProtocolFeeBps) * wethAmount / 10000,
            uint256(netSenderFeeBps) * wethAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationId, user, tokenId);

        // call handleDirectTransfer
        settler.handleDirectTransfer(weth, wethAmount, data);

        assertCorrectAmountsForNativeTokenPositions(vm.getRecordedLogs(), poolKey, wethAmount, 0);
    }

    /**
     * SINGLE TOKEN PATHS - Token0BaseToken scenarios (WETH/USDC)
     */
    function test_handleDirectTransfer_ST_Token0BaseToken_failsAndRefunds() public {
        deal(weth, address(settler), wethAmount);
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(weth),
            currency1: Currency.wrap(usdc),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });

        // generate data with high amount0Min and amount1Min so it'll fail to mint
        (bytes32 migrationId, bytes memory data) =
            genSettlerDataWithAmounts(poolKey, SettlementHelpers.Range.InRange, true, 1 ether, 1 ether);

        // Receipt
        vm.expectEmit(true, true, false, true);
        emit ISettler.Receipt(migrationId, weth, wethAmount);

        // expect the entire weth amount to be transferred to user
        vm.expectEmit(true, true, false, true, address(weth));
        emit IERC20.Transfer(address(settler), address(user), wethAmount);
        // expect a refund
        vm.expectEmit(true, true, true, true);
        emit ISettler.Refund(migrationId, address(user), weth, wethAmount);

        // call handleDirectTransfer
        settler.handleDirectTransfer(weth, wethAmount, data);
    }

    function test_handleDirectTransfer_ST_Token0BaseToken_InRange() public {
        deal(weth, address(settler), wethAmount);
        vm.recordLogs();

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(weth),
            currency1: Currency.wrap(usdc),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });

        // generate data
        (bytes32 migrationId, bytes memory data) = genSettlerData(poolKey, SettlementHelpers.Range.InRange, true);

        // Receipt
        vm.expectEmit(true, true, false, true);
        emit ISettler.Receipt(migrationId, weth, wethAmount);

        // Swap

        // ModifyLiquidity

        // Transfer Position from 0x0 to user
        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationId,
            weth,
            uint256(totalProtocolFeeBps) * wethAmount / 10000,
            uint256(netSenderFeeBps) * wethAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationId, user, tokenId);

        // call handleDirectTransfer
        settler.handleDirectTransfer(weth, wethAmount, data);

        assertCorrectAmounts(vm.getRecordedLogs(), poolKey, true, wethAmount, 0);
    }

    function test_handleDirectTransfer_ST_Token0BaseToken_BelowCurrentTick() public {
        deal(weth, address(settler), wethAmount);
        vm.recordLogs();

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(weth),
            currency1: Currency.wrap(usdc),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });

        // generate data; below tick means only token1 is needed
        (bytes32 migrationId, bytes memory data) = genSettlerData(poolKey, SettlementHelpers.Range.BelowTick, true);

        // Receipt
        vm.expectEmit(true, true, false, true);
        emit ISettler.Receipt(migrationId, weth, wethAmount);

        // call handleDirectTransfer - may refund due to pool state
        settler.handleDirectTransfer(weth, wethAmount, data);

        // Check that either settlement or refund happened
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool hasSettlement = false;
        bool hasRefund = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Settlement(bytes32,address,uint256)")) {
                hasSettlement = true;
            } else if (logs[i].topics[0] == keccak256("Refund(bytes32,address,address,uint256)")) {
                hasRefund = true;
            }
        }
        assertTrue(hasSettlement || hasRefund, "Should either settle or refund");
    }

    function test_handleDirectTransfer_ST_Token0BaseToken_AboveCurrentTick() public {
        deal(weth, address(settler), wethAmount);
        vm.recordLogs();

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(weth),
            currency1: Currency.wrap(usdc),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });

        // generate data; above tick means only token0 is needed
        (bytes32 migrationId, bytes memory data) = genSettlerData(poolKey, SettlementHelpers.Range.AboveTick, true);

        // Receipt
        vm.expectEmit(true, true, false, true);
        emit ISettler.Receipt(migrationId, weth, wethAmount);

        // No swap expected for above tick (only token0 needed)

        // ModifyLiquidity

        // Transfer Position from 0x0 to user
        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationId,
            weth,
            uint256(totalProtocolFeeBps) * wethAmount / 10000,
            uint256(netSenderFeeBps) * wethAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationId, user, tokenId);

        // call handleDirectTransfer
        settler.handleDirectTransfer(weth, wethAmount, data);

        assertCorrectAmounts(vm.getRecordedLogs(), poolKey, true, wethAmount, 0);
    }

    /**
     * SINGLE TOKEN PATHS - Token1BaseToken scenarios (USDC/WETH)
     */
    function test_handleDirectTransfer_ST_Token1BaseToken_failsAndRefunds() public {
        deal(weth, address(settler), wethAmount);
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(usdc),
            currency1: Currency.wrap(weth),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });

        // generate data with high amount0Min and amount1Min so it'll fail to mint
        (bytes32 migrationId, bytes memory data) =
            genSettlerDataWithAmounts(poolKey, SettlementHelpers.Range.InRange, false, 1 ether, 1 ether);

        // Receipt
        vm.expectEmit(true, true, false, true);
        emit ISettler.Receipt(migrationId, weth, wethAmount);

        // expect the entire weth amount to be transferred to user
        vm.expectEmit(true, true, false, true, address(weth));
        emit IERC20.Transfer(address(settler), address(user), wethAmount);
        // expect a refund
        vm.expectEmit(true, true, true, true);
        emit ISettler.Refund(migrationId, address(user), weth, wethAmount);

        // call handleDirectTransfer
        settler.handleDirectTransfer(weth, wethAmount, data);
    }

    function test_handleDirectTransfer_ST_Token1BaseToken_InRange() public {
        deal(weth, address(settler), wethAmount);
        vm.recordLogs();

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(usdc),
            currency1: Currency.wrap(weth),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });

        // generate data
        (bytes32 migrationId, bytes memory data) = genSettlerData(poolKey, SettlementHelpers.Range.InRange, false);

        // Receipt
        vm.expectEmit(true, true, false, true);
        emit ISettler.Receipt(migrationId, weth, wethAmount);

        // call handleDirectTransfer - may refund due to pool state
        settler.handleDirectTransfer(weth, wethAmount, data);

        // Check that either settlement or refund happened
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool hasSettlement = false;
        bool hasRefund = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Settlement(bytes32,address,uint256)")) {
                hasSettlement = true;
            } else if (logs[i].topics[0] == keccak256("Refund(bytes32,address,address,uint256)")) {
                hasRefund = true;
            }
        }
        assertTrue(hasSettlement || hasRefund, "Should either settle or refund");
    }

    /**
     * DUAL TOKEN PATHS - Native Token scenarios
     */
    function test_handleDirectTransfer_DT_NativeToken_FirstBridgeCallFailsWhenFirstAmountTooLowAndIsIgnored() public {
        vm.recordLogs();
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(0)), // native token
            currency1: Currency.wrap(usdc),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });

        // generate data
        (bytes32 migrationId, bytes memory data) =
            genSettlerDataForDualToken(poolKey, SettlementHelpers.Range.InRange, true, wethAmount - 1, usdcAmount - 1);

        // call handleDirectTransfer
        vm.expectRevert(bytes(""));
        settler.handleDirectTransfer(weth, wethAmount - 10, data);

        // verify no amounts were transferred
        assertEq(IERC20(weth).balanceOf(address(settler)), 0);
        assertEq(IERC20(usdc).balanceOf(address(settler)), 0);

        // verify settlement cache is not set
        assertEq(settler.checkSettlementCache(migrationId), false);
    }

    function test_handleDirectTransfer_DT_NativeToken_InRange_ExistingPool_Token0ArrivesBeforeToken1() public {
        deal(weth, address(settler), wethAmount);
        deal(usdc, address(settler), usdcAmount);

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(0)), // native token
            currency1: Currency.wrap(usdc),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });

        // generate data
        (bytes32 migrationId, bytes memory data) =
            genSettlerDataForDualToken(poolKey, SettlementHelpers.Range.InRange, true, wethAmount, usdcAmount);

        // first call to handleDirectTransfer; succeeds
        settler.handleDirectTransfer(weth, wethAmount, data);
        assertEq(settler.checkSettlementCache(migrationId), true);

        vm.recordLogs();
        // Receipt
        vm.expectEmit(true, true, false, true);
        emit ISettler.Receipt(migrationId, usdc, usdcAmount);

        // ModifyLiquidity

        // Transfer Position from 0x0 to user
        // Fee payments
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationId,
            usdc,
            uint256(totalProtocolFeeBps) * usdcAmount / 10000,
            uint256(netSenderFeeBps) * usdcAmount / 10000
        );

        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationId,
            weth,
            uint256(totalProtocolFeeBps) * wethAmount / 10000,
            uint256(netSenderFeeBps) * wethAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationId, user, tokenId);

        // second call to handleDirectTransfer
        settler.handleDirectTransfer(usdc, usdcAmount, data);

        assertCorrectAmountsDualTokenForNativeTokenPositions(
            vm.getRecordedLogs(), poolKey, true, wethAmount, usdcAmount
        );
    }

    /**
     * DUAL TOKEN PATHS - Token0WETH scenarios
     */
    function test_handleDirectTransfer_DT_Token0WETH_InRange_ExistingPool_Token0ArrivesBeforeToken1() public {
        deal(weth, address(settler), wethAmount);
        deal(usdc, address(settler), usdcAmount);

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(weth),
            currency1: Currency.wrap(usdc),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });

        // generate data
        (bytes32 migrationId, bytes memory data) =
            genSettlerDataForDualToken(poolKey, SettlementHelpers.Range.InRange, true, wethAmount, usdcAmount);

        // first call to handleDirectTransfer; succeeds
        settler.handleDirectTransfer(weth, wethAmount, data);
        assertEq(settler.checkSettlementCache(migrationId), true);

        vm.recordLogs();
        // Receipt
        vm.expectEmit(true, true, false, true);
        emit ISettler.Receipt(migrationId, usdc, usdcAmount);

        // ModifyLiquidity

        // Transfer Position from 0x0 to user
        // Fee payments
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationId,
            usdc,
            uint256(totalProtocolFeeBps) * usdcAmount / 10000,
            uint256(netSenderFeeBps) * usdcAmount / 10000
        );

        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationId,
            weth,
            uint256(totalProtocolFeeBps) * wethAmount / 10000,
            uint256(netSenderFeeBps) * wethAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationId, user, tokenId);

        // second call to handleDirectTransfer
        settler.handleDirectTransfer(usdc, usdcAmount, data);

        assertCorrectAmountsDualToken(vm.getRecordedLogs(), poolKey, true, wethAmount, usdcAmount);
    }

    function test() public override(TestContext, UniswapV4Helpers) {}
}
