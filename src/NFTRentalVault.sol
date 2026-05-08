// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


interface IERC4907 {
    function setUser(uint256 tokenId, address user, uint64 expires) external;
    function userOf(uint256 tokenId) external view returns (address);
    function userExpires(uint256 tokenId) external view returns (uint256);
}

contract NFTRentalVault is ReentrancyGuard {
    struct RentalListing {
        address owner;
        uint256 pricePerDay;
        uint256 maxDuration;
        bool active;
    }

    IERC20 public immutable manaToken;
    mapping(address => mapping(uint256 => RentalListing)) public listings;

    event NFTListed(address indexed nftAddress, uint256 indexed tokenId, uint256 price, uint256 duration);
    event NFTRented(address indexed nftAddress, uint256 indexed tokenId, address indexed renter, uint256 expiry);

    constructor(address _manaToken) {
        manaToken = IERC20(_manaToken);
    }

    
    function listNFT(address nftAddress, uint256 tokenId, uint256 pricePerDay, uint256 maxDuration) external {
        IERC721(nftAddress).transferFrom(msg.sender, address(this), tokenId);
        
        listings[nftAddress][tokenId] = RentalListing({
            owner: msg.sender,
            pricePerDay: pricePerDay,
            maxDuration: maxDuration,
            active: true
        });

        emit NFTListed(nftAddress, tokenId, pricePerDay, maxDuration);
    }

    
    function rentNFT(address nftAddress, uint256 tokenId, uint64 durationDays) external nonReentrant {
        RentalListing storage listing = listings[nftAddress][tokenId];
        require(listing.active, "Not for rent");
        require(durationDays > 0 && durationDays <= listing.maxDuration, "Invalid duration");

        uint256 totalPrice = listing.pricePerDay * durationDays;
        uint64 expiry = uint64(block.timestamp + (durationDays * 1 days));

        
        manaToken.transferFrom(msg.sender, listing.owner, totalPrice);

        
        IERC4907(nftAddress).setUser(tokenId, msg.sender, expiry);

        emit NFTRented(nftAddress, tokenId, msg.sender, expiry);
    }

    function withdrawNFT(address nftAddress, uint256 tokenId) external {
        RentalListing storage listing = listings[nftAddress][tokenId];
        require(listing.owner == msg.sender, "Not owner");
        
        delete listings[nftAddress][tokenId];
        IERC721(nftAddress).transferFrom(address(this), msg.sender, tokenId);
    }
}