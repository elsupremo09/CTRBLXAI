--!strict
-- BattlefieldEventService — spawns and resolves the 35 battlefield events (Slice 5).
--
-- Battlefield events are SEPARATE from the weather/crisis slot and layer freely on
-- top of it (locked model 2026-10-04). The catalog (BattlefieldEventData) is prose
-- only; behaviour is resolved CODE-SIDE by the Handlers table keyed by event name,
-- mirroring ObjectEffectService exactly.
--
-- SERVER-ONLY (ServerScriptService). Server authority (ARC-001): every effect
-- mutates authoritative unit/battle state here; the client only renders via the
-- broadcaster. Spawned units go through EnemyGenerator.SpawnReinforcement and the
-- CALLER broadcasts UnitSpawned (caller-broadcasts pattern, proven in
-- ObjectEffectService). No per-frame work.
--
-- Cycle-free: siblings that would form a require cycle (BattleVisualBroadcaster,
-- TileEffectService, EnemyGenerator, RewardService, WeatherService, tile reshaper)
-- are INJECTED at runtime via Set* setters from Main.server during init. All
-- injected refs are nil-checked at every use.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Content catalog (prose fields: id, name, type, triggerSpawn, behaviorEffect).
local BattlefieldEventData = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("BattlefieldEventData"))

local GameConstants = require(
	ReplicatedStorage:WaitForChild("CTRBLXAI"):WaitForChild("Shared"):WaitForChild("GameConstants"))

local BattlefieldEventService = {}

--------------------------------------------------------------------
-- INJECTED DEPENDENCIES (set by Main.server during init; all nil-safe)
--------------------------------------------------------------------
local _broadcaster = nil        -- BattleVisualBroadcaster (UnitSpawned, etc.)
local _tileEffectService = nil  -- ApplyTileEffect / spread
local _enemyGenerator = nil     -- SpawnReinforcement / GenerateEnemy
local _rewardService = nil      -- SetRewardModifier / Clear
local _weatherService = nil     -- RerollForNewRound / condition pick (Fortune Teller)
local _tileReshaper = nil       -- MapRenderer.ReshapeTile(x, y, terrain, elev)

function BattlefieldEventService.SetBroadcaster(b) _broadcaster = b end
function BattlefieldEventService.SetTileEffectService(tes) _tileEffectService = tes end
function BattlefieldEventService.SetEnemyGenerator(eg) _enemyGenerator = eg end
function BattlefieldEventService.SetRewardService(rs) _rewardService = rs end
function BattlefieldEventService.SetWeatherService(ws) _weatherService = ws end
function BattlefieldEventService.SetTileReshaper(fn) _tileReshaper = fn end
local _unitRemover = nil
function BattlefieldEventService.SetUnitRemover(fn) _unitRemover = fn end
local _targetingService = nil
function BattlefieldEventService.SetTargetingService(ts) _targetingService = ts end
local _statusService = nil
function BattlefieldEventService.SetStatusService(ss) _statusService = ss end
local _commandService = nil
function BattlefieldEventService.SetCommandService(cs) _commandService = cs end

--------------------------------------------------------------------
-- SHARED HELPERS
--------------------------------------------------------------------
-- Map dimensions from the live grid (NO GameConstants.MAP_WIDTH/HEIGHT fields —
-- that assumption was the WEATHER-01 bug). TERRAIN_MAP[y][x]: height=#rows, width=#cols.
local function gridDims(): (number, number)
	local grid = GameConstants.TERRAIN_MAP
	local h = grid and #grid or 0
	local w = (h > 0 and grid[1]) and #grid[1] or 0
	return w, h
end

local function livingUnits(state)
	local out = {}
	for _, u in ipairs(state.units) do
		if u.isAlive and not u.isGroundTarget then table.insert(out, u) end
	end
	return out
end

local function livingBySide(state, side)
	local out = {}
	for _, u in ipairs(state.units) do
		if u.isAlive and not u.isGroundTarget and u.side == side then table.insert(out, u) end
	end
	return out
end

-- Spawn an event unit via the injected EnemyGenerator and broadcast it (caller-
-- broadcasts pattern). Tags the unit with eventKind/eventName so the neutral
-- behaviour resolver and later handlers can identify it. Returns the unit or nil.
local EVENT_UNIT_NAME = {
	["Zombie Horde"] = "Zombie",
	["Wandering Bandits"] = "Bandit",
	["Wandering Mercenaries"] = "Mercenary",
}

local function spawnEventUnit(state, rng, spec, spawnTile, side, raceOverride, eventName, eventKind)
	if not _enemyGenerator or not _enemyGenerator.SpawnReinforcement then
		warn("[BattlefieldEventService] EnemyGenerator not injected — cannot spawn " .. tostring(eventName))
		return nil
	end
	-- Never spawn onto a living unit / blocker / impassable tile: snap the chosen
	-- (edge) tile to the nearest free tile.
	if _enemyGenerator.FindNearestFreeSpawnTile and spawnTile then
		local free = _enemyGenerator.FindNearestFreeSpawnTile(state, spawnTile.x, spawnTile.y, rng)
		if not free then
			warn("[BattlefieldEventService] No free spawn tile for " .. tostring(eventName) .. " — skipped")
			return nil
		end
		spawnTile = free
	end
	local unit = _enemyGenerator.SpawnReinforcement(spec, spawnTile, state, rng, side, raceOverride)
	if not unit then return nil end
	unit.eventName = eventName
	unit.eventKind = eventKind
	-- Single-active-event model: tie the unit to the event being fired so the event
	-- ends when all its units are gone (defeated or left the map).
	if state.currentEventRecord then
		state.currentEventRecord.units = state.currentEventRecord.units or {}
		table.insert(state.currentEventRecord.units, unit)
	end
	-- Event units are named after their event, not procedurally (plural events -> singular).
	if type(eventName) == "string" and eventName ~= "" then
		unit.name = EVENT_UNIT_NAME[eventName] or eventName
	end
	if _broadcaster and _broadcaster.UnitSpawned then
		_broadcaster.UnitSpawned(unit)
	end
	return unit
end

