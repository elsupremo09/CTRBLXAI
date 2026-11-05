--------------------------------------------------------------------
-- ObjectiveService.lua  (Phase 0 foundation — in-battle optional objectives)
--------------------------------------------------------------------
-- WHAT THIS IS (plain English):
--   The single place that tracks a battle's OPTIONAL objectives. An objective
--   lives and dies inside ONE battle: it is rolled at battle start, counted as
--   the fight happens, checked at battle end, and erased if its condition was
--   not met. Failure never costs the player anything (locked rule,
--   unit_progression id 63 / id 68).
--
-- WHAT IT IS NOT (yet):
--   This foundation does NOT yet read "how a unit died" (the kill-cause tag).
--   The 6 objectives that need that (One-punch, Nuker, Siege, Elite Slayer,
--   Pusher, Power of Nature) are DEFINED here but marked needsKillCause=true
--   and are left out of the roll until Phase 2 wires the kill-cause choke-point.
--   Everything else works with simple event counters + end-of-battle checks.
--
-- ROUND = 1000 CT (user-locked 2026-10-24). round(state) = floor(ct / 1000).
--   Speed clear: win before 4000 CT (Hard 3000). Elite Slayer: elite dead
--   before 3000 CT (Hard 2000).
--
-- REWARDS (user-locked 2026-10-24): gear / skills / augments (ready now via
--   RewardService); gold + materials are Phase 3 (grant paths not built yet).
--   Consumables and doctrines are EXCLUDED from objective rewards.
--
-- INTEGRATION (wired incrementally in Phase 1, not here):
--   BeginBattle(state, ctx)  -> rolls applicable objectives onto state
--   RecordEvent(state, kind, data)  -> bump a counter (chest opened, object
--                                      broken, charge used, tile reshaped, ...)
--   Evaluate(state, won)     -> returns { completed = {...}, rewards = {...} }
--                               called at battle end INSIDE the protected
--                               commit->save->announce order (BUG-013: never
--                               before rewards/save are committed).
--------------------------------------------------------------------

local ObjectiveService = {}

-- Difficulty modes
local NORMAL, HARD = "Normal", "Hard"

-- One round = 1000 CT.
local CT_PER_ROUND = 1000
local function roundOf(state)
	return math.floor((state and state.ct or 0) / CT_PER_ROUND)
end

--------------------------------------------------------------------
-- OBJECTIVE CATALOG
--------------------------------------------------------------------
-- Revive-potion checker (dependency injection, set by Main at init). Returns
-- true for a player unit that has a deliberately-targetable revive consumable
-- ("KO Ally" rule) equipped with charges. Kept as DI so ObjectiveService stays
-- a leaf module (zero requires -> no cycle); Main owns the ConsumableData lookup.
-- nil-safe: with no checker wired, hasRevivePotion stays false and Torture never
-- rolls (safe: never an impossible objective).
local _reviveChecker = nil
function ObjectiveService.SetRevivePotionChecker(fn)
	_reviveChecker = fn
end

-- Element-source checker (DI, set by Main). Returns true for a player unit that
-- can produce/apply an element to terrain — an element weapon OR an element-tagged
-- skill — i.e. a unit that can create a burning/hazard tile (Power of Nature) or
-- transform terrain (Terra Former). Gating on this prevents a purely-physical
-- party from being handed a terrain-element objective it cannot complete. Leaf-safe
-- DI; Main owns the weapon/skill element lookup (reuses CombatResolver element).
local _elementChecker = nil
function ObjectiveService.SetElementSourceChecker(fn)
	_elementChecker = fn
end

-- Disguise checker (DI, set by Main = ObjectEffectService.IsDisguised). A disguised
-- Mimic counts as a chest (project_rules 224). DI because ObjectEffectService
-- requires ObjectiveService (direct require would be circular, ARC DI pattern).
-- nil-safe: with no checker wired, Mimics are simply not counted.
local _disguiseChecker = nil
function ObjectiveService.SetDisguiseChecker(fn)
	_disguiseChecker = fn
