// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {Auctioneer} from "../src/Auctioneer.sol";

contract DeployAuctioneer is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying Auctioneer with owner:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        Auctioneer auctioneer = new Auctioneer();

        console.log("Auctioneer deployed at:", address(auctioneer));

        vm.stopBroadcast();
    }
}
