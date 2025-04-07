import { ethers } from 'hardhat';

async function main() {
	const [deployer] = await ethers.getSigners();
	console.log('Deploying contracts with the account:', deployer.address);

	// Deploy the implementation contract first
	const KAMI721CUpgradeable = await ethers.getContractFactory('KAMI721CUpgradeable');
	const implementation = await KAMI721CUpgradeable.deploy();
	await implementation.waitForDeployment();
	console.log('KAMI721CUpgradeable implementation deployed to:', await implementation.getAddress());

	// Deploy the proxy admin
	const KAMIProxyAdmin = await ethers.getContractFactory('KAMIProxyAdmin');
	const proxyAdmin = await KAMIProxyAdmin.deploy(deployer.address);
	await proxyAdmin.waitForDeployment();
	console.log('KAMIProxyAdmin deployed to:', await proxyAdmin.getAddress());

	// Prepare initialization data
	// Replace these parameters with your actual values
	const usdcAddress = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48'; // Mainnet USDC address - Replace with appropriate address
	const name = 'KAMI NFT';
	const symbol = 'KAMI';
	const baseTokenURI = 'https://api.kami.com/metadata/';
	const initialMintPrice = ethers.parseUnits('100', 6); // 100 USDC (assuming 6 decimals)
	const platformAddress = deployer.address; // Using deployer as platform for this example
	const platformCommissionPercentage = 500; // 5%

	// Encode the initialize function call
	const abiCoder = new ethers.AbiCoder();
	const initializeData = KAMI721CUpgradeable.interface.encodeFunctionData('initialize', [
		usdcAddress,
		name,
		symbol,
		baseTokenURI,
		initialMintPrice,
		platformAddress,
		platformCommissionPercentage,
	]);

	// Deploy the transparent upgradeable proxy
	const KAMITransparentUpgradeableProxy = await ethers.getContractFactory('KAMITransparentUpgradeableProxy');
	const proxy = await KAMITransparentUpgradeableProxy.deploy(
		await implementation.getAddress(),
		await proxyAdmin.getAddress(),
		initializeData
	);
	await proxy.waitForDeployment();
	console.log('KAMITransparentUpgradeableProxy deployed to:', await proxy.getAddress());

	console.log('Proxy deployment completed. The contract is now upgradeable.');
	console.log('To interact with the contract, use the proxy address with the KAMI721CUpgradeable ABI.');
}

main().catch((error) => {
	console.error(error);
	process.exitCode = 1;
});
