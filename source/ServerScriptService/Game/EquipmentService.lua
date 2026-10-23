-- EquipmentService.lua
local RacePassiveService = require(script.Parent.RacePassiveService)
local TraitEffectService = require(script.Parent.TraitEffectService) -- Perks & Flaws Phase 2
local WeaponPassiveService = require(script.Parent.WeaponPassiveService) -- Weapon passives (Group 1, 2026-10-23)
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

	local archetype: any, itemType = resolveArchetype(itemInstance.baseArchetypeId)
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

-- opts.allowWeaponless (default false): when true, permits emptying the MainHand
-- even though it leaves the unit with no weapon. Used ONLY by whole-unit teardown
-- (recruit dismissal), never by the loadout screen. Every unit must always keep a
-- weapon (2026-10-18 ruling): a weapon can be SWAPPED (Equip replaces the slot in
-- place, which does not call this function) but never plainly removed to leave the
-- unit bare. Off-hand may always be removed (1H alone is a valid loadout).
function EquipmentService.Unequip(unit, slot, opts)
	if not VALID_SLOTS[slot] then
		return false, "Invalid slot"
	end
	if not unit.equipmentSlots or not unit.equipmentSlots[slot] then
		return false, "Slot is empty"
	end

	-- Weapon-retention guard: a unit may never be left without a MainHand weapon.
	if slot == "MainHand" and not (opts and opts.allowWeaponless) then
		return false, "Every unit must keep a weapon — equip a replacement weapon instead of removing this one"
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

-- Consumable slot capacity (2026-10-20): base 3 open slots, hard cap 6. Extra slots are
-- granted by sources whose descriptive text carries the marker "Equipped Item slot
-- capacity +1" — the Utility Belt accessory (ArmorData archetype passive), the rollable
-- Expanded Bandolier (BonusData PAS-055 on an equipped item), and the Chemist/Artificer
-- doctrines (doctrine passiveEffect). Each matching source grants +1. Same string-match
-- convention ArmorPassiveService uses for item RT/range passives.
local CONSUMABLE_SLOT_GRANT_MARKER = "Equipped Item slot capacity +1"
local CONSUMABLE_SLOT_BASE = 3

function EquipmentService.ComputeConsumableSlotCount(unit)
	local maxSlots = unit.maxConsumableSlots or 6
	local grants = 0
	-- (a) Doctrine grant (Chemist / Artificer)
	if unit.doctrineId then
		local doctrine = DoctrineData[unit.doctrineId]
		if doctrine and doctrine.passiveEffect
			and string.find(doctrine.passiveEffect, CONSUMABLE_SLOT_GRANT_MARKER, 1, true) then
			grants = grants + 1
		end
	end
	-- (b) Equipped gear: archetype fixed passive (Utility Belt) + rolled bonus passives (Bandolier)
	for _, item in ipairs(EquipmentService.GetAllEquippedItems(unit)) do
		local arch = ArmorData.GetByArchetypeId(item.baseArchetypeId)
		if arch and arch.passiveName
			and string.find(arch.passiveName, CONSUMABLE_SLOT_GRANT_MARKER, 1, true) then
			grants = grants + 1
		end
		for _, pid in ipairs(item.bonusPassiveIds or {}) do
			local pdef = BonusData.GetPassive(pid)
			if pdef then
				local txt = (pdef.desc or "") .. " " .. (pdef.name or "")
				if string.find(txt, CONSUMABLE_SLOT_GRANT_MARKER, 1, true) then
					grants = grants + 1
				end
			end
		end
	end
	local count = CONSUMABLE_SLOT_BASE + grants
	if count < CONSUMABLE_SLOT_BASE then count = CONSUMABLE_SLOT_BASE end
	if count > maxSlots then count = maxSlots end
	return count
