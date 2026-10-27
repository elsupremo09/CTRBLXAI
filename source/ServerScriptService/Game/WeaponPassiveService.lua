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

-- GuardBonus (weapon native, Shield): +15 percentage points of Guard damage mitigation while
-- the wearer is Guarding (DB "On Guard, +15% damage mitigation"). Folded into unit.guardBonus by
-- the Guard command alongside Race/Trait/Armor; the damage path reads guardBonus and clamps to
-- GUARD_CAP. Returns 0 without the passive.
function WeaponPassiveService.GetGuardMitigationBonus(unit: any): number
	return WeaponPassiveService.GetCombatKeys(unit).GuardBonus and 0.15 or 0
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
function WeaponPassiveService.GetFortifyFlatDefensePerHit(unit: any): number
	if not WeaponPassiveService.GetCombatKeys(unit).Fortify then return 0 end
	return math.round(0.20 * ((unit and unit.weaponDefense) or 0))
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

-- HighGround (weapon native, Great Bow): +35% damage when attacking from strictly higher elevation
-- than the target (DB "+35% elevation damage bonus when attacking from above"). Returns the flat
-- bonus 0.35 or 0; CombatResolver applies it only when attacker elevation > defender elevation.
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

-- QuickDraw (weapon native, Quiver): after N basic attacks the next basic attack costs 0 RT (DB
-- "After 2 Basic Attacks, next attack costs 0 RT"). Returns the threshold N (2) when the unit
-- carries QuickDraw, else nil. The per-action attack counter + the RT waiver live in
-- CommandService's Attack branch (they need the command / RT-accrual context). Pure READ.
function WeaponPassiveService.GetQuickDrawThreshold(unit: any): number?
	return WeaponPassiveService.GetCombatKeys(unit).QuickDraw and 2 or nil
end

-- ArcaneReach (weapon native, Staff): skills that explicitly INHERIT weapon range gain +1 Max
-- Range (DB "Skills inheriting weapon range gain +1 Maximum Range"). Gated on skillDef.range == -1
-- (the "follows weapon range" marker CalcSkillRange keys on), so fixed-range skills are unaffected.
-- Returns 1 (fold into the CalcSkillRange raceModifier slot) or 0. Pure READ -> safe in AI preview.
function WeaponPassiveService.GetSkillRangeBonus(unit: any, skillDef: any): number
	if not skillDef or skillDef.range ~= -1 then return 0 end
	return WeaponPassiveService.GetCombatKeys(unit).ArcaneReach and 1 or 0
end

function WeaponPassiveService.OnReadyTurn(unit: any): number
	if not unit then return 0 end
	if not WeaponPassiveService.GetCombatKeys(unit).ArcaneFlow then return 0 end
	local int = (unit.effectiveStats and unit.effectiveStats.INT) or 10
	local gain = 5 + math.floor(int / 20)
	local maxMp = unit.maxMp or 0
	local before = unit.currentMp or 0
	if before >= maxMp then return 0 end
	unit.currentMp = math.min(maxMp, before + gain)
	return unit.currentMp - before
end

return WeaponPassiveService
