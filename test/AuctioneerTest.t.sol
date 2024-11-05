// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Auctioneer} from "../src/Auctioneer.sol";
import {DutchAuction} from "../src/DutchAuction.sol";
import {Token} from "../src/Token.sol";
import {MockLinkToken} from "./mocks/MockLinkToken.sol";
import {MockRegistry} from "./mocks/MockRegistry.sol";

error InvalidAddresses();
error AuctionNotFound();

contract AuctioneerTest is Test {
    Auctioneer public auctioneer;
    MockLinkToken public linkToken;
    MockRegistry public registry;
    address public owner;

    // Test constants
    string constant NAME = "Test Auction";
    string constant SYMBOL = "TEST";
    uint256 constant TOTAL_SUPPLY = 100;
    uint256 constant INITIAL_PRICE = 1 ether;
    uint256 constant RESERVE_PRICE = 0.1 ether;
    uint256 constant MINIMUM_BID = 0.01 ether;
    uint96 constant UPKEEP_FUNDS = 5 * 10 ** 18; // 5 LINK

    function setUp() public {
        owner = makeAddr("owner");
        vm.startPrank(owner);

        // Deploy mock contracts
        linkToken = new MockLinkToken();
        registry = new MockRegistry();

        // Deploy Auctioneer
        auctioneer = new Auctioneer(address(linkToken), address(registry));

        // Fund owner with LINK tokens
        linkToken.mint(owner, 100 * 10 ** 18);
        linkToken.approve(address(auctioneer), type(uint256).max);

        vm.stopPrank();
    }

    function test_Constructor() public view {
        assertEq(address(auctioneer.i_link()), address(linkToken));
        assertEq(address(auctioneer.i_registry()), address(registry));
    }

    function test_RevertIf_ConstructorZeroAddresses() public {
        vm.expectRevert(InvalidAddresses.selector);
        new Auctioneer(address(0), address(registry));

        vm.expectRevert(InvalidAddresses.selector);
        new Auctioneer(address(linkToken), address(0));
    }

    function test_CreateAuction() public {
        vm.startPrank(owner);

        address auctionAddress =
            auctioneer.createAuction(NAME, SYMBOL, TOTAL_SUPPLY, INITIAL_PRICE, RESERVE_PRICE, MINIMUM_BID);

        assertTrue(auctioneer.isValidAuction(auctionAddress));
        assertEq(auctioneer.getTotalAuctions(), 1);

        DutchAuction auction = DutchAuction(auctionAddress);
        Token token = auction.token();
        assertEq(token.name(), NAME);
        assertEq(token.symbol(), SYMBOL);
        assertEq(auction.totalTokensForSale(), TOTAL_SUPPLY);
        assertEq(auction.initialPrice(), INITIAL_PRICE);
        assertEq(auction.reservePrice(), RESERVE_PRICE);
        assertEq(auction.minimumBid(), MINIMUM_BID);
        assertEq(auction.owner(), owner);

        vm.stopPrank();
    }

    function test_GetAuctionsByOwner() public {
        vm.startPrank(owner);

        address auction1 =
            auctioneer.createAuction(NAME, SYMBOL, TOTAL_SUPPLY, INITIAL_PRICE, RESERVE_PRICE, MINIMUM_BID);

        // Create auction with different owner
        vm.stopPrank();
        address otherOwner = makeAddr("other");
        vm.startPrank(otherOwner);
        linkToken.mint(otherOwner, 100 * 10 ** 18);
        linkToken.approve(address(auctioneer), type(uint256).max);

        address auction2 =
            auctioneer.createAuction(NAME, SYMBOL, TOTAL_SUPPLY, INITIAL_PRICE, RESERVE_PRICE, MINIMUM_BID);

        // Check auctions by owner
        address[] memory ownerAuctions = auctioneer.getAuctionsByOwner(owner);
        assertEq(ownerAuctions.length, 1);
        assertEq(ownerAuctions[0], auction1);

        address[] memory otherOwnerAuctions = auctioneer.getAuctionsByOwner(otherOwner);
        assertEq(otherOwnerAuctions.length, 1);
        assertEq(otherOwnerAuctions[0], auction2);

        vm.stopPrank();
    }

    function test_FundUpkeep() public {
        vm.startPrank(owner);

        address auctionAddress =
            auctioneer.createAuction(NAME, SYMBOL, TOTAL_SUPPLY, INITIAL_PRICE, RESERVE_PRICE, MINIMUM_BID);

        uint96 additionalFunds = 1 * 10 ** 18; // 1 LINK
        auctioneer.fundUpkeep(auctionAddress, additionalFunds);

        vm.stopPrank();
    }

    function test_RevertIf_FundInvalidAuction() public {
        vm.startPrank(owner);

        vm.expectRevert(AuctionNotFound.selector);
        auctioneer.fundUpkeep(makeAddr("invalid"), 1 * 10 ** 18);

        vm.stopPrank();
    }
}
