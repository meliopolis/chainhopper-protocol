// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {TestContext} from "./utils/TestContext.sol";
import {Vm} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IMigrator} from "../src/interfaces/IMigrator.sol";
import {ISettler} from "../src/interfaces/ISettler.sol";
import {IUniswapV4Settler} from "../src/interfaces/IUniswapV4Settler.sol";
import {UniswapV4DirectMigrator} from "../src/UniswapV4DirectMigrator.sol";
import {PoolId, PoolIdLibrary} from "@uniswap-v4-core/types/PoolId.sol";
import {Currency} from "@uniswap-v4-core/types/Currency.sol";
import {PoolKey} from "@uniswap-v4-core/types/PoolKey.sol";
import {UniswapV4Helpers} from "./utils/UniswapV4Helpers.sol";
import {MigrationData} from "../src/types/MigrationData.sol";
import {MigrationModes, MigrationMode} from "../src/types/MigrationMode.sol";
import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {MigrationHelpers} from "./utils/MigrationHelpers.sol";
import {IHooks} from "@uniswap-v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap-v4-core/interfaces/IPoolManager.sol";
import {TickMath} from "@uniswap-v4-core/libraries/TickMath.sol";
import {MockUniswapVXDirectSettler} from "./mocks/MockUniswapVXDirectSettler.sol";

