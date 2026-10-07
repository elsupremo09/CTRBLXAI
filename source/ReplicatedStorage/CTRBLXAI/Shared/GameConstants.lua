-- GameConstants.lua
-- CTRBLXAI | Shared numeric constants (Slice 3: Skills and Real Combat)
--
-- Single source of truth for constants that are used by more than one
-- server module. Require this module instead of defining local copies.
--
-- Location: ReplicatedStorage/CTRBLXAI/Shared/GameConstants
-- (ReplicatedStorage so both server and future client modules can access it)

local GameConstants = {}

--------------------------------------------------
-- TIMELINE  (from DB: core_stats — Timeline AP RT)
--------------------------------------------------

GameConstants.BASE_RT_STANDARD = 400
GameConstants.AP_PER_TURN_STANDARD = 2

GameConstants.BASE_RT_BOSS     = 300
GameConstants.AP_PER_TURN_BOSS = 3

GameConstants.REST_RT_MULTIPLIER = 0.75

--------------------------------------------------
-- ACTION RT COST MULTIPLIERS
--------------------------------------------------

GameConstants.MOVE_RT_FACTOR         = 0.0625
GameConstants.BASIC_ATTACK_RT_FACTOR = 0.10
-- Guard
GameConstants.GUARD_MITIGATION      = 0.35   -- base 35% damage reduction
GameConstants.GUARD_CAP             = 0.80   -- maximum Guard mitigation (passives can add up to cap)
GameConstants.GUARD_RT_BASE_FACTOR  = 0.10   -- round(Modified Base RT × this)
GameConstants.GUARD_OFFHAND_WT_FACTOR = 0.50 -- + 50% of Effective Armor Off-Hand WT


--------------------------------------------------
-- ELEVATION  (from DB: movement_targeting — Elevation & Displacement)
--------------------------------------------------

-- Empty default — overwritten by SetGeneratedMap() from MapService
-- output before battle starts. Functions below read from this table.
GameConstants.ELEVATION_MAP = {}

function GameConstants.GetElevation(tileX, tileY)
	local row = GameConstants.ELEVATION_MAP[tileY]
	if row then
		return row[tileX] or 1
	end
	return 1
end

--------------------------------------------------
-- SPAN TILE PROTECTION + CHASM FLOORS (map_gen_rules rows 59/60/65/67)
-- Populated by SetGeneratedMap() from MapService (protectedSpanTiles /
-- chasmFloorTiles / floorEffects). Generated bridge spans (Plank Bridge, Rocky
-- Causeway, Drawbridge — plus repairBridgePass safety-net tiles, which are also
-- isBridge LAN crossings) are PROTECTED during battle: they never lose elevation,
-- never crack / collapse, and never change terrain (a burning Plank span keeps its
-- Wooden Floor deck and stays walkable). Tile EFFECTS (e.g. Burning) still apply.
--------------------------------------------------
GameConstants.SPAN_MAP        = {}   -- [y][x] = true for protected span tiles
GameConstants.CHASM_FLOOR_MAP = {}   -- [y][x] = true for deliberate gap (chasm floor) tiles
GameConstants.FLOOR_EFFECTS   = {}   -- { {x, y, effectId}, ... } permanent chasm-floor tile effects

function GameConstants.IsProtectedSpan(tileX, tileY)
	local row = GameConstants.SPAN_MAP[tileY]
	return row ~= nil and row[tileX] == true
end

function GameConstants.IsChasmFloor(tileX, tileY)
	local row = GameConstants.CHASM_FLOOR_MAP[tileY]
	return row ~= nil and row[tileX] == true
end

-- Molten / Tainted Ground ground effects (terrain_effects rows 14 / 16) were not
-- implemented anywhere before Slice 5. They are now applied by TileEffectService
-- on CHASM-FLOOR tiles (map_gen_rules row 65). true = chasm floors only (current,
-- smallest blast radius); set false to apply them on every Molten / Tainted tile
-- once the Designer confirms map-wide activation.
GameConstants.GROUND_EFFECTS_CHASM_ONLY = true

-- Lower a tile's elevation by `amount` (floor-clamped to 1). Used by explosion
-- tile-lowering and Cracked Ground collapse (Round 2 terrain pass 2026-09-29).
-- Returns the ACTUAL drop applied (may be < amount near the floor).
-- Protected span tiles never drop (map_gen_rules row 60 point 2).
function GameConstants.LowerElevation(tileX, tileY, amount)
	if GameConstants.IsProtectedSpan(tileX, tileY) then
		print(string.format("[GameConstants] Span (%d,%d) is PROTECTED — elevation unchanged", tileX, tileY))
		return 0
	end
	local row = GameConstants.ELEVATION_MAP[tileY]
	if not row then return 0 end
	local cur = row[tileX] or 1
	local target = math.max(1, cur - (amount or 1))
	row[tileX] = target
	return cur - target
end

--------------------------------------------------
-- TERRAIN TYPES  (from DB: terrain_effects)
--------------------------------------------------

GameConstants.TERRAIN_TYPES = {
	Clear = {
		id = "Clear", moveCost = 1,
		tags = { "Solid", "Natural" },
		occupyBonus = {},
		crossCost = 0,
		triggerEffect = nil,
		transformations = {},
	},
	Grassland = {
		id = "Grassland", moveCost = 1,
		tags = { "Solid", "Organic", "Flammable", "Blessed" },
		occupyBonus = { Holy = 0.15 },
		crossCost = 0,
		triggerEffect = nil,
		transformations = { Fire = "Sand", Dark = "Tainted Ground" },
	},
	["Clover Field"] = {
		id = "Clover Field", moveCost = 1,
		tags = { "Solid", "Organic", "Flammable", "Blessed", "Lucky" },
		occupyBonus = { LUK = 0.30 },   -- stat bonus, not element
		crossCost = 0,
		triggerEffect = nil,
		transformations = { Fire = "Sand", Dark = "Tainted Ground" },
	},
	["Wooden Floor"] = {
		id = "Wooden Floor", moveCost = 1,
		tags = { "Solid", "Organic", "Flammable" },
		occupyBonus = {},
		crossCost = 0,
		triggerEffect = nil,
		transformations = { Fire = "Clear" },
	},
	Rocky = {
		id = "Rocky", moveCost = 1,
		tags = { "Solid", "Stone", "Stable", "Earth" },
		occupyBonus = { Earth = 0.30 },
		crossCost = 0,
		triggerEffect = "KnockbackImmunity",
		transformations = {},   -- Explosion@≥8→Cracked: needs runtime check
	},
	Sand = {
		id = "Sand", moveCost = 1,   -- DB total 2, halved → 1 (Sep 28 2026 balance change)
		tags = { "Solid", "Loose", "Earth" },
		occupyBonus = { Earth = 0.15 },
		crossCost = 0,   -- cost consolidated into moveCost (crossCost retired)
		triggerEffect = nil,
		transformations = { Fire = "Molten" },
	},
	Mud = {
		id = "Mud", moveCost = 1,   -- DB total 2, halved → 1 (Sep 28 2026 balance change)
		tags = { "Liquid", "Soft", "Conductive", "Earth", "Sticky" },
		occupyBonus = { Earth = 0.15, Water = 0.15 },
		crossCost = 0,   -- cost consolidated into moveCost
		triggerEffect = nil,
		transformations = { Fire = "Rocky" },
	},
	Swamp = {
		id = "Swamp", moveCost = 1.5,   -- DB total 3, halved → 1.5 (Sep 28 2026 balance change)
		tags = { "Liquid", "Organic", "Sticky", "Water", "Dark" },
		occupyBonus = { Water = 0.15, Dark = 0.15 },
		crossCost = 0,   -- cost consolidated into moveCost
		triggerEffect = nil,
		transformations = { Fire = "Rocky" },
	},
	["Shallow Water"] = {
		id = "Shallow Water", moveCost = 1,   -- DB total 2, halved → 1 (Sep 28 2026 balance change)
		tags = { "Liquid", "Conductive", "Water" },
		occupyBonus = { Water = 0.25 },
		crossCost = 0,   -- cost consolidated into moveCost
		triggerEffect = nil,
		transformations = { Ice = "Ice", Earth = "Mud" },
	},
	["Deep Water"] = {
		id = "Deep Water", moveCost = 1.5,   -- DB total 3, halved → 1.5 (Sep 28 2026 balance change)
		tags = { "Liquid", "Conductive", "Water", "Deep" },
		occupyBonus = { Water = 0.30 },
		crossCost = 0,   -- cost consolidated into moveCost
		triggerEffect = "Drowning",
		transformations = { Ice = "Ice" },
	},
	Ice = {
		id = "Ice", moveCost = 1,
		tags = { "Solid", "Frozen", "Slippery", "Water" },
		occupyBonus = { Water = 0.25 },
		crossCost = 0,
		triggerEffect = nil,   -- Sliding Knockback is a cross effect, not trigger
		transformations = { Fire = "Shallow Water" },
	},
	Metal = {
		id = "Metal", moveCost = 1,
		tags = { "Solid", "Metal", "Conductive" },
		occupyBonus = {},
		crossCost = 0,
		triggerEffect = nil,
		transformations = { Fire = "Molten" },
	},
	Molten = {
		id = "Molten", moveCost = 1,
		tags = { "Liquid", "Molten", "Fire", "Hazard" },
		occupyBonus = { Fire = 0.30 },
		crossCost = 0,
		triggerEffect = "MoltenBurn",   -- End Turn: Burn 25% MaxHP
		transformations = { Water = "Rocky" },
	},
	["Magic Circle"] = {
		id = "Magic Circle", moveCost = 1,
		tags = { "Solid", "Arcane" },
		occupyBonus = {},   -- INT +30%, Spell Range +1, +20% spell dmg recv: needs stat/range modifier system
		crossCost = 0,
		triggerEffect = nil,
		transformations = { Dark = "Tainted Ground" },
	},
	["Tainted Ground"] = {
		id = "Tainted Ground", moveCost = 1,
		tags = { "Solid", "Corrupted", "Dark" },
		occupyBonus = {},   -- MP drain/restore: needs periodic tick system
		crossCost = 0,
		triggerEffect = nil,
		transformations = { Light = "Grassland" },
	},
	["Cracked Ground"] = {
		id = "Cracked Ground", moveCost = 1,
		tags = { "Solid", "Fragile" },
		occupyBonus = {},
		crossCost = 0,
		triggerEffect = "Collapse",   -- Explosion or WT>15 → Collapse
		transformations = {},
	},
	Quicksand = {
		id = "Quicksand", moveCost = 1,
		tags = { "Loose", "Hazard", "Sticky" },
		occupyBonus = {},
		crossCost = 0,   -- movement prohibited (pathfinding blocker, not cost)
		triggerEffect = "Sinking",
		transformations = { Water = "Mud" },
	},
	["Monolith (One-way)"] = {
		id = "Monolith (One-way)", moveCost = 1,
		tags = { "Solid", "Portal" },
		occupyBonus = {},
		crossCost = 0,
		triggerEffect = "RandomTeleport",
		transformations = {},
	},
	["Monolith (Two-way)"] = {
		id = "Monolith (Two-way)", moveCost = 1,
		tags = { "Solid", "Portal" },
		occupyBonus = {},
		crossCost = 0,
		triggerEffect = nil,   -- cross effect: paired portal
		transformations = {},
	},
}

-- Empty default — overwritten by SetGeneratedMap() from MapService
-- output before battle starts. Functions below read from this table.
GameConstants.TERRAIN_MAP = {}

-- Check if a terrain type is impassable (cannot be entered by voluntary movement).
-- DB: Quicksand col_5 = "Movement prohibited"
function GameConstants.IsImpassableTerrain(tileX, tileY)
	local terrainId = GameConstants.GetTerrainId(tileX, tileY)
	-- Quicksand: movement prohibited
	if terrainId == "Quicksand" then return true end
	-- Deep Water: impassable for non-Amphibious units (caller checks race tag)
	-- For now, Deep Water is passable with +2 cost — Amphibious race restriction
	-- is handled at the caller level when races are implemented.
	return false
end

-- Check if a tile blocks AOE spread (Center Spread AOE).
-- DB: "Center Spread AOE does not pass through solid BlocksAOE barriers"
function GameConstants.BlocksAOE(tileX, tileY)
	return GameConstants.TileHasTag(tileX, tileY, "BlocksAOE")
end

function GameConstants.GetTerrainData(tileX, tileY)
	local terrainId = GameConstants.GetTerrainId(tileX, tileY)
	return GameConstants.TERRAIN_TYPES[terrainId] or GameConstants.TERRAIN_TYPES.Clear
end

function GameConstants.GetTerrainOccupyBonus(terrainId, element)
	local def = GameConstants.TERRAIN_TYPES[terrainId]
	if def and def.occupyBonus and def.occupyBonus[element] then
		return 1 + def.occupyBonus[element]
	end
	return 1
end

function GameConstants.GetTerrainCost(tileX, tileY)
	local row = GameConstants.TERRAIN_MAP[tileY]
	if row then
		local terrainId = row[tileX]
		if terrainId and GameConstants.TERRAIN_TYPES[terrainId] then
			return GameConstants.TERRAIN_TYPES[terrainId].moveCost
		end
	end
	return 1
end

function GameConstants.GetTerrainId(tileX, tileY)
	local row = GameConstants.TERRAIN_MAP[tileY]
	if row then
		return row[tileX] or "Clear"
	end
	return "Clear"
end

-- Set a tile's terrain id directly (no transformation lookup). Used for the
-- runtime Rocky@Elev>=8 -> Cracked Ground crack and Cracked Ground -> Rocky
-- collapse, neither of which is expressible via the transformations table.
function GameConstants.SetTerrainId(tileX, tileY, terrainId)
	if not GameConstants.TERRAIN_TYPES[terrainId] then return false end
	local row = GameConstants.TERRAIN_MAP[tileY]
	if not row then return false end
	row[tileX] = terrainId
	return true
end

--------------------------------------------------
-- TERRAIN TRANSFORMATION
-- When an element hits a terrain, the terrain may transform.
-- DB: terrain_effects.Transformations (e.g. Fire→Sand for Grassland)
-- TRG-013: one-pass processing; transform does not re-trigger.
--------------------------------------------------

function GameConstants.TransformTerrain(tileX, tileY, element)
	-- Protected spans keep their deck terrain (map_gen_rules row 60 point 4: a burnt
	-- Plank/Drawbridge span stays a walkable span; Wooden Floor Fire -> Clear skipped).
	if GameConstants.IsProtectedSpan(tileX, tileY) then return false, nil end
	local terrainId = GameConstants.GetTerrainId(tileX, tileY)
	local def = GameConstants.TERRAIN_TYPES[terrainId]
	if not def or not def.transformations then return false, nil end

	local newTerrainId = def.transformations[element]
	if not newTerrainId then return false, nil end
	if not GameConstants.TERRAIN_TYPES[newTerrainId] then return false, nil end

	-- Apply transformation: mutate TERRAIN_MAP
	local row = GameConstants.TERRAIN_MAP[tileY]
	if row then
		row[tileX] = newTerrainId
		print(string.format("[GameConstants] Terrain transform: %s → %s at (%d,%d) by %s",
			terrainId, newTerrainId, tileX, tileY, element))
		return true, newTerrainId
	end
	return false, nil
end

--------------------------------------------------
-- TILE EFFECTS  (from DB: terrain_effects — Tile Effect Catalog)
-- Data definitions only.  Runtime tile-effect lifecycle (apply,
-- tick, remove, react) requires a TileEffectService not yet built.
--------------------------------------------------

