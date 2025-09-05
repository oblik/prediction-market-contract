// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/Console.sol";
import {PolicastMarketV3} from "../src/V3.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract PriceMovementDemo is Test {
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
            "Will the price move correctly?",
            "Testing price movements",
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

    function testPriceMovementDemo() public {
        console.log("=== PRICE MOVEMENT DEMONSTRATION ===");
        console.log("");

        // Show initial state
        uint256 initialPrice0 = market.calculateCurrentPrice(marketId, 0);
        uint256 initialPrice1 = market.calculateCurrentPrice(marketId, 1);
        console.log("INITIAL STATE:");
        console.log("Option 0 (Yes) price:", initialPrice0);
        console.log("Option 1 (No) price: ", initialPrice1);
        console.log("");

        // User1 buys 100 shares of Option 0
        vm.startPrank(user1);
        uint256 buyAmount1 = 100 * 1e18;
        uint256 cost1 = market.calculateAMMBuyCost(marketId, 0, buyAmount1);
        uint256 avgPrice1 = cost1 * 1e18 / buyAmount1;

        console.log("USER1 BUYS 100 shares of Option 0:");
        console.log("Total cost:      ", cost1);
        console.log("Average price:   ", avgPrice1);

        market.buyShares(marketId, 0, buyAmount1, avgPrice1 + 1e15); // Small slippage

        uint256 priceAfterBuy1_0 = market.calculateCurrentPrice(marketId, 0);
        uint256 priceAfterBuy1_1 = market.calculateCurrentPrice(marketId, 1);
        console.log("AFTER USER1 BUY:");
        console.log("Option 0 price:  ", priceAfterBuy1_0);
        console.log("Option 1 price:  ", priceAfterBuy1_1);
        console.log("Price increase:  ", priceAfterBuy1_0 - initialPrice0);
        console.log("");
        vm.stopPrank();

        // User2 buys 200 shares of Option 0 (larger purchase)
        vm.startPrank(user2);
        uint256 buyAmount2 = 200 * 1e18;
        uint256 cost2 = market.calculateAMMBuyCost(marketId, 0, buyAmount2);
        uint256 avgPrice2 = cost2 * 1e18 / buyAmount2;

        console.log("USER2 BUYS 200 shares of Option 0:");
        console.log("Total cost:      ", cost2);
        console.log("Average price:   ", avgPrice2);

        market.buyShares(marketId, 0, buyAmount2, avgPrice2 + 1e15);

        uint256 priceAfterBuy2_0 = market.calculateCurrentPrice(marketId, 0);
        uint256 priceAfterBuy2_1 = market.calculateCurrentPrice(marketId, 1);
        console.log("AFTER USER2 BUY:");
        console.log("Option 0 price:  ", priceAfterBuy2_0);
        console.log("Option 1 price:  ", priceAfterBuy2_1);
        console.log("Price increase:  ", priceAfterBuy2_0 - priceAfterBuy1_0);
        console.log("");
        vm.stopPrank();

        // User1 sells 50 shares
        vm.startPrank(user1);
        uint256 sellAmount = 50 * 1e18;
        uint256 revenue = market.calculateAMMSellRevenue(marketId, 0, sellAmount);
        uint256 sellPrice = revenue * 1e18 / sellAmount;

        console.log("USER1 SELLS 50 shares of Option 0:");
        console.log("Total revenue:   ", revenue);
        console.log("Average price:   ", sellPrice);

        market.sellShares(marketId, 0, sellAmount, sellPrice - 1e15); // Small slippage

        uint256 priceAfterSell_0 = market.calculateCurrentPrice(marketId, 0);
        uint256 priceAfterSell_1 = market.calculateCurrentPrice(marketId, 1);
        console.log("AFTER USER1 SELL:");
        console.log("Option 0 price:  ", priceAfterSell_0);
        console.log("Option 1 price:  ", priceAfterSell_1);
        console.log("Price decrease:  ", priceAfterBuy2_0 - priceAfterSell_0);
        console.log("");
        vm.stopPrank();

        // Show user balances
        uint256[] memory user1Shares = market.getUserShares(marketId, user1);
        uint256[] memory user2Shares = market.getUserShares(marketId, user2);

        console.log("FINAL USER POSITIONS:");
        console.log("User1 Option 0:  ", user1Shares[0]);
        console.log("User1 Option 1:  ", user1Shares[1]);
        console.log("User2 Option 0:  ", user2Shares[0]);
        console.log("User2 Option 1:  ", user2Shares[1]);
        console.log("");

        // Show price progression summary
        console.log("PRICE PROGRESSION SUMMARY:");
        console.log("Initial:         ", initialPrice0);
        console.log("After 100 buy:   ", priceAfterBuy1_0);
        console.log("After 200 buy:   ", priceAfterBuy2_0);
        console.log("After 50 sell:   ", priceAfterSell_0);
        console.log("");

        // Test slippage for different amounts
        console.log("SLIPPAGE ANALYSIS:");
        uint256 small = 10 * 1e18;
        uint256 medium = 100 * 1e18;
        uint256 large = 500 * 1e18;

        uint256 smallCost = market.calculateAMMBuyCost(marketId, 0, small);
        uint256 mediumCost = market.calculateAMMBuyCost(marketId, 0, medium);
        uint256 largeCost = market.calculateAMMBuyCost(marketId, 0, large);

        console.log("10 shares cost:  ", smallCost * 1e18 / small);
        console.log("100 shares cost: ", mediumCost * 1e18 / medium);
        console.log("500 shares cost: ", largeCost * 1e18 / large);

        // Verify the fundamental AMM property: buys increase price, sells decrease price
        assertTrue(priceAfterBuy1_0 > initialPrice0, "First buy should increase price");
        assertTrue(priceAfterBuy2_0 > priceAfterBuy1_0, "Second buy should increase price further");
        assertTrue(priceAfterSell_0 < priceAfterBuy2_0, "Sell should decrease price");

        // Verify slippage: larger amounts should have higher average prices
        assertTrue(
            mediumCost * 1e18 / medium > smallCost * 1e18 / small, "Medium purchase should have higher avg price"
        );
        assertTrue(
            largeCost * 1e18 / large > mediumCost * 1e18 / medium, "Large purchase should have highest avg price"
        );
    }

    function testDetailedPriceCalculations() public view {
        console.log("=== DETAILED PRICE CALCULATIONS ===");
        console.log("");

        uint256 currentPrice = market.calculateCurrentPrice(marketId, 0);
        console.log("Current price: ", currentPrice);

        // Test different buy amounts and their impact
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 50 * 1e18;
        amounts[1] = 100 * 1e18;
        amounts[2] = 200 * 1e18;
        amounts[3] = 300 * 1e18;
        amounts[4] = 400 * 1e18;

        console.log("BUY PRICE ANALYSIS:");
        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 cost = market.calculateAMMBuyCost(marketId, 0, amounts[i]);
            uint256 avgPrice = cost * 1e18 / amounts[i];
            uint256 newPrice = market.calculateNewPrice(marketId, 0, amounts[i], true);

            console.log("Amount:", amounts[i] / 1e18);
            console.log("  Avg price:", avgPrice);
            console.log("  New price:", newPrice);
            console.log("  Premium:  ", avgPrice > currentPrice ? avgPrice - currentPrice : 0);
        }

        console.log("");
        console.log("SELL PRICE ANALYSIS:");
        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 revenue = market.calculateAMMSellRevenue(marketId, 0, amounts[i]);
            uint256 avgPrice = revenue * 1e18 / amounts[i];
            uint256 newPrice = market.calculateNewPrice(marketId, 0, amounts[i], false);

            console.log("Amount:", amounts[i] / 1e18);
            console.log("  Avg price:", avgPrice);
            console.log("  New price:", newPrice);
            console.log("  Discount: ", currentPrice > avgPrice ? currentPrice - avgPrice : 0);
        }
    }

    function testCrossOptionTrading() public {
        console.log("=== CROSS-OPTION TRADING ===");
        console.log("");

        uint256 price0_initial = market.calculateCurrentPrice(marketId, 0);
        uint256 price1_initial = market.calculateCurrentPrice(marketId, 1);
        console.log("Initial Option 0:", price0_initial);
        console.log("Initial Option 1:", price1_initial);
        console.log("");

        // Buy Option 0, see effect on Option 1
        vm.startPrank(user1);
        uint256 buyAmount = 200 * 1e18;
        uint256 cost = market.calculateAMMBuyCost(marketId, 0, buyAmount);
        market.buyShares(marketId, 0, buyAmount, cost * 1e18 / buyAmount + 1e15);

        uint256 price0_after = market.calculateCurrentPrice(marketId, 0);
        uint256 price1_after = market.calculateCurrentPrice(marketId, 1);
        console.log("After buying 200 Option 0:");
        console.log("Option 0 price: ", price0_after);
        console.log("Option 1 price: ", price1_after);
        console.log("Option 0 change:", price0_after > price0_initial ? price0_after - price0_initial : 0);
        console.log("Option 1 change:", price1_initial > price1_after ? price1_initial - price1_after : 0);
        console.log("");

        // Now buy some Option 1
        uint256 cost1 = market.calculateAMMBuyCost(marketId, 1, buyAmount);
        market.buyShares(marketId, 1, buyAmount, cost1 * 1e18 / buyAmount + 1e15);

        uint256 price0_final = market.calculateCurrentPrice(marketId, 0);
        uint256 price1_final = market.calculateCurrentPrice(marketId, 1);
        console.log("After buying 200 Option 1:");
        console.log("Option 0 price: ", price0_final);
        console.log("Option 1 price: ", price1_final);

        vm.stopPrank();

        // Verify both options moved up from their initial prices
        assertTrue(price0_final > price0_initial, "Option 0 should be higher than initial");
        assertTrue(price1_final > price1_initial, "Option 1 should be higher than initial");
    }
}
