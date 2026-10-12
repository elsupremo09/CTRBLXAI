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
	isFreeBundle: boolean?, -- DB-verified 0 R$ bundle (ugc_rules 57); see the FREE block below
	skipRecheck: boolean?, -- known permanently free: check once to learn its type, then never re-verify sale status
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
UGCCatalogData.ENEMY_ITEMS_PER_ENEMY = 3
UGCCatalogData.ENEMY_DISTINCT_ITEMS_PER_BATTLE = 12

-- FIT BLOCKLIST (manual): item IDs that attach/scale badly on the caged body.
-- A blocked item stays owned and in the catalog, but is never WORN (skipped in
-- dress-up ApplyLook and in enemy-outfit pool building). Add an entry id (the
-- catalog key) you have seen misfit in Studio. Roblox exposes no fit flag, so
-- this is identified by eye, not detected. Empty = nothing blocked.
UGCCatalogData.FIT_BLOCKLIST = table.freeze({
	-- [1234567890] = true, -- example: "Name" — reason it misfits
})

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

-- Price filter bands (Robux), user decision 2026-10-12. Order = dropdown order.
-- A price of 0 is "Free"; nil (not yet price-checked) has no band and is excluded
-- from a band filter and sorted last by the price sort.
UGCCatalogData.PRICE_BANDS = table.freeze({ "Free", "1-50", "51-100", "101-250", "250+" })
UGCCatalogData.PRICE_BAND_LABELS = table.freeze({
	Free = "Free", ["1-50"] = "1-50 R$", ["51-100"] = "51-100 R$",
	["101-250"] = "101-250 R$", ["250+"] = "250+ R$",
})
-- Map a Robux price to its band id. nil price -> nil (unknown).
function UGCCatalogData.PriceBandOf(price: number?): string?
	if type(price) ~= "number" then return nil end
	if price <= 0 then return "Free" end
	if price <= 50 then return "1-50" end
	if price <= 100 then return "51-100" end
	if price <= 250 then return "101-250" end
	return "250+"
end

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
-- Mirrors the 34 'Test 2026-10-09' rows + 49 'Free 2026-10-09' rows (83; Designer-verified on sale, not Limited).
-- The PLACEHOLDER row was removed from the DB. Rent price is NOT per item: the
-- server computes it at runtime (RENT_BASE_BATTLE_RATIO x avg battle gold x
-- RENT_ESCALATION^paid rentals). Add new entries to the DB first, then here:
--   [assetId] = table.freeze({ assetId = assetId, name = "...", slot = "Hat" }),
-- Paired shoes (both parts; add bundleId if the pair is sold as a bundle):
--   [leftId] = table.freeze({ assetId = leftId, assetId2 = rightId, bundleId = nil,
--       name = "...", slot = "Shoes" }),
--------------------------------------------------

