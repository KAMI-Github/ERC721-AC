# KAMI721AC - Upgradeable ERC721A NFT Contract with Rentals

KAMI721AC is an advanced ERC721A NFT contract supporting batch minting (claiming), programmable royalties, rental functionality, and USDC payment integration. This repository contains both the standard implementation and an upgradeable version using OpenZeppelin's transparent proxy pattern.

## Features

-   **ERC721A Standard**: Efficient batch minting for reduced gas costs (claiming).
-   **ERC721 Standard Compatibility**: Fully compatible with the ERC721 standard.
-   **Programmable Royalties**: Configurable royalty distribution for both minting and transfers (ERC2981 compatible).
-   **Rental System**: Built-in functionality for renting NFTs with time-based access control (`userOf`).
-   **USDC Payments**: Integration with USDC for minting, selling, and rental payments.
-   **Platform Commission**: Configurable platform fee for all transactions.
-   **Role-Based Access Control**: Secure permission system for different contract functions.
-   **Upgradeable Architecture**: Transparent proxy pattern for future upgrades (optional).

## Contract Architecture

### KAMI721AC (Standard Version)

The standard KAMI721AC contract is a non-upgradeable ERC721A implementation with the following key components:

-   **ERC721A**: Inherits from `ERC721A` for efficient batch minting.
-   **Access Control**: Uses OpenZeppelin's `AccessControl` for role-based permissions.
-   **ERC2981**: Implements the ERC2981 standard for royalty information.
-   **Pausable**: Allows pausing of contract operations in emergencies.
-   **Rental Logic**: Includes structs and functions for NFT rentals.

### KAMI721ACUpgradeable

The upgradeable version consists of three main contracts:

1. **KAMI721ACUpgradeable.sol**: The implementation contract with UUPS upgradeability (inherits from `ERC721AUpgradeable`, `AccessControlUpgradeable`, etc.).
2. **KAMIProxyAdmin.sol**: The admin contract for managing the proxy.
3. **KAMITransparentUpgradeableProxy.sol**: The actual proxy contract.

## Installation

```bash
# Clone the repository (replace with your fork/repo URL)
git clone <your-repository-url>
cd ERC721-AC # Or your repository name

# Install dependencies
npm install
```

## Deployment

Update the `.env` file (copy from `.env.example`) with your network RPC URLs, private keys, Etherscan API key, and desired contract parameters (USDC address for the target network, NFT name, symbol, base URI, mint price, platform address, commission).

### Standard Contract

```bash
npx hardhat run scripts/deploy.ts --network <network-name>
```

### Upgradeable Contract

```bash
npx hardhat run scripts/deploy_upgradeable.ts --network <network-name>
```

## Usage Examples

(Examples assume `ethers` is set up and `kami` points to the deployed contract instance - either standard or the proxy address for upgradeable)

### Initializing the Contract (Deployment Script handles this)

// Deployment script example (deploy.ts for standard)
const KAMI721AC = await ethers.getContractFactory('KAMI721AC');
const kami = await KAMI721AC.deploy(
// ... constructor arguments ...
);
await kami.waitForDeployment();

// (For upgradeable, interaction is via proxy after deployment)

### Setting Royalties

// Set default mint royalties (percentages of remaining amount after platform fee)
const mintRoyalties = [
{ receiver: creatorAddress, feeNumerator: 9500 }, // 95%
];
await kami.connect(owner).setMintRoyalties(mintRoyalties);

// Set default transfer royalties (percentages of total royalty amount)
const transferRoyalties = [
{ receiver: creatorAddress, feeNumerator: 10000 }, // 100%
];
await kami.connect(owner).setTransferRoyalties(transferRoyalties);

### Minting NFTs (Claiming)

// Approve USDC spending for the total cost
const quantity = 5;
const totalCost = await kami.mintPrice() \* BigInt(quantity);
await usdc.connect(minter).approve(await kami.getAddress(), totalCost);

// Mint/Claim multiple NFTs
await kami.connect(minter).mint(quantity);

### Selling NFTs

// Approve the contract to transfer the token
// await kami.connect(seller).approve(await kami.getAddress(), tokenId); // Not needed if using sellToken

// Sell the token
const salePrice = ethers.parseUnits('200', 6);
await kami.connect(seller).sellToken(buyerAddress, tokenId, salePrice);

### Renting NFTs

// Renter approves USDC for rental price
const rentalDuration = 86400; // 1 day
const rentalPrice = ethers.parseUnits('50', 6);
await usdc.connect(renter).approve(await kami.getAddress(), rentalPrice);

