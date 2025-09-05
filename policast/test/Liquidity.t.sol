// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/V3.sol";
import "./mocks/MockERC20.sol";

contract LiquidityTest is Test {
    PolicastMarketV3 public market;
    MockERC20 public token;

    address public owner = address(0x123);
    address public user1 = address(0x789);
    address public user2 = address(0xabc);
    address public user3 = address(0xdef);
    address public nonLP = address(0x999);

    uint256 public marketId;
    uint256 public freeMarketId;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy token and market contract
        token = new MockERC20("Test Token", "TEST", 18);
        market = new PolicastMarketV3(address(token));

        // Mint tokens to all users
        token.mint(owner, 1000000 * 1e18);
        token.mint(user1, 10000 * 1e18);
        token.mint(user2, 10000 * 1e18);
        token.mint(user3, 10000 * 1e18);
        token.mint(nonLP, 10000 * 1e18);

        // Approve market contract for all users
        token.approve(address(market), type(uint256).max);

        // Grant necessary roles
        market.grantMarketValidatorRole(owner);

        vm.stopPrank();

        // Other users approve market contract
        vm.startPrank(user1);
        token.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user3);
        token.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(nonLP);
        token.approve(address(market), type(uint256).max);
        vm.stopPrank();

        // Create markets for testing
        vm.startPrank(owner);

        string[] memory optionNames = new string[](2);
        optionNames[0] = "Yes";
        optionNames[1] = "No";

        string[] memory optionDescriptions = new string[](2);
        optionDescriptions[0] = "Option Yes";
        optionDescriptions[1] = "Option No";

        // Create main test market (paid)
        marketId = market.createMarket(
            "Test liquidity market",
            "Testing liquidity functionality",
            optionNames,
            optionDescriptions,
            1 days,
            PolicastMarketV3.MarketCategory.OTHER,
            PolicastMarketV3.MarketType.PAID,
            1000 * 1e18
        );

        // Create free market for testing admin liquidity withdrawal
        freeMarketId = market.createFreeMarket(
            "Free test market",
            "Testing free market admin liquidity",
            optionNames,
            optionDescriptions,
            1 days,
            PolicastMarketV3.MarketCategory.OTHER,
            100, // maxParticipants
            500 * 1e18, // tokensPerParticipant
            2000 * 1e18 // initialLiquidity
        );

        // Validate both markets
        market.validateMarket(marketId);
        market.validateMarket(freeMarketId);

        vm.stopPrank();

        // Set up some trading to generate AMM fees
        vm.startPrank(user1);
        uint256 cost = market.calculateAMMBuyCost(marketId, 0, 100 * 1e18);
        market.buyShares(marketId, 0, 100 * 1e18, cost * 2);
        vm.stopPrank();

        vm.startPrank(user2);
        uint256 cost2 = market.calculateAMMBuyCost(marketId, 1, 50 * 1e18);
        market.buyShares(marketId, 1, 50 * 1e18, cost2 * 2);
        vm.stopPrank();
    }

    function testAddAMMLiquiditySuccess() public {
        vm.startPrank(user1);

        uint256 liquidityAmount = 1000 * 1e18;
        uint256 balanceBefore = token.balanceOf(user1);

        // Check LP info before
        (uint256 contributionBefore, bool rewardsClaimedBefore, uint256 estimatedRewardsBefore) =
            market.getLPInfo(marketId, user1);
        assertEq(contributionBefore, 0);
        assertFalse(rewardsClaimedBefore);
        assertEq(estimatedRewardsBefore, 0);

        vm.expectEmit(true, true, false, true);
        emit PolicastMarketV3.LiquidityAdded(marketId, user1, liquidityAmount);
        market.addAMMLiquidity(marketId, liquidityAmount);

        uint256 balanceAfter = token.balanceOf(user1);
        assertEq(balanceBefore - balanceAfter, liquidityAmount);

        // Check LP info after
        (uint256 contributionAfter,,) = market.getLPInfo(marketId, user1);
        assertEq(contributionAfter, liquidityAmount);

        vm.stopPrank();
    }

    function testAddAMMLiquidityAmountMustBePositive() public {
        vm.startPrank(user1);

        vm.expectRevert(PolicastMarketV3.AmountMustBePositive.selector);
        market.addAMMLiquidity(marketId, 0);

        vm.stopPrank();
    }

    function testAddAMMLiquidityTransferFailed() public {
        // Create a scenario where transfer fails by setting insufficient allowance
        vm.startPrank(user1);
        token.approve(address(market), 500 * 1e18); // Less than what we're trying to add

        vm.expectRevert(); // Just expect any revert since it could be ERC20 error or TransferFailed
        market.addAMMLiquidity(marketId, 1000 * 1e18);

        vm.stopPrank();
    }

    function testClaimLPRewardsSuccess() public {
        // First, add liquidity from multiple users
        vm.startPrank(user1);
        market.addAMMLiquidity(marketId, 1000 * 1e18);
        vm.stopPrank();

        vm.startPrank(user2);
        market.addAMMLiquidity(marketId, 500 * 1e18);
        vm.stopPrank();

        // Generate AMM fees through swapping (not just buying)
        // First buy shares so we have something to swap
        vm.startPrank(user3);
        uint256 cost = market.calculateAMMBuyCost(marketId, 0, 1000 * 1e18);
        market.buyShares(marketId, 0, 1000 * 1e18, cost * 2);

        uint256 cost2 = market.calculateAMMBuyCost(marketId, 1, 500 * 1e18);
        market.buyShares(marketId, 1, 500 * 1e18, cost2 * 2);

        // Now swap to generate AMM fees
        market.ammSwap(marketId, 0, 1, 100 * 1e18, 0); // Swap some option 0 for option 1
        market.ammSwap(marketId, 1, 0, 50 * 1e18, 0); // Swap some option 1 for option 0
        vm.stopPrank();

        // Check estimated rewards
        (, bool rewardsClaimed, uint256 estimatedRewards) = market.getLPInfo(marketId, user1);
        assertGt(estimatedRewards, 0);
        assertFalse(rewardsClaimed);

        // Claim rewards
        vm.startPrank(user1);
        uint256 balanceBefore = token.balanceOf(user1);

        vm.expectEmit(true, true, false, true);
        emit PolicastMarketV3.LPRewardsClaimed(marketId, user1, estimatedRewards);
        market.claimLPRewards(marketId);

        uint256 balanceAfter = token.balanceOf(user1);
        uint256 rewardsReceived = balanceAfter - balanceBefore;
        assertEq(rewardsReceived, estimatedRewards);

        // Check rewards claimed status
        (, bool rewardsClaimedAfter,) = market.getLPInfo(marketId, user1);
        assertTrue(rewardsClaimedAfter);

        vm.stopPrank();
    }

    function testClaimLPRewardsNotLiquidityProvider() public {
        vm.startPrank(nonLP);

        vm.expectRevert(PolicastMarketV3.NotLiquidityProvider.selector);
        market.claimLPRewards(marketId);

        vm.stopPrank();
    }

    function testClaimLPRewardsAlreadyClaimed() public {
        // Add liquidity and generate fees via swaps
        vm.startPrank(user1);
        market.addAMMLiquidity(marketId, 1000 * 1e18);
        vm.stopPrank();

        vm.startPrank(user3);
        // Buy shares first
        uint256 cost = market.calculateAMMBuyCost(marketId, 0, 500 * 1e18);
        market.buyShares(marketId, 0, 500 * 1e18, cost * 2);
        uint256 cost2 = market.calculateAMMBuyCost(marketId, 1, 500 * 1e18);
        market.buyShares(marketId, 1, 500 * 1e18, cost2 * 2);

        // Generate AMM fees through swaps
        market.ammSwap(marketId, 0, 1, 100 * 1e18, 0);
        vm.stopPrank();

        // Claim rewards first time
        vm.startPrank(user1);
        market.claimLPRewards(marketId);

        // Try to claim again
        vm.expectRevert(PolicastMarketV3.AlreadyClaimed.selector);
        market.claimLPRewards(marketId);

        vm.stopPrank();
    }

    function testClaimLPRewardsNoRewards() public {
        // Add liquidity but don't generate any AMM fees
        vm.startPrank(user1);
        market.addAMMLiquidity(marketId, 1000 * 1e18);

        // Since there are already some AMM fees from setUp, let's create a new market
        string[] memory optionNames = new string[](2);
        optionNames[0] = "Yes";
        optionNames[1] = "No";

        string[] memory optionDescriptions = new string[](2);
        optionDescriptions[0] = "Option Yes";
        optionDescriptions[1] = "Option No";

        vm.stopPrank();

        vm.startPrank(owner);
        uint256 noFeesMarketId = market.createMarket(
            "No fees market",
            "Market with no AMM fees",
            optionNames,
            optionDescriptions,
            1 days,
            PolicastMarketV3.MarketCategory.OTHER,
            PolicastMarketV3.MarketType.PAID,
            1000 * 1e18
        );
        market.validateMarket(noFeesMarketId);
        vm.stopPrank();

        vm.startPrank(user1);
        market.addAMMLiquidity(noFeesMarketId, 1000 * 1e18);

        vm.expectRevert(PolicastMarketV3.NoLPRewards.selector);
        market.claimLPRewards(noFeesMarketId);

        vm.stopPrank();
    }

    function testWithdrawAdminLiquiditySuccess() public {
        // Resolve the market first
        vm.warp(block.timestamp + 1 days + 1);
        vm.startPrank(owner);
        market.resolveMarket(marketId, 0);

        uint256 balanceBefore = token.balanceOf(owner);

        vm.expectEmit(true, true, false, true);
        emit PolicastMarketV3.AdminLiquidityWithdrawn(marketId, owner, 1000 * 1e18);
        market.withdrawAdminLiquidity(marketId);

        uint256 balanceAfter = token.balanceOf(owner);
        uint256 withdrawn = balanceAfter - balanceBefore;
        assertEq(withdrawn, 1000 * 1e18);

        vm.stopPrank();
    }

    function testWithdrawAdminLiquidityNotCreator() public {
        // Resolve the market first
        vm.warp(block.timestamp + 1 days + 1);
        vm.startPrank(owner);
        market.resolveMarket(marketId, 0);
        vm.stopPrank();

        vm.startPrank(user1);

        vm.expectRevert(PolicastMarketV3.NotAuthorized.selector);
        market.withdrawAdminLiquidity(marketId);

        vm.stopPrank();
    }

    function testWithdrawAdminLiquidityNotResolved() public {
        vm.startPrank(owner);

        vm.expectRevert(PolicastMarketV3.MarketNotResolved.selector);
        market.withdrawAdminLiquidity(marketId);

        vm.stopPrank();
    }

    function testWithdrawAdminLiquidityAlreadyClaimed() public {
        // Resolve and withdraw first time
        vm.warp(block.timestamp + 1 days + 1);
        vm.startPrank(owner);
        market.resolveMarket(marketId, 0);
        market.withdrawAdminLiquidity(marketId);

        // Try to withdraw again
        vm.expectRevert(PolicastMarketV3.AdminLiquidityAlreadyClaimed.selector);
        market.withdrawAdminLiquidity(marketId);

        vm.stopPrank();
    }

    function testMultipleLPsAddLiquidity() public {
        // Multiple users add liquidity
        vm.startPrank(user1);
        market.addAMMLiquidity(marketId, 1000 * 1e18);
        vm.stopPrank();

        vm.startPrank(user2);
        market.addAMMLiquidity(marketId, 2000 * 1e18);
        vm.stopPrank();

        vm.startPrank(user3);
        market.addAMMLiquidity(marketId, 500 * 1e18);
        vm.stopPrank();

        // Check each LP's contribution
        (uint256 contribution1,,) = market.getLPInfo(marketId, user1);
        (uint256 contribution2,,) = market.getLPInfo(marketId, user2);
        (uint256 contribution3,,) = market.getLPInfo(marketId, user3);

        assertEq(contribution1, 1000 * 1e18);
        assertEq(contribution2, 2000 * 1e18);
        assertEq(contribution3, 500 * 1e18);

        // Generate fees and check reward distribution
        vm.startPrank(nonLP);
        uint256 cost = market.calculateAMMBuyCost(marketId, 1, 500 * 1e18);
        market.buyShares(marketId, 1, 500 * 1e18, cost * 2);
        vm.stopPrank();

        // Check estimated rewards are proportional to contributions
        (,, uint256 estimatedRewards1) = market.getLPInfo(marketId, user1);
        (,, uint256 estimatedRewards2) = market.getLPInfo(marketId, user2);
        (,, uint256 estimatedRewards3) = market.getLPInfo(marketId, user3);

        // User2 should get 2x rewards compared to user1 (2000 vs 1000 contribution)
        assertApproxEqAbs(estimatedRewards2, estimatedRewards1 * 2, 1e15); // Allow small rounding error

        // User3 should get 0.5x rewards compared to user1 (500 vs 1000 contribution)
        assertApproxEqAbs(estimatedRewards3, estimatedRewards1 / 2, 1e15);
    }

    function testLPInfoAfterMultipleAdditions() public {
        vm.startPrank(user1);

        // Add liquidity multiple times
        market.addAMMLiquidity(marketId, 500 * 1e18);
        (uint256 contribution1,,) = market.getLPInfo(marketId, user1);
        assertEq(contribution1, 500 * 1e18);

        market.addAMMLiquidity(marketId, 300 * 1e18);
        (uint256 contribution2,,) = market.getLPInfo(marketId, user1);
        assertEq(contribution2, 800 * 1e18);

        market.addAMMLiquidity(marketId, 200 * 1e18);
        (uint256 contribution3,,) = market.getLPInfo(marketId, user1);
        assertEq(contribution3, 1000 * 1e18);

        vm.stopPrank();
    }

    function testLPRewardsCalculationAccuracy() public {
        // Add known amounts of liquidity
        vm.startPrank(user1);
        market.addAMMLiquidity(marketId, 1000 * 1e18); // 50% of total LP pool
        vm.stopPrank();

        vm.startPrank(user2);
        market.addAMMLiquidity(marketId, 1000 * 1e18); // 50% of total LP pool
        vm.stopPrank();

        // Generate AMM fees through swaps
        vm.startPrank(user3);
        // Buy shares first
        uint256 cost = market.calculateAMMBuyCost(marketId, 0, 1000 * 1e18);
        market.buyShares(marketId, 0, 1000 * 1e18, cost * 2);
        uint256 cost2 = market.calculateAMMBuyCost(marketId, 1, 1000 * 1e18);
        market.buyShares(marketId, 1, 1000 * 1e18, cost2 * 2);

        // Generate fees through swaps
        market.ammSwap(marketId, 0, 1, 200 * 1e18, 0);
        market.ammSwap(marketId, 1, 0, 100 * 1e18, 0);
        vm.stopPrank();

        // Check that rewards are split equally between the two LPs
        (,, uint256 estimatedRewards1) = market.getLPInfo(marketId, user1);
        (,, uint256 estimatedRewards2) = market.getLPInfo(marketId, user2);

        // Should be equal since they both contributed the same amount
        assertEq(estimatedRewards1, estimatedRewards2);

        // Both should be able to claim their rewards
        vm.startPrank(user1);
        uint256 balanceBefore1 = token.balanceOf(user1);
        market.claimLPRewards(marketId);
        uint256 balanceAfter1 = token.balanceOf(user1);
        uint256 actualRewards1 = balanceAfter1 - balanceBefore1;
        vm.stopPrank();

        vm.startPrank(user2);
        uint256 balanceBefore2 = token.balanceOf(user2);
        market.claimLPRewards(marketId);
        uint256 balanceAfter2 = token.balanceOf(user2);
        uint256 actualRewards2 = balanceAfter2 - balanceBefore2;
        vm.stopPrank();

        assertEq(actualRewards1, estimatedRewards1);
        assertEq(actualRewards2, estimatedRewards2);
        assertEq(actualRewards1, actualRewards2);
    }

    function testWithdrawAdminLiquidityFromInvalidatedMarket() public {
        // Create a new unvalidated market to test invalidation
        vm.startPrank(owner);

        string[] memory optionNames = new string[](2);
        optionNames[0] = "Yes";
        optionNames[1] = "No";

        string[] memory optionDescriptions = new string[](2);
        optionDescriptions[0] = "Option Yes";
        optionDescriptions[1] = "Option No";

        uint256 unvalidatedMarketId = market.createMarket(
            "Unvalidated market",
            "Market to be invalidated",
            optionNames,
            optionDescriptions,
            1 days,
            PolicastMarketV3.MarketCategory.OTHER,
            PolicastMarketV3.MarketType.PAID,
            1000 * 1e18
        );

        // Don't validate this market, so we can invalidate it

        // Invalidate the market (this automatically refunds admin liquidity)
        market.invalidateMarket(unvalidatedMarketId);

        // Since invalidateMarket automatically refunds admin liquidity,
        // trying to withdraw again should fail
        vm.expectRevert(PolicastMarketV3.AdminLiquidityAlreadyClaimed.selector);
        market.withdrawAdminLiquidity(unvalidatedMarketId);

        vm.stopPrank();
    }
}