GameConstants.TILE_EFFECTS = {
	Burning = {
		id = "Burning", element = "Fire", hazard = true,
		tags = { "Fire", "Hazard" },
		durationCt = 900,
		occupyEffect  = "Burn",          -- inflicts Burn status
		crossEffect   = "Burn",
		tickCt = 300, tickDamage = 0.15, tickElement = "Fire",  -- 15% MaxHP
		reactions = { Water = "Steam" },
		-- Spread (DB spec rows 40-43): every 500 CT, ignite orthogonally-adjacent
		-- Flammable base terrain within |elev| <= 1. New tiles start at full 900 CT.
		-- Base terrain is NOT transformed by spread. TRG-012 guards cadence.
		spread = {
			cadenceCt = 500, radius = 1, adjacency = "orthogonal",
			elevDelta = 1, targetTag = "Flammable",
			newDurationCt = 900, transformsTerrain = false,
		},
	},
	Wet = {
		id = "Wet", element = "Water", hazard = false,
		tags = { "Water", "Conductive" },
		durationCt = 1500,
		occupyEffect  = nil,             -- Water Skills +25% (handled as occupy bonus)
		occupyBonus   = { Water = 0.25 },
		reactions = { Fire = "Steam", Ice = "Frozen", Electric = "Static Cloud" },  -- Electric on Wet → Static Cloud (ruling 2026-09-29)
	},
	Frozen = {
		id = "Frozen", element = "Ice", hazard = false,
		tags = { "Frozen", "Slippery" },
		durationCt = 900,
		occupyBonus   = { Water = 0.25 },  -- Water +25%
		occupyDamageMod = { Fire = -0.5 },  -- Fire damage received -50% (audit row 63)
		crossEffect   = "SlidingKnockback",
		reactions = { Fire = "Wet" },
	},
	Steam = {
		id = "Steam", element = "Water", hazard = false,
		tags = { "Airborne", "Conductive" },
		durationCt = 900,
		occupyBonus   = { Water = 0.25 },
		occupyEvasion = 0.25,   -- +25% Evasion (audit row 57; mapping formula parked pending Electric pass)
		reactions = { Electric = "Static Cloud", Wind = nil },  -- Wind clears; Electric on Steam → Static Cloud
	},
	["Static Cloud"] = {
		id = "Static Cloud", element = "Electric", hazard = true,
		tags = { "Airborne", "Conductive", "Electric" },
		durationCt = 900,
		tickCt = 300, tickDamage = 0.15, tickElement = "Electric",
		reactions = { Wind = nil },  -- Wind clears
	},
	["Poison Cloud"] = {
		id = "Poison Cloud", element = "Poison", hazard = false,
		tags = { "Airborne", "Poison" },
		durationCt = 1500,
		occupyEffect  = "Poison",
		crossEffect   = "Poison",
		reactions = { Fire = "Explosion" },  -- Fire → Explosion (source consumed)
		-- Explosion (DB spec rows 47-52): generic explosion tag carries NO blanket HP
		-- damage — damage is PER-SOURCE (barrel bomb / terrain chain supplies payload).
		-- Intrinsic = tile-lowering + terrain-chain trigger + chain queue (TRG-011).
		explosion = { pattern = "diamond", radius = 1, element = "Fire",
			chainReductionFactor = 0.5, maxChainDepth = 4 },
	},

	-- ===== Effects added 2026-09-29 (were omitted; DB audit rows 60-62) =====
	Oily = {
		id = "Oily", element = "Oil", hazard = false,
		tags = { "Flammable", "Slippery" },
		durationCt = -1,   -- Unlimited (persists until removed/exploded)
		-- Occupy: knockback slide continues until first non-Oily/non-Ice tile
		-- (slide-extension MECHANIC, handled by TileCrossEffectService, not a status).
		slideExtension = true,
		reactions = { Fire = "Explosion" },  -- Fire → Explosion; Oily removed after
		explosion = { pattern = "diamond", radius = 1, element = "Fire",
			chainReductionFactor = 0.5, maxChainDepth = 4 },
	},
	["Tar Pit"] = {
		id = "Tar Pit", element = "Earth", hazard = true,
		tags = { "Sticky" },
		durationCt = -1,   -- Unlimited
		crossCostBonus = 1.5,   -- effective move cost to cross (RESOLVED 2026-09-29 = 1.5)
		petrifyOnConsecutiveTurns = 2,  -- 2 own turn-ends on any Tar Pit → Petrify
		reactions = { Fire = "Burning" },  -- Fire → Burning (DB terrain_effects)
	},
	Vines = {
		id = "Vines", element = "Nature", hazard = false,
		tags = { "Organic" },
		durationCt = -1,   -- Unlimited
		occupyEffect  = "Pinned",
		crossEffect   = "Pinned",
		reactions = { Fire = "Burning" },  -- Fire → Burning
	},
}
-- Oily, Tar Pit, Vines omitted — unlimited duration + complex
-- mechanics that need full TileEffectService.

--------------------------------------------------
-- BLOCKERS
--------------------------------------------------

-- Empty default — overwritten by SetGeneratedMap() from MapService
-- output before battle starts. Functions below read from this table.
GameConstants.BLOCKERS = {}

function GameConstants.IsBlocked(tileX, tileY)
	for _, b in ipairs(GameConstants.BLOCKERS) do
		if b.tileX == tileX and b.tileY == tileY then
			return true
		end
	end
	return false
end

-- Get blocker metadata at a tile (nil if no blocker).
function GameConstants.GetBlockerData(tileX, tileY)
	for _, b in ipairs(GameConstants.BLOCKERS) do
		if b.tileX == tileX and b.tileY == tileY then
			return b
		end
	end
	return nil
end

-- Check if a tile has a specific tag (on its blocker).
function GameConstants.TileHasTag(tileX, tileY, tag)
	local blocker = GameConstants.GetBlockerData(tileX, tileY)
	if blocker and blocker.tags then
		for _, t in ipairs(blocker.tags) do
			if t == tag then return true end
		end
	end
	return false
end

function GameConstants.GetBlockerAt(tileX, tileY)
	for _, b in ipairs(GameConstants.BLOCKERS) do
		if b.tileX == tileX and b.tileY == tileY then
			return b
		end
	end
	return nil
end

-- Remove ALL blocker entries at a tile (e.g. a Stone Pillar that fell and became a
-- walkable Rocky span, or a removed/destroyed solid object). Returns how many were
-- removed. Iterates backward so removal while looping is safe.
function GameConstants.RemoveBlockerAt(tileX, tileY)
	local removed = 0
	for i = #GameConstants.BLOCKERS, 1, -1 do
		local b = GameConstants.BLOCKERS[i]
		if b.tileX == tileX and b.tileY == tileY then
			table.remove(GameConstants.BLOCKERS, i)
			removed = removed + 1
		end
	end
	return removed
end

function GameConstants.HasBlockerTag(tileX, tileY, tag)
	local b = GameConstants.GetBlockerAt(tileX, tileY)
	if not b or not b.tags then return false end
	for _, t in ipairs(b.tags) do
		if t == tag then return true end
	end
	return false
end

--------------------------------------------------
-- MAP GENERATION BRIDGE
-- Populates hardcoded tables from generated map data.
-- Called by Main.server.lua after MapService.Generate().
--------------------------------------------------

