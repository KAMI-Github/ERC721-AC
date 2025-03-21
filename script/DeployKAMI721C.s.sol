// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {KAMI721C} from "../contracts/KAMI721C.sol";
import {MockERC20} from "../contracts/MockERC20.sol";

contract DeployKAMI721C is Script {
    // USDC addresses on different networks
    address constant USDC_ETHEREUM_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDC_GOERLI = 0x07865c6E87B9F70255377e024ace6630C1Eaa37F;
    address constant USDC_SEPOLIA = 0xda9d4f9b69ac6C22e444eD9aF0CfC043b7a7f53f;
    address constant USDC_POLYGON = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address constant USDC_MUMBAI = 0x0FA8781a83E46826621b3BC094Ea2A0212e71B23;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Determine USDC address based on the current network
        address usdcAddress;
        uint256 chainId = block.chainid;

        if (chainId == 1) {
            // Ethereum Mainnet
            usdcAddress = USDC_ETHEREUM_MAINNET;
            console2.log("Using Ethereum Mainnet USDC:", usdcAddress);
        } else if (chainId == 5) {
            // Goerli
            usdcAddress = USDC_GOERLI;
            console2.log("Using Goerli USDC:", usdcAddress);
        } else if (chainId == 11155111) {
            // Sepolia
            usdcAddress = USDC_SEPOLIA;
            console2.log("Using Sepolia USDC:", usdcAddress);
        } else if (chainId == 137) {
            // Polygon
            usdcAddress = USDC_POLYGON;
            console2.log("Using Polygon USDC:", usdcAddress);
        } else if (chainId == 80001) {
            // Mumbai
            usdcAddress = USDC_MUMBAI;
            console2.log("Using Mumbai USDC:", usdcAddress);
        } else {
            // For local networks, deploy a mock USDC token
            console2.log("Local network detected. Deploying MockERC20 token...");
            MockERC20 mockUsdc = new MockERC20("USD Coin", "USDC", 6);
            usdcAddress = address(mockUsdc);
            console2.log("Deployed MockERC20 at:", usdcAddress);
        }

        // Deploy KAMI721C
        string memory nftName = "KAMI NFT";
        string memory nftSymbol = "KAMI";
        string memory baseURI = "https://api.example.com/token/";
        uint256 mintPrice = 1 * 10**6; // 1 USDC (6 decimals)
        address platformAddress = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // Replace with your desired platform address
        uint96 platformCommission = 500; // 5% platform commission
        
        KAMI721C kami721c = new KAMI721C(
            usdcAddress,
            nftName,
            nftSymbol,
            baseURI,
            mintPrice,
            platformAddress,
            platformCommission
        );
        
        console2.log("KAMI721C deployed at:", address(kami721c));
        
        // Add deployer to the renter role for testing
        kami721c.grantRole(kami721c.RENTER_ROLE(), msg.sender);
        console2.log("Added deployer to RENTER_ROLE");

        console2.log("Deployment completed successfully!");
        vm.stopBroadcast();
    }
} 