// Rent a token (Payment goes directly to owner)
await kami.connect(renter).rentToken(tokenId, rentalDuration, rentalPrice);

// Check who the current user is (renter)
const currentUser = await kami.userOf(tokenId);
console.log('Current user:', currentUser);

// End a rental (owner or renter can end)
await kami.connect(owner).endRental(tokenId);

// Extend a rental
const additionalDuration = 43200; // 12 hours
const additionalPayment = ethers.parseUnits('25', 6);
await usdc.connect(renter).approve(await kami.getAddress(), additionalPayment);
await kami.connect(renter).extendRental(tokenId, additionalDuration, additionalPayment);

### Upgrading the Contract (Upgradeable Version Only)

```bash
# 1. Deploy the new implementation (e.g., KAMI721ACUpgradeableV2)
# (Potentially modify deploy script or manually deploy V2)

# 2. Run the upgrade script (update .env with proxy addresses and new implementation)
npx hardhat run scripts/upgrade.ts --network <network-name>
```

## Testing

Run the test suite:

```bash
npx hardhat test
# Or specific tests
npm run test:kami
npm run test:upgradeable
```

## Contract Functions

### Core Functions

-   `mint(uint256 quantity)`: Mint/Claim one or more new NFTs by paying the total mint price in USDC.
-   `sellToken(address to, uint256 tokenId, uint256 salePrice)`: Sell an NFT with royalty distribution.
-   `rentToken(uint256 tokenId, uint256 duration, uint256 rentalPrice)`: Rent an NFT for a specified duration (renter pays owner).
-   `endRental(uint256 tokenId)`: End a rental early (owner or renter).
-   `extendRental(uint256 tokenId, uint256 additionalDuration, uint256 additionalPayment)`: Extend a rental period (renter pays owner).
-   `userOf(uint256 tokenId)`: Returns the current user (owner or active renter).
-   `isUser(uint256 tokenId, address account)`: Checks if an account is the current user.

### Royalty Management

-   `setMintRoyalties(RoyaltyData[] calldata royalties)`: Set default royalties for minting.
-   `setTransferRoyalties(RoyaltyData[] calldata royalties)`: Set default royalties for transfers.
-   `setTokenMintRoyalties(uint256 tokenId, RoyaltyData[] calldata royalties)`: Set token-specific mint royalties.
-   `setTokenTransferRoyalties(uint256 tokenId, RoyaltyData[] calldata royalties)`: Set token-specific transfer royalties.
-   `getMintRoyaltyReceivers(uint256 tokenId)`: Get mint royalty receivers for a token (uses default if token-specific not set).
-   `getTransferRoyaltyReceivers(uint256 tokenId)`: Get transfer royalty receivers for a token (uses default if token-specific not set).
-   `royaltyInfo(uint256 tokenId, uint256 salePrice)`: ERC2981 standard function for royalty info.

### Configuration

-   `setMintPrice(uint256 newMintPrice)`: Set the mint price per token.
-   `setPlatformCommission(uint96 newPlatformCommissionPercentage, address newPlatformAddress)`: Set platform commission details.
-   `setRoyaltyPercentage(uint96 newRoyaltyPercentage)`: Set the _total_ royalty percentage for transfers (relative to sale price).
-   `setBaseURI(string memory baseURI)`: Set the base URI for token metadata.
-   `setTransferValidator(address _validator)`: Set the address for an optional transfer validator contract (for LimitBreak compliance or custom rules).

### Administrative

-   `pause()`: Pause the contract (requires admin role).
-   `unpause()`: Unpause the contract (requires admin role).
-   `burn(uint256 tokenId)`: Burn an NFT (standard ERC721A burn, may be restricted or removed based on exact `ERC721A` version/config). Transfer restrictions apply if rented.
-   `upgradeTo(address newImplementation)` (UUPS - called via ProxyAdmin): Upgrades the contract implementation (upgradeable version only).

## Roles

-   `DEFAULT_ADMIN_ROLE`: Can manage all roles, pause/unpause, upgrade (if UUPS).
-   `OWNER_ROLE`: Can configure the contract (prices, royalties, URIs, validator) and manage royalties.
-   `PLATFORM_ROLE`: Receives platform commission.
-   `RENTER_ROLE`: Granted to users who actively rent NFTs.
-   `UPGRADER_ROLE` (Upgradeable only): Can upgrade the implementation via UUPS (if granted separately from admin).

## License

MIT
