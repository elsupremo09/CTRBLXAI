-- BonusData.lua
-- CTRBLXAI | Slice 4A — Equipment Foundation
-- Auto-generated from CTRBLXAI.db bonus_numerical_attributes + bonus_passives.
-- Do not edit manually. Regenerate from database.
--
-- Numerical attributes: tiered stat bonuses that can roll on items.
-- Bonus passives: rare mechanic-altering effects (max 1 per standard, 2 per 2H).

local BonusData = {}

--------------------------------------------------
-- RARITY HIERARCHY (for minimum_rarity checks)
--------------------------------------------------

BonusData.RARITY_ORDER = {
	Broken = 0, Common = 1, Uncommon = 2, Rare = 3,
	Epic = 4, Legendary = 5, Mythic = 6, Transcendent = 7, Unique = 99,
}

BonusData.RARITY_BP = {
	Broken = 0, Common = 0, Uncommon = 100, Rare = 150,
	Epic = 200, Legendary = 250, Mythic = 300, Transcendent = 350,
}

BonusData.RARITY_BP_2H = {
	Broken = 0, Common = 0, Uncommon = 200, Rare = 300,
	Epic = 400, Legendary = 500, Mythic = 600, Transcendent = 700,
}

BonusData.RARITY_TOLERANCE = {
	Broken = 0, Common = 0, Uncommon = 5, Rare = 7.5,
	Epic = 10, Legendary = 12.5, Mythic = 15, Transcendent = 17.5,
}

function BonusData.MeetsMinimumRarity(itemRarity, minimumRarity)
	local itemOrder = BonusData.RARITY_ORDER[itemRarity] or 0
	local minOrder = BonusData.RARITY_ORDER[minimumRarity] or 0
	return itemOrder >= minOrder
end

function BonusData.GetBonusBp(rarity, is2H)
	if is2H then
		return BonusData.RARITY_BP_2H[rarity] or 0
	end
	return BonusData.RARITY_BP[rarity] or 0
end

function BonusData.GetTolerance(rarity)
	return BonusData.RARITY_TOLERANCE[rarity] or 0
end

--------------------------------------------------
-- NUMERICAL ATTRIBUTES (117 entries)
-- operation types:
--   "PrimaryStat"  = round(BaseStat × pct) + ScaledFlat
--   "BaseItemStat" = round(ScaledBaseProp × pct) + ScaledFlat
--   "Derived"      = fixed value/multiplier (not level-scaled)
--   "WeightReduce" = reduce scaled base WT
--------------------------------------------------

