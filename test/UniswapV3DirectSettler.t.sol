// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {TestContext} from "./utils/TestContext.sol";
import {ISettler} from "../src/interfaces/ISettler.sol";
import {IDirectSettler} from "../src/interfaces/IDirectSettler.sol";
import {IUniswapV3Settler} from "../src/interfaces/IUniswapV3Settler.sol";
import {UniswapV3DirectSettlerHarness} from "./mocks/UniswapV3DirectSettlerHarness.sol";
import {UniswapV3Helpers} from "./utils/UniswapV3Helpers.sol";
import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {INonfungiblePositionManager} from "../src/interfaces/external/INonfungiblePositionManager.sol";
import {IUniswapV3PoolEvents} from "@uniswap-v3-core/interfaces/pool/IUniswapV3PoolEvents.sol";
import {IUniswapV3Factory} from "@uniswap-v3-core/interfaces/IUniswapV3Factory.sol";
import {MigrationModes, MigrationMode} from "../src/types/MigrationMode.sol";
import {MigrationData} from "../src/types/MigrationData.sol";
import {SettlementHelpers} from "./utils/SettlementHelpers.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

contract UniswapV3DirectSettlerTest is TestContext, UniswapV3Helpers {
    string public constant CHAIN_NAME = "BASE";
    UniswapV3DirectSettlerHarness public settler;
    uint256 public tokenId = 2806740;
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
        settler = new UniswapV3DirectSettlerHarness(
            owner, address(v3PositionManager), address(universalRouter), address(permit2)
        );

        // todo setup a protocol fee recipient
        vm.prank(owner);
        settler.setProtocolFeeRecipient(protocolFeeRecipient);
        vm.prank(owner);
        settler.setProtocolShareBps(protocolFee);
        vm.prank(owner);
        settler.setProtocolShareOfSenderFeePct(protocolShareOfSenderFeePct);
    }

    function genSettlerData(
        address token0,
        address token1,
        uint24 fee,
        SettlementHelpers.Range range,
        bool isToken0BaseToken
    ) public view returns (bytes32 migrationId, bytes memory data) {
        int24 currentTick = UniswapV3Helpers.getCurrentTick(address(v3PositionManager), token0, token1, fee);
        (migrationId, data) = SettlementHelpers.generateSettlerData(
            SettlementHelpers.generateV3SettlementParamsUsingCurrentTick(
                user, token0, token1, fee, 0, currentTick, range, 0, 0, isToken0BaseToken, senderShareBps
            ),
            MigrationModes.SINGLE,
            ""
        );
        return (migrationId, data);
    }

    function genSettlerDataWithSqrtPriceX96(
        address token0,
        address token1,
        uint24 fee,
        SettlementHelpers.Range range,
        bool isToken0BaseToken,
        uint160 sqrtPriceX96
    ) public view returns (bytes32 migrationId, bytes memory data) {
        int24 currentTick = 10000;
        (migrationId, data) = SettlementHelpers.generateSettlerData(
            SettlementHelpers.generateV3SettlementParamsUsingCurrentTick(
                user, token0, token1, fee, sqrtPriceX96, currentTick, range, 0, 0, isToken0BaseToken, senderShareBps
            ),
            MigrationModes.SINGLE,
            ""
        );
        return (migrationId, data);
    }

    function genSettlerDataWithAmounts(
        address token0,
        address token1,
        uint24 fee,
        SettlementHelpers.Range range,
        bool isToken0BaseToken,
        uint256 amount0Min,
        uint256 amount1Min
    ) public view returns (bytes32 migrationId, bytes memory data) {
        int24 currentTick = UniswapV3Helpers.getCurrentTick(address(v3PositionManager), token0, token1, fee);
        (migrationId, data) = SettlementHelpers.generateSettlerData(
            SettlementHelpers.generateV3SettlementParamsUsingCurrentTick(
                user,
                token0,
                token1,
                fee,
                0,
                currentTick,
                range,
                amount0Min,
                amount1Min,
                isToken0BaseToken,
                senderShareBps
            ),
            MigrationModes.SINGLE,
            ""
        );
        return (migrationId, data);
    }

    function genSettlerDataForDualToken(
        address token0,
        address token1,
        uint24 fee,
        SettlementHelpers.Range range,
        bool isToken0BaseToken,
        uint256 routeMinAmount0,
        uint256 routeMinAmount1
    ) public view returns (bytes32 migrationId, bytes memory data) {
        int24 currentTick = UniswapV3Helpers.getCurrentTick(address(v3PositionManager), token0, token1, fee);
        (migrationId, data) = SettlementHelpers.generateSettlerData(
            SettlementHelpers.generateV3SettlementParamsUsingCurrentTick(
                user, token0, token1, fee, 0, currentTick, range, 0, 0, isToken0BaseToken, senderShareBps
            ),
            MigrationModes.DUAL,
            abi.encode(token0, token1, routeMinAmount0, routeMinAmount1)
        );
        return (migrationId, data);
    }

    function genSettlerDataForDualTokenWithSqrtPriceX96(
        address token0,
        address token1,
        uint24 fee,
        SettlementHelpers.Range range,
        bool isToken0BaseToken,
        uint256 routeMinAmount0,
        uint256 routeMinAmount1,
        uint160 sqrtPriceX96
    ) public view returns (bytes32 migrationId, bytes memory data) {
        int24 currentTick = 10000;
        (migrationId, data) = SettlementHelpers.generateSettlerData(
            SettlementHelpers.generateV3SettlementParamsUsingCurrentTick(
                user, token0, token1, fee, sqrtPriceX96, currentTick, range, 0, 0, isToken0BaseToken, senderShareBps
            ),
            MigrationModes.DUAL,
            abi.encode(token0, token1, routeMinAmount0, routeMinAmount1)
        );
        return (migrationId, data);
    }

    function genSettlerDataForDualTokenWithAmounts(
        address token0,
        address token1,
        uint24 fee,
        SettlementHelpers.Range range,
        bool isToken0BaseToken,
        uint256 routeMinAmount0,
        uint256 routeMinAmount1,
        uint256 amount0Min,
        uint256 amount1Min
    ) public view returns (bytes32 migrationId, bytes memory data) {
        int24 currentTick = UniswapV3Helpers.getCurrentTick(address(v3PositionManager), token0, token1, fee);
        (migrationId, data) = SettlementHelpers.generateSettlerData(
            SettlementHelpers.generateV3SettlementParamsUsingCurrentTick(
                user,
                token0,
                token1,
                fee,
                0,
                currentTick,
                range,
                amount0Min,
                amount1Min,
                isToken0BaseToken,
                senderShareBps
            ),
            MigrationModes.DUAL,
            abi.encode(token0, token1, routeMinAmount0, routeMinAmount1)
        );
        return (migrationId, data);
    }

    function assertCorrectAmounts(
        Vm.Log[] memory entries,
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
        // check mint event
        Vm.Log memory mintEvent = findMintEvent(entries);
        uint256 mintAmount0 = 0;
        uint256 mintAmount1 = 0;
        if (mintEvent.data.length > 0) {
            (mintAmount0, mintAmount1) = parseMintEvent(mintEvent.data);
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

    function assertCorrectAmountsDualToken(
        Vm.Log[] memory entries,
        bool didToken0ArriveFirst,
        uint256 expectedAmount0,
        uint256 expectedAmount1
    ) public view {
        // check mint event
        Vm.Log memory mintEvent = findMintEvent(entries);
        uint256 mintAmount0 = 0;
        uint256 mintAmount1 = 0;
        if (mintEvent.data.length > 0) {
            (mintAmount0, mintAmount1) = parseMintEvent(mintEvent.data);
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
    - migrationId check (before either path)
    - Single token path
    - Dual token path (only applicable to both tokens being base tokens and in range)

    TokenPairs to include in tests:
    - weth/usdc (token0: weth/basetoken, token1: usdc)
    - usdc/weth (token0: usdc/erc20, token1: weth/basetoken)
    - usdc/usdt (non-weth base token)

    Ranges & final states to include in tests:
    - fails and is ignored (id doesn't match)
    - fails and is ignored (id matches but first amount is too low) (dual token only)
    - fails and is ignored (id matches but second amount is too low) (dual Token only)
    - fails and is ignored (id matches but token doesn't match)
    - fails and refunds one
    - fails and refunds both (dual token only)
    - succeeds creating a new pool
    - succeeds using an existing pool
      - below tickLower
      - between tickLower and tickUpper
      - above tickUpper
    */

    /**
     * migrationId fails and is ignored
     */
    function test_handleDirectTransfer_failsHashAndIsIgnored() public {
        deal(weth, address(settler), wethAmount);
        vm.recordLogs();
        // generate data
        (bytes32 migrationId, bytes memory data) =
            genSettlerData(weth, usdc, 500, SettlementHelpers.Range.InRange, true);
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
     * SINGLE TOKEN PATHS ***
     */

    // Token0BaseToken scenarios
    function test_handleDirectTransfer_ST_Token0BaseToken_failsAndRefunds() public {
        // generate data with high amount0Min and amount1Min so it'll fail to mint
        deal(weth, address(settler), wethAmount);
        (bytes32 migrationId, bytes memory data) =
            genSettlerDataWithAmounts(weth, usdc, 500, SettlementHelpers.Range.InRange, true, 1 ether, 1 ether);

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
        // generate data
        (bytes32 migrationId, bytes memory data) =
            genSettlerData(weth, usdc, 500, SettlementHelpers.Range.InRange, true);

        // Receipt
        vm.expectEmit(true, true, false, true);
        emit ISettler.Receipt(migrationId, weth, wethAmount);

        vm.expectEmit(true, true, false, false);
        emit IUniswapV3PoolEvents.Swap(address(universalRouter), address(settler), 0, 1, 0, 0, 0);

        // Minting
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Mint(address(settler), address(v3PositionManager), 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // // Sweep remaining tokens to user
        vm.expectEmit(true, true, false, false, address(weth));
        emit IERC20.Transfer(address(settler), address(user), 0);
        vm.expectEmit(true, true, false, false, address(usdc));
        emit IERC20.Transfer(address(settler), address(user), 0);

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

        assertCorrectAmounts(vm.getRecordedLogs(), true, wethAmount, 0);
    }

    function test_handleDirectTransfer_ST_Token0BaseToken_BelowCurrentTick() public {
        deal(weth, address(settler), wethAmount);
        vm.recordLogs();
        // generate data; below tick means only token1 is needed
        (bytes32 migrationId, bytes memory data) =
            genSettlerData(weth, usdc, 500, SettlementHelpers.Range.BelowTick, true);

        // Receipt
        vm.expectEmit(true, true, false, true);
        emit ISettler.Receipt(migrationId, weth, wethAmount);

        vm.expectEmit(true, true, false, false);
        emit IUniswapV3PoolEvents.Swap(address(universalRouter), address(settler), 0, 1, 0, 0, 0);

        // Minting
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Mint(address(settler), address(v3PositionManager), 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Sweep remaining tokens to user
        // should be no tokens to sweep, as everything used to mint

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

        assertCorrectAmounts(vm.getRecordedLogs(), true, wethAmount, 0);
    }

    function test_handleDirectTransfer_ST_Token0BaseToken_AboveCurrentTick() public {
        deal(weth, address(settler), wethAmount);
        vm.recordLogs();
        // generate data; above tick means only token0 is needed
        (bytes32 migrationId, bytes memory data) =
            genSettlerData(weth, usdc, 500, SettlementHelpers.Range.AboveTick, true);

        // Receipt
        vm.expectEmit(true, true, false, true);
        emit ISettler.Receipt(migrationId, weth, wethAmount);

        // swap event
        // no swap event expected

        // Minting
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Mint(address(settler), address(v3PositionManager), 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Sweep remaining tokens to user
        // should be no tokens to sweep, as everything used to mint

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

        assertCorrectAmounts(vm.getRecordedLogs(), true, wethAmount, 0);
    }

    function test_handleDirectTransfer_ST_Token0BaseToken_SingleSided_NewPool() public {
        deal(weth, address(settler), wethAmount);
        vm.recordLogs();
        // generate data; above tick means only token0 is needed
        (bytes32 migrationId, bytes memory data) =
            genSettlerDataWithSqrtPriceX96(weth, newTokenSecond, 500, SettlementHelpers.Range.AboveTick, true, 2 ** 96);

        // Receipt
        vm.expectEmit(true, true, false, true);
        emit ISettler.Receipt(migrationId, weth, wethAmount);

        // swap event
        // no swap event expected

        // pool creation event
        vm.expectEmit(true, true, false, false);
        emit IUniswapV3Factory.PoolCreated(weth, newTokenSecond, 500, 10, address(0));

        // Minting
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Mint(address(settler), address(v3PositionManager), 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Sweep remaining tokens to user
        // should be no tokens to sweep, as everything used to mint

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

        assertCorrectAmounts(vm.getRecordedLogs(), true, wethAmount, 0);
    }

    // Token1BaseToken scenarios
    function test_handleDirectTransfer_ST_Token1BaseToken_failsAndRefunds() public {
        deal(weth, address(settler), wethAmount);
        vm.recordLogs();
        // generate data with high amount0Min and amount1Min so it'll fail to mint
        (bytes32 migrationId, bytes memory data) =
            genSettlerDataWithAmounts(virtualToken, weth, 500, SettlementHelpers.Range.InRange, false, 1 ether, 1 ether);

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
        // generate data
        (bytes32 migrationId, bytes memory data) =
            genSettlerData(virtualToken, weth, 500, SettlementHelpers.Range.InRange, false);

        // Receipt
        vm.expectEmit(true, true, false, true);
        emit ISettler.Receipt(migrationId, weth, wethAmount);

        // swap event
        vm.expectEmit(true, true, false, false);
        emit IUniswapV3PoolEvents.Swap(address(universalRouter), address(settler), 0, 1, 0, 0, 0);

        // Minting
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Mint(address(settler), address(v3PositionManager), 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Sweep remaining tokens to user
        vm.expectEmit(true, true, false, false, address(virtualToken));
        emit IERC20.Transfer(address(settler), address(user), 0);

        vm.expectEmit(true, true, false, false, address(weth));
        emit IERC20.Transfer(address(settler), address(user), 0);

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

        assertCorrectAmounts(vm.getRecordedLogs(), false, 0, wethAmount);
    }

    function test_handleDirectTransfer_ST_Token1BaseToken_BelowCurrentTick() public {
        deal(weth, address(settler), wethAmount);
        vm.recordLogs();
        // generate data
        (bytes32 migrationId, bytes memory data) =
            genSettlerData(virtualToken, weth, 500, SettlementHelpers.Range.BelowTick, false);

        // Receipt
        vm.expectEmit(true, true, false, true);
        emit ISettler.Receipt(migrationId, weth, wethAmount);

        // only token1 is needed
        // swap event
        // no swap event expected

        // Minting
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Mint(address(settler), address(v3PositionManager), 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Sweep remaining tokens to user
        // should be no tokens to sweep, as everything used to mint

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

        assertCorrectAmounts(vm.getRecordedLogs(), false, 0, wethAmount);
    }

    function test_handleDirectTransfer_ST_Token1BaseToken_AboveCurrentTick() public {
        deal(weth, address(settler), wethAmount);
        vm.recordLogs();
        // generate data
        (bytes32 migrationId, bytes memory data) =
            genSettlerData(virtualToken, weth, 500, SettlementHelpers.Range.AboveTick, false);

        // Receipt
        vm.expectEmit(true, true, false, true);
        emit ISettler.Receipt(migrationId, weth, wethAmount);

        // only token0 is needed
        // swap event
        vm.expectEmit(true, true, false, false);
        emit IUniswapV3PoolEvents.Swap(address(universalRouter), address(settler), 0, 1, 0, 0, 0);

        // Minting
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Mint(address(settler), address(v3PositionManager), 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Sweep remaining tokens to user
        // should be no tokens to sweep, as everything used to mint

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

        assertCorrectAmounts(vm.getRecordedLogs(), false, 0, wethAmount);
    }

    function test_handleDirectTransfer_ST_Token1BaseToken_SingleSided_NewPool() public {
        deal(weth, address(settler), wethAmount);
        vm.recordLogs();
        // generate data; above tick means only token0 is needed
        (bytes32 migrationId, bytes memory data) =
            genSettlerDataWithSqrtPriceX96(newTokenFirst, weth, 500, SettlementHelpers.Range.BelowTick, false, 2 ** 96);

        // Receipt
        vm.expectEmit(true, true, false, true);
        emit ISettler.Receipt(migrationId, weth, wethAmount);

        // swap event
        // no swap event expected

        // pool creation event
        vm.expectEmit(true, true, false, false);
        emit IUniswapV3Factory.PoolCreated(newTokenFirst, weth, 500, 10, address(0));

        // Minting
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Mint(address(settler), address(v3PositionManager), 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Sweep remaining tokens to user
        // should be no tokens to sweep, as everything used to mint

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

        assertCorrectAmounts(vm.getRecordedLogs(), false, 0, wethAmount);
    }

    // Non-WETH base token scenarios
    function test_handleDirectTransfer_ST_NonWethBaseToken_failsAndRefunds() public {
        deal(usdc, address(settler), usdcAmount);
        (bytes32 migrationId, bytes memory data) =
            genSettlerDataWithAmounts(usdc, usdt, 100, SettlementHelpers.Range.InRange, true, 1 ether, 1 ether);

        // Receipt
        vm.expectEmit(true, true, false, true);
        emit ISettler.Receipt(migrationId, usdc, usdcAmount);

        // expect the entire weth amount to be transferred to user
        vm.expectEmit(true, true, false, true, address(usdc));
        emit IERC20.Transfer(address(settler), address(user), usdcAmount);

        // expect a refund
        vm.expectEmit(true, true, true, true);
        emit ISettler.Refund(migrationId, address(user), usdc, usdcAmount);

        // call handleDirectTransfer
        settler.handleDirectTransfer(usdc, usdcAmount, data);
    }

    function test_handleDirectTransfer_ST_NonWethBaseToken_InRange() public {
        deal(usdc, address(settler), usdcAmount);

        vm.recordLogs();
        // generate data
        (bytes32 migrationId, bytes memory data) =
            genSettlerData(usdc, usdt, 100, SettlementHelpers.Range.InRange, true);

        // Receipt
        vm.expectEmit(true, true, true, true);
        emit ISettler.Receipt(migrationId, usdc, usdcAmount);

        // swap event
        vm.expectEmit(true, true, false, false);
        emit IUniswapV3PoolEvents.Swap(address(universalRouter), address(settler), 0, 1, 0, 0, 0);

        // Minting
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Mint(address(settler), address(v3PositionManager), 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Sweep remaining tokens to user; only one in this scenario
        vm.expectEmit(true, true, false, false, address(usdc));
        emit IERC20.Transfer(address(settler), address(user), 0);

        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationId,
            usdc,
            uint256(totalProtocolFeeBps) * usdcAmount / 10000,
            uint256(netSenderFeeBps) * usdcAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationId, user, tokenId);

        // call handleDirectTransfer
        settler.handleDirectTransfer(usdc, usdcAmount, data);

        assertCorrectAmounts(vm.getRecordedLogs(), true, usdcAmount, 0);
    }

    function test_handleDirectTransfer_ST_NonWethBaseToken_BelowCurrentTick() public {
        deal(usdc, address(settler), usdcAmount);

        vm.recordLogs();
        // generate data
        (bytes32 migrationId, bytes memory data) =
            genSettlerData(usdc, usdt, 100, SettlementHelpers.Range.BelowTick, true);

        // Receipt
        vm.expectEmit(true, true, false, true);
        emit ISettler.Receipt(migrationId, usdc, usdcAmount);

        // only token1 is needed
        // swap event
        vm.expectEmit(true, true, false, false);
        emit IUniswapV3PoolEvents.Swap(address(universalRouter), address(settler), 0, 1, 0, 0, 0);

        // Minting
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Mint(address(settler), address(v3PositionManager), 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Sweep remaining tokens to user; only one in this scenario
        // no tokens to sweep

        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationId,
            usdc,
            uint256(totalProtocolFeeBps) * usdcAmount / 10000,
            uint256(netSenderFeeBps) * usdcAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationId, user, tokenId);

        // call handleDirectTransfer
        settler.handleDirectTransfer(usdc, usdcAmount, data);

        assertCorrectAmounts(vm.getRecordedLogs(), true, usdcAmount, 0);
    }

    function test_handleDirectTransfer_ST_NonWethBaseToken_AboveCurrentTick() public {
        deal(usdc, address(settler), usdcAmount);

        vm.recordLogs();
        // generate data
        (bytes32 migrationId, bytes memory data) =
            genSettlerData(usdc, usdt, 100, SettlementHelpers.Range.AboveTick, true);

        // Receipt
        vm.expectEmit(true, true, false, true);
        emit ISettler.Receipt(migrationId, usdc, usdcAmount);

        // only token0 is needed
        // swap event
        // no swap event expected

        // Minting
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Mint(address(settler), address(v3PositionManager), 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Sweep remaining tokens to user; only one in this scenario
        // no tokens to sweep
        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationId,
            usdc,
            uint256(totalProtocolFeeBps) * usdcAmount / 10000,
            uint256(netSenderFeeBps) * usdcAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationId, user, tokenId);

        // call handleDirectTransfer
        settler.handleDirectTransfer(usdc, usdcAmount, data);

        assertCorrectAmounts(vm.getRecordedLogs(), true, usdcAmount, 0);
    }

    function test_handleDirectTransfer_ST_NonWethBaseToken_SingleSided_NewPool() public {
        deal(usdc, address(settler), usdcAmount);
        vm.recordLogs();
        // generate data; above tick means only token0 is needed
        (bytes32 migrationId, bytes memory data) =
            genSettlerDataWithSqrtPriceX96(usdc, newTokenSecond, 500, SettlementHelpers.Range.AboveTick, true, 2 ** 96);

        // Receipt
        vm.expectEmit(true, true, false, true);
        emit ISettler.Receipt(migrationId, usdc, usdcAmount);

        // swap event
        // no swap event expected

        // pool creation event
        vm.expectEmit(true, true, false, false);
        emit IUniswapV3Factory.PoolCreated(usdc, newTokenSecond, 500, 10, address(0));

        // Minting
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Mint(address(settler), address(v3PositionManager), 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Sweep remaining tokens to user
        // should be no tokens to sweep, as everything used to mint

        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationId,
            usdc,
            uint256(totalProtocolFeeBps) * usdcAmount / 10000,
            uint256(netSenderFeeBps) * usdcAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationId, user, tokenId);

        // call handleDirectTransfer
        settler.handleDirectTransfer(usdc, usdcAmount, data);

        assertCorrectAmounts(vm.getRecordedLogs(), true, usdcAmount, 0);
    }

    /**
     * DUAL TOKEN PATHS ***
     */
    function test_handleDirectTransfer_DT_FirstBridgeCallFailsWhenFirstAmountTooLowAndIsIgnored() public {
        vm.recordLogs();
        // generate data
        (bytes32 migrationId, bytes memory data) = genSettlerDataForDualToken(
            weth, usdc, 500, SettlementHelpers.Range.InRange, true, wethAmount - 1, usdcAmount - 1
        );

        // call handleDirectTransfer
        vm.expectRevert(bytes("")); // important to use bytes("") as this revert should contain no data
        settler.handleDirectTransfer(weth, wethAmount - 10, data);

        // verify no amounts were transferred
        assertEq(IERC20(weth).balanceOf(address(settler)), 0);
        assertEq(IERC20(usdc).balanceOf(address(settler)), 0);

        // verify settlement cache is not set
        assertEq(settler.checkSettlementCache(migrationId), false);
    }

    function test_handleDirectTransfer_DT_FirstBridgeCallFailsWhenSecondAmountTooLowAndIsIgnored() public {
        vm.recordLogs();
        // generate data
        (bytes32 migrationId, bytes memory data) = genSettlerDataForDualToken(
            weth, usdc, 500, SettlementHelpers.Range.InRange, true, wethAmount - 1, usdcAmount - 1
        );

        // call handleDirectTransfer
        vm.expectRevert(bytes("")); // important to use bytes("") as this revert should contain no data
        settler.handleDirectTransfer(usdc, usdcAmount - 10, data);

        // verify no amounts were transferred
        assertEq(IERC20(weth).balanceOf(address(settler)), 0);
        assertEq(IERC20(usdc).balanceOf(address(settler)), 0);

        // verify settlement cache is not set
        assertEq(settler.checkSettlementCache(migrationId), false);
    }

    function test_handleDirectTransfer_DT_FirstBridgeCallFailsTokenMismatchAndIsIgnored() public {
        vm.recordLogs();
        // generate data
        (bytes32 migrationId, bytes memory data) = genSettlerDataForDualToken(
            weth, usdc, 500, SettlementHelpers.Range.InRange, true, wethAmount - 1, usdcAmount - 1
        );

        // call handleDirectTransfer
        vm.expectRevert(bytes("")); // important to use bytes("") as this revert should contain no data
        settler.handleDirectTransfer(virtualToken, wethAmount - 10, data);

        // verify no amounts were transferred
        assertEq(IERC20(weth).balanceOf(address(settler)), 0);
        assertEq(IERC20(usdc).balanceOf(address(settler)), 0);

        // verify settlement cache is not set
        assertEq(settler.checkSettlementCache(migrationId), false);
    }

    function test_handleDirectTransfer_DT_SecondBridgeCallFailsSecondAmountTooLowAndIsIgnored() public {
        deal(weth, address(settler), wethAmount);
        deal(usdc, address(settler), usdcAmount);
        // generate data
        (bytes32 migrationId, bytes memory data) = genSettlerDataForDualTokenWithAmounts(
            weth, usdc, 500, SettlementHelpers.Range.InRange, true, wethAmount, usdcAmount, wethAmount, usdcAmount
        );

        // first call to handleDirectTransfer; succeeds
        settler.handleDirectTransfer(weth, wethAmount, data);
        assertEq(settler.checkSettlementCache(migrationId), true);

        vm.recordLogs();

        // second call to handleDirectTransfer; ignored
        vm.expectRevert(bytes("")); // important to use bytes("") as this revert should contain no data
        settler.handleDirectTransfer(usdc, 1, data);

        // verify settlement cache still exists
        assertEq(settler.checkSettlementCache(migrationId), true);
        // verify no amounts were transferred
        assertEq(IERC20(weth).balanceOf(address(settler)), wethAmount);
        assertEq(IERC20(usdc).balanceOf(address(settler)), usdcAmount);
    }

    function test_handleDirectTransfer_DT_SecondBridgeCallFailsAndRefundsBoth() public {
        deal(weth, address(settler), wethAmount);
        deal(usdc, address(settler), usdcAmount);
        // generate data
        (bytes32 migrationId, bytes memory data) = genSettlerDataForDualTokenWithAmounts(
            weth, usdc, 500, SettlementHelpers.Range.InRange, true, wethAmount, usdcAmount, wethAmount, usdcAmount
        );

        // first call to handleDirectTransfer; succeeds
        settler.handleDirectTransfer(weth, wethAmount, data);
        assertEq(settler.checkSettlementCache(migrationId), true);

        // Receipt
        vm.expectEmit(true, true, false, true);
        emit ISettler.Receipt(migrationId, usdc, usdcAmount);

        // expect the entire usdc amount to be transferred to user
        vm.expectEmit(true, true, false, true, address(usdc));
        emit IERC20.Transfer(address(settler), address(user), usdcAmount);

        // expect a refund
        vm.expectEmit(true, true, true, true);
        emit ISettler.Refund(migrationId, address(user), usdc, usdcAmount);

        // expect the entire weth amount to be transferred to user
        vm.expectEmit(true, true, false, true, address(weth));
        emit IERC20.Transfer(address(settler), address(user), wethAmount);

        // expect a refund
        vm.expectEmit(true, true, true, true);
        emit ISettler.Refund(migrationId, address(user), weth, wethAmount);

        // second call to handleDirectTransfer fails via catch and refunds both token
        settler.handleDirectTransfer(usdc, usdcAmount, data);

        // verify settlement cache is not set
        assertEq(settler.checkSettlementCache(migrationId), false);
    }

    function test_handleDirectTransfer_DT_InRange_ExistingPool_Token0ArrivesBeforeToken1() public {
        deal(weth, address(settler), wethAmount);
        deal(usdc, address(settler), usdcAmount);
        // generate data
        (bytes32 migrationId, bytes memory data) =
            genSettlerDataForDualToken(weth, usdc, 500, SettlementHelpers.Range.InRange, true, wethAmount, usdcAmount);

        // first call to handleDirectTransfer; succeeds
        settler.handleDirectTransfer(weth, wethAmount, data);
        assertEq(settler.checkSettlementCache(migrationId), true);

        vm.recordLogs();
        // Receipt
        vm.expectEmit(true, true, false, true);
        emit ISettler.Receipt(migrationId, usdc, usdcAmount);

        // Minting
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Mint(address(settler), address(v3PositionManager), 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Sweep remaining tokens to user
        vm.expectEmit(true, true, false, false, address(weth));
        emit IERC20.Transfer(address(settler), address(user), 0);

        // Fee payment
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

        // second call to handleDirectTransfer fails via catch and refunds both token
        settler.handleDirectTransfer(usdc, usdcAmount, data);
        assertCorrectAmountsDualToken(vm.getRecordedLogs(), true, wethAmount, usdcAmount);
    }

    function test_handleDirectTransfer_DT_InRange_ExistingPool_Token1ArrivesBeforeToken0() public {
        deal(weth, address(settler), wethAmount);
        deal(usdc, address(settler), usdcAmount);
        // generate data
        (bytes32 migrationId, bytes memory data) =
            genSettlerDataForDualToken(weth, usdc, 500, SettlementHelpers.Range.InRange, true, wethAmount, usdcAmount);

        // first call to handleDirectTransfer; succeeds
        settler.handleDirectTransfer(usdc, usdcAmount, data);
        assertEq(settler.checkSettlementCache(migrationId), true);

        vm.recordLogs();

        // Receipt
        vm.expectEmit(true, true, false, true);
        emit ISettler.Receipt(migrationId, weth, wethAmount);

        // Minting
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Mint(address(settler), address(v3PositionManager), 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Sweep remaining tokens to user
        vm.expectEmit(true, true, false, false, address(weth));
        emit IERC20.Transfer(address(settler), address(user), 0);

        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationId,
            weth,
            uint256(totalProtocolFeeBps) * wethAmount / 10000,
            uint256(netSenderFeeBps) * wethAmount / 10000
        );

        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationId,
            usdc,
            uint256(totalProtocolFeeBps) * usdcAmount / 10000,
            uint256(netSenderFeeBps) * usdcAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationId, user, tokenId);

        // second call to handleDirectTransfer fails via catch and refunds both token
        settler.handleDirectTransfer(weth, wethAmount, data);
        assertCorrectAmountsDualToken(vm.getRecordedLogs(), false, wethAmount, usdcAmount);
    }

    function test_handleDirectTransfer_DT_InRange_NewPool_Token0ArrivesBeforeToken1() public {
        MockUSDC mockUSDC = new MockUSDC("Mock USDT", "USDT", address(settler), usdcAmount);
        deal(weth, address(settler), wethAmount);
        deal(address(mockUSDC), address(settler), usdcAmount);
        // generate data
        (bytes32 migrationId, bytes memory data) = genSettlerDataForDualTokenWithSqrtPriceX96(
            weth, address(mockUSDC), 10000, SettlementHelpers.Range.InRange, true, wethAmount, usdcAmount, 2 ** 96
        );

        // first call to handleDirectTransfer; succeeds
        settler.handleDirectTransfer(weth, wethAmount, data);
        assertEq(settler.checkSettlementCache(migrationId), true);

        vm.recordLogs();

        // Receipt
        vm.expectEmit(true, true, false, true);
        emit ISettler.Receipt(migrationId, address(mockUSDC), usdcAmount);

        // pool creation event
        vm.expectEmit(true, true, false, false);
        emit IUniswapV3Factory.PoolCreated(weth, address(mockUSDC), 10000, 10, address(0));

        // Minting
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Mint(address(settler), address(v3PositionManager), 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Sweep remaining tokens to user
        vm.expectEmit(true, true, false, false, address(weth));
        emit IERC20.Transfer(address(settler), address(user), 0);

        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationId,
            address(mockUSDC),
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

        // second call to handleDirectTransfer fails via catch and refunds both token
        settler.handleDirectTransfer(address(mockUSDC), usdcAmount, data);
        assertCorrectAmountsDualToken(vm.getRecordedLogs(), true, wethAmount, usdcAmount);
    }

    function test_handleDirectTransfer_DT_InRange_NewPool_Token1ArrivesBeforeToken0() public {
        MockUSDC mockUSDC = new MockUSDC("Mock USDT", "USDT", address(settler), usdcAmount);
        deal(weth, address(settler), wethAmount);
        deal(address(mockUSDC), address(settler), usdcAmount);
        // generate data
        (bytes32 migrationId, bytes memory data) = genSettlerDataForDualTokenWithSqrtPriceX96(
            weth, address(mockUSDC), 10000, SettlementHelpers.Range.InRange, true, wethAmount, usdcAmount, 2 ** 96
        );

        // first call to handleDirectTransfer; succeeds
        settler.handleDirectTransfer(address(mockUSDC), usdcAmount, data);
        assertEq(settler.checkSettlementCache(migrationId), true);

        vm.recordLogs();

        // Receipt
        vm.expectEmit(true, true, false, true);
        emit ISettler.Receipt(migrationId, weth, wethAmount);

        // pool creation event
        vm.expectEmit(true, true, false, false);
        emit IUniswapV3Factory.PoolCreated(weth, address(mockUSDC), 10000, 10, address(0));

        // Minting
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Mint(address(settler), address(v3PositionManager), 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), user, tokenId);

        // Sweep remaining tokens to user
        vm.expectEmit(true, true, false, false, address(weth));
        emit IERC20.Transfer(address(settler), address(user), 0);

        // Fee payment
        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationId,
            weth,
            uint256(totalProtocolFeeBps) * wethAmount / 10000,
            uint256(netSenderFeeBps) * wethAmount / 10000
        );

        vm.expectEmit(true, true, false, true);
        emit ISettler.FeePayment(
            migrationId,
            address(mockUSDC),
            uint256(totalProtocolFeeBps) * usdcAmount / 10000,
            uint256(netSenderFeeBps) * usdcAmount / 10000
        );

        // Settlement
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(migrationId, user, tokenId);

        // second call to handleDirectTransfer fails via catch and refunds both token
        settler.handleDirectTransfer(weth, wethAmount, data);
        assertCorrectAmountsDualToken(vm.getRecordedLogs(), false, wethAmount, usdcAmount);
    }

    function test() public override(TestContext, UniswapV3Helpers) {}
}