end

-- Each entry:
--   id            stable key
--   name          player-facing label
--   needsKillCause true = deferred to Phase 2 (not rolled yet)
--   spawnable(ctx) -> bool : can this objective appear for this battle?
--                     ctx carries map/encounter facts (objects present,
--                     elite count, whether an NPC/dragon-utopia exists, etc.)
--   thresholds    { Normal = N, Hard = M }  (meaning depends on the objective)
--   evaluate(state, mode) -> bool : was it met? (reads counters / end-state)
--
-- Counters live on state.objectiveCounters (a plain number table). RecordEvent
-- bumps them; evaluate() reads them. End-state objectives (Strategist, Speed
-- clear, NPC survive) read state directly instead of a counter.
--------------------------------------------------------------------

local function counter(state, key)
	local c = state.objectiveCounters
	return (c and c[key]) or 0
end

local Catalog = {}

-- a. Strategist — player KO tolerance
Catalog["strategist"] = {
	id = "strategist", name = "Strategist", needsKillCause = false,
	thresholds = { [NORMAL] = 1, [HARD] = 0 },
	spawnable = function() return true end,  -- always available
	evaluate = function(state, mode)
		return counter(state, "playerKOs") <= Catalog["strategist"].thresholds[mode]
	end,
}

-- d. Speed clear — win before a round deadline (no elite present)
Catalog["speed_clear"] = {
	id = "speed_clear", name = "Speed Clear", needsKillCause = false,
	thresholds = { [NORMAL] = 4, [HARD] = 3 },  -- rounds (1000 CT each)
	spawnable = function(ctx) return not (ctx and ctx.hasElite) end,
	evaluate = function(state, mode)
		-- met only on victory (caller passes won); win must land before the
		-- deadline round. roundOf is 0-based; "within 4 rounds" = ct < 4000.
		return roundOf(state) < Catalog["speed_clear"].thresholds[mode]
	end,
}

-- h. Treasure fever — open chests (hidden treasures count as opens, but a
-- hidden treasure cannot be the spawn trigger: need >= threshold real chests).
Catalog["treasure_fever"] = {
	id = "treasure_fever", name = "Treasure Fever", needsKillCause = false,
	thresholds = { [NORMAL] = 1, [HARD] = 2 },
	spawnable = function(ctx) return (ctx and ctx.chestCount or 0) >= 2 end, -- enough to allow Hard
	evaluate = function(state, mode)
		return counter(state, "chestsOpened") >= Catalog["treasure_fever"].thresholds[mode]
	end,
}

-- l. Glutton — total consumable charges used
Catalog["glutton"] = {
	id = "glutton", name = "Glutton", needsKillCause = false,
	thresholds = { [NORMAL] = 7, [HARD] = 10 },
	spawnable = function() return true end,
	evaluate = function(state, mode)
		return counter(state, "chargesUsed") >= Catalog["glutton"].thresholds[mode]
	end,
}

-- i. Demolition — break map objects / obstacles
Catalog["demolition"] = {
	id = "demolition", name = "Demolition", needsKillCause = false,
	thresholds = { [NORMAL] = 2, [HARD] = 3 },
	spawnable = function(ctx) return (ctx and ctx.breakableCount or 0) >= 3 end,
	evaluate = function(state, mode)
		return counter(state, "objectsBroken") >= Catalog["demolition"].thresholds[mode]
	end,
}

-- o. Terrain shaper — player-caused elevation changes (exclude quake / non-player)
Catalog["terrain_shaper"] = {
	id = "terrain_shaper", name = "Terrain Shaper", needsKillCause = false,
	thresholds = { [NORMAL] = 5, [HARD] = 10 },
	-- Needs a player-usable elevation-change source on the map: an explosive object
	-- (Bomb Barrel / Land Mine), an Oil Sluice (fire-on-oil explosion), or a Stone
	-- Pillar (Interact fall). Without one, 5/10 elevation changes is impossible.
	spawnable = function(ctx) return (ctx and ctx.hasElevationSource) == true end,
	evaluate = function(state, mode)
		return counter(state, "elevationTilesChanged") >= Catalog["terrain_shaper"].thresholds[mode]
	end,
}

