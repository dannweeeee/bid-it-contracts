// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./Token.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {console} from "forge-std/console.sol";

/**
 * @title Auction
 * @author Dann Wee
 * @notice This contract is the initialization of a Dutch Auction for an ERC20 token.
 */
contract Auction is ReentrancyGuard, Pausable, Ownable {
    Token public token;
    mapping(address => User) private bidsByUser;
    mapping(address => uint256) private assignedTokens;
    mapping(address => uint256) private pendingWithdrawals;
    Bid[] private bids;
    address[] private bidders;
    uint256 private totalBids;
    uint256 public immutable lowestPossibleBid;
    uint256 public immutable startingPrice;
    uint256 public price;
    uint256 public immutable discountRate;
    uint256 public quantity;
    uint256 public immutable initialQuantity;
    uint256 public immutable start;
    uint256 public end;
    States public state;
    uint8 public immutable decimals;

    struct User {
        uint256 amount;
        bool isExist;
    }

    struct Bid {
        address user;
        uint256 amount;
        uint256 price;
        uint256 quantity;
        uint256 time;
    }

    struct Data {
        address tokenAddress;
        string name;
        string symbol;
        uint256 quantity;
        uint256 startDateTime;
        uint256 startingPrice;
        uint256 state;
        uint256 price;
        Bid[] bids;
    }

    enum States {
        Pending,
        AcceptingBids,
        Withdrawal
    }

    event NewBid(address indexed user, uint256 amount, uint256 price, uint256 quantity, uint256 time);
    event AssignmentStart();
    event AssignmentDone();
    event TokensBurned(uint256 amount);
    event AuctionEnded();
    event AuctionStarted(uint256 startTime, uint256 endTime);
    event PriceUpdated(uint256 newPrice);
    event AuctionExtended(uint256 newEndTime);

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _quantity,
        uint256 _startingPrice,
        uint256 _discountRate,
        uint256 _lowestPossibleBid,
        uint256 _start,
        address _owner
    ) ReentrancyGuard() Pausable() Ownable(_owner) {
        require(_start > block.timestamp, "Start time must be in the future");
        require(_quantity > 0, "Quantity must be greater than 0");
        require(_startingPrice > _lowestPossibleBid, "Starting price must be greater than lowest possible bid");
        require(_discountRate > 0, "Discount rate must be greater than 0");

        quantity = _quantity;
        lowestPossibleBid = _lowestPossibleBid;
        startingPrice = _startingPrice;
        discountRate = _discountRate;
        price = _startingPrice;
        initialQuantity = _quantity;
        decimals = _decimals;
        token = new Token(_name, _symbol, _quantity * (10 ** uint256(_decimals)), _decimals, address(this));
        start = _start;
        end = _start + 20 minutes;
        state = States.Pending;

        emit AuctionStarted(start, end);
    }

    /**
     * @notice Modifier to check if the auction is in a specific state
     * @param _state The state to check
     */
    modifier atState(States _state) {
        require(state == _state, "Invalid state");
        _;
    }

    /**
     * @notice Modifier to handle timed transitions
     */
    modifier timedTransitions() {
        if (state == States.Pending && block.timestamp >= start) {
            state = States.AcceptingBids;
        }
        if (state == States.AcceptingBids && (block.timestamp >= end || totalBids >= price * quantity)) {
            assignTokens();
            state = States.Withdrawal;
        }
        _;
    }

    /**
     * @notice Function to update the price of the auction
     */
    function updatePrice() public timedTransitions whenNotPaused {
        require(state == States.AcceptingBids, "Not in bidding state");
        uint256 timeElapsed = (block.timestamp - start) / 60;
        uint256 discount = discountRate * timeElapsed;
        uint256 newPrice;
        if (startingPrice > discount && startingPrice - discount >= lowestPossibleBid) {
            newPrice = startingPrice - discount;
        } else {
            newPrice = lowestPossibleBid;
        }
        if (newPrice != price) {
            price = newPrice;
            emit PriceUpdated(price);
        }
    }

    /**
     * @notice Function to place a bid
     * @param _quantity The quantity of the bid
     */
    function placeBid(uint256 _quantity)
        public
        payable
        timedTransitions
        atState(States.AcceptingBids)
        whenNotPaused
        nonReentrant
    {
        require(msg.value >= price * _quantity, "Insufficient bid amount");
        require(_quantity > 0 && _quantity <= quantity, "Invalid quantity");

        if (!bidsByUser[msg.sender].isExist) {
            bidders.push(msg.sender);
            bidsByUser[msg.sender].isExist = true;
        }

        bidsByUser[msg.sender].amount += msg.value;
        totalBids += msg.value;
        quantity -= _quantity;

        bids.push(Bid(msg.sender, msg.value, price, _quantity, block.timestamp));

        emit NewBid(msg.sender, msg.value, price, _quantity, block.timestamp);
    }

    /**
     * @notice Function to assign tokens to the bidders
     */
    function assignTokens() internal {
        emit AssignmentStart();
        for (uint256 i = 0; i < bids.length; i++) {
            Bid memory bid = bids[i];
            uint256 tokenAmount = bid.amount / price;
            if (tokenAmount > 0) {
                if (quantity >= tokenAmount) {
                    quantity -= tokenAmount;
                    bidsByUser[bid.user].amount -= tokenAmount * price;
                    assignedTokens[bid.user] += tokenAmount;
                } else {
                    bidsByUser[bid.user].amount -= quantity * price;
                    assignedTokens[bid.user] += quantity;
                    quantity = 0;
                    break;
                }
            }
        }
        emit AssignmentDone();
    }

    /**
     * @notice Function to withdraw tokens or refunds
     */
    function withdraw() public atState(States.Withdrawal) whenNotPaused nonReentrant {
        uint256 tokenAmount = assignedTokens[msg.sender];
        uint256 refundAmount = bidsByUser[msg.sender].amount;

        require(tokenAmount > 0 || refundAmount > 0, "No tokens or refunds to withdraw");

        // Clear the state before making external calls
        if (tokenAmount > 0) {
            assignedTokens[msg.sender] = 0;
        }
        if (refundAmount > 0) {
            bidsByUser[msg.sender].amount = 0;
            pendingWithdrawals[msg.sender] += refundAmount;
        }

        // Perform external calls after updating state
        if (tokenAmount > 0) {
            require(token.transfer(msg.sender, tokenAmount * (10 ** uint256(decimals))), "Token transfer failed");
        }
    }

    /**
     * @notice Function to withdraw Ether
     */
    function withdrawEther() public nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "No Ether to withdraw");

        pendingWithdrawals[msg.sender] = 0;
        (bool sent,) = msg.sender.call{value: amount}("");
        require(sent, "Failed to send Ether");
    }

    /**
     * @notice Function to burn unsold tokens
     */
    function burnUnsoldTokens() public onlyOwner atState(States.Withdrawal) {
        require(block.timestamp >= end, "Auction not yet ended");
        uint256 unsoldTokens = quantity * (10 ** uint256(decimals));
        if (unsoldTokens > 0) {
            token.burn(unsoldTokens);
            emit TokensBurned(unsoldTokens);
        }
        emit AuctionEnded();
    }

    /**
     * @notice Function to withdraw collected Ether
     */
    function withdrawCollectedEther() public onlyOwner atState(States.Withdrawal) {
        require(block.timestamp >= end, "Auction not yet ended");
        uint256 balance = address(this).balance;
        (bool sent,) = owner().call{value: balance}("");
        require(sent, "Failed to send Ether");
    }

    /**
     * @notice Function to pause the auction
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @notice Function to unpause the auction
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * @notice Function to extend the auction
     * @param _additionalTime The additional time to extend the auction
     */
    function extendAuction(uint256 _additionalTime) public onlyOwner {
        require(state == States.AcceptingBids, "Auction not in progress");
        end += _additionalTime;
        emit AuctionExtended(end);
    }

    /**
     * @notice Function to check if the auction has ended
     * @return bool True if the auction has ended, false otherwise
     */
    function isAuctionEnded() public view returns (bool) {
        return block.timestamp >= end || state == States.Withdrawal;
    }

    /**
     * @notice Function to get the current state of the auction
     * @return States The current state of the auction
     */
    function getState() public view returns (States) {
        return state;
    }

    /**
     * @notice Function to get the initial quantity of the auction
     * @return uint256 The initial quantity of the auction
     */
    function getQuantity() public view returns (uint256) {
        return initialQuantity;
    }

    /**
     * @notice Function to get the start time of the auction
     * @return uint256 The start time of the auction
     */
    function getStartTime() public view returns (uint256) {
        return start;
    }

    /**
     * @notice Function to get the token address
     * @return address The token address
     */
    function getToken() public view returns (address) {
        return address(token);
    }

    /**
     * @notice Function to get the auction data
     * @return Data memory The auction data
     */
    function getData() public view returns (Data memory) {
        return Data(
            address(token), token.name(), token.symbol(), quantity, start, startingPrice, uint256(state), price, bids
        );
    }

    /**
     * @notice Function to get the bids
     * @return Bid[] memory The bids
     */
    function getBids() public view returns (Bid[] memory) {
        return bids;
    }

    /**
     * @notice Function to get the token balance of the sender
     * @return uint256 The token balance
     */
    function getTokenBalance() public view returns (uint256) {
        return token.balanceOf(msg.sender);
    }

    /**
     * @notice Function to get the assigned tokens of a user
     * @param user The address of the user
     * @return uint256 The assigned tokens
     */
    function getAssigned(address user) public view returns (uint256) {
        return assignedTokens[user];
    }

    /**
     * @notice Function to get the bids by user
     * @param user The address of the user
     * @return uint256 The bids by user
     */
    function getBidsByUser(address user) public view returns (uint256) {
        return bidsByUser[user].amount;
    }

    /**
     * @notice Function to check if a user has assigned tokens or bids
     * @param user The address of the user
     * @return bool True if the user has assigned tokens or bids, false otherwise
     */
    function checkAssigned(address user) public view returns (bool) {
        return assignedTokens[user] > 0 || bidsByUser[user].amount > 0;
    }

    /**
     * @notice Function to get the pending withdrawals of a user
     * @param user The address of the user
     * @return uint256 The pending withdrawals
     */
    function getPendingWithdrawals(address user) public view returns (uint256) {
        return pendingWithdrawals[user];
    }
}
