-- CombatResolver.lua
-- CTRBLXAI | Slice 3 (AOE, Healing, Burn/Poison generation)
--
-- Calculates the numerical result of an attack or skill hit.
-- Returns an outcome table — does NOT write to unit state directly.
--
-- Slice 3 additions:
--   - ResolveHealing: calculates healing amount
--   - Burn status application uses actual fire damage dealt
--   - AOE outcomes return multiple results

local StatusService = require(script.Parent.StatusService)
local RacePassiveService = require(script.Parent.RacePassiveService)
local DoctrinePassiveService = require(script.Parent.DoctrinePassiveService)
local ArmorPassiveService = require(script.Parent.ArmorPassiveService)
local AugmentEffectService = require(script.Parent.AugmentEffectService)
local TraitEffectService = require(script.Parent.TraitEffectService) -- Perks & Flaws Phase 2
local BattleVisualBroadcaster = require(script.Parent.BattleVisualBroadcaster)

local RaceData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("RaceData")
)

local GameConstants = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Shared")
		:WaitForChild("GameConstants")
)

local CombatResolver = {}

-- Optional: TileEffectService injected at runtime (DI, mirrors CommandService/
-- BattleCoordinator) so hit-quality can read the defender's active tile effect
-- (e.g. Steam occupyEvasion). Wired in Main.server.lua during init.
local _tileEffectService = nil
function CombatResolver.SetTileEffectService(tes)
	_tileEffectService = tes
	-- Forward to RacePassiveService (Treant Forest Wrath reads the Vines effect).
	if RacePassiveService.SetTileEffectService then
		RacePassiveService.SetTileEffectService(tes)
	end
end

-- Weather passive element-damage modifier (Rain/Heatwave/Dark Eclipse/Holy Aurora/
-- Strong Wind). Injected to avoid a require cycle. nil-safe -> multiplier 1.0.
local _weatherService = nil
function CombatResolver.SetWeatherService(ws)
	_weatherService = ws
end
local function weatherElementMult(element)
	if _weatherService and _weatherService.GetElementDamageMultiplier then
		return _weatherService.GetElementDamageMultiplier(element)
	end
	return 1.0
end

--------------------------------------------------
-- INTERNAL FORMULA HELPERS
--------------------------------------------------

-- Known element tags. Anything in this set found in a skill's .tags array
-- is treated as the skill's element. First match wins.
local ELEMENT_SET = {
	Physical = true, Fire = true, Water = true, Ice = true,
	Poison = true, Dark = true, Holy = true, Electric = true,
}

local function extractElement(tags)
	if not tags then return "Physical" end
	for _, tag in ipairs(tags) do
		if ELEMENT_SET[tag] then return tag end
	end
	return "Physical"
end

-- Returns true if unit has the Undead race tag
local function isUndead(unit)
	if not unit.raceId then return false end
	local raceEntry = RaceData.GetRace(unit.raceId)
	if raceEntry and raceEntry.tags then
		for _, tag in ipairs(raceEntry.tags) do
			if tag == "Undead" then return true end
		end
	end
	return false
end

--------------------------------------------------
-- ELEMENT DAMAGE INTERACTIONS (Phase 3)
--
-- Modifies finalDamage based on element vs defender status.
-- Returns: modifiedDamage, removedStatuses (table of IDs)
--
-- Rules from DB (elements_statuses):
--   Fire vs Wet/Frozen    → damage ×0.50, removes Wet/Frozen
--   Physical vs Frozen    → damage ×1.50
--   Water vs Frozen       → damage ×1.50
--   Water vs Burn         → removes Burn, Water damage ×0.50
--   Holy vs Undead        → damage ×2.0
--   Dark vs Undead        → heals instead (handled separately)
--------------------------------------------------

local function applyElementInteractions(defender, element, finalDamage)
	local removed = {}

	local hasWet    = StatusService.HasStatus(defender, "Wet")
	local hasFrozen = StatusService.HasStatus(defender, "Frozen")
	local hasBurn   = StatusService.HasStatus(defender, "Burn")
	local undead    = isUndead(defender)

	if element == "Fire" then
		-- Fire vs Wet: halved, removes Wet
		if hasWet then
			finalDamage = math.max(0, math.round(finalDamage * 0.50))
			StatusService.RemoveStatus(defender, "Wet")
			table.insert(removed, "Wet")
		end
		-- Fire vs Frozen: halved, removes Frozen
		if hasFrozen then
			finalDamage = math.max(0, math.round(finalDamage * 0.50))
			StatusService.RemoveStatus(defender, "Frozen")
			table.insert(removed, "Frozen")
		end

	elseif element == "Physical" then
		-- Physical vs Frozen: ×1.50
		if hasFrozen then
			finalDamage = math.max(0, math.round(finalDamage * 1.50))
		end

	elseif element == "Water" then
		-- Water vs Frozen: ×1.50
		if hasFrozen then
			finalDamage = math.max(0, math.round(finalDamage * 1.50))
		end
		-- Water vs Burn: removes Burn, Water damage halved
		if hasBurn then
			finalDamage = math.max(0, math.round(finalDamage * 0.50))
			StatusService.RemoveStatus(defender, "Burn")
			table.insert(removed, "Burn")
		end

	elseif element == "Holy" then
		-- Holy vs Undead: ×2.0
		if undead then
			finalDamage = math.max(0, math.round(finalDamage * 2.0))
		end
	end

	-- Electric: no interactions yet (DB: "Future interactions not finalized")

	return finalDamage, removed
end

-- Element→status triggers. Applied after damage resolves.
-- Skips if the skill already applied the same status via appliesStatus.
-- Broadcasts StatusImmune if the status was blocked by immunity.
local function applyElementStatusTriggers(sourceUnitId, defender, element, actualDamage, alreadyApplied, attackerUnit)
	if actualDamage <= 0 or not defender.isAlive then return end

	local function tryApply(statusId, fireDmg)
		local applied, _, immuneReason = StatusService.ApplyStatus(defender, statusId, sourceUnitId, fireDmg)
		if not applied and immuneReason then
			BattleVisualBroadcaster.StatusImmune(defender, statusId, immuneReason)
		end
	end

	-- LICH — Arcane Corruption: override element→status mapping
	-- DB: Fire→Burn, Water→Frozen, Earth→Petrify, Dark→Poison
	if attackerUnit then
		local override = RacePassiveService.GetElementStatusOverride(attackerUnit, element)
		if override and override ~= alreadyApplied then
			local fireDmg = (element == "Fire") and actualDamage or nil
			tryApply(override, fireDmg)
			print(string.format("[CombatResolver] Lich Arcane Corruption: %s → %s", element, override))
			return   -- skip default triggers
		end
	end

	if element == "Fire" and alreadyApplied ~= "Burn" then
		tryApply("Burn", actualDamage)
	elseif element == "Water" then
		tryApply("Wet")
	elseif element == "Ice" then
		-- Ice on Wet target → convert Wet to Frozen
		if StatusService.HasStatus(defender, "Wet") then
			StatusService.RemoveStatus(defender, "Wet")
			tryApply("Frozen")
		end
	elseif element == "Poison" and alreadyApplied ~= "Poison" then
		tryApply("Poison")
	end
end

