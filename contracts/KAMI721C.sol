// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

/**
 * @title KAMI721C
 * @dev An ERC721 implementation with USDC payments and programmable royalties for both minting and transfers
 */
contract KAMI721C is AccessControl, ERC721Enumerable, ERC2981 {
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;
    
    // Role definitions
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant RENTER_ROLE = keccak256("RENTER_ROLE");
    bytes32 public constant PLATFORM_ROLE = keccak256("PLATFORM_ROLE");
    
    // Using Counter for token IDs
    Counters.Counter private _tokenIdCounter;
    uint256 public mintPrice;
    string private _baseTokenURI;
    
    // Platform commission details
    uint96 public platformCommissionPercentage; // Percentage in basis points (e.g., 500 = 5%)
    address public platformAddress;
    
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
    
    // Royalty percentage for transfers as percentage of sale price (in basis points, 10000 = 100%)
    uint96 public royaltyPercentage = 1000; // Default to 10%
    
    // Events
    event MintRoyaltiesUpdated(RoyaltyData[] royalties);
    event TransferRoyaltiesUpdated(RoyaltyData[] royalties);
    event TokenMintRoyaltiesUpdated(uint256 indexed tokenId, RoyaltyData[] royalties);
    event TokenTransferRoyaltiesUpdated(uint256 indexed tokenId, RoyaltyData[] royalties);
    event TransferRoyaltyDistributed(uint256 indexed tokenId, address indexed receiver, uint256 amount);
    event PlatformCommissionPaid(uint256 indexed tokenId, address indexed platformAddress, uint256 amount);
    event RoyaltyPercentageUpdated(uint96 newPercentage);
    event PlatformCommissionUpdated(uint96 newPercentage, address newPlatformAddress);
    event TokenSold(uint256 indexed tokenId, address indexed from, address indexed to, uint256 salePrice);
    
    constructor(
        address usdcAddress_,
        string memory name_,
        string memory symbol_,
        string memory baseTokenURI_,
        uint256 initialMintPrice_,
        address platformAddress_,
        uint96 platformCommissionPercentage_
    ) 
        ERC721(name_, symbol_)
    {
        require(usdcAddress_ != address(0), "Invalid USDC address");
        require(platformAddress_ != address(0), "Invalid platform address");
        require(platformCommissionPercentage_ <= 2000, "Platform commission too high"); // Max 20%
        
        usdcToken = IERC20(usdcAddress_);
        _baseTokenURI = baseTokenURI_;
        mintPrice = initialMintPrice_;
        platformAddress = platformAddress_;
        platformCommissionPercentage = platformCommissionPercentage_;
        
        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OWNER_ROLE, msg.sender);
        _grantRole(PLATFORM_ROLE, platformAddress_);
    }

    function supportsInterface(bytes4 interfaceId) 
        public 
        view 
        virtual 
        override(ERC721Enumerable, ERC2981, AccessControl) 
        returns (bool) 
    {
        return ERC721Enumerable.supportsInterface(interfaceId) ||
            ERC2981.supportsInterface(interfaceId) ||
            AccessControl.supportsInterface(interfaceId);
    }
    
    /**
     * @dev Set the platform commission percentage and address
     * @param newPlatformCommissionPercentage New commission percentage in basis points (e.g., 500 = 5%)
     * @param newPlatformAddress New platform address to receive commission
     */
    function setPlatformCommission(uint96 newPlatformCommissionPercentage, address newPlatformAddress) external {
        require(hasRole(OWNER_ROLE, msg.sender), "Caller is not an owner");
        require(newPlatformAddress != address(0), "Invalid platform address");
        require(newPlatformCommissionPercentage <= 2000, "Platform commission too high"); // Max 20%
        
        // Store old platform address for role revocation
        address oldPlatformAddress = platformAddress;
        
        // Update commission and address
        platformCommissionPercentage = newPlatformCommissionPercentage;
        platformAddress = newPlatformAddress;
        
        // Update platform role - revoke from old address if different
        if (oldPlatformAddress != newPlatformAddress) {
            if (hasRole(PLATFORM_ROLE, oldPlatformAddress)) {
                _revokeRole(PLATFORM_ROLE, oldPlatformAddress);
            }
            _grantRole(PLATFORM_ROLE, newPlatformAddress);
        }
        
        emit PlatformCommissionUpdated(newPlatformCommissionPercentage, newPlatformAddress);
    }
    
    /**
     * @dev Set the royalty percentage for transfers
     * @param newRoyaltyPercentage New royalty percentage in basis points (e.g., 1000 = 10%)
     */
    function setRoyaltyPercentage(uint96 newRoyaltyPercentage) external {
        require(hasRole(OWNER_ROLE, msg.sender), "Caller is not an owner");
        require(newRoyaltyPercentage <= 3000, "Royalty percentage too high"); // Max 30%
        
        royaltyPercentage = newRoyaltyPercentage;
        emit RoyaltyPercentageUpdated(newRoyaltyPercentage);
    }
    
    // Setting default royalty receivers for minting
    function setMintRoyalties(RoyaltyData[] calldata royalties) external {
        require(hasRole(OWNER_ROLE, msg.sender), "Caller is not an owner");
        delete _mintRoyaltyReceivers;
        
        uint96 totalFees = 0;
        for (uint i = 0; i < royalties.length; i++) {
            require(royalties[i].receiver != address(0), "Invalid receiver");
            totalFees += royalties[i].feeNumerator;
            _mintRoyaltyReceivers.push(royalties[i]);
        }
        
        // Mint royalties + platform commission must not exceed 100%
        require(totalFees + platformCommissionPercentage <= 10000, "Royalties + platform commission exceed 100%");
        
        emit MintRoyaltiesUpdated(royalties);
    }
    
    // Setting default royalty receivers for transfers
    function setTransferRoyalties(RoyaltyData[] calldata royalties) external {
        require(hasRole(OWNER_ROLE, msg.sender), "Caller is not an owner");
        delete _transferRoyaltyReceivers;
        
        uint96 totalFees = 0;
        for (uint i = 0; i < royalties.length; i++) {
            require(royalties[i].receiver != address(0), "Invalid receiver");
            totalFees += royalties[i].feeNumerator;
            _transferRoyaltyReceivers.push(royalties[i]);
        }
        
        // Total transfer royalty percentages must equal 100%
        require(totalFees == 10000, "Total transfer royalty percentages must equal 100%");
        
        // Set the default receiver and fee for ERC2981 compatibility
        if (royalties.length > 0) {
            _setDefaultRoyalty(royalties[0].receiver, royalties[0].feeNumerator);
        }
        
        emit TransferRoyaltiesUpdated(royalties);
    }
    
    // Setting token-specific mint royalties
    function setTokenMintRoyalties(uint256 tokenId, RoyaltyData[] calldata royalties) external {
        require(hasRole(OWNER_ROLE, msg.sender), "Caller is not an owner");
        require(_exists(tokenId), "Token does not exist");
        
        delete _tokenMintRoyalties[tokenId];
        
        uint96 totalFees = 0;
        for (uint i = 0; i < royalties.length; i++) {
            require(royalties[i].receiver != address(0), "Invalid receiver");
            totalFees += royalties[i].feeNumerator;
            _tokenMintRoyalties[tokenId].push(royalties[i]);
        }
        
        // Mint royalties + platform commission must not exceed 100%
        require(totalFees + platformCommissionPercentage <= 10000, "Royalties + platform commission exceed 100%");
        
        emit TokenMintRoyaltiesUpdated(tokenId, royalties);
    }
    
    // Setting token-specific transfer royalties
    function setTokenTransferRoyalties(uint256 tokenId, RoyaltyData[] calldata royalties) external {
        require(hasRole(OWNER_ROLE, msg.sender), "Caller is not an owner");
        require(_exists(tokenId), "Token does not exist");
        
        delete _tokenTransferRoyalties[tokenId];
        
        uint96 totalFees = 0;
        for (uint i = 0; i < royalties.length; i++) {
            require(royalties[i].receiver != address(0), "Invalid receiver");
            totalFees += royalties[i].feeNumerator;
            _tokenTransferRoyalties[tokenId].push(royalties[i]);
        }
        
        // Total transfer royalty percentages must equal 100%
        require(totalFees == 10000, "Total transfer royalty percentages must equal 100%");
        
        // Set the token royalty for ERC2981 compatibility (this is for external marketplaces)
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
        // For ERC2981 compatibility, calculate based on the royaltyPercentage
        uint256 totalRoyaltyAmount = (salePrice * royaltyPercentage) / 10000;
        
        // Determine the receivers and their shares
        RoyaltyData[] memory royalties = _tokenTransferRoyalties[tokenId].length > 0 
            ? _tokenTransferRoyalties[tokenId] 
            : _transferRoyaltyReceivers;
            
        if (royalties.length > 0) {
            // For ERC2981, we return the first receiver with a proportional amount
            RoyaltyData memory info = royalties[0];
            uint256 receiverShare = (totalRoyaltyAmount * info.feeNumerator) / 10000;
            return (info.receiver, receiverShare);
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
        // Calculate platform commission
        uint256 platformCommission = (mintPrice * platformCommissionPercentage) / 10000;
        
        // Get mint royalties for this token
        RoyaltyData[] memory royalties = _mintRoyaltyReceivers;
            
        // Calculate remaining amount to distribute
        uint256 remainingAmount = mintPrice - platformCommission;
        
        // Transfer USDC from sender to this contract
        usdcToken.safeTransferFrom(msg.sender, address(this), mintPrice);
        
        // Pay platform commission
        if (platformCommission > 0) {
            usdcToken.safeTransfer(platformAddress, platformCommission);
        }
        
        // Distribute mint royalties
        uint256 totalDistributed = 0;
        if (royalties.length > 0) {
            for (uint i = 0; i < royalties.length; i++) {
                uint256 amount = (remainingAmount * royalties[i].feeNumerator) / 10000;
                if (amount > 0) {
                    usdcToken.safeTransfer(royalties[i].receiver, amount);
                    totalDistributed += amount;
                }
            }
        }
        
        // If there's any remaining USDC (due to rounding), send it to the first royalty receiver or platform
        uint256 undistributed = remainingAmount - totalDistributed;
        if (undistributed > 0) {
            if (royalties.length > 0) {
                usdcToken.safeTransfer(royalties[0].receiver, undistributed);
            } else {
                usdcToken.safeTransfer(platformAddress, undistributed);
            }
        }
        
        // Get current token ID and increment for next mint
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        
        // Mint the token
        _safeMint(msg.sender, tokenId);
    }
    
    /**
     * @dev Sell a token with royalties in a single transaction
     * @param to The buyer address
     * @param tokenId The token ID to sell
     * @param salePrice The sale price in USDC
     */
    function sellToken(address to, uint256 tokenId, uint256 salePrice) external {
        address seller = ownerOf(tokenId);
        require(msg.sender == seller, "Only token owner can sell");
        
        // Calculate royalty amount
        uint256 royaltyAmount = (salePrice * royaltyPercentage) / 10000;
        
        // Calculate platform commission
        uint256 platformCommission = (salePrice * platformCommissionPercentage) / 10000;
        
        // Calculate seller proceeds
        uint256 sellerProceeds = salePrice - (royaltyAmount + platformCommission);
        
        // Transfer total sale price from buyer to contract
        usdcToken.safeTransferFrom(to, address(this), salePrice);
        
        // Distribute royalties
        if (royaltyAmount > 0) {
            // Get royalty receivers for this token
            RoyaltyData[] memory royalties = _tokenTransferRoyalties[tokenId].length > 0 
                ? _tokenTransferRoyalties[tokenId] 
                : _transferRoyaltyReceivers;
                
            if (royalties.length > 0) {
                for (uint i = 0; i < royalties.length; i++) {
                    uint256 amount = (royaltyAmount * royalties[i].feeNumerator) / 10000;
                    if (amount > 0) {
                        usdcToken.safeTransfer(royalties[i].receiver, amount);
                        emit TransferRoyaltyDistributed(tokenId, royalties[i].receiver, amount);
                    }
                }
            }
        }
        
        // Pay platform commission
        if (platformCommission > 0) {
            usdcToken.safeTransfer(platformAddress, platformCommission);
            emit PlatformCommissionPaid(tokenId, platformAddress, platformCommission);
        }
        
        // Pay seller
        usdcToken.safeTransfer(seller, sellerProceeds);
        
        // Transfer the token
        safeTransferFrom(seller, to, tokenId);
        
        emit TokenSold(tokenId, seller, to, salePrice);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseURI(string memory baseURI) external {
        require(hasRole(OWNER_ROLE, msg.sender), "Caller is not an owner");
        _baseTokenURI = baseURI;
    }

    function burn(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "Not token owner");
        _burn(tokenId);
    }

    /**
     * Set the mint price
     * @param newMintPrice The new mint price in USDC (with 6 decimals)
     */
    function setMintPrice(uint256 newMintPrice) external {
        require(hasRole(OWNER_ROLE, msg.sender), "Caller is not an owner");
        mintPrice = newMintPrice;
    }
} 