-- p. Terra former — player-caused terrain transformations
Catalog["terra_former"] = {
	id = "terra_former", name = "Terra Former", needsKillCause = false,
	thresholds = { [NORMAL] = 5, [HARD] = 10 },
	-- Needs an element source (element weapon or element-tagged skill) to transform
	-- terrain; a purely-physical party cannot transform tiles.
	spawnable = function(ctx) return (ctx and ctx.hasElementSource) == true end,
	evaluate = function(state, mode)
		return counter(state, "terrainTilesTransformed") >= Catalog["terra_former"].thresholds[mode]
	end,
}

-- q. Dragon slayer — kill all dragons spawned by a Dragon Utopia (Hard only)
Catalog["dragon_slayer"] = {
	id = "dragon_slayer", name = "Dragon Slayer", needsKillCause = false,
	thresholds = { [HARD] = 1 },  -- Hard-only per spec
	spawnable = function(ctx) return (ctx and ctx.hasDragonUtopia) == true end,
	evaluate = function(state)
		-- met when a Dragon Utopia was triggered AND no dragon from it is alive.
		return counter(state, "dragonUtopiaTriggered") > 0
			and counter(state, "dragonsAlive") <= 0
	end,
}

-- j. Recruit — recruit enemies via Interact (recruit need not survive)
Catalog["recruit"] = {
	id = "recruit", name = "Recruit", needsKillCause = false,
	thresholds = { [NORMAL] = 1, [HARD] = 2 },
	spawnable = function() return true end,  -- any enemy can be weakened + recruited
	evaluate = function(state, mode)
		return counter(state, "enemiesRecruited") >= Catalog["recruit"].thresholds[mode]
	end,
}

-- f. NPC spawned — a spawned NPC (enemyPriorityTarget) must survive the battle
Catalog["npc_survive"] = {
	id = "npc_survive", name = "Protect the NPC", needsKillCause = false,
	thresholds = { [NORMAL] = 0 },  -- single-mode: survive = met
	spawnable = function(ctx) return (ctx and ctx.hasPriorityNpc) == true end,
	evaluate = function(state)
		return counter(state, "npcDied") <= 0
	end,
}

-- k. Torture — revive KO'd enemies (revived enemy returns AS an enemy)
Catalog["torture"] = {
	id = "torture", name = "Torture", needsKillCause = false,
	thresholds = { [NORMAL] = 1, [HARD] = 2 },
	spawnable = function(ctx) return (ctx and ctx.hasRevivePotion) == true end,  -- needs a targetable revive potion equipped
	evaluate = function(state, mode)
		return counter(state, "enemiesRevived") >= Catalog["torture"].thresholds[mode]
	end,
}