local function calcHitQuality(attackerDex, defenderAgi, attackerUnit, defenderUnit)
	local precision   = GameConstants.CalcPrecision(attackerDex)
	local evasiveness = GameConstants.CalcEvasiveness(defenderAgi)
	-- Perks & Flaws (Phase 2b): Keen Aim/Clumsy feed Precision; Light Step/Heavy-Footed feed Evasiveness.
	if attackerUnit then
		precision = precision + TraitEffectService.GetPrecisionModifier(attackerUnit)
	end
	if defenderUnit then
		evasiveness = evasiveness + TraitEffectService.GetEvasivenessModifier(defenderUnit)
	end
	-- Blind: Final Precision = Precision × 0.50 (DB: elements_statuses)
	if attackerUnit and StatusService.HasStatus(attackerUnit, "Blind") then
		precision = precision * 0.50
	end
	local hq = 1 + (precision - evasiveness)
	-- Blessed / Cursed: additive Final Hit Quality modifier on the attacker.
	-- DB (elements_statuses): Blessed +0.25, Cursed -0.25. Applied to the
	-- afflicted unit's OWN attacks, after the precision/evasiveness term so it
	-- stacks cleanly with facing/Hide (which are also added to final HQ).
	if attackerUnit then
		for _, inst in ipairs(attackerUnit.statusInstances or {}) do
			local sdef = GameConstants.STATUSES[inst.id]
			if sdef and sdef.hitQualityMod then
				hq = hq + sdef.hitQualityMod
			end
		end
	end
	-- Perks & Flaws (Phase 2b): Clean/Sloppy Fighter (melee) and Steady/Shaky Aim (ranged)
	-- add a flat +/-0.05 to Hit Quality. The getter classifies melee vs ranged by the
	-- attacker's weapon projectile type (NOT reach — Spear/Whip/Chains are melee).
	if attackerUnit then
		hq = hq + TraitEffectService.GetHitQualityModifier(attackerUnit)
	end
	-- Tile-effect defender evasion (interpretation iii, RESOLVED 2026-09-29): when the
	-- DEFENDER occupies a tile whose active effect def carries occupyEvasion (Steam =
	-- 0.25), subtract it from Final Hit Quality. Additive with the other HQ terms; no
	-- HQ clamp (the existing 0.10 damage floor governs downstream).
	if defenderUnit and _tileEffectService and _tileEffectService.GetTileEffect then
		local teff = _tileEffectService.GetTileEffect(defenderUnit.tileX, defenderUnit.tileY)
		if teff then
			local edef = GameConstants.TILE_EFFECTS[teff.id]
			if edef and edef.occupyEvasion then
				hq = hq - edef.occupyEvasion
			end
		end
	end
	return hq
end

local function calcEffectiveDefense(attackPower, defensePower)
	if attackPower <= 0 then return 0 end
	if defensePower <= 0 then return 0 end
	return (attackPower * defensePower) / (attackPower + defensePower)
end

-- Melee-hit classification for on-hit reactions (Lizardmen Spiked Hide, 2026-10-02).
-- Melee = attacker on one of the 8 adjacent tiles (Chebyshev 1), NOT AOE, and the
-- attack's reach is melee (<= 2, same threshold as TargetingService's melee
-- elevation rule). Skills: authored range (-1 = inherit weapon) and a Single
-- pattern; skill ids with no GameConstants.SKILLS def are treated as NOT melee
-- (conservative). Basic Attacks: the weapon's max range.
local function isMeleeHit(outcome, attacker, target)
	if not attacker or not target or not attacker.tileX or not target.tileX then return false end
	if outcome.isAOE then return false end
	local dist = math.max(math.abs(attacker.tileX - target.tileX), math.abs(attacker.tileY - target.tileY))
	if dist ~= 1 then return false end
	local reach
	if outcome.skillId then
		local sd = GameConstants.SKILLS and GameConstants.SKILLS[outcome.skillId]
		if not sd then return false end
		if sd.aoePattern ~= nil and sd.aoePattern ~= "Single" then return false end
		reach = (sd.range == -1) and (attacker.weaponMaxRange or 1) or (sd.range or 1)
	else
		reach = attacker.weaponMaxRange or 1
	end
	return reach <= 2
end

-- Build the conditional-trait context passed to TraitEffectService.GetDamageDealtModifier.
-- Carries battlefield facts the resolver owns. enemiesWithin2 / killCount are left nil
-- here (the resolver has no unit list); the traits that need them (Crowd Fighter,
-- Slayer) stay dormant until that plumbing is added. facingZone is "Front"/"Side"/"Back".
local function buildTraitCtx(attacker, defender, facingZone)
	local ctx = {}
	if attacker.maxHp and attacker.maxHp > 0 then
		ctx.hpFrac = (attacker.currentHp or attacker.maxHp) / attacker.maxHp
	end
	ctx.facingSideBack = (facingZone == "Side" or facingZone == "Back")
	-- Elevation difference: target elevation minus attacker elevation (positive = target higher).
	local aElev = GameConstants.GetElevation(attacker.tileX, attacker.tileY)
	local dElev = GameConstants.GetElevation(defender.tileX, defender.tileY)
	ctx.elevDiff = (dElev or 1) - (aElev or 1)
	-- Target afflicted with any debuff (kind == "Debuff" in GameConstants.STATUSES)?
	ctx.targetDebuffed = false
	if defender.statusInstances then
		for _, inst in ipairs(defender.statusInstances) do
			local def = GameConstants.STATUSES and GameConstants.STATUSES[inst.id]
			if def and def.kind == "Debuff" then
				ctx.targetDebuffed = true
				break
			end
		end
	end
	-- Kill count this battle (incremented by the on-KO hook) — feeds Slayer / Pacifist.
	ctx.killCount = attacker.killsThisBattle
	return ctx
end

--------------------------------------------------
-- PUBLIC: RESOLVE BASIC ATTACK
--------------------------------------------------

