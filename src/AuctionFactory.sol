// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./Auction.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import {console} from "forge-std/console.sol";

/**
 * @title AuctionFactory
 * @author Dann Wee
 * @notice This contract is used to create and manage auctions
 */
contract AuctionFactory is AccessControl {
    bytes32 public constant AUCTION_CREATOR_ROLE = keccak256("AUCTION_CREATOR_ROLE");

    address[] public auctions;
    bool public isPaused;

    event NewAuction(address indexed auctionAddress, string name, string symbol);
    event AuctionRemoved(address indexed auctionAddress);
    event FactoryPaused(bool isPaused);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(AUCTION_CREATOR_ROLE, msg.sender);
    }

    /**
     * @notice Function to create a new auction
     * @param _name The name of the auction
     * @param _symbol The symbol of the auction
     * @param _decimals The decimals of the auction
     * @param _quantity The quantity of the auction
     * @param _startingPrice The starting price of the auction
     * @param _discountRate The discount rate of the auction
     * @param _lowestPossibleBid The lowest possible bid of the auction
     * @param _start The start time of the auction
     * @param _owner The owner of the auction
     * @return address The address of the new auction
     */
    function createAuction(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _quantity,
        uint256 _startingPrice,
        uint256 _discountRate,
        uint256 _lowestPossibleBid,
        uint256 _start,
        address _owner
    ) public onlyRole(AUCTION_CREATOR_ROLE) returns (address) {
        require(!isPaused, "Auction creation is paused");

        Auction newAuction = new Auction(
            _name, _symbol, _decimals, _quantity, _startingPrice, _discountRate, _lowestPossibleBid, _start, _owner
        );
        address auctionAddress = address(newAuction);
        auctions.push(auctionAddress);

        emit NewAuction(auctionAddress, _name, _symbol);
        return auctionAddress;
    }

    /**
     * @notice Function to remove an auction
     * @param index The index of the auction to remove
     */
    function removeAuction(uint256 index) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(index < auctions.length, "Invalid index");
        address auctionToRemove = auctions[index];
        auctions[index] = auctions[auctions.length - 1];
        auctions.pop();
        emit AuctionRemoved(auctionToRemove);
    }

    /**
     * @notice Function to toggle the pause state of the factory
     */
    function togglePause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        isPaused = !isPaused;
        emit FactoryPaused(isPaused);
    }

    ///////////////////////////////
    /////// GETTER FUNCTIONS //////
    ///////////////////////////////

    /**
     * @notice Function to get all auctions
     * @return address[] memory The addresses of all auctions
     */
    function getAuctions() public view returns (address[] memory) {
        return auctions;
    }

    /**
     * @notice Function to get the number of auctions
     * @return uint256 The number of auctions
     */
    function getAuctionCount() public view returns (uint256) {
        return auctions.length;
    }

    /**
     * @notice Function to get the details of an auction
     * @param index The index of the auction
     * @return address The address of the auction
     * @return string memory The name of the auction
     * @return string memory The symbol of the auction
     * @return uint256 The quantity of the auction
     * @return uint256 The starting price of the auction
     * @return uint256 The start time of the auction
     */
    function getAuctionDetails(uint256 index)
        public
        view
        returns (address, string memory, string memory, uint256, uint256, uint256)
    {
        require(index < auctions.length, "Invalid index");
        Auction auction = Auction(auctions[index]);
        return (
            auctions[index],
            auction.token().name(),
            auction.token().symbol(),
            auction.getQuantity(),
            auction.startingPrice(),
            auction.start()
        );
    }
}
