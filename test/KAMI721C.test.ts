import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';
import { parseUnits } from 'ethers';

describe('KAMI721C with USDC Payments', function () {
	let kami721c: any;
	let usdc: any;
	let owner: SignerWithAddress;
	let user1: SignerWithAddress;
	let user2: SignerWithAddress;
	let platformAddress: SignerWithAddress;
	let royaltyReceiver1: SignerWithAddress;
	let royaltyReceiver2: SignerWithAddress;
	let royaltyReceiver3: SignerWithAddress;

	// USDC has 6 decimals
	const MINT_PRICE = parseUnits('1', 6); // 1 USDC
	const INITIAL_USDC_BALANCE = parseUnits('10000', 6); // 10,000 USDC
	const PLATFORM_COMMISSION_PERCENTAGE = 500; // 5%
	const DEFAULT_ROYALTY_PERCENTAGE = 1000; // 10%

	const createRoyaltyInfo = (address: string, feeNumerator: number) => {
		return {
			receiver: address,
			feeNumerator: feeNumerator,
		};
	};

	beforeEach(async function () {
		[owner, user1, user2, platformAddress, royaltyReceiver1, royaltyReceiver2, royaltyReceiver3] = await ethers.getSigners();

		// Deploy mock USDC token
		const MockERC20 = await ethers.getContractFactory('contracts/MockERC20.sol:MockERC20');
		usdc = await MockERC20.deploy('USD Coin', 'USDC', 6);
		await usdc.waitForDeployment();

		// Mint USDC to users
		await usdc.mint(await user1.getAddress(), INITIAL_USDC_BALANCE);
		await usdc.mint(await user2.getAddress(), INITIAL_USDC_BALANCE);

		// Deploy KAMI721C with USDC payments
		const KAMI721C = await ethers.getContractFactory('KAMI721C');
		kami721c = await KAMI721C.deploy(
			await usdc.getAddress(),
			'KAMI NFT',
			'KAMI',
			'https://api.example.com/token/',
			MINT_PRICE,
			await platformAddress.getAddress(),
			PLATFORM_COMMISSION_PERCENTAGE
		);
		await kami721c.waitForDeployment();

		// Approve USDC spending for users
		await usdc.connect(user1).approve(await kami721c.getAddress(), INITIAL_USDC_BALANCE);
		await usdc.connect(user2).approve(await kami721c.getAddress(), INITIAL_USDC_BALANCE);
	});

	describe('Deployment', function () {
		it('Should set the right owner role', async function () {
			expect(await kami721c.hasRole(await kami721c.OWNER_ROLE(), await owner.getAddress())).to.be.true;
		});

		it('Should set the right platform role', async function () {
			expect(await kami721c.hasRole(await kami721c.PLATFORM_ROLE(), await platformAddress.getAddress())).to.be.true;
		});

		it('Should set the correct USDC token address', async function () {
			expect(await kami721c.usdcToken()).to.equal(await usdc.getAddress());
		});

		it('Should set the correct mint price', async function () {
			expect(await kami721c.mintPrice()).to.equal(MINT_PRICE);
		});

		it('Should set the correct platform commission percentage', async function () {
			expect(await kami721c.platformCommissionPercentage()).to.equal(PLATFORM_COMMISSION_PERCENTAGE);
		});

		it('Should set the correct platform address', async function () {
			expect(await kami721c.platformAddress()).to.equal(await platformAddress.getAddress());
		});

		it('Should implement ERC721Enumerable functionality', async function () {
			// Check supportsInterface for ERC721Enumerable
			const ERC721EnumerableInterfaceId = '0x780e9d63';
			expect(await kami721c.supportsInterface(ERC721EnumerableInterfaceId)).to.be.true;
		});
	});

	describe('Mint Price Distribution', function () {
		it('Should distribute mint price correctly with platform commission and royalties', async function () {
			// Set mint royalties (95% in total to distribute the entire remaining amount after platform commission)
			const mintRoyalties = [
				createRoyaltyInfo(await royaltyReceiver1.getAddress(), 6000), // 60%
				createRoyaltyInfo(await royaltyReceiver2.getAddress(), 3500), // 35%
			];
			await kami721c.connect(owner).setMintRoyalties(mintRoyalties);

			// Record initial balances
			const platformBalanceBefore = await usdc.balanceOf(await platformAddress.getAddress());
			const r1BalanceBefore = await usdc.balanceOf(await royaltyReceiver1.getAddress());
			const r2BalanceBefore = await usdc.balanceOf(await royaltyReceiver2.getAddress());
			const contractBalanceBefore = await usdc.balanceOf(await kami721c.getAddress());

			// Mint a token
			await kami721c.connect(user1).mint();

			// Calculate expected distributions
			const platformCommission = (MINT_PRICE * BigInt(PLATFORM_COMMISSION_PERCENTAGE)) / BigInt(10000);
			const remainingAmount = MINT_PRICE - platformCommission;
			const royalty1Amount = (remainingAmount * BigInt(6000)) / BigInt(10000);
			const royalty2Amount = (remainingAmount * BigInt(3500)) / BigInt(10000);

			// Calculate undistributed amount (rounding error) that goes to first royalty receiver
			const totalRoyaltyAmounts = royalty1Amount + royalty2Amount;
			const undistributedAmount = remainingAmount - totalRoyaltyAmounts;

			// Verify platform commission
			expect(await usdc.balanceOf(await platformAddress.getAddress())).to.equal(platformBalanceBefore + platformCommission);

			// Verify royalty distributions (first receiver gets their share + any undistributed amount)
			expect(await usdc.balanceOf(await royaltyReceiver1.getAddress())).to.equal(
				r1BalanceBefore + royalty1Amount + undistributedAmount
			);
			expect(await usdc.balanceOf(await royaltyReceiver2.getAddress())).to.equal(r2BalanceBefore + royalty2Amount);

			// Contract shouldn't retain any USDC
			expect(await usdc.balanceOf(await kami721c.getAddress())).to.equal(contractBalanceBefore);
		});

		it('Should ensure mint royalties plus platform commission cannot exceed 100%', async function () {
			// Try to set mint royalties that, when combined with platform commission, exceed 100%
			const excessiveMintRoyalties = [
				createRoyaltyInfo(await royaltyReceiver1.getAddress(), 6000), // 60%
				createRoyaltyInfo(await royaltyReceiver2.getAddress(), 4000), // 40%
			];
			// Total: 100% + 5% platform commission = 105%
			await expect(kami721c.connect(owner).setMintRoyalties(excessiveMintRoyalties)).to.be.revertedWith(
				'Royalties + platform commission exceed 100%'
			);
		});
	});

	describe('Token Sale Process', function () {
		beforeEach(async function () {
			// Set transfer royalties (must total 100%)
			const transferRoyalties = [
				createRoyaltyInfo(await royaltyReceiver1.getAddress(), 7000), // 70%
				createRoyaltyInfo(await royaltyReceiver2.getAddress(), 3000), // 30%
			];
			await kami721c.connect(owner).setTransferRoyalties(transferRoyalties);

			// Set the royalty percentage (10% of sale price)
			await kami721c.connect(owner).setRoyaltyPercentage(DEFAULT_ROYALTY_PERCENTAGE);

			// Mint a token for user1
			await kami721c.connect(user1).mint();
		});

		it('Should correctly process a token sale with royalties and platform commission', async function () {
			// Record initial balances
			const salePrice = parseUnits('1000', 6); // 1000 USDC
			const user1BalanceBefore = await usdc.balanceOf(await user1.getAddress());
			const user2BalanceBefore = await usdc.balanceOf(await user2.getAddress());
			const platformBalanceBefore = await usdc.balanceOf(await platformAddress.getAddress());
			const r1BalanceBefore = await usdc.balanceOf(await royaltyReceiver1.getAddress());
			const r2BalanceBefore = await usdc.balanceOf(await royaltyReceiver2.getAddress());

			// Sell token from user1 to user2
			await kami721c.connect(user1).sellToken(await user2.getAddress(), 0, salePrice);

			// Calculate expected distributions
			const royaltyAmount = (salePrice * BigInt(DEFAULT_ROYALTY_PERCENTAGE)) / BigInt(10000); // 10% of sale price
			const platformCommission = (salePrice * BigInt(PLATFORM_COMMISSION_PERCENTAGE)) / BigInt(10000); // 5% of sale price
			const royalty1Amount = (royaltyAmount * BigInt(7000)) / BigInt(10000); // 70% of royalty amount
			const royalty2Amount = (royaltyAmount * BigInt(3000)) / BigInt(10000); // 30% of royalty amount
			const sellerProceeds = salePrice - (royaltyAmount + platformCommission);

			// Verify ownership transfer
			expect(await kami721c.ownerOf(0)).to.equal(await user2.getAddress());

			// Verify platform commission
			expect(await usdc.balanceOf(await platformAddress.getAddress())).to.equal(platformBalanceBefore + platformCommission);

			// Verify royalty payments
			expect(await usdc.balanceOf(await royaltyReceiver1.getAddress())).to.equal(r1BalanceBefore + royalty1Amount);
			expect(await usdc.balanceOf(await royaltyReceiver2.getAddress())).to.equal(r2BalanceBefore + royalty2Amount);

			// Verify seller receives correct payment
			expect(await usdc.balanceOf(await user1.getAddress())).to.equal(user1BalanceBefore + sellerProceeds);

			// Verify buyer paid the full sale price
			expect(await usdc.balanceOf(await user2.getAddress())).to.equal(user2BalanceBefore - salePrice);
		});

		it('Should use token-specific royalty receivers if set', async function () {
			// Set token-specific royalty receivers
			const tokenSpecificRoyalties = [
				createRoyaltyInfo(await royaltyReceiver2.getAddress(), 8000), // 80%
				createRoyaltyInfo(await royaltyReceiver3.getAddress(), 2000), // 20%
			];
			await kami721c.connect(owner).setTokenTransferRoyalties(0, tokenSpecificRoyalties);

			// Record initial balances
			const salePrice = parseUnits('1000', 6); // 1000 USDC
			const r1BalanceBefore = await usdc.balanceOf(await royaltyReceiver1.getAddress());
			const r2BalanceBefore = await usdc.balanceOf(await royaltyReceiver2.getAddress());
			const r3BalanceBefore = await usdc.balanceOf(await royaltyReceiver3.getAddress());

			// Sell token
			await kami721c.connect(user1).sellToken(await user2.getAddress(), 0, salePrice);

			// Calculate expected royalty distributions
			const totalRoyaltyAmount = (salePrice * BigInt(DEFAULT_ROYALTY_PERCENTAGE)) / BigInt(10000);
			const royalty2Amount = (totalRoyaltyAmount * BigInt(8000)) / BigInt(10000);
			const royalty3Amount = (totalRoyaltyAmount * BigInt(2000)) / BigInt(10000);

			// Verify token-specific royalties were used
			expect(await usdc.balanceOf(await royaltyReceiver1.getAddress())).to.equal(r1BalanceBefore); // Unchanged
			expect(await usdc.balanceOf(await royaltyReceiver2.getAddress())).to.equal(r2BalanceBefore + royalty2Amount);
			expect(await usdc.balanceOf(await royaltyReceiver3.getAddress())).to.equal(r3BalanceBefore + royalty3Amount);
		});

		it('Should only allow the token owner to sell', async function () {
			const salePrice = parseUnits('1000', 6);
			await expect(kami721c.connect(user2).sellToken(await user2.getAddress(), 0, salePrice)).to.be.revertedWith(
				'Only token owner can sell'
			);
		});
	});

	describe('Platform Management', function () {
		it('Should allow updating platform commission and address', async function () {
			const newPlatformCommission = 800; // 8%
			const newPlatformAddress = await royaltyReceiver3.getAddress();

			await kami721c.connect(owner).setPlatformCommission(newPlatformCommission, newPlatformAddress);

			expect(await kami721c.platformCommissionPercentage()).to.equal(newPlatformCommission);
			expect(await kami721c.platformAddress()).to.equal(newPlatformAddress);
			expect(await kami721c.hasRole(await kami721c.PLATFORM_ROLE(), await platformAddress.getAddress())).to.be.false;
			expect(await kami721c.hasRole(await kami721c.PLATFORM_ROLE(), newPlatformAddress)).to.be.true;
		});

		it('Should allow updating royalty percentage', async function () {
			const newRoyaltyPercentage = 1500; // 15%
			await kami721c.connect(owner).setRoyaltyPercentage(newRoyaltyPercentage);
			expect(await kami721c.royaltyPercentage()).to.equal(newRoyaltyPercentage);
		});

		it('Should not allow platform commission to exceed 20%', async function () {
			await expect(kami721c.connect(owner).setPlatformCommission(2100, await platformAddress.getAddress())).to.be.revertedWith(
				'Platform commission too high'
			);
		});

		it('Should not allow royalty percentage to exceed 30%', async function () {
			await expect(kami721c.connect(owner).setRoyaltyPercentage(3100)).to.be.revertedWith('Royalty percentage too high');
		});
	});

	describe('Transfer Royalties', function () {
		it('Should enforce 100% total for transfer royalty percentages', async function () {
			// Try with total < 100%
			const lowRoyalties = [
				createRoyaltyInfo(await royaltyReceiver1.getAddress(), 5000), // 50%
				createRoyaltyInfo(await royaltyReceiver2.getAddress(), 3000), // 30%
			];
			await expect(kami721c.connect(owner).setTransferRoyalties(lowRoyalties)).to.be.revertedWith(
				'Total transfer royalty percentages must equal 100%'
			);

			// Try with total > 100%
			const highRoyalties = [
				createRoyaltyInfo(await royaltyReceiver1.getAddress(), 7000), // 70%
				createRoyaltyInfo(await royaltyReceiver2.getAddress(), 4000), // 40%
			];
			await expect(kami721c.connect(owner).setTransferRoyalties(highRoyalties)).to.be.revertedWith(
				'Total transfer royalty percentages must equal 100%'
			);

			// Should work with exactly 100%
			const perfectRoyalties = [
				createRoyaltyInfo(await royaltyReceiver1.getAddress(), 7000), // 70%
				createRoyaltyInfo(await royaltyReceiver2.getAddress(), 3000), // 30%
			];
			await kami721c.connect(owner).setTransferRoyalties(perfectRoyalties);

			// Verify we can retrieve the receivers
			const royalties = await kami721c.getTransferRoyaltyReceivers(0);
			expect(royalties.length).to.equal(2);
			expect(royalties[0].receiver).to.equal(await royaltyReceiver1.getAddress());
			expect(royalties[0].feeNumerator).to.equal(7000);
			expect(royalties[1].receiver).to.equal(await royaltyReceiver2.getAddress());
			expect(royalties[1].feeNumerator).to.equal(3000);
		});
	});

	describe('ERC721Enumerable Functionality', function () {
		it('Should properly track token ownership with ERC721Enumerable', async function () {
			// Mint multiple tokens
			await kami721c.connect(user1).mint(); // Token ID 0
			await kami721c.connect(user1).mint(); // Token ID 1
			await kami721c.connect(user2).mint(); // Token ID 2

			// Check total supply
			expect(await kami721c.totalSupply()).to.equal(3);

			// Check balance of each user
			expect(await kami721c.balanceOf(await user1.getAddress())).to.equal(2);
			expect(await kami721c.balanceOf(await user2.getAddress())).to.equal(1);

			// Check tokenOfOwnerByIndex
			expect(await kami721c.tokenOfOwnerByIndex(await user1.getAddress(), 0)).to.equal(0);
			expect(await kami721c.tokenOfOwnerByIndex(await user1.getAddress(), 1)).to.equal(1);
			expect(await kami721c.tokenOfOwnerByIndex(await user2.getAddress(), 0)).to.equal(2);

			// Check tokenByIndex
			expect(await kami721c.tokenByIndex(0)).to.equal(0);
			expect(await kami721c.tokenByIndex(1)).to.equal(1);
			expect(await kami721c.tokenByIndex(2)).to.equal(2);
		});

		it('Should update enumeration correctly after transfers', async function () {
			// Mint tokens
			await kami721c.connect(user1).mint(); // Token ID 0
			await kami721c.connect(user1).mint(); // Token ID 1

			// Transfer from user1 to user2
			await kami721c.connect(user1).sellToken(await user2.getAddress(), 0, MINT_PRICE);

			// Check updated balances
			expect(await kami721c.balanceOf(await user1.getAddress())).to.equal(1);
			expect(await kami721c.balanceOf(await user2.getAddress())).to.equal(1);

			// Check tokenOfOwnerByIndex
			expect(await kami721c.tokenOfOwnerByIndex(await user1.getAddress(), 0)).to.equal(1);
			expect(await kami721c.tokenOfOwnerByIndex(await user2.getAddress(), 0)).to.equal(0);
		});
	});

	describe('Rental Functionality', function () {
		beforeEach(async function () {
			// Mint a token for user1
			await kami721c.connect(user1).mint();
		});

		it('Should allow renting a token', async function () {
			const rentalDuration = 86400; // 1 day in seconds
			const rentalPrice = parseUnits('0.5', 6); // 0.5 USDC

			// Approve USDC for rental
			await usdc.connect(user2).approve(await kami721c.getAddress(), rentalPrice);

			// Record initial balances
			const user1BalanceBefore = await usdc.balanceOf(await user1.getAddress());
			const user2BalanceBefore = await usdc.balanceOf(await user2.getAddress());
			const platformBalanceBefore = await usdc.balanceOf(await platformAddress.getAddress());
			const contractBalanceBefore = await usdc.balanceOf(await kami721c.getAddress());

			// Get current block timestamp
			const latestBlock = await ethers.provider.getBlock('latest');
			if (!latestBlock) throw new Error('Failed to get latest block');
			const currentBlockTimestamp = latestBlock.timestamp;

			// Rent the token
			await kami721c.connect(user2).rentToken(0, rentalDuration, rentalPrice);

			// Verify rental information
			const rentalInfo = await kami721c.getRentalInfo(0);
			expect(rentalInfo.renter).to.equal(await user2.getAddress());
			expect(rentalInfo.startTime).to.be.closeTo(currentBlockTimestamp, 5);
			expect(rentalInfo.endTime).to.be.closeTo(currentBlockTimestamp + rentalDuration, 5);
			expect(rentalInfo.rentalPrice).to.equal(rentalPrice);
			expect(rentalInfo.active).to.be.true;

			// Calculate expected distributions
			const platformCommission = (rentalPrice * BigInt(PLATFORM_COMMISSION_PERCENTAGE)) / BigInt(10000);
			const ownerShare = rentalPrice - platformCommission;

			// Verify USDC transfers
			expect(await usdc.balanceOf(await user1.getAddress())).to.equal(user1BalanceBefore + ownerShare);
			expect(await usdc.balanceOf(await user2.getAddress())).to.equal(user2BalanceBefore - rentalPrice);
			expect(await usdc.balanceOf(await platformAddress.getAddress())).to.equal(platformBalanceBefore + platformCommission);
			expect(await usdc.balanceOf(await kami721c.getAddress())).to.equal(contractBalanceBefore);

			// Verify RENTER_ROLE was granted
			expect(await kami721c.hasRole(await kami721c.RENTER_ROLE(), await user2.getAddress())).to.be.true;
		});

		it('Should prevent renting an already rented token', async function () {
			const rentalDuration = 86400; // 1 day in seconds
			const rentalPrice = parseUnits('0.5', 6); // 0.5 USDC

			// Approve USDC for rental
			await usdc.connect(user2).approve(await kami721c.getAddress(), rentalPrice);

			// Rent the token
			await kami721c.connect(user2).rentToken(0, rentalDuration, rentalPrice);

			// Try to rent the same token again
			await expect(kami721c.connect(royaltyReceiver1).rentToken(0, rentalDuration, rentalPrice)).to.be.revertedWith(
				'Token is already rented'
			);
		});

		it('Should prevent the owner from renting their own token', async function () {
			const rentalDuration = 86400; // 1 day in seconds
			const rentalPrice = parseUnits('0.5', 6); // 0.5 USDC

			// Approve USDC for rental
			await usdc.connect(user1).approve(await kami721c.getAddress(), rentalPrice);

			// Try to rent the token
			await expect(kami721c.connect(user1).rentToken(0, rentalDuration, rentalPrice)).to.be.revertedWith(
				'Owner cannot rent their own token'
			);
		});

		it('Should allow ending a rental early', async function () {
			const rentalDuration = 86400; // 1 day in seconds
			const rentalPrice = parseUnits('0.5', 6); // 0.5 USDC

			// Approve USDC for rental
			await usdc.connect(user2).approve(await kami721c.getAddress(), rentalPrice);

			// Rent the token
			await kami721c.connect(user2).rentToken(0, rentalDuration, rentalPrice);

			// End the rental
			await kami721c.connect(user1).endRental(0);

			// Verify rental is no longer active
			const rentalInfo = await kami721c.getRentalInfo(0);
			expect(rentalInfo.active).to.be.false;

			// Verify RENTER_ROLE was revoked
			expect(await kami721c.hasRole(await kami721c.RENTER_ROLE(), await user2.getAddress())).to.be.false;
		});

		it('Should allow extending a rental', async function () {
			const rentalDuration = 86400; // 1 day in seconds
			const rentalPrice = parseUnits('0.5', 6); // 0.5 USDC
			const additionalDuration = 43200; // 12 hours in seconds
			const additionalPayment = parseUnits('0.25', 6); // 0.25 USDC

			// Approve USDC for rental
			await usdc.connect(user2).approve(await kami721c.getAddress(), rentalPrice + additionalPayment);

			// Rent the token
			await kami721c.connect(user2).rentToken(0, rentalDuration, rentalPrice);

			// Record initial balances
			const user1BalanceBefore = await usdc.balanceOf(await user1.getAddress());
			const user2BalanceBefore = await usdc.balanceOf(await user2.getAddress());
			const platformBalanceBefore = await usdc.balanceOf(await platformAddress.getAddress());
			const contractBalanceBefore = await usdc.balanceOf(await kami721c.getAddress());

			// Get current block timestamp
			const latestBlock = await ethers.provider.getBlock('latest');
			if (!latestBlock) throw new Error('Failed to get latest block');
			const currentBlockTimestamp = latestBlock.timestamp;

			// Extend the rental
			await kami721c.connect(user2).extendRental(0, additionalDuration, additionalPayment);

			// Verify rental information
			const rentalInfo = await kami721c.getRentalInfo(0);
			expect(rentalInfo.endTime).to.be.closeTo(currentBlockTimestamp + rentalDuration + additionalDuration, 5);
			expect(rentalInfo.rentalPrice).to.equal(rentalPrice + additionalPayment);
			expect(rentalInfo.active).to.be.true;

			// Calculate expected distributions
			const platformCommission = (additionalPayment * BigInt(PLATFORM_COMMISSION_PERCENTAGE)) / BigInt(10000);
			const ownerShare = additionalPayment - platformCommission;

			// Verify USDC transfers
			expect(await usdc.balanceOf(await user1.getAddress())).to.equal(user1BalanceBefore + ownerShare);
			expect(await usdc.balanceOf(await user2.getAddress())).to.equal(user2BalanceBefore - additionalPayment);
			expect(await usdc.balanceOf(await platformAddress.getAddress())).to.equal(platformBalanceBefore + platformCommission);
			expect(await usdc.balanceOf(await kami721c.getAddress())).to.equal(contractBalanceBefore);
		});

		it('Should prevent transfers during rental period', async function () {
			const rentalDuration = 86400; // 1 day in seconds
			const rentalPrice = parseUnits('0.5', 6); // 0.5 USDC

			// Approve USDC for rental
			await usdc.connect(user2).approve(await kami721c.getAddress(), rentalPrice);

			// Rent the token
			await kami721c.connect(user2).rentToken(0, rentalDuration, rentalPrice);

			// Try to transfer the token
			await expect(
				kami721c.connect(user1).transferFrom(await user1.getAddress(), await royaltyReceiver1.getAddress(), 0)
			).to.be.revertedWith('Token is locked during rental period');
		});

		it('Should automatically end rental when the rental period expires', async function () {
			const rentalDuration = 5; // 5 seconds
			const rentalPrice = parseUnits('0.5', 6); // 0.5 USDC

			// Approve USDC for rental
			await usdc.connect(user2).approve(await kami721c.getAddress(), rentalPrice);

			// Rent the token
			await kami721c.connect(user2).rentToken(0, rentalDuration, rentalPrice);

			// Wait for rental period to expire
			await new Promise((resolve) => setTimeout(resolve, 6000));

			// Try to transfer the token (should succeed as rental has expired)
			await kami721c.connect(user1).transferFrom(await user1.getAddress(), await royaltyReceiver1.getAddress(), 0);

			// Verify rental is no longer active
			const rentalInfo = await kami721c.getRentalInfo(0);
			expect(rentalInfo.active).to.be.false;

			// Verify RENTER_ROLE was revoked
			expect(await kami721c.hasRole(await kami721c.RENTER_ROLE(), await user2.getAddress())).to.be.false;
		});

		it('Should prevent selling a rented token', async function () {
			const rentalDuration = 86400; // 1 day in seconds
			const rentalPrice = parseUnits('0.5', 6); // 0.5 USDC
			const salePrice = parseUnits('10', 6); // 10 USDC

			// Approve USDC for rental
			await usdc.connect(user2).approve(await kami721c.getAddress(), rentalPrice);

			// Rent the token
			await kami721c.connect(user2).rentToken(0, rentalDuration, rentalPrice);

			// Try to sell the token
			await expect(kami721c.connect(user1).sellToken(await royaltyReceiver1.getAddress(), 0, salePrice)).to.be.revertedWith(
				'Token is currently rented'
			);
		});

		it('Should prevent burning a rented token', async function () {
			const rentalDuration = 86400; // 1 day in seconds
			const rentalPrice = parseUnits('0.5', 6); // 0.5 USDC

			// Approve USDC for rental
			await usdc.connect(user2).approve(await kami721c.getAddress(), rentalPrice);

			// Rent the token
			await kami721c.connect(user2).rentToken(0, rentalDuration, rentalPrice);

			// Try to burn the token
			await expect(kami721c.connect(user1).burn(0)).to.be.revertedWith('Cannot burn a rented token');
		});
	});
});
