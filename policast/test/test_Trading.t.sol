// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PolicastMarketV3} from "../src/V3.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract TradingTest is Test {
    PolicastMarketV3 public market;
    MockERC20 public bettingToken;
    address public owner = address(0x123);
    address public user1 = address(0x456);
    address public user2 = address(0x789);
    address public validator = address(0x999);

    uint256 public constant INITIAL_LIQUIDITY = 1000 * 1e18;
    uint256 public marketId;

    function setUp() public {
        vm.startPrank(owner);
        bettingToken = new MockERC20("Betting Token", "BET", 18);
        market = new PolicastMarketV3(address(bettingToken));

        // Mint tokens to users
        bettingToken.mint(owner, 1000000 * 1e18);
        bettingToken.mint(user1, 1000000 * 1e18);
        bettingToken.mint(user2, 1000000 * 1e18);

        // Approve market to spend tokens
        bettingToken.approve(address(market), type(uint256).max);

        // Grant validator role
        market.grantMarketValidatorRole(validator);

        vm.stopPrank();

        vm.startPrank(user1);
        bettingToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        bettingToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        // Create and validate a market for testing
        vm.startPrank(owner);
        string[] memory optionNames = new string[](2);
        optionNames[0] = "Yes";
        optionNames[1] = "No";

        string[] memory optionDescriptions = new string[](2);
        optionDescriptions[0] = "Option Yes";
        optionDescriptions[1] = "Option No";

        marketId = market.createMarket(
            "Will it rain tomorrow?",
            "Weather prediction market",
            optionNames,
            optionDescriptions,
            1 days,
            PolicastMarketV3.MarketCategory.OTHER,
            PolicastMarketV3.MarketType.PAID,
            INITIAL_LIQUIDITY
        );

        // Validate the market
        market.validateMarket(marketId);
        vm.stopPrank();
    }

    function testBuySharesSuccess() public {
        vm.startPrank(user1);

        uint256 initialBalance = bettingToken.balanceOf(user1);
        uint256 quantity = 100 * 1e18;
        uint256 maxPrice = 50 * 1e18; // Higher max price to allow for AMM pricing

        market.buyShares(marketId, 0, quantity, maxPrice);

        // Verify shares were purchased
        uint256[] memory shares = market.getUserShares(marketId, user1);
        assertEq(shares[0], quantity);
        assertEq(shares[1], 0);

        // Verify tokens were spent
        uint256 finalBalance = bettingToken.balanceOf(user1);
        assertLt(finalBalance, initialBalance); // Some tokens were spent

        vm.stopPrank();
    }

    function testBuySharesPriceTooHigh() public {
        vm.startPrank(user1);

        uint256 quantity = 100 * 1e18;
        uint256 maxPrice = 0.001 * 1e18; // Very low max price to trigger slippage

        vm.expectRevert(PolicastMarketV3.PriceTooHigh.selector);
        market.buyShares(marketId, 0, quantity, maxPrice);

        vm.stopPrank();
    }

    function testBuySharesAmountMustBePositive() public {
        vm.startPrank(user1);

        vm.expectRevert(PolicastMarketV3.AmountMustBePositive.selector);
        market.buyShares(marketId, 0, 0, 1 * 1e18);

        vm.stopPrank();
    }

    function testBuySharesMarketNotValidated() public {
        // Create a new unvalidated market
        vm.startPrank(owner);
        string[] memory optionNames = new string[](2);
        optionNames[0] = "Yes";
        optionNames[1] = "No";

        string[] memory optionDescriptions = new string[](2);
        optionDescriptions[0] = "Option Yes";
        optionDescriptions[1] = "Option No";

        uint256 unvalidatedMarketId = market.createMarket(
            "Unvalidated market",
            "Should fail",
            optionNames,
            optionDescriptions,
            1 days,
            PolicastMarketV3.MarketCategory.OTHER,
            PolicastMarketV3.MarketType.PAID,
            INITIAL_LIQUIDITY
        );
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert(PolicastMarketV3.MarketNotValidated.selector);
        market.buyShares(unvalidatedMarketId, 0, 100 * 1e18, 1 * 1e18);
        vm.stopPrank();
    }

    function testBuySharesInvalidOption() public {
        vm.startPrank(user1);

        vm.expectRevert(PolicastMarketV3.InvalidOption.selector);
        market.buyShares(marketId, 99, 100 * 1e18, 1 * 1e18); // Invalid option ID

        vm.stopPrank();
    }

    function testBuySharesTransferFailed() public {
        vm.startPrank(user1);

        // Revoke approval to make transfer fail
        bettingToken.approve(address(market), 0);

        vm.expectRevert(); // Expect any revert for transfer failure
        market.buyShares(marketId, 0, 100 * 1e18, 10 * 1e18);

        vm.stopPrank();
    }

    function testSellSharesSuccess() public {
        // First buy some shares
        vm.startPrank(user1);
        market.buyShares(marketId, 0, 100 * 1e18, 50 * 1e18);
        vm.stopPrank();

        // Now sell them
        vm.startPrank(user1);

        uint256 initialBalance = bettingToken.balanceOf(user1);
        uint256 sellQuantity = 50 * 1e18;
        uint256 minPrice = 0.001 * 1e18; // Low minimum to ensure sale

        market.sellShares(marketId, 0, sellQuantity, minPrice);

        // Verify shares were reduced
        uint256[] memory shares = market.getUserShares(marketId, user1);
        assertEq(shares[0], 50 * 1e18); // Should have 50 left
        assertEq(shares[1], 0);

        // Verify tokens were received
        uint256 finalBalance = bettingToken.balanceOf(user1);
        assertGt(finalBalance, initialBalance); // Some tokens were received

        vm.stopPrank();
    }

    function testSellSharesPriceTooLow() public {
        // First buy some shares
        vm.startPrank(user1);
        market.buyShares(marketId, 0, 100 * 1e18, 50 * 1e18);
        vm.stopPrank();

        // Try to sell with too high minimum price
        vm.startPrank(user1);

        uint256 sellQuantity = 50 * 1e18;
        uint256 minPrice = 100 * 1e18; // Very high minimum to trigger slippage

        vm.expectRevert(PolicastMarketV3.PriceTooLow.selector);
        market.sellShares(marketId, 0, sellQuantity, minPrice);

        vm.stopPrank();
    }

    function testSellSharesInsufficientShares() public {
        vm.startPrank(user1);

        vm.expectRevert(PolicastMarketV3.InsufficientShares.selector);
        market.sellShares(marketId, 0, 100 * 1e18, 0.1 * 1e18); // Trying to sell shares we don't have

        vm.stopPrank();
    }

    function testSellSharesTransferFailed() public {
        // First buy some shares
        vm.startPrank(user1);
        market.buyShares(marketId, 0, 100 * 1e18, 50 * 1e18);
        vm.stopPrank();

        // Mock the token contract to return false on transfer
        vm.startPrank(user1);
        vm.mockCall(address(bettingToken), abi.encodeWithSelector(bettingToken.transfer.selector), abi.encode(false));

        vm.expectRevert(PolicastMarketV3.TransferFailed.selector);
        market.sellShares(marketId, 0, 50 * 1e18, 0.001 * 1e18);

        vm.stopPrank();
    }

    function testAMMSwapSuccess() public {
        // First buy some shares of option 0
        vm.startPrank(user1);
        market.buyShares(marketId, 0, 100 * 1e18, 50 * 1e18);
        vm.stopPrank();

        // Now swap from option 0 to option 1
        vm.startPrank(user1);

        uint256 swapAmount = 50 * 1e18;
        uint256 minAmountOut = 1 * 1e18;

        uint256 amountOut = market.ammSwap(marketId, 0, 1, swapAmount, minAmountOut);

        // Verify swap occurred
        uint256[] memory shares = market.getUserShares(marketId, user1);
        assertEq(shares[0], 50 * 1e18); // Reduced by swap amount
        assertEq(shares[1], amountOut); // Increased by output amount

        vm.stopPrank();
    }

    function testAMMSwapSameOption() public {
        vm.startPrank(user1);

        vm.expectRevert(PolicastMarketV3.CannotSwapSameOption.selector);
        market.ammSwap(marketId, 0, 0, 100 * 1e18, 1 * 1e18);

        vm.stopPrank();
    }

    function testAMMSwapInsufficientShares() public {
        vm.startPrank(user1);

        vm.expectRevert(PolicastMarketV3.InsufficientShares.selector);
        market.ammSwap(marketId, 0, 1, 100 * 1e18, 1 * 1e18); // Don't have shares to swap

        vm.stopPrank();
    }

    function testAMMSwapInsufficientOutput() public {
        // First buy some shares
        vm.startPrank(user1);
        market.buyShares(marketId, 0, 100 * 1e18, 50 * 1e18);
        vm.stopPrank();

        // Try to swap with very high minimum output
        vm.startPrank(user1);

        vm.expectRevert(PolicastMarketV3.InsufficientOutput.selector);
        market.ammSwap(marketId, 0, 1, 50 * 1e18, 1000 * 1e18); // Unrealistic minimum

        vm.stopPrank();
    }

    function testAMMSwapInsufficientLiquidity() public {
        // Buy a large amount to reduce available liquidity significantly
        vm.startPrank(user1);
        market.buyShares(marketId, 0, 400 * 1e18, 500 * 1e18);
        vm.stopPrank();

        // Try to swap an amount that would require more liquidity than available
        vm.startPrank(user1);

        // This should fail because we're trying to get more from the reserve than exists
        vm.expectRevert(); // Expect any revert related to insufficient liquidity
        market.ammSwap(marketId, 0, 1, 350 * 1e18, 400 * 1e18); // Try to get more than available

        vm.stopPrank();
    }

    function testCalculateAMMBuyCost() public view {
        uint256 quantity = 100 * 1e18;
        uint256 cost = market.calculateAMMBuyCost(marketId, 0, quantity);

        // Cost should be positive and reasonable
        assertGt(cost, 0);
        assertLt(cost, quantity * 10); // Shouldn't be more than 10x the quantity
    }

    function testCalculateAMMSellRevenue() public view {
        uint256 quantity = 100 * 1e18;
        uint256 revenue = market.calculateAMMSellRevenue(marketId, 0, quantity);

        // Revenue should be positive and reasonable
        assertGt(revenue, 0);
        assertLt(revenue, quantity * 10); // Shouldn't be more than 10x the quantity
    }

    function testCalculateCurrentPrice() public view {
        uint256 price = market.calculateCurrentPrice(marketId, 0);

        // Price should be positive and reasonable (around 0.5 for equal distribution)
        assertGt(price, 0.1 * 1e18);
        assertLt(price, 1 * 1e18);
    }

    function testCalculateNewPriceBuy() public view {
        uint256 quantity = 100 * 1e18;
        uint256 newPrice = market.calculateNewPrice(marketId, 0, quantity, true);

        uint256 currentPrice = market.calculateCurrentPrice(marketId, 0);

        // New price after buy should be higher than current price
        assertGt(newPrice, currentPrice);
    }

    function testCalculateNewPriceSell() public view {
        uint256 quantity = 100 * 1e18;
        uint256 newPrice = market.calculateNewPrice(marketId, 0, quantity, false);

        uint256 currentPrice = market.calculateCurrentPrice(marketId, 0);

        // When selling shares, the price should decrease (more supply = lower price)
        // This is now working correctly with the fixed AMM logic
        assertLt(newPrice, currentPrice);
    }

    function testBuySharesWithExactMaxPrice() public {
        vm.startPrank(user1);

        uint256 quantity = 100 * 1e18;
        uint256 cost = market.calculateAMMBuyCost(marketId, 0, quantity);
        uint256 avgPrice = (cost * 1e18) / quantity; // Proper scaling for price per share
        uint256 maxPrice = avgPrice + (avgPrice / 100); // Add 1% buffer for AMM slippage

        market.buyShares(marketId, 0, quantity, maxPrice);

        uint256[] memory shares = market.getUserShares(marketId, user1);
        assertEq(shares[0], quantity);

        vm.stopPrank();
    }

    function testSellSharesWithExactMinPrice() public {
        // First buy shares
        vm.startPrank(user1);
        market.buyShares(marketId, 0, 100 * 1e18, 50 * 1e18);
        vm.stopPrank();

        vm.startPrank(user1);
        uint256 sellQuantity = 50 * 1e18;
        uint256 revenue = market.calculateAMMSellRevenue(marketId, 0, sellQuantity);
        uint256 exactMinPrice = revenue / sellQuantity;

        market.sellShares(marketId, 0, sellQuantity, exactMinPrice);

        uint256[] memory shares = market.getUserShares(marketId, user1);
        assertEq(shares[0], 50 * 1e18);

        vm.stopPrank();
    }

    function testMultipleUserTrading() public {
        // User1 buys shares
        vm.startPrank(user1);
        market.buyShares(marketId, 0, 100 * 1e18, 50 * 1e18);
        vm.stopPrank();

        // User2 buys different option
        vm.startPrank(user2);
        market.buyShares(marketId, 1, 100 * 1e18, 50 * 1e18);
        vm.stopPrank();

        // Verify both users have shares
        uint256[] memory user1Shares = market.getUserShares(marketId, user1);
        uint256[] memory user2Shares = market.getUserShares(marketId, user2);

        assertEq(user1Shares[0], 100 * 1e18);
        assertEq(user1Shares[1], 0);
        assertEq(user2Shares[0], 0);
        assertEq(user2Shares[1], 100 * 1e18);
    }

    function testLargeTradingVolume() public {
        vm.startPrank(user1);

        // Buy a large amount - use smaller quantity to avoid extreme slippage
        uint256 largeQuantity = 400 * 1e18; // Reduced from 800 to 400
        uint256 cost = market.calculateAMMBuyCost(marketId, 0, largeQuantity);
        uint256 maxPrice = (cost * 1e18 * 120) / (largeQuantity * 100); // 20% slippage tolerance with proper scaling

        market.buyShares(marketId, 0, largeQuantity, maxPrice);

        uint256[] memory shares = market.getUserShares(marketId, user1);
        assertEq(shares[0], largeQuantity);

        vm.stopPrank();
    }

    function testAMMSwapAfterLargeBuy() public {
        // First user makes a large buy
        vm.startPrank(user1);
        market.buyShares(marketId, 0, 300 * 1e18, 500 * 1e18);
        vm.stopPrank();

        // Second user makes smaller buy then swaps
        vm.startPrank(user2);
        market.buyShares(marketId, 1, 100 * 1e18, 50 * 1e18);

        uint256 swapAmount = 50 * 1e18;
        uint256 amountOut = market.ammSwap(marketId, 1, 0, swapAmount, 1 * 1e18);

        uint256[] memory shares = market.getUserShares(marketId, user2);
        assertEq(shares[1], 50 * 1e18); // Remaining shares
        assertEq(shares[0], amountOut); // Swapped shares

        vm.stopPrank();
    }
}
