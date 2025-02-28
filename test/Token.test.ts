import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Token } from '../typechain-types';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';

describe('Token', function () {
	let token: Token;
	let owner: SignerWithAddress;
	let addr1: SignerWithAddress;
	let addr2: SignerWithAddress;

	beforeEach(async function () {
		[owner, addr1, addr2] = await ethers.getSigners();

		const Token = await ethers.getContractFactory('Token');
		token = (await Token.deploy('Test Token', 'TEST', 1000)) as Token;
		await token.waitForDeployment();
	});

	describe('Deployment', function () {
		it('Should set the right owner', async function () {
			expect(await token.owner()).to.equal(await owner.getAddress());
		});

		it('Should assign the total supply of tokens to the owner', async function () {
			const ownerBalance = await token.balanceOf(await owner.getAddress());
			expect(await token.totalSupply()).to.equal(ownerBalance);
		});
	});

	describe('Transactions', function () {
		it('Should transfer tokens between accounts', async function () {
			// Transfer 50 tokens from owner to addr1
			await token.transfer(await addr1.getAddress(), 50);
			expect(await token.balanceOf(await addr1.getAddress())).to.equal(50);

			// Transfer 50 tokens from addr1 to addr2
			await token.connect(addr1).transfer(await addr2.getAddress(), 50);
			expect(await token.balanceOf(await addr2.getAddress())).to.equal(50);
		});

		it("Should fail if sender doesn't have enough tokens", async function () {
			const initialOwnerBalance = await token.balanceOf(await owner.getAddress());
			await expect(token.connect(addr1).transfer(await owner.getAddress(), 1)).to.be.revertedWithCustomError(
				token,
				'ERC20InsufficientBalance'
			);

			expect(await token.balanceOf(await owner.getAddress())).to.equal(initialOwnerBalance);
		});
	});

	describe('Minting', function () {
		it('Should allow owner to mint new tokens', async function () {
			await token.mint(await addr1.getAddress(), 100);
			expect(await token.balanceOf(await addr1.getAddress())).to.equal(100);
		});

		it('Should not allow non-owner to mint tokens', async function () {
			await expect(token.connect(addr1).mint(await addr2.getAddress(), 100)).to.be.revertedWithCustomError(
				token,
				'OwnableUnauthorizedAccount'
			);
		});
	});
});