--------------------------------------------------------------------
-- DEFERRED (Phase 2 — need the kill-cause tag). Defined for completeness;
-- NOT rolled until the kill-cause choke-point exists.
--------------------------------------------------------------------
-- One-Punch / Nuker (Phase 3) — kill-cause stamped centrally. One-Punch counts
-- single-attack KOs of a FULL-HP enemy (UnitSchema stamps _killedFromFull on a
-- lethal-from-full normal hit); Nuker counts the MAX enemies KO'd by one action
-- (per-action death-sweep tally). spawnable gates on the HARD requirement, so if
-- it rolls, BOTH modes are achievable — never a rollable-but-impossible objective.
Catalog["one_punch"] = {
	id = "one_punch", name = "One-Punch", needsKillCause = false,
	thresholds = { [NORMAL] = 1, [HARD] = 2 },
	spawnable = function(ctx) return (ctx and ctx.enemyCount or 0) >= 2 end,
	evaluate = function(state, mode)
		return counter(state, "oneShotFullKOs") >= Catalog["one_punch"].thresholds[mode]
	end,
}
Catalog["nuker"] = {
	id = "nuker", name = "Nuker", needsKillCause = false,
	thresholds = { [NORMAL] = 2, [HARD] = 3 },
	spawnable = function(ctx) return (ctx and ctx.enemyCount or 0) >= 3 end,
	evaluate = function(state, mode)
		return counter(state, "maxKOsInOneAction") >= Catalog["nuker"].thresholds[mode]
	end,
}
-- Siege Operator / Pusher / Elite Slayer: enabled in Phase 2. Their kill cause
-- is stamped centrally (UnitSchema.ApplyDamage for push; the siege site) and the
-- death-sweep (ObjectEffectService.ProcessDeaths -> OnUnitKilled) counts them.
Catalog["siege"] = {
	id = "siege", name = "Siege Operator", needsKillCause = false,
	thresholds = { [NORMAL] = 1, [HARD] = 2 },
	spawnable = function(ctx) return (ctx and ctx.hasSiege) == true end,
	evaluate = function(state, mode)
		return counter(state, "siegeKOs") >= Catalog["siege"].thresholds[mode]
	end,
}
Catalog["pusher"] = {
	id = "pusher", name = "Pusher", needsKillCause = false,
	thresholds = { [NORMAL] = 1, [HARD] = 2 },
	spawnable = function() return true end,
	evaluate = function(state, mode)
		return counter(state, "pushKOs") >= Catalog["pusher"].thresholds[mode]
	end,
}
Catalog["elite_slayer"] = {
	id = "elite_slayer", name = "Elite Slayer", needsKillCause = false,
	thresholds = { [NORMAL] = 3, [HARD] = 2 },  -- rounds (1000 CT each)
	spawnable = function(ctx) return (ctx and ctx.eliteCount or 0) == 1 end,
	evaluate = function(state, mode)
		local r = counter(state, "eliteSlainRound1")  -- 1-based; 0 = not slain
		return r >= 1 and r <= Catalog["elite_slayer"].thresholds[mode]
	end,
}
-- n. Power of Nature — KO enemies via terrain effects (burning tiles, lava/molten,
-- collapse). Kill-cause "terrain" is stamped at the terrain-damage death sites in
-- TileEffectService; OnUnitKilled routes an enemy terrain-death to terrainKOs.
-- Gated on the player having an element source (to create burning/hazard tiles).
Catalog["power_nature"] = {
	id = "power_nature", name = "Power of Nature", needsKillCause = false,
	thresholds = { [NORMAL] = 1, [HARD] = 2 },
	spawnable = function(ctx) return (ctx and ctx.hasElementSource) == true end,
	evaluate = function(state, mode)
		return counter(state, "terrainKOs") >= Catalog["power_nature"].thresholds[mode]
	end,
}

ObjectiveService.Catalog = Catalog

-- IMPLEMENTED allowlist: only these objectives are ROLLED today. An objective
-- is added here ONLY once its event counting is fully wired end-to-end, so a
-- rolled objective can never silently mis-evaluate (e.g. count 0 and falsely
-- pass). This list grows as each counter is wired; everything else stays
-- defined-but-dormant until then.
local IMPLEMENTED = {
	speed_clear = true,  -- reads battle CT at end; no per-event counter needed
	strategist  = true,  -- reads player KO count at end; no per-event counter needed
	treasure_fever = true, -- chestsOpened counter wired in ObjectEffectService
	glutton        = true, -- chargesUsed counter wired in CommandService (Item action)
	recruit        = true, -- enemiesRecruited counter wired in CommandService (recruit Interact)
	pusher       = true, -- pushKOs via UnitSchema.ApplyDamage("push") + death-sweep
	siege        = true, -- siegeKOs via siege stamp + death-sweep
	elite_slayer = true, -- eliteSlainRound1 via death-sweep (cause-agnostic)
	one_punch    = true, -- oneShotFullKOs via UnitSchema _killedFromFull stamp
	nuker        = true, -- maxKOsInOneAction via per-action death-sweep tally
	demolition   = true, -- objectsBroken via ApplyObjectHit break sites
	dragon_slayer= true, -- dragonUtopiaTriggered + dragonsAlive via doSummon + death-sweep
	npc_survive  = true, -- npcDied via death-sweep (priority NPC)
	torture      = true, -- enemiesRevived via revive-potion on KO'd enemy (CommandService Item action)
	power_nature = true, -- terrainKOs via "terrain" kill-cause stamp + death-sweep
	terrain_shaper = true, -- elevationTilesChanged via explosion-terrain owner-threaded count + Stone Pillar
	terra_former = true, -- terrainTilesTransformed via ResolveElementOnTile player-owner count
}

