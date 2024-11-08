// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {DutchAuction} from "../src/DutchAuction.sol";
import {Token} from "../src/Token.sol";

error AuctionNotEnded();

contract DutchAuctionTest is Test {
    DutchAuction public auction;
    Token public token;
    address public owner;
    address public auctioneer;
    address public alice;
    address public bob;

    function setUp() public {
        owner = makeAddr("owner");
        auctioneer = makeAddr("auctioneer");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        vm.startPrank(owner);
        auction = new DutchAuction("Test Token", "TEST", 1000, 1 ether, 0.1 ether, 0.1 ether, owner, auctioneer);

        (,,,, address tokenAddress,) = auction.getTokenDetails();
        token = Token(tokenAddress);
        vm.stopPrank();
    }

    function testMultipleBidsLegitimate() public {
        vm.prank(owner);
        auction.startAuction();

        // Fund bidders
        vm.deal(alice, 50 ether);
        vm.deal(bob, 50 ether);

        // Alice bids 1 ETH
        vm.prank(alice);
        auction.bid{value: 1 ether}();

        // Bob bids 2 ETH
        vm.prank(bob);
        auction.bid{value: 2 ether}();

        // Alice bids another 1.5 ETH
        vm.prank(alice);
        auction.bid{value: 1.5 ether}();

        // Fast forward to end
        vm.warp(1201);

        vm.prank(owner);
        auction.endAuction();

        uint256 clearingPrice = auction.clearingPrice();
        uint256 aliceTokens = token.balanceOf(alice);

        // Verify clearing price and token distribution
        assertEq(clearingPrice, 0.1 ether, "Clearing price should be reserve price");
        assertApproxEqRel(aliceTokens, 25 ether, 0.01e18, "Alice should receive proportional tokens");
    }

    function testPriceDecline() public {
        vm.prank(owner);
        auction.startAuction();

        uint256 initialPrice = auction.getCurrentPrice();

        // Check price after 1 minute (halfway)
        vm.warp(block.timestamp + 1 minutes);
        uint256 midPrice = auction.getCurrentPrice();

        // Check final price - need to warp to end of auction
        vm.warp(block.timestamp + 10 minutes); // Warp further to ensure we reach end
        uint256 finalPrice = auction.getCurrentPrice();

        assertTrue(initialPrice > midPrice, "Price should decrease from start to mid");
        assertTrue(midPrice > finalPrice, "Price should decrease from mid to end");
        assertEq(finalPrice, auction.reservePrice(), "Final price should be reserve price");
    }

    function testRefundMechanism() public {
        vm.prank(owner);
        auction.startAuction();

        vm.deal(alice, 10 ether);

        // Alice bids at high price
        vm.prank(alice);
        auction.bid{value: 5 ether}();

        // Fast forward to end (lower price)
        vm.warp(121);

        vm.prank(owner);
        vm.expectRevert(AuctionNotEnded.selector);
        auction.endAuction();
    }

    function testAuctionEndConditions() public {
        vm.prank(owner);
        auction.startAuction();

        // Try ending too early
        vm.expectRevert(AuctionNotEnded.selector);
        vm.prank(owner);
        auction.endAuction();

        // Fast forward to middle of auction
        vm.warp(61);

        vm.expectRevert(AuctionNotEnded.selector);
        vm.prank(owner);
        auction.endAuction();

        // Fast forward to near end but not quite
        vm.warp(121);

        vm.expectRevert(AuctionNotEnded.selector);
        vm.prank(owner);
        auction.endAuction();

        // Fast forward past end
        vm.warp(182);

        vm.prank(owner);
        auction.endAuction();

        assertTrue(auction.auctionEnded());
    }
}
