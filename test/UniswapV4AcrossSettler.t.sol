// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {TestContext} from "./utils/TestContext.sol";
import {ISettler} from "../src/interfaces/ISettler.sol";
import {IUniswapV4Settler} from "../src/interfaces/IUniswapV4Settler.sol";
import {IAcrossSettler} from "../src/interfaces/IAcrossSettler.sol";
import {UniswapV4AcrossSettlerHarness} from "./mocks/UniswapV4AcrossSettlerHarness.sol";
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

contract UniswapV4AcrossSettlerTest is TestContext, UniswapV4Helpers {
    string public constant CHAIN_NAME = "BASE";
    UniswapV4AcrossSettlerHarness public settler;
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
        settler = new UniswapV4AcrossSettlerHarness(
            owner,
            address(v4PositionManager),
            address(universalRouter),
            address(permit2),
            address(acrossSpokePool),
            address(weth)
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
        returns (bytes32 migrationHash, bytes memory data)
    {
        int24 currentTick = UniswapV4Helpers.getCurrentTick(address(v4StateView), poolKey);
        (migrationHash, data) = SettlementHelpers.generateSettlerData(
            SettlementHelpers.generateV4SettlementParamsUsingCurrentTick(
                user, poolKey, 0, currentTick, range, 0, 0, isToken0BaseToken, senderShareBps
            ),
            MigrationModes.SINGLE,
            ""
        );
        return (migrationHash, data);
    }

    function genSettlerDataWithSqrtPriceX96(
        PoolKey memory poolKey,
        SettlementHelpers.Range range,
        bool isToken0BaseToken,
        uint160 sqrtPriceX96
    ) public view returns (bytes32 migrationHash, bytes memory data) {
        int24 currentTick = 10000;
        (migrationHash, data) = SettlementHelpers.generateSettlerData(
            SettlementHelpers.generateV4SettlementParamsUsingCurrentTick(
                user, poolKey, sqrtPriceX96, currentTick, range, 0, 0, isToken0BaseToken, senderShareBps
            ),
            MigrationModes.SINGLE,
            ""
        );
        return (migrationHash, data);
    }

    function genSettlerDataWithAmounts(
        PoolKey memory poolKey,
        SettlementHelpers.Range range,
        bool isToken0BaseToken,
        uint256 amount0Min,
        uint256 amount1Min
    ) public view returns (bytes32 migrationHash, bytes memory data) {
        int24 currentTick = UniswapV4Helpers.getCurrentTick(address(v4StateView), poolKey);
        (migrationHash, data) = SettlementHelpers.generateSettlerData(
            SettlementHelpers.generateV4SettlementParamsUsingCurrentTick(
                user, poolKey, 0, currentTick, range, amount0Min, amount1Min, isToken0BaseToken, senderShareBps
            ),
            MigrationModes.SINGLE,
            ""
        );
        return (migrationHash, data);
    }

    function genSettlerDataForDualToken(
        PoolKey memory poolKey,
        SettlementHelpers.Range range,
        bool isToken0BaseToken,
        uint256 routeMinAmount0,
        uint256 routeMinAmount1
    ) public view returns (bytes32 migrationHash, bytes memory data) {
        int24 currentTick = UniswapV4Helpers.getCurrentTick(address(v4StateView), poolKey);
        // need to handle native token case
        address currency0 = Currency.unwrap(poolKey.currency0) == address(0) ? weth : Currency.unwrap(poolKey.currency0);
        (migrationHash, data) = SettlementHelpers.generateSettlerData(
            SettlementHelpers.generateV4SettlementParamsUsingCurrentTick(
                user, poolKey, 0, currentTick, range, 0, 0, isToken0BaseToken, senderShareBps
            ),
            MigrationModes.DUAL,
            abi.encode(currency0, Currency.unwrap(poolKey.currency1), routeMinAmount0, routeMinAmount1)
        );
        return (migrationHash, data);
    }

    function genSettlerDataForDualTokenWithSqrtPriceX96(
        PoolKey memory poolKey,
        SettlementHelpers.Range range,
        bool isToken0BaseToken,
        uint256 routeMinAmount0,
        uint256 routeMinAmount1,
        uint160 sqrtPriceX96
    ) public view returns (bytes32 migrationHash, bytes memory data) {
        int24 currentTick = 10000;
        // need to handle native token case
        address currency0 = Currency.unwrap(poolKey.currency0) == address(0) ? weth : Currency.unwrap(poolKey.currency0);
        (migrationHash, data) = SettlementHelpers.generateSettlerData(
            SettlementHelpers.generateV4SettlementParamsUsingCurrentTick(
                user, poolKey, sqrtPriceX96, currentTick, range, 0, 0, isToken0BaseToken, senderShareBps
            ),
            MigrationModes.DUAL,
            abi.encode(currency0, Currency.unwrap(poolKey.currency1), routeMinAmount0, routeMinAmount1)
        );
        return (migrationHash, data);
    }

    function genSettlerDataForDualTokenWithAmounts(
        PoolKey memory poolKey,
        SettlementHelpers.Range range,
        bool isToken0BaseToken,
        uint256 routeMinAmount0,
        uint256 routeMinAmount1,
        uint256 amount0Min,
        uint256 amount1Min
    ) public view returns (bytes32 migrationHash, bytes memory data) {
        int24 currentTick = UniswapV4Helpers.getCurrentTick(address(v4StateView), poolKey);
        // need to handle native token case
        address currency0 = Currency.unwrap(poolKey.currency0) == address(0) ? weth : Currency.unwrap(poolKey.currency0);
        (migrationHash, data) = SettlementHelpers.generateSettlerData(
            SettlementHelpers.generateV4SettlementParamsUsingCurrentTick(
                user, poolKey, 0, currentTick, range, amount0Min, amount1Min, isToken0BaseToken, senderShareBps
            ),
            MigrationModes.DUAL,
            abi.encode(currency0, Currency.unwrap(poolKey.currency1), routeMinAmount0, routeMinAmount1)
        );
        return (migrationHash, data);
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
        // console.log("mintAmount0", mintAmount0);
        // console.log("mintAmount1", mintAmount1);
        // console.log("swapAmountIn", swapAmountIn);
        // console.log("swapAmountOut", swapAmountOut);
        // console.log("feePaymentAmount", feePaymentAmount);
        // console.log("transferAmount0", transferAmount0);
        // console.log("transferAmount1", transferAmount1);
        // console.log("expectedAmount0", expectedAmount0);
        // console.log("expectedAmount1", expectedAmount1);
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
        // console.log("mintAmount0", mintAmount0);
        // console.log("mintAmount1", mintAmount1);
        // console.log("swapAmountIn", swapAmountIn);
        // console.log("swapAmountOut", swapAmountOut);
        // console.log("feePaymentAmount", feePaymentAmount);
        // console.log("transferAmount0", transferAmount0);
        // console.log("transferAmount1", transferAmount1);
        // console.log("expectedAmount0", expectedAmount0);
        // console.log("expectedAmount1", expectedAmount1);

        // verify amounts
        assertEq(expectedAmount0, mintAmount0 + swapAmountIn + feePaymentAmount + transferAmount0);
        assertEq(expectedAmount1, mintAmount1 + transferAmount1 - swapAmountOut); // ordering important since it's uint256
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
        // console.log("mintAmount0", mintAmount0);
        // console.log("mintAmount1", mintAmount1);
        // console.log("feePaymentAmount0", feePaymentAmount0);
        // console.log("feePaymentAmount1", feePaymentAmount1);
        // console.log("transferAmount0", transferAmount0);
        // console.log("transferAmount1", transferAmount1);
        // console.log("expectedAmount0", expectedAmount0);
        // console.log("expectedAmount1", expectedAmount1);
        // verify amounts
        assertEq(expectedAmount0, mintAmount0 + feePaymentAmount0 + transferAmount0);
        assertEq(expectedAmount1, mintAmount1 + feePaymentAmount1 + transferAmount1); // ordering important since it's uint256
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
        // console.log("mintAmount0", mintAmount0);
        // console.log("mintAmount1", mintAmount1);
        // console.log("feePaymentAmount0", feePaymentAmount0);
        // console.log("feePaymentAmount1", feePaymentAmount1);
        // console.log("transferAmount0", transferAmount0);
        // console.log("transferAmount1", transferAmount1);
        // console.log("expectedAmount0", expectedAmount0);
        // console.log("expectedAmount1", expectedAmount1);
        // verify amounts
        assertEq(expectedAmount0, mintAmount0 + feePaymentAmount0 + transferAmount0);
        assertEq(expectedAmount1, mintAmount1 + feePaymentAmount1 + transferAmount1); // ordering important since it's uint256
    }

    /*
    Paths to include in tests:
    - migrationHash check (before either path)
    - Single token path
    - Dual token path (only applicable to both tokens being base tokens and in range)

    TokenPairs to include in tests:
    - native/usdc (native: eth, token1: usdc/erc20) [only needed for V4Settler]
    - weth/usdc (token0: weth/basetoken, token1: usdc)
    - usdc/weth (token0: usdc/erc20, token1: weth/basetoken)
    - usdc/usdt (non-weth base token)

    Ranges & final states to include in tests:
    - fails and is ignored (hash doesn't match)
    - fails and is ignored (hash matches but first amount is too low) (dual token only)
    - fails and is ignored (hash matches but second amount is too low) (dual Token only)
    - fails and is ignored (hash matches but token doesn't match)
    - fails and refunds one
    - fails and refunds both (dual token only)
    - succeeds creating a new pool
    - succeeds using an existing pool
      - below tickLower
      - between tickLower and tickUpper
      - above tickUpper
    */

    /**
     * MigrationHash fails and is ignored
     */
    function test_handleV3AcrossMessage_failsHashAndIsIgnored() public {
        deal(weth, address(settler), wethAmount);
        vm.recordLogs();
        // generate data
        PoolKey memory poolKey = PoolKey(Currency.wrap(weth), Currency.wrap(usdc), 500, 10, IHooks(address(0)));
        (bytes32 migrationHash, bytes memory data) = genSettlerData(poolKey, SettlementHelpers.Range.InRange, true);
        (, MigrationData memory migrationData) = abi.decode(data, (bytes32, MigrationData));
        bytes32 fakeMigrationHash = bytes32(abi.encode(bytes("fake")));
        bytes memory fakeData = abi.encode(fakeMigrationHash, migrationData);

        // call handleV3AcrossMessage
        vm.prank(address(acrossSpokePool));
        vm.expectRevert(bytes("")); // important to use bytes("") as this revert should contain no data
        settler.handleV3AcrossMessage(weth, wethAmount, address(0), fakeData);

        // verify no amounts were transferred
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0); // no logs were emitted
        assertEq(IERC20(weth).balanceOf(address(settler)), wethAmount);
        assertEq(IERC20(usdc).balanceOf(address(settler)), 0);

        // verify settlement cache is not set
        assertEq(settler.checkSettlementCache(fakeMigrationHash), false);
        assertEq(settler.checkSettlementCache(migrationHash), false);
    }
    // /**
    //  * SINGLE TOKEN PATHS ***
    //  */

    // Native/USDC scenarios
    function test_handleV3AcrossMessage_ST_NativeToken_failsAndRefunds() public {
        // generate data with high amount0Min and amount1Min so it'll fail to mint
        deal(weth, address(settler), wethAmount);
        PoolKey memory poolKey = PoolKey(Currency.wrap(address(0)), Currency.wrap(usdc), 500, 10, IHooks(address(0)));
        (, bytes memory data) =
            genSettlerDataWithAmounts(poolKey, SettlementHelpers.Range.InRange, true, 1 ether, 1 ether);

        // expect the entire weth amount to be transferred to user
        vm.expectEmit(true, true, false, true, address(weth));
        emit IERC20.Transfer(address(settler), address(user), wethAmount);

        // call handleV3AcrossMessage
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(weth, wethAmount, address(0), data);
    }

    function test_handleV3AcrossMessage_ST_NativeToken_InRange() public {
        PoolKey memory poolKey = PoolKey(Currency.wrap(address(0)), Currency.wrap(usdc), 500, 10, IHooks(address(0)));
        deal(weth, address(settler), wethAmount);
        PoolId poolId = PoolIdLibrary.toId(poolKey);

        vm.recordLogs();
        // generate data
        (bytes32 migrationHash, bytes memory data) = genSettlerData(poolKey, SettlementHelpers.Range.InRange, true);

        // swap event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Swap(poolId, address(universalRouter), 0, 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, false, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // Sweep remaining tokens to user
        vm.expectEmit(true, true, false, false, address(weth));
        emit IERC20.Transfer(address(settler), address(user), 0);
        vm.expectEmit(true, true, false, false, address(usdc));
        emit IERC20.Transfer(address(settler), address(user), 0);

        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            weth,
            uint256(totalProtocolFeeBps) * wethAmount / 10000,
            uint256(netSenderFeeBps) * wethAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationHash, user, tokenId);

        // Receipt
        vm.expectEmit(true, true, true, true);
        emit IAcrossSettler.Receipt(migrationHash, user, weth, wethAmount);

        // call handleV3AcrossMessage
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(weth, wethAmount, address(0), data);

        assertCorrectAmountsForNativeTokenPositions(vm.getRecordedLogs(), poolKey, wethAmount, 0);
    }

    function test_handleV3AcrossMessage_ST_NativeToken_BelowCurrentTick() public {
        PoolKey memory poolKey = PoolKey(Currency.wrap(address(0)), Currency.wrap(usdc), 500, 10, IHooks(address(0)));
        deal(weth, address(settler), wethAmount);
        PoolId poolId = PoolIdLibrary.toId(poolKey);

        vm.recordLogs();
        // generate data; below tick means only token1 is needed
        (bytes32 migrationHash, bytes memory data) = genSettlerData(poolKey, SettlementHelpers.Range.BelowTick, true);

        // swap event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Swap(poolId, address(universalRouter), 0, 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, false, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // Sweep remaining tokens to user
        // should be no tokens to sweep, as everything used to mint

        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            weth,
            uint256(totalProtocolFeeBps) * wethAmount / 10000,
            uint256(netSenderFeeBps) * wethAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, false);
        emit ISettler.Settlement(migrationHash, user, tokenId);

        // Receipt
        vm.expectEmit(true, true, true, true);
        emit IAcrossSettler.Receipt(migrationHash, user, weth, wethAmount);

        // call handleV3AcrossMessage
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(weth, wethAmount, address(0), data);

        // can use assertCorrectAmounts for native token positions in this case
        // because there is not token0 in this position
        assertCorrectAmounts(vm.getRecordedLogs(), poolKey, true, wethAmount, 0);
    }

    function test_handleV3AcrossMessage_ST_NativeToken_AboveCurrentTick() public {
        PoolKey memory poolKey = PoolKey(Currency.wrap(address(0)), Currency.wrap(usdc), 500, 10, IHooks(address(0)));
        deal(weth, address(settler), wethAmount);
        PoolId poolId = PoolIdLibrary.toId(poolKey);

        vm.recordLogs();
        // generate data; above tick means only token0 is needed
        (bytes32 migrationHash, bytes memory data) = genSettlerData(poolKey, SettlementHelpers.Range.AboveTick, true);

        // swap event
        // no swap event expected

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, false, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // Sweep remaining tokens to user
        // should be no tokens to sweep, as everything used to mint

        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            weth,
            uint256(totalProtocolFeeBps) * wethAmount / 10000,
            uint256(netSenderFeeBps) * wethAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, false);
        emit ISettler.Settlement(migrationHash, user, tokenId);

        // Receipt
        vm.expectEmit(true, true, true, true);
        emit IAcrossSettler.Receipt(migrationHash, user, weth, wethAmount);

        // call handleV3AcrossMessage
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(weth, wethAmount, address(0), data);

        assertCorrectAmountsForNativeTokenPositions(vm.getRecordedLogs(), poolKey, wethAmount, 0);
    }

    function test_handleV3AcrossMessage_ST_NativeToken_SingleSided_NewPool() public {
        MockUSDC mockUSDC = new MockUSDC("Mock USDT", "USDT", address(settler), usdcAmount);

        PoolKey memory poolKey =
            PoolKey(Currency.wrap(address(0)), Currency.wrap(address(mockUSDC)), 500, 10, IHooks(address(0)));
        deal(weth, address(settler), wethAmount);
        PoolId poolId = PoolIdLibrary.toId(poolKey);

        vm.recordLogs();
        // generate data; above tick means only token0 is needed
        (bytes32 migrationHash, bytes memory data) =
            genSettlerDataWithSqrtPriceX96(poolKey, SettlementHelpers.Range.AboveTick, true, 2 ** 96);

        // swap event
        // no swap event expected

        // pool creation event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Initialize(
            poolId, Currency.wrap(address(0)), Currency.wrap(address(mockUSDC)), 500, 10, IHooks(address(0)), 2 ** 96, 0
        );

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, false, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // Sweep remaining tokens to user
        // should be no tokens to sweep, as everything used to mint

        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            weth,
            uint256(totalProtocolFeeBps) * wethAmount / 10000,
            uint256(netSenderFeeBps) * wethAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationHash, user, tokenId);

        // Receipt
        vm.expectEmit(true, true, true, true);
        emit IAcrossSettler.Receipt(migrationHash, user, weth, wethAmount);

        // call handleV3AcrossMessage
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(weth, wethAmount, address(0), data);

        assertCorrectAmountsForNativeTokenPositions(vm.getRecordedLogs(), poolKey, wethAmount, 0);
    }

    // Token0WETH/BaseToken scenarios
    function test_handleV3AcrossMessage_ST_Token0BaseToken_failsAndRefunds() public {
        // generate data with high amount0Min and amount1Min so it'll fail to mint
        deal(weth, address(settler), wethAmount);
        PoolKey memory poolKey = PoolKey(Currency.wrap(weth), Currency.wrap(usdc), 500, 10, IHooks(address(0)));
        (, bytes memory data) =
            genSettlerDataWithAmounts(poolKey, SettlementHelpers.Range.InRange, true, 1 ether, 1 ether);

        // expect the entire weth amount to be transferred to user
        vm.expectEmit(true, true, false, true, address(weth));
        emit IERC20.Transfer(address(settler), address(user), wethAmount);

        // call handleV3AcrossMessage
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(weth, wethAmount, address(0), data);
    }

    function test_handleV3AcrossMessage_ST_Token0BaseToken_InRange() public {
        PoolKey memory poolKey = PoolKey(Currency.wrap(weth), Currency.wrap(usdc), 500, 10, IHooks(address(0)));
        UniswapV4Helpers.mintBigV4PositionToPopulatePool(
            address(v4PositionManager), address(permit2), user, poolKey, -600000, 100000, 1_000_000_000_000_000
        );
        deal(weth, address(settler), wethAmount);
        PoolId poolId = PoolIdLibrary.toId(poolKey);

        vm.recordLogs();
        // generate data
        (bytes32 migrationHash, bytes memory data) = genSettlerData(poolKey, SettlementHelpers.Range.InRange, true);

        // swap event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Swap(poolId, address(universalRouter), 0, 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), user, tokenId + 1);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // Sweep remaining tokens to user
        vm.expectEmit(true, true, false, false, address(weth));
        emit IERC20.Transfer(address(settler), address(user), 0);
        vm.expectEmit(true, true, false, false, address(usdc));
        emit IERC20.Transfer(address(settler), address(user), 0);

        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            weth,
            uint256(totalProtocolFeeBps) * wethAmount / 10000,
            uint256(netSenderFeeBps) * wethAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationHash, user, tokenId + 1);

        // Receipt
        vm.expectEmit(true, true, true, true);
        emit IAcrossSettler.Receipt(migrationHash, user, weth, wethAmount);

        // call handleV3AcrossMessage
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(weth, wethAmount, address(0), data);

        assertCorrectAmounts(vm.getRecordedLogs(), poolKey, true, wethAmount, 0);
    }

    function test_handleV3AcrossMessage_ST_Token0BaseToken_BelowCurrentTick() public {
        PoolKey memory poolKey = PoolKey(Currency.wrap(weth), Currency.wrap(usdc), 500, 10, IHooks(address(0)));
        UniswapV4Helpers.mintBigV4PositionToPopulatePool(
            address(v4PositionManager), address(permit2), user, poolKey, -600000, 100000, 1_000_000_000_000_000
        );
        deal(weth, address(settler), wethAmount);
        PoolId poolId = PoolIdLibrary.toId(poolKey);

        vm.recordLogs();
        // generate data; below tick means only token1 is needed
        (bytes32 migrationHash, bytes memory data) = genSettlerData(poolKey, SettlementHelpers.Range.BelowTick, true);

        // swap event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Swap(poolId, address(universalRouter), 0, 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, false, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // Sweep remaining tokens to user
        // should be no tokens to sweep, as everything used to mint

        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            weth,
            uint256(totalProtocolFeeBps) * wethAmount / 10000,
            uint256(netSenderFeeBps) * wethAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, false);
        emit ISettler.Settlement(migrationHash, user, tokenId);

        // Receipt
        vm.expectEmit(true, true, true, true);
        emit IAcrossSettler.Receipt(migrationHash, user, weth, wethAmount);

        // call handleV3AcrossMessage
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(weth, wethAmount, address(0), data);

        assertCorrectAmounts(vm.getRecordedLogs(), poolKey, true, wethAmount, 0);
    }

    function test_handleV3AcrossMessage_ST_Token0BaseToken_AboveCurrentTick() public {
        PoolKey memory poolKey = PoolKey(Currency.wrap(weth), Currency.wrap(usdc), 500, 10, IHooks(address(0)));
        UniswapV4Helpers.mintBigV4PositionToPopulatePool(
            address(v4PositionManager), address(permit2), user, poolKey, -600000, 100000, 1_000_000_000_000_000
        );
        deal(weth, address(settler), wethAmount);
        PoolId poolId = PoolIdLibrary.toId(poolKey);

        vm.recordLogs();
        // generate data; above tick means only token0 is needed
        (bytes32 migrationHash, bytes memory data) = genSettlerData(poolKey, SettlementHelpers.Range.AboveTick, true);

        // swap event
        // no swap event expected

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, false, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // Sweep remaining tokens to user
        // should be no tokens to sweep, as everything used to mint

        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            weth,
            uint256(totalProtocolFeeBps) * wethAmount / 10000,
            uint256(netSenderFeeBps) * wethAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, false);
        emit ISettler.Settlement(migrationHash, user, tokenId);

        // Receipt
        vm.expectEmit(true, true, true, true);
        emit IAcrossSettler.Receipt(migrationHash, user, weth, wethAmount);

        // call handleV3AcrossMessage
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(weth, wethAmount, address(0), data);

        assertCorrectAmounts(vm.getRecordedLogs(), poolKey, true, wethAmount, 0);
    }

    function test_handleV3AcrossMessage_ST_Token0BaseToken_SingleSided_NewPool() public {
        MockUSDC mockUSDC = new MockUSDC("Mock USDT", "USDT", address(settler), usdcAmount);

        PoolKey memory poolKey =
            PoolKey(Currency.wrap(weth), Currency.wrap(address(mockUSDC)), 500, 10, IHooks(address(0)));
        deal(weth, address(settler), wethAmount);
        PoolId poolId = PoolIdLibrary.toId(poolKey);

        vm.recordLogs();
        // generate data; above tick means only token0 is needed
        (bytes32 migrationHash, bytes memory data) =
            genSettlerDataWithSqrtPriceX96(poolKey, SettlementHelpers.Range.AboveTick, true, 2 ** 96);

        // swap event
        // no swap event expected

        // pool creation event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Initialize(
            poolId, Currency.wrap(weth), Currency.wrap(address(mockUSDC)), 500, 10, IHooks(address(0)), 2 ** 96, 0
        );

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, false, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // Sweep remaining tokens to user
        // should be no tokens to sweep, as everything used to mint

        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            weth,
            uint256(totalProtocolFeeBps) * wethAmount / 10000,
            uint256(netSenderFeeBps) * wethAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationHash, user, tokenId);

        // Receipt
        vm.expectEmit(true, true, true, true);
        emit IAcrossSettler.Receipt(migrationHash, user, weth, wethAmount);

        // call handleV3AcrossMessage
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(weth, wethAmount, address(0), data);

        assertCorrectAmounts(vm.getRecordedLogs(), poolKey, true, wethAmount, 0);
    }

    // Token1BaseToken scenarios
    function test_handleV3AcrossMessage_ST_Token1BaseToken_failsAndRefunds() public {
        PoolKey memory poolKey =
            PoolKey(Currency.wrap(virtualToken), Currency.wrap(weth), 3000, 100, IHooks(address(0)));
        // initialize pool
        v4PositionManager.initializePool(poolKey, TickMath.getSqrtPriceAtTick(300000));
        UniswapV4Helpers.mintBigV4PositionToPopulatePool(
            address(v4PositionManager), address(permit2), user, poolKey, -600000, 100000, 1_000_000_000_000_000_000
        );
        deal(weth, address(settler), wethAmount);

        vm.recordLogs();
        // generate data with high amount0Min and amount1Min so it'll fail to mint
        (, bytes memory data) =
            genSettlerDataWithAmounts(poolKey, SettlementHelpers.Range.InRange, false, 1 ether, 1 ether);

        // expect the entire weth amount to be transferred to user
        vm.expectEmit(true, true, false, true, address(weth));
        emit IERC20.Transfer(address(settler), address(user), wethAmount);

        // call handleV3AcrossMessage
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(weth, wethAmount, address(0), data);
    }

    function test_handleV3AcrossMessage_ST_Token1BaseToken_InRange() public {
        PoolKey memory poolKey =
            PoolKey(Currency.wrap(virtualToken), Currency.wrap(weth), 3000, 100, IHooks(address(0)));
        // initialize pool
        v4PositionManager.initializePool(poolKey, TickMath.getSqrtPriceAtTick(7));
        UniswapV4Helpers.mintBigV4PositionToPopulatePool(
            address(v4PositionManager), address(permit2), user, poolKey, -50000, 50000, 1_000_000_000_000_000_000_000
        );
        deal(weth, address(settler), wethAmount);
        PoolId poolId = PoolIdLibrary.toId(poolKey);

        vm.recordLogs();
        // generate data
        (bytes32 migrationHash, bytes memory data) = genSettlerData(poolKey, SettlementHelpers.Range.InRange, false);

        // swap event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Swap(poolId, address(universalRouter), 0, 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), user, tokenId + 1);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // Sweep remaining tokens to user
        vm.expectEmit(true, true, false, false, address(virtualToken));
        emit IERC20.Transfer(address(settler), address(user), 0);
        // no left over WETH in this scenario
        // vm.expectEmit(true, true, false, false, address(weth));
        // emit IERC20.Transfer(address(settler), address(user), 0);

        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            weth,
            uint256(totalProtocolFeeBps) * wethAmount / 10000,
            uint256(netSenderFeeBps) * wethAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationHash, user, tokenId + 1);

        // Receipt
        vm.expectEmit(true, true, true, true);
        emit IAcrossSettler.Receipt(migrationHash, user, weth, wethAmount);

        // call handleV3AcrossMessage
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(weth, wethAmount, address(0), data);

        assertCorrectAmounts(vm.getRecordedLogs(), poolKey, false, 0, wethAmount);
    }

    function test_handleV3AcrossMessage_ST_Token1BaseToken_BelowCurrentTick() public {
        PoolKey memory poolKey =
            PoolKey(Currency.wrap(virtualToken), Currency.wrap(weth), 3000, 100, IHooks(address(0)));
        // initialize pool
        v4PositionManager.initializePool(poolKey, TickMath.getSqrtPriceAtTick(7));
        UniswapV4Helpers.mintBigV4PositionToPopulatePool(
            address(v4PositionManager), address(permit2), user, poolKey, -50000, 50000, 1_000_000_000_000_000_000_000
        );
        deal(weth, address(settler), wethAmount);
        PoolId poolId = PoolIdLibrary.toId(poolKey);

        vm.recordLogs();
        // generate data
        (bytes32 migrationHash, bytes memory data) = genSettlerData(poolKey, SettlementHelpers.Range.BelowTick, false);

        // only token1 is needed
        // swap event
        // no swap event expected

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), user, tokenId + 1);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // Sweep remaining tokens to user
        // should be no tokens to sweep, as everything used to mint

        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            weth,
            uint256(totalProtocolFeeBps) * wethAmount / 10000,
            uint256(netSenderFeeBps) * wethAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationHash, user, tokenId + 1);

        // Receipt
        vm.expectEmit(true, true, true, true);
        emit IAcrossSettler.Receipt(migrationHash, user, weth, wethAmount);

        // call handleV3AcrossMessage
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(weth, wethAmount, address(0), data);

        assertCorrectAmounts(vm.getRecordedLogs(), poolKey, false, 0, wethAmount);
    }

    function test_handleV3AcrossMessage_ST_Token1BaseToken_AboveCurrentTick() public {
        PoolKey memory poolKey =
            PoolKey(Currency.wrap(virtualToken), Currency.wrap(weth), 3000, 100, IHooks(address(0)));
        // initialize pool
        v4PositionManager.initializePool(poolKey, TickMath.getSqrtPriceAtTick(7));
        UniswapV4Helpers.mintBigV4PositionToPopulatePool(
            address(v4PositionManager), address(permit2), user, poolKey, -50000, 50000, 1_000_000_000_000_000_000_000
        );
        deal(weth, address(settler), wethAmount);
        PoolId poolId = PoolIdLibrary.toId(poolKey);

        vm.recordLogs();
        // generate data
        (bytes32 migrationHash, bytes memory data) = genSettlerData(poolKey, SettlementHelpers.Range.AboveTick, false);

        // only token0 is needed
        // swap event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Swap(poolId, address(universalRouter), 0, 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), user, tokenId + 1);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // Sweep remaining tokens to user
        // should be no tokens to sweep, as everything used to mint

        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            weth,
            uint256(totalProtocolFeeBps) * wethAmount / 10000,
            uint256(netSenderFeeBps) * wethAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationHash, user, tokenId + 1);

        // Receipt
        vm.expectEmit(true, true, true, true);
        emit IAcrossSettler.Receipt(migrationHash, user, weth, wethAmount);

        // call handleV3AcrossMessage
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(weth, wethAmount, address(0), data);

        assertCorrectAmounts(vm.getRecordedLogs(), poolKey, false, 0, wethAmount);
    }

    function test_handleV3AcrossMessage_ST_Token1BaseToken_SingleSided_NewPool() public {
        PoolKey memory poolKey =
            PoolKey(Currency.wrap(virtualToken), Currency.wrap(weth), 3000, 100, IHooks(address(0)));
        deal(weth, address(settler), wethAmount);
        PoolId poolId = PoolIdLibrary.toId(poolKey);

        vm.recordLogs();
        // generate data; above tick means only token0 is needed
        (bytes32 migrationHash, bytes memory data) =
            genSettlerDataWithSqrtPriceX96(poolKey, SettlementHelpers.Range.BelowTick, false, 2 ** 96);

        // swap event
        // no swap event expected

        // pool creation event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Initialize(
            poolId, Currency.wrap(address(virtualToken)), Currency.wrap(weth), 500, 10, IHooks(address(0)), 2 ** 96, 0
        );

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, false, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // Sweep remaining tokens to user
        // should be no tokens to sweep, as everything used to mint

        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            weth,
            uint256(totalProtocolFeeBps) * wethAmount / 10000,
            uint256(netSenderFeeBps) * wethAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationHash, user, tokenId);

        // Receipt
        vm.expectEmit(true, true, true, true);
        emit IAcrossSettler.Receipt(migrationHash, user, weth, wethAmount);

        // call handleV3AcrossMessage
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(weth, wethAmount, address(0), data);

        assertCorrectAmounts(vm.getRecordedLogs(), poolKey, false, 0, wethAmount);
    }

    // Non-WETH base token scenarios
    function test_handleV3AcrossMessage_ST_NonWethBaseToken_failsAndRefunds() public {
        deal(usdc, address(settler), usdcAmount);
        PoolKey memory poolKey = PoolKey(Currency.wrap(usdc), Currency.wrap(usdt), 500, 10, IHooks(address(0)));

        (, bytes memory data) =
            genSettlerDataWithAmounts(poolKey, SettlementHelpers.Range.InRange, true, 1 ether, 1 ether);

        // expect the entire weth amount to be transferred to user
        vm.expectEmit(true, true, false, true, address(usdc));
        emit IERC20.Transfer(address(settler), address(user), usdcAmount);

        // call handleV3AcrossMessage
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(usdc, usdcAmount, address(0), data);
    }

    function test_handleV3AcrossMessage_ST_NonWethBaseToken_InRange() public {
        PoolKey memory poolKey = PoolKey(Currency.wrap(usdc), Currency.wrap(usdt), 500, 10, IHooks(address(0)));
        UniswapV4Helpers.mintBigV4PositionToPopulatePool(
            address(v4PositionManager), address(permit2), user, poolKey, -100000, 100000, 1_000_000_000_000_000_000
        );
        deal(usdc, address(settler), usdcAmount);
        PoolId poolId = PoolIdLibrary.toId(poolKey);

        vm.recordLogs();
        // generate data
        (bytes32 migrationHash, bytes memory data) = genSettlerData(poolKey, SettlementHelpers.Range.InRange, true);

        // swap event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Swap(poolId, address(universalRouter), 0, 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), user, tokenId + 1);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // Sweep remaining tokens to user; only one in this scenario
        vm.expectEmit(true, true, false, false, address(usdc));
        emit IERC20.Transfer(address(settler), address(user), 0);

        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            usdc,
            uint256(totalProtocolFeeBps) * usdcAmount / 10000,
            uint256(netSenderFeeBps) * usdcAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, false);
        emit ISettler.Settlement(migrationHash, user, tokenId);

        // Receipt
        vm.expectEmit(true, true, true, true);
        emit IAcrossSettler.Receipt(migrationHash, user, usdc, usdcAmount);

        // call handleV3AcrossMessage
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(usdc, usdcAmount, address(0), data);

        assertCorrectAmounts(vm.getRecordedLogs(), poolKey, true, usdcAmount, 0);
    }

    function test_handleV3AcrossMessage_ST_NonWethBaseToken_BelowCurrentTick() public {
        PoolKey memory poolKey = PoolKey(Currency.wrap(usdc), Currency.wrap(usdt), 500, 10, IHooks(address(0)));
        UniswapV4Helpers.mintBigV4PositionToPopulatePool(
            address(v4PositionManager), address(permit2), user, poolKey, -100000, 100000, 1_000_000_000_000_000_000
        );
        deal(usdc, address(settler), usdcAmount);
        PoolId poolId = PoolIdLibrary.toId(poolKey);

        vm.recordLogs();
        // generate data
        (bytes32 migrationHash, bytes memory data) = genSettlerData(poolKey, SettlementHelpers.Range.BelowTick, true);

        // only token1 is needed
        // swap event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Swap(poolId, address(universalRouter), 0, 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), user, tokenId + 1);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // Sweep remaining tokens to user; only one in this scenario
        // no tokens to sweep

        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            usdc,
            uint256(totalProtocolFeeBps) * usdcAmount / 10000,
            uint256(netSenderFeeBps) * usdcAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationHash, user, tokenId + 1);

        // Receipt
        vm.expectEmit(true, true, true, true);
        emit IAcrossSettler.Receipt(migrationHash, user, usdc, usdcAmount);

        // call handleV3AcrossMessage
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(usdc, usdcAmount, address(0), data);

        assertCorrectAmounts(vm.getRecordedLogs(), poolKey, true, usdcAmount, 0);
    }

    function test_handleV3AcrossMessage_ST_NonWethBaseToken_AboveCurrentTick() public {
        PoolKey memory poolKey = PoolKey(Currency.wrap(usdc), Currency.wrap(usdt), 500, 10, IHooks(address(0)));
        UniswapV4Helpers.mintBigV4PositionToPopulatePool(
            address(v4PositionManager), address(permit2), user, poolKey, -100000, 100000, 1_000_000_000_000_000_000
        );
        deal(usdc, address(settler), usdcAmount);
        PoolId poolId = PoolIdLibrary.toId(poolKey);

        vm.recordLogs();
        // generate data
        (bytes32 migrationHash, bytes memory data) = genSettlerData(poolKey, SettlementHelpers.Range.AboveTick, true);

        // only token0 is needed
        // swap event
        // no swap event expected

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), user, tokenId + 1);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // Sweep remaining tokens to user; only one in this scenario
        // no tokens to sweep
        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            usdc,
            uint256(totalProtocolFeeBps) * usdcAmount / 10000,
            uint256(netSenderFeeBps) * usdcAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationHash, user, tokenId + 1);

        // Receipt
        vm.expectEmit(true, true, true, true);
        emit IAcrossSettler.Receipt(migrationHash, user, usdc, usdcAmount);

        // call handleV3AcrossMessage
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(usdc, usdcAmount, address(0), data);

        assertCorrectAmounts(vm.getRecordedLogs(), poolKey, true, usdcAmount, 0);
    }

    function test_handleV3AcrossMessage_ST_NonWethBaseToken_SingleSided_NewPool() public {
        address mockUSDC = address(uint160(usdc) + 10000000); // needs to be larger than usdc
        deployCodeTo("MockUSDC.sol", abi.encode("Mock USDC", "USDC", address(settler), usdcAmount), mockUSDC);

        PoolKey memory poolKey =
            PoolKey(Currency.wrap(usdc), Currency.wrap(address(mockUSDC)), 500, 10, IHooks(address(0)));
        deal(usdc, address(settler), usdcAmount);
        PoolId poolId = PoolIdLibrary.toId(poolKey);

        vm.recordLogs();
        // generate data; above tick means only token0 is needed
        (bytes32 migrationHash, bytes memory data) =
            genSettlerDataWithSqrtPriceX96(poolKey, SettlementHelpers.Range.AboveTick, true, 2 ** 96);

        // swap event
        // no swap event expected

        // pool creation event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Initialize(
            poolId, Currency.wrap(usdc), Currency.wrap(address(mockUSDC)), 500, 10, IHooks(address(0)), 2 ** 96, 0
        );

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, false, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // Sweep remaining tokens to user
        // should be no tokens to sweep, as everything used to mint

        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            usdc,
            uint256(totalProtocolFeeBps) * usdcAmount / 10000,
            uint256(netSenderFeeBps) * usdcAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationHash, user, tokenId);

        // Receipt
        vm.expectEmit(true, true, true, true);
        emit IAcrossSettler.Receipt(migrationHash, user, usdc, usdcAmount);

        // call handleV3AcrossMessage
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(usdc, usdcAmount, address(0), data);

        assertCorrectAmounts(vm.getRecordedLogs(), poolKey, true, usdcAmount, 0);
    }

    /**
     * DUAL TOKEN PATHS ***
     */

    // NativeToken scenarios
    function test_handleV3AcrossMessage_DT_NativeToken_FirstBridgeCallFailsWhenFirstAmountTooLowAndIsIgnored() public {
        PoolKey memory poolKey = PoolKey(Currency.wrap(address(0)), Currency.wrap(usdc), 500, 10, IHooks(address(0)));

        vm.recordLogs();
        // generate data
        (bytes32 migrationHash, bytes memory data) =
            genSettlerDataForDualToken(poolKey, SettlementHelpers.Range.InRange, true, wethAmount - 1, usdcAmount - 1);

        // call handleV3AcrossMessage
        vm.prank(address(acrossSpokePool));
        vm.expectRevert(bytes("")); // important to use bytes("") as this revert should contain no data
        settler.handleV3AcrossMessage(weth, wethAmount - 10, address(0), data);

        // verify no amounts were transferred
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0); // no logs were emitted
        assertEq(IERC20(weth).balanceOf(address(settler)), 0);
        assertEq(IERC20(usdc).balanceOf(address(settler)), 0);

        // verify settlement cache is not set
        assertEq(settler.checkSettlementCache(migrationHash), false);
    }

    function test_handleV3AcrossMessage_DT_NativeToken_FirstBridgeCallFailsWhenSecondAmountTooLowAndIsIgnored()
        public
    {
        PoolKey memory poolKey = PoolKey(Currency.wrap(address(0)), Currency.wrap(usdc), 500, 10, IHooks(address(0)));
        vm.recordLogs();
        // generate data
        (bytes32 migrationHash, bytes memory data) =
            genSettlerDataForDualToken(poolKey, SettlementHelpers.Range.InRange, true, wethAmount - 1, usdcAmount - 1);

        // call handleV3AcrossMessage
        vm.prank(address(acrossSpokePool));
        vm.expectRevert(bytes("")); // important to use bytes("") as this revert should contain no data
        settler.handleV3AcrossMessage(usdc, usdcAmount - 10, address(0), data);

        // verify no amounts were transferred
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0); // no logs were emitted
        assertEq(IERC20(weth).balanceOf(address(settler)), 0);
        assertEq(IERC20(usdc).balanceOf(address(settler)), 0);

        // verify settlement cache is not set
        assertEq(settler.checkSettlementCache(migrationHash), false);
    }

    function test_handleV3AcrossMessage_DT_NativeToken_FirstBridgeCallFailsTokenMismatchAndIsIgnored() public {
        PoolKey memory poolKey = PoolKey(Currency.wrap(address(0)), Currency.wrap(usdc), 500, 10, IHooks(address(0)));
        vm.recordLogs();
        // generate data
        (bytes32 migrationHash, bytes memory data) =
            genSettlerDataForDualToken(poolKey, SettlementHelpers.Range.InRange, true, wethAmount - 1, usdcAmount - 1);

        // call handleV3AcrossMessage
        vm.prank(address(acrossSpokePool));
        vm.expectRevert(bytes("")); // important to use bytes("") as this revert should contain no data
        settler.handleV3AcrossMessage(virtualToken, wethAmount - 10, address(0), data);

        // verify no amounts were transferred
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0); // no logs were emitted
        assertEq(IERC20(weth).balanceOf(address(settler)), 0);
        assertEq(IERC20(usdc).balanceOf(address(settler)), 0);

        // verify settlement cache is not set
        assertEq(settler.checkSettlementCache(migrationHash), false);
    }

    function test_handleV3AcrossMessage_DT_NativeToken_SecondBridgeCallFailsSecondAmountTooLowAndIsIgnored() public {
        PoolKey memory poolKey = PoolKey(Currency.wrap(address(0)), Currency.wrap(usdc), 500, 10, IHooks(address(0)));
        deal(weth, address(settler), wethAmount);
        // generate data
        (bytes32 migrationHash, bytes memory data) =
            genSettlerDataForDualToken(poolKey, SettlementHelpers.Range.InRange, true, wethAmount, usdcAmount);

        // first call to handleV3AcrossMessage; succeeds
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(weth, wethAmount, address(0), data);
        assertEq(settler.checkSettlementCache(migrationHash), true);

        vm.recordLogs();

        // second call to handleV3AcrossMessage; ignored
        vm.prank(address(acrossSpokePool));
        vm.expectRevert(bytes("")); // important to use bytes("") as this revert should contain no data
        settler.handleV3AcrossMessage(usdc, 1, address(0), data);

        // verify settlement cache still exists
        assertEq(settler.checkSettlementCache(migrationHash), true);
        // verify no amounts were transferred
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0); // no logs were emitted
        assertEq(IERC20(weth).balanceOf(address(settler)), wethAmount);
        assertEq(IERC20(usdc).balanceOf(address(settler)), 0);
    }

    function test_handleV3AcrossMessage_DT_NativeToken_SecondBridgeCallFailsAndRefundsBoth() public {
        PoolKey memory poolKey = PoolKey(Currency.wrap(address(0)), Currency.wrap(usdc), 500, 10, IHooks(address(0)));
        deal(weth, address(settler), wethAmount);
        deal(usdc, address(settler), usdcAmount);
        // generate data
        (bytes32 migrationHash, bytes memory data) = genSettlerDataForDualTokenWithAmounts(
            poolKey, SettlementHelpers.Range.InRange, true, wethAmount, usdcAmount, wethAmount, usdcAmount
        );

        // first call to handleV3AcrossMessage; succeeds
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(weth, wethAmount, address(0), data);
        assertEq(settler.checkSettlementCache(migrationHash), true);

        // expect the entire usdc amount to be transferred to user
        vm.expectEmit(true, true, false, true, address(usdc));
        emit IERC20.Transfer(address(settler), address(user), usdcAmount);

        // expect the entire weth amount to be transferred to user
        vm.expectEmit(true, true, false, true, address(weth));
        emit IERC20.Transfer(address(settler), address(user), wethAmount);

        // second call to handleV3AcrossMessage fails via catch and refunds both token
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(usdc, usdcAmount, address(0), data);

        // verify settlement cache is not set
        assertEq(settler.checkSettlementCache(migrationHash), false);
    }

    function test_handleV3AcrossMessage_DT_NativeToken_InRange_ExistingPool_Token0ArrivesBeforeToken1() public {
        PoolKey memory poolKey = PoolKey(Currency.wrap(address(0)), Currency.wrap(usdc), 500, 10, IHooks(address(0)));
        PoolId poolId = PoolIdLibrary.toId(poolKey);
        deal(weth, address(settler), wethAmount);
        deal(usdc, address(settler), usdcAmount);
        // generate data
        (bytes32 migrationHash, bytes memory data) =
            genSettlerDataForDualToken(poolKey, SettlementHelpers.Range.InRange, true, wethAmount, usdcAmount);

        // first call to handleV3AcrossMessage; succeeds
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(weth, wethAmount, address(0), data);
        assertEq(settler.checkSettlementCache(migrationHash), true);

        vm.recordLogs();

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // Sweep remaining tokens to user
        vm.expectEmit(true, true, false, false, address(weth));
        emit IERC20.Transfer(address(settler), address(user), 0);

        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            usdc,
            uint256(totalProtocolFeeBps) * usdcAmount / 10000,
            uint256(netSenderFeeBps) * usdcAmount / 10000
        );

        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            weth,
            uint256(totalProtocolFeeBps) * wethAmount / 10000,
            uint256(netSenderFeeBps) * wethAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationHash, user, tokenId);

        // Receipt
        vm.expectEmit(true, true, true, true);
        emit IAcrossSettler.Receipt(migrationHash, user, usdc, usdcAmount);

        // second call to handleV3AcrossMessage fails via catch and refunds both token
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(usdc, usdcAmount, address(0), data);
        assertCorrectAmountsDualTokenForNativeTokenPositions(
            vm.getRecordedLogs(), poolKey, true, wethAmount, usdcAmount
        );
    }

    function test_handleV3AcrossMessage_DT_NativeToken_InRange_ExistingPool_Token1ArrivesBeforeToken0() public {
        PoolKey memory poolKey = PoolKey(Currency.wrap(address(0)), Currency.wrap(usdc), 500, 10, IHooks(address(0)));
        PoolId poolId = PoolIdLibrary.toId(poolKey);

        deal(weth, address(settler), wethAmount);
        deal(usdc, address(settler), usdcAmount);
        // generate data
        (bytes32 migrationHash, bytes memory data) =
            genSettlerDataForDualToken(poolKey, SettlementHelpers.Range.InRange, true, wethAmount, usdcAmount);

        // first call to handleV3AcrossMessage; succeeds
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(usdc, usdcAmount, address(0), data);
        assertEq(settler.checkSettlementCache(migrationHash), true);

        vm.recordLogs();
        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // Sweep remaining tokens to user
        vm.expectEmit(true, true, false, false, address(weth));
        emit IERC20.Transfer(address(settler), address(user), 0);

        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            weth,
            uint256(totalProtocolFeeBps) * wethAmount / 10000,
            uint256(netSenderFeeBps) * wethAmount / 10000
        );

        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            usdc,
            uint256(totalProtocolFeeBps) * usdcAmount / 10000,
            uint256(netSenderFeeBps) * usdcAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationHash, user, tokenId);

        // Receipt
        vm.expectEmit(true, true, true, true);
        emit IAcrossSettler.Receipt(migrationHash, user, weth, wethAmount);

        // second call to handleV3AcrossMessage fails via catch and refunds both token
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(weth, wethAmount, address(0), data);
        assertCorrectAmountsDualTokenForNativeTokenPositions(
            vm.getRecordedLogs(), poolKey, false, wethAmount, usdcAmount
        );
    }

    function test_handleV3AcrossMessage_DT_NativeToken_InRange_NewPool_Token0ArrivesBeforeToken1() public {
        MockUSDC mockUSDC = new MockUSDC("Mock USDT", "USDT", address(settler), usdcAmount);
        PoolKey memory poolKey =
            PoolKey(Currency.wrap(address(0)), Currency.wrap(address(mockUSDC)), 500, 10, IHooks(address(0)));
        PoolId poolId = PoolIdLibrary.toId(poolKey);

        deal(weth, address(settler), wethAmount);
        deal(address(mockUSDC), address(settler), usdcAmount);
        // generate data
        (bytes32 migrationHash, bytes memory data) = genSettlerDataForDualTokenWithSqrtPriceX96(
            poolKey, SettlementHelpers.Range.InRange, true, wethAmount, usdcAmount, 2 ** 96
        );

        // first call to handleV3AcrossMessage; succeeds
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(weth, wethAmount, address(0), data);
        assertEq(settler.checkSettlementCache(migrationHash), true);

        vm.recordLogs();

        // pool creation event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Initialize(
            poolId, Currency.wrap(address(0)), Currency.wrap(address(mockUSDC)), 500, 10, IHooks(address(0)), 2 ** 96, 0
        );

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, false, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // Sweep remaining tokens to user
        vm.expectEmit(true, true, false, false, address(weth));
        emit IERC20.Transfer(address(settler), address(user), 0);

        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            address(mockUSDC),
            uint256(totalProtocolFeeBps) * usdcAmount / 10000,
            uint256(netSenderFeeBps) * usdcAmount / 10000
        );

        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            weth,
            uint256(totalProtocolFeeBps) * wethAmount / 10000,
            uint256(netSenderFeeBps) * wethAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationHash, user, tokenId);

        // Receipt
        vm.expectEmit(true, true, true, true);
        emit IAcrossSettler.Receipt(migrationHash, user, address(mockUSDC), usdcAmount);

        // second call to handleV3AcrossMessage fails via catch and refunds both token
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(address(mockUSDC), usdcAmount, address(0), data);
        assertCorrectAmountsDualTokenForNativeTokenPositions(
            vm.getRecordedLogs(), poolKey, true, wethAmount, usdcAmount
        );
    }

    function test_handleV3AcrossMessage_DT_NativeToken_InRange_NewPool_Token1ArrivesBeforeToken0() public {
        MockUSDC mockUSDC = new MockUSDC("Mock USDT", "USDT", address(settler), usdcAmount);
        PoolKey memory poolKey =
            PoolKey(Currency.wrap(address(0)), Currency.wrap(address(mockUSDC)), 500, 10, IHooks(address(0)));
        PoolId poolId = PoolIdLibrary.toId(poolKey);

        deal(weth, address(settler), wethAmount);
        deal(address(mockUSDC), address(settler), usdcAmount);
        // generate data
        (bytes32 migrationHash, bytes memory data) = genSettlerDataForDualTokenWithSqrtPriceX96(
            poolKey, SettlementHelpers.Range.InRange, true, wethAmount, usdcAmount, 2 ** 96
        );

        // first call to handleV3AcrossMessage; succeeds
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(address(mockUSDC), usdcAmount, address(0), data);
        assertEq(settler.checkSettlementCache(migrationHash), true);

        vm.recordLogs();

        // pool creation event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Initialize(
            poolId, Currency.wrap(address(0)), Currency.wrap(address(mockUSDC)), 500, 10, IHooks(address(0)), 2 ** 96, 0
        );

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // Sweep remaining tokens to user
        vm.expectEmit(true, true, false, false, address(weth));
        emit IERC20.Transfer(address(settler), address(user), 0);

        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            weth,
            uint256(totalProtocolFeeBps) * wethAmount / 10000,
            uint256(netSenderFeeBps) * wethAmount / 10000
        );

        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            address(mockUSDC),
            uint256(totalProtocolFeeBps) * usdcAmount / 10000,
            uint256(netSenderFeeBps) * usdcAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationHash, user, tokenId);

        // Receipt
        vm.expectEmit(true, true, true, true);
        emit IAcrossSettler.Receipt(migrationHash, user, weth, wethAmount);

        // second call to handleV3AcrossMessage fails via catch and refunds both token
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(weth, wethAmount, address(0), data);
        assertCorrectAmountsDualTokenForNativeTokenPositions(
            vm.getRecordedLogs(), poolKey, false, wethAmount, usdcAmount
        );
    }

    // Token0WETH/BaseToken scenarios
    function test_handleV3AcrossMessage_DT_Token0WETH_BaseToken_FirstBridgeCallFailsWhenFirstAmountTooLowAndIsIgnored()
        public
    {
        PoolKey memory poolKey = PoolKey(Currency.wrap(weth), Currency.wrap(usdc), 500, 10, IHooks(address(0)));

        vm.recordLogs();
        // generate data
        (bytes32 migrationHash, bytes memory data) =
            genSettlerDataForDualToken(poolKey, SettlementHelpers.Range.InRange, true, wethAmount - 1, usdcAmount - 1);

        // call handleV3AcrossMessage
        vm.prank(address(acrossSpokePool));
        vm.expectRevert(bytes("")); // important to use bytes("") as this revert should contain no data
        settler.handleV3AcrossMessage(weth, wethAmount - 10, address(0), data);

        // verify no amounts were transferred
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0); // no logs were emitted
        assertEq(IERC20(weth).balanceOf(address(settler)), 0);
        assertEq(IERC20(usdc).balanceOf(address(settler)), 0);

        // verify settlement cache is not set
        assertEq(settler.checkSettlementCache(migrationHash), false);
    }

    function test_handleV3AcrossMessage_DT_Token0WETH_BaseToken_FirstBridgeCallFailsWhenSecondAmountTooLowAndIsIgnored()
        public
    {
        PoolKey memory poolKey = PoolKey(Currency.wrap(weth), Currency.wrap(usdc), 500, 10, IHooks(address(0)));
        vm.recordLogs();
        // generate data
        (bytes32 migrationHash, bytes memory data) =
            genSettlerDataForDualToken(poolKey, SettlementHelpers.Range.InRange, true, wethAmount - 1, usdcAmount - 1);

        // call handleV3AcrossMessage
        vm.prank(address(acrossSpokePool));
        vm.expectRevert(bytes("")); // important to use bytes("") as this revert should contain no data
        settler.handleV3AcrossMessage(usdc, usdcAmount - 10, address(0), data);

        // verify no amounts were transferred
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0); // no logs were emitted
        assertEq(IERC20(weth).balanceOf(address(settler)), 0);
        assertEq(IERC20(usdc).balanceOf(address(settler)), 0);

        // verify settlement cache is not set
        assertEq(settler.checkSettlementCache(migrationHash), false);
    }

    function test_handleV3AcrossMessage_DT_Token0WETH_BaseToken_FirstBridgeCallFailsTokenMismatchAndIsIgnored()
        public
    {
        PoolKey memory poolKey = PoolKey(Currency.wrap(weth), Currency.wrap(usdc), 500, 10, IHooks(address(0)));
        vm.recordLogs();
        // generate data
        (bytes32 migrationHash, bytes memory data) =
            genSettlerDataForDualToken(poolKey, SettlementHelpers.Range.InRange, true, wethAmount - 1, usdcAmount - 1);

        // call handleV3AcrossMessage
        vm.prank(address(acrossSpokePool));
        vm.expectRevert(bytes("")); // important to use bytes("") as this revert should contain no data
        settler.handleV3AcrossMessage(virtualToken, wethAmount - 10, address(0), data);

        // verify no amounts were transferred
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0); // no logs were emitted
        assertEq(IERC20(weth).balanceOf(address(settler)), 0);
        assertEq(IERC20(usdc).balanceOf(address(settler)), 0);

        // verify settlement cache is not set
        assertEq(settler.checkSettlementCache(migrationHash), false);
    }

    function test_handleV3AcrossMessage_DT_Token0WETH_BaseToken_SecondBridgeCallFailsSecondAmountTooLowAndIsIgnored()
        public
    {
        PoolKey memory poolKey = PoolKey(Currency.wrap(weth), Currency.wrap(usdc), 500, 10, IHooks(address(0)));
        deal(weth, address(settler), wethAmount);
        // generate data
        (bytes32 migrationHash, bytes memory data) =
            genSettlerDataForDualToken(poolKey, SettlementHelpers.Range.InRange, true, wethAmount, usdcAmount);

        // first call to handleV3AcrossMessage; succeeds
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(weth, wethAmount, address(0), data);
        assertEq(settler.checkSettlementCache(migrationHash), true);

        vm.recordLogs();

        // second call to handleV3AcrossMessage; ignored
        vm.prank(address(acrossSpokePool));
        vm.expectRevert(bytes("")); // important to use bytes("") as this revert should contain no data
        settler.handleV3AcrossMessage(usdc, 1, address(0), data);

        // verify settlement cache still exists
        assertEq(settler.checkSettlementCache(migrationHash), true);
        // verify no amounts were transferred
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0); // no logs were emitted
        assertEq(IERC20(weth).balanceOf(address(settler)), wethAmount);
        assertEq(IERC20(usdc).balanceOf(address(settler)), 0);
    }

    function test_handleV3AcrossMessage_DT_Token0WETH_BaseToken_SecondBridgeCallFailsAndRefundsBoth() public {
        PoolKey memory poolKey = PoolKey(Currency.wrap(weth), Currency.wrap(usdc), 500, 10, IHooks(address(0)));
        deal(weth, address(settler), wethAmount);
        deal(usdc, address(settler), usdcAmount);
        // generate data
        (bytes32 migrationHash, bytes memory data) = genSettlerDataForDualTokenWithAmounts(
            poolKey, SettlementHelpers.Range.InRange, true, wethAmount, usdcAmount, wethAmount, usdcAmount
        );

        // first call to handleV3AcrossMessage; succeeds
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(weth, wethAmount, address(0), data);
        assertEq(settler.checkSettlementCache(migrationHash), true);

        // expect the entire usdc amount to be transferred to user
        vm.expectEmit(true, true, false, true, address(usdc));
        emit IERC20.Transfer(address(settler), address(user), usdcAmount);

        // expect the entire weth amount to be transferred to user
        vm.expectEmit(true, true, false, true, address(weth));
        emit IERC20.Transfer(address(settler), address(user), wethAmount);

        // second call to handleV3AcrossMessage fails via catch and refunds both token
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(usdc, usdcAmount, address(0), data);

        // verify settlement cache is not set
        assertEq(settler.checkSettlementCache(migrationHash), false);
    }

    function test_handleV3AcrossMessage_DT_Token0WETH_BaseToken_InRange_ExistingPool_Token0ArrivesBeforeToken1()
        public
    {
        PoolKey memory poolKey = PoolKey(Currency.wrap(weth), Currency.wrap(usdc), 500, 10, IHooks(address(0)));
        PoolId poolId = PoolIdLibrary.toId(poolKey);
        deal(weth, address(settler), wethAmount);
        deal(usdc, address(settler), usdcAmount);
        // generate data
        (bytes32 migrationHash, bytes memory data) =
            genSettlerDataForDualToken(poolKey, SettlementHelpers.Range.InRange, true, wethAmount, usdcAmount);

        // first call to handleV3AcrossMessage; succeeds
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(weth, wethAmount, address(0), data);
        assertEq(settler.checkSettlementCache(migrationHash), true);

        vm.recordLogs();

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // Sweep remaining tokens to user
        vm.expectEmit(true, true, false, false, address(weth));
        emit IERC20.Transfer(address(settler), address(user), 0);

        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            usdc,
            uint256(totalProtocolFeeBps) * usdcAmount / 10000,
            uint256(netSenderFeeBps) * usdcAmount / 10000
        );

        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            weth,
            uint256(totalProtocolFeeBps) * wethAmount / 10000,
            uint256(netSenderFeeBps) * wethAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationHash, user, tokenId);

        // Receipt
        vm.expectEmit(true, true, true, true);
        emit IAcrossSettler.Receipt(migrationHash, user, usdc, usdcAmount);

        // second call to handleV3AcrossMessage fails via catch and refunds both token
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(usdc, usdcAmount, address(0), data);
        assertCorrectAmountsDualToken(vm.getRecordedLogs(), poolKey, true, wethAmount, usdcAmount);
    }

    function test_handleV3AcrossMessage_DT_Token0WETH_BaseToken_InRange_ExistingPool_Token1ArrivesBeforeToken0()
        public
    {
        PoolKey memory poolKey = PoolKey(Currency.wrap(weth), Currency.wrap(usdc), 500, 10, IHooks(address(0)));
        PoolId poolId = PoolIdLibrary.toId(poolKey);

        deal(weth, address(settler), wethAmount);
        deal(usdc, address(settler), usdcAmount);
        // generate data
        (bytes32 migrationHash, bytes memory data) =
            genSettlerDataForDualToken(poolKey, SettlementHelpers.Range.InRange, true, wethAmount, usdcAmount);

        // first call to handleV3AcrossMessage; succeeds
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(usdc, usdcAmount, address(0), data);
        assertEq(settler.checkSettlementCache(migrationHash), true);

        vm.recordLogs();
        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // Sweep remaining tokens to user
        vm.expectEmit(true, true, false, false, address(weth));
        emit IERC20.Transfer(address(settler), address(user), 0);

        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            weth,
            uint256(totalProtocolFeeBps) * wethAmount / 10000,
            uint256(netSenderFeeBps) * wethAmount / 10000
        );

        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            usdc,
            uint256(totalProtocolFeeBps) * usdcAmount / 10000,
            uint256(netSenderFeeBps) * usdcAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationHash, user, tokenId);

        // Receipt
        vm.expectEmit(true, true, true, true);
        emit IAcrossSettler.Receipt(migrationHash, user, weth, wethAmount);

        // second call to handleV3AcrossMessage fails via catch and refunds both token
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(weth, wethAmount, address(0), data);
        assertCorrectAmountsDualToken(vm.getRecordedLogs(), poolKey, false, wethAmount, usdcAmount);
    }

    function test_handleV3AcrossMessage_DT_Token0WETH_BaseToken_InRange_NewPool_Token0ArrivesBeforeToken1() public {
        MockUSDC mockUSDC = new MockUSDC("Mock USDT", "USDT", address(settler), usdcAmount);
        PoolKey memory poolKey =
            PoolKey(Currency.wrap(weth), Currency.wrap(address(mockUSDC)), 500, 10, IHooks(address(0)));
        PoolId poolId = PoolIdLibrary.toId(poolKey);

        deal(weth, address(settler), wethAmount);
        deal(address(mockUSDC), address(settler), usdcAmount);
        // generate data
        (bytes32 migrationHash, bytes memory data) = genSettlerDataForDualTokenWithSqrtPriceX96(
            poolKey, SettlementHelpers.Range.InRange, true, wethAmount, usdcAmount, 2 ** 96
        );

        // first call to handleV3AcrossMessage; succeeds
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(weth, wethAmount, address(0), data);
        assertEq(settler.checkSettlementCache(migrationHash), true);

        vm.recordLogs();

        // pool creation event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Initialize(
            poolId, Currency.wrap(weth), Currency.wrap(address(mockUSDC)), 500, 10, IHooks(address(0)), 2 ** 96, 0
        );

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, false, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // Sweep remaining tokens to user
        vm.expectEmit(true, true, false, false, address(weth));
        emit IERC20.Transfer(address(settler), address(user), 0);

        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            address(mockUSDC),
            uint256(totalProtocolFeeBps) * usdcAmount / 10000,
            uint256(netSenderFeeBps) * usdcAmount / 10000
        );

        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            weth,
            uint256(totalProtocolFeeBps) * wethAmount / 10000,
            uint256(netSenderFeeBps) * wethAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationHash, user, tokenId);

        // Receipt
        vm.expectEmit(true, true, true, true);
        emit IAcrossSettler.Receipt(migrationHash, user, address(mockUSDC), usdcAmount);

        // second call to handleV3AcrossMessage fails via catch and refunds both token
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(address(mockUSDC), usdcAmount, address(0), data);
        assertCorrectAmountsDualToken(vm.getRecordedLogs(), poolKey, true, wethAmount, usdcAmount);
    }

    function test_handleV3AcrossMessage_DT_Token0WETH_BaseToken_InRange_NewPool_Token1ArrivesBeforeToken0() public {
        MockUSDC mockUSDC = new MockUSDC("Mock USDT", "USDT", address(settler), usdcAmount);
        PoolKey memory poolKey =
            PoolKey(Currency.wrap(weth), Currency.wrap(address(mockUSDC)), 500, 10, IHooks(address(0)));
        PoolId poolId = PoolIdLibrary.toId(poolKey);

        deal(weth, address(settler), wethAmount);
        deal(address(mockUSDC), address(settler), usdcAmount);
        // generate data
        (bytes32 migrationHash, bytes memory data) = genSettlerDataForDualTokenWithSqrtPriceX96(
            poolKey, SettlementHelpers.Range.InRange, true, wethAmount, usdcAmount, 2 ** 96
        );

        // first call to handleV3AcrossMessage; succeeds
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(address(mockUSDC), usdcAmount, address(0), data);
        assertEq(settler.checkSettlementCache(migrationHash), true);

        vm.recordLogs();

        // pool creation event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Initialize(
            poolId, Currency.wrap(weth), Currency.wrap(address(mockUSDC)), 500, 10, IHooks(address(0)), 2 ** 96, 0
        );

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // Sweep remaining tokens to user
        vm.expectEmit(true, true, false, false, address(weth));
        emit IERC20.Transfer(address(settler), address(user), 0);

        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            weth,
            uint256(totalProtocolFeeBps) * wethAmount / 10000,
            uint256(netSenderFeeBps) * wethAmount / 10000
        );

        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationHash,
            address(mockUSDC),
            uint256(totalProtocolFeeBps) * usdcAmount / 10000,
            uint256(netSenderFeeBps) * usdcAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationHash, user, tokenId);

        // Receipt
        vm.expectEmit(true, true, true, true);
        emit IAcrossSettler.Receipt(migrationHash, user, weth, wethAmount);

        // second call to handleV3AcrossMessage fails via catch and refunds both token
        vm.prank(address(acrossSpokePool));
        settler.handleV3AcrossMessage(weth, wethAmount, address(0), data);
        assertCorrectAmountsDualToken(vm.getRecordedLogs(), poolKey, false, wethAmount, usdcAmount);
    }

    function test() public override(TestContext, UniswapV4Helpers) {}
}