--------------------------------------------------------------------
-- EVENT RULES (explicit per-event spawn metadata — replaces prose-sniffing).
-- Matches docs\CTRBLXAI.db battlefield_events trigger_spawn exactly.
--   rarity : "Common"(1.0) | "Uncommon"(0.5) | "Rare"(0.2) spawn weight.
--   gate   : nil = eligible in the random start pool;
--            "roundN" = conditional, fires round>=N (OnRoundStart);
--            "champion" / "divine" / "necromancer" / "earthScout" = special gate fns.
--   biomes : optional allow-list (Zombie Horde "applicable biomes").
--------------------------------------------------------------------
local RARITY_WEIGHT = { Common = 1.0, Uncommon = 0.5, Rare = 0.2 }

local EVENT_RULES = {
	["Merchant Caravan"]   = { rarity = "Common" },
	["Slave Trader"]       = { rarity = "Common" },
	["Wandering Scholar"]  = { rarity = "Common" },
	["Wandering Bard"]     = { rarity = "Common" },
	["Wandering Mercenaries"] = { rarity = "Common" },
	["Champion"]           = { rarity = "Uncommon", gate = "champion" },      -- round2+ & HP<=50% & >50% enemies defeated
	["Zombie Horde"]       = { rarity = "Common",  gate = "round2", biomes = { Corrupted = true, Ruins = true, Cave = true, Castle = true } },
	["Leprechaun"]         = { rarity = "Rare" },
	["Thief"]              = { rarity = "Common" },                           -- spawns visible; Hides on its own turn
	["Wandering Blacksmith"] = { rarity = "Common" },
	["Mutator"]            = { rarity = "Uncommon" },
	["Herald of XXX"]      = { rarity = "Uncommon", gate = "round2" },
	["Divine Intervention"]= { rarity = "Rare", gate = "divine" },            -- >=50% friendly KO'd AND map>=5 lvls above highest friendly
	["Chaos Necromancer"]  = { rarity = "Uncommon", gate = "necromancer" },   -- round2+ & >50% enemies defeated
	["Fortune Teller"]     = { rarity = "Common" },
	["Lost Noble"]         = { rarity = "Common" },
	["Treasure Hunter"]    = { rarity = "Common" },
	["Wandering Monster"]  = { rarity = "Common" },
	["Vengeful Spirit"]    = { rarity = "Common" },
	["Bounty Hunter"]      = { rarity = "Common" },
	["Monster Hunter"]     = { rarity = "Common" },
	["Wandering Bandits"]  = { rarity = "Common" },
	["Plague Carrier"]     = { rarity = "Common" },
	["Traitor"]            = { rarity = "Common" },
	["Enemy Scout"]        = { rarity = "Common" },                           -- DB: random spawn (de-gated)
	["Doppelganger"]       = { rarity = "Common" },
	["Chaos Lich"]         = { rarity = "Rare" },
	["Fog Spirit"]         = { rarity = "Common" },
	["Fire Spirit"]        = { rarity = "Common" },
	["Wind Spirit"]        = { rarity = "Common" },
	["Water Spirit"]       = { rarity = "Common" },
	["Lightning Elemental"]= { rarity = "Common" },
	["Earth Elemental"]    = { rarity = "Common", noDuringCondition = "Earthquake" },  -- DB: random spawn, not during Earthquake  -- not during Earthquake Crisis (spawn-time)
	["Gold Golem"]         = { rarity = "Rare" },
	["Crystal Golem"]      = { rarity = "Rare" },
}

local function eventRule(name)
	return EVENT_RULES[name] or { rarity = "Common" }
end

--------------------------------------------------------------------
-- HANDLERS (keyed by event name). Populated in later build steps.
-- Each handler: function(ctx) where ctx = { state, rng, roundIndex }.
--------------------------------------------------------------------
local Handlers = {}

-- Status helpers (nil-safe via injected StatusService).
local function applyStatusTo(unit, statusId, sourceId)
	if _statusService and _statusService.ApplyStatus then
		_statusService.ApplyStatus(unit, statusId, sourceId or "battlefieldEvent")
	end
end

local BARD_BUFFS = { "Blessed", "Haste", "Rally", "Regeneration", "Battle Rage", "Rune Ward" }
local BARD_DEBUFFS = { "Cursed", "Slow", "Weakened", "Blind" }

-- Pick a spawn tile near the map edge for an event unit (deterministic).
local function edgeSpawnTile(state, rng)
	local w, h = gridDims()
	if w == 0 or h == 0 then return { x = 1, y = 1 } end
	local side = rng:NextInteger(1, 4)
	if side == 1 then return { x = 1, y = rng:NextInteger(1, h) }
	elseif side == 2 then return { x = w, y = rng:NextInteger(1, h) }
	elseif side == 3 then return { x = rng:NextInteger(1, w), y = 1 }
	else return { x = rng:NextInteger(1, w), y = h } end
end

-- Highest-friendly level (for scaling event units).
local function highestFriendlyLevel(state)
	local lvl = 1
	for _, u in ipairs(state.units) do
		if u.side == "Player" and (u.level or 1) > lvl then lvl = u.level or 1 end
	end
	return lvl
end

-- ===================== NEUTRAL NPCs (spawn + behaviour tag) =====================

-- Merchant Caravan — moves across map; shop payload STUBBED (no Merchant Shop system).
Handlers["Merchant Caravan"] = function(ctx)
	local u = spawnEventUnit(ctx.state, ctx.rng, { type = "Grunt", level = 1 },
		edgeSpawnTile(ctx.state, ctx.rng), "Neutral", nil, "Merchant Caravan", "crossMap")
	-- STUB: Merchant Shop system does not exist yet; interacting would double next
	-- shop items + rarity. Spawn + cross-map movement only until the shop exists.
	return true
end

-- Slave Trader — moves across map; recruitment payload STUBBED (no recruitment UI).
Handlers["Slave Trader"] = function(ctx)
	spawnEventUnit(ctx.state, ctx.rng, { type = "Grunt", level = 1 },
		edgeSpawnTile(ctx.state, ctx.rng), "Neutral", nil, "Slave Trader", "crossMap")
	-- STUB: recruitment system does not exist yet (doubles recruit options + rarity).
	return true
