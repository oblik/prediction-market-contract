## Test Structure Overview

We'll create the following test files in test:

1. **Setup.t.sol** - Contract deployment and basic setup
2. **MarketCreation.t.sol** - Market creation functions
3. **Trading.t.sol** - Buy/sell shares and AMM functionality
4. **FreeMarkets.t.sol** - Free entry market features
5. **Resolution.t.sol** - Market resolution and payouts
6. **Liquidity.t.sol** - Liquidity provision and LP rewards
7. **Fees.t.sol** - Fee management and withdrawals
8. **ViewFunctions.t.sol** - All getter/view functions
9. **ErrorCases.t.sol** - All revert scenarios
10. **EdgeCases.t.sol** - Boundary conditions and complex scenarios

## Detailed Test Cases

### Setup.t.sol

- `testConstructor()` - Verify initial state after deployment
- `testInitialRoles()` - Check DEFAULT_ADMIN_ROLE assignment
- `testInitialFeeCollector()` - Verify fee collector is owner
- `testInitialPlatformFeeRate()` - Check default 2% fee rate
- `testInitialAMMFeeRate()` - Verify 0.3% AMM fee

### MarketCreation.t.sol

- `testCreateMarketSuccess()` - Successful market creation with valid inputs
- `testCreateMarketWithDefaultLiquidity()` - Using convenience function
- `testCreateFreeMarketSuccess()` - Free market creation
- `testCreateMarketUnauthorized()` - Non-creator trying to create market
- `testCreateMarketInvalidDuration()` - Duration too short/long
- `testCreateMarketEmptyQuestion()` - Empty question string
- `testCreateMarketBadOptionCount()` - Too few/many options
- `testCreateMarketLengthMismatch()` - Option names/descriptions mismatch
- `testCreateMarketMinTokensRequired()` - Insufficient initial liquidity
- `testCreateMarketTransferFailed()` - Token transfer failure
- `testValidateMarketSuccess()` - Successful validation
- `testValidateMarketUnauthorized()` - Non-validator trying to validate
- `testValidateMarketAlreadyValidated()` - Double validation attempt

### Trading.t.sol

- `testBuySharesSuccess()` - Successful share purchase
- `testBuySharesPriceTooHigh()` - Slippage protection
- `testBuySharesAmountMustBePositive()` - Zero quantity
- `testBuySharesMarketNotValidated()` - Unvalidated market
- `testBuySharesInvalidOption()` - Invalid option ID
- `testBuySharesTransferFailed()` - Token transfer failure
- `testSellSharesSuccess()` - Successful share sale
- `testSellSharesPriceTooLow()` - Slippage protection
- `testSellSharesInsufficientShares()` - Not enough shares
- `testSellSharesTransferFailed()` - Token transfer failure
- `testAMMSwapSuccess()` - Successful AMM swap
- `testAMMSwapSameOption()` - Swapping same option
- `testAMMSwapInsufficientShares()` - Not enough shares to swap
- `testAMMSwapInsufficientOutput()` - Output below minimum
- `testAMMSwapInsufficientLiquidity()` - Not enough liquidity
- `testCalculateAMMBuyCost()` - Cost calculation accuracy
- `testCalculateAMMSellRevenue()` - Revenue calculation accuracy
- `testCalculateCurrentPrice()` - Price calculation
- `testCalculateNewPriceBuy()` - Price after buy
- `testCalculateNewPriceSell()` - Price after sell

### FreeMarkets.t.sol

- `testClaimFreeTokensSuccess()` - Successful free token claim
- `testClaimFreeTokensAlreadyClaimed()` - Double claim attempt
- `testClaimFreeTokensNotFreeMarket()` - Claiming on paid market
- `testClaimFreeTokensInactive()` - Claiming when inactive
- `testClaimFreeTokensSlotsFull()` - All slots taken
- `testClaimFreeTokensInsufficientPrizePool()` - Not enough tokens left
- `testClaimFreeTokensTransferFailed()` - Token transfer failure
- `testWithdrawUnusedPrizePoolSuccess()` - Withdraw unused tokens
- `testWithdrawUnusedPrizePoolNotCreator()` - Non-creator withdrawal
- `testWithdrawUnusedPrizePoolNotResolved()` - Market not resolved
- `testWithdrawUnusedPrizePoolZeroAmount()` - No unused tokens

