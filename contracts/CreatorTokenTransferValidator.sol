// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title CreatorTokenTransferValidator
 * @dev Simplified implementation of the Limit Break CreatorTokenTransferValidator
 * This provides the essential security features for ERC721C tokens
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

// Security constants mirroring Limit Break's implementation
uint256 constant CALLER_CONSTRAINTS_NONE = 0;
uint256 constant CALLER_CONSTRAINTS_OPERATOR_BLACKLIST_ENABLE_OTC = 1;
uint256 constant CALLER_CONSTRAINTS_OPERATOR_WHITELIST_ENABLE_OTC = 2;
uint256 constant CALLER_CONSTRAINTS_OPERATOR_WHITELIST_DISABLE_OTC = 3;

uint256 constant RECEIVER_CONSTRAINTS_NONE = 0;
uint256 constant RECEIVER_CONSTRAINTS_NO_CODE = 1;
uint256 constant RECEIVER_CONSTRAINTS_EOA = 2;
uint256 constant RECEIVER_CONSTRAINTS_VERIFIED = 3;
uint256 constant RECEIVER_CONSTRAINTS_ALLOWLIST = 4;

// Security levels
uint8 constant TRANSFER_SECURITY_LEVEL_RECOMMENDED = 0;
uint8 constant TRANSFER_SECURITY_LEVEL_ONE = 1;
uint8 constant TRANSFER_SECURITY_LEVEL_TWO = 2;
uint8 constant TRANSFER_SECURITY_LEVEL_THREE = 3;
uint8 constant TRANSFER_SECURITY_LEVEL_FOUR = 4;
uint8 constant TRANSFER_SECURITY_LEVEL_FIVE = 5;
uint8 constant TRANSFER_SECURITY_LEVEL_SIX = 6;
uint8 constant TRANSFER_SECURITY_LEVEL_SEVEN = 7;
uint8 constant TRANSFER_SECURITY_LEVEL_EIGHT = 8;

