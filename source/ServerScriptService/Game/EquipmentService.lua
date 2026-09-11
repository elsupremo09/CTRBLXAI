-- EquipmentService.lua
local RacePassiveService = require(script.Parent.RacePassiveService)
-- CTRBLXAI | Slice 4A — Equipment Foundation
-- Slice 4G — Armor Slot Expansion
--
-- Owns: equipped state, hand legality, deterministic stat rebuilding.
-- Interface: ValidateLoadout, Equip, Unequip, RebuildUnitStats.
--
-- CRITICAL RULE: Final unit statistics are ALWAYS rebuilt from authoritative
-- sources. Never incremental add/subtract. Recalculating twice = same result.
--
-- Rebuild order:
--   1. Race base stats (permanent)
--   2. Doctrine stat package (once)
--   3. Equipment bonus numerical attributes (all equipped items)
--   3b. Race passive stat penalties
--   3c. Armor stat contributions (Def, HP, MP, WT)
--   4. Weapon combat profile from MainHand
--   5. HP/MP from effective stats + armor HP/MP
--   6. Derived stats from totals
--
-- Equipment slots (7):
--   MainHand, OffHand — weapons
--   Head, Body, Gloves, Feet, Accessory — armor
-- 2H weapon → OffHand forced nil, Armor Off-Hand WT = 0 in Guard RT.

local WeaponData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("WeaponData")
)
local ArmorData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("ArmorData")
)
local BonusData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("BonusData")
)
local DoctrineData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("DoctrineData")
)

local GameConstants = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Shared")
		:WaitForChild("GameConstants")
)

local EquipmentService = {}

--------------------------------------------------
-- SLOT DEFINITIONS
--------------------------------------------------

local VALID_SLOTS = {
	MainHand = true,
	OffHand = true,
	Head = true,
	Body = true,
	Gloves = true,
	Feet = true,
	Accessory = true,
}

local ARMOR_SLOTS = {
	Head = true,
	Body = true,
	Gloves = true,
	Feet = true,
	Accessory = true,
}

--------------------------------------------------
-- ARCHETYPE RESOLUTION (weapon or armor)
--------------------------------------------------

local function resolveArchetype(baseArchetypeId)
	local wArch = WeaponData.GetByArchetypeId(baseArchetypeId)
	if wArch then return wArch, "weapon" end
	local aArch = ArmorData.GetByArchetypeId(baseArchetypeId)
	if aArch then return aArch, "armor" end
	return nil, nil
end

--------------------------------------------------
-- SLOT DETERMINATION
--------------------------------------------------

function EquipmentService.DetermineSlot(itemInstance)
	local wArch = WeaponData.GetByArchetypeId(itemInstance.baseArchetypeId)
	if wArch then
		return (wArch.category == "OffHand") and "OffHand" or "MainHand"
	end
	local aArch = ArmorData.GetByArchetypeId(itemInstance.baseArchetypeId)
	if aArch then
		return aArch.slot -- "Head", "Body", "Gloves", "Feet", "Accessory"
	end
	return nil
end

--------------------------------------------------
-- LOADOUT VALIDATION
--------------------------------------------------

