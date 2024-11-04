// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {Auctioneer} from "../src/Auctioneer.sol";

contract DeployAuctioneer is Script {
    address constant LINK_TOKEN = 0x779877A7B0D9E8603169DdbD7836e478b4624789;
    address constant AUTOMATION_REGISTRY = 0x86EFBD0b6736Bed994962f9797049422A3A8E8Ad;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying Auctioneer with owner:", deployer);
        console.log("Using LINK token:", LINK_TOKEN);
        console.log("Using Automation Registry:", AUTOMATION_REGISTRY);

        vm.startBroadcast(deployerPrivateKey);
        Auctioneer auctioneer = new Auctioneer(LINK_TOKEN, AUTOMATION_REGISTRY);

        // Fund the contract with LINK tokens
        LinkTokenInterface link = LinkTokenInterface(LINK_TOKEN);
        uint256 fundingAmount = 10 * 10 ** 18; // 10 LINK tokens

        // Approve and transfer LINK tokens
        link.approve(address(auctioneer), fundingAmount);
        bool success = link.transfer(address(auctioneer), fundingAmount);
        require(success, "LINK transfer failed");

        console.log("Auctioneer deployed at:", address(auctioneer));
        console.log("Funding contract with", fundingAmount / 10 ** 18, "LINK tokens");

        vm.stopBroadcast();
    }
}
