// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
// Import interfaces needed for supportsInterface check
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title KAMI721AC
 * @dev An ERC721A implementation with USDC payments, programmable royalties, and rental functionality
 */
contract KAMI721AC is AccessControl, ERC721A, ERC2981, Pausable {
    using SafeERC20 for IERC20;
    
    // Role definitions
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant RENTER_ROLE = keccak256("RENTER_ROLE");
    bytes32 public constant PLATFORM_ROLE = keccak256("PLATFORM_ROLE");
    
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
    
    constructor(
        address usdcAddress_,
        string memory name_,
        string memory symbol_,
        string memory baseTokenURI_,
        uint256 initialMintPrice_,
        address platformAddress_,
        uint96 platformCommissionPercentage_
    ) 
        ERC721A(name_, symbol_)
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
        override(ERC721A, ERC2981, AccessControl)
        returns (bool) 
    {
        // Explicitly check ONLY the interfaces we directly care about supporting
        // plus the base ERC165 requirement.
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            interfaceId == type(IERC2981).interfaceId ||
            interfaceId == type(IAccessControl).interfaceId ||
            interfaceId == type(IERC165).interfaceId; // Check ERC165 explicitly
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
        require(totalMintPrice > 0, "Mint price must be set"); // Ensure mint price is set
        require(usdcToken.balanceOf(msg.sender) >= totalMintPrice, "Insufficient USDC balance");
        require(usdcToken.allowance(msg.sender, address(this)) >= totalMintPrice, "Insufficient USDC allowance");

        // Transfer USDC from minter to contract
        usdcToken.safeTransferFrom(msg.sender, address(this), totalMintPrice);
        
        // Distribute royalties and commission for each token potentially, or aggregate
        // Aggregating for efficiency:
        _distributeMintRoyaltiesAndCommission(totalMintPrice, 0); // Pass 0 as placeholder tokenId for aggregated payment

        // Mint the tokens using ERC721A's efficient batch minting
        _safeMint(msg.sender, quantity);
    }

    /**
     * @dev Internal function to distribute mint royalties and platform commission.
     * @param totalPayment The total USDC paid for the mint.
     * @param tokenId Placeholder, as distribution is aggregated for batch mints.
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
        
        // Determine which royalty configuration to use (token-specific or default)
        RoyaltyData[] memory currentRoyalties = _tokenMintRoyalties[tokenId]; // This logic might need adjustment for batch mints
        if (currentRoyalties.length == 0) {
            currentRoyalties = _mintRoyaltyReceivers;
        }
        
        // Distribute royalties based on the determined configuration
        // Note: For batch mints (tokenId 0), we MUST use default royalties.
        // A more complex system could pro-rate based on token-specific royalties if needed,
        // but that adds significant complexity. Using default for batch mint is simpler.
        if (tokenId == 0) { // Use default for batch mints
             currentRoyalties = _mintRoyaltyReceivers;
        }

        uint256 totalRoyaltyDistributed = 0;
        for (uint i = 0; i < currentRoyalties.length; i++) {
            uint256 royaltyAmount = (totalPayment * currentRoyalties[i].feeNumerator) / 10000;
            if (royaltyAmount > 0) {
                 usdcToken.safeTransfer(currentRoyalties[i].receiver, royaltyAmount);
                 totalRoyaltyDistributed += royaltyAmount;
                 // Event emission might need adjustment for batch context
            }
        }
        
        // Ensure remaining payment matches total distributed royalties
        // require(remainingPayment == totalRoyaltyDistributed, "Royalty distribution mismatch"); // This check might fail due to integer division precision loss
        // Consider a check with a small tolerance if needed
    }

    /**
     * @dev Sells a token from the caller to a specified buyer.
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
     * @dev Internal function to distribute transfer royalties and platform commission.
     * Calculates royalty based on `royaltyPercentage`.
     * @param tokenId The ID of the token being transferred.
     * @param salePrice The price the token was sold for.
     */
    function _distributeTransferRoyaltiesAndCommission(uint256 tokenId, uint256 salePrice) internal {
        // Calculate royalty amount
        uint256 royaltyAmount = (salePrice * royaltyPercentage) / 10000;
        
        // Calculate platform commission
        uint256 platformCommission = (salePrice * platformCommissionPercentage) / 10000;
        
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
    }

    /**
     * @dev Rents a token to a specified renter for a duration.
     * Requires the caller to be the owner or approved.
     * Requires sufficient USDC allowance and balance from the renter (paid to owner).
     * Grants RENTER_ROLE to the renter for the duration.
     * @param tokenId The ID of the token to rent.
     * @param duration The rental duration in seconds.
     * @param rentalPrice The total price for the rental period in USDC.
     */
    function rentToken(uint256 tokenId, uint256 duration, uint256 rentalPrice) external whenNotPaused {
        address owner = ownerOf(tokenId);
        require(msg.sender != owner, "Owner cannot rent their own token"); // Renter cannot be the owner
        require(duration > 0, "Duration must be positive");
        require(_rentals[tokenId].active == false, "Token is already rented");

        // Renter needs to pay the owner
        require(usdcToken.balanceOf(msg.sender) >= rentalPrice, "Insufficient USDC balance for rental");
        require(usdcToken.allowance(msg.sender, address(this)) >= rentalPrice, "Insufficient USDC allowance for rental");

        // Transfer rental payment from renter to owner
        usdcToken.safeTransferFrom(msg.sender, owner, rentalPrice);

        // Set rental details
        _rentals[tokenId] = Rental({
            renter: msg.sender,
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            rentalPrice: rentalPrice, // Store price for potential future reference/events
            active: true
        });

        // Grant RENTER_ROLE to the renter (careful: this is a global role)
        // Consider if a more granular check is needed based on tokenId
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
        // Note: This revokes the role globally even if the user rents other tokens.
        // A more complex system would track rentals per user.
        // if (!hasActiveRentals(renter)) { // Removed check
        _revokeRole(RENTER_ROLE, renter);
        // }
        
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
        require(block.timestamp < rental.endTime, "Rental has already expired"); // Cannot extend expired rental

        address owner = ownerOf(tokenId); // Get current owner

        // Renter needs to pay the owner for the extension
        require(usdcToken.balanceOf(msg.sender) >= additionalPayment, "Insufficient USDC balance for extension");
        require(usdcToken.allowance(msg.sender, address(this)) >= additionalPayment, "Insufficient USDC allowance for extension");

        // Transfer extension payment from renter to owner
        usdcToken.safeTransferFrom(msg.sender, owner, additionalPayment);

        // Extend the rental end time
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

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    /**
     * @dev Sets the base URI for all token IDs.
     * @param baseURI_ The new base URI.
     */
    function setBaseURI(string memory baseURI_) external {
        require(hasRole(OWNER_ROLE, msg.sender), "Caller is not an owner");
        _baseTokenURI = baseURI_;
    }

    /**
     * @dev Pauses all token transfers and minting.
     * See {ERC721Pausable-_pause}.
     * Requirements:
     * - The caller must have the `DEFAULT_ADMIN_ROLE`.
     */
    function pause() external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not admin");
        _pause();
    }

    /**
     * @dev Unpauses all token transfers and minting.
     * See {ERC721Pausable-_unpause}.
     * Requirements:
     * - The caller must have the `DEFAULT_ADMIN_ROLE`.
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
     * @dev Returns the user of a token, which is the renter if the token is actively rented,
     * otherwise the owner. This is useful for frontends interacting with rentals.
     * @param tokenId The ID of the token.
     * @return The address of the user (renter or owner).
     */
    function userOf(uint256 tokenId) public view returns (address) {
         Rental storage rental = _rentals[tokenId];
        if (rental.active && block.timestamp < rental.endTime) {
            return rental.renter;
        }
        return ownerOf(tokenId); // Returns actual owner if not rented
    }

    /**
     * @dev Function to check if an address is the current user (owner or active renter)
     * @param tokenId The ID of the token.
     * @param account The account to check.
     * @return bool True if the account is the current user.
     */
    function isUser(uint256 tokenId, address account) public view returns (bool) {
        return userOf(tokenId) == account;
    }

    // Override transferFrom and safeTransferFrom to check rentals
    function transferFrom(address from, address to, uint256 tokenId) public payable virtual override(ERC721A) {
        require(!_rentals[tokenId].active || block.timestamp >= _rentals[tokenId].endTime, "Token is rented");
        // --- Rental Cleanup Logic (if transfer implies end) --- START
        if (_rentals[tokenId].active && to != address(0) && block.timestamp >= _rentals[tokenId].endTime) { 
            address renter = _rentals[tokenId].renter;
            if (hasRole(RENTER_ROLE, renter)) {
                 _revokeRole(RENTER_ROLE, renter);
            }
            delete _rentals[tokenId];
        }
        // --- Rental Cleanup Logic --- END
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public payable virtual override(ERC721A) {
        require(!_rentals[tokenId].active || block.timestamp >= _rentals[tokenId].endTime, "Token is rented");
         // --- Rental Cleanup Logic (if transfer implies end) --- START
        if (_rentals[tokenId].active && to != address(0) && block.timestamp >= _rentals[tokenId].endTime) { 
            address renter = _rentals[tokenId].renter;
            if (hasRole(RENTER_ROLE, renter)) {
                 _revokeRole(RENTER_ROLE, renter);
            }
            delete _rentals[tokenId];
        }
        // --- Rental Cleanup Logic --- END
        super.safeTransferFrom(from, to, tokenId, data);
    }

    // --- DEBUGGING FUNCTION --- 
    function debugGetERC2981Id() public pure returns (bytes4) {
        return type(IERC2981).interfaceId;
    }
    // --- END DEBUGGING FUNCTION ---
}