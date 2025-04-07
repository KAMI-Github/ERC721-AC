import { ethers } from 'hardhat';

// ProxyAdmin ABI (partial, only needed functions)
const ProxyAdminABI = [
	'function upgrade(address proxy, address implementation) external',
	'function upgradeAndCall(address proxy, address implementation, bytes memory data) external',
];

async function main() {
	const [deployer] = await ethers.getSigners();
	console.log('Upgrading contract with the account:', deployer.address);

	// You need to specify these addresses after the initial deployment
	const proxyAddress = 'YOUR_PROXY_ADDRESS'; // Replace with your actual proxy address
	const proxyAdminAddress = 'YOUR_PROXY_ADMIN_ADDRESS'; // Replace with your actual proxy admin address

	// Deploy the new implementation contract
	const KAMI721CUpgradeableV2 = await ethers.getContractFactory('KAMI721CUpgradeable'); // If you rename your upgraded contract, change this
	const newImplementation = await KAMI721CUpgradeableV2.deploy();
	await newImplementation.waitForDeployment();
	console.log('New implementation deployed to:', await newImplementation.getAddress());

	// Connect to the proxy admin using its ABI
	const proxyAdmin = new ethers.Contract(proxyAdminAddress, ProxyAdminABI, deployer);

	// Upgrade the proxy to the new implementation
	const tx = await proxyAdmin.upgrade(proxyAddress, await newImplementation.getAddress());
	await tx.wait();

	console.log('Proxy upgraded to new implementation successfully!');
	console.log('To interact with the upgraded contract, continue using the proxy address with the new ABI');
}

main().catch((error) => {
	console.error(error);
	process.exitCode = 1;
});
