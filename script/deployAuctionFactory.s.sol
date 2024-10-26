// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {AuctionFactory} from "../src/AuctionFactory.sol";
import {console} from "forge-std/console.sol";

contract DeployAuctionFactory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        AuctionFactory auctionFactory = new AuctionFactory();

        console.log("AuctionFactory deployed at:", address(auctionFactory));

        // Grant AUCTION_CREATOR_ROLE to the deployer
        auctionFactory.grantRole(auctionFactory.AUCTION_CREATOR_ROLE(), deployerAddress);

        vm.stopBroadcast();
    }
}