function EquipmentService.ValidateEquip(unit, itemInstance, slot)
	if not VALID_SLOTS[slot] then
		return false, "Invalid slot: " .. tostring(slot)
	end
	if not itemInstance or type(itemInstance) ~= "table" then
		return false, "Invalid item instance"
	end

	local archetype, itemType = resolveArchetype(itemInstance.baseArchetypeId)
	if not archetype then
		return false, "Unknown archetype: " .. tostring(itemInstance.baseArchetypeId)
	end

	if itemType == "weapon" then
		-- Weapon → MainHand only
		if archetype.category == "Weapon" and slot ~= "MainHand" then
			return false, "Weapons can only go in MainHand"
		end
		-- OffHand → OffHand only
		if archetype.category == "OffHand" and slot ~= "OffHand" then
			return false, "Off-hands can only go in OffHand slot"
		end
		-- Cannot put weapon in armor slot
		if ARMOR_SLOTS[slot] then
			return false, "Cannot equip weapon in armor slot"
		end
		-- 2H weapon check: cannot equip OffHand if MainHand is 2H
		if slot == "OffHand" then
			local mainHand = unit.equipmentSlots and unit.equipmentSlots.MainHand
			if mainHand then
				local mainArchetype = WeaponData.GetByArchetypeId(mainHand.baseArchetypeId)
				-- Titan: Colossal Arsenal allows 2H melee as 1H, so OffHand is available
				local titanBypass = mainArchetype and mainArchetype.handClass == "2H" and RacePassiveService.CanEquip2HAsWith1H(unit)
				if mainArchetype and mainArchetype.handClass == "2H" and not titanBypass then
					return false, "Cannot equip off-hand with a 2H weapon"
				end
			end
		end
		-- If equipping a 2H weapon, off-hand must be cleared
		-- Titan: Colossal Arsenal — 2H melee equipped as 1H, OffHand NOT cleared
		if slot == "MainHand" and archetype.handClass == "2H" and not RacePassiveService.CanEquip2HAsWith1H(unit) then
			-- This is allowed; OffHand will be force-cleared during equip
		end
	elseif itemType == "armor" then
		-- Armor → matching slot only
		if archetype.slot ~= slot then
			return false, "This armor goes in " .. archetype.slot .. ", not " .. slot
		end
		-- Cannot put armor in weapon slots
		if slot == "MainHand" or slot == "OffHand" then
			return false, "Cannot equip armor in weapon slot"
		end
	end

	-- Cannot equip same instance in multiple slots
	if unit.equipmentSlots then
		for existingSlot, existingItem in pairs(unit.equipmentSlots) do
			if existingItem and existingItem.instanceId == itemInstance.instanceId
				and existingSlot ~= slot then
				return false, "Item already equipped in " .. existingSlot
			end
		end
	end

	return true
end

--------------------------------------------------
-- EQUIP / UNEQUIP
--------------------------------------------------

function EquipmentService.Equip(unit, itemInstance, slot)
	local valid, reason = EquipmentService.ValidateEquip(unit, itemInstance, slot)
	if not valid then
		return false, reason
	end

	-- Ensure equipmentSlots exists
	if not unit.equipmentSlots then
		unit.equipmentSlots = {}
	end

	local archetype, itemType = resolveArchetype(itemInstance.baseArchetypeId)

	-- If 2H weapon, force-clear off-hand (Titan bypasses this)
	if itemType == "weapon" and slot == "MainHand" and archetype.handClass == "2H"
		and not RacePassiveService.CanEquip2HAsWith1H(unit) then
		unit.equipmentSlots.OffHand = nil
	end

	-- Assign to slot (replaces whatever was there)
	unit.equipmentSlots[slot] = itemInstance

	-- Rebuild stats from scratch
	EquipmentService.RebuildUnitStats(unit)

	print(string.format(
		"[EquipmentService] %s equipped %s [%s] in %s",
		unit.name or unit.id, archetype.name, itemInstance.instanceId, slot
	))
	return true
end

function EquipmentService.Unequip(unit, slot)
	if not VALID_SLOTS[slot] then
		return false, "Invalid slot"
	end
	if not unit.equipmentSlots or not unit.equipmentSlots[slot] then
		return false, "Slot is empty"
	end

	local removed = unit.equipmentSlots[slot]
	unit.equipmentSlots[slot] = nil

	-- Rebuild stats from scratch
	EquipmentService.RebuildUnitStats(unit)

	print(string.format(
		"[EquipmentService] %s unequipped %s from %s",
		unit.name or unit.id, removed.instanceId, slot
	))
	return true, removed
end