--------------------------------------------------------------------
-- REWARD CATEGORIES allowed for objectives (user-locked): gear/skills/augments.
-- Gold + materials are Phase 3. Consumables + doctrines EXCLUDED.
--------------------------------------------------------------------
ObjectiveService.REWARD_CATEGORIES = { "Equipment", "SkillCard", "AugmentCard" }

-- Build the spawn-gating context from live battle data. Used at battle start
-- (Main) and mid-battle (AddOne — Chaos Statue) so both gate objectives the
-- same way and never diverge.
function ObjectiveService.BuildContext(units, objects)
	local ctx = {
		hasElite = false, eliteCount = 0, chestCount = 0, hasSiege = false,
		hasDragonUtopia = false, breakableCount = 0, hasHazardTerrain = false,
		hasPriorityNpc = false, enemyCount = 0, hasRevivePotion = false,
		hasElementSource = false, hasElevationSource = false,
	}
	for _, u in ipairs(units or {}) do
		if u.side == "Enemy" and u.enemyType == "Elite" then
			ctx.eliteCount += 1
			ctx.hasElite = true
		end
		if u.side == "Enemy" and u.isAlive and not u.isSummon then ctx.enemyCount += 1 end
		if u.enemyPriorityTarget then ctx.hasPriorityNpc = true end
		-- Torture gate: a deployed player unit must be able to revive (a targetable
		-- revive consumable OR an equipped revive skill — the injected checker covers
		-- both), else reviving an enemy is impossible and Torture must not roll.
		if _reviveChecker and u.side == "Player" and _reviveChecker(u) then
			ctx.hasRevivePotion = true
		end
		-- Terrain-element gate (Power of Nature / Terra Former): a deployed player
		-- unit must have an element source to burn/transform terrain.
		if _elementChecker and u.side == "Player" and _elementChecker(u) then
			ctx.hasElementSource = true
		end
	end
	for _, o in ipairs(objects or {}) do
		local t = o.type
		-- Disguised Mimic counts as a chest (rules 224); waking it records chestsOpened.
		local disguisedMimic = t == "Mimic" and _disguiseChecker ~= nil and _disguiseChecker(o) == true
		if t == "Treasure Chest" or t == "Cursed Chest" or disguisedMimic then ctx.chestCount += 1
		elseif t == "Ballista" or t == "Catapult" or t == "Portable Ballista" then ctx.hasSiege = true
		elseif t == "Dragon Utopia" then ctx.hasDragonUtopia = true end
		if o.hp ~= nil then ctx.breakableCount += 1 end
		-- Terrain Shaper: map carries a player-usable elevation-change source.
		if t == "Bomb Barrel" or t == "Land Mine" or t == "Oil Sluice" or t == "Stone Pillar" then
			ctx.hasElevationSource = true
		end
	end
	return ctx
end

--------------------------------------------------------------------
-- RUNTIME API
--------------------------------------------------------------------

-- Bump a counter. Safe no-op if state has no objective block (e.g. objectives
-- disabled for this battle).
function ObjectiveService.RecordEvent(state, key, amount)
	if not state or not state.objectiveCounters then return end
	state.objectiveCounters[key] = (state.objectiveCounters[key] or 0) + (amount or 1)
end

