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
	-- Rolled copies of weapon natives (2026-10-28): these PAS ids had no reader. They now count as
	-- the same key as the weapon native, so every existing reader picks them up.
	["PAS-003"] = "Knockback",
	["PAS-005"] = "Fortify",
	["PAS-006"] = "ArcaneFlow",
	["PAS-008"] = "ArcaneReach",
	["PAS-045"] = "HighGround",
	["PAS-047"] = "Reap",
	["PAS-048"] = "Pull",
	["PAS-049"] = "Charge",
}

-- Status-applier key -> status id it inflicts on hit (the statuses already exist
-- in StatusService / elements_statuses and are applied through the normal path).
local ON_HIT_STATUS: { [string]: string } = {
	Venomous = "Venom",
	Lacerate = "Bleed",
	Freeze = "Frozen",   -- weapon Freeze: 1 turn + Thawed (CombatResolver routes it to StatusService.ApplyWeaponFreeze)
	Lullaby = "Sleep",
	Poisonous = "Poison",
	-- DESIGNER RULING 2026-11-21 (weapons_equipment 161/162): Basic Attack on-hit debuffs, native only.
	Lash = "Lashed",     -- Whip
	Breaker = "Blunted", -- Sword Breaker
}

-- Native passive keys of one weapon archetype: nativePassiveId plus nativeExtraPassiveIds (Boomerang
-- Tricky + Rebound, weapons_equipment 121/164). One reader so every collector sees both (DAT-001).
local function nativeKeysOf(arch: any): { string }
	local out: { string } = {}
	if not arch then return out end
	if arch.nativePassiveId then table.insert(out, arch.nativePassiveId) end
	if type(arch.nativeExtraPassiveIds) == "table" then
		for _, k in ipairs(arch.nativeExtraPassiveIds) do table.insert(out, k) end
	end
	return out
end

-- Collect the set of canonical weapon-passive keys active on a unit's main hand.
function WeaponPassiveService.GetKeys(unit: any): { [string]: boolean }
	local keys: { [string]: boolean } = {}
	-- Dual wield (2026-10-28): during an off-hand hit (unit._dwHand == "OffHand") the off-hand
	-- weapon's keys are used instead (each hand delivers its own passives).
	local handSlot = if (unit and unit._dwHand == "OffHand") then "OffHand" else "MainHand"
	local mh = unit and unit.equipmentSlots and unit.equipmentSlots[handSlot]
	if not mh then return keys end

	-- (1) native archetype passive (bare canonical string)
	local arch = WeaponData.GetByArchetypeId(mh.baseArchetypeId)
	for _, nk in ipairs(nativeKeysOf(arch)) do
		keys[nk] = true
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

-- Exported read-only (2026-10-29) so GearPassiveSummary uses the SAME rule tables as
-- combat instead of a duplicate copy (DAT-001).
WeaponPassiveService.PAS_ID_TO_KEY = PAS_ID_TO_KEY
WeaponPassiveService.WEAPON_STAT_KEYS = WEAPON_STAT_KEYS

-- Collect ON-HIT / ATTACK-MODIFIER weapon-passive keys from EVERY equipped slot that
-- can carry them (main hand + off-hand + gloves), per ItemGenerator eligibility
-- (isWeaponish = weapon/off-hand/gloves) and DB bonus_passives eligible_item_types
-- (user ruling 2026-10-23). These passives modify the unit's ATTACKS, so they apply
-- no matter which equipped item rolled them. The weapon-STAT passives are excluded
-- here (still main-hand-only via GetKeys). Nil-safe.
local COMBAT_SLOTS = { "MainHand", "OffHand", "Gloves" }
-- Same collection as GetCombatKeys, but COUNTS how many equipped sources carry each key (a native
-- and a rolled copy, or the same passive rolled on two items). Used where the DB stacking rule is
-- "Additive" or "Independent" (Arcane Reach, Guard Bonus, Knockback, Pull). 2026-10-28.
function WeaponPassiveService.GetCombatKeyCounts(unit: any): { [string]: number }
	local counts: { [string]: number } = {}
	if not (unit and unit.equipmentSlots) then return counts end
	for _, slot in ipairs(COMBAT_SLOTS) do
		local item = unit.equipmentSlots[slot]
		if item and (slot == "MainHand" or slot == "OffHand") then
			local _a = WeaponData.GetByArchetypeId(item.baseArchetypeId)
			if _a and _a.category == "Weapon" then
				local want = if unit._dwHand == "OffHand" then "OffHand" else "MainHand"
				if slot ~= want or (slot == "OffHand" and not unit.dualWieldActive) then item = nil end
			end
		end
		if item then
			local arch = WeaponData.GetByArchetypeId(item.baseArchetypeId)
			for _, nk in ipairs(nativeKeysOf(arch)) do
				if not WEAPON_STAT_KEYS[nk] then counts[nk] = (counts[nk] or 0) + 1 end
			end
			if type(item.bonusPassiveIds) == "table" then
				for _, pid in ipairs(item.bonusPassiveIds) do
					local k = PAS_ID_TO_KEY[pid]
					if k and not WEAPON_STAT_KEYS[k] then counts[k] = (counts[k] or 0) + 1 end
				end
			end
		end
	end
	return counts