UGCCatalogData.Items = table.freeze({
	-- Hat (7)
	[5231223671] = table.freeze({ assetId = 5231223671, name = "Black Tophead", slot = "Hat" }),
	[6869986319] = table.freeze({ assetId = 6869986319, name = "Devil Straw Samurai Hat", slot = "Hat" }),
	[5316615598] = table.freeze({ assetId = 5316615598, name = "Rainbow Fashion Hood", slot = "Hat" }),
	[6441016373] = table.freeze({ assetId = 6441016373, name = "Goth Beanie", slot = "Hat" }),
	[7485912398] = table.freeze({ assetId = 7485912398, name = "Black Jewelled Horns of the Abyss", slot = "Hat" }),
	[7676195837] = table.freeze({ assetId = 7676195837, name = "Black Spikey Batphones", slot = "Hat" }),
	[17225320544] = table.freeze({ assetId = 17225320544, name = "Black Goth Captain Hat", slot = "Hat" }),
	-- Hair (4)
	[6501746646] = table.freeze({ assetId = 6501746646, name = "Popular Girl Blonde & Brown Hair", slot = "Hair" }),
	[7141674388] = table.freeze({ assetId = 7141674388, name = "Black Cat Ears Hairstyle", slot = "Hair" }),
	[14892162637] = table.freeze({ assetId = 14892162637, name = "Fluffy Messy Hair(Black)", slot = "Hair" }),
	[5945436918] = table.freeze({ assetId = 5945436918, name = "Light Brown Ethereal Hairstyle", slot = "Hair" }),
	-- Torso (7)
	[11168616115] = table.freeze({ assetId = 11168616115, name = "Kitty Paw Oversized Hoodie Black", slot = "Torso" }),
	[14399259123] = table.freeze({ assetId = 14399259123, name = "suit", slot = "Torso" }),
	[92878061462559] = table.freeze({ assetId = 92878061462559, name = "adidas Dark Tactical Bandit Top", slot = "Torso" }),
	[132330253223450] = table.freeze({ assetId = 132330253223450, name = "black blouse", slot = "Torso" }),
	[17409238119] = table.freeze({ assetId = 17409238119, name = "Black Crop Top w/ Silver Cross Necklace", slot = "Torso" }),
	[112473710435106] = table.freeze({ assetId = 112473710435106, name = "Money Spread", slot = "Torso" }),
	[13146393006] = table.freeze({ assetId = 13146393006, name = "Demon Warrior Top Nezuko Brown & Pink", slot = "Torso" }),
	-- Back (5)
	[6472661790] = table.freeze({ assetId = 6472661790, name = "Black Feather Void Wings [Dark]", slot = "Back" }),
	[106690045] = table.freeze({ assetId = 106690045, name = "Classic Swordpack Throwback", slot = "Back" }),
	[8210597039] = table.freeze({ assetId = 8210597039, name = "Simple Backpack", slot = "Back" }),
	[8528038968] = table.freeze({ assetId = 8528038968, name = "Rococo Back Bustle Black", slot = "Back" }),
	[4998594674] = table.freeze({ assetId = 4998594674, name = "Dark Energy Wings", slot = "Back" }),
	-- Pants (5)
	[11433864064] = table.freeze({ assetId = 11433864064, name = "Cyber Midnight Storm Leg Warmers", slot = "Pants" }),
	[126490351689789] = table.freeze({ assetId = 126490351689789, name = "Y2K Black Cargo Pants with Strap 🫐", slot = "Pants" }),
	[18539653755] = table.freeze({ assetId = 18539653755, name = "Black Metal Cross Y2K Cargo Pants w/ Shoes", slot = "Pants" }),
	[16018769188] = table.freeze({ assetId = 16018769188, name = "Red Smoke Pants", slot = "Pants" }),
	[10268635618] = table.freeze({ assetId = 10268635618, name = "Tactical Techwear Pants Black", slot = "Pants" }),
	-- Shoes (6)
	[9614836327] = table.freeze({ assetId = 9614836327, assetId2 = 9614841343, bundleId = 930, name = "Military Boots - Black", slot = "Shoes" }),
	[74352056391317] = table.freeze({ assetId = 74352056391317, assetId2 = 79490579438209, bundleId = 11581496332237, name = "Boots Black Leather Winter Work Heel Military Y2K", slot = "Shoes" }),
	[89438115872840] = table.freeze({ assetId = 89438115872840, assetId2 = 89894672120441, bundleId = 7122370145429, name = "Monster slippers [Black]", slot = "Shoes" }),
	[128723411408193] = table.freeze({ assetId = 128723411408193, assetId2 = 91980022625401, bundleId = 150855766684661, name = "Mega Metal Spikey Goth Boots", slot = "Shoes" }),
	[104998042533502] = table.freeze({ assetId = 104998042533502, assetId2 = 116692639426912, bundleId = 259439490219926, name = "Chunky Lace Up Platform Boots w/ Leg Bands - Black", slot = "Shoes" }),
	[103759225227074] = table.freeze({ assetId = 103759225227074, assetId2 = 102152144856557, bundleId = 234855471229439, name = "✅Goth✅", slot = "Shoes" }),
	-- FREE (49 'Free 2026-10-09' rows, Designer-verified 0 R$, on sale, not Limited, made by Roblox).
	-- Free is decided at RUNTIME from the live price (UGCOutfitService), never from this list,
	-- except isFreeBundle: in-game bundle info has no sale-status field, so a price of 0 can't be
	-- told apart from "no price"; this DB-verified hint + a live price of exactly 0 = free (ugc_rules 57).
	-- Hair (free)
	[7193442167] = table.freeze({ skipRecheck = true, assetId = 7193442167, name = "Pony Tail - Black", slot = "Hair" }),
	[6993754725] = table.freeze({ skipRecheck = true, assetId = 6993754725, name = "Straight Bangs - Black", slot = "Hair" }),
	[9244111257] = table.freeze({ skipRecheck = true, assetId = 9244111257, name = "Wavy Middle Part - Black", slot = "Hair" }),
	[9244095135] = table.freeze({ skipRecheck = true, assetId = 9244095135, name = "Pony Tail - Blonde", slot = "Hair" }),
	[7193444640] = table.freeze({ skipRecheck = true, assetId = 7193444640, name = "Pony Tail - Red", slot = "Hair" }),
	[9244097555] = table.freeze({ skipRecheck = true, assetId = 9244097555, name = "Pony Tail - Brown", slot = "Hair" }),
	[7193455510] = table.freeze({ skipRecheck = true, assetId = 7193455510, name = "Braided Hair - Red", slot = "Hair" }),
	[9244148336] = table.freeze({ skipRecheck = true, assetId = 9244148336, name = "Braided Hair - Blonde", slot = "Hair" }),
	[9244060144] = table.freeze({ skipRecheck = true, assetId = 9244060144, name = "Top Knot - Brown", slot = "Hair" }),
	[9244057408] = table.freeze({ skipRecheck = true, assetId = 9244057408, name = "Top Knot - Blonde", slot = "Hair" }),
	[7193454569] = table.freeze({ skipRecheck = true, assetId = 7193454569, name = "Braided Hair - Black", slot = "Hair" }),
	[9244150641] = table.freeze({ skipRecheck = true, assetId = 9244150641, name = "Braided Hair - Cool Brown", slot = "Hair" }),
	-- Torso (free)
	[9240757332] = table.freeze({ skipRecheck = true, assetId = 9240757332, name = "Knit Sweater - Black", slot = "Torso" }),
	[7192553841] = table.freeze({ skipRecheck = true, assetId = 7192553841, name = "Zip Hoodie - Black", slot = "Torso" }),
	[9240752338] = table.freeze({ skipRecheck = true, assetId = 9240752338, name = "Tie-Front Top - White", slot = "Torso" }),
	[8648380153] = table.freeze({ skipRecheck = true, assetId = 8648380153, name = "Trench Coat - White", slot = "Torso" }),
	[7192549218] = table.freeze({ skipRecheck = true, assetId = 7192549218, name = "Leather Jacket - Black", slot = "Torso" }),
	[9120031517] = table.freeze({ skipRecheck = true, assetId = 9120031517, name = "Baseball Long Sleeve - B&W", slot = "Torso" }),
	[8516609675] = table.freeze({ skipRecheck = true, assetId = 8516609675, name = "Denim Jacket - Light Wash", slot = "Torso" }),
	[9112474888] = table.freeze({ skipRecheck = true, assetId = 9112474888, name = "Basic T-Shirt - Gray", slot = "Torso" }),
	[6984769289] = table.freeze({ skipRecheck = true, assetId = 6984769289, name = "Knit Sweater - Beige", slot = "Torso" }),
	[8516620262] = table.freeze({ skipRecheck = true, assetId = 8516620262, name = "Hooded Jacket - Gray", slot = "Torso" }),
	[7178740556] = table.freeze({ skipRecheck = true, assetId = 7178740556, name = "Baseball Long Sleeve - Red", slot = "Torso" }),
	[8648389231] = table.freeze({ skipRecheck = true, assetId = 8648389231, name = "Zip Hoodie - Teal", slot = "Torso" }),
	[9240758221] = table.freeze({ skipRecheck = true, assetId = 9240758221, name = "Knit Sweater - Gray", slot = "Torso" }),
	[8516612751] = table.freeze({ skipRecheck = true, assetId = 8516612751, name = "Denim Jacket - White", slot = "Torso" }),
	[7178737816] = table.freeze({ skipRecheck = true, assetId = 7178737816, name = "Roblox T-Shirt - White", slot = "Torso" }),
	[6984765766] = table.freeze({ skipRecheck = true, assetId = 6984765766, name = "Zip Hoodie - Orange", slot = "Torso" }),
	[8648397446] = table.freeze({ skipRecheck = true, assetId = 8648397446, name = "Parka - Brown", slot = "Torso" }),
	[9119670803] = table.freeze({ skipRecheck = true, assetId = 9119670803, name = "Striped T-Shirt - Black", slot = "Torso" }),
	[7192546798] = table.freeze({ skipRecheck = true, assetId = 7192546798, name = "Collared Leather Jacket - White", slot = "Torso" }),
	[9112483644] = table.freeze({ skipRecheck = true, assetId = 9112483644, name = "Striped T-Shirt - White", slot = "Torso" }),
	[7192547628] = table.freeze({ skipRecheck = true, assetId = 7192547628, name = "Collared Leather Jacket - Brown", slot = "Torso" }),
	[8516648620] = table.freeze({ skipRecheck = true, assetId = 8516648620, name = "Business Coat - Striped Gray", slot = "Torso" }),
	[6984767443] = table.freeze({ skipRecheck = true, assetId = 6984767443, name = "Leather Jacket - Brown", slot = "Torso" }),
	[8516655378] = table.freeze({ skipRecheck = true, assetId = 8516655378, name = "Business Coat - Salmon", slot = "Torso" }),
	-- Pants (free)
	[6984763785] = table.freeze({ skipRecheck = true, assetId = 6984763785, name = "Casual Sweats - Black", slot = "Pants" }),
	[9120251003] = table.freeze({ skipRecheck = true, assetId = 9120251003, name = "Wetsuit Pants - Black", slot = "Pants" }),
	[7192664790] = table.freeze({ skipRecheck = true, assetId = 7192664790, name = "Casual Sweats - Gray", slot = "Pants" }),
	[6984740059] = table.freeze({ skipRecheck = true, assetId = 6984740059, name = "Cargo Pants - Brown", slot = "Pants" }),
	[7192681239] = table.freeze({ skipRecheck = true, assetId = 7192681239, name = "Textured Leather Pants - White", slot = "Pants" }),
	[9174391966] = table.freeze({ skipRecheck = true, assetId = 9174391966, name = "Bermuda Shorts - Black", slot = "Pants" }),
	[7192685245] = table.freeze({ skipRecheck = true, assetId = 7192685245, name = "Floral Swim Trunks - Blue", slot = "Pants" }),
	[8721985925] = table.freeze({ skipRecheck = true, assetId = 8721985925, name = "Motorcycle Pants - Brown", slot = "Pants" }),
	[9274635732] = table.freeze({ skipRecheck = true, assetId = 9274635732, name = "Floral Swim Trunks - White", slot = "Pants" }),
	-- Shoes (free)
	[7193165925] = table.freeze({ skipRecheck = true, assetId = 7193165925, assetId2 = 7193166879, bundleId = 872, isFreeBundle = true, name = "Roblox Sneakers - Gray", slot = "Shoes" }),
	[9482987287] = table.freeze({ skipRecheck = true, assetId = 9482987287, assetId2 = 9482991343, bundleId = 896, isFreeBundle = true, name = "Sneakers - White", slot = "Shoes" }),
	[9481782649] = table.freeze({ skipRecheck = true, assetId = 9481782649, assetId2 = 9481786623, bundleId = 894, isFreeBundle = true, name = "Canvas Shoes - White", slot = "Shoes" }),
	[9483690316] = table.freeze({ skipRecheck = true, assetId = 9483690316, assetId2 = 9483697460, bundleId = 905, isFreeBundle = true, name = "Canvas Shoes - Gray", slot = "Shoes" }),
} :: { [number]: UGCItem })

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
