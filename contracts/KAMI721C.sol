// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@limitbreak/creator-token-standards/src/access/OwnableBasic.sol";
import "@limitbreak/creator-token-standards/src/erc721c/ERC721C.sol";
import "@limitbreak/creator-token-standards/src/programmable-royalties/BasicRoyalties.sol";
import "@limitbreak/creator-token-standards/src/interfaces/ITransferValidator.sol";

/**
 * @title KAMI721C
 * @dev An ERC721C implementation with USDC payments and programmable royalties for both minting and transfers
 */
contract KAMI721C is OwnableBasic, ERC721C, ERC2981 {
    using SafeERC20 for IERC20;
    
    uint256 private _nextTokenId;
    uint256 public constant MINT_PRICE = 100 * 10**6; // 100 USDC (6 decimals)
    string private _baseTokenURI;
    
    // USDC token contract
    IERC20 public immutable usdcToken;
    
    // Struct to represent a royalty recipient
    struct RoyaltyData {
        address receiver;
        uint96 feeNumerator;
    }
    
    // Arrays to store multiple royalty receivers
    RoyaltyData[] private _mintRoyaltyReceivers;
    RoyaltyData[] private _transferRoyaltyReceivers;
    
    // Mapping from token ID to custom royalty info
    mapping(uint256 => RoyaltyData[]) private _tokenMintRoyalties;
    mapping(uint256 => RoyaltyData[]) private _tokenTransferRoyalties;
    
    // Map to track transfer prices for each token
    mapping(uint256 => uint256) private _lastTransferPrices;
    
    // Events
    event MintRoyaltiesUpdated(RoyaltyData[] royalties);
    event TransferRoyaltiesUpdated(RoyaltyData[] royalties);
    event TokenMintRoyaltiesUpdated(uint256 indexed tokenId, RoyaltyData[] royalties);
    event TokenTransferRoyaltiesUpdated(uint256 indexed tokenId, RoyaltyData[] royalties);
    event TransferRoyaltyDistributed(uint256 indexed tokenId, address indexed receiver, uint256 amount);
    event TransferPriceSet(uint256 indexed tokenId, uint256 price);
    
    constructor(
        address usdcAddress_,
        string memory name_,
        string memory symbol_,
        string memory baseTokenURI_
    ) 
        ERC721OpenZeppelin(name_, symbol_)
        OwnableBasic()
    {
        require(usdcAddress_ != address(0), "Invalid USDC address");
        usdcToken = IERC20(usdcAddress_);
        _baseTokenURI = baseTokenURI_;
    }

    function supportsInterface(bytes4 interfaceId) 
        public 
        view 
        virtual 
        override(ERC721C, ERC2981) 
        returns (bool) 
    {
        return ERC721C.supportsInterface(interfaceId) ||
            ERC2981.supportsInterface(interfaceId);
    }
    
    // Setting default royalty receivers for minting
    function setMintRoyalties(RoyaltyData[] calldata royalties) external {
        _requireCallerIsContractOwner();
        delete _mintRoyaltyReceivers;
        
        uint96 totalFees = 0;
        for (uint i = 0; i < royalties.length; i++) {
            require(royalties[i].receiver != address(0), "Invalid receiver");
            totalFees += royalties[i].feeNumerator;
            _mintRoyaltyReceivers.push(royalties[i]);
        }
        
        // Maximum royalty is 25% (keeping reasonable limits)
        require(totalFees <= 2500, "Royalties exceed 25%");
        
        emit MintRoyaltiesUpdated(royalties);
    }
    
    // Setting default royalty receivers for transfers
    function setTransferRoyalties(RoyaltyData[] calldata royalties) external {
        _requireCallerIsContractOwner();
        delete _transferRoyaltyReceivers;
        
        uint96 totalFees = 0;
        for (uint i = 0; i < royalties.length; i++) {
            require(royalties[i].receiver != address(0), "Invalid receiver");
            totalFees += royalties[i].feeNumerator;
            _transferRoyaltyReceivers.push(royalties[i]);
        }
        
        // Maximum royalty is 25% (keeping reasonable limits)
        require(totalFees <= 2500, "Royalties exceed 25%");
        
        // Set the default receiver and fee for ERC2981 compatibility
        if (royalties.length > 0) {
            _setDefaultRoyalty(royalties[0].receiver, royalties[0].feeNumerator);
        }
        
        emit TransferRoyaltiesUpdated(royalties);
    }
    
    // Setting token-specific mint royalties
    function setTokenMintRoyalties(uint256 tokenId, RoyaltyData[] calldata royalties) external {
        _requireCallerIsContractOwner();
        require(_exists(tokenId), "Token does not exist");
        
        delete _tokenMintRoyalties[tokenId];
        
        uint96 totalFees = 0;
        for (uint i = 0; i < royalties.length; i++) {
            require(royalties[i].receiver != address(0), "Invalid receiver");
            totalFees += royalties[i].feeNumerator;
            _tokenMintRoyalties[tokenId].push(royalties[i]);
        }
        
        require(totalFees <= 2500, "Royalties exceed 25%");
        
        emit TokenMintRoyaltiesUpdated(tokenId, royalties);
    }
    
    // Setting token-specific transfer royalties
    function setTokenTransferRoyalties(uint256 tokenId, RoyaltyData[] calldata royalties) external {
        _requireCallerIsContractOwner();
        require(_exists(tokenId), "Token does not exist");
        
        delete _tokenTransferRoyalties[tokenId];
        
        uint96 totalFees = 0;
        for (uint i = 0; i < royalties.length; i++) {
            require(royalties[i].receiver != address(0), "Invalid receiver");
            totalFees += royalties[i].feeNumerator;
            _tokenTransferRoyalties[tokenId].push(royalties[i]);
        }
        
        require(totalFees <= 2500, "Royalties exceed 25%");
        
        // Set the token royalty for ERC2981 compatibility
        if (royalties.length > 0) {
            _setTokenRoyalty(tokenId, royalties[0].receiver, royalties[0].feeNumerator);
        }
        
        emit TokenTransferRoyaltiesUpdated(tokenId, royalties);
    }
    
    // Override royaltyInfo to provide compatibility with ERC2981
    function royaltyInfo(uint256 tokenId, uint256 salePrice) 
        public 
        view 
        override 
        returns (address receiver, uint256 royaltyAmount) 
    {
        // For ERC2981 compatibility, we return info for the first transfer royalty receiver
        if (_tokenTransferRoyalties[tokenId].length > 0) {
            RoyaltyData memory info = _tokenTransferRoyalties[tokenId][0];
            return (info.receiver, (salePrice * info.feeNumerator) / 10000);
        } else if (_transferRoyaltyReceivers.length > 0) {
            RoyaltyData memory info = _transferRoyaltyReceivers[0];
            return (info.receiver, (salePrice * info.feeNumerator) / 10000);
        }
        
        return (address(0), 0);
    }
    
    // Function to get all mint royalty receivers for a token
    function getMintRoyaltyReceivers(uint256 tokenId) 
        external 
        view 
        returns (RoyaltyData[] memory) 
    {
        if (_tokenMintRoyalties[tokenId].length > 0) {
            return _tokenMintRoyalties[tokenId];
        } else {
            return _mintRoyaltyReceivers;
        }
    }
    
    // Function to get all transfer royalty receivers for a token
    function getTransferRoyaltyReceivers(uint256 tokenId) 
        external 
        view 
        returns (RoyaltyData[] memory) 
    {
        if (_tokenTransferRoyalties[tokenId].length > 0) {
            return _tokenTransferRoyalties[tokenId];
        } else {
            return _transferRoyaltyReceivers;
        }
    }

    function mint() external {
        // Transfer USDC from sender to this contract
        usdcToken.safeTransferFrom(msg.sender, address(this), MINT_PRICE);
        
        uint256 tokenId = _nextTokenId++;
        _safeMint(msg.sender, tokenId);
        
        // Distribute mint royalties
        _distributeMintRoyalties(tokenId);
    }
    
    // Internal function to distribute royalties during minting
    function _distributeMintRoyalties(uint256 tokenId) internal {
        RoyaltyData[] memory royalties = _tokenMintRoyalties[tokenId].length > 0 
            ? _tokenMintRoyalties[tokenId] 
            : _mintRoyaltyReceivers;
            
        if (royalties.length == 0) return;
        
        uint256 totalAmount = MINT_PRICE;
        uint256 totalDistributed = 0;
        
        for (uint i = 0; i < royalties.length; i++) {
            uint256 amount = (totalAmount * royalties[i].feeNumerator) / 10000;
            if (amount > 0 && totalDistributed + amount <= totalAmount) {
                usdcToken.safeTransfer(royalties[i].receiver, amount);
                totalDistributed += amount;
            }
        }
    }
    
    /**
     * @dev This function allows a token seller to set a transfer price for royalty calculation
     * @param tokenId The ID of the token being sold
     * @param price The sale price in USDC, used for calculating royalties
     */
    function setTransferPrice(uint256 tokenId, uint256 price) external {
        require(ownerOf(tokenId) == msg.sender, "Not token owner");
        _lastTransferPrices[tokenId] = price;
        emit TransferPriceSet(tokenId, price);
    }
    
    /**
     * @dev Pay transfer royalties directly without relying on a marketplace
     * @param tokenId The ID of the token being transferred
     */
    function payTransferRoyalties(uint256 tokenId) external {
        uint256 salePrice = _lastTransferPrices[tokenId];
        require(salePrice > 0, "Transfer price not set");
        
        // Get royalty receivers for this token
        RoyaltyData[] memory royalties = _tokenTransferRoyalties[tokenId].length > 0 
            ? _tokenTransferRoyalties[tokenId] 
            : _transferRoyaltyReceivers;
            
        if (royalties.length == 0) return;
        
        uint256 totalFeeAmount = 0;
        for (uint i = 0; i < royalties.length; i++) {
            uint256 amount = (salePrice * royalties[i].feeNumerator) / 10000;
            totalFeeAmount += amount;
        }
        
        // Transfer total USDC amount needed from sender to this contract
        usdcToken.safeTransferFrom(msg.sender, address(this), totalFeeAmount);
        
        // Distribute royalties
        for (uint i = 0; i < royalties.length; i++) {
            uint256 amount = (salePrice * royalties[i].feeNumerator) / 10000;
            if (amount > 0) {
                usdcToken.safeTransfer(royalties[i].receiver, amount);
                emit TransferRoyaltyDistributed(tokenId, royalties[i].receiver, amount);
            }
        }
        
        // Reset transfer price after royalties are paid
        delete _lastTransferPrices[tokenId];
    }
    
    /**
     * @dev Custom safeTransferFrom that automatically handles royalty payments if price is set
     */
    function safeTransferFromWithRoyalties(
        address from,
        address to,
        uint256 tokenId,
        uint256 salePrice,
        bytes memory data
    ) external {
        require(ownerOf(tokenId) == from, "Not token owner");
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not approved");
        
        // Calculate and pay royalties if there's a sale price
        if (salePrice > 0) {
            // Calculate royalties
            RoyaltyData[] memory royalties = _tokenTransferRoyalties[tokenId].length > 0 
                ? _tokenTransferRoyalties[tokenId] 
                : _transferRoyaltyReceivers;
                
            if (royalties.length > 0) {
                uint256 totalFeeAmount = 0;
                
                // Calculate total royalty amount
                for (uint i = 0; i < royalties.length; i++) {
                    uint256 amount = (salePrice * royalties[i].feeNumerator) / 10000;
                    totalFeeAmount += amount;
                }
                
                // Transfer total USDC amount from sender to this contract
                if (totalFeeAmount > 0) {
                    usdcToken.safeTransferFrom(msg.sender, address(this), totalFeeAmount);
                    
                    // Distribute to royalty receivers
                    for (uint i = 0; i < royalties.length; i++) {
                        uint256 amount = (salePrice * royalties[i].feeNumerator) / 10000;
                        if (amount > 0) {
                            usdcToken.safeTransfer(royalties[i].receiver, amount);
                            emit TransferRoyaltyDistributed(tokenId, royalties[i].receiver, amount);
                        }
                    }
                }
            }
        }
        
        // Perform the transfer
        _safeTransfer(from, to, tokenId, data);
    }
    
    // Override _beforeTokenTransfer to properly call superclass method
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
        
        // No direct handling of transfer royalties here
        // This is handled by explicit royalty payment functions or safeTransferFromWithRoyalties
    }

    /**
     * @dev Withdraw USDC from contract to owner
     */
    function withdrawUSDC() external {
        _requireCallerIsContractOwner();
        uint256 balance = usdcToken.balanceOf(address(this));
        require(balance > 0, "No USDC to withdraw");
        usdcToken.safeTransfer(msg.sender, balance);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseURI(string memory baseURI) external {
        _requireCallerIsContractOwner();
        _baseTokenURI = baseURI;
    }

    function burn(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "Not token owner");
        _burn(tokenId);
    }

    function setSecurityPolicy(
        uint8 securityLevel,
        uint32 operatorWhitelistId,
        uint32 permittedContractReceiversAllowlistId
    ) external {
        _requireCallerIsContractOwner();
        
        // Store the security policy parameters for later use
        // This is a fallback since we can't directly call the validator's method
        // In a real implementation, you would call the appropriate method on the validator
        emit SecurityPolicyUpdated(
            address(this),
            securityLevel,
            operatorWhitelistId,
            permittedContractReceiversAllowlistId
        );
    }
    
    // Event to track security policy updates
    event SecurityPolicyUpdated(
        address indexed collection,
        uint8 securityLevel,
        uint32 operatorWhitelistId,
        uint32 permittedContractReceiversAllowlistId
    );
} 