// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {Auctioneer} from "../src/Auctioneer.sol";

contract DeployAuctioneer is Script {
    address constant LINK_TOKEN = 0x779877A7B0D9E8603169DdbD7836e478b4624789;
    address constant AUTOMATION_REGISTRAR = 0xb0E49c5D0d05cbc241d68c05BC5BA1d1B7B72976;

    function run() external returns (Auctioneer) {
        vm.startBroadcast();

        Auctioneer auctioneer = new Auctioneer(LINK_TOKEN, AUTOMATION_REGISTRAR);

        vm.stopBroadcast();

        console.log("Auctioneer deployed to:", address(auctioneer));

        return auctioneer;
    }
}
