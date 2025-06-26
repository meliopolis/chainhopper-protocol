// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "@forge-std/Test.sol";
import {V3SpokePoolInterface as IAcrossSpokePool} from "@across/interfaces/V3SpokePoolInterface.sol";
import {IPermit2} from "@uniswap-permit2/interfaces/IPermit2.sol";
import {IUniversalRouter} from "@uniswap-universal-router/interfaces/IUniversalRouter.sol";
import {IHooks} from "@uniswap-v4-core/interfaces/IHooks.sol";
import {Currency} from "@uniswap-v4-core/types/Currency.sol";
import {PoolKey} from "@uniswap-v4-core/types/PoolKey.sol";
import {IPositionManager as IV4PositionManager} from "@uniswap-v4-periphery/interfaces/IPositionManager.sol";
import {IStateView} from "@uniswap-v4-periphery/interfaces/IStateView.sol";
import {IPoolManager} from "@uniswap-v4-core/interfaces/IPoolManager.sol";

// copied and modified from uniswap-v3-periphery, as the original had bad imports
import {INonfungiblePositionManager as IV3PositionManager} from
    "../../src/interfaces/external/INonfungiblePositionManager.sol";

contract TestContext is Test {
    address internal user = makeAddr("user");
    address internal owner = makeAddr("owner");

    address internal weth;
    address internal usdc;
    address internal usdt;
    address internal virtualToken;
    address internal destChainUsdc;
    address internal newTokenFirst = address(10); // so it sorts before weth
    address internal newTokenSecond = makeAddr("newToken");

    IAcrossSpokePool internal acrossSpokePool;
    IPermit2 internal permit2;
    IUniversalRouter internal universalRouter;
    IUniversalRouter internal aerodromeRouter;
    IV3PositionManager internal v3PositionManager;
    IV4PositionManager internal v4PositionManager;
    IStateView internal v4StateView;
    IPoolManager internal v4PoolManager;
    PoolKey internal v4FreshPoolKey;
    PoolKey internal v4NativePoolKey;
    PoolKey internal v4TokenPoolKey;

    function _loadChain(string memory srcChainName, string memory destChainName) internal {
        // setting block number to 28545100 for repeatability
        vm.createSelectFork(vm.envString(string(abi.encodePacked(srcChainName, "_RPC_URL"))), 28545100);

        weth = vm.envAddress(string(abi.encodePacked(srcChainName, "_WETH")));
        usdc = vm.envAddress(string(abi.encodePacked(srcChainName, "_USDC")));
        usdt = vm.envAddress(string(abi.encodePacked(srcChainName, "_USDT")));
        virtualToken = address(0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b); // useful as it sorts before weth and usdc
        if (bytes(destChainName).length > 0) {
            destChainUsdc = vm.envAddress(string(abi.encodePacked(destChainName, "_USDC")));
        }

        acrossSpokePool = IAcrossSpokePool(vm.envAddress(string(abi.encodePacked(srcChainName, "_ACROSS_SPOKE_POOL"))));
        permit2 = IPermit2(vm.envAddress(string(abi.encodePacked(srcChainName, "_UNISWAP_PERMIT2"))));
        universalRouter =
            IUniversalRouter(vm.envAddress(string(abi.encodePacked(srcChainName, "_UNISWAP_UNIVERSAL_ROUTER"))));
        aerodromeRouter = IUniversalRouter(vm.envAddress(string(abi.encodePacked(srcChainName, "_AERODROME_UNIVERSAL_ROUTER"))));
        v3PositionManager =
            IV3PositionManager(vm.envAddress(string(abi.encodePacked(srcChainName, "_UNISWAP_V3_POSITION_MANAGER"))));
        v4PositionManager =
            IV4PositionManager(vm.envAddress(string(abi.encodePacked(srcChainName, "_UNISWAP_V4_POSITION_MANAGER"))));
        v4StateView = IStateView(vm.envAddress(string(abi.encodePacked(srcChainName, "_UNISWAP_V4_STATE_VIEW"))));
        v4PoolManager = IPoolManager(vm.envAddress(string(abi.encodePacked(srcChainName, "_UNISWAP_V4_POOL_MANAGER"))));

        v4FreshPoolKey = PoolKey(Currency.wrap(address(1)), Currency.wrap(address(2)), 100, 1, IHooks(address(0)));
        v4NativePoolKey = PoolKey(Currency.wrap(address(0)), Currency.wrap(usdc), 500, 10, IHooks(address(0)));
        v4TokenPoolKey = PoolKey(
            Currency.wrap(usdc > usdt ? usdt : usdc),
            Currency.wrap(usdc > usdt ? usdc : usdt),
            100,
            1,
            IHooks(address(0))
        );
    }

    receive() external payable {}

    // add this to be excluded from coverage report
    function test() public virtual {}
}
