// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

interface IGameItems {
    function burnBatch(
        address account,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external;
}

interface IEquipmentNFT {
    function mint(address to, uint256 tokenId) external;
}

contract CraftingEngine is AccessControl {
    bytes32 public constant DAO_ROLE = keccak256("DAO_ROLE");

    IGameItems public gameItems;
    IEquipmentNFT public equipmentNFT;

    struct Recipe {
        uint256[] resourceIds;
        uint256[] resourceAmounts;

        uint256 equipmentTokenId;

        bool exists;
    }

    mapping(uint256 => Recipe) public recipes;

    event RecipeCreated(uint256 indexed recipeId);
    event RecipeUpdated(uint256 indexed recipeId);

    event Crafted(
        address indexed player,
        uint256 indexed recipeId,
        uint256 equipmentTokenId
    );

    constructor(
        address _gameItems,
        address _equipmentNFT
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DAO_ROLE, msg.sender);

        gameItems = IGameItems(_gameItems);
        equipmentNFT = IEquipmentNFT(_equipmentNFT);
    }

    function createRecipe(
        uint256 recipeId,
        uint256[] calldata resourceIds,
        uint256[] calldata resourceAmounts,
        uint256 equipmentTokenId
    ) external onlyRole(DAO_ROLE) {
        require(!recipes[recipeId].exists, "Recipe already exists");

        require(
            resourceIds.length == resourceAmounts.length,
            "Array length mismatch"
        );

        recipes[recipeId] = Recipe({
            resourceIds: resourceIds,
            resourceAmounts: resourceAmounts,
            equipmentTokenId: equipmentTokenId,
            exists: true
        });

        emit RecipeCreated(recipeId);
    }

    function updateRecipe(
        uint256 recipeId,
        uint256[] calldata resourceIds,
        uint256[] calldata resourceAmounts,
        uint256 equipmentTokenId
    ) external onlyRole(DAO_ROLE) {
        require(recipes[recipeId].exists, "Recipe does not exist");

        require(
            resourceIds.length == resourceAmounts.length,
            "Array length mismatch"
        );

        recipes[recipeId] = Recipe({
            resourceIds: resourceIds,
            resourceAmounts: resourceAmounts,
            equipmentTokenId: equipmentTokenId,
            exists: true
        });

        emit RecipeUpdated(recipeId);
    }

    function craft(uint256 recipeId) external {
        Recipe storage recipe = recipes[recipeId];

        require(recipe.exists, "Invalid recipe");

        gameItems.burnBatch(
            msg.sender,
            recipe.resourceIds,
            recipe.resourceAmounts
        );

        equipmentNFT.mint(
            msg.sender,
            recipe.equipmentTokenId
        );

        emit Crafted(
            msg.sender,
            recipeId,
            recipe.equipmentTokenId
        );
    }

    function setGameItems(address _gameItems)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        gameItems = IGameItems(_gameItems);
    }

    function setEquipmentNFT(address _equipmentNFT)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        equipmentNFT = IEquipmentNFT(_equipmentNFT);
    }
}