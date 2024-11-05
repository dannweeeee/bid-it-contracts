// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {DutchAuction} from "../src/DutchAuction.sol";
import {Token} from "../src/Token.sol";

contract MaliciousContract {
    DutchAuction public auction;
    uint256 public attackCount;
    uint256 public bidQuantity;

    constructor(address _auction) {
        auction = DutchAuction(_auction);
    }

    // Fallback function that attempts to reenter the bid function
    receive() external payable {
        if (attackCount < 3) {
            // Limit attack attempts to prevent infinite loops
            attackCount++;
            // Try to bid again when receiving refund
            auction.bid{value: msg.value}(bidQuantity);
        }
    }

    // Function to initiate the attack
    function attack(uint256 _quantity) external payable {
        bidQuantity = _quantity;
        auction.bid{value: msg.value}(_quantity);
    }
}

contract ReentrancyAttackTest is Test {
    DutchAuction public auction;
    MaliciousContract public attacker;
    address public owner;
    address public auctioneer;
    address public alice;

    function setUp() public {
        owner = makeAddr("owner");
        auctioneer = makeAddr("auctioneer");
        alice = makeAddr("alice");

        // Deploy Dutch Auction with initial parameters
        auction = new DutchAuction(
            "Test Token",
            "TEST",
            1000, // total supply
            1 ether, // initial price
            0.1 ether, // reserve price
            0.1 ether, // minimum bid
            owner,
            auctioneer
        );

        // Deploy attacker contract
        attacker = new MaliciousContract(address(auction));

        // Start auction
        vm.prank(owner);
        auction.startAuction();
    }

    function testReentrancyAttack() public {
        // Fund attacker contract
        vm.deal(address(attacker), 10 ether);

        // Record initial state
        uint256 initialTokensForSale = auction.totalTokensForSale();

        // Attempt reentrancy attack
        uint256 bidQuantity = 1 ether;
        uint256 currentPrice = auction.getCurrentPrice();
        uint256 bidAmount = bidQuantity * currentPrice;

        vm.expectRevert();
        attacker.attack{value: bidAmount}(bidQuantity);

        // Verify state after attack
        assertEq(
            auction.totalTokensForSale(),
            initialTokensForSale,
            "Reentrancy attack should not affect total tokens for sale"
        );
        assertEq(attacker.attackCount(), 0, "Reentrancy attack should not increment attack counter");
    }

    function testMultipleBidsLegitimate() public {
        // Fund alice
        vm.deal(alice, 50 ether);

        // Make multiple legitimate bids
        vm.startPrank(alice);

        uint256 bidQuantity = 10;
        uint256 currentPrice = auction.getCurrentPrice();
        uint256 bidAmount = bidQuantity * currentPrice;

        auction.bid{value: bidAmount}(bidQuantity);
        auction.bid{value: bidAmount}(bidQuantity);

        vm.stopPrank();

        // Verify legitimate multiple bids work
        assertEq(auction.claimableTokens(alice), 20);
    }
}
