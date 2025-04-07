// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/**
 * @dev This is a ProxyAdmin used for managing proxies.
 */
contract KAMIProxyAdmin is ProxyAdmin {
    constructor(address owner) ProxyAdmin() {
        _transferOwnership(owner);
    }
} 