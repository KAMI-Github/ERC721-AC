// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title MockTransferValidator
 * @dev Simple mock implementation of ITransferValidator for testing purposes
 * This implementation allows all transfers without validation
 */
interface ITransferValidator {
    function applyCollectionTransferPolicy(address caller, address from, address to) external view;
    function validateTransfer(address caller, address from, address to) external view;
    function validateTransfer(address caller, address from, address to, uint256 tokenId) external view;
    function validateTransfer(address caller, address from, address to, uint256 tokenId, uint256 amount) external;

    function beforeAuthorizedTransfer(address operator, address token, uint256 tokenId) external;
    function afterAuthorizedTransfer(address token, uint256 tokenId) external;
    function beforeAuthorizedTransfer(address operator, address token) external;
    function afterAuthorizedTransfer(address token) external;
    function beforeAuthorizedTransfer(address token, uint256 tokenId) external;
    function beforeAuthorizedTransferWithAmount(address token, uint256 tokenId, uint256 amount) external;
    function afterAuthorizedTransferWithAmount(address token, uint256 tokenId) external;
}

contract MockTransferValidator is ITransferValidator, ERC165 {
    // Track collections and their security policies
    mapping(address => uint8) private _collectionSecurityLevels;
    mapping(address => uint32) private _collectionOperatorWhitelists;
    mapping(address => uint32) private _collectionContractAllowlists;
    
    // Whitelist for collections to use
    mapping(uint32 => mapping(address => bool)) private _operatorWhitelists;
    
    /**
     * @dev Constructor for MockTransferValidator
     */
    constructor() {}
    
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return 
            interfaceId == type(ITransferValidator).interfaceId || 
            super.supportsInterface(interfaceId);
    }
    
    /**
     * @dev Sets the security level and whitelist IDs for a collection
     */
    function setCollectionSecurityPolicy(
        address collection,
        uint8 securityLevel,
        uint32 operatorWhitelistId,
        uint32 contractAllowlistId
    ) external {
        _collectionSecurityLevels[collection] = securityLevel;
        _collectionOperatorWhitelists[collection] = operatorWhitelistId;
        _collectionContractAllowlists[collection] = contractAllowlistId;
    }
    
    /**
     * @dev Adds an operator to a whitelist
     */
    function addOperatorToWhitelist(uint32 whitelistId, address operator) external {
        _operatorWhitelists[whitelistId][operator] = true;
    }
    
    /**
     * @dev Implementation of applyCollectionTransferPolicy - always allows transfers
     */
    function applyCollectionTransferPolicy(address caller, address from, address to) external view override {}
    
    /**
     * @dev Implementation of validateTransfer - always allows transfers
     */
    function validateTransfer(address caller, address from, address to) external view override {}
    
    /**
     * @dev Implementation of validateTransfer with tokenId - always allows transfers
     */
    function validateTransfer(address caller, address from, address to, uint256 tokenId) external view override {}
    
    /**
     * @dev Implementation of validateTransfer with amount - always allows transfers
     */
    function validateTransfer(address caller, address from, address to, uint256 tokenId, uint256 amount) external override {}
    
    /**
     * @dev Mock implementations of authorization callbacks
     */
    function beforeAuthorizedTransfer(address operator, address token, uint256 tokenId) external override {}
    function afterAuthorizedTransfer(address token, uint256 tokenId) external override {}
    function beforeAuthorizedTransfer(address operator, address token) external override {}
    function afterAuthorizedTransfer(address token) external override {}
    function beforeAuthorizedTransfer(address token, uint256 tokenId) external override {}
    function beforeAuthorizedTransferWithAmount(address token, uint256 tokenId, uint256 amount) external override {}
    function afterAuthorizedTransferWithAmount(address token, uint256 tokenId) external override {}
} 