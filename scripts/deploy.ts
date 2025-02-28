import { ethers } from 'hardhat';

async function main() {
	const [deployer] = await ethers.getSigners();

	console.log('Deploying contracts with the account:', await deployer.getAddress());
	console.log('Account balance:', (await deployer.provider.getBalance(await deployer.getAddress())).toString());

	const token = await ethers.deployContract('Token', ['My Token', 'MTK', 1000000]);
	await token.waitForDeployment();

	console.log('Token address:', await token.getAddress());
}

main()
	.then(() => process.exit(0))
	.catch((error) => {
		console.error(error);
		process.exit(1);
	});
