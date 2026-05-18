// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import "./GameItems.sol";

/// @title LootVRF
/// @notice Players spend $MANA to request a loot drop.
///         Chainlink VRF returns randomness; contract resolves the drop table
///         and mints items via GameItems.
///         Drop weights are settable by DAO (owner).
contract LootVRF is VRFConsumerBaseV2Plus {
    // ─── Chainlink VRF config ─────────────────────────────────────────────────
    IVRFCoordinatorV2Plus public immutable coordinator;
    uint256 public subscriptionId;
    bytes32 public keyHash;
    uint32 public callbackGasLimit = 200_000;
    uint16 public requestConfirmations = 3;
    uint32 public constant NUM_WORDS = 1;

    // ─── External contracts ───────────────────────────────────────────────────
    GameItems public immutable items;

    // ─── Drop table ───────────────────────────────────────────────────────────
    /// @dev Weights sum must equal 10_000 (basis points).
    ///      Each entry = (tokenId, weight, minAmount, maxAmount)
    struct DropEntry {
        uint256 tokenId; // GameItems token ID
        uint16 weight; // weight in basis points
        uint64 minAmt;
        uint64 maxAmt;
        bool isEquip; // if true, mint as equipment NFT
    }
    DropEntry[] public dropTable;
    uint16 public totalWeight; // should always be 10_000

    // ─── Pending requests ─────────────────────────────────────────────────────
    struct Request {
        address player;
        bool fulfilled;
    }
    mapping(uint256 => Request) public requests;

    // ─── Cost ─────────────────────────────────────────────────────────────────
    uint256 public manaCost; // $MANA tokens burned per loot roll

    // ─── Events ───────────────────────────────────────────────────────────────
    event LootRequested(uint256 indexed requestId, address indexed player);
    event LootFulfilled(uint256 indexed requestId, address indexed player, uint256 tokenId, uint256 amount);
    event DropTableUpdated();

    constructor(
        address vrfCoordinator_,
        address itemsContract_,
        uint256 subscriptionId_,
        bytes32 keyHash_,
        uint256 manaCost_,
        address admin_
    ) VRFConsumerBaseV2Plus(vrfCoordinator_) {
        if (admin_ != address(0) && admin_ != msg.sender) {
            transferOwnership(admin_);
        }
        coordinator = IVRFCoordinatorV2Plus(vrfCoordinator_);
        items = GameItems(itemsContract_);
        subscriptionId = subscriptionId_;
        keyHash = keyHash_;
        manaCost = manaCost_;

        // Default drop table (DAO can override via setDropTable)
        _initDefaultDropTable();
    }

    // ─── Player entry point ───────────────────────────────────────────────────
    /// @notice Burn MANA and request a random loot drop.
    function requestLoot() external returns (uint256 requestId) {
        // Burn $MANA from caller (caller must have approved this contract)
        items.burn(msg.sender, items.MANA(), manaCost);

        requestId = coordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
            })
        );

        requests[requestId] = Request({player: msg.sender, fulfilled: false});
        emit LootRequested(requestId, msg.sender);
    }

    // ─── VRF callback ─────────────────────────────────────────────────────────
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        Request storage req = requests[requestId];
        require(!req.fulfilled, "LootVRF: already fulfilled");
        req.fulfilled = true;

        uint256 roll = randomWords[0] % 10_000; // 0 – 9999
        (uint256 tokenId, uint256 amount, bool isEquip) = _resolveRoll(roll, randomWords[0]);

        if (isEquip) {
            // Mint a named equipment piece; tier derived from roll bucket
            uint8 tier = _rollToTier(roll);
            items.mintEquipment(req.player, _tierName(tier), tier, roll % 100 + 1);
        } else {
            items.mintResource(req.player, tokenId, amount);
        }

        emit LootFulfilled(requestId, req.player, tokenId, amount);
    }

    // ─── Internal helpers ─────────────────────────────────────────────────────
    function _resolveRoll(uint256 roll, uint256 seed)
        internal
        view
        returns (uint256 tokenId, uint256 amount, bool isEquip)
    {
        uint16 cumulative = 0;
        for (uint256 i = 0; i < dropTable.length; i++) {
            cumulative += dropTable[i].weight;
            if (roll < cumulative) {
                DropEntry memory e = dropTable[i];
                uint256 range = e.maxAmt - e.minAmt + 1;
                amount = (range == 0) ? e.minAmt : (seed % range) + e.minAmt;
                tokenId = e.tokenId;
                isEquip = e.isEquip;
                return (tokenId, amount, isEquip);
            }
        }
        // Fallback: small IRON drop
        return (items.IRON(), 1, false);
    }

    function _rollToTier(uint256 roll) internal pure returns (uint8) {
        if (roll < 100) return 5; // Legendary  1 %
        if (roll < 500) return 4; // Epic        4 %
        if (roll < 1500) return 3; // Rare       10 %
        if (roll < 4000) return 2; // Uncommon   25 %
        return 1; // Common     60 %
    }

    function _tierName(uint8 tier) internal pure returns (string memory) {
        if (tier == 5) return "Legendary Sword";
        if (tier == 4) return "Epic Shield";
        if (tier == 3) return "Rare Staff";
        if (tier == 2) return "Uncommon Helm";
        return "Common Dagger";
    }

    function _initDefaultDropTable() internal {
        // 60 % IRON resource, 20 % WOOD, 10 % MANA, 10 % Equipment NFT
        dropTable.push(DropEntry({tokenId: 1, weight: 6000, minAmt: 5, maxAmt: 20, isEquip: false}));
        dropTable.push(DropEntry({tokenId: 2, weight: 2000, minAmt: 3, maxAmt: 10, isEquip: false}));
        dropTable.push(DropEntry({tokenId: 3, weight: 1000, minAmt: 1, maxAmt: 5, isEquip: false}));
        dropTable.push(DropEntry({tokenId: 0, weight: 1000, minAmt: 1, maxAmt: 1, isEquip: true}));
        totalWeight = 10_000;
    }

    // ─── DAO-controlled setters ───────────────────────────────────────────────
    /// @notice Replace the entire drop table. Callable by owner (DAO).
    function setDropTable(DropEntry[] calldata entries) external onlyOwner {
        delete dropTable;
        uint16 sum = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            dropTable.push(entries[i]);
            sum += entries[i].weight;
        }
        require(sum == 10_000, "LootVRF: weights must sum to 10000");
        totalWeight = sum;
        emit DropTableUpdated();
    }

    function setManaCost(uint256 newCost) external onlyOwner {
        manaCost = newCost;
    }

    function setCallbackGasLimit(uint32 limit) external onlyOwner {
        callbackGasLimit = limit;
    }
}
