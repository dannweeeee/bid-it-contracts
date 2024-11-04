// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {DutchAuction} from "../src/DutchAuction.sol";

contract DutchAuctionTest is Test {
    DutchAuction public auction;
    address public owner;
    address public bidder;

    // Custom errors
    error BidTooLow();
    error PriceNotMet();
    error AuctionNotStarted();
    error NotEnoughTokens();
    error AuctionAlreadyEnded();

    uint256 public constant INITIAL_PRICE = 1 ether;
    uint256 public constant RESERVE_PRICE = 0.1 ether;
    uint256 public constant TOTAL_SUPPLY = 1000;
    uint256 public constant MINIMUM_BID = 0.1 ether;

    function setUp() public {
        owner = makeAddr("owner");
        bidder = makeAddr("bidder");

        vm.startPrank(owner);
        auction = new DutchAuction("TestToken", "TEST", TOTAL_SUPPLY, INITIAL_PRICE, RESERVE_PRICE, MINIMUM_BID, owner);
        auction.startAuction();
        vm.stopPrank();

        // Fund bidder with ETH
        vm.deal(bidder, 100 ether);
    }

    function test_BidSuccessful() public {
        vm.startPrank(bidder);

        uint256 quantity = 5;
        uint256 currentPrice = auction.getCurrentPrice();
        uint256 totalCost = quantity * currentPrice;

        auction.bid{value: totalCost}(quantity);

        assertEq(auction.claimableTokens(bidder), quantity);
        assertEq(auction.totalTokensSold(), quantity);
        assertEq(auction.totalTokensForSale(), TOTAL_SUPPLY - quantity);
        assertEq(auction.totalEthRaised(), totalCost);
        assertTrue(auction.isBidder(bidder));

        vm.stopPrank();
    }

    function test_RevertWhen_BidTooLow() public {
        vm.startPrank(bidder);

        uint256 quantity = 1;
        uint256 lowBidAmount = MINIMUM_BID - 1;

        vm.expectRevert(BidTooLow.selector);
        auction.bid{value: lowBidAmount}(quantity);

        vm.stopPrank();
    }

    function test_RevertWhen_InsufficientPayment() public {
        vm.startPrank(bidder);

        uint256 quantity = 5;
        uint256 currentPrice = auction.getCurrentPrice();
        uint256 totalCost = quantity * currentPrice;
        uint256 insufficientPayment = totalCost - 0.1 ether;

        vm.expectRevert(PriceNotMet.selector);
        auction.bid{value: insufficientPayment}(quantity);

        vm.stopPrank();
    }

    function test_RevertWhen_AuctionNotStarted() public {
        // Deploy new auction without starting it
        vm.startPrank(owner);
        DutchAuction newAuction =
            new DutchAuction("TestToken", "TEST", TOTAL_SUPPLY, INITIAL_PRICE, RESERVE_PRICE, MINIMUM_BID, owner);
        vm.stopPrank();

        vm.startPrank(bidder);
        vm.expectRevert(AuctionNotStarted.selector);
        newAuction.bid{value: 1 ether}(1);
        vm.stopPrank();
    }

    function test_RevertWhen_QuantityTooHigh() public {
        vm.startPrank(bidder);

        uint256 quantity = TOTAL_SUPPLY + 1;
        uint256 sendAmount = 1 ether;

        vm.expectRevert(NotEnoughTokens.selector);
        auction.bid{value: sendAmount}(quantity);

        vm.stopPrank();
    }

    function test_RevertWhen_AuctionEnded() public {
        // Fast forward to end of auction
        vm.warp(block.timestamp + auction.AUCTION_DURATION() + 1);

        // End the auction first
        vm.prank(owner);
        auction.endAuction();

        vm.startPrank(bidder);
        vm.expectRevert(AuctionAlreadyEnded.selector);
        auction.bid{value: 1 ether}(1);
        vm.stopPrank();
    }

    function test_RefundExcessPayment() public {
        vm.startPrank(bidder);

        uint256 quantity = 1;
        uint256 currentPrice = auction.getCurrentPrice();
        uint256 totalCost = quantity * currentPrice;
        uint256 excessPayment = totalCost + 0.5 ether;

        uint256 balanceBefore = bidder.balance;
        auction.bid{value: excessPayment}(quantity);
        uint256 balanceAfter = bidder.balance;

        assertEq(balanceAfter, balanceBefore - totalCost);

        vm.stopPrank();
    }
}
