import { ethers } from 'hardhat';
import * as fs from 'fs';
import * as path from 'path';

async function main() {
	const [user] = await ethers.getSigners();
	console.log('Interacting with the contract using account:', user.address);

	// This is the proxy address, not the implementation address
	const proxyAddress = 'YOUR_PROXY_ADDRESS'; // Replace with your actual proxy address

	// Load the contract ABI from the compiled artifacts
	const artifactPath = path.join(__dirname, '../artifacts/contracts/KAMI721ACUpgradeable.sol/KAMI721ACUpgradeable.json');
	if (!fs.existsSync(artifactPath)) {
		console.error(`Artifact not found at ${artifactPath}. Make sure contracts are compiled.`);
		process.exit(1);
	}
	const contractJson = JSON.parse(fs.readFileSync(artifactPath, 'utf8'));
	const contractAbi = contractJson.abi;

	// Connect to the proxy with the implementation ABI
	const contract = new ethers.Contract(proxyAddress, contractAbi, user);

	// Example: Get current mint price
	const mintPrice = await contract.mintPrice();
	console.log('Current mint price:', ethers.formatUnits(mintPrice, 6), 'USDC'); // Assuming 6 decimals for USDC

	// Example: Check if user has the OWNER_ROLE
	const OWNER_ROLE = await contract.OWNER_ROLE();
	const isOwner = await contract.hasRole(OWNER_ROLE, user.address);
	console.log('Is user an owner:', isOwner);

	// You can add more interactions here...

	// Example: Change mint price (only if user is owner)
	if (isOwner) {
		console.log('Setting new mint price...');
		const newMintPrice = ethers.parseUnits('150', 6); // 150 USDC
		const tx = await contract.setMintPrice(newMintPrice);
		await tx.wait();

		const updatedMintPrice = await contract.mintPrice();
		console.log('Updated mint price:', ethers.formatUnits(updatedMintPrice, 6), 'USDC');
	}
}

main().catch((error) => {
	console.error(error);
	process.exitCode = 1;
});