### Resolution.t.sol

- `testResolveMarketSuccess()` - Successful resolution
- `testResolveMarketUnauthorized()` - Non-resolver trying to resolve
- `testResolveMarketNotEnded()` - Resolving before end time
- `testResolveMarketAlreadyResolved()` - Double resolution
- `testResolveMarketInvalidOption()` - Invalid winning option
- `testDisputeMarketSuccess()` - Successful dispute
- `testDisputeMarketNotResolved()` - Disputing unresolved market
- `testDisputeMarketAlreadyDisputed()` - Double dispute
- `testDisputeMarketCannotDisputeIfWon()` - Winner trying to dispute
- `testClaimWinningsSuccess()` - Successful claim
- `testClaimWinningsAlreadyClaimed()` - Double claim
- `testClaimWinningsNoWinningShares()` - No shares in winning option
- `testClaimWinningsMarketNotReady()` - Market not resolved or disputed
- `testClaimWinningsTransferFailed()` - Token transfer failure

### Liquidity.t.sol

- `testAddAMMLiquiditySuccess()` - Successful liquidity addition
- `testAddAMMLiquidityAmountMustBePositive()` - Zero amount
- `testAddAMMLiquidityTransferFailed()` - Token transfer failure
- `testClaimLPRewardsSuccess()` - Successful reward claim
- `testClaimLPRewardsNotLiquidityProvider()` - Non-LP claiming
- `testClaimLPRewardsAlreadyClaimed()` - Double claim
- `testClaimLPRewardsNoRewards()` - No rewards available
- `testWithdrawAdminLiquiditySuccess()` - Admin liquidity withdrawal
- `testWithdrawAdminLiquidityNotCreator()` - Non-creator withdrawal
- `testWithdrawAdminLiquidityNotResolved()` - Market not resolved
- `testWithdrawAdminLiquidityAlreadyClaimed()` - Double withdrawal

### Fees.t.sol

- `testSetPlatformFeeRateSuccess()` - Successful fee rate update
- `testSetPlatformFeeRateTooHigh()` - Fee rate > 10%
- `testSetPlatformFeeRateUnauthorized()` - Non-owner trying to set
- `testSetFeeCollectorSuccess()` - Successful collector update
- `testSetFeeCollectorUnauthorized()` - Non-owner trying to set
- `testWithdrawPlatformFeesSuccess()` - Successful fee withdrawal
- `testWithdrawPlatformFeesUnauthorized()` - Non-collector/owner
- `testWithdrawPlatformFeesNoFees()` - No fees to withdraw
- `testUpdateBettingTokenSuccess()` - Successful token update
- `testUpdateBettingTokenSameToken()` - Updating to same token
- `testUpdateBettingTokenInvalidToken()` - Zero address
- `testUpdateBettingTokenUnauthorized()` - Non-owner trying to update

### ViewFunctions.t.sol

- `testGetMarketInfo()` - Market info retrieval
- `testGetMarketOption()` - Option info retrieval
- `testGetUserShares()` - User shares retrieval
- `testGetUserPortfolio()` - Portfolio retrieval
- `testGetPriceHistory()` - Price history retrieval
- `testGetMarketsByCategory()` - Markets by category
- `testGetMarketCount()` - Market count
- `testGetBettingToken()` - Token address
- `testGetMarketFinancials()` - Financial breakdown
- `testGetLPInfo()` - LP information
- `testGetPlatformStats()` - Platform statistics
- `testGetFreeMarketInfo()` - Free market config
- `testHasUserClaimedFreeTokens()` - Free token claim status
- `testGetMarketOdds()` - Market odds calculation

### ErrorCases.t.sol

