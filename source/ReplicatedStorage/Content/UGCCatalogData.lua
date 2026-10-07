--!strict
-- UGCCatalogData.lua
-- CTRBLXAI | UGC Rental & Ownership — data mirror of CTRBLXAI.db (2026-10-07)
--   ugc_rules, ugc_slots, ugc_race_slot_blocks, ugc_catalog
--
-- DATA ONLY (ARC-003, DAT-003): no game logic lives here. Server services
-- (UGCService / UGCOutfitService) decide everything; the client may read slot and
-- item names for display only. Change values in the DB first (Designer agent),
-- then mirror them here. Frozen (DAT-002).

export type UGCItem = {
	assetId: number,
	name: string,
	slot: string, -- one of SLOTS
}

local UGCCatalogData = {}

--------------------------------------------------
-- RULE VALUES (ugc_rules)
--------------------------------------------------

-- Try-On / free_tryon_battles (Locked). Once per item, ever; any number of items
-- may be on trial at the same time (user decision 2026-10-07). Not a rental.
UGCCatalogData.TRIAL_BATTLES = 5

-- Rental / rental_duration_battles (Locked). Per rental.
UGCCatalogData.RENT_BATTLES = 30

-- Rental / rental_base_battle_ratio (PROVISIONAL): base price = ratio x average
-- battle gold at the player's current level.
UGCCatalogData.RENT_BASE_BATTLE_RATIO = 10

-- Rental / rental_price_escalation (Locked): price = base x 2^(previous paid
-- rentals of THAT item, per player). Never resets. No rental cap.
UGCCatalogData.RENT_ESCALATION = 2

-- Wishlist / wishlist_cap (Locked) + exact block message.
UGCCatalogData.WISHLIST_CAP = 50
UGCCatalogData.WISHLIST_FULL_MESSAGE = "Wishlist full (50)"

-- Enemy Outfits (PROVISIONAL until the mobile Render Stats test).
UGCCatalogData.ENEMY_ITEMS_PER_ENEMY = 2
UGCCatalogData.ENEMY_DISTINCT_ITEMS_PER_BATTLE = 4

--------------------------------------------------
-- SLOTS (ugc_slots, sort_order)
--------------------------------------------------

UGCCatalogData.SLOTS = table.freeze({
	"Hat", "Hair", "Face", "Neck", "Shoulder", "Front",
	"Back", "Waist", "Shirt", "Pants", "Shoes",
})

local slotSet: { [string]: boolean } = {}
for _, slot in UGCCatalogData.SLOTS do
	slotSet[slot] = true
end
UGCCatalogData.SLOT_SET = table.freeze(slotSet)

-- Roblox Enum.AssetType names allowed in each slot. The server checks the
-- catalog entry against MarketplaceService:GetProductInfo().AssetTypeId and
-- rejects mismatches (fail closed). Platform mapping — ugc_slots notes only say
-- "Roblox accessory/clothing category"; Designer to mirror this list in the DB.
UGCCatalogData.SLOT_ASSET_TYPES = table.freeze({
	Hat      = table.freeze({ "Hat" }),
	Hair     = table.freeze({ "HairAccessory" }),
	Face     = table.freeze({ "FaceAccessory" }),
	Neck     = table.freeze({ "NeckAccessory" }),
	Shoulder = table.freeze({ "ShoulderAccessory" }),
	Front    = table.freeze({ "FrontAccessory" }),
	Back     = table.freeze({ "BackAccessory" }),
	Waist    = table.freeze({ "WaistAccessory" }),
	Shirt    = table.freeze({ "Shirt", "TShirtAccessory", "ShirtAccessory", "JacketAccessory", "SweaterAccessory" }),
	Pants    = table.freeze({ "Pants", "PantsAccessory", "ShortsAccessory", "DressSkirtAccessory" }),
	Shoes    = table.freeze({ "LeftShoeAccessory", "RightShoeAccessory" }),
})

--------------------------------------------------
-- RACE SLOT BLOCKS (ugc_race_slot_blocks — ALL PROVISIONAL, cosmetic only)
-- Keyed by race NAME (RaceData.Races[*].name), not by tag: Froc is Amphibious
-- but has legs.
--------------------------------------------------

UGCCatalogData.RACE_SLOT_BLOCKS = table.freeze({
	Fairy   = table.freeze({ Back = true }),                            -- id 1: wings occupy back
	Avian   = table.freeze({ Back = true }),                            -- id 2: wings occupy back
	Mermaid = table.freeze({ Pants = true, Shoes = true, Waist = true }), -- id 3-5: tail replaces legs
	Treant  = table.freeze({ Hair = true }),                            -- id 6: PLACEHOLDER foliage head
})

--------------------------------------------------
-- CURATED CATALOG (ugc_catalog)
-- The DB currently holds only a 'PLACEHOLDER' row (not a real asset), so the
-- live catalog is EMPTY. Add real on-sale entries to the DB first, then here:
--   [assetId] = table.freeze({ assetId = assetId, name = "...", slot = "Hat" }),
--------------------------------------------------

UGCCatalogData.Items = table.freeze({} :: { [number]: UGCItem })

return table.freeze(UGCCatalogData)
