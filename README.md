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
-   **NFT Rental System**: Built-in rental functionality with automatic expiration and transfer restrictions
-   **Rental Extensions**: Support for extending rental periods with additional payments
-   **Rental Protection**: Prevents token transfers, sales, and burns during active rental periods

## 📋 Prerequisites

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
npm install
```

### 3. Configure the deployment

Create or modify the `.env` file with the necessary configuration:

```
# Network RPC URLs
MAINNET_RPC_URL=https://eth-mainnet.alchemyapi.io/v2/your-api-key
GOERLI_RPC_URL=https://eth-goerli.alchemyapi.io/v2/your-api-key
SEPOLIA_RPC_URL=https://eth-sepolia.alchemyapi.io/v2/your-api-key
POLYGON_RPC_URL=https://polygon-mainnet.alchemyapi.io/v2/your-api-key
MUMBAI_RPC_URL=https://polygon-mumbai.alchemyapi.io/v2/your-api-key

# Private key for deployment
PRIVATE_KEY=your-private-key

# Contract configuration
NFT_NAME="KAMI NFT Collection"
NFT_SYMBOL="KAMI"
BASE_URI="https://your-metadata-api.com/tokens/"
SECURITY_LEVEL=1

# API keys for verification
ETHERSCAN_API_KEY=your-etherscan-api-key
POLYGONSCAN_API_KEY=your-polygonscan-api-key
```

### 4. Deploy to your chosen network

```shell
# Local development
npm run deploy:local

# Test networks
npm run deploy:goerli
npm run deploy:sepolia
npm run deploy:mumbai

# Production networks
npm run deploy:polygon
npm run deploy:mainnet
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

```javascript
// Example to grant RENTER_ROLE to an address using ethers.js
const roleHash = ethers.keccak256(ethers.toUtf8Bytes('RENTER_ROLE'));
await nftContract.grantRole(roleHash, accountAddress);
```

#### `revokeRole(bytes32 role, address account)`

Revokes a role from an account. Can only be called by accounts with the DEFAULT_ADMIN_ROLE.

```javascript
// Example to revoke RENTER_ROLE from an address using ethers.js
const roleHash = ethers.keccak256(ethers.toUtf8Bytes('RENTER_ROLE'));
await nftContract.revokeRole(roleHash, accountAddress);
```

#### `hasRole(bytes32 role, address account)`

Checks if an account has a specific role.

```javascript
// Example to check if an address has OWNER_ROLE using ethers.js
const roleHash = ethers.keccak256(ethers.toUtf8Bytes('OWNER_ROLE'));
const hasRole = await nftContract.hasRole(roleHash, accountAddress);
```

## 📝 External Methods Guide

### Core Functions

#### `mint()`

Allows users to mint a new NFT by paying the fixed USDC mint price.

```javascript
// First approve USDC spending
await usdcContract.approve(nftContractAddress, mintPrice);
// Then mint the NFT
await nftContract.mint();
```

**Note**: Users must first approve the contract to spend their USDC.

#### `burn(uint256 tokenId)`

Allows the token owner to burn their NFT.

```javascript
await nftContract.burn(tokenId);
```

### Royalty Management

#### `setMintRoyalties(RoyaltyData[] calldata royalties)`

Sets global royalties distributed during minting. Only callable by users with OWNER_ROLE.

```javascript
// Example to set 5% royalty to address1 and 3% to address2
const royalties = [
	{ receiver: address1, feeNumerator: 500 }, // 5%
	{ receiver: address2, feeNumerator: 300 }, // 3%
];
await nftContract.setMintRoyalties(royalties);
```

#### `setTransferRoyalties(RoyaltyData[] calldata royalties)`

Sets global royalties for token transfers. Only callable by users with OWNER_ROLE.

```javascript
// Example to set transfer royalties that total to 100%
const royalties = [
	{ receiver: address1, feeNumerator: 7000 }, // 70%
	{ receiver: address2, feeNumerator: 3000 }, // 30%
];
await nftContract.setTransferRoyalties(royalties);
```

#### `setTokenMintRoyalties(uint256 tokenId, RoyaltyData[] calldata royalties)`

Sets token-specific mint royalties. Only callable by users with OWNER_ROLE.

```javascript
// Example for token ID 0
const royalties = [
	{ receiver: address1, feeNumerator: 400 }, // 4%
	{ receiver: address2, feeNumerator: 200 }, // 2%
];
await nftContract.setTokenMintRoyalties(0, royalties);
```

#### `setTokenTransferRoyalties(uint256 tokenId, RoyaltyData[] calldata royalties)`

Sets token-specific transfer royalties. Only callable by users with OWNER_ROLE.

```javascript
// Example for token ID 0
const royalties = [
	{ receiver: address1, feeNumerator: 7000 }, // 70%
	{ receiver: address2, feeNumerator: 3000 }, // 30%
];
await nftContract.setTokenTransferRoyalties(0, royalties);
```

### Transfer Functions

#### `sellToken(address to, uint256 tokenId, uint256 salePrice)`

