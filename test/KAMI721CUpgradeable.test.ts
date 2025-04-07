import { expect } from 'chai';
import { ethers, upgrades } from 'hardhat';
import { Contract } from 'ethers';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import { MockERC20, ProxyAdmin } from '../typechain-types';
import { KAMI721CUpgradeable } from '../typechain-types';

describe('KAMI721CUpgradeable', function () {
	let contract: KAMI721CUpgradeable;
	let proxyAdmin: ProxyAdmin;
	let mockUSDC: any;
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
		const MockERC20Factory = await ethers.getContractFactory('contracts/test/MockERC20.sol:MockERC20');
		mockUSDC = await MockERC20Factory.deploy('USD Coin', 'USDC', 6);
		await mockUSDC.mint(buyer.address, ethers.parseUnits('1000', 6));

		// Deploy the contract using the hardhat-upgrades plugin
		const KAMI721CUpgradeableFactory = await ethers.getContractFactory('KAMI721CUpgradeable');

		const contractInstance = await upgrades.deployProxy(
			KAMI721CUpgradeableFactory,
			[await mockUSDC.getAddress(), NAME, SYMBOL, BASE_URI, MINT_PRICE, platform.address, PLATFORM_COMMISSION],
			{
				initializer: 'initialize',
				kind: 'transparent',
			}
		);

		contract = contractInstance as unknown as KAMI721CUpgradeable;

		// Save the proxy admin address for later testing
		const proxyAdminAddress = await upgrades.erc1967.getAdminAddress(await contract.getAddress());
		proxyAdmin = (await ethers.getContractAt('ProxyAdmin', proxyAdminAddress)) as unknown as ProxyAdmin;

		// Approve the contract to spend buyer's USDC
		await mockUSDC.connect(buyer).approve(await contract.getAddress(), ethers.parseUnits('1000', 6));
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

		it('should mint a token', async function () {
			const initialUSDCBalance = await mockUSDC.balanceOf(buyer.address);
			const initialPlatformBalance = await mockUSDC.balanceOf(platform.address);
			const initialRoyaltyReceiverBalance = await mockUSDC.balanceOf(royaltyReceiver.address);

			// Mint a token
			await contract.connect(buyer).mint();

			// Check token ownership
			expect(await contract.ownerOf(0)).to.equal(buyer.address);
			expect(await contract.totalSupply()).to.equal(1);

			// Check USDC balances
			const platformCommission = (MINT_PRICE * BigInt(PLATFORM_COMMISSION)) / 10000n;
			const royaltyAmount = ((MINT_PRICE - platformCommission) * 9500n) / 10000n;

			expect(await mockUSDC.balanceOf(buyer.address)).to.equal(initialUSDCBalance - MINT_PRICE);
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
			await expect(contract.connect(buyer).setMintPrice(newMintPrice)).to.be.revertedWith('Caller is not an owner');
		});

		it('should set base URI', async function () {
			const newBaseURI = 'https://new.api.kami.example/metadata/';
			await contract.setBaseURI(newBaseURI);

			// Mint a token to check URI
			await contract.connect(buyer).mint();

			expect(await contract.tokenURI(0)).to.equal(newBaseURI + '0');
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
			await mockUSDC.mint(owner.address, ethers.parseUnits('1000', 6));
			await mockUSDC.connect(owner).approve(await contract.getAddress(), ethers.parseUnits('1000', 6));
			await contract.connect(owner).mint();
		});

		it('should sell a token with royalties', async function () {
			const tokenId = 0;
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
		let tokenId = 0;
		const rentalPrice = ethers.parseUnits('50', 6);
		const rentalDuration = 86400; // 1 day in seconds

		beforeEach(async function () {
			// Mint a token for the owner
			await mockUSDC.mint(owner.address, ethers.parseUnits('1000', 6));
			await mockUSDC.connect(owner).approve(await contract.getAddress(), ethers.parseUnits('1000', 6));
			await contract.connect(owner).mint();
			tokenId = 0;
		});

		it('should rent a token', async function () {
			const initialOwnerBalance = await mockUSDC.balanceOf(owner.address);
			const initialBuyerBalance = await mockUSDC.balanceOf(buyer.address);
			const initialPlatformBalance = await mockUSDC.balanceOf(platform.address);

			// Rent the token
			await contract.connect(buyer).rentToken(tokenId, rentalDuration, rentalPrice);

			// Check rental status
			const rentalInfo = await contract.getRentalInfo(tokenId);
			expect(rentalInfo.renter).to.equal(buyer.address);
			expect(rentalInfo.active).to.be.true;

			// Calculate expected distribution
			const platformCommission = (rentalPrice * BigInt(PLATFORM_COMMISSION)) / 10000n;
			const ownerShare = rentalPrice - platformCommission;

			// Check USDC balances
			expect(await mockUSDC.balanceOf(buyer.address)).to.equal(initialBuyerBalance - rentalPrice);
			expect(await mockUSDC.balanceOf(owner.address)).to.equal(initialOwnerBalance + ownerShare);
			expect(await mockUSDC.balanceOf(platform.address)).to.equal(initialPlatformBalance + platformCommission);

			// Check renter role
			const RENTER_ROLE = await contract.RENTER_ROLE();
			expect(await contract.hasRole(RENTER_ROLE, buyer.address)).to.be.true;
		});

		it('should end rental', async function () {
			// Rent the token
			await contract.connect(buyer).rentToken(tokenId, rentalDuration, rentalPrice);

			// End the rental
			await contract.connect(owner).endRental(tokenId);

			// Check rental status
			const rentalInfo = await contract.getRentalInfo(tokenId);
			expect(rentalInfo.active).to.be.false;
		});

		it('should extend rental', async function () {
			// Rent the token
			await contract.connect(buyer).rentToken(tokenId, rentalDuration, rentalPrice);

			const rentalInfo = await contract.getRentalInfo(tokenId);
			const originalEndTime = rentalInfo.endTime;

			// Extend the rental
			const additionalDuration = 43200; // 12 hours
			const additionalPayment = ethers.parseUnits('25', 6);
			await contract.connect(buyer).extendRental(tokenId, additionalDuration, additionalPayment);

			// Check rental status
			const updatedRentalInfo = await contract.getRentalInfo(tokenId);
			expect(updatedRentalInfo.endTime).to.equal(originalEndTime + BigInt(additionalDuration));
			expect(updatedRentalInfo.rentalPrice).to.equal(rentalPrice + additionalPayment);
		});
	});

	describe('Upgradeability', function () {
		it('should be managed by ProxyAdmin', async function () {
			// Get the deployed proxy admin
			const proxyAddress = await contract.getAddress();
			const adminAddress = await upgrades.erc1967.getAdminAddress(proxyAddress);

			// Check that the proxy admin is set
			expect(adminAddress).to.not.equal(ethers.ZeroAddress);

			// Get the implementation address
			const implementationAddress = await upgrades.erc1967.getImplementationAddress(proxyAddress);

			// Check that the implementation is set
			expect(implementationAddress).to.not.equal(ethers.ZeroAddress);
		});
	});
});
