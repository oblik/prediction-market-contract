// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/V3.sol";
import "./mocks/MockERC20.sol";

contract FeesTest is Test {
    PolicastMarketV3 public market;
    MockERC20 public token;
    MockERC20 public newToken;

    address public owner = address(0x123);
    address public newFeeCollector = address(0x456);
    address public user1 = address(0x789);
    address public user2 = address(0xabc);
    address public unauthorizedUser = address(0xdef);

    uint256 public marketId;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy tokens and market contract
        token = new MockERC20("Test Token", "TEST", 18);
        newToken = new MockERC20("New Token", "NEW", 18);
        market = new PolicastMarketV3(address(token));

        // Mint tokens to users
        token.mint(owner, 1000000 * 1e18);
        token.mint(user1, 10000 * 1e18);
        token.mint(user2, 10000 * 1e18);
        token.mint(unauthorizedUser, 10000 * 1e18);

        newToken.mint(owner, 1000000 * 1e18);

        // Approve market contract
        token.approve(address(market), type(uint256).max);

        // Grant necessary roles
        market.grantMarketValidatorRole(owner);

        vm.stopPrank();

        // Users approve market contract
        vm.startPrank(user1);
        token.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(unauthorizedUser);
        token.approve(address(market), type(uint256).max);
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
            "Test fees market",
            "Testing fee functionality",
            optionNames,
            optionDescriptions,
            1 days,
            PolicastMarketV3.MarketCategory.OTHER,
            PolicastMarketV3.MarketType.PAID,
            1000 * 1e18
        );

        market.validateMarket(marketId);
        vm.stopPrank();
    }

    function testSetPlatformFeeRateSuccess() public {
        vm.startPrank(owner);

        uint256 newFeeRate = 300; // 3%
        market.setPlatformFeeRate(newFeeRate);

        assertEq(market.platformFeeRate(), newFeeRate);

        vm.stopPrank();
    }

    function testSetPlatformFeeRateTooHigh() public {
        vm.startPrank(owner);

        uint256 tooHighFeeRate = 1001; // > 10% (1000 basis points)
        vm.expectRevert(PolicastMarketV3.FeeTooHigh.selector);
        market.setPlatformFeeRate(tooHighFeeRate);

        vm.stopPrank();
    }

    function testSetPlatformFeeRateUnauthorized() public {
        vm.startPrank(unauthorizedUser);

        uint256 newFeeRate = 300;
        vm.expectRevert(); // OwnableUnauthorizedAccount error
        market.setPlatformFeeRate(newFeeRate);

        vm.stopPrank();
    }

    function testSetFeeCollectorSuccess() public {
        vm.startPrank(owner);

        address oldCollector = market.feeCollector();

        vm.expectEmit(true, true, false, false);
        emit PolicastMarketV3.FeeCollectorUpdated(oldCollector, newFeeCollector);
        market.setFeeCollector(newFeeCollector);

        assertEq(market.feeCollector(), newFeeCollector);

        vm.stopPrank();
    }

    function testSetFeeCollectorUnauthorized() public {
        vm.startPrank(unauthorizedUser);

        vm.expectRevert(); // OwnableUnauthorizedAccount error
        market.setFeeCollector(newFeeCollector);

        vm.stopPrank();
    }

    function testSetFeeCollectorZeroAddress() public {
        vm.startPrank(owner);

        vm.expectRevert(PolicastMarketV3.InvalidToken.selector);
        market.setFeeCollector(address(0));

        vm.stopPrank();
    }

    function testWithdrawPlatformFeesSuccess() public {
        // Generate platform fees through trading
        vm.startPrank(user1);
        uint256 cost = market.calculateAMMBuyCost(marketId, 0, 1000 * 1e18);
        market.buyShares(marketId, 0, 1000 * 1e18, cost * 2);
        vm.stopPrank();

        // Check that fees were collected
        uint256 feesCollected = market.totalPlatformFeesCollected();
        assertGt(feesCollected, 0);

        // Withdraw fees as fee collector (owner by default)
        vm.startPrank(owner);
        uint256 balanceBefore = token.balanceOf(owner);

        vm.expectEmit(true, false, false, true);
        emit PolicastMarketV3.PlatformFeesWithdrawn(owner, feesCollected);
        market.withdrawPlatformFees();

        uint256 balanceAfter = token.balanceOf(owner);
        uint256 withdrawn = balanceAfter - balanceBefore;
        assertEq(withdrawn, feesCollected);

        // Check that fees collected is reset to 0
        assertEq(market.totalPlatformFeesCollected(), 0);

        vm.stopPrank();
    }

    function testWithdrawPlatformFeesAsNewCollector() public {
        // Set new fee collector
        vm.startPrank(owner);
        market.setFeeCollector(newFeeCollector);
        vm.stopPrank();

        // Generate platform fees
        vm.startPrank(user1);
        uint256 cost = market.calculateAMMBuyCost(marketId, 0, 1000 * 1e18);
        market.buyShares(marketId, 0, 1000 * 1e18, cost * 2);
        vm.stopPrank();

        uint256 feesCollected = market.totalPlatformFeesCollected();
        assertGt(feesCollected, 0);

        // Withdraw fees as new collector
        vm.startPrank(newFeeCollector);
        uint256 balanceBefore = token.balanceOf(newFeeCollector);

        market.withdrawPlatformFees();

        uint256 balanceAfter = token.balanceOf(newFeeCollector);
        uint256 withdrawn = balanceAfter - balanceBefore;
        assertEq(withdrawn, feesCollected);

        vm.stopPrank();
    }

    function testWithdrawPlatformFeesUnauthorized() public {
        // Generate some fees first
        vm.startPrank(user1);
        uint256 cost = market.calculateAMMBuyCost(marketId, 0, 1000 * 1e18);
        market.buyShares(marketId, 0, 1000 * 1e18, cost * 2);
        vm.stopPrank();

        vm.startPrank(unauthorizedUser);

        vm.expectRevert(PolicastMarketV3.NotAuthorized.selector);
        market.withdrawPlatformFees();

        vm.stopPrank();
    }

    function testWithdrawPlatformFeesNoFees() public {
        vm.startPrank(owner);

        vm.expectRevert(PolicastMarketV3.NoFeesToWithdraw.selector);
        market.withdrawPlatformFees();

        vm.stopPrank();
    }

    function testUpdateBettingTokenSuccess() public {
        vm.startPrank(owner);

        address oldToken = address(market.bettingToken());

        vm.expectEmit(true, true, false, false);
        emit PolicastMarketV3.BettingTokenUpdated(oldToken, address(newToken), block.timestamp);
        market.updateBettingToken(address(newToken));

        assertEq(address(market.bettingToken()), address(newToken));
        assertEq(market.previousBettingToken(), oldToken);
        assertEq(market.tokenUpdatedAt(), block.timestamp);

        vm.stopPrank();
    }

    function testUpdateBettingTokenAlternativeFunction() public {
        vm.startPrank(owner);

        address oldToken = address(market.bettingToken());

        vm.expectEmit(true, true, false, false);
        emit PolicastMarketV3.BettingTokenUpdated(oldToken, address(newToken), block.timestamp);
        market.updateBettingTokenAddress(address(newToken));

        assertEq(address(market.bettingToken()), address(newToken));
        assertEq(market.previousBettingToken(), oldToken);

        vm.stopPrank();
    }

    function testUpdateBettingTokenSameToken() public {
        vm.startPrank(owner);

        address currentToken = address(market.bettingToken());
        vm.expectRevert(PolicastMarketV3.SameToken.selector);
        market.updateBettingToken(currentToken);

        vm.stopPrank();
    }

    function testUpdateBettingTokenInvalidToken() public {
        vm.startPrank(owner);

        vm.expectRevert(PolicastMarketV3.InvalidToken.selector);
        market.updateBettingToken(address(0));

        vm.stopPrank();
    }

    function testUpdateBettingTokenUnauthorized() public {
        vm.startPrank(unauthorizedUser);

        vm.expectRevert(PolicastMarketV3.OnlyAdminOrOwner.selector);
        market.updateBettingToken(address(newToken));

        vm.stopPrank();
    }

    function testUpdateBettingTokenAddressInvalidToken() public {
        vm.startPrank(owner);

        vm.expectRevert(PolicastMarketV3.InvalidToken.selector);
        market.updateBettingTokenAddress(address(0));

        vm.stopPrank();
    }

    function testUpdateBettingTokenAddressUnauthorized() public {
        vm.startPrank(unauthorizedUser);

        vm.expectRevert(); // OwnableUnauthorizedAccount error
        market.updateBettingTokenAddress(address(newToken));

        vm.stopPrank();
    }

    function testInitialFeeSettings() public view {
        // Test initial platform fee rate (2%)
        assertEq(market.platformFeeRate(), 200);

        // Test initial AMM fee rate (0.3%)
        assertEq(market.AMM_FEE_RATE(), 30);

        // Test initial fee collector is owner
        assertEq(market.feeCollector(), owner);
    }

    function testPlatformFeeCalculationInBuyShares() public {
        vm.startPrank(user1);

        uint256 shareAmount = 1000 * 1e18;
        uint256 balanceBefore = token.balanceOf(user1);
        uint256 feesBefore = market.totalPlatformFeesCollected();

        uint256 cost = market.calculateAMMBuyCost(marketId, 0, shareAmount);
        market.buyShares(marketId, 0, shareAmount, cost * 2);

        uint256 balanceAfter = token.balanceOf(user1);
        uint256 feesAfter = market.totalPlatformFeesCollected();

        uint256 totalPaid = balanceBefore - balanceAfter;
        uint256 feesCollected = feesAfter - feesBefore;

        // Calculate expected fee (2% of total cost)
        uint256 expectedFee = totalPaid * 200 / (10000 + 200); // Extract fee from total

        assertApproxEqAbs(feesCollected, expectedFee, 1e15); // Allow small rounding error

        vm.stopPrank();
    }

    function testMultipleWithdrawals() public {
        // Generate fees in multiple transactions
        vm.startPrank(user1);
        uint256 cost1 = market.calculateAMMBuyCost(marketId, 0, 500 * 1e18);
        market.buyShares(marketId, 0, 500 * 1e18, cost1 * 2);
        vm.stopPrank();

        uint256 firstFees = market.totalPlatformFeesCollected();

        vm.startPrank(user2);
        uint256 cost2 = market.calculateAMMBuyCost(marketId, 1, 300 * 1e18);
        market.buyShares(marketId, 1, 300 * 1e18, cost2 * 2);
        vm.stopPrank();

        uint256 totalFees = market.totalPlatformFeesCollected();
        assertGt(totalFees, firstFees);

        // Withdraw first batch
        vm.startPrank(owner);
        uint256 balanceBefore = token.balanceOf(owner);
        market.withdrawPlatformFees();
        uint256 balanceAfter = token.balanceOf(owner);

        uint256 withdrawn = balanceAfter - balanceBefore;
        assertEq(withdrawn, totalFees);
        assertEq(market.totalPlatformFeesCollected(), 0);

        vm.stopPrank();

        // Generate more fees
        vm.startPrank(user1);
        uint256 cost3 = market.calculateAMMBuyCost(marketId, 0, 200 * 1e18);
        market.buyShares(marketId, 0, 200 * 1e18, cost3 * 2);
        vm.stopPrank();

        uint256 newFees = market.totalPlatformFeesCollected();
        assertGt(newFees, 0);

        // Withdraw second batch
        vm.startPrank(owner);
        uint256 balanceBefore2 = token.balanceOf(owner);
        market.withdrawPlatformFees();
        uint256 balanceAfter2 = token.balanceOf(owner);

        uint256 withdrawn2 = balanceAfter2 - balanceBefore2;
        assertEq(withdrawn2, newFees);

        vm.stopPrank();
    }

    function testFeeRateBoundaries() public {
        vm.startPrank(owner);

        // Test minimum fee rate (0%)
        market.setPlatformFeeRate(0);
        assertEq(market.platformFeeRate(), 0);

        // Test maximum fee rate (10%)
        market.setPlatformFeeRate(1000);
        assertEq(market.platformFeeRate(), 1000);

        // Test just over maximum (should fail)
        vm.expectRevert(PolicastMarketV3.FeeTooHigh.selector);
        market.setPlatformFeeRate(1001);

        vm.stopPrank();
    }

    function testOwnerCanWithdrawFeesEvenAfterCollectorChange() public {
        // Set new fee collector
        vm.startPrank(owner);
        market.setFeeCollector(newFeeCollector);
        vm.stopPrank();

        // Generate fees
        vm.startPrank(user1);
        uint256 cost = market.calculateAMMBuyCost(marketId, 0, 1000 * 1e18);
        market.buyShares(marketId, 0, 1000 * 1e18, cost * 2);
        vm.stopPrank();

        // Owner should still be able to withdraw fees
        vm.startPrank(owner);
        uint256 feesCollected = market.totalPlatformFeesCollected();
        assertGt(feesCollected, 0);

        market.withdrawPlatformFees();
        assertEq(market.totalPlatformFeesCollected(), 0);

        vm.stopPrank();
    }
}
