// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Token} from "./Token.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";

error InitialPriceTooLow();
error InvalidInitialPrice();
error InvalidTotalSupply();
error MinimumBidTooHigh();
error InvalidMinimumBid();
error AuctionNotStarted();
error AuctionAlreadyEnded();
error MsgValueTooLow();
error AuctionAlreadyStarted();
error AuctionNotEnded();
error NoEthToClaim();
error TransferFailed();
error RefundFailed();

/**
 * @title Dutch Auction
 * @author @dannweeeee
 * @notice A Dutch auction contract for token ICOs (similar to Liquidity Bootstrapping Pools)
 */
contract DutchAuction is ReentrancyGuard, Pausable, Ownable, AutomationCompatibleInterface {
    Token public token;

    uint256 public initialPrice;
    uint256 public clearingPrice;
    uint256 public reservePrice;
    uint256 public minimumBid;
    uint256 public startTime;
    uint256 public endTime;
    uint256 public immutable AUCTION_DURATION = 3 minutes;
    uint256 public totalTokensForSale;
    uint256 public totalEthRaised;
    bool public auctionEnded;
    address[] public bidders;
    address public immutable auctioneer;

    mapping(address => uint256) public ethContributed;
    mapping(address => bool) public hasClaimedTokens;
    mapping(address => bool) public isBidder;

    event Bid(address indexed bidder, uint256 ethAmount, uint256 price);
    event AuctionStarted(uint256 startTime, uint256 endTime, uint256 startingPrice);
    event AuctionEnded(uint256 finalPrice, uint256 tokensSold, uint256 ethRaised);
    event TokensClaimed(address indexed bidder, uint256 amount);
    event EthWithdrawn(address indexed owner, uint256 amount);

    /**
     * @notice Constructor for the DutchAuction contract
     * @param _name The name of the token
     * @param _symbol The symbol of the token
     * @param _totalSupply The total supply of the token
     * @param _initialPrice The initial price of the token
     * @param _reservePrice The reserve price of the token
     * @param _minimumBid The minimum bid amount
     * @param _owner The owner of the contract
     * @param _auctioneer The auctioneer of the contract
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        uint256 _initialPrice,
        uint256 _reservePrice,
        uint256 _minimumBid,
        address _owner,
        address _auctioneer
    ) ReentrancyGuard() Pausable() Ownable(_owner) {
        if (_initialPrice == 0) revert InvalidInitialPrice();
        if (_initialPrice <= _reservePrice) revert InitialPriceTooLow();
        if (_totalSupply == 0) revert InvalidTotalSupply();
        if (_minimumBid == 0) revert InvalidMinimumBid();
        if (_minimumBid > _reservePrice) revert MinimumBidTooHigh();

        uint256 initialSupply = _totalSupply * 1e18;

        token = new Token(_name, _symbol, initialSupply, address(this));
        totalTokensForSale = _totalSupply;
        initialPrice = _initialPrice;
        reservePrice = _reservePrice;
        minimumBid = _minimumBid;
        auctioneer = _auctioneer;
    }

    /**
     * @notice Place a bid for a given quantity of tokens with ETH
     */
    function bid() public payable nonReentrant whenNotPaused {
        if (startTime == 0) revert AuctionNotStarted();
        if (auctionEnded) revert AuctionAlreadyEnded();
        if (msg.value < minimumBid) revert MsgValueTooLow();

        uint256 currentPrice = getCurrentPrice();

        // Track total ETH raised and bidder state
        ethContributed[msg.sender] += msg.value;
        totalEthRaised += msg.value;

        // Add bidder to list if first time bidding
        if (!isBidder[msg.sender]) {
            isBidder[msg.sender] = true;
            bidders.push(msg.sender);
        }

        emit Bid(msg.sender, msg.value, currentPrice);
    }

    ///////////////////////////////
    /////// ADMIN FUNCTIONS ///////
    ///////////////////////////////

    /**
     * @notice Start the auction
     */
    function startAuction() external onlyOwner {
        if (auctionEnded) revert AuctionAlreadyEnded();
        if (startTime != 0) revert AuctionAlreadyStarted();

        startTime = block.timestamp;
        endTime = startTime + AUCTION_DURATION;

        emit AuctionStarted(startTime, endTime, initialPrice);
    }

    /**
     * @notice End the auction
     */
    function endAuction() external onlyOwner {
        if (startTime == 0) revert AuctionNotStarted();
        if (auctionEnded) revert AuctionAlreadyEnded();
        if (block.timestamp < endTime && getRemainingTokens() > 0) revert AuctionNotEnded();

        auctionEnded = true;

        // Tokens to distribute are the total tokens sold
        uint256 tokensToDistribute = getSoldTokens();

        // Get the clearing price
        clearingPrice = getCurrentPrice();

        // Distribute tokens to bidders proportionally
        for (uint256 i = 0; i < bidders.length; i++) {
            address bidder = bidders[i];
            uint256 ethContribution = ethContributed[bidder];

            // Calculate tokens for this bidder based on their ETH contribution
            uint256 tokenAmount = (ethContribution * tokensToDistribute) / totalEthRaised;
            uint256 ethNeeded = tokenAmount * clearingPrice;
            uint256 refund = ethContribution - ethNeeded;

            if (refund > 0) {
                (bool success,) = bidder.call{value: refund}("");
                if (!success) revert RefundFailed();
            }

            if (tokenAmount > 0 && !hasClaimedTokens[bidder]) {
                hasClaimedTokens[bidder] = true;
                bool success = token.transfer(bidder, tokenAmount * 1e18);
                if (!success) {
                    hasClaimedTokens[bidder] = false;
                    revert TransferFailed();
                }
                emit TokensClaimed(bidder, tokenAmount * 1e18);
            }
        }

        // Burn any remaining tokens
        uint256 remainingTokens = totalTokensForSale - tokensToDistribute;
        if (remainingTokens > 0) {
            token.burn(remainingTokens * 1e18);
        }

        emit AuctionEnded(clearingPrice, tokensToDistribute, totalEthRaised);
    }

    /**
     * @notice Pause the auction
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the auction
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Withdraw ETH from the auction
     */
    function withdrawEth() external onlyOwner nonReentrant {
        if (!auctionEnded) revert AuctionNotEnded();

        // Get balance of contract
        uint256 balance = address(this).balance;
        if (balance == 0) revert NoEthToClaim();

        // Transfer ETH to owner
        (bool success,) = owner().call{value: balance}("");
        if (!success) revert TransferFailed();

        emit EthWithdrawn(owner(), balance);
    }

    ///////////////////////////////
    /////// GETTER FUNCTIONS //////
    ///////////////////////////////

    /**
     * @notice Get the current price of the tokens
     * @return The current price of the tokens (in wei)
     */
    function getCurrentPrice() public view returns (uint256) {
        if (block.timestamp <= startTime) return initialPrice;
        if (block.timestamp >= endTime) return reservePrice;

        uint256 timeElapsed = block.timestamp - startTime;
        uint256 totalPriceDrop = initialPrice - reservePrice;
        uint256 discount = (timeElapsed * totalPriceDrop) / AUCTION_DURATION;
        return initialPrice - discount;
    }

    /**
     * @notice Get the total tokens sold
     * @return The total tokens sold
     */
    function getSoldTokens() public view returns (uint256) {
        uint256 currentPrice = getCurrentPrice();
        uint256 totalTokenDemand = Math.min((totalEthRaised / currentPrice), totalTokensForSale);

        return totalTokenDemand;
    }

    /**
     * @notice Get the remaining tokens for sale
     * @return The remaining tokens for sale
     */
    function getRemainingTokens() public view returns (uint256) {
        uint256 totalTokenDemand = getSoldTokens();
        uint256 remainingTokens = totalTokensForSale - totalTokenDemand;

        return remainingTokens;
    }

    /**
     * @notice Get token-specific details of the auction
     * @return tokenName The name of the token being auctioned
     * @return tokenSymbol The symbol of the token
     * @return tokenDecimals The number of decimals of the token
     * @return tokenTotalSupply The total supply of the token
     * @return tokenAddress The address of the token contract
     * @return tokenBalance The token balance of this contract
     */
    function getTokenDetails()
        external
        view
        returns (
            string memory tokenName,
            string memory tokenSymbol,
            uint8 tokenDecimals,
            uint256 tokenTotalSupply,
            address tokenAddress,
            uint256 tokenBalance
        )
    {
        return (
            token.name(),
            token.symbol(),
            token.decimals(),
            token.totalSupply(),
            address(token),
            token.balanceOf(address(this))
        );
    }

    /**
     * @notice Get the auction statistics
     * @return tokenAddress The address of the token contract
     * @return initialTokenPrice The initial price of the token
     * @return reserveTokenPrice The reserve price of the token
     * @return minBidAmount The minimum bid amount
     * @return auctionStartTime The start time of the auction
     * @return auctionEndTime The end time of the auction
     * @return duration The duration of the auction
     * @return totalSupply The total supply of the token
     * @return soldTokens The total tokens sold
     * @return remainingTokens The remaining tokens for sale
     */
    function getAuctionStatistics()
        external
        view
        returns (
            address tokenAddress,
            uint256 initialTokenPrice,
            uint256 reserveTokenPrice,
            uint256 minBidAmount,
            uint256 auctionStartTime,
            uint256 auctionEndTime,
            uint256 duration,
            uint256 totalSupply,
            uint256 soldTokens,
            uint256 remainingTokens,
            uint256 ethRaised,
            uint256 totalBidders,
            address auctioneerAddress
        )
    {
        return (
            address(token),
            initialPrice,
            reservePrice,
            minimumBid,
            startTime,
            endTime,
            AUCTION_DURATION,
            totalTokensForSale,
            getSoldTokens(),
            getRemainingTokens(),
            totalEthRaised,
            bidders.length,
            auctioneer
        );
    }

    /**
     * @notice Get the auction status
     * @return isStarted Whether the auction has started
     * @return isEnded Whether the auction has ended
     * @return currentTokenPrice The current price of the tokens
     * @return remainingTokens The remaining tokens for sale
     * @return timeRemaining The time remaining in the auction
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

    /**
     * @notice Get the bidders
     * @return The bidders
     */
    function getBidders() external view returns (address[] memory) {
        return bidders;
    }

    //////////////////////////////////////////
    ////// CHAINLINK AUTOMATION FUNCTIONS ////
    //////////////////////////////////////////

    /**
     * @notice Chainlink Automation: Check if upkeep is needed
     */
    function checkUpkeep(bytes calldata /* checkData */ )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */ )
    {
        upkeepNeeded = (startTime != 0) // auction has started
            && !auctionEnded // auction hasn't ended yet
            && (block.timestamp >= endTime || getRemainingTokens() == 0); // time is up OR remaining tokens are 0
        return (upkeepNeeded, "");
    }

    /**
     * @notice Chainlink Automation: Perform the upkeep
     */
    function performUpkeep(bytes calldata /* performData */ ) external override {
        if (startTime == 0) revert AuctionNotStarted();
        if (auctionEnded) revert AuctionAlreadyEnded();
        if (block.timestamp < endTime && getRemainingTokens() > 0) revert AuctionNotEnded();

        auctionEnded = true;

        // Tokens to distribute are the total tokens sold
        uint256 tokensToDistribute = getSoldTokens();

        // Get the clearing price
        clearingPrice = getCurrentPrice();

        // Distribute tokens to bidders proportionally
        for (uint256 i = 0; i < bidders.length; i++) {
            address bidder = bidders[i];
            uint256 ethContribution = ethContributed[bidder];

            // Calculate tokens for this bidder based on their ETH contribution
            uint256 tokenAmount = (ethContribution * tokensToDistribute) / totalEthRaised;
            uint256 ethNeeded = tokenAmount * clearingPrice;
            uint256 refund = ethContribution - ethNeeded;

            if (refund > 0) {
                (bool success,) = bidder.call{value: refund}("");
                if (!success) revert RefundFailed();
            }

            if (tokenAmount > 0 && !hasClaimedTokens[bidder]) {
                hasClaimedTokens[bidder] = true;
                bool success = token.transfer(bidder, tokenAmount * 1e18);
                if (!success) {
                    hasClaimedTokens[bidder] = false;
                    revert TransferFailed();
                }
                emit TokensClaimed(bidder, tokenAmount * 1e18);
            }
        }

        // Burn any remaining tokens
        uint256 remainingTokens = totalTokensForSale - tokensToDistribute;
        if (remainingTokens > 0) {
            token.burn(remainingTokens * 1e18);
        }

        emit AuctionEnded(clearingPrice, tokensToDistribute, totalEthRaised);
    }
}
