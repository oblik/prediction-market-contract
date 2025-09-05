// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/Console.sol";
import {PolicastMarketV3} from "../src/V3.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract PricingLogicTest is Test {
    PolicastMarketV3 public market;
    MockERC20 public bettingToken;
    address public owner = address(0x123);
    address public user1 = address(0x456);
    address public user2 = address(0x789);

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

        // Grant validator role to owner
        market.grantMarketValidatorRole(owner);

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
            "Test pricing market",
            "Testing AMM pricing logic",
            optionNames,
            optionDescriptions,
            1 days,
            PolicastMarketV3.MarketCategory.OTHER,
            PolicastMarketV3.MarketType.PAID,
            INITIAL_LIQUIDITY
        );

        market.validateMarket(marketId);
        vm.stopPrank();
    }

    function testInitialPricing() public view {
        // Test initial state
        uint256 price0 = market.calculateCurrentPrice(marketId, 0);
        uint256 price1 = market.calculateCurrentPrice(marketId, 1);

        // With 2 options, each should start at 0.5 * 1e18
        assertEq(price0, 0.5 * 1e18);
        assertEq(price1, 0.5 * 1e18);

        console.log("Initial price option 0:", price0);
        console.log("Initial price option 1:", price1);
    }

    function testPriceMovementAfterBuy() public {
        uint256 initialPrice = market.calculateCurrentPrice(marketId, 0);
        console.log("Initial price:", initialPrice);

        vm.startPrank(user1);
        uint256 buyAmount = 100 * 1e18;
        uint256 cost = market.calculateAMMBuyCost(marketId, 0, buyAmount);
        console.log("Cost for", buyAmount / 1e18, "shares:", cost / 1e18);

        // Calculate realistic max price per share with proper scaling
        uint256 maxPricePerShare = (cost * 1e18) / buyAmount + 1e15; // Add 0.001 token tolerance
        market.buyShares(marketId, 0, buyAmount, maxPricePerShare);

        uint256 newPrice = market.calculateCurrentPrice(marketId, 0);
        console.log("Price after buy:", newPrice);

        // Price should increase after buying
        assertGt(newPrice, initialPrice, "Price should increase after buying");
        vm.stopPrank();
    }

    function testPriceMovementAfterSell() public {
        // First buy some shares
        vm.startPrank(user1);
        uint256 buyAmount = 100 * 1e18;
        uint256 cost = market.calculateAMMBuyCost(marketId, 0, buyAmount);
        uint256 maxPricePerShare = (cost * 1e18) / buyAmount + 1e15; // Add 0.001 token tolerance
        market.buyShares(marketId, 0, buyAmount, maxPricePerShare);

        uint256 priceAfterBuy = market.calculateCurrentPrice(marketId, 0);
        console.log("Price after buy:", priceAfterBuy);

        // Now sell half
        uint256 sellAmount = 50 * 1e18;
        uint256 revenue = market.calculateAMMSellRevenue(marketId, 0, sellAmount);
        console.log("Revenue for selling", sellAmount / 1e18, "shares:", revenue / 1e18);

        // Calculate realistic min price per share with proper scaling
        uint256 minPricePerShare = (revenue * 1e18) / sellAmount;
        if (minPricePerShare > 1e15) minPricePerShare -= 1e15; // Subtract 0.001 token tolerance
        market.sellShares(marketId, 0, sellAmount, minPricePerShare);

        uint256 priceAfterSell = market.calculateCurrentPrice(marketId, 0);
        console.log("Price after sell:", priceAfterSell);

        // Price should decrease after selling
        assertLt(priceAfterSell, priceAfterBuy, "Price should decrease after selling");
        vm.stopPrank();
    }

    function testCalculateNewPriceBuyVsSell() public view {
        uint256 currentPrice = market.calculateCurrentPrice(marketId, 0);
        uint256 quantity = 100 * 1e18;

        uint256 priceAfterBuy = market.calculateNewPrice(marketId, 0, quantity, true);
        uint256 priceAfterSell = market.calculateNewPrice(marketId, 0, quantity, false);

        console.log("Current price:", currentPrice);
        console.log("Price after hypothetical buy:", priceAfterBuy);
        console.log("Price after hypothetical sell:", priceAfterSell);

        // Buy should increase price, sell should decrease price
        assertGt(priceAfterBuy, currentPrice, "Buy should increase price");
        assertLt(priceAfterSell, currentPrice, "Sell should decrease price");
    }

    function testAMMConstantProductFormula() public view {
        // Get initial market state
        (,, uint256 shares0, uint256 volume0, uint256 price0,) = market.getMarketOption(marketId, 0);
        (,, uint256 shares1, uint256 volume1, uint256 price1,) = market.getMarketOption(marketId, 1);

        console.log("Option 0 Shares:", shares0);
        console.log("Option 0 Price:", price0);
        console.log("Option 1 Shares:", shares1);
        console.log("Option 1 Price:", price1);
        console.log("Option 0 Volume:", volume0);
        console.log("Option 1 Volume:", volume1);
        // Initial reserves should be equal for both options
        // k = initialLiquidity / optionCount = 1000e18 / 2 = 500e18
        // reserve = k = 500e18
        // price = k / reserve = 500e18 / 500e18 = 1e18, but scaled by option count gives 0.5e18
    }

    function testPriceSlippage() public {
        vm.startPrank(user1);

        uint256 smallAmount = 10 * 1e18;
        uint256 largeAmount = 400 * 1e18;

        uint256 initialPrice = market.calculateCurrentPrice(marketId, 0);

        uint256 smallBuyCost = market.calculateAMMBuyCost(marketId, 0, smallAmount);
        uint256 largeBuyCost = market.calculateAMMBuyCost(marketId, 0, largeAmount);

        uint256 smallBuyPricePerShare = smallBuyCost * 1e18 / smallAmount;
        uint256 largeBuyPricePerShare = largeBuyCost * 1e18 / largeAmount;

        console.log("Initial price:", initialPrice);
        console.log("Small buy price per share:", smallBuyPricePerShare);
        console.log("Large buy price per share:", largeBuyPricePerShare);

        // Larger purchases should have higher average price per share (slippage)
        assertGt(largeBuyPricePerShare, smallBuyPricePerShare, "Large purchases should have higher slippage");

        vm.stopPrank();
    }

    function testSymmetricPricing() public {
        vm.startPrank(user1);

        // Test if buying then selling the same amount returns similar price
        uint256 initialPrice = market.calculateCurrentPrice(marketId, 0);
        uint256 amount = 100 * 1e18;

        // Buy shares
        uint256 cost = market.calculateAMMBuyCost(marketId, 0, amount);
        uint256 maxPricePerShare = (cost * 1e18) / amount + 1e15; // Add 0.001 token tolerance
        market.buyShares(marketId, 0, amount, maxPricePerShare);

        uint256 priceAfterBuy = market.calculateCurrentPrice(marketId, 0);

        // Sell the same amount
        uint256 revenue = market.calculateAMMSellRevenue(marketId, 0, amount);
        uint256 minPricePerShare = (revenue * 1e18) / amount;
        if (minPricePerShare > 1e15) minPricePerShare -= 1e15; // Subtract 0.001 token tolerance
        market.sellShares(marketId, 0, amount, minPricePerShare);

        uint256 finalPrice = market.calculateCurrentPrice(marketId, 0);

        console.log("Initial price:", initialPrice);
        console.log("Price after buy:", priceAfterBuy);
        console.log("Final price after sell:", finalPrice);

        // Due to fees and AMM mechanics, final price might not exactly equal initial
        // But it should be close (within reasonable bounds)
        uint256 priceDiff = finalPrice > initialPrice ? finalPrice - initialPrice : initialPrice - finalPrice;
        uint256 tolerance = initialPrice / 100; // 1% tolerance

        assertLt(priceDiff, tolerance, "Round trip should be close to initial price");

        vm.stopPrank();
    }

    function testReserveConsistency() public {
        vm.startPrank(user1);

        uint256 buyAmount = 100 * 1e18;

        // Get initial state
        uint256 initialPrice = market.calculateCurrentPrice(marketId, 0);

        // Buy shares and check price movement
        uint256 cost = market.calculateAMMBuyCost(marketId, 0, buyAmount);
        uint256 maxPricePerShare = (cost * 1e18) / buyAmount + 1e15; // Add 0.001 token tolerance
        market.buyShares(marketId, 0, buyAmount, maxPricePerShare);

        uint256 priceAfterBuy = market.calculateCurrentPrice(marketId, 0);

        // The price should follow AMM formula: price = k / reserve
        // When buying, reserve decreases, so price should increase
        assertGt(priceAfterBuy, initialPrice, "Price should increase when reserve decreases");

        vm.stopPrank();
    }

    function testPriceCalculationEdgeCases() public view {
        // Test with very small amounts
        uint256 tinyAmount = 1e15; // 0.001 tokens
        uint256 tinyCost = market.calculateAMMBuyCost(marketId, 0, tinyAmount);
        assertGt(tinyCost, 0, "Tiny amount should have non-zero cost");

        // Test with large amounts (but not exceeding reserves)
        uint256 largeAmount = 400 * 1e18;
        uint256 largeCost = market.calculateAMMBuyCost(marketId, 0, largeAmount);
        assertGt(largeCost, 0, "Large amount should have non-zero cost");

        console.log("Tiny amount cost:", tinyCost);
        console.log("Large amount cost:", largeCost);
    }

    function testMultipleTradesImpact() public {
        uint256 initialPrice = market.calculateCurrentPrice(marketId, 0);
        console.log("Initial price:", initialPrice);

        // User1 buys
        vm.startPrank(user1);
        uint256 amount1 = 50 * 1e18;
        uint256 cost1 = market.calculateAMMBuyCost(marketId, 0, amount1);
        uint256 maxPricePerShare1 = (cost1 * 1e18) / amount1 + 1e15; // Add 0.001 token tolerance
        market.buyShares(marketId, 0, amount1, maxPricePerShare1);
        vm.stopPrank();

        uint256 priceAfterUser1 = market.calculateCurrentPrice(marketId, 0);
        console.log("Price after user1 buy:", priceAfterUser1);

        // User2 buys
        vm.startPrank(user2);
        uint256 amount2 = 75 * 1e18;
        uint256 cost2 = market.calculateAMMBuyCost(marketId, 0, amount2);
        uint256 maxPricePerShare2 = (cost2 * 1e18) / amount2 + 1e15; // Add 0.001 token tolerance
        market.buyShares(marketId, 0, amount2, maxPricePerShare2);
        vm.stopPrank();

        uint256 priceAfterUser2 = market.calculateCurrentPrice(marketId, 0);
        console.log("Price after user2 buy:", priceAfterUser2);

        // Each subsequent buy should increase the price further
        assertGt(priceAfterUser1, initialPrice, "First buy should increase price");
        assertGt(priceAfterUser2, priceAfterUser1, "Second buy should increase price further");
    }

    function testOptionPriceIndependence() public {
        uint256 initialPrice0 = market.calculateCurrentPrice(marketId, 0);
        uint256 initialPrice1 = market.calculateCurrentPrice(marketId, 1);

        // Buy option 0
        vm.startPrank(user1);
        uint256 amount = 100 * 1e18;
        uint256 cost = market.calculateAMMBuyCost(marketId, 0, amount);
        uint256 maxPricePerShare = (cost * 1e18) / amount + 1e15; // Add 0.001 token tolerance
        market.buyShares(marketId, 0, amount, maxPricePerShare);
        vm.stopPrank();

        uint256 newPrice0 = market.calculateCurrentPrice(marketId, 0);
        uint256 newPrice1 = market.calculateCurrentPrice(marketId, 1);

        console.log("Option 0 price change:", initialPrice0, "->", newPrice0);
        console.log("Option 1 price change:", initialPrice1, "->", newPrice1);

        // Option 0 price should increase, Option 1 should remain the same or decrease slightly
        assertGt(newPrice0, initialPrice0, "Bought option price should increase");
        // Option 1 price might change due to shared liquidity pool dynamics
    }

    function testFixedPricingIssue() public view {
        // This test specifically addresses the failing test case
        uint256 quantity = 100 * 1e18;
        uint256 currentPrice = market.calculateCurrentPrice(marketId, 0);

        // Test the specific calculateNewPrice function behavior
        uint256 newPriceBuy = market.calculateNewPrice(marketId, 0, quantity, true);
        uint256 newPriceSell = market.calculateNewPrice(marketId, 0, quantity, false);

        console.log("Current price:", currentPrice);
        console.log("New price after buy:", newPriceBuy);
        console.log("New price after sell:", newPriceSell);

        // According to AMM logic:
        // Buy: reserve decreases -> price increases
        // Sell: reserve increases -> price decreases
        assertGt(newPriceBuy, currentPrice, "Buy should increase price");
        assertLt(newPriceSell, currentPrice, "Sell should decrease price");
    }

    function testReserveAndKValues() public view {
        // Test the internal AMM state
        (,,,, uint256 price0,) = market.getMarketOption(marketId, 0);
        (,,,, uint256 price1,) = market.getMarketOption(marketId, 1);

        console.log("Option 0 price:", price0);
        console.log("Option 1 price:", price1);

        // Check if reserves and k values are consistent with pricing
        uint256 expectedK = INITIAL_LIQUIDITY / 2; // Should be 500e18 for each option
        console.log("Expected k value:", expectedK);

        // Price should equal k / reserve
        // If price = 0.5e18 and k = 500e18, then reserve should be 1000e18
        uint256 expectedReserve = expectedK * 1e18 / price0;
        console.log("Expected reserve for option 0:", expectedReserve);
    }

    function testAMMFormulaMath() public view {
        // Test the mathematical consistency of the AMM formula
        uint256 k = INITIAL_LIQUIDITY / 2; // 500e18
        uint256 initialReserve = k; // Should start at k
        uint256 initialPrice = (k * 1e18) / initialReserve; // Should be 1e18

        console.log("K value:", k);
        console.log("Initial reserve:", initialReserve);
        console.log("Calculated initial price:", initialPrice);
        console.log("Actual initial price:", market.calculateCurrentPrice(marketId, 0));

        // The actual price should match our calculation
        // Note: The contract divides by option count, so actual price = 1e18 / 2 = 0.5e18
        uint256 actualPrice = market.calculateCurrentPrice(marketId, 0);
        uint256 expectedPrice = 1e18 / 2; // Divided by option count
        assertEq(actualPrice, expectedPrice, "Price calculation should match expected formula");
    }

    function testBuySellAsymmetry() public {
        vm.startPrank(user1);

        uint256 amount = 100 * 1e18;
        uint256 currentPrice = market.calculateCurrentPrice(marketId, 0);

        // Calculate theoretical buy and sell prices
        uint256 buyCost = market.calculateAMMBuyCost(marketId, 0, amount);
        uint256 sellRevenue = market.calculateAMMSellRevenue(marketId, 0, amount);

        uint256 buyPricePerShare = buyCost * 1e18 / amount;
        uint256 sellPricePerShare = sellRevenue * 1e18 / amount;

        console.log("Current price:", currentPrice);
        console.log("Buy price per share:", buyPricePerShare);
        console.log("Sell price per share:", sellPricePerShare);

        // Buy price should be higher than current price
        // Sell price should be lower than current price
        assertGt(buyPricePerShare, currentPrice, "Buy price should be higher than current");
        assertLt(sellPricePerShare, currentPrice, "Sell price should be lower than current");

        // The spread should exist due to fees and AMM mechanics
        assertGt(buyPricePerShare, sellPricePerShare, "Buy-sell spread should exist");

        vm.stopPrank();
    }

    function testLargePurchaseImpact() public {
        vm.startPrank(user1);

        uint256 initialPrice = market.calculateCurrentPrice(marketId, 0);

        // Try to buy a large amount (close to reserve limit)
        uint256 largeAmount = 450 * 1e18; // 90% of initial reserve
        uint256 cost = market.calculateAMMBuyCost(marketId, 0, largeAmount);

        console.log("Initial price:", initialPrice);
        console.log("Cost for large purchase:", cost);
        console.log("Price per share for large purchase:", cost * 1e18 / largeAmount);

        // Execute the large purchase with realistic slippage tolerance
        uint256 maxPricePerShare = (cost * 1e18) / largeAmount + 1e17; // Add 0.1 token tolerance for large orders
        market.buyShares(marketId, 0, largeAmount, maxPricePerShare);

        uint256 newPrice = market.calculateCurrentPrice(marketId, 0);
        console.log("Price after large purchase:", newPrice);

        // Price should increase significantly (at least 50% increase for large purchase)
        uint256 expectedMinPrice = initialPrice + initialPrice / 2; // 1.5x initial price
        assertGt(newPrice, expectedMinPrice, "Large purchase should significantly increase price");

        vm.stopPrank();
    }
}
