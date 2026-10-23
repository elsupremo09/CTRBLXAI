--!strict
-- WeaponPassiveService.lua
-- CTRBLXAI | Weapon on-hit / weapon-stat passive dispatch (Group 1, 2026-10-23)
--
-- Single source for "what weapon passives does this unit have, and what do they
-- do" for the combat pipeline. Collects a unit's active weapon passives from TWO
-- namespaces and normalizes them to one canonical key:
--   1. the main-hand archetype's nativePassiveId (bare string, e.g. "Brutal")
--   2. rolled bonus passives on the main-hand (BonusData "PAS-xxx" ids)
--
-- SCOPE (Group 1, DB-grounded):
--   * Weapon-STAT passives (Brutal / Stagger / Bulwark) are applied by
--     EquipmentService.RebuildUnitStats via ApplyWeaponStatMods -- they modify the
--     unit's weapon damage / RT delay at profile-build time, so they also flow into
--     skills that scale off weapon damage (DB wording: "Effective Weapon Damage =").
--   * Combat-MOMENT passives (Armor Pierce, Piercing Edge, Precision Strike, Tricky,
--     True Strike, Backstab, Executioner, Bypass, Drain) and the STATUS-appliers
--     (Venomous, Lacerate, Freeze, Lullaby, Poisonous) are consumed by
--     CombatResolver on the BASIC ATTACK path only. Whether they also ride skills is
--     a per-skill design question, deliberately NOT wired here.
--
-- Passives collected from the MAIN HAND only (a weapon passive belongs to the
-- weapon). Nil-safe throughout: a unit with no weapon returns no keys and every
-- query is a no-op (multiplier 1, empty list, false).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Content = ReplicatedStorage:WaitForChild("Content")

local WeaponData = require(Content:WaitForChild("WeaponData"))

local WeaponPassiveService = {}

-- Rolled bonus-passive id -> canonical key. Only the Group-1 reused-weapon
-- passives are mapped; other PAS ids (threshold/ward/transform) are not Group 1.
local PAS_ID_TO_KEY: { [string]: string } = {
	["PAS-001"] = "Brutal",
	["PAS-002"] = "Stagger",
	["PAS-004"] = "ArmorPierce",
	["PAS-022"] = "Poisonous",
	["PAS-037"] = "Ignite",
	["PAS-038"] = "Backstab",
	["PAS-039"] = "Executioner",
	["PAS-040"] = "Drain",
	["PAS-041"] = "Bypass",
	["PAS-042"] = "TrueStrike",
	["PAS-043"] = "PrecisionStrike",
	["PAS-044"] = "Tricky",
	["PAS-046"] = "Bulwark",
	["PAS-050"] = "Venomous",
	["PAS-051"] = "PiercingEdge",
	["PAS-052"] = "Lacerate",
	["PAS-053"] = "Freeze",
	["PAS-054"] = "Lullaby",
}

-- Status-applier key -> status id it inflicts on hit (the statuses already exist
-- in StatusService / elements_statuses and are applied through the normal path).
local ON_HIT_STATUS: { [string]: string } = {
	Venomous = "Venom",
	Lacerate = "Bleed",
	Freeze = "Frozen",
	Lullaby = "Sleep",
	Poisonous = "Poison",
}

-- Collect the set of canonical weapon-passive keys active on a unit's main hand.
function WeaponPassiveService.GetKeys(unit: any): { [string]: boolean }
	local keys: { [string]: boolean } = {}
	local mh = unit and unit.equipmentSlots and unit.equipmentSlots.MainHand
	if not mh then return keys end

	-- (1) native archetype passive (bare canonical string)
	local arch = WeaponData.GetByArchetypeId(mh.baseArchetypeId)
	if arch and arch.nativePassiveId then
		keys[arch.nativePassiveId] = true
	end

	-- (2) rolled bonus passives on the main hand (PAS-xxx)
	if type(mh.bonusPassiveIds) == "table" then
		for _, pid in ipairs(mh.bonusPassiveIds) do
			local k = PAS_ID_TO_KEY[pid]
			if k then keys[k] = true end
		end
	end

	return keys
end

