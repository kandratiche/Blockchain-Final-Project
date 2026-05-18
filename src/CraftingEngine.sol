// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./GameItems.sol";

/// @title CraftingEngine
/// @notice Burns fungible resources according to a DAO-defined recipe and mints
///         an equipment NFT through GameItems. Both the recipe set and the flat
///         MANA crafting fee are governed by the DAO through DAO_ROLE.
/// @dev    Design patterns: Access Control (DAO_ROLE), Reentrancy Guard,
///         Checks-Effects-Interactions, Pausable / Circuit Breaker.
contract CraftingEngine is AccessControl, ReentrancyGuard, Pausable {
    // ─── Roles ────────────────────────────────────────────────────────────────
    /// @notice Held by the Timelock; controls recipes and the crafting fee.
    bytes32 public constant DAO_ROLE = keccak256("DAO_ROLE");
    /// @notice Allowed to pause/unpause crafting in an emergency.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ─── External contracts ───────────────────────────────────────────────────
    GameItems public immutable items;

    // ─── Recipe storage ───────────────────────────────────────────────────────
    struct Recipe {
        uint256[] resourceIds; // GameItems resource IDs (1-3) to burn
        uint256[] resourceAmounts; // amount of each resource to burn
        string outputName; // name of the crafted equipment
        uint8 outputTier; // 1 common .. 5 legendary
        uint256 outputPower; // power stat of the crafted equipment
        bool exists;
    }

    /// @dev Private — the public getter cannot return the dynamic arrays.
    mapping(uint256 => Recipe) private _recipes;

    /// @notice Flat MANA amount burned on every craft. DAO-governed.
    uint256 public manaFee;

    // ─── Events ───────────────────────────────────────────────────────────────
    event RecipeCreated(uint256 indexed recipeId, string outputName, uint8 tier);
    event RecipeUpdated(uint256 indexed recipeId);
    event RecipeRemoved(uint256 indexed recipeId);
    event ManaFeeUpdated(uint256 newFee);
    event Crafted(address indexed player, uint256 indexed recipeId, uint256 equipmentTokenId);

    /// @param itemsContract_ deployed GameItems address
    /// @param dao_           address granted DAO_ROLE + admin (the Timelock)
    /// @param manaFee_       initial flat MANA crafting fee
    constructor(address itemsContract_, address dao_, uint256 manaFee_) {
        require(itemsContract_ != address(0) && dao_ != address(0), "Crafting: zero address");
        items = GameItems(itemsContract_);
        manaFee = manaFee_;
        _grantRole(DEFAULT_ADMIN_ROLE, dao_);
        _grantRole(DAO_ROLE, dao_);
        _grantRole(PAUSER_ROLE, dao_);
    }

    // ─── Views ────────────────────────────────────────────────────────────────
    /// @notice Returns the full recipe struct including its dynamic arrays.
    function getRecipe(uint256 recipeId) external view returns (Recipe memory) {
        return _recipes[recipeId];
    }

    function recipeExists(uint256 recipeId) external view returns (bool) {
        return _recipes[recipeId].exists;
    }

    // ─── DAO: recipe management ───────────────────────────────────────────────
    /// @notice Register a new crafting recipe.
    function createRecipe(
        uint256 recipeId,
        uint256[] calldata resourceIds,
        uint256[] calldata resourceAmounts,
        string calldata outputName,
        uint8 outputTier,
        uint256 outputPower
    ) external onlyRole(DAO_ROLE) {
        require(!_recipes[recipeId].exists, "Crafting: recipe exists");
        _validate(resourceIds, resourceAmounts, outputTier);

        _recipes[recipeId] = Recipe({
            resourceIds: resourceIds,
            resourceAmounts: resourceAmounts,
            outputName: outputName,
            outputTier: outputTier,
            outputPower: outputPower,
            exists: true
        });
        emit RecipeCreated(recipeId, outputName, outputTier);
    }

    /// @notice Overwrite an existing recipe's inputs and output.
    function updateRecipe(
        uint256 recipeId,
        uint256[] calldata resourceIds,
        uint256[] calldata resourceAmounts,
        string calldata outputName,
        uint8 outputTier,
        uint256 outputPower
    ) external onlyRole(DAO_ROLE) {
        require(_recipes[recipeId].exists, "Crafting: no recipe");
        _validate(resourceIds, resourceAmounts, outputTier);

        _recipes[recipeId] = Recipe({
            resourceIds: resourceIds,
            resourceAmounts: resourceAmounts,
            outputName: outputName,
            outputTier: outputTier,
            outputPower: outputPower,
            exists: true
        });
        emit RecipeUpdated(recipeId);
    }

    /// @notice Delete a recipe so it can no longer be crafted.
    function removeRecipe(uint256 recipeId) external onlyRole(DAO_ROLE) {
        require(_recipes[recipeId].exists, "Crafting: no recipe");
        delete _recipes[recipeId];
        emit RecipeRemoved(recipeId);
    }

    /// @notice Update the flat MANA crafting fee.
    function setManaFee(uint256 newFee) external onlyRole(DAO_ROLE) {
        manaFee = newFee;
        emit ManaFeeUpdated(newFee);
    }

    // ─── Circuit breaker ──────────────────────────────────────────────────────
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // ─── Player entry point ───────────────────────────────────────────────────
    /// @notice Craft a recipe: burns the MANA fee + recipe inputs, mints output.
    /// @dev    Checks-Effects-Interactions — every state change is a burn/mint on
    ///         GameItems which is role-gated; nonReentrant added for defence.
    function craft(uint256 recipeId) external nonReentrant whenNotPaused returns (uint256 equipmentTokenId) {
        Recipe storage r = _recipes[recipeId];
        require(r.exists, "Crafting: invalid recipe");

        // Burn the flat MANA fee (if any).
        if (manaFee > 0) {
            items.burn(msg.sender, items.MANA(), manaFee);
        }
        // Burn the recipe's resource inputs.
        items.burnBatch(msg.sender, r.resourceIds, r.resourceAmounts);
        // Mint the crafted equipment NFT to the player.
        equipmentTokenId = items.mintEquipment(msg.sender, r.outputName, r.outputTier, r.outputPower);

        emit Crafted(msg.sender, recipeId, equipmentTokenId);
    }

    // ─── Internal ─────────────────────────────────────────────────────────────
    function _validate(uint256[] calldata resourceIds, uint256[] calldata resourceAmounts, uint8 outputTier)
        private
        pure
    {
        require(resourceIds.length == resourceAmounts.length, "Crafting: length mismatch");
        require(resourceIds.length > 0, "Crafting: empty recipe");
        require(outputTier >= 1 && outputTier <= 5, "Crafting: bad tier");
        for (uint256 i = 0; i < resourceIds.length; i++) {
            require(resourceIds[i] >= 1 && resourceIds[i] <= 3, "Crafting: not a resource");
            require(resourceAmounts[i] > 0, "Crafting: zero amount");
        }
    }
}
