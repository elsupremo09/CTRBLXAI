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
local WeaponPassiveService = require(script.Parent.WeaponPassiveService) -- Weapon passives (Group 1, 2026-10-23)

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

-- Skill Potency applies ONLY to skills whose authored DB formula declares it
-- (CTRBLXAI.db core_stats id 31: "Skill Potency does not apply to a Skill formula
-- unless the Skill explicitly declares it"). Built once from SkillData.powerFormula
-- (generated from the DB) so the set always matches the authored data — no hardcoded
-- list, no drift. 65/108 skills declare it. (2026-10-19 fix: replaces an earlier
-- blanket apply that wrongly scaled all 108.)
local SkillData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("SkillData")
)
local POTENCY_DECLARED = {}
for skillId, def in pairs(SkillData) do
	local pf = type(def) == "table" and def.powerFormula
	if type(pf) == "string" and string.find(string.lower(pf), "skill potency", 1, true) then
		POTENCY_DECLARED[skillId] = true
	end
end

local CombatResolver = {}

-- Optional: TileEffectService injected at runtime (DI, mirrors CommandService/
-- BattleCoordinator) so hit-quality can read the defender's active tile effect
-- (e.g. Steam occupyEvasion). Wired in Main.server.lua during init.
local _unitsProvider = nil
function CombatResolver.SetUnitsProvider(fn) _unitsProvider = fn end

-- BD-014 Guardian Mantle (2026-10-24): a Guarding ally wearing it shares 50% of its Guard damage
-- reduction with adjacent (Chebyshev 1) same-side units, whether or not they are Guarding. Returns
-- the best such share for `defender` (0 if none). Uses the injected units provider (mirrors
-- StatusService.SetAuraUnitsProvider) so ApplyOutcome's signature stays untouched.
-- SUP-011 Guardian Standard (2026-10-27): a living same-side device with auraSpec.guardBonus
-- adds that many Guard percentage points while the defender is Guarding (best one counts).
local function guardAuraBonus(defender)
	if not defender or not defender.tileX or not _unitsProvider then return 0 end
	local units = _unitsProvider()
	if type(units) ~= "table" then return 0 end
	local best = 0
	for _, u in ipairs(units) do
		local a = u.auraSpec
		if u ~= defender and u.isAlive and a and a.guardBonus and u.side == defender.side and u.tileX
			and math.max(math.abs(u.tileX - defender.tileX), math.abs(u.tileY - defender.tileY)) <= (a.radius or 0) then
			best = math.max(best, a.guardBonus)
		end
	end
	return best
end

local function guardianMantleShare(defender)
	if not defender or not defender.tileX or not _unitsProvider then return 0 end
	local units = _unitsProvider()
	if type(units) ~= "table" then return 0 end
	local best = 0
	for _, ally in ipairs(units) do
		if ally ~= defender and ally.isAlive and ally.side == defender.side
			and ally.tileX and ally.tileY
			and math.max(math.abs(ally.tileX - defender.tileX), math.abs(ally.tileY - defender.tileY)) == 1 then
			local guarding = false
			if ally.statusInstances then
				for _, inst in ipairs(ally.statusInstances) do
					if inst.id == "Guard" then guarding = true; break end
				end
			end
			if guarding and ArmorPassiveService.GetGuardAllyProtection(ally) then
				local allyMit = math.min(GameConstants.GUARD_MITIGATION + (ally.guardBonus or 0), GameConstants.GUARD_CAP)
				local share = allyMit * 0.50
				if share > best then best = share end
			end
		end
	end
	return best
end

local _tileEffectService = nil
function CombatResolver.SetTileEffectService(tes)
	_tileEffectService = tes
	-- Forward to RacePassiveService (Treant Forest Wrath reads the Vines effect).
	if RacePassiveService.SetTileEffectService then
		RacePassiveService.SetTileEffectService(tes)
	end
end

-- PHASE 2 — ELECTRIC SHOCK accumulator (project_rules 146-147). ApplyOutcome buffers
-- each Electric hit of the CURRENT action here; CommandService calls FlushElectricShock
-- once at the end of the action (after all targets are hit) so the shock knows the
-- biggest final hit and can exclude ALL initial targets. _electricEvent.hits is a list
-- of { id, x, y, dmg }. Buffer-based so multi-target (Cleave/AOE/Chain) electric
-- attacks produce ONE shock, not one per target.
local _electricEvent = { hits = {}, ownerId = nil }

-- Buffer one Electric hit for the pending shock (called from ApplyOutcome).
local function bufferElectricHit(target, finalDmg, attacker)
	if not (target and target.tileX and target.tileY) then return end
	table.insert(_electricEvent.hits, {
		id = target.id, x = target.tileX, y = target.tileY, dmg = finalDmg or 0,
	})
	_electricEvent.ownerId = attacker and attacker.id or _electricEvent.ownerId
end

-- Resolve + clear the buffered Electric shock. Called by CommandService once per
-- action, after the if/elseif action chain. nil-safe if no electric hits occurred.
function CombatResolver.FlushElectricShock(allUnits)
	local hits = _electricEvent.hits
	if #hits == 0 then return end
	local ownerId = _electricEvent.ownerId
	-- reset buffer BEFORE resolving so a re-entrant path can't double-fire
	_electricEvent = { hits = {}, ownerId = nil }
	if not (_tileEffectService and _tileEffectService.ResolveElectricShock) then return end

	local biggest = 0
	local excludeIds = {}
	local seedTiles = {}
	for _, h in ipairs(hits) do
		if h.dmg > biggest then biggest = h.dmg end
		excludeIds[h.id] = true
		table.insert(seedTiles, { x = h.x, y = h.y })  -- seed = tile the target stood on
	end
	if biggest <= 0 then return end
	_tileEffectService.ResolveElectricShock(seedTiles, biggest, excludeIds, ownerId, allUnits)
end

-- Ally-KO reaction buffer (Perks & Flaws 2026-10-23): units KO'd by this action's combat
-- damage, pending nearby-ally reactions. Mirrors the electric buffer -- filled in
-- ApplyOutcome, drained once per action by CommandService via FlushAllyKoReactions.
local _allyKoBuffer = {}
local ALLY_KO_RADIUS = 3 -- Chebyshev tiles; "nearby" (user default 2026-10-23)

-- Resolve + clear buffered ally-KO reactions. For each unit KO'd this action, nearby LIVING
-- same-side allies suffer Hemophage (lose a fraction of CURRENT HP) and/or Sluggish Finisher
-- (lose 1 AP, once per turn). Reaction damage is applied DIRECTLY (not via ApplyOutcome), so a
-- Hemophage self-KO cannot buffer a further reaction -- no chain (TRG-010 pattern). Buffer is
-- reset BEFORE resolving so nothing re-enters. Combat deaths only; DoT / CT-tick / collision /
-- fall deaths are not buffered (deferred).
function CombatResolver.FlushAllyKoReactions(allUnits)
	local dead = _allyKoBuffer
	if #dead == 0 then return end
	_allyKoBuffer = {}
	if type(allUnits) ~= "table" then return end
	for _, d in ipairs(dead) do
		d._allyKoBuffered = nil
		if d.tileX and d.tileY then
			for _, u in ipairs(allUnits) do
				if u ~= d and u.isAlive and u.side == d.side and u.tileX and u.tileY then
					local dist = math.max(math.abs(u.tileX - d.tileX), math.abs(u.tileY - d.tileY))
					if dist <= ALLY_KO_RADIUS then
						local frac = TraitEffectService.GetAllyKoHpLossFraction(u)
						if frac > 0 and (u.currentHp or 0) > 0 then
							local loss = math.max(1, math.round((u.currentHp or 0) * frac))
							local applied = UnitSchema_ApplyDamage(loss, u)
							print(string.format(
								"[CombatResolver] Hemophage: %s loses %d HP (ally %s KO'd nearby) | HP: %d/%d%s",
								u.name, applied, d.name, u.currentHp, u.maxHp, u.isAlive and "" or " | DEFEATED"
							))
							if not u.isAlive then
								u._killedBy = u._killedBy or d._killedBy
								RacePassiveService.OnUnitKO(u)
							end
							if BattleVisualBroadcaster.UnitStateChanged then
								BattleVisualBroadcaster.UnitStateChanged(u)
							end
						end
						if TraitEffectService.HasAllyKoApLoss(u) and not u.sluggishApLossUsedThisTurn then
							u.currentAp = math.max(0, (u.currentAp or 0) - 1)
							u.sluggishApLossUsedThisTurn = true
							print(string.format(
								"[CombatResolver] Sluggish Finisher: %s loses 1 AP (ally %s KO'd nearby) | AP: %d",
								u.name, d.name, u.currentAp
							))
						end
					end
				end
			end
		end
	end