end

-- Wandering Blacksmith — moves across map; blacksmith payload STUBBED (no blacksmith UI).
Handlers["Wandering Blacksmith"] = function(ctx)
	spawnEventUnit(ctx.state, ctx.rng, { type = "Grunt", level = 1 },
		edgeSpawnTile(ctx.state, ctx.rng), "Neutral", nil, "Wandering Blacksmith", "crossMap")
	-- STUB: Blacksmith system does not exist yet (improves next blacksmith interaction).
	return true
end

-- Wandering Scholar — passive; interacting doubles EXP (via reward hook, on interact).
Handlers["Wandering Scholar"] = function(ctx)
	spawnEventUnit(ctx.state, ctx.rng, { type = "Grunt", level = 1 },
		edgeSpawnTile(ctx.state, ctx.rng), "Neutral", nil, "Wandering Scholar", "passive")
	-- EXP x2 is applied via RewardService.SetRewardModifier when the player interacts
	-- (ResolveInteract). Spawn + passive presence here.
	return true
end

-- Wandering Mercenaries — passive; fight-for-gold is an interact choice (STUB payload).
Handlers["Wandering Mercenaries"] = function(ctx)
	spawnEventUnit(ctx.state, ctx.rng, { type = "Veteran", level = highestFriendlyLevel(ctx.state) },
		edgeSpawnTile(ctx.state, ctx.rng), "Neutral", nil, "Wandering Mercenaries", "passive")
	-- STUB: the fight-for-half-gold contract needs the gold-economy interact flow.
	return true
end

-- Fortune Teller — passive; interacting lets the player choose the next weather/crisis.
Handlers["Fortune Teller"] = function(ctx)
	spawnEventUnit(ctx.state, ctx.rng, { type = "Grunt", level = 1 },
		edgeSpawnTile(ctx.state, ctx.rng), "Neutral", nil, "Fortune Teller", "passive")
	-- Interact → WeatherService.SetNextCondition(playerChoice) (handled in ResolveInteract).
	return true
end

-- Lost Noble — passive; enemies prioritise it; survival → loot (loot-pool STUBBED).
Handlers["Lost Noble"] = function(ctx)
	-- Spawn on the far edge from the player deploy zone so its run home matters.
	local spawnTile = edgeSpawnTile(ctx.state, ctx.rng)
	local pd = ctx.state.playerDeployTiles
	if pd and #pd > 0 then
		local w, h = gridDims()
		local ax, ay = 0, 0
		for _, t in ipairs(pd) do ax = ax + t.x; ay = ay + t.y end
		ax, ay = ax / #pd, ay / #pd
		spawnTile = { x = (ax <= w / 2) and w or 1, y = math.clamp(math.floor(ay + 0.5), 1, math.max(1, h)) }
	end
	local u = spawnEventUnit(ctx.state, ctx.rng, { type = "Grunt", level = 1 },
		spawnTile, "Neutral", nil, "Lost Noble", "fleeToPD")
	if u then
		u.enemyPriorityTarget = true      -- the ONE neutral enemies attack (protect-the-NPC event)
		u.initiativeBaseRt = 300          -- user rule 2026-10-06: base RT 300
		u.remainingRt = math.min(u.remainingRt or 300, 300)
	end
	-- STUB: "add Rare+ item to loot pool on survival" needs a loot-pool hook that does
	-- not exist yet. The priority-target flag + spawn are live.
	return true
end

-- Treasure Hunter — moves to nearest treasure and loots it over turns.
Handlers["Treasure Hunter"] = function(ctx)
	spawnEventUnit(ctx.state, ctx.rng, { type = "Veteran", level = 1 },
		edgeSpawnTile(ctx.state, ctx.rng), "Neutral", nil, "Treasure Hunter", "seekTreasure")
	return true
end

-- Monster Hunter — hunts enemy units; drops a visible trap each of its turns.
Handlers["Monster Hunter"] = function(ctx)
	spawnEventUnit(ctx.state, ctx.rng, { type = "Veteran", level = highestFriendlyLevel(ctx.state) },
		edgeSpawnTile(ctx.state, ctx.rng), "Neutral", nil, "Monster Hunter", "huntMonster")
	-- Trap drop handled by OnEventUnitTurn (Snare Trap tile effect at its tile).
	return true
end

-- Wandering Bard — passive; while alive, applies a random buff OR debuff to all units.
Handlers["Wandering Bard"] = function(ctx)
	local u = spawnEventUnit(ctx.state, ctx.rng, { type = "Grunt", level = 1 },
		edgeSpawnTile(ctx.state, ctx.rng), "Neutral", nil, "Wandering Bard", "passive")
	if u then u.bardAura = true end
	-- The per-round random buff/debuff-to-all is applied in OnEventUnitTurn / OnRoundStart
	-- while the Bard is alive.
	return true
end

-- ===================== HOSTILE / COMBAT EVENTS =====================

-- Champion — powerful elite comeback threat (conditional spawn).
Handlers["Champion"] = function(ctx)
	spawnEventUnit(ctx.state, ctx.rng, { type = "Elite", level = highestFriendlyLevel(ctx.state) + 2 },
		edgeSpawnTile(ctx.state, ctx.rng), "Enemy", nil, "Champion", nil)
	return true
end

-- Zombie Horde — several hostile undead, hostile to non-undead.
Handlers["Zombie Horde"] = function(ctx)
	local n = ctx.rng:NextInteger(3, 5)
	for _ = 1, n do
		spawnEventUnit(ctx.state, ctx.rng, { type = "Grunt", level = highestFriendlyLevel(ctx.state) },
			edgeSpawnTile(ctx.state, ctx.rng), "Enemy", "RACE-ZOMBIE", "Zombie Horde", nil)
	end
	return true
end

-- Leprechaun — defeating grants large gold (reward modifier on its death).
Handlers["Leprechaun"] = function(ctx)
	local u = spawnEventUnit(ctx.state, ctx.rng, { type = "Grunt", level = 1 },
		edgeSpawnTile(ctx.state, ctx.rng), "Enemy", nil, "Leprechaun", nil)
	if u then u.rewardOnDeath = { goldMult = 3.0 } end  -- applied via reward hook on defeat
	return true