contract CreatorTokenTransferValidator is ITransferValidator, ERC165, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    
    struct SecurityPolicy {
        uint8 securityLevel;
        uint32 operatorWhitelistId;
        uint32 contractReceiversAllowlistId;
        bool isPaused;
    }
    
    // Collection security policies
    mapping(address => SecurityPolicy) private _collectionPolicies;
    
    // Whitelist tracking (listId => addresses)
    mapping(uint32 => EnumerableSet.AddressSet) private _operatorWhitelists;
    mapping(uint32 => EnumerableSet.AddressSet) private _contractReceiversAllowlists;
    
    // List tracking
    uint32 private _listCounter;
    mapping(uint32 => string) private _listNames;
    mapping(uint32 => address) private _listOwners;
    
    // Collection blacklists and whitelists for operators
    mapping(address => EnumerableSet.AddressSet) private _operatorBlacklists;
    
    // Pre-defined security policies (security level => (caller constraints, receiver constraints))
    mapping(uint8 => SecurityPolicyConfig) private _securityPolicies;
    
    struct SecurityPolicyConfig {
        uint256 callerConstraints;
        uint256 receiverConstraints;
    }
    
    // Events
    event CollectionSecurityPolicySet(
        address indexed collection,
        uint8 securityLevel,
        uint32 operatorWhitelistId,
        uint32 contractReceiversAllowlistId
    );
    
    event AddedToList(uint32 indexed listId, address indexed entry);
    event RemovedFromList(uint32 indexed listId, address indexed entry);
    event CreatedList(uint32 indexed listId, string name);
    event ReassignedListOwnership(uint32 indexed listId, address indexed newOwner);
    
    /**
     * @dev Constructor for CreatorTokenTransferValidator
     */
    constructor() {
        _transferOwnership(msg.sender);
        
        // Initialize default security policies
        _securityPolicies[TRANSFER_SECURITY_LEVEL_RECOMMENDED] = SecurityPolicyConfig(
            CALLER_CONSTRAINTS_OPERATOR_WHITELIST_ENABLE_OTC,
            RECEIVER_CONSTRAINTS_NONE
        );
        
        _securityPolicies[TRANSFER_SECURITY_LEVEL_ONE] = SecurityPolicyConfig(
            CALLER_CONSTRAINTS_NONE,
            RECEIVER_CONSTRAINTS_NONE
        );
        
        _securityPolicies[TRANSFER_SECURITY_LEVEL_TWO] = SecurityPolicyConfig(
            CALLER_CONSTRAINTS_OPERATOR_BLACKLIST_ENABLE_OTC,
            RECEIVER_CONSTRAINTS_NONE
        );
        
        _securityPolicies[TRANSFER_SECURITY_LEVEL_THREE] = SecurityPolicyConfig(
            CALLER_CONSTRAINTS_OPERATOR_WHITELIST_ENABLE_OTC,
            RECEIVER_CONSTRAINTS_NONE
        );
        
        _securityPolicies[TRANSFER_SECURITY_LEVEL_FOUR] = SecurityPolicyConfig(
            CALLER_CONSTRAINTS_OPERATOR_WHITELIST_DISABLE_OTC,
            RECEIVER_CONSTRAINTS_NONE
        );
        
        _securityPolicies[TRANSFER_SECURITY_LEVEL_FIVE] = SecurityPolicyConfig(
            CALLER_CONSTRAINTS_OPERATOR_WHITELIST_ENABLE_OTC,
            RECEIVER_CONSTRAINTS_NO_CODE
        );
        
        _securityPolicies[TRANSFER_SECURITY_LEVEL_SIX] = SecurityPolicyConfig(
            CALLER_CONSTRAINTS_OPERATOR_WHITELIST_ENABLE_OTC,
            RECEIVER_CONSTRAINTS_EOA
        );
        
        _securityPolicies[TRANSFER_SECURITY_LEVEL_SEVEN] = SecurityPolicyConfig(
            CALLER_CONSTRAINTS_OPERATOR_WHITELIST_DISABLE_OTC,
            RECEIVER_CONSTRAINTS_NO_CODE
        );
        
        _securityPolicies[TRANSFER_SECURITY_LEVEL_EIGHT] = SecurityPolicyConfig(
            CALLER_CONSTRAINTS_OPERATOR_WHITELIST_DISABLE_OTC,
            RECEIVER_CONSTRAINTS_EOA
        );
        
        // Create default whitelist (list ID 0)
        _createList("DEFAULT LIST");
    }
    
    /**
     * @dev Creates a new list
     */
    function _createList(string memory name) internal returns (uint32) {
        uint32 listId = _listCounter++;
        _listNames[listId] = name;
        _listOwners[listId] = msg.sender;
        
        emit CreatedList(listId, name);
        emit ReassignedListOwnership(listId, msg.sender);
        
        return listId;
    }
    
    /**
     * @dev Public method to create a new whitelist
     */
    function createList(string calldata name) external returns (uint32) {
        return _createList(name);
    }
    
    /**
     * @dev Set a collection's security policy
     */
    function setCollectionSecurityPolicy(
        address collection,
        uint8 securityLevel,
        uint32 operatorWhitelistId,
        uint32 contractReceiversAllowlistId
    ) external {
        require(
            securityLevel <= TRANSFER_SECURITY_LEVEL_EIGHT,
            "Invalid security level"
        );
        
        _collectionPolicies[collection] = SecurityPolicy({
            securityLevel: securityLevel,
            operatorWhitelistId: operatorWhitelistId,
            contractReceiversAllowlistId: contractReceiversAllowlistId,
            isPaused: false
        });
        
        emit CollectionSecurityPolicySet(
            collection,
            securityLevel,
            operatorWhitelistId,
            contractReceiversAllowlistId
        );
    }
    
    /**
     * @dev Add an address to a whitelist
     */
    function addToList(uint32 listId, address entry) external {
        require(_listOwners[listId] == msg.sender || owner() == msg.sender, "Not list owner");
        
        if (_operatorWhitelists[listId].add(entry)) {
            emit AddedToList(listId, entry);
        }
    }
    
    /**
     * @dev Remove an address from a whitelist
     */
    function removeFromList(uint32 listId, address entry) external {
        require(_listOwners[listId] == msg.sender || owner() == msg.sender, "Not list owner");
        
        if (_operatorWhitelists[listId].remove(entry)) {
            emit RemovedFromList(listId, entry);
        }
    }
    
    /**
     * @dev Adds an operator to a collection's blacklist
     */
    function addOperatorToCollectionBlacklist(address collection, address operator) external {
        // In a real implementation, we would check that the caller owns the collection
        // For simplicity, we allow anyone to call this method for testing purposes
        _operatorBlacklists[collection].add(operator);
    }
    
    /**
     * @dev Get the security policy for a given security level
     */
    function transferSecurityPolicies(uint8 securityLevel) 
        external 
        view 
        returns (uint256 callerConstraints, uint256 receiverConstraints) 
    {
        SecurityPolicyConfig memory policy = _securityPolicies[securityLevel];
        return (policy.callerConstraints, policy.receiverConstraints);
    }
    
    /**
     * @dev Check if an address is in a whitelist
     */
    function isOperatorWhitelisted(uint32 listId, address operator) external view returns (bool) {
        return _operatorWhitelists[listId].contains(operator);
    }
    
    /**
     * @dev Check if an address is in a contract receivers allowlist
     */
    function isContractReceiverAllowed(uint32 listId, address receiver) external view returns (bool) {
        return _contractReceiversAllowlists[listId].contains(receiver);
    }
    
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return 
            interfaceId == type(ITransferValidator).interfaceId || 
            super.supportsInterface(interfaceId);
    }
    
    /**
     * @dev Implementation of applyCollectionTransferPolicy
     */
    function applyCollectionTransferPolicy(address caller, address from, address to) external view override {
        _validateTransferWithPolicy(msg.sender, caller, from, to);
    }
    
    /**
     * @dev Implementation of validateTransfer
     */
    function validateTransfer(address caller, address from, address to) external view override {
        _validateTransferWithPolicy(msg.sender, caller, from, to);
    }
    
    /**
     * @dev Implementation of validateTransfer with tokenId
     */
    function validateTransfer(address caller, address from, address to, uint256 /* tokenId */) external view override {
        _validateTransferWithPolicy(msg.sender, caller, from, to);
    }
    
    /**
     * @dev Implementation of validateTransfer with amount
     */
    function validateTransfer(address caller, address from, address to, uint256 /* tokenId */, uint256 /* amount */) external view override {
        _validateTransferWithPolicy(msg.sender, caller, from, to);
    }
    
    /**
     * @dev Core validation function
     */
    function _validateTransferWithPolicy(address collection, address caller, address from, address to) internal view {
        // Get the collection's security policy
        SecurityPolicy storage policy = _collectionPolicies[collection];
        
        // Revert if transfers are paused
        require(!policy.isPaused, "Transfers are paused");
        
        // Get the security constraints for this security level
        SecurityPolicyConfig memory securityConfig = _securityPolicies[policy.securityLevel];
        
        // Apply caller constraints
        _applyCaller(collection, caller, from, securityConfig.callerConstraints, policy.operatorWhitelistId);
        
        // Apply receiver constraints
        _applyReceiver(to, securityConfig.receiverConstraints, policy.contractReceiversAllowlistId);
    }
    
    /**
     * @dev Apply caller constraints
     */
    function _applyCaller(
        address collection, 
        address caller, 
        address from, 
        uint256 callerConstraints, 
        uint32 operatorWhitelistId
    ) internal view {
        // Skip checks if called by the token owner
        if (caller == from) return;
        
        if (callerConstraints == CALLER_CONSTRAINTS_OPERATOR_BLACKLIST_ENABLE_OTC) {
            // Revert if operator is blacklisted
            require(!_operatorBlacklists[collection].contains(caller), "Operator blacklisted");
        } else if (callerConstraints == CALLER_CONSTRAINTS_OPERATOR_WHITELIST_ENABLE_OTC) {
            // Revert if operator is not whitelisted
            require(_operatorWhitelists[operatorWhitelistId].contains(caller), "Operator not whitelisted");
        } else if (callerConstraints == CALLER_CONSTRAINTS_OPERATOR_WHITELIST_DISABLE_OTC) {
            // Strictest policy - operator must be whitelisted, no exceptions
            require(_operatorWhitelists[operatorWhitelistId].contains(caller), "Operator not whitelisted");
        }
    }
    
    /**
     * @dev Apply receiver constraints
     */
    function _applyReceiver(
        address to, 
        uint256 receiverConstraints, 
        uint32 contractReceiversAllowlistId
    ) internal view {
        if (receiverConstraints == RECEIVER_CONSTRAINTS_NO_CODE) {
            // Target must not have code (either EOA or non-existent address)
            require(to.code.length == 0, "Receiver must not be a contract");
        } else if (receiverConstraints == RECEIVER_CONSTRAINTS_EOA) {
            // More strict check (must be an EOA)
            require(to.code.length == 0, "Receiver must be an EOA");
            require(to != address(0), "Receiver cannot be zero address");
        } else if (receiverConstraints == RECEIVER_CONSTRAINTS_ALLOWLIST) {
            // If the receiver is a contract, it must be allowlisted
            if (to.code.length > 0) {
                require(_contractReceiversAllowlists[contractReceiversAllowlistId].contains(to), "Contract receiver not allowed");
            }
        }
    }
    
    /**
     * @dev Pause transfers for a collection
     */
    function pauseTransfers(address collection) external onlyOwner {
        _collectionPolicies[collection].isPaused = true;
    }
    
    /**
     * @dev Unpause transfers for a collection
     */
    function unpauseTransfers(address collection) external onlyOwner {
        _collectionPolicies[collection].isPaused = false;
    }
    
    /**
     * @dev Mock implementations of authorization callbacks
     * In a full implementation, these would track and authorize transfers
     */
    function beforeAuthorizedTransfer(address operator, address token, uint256 tokenId) external override {}
    function afterAuthorizedTransfer(address token, uint256 tokenId) external override {}
    function beforeAuthorizedTransfer(address operator, address token) external override {}
    function afterAuthorizedTransfer(address token) external override {}
    function beforeAuthorizedTransfer(address token, uint256 tokenId) external override {}
    function beforeAuthorizedTransferWithAmount(address token, uint256 tokenId, uint256 amount) external override {}
    function afterAuthorizedTransferWithAmount(address token, uint256 tokenId) external override {}
} 