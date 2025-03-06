// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20
 * @dev Mock ERC20 token for testing USDC functionality
 */
contract MockERC20 is ERC20 {
    uint8 private _decimals;
    uint256 public constant INITIAL_SUPPLY = 1000000; // 1 million tokens
    
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_
    ) ERC20(name, symbol) {
        _decimals = decimals_;
        
        // Mint initial supply to the deployer
        _mint(msg.sender, INITIAL_SUPPLY * (10 ** decimals_));
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
} 