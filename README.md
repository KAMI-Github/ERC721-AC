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

## Supported Interfaces (ERC165)

The contract explicitly supports the following interfaces via `supportsInterface`:

-   `IERC165` (0x01ffc9a7)
-   `IERC721` (0x80ac58cd)
-   `IERC721Metadata` (0x5b5e139f)
-   `IAccessControl` (0x7965db0b)
-   `IERC2981` (0x2a55205a)

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

1.  **Configure Environment Variables**: Copy the `.env.example` file to a new file named `.env`. Update this file with your:

    -   `DEPLOYER_PRIVATE_KEY`: The private key of the account you'll use for deployment.
    -   `ETHERSCAN_API_KEY`: Your Etherscan API key for contract verification (optional but recommended).
    -   Network-specific RPC URLs (e.g., `SEPOLIA_RPC_URL`, `MAINNET_RPC_URL`).
    -   Contract parameters for the target network:
        -   `USDC_ADDRESS`: The address of the USDC contract on the target network.
        -   `NFT_NAME`: Desired name for your NFT collection (e.g., "My KAMI Collection").
        -   `NFT_SYMBOL`: Desired symbol (e.g., "MYKAMI").
        -   `MINT_PRICE_USDC`: The price per NFT in USDC (e.g., "1.5" for 1.5 USDC). The script converts this to the correct unit based on USDC decimals.
        -   `PLATFORM_ADDRESS`: The wallet address that will receive platform commissions.
        -   `PLATFORM_COMMISSION_PERCENTAGE`: The commission percentage (e.g., "10" for 10%).
        -   `ROYALTY_PERCENTAGE`: The default total royalty percentage for secondary sales (e.g., "5" for 5%).
        -   `BASE_URI`: The base URI for token metadata (can be updated later).

2.  **Run Deployment Script**: Choose the appropriate script based on whether you want the standard or upgradeable version.

### Standard Contract

_This deploys the `KAMI721AC.sol` contract directly._

```bash
npx hardhat run scripts/deploy.ts --network <network-name>
# Example: npx hardhat run scripts/deploy.ts --network sepolia
```

The script will:

-   Read parameters from `.env`.
-   Deploy the `KAMI721AC` contract with the specified constructor arguments.
-   Log the deployed contract address.
-   Optionally verify the contract on Etherscan if `ETHERSCAN_API_KEY` is set.

### Upgradeable Contract

_This deploys the `KAMI721ACUpgradeable.sol` implementation, a `KAMIProxyAdmin`, and a `KAMITransparentUpgradeableProxy` pointing to the implementation. Initialization happens via the proxy._

```bash
npx hardhat run scripts/deploy_upgradeable.ts --network <network-name>
# Example: npx hardhat run scripts/deploy_upgradeable.ts --network sepolia
```

The script will:

-   Read parameters from `.env`.
-   Deploy the implementation contract (`KAMI721ACUpgradeable`).
-   Deploy the `KAMIProxyAdmin`.
-   Deploy the `KAMITransparentUpgradeableProxy`, linking it to the implementation and admin.
-   Call the `initialize` function on the proxy with the specified parameters.
-   Log the proxy address (this is the address you interact with), the implementation address, and the admin address.
-   Optionally verify the contracts on Etherscan.

## Usage Examples

