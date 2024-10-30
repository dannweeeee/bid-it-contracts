// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DutchAuction} from "./DutchAuction.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

error AuctionNotFound();
error InvalidParameters();

/**
 * @title Auctioneer
 * @author @Dann Wee
 * @notice Factory contract for creating and managing Dutch auctions
 */
contract Auctioneer is Ownable {
    DutchAuction[] public auctions;

    mapping(address => bool) public isValidAuction;
    mapping(address => AuctionInfo) public auctionDetails;

    struct AuctionInfo {
        string name;
        string symbol;
        uint256 createdAt;
        bool isActive;
        uint256 totalEthRaised;
        uint256 totalTokensSold;
        uint256 auctionDuration;
    }

    event AuctionCreated(
        address indexed auctionAddress,
        string name,
        string symbol,
        uint256 totalSupply,
        uint256 initialPrice,
        uint256 reservePrice
    );
    event AuctionPaused(address indexed auctionAddress);
    event AuctionUnpaused(address indexed auctionAddress);

    constructor() Ownable(msg.sender) {}

    ///////////////////////////////
    /// ADMINISTRATIVE FUNCTIONS //
    ///////////////////////////////

    /**
     * @notice Create a new Dutch auction with custom duration
     */
    function createAuction(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        uint256 _initialPrice,
        uint256 _reservePrice,
        uint256 _minimumBid,
        uint256 _auctionDuration // New: Custom duration parameter
    ) external onlyOwner returns (address) {
        if (_totalSupply == 0 || _initialPrice <= _reservePrice || _minimumBid == 0) {
            revert InvalidParameters();
        }

        DutchAuction newAuction =
            new DutchAuction(_name, _symbol, _totalSupply, _initialPrice, _reservePrice, _minimumBid);

        auctions.push(newAuction);
        isValidAuction[address(newAuction)] = true;

        auctionDetails[address(newAuction)] = AuctionInfo({
            name: _name,
            symbol: _symbol,
            createdAt: block.timestamp,
            isActive: true,
            totalEthRaised: 0,
            totalTokensSold: 0,
            auctionDuration: _auctionDuration
        });

        emit AuctionCreated(address(newAuction), _name, _symbol, _totalSupply, _initialPrice, _reservePrice);

        return address(newAuction);
    }

    /**
     * @notice Administrative function to pause an auction
     */
    function pauseAuction(address _auctionAddress) external onlyOwner {
        if (!isValidAuction[_auctionAddress]) revert AuctionNotFound();

        DutchAuction auction = DutchAuction(_auctionAddress);
        auction.pause();

        emit AuctionPaused(_auctionAddress);
    }

    /**
     * @notice Administrative function to unpause an auction
     */
    function unpauseAuction(address _auctionAddress) external onlyOwner {
        if (!isValidAuction[_auctionAddress]) revert AuctionNotFound();

        DutchAuction auction = DutchAuction(_auctionAddress);
        auction.unpause();

        emit AuctionUnpaused(_auctionAddress);
    }

    /**
     * @notice Start an auction
     */
    function startAuction(address _auctionAddress) external onlyOwner {
        if (!isValidAuction[_auctionAddress]) revert AuctionNotFound();

        DutchAuction auction = DutchAuction(_auctionAddress);
        auction.startAuction();
    }

    /**
     * @notice End an auction
     */
    function endAuction(address _auctionAddress) external onlyOwner {
        if (!isValidAuction[_auctionAddress]) revert AuctionNotFound();

        DutchAuction auction = DutchAuction(_auctionAddress);
        auction.endAuction();
        auctionDetails[_auctionAddress].isActive = false;
    }

    ///////////////////////////////
    /////// GETTER FUNCTIONS //////
    ///////////////////////////////

    /**
     * @notice Get all active auctions
     */
    function getActiveAuctions() external view returns (address[] memory) {
        uint256 activeCount = 0;

        // First, count active auctions
        for (uint256 i = 0; i < auctions.length; i++) {
            if (auctionDetails[address(auctions[i])].isActive) {
                activeCount++;
            }
        }

        // Create result array
        address[] memory activeAuctions = new address[](activeCount);
        uint256 currentIndex = 0;

        // Fill result array
        for (uint256 i = 0; i < auctions.length; i++) {
            if (auctionDetails[address(auctions[i])].isActive) {
                activeAuctions[currentIndex] = address(auctions[i]);
                currentIndex++;
            }
        }

        return activeAuctions;
    }

    /**
     * @notice Get total number of auctions created
     */
    function getTotalAuctions() external view returns (uint256) {
        return auctions.length;
    }

    /**
     * @notice Get comprehensive auction information
     */
    function getAuctionInfo(address _auctionAddress)
        external
        view
        returns (
            string memory name,
            string memory symbol,
            uint256 createdAt,
            bool isActive,
            bool isStarted,
            bool isEnded,
            uint256 currentPrice,
            uint256 remainingTokens,
            uint256 timeRemaining,
            uint256 totalEthRaised,
            uint256 totalTokensSold
        )
    {
        if (!isValidAuction[_auctionAddress]) revert AuctionNotFound();

        AuctionInfo memory info = auctionDetails[_auctionAddress];
        DutchAuction auction = DutchAuction(_auctionAddress);

        (isStarted, isEnded, currentPrice, remainingTokens, timeRemaining) = auction.getAuctionStatus();

        return (
            info.name,
            info.symbol,
            info.createdAt,
            info.isActive,
            isStarted,
            isEnded,
            currentPrice,
            remainingTokens,
            timeRemaining,
            info.totalEthRaised,
            info.totalTokensSold
        );
    }
}
