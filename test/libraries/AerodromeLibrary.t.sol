// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AerodromeLibrary} from "../../src/libraries/AerodromeLibrary.sol";
import {IAerodromeNonfungiblePositionManager} from "../../src/interfaces/external/IAerodromeNonfungiblePositionManager.sol";
import {TestContext} from "../utils/TestContext.sol";

contract AerodromeLibraryTest is TestContext {
    string public constant SRC_CHAIN_NAME = "BASE";
    string public constant DEST_CHAIN_NAME = "";

    address private token0;
    address private token1;
    mapping(address => bool) private isPermit2Approved;
    
    // Aerodrome-specific variables
    IAerodromeNonfungiblePositionManager private aerodromePositionManager;
    int24 private tickSpacing = 100; // Default tick spacing for Aerodrome
    uint160 private sqrtPriceX96 = 79228162514264337593543950336; // 1:1 price ratio

    function setUp() public {
        _loadChain(SRC_CHAIN_NAME, DEST_CHAIN_NAME);

        token0 = usdc < weth ? usdc : weth;
        token1 = usdc > weth ? usdc : weth;

        // For Aerodrome, we need to set up the position manager
        // Since this is a test, we'll use a mock or the actual Aerodrome position manager
        // You may need to add this to your environment variables
        aerodromePositionManager = IAerodromeNonfungiblePositionManager(vm.envAddress(string(abi.encodePacked(SRC_CHAIN_NAME, "_AERODROME_POSITION_MANAGER"))));
        
        // Note: AerodromeLibrary doesn't have a createAndInitializePoolIfNecessary function
        // The pool should already exist or be created through other means
    }

    function test_fuzz_mintPosition(bool extraOnZero, bool isTooMuchSlippage, bool newPool) public {
        address _token0 = token0;
        address _token1 = token1;

        if (newPool) {
            _token0 = usdc < usdt ? usdc : usdt;
            _token1 = usdc > usdt ? usdc : usdt;
        }

        deal(_token0, address(this), 200);
        deal(_token1, address(this), 200);

        uint256 amount0Desired = extraOnZero ? 200 : 100;
        uint256 amount1Desired = extraOnZero ? 100 : 200;
        uint256 amount0Min = isTooMuchSlippage ? type(uint128).max : 0;
        uint256 amount1Min = isTooMuchSlippage ? type(uint128).max : 0;

        if (isTooMuchSlippage) {
            vm.expectRevert(bytes("PSC"));
        }

        this.mintPositionWrapper(
            _token0,
            _token1,
            tickSpacing, 
            -600, 
            600, 
            amount0Desired, 
            amount1Desired, 
            amount0Min, 
            amount1Min, 
            address(this),
            newPool ? sqrtPriceX96 : 0
        );
    }

    function test_fuzz_liquidatePosition(bool hasMinMounts) public {
        deal(token0, address(this), 200);
        deal(token1, address(this), 200);

        (uint256 positionId,,,) = this.mintPositionWrapper(
            token0,
            token1,
            tickSpacing, 
            -600, 
            600, 
            200, 
            200, 
            0, 
            0, 
            address(this),
            0
        );
        
        uint256 amount0Min = hasMinMounts ? type(uint128).max : 0;
        uint256 amount1Min = hasMinMounts ? type(uint128).max : 0;

        if (hasMinMounts) {
            vm.expectRevert(bytes("PS"));
        }

        this.liquidatePositionWrapper(positionId, amount0Min, amount1Min, address(this));
    }

    function test_fuzz_swap(bool isZeroForOne, bool isTooMuchSlippage) public {
        deal(token0, address(this), 200);
        deal(token1, address(this), 200);

        address tokenIn = isZeroForOne ? token0 : token1;
        address tokenOut = isZeroForOne ? token1 : token0;
        uint256 amountOutMin = isTooMuchSlippage ? type(uint128).max : 0;

        if (isTooMuchSlippage) {
            vm.expectRevert(); // V3TooLittleReceived error selector
        }

        this.swapWrapper(tokenIn, tokenOut, tickSpacing, 100, amountOutMin, address(this));
    }

    function test_mintPosition_success() public {
        deal(token0, address(this), 1000000000000000000);
        deal(token1, address(this), 1000000000000000000);

        (uint256 positionId, uint128 liquidity, uint256 amount0, uint256 amount1) = this.mintPositionWrapper(
            token0,
            token1,
            tickSpacing,
            -300000,
            300000,
            1000000000000000000,
            1000000000000000000,
            0,
            0,
            address(this),
            0
        );

        assertGt(positionId, 0, "Position ID should be greater than 0");
        assertGt(liquidity, 0, "Liquidity should be greater than 0");
        assertGt(amount0, 0, "Amount0 should be greater than 0");
        assertGt(amount1, 0, "Amount1 should be greater than 0");
    }

    function test_liquidatePosition_success() public {
        deal(token0, address(this), 1000000000000000000);
        deal(token1, address(this), 1000000000000000000);

        (uint256 positionId,,,) = this.mintPositionWrapper(
            token0,
            token1,
            tickSpacing,
            -300000,
            300000,
            1000000000000000000,
            1000000000000000000,
            0,
            0,
            address(this),
            0
        );

        (address returnedToken0, address returnedToken1, int24 returnedTickSpacing, uint256 amount0, uint256 amount1) = 
            this.liquidatePositionWrapper(positionId, 0, 0, address(this));

        assertEq(returnedToken0, token0, "Returned token0 should match");
        assertEq(returnedToken1, token1, "Returned token1 should match");
        assertEq(returnedTickSpacing, tickSpacing, "Returned tick spacing should match");
        assertGt(amount0, 0, "Amount0 should be greater than 0");
        assertGt(amount1, 0, "Amount1 should be greater than 0");
    }

    function test_swap_success() public {
        deal(token0, address(this), 1000000000000000000);
        deal(token1, address(this), 1000000000000000000);

        uint256 amountOut = this.swapWrapper(token0, token1, tickSpacing, 5000000000000000, 0, address(this));

        assertGt(amountOut, 0, "Amount out should be greater than 0");
    }

    function test_mintPosition_differentTickRanges() public {
        address _token0 = usdc < usdt ? usdc : usdt;
        address _token1 = usdc > usdt ? usdc : usdt;

        deal(_token0, address(this), 10000);
        deal(_token1, address(this), 10000);

        // Test with different tick ranges
        int24[] memory tickRanges = new int24[](3);
        tickRanges[0] = 100; // Narrow range
        tickRanges[1] = 5000;
        tickRanges[2] = 10000;
        bool firstTime = true;

        for (uint i = 0; i < tickRanges.length; i++) {
            (uint256 positionId, uint128 liquidity, uint256 amount0, uint256 amount1) = this.mintPositionWrapper(
                _token0,
                _token1,
                10,
                -tickRanges[i],
                tickRanges[i],
                500,
                500,
                0,
                0,
                address(this),
                firstTime ? sqrtPriceX96 : 0
            );
            firstTime = false;

            assertGt(positionId, 0, "Position ID should be greater than 0");
            assertGt(liquidity, 0, "Liquidity should be greater than 0");
            assertGt(amount0, 0, "Amount0 should be greater than 0");
            assertGt(amount1, 0, "Amount1 should be greater than 0");
        }
    }

    function test_swap_differentAmounts() public {
        deal(token0, address(this), 1000000000000000000);
        deal(token1, address(this), 1000000000000000000);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1000000000000;   // Small amount
        amounts[1] = 10000000000000;  // Medium amount
        amounts[2] = 50000000000000;  // Large amount

        for (uint i = 0; i < amounts.length; i++) {
            uint256 amountOut = this.swapWrapper(token0, token1, tickSpacing, amounts[i], 0, address(this));
            assertGt(amountOut, 0, "Amount out should be greater than 0");
        }
    }

    function test_swap_reverseDirection() public {
        deal(token0, address(this), 1000000000000000000);
        deal(token1, address(this), 1000000000000000000);

        // Test swap in both directions
        uint256 amountOut1 = this.swapWrapper(token0, token1, tickSpacing, 5000000000000000, 0, address(this));
        uint256 amountOut2 = this.swapWrapper(token1, token0, tickSpacing, 50000, 0, address(this));

        assertGt(amountOut1, 0, "Amount out from token0 to token1 should be greater than 0");
        assertGt(amountOut2, 0, "Amount out from token1 to token0 should be greater than 0");
    }

    function mintPositionWrapper(
        address _token0,
        address _token1,
        int24 _tickSpacing,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address recipient,
        uint160 _sqrtPriceX96
    ) public returns (uint256, uint128, uint256, uint256) {
        return AerodromeLibrary.mintPosition(
            aerodromePositionManager,
            _token0,
            _token1,
            _tickSpacing,
            tickLower,
            tickUpper,
            amount0Desired,
            amount1Desired,
            amount0Min,
            amount1Min,
            recipient,
            _sqrtPriceX96
        );
    }

    function liquidatePositionWrapper(uint256 positionId, uint256 amount0Min, uint256 amount1Min, address recipient)
        public
        returns (address, address, int24, uint256, uint256)
    {
        return AerodromeLibrary.liquidatePosition(aerodromePositionManager, positionId, amount0Min, amount1Min, recipient);
    }

    function swapWrapper(
        address tokenIn,
        address tokenOut,
        int24 _tickSpacing,
        uint256 amountIn,
        uint256 amountOutMin,
        address recipient
    ) public returns (uint256) {
        return AerodromeLibrary.swap(
            aerodromeRouter, 
            permit2, 
            isPermit2Approved, 
            tokenIn, 
            tokenOut, 
            _tickSpacing, 
            amountIn, 
            amountOutMin, 
            recipient
        );
    }
} 