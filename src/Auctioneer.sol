// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DutchAuction} from "./DutchAuction.sol";
import {IERC20Metadata as IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";

struct RegistrationParams {
    address upkeepContract;
    uint96 amount;
    address adminAddress;
    uint32 gasLimit;
    uint8 triggerType;
    IERC20 billingToken;
    string name;
    bytes encryptedEmail;
    bytes checkData;
    bytes triggerConfig;
    bytes offchainConfig;
}

interface AutomationRegistrarInterface {
    function registerUpkeep(RegistrationParams calldata requestParams) external returns (uint256);
}

error InvalidAddresses();
error LinkTransferFailed();
error AuctionNotFound();
error InsufficientUpkeepFunds();
error UpkeepRegistrationFailed();

/**
 * @title Auctioneer
 * @author @dannweeeee
 * @notice Factory contract for creating and managing Dutch auctions
 */
contract Auctioneer {
    LinkTokenInterface public immutable i_link;
    AutomationRegistrarInterface public immutable i_registrar;
    address public immutable i_registry;

    uint96 public constant UPKEEP_MINIMUM_FUNDS = 1 * 10 ** 18; // minimum 1 LINK
    uint32 public constant UPKEEP_GAS_LIMIT = 500000;

    DutchAuction[] public auctions;

    mapping(address => bool) public isValidAuction;
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

    constructor(address _link, address _registrar, address _registry) {
        if (_link == address(0) || _registrar == address(0) || _registry == address(0)) {
            revert InvalidAddresses();
        }
        i_link = LinkTokenInterface(_link);
        i_registrar = AutomationRegistrarInterface(_registrar);
        i_registry = _registry;
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
        // Create new auction
        DutchAuction newAuction = new DutchAuction(
            _name, _symbol, _totalSupply, _initialPrice, _reservePrice, _minimumBid, msg.sender, address(this)
        );

        // Transfer LINK tokens from msg.sender to this contract
        if (!i_link.transferFrom(msg.sender, address(this), UPKEEP_MINIMUM_FUNDS)) {
            revert LinkTransferFailed();
        }

        // Register the upkeep
        uint256 upkeepId = _registerAuctionUpkeep(address(newAuction));

        // Setup auction with registry (not registrar)
        auctions.push(newAuction);
        isValidAuction[address(newAuction)] = true;
        auctionUpkeepIds[address(newAuction)] = upkeepId;

        emit AuctionCreated(
            address(newAuction), _name, _symbol, _totalSupply, _initialPrice, _reservePrice, _minimumBid, upkeepId
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
     * @notice Get all auctions owned by a specific address
     * @param owner The address of the auction owner
     * @return Array of auction addresses owned by the specified address
     */
    function getAuctionsByOwner(address owner) external view returns (address[] memory) {
        uint256 ownerAuctionCount = 0;

        // Count auctions owned by the address
        for (uint256 i = 0; i < auctions.length; i++) {
            DutchAuction auction = DutchAuction(address(auctions[i]));
            if (auction.owner() == owner) {
                ownerAuctionCount++;
            }
        }

        // Create array for owner's auctions
        address[] memory ownerAuctions = new address[](ownerAuctionCount);
        uint256 currentIndex = 0;

        // Fill array with owner's auctions
        for (uint256 i = 0; i < auctions.length; i++) {
            DutchAuction auction = DutchAuction(address(auctions[i]));
            if (auction.owner() == owner) {
                ownerAuctions[currentIndex] = address(auctions[i]);
                currentIndex++;
            }
        }

        return ownerAuctions;
    }

    /**
     * @notice Get price intervals for an auction
     * @param _auctionAddress Address of the auction to query
     * @return Array of price points at 2-minute intervals
     */
    function getPriceIntervals(address _auctionAddress) external view returns (string memory) {
        if (!isValidAuction[_auctionAddress]) revert AuctionNotFound();

        DutchAuction auction = DutchAuction(_auctionAddress);
        uint256 initialPrice = auction.initialPrice();
        uint256 reservePrice = auction.reservePrice();
        uint256 duration = auction.AUCTION_DURATION();

        // Calculate number of 2-minute intervals
        uint256 intervals = duration / 2 minutes;

        // Calculate price drop per interval
        uint256 priceDropPerInterval = ((initialPrice - reservePrice) * 2 minutes) / duration;

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
        if (!isValidAuction[auctionAddress]) revert AuctionNotFound();
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

    ///////////////////////////////
    ///// CHAINLINK FUNCTIONS /////
    ///////////////////////////////

    /**
     * @notice Internal function to register upkeep for an auction
     * @param auctionAddress The address of the auction to register upkeep for
     * @return upkeepId The ID of the registered upkeep
     */
    function _registerAuctionUpkeep(address auctionAddress) internal returns (uint256) {
        // Approve LINK transfer to registrar
        i_link.approve(address(i_registrar), UPKEEP_MINIMUM_FUNDS);

        // Prepare registration parameters
        RegistrationParams memory params = RegistrationParams({
            name: "Dutch Auction Automation",
            encryptedEmail: bytes(""),
            upkeepContract: auctionAddress,
            gasLimit: UPKEEP_GAS_LIMIT,
            adminAddress: msg.sender,
            triggerType: 0,
            checkData: bytes(""),
            triggerConfig: bytes(""),
            offchainConfig: bytes(""),
            amount: UPKEEP_MINIMUM_FUNDS,
            billingToken: IERC20(address(i_link))
        });

        // Register upkeep
        try i_registrar.registerUpkeep(params) returns (uint256 upkeepId) {
            return upkeepId;
        } catch {
            revert UpkeepRegistrationFailed();
        }
    }
}