function CombatResolver.ResolveBasicAttack(attacker, defender, weaponDamage)
	assert(
		type(attacker) == "table" and type(defender) == "table",
		"ResolveBasicAttack: attacker and defender must be unit tables."
	)

	local aStats = attacker.effectiveStats
	local dStats = defender.effectiveStats

	local ap = GameConstants.CalcAttackPower(weaponDamage, aStats.STR)
	-- Defense Power = Defense x (1 + VIT / 300) (DB core_stats id 31/5); Defense =
	-- weapon + off-hand + armor Defense (core_stats id 30). Was hard-coded 0.
	local dp = GameConstants.CalcDefensePower(GameConstants.GetUnitDefense(defender), dStats.VIT)
	local effectiveDefense = calcEffectiveDefense(ap, dp)
	-- Slice 5 buff: Rune Ward raises defender's effective Defense (defenseMult).
	effectiveDefense = effectiveDefense * StatusService.GetDefenseMultiplier(defender)
	-- Phase 3: Determined / Coward -- Defense +/-30% while defender below HP threshold.
	do
		local dHpFrac = (defender.maxHp and defender.maxHp > 0)
			and ((defender.currentHp or defender.maxHp) / defender.maxHp) or nil
		effectiveDefense = effectiveDefense * TraitEffectService.GetDefenseMultiplier(defender, dHpFrac)
	end
	local hitQuality = calcHitQuality(aStats.DEX, dStats.AGI, attacker, defender)

	-- Hide: +50% hit quality when attacking from Hide
	if StatusService.HasStatus(attacker, "Hide") then
		hitQuality = hitQuality * 1.50
		print(string.format("[CombatResolver] %s attacking from Hide: HQ x1.50", attacker.name))
	end

	-- Facing precision bonus: side/back attacks boost HQ
	local facingZone = GameConstants.GetFacingZone(
		attacker.tileX, attacker.tileY,
		defender.tileX, defender.tileY,
		defender.facing
	)
	local facingBonus = GameConstants.GetFacingPrecisionBonus(facingZone)
	hitQuality = hitQuality + facingBonus

	local positionalMod = GameConstants.GetPositionalModifier(
		attacker.tileX, attacker.tileY,
		defender.tileX, defender.tileY
	)

	local rawDamage   = ap - effectiveDefense
	-- Combat Fortune: LUK difference modifies damage (step 7 in pipeline)
	local fortuneMod = GameConstants.CalcCombatFortune(aStats.LUK, dStats.LUK)

	local finalDamage = math.max(0, math.round(rawDamage * hitQuality * positionalMod * fortuneMod))

	-- Race passive modifiers (Slice 4F)
	-- Basic Attack: element=nil, isAOE=false, isPhysical=true
	local raceDealtMod = RacePassiveService.GetDamageDealtModifier(attacker, nil, false, defender)
	local raceRecvMod  = RacePassiveService.GetDamageReceivedModifier(defender, nil, false, true)
	-- Doctrine passive modifiers (Slice 4H)
	local docBADmgMod = DoctrinePassiveService.GetBasicAttackDamageModifier(attacker)
	local docDealtMod = DoctrinePassiveService.GetDamageDealtModifier(attacker, defender, nil, false, true, nil)
	local docRecvMod  = DoctrinePassiveService.GetDamageReceivedModifier(defender, attacker, nil, false)
	-- Perks & Flaws Phase 2 (TRAIT-DMG-BA): unit-trait dealt / received multipliers, folded
	-- alongside the race mods. Basic Attack = weapon element (or Physical), not AOE,
	-- physical, not a skill. Neutral 1.0 for units without Phase-2 traits.
	local baTraitElement = attacker.weaponElement or "Physical"
	-- Phase 3 conditional context (battlefield facts the resolver owns). killCount is
	-- populated (Slayer/Pacifist live); only adjacency (enemiesWithin2) stays nil, so
	-- Crowd Fighter / Claustrophobic remain dormant until unit-list plumbing lands.
	local traitCtx = buildTraitCtx(attacker, defender, facingZone)
	local traitDealtMod = TraitEffectService.GetDamageDealtModifier(attacker, baTraitElement, false, defender, false, traitCtx)
	local traitRecvMod  = TraitEffectService.GetDamageReceivedModifier(defender, baTraitElement, false, true, attacker)
	finalDamage = math.max(0, math.round(finalDamage * raceDealtMod * raceRecvMod * docBADmgMod * docDealtMod * docRecvMod * traitDealtMod * traitRecvMod))
	-- Slice 5 buff: Battle Rage (+20% physical) / Rune Ward (+10% attack) on the
	-- attacker. Basic attacks are always physical (isSpell=false).
	finalDamage = math.max(0, math.round(finalDamage * StatusService.GetDamageDealtMultiplier(attacker, false)
		* StatusService.GetDamageReceivedMultiplier(defender))) -- Hold the Line x0.85 (2026-10-07)

	-- Step 8: Guard and other final mitigation
	-- Check Guard via status instances (Guard is now a proper status)
	local hasGuard = false
	if defender.statusInstances then
		for _, inst in ipairs(defender.statusInstances) do
			if inst.id == "Guard" then hasGuard = true; break end
		end
	end
	if hasGuard then
		local mitigation = GameConstants.GUARD_MITIGATION + (defender.guardBonus or 0)
		mitigation = math.min(mitigation, GameConstants.GUARD_CAP)
		finalDamage = math.max(0, math.round(finalDamage * (1 - mitigation)))
	end

	-- Step 9: Petrify damage reduction
	-- Petrify: normal damage ×0.70, HP%-based damage ×0.25
	if StatusService.HasStatus(defender, "Petrify") then
		finalDamage = math.max(0, math.round(finalDamage * 0.70))
		print(string.format(
			"[CombatResolver] Petrify reduces damage to %d (×0.70)", finalDamage
		))
	end

	-- Step 10: Element interactions (Phase 3)
	-- Basic Attack element = weapon element or Physical
	local attackElement = attacker.weaponElement or "Physical"

	-- Step 6b: Terrain occupy bonus — attacker's tile element bonus
	-- Flight bypasses terrain bonuses
	if not StatusService.HasStatus(attacker, "Flight") then
		local terrainBonus = GameConstants.GetTerrainOccupyBonus(
			GameConstants.GetTerrainId(attacker.tileX, attacker.tileY),
			attackElement
		)
		if terrainBonus ~= 1 then
			print(string.format("[CombatResolver] Terrain occupy bonus: %s ×%.2f",
				GameConstants.GetTerrainId(attacker.tileX, attacker.tileY), terrainBonus))
			finalDamage = math.max(0, math.round(finalDamage * terrainBonus))
		end
	end

	-- Dark vs Undead: convert damage to healing
	if attackElement == "Dark" and isUndead(defender) then
		return {
			type         = "Healing",
			targetId     = defender.id,
			finalHealing = finalDamage,
			sourceUnitId = attacker.id,
			element      = attackElement,
		}
	end

	finalDamage = applyElementInteractions(defender, attackElement, finalDamage)
	-- Weather passive element modifier (Rain Fire-25%/Water+25%, Heatwave, etc.).
	finalDamage = math.max(0, math.round(finalDamage * weatherElementMult(attackElement)))

	return {
		type           = "Damage",
		targetId       = defender.id,
		attackPower    = ap,
		defensePower   = dp,
		rawDamage      = rawDamage,
		hitQuality     = hitQuality,
		positionalMod  = positionalMod,
		facingZone     = facingZone,
		finalDamage    = finalDamage,
		appliesStatus  = RacePassiveService.GetBasicAttackStatus(attacker, defender),
		element        = attackElement,
		sourceUnitId   = attacker.id,
	}
end

--------------------------------------------------
-- PUBLIC: RESOLVE SKILL (damage skill, single target)
--------------------------------------------------