-- Roll which objectives apply to this battle. ctx describes the encounter so
-- spawnable() predicates can gate (chests present, elite count, NPC, etc.).
-- `rng` is the battle's deterministic RNG (determinism rule, project_rules 108).
-- maxActive caps how many optional objectives a single battle carries.
function ObjectiveService.BeginBattle(state, ctx, rng, maxActive)
	state.objectiveCounters = {}
	state.activeObjectives = {}
	maxActive = maxActive or 2

	local pool = {}
	for _, def in pairs(Catalog) do
		if not def.needsKillCause and IMPLEMENTED[def.id] and def.spawnable(ctx or {}) then
			pool[#pool + 1] = def
		end
	end
	table.sort(pool, function(a, b) return a.id < b.id end) -- deterministic order

	-- ctx.forceObjective (2026-11-01, elite encounters): this objective is always one of the
	-- active ones when it is eligible ("Defeat the Elite within N rounds" in an elite encounter).
	local forced = ctx and ctx.forceObjective
	if forced then
		for i, def in ipairs(pool) do
			if def.id == forced then
				table.remove(pool, i)
				local mode = NORMAL
				if def.thresholds[HARD] ~= nil then
					mode = (rng and rng:NextNumber() < 0.35) and HARD or NORMAL
				end
				state.activeObjectives[#state.activeObjectives + 1] = { id = def.id, mode = mode }
				break
			end
		end
	end

	-- Deterministic pick of up to maxActive objectives; each rolls a mode.
	while #pool > 0 and #state.activeObjectives < maxActive do
		local i = rng and rng:NextInteger(1, #pool) or 1
		local def = table.remove(pool, i)
		-- Mode roll: Hard only if the def has a Hard threshold.
		local mode = NORMAL
		if def.thresholds[HARD] ~= nil then
			mode = (rng and rng:NextNumber() < 0.35) and HARD or NORMAL
		end
		state.activeObjectives[#state.activeObjectives + 1] = { id = def.id, mode = mode }
	end

	return state.activeObjectives
end

--------------------------------------------------------------------
-- PLAYER-FACING TEXT (2026-10-28): plain-language goal + live progress for every
-- objective. Single source for BOTH Map Details (mid-battle) and the victory
-- screen, so the two can never disagree. Pure reads — never mutates state.
--------------------------------------------------------------------
local function liveKOs(state)
	local n = 0
	for _, u in ipairs((state and state.units) or {}) do
		if u.side == "Player" and not u.isSummon and not u.isAlive then n += 1 end
	end
	return n
end

local function counterText(key, goalFmt)
	return {
		goal = function(t) return string.format(goalFmt, t) end,
		progress = function(state, t) return string.format("%d / %d", counter(state, key), t) end,
		done = function(state, t) return counter(state, key) >= t end,
	}
end

local TEXT = {
	strategist = {
		goal = function(t)
			if t == 0 then return "Win without any of your units being KO'd" end
			return string.format("Win with no more than %d of your units KO'd", t)
		end,
		progress = function(state, t) return string.format("%d KO'd so far (limit %d)", liveKOs(state), t) end,
	},
	speed_clear = {
		goal = function(t) return string.format("Win within %d rounds (before %d CT)", t, t * CT_PER_ROUND) end,
		progress = function(state, t) return string.format("Round %d of %d", roundOf(state) + 1, t) end,
	},
	elite_slayer = {
		goal = function(t) return string.format("Defeat the Elite within %d rounds", t) end,
		progress = function(state, t)
			local r = counter(state, "eliteSlainRound1")
			if r > 0 then return string.format("Elite defeated in round %d", r) end
			return string.format("Round %d of %d, Elite still standing", roundOf(state) + 1, t)
		end,
		done = function(state, t)
			local r = counter(state, "eliteSlainRound1")
			return r >= 1 and r <= t
		end,
	},
	dragon_slayer = {
		goal = function() return "Trigger the Dragon Utopia, then defeat every dragon it summons" end,
		progress = function(state)
			if counter(state, "dragonUtopiaTriggered") <= 0 then return "Dragon Utopia not triggered yet" end
			return string.format("%d dragon(s) remaining", math.max(0, counter(state, "dragonsAlive")))
		end,
	},
	npc_survive = {
		goal = function() return "Keep the protected NPC alive until the battle ends" end,
		progress = function(state)
			if counter(state, "npcDied") > 0 then return "The NPC has fallen" end
			return "NPC is alive"
		end,
	},
	treasure_fever = counterText("chestsOpened",            "Open %d treasure chest(s)"),
	glutton        = counterText("chargesUsed",             "Use %d consumable charges"),
	demolition     = counterText("objectsBroken",           "Destroy %d map objects"),
	recruit        = counterText("enemiesRecruited",        "Recruit %d enemy unit(s) with Interact"),
	torture        = counterText("enemiesRevived",          "Revive %d KO'd enemy unit(s)"),
	one_punch      = counterText("oneShotFullKOs",          "KO %d full-HP enemy unit(s) with a single hit each"),
	nuker          = counterText("maxKOsInOneAction",       "KO %d or more enemies with a single attack"),
	siege          = counterText("siegeKOs",                "KO %d enemy unit(s) with a Ballista or Catapult"),
	pusher         = counterText("pushKOs",                 "KO %d enemy unit(s) by push, collision, or fall"),
	power_nature   = counterText("terrainKOs",              "KO %d enemy unit(s) with terrain (burning, lava, collapse)"),
	terrain_shaper = counterText("elevationTilesChanged",   "Change the elevation of %d tiles (explosions, Stone Pillar)"),
	terra_former   = counterText("terrainTilesTransformed", "Transform %d terrain tiles with elemental attacks"),
}

local function rewardCountFor(mode) return (mode == HARD) and 2 or 1 end

local function goalFor(def, mode)
	local tx = TEXT[def.id]
	local t = def.thresholds[mode]
	return (tx and tx.goal and tx.goal(t)) or def.name
end

-- Mid-battle view of the active objectives (Map Details). Returns a list of
-- { id, name, mode, goal, progress, done, rewardCount }. Empty list if none.
function ObjectiveService.Describe(state)
	local out = {}
	if not state or not state.activeObjectives then return out end
	for _, active in ipairs(state.activeObjectives) do
		local def = Catalog[active.id]
		if def then
			local tx = TEXT[def.id]
			local t = def.thresholds[active.mode]
			out[#out + 1] = {
				id = def.id,
				name = def.name,
				mode = active.mode,
				goal = goalFor(def, active.mode),
				progress = (tx and tx.progress and tx.progress(state, t)) or "",
				done = (tx and tx.done and tx.done(state, t)) or false,
				rewardCount = rewardCountFor(active.mode),
			}
		end
	end
	return out
end

-- Evaluate at battle end. Only grants on victory (won=true); on defeat every
-- optional objective fails with no reward and no penalty. Always erases.
-- Returns {
--   completed = { {id,mode,name}, ... }, rewardCount = N,
--   objectives = { {id,name,mode,goal,achieved,rewardCount,reason}, ... }  -- every
--     objective this battle, achieved OR failed (for the victory/defeat screen).
-- }
function ObjectiveService.Evaluate(state, won)
	local result = { completed = {}, rewardCount = 0, objectives = {} }
	if not state or not state.activeObjectives then return result end

	for _, active in ipairs(state.activeObjectives) do
		local def = Catalog[active.id]
		if def then
			local achieved = false
			if won and def.evaluate then
				achieved = def.evaluate(state, active.mode) == true
			end
			-- Hard objectives grant more reward than Normal: 2 rolls vs 1.
			local rc = achieved and rewardCountFor(active.mode) or 0
			result.objectives[#result.objectives + 1] = {
				id = def.id, name = def.name, mode = active.mode,
				goal = goalFor(def, active.mode),
				achieved = achieved,
				rewardCount = rc,
				reason = (not won) and "Battle lost" or ((not achieved) and "Not completed" or nil),
			}
			if achieved then
				result.completed[#result.completed + 1] = { id = def.id, mode = active.mode, name = def.name }
				result.rewardCount = result.rewardCount + rc
			end
		end
	end

	-- Fail-and-erase: clear the battle's objective state no matter the outcome.
	state.activeObjectives = nil
	state.objectiveCounters = nil
	return result
end

-- Mid-battle: add ONE more optional objective to a live battle (used by the
-- Chaos Statue, converted from its old board-quest behavior). Rolls from the
-- implemented pool, skips objectives already active, and gates by the live
-- battle context. Returns the added { id, mode, name } or nil if none eligible.
-- Counters already exist (BeginBattle created them at battle start); if the
-- statue somehow fires with no objective block, we initialize one defensively.
function ObjectiveService.AddOne(state, rng)
	if not state then return nil end
	state.objectiveCounters = state.objectiveCounters or {}
	state.activeObjectives = state.activeObjectives or {}

	local activeById = {}
	for _, a in ipairs(state.activeObjectives) do activeById[a.id] = true end

	local ctx = ObjectiveService.BuildContext(state.units, state.objects)
	local pool = {}
	for _, def in pairs(Catalog) do
		if not def.needsKillCause and IMPLEMENTED[def.id]
			and not activeById[def.id] and def.spawnable(ctx) then
			pool[#pool + 1] = def
		end
	end
	if #pool == 0 then return nil end
	table.sort(pool, function(a, b) return a.id < b.id end)

	local def = pool[(rng and rng:NextInteger(1, #pool)) or 1]
	local mode = NORMAL
	if def.thresholds[HARD] ~= nil then
		mode = (rng and rng:NextNumber() < 0.35) and HARD or NORMAL
	end
	local entry = { id = def.id, mode = mode, name = def.name }
	state.activeObjectives[#state.activeObjectives + 1] = entry
	return entry
end

-- Kill routing (Phase 2): called once per newly-dead unit by the
-- ObjectEffectService death-sweep. Reads the kill-cause tag (set centrally in
-- UnitSchema.ApplyDamage / the siege site) and bumps the matching counters.
-- Enemy KOs feed Pusher / Siege / Elite-timing; the priority NPC's death feeds
-- the (not-yet-rolled) Protect-the-NPC objective. Safe no-op if no battle block.
function ObjectiveService.OnUnitKilled(state, u)
	if not state or not u then return end
	state.objectiveCounters = state.objectiveCounters or {}
	if u.enemyPriorityTarget then
		state.objectiveCounters.npcDied = (state.objectiveCounters.npcDied or 0) + 1
	end
	if u.side ~= "Enemy" then return end
	local cause = u._killCause
	if cause == "push" then
		state.objectiveCounters.pushKOs = (state.objectiveCounters.pushKOs or 0) + 1
	elseif cause == "siege" then
		state.objectiveCounters.siegeKOs = (state.objectiveCounters.siegeKOs or 0) + 1
	elseif cause == "terrain" then
		state.objectiveCounters.terrainKOs = (state.objectiveCounters.terrainKOs or 0) + 1
	end
	if u.enemyType == "Elite" and (state.objectiveCounters.eliteSlainRound1 or 0) == 0 then
		state.objectiveCounters.eliteSlainRound1 = roundOf(state) + 1
	end
	if u._killedFromFull then
		state.objectiveCounters.oneShotFullKOs = (state.objectiveCounters.oneShotFullKOs or 0) + 1
	end
	if u.fromDragonUtopia then
		state.objectiveCounters.dragonsAlive = (state.objectiveCounters.dragonsAlive or 0) - 1
	end
end

-- Per-action multi-kill tally (Nuker). Called once per death-sweep with the
-- number of enemies that died in that single action; keeps the running max.
function ObjectiveService.RecordMultiKill(state, enemyKOsThisAction)
	if not state or not enemyKOsThisAction or enemyKOsThisAction <= 0 then return end
	state.objectiveCounters = state.objectiveCounters or {}
	local cur = state.objectiveCounters.maxKOsInOneAction or 0
	if enemyKOsThisAction > cur then
		state.objectiveCounters.maxKOsInOneAction = enemyKOsThisAction
	end
end

return ObjectiveService
