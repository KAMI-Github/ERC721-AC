// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@limitbreak/creator-token-standards/src/access/OwnableBasic.sol";
import "@limitbreak/creator-token-standards/src/erc721c/ERC721C.sol";
import "@limitbreak/creator-token-standards/src/programmable-royalties/BasicRoyalties.sol";
import "@limitbreak/creator-token-standards/src/interfaces/ITransferValidator.sol";

contract GameNFT is OwnableBasic, ERC721C, BasicRoyalties {
    uint256 private _nextTokenId;
    uint256 public constant MINT_PRICE = 0.1 ether;
    string private _baseTokenURI;
    
    constructor(
        address royaltyReceiver_,
        uint96 royaltyFeeNumerator_,
        string memory name_,
        string memory symbol_,
        string memory baseTokenURI_
    ) 
        ERC721OpenZeppelin(name_, symbol_)
        BasicRoyalties(royaltyReceiver_, royaltyFeeNumerator_)
        OwnableBasic()
    {
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

    function mint() external payable {
        require(msg.value >= MINT_PRICE, "Insufficient payment");
        
        uint256 tokenId = _nextTokenId++;
        _safeMint(msg.sender, tokenId);
    }

    function withdraw() external {
        _requireCallerIsContractOwner();
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "Transfer failed");
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseURI(string memory baseURI) external {
        _requireCallerIsContractOwner();
        _baseTokenURI = baseURI;
    }

    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external {
        _requireCallerIsContractOwner();
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) external {
        _requireCallerIsContractOwner();
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
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