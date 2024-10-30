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

/**
 * @title Dutch Auction
 * @author @Dann Wee
 * @notice A Dutch auction contract for a token sale.
 */
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

    /**
     * @param _name The name of the token.
     * @param _symbol The symbol of the token.
     * @param _totalSupply The total supply of the token.
     * @param _initialPrice The initial price of the token.
     * @param _reservePrice The reserve price of the token.
     * @param _minimumBid The minimum bid amount.
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        uint256 _initialPrice,
        uint256 _reservePrice,
        uint256 _minimumBid
    ) ReentrancyGuard() Pausable() Ownable(msg.sender) {
        if (_initialPrice <= _reservePrice) revert InvalidBid();
        if (_totalSupply == 0) revert InvalidBid();
        if (_minimumBid == 0) revert InvalidAmount();

        token = new Token(_name, _symbol, _totalSupply, address(this));
        initialPrice = _initialPrice;
        reservePrice = _reservePrice;
        totalTokensForSale = _totalSupply;
        minimumBid = _minimumBid;

        // Improve precision in price calculation
        discountRate = (_initialPrice - _reservePrice) / AUCTION_DURATION;
    }

    /**
     * @notice Start the auction.
     */
    function startAuction() external onlyOwner {
        if (auctionEnded) revert AuctionAlreadyEnded();
        if (startTime != 0) revert AuctionAlreadyStarted();

        startTime = block.timestamp;
        endTime = startTime + AUCTION_DURATION;

        emit AuctionStarted(startTime, endTime, initialPrice);
    }

    /**
     * @notice End the auction.
     */
    function endAuction() external onlyOwner {
        if (startTime == 0) revert AuctionNotStarted();
        if (block.timestamp < endTime && totalTokensForSale > 0) revert AuctionNotEnded();
        if (auctionEnded) revert AuctionAlreadyEnded();

        auctionEnded = true;

        // Burn remaining tokens if any
        if (totalTokensForSale > 0) {
            token.burn(totalTokensForSale);
        }

        emit AuctionEnded(getCurrentPrice(), token.initialSupply() - totalTokensForSale, totalEthRaised);
    }

    /**
     * @notice Place a bid.
     */
    function bid() public payable nonReentrant whenNotPaused {
        if (startTime == 0) revert AuctionNotStarted();
        if (block.timestamp >= endTime) revert AuctionAlreadyEnded();
        if (msg.value < minimumBid) revert BidTooLow();

        currentPrice = getCurrentPrice();

        uint256 tokenAmount = msg.value / currentPrice;

        if (tokenAmount == 0) revert InvalidBid();

        if (tokenAmount > totalTokensForSale) {
            uint256 actualCost = (totalTokensForSale * currentPrice);
            uint256 refundAmount = msg.value - actualCost;
            tokenAmount = totalTokensForSale;

            // Refund excess ETH
            (bool success,) = msg.sender.call{value: refundAmount}("");
            if (!success) revert RefundFailed();
        }

        userBids[msg.sender] += msg.value;
        claimableTokens[msg.sender] += tokenAmount;
        totalTokensForSale -= tokenAmount;
        totalTokensSold += tokenAmount;
        totalEthRaised += msg.value;

        emit Bid(msg.sender, msg.value, tokenAmount, currentPrice);
    }

    /**
     * @notice Claim tokens.
     */
    function claimTokens() external nonReentrant {
        if (!auctionEnded) revert AuctionNotEnded();

        uint256 tokensToClaim = claimableTokens[msg.sender];
        if (tokensToClaim == 0) revert NothingToClaim();

        claimableTokens[msg.sender] = 0;
        bool success = token.transfer(msg.sender, tokensToClaim);
        if (!success) revert TransferFailed();

        emit TokensClaimed(msg.sender, tokensToClaim);
    }

    /**
     * @notice Bulk claim tokens for gas optimization.
     */
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

    /**
     * @notice Withdraw ETH from the contract.
     */
    function withdrawEth() external onlyOwner nonReentrant {
        if (!auctionEnded) revert AuctionNotEnded();

        uint256 balance = address(this).balance;
        if (balance == 0) revert NothingToClaim();

        (bool success,) = owner().call{value: balance}("");
        if (!success) revert TransferFailed();

        emit EthWithdrawn(owner(), balance);
    }

    /**
     * @notice Pause the auction.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the auction.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    ///////////////////////////////
    /////// GETTER FUNCTIONS //////
    ///////////////////////////////

    /**
     * @notice Get the current price of the token.
     */
    function getCurrentPrice() public view returns (uint256) {
        if (block.timestamp < startTime) return initialPrice;
        if (block.timestamp >= endTime) return reservePrice;

        uint256 timeElapsed = block.timestamp - startTime;
        uint256 discount = discountRate * timeElapsed;
        return initialPrice - discount;
    }

    /**
     * @notice Get the auction status.
     */
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
