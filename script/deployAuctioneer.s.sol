// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {Auctioneer} from "../src/Auctioneer.sol";

contract DeployAuctioneer is Script {
    // Chainlink contract addresses on Mainnet Sepolia
    // address constant LINK_TOKEN = 0x779877A7B0D9E8603169DdbD7836e478b4624789;
    // address constant AUTOMATION_REGISTRY = 0x86EFBD0b6736Bed994962f9797049422A3A8E8Ad;
    // address constant AUTOMATION_REGISTRAR = 0xb0E49c5D0d05cbc241d68c05BC5BA1d1B7B72976;

    // Chainlink contract addresses on Base Sepolia
    address constant LINK_TOKEN = 0xE4aB69C077896252FAFBD49EFD26B5D171A32410;
    address constant AUTOMATION_REGISTRY = 0x91D4a4C3D448c7f3CB477332B1c7D420a5810aC3;
    address constant AUTOMATION_REGISTRAR = 0xf28D56F3A707E25B71Ce529a21AF388751E1CF2A;

    function run() external returns (Auctioneer) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy Auctioneer
        Auctioneer auctioneer = new Auctioneer(LINK_TOKEN, AUTOMATION_REGISTRAR, AUTOMATION_REGISTRY);

        vm.stopBroadcast();

        console.log("Auctioneer deployed to:", address(auctioneer));

        return auctioneer;

        // NOTE: Fund the Auctioneer with LINK manually
    }
}
