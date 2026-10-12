--!strict
-- UGCCatalogData.lua
-- CTRBLXAI | UGC Rental & Ownership — data mirror of CTRBLXAI.db (2026-10-08)
--   ugc_rules, ugc_slots, ugc_race_slot_blocks, ugc_catalog
--
-- DATA ONLY (ARC-003, DAT-003): no game logic lives here. Server services
-- (UGCService / UGCOutfitService) decide everything; the client may read slot and
-- item names for display only. Change values in the DB first (Designer agent),
-- then mirror them here. Frozen (DAT-002).

-- One catalog ENTRY is keyed by its primary asset id (ugc_catalog.asset_id).
-- Paired items (ugc_rules paired_items, id 51): shoes and any L/R pair carry a
-- second part (ugc_catalog.asset_id_2) and/or a bundle (ugc_catalog.bundle_id).
-- Both parts are worn together and the entry counts as owned only if BOTH are.
export type UGCItem = {
	assetId: number,   -- ugc_catalog.asset_id (entry key, first part)
	name: string,
	slot: string, -- one of SLOTS
	assetId2: number?, -- ugc_catalog.asset_id_2 (second part of an L/R pair)
	bundleId: number?, -- ugc_catalog.bundle_id (bought with the bundle prompt)
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

-- Cart / cart_cap (id 30, Locked 2026-10-08) + exact block message. Replaces the
-- 2026-10-07 wishlist (same cap). Saved across sessions (cart_persistence, id 46).
UGCCatalogData.CART_CAP = 50
UGCCatalogData.CART_FULL_MESSAGE = "Cart full (50)"

-- Availability / availability_pool_refresh (id 49, PROVISIONAL): every curated
-- item's on-sale status is re-verified in the background about this often.
UGCCatalogData.AVAILABILITY_REFRESH_SECONDS = 600

-- Enemy Outfits (PROVISIONAL until the mobile Render Stats test).
UGCCatalogData.ENEMY_ITEMS_PER_ENEMY = 2
UGCCatalogData.ENEMY_DISTINCT_ITEMS_PER_BATTLE = 4

--------------------------------------------------
-- SLOTS (ugc_slots, sort_order)
--------------------------------------------------

-- Reduced to 6 kinds (user ruling 2026-10-08; may expand later).
UGCCatalogData.SLOTS = table.freeze({
	"Hat", "Hair", "Torso", "Back", "Pants", "Shoes",
})

local slotSet: { [string]: boolean } = {}
for _, slot in UGCCatalogData.SLOTS do
	slotSet[slot] = true
end
UGCCatalogData.SLOT_SET = table.freeze(slotSet)

-- Slot icons for the Outfit tab Worn list and Type filter (El_Pi0818, 2026-10-08).
UGCCatalogData.ALL_TYPES_ICON = "rbxassetid://87409616114560" -- Type filter "All types" (2026-10-08)
UGCCatalogData.SLOT_ICONS = table.freeze({
	Hat   = "rbxassetid://125260790005553",
	Hair  = "rbxassetid://95591462786130",
	Torso = "rbxassetid://109385103522000",
	Back  = "rbxassetid://111417618836315",
	Pants = "rbxassetid://136121390492820",
	Shoes = "rbxassetid://81092915600570",
})

-- Outfit tab / UGC merchant filters (loadout_ui_spec 69/70, Locked 2026-10-08).
-- Type groups cover all 11 slots. Weapon skin is NOT a Roblox Marketplace type
-- (loadout_ui_spec 71, Pending): no filter until that separate system exists.
-- Type filter = the 6 slots, same order and names as the Worn list (2026-10-08).
UGCCatalogData.FILTER_TYPES = UGCCatalogData.SLOTS
UGCCatalogData.SLOT_FILTER_TYPE = table.freeze({
	Hat = "Hat", Hair = "Hair", Torso = "Torso", Back = "Back", Pants = "Pants", Shoes = "Shoes",
})
-- Status filter: a trial counts as Rented (id 70); locked items have no status.
UGCCatalogData.STATUS_FILTERS = table.freeze({ "Permanent", "Rented", "OutOfUse" })
UGCCatalogData.STATUS_FILTER_LABELS = table.freeze({ Permanent = "Permanent", Rented = "Rented", OutOfUse = "Out of use" })
UGCCatalogData.STATUS_FILTER_OF = table.freeze({ owned = "Permanent", trial = "Rented", rent = "Rented", expired = "OutOfUse" })

-- Roblox Enum.AssetType names allowed in each slot. The server checks the
-- catalog entry against MarketplaceService:GetProductInfo().AssetTypeId and
-- rejects mismatches (fail closed). Platform mapping — ugc_slots notes only say
-- "Roblox accessory/clothing category"; Designer to mirror this list in the DB.
UGCCatalogData.SLOT_ASSET_TYPES = table.freeze({
	-- Hat: headgear, masks, full helms. Torso: shirts, jackets, armour, dresses.
	-- Neck/Shoulder/Waist accessory types are not equippable for now (2026-10-08).
	Hat   = table.freeze({ "Hat", "FaceAccessory" }),
	Hair  = table.freeze({ "HairAccessory" }),
	Torso = table.freeze({ "Shirt", "TShirtAccessory", "ShirtAccessory", "JacketAccessory",
		"SweaterAccessory", "DressSkirtAccessory", "FrontAccessory" }),
	Back  = table.freeze({ "BackAccessory" }),
	Pants = table.freeze({ "Pants", "PantsAccessory", "ShortsAccessory" }),
	Shoes = table.freeze({ "LeftShoeAccessory", "RightShoeAccessory" }),
})

--------------------------------------------------
-- RACE SLOT BLOCKS (ugc_race_slot_blocks — ALL PROVISIONAL, cosmetic only)
-- Keyed by race NAME (RaceData.Races[*].name), not by tag: Froc is Amphibious
-- but has legs.
--------------------------------------------------

UGCCatalogData.RACE_SLOT_BLOCKS = table.freeze({
	Fairy   = table.freeze({ Back = true }),                            -- id 1: wings occupy back
	Avian   = table.freeze({ Back = true }),                            -- id 2: wings occupy back
	Treant  = table.freeze({ Hair = true }),                            -- id 6: PLACEHOLDER foliage head
})

--------------------------------------------------
-- CURATED CATALOG (ugc_catalog)
-- The DB currently holds only a 'PLACEHOLDER' row (not a real asset), so the
-- live catalog is EMPTY. Add real on-sale entries to the DB first, then here:
--   [assetId] = table.freeze({ assetId = assetId, name = "...", slot = "Hat" }),
-- Paired shoes (both parts; add bundleId if the pair is sold as a bundle):
--   [leftId] = table.freeze({ assetId = leftId, assetId2 = rightId, bundleId = nil,
--       name = "...", slot = "Shoes" }),
--------------------------------------------------

UGCCatalogData.Items = table.freeze({} :: { [number]: UGCItem })

-- Lookup: any part asset id (asset_id or asset_id_2) -> catalog entry key.
-- Lets a purchase of either shoe resolve to its pair entry. Derived, not new data.
local entryByAsset: { [number]: number } = {}
for entryId, item in UGCCatalogData.Items do
	entryByAsset[item.assetId] = entryId
	if item.assetId2 then
		entryByAsset[item.assetId2] = entryId
	end
end
UGCCatalogData.ENTRY_BY_ASSET = table.freeze(entryByAsset)

return table.freeze(UGCCatalogData)
