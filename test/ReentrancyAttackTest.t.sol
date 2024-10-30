// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DutchAuction} from "../src/DutchAuction.sol";
import {Token} from "../src/Token.sol";

/**
 * @title Malicious Contract
 * @author Dann Wee
 * @notice This contract is used to mimic a malicious contract that attempts reentrancy attacks.
 */
contract MaliciousContract {
    DutchAuction public auction;
    uint256 public attackCount;
    uint256 public constant ATTACK_LOOPS = 2;
    bool public attacking;

    constructor(DutchAuction _auction) {
        auction = _auction;
    }

    /**
     * Fallback function to attempt reentrancy on ETH refund
     */
    receive() external payable {
        if (attackCount < ATTACK_LOOPS) {
            attackCount++;
            // Try to reenter bid function
            auction.bid{value: 1 ether}();
        }
    }

    /**
     * @notice Attack the bid function
     */
    function attackBid() external payable {
        require(msg.value >= 1 ether, "Need ETH for attack");
        auction.bid{value: 1 ether}();
    }

    /**
     * @notice Attack the claim function
     */
    function attackClaim() external {
        auction.claimTokens();
    }

    /**
     * @notice Get the claimable tokens
     */
    function getClaimableTokens() external view returns (uint256) {
        return auction.claimableTokens(address(this));
    }
}

/**
 * @title Reentrancy Attack Test
 * @author Dann Wee
 * @notice This contract is used to test reentrancy attacks on the DutchAuction contract.
 */
contract ReentrancyAttackTest is Test {
    DutchAuction public auction;
    Token public token;
    MaliciousContract public attacker;

    // Add receive function to accept ETH
    receive() external payable {}

    /**
     * @notice Set up the test
     */
    function setUp() public {
        // Deploy contracts
        auction = new DutchAuction(
            "Test Token",
            "TEST",
            1000 ether, // total supply
            1 ether, // initial price
            0.1 ether, // reserve price
            0.1 ether // minimum bid
        );
        attacker = new MaliciousContract(auction);

        // Start auction
        auction.startAuction();
    }

    /**
     * @notice Test the bid reentrancy attack
     */
    function testBidReentrancy() public {
        // Fund attacker
        vm.deal(address(attacker), 5 ether);

        // Record initial state
        uint256 initialBalance = address(auction).balance;
        console.log("Initial balance: %s", initialBalance);
        uint256 initialTokensForSale = auction.totalTokensForSale();
        console.log("Initial tokens for sale: %s", initialTokensForSale);

        // Perform attack
        attacker.attackBid{value: 1 ether}();

        // Verify state consistency
        assertEq(auction.userBids(address(attacker)), 1 ether, "Bid amount should only be counted once");
        assertTrue(auction.totalTokensForSale() < initialTokensForSale, "Tokens for sale should decrease only once");
    }

    /**
     * @notice Test the claim reentrancy attack
     */
    function testClaimReentrancy() public {
        // First make a legitimate bid
        vm.deal(address(attacker), 2 ether);
        attacker.attackBid{value: 1 ether}();

        // Fast forward to end of auction
        skip(21 minutes);
        auction.endAuction();

        // Record initial claimable tokens
        uint256 initialClaimable = attacker.getClaimableTokens();
        require(initialClaimable > 0, "Setup failed: No tokens to claim");

        // Attempt claim attack
        attacker.attackClaim();

        // Verify tokens were only claimed once
        assertEq(attacker.getClaimableTokens(), 0, "Tokens should only be claimed once");
    }

    /**
     * @notice Test the withdraw reentrancy attack
     */
    function testWithdrawReentrancy() public {
        // Fund contract and make a bid
        vm.deal(address(this), 2 ether);
        auction.bid{value: 2 ether}();

        // Fast forward and end auction
        skip(21 minutes);
        auction.endAuction();

        // Record initial balance
        uint256 initialBalance = address(auction).balance;
        assertTrue(initialBalance > 0, "Contract should have ETH balance");

        // Attempt withdraw as owner
        auction.withdrawEth();

        // Verify complete withdrawal
        assertEq(address(auction).balance, 0, "Contract should be empty after withdrawal");
    }

    /**
     * @notice Test the auction state
     */
    function testAuctionState() public {
        // Initial state checks
        assertEq(address(auction).balance, 0, "Initial balance should be 0");
        assertEq(auction.totalTokensForSale(), 1000 ether, "Initial tokens for sale incorrect");

        // Make a bid
        vm.deal(address(this), 1 ether);
        auction.bid{value: 1 ether}();

        // Check state after bid
        assertEq(auction.userBids(address(this)), 1 ether, "Bid not recorded correctly");

        // End auction
        skip(21 minutes);
        auction.endAuction();

        // Check final state
        assertTrue(auction.auctionEnded(), "Auction should be ended");
    }
}
