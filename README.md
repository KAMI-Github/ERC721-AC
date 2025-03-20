# 🎮 KAMI721-C Smart Contract Documentation

<div align="center">
  <img src="https://img.shields.io/badge/Solidity-^0.8.24-red.svg" alt="Solidity Version">
  <img src="https://img.shields.io/badge/ERC721C-Compliant-blue.svg" alt="ERC721C Compliant">
  <img src="https://img.shields.io/badge/ERC2981-Royalties-green.svg" alt="ERC2981 Royalties">
  <img src="https://img.shields.io/badge/AccessControl-Role_Based-purple.svg" alt="Role-Based Access Control">
</div>

## 📑 Overview

The `KAMI721C` contract is a modern implementation of an NFT collection that leverages USDC for payments and includes advanced royalty distribution capabilities. Built on ERC721C with support for multiple royalty receivers for both minting and transfers, it provides a flexible solution for game asset tokenization with role-based access control.

## 🔧 Features

-   **Role-Based Access Control**: Utilizes OpenZeppelin's AccessControl for flexible permission management
-   **Multiple Roles**: Includes OWNER_ROLE, RENTER_ROLE, and PLATFORM_ROLE for granular access control
-   **USDC Payments**: All transactions use USDC instead of native ETH
-   **Multiple Royalty Receivers**: Supports multiple royalty recipients for both minting and transfers
-   **Token-Specific Royalties**: Set different royalty structures per token
-   **ERC2981 Compatible**: Full support for on-chain royalty information
-   **Flexible Transfers**: Manual royalty payments or automatic distribution during transfers
-   **Secure Access Management**: Role-based permissions for administrative functions

## 📋 Prerequisites

