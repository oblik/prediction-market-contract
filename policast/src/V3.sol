// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract PolicastMarketV3 is Ownable, ReentrancyGuard, AccessControl, Pausable {
    // ERRORS
    error InsufficientBalance();
    error InvalidMarket();
    error MarketNotActive();
    error InvalidOption();
    error NotAuthorized();
    error MarketAlreadyResolved();
    error MarketNotResolved();
    error AlreadyClaimed();
    error NoWinningShares();
    error TransferFailed();
    error InvalidInput();
    error OnlyAdminOrOwner();
    error MarketEnded();
    error MarketResolvedAlready();
    error OptionInactive();
    error FeeTooHigh();
    error BadDuration();
    error EmptyQuestion();
    error BadOptionCount();
    error LengthMismatch();
    error MinTokensRequired();
    error SamePrizeRequired();
    error NotFreeMarket();
    error FreeEntryInactive();
    error AlreadyClaimedFree();
    error FreeSlotseFull();
    error ExceedsFreeAllowance();
    error InsufficientPrizePool();
    error CannotSwapSameOption();
    error AmountMustBePositive();
    error InsufficientShares();
    error InsufficientOutput();
    error InsufficientLiquidity();
    error MarketNotValidated();
    error PriceTooHigh();
    error PriceTooLow();
    error MarketNotEndedYet();
    error InvalidWinningOption();
    error CannotDisputeIfWon();
    error MarketNotReady();
    error InvalidToken();
    error SameToken();
    error NoFeesToWithdraw();
    error NoLPRewards();
    error NotLiquidityProvider();
    error AdminLiquidityAlreadyClaimed();
    error InsufficientParticipants();
    error MarketIsInvalidated();
    error MarketAlreadyInvalidated();
    error BatchDistributionFailed();
    error EmptyBatchList();
    error MarketTooNew(); // NEW: Prevent immediate resolution of event-based markets

    bytes32 public constant QUESTION_CREATOR_ROLE = keccak256("QUESTION_CREATOR_ROLE");
    bytes32 public constant QUESTION_RESOLVE_ROLE = keccak256("QUESTION_RESOLVE_ROLE");
    bytes32 public constant MARKET_VALIDATOR_ROLE = keccak256("MARKET_VALIDATOR_ROLE");

    // Market Categories
    enum MarketCategory {
        POLITICS,
        SPORTS,
        ENTERTAINMENT,
        TECHNOLOGY,
        ECONOMICS,
        SCIENCE,
        WEATHER,
        OTHER
    }

    // Market Types
    enum MarketType {
        PAID, // Regular betting token markets
        FREE_ENTRY // Free markets with limited participation

    }

    struct MarketOption {
        string name;
        string description;
        uint256 totalShares;
        uint256 totalVolume;
        uint256 currentPrice; // Price in wei (scaled by 1e18)
        bool isActive;
        uint256 k; // AMM liquidity constant for this option
        uint256 reserve; // AMM reserve for this option
    }

    struct FreeMarketConfig {
        uint256 maxFreeParticipants; // Max users who can enter for free
        uint256 tokensPerParticipant; // Buster tokens per user (instead of shares)
        uint256 currentFreeParticipants; // Current count
        uint256 totalPrizePool; // Total tokens allocated for free users
        uint256 remainingPrizePool; // Remaining tokens available
        bool isActive; // Can still accept free entries
        mapping(address => bool) hasClaimedFree; // Track who claimed free tokens
        mapping(address => uint256) tokensReceived; // Amount of free tokens claimed per user
    }

    struct Market {
        string question;
        string description;
        uint256 endTime;
        MarketCategory category;
        MarketType marketType; // Market type (PAID, FREE_ENTRY)
        uint256 winningOptionId;
        bool resolved;
        bool disputed;
        bool validated;
        bool invalidated; // NEW: Market has been invalidated by admin
        address creator;
        uint256 adminInitialLiquidity; // NEW: Admin's initial liquidity (separate tracking)
        uint256 userLiquidity; // NEW: User contributions only
        uint256 totalVolume;
        uint256 createdAt;
        uint256 optionCount;
        uint256 ammLiquidityPool; // Total AMM liquidity
        uint256 platformFeesCollected; // NEW: Platform fees for this market
        uint256 ammFeesCollected; // NEW: AMM fees for LPs
        bool adminLiquidityClaimed; // NEW: Track if admin claimed their liquidity back
        mapping(uint256 => MarketOption) options;
        mapping(address => mapping(uint256 => uint256)) userShares; // user => optionId => shares
        mapping(address => bool) hasClaimed;
        mapping(address => uint256) lpContributions; // NEW: Track LP contributions
        mapping(address => bool) lpRewardsClaimed; // NEW: Track LP reward claims
        address[] participants;
        address[] liquidityProviders; // NEW: Track LP addresses
        uint256 payoutIndex;
        FreeMarketConfig freeConfig; // Free market configuration
        bool earlyResolutionAllowed; // NEW: Allow resolution before endTime for event-based markets
    }

    struct Trade {
        uint256 marketId;
        uint256 optionId;
        address buyer;
        address seller;
        uint256 price;
        uint256 quantity;
        uint256 timestamp;
    }

    struct PricePoint {
        uint256 price;
        uint256 timestamp;
        uint256 volume;
    }

    struct UserPortfolio {
        uint256 totalInvested;
        uint256 totalWinnings;
        int256 unrealizedPnL;
        int256 realizedPnL;
        uint256 tradeCount;
    }

    //     // State variables
    IERC20 public bettingToken;
    address public previousBettingToken; // Track previous token for migration
    uint256 public tokenUpdatedAt; // When token was last updated
    uint256 public marketCount;
    uint256 public tradeCount;
    uint256 public platformFeeRate = 200; // 2% (basis points)
    uint256 public constant MAX_OPTIONS = 10;
    uint256 public constant MIN_MARKET_DURATION = 1 hours;
    uint256 public constant MAX_MARKET_DURATION = 365 days;
    uint256 public constant AMM_FEE_RATE = 30; // 0.3% AMM swap fee
    address public feeCollector; // NEW: Address that can withdraw platform fees
    uint256 public totalPlatformFeesCollected; // NEW: Global platform fees

    //     // Mappings
    mapping(uint256 => Market) internal markets;
    mapping(address => UserPortfolio) public userPortfolios;
    mapping(address => Trade[]) public userTradeHistory;
    mapping(uint256 => Trade[]) public marketTrades;
    mapping(uint256 => mapping(uint256 => PricePoint[])) public priceHistory; // marketId => optionId => prices
    mapping(MarketCategory => uint256[]) public categoryMarkets;
    mapping(address => uint256) public totalWinnings;
    mapping(MarketType => uint256[]) public marketsByType; // Markets by type
    mapping(address => uint256) public lpRewardsEarned; // NEW: LP rewards earned globally
    address[] public allParticipants;

    //     // Events
    event MarketCreated(
        uint256 indexed marketId,
        string question,
        string[] options,
        uint256 endTime,
        MarketCategory category,
        MarketType marketType,
        address creator
    );
    event FreeTokensClaimed(uint256 indexed marketId, address indexed user, uint256 tokens);
    event BettingTokenUpdated(address indexed oldToken, address indexed newToken, uint256 timestamp);
    event AMMSwap(
        uint256 indexed marketId,
        uint256 optionIdIn,
        uint256 optionIdOut,
        uint256 amountIn,
        uint256 amountOut,
        address trader
    );
    event LiquidityAdded(uint256 indexed marketId, address indexed provider, uint256 amount);
    event MarketValidated(uint256 indexed marketId, address validator);
    event MarketInvalidated(uint256 indexed marketId, address validator, uint256 refundedAmount);
    event TradeExecuted(
        uint256 indexed marketId,
        uint256 indexed optionId,
        address indexed buyer,
        address seller,
        uint256 price,
        uint256 quantity,
        uint256 tradeId
    );
    event SharesSold(
        uint256 indexed marketId, uint256 indexed optionId, address indexed seller, uint256 quantity, uint256 price
    );
    event MarketResolved(uint256 indexed marketId, uint256 winningOptionId, address resolver);
    event MarketDisputed(uint256 indexed marketId, address disputer, string reason);
    event Claimed(uint256 indexed marketId, address indexed user, uint256 amount);
    event FeeCollected(uint256 indexed marketId, uint256 amount);
    event MarketPaused(uint256 indexed marketId);
    event PlatformFeesWithdrawn(address indexed collector, uint256 amount);
    event AdminLiquidityWithdrawn(uint256 indexed marketId, address indexed creator, uint256 amount);
    event LPRewardsClaimed(uint256 indexed marketId, address indexed provider, uint256 amount);
    event FeeCollectorUpdated(address indexed oldCollector, address indexed newCollector);
    event BatchWinningsDistributed(uint256 indexed marketId, uint256 totalDistributed, uint256 recipientCount);
    event WinningsDistributedToUser(uint256 indexed marketId, address indexed user, uint256 amount);

    constructor(address _bettingToken) Ownable(msg.sender) {
        bettingToken = IERC20(_bettingToken);
        tokenUpdatedAt = block.timestamp;
        feeCollector = msg.sender; // Owner is initial fee collector
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    //     // Token Management Functions
    function updateBettingToken(address _newToken) external {
        if (msg.sender != owner() && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert OnlyAdminOrOwner();
        if (_newToken == address(0)) revert InvalidToken();
        if (_newToken == address(bettingToken)) revert SameToken();

        previousBettingToken = address(bettingToken);
        bettingToken = IERC20(_newToken);
        tokenUpdatedAt = block.timestamp;

        emit BettingTokenUpdated(previousBettingToken, _newToken, block.timestamp);
    }

    function setFeeCollector(address _feeCollector) external onlyOwner {
        if (_feeCollector == address(0)) revert InvalidToken();
        address oldCollector = feeCollector;
        feeCollector = _feeCollector;
        emit FeeCollectorUpdated(oldCollector, _feeCollector);
    }

    //     // Modifiers
    modifier validMarket(uint256 _marketId) {
        if (_marketId >= marketCount) revert InvalidMarket();
        _;
    }

    modifier marketActive(uint256 _marketId) {
        if (markets[_marketId].resolved) revert MarketResolvedAlready();
        if (block.timestamp >= markets[_marketId].endTime) revert MarketEnded();
        if (markets[_marketId].invalidated) revert MarketIsInvalidated();
        _;
    }

    modifier validOption(uint256 _marketId, uint256 _optionId) {
        if (_optionId >= markets[_marketId].optionCount) revert InvalidOption();
        if (!markets[_marketId].options[_optionId].isActive) revert OptionInactive();
        _;
    }

    //     // Admin Functions
    function grantQuestionCreatorRole(address _account) external onlyOwner {
        grantRole(QUESTION_CREATOR_ROLE, _account);
    }

    function grantQuestionResolveRole(address _account) external onlyOwner {
        grantRole(QUESTION_RESOLVE_ROLE, _account);
    }

    function grantMarketValidatorRole(address _account) external onlyOwner {
        grantRole(MARKET_VALIDATOR_ROLE, _account);
    }

    function setPlatformFeeRate(uint256 _feeRate) external onlyOwner {
        if (_feeRate > 1000) revert FeeTooHigh();
        platformFeeRate = _feeRate;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    //     // Market Creation
    function createMarket(
        string memory _question,
        string memory _description,
        string[] memory _optionNames,
        string[] memory _optionDescriptions,
        uint256 _duration,
        MarketCategory _category,
        MarketType _marketType,
        uint256 _initialLiquidity,
        bool _earlyResolutionAllowed // NEW parameter
    ) public whenNotPaused returns (uint256) {
        if (msg.sender != owner() && !hasRole(QUESTION_CREATOR_ROLE, msg.sender)) revert NotAuthorized();
        if (_duration < MIN_MARKET_DURATION || _duration > MAX_MARKET_DURATION) revert BadDuration();
        if (bytes(_question).length == 0) revert EmptyQuestion();
        if (_optionNames.length < 2 || _optionNames.length > MAX_OPTIONS) revert BadOptionCount();
        if (_optionNames.length != _optionDescriptions.length) revert LengthMismatch();
        if (_initialLiquidity < 100 * 1e18) revert MinTokensRequired();

        // Transfer initial liquidity from creator
        if (!bettingToken.transferFrom(msg.sender, address(this), _initialLiquidity)) revert TransferFailed();

        uint256 marketId = marketCount++;
        Market storage market = markets[marketId];
        market.question = _question;
        market.description = _description;
        market.endTime = block.timestamp + _duration;
        market.category = _category;
        market.marketType = _marketType;
        market.creator = msg.sender;
        market.createdAt = block.timestamp;
        market.optionCount = _optionNames.length;
        market.earlyResolutionAllowed = _earlyResolutionAllowed; // NEW: Set the flag

        // Track admin's initial liquidity separately
        market.adminInitialLiquidity = _initialLiquidity;
        market.userLiquidity = 0; // No user liquidity yet

        // Initialize AMM liquidity pool with provided liquidity
        market.ammLiquidityPool = _initialLiquidity;

        // Initialize options with equal starting prices and AMM constants
        uint256 initialPrice = 1e18 / _optionNames.length; // Equal probability distribution
        uint256 initialK = _initialLiquidity / _optionNames.length; // AMM constant per option
        // Calculate reserve so that price = (k * 1e18) / reserve = initialPrice
        // If initialPrice = 0.5e18 and k = 500e18, then reserve = (500e18 * 1e18) / 0.5e18 = 1000e18
        uint256 initialReserve = (initialK * 1e18) / initialPrice;

        for (uint256 i = 0; i < _optionNames.length; i++) {
            market.options[i] = MarketOption({
                name: _optionNames[i],
                description: _optionDescriptions[i],
                totalShares: 0,
                totalVolume: 0,
                currentPrice: initialPrice,
                isActive: true,
                k: initialK,
                reserve: initialReserve
            });

            // Initialize price history
            priceHistory[marketId][i].push(PricePoint({price: initialPrice, timestamp: block.timestamp, volume: 0}));
        }

        categoryMarkets[_category].push(marketId);
        marketsByType[_marketType].push(marketId);

        emit MarketCreated(marketId, _question, _optionNames, market.endTime, _category, _marketType, msg.sender);
        return marketId;
    }

    //     // Create Free Entry Market
    function createFreeMarket(
        string memory _question,
        string memory _description,
        string[] memory _optionNames,
        string[] memory _optionDescriptions,
        uint256 _duration,
        MarketCategory _category,
        uint256 _maxFreeParticipants,
        uint256 _tokensPerParticipant,
        uint256 _initialLiquidity,
        bool _earlyResolutionAllowed // NEW parameter
    ) external whenNotPaused returns (uint256) {
        // Calculate total required: liquidity + prize pool
        uint256 totalPrizePool = _maxFreeParticipants * _tokensPerParticipant;
        uint256 totalRequired = _initialLiquidity + totalPrizePool;

        // Transfer both liquidity and prize pool from creator
        if (!bettingToken.transferFrom(msg.sender, address(this), totalRequired)) revert TransferFailed();

        // Create market WITHOUT calling the internal createMarket to avoid double transfer
        if (msg.sender != owner() && !hasRole(QUESTION_CREATOR_ROLE, msg.sender)) revert NotAuthorized();
        if (_duration < MIN_MARKET_DURATION || _duration > MAX_MARKET_DURATION) revert BadDuration();
        if (bytes(_question).length == 0) revert EmptyQuestion();
        if (_optionNames.length < 2 || _optionNames.length > MAX_OPTIONS) revert BadOptionCount();
        if (_optionNames.length != _optionDescriptions.length) revert LengthMismatch();
        if (_initialLiquidity < 100 * 1e18) revert MinTokensRequired();

        uint256 marketId = marketCount++;
        Market storage market = markets[marketId];
        market.question = _question;
        market.description = _description;
        market.endTime = block.timestamp + _duration;
        market.category = _category;
        market.marketType = MarketType.FREE_ENTRY;
        market.creator = msg.sender;
        market.createdAt = block.timestamp;
        market.optionCount = _optionNames.length;
        market.earlyResolutionAllowed = _earlyResolutionAllowed; // NEW: Set the flag

        // Track admin's initial liquidity separately
        market.adminInitialLiquidity = _initialLiquidity;
        market.userLiquidity = 0; // No user liquidity yet

        // Initialize AMM liquidity pool with provided liquidity
        market.ammLiquidityPool = _initialLiquidity;

        // Initialize options with equal starting prices and AMM constants
        uint256 initialPrice = 1e18 / _optionNames.length; // Equal probability distribution
        uint256 initialK = _initialLiquidity / _optionNames.length; // AMM constant per option
        uint256 initialReserve = (initialK * 1e18) / initialPrice;

        for (uint256 i = 0; i < _optionNames.length; i++) {
            market.options[i] = MarketOption({
                name: _optionNames[i],
                description: _optionDescriptions[i],
                totalShares: 0,
                totalVolume: 0,
                currentPrice: initialPrice,
                isActive: true,
                k: initialK,
                reserve: initialReserve
            });

            // Initialize price history
            priceHistory[marketId][i].push(PricePoint({price: initialPrice, timestamp: block.timestamp, volume: 0}));
        }

        categoryMarkets[_category].push(marketId);
        marketsByType[MarketType.FREE_ENTRY].push(marketId);

        // Configure free market settings
        market.freeConfig.maxFreeParticipants = _maxFreeParticipants;
        market.freeConfig.tokensPerParticipant = _tokensPerParticipant;
        market.freeConfig.totalPrizePool = totalPrizePool;
        market.freeConfig.remainingPrizePool = totalPrizePool;
        market.freeConfig.isActive = true;

        emit MarketCreated(
            marketId, _question, _optionNames, market.endTime, _category, MarketType.FREE_ENTRY, msg.sender
        );
        return marketId;
    }

    function validateMarket(uint256 _marketId) external validMarket(_marketId) {
        if (!hasRole(MARKET_VALIDATOR_ROLE, msg.sender) && msg.sender != owner()) revert NotAuthorized();
        if (markets[_marketId].validated) revert MarketAlreadyResolved();
        if (markets[_marketId].invalidated) revert MarketIsInvalidated();

        markets[_marketId].validated = true;
        emit MarketValidated(_marketId, msg.sender);
    }

    function invalidateMarket(uint256 _marketId) external validMarket(_marketId) {
        if (!hasRole(MARKET_VALIDATOR_ROLE, msg.sender) && msg.sender != owner()) revert NotAuthorized();
        if (markets[_marketId].validated) revert MarketAlreadyResolved();
        if (markets[_marketId].invalidated) revert MarketAlreadyInvalidated();

        Market storage market = markets[_marketId];
        market.invalidated = true;

        // Automatically refund creator's initial liquidity
        uint256 refundAmount = 0;
        if (!market.adminLiquidityClaimed && market.adminInitialLiquidity > 0) {
            refundAmount = market.adminInitialLiquidity;
            market.adminLiquidityClaimed = true;

            if (!bettingToken.transfer(market.creator, refundAmount)) revert TransferFailed();
        }

        emit MarketInvalidated(_marketId, msg.sender, refundAmount);
    }

    // Trading Functions
    function claimFreeTokens(uint256 _marketId)
        external
        nonReentrant
        whenNotPaused
        validMarket(_marketId)
        marketActive(_marketId)
    {
        Market storage market = markets[_marketId];
        if (market.marketType != MarketType.FREE_ENTRY) revert NotFreeMarket();
        if (!market.freeConfig.isActive) revert FreeEntryInactive();
        if (market.freeConfig.hasClaimedFree[msg.sender]) revert AlreadyClaimedFree();
        if (market.freeConfig.currentFreeParticipants >= market.freeConfig.maxFreeParticipants) revert FreeSlotseFull();
        if (market.freeConfig.remainingPrizePool < market.freeConfig.tokensPerParticipant) {
            revert InsufficientPrizePool();
        }

        uint256 freeTokens = market.freeConfig.tokensPerParticipant;

        // Update tracking
        market.freeConfig.hasClaimedFree[msg.sender] = true;
        market.freeConfig.tokensReceived[msg.sender] = freeTokens;
        market.freeConfig.currentFreeParticipants++;
        market.freeConfig.remainingPrizePool -= freeTokens;

        // Add user as participant if new
        if (_isNewParticipant(msg.sender, _marketId)) {
            market.participants.push(msg.sender);
            if (userPortfolios[msg.sender].totalInvested == 0) {
                allParticipants.push(msg.sender);
            }
        }

        // Transfer actual Buster tokens to user
        if (!bettingToken.transfer(msg.sender, freeTokens)) revert TransferFailed();

        // Update user portfolio (tokens received count as "investment" for tracking)
        userPortfolios[msg.sender].tradeCount++;

        emit FreeTokensClaimed(_marketId, msg.sender, freeTokens);
    }

    // AMM Swap Function
    function ammSwap(
        uint256 _marketId,
        uint256 _optionIdIn,
        uint256 _optionIdOut,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) external nonReentrant whenNotPaused validMarket(_marketId) marketActive(_marketId) returns (uint256 amountOut) {
        if (_optionIdIn == _optionIdOut) revert CannotSwapSameOption();
        if (_amountIn == 0) revert AmountMustBePositive();
        if (markets[_marketId].userShares[msg.sender][_optionIdIn] < _amountIn) revert InsufficientShares();

        Market storage market = markets[_marketId];
        MarketOption storage optionIn = market.options[_optionIdIn];
        MarketOption storage optionOut = market.options[_optionIdOut];

        // Calculate AMM swap using constant product formula: x * y = k
        uint256 reserveIn = optionIn.reserve;
        uint256 reserveOut = optionOut.reserve;

        // Apply AMM fee
        uint256 amountInWithFee = _amountIn * (10000 - AMM_FEE_RATE) / 10000;
        uint256 ammFee = _amountIn - amountInWithFee;

        // Track AMM fees for LP rewards
        market.ammFeesCollected += ammFee;

        // Calculate output amount: amountOut = (reserveOut * amountInWithFee) / (reserveIn + amountInWithFee)
        amountOut = (reserveOut * amountInWithFee) / (reserveIn + amountInWithFee);
        if (amountOut < _minAmountOut) revert InsufficientOutput();
        if (amountOut >= reserveOut) revert InsufficientLiquidity();

        // Update reserves
        optionIn.reserve += _amountIn;
        optionOut.reserve -= amountOut;

        // Update user shares
        market.userShares[msg.sender][_optionIdIn] -= _amountIn;
        market.userShares[msg.sender][_optionIdOut] += amountOut;

        // Update prices based on new reserves
        optionIn.currentPrice = (optionIn.k * 1e18) / optionIn.reserve;
        optionOut.currentPrice = (optionOut.k * 1e18) / optionOut.reserve;

        // Record price history
        priceHistory[_marketId][_optionIdIn].push(
            PricePoint({
                price: optionIn.currentPrice,
                timestamp: block.timestamp,
                volume: _amountIn * optionIn.currentPrice / 1e18
            })
        );

        priceHistory[_marketId][_optionIdOut].push(
            PricePoint({
                price: optionOut.currentPrice,
                timestamp: block.timestamp,
                volume: amountOut * optionOut.currentPrice / 1e18
            })
        );

        emit AMMSwap(_marketId, _optionIdIn, _optionIdOut, _amountIn, amountOut, msg.sender);
        return amountOut;
    }

    function buyShares(uint256 _marketId, uint256 _optionId, uint256 _quantity, uint256 _maxPricePerShare)
        external
        nonReentrant
        whenNotPaused
        validMarket(_marketId)
        marketActive(_marketId)
        validOption(_marketId, _optionId)
    {
        if (_quantity == 0) revert AmountMustBePositive();
        if (!markets[_marketId].validated) revert MarketNotValidated();

        Market storage market = markets[_marketId];
        MarketOption storage option = market.options[_optionId];

        // Use AMM cost calculation instead of flat pricing
        uint256 totalCost = calculateAMMBuyCost(_marketId, _optionId, _quantity);
        uint256 avgPricePerShare = totalCost * 1e18 / _quantity;
        if (avgPricePerShare > _maxPricePerShare) revert PriceTooHigh();

        if (!bettingToken.transferFrom(msg.sender, address(this), totalCost)) revert TransferFailed();

        // Update reserves BEFORE updating shares (critical for AMM)
        option.reserve = option.reserve > _quantity ? option.reserve - _quantity : option.reserve / 2;

        // Update user shares
        if (market.userShares[msg.sender][_optionId] == 0 && _isNewParticipant(msg.sender, _marketId)) {
            market.participants.push(msg.sender);
            if (userPortfolios[msg.sender].totalInvested == 0) {
                allParticipants.push(msg.sender);
            }
        }

        market.userShares[msg.sender][_optionId] += _quantity;
        option.totalShares += _quantity;

        // Extract fees from totalCost
        uint256 fee = totalCost * platformFeeRate / (10000 + platformFeeRate); // Extract fee from total
        uint256 netCostToMarket = totalCost - fee;

        option.totalVolume += netCostToMarket;
        market.userLiquidity += netCostToMarket; // Only non-fee amount goes to user liquidity
        market.totalVolume += netCostToMarket;
        market.platformFeesCollected += fee; // Track platform fees separately
        totalPlatformFeesCollected += fee; // Global platform fees

        // Update user portfolio
        userPortfolios[msg.sender].totalInvested += totalCost;
        userPortfolios[msg.sender].tradeCount++;

        // Update price based on new reserve (reserve already updated above)
        option.currentPrice = (option.k * 1e18) / option.reserve;

        // Record price history
        priceHistory[_marketId][_optionId].push(
            PricePoint({price: option.currentPrice, timestamp: block.timestamp, volume: netCostToMarket})
        );

        // Record trade
        Trade memory trade = Trade({
            marketId: _marketId,
            optionId: _optionId,
            buyer: msg.sender,
            seller: address(0), // Market maker
            price: option.currentPrice,
            quantity: _quantity,
            timestamp: block.timestamp
        });

        userTradeHistory[msg.sender].push(trade);
        marketTrades[_marketId].push(trade);

        emit TradeExecuted(_marketId, _optionId, msg.sender, address(0), option.currentPrice, _quantity, tradeCount++);
        emit FeeCollected(_marketId, fee);
    }

    function sellShares(uint256 _marketId, uint256 _optionId, uint256 _quantity, uint256 _minPricePerShare)
        external
        nonReentrant
        whenNotPaused
        validMarket(_marketId)
        marketActive(_marketId)
        validOption(_marketId, _optionId)
    {
        if (_quantity == 0) revert AmountMustBePositive();
        if (markets[_marketId].userShares[msg.sender][_optionId] < _quantity) revert InsufficientShares();

        Market storage market = markets[_marketId];
        MarketOption storage option = market.options[_optionId];

        // Use AMM revenue calculation instead of flat pricing
        uint256 netRevenue = calculateAMMSellRevenue(_marketId, _optionId, _quantity);
        uint256 avgPricePerShare = netRevenue * 1e18 / _quantity;
        if (avgPricePerShare < _minPricePerShare) revert PriceTooLow();

        // Update reserves BEFORE updating shares (critical for AMM)
        option.reserve = option.reserve + _quantity;

        // Update shares
        market.userShares[msg.sender][_optionId] -= _quantity;
        option.totalShares -= _quantity;

        // Extract fees for tracking
        uint256 grossRevenue = netRevenue * (10000 + platformFeeRate) / 10000;
        uint256 fee = grossRevenue - netRevenue;

        option.totalVolume += grossRevenue;
        market.totalVolume += grossRevenue;
        market.platformFeesCollected += fee; // Track platform fees separately
        totalPlatformFeesCollected += fee; // Global platform fees

        // Update price based on new reserve (reserve already updated above)
        option.currentPrice = (option.k * 1e18) / option.reserve;

        // Calculate P&L: (sell revenue - estimated cost basis) * quantity
        // For simplicity, we'll use current AMM pricing as cost basis approximation
        int256 pnl = int256(netRevenue) - int256(avgPricePerShare * _quantity / 1e18);
        userPortfolios[msg.sender].realizedPnL += pnl;
        userPortfolios[msg.sender].tradeCount++;

        // Record price history
        priceHistory[_marketId][_optionId].push(
            PricePoint({price: option.currentPrice, timestamp: block.timestamp, volume: grossRevenue})
        );

        // Record trade
        Trade memory trade = Trade({
            marketId: _marketId,
            optionId: _optionId,
            buyer: address(0), // Market maker
            seller: msg.sender,
            price: avgPricePerShare,
            quantity: _quantity,
            timestamp: block.timestamp
        });

        userTradeHistory[msg.sender].push(trade);
        marketTrades[_marketId].push(trade);

        if (!bettingToken.transfer(msg.sender, netRevenue)) revert TransferFailed();

        emit SharesSold(_marketId, _optionId, msg.sender, _quantity, avgPricePerShare);
        emit TradeExecuted(_marketId, _optionId, address(0), msg.sender, avgPricePerShare, _quantity, tradeCount++);
        emit FeeCollected(_marketId, fee);
    }

    // Market Resolution
    function resolveMarket(uint256 _marketId, uint256 _winningOptionId) external validMarket(_marketId) {
        if (msg.sender != owner() && !hasRole(QUESTION_RESOLVE_ROLE, msg.sender)) revert NotAuthorized();
        Market storage market = markets[_marketId];
        
        // NEW: Allow early resolution for event-based markets
        if (!market.earlyResolutionAllowed && block.timestamp < market.endTime) {
            revert MarketNotEndedYet();
        }
        
        // NEW: Prevent immediate resolution (require minimum 1 hour)
        if (market.earlyResolutionAllowed && block.timestamp < market.createdAt + 1 hours) {
            revert MarketTooNew();
        }
        
        if (market.resolved) revert MarketAlreadyResolved();
        if (_winningOptionId >= market.optionCount) revert InvalidWinningOption();

        market.winningOptionId = _winningOptionId;
        market.resolved = true;

        emit MarketResolved(_marketId, _winningOptionId, msg.sender);
    }

    function disputeMarket(uint256 _marketId, string memory _reason) external validMarket(_marketId) {
        if (!markets[_marketId].resolved) revert MarketNotResolved();
        if (markets[_marketId].disputed) revert AlreadyClaimed();
        if (markets[_marketId].userShares[msg.sender][markets[_marketId].winningOptionId] > 0) {
            revert CannotDisputeIfWon();
        }

        markets[_marketId].disputed = true;
        emit MarketDisputed(_marketId, msg.sender, _reason);
    }

    // Payout Functions
    function claimWinnings(uint256 _marketId) external nonReentrant validMarket(_marketId) {
        Market storage market = markets[_marketId];
        if (!market.resolved || market.disputed) revert MarketNotReady();
        if (market.invalidated) revert MarketIsInvalidated();
        if (market.hasClaimed[msg.sender]) revert AlreadyClaimed();

        uint256 userWinningShares = market.userShares[msg.sender][market.winningOptionId];
        if (userWinningShares == 0) revert NoWinningShares();

        uint256 totalWinningShares = market.options[market.winningOptionId].totalShares;
        if (totalWinningShares == 0) revert NoWinningShares(); // Prevent division by zero

        // Only distribute user liquidity, not admin liquidity or platform fees
        uint256 winningSharesValue = totalWinningShares * market.options[market.winningOptionId].currentPrice / 1e18;
        uint256 totalLosingValue = winningSharesValue > market.userLiquidity ? 0 : market.userLiquidity - winningSharesValue;

        uint256 winnings = (userWinningShares * market.options[market.winningOptionId].currentPrice / 1e18)
            + (userWinningShares * totalLosingValue / totalWinningShares);

        market.hasClaimed[msg.sender] = true;
        userPortfolios[msg.sender].totalWinnings += winnings;
        totalWinnings[msg.sender] += winnings;

        if (!bettingToken.transfer(msg.sender, winnings)) revert TransferFailed();
        emit Claimed(_marketId, msg.sender, winnings);
    }

    // Price Calculation Functions
    function calculateCurrentPrice(uint256 _marketId, uint256 _optionId) public view returns (uint256) {
        Market storage market = markets[_marketId];
        return market.options[_optionId].currentPrice;
    }

    function calculateNewPrice(uint256 _marketId, uint256 _optionId, uint256 _quantity, bool _isBuy)
        public
        view
        returns (uint256)
    {
        Market storage market = markets[_marketId];
        MarketOption storage option = market.options[_optionId];

        // Use AMM pricing model based on reserves
        uint256 reserve = option.reserve;
        uint256 k = option.k;

        if (_isBuy) {
            // When buying shares, more tokens flow into the pool → reserve increases → price decreases for that option
            // BUT: we want price to increase when demand increases, so we need to model this differently
            // In a prediction market: buying an option should increase its price (probability)
            // The reserve model should reflect token scarcity, not token abundance
            uint256 newReserve = reserve > _quantity ? reserve - _quantity : reserve / 2;
            return (k * 1e18) / newReserve;
        } else {
            // When selling shares, tokens flow out of the pool → reserve decreases → price increases
            // But selling should decrease the price, so we add to reserve instead
            uint256 newReserve = reserve + _quantity;
            return (k * 1e18) / newReserve;
        }
    }

    // Add AMM Liquidity
    function addAMMLiquidity(uint256 _marketId, uint256 _amount)
        external
        nonReentrant
        validMarket(_marketId)
        marketActive(_marketId)
    {
        if (_amount == 0) revert AmountMustBePositive();
        if (!bettingToken.transferFrom(msg.sender, address(this), _amount)) revert TransferFailed();

        Market storage market = markets[_marketId];
        market.ammLiquidityPool += _amount;

        // Track LP contribution
        if (market.lpContributions[msg.sender] == 0) {
            market.liquidityProviders.push(msg.sender);
        }
        market.lpContributions[msg.sender] += _amount;

        // Distribute liquidity across options proportionally
        uint256 amountPerOption = _amount / market.optionCount;
        for (uint256 i = 0; i < market.optionCount; i++) {
            market.options[i].k += amountPerOption;
            market.options[i].reserve += amountPerOption;
        }

        emit LiquidityAdded(_marketId, msg.sender, _amount);
    }

    function calculateSellPrice(uint256 _marketId, uint256 _optionId, uint256 _quantity)
        public
        view
        returns (uint256)
    {
        Market storage market = markets[_marketId];
        MarketOption storage option = market.options[_optionId];

        // Calculate sell price using AMM formula with 0.3% fee
        uint256 newReserve = option.reserve > _quantity ? option.reserve - _quantity : option.reserve / 2;
        uint256 newPrice = (option.k * 1e18) / newReserve;
        uint256 sellPrice = newPrice * _quantity / 1e18;

        // Apply 0.3% fee
        return sellPrice * 997 / 1000;
    }

    // AMM Cost Estimation Functions
    function calculateAMMBuyCost(uint256 _marketId, uint256 _optionId, uint256 _quantity)
        public
        view
        returns (uint256)
    {
        if (_quantity == 0) return 0;

        Market storage market = markets[_marketId];
        MarketOption storage option = market.options[_optionId];

        // Use AMM constant product formula to calculate true cost
        uint256 currentReserve = option.reserve;
        uint256 k = option.k;

        // Calculate new reserve after removing shares (buying reduces reserve)
        uint256 newReserve = currentReserve > _quantity ? currentReserve - _quantity : currentReserve / 2;

        // Calculate total cost using price difference
        // Cost = quantity * average_price = quantity * (current_price + new_price) / 2
        uint256 currentPrice = (k * 1e18) / currentReserve;
        uint256 newPrice = (k * 1e18) / newReserve;
        uint256 avgPrice = (currentPrice + newPrice) / 2;
        uint256 totalCost = (_quantity * avgPrice) / 1e18;

        // Add platform fee
        uint256 fee = totalCost * platformFeeRate / 10000;
        return totalCost + fee;
    }

    function calculateAMMSellRevenue(uint256 _marketId, uint256 _optionId, uint256 _quantity)
        public
        view
        returns (uint256)
    {
        if (_quantity == 0) return 0;

        Market storage market = markets[_marketId];
        MarketOption storage option = market.options[_optionId];

        // Use AMM constant product formula to calculate true revenue
        uint256 currentReserve = option.reserve;
        uint256 k = option.k;

        // Calculate new reserve after adding shares (selling increases reserve)
        uint256 newReserve = currentReserve + _quantity;

        // Calculate total revenue using price difference
        // Revenue = quantity * average_price = quantity * (current_price + new_price) / 2
        uint256 currentPrice = (k * 1e18) / currentReserve;
        uint256 newPrice = (k * 1e18) / newReserve;
        uint256 avgPrice = (currentPrice + newPrice) / 2;
        uint256 totalRevenue = (_quantity * avgPrice) / 1e18;

        // Subtract platform fee
        uint256 fee = totalRevenue * platformFeeRate / 10000;
        return totalRevenue > fee ? totalRevenue - fee : 0;
    }

    // Get current market odds for all options
    function getMarketOdds(uint256 _marketId) external view validMarket(_marketId) returns (uint256[] memory) {
        Market storage market = markets[_marketId];
        uint256[] memory odds = new uint256[](market.optionCount);

        uint256 totalLiquidity = 0;
        for (uint256 i = 0; i < market.optionCount; i++) {
            totalLiquidity += market.options[i].k;
        }

        for (uint256 i = 0; i < market.optionCount; i++) {
            odds[i] = (market.options[i].k * 1e18) / totalLiquidity;
        }

        return odds;
    }

    // Emergency functions
    function pauseMarket(uint256 _marketId) external onlyOwner validMarket(_marketId) {
        markets[_marketId].resolved = true;
        emit MarketPaused(_marketId);
    }

    function updateBettingTokenAddress(address _newToken) external onlyOwner {
        if (_newToken == address(0)) revert InvalidToken();
        previousBettingToken = address(bettingToken);
        bettingToken = IERC20(_newToken);
        tokenUpdatedAt = block.timestamp;

        emit BettingTokenUpdated(previousBettingToken, _newToken, block.timestamp);
    }

    // NEW: Platform Fee Management
    function withdrawPlatformFees() external nonReentrant {
        if (msg.sender != feeCollector && msg.sender != owner()) revert NotAuthorized();
        if (totalPlatformFeesCollected == 0) revert NoFeesToWithdraw();

        uint256 feesToWithdraw = totalPlatformFeesCollected;
        totalPlatformFeesCollected = 0;

        if (!bettingToken.transfer(feeCollector, feesToWithdraw)) revert TransferFailed();
        emit PlatformFeesWithdrawn(feeCollector, feesToWithdraw);
    }

    // NEW: Admin Liquidity Recovery
    function withdrawAdminLiquidity(uint256 _marketId) external nonReentrant validMarket(_marketId) {
        Market storage market = markets[_marketId];
        if (msg.sender != market.creator) revert NotAuthorized();
        if (!market.resolved && !market.invalidated) revert MarketNotResolved();
        if (market.adminLiquidityClaimed) revert AdminLiquidityAlreadyClaimed();
        if (market.adminInitialLiquidity == 0) revert AmountMustBePositive();

        uint256 liquidityToReturn = market.adminInitialLiquidity;
        market.adminLiquidityClaimed = true;

        if (!bettingToken.transfer(market.creator, liquidityToReturn)) revert TransferFailed();
        emit AdminLiquidityWithdrawn(_marketId, market.creator, liquidityToReturn);
    }

    // NEW: Withdraw unused prize pool from free markets
    function withdrawUnusedPrizePool(uint256 _marketId) external nonReentrant validMarket(_marketId) {
        Market storage market = markets[_marketId];
        if (msg.sender != market.creator) revert NotAuthorized();
        if (market.marketType != MarketType.FREE_ENTRY) revert NotFreeMarket();
        if (!market.resolved) revert MarketNotResolved();
        if (market.freeConfig.remainingPrizePool == 0) revert AmountMustBePositive();

        uint256 unusedTokens = market.freeConfig.remainingPrizePool;
        market.freeConfig.remainingPrizePool = 0;

        if (!bettingToken.transfer(market.creator, unusedTokens)) revert TransferFailed();
        emit AdminLiquidityWithdrawn(_marketId, market.creator, unusedTokens); // Reuse event
    }

    // NEW: LP Rewards Claiming
    function claimLPRewards(uint256 _marketId) external nonReentrant validMarket(_marketId) {
        Market storage market = markets[_marketId];
        if (market.lpContributions[msg.sender] == 0) revert NotLiquidityProvider();
        if (market.lpRewardsClaimed[msg.sender]) revert AlreadyClaimed();
        if (market.ammFeesCollected == 0) revert NoLPRewards();

        // Calculate LP's share of AMM fees based on their contribution
        uint256 totalLPContributions = market.ammLiquidityPool;
        uint256 lpShare = (market.lpContributions[msg.sender] * market.ammFeesCollected) / totalLPContributions;

        if (lpShare == 0) revert NoLPRewards();

        market.lpRewardsClaimed[msg.sender] = true;
        lpRewardsEarned[msg.sender] += lpShare;

        if (!bettingToken.transfer(msg.sender, lpShare)) revert TransferFailed();
        emit LPRewardsClaimed(_marketId, msg.sender, lpShare);
    }

    // Helper Functions
    function _isNewParticipant(address _user, uint256 _marketId) internal view returns (bool) {
        Market storage market = markets[_marketId];
        for (uint256 i = 0; i < market.optionCount; i++) {
            if (market.userShares[_user][i] > 0) {
                return false;
            }
        }
        return true;
    }

    // View Functions
    // View Functions
    function getMarketInfo(uint256 _marketId)
        external
        view
        validMarket(_marketId)
        returns (
            string memory question,
            string memory description,
            uint256 endTime,
            MarketCategory category,
            uint256 optionCount,
            bool resolved,
            bool disputed,
            MarketType marketType,
            bool invalidated,
            uint256 winningOptionId,
            address creator,
            bool earlyResolutionAllowed // NEW return value
        )
    {
        Market storage market = markets[_marketId];
        return (
            market.question,
            market.description,
            market.endTime,
            market.category,
            market.optionCount,
            market.resolved,
            market.disputed,
            market.marketType,
            market.invalidated,
            market.winningOptionId,
            market.creator,
            market.earlyResolutionAllowed // NEW return value
        );
    }

    function getMarketOption(uint256 _marketId, uint256 _optionId)
        external
        view
        validMarket(_marketId)
        returns (
            string memory name,
            string memory description,
            uint256 totalShares,
            uint256 totalVolume,
            uint256 currentPrice,
            bool isActive
        )
    {
        MarketOption storage option = markets[_marketId].options[_optionId];
        return (
            option.name,
            option.description,
            option.totalShares,
            option.totalVolume,
            option.currentPrice,
            option.isActive
        );
    }

    function getUserShares(uint256 _marketId, address _user)
        external
        view
        validMarket(_marketId)
        returns (uint256[] memory)
    {
        Market storage market = markets[_marketId];
        uint256[] memory shares = new uint256[](market.optionCount);
        for (uint256 i = 0; i < market.optionCount; i++) {
            shares[i] = market.userShares[_user][i];
        }
        return shares;
    }

    function getUserPortfolio(address _user) external view returns (UserPortfolio memory) {
        return userPortfolios[_user];
    }

    function getPriceHistory(uint256 _marketId, uint256 _optionId, uint256 _limit)
        external
        view
        returns (PricePoint[] memory)
    {
        PricePoint[] storage history = priceHistory[_marketId][_optionId];
        uint256 length = history.length;
        uint256 returnLength = _limit > length ? length : _limit;

        PricePoint[] memory result = new PricePoint[](returnLength);
        uint256 startIndex = length > _limit ? length - _limit : 0;

        for (uint256 i = 0; i < returnLength; i++) {
            result[i] = history[startIndex + i];
        }

        return result;
    }

    function getMarketsByCategory(MarketCategory _category, uint256 _limit) external view returns (uint256[] memory) {
        uint256[] storage categoryMarketIds = categoryMarkets[_category];
        uint256 length = categoryMarketIds.length;
        uint256 returnLength = _limit > length ? length : _limit;

        uint256[] memory result = new uint256[](returnLength);
        uint256 startIndex = length > _limit ? length - _limit : 0;

        for (uint256 i = 0; i < returnLength; i++) {
            result[i] = categoryMarketIds[startIndex + i];
        }

        return result;
    }

    function getMarketCount() external view returns (uint256) {
        return marketCount;
    }

    function getBettingToken() external view returns (address) {
        return address(bettingToken);
    }

    // NEW: Get market financial breakdown
    function getMarketFinancials(uint256 _marketId)
        external
        view
        validMarket(_marketId)
        returns (
            uint256 adminInitialLiquidity,
            uint256 userLiquidity,
            uint256 platformFeesCollected,
            uint256 ammFeesCollected,
            bool adminLiquidityClaimed
        )
    {
        Market storage market = markets[_marketId];
        return (
            market.adminInitialLiquidity,
            market.userLiquidity,
            market.platformFeesCollected,
            market.ammFeesCollected,
            market.adminLiquidityClaimed
        );
    }

    // NEW: Get LP information for a market
    function getLPInfo(uint256 _marketId, address _lp)
        external
        view
        validMarket(_marketId)
        returns (uint256 contribution, bool rewardsClaimed, uint256 estimatedRewards)
    {
        Market storage market = markets[_marketId];
        contribution = market.lpContributions[_lp];
        rewardsClaimed = market.lpRewardsClaimed[_lp];

        estimatedRewards = 0;
        if (contribution > 0 && market.ammLiquidityPool > 0) {
            estimatedRewards = (contribution * market.ammFeesCollected) / market.ammLiquidityPool;
        }

        return (contribution, rewardsClaimed, estimatedRewards);
    }

    // NEW: Get global platform statistics
    function getPlatformStats()
        external
        view
        returns (uint256 totalFeesCollected, address currentFeeCollector, uint256 totalMarkets, uint256 totalTrades)
    {
        return (totalPlatformFeesCollected, feeCollector, marketCount, tradeCount);
    }

    // NEW: Get free market configuration
    function getFreeMarketInfo(uint256 _marketId)
        external
        view
        validMarket(_marketId)
        returns (
            uint256 maxFreeParticipants,
            uint256 tokensPerParticipant,
            uint256 currentFreeParticipants,
            uint256 totalPrizePool,
            uint256 remainingPrizePool,
            bool isActive
        )
    {
        Market storage market = markets[_marketId];
        if (market.marketType != MarketType.FREE_ENTRY) revert NotFreeMarket();

        return (
            market.freeConfig.maxFreeParticipants,
            market.freeConfig.tokensPerParticipant,
            market.freeConfig.currentFreeParticipants,
            market.freeConfig.totalPrizePool,
            market.freeConfig.remainingPrizePool,
            market.freeConfig.isActive
        );
    }

    // NEW: Check if user claimed free market tokens
    function hasUserClaimedFreeTokens(uint256 _marketId, address _user)
        external
        view
        validMarket(_marketId)
        returns (bool, uint256)
    {
        Market storage market = markets[_marketId];
        if (market.marketType != MarketType.FREE_ENTRY) revert NotFreeMarket();

        return (market.freeConfig.hasClaimedFree[_user], market.freeConfig.tokensReceived[_user]);
    }

    function hasUserClaimedWinnings(uint256 _marketId, address _user)
        external
        view
        validMarket(_marketId)
        returns (bool)
    {
        return markets[_marketId].hasClaimed[_user];
    }

    // /**
    //  * @dev Batch distribute winnings to multiple users at once (admin only)
    //  * @param _marketId The market ID to distribute winnings for
    //  * @param _recipients Array of addresses to distribute winnings to
    //  */
    // function batchDistributeWinnings(uint256 _marketId, address[] calldata _recipients)
    //     external
    //     nonReentrant
    //     validMarket(_marketId)
    //     onlyOwner
    // {
    //     if (_recipients.length == 0) revert EmptyBatchList();

    //     Market storage market = markets[_marketId];
    //     if (!market.resolved || market.disputed) revert MarketNotReady();

    //     uint256 totalDistributed = 0;
    //     uint256 successfulDistributions = 0;

    //     uint256 totalWinningShares = market.options[market.winningOptionId].totalShares;
    //     uint256 winningSharesValue = totalWinningShares * market.options[market.winningOptionId].currentPrice / 1e18;
    //     uint256 totalLosingValue = winningSharesValue > market.userLiquidity ? 0 : market.userLiquidity - winningSharesValue;

    //     for (uint256 i = 0; i < _recipients.length; i++) {
    //         address recipient = _recipients[i];

    //         // Skip if already claimed or no winning shares
    //         if (market.hasClaimed[recipient]) continue;

    //         uint256 userWinningShares = market.userShares[recipient][market.winningOptionId];
    //         if (userWinningShares == 0) continue;

    //         // Calculate winnings using same formula as claimWinnings
    //         uint256 winnings = (userWinningShares * market.options[market.winningOptionId].currentPrice / 1e18)
    //             + (userWinningShares * totalLosingValue / totalWinningShares);

    //         // Mark as claimed and update portfolios
    //         market.hasClaimed[recipient] = true;
    //         userPortfolios[recipient].totalWinnings += winnings;
    //         totalWinnings[recipient] += winnings;

    //         // Transfer tokens
    //         if (bettingToken.transfer(recipient, winnings)) {
    //             totalDistributed += winnings;
    //             successfulDistributions++;
    //             emit WinningsDistributedToUser(_marketId, recipient, winnings);
    //         } else {
    //             // Revert the claim status if transfer failed
    //             market.hasClaimed[recipient] = false;
    //             userPortfolios[recipient].totalWinnings -= winnings;
    //             totalWinnings[recipient] -= winnings;
    //         }
    //     }

    //     if (successfulDistributions == 0) revert BatchDistributionFailed();

    //     emit BatchWinningsDistributed(_marketId, totalDistributed, successfulDistributions);
    // }

    function getUserWinnings(uint256 _marketId, address _user)
        external
        view
        validMarket(_marketId)
        returns (bool hasWinnings, uint256 amount)
    {
        Market storage market = markets[_marketId];
        if (!market.resolved || market.disputed) return (false, 0);
        if (market.hasClaimed[_user]) return (false, 0);

        uint256 userWinningShares = market.userShares[_user][market.winningOptionId];
        if (userWinningShares == 0) return (false, 0);

        uint256 totalWinningShares = market.options[market.winningOptionId].totalShares;
        uint256 winningSharesValue = totalWinningShares * market.options[market.winningOptionId].currentPrice / 1e18;
        uint256 totalLosingValue = winningSharesValue > market.userLiquidity ? 0 : market.userLiquidity - winningSharesValue;

        amount = (userWinningShares * market.options[market.winningOptionId].currentPrice / 1e18)
            + (userWinningShares * totalLosingValue / totalWinningShares);

        hasWinnings = true;
    }

    // NEW: Get comprehensive market status
    function getMarketStatus(uint256 _marketId) external view validMarket(_marketId) returns (
        bool isActive,
        bool isResolved,
        bool isExpired,
        bool canTrade,
        bool canResolve,
        uint256 timeRemaining
    ) {
        Market storage market = markets[_marketId];
        isActive = !market.resolved && !market.invalidated && block.timestamp < market.endTime;
        isExpired = block.timestamp >= market.endTime && !market.resolved;
        canTrade = isActive && market.validated;
        canResolve = market.validated && (market.earlyResolutionAllowed || block.timestamp >= market.endTime);
        timeRemaining = block.timestamp >= market.endTime ? 0 : market.endTime - block.timestamp;

        return (isActive, market.resolved, isExpired, canTrade, canResolve, timeRemaining);
    }

    // NEW: Get market timing information
    function getMarketTiming(uint256 _marketId) external view validMarket(_marketId) returns (
        uint256 createdAt,
        uint256 endTime,
        uint256 timeRemaining,
        bool isExpired,
        bool canResolveEarly
    ) {
        Market storage market = markets[_marketId];
        timeRemaining = block.timestamp >= market.endTime ? 0 : market.endTime - block.timestamp;
        isExpired = block.timestamp >= market.endTime;
        canResolveEarly = market.earlyResolutionAllowed && block.timestamp >= market.createdAt + 1 hours;

        return (market.createdAt, market.endTime, timeRemaining, isExpired, canResolveEarly);
    }

    // NEW: Get all markets where user has participated
    function getUserMarkets(address _user) external view returns (uint256[] memory) {
        uint256[] memory tempMarkets = new uint256[](marketCount);
        uint256 count = 0;

        for (uint256 i = 0; i < marketCount; i++) {
            Market storage market = markets[i];
            // Check if user has any shares in this market
            bool hasParticipated = false;
            for (uint256 j = 0; j < market.optionCount; j++) {
                if (market.userShares[_user][j] > 0) {
                    hasParticipated = true;
                    break;
                }
            }
            if (hasParticipated) {
                tempMarkets[count] = i;
                count++;
            }
        }

        // Create properly sized array
        uint256[] memory userMarkets = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            userMarkets[i] = tempMarkets[i];
        }

        return userMarkets;
    }

    // NEW: Check if market is tradable
    function isMarketTradable(uint256 _marketId) external view validMarket(_marketId) returns (bool) {
        Market storage market = markets[_marketId];
        return market.validated && !market.resolved && !market.invalidated &&
               block.timestamp < market.endTime;
    }

    // NEW: Get market participants
    function getMarketParticipants(uint256 _marketId) external view validMarket(_marketId) returns (
        address[] memory participants,
        uint256 participantCount
    ) {
        Market storage market = markets[_marketId];
        return (market.participants, market.participants.length);
    }

    // NEW: Get unresolved markets for admin
    function getUnresolvedMarkets() external view returns (uint256[] memory) {
        uint256[] memory tempMarkets = new uint256[](marketCount);
        uint256 count = 0;

        for (uint256 i = 0; i < marketCount; i++) {
            Market storage market = markets[i];
            if (!market.resolved && market.validated && !market.invalidated) {
                tempMarkets[count] = i;
                count++;
            }
        }

        uint256[] memory unresolvedMarkets = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            unresolvedMarkets[i] = tempMarkets[i];
        }

        return unresolvedMarkets;
    }

    // NEW: Get event-based markets
    function getEventBasedMarkets() external view returns (uint256[] memory) {
        uint256[] memory tempMarkets = new uint256[](marketCount);
        uint256 count = 0;

        for (uint256 i = 0; i < marketCount; i++) {
            Market storage market = markets[i];
            if (market.earlyResolutionAllowed) {
                tempMarkets[count] = i;
                count++;
            }
        }

        uint256[] memory eventMarkets = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            eventMarkets[i] = tempMarkets[i];
        }

        return eventMarkets;
    }
    /**
     * @dev Get winnings amount for specific users
     * @param _marketId The market ID to check
     * @param _users Array of addresses to check
     * @return recipients Array of addresses eligible for winnings
     * @return amounts Array of corresponding winning amounts
     */

    // function getEligibleWinners(uint256 _marketId, address[] calldata _users)
    //     external
    //     view
    //     validMarket(_marketId)
    //     returns (address[] memory recipients, uint256[] memory amounts)
    // {
    //     Market storage market = markets[_marketId];
    //     if (!market.resolved || market.disputed) revert MarketNotReady();

    //     // Count eligible recipients first
    //     uint256 eligibleCount = 0;
    //     uint256 totalWinningShares = market.options[market.winningOptionId].totalShares;
    //     uint256 winningSharesValue = totalWinningShares * market.options[market.winningOptionId].currentPrice / 1e18;
    //     uint256 totalLosingValue = winningSharesValue > market.userLiquidity ? 0 : market.userLiquidity - winningSharesValue;

    //     // First pass: count eligible users
    //     for (uint256 i = 0; i < _users.length; i++) {
    //         address user = _users[i];
    //         if (!market.hasClaimed[user] && market.userShares[user][market.winningOptionId] > 0) {
    //             eligibleCount++;
    //         }
    //     }

    //     // Initialize arrays
    //     recipients = new address[](eligibleCount);
    //     amounts = new uint256[](eligibleCount);

    //     // Second pass: populate arrays
    //     uint256 index = 0;
    //     for (uint256 i = 0; i < _users.length; i++) {
    //         address user = _users[i];
    //         if (!market.hasClaimed[user] && market.userShares[user][market.winningOptionId] > 0) {
    //             uint256 userWinningShares = market.userShares[user][market.winningOptionId];
    //             uint256 winnings = (userWinningShares * market.options[market.winningOptionId].currentPrice / 1e18)
    //                 + (userWinningShares * totalLosingValue / totalWinningShares);

    //             recipients[index] = user;
    //             amounts[index] = winnings;
    //             index++;
    //         }
    //     }
    // }
}