(Examples assume `ethers` is set up with signers like `owner`, `minter`, `seller`, `buyer`, `renter`, and `kami` points to the deployed contract instance - either standard or the proxy address for upgradeable. `usdc` points to the deployed USDC contract instance. `tokenId` is a specific token ID, `creatorAddress` is the artist/creator's address.)

### Deployment Script Snippet (Initialization Example)

_The deployment scripts handle the actual deployment and initialization using parameters from your `.env` file. Below is a conceptual snippet showing how the standard contract might be deployed within the `deploy.ts` script using `ethers.js`:_

```javascript
// Example snippet conceptually similar to what happens in deploy.ts
// (Actual script reads values from process.env based on .env file)

const KAMI721AC = await ethers.getContractFactory('KAMI721AC');

// Values would be dynamically loaded from .env in the actual script
const name = process.env.NFT_NAME || 'Default KAMI Name';
const symbol = process.env.NFT_SYMBOL || 'DKAMI';
const initialOwner = (await ethers.getSigners())[0].address; // Deployer is often initial owner
const mintPrice = ethers.parseUnits(process.env.MINT_PRICE_USDC || '1', 6); // Assuming 6 decimals for USDC
const usdcAddress = process.env.USDC_ADDRESS; // Must be set in .env
const platformAddress = process.env.PLATFORM_ADDRESS; // Must be set in .env
const platformCommission = parseInt(process.env.PLATFORM_COMMISSION_PERCENTAGE || '0') * 100; // e.g., 10% -> 1000
const royaltyPercentage = parseInt(process.env.ROYALTY_PERCENTAGE || '0') * 100; // e.g., 5% -> 500

console.log('Deploying KAMI721AC with parameters:');
// ... log parameters ...

const kami = await KAMI721AC.deploy(
	name,
	symbol,
	initialOwner,
	mintPrice,
	usdcAddress,
	platformAddress,
	platformCommission,
	royaltyPercentage
);

await kami.waitForDeployment();
const deployedAddress = await kami.getAddress();
console.log(`KAMI721AC (Standard) deployed to: ${deployedAddress}`);

// The deploy_upgradeable.ts script follows a different pattern using Hardhat Upgrades plugin:
// 1. Deploy implementation: ethers.getContractFactory('KAMI721ACUpgradeable')
// 2. Deploy proxy: upgrades.deployProxy(factory, [/* initializer args */], { initializer: 'initialize', kind: 'transparent' })
// Interaction is then done via the proxy's address.
```

### Configuring the Contract (Owner Role)

```javascript
// Set the base URI for metadata
const newBaseURI = 'ipfs://YOUR_METADATA_CID/';
await kami.connect(owner).setBaseURI(newBaseURI);

// Set the platform commission details
const newPlatformAddress = '0x...'; // New platform wallet
const newCommissionPercent = 500; // 5% = 500
await kami.connect(owner).setPlatformCommission(newCommissionPercent, newPlatformAddress);

// Set the default total royalty percentage for secondary sales (e.g., 7.5%)
const newRoyaltyPercent = 750; // 7.5% = 750
await kami.connect(owner).setRoyaltyPercentage(newRoyaltyPercent);

// Set an optional transfer validator contract (for custom transfer rules)
const validatorAddress = '0x...'; // Address of deployed validator contract
await kami.connect(owner).setTransferValidator(validatorAddress);
```

### Setting Royalties (Owner Role)

```javascript
// --- Default Royalties ---

// Set default mint royalties (percentages applied *after* platform fee)
// Example: 90% to creator, 10% to collaborator
const mintRoyalties = [
	{ receiver: creatorAddress, feeNumerator: 9000 }, // 90%
	{ receiver: collaboratorAddress, feeNumerator: 1000 }, // 10%
];
await kami.connect(owner).setMintRoyalties(mintRoyalties);
// Note: feeNumerators must sum to 10000 (100%)

// Set default transfer royalties (percentages applied to the *total* royalty amount)
// Example: 100% of the calculated royalty goes to the creator
const transferRoyalties = [
	{ receiver: creatorAddress, feeNumerator: 10000 }, // 100%
];
await kami.connect(owner).setTransferRoyalties(transferRoyalties);
// Note: feeNumerators must sum to 10000 (100%)

// --- Token-Specific Royalties ---

// Set specific mint royalties for tokenId = 1
const tokenMintRoyalties = [
	{ receiver: specialArtistAddress, feeNumerator: 10000 }, // 100% to a specific artist
];
await kami.connect(owner).setTokenMintRoyalties(tokenId, tokenMintRoyalties);

// Set specific transfer royalties for tokenId = 1
const tokenTransferRoyalties = [
	{ receiver: specialArtistAddress, feeNumerator: 5000 }, // 50% to artist
	{ receiver: originalOwnerAddress, feeNumerator: 5000 }, // 50% to original owner
];
await kami.connect(owner).setTokenTransferRoyalties(tokenId, tokenTransferRoyalties);
```

### Getting Royalty Information (ERC2981)

```javascript
// Get royalty info for a specific sale price (e.g., 100 USDC)
const salePrice = ethers.parseUnits('100', 6); // 100 USDC (assuming 6 decimals)
const [receiver, royaltyAmount] = await kami.royaltyInfo(tokenId, salePrice);

console.log(`Royalty Receiver: ${receiver}`);
console.log(`Royalty Amount: ${ethers.formatUnits(royaltyAmount, 6)} USDC`); // Format back to readable USDC

// Get mint royalty receivers for a token (uses default if token-specific not set)
const mintReceivers = await kami.getMintRoyaltyReceivers(tokenId);
console.log('Mint Royalty Receivers:', mintReceivers);

// Get transfer royalty receivers for a token (uses default if token-specific not set)
const transferReceivers = await kami.getTransferRoyaltyReceivers(tokenId);
console.log('Transfer Royalty Receivers:', transferReceivers);
```

### Minting NFTs (Claiming)

```javascript
// Ensure the minter has enough USDC and has approved the contract

const quantity = 3;
const currentMintPrice = await kami.mintPrice(); // Fetch current price
const totalCost = currentMintPrice * BigInt(quantity);

// Check allowance
const allowance = await usdc.allowance(minter.address, await kami.getAddress());
if (allowance < totalCost) {
	// Approve USDC spending for the total cost
	const approveTx = await usdc.connect(minter).approve(await kami.getAddress(), totalCost);
	await approveTx.wait();
	console.log(`Approved ${ethers.formatUnits(totalCost, 6)} USDC spending`);
}

// Check balance
const balance = await usdc.balanceOf(minter.address);
if (balance < totalCost) {
	console.error('Insufficient USDC balance');
	// Handle error appropriately
	return;
}

// Mint/Claim multiple NFTs
console.log(`Minting ${quantity} tokens for ${ethers.formatUnits(totalCost, 6)} USDC...`);
const mintTx = await kami.connect(minter).mint(quantity);
const receipt = await mintTx.wait();
console.log(`Mint successful! Transaction hash: ${receipt.hash}`);
// You might want to parse logs here to get the minted token IDs
```

### Selling NFTs

```javascript
// Seller owns the NFT with tokenId
// Buyer has enough USDC and has approved the contract for the salePrice

const salePrice = ethers.parseUnits('250', 6); // 250 USDC

// Buyer needs to approve the KAMI contract to spend their USDC
const approveTx = await usdc.connect(buyer).approve(await kami.getAddress(), salePrice);
await approveTx.wait();
console.log(`Buyer approved ${ethers.formatUnits(salePrice, 6)} USDC spending`);

// Note: The seller does NOT need to approve the KAMI contract for the specific token
// when using sellToken, as the function handles the transfer internally.

// Seller initiates the sale to the buyer
console.log(`Selling token ${tokenId} to ${buyer.address} for ${ethers.formatUnits(salePrice, 6)} USDC...`);
const sellTx = await kami.connect(seller).sellToken(buyer.address, tokenId, salePrice);
const receipt = await sellTx.wait();
console.log(`Sale successful! Transaction hash: ${receipt.hash}`);

// Verify ownership change
const newOwner = await kami.ownerOf(tokenId);
console.log(`New owner of token ${tokenId}: ${newOwner}`); // Should be buyer.address
```

### Renting NFTs

```javascript
// Owner (or current owner) owns the NFT with tokenId
// Renter has enough USDC and approves the contract for the rentalPrice

const rentalDurationSeconds = 86400 * 7; // 7 days in seconds
const rentalPrice = ethers.parseUnits('30', 6); // 30 USDC for the period

// Renter approves USDC spending for the rental price
const approveTx = await usdc.connect(renter).approve(await kami.getAddress(), rentalPrice);
await approveTx.wait();
console.log(`Renter approved ${ethers.formatUnits(rentalPrice, 6)} USDC spending`);

// Renter initiates the rental
console.log(`Renting token ${tokenId} for ${rentalDurationSeconds / 86400} days for ${ethers.formatUnits(rentalPrice, 6)} USDC...`);
const rentTx = await kami.connect(renter).rentToken(tokenId, rentalDurationSeconds, rentalPrice);
const receipt = await rentTx.wait();
console.log(`Rental successful! Transaction hash: ${receipt.hash}`);

// --- Check Rental Status ---

// Check who the current user is (should be the renter)
const currentUser = await kami.userOf(tokenId);
console.log(`Current user of token ${tokenId}: ${currentUser}`); // Should be renter.address

// Check if a specific address is the current user
const isRenterUser = await kami.isUser(tokenId, renter.address);
console.log(`Is renter the current user? ${isRenterUser}`); // Should be true

// Check rental expiry time (implementation detail, might need a dedicated function or event parsing)
// const rentalInfo = await kami.getRentalInfo(tokenId); // Assuming such a function exists
// console.log(`Rental expires at: ${new Date(rentalInfo.expires * 1000)}`);

// --- End a Rental Early ---

// Owner or Renter can end the rental
console.log(`Ending rental for token ${tokenId}...`);
// const endTx = await kami.connect(owner).endRental(tokenId); // Owner ends
const endTx = await kami.connect(renter).endRental(tokenId); // Or Renter ends
await endTx.wait();
console.log(`Rental ended.`);

const finalUser = await kami.userOf(tokenId);
console.log(`User after ending rental: ${finalUser}`); // Should be the actual owner

// --- Extend a Rental ---

// (First, rent the token again as shown above)
// ... rent token ...

// Extend the rental period
const additionalDuration = 86400 * 3; // Extend by 3 days
const additionalPayment = ethers.parseUnits('15', 6); // Pay 15 USDC more

// Renter approves the additional payment
const approveExtendTx = await usdc.connect(renter).approve(await kami.getAddress(), additionalPayment);
await approveExtendTx.wait();

// Renter extends the rental
console.log(`Extending rental for token ${tokenId} by ${additionalDuration / 86400} days...`);
const extendTx = await kami.connect(renter).extendRental(tokenId, additionalDuration, additionalPayment);
await extendTx.wait();
console.log(`Rental extended.`);

// (Verify new expiry if possible)
```

### Administrative Functions (Admin Role)

```javascript
// Pause the contract (stops minting, selling, renting, etc.)
console.log('Pausing contract...');
const pauseTx = await kami.connect(admin).pause(); // Assuming 'admin' has DEFAULT_ADMIN_ROLE
await pauseTx.wait();
console.log('Contract paused.');

// Attempt a mint while paused (should fail)
try {
	await kami.connect(minter).mint(1);
} catch (error) {
	console.log('Mint failed as expected:', error.message);
}

// Unpause the contract
console.log('Unpausing contract...');
const unpauseTx = await kami.connect(admin).unpause();
await unpauseTx.wait();
console.log('Contract unpaused.');

// Burn an NFT (requires owner/approved or specific role depending on ERC721A config)
// Note: Burning might be disabled or restricted in some ERC721A versions.
// It also fails if the token is currently rented.
console.log(`Attempting to burn token ${tokenId}...`);
// await kami.connect(owner).burn(tokenId); // Standard burn if enabled
// Check specific ERC721A docs and KAMI implementation for burn permissions/availability.
```

### Upgrading the Contract (Upgradeable Version Only)

_Upgrade requires deploying a new implementation contract and then calling the upgrade function on the proxy (usually via the ProxyAdmin)._

```bash
# 1. Deploy the new implementation contract (e.g., KAMI721ACUpgradeableV2)
#    (You might modify deploy_upgradeable.ts or use a dedicated script)
npx hardhat run scripts/deploy_new_implementation.ts --network <network-name>
#    (This script should output the address of the new implementation)

# 2. Update your .env file with the deployed ProxyAdmin address, Proxy address,
#    and the NEW implementation address.

# 3. Run the upgrade script
npx hardhat run scripts/upgrade.ts --network <network-name>
#    (This script interacts with the ProxyAdmin to point the proxy to the new implementation)
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

-   `setPlatformCommission(uint96 newPlatformCommissionPercentage, address newPlatformAddress)`: Set platform commission details.
-   `setRoyaltyPercentage(uint96 newRoyaltyPercentage)`: Set the _total_ royalty percentage for transfers (relative to sale price).
-   `setBaseURI(string memory baseURI)`: Set the base URI for token metadata.
-   `setTransferValidator(address _validator)`: Set the address for an optional transfer validator contract (for LimitBreak compliance or custom rules).

### Administrative

-   `pause()`: Pause the contract (requires admin role).
-   `unpause()`: Unpause the contract (requires admin role).
-   `burn(uint256 tokenId)`: Burn an NFT (Inherited standard ERC721A burn, may be restricted or removed based on exact `ERC721A` version/config). Transfer restrictions apply if rented.
-   `upgradeTo(address newImplementation)` (UUPS - called via ProxyAdmin): Upgrades the contract implementation (upgradeable version only).

## Roles

-   `DEFAULT_ADMIN_ROLE`: Can manage all roles, pause/unpause, upgrade (if UUPS).
-   `OWNER_ROLE`: Can configure the contract (prices, royalties, URIs, validator) and manage royalties.
-   `PLATFORM_ROLE`: Receives platform commission.
-   `RENTER_ROLE`: Granted to users who actively rent NFTs.
-   `UPGRADER_ROLE` (Upgradeable only): Can upgrade the implementation via UUPS (if granted separately from admin).

## Considerations

-   **Contract Size**: Due to the combination of features (ERC721A, AccessControl, ERC2981, Rentals, Pausable, USDC integration), the compiled contract size may exceed the 24KB limit recommended for deployment on some networks. This can lead to increased deployment costs or potential issues. Consider splitting functionality or optimizing further if size becomes a critical issue.

## License

MIT
