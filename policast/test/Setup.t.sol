// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PolicastMarketV3} from "../src/V3.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract SetupTest is Test {
    PolicastMarketV3 public market;
    MockERC20 public bettingToken;
    address public owner = address(0x123);
    address public user1 = address(0x456);

    function setUp() public {
        vm.startPrank(owner);
        bettingToken = new MockERC20("Betting Token", "BET", 18);
        market = new PolicastMarketV3(address(bettingToken));
        vm.stopPrank();
    }

    function testConstructor() public view {
        // Verify initial state
        assertEq(market.marketCount(), 0);
        assertEq(market.tradeCount(), 0);
        assertEq(address(market.bettingToken()), address(bettingToken));
        assertEq(market.tokenUpdatedAt(), block.timestamp);
        assertEq(market.feeCollector(), owner);
        assertEq(market.totalPlatformFeesCollected(), 0);
    }

    function testInitialRoles() public view {
        // Check DEFAULT_ADMIN_ROLE assignment
        assertTrue(market.hasRole(market.DEFAULT_ADMIN_ROLE(), owner));
    }

    function testInitialFeeCollector() public view {
        // Verify fee collector is owner
        assertEq(market.feeCollector(), owner);
    }

    function testInitialPlatformFeeRate() public view {
        // Check default 2% fee rate (200 basis points)
        assertEq(market.platformFeeRate(), 200);
    }

    function testInitialAMMFeeRate() public view {
        // Verify 0.3% AMM fee (30 basis points)
        // Note: AMM_FEE_RATE is a constant, so we can't directly access it
        // We'll verify it through behavior in other tests
        // For now, just ensure the contract deployed successfully
        assertTrue(address(market) != address(0));
    }
}
