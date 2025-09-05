// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PolicastMarketV3} from "../src/V3.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract MarketCreationTest is Test {
    PolicastMarketV3 public market;
    MockERC20 public bettingToken;
    address public owner = address(0x123);
    address public user1 = address(0x456);
    address public user2 = address(0x789);

    uint256 public constant INITIAL_LIQUIDITY = 1000 * 1e18;
    uint256 public constant DEFAULT_LIQUIDITY = 1000 * 1e18;

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

        vm.stopPrank();

        vm.startPrank(user1);
        bettingToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        bettingToken.approve(address(market), type(uint256).max);
        vm.stopPrank();
    }

    function testCreateMarketSuccess() public {
        vm.startPrank(owner);

        string[] memory optionNames = new string[](2);
        optionNames[0] = "Yes";
        optionNames[1] = "No";

        string[] memory optionDescriptions = new string[](2);
        optionDescriptions[0] = "Option Yes";
        optionDescriptions[1] = "Option No";

        uint256 marketId = market.createMarket(
            "Will it rain tomorrow?",
            "Weather prediction market",
            optionNames,
            optionDescriptions,
            1 days,
            PolicastMarketV3.MarketCategory.WEATHER,
            PolicastMarketV3.MarketType.PAID,
            INITIAL_LIQUIDITY
        );

        // Verify market creation
        assertEq(market.marketCount(), 1);
        assertEq(marketId, 0);

        // Verify market info
        (
            string memory question,
            string memory description,
            uint256 endTime,
            PolicastMarketV3.MarketCategory category,
            uint256 optionCount,
            bool resolved,
            bool disputed,
            ,
            bool invalidated,
            uint256 winningOptionId,
            address creator
        ) = market.getMarketInfo(marketId);

        assertEq(question, "Will it rain tomorrow?");
        assertEq(description, "Weather prediction market");
        assertEq(endTime, block.timestamp + 1 days);
        assertEq(uint256(category), uint256(PolicastMarketV3.MarketCategory.WEATHER));
        assertEq(optionCount, 2);
        assertFalse(resolved);
        assertFalse(disputed);
        assertFalse(invalidated);
        assertEq(winningOptionId, 0);
        assertEq(creator, owner);

        // Verify options
        (string memory name1, string memory desc1, uint256 shares1, uint256 volume1, uint256 price1, bool active1) =
            market.getMarketOption(marketId, 0);
        assertEq(name1, "Yes");
        assertEq(desc1, "Option Yes");
        assertEq(shares1, 0);
        assertEq(volume1, 0);
        assertEq(price1, 5e17); // 0.5e18
        assertTrue(active1);

        (string memory name2, string memory desc2, uint256 shares2, uint256 volume2, uint256 price2, bool active2) =
            market.getMarketOption(marketId, 1);
        assertEq(name2, "No");
        assertEq(desc2, "Option No");
        assertEq(shares2, 0);
        assertEq(volume2, 0);
        assertEq(price2, 5e17); // 0.5e18
        assertTrue(active2);

        vm.stopPrank();
    }

    function testCreateMarketWithDefaultLiquidity() public {
        vm.startPrank(owner);

        string[] memory optionNames = new string[](3);
        optionNames[0] = "Option A";
        optionNames[1] = "Option B";
        optionNames[2] = "Option C";

        string[] memory optionDescriptions = new string[](3);
        optionDescriptions[0] = "Description A";
        optionDescriptions[1] = "Description B";
        optionDescriptions[2] = "Description C";

        uint256 initialLiquidity = 1000 * 1e18; // Minimum required liquidity

        uint256 marketId = market.createMarket(
            "Default liquidity market",
            "Test market with default liquidity",
            optionNames,
            optionDescriptions,
            2 days,
            PolicastMarketV3.MarketCategory.TECHNOLOGY,
            PolicastMarketV3.MarketType.PAID,
            initialLiquidity
        );

        assertEq(market.marketCount(), 1);
        assertEq(marketId, 0);

        vm.stopPrank();
    }

    function testCreateFreeMarketSuccess() public {
        vm.startPrank(owner);

        string[] memory optionNames = new string[](2);
        optionNames[0] = "Win";
        optionNames[1] = "Lose";

        string[] memory optionDescriptions = new string[](2);
        optionDescriptions[0] = "Winning option";
        optionDescriptions[1] = "Losing option";

        uint256 maxFreeParticipants = 100;
        uint256 tokensPerParticipant = 10 * 1e18;
        uint256 initialLiquidity = 500 * 1e18;

        uint256 marketId = market.createFreeMarket(
            "Free entry sports market",
            "Test free market",
            optionNames,
            optionDescriptions,
            3 days,
            PolicastMarketV3.MarketCategory.SPORTS,
            maxFreeParticipants,
            tokensPerParticipant,
            initialLiquidity
        );

        assertEq(market.marketCount(), 1);
        assertEq(marketId, 0);

        // Verify free market config
        (
            uint256 maxFree,
            uint256 tokensPer,
            uint256 currentFree,
            uint256 totalPrizePool,
            uint256 remainingPrizePool,
            bool isActive
        ) = market.getFreeMarketInfo(marketId);

        assertEq(maxFree, maxFreeParticipants);
        assertEq(tokensPer, tokensPerParticipant);
        assertEq(currentFree, 0);
        assertEq(totalPrizePool, maxFreeParticipants * tokensPerParticipant);
        assertEq(remainingPrizePool, totalPrizePool);
        assertTrue(isActive);

        vm.stopPrank();
    }

    function testCreateMarketUnauthorized() public {
        vm.startPrank(user1);

        string[] memory optionNames = new string[](2);
        optionNames[0] = "Yes";
        optionNames[1] = "No";

        string[] memory optionDescriptions = new string[](2);
        optionDescriptions[0] = "Option Yes";
        optionDescriptions[1] = "Option No";

        vm.expectRevert(PolicastMarketV3.NotAuthorized.selector);
        market.createMarket(
            "Unauthorized market",
            "Should fail",
            optionNames,
            optionDescriptions,
            1 days,
            PolicastMarketV3.MarketCategory.OTHER,
            PolicastMarketV3.MarketType.PAID,
            INITIAL_LIQUIDITY
        );

        vm.stopPrank();
    }

    function testCreateMarketInvalidDuration() public {
        vm.startPrank(owner);

        string[] memory optionNames = new string[](2);
        optionNames[0] = "Yes";
        optionNames[1] = "No";

        string[] memory optionDescriptions = new string[](2);
        optionDescriptions[0] = "Option Yes";
        optionDescriptions[1] = "Option No";

        // Test too short duration
        vm.expectRevert(PolicastMarketV3.BadDuration.selector);
        market.createMarket(
            "Too short",
            "Should fail",
            optionNames,
            optionDescriptions,
            1 hours - 1,
            PolicastMarketV3.MarketCategory.OTHER,
            PolicastMarketV3.MarketType.PAID,
            INITIAL_LIQUIDITY
        );

        // Test too long duration
        vm.expectRevert(PolicastMarketV3.BadDuration.selector);
        market.createMarket(
            "Too long",
            "Should fail",
            optionNames,
            optionDescriptions,
            366 days,
            PolicastMarketV3.MarketCategory.OTHER,
            PolicastMarketV3.MarketType.PAID,
            INITIAL_LIQUIDITY
        );

        vm.stopPrank();
    }

    function testCreateMarketEmptyQuestion() public {
        vm.startPrank(owner);

        string[] memory optionNames = new string[](2);
        optionNames[0] = "Yes";
        optionNames[1] = "No";

        string[] memory optionDescriptions = new string[](2);
        optionDescriptions[0] = "Option Yes";
        optionDescriptions[1] = "Option No";

        vm.expectRevert(PolicastMarketV3.EmptyQuestion.selector);
        market.createMarket(
            "",
            "Empty question",
            optionNames,
            optionDescriptions,
            1 days,
            PolicastMarketV3.MarketCategory.OTHER,
            PolicastMarketV3.MarketType.PAID,
            INITIAL_LIQUIDITY
        );

        vm.stopPrank();
    }

    function testCreateMarketBadOptionCount() public {
        vm.startPrank(owner);

        // Test too few options
        string[] memory optionNames1 = new string[](1);
        optionNames1[0] = "Only";

        string[] memory optionDescriptions1 = new string[](1);
        optionDescriptions1[0] = "Only option";

        vm.expectRevert(PolicastMarketV3.BadOptionCount.selector);
        market.createMarket(
            "Too few options",
            "Should fail",
            optionNames1,
            optionDescriptions1,
            1 days,
            PolicastMarketV3.MarketCategory.OTHER,
            PolicastMarketV3.MarketType.PAID,
            INITIAL_LIQUIDITY
        );

        // Test too many options
        string[] memory optionNames2 = new string[](11);
        string[] memory optionDescriptions2 = new string[](11);
        for (uint256 i = 0; i < 11; i++) {
            optionNames2[i] = string(abi.encodePacked("Option ", i));
            optionDescriptions2[i] = string(abi.encodePacked("Description ", i));
        }

        vm.expectRevert(PolicastMarketV3.BadOptionCount.selector);
        market.createMarket(
            "Too many options",
            "Should fail",
            optionNames2,
            optionDescriptions2,
            1 days,
            PolicastMarketV3.MarketCategory.OTHER,
            PolicastMarketV3.MarketType.PAID,
            INITIAL_LIQUIDITY
        );

        vm.stopPrank();
    }

    function testCreateMarketLengthMismatch() public {
        vm.startPrank(owner);

        string[] memory optionNames = new string[](2);
        optionNames[0] = "Yes";
        optionNames[1] = "No";

        string[] memory optionDescriptions = new string[](3); // Different length
        optionDescriptions[0] = "Option Yes";
        optionDescriptions[1] = "Option No";
        optionDescriptions[2] = "Extra";

        vm.expectRevert(PolicastMarketV3.LengthMismatch.selector);
        market.createMarket(
            "Length mismatch",
            "Should fail",
            optionNames,
            optionDescriptions,
            1 days,
            PolicastMarketV3.MarketCategory.OTHER,
            PolicastMarketV3.MarketType.PAID,
            INITIAL_LIQUIDITY
        );

        vm.stopPrank();
    }

    function testCreateMarketMinTokensRequired() public {
        vm.startPrank(owner);

        string[] memory optionNames = new string[](2);
        optionNames[0] = "Yes";
        optionNames[1] = "No";

        string[] memory optionDescriptions = new string[](2);
        optionDescriptions[0] = "Option Yes";
        optionDescriptions[1] = "Option No";

        vm.expectRevert(PolicastMarketV3.MinTokensRequired.selector);
        market.createMarket(
            "Insufficient liquidity",
            "Should fail",
            optionNames,
            optionDescriptions,
            1 days,
            PolicastMarketV3.MarketCategory.OTHER,
            PolicastMarketV3.MarketType.PAID,
            50 * 1e18 // Less than minimum 100 * 1e18
        );

        vm.stopPrank();
    }

    function testCreateMarketTransferFailed() public {
        vm.startPrank(owner);

        // Mock transferFrom to return false
        vm.mockCall(
            address(bettingToken),
            abi.encodeWithSelector(bettingToken.transferFrom.selector, owner, address(market), INITIAL_LIQUIDITY),
            abi.encode(false)
        );

        string[] memory optionNames = new string[](2);
        optionNames[0] = "Yes";
        optionNames[1] = "No";

        string[] memory optionDescriptions = new string[](2);
        optionDescriptions[0] = "Option Yes";
        optionDescriptions[1] = "Option No";

        vm.expectRevert(PolicastMarketV3.TransferFailed.selector);
        market.createMarket(
            "Transfer failed",
            "Should fail",
            optionNames,
            optionDescriptions,
            1 days,
            PolicastMarketV3.MarketCategory.OTHER,
            PolicastMarketV3.MarketType.PAID,
            INITIAL_LIQUIDITY
        );

        vm.stopPrank();
    }

    function testValidateMarketSuccess() public {
        // First create a market
        vm.startPrank(owner);

        string[] memory optionNames = new string[](2);
        optionNames[0] = "Yes";
        optionNames[1] = "No";

        string[] memory optionDescriptions = new string[](2);
        optionDescriptions[0] = "Option Yes";
        optionDescriptions[1] = "Option No";

        uint256 marketId = market.createMarket(
            "Validation test",
            "Test market validation",
            optionNames,
            optionDescriptions,
            1 days,
            PolicastMarketV3.MarketCategory.OTHER,
            PolicastMarketV3.MarketType.PAID,
            INITIAL_LIQUIDITY
        );

        // Grant validator role to user1
        market.grantMarketValidatorRole(user1);

        vm.stopPrank();

        // Validate market as validator
        vm.startPrank(user1);
        market.validateMarket(marketId);

        // Verify validation
        // Note: validated field is not exposed in getMarketInfo, so we test through behavior
        // Market should now allow trading since it's validated

        vm.stopPrank();
    }

    function testValidateMarketUnauthorized() public {
        // First create a market
        vm.startPrank(owner);

        string[] memory optionNames = new string[](2);
        optionNames[0] = "Yes";
        optionNames[1] = "No";

        string[] memory optionDescriptions = new string[](2);
        optionDescriptions[0] = "Option Yes";
        optionDescriptions[1] = "Option No";

        uint256 marketId = market.createMarket(
            "Unauthorized validation",
            "Should fail",
            optionNames,
            optionDescriptions,
            1 days,
            PolicastMarketV3.MarketCategory.OTHER,
            PolicastMarketV3.MarketType.PAID,
            INITIAL_LIQUIDITY
        );

        vm.stopPrank();

        // Try to validate as non-validator
        vm.startPrank(user1);
        vm.expectRevert(PolicastMarketV3.NotAuthorized.selector);
        market.validateMarket(marketId);

        vm.stopPrank();
    }

    function testValidateMarketAlreadyValidated() public {
        // First create and validate a market
        vm.startPrank(owner);

        string[] memory optionNames = new string[](2);
        optionNames[0] = "Yes";
        optionNames[1] = "No";

        string[] memory optionDescriptions = new string[](2);
        optionDescriptions[0] = "Option Yes";
        optionDescriptions[1] = "Option No";

        uint256 marketId = market.createMarket(
            "Double validation",
            "Should fail",
            optionNames,
            optionDescriptions,
            1 days,
            PolicastMarketV3.MarketCategory.OTHER,
            PolicastMarketV3.MarketType.PAID,
            INITIAL_LIQUIDITY
        );

        // Grant validator role to user1
        market.grantMarketValidatorRole(user1);

        vm.stopPrank();

        // Validate market
        vm.startPrank(user1);
        market.validateMarket(marketId);

        // Try to validate again
        vm.expectRevert(PolicastMarketV3.MarketAlreadyResolved.selector);
        market.validateMarket(marketId);

        vm.stopPrank();
    }

    function testInvalidateMarketSuccess() public {
        vm.startPrank(owner);

        string[] memory optionNames = new string[](2);
        optionNames[0] = "Yes";
        optionNames[1] = "No";

        string[] memory optionDescriptions = new string[](2);
        optionDescriptions[0] = "Option Yes";
        optionDescriptions[1] = "Option No";

        uint256 marketId = market.createMarket(
            "Test Market",
            "Test Description",
            optionNames,
            optionDescriptions,
            1 days,
            PolicastMarketV3.MarketCategory.OTHER,
            PolicastMarketV3.MarketType.PAID,
            INITIAL_LIQUIDITY
        );

        // Check initial balance
        uint256 initialBalance = bettingToken.balanceOf(owner);

        // Invalidate market
        market.invalidateMarket(marketId);

        // Check that liquidity was refunded
        uint256 finalBalance = bettingToken.balanceOf(owner);
        assertEq(finalBalance, initialBalance + INITIAL_LIQUIDITY);

        // Check market state
        (,,,,,,,, bool invalidated,,) = market.getMarketInfo(marketId);
        assertTrue(invalidated);

        vm.stopPrank();
    }

    function testInvalidateMarketUnauthorized() public {
        vm.startPrank(owner);

        string[] memory optionNames = new string[](2);
        optionNames[0] = "Yes";
        optionNames[1] = "No";

        string[] memory optionDescriptions = new string[](2);
        optionDescriptions[0] = "Option Yes";
        optionDescriptions[1] = "Option No";

        uint256 marketId = market.createMarket(
            "Test Market",
            "Test Description",
            optionNames,
            optionDescriptions,
            1 days,
            PolicastMarketV3.MarketCategory.OTHER,
            PolicastMarketV3.MarketType.PAID,
            INITIAL_LIQUIDITY
        );

        vm.stopPrank();

        // Try to invalidate without permission
        vm.startPrank(user1);
        vm.expectRevert(PolicastMarketV3.NotAuthorized.selector);
        market.invalidateMarket(marketId);
        vm.stopPrank();
    }

    function testInvalidateMarketAlreadyInvalidated() public {
        vm.startPrank(owner);

        string[] memory optionNames = new string[](2);
        optionNames[0] = "Yes";
        optionNames[1] = "No";

        string[] memory optionDescriptions = new string[](2);
        optionDescriptions[0] = "Option Yes";
        optionDescriptions[1] = "Option No";

        uint256 marketId = market.createMarket(
            "Test Market",
            "Test Description",
            optionNames,
            optionDescriptions,
            1 days,
            PolicastMarketV3.MarketCategory.OTHER,
            PolicastMarketV3.MarketType.PAID,
            INITIAL_LIQUIDITY
        );

        // Invalidate market
        market.invalidateMarket(marketId);

        // Try to invalidate again
        vm.expectRevert(PolicastMarketV3.MarketAlreadyInvalidated.selector);
        market.invalidateMarket(marketId);

        vm.stopPrank();
    }

    function testInvalidateMarketAlreadyValidated() public {
        vm.startPrank(owner);

        string[] memory optionNames = new string[](2);
        optionNames[0] = "Yes";
        optionNames[1] = "No";

        string[] memory optionDescriptions = new string[](2);
        optionDescriptions[0] = "Option Yes";
        optionDescriptions[1] = "Option No";

        uint256 marketId = market.createMarket(
            "Test Market",
            "Test Description",
            optionNames,
            optionDescriptions,
            1 days,
            PolicastMarketV3.MarketCategory.OTHER,
            PolicastMarketV3.MarketType.PAID,
            INITIAL_LIQUIDITY
        );

        // Validate market first
        market.validateMarket(marketId);

        // Try to invalidate validated market
        vm.expectRevert(PolicastMarketV3.MarketAlreadyResolved.selector);
        market.invalidateMarket(marketId);

        vm.stopPrank();
    }

    function testTradingOnInvalidatedMarket() public {
        vm.startPrank(owner);

        string[] memory optionNames = new string[](2);
        optionNames[0] = "Yes";
        optionNames[1] = "No";

        string[] memory optionDescriptions = new string[](2);
        optionDescriptions[0] = "Option Yes";
        optionDescriptions[1] = "Option No";

        uint256 marketId = market.createMarket(
            "Test Market",
            "Test Description",
            optionNames,
            optionDescriptions,
            1 days,
            PolicastMarketV3.MarketCategory.OTHER,
            PolicastMarketV3.MarketType.PAID,
            INITIAL_LIQUIDITY
        );

        // Invalidate market
        market.invalidateMarket(marketId);

        vm.stopPrank();

        // Try to buy shares on invalidated market
        vm.startPrank(user1);
        vm.expectRevert(PolicastMarketV3.MarketIsInvalidated.selector);
        market.buyShares(marketId, 0, 100 * 1e18, 2e18);
        vm.stopPrank();
    }
}