end

-- How many equipped items (ANY slot) carry this rolled passive id. For passives that may roll on
-- armor as well as weapons (e.g. PAS-035 Guard Bonus on body armor). An off-hand weapon held while
-- dual wield is inactive counts as inactive.
function WeaponPassiveService.CountRolledPassive(unit: any, passiveId: string): number
	local n = 0
	if not (unit and unit.equipmentSlots) then return 0 end
	for slot, item in pairs(unit.equipmentSlots) do
		local skip = false
		if slot == "OffHand" and item and not unit.dualWieldActive then
			local _a = WeaponData.GetByArchetypeId(item.baseArchetypeId)
			skip = _a ~= nil and _a.category == "Weapon"
		end
		if item and not skip and type(item.bonusPassiveIds) == "table" then
			for _, pid in ipairs(item.bonusPassiveIds) do
				if pid == passiveId then n += 1 end
			end
		end
	end
	return n
end

-- Knockback / Pull sources (DB stacking "Independent; displacement merges"): each source adds its
-- own push to the attack's merged knockback.
function WeaponPassiveService.GetKnockbackSourceCount(unit: any): number
	return WeaponPassiveService.GetCombatKeyCounts(unit).Knockback or 0
end
function WeaponPassiveService.GetPullSourceCount(unit: any): number
	return WeaponPassiveService.GetCombatKeyCounts(unit).Pull or 0
end

function WeaponPassiveService.GetCombatKeys(unit: any): { [string]: boolean }
	local keys: { [string]: boolean } = {}
	if not (unit and unit.equipmentSlots) then return keys end
	for _, slot in ipairs(COMBAT_SLOTS) do
		local item = unit.equipmentSlots[slot]
		-- Dual wield (2026-10-28): a WEAPON in a hand slot delivers only on its own hand's hits
		-- (main hand by default; off hand only while unit._dwHand == "OffHand", and only while dual
		-- wield is active). Shields / off-hand items and gloves always apply.
		if item and (slot == "MainHand" or slot == "OffHand") then
			local _a = WeaponData.GetByArchetypeId(item.baseArchetypeId)
			if _a and _a.category == "Weapon" then
				local want = if unit._dwHand == "OffHand" then "OffHand" else "MainHand"
				if slot ~= want or (slot == "OffHand" and not unit.dualWieldActive) then item = nil end
			end
		end
		if item then
			-- native archetype passive (bare canonical string) -- weapons only carry one
			local arch = WeaponData.GetByArchetypeId(item.baseArchetypeId)
			for _, nk in ipairs(nativeKeysOf(arch)) do
				if not WEAPON_STAT_KEYS[nk] then keys[nk] = true end
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
-- = round(Fire Damage Dealt x 0.30) (DESIGNER RULING 2026-11-21, was 0.25), overriding the base
-- Burn 0.20 for this source. Returns 0.30 when the unit carries Ignite, else nil (caller falls back).
-- The conditional Fire re-type of an otherwise-Physical attack is applied by
-- CombatResolver (basic attack AND skill) via Has(unit, "Ignite").
function WeaponPassiveService.IgniteBurnFraction(unit: any): number?
	return WeaponPassiveService.HasCombat(unit, "Ignite") and 0.30 or nil
end

