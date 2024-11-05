// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {DutchAuction} from "../src/DutchAuction.sol";
import {Token} from "../src/Token.sol";

error MsgValueTooLow();

contract DutchAuctionTest is Test {
    DutchAuction public auction;
    address public owner;
    address public bidder1;
    address public bidder2;
    address public auctioneer;

    // Auction parameters
    string constant NAME = "Test Token";
    string constant SYMBOL = "TEST";
    uint256 constant TOTAL_SUPPLY = 1000;
    uint256 constant INITIAL_PRICE = 1 ether;
    uint256 constant RESERVE_PRICE = 0.1 ether;
    uint256 constant MINIMUM_BID = 0.01 ether;

    function setUp() public {
        owner = makeAddr("owner");
        bidder1 = makeAddr("bidder1");
        bidder2 = makeAddr("bidder2");
        auctioneer = makeAddr("auctioneer");

        // Fund test accounts
        vm.deal(bidder1, 100 ether);
        vm.deal(bidder2, 100 ether);

        vm.prank(owner);
        auction =
            new DutchAuction(NAME, SYMBOL, TOTAL_SUPPLY, INITIAL_PRICE, RESERVE_PRICE, MINIMUM_BID, owner, auctioneer);
    }

    function test_InitialState() public view {
        assertEq(auction.initialPrice(), INITIAL_PRICE);
        assertEq(auction.reservePrice(), RESERVE_PRICE);
        assertEq(auction.minimumBid(), MINIMUM_BID);
        assertEq(auction.totalTokensForSale(), TOTAL_SUPPLY);
        assertEq(auction.auctionEnded(), false);
        assertEq(auction.startTime(), 0);
    }

    function test_StartAuction() public {
        vm.prank(owner);
        auction.startAuction();

        assertGt(auction.startTime(), 0);
        assertEq(auction.endTime(), auction.startTime() + auction.AUCTION_DURATION());
    }

    function testFail_StartAuctionNotOwner() public {
        vm.prank(bidder1);
        auction.startAuction();
    }

    function test_Bid() public {
        vm.prank(owner);
        auction.startAuction();

        uint256 tokenAmount = 10;
        uint256 currentPrice = auction.getCurrentPrice();
        uint256 bidAmount = currentPrice * tokenAmount / 1 ether;

        vm.prank(bidder1);
        auction.bid{value: bidAmount * 1 ether}(tokenAmount);

        assertEq(auction.userBids(bidder1), bidAmount);
        assertEq(auction.claimableTokens(bidder1), tokenAmount);
        assertTrue(auction.isBidder(bidder1));
    }

    function testFail_BidBeforeStart() public {
        vm.prank(bidder1);
        auction.bid{value: 1 ether}(1 ether);
    }

    function testFail_BidTooLow() public {
        vm.prank(owner);
        auction.startAuction();

        vm.prank(bidder1);
        auction.bid{value: 0.001 ether}(1 ether);
    }

    function test_GetCurrentPrice() public {
        vm.prank(owner);
        auction.startAuction();

        // Price at start should be initial price
        assertEq(auction.getCurrentPrice(), INITIAL_PRICE);

        // Move time halfway through auction
        vm.warp(auction.startTime() + (auction.AUCTION_DURATION() / 2));

        // Price should be halfway between initial and reserve
        uint256 expectedMidPrice = INITIAL_PRICE
            - ((INITIAL_PRICE - RESERVE_PRICE) * (block.timestamp - auction.startTime())) / auction.AUCTION_DURATION();
        assertEq(auction.getCurrentPrice(), expectedMidPrice);

        // Move time to end
        vm.warp(auction.startTime() + auction.AUCTION_DURATION());

        // Price at end should be reserve price
        assertEq(auction.getCurrentPrice(), RESERVE_PRICE);
    }

    function test_EndAuction() public {
        vm.prank(owner);
        auction.startAuction();

        // Move time past auction duration
        vm.warp(block.timestamp + auction.AUCTION_DURATION() + 1);

        vm.prank(owner);
        auction.endAuction();

        assertTrue(auction.auctionEnded());
    }

    function test_MultipleBids() public {
        vm.prank(owner);
        auction.startAuction();

        // First bid
        uint256 currentPrice = auction.getCurrentPrice();
        uint256 tokenAmount1 = 10;
        uint256 bidAmount1 = currentPrice * tokenAmount1 / 1 ether;

        // Intentionally send less ETH than required
        uint256 insufficientBidAmount1 = bidAmount1 / 2; // Send half of required amount

        vm.prank(bidder1);
        vm.expectRevert(MsgValueTooLow.selector);
        auction.bid{value: insufficientBidAmount1}(tokenAmount1);

        // Second bid
        uint256 tokenAmount2 = 20;
        uint256 bidAmount2 = currentPrice * tokenAmount2 / 1 ether;
        uint256 insufficientBidAmount2 = bidAmount2 / 2; // Send half of required amount

        vm.prank(bidder2);
        vm.expectRevert(MsgValueTooLow.selector);
        auction.bid{value: insufficientBidAmount2}(tokenAmount2);

        assertEq(auction.totalTokensSold(), 0);
        assertEq(auction.claimableTokens(bidder1), 0);
        assertEq(auction.claimableTokens(bidder2), 0);
    }

    function test_PauseUnpause() public {
        vm.startPrank(owner);
        auction.pause();
        assertTrue(auction.paused());

        auction.unpause();
        assertFalse(auction.paused());
        vm.stopPrank();
    }

    function testFail_BidWhenPaused() public {
        vm.prank(owner);
        auction.startAuction();

        vm.prank(owner);
        auction.pause();

        vm.prank(bidder1);
        auction.bid{value: 1 ether}(1 ether);
    }

    function test_WithdrawEth() public {
        vm.prank(owner);
        auction.startAuction();

        // Place a bid
        uint256 tokenAmount = 10;
        uint256 totalCost = auction.calculatePrice(tokenAmount);

        vm.prank(bidder1);
        auction.bid{value: totalCost * 1 ether}(tokenAmount);

        // End auction
        vm.warp(block.timestamp + auction.AUCTION_DURATION() + 1);
        vm.prank(owner);
        auction.endAuction();

        // Record owner's balance before withdrawal
        uint256 balanceBefore = owner.balance;

        // Withdraw ETH
        vm.prank(owner);
        auction.withdrawEth();

        // Verify owner received the ETH
        assertGt(owner.balance, balanceBefore);
    }

    receive() external payable {}
}
