import { expect } from 'chai';
import { ethers } from 'hardhat';
import { GameNFT } from '../typechain-types';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';

describe('GameNFT', function () {
	let gameNFT: GameNFT;
	let owner: SignerWithAddress;
	let addr1: SignerWithAddress;
	let addr2: SignerWithAddress;
	const MINT_PRICE = ethers.parseEther('0.1');
	const ROYALTY_FEE = 1000; // 10% royalty

	beforeEach(async function () {
		[owner, addr1, addr2] = await ethers.getSigners();

		const GameNFT = await ethers.getContractFactory('GameNFT');
		gameNFT = (await GameNFT.deploy(ROYALTY_FEE, 'Game NFT', 'GNFT', 'https://api.example.com/token/')) as GameNFT;
		await gameNFT.waitForDeployment();
	});

	describe('Deployment', function () {
		it('Should set the right owner', async function () {
			expect(await gameNFT.owner()).to.equal(await owner.getAddress());
		});

		it('Should set the correct name and symbol', async function () {
			expect(await gameNFT.name()).to.equal('Game NFT');
			expect(await gameNFT.symbol()).to.equal('GNFT');
		});
	});

	describe('Minting', function () {
		it('Should allow minting with correct payment', async function () {
			await gameNFT.connect(addr1).mint({ value: MINT_PRICE });
			expect(await gameNFT.ownerOf(0)).to.equal(await addr1.getAddress());
		});

		it('Should fail minting with insufficient payment', async function () {
			await expect(gameNFT.connect(addr1).mint({ value: ethers.parseEther('0.05') })).to.be.revertedWith('Insufficient payment');
		});
	});

	describe('Royalties', function () {
		it('Should return correct royalty info', async function () {
			await gameNFT.connect(addr1).mint({ value: MINT_PRICE });
			const salePrice = ethers.parseEther('1.0');
			const [receiver, royaltyAmount] = await gameNFT.royaltyInfo(0, salePrice);

			expect(receiver).to.equal(await addr1.getAddress());
			expect(royaltyAmount).to.equal((salePrice * BigInt(ROYALTY_FEE)) / BigInt(10000));
		});
	});

	describe('Token URI', function () {
		it('Should return correct token URI', async function () {
			await gameNFT.connect(addr1).mint({ value: MINT_PRICE });
			expect(await gameNFT.tokenURI(0)).to.equal('https://api.example.com/token/0');
		});

		it('Should allow owner to update base URI', async function () {
			const newBaseURI = 'https://new.example.com/token/';
			await gameNFT.connect(owner).setBaseURI(newBaseURI);
			await gameNFT.connect(addr1).mint({ value: MINT_PRICE });
			expect(await gameNFT.tokenURI(0)).to.equal(newBaseURI + '0');
		});
	});

	describe('Burning', function () {
		beforeEach(async function () {
			await gameNFT.connect(addr1).mint({ value: MINT_PRICE });
		});

		it('Should allow token owner to burn', async function () {
			await gameNFT.connect(addr1).burn(0);
			await expect(gameNFT.ownerOf(0)).to.be.revertedWithCustomError(gameNFT, 'ERC721NonexistentToken');
		});

		it('Should not allow non-owner to burn', async function () {
			await expect(gameNFT.connect(addr2).burn(0)).to.be.revertedWith('Not token owner');
		});
	});
});