end

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
		-- Perks & Flaws Phase 2 (TRAIT-ARMORSLOT-BONUS): <Slot> Specialist x2 / Klutz x0.5
		-- scales this armor piece's primary-stat Bonus lines (weapons / no trait: slotMult = 1).
		local itemArmorArch = ArmorData.GetByArchetypeId(item.baseArchetypeId)
		local slotMult = itemArmorArch and TraitEffectService.GetArmorSlotMultiplier(unit, itemArmorArch.slot) or 1
		for _, line in ipairs(item.bonusLines or {}) do
			local attr = BonusData.GetAttribute(line.id)
			if attr and attr.operation == "PrimaryStat" then
				local stat = attr.stat
				if primaryPctBonuses[stat] then
					primaryPctBonuses[stat] = primaryPctBonuses[stat] + attr.pct * slotMult
					local scaledFlat = WeaponData.ScaleProperty(attr.l99Flat, item.itemLevel)
					if slotMult ~= 1 then scaledFlat = math.round(scaledFlat * slotMult) end
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

	-- 3b-T. Perks & Flaws Phase 2 (TRAIT-STAT-FOLD): unit-trait primary stat %
	-- (Brawny/Weak STR +/-15%, Alert/Dull, ...). Same shape as the race fold above:
	-- round(total * (1 + summed perk+flaw offset)). Static per unit; nil for no traits.
	local traitMods = TraitEffectService.GetStatModifiers(unit)
	if traitMods then
		for stat, pctMod in pairs(traitMods) do
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
				-- Perks & Flaws Phase 2 (TRAIT-ARMORSLOT-BASE): <Slot> Specialist x2 / Klutz x0.5
				-- on this piece's Base Defense / HP / MP. Armor WT intentionally NOT scaled.
				local sm = TraitEffectService.GetArmorSlotMultiplier(unit, aArch.slot)
				if sm ~= 1 then
					armorDefense = armorDefense + math.round(scaled.defense * sm)
					armorWt = armorWt + scaled.wt
					armorHp = armorHp + math.round(scaled.hp * sm)
					armorMp = armorMp + math.round(scaled.mp * sm)
				else
					armorDefense = armorDefense + scaled.defense
					armorWt = armorWt + scaled.wt
					armorHp = armorHp + scaled.hp
					armorMp = armorMp + scaled.mp
				end
			end
		end
	end

	-- Perks & Flaws Phase 2 (TRAIT-ARMORDEF): Defensive / Exposed Armor -- summed armor
	-- Defense x (1 +/- 20%/24%). Neutral (no trait) path leaves armorDefense untouched.
	local armorDefMult = TraitEffectService.GetArmorDefenseMultiplier(unit)
	if armorDefMult ~= 1 then
		armorDefense = math.round(armorDefense * armorDefMult)
	end

	-- Perks & Flaws Phase 2 (TRAIT-034/092): Ironhide / Brittle Plating -- add/subtract
	-- a fraction (±20%/25%) of total non-weapon (armor) WT to/from base armor defense.
	-- armorWt is the summed WT of all equipped armor pieces (non-weapon by definition).
	local armorFromWtFrac = TraitEffectService.GetArmorFromWtFraction(unit)
	if armorFromWtFrac ~= 0 and armorWt and armorWt > 0 then
		armorDefense = armorDefense + math.round(armorWt * armorFromWtFrac)
	end
	-- Floor armor Defense at 0 (consistent with the force/damage/WT folds). Only a
	-- rare stack (Brittle Plating Greater + Exposed Armor Greater + a slot Klutz) could
	-- push it negative. DESIGNER: if negative armor Defense is intended, drop this floor.
	if armorDefense < 0 then armorDefense = 0 end

	unit.armorDefense = armorDefense
	unit.armorWt = armorWt

	-- Write effective stats
	-- Clamp all stats to minimum 0 (doctrine packages can push stats negative at low levels)
	-- 3d. Status stat-modifiers (Slice 5 buff mechanism). Folded here so timed
	-- buffs (Banner Blessing +15% all, Fortune Boon +50% LUK) and the existing
	-- Weakened/Giant/Rush/Enlightened offsets finally affect effectiveStats via
	-- the rebuild path. DEFERRED require avoids a load-time circular dependency
	-- (EquipmentService <- GameConstants -> StatusService): require at call time.
	-- Applied as round(total * (1 + pct)) per stat, matching the RacePassive 3b
	-- pattern, AFTER doctrine/equipment/race/armor and BEFORE the min-0 clamp.
	if unit.statusInstances then
		local StatusService = require(script.Parent.StatusService)
		local statMods = StatusService.GetStatusStatModifiers(unit)
		if statMods then
			for _, stat in ipairs({"STR", "AGI", "INT", "VIT", "DEX", "LUK"}) do
				local pct = statMods[stat]
				if pct and pct ~= 0 then
					total[stat] = math.round(total[stat] * (1 + pct))
				end
			end
		end
	end

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
			local raceEntry = RaceData.GetRace(unit.raceId)
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
		unit.weaponElement = nil
	end

	-- 4a. OGRE — Brutish Bulk (races row 'Ogre', 2026-10-02): Weapon WT +20%.
	-- Applied after the Mechanical raw-WT step and before derived stats, so the
	-- effective (STR-reduced) Weapon WT, Basic Attack RT and the Ogre on-hit RT
	-- delay all inherit it. Non-positive WT is left alone (x1.20 would make a
	-- negative WT "lighter").
	local wtMult = RacePassiveService.GetWeaponWtMultiplier(unit)
	if wtMult ~= 1 and unit.weaponWt and unit.weaponWt > 0 then
		unit.weaponWt = math.floor(unit.weaponWt * wtMult + 1e-6)
	end

	-- 4a-T. Perks & Flaws Phase 2 (TRAIT-WEAPON): MainHand weapons only.
	--   <Weapon> Specialist / Klutz: weapon WT x(1 -/+ 25%), base weapon damage x(1 +/- 25%)
	--     when the equipped MainHand archetype name matches (TraitEffectService).
	--   Heavy Hitter / Feather Strikes: +/- round(weapon WT x 20%/25%) to base weapon damage
	--     (uses the final, trait-adjusted weapon WT; non-positive WT contributes nothing).
	-- Applied after the race WT steps so effective WT / Basic Attack RT inherit it.
	if mainHand then
		local traitWtMult = TraitEffectService.GetWeaponWtMultiplier(unit)
		if traitWtMult ~= 1 and unit.weaponWt and unit.weaponWt > 0 then
			unit.weaponWt = math.floor(unit.weaponWt * traitWtMult + 1e-6)
		end
		-- Perks & Flaws Phase 2 (TRAIT-043/118): Strong Back / Weak Grip.
		-- Gear (weapon) WT changed by -/+ frac; the magnitude of that WT change is
		-- added to / subtracted from STR. STR delta uses the pre-change weapon WT so
		-- the "amount" matches the WT actually shifted. effectiveStats was assigned
		-- earlier (as `total`); ComputeDerivedStats runs after this, so the STR bump
		-- flows into derived stats and STR-based WT reduction. Weapon-only scope
		-- (DESIGNER: confirm whether "Gear WT" should include armor WT too).
		local gearFrac = TraitEffectService.GetGearWtStrFraction(unit)
		if gearFrac ~= 0 and unit.weaponWt and unit.weaponWt > 0 and unit.effectiveStats then
			local wtDelta = math.round(unit.weaponWt * gearFrac)
			unit.weaponWt = math.max(0, unit.weaponWt - wtDelta)
			unit.effectiveStats.STR = math.max(0, (unit.effectiveStats.STR or 0) + wtDelta)
		end
		local traitDmgMult = TraitEffectService.GetWeaponDamageMultiplier(unit)
		if traitDmgMult ~= 1 and unit.weaponDamage then
			unit.weaponDamage = math.max(0, math.round(unit.weaponDamage * traitDmgMult))
		end
		local wtDmgFrac = TraitEffectService.GetWeaponWtDamageFraction(unit)
		if wtDmgFrac ~= 0 and unit.weaponDamage and unit.weaponWt and unit.weaponWt > 0 then
			unit.weaponDamage = math.max(0, unit.weaponDamage + math.round(unit.weaponWt * wtDmgFrac))
		end

		-- Weapon-STAT passives (Group 1, 2026-10-23): Brutal / Bulwark (weapon damage)
		-- and Stagger (weapon RT delay), applied on top of the finalized (trait-folded)
		-- weapon stats so they also flow into skills that scale off weapon damage.
		WeaponPassiveService.ApplyWeaponStatMods(unit)

		-- Weapon element (2026-10-23): a rolled elemental Transformation passive on the
		-- main hand re-types basic attacks to that element; nil = Physical. Flows into the
		-- existing element reaction / terrain / status-trigger engine via outcome.element.
		unit.weaponElement = WeaponData.GetInstanceElement(mainHand)
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
	-- Perks & Flaws Phase 2 (TRAIT-HPMP): Hardy / Frail (+/-20% max HP from VIT) and Deep /
	-- Shallow Well (+/-20% max MP from INT) scale ONLY the stat term; neutral path unchanged.
	local vitHp = vit * 4
	local intMp = int * 2
	local hpFromVit = TraitEffectService.GetHpFromVitMultiplier(unit)
	local mpFromInt = TraitEffectService.GetMpFromIntMultiplier(unit)
	if hpFromVit ~= 1 then vitHp = math.round(vitHp * hpFromVit) end
	if mpFromInt ~= 1 then intMp = math.round(intMp * mpFromInt) end
	unit.maxHp = 50 + vitHp + armorHp
	unit.maxMp = 20 + intMp + armorMp

	-- Clamp current to new max (don't increase current beyond max)
	if unit.currentHp and unit.currentHp > unit.maxHp then
		unit.currentHp = unit.maxHp
	end
	if unit.currentMp and unit.currentMp > unit.maxMp then
		unit.currentMp = unit.maxMp
	end

	-- 6. Compute all derived stats (formulas from all primary stats)
	GameConstants.ComputeDerivedStats(unit)

	-- 6b. Perks & Flaws Phase 2 (TRAIT-FORCESTAB): Powerful Build / Frail Arms / Overwhelming
	-- Force (flaw) flat Force; Rooted / Toppling flat Stability. Floored at 0.
	local derived = unit.derivedStats
	if derived then
		local fMod = TraitEffectService.GetForceModifier(unit)
		if fMod ~= 0 and derived.force then
			derived.force = math.max(0, derived.force + fMod)
		end
		local sMod = TraitEffectService.GetStabilityModifier(unit)
		if sMod ~= 0 and derived.stability then
			derived.stability = math.max(0, derived.stability + sMod)
		end
		-- Perks & Flaws (Phase 2b): Far/Near-Sighted adjust Discovery Radius. Floored at 0.
		local dMod = TraitEffectService.GetDiscoveryRadiusModifier(unit)
			+ RacePassiveService.GetDiscoveryRadiusModifier(unit) -- Avian Keen Sight +1
		if dMod ~= 0 and derived.discoveryRadius then
			derived.discoveryRadius = math.max(0, derived.discoveryRadius + dMod)
		end
		-- ARTIFICER — Applied Artifice drawback: Bonus Skill Range -1, explicitly allowed
		-- to go below 0 (no floor). 2026-10-20.
		if unit.doctrineId == "DOC-ARTIFICER" and derived.bonusSkillRange ~= nil then
			derived.bonusSkillRange = derived.bonusSkillRange - 1
		end
	end

	-- 6c. GEAR DERIVED BONUSES (Derived family, 2026-10-23). Fold equipment's rolled
	-- Derived / DerivedMultiplier bonus lines (Fortune / Precision / Evasiveness / Skill
	-- Potency / Healing Output / Debuff Resistance / RT Delay Resistance) onto the unit.
	-- unit.gearDerived = gear-only bonus the combat + loot consumers read (fraction added
	-- for pp families; product for multiplier families). derivedStats is also updated so
	-- the Info panel shows the combined value. Per DB item_rarity_rules: applied AFTER
	-- Total Primary Stats and NOT scaled by Item Level (fixedValue used as-is).
	local gearDerived = {
		precision = 0, evasiveness = 0, fortune = 0, skillPotency = 0,
		healingOutput = 1, debuffResist = 1, rtDelayResist = 1,
	}
	for _, item in ipairs(equippedItems) do
		for _, line in ipairs(item.bonusLines or {}) do
			local attr = BonusData.GetAttribute(line.id)
			if attr and attr.stat and gearDerived[attr.stat] ~= nil then
				if attr.operation == "Derived" then
					gearDerived[attr.stat] = gearDerived[attr.stat] + (attr.fixedValue or 0)
				elseif attr.operation == "DerivedMultiplier" then
					gearDerived[attr.stat] = gearDerived[attr.stat] * (attr.fixedValue or 1)
				end
			end
		end
	end
	unit.gearDerived = gearDerived
	if derived then
		-- Percentage-point families are stored as % in derivedStats; add gear as pp.
		derived.precision   = derived.precision   + gearDerived.precision * 100
		derived.evasiveness = derived.evasiveness + gearDerived.evasiveness * 100
		derived.unitFortune = derived.unitFortune + gearDerived.fortune * 100
		-- Multiplier / additive-multiplier families: fold the gear component in.
		derived.skillPotency  = math.round((derived.skillPotency + gearDerived.skillPotency) * 1000) / 1000
		derived.debuffResist  = math.round(derived.debuffResist * gearDerived.debuffResist * 1000) / 1000
		derived.rtDelayResist = math.round(derived.rtDelayResist * gearDerived.rtDelayResist * 1000) / 1000
		-- Healing Output is a new caster-side healing multiplier (base 1.0 x gear).
		derived.healingOutput = math.round(gearDerived.healingOutput * 1000) / 1000
	end

	-- 7. Consumable slot capacity (2026-10-20): recompute from gear + doctrine grants,
	-- clamped to [3, maxConsumableSlots]. Independent of the stat math above; runs on
	-- every equip/unequip/doctrine change and at boot establishment (all call RebuildUnitStats).
	unit.maxConsumableSlots = unit.maxConsumableSlots or 6
	unit.consumableSlotCount = EquipmentService.ComputeConsumableSlotCount(unit)
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
