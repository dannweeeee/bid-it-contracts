// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DutchAuction} from "./DutchAuction.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {AutomationRegistryBaseInterface} from
    "@chainlink/contracts/src/v0.8/automation/interfaces/v2_0/AutomationRegistryInterface2_0.sol";

error AuctionNotFound();
error InvalidParameters();
error LinkTransferFailed();

/**
 * @title Auctioneer
 * @author @dannweeeee
 * @notice Factory contract for creating and managing Dutch auctions
 */
contract Auctioneer {
    LinkTokenInterface public immutable i_link;
    AutomationRegistryBaseInterface public immutable i_registry;

    uint96 public constant UPKEEP_MINIMUM_FUNDS = 5 * 10 ** 18; // minimum 5 LINK
    uint32 public constant UPKEEP_GAS_LIMIT = 500000;

    DutchAuction[] public auctions;

    mapping(address => bool) public doesAuctionExist;
    mapping(address => uint256) public auctionUpkeepIds;

    event AuctionCreated(
        address indexed auctionAddress,
        string name,
        string symbol,
        uint256 totalSupply,
        uint256 initialPrice,
        uint256 reservePrice,
        uint256 minimumBid,
        uint256 upkeepId
    );
    event AuctionPaused(address indexed auctionAddress);
    event AuctionUnpaused(address indexed auctionAddress);

    constructor(address _link, address _registry) {
        if (_link == address(0) || _registry == address(0)) revert InvalidParameters();
        i_link = LinkTokenInterface(_link);
        i_registry = AutomationRegistryBaseInterface(_registry);
    }

    ///////////////////////////////
    /// ADMINISTRATIVE FUNCTIONS //
    ///////////////////////////////

    /**
     * @notice Create a new Dutch auction
     */
    function createAuction(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        uint256 _initialPrice,
        uint256 _reservePrice,
        uint256 _minimumBid
    ) external returns (address) {
        if (_totalSupply == 0 || _initialPrice <= _reservePrice || _minimumBid == 0 || _minimumBid > _reservePrice) {
            revert InvalidParameters();
        }

        // Create new auction
        DutchAuction newAuction =
            new DutchAuction(_name, _symbol, _totalSupply, _initialPrice, _reservePrice, _minimumBid, msg.sender);

        // Transfer LINK tokens from msg.sender to this contract
        if (!i_link.transferFrom(msg.sender, address(this), UPKEEP_MINIMUM_FUNDS)) {
            revert LinkTransferFailed();
        }

        // Approve LINK transfer to registry
        i_link.approve(address(i_registry), UPKEEP_MINIMUM_FUNDS);

        // Register upkeep
        uint256 upkeepID = i_registry.registerUpkeep(
            address(newAuction), // Target contract address
            UPKEEP_GAS_LIMIT, // Gas limit for upkeep
            msg.sender, // Admin address (auction creator)
            "", // Empty check data
            "" // Empty offchain config
        );

        DutchAuction(address(newAuction)).setAutomationRegistry(address(i_registry));
        auctions.push(newAuction);
        doesAuctionExist[address(newAuction)] = true;
        auctionUpkeepIds[address(newAuction)] = upkeepID;

        emit AuctionCreated(
            address(newAuction), _name, _symbol, _totalSupply, _initialPrice, _reservePrice, _minimumBid, upkeepID
        );

        return address(newAuction);
    }

    ///////////////////////////////
    /////// GETTER FUNCTIONS //////
    ///////////////////////////////

    /**
     * @notice Get total number of auctions created
     */
    function getTotalAuctions() external view returns (uint256) {
        return auctions.length;
    }

    /**
     * @notice Get all active auctions
     */
    function getActiveAuctions() external view returns (address[] memory) {
        uint256 activeCount = 0;

        // Count active auctions
        for (uint256 i = 0; i < auctions.length; i++) {
            DutchAuction auction = DutchAuction(address(auctions[i]));
            if (!auction.auctionEnded()) {
                activeCount++;
            }
        }

        // Create active auctions array
        address[] memory activeAuctions = new address[](activeCount);
        uint256 currentIndex = 0;

        // Fill active auctions array
        for (uint256 i = 0; i < auctions.length; i++) {
            DutchAuction auction = DutchAuction(address(auctions[i]));
            if (!auction.auctionEnded()) {
                activeAuctions[currentIndex] = address(auctions[i]);
                currentIndex++;
            }
        }

        return activeAuctions;
    }

    /**
     * @notice Get all inactive auctions (ended)
     */
    function getInactiveAuctions() external view returns (address[] memory) {
        uint256 inactiveCount = 0;

        // Count inactive auctions
        for (uint256 i = 0; i < auctions.length; i++) {
            DutchAuction auction = DutchAuction(address(auctions[i]));
            if (auction.auctionEnded()) {
                inactiveCount++;
            }
        }

        // Create inactive auctions array
        address[] memory inactiveAuctions = new address[](inactiveCount);
        uint256 currentIndex = 0;

        // Fill inactive auctions array
        for (uint256 i = 0; i < auctions.length; i++) {
            DutchAuction auction = DutchAuction(address(auctions[i]));
            if (auction.auctionEnded()) {
                inactiveAuctions[currentIndex] = address(auctions[i]);
                currentIndex++;
            }
        }

        return inactiveAuctions;
    }

    /**
     * @notice Get price intervals for an auction
     * @param _auctionAddress Address of the auction to query
     * @return Array of price points at 2-minute intervals
     */
    function getPriceIntervals(address _auctionAddress) external view returns (string memory) {
        if (!doesAuctionExist[_auctionAddress]) revert AuctionNotFound();

        DutchAuction auction = DutchAuction(_auctionAddress);
        uint256 initialPrice = auction.initialPrice();
        uint256 reservePrice = auction.reservePrice();
        uint256 duration = auction.AUCTION_DURATION();

        // Calculate number of 2-minute intervals
        uint256 intervals = duration / 2 minutes;

        // Calculate price drop per interval
        uint256 priceDropPerInterval = (initialPrice - reservePrice) / (duration / 2 minutes);

        // Build JSON string
        bytes memory json = abi.encodePacked('{"prices":[');

        for (uint256 i = 0; i <= intervals; i++) {
            uint256 price = initialPrice - (priceDropPerInterval * i);

            // Add price to JSON
            if (i > 0) {
                json = abi.encodePacked(json, ",");
            }
            json = abi.encodePacked(json, '{"minute":', toString(i * 2), ',"price":', toString(price), "}");
        }

        json = abi.encodePacked(json, "]}");

        return string(json);
    }

    /**
     * @notice Get the upkeep ID for a specific auction
     * @param auctionAddress The address of the auction
     */
    function getUpkeepId(address auctionAddress) external view returns (uint256) {
        if (!doesAuctionExist[auctionAddress]) revert AuctionNotFound();
        return auctionUpkeepIds[auctionAddress];
    }

    ///////////////////////////////
    ////// HELPER FUNCTIONS //////
    ///////////////////////////////

    /**
     * @notice Helper function to convert uint to string
     */
    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /**
     * @notice Add more LINK funding to an auction's upkeep
     * @param auctionAddress The address of the auction to fund
     * @param amount Amount of LINK tokens to add
     */
    function fundUpkeep(address auctionAddress, uint96 amount) external {
        if (!doesAuctionExist[auctionAddress]) revert AuctionNotFound();

        if (!i_link.transferFrom(msg.sender, address(this), amount)) {
            revert LinkTransferFailed();
        }

        i_link.approve(address(i_registry), amount);
        i_registry.addFunds(auctionUpkeepIds[auctionAddress], amount);
    }
}