-- WEAPON-STAT passives. Mutates unit.weaponDamage / unit.weaponRtDelay in place.
-- Called by EquipmentService.RebuildUnitStats AFTER the weapon profile + trait
-- folds are applied, so these sit on top of the finalized weapon stats and flow
-- everywhere weaponDamage/weaponRtDelay are read (basic attacks AND skills).
-- All "before STR scaling" per DB -- weaponDamage is the pre-STR base; STR scaling
-- happens later in CalcAttackPower. No-op when the relevant passive is absent.
-- Same weapon-stat passives for a single weapon ITEM (used for the off-hand weapon's own profile
-- while dual wielding, 2026-10-28). Returns adjusted damage, rtDelay.
function WeaponPassiveService.ApplyItemStatMods(item: any, damage: number, defense: number, rtDelay: number): (number, number)
	local keys: { [string]: boolean } = {}
	local arch = item and WeaponData.GetByArchetypeId(item.baseArchetypeId)
	if arch and arch.nativePassiveId then keys[arch.nativePassiveId] = true end
	for _, pid in ipairs((item and item.bonusPassiveIds) or {}) do
		local k = PAS_ID_TO_KEY[pid]
		if k then keys[k] = true end
	end
	local dmg = damage or 0
	if keys.Bulwark and (defense or 0) > 0 then dmg = dmg + defense * 0.25 end
	if keys.Brutal then dmg = dmg * 1.20 end
	local rtd = rtDelay or 0
	if keys.Stagger then rtd = math.round(rtd * 1.25) end
	return math.max(0, math.round(dmg)), rtd
end

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
-- Armor Pierce = x0.50 (PAS-004); Piercing Edge = x0.70 (PAS-051) -- DESIGNER RULING 2026-11-21
-- (weapons_equipment 102/108; was x0.70 / x0.80). Callers apply it through ScaleDefensePower. Each is
-- "Strongest only"; if both are present, take the stronger penetration (lower
-- multiplier). Returns 1 when neither is present.
function WeaponPassiveService.DefenseMultiplier(unit: any): number
	local keys = WeaponPassiveService.GetCombatKeys(unit)
	local mult = 1
	if keys.ArmorPierce then mult = math.min(mult, 0.50) end
	if keys.PiercingEdge then mult = math.min(mult, 0.70) end
	return mult
end

local TRUE_STRIKE_FLOOR = 1.05  -- weapons_equipment / PAS-042: "Hit Quality cannot go below 105%"

-- Hit-quality adjustment for the BASIC ATTACK path. Applies, in order:
--   Tricky         ignore 40% of the target's AGI-derived Evasiveness (PAS-044)
--   PrecisionStrike +15% Hit Quality on Basic Attacks -> flat +0.15 (PAS-043, user ruling 2026-10-23)
--   TrueStrike     Hit Quality cannot drop below TRUE_STRIKE_FLOOR = 1.05 (PAS-042, DESIGNER RULING 2026-11-21)
-- defenderAgi is the defender's effective AGI (to recover the evasiveness that was
-- already subtracted upstream). Returns the adjusted hit quality.
function WeaponPassiveService.AdjustBasicHitQuality(unit: any, hitQuality: number, defenderAgi: number, totalEvasiveness: any): number
	local keys = WeaponPassiveService.GetCombatKeys(unit)
	local hq = hitQuality

	-- Tricky: "ignore 40% of target Evasiveness" -- the target's WHOLE Evasiveness (gear, traits,
	-- Retreat Boots, Evasion Surge, doctrine ... as summed in CombatResolver.calcHitQuality), not just
	-- the AGI part (checklist fix 2026-10-29). Falls back to the AGI part if no total is passed.
	if keys.Tricky then
		local evasiveness = totalEvasiveness
		if type(evasiveness) ~= "number" then
			local agi = defenderAgi or 10
			evasiveness = agi / (agi + 200)
		end
		hq = hq + 0.40 * math.max(0, evasiveness)
	end
	if keys.PrecisionStrike then
		-- DB "+15% Hit Quality on Basic Attacks" read as a flat additive +0.15 (user
		-- ruling 2026-10-23), applied before the True Strike floor below.
		hq = hq + 0.15
	end
	if keys.TrueStrike and hq < TRUE_STRIKE_FLOOR then
		hq = TRUE_STRIKE_FLOOR
	end

	return hq
end

