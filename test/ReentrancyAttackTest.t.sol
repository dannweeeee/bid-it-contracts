// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {DutchAuction} from "../src/DutchAuction.sol";
import {Token} from "../src/Token.sol";

/**
 * @title ReentrancyAttacker
 * @author @dannweeeee
 * @notice This contract is used to test the reentrancy attack on the Dutch Auction
 */
contract ReentrancyAttacker {
    DutchAuction public auction;
    uint256 public attackCount;
    uint256 public targetAmount;

    constructor(address _auction) {
        auction = DutchAuction(_auction);
    }

    /**
     * @notice Function to start the attack
     * @param _tokenAmount The amount of tokens to bid for
     */
    function attack(uint256 _tokenAmount) external payable {
        targetAmount = _tokenAmount;
        // Initial bid
        auction.bid{value: msg.value}(_tokenAmount);
    }

    /**
     * @notice Fallback function to perform the reentrant attack
     */
    receive() external payable {
        if (address(auction).balance >= msg.value && attackCount < 3) {
            attackCount++;
            // Try to reenter the bid function
            auction.bid{value: msg.value}(targetAmount);
        }
    }
}
/**
 * @title ReentrancyAttackTest
 * @author @dannweeeee
 * @notice This contract is used to test the reentrancy attack on the Dutch Auction
 */

contract ReentrancyAttackTest is Test {
    DutchAuction public auction;
    ReentrancyAttacker public attacker;
    address public owner;
    address public alice;
    address public bob;

    /**
     * @notice Setup function to initialize the test
     */
    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        vm.prank(owner);
        auction = new DutchAuction(
            "Test Token",
            "TEST",
            1000 ether, // total supply
            2 ether, // initial price
            1 ether, // reserve price
            0.1 ether, // minimum bid
            owner
        );

        attacker = new ReentrancyAttacker(address(auction));

        vm.prank(owner);
        auction.startAuction();
    }

    /**
     * @notice Test the reentrancy attack on the bid function
     */
    function test_ReentrancyAttackBidFunction() public {
        vm.deal(address(attacker), 10 ether);

        uint256 initialAttackerBalance = address(attacker).balance;

        uint256 tokenAmount = 1 ether;
        uint256 bidAmount = 2 ether;

        vm.expectRevert();
        attacker.attack{value: bidAmount}(tokenAmount);

        // Verify that the attack was unsuccessful
        assertEq(auction.totalTokensSold(), 0, "Tokens should not have been sold during attack");
        assertEq(attacker.attackCount(), 0, "Attack count should remain 0");
        assertEq(address(attacker).balance, initialAttackerBalance, "Attacker balance should remain unchanged");
    }

    /**
     * @notice Test the legitimate multiple bids
     */
    function test_LegitimateMultipleBids() public {
        vm.deal(alice, 1000000 ether);
        vm.deal(bob, 1000000 ether);

        uint256 tokenAmount = 1000; // 1000 tokens
        uint256 currentPrice = auction.getCurrentPrice();
        uint256 totalCost = currentPrice * tokenAmount; // Divide by 1e18 to handle decimals

        // Alice's bid
        vm.startPrank(alice);
        auction.bid{value: totalCost}(tokenAmount);
        vm.stopPrank();

        // Bob's bid
        vm.startPrank(bob);
        currentPrice = auction.getCurrentPrice();
        totalCost = currentPrice * tokenAmount;
        auction.bid{value: totalCost}(tokenAmount);
        vm.stopPrank();

        // Verify the total tokens sold
        assertEq(auction.totalTokensSold(), 2000, "Total tokens sold should be correct");
    }

    /**
     * @notice Test the reentrancy attack on the withdraw function
     */
    function test_ReentrancyAttackWithdraw() public {
        vm.deal(address(auction), 5 ether);

        // End the auction to enable withdrawals
        vm.warp(block.timestamp + 21 minutes);
        vm.prank(owner);
        auction.endAuction();

        // Attempt to attack the withdraw function
        uint256 initialBalance = address(auction).balance;

        vm.prank(owner);
        auction.withdrawEth();

        assertEq(address(auction).balance, 0, "All ETH should be withdrawn");
        assertEq(owner.balance, initialBalance, "Owner should receive all ETH");
    }

    function test_ReentrancyGuardPause() public {
        // Test that pause/unpause functions are protected
        vm.startPrank(owner);
        auction.pause();

        // Attempt to bid while paused
        vm.deal(alice, 2 ether);
        vm.expectRevert();
        vm.prank(alice);
        auction.bid{value: 2 ether}(1 ether);

        // Unpause and verify bid works
        auction.unpause();
        vm.stopPrank();

        vm.prank(alice);
        auction.bid{value: 2 ether}(1 ether);

        assertEq(auction.totalTokensSold(), 1 ether, "Bid should succeed after unpause");
    }
}
