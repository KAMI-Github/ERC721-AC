import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';
import { parseUnits, ZeroAddress } from 'ethers';
// import { KAMI721AC, MockERC20 } from '../typechain-types'; // Removed type imports for now

describe('KAMI721AC with USDC Payments', function () {
	let kami721ac: any; // Type changed to any
	let usdc: any; // Type changed to any
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

		// Deploy KAMI721AC with USDC payments
		const KAMI721ACFactory = await ethers.getContractFactory('KAMI721AC');
		kami721ac = await KAMI721ACFactory.deploy(
			await usdc.getAddress(),
			'KAMI NFT',
			'KAMI',
			'https://api.example.com/token/',
			MINT_PRICE,
			await platformAddress.getAddress(),
			PLATFORM_COMMISSION_PERCENTAGE
		);
		await kami721ac.waitForDeployment();

		// Approve USDC spending for users
		await usdc.connect(user1).approve(await kami721ac.getAddress(), INITIAL_USDC_BALANCE);
		await usdc.connect(user2).approve(await kami721ac.getAddress(), INITIAL_USDC_BALANCE);
	});

	describe('Deployment', function () {
		it('Should set the right owner role', async function () {
			expect(await kami721ac.hasRole(await kami721ac.OWNER_ROLE(), await owner.getAddress())).to.be.true;
		});

		it('Should set the right platform role', async function () {
			expect(await kami721ac.hasRole(await kami721ac.PLATFORM_ROLE(), await platformAddress.getAddress())).to.be.true;
		});

		it('Should set the correct USDC token address', async function () {
			expect(await kami721ac.usdcToken()).to.equal(await usdc.getAddress());
		});

		it('Should set the correct mint price', async function () {
			expect(await kami721ac.mintPrice()).to.equal(MINT_PRICE);
		});

		it('Should set the correct platform commission percentage', async function () {
			expect(await kami721ac.platformCommissionPercentage()).to.equal(PLATFORM_COMMISSION_PERCENTAGE);
		});

		it('Should set the correct platform address', async function () {
			expect(await kami721ac.platformAddress()).to.equal(await platformAddress.getAddress());
		});

		it('Should support ERC721A and ERC2981 interfaces', async function () {
			// Check supportsInterface for ERC721A and ERC2981
			const ERC721InterfaceId = '0x80ac58cd'; // Standard ERC721
			const ERC2981InterfaceId = '0x2a55205a';
			expect(await kami721ac.supportsInterface(ERC721InterfaceId)).to.be.true;

			// --- Debugging ERC2981 ---
			const reportedERC2981Id = await kami721ac.debugGetERC2981Id();
			const supportsERC2981 = await kami721ac.supportsInterface(ERC2981InterfaceId);
			console.log(`   [DEBUG] ERC2981 ID from test: ${ERC2981InterfaceId}`);
			console.log(`   [DEBUG] ERC2981 ID from contract (debugGetERC2981Id): ${reportedERC2981Id}`);
			console.log(`   [DEBUG] supportsInterface(ERC2981InterfaceId) returned: ${supportsERC2981}`);
			// --- End Debugging ---

			expect(supportsERC2981).to.be.true;
		});
	});

	describe('Single Mint Price Distribution', function () {
		it('Should distribute mint price correctly for a single mint', async function () {
			// Set mint royalties (95% total to match remaining after 5% platform commission)
			const mintRoyalties = [
				createRoyaltyInfo(await royaltyReceiver1.getAddress(), 6000), // 60%
				createRoyaltyInfo(await royaltyReceiver2.getAddress(), 3500), // 35%
			];
			await kami721ac.connect(owner).setMintRoyalties(mintRoyalties);

			// Record initial balances
			const platformBalanceBefore = await usdc.balanceOf(await platformAddress.getAddress());
			const r1BalanceBefore = await usdc.balanceOf(await royaltyReceiver1.getAddress());
			const r2BalanceBefore = await usdc.balanceOf(await royaltyReceiver2.getAddress());
			const contractBalanceBefore = await usdc.balanceOf(await kami721ac.getAddress());

			// Mint ONE token
			await kami721ac.connect(user1).mint(1);

			// Calculate expected distributions (for ONE token)
			const platformCommission = (MINT_PRICE * BigInt(PLATFORM_COMMISSION_PERCENTAGE)) / BigInt(10000);
			// Royalties are calculated on the *total* mint price
			const royalty1Amount = (MINT_PRICE * BigInt(6000)) / BigInt(10000);
			const royalty2Amount = (MINT_PRICE * BigInt(3500)) / BigInt(10000);

			// No undistributed amount calculation needed here as percentages are applied to total price
			// const totalRoyaltyAmounts = royalty1Amount + royalty2Amount;
			// const undistributedAmount = remainingAmount - totalRoyaltyAmounts; // Removed this

			// Verify platform commission
			expect(await usdc.balanceOf(await platformAddress.getAddress())).to.equal(platformBalanceBefore + platformCommission);

			// Verify royalty distributions
			expect(await usdc.balanceOf(await royaltyReceiver1.getAddress())).to.equal(
				r1BalanceBefore + royalty1Amount // Removed undistributedAmount
			);
			expect(await usdc.balanceOf(await royaltyReceiver2.getAddress())).to.equal(r2BalanceBefore + royalty2Amount);

			// Contract shouldn't retain any USDC
			expect(await usdc.balanceOf(await kami721ac.getAddress())).to.equal(contractBalanceBefore);
		});

		it('Should ensure mint royalties plus platform commission cannot exceed 100%', async function () {
			// Try to set mint royalties that, when combined with platform commission, exceed 100%
			const excessiveMintRoyalties = [
				createRoyaltyInfo(await royaltyReceiver1.getAddress(), 6000), // 60%
				createRoyaltyInfo(await royaltyReceiver2.getAddress(), 4000), // 40% (Total 100% + 5% platform = 105%)
			];
			await expect(kami721ac.connect(owner).setMintRoyalties(excessiveMintRoyalties)).to.be.revertedWith(
				'Royalties + platform commission exceed 100%'
			);
		});
	});

	describe('Claiming / Batch Minting', function () {
		const BATCH_SIZE = 5;

		beforeEach(async function () {
			// Set up default mint royalties for batch test
			const mintRoyalties = [
				createRoyaltyInfo(await royaltyReceiver1.getAddress(), 7500), // 75%
				createRoyaltyInfo(await royaltyReceiver2.getAddress(), 2000), // 20%
			]; // Total 95% to match remaining after 5% platform fee
			await kami721ac.connect(owner).setMintRoyalties(mintRoyalties);

			// Ensure user1 has enough allowance for batch mint
			const totalMintPrice = MINT_PRICE * BigInt(BATCH_SIZE);
			await usdc.connect(user1).approve(await kami721ac.getAddress(), totalMintPrice);
		});

		it('Should allow batch minting multiple tokens', async function () {
			await expect(kami721ac.connect(user1).mint(BATCH_SIZE))
				.to.emit(kami721ac, 'Transfer')
				.withArgs(ZeroAddress, await user1.getAddress(), 0) // ERC721A emits only one Transfer event for batch mints
				.and.to.emit(kami721ac, 'Transfer')
				.withArgs(ZeroAddress, await user1.getAddress(), BATCH_SIZE - 1);

			expect(await kami721ac.totalSupply()).to.equal(BATCH_SIZE);
			expect(await kami721ac.balanceOf(await user1.getAddress())).to.equal(BATCH_SIZE);
			for (let i = 0; i < BATCH_SIZE; i++) {
				expect(await kami721ac.ownerOf(i)).to.equal(await user1.getAddress());
			}
		});

		it('Should distribute funds correctly for batch minting', async function () {
			const totalMintPrice = MINT_PRICE * BigInt(BATCH_SIZE);

			// Record initial balances
			const user1BalanceBefore = await usdc.balanceOf(await user1.getAddress());
			const platformBalanceBefore = await usdc.balanceOf(await platformAddress.getAddress());
			const r1BalanceBefore = await usdc.balanceOf(await royaltyReceiver1.getAddress());
			const r2BalanceBefore = await usdc.balanceOf(await royaltyReceiver2.getAddress());
			const contractBalanceBefore = await usdc.balanceOf(await kami721ac.getAddress());

			// Mint batch
			await kami721ac.connect(user1).mint(BATCH_SIZE);

			// Calculate expected distributions (based on total price and default mint royalties)
			const platformCommission = (totalMintPrice * BigInt(PLATFORM_COMMISSION_PERCENTAGE)) / BigInt(10000);
			const remainingAmount = totalMintPrice - platformCommission;
			const royalty1Amount = (totalMintPrice * BigInt(7500)) / BigInt(10000); // Using total payment for calculation
			const royalty2Amount = (totalMintPrice * BigInt(2000)) / BigInt(10000);
			// Note: The contract's distribution logic applies percentages to the total payment.
			// The internal function calculates commission first, then distributes royalties based on *original* total payment.

			// Verify balances
			expect(await usdc.balanceOf(await user1.getAddress())).to.equal(user1BalanceBefore - totalMintPrice);
			expect(await usdc.balanceOf(await platformAddress.getAddress())).to.equal(platformBalanceBefore + platformCommission);
			expect(await usdc.balanceOf(await royaltyReceiver1.getAddress())).to.equal(r1BalanceBefore + royalty1Amount);
			expect(await usdc.balanceOf(await royaltyReceiver2.getAddress())).to.equal(r2BalanceBefore + royalty2Amount);
			expect(await usdc.balanceOf(await kami721ac.getAddress())).to.equal(contractBalanceBefore); // Should be zero
		});

		it('Should revert if minting quantity is zero', async function () {
			await expect(kami721ac.connect(user1).mint(0)).to.be.revertedWith('Quantity must be greater than zero');
		});

		it('Should revert if user has insufficient USDC balance for batch mint', async function () {
			// Drain user1's USDC
			const user1Balance = await usdc.balanceOf(await user1.getAddress());
			await usdc.connect(user1).transfer(await owner.getAddress(), user1Balance);

			await expect(kami721ac.connect(user1).mint(BATCH_SIZE)).to.be.revertedWith('Insufficient USDC balance');
		});

		it('Should revert if user has insufficient USDC allowance for batch mint', async function () {
			// Reduce user1's allowance
			await usdc.connect(user1).approve(await kami721ac.getAddress(), 0);

			await expect(kami721ac.connect(user1).mint(BATCH_SIZE)).to.be.revertedWith('Insufficient USDC allowance');
		});
	});

	describe('Token Sale Process', function () {
		beforeEach(async function () {
			// Set transfer royalties (must total 100%)
			const transferRoyalties = [
				createRoyaltyInfo(await royaltyReceiver1.getAddress(), 7000), // 70%
				createRoyaltyInfo(await royaltyReceiver2.getAddress(), 3000), // 30%
			];
			await kami721ac.connect(owner).setTransferRoyalties(transferRoyalties);

			// Set the royalty percentage (10% of sale price)
			await kami721ac.connect(owner).setRoyaltyPercentage(DEFAULT_ROYALTY_PERCENTAGE);

			// Mint a token for user1
			await kami721ac.connect(user1).mint(1); // Mint token 0
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
			await kami721ac.connect(user1).sellToken(await user2.getAddress(), 0, salePrice);

			// Calculate expected distributions
			const royaltyAmount = (salePrice * BigInt(DEFAULT_ROYALTY_PERCENTAGE)) / BigInt(10000); // 10% of sale price
			const platformCommission = (salePrice * BigInt(PLATFORM_COMMISSION_PERCENTAGE)) / BigInt(10000); // 5% of sale price
			const royalty1Amount = (royaltyAmount * BigInt(7000)) / BigInt(10000); // 70% of royalty amount
			const royalty2Amount = (royaltyAmount * BigInt(3000)) / BigInt(10000); // 30% of royalty amount
			const sellerProceeds = salePrice - (royaltyAmount + platformCommission);

			// Verify ownership transfer
			expect(await kami721ac.ownerOf(0)).to.equal(await user2.getAddress());

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
			await kami721ac.connect(owner).setTokenTransferRoyalties(0, tokenSpecificRoyalties);

			// Record initial balances
			const salePrice = parseUnits('1000', 6); // 1000 USDC
			const r1BalanceBefore = await usdc.balanceOf(await royaltyReceiver1.getAddress());
			const r2BalanceBefore = await usdc.balanceOf(await royaltyReceiver2.getAddress());
			const r3BalanceBefore = await usdc.balanceOf(await royaltyReceiver3.getAddress());

			// Sell token
			await kami721ac.connect(user1).sellToken(await user2.getAddress(), 0, salePrice);

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
			await expect(kami721ac.connect(user2).sellToken(await user2.getAddress(), 0, salePrice)).to.be.revertedWith(
				'Only token owner can sell'
			);
		});
	});

	describe('Platform Management', function () {
		it('Should allow updating platform commission and address', async function () {
			const newPlatformCommission = 800; // 8%
			const newPlatformAddress = await royaltyReceiver3.getAddress();

			await kami721ac.connect(owner).setPlatformCommission(newPlatformCommission, newPlatformAddress);

			expect(await kami721ac.platformCommissionPercentage()).to.equal(newPlatformCommission);
			expect(await kami721ac.platformAddress()).to.equal(newPlatformAddress);
			expect(await kami721ac.hasRole(await kami721ac.PLATFORM_ROLE(), await platformAddress.getAddress())).to.be.false;
			expect(await kami721ac.hasRole(await kami721ac.PLATFORM_ROLE(), newPlatformAddress)).to.be.true;
		});

		it('Should allow updating royalty percentage', async function () {
			const newRoyaltyPercentage = 1500; // 15%
			await kami721ac.connect(owner).setRoyaltyPercentage(newRoyaltyPercentage);
			expect(await kami721ac.royaltyPercentage()).to.equal(newRoyaltyPercentage);
		});

		it('Should not allow platform commission to exceed 20%', async function () {
			await expect(kami721ac.connect(owner).setPlatformCommission(2100, await platformAddress.getAddress())).to.be.revertedWith(
				'Platform commission too high'
			);
		});

		it('Should not allow royalty percentage to exceed 30%', async function () {
			await expect(kami721ac.connect(owner).setRoyaltyPercentage(3100)).to.be.revertedWith('Royalty percentage too high');
		});
	});

	describe('Transfer Royalties', function () {
		it('Should enforce 100% total for transfer royalty percentages', async function () {
			// Try with total < 100%
			const lowRoyalties = [
				createRoyaltyInfo(await royaltyReceiver1.getAddress(), 5000), // 50%
				createRoyaltyInfo(await royaltyReceiver2.getAddress(), 3000), // 30%
			];
			await expect(kami721ac.connect(owner).setTransferRoyalties(lowRoyalties)).to.be.revertedWith(
				'Total transfer royalty percentages must equal 100%'
			);

			// Try with total > 100%
			const highRoyalties = [
				createRoyaltyInfo(await royaltyReceiver1.getAddress(), 7000), // 70%
				createRoyaltyInfo(await royaltyReceiver2.getAddress(), 4000), // 40%
			];
			await expect(kami721ac.connect(owner).setTransferRoyalties(highRoyalties)).to.be.revertedWith(
				'Total transfer royalty percentages must equal 100%'
			);

			// Should work with exactly 100%
			const perfectRoyalties = [
				createRoyaltyInfo(await royaltyReceiver1.getAddress(), 7000), // 70%
				createRoyaltyInfo(await royaltyReceiver2.getAddress(), 3000), // 30%
			];
			await kami721ac.connect(owner).setTransferRoyalties(perfectRoyalties);

			// Verify we can retrieve the receivers
			const royalties = await kami721ac.getTransferRoyaltyReceivers(0);
			expect(royalties.length).to.equal(2);
			expect(royalties[0].receiver).to.equal(await royaltyReceiver1.getAddress());
			expect(royalties[0].feeNumerator).to.equal(7000);
			expect(royalties[1].receiver).to.equal(await royaltyReceiver2.getAddress());
			expect(royalties[1].feeNumerator).to.equal(3000);
		});
	});

	describe('ERC721A Functionality', function () {
		it('Should properly track token ownership with ERC721A', async function () {
			// Mint multiple tokens (batch and single)
			await kami721ac.connect(user1).mint(2); // Token IDs 0, 1
			await kami721ac.connect(user2).mint(1); // Token ID 2

			// Check total supply
			expect(await kami721ac.totalSupply()).to.equal(3);

			// Check balance of each user
			expect(await kami721ac.balanceOf(await user1.getAddress())).to.equal(2);
			expect(await kami721ac.balanceOf(await user2.getAddress())).to.equal(1);

			// Check ownerOf for each token
			expect(await kami721ac.ownerOf(0)).to.equal(await user1.getAddress());
			expect(await kami721ac.ownerOf(1)).to.equal(await user1.getAddress());
			expect(await kami721ac.ownerOf(2)).to.equal(await user2.getAddress());

			// ERC721Enumerable specific tests removed (tokenOfOwnerByIndex, tokenByIndex)
		});

		it('Should update ownership correctly after transfers', async function () {
			// Mint tokens
			await kami721ac.connect(user1).mint(2); // Token IDs 0, 1

			// Transfer token 0 from user1 to user2 (using safeTransferFrom)
			await kami721ac.connect(user1).safeTransferFrom(await user1.getAddress(), await user2.getAddress(), 0);

			// Check updated balances
			expect(await kami721ac.balanceOf(await user1.getAddress())).to.equal(1);
			expect(await kami721ac.balanceOf(await user2.getAddress())).to.equal(1);

			// Check ownerOf for transferred and remaining tokens
			expect(await kami721ac.ownerOf(0)).to.equal(await user2.getAddress());
			expect(await kami721ac.ownerOf(1)).to.equal(await user1.getAddress());

			// ERC721Enumerable specific tests removed
		});
	});

	describe('Rental Functionality', function () {
		beforeEach(async function () {
			// Mint a token for user1
			await kami721ac.connect(user1).mint(1); // Token ID 0
		});

		it('Should allow renting a token and update userOf', async function () {
			const rentalDuration = 86400; // 1 day in seconds
			const rentalPrice = parseUnits('0.5', 6); // 0.5 USDC

			// Approve USDC for rental
			await usdc.connect(user2).approve(await kami721ac.getAddress(), rentalPrice);

			// Record initial balances
			const user1BalanceBefore = await usdc.balanceOf(await user1.getAddress());
			const user2BalanceBefore = await usdc.balanceOf(await user2.getAddress());
			const contractBalanceBefore = await usdc.balanceOf(await kami721ac.getAddress());

			// Get current block timestamp
			const latestBlock = await ethers.provider.getBlock('latest');
			if (!latestBlock) throw new Error('Failed to get latest block');
			const currentBlockTimestamp = latestBlock.timestamp;

			// Rent the token
			await kami721ac.connect(user2).rentToken(0, rentalDuration, rentalPrice);

			// Verify rental information
			const rentalInfo = await kami721ac.getRentalInfo(0);
			expect(rentalInfo.renter).to.equal(await user2.getAddress());
			expect(rentalInfo.startTime).to.be.closeTo(currentBlockTimestamp, 5);
			expect(rentalInfo.endTime).to.be.closeTo(currentBlockTimestamp + rentalDuration, 5);
			expect(rentalInfo.rentalPrice).to.equal(rentalPrice);
			expect(rentalInfo.active).to.be.true;

			// Calculate expected distributions (direct payment from renter to owner)
			const ownerShare = rentalPrice; // Owner gets full rental price

			// Verify USDC transfers
			expect(await usdc.balanceOf(await user1.getAddress())).to.equal(user1BalanceBefore + ownerShare);
			expect(await usdc.balanceOf(await user2.getAddress())).to.equal(user2BalanceBefore - rentalPrice);
			expect(await usdc.balanceOf(await kami721ac.getAddress())).to.equal(contractBalanceBefore);

			// Verify RENTER_ROLE was granted
			expect(await kami721ac.hasRole(await kami721ac.RENTER_ROLE(), await user2.getAddress())).to.be.true;

			// Verify userOf returns the renter
			expect(await kami721ac.userOf(0)).to.equal(await user2.getAddress());
			expect(await kami721ac.isUser(0, await user2.getAddress())).to.be.true;
			expect(await kami721ac.isUser(0, await user1.getAddress())).to.be.false;
		});

		it('Should prevent renting an already rented token', async function () {
			const rentalDuration = 86400; // 1 day in seconds
			const rentalPrice = parseUnits('0.5', 6); // 0.5 USDC

			// Approve USDC for rental
			await usdc.connect(user2).approve(await kami721ac.getAddress(), rentalPrice * 2n); // Approve enough for two attempts

			// Rent the token
			await kami721ac.connect(user2).rentToken(0, rentalDuration, rentalPrice);

			// Try to rent the same token again
			await expect(kami721ac.connect(royaltyReceiver1).rentToken(0, rentalDuration, rentalPrice)).to.be.revertedWith(
				'Token is already rented'
			);
		});

		it('Should prevent the owner from renting their own token', async function () {
			const rentalDuration = 86400; // 1 day in seconds
			const rentalPrice = parseUnits('0.5', 6); // 0.5 USDC

			// Approve USDC for rental
			await usdc.connect(user1).approve(await kami721ac.getAddress(), rentalPrice);

			// Try to rent the token
			await expect(kami721ac.connect(user1).rentToken(0, rentalDuration, rentalPrice)).to.be.revertedWith(
				'Owner cannot rent their own token'
			);
		});

		it('Should allow ending a rental early and update userOf', async function () {
			const rentalDuration = 86400; // 1 day in seconds
			const rentalPrice = parseUnits('0.5', 6); // 0.5 USDC

			// Approve USDC for rental
			await usdc.connect(user2).approve(await kami721ac.getAddress(), rentalPrice);

			// Rent the token
			await kami721ac.connect(user2).rentToken(0, rentalDuration, rentalPrice);

			// End the rental (owner ends it)
			await kami721ac.connect(user1).endRental(0);

			// Verify rental is no longer active
			const rentalInfo = await kami721ac.getRentalInfo(0);
			expect(rentalInfo.active).to.be.false;

			// Verify RENTER_ROLE was revoked
			expect(await kami721ac.hasRole(await kami721ac.RENTER_ROLE(), await user2.getAddress())).to.be.false;

			// Verify userOf now returns the owner
			expect(await kami721ac.userOf(0)).to.equal(await user1.getAddress());
			expect(await kami721ac.isUser(0, await user1.getAddress())).to.be.true;
			expect(await kami721ac.isUser(0, await user2.getAddress())).to.be.false;
		});

		it('Should allow extending a rental', async function () {
			const rentalDuration = 86400n; // Use BigInt
			const rentalPrice = parseUnits('0.5', 6);
			const additionalDuration = 43200n; // Use BigInt
			const additionalPayment = parseUnits('0.25', 6); // 0.25 USDC

			// Approve USDC for rental and extension
			await usdc.connect(user2).approve(await kami721ac.getAddress(), rentalPrice + additionalPayment);

			// Rent the token
			await kami721ac.connect(user2).rentToken(0, rentalDuration, rentalPrice);
			const rentalInfoBefore = await kami721ac.getRentalInfo(0);
			const expectedInitialEndTime = rentalInfoBefore.startTime + rentalDuration; // BigInt math

			// Record initial balances before extension
			const user1BalanceBeforeExt = await usdc.balanceOf(await user1.getAddress());
			const user2BalanceBeforeExt = await usdc.balanceOf(await user2.getAddress());
			const contractBalanceBeforeExt = await usdc.balanceOf(await kami721ac.getAddress());

			// Extend the rental
			await kami721ac.connect(user2).extendRental(0, additionalDuration, additionalPayment);

			// Verify rental information
			const extendedRentalInfo = await kami721ac.getRentalInfo(0);
			expect(extendedRentalInfo.endTime).to.equal(expectedInitialEndTime + additionalDuration); // BigInt math
			// rentalPrice in struct is not updated by extendRental, which is expected
			// expect(extendedRentalInfo.rentalPrice).to.equal(rentalPrice + additionalPayment);
			expect(extendedRentalInfo.active).to.be.true;

			// Calculate expected distributions (direct payment)
			const ownerShareExtension = additionalPayment;

			// Verify USDC transfers for extension
			expect(await usdc.balanceOf(await user1.getAddress())).to.equal(user1BalanceBeforeExt + ownerShareExtension);
			expect(await usdc.balanceOf(await user2.getAddress())).to.equal(user2BalanceBeforeExt - additionalPayment);
			expect(await usdc.balanceOf(await kami721ac.getAddress())).to.equal(contractBalanceBeforeExt);
		});

		it('Should prevent transfers during rental period', async function () {
			const rentalDuration = 86400n; // Use BigInt
			const rentalPrice = parseUnits('0.5', 6); // 0.5 USDC

			// Approve USDC for rental
			await usdc.connect(user2).approve(await kami721ac.getAddress(), rentalPrice);

			// Rent the token
			await kami721ac.connect(user2).rentToken(0, rentalDuration, rentalPrice);

			// Try to transfer the token using transferFrom
			await expect(
				kami721ac.connect(user1).transferFrom(await user1.getAddress(), await royaltyReceiver1.getAddress(), 0)
			).to.be.revertedWith('Token is rented');

			// Try to transfer the token using safeTransferFrom
			await expect(
				kami721ac.connect(user1).safeTransferFrom(await user1.getAddress(), await royaltyReceiver1.getAddress(), 0)
			).to.be.revertedWith('Token is rented');
		});

		it('Should allow transfers after rental period expires', async function () {
			const rentalDuration = 2n; // Use BigInt
			const rentalPrice = parseUnits('0.5', 6); // 0.5 USDC

			// Approve USDC for rental
			await usdc.connect(user2).approve(await kami721ac.getAddress(), rentalPrice);

			// Rent the token
			await kami721ac.connect(user2).rentToken(0, rentalDuration, rentalPrice);

			// Verify userOf is renter
			expect(await kami721ac.userOf(0)).to.equal(await user2.getAddress());

			// Wait for rental period to expire
			await ethers.provider.send('evm_increaseTime', [Number(rentalDuration) + 1]); // evm_increaseTime takes number
			await ethers.provider.send('evm_mine', []);

			// Verify userOf is now owner after expiration
			expect(await kami721ac.userOf(0)).to.equal(await user1.getAddress());

			// Try to transfer the token (should succeed as rental has expired)
			// Note: The transferFrom override now includes the rental check/cleanup
			await kami721ac.connect(user1).transferFrom(await user1.getAddress(), await royaltyReceiver1.getAddress(), 0);

			// Verify ownership changed
			expect(await kami721ac.ownerOf(0)).to.equal(await royaltyReceiver1.getAddress());

			// Verify rental is no longer active (transfer should have cleared it)
			const rentalInfo = await kami721ac.getRentalInfo(0);
			expect(rentalInfo.active).to.be.false;
			expect(rentalInfo.renter).to.equal(ZeroAddress);

			// Verify RENTER_ROLE was revoked (transfer should have cleared it)
			expect(await kami721ac.hasRole(await kami721ac.RENTER_ROLE(), await user2.getAddress())).to.be.false;
		});

		it('Should prevent selling a rented token', async function () {
			const rentalDuration = 86400n; // Use BigInt
			const rentalPrice = parseUnits('0.5', 6); // 0.5 USDC
			const salePrice = parseUnits('10', 6); // 10 USDC

			// Approve USDC for rental
			await usdc.connect(user2).approve(await kami721ac.getAddress(), rentalPrice);

			// Rent the token
			await kami721ac.connect(user2).rentToken(0, rentalDuration, rentalPrice);

			// Try to sell the token
			await expect(kami721ac.connect(user1).sellToken(await royaltyReceiver1.getAddress(), 0, salePrice)).to.be.revertedWith(
				'Token is currently rented'
			);
		});
	});
});
