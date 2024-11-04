// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Token} from "./Token.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";

error AuctionNotStarted();
error AuctionAlreadyStarted();
error AuctionNotEnded();
error AuctionAlreadyEnded();
error InvalidBid();
error InvalidAmount();
error InvalidMinimumBid();
error NothingToClaim();
error AlreadyClaimed();
error NotEnoughTokens();
error PriceNotMet();
error BidTooLow();
error InvalidPrice();
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
    address public automationRegistry; // Chainlink Automation registry
    uint256 public constant BATCH_SIZE = 50; // Number of claims to process per upkeep
    uint256 public currentClaimIndex;
    address[] public bidders;

    mapping(address => uint256) public userBids;
    mapping(address => uint256) public claimableTokens;
    mapping(address => bool) public hasClaimedTokens;
    mapping(address => bool) public isBidder;

    event Bid(address indexed bidder, uint256 ethAmount, uint256 tokenAmount, uint256 price);
    event AuctionStarted(uint256 startTime, uint256 endTime, uint256 startingPrice);
    event AuctionEnded(uint256 finalPrice, uint256 tokensSold, uint256 ethRaised);
    event TokensClaimed(address indexed bidder, uint256 amount);
    event EthWithdrawn(address indexed owner, uint256 amount);
    event AutomationRegistryUpdated(address oldRegistry, address newRegistry);

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        uint256 _initialPrice,
        uint256 _reservePrice,
        uint256 _minimumBid,
        address _owner
    ) ReentrancyGuard() Pausable() Ownable(_owner) {
        if (_initialPrice <= _reservePrice) revert InvalidPrice();
        if (_totalSupply == 0) revert InvalidAmount();
        if (_minimumBid == 0) revert InvalidAmount();
        if (_initialPrice == 0) revert InvalidPrice();
        if (_minimumBid > _reservePrice) revert InvalidMinimumBid();

        token = new Token(_name, _symbol, _totalSupply, address(this));
        initialPrice = _initialPrice;
        reservePrice = _reservePrice;
        totalTokensForSale = _totalSupply;
        minimumBid = _minimumBid;
    }

    /**
     * @notice Place a bid for a given quantity of tokens
     * @param _quantity The quantity of tokens to bid for
     */
    function bid(uint256 _quantity) public payable nonReentrant whenNotPaused {
        if (startTime == 0) revert AuctionNotStarted();
        if (auctionEnded) revert AuctionAlreadyEnded();
        if (_quantity == 0) revert InvalidBid();
        if (_quantity > totalTokensForSale) revert NotEnoughTokens();
        if (msg.value < minimumBid) revert BidTooLow();

        uint256 currentTokenPrice = getCurrentPrice();
        uint256 totalCost = _quantity * currentTokenPrice;

        if (msg.value < totalCost) revert PriceNotMet();

        totalTokensForSale -= _quantity;
        totalTokensSold += _quantity;
        totalEthRaised += totalCost;
        userBids[msg.sender] += totalCost;
        claimableTokens[msg.sender] += _quantity;

        if (!isBidder[msg.sender]) {
            isBidder[msg.sender] = true;
            bidders.push(msg.sender);
        }

        emit Bid(msg.sender, totalCost, _quantity, currentTokenPrice);

        uint256 refundAmount = msg.value - totalCost;
        if (refundAmount > 0) {
            (bool success,) = msg.sender.call{value: refundAmount}("");
            if (!success) revert RefundFailed();
        }
    }

    ///////////////////////////////
    /////// OWNER FUNCTIONS ///////
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
     * @notice End the auction - only for emergency use
     * @dev This function should only be used if Chainlink Automation fails
     */
    function endAuction() external onlyOwner {
        if (startTime == 0) revert AuctionNotStarted();
        if (block.timestamp < endTime && totalTokensForSale > 0) revert AuctionNotEnded();
        if (auctionEnded) revert AuctionAlreadyEnded();

        // Disable Chainlink Automation to prevent conflicts
        address oldRegistry = automationRegistry;
        automationRegistry = address(0);

        auctionEnded = true;

        // Burn remaining tokens if any
        if (totalTokensForSale > 0) {
            token.burn(totalTokensForSale);
        }

        emit AuctionEnded(getCurrentPrice(), totalTokensSold, totalEthRaised);

        // Restore Chainlink Automation
        automationRegistry = oldRegistry;
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

        uint256 balance = address(this).balance;
        if (balance == 0) revert NothingToClaim();

        (bool success,) = owner().call{value: balance}("");
        if (!success) revert TransferFailed();

        emit EthWithdrawn(owner(), balance);
    }

    ///////////////////////////////
    ////// HELPER FUNCTIONS ///////
    ///////////////////////////////

    /**
     * @notice Calculate the price for a given quantity of tokens
     * @param _quantity The quantity of tokens to calculate the price for
     * @return The price for the given quantity of tokens
     */
    function calculatePrice(uint256 _quantity) public view returns (uint256) {
        uint256 price = getCurrentPrice();
        return price * _quantity;
    }

    ///////////////////////////////
    /////// GETTER FUNCTIONS //////
    ///////////////////////////////

    /**
     * @notice Get the current price of the tokens
     * @return The current price of the tokens
     */
    function getCurrentPrice() public view returns (uint256) {
        if (block.timestamp <= startTime) return initialPrice;
        if (block.timestamp >= endTime) return reservePrice;

        uint256 timeElapsed = block.timestamp - startTime;
        uint256 totalPriceDrop = initialPrice - reservePrice;
        uint256 discount = (totalPriceDrop * timeElapsed) / AUCTION_DURATION;
        return initialPrice - discount;
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

    ///////////////////////////////
    ////// CHAINLINK FUNCTIONS ////
    ///////////////////////////////

    /**
     * @notice Modifier to ensure only the automation registry can call a function
     */
    modifier onlyAutomation() {
        require(msg.sender == automationRegistry, "Only Chainlink Automation can call this");
        _;
    }

    /**
     * @notice Set the automation registry
     * @param _registry The address of the automation registry
     */
    function setAutomationRegistry(address _registry) external onlyOwner {
        require(_registry != address(0), "Invalid registry address");
        address oldRegistry = automationRegistry;
        automationRegistry = _registry;
        emit AutomationRegistryUpdated(oldRegistry, _registry);
    }

    /**
     * @notice Chainlink Automation: Check if upkeep is needed
     * @dev This function is used to determine if the auction should be ended or if the tokens should be distributed
     */
    function checkUpkeep(bytes calldata /* checkData */ )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        if (startTime != 0 && !auctionEnded && block.timestamp >= endTime) {
            return (true, abi.encode(true, 0)); // indicates auction end
        }

        if (auctionEnded && currentClaimIndex < bidders.length) {
            return (true, abi.encode(false, currentClaimIndex)); // indicates token distribution
        }

        return (false, "");
    }

    /**
     * @notice Chainlink Automation: Perform the upkeep
     * @dev This function is used to end the auction and distribute the tokens
     */
    function performUpkeep(bytes calldata performData) external override onlyAutomation {
        (bool isAuctionEnd, uint256 startIndex) = abi.decode(performData, (bool, uint256));

        if (isAuctionEnd) {
            if (block.timestamp >= endTime && !auctionEnded) {
                auctionEnded = true;
                if (totalTokensForSale > 0) {
                    token.burn(totalTokensForSale);
                }
                emit AuctionEnded(getCurrentPrice(), totalTokensSold, totalEthRaised);
            }
            return;
        }

        // Process token distribution in batches
        uint256 endIndex = Math.min(startIndex + BATCH_SIZE, bidders.length);
        for (uint256 i = startIndex; i < endIndex; i++) {
            address bidder = bidders[i];
            uint256 tokenAmount = claimableTokens[bidder];

            if (tokenAmount > 0 && !hasClaimedTokens[bidder]) {
                claimableTokens[bidder] = 0;
                hasClaimedTokens[bidder] = true;

                bool success = token.transfer(bidder, tokenAmount);
                if (success) {
                    emit TokensClaimed(bidder, tokenAmount);
                }
            }
        }

        currentClaimIndex = endIndex;
    }
}