end

-- Weather passive element-damage modifier (Rain/Heatwave/Dark Eclipse/Holy Aurora/
-- Strong Wind). Injected to avoid a require cycle. nil-safe -> multiplier 1.0.
-- RESOLUTION COUNTER (2026-10-27, Countermeasure Turret "one interception per resolution").
-- CommandService calls BeginResolution at the start of every command / channel activation.
local _resolutionId = 0
function CombatResolver.BeginResolution()
	_resolutionId += 1
end

-- COUNTERMEASURE TURRET (DEP-018): a living device with auraSpec.interceptLeft > 0 blocks a
-- hostile RANGED hit (attacker carries a weapon projectile type -- the same rule Mirror Mail's
-- projectile reflect uses) aimed at a unit of its side within its radius. At most one block
-- per turret per resolution. Item hits (timed / placed-object shots) are not intercepted.
local function tryIntercept(outcome, target, attacker)
	if not (attacker and target and attacker ~= target and attacker.weaponProjectileType ~= nil) then return false end
	if outcome.skillId and string.sub(tostring(outcome.skillId), 1, 5) == "ITEM-" then return false end
	if not (target.tileX and _unitsProvider) then return false end
	local units = _unitsProvider()
	if type(units) ~= "table" then return false end
	for _, u in ipairs(units) do
		local a = u.auraSpec
		if u.isAlive and a and (a.interceptLeft or 0) > 0 and u.side == target.side and attacker.side ~= u.side
			and u.tileX and u._lastIntercept ~= _resolutionId
			and math.max(math.abs(u.tileX - target.tileX), math.abs(u.tileY - target.tileY)) <= (a.radius or 0) then
			a.interceptLeft -= 1
			u._lastIntercept = _resolutionId
			target._blockedRes = _resolutionId  -- read by WasLastHitBlocked (user ruling 2026-10-27)
			print(string.format("[CombatResolver] %s intercepts %s's shot at %s | %d left",
				tostring(u.name), tostring(attacker.name), tostring(target.name), a.interceptLeft))
			return true
		end
	end
	return false
end

-- User ruling 2026-10-27: a blocked shot does NOTHING -- callers skip the hit's after-effects
-- (weapon RT delay, knockback / pull) when the LAST hit on this target in the current
-- resolution was blocked. A later landed hit on the same target clears the flag.
function CombatResolver.WasLastHitBlocked(target)
	return target ~= nil and target._blockedRes ~= nil and target._blockedRes == _resolutionId
end

local _weatherService = nil
function CombatResolver.SetWeatherService(ws)
	_weatherService = ws
end
local function weatherElementMult(element, defender)
	-- Weather shield (2026-10-27, Weather Stabilizer + Totem): a protected defender takes no
	-- weather change to element damage.
	if defender and _weatherService and _weatherService.IsUnitShielded
		and _weatherService.IsUnitShielded(defender, _unitsProvider and _unitsProvider() or nil) then
		return 1.0
	end
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

-- Exported wrapper (2026-10-24, all-tile targeting): lets CommandService derive a
-- skill's element from its tags the SAME way resolution does, so a widened skill
-- committed on an EMPTY tile can fire the terrain reaction (ResolveElementOnTile)
-- with the correct element. Single source of truth — never duplicate ELEMENT_SET.
function CombatResolver.ExtractSkillElement(skillDef)
	return extractElement(skillDef and skillDef.tags)
end

-- Returns true if unit has the Undead race tag
local function isUndead(unit)
	-- The Undead STATUS (e.g. raised by a Chaos Necromancer) counts the same as an Undead race.
	for _, inst in ipairs(unit.statusInstances or {}) do
		if inst.id == "Undead" then return true end
	end
	if not unit.raceId then return false end
	local raceEntry = RaceData.GetRace(unit.raceId)
	if raceEntry and raceEntry.tags then
		for _, tag in ipairs(raceEntry.tags) do
			if tag == "Undead" then return true end
		end
	end
	return false
end
-- Public read-only alias (2026-10-26, DAM-009 Holy Water item + its target validation).
CombatResolver.IsUndead = isUndead
-- Generic race-tag check (2026-10-26, CON-016 Magnetic Snare "Mechanical" targets).
function CombatResolver.HasRaceTag(unit, tag)
	if not (unit and unit.raceId) then return false end
	local raceEntry = RaceData.GetRace(unit.raceId)
	for _, t in ipairs((raceEntry and raceEntry.tags) or {}) do
		if t == tag then return true end
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

	-- Element wards (2026-10-26): single chokepoint for basic attacks and skills / item damage.
	--   * Elemental Ward status (SUP-016): x0.75 vs the warded element.
	--   * Elemental Ward Totem aura (DEP-013): x0.80 vs its picked element, for same-side
	--     units in its radius. Several totems on the same element do not stack (the
	--     strongest applies).
	-- Ruling 10 (different effects are TOTALED): status + totem = 25% + 20% = 45% less.
	do
		local cut = 0
		-- Firebreak zone (user ruling 2026-10-27): everyone standing in it takes half Fire damage.
		-- Adds into the same total as the wards (capped at 100% by the max(0, ...) below).
		if element == "Fire" and StatusService.IsFireGuarded and StatusService.IsFireGuarded(defender) then
			cut += 0.5
		end
		local _ward = StatusService.HasStatus(defender, "Elemental Ward")
		if type(_ward) == "table" and _ward.wardElement and element == _ward.wardElement then
			local _wdef = GameConstants.STATUSES["Elemental Ward"]
			cut += 1 - ((_wdef and _wdef.elementWardMult) or 0.75)
		end
		local units = _unitsProvider and _unitsProvider() or nil
		if type(units) == "table" and defender.tileX then
			local best = 0
			for _, u in ipairs(units) do
				local a = u.auraSpec
				if u ~= defender and u.isAlive and a and a.wardMult and a.wardElement == element
					and u.side == defender.side and u.tileX
					and math.max(math.abs(u.tileX - defender.tileX), math.abs(u.tileY - defender.tileY)) <= (a.radius or 0) then
					best = math.max(best, 1 - a.wardMult)
				end
			end
			cut += best
		end
		if cut > 0 then
			finalDamage = math.max(0, math.round(finalDamage * math.max(0, 1 - cut)))
		end
	end

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
local function applyElementStatusTriggers(sourceUnitId: any, defender: any, element: any, actualDamage: any, alreadyApplied: any, attackerUnit: any)
	if actualDamage <= 0 or not defender.isAlive then return end

	-- Ignite (Group 2): a Fire->Burn trigger from an Ignite carrier stores 25% of the
	-- fire damage instead of the base 20% (nil for non-Ignite -> base fraction).
	local igniteBurnFrac = WeaponPassiveService.IgniteBurnFraction(attackerUnit)
	local function tryApply(statusId, fireDmg)
		local frac = (statusId == "Burn") and igniteBurnFrac or nil
		local applied, _, immuneReason = StatusService.ApplyStatus(defender, statusId, sourceUnitId, fireDmg, nil, frac)
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
		precision = precision + (attackerUnit.gearDerived and attackerUnit.gearDerived.precision or 0)
	end
	if defenderUnit then
		evasiveness = evasiveness + TraitEffectService.GetEvasivenessModifier(defenderUnit)
		evasiveness = evasiveness + (defenderUnit.gearDerived and defenderUnit.gearDerived.evasiveness or 0)
		-- FT-009 Retreat Boots: +20% Evasiveness while the retreat window is active (armed at move-end
		-- when every step strictly increased distance from the nearest enemy; cleared at the wearer's
		-- next turn via OnTurnStart). Fraction, same units as the trait evasiveness fold. Pure READ ->
		-- safe inside Resolve* that AI preview calls.
		evasiveness = evasiveness + ArmorPassiveService.GetRetreatEvasivenessBonus(defenderUnit)
		-- Evasion Surge (reworked 2026-10-26): +0.30 evasiveness while the defender holds >=1 charge.
		-- Pure READ (safe in AI preview); the charge is CONSUMED per incoming hit in ApplyOutcome.
		if (defenderUnit._evasionSurgeStacks or 0) > 0 then
			evasiveness = evasiveness + 0.30
		end
		-- Evasion (weapon native, Parrying Dagger): +0.15 final Evasiveness (DB "+15% final
		-- Evasiveness", flat additive to match the project's other evasiveness folds + the
		-- PrecisionStrike +0.15 ruling). Pure READ -> safe in AI preview. Defensive: applies to
		-- EVERY incoming attack (basic and skill) since it modifies the defender's own stat.
		evasiveness = evasiveness + WeaponPassiveService.GetEvasivenessBonus(defenderUnit)
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
				-- Debuff Resistance (ruling 11, 2026-10-26): a turn-based debuff's value is
				-- scaled by the resistance stored on the instance at application (Cursed).
				hq = hq + sdef.hitQualityMod * (inst.valueScale or 1)
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

