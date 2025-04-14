import { ethers } from 'hardhat';

// ProxyAdmin ABI (partial, only needed functions)
const ProxyAdminABI = [
	'function upgrade(address proxy, address implementation) external',
	'function upgradeAndCall(address proxy, address implementation, bytes memory data) external',
];

async function main() {
	const proxyAddress = process.env.PROXY_CONTRACT_ADDRESS;
	const proxyAdminAddress = process.env.PROXY_ADMIN_ADDRESS;
	const [deployer] = await ethers.getSigners();

	if (!proxyAddress) {
		console.error('Proxy contract address not found in environment variables');
		process.exit(1);
	}

	console.log('Upgrading contract with the account:', deployer.address);

	// Replace 'KAMI721ACUpgradeableV2' with the name of your new implementation contract
	console.log('Deploying new implementation contract...');
	const KAMI721ACUpgradeableV2 = await ethers.getContractFactory('KAMI721ACUpgradeable'); // Assuming V2 has same name for now
	const newImplementation = await KAMI721ACUpgradeableV2.deploy();
	await newImplementation.waitForDeployment();
	const newImplementationAddress = await newImplementation.getAddress();
	console.log('New implementation deployed to:', newImplementationAddress);

	// Get the ProxyAdmin contract
	console.log(`Using ProxyAdmin at: ${proxyAdminAddress}`);
	const proxyAdmin = new ethers.Contract(proxyAdminAddress, ProxyAdminABI, deployer);

	// Upgrade the proxy to the new implementation
	const tx = await proxyAdmin.upgrade(proxyAddress, newImplementationAddress);
	await tx.wait();

	console.log('Proxy upgraded to new implementation successfully!');
	console.log('To interact with the upgraded contract, continue using the proxy address with the new ABI');
}

main().catch((error) => {
	console.error(error);
	process.exitCode = 1;
});
