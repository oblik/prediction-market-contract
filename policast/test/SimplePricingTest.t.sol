// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PolicastMarketV3} from "../src/V3.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract PricingLogicTest is Test {
    PolicastMarketV3 public market;
    MockERC20 public bettingToken;
    address public owner = address(0x123);
    address public user1 = address(0x456);

    uint256 public constant INITIAL_LIQUIDITY = 1000 * 1e18;
    uint256 public marketId;

    function setUp() public {
        vm.startPrank(owner);
        bettingToken = new MockERC20("Betting Token", "BET", 18);
        market = new PolicastMarketV3(address(bettingToken));

        // Mint tokens to users
        bettingToken.mint(owner, 1000000 * 1e18);
        bettingToken.mint(user1, 1000000 * 1e18);

        // Approve market to spend tokens
        bettingToken.approve(address(market), type(uint256).max);

        // Grant validator role to owner
        market.grantMarketValidatorRole(owner);

        vm.stopPrank();

        vm.startPrank(user1);
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
        uint256 price0 = market.calculateCurrentPrice(marketId, 0);
        uint256 price1 = market.calculateCurrentPrice(marketId, 1);

        // With 2 options, each should start at 0.5 * 1e18
        assertEq(price0, 0.5 * 1e18, "Option 0 initial price should be 0.5");
        assertEq(price1, 0.5 * 1e18, "Option 1 initial price should be 0.5");
    }

    function testCalculateNewPriceBuy() public view {
        uint256 currentPrice = market.calculateCurrentPrice(marketId, 0);
        uint256 quantity = 100 * 1e18;

        uint256 newPriceBuy = market.calculateNewPrice(marketId, 0, quantity, true);

        // Buy should increase price
        assertGt(newPriceBuy, currentPrice, "Buy should increase price");
    }

    function testCalculateNewPriceSell() public view {
        uint256 currentPrice = market.calculateCurrentPrice(marketId, 0);
        uint256 quantity = 100 * 1e18;

        uint256 newPriceSell = market.calculateNewPrice(marketId, 0, quantity, false);

        // Sell should decrease price - THIS IS THE FAILING TEST
        assertLt(newPriceSell, currentPrice, "Sell should decrease price");
    }

    function testCalculateNewPriceBuyVsSell() public view {
        uint256 currentPrice = market.calculateCurrentPrice(marketId, 0);
        uint256 quantity = 100 * 1e18;

        uint256 priceAfterBuy = market.calculateNewPrice(marketId, 0, quantity, true);
        uint256 priceAfterSell = market.calculateNewPrice(marketId, 0, quantity, false);

        // Buy should increase price, sell should decrease price
        assertGt(priceAfterBuy, currentPrice, "Buy should increase price");
        assertLt(priceAfterSell, currentPrice, "Sell should decrease price");

        // Buy price should be higher than sell price
        assertGt(priceAfterBuy, priceAfterSell, "Buy price should be higher than sell price");
    }

    function testActualBuyBehavior() public {
        uint256 initialPrice = market.calculateCurrentPrice(marketId, 0);

        vm.startPrank(user1);
        uint256 buyAmount = 100 * 1e18;
        uint256 cost = market.calculateAMMBuyCost(marketId, 0, buyAmount);

        // Calculate average price per share including fees and scale properly
        uint256 avgPricePerShare = (cost * 1e18) / buyAmount;
        // Add 1% slippage tolerance
        uint256 maxPricePerShare = avgPricePerShare * 101 / 100;

        market.buyShares(marketId, 0, buyAmount, maxPricePerShare);

        uint256 newPrice = market.calculateCurrentPrice(marketId, 0);

        // Price should increase after buying
        assertGt(newPrice, initialPrice, "Price should increase after buying");
        vm.stopPrank();
    }

    function testActualSellBehavior() public {
        // First buy some shares
        vm.startPrank(user1);
        uint256 buyAmount = 100 * 1e18;
        uint256 cost = market.calculateAMMBuyCost(marketId, 0, buyAmount);
        // Calculate average price per share including fees and scale properly
        uint256 avgBuyPricePerShare = (cost * 1e18) / buyAmount;
        // Add 1% slippage tolerance
        uint256 maxPricePerShare = avgBuyPricePerShare * 101 / 100;

        market.buyShares(marketId, 0, buyAmount, maxPricePerShare);

        uint256 priceAfterBuy = market.calculateCurrentPrice(marketId, 0);

        // Now sell half
        uint256 sellAmount = 50 * 1e18;
        uint256 revenue = market.calculateAMMSellRevenue(marketId, 0, sellAmount);
        // Calculate average price per share for selling and scale properly
        uint256 avgSellPricePerShare = (revenue * 1e18) / sellAmount;
        // Subtract 1% slippage tolerance (allow for lower price)
        uint256 minPricePerShare = avgSellPricePerShare * 99 / 100;

        market.sellShares(marketId, 0, sellAmount, minPricePerShare);

        uint256 priceAfterSell = market.calculateCurrentPrice(marketId, 0);

        // Price should decrease after selling
        assertLt(priceAfterSell, priceAfterBuy, "Price should decrease after selling");
        vm.stopPrank();
    }

    function testAMMFormulaMath() public view {
        uint256 k = INITIAL_LIQUIDITY / 2; // 500e18
        uint256 initialReserve = k; // Should start at k
        uint256 calculatedPrice = (k * 1e18) / initialReserve; // Should be 1e18

        uint256 actualPrice = market.calculateCurrentPrice(marketId, 0);
        uint256 expectedPrice = 1e18 / 2; // Divided by option count

        assertEq(actualPrice, expectedPrice, "Price calculation should match expected formula");
        assertEq(calculatedPrice, 1e18, "K/reserve should equal 1e18");
    }

    function testBuySellAsymmetry() public view {
        uint256 amount = 100 * 1e18;
        uint256 currentPrice = market.calculateCurrentPrice(marketId, 0);

        uint256 buyCost = market.calculateAMMBuyCost(marketId, 0, amount);
        uint256 sellRevenue = market.calculateAMMSellRevenue(marketId, 0, amount);

        uint256 buyPricePerShare = buyCost * 1e18 / amount;
        uint256 sellPricePerShare = sellRevenue * 1e18 / amount;

        // Buy price should be higher than current price
        assertGt(buyPricePerShare, currentPrice, "Buy price should be higher than current");

        // Sell price should be lower than current price
        assertLt(sellPricePerShare, currentPrice, "Sell price should be lower than current");

        // The spread should exist
        assertGt(buyPricePerShare, sellPricePerShare, "Buy-sell spread should exist");
    }

    function testPriceSlippage() public view {
        uint256 smallAmount = 10 * 1e18;
        uint256 largeAmount = 400 * 1e18;

        uint256 smallBuyCost = market.calculateAMMBuyCost(marketId, 0, smallAmount);
        uint256 largeBuyCost = market.calculateAMMBuyCost(marketId, 0, largeAmount);

        uint256 smallBuyPricePerShare = smallBuyCost * 1e18 / smallAmount;
        uint256 largeBuyPricePerShare = largeBuyCost * 1e18 / largeAmount;

        // Larger purchases should have higher average price per share (slippage)
        assertGt(largeBuyPricePerShare, smallBuyPricePerShare, "Large purchases should have higher slippage");
    }

    function testReserveConsistency() public {
        vm.startPrank(user1);

        uint256 buyAmount = 100 * 1e18;
        uint256 initialPrice = market.calculateCurrentPrice(marketId, 0);

        uint256 cost = market.calculateAMMBuyCost(marketId, 0, buyAmount);
        // Calculate average price per share including fees and scale properly
        uint256 avgPricePerShare = (cost * 1e18) / buyAmount;
        // Add 1% slippage tolerance
        uint256 maxPricePerShare = avgPricePerShare * 101 / 100;

        market.buyShares(marketId, 0, buyAmount, maxPricePerShare);

        uint256 priceAfterBuy = market.calculateCurrentPrice(marketId, 0);

        // When buying, reserve decreases, so price should increase
        assertGt(priceAfterBuy, initialPrice, "Price should increase when reserve decreases");

        vm.stopPrank();
    }
}