--------------------------------------------------
-- DETERMINISTIC STAT REBUILD
--
-- Called after any equipment/doctrine change.
-- Produces the same result regardless of call count.
--------------------------------------------------

function EquipmentService.RebuildUnitStats(unit)
	-- 1. Start from race base stats (permanent values)
	local base = unit.baseStats or { STR = 10, AGI = 10, INT = 10, VIT = 10, DEX = 10, LUK = 10 }

	local total = {
		STR = base.STR,
		AGI = base.AGI,
		INT = base.INT,
		VIT = base.VIT,
		DEX = base.DEX,
		LUK = base.LUK,
	}

	-- 2. Doctrine stat package (percentage modifiers applied to base stats)
	-- DB: "Six signed percentages" — e.g. STR_Modifier: 15 means +15% of base STR
	if unit.doctrineId then
		local doctrine = DoctrineData[unit.doctrineId]
		if doctrine and doctrine.statPackage then
			local pkg = doctrine.statPackage
			total.STR = total.STR + math.round(base.STR * (pkg.STR or 0) / 100)
			total.AGI = total.AGI + math.round(base.AGI * (pkg.AGI or 0) / 100)
			total.INT = total.INT + math.round(base.INT * (pkg.INT or 0) / 100)
			total.VIT = total.VIT + math.round(base.VIT * (pkg.VIT or 0) / 100)
			total.DEX = total.DEX + math.round(base.DEX * (pkg.DEX or 0) / 100)
			total.LUK = total.LUK + math.round(base.LUK * (pkg.LUK or 0) / 100)
		end
	end

	-- 3. Equipment bonus numerical attributes (Primary Stat bonuses)
	-- Calculation order: aggregate percentages first, apply once, round once.
	-- Then add scaled flat bonuses.
	local primaryPctBonuses = { STR = 0, AGI = 0, INT = 0, VIT = 0, DEX = 0, LUK = 0 }
	local primaryFlatBonuses = { STR = 0, AGI = 0, INT = 0, VIT = 0, DEX = 0, LUK = 0 }

	local equippedItems = EquipmentService.GetAllEquippedItems(unit)
	for _, item in ipairs(equippedItems) do
		for _, line in ipairs(item.bonusLines or {}) do
			local attr = BonusData.GetAttribute(line.id)
			if attr and attr.operation == "PrimaryStat" then
				local stat = attr.stat
				if primaryPctBonuses[stat] then
					primaryPctBonuses[stat] = primaryPctBonuses[stat] + attr.pct
					local scaledFlat = WeaponData.ScaleProperty(attr.l99Flat, item.itemLevel)
					primaryFlatBonuses[stat] = primaryFlatBonuses[stat] + scaledFlat
				end
			end
		end
	end

	-- Apply: Primary bonus = round(Base Primary Stat × aggregated pct) + sum of scaled flats
	-- "Base Primary Stat" = race growth (unit.baseStats), NOT including Doctrine/equipment.
	for _, stat in ipairs({"STR", "AGI", "INT", "VIT", "DEX", "LUK"}) do
		if primaryPctBonuses[stat] ~= 0 or primaryFlatBonuses[stat] ~= 0 then
			local pctBonus = math.round(base[stat] * primaryPctBonuses[stat])
			total[stat] = total[stat] + pctBonus + primaryFlatBonuses[stat]
		end
	end

	-- 3b. Race passive stat penalties (Slice 4F)
	-- Applied AFTER doctrine + equipment, BEFORE HP/MP derivation
	local raceMods = RacePassiveService.GetStatModifiers(unit)
	if raceMods then
		for stat, pctMod in pairs(raceMods) do
			if total[stat] then
				total[stat] = math.max(0, math.round(total[stat] * (1 + pctMod)))
			end
		end
	end

	-- 3c. Armor stat contributions (Slice 4G)
	-- Sum scaled defense, hp, mp, wt from all equipped armor pieces
	local armorDefense = 0
	local armorWt = 0
	local armorHp = 0
	local armorMp = 0

	for _, item in ipairs(equippedItems) do
		local aArch = ArmorData.GetByArchetypeId(item.baseArchetypeId)
		if aArch then
			local scaled = ArmorData.GetScaledProfile(item.baseArchetypeId, item.itemLevel)
			if scaled then
				armorDefense = armorDefense + scaled.defense
				armorWt = armorWt + scaled.wt
				armorHp = armorHp + scaled.hp
				armorMp = armorMp + scaled.mp
			end
		end
	end

	unit.armorDefense = armorDefense
	unit.armorWt = armorWt

	-- Write effective stats
	-- Clamp all stats to minimum 0 (doctrine packages can push stats negative at low levels)
	for _, stat in ipairs({"STR", "AGI", "INT", "VIT", "DEX", "LUK"}) do
		if total[stat] < 0 then
			total[stat] = 0
		end
	end
	unit.effectiveStats = total

	-- 4. Rebuild weapon combat profile from MainHand
	local mainHand = unit.equipmentSlots and unit.equipmentSlots.MainHand
	if mainHand then
		local profile = EquipmentService.GetEffectiveWeaponProfile(mainHand)
		unit.weaponDamage = profile.damage
		unit.weaponWt = profile.wt

		-- Mechanical race tag: Raw Weapon WT ×1.15
		if unit.raceId then
			local RaceData = require(game:GetService("ReplicatedStorage"):WaitForChild("Content"):WaitForChild("RaceData"))
			local raceEntry = RaceData[unit.raceId]
			if raceEntry and raceEntry.tags then
				for _, tag in ipairs(raceEntry.tags) do
					if tag == "Mechanical" then
						unit.weaponWt = math.floor(unit.weaponWt * 1.15)
						break
					end
				end
			end
		end

		unit.weaponRtDelay = profile.rtDelay
		unit.weaponDefense = profile.defense
		unit.weaponMinRange = profile.minRange
		unit.weaponMaxRange = profile.maxRange
		unit.weaponPattern = profile.pattern
		unit.weaponProjectileType = profile.projectileType
		unit.weaponHandClass = profile.handClass
	else
		-- Unarmed defaults
		unit.weaponDamage = 5
		unit.weaponWt = 20
		unit.weaponRtDelay = 0
		unit.weaponDefense = 0
		unit.weaponMinRange = 1
		unit.weaponMaxRange = 1
		unit.weaponPattern = "Single"
		unit.weaponProjectileType = nil
		unit.weaponHandClass = "1H"
	end

	-- 4b. Off-hand defense contribution
	local offHand = unit.equipmentSlots and unit.equipmentSlots.OffHand
	if offHand then
		local offProfile = EquipmentService.GetEffectiveWeaponProfile(offHand)
		unit.offHandDefense = offProfile.defense
	else
		unit.offHandDefense = 0
	end

	-- 5. Rebuild HP/MP from effective stats + armor contributions
	local vit = total.VIT
	local int = total.INT
	unit.maxHp = 50 + vit * 4 + armorHp
	unit.maxMp = 20 + int * 2 + armorMp

	-- Clamp current to new max (don't increase current beyond max)
	if unit.currentHp and unit.currentHp > unit.maxHp then
		unit.currentHp = unit.maxHp
	end
	if unit.currentMp and unit.currentMp > unit.maxMp then
		unit.currentMp = unit.maxMp
	end

	-- 6. Compute all derived stats (formulas from all primary stats)
	GameConstants.ComputeDerivedStats(unit)
end

--------------------------------------------------
-- WEAPON PROFILE (with rarity bonuses applied)
--------------------------------------------------

function EquipmentService.GetEffectiveWeaponProfile(itemInstance)
	local archetype = WeaponData.GetByArchetypeId(itemInstance.baseArchetypeId)
	if not archetype then
		return { damage = 5, wt = 20, rtDelay = 0, defense = 0,
			minRange = 1, maxRange = 1, pattern = "Single",
			projectileType = nil, handClass = "1H" }
	end

	-- Get scaled base profile
	local profile = WeaponData.GetScaledProfile(itemInstance.baseArchetypeId, itemInstance.itemLevel)

	-- Apply rarity numerical bonuses to base item stats
	-- Calculation order: round(Scaled Base × aggregated pct) + sum of scaled flats
	local pctBonuses = { damage = 0, defense = 0, rtDelay = 0, wt = 0 }
	local flatBonuses = { damage = 0, defense = 0, rtDelay = 0, wt = 0 }

	for _, line in ipairs(itemInstance.bonusLines or {}) do
		local attr = BonusData.GetAttribute(line.id)
		if attr then
			if attr.operation == "BaseItemStat" then
				local stat = attr.stat
				if pctBonuses[stat] then
					pctBonuses[stat] = pctBonuses[stat] + attr.pct
					local scaledFlat = WeaponData.ScaleProperty(attr.l99Flat, itemInstance.itemLevel)
					flatBonuses[stat] = flatBonuses[stat] + scaledFlat
				end
			elseif attr.operation == "WeightReduce" then
				-- Weight reduction: subtract from scaled base
				pctBonuses.wt = pctBonuses.wt + attr.pct
				local scaledFlat = WeaponData.ScaleProperty(attr.l99Flat, itemInstance.itemLevel)
				flatBonuses.wt = flatBonuses.wt + scaledFlat
			end
		end
	end

	-- Apply bonuses: percentage uses scaled native BEFORE rarity bonuses
	local finalDamage = profile.damage + math.round(profile.damage * pctBonuses.damage) + flatBonuses.damage
	local finalDefense = profile.defense + math.round(profile.defense * pctBonuses.defense) + flatBonuses.defense
	local finalRtDelay = profile.rtDelay + math.round(profile.rtDelay * pctBonuses.rtDelay) + flatBonuses.rtDelay
	-- Weight: reduction subtracts
	local finalWt = profile.wt - math.round(profile.wt * pctBonuses.wt) - flatBonuses.wt

	return {
		damage = math.max(0, finalDamage),
		wt = finalWt, -- can go negative (STR/negative-WT formula resolves later)
		rtDelay = math.max(0, finalRtDelay),
		defense = finalDefense, -- can be negative
		minRange = profile.minRange,
		maxRange = profile.maxRange,
		pattern = profile.pattern,
		projectileType = profile.projectileType,
		handClass = profile.handClass,
		nativePassiveId = profile.nativePassiveId,
	}
end

--------------------------------------------------
-- ARMOR PROFILE (scaled stats at item level)
--------------------------------------------------

function EquipmentService.GetEffectiveArmorProfile(itemInstance)
	return ArmorData.GetScaledProfile(itemInstance.baseArchetypeId, itemInstance.itemLevel)
end

--------------------------------------------------
-- HELPERS
--------------------------------------------------

function EquipmentService.GetAllEquippedItems(unit)
	local items = {}
	if not unit.equipmentSlots then return items end
	for _, item in pairs(unit.equipmentSlots) do
		if item then
			table.insert(items, item)
		end
	end
	return items
end

function EquipmentService.GetMainHandArchetype(unit)
	local mainHand = unit.equipmentSlots and unit.equipmentSlots.MainHand
	if not mainHand then return nil end
	return WeaponData.GetByArchetypeId(mainHand.baseArchetypeId)
end

function EquipmentService.Is2HEquipped(unit)
	local archetype = EquipmentService.GetMainHandArchetype(unit)
	return archetype and archetype.handClass == "2H"
end

function EquipmentService.GetLoadout(unit)
	return unit.equipmentSlots or {}
end

function EquipmentService.IsArmorSlot(slot)
	return ARMOR_SLOTS[slot] == true
end

return EquipmentService