-- Hit-quality adjustment for a WEAPON SKILL (skill tagged Weapon Scaling; user ruling 2026-10-29):
-- Tricky and True Strike apply like on a Basic Attack. Precision Strike stays Basic Attack only (its
-- DB text says "on Basic Attacks").
function WeaponPassiveService.AdjustWeaponSkillHitQuality(unit: any, hitQuality: number, defenderAgi: number, totalEvasiveness: any): number
	local keys = WeaponPassiveService.GetCombatKeys(unit)
	local hq = hitQuality
	if keys.Tricky then
		local evasiveness = totalEvasiveness
		if type(evasiveness) ~= "number" then
			local agi = defenderAgi or 10
			evasiveness = agi / (agi + 200)
		end
		hq = hq + 0.40 * math.max(0, evasiveness)
	end
	if keys.TrueStrike and hq < TRUE_STRIKE_FLOOR then
		hq = TRUE_STRIKE_FLOOR
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

-- GuardBonus (weapon native, Shield): +15 percentage points of Guard damage mitigation while
-- the wearer is Guarding (DB "On Guard, +15% damage mitigation"). Folded into unit.guardBonus by
-- the Guard command alongside Race/Trait/Armor; the damage path reads guardBonus and clamps to
-- GUARD_CAP. Returns 0 without the passive.
function WeaponPassiveService.GetGuardMitigationBonus(unit: any): number
	-- Additive under the Guard cap (DB PAS-035 stacking): +0.15 per native Guard Bonus source plus
	-- +0.15 per rolled PAS-035 on ANY equipped item (shields, body armor). Cap applied by callers.
	local n = (WeaponPassiveService.GetCombatKeyCounts(unit).GuardBonus or 0)
		+ WeaponPassiveService.CountRolledPassive(unit, "PAS-035")
	return 0.15 * n
end

-- Deflect (weapon native, Buckler): while Guarding, reflect 20% of the damage Guard just
-- MITIGATED back to the attacker (DB "On Guard, reflect 20% of mitigated damage"). Keyed on the
-- mitigated amount (not damage dealt), so it fires even on a fully-absorbed hit. Returns 0
-- without the passive.
function WeaponPassiveService.GetGuardDeflectPercent(unit: any): number
	return WeaponPassiveService.GetCombatKeys(unit).Deflect and 0.20 or 0
end

-- Evasion (weapon native, Parrying Dagger): +0.15 final Evasiveness (DB "+15% final Evasiveness",
-- read as a flat additive to match the project's other evasiveness folds and the PrecisionStrike
-- +0.15 ruling). Defensive: folded into the defender's evasiveness in calcHitQuality, so it
-- lowers every incoming attack's Hit Quality (basic AND skill). Returns 0 without the passive.
function WeaponPassiveService.GetEvasivenessBonus(unit: any): number
	return WeaponPassiveService.GetCombatKeys(unit).Evasion and 0.15 or 0
end