-- Melee-hit classification for on-hit reactions (Reptilian Spiked Hide, 2026-10-02).
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
	-- Fortify (weapon native, Spear): add the defender's accumulated on-hit flat Defense (0 without
	-- the passive / before any hit this turn) to its equipment Defense before the defense-power curve.
	local dp = GameConstants.CalcDefensePower(GameConstants.GetUnitDefense(defender) * StatusService.GetEquipDefenseMultiplier(defender) + WeaponPassiveService.GetFortifyFlatDefense(defender), dStats.VIT)
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

	-- Weapon passives (Group 1, basic attack): armor penetration on the target's
	-- effective Defense, then hit-quality passives (Tricky / Precision Strike / True
	-- Strike). Nil-safe no-ops when the weapon carries none.
	effectiveDefense = effectiveDefense * WeaponPassiveService.DefenseMultiplier(attacker)
	hitQuality = WeaponPassiveService.AdjustBasicHitQuality(attacker, hitQuality, dStats.AGI)

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
	-- Minion Specialist / Skill Issues (2026-10-23): summon outgoing-damage multiplier from
	-- the owner's trait (1 when absent / not a modified summon). Stamped on the unit at creation.
	if attacker.summonDamageMult and attacker.summonDamageMult ~= 1 then
		finalDamage = math.max(0, math.round(finalDamage * attacker.summonDamageMult))
	end
	-- Slice 5 buff: Battle Rage (+20% physical) / Rune Ward (+10% attack) on the
	-- attacker. Basic attacks are always physical (isSpell=false).
	finalDamage = math.max(0, math.round(finalDamage * StatusService.GetDamageDealtMultiplier(attacker, false)
		* StatusService.GetDamageReceivedMultiplier(defender))) -- Hold the Line x0.85 (2026-10-07)
	-- Weapon passives (Group 1): Backstab (rear +50%) / Executioner (<25% HP +30%).
	finalDamage = math.max(0, math.round(finalDamage * WeaponPassiveService.ConditionalDamageMultiplier(attacker, defender, facingZone)))
	-- HighGround (weapon native, Great Bow): +35% when attacking from strictly higher elevation.
	-- Positional offensive bonus (pre-guard, like Backstab above). Hybrid: basic + skill.
	do
		local hgBonus = WeaponPassiveService.GetHighGroundBonus(attacker)
		if hgBonus > 0 then
			local aElev = GameConstants.GetElevation(attacker.tileX, attacker.tileY)
			local dElev = GameConstants.GetElevation(defender.tileX, defender.tileY)
			if aElev > dElev then
				finalDamage = math.max(0, math.round(finalDamage * (1 + hgBonus)))
			end
		end
	end

	-- Charge (weapon native, Lance): +6% final damage per tile the attacker moved THIS TURN before
	-- this attack (DB "+6% damage per tile moved this turn"). BASIC-ATTACK ONLY (not in ResolveSkill).
	-- Reads the per-turn tiles accumulator via the getter; 0 without Charge or without prior movement.
	do
		local chargeBonus = WeaponPassiveService.GetChargeDamageBonus(attacker)
		if chargeBonus > 0 then
			finalDamage = math.max(0, math.round(finalDamage * (1 + chargeBonus)))
		end
	end

	-- FT-008 Skirmisher Greaves: after moving >=3 path-cost this turn, the NEXT direct damage
	-- ACTION gains +15% final damage -- the WHOLE action, every hit of a multi-hit swing, not just
	-- the first (design ruling 2026-10-25: "next attack" = next action, not next hit). Pure READ
	-- here (safe inside Resolve* that AI preview calls); the window is marked used ONCE at the END
	-- of the action on the real path (CommandService: after the Dual Strike loop for Basic Attacks,
	-- at the skill shared-tail for Skills), NOT per-hit here -- so all hits of the one action read
	-- not-yet-used and get +15%, while a separate later action this turn sees it used. Re-arms at
	-- OnTurnStart.
	if attacker and not attacker._armorSkirmishUsed then
		local skirmish = ArmorPassiveService.GetMoveSkirmishDamageBonus(attacker)
		if skirmish > 0 then
			finalDamage = math.max(0, math.round(finalDamage * (1 + skirmish)))
		end
	end

	-- FT-010 Vanguard Greaves: incoming DIRECT damage -15% while the window is active (armed at
	-- move-end when the defender ended its Move adjacent to an enemy; cleared at its next turn
	-- start via OnTurnStart). Pure read -> safe inside Resolve* (AI preview reflects it too).
	if defender._armorVanguardDrActive then
		local vg = ArmorPassiveService.GetMoveVanguardConfig(defender)
		if vg then
			finalDamage = math.max(0, math.round(finalDamage * (1 - vg.damageReduction)))
		end
	end

	-- Step 8: Guard and other final mitigation
	-- Check Guard via status instances (Guard is now a proper status)
	local hasGuard = false
	if defender.statusInstances then
		for _, inst in ipairs(defender.statusInstances) do
			if inst.id == "Guard" then hasGuard = true; break end
		end
	end
	local guardMitigatedAmount = 0
	local wasGuarding = false
	if hasGuard and not WeaponPassiveService.BypassesGuard(attacker) then
		wasGuarding = true
		-- BD-006 Layered Lamellar: successive-hit DR (0 until OnGuardHitReceived accrues hits) adds
		-- into the Guard mitigation, still clamped to GUARD_CAP. 0 for units without the passive.
		local mitigation = GameConstants.GUARD_MITIGATION + (defender.guardBonus or 0)
			+ ArmorPassiveService.GetGuardLayeredBonus(defender)
			+ guardAuraBonus(defender)  -- SUP-011 Guardian Standard
		mitigation = math.min(mitigation, GameConstants.GUARD_CAP)
		local preGuard = finalDamage
		finalDamage = math.max(0, math.round(finalDamage * (1 - mitigation)))
		guardMitigatedAmount = math.max(0, preGuard - finalDamage)
	end
	-- BD-014 Guardian Mantle: apply any adjacent-ally shared Guard DR (multiplicative, after own
	-- guard; runs whether or not this unit is Guarding).
	do
		local gmShare = guardianMantleShare(defender)
		if gmShare > 0 then
			finalDamage = math.max(0, math.round(finalDamage * (1 - gmShare)))
		end
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
	-- Ignite (PAS-037, Group 2): an otherwise-Physical basic attack executes as Fire.
	-- Never overrides a real weapon element (transformation). DB: "would otherwise be
	-- non-elemental (Physical)".
	if attackElement == "Physical" and WeaponPassiveService.HasCombat(attacker, "Ignite") then
		attackElement = "Fire"
	end

	-- Attunement (weapon native, Crystal): +25% elemental damage dealt (applies when the attack
	-- element is elemental; in the element section like the terrain-element bonus). Hybrid: basic + skill.
	do
		local atBonus = WeaponPassiveService.GetAttunementBonus(attacker, attackElement)
		if atBonus > 0 then
			finalDamage = math.max(0, math.round(finalDamage * (1 + atBonus)))
		end
	end

	-- Step 6b: Terrain occupy bonus — attacker's tile element bonus
	-- Flight bypasses terrain bonuses
	-- An item-owned timed hit (isItemSource, user ruling 2026-10-27) stands on no tile of its
	-- own, so it gets no terrain occupy bonus.
	if not StatusService.HasStatus(attacker, "Flight") and not attacker.isItemSource then
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
	finalDamage = math.max(0, math.round(finalDamage * weatherElementMult(attackElement, defender)))

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
		appliesStatuses = WeaponPassiveService.OnHitStatuses(attacker), -- weapon status-appliers (Group 1)
		weaponDrainFrac = WeaponPassiveService.DrainFraction(attacker), -- Drain (Group 1)
		element        = attackElement,
		sourceUnitId   = attacker.id,
		guardMitigatedAmount = guardMitigatedAmount,  -- armor Guard on-hit reactions (2026-10-24)
		wasGuarding    = wasGuarding,
	}