-- SHARED PRE-DEFENSE POWER (used by ResolveSkill/ResolveHealing AND the unit
-- inspector's raw-damage display, so the shown number can never drift from
-- real combat). Skill power = weapon attack power x skill power multiplier.
function CombatResolver.EstimateSkillPower(attacker, skillDef)
	local aStats = attacker.effectiveStats or {}
	local weaponDamage = attacker.weaponDamage or 10
	local sp = weaponDamage * (skillDef.power or 1.0)
	if skillDef.inheritStr then
		sp = GameConstants.CalcAttackPower(sp, aStats.STR)
	end
	-- SKL-LUCKY-STRIKE signature recipe (DB skills powerFormula): its damage scales
	-- with the caster's LUK on top of the Weapon Attack Power base, and also folds in
	-- the Skill Potency Multiplier (the plain skill path has no potency term, so it
	-- is applied here only for Lucky Strike). Combat Fortune still applies downstream
	-- in ResolveSkill, unchanged (per the skill's authored notes).
	--   LUK Power Bonus = 0.75 x LUK / (100 + LUK)
	--   Power = Weapon Attack Power x (1 + LUK Power Bonus) x Skill Potency Multiplier
	if skillDef.id == "SKL-LUCKY-STRIKE" then
		local luk = aStats.LUK or 10
		local int = aStats.INT or 10
		local lukPowerBonus = 0.75 * luk / (100 + luk)
		sp = sp * (1 + lukPowerBonus) * GameConstants.CalcSkillPotency(int)
	end
	-- DOC-SPELLBLADE-01 "Arcane Strike" signature recipe (DB/SkillData powerFormula):
	-- Power = Weapon Attack Power x 1.00 x Skill Potency Multiplier, PLUS a flat
	-- INT/2 bonus to Skill Power applied BEFORE Defense. The generic skill-power
	-- path has no potency term and no INT flat term, so BOTH are applied here,
	-- keyed to this id only (no other skill's damage changes). Combat Fortune and
	-- Defense still apply downstream in ResolveSkill, unchanged. This branch sits
	-- alongside the SKL-LUCKY-STRIKE branch above and does not alter it.
	if skillDef.id == "DOC-SPELLBLADE-01" then
		local int = aStats.INT or 10
		sp = sp * GameConstants.CalcSkillPotency(int) + int / 2
	end
	return sp
end

-- Pre-target heal power (before the target's VIT heal efficiency).
function CombatResolver.EstimateHealPower(caster, skillDef)
	local int = (caster.effectiveStats and caster.effectiveStats.INT) or 10
	if skillDef and skillDef.isMenderHeal then
		-- Authored Mender heal: (10 + 0.20L + 0.40 x Mender INT) x Skill Potency
		local L = caster.level or 1
		return (10 + 0.20 * L + 0.40 * int) * GameConstants.CalcSkillPotency(int)
	end
	local weaponDamage = caster.weaponDamage or 10
	-- Skill Potency Multiplier = 1 + INT / (200 + INT)
	local skillPotency = GameConstants.CalcSkillPotency(int)
	-- Celestial Radiant Grace / Demon Infernal Pact (2026-10-02): the INT
	-- contribution of a Holy / Dark tagged SKILL is boosted 20% -> 1 + 1.20p.
	-- skillDef is optional (skill-agnostic callers, e.g. the inspector, pass none).
	if skillDef then
		skillPotency = skillPotency * RacePassiveService.GetSkillPotencyMultiplier(caster, skillDef.tags, int)
	end
	local baseHeal = 10 + 0.35 * int + weaponDamage * 0.30
	return baseHeal * skillPotency
end

function CombatResolver.ResolveSkill(attacker, defender, skillDef)
	assert(
		type(attacker) == "table" and type(defender) == "table",
		"ResolveSkill: attacker and defender must be unit tables."
	)

	local aStats = attacker.effectiveStats
	local dStats = defender.effectiveStats

	-- Skill Power = Weapon Attack Power × power multiplier (shared helper)
	local sp = CombatResolver.EstimateSkillPower(attacker, skillDef)

	-- Defense Power from real equipment Defense (core_stats id 30/31). Was hard-coded 0.
	local dp = GameConstants.CalcDefensePower(GameConstants.GetUnitDefense(defender), dStats.VIT)
	local effectiveDefense = calcEffectiveDefense(sp, dp)
	-- Slice 5 buff: Rune Ward raises defender's effective Defense (defenseMult).
	effectiveDefense = effectiveDefense * StatusService.GetDefenseMultiplier(defender)
	-- Phase 3: Determined / Coward -- Defense +/-30% while defender below HP threshold.
	do
		local dHpFrac = (defender.maxHp and defender.maxHp > 0)
			and ((defender.currentHp or defender.maxHp) / defender.maxHp) or nil
		effectiveDefense = effectiveDefense * TraitEffectService.GetDefenseMultiplier(defender, dHpFrac)
	end
	local hitQuality = calcHitQuality(aStats.DEX, dStats.AGI, attacker, defender)

	-- Hide: +50% hit quality when attacking from Hide
	if StatusService.HasStatus(attacker, "Hide") then
		hitQuality = hitQuality * 1.50
		print(string.format("[CombatResolver] %s attacking from Hide: HQ x1.50", attacker.name))
	end

	-- Facing precision bonus: side/back attacks boost HQ
	local facingZone = GameConstants.GetFacingZone(
		attacker.tileX, attacker.tileY,
		defender.tileX, defender.tileY,
		defender.facing
	)
	local facingBonus = GameConstants.GetFacingPrecisionBonus(facingZone)
	hitQuality = hitQuality + facingBonus

	local positionalMod = GameConstants.GetPositionalModifier(
		attacker.tileX, attacker.tileY,
		defender.tileX, defender.tileY
	)

	local rawDamage   = sp - effectiveDefense
	-- Combat Fortune: LUK difference modifies damage (step 7 in pipeline)
	local fortuneMod = GameConstants.CalcCombatFortune(aStats.LUK, dStats.LUK)

	local finalDamage = math.max(0, math.round(rawDamage * hitQuality * positionalMod * fortuneMod))

	-- Race passive modifiers (Slice 4F)
	-- Extract element from skill tags (Phase 3)
	local skillElement = extractElement(skillDef.tags)
	local skillIsAOE = skillDef.aoePattern ~= nil and skillDef.aoePattern ~= "Single"
	local skillIsPhysical = (skillElement == nil or skillElement == "Physical" or skillElement == "")
	local raceDealtMod = RacePassiveService.GetDamageDealtModifier(attacker, skillElement, skillIsAOE, defender)
	local raceRecvMod  = RacePassiveService.GetDamageReceivedModifier(defender, skillElement, skillIsAOE, skillIsPhysical)
	-- Doctrine passive modifiers (Slice 4H)
	local docSkillPotency = DoctrinePassiveService.GetSkillPotencyModifier(attacker)
	-- Race Skill Potency (INT contribution) boost -- Celestial Holy / Demon Dark
	-- SKILLS only (2026-10-02). NOTE: the skill DAMAGE formula has no INT Skill
	-- Potency term today, so the boost is applied at this skill-potency slot as the
	-- ratio (1 + 1.20p) / (1 + p) -- see RacePassiveService.GetSkillPotencyMultiplier.
	local raceSkillPotency = RacePassiveService.GetSkillPotencyMultiplier(attacker, skillDef.tags, aStats and aStats.INT)
	local docDealtMod = DoctrinePassiveService.GetDamageDealtModifier(attacker, defender, skillElement, true, false, nil)
	local docRecvMod  = DoctrinePassiveService.GetDamageReceivedModifier(defender, attacker, skillElement, true)
	-- Perks & Flaws Phase 2 (TRAIT-DMG-SKILL): unit-trait dealt / received multipliers,
	-- element / AOE / skill aware, folded alongside the race mods. Neutral 1.0 for no traits.
	-- Phase 3 conditional context also applies to skills (Adrenaline/Backstabber/elevation/etc.).
	local skillTraitCtx = buildTraitCtx(attacker, defender, facingZone)
	local traitDealtMod = TraitEffectService.GetDamageDealtModifier(attacker, skillElement, skillIsAOE, defender, true, skillTraitCtx)
	local traitRecvMod  = TraitEffectService.GetDamageReceivedModifier(defender, skillElement, skillIsAOE, skillIsPhysical, attacker)
	-- Perks & Flaws (Phase 2b): Arcane Prodigy skill-potency +/-12%. Additive potency %
	-- (per DB id 33 same-category additive); applied as a (1 + pct) multiplier on the
	-- skill-potency slot, consistent with race/doctrine potency folds above.
	local traitSkillPotency = 1 + TraitEffectService.GetSkillPotencyModifier(attacker)
	finalDamage = math.max(0, math.round(finalDamage * raceDealtMod * raceRecvMod * docSkillPotency * raceSkillPotency * traitSkillPotency * docDealtMod * docRecvMod * traitDealtMod * traitRecvMod))
	-- Slice 5 buff: Spell Focus (+20% spell) / Battle Rage (+20% physical) /
	-- Rune Ward (+10% attack) on the caster. skillIsPhysical selects which.
	finalDamage = math.max(0, math.round(finalDamage * StatusService.GetDamageDealtMultiplier(attacker, not skillIsPhysical)
		* StatusService.GetDamageReceivedMultiplier(defender) -- Hold the Line x0.85 (2026-10-07)
		* (skillDef.potencyBonusMult or 1))) -- Mana Surge +10% potency, snapshotted at commit

	-- Step 8: Guard and other final mitigation
	local hasGuardSkill = false
	if defender.statusInstances then
		for _, inst in ipairs(defender.statusInstances) do
			if inst.id == "Guard" then hasGuardSkill = true; break end
		end
	end
	if hasGuardSkill then
		local mitigation = GameConstants.GUARD_MITIGATION + (defender.guardBonus or 0)
		mitigation = math.min(mitigation, GameConstants.GUARD_CAP)
		finalDamage = math.max(0, math.round(finalDamage * (1 - mitigation)))
	end

	-- Step 9: Petrify damage reduction
	if StatusService.HasStatus(defender, "Petrify") then
		finalDamage = math.max(0, math.round(finalDamage * 0.70))
		print(string.format(
			"[CombatResolver] Petrify reduces skill damage to %d (×0.70)", finalDamage
		))
	end

	-- Step 10: Element interactions (Phase 3)

	-- Step 6b: Terrain occupy bonus — attacker's tile element bonus
	-- Flight bypasses terrain bonuses
	if not StatusService.HasStatus(attacker, "Flight") then
		local terrainBonusSkill = GameConstants.GetTerrainOccupyBonus(
			GameConstants.GetTerrainId(attacker.tileX, attacker.tileY),
			skillElement or "Physical"
		)
		if terrainBonusSkill ~= 1 then
			print(string.format("[CombatResolver] Terrain occupy bonus (skill): %s ×%.2f",
				GameConstants.GetTerrainId(attacker.tileX, attacker.tileY), terrainBonusSkill))
			finalDamage = math.max(0, math.round(finalDamage * terrainBonusSkill))
		end
	end

	-- Dark vs Undead: convert damage to healing
	if skillElement == "Dark" and isUndead(defender) then
		return {
			type         = "Healing",
			targetId     = defender.id,
			finalHealing = finalDamage,
			sourceUnitId = attacker.id,
			element      = skillElement,
		}
	end

	finalDamage = applyElementInteractions(defender, skillElement, finalDamage)
	-- Weather passive element modifier (Rain Fire-25%/Water+25%, Heatwave, etc.).
	finalDamage = math.max(0, math.round(finalDamage * weatherElementMult(skillElement)))

	-- Pure-debuff detection: a skill whose intent is the status itself, not
	-- damage (power 0/nil and no STR inheritance). Its authored status must
	-- land even though it deals no damage — the actual>0 gate in ApplyOutcome
	-- is meant only to suppress rider statuses on fully-mitigated DAMAGING hits.
	-- (See ApplyOutcome. Damaging skills leave this false and stay gated.)
	local isPureStatusSkill = (skillDef.appliesStatus ~= nil or skillDef.appliesStatuses ~= nil)
		and (not skillDef.inheritStr) and ((skillDef.power or 0) == 0)

	return {
		type           = "Damage",
		targetId       = defender.id,
		skillId        = skillDef.id or nil,
		attackPower    = sp,
		defensePower   = dp,
		rawDamage      = rawDamage,
		hitQuality     = hitQuality,
		positionalMod  = positionalMod,
		facingZone     = facingZone,
		finalDamage    = finalDamage,
		appliesStatus  = skillDef.appliesStatus or nil,
		appliesStatuses = skillDef.appliesStatuses or nil,
		applyStatusUnconditional = isPureStatusSkill,
		statusDurationCt = skillDef.statusDurationCt or nil, -- skill-authored CT duration (2026-10-07)
		element        = skillElement,
		sourceUnitId   = attacker.id,
	}
end

--------------------------------------------------
-- PUBLIC: RESOLVE HEALING (Slice 3)
--
-- Healing Light formula (simplified for L=1):
--   HealAmount = round((10 + 0.35×INT + WeaponDamage×0.30) × SkillPotency)
--   SkillPotency = 1 + INT / (200 + INT)
--------------------------------------------------

function CombatResolver.ResolveHealing(caster, target, skillDef)
	assert(
		type(caster) == "table" and type(target) == "table",
		"ResolveHealing: caster and target must be unit tables."
	)

	-- Pre-target heal power: (10 + 0.35*INT + weaponDmg*0.30) x skill potency (shared helper)
	local healPower = CombatResolver.EstimateHealPower(caster, skillDef)

	-- Healing Efficiency: target's VIT increases received healing
	local targetVit = target.effectiveStats and target.effectiveStats.VIT or 10
	local healEfficiency = GameConstants.CalcHealEfficiency(targetVit)
	local finalHeal = math.max(1, math.round(healPower * healEfficiency
		* (skillDef.potencyBonusMult or 1))) -- Mana Surge +10% potency (2026-10-07)

	-- Phase 3: Undead healing reversal
	-- Non-Dark healing vs Undead → converted to damage
	local healElement = extractElement(skillDef.tags)
	if isUndead(target) and healElement ~= "Dark" then
		print(string.format(
			"[CombatResolver] Undead healing reversal: %s receives %d damage instead of healing",
			target.name, finalHeal
		))
		return {
			type         = "Damage",
			targetId     = target.id,
			finalDamage  = finalHeal,
			attackPower  = 0,
			defensePower = 0,
			rawDamage    = finalHeal,
			hitQuality   = 1.0,
			positionalMod = 1.0,
			appliesStatus = nil,
			element      = healElement,
			sourceUnitId = caster.id,
		}
	end

	-- Perks & Flaws Phase 2 (TRAIT-HEAL): Blessed Recovery / Cursed Wounds -- skill healing
	-- RECEIVED by the target x(1 +/- 25%/35%). Applied only to real healing (after the
	-- Undead reversal branch above). Neutral path leaves finalHeal untouched.
	local healRecvMod = TraitEffectService.GetHealingReceivedModifier(target)
	if healRecvMod ~= 1 then
		finalHeal = math.max(1, math.round(finalHeal * healRecvMod))
	end

	return {
		type         = "Healing",
		targetId     = target.id,
		finalHealing = finalHeal,
		sourceUnitId = caster.id,
	}
end

--------------------------------------------------
-- PUBLIC: RESOLVE SHIELD  (shield subsystem — 2026-10-05)
--
-- The six Shield skills (GameConstants isShield = true) GRANT an absorption
-- pool; they deal NO attack damage. Shield amount is read from each skill's
-- AUTHORED recipe (CTRBLXAI.db / SkillData powerFormula), keyed by skill id —
-- mirroring the SKL-LUCKY-STRIKE / DOC-SPELLBLADE-01 signature branches in
-- EstimateSkillPower (those are untouched). L = Effective Skill Level (caster
-- main-hand item level). The grant is applied via StatusService.ApplyShield
-- (the EXISTING shield API that the decay / Retribution hooks already maintain)
-- in ApplyShieldOutcome — ResolveShield only computes the authored amount.
--
--   SKL-ARCANE-BARRIER      (12 + 0.25L + max(0,WeaponDef) x 1.50 + 0.25INT) x SkillPotency
--   SKL-VITAL-BARRIER       (10 + 0.20L + 0.75VIT + max(0,WeaponDef) x 0.50) x SkillPotency
--   SKL-WEAPON-WARD         (WeaponAttackPower x 0.30 + max(0,WeaponDef) x 2 + 0.15L) x SkillPotency
--   SKL-BASTION-PROJECTION  (max(0,WeaponDef) x 2 + 0.60VIT + 0.10L) x SkillPotency
--   SKL-BULWARK-FIELD       round(8 + 0.15L + max(0,WeaponDef) x 1.00 + 0.30VIT)   [per ally, no potency term]
--   SKL-RETRIBUTION-SHELL   round(10 + 0.20L + max(0,WeaponDef) x 1.50)            [no potency term]
--                           on break: Physical = round(Shield Max HP x 0.50) to the breaker
--------------------------------------------------

-- Authored per-skill shield durations (CT). nil = no explicit duration (the shield
-- simply decays via StatusService 10%/300 CT until gone). From SkillData.
local SHIELD_DURATION_CT = {
	["SKL-BULWARK-FIELD"]     = 1500,
	["SKL-RETRIBUTION-SHELL"] = 2000,
}

-- Retribution Shell on-break retaliation fraction of the shield's MAX HP (DB /
-- SkillData: "deal Physical damage = round(Shield Max HP x 0.50) to the breaker").
local RETRIBUTION_BREAK_FRACTION = 0.50

-- Compute the authored shield HP for a caster + shield skill. L defaults to 1.
-- Pre-potency math follows each skill's recipe exactly; the Skill Potency
-- Multiplier (1 + INT/(200+INT)) is applied only to the skills whose recipe
-- includes it (Arcane/Vital/Weapon/Bastion). Bulwark and Retribution are flat.
function CombatResolver.EstimateShield(caster, skillDef, skillLevel)
	local s = caster.effectiveStats or {}
	local vit = s.VIT or 10
	local int = s.INT or 10
	local L = skillLevel or 1
	local weaponDefense = math.max(0, caster.weaponDefense or 0)
	local weaponAttackPower = GameConstants.CalcAttackPower(caster.weaponDamage or 10, s.STR or 10)
	local potency = GameConstants.CalcSkillPotency(int) * (skillDef.potencyBonusMult or 1) -- Mana Surge
	local id = skillDef.id

	local amount
	if id == "SKL-ARCANE-BARRIER" then
		amount = (12 + 0.25 * L + weaponDefense * 1.50 + 0.25 * int) * potency
	elseif id == "SKL-VITAL-BARRIER" then
		amount = (10 + 0.20 * L + 0.75 * vit + weaponDefense * 0.50) * potency
	elseif id == "SKL-WEAPON-WARD" then
		amount = (weaponAttackPower * 0.30 + weaponDefense * 2 + 0.15 * L) * potency
	elseif id == "SKL-BASTION-PROJECTION" then
		amount = (weaponDefense * 2 + 0.60 * vit + 0.10 * L) * potency
	elseif id == "SKL-BULWARK-FIELD" then
		amount = 8 + 0.15 * L + weaponDefense * 1.00 + 0.30 * vit
	elseif id == "SKL-RETRIBUTION-SHELL" then
		amount = 10 + 0.20 * L + weaponDefense * 1.50
	else
		-- Unknown shield id: no authored recipe — grant nothing rather than guess.
		warn("[CombatResolver] EstimateShield: no authored recipe for " .. tostring(id))
		return 0
	end
	return math.max(0, math.round(amount))
end

-- Build a Shield OUTCOME table (no state change). ResolveShield mirrors
-- ResolveHealing's shape so the command layer can treat it uniformly.
-- durationCt / retributionDamage are authored per skill (nil for the plain five).
function CombatResolver.ResolveShield(caster, target, skillDef, skillLevel)
	assert(
		type(caster) == "table" and type(target) == "table",
		"ResolveShield: caster and target must be unit tables."
	)
	local shieldHp = CombatResolver.EstimateShield(caster, skillDef, skillLevel)
	local durationCt = SHIELD_DURATION_CT[skillDef.id]  -- nil = decay-only
	local retributionDamage = nil
	if skillDef.id == "SKL-RETRIBUTION-SHELL" then
		-- Snapshot at cast time, based on the shield's MAX HP (SkillData special rule).
		retributionDamage = math.round(shieldHp * RETRIBUTION_BREAK_FRACTION)
	end
	return {
		type              = "Shield",
		targetId          = target.id,
		shieldHp          = shieldHp,
		durationCt        = durationCt,
		retributionDamage = retributionDamage,
		sourceUnitId      = caster.id,
		skillId           = skillDef.id,
	}
end

-- Apply a Shield outcome to the target via the EXISTING StatusService shield API
-- (StatusService.ApplyShield — the one the decay / Retribution handling already
-- maintains). Adds to unit.shield_total through that API; deals NO damage. Nil-safe
-- if StatusService isn't wired. Returns the granted shield HP (0 if none).
function CombatResolver.ApplyShieldOutcome(outcome, target)
	assert(outcome.type == "Shield", "ApplyShieldOutcome: outcome must be a Shield.")
	if (outcome.shieldHp or 0) <= 0 then return 0 end
	local granted = StatusService.ApplyShield(
		target,
		outcome.shieldHp,
		outcome.durationCt,
		outcome.sourceUnitId,
		outcome.retributionDamage
	)
	print(string.format(
		"[CombatResolver] %s SHIELD +%d HP%s%s | pool %d",
		target.name, outcome.shieldHp,
		outcome.durationCt and (" | dur " .. tostring(outcome.durationCt) .. " CT") or " | decay-only",
		outcome.retributionDamage and (" | retrib " .. tostring(outcome.retributionDamage)) or "",
		target.shield_total or 0
	))
	return (granted ~= false) and outcome.shieldHp or 0
end

--------------------------------------------------
-- PUBLIC: APPLY OUTCOME (damage or healing)
-- attacker (optional): unit table of the source, used for Confuse backlash.
-- Callers that have the attacker unit should pass it.
--------------------------------------------------

function CombatResolver.ApplyOutcome(outcome, target, attacker)
	if outcome.type == "Healing" then
		local actual = UnitSchema_ApplyHealing(outcome.finalHealing, target)
		print(string.format(
			"[CombatResolver] %s healed for %d | HP: %d/%d",
			target.name, actual, target.currentHp, target.maxHp
		))
		return actual, nil
	end

	-- Damage outcome
	assert(outcome.type == "Damage", "ApplyOutcome: unsupported outcome type.")

	local actual, shieldBroke, _shieldAbsorbed, _shieldMaxAtBreak, retributionDamage =
		UnitSchema_ApplyDamage(outcome.finalDamage, target)

	-- RETRIBUTION SHELL on-break (shield subsystem — 2026-10-05). The hit that
	-- EMPTIES a Retribution Shell retaliates against the breaker. retributionDamage
	-- is the snapshot the shield carried (round(Shield Max HP x 0.50), stamped at
	-- cast by StatusService.ApplyShield and returned here through ApplyDamage ->
	-- OnShieldAbsorb). This CONNECTS the authored skill to the EXISTING on-break
	-- hooks (StatusService owns the instance + the snapshot; ApplyOutcome, which
	-- knows the attacker, deals the retaliation). Applied with UnitSchema_ApplyDamage
	-- DIRECTLY (never through ApplyOutcome) so it cannot re-trigger reflects /
	-- lifesteal / counters / another shield break — TRG-010 pattern, like Lizardmen
	-- Spiked Hide above. attacker here is the breaker (the unit that just hit the
	-- shield holder). Only fires on a genuine break with a retribution snapshot and a
	-- living attacker that is not the shield holder itself.
	-- NOTE (flagged for Simulator/Designer): the snapshot is dealt as-is. SkillData
	-- notes "attacker can reduce retribution with their own defense" — if a defense
	-- pass is wanted on the retaliation, that is a balance refinement, not part of
	-- the grant wiring. shield_total on the breaker still soaks it first (gate in
	-- UnitSchema.ApplyDamage), which is correct.
	if shieldBroke and retributionDamage and retributionDamage > 0
		and attacker and attacker.isAlive and attacker ~= target then
		local retDealt = UnitSchema_ApplyDamage(retributionDamage, attacker)
		print(string.format(
			"[CombatResolver] Retribution Shell: %s shield broke -> %d Physical to %s | HP: %d/%d%s",
			target.name, retDealt, attacker.name, attacker.currentHp, attacker.maxHp,
			attacker.isAlive and "" or " | DEFEATED"
		))
		if not attacker.isAlive then
			-- Shield caster gets the kill credit (SkillData killCredit rule).
			attacker._killedBy = outcome.retributionCasterId or target._shieldCasterId or attacker._killedBy
			RacePassiveService.OnUnitKO(attacker)
			if BattleVisualBroadcaster.UnitStateChanged then
				BattleVisualBroadcaster.UnitStateChanged(attacker)
			end
		end
	end

	-- Track who dealt the killing blow (for unit records)
	if not target.isAlive and attacker then
		target._killedBy = attacker.id
	end

	-- Phase 2: Check for damage-triggered status removal (e.g. Sleep)
	StatusService.OnDamageReceived(target, actual)

	local statusApplied = nil
	-- Pure-debuff skills (applyStatusUnconditional) land their status with no
	-- damage; damaging attacks still require actual>0 so a fully-mitigated hit
	-- does not apply its rider status.
	if outcome.appliesStatus and (actual > 0 or outcome.applyStatusUnconditional) and target.isAlive then
		-- For Burn, pass the actual fire damage dealt
		local fireDmg = nil
		if outcome.appliesStatus == "Burn" then
			fireDmg = actual
		end
		local applied, _, immuneReason = StatusService.ApplyStatus(
			target,
			outcome.appliesStatus,
			outcome.sourceUnitId or "unknown",
			fireDmg,
			outcome.statusDurationCt
		)
		if applied then
			statusApplied = outcome.appliesStatus
		elseif not applied and immuneReason then
			BattleVisualBroadcaster.StatusImmune(target, outcome.appliesStatus, immuneReason)
		end
	end

	-- Multi-status skills: apply each status in outcome.appliesStatuses (e.g. Wither
	-- lands Weakened + Cursed on the enemy damage path). Same gate as the singular
	-- appliesStatus above so a fully-mitigated damaging hit does not apply riders,
	-- while pure-status skills (applyStatusUnconditional) always land. Burn is not
	-- routed here (it uses the singular appliesStatus + fireDmg path).
	if outcome.appliesStatuses and (actual > 0 or outcome.applyStatusUnconditional) and target.isAlive then
		for _, sid in ipairs(outcome.appliesStatuses) do
			local applied, _, immuneReason = StatusService.ApplyStatus(
				target, sid, outcome.sourceUnitId or "unknown", nil, outcome.statusDurationCt
			)
			if applied then
				statusApplied = statusApplied or sid
			elseif not applied and immuneReason then
				BattleVisualBroadcaster.StatusImmune(target, sid, immuneReason)
			end
		end
	end

	-- Phase 3: Element→status triggers (Fire→Burn, Water→Wet, Ice→Frozen, Poison→Poison)
	-- Only fires if actual damage > 0 and target alive.
	-- Skips if the same status was already applied by appliesStatus above.
	if outcome.element and actual > 0 and target.isAlive then
		applyElementStatusTriggers(outcome.sourceUnitId or "unknown", target, outcome.element, actual, statusApplied, attacker)
	end

	-- Confuse backlash: when a confused unit deals damage, it takes
	-- backlash = round(finalDamage × 0.30 × debuffResist)
	-- DB: "backlash = round(Final Enemy HP Damage × 0.30 × Debuff Resistance)"
	if attacker and actual > 0 and StatusService.HasStatus(attacker, "Confuse") then
		local debuffResist = StatusService.GetDebuffResist(attacker) -- incl. Debuff Res Down (2026-10-07)
		local backlash = math.max(0, math.round(actual * 0.30 * debuffResist))
		if backlash > 0 and attacker.isAlive then
			UnitSchema_ApplyDamage(backlash, attacker)
			print(string.format(
				"[CombatResolver] Confuse backlash: %s takes %d self-damage", attacker.name, backlash
			))
		end
	end

	-- Vampire lifesteal: heal attacker for % of damage dealt
	-- TRG-010: Uses UnitSchema_ApplyHealing directly (not ApplyOutcome),
	-- so it cannot recursively trigger lifesteal or other generated effects.
	if attacker and actual > 0 and attacker.isAlive then
		local isAOE = outcome.isAOE or false
		local lifesteal = RacePassiveService.GetLifestealAmount(attacker, actual, isAOE)
		if lifesteal > 0 then
			UnitSchema_ApplyHealing(lifesteal, attacker)
			print(string.format(
				"[CombatResolver] Vampire lifesteal: %s heals %d (%.0f%% of %d)",
				attacker.name, lifesteal, isAOE and 5 or 15, actual
			))
		end
	end

	-- Doctrine lifesteal: Reaper Soul Rend (Slice 4H)
	if attacker and actual > 0 and attacker.isAlive then
		local docLifesteal = DoctrinePassiveService.GetLifestealAmount(attacker, actual, outcome.isAOE or false)
		if docLifesteal > 0 then
			UnitSchema_ApplyHealing(docLifesteal, attacker)
			print(string.format(
				"[CombatResolver] Doctrine lifesteal: %s heals %d", attacker.name, docLifesteal
			))
		end
	end

	-- Phase 3: Trait Lifesteal (perk) / Lifeless recoil (flaw) on direct damage dealt.
	-- TRG-010: heal/recoil applied directly (not via ApplyOutcome) so they cannot
	-- recursively re-trigger. Lifeless recoil is NON-LETHAL (never below 1 HP).
	if attacker and actual > 0 and attacker.isAlive then
		local traitHeal = TraitEffectService.GetLifestealAmount(attacker, actual)
		if traitHeal > 0 then
			UnitSchema_ApplyHealing(traitHeal, attacker)
			print(string.format("[CombatResolver] Trait lifesteal: %s heals %d (of %d)", attacker.name, traitHeal, actual))
		end
		local recoil = TraitEffectService.GetRecoilAmount(attacker, actual)
		if recoil > 0 and attacker.currentHp and attacker.currentHp > 1 then
			local applied = math.min(recoil, attacker.currentHp - 1) -- non-lethal clamp
			attacker.currentHp = attacker.currentHp - applied
			print(string.format("[CombatResolver] Lifeless recoil: %s takes %d (non-lethal, of %d)", attacker.name, applied, actual))
		end
	end

	-- Phase 3: Trait on-KO-of-enemy effects (killer side). Fires when this attack kills
	-- the target. Increments the killer's per-battle kill count (feeds Slayer/Pacifist),
	-- then applies HP/MP recovery or MP loss. Momentum's +1 AP gain is NOT applied here —
	-- it sets a per-turn flag (pendingKoApGain) that CommandService STEP 9 consumes
	-- before its zero-AP end-turn check, so a kill with the last AP keeps the turn open.
	if attacker and target and not target.isAlive and attacker.isAlive and attacker.side ~= target.side then
		attacker.killsThisBattle = (attacker.killsThisBattle or 0) + 1
		-- Phase 3 Cleanse (TRAIT-P-132): on enemy KO, remove 1 random active debuff from self.
		if TraitEffectService.HasCleanseOnKill(attacker) then
			StatusService.RemoveRandomDebuff(attacker)
		end
		local ko = TraitEffectService.GetOnKillEffects(attacker)
		-- DB cap: Bloodbath / Soul Charge recovery from multiple kills in one action caps
		-- at 45% of max HP / MP. Track the fraction already granted this turn and clamp
		-- each kill's contribution so the running total never exceeds 0.45. (Soul Harvest
		-- P-177 has no cap clause in the DB; it shares these fields and is treated under
		-- the same aggregate cap -- flagged for designer if it should be exempt.)
		local KO_RECOVERY_CAP = 0.45
		-- Cap tracked in ACTUAL HP/MP (not fractions) so per-kill rounding can't push the
		-- turn total past round(max * 0.45). koHpThisTurn / koMpThisTurn accumulate granted
		-- amounts; reset at turn start in BattleCoordinator.
		if ko.healFrac > 0 and attacker.maxHp then
			local capHp = math.round(attacker.maxHp * KO_RECOVERY_CAP)
			local used = attacker.koHpThisTurn or 0
			local grant = math.min(math.round(attacker.maxHp * ko.healFrac), capHp - used)
			if grant > 0 then
				UnitSchema_ApplyHealing(grant, attacker)
				attacker.koHpThisTurn = used + grant
			end
		end
		if ko.mpFrac > 0 and attacker.maxMp then
			local capMp = math.round(attacker.maxMp * KO_RECOVERY_CAP)
			local used = attacker.koMpThisTurn or 0
			local grant = math.min(math.round(attacker.maxMp * ko.mpFrac), capMp - used)
			if grant > 0 then
				attacker.currentMp = math.min(attacker.maxMp, (attacker.currentMp or 0) + grant)
				attacker.koMpThisTurn = used + grant
			end
		end
		if ko.mpLossFrac > 0 and attacker.currentMp then
			attacker.currentMp = math.max(0, attacker.currentMp - math.round(attacker.currentMp * ko.mpLossFrac))
		end
		if ko.apGain > 0 then
			-- Flag it; CommandService STEP 9 grants the AP once per turn (before end-turn check).
			attacker.pendingKoApGain = (attacker.pendingKoApGain or 0) + ko.apGain
		end
		if ko.healFrac > 0 or ko.mpFrac > 0 or ko.mpLossFrac > 0 or ko.apGain > 0 then
			print(string.format("[CombatResolver] On-KO traits: %s (kills=%d)", attacker.name, attacker.killsThisBattle))
		end
	end

	-- Augment effects (Slice 4 — AugmentEffectService)
	if attacker and outcome.skillId and actual > 0 then
		local augIds = AugmentEffectService.GetAugmentsForSkill(attacker, outcome.skillId)
		if #augIds > 0 then
			AugmentEffectService.OnDamageResolved(attacker, target, actual, nil, augIds, nil)
			-- OnKill: if target died
			if not target.isAlive then
				AugmentEffectService.OnKill(attacker, target, nil, augIds)
			end
		end
	end

	-- Shadow Hide-on-hit: defender gains Hide after taking damage
	if actual > 0 then
		RacePassiveService.OnDamageReceived(target, actual, outcome.sourceUnitId)
		DoctrinePassiveService.OnDamageTaken(target)
	end

	-- Phase 3 on-hit-received debuff traits (fire on a landed hit). Status application
	-- deals no damage, so these can't re-trigger this hook directly. REACTION RULE
	-- (user 2026-10-04): a reaction must not trigger another reaction unless it says so.
	-- A counter-attack IS a reaction, so a counter's hit (outcome.isCounter) must NOT
	-- provoke Retaliator / Defenseless / Lingering Curse. Gate on `not outcome.isCounter`.
	if actual > 0 and target.isAlive and not outcome.isCounter then
		-- Defenseless / Lingering Curse: target takes 1 random debuff from the curated pool.
		if TraitEffectService.HasSelfDebuffOnHit(target) then
			local dbf = TraitEffectService.RollRandomDebuff()
			StatusService.ApplyStatus(target, dbf, target.id)
			print(string.format("[CombatResolver] Defenseless/Lingering Curse: %s self-inflicts %s", target.name, dbf))
		end
		-- Retaliator: inflict the target's per-unit rolled debuff on the attacker.
		if attacker and attacker.isAlive and TraitEffectService.HasDebuffAttackerOnHit(target) then
			if not target.retaliatorDebuff then
				target.retaliatorDebuff = TraitEffectService.RollRandomDebuff()
			end
			StatusService.ApplyStatus(attacker, target.retaliatorDebuff, target.id)
			print(string.format("[CombatResolver] Retaliator: %s inflicts %s on %s", target.name, target.retaliatorDebuff, attacker.name))
		end
		-- Wrathful / Meek: each attack received accumulates a damage-dealt +/- % onto the
		-- target. Hits land during an enemy turn, so the stack boosts the target's NEXT
		-- turn and Main clears it at the end of that turn (1-turn window, user Option A
		-- 2026-10-04). Gated by `not outcome.isCounter` above, so a counter-attack (a
		-- reaction) does NOT build the stack (reaction rule 2026-10-04).
		local stackStep = TraitEffectService.GetCombatStackPerHit(target)
		if stackStep ~= 0 then
			target.combatStackPct = (target.combatStackPct or 0) + stackStep
			print(string.format("[CombatResolver] Wrathful/Meek: %s stack now %+.2f", target.name, target.combatStackPct))
		end
	end

	-- LIZARDMEN — Spiked Hide (2026-10-02): a MELEE hit from one of the 8 adjacent
	-- tiles reflects damage = the Lizardman's level onto the attacker. Not on ranged
	-- or AOE hits. Applied with UnitSchema_ApplyDamage directly (never through
	-- ApplyOutcome), so a reflect cannot re-trigger reflects / lifesteal / other
	-- reaction hooks -- no loop (TRG-010 pattern). outcome.isReflect guards re-entry.
	if attacker and actual > 0 and attacker ~= target and attacker.isAlive
		and not outcome.isReflect and isMeleeHit(outcome, attacker, target) then
		local reflect = RacePassiveService.GetMeleeReflectDamage(target)
		if reflect > 0 then
			local reflected = UnitSchema_ApplyDamage(reflect, attacker)
			print(string.format(
				"[CombatResolver] Lizardmen Spiked Hide: %s reflects %d to %s | HP: %d/%d%s",
				target.name, reflected, attacker.name, attacker.currentHp, attacker.maxHp,
				attacker.isAlive and "" or " | DEFEATED"
			))
			if not attacker.isAlive then
				attacker._killedBy = target.id
				RacePassiveService.OnUnitKO(attacker)
			end
			if BattleVisualBroadcaster.UnitStateChanged then
				BattleVisualBroadcaster.UnitStateChanged(attacker)
			end
		end
	end

	-- OGRE — Brutish Bulk (2026-10-02): on a successful hit, bonus RT delay on the
	-- TARGET = round(0.50 x the Ogre's effective Weapon WT). Raw value per the DB text
	-- (not passed through VIT RT-delay resistance).
	if attacker and actual > 0 and attacker ~= target and target.isAlive then
		local ogreDelay = RacePassiveService.GetOnHitRtDelay(attacker)
		if ogreDelay > 0 then
			target.remainingRt = (target.remainingRt or 0) + ogreDelay
			print(string.format(
				"[CombatResolver] Ogre Brutish Bulk: %s delays %s by +%d RT (now %d)",
				attacker.name, target.name, ogreDelay, target.remainingRt
			))
		end
	end

	local posLabel = ""
	if outcome.positionalMod and outcome.positionalMod ~= 1.0 then
		local pct = math.round((outcome.positionalMod - 1) * 100)
		posLabel = string.format(" | Pos:%+d%%", pct)
	end

	local facingLabel = ""
	if outcome.facingZone and outcome.facingZone ~= "Front" then
		facingLabel = string.format(" | %s(+%.0f%%)", outcome.facingZone, GameConstants.GetFacingPrecisionBonus(outcome.facingZone) * 100)
	end

	print(string.format(
		"[CombatResolver] %s takes %d damage (AP:%.1f HQ:%.2f%s%s) | HP: %d/%d %s%s",
		target.name,
		outcome.finalDamage,
		outcome.attackPower,
		outcome.hitQuality,
		posLabel,
		facingLabel,
		target.currentHp,
		target.maxHp,
		target.isAlive and "" or "| DEFEATED",
		statusApplied and (" | +" .. statusApplied) or ""
	))

	-- Zombie KO timer: start revive countdown on death
	if not target.isAlive then
		RacePassiveService.OnUnitKO(target)
	end

	-- DRAGONKIN — Dragonscale (2026-10-02): this hit may have applied (Fire) or
	-- removed (Water) Burn -- resync the Burn-conditional +15% stat bonus.
	RacePassiveService.RefreshConditionalStats(target)

	return actual, statusApplied
end

--------------------------------------------------
-- BIND APPLY DAMAGE / HEALING
--------------------------------------------------

local _applyDamage = nil
local _applyHealing = nil

function CombatResolver.BindApplyDamage(fn)
	_applyDamage = fn
end

function CombatResolver.BindApplyHealing(fn)
	_applyHealing = fn
end

function UnitSchema_ApplyDamage(amount, unit)
	if _applyDamage then
		-- Forward ALL returns from the bound UnitSchema.ApplyDamage:
		-- actual, shieldBroke, shieldAbsorbed, shieldMaxAtBreak, retributionDamage.
		-- The 5th (retributionDamage) carries a broken Retribution Shell's snapshot
		-- so ApplyOutcome can retaliate against the breaker (shield subsystem).
		return _applyDamage(unit, amount)
	end
	-- Fallback path (no bound ApplyDamage): no shield plumbing available.
	local actual = math.min(unit.currentHp, amount)
	unit.currentHp = unit.currentHp - actual
	if unit.currentHp <= 0 then
		-- Armor passive: survive lethal damage at 1 HP (once per battle)
		if ArmorPassiveService.CanSurviveLethalDamage(unit) then
			unit.currentHp = 1
			print(string.format("[CombatResolver] %s survived lethal damage via armor passive (1 HP)", unit.name))
			return actual - 1
		end
		unit.isAlive   = false
		unit.currentHp = 0
		unit.currentAp = 0
	end
	return actual
end

function UnitSchema_ApplyHealing(amount, unit)
	if _applyHealing then
		return _applyHealing(unit, amount)
	end
	local actual = math.min(unit.maxHp - unit.currentHp, amount)
	unit.currentHp = unit.currentHp + actual
	return actual
end

return CombatResolver