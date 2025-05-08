// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {TestContext} from "./utils/TestContext.sol";
import {Vm} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IMigrator} from "../src/interfaces/IMigrator.sol";
import {IAcrossMigrator} from "../src/interfaces/IAcrossMigrator.sol";
import {ISettler} from "../src/interfaces/ISettler.sol";
import {IUniswapV4Settler} from "../src/interfaces/IUniswapV4Settler.sol";
import {UniswapV4AcrossMigrator} from "../src/UniswapV4AcrossMigrator.sol";
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
import {V3SpokePoolInterface} from "@across/interfaces/V3SpokePoolInterface.sol";
import {AcrossHelpers} from "./utils/AcrossHelpers.sol";
import {TickMath} from "@uniswap-v4-core/libraries/TickMath.sol";

contract UniswapV4AcrossMigratorTest is TestContext, UniswapV4Helpers {
    string public constant SRC_CHAIN_NAME = "BASE";
    string public constant DEST_CHAIN_NAME = "UNICHAIN";
    address public settler = address(123);
    uint256 public maxFees = 10_000_000;
    UniswapV4AcrossMigrator public migrator;
    uint256 public sourceChainId = 8453;
    uint256 public destinationChainId = 130;

    function setUp() public {
        _loadChain(SRC_CHAIN_NAME, DEST_CHAIN_NAME);

        vm.prank(owner);
        migrator = new UniswapV4AcrossMigrator(
            owner,
            address(v4PositionManager),
            address(universalRouter),
            address(permit2),
            address(acrossSpokePool),
            weth
        );
        // update chainSettler
        vm.prank(owner);
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = destinationChainId;
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

    /**
     * SINGLE TOKEN PATHS ***
     */
    function test_onERC721Received_NativeToken_InRange() public {
        address token0 = weth; // this is still left as weth for later in the test
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
            MigrationHelpers.generateMigrationParams(token0, address(settler), amount0 - maxFees);

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationHash = migrationData.toHash();
        bytes memory data = abi.encode(migrationHash, migrationData);

        vm.recordLogs();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v4PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // collect
        // vm.expectEmit(true, true, false, true, address(token0));
        // emit IERC20.Transfer(address(v4PoolManager), address(migrator), amount0 - 1); // rounding error
        vm.expectEmit(true, true, false, true, address(usdc));
        emit IERC20.Transfer(address(v4PoolManager), address(migrator), amount1 - 1); // rounding error

        // swap event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Swap(poolId, address(universalRouter), 0, 0, 0, 0, 0, 0);

        // bridge
        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.FundsDeposited(
            bytes32(uint256(uint160(token0))), // still needs to be weth
            bytes32(uint256(uint160(token0))), // still needs to be weth
            0,
            0,
            destinationChainId,
            1,
            uint32(block.timestamp),
            uint32(block.timestamp + 3000),
            0,
            bytes32(bytes20(user)),
            bytes32(bytes20(user)),
            bytes32(0),
            ""
        );

        vm.expectEmit(true, true, true, false);
        emit IMigrator.MigrationStarted(
            migrationHash, tokenId, destinationChainId, address(settler), MigrationModes.SINGLE, user, token0, 0
        );
        vm.prank(user);
        IERC721(address(v4PositionManager)).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(migrationParams)
        );

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log[] memory swapEvents = findSwapEvents(entries);
        (, uint256 amountOut) = parseSwapEventForBothAmounts(swapEvents[0].data);
        Vm.Log memory fundsDepositedEvent = AcrossHelpers.findFundsDepositedEvent(entries);

        (bytes32 inputToken, bytes32 outputToken, uint256 inputAmount, uint256 outputAmount, bytes memory message) =
            AcrossHelpers.parseFundsDepositedEvent(fundsDepositedEvent.data);
        assertEq(inputToken, bytes32(uint256(uint160(token0))));
        assertEq(outputToken, bytes32(uint256(uint160(token0))));
        assertEq(inputAmount, amount0 + amountOut - 1); // -1 for rounding error
        assertEq(outputAmount, amount0 + amountOut - 1 - maxFees); // -1 for rounding error
        assertEq(message, data);
    }

    function test_onERC721Received_NativeToken_BelowTickLower() public {
        address token0 = weth; // this is still left as weth for later in the test
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

        IMigrator.MigrationParams memory migrationParams =
            MigrationHelpers.generateMigrationParams(token0, address(settler), maxFees);

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationHash = migrationData.toHash();
        bytes memory data = abi.encode(migrationHash, migrationData);

        vm.recordLogs();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v4PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // collect
        vm.expectEmit(true, true, false, true, address(usdc));
        emit IERC20.Transfer(address(v4PoolManager), address(migrator), amount1 - 1); // rounding error

        // swap event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Swap(poolId, address(universalRouter), 0, 0, 0, 0, 0, 0);

        // bridge
        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.FundsDeposited(
            bytes32(uint256(uint160(token0))), // still needs to be weth
            bytes32(uint256(uint160(token0))), // still needs to be weth
            0,
            0,
            destinationChainId,
            1,
            uint32(block.timestamp),
            uint32(block.timestamp + 3000),
            0,
            bytes32(bytes20(user)),
            bytes32(bytes20(user)),
            bytes32(0),
            ""
        );

        vm.expectEmit(true, true, true, false);
        emit IMigrator.MigrationStarted(
            migrationHash, tokenId, destinationChainId, address(settler), MigrationModes.SINGLE, user, token0, 0
        );
        vm.prank(user);
        IERC721(address(v4PositionManager)).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(migrationParams)
        );

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log[] memory swapEvents = findSwapEvents(entries);
        (, uint256 amountOut) = parseSwapEventForBothAmounts(swapEvents[0].data);
        Vm.Log memory fundsDepositedEvent = AcrossHelpers.findFundsDepositedEvent(entries);

        (bytes32 inputToken, bytes32 outputToken, uint256 inputAmount, uint256 outputAmount, bytes memory message) =
            AcrossHelpers.parseFundsDepositedEvent(fundsDepositedEvent.data);
        assertEq(inputToken, bytes32(uint256(uint160(token0))));
        assertEq(outputToken, bytes32(uint256(uint160(token0))));
        assertEq(inputAmount, amount0 + amountOut);
        assertEq(outputAmount, amount0 + amountOut - maxFees);
        assertEq(message, data);
    }

    function test_onERC721Received_NativeToken_AboveTickUpper() public {
        address token0 = weth; // this is still left as weth for later in the test
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
            MigrationHelpers.generateMigrationParams(token0, address(settler), amount0 - maxFees - 1);

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationHash = migrationData.toHash();
        bytes memory data = abi.encode(migrationHash, migrationData);

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

        // bridge
        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.FundsDeposited(
            bytes32(uint256(uint160(token0))), // still needs to be weth
            bytes32(uint256(uint160(token0))), // still needs to be weth
            0,
            0,
            destinationChainId,
            1,
            uint32(block.timestamp),
            uint32(block.timestamp + 3000),
            0,
            bytes32(bytes20(user)),
            bytes32(bytes20(user)),
            bytes32(0),
            ""
        );

        vm.expectEmit(true, true, true, false);
        emit IMigrator.MigrationStarted(
            migrationHash, tokenId, destinationChainId, address(settler), MigrationModes.SINGLE, user, token0, 0
        );
        vm.prank(user);
        IERC721(address(v4PositionManager)).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(migrationParams)
        );

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        (, uint256 amountOut) = (0, 0); // no swap
        Vm.Log memory fundsDepositedEvent = AcrossHelpers.findFundsDepositedEvent(entries);

        (bytes32 inputToken, bytes32 outputToken, uint256 inputAmount, uint256 outputAmount, bytes memory message) =
            AcrossHelpers.parseFundsDepositedEvent(fundsDepositedEvent.data);
        assertEq(inputToken, bytes32(uint256(uint160(token0))));
        assertEq(outputToken, bytes32(uint256(uint160(token0))));
        assertEq(inputAmount, amount0 + amountOut - 1); // -1 for rounding error
        assertEq(outputAmount, amount0 + amountOut - 1 - maxFees); // -1 for rounding error
        assertEq(message, data);
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
            MigrationHelpers.generateMigrationParams(token0, address(settler), amount0 - maxFees);

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationHash = migrationData.toHash();
        bytes memory data = abi.encode(migrationHash, migrationData);

        vm.recordLogs();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v4PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // collect
        vm.expectEmit(true, true, false, true, address(weth));
        emit IERC20.Transfer(address(v4PoolManager), address(migrator), amount0 - 1); // rounding error
        vm.expectEmit(true, true, false, true, address(usdc));
        emit IERC20.Transfer(address(v4PoolManager), address(migrator), amount1 - 1); // rounding error

        // swap event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Swap(poolId, address(universalRouter), 0, 0, 0, 0, 0, 0);

        // bridge
        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.FundsDeposited(
            bytes32(uint256(uint160(token0))),
            bytes32(uint256(uint160(token0))),
            0,
            0,
            destinationChainId,
            1,
            uint32(block.timestamp),
            uint32(block.timestamp + 3000),
            0,
            bytes32(bytes20(user)),
            bytes32(bytes20(user)),
            bytes32(0),
            ""
        );

        vm.expectEmit(true, true, true, false);
        emit IMigrator.MigrationStarted(
            migrationHash, tokenId, destinationChainId, address(settler), MigrationModes.SINGLE, user, token0, 0
        );
        vm.prank(user);
        IERC721(address(v4PositionManager)).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(migrationParams)
        );

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log[] memory swapEvents = findSwapEvents(entries);
        (, uint256 amountOut) = parseSwapEventForBothAmounts(swapEvents[0].data);
        Vm.Log memory fundsDepositedEvent = AcrossHelpers.findFundsDepositedEvent(entries);

        (bytes32 inputToken, bytes32 outputToken, uint256 inputAmount, uint256 outputAmount, bytes memory message) =
            AcrossHelpers.parseFundsDepositedEvent(fundsDepositedEvent.data);
        assertEq(inputToken, bytes32(uint256(uint160(token0))));
        assertEq(outputToken, bytes32(uint256(uint160(weth))));
        assertEq(inputAmount, amount0 + amountOut - 1); // -1 for rounding error
        assertEq(outputAmount, amount0 + amountOut - 1 - maxFees); // -1 for rounding error
        assertEq(message, data);
    }

    function test_onERC721Received_Token0WETHBaseToken_BelowTickLower() public {
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

        IMigrator.MigrationParams memory migrationParams =
            MigrationHelpers.generateMigrationParams(token0, address(settler), maxFees);

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationHash = migrationData.toHash();
        bytes memory data = abi.encode(migrationHash, migrationData);

        vm.recordLogs();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v4PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // collect token1
        vm.expectEmit(true, true, false, true, address(usdc));
        emit IERC20.Transfer(address(v4PoolManager), address(migrator), amount1 - 1); // rounding error

        // swap event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Swap(poolId, address(universalRouter), 0, 0, 0, 0, 0, 0);

        // bridge
        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.FundsDeposited(
            bytes32(uint256(uint160(token0))),
            bytes32(uint256(uint160(token0))),
            0,
            0,
            destinationChainId,
            1,
            uint32(block.timestamp),
            uint32(block.timestamp + 3000),
            0,
            bytes32(bytes20(user)),
            bytes32(bytes20(user)),
            bytes32(0),
            ""
        );

        vm.expectEmit(true, true, true, false);
        emit IMigrator.MigrationStarted(
            migrationHash, tokenId, destinationChainId, address(settler), MigrationModes.SINGLE, user, token0, 0
        );
        vm.prank(user);
        IERC721(address(v4PositionManager)).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(migrationParams)
        );

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log[] memory swapEvents = findSwapEvents(entries);
        (uint256 amountIn, uint256 amountOut) = parseSwapEventForBothAmounts(swapEvents[0].data);
        Vm.Log memory fundsDepositedEvent = AcrossHelpers.findFundsDepositedEvent(entries);

        (bytes32 inputToken, bytes32 outputToken, uint256 inputAmount, uint256 outputAmount, bytes memory message) =
            AcrossHelpers.parseFundsDepositedEvent(fundsDepositedEvent.data);
        assertEq(inputToken, bytes32(uint256(uint160(token0))));
        assertEq(outputToken, bytes32(uint256(uint160(weth))));
        assertEq(inputAmount, amount0 + amountOut);
        assertEq(outputAmount, amount0 + amountOut - maxFees);
        assertEq(message, data);
    }

    function test_onERC721Received_Token0WETHBaseToken_AboveTickUpper() public {
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
            MigrationHelpers.generateMigrationParams(token0, address(settler), amount0 - maxFees - 1);

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationHash = migrationData.toHash();
        bytes memory data = abi.encode(migrationHash, migrationData);

        vm.recordLogs();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v4PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // collect
        vm.expectEmit(true, true, false, true, address(weth));
        emit IERC20.Transfer(address(v4PoolManager), address(migrator), amount0 - 1);

        // swap event
        // no swap needed

        // bridge
        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.FundsDeposited(
            bytes32(uint256(uint160(token0))),
            bytes32(uint256(uint160(token0))),
            0,
            0,
            destinationChainId,
            1,
            uint32(block.timestamp),
            uint32(block.timestamp + 3000),
            0,
            bytes32(bytes20(user)),
            bytes32(bytes20(user)),
            bytes32(0),
            ""
        );

        vm.expectEmit(true, true, true, false);
        emit IMigrator.MigrationStarted(
            migrationHash, tokenId, destinationChainId, address(settler), MigrationModes.SINGLE, user, token0, 0
        );
        vm.prank(user);
        IERC721(address(v4PositionManager)).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(migrationParams)
        );

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 amountOut = 0;
        Vm.Log memory fundsDepositedEvent = AcrossHelpers.findFundsDepositedEvent(entries);

        (bytes32 inputToken, bytes32 outputToken, uint256 inputAmount, uint256 outputAmount, bytes memory message) =
            AcrossHelpers.parseFundsDepositedEvent(fundsDepositedEvent.data);
        assertEq(inputToken, bytes32(uint256(uint160(token0))));
        assertEq(outputToken, bytes32(uint256(uint160(weth))));
        assertEq(inputAmount, amount0 + amountOut - 1); // -1 for rounding error
        assertEq(outputAmount, amount0 + amountOut - 1 - maxFees); // -1 for rounding error
        assertEq(message, data);
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
            MigrationHelpers.generateMigrationParams(token1, address(settler), amount1 - maxFees);

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationHash = migrationData.toHash();
        bytes memory data = abi.encode(migrationHash, migrationData);

        vm.recordLogs();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v4PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId + 1);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // collect
        vm.expectEmit(true, true, false, true, address(virtualToken));
        emit IERC20.Transfer(address(v4PoolManager), address(migrator), amount0 - 1); // rounding error
        vm.expectEmit(true, true, false, true, address(weth));
        emit IERC20.Transfer(address(v4PoolManager), address(migrator), amount1 - 1); // rounding error

        // swap event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Swap(poolId, address(universalRouter), 0, 0, 0, 0, 0, 0);

        // bridge
        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.FundsDeposited(
            bytes32(uint256(uint160(token1))),
            bytes32(uint256(uint160(token1))),
            0,
            0,
            destinationChainId,
            1,
            uint32(block.timestamp),
            uint32(block.timestamp + 3000),
            0,
            bytes32(bytes20(user)),
            bytes32(bytes20(user)),
            bytes32(0),
            ""
        );

        vm.expectEmit(true, true, true, false);
        emit IMigrator.MigrationStarted(
            migrationHash, tokenId, destinationChainId, address(settler), MigrationModes.SINGLE, user, token1, 0
        );
        vm.prank(user);
        IERC721(address(v4PositionManager)).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(migrationParams)
        );

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log[] memory swapEvents = findSwapEvents(entries);
        (, uint256 amountOut) = parseSwapEventForBothAmounts(swapEvents[0].data);
        Vm.Log memory fundsDepositedEvent = AcrossHelpers.findFundsDepositedEvent(entries);

        (bytes32 inputToken, bytes32 outputToken, uint256 inputAmount, uint256 outputAmount, bytes memory message) =
            AcrossHelpers.parseFundsDepositedEvent(fundsDepositedEvent.data);
        assertEq(inputToken, bytes32(uint256(uint160(token1))));
        assertEq(outputToken, bytes32(uint256(uint160(weth))));
        assertEq(inputAmount, amount1 + amountOut - 1); // -1 for rounding error
        assertEq(outputAmount, amount1 + amountOut - 1 - maxFees); // -1 for rounding error
        assertEq(message, data);
    }

    function test_onERC721Received_Token1WETHBaseToken_BelowTickLower() public {
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
            MigrationHelpers.generateMigrationParams(token1, address(settler), amount1 - maxFees - 1);

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationHash = migrationData.toHash();
        bytes memory data = abi.encode(migrationHash, migrationData);

        vm.recordLogs();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v4PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId + 1);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // collect
        vm.expectEmit(true, true, false, true, address(weth));
        emit IERC20.Transfer(address(v4PoolManager), address(migrator), amount1 - 1); // rounding error

        // swap event
        // no swap needed

        // bridge
        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.FundsDeposited(
            bytes32(uint256(uint160(token1))),
            bytes32(uint256(uint160(token1))),
            0,
            0,
            destinationChainId,
            1,
            uint32(block.timestamp),
            uint32(block.timestamp + 3000),
            0,
            bytes32(bytes20(user)),
            bytes32(bytes20(user)),
            bytes32(0),
            ""
        );

        vm.expectEmit(true, true, true, false);
        emit IMigrator.MigrationStarted(
            migrationHash, tokenId, destinationChainId, address(settler), MigrationModes.SINGLE, user, token1, 0
        );
        vm.prank(user);
        IERC721(address(v4PositionManager)).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(migrationParams)
        );

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        (, uint256 amountOut) = (0, 0);
        Vm.Log memory fundsDepositedEvent = AcrossHelpers.findFundsDepositedEvent(entries);

        (bytes32 inputToken, bytes32 outputToken, uint256 inputAmount, uint256 outputAmount, bytes memory message) =
            AcrossHelpers.parseFundsDepositedEvent(fundsDepositedEvent.data);
        assertEq(inputToken, bytes32(uint256(uint160(token1))));
        assertEq(outputToken, bytes32(uint256(uint160(weth))));
        assertEq(inputAmount, amount1 + amountOut - 1); // -1 for rounding error
        assertEq(outputAmount, amount1 + amountOut - 1 - maxFees); // -1 for rounding error
        assertEq(message, data);
    }

    function test_onERC721Received_Token1WETHBaseToken_AboveTickUpper() public {
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
        IMigrator.MigrationParams memory migrationParams =
            MigrationHelpers.generateMigrationParams(token1, address(settler), maxFees);

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationHash = migrationData.toHash();
        bytes memory data = abi.encode(migrationHash, migrationData);

        vm.recordLogs();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v4PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId + 1);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // collect
        vm.expectEmit(true, true, false, true, address(virtualToken));
        emit IERC20.Transfer(address(v4PoolManager), address(migrator), amount0 - 1); // rounding error

        // swap event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Swap(poolId, address(universalRouter), 0, 0, 0, 0, 0, 0);

        // bridge
        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.FundsDeposited(
            bytes32(uint256(uint160(token1))),
            bytes32(uint256(uint160(token1))),
            0,
            0,
            destinationChainId,
            1,
            uint32(block.timestamp),
            uint32(block.timestamp + 3000),
            0,
            bytes32(bytes20(user)),
            bytes32(bytes20(user)),
            bytes32(0),
            ""
        );

        vm.expectEmit(true, true, true, false);
        emit IMigrator.MigrationStarted(
            migrationHash, tokenId, destinationChainId, address(settler), MigrationModes.SINGLE, user, token1, 0
        );
        vm.prank(user);
        IERC721(address(v4PositionManager)).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(migrationParams)
        );

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log[] memory swapEvents = findSwapEvents(entries);
        (, uint256 amountOut) = parseSwapEventForBothAmounts(swapEvents[0].data);
        Vm.Log memory fundsDepositedEvent = AcrossHelpers.findFundsDepositedEvent(entries);

        (bytes32 inputToken, bytes32 outputToken, uint256 inputAmount, uint256 outputAmount, bytes memory message) =
            AcrossHelpers.parseFundsDepositedEvent(fundsDepositedEvent.data);
        assertEq(inputToken, bytes32(uint256(uint160(token1))));
        assertEq(outputToken, bytes32(uint256(uint160(weth))));
        assertEq(inputAmount, amount1 + amountOut);
        assertEq(outputAmount, amount1 + amountOut - maxFees);
        assertEq(message, data);
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
            MigrationHelpers.generateMigrationParams(token0, destChainUsdc, amount0 - maxFees, address(settler));

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationHash = migrationData.toHash();
        bytes memory data = abi.encode(migrationHash, migrationData);

        vm.recordLogs();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v4PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // collect
        vm.expectEmit(true, true, false, true, address(usdc));
        emit IERC20.Transfer(address(v4PoolManager), address(migrator), amount0 - 1); // rounding error
        vm.expectEmit(true, true, false, true, address(usdt));
        emit IERC20.Transfer(address(v4PoolManager), address(migrator), amount1 - 1); // rounding error

        // swap event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Swap(poolId, address(universalRouter), 0, 0, 0, 0, 0, 0);

        // bridge
        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.FundsDeposited(
            bytes32(uint256(uint160(token0))),
            bytes32(uint256(uint160(destChainUsdc))),
            0,
            0,
            destinationChainId,
            1,
            uint32(block.timestamp),
            uint32(block.timestamp + 3000),
            0,
            bytes32(bytes20(user)),
            bytes32(bytes20(user)),
            bytes32(0),
            ""
        );

        vm.expectEmit(true, true, true, false);
        emit IMigrator.MigrationStarted(
            migrationHash, tokenId, destinationChainId, address(settler), MigrationModes.SINGLE, user, token0, 0
        );
        vm.prank(user);
        IERC721(address(v4PositionManager)).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(migrationParams)
        );

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log[] memory swapEvents = findSwapEvents(entries);
        (, uint256 amountOut) = parseSwapEventForBothAmounts(swapEvents[0].data);
        Vm.Log memory fundsDepositedEvent = AcrossHelpers.findFundsDepositedEvent(entries);

        (bytes32 inputToken, bytes32 outputToken, uint256 inputAmount, uint256 outputAmount, bytes memory message) =
            AcrossHelpers.parseFundsDepositedEvent(fundsDepositedEvent.data);
        assertEq(inputToken, bytes32(uint256(uint160(token0))));
        assertEq(outputToken, bytes32(uint256(uint160(destChainUsdc))));
        assertEq(inputAmount, amount0 + amountOut - 1); // -1 for rounding error
        assertEq(outputAmount, amount0 + amountOut - 1 - maxFees); // -1 for rounding error
        assertEq(message, data);
    }

    function test_onERC721Received_Token0USDCBaseToken_NoWETH_BelowTickLower() public {
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

        IMigrator.MigrationParams memory migrationParams =
            MigrationHelpers.generateMigrationParams(token0, destChainUsdc, maxFees, address(settler));

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationHash = migrationData.toHash();
        bytes memory data = abi.encode(migrationHash, migrationData);

        vm.recordLogs();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v4PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // collect
        vm.expectEmit(true, true, false, true, address(usdt));
        emit IERC20.Transfer(address(v4PoolManager), address(migrator), amount1 - 1); // rounding error

        // swap event
        vm.expectEmit(true, true, false, false);
        emit IPoolManager.Swap(poolId, address(universalRouter), 0, 0, 0, 0, 0, 0);

        // bridge
        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.FundsDeposited(
            bytes32(uint256(uint160(token0))),
            bytes32(uint256(uint160(destChainUsdc))),
            0,
            0,
            destinationChainId,
            1,
            uint32(block.timestamp),
            uint32(block.timestamp + 3000),
            0,
            bytes32(bytes20(user)),
            bytes32(bytes20(user)),
            bytes32(0),
            ""
        );

        vm.expectEmit(true, true, true, false);
        emit IMigrator.MigrationStarted(
            migrationHash, tokenId, destinationChainId, address(settler), MigrationModes.SINGLE, user, token0, 0
        );
        vm.prank(user);
        IERC721(address(v4PositionManager)).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(migrationParams)
        );

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log[] memory swapEvents = findSwapEvents(entries);
        (, uint256 amountOut) = parseSwapEventForBothAmounts(swapEvents[0].data);
        Vm.Log memory fundsDepositedEvent = AcrossHelpers.findFundsDepositedEvent(entries);

        (bytes32 inputToken, bytes32 outputToken, uint256 inputAmount, uint256 outputAmount, bytes memory message) =
            AcrossHelpers.parseFundsDepositedEvent(fundsDepositedEvent.data);
        assertEq(inputToken, bytes32(uint256(uint160(token0))));
        assertEq(outputToken, bytes32(uint256(uint160(destChainUsdc))));
        assertEq(inputAmount, amount0 + amountOut);
        assertEq(outputAmount, amount0 + amountOut - maxFees);
        assertEq(message, data);
    }

    function test_onERC721Received_Token0USDCBaseToken_NoWETH_AboveTickUpper() public {
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
            MigrationHelpers.generateMigrationParams(token0, destChainUsdc, amount0 - maxFees - 1, address(settler));

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationHash = migrationData.toHash();
        bytes memory data = abi.encode(migrationHash, migrationData);

        vm.recordLogs();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v4PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // collect
        vm.expectEmit(true, true, false, true, address(usdc));
        emit IERC20.Transfer(address(v4PoolManager), address(migrator), amount0 - 1); // rounding error

        // swap event
        // no swap needed

        // bridge
        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.FundsDeposited(
            bytes32(uint256(uint160(token0))),
            bytes32(uint256(uint160(destChainUsdc))),
            0,
            0,
            destinationChainId,
            1,
            uint32(block.timestamp),
            uint32(block.timestamp + 3000),
            0,
            bytes32(bytes20(user)),
            bytes32(bytes20(user)),
            bytes32(0),
            ""
        );

        vm.expectEmit(true, true, true, false);
        emit IMigrator.MigrationStarted(
            migrationHash, tokenId, destinationChainId, address(settler), MigrationModes.SINGLE, user, token0, 0
        );
        vm.prank(user);
        IERC721(address(v4PositionManager)).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(migrationParams)
        );

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        (, uint256 amountOut) = (0, 0);
        Vm.Log memory fundsDepositedEvent = AcrossHelpers.findFundsDepositedEvent(entries);

        (bytes32 inputToken, bytes32 outputToken, uint256 inputAmount, uint256 outputAmount, bytes memory message) =
            AcrossHelpers.parseFundsDepositedEvent(fundsDepositedEvent.data);
        assertEq(inputToken, bytes32(uint256(uint160(token0))));
        assertEq(outputToken, bytes32(uint256(uint160(destChainUsdc))));
        assertEq(inputAmount, amount0 + amountOut - 1); // -1 for rounding error
        assertEq(outputAmount, amount0 + amountOut - 1 - maxFees); // -1 for rounding error
        assertEq(message, data);
    }

    /**
     * DUAL TOKEN PATHS ***
     */
    function test_onERC721Received_NativeTokenandERC20BaseTokens_InRange() public {
        address token0 = weth; // this is still left as weth for later in the test
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

        IMigrator.MigrationParams memory migrationParams = MigrationHelpers.generateMigrationParams(
            token0, token1, token0, destChainUsdc, amount0 - maxFees - 1, amount1 - maxFees - 1, address(settler)
        );

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.DUAL,
            routesData: abi.encode(token0, token1, amount0 - maxFees - 1, amount1 - maxFees - 1),
            settlementData: ""
        });
        bytes32 migrationHash = migrationData.toHash();
        bytes memory data = abi.encode(migrationHash, migrationData);

        vm.recordLogs();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v4PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // collect
        // native token won't emit transfer event
        vm.expectEmit(true, true, false, true, address(usdc));
        emit IERC20.Transfer(address(v4PoolManager), address(migrator), amount1 - 1); // rounding error

        // swap event
        // no swap needed
        // bridge
        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.FundsDeposited(
            bytes32(uint256(uint160(token0))), // still needs to be weth
            bytes32(uint256(uint160(token0))), // still needs to be weth
            0,
            0,
            destinationChainId,
            1,
            uint32(block.timestamp),
            uint32(block.timestamp + 3000),
            0,
            bytes32(bytes20(user)),
            bytes32(bytes20(user)),
            bytes32(0),
            ""
        );

        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.FundsDeposited(
            bytes32(uint256(uint160(token1))),
            bytes32(uint256(uint160(destChainUsdc))),
            0,
            0,
            destinationChainId,
            1,
            uint32(block.timestamp),
            uint32(block.timestamp + 3000),
            0,
            bytes32(bytes20(user)),
            bytes32(bytes20(user)),
            bytes32(0),
            ""
        );

        vm.expectEmit(true, true, true, false);
        emit IMigrator.MigrationStarted(
            migrationHash, tokenId, destinationChainId, address(settler), MigrationModes.DUAL, user, token0, 0
        );
        vm.expectEmit(true, true, true, false);
        emit IMigrator.MigrationStarted(
            migrationHash, tokenId, destinationChainId, address(settler), MigrationModes.DUAL, user, token1, 0
        );
        vm.prank(user);
        IERC721(address(v4PositionManager)).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(migrationParams)
        );

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log[] memory fundsDepositedEvents = AcrossHelpers.findFundsDepositedEvents(entries);
        (bytes32 inputToken0, bytes32 outputToken0, uint256 inputAmount0, uint256 outputAmount0, bytes memory message0)
        = AcrossHelpers.parseFundsDepositedEvent(fundsDepositedEvents[0].data);
        assertEq(inputToken0, bytes32(uint256(uint160(token0))));
        assertEq(outputToken0, bytes32(uint256(uint160(weth))));
        assertEq(inputAmount0, amount0 - 1); // -1 for rounding error
        assertEq(outputAmount0, amount0 - 1 - maxFees); // -1 for rounding error
        assertEq(message0, data);
        (bytes32 inputToken1, bytes32 outputToken1, uint256 inputAmount1, uint256 outputAmount1, bytes memory message1)
        = AcrossHelpers.parseFundsDepositedEvent(fundsDepositedEvents[1].data);
        assertEq(inputToken1, bytes32(uint256(uint160(token1))));
        assertEq(outputToken1, bytes32(uint256(uint160(destChainUsdc))));
        assertEq(inputAmount1, amount1 - 1); // -1 for rounding error
        assertEq(outputAmount1, amount1 - 1 - maxFees); // -1 for rounding error
        assertEq(message1, data);
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
            MigrationHelpers.generateMigrationParams(token0, token1, token0, destChainUsdc, amount0 - maxFees-1, amount1 - maxFees-1, address(settler));

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.DUAL,
            routesData: abi.encode(token0, token1, amount0 - maxFees-1, amount1 - maxFees-1),
            settlementData: ""
        });
        bytes32 migrationHash = migrationData.toHash();
        bytes memory data = abi.encode(migrationHash, migrationData);

        vm.recordLogs();

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v4PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IPoolManager.ModifyLiquidity(poolId, address(v4PositionManager), 0, 0, 0, bytes32(0));

        // collect
        vm.expectEmit(true, true, false, true, address(weth));
        emit IERC20.Transfer(address(v4PoolManager), address(migrator), amount0 - 1); // rounding error
        vm.expectEmit(true, true, false, true, address(usdc));
        emit IERC20.Transfer(address(v4PoolManager), address(migrator), amount1 - 1); // rounding error

        // swap event
        // no swap needed

        // bridge
        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.FundsDeposited(
            bytes32(uint256(uint160(token0))),
            bytes32(uint256(uint160(token0))),
            0,
            0,
            destinationChainId,
            1,
            uint32(block.timestamp),
            uint32(block.timestamp + 3000),
            0,
            bytes32(bytes20(user)),
            bytes32(bytes20(user)),
            bytes32(0),
            ""
        );

        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.FundsDeposited(
            bytes32(uint256(uint160(token1))),
            bytes32(uint256(uint160(destChainUsdc))),
            0,
            0,
            destinationChainId,
            1,
            uint32(block.timestamp),
            uint32(block.timestamp + 3000),
            0,
            bytes32(bytes20(user)),
            bytes32(bytes20(user)),
            bytes32(0),
            ""
        );

        vm.expectEmit(true, true, true, false);
        emit IMigrator.MigrationStarted(
            migrationHash, tokenId, destinationChainId, address(settler), MigrationModes.DUAL, user, token0, 0
        );
                vm.expectEmit(true, true, true, false);
        emit IMigrator.MigrationStarted(
            migrationHash, tokenId, destinationChainId, address(settler), MigrationModes.DUAL, user, token1, 0
        );
        vm.prank(user);
        IERC721(address(v4PositionManager)).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(migrationParams)
        );

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log[] memory fundsDepositedEvents = AcrossHelpers.findFundsDepositedEvents(entries);
        (bytes32 inputToken0, bytes32 outputToken0, uint256 inputAmount0, uint256 outputAmount0, bytes memory message0)
        = AcrossHelpers.parseFundsDepositedEvent(fundsDepositedEvents[0].data);
        assertEq(inputToken0, bytes32(uint256(uint160(token0))));
        assertEq(outputToken0, bytes32(uint256(uint160(weth))));
        assertEq(inputAmount0, amount0 - 1); // -1 for rounding error
        assertEq(outputAmount0, amount0 - 1 - maxFees); // -1 for rounding error
        assertEq(message0, data);
        (bytes32 inputToken1, bytes32 outputToken1, uint256 inputAmount1, uint256 outputAmount1, bytes memory message1)
        = AcrossHelpers.parseFundsDepositedEvent(fundsDepositedEvents[1].data);
        assertEq(inputToken1, bytes32(uint256(uint160(token1))));
        assertEq(outputToken1, bytes32(uint256(uint160(destChainUsdc))));
        assertEq(inputAmount1, amount1 - 1); // -1 for rounding error
        assertEq(outputAmount1, amount1 - 1 - maxFees); // -1 for rounding error
        assertEq(message1, data);
        }

    function test() public override(TestContext, UniswapV4Helpers) {}
}