end

--------------------------------------------------
-- PUBLIC: RESOLVE SKILL (damage skill, single target)
--------------------------------------------------

-- SHARED PRE-DEFENSE POWER (used by ResolveSkill/ResolveHealing AND the unit
-- inspector's raw-damage display, so the shown number can never drift from
-- real combat). Skill power = weapon attack power x skill power multiplier.
function CombatResolver.EstimateSkillPower(attacker, skillDef, statOverride)
	local aStats = attacker.effectiveStats or {}
	local weaponDamage = attacker.weaponDamage or 10
	local int = aStats.INT or 10
	-- ITEM DAMAGE (2026-10-26): a consumable supplies a self-contained flat Power value
	-- (e.g. "Fire Power = 18 + 0.40×IL + 0.35×INT"), already computed by ItemEffectService.
	-- It is NOT weapon-scaled and already bakes in its own IL/stat scaling, so return it
	-- directly and skip the Weapon-Attack-Power base and the Skill Potency multiply (either
	-- would double-scale). Downstream ResolveSkill still runs Defense, element resistance,
	-- and race/doctrine/trait modifiers, so item damage obeys the same resolution rules.
	if skillDef.flatPower ~= nil then
		return skillDef.flatPower
	end
	local sp = weaponDamage * (skillDef.power or 1.0)
	-- Stat-scaling augment (AGI/DEX/INT/LUK/VIT-SCALING, 2026-10-24): redirect the
	-- attack-power scaling stat to the augment's chosen stat (authored intent). nil → STR
	-- as before (backward compatible; other callers pass no override).
	if skillDef.inheritStr then
		sp = GameConstants.CalcAttackPower(sp, statOverride and (aStats[statOverride] or aStats.STR) or aStats.STR)
	elseif statOverride then
		sp = GameConstants.CalcAttackPower(sp, aStats[statOverride] or 10)
	end
	-- Apply the authored Skill Potency Multiplier = 1 + INT/(200+INT) ONLY to skills whose
	-- DB formula declares it (POTENCY_DECLARED, built above). This fixes the Fire Bolt
	-- zero-damage bug (INT now scales declared skills) WITHOUT over-applying to the 43
	-- utility/buff/summon/shield skills that do not declare potency (CTRBLXAI.db core_stats
	-- id 31). Downstream race/doctrine/trait potency modifiers in ResolveSkill still apply.
	if skillDef.id and POTENCY_DECLARED[skillDef.id] then
		sp = sp * (GameConstants.CalcSkillPotency(int) + (attacker.gearDerived and attacker.gearDerived.skillPotency or 0))
	end
	-- SKL-LUCKY-STRIKE signature recipe (DB powerFormula): additional LUK scaling on top
	-- of the Weapon-Attack-Power x Skill-Potency base above.
	--   LUK Power Bonus = 0.75 x LUK / (100 + LUK)
	if skillDef.id == "SKL-LUCKY-STRIKE" then
		local luk = aStats.LUK or 10
		sp = sp * (1 + 0.75 * luk / (100 + luk))
	end
	-- DOC-SPELLBLADE-01 "Arcane Strike" (DB powerFormula): flat +INT/2 added to Skill
	-- Power AFTER the potency multiply above, BEFORE Defense (applied downstream).
	if skillDef.id == "DOC-SPELLBLADE-01" then
		sp = sp + int / 2
	end
	return sp
end

-- Dark Restoration card power (DB SKL-DARK-RESTORATION Power_Formula), shared by its heal and its
-- damage so they can never drift: (12 + 0.30L + 0.35INT + Weapon Damage x 0.35) x Skill Potency.
-- L = Effective Skill Level = main-hand item level (project convention).
function CombatResolver.EstimateDarkRestorationPower(caster)
	local int = (caster.effectiveStats and caster.effectiveStats.INT) or 10
	local mainHand = caster.equipmentSlots and caster.equipmentSlots.MainHand
	local level = (mainHand and mainHand.itemLevel) or 1
	local potency = GameConstants.CalcSkillPotency(int) + (caster.gearDerived and caster.gearDerived.skillPotency or 0)
	return (12 + 0.30 * level + 0.35 * int + (caster.weaponDamage or 10) * 0.35) * potency
end