- `testInvalidMarket()` - Accessing non-existent market
- `testMarketNotActive()` - Operations on ended/resolved market
- `testOptionInactive()` - Operations on inactive option
- `testNotAuthorized()` - Unauthorized access attempts
- `testAlreadyClaimed()` - Double claims
- `testTransferFailed()` - Token transfer failures
- `testInvalidInput()` - Invalid input parameters
- `testInsufficientBalance()` - Insufficient token balance
- `testMarketAlreadyResolved()` - Operations on resolved market
- `testMarketNotResolved()` - Operations requiring resolution
- `testNoWinningShares()` - No shares in winning option
- `testFeeTooHigh()` - Fee rate too high
- `testBadDuration()` - Invalid market duration
- `testEmptyQuestion()` - Empty question
- `testBadOptionCount()` - Invalid option count
- `testLengthMismatch()` - Array length mismatch
- `testMinTokensRequired()` - Insufficient liquidity
- `testSamePrizeRequired()` - Invalid prize amounts
- `testNotFreeMarket()` - Operations on non-free markets
- `testFreeEntryInactive()` - Free market inactive
- `testAlreadyClaimedFree()` - Double free claim
- `testFreeSlotsFull()` - Free slots exhausted
- `testExceedsFreeAllowance()` - Exceeding free limits
- `testInsufficientPrizePool()` - Insufficient prize pool
- `testCannotSwapSameOption()` - Same option swap
- `testAmountMustBePositive()` - Zero amounts
- `testInsufficientShares()` - Insufficient shares
- `testInsufficientOutput()` - Insufficient swap output
- `testInsufficientLiquidity()` - Insufficient liquidity
- `testMarketNotValidated()` - Unvalidated market operations
- `testPriceTooHigh()` - Buy price too high
- `testPriceTooLow()` - Sell price too low
- `testMarketNotEndedYet()` - Early resolution
- `testInvalidWinningOption()` - Invalid winning option
- `testCannotDisputeIfWon()` - Winner disputing
- `testMarketNotReady()` - Unready market operations
- `testInvalidToken()` - Invalid token address
- `testSameToken()` - Same token update
- `testNoFeesToWithdraw()` - No fees available
- `testNoLPRewards()` - No LP rewards
- `testNotLiquidityProvider()` - Non-LP operations
- `testAdminLiquidityAlreadyClaimed()` - Double admin withdrawal
- `testInsufficientParticipants()` - Insufficient participants

### EdgeCases.t.sol

- `testMarketCreationBoundaryDurations()` - Min/max duration edges
- `testOptionCountBoundaries()` - Min/max option counts
- `testLiquidityBoundaries()` - Min/max liquidity amounts
- `testPriceCalculationsEdgeCases()` - Extreme price scenarios
- `testAMMReserveEdgeCases()` - Reserve manipulation edges
- `testMultipleMarketsInteraction()` - Cross-market interactions
- `testConcurrentOperations()` - Simultaneous operations
- `testLargeNumbers()` - Overflow/underflow protection
- `testTimeBasedOperations()` - Time-sensitive operations
- `testRoleCombinations()` - Multiple role scenarios
- `testStateTransitions()` - Complex state changes
- `testGasOptimization()` - Gas usage verification

## Coverage Goals

- **Function Coverage**: 100% of all public/external functions called
- **Branch Coverage**: All if/else branches executed
- **Statement Coverage**: Every line of code executed at least once
- **Modifier Coverage**: All modifiers triggered
- **Error Coverage**: All revert conditions tested
- **Event Coverage**: All events emitted and verified

## Testing Strategy

- Use Foundry's `forge test` with `--coverage` flag to measure coverage
- Implement fuzz testing for mathematical functions
- Use invariant testing for state consistency
- Test with different user roles and permissions
- Verify all emitted events
- Test gas usage and optimization
- Include integration tests for complex workflows

This comprehensive test suite will ensure robust security and functionality of the PolicastMarketV3 contract. Each test should include proper setup, execution, and assertions to validate expected behavior.