BonusData.NumericalAttributes = {
	-- PRIMARY STAT BONUSES (6 stats × 6 tiers = 36)
	["PRI-STRBONUS-1"] = { family = "STR Bonus", tier = 1, bpCost = 50, minRarity = "Uncommon", eligible = "Any", l99Flat = 2, pct = 0.05, operation = "PrimaryStat", stat = "STR" },
	["PRI-STRBONUS-2"] = { family = "STR Bonus", tier = 2, bpCost = 100, minRarity = "Uncommon", eligible = "Any", l99Flat = 5, pct = 0.10, operation = "PrimaryStat", stat = "STR" },
	["PRI-STRBONUS-3"] = { family = "STR Bonus", tier = 3, bpCost = 150, minRarity = "Rare", eligible = "Any", l99Flat = 8, pct = 0.15, operation = "PrimaryStat", stat = "STR" },
	["PRI-STRBONUS-4"] = { family = "STR Bonus", tier = 4, bpCost = 200, minRarity = "Epic", eligible = "Any", l99Flat = 12, pct = 0.20, operation = "PrimaryStat", stat = "STR" },
	["PRI-STRBONUS-5"] = { family = "STR Bonus", tier = 5, bpCost = 250, minRarity = "Legendary", eligible = "Any", l99Flat = 16, pct = 0.25, operation = "PrimaryStat", stat = "STR" },
	["PRI-STRBONUS-6"] = { family = "STR Bonus", tier = 6, bpCost = 300, minRarity = "Mythic", eligible = "Any", l99Flat = 21, pct = 0.30, operation = "PrimaryStat", stat = "STR" },
	["PRI-AGIBONUS-1"] = { family = "AGI Bonus", tier = 1, bpCost = 50, minRarity = "Uncommon", eligible = "Any", l99Flat = 2, pct = 0.05, operation = "PrimaryStat", stat = "AGI" },
	["PRI-AGIBONUS-2"] = { family = "AGI Bonus", tier = 2, bpCost = 100, minRarity = "Uncommon", eligible = "Any", l99Flat = 5, pct = 0.10, operation = "PrimaryStat", stat = "AGI" },
	["PRI-AGIBONUS-3"] = { family = "AGI Bonus", tier = 3, bpCost = 150, minRarity = "Rare", eligible = "Any", l99Flat = 8, pct = 0.15, operation = "PrimaryStat", stat = "AGI" },
	["PRI-AGIBONUS-4"] = { family = "AGI Bonus", tier = 4, bpCost = 200, minRarity = "Epic", eligible = "Any", l99Flat = 12, pct = 0.20, operation = "PrimaryStat", stat = "AGI" },
	["PRI-AGIBONUS-5"] = { family = "AGI Bonus", tier = 5, bpCost = 250, minRarity = "Legendary", eligible = "Any", l99Flat = 16, pct = 0.25, operation = "PrimaryStat", stat = "AGI" },
	["PRI-AGIBONUS-6"] = { family = "AGI Bonus", tier = 6, bpCost = 300, minRarity = "Mythic", eligible = "Any", l99Flat = 21, pct = 0.30, operation = "PrimaryStat", stat = "AGI" },
	["PRI-INTBONUS-1"] = { family = "INT Bonus", tier = 1, bpCost = 50, minRarity = "Uncommon", eligible = "Any", l99Flat = 2, pct = 0.05, operation = "PrimaryStat", stat = "INT" },
	["PRI-INTBONUS-2"] = { family = "INT Bonus", tier = 2, bpCost = 100, minRarity = "Uncommon", eligible = "Any", l99Flat = 5, pct = 0.10, operation = "PrimaryStat", stat = "INT" },
	["PRI-INTBONUS-3"] = { family = "INT Bonus", tier = 3, bpCost = 150, minRarity = "Rare", eligible = "Any", l99Flat = 8, pct = 0.15, operation = "PrimaryStat", stat = "INT" },
	["PRI-INTBONUS-4"] = { family = "INT Bonus", tier = 4, bpCost = 200, minRarity = "Epic", eligible = "Any", l99Flat = 12, pct = 0.20, operation = "PrimaryStat", stat = "INT" },
	["PRI-INTBONUS-5"] = { family = "INT Bonus", tier = 5, bpCost = 250, minRarity = "Legendary", eligible = "Any", l99Flat = 16, pct = 0.25, operation = "PrimaryStat", stat = "INT" },
	["PRI-INTBONUS-6"] = { family = "INT Bonus", tier = 6, bpCost = 300, minRarity = "Mythic", eligible = "Any", l99Flat = 21, pct = 0.30, operation = "PrimaryStat", stat = "INT" },
	["PRI-VITBONUS-1"] = { family = "VIT Bonus", tier = 1, bpCost = 50, minRarity = "Uncommon", eligible = "Any", l99Flat = 2, pct = 0.05, operation = "PrimaryStat", stat = "VIT" },
	["PRI-VITBONUS-2"] = { family = "VIT Bonus", tier = 2, bpCost = 100, minRarity = "Uncommon", eligible = "Any", l99Flat = 5, pct = 0.10, operation = "PrimaryStat", stat = "VIT" },
	["PRI-VITBONUS-3"] = { family = "VIT Bonus", tier = 3, bpCost = 150, minRarity = "Rare", eligible = "Any", l99Flat = 8, pct = 0.15, operation = "PrimaryStat", stat = "VIT" },
	["PRI-VITBONUS-4"] = { family = "VIT Bonus", tier = 4, bpCost = 200, minRarity = "Epic", eligible = "Any", l99Flat = 12, pct = 0.20, operation = "PrimaryStat", stat = "VIT" },
	["PRI-VITBONUS-5"] = { family = "VIT Bonus", tier = 5, bpCost = 250, minRarity = "Legendary", eligible = "Any", l99Flat = 16, pct = 0.25, operation = "PrimaryStat", stat = "VIT" },
	["PRI-VITBONUS-6"] = { family = "VIT Bonus", tier = 6, bpCost = 300, minRarity = "Mythic", eligible = "Any", l99Flat = 21, pct = 0.30, operation = "PrimaryStat", stat = "VIT" },
	["PRI-DEXBONUS-1"] = { family = "DEX Bonus", tier = 1, bpCost = 50, minRarity = "Uncommon", eligible = "Any", l99Flat = 2, pct = 0.05, operation = "PrimaryStat", stat = "DEX" },
	["PRI-DEXBONUS-2"] = { family = "DEX Bonus", tier = 2, bpCost = 100, minRarity = "Uncommon", eligible = "Any", l99Flat = 5, pct = 0.10, operation = "PrimaryStat", stat = "DEX" },
	["PRI-DEXBONUS-3"] = { family = "DEX Bonus", tier = 3, bpCost = 150, minRarity = "Rare", eligible = "Any", l99Flat = 8, pct = 0.15, operation = "PrimaryStat", stat = "DEX" },
	["PRI-DEXBONUS-4"] = { family = "DEX Bonus", tier = 4, bpCost = 200, minRarity = "Epic", eligible = "Any", l99Flat = 12, pct = 0.20, operation = "PrimaryStat", stat = "DEX" },
	["PRI-DEXBONUS-5"] = { family = "DEX Bonus", tier = 5, bpCost = 250, minRarity = "Legendary", eligible = "Any", l99Flat = 16, pct = 0.25, operation = "PrimaryStat", stat = "DEX" },
	["PRI-DEXBONUS-6"] = { family = "DEX Bonus", tier = 6, bpCost = 300, minRarity = "Mythic", eligible = "Any", l99Flat = 21, pct = 0.30, operation = "PrimaryStat", stat = "DEX" },
	["PRI-LUKBONUS-1"] = { family = "LUK Bonus", tier = 1, bpCost = 50, minRarity = "Uncommon", eligible = "Any", l99Flat = 2, pct = 0.05, operation = "PrimaryStat", stat = "LUK" },
	["PRI-LUKBONUS-2"] = { family = "LUK Bonus", tier = 2, bpCost = 100, minRarity = "Uncommon", eligible = "Any", l99Flat = 5, pct = 0.10, operation = "PrimaryStat", stat = "LUK" },
	["PRI-LUKBONUS-3"] = { family = "LUK Bonus", tier = 3, bpCost = 150, minRarity = "Rare", eligible = "Any", l99Flat = 8, pct = 0.15, operation = "PrimaryStat", stat = "LUK" },
	["PRI-LUKBONUS-4"] = { family = "LUK Bonus", tier = 4, bpCost = 200, minRarity = "Epic", eligible = "Any", l99Flat = 12, pct = 0.20, operation = "PrimaryStat", stat = "LUK" },
	["PRI-LUKBONUS-5"] = { family = "LUK Bonus", tier = 5, bpCost = 250, minRarity = "Legendary", eligible = "Any", l99Flat = 16, pct = 0.25, operation = "PrimaryStat", stat = "LUK" },
	["PRI-LUKBONUS-6"] = { family = "LUK Bonus", tier = 6, bpCost = 300, minRarity = "Mythic", eligible = "Any", l99Flat = 21, pct = 0.30, operation = "PrimaryStat", stat = "LUK" },
	-- BASE ITEM STAT BONUSES
	["NUM-WEAPONATTACK-1"] = { family = "Weapon Attack", tier = 1, bpCost = 50, minRarity = "Uncommon", eligible = "Weapons", l99Flat = 2, pct = 0.05, operation = "BaseItemStat", stat = "damage" },
	["NUM-WEAPONATTACK-2"] = { family = "Weapon Attack", tier = 2, bpCost = 100, minRarity = "Uncommon", eligible = "Weapons", l99Flat = 4, pct = 0.10, operation = "BaseItemStat", stat = "damage" },
	["NUM-WEAPONATTACK-3"] = { family = "Weapon Attack", tier = 3, bpCost = 150, minRarity = "Rare", eligible = "Weapons", l99Flat = 7, pct = 0.15, operation = "BaseItemStat", stat = "damage" },
	["NUM-WEAPONATTACK-4"] = { family = "Weapon Attack", tier = 4, bpCost = 200, minRarity = "Epic", eligible = "Weapons", l99Flat = 10, pct = 0.20, operation = "BaseItemStat", stat = "damage" },
	["NUM-WEAPONATTACK-5"] = { family = "Weapon Attack", tier = 5, bpCost = 250, minRarity = "Legendary", eligible = "Weapons", l99Flat = 14, pct = 0.25, operation = "BaseItemStat", stat = "damage" },
	["NUM-WEAPONDEFENS-1"] = { family = "Weapon Defense", tier = 1, bpCost = 50, minRarity = "Uncommon", eligible = "WeaponsOffHands", l99Flat = 2, pct = 0.08, operation = "BaseItemStat", stat = "defense" },
	["NUM-WEAPONDEFENS-2"] = { family = "Weapon Defense", tier = 2, bpCost = 100, minRarity = "Uncommon", eligible = "WeaponsOffHands", l99Flat = 4, pct = 0.15, operation = "BaseItemStat", stat = "defense" },
	["NUM-WEAPONDEFENS-3"] = { family = "Weapon Defense", tier = 3, bpCost = 150, minRarity = "Rare", eligible = "WeaponsOffHands", l99Flat = 7, pct = 0.22, operation = "BaseItemStat", stat = "defense" },
	["NUM-WEAPONDEFENS-4"] = { family = "Weapon Defense", tier = 4, bpCost = 200, minRarity = "Epic", eligible = "WeaponsOffHands", l99Flat = 10, pct = 0.30, operation = "BaseItemStat", stat = "defense" },
	["NUM-WEAPONRTDELA-1"] = { family = "Weapon RT Delay", tier = 1, bpCost = 50, minRarity = "Uncommon", eligible = "WeaponsOffHands", l99Flat = 2, pct = 0.08, operation = "BaseItemStat", stat = "rtDelay" },
	["NUM-WEAPONRTDELA-2"] = { family = "Weapon RT Delay", tier = 2, bpCost = 100, minRarity = "Uncommon", eligible = "WeaponsOffHands", l99Flat = 4, pct = 0.15, operation = "BaseItemStat", stat = "rtDelay" },
	["NUM-WEAPONRTDELA-3"] = { family = "Weapon RT Delay", tier = 3, bpCost = 150, minRarity = "Rare", eligible = "WeaponsOffHands", l99Flat = 7, pct = 0.22, operation = "BaseItemStat", stat = "rtDelay" },
	["NUM-WEAPONRTDELA-4"] = { family = "Weapon RT Delay", tier = 4, bpCost = 200, minRarity = "Epic", eligible = "WeaponsOffHands", l99Flat = 10, pct = 0.30, operation = "BaseItemStat", stat = "rtDelay" },
	["NUM-WEIGHTREDUCT-1"] = { family = "Weight Reduction", tier = 1, bpCost = 50, minRarity = "Uncommon", eligible = "Any", l99Flat = 2, pct = 0.05, operation = "WeightReduce", stat = "wt" },
	["NUM-WEIGHTREDUCT-2"] = { family = "Weight Reduction", tier = 2, bpCost = 100, minRarity = "Uncommon", eligible = "Any", l99Flat = 4, pct = 0.10, operation = "WeightReduce", stat = "wt" },
	["NUM-WEIGHTREDUCT-3"] = { family = "Weight Reduction", tier = 3, bpCost = 150, minRarity = "Rare", eligible = "Any", l99Flat = 7, pct = 0.15, operation = "WeightReduce", stat = "wt" },
	["NUM-WEIGHTREDUCT-4"] = { family = "Weight Reduction", tier = 4, bpCost = 200, minRarity = "Epic", eligible = "Any", l99Flat = 10, pct = 0.20, operation = "WeightReduce", stat = "wt" },
	["NUM-WEIGHTREDUCT-5"] = { family = "Weight Reduction", tier = 5, bpCost = 250, minRarity = "Legendary", eligible = "Any", l99Flat = 14, pct = 0.25, operation = "WeightReduce", stat = "wt" },
	["NUM-HP-1"] = { family = "HP", tier = 1, bpCost = 50, minRarity = "Uncommon", eligible = "Any", l99Flat = 4, pct = 0.05, operation = "BaseItemStat", stat = "hp" },
	["NUM-HP-2"] = { family = "HP", tier = 2, bpCost = 100, minRarity = "Uncommon", eligible = "Any", l99Flat = 8, pct = 0.10, operation = "BaseItemStat", stat = "hp" },
	["NUM-HP-3"] = { family = "HP", tier = 3, bpCost = 150, minRarity = "Rare", eligible = "Any", l99Flat = 13, pct = 0.15, operation = "BaseItemStat", stat = "hp" },
	["NUM-HP-4"] = { family = "HP", tier = 4, bpCost = 200, minRarity = "Epic", eligible = "Any", l99Flat = 18, pct = 0.20, operation = "BaseItemStat", stat = "hp" },
	["NUM-HP-5"] = { family = "HP", tier = 5, bpCost = 250, minRarity = "Legendary", eligible = "Any", l99Flat = 24, pct = 0.25, operation = "BaseItemStat", stat = "hp" },
	["NUM-MP-1"] = { family = "MP", tier = 1, bpCost = 50, minRarity = "Uncommon", eligible = "Any", l99Flat = 3, pct = 0.05, operation = "BaseItemStat", stat = "mp" },
	["NUM-MP-2"] = { family = "MP", tier = 2, bpCost = 100, minRarity = "Uncommon", eligible = "Any", l99Flat = 6, pct = 0.10, operation = "BaseItemStat", stat = "mp" },
	["NUM-MP-3"] = { family = "MP", tier = 3, bpCost = 150, minRarity = "Rare", eligible = "Any", l99Flat = 10, pct = 0.15, operation = "BaseItemStat", stat = "mp" },
	["NUM-MP-4"] = { family = "MP", tier = 4, bpCost = 200, minRarity = "Epic", eligible = "Any", l99Flat = 14, pct = 0.20, operation = "BaseItemStat", stat = "mp" },
	["NUM-MP-5"] = { family = "MP", tier = 5, bpCost = 250, minRarity = "Legendary", eligible = "Any", l99Flat = 19, pct = 0.25, operation = "BaseItemStat", stat = "mp" },
	["NUM-EQUIPMENTDEF-1"] = { family = "Equipment Defense", tier = 1, bpCost = 50, minRarity = "Uncommon", eligible = "NonWeapon", l99Flat = 2, pct = 0.08, operation = "BaseItemStat", stat = "defense" },
	["NUM-EQUIPMENTDEF-2"] = { family = "Equipment Defense", tier = 2, bpCost = 100, minRarity = "Uncommon", eligible = "NonWeapon", l99Flat = 4, pct = 0.15, operation = "BaseItemStat", stat = "defense" },
	["NUM-EQUIPMENTDEF-3"] = { family = "Equipment Defense", tier = 3, bpCost = 150, minRarity = "Rare", eligible = "NonWeapon", l99Flat = 7, pct = 0.22, operation = "BaseItemStat", stat = "defense" },
	["NUM-EQUIPMENTDEF-4"] = { family = "Equipment Defense", tier = 4, bpCost = 200, minRarity = "Epic", eligible = "NonWeapon", l99Flat = 10, pct = 0.30, operation = "BaseItemStat", stat = "defense" },
	["NUM-EQUIPMENTDEF-5"] = { family = "Equipment Defense", tier = 5, bpCost = 250, minRarity = "Legendary", eligible = "NonWeapon", l99Flat = 14, pct = 0.38, operation = "BaseItemStat", stat = "defense" },
	-- DERIVED STAT BONUSES (fixed values, not level-scaled)
	["DER-PRECISION-1"] = { family = "Precision", tier = 1, bpCost = 50, minRarity = "Uncommon", eligible = "Any", fixedValue = 0.03, operation = "Derived", stat = "precision" },
	["DER-PRECISION-2"] = { family = "Precision", tier = 2, bpCost = 100, minRarity = "Uncommon", eligible = "Any", fixedValue = 0.06, operation = "Derived", stat = "precision" },
	["DER-PRECISION-3"] = { family = "Precision", tier = 3, bpCost = 150, minRarity = "Rare", eligible = "Any", fixedValue = 0.09, operation = "Derived", stat = "precision" },
	["DER-PRECISION-4"] = { family = "Precision", tier = 4, bpCost = 200, minRarity = "Epic", eligible = "Any", fixedValue = 0.12, operation = "Derived", stat = "precision" },
	["DER-EVASIVENESS-1"] = { family = "Evasiveness", tier = 1, bpCost = 50, minRarity = "Uncommon", eligible = "Any", fixedValue = 0.03, operation = "Derived", stat = "evasiveness" },
	["DER-EVASIVENESS-2"] = { family = "Evasiveness", tier = 2, bpCost = 100, minRarity = "Uncommon", eligible = "Any", fixedValue = 0.06, operation = "Derived", stat = "evasiveness" },
	["DER-EVASIVENESS-3"] = { family = "Evasiveness", tier = 3, bpCost = 150, minRarity = "Rare", eligible = "Any", fixedValue = 0.09, operation = "Derived", stat = "evasiveness" },
	["DER-EVASIVENESS-4"] = { family = "Evasiveness", tier = 4, bpCost = 200, minRarity = "Epic", eligible = "Any", fixedValue = 0.12, operation = "Derived", stat = "evasiveness" },
	["DER-FORTUNE-1"] = { family = "Fortune", tier = 1, bpCost = 50, minRarity = "Uncommon", eligible = "Any", fixedValue = 0.05, operation = "Derived", stat = "fortune" },
	["DER-FORTUNE-2"] = { family = "Fortune", tier = 2, bpCost = 100, minRarity = "Uncommon", eligible = "Any", fixedValue = 0.10, operation = "Derived", stat = "fortune" },
	["DER-FORTUNE-3"] = { family = "Fortune", tier = 3, bpCost = 150, minRarity = "Rare", eligible = "Any", fixedValue = 0.15, operation = "Derived", stat = "fortune" },
	["DER-FORTUNE-4"] = { family = "Fortune", tier = 4, bpCost = 200, minRarity = "Epic", eligible = "Any", fixedValue = 0.20, operation = "Derived", stat = "fortune" },
	["DER-SKILLPOTENCY-1"] = { family = "Skill Potency Bonus", tier = 1, bpCost = 50, minRarity = "Uncommon", eligible = "Any", fixedValue = 0.05, operation = "Derived", stat = "skillPotency" },
	["DER-SKILLPOTENCY-2"] = { family = "Skill Potency Bonus", tier = 2, bpCost = 100, minRarity = "Uncommon", eligible = "Any", fixedValue = 0.10, operation = "Derived", stat = "skillPotency" },
	["DER-SKILLPOTENCY-3"] = { family = "Skill Potency Bonus", tier = 3, bpCost = 150, minRarity = "Rare", eligible = "Any", fixedValue = 0.15, operation = "Derived", stat = "skillPotency" },
	["DER-SKILLPOTENCY-4"] = { family = "Skill Potency Bonus", tier = 4, bpCost = 200, minRarity = "Epic", eligible = "Any", fixedValue = 0.20, operation = "Derived", stat = "skillPotency" },
	["DER-HEALINGOUTPU-1"] = { family = "Healing Output", tier = 1, bpCost = 50, minRarity = "Uncommon", eligible = "Any", fixedValue = 1.08, operation = "DerivedMultiplier", stat = "healingOutput" },
	["DER-HEALINGOUTPU-2"] = { family = "Healing Output", tier = 2, bpCost = 100, minRarity = "Uncommon", eligible = "Any", fixedValue = 1.15, operation = "DerivedMultiplier", stat = "healingOutput" },
	["DER-HEALINGOUTPU-3"] = { family = "Healing Output", tier = 3, bpCost = 150, minRarity = "Rare", eligible = "Any", fixedValue = 1.22, operation = "DerivedMultiplier", stat = "healingOutput" },
	["DER-HEALINGOUTPU-4"] = { family = "Healing Output", tier = 4, bpCost = 200, minRarity = "Epic", eligible = "Any", fixedValue = 1.30, operation = "DerivedMultiplier", stat = "healingOutput" },
	["DER-DEBUFFRESIST-1"] = { family = "Debuff Resistance", tier = 1, bpCost = 50, minRarity = "Uncommon", eligible = "Any", fixedValue = 0.95, operation = "DerivedMultiplier", stat = "debuffResist" },
	["DER-DEBUFFRESIST-2"] = { family = "Debuff Resistance", tier = 2, bpCost = 100, minRarity = "Uncommon", eligible = "Any", fixedValue = 0.90, operation = "DerivedMultiplier", stat = "debuffResist" },
	["DER-DEBUFFRESIST-3"] = { family = "Debuff Resistance", tier = 3, bpCost = 150, minRarity = "Rare", eligible = "Any", fixedValue = 0.85, operation = "DerivedMultiplier", stat = "debuffResist" },
	["DER-DEBUFFRESIST-4"] = { family = "Debuff Resistance", tier = 4, bpCost = 200, minRarity = "Epic", eligible = "Any", fixedValue = 0.80, operation = "DerivedMultiplier", stat = "debuffResist" },
	["DER-RTDELAYRESIS-1"] = { family = "RT Delay Resistance", tier = 1, bpCost = 50, minRarity = "Uncommon", eligible = "Any", fixedValue = 0.95, operation = "DerivedMultiplier", stat = "rtDelayResist" },
	["DER-RTDELAYRESIS-2"] = { family = "RT Delay Resistance", tier = 2, bpCost = 100, minRarity = "Uncommon", eligible = "Any", fixedValue = 0.90, operation = "DerivedMultiplier", stat = "rtDelayResist" },
	["DER-RTDELAYRESIS-3"] = { family = "RT Delay Resistance", tier = 3, bpCost = 150, minRarity = "Rare", eligible = "Any", fixedValue = 0.85, operation = "DerivedMultiplier", stat = "rtDelayResist" },
	["DER-RTDELAYRESIS-4"] = { family = "RT Delay Resistance", tier = 4, bpCost = 200, minRarity = "Epic", eligible = "Any", fixedValue = 0.80, operation = "DerivedMultiplier", stat = "rtDelayResist" },
}