end

-- Thief — attempts Steal on friendlies; defeating recovers the stolen item.
Handlers["Thief"] = function(ctx)
	local u = spawnEventUnit(ctx.state, ctx.rng, { type = "Veteran", level = highestFriendlyLevel(ctx.state) },
		edgeSpawnTile(ctx.state, ctx.rng), "Enemy", nil, "Thief", nil)
	if u then u.thiefBehavior = true end  -- AI/Steal path reads this
	return true
end

-- Chaos Necromancer — turns enemy corpses into undead each turn.
Handlers["Chaos Necromancer"] = function(ctx)
	local u = spawnEventUnit(ctx.state, ctx.rng, { type = "Elite", level = highestFriendlyLevel(ctx.state) },
		edgeSpawnTile(ctx.state, ctx.rng), "Enemy", nil, "Chaos Necromancer", nil)
	if u then u.raisesCorpses = true end  -- OnEventUnitTurn raises nearby corpses
	return true
end

-- Chaos Lich — casts Death Ripple each turn hitting all non-undead.
Handlers["Chaos Lich"] = function(ctx)
	local u = spawnEventUnit(ctx.state, ctx.rng, { type = "Elite", level = highestFriendlyLevel(ctx.state) + 2 },
		edgeSpawnTile(ctx.state, ctx.rng), "Enemy", nil, "Chaos Lich", nil)
	if u then u.deathRipple = true end  -- OnEventUnitTurn applies the ripple
	return true
end

-- Wandering Monster — high level; neutral until a friendly attacks it.
Handlers["Wandering Monster"] = function(ctx)
	local u = spawnEventUnit(ctx.state, ctx.rng, { type = "Elite", level = highestFriendlyLevel(ctx.state) + ctx.rng:NextInteger(5, 10) },
		edgeSpawnTile(ctx.state, ctx.rng), "Neutral", nil, "Wandering Monster", "passive")
	if u then u.turnsHostileWhenAttacked = true end
	return true
end

-- Wandering Bandits — demand gold; refuse/attack → hostile (gold path STUB; hostile live).
Handlers["Wandering Bandits"] = function(ctx)
	local n = ctx.rng:NextInteger(2, 3)
	for _ = 1, n do
		local u = spawnEventUnit(ctx.state, ctx.rng, { type = "Veteran", level = highestFriendlyLevel(ctx.state) },
			edgeSpawnTile(ctx.state, ctx.rng), "Neutral", nil, "Wandering Bandits", "passive")
		if u then u.turnsHostileWhenAttacked = true end
	end
	-- STUB: "pay gold to make them leave" needs the gold-economy interact; refuse/attack
	-- → hostile is live via turnsHostileWhenAttacked.
	return true
end

-- Vengeful Spirit — seeks a monster; interacting makes that monster Elite +10 (hostile unit).
Handlers["Vengeful Spirit"] = function(ctx)
	local u = spawnEventUnit(ctx.state, ctx.rng, { type = "Veteran", level = highestFriendlyLevel(ctx.state) },
		edgeSpawnTile(ctx.state, ctx.rng), "Enemy", nil, "Vengeful Spirit", nil)
	return true
end

-- Bounty Hunter — targets one friendly; immune to Taunt.
Handlers["Bounty Hunter"] = function(ctx)
	local players = livingBySide(ctx.state, "Player")
	local u = spawnEventUnit(ctx.state, ctx.rng, { type = "Elite", level = highestFriendlyLevel(ctx.state) + 1 },
		edgeSpawnTile(ctx.state, ctx.rng), "Enemy", nil, "Bounty Hunter", nil)
	if u then
		u.tauntImmune = true
		if #players > 0 then u.lockedTarget = players[ctx.rng:NextInteger(1, #players)].id end
	end
	return true
end

-- Enemy Scout — defeat before end of Round 2 or enemy gets reinforcements.
Handlers["Enemy Scout"] = function(ctx)
	local u = spawnEventUnit(ctx.state, ctx.rng, { type = "Grunt", level = highestFriendlyLevel(ctx.state) },
		edgeSpawnTile(ctx.state, ctx.rng), "Enemy", nil, "Enemy Scout", nil)
	if u then u.scoutDeadline = (ctx.roundIndex or 0) + 2 end  -- OnRoundStart checks survival
	return true
end

