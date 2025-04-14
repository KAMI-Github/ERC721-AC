// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title KAMI721ACUpgradeable
 * @dev An upgradeable ERC721 implementation with batch minting (loop), USDC payments, programmable royalties, and rental functionality
 */
contract KAMI721ACUpgradeable is 
    Initializable, 
    AccessControlUpgradeable, 
    ERC721EnumerableUpgradeable,
    ERC2981Upgradeable, 
    PausableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;
    using CountersUpgradeable for CountersUpgradeable.Counter;
    
    // Role definitions
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant RENTER_ROLE = keccak256("RENTER_ROLE");
    bytes32 public constant PLATFORM_ROLE = keccak256("PLATFORM_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    
    // Re-introduce Counter for token IDs
    CountersUpgradeable.Counter private _tokenIdCounter;
    
    // Using Counter for token IDs
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
    
    // Transfer validator address
    address public transferValidator;
    
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
        // --- Explicitly call inherited initializers --- 
        __ERC721_init(name_, symbol_);
        __ERC721Enumerable_init();
        __AccessControl_init();
        __ERC2981_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        // --- Initialize contract-specific state --- 
        require(usdcAddress_ != address(0), "Invalid USDC address");
        require(platformAddress_ != address(0), "Invalid platform address");
        require(platformCommissionPercentage_ <= 2000, "Platform commission too high"); // Max 20%
        
        usdcToken = IERC20(usdcAddress_);
        _baseTokenURI = baseTokenURI_;
        mintPrice = initialMintPrice_;
        platformAddress = platformAddress_;
        platformCommissionPercentage = platformCommissionPercentage_;
        royaltyPercentage = 1000; // Default to 10%
        
        // Grant roles (msg.sender is the deployer/proxy admin initially)
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
        return super.supportsInterface(interfaceId);
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

    /**
     * @dev Mints `quantity` new tokens for `msg.sender`.
     * Calculates the total mint price based on the quantity.
     * Requires sufficient USDC allowance and balance.
     * Distributes mint royalties and platform commission.
     * @param quantity The number of tokens to mint.
     */
    function mint(uint256 quantity) external payable whenNotPaused {
        require(quantity > 0, "Quantity must be greater than zero");
        
        uint256 totalMintPrice = mintPrice * quantity;
        require(totalMintPrice > 0, "Mint price must be set");
        require(usdcToken.balanceOf(msg.sender) >= totalMintPrice, "Insufficient USDC balance");
        require(usdcToken.allowance(msg.sender, address(this)) >= totalMintPrice, "Insufficient USDC allowance");

        // Transfer USDC from minter to contract
        usdcToken.safeTransferFrom(msg.sender, address(this), totalMintPrice);
        
        // Distribute royalties and commission (aggregated for the batch)
        _distributeMintRoyaltiesAndCommission(totalMintPrice, 0); // Placeholder tokenId 0 for batch

        // Mint the tokens using a loop and standard _safeMint
        for (uint i = 0; i < quantity; i++) {
            uint256 tokenId = _tokenIdCounter.current();
            _safeMint(msg.sender, tokenId);
            _tokenIdCounter.increment();
        }
    }

     /**
     * @dev Internal function to distribute mint royalties and platform commission for batch mints.
     * @param totalPayment The total USDC paid for the mint batch.
     * @param tokenId Placeholder (usually 0), distribution uses default royalties.
     */
    function _distributeMintRoyaltiesAndCommission(uint256 totalPayment, uint256 tokenId) internal {
        uint256 remainingPayment = totalPayment;
        
        // Calculate and distribute platform commission
        uint256 platformCommission = (totalPayment * platformCommissionPercentage) / 10000;
        if (platformCommission > 0) {
            usdcToken.safeTransfer(platformAddress, platformCommission);
            remainingPayment -= platformCommission;
            emit PlatformCommissionPaid(tokenId, platformAddress, platformCommission); // Emitting with placeholder tokenId 0
        }
        
        // For batch mints, always use default mint royalties
        RoyaltyData[] memory currentRoyalties = _mintRoyaltyReceivers;
        
        uint256 totalRoyaltyDistributed = 0;
        for (uint i = 0; i < currentRoyalties.length; i++) {
            uint256 royaltyAmount = (totalPayment * currentRoyalties[i].feeNumerator) / 10000;
            if (royaltyAmount > 0) {
                 usdcToken.safeTransfer(currentRoyalties[i].receiver, royaltyAmount);
                 totalRoyaltyDistributed += royaltyAmount;
                 // Event emission might need adjustment for batch context if needed
            }
        }
        
        // Optional: Check remainingPayment against totalRoyaltyDistributed with tolerance for rounding
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
    function rentToken(uint256 tokenId, uint256 duration, uint256 rentalPrice) external whenNotPaused {
        address owner = ownerOf(tokenId);
        require(msg.sender != owner, "Owner cannot rent their own token");
        require(duration > 0, "Duration must be positive");
        require(!_rentals[tokenId].active, "Token is already rented");

        // Renter pays the owner directly (simplified flow)
        require(usdcToken.balanceOf(msg.sender) >= rentalPrice, "Insufficient USDC balance for rental");
        require(usdcToken.allowance(msg.sender, address(this)) >= rentalPrice, "Insufficient USDC allowance for rental");
        
        // Transfer rental payment from renter to owner
        usdcToken.safeTransferFrom(msg.sender, owner, rentalPrice);

        // Set rental details
        _rentals[tokenId] = Rental({
            renter: msg.sender,
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            rentalPrice: rentalPrice,
            active: true
        });

        // Grant RENTER_ROLE
        _grantRole(RENTER_ROLE, msg.sender);

        emit TokenRented(tokenId, owner, msg.sender, _rentals[tokenId].startTime, _rentals[tokenId].endTime, rentalPrice);
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
        
        // Revoke RENTER_ROLE from the renter
        _revokeRole(RENTER_ROLE, renter);
        
        emit RentalEnded(tokenId, tokenOwner, renter);
    }
    
    /**
     * @dev Extend a rental period
     * @param tokenId The token ID to extend rental for
     * @param additionalDuration The additional duration in seconds
     * @param additionalPayment The additional payment in USDC
     */
    function extendRental(uint256 tokenId, uint256 additionalDuration, uint256 additionalPayment) external whenNotPaused {
         Rental storage rental = _rentals[tokenId];
        require(rental.active, "Token is not currently rented");
        require(msg.sender == rental.renter, "Only the renter can extend");
        require(additionalDuration > 0, "Additional duration must be positive");
        require(block.timestamp < rental.endTime, "Rental has already expired");

        address owner = ownerOf(tokenId);

        // Renter pays the owner directly for extension
        require(usdcToken.balanceOf(msg.sender) >= additionalPayment, "Insufficient USDC balance for extension");
        require(usdcToken.allowance(msg.sender, address(this)) >= additionalPayment, "Insufficient USDC allowance for extension");
        
        // Transfer extension payment from renter to owner
        usdcToken.safeTransferFrom(msg.sender, owner, additionalPayment);

        // Extend rental end time
        rental.endTime += additionalDuration;

        emit RentalExtended(tokenId, rental.renter, rental.endTime);
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
     * @dev Returns the user of a token, which is the renter if the token is actively rented,
     * otherwise the owner.
     * @param tokenId The ID of the token.
     * @return The address of the user (renter or owner).
     */
    function userOf(uint256 tokenId) public view returns (address) {
         Rental storage rental = _rentals[tokenId];
        if (rental.active && block.timestamp < rental.endTime) {
            return rental.renter;
        }
        // ERC721A might throw if token doesn't exist, handle this?
        // It should revert anyway if tokenId is invalid.
        return ownerOf(tokenId);
    }

    // Function to check if an address is the current user (owner or active renter)
    function isUser(uint256 tokenId, address account) public view returns (bool) {
        return userOf(tokenId) == account;
    }

    // Override transferFrom and safeTransferFrom - Revert to non-payable for standard ERC721 
    // Add rental cleanup logic here since _update override is problematic
    function transferFrom(address from, address to, uint256 tokenId) public virtual override(ERC721Upgradeable, IERC721Upgradeable) {
        // Initial check: prevent transfer if actively rented and not expired
        require(!_rentals[tokenId].active || block.timestamp >= _rentals[tokenId].endTime, "Token is rented");

        // --- Rental Cleanup Logic (if transfer implies end) --- START
        // If it *was* rented (even if expired now), clear state before transfer
        if (_rentals[tokenId].renter != address(0) && to != address(0)) { // Check if renter exists & not burning
            address renter = _rentals[tokenId].renter;
            // Revoke role regardless of expiry if transfer is happening
            if (hasRole(RENTER_ROLE, renter)) {
                 _revokeRole(RENTER_ROLE, renter);
            }
            delete _rentals[tokenId];
            // RentalEnded event could be emitted here
        }
        // --- Rental Cleanup Logic --- END

        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public virtual override(ERC721Upgradeable, IERC721Upgradeable) {
        // Initial check: prevent transfer if actively rented and not expired
        require(!_rentals[tokenId].active || block.timestamp >= _rentals[tokenId].endTime, "Token is rented");

        // --- Rental Cleanup Logic (if transfer implies end) --- START
        // If it *was* rented (even if expired now), clear state before transfer
        if (_rentals[tokenId].renter != address(0) && to != address(0)) { // Check if renter exists & not burning
            address renter = _rentals[tokenId].renter;
            // Revoke role regardless of expiry if transfer is happening
            if (hasRole(RENTER_ROLE, renter)) {
                 _revokeRole(RENTER_ROLE, renter);
            }
            delete _rentals[tokenId];
            // RentalEnded event could be emitted here
        }
        // --- Rental Cleanup Logic --- END

        super.safeTransferFrom(from, to, tokenId, data);
    }

    /**
     * @dev Override _baseURI to return the stored base token URI.
     */
    function _baseURI() internal view virtual override(ERC721Upgradeable) returns (string memory) {
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
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not admin");
        _pause();
    }
    
    /**
     * @dev Unpause the contract
     */
    function unpause() external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not admin");
        _unpause();
    }
    
    /**
     * @dev Sets the transfer validator contract address.
     * @param _validator The address of the transfer validator contract.
     */
    function setTransferValidator(address _validator) external {
        require(hasRole(OWNER_ROLE, msg.sender), "Caller is not an owner");
        transferValidator = _validator;
    }
    
    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
} 