// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/V3.sol";
import "./mocks/MockERC20.sol";

contract PayoutTest is Test {
    PolicastMarketV3 public market;
    MockERC20 public token;

    address public owner = address(0x123);
    address public user1 = address(0x456);
    address public user2 = address(0x789);
    address public user3 = address(0xabc);
    address public creator = address(0x111);
    address public resolver = address(0x222);

    uint256 public testMarketId;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy contracts
        token = new MockERC20("Test Token", "TEST", 18);
        market = new PolicastMarketV3(address(token));

        // Mint tokens to all users
        token.mint(owner, 1000000 * 1e18);
        token.mint(user1, 100000 * 1e18);
        token.mint(user2, 100000 * 1e18);
        token.mint(user3, 100000 * 1e18);
        token.mint(creator, 100000 * 1e18);
        token.mint(resolver, 100000 * 1e18);

        // Grant roles
        market.grantQuestionCreatorRole(creator);
        market.grantQuestionResolveRole(resolver);

        vm.stopPrank();

        // Create a test market
        vm.startPrank(creator);
        token.approve(address(market), 10000 * 1e18);

        string[] memory optionNames = new string[](3);
        optionNames[0] = "Yes";
        optionNames[1] = "No";
        optionNames[2] = "Maybe";

        string[] memory optionDescriptions = new string[](3);
        optionDescriptions[0] = "Option Yes";
        optionDescriptions[1] = "Option No";
        optionDescriptions[2] = "Option Maybe";

        testMarketId = market.createMarket(
            "Test Market for Payouts",
            "Testing payout functions",
            optionNames,
            optionDescriptions,
            1 days,
            PolicastMarketV3.MarketCategory.OTHER,
            PolicastMarketV3.MarketType.PAID,
            1000 * 1e18
        );

        vm.stopPrank();

        // Validate market
        vm.prank(owner);
        market.validateMarket(testMarketId);
    }

    function testIndividualClaimWinnings() public {
        // Setup: Users buy shares
        vm.startPrank(user1);
        token.approve(address(market), 10000 * 1e18);
        uint256 cost1 = market.calculateAMMBuyCost(testMarketId, 0, 100 * 1e18);
        market.buyShares(testMarketId, 0, 100 * 1e18, cost1 * 2);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(market), 10000 * 1e18);
        uint256 cost2 = market.calculateAMMBuyCost(testMarketId, 1, 50 * 1e18);
        market.buyShares(testMarketId, 1, 50 * 1e18, cost2 * 2);
        vm.stopPrank();

        // Resolve market with option 0 as winner
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(resolver);
        market.resolveMarket(testMarketId, 0);

        // User1 claims winnings (should succeed)
        vm.startPrank(user1);
        uint256 balanceBefore = token.balanceOf(user1);
        market.claimWinnings(testMarketId);
        uint256 balanceAfter = token.balanceOf(user1);
        assertGt(balanceAfter, balanceBefore);
        vm.stopPrank();

        // User2 tries to claim (should fail - they didn't win)
        vm.startPrank(user2);
        vm.expectRevert(PolicastMarketV3.NoWinningShares.selector);
        market.claimWinnings(testMarketId);
        vm.stopPrank();

        // User1 tries to claim again (should fail - already claimed)
        vm.startPrank(user1);
        vm.expectRevert(PolicastMarketV3.AlreadyClaimed.selector);
        market.claimWinnings(testMarketId);
        vm.stopPrank();
    }

    function testBatchDistributeWinnings() public {
        // Setup: Multiple users buy shares
        address[] memory buyers = new address[](3);
        buyers[0] = user1;
        buyers[1] = user2;
        buyers[2] = user3;

        for (uint256 i = 0; i < buyers.length; i++) {
            vm.startPrank(buyers[i]);
            token.approve(address(market), 10000 * 1e18);
            uint256 buyCost = market.calculateAMMBuyCost(testMarketId, 0, 50 * 1e18);
            market.buyShares(testMarketId, 0, 50 * 1e18, buyCost * 2);
            vm.stopPrank();
        }

        // Resolve market
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(resolver);
        market.resolveMarket(testMarketId, 0);

        // Get eligible winners before batch distribution
        (address[] memory eligible, uint256[] memory amounts) = market.getEligibleWinners(testMarketId, buyers);
        assertEq(eligible.length, 3);
        assertGt(amounts[0], 0);

        // Record balances before batch distribution
        uint256[] memory balancesBefore = new uint256[](3);
        for (uint256 i = 0; i < buyers.length; i++) {
            balancesBefore[i] = token.balanceOf(buyers[i]);
        }

        // Batch distribute winnings
        vm.prank(owner);
        market.batchDistributeWinnings(testMarketId, buyers);

        // Check balances after distribution
        for (uint256 i = 0; i < buyers.length; i++) {
            uint256 balanceAfter = token.balanceOf(buyers[i]);
            assertGt(balanceAfter, balancesBefore[i]);
        }

        // Verify users are marked as claimed
        for (uint256 i = 0; i < buyers.length; i++) {
            assertTrue(market.hasUserClaimedWinnings(testMarketId, buyers[i]));
        }
    }

    function testGetUserWinnings() public {
        // User buys shares
        vm.startPrank(user1);
        token.approve(address(market), 10000 * 1e18);
        uint256 cost = market.calculateAMMBuyCost(testMarketId, 0, 100 * 1e18);
        market.buyShares(testMarketId, 0, 100 * 1e18, cost * 2);
        vm.stopPrank();

        // Before resolution - should return false
        (bool hasWinnings, uint256 amount) = market.getUserWinnings(testMarketId, user1);
        assertFalse(hasWinnings);
        assertEq(amount, 0);

        // Resolve market
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(resolver);
        market.resolveMarket(testMarketId, 0);

        // After resolution - should return true with amount
        (hasWinnings, amount) = market.getUserWinnings(testMarketId, user1);
        assertTrue(hasWinnings);
        assertGt(amount, 0);

        // After claiming - should return false
        vm.prank(user1);
        market.claimWinnings(testMarketId);

        (hasWinnings, amount) = market.getUserWinnings(testMarketId, user1);
        assertFalse(hasWinnings);
        assertEq(amount, 0);
    }

    function testGetEligibleWinners() public {
        // Setup multiple users with different positions
        address[] memory testUsers = new address[](4);
        testUsers[0] = user1; // Will buy winning option
        testUsers[1] = user2; // Will buy losing option
        testUsers[2] = user3; // Will buy winning option
        // testUsers[3] not used

        // User1 and User3 buy winning option
        for (uint256 i = 0; i < 3; i += 2) {
            vm.startPrank(testUsers[i]);
            token.approve(address(market), 10000 * 1e18);
            uint256 cost = market.calculateAMMBuyCost(testMarketId, 0, 50 * 1e18);
            market.buyShares(testMarketId, 0, 50 * 1e18, cost * 2);
            vm.stopPrank();
        }

        // User2 buys losing option
        vm.startPrank(user2);
        token.approve(address(market), 10000 * 1e18);
        uint256 sellCost = market.calculateAMMBuyCost(testMarketId, 1, 50 * 1e18);
        market.buyShares(testMarketId, 1, 50 * 1e18, sellCost * 2);
        vm.stopPrank();

        // Before resolution - should revert
        vm.expectRevert(PolicastMarketV3.MarketNotReady.selector);
        market.getEligibleWinners(testMarketId, testUsers);

        // Resolve market
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(resolver);
        market.resolveMarket(testMarketId, 0);

        // Get eligible winners
        (address[] memory eligible, uint256[] memory amounts) = market.getEligibleWinners(testMarketId, testUsers);

        // Should have 2 eligible winners (user1 and user3)
        assertEq(eligible.length, 2);
        assertEq(amounts.length, 2);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);

        // Check that user2 is not in eligible list
        bool user2Found = false;
        for (uint256 i = 0; i < eligible.length; i++) {
            if (eligible[i] == user2) {
                user2Found = true;
                break;
            }
        }
        assertFalse(user2Found);
    }

    function testPostResolutionActivities() public {
        // Setup: User buys shares
        vm.startPrank(user1);
        token.approve(address(market), 10000 * 1e18);
        uint256 cost = market.calculateAMMBuyCost(testMarketId, 0, 100 * 1e18);
        market.buyShares(testMarketId, 0, 100 * 1e18, cost * 2);
        vm.stopPrank();

        // Resolve market
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(resolver);
        market.resolveMarket(testMarketId, 0);

        // Test: Cannot buy shares after resolution
        vm.startPrank(user2);
        token.approve(address(market), 10000 * 1e18);
        vm.expectRevert(PolicastMarketV3.MarketResolvedAlready.selector);
        market.buyShares(testMarketId, 0, 50 * 1e18, 1000 * 1e18);
        vm.stopPrank();

        // Test: Cannot sell shares after resolution
        vm.startPrank(user1);
        vm.expectRevert(PolicastMarketV3.MarketResolvedAlready.selector);
        market.sellShares(testMarketId, 0, 50 * 1e18, 0);
        vm.stopPrank();

        // Test: Cannot add liquidity after resolution
        vm.startPrank(user2);
        vm.expectRevert(PolicastMarketV3.MarketResolvedAlready.selector);
        market.addAMMLiquidity(testMarketId, 100 * 1e18);
        vm.stopPrank();

        // Test: Cannot swap after resolution
        vm.startPrank(user1);
        vm.expectRevert(PolicastMarketV3.MarketResolvedAlready.selector);
        market.ammSwap(testMarketId, 0, 1, 10 * 1e18, 0);
        vm.stopPrank();

        // Test: Can still claim winnings
        // First check user shares
        uint256[] memory userShares = market.getUserShares(testMarketId, user1);
        (, , , , , , , , , uint256 winningOptionId, ) = market.getMarketInfo(testMarketId);
        console.log("User shares - Option 0:", userShares[0]);
        console.log("User shares - Option 1:", userShares[1]);
        console.log("User shares - Option 2:", userShares[2]);
        console.log("Winning option ID:", winningOptionId);
        
        // Check total shares for winning option
        (, , uint256 totalShares, , , ) = market.getMarketOption(testMarketId, winningOptionId);
        console.log("Total shares for winning option:", totalShares);
        
        // Check if user has already claimed
        bool hasClaimed = market.hasUserClaimedWinnings(testMarketId, user1);
        console.log("User has already claimed:", hasClaimed);
        
        // Try to check user winnings directly
        (bool hasWinnings, uint256 winningsAmount) = market.getUserWinnings(testMarketId, user1);
        console.log("User has winnings:", hasWinnings);
        console.log("Winnings amount:", winningsAmount);
        
        vm.startPrank(user1);
        market.claimWinnings(testMarketId);
        vm.stopPrank();
        assertTrue(market.hasUserClaimedWinnings(testMarketId, user1));
    }

    function testBatchDistributionWithEmptyList() public {
        // Resolve market first
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(resolver);
        market.resolveMarket(testMarketId, 0);

        // Try batch distribution with empty list
        address[] memory emptyList = new address[](0);
        vm.prank(owner);
        vm.expectRevert(PolicastMarketV3.EmptyBatchList.selector);
        market.batchDistributeWinnings(testMarketId, emptyList);
    }

    function testBatchDistributionBeforeResolution() public {
        // Try batch distribution before market is resolved
        address[] memory users = new address[](1);
        users[0] = user1;

        vm.prank(owner);
        vm.expectRevert(PolicastMarketV3.MarketNotReady.selector);
        market.batchDistributeWinnings(testMarketId, users);
    }

    function testBatchDistributionPartialSuccess() public {
        // Setup: user1 buys winning shares, user2 buys losing shares
        vm.startPrank(user1);
        token.approve(address(market), 10000 * 1e18);
        uint256 cost1 = market.calculateAMMBuyCost(testMarketId, 0, 100 * 1e18);
        market.buyShares(testMarketId, 0, 100 * 1e18, cost1 * 2);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(market), 10000 * 1e18);
        uint256 cost2 = market.calculateAMMBuyCost(testMarketId, 1, 50 * 1e18);
        market.buyShares(testMarketId, 1, 50 * 1e18, cost2 * 2);
        vm.stopPrank();

        // Resolve market
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(resolver);
        market.resolveMarket(testMarketId, 0);

        // Batch distribute to both users (user2 should be skipped)
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        uint256 balanceBefore1 = token.balanceOf(user1);
        uint256 balanceBefore2 = token.balanceOf(user2);

        vm.prank(owner);
        market.batchDistributeWinnings(testMarketId, users);

        uint256 balanceAfter1 = token.balanceOf(user1);
        uint256 balanceAfter2 = token.balanceOf(user2);

        // user1 should have received winnings
        assertGt(balanceAfter1, balanceBefore1);
        // user2 should not have received anything
        assertEq(balanceAfter2, balanceBefore2);

        // Only user1 should be marked as claimed
        assertTrue(market.hasUserClaimedWinnings(testMarketId, user1));
        assertFalse(market.hasUserClaimedWinnings(testMarketId, user2));
    }

    function testClaimWinningsAfterDispute() public {
        // Setup: User buys shares
        vm.startPrank(user1);
        token.approve(address(market), 10000 * 1e18);
        uint256 cost = market.calculateAMMBuyCost(testMarketId, 0, 100 * 1e18);
        market.buyShares(testMarketId, 0, 100 * 1e18, cost * 2);
        vm.stopPrank();

        // Resolve market
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(resolver);
        market.resolveMarket(testMarketId, 0);

        // Dispute the market
        vm.prank(user2);
        market.disputeMarket(testMarketId, "I disagree with the outcome");

        // Try to claim winnings after dispute (should fail)
        vm.prank(user1);
        vm.expectRevert(PolicastMarketV3.MarketNotReady.selector);
        market.claimWinnings(testMarketId);

        // Batch distribution should also fail
        address[] memory users = new address[](1);
        users[0] = user1;

        vm.prank(owner);
        vm.expectRevert(PolicastMarketV3.MarketNotReady.selector);
        market.batchDistributeWinnings(testMarketId, users);
    }
}
