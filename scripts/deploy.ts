import { ethers } from 'hardhat';
import * as dotenv from 'dotenv';

dotenv.config();

async function main() {
	const [deployer] = await ethers.getSigners();

	console.log('Deploying contracts with the account:', await deployer.getAddress());
	console.log('Account balance:', (await deployer.provider.getBalance(await deployer.getAddress())).toString());

	// Get network specific USDC address
	const network = await ethers.provider.getNetwork();
	let usdcAddress: string;

	if (network.name === 'mainnet' || network.chainId === 1n) {
		usdcAddress = process.env.MAINNET_USDC_ADDRESS || '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48';
	} else if (network.name === 'goerli' || network.chainId === 5n) {
		usdcAddress = process.env.GOERLI_USDC_ADDRESS || '0x07865c6E87B9F70255377e024ace6630C1Eaa37F';
	} else if (network.name === 'sepolia' || network.chainId === 11155111n) {
		usdcAddress = process.env.SEPOLIA_USDC_ADDRESS || '0x1c7d4b196cb0c7b01d743fbc6116a902379c7238';
	} else if (network.name === 'polygon' || network.chainId === 137n) {
		usdcAddress = process.env.POLYGON_USDC_ADDRESS || '0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174';
	} else if (network.name === 'mumbai' || network.chainId === 80001n) {
		usdcAddress = process.env.MUMBAI_USDC_ADDRESS || '0xe11A86849d99F524cAC3E7A0Ec1241828e332C62';
	} else if (network.name === 'hardhat' || network.name === 'localhost') {
		// For local development, deploy MockERC20 as USDC
		console.log('Deploying MockERC20 as USDC on local network...');
		const MockERC20 = await ethers.getContractFactory('MockERC20');
		const mockUsdc = await MockERC20.deploy('USD Coin', 'USDC', 6);
		await mockUsdc.waitForDeployment();
		usdcAddress = await mockUsdc.getAddress();
		console.log('MockERC20 (USDC) deployed to:', usdcAddress);
	} else {
		throw new Error(`Unsupported network: ${network.name}`);
	}

	// Get NFT configuration from environment variables
	const nftName = process.env.NFT_NAME || 'KAMI NFT Collection';
	const nftSymbol = process.env.NFT_SYMBOL || 'KAMI';
	const baseUri = process.env.BASE_URI || 'https://metadata-api.example.com/token/';
	const securityLevel = parseInt(process.env.SECURITY_LEVEL || '1');

	// Deploy CreatorTokenTransferValidator
	console.log('Deploying CreatorTokenTransferValidator...');
	const CreatorTokenTransferValidator = await ethers.getContractFactory('CreatorTokenTransferValidator');
	const validator = await CreatorTokenTransferValidator.deploy();
	await validator.waitForDeployment();
	const validatorAddress = await validator.getAddress();
	console.log('CreatorTokenTransferValidator deployed to:', validatorAddress);

	// Deploy KAMI721AC
	console.log(`Deploying KAMI721AC with USDC address: ${usdcAddress}...`);
	const KAMI721AC = await ethers.getContractFactory('KAMI721AC');
	const kami721ac = await KAMI721AC.deploy(usdcAddress, nftName, nftSymbol, baseUri);
	await kami721ac.waitForDeployment();
	const kami721acAddress = await kami721ac.getAddress();
	console.log('KAMI721AC deployed to:', kami721acAddress);

	// Configure the KAMI721AC contract with the transfer validator
	console.log('Setting up transfer validator for KAMI721AC...');
	const setValidatorTx = await kami721ac.setTransferValidator(validatorAddress);
	await setValidatorTx.wait();
	console.log('Transfer validator set for KAMI721AC');

	// Configure security policy for the KAMI721AC contract
	console.log(`Setting security policy (level ${securityLevel}) for KAMI721AC...`);
	const setSecurityPolicyTx = await validator.setCollectionSecurityPolicy(
		kami721acAddress,
		securityLevel,
		0, // Default operator whitelist ID
		0 // Default contract receivers allowlist ID
	);
	await setSecurityPolicyTx.wait();
	console.log('Security policy set for KAMI721AC');

	console.log('Deployment completed successfully!');
	console.log('-----------------------------------');
	console.log('Summary:');
	console.log(`CreatorTokenTransferValidator: ${validatorAddress}`);
	console.log(`KAMI721AC: ${kami721acAddress}`);
	console.log(`USDC: ${usdcAddress}`);
	console.log('-----------------------------------');
}

main()
	.then(() => process.exit(0))
	.catch((error) => {
		console.error(error);
		process.exit(1);
	});