Allows the token owner to sell the token directly through the contract, handling all royalty and fee payments automatically.

```javascript
// First, buyer needs to approve USDC spending
await usdcContract.connect(buyerSigner).approve(nftContractAddress, salePrice);
// Then seller initiates the sale
await nftContract.connect(sellerSigner).sellToken(buyerAddress, tokenId, salePrice);
```

### Administrative Functions

#### `setBaseURI(string memory baseURI)`

Updates the base URI for token metadata. Only callable by users with OWNER_ROLE.

```javascript
await nftContract.setBaseURI('https://new-metadata-api.com/tokens/');
```

#### `setPlatformCommission(uint96 newPlatformCommissionPercentage, address newPlatformAddress)`

Updates the platform commission percentage and platform address. Only callable by users with OWNER_ROLE.

```javascript
// Set 8% commission and update platform address
await nftContract.setPlatformCommission(800, newPlatformAddress);
```

#### `setSecurityPolicy(uint8 securityLevel, uint32 operatorWhitelistId, uint32 permittedContractReceiversAllowlistId)`

Sets the security policy for the ERC721C implementation. Only callable by users with OWNER_ROLE.

```javascript
// Set security policy
await nftContract.setSecurityPolicy(
	2, // Security level
	1, // Operator whitelist ID
	1 // Permitted contract receivers allowlist ID
);
```

### View Functions

#### `hasRole(bytes32 role, address account)`

Checks if an account has a specific role.

```javascript
const roleHash = ethers.keccak256(ethers.toUtf8Bytes('OWNER_ROLE'));
const hasRole = await nftContract.hasRole(roleHash, accountAddress);
```

#### `getMintRoyaltyReceivers(uint256 tokenId)`

Returns all mint royalty receivers for a given token.

```javascript
const mintRoyaltyReceivers = await nftContract.getMintRoyaltyReceivers(tokenId);
```

#### `getTransferRoyaltyReceivers(uint256 tokenId)`

Returns all transfer royalty receivers for a given token.

```javascript
const transferRoyaltyReceivers = await nftContract.getTransferRoyaltyReceivers(tokenId);
```

#### `royaltyInfo(uint256 tokenId, uint256 salePrice)`

Returns royalty information according to ERC2981.

```javascript
const [receiver, royaltyAmount] = await nftContract.royaltyInfo(tokenId, salePrice);
```

## 🏠 Rental System

The KAMI721C contract includes a comprehensive rental system that allows NFT owners to rent out their tokens while maintaining ownership and receiving rental payments.

### Rental Functions

#### `rentToken(uint256 tokenId, uint256 duration, uint256 rentalPrice)`

Allows a user to rent a token for a specified duration by paying the rental price in USDC.

```javascript
// First approve USDC spending
const rentalDuration = 86400; // 1 day in seconds
const rentalPrice = ethers.parseUnits('0.5', 6); // 0.5 USDC
await usdcContract.approve(nftContractAddress, rentalPrice);

// Then rent the token
await nftContract.rentToken(tokenId, rentalDuration, rentalPrice);
```

**Note**: The rental price is distributed between the token owner and the platform based on the platform commission percentage.

#### `extendRental(uint256 tokenId, uint256 additionalDuration, uint256 additionalPayment)`

Allows the current renter to extend their rental period by making an additional payment.

```javascript
// First approve USDC spending
const additionalDuration = 43200; // 12 hours in seconds
const additionalPayment = ethers.parseUnits('0.25', 6); // 0.25 USDC
await usdcContract.approve(nftContractAddress, additionalPayment);

// Then extend the rental
await nftContract.extendRental(tokenId, additionalDuration, additionalPayment);
```

#### `endRental(uint256 tokenId)`

Allows either the token owner or the renter to end a rental early.

```javascript
await nftContract.endRental(tokenId);
```

### Rental Information

#### `isRented(uint256 tokenId)`

Checks if a token is currently rented.

```javascript
const isRented = await nftContract.isRented(tokenId);
```

#### `getRentalInfo(uint256 tokenId)`

Retrieves detailed information about a token's rental status.

```javascript
const { renter, startTime, endTime, rentalPrice, active } = await nftContract.getRentalInfo(tokenId);
```

### Rental Restrictions

During an active rental period:

-   The token cannot be transferred by the owner
-   The token cannot be sold using the `sellToken` function
-   The token cannot be burned
-   Only the renter can extend the rental period
-   The rental can be ended early by either the owner or renter
-   The rental automatically expires after the rental period, allowing the owner to transfer the token again

### Rental Events

The contract emits the following events related to rentals:

-   `TokenRented(uint256 tokenId, address owner, address renter, uint256 startTime, uint256 endTime, uint256 rentalPrice)`
-   `RentalEnded(uint256 tokenId, address owner, address renter)`
-   `RentalExtended(uint256 tokenId, address renter, uint256 newEndTime)`

These events can be used to track rental activity and update off-chain systems.

## 🧪 Testing

Run the test suite to verify the contract's functionality:

```shell
# Run all tests
npm test

# Run specific KAMI721C tests
npm run test:kami
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
