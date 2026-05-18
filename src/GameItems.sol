// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/// @title GameItems
/// @notice ERC-1155 contract for RealmForge.
///         Token IDs 1-3 are fungible resources ($IRON, $WOOD, $MANA).
///         Token IDs 1000+ are unique NFT equipment pieces.
contract GameItems is ERC1155, AccessControl {
    using Strings for uint256;

    // ─── Roles ───────────────────────────────────────────────────────────────
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    // ─── Token IDs ────────────────────────────────────────────────────────────
    uint256 public constant IRON = 1;
    uint256 public constant WOOD = 2;
    uint256 public constant MANA = 3;

    // Equipment starts at 1000
    uint256 private _nextEquipmentId = 1000;

    // ─── Metadata ─────────────────────────────────────────────────────────────
    string public name = "RealmForge Items";
    string private _baseURI;

    // ─── Equipment registry ───────────────────────────────────────────────────
    struct Equipment {
        string name;
        uint8 tier; // 1 common → 5 legendary
        uint256 power;
    }
    mapping(uint256 => Equipment) public equipment;

    // ─── Events ───────────────────────────────────────────────────────────────
    event EquipmentRegistered(uint256 indexed tokenId, string name, uint8 tier);
    event ResourcesMinted(address indexed to, uint256 indexed tokenId, uint256 amount);

    constructor(address admin, string memory baseURI_) ERC1155(baseURI_) {
        _baseURI = baseURI_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(BURNER_ROLE, admin);
    }

    // ─── Mint resources ───────────────────────────────────────────────────────
    /// @notice Mint fungible resource tokens. Called by LootVRF or admin.
    function mintResource(address to, uint256 tokenId, uint256 amount) external onlyRole(MINTER_ROLE) {
        require(tokenId >= 1 && tokenId <= 3, "GameItems: not a resource");
        _mint(to, tokenId, amount, "");
        emit ResourcesMinted(to, tokenId, amount);
    }

    // ─── Mint equipment NFT ───────────────────────────────────────────────────
    /// @notice Mint a unique equipment piece and register its metadata.
    function mintEquipment(address to, string calldata equipName, uint8 tier, uint256 power)
        external
        onlyRole(MINTER_ROLE)
        returns (uint256 tokenId)
    {
        tokenId = _nextEquipmentId++;
        equipment[tokenId] = Equipment({name: equipName, tier: tier, power: power});
        _mint(to, tokenId, 1, "");
        emit EquipmentRegistered(tokenId, equipName, tier);
    }

    // ─── Burn (called by CraftingEngine) ──────────────────────────────────────
    function burn(address from, uint256 tokenId, uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(from, tokenId, amount);
    }

    function burnBatch(address from, uint256[] calldata ids, uint256[] calldata amounts)
        external
        onlyRole(BURNER_ROLE)
    {
        _burnBatch(from, ids, amounts);
    }

    // ─── URI ──────────────────────────────────────────────────────────────────
    function uri(uint256 tokenId) public view override returns (string memory) {
        return string(abi.encodePacked(_baseURI, tokenId.toString(), ".json"));
    }

    function setBaseURI(string calldata newURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _baseURI = newURI;
    }

    // ─── Supports interface ───────────────────────────────────────────────────
    function supportsInterface(bytes4 interfaceId) public view override(ERC1155, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
