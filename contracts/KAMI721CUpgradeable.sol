// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title KAMI721CUpgradeable
 * @dev An upgradeable ERC721 implementation with USDC payments, programmable royalties, and rental functionality
 */
contract KAMI721CUpgradeable is 
    Initializable, 
    AccessControlUpgradeable, 
    ERC721EnumerableUpgradeable, 
    ERC2981Upgradeable, 
    PausableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;
    
    // Role definitions
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant RENTER_ROLE = keccak256("RENTER_ROLE");
    bytes32 public constant PLATFORM_ROLE = keccak256("PLATFORM_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    
    // Using Counter for token IDs
    Counters.Counter private _tokenIdCounter;
    uint256 public mintPrice;
    string private _baseTokenURI;
    
    // Platform commission details
    uint96 public platformCommissionPercentage; // Percentage in basis points (e.g., 500 = 5%)
    address public platformAddress;
    
    // USDC token contract
    IERC20 public usdcToken;
    
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
    uint96 public royaltyPercentage;
    
    // Rental functionality
    struct Rental {
        address renter;
        uint256 startTime;
        uint256 endTime;
        uint256 rentalPrice;
        bool active;
    }
    
    // Mapping from token ID to rental information
    mapping(uint256 => Rental) private _rentals;
    
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
    event TokenRented(uint256 indexed tokenId, address indexed owner, address indexed renter, uint256 startTime, uint256 endTime, uint256 rentalPrice);
    event RentalEnded(uint256 indexed tokenId, address indexed owner, address indexed renter);
    event RentalExtended(uint256 indexed tokenId, address indexed renter, uint256 newEndTime);
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @dev Initializes the contract
     */
    function initialize(
        address usdcAddress_,
        string memory name_,
        string memory symbol_,
        string memory baseTokenURI_,
        uint256 initialMintPrice_,
        address platformAddress_,
        uint96 platformCommissionPercentage_
    ) public initializer {
        require(usdcAddress_ != address(0), "Invalid USDC address");
        require(platformAddress_ != address(0), "Invalid platform address");
        require(platformCommissionPercentage_ <= 2000, "Platform commission too high"); // Max 20%
        
        __ERC721_init(name_, symbol_);
        __ERC721Enumerable_init();
        __AccessControl_init();
        __ERC2981_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        
        usdcToken = IERC20(usdcAddress_);
        _baseTokenURI = baseTokenURI_;
        mintPrice = initialMintPrice_;
        platformAddress = platformAddress_;
        platformCommissionPercentage = platformCommissionPercentage_;
        royaltyPercentage = 1000; // Default to 10%
        
        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OWNER_ROLE, msg.sender);
        _grantRole(PLATFORM_ROLE, platformAddress_);
        _grantRole(UPGRADER_ROLE, msg.sender);
    }

    /**
     * @dev Function that should revert when `msg.sender` is not authorized to upgrade the contract.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    function supportsInterface(bytes4 interfaceId) 
        public 
        view 
        virtual 
        override(ERC721EnumerableUpgradeable, ERC2981Upgradeable, AccessControlUpgradeable) 
        returns (bool) 
    {
        return ERC721EnumerableUpgradeable.supportsInterface(interfaceId) ||
            ERC2981Upgradeable.supportsInterface(interfaceId) ||
            AccessControlUpgradeable.supportsInterface(interfaceId);
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
        require(!_rentals[tokenId].active, "Token is currently rented");
        
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

    /**
     * @dev Rent a token for a specified duration
     * @param tokenId The token ID to rent
     * @param duration The rental duration in seconds
     * @param rentalPrice The rental price in USDC
     */
    function rentToken(uint256 tokenId, uint256 duration, uint256 rentalPrice) external {
        require(_exists(tokenId), "Token does not exist");
        require(!_rentals[tokenId].active, "Token is already rented");
        require(duration > 0, "Rental duration must be greater than 0");
        require(rentalPrice > 0, "Rental price must be greater than 0");
        
        address tokenOwner = ownerOf(tokenId);
        require(tokenOwner != msg.sender, "Owner cannot rent their own token");
        
        // Calculate platform commission
        uint256 platformCommission = (rentalPrice * platformCommissionPercentage) / 10000;
        
        // Calculate owner's share (rental price minus platform commission)
        uint256 ownerShare = rentalPrice - platformCommission;
        
        // Transfer rental payment from renter to this contract
        usdcToken.safeTransferFrom(msg.sender, address(this), rentalPrice);
        
        // Pay platform commission
        if (platformCommission > 0) {
            usdcToken.safeTransfer(platformAddress, platformCommission);
            emit PlatformCommissionPaid(tokenId, platformAddress, platformCommission);
        }
        
        // Pay owner's share
        usdcToken.safeTransfer(tokenOwner, ownerShare);
        
        // Create rental record
        _rentals[tokenId] = Rental({
            renter: msg.sender,
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            rentalPrice: rentalPrice,
            active: true
        });
        
        // Grant RENTER_ROLE to the renter
        _grantRole(RENTER_ROLE, msg.sender);
        
        emit TokenRented(tokenId, tokenOwner, msg.sender, block.timestamp, block.timestamp + duration, rentalPrice);
    }
    
    /**
     * @dev End a rental early (can be called by either the owner or the renter)
     * @param tokenId The token ID to end rental for
     */
    function endRental(uint256 tokenId) external {
        require(_exists(tokenId), "Token does not exist");
        require(_rentals[tokenId].active, "Token is not rented");
        
        address tokenOwner = ownerOf(tokenId);
        require(msg.sender == tokenOwner || msg.sender == _rentals[tokenId].renter, "Only owner or renter can end rental");
        
        address renter = _rentals[tokenId].renter;
        
        // Mark rental as inactive
        _rentals[tokenId].active = false;
        
        // Revoke RENTER_ROLE from the renter if they have no other active rentals
        if (!hasActiveRentals(renter)) {
            _revokeRole(RENTER_ROLE, renter);
        }
        
        emit RentalEnded(tokenId, tokenOwner, renter);
    }
    
    /**
     * @dev Extend a rental period
     * @param tokenId The token ID to extend rental for
     * @param additionalDuration The additional duration in seconds
     * @param additionalPayment The additional payment in USDC
     */
    function extendRental(uint256 tokenId, uint256 additionalDuration, uint256 additionalPayment) external {
        require(_exists(tokenId), "Token does not exist");
        require(_rentals[tokenId].active, "Token is not rented");
        require(additionalDuration > 0, "Additional duration must be greater than 0");
        require(additionalPayment > 0, "Additional payment must be greater than 0");
        
        address tokenOwner = ownerOf(tokenId);
        require(msg.sender == _rentals[tokenId].renter, "Only renter can extend rental");
        
        // Calculate platform commission for the additional payment
        uint256 platformCommission = (additionalPayment * platformCommissionPercentage) / 10000;
        
        // Calculate owner's share (additional payment minus platform commission)
        uint256 ownerShare = additionalPayment - platformCommission;
        
        // Transfer additional payment from renter to this contract
        usdcToken.safeTransferFrom(msg.sender, address(this), additionalPayment);
        
        // Pay platform commission
        if (platformCommission > 0) {
            usdcToken.safeTransfer(platformAddress, platformCommission);
            emit PlatformCommissionPaid(tokenId, platformAddress, platformCommission);
        }
        
        // Pay owner's share
        usdcToken.safeTransfer(tokenOwner, ownerShare);
        
        // Update rental end time
        _rentals[tokenId].endTime += additionalDuration;
        _rentals[tokenId].rentalPrice += additionalPayment;
        
        emit RentalExtended(tokenId, msg.sender, _rentals[tokenId].endTime);
    }
    
    /**
     * @dev Check if a token is currently rented
     * @param tokenId The token ID to check
     * @return bool Whether the token is rented
     */
    function isRented(uint256 tokenId) external view returns (bool) {
        return _rentals[tokenId].active;
    }
    
    /**
     * @dev Get rental information for a token
     * @param tokenId The token ID to get rental info for
     * @return renter The address of the renter
     * @return startTime The rental start time
     * @return endTime The rental end time
     * @return rentalPrice The rental price
     * @return active Whether the rental is active
     */
    function getRentalInfo(uint256 tokenId) external view returns (
        address renter,
        uint256 startTime,
        uint256 endTime,
        uint256 rentalPrice,
        bool active
    ) {
        Rental memory rental = _rentals[tokenId];
        return (rental.renter, rental.startTime, rental.endTime, rental.rentalPrice, rental.active);
    }
    
    /**
     * @dev Check if a user has any active rentals
     * @param user The user address to check
     * @return bool Whether the user has active rentals
     */
    function hasActiveRentals(address user) public view returns (bool) {
        for (uint256 i = 0; i < totalSupply(); i++) {
            uint256 tokenId = tokenByIndex(i);
            if (_rentals[tokenId].active && _rentals[tokenId].renter == user) {
                return true;
            }
        }
        return false;
    }
    
    /**
     * @dev Override _beforeTokenTransfer to prevent transfers during rental
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal virtual override(ERC721EnumerableUpgradeable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
        
        // Allow minting and burning
        if (from == address(0) || to == address(0)) {
            return;
        }
        
        // Check if token is rented
        if (_rentals[tokenId].active) {
            // Only allow transfers from the renter back to the owner
            address tokenOwner = ownerOf(tokenId);
            require(
                (from == _rentals[tokenId].renter && to == tokenOwner) || 
                (msg.sender == tokenOwner && block.timestamp >= _rentals[tokenId].endTime),
                "Token is locked during rental period"
            );
            
            // If rental period has ended, mark it as inactive
            if (block.timestamp >= _rentals[tokenId].endTime) {
                _rentals[tokenId].active = false;
                
                // Revoke RENTER_ROLE from the renter if they have no other active rentals
                if (!hasActiveRentals(_rentals[tokenId].renter)) {
                    _revokeRole(RENTER_ROLE, _rentals[tokenId].renter);
                }
                
                emit RentalEnded(tokenId, tokenOwner, _rentals[tokenId].renter);
            }
        }
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
        require(!_rentals[tokenId].active, "Cannot burn a rented token");
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
    
    /**
     * @dev Pause the contract
     */
    function pause() external {
        require(hasRole(OWNER_ROLE, msg.sender), "Caller is not an owner");
        _pause();
    }
    
    /**
     * @dev Unpause the contract
     */
    function unpause() external {
        require(hasRole(OWNER_ROLE, msg.sender), "Caller is not an owner");
        _unpause();
    }
    
    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
} 