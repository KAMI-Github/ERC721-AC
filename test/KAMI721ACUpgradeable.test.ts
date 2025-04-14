import { expect } from 'chai';
import { ethers, upgrades } from 'hardhat';
import { Contract } from 'ethers';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
// import { MockERC20 } from '../typechain-types'; // Remove type import for now

describe('KAMI721ACUpgradeable', function () {
	let contract: any;
	let mockUSDC: any; // Use any for now
	let owner: HardhatEthersSigner;
	let platform: HardhatEthersSigner;
	let buyer: HardhatEthersSigner;
	let royaltyReceiver: HardhatEthersSigner;
	let upgrader: HardhatEthersSigner;

	const NAME = 'KAMI NFT';
	const SYMBOL = 'KAMI';
	const BASE_URI = 'https://api.kami.example/metadata/';
	const MINT_PRICE = ethers.parseUnits('100', 6); // 100 USDC
	const PLATFORM_COMMISSION = 500; // 5%

	beforeEach(async function () {
		[owner, platform, buyer, royaltyReceiver, upgrader] = await ethers.getSigners();

		// Deploy mock ERC20 (USDC)
		const MockERC20Factory = await ethers.getContractFactory('contracts/MockERC20.sol:MockERC20');
		mockUSDC = await MockERC20Factory.deploy('USD Coin', 'USDC', 6);
		await mockUSDC.mint(buyer.address, ethers.parseUnits('10000', 6));
		await mockUSDC.mint(owner.address, ethers.parseUnits('1000', 6)); // Mint some for owner too

		// Deploy using hardhat-upgrades plugin (Transparent Proxy is default)
		const KAMI721ACUpgradeableFactory = await ethers.getContractFactory('KAMI721ACUpgradeable');
		contract = await upgrades.deployProxy(
			KAMI721ACUpgradeableFactory,
			[await mockUSDC.getAddress(), NAME, SYMBOL, BASE_URI, MINT_PRICE, platform.address, PLATFORM_COMMISSION],
			{
				initializer: 'initialize',
				// kind: 'transparent' // Default, no need to specify unless changing
			}
		);
		await contract.waitForDeployment();

		// Approve the contract (proxy) to spend buyer's and owner's USDC
		await mockUSDC.connect(buyer).approve(await contract.getAddress(), ethers.parseUnits('10000', 6));
		await mockUSDC.connect(owner).approve(await contract.getAddress(), ethers.parseUnits('1000', 6));
	});

	describe('Initialization', function () {
		it('should initialize with correct values', async function () {
			expect(await contract.name()).to.equal(NAME);
			expect(await contract.symbol()).to.equal(SYMBOL);
			expect(await contract.mintPrice()).to.equal(MINT_PRICE);
			expect(await contract.platformAddress()).to.equal(platform.address);
			expect(await contract.platformCommissionPercentage()).to.equal(PLATFORM_COMMISSION);
			expect(await contract.royaltyPercentage()).to.equal(1000); // Default 10%
		});

		it('should assign roles correctly', async function () {
			const OWNER_ROLE = await contract.OWNER_ROLE();
			const PLATFORM_ROLE = await contract.PLATFORM_ROLE();
			const UPGRADER_ROLE = await contract.UPGRADER_ROLE();

			expect(await contract.hasRole(OWNER_ROLE, owner.address)).to.be.true;
			expect(await contract.hasRole(PLATFORM_ROLE, platform.address)).to.be.true;
			expect(await contract.hasRole(UPGRADER_ROLE, owner.address)).to.be.true;
		});

		it('should not be able to initialize again', async function () {
			await expect(
				contract.initialize(await mockUSDC.getAddress(), NAME, SYMBOL, BASE_URI, MINT_PRICE, platform.address, PLATFORM_COMMISSION)
			).to.be.revertedWith('Initializable: contract is already initialized');
		});
	});

	describe('Basic Functionality', function () {
		beforeEach(async function () {
			// Set up royalty receivers for testing
			const mintRoyaltyData = [
				{
					receiver: royaltyReceiver.address,
					feeNumerator: 9500, // 95% of royalties, staying below the platform commission
				},
			];

			// For transfer royalties, the total percentages must equal 100%
			const transferRoyaltyData = [
				{
					receiver: royaltyReceiver.address,
					feeNumerator: 10000, // 100% of royalties
				},
			];

			await contract.setMintRoyalties(mintRoyaltyData);
			await contract.setTransferRoyalties(transferRoyaltyData);
		});

		it('should mint a single token and check enumeration', async function () {
			const initialUSDCBalance = await mockUSDC.balanceOf(buyer.address);
			const initialPlatformBalance = await mockUSDC.balanceOf(platform.address);
			const initialRoyaltyReceiverBalance = await mockUSDC.balanceOf(royaltyReceiver.address);

			// Mint ONE token
			await contract.connect(buyer).mint(1);

			// Check token ownership and enumeration
			expect(await contract.ownerOf(0)).to.equal(buyer.address);
			expect(await contract.totalSupply()).to.equal(1);
			expect(await contract.tokenByIndex(0)).to.equal(0);
			expect(await contract.tokenOfOwnerByIndex(buyer.address, 0)).to.equal(0);

			// Check USDC balances
			const platformCommission = (MINT_PRICE * BigInt(PLATFORM_COMMISSION)) / 10000n;
			const royaltyAmount = ((MINT_PRICE - platformCommission) * 9500n) / 10000n;

			expect(await mockUSDC.balanceOf(buyer.address)).to.equal(initialUSDCBalance - MINT_PRICE);
			expect(await mockUSDC.balanceOf(platform.address)).to.be.gte(initialPlatformBalance + platformCommission);
			expect(await mockUSDC.balanceOf(royaltyReceiver.address)).to.be.gte(initialRoyaltyReceiverBalance + royaltyAmount);
		});

		it('should batch mint multiple tokens and check enumeration', async function () {
			const BATCH_SIZE = 3;
			const totalMintPrice = MINT_PRICE * BigInt(BATCH_SIZE);

			const initialUSDCBalance = await mockUSDC.balanceOf(buyer.address);
			const initialPlatformBalance = await mockUSDC.balanceOf(platform.address);
			const initialRoyaltyReceiverBalance = await mockUSDC.balanceOf(royaltyReceiver.address);

			// Approve enough for batch mint
			await mockUSDC.connect(buyer).approve(await contract.getAddress(), totalMintPrice);

			// Batch Mint tokens
			await contract.connect(buyer).mint(BATCH_SIZE);

			// Check token ownership and enumeration
			expect(await contract.totalSupply()).to.equal(BATCH_SIZE);
			for (let i = 0; i < BATCH_SIZE; i++) {
				expect(await contract.ownerOf(i)).to.equal(buyer.address);
				expect(await contract.tokenByIndex(i)).to.equal(i);
				expect(await contract.tokenOfOwnerByIndex(buyer.address, i)).to.equal(i);
			}

			// Check USDC balances (uses default mint royalties)
			const platformCommission = (totalMintPrice * BigInt(PLATFORM_COMMISSION)) / 10000n;
			// Royalty calculation based on total payment and default receiver (95%)
			const royaltyAmount = (totalMintPrice * 9500n) / 10000n;

			expect(await mockUSDC.balanceOf(buyer.address)).to.equal(initialUSDCBalance - totalMintPrice);
			expect(await mockUSDC.balanceOf(platform.address)).to.be.gte(initialPlatformBalance + platformCommission);
			expect(await mockUSDC.balanceOf(royaltyReceiver.address)).to.be.gte(initialRoyaltyReceiverBalance + royaltyAmount);
		});

		it('should set and get mint price', async function () {
			const newMintPrice = ethers.parseUnits('150', 6);
			await contract.setMintPrice(newMintPrice);
			expect(await contract.mintPrice()).to.equal(newMintPrice);
		});

		it('should not allow non-owners to set mint price', async function () {
			const newMintPrice = ethers.parseUnits('150', 6);
			await expect(contract.connect(buyer).setMintPrice(newMintPrice)).to.be.revertedWith('Caller is not an owner'); // Use the contract's custom error string
		});

		it('should set base URI', async function () {
			const newBaseURI = 'https://new.api.kami.example/metadata/';
			await contract.setBaseURI(newBaseURI);

			// Mint a token to check URI
			const tx = await contract.connect(buyer).mint(1);
			await tx.wait(); // Wait for mint tx
			const tokenId = await contract.tokenOfOwnerByIndex(buyer.address, 0); // Get assigned ID

			expect(await contract.tokenURI(tokenId)).to.equal(newBaseURI + tokenId.toString());
		});
	});

	describe('Royalties', function () {
		it('should set and get royalty percentage', async function () {
			const newRoyaltyPercentage = 1500; // 15%
			await contract.setRoyaltyPercentage(newRoyaltyPercentage);
			expect(await contract.royaltyPercentage()).to.equal(newRoyaltyPercentage);
		});

		it('should set and get mint royalties', async function () {
			// Note: adjusting feeNumerator values to stay under the platform commission
			const royaltyData = [
				{
					receiver: royaltyReceiver.address,
					feeNumerator: 7600, // 76% of royalties
				},
				{
					receiver: owner.address,
					feeNumerator: 1900, // 19% of royalties
				},
			];

			await contract.setMintRoyalties(royaltyData);

			const receiverData = await contract.getMintRoyaltyReceivers(0);
			expect(receiverData[0].receiver).to.equal(royaltyReceiver.address);
			expect(receiverData[0].feeNumerator).to.equal(7600);
			expect(receiverData[1].receiver).to.equal(owner.address);
			expect(receiverData[1].feeNumerator).to.equal(1900);
		});

		it('should set and get transfer royalties', async function () {
			const royaltyData = [
				{
					receiver: royaltyReceiver.address,
					feeNumerator: 6000, // 60% of royalties
				},
				{
					receiver: owner.address,
					feeNumerator: 4000, // 40% of royalties
				},
			];

			await contract.setTransferRoyalties(royaltyData);

			const receiverData = await contract.getTransferRoyaltyReceivers(0);
			expect(receiverData[0].receiver).to.equal(royaltyReceiver.address);
			expect(receiverData[0].feeNumerator).to.equal(6000);
			expect(receiverData[1].receiver).to.equal(owner.address);
			expect(receiverData[1].feeNumerator).to.equal(4000);
		});
	});

	describe('Selling & Transfers', function () {
		beforeEach(async function () {
			// Set up royalty receivers for testing
			const mintRoyaltyData = [
				{
					receiver: royaltyReceiver.address,
					feeNumerator: 9500, // 95% of royalties, staying below the platform commission
				},
			];

			// For transfer royalties, the total percentages must equal 100%
			const transferRoyaltyData = [
				{
					receiver: royaltyReceiver.address,
					feeNumerator: 10000, // 100% of royalties
				},
			];

			await contract.setMintRoyalties(mintRoyaltyData);
			await contract.setTransferRoyalties(transferRoyaltyData);

			// Mint a token for the owner
			await contract.connect(owner).mint(1);
			const tokenId = await contract.tokenOfOwnerByIndex(owner.address, 0); // Get assigned token ID
			this.tokenId = tokenId; // Store for subsequent tests in this block
		});

		it('should sell a token with royalties', async function () {
			const tokenId = this.tokenId;
			const salePrice = ethers.parseUnits('200', 6);

			const initialOwnerBalance = await mockUSDC.balanceOf(owner.address);
			const initialBuyerBalance = await mockUSDC.balanceOf(buyer.address);
			const initialPlatformBalance = await mockUSDC.balanceOf(platform.address);
			const initialRoyaltyReceiverBalance = await mockUSDC.balanceOf(royaltyReceiver.address);

			// Approve the contract to transfer the token
			await contract.connect(owner).approve(await contract.getAddress(), tokenId);

			// Sell the token
			await contract.connect(owner).sellToken(buyer.address, tokenId, salePrice);

			// Check token ownership
			expect(await contract.ownerOf(tokenId)).to.equal(buyer.address);

			// Calculate expected distribution
			const royaltyAmount = (salePrice * BigInt(await contract.royaltyPercentage())) / 10000n;
			const platformCommission = (salePrice * BigInt(PLATFORM_COMMISSION)) / 10000n;
			const sellerProceeds = salePrice - (royaltyAmount + platformCommission);

			// Check USDC balances
			expect(await mockUSDC.balanceOf(buyer.address)).to.equal(initialBuyerBalance - salePrice);
			expect(await mockUSDC.balanceOf(owner.address)).to.equal(initialOwnerBalance + sellerProceeds);
			expect(await mockUSDC.balanceOf(platform.address)).to.be.gte(initialPlatformBalance + platformCommission);
			expect(await mockUSDC.balanceOf(royaltyReceiver.address)).to.be.gte(initialRoyaltyReceiverBalance + royaltyAmount);
		});
	});

	describe('Rental Functionality', function () {
		let tokenId: bigint;
		const rentalPrice = ethers.parseUnits('50', 6);
		const rentalDuration = 86400n; // Use BigInt for duration

		beforeEach(async function () {
			// Mint a token for the owner
			await contract.connect(owner).mint(1);
			tokenId = await contract.tokenOfOwnerByIndex(owner.address, 0); // Get assigned ID
		});

		it('should rent a token and check userOf', async function () {
			const initialOwnerBalance = await mockUSDC.balanceOf(owner.address);
			const initialBuyerBalance = await mockUSDC.balanceOf(buyer.address);
			// Platform commission handled differently

			// Approve enough USDC for the rental
			await mockUSDC.connect(buyer).approve(await contract.getAddress(), rentalPrice);

			// Rent the token
			await contract.connect(buyer).rentToken(tokenId, rentalDuration, rentalPrice);

			// Check rental status
			const rentalInfo = await contract.getRentalInfo(tokenId);
			expect(rentalInfo.renter).to.equal(buyer.address);
			expect(rentalInfo.active).to.be.true;

			// Calculate expected distribution (Direct payment)
			const ownerShare = rentalPrice;

			// Check USDC balances
			expect(await mockUSDC.balanceOf(buyer.address)).to.equal(initialBuyerBalance - rentalPrice);
			expect(await mockUSDC.balanceOf(owner.address)).to.equal(initialOwnerBalance + ownerShare);
			// Platform balance should not change in this simplified flow

			// Check renter role
			const RENTER_ROLE = await contract.RENTER_ROLE();
			expect(await contract.hasRole(RENTER_ROLE, buyer.address)).to.be.true;

			// Check userOf
			expect(await contract.userOf(tokenId)).to.equal(buyer.address);
			expect(await contract.isUser(tokenId, buyer.address)).to.be.true;
			expect(await contract.isUser(tokenId, owner.address)).to.be.false;
		});

		it('should end rental and update userOf', async function () {
			// Approve and Rent the token
			await mockUSDC.connect(buyer).approve(await contract.getAddress(), rentalPrice);
			await contract.connect(buyer).rentToken(tokenId, rentalDuration, rentalPrice);

			// End the rental
			await contract.connect(owner).endRental(tokenId);

			// Check rental status
			const rentalInfo = await contract.getRentalInfo(tokenId);
			expect(rentalInfo.active).to.be.false;

			// Check userOf returns owner
			expect(await contract.userOf(tokenId)).to.equal(owner.address);

			// Check RENTER_ROLE revoked
			const RENTER_ROLE = await contract.RENTER_ROLE();
			expect(await contract.hasRole(RENTER_ROLE, buyer.address)).to.be.false;
		});

		it('should extend rental', async function () {
			const rentalDurationBN = BigInt(rentalDuration);
			const additionalDurationBN = 43200n;
			// Approve and Rent the token
			const totalPayment = rentalPrice + ethers.parseUnits('25', 6);
			await mockUSDC.connect(buyer).approve(await contract.getAddress(), totalPayment);
			await contract.connect(buyer).rentToken(tokenId, rentalDurationBN, rentalPrice);

			const rentalInfo = await contract.getRentalInfo(tokenId);
			const originalEndTime = rentalInfo.endTime;

			// Record balances before extension
			const ownerBalanceBefore = await mockUSDC.balanceOf(owner.address);
			const buyerBalanceBefore = await mockUSDC.balanceOf(buyer.address);

			// Extend the rental
			const additionalPayment = ethers.parseUnits('25', 6);
			await contract.connect(buyer).extendRental(tokenId, additionalDurationBN, additionalPayment);

			// Check rental status
			const updatedRentalInfo = await contract.getRentalInfo(tokenId);
			expect(updatedRentalInfo.endTime).to.equal(originalEndTime + additionalDurationBN);
			// rentalPrice in struct is not updated by extendRental

			// Check balances (direct payment)
			expect(await mockUSDC.balanceOf(owner.address)).to.equal(ownerBalanceBefore + additionalPayment);
			expect(await mockUSDC.balanceOf(buyer.address)).to.equal(buyerBalanceBefore - additionalPayment);
		});

		it('should prevent transfers during rental', async function () {
			const rentalDurationBN = BigInt(rentalDuration);
			// Approve and Rent the token
			await mockUSDC.connect(buyer).approve(await contract.getAddress(), rentalPrice);
			await contract.connect(buyer).rentToken(tokenId, rentalDurationBN, rentalPrice);

			// Try to transfer
			await expect(contract.connect(owner).transferFrom(owner.address, buyer.address, tokenId)).to.be.revertedWith('Token is rented');
		});

		it('should allow transfers after rental expires', async function () {
			const shortDuration = 2n; // Use BigInt
			// Approve and Rent the token
			await mockUSDC.connect(buyer).approve(await contract.getAddress(), rentalPrice);
			await contract.connect(buyer).rentToken(tokenId, shortDuration, rentalPrice);

			// Wait for rental to expire
			await ethers.provider.send('evm_increaseTime', [Number(shortDuration) + 1]); // evm_increaseTime needs number
			await ethers.provider.send('evm_mine', []);

			// Transfer should now succeed (rental cleanup happens in _update)
			await contract.connect(owner).transferFrom(owner.address, buyer.address, tokenId);
			expect(await contract.ownerOf(tokenId)).to.equal(buyer.address);

			// Verify rental is cleared by transfer
			const rentalInfo = await contract.getRentalInfo(tokenId);
			expect(rentalInfo.active).to.be.false;
		});
	});

	describe('Upgradeability', function () {
		it('should allow upgrade by owner/upgrader (UUPS)', async function () {
			const KAMI721ACUpgradeableV2 = await ethers.getContractFactory('KAMI721ACUpgradeable'); // Use the same factory for simplicity, real upgrade needs V2
			// For UUPS, ensure the deployer (owner) has the UPGRADER_ROLE
			expect(await contract.hasRole(await contract.UPGRADER_ROLE(), owner.address)).to.be.true;

			const proxyAddress = await contract.getAddress(); // Get proxy address
			const upgradedContract = await upgrades.upgradeProxy(proxyAddress, KAMI721ACUpgradeableV2);

			// Check if the contract address remains the same
			expect(await upgradedContract.getAddress()).to.equal(proxyAddress);

			// Optionally, check if a V2 function exists (if you create a V2)
			// expect(await upgradedContract.newFunction()).to.exist;
		});

		it('should not allow upgrade by non-upgrader', async function () {
			const KAMI721ACUpgradeableV2_Factory = await ethers.getContractFactory('KAMI721ACUpgradeable');
			// Connect the factory to the non-upgrader signer (buyer)
			const factoryConnectedToBuyer = KAMI721ACUpgradeableV2_Factory.connect(buyer);

			await expect(upgrades.upgradeProxy(await contract.getAddress(), factoryConnectedToBuyer)).to.be.reverted;
			// The exact error might depend on ProxyAdmin vs UUPS roles.
			// If using UUPS and UPGRADER_ROLE, it should revert due to role check.
			// If using Transparent Proxy and ProxyAdmin, the transaction itself might fail
			// or revert if the ProxyAdmin doesn't authorize the non-admin buyer.
		});
	});
});
