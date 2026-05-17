// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "./GameItems.sol";

/// @title NFTRentalVault
/// @notice Custodial rental vault for GameItems equipment NFTs (ERC-1155 tokens
///         with supply 1, IDs >= 1000). An owner deposits an equipment piece and
///         sets a daily price in MANA plus a maximum rental duration. A renter
///         pays the MANA up-front and receives time-bound `user` rights tracked
///         on-chain — an ERC-4907-style model adapted to ERC-1155.
/// @dev    Design patterns: Checks-Effects-Interactions, Reentrancy Guard,
///         Pull-over-push (owners withdraw earnings), Pausable / Circuit Breaker,
///         State Machine (listing lifecycle: None -> Listed -> Rented -> Listed).
contract NFTRentalVault is ReentrancyGuard, Pausable, Ownable, ERC1155Holder {
    // ─── External contracts ───────────────────────────────────────────────────
    GameItems public immutable items;
    /// @notice MANA token ID inside GameItems — the rental currency.
    uint256 public immutable MANA;

    // ─── Listing storage ──────────────────────────────────────────────────────
    struct Listing {
        address owner;        // depositor / NFT owner
        uint256 pricePerDay;  // rental price per day, in MANA units
        uint64  maxDuration;  // maximum rentable duration, in days
        address user;         // current renter (ERC-4907 `user`)
        uint64  userExpires;  // unix timestamp the rental rights expire at
        bool    active;       // true while the NFT is held by the vault
    }

    /// @dev equipmentId => Listing. Equipment IDs are unique (supply 1).
    mapping(uint256 => Listing) public listings;

    /// @notice Unclaimed MANA earnings per owner (pull-over-push).
    mapping(address => uint256) public earnings;

    // ─── Events ───────────────────────────────────────────────────────────────
    event Listed(uint256 indexed equipmentId, address indexed owner, uint256 pricePerDay, uint64 maxDuration);
    event PriceUpdated(uint256 indexed equipmentId, uint256 pricePerDay, uint64 maxDuration);
    event Rented(uint256 indexed equipmentId, address indexed renter, uint64 expires, uint256 paid);
    event Delisted(uint256 indexed equipmentId, address indexed owner);
    event EarningsClaimed(address indexed owner, uint256 amount);

    constructor(address itemsContract_, address admin_) Ownable(admin_) {
        require(itemsContract_ != address(0), "Rental: zero address");
        GameItems items_ = GameItems(itemsContract_);
        items = items_;
        MANA  = items_.MANA();
    }

    // ─── Owner: list an equipment NFT ─────────────────────────────────────────
    /// @notice Deposit an equipment NFT into the vault and open it for rent.
    function list(uint256 equipmentId, uint256 pricePerDay, uint64 maxDuration)
        external
        nonReentrant
        whenNotPaused
    {
        require(equipmentId >= 1000, "Rental: not equipment");
        require(maxDuration > 0, "Rental: zero duration");
        require(!listings[equipmentId].active, "Rental: already listed");

        // Effects: record the listing before pulling the NFT in.
        listings[equipmentId] = Listing({
            owner: msg.sender,
            pricePerDay: pricePerDay,
            maxDuration: maxDuration,
            user: address(0),
            userExpires: 0,
            active: true
        });

        // Interaction: pull the NFT into custody.
        items.safeTransferFrom(msg.sender, address(this), equipmentId, 1, "");
        emit Listed(equipmentId, msg.sender, pricePerDay, maxDuration);
    }

    /// @notice Update price / max duration of an idle listing.
    function updateListing(uint256 equipmentId, uint256 pricePerDay, uint64 maxDuration)
        external
    {
        Listing storage l = listings[equipmentId];
        require(l.owner == msg.sender, "Rental: not owner");
        require(maxDuration > 0, "Rental: zero duration");
        require(block.timestamp >= l.userExpires, "Rental: active rental");

        l.pricePerDay = pricePerDay;
        l.maxDuration = maxDuration;
        emit PriceUpdated(equipmentId, pricePerDay, maxDuration);
    }

    // ─── Renter: rent an equipment NFT ────────────────────────────────────────
    /// @notice Rent an equipment NFT for `durationDays` days, paying in MANA.
    /// @dev    Checks-Effects-Interactions: the rental state is written before
    ///         the MANA transfer; payment is credited to the owner's pull
    ///         balance rather than pushed.
    function rent(uint256 equipmentId, uint64 durationDays)
        external
        nonReentrant
        whenNotPaused
    {
        Listing storage l = listings[equipmentId];
        require(l.active, "Rental: not listed");
        require(durationDays > 0 && durationDays <= l.maxDuration, "Rental: bad duration");
        require(block.timestamp >= l.userExpires, "Rental: currently rented");
        require(msg.sender != l.owner, "Rental: owner cannot rent");

        uint256 total = l.pricePerDay * durationDays;
        uint64 expires = uint64(block.timestamp + uint256(durationDays) * 1 days);

        // Effects.
        l.user = msg.sender;
        l.userExpires = expires;
        earnings[l.owner] += total;

        // Interaction: pull MANA from the renter into the vault.
        if (total > 0) {
            items.safeTransferFrom(msg.sender, address(this), MANA, total, "");
        }
        emit Rented(equipmentId, msg.sender, expires, total);
    }

    // ─── Owner: claim earnings (pull-over-push) ───────────────────────────────
    /// @notice Withdraw accumulated MANA rental income.
    function claimEarnings() external nonReentrant {
        uint256 amount = earnings[msg.sender];
        require(amount > 0, "Rental: nothing to claim");

        earnings[msg.sender] = 0; // effect before interaction
        items.safeTransferFrom(address(this), msg.sender, MANA, amount, "");
        emit EarningsClaimed(msg.sender, amount);
    }

    // ─── Owner: reclaim the NFT ───────────────────────────────────────────────
    /// @notice Withdraw the equipment NFT once no active rental remains.
    function delist(uint256 equipmentId) external nonReentrant {
        Listing storage l = listings[equipmentId];
        require(l.owner == msg.sender, "Rental: not owner");
        require(l.active, "Rental: not listed");
        require(block.timestamp >= l.userExpires, "Rental: active rental");

        delete listings[equipmentId];
        items.safeTransferFrom(address(this), msg.sender, equipmentId, 1, "");
        emit Delisted(equipmentId, msg.sender);
    }

    // ─── ERC-4907-style views ─────────────────────────────────────────────────
    /// @notice The address currently holding rental rights, or zero if none.
    function userOf(uint256 equipmentId) external view returns (address) {
        Listing storage l = listings[equipmentId];
        return block.timestamp < l.userExpires ? l.user : address(0);
    }

    /// @notice Timestamp the current rental expires at.
    function userExpires(uint256 equipmentId) external view returns (uint256) {
        return listings[equipmentId].userExpires;
    }

    /// @notice Quote the MANA cost to rent for `durationDays` days.
    function quoteRent(uint256 equipmentId, uint64 durationDays)
        external
        view
        returns (uint256)
    {
        return listings[equipmentId].pricePerDay * durationDays;
    }

    // ─── Circuit breaker ──────────────────────────────────────────────────────
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
