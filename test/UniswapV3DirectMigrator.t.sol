// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Test.sol";
import {TestContext} from "./utils/TestContext.sol";
import {IMigrator} from "../src/interfaces/IMigrator.sol";
import {IDirectMigrator} from "../src/interfaces/IDirectMigrator.sol";
import {ISettler} from "../src/interfaces/ISettler.sol";
import {IUniswapV3Settler} from "../src/interfaces/IUniswapV3Settler.sol";
import {UniswapV3DirectMigrator} from "../src/UniswapV3DirectMigrator.sol";
import {UniswapV3DirectSettler} from "../src/UniswapV3DirectSettler.sol";
import {UniswapV3Helpers} from "./utils/UniswapV3Helpers.sol";
import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {INonfungiblePositionManager} from "../src/interfaces/external/INonfungiblePositionManager.sol";
import {IUniswapV3PoolEvents} from "@uniswap-v3-core/interfaces/pool/IUniswapV3PoolEvents.sol";
import {MigrationModes, MigrationMode} from "../src/types/MigrationMode.sol";
import {MigrationHelpers} from "./utils/MigrationHelpers.sol";
import {MigrationData} from "../src/types/MigrationData.sol";

contract UniswapV3DirectMigratorTest is TestContext, UniswapV3Helpers {
    string public constant SRC_CHAIN_NAME = "BASE";
    string public constant DEST_CHAIN_NAME = "";
    UniswapV3DirectSettler public settler;
    UniswapV3DirectMigrator public migrator;
    uint256 public sourceChainId = 8453;

    function setUp() public {
        _loadChain(SRC_CHAIN_NAME, DEST_CHAIN_NAME);

        vm.prank(owner);
        settler =
            new UniswapV3DirectSettler(owner, address(v3PositionManager), address(universalRouter), address(permit2));

        vm.prank(owner);
        migrator = new UniswapV3DirectMigrator(
            owner, address(v3PositionManager), address(universalRouter), address(permit2), weth
        );

        // Configure the settler
        vm.startPrank(owner);
        settler.setProtocolFeeRecipient(owner);
        settler.setProtocolShareBps(100);
        settler.setProtocolShareOfSenderFeePct(10);
        vm.stopPrank();

        // Set the settler for the current chain
        vm.prank(owner);
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = sourceChainId;
        address[] memory settlers = new address[](1);
        settlers[0] = address(settler);
        bool[] memory values = new bool[](1);
        values[0] = true;
        migrator.setChainSettlers(chainIds, settlers, values);
    }

    /*
    TokenPairs to include in tests:
    - weth/usdc (token0: weth/default basetoken, token1: usdc/second basetoken for dual token paths)
    - usdt/weth (token0: usdt and token1: weth/basetoken)
    - usdc/usdt (non-weth token pair with usdc as base token)

    Ranges to include in tests:
    - below tickLower
    - between tickLower and tickUpper (in-range)
    - above tickUpper

    Paths to include in tests:
    - Single token path
    - Dual token path (only applicable to both tokens being base tokens and in range)
    */

    // Helper function to generate migration params for direct migration (same chain)
    function generateDirectMigrationParams(address token, address settlerAddress, uint256 amountOutMin)
        internal
        view
        returns (IMigrator.MigrationParams memory)
    {
        address[] memory tokensSourceChain = new address[](1);
        tokensSourceChain[0] = token;
        address[] memory tokensDestinationChain = new address[](1);
        tokensDestinationChain[0] = token;
        uint256[] memory amountOutMins = new uint256[](1);
        amountOutMins[0] = amountOutMin;

        // generate routes
        IMigrator.TokenRoute[] memory tokenRoutes = new IMigrator.TokenRoute[](tokensSourceChain.length);

        for (uint256 i = 0; i < tokensSourceChain.length; i++) {
            // For direct migration, we don't need route data since it's same-chain
            tokenRoutes[i] =
                IMigrator.TokenRoute({token: tokensSourceChain[i], amountOutMin: amountOutMins[i], route: ""});
        }

        return IMigrator.MigrationParams({
            chainId: sourceChainId, // Use current chain ID
            settler: settlerAddress,
            tokenRoutes: tokenRoutes,
            settlementParams: ""
        });
    }

    function generateDirectMigrationParams(
        address token0,
        address token1,
        address token0Destination,
        address token1Destination,
        uint256 amountOutMin0,
        uint256 amountOutMin1,
        address settlerAddress
    ) internal view returns (IMigrator.MigrationParams memory) {
        address[] memory tokensSourceChain = new address[](2);
        tokensSourceChain[0] = token0;
        tokensSourceChain[1] = token1;
        address[] memory tokensDestinationChain = new address[](2);
        tokensDestinationChain[0] = token0Destination;
        tokensDestinationChain[1] = token1Destination;
        uint256[] memory amountOutMins = new uint256[](2);
        amountOutMins[0] = amountOutMin0;
        amountOutMins[1] = amountOutMin1;

        // generate routes
        IMigrator.TokenRoute[] memory tokenRoutes = new IMigrator.TokenRoute[](tokensSourceChain.length);

        for (uint256 i = 0; i < tokensSourceChain.length; i++) {
            // For direct migration, we don't need route data since it's same-chain
            tokenRoutes[i] =
                IMigrator.TokenRoute({token: tokensSourceChain[i], amountOutMin: amountOutMins[i], route: ""});
        }

        return IMigrator.MigrationParams({
            chainId: sourceChainId, // Use current chain ID
            settler: settlerAddress,
            tokenRoutes: tokenRoutes,
            settlementParams: ""
        });
    }

    /**
     * SINGLE TOKEN PATHS ***
     */
    function test_onERC721Received_Token0WETHBaseToken_InRange() public {
        vm.recordLogs();
        address token0 = weth;
        address token1 = usdc;
        // current tick is ~ -201000
        (uint256 tokenId, uint256 amount0,) =
            mintV3Position(address(v3PositionManager), user, token0, token1, -250000, -100000, 500);

        // verify posToken0 is baseToken
        (,, address posToken0,,,,,,,,,) = v3PositionManager.positions(tokenId);
        assertEq(posToken0, token0);

        IMigrator.MigrationParams memory migrationParams =
            generateDirectMigrationParams(token0, address(settler), amount0 - 1);

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationId = migrationData.toId();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v3PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false, address(v3PositionManager));
        emit INonfungiblePositionManager.DecreaseLiquidity(tokenId, 0, 0, 0);

        // collect
        vm.expectEmit(true, false, false, false, address(v3PositionManager));
        emit INonfungiblePositionManager.Collect(tokenId, address(0), 0, 0);

        // Swap
        vm.expectEmit(true, true, false, false);
        emit IUniswapV3PoolEvents.Swap(address(universalRouter), address(migrator), 0, 0, 0, 0, 0);

        // Direct transfer to settler or user (dynamic check)
        // vm.expectEmit(true, true, true, true);
        // emit IERC20.Transfer(address(migrator), address(settler), 0);

        // No expectEmit for MigrationStarted; instead, check the event after the call
        vm.prank(user);
        v3PositionManager.safeTransferFrom(user, address(migrator), tokenId, abi.encode(migrationParams));

        // verify the transfer happened
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log[] memory swapEvents = findSwapEvents(entries);
        if (swapEvents.length > 0) {
            uint256 swapOutAmount = parseSwapEvent(swapEvents[0].data);
        }
        // Find the transfer event from migrator to settler or user
        bool foundTransfer = false;
        uint256 transferredAmount = 0;
        address recipient;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics.length > 0 && entries[i].topics[0] == IERC20.Transfer.selector) {
                address from = address(uint160(uint256(entries[i].topics[1])));
                address to = address(uint160(uint256(entries[i].topics[2])));
                if (from == address(migrator) && (to == address(settler) || to == user)) {
                    transferredAmount = parseTransferEvent(entries[i].data);
                    recipient = to;
                    foundTransfer = true;
                    break;
                }
            }
        }
        assertTrue(foundTransfer, "Transfer from migrator to settler or user not found");
        assertGt(transferredAmount, 0);

        // Find the MigrationStarted event in the logs and check its parameters
        bool foundMigrationStarted = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics.length > 0 && entries[i].topics[0] == IMigrator.MigrationStarted.selector) {
                // Decode topics and data
                bytes32 emittedMigrationId = entries[i].topics[1];
                uint256 loggedPositionId = uint256(entries[i].topics[2]);
                uint256 loggedChainId = uint256(entries[i].topics[3]);
                (
                    address loggedSettler,
                    MigrationMode loggedMode,
                    address loggedSender,
                    address loggedToken,
                    uint256 loggedAmount
                ) = abi.decode(entries[i].data, (address, MigrationMode, address, address, uint256));
                assertTrue(emittedMigrationId != bytes32(0), "migrationId should not be zero");
                assertEq(loggedPositionId, tokenId, "positionId mismatch");
                assertEq(loggedChainId, sourceChainId, "chainId mismatch");
                assertEq(loggedSettler, address(settler), "settler mismatch");
                assertTrue(loggedMode == MigrationModes.SINGLE, "mode mismatch");
                assertEq(loggedSender, user, "sender mismatch");
                assertEq(loggedToken, token0, "token mismatch");
                // Amount is dynamic, but should be > 0
                assertGt(loggedAmount, 0);
                foundMigrationStarted = true;
                break;
            }
        }
        assertTrue(foundMigrationStarted, "MigrationStarted event not found");
    }

    function test_onERC721Received_Token0WETHBaseToken_BelowCurrentTick() public {
        vm.recordLogs();
        address token0 = weth;
        address token1 = usdc;
        // current tick is ~ -201000

        (uint256 tokenId, uint256 amount0,) =
            mintV3Position(address(v3PositionManager), user, token0, token1, -250000, -210000, 500);
        // only token1 is used

        // verify posToken0 is baseToken
        (,, address posToken0,,,,,,,,,) = v3PositionManager.positions(tokenId);
        assertEq(posToken0, token0);

        IMigrator.MigrationParams memory migrationParams = generateDirectMigrationParams(token0, address(settler), 1);

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationId = migrationData.toId();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v3PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false, address(v3PositionManager));
        emit INonfungiblePositionManager.DecreaseLiquidity(tokenId, 0, 0, 0);

        // collect
        vm.expectEmit(true, false, false, false, address(v3PositionManager));
        emit INonfungiblePositionManager.Collect(tokenId, address(0), 0, 0);

        // Swap
        vm.expectEmit(true, true, false, false);
        emit IUniswapV3PoolEvents.Swap(address(universalRouter), address(migrator), 0, 0, 0, 0, 0);

        // Direct transfer to settler or user (dynamic check)
        // vm.expectEmit(true, true, true, true);
        // emit IERC20.Transfer(address(migrator), address(settler), 0);

        // No expectEmit for MigrationStarted; instead, check the event after the call
        vm.prank(user);
        v3PositionManager.safeTransferFrom(user, address(migrator), tokenId, abi.encode(migrationParams));

        // verify the transfer happened
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log[] memory swapEvents = findSwapEvents(entries);
        if (swapEvents.length > 0) {
            uint256 swapOutAmount = parseSwapEvent(swapEvents[0].data);
        }
        // Find the transfer event from migrator to settler or user
        bool foundTransfer = false;
        uint256 transferredAmount = 0;
        address recipient;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics.length > 0 && entries[i].topics[0] == IERC20.Transfer.selector) {
                address from = address(uint160(uint256(entries[i].topics[1])));
                address to = address(uint160(uint256(entries[i].topics[2])));
                if (from == address(migrator) && (to == address(settler) || to == user)) {
                    transferredAmount = parseTransferEvent(entries[i].data);
                    recipient = to;
                    foundTransfer = true;
                    break;
                }
            }
        }
        assertTrue(foundTransfer, "Transfer from migrator to settler or user not found");
        assertGt(transferredAmount, 0);

        // Find the MigrationStarted event in the logs and check its parameters
        bool foundMigrationStarted = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics.length > 0 && entries[i].topics[0] == IMigrator.MigrationStarted.selector) {
                // Decode topics and data
                bytes32 emittedMigrationId = entries[i].topics[1];
                uint256 loggedPositionId = uint256(entries[i].topics[2]);
                uint256 loggedChainId = uint256(entries[i].topics[3]);
                (
                    address loggedSettler,
                    MigrationMode loggedMode,
                    address loggedSender,
                    address loggedToken,
                    uint256 loggedAmount
                ) = abi.decode(entries[i].data, (address, MigrationMode, address, address, uint256));
                assertTrue(emittedMigrationId != bytes32(0), "migrationId should not be zero");
                assertEq(loggedPositionId, tokenId, "positionId mismatch");
                assertEq(loggedChainId, sourceChainId, "chainId mismatch");
                assertEq(loggedSettler, address(settler), "settler mismatch");
                assertTrue(loggedMode == MigrationModes.SINGLE, "mode mismatch");
                assertEq(loggedSender, user, "sender mismatch");
                assertEq(loggedToken, token0, "token mismatch");
                // Amount is dynamic, but should be > 0
                assertGt(loggedAmount, 0);
                foundMigrationStarted = true;
                break;
            }
        }
        assertTrue(foundMigrationStarted, "MigrationStarted event not found");
    }

    function test_onERC721Received_Token0WETHBaseToken_AboveCurrentTick() public {
        vm.recordLogs();
        address token0 = weth;
        address token1 = usdc;
        // current tick is ~ -201000
        (uint256 tokenId, uint256 amount0,) =
            mintV3Position(address(v3PositionManager), user, token0, token1, -150000, -100000, 500);

        // only token0 is used, so no swap is needed

        // verify posToken0 is baseToken
        (,, address posToken0,,,,,,,,,) = v3PositionManager.positions(tokenId);
        assertEq(posToken0, token0);

        IMigrator.MigrationParams memory migrationParams =
            generateDirectMigrationParams(token0, address(settler), amount0 - 1);

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationId = migrationData.toId();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v3PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false, address(v3PositionManager));
        emit INonfungiblePositionManager.DecreaseLiquidity(tokenId, 0, 0, 0);

        // collect
        vm.expectEmit(true, false, false, false, address(v3PositionManager));
        emit INonfungiblePositionManager.Collect(tokenId, address(0), 0, 0);

        // swap
        // not needed

        // Direct transfer to settler or user (dynamic check)
        // vm.expectEmit(true, true, true, true);
        // emit IERC20.Transfer(address(migrator), address(settler), 0);

        // No expectEmit for MigrationStarted; instead, check the event after the call
        vm.prank(user);
        v3PositionManager.safeTransferFrom(user, address(migrator), tokenId, abi.encode(migrationParams));

        // verify the transfer happened
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Find the transfer event from migrator to settler or user
        bool foundTransfer = false;
        uint256 transferredAmount = 0;
        address recipient;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics.length > 0 && entries[i].topics[0] == IERC20.Transfer.selector) {
                address from = address(uint160(uint256(entries[i].topics[1])));
                address to = address(uint160(uint256(entries[i].topics[2])));
                if (from == address(migrator) && (to == address(settler) || to == user)) {
                    transferredAmount = parseTransferEvent(entries[i].data);
                    recipient = to;
                    foundTransfer = true;
                    break;
                }
            }
        }
        assertTrue(foundTransfer, "Transfer from migrator to settler or user not found");
        assertGt(transferredAmount, 0);

        // Find the MigrationStarted event in the logs and check its parameters
        bool foundMigrationStarted = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics.length > 0 && entries[i].topics[0] == IMigrator.MigrationStarted.selector) {
                // Decode topics and data
                bytes32 emittedMigrationId = entries[i].topics[1];
                uint256 loggedPositionId = uint256(entries[i].topics[2]);
                uint256 loggedChainId = uint256(entries[i].topics[3]);
                (
                    address loggedSettler,
                    MigrationMode loggedMode,
                    address loggedSender,
                    address loggedToken,
                    uint256 loggedAmount
                ) = abi.decode(entries[i].data, (address, MigrationMode, address, address, uint256));
                assertTrue(emittedMigrationId != bytes32(0), "migrationId should not be zero");
                assertEq(loggedPositionId, tokenId, "positionId mismatch");
                assertEq(loggedChainId, sourceChainId, "chainId mismatch");
                assertEq(loggedSettler, address(settler), "settler mismatch");
                assertTrue(loggedMode == MigrationModes.SINGLE, "mode mismatch");
                assertEq(loggedSender, user, "sender mismatch");
                assertEq(loggedToken, token0, "token mismatch");
                // Amount is dynamic, but should be > 0
                assertGt(loggedAmount, 0);
                foundMigrationStarted = true;
                break;
            }
        }
        assertTrue(foundMigrationStarted, "MigrationStarted event not found");
    }

    function test_onERC721Received_Token1WETHBaseToken_InRange() public {
        vm.recordLogs();
        address token0 = virtualToken;
        address token1 = weth;
        (uint256 tokenId,, uint256 amount1) =
            mintV3Position(address(v3PositionManager), user, token0, token1, -200000, -5000, 500);

        // verify posToken0 is baseToken
        (,,, address posToken1,,,,,,,,) = v3PositionManager.positions(tokenId);
        assertEq(posToken1, token1);

        IMigrator.MigrationParams memory migrationParams =
            generateDirectMigrationParams(token1, address(settler), amount1 - 1);

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationId = migrationData.toId();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v3PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false, address(v3PositionManager));
        emit INonfungiblePositionManager.DecreaseLiquidity(tokenId, 0, 0, 0);

        // collect
        vm.expectEmit(true, false, false, false, address(v3PositionManager));
        emit INonfungiblePositionManager.Collect(tokenId, address(0), 0, 0);

        // Swap
        vm.expectEmit(true, true, false, false);
        emit IUniswapV3PoolEvents.Swap(address(universalRouter), address(migrator), 0, 0, 0, 0, 0);

        // Direct transfer to settler or user (dynamic check)
        // vm.expectEmit(true, true, true, true);
        // emit IERC20.Transfer(address(migrator), address(settler), 0);

        // No expectEmit for MigrationStarted; instead, check the event after the call
        vm.prank(user);
        v3PositionManager.safeTransferFrom(user, address(migrator), tokenId, abi.encode(migrationParams));

        // verify the transfer happened
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log[] memory swapEvents = findSwapEvents(entries);
        if (swapEvents.length > 0) {
            uint256 swapOutAmount = parseSwapEvent(swapEvents[0].data);
        }
        // Find the transfer event from migrator to settler or user
        bool foundTransfer = false;
        uint256 transferredAmount = 0;
        address recipient;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics.length > 0 && entries[i].topics[0] == IERC20.Transfer.selector) {
                address from = address(uint160(uint256(entries[i].topics[1])));
                address to = address(uint160(uint256(entries[i].topics[2])));
                if (from == address(migrator) && (to == address(settler) || to == user)) {
                    transferredAmount = parseTransferEvent(entries[i].data);
                    recipient = to;
                    foundTransfer = true;
                    break;
                }
            }
        }
        assertTrue(foundTransfer, "Transfer from migrator to settler or user not found");
        assertGt(transferredAmount, 0);

        // Find the MigrationStarted event in the logs and check its parameters
        bool foundMigrationStarted = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics.length > 0 && entries[i].topics[0] == IMigrator.MigrationStarted.selector) {
                // Decode topics and data
                bytes32 emittedMigrationId = entries[i].topics[1];
                uint256 loggedPositionId = uint256(entries[i].topics[2]);
                uint256 loggedChainId = uint256(entries[i].topics[3]);
                (
                    address loggedSettler,
                    MigrationMode loggedMode,
                    address loggedSender,
                    address loggedToken,
                    uint256 loggedAmount
                ) = abi.decode(entries[i].data, (address, MigrationMode, address, address, uint256));
                assertTrue(emittedMigrationId != bytes32(0), "migrationId should not be zero");
                assertEq(loggedPositionId, tokenId, "positionId mismatch");
                assertEq(loggedChainId, sourceChainId, "chainId mismatch");
                assertEq(loggedSettler, address(settler), "settler mismatch");
                assertTrue(loggedMode == MigrationModes.SINGLE, "mode mismatch");
                assertEq(loggedSender, user, "sender mismatch");
                assertEq(loggedToken, token1, "token mismatch");
                // Amount is dynamic, but should be > 0
                assertGt(loggedAmount, 0);
                foundMigrationStarted = true;
                break;
            }
        }
        assertTrue(foundMigrationStarted, "MigrationStarted event not found");
    }

    function test_onERC721Received_Token1WETHBaseToken_BelowCurrentTick() public {
        vm.recordLogs();
        address token0 = virtualToken;
        address token1 = weth;
        (uint256 tokenId,, uint256 amount1) =
            mintV3Position(address(v3PositionManager), user, token0, token1, -200000, -100000, 500);

        // only token1 is used; no swap is needed

        // verify posToken0 is baseToken
        (,,, address posToken1,,,,,,,,) = v3PositionManager.positions(tokenId);
        assertEq(posToken1, token1);

        IMigrator.MigrationParams memory migrationParams =
            generateDirectMigrationParams(token1, address(settler), amount1 - 1);

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationId = migrationData.toId();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v3PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false, address(v3PositionManager));
        emit INonfungiblePositionManager.DecreaseLiquidity(tokenId, 0, 0, 0);

        // collect
        vm.expectEmit(true, false, false, false, address(v3PositionManager));
        emit INonfungiblePositionManager.Collect(tokenId, address(0), 0, 0);

        // Swap
        // not needed

        // Direct transfer to settler or user (dynamic check)
        // vm.expectEmit(true, true, true, true);
        // emit IERC20.Transfer(address(migrator), address(settler), 0);

        // No expectEmit for MigrationStarted; instead, check the event after the call
        vm.prank(user);
        v3PositionManager.safeTransferFrom(user, address(migrator), tokenId, abi.encode(migrationParams));

        // verify the transfer happened
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Find the transfer event from migrator to settler or user
        bool foundTransfer = false;
        uint256 transferredAmount = 0;
        address recipient;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics.length > 0 && entries[i].topics[0] == IERC20.Transfer.selector) {
                address from = address(uint160(uint256(entries[i].topics[1])));
                address to = address(uint160(uint256(entries[i].topics[2])));
                if (from == address(migrator) && (to == address(settler) || to == user)) {
                    transferredAmount = parseTransferEvent(entries[i].data);
                    recipient = to;
                    foundTransfer = true;
                    break;
                }
            }
        }
        assertTrue(foundTransfer, "Transfer from migrator to settler or user not found");
        assertGt(transferredAmount, 0);

        // Find the MigrationStarted event in the logs and check its parameters
        bool foundMigrationStarted = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics.length > 0 && entries[i].topics[0] == IMigrator.MigrationStarted.selector) {
                // Decode topics and data
                bytes32 emittedMigrationId = entries[i].topics[1];
                uint256 loggedPositionId = uint256(entries[i].topics[2]);
                uint256 loggedChainId = uint256(entries[i].topics[3]);
                (
                    address loggedSettler,
                    MigrationMode loggedMode,
                    address loggedSender,
                    address loggedToken,
                    uint256 loggedAmount
                ) = abi.decode(entries[i].data, (address, MigrationMode, address, address, uint256));
                assertTrue(emittedMigrationId != bytes32(0), "migrationId should not be zero");
                assertEq(loggedPositionId, tokenId, "positionId mismatch");
                assertEq(loggedChainId, sourceChainId, "chainId mismatch");
                assertEq(loggedSettler, address(settler), "settler mismatch");
                assertTrue(loggedMode == MigrationModes.SINGLE, "mode mismatch");
                assertEq(loggedSender, user, "sender mismatch");
                assertEq(loggedToken, token1, "token mismatch");
                // Amount is dynamic, but should be > 0
                assertGt(loggedAmount, 0);
                foundMigrationStarted = true;
                break;
            }
        }
        assertTrue(foundMigrationStarted, "MigrationStarted event not found");
    }

    function test_onERC721Received_Token1WETHBaseToken_AboveCurrentTick() public {
        vm.recordLogs();
        address token0 = virtualToken;
        address token1 = weth;
        (uint256 tokenId,, uint256 amount1) =
            mintV3Position(address(v3PositionManager), user, token0, token1, -200000, -5000, 500);

        // only token0 is used

        // verify posToken0 is baseToken
        (,,, address posToken1,,,,,,,,) = v3PositionManager.positions(tokenId);
        assertEq(posToken1, token1);

        IMigrator.MigrationParams memory migrationParams =
            generateDirectMigrationParams(token1, address(settler), amount1 - 1);

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationId = migrationData.toId();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v3PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false, address(v3PositionManager));
        emit INonfungiblePositionManager.DecreaseLiquidity(tokenId, 0, 0, 0);

        // collect
        vm.expectEmit(true, false, false, false, address(v3PositionManager));
        emit INonfungiblePositionManager.Collect(tokenId, address(0), 0, 0);

        // Swap
        vm.expectEmit(true, true, false, false);
        emit IUniswapV3PoolEvents.Swap(address(universalRouter), address(migrator), 0, 0, 0, 0, 0);

        // Direct transfer to settler or user (dynamic check)
        // vm.expectEmit(true, true, true, true);
        // emit IERC20.Transfer(address(migrator), address(settler), 0);

        // No expectEmit for MigrationStarted; instead, check the event after the call
        vm.prank(user);
        v3PositionManager.safeTransferFrom(user, address(migrator), tokenId, abi.encode(migrationParams));

        // verify the transfer happened
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Find the transfer event from migrator to settler or user
        bool foundTransfer = false;
        uint256 transferredAmount = 0;
        address recipient;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics.length > 0 && entries[i].topics[0] == IERC20.Transfer.selector) {
                address from = address(uint160(uint256(entries[i].topics[1])));
                address to = address(uint160(uint256(entries[i].topics[2])));
                if (from == address(migrator) && (to == address(settler) || to == user)) {
                    transferredAmount = parseTransferEvent(entries[i].data);
                    recipient = to;
                    foundTransfer = true;
                    break;
                }
            }
        }
        assertTrue(foundTransfer, "Transfer from migrator to settler or user not found");
        assertGt(transferredAmount, 0);

        // Find the MigrationStarted event in the logs and check its parameters
        bool foundMigrationStarted = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics.length > 0 && entries[i].topics[0] == IMigrator.MigrationStarted.selector) {
                // Decode topics and data
                bytes32 emittedMigrationId = entries[i].topics[1];
                uint256 loggedPositionId = uint256(entries[i].topics[2]);
                uint256 loggedChainId = uint256(entries[i].topics[3]);
                (
                    address loggedSettler,
                    MigrationMode loggedMode,
                    address loggedSender,
                    address loggedToken,
                    uint256 loggedAmount
                ) = abi.decode(entries[i].data, (address, MigrationMode, address, address, uint256));
                assertTrue(emittedMigrationId != bytes32(0), "migrationId should not be zero");
                assertEq(loggedPositionId, tokenId, "positionId mismatch");
                assertEq(loggedChainId, sourceChainId, "chainId mismatch");
                assertEq(loggedSettler, address(settler), "settler mismatch");
                assertTrue(loggedMode == MigrationModes.SINGLE, "mode mismatch");
                assertEq(loggedSender, user, "sender mismatch");
                assertEq(loggedToken, token1, "token mismatch");
                // Amount is dynamic, but should be > 0
                assertGt(loggedAmount, 0);
                foundMigrationStarted = true;
                break;
            }
        }
        assertTrue(foundMigrationStarted, "MigrationStarted event not found");
    }

    function test_onERC721Received_Token0USDCBaseToken_NoWETH_InRange() public {
        vm.recordLogs();
        address token0 = usdc;
        address token1 = usdt;
        // current tick is ~ -201000
        (uint256 tokenId, uint256 amount0,) =
            mintV3Position(address(v3PositionManager), user, token0, token1, -5000, 5000, 100);

        // verify posToken0 is baseToken
        (,, address posToken0,,,,,,,,,) = v3PositionManager.positions(tokenId);
        assertEq(posToken0, token0);

        IMigrator.MigrationParams memory migrationParams =
            generateDirectMigrationParams(token0, address(settler), amount0 - 1);

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationId = migrationData.toId();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v3PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false, address(v3PositionManager));
        emit INonfungiblePositionManager.DecreaseLiquidity(tokenId, 0, 0, 0);

        // collect
        vm.expectEmit(true, false, false, false, address(v3PositionManager));
        emit INonfungiblePositionManager.Collect(tokenId, address(0), 0, 0);

        // Swap
        vm.expectEmit(true, true, false, false);
        emit IUniswapV3PoolEvents.Swap(address(universalRouter), address(migrator), 0, 0, 0, 0, 0);

        // Direct transfer to settler or user (dynamic check)
        // vm.expectEmit(true, true, true, true);
        // emit IERC20.Transfer(address(migrator), address(settler), 0);

        // No expectEmit for MigrationStarted; instead, check the event after the call
        vm.prank(user);
        v3PositionManager.safeTransferFrom(user, address(migrator), tokenId, abi.encode(migrationParams));

        // verify the transfer happened
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log[] memory swapEvents = findSwapEvents(entries);
        if (swapEvents.length > 0) {
            uint256 swapOutAmount = parseSwapEvent(swapEvents[0].data);
        }
        // Find the transfer event from migrator to settler or user
        bool foundTransfer = false;
        uint256 transferredAmount = 0;
        address recipient;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics.length > 0 && entries[i].topics[0] == IERC20.Transfer.selector) {
                address from = address(uint160(uint256(entries[i].topics[1])));
                address to = address(uint160(uint256(entries[i].topics[2])));
                if (from == address(migrator) && (to == address(settler) || to == user)) {
                    transferredAmount = parseTransferEvent(entries[i].data);
                    recipient = to;
                    foundTransfer = true;
                    break;
                }
            }
        }
        assertTrue(foundTransfer, "Transfer from migrator to settler or user not found");
        assertGt(transferredAmount, 0);

        // Find the MigrationStarted event in the logs and check its parameters
        bool foundMigrationStarted = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics.length > 0 && entries[i].topics[0] == IMigrator.MigrationStarted.selector) {
                // Decode topics and data
                bytes32 emittedMigrationId = entries[i].topics[1];
                uint256 loggedPositionId = uint256(entries[i].topics[2]);
                uint256 loggedChainId = uint256(entries[i].topics[3]);
                (
                    address loggedSettler,
                    MigrationMode loggedMode,
                    address loggedSender,
                    address loggedToken,
                    uint256 loggedAmount
                ) = abi.decode(entries[i].data, (address, MigrationMode, address, address, uint256));
                assertTrue(emittedMigrationId != bytes32(0), "migrationId should not be zero");
                assertEq(loggedPositionId, tokenId, "positionId mismatch");
                assertEq(loggedChainId, sourceChainId, "chainId mismatch");
                assertEq(loggedSettler, address(settler), "settler mismatch");
                assertTrue(loggedMode == MigrationModes.SINGLE, "mode mismatch");
                assertEq(loggedSender, user, "sender mismatch");
                assertEq(loggedToken, token0, "token mismatch");
                // Amount is dynamic, but should be > 0
                assertGt(loggedAmount, 0);
                foundMigrationStarted = true;
                break;
            }
        }
        assertTrue(foundMigrationStarted, "MigrationStarted event not found");
    }

    function test_onERC721Received_Token0USDCBaseToken_NoWETH_BelowCurrentTick() public {
        vm.recordLogs();
        address token0 = usdc;
        address token1 = usdt;
        // current tick is ~ -201000
        (uint256 tokenId, uint256 amount0,) =
            mintV3Position(address(v3PositionManager), user, token0, token1, -1000, -100, 100);

        // only token1 is used

        // verify posToken0 is baseToken
        (,, address posToken0,,,,,,,,,) = v3PositionManager.positions(tokenId);
        assertEq(posToken0, token0);

        IMigrator.MigrationParams memory migrationParams = generateDirectMigrationParams(token0, address(settler), 1);

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationId = migrationData.toId();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v3PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false, address(v3PositionManager));
        emit INonfungiblePositionManager.DecreaseLiquidity(tokenId, 0, 0, 0);

        // collect
        vm.expectEmit(true, false, false, false, address(v3PositionManager));
        emit INonfungiblePositionManager.Collect(tokenId, address(0), 0, 0);

        // Swap
        vm.expectEmit(true, true, false, false);
        emit IUniswapV3PoolEvents.Swap(address(universalRouter), address(migrator), 0, 0, 0, 0, 0);

        // Direct transfer to settler or user (dynamic check)
        // vm.expectEmit(true, true, true, true);
        // emit IERC20.Transfer(address(migrator), address(settler), 0);

        // No expectEmit for MigrationStarted; instead, check the event after the call
        vm.prank(user);
        v3PositionManager.safeTransferFrom(user, address(migrator), tokenId, abi.encode(migrationParams));

        // verify the transfer happened
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Find the transfer event from migrator to settler or user
        bool foundTransfer = false;
        uint256 transferredAmount = 0;
        address recipient;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics.length > 0 && entries[i].topics[0] == IERC20.Transfer.selector) {
                address from = address(uint160(uint256(entries[i].topics[1])));
                address to = address(uint160(uint256(entries[i].topics[2])));
                if (from == address(migrator) && (to == address(settler) || to == user)) {
                    transferredAmount = parseTransferEvent(entries[i].data);
                    recipient = to;
                    foundTransfer = true;
                    break;
                }
            }
        }
        assertTrue(foundTransfer, "Transfer from migrator to settler or user not found");
        assertGt(transferredAmount, 0);

        // Find the MigrationStarted event in the logs and check its parameters
        bool foundMigrationStarted = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics.length > 0 && entries[i].topics[0] == IMigrator.MigrationStarted.selector) {
                // Decode topics and data
                bytes32 emittedMigrationId = entries[i].topics[1];
                uint256 loggedPositionId = uint256(entries[i].topics[2]);
                uint256 loggedChainId = uint256(entries[i].topics[3]);
                (
                    address loggedSettler,
                    MigrationMode loggedMode,
                    address loggedSender,
                    address loggedToken,
                    uint256 loggedAmount
                ) = abi.decode(entries[i].data, (address, MigrationMode, address, address, uint256));
                assertTrue(emittedMigrationId != bytes32(0), "migrationId should not be zero");
                assertEq(loggedPositionId, tokenId, "positionId mismatch");
                assertEq(loggedChainId, sourceChainId, "chainId mismatch");
                assertEq(loggedSettler, address(settler), "settler mismatch");
                assertTrue(loggedMode == MigrationModes.SINGLE, "mode mismatch");
                assertEq(loggedSender, user, "sender mismatch");
                assertEq(loggedToken, token0, "token mismatch");
                // Amount is dynamic, but should be > 0
                assertGt(loggedAmount, 0);
                foundMigrationStarted = true;
                break;
            }
        }
        assertTrue(foundMigrationStarted, "MigrationStarted event not found");
    }

    function test_onERC721Received_Token0USDCBaseToken_NoWETH_AboveCurrentTick() public {
        vm.recordLogs();
        address token0 = usdc;
        address token1 = usdt;
        // current tick is ~ -201000
        (uint256 tokenId, uint256 amount0,) =
            mintV3Position(address(v3PositionManager), user, token0, token1, 100, 500, 100);

        // only token0 is used; no swap is needed

        // verify posToken0 is baseToken
        (,, address posToken0,,,,,,,,,) = v3PositionManager.positions(tokenId);
        assertEq(posToken0, token0);

        IMigrator.MigrationParams memory migrationParams =
            generateDirectMigrationParams(token0, address(settler), amount0 - 1);

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationId = migrationData.toId();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v3PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false, address(v3PositionManager));
        emit INonfungiblePositionManager.DecreaseLiquidity(tokenId, 0, 0, 0);

        // collect
        vm.expectEmit(true, false, false, false, address(v3PositionManager));
        emit INonfungiblePositionManager.Collect(tokenId, address(0), 0, 0);

        // Swap
        // not needed

        // Direct transfer to settler or user (dynamic check)
        // vm.expectEmit(true, true, true, true);
        // emit IERC20.Transfer(address(migrator), address(settler), 0);

        // No expectEmit for MigrationStarted; instead, check the event after the call
        vm.prank(user);
        v3PositionManager.safeTransferFrom(user, address(migrator), tokenId, abi.encode(migrationParams));

        // verify the transfer happened
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Find the transfer event from migrator to settler or user
        bool foundTransfer = false;
        uint256 transferredAmount = 0;
        address recipient;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics.length > 0 && entries[i].topics[0] == IERC20.Transfer.selector) {
                address from = address(uint160(uint256(entries[i].topics[1])));
                address to = address(uint160(uint256(entries[i].topics[2])));
                if (from == address(migrator) && (to == address(settler) || to == user)) {
                    transferredAmount = parseTransferEvent(entries[i].data);
                    recipient = to;
                    foundTransfer = true;
                    break;
                }
            }
        }
        assertTrue(foundTransfer, "Transfer from migrator to settler or user not found");
        assertGt(transferredAmount, 0);

        // Find the MigrationStarted event in the logs and check its parameters
        bool foundMigrationStarted = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics.length > 0 && entries[i].topics[0] == IMigrator.MigrationStarted.selector) {
                // Decode topics and data
                bytes32 emittedMigrationId = entries[i].topics[1];
                uint256 loggedPositionId = uint256(entries[i].topics[2]);
                uint256 loggedChainId = uint256(entries[i].topics[3]);
                (
                    address loggedSettler,
                    MigrationMode loggedMode,
                    address loggedSender,
                    address loggedToken,
                    uint256 loggedAmount
                ) = abi.decode(entries[i].data, (address, MigrationMode, address, address, uint256));
                assertTrue(emittedMigrationId != bytes32(0), "migrationId should not be zero");
                assertEq(loggedPositionId, tokenId, "positionId mismatch");
                assertEq(loggedChainId, sourceChainId, "chainId mismatch");
                assertEq(loggedSettler, address(settler), "settler mismatch");
                assertTrue(loggedMode == MigrationModes.SINGLE, "mode mismatch");
                assertEq(loggedSender, user, "sender mismatch");
                assertEq(loggedToken, token0, "token mismatch");
                // Amount is dynamic, but should be > 0
                assertGt(loggedAmount, 0);
                foundMigrationStarted = true;
                break;
            }
        }
        assertTrue(foundMigrationStarted, "MigrationStarted event not found");
    }

    /**
     * DUAL TOKEN PATHS ***
     */
    function test_onERC721Received_Token0WETHBaseToken_Token1USDCBaseToken_InRange() public {
        vm.recordLogs();
        address token0 = weth;
        address token1 = usdc;
        // current tick is ~ -201000
        (uint256 tokenId, uint256 amount0, uint256 amount1) =
            mintV3Position(address(v3PositionManager), user, token0, token1, -250000, -100000, 500);

        // verify posToken0 is baseToken
        (,, address posToken0, address posToken1,,,,,,,,) = v3PositionManager.positions(tokenId);
        assertEq(posToken0, token0);
        assertEq(posToken1, token1);

        IMigrator.MigrationParams memory migrationParams =
            generateDirectMigrationParams(token0, token1, token0, token1, amount0 - 1, amount1 - 1, address(settler));

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.DUAL,
            routesData: abi.encode(token0, token1, amount0 - 1, amount1 - 1),
            settlementData: ""
        });
        bytes32 migrationId = migrationData.toId();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v3PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false, address(v3PositionManager));
        emit INonfungiblePositionManager.DecreaseLiquidity(tokenId, 0, 0, 0);

        // collect
        vm.expectEmit(true, false, false, false, address(v3PositionManager));
        emit INonfungiblePositionManager.Collect(tokenId, address(0), 0, 0);

        // Swap
        // no swap as it's dual token path

        // Direct transfers to settler (two transfers for dual token)
        // vm.expectEmit(true, true, true, true);
        // emit IERC20.Transfer(address(migrator), address(settler), 0);
        // vm.expectEmit(true, true, true, true);
        // emit IERC20.Transfer(address(migrator), address(settler), 0);

        // No expectEmit for MigrationStarted; instead, check the event after the call
        vm.prank(user);
        v3PositionManager.safeTransferFrom(user, address(migrator), tokenId, abi.encode(migrationParams));

        // verify the transfers happened
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log[] memory transferEvents = findTransferEvents(entries, address(migrator), address(settler));

        assertEq(transferEvents.length, 2);

        uint256 transferredAmount0 = parseTransferEvent(transferEvents[0].data);
        uint256 transferredAmount1 = parseTransferEvent(transferEvents[1].data);

        assertGt(transferredAmount0, 0);
        assertGt(transferredAmount1, 0);

        // Find the MigrationStarted event in the logs and check its parameters
        bool foundMigrationStarted = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics.length > 0 && entries[i].topics[0] == IMigrator.MigrationStarted.selector) {
                // Decode topics and data
                bytes32 emittedMigrationId = entries[i].topics[1];
                uint256 loggedPositionId = uint256(entries[i].topics[2]);
                uint256 loggedChainId = uint256(entries[i].topics[3]);
                (
                    address loggedSettler,
                    MigrationMode loggedMode,
                    address loggedSender,
                    address loggedToken,
                    uint256 loggedAmount
                ) = abi.decode(entries[i].data, (address, MigrationMode, address, address, uint256));
                assertTrue(emittedMigrationId != bytes32(0), "migrationId should not be zero");
                assertEq(loggedPositionId, tokenId, "positionId mismatch");
                assertEq(loggedChainId, sourceChainId, "chainId mismatch");
                assertEq(loggedSettler, address(settler), "settler mismatch");
                assertTrue(loggedMode == MigrationModes.DUAL, "mode mismatch");
                assertEq(loggedSender, user, "sender mismatch");
                assertEq(loggedToken, token0, "token mismatch");
                // Amount is dynamic, but should be > 0
                assertGt(loggedAmount, 0);
                foundMigrationStarted = true;
                break;
            }
        }
        assertTrue(foundMigrationStarted, "MigrationStarted event not found");
    }

    /**
     * ERROR CASES ***
     */
    function test_onERC721Received_fails_ifCrossChainMigration() public {
        address token0 = weth;
        address token1 = usdc;
        (uint256 tokenId, uint256 amount0,) =
            mintV3Position(address(v3PositionManager), user, token0, token1, -250000, -100000, 500);

        // Try to migrate to a different chain
        IMigrator.MigrationParams memory migrationParams =
            generateDirectMigrationParams(token0, address(settler), amount0 - 1);
        migrationParams.chainId = sourceChainId + 1; // Different chain

        vm.expectRevert(abi.encodeWithSelector(IDirectMigrator.CrossChainNotSupported.selector));
        vm.prank(user);
        v3PositionManager.safeTransferFrom(user, address(migrator), tokenId, abi.encode(migrationParams));
    }

    function test_onERC721Received_fails_ifInvalidSettler() public {
        address token0 = weth;
        address token1 = usdc;
        (uint256 tokenId, uint256 amount0,) =
            mintV3Position(address(v3PositionManager), user, token0, token1, -250000, -100000, 500);

        // Try to migrate to an invalid settler
        IMigrator.MigrationParams memory migrationParams =
            generateDirectMigrationParams(token0, address(0), amount0 - 1);

        vm.expectRevert();
        vm.prank(user);
        v3PositionManager.safeTransferFrom(user, address(migrator), tokenId, abi.encode(migrationParams));
    }

    // Helper functions
    function findTransferEvent(Vm.Log[] memory entries, address from, address to)
        internal
        pure
        returns (Vm.Log memory)
    {
        for (uint256 i = 0; i < entries.length; i++) {
            if (
                entries[i].topics[0] == IERC20.Transfer.selector
                    && entries[i].topics[1] == bytes32(uint256(uint160(from)))
                    && entries[i].topics[2] == bytes32(uint256(uint160(to)))
            ) {
                return entries[i];
            }
        }
        revert("Transfer event not found");
    }

    function findTransferEvents(Vm.Log[] memory entries, address from, address to)
        internal
        pure
        returns (Vm.Log[] memory)
    {
        Vm.Log[] memory events = new Vm.Log[](10); // Max 10 events
        uint256 count = 0;

        for (uint256 i = 0; i < entries.length; i++) {
            if (
                entries[i].topics[0] == IERC20.Transfer.selector
                    && entries[i].topics[1] == bytes32(uint256(uint160(from)))
                    && entries[i].topics[2] == bytes32(uint256(uint160(to)))
            ) {
                events[count] = entries[i];
                count++;
                if (count >= 10) break;
            }
        }

        // Resize array to actual count
        Vm.Log[] memory result = new Vm.Log[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = events[i];
        }
        return result;
    }

    function parseTransferEvent(bytes memory data) internal pure returns (uint256) {
        return abi.decode(data, (uint256));
    }

    function test() public override(TestContext, UniswapV3Helpers) {}
}
