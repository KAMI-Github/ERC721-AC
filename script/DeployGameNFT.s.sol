// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {GameNFT} from "../contracts/GameNFT.sol";

contract DeployGameNFT is Script {
    function run() public returns (GameNFT) {
        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy the GameNFT contract
        GameNFT gameNFT = new GameNFT(
            msg.sender,                // royalty receiver
            500,                       // 5% royalty fee (500 / 10000)
            "Game NFT Collection",     // name
            "GNFT",                    // symbol
            "https://example.com/api/" // base URI
        );

        // Stop broadcasting transactions
        vm.stopBroadcast();

        return gameNFT;
    }
} 