// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Token} from "./Token.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

error AuctionNotStarted();
error AuctionAlreadyStarted();
error AuctionNotEnded();
error AuctionAlreadyEnded();
error PriceNotMet();
error InvalidBid();
error InvalidAmount();
error NothingToClaim();
error NotEnoughTokens();
error BidTooLow();
error TransferFailed();
error RefundFailed();
error InvalidPrice();

contract DutchAuction is ReentrancyGuard, Pausable, Ownable {
    Token public token;

    uint256 public initialPrice;
    uint256 public currentPrice;
    uint256 public reservePrice;
    uint256 public startTime;
    uint256 public endTime;
    uint256 public immutable AUCTION_DURATION = 20 minutes;
    uint256 public discountRate;
    uint256 public totalTokensForSale;
    uint256 public totalEthRaised;
    uint256 public totalTokensSold;
    uint256 public minimumBid;
    bool public auctionEnded;

    mapping(address => uint256) public userBids;
    mapping(address => uint256) public claimableTokens;
    mapping(address => bool) public hasClaimedTokens;

    event Bid(address indexed bidder, uint256 ethAmount, uint256 tokenAmount, uint256 price);
    event AuctionStarted(uint256 startTime, uint256 endTime, uint256 startingPrice);
    event AuctionEnded(uint256 finalPrice, uint256 tokensSold, uint256 ethRaised);
    event TokensClaimed(address indexed bidder, uint256 amount);
    event EthWithdrawn(address indexed owner, uint256 amount);

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        uint256 _initialPrice,
        uint256 _reservePrice,
        uint256 _minimumBid
    ) ReentrancyGuard() Pausable() Ownable(msg.sender) {
        if (_initialPrice <= _reservePrice) revert InvalidPrice();
        if (_totalSupply == 0) revert InvalidAmount();
        if (_minimumBid == 0) revert InvalidAmount();
        if (_initialPrice == 0) revert InvalidPrice();

        token = new Token(_name, _symbol, _totalSupply, address(this));
        initialPrice = _initialPrice;
        reservePrice = _reservePrice;
        totalTokensForSale = _totalSupply;
        minimumBid = _minimumBid;

        // Calculate discount rate with better precision
        discountRate = (_initialPrice - _reservePrice) / AUCTION_DURATION;
        if (discountRate == 0) revert InvalidPrice();
    }

    function startAuction() external onlyOwner {
        if (auctionEnded) revert AuctionAlreadyEnded();
        if (startTime != 0) revert AuctionAlreadyStarted();

        startTime = block.timestamp;
        endTime = startTime + AUCTION_DURATION;

        emit AuctionStarted(startTime, endTime, initialPrice);
    }

    function calculatePrice(uint256 _quantity) public view returns (uint256) {
        uint256 price = getCurrentPrice();
        return price * _quantity;
    }

    function bid(uint256 _quantity) public payable nonReentrant whenNotPaused {
        if (startTime == 0) revert AuctionNotStarted();
        if (block.timestamp >= endTime) revert AuctionAlreadyEnded();
        if (_quantity == 0) revert InvalidBid();
        if (_quantity > totalTokensForSale) revert NotEnoughTokens();

        // Price calculation
        currentPrice = getCurrentPrice();
        uint256 totalCost = calculatePrice(_quantity);

        // Payment validation
        if (msg.value < minimumBid) revert BidTooLow();
        if (msg.value < totalCost) revert PriceNotMet();

        // Process refund if necessary
        if (msg.value > totalCost) {
            uint256 refundAmount = msg.value - totalCost;
            (bool success,) = msg.sender.call{value: refundAmount}("");
            if (!success) revert RefundFailed();
        }

        userBids[msg.sender] += totalCost;
        claimableTokens[msg.sender] += _quantity;
        totalTokensForSale -= _quantity;
        totalTokensSold += _quantity;
        totalEthRaised += totalCost;

        emit Bid(msg.sender, totalCost, _quantity, currentPrice);
    }

    function claimTokens() external nonReentrant {
        if (!auctionEnded) revert AuctionNotEnded();

        uint256 tokensToClaim = claimableTokens[msg.sender];
        if (tokensToClaim == 0) revert NothingToClaim();

        claimableTokens[msg.sender] = 0;
        hasClaimedTokens[msg.sender] = true;

        bool success = token.transfer(msg.sender, tokensToClaim);
        if (!success) revert TransferFailed();

        emit TokensClaimed(msg.sender, tokensToClaim);
    }

    function bulkClaimTokens(address[] calldata _bidders) external onlyOwner nonReentrant {
        if (!auctionEnded) revert AuctionNotEnded();

        for (uint256 i = 0; i < _bidders.length; i++) {
            address bidder = _bidders[i];
            uint256 tokensToClaim = claimableTokens[bidder];

            if (tokensToClaim > 0 && !hasClaimedTokens[bidder]) {
                claimableTokens[bidder] = 0;
                hasClaimedTokens[bidder] = true;
                bool success = token.transfer(bidder, tokensToClaim);
                if (!success) revert TransferFailed();
                emit TokensClaimed(bidder, tokensToClaim);
            }
        }
    }

    function endAuction() external onlyOwner {
        if (startTime == 0) revert AuctionNotStarted();
        if (block.timestamp < endTime && totalTokensForSale > 0) revert AuctionNotEnded();
        if (auctionEnded) revert AuctionAlreadyEnded();

        auctionEnded = true;

        // Burn remaining tokens if any
        if (totalTokensForSale > 0) {
            token.burn(totalTokensForSale);
        }

        emit AuctionEnded(getCurrentPrice(), totalTokensSold, totalEthRaised);
    }

    function withdrawEth() external onlyOwner nonReentrant {
        if (!auctionEnded) revert AuctionNotEnded();

        uint256 balance = address(this).balance;
        if (balance == 0) revert NothingToClaim();

        (bool success,) = owner().call{value: balance}("");
        if (!success) revert TransferFailed();

        emit EthWithdrawn(owner(), balance);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function getCurrentPrice() public view returns (uint256) {
        if (block.timestamp < startTime) return initialPrice;
        if (block.timestamp >= endTime) return reservePrice;

        uint256 timeElapsed = block.timestamp - startTime;
        uint256 discount = discountRate * timeElapsed;
        return initialPrice - discount;
    }

    function getAuctionStatus()
        external
        view
        returns (
            bool isStarted,
            bool isEnded,
            uint256 currentTokenPrice,
            uint256 remainingTokens,
            uint256 timeRemaining
        )
    {
        isStarted = startTime != 0;
        isEnded = auctionEnded;
        currentTokenPrice = getCurrentPrice();
        remainingTokens = totalTokensForSale;
        timeRemaining = block.timestamp >= endTime ? 0 : endTime - block.timestamp;
    }
}
