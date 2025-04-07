# KAMI721C Upgradeable Contract

This document explains how the KAMI721C contract has been made upgradeable using the transparent proxy pattern.

## Overview

The KAMI721C contract has been modified to support upgrades through the transparent proxy pattern. This allows the contract's logic to be upgraded while preserving its state and address.

The upgrade implementation uses:

-   OpenZeppelin's Transparent Proxy pattern
-   UUPS (Universal Upgradeable Proxy Standard) for the implementation contract
-   A separate ProxyAdmin contract for managing the proxy

## Contract Structure

The upgradeable system consists of three main components:

1. **KAMI721CUpgradeable.sol**: The implementation contract that contains the logic.
2. **KAMITransparentUpgradeableProxy.sol**: The proxy contract that users interact with.
3. **KAMIProxyAdmin.sol**: The admin contract that controls upgrades to the proxy.

## Deployment

To deploy the upgradeable contract system:

```bash
npx hardhat run scripts/deploy_upgradeable.ts --network [your-network]
```

Make sure to save the addresses of the deployed contracts:

-   Implementation contract
-   Proxy contract
-   Proxy admin contract

## Interacting with the Contract

When interacting with the contract, always use the proxy address with the implementation ABI. The proxy will delegate all calls to the implementation contract.

```bash
# Replace YOUR_PROXY_ADDRESS with the actual address
npx hardhat run scripts/interact.ts --network [your-network]
```

## Upgrading the Contract

To upgrade the contract:

1. Create a new implementation of `KAMI721CUpgradeable.sol` with your changes
2. Deploy the new implementation
3. Update the proxy to point to the new implementation

```bash
# Edit the script first to add your addresses
npx hardhat run scripts/upgrade.ts --network [your-network]
```

## Important Considerations

When upgrading the contract:

1. **Storage Layout**: Never change the order or type of existing storage variables in the contract. Always add new variables at the end.
2. **Initialization**: The upgradeable contract uses an `initialize` function instead of a constructor. This is called only once through the proxy when first deploying.
3. **Storage Gaps**: The contract includes a storage gap (`__gap`) to reserve space for future versions.
4. **Access Control**: Only addresses with the `UPGRADER_ROLE` can trigger upgrades.

## Best Practices

1. **Test thoroughly**: Before deploying an upgrade, test the new implementation thoroughly.
2. **Security review**: Consider having the upgrade reviewed for security vulnerabilities.
3. **Transparent governance**: Ensure the upgrade process is transparent to users.
4. **Backwards compatibility**: Maintain backwards compatibility when possible.

## Contract Differences

The main differences between the original KAMI721C and the upgradeable version:

1. Inheritance from upgradeable versions of OpenZeppelin contracts
2. Constructor replaced with an `initialize` function
3. Addition of the `UPGRADER_ROLE` for access control
4. Implementation of `_authorizeUpgrade` function for UUPS
5. Addition of a storage gap for future upgrades