-   [Foundry](https://book.getfoundry.sh/getting-started/installation) installed
-   [Node.js](https://nodejs.org/) and npm/yarn installed
-   Access to an RPC provider for deployment (Infura, Alchemy, etc.)
-   USDC contract address on your target network

## 🚀 Deployment Instructions

### 1. Clone the repository

```shell
git clone <repository-url>
cd <repository-directory>
```

### 2. Install dependencies

```shell
forge install
npm install
```

### 3. Configure the deployment

Edit the deployment script in `script/DeployKAMI721C.s.sol` to use the correct USDC address for your target network:

```solidity
// Example for Polygon
KAMI721C kami721c = new KAMI721C(
    0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174, // USDC address on Polygon
    "KAMI NFT Collection",                       // name
    "KAMI",                                      // symbol
    "https://your-metadata-api.com/tokens/"      // base URI
);
```

### 4. Deploy to your chosen network

```shell
forge script script/DeployKAMI721C.s.sol:DeployKAMI721C --rpc-url <your_rpc_url> --private-key <your_private_key> --broadcast
```

## 🔐 Role-Based Access Control

The contract implements OpenZeppelin's AccessControl pattern with the following roles:

### Available Roles

-   **OWNER_ROLE**: Administrative role with permissions to manage contract settings, royalties, and platform commissions
-   **RENTER_ROLE**: Role designed for users who can rent or temporarily use NFTs
-   **PLATFORM_ROLE**: Special role for the platform address that receives commission fees

### Role Management

#### `grantRole(bytes32 role, address account)`

Grants a role to an account. Can only be called by accounts with the DEFAULT_ADMIN_ROLE.

```shell
# Example to grant RENTER_ROLE to an address
cast send --rpc-url <rpc_url> \
  --private-key <admin_private_key> \
  <contract_address> \
  "grantRole(bytes32,address)" \
  $(cast keccak "RENTER_ROLE") \
  <account_address>
```

#### `revokeRole(bytes32 role, address account)`

Revokes a role from an account. Can only be called by accounts with the DEFAULT_ADMIN_ROLE.

```shell
# Example to revoke RENTER_ROLE from an address
cast send --rpc-url <rpc_url> \
  --private-key <admin_private_key> \
  <contract_address> \
  "revokeRole(bytes32,address)" \
  $(cast keccak "RENTER_ROLE") \
  <account_address>
```

#### `hasRole(bytes32 role, address account)`

Checks if an account has a specific role.

```shell
# Example to check if an address has OWNER_ROLE
cast call --rpc-url <rpc_url> \
  <contract_address> \
  "hasRole(bytes32,address)" \
  $(cast keccak "OWNER_ROLE") \
  <account_address>
```

## 📝 External Methods Guide

### Core Functions

#### `mint()`

Allows users to mint a new NFT by paying the fixed USDC mint price.

```shell
# Using Cast
cast send --rpc-url <rpc_url> \
  --private-key <your_private_key> \
  <contract_address> \
  "mint()"
```

**Note**: Users must first approve the contract to spend their USDC.

#### `burn(uint256 tokenId)`

Allows the token owner to burn their NFT.

```shell
cast send --rpc-url <rpc_url> \
  --private-key <your_private_key> \
  <contract_address> \
  "burn(uint256)" \
  <token_id>
```

### Royalty Management

#### `setMintRoyalties(RoyaltyData[] calldata royalties)`

Sets global royalties distributed during minting. Only callable by users with OWNER_ROLE.

```shell
# Example to set 5% royalty to address1 and 3% to address2
cast send --rpc-url <rpc_url> \
  --private-key <owner_private_key> \
  <contract_address> \
  "setMintRoyalties(((address,uint96)[]))" \
  "[(<address1>,500),(<address2>,300)]"
```

#### `setTransferRoyalties(RoyaltyData[] calldata royalties)`

Sets global royalties for token transfers. Only callable by users with OWNER_ROLE.

```shell
# Example to set 7% royalty to address1
cast send --rpc-url <rpc_url> \
  --private-key <owner_private_key> \
  <contract_address> \
  "setTransferRoyalties(((address,uint96)[]))" \
  "[(<address1>,700)]"
```

#### `setTokenMintRoyalties(uint256 tokenId, RoyaltyData[] calldata royalties)`

Sets token-specific mint royalties. Only callable by users with OWNER_ROLE.

```shell
# Example for token ID 0
cast send --rpc-url <rpc_url> \
  --private-key <owner_private_key> \
  <contract_address> \
  "setTokenMintRoyalties(uint256,(address,uint96)[])" \
  0 \
  "[(<address1>,400),(<address2>,200)]"
```

#### `setTokenTransferRoyalties(uint256 tokenId, RoyaltyData[] calldata royalties)`

Sets token-specific transfer royalties. Only callable by users with OWNER_ROLE.

```shell
# Example for token ID 0
cast send --rpc-url <rpc_url> \
  --private-key <owner_private_key> \
  <contract_address> \
  "setTokenTransferRoyalties(uint256,(address,uint96)[])" \
  0 \
  "[(<address1>,400),(<address2>,200)]"
```

### Transfer Functions

#### `setTransferPrice(uint256 tokenId, uint256 price)`

Sets a transfer price for a token. This price is used for royalty calculations. Only callable by token owner.

```shell
# Example to set 500 USDC as transfer price
cast send --rpc-url <rpc_url> \
  --private-key <your_private_key> \
  <contract_address> \
  "setTransferPrice(uint256,uint256)" \
  <token_id> \
  500000000  # 500 USDC with 6 decimals
```

#### `payTransferRoyalties(uint256 tokenId)`

Allows anyone to pay the transfer royalties for a token. The transfer price must be set first.

```shell
cast send --rpc-url <rpc_url> \
  --private-key <your_private_key> \
  <contract_address> \
  "payTransferRoyalties(uint256)" \
  <token_id>
```

**Note**: User must first approve the contract to spend the required USDC.

#### `safeTransferFromWithRoyalties(address from, address to, uint256 tokenId, uint256 salePrice, bytes memory data)`

Transfers a token and handles royalty payments in one transaction.

```shell
cast send --rpc-url <rpc_url> \
  --private-key <your_private_key> \
  <contract_address> \
  "safeTransferFromWithRoyalties(address,address,uint256,uint256,bytes)" \
  <from_address> \
  <to_address> \
  <token_id> \
  500000000  # 500 USDC with 6 decimals
  0x         # Empty bytes
```

**Note**: User must first approve the contract to spend the required USDC.

### Administrative Functions

#### `withdrawUSDC()`

Allows users with OWNER_ROLE to withdraw all USDC held by the contract.

```shell
cast send --rpc-url <rpc_url> \
  --private-key <owner_private_key> \
  <contract_address> \
  "withdrawUSDC()"
```

#### `setBaseURI(string memory baseURI)`

Updates the base URI for token metadata. Only callable by users with OWNER_ROLE.

```shell
cast send --rpc-url <rpc_url> \
  --private-key <owner_private_key> \
  <contract_address> \
  "setBaseURI(string)" \
  "https://new-metadata-api.com/tokens/"
```

#### `setPlatformCommission(uint96 newPlatformCommissionPercentage, address newPlatformAddress)`

Updates the platform commission percentage and platform address. Only callable by users with OWNER_ROLE.

```shell
cast send --rpc-url <rpc_url> \
  --private-key <owner_private_key> \
  <contract_address> \
  "setPlatformCommission(uint96,address)" \
  800 \  # 8% commission
  <new_platform_address>
```

#### `setSecurityPolicy(uint8 securityLevel, uint32 operatorWhitelistId, uint32 permittedContractReceiversAllowlistId)`

Sets the security policy for the ERC721C implementation. Only callable by users with OWNER_ROLE.

```shell
cast send --rpc-url <rpc_url> \
  --private-key <owner_private_key> \
  <contract_address> \
  "setSecurityPolicy(uint8,uint32,uint32)" \
  2  # Security level
  1  # Operator whitelist ID
  1  # Permitted contract receivers allowlist ID
```

### View Functions

#### `hasRole(bytes32 role, address account)`

Checks if an account has a specific role.

```shell
cast call --rpc-url <rpc_url> \
  <contract_address> \
  "hasRole(bytes32,address)" \
  <role_bytes32> \
  <account_address>
```

#### `getMintRoyaltyReceivers(uint256 tokenId)`

Returns all mint royalty receivers for a given token.

```shell
cast call --rpc-url <rpc_url> \
  <contract_address> \
  "getMintRoyaltyReceivers(uint256)" \
  <token_id>
```

#### `getTransferRoyaltyReceivers(uint256 tokenId)`

Returns all transfer royalty receivers for a given token.

```shell
cast call --rpc-url <rpc_url> \
  <contract_address> \
  "getTransferRoyaltyReceivers(uint256)" \
  <token_id>
```

#### `royaltyInfo(uint256 tokenId, uint256 salePrice)`

Returns royalty information according to ERC2981.

```shell
cast call --rpc-url <rpc_url> \
  <contract_address> \
  "royaltyInfo(uint256,uint256)" \
  <token_id> \
  <sale_price>
```

## 🧪 Testing

Run the comprehensive test suite to verify the contract's functionality:

```shell
# Run Foundry tests
forge test

# Run TypeScript tests
npx hardhat test
```

## ⚠️ Important Notes

-   The maximum total royalty for any operation is 25%.
-   USDC tokens must be approved before minting or paying royalties.
-   The contract uses USDC with 6 decimals. Adjust values accordingly if using a different token.
-   This contract inherits from ERC721C, which includes additional transfer security mechanics.
-   Role management is controlled by accounts with the DEFAULT_ADMIN_ROLE.
-   When deploying, the deployer automatically receives the OWNER_ROLE and DEFAULT_ADMIN_ROLE.

## 📜 License

This project is licensed under the MIT License.

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/DeployKAMI721C.s.sol:DeployKAMI721C --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