function GameConstants.SetGeneratedMap(mapState)
	GameConstants.ELEVATION_MAP = mapState.elevationGrid
	GameConstants.TERRAIN_MAP   = mapState.terrainGrid
	GameConstants.OBJECT_MAP    = mapState.objectGrid or {}
	GameConstants.BLOCKERS      = mapState.blockers
	-- Span protection + chasm floors (map_gen_rules rows 59/60/65/67).
	local spanMap, chasmMap = {}, {}
	for _, s in ipairs(mapState.protectedSpanTiles or {}) do
		spanMap[s.y] = spanMap[s.y] or {}
		spanMap[s.y][s.x] = true
	end
	for _, c in ipairs(mapState.chasmFloorTiles or {}) do
		chasmMap[c.y] = chasmMap[c.y] or {}
		chasmMap[c.y][c.x] = true
	end
	GameConstants.SPAN_MAP        = spanMap
	GameConstants.CHASM_FLOOR_MAP = chasmMap
	GameConstants.FLOOR_EFFECTS   = mapState.floorEffects or {}
	print(string.format(
		"[GameConstants] SetGeneratedMap: %dx%d, %d blockers",
		#mapState.terrainGrid[1], #mapState.terrainGrid,
		#mapState.blockers))
end

--- Return the object name at tile (x, y), or nil if none.
function GameConstants.GetObjectAt(tileX, tileY)
	local row = GameConstants.OBJECT_MAP and GameConstants.OBJECT_MAP[tileY]
	return row and row[tileX] or nil
end

--------------------------------------------------
-- POSITIONAL DAMAGE MODIFIER
--------------------------------------------------

GameConstants.POSITIONAL_MODIFIER_PER_LEVEL = 0.10
GameConstants.POSITIONAL_MODIFIER_MIN       = 0.70
GameConstants.POSITIONAL_MODIFIER_MAX       = 1.30

function GameConstants.GetPositionalModifier(attackerTileX, attackerTileY, defenderTileX, defenderTileY)
	local aElev = GameConstants.GetElevation(attackerTileX, attackerTileY)
	local dElev = GameConstants.GetElevation(defenderTileX, defenderTileY)
	local diff  = aElev - dElev
	local mod   = 1 + GameConstants.POSITIONAL_MODIFIER_PER_LEVEL * diff
	return math.clamp(mod, GameConstants.POSITIONAL_MODIFIER_MIN, GameConstants.POSITIONAL_MODIFIER_MAX)
end

--------------------------------------------------
-- STATUS DEFINITIONS  (from DB: elements_statuses)
--
-- Slice 3 adds: Poison and Burn (DoT debuffs)
-- Poison: 5 turns, Damage = round(MaxHP × 0.15 × DebuffResistance)
--         Reapplication: refresh duration. Undead immune.
-- Burn:   3 turns, stored damage model.
--         On application: storedBurn = round(fireDamageDealt × 0.20)
--         Tick = round(storedBurn × DebuffResistance)
--         Reapplication: adds stored Burn damage and extends duration
--------------------------------------------------

GameConstants.STATUSES = {
	Slow = {
		id           = "Slow",
		description  = "RT costs increased by 10%.",
		kind         = "Debuff",
		duration     = 3,
		reapply      = "refresh",
		rtMultiplier = 1.10,
		dotType      = nil,
	},
	Poison = {
		id           = "Poison",
		description  = "Takes 15% Max HP damage each turn.",
		kind         = "Debuff",
		duration     = 5,
		reapply      = "refresh",
		rtMultiplier = nil,
		dotType      = "Poison",
		-- Damage = round(MaxHP × 0.15 × debuffResistance)
		-- debuffResistance defaults to 1.0 (no resistance system yet)
		dotFraction  = 0.15,
	},
	Burn = {
		id           = "Burn",
		description  = "Takes stored fire damage each turn. Accumulates on reapply.",
		kind         = "Debuff",
		duration     = 3,
		reapply      = "accumulate", -- adds stored damage + extends duration
		rtMultiplier = nil,
		dotType      = "Burn",
		-- storedBurn set on application; tick = round(storedBurn × debuffResistance)
		burnFraction = 0.20,
	},
	Guard = {
		id           = "Guard",
		description  = "Reduces incoming damage by 35%. Removed by hard CC.",
		kind         = "Buff",
		duration     = 2,        -- survives the EndTurn tick on the application turn;
		                         -- expires at EndTurn of the unit's NEXT ready turn
		reapply      = "refresh",
		dispellable  = true,     -- removed by Purge/Dispel
		removedByCC  = true,     -- removed by hard CC (Sleep, Petrify, Stun when defined)
		dotType      = nil,
	},

	-- ===== DAMAGE OVER TIME (new) =====

	Venom = {
		id           = "Venom",
		description  = "Takes 3% Max HP per stack each turn. Stacks on reapply.",
		kind         = "Debuff",
		duration     = nil,       -- Unlimited until cured
		reapply      = "stack",   -- Venom Strength +1 on reapply
	},

	Bleed = {
		id           = "Bleed",
		description  = "Takes 5% Max HP bonus damage when hit by physical attacks.",
		kind         = "Debuff",
		duration     = nil,
		durationCt   = 2000,
		reapply      = "chain",   -- Refresh self + apply Raptured
	},

	Raptured = {
		id           = "Raptured",
		description  = "Takes 2% Max HP damage per tile moved.",
		kind         = "Debuff",
		duration     = 5,
		reapply      = "chain",   -- Refresh self + apply Wounded
	},

	Wounded = {
		id           = "Wounded",
		description  = "Takes 15% Max HP damage on AP-spending actions.",
		kind         = "Debuff",
		duration     = 3,
		reapply      = "chain",   -- Refresh self + apply Bleed
	},

	-- ===== HAZARD CONDITIONS =====

	Drowning = {
		id           = "Drowning",
		description  = "Jump penalty -1 every 500 CT. KO at -5.",
		kind         = "Debuff",
		duration     = nil,       -- Unlimited while valid
		reapply      = "none",
		implemented  = false,     -- BLOCKED: needs water tile system
	},

	Sinking = {
		id           = "Sinking",
		description  = "Cannot move. Jump penalty -1 every 500 CT. KO at -5.",
		kind         = "Debuff",
		duration     = nil,       -- Unlimited while valid
		reapply      = "none",
		blocks       = { Move = true },
		implemented  = false,     -- BLOCKED: needs sinking tile system
	},

	-- ===== DEBUFFS =====

	Blind = {
		id           = "Blind",
		description  = "Precision halved.",
		kind         = "Debuff",
		duration     = nil,
		durationCt   = 2000,
		reapply      = "refresh",
	},

	Confuse = {
		id           = "Confuse",
		description  = "Takes 30% of dealt damage as backlash.",
		kind         = "Debuff",
		duration     = 3,
		reapply      = "refresh",
	},

	Silence = {
		id           = "Silence",
		description  = "Cannot use skills. Interrupts channeling.",
		kind         = "Debuff",
		duration     = nil,
		durationCt   = 2000,
		reapply      = "refresh",
		blocks       = { Skills = true },
	},

	Mute = {
		id           = "Mute",
		description  = "Skill augments disabled. Base skills remain usable.",
		kind         = "Debuff",
		duration     = nil,
		durationCt   = 3000,
		reapply      = "refresh",
	},

	Break = {
		id           = "Break",
		description  = "Doctrine, race, and unit passives disabled.",
		kind         = "Debuff",
		duration     = nil,
		durationCt   = 3000,
		reapply      = "refresh",
	},

	Disarmed = {
		id           = "Disarmed",
		description  = "Cannot use basic attack.",
		kind         = "Debuff",
		duration     = nil,
		durationCt   = 3000,
		reapply      = "refresh",
		blocks       = { BasicAttack = true },
	},

	Pinned = {
		id           = "Pinned",
		description  = "Cannot move. Other actions unaffected.",
		kind         = "Debuff",
		duration     = nil,
		durationCt   = 1000,
		reapply      = "refresh",
		blocks       = { Move = true },
	},

	Crippled = {
		id           = "Crippled",
		description  = "Movement range and jump halved.",
		kind         = "Debuff",
		duration     = 5,
		reapply      = "refresh",
	},

	["Mana Burn"] = {
		id           = "Mana Burn",
		description  = "Skills cost 20% Max MP extra. Excess MP dealt as damage.",
		kind         = "Debuff",
		duration     = 3,
		reapply      = "refresh",
	},

	Petrify = {
		id           = "Petrify",
		description  = "Cannot act. RT frozen. Immune to new debuffs. Reduced damage taken.",
		kind         = "Debuff",
		duration     = nil,
		durationCt   = 1500,
		reapply      = "refresh",
		blocks       = { All = true },
		skipsTurn    = true,
	},

	-- ===== TEMPO MODIFIERS =====

	Haste = {
		id           = "Haste",
		description  = "RT costs reduced by 10%.",
		kind         = "Buff",
		duration     = 3,
		reapply      = "refresh",
		rtMultiplier = 0.90,
	},

	Frenzy = {
		id           = "Frenzy",
		description  = "Basic attack tempo increased.",
		kind         = "Buff",
		duration     = 3,
		reapply      = "refresh",
		-- DB (elements_statuses id 72) specifies "Basic Attack tempo only".
		-- Magnitude set by developer decision 2026-09-26: reduce the base-RT
		-- component of Basic Attack RT by 50%. Does NOT affect the weapon-WT
		-- component (applied to the base-RT portion only in calcBasicAttackBaseRt).
		basicAttackRtMult = 0.50,
	},

	Wet = {
		id           = "Wet",
		description  = "Movement RT increased. Fire damage halved. Ice may freeze.",
		kind         = "Debuff",
		duration     = 5,
		reapply      = "refresh",
	},

	Frozen = {
		id           = "Frozen",
		description  = "All RT costs doubled. Physical/Water damage +50%. Fire removes.",
		kind         = "Debuff",
		duration     = 3,
		reapply      = "refresh",
	},

	-- ===== SPECIAL CONDITIONS =====

	Undead = {
		id           = "Undead",
		description  = "Dark heals. Holy damage doubled. Immune to Poison/Bleed family.",
		kind         = "Special",
		duration     = nil,       -- Permanent or temporary
		reapply      = "none",
	},

	Overflow = {
		id           = "Overflow",
		description  = "Pending clarification.",
		kind         = "Buff",
		duration     = 3,
		reapply      = "extend",
		implemented  = false,     -- BLOCKED: pending clarification
	},

	-- ===== HEALING / RESOURCE BUFFS =====

	Regeneration = {
		id           = "Regeneration",
		description  = "Heals 5% Max HP every 300 CT.",
		kind         = "Buff",
		duration     = nil,
		durationCt   = 3000,
		reapply      = "extend",
		-- DB: Final Heal = round(round(Max HP x 0.05) x (1 + VIT / 300)) every 300 CT.
		regenFraction = 0.05,
		regenIntervalCt = 300,
	},

	Recharge = {
		id           = "Recharge",
		description  = "Restores 5% Max MP every 300 CT.",
		kind         = "Buff",
		duration     = nil,
		durationCt   = 1200,
		reapply      = "refresh",
		-- DB: on application restore round(Max MP x 0.10) min 1; then round(Max MP x 0.05) min 1
		-- at 300, 600, 900, 1200 CT. Current MP cannot exceed Max MP.
		rechargeImmediateFraction = 0.10,
		rechargeTickFraction = 0.05,
		rechargeIntervalCt = 300,
	},

	-- ===== COMBAT BUFFS =====

	Hide = {
		id           = "Hide",
		description  = "Untargetable. Next attack gains +50% hit quality. Broken by offensive action.",
		kind         = "Buff",
		duration     = 3,
		reapply      = "refresh",
	},

	Blessed = {
		id           = "Blessed",
		description  = "Hit quality +25%.",
		kind         = "Buff",
		duration     = 4,
		reapply      = "refresh",
		-- DB: Final Hit Quality +0.25 (additive to final HQ, on the afflicted unit's attacks).
		hitQualityMod = 0.25,
	},

	Cursed = {
		id           = "Cursed",
		description  = "Hit quality -25%.",
		kind         = "Debuff",
		duration     = 4,
		reapply      = "refresh",
		-- DB: Final Hit Quality -0.25 (additive to final HQ, on the afflicted unit's attacks).
		hitQualityMod = -0.25,
	},

	Enlightened = {
		id           = "Enlightened",
		description  = "All stats +10% per stack.",
		kind         = "Buff",
		duration     = nil,
		durationCt   = 3000,
		reapply      = "stack",
	},

	-- ===== STATE BUFFS =====

	Flight = {
		id           = "Flight",
		description  = "Elevation +5. Ignores terrain costs. Incoming damage +30%.",
		kind         = "Buff",
		duration     = 3,
		reapply      = "refresh",
	},

	["Giant Transformation"] = {
		id           = "Giant Transformation",
		description  = "STR/VIT +20%. INT/DEX/AGI -20%.",
		kind         = "Buff",
		duration     = nil,
		durationCt   = 3000,
		reapply      = "refresh",
	},

	-- ===== COMBAT STATES =====

	["Knock-out"] = {
		id           = "Knock-out",
		description  = "Cannot act. Removed from battle after 3000 CT if not revived.",
		kind         = "Special",
		duration     = nil,
		durationCt   = 3000,
		reapply      = "none",
		blocks       = { All = true },
		skipsTurn    = true,
	},

	Rush = {
		id           = "Rush",
		description  = "Movement range +3. DEX -20%.",
		kind         = "Buff",
		duration     = 4,
		reapply      = "refresh",
	},

	Weakened = {
		id           = "Weakened",
		description  = "All stats -10%.",
		kind         = "Debuff",
		duration     = nil,
		durationCt   = 2000,
		reapply      = "refresh",
	},

	-- Debuff Resistance -10 percentage points (Veil of Weakness, DOC-SHADOWBINDER-01,
	-- CTRBLXAI.db skills: "reduce Debuff Resistance by 10 percentage points for
	-- 1500 CT before resistance/boss handling"). Refresh; does not stack.
	-- Applied in StatusService.GetDebuffResist. Id matches the existing Theme icon.
	["Debuff Res Down"] = {
		id           = "Debuff Res Down",
		description  = "Debuff Resistance -10 points.",
		kind         = "Debuff",
		duration     = nil,
		durationCt   = 1500,
		reapply      = "refresh",
		debuffResistPenalty = 0.10,
	},
	-- Meditate (DOC-ASCETIC-01, 2026-10-07): Debuff Resistance +10 points for 1000 CT,
	-- refresh. Same scale as Debuff Res Down (GetDebuffResist multiplier -0.10).
	["Debuff Res Up"] = {
		id           = "Debuff Res Up",
		description  = "Debuff Resistance +10 points.",
		kind         = "Buff",
		duration     = nil,
		durationCt   = 1000,
		reapply      = "refresh",
		debuffResistBonus = 0.10,
	},
	-- Mana Surge (DOC-ARCANIST-01, 2026-10-07): the next eligible skill committed
	-- within 1000 CT gains Skill Potency +10%; consumed at that commit
	-- (CommandService ValidateAndCommit). Refresh on recast.
	["Mana Surge"] = {
		id           = "Mana Surge",
		description  = "Next skill: Skill Potency +10%.",
		kind         = "Buff",
		duration     = nil,
		durationCt   = 1000,
		reapply      = "refresh",
		potencyBonusMult = 1.10,
	},
	-- Misdirection (DB skills DOC-TRICKSTER-01, 2026-10-07): one trigger; the
	-- redirect itself is resolved in CommandService (applyMisdirection).
	["Misdirection"] = {
		id           = "Misdirection",
		description  = "First enemy single-target attack on this unit is redirected to an adjacent valid target.",
		kind         = "Buff",
		duration     = nil,
		durationCt   = 1000,
		reapply      = "refresh",
	},

	-- Doctrine signature buffs (2026-10-07; DB skills rows DOC-VANGUARD-01 /
	-- DOC-TACTICIAN-01 / DOC-WARLORD-01). 1000 CT, refresh, no stack.
	-- stabilityOffset -> StatusService.GetStabilityModifier (push distance)
	-- damageTakenMult -> StatusService.GetDamageReceivedMultiplier (direct hits)
	-- moveRtMult      -> StatusService.GetMovementRtMultiplier
	-- moveOffset / attackMult use the existing readers.
	["Hold the Line"] = {
		id              = "Hold the Line",
		description     = "Stability +2. Direct damage received -15%.",
		kind            = "Buff",
		duration        = nil,
		durationCt      = 1000,
		reapply         = "refresh",
		stabilityOffset = 2,
		damageTakenMult = 0.85,
	},
	["Coordinated Advance"] = {
		id           = "Coordinated Advance",
		description  = "Movement Range +2. Movement RT -20%.",
		kind         = "Buff",
		duration     = nil,
		durationCt   = 1000,
		reapply      = "refresh",
		moveOffset   = 2,
		moveRtMult   = 0.80,
	},
	["War Cry"] = {
		id              = "War Cry",
		description     = "Direct damage dealt +10%. Stability +1.",
		kind            = "Buff",
		duration        = nil,
		durationCt      = 1000,
		reapply         = "refresh",
		attackMult      = 1.10,
		stabilityOffset = 1,
	},

	-- ===== HARD CONTROL =====

	Sleep = {
		id           = "Sleep",
		description  = "Cannot act. Damage breaks sleep. Heals 3% per 200 CT.",
		kind         = "Debuff",
		duration     = 2,
		reapply      = "none",
		blocks       = { All = true },
		skipsTurn    = true,
	},

	["Sleep Immunity"] = {
		id           = "Sleep Immunity",
		description  = "Immune to Sleep.",
		kind         = "Buff",
		duration     = 2,
		reapply      = "refresh",
		undispellable = true,
	},

	-- ===== DEFERRED =====

	Stun = {
		id           = "Stun",
		description  = "Cannot act.",
		kind         = "Debuff",
		duration     = nil,
		reapply      = "refresh",
		blocks       = { All = true },
		skipsTurn    = true,
		implemented  = false,     -- DEFERRED: no DB definition yet
	},

	-- ===== REACTION STANCES =====

	-- Shared by Riposte Stance (DOC-DUELIST-01) and Counter Stance (SKL-COUNTER-STANCE).
	-- Developer decision 2026-09-28 (overrides DB max-2 / melee-only / single-use):
	-- counters EVERY eligible direct hit from an attacker inside this unit's
	-- equipped-weapon basic-attack reach; the balancer is RT — each counter adds
	-- the unit's basic-attack RT cost to its remainingRt. The casting skill stamps
	-- its own counter power on the instance (inst.counterPowerMult).
	CounterStance = {
		id           = "CounterStance",
		description  = "Counterattacks every hit from an attacker within basic-attack reach. Each counter delays this unit's next turn.",
		kind         = "Buff",
		duration     = nil,
		durationCt   = 1000,   -- DB: Riposte Stance / Counter Stance duration 1000 CT
		reapply      = "refresh",
		dispellable  = true,
		counterPowerMult = 0.85, -- fallback only; skills stamp their own value on the instance
	},

	-- ===== MAP-OBJECT TIMED BUFFS (Slice 5) =====
	-- Data-driven buff mechanism: these statuses carry optional modifier fields
	-- (statPctMod / rtMultiplier / moveOffset / jumpOffset / physDamageMult /
	-- spellDamageMult / attackMult / defenseMult) that the read paths honor.
	-- Magnitudes/durations come from the Designer's objects_encounters catalog.
	-- All doesNotStack=true (reapply=refresh -> one instance, refresh duration).
	["Banner Blessing"] = {
		id           = "Banner Blessing",
		description  = "+15% to all primary stats.",
		kind         = "Buff",
		duration     = nil,
		durationCt   = 1500,
		reapply      = "refresh",
		doesNotStack = true,
		statPctMod   = { STR = 0.15, AGI = 0.15, INT = 0.15, VIT = 0.15, DEX = 0.15, LUK = 0.15 },
	},
	["Cursed Aura"] = {
		id           = "Cursed Aura",
		description  = "+20% base RT (acts slower).",
		kind         = "Debuff",
		duration     = nil,
		durationCt   = 1500,
		reapply      = "refresh",
		doesNotStack = true,
		rtMultiplier = 1.20,
	},
	["Spell Focus"] = {
		id             = "Spell Focus",
		description    = "+20% Spell Damage.",
		kind           = "Buff",
		duration       = nil,
		durationCt     = 1500,
		reapply        = "refresh",
		doesNotStack   = true,
		spellDamageMult = 1.20,
	},
	["Battle Rage"] = {
		id             = "Battle Rage",
		description    = "+20% Physical Damage.",
		kind           = "Buff",
		duration       = nil,
		durationCt     = 1500,
		reapply        = "refresh",
		doesNotStack   = true,
		physDamageMult = 1.20,
	},
	["War Rhythm"] = {
		id           = "War Rhythm",
		description  = "-15% base RT (acts faster).",
		kind         = "Buff",
		duration     = nil,
		durationCt   = 1500,
		reapply      = "refresh",
		doesNotStack = true,
		rtMultiplier = 0.85,
	},
	["Rune Ward"] = {
		id          = "Rune Ward",
		description = "+10% Attack and +10% Defense.",
		kind        = "Buff",
		duration    = nil,
		durationCt  = 1500,
		reapply     = "refresh",
		doesNotStack = true,
		attackMult  = 1.10,
		defenseMult = 1.10,
	},
	["Rally"] = {
		id          = "Rally",
		description = "+1 Move and +1 Jump.",
		kind        = "Buff",
		duration    = nil,
		durationCt  = 1500,
		reapply     = "refresh",
		doesNotStack = true,
		moveOffset  = 1,
		jumpOffset  = 1,
	},
	["Fortune Boon"] = {
		id           = "Fortune Boon",
		description  = "+50% LUK (raises Fortune).",
		kind         = "Buff",
		duration     = nil,
		durationCt   = 1500,
		reapply      = "refresh",
		doesNotStack = true,
		statPctMod   = { LUK = 0.50 },
	},
}

--------------------------------------------------
-- SKILL DEFINITIONS (Slice 3: expanded catalog)
--
-- Simplified for implementation. Full formulas from DB are adapted
-- for our current Effective Skill Level = 1 demo.
-- L = Effective Skill Level (using 1 for now)
-- Weapon WT = weaponWt on the unit
-- Weapon Attack Power = weaponDamage × (1 + STR/200) [for Physical]
--------------------------------------------------

-- Generated from CTRBLXAI.db skills table
-- 89 active skills (DOC-* doctrine skills excluded)
-- range = -1 means 'inherit weapon range' (resolved at runtime)
-- mpCost is base value at L=1; level scaling applied at runtime
-- rtMult is multiplier on Effective Weapon WT for RT cost

-- ============================================================
-- SKILL RANGE (user rulings 2026-10-07; DAT-001 / AP-021: ONE shared formula)
-- * Minimum range comes ONLY from the weapon. A skill that follows weapon range
--   (range = -1) uses the weapon's min AND max; a skill with its own range has
--   NO minimum (0). No default/hardcoded minimum (e.g. projectile min 2) exists.
-- * Each skill declares how much Bonus Skill Range it may apply (DB
--   skills.Targeting_Range): 1.0 = 100%, 0.5 = 50%; any skill NOT listed = 0%
--   (melee reach, self, weapon-range skills that state no share, 'Fixed N' with
--   no share stated, and the 3 rows whose text points to an unrelated U86 note).
-- * Bonus applied = floor(bonusSkillRange x share): a partial tile is never
--   granted (50% of 1 = 0), keeping range in whole tiles and never overshooting
--   the authored share.
-- ============================================================
GameConstants.SKILL_BONUS_RANGE_SHARE = table.freeze({
-- 100%
	["SKL-ARCANE-RENEWAL"] = 1.0,
	["SKL-BLOOD-PRICE"] = 1.0,
	["SKL-CHAIN-SPARK"] = 1.0,
	["SKL-DARK-RESTORATION"] = 1.0,
	["SKL-EARTHEN-LANCE"] = 1.0,
	["SKL-FESTERING-WOUND"] = 1.0,
	["SKL-FIRE-BOLT"] = 1.0,
	["SKL-FROSTBIND"] = 1.0,
	["SKL-GUARDIAN-S-PROJECTION"] = 1.0,
	["SKL-HEALING-LIGHT"] = 1.0,
	["SKL-HOLY-SMITE"] = 1.0,
	["SKL-IGNITE-GROUND"] = 1.0,
	["SKL-IGNITION-LANCE"] = 1.0,
	["SKL-MANA-SCORCH"] = 1.0,
	["SKL-METEOR-MARKER"] = 1.0,
	["SKL-MIASMA-CLOUD"] = 1.0,
	["SKL-MIND-FRACTURE"] = 1.0,
	["SKL-PHANTOM-EXCHANGE"] = 1.0,
	["SKL-PURGE"] = 1.0,
	["SKL-PYROCLASM"] = 1.0,
	["SKL-RAINFALL-ZONE"] = 1.0,
	["SKL-TIDAL-CRASH"] = 1.0,
	["SKL-TORRENT-SPEAR"] = 1.0,
	["SKL-TOXIC-NEEDLE"] = 1.0,
	["SKL-VOLTAIC-CHAIN"] = 1.0,
	-- Doctrine skills (UAT fix 2026-10-07: DOC- rows were missing)
	["DOC-TACTICIAN-01"] = 1.0,
	["DOC-SHADOWBINDER-01"] = 1.0,
	["DOC-CONJURER-02"] = 1.0,
	["DOC-CONJURER-03"] = 1.0,
-- 50%
	["SKL-ARCANE-BARRIER"] = 0.5,
	["SKL-BASTION-PROJECTION"] = 0.5,
	["SKL-BENEDICTION"] = 0.5,
	["SKL-FISSURE-LINE"] = 0.5,
	["SKL-FLASH-FREEZE"] = 0.5,
	["SKL-GLACIAL-WAVE"] = 0.5,
	["SKL-INVIGORATE"] = 0.5,
	["SKL-LIFE-LINK"] = 0.5,
	["SKL-MENDING-RAIN"] = 0.5,
	["SKL-RETRIBUTION-SHELL"] = 0.5,
	["SKL-SEAL-OF-SILENCE"] = 0.5,
	["SKL-STONE-PRISON"] = 0.5,
	["SKL-SUMMON-DECOY"] = 0.5,
	["SKL-SUMMON-TURRET"] = 0.5,
	["SKL-SUMMON-WARD-TOTEM"] = 0.5,
	["SKL-VITAL-BARRIER"] = 0.5,
	["SKL-WEAPON-WARD"] = 0.5,
	["SKL-WITHER"] = 0.5,
	["DOC-ASCETIC-01"] = 0.5,
	["DOC-CONJURER-01"] = 0.5,
})

function GameConstants.GetSkillBonusRangeShare(skillId)
	return GameConstants.SKILL_BONUS_RANGE_SHARE[skillId] or 0
end

-- Returns maxRange, minRange, baseRange, appliedBonus for a skill cast by actor.
-- raceModifier: caller-supplied (RacePassiveService is server-only), default 0.
function GameConstants.CalcSkillRange(actor, skillDef, raceModifier)
	local followsWeapon = (skillDef.range == -1)
	local baseRange = followsWeapon and (actor.weaponMaxRange or 1) or (skillDef.range or 1)
	local bonusStat = (actor.derivedStats and actor.derivedStats.bonusSkillRange)
		or math.floor((actor.effectiveStats and actor.effectiveStats.INT or 10) / 75)
	local appliedBonus = math.floor(bonusStat * GameConstants.GetSkillBonusRangeShare(skillDef.id))
	local maxRange = math.max(1, baseRange + appliedBonus + (raceModifier or 0))
	local minRange = followsWeapon and (actor.weaponMinRange or 1) or 0
	return maxRange, minRange, baseRange, appliedBonus
end

-- ============================================================
-- SKILL ACTIVATION TIME (2026-10-07). frameworks 10/37: Activation Time is CT,
-- begins after Channel Time, cannot be interrupted once scheduled, and is NOT
-- reduced by DEX. Read from the ONE content source (ReplicatedStorage.Content.
-- SkillData, generated from CTRBLXAI.db) -- never copied into a second table
-- (DAT-001). Deferred require: SkillData requires nothing, but loading it at
-- call time keeps GameConstants free of new top-level dependencies (ARC-004).
-- Missing / non-numeric value = 0 (immediate).
-- ============================================================
local _skillDataForActivation = nil
function GameConstants.GetSkillActivationTime(skillId)
	if type(skillId) ~= "string" then return 0 end
	if _skillDataForActivation == nil then
		local ok, data = pcall(function()
			return require(game:GetService("ReplicatedStorage"):WaitForChild("Content", 10):WaitForChild("SkillData", 10))
		end)
		_skillDataForActivation = (ok and type(data) == "table") and data or false
	end
	local entry = _skillDataForActivation and _skillDataForActivation[skillId]
	local ct = entry and tonumber(entry.activationTime) or 0
	return math.max(0, math.floor(ct))
end

-- ============================================================
-- LEVEL-BASED SKILL MP COST (2026-10-07). project_rules 43 / frameworks 8 & 33:
--   MP Cost = round(Base + Growth x (Effective Skill Level - 1))
--   Effective Skill Level (ESL) = caster main-hand item level; rounded ONCE at the
--   final result (after the race/trait/doctrine/augment multipliers); may be 0.
-- ONE data source (DAT-001): each skill's base/growth is parsed once from its
-- mpCostFormula string in ReplicatedStorage.Content.SkillData (auto-generated from
-- CTRBLXAI.db, same loader as activation time). Accepted forms:
--   "round(B + G × (L - 1))"   (103 skills)
--   "B + round(G × (Effective Skill Level - 1))"   (SKL-STEAL; B is whole, so
--       the result equals round(B + G x (ESL - 1)))
--   "N"   (constant, e.g. "0" for Mana Surge / Meditate / Blood Price)
-- Anything else (or a skill absent from SkillData, e.g. summon/internal skills)
-- falls back to the skill def's flat mpCost, warned once.
-- ============================================================
local _mpCostCache = {} -- [skillId] = { base, growth } | false (= use flat mpCost)

local function parseMpFormula(formula)
	if type(formula) ~= "string" then return nil end
	local f = formula:gsub("×", "x"):gsub("%*", "x")
	f = f:gsub("^%s+", ""):gsub("%s+$", "")
	local b, g = f:match("^round%(%s*([%d%.]+)%s*%+%s*([%d%.]+)%s*x%s*%(%s*L%s*%-%s*1%s*%)%s*%)$")
	if not b then
		b, g = f:match("^([%d%.]+)%s*%+%s*round%(%s*([%d%.]+)%s*x%s*%(%s*Effective Skill Level%s*%-%s*1%s*%)%s*%)$")
	end
	if b then return { base = tonumber(b), growth = tonumber(g) } end
	local n = f:match("^([%d%.]+)$")
	if n then return { base = tonumber(n), growth = 0 } end
	return nil
end

function GameConstants.GetSkillMpFormula(skillId)
	if type(skillId) ~= "string" then return nil end
	local cached = _mpCostCache[skillId]
	if cached ~= nil then return cached or nil end
	if _skillDataForActivation == nil then
		local ok, data = pcall(function()
			return require(game:GetService("ReplicatedStorage"):WaitForChild("Content", 10):WaitForChild("SkillData", 10))
		end)
		_skillDataForActivation = (ok and type(data) == "table") and data or false
	end
	local entry = _skillDataForActivation and _skillDataForActivation[skillId]
	local parsed = entry and parseMpFormula(entry.mpCostFormula) or nil
	if entry and not parsed then
		warn(`[GameConstants] MP formula for {skillId} not understood ("{tostring(entry.mpCostFormula)}") — using flat mpCost`)
	end
	_mpCostCache[skillId] = parsed or false
	return parsed
end

-- Effective Skill Level = caster main-hand item level (frameworks 33). Units with
-- no main hand (summons, authored units) use ESL 1, i.e. the formula's base cost.
function GameConstants.GetEffectiveSkillLevel(actor)
	local mh = actor and actor.equipmentSlots and actor.equipmentSlots.MainHand
	local lvl = mh and tonumber(mh.itemLevel) or 1
	return math.max(1, math.floor(lvl))
end

-- Final MP cost of one cast BEFORE Mana Burn's flat extra.
--   multiplier = product of the caster's race/trait/doctrine/augment MP modifiers
--   (computed by CommandService, which owns those services; 1 if omitted).
-- Rounded once at the end, never below 0.
function GameConstants.CalcSkillMpCost(actor, skillDef, multiplier)
	if type(skillDef) ~= "table" then return 0 end
	local raw
	local f = GameConstants.GetSkillMpFormula(skillDef.id)
	if f then
		raw = f.base + f.growth * (GameConstants.GetEffectiveSkillLevel(actor) - 1)
	else
		raw = skillDef.mpCost or 0
	end
	return math.max(0, math.round(raw * (multiplier or 1)))
end

-- ============================================================
-- Fixed/level-based skill RT costs (DB skills.RT_Cost_Formula, authoritative
-- 2026-10-04). These 38 skills (28 SKL + 10 level-based doctrine) do NOT use the weapon-WT skill RT formula; they
-- charge round(base + growth × L) where L = Effective Skill Level = caster
-- main-hand item level (project_rules 42/43). SKL-STEAL uses round(growth×(L-1)).
-- Outer layers (Frozen ×2, Arcane Prodigy skill-RT trait) STILL apply on top,
-- same as weapon-WT skills (user ruling 2026-10-04).
GameConstants.SKILL_FIXED_RT = {
	["SKL-ARCANE-RENEWAL"] = { base = 70, growth = 0.25, eslMinus1 = false },
	["SKL-BATTLE-FURY"] = { base = 60, growth = 0.2, eslMinus1 = false },
	["SKL-BENEDICTION"] = { base = 80, growth = 0.3, eslMinus1 = false },
	["SKL-BLINDING-FLASH"] = { base = 70, growth = 0.25, eslMinus1 = false },
	["SKL-BLINK"] = { base = 40, growth = 0.2, eslMinus1 = false },
	["SKL-BULWARK-FIELD"] = { base = 80, growth = 0.3, eslMinus1 = false },
	["SKL-CONSECRATE"] = { base = 70, growth = 0.3, eslMinus1 = false },
	["SKL-COUNTER-STANCE"] = { base = 50, growth = 0.15, eslMinus1 = false },
	["SKL-FATED-ESCAPE"] = { base = 55, growth = 0.25, eslMinus1 = false },
	["SKL-FESTERING-WOUND"] = { base = 70, growth = 0.25, eslMinus1 = false },
	["SKL-FLASH-FREEZE"] = { base = 70, growth = 0.3, eslMinus1 = false },
	["SKL-INVIGORATE"] = { base = 70, growth = 0.25, eslMinus1 = false },
	["SKL-LIFE-LINK"] = { base = 70, growth = 0.25, eslMinus1 = false },
	["SKL-MENDING-RAIN"] = { base = 70, growth = 0.3, eslMinus1 = false },
	["SKL-MIASMA-CLOUD"] = { base = 70, growth = 0.3, eslMinus1 = false },
	["SKL-MIND-FRACTURE"] = { base = 70, growth = 0.25, eslMinus1 = false },
	["SKL-PHANTOM-EXCHANGE"] = { base = 60, growth = 0.35, eslMinus1 = false },
	["SKL-POISON-TRAP"] = { base = 60, growth = 0.2, eslMinus1 = false },
	["SKL-PURGE"] = { base = 70, growth = 0.25, eslMinus1 = false },
	["SKL-RAINFALL-ZONE"] = { base = 70, growth = 0.3, eslMinus1 = false },
	["SKL-SEAL-OF-SILENCE"] = { base = 70, growth = 0.3, eslMinus1 = false },
	["SKL-STATIC-FIELD"] = { base = 70, growth = 0.3, eslMinus1 = false },
	["SKL-STEAL"] = { base = 60, growth = 0.25, eslMinus1 = true },
	["SKL-SUMMON-DECOY"] = { base = 80, growth = 0.3, eslMinus1 = false },
	["SKL-SUMMON-TURRET"] = { base = 90, growth = 0.35, eslMinus1 = false },
	["SKL-SUMMON-WARD-TOTEM"] = { base = 80, growth = 0.3, eslMinus1 = false },
	["SKL-VANISHING-STEP"] = { base = 60, growth = 0.2, eslMinus1 = false },
	["SKL-WITHER"] = { base = 70, growth = 0.25, eslMinus1 = false },
	-- Level-based doctrine skills (DB authoritative) — same fixed-cost treatment.
	["DOC-ARCANIST-01"] = { base = 60, growth = 0.3, eslMinus1 = false },
	["DOC-ASCETIC-01"] = { base = 70, growth = 0.3, eslMinus1 = false },
	["DOC-CONJURER-01"] = { base = 90, growth = 0.35, eslMinus1 = false },
	["DOC-CONJURER-02"] = { base = 80, growth = 0.3, eslMinus1 = false },
	["DOC-CONJURER-03"] = { base = 85, growth = 0.3, eslMinus1 = false },
	["DOC-DUELIST-01"] = { base = 60, growth = 0.25, eslMinus1 = false },
	["DOC-SHADOWBINDER-01"] = { base = 80, growth = 0.35, eslMinus1 = false },
	["DOC-TACTICIAN-01"] = { base = 60, growth = 0.3, eslMinus1 = false },
	["DOC-TRICKSTER-01"] = { base = 60, growth = 0.25, eslMinus1 = false },
	["DOC-WARLORD-01"] = { base = 70, growth = 0.3, eslMinus1 = false },
}


-- Compute a fixed/level-based skill's authored RT cost. Returns nil if the skill is
-- NOT a fixed-cost skill (caller should then use the weapon-WT formula).
-- level = Effective Skill Level (caster main-hand item level), default 1.
-- SKL-STEAL form: base + round(growth × (L - 1)); all others: round(base + growth × L).
function GameConstants.CalcFixedSkillRt(skillId, level)
	local def = GameConstants.SKILL_FIXED_RT and GameConstants.SKILL_FIXED_RT[skillId]
	if not def then return nil end
	level = level or 1
	if def.eslMinus1 then
		return def.base + math.round(def.growth * (level - 1))
	end
	return math.round(def.base + def.growth * level)
end

GameConstants.SKILLS = {
	["SKL-FIRE-BOLT"] = {
		id            = "SKL-FIRE-BOLT",
		name          = "Fire Bolt",
		tags          = { "Direct Damage", "Fire" },
		targetRules   = "Enemy Unit",
		range         = 4,
		aoePattern    = nil,
		mpCost        = 3,
		rtMult        = 1.0,
		channelTime   = 0,
		power         = 1.1,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-FROSTBIND"] = {
		id            = "SKL-FROSTBIND",
		name          = "Frostbind",
		tags          = { "Direct Damage", "Debuff", "Ice" },
		targetRules   = "Enemy Unit",
		range         = 3,
		aoePattern    = nil,
		mpCost        = 3,
		rtMult        = 0.75,
		channelTime   = 100,
		power         = 0.7,
		inheritStr    = true,
		appliesStatus = "Frozen",
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-HEALING-LIGHT"] = {
		id            = "SKL-HEALING-LIGHT",
		name          = "Healing Light",
		tags          = { "Healing", "Holy" },
		targetRules   = "Ally Unit, Self",
		range         = 4,
		aoePattern    = nil,
		mpCost        = 4,
		rtMult        = 0.5,
		channelTime   = 100,
		power         = 0.3,
		inheritStr    = false,
		appliesStatus = nil,
		isHealing     = true,
		projectileType = "Direct",
	},
	["SKL-DARK-RESTORATION"] = {
		id            = "SKL-DARK-RESTORATION",
		name          = "Dark Restoration",
		tags          = { "Healing", "Direct Damage", "Dark" },
		targetRules   = "Ally Unit, Enemy Unit, Self",
		range         = 3,
		aoePattern    = nil,
		mpCost        = 5,
		rtMult        = 0.6,
		channelTime   = 150,
		power         = 0.35,
		inheritStr    = false,
		appliesStatus = nil,
		isHealing     = true,
		projectileType = "Direct",
	},
	["SKL-ARCANE-BARRIER"] = {
		id            = "SKL-ARCANE-BARRIER",
		name          = "Arcane Barrier",
		tags          = { "Shield", "Buff" },
		targetRules   = "Ally Unit, Self",
		range         = 3,
		aoePattern    = nil,
		mpCost        = 4,
		rtMult        = 0.5,
		channelTime   = 0,
		power         = 1.5,
		inheritStr    = false,
		appliesStatus = nil,
		isHealing     = false,
		isShield      = true,  -- shield-grant routing (2026-10-05)
		projectileType = "Direct",
	},
	["SKL-RAINFALL-ZONE"] = {
		id            = "SKL-RAINFALL-ZONE",
		name          = "Rainfall Zone",
		tags          = { "Debuff", "Water" },
		targetRules   = "Ground, including occupied Ground",
		range         = 4,
		aoePattern    = "Circle2",
		mpCost        = 5,
		rtMult        = 1.0,
		channelTime   = 0,
		power         = 0,
		inheritStr    = false,
		appliesStatus = "Wet",
		isHealing     = false,
		projectileType = "Direct",
		createsTileEffect = "Wet",   -- applies Wet tile effect to all AOE tiles
	},
	["SKL-STONE-PRISON"] = {
		id            = "SKL-STONE-PRISON",
		name          = "Stone Prison",
		tags          = { "Debuff", "Earth" },
		targetRules   = "Enemy Unit",
		range         = 3,
		aoePattern    = nil,
		mpCost        = 7,
		rtMult        = 1.0,
		channelTime   = 300,
		power         = 0,
		inheritStr    = false,
		appliesStatus = "Petrify",
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-CHAIN-SPARK"] = {
		id            = "SKL-CHAIN-SPARK",
		name          = "Chain Spark",
		tags          = { "Direct Damage", "Electric" },
		targetRules   = "Enemy Unit",
		range         = 4,
		aoePattern    = "Chain4",
		mpCost        = 6,
		rtMult        = 1.0,
		channelTime   = 100,
		power         = 0.8,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
		chainFalloff  = 0.80,   -- 100%, 80%, 64%, 51.2%
	},
	["SKL-METEOR-MARKER"] = {
		id            = "SKL-METEOR-MARKER",
		name          = "Meteor Marker",
		tags          = { "Direct Damage", "Fire", "Debuff" },
		targetRules   = "Ground, including occupied Ground",
		range         = 5,
		aoePattern    = "Spread3x3",
		mpCost        = 8,
		rtMult        = 1.4,
		channelTime   = 200,
		power         = 1.5,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Arc",
	},
	["SKL-PHANTOM-EXCHANGE"] = {
		id            = "SKL-PHANTOM-EXCHANGE",
		name          = "Phantom Exchange",
		tags          = { "Utility" },
		targetRules   = "Ally Unit",
		range         = 4,
		aoePattern    = nil,
		mpCost        = 4,
		rtMult        = 1.0,
		channelTime   = 0,
		power         = 0,
		inheritStr    = false,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-BLINK"] = {
		id            = "SKL-BLINK",
		name          = "Blink",
		tags          = { "Utility" },
		targetRules   = "Empty Tile",
		range         = 2,
		aoePattern    = nil,
		mpCost        = 3,
		rtMult        = 1.0,
		channelTime   = 0,
		power         = 0,
		inheritStr    = false,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-VITAL-BARRIER"] = {
		id            = "SKL-VITAL-BARRIER",
		name          = "Vital Barrier",
		tags          = { "Shield", "Buff" },
		targetRules   = "Ally Unit, Self",
		range         = 3,
		aoePattern    = nil,
		mpCost        = 4,
		rtMult        = 0.5,
		channelTime   = 100,
		power         = 0.5,
		inheritStr    = false,
		appliesStatus = nil,
		isHealing     = false,
		isShield      = true,  -- shield-grant routing (2026-10-05)
		projectileType = "Direct",
	},
	["SKL-FATED-ESCAPE"] = {
		id            = "SKL-FATED-ESCAPE",
		name          = "Fated Escape",
		tags          = { "Utility" },
		targetRules   = "Ally Unit",
		range         = 2,
		aoePattern    = nil,
		mpCost        = 4,
		rtMult        = 1.0,
		channelTime   = 100,
		power         = 0,
		inheritStr    = false,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-POWER-STRIKE"] = {
		id            = "SKL-POWER-STRIKE",
		name          = "Power Strike",
		tags          = { "Direct Damage", "Physical" },
		targetRules   = "Enemy Unit",
		range         = -1,
		aoePattern    = "InheritWeapon",
		mpCost        = 3,
		rtMult        = 1.25,
		channelTime   = 0,
		power         = 1.25,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Inherit",
	},
	["SKL-SWEEPING-CUT"] = {
		id            = "SKL-SWEEPING-CUT",
		name          = "Sweeping Cut",
		tags          = { "Direct Damage", "Physical" },
		targetRules   = "Enemy Unit",
		range         = 1,
		aoePattern    = "Cleave",
		mpCost        = 4,
		rtMult        = 1.5,
		channelTime   = 0,
		power         = 0.9,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-CRUSHING-ADVANCE"] = {
		id            = "SKL-CRUSHING-ADVANCE",
		name          = "Crushing Advance",
		tags          = { "Direct Damage", "Physical" },
		targetRules   = "Enemy Unit",
		range         = 1,
		aoePattern    = nil,
		mpCost        = 4,
		rtMult        = 1.5,
		channelTime   = 100,
		power         = 1.1,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-LONGSHOT"] = {
		id            = "SKL-LONGSHOT",
		name          = "Longshot",
		tags          = { "Direct Damage", "Physical" },
		targetRules   = "Enemy Unit",
		range         = -1,
		aoePattern    = nil,
		mpCost        = 4,
		rtMult        = 1.5,
		channelTime   = 150,
		power         = 1.3,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-HAMSTRING"] = {
		id            = "SKL-HAMSTRING",
		name          = "Hamstring",
		tags          = { "Direct Damage", "Debuff", "Physical" },
		targetRules   = "Enemy Unit",
		range         = -1,
		aoePattern    = nil,
		mpCost        = 3,
		rtMult        = 0.75,
		channelTime   = 0,
		power         = 0.65,
		inheritStr    = true,
		appliesStatus = "Crippled",
		isHealing     = false,
		projectileType = "Inherit",
	},
	["SKL-EXECUTION-STROKE"] = {
		id            = "SKL-EXECUTION-STROKE",
		name          = "Execution Stroke",
		tags          = { "Direct Damage", "Physical" },
		targetRules   = "Enemy Unit",
		range         = -1,
		aoePattern    = "InheritWeapon",
		mpCost        = 6,
		rtMult        = 2.0,
		channelTime   = 200,
		power         = 1.4,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Inherit",
	},
	["SKL-FIELD-DRESSING"] = {
		id            = "SKL-FIELD-DRESSING",
		name          = "Field Dressing",
		tags          = { "Healing" },
		targetRules   = "Ally Unit, Self",
		range         = 1,
		aoePattern    = nil,
		mpCost        = 3,
		rtMult        = 0.75,
		channelTime   = 150,
		power         = 0.6,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = true,
		projectileType = "Direct",
	},
	["SKL-WEAPON-WARD"] = {
		id            = "SKL-WEAPON-WARD",
		name          = "Weapon Ward",
		tags          = { "Shield", "Buff" },
		targetRules   = "Ally Unit, Self",
		range         = 3,
		aoePattern    = nil,
		mpCost        = 4,
		rtMult        = 1.0,
		channelTime   = 0,
		power         = 0.3,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		isShield      = true,  -- shield-grant routing (2026-10-05)
		projectileType = "Direct",
	},
	["SKL-PURIFYING-FORM"] = {
		id            = "SKL-PURIFYING-FORM",
		name          = "Purifying Form",
		tags          = { "Utility", "Buff" },
		targetRules   = "Ally Unit, Self",
		range         = 3,
		aoePattern    = nil,
		mpCost        = 4,
		rtMult        = 1.0,
		channelTime   = 200,
		power         = 0,
		inheritStr    = false,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-GUARDIAN-S-PROJECTION"] = {
		id            = "SKL-GUARDIAN-S-PROJECTION",
		name          = "Guardian’s Projection",
		tags          = { "Buff" },
		targetRules   = "Ally Unit, Self",
		range         = 4,
		aoePattern    = nil,
		mpCost        = 5,
		rtMult        = 1.25,
		channelTime   = 100,
		power         = 1.0,
		inheritStr    = false,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-LUCKY-STRIKE"] = {
		id            = "SKL-LUCKY-STRIKE",
		name          = "Lucky Strike",
		tags          = { "Direct Damage", "Physical" },
		targetRules   = "Enemy Unit",
		range         = -1,
		aoePattern    = "InheritWeapon",
		mpCost        = 3,
		rtMult        = 1.0,
		channelTime   = 0,
		power         = 1.0,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Inherit",
	},
	["SKL-RAPID-ASSAULT"] = {
		id            = "SKL-RAPID-ASSAULT",
		name          = "Rapid Assault",
		tags          = { "Direct Damage", "Physical" },
		targetRules   = "Enemy Unit",
		range         = -1,
		aoePattern    = nil,
		mpCost        = 4,
		rtMult        = 1.35,
		channelTime   = 100,
		power         = 0.45,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Inherit",
	},
	["SKL-BASTION-PROJECTION"] = {
		id            = "SKL-BASTION-PROJECTION",
		name          = "Bastion Projection",
		tags          = { "Shield", "Buff" },
		targetRules   = "Ally Unit, Self",
		range         = 3,
		aoePattern    = nil,
		mpCost        = 4,
		rtMult        = 1.0,
		channelTime   = 100,
		power         = 2.0,
		inheritStr    = false,
		appliesStatus = nil,
		isHealing     = false,
		isShield      = true,  -- shield-grant routing (2026-10-05)
		projectileType = "Direct",
	},
	["SKL-PRECISE-DISARM"] = {
		id            = "SKL-PRECISE-DISARM",
		name          = "Precise Disarm",
		tags          = { "Direct Damage", "Debuff", "Physical" },
		targetRules   = "Enemy Unit",
		range         = -1,
		aoePattern    = nil,
		mpCost        = 4,
		rtMult        = 1.0,
		channelTime   = 150,
		power         = 0.6,
		inheritStr    = true,
		appliesStatus = "Disarmed",
		isHealing     = false,
		projectileType = "Inherit",
	},
	["SKL-OPPORTUNIST-S-STEP"] = {
		id            = "SKL-OPPORTUNIST-S-STEP",
		name          = "Opportunist’s Step",
		tags          = { "Utility" },
		targetRules   = "Empty Tile",
		range         = 4,
		aoePattern    = nil,
		mpCost        = 2,
		rtMult        = 0.5,
		channelTime   = 0,
		power         = 0,
		inheritStr    = false,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-STEAL"] = {
		id            = "SKL-STEAL",
		name          = "Steal",
		tags          = { "Utility" },
		targetRules   = "Enemy Unit",
		range         = 1,
		aoePattern    = nil,
		mpCost        = 0,
		rtMult        = 1.0,
		channelTime   = 200,
		power         = 0,
		inheritStr    = false,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-CRIPPLING-SHOT"] = {
		id            = "SKL-CRIPPLING-SHOT",
		name          = "Crippling Shot",
		tags          = { "Direct Damage", "Debuff", "Physical" },
		targetRules   = "Enemy Unit",
		range         = -1,
		aoePattern    = nil,
		mpCost        = 3,
		rtMult        = 1.0,
		channelTime   = 0,
		power         = 0.8,
		inheritStr    = true,
		appliesStatus = "Slow",
		isHealing     = false,
		projectileType = "Inherit",
	},
	["SKL-PYROCLASM"] = {
		id            = "SKL-PYROCLASM",
		name          = "Pyroclasm",
		tags          = { "Direct Damage", "Fire" },
		targetRules   = "Ground, including occupied Ground",
		range         = 4,
		aoePattern    = "Line5",
		mpCost        = 6,
		rtMult        = 1.3,
		channelTime   = 100,
		power         = 0.85,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-GALE-THRUST"] = {
		id            = "SKL-GALE-THRUST",
		name          = "Gale Thrust",
		tags          = { "Direct Damage", "Physical", "Utility" },
		targetRules   = "Enemy Unit",
		range         = 0,
		aoePattern    = "Cone3",
		mpCost        = 5,
		rtMult        = 1.35,
		channelTime   = 0,
		power         = 0.8,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-TIDAL-CRASH"] = {
		id            = "SKL-TIDAL-CRASH",
		name          = "Tidal Crash",
		tags          = { "Direct Damage", "Water" },
		targetRules   = "Ground, including occupied Ground",
		range         = 4,
		aoePattern    = "Cross3",
		mpCost        = 7,
		rtMult        = 1.4,
		channelTime   = 150,
		power         = 0.7,
		inheritStr    = true,
		appliesStatus = "Wet",
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-STATIC-FIELD"] = {
		id            = "SKL-STATIC-FIELD",
		name          = "Static Field",
		tags          = { "Debuff", "Electric" },
		targetRules   = "Enemy Unit",
		range         = 0,
		aoePattern    = "Ring2",
		mpCost        = 5,
		rtMult        = 1.0,
		channelTime   = 100,
		power         = 0,
		inheritStr    = false,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-VENOM-BURST"] = {
		id            = "SKL-VENOM-BURST",
		name          = "Venom Burst",
		tags          = { "Direct Damage", "Poison", "Debuff" },
		targetRules   = "Enemy Unit",
		range         = 0,
		aoePattern    = "Adjacent",
		mpCost        = 4,
		rtMult        = 1.4,
		channelTime   = 0,
		power         = 0.7,
		inheritStr    = true,
		appliesStatus = "Poison",
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-FISSURE-LINE"] = {
		id            = "SKL-FISSURE-LINE",
		name          = "Fissure Line",
		tags          = { "Direct Damage", "Earth", "Debuff" },
		targetRules   = "Ground, including occupied Ground",
		range         = 3,
		aoePattern    = "Line4",
		mpCost        = 5,
		rtMult        = 1.3,
		channelTime   = 0,
		power         = 0.75,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-CONSECRATE"] = {
		id            = "SKL-CONSECRATE",
		name          = "Consecrate",
		tags          = { "Healing", "Buff", "Holy" },
		targetRules   = "Self, Allies",
		range         = 0,
		aoePattern    = "Circle2",
		mpCost        = 7,
		rtMult        = 1.0,
		channelTime   = 150,
		power         = 0.4,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = true,
		projectileType = "Direct",
	},
	["SKL-SHADOW-RAKE"] = {
		id            = "SKL-SHADOW-RAKE",
		name          = "Shadow Rake",
		tags          = { "Direct Damage", "Dark" },
		targetRules   = "Enemy Unit",
		range         = 0,
		aoePattern    = "Cone2",
		mpCost        = 5,
		rtMult        = 1.35,
		channelTime   = 0,
		power         = 0.85,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-GLACIAL-WAVE"] = {
		id            = "SKL-GLACIAL-WAVE",
		name          = "Glacial Wave",
		tags          = { "Direct Damage", "Ice", "Debuff" },
		targetRules   = "Ground, including occupied Ground",
		range         = 3,
		aoePattern    = "Line3",
		mpCost        = 5,
		rtMult        = 1.25,
		channelTime   = 100,
		power         = 0.75,
		inheritStr    = true,
		appliesStatus = "Frozen",
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-MIASMA-CLOUD"] = {
		id            = "SKL-MIASMA-CLOUD",
		name          = "Miasma Cloud",
		tags          = { "Debuff", "Poison" },
		targetRules   = "Ground, including occupied Ground",
		range         = 4,
		aoePattern    = "Circle2",
		mpCost        = 5,
		rtMult        = 1.0,
		channelTime   = 100,
		power         = 0,
		inheritStr    = false,
		appliesStatus = "Poison",
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-BLINDING-FLASH"] = {
		id            = "SKL-BLINDING-FLASH",
		name          = "Blinding Flash",
		tags          = { "Debuff", "Holy" },
		targetRules   = "Enemy Unit",
		range         = 0,
		aoePattern    = "Cone2",
		mpCost        = 5,
		rtMult        = 1.0,
		channelTime   = 0,
		power         = 0,
		inheritStr    = false,
		appliesStatus = "Blind",
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-SIPHON-PULSE"] = {
		id            = "SKL-SIPHON-PULSE",
		name          = "Siphon Pulse",
		tags          = { "Direct Damage", "Dark", "Healing" },
		targetRules   = "Enemy Unit",
		range         = 0,
		aoePattern    = "Ring1",
		mpCost        = 6,
		rtMult        = 1.5,
		channelTime   = 150,
		power         = 0.6,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = true,
		projectileType = "Direct",
	},
	["SKL-SUMMON-DECOY"] = {
		id            = "SKL-SUMMON-DECOY",
		name          = "Summon Decoy",
		tags          = { "Summon", "Utility" },
		targetRules   = "Empty Tile",
		range         = 3,
		aoePattern    = nil,
		mpCost        = 5,
		rtMult        = 1.0,
		channelTime   = 100,
		power         = 1.0,
		inheritStr    = false,
		appliesStatus = nil,
		isHealing     = false,
		isSummon      = true,  -- summon-spawn routing (2026-10-05)
		summonProfile = "idle",  -- AI behaviour tag for the spawned unit
		projectileType = "Direct",
	},
	["SKL-MENDING-RAIN"] = {
		id            = "SKL-MENDING-RAIN",
		name          = "Mending Rain",
		tags          = { "Healing", "Water" },
		targetRules   = "Self, Allies",
		range         = 3,
		aoePattern    = "Circle2",
		mpCost        = 7,
		rtMult        = 1.0,
		channelTime   = 150,
		power         = 0.35,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = true,
		projectileType = "Direct",
	},
	["SKL-VOLTAIC-CHAIN"] = {
		id            = "SKL-VOLTAIC-CHAIN",
		name          = "Voltaic Chain",
		tags          = { "Direct Damage", "Electric", "Debuff" },
		targetRules   = "Enemy Unit",
		range         = 3,
		aoePattern    = "Chain3",
		mpCost        = 5,
		rtMult        = 1.1,
		channelTime   = 100,
		power         = 0.9,
		inheritStr    = true,
		appliesStatus = "Pinned",
		isHealing     = false,
		projectileType = "Direct",
		chainFalloff  = 0.75,   -- 100%, 75%, 50%
	},
	["SKL-IGNITION-LANCE"] = {
		id            = "SKL-IGNITION-LANCE",
		name          = "Ignition Lance",
		tags          = { "Direct Damage", "Fire" },
		targetRules   = "Enemy Unit",
		range         = 6,
		aoePattern    = nil,
		mpCost        = 7,
		rtMult        = 1.5,
		channelTime   = 200,
		power         = 1.4,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-RENDING-SLASH"] = {
		id            = "SKL-RENDING-SLASH",
		name          = "Rending Slash",
		tags          = { "Direct Damage", "Physical", "Debuff" },
		targetRules   = "Enemy Unit",
		range         = -1,
		aoePattern    = nil,
		mpCost        = 3,
		rtMult        = 1.1,
		channelTime   = 0,
		power         = 0.95,
		inheritStr    = true,
		appliesStatus = "Bleed",
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-MIND-FRACTURE"] = {
		id            = "SKL-MIND-FRACTURE",
		name          = "Mind Fracture",
		tags          = { "Debuff", "Dark" },
		targetRules   = "Enemy Unit",
		range         = 4,
		aoePattern    = nil,
		mpCost        = 6,
		rtMult        = 1.0,
		channelTime   = 150,
		power         = 0,
		inheritStr    = false,
		appliesStatus = "Confuse",
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-SEAL-OF-SILENCE"] = {
		id            = "SKL-SEAL-OF-SILENCE",
		name          = "Seal of Silence",
		tags          = { "Debuff", "Holy" },
		targetRules   = "Enemy Unit",
		range         = 4,
		aoePattern    = nil,
		mpCost        = 6,
		rtMult        = 1.0,
		channelTime   = 100,
		power         = 0,
		inheritStr    = false,
		appliesStatus = "Silence",
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-MANA-SCORCH"] = {
		id            = "SKL-MANA-SCORCH",
		name          = "Mana Scorch",
		tags          = { "Direct Damage", "Fire", "Debuff" },
		targetRules   = "Enemy Unit",
		range         = 4,
		aoePattern    = nil,
		mpCost        = 5,
		rtMult        = 1.2,
		channelTime   = 100,
		power         = 0.8,
		inheritStr    = true,
		appliesStatus = "Mana Burn",
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-WITHER"] = {
		id            = "SKL-WITHER",
		name          = "Wither",
		tags          = { "Debuff", "Poison" },
		targetRules   = "Enemy Unit",
		range         = 3,
		aoePattern    = nil,
		mpCost        = 4,
		rtMult        = 1.0,
		channelTime   = 100,
		power         = 0,
		inheritStr    = false,
		-- DB: Apply Weakened (2000 CT) + Cursed (4 turns) to target. Undead are
		-- immune to Poison-tagged Cursed (handled by StatusService.IsImmune).
		appliesStatuses = { "Weakened", "Cursed" },
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-BULWARK-FIELD"] = {
		id            = "SKL-BULWARK-FIELD",
		name          = "Bulwark Field",
		tags          = { "Shield", "Buff" },
		targetRules   = "Self, Allies",
		range         = 0,
		aoePattern    = "Circle2",
		mpCost        = 8,
		rtMult        = 1.0,
		channelTime   = 200,
		power         = 1.0,
		inheritStr    = false,
		appliesStatus = nil,
		isHealing     = false,
		isShield      = true,  -- shield-grant routing (2026-10-05)
		projectileType = "Direct",
	},
	["SKL-RETRIBUTION-SHELL"] = {
		id            = "SKL-RETRIBUTION-SHELL",
		name          = "Retribution Shell",
		tags          = { "Shield", "Buff", "Direct Damage" },
		targetRules   = "Ally Unit, Self",
		range         = 3,
		aoePattern    = nil,
		mpCost        = 6,
		rtMult        = 1.2,
		channelTime   = 100,
		power         = 1.5,
		inheritStr    = false,
		appliesStatus = nil,
		isHealing     = false,
		isShield      = true,  -- shield-grant routing (2026-10-05)
		projectileType = "Direct",
	},
	["SKL-INVIGORATE"] = {
		id            = "SKL-INVIGORATE",
		name          = "Invigorate",
		tags          = { "Buff", "Utility" },
		targetRules   = "Ally Unit, Self",
		range         = 3,
		aoePattern    = nil,
		mpCost        = 5,
		rtMult        = 1.0,
		channelTime   = 0,
		power         = 0,  -- pure ally buff; no damage (routes through ally-buff branch)
		inheritStr    = false,
		-- DB: Apply Haste (3 turns) + Regeneration (3000 CT) to target ally or self.
		appliesStatuses = { "Haste", "Regeneration" },
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-TOXIC-NEEDLE"] = {
		id            = "SKL-TOXIC-NEEDLE",
		name          = "Toxic Needle",
		tags          = { "Direct Damage", "Poison", "Debuff" },
		targetRules   = "Enemy Unit",
		range         = 4,
		aoePattern    = nil,
		mpCost        = 3,
		rtMult        = 0.85,
		channelTime   = 0,
		power         = 0.5,
		inheritStr    = true,
		appliesStatus = "Venom",
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-SHATTER-POINT"] = {
		id            = "SKL-SHATTER-POINT",
		name          = "Shatter Point",
		tags          = { "Direct Damage", "Earth", "Debuff" },
		targetRules   = "Enemy Unit",
		range         = -1,
		aoePattern    = nil,
		mpCost        = 7,
		rtMult        = 1.6,
		channelTime   = 200,
		power         = 1.0,
		inheritStr    = true,
		appliesStatus = "Break",  -- Earth damage skill; Break disables target passives (mechanic in DoctrinePassiveService)
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-NULL-STRIKE"] = {
		id            = "SKL-NULL-STRIKE",
		name          = "Null Strike",
		tags          = { "Direct Damage", "Physical", "Debuff" },
		targetRules   = "Enemy Unit",
		range         = -1,
		aoePattern    = nil,
		mpCost        = 4,
		rtMult        = 1.15,
		channelTime   = 0,
		power         = 0.9,
		inheritStr    = true,
		-- DB: Physical damage + apply Mute (3000 CT). Mute disables skill augments
		-- only. Damaging rider — lands via the actual>0 status gate in ApplyOutcome.
		appliesStatus = "Mute",
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-BATTLE-FURY"] = {
		id            = "SKL-BATTLE-FURY",
		name          = "Battle Fury",
		tags          = { "Buff", "Utility" },
		targetRules   = "Self",
		range         = 0,
		aoePattern    = nil,
		mpCost        = 4,
		rtMult        = 1.0,
		channelTime   = 0,
		power         = 0,  -- pure self-buff; no damage (was 1.0 → hit caster for weapon dmg)
		inheritStr    = false,
		-- Applies BOTH Frenzy (3 turns) and Rush (4 turns) per DB. Rush mechanic works
		-- (movement +3, DEX -20%); Frenzy mechanic (basic-attack tempo) is not yet consumed.
		appliesStatuses = { "Frenzy", "Rush" },
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-ARCANE-RENEWAL"] = {
		id            = "SKL-ARCANE-RENEWAL",
		name          = "Arcane Renewal",
		tags          = { "Buff", "Utility" },
		targetRules   = "Ally Unit, Self",
		range         = 4,
		aoePattern    = nil,
		mpCost        = 4,
		rtMult        = 1.0,
		channelTime   = 100,
		power         = 0,  -- pure ally buff; no damage (routes through ally-buff branch)
		inheritStr    = false,
		-- DB: Apply Recharge (1200 CT) to target ally or self. Immediate MP restore
		-- on apply + periodic restore every 300 CT (handled in StatusService).
		appliesStatus = "Recharge",
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-VANISHING-STEP"] = {
		id            = "SKL-VANISHING-STEP",
		name          = "Vanishing Step",
		tags          = { "Utility", "Dark" },
		targetRules   = "Self",
		range         = 0,
		aoePattern    = nil,
		mpCost        = 5,
		rtMult        = 1.0,
		channelTime   = 0,
		power         = 1.0,
		inheritStr    = false,
		appliesStatus = "Hide",
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-BENEDICTION"] = {
		id            = "SKL-BENEDICTION",
		name          = "Benediction",
		tags          = { "Buff", "Holy" },
		targetRules   = "Ally Unit, Self",
		range         = 4,
		aoePattern    = nil,
		mpCost        = 7,
		rtMult        = 1.0,
		channelTime   = 200,
		power         = 0,  -- pure ally buff; no damage (routes through ally-buff branch)
		inheritStr    = false,
		-- DB: Apply Blessed (4 turns) + Enlightened (3000 CT, 1 stack) to target.
		appliesStatuses = { "Blessed", "Enlightened" },
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-EARTHEN-LANCE"] = {
		id            = "SKL-EARTHEN-LANCE",
		name          = "Earthen Lance",
		tags          = { "Direct Damage", "Earth" },
		targetRules   = "Enemy Unit",
		range         = 5,
		aoePattern    = nil,
		mpCost        = 4,
		rtMult        = 1.1,
		channelTime   = 100,
		power         = 1.0,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-FLASH-FREEZE"] = {
		id            = "SKL-FLASH-FREEZE",
		name          = "Flash Freeze",
		tags          = { "Utility", "Ice" },
		targetRules   = "Ground, including occupied Ground",
		range         = 3,
		aoePattern    = "Cross2",
		mpCost        = 6,
		rtMult        = 1.0,
		channelTime   = 100,
		power         = 0,
		inheritStr    = false,
		appliesStatus = "Wet",
		isHealing     = false,
		projectileType = "Direct",
		createsTileEffect = "Wet",   -- applies Wet tile effect + terrain transforms (Water→Ice)
	},
	["SKL-IGNITE-GROUND"] = {
		id            = "SKL-IGNITE-GROUND",
		name          = "Ignite Ground",
		tags          = { "Direct Damage", "Fire", "Utility" },
		targetRules   = "Ground, including occupied Ground",
		range         = 4,
		aoePattern    = "Circle1",
		mpCost        = 5,
		rtMult        = 1.2,
		channelTime   = 0,
		power         = 0.5,
		inheritStr    = true,
		appliesStatus = "Burn",
		isHealing     = false,
		projectileType = "Direct",
		createsTileEffect = "Burning",   -- applies Burning tile effect + terrain transforms
	},
	["SKL-TWIN-FANGS"] = {
		id            = "SKL-TWIN-FANGS",
		name          = "Twin Fangs",
		tags          = { "Direct Damage", "Physical" },
		targetRules   = "Enemy Unit",
		range         = -1,
		aoePattern    = nil,
		mpCost        = 4,
		rtMult        = 1.3,
		channelTime   = 0,
		power         = 0.65,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-STORM-BARRAGE"] = {
		id            = "SKL-STORM-BARRAGE",
		name          = "Storm Barrage",
		tags          = { "Direct Damage", "Electric" },
		targetRules   = "Enemy Unit",
		range         = -1,
		aoePattern    = "InheritWeapon",
		mpCost        = 6,
		rtMult        = 1.4,
		channelTime   = 150,
		power         = 0.45,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-LUNGE"] = {
		id            = "SKL-LUNGE",
		name          = "Lunge",
		tags          = { "Direct Damage", "Physical", "Utility" },
		targetRules   = "Enemy Unit",
		range         = 2,
		aoePattern    = nil,
		mpCost        = 3,
		rtMult        = 1.2,
		channelTime   = 0,
		power         = 1.0,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-RECOIL-SHOT"] = {
		id            = "SKL-RECOIL-SHOT",
		name          = "Recoil Shot",
		tags          = { "Direct Damage", "Physical", "Utility" },
		targetRules   = "Enemy Unit",
		range         = -1,
		aoePattern    = nil,
		mpCost        = 3,
		rtMult        = 1.1,
		channelTime   = 0,
		power         = 0.8,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-COUNTER-STANCE"] = {
		id            = "SKL-COUNTER-STANCE",
		name          = "Counter Stance",
		tags          = { "Buff", "Utility" },
		targetRules   = "Self",
		range         = 0,
		aoePattern    = nil,
		mpCost        = 3,
		rtMult        = 1.0,
		channelTime   = 0,
		power         = 0,     -- self-buff: no damage on cast
		inheritStr    = false,
		appliesStatus = "CounterStance",
		-- DB: "Counter attack: Weapon Attack Power x 0.60" — applied to each counter hit.
		counterPowerMult = 0.60,
		-- DB: counter applies 30% of the defender's Weapon RT Delay to the attacker.
		counterRtDelayMult = 0.30,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-POISON-TRAP"] = {
		id            = "SKL-POISON-TRAP",
		name          = "Poison Trap",
		tags          = { "Debuff", "Poison", "Utility" },
		targetRules   = "Empty Tile",
		range         = 2,
		aoePattern    = nil,
		mpCost        = 4,
		rtMult        = 1.0,
		channelTime   = 0,
		power         = 0,
		inheritStr    = false,
		appliesStatus = "Poison",
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-DECIMATING-SWING"] = {
		id            = "SKL-DECIMATING-SWING",
		name          = "Decimating Swing",
		tags          = { "Direct Damage", "Physical" },
		targetRules   = "Enemy Unit",
		range         = -1,
		aoePattern    = "Cleave",
		mpCost        = 5,
		rtMult        = 1.6,
		channelTime   = 100,
		power         = 1.5,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-FLURRY-OF-BLADES"] = {
		id            = "SKL-FLURRY-OF-BLADES",
		name          = "Flurry of Blades",
		tags          = { "Direct Damage", "Physical" },
		targetRules   = "Enemy Unit",
		range         = -1,
		aoePattern    = nil,
		mpCost        = 5,
		rtMult        = 1.2,
		channelTime   = 0,
		power         = 0.4,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-SUMMON-TURRET"] = {
		id            = "SKL-SUMMON-TURRET",
		name          = "Summon Turret",
		tags          = { "Summon", "Direct Damage" },
		targetRules   = "Empty Tile",
		range         = 3,
		aoePattern    = nil,
		mpCost        = 7,
		rtMult        = 1.0,
		channelTime   = 200,
		power         = 0.5,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		isSummon      = true,  -- summon-spawn routing (2026-10-05)
		summonProfile = "turret",  -- AI behaviour tag for the spawned unit
		projectileType = "Direct",
	},
	["SKL-SUMMON-WARD-TOTEM"] = {
		id            = "SKL-SUMMON-WARD-TOTEM",
		name          = "Summon Ward Totem",
		tags          = { "Summon", "Buff" },
		targetRules   = "Empty Tile",
		range         = 3,
		aoePattern    = nil,
		mpCost        = 6,
		rtMult        = 1.0,
		channelTime   = 150,
		power         = 0.2,
		inheritStr    = false,
		appliesStatus = nil,
		isHealing     = false,
		isSummon      = true,  -- summon-spawn routing (2026-10-05)
		summonProfile = "idle",  -- AI behaviour tag for the spawned unit
		projectileType = "Direct",
	},
	["SKL-SHATTER-BLOW"] = {
		id            = "SKL-SHATTER-BLOW",
		name          = "Shatter Blow",
		tags          = { "Direct Damage", "Physical" },
		targetRules   = "Enemy Unit",
		range         = -1,
		aoePattern    = nil,
		mpCost        = 4,
		rtMult        = 1.3,
		channelTime   = 0,
		power         = 1.0,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-HEMORRHAGE"] = {
		id            = "SKL-HEMORRHAGE",
		name          = "Hemorrhage",
		tags          = { "Direct Damage", "Physical", "Debuff" },
		targetRules   = "Enemy Unit",
		range         = -1,
		aoePattern    = nil,
		mpCost        = 3,
		rtMult        = 1.1,
		channelTime   = 0,
		power         = 0.6,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-PURGE"] = {
		id            = "SKL-PURGE",
		name          = "Purge",
		tags          = { "Healing", "Utility", "Holy" },
		targetRules   = "Ally Unit, Self",
		range         = 4,
		aoePattern    = nil,
		mpCost        = 5,
		rtMult        = 1.0,
		channelTime   = 0,
		power         = 0.2,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = true,
		projectileType = "Direct",
	},
	["SKL-LIFE-LINK"] = {
		id            = "SKL-LIFE-LINK",
		name          = "Life Link",
		tags          = { "Buff", "Healing", "Utility" },
		targetRules   = "Ally Unit",
		range         = 4,
		aoePattern    = nil,
		mpCost        = 5,
		rtMult        = 1.0,
		channelTime   = 100,
		power         = 1.0,
		inheritStr    = false,
		appliesStatus = nil,
		isHealing     = true,
		projectileType = "Direct",
	},
	["SKL-TORRENT-SPEAR"] = {
		id            = "SKL-TORRENT-SPEAR",
		name          = "Torrent Spear",
		tags          = { "Direct Damage", "Water" },
		targetRules   = "Enemy Unit",
		range         = 5,
		aoePattern    = nil,
		mpCost        = 4,
		rtMult        = 1.1,
		channelTime   = 50,
		power         = 1.1,
		inheritStr    = true,
		appliesStatus = "Wet",
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-BLOOD-PRICE"] = {
		id            = "SKL-BLOOD-PRICE",
		name          = "Blood Price",
		tags          = { "Direct Damage", "Dark" },
		targetRules   = "Enemy Unit",
		range         = 3,
		aoePattern    = nil,
		mpCost        = 0,
		rtMult        = 0.8,
		channelTime   = 0,
		power         = 1.4,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-FESTERING-WOUND"] = {
		id            = "SKL-FESTERING-WOUND",
		name          = "Festering Wound",
		tags          = { "Debuff", "Poison", "Dark" },
		targetRules   = "Enemy Unit",
		range         = 4,
		aoePattern    = nil,
		mpCost        = 5,
		rtMult        = 1.0,
		channelTime   = 100,
		power         = 0,
		inheritStr    = false,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-THUNDERCLAP"] = {
		id            = "SKL-THUNDERCLAP",
		name          = "Thunderclap",
		tags          = { "Direct Damage", "Electric", "Debuff" },
		targetRules   = "Enemy Unit",
		range         = 0,
		aoePattern    = "Circle3",
		mpCost        = 7,
		rtMult        = 1.4,
		channelTime   = 150,
		power         = 0.75,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-EMPOWERING-AURA"] = {
		id            = "SKL-EMPOWERING-AURA",
		name          = "Empowering Aura",
		tags          = { "Buff", "Utility" },
		targetRules   = "Self (Aura)",
		range         = 0,
		aoePattern    = "Aura3",
		mpCost        = 8,
		rtMult        = 1.5,
		channelTime   = 0,
		power         = 1.0,
		inheritStr    = false,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-SKYFALL-LANCE"] = {
		id            = "SKL-SKYFALL-LANCE",
		name          = "Skyfall Lance",
		tags          = { "Direct Damage", "Physical", "Utility" },
		targetRules   = "Enemy Unit",
		range         = 3,
		aoePattern    = nil,
		mpCost        = 5,
		rtMult        = 1.4,
		channelTime   = 0,
		power         = 1.3,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-DRAGON-DIVE"] = {
		id            = "SKL-DRAGON-DIVE",
		name          = "Dragon Dive",
		tags          = { "Direct Damage", "Physical", "Utility" },
		targetRules   = "Enemy Tile",
		range         = 4,
		aoePattern    = "Impact1",
		mpCost        = 8,
		rtMult        = 1.6,
		channelTime   = 0,
		power         = 1.1,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-HOLY-SMITE"] = {
		id            = "SKL-HOLY-SMITE",
		name          = "Holy Smite",
		tags          = { "Direct Damage", "Holy" },
		targetRules   = "Enemy Unit",
		range         = -1,
		aoePattern    = nil,
		mpCost        = 6,
		rtMult        = 1.2,
		channelTime   = 0,
		power         = 1.15,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-SANCTIFY"] = {
		id            = "SKL-SANCTIFY",
		name          = "Sanctify",
		tags          = { "Healing", "Buff", "Holy" },
		targetRules   = "Ally Tile (centered on caster)",
		range         = 0,
		aoePattern    = "Impact1",
		mpCost        = 10,
		rtMult        = 1.4,
		channelTime   = 0,
		power         = 0.3,
		inheritStr    = false,
		appliesStatus = nil,
		isHealing     = true,
		projectileType = "Direct",
	},
	["SKL-BARRAGE"] = {
		id            = "SKL-BARRAGE",
		name          = "Barrage",
		tags          = { "Direct Damage", "Physical" },
		targetRules   = "Enemy Unit",
		range         = -1,
		aoePattern    = nil,
		mpCost        = 7,
		rtMult        = 1.5,
		channelTime   = 0,
		power         = 0.4,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Direct",
	},
	["SKL-NATURES-GRASP"] = {
		id            = "SKL-NATURES-GRASP",
		name          = "Nature's Grasp",
		tags          = { "Debuff", "Earth", "Utility" },
		targetRules   = "Enemy Unit",
		range         = 4,
		aoePattern    = nil,
		mpCost        = 5,
		rtMult        = 1.2,
		channelTime   = 0,
		power         = 1.0,
		inheritStr    = false,
		appliesStatus = "Pinned",
		isHealing     = false,
		projectileType = "Direct",
	},
	["DOC-SPELLBLADE-01"] = {
		id            = "DOC-SPELLBLADE-01",
		name          = "Arcane Strike",
		tags          = { "Direct Damage", "Physical" },
		targetRules   = "Enemy Unit",
		range         = -1,
		aoePattern    = "InheritWeapon",
		mpCost        = 4,
		rtMult        = 1.0,
		channelTime   = 0,
		power         = 1.0,
		inheritStr    = true,
		appliesStatus = nil,
		isHealing     = false,
		projectileType = "Inherit",
		-- Hybrid weapon/INT strike (Doctrine: Spellblade). Authored recipe
		-- (DB/SkillData DOC-SPELLBLADE-01): Power = Weapon Attack Power x 1.00 x
		-- Skill Potency Multiplier, PLUS a flat INT/2 bonus to Skill Power applied
		-- before Defense. The flat INT/2 term lives in CombatResolver.EstimateSkillPower,
		-- keyed to this id (the generic skill-power path has no INT flat term).
		-- Castable def lives here so it supersedes the placeholder in
		-- Main.server doctrineSkillCombatDefs (registered first; that loop skips
		-- ids already registered).
	},
}

--------------------------------------------------
-- LEGACY SKILL ALIASES  (demo units use old IDs)
-- Maps old hand-authored IDs to DB skill entries.
-- Remove when demo units migrate to SKL-* IDs.
--------------------------------------------------

GameConstants.SKILLS["skill_power_strike"]   = GameConstants.SKILLS["SKL-POWER-STRIKE"]
GameConstants.SKILLS["skill_crippling_shot"] = GameConstants.SKILLS["SKL-CRIPPLING-SHOT"]
GameConstants.SKILLS["skill_sweeping_cut"]   = GameConstants.SKILLS["SKL-SWEEPING-CUT"]
GameConstants.SKILLS["skill_fire_bolt"]      = GameConstants.SKILLS["SKL-FIRE-BOLT"]
GameConstants.SKILLS["skill_venom_strike"]   = GameConstants.SKILLS["SKL-VENOM-STRIKE"]  -- nil (no DB entry)
GameConstants.SKILLS["skill_healing_light"]  = GameConstants.SKILLS["SKL-HEALING-LIGHT"]

-- SKL-VENOM-STRIKE doesn't exist in DB — Venom Strike was a demo-only skill.
-- Keep a manual entry until demo units are updated.
if not GameConstants.SKILLS["skill_venom_strike"] then
	GameConstants.SKILLS["skill_venom_strike"] = {
		id = "skill_venom_strike", name = "Venom Strike",
		tags = { "Direct Damage", "Poison" }, targetRules = "Enemy Unit",
		range = 1, aoePattern = nil, mpCost = 2,
		rtMult = 1.0, channelTime = 0, power = 1.00,
		inheritStr = true, appliesStatus = "Poison",
		isHealing = false, projectileType = "Direct",
	}
end

--------------------------------------------------
-- EVENT QUEUE LIMITS (from DB: trigger_safety)
--------------------------------------------------

GameConstants.EVENT_QUEUE_HARD_CAP       = 128
GameConstants.EVENT_QUEUE_YIELD_INTERVAL = 32
GameConstants.MAX_SECONDARY_EVENTS       = 20

--------------------------------------------------
-- CHANNEL TIME FORMULA (from DB: core_stats — DEX)
-- Channel Time = Base Channel Time × (1 - DEX / (300 + DEX))
--------------------------------------------------

function GameConstants.CalcChannelTime(baseChannelTime, dex)
	if baseChannelTime <= 0 then return 0 end
	local reduction = dex / (300 + dex)
	return math.max(1, math.round(baseChannelTime * (1 - reduction)))
end

--------------------------------------------------
-- SHARED COMBAT FORMULAS
--------------------------------------------------

-- Bug 1 fix: STR reduces Effective Weapon WT
-- Rule: Effective WT = WT × (1 - STR/(200+STR)) if WT>=0
--        Effective WT = WT × (1 + STR/(200+STR)) if WT<0
function GameConstants.CalcEffectiveWt(rawWt, str)
	str = str or 0
	rawWt = rawWt or 0
	if rawWt >= 0 then
		return rawWt * (1 - str / (200 + str))
	else
		return rawWt * (1 + str / (200 + str))
	end
end

-- Missing 5: Combat Fortune (LUK damage modifier)
-- Rule: Modifier = 0.40 × DeltaLUK / (abs(DeltaLUK) + 150)
--       Multiplier = 1 + Modifier
function GameConstants.CalcCombatFortune(attackerLuk, defenderLuk)
	local delta = (attackerLuk or 10) - (defenderLuk or 10)
	local modifier = 0.40 * delta / (math.abs(delta) + 150)
	return 1 + modifier
end

-- Missing 6: LUK Starting RT
-- Rule: Starting RT = round(Base RT × (1 - 0.30 × LUK / (100 + LUK)))
function GameConstants.CalcStartingRt(baseRt, luk)
	luk = luk or 10
	return math.round(baseRt * (1 - 0.30 * luk / (100 + luk)))
end

-- Player Initiative Edge (DB core_stats id 54, STEP 2 — user ruling 2026-10-02).
-- PLAYER-ROSTER units only: Starting RT = LUK Starting RT - 10 (minimum 1), applied
-- LAST (after any % Starting-RT modifiers). NOT for enemies, neutrals, allied NPCs,
-- summons, or mid-battle reinforcements. STEP 1 (CalcStartingRt) is symmetric.
GameConstants.PLAYER_INITIATIVE_EDGE_RT = 10
function GameConstants.ApplyPlayerInitiativeEdge(startingRt)
	return math.max(1, (startingRt or 0) - GameConstants.PLAYER_INITIATIVE_EDGE_RT)
end

-- RT Delay Resistance (VIT reduces incoming RT Delay)
-- Rule: Incoming RT Delay × (1 - VIT / (300 + VIT))
function GameConstants.CalcRtDelayResistance(rawDelay, targetVit)
	targetVit = targetVit or 10
	local resist = 1 - targetVit / (300 + targetVit)
	return math.round(rawDelay * resist)
end

--------------------------------------------------
-- SHARED DERIVED STAT FORMULAS
--
-- Primitive functions used by ComputeDerivedStats and by services
-- that need to recalculate with dynamic inputs (e.g. CombatResolver
-- calculating attack power with a different weapon mid-action).
-- Each function returns the RAW (unrounded) value.
--------------------------------------------------

function GameConstants.CalcAttackPower(weaponDmg, str)
	return weaponDmg * (1 + str / 200)
end

function GameConstants.CalcDefensePower(def, vit)
	if def <= 0 then return 0 end
	return def * (1 + vit / 300)
end

-- Total equipment Defense feeding Defense Power (DB core_stats id 30: "Defense comes
-- from equipment and modifiers"; id 31/5: Defense Power = Defense x (1 + VIT / 300)).
-- = MainHand weapon Defense + Off-Hand Defense + summed armor Defense. All three are
-- rebuilt by EquipmentService.RebuildUnitStats (rarity Defense lines already folded
-- into each item's profile). Units without equipment fall back to 0 (legacy).
function GameConstants.GetUnitDefense(unit)
	if not unit then return 0 end
	return (unit.weaponDefense or 0) + (unit.offHandDefense or 0) + (unit.armorDefense or 0)
end

-- Effective Armor WT (DB core_stats id 2 Effective Equipment WT formula applied to the
-- summed armor WT). Feeds Modified Base RT (DB weapons_equipment id 7:
-- "Modified Base RT = Base RT + Effective Armor WT") — NOT the action WT term.
function GameConstants.CalcEffectiveArmorWt(unit)
	if not unit then return 0 end
	local str = (unit.effectiveStats and unit.effectiveStats.STR) or 10
	return GameConstants.CalcEffectiveWt(unit.armorWt or 0, str)
end

function GameConstants.CalcPrecision(dex)
	return dex / (dex + 200)
end

function GameConstants.CalcEvasiveness(agi)
	return agi / (agi + 200)
end

function GameConstants.CalcSkillPotency(int)
	return 1 + int / (200 + int)
end

function GameConstants.CalcHealEfficiency(vit)
	return 1 + vit / 300
end

--------------------------------------------------
-- DERIVED STATS COMPUTATION
--
-- Builds the full derivedStats table from a unit's effectiveStats + weapon data.
-- Called after every stat rebuild (equip, doctrine, buff/debuff).
-- Returns { derivedStats = {...}, statBreakdown = {...} }
--------------------------------------------------

function GameConstants.ComputeDerivedStats(unit)
	local s = unit.effectiveStats or {}
	local str = s.STR or 10
	local agi = s.AGI or 10
	local int = s.INT or 10
	local vit = s.VIT or 10
	local dex = s.DEX or 10
	local luk = s.LUK or 10

	local weaponDamage  = unit.weaponDamage or 10
	local weaponWt      = unit.weaponWt or 20
	local weaponRtDelay = unit.weaponRtDelay or 0
	local weaponDefense = unit.weaponDefense or 0

	local derived = {
		-- STR derived
		attackPower     = math.round(GameConstants.CalcAttackPower(weaponDamage, str) * 10) / 10,
		effectiveWt     = math.round(GameConstants.CalcEffectiveWt(weaponWt, str)),
		rtDelayBonus    = math.round(weaponRtDelay * (1 + math.min(str / (200 + str), 0.75)) * 10) / 10,
		force           = 1 + math.floor(str / 60),

		-- AGI derived
		movementRange   = 3 + math.floor(agi / 60),
		evasiveness     = math.round(GameConstants.CalcEvasiveness(agi) * 1000) / 10, -- store as % (e.g. 6.5)

		-- INT derived
		skillPotency    = math.round(GameConstants.CalcSkillPotency(int) * 1000) / 1000,
		maxMp           = 20 + int * 2,
		bonusSkillRange = math.floor(int / 75),
		mpRegen         = 2 + math.floor(int / 40),

		-- VIT derived
		maxHp           = 50 + vit * 4,
		healEfficiency  = math.round(GameConstants.CalcHealEfficiency(vit) * 1000) / 1000,
		defensePower    = math.round(GameConstants.CalcDefensePower(GameConstants.GetUnitDefense(unit), vit) * 10) / 10,
		debuffResist    = math.round((1 - vit / (300 + vit)) * 1000) / 1000, -- no Calc* for this composite
		rtDelayResist   = math.round((1 - vit / (300 + vit)) * 1000) / 1000,
		stability       = math.floor(vit / 60),

		-- DEX derived
		precision       = math.round(GameConstants.CalcPrecision(dex) * 1000) / 10, -- store as % (e.g. 5.7)
		jump            = 1 + math.floor(dex / 60),
		channelReduction = math.round(dex / (300 + dex) * 1000) / 10, -- store as % reduction

		-- LUK derived
		discoveryRadius = 1 + math.floor(luk / 60),
		unitFortune     = math.round(luk / (luk + 200) * 1000) / 10, -- store as %
		startingRt      = GameConstants.CalcStartingRt(GameConstants.BASE_RT_STANDARD, luk),

		-- Composite combat stats
		-- Basic Attack RT = round(Modified Base RT x 0.10) + Effective Weapon WT
		-- (DB weapons_equipment id 8); Modified Base RT = Base RT + Effective Armor WT (id 7).
		basicAttackRt   = math.round((GameConstants.BASE_RT_STANDARD + GameConstants.CalcEffectiveArmorWt(unit)) * GameConstants.BASIC_ATTACK_RT_FACTOR)
			+ math.round(GameConstants.CalcEffectiveWt(weaponWt, str)),
	}

	-- Store on unit
	unit.derivedStats = derived

	-- Build primary stat breakdown (base vs bonus)
	local base = unit.baseStats or s
	unit.primaryStats = {}
	for _, stat in ipairs({"STR", "AGI", "INT", "VIT", "DEX", "LUK"}) do
		local baseVal = base[stat] or 10
		local totalVal = s[stat] or 10
		unit.primaryStats[stat] = {
			base  = baseVal,
			bonus = totalVal - baseVal,
			total = totalVal,
		}
	end

	return derived
end

--------------------------------------------------
-- DISPLACEMENT FORMULAS (from DB: movement_targeting — Elevation & Displacement)
--
-- Wall Collision Damage = round(MaxHP × 0.04 × BlockedTiles × (1 + STR/200) × CollisionMult × BossHpMod × SourceMod)
-- Fall Damage = round(MaxHP × 0.04 × (FallHeight - 2)^1.5)  [only if FallHeight >= 3]
-- Push Distance = max(0, Force - Stability)
--------------------------------------------------

GameConstants.COLLISION_MULTIPLIERS = {
	Unit       = 0.8,
	WoodenWall = 1.0,
	StoneWall  = 1.2,
	Pillar     = 1.3,
	Spikes     = 1.6,
}

GameConstants.KNOCKBACK_SOURCE_MODIFIERS = {
	GlobalPush     = 1.0,
	SkillKnockback = 0.5,
}

GameConstants.FALL_DAMAGE_MIN_HEIGHT = 3 -- forced drops below this cause no fall damage

function GameConstants.CalcWallCollisionDamage(targetMaxHp, blockedTiles, attackerStr, collisionType, sourceModifier)
	local collisionMult = GameConstants.COLLISION_MULTIPLIERS[collisionType] or 1.0
	local bossMod = 1.0 -- Boss HP% modifier stub — no bosses in Slice 2
	return math.round(targetMaxHp * 0.04 * blockedTiles * (1 + attackerStr / 200) * collisionMult * bossMod * sourceModifier)
end

function GameConstants.CalcFallDamage(targetMaxHp, fallHeight)
	if fallHeight < GameConstants.FALL_DAMAGE_MIN_HEIGHT then return 0 end
	return math.round(targetMaxHp * 0.04 * (fallHeight - 2) ^ 1.5)
end

-- Stat metadata for client UI breakdown (formula strings + parent stat)
GameConstants.STAT_META = {
	attackPower     = { label = "Attack Power",     formula = "WeaponDmg × (1 + STR/200)", parent = "STR" },
	effectiveWt     = { label = "Effective WT",     formula = "Weapon WT × (1 - STR/(200+STR))", parent = "STR" },
	rtDelayBonus    = { label = "RT Delay Bonus",   formula = "Base RT Delay × (1 + min(STR/(200+STR), 0.75))", parent = "STR" },
	force           = { label = "Force",            formula = "1 + floor(STR / 60)", parent = "STR" },
	movementRange   = { label = "Movement Range",   formula = "3 + floor(AGI / 60)", parent = "AGI" },
	evasiveness     = { label = "Evasiveness",      formula = "AGI / (AGI + 200)", parent = "AGI", unit = "%" },
	skillPotency    = { label = "Skill Potency",    formula = "1 + INT / (200 + INT)", parent = "INT", unit = "×" },
	maxMp           = { label = "Max MP",           formula = "20 + INT × 2", parent = "INT" },
	bonusSkillRange = { label = "Bonus Skill Range", formula = "floor(INT / 75)", parent = "INT" },
	mpRegen         = { label = "MP Regen",         formula = "2 + floor(INT / 40) per 1000 CT", parent = "INT" },
	maxHp           = { label = "Max HP",           formula = "50 + VIT × 4", parent = "VIT" },
	healEfficiency  = { label = "Heal Efficiency",  formula = "1 + VIT / 300", parent = "VIT", unit = "×" },
	defensePower    = { label = "Defense Power",    formula = "(Weapon + Off-Hand + Armor Defense) × (1 + VIT / 300)", parent = "VIT" },
	debuffResist    = { label = "Debuff Resist",    formula = "1 - VIT / (300 + VIT)", parent = "VIT", unit = "×" },
	rtDelayResist   = { label = "RT Delay Resist",  formula = "1 - VIT / (300 + VIT)", parent = "VIT", unit = "×" },
	stability       = { label = "Stability",        formula = "floor(VIT / 60)", parent = "VIT" },
	precision       = { label = "Precision",        formula = "DEX / (DEX + 200)", parent = "DEX", unit = "%" },
	jump            = { label = "Jump",             formula = "1 + floor(DEX / 60)", parent = "DEX" },
	channelReduction = { label = "Channel Speed",   formula = "DEX / (300 + DEX) reduction", parent = "DEX", unit = "%" },
	discoveryRadius = { label = "Discovery Radius", formula = "1 + floor(LUK / 60)", parent = "LUK" },
	unitFortune     = { label = "Unit Fortune",     formula = "LUK / (LUK + 200)", parent = "LUK", unit = "%" },
	startingRt      = { label = "Starting RT",      formula = "round(400 × (1 - 0.30 × LUK/(100+LUK)))", parent = "LUK" },
	basicAttackRt   = { label = "Basic Attack RT",  formula = "round((Base RT + Eff. Armor WT) × 0.10) + Effective Weapon WT", parent = "STR" },
}

--------------------------------------------------
-- FACING SYSTEM  (8-direction unit facing)
--
-- Every unit faces one of 8 directions. Facing affects
-- Hit Quality: attackers gain a Precision bonus when
-- striking from the side (+0.05) or back (+0.10).
--
-- Zone classification (relative to defender's facing):
--   Offset 0-1 → Front, Offset 2 → Side, Offset 3-4 → Back
--------------------------------------------------

GameConstants.FACING_VECTORS = {
	N  = { dx =  0, dy = -1 },
	NE = { dx =  1, dy = -1 },
	E  = { dx =  1, dy =  0 },
	SE = { dx =  1, dy =  1 },
	S  = { dx =  0, dy =  1 },
	SW = { dx = -1, dy =  1 },
	W  = { dx = -1, dy =  0 },
	NW = { dx = -1, dy = -1 },
}

GameConstants.FACING_INDEX = {
	N = 0, NE = 1, E = 2, SE = 3, S = 4, SW = 5, W = 6, NW = 7,
}

GameConstants.FACING_FROM_INDEX = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
-- Index 1-based: FACING_FROM_INDEX[1]="N" ... FACING_FROM_INDEX[8]="NW"
-- To convert 0-based index: FACING_FROM_INDEX[idx + 1]

GameConstants.FACING_PRECISION_BONUS = {
	Front = 0.00,
	Side  = 0.05,
	Back  = 0.10,
}

GameConstants.FACING_OPPOSITE = {
	N = "S", NE = "SW", E = "W", SE = "NW",
	S = "N", SW = "NE", W = "E", NW = "SE",
}

--- Return the nearest of 8 directions from (fromX,fromY) toward (toX,toY).
--- Returns nil if from == to (no direction change).
function GameConstants.CalcFacingFrom(fromX, fromY, toX, toY)
	local dx = toX - fromX
	local dy = toY - fromY
	if dx == 0 and dy == 0 then return nil end

	-- atan2 gives angle in radians; convert to 0-7 index (clockwise from N)
	-- math.atan2(dx, -dy) gives 0 = North, positive = clockwise
	local angle = math.atan2(dx, -dy)
	if angle < 0 then angle = angle + 2 * math.pi end

	local step = 2 * math.pi / 8  -- 45 degrees
	local idx = math.floor((angle + step / 2) / step) % 8
	return GameConstants.FACING_FROM_INDEX[idx + 1]
end

--- Determine the facing zone: "Front", "Side", or "Back".
--- Compares the direction FROM defender TO attacker against
--- the defender's facing direction.
function GameConstants.GetFacingZone(attackerX, attackerY, defenderX, defenderY, defenderFacing)
	if not defenderFacing then return "Front" end

	-- Direction from defender toward attacker (where the attack comes from)
	local attackDir = GameConstants.CalcFacingFrom(defenderX, defenderY, attackerX, attackerY)
	if not attackDir then return "Front" end -- same tile

	local attackIdx = GameConstants.FACING_INDEX[attackDir]
	local defIdx    = GameConstants.FACING_INDEX[defenderFacing]
	if not attackIdx or not defIdx then return "Front" end

	local offset = (attackIdx - defIdx) % 8
	if offset > 4 then offset = 8 - offset end

	-- offset 0-1 = Front (forward arc), 2 = Side, 3-4 = Back (rear arc)
	if offset <= 1 then
		return "Front"
	elseif offset == 2 then
		return "Side"
	else
		return "Back"
	end
end

--- Return the Precision bonus for a facing zone.
function GameConstants.GetFacingPrecisionBonus(zone)
	return GameConstants.FACING_PRECISION_BONUS[zone] or 0.00
end

--- Return the facing vector {dx, dy} for a direction string.
function GameConstants.GetFacingVector(facing)
	return GameConstants.FACING_VECTORS[facing] or GameConstants.FACING_VECTORS.S
end

--- Return the tile directly behind a unit (opposite of facing).
function GameConstants.GetRearTile(unitX, unitY, unitFacing)
	local vec = GameConstants.GetFacingVector(unitFacing)
	return unitX - vec.dx, unitY - vec.dy
end

--- Return the opposite direction.
function GameConstants.GetOppositeFacing(facing)
	return GameConstants.FACING_OPPOSITE[facing] or "N"
end

--- Validate a facing direction string.
function GameConstants.IsValidFacing(facing)
	return GameConstants.FACING_INDEX[facing] ~= nil
end

--- Get cone tiles for a facing-based cone skill.
--- coneSize = number of rows (2 → 3 tiles, 3 → 6 tiles).
--- Returns array of {x, y} tiles (narrow wedge per DB spec).
function GameConstants.GetConeTiles(originX, originY, facing, coneSize)
	local fv = GameConstants.GetFacingVector(facing)
	-- Perpendicular vector: rotate 90° clockwise
	local px, py = -fv.dy, fv.dx
	local tiles = {}
	for row = 1, coneSize do
		-- Center tile of this row
		local cx = originX + fv.dx * row
		local cy = originY + fv.dy * row
		table.insert(tiles, { x = cx, y = cy })
		-- Spread tiles: ±1 to ±(row-1) perpendicular
		for spread = 1, row - 1 do
			table.insert(tiles, { x = cx + px * spread, y = cy + py * spread })
			table.insert(tiles, { x = cx - px * spread, y = cy - py * spread })
		end
	end
	return tiles
end

return GameConstants