function WeaponPassiveService.Has(unit: any, key: string): boolean
	return WeaponPassiveService.GetKeys(unit)[key] == true
end

-- The three WEAPON-STAT passives. These modify weapon damage / RT delay at profile-
-- build time (ApplyWeaponStatMods) and are deliberately MAIN-HAND-ONLY: "which weapon
-- does an off-hand/glove/body passive modify" is an open Designer question (2026-10-23),
-- so they must NOT be collected from other slots. GetCombatKeys excludes them.
local WEAPON_STAT_KEYS: { [string]: boolean } = {
	Brutal = true, Stagger = true, Bulwark = true,
}

-- Collect ON-HIT / ATTACK-MODIFIER weapon-passive keys from EVERY equipped slot that
-- can carry them (main hand + off-hand + gloves), per ItemGenerator eligibility
-- (isWeaponish = weapon/off-hand/gloves) and DB bonus_passives eligible_item_types
-- (user ruling 2026-10-23). These passives modify the unit's ATTACKS, so they apply
-- no matter which equipped item rolled them. The weapon-STAT passives are excluded
-- here (still main-hand-only via GetKeys). Nil-safe.
local COMBAT_SLOTS = { "MainHand", "OffHand", "Gloves" }
function WeaponPassiveService.GetCombatKeys(unit: any): { [string]: boolean }
	local keys: { [string]: boolean } = {}
	if not (unit and unit.equipmentSlots) then return keys end
	for _, slot in ipairs(COMBAT_SLOTS) do
		local item = unit.equipmentSlots[slot]
		if item then
			-- native archetype passive (bare canonical string) -- weapons only carry one
			local arch = WeaponData.GetByArchetypeId(item.baseArchetypeId)
			if arch and arch.nativePassiveId and not WEAPON_STAT_KEYS[arch.nativePassiveId] then
				keys[arch.nativePassiveId] = true
			end
			-- rolled bonus passives (PAS-xxx)
			if type(item.bonusPassiveIds) == "table" then
				for _, pid in ipairs(item.bonusPassiveIds) do
					local k = PAS_ID_TO_KEY[pid]
					if k and not WEAPON_STAT_KEYS[k] then keys[k] = true end
				end
			end
		end
	end
	return keys
end

-- True if any equipped combat slot carries the given ON-HIT/ATTACK key.
function WeaponPassiveService.HasCombat(unit: any, key: string): boolean
	return WeaponPassiveService.GetCombatKeys(unit)[key] == true
end

-- Ignite (PAS-037, Group 2): stored-Burn fraction override. DB: Ignite's stored Burn
-- = round(Fire Damage Dealt x 0.25), overriding the base Burn 0.20 for this source.
-- Returns 0.25 when the unit carries Ignite, else nil (caller falls back to base).
-- The conditional Fire re-type of an otherwise-Physical attack is applied by
-- CombatResolver (basic attack AND skill) via Has(unit, "Ignite").
function WeaponPassiveService.IgniteBurnFraction(unit: any): number?
	return WeaponPassiveService.HasCombat(unit, "Ignite") and 0.25 or nil
end

-- WEAPON-STAT passives. Mutates unit.weaponDamage / unit.weaponRtDelay in place.
-- Called by EquipmentService.RebuildUnitStats AFTER the weapon profile + trait
-- folds are applied, so these sit on top of the finalized weapon stats and flow
-- everywhere weaponDamage/weaponRtDelay are read (basic attacks AND skills).
-- All "before STR scaling" per DB -- weaponDamage is the pre-STR base; STR scaling
-- happens later in CalcAttackPower. No-op when the relevant passive is absent.
function WeaponPassiveService.ApplyWeaponStatMods(unit: any)
	if not unit then return end
	local keys = WeaponPassiveService.GetKeys(unit)
	if next(keys) == nil then return end

	local dmg = unit.weaponDamage or 0
	local def = unit.weaponDefense or 0

	-- Bulwark: + 25% of base Weapon Defense to base Weapon Damage (PAS-046).
	if keys.Bulwark and def > 0 then
		dmg = dmg + def * 0.25
	end
	-- Brutal: Effective Weapon Damage x1.20 (PAS-001).
	if keys.Brutal then
		dmg = dmg * 1.20
	end
	if keys.Bulwark or keys.Brutal then
		unit.weaponDamage = math.max(0, math.round(dmg))
	end

	-- Stagger: Effective Weapon RT Delay x1.25 (PAS-002).
	if keys.Stagger and unit.weaponRtDelay then
		unit.weaponRtDelay = math.round(unit.weaponRtDelay * 1.25)
	end
end

-- Target Defense multiplier from armor-penetration passives (basic attack).
-- Armor Pierce = x0.70 (PAS-004); Piercing Edge = x0.80 (PAS-051). Each is
-- "Strongest only"; if both are present, take the stronger penetration (lower
-- multiplier). Returns 1 when neither is present.
function WeaponPassiveService.DefenseMultiplier(unit: any): number
	local keys = WeaponPassiveService.GetCombatKeys(unit)
	local mult = 1
	if keys.ArmorPierce then mult = math.min(mult, 0.70) end
	if keys.PiercingEdge then mult = math.min(mult, 0.80) end
	return mult
end

-- Hit-quality adjustment for the BASIC ATTACK path. Applies, in order:
--   Tricky         ignore 40% of the target's AGI-derived Evasiveness (PAS-044)
--   PrecisionStrike +15% Hit Quality on Basic Attacks -> flat +0.15 (PAS-043, user ruling 2026-10-23)
--   TrueStrike     Hit Quality cannot drop below 1.0 (PAS-042)
-- defenderAgi is the defender's effective AGI (to recover the evasiveness that was
-- already subtracted upstream). Returns the adjusted hit quality.
function WeaponPassiveService.AdjustBasicHitQuality(unit: any, hitQuality: number, defenderAgi: number): number
	local keys = WeaponPassiveService.GetCombatKeys(unit)
	local hq = hitQuality

	if keys.Tricky then
		local agi = defenderAgi or 10
		local evasiveness = agi / (agi + 200)
		hq = hq + 0.40 * evasiveness
	end
	if keys.PrecisionStrike then
		-- DB "+15% Hit Quality on Basic Attacks" read as a flat additive +0.15 (user
		-- ruling 2026-10-23), applied before the True Strike floor below.
		hq = hq + 0.15
	end
	if keys.TrueStrike and hq < 1.0 then
		hq = 1.0
	end

	return hq
end

-- Conditional final-damage multiplier (basic attack):
--   Backstab    +50% when attacking the target's rear facing zone (PAS-038)
--   Executioner +30% vs targets below 25% current HP (PAS-039)
-- facingZone is "Front" / "Side" / "Back". Multiplicative; 1 when neither applies.
function WeaponPassiveService.ConditionalDamageMultiplier(unit: any, defender: any, facingZone: any): number
	local keys = WeaponPassiveService.GetCombatKeys(unit)
	local mult = 1

	if keys.Backstab and facingZone == "Back" then
		mult = mult * 1.50
	end
	if keys.Executioner and defender and defender.maxHp and defender.maxHp > 0 then
		local frac = (defender.currentHp or defender.maxHp) / defender.maxHp
		if frac < 0.25 then
			mult = mult * 1.30
		end
	end

	return mult
end

-- Bypass: the attack ignores the target's Guard mitigation (PAS-041).
function WeaponPassiveService.BypassesGuard(unit: any): boolean
	return WeaponPassiveService.GetCombatKeys(unit).Bypass == true
end

-- On-hit status ids inflicted by the weapon's status-applier passives (basic
-- attack). Returns an array (possibly empty) of status ids for the resolver to
-- stamp into outcome.appliesStatuses (applied through the normal gated path).
function WeaponPassiveService.OnHitStatuses(unit: any): { string }
	local keys = WeaponPassiveService.GetCombatKeys(unit)
	local out: { string } = {}
	for key, statusId in pairs(ON_HIT_STATUS) do
		if keys[key] then
			table.insert(out, statusId)
		end
	end
	return out
end

-- Drain: fraction of final damage healed back to the attacker on hit (PAS-040).
-- Returns 0 when absent.
function WeaponPassiveService.DrainFraction(unit: any): number
	return WeaponPassiveService.GetCombatKeys(unit).Drain and 0.05 or 0
end

return WeaponPassiveService
