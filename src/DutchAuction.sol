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
error InvalidBidQuantity();
error BidQuantityTooHigh();
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
    uint256 public reservePrice;
    uint256 public minimumBid;
    uint256 public startTime;
    uint256 public endTime;
    uint256 public immutable AUCTION_DURATION = 20 minutes;
    uint256 public totalTokensForSale;
    uint256 public totalEthRaised;
    uint256 public totalTokensSold;
    bool public auctionEnded;
    address public automationRegistry;
    uint256 public constant BATCH_SIZE = 50;
    uint256 public currentClaimIndex;
    address[] public bidders;
    address public immutable auctioneer;

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
        address _owner,
        address _auctioneer
    ) ReentrancyGuard() Pausable() Ownable(_owner) {
        if (_initialPrice == 0) revert InvalidInitialPrice();
        if (_initialPrice <= _reservePrice) revert InitialPriceTooLow();
        if (_totalSupply == 0) revert InvalidTotalSupply();
        if (_minimumBid == 0) revert InvalidMinimumBid();
        if (_minimumBid > _reservePrice) revert MinimumBidTooHigh();

        token = new Token(_name, _symbol, _totalSupply, address(this));
        totalTokensForSale = _totalSupply;
        initialPrice = _initialPrice;
        reservePrice = _reservePrice;
        minimumBid = _minimumBid;
        auctioneer = _auctioneer;
    }

    /**
     * @notice Place a bid for a given quantity of tokens
     * @param _quantity The quantity of tokens to bid for
     */
    function bid(uint256 _quantity) public payable nonReentrant whenNotPaused {
        // Check if auction has started and not ended
        if (startTime == 0) revert AuctionNotStarted();
        if (auctionEnded) revert AuctionAlreadyEnded();

        // Validate bid quantity
        if (_quantity == 0) revert InvalidBidQuantity();
        if (_quantity > totalTokensForSale) revert BidQuantityTooHigh();
        if (msg.value < minimumBid) revert MsgValueTooLow();

        // Calculate total cost based on current token price
        uint256 currentTokenPrice = getCurrentPrice();
        uint256 totalCost = _quantity * currentTokenPrice / (1 ether);

        // Ensure sufficient ETH was sent
        if (msg.value < totalCost) revert MsgValueTooLow();

        // Update auction state
        totalTokensForSale -= _quantity;
        totalTokensSold += _quantity;
        totalEthRaised += totalCost;

        // Update bidder state
        userBids[msg.sender] += totalCost;
        claimableTokens[msg.sender] += _quantity;

        // Add bidder to list if first time bidding
        if (!isBidder[msg.sender]) {
            isBidder[msg.sender] = true;
            bidders.push(msg.sender);
        }

        emit Bid(msg.sender, totalCost, _quantity, currentTokenPrice);

        // Refund excess ETH if any
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

        // Get balance of contract
        uint256 balance = address(this).balance;
        if (balance == 0) revert NoEthToClaim();

        // Transfer ETH to owner
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
        return price * _quantity / (1 ether);
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
     * @notice Modifier to ensure only the auctioneer can call a function
     */
    modifier onlyAuctioneer() {
        require(msg.sender == auctioneer, "Only Auctioneer can call this");
        _;
    }

    /**
     * @notice Set the automation registry
     * @param _registry The address of the automation registry
     */
    function setAutomationRegistry(address _registry) external onlyAuctioneer {
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

        return (false, abi.encode(false, 0));
    }

    /**
     * @notice Chainlink Automation: Perform the upkeep
     * @dev This function is used to end the auction and distribute the tokens
     */
    function performUpkeep(bytes calldata performData) external override onlyAutomation {
        (bool isAuctionEnd, uint256 startIndex) = abi.decode(performData, (bool, uint256));

        if (isAuctionEnd) {
            if (startTime == 0) revert AuctionNotStarted();
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
                if (!success) {
                    // Revert state changes if transfer fails
                    claimableTokens[bidder] = tokenAmount;
                    hasClaimedTokens[bidder] = false;
                    revert TransferFailed();
                }
                emit TokensClaimed(bidder, tokenAmount);
            }
        }

        currentClaimIndex = endIndex;
    }
}