--------------------------------------------------
-- BONUS PASSIVES (36 entries)
--------------------------------------------------

BonusData.BonusPassives = {
	["PAS-001"] = { name = "Brutal", bpCost = 100, minRarity = "Uncommon", eligible = "HighDamageMelee", slotCost = 1, desc = "Effective Weapon Damage = Base Weapon Damage ×1.20 before STR scaling." },
	["PAS-002"] = { name = "Stagger", bpCost = 100, minRarity = "Uncommon", eligible = "FastWeapons", slotCost = 1, desc = "Effective Weapon RT Delay = Base Weapon RT Delay ×1.25." },
	["PAS-003"] = { name = "Knockback", bpCost = 150, minRarity = "Rare", eligible = "BluntHeavy", slotCost = 1, desc = "On hit, push floor(Force/2) tiles; normal collision/fall rules." },
	["PAS-004"] = { name = "Armor Pierce", bpCost = 130, minRarity = "Rare", eligible = "Piercing", slotCost = 1, desc = "Use 70% of target Defense for eligible weapon attacks." },
	["PAS-005"] = { name = "Fortify", bpCost = 120, minRarity = "Rare", eligible = "NonSingleTarget", slotCost = 1, desc = "Gain flat Defense based on owning item base Weapon Defense when hitting units." },
	["PAS-006"] = { name = "Arcane Flow", bpCost = 80, minRarity = "Uncommon", eligible = "Magical", slotCost = 1, desc = "On ready turn, restore authored MP amount." },
	["PAS-007"] = { name = "Range +1", bpCost = 190, minRarity = "Epic", eligible = "ApprovedRanged", slotCost = 1, desc = "Maximum Weapon Range +1; Minimum Range unchanged." },
	["PAS-008"] = { name = "Arcane Reach", bpCost = 120, minRarity = "Rare", eligible = "ApprovedRanged", slotCost = 1, desc = "Skills explicitly inheriting weapon range gain +1 Maximum Range." },
	["PAS-009"] = { name = "Surveyor Visor Range", bpCost = 70, minRarity = "Uncommon", eligible = "Any", slotCost = 1, desc = "Interact Maximum Range +2." },
	["PAS-010"] = { name = "Long-Throw Strap Range", bpCost = 80, minRarity = "Uncommon", eligible = "Any", slotCost = 1, desc = "Item Maximum Range +2; normal Item restrictions remain." },
	["PAS-011"] = { name = "Movement Range +1", bpCost = 150, minRarity = "Rare", eligible = "Any", slotCost = 1, desc = "Final Movement Range +1." },
	["PAS-012"] = { name = "Jump +1", bpCost = 100, minRarity = "Uncommon", eligible = "Any", slotCost = 1, desc = "Final Jump +1." },
	["PAS-013"] = { name = "Force +1", bpCost = 150, minRarity = "Rare", eligible = "Any", slotCost = 1, desc = "Final Force +1." },
	["PAS-014"] = { name = "Stability +1", bpCost = 120, minRarity = "Rare", eligible = "Any", slotCost = 1, desc = "Final Stability +1." },
	["PAS-015"] = { name = "Discovery Radius +1", bpCost = 70, minRarity = "Uncommon", eligible = "Any", slotCost = 1, desc = "Final Discovery Radius +1." },
	["PAS-016"] = { name = "Fire Transformation", bpCost = 150, minRarity = "Rare", eligible = "NonElementalWeapons", slotCost = 1, desc = "Weapon gains Fire tag and approved Fire interactions." },
	["PAS-017"] = { name = "Water Transformation", bpCost = 150, minRarity = "Rare", eligible = "NonElementalWeapons", slotCost = 1, desc = "Weapon gains Water tag and approved Water interactions." },
	["PAS-018"] = { name = "Ice Transformation", bpCost = 150, minRarity = "Rare", eligible = "NonElementalWeapons", slotCost = 1, desc = "Weapon gains Ice tag and approved Ice interactions." },
	["PAS-019"] = { name = "Electric Transformation", bpCost = 150, minRarity = "Rare", eligible = "NonElementalWeapons", slotCost = 1, desc = "Weapon gains Electric tag and approved Electric interactions." },
	["PAS-020"] = { name = "Dark Transformation", bpCost = 170, minRarity = "Epic", eligible = "NonElementalWeapons", slotCost = 1, desc = "Weapon gains Dark tag and approved Dark interactions." },
	["PAS-021"] = { name = "Holy Transformation", bpCost = 170, minRarity = "Epic", eligible = "NonElementalWeapons", slotCost = 1, desc = "Weapon gains Holy tag and approved Holy interactions." },
	["PAS-022"] = { name = "Poison Transformation", bpCost = 170, minRarity = "Epic", eligible = "NonElementalWeapons", slotCost = 1, desc = "Weapon gains Poison tag and approved Poison interactions." },
	["PAS-023"] = { name = "Cleave Conversion", bpCost = 200, minRarity = "Epic", eligible = "SingleTargetMelee", slotCost = 1, desc = "Replace Single pattern with Cleave." },
	["PAS-024"] = { name = "Line 2 Conversion", bpCost = 200, minRarity = "Epic", eligible = "SingleTargetThrust", slotCost = 1, desc = "Replace Single pattern with Line 2." },
	["PAS-025"] = { name = "Impact Splash Conversion", bpCost = 200, minRarity = "Epic", eligible = "SingleTargetRanged", slotCost = 1, desc = "Replace Single pattern with approved Impact Splash." },
	["PAS-026"] = { name = "Electric Ward", bpCost = 150, minRarity = "Rare", eligible = "ArmorShield", slotCost = 1, desc = "Incoming Electric-tagged direct damage ×0.75." },
	["PAS-027"] = { name = "Electric Negation", bpCost = 250, minRarity = "Legendary", eligible = "ArmorShield", slotCost = 1, desc = "First Electric-tagged direct damage each round becomes 0." },
	["PAS-028"] = { name = "Electric Absorption", bpCost = 300, minRarity = "Mythic", eligible = "ArmorShield", slotCost = 1, desc = "Electric-tagged direct damage heals instead; excess healing discarded." },
	["PAS-029"] = { name = "Fire Ward", bpCost = 150, minRarity = "Rare", eligible = "ArmorShield", slotCost = 1, desc = "Incoming Fire-tagged direct damage ×0.75." },
	["PAS-030"] = { name = "Water Ward", bpCost = 150, minRarity = "Rare", eligible = "ArmorShield", slotCost = 1, desc = "Incoming Water-tagged direct damage ×0.75." },
	["PAS-031"] = { name = "Ice Ward", bpCost = 150, minRarity = "Rare", eligible = "ArmorShield", slotCost = 1, desc = "Incoming Ice-tagged direct damage ×0.75." },
	["PAS-032"] = { name = "Dark Ward", bpCost = 170, minRarity = "Epic", eligible = "ArmorShield", slotCost = 1, desc = "Incoming Dark-tagged direct damage ×0.75." },
	["PAS-033"] = { name = "Holy Ward", bpCost = 170, minRarity = "Epic", eligible = "ArmorShield", slotCost = 1, desc = "Incoming Holy-tagged direct damage ×0.75." },
	["PAS-034"] = { name = "Quickdraw Pouch", bpCost = 90, minRarity = "Uncommon", eligible = "Accessories", slotCost = 1, desc = "Item RT Cost ×0.75 after authored eligibility checks and combined-RT calculations." },
	["PAS-035"] = { name = "Guard Bonus +15%", bpCost = 120, minRarity = "Rare", eligible = "ShieldsArmor", slotCost = 1, desc = "Guard mitigation +15 percentage points, subject to global Guard cap." },
	["PAS-036"] = { name = "Push RT x0.75", bpCost = 60, minRarity = "Uncommon", eligible = "Gloves", slotCost = 1, desc = "Push RT Cost ×0.75 with the authored drawback if copied as the full passive." },
}

--------------------------------------------------
-- LOOKUP HELPERS
--------------------------------------------------

function BonusData.GetAttribute(attrId)
	return BonusData.NumericalAttributes[attrId]
end

function BonusData.GetPassive(passiveId)
	return BonusData.BonusPassives[passiveId]
end

-- Get all tiers in a family (ordered by tier)
function BonusData.GetFamilyTiers(family)
	local tiers = {}
	for id, attr in pairs(BonusData.NumericalAttributes) do
		if attr.family == family then
			table.insert(tiers, { id = id, tier = attr.tier, bpCost = attr.bpCost })
		end
	end
	table.sort(tiers, function(a, b) return a.tier < b.tier end)
	return tiers
end

-- Get all families
function BonusData.GetAllFamilies()
	local seen = {}
	local families = {}
	for _, attr in pairs(BonusData.NumericalAttributes) do
		if not seen[attr.family] then
			seen[attr.family] = true
			table.insert(families, attr.family)
		end
	end
	table.sort(families)
	return families
end

return BonusData