-- SkillPotency (weapon native, Orb off-hand): +8% Skill damage dealt (DB "+8% Skill damage
-- dealt"). Returns a multiplicative factor (1.08) folded into the skill final-damage chain in
-- CombatResolver.ResolveSkill alongside the doctrine/race/trait skill-potency mods. 1 without it.
-- Pure READ -> safe in AI preview. Applies to damaging skills only (it multiplies skill damage).
function WeaponPassiveService.GetSkillDamageMultiplier(unit: any): number
	return WeaponPassiveService.GetCombatKeys(unit).SkillPotency and 1.08 or 1
end

-- ArcaneFlow (weapon native, Wand): recover MP = 5 + floor(INT/20) at the start of the wearer's
-- ready turn (DB "Recover MP = 5 + floor(INT/20) on ready turn"). Called by BattleCoordinator in
-- the OnTurnStart hook cluster (both the normal and channel-resolve turn-open paths). Grants the
-- MP in place (clamped to maxMp) and RETURNS the amount actually restored (0 when absent / full),
-- so the caller can log it. Mutates currentMp -> only called from the real turn-open, never AI preview.
-- Reap (weapon native, Scythe): heal 5% of the TOTAL damage dealt by a basic attack (DB "Heal 5%
-- of total Cleave damage dealt"). Returns 0.05 or 0. Applied by CommandService's Attack branch on
-- the summed basic-attack damage (so a multi-target cleave heals 5% of the whole spread). BASIC-
-- ATTACK ONLY (Cleave is a basic-attack weapon pattern; skills author their own AOE). Pure READ.
function WeaponPassiveService.GetReapHealFraction(unit: any): number
	return WeaponPassiveService.GetCombatKeys(unit).Reap and 0.05 or 0
end

-- Charge (weapon native, Lance): +6% damage per tile the attacker moved THIS TURN before attacking
-- (DB "+6% damage per tile moved this turn"). Returns the final-damage multiplier bonus
-- 0.06 * tilesMovedThisTurn, or 0 without Charge. BASIC-ATTACK ONLY (its own wording: scales with
-- the approach, a basic-attack concept). Reads unit._chargeTilesThisTurn (accumulated by the Move
-- commit, reset in OnTurnStart below). Pure READ.
function WeaponPassiveService.GetChargeDamageBonus(unit: any): number
	if not WeaponPassiveService.GetCombatKeys(unit).Charge then return 0 end
	return 0.06 * ((unit and unit._chargeTilesThisTurn) or 0)
end

-- Fortify (weapon native, Spear): on a landed hit, the attacker gains +20% of its Weapon Defense
-- as flat Defense (DB "On hit, gain +20% of Weapon Defense as flat Defense"). User ruling 2026-10-26
-- (Option B): STACKS per hit within the turn (a multi-hit swing adds once per hit), RESETS at the
-- wearer's next turn (via OnTurnStart). Hybrid: fires on basic attacks AND damaging skills (both
-- resolve through ApplyOutcome, where the per-hit accrual lives). Two pure-READ getters:
--   GetFortifyFlatDefensePerHit -> the flat Defense added by ONE landed hit (round(0.20 x weaponDef)).
--   GetFortifyFlatDefense       -> the accumulated total currently protecting the unit (read into the
--                                  defender's Defense in CombatResolver before CalcDefensePower).
-- (2026-10-29, DB PAS-005 "based on OWNING ITEM base Weapon Defense"; weapons row 154 "always use the
-- OWNING ITEM base stat"): the amount comes from the defense of the item that carries Fortify (main-hand
-- weapon, off-hand weapon on its own hits, shield / off-hand item, or gloves), not always the main hand.
-- One Fortify effect: the strongest carrier counts.
local function itemHasFortify(item: any): boolean
	local arch = WeaponData.GetByArchetypeId(item.baseArchetypeId)
	if arch and arch.nativePassiveId == "Fortify" then return true end
	for _, pid in ipairs(item.bonusPassiveIds or {}) do
		if PAS_ID_TO_KEY[pid] == "Fortify" then return true end
	end
	return false
end

local function fortifyItemDefense(unit: any, slot: string, item: any): number
	local arch = WeaponData.GetByArchetypeId(item.baseArchetypeId)
	if slot == "MainHand" then
		return unit.weaponDefense or 0
	elseif slot == "OffHand" and arch and arch.category == "Weapon" then
		return (unit.offWeapon and unit.offWeapon.defense) or 0
	elseif slot == "OffHand" then
		local ok, prof = pcall(function()
			return (require :: any)(script.Parent.EquipmentService).GetEffectiveWeaponProfile(item)
		end)
		return (ok and type(prof) == "table" and prof.defense) or 0
	else
		local ok, prof = pcall(function()
			local AD = (require :: any)(Content:WaitForChild("ArmorData"))
			return AD.GetScaledProfile(item.baseArchetypeId, item.itemLevel)
		end)
		return (ok and type(prof) == "table" and prof.defense) or 0
	end
end

function WeaponPassiveService.GetFortifyFlatDefensePerHit(unit: any): number
	if not WeaponPassiveService.GetCombatKeys(unit).Fortify then return 0 end
	local best = 0
	for _, slot in ipairs(COMBAT_SLOTS) do
		local item = unit.equipmentSlots and unit.equipmentSlots[slot]
		-- Same hand rule as GetCombatKeys: a hand weapon only counts on its own hand's hits.
		if item and (slot == "MainHand" or slot == "OffHand") then
			local _a = WeaponData.GetByArchetypeId(item.baseArchetypeId)
			if _a and _a.category == "Weapon" then
				local want = if unit._dwHand == "OffHand" then "OffHand" else "MainHand"
				if slot ~= want or (slot == "OffHand" and not unit.dualWieldActive) then item = nil end
			end
		end
		if item and itemHasFortify(item) then
			best = math.max(best, math.round(0.20 * fortifyItemDefense(unit, slot, item)))
		end
	end
	return best
end

function WeaponPassiveService.GetFortifyFlatDefense(unit: any): number
	return (unit and unit._fortifyFlatDefense) or 0
end

-- Start-of-turn reset for weapon-passive per-turn accumulators. Called by BattleCoordinator in the
-- OnTurnStart hook cluster (both turn-open paths), mirroring the other passive services' OnTurnStart.
-- Currently resets the Charge tiles-moved-this-turn counter. Nil-safe no-op otherwise.
function WeaponPassiveService.OnTurnStart(unit: any)
	if not unit then return end
	unit._chargeTilesThisTurn = 0
	unit._fortifyFlatDefense = 0  -- Fortify (Spear): on-hit flat Defense resets each turn (Option B)
	unit._qdBaThisTurn = 0        -- Quick Draw: Basic Attack actions committed this turn
	unit._qdUsedThisTurn = false  -- Quick Draw: once per turn
	-- Lash / Breaker (2026-11-21): the unit's own turn is open. StatusService reads this so a Lashed /
	-- Blunted landed DURING this turn (counter, reaction) still lasts through its NEXT turn; cleared by
	-- StatusService.TickStatuses at the turn end.
	unit._inOwnTurn = true
end

-- RAKE (Claws native, weapons_equipment 163; DESIGNER RULING 2026-11-21): a Basic Attack resolves
-- RAKE_HITS hits at RAKE_HIT_MULT damage each. Returns (hits, damage multiplier) -- (1, 1) without
-- Rake. Basic Attacks only; skills are not doubled. Read by the Attack commit and the basic-attack
-- prediction (CombatResolver.PredictBasicAttack), so preview / AI / commit cannot drift. Pure READ.
local RAKE_HITS, RAKE_HIT_MULT = 2, 0.55
function WeaponPassiveService.GetRakeHits(unit: any): (number, number)
	if WeaponPassiveService.GetCombatKeys(unit).Rake then return RAKE_HITS, RAKE_HIT_MULT end
	return 1, 1
end

-- REBOUND (Boomerang native, weapons_equipment 164): after a Basic Attack hit, 1 adjacent enemy takes
-- REBOUND_DAMAGE_MULT of normal damage. Returns the multiplier, or 0 without Rebound. Pure READ.
local REBOUND_DAMAGE_MULT = 0.40
function WeaponPassiveService.GetReboundDamageMult(unit: any): number
	return WeaponPassiveService.GetCombatKeys(unit).Rebound and REBOUND_DAMAGE_MULT or 0
end

-- Knockback (weapon native, Hammer/Club): on a landed basic attack, push the primary target
-- floor(Force/2) tiles away (DB "Push target floor(Force/2) tiles away on hit"). Returns true when
-- the unit carries Knockback, else false. BASIC-ATTACK ONLY (user ruling 2026-10-26: NOT on skills,
-- because 9 damaging skills already author their own displacement -- stacking would double-push or
-- contradict). The push itself (force, direction, collision) is applied by CommandService's Attack
-- branch via the shared applyKnockback helper. Pure READ.
function WeaponPassiveService.HasKnockbackOnHit(unit: any): boolean
	return WeaponPassiveService.GetCombatKeys(unit).Knockback == true
end

-- Pull (weapon native, Chains): on a landed basic attack, drag the primary target floor(Force/2)
-- tiles TOWARD the attacker (DB "Drag target floor(Force/2) tiles toward attacker"). Returns true
-- when the unit carries Pull, else false. BASIC-ATTACK ONLY (same user ruling as Knockback). The
-- drag is applied by CommandService via applyKnockback with a reversed (toward-attacker) direction
-- override. Pure READ. Mutually exclusive in practice with Knockback (a weapon has one native).
function WeaponPassiveService.HasPullOnHit(unit: any): boolean
	return WeaponPassiveService.GetCombatKeys(unit).Pull == true
end

-- HighGround (weapon native, Great Bow + rolled PAS-045): returns 0.35 or 0. User ruling 2026-10-29:
-- CombatResolver multiplies the HEIGHT BONUS by (1 + this) after the +30% cap (+13.5/+27/+40.5%),
-- only when the attacker is higher.
-- Hybrid ruling: generalizes to basic attacks AND damaging skills (a positional damage bonus).
-- Pure READ -> safe in AI preview.
function WeaponPassiveService.GetHighGroundBonus(unit: any): number
	return WeaponPassiveService.GetCombatKeys(unit).HighGround and 0.35 or 0
end

-- Attunement (weapon native, Crystal): +25% elemental damage dealt (DB "+25% elemental damage
-- dealt"). Returns 0.25 only when the unit carries Attunement AND the attack element is elemental
-- (not nil / "Physical" / ""); else 0. Hybrid ruling: generalizes to basic attacks AND damaging
-- skills. Pure READ -> safe in AI preview.
function WeaponPassiveService.GetAttunementBonus(unit: any, element: any): number
	if element == nil or element == "Physical" or element == "" then return 0 end
	return WeaponPassiveService.GetCombatKeys(unit).Attunement and 0.25 or 0
end

-- Lore (weapon native, Tome): the APPLIER gets +30% duration on every status / buff it applies
-- (DB "+30% applied status and buff duration"). Returns the duration multiplier (1.30) when the
-- applier carries Lore, else 1. Consumed by StatusService.ApplyStatus keyed on the SOURCE (applier)
-- unit, on new application only. Pure READ -> safe in AI preview.
function WeaponPassiveService.GetAppliedStatusDurationMultiplier(unit: any): number
	return WeaponPassiveService.GetCombatKeys(unit).Lore and 1.30 or 1
end

-- QuickDraw (weapon native, Quiver). DB weapons_equipment 141 (user ruling 2026-10-29: build as
-- the DB says): "Once per turn, after committing 2 Basic Attack actions in same turn, pay 10% Max
-- MP to perform 1 bonus Basic Attack at 0 AP. Bonus BA adds full Basic Attack RT. Cannot trigger
-- Quick Draw or other additional-action effects." Returns the threshold (2 Basic Attack actions)
-- when the unit carries QuickDraw, else nil. The offer / MP payment / 0-AP commit live in
-- CommandService (it owns the AP and turn-end flow). Pure READ.
function WeaponPassiveService.GetQuickDrawThreshold(unit: any): number?
	return WeaponPassiveService.GetCombatKeys(unit).QuickDraw and 2 or nil
end

-- Quick Draw MP price: 10% of Max MP, rounded, at least 1.
function WeaponPassiveService.GetQuickDrawMpCost(unit: any): number
	return math.max(1, math.round(((unit and unit.maxMp) or 0) * 0.10))
end

-- ArcaneReach (weapon native, Staff): skills that explicitly INHERIT weapon range gain +1 Max
-- Range (DB "Skills inheriting weapon range gain +1 Maximum Range"). Gated on skillDef.range == -1
-- (the "follows weapon range" marker CalcSkillRange keys on), so fixed-range skills are unaffected.
-- Returns 1 (fold into the CalcSkillRange raceModifier slot) or 0. Pure READ -> safe in AI preview.
function WeaponPassiveService.GetSkillRangeBonus(unit: any, skillDef: any): number
	if not skillDef or skillDef.range ~= -1 then return 0 end
	-- Additive (DB PAS-008 stacking): +1 per Arcane Reach source (native Staff + rolled copies).
	return WeaponPassiveService.GetCombatKeyCounts(unit).ArcaneReach or 0
end

function WeaponPassiveService.OnReadyTurn(unit: any): number
	if not unit then return 0 end
	if not WeaponPassiveService.GetCombatKeys(unit).ArcaneFlow then return 0 end
	-- DB weapons_equipment 106: "Does not trigger during channeling, stun, or sleep." (2026-10-29)
	if unit.isChanneling or unit.channelPhase ~= nil then return 0 end
	for _, inst in ipairs(unit.statusInstances or {}) do
		if inst.id == "Stun" or inst.id == "Sleep" then return 0 end
	end
	local int = (unit.effectiveStats and unit.effectiveStats.INT) or 10
	local gain = 5 + math.floor(int / 20)
	local maxMp = unit.maxMp or 0
	local before = unit.currentMp or 0
	if before >= maxMp then return 0 end
	unit.currentMp = math.min(maxMp, before + gain)
	return unit.currentMp - before
end

return WeaponPassiveService
