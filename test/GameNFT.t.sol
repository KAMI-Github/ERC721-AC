// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {GameNFT} from "../contracts/GameNFT.sol";

contract GameNFTTest is Test {
    GameNFT public gameNFT;
    address public owner = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    address public royaltyReceiver = address(4);
    uint96 public royaltyFeeNumerator = 500; // 5%
    
    function setUp() public {
        vm.startPrank(owner);
        gameNFT = new GameNFT(
            royaltyReceiver,
            royaltyFeeNumerator,
            "Game NFT Collection",
            "GNFT",
            "https://example.com/api/"
        );
        vm.stopPrank();
    }
    
    function testMint() public {
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        gameNFT.mint{value: 0.1 ether}();
        
        assertEq(gameNFT.ownerOf(0), user1);
        assertEq(address(gameNFT).balance, 0.1 ether);
    }
    
    function testWithdraw() public {
        // First mint an NFT to add funds to the contract
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        gameNFT.mint{value: 0.1 ether}();
        
        // Check owner's balance before withdrawal
        uint256 ownerBalanceBefore = owner.balance;
        
        // Owner withdraws funds
        vm.prank(owner);
        gameNFT.withdraw();
        
        // Check balances after withdrawal
        assertEq(address(gameNFT).balance, 0);
        assertEq(owner.balance, ownerBalanceBefore + 0.1 ether);
    }
    
    function testRoyaltyInfo() public {
        // Mint an NFT
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        gameNFT.mint{value: 0.1 ether}();
        
        // Check royalty info
        (address receiver, uint256 royaltyAmount) = gameNFT.royaltyInfo(0, 1 ether);
        
        assertEq(receiver, royaltyReceiver);
        assertEq(royaltyAmount, 0.05 ether); // 5% of 1 ether
    }
    
    function testSetSecurityPolicy() public {
        uint8 securityLevel = 1;
        uint32 operatorWhitelistId = 100;
        uint32 permittedContractReceiversAllowlistId = 200;
        
        vm.prank(owner);
        gameNFT.setSecurityPolicy(
            securityLevel,
            operatorWhitelistId,
            permittedContractReceiversAllowlistId
        );
        
        // Note: We can't directly test the security policy values as they're stored in the
        // CreatorTokenBaseStorage layout, but we can test that the function doesn't revert
        // when called by the owner
    }
    
    function test_RevertWhen_SetSecurityPolicyNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        gameNFT.setSecurityPolicy(1, 100, 200);
    }
} 