contract UniswapV4DirectMigratorTest is TestContext, UniswapV4Helpers {
    string public constant SRC_CHAIN_NAME = "BASE";
    string public constant DEST_CHAIN_NAME = "";
    MockUniswapVXDirectSettler public settler;
    uint256 public maxFees = 10_000_000;
    UniswapV4DirectMigrator public migrator;
    uint256 public sourceChainId = 8453;

    function setUp() public {
        _loadChain(SRC_CHAIN_NAME, DEST_CHAIN_NAME);

        vm.prank(owner);
        settler = new MockUniswapVXDirectSettler(owner);

        vm.prank(owner);
        migrator = new UniswapV4DirectMigrator(
            owner, address(v4PositionManager), address(universalRouter), address(permit2), weth
        );
        // Configure the settler
        vm.startPrank(owner);
        settler.setProtocolFeeRecipient(owner);
        settler.setProtocolShareBps(100);
        settler.setProtocolShareOfSenderFeePct(10);
        vm.stopPrank();

        // update chainSettler
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
        - eth/usdc (token0: eth/default basetoken, token1: usdc/second basetoken for dual token paths)
        - weth/usdc (token0: weth/default basetoken, token1: usdc/second basetoken for dual token paths)
        - erc20/weth (token0: erc20 and token1: weth/basetoken)
        - usdc/usdt (non-weth token pair with usdc as base token)

        Ranges to include in tests:
        - below tickLower
        - between tickLower and tickUpper
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
    function test_onERC721Received_NativeToken_InRange() public {
        address token0 = address(0); // Native ETH for direct matching
        address token1 = usdc;
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(0)), // native pool
            currency1: Currency.wrap(token1),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });
        PoolId poolId = PoolIdLibrary.toId(poolKey);
        // current tick is ~ -201000
        uint256 tokenId = mintV4Position(address(v4PositionManager), address(permit2), user, poolKey, -250000, -100000);
        (uint256 amount0, uint256 amount1) =
            getPositionAmounts(address(v4PositionManager), address(v4StateView), tokenId);

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

        vm.recordLogs();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v4PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // collect
        // Events are emitted but exact params may vary

        // swap event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Swap(poolId, address(universalRouter), 0, 0, 0, 0, 0, 0);

        // Direct transfer to settler
        // vm.expectEmit(true, true, true, true);
        // emit IERC20.Transfer(address(migrator), address(settler), 0);

        // No expectEmit for MigrationStarted; instead, check the event after the call
        vm.prank(user);
        IERC721(address(v4PositionManager)).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(migrationParams)
        );

        // verify the transfer happened
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log[] memory swapEvents = findSwapEvents(entries);
        uint256 swapOutAmount = 0;
        if (swapEvents.length > 0) {
            (, swapOutAmount) = parseSwapEventForBothAmounts(swapEvents[0].data);
        }
        // Find the transfer event from migrator to settler
        bool foundTransfer = false;
        uint256 transferredAmount = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            // Check for ERC20 Transfer event
            if (entries[i].topics[0] == keccak256("Transfer(address,address,uint256)")) {
                address from = address(uint160(uint256(entries[i].topics[1])));
                address to = address(uint160(uint256(entries[i].topics[2])));
                if (from == address(migrator) && to == address(settler)) {
                    transferredAmount = abi.decode(entries[i].data, (uint256));
                    foundTransfer = true;
                    break;
                }
            }
        }
        assertTrue(foundTransfer, "Direct transfer to settler not found");
        assertGt(transferredAmount, 0, "Transfer amount should be greater than 0");
    }

    function test_onERC721Received_NativeToken_BelowCurrentTick() public {
        address token0 = address(0); // Native ETH for direct matching
        address token1 = usdc;
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(0)), // native pool
            currency1: Currency.wrap(token1),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });
        PoolId poolId = PoolIdLibrary.toId(poolKey);
        // current tick is ~ -201000
        uint256 tokenId = mintV4Position(address(v4PositionManager), address(permit2), user, poolKey, -250000, -210000);
        (uint256 amount0, uint256 amount1) =
            getPositionAmounts(address(v4PositionManager), address(v4StateView), tokenId);
        // only token1 is used
        assertEq(amount0, 0);

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
        bytes memory data = abi.encode(migrationId, migrationData);

        vm.recordLogs();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v4PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // collect events - exact params may vary

        // swap event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Swap(poolId, address(universalRouter), 0, 0, 0, 0, 0, 0);

        // No bridge events for DirectTransfer

        // No expectEmit for MigrationStarted; check after call
        vm.prank(user);
        IERC721(address(v4PositionManager)).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(migrationParams)
        );

        // verify the transfer happened
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log[] memory swapEvents = findSwapEvents(entries);
        uint256 swapOutAmount = 0;
        if (swapEvents.length > 0) {
            (, swapOutAmount) = parseSwapEventForBothAmounts(swapEvents[0].data);
        }
        // Find the transfer event from migrator to settler
        bool foundTransfer = false;
        uint256 transferredAmount = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            // Check for ERC20 Transfer event
            if (entries[i].topics[0] == keccak256("Transfer(address,address,uint256)")) {
                address from = address(uint160(uint256(entries[i].topics[1])));
                address to = address(uint160(uint256(entries[i].topics[2])));
                if (from == address(migrator) && to == address(settler)) {
                    transferredAmount = abi.decode(entries[i].data, (uint256));
                    foundTransfer = true;
                    break;
                }
            }
        }
        assertTrue(foundTransfer, "Direct transfer to settler not found");
        assertGt(transferredAmount, 0, "Transfer amount should be greater than 0");
    }

    function test_onERC721Received_NativeToken_AboveCurrentTick() public {
        address token0 = address(0); // Native ETH for direct matching
        address token1 = usdc;
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(0)), // native pool
            currency1: Currency.wrap(token1),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });
        PoolId poolId = PoolIdLibrary.toId(poolKey);
        // current tick is ~ -201000
        uint256 tokenId = mintV4Position(address(v4PositionManager), address(permit2), user, poolKey, -150000, -100000);
        (uint256 amount0, uint256 amount1) =
            getPositionAmounts(address(v4PositionManager), address(v4StateView), tokenId);
        // only token0 is used
        assertEq(amount1, 0);

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
        bytes memory data = abi.encode(migrationId, migrationData);

        vm.recordLogs();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v4PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // collect
        // only native token collected, which won't be emitted

        // swap event
        // no swap needed

        // No bridge events for DirectTransfer

        // No expectEmit for MigrationStarted; check after call
        vm.prank(user);
        IERC721(address(v4PositionManager)).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(migrationParams)
        );

        // verify the transfer happened (no swap)
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // Find the transfer event from migrator to settler
        bool foundTransfer = false;
        uint256 transferredAmount = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            // Check for ERC20 Transfer event
            if (entries[i].topics[0] == keccak256("Transfer(address,address,uint256)")) {
                address from = address(uint160(uint256(entries[i].topics[1])));
                address to = address(uint160(uint256(entries[i].topics[2])));
                if (from == address(migrator) && to == address(settler)) {
                    transferredAmount = abi.decode(entries[i].data, (uint256));
                    foundTransfer = true;
                    break;
                }
            }
        }
        assertTrue(foundTransfer, "Direct transfer to settler not found");
        assertGt(transferredAmount, 0, "Transfer amount should be greater than 0");
    }

    function test_onERC721Received_Token0WETHBaseToken_InRange() public {
        address token0 = weth;
        address token1 = usdc;
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });
        PoolId poolId = PoolIdLibrary.toId(poolKey);
        // mint a large position first to populate the pool
        UniswapV4Helpers.mintBigV4PositionToPopulatePool(
            address(v4PositionManager), address(permit2), user, poolKey, -600000, 100000, 1_000_000_000_000_000
        );
        // current tick is ~ -201000
        uint256 tokenId = mintV4Position(address(v4PositionManager), address(permit2), user, poolKey, -250000, -100000);
        (uint256 amount0, uint256 amount1) =
            getPositionAmounts(address(v4PositionManager), address(v4StateView), tokenId);

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
        bytes memory data = abi.encode(migrationId, migrationData);

        vm.recordLogs();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v4PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // collect events - exact params may vary

        // swap event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Swap(poolId, address(universalRouter), 0, 0, 0, 0, 0, 0);

        // No bridge events for DirectTransfer

        // No expectEmit for MigrationStarted; check after call
        vm.prank(user);
        IERC721(address(v4PositionManager)).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(migrationParams)
        );

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log[] memory swapEvents = findSwapEvents(entries);
        (, uint256 amountOut) = parseSwapEventForBothAmounts(swapEvents[0].data);

        // Find the transfer event from migrator to settler
        bool foundTransfer = false;
        uint256 transferredAmount = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            // Check for ERC20 Transfer event
            if (entries[i].topics[0] == keccak256("Transfer(address,address,uint256)")) {
                address from = address(uint160(uint256(entries[i].topics[1])));
                address to = address(uint160(uint256(entries[i].topics[2])));
                if (from == address(migrator) && to == address(settler)) {
                    transferredAmount = abi.decode(entries[i].data, (uint256));
                    foundTransfer = true;
                    break;
                }
            }
        }
        assertTrue(foundTransfer, "Direct transfer to settler not found");
        assertGt(transferredAmount, 0, "Transfer amount should be greater than 0");
    }

    function test_onERC721Received_Token0WETHBaseToken_BelowCurrentTick() public {
        address token0 = weth;
        address token1 = usdc;
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });
        PoolId poolId = PoolIdLibrary.toId(poolKey);
        // mint a large position first to populate the pool
        UniswapV4Helpers.mintBigV4PositionToPopulatePool(
            address(v4PositionManager), address(permit2), user, poolKey, -600000, 100000, 1_000_000_000_000_000
        );
        // current tick is ~ -201000
        uint256 tokenId = mintV4Position(address(v4PositionManager), address(permit2), user, poolKey, -250000, -210000);
        (uint256 amount0, uint256 amount1) =
            getPositionAmounts(address(v4PositionManager), address(v4StateView), tokenId);
        // only token1 is used
        assertEq(amount0, 0);

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
        bytes memory data = abi.encode(migrationId, migrationData);

        vm.recordLogs();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v4PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // collect events - exact params may vary

        // swap event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Swap(poolId, address(universalRouter), 0, 0, 0, 0, 0, 0);

        // No bridge events for DirectTransfer

        // No expectEmit for MigrationStarted; check after call
        vm.prank(user);
        IERC721(address(v4PositionManager)).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(migrationParams)
        );

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log[] memory swapEvents = findSwapEvents(entries);
        (, uint256 amountOut) = parseSwapEventForBothAmounts(swapEvents[0].data);

        // Find the transfer event from migrator to settler
        bool foundTransfer = false;
        uint256 transferredAmount = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            // Check for ERC20 Transfer event
            if (entries[i].topics[0] == keccak256("Transfer(address,address,uint256)")) {
                address from = address(uint160(uint256(entries[i].topics[1])));
                address to = address(uint160(uint256(entries[i].topics[2])));
                if (from == address(migrator) && to == address(settler)) {
                    transferredAmount = abi.decode(entries[i].data, (uint256));
                    foundTransfer = true;
                    break;
                }
            }
        }
        assertTrue(foundTransfer, "Direct transfer to settler not found");
        assertGt(transferredAmount, 0, "Transfer amount should be greater than 0");
    }

    function test_onERC721Received_Token0WETHBaseToken_AboveCurrentTick() public {
        address token0 = weth;
        address token1 = usdc;
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });
        PoolId poolId = PoolIdLibrary.toId(poolKey);
        // mint a large position first to populate the pool
        UniswapV4Helpers.mintBigV4PositionToPopulatePool(
            address(v4PositionManager), address(permit2), user, poolKey, -600000, 100000, 1_000_000_000_000_000
        );
        // current tick is ~ -201000
        uint256 tokenId = mintV4Position(address(v4PositionManager), address(permit2), user, poolKey, -150000, -100000);
        (uint256 amount0, uint256 amount1) =
            getPositionAmounts(address(v4PositionManager), address(v4StateView), tokenId);
        // only token0 is used
        assertEq(amount1, 0);

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
        bytes memory data = abi.encode(migrationId, migrationData);

        vm.recordLogs();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v4PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // collect events - exact params may vary

        // swap event
        // no swap needed

        // No bridge events for DirectTransfer

        // No expectEmit for MigrationStarted; check after call
        vm.prank(user);
        IERC721(address(v4PositionManager)).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(migrationParams)
        );

        // verify the transfer happened (no swap)
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Find the transfer event from migrator to settler
        bool foundTransfer = false;
        uint256 transferredAmount = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            // Check for ERC20 Transfer event
            if (entries[i].topics[0] == keccak256("Transfer(address,address,uint256)")) {
                address from = address(uint160(uint256(entries[i].topics[1])));
                address to = address(uint160(uint256(entries[i].topics[2])));
                if (from == address(migrator) && to == address(settler)) {
                    transferredAmount = abi.decode(entries[i].data, (uint256));
                    foundTransfer = true;
                    break;
                }
            }
        }
        assertTrue(foundTransfer, "Direct transfer to settler not found");
        assertGt(transferredAmount, 0, "Transfer amount should be greater than 0");
    }

    function test_onERC721Received_Token1WETHBaseToken_InRange() public {
        address token0 = virtualToken;
        address token1 = weth;
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 3000,
            tickSpacing: 100,
            hooks: IHooks(address(0))
        });
        PoolId poolId = PoolIdLibrary.toId(poolKey);
        v4PositionManager.initializePool(poolKey, TickMath.getSqrtPriceAtTick(7));
        // mint a large position first to populate the pool
        UniswapV4Helpers.mintBigV4PositionToPopulatePool(
            address(v4PositionManager), address(permit2), user, poolKey, -50000, 50000, 1_000_000_000_000_000
        );
        uint256 tokenId = mintV4Position(address(v4PositionManager), address(permit2), user, poolKey, -25000, 25000);
        (uint256 amount0, uint256 amount1) =
            getPositionAmounts(address(v4PositionManager), address(v4StateView), tokenId);
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
        bytes memory data = abi.encode(migrationId, migrationData);

        vm.recordLogs();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v4PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // collect events - exact params may vary

        // swap event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Swap(poolId, address(universalRouter), 0, 0, 0, 0, 0, 0);

        // No bridge events for DirectTransfer

        // No expectEmit for MigrationStarted; check after call
        vm.prank(user);
        IERC721(address(v4PositionManager)).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(migrationParams)
        );

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log[] memory swapEvents = findSwapEvents(entries);
        (, uint256 amountOut) = parseSwapEventForBothAmounts(swapEvents[0].data);

        // Find the transfer event from migrator to settler
        bool foundTransfer = false;
        uint256 transferredAmount = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            // Check for ERC20 Transfer event
            if (entries[i].topics[0] == keccak256("Transfer(address,address,uint256)")) {
                address from = address(uint160(uint256(entries[i].topics[1])));
                address to = address(uint160(uint256(entries[i].topics[2])));
                if (from == address(migrator) && to == address(settler)) {
                    transferredAmount = abi.decode(entries[i].data, (uint256));
                    foundTransfer = true;
                    break;
                }
            }
        }
        assertTrue(foundTransfer, "Direct transfer to settler not found");
        assertGt(transferredAmount, 0, "Transfer amount should be greater than 0");
    }

    function test_onERC721Received_Token1WETHBaseToken_BelowCurrentTick() public {
        address token0 = virtualToken;
        address token1 = weth;
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 3000,
            tickSpacing: 100,
            hooks: IHooks(address(0))
        });
        PoolId poolId = PoolIdLibrary.toId(poolKey);
        v4PositionManager.initializePool(poolKey, TickMath.getSqrtPriceAtTick(7));
        // mint a large position first to populate the pool
        UniswapV4Helpers.mintBigV4PositionToPopulatePool(
            address(v4PositionManager), address(permit2), user, poolKey, -50000, 50000, 1_000_000_000_000_000
        );
        uint256 tokenId = mintV4Position(address(v4PositionManager), address(permit2), user, poolKey, -5000, -1000);
        (uint256 amount0, uint256 amount1) =
            getPositionAmounts(address(v4PositionManager), address(v4StateView), tokenId);
        // only token1 is used
        assertEq(amount0, 0);
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
        bytes memory data = abi.encode(migrationId, migrationData);

        vm.recordLogs();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v4PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // collect events - exact params may vary

        // swap event
        // no swap needed

        // No bridge events for DirectTransfer

        // No expectEmit for MigrationStarted; check after call
        vm.prank(user);
        IERC721(address(v4PositionManager)).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(migrationParams)
        );

        // verify the transfer happened (no swap)
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Find the transfer event from migrator to settler
        bool foundTransfer = false;
        uint256 transferredAmount = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            // Check for ERC20 Transfer event
            if (entries[i].topics[0] == keccak256("Transfer(address,address,uint256)")) {
                address from = address(uint160(uint256(entries[i].topics[1])));
                address to = address(uint160(uint256(entries[i].topics[2])));
                if (from == address(migrator) && to == address(settler)) {
                    transferredAmount = abi.decode(entries[i].data, (uint256));
                    foundTransfer = true;
                    break;
                }
            }
        }
        assertTrue(foundTransfer, "Direct transfer to settler not found");
        assertGt(transferredAmount, 0, "Transfer amount should be greater than 0");
    }

    function test_onERC721Received_Token1WETHBaseToken_AboveCurrentTick() public {
        address token0 = virtualToken;
        address token1 = weth;
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 3000,
            tickSpacing: 100,
            hooks: IHooks(address(0))
        });
        PoolId poolId = PoolIdLibrary.toId(poolKey);
        v4PositionManager.initializePool(poolKey, TickMath.getSqrtPriceAtTick(7));
        // mint a large position first to populate the pool
        UniswapV4Helpers.mintBigV4PositionToPopulatePool(
            address(v4PositionManager), address(permit2), user, poolKey, -50000, 50000, 1_000_000_000_000_000
        );
        uint256 tokenId = mintV4Position(address(v4PositionManager), address(permit2), user, poolKey, 1000, 5000);
        (uint256 amount0, uint256 amount1) =
            getPositionAmounts(address(v4PositionManager), address(v4StateView), tokenId);
        // only token0 is used
        assertEq(amount1, 0);
        IMigrator.MigrationParams memory migrationParams = generateDirectMigrationParams(token1, address(settler), 1);

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationId = migrationData.toId();
        bytes memory data = abi.encode(migrationId, migrationData);

        vm.recordLogs();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v4PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // collect events - exact params may vary

        // swap event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Swap(poolId, address(universalRouter), 0, 0, 0, 0, 0, 0);

        // No bridge events for DirectTransfer

        // No expectEmit for MigrationStarted; check after call
        vm.prank(user);
        IERC721(address(v4PositionManager)).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(migrationParams)
        );

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log[] memory swapEvents = findSwapEvents(entries);
        (, uint256 amountOut) = parseSwapEventForBothAmounts(swapEvents[0].data);

        // Find the transfer event from migrator to settler
        bool foundTransfer = false;
        uint256 transferredAmount = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            // Check for ERC20 Transfer event
            if (entries[i].topics[0] == keccak256("Transfer(address,address,uint256)")) {
                address from = address(uint160(uint256(entries[i].topics[1])));
                address to = address(uint160(uint256(entries[i].topics[2])));
                if (from == address(migrator) && to == address(settler)) {
                    transferredAmount = abi.decode(entries[i].data, (uint256));
                    foundTransfer = true;
                    break;
                }
            }
        }
        assertTrue(foundTransfer, "Direct transfer to settler not found");
        assertGt(transferredAmount, 0, "Transfer amount should be greater than 0");
    }

    function test_onERC721Received_Token0USDCBaseToken_NoWETH_InRange() public {
        address token0 = usdc;
        address token1 = usdt;
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });
        PoolId poolId = PoolIdLibrary.toId(poolKey);
        // mint a large position first to populate the pool
        UniswapV4Helpers.mintBigV4PositionToPopulatePool(
            address(v4PositionManager), address(permit2), user, poolKey, -100000, 100000, 1_000_000_000_000_000_000
        );
        uint256 tokenId = mintV4Position(address(v4PositionManager), address(permit2), user, poolKey, -10000, 10000);
        (uint256 amount0, uint256 amount1) =
            getPositionAmounts(address(v4PositionManager), address(v4StateView), tokenId);

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
        bytes memory data = abi.encode(migrationId, migrationData);

        vm.recordLogs();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v4PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // collect events - exact params may vary

        // swap event - test if this works
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Swap(poolId, address(universalRouter), 0, 0, 0, 0, 0, 0);

        // No bridge events for DirectTransfer

        // No expectEmit for MigrationStarted; check after call
        vm.prank(user);
        IERC721(address(v4PositionManager)).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(migrationParams)
        );

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log[] memory swapEvents = findSwapEvents(entries);
        (, uint256 amountOut) = parseSwapEventForBothAmounts(swapEvents[0].data);

        // Find the transfer event from migrator to settler
        bool foundTransfer = false;
        uint256 transferredAmount = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            // Check for ERC20 Transfer event
            if (entries[i].topics[0] == keccak256("Transfer(address,address,uint256)")) {
                address from = address(uint160(uint256(entries[i].topics[1])));
                address to = address(uint160(uint256(entries[i].topics[2])));
                if (from == address(migrator) && to == address(settler)) {
                    transferredAmount = abi.decode(entries[i].data, (uint256));
                    foundTransfer = true;
                    break;
                }
            }
        }
        assertTrue(foundTransfer, "Direct transfer to settler not found");
        assertGt(transferredAmount, 0, "Transfer amount should be greater than 0");
    }

    function test_onERC721Received_Token0USDCBaseToken_NoWETH_BelowCurrentTick() public {
        address token0 = usdc;
        address token1 = usdt;
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });
        PoolId poolId = PoolIdLibrary.toId(poolKey);
        // mint a large position first to populate the pool
        UniswapV4Helpers.mintBigV4PositionToPopulatePool(
            address(v4PositionManager), address(permit2), user, poolKey, -100000, 100000, 1_000_000_000_000_000_000
        );
        uint256 tokenId = mintV4Position(address(v4PositionManager), address(permit2), user, poolKey, -10000, -1000);
        (uint256 amount0, uint256 amount1) =
            getPositionAmounts(address(v4PositionManager), address(v4StateView), tokenId);
        // only token1 is used
        assertEq(amount0, 0);

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
        bytes memory data = abi.encode(migrationId, migrationData);

        vm.recordLogs();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v4PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // collect events - exact params may vary

        // swap event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Swap(poolId, address(universalRouter), 0, 0, 0, 0, 0, 0);

        // No bridge events for DirectTransfer

        // No expectEmit for MigrationStarted; check after call
        vm.prank(user);
        IERC721(address(v4PositionManager)).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(migrationParams)
        );

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log[] memory swapEvents = findSwapEvents(entries);
        (, uint256 amountOut) = parseSwapEventForBothAmounts(swapEvents[0].data);

        // Find the transfer event from migrator to settler
        bool foundTransfer = false;
        uint256 transferredAmount = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            // Check for ERC20 Transfer event
            if (entries[i].topics[0] == keccak256("Transfer(address,address,uint256)")) {
                address from = address(uint160(uint256(entries[i].topics[1])));
                address to = address(uint160(uint256(entries[i].topics[2])));
                if (from == address(migrator) && to == address(settler)) {
                    transferredAmount = abi.decode(entries[i].data, (uint256));
                    foundTransfer = true;
                    break;
                }
            }
        }
        assertTrue(foundTransfer, "Direct transfer to settler not found");
        assertGt(transferredAmount, 0, "Transfer amount should be greater than 0");
    }

    function test_onERC721Received_Token0USDCBaseToken_NoWETH_AboveCurrentTick() public {
        address token0 = usdc;
        address token1 = usdt;
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });
        PoolId poolId = PoolIdLibrary.toId(poolKey);
        // mint a large position first to populate the pool
        UniswapV4Helpers.mintBigV4PositionToPopulatePool(
            address(v4PositionManager), address(permit2), user, poolKey, -100000, 100000, 1_000_000_000_000_000_000
        );
        uint256 tokenId = mintV4Position(address(v4PositionManager), address(permit2), user, poolKey, 1000, 10000);
        (uint256 amount0, uint256 amount1) =
            getPositionAmounts(address(v4PositionManager), address(v4StateView), tokenId);

        // only token0 is used
        assertEq(amount1, 0);

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
        bytes memory data = abi.encode(migrationId, migrationData);

        vm.recordLogs();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v4PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // collect events - exact params may vary

        // swap event
        // no swap needed

        // No bridge events for DirectTransfer

        // No expectEmit for MigrationStarted; check after call
        vm.prank(user);
        IERC721(address(v4PositionManager)).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(migrationParams)
        );

        // verify the transfer happened (no swap)
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Find the transfer event from migrator to settler
        bool foundTransfer = false;
        uint256 transferredAmount = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            // Check for ERC20 Transfer event
            if (entries[i].topics[0] == keccak256("Transfer(address,address,uint256)")) {
                address from = address(uint160(uint256(entries[i].topics[1])));
                address to = address(uint160(uint256(entries[i].topics[2])));
                if (from == address(migrator) && to == address(settler)) {
                    transferredAmount = abi.decode(entries[i].data, (uint256));
                    foundTransfer = true;
                    break;
                }
            }
        }
        assertTrue(foundTransfer, "Direct transfer to settler not found");
        assertGt(transferredAmount, 0, "Transfer amount should be greater than 0");
    }

    /**
     * DUAL TOKEN PATHS ***
     */
    function test_onERC721Received_NativeTokenandERC20BaseTokens_InRange() public {
        address token0 = address(0); // Native ETH for direct matching
        address token1 = usdc;
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(0)), // native pool
            currency1: Currency.wrap(token1),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });
        PoolId poolId = PoolIdLibrary.toId(poolKey);
        // current tick is ~ -201000
        uint256 tokenId = mintV4Position(address(v4PositionManager), address(permit2), user, poolKey, -250000, -100000);
        (uint256 amount0, uint256 amount1) =
            getPositionAmounts(address(v4PositionManager), address(v4StateView), tokenId);

        IMigrator.MigrationParams memory migrationParams =
            generateDirectMigrationParams(token0, token1, token0, usdc, amount0 - 1, amount1 - 1, address(settler));

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.DUAL,
            routesData: abi.encode(token0, usdc, amount0 - 1, amount1 - 1),
            settlementData: ""
        });
        bytes32 migrationId = migrationData.toId();
        bytes memory data = abi.encode(migrationId, migrationData);

        vm.recordLogs();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v4PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // collect events - exact params may vary

        // swap event
        // no swap needed
        // No bridge events for DirectTransfer

        /* vm.expectEmit(true, false, false, false);
        /* emit V3SpokePoolInterface.FundsDeposited(
            bytes32(uint256(uint160(token1))),
            bytes32(uint256(uint160(usdc))),
            0,
            0,
            sourceChainId,
            1,
            uint32(block.timestamp),
            uint32(block.timestamp + 3000),
            0,
            bytes32(bytes20(user)),
            bytes32(bytes20(user)),
            bytes32(0),
            ""
        ); */

        // No expectEmit for MigrationStarted events in direct migration
        vm.prank(user);
        IERC721(address(v4PositionManager)).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(migrationParams)
        );

        // verify the transfers happened
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // Find the transfer events from migrator to settler
        uint256 transferCount = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            // Check for ERC20 Transfer event
            if (entries[i].topics[0] == keccak256("Transfer(address,address,uint256)")) {
                address from = address(uint160(uint256(entries[i].topics[1])));
                address to = address(uint160(uint256(entries[i].topics[2])));
                if (from == address(migrator) && to == address(settler)) {
                    uint256 transferredAmount = abi.decode(entries[i].data, (uint256));
                    assertGt(transferredAmount, 0, "Transfer amount should be greater than 0");
                    transferCount++;
                }
            }
        }
        assertEq(transferCount, 2, "Should have 2 direct transfers to settler for dual token migration");
    }

    function test_onERC721Received_BothTokensERC20andBaseTokens_InRange() public {
        address token0 = weth;
        address token1 = usdc;
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });
        PoolId poolId = PoolIdLibrary.toId(poolKey);
        // mint a large position first to populate the pool
        UniswapV4Helpers.mintBigV4PositionToPopulatePool(
            address(v4PositionManager), address(permit2), user, poolKey, -600000, 100000, 1_000_000_000_000_000
        );
        // current tick is ~ -201000
        uint256 tokenId = mintV4Position(address(v4PositionManager), address(permit2), user, poolKey, -250000, -100000);
        (uint256 amount0, uint256 amount1) =
            getPositionAmounts(address(v4PositionManager), address(v4StateView), tokenId);

        IMigrator.MigrationParams memory migrationParams =
            generateDirectMigrationParams(token0, token1, token0, usdc, amount0 - 1, amount1 - 1, address(settler));

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.DUAL,
            routesData: abi.encode(token0, usdc, amount0 - 1, amount1 - 1),
            settlementData: ""
        });
        bytes32 migrationId = migrationData.toId();
        bytes memory data = abi.encode(migrationId, migrationData);

        vm.recordLogs();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v4PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // collect events - exact params may vary

        // swap event
        // no swap needed

        // No bridge events for DirectTransfer

        /* vm.expectEmit(true, false, false, false);
        /* emit V3SpokePoolInterface.FundsDeposited(
            bytes32(uint256(uint160(token1))),
            bytes32(uint256(uint160(usdc))),
            0,
            0,
            sourceChainId,
            1,
            uint32(block.timestamp),
            uint32(block.timestamp + 3000),
            0,
            bytes32(bytes20(user)),
            bytes32(bytes20(user)),
            bytes32(0),
            ""
        ); */

        // No expectEmit for MigrationStarted events in direct migration
        vm.prank(user);
        IERC721(address(v4PositionManager)).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(migrationParams)
        );

        // verify the transfers happened
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // Find the transfer events from migrator to settler
        uint256 transferCount = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            // Check for ERC20 Transfer event
            if (entries[i].topics[0] == keccak256("Transfer(address,address,uint256)")) {
                address from = address(uint160(uint256(entries[i].topics[1])));
                address to = address(uint160(uint256(entries[i].topics[2])));
                if (from == address(migrator) && to == address(settler)) {
                    uint256 transferredAmount = abi.decode(entries[i].data, (uint256));
                    assertGt(transferredAmount, 0, "Transfer amount should be greater than 0");
                    transferCount++;
                }
            }
        }
        assertEq(transferCount, 2, "Should have 2 direct transfers to settler for dual token migration");
    }

    function test() public override(TestContext, UniswapV4Helpers) {}
}