-- Doppelganger — copies a friendly unit; defeating grants 5x EXP.
Handlers["Doppelganger"] = function(ctx)
	local players = livingBySide(ctx.state, "Player")
	local copyLvl = (#players > 0) and (players[1].level or 1) or 1
	local u = spawnEventUnit(ctx.state, ctx.rng, { type = "Elite", level = copyLvl },
		edgeSpawnTile(ctx.state, ctx.rng), "Enemy", nil, "Doppelganger", nil)
	if u then u.rewardOnDeath = { expMult = 5.0 } end
	return true
end

-- Lightning Elemental — every turn strikes the unit on highest elevation (any range).
Handlers["Lightning Elemental"] = function(ctx)
	local u = spawnEventUnit(ctx.state, ctx.rng, { type = "Elite", level = highestFriendlyLevel(ctx.state) },
		edgeSpawnTile(ctx.state, ctx.rng), "Enemy", nil, "Lightning Elemental", nil)
	if u then u.strikesHighestElevation = true end  -- OnEventUnitTurn
	return true
end

-- Gold Golem — defeating yields 5x gold.
Handlers["Gold Golem"] = function(ctx)
	local u = spawnEventUnit(ctx.state, ctx.rng, { type = "Elite", level = highestFriendlyLevel(ctx.state) },
		edgeSpawnTile(ctx.state, ctx.rng), "Enemy", nil, "Gold Golem", nil)
	if u then u.rewardOnDeath = { goldMult = 5.0 } end
	return true
end

-- Crystal Golem — defeating yields 5x material.
Handlers["Crystal Golem"] = function(ctx)
	local u = spawnEventUnit(ctx.state, ctx.rng, { type = "Elite", level = highestFriendlyLevel(ctx.state) },
		edgeSpawnTile(ctx.state, ctx.rng), "Enemy", nil, "Crystal Golem", nil)
	if u then u.rewardOnDeath = { materialMult = 5.0 } end
	return true
end

-- ===================== HAZARD / MODIFIER / TRANSFORM EVENTS =====================

-- Plague Carrier — every tile it crosses becomes Corrupted + Poison Gas.
Handlers["Plague Carrier"] = function(ctx)
	local u = spawnEventUnit(ctx.state, ctx.rng, { type = "Grunt", level = highestFriendlyLevel(ctx.state) },
		edgeSpawnTile(ctx.state, ctx.rng), "Enemy", nil, "Plague Carrier", nil)
	if u then u.trailEffect = "Tainted Ground"; u.trailEffect2 = "Poison Cloud" end  -- OnEventUnitTurn
	return true
end

-- Fog Spirit — leaves Fog on every tile it crosses.
Handlers["Fog Spirit"] = function(ctx)
	local u = spawnEventUnit(ctx.state, ctx.rng, { type = "Grunt", level = highestFriendlyLevel(ctx.state) },
		edgeSpawnTile(ctx.state, ctx.rng), "Enemy", nil, "Fog Spirit", nil)
	if u then u.trailEffect = "Fog" end
	return true
end

-- Fire Spirit — burns every tile it crosses.
Handlers["Fire Spirit"] = function(ctx)
	local u = spawnEventUnit(ctx.state, ctx.rng, { type = "Grunt", level = highestFriendlyLevel(ctx.state) },
		edgeSpawnTile(ctx.state, ctx.rng), "Enemy", nil, "Fire Spirit", nil)
	if u then u.trailEffect = "Burning" end
	return true
end

-- Wind Spirit — while alive, flying effects and Flying race are disabled.
Handlers["Wind Spirit"] = function(ctx)
	local u = spawnEventUnit(ctx.state, ctx.rng, { type = "Elite", level = highestFriendlyLevel(ctx.state) },
		edgeSpawnTile(ctx.state, ctx.rng), "Enemy", nil, "Wind Spirit", nil)
	if u then ctx.state.flyingDisabled = true; u.disablesFlying = true end
	return true
end

-- Water Spirit — each turn: lowest non-water tiles → Shallow Water; Water → Deep Water.
Handlers["Water Spirit"] = function(ctx)
	local u = spawnEventUnit(ctx.state, ctx.rng, { type = "Elite", level = highestFriendlyLevel(ctx.state) },
		edgeSpawnTile(ctx.state, ctx.rng), "Enemy", nil, "Water Spirit", nil)
	if u then u.floodsTiles = true end  -- OnEventUnitTurn
	return true
end

-- Earth Elemental — triggers Earthquake crisis each turn (and blocks the natural one).
Handlers["Earth Elemental"] = function(ctx)
	local u = spawnEventUnit(ctx.state, ctx.rng, { type = "Elite", level = highestFriendlyLevel(ctx.state) },
		edgeSpawnTile(ctx.state, ctx.rng), "Enemy", nil, "Earth Elemental", nil)
	if u then
		u.triggersEarthquake = true
		if _weatherService and _weatherService.SetConditionBlocked then
			_weatherService.SetConditionBlocked("Earthquake", true)  -- can't co-occur
		end
	end
	return true
end

-- ===================== SPECIAL EVENTS =====================

-- Divine Intervention — revive all KO'd friendlies at full HP + team buff; once/battle.
Handlers["Divine Intervention"] = function(ctx)
	for _, u in ipairs(ctx.state.units) do
		if u.side == "Player" and not u.isAlive then
			u.isAlive = true
			u.currentHp = u.maxHp
			applyStatusTo(u, "Blessed", "Divine Intervention")
			if _broadcaster and _broadcaster.UnitStateChanged then _broadcaster.UnitStateChanged(u) end
		elseif u.side == "Player" and u.isAlive then
			applyStatusTo(u, "Blessed", "Divine Intervention")
		end
	end
	print("[BattlefieldEventService] Divine Intervention — revived KO'd allies + team Blessed.")
	return true
end

-- Herald of XXX — a neutral Herald whose defeat spawns the boss it heralds.
Handlers["Herald of XXX"] = function(ctx)
	local u = spawnEventUnit(ctx.state, ctx.rng, { type = "Veteran", level = highestFriendlyLevel(ctx.state) },
		edgeSpawnTile(ctx.state, ctx.rng), "Neutral", nil, "Herald of XXX", "passive")
	if u then u.spawnsBossOnDeath = true end  -- defeat → SpawnReinforcement a boss (OnDeath)
	return true
end

-- Mutator — defeating spawns Mutation Bench; STUBBED (Mutation Bench + perk/drawback undesigned).
Handlers["Mutator"] = function(ctx)
	local u = spawnEventUnit(ctx.state, ctx.rng, { type = "Elite", level = highestFriendlyLevel(ctx.state) },
		edgeSpawnTile(ctx.state, ctx.rng), "Enemy", nil, "Mutator", nil)
	-- STUB: Mutation Bench + perk/drawback catalog/roll logic are NOT designed yet.
	-- Spawn the enemy; the "spawn Mutation Bench on defeat" payload is inert until that exists.
	return true
end

-- Traitor — enemy (debuffed) until <=25% original enemies alive, then becomes neutral ally + dispel.
Handlers["Traitor"] = function(ctx)
	local u = spawnEventUnit(ctx.state, ctx.rng, { type = "Veteran", level = highestFriendlyLevel(ctx.state) },
		edgeSpawnTile(ctx.state, ctx.rng), "Enemy", nil, "Traitor", nil)
	if u then
		u.traitorFlips = true  -- OnRoundStart/OnEventUnitTurn flips side at threshold
		applyStatusTo(u, "Weakened", "Traitor")
	end
	return true
end


-- Neutral behaviour resolvers (keyed by eventKind). Populated in the neutral step.
local NeutralBehaviors = {}

-- Reachable empty tiles for a neutral unit (reuse the AI/targeting pathing so a
-- neutral never stops on an occupied/unreachable tile). Returns {} if unavailable.
local function moveCandidates(unit, state)
	if not _targetingService or not _targetingService.GetMoveCandidates then return {} end
	local w, h = gridDims()
	return _targetingService.GetMoveCandidates(unit, state.units, w, h) or {}
end

-- Pick the reachable candidate that minimises distance to (gx, gy). Returns a
-- Move action descriptor { actionType="Move", selection=tile } or nil (→ Wait).
local function moveTowardGoal(unit, state, gx, gy)
	local cands = moveCandidates(unit, state)
	if #cands == 0 then return nil end
	local best, bestD = nil, math.huge
	for _, t in ipairs(cands) do
		local tx, ty = t.tileX or t.x, t.tileY or t.y
		local d = math.abs(tx - gx) + math.abs(ty - gy)
		if d < bestD then bestD, best = d, t end
	end
	if not best then return nil end
	return { actionType = "Move", selection = best, skillName = nil }
end

-- "Cross the map": walk toward the far edge from the unit's spawn side.
NeutralBehaviors["crossMap"] = function(unit, state)
	local w, h = gridDims()
	-- Exit: once the walker reaches its goal edge, it leaves the map (unit removed),
	-- which ends its event so the next one can fire (single-active-event model).
	unit.crossGoalX = unit.crossGoalX or ((unit.tileX <= w / 2) and w or 1)
	if unit.tileX == unit.crossGoalX then
		unit.leftMap = true
		unit.isAlive = false
		if _unitRemover then _unitRemover(unit) end  -- free tile + remove client token
		print("[BattlefieldEventService] " .. tostring(unit.name) .. " left the map.")
		return nil
	end
	return moveTowardGoal(unit, state, unit.crossGoalX, unit.tileY)
end

-- "Seek nearest treasure": move toward the closest Treasure/Cursed Chest object.
NeutralBehaviors["seekTreasure"] = function(unit, state)
	local objs = state.objects or {}
	local best, bestD = nil, math.huge
	for _, o in ipairs(objs) do
		if o.type == "Treasure Chest" or o.type == "Cursed Chest" then
			local d = math.abs((o.x or 0) - unit.tileX) + math.abs((o.y or 0) - unit.tileY)
			if d < bestD then bestD, best = d, o end
		end
	end
	if not best then return nil end  -- no treasure left → Wait
	return moveTowardGoal(unit, state, best.x, best.y)
end

-- "Hunt nearest monster": advance toward the closest enemy-side unit. (The visible
-- trap-drop each turn is applied by the Monster Hunter handler's turn hook.)
NeutralBehaviors["huntMonster"] = function(unit, state)
	local best, bestD = nil, math.huge
	for _, u in ipairs(state.units) do
		if u.isAlive and not u.isGroundTarget and u.side == "Enemy" then
			local d = math.abs(u.tileX - unit.tileX) + math.abs(u.tileY - unit.tileY)
			if d < bestD then bestD, best = d, u end
		end
	end
	if not best then return nil end
	return moveTowardGoal(unit, state, best.tileX, best.tileY)
end

-- Passive neutrals (Bard, Scholar, Fortune Teller, Mercenaries, Lost Noble): stand.
-- Lost Noble: MOVE-ONLY, always runs toward the player deploy (PD) area.
NeutralBehaviors["fleeToPD"] = function(unit, state)
	local pd = state.playerDeployTiles
	if not pd or #pd == 0 then return nil end
	local best, bestD = nil, math.huge
	for _, t in ipairs(pd) do
		local d = math.abs(t.x - unit.tileX) + math.abs(t.y - unit.tileY)
		if d < bestD then bestD, best = d, t end
	end
	if not best or bestD == 0 then return nil end
	return moveTowardGoal(unit, state, best.x, best.y)
end

NeutralBehaviors["passive"] = function(unit, state)
	return nil  -- Wait
end

--------------------------------------------------------------------
-- PUBLIC API (bodies filled in later steps; declared now so Main can wire + the
-- module is complete/loadable at every checkpoint)
--------------------------------------------------------------------

-- Choose which events spawn for this battle (0-3 random eligible + register
-- conditional/round-gated ones). Deterministic from the seeded rng.
-- Rarity-weighted draw of ONE event from the remaining start pool (removes it).
function BattlefieldEventService._drawStartEvent(state, rng)
	local active = _weatherService and _weatherService.GetActiveCondition and _weatherService.GetActiveCondition()
	local function eligible(def)
		local nd = eventRule(def.name).noDuringCondition
		return not (nd and active == nd)
	end
	local pool = {}
	for _, def in ipairs(state.bfStartPool or {}) do if eligible(def) then table.insert(pool, def) end end
	local total = 0
	for _, def in ipairs(pool) do total = total + (RARITY_WEIGHT[eventRule(def.name).rarity] or 1.0) end
	if total <= 0 or #pool == 0 then return nil end
	local r, acc, pickIdx = rng:NextNumber() * total, 0, nil
	for idx, def in ipairs(pool) do
		acc = acc + (RARITY_WEIGHT[eventRule(def.name).rarity] or 1.0)
		if r <= acc then pickIdx = idx break end
	end
	pickIdx = pickIdx or #pool
	local def = pool[pickIdx]
	for i, d in ipairs(state.bfStartPool) do if d == def then table.remove(state.bfStartPool, i) break end end
	return def
end

-- Fire one event: announce, run its spawn handler, make it the active event.
function BattlefieldEventService._fireEvent(state, rng, def, roundIndex)
	local rec = { def = def, name = def.name, units = {}, spawnedUnit = nil }
	state.battlefieldEvents = state.battlefieldEvents or {}
	table.insert(state.battlefieldEvents, rec)
	state.bfFiredCount  = (state.bfFiredCount or 0) + 1
	state.bfActiveEvent = rec
	if _broadcaster and _broadcaster.BattlefieldEventAnnounced then
		_broadcaster.BattlefieldEventAnnounced(def.name)
	end
	local handler = Handlers[def.name]
	state.currentEventRecord = rec
	if handler then
		local ok, err = pcall(handler, { state = state, rng = rng, roundIndex = roundIndex or 0, record = rec, phase = "spawn" })
		if not ok then
			warn("[BattlefieldEventService] handler '" .. def.name .. "' error: " .. tostring(err))
		end
	end
	state.currentEventRecord = nil
	-- Instant events (no units spawned, e.g. Divine Intervention) end immediately.
	if #rec.units == 0 then state.bfActiveEvent = nil end
	print(string.format("[BattlefieldEventService] Event fired: %s (%d/%d this battle)%s",
		def.name, state.bfFiredCount, state.bfBudget or 0,
		state.bfActiveEvent and "" or " [instant — slot free]"))
	return rec
end

-- Active event is over when every unit it spawned is dead or has left the map.
local function activeEventDone(state)
	local rec = state.bfActiveEvent
	if not rec then return true end
	for _, u in ipairs(rec.units or {}) do
		if u.isAlive and not u.leftMap then return false end
	end
	return true
end

-- Called every turn advance: free the slot when the active event ends, then fire
-- the next one (queued conditional first, else a random start-pool draw if the
-- per-battle budget allows).
function BattlefieldEventService.OnTurnTick(state, rng, roundIndex)
	if state.bfBudget == nil then return end
	if state.bfActiveEvent and activeEventDone(state) then
		print("[BattlefieldEventService] Event ended: " .. state.bfActiveEvent.name)
		state.bfActiveEvent = nil
	end
	if state.bfActiveEvent then return end
	-- Queued conditional events take priority (they still need their condition true —
	-- it was true when queued; they fire as soon as the slot frees).
	local q = state.bfPendingQueue
	if q and #q > 0 then
		local def = table.remove(q, 1)
		BattlefieldEventService._fireEvent(state, rng, def, roundIndex or 0)
		return
	end
	if (state.bfFiredCount or 0) < (state.bfBudget or 0) then
		local def = BattlefieldEventService._drawStartEvent(state, rng)
		if def then BattlefieldEventService._fireEvent(state, rng, def, roundIndex or 0) end
	end
end

function BattlefieldEventService.SelectEventsForBattle(state, biome, rng)
	state.battlefieldEvents = {}          -- active event records this battle
	state.battlefieldConditional = {}     -- round-gated / conditional, not yet fired

	-- Partition via EVENT_RULES: gated events (round/condition) → conditional registry;
	-- the rest form the start pool (filtered by biome allow-list where set).
	local biomeName = (type(biome) == "table" and biome.name) or biome
	local startPool, conditional = {}, {}
	for _, name in ipairs(BattlefieldEventData.Order) do
		local def = BattlefieldEventData.Events[name]
		if def then
			local rule = eventRule(name)
			-- Biome allow-list (e.g. Zombie Horde): if set and this biome not listed, skip entirely.
			local biomeOk = (rule.biomes == nil) or (biomeName ~= nil and rule.biomes[biomeName] == true)
			if biomeOk then
				if rule.gate ~= nil then
					conditional[name] = def
				else
					table.insert(startPool, def)
				end
			end
		end
	end

	for name, def in pairs(conditional) do
		state.battlefieldConditional[name] = { def = def, fired = false, rule = eventRule(name) }
	end

	-- SINGLE-ACTIVE-EVENT MODEL (user rule 2026-10-06): 0-3 events total per battle,
	-- but only ONE may be active at a time. A new event fires only after the active one
	-- ends (its units are defeated or leave the map; instant events end immediately).
	table.sort(startPool, function(a, b) return a.name < b.name end)
	state.bfStartPool    = startPool
	state.bfBudget       = rng:NextInteger(0, 3)   -- total events this battle
	state.bfFiredCount   = 0
	state.bfActiveEvent  = nil
	state.bfPendingQueue = {}                      -- conditional events waiting for the slot
	if state.bfBudget > 0 then
		local def = BattlefieldEventService._drawStartEvent(state, rng)
		if def then BattlefieldEventService._fireEvent(state, rng, def, 0) end
	end

	local condCount = 0
	for _ in pairs(state.battlefieldConditional) do condCount = condCount + 1 end
	print(string.format("[BattlefieldEventService] SelectEventsForBattle | budget %d, active=%s, %d conditional registered.",
		state.bfBudget, state.bfActiveEvent and state.bfActiveEvent.name or "none", condCount))
	return state.battlefieldEvents
end

-- Evaluate conditional / round-gated spawns at each 1000-CT round boundary.
function BattlefieldEventService.OnRoundStart(state, roundIndex, rng)
	if not state.battlefieldConditional then return end
	for name, c in pairs(state.battlefieldConditional) do
		if not c.fired then
			local def = c.def
			local gate = (c.rule and c.rule.gate) or eventRule(name).gate
			local shouldFire = false

			local function enemiesHalfDefeated()
				local enemiesAlive = #livingBySide(state, "Enemy")
				local enemiesTotal = state.enemyCountAtStart or (enemiesAlive + 1)
				return (enemiesTotal > 0) and ((enemiesTotal - enemiesAlive) > enemiesTotal * 0.5)
			end
			local function anyPlayerLowHp()
				for _, u in ipairs(livingBySide(state, "Player")) do
					if (u.currentHp or 0) <= (u.maxHp or 1) * 0.5 then return true end
				end
				return false
			end

			if gate == "champion" then
				-- Round 2+ when friendly HP <=50% max AND >50% enemies defeated.
				shouldFire = roundIndex >= 2 and anyPlayerLowHp() and enemiesHalfDefeated()
			elseif gate == "necromancer" then
				-- Round 2+ when >50% enemies defeated.
				shouldFire = roundIndex >= 2 and enemiesHalfDefeated()
			elseif gate == "divine" then
				-- Rare; requires >=50% friendly KO'd AND map >=5 levels above highest friendly.
				local players, kod, highest = 0, 0, 1
				for _, u in ipairs(state.units) do
					if u.side == "Player" then
						players = players + 1
						if not u.isAlive then kod = kod + 1 end
						if (u.level or 1) > highest then highest = u.level or 1 end
					end
				end
				local koRatioOk = players > 0 and (kod / players) >= 0.5
				local mapLevel = state.mapLevel or state.MAP_LEVEL or 1
				local mapLevelOk = mapLevel >= (highest + 5)
				shouldFire = koRatioOk and mapLevelOk
			elseif gate == "earthElemental" then
				-- Spawn only when the Earthquake crisis is NOT currently active.
				local active = _weatherService and _weatherService.GetActiveCondition and _weatherService.GetActiveCondition()
				shouldFire = (active ~= "Earthquake")
			elseif gate == "round2" then
				shouldFire = roundIndex >= 2
			else
				-- Generic "roundN" gate string, if any.
				local rnum = type(gate) == "string" and string.match(gate, "round(%d+)")
				shouldFire = rnum ~= nil and roundIndex >= tonumber(rnum)
			end

			if shouldFire then
				-- Conditional events count toward the 0-3 budget and respect the single
				-- active slot: fire now if free, otherwise QUEUE until it frees (user rule).
				if (state.bfFiredCount or 0) + #(state.bfPendingQueue or {}) < (state.bfBudget or 0) then
					c.fired = true
					if state.bfActiveEvent == nil then
						BattlefieldEventService._fireEvent(state, rng, def, roundIndex)
					else
						state.bfPendingQueue = state.bfPendingQueue or {}
						table.insert(state.bfPendingQueue, def)
						print("[BattlefieldEventService] Queued conditional event: " .. name)
					end
				end
			end
		end
	end
end

-- Neutral-side turn behaviour (routed from Main.runAiTurn). Returns a simple
-- action descriptor the caller commits, or nil for Wait.
function BattlefieldEventService.NeutralAction(unit, state)
	local kind = unit and unit.eventKind
	local fn = kind and NeutralBehaviors[kind]
	if fn then
		return fn(unit, state)
	end
	return nil  -- default: Wait (passive neutral)
end

-- Resolve an Interact on an event unit/NPC (routed from CommandService where
-- applicable). Filled in the handler steps.
function BattlefieldEventService.OnEventUnitTurn(unit, state, rng)
	if not unit or not unit.isAlive then return end

	if unit.thiefBehavior and _statusService and _statusService.ApplyStatus then
		if not (_statusService.HasStatus and _statusService.HasStatus(unit, "Hide")) then
			_statusService.ApplyStatus(unit, "Hide", "Thief")
		end
	end

	if unit.trailEffect and _tileEffectService and _tileEffectService.ApplyTileEffect then
		_tileEffectService.ApplyTileEffect(unit.tileX, unit.tileY, unit.trailEffect, unit.id, state.units)
		if unit.trailEffect2 then
			_tileEffectService.ApplyTileEffect(unit.tileX, unit.tileY, unit.trailEffect2, unit.id, state.units)
		end
	end

	if unit.eventName == "Monster Hunter" and _tileEffectService and _tileEffectService.ApplyTileEffect then
		_tileEffectService.ApplyTileEffect(unit.tileX, unit.tileY, "Snare Trap", unit.id, state.units)
	end

	if unit.strikesHighestElevation then
		local best, bestE = nil, -math.huge
		for _, u in ipairs(state.units) do
			if u.isAlive and not u.isGroundTarget and u.id ~= unit.id then
				local e = GameConstants.GetElevation(u.tileX, u.tileY)
				if e > bestE then bestE, best = e, u end
			end
		end
		if best then
			local dmg = math.floor((best.maxHp or 0) * 0.20)
			best.currentHp = math.max(0, (best.currentHp or 0) - dmg)
			if best.currentHp <= 0 then best.isAlive = false end
			if _broadcaster and _broadcaster.UnitStateChanged then _broadcaster.UnitStateChanged(best) end
		end
	end

	if unit.deathRipple then
		for _, u in ipairs(state.units) do
			if u.isAlive and not u.isGroundTarget and u.id ~= unit.id then
				local isUndead = false
				if u.statusInstances then
					for _, inst in ipairs(u.statusInstances) do if inst.id == "Undead" then isUndead = true break end end
				end
				if u.raceId == "RACE-ZOMBIE" or u.raceId == "RACE-VAMPIRE" then isUndead = true end
				if not isUndead then
					local dmg = math.floor((u.maxHp or 0) * 0.10)
					u.currentHp = math.max(0, (u.currentHp or 0) - dmg)
					if u.currentHp <= 0 then u.isAlive = false end
					if _broadcaster and _broadcaster.UnitStateChanged then _broadcaster.UnitStateChanged(u) end
				end
			end
		end
	end

	if unit.floodsTiles and _tileReshaper then
		local t = GameConstants.GetTerrainId and GameConstants.GetTerrainId(unit.tileX, unit.tileY)
		if t ~= "Shallow Water" and t ~= "Deep Water" then
			_tileReshaper(unit.tileX, unit.tileY, "Shallow Water", nil)
		end
	end

	if unit.bardAura and _statusService and _statusService.ApplyStatus and rng then
		local pool = (rng:NextNumber() < 0.5) and BARD_BUFFS or BARD_DEBUFFS
		local pick = pool[rng:NextInteger(1, #pool)]
		for _, u in ipairs(state.units) do
			if u.isAlive and not u.isGroundTarget then
				_statusService.ApplyStatus(u, pick, "Wandering Bard")
			end
		end
	end

	if unit.traitorFlips and not unit.traitorFlipped then
		local enemiesAlive = #livingBySide(state, "Enemy")
		local enemiesTotal = state.enemyCountAtStart or (enemiesAlive + 1)
		if enemiesTotal > 0 and enemiesAlive <= enemiesTotal * 0.25 then
			unit.side = "Neutral"
			unit.traitorFlipped = true
			if _statusService and _statusService.RemoveDispellable then
				_statusService.RemoveDispellable(unit)
			end
			if _broadcaster and _broadcaster.UnitStateChanged then _broadcaster.UnitStateChanged(unit) end
			print("[BattlefieldEventService] Traitor flipped to Neutral ally.")
		end
	end
end

function BattlefieldEventService.ResolveInteract(ctx)
	return false, "not implemented"
end

-- Expose internals for the later build steps to populate without re-opening the
-- module header (kept local-first; these accessors avoid global leakage).
function BattlefieldEventService._Handlers() return Handlers end
function BattlefieldEventService._NeutralBehaviors() return NeutralBehaviors end

return BattlefieldEventService