-- Pre-target heal power (before the target's VIT heal efficiency).
function CombatResolver.EstimateHealPower(caster, skillDef)
	local int = (caster.effectiveStats and caster.effectiveStats.INT) or 10
	if skillDef and skillDef.id == "SKL-DARK-RESTORATION" then
		-- Its card formula, not the generic heal (UAT 2026-10-27 A3). Dark-skill race potency
		-- bonus (Demon Infernal Pact) applies like any Dark-tagged heal.
		return CombatResolver.EstimateDarkRestorationPower(caster)
			* RacePassiveService.GetSkillPotencyMultiplier(caster, skillDef.tags, int)
	end
	if skillDef and skillDef.isMenderHeal then
		-- Authored Mender heal: (10 + 0.20L + 0.40 x Mender INT) x Skill Potency
		local L = caster.level or 1
		return (10 + 0.20 * L + 0.40 * int) * (GameConstants.CalcSkillPotency(int) + (caster.gearDerived and caster.gearDerived.skillPotency or 0))
	end
	local weaponDamage = caster.weaponDamage or 10
	-- Skill Potency Multiplier = 1 + INT / (200 + INT)
	local skillPotency = GameConstants.CalcSkillPotency(int) + (caster.gearDerived and caster.gearDerived.skillPotency or 0)
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

	-- Augment pre-damage calc (2026-10-24 augment fix): OnDamageCalculation was defined but
	-- never called, so stat-scaling / element-conversion / conditional-amplifier / armor-
	-- piercing augments did nothing. Wire it here. nil-safe identity when no augments.
	local _augCalc = { damageMultiplier = 1.0 }
	if skillDef and skillDef.id and AugmentEffectService and AugmentEffectService.OnDamageCalculation then
		local _augIds = AugmentEffectService.GetAugmentsForSkill(attacker, skillDef.id)
		if _augIds and #_augIds > 0 then
			_augCalc = AugmentEffectService.OnDamageCalculation(attacker, defender, skillDef, _augIds) or _augCalc
		end
	end

	-- Skill Power = Weapon Attack Power × power multiplier (shared helper)
	local sp = CombatResolver.EstimateSkillPower(attacker, skillDef, _augCalc.statOverride)

	-- Defense Power from real equipment Defense (core_stats id 30/31). Was hard-coded 0.
	-- Fortify (weapon native, Spear): add the defender's accumulated on-hit flat Defense (skill path).
	local dp = GameConstants.CalcDefensePower(GameConstants.GetUnitDefense(defender) * StatusService.GetEquipDefenseMultiplier(defender) + WeaponPassiveService.GetFortifyFlatDefense(defender), dStats.VIT)
	local effectiveDefense = calcEffectiveDefense(sp, dp)
	-- Augment armor-piercing (2026-10-24): ignore a fraction of effective Defense.
	if _augCalc.armorPiercing and _augCalc.armorPiercing > 0 then
		effectiveDefense = effectiveDefense * (1 - _augCalc.armorPiercing)
	end
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

	local finalDamage = math.max(0, math.round(rawDamage * hitQuality * positionalMod * fortuneMod * (_augCalc.damageMultiplier or 1.0)))

	-- Race passive modifiers (Slice 4F)
	-- Extract element from skill tags (Phase 3)
	local skillElement = extractElement(skillDef.tags)
	-- Augment element conversion (2026-10-24): override the skill's damage element.
	if _augCalc.elementOverride then
		skillElement = _augCalc.elementOverride
	end
	-- Ignite (PAS-037, Group 2): an otherwise-Physical SKILL executes as Fire (DB:
	-- "Basic Attack or Skill"). An authored-element skill keeps its own element, so the
	-- skill still wins on a clash (user ruling 2026-10-23).
	if skillElement == "Physical" and WeaponPassiveService.HasCombat(attacker, "Ignite") then
		skillElement = "Fire"
	end
	local skillIsAOE = skillDef.aoePattern ~= nil and skillDef.aoePattern ~= "Single"
	local skillIsPhysical = (skillElement == nil or skillElement == "Physical" or skillElement == "")
	local raceDealtMod = RacePassiveService.GetDamageDealtModifier(attacker, skillElement, skillIsAOE, defender)
	local raceRecvMod  = RacePassiveService.GetDamageReceivedModifier(defender, skillElement, skillIsAOE, skillIsPhysical)
	-- Doctrine passive modifiers (Slice 4H)
	local docSkillPotency = DoctrinePassiveService.GetSkillPotencyModifier(attacker)
	-- Race Skill Potency (INT contribution) boost -- Celestial Holy / Demon Dark
	-- SKILLS only (2026-10-02). The base Skill Potency (1 + p) is now applied in
	-- EstimateSkillPower, so this Holy/Dark boost is the ratio (1 + 1.20p)/(1 + p),
	-- yielding net (1 + 1.20p). See RacePassiveService.GetSkillPotencyMultiplier.
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
	-- SkillPotency (weapon native, Orb): +8% Skill damage dealt. Multiplicative on final skill
	-- damage alongside the doctrine/race/trait potency mods. 1 without the passive. Pure READ.
	local weaponSkillPotency = WeaponPassiveService.GetSkillDamageMultiplier(attacker)
	finalDamage = math.max(0, math.round(finalDamage * raceDealtMod * raceRecvMod * docSkillPotency * raceSkillPotency * traitSkillPotency * weaponSkillPotency * docDealtMod * docRecvMod * traitDealtMod * traitRecvMod))
	-- HighGround (weapon native, Great Bow): +35% from strictly higher elevation (skill path).
	do
		local hgBonus = WeaponPassiveService.GetHighGroundBonus(attacker)
		if hgBonus > 0 then
			local aElev = GameConstants.GetElevation(attacker.tileX, attacker.tileY)
			local dElev = GameConstants.GetElevation(defender.tileX, defender.tileY)
			if aElev > dElev then
				finalDamage = math.max(0, math.round(finalDamage * (1 + hgBonus)))
			end
		end
	end
	-- Minion Specialist / Skill Issues (2026-10-23): summon outgoing-damage multiplier from
	-- the owner's trait (1 when absent / not a modified summon), on the skill path too.
	if attacker.summonDamageMult and attacker.summonDamageMult ~= 1 then
		finalDamage = math.max(0, math.round(finalDamage * attacker.summonDamageMult))
	end
	-- Slice 5 buff: Spell Focus (+20% spell) / Battle Rage (+20% physical) /
	-- Rune Ward (+10% attack) on the caster. skillIsPhysical selects which.
	finalDamage = math.max(0, math.round(finalDamage * StatusService.GetDamageDealtMultiplier(attacker, not skillIsPhysical)
		* StatusService.GetDamageReceivedMultiplier(defender) -- Hold the Line x0.85 (2026-10-07)
		* (skillDef.potencyBonusMult or 1))) -- Mana Surge +10% potency, snapshotted at commit

	-- FT-008 Skirmisher Greaves: after moving >=3 path-cost this turn, the NEXT direct damage
	-- ACTION gains +15% final damage -- the WHOLE action, every hit of a multi-hit swing, not just
	-- the first (design ruling 2026-10-25: "next attack" = next action, not next hit). Pure READ
	-- here (safe inside Resolve* that AI preview calls); the window is marked used ONCE at the END
	-- of the action on the real path (CommandService: after the Dual Strike loop for Basic Attacks,
	-- at the skill shared-tail for Skills), NOT per-hit here -- so all hits of the one action read
	-- not-yet-used and get +15%, while a separate later action this turn sees it used. Re-arms at
	-- OnTurnStart.
	if attacker and not attacker._armorSkirmishUsed then
		local skirmish = ArmorPassiveService.GetMoveSkirmishDamageBonus(attacker)
		if skirmish > 0 then
			finalDamage = math.max(0, math.round(finalDamage * (1 + skirmish)))
		end
	end

	-- FT-010 Vanguard Greaves: incoming DIRECT damage -15% while the window is active (armed at
	-- move-end when the defender ended its Move adjacent to an enemy; cleared at its next turn
	-- start via OnTurnStart). Pure read -> safe inside Resolve* (AI preview reflects it too).
	if defender._armorVanguardDrActive then
		local vg = ArmorPassiveService.GetMoveVanguardConfig(defender)
		if vg then
			finalDamage = math.max(0, math.round(finalDamage * (1 - vg.damageReduction)))
		end
	end

	-- Step 8: Guard and other final mitigation
	local hasGuardSkill = false
	if defender.statusInstances then
		for _, inst in ipairs(defender.statusInstances) do
			if inst.id == "Guard" then hasGuardSkill = true; break end
		end
	end
	local guardMitigatedAmount = 0
	local wasGuarding = false
	if hasGuardSkill then
		wasGuarding = true
		-- BD-006 Layered Lamellar: successive-hit DR (0 until OnGuardHitReceived accrues hits) adds
		-- into the Guard mitigation, still clamped to GUARD_CAP. 0 for units without the passive.
		local mitigation = GameConstants.GUARD_MITIGATION + (defender.guardBonus or 0)
			+ ArmorPassiveService.GetGuardLayeredBonus(defender)
			+ guardAuraBonus(defender)  -- SUP-011 Guardian Standard
		mitigation = math.min(mitigation, GameConstants.GUARD_CAP)
		local preGuard = finalDamage
		finalDamage = math.max(0, math.round(finalDamage * (1 - mitigation)))
		guardMitigatedAmount = math.max(0, preGuard - finalDamage)
	end
	-- BD-014 Guardian Mantle: apply any adjacent-ally shared Guard DR (multiplicative, after own
	-- guard; runs whether or not this unit is Guarding).
	do
		local gmShare = guardianMantleShare(defender)
		if gmShare > 0 then
			finalDamage = math.max(0, math.round(finalDamage * (1 - gmShare)))
		end
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
	-- An item-owned timed hit (isItemSource, user ruling 2026-10-27) stands on no tile of its
	-- own, so it gets no terrain occupy bonus.
	if not StatusService.HasStatus(attacker, "Flight") and not attacker.isItemSource then
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

	-- Attunement (weapon native, Crystal): +25% elemental damage dealt (skill path; element section).
	do
		local atBonus = WeaponPassiveService.GetAttunementBonus(attacker, skillElement)
		if atBonus > 0 then
			finalDamage = math.max(0, math.round(finalDamage * (1 + atBonus)))
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
	finalDamage = math.max(0, math.round(finalDamage * weatherElementMult(skillElement, defender)))

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
		minRiderDamage = skillDef.minRiderDamage,  -- DAM-017 Venom Repeater (2026-10-27)
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
		guardMitigatedAmount = guardMitigatedAmount,  -- armor Guard on-hit reactions (2026-10-24)
		wasGuarding    = wasGuarding,
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
	local healingOutput = (caster.gearDerived and caster.gearDerived.healingOutput) or 1
	local finalHeal = math.max(1, math.round(healPower * healEfficiency
		* (skillDef.potencyBonusMult or 1) * healingOutput)) -- Mana Surge +10% potency (2026-10-07); x gear Healing Output (2026-10-23)

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
	local potency = (GameConstants.CalcSkillPotency(int) + (caster.gearDerived and caster.gearDerived.skillPotency or 0)) * (skillDef.potencyBonusMult or 1) -- Mana Surge
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
	if granted ~= false then
		-- Shield visual (2026-10-23): surface the grant to the client (pool appears).
		BattleVisualBroadcaster.ShieldChanged(target, outcome.shieldHp, "grant")
	end
	return (granted ~= false) and outcome.shieldHp or 0
end

--------------------------------------------------
-- PUBLIC: APPLY OUTCOME (damage or healing)
-- attacker (optional): unit table of the source, used for Confuse backlash.
-- Callers that have the attacker unit should pass it.
--------------------------------------------------

-- REACTION WINDOW (DB TRG-004, Locked): CommandService opens a window while one action resolves
-- and records every unit that action hits for direct damage > 0, measured AFTER defense/Guard and
-- BEFORE shields ("Shield-soaked damage counts"). Counter hits (isCounter) and passive follow-ups
-- (isFollowUp) are never recorded. nil = no window open (AI preview never calls ApplyOutcome).
local _hitRecorder = nil
function CombatResolver.SetHitRecorder(fn)
	_hitRecorder = fn
end
function CombatResolver.GetHitRecorder()
	return _hitRecorder
end

function CombatResolver.ApplyOutcome(outcome, target, attacker)
	if outcome.type == "Healing" then
		local healAmt = outcome.finalHealing
		-- Darkened Ground augment (2026-10-25): a unit standing on Darkened Ground receives
		-- reduced healing. Applied here at the skill-heal chokepoint (the primary heal path);
		-- regen/HoT ticks are a separate path and not covered by this hook (flagged).
		if _tileEffectService and _tileEffectService.GetHealingMultiplier and target.tileX then
			healAmt = math.round(healAmt * _tileEffectService.GetHealingMultiplier(target.tileX, target.tileY))
		end
		local actual = UnitSchema_ApplyHealing(healAmt, target)
		print(string.format(
			"[CombatResolver] %s healed for %d | HP: %d/%d",
			target.name, actual, target.currentHp, target.maxHp
		))
		return actual, nil
	end

	-- Damage outcome
	assert(outcome.type == "Damage", "ApplyOutcome: unsupported outcome type.")

	-- Countermeasure Turret block (2026-10-27): the blocked hit deals nothing.
	if tryIntercept(outcome, target, attacker) then
		outcome.finalDamage = 0
		outcome.intercepted = true
		return 0, nil
	end
	target._blockedRes = nil  -- this hit landed

	-- Augment damage-taken reduction (2026-10-25): Fortify on Kill (_fortifyMult, persists a
	-- round) and Retaliation Guard (_retaliationGuard, next incoming hit only). Applied HERE in
	-- ApplyOutcome (the real-hit chokepoint, never the AI preview path), and Retaliation is
	-- consumed on this hit. Both flags cleared at the holder's EndTurn.
	if target._fortifyMult and target._fortifyMult ~= 1 then
		outcome.finalDamage = math.max(0, math.round((outcome.finalDamage or 0) * target._fortifyMult))
	end
	if target._retaliationGuard and target._retaliationGuard ~= 1 then
		outcome.finalDamage = math.max(0, math.round((outcome.finalDamage or 0) * target._retaliationGuard))
		target._retaliationGuard = nil
	end

	-- Pre-hit HP captured for augment overkill math (2026-10-24). Overkill = the portion
	-- of the uncapped skill damage that exceeded the target's remaining HP.
	local _preHitHp = target.currentHp or 0

	-- BD-009 Reprisal Coat CONSUME (2026-10-24): a committed Basic Attack / damage Skill by the
	-- attacker spends its stored reprisal damage (flat), added to this hit, then cleared. Done
	-- HERE in ApplyOutcome (real resolution only) -- NOT in ResolveBasicAttack/ResolveSkill, which
	-- AI scoring/preview also call (that would drain the store without attacking). Consumed ONCE
	-- per action: the first ApplyOutcome of a multi-target attack gets it, the rest see 0 (store
	-- already cleared). Carries across turns, no cap (user ruling).
	if attacker and attacker ~= target then
		local _reprisal = ArmorPassiveService.ConsumeReprisalDamage(attacker)
		if _reprisal and _reprisal > 0 then
			outcome.finalDamage = (outcome.finalDamage or 0) + _reprisal
			print(string.format("[CombatResolver] Reprisal Coat: %s adds %d stored damage", attacker.name, _reprisal))
		end
	end

	-- BD-017 Ablative Shell (armor, 2026-10-24): while Guarding, refresh a Shield = 15% Max HP
	-- BEFORE each incoming hit resolves (user ruling: fresh shield per hit). Uses the shield
	-- subsystem; ApplyShield's replace-semantics make it "fresh" each hit; the hit below soaks
	-- against it. FLAGGED: occupies the single shield pool (replaces any other active shield);
	-- an unspent remainder lingers (~short) until the next hit refreshes it or it decays.
	if outcome.wasGuarding and attacker ~= target then
		local shieldPct = ArmorPassiveService.GetGuardShieldPercent(target)
		if shieldPct > 0 then
			local shieldHp = math.max(0, math.round((target.maxHp or 0) * shieldPct))
			if shieldHp > 0 then
				StatusService.ApplyShield(target, shieldHp, 1000, target.id)
			end
		end
	end

	if _hitRecorder and not outcome.isCounter and not outcome.isFollowUp then
		_hitRecorder(target, attacker, outcome.finalDamage or 0)
	end

	local actual, shieldBroke, _shieldAbsorbed, _shieldMaxAtBreak, retributionDamage =
		UnitSchema_ApplyDamage(outcome.finalDamage, target)

	-- Shield visual (2026-10-23): surface absorb/break to the client. _shieldAbsorbed
	-- is the damage the pool soaked this hit; shieldBroke = pool emptied on this hit.
	if (_shieldAbsorbed or 0) > 0 then
		BattleVisualBroadcaster.ShieldChanged(target, -_shieldAbsorbed, shieldBroke and "break" or "absorb")
	end

	-- RETRIBUTION SHELL on-break (shield subsystem — 2026-10-05). The hit that
	-- EMPTIES a Retribution Shell retaliates against the breaker. retributionDamage
	-- is the snapshot the shield carried (round(Shield Max HP x 0.50), stamped at
	-- cast by StatusService.ApplyShield and returned here through ApplyDamage ->
	-- OnShieldAbsorb). This CONNECTS the authored skill to the EXISTING on-break
	-- hooks (StatusService owns the instance + the snapshot; ApplyOutcome, which
	-- knows the attacker, deals the retaliation). Applied with UnitSchema_ApplyDamage
	-- DIRECTLY (never through ApplyOutcome) so it cannot re-trigger reflects /
	-- lifesteal / counters / another shield break — TRG-010 pattern, like Reptilian
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

	-- Evasion Surge (reworked 2026-10-26): a direct-damage hit resolved against this target consumes
	-- ONE evasion charge (the +0.30 evasiveness it granted applied to THIS hit in calcHitQuality).
	-- Consumed only here in the real apply path (never in ResolveSkill AI preview). DoT / detonation
	-- use raw ApplyDamage (not ApplyOutcome) so they correctly do NOT consume a charge.
	if (target._evasionSurgeStacks or 0) > 0 then
		target._evasionSurgeStacks = target._evasionSurgeStacks - 1
	end

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
		-- Perks & Flaws Phobia (2026-10-23): a unit with the matching Phobia flaw "cannot
		-- inflict" that status with attacks -> skip the rider. Attacker is the source unit.
		local phobiaBlocked = attacker ~= nil
			and TraitEffectService.HasStatusPhobia(attacker, outcome.appliesStatus)
		if not phobiaBlocked then
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
	end

	-- Multi-status skills: apply each status in outcome.appliesStatuses (e.g. Wither
	-- lands Weakened + Cursed on the enemy damage path). Same gate as the singular
	-- appliesStatus above so a fully-mitigated damaging hit does not apply riders,
	-- while pure-status skills (applyStatusUnconditional) always land. Burn is not
	-- routed here (it uses the singular appliesStatus + fireDmg path).
	if outcome.appliesStatuses and (actual > 0 or outcome.applyStatusUnconditional) and target.isAlive then
		for _, sid in ipairs(outcome.appliesStatuses) do
			-- Perks & Flaws Phobia (2026-10-23): skip a status this attacker cannot inflict.
			local phobiaBlocked = attacker ~= nil and TraitEffectService.HasStatusPhobia(attacker, sid)
			if not phobiaBlocked then
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
	end

	-- Phase 3: Element→status triggers (Fire→Burn, Water→Wet, Ice→Frozen, Poison→Poison)
	-- Only fires if actual damage > 0 and target alive.
	-- Skips if the same status was already applied by appliesStatus above.
	if outcome.element and actual > 0 and target.isAlive
		and (outcome.minRiderDamage == nil or actual >= outcome.minRiderDamage) then
		applyElementStatusTriggers(outcome.sourceUnitId or "unknown", target, outcome.element, actual, statusApplied, attacker)
	end

	-- ===== Perks & Flaws: Status Specialist / Phobia (Bleed/Burn/Poison/Venom) =====
	-- Fires on basic attacks AND damaging skills (user ruling 2026-10-23): this runs in the
	-- shared ApplyOutcome damage path, so both routes are covered. Requires a landed hit.
	-- Specialist (perk): if the target HAS the status, trigger an early DOT tick now (status
	-- keeps running); if the target LACKS it, inflict one standard stack (Bleed/Poison/Venom
	-- only — Burn's DB text has no "inflict if absent" clause). Phobia is handled separately
	-- as a block on this unit's status application (see rider gates above). Early-tick damage
	-- is applied DIRECTLY via UnitSchema_ApplyDamage (TRG-010: cannot re-enter reactions).
	if attacker and actual > 0 and target.isAlive then
		for _, sid in ipairs({ "Bleed", "Poison", "Venom", "Burn" }) do
			if TraitEffectService.HasStatusSpecialist(attacker, sid)
				and not TraitEffectService.HasStatusPhobia(attacker, sid) then
				if StatusService.HasStatus(target, sid) then
					-- TRIGGER: deal the status's current DOT once now; leave it running.
					local dot = StatusService.GetCurrentDotDamage(target, sid)
					if dot > 0 then
						local dealt = UnitSchema_ApplyDamage(dot, target)
						print(string.format(
							"[CombatResolver] %s Specialist: %s triggers %s on %s for %d%s",
							sid, attacker.name, sid, target.name, dealt,
							target.isAlive and "" or " | DEFEATED"
						))
						if not target.isAlive then
							target._killedBy = target._killedBy or (attacker.id)
							RacePassiveService.OnUnitKO(target)
						end
						if BattleVisualBroadcaster.DotDamage then
							BattleVisualBroadcaster.DotDamage(target, sid, dealt)
						end
					end
				elseif sid ~= "Burn" and target.isAlive then
					-- INFLICT: target lacks the status -> apply one standard stack.
					StatusService.ApplyStatus(target, sid, attacker.id)
					print(string.format(
						"[CombatResolver] %s Specialist: %s inflicts %s on %s",
						sid, attacker.name, sid, target.name
					))
				end
			end
		end
	end

	-- ===== Perks & Flaws: Buff manipulation on hit (Purifier P-107 / Buff-Blind F-107) =====
	-- Fires on basic attacks AND damaging skills (shared ApplyOutcome path), on a landed hit.
	-- Purifier: dispel one random active buff from the target. Buff-Blind: grant the target one
	-- random buff from the curated pool instead. Mutually independent (a unit has at most one).
	if attacker and actual > 0 and target.isAlive then
		if TraitEffectService.HasPurifier(attacker) then
			local removed = StatusService.RemoveRandomBuff(target)
			if removed then
				print(string.format("[CombatResolver] Purifier: %s dispels %s from %s", attacker.name, removed, target.name))
				if BattleVisualBroadcaster.UnitStateChanged then
					BattleVisualBroadcaster.UnitStateChanged(target)
				end
			end
		end
		if TraitEffectService.HasBuffBlind(attacker) then
			local pool = TraitEffectService.BUFF_BLIND_POOL
			if pool and #pool > 0 then
				local sid = pool[math.random(1, #pool)]
				StatusService.ApplyStatus(target, sid, attacker.id)
				print(string.format("[CombatResolver] Buff-Blind: %s grants %s to %s", attacker.name, sid, target.name))
				if BattleVisualBroadcaster.UnitStateChanged then
					BattleVisualBroadcaster.UnitStateChanged(target)
				end
			end
		end
	end

	-- PHASE 3a — WEAPON/SKILL ELEMENT → TERRAIN BRIDGE. The element that hit the
	-- target also touches the TILE the target stands on (tile-keyed reaction, rule
	-- 140): a Fire hit on a unit standing on Grassland ignites the grass, etc. Routed
	-- through the shared Phase 0 doorway, which handles effect reaction / deferred or
	-- instant terrain transform / secondary. Runs on any elemental hit (Physical is a
	-- no-op inside the doorway). Independent of whether the unit survived.
	if outcome.element and _tileEffectService and _tileEffectService.ResolveElementOnTile
		and target.tileX and target.tileY then
		_tileEffectService.ResolveElementOnTile(
			target.tileX, target.tileY, outcome.element,
			outcome.sourceUnitId or (attacker and attacker.id) or "unknown", nil
		)
	end

	-- PHASE 2 — buffer an Electric hit for the end-of-action shock reaction. Uses the
	-- FINAL post-mitigation damage (actual). The shock itself resolves in
	-- CommandService via FlushElectricShock once all targets are hit.
	if outcome.element == "Electric" and actual > 0 then
		bufferElectricHit(target, actual, attacker)
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
	-- Weapon passive Drain (Group 1, PAS-040): heal attacker a fraction of final
	-- damage dealt. Direct heal (TRG-010) so it cannot re-trigger generated effects.
	if attacker and actual > 0 and attacker.isAlive and outcome.weaponDrainFrac and outcome.weaponDrainFrac > 0 then
		-- No 1-HP floor (user ruling 2026-10-23): heal the literal rounded 5% of final
		-- damage, which rounds to 0 for hits under 10 damage.
		local drainHeal = math.round(actual * outcome.weaponDrainFrac)
		if drainHeal > 0 then
			UnitSchema_ApplyHealing(drainHeal, attacker)
		end
	end

	-- Fortify (weapon native, Spear): on a landed hit the ATTACKER accrues +20% of its Weapon Defense
	-- as flat Defense (round). STACKS per hit within the turn (each ApplyOutcome hit adds once -- a
	-- multi-target swing stacks); RESET at the wearer's next turn via WeaponPassiveService.OnTurnStart.
	-- Fires on basic AND damaging skills (Hybrid) since both resolve here. Real-resolution only
	-- (ApplyOutcome is never called in AI preview). Matches Drain's gating (actual>0, attacker alive).
	if attacker and attacker ~= target and actual > 0 and attacker.isAlive then
		local fortAdd = WeaponPassiveService.GetFortifyFlatDefensePerHit(attacker)
		if fortAdd > 0 then
			attacker._fortifyFlatDefense = (attacker._fortifyFlatDefense or 0) + fortAdd
			print(string.format("[CombatResolver] Fortify: %s gains +%d flat Defense on hit (total +%d this turn)",
				attacker.name, fortAdd, attacker._fortifyFlatDefense))
		end
	end

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

	-- Ally-KO reaction buffer (Perks & Flaws 2026-10-23): if this hit left the target KO'd,
	-- record it once so FlushAllyKoReactions (CommandService, end of action) can apply
	-- Hemophage / Sluggish Finisher to nearby same-side allies. Combat deaths only.
	if target and not target.isAlive and not target._allyKoBuffered then
		target._allyKoBuffered = true
		table.insert(_allyKoBuffer, target)
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

	-- Augment effects (Slice 4 — AugmentEffectService). skillDef + overkill context added
	-- 2026-10-24 so kill-trigger augments (Kill-Momentum-MP, Overkill-Splash) have the data
	-- they need. skillDef resolved from the shared registry; nil for doctrine-only ids (those
	-- augments simply no-op, guarded below).
	if attacker and outcome.skillId and actual > 0 then
		local augIds = AugmentEffectService.GetAugmentsForSkill(attacker, outcome.skillId)
		if #augIds > 0 then
			local _augSkillDef = GameConstants.SKILLS and GameConstants.SKILLS[outcome.skillId] or nil
			AugmentEffectService.OnDamageResolved(attacker, target, actual, _augSkillDef, augIds, nil, _shieldAbsorbed)
			-- OnKill: if target died. ctx carries overkill (uncapped damage beyond lethal)
			-- and the original hit damage so splash/MP-refund augments can compute.
			if not target.isAlive then
				local _overkill = math.max(0, (outcome.finalDamage or 0) - _preHitHp)
				AugmentEffectService.OnKill(attacker, target, _augSkillDef, augIds, {
					overkill = _overkill,
					hitDamage = outcome.finalDamage or 0,
				})
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

	-- REPTILIAN — Spiked Hide (2026-10-02; race renamed from Lizardmen 2026-10-09): a MELEE hit from one of the 8 adjacent
	-- tiles reflects damage = the Reptilian's level onto the attacker. Not on ranged
	-- or AOE hits. Applied with UnitSchema_ApplyDamage directly (never through
	-- ApplyOutcome), so a reflect cannot re-trigger reflects / lifesteal / other
	-- reaction hooks -- no loop (TRG-010 pattern). outcome.isReflect guards re-entry.
	if attacker and actual > 0 and attacker ~= target and attacker.isAlive
		and not outcome.isReflect and isMeleeHit(outcome, attacker, target) then
		local reflect = RacePassiveService.GetMeleeReflectDamage(target)
		if reflect > 0 then
			local reflected = UnitSchema_ApplyDamage(reflect, attacker)
			print(string.format(
				"[CombatResolver] Reptilian Spiked Hide: %s reflects %d to %s | HP: %d/%d%s",
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

	-- ARMOR GUARD on-hit reactions (2026-10-24): fire only when the defender was Guarding this
	-- hit (outcome.wasGuarding) and it was a real incoming hit (not a reflect/counter re-entry).
	-- All damage is applied DIRECTLY (TRG-010) so none can re-trigger another reaction.
	if attacker and target and outcome.wasGuarding and not outcome.isReflect and not outcome.isCounter then
		local _aps = (require :: any)(script.Parent.ArmorPassiveService)
		-- BD-006 Layered Lamellar: count this hit so successive-hit DR grows next hit.
		_aps.OnGuardHitReceived(target)
		-- BD-009 Reprisal Coat: store 40% of the damage Guard just mitigated (carries across
		-- turns, no cap; consumed by the unit's next Basic Attack / damage Skill).
		if outcome.guardMitigatedAmount and outcome.guardMitigatedAmount > 0 then
			_aps.OnGuardDamageMitigated(target, outcome.guardMitigatedAmount)
		end
		if actual > 0 and attacker.isAlive and attacker ~= target then
			-- BD-007 Mirror Mail: reflect 30% of damage taken back to a PROJECTILE attacker.
			local refl = _aps.GetGuardProjectileReflect(target)
			if refl and (attacker.weaponProjectileType ~= nil) then
				local dmg = math.max(0, math.round(actual * refl.reflectPercent))
				if dmg > 0 then
					local dealt = UnitSchema_ApplyDamage(dmg, attacker)
					print(string.format("[CombatResolver] Mirror Mail: %s reflects %d to %s%s",
						target.name, dealt, attacker.name, attacker.isAlive and "" or " | DEFEATED"))
					if not attacker.isAlive then attacker._killedBy = target.id; RacePassiveService.OnUnitKO(attacker) end
					if BattleVisualBroadcaster.UnitStateChanged then BattleVisualBroadcaster.UnitStateChanged(attacker) end
				end
			end
			-- BD-016 Spiked Plate: attacker takes 20% of the damage they dealt as retaliation.
			local retal = _aps.GetGuardRetaliationPercent(target)
			if retal > 0 and attacker.isAlive then
				local dmg = math.max(0, math.round(actual * retal))
				if dmg > 0 then
					local dealt = UnitSchema_ApplyDamage(dmg, attacker)
					print(string.format("[CombatResolver] Spiked Plate: %s retaliates %d to %s%s",
						target.name, dealt, attacker.name, attacker.isAlive and "" or " | DEFEATED"))
					if not attacker.isAlive then attacker._killedBy = target.id; RacePassiveService.OnUnitKO(attacker) end
					if BattleVisualBroadcaster.UnitStateChanged then BattleVisualBroadcaster.UnitStateChanged(attacker) end
				end
			end
		end
		-- Deflect (weapon native, Buckler): reflect 20% of the damage Guard just MITIGATED back to
		-- the attacker (DB "On Guard, reflect 20% of mitigated damage"). Keyed on mitigated amount,
		-- so it fires even on a fully-absorbed hit. Direct ApplyDamage (TRG-010, no reaction re-entry).
		if attacker.isAlive and attacker ~= target and (outcome.guardMitigatedAmount or 0) > 0 then
			local deflectPct = WeaponPassiveService.GetGuardDeflectPercent(target)
			if deflectPct > 0 then
				local dmg = math.max(0, math.round(outcome.guardMitigatedAmount * deflectPct))
				if dmg > 0 then
					local dealt = UnitSchema_ApplyDamage(dmg, attacker)
					print(string.format("[CombatResolver] Deflect: %s reflects %d to %s%s",
						target.name, dealt, attacker.name, attacker.isAlive and "" or " | DEFEATED"))
					if not attacker.isAlive then attacker._killedBy = target.id; RacePassiveService.OnUnitKO(attacker) end
					if BattleVisualBroadcaster.UnitStateChanged then BattleVisualBroadcaster.UnitStateChanged(attacker) end
				end
			end
		end
	end

	-- BD-005 Reactive Cuirass (2026-10-24): the FIRST hit a unit takes each turn triggers a free
	-- auto-Guard (no AP) covering LATER hits this turn; the triggering hit itself lands full (Guard
	-- is applied AFTER this hit resolved). Once per turn via _armorAutoGuardUsed (reset at turn start).
	-- Skipped if already Guarding. guardBonus mirrors the Guard command's Race+Trait+Armor fold.
	if target and target.isAlive and actual > 0 and not outcome.isReflect and not outcome.isCounter then
		if ArmorPassiveService.CanAutoGuard(target) then
			local alreadyGuard = false
			if target.statusInstances then
				for _, inst in ipairs(target.statusInstances) do
					if inst.id == "Guard" then alreadyGuard = true; break end
				end
			end
			if not alreadyGuard then
				StatusService.ApplyStatus(target, "Guard", target.id)
				target.guardBonus = RacePassiveService.GetGuardMitigationBonus(target)
					+ TraitEffectService.GetGuardMitigationBonus(target)
					+ ArmorPassiveService.GetGuardMitigationBonus(target)
					+ WeaponPassiveService.GetGuardMitigationBonus(target)
				target._armorAutoGuardUsed = true
				print(string.format("[CombatResolver] Reactive Cuirass: %s auto-Guards after first hit this turn", target.name))
				if BattleVisualBroadcaster.UnitStateChanged then BattleVisualBroadcaster.UnitStateChanged(target) end
			end
		end
	end

	-- FROC — Toxic Skin (DB races row 'Froc'): when this defender is attacked and the
	-- hit lands, inflict Poison on the attacker -- UNLESS the attack element is Fire,
	-- Ice, or Electric. Mirrors the Retaliator status-to-attacker idiom; gated against
	-- reaction re-entry (not reflect / not counter) so it cannot loop (TRG-010 pattern).
	if attacker and actual > 0 and attacker ~= target and attacker.isAlive
		and not outcome.isReflect and not outcome.isCounter
		and RacePassiveService.GetToxicSkinStatus(target) then
		local atkElement = outcome.element or attacker.weaponElement or "Physical"
		if atkElement ~= "Fire" and atkElement ~= "Ice" and atkElement ~= "Electric" then
			StatusService.ApplyStatus(attacker, "Poison", target.id)
			print(string.format(
				"[CombatResolver] Froc Toxic Skin: %s poisons %s (element=%s)",
				target.name, attacker.name, atkElement
			))
		end
	end

	-- AC Accessory "recharge 1 item charge" (2026-10-26): when the WEARER (defender) takes a real
	-- hit, restore 1 use charge to ONE depleted equipped consumable (currentCharges < maxCharges).
	-- Fires every time the wearer is hit (user default 2026-10-26; flagged for playtest). Keyed on
	-- the TARGET's Accessory passive; nil for everyone else. Scope: direct combat hits resolved here
	-- (DoT / push / trap damage go through other paths and do NOT trigger it -- noted).
	if target and actual > 0 and target.isAlive and target.consumableSlots then
		local rechargeCfg = ArmorPassiveService.GetItemRechargeOnDamageConfig(target)
		if rechargeCfg then
			for _, slot in pairs(target.consumableSlots) do
				if slot and slot.consumableId and (slot.currentCharges or 0) < (slot.maxCharges or 0) then
					slot.currentCharges = (slot.currentCharges or 0) + (rechargeCfg.chargeRestore or 1)
					if slot.currentCharges > slot.maxCharges then slot.currentCharges = slot.maxCharges end
					print(string.format("[CombatResolver] Item Recharge: %s restores 1 charge to %s on being hit",
						target.name, tostring(slot.consumableId)))
					break  -- one charge to one slot per hit
				end
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