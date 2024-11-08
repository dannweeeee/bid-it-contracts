// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {DutchAuction} from "../src/DutchAuction.sol";
import {Token} from "../src/Token.sol";

contract MaliciousContract {
    DutchAuction public auction;
    uint256 public attackCount;
    uint256 public constant ATTACK_ROUNDS = 3;

    constructor(address _auctionAddress) {
        auction = DutchAuction(_auctionAddress);
    }

    // Function to start the attack
    function attack() external payable {
        require(msg.value >= 1 ether, "Need ETH for attack");
        auction.bid{value: 1 ether}();
    }

    // Fallback function to perform the reentrancy attack
    receive() external payable {
        if (attackCount < ATTACK_ROUNDS && address(auction).balance >= 1 ether) {
            attackCount++;
            auction.bid{value: 1 ether}();
        }
    }
}

contract ReentrancyAttackTest is Test {
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

    function testReentrancyAttack() public {
        // Start the auction
        vm.prank(owner);
        auction.startAuction();

        // Deploy malicious contract
        MaliciousContract attacker = new MaliciousContract(address(auction));

        // Fund the attacker contract
        vm.deal(address(attacker), 5 ether);

        // Record initial balances
        uint256 initialAuctionBalance = address(auction).balance;

        // Perform the attack
        vm.prank(address(attacker));
        attacker.attack{value: 1 ether}();

        // Verify that only one bid succeeded due to reentrancy guard
        assertEq(attacker.attackCount(), 0, "Reentrancy guard should prevent multiple bids");
        assertEq(address(auction).balance, initialAuctionBalance + 1 ether, "Only one bid should succeed");
    }
}
