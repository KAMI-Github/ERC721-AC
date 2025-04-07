# KAMI721C - Upgradeable ERC721 NFT Contract

KAMI721C is an advanced ERC721 NFT contract with programmable royalties, rental functionality, and USDC payment integration. This repository contains both the standard implementation and an upgradeable version using OpenZeppelin's transparent proxy pattern.

## Features

-   **ERC721 Standard**: Implements the ERC721 standard for non-fungible tokens
-   **Programmable Royalties**: Configurable royalty distribution for both minting and transfers
-   **Rental System**: Built-in functionality for renting NFTs with time-based access control
-   **USDC Payments**: Integration with USDC for minting, selling, and rental payments
-   **Platform Commission**: Configurable platform fee for all transactions
-   **Role-Based Access Control**: Secure permission system for different contract functions
-   **Upgradeable Architecture**: Transparent proxy pattern for future upgrades

## Contract Architecture

### KAMI721C (Standard Version)

The standard KAMI721C contract is a non-upgradeable ERC721 implementation with the following key components:

-   **Access Control**: Uses OpenZeppelin's AccessControl for role-based permissions
-   **ERC2981**: Implements the ERC2981 standard for royalty information
-   **ERC721Enumerable**: Extends ERC721 with enumeration capabilities
-   **Pausable**: Allows pausing of contract operations in emergencies

### KAMI721CUpgradeable

The upgradeable version consists of three main contracts:

1. **KAMI721CUpgradeable.sol**: The implementation contract with UUPS upgradeability
2. **KAMIProxyAdmin.sol**: The admin contract for managing the proxy
3. **KAMITransparentUpgradeableProxy.sol**: The actual proxy contract

## Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/KAMI721C.git
cd KAMI721C

# Install dependencies
npm install
```

## Deployment

### Standard Contract

```bash
npx hardhat run scripts/deploy.ts --network <network-name>
```

### Upgradeable Contract

```bash
npx hardhat run scripts/deploy_upgradeable.ts --network <network-name>
```

## Usage Examples

### Initializing the Contract

```javascript
// Deploy the contract
const KAMI721C = await ethers.getContractFactory('KAMI721C');
const kami = await KAMI721C.deploy(
	usdcAddress,
	'KAMI NFT',
	'KAMI',
	'https://api.kami.example/metadata/',
	ethers.parseUnits('100', 6), // 100 USDC mint price
	platformAddress,
	500 // 5% platform commission
);
await kami.deployed();
```

### Setting Royalties

```javascript
// Set mint royalties
const mintRoyalties = [
	{
		receiver: creatorAddress,
		feeNumerator: 9500, // 95% of royalties
	},
];
await kami.setMintRoyalties(mintRoyalties);

// Set transfer royalties
const transferRoyalties = [
	{
		receiver: creatorAddress,
		feeNumerator: 10000, // 100% of royalties
	},
];
await kami.setTransferRoyalties(transferRoyalties);
```

### Minting NFTs

```javascript
// Approve USDC spending
await usdc.approve(kami.address, ethers.parseUnits('100', 6));

// Mint an NFT
await kami.mint();
```

### Selling NFTs

```javascript
// Approve the contract to transfer the token
await kami.approve(kami.address, tokenId);

// Sell the token
const salePrice = ethers.parseUnits('200', 6);
await kami.sellToken(buyerAddress, tokenId, salePrice);
```

### Renting NFTs

```javascript
// Rent a token
const rentalDuration = 86400; // 1 day in seconds
const rentalPrice = ethers.parseUnits('50', 6);
await kami.rentToken(tokenId, rentalDuration, rentalPrice);

// End a rental
await kami.endRental(tokenId);

// Extend a rental
const additionalDuration = 43200; // 12 hours
const additionalPayment = ethers.parseUnits('25', 6);
await kami.extendRental(tokenId, additionalDuration, additionalPayment);
```

### Upgrading the Contract

```javascript
// Deploy a new implementation
const KAMI721CUpgradeableV2 = await ethers.getContractFactory('KAMI721CUpgradeableV2');
await upgrades.upgradeProxy(proxyAddress, KAMI721CUpgradeableV2);
```

## Testing

Run the test suite:

```bash
npx hardhat test
```

## Contract Functions

### Core Functions

-   `mint()`: Mint a new NFT by paying the mint price in USDC
-   `sellToken(address to, uint256 tokenId, uint256 salePrice)`: Sell an NFT with royalty distribution
-   `rentToken(uint256 tokenId, uint256 duration, uint256 rentalPrice)`: Rent an NFT for a specified duration
-   `endRental(uint256 tokenId)`: End a rental early
-   `extendRental(uint256 tokenId, uint256 additionalDuration, uint256 additionalPayment)`: Extend a rental period

### Royalty Management

-   `setMintRoyalties(RoyaltyData[] calldata royalties)`: Set default royalties for minting
-   `setTransferRoyalties(RoyaltyData[] calldata royalties)`: Set default royalties for transfers
-   `setTokenMintRoyalties(uint256 tokenId, RoyaltyData[] calldata royalties)`: Set token-specific mint royalties
-   `setTokenTransferRoyalties(uint256 tokenId, RoyaltyData[] calldata royalties)`: Set token-specific transfer royalties
-   `getMintRoyaltyReceivers(uint256 tokenId)`: Get mint royalty receivers for a token
-   `getTransferRoyaltyReceivers(uint256 tokenId)`: Get transfer royalty receivers for a token

### Configuration

-   `setMintPrice(uint256 newMintPrice)`: Set the mint price
-   `setPlatformCommission(uint96 newPlatformCommissionPercentage, address newPlatformAddress)`: Set platform commission
-   `setRoyaltyPercentage(uint96 newRoyaltyPercentage)`: Set the royalty percentage for transfers
-   `setBaseURI(string memory baseURI)`: Set the base URI for token metadata

### Administrative

-   `pause()`: Pause the contract
-   `unpause()`: Unpause the contract
-   `burn(uint256 tokenId)`: Burn an NFT

## Roles

-   `DEFAULT_ADMIN_ROLE`: Can manage all roles
-   `OWNER_ROLE`: Can configure the contract and manage royalties
-   `PLATFORM_ROLE`: Receives platform commission
-   `RENTER_ROLE`: Granted to users who rent NFTs
-   `UPGRADER_ROLE`: Can upgrade the implementation (upgradeable version only)

## License

MIT
