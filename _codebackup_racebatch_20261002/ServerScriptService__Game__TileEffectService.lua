-- TileEffectService.lua
-- CTRBLXAI | Slice 3 — Tile Effect Lifecycle Engine
--
-- Manages persistent tile effects (Burning, Wet, Frozen, Steam,
-- Static Cloud, Poison Cloud). Each effect has a CT-based duration,
-- optional periodic tick damage, occupy/cross effects, and element
-- reactions with other tile effects.
--
-- Data source: GameConstants.TILE_EFFECTS
-- Rules source: terrain_effects DB table (Tile Effect Catalog)
--               trigger_safety TRG-012 (Periodic Propagation Guard)
--               trigger_safety TRG-013 (Elemental One-Pass Processing)
--
-- Integration points:
--   BattleCoordinator.AdvanceClock → ProcessCtTick (decay + periodic damage)
--   Movement resolution → OnUnitEntersTile (cross effects)
--   Start of unit turn → OnUnitStartTurn (occupy effects)
--   CombatResolver element triggers → ApplyTileEffect (element reactions)
--   BattleVisualBroadcaster → TileEffectApplied / TileEffectRemoved

local GameConstants = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Shared")
		:WaitForChild("GameConstants")
)

local TileEffectService = {}

--------------------------------------------------
-- STATE
-- effects[tileKey] = { id, remainingCt, ownerId, tickAccum }
-- tileKey = "x,y" string for fast lookup
--------------------------------------------------

local effects = {}    -- active tile effects
local _mapWidth = 8
local _mapHeight = 8
local _statusService = nil   -- injected to avoid circular require
local _bvb = nil             -- BattleVisualBroadcaster, injected
local _allUnits = nil        -- cached live unit list (state.units ref) for explosions

local function tileKey(x, y) return x .. "," .. y end

-- PER-TILE BASE FLOOR-EFFECT SLOT (map_gen_rules row 67 'Chasm-Floor Effect
-- Permanence', Slice 5 2026-10-02). baseFloor[tileKey] = effectId of the PERMANENT
-- floor effect generation placed on a chasm floor (Vines on Plains/Forest, Tar Pit
-- on Castle). While a transient effect (Burning from Fire, Steam, Wet, ...) sits on
-- the tile the floor effect is suppressed; when the tile becomes bare again the
-- base effect RE-ESTABLISHES if the terrain still allows it (Vines need Organic
-- ground, Tar Pit needs Solid ground). If the terrain no longer allows it the slot
-- is cleared — the loss is permanent. Terrain transforms of the floor itself
-- (Quicksand->Mud, Molten->Rocky, Deep Water->Ice) are permanent and never revert.
local baseFloor = {}

-- Terrain tag a floor effect needs in order to exist / re-establish.
local FLOOR_EFFECT_REQUIRED_TAG = {
	Vines     = "Organic",  -- terrain_effects Vines: "Cannot exist on incompatible terrain"
	["Tar Pit"] = "Solid",
}

local function terrainHasTag(tileX, tileY, tag)
	local terrainId = GameConstants.GetTerrainId(tileX, tileY)
	local tDef = GameConstants.TERRAIN_TYPES[terrainId]
	if not tDef or not tDef.tags then return false end
	for _, t in ipairs(tDef.tags) do
		if t == tag then return true end
	end
	return false
end

local function floorEffectCompatible(tileX, tileY, effectId)
	local need = FLOOR_EFFECT_REQUIRED_TAG[effectId]
	if not need then return true end
	return terrainHasTag(tileX, tileY, need)
end

-- Re-establish a tile's base floor effect if the tile is bare. Returns true if applied.
local function tryReinstateFloor(tileX, tileY)
	local key = tileKey(tileX, tileY)
	local baseId = baseFloor[key]
	if not baseId or effects[key] then return false end
	if not floorEffectCompatible(tileX, tileY, baseId) then
		baseFloor[key] = nil
		print(string.format(
			"[TileEffectService] Floor %s at (%d,%d) LOST permanently — terrain %s no longer compatible",
			baseId, tileX, tileY, tostring(GameConstants.GetTerrainId(tileX, tileY))))
		return false
	end
	print(string.format("[TileEffectService] Floor %s RE-ESTABLISHED at (%d,%d)", baseId, tileX, tileY))
	TileEffectService.ApplyTileEffect(tileX, tileY, baseId, "floor", nil, true)
	return true
end

function TileEffectService.Init(mapWidth, mapHeight)
	_mapWidth = mapWidth
	_mapHeight = mapHeight
	effects = {}
	baseFloor = {}
end

-- Register + apply a permanent chasm-floor effect (called at battle start from the
-- generated map's floorEffects list). Skips silently if the terrain is incompatible.
function TileEffectService.SetBaseFloorEffect(tileX, tileY, effectId)
	if not GameConstants.TILE_EFFECTS[effectId] then return false end
	if not floorEffectCompatible(tileX, tileY, effectId) then return false end
	baseFloor[tileKey(tileX, tileY)] = effectId
	TileEffectService.ApplyTileEffect(tileX, tileY, effectId, "floor", nil, true)
	return true
end

function TileEffectService.GetBaseFloorEffect(tileX, tileY)
	return baseFloor[tileKey(tileX, tileY)]
end

-- Seed every generated floor effect ({ {x, y, effectId}, ... }). Returns count applied.
function TileEffectService.SeedFloorEffects(list)
	local n = 0
	for _, fe in ipairs(list or {}) do
		if TileEffectService.SetBaseFloorEffect(fe.x, fe.y, fe.effectId) then n = n + 1 end
	end
	if n > 0 then
		print(string.format("[TileEffectService] Seeded %d permanent chasm-floor effect tile(s)", n))
	end
	return n
end

-- Inject dependencies to avoid circular requires
function TileEffectService.SetStatusService(ss)
	_statusService = ss
end

function TileEffectService.SetBroadcaster(bvb)
	_bvb = bvb
end

--------------------------------------------------
-- ELEMENT REACTIONS
-- When a new effect is applied to a tile that already has an effect,
-- the two may react to produce a third effect (or clear both).
--
-- TRG-013: One pass per incoming packet. Later-stage transformation
-- does not return same packet to earlier stage.
--------------------------------------------------

local REACTIONS = {
	-- existing effect → incoming element → result (nil = both cleared)
	Burning = { Water = "Steam",   Ice = "Steam"    },
	Wet     = { Fire  = "Steam",   Ice = "Frozen"   },
	Frozen  = { Fire  = "Wet"                       },
	Steam   = { Electric = "Static Cloud", Wind = nil },
	["Static Cloud"] = { Wind = nil                  },
	["Poison Cloud"] = { Fire = "Explosion"          },
	-- terrain_effects rows 29/30 (+ GameConstants.TILE_EFFECTS reactions): Fire ignites.
	Vines            = { Fire = "Burning"            },
	["Tar Pit"]      = { Fire = "Burning"            },
}

local function resolveReaction(existingId, incomingElement)
	local reactions = REACTIONS[existingId]
	if reactions and reactions[incomingElement] ~= nil then
		return true, reactions[incomingElement]  -- reacted, result (nil = clear)
	end
	return false, nil  -- no reaction
end

--------------------------------------------------
-- APPLY / REMOVE
--------------------------------------------------

function TileEffectService.ApplyTileEffect(tileX, tileY, effectId, ownerId, allUnits, skipTransform)
	-- skipTransform (optional): do not run the base-terrain element transform for
	-- this placement. Used when a permanent floor effect is (re)seeded, and when the
	-- incoming packet was consumed by reacting with a tile's base floor effect
	-- (TRG-013 one-pass: Fire that ignites Vines does not ALSO turn the Grassland
	-- floor to Sand — map_gen_rules row 67).
	if allUnits then _allUnits = allUnits end
	if tileX < 1 or tileX > _mapWidth or tileY < 1 or tileY > _mapHeight then return end

	local def = GameConstants.TILE_EFFECTS[effectId]
	if not def then
		print(string.format("[TileEffectService] Unknown effect: %s", tostring(effectId)))
		return
	end

	local key = tileKey(tileX, tileY)
	local existing = effects[key]

	-- Check element reaction with existing effect
	if existing then
		local reacted, resultId = resolveReaction(existing.id, def.element)
		if reacted then
			print(string.format(
				"[TileEffectService] Reaction: %s + %s → %s at (%d,%d)",
				existing.id, effectId, tostring(resultId), tileX, tileY
			))
			local consumedByFloor = (baseFloor[key] ~= nil and baseFloor[key] == existing.id)
			-- Remove existing
			TileEffectService.RemoveTileEffect(tileX, tileY)

			-- Apply result if not nil (nil = both cleared)
			if resultId and resultId ~= "Explosion" then
				TileEffectService.ApplyTileEffect(tileX, tileY, resultId, ownerId, allUnits, consumedByFloor)
			end
			-- Explosion: source tile effect (Oily/Poison Cloud) already removed above.
			-- Queue an explosion event (TRG-011). The generic explosion carries NO
			-- blanket HP damage — damagePayload is per-source (nil here = reaction-
			-- triggered, tile-lowering + terrain-chain only; barrel bombs pass a payload).
			if resultId == "Explosion" then
				-- Reaction-triggered explosion: diamond r1, NO HP payload (tile-lowering +
				-- terrain-chain only). allUnits threaded so collapse occupant effects fire.
				TileEffectService.QueueExplosion(tileX, tileY, 0, ownerId, nil, allUnits, "diamond")
			end
			-- Tile left bare by the reaction (nil / Explosion result): floor returns.
			if not effects[key] then
				tryReinstateFloor(tileX, tileY)
			end
			return
		end

		-- No reaction: new effect replaces old
		TileEffectService.RemoveTileEffect(tileX, tileY)
	end

	-- Place new effect
	effects[key] = {
		id          = effectId,
		remainingCt = def.durationCt or 900,
		ownerId     = ownerId,
		tickAccum   = 0,
		tileX       = tileX,
		tileY       = tileY,
	}

	print(string.format(
		"[TileEffectService] Applied %s at (%d,%d) | Duration: %d CT | Owner: %s",
		effectId, tileX, tileY, def.durationCt or 900, tostring(ownerId)
	))

	-- Terrain transformation: element vs base terrain (Fire on Grassland → Sand)
	-- (protected span tiles are exempt inside GameConstants.TransformTerrain)
	if not skipTransform then
		GameConstants.TransformTerrain(tileX, tileY, def.element)
	end

	if _bvb and _bvb.TileEffectApplied then
		_bvb.TileEffectApplied(tileX, tileY, effectId, def.durationCt or 900)
	end
end

function TileEffectService.RemoveTileEffect(tileX, tileY)
	local key = tileKey(tileX, tileY)
	local eff = effects[key]
	if eff then
		print(string.format("[TileEffectService] Removed %s from (%d,%d)", eff.id, tileX, tileY))
		effects[key] = nil
		if _bvb and _bvb.TileEffectRemoved then
			_bvb.TileEffectRemoved(tileX, tileY, eff.id)
		end
	end
end

function TileEffectService.GetTileEffect(tileX, tileY)
	return effects[tileKey(tileX, tileY)]
end

function TileEffectService.GetAllEffects()
	return effects
end

--------------------------------------------------
-- CT TICK — called from BattleCoordinator.AdvanceClock
--
-- Decrements remaining CT on all effects.
-- Fires periodic tick damage on effects with tickCt.
-- TRG-012: Each source processed once per interval.
--------------------------------------------------

function TileEffectService.ProcessCtTick(ctElapsed, allUnits)
	if allUnits then _allUnits = allUnits end
	local toRemove = {}

	for key, eff in pairs(effects) do
		local def = GameConstants.TILE_EFFECTS[eff.id]
		if not def then
			table.insert(toRemove, key)
		else
			-- Unlimited-duration effects (durationCt = -1: Oily, Tar Pit, Vines) never decay.
			local unlimited = (def.durationCt == -1)
			-- Decrement duration (skip for unlimited)
			if not unlimited then
				eff.remainingCt = eff.remainingCt - ctElapsed
			end
			if not unlimited and eff.remainingCt <= 0 then
				table.insert(toRemove, key)
			else
				-- Periodic tick damage
				if def.tickCt and def.tickCt > 0 then
					eff.tickAccum = eff.tickAccum + ctElapsed
					while eff.tickAccum >= def.tickCt do
						eff.tickAccum = eff.tickAccum - def.tickCt
						-- Find unit on this tile
						if allUnits then
							for _, u in ipairs(allUnits) do
								if u.isAlive and u.tileX == eff.tileX and u.tileY == eff.tileY then
									local damage = math.round(u.maxHp * (def.tickDamage or 0.15))
									if damage > 0 then
										u.currentHp = math.max(0, u.currentHp - damage)
										if u.currentHp <= 0 then u.isAlive = false end
										print(string.format(
											"[TileEffectService] %s tick: %s takes %d %s damage at (%d,%d) | HP: %d/%d",
											eff.id, u.name, damage, def.tickElement or "?",
											eff.tileX, eff.tileY, u.currentHp, u.maxHp
										))
										if _bvb and _bvb.DotDamage then
											_bvb.DotDamage(u, eff.id, damage)
										end
									end
								end
							end
						end
					end
				end
			end
		end
	end

	-- Remove expired effects
	for _, key in ipairs(toRemove) do
		local eff = effects[key]
		if eff then
			print(string.format("[TileEffectService] %s expired at (%d,%d)", eff.id, eff.tileX, eff.tileY))
			if _bvb and _bvb.TileEffectRemoved then
				_bvb.TileEffectRemoved(eff.tileX, eff.tileY, eff.id)
			end
			effects[key] = nil
			-- Transient effect gone: a permanent chasm-floor effect returns if the
			-- ground still allows it (map_gen_rules row 67).
			tryReinstateFloor(eff.tileX, eff.tileY)
		end
	end
end

--------------------------------------------------
-- UNIT EVENTS
-- Called when a unit enters a tile (movement) or starts turn.
--------------------------------------------------

-- Cross effect: applied when unit moves THROUGH a tile
function TileEffectService.OnUnitEntersTile(unit, tileX, tileY)
	local eff = effects[tileKey(tileX, tileY)]
	if not eff or not unit.isAlive then return end

	local def = GameConstants.TILE_EFFECTS[eff.id]
	if not def then return end

	-- Cross effects: inflict status
	if def.crossEffect and _statusService then
		_statusService.ApplyStatus(unit, def.crossEffect, eff.ownerId or "tile")
		print(string.format(
			"[TileEffectService] Cross effect: %s on %s (entering %s at %d,%d)",
			def.crossEffect, unit.name, eff.id, tileX, tileY
		))
	end
end

--------------------------------------------------
-- CHASM-FLOOR GROUND EFFECTS (map_gen_rules row 65 point 1; terrain_effects
-- rows 14 Molten / 16 Tainted Ground). Neither ground effect existed in code
-- before Slice 5. Applied on chasm-floor tiles (GameConstants.IsChasmFloor);
-- GameConstants.GROUND_EFFECTS_CHASM_ONLY = false would extend them map-wide.
--   Tainted Ground — start of the unit's turn: non-undead lose 10% Max MP;
--                    Undead/Demons restore 10% Max MP instead.
--   Molten         — end of the unit's own turn: Burn +25% Max HP (Fire).
-- Deep Water (Drowning) / Quicksand (Sinking) already apply on entry via the
-- terrain trigger paths; Vines / Tar Pit are tile effects (above).
--------------------------------------------------

local MOLTEN_END_TURN_PCT  = 0.25  -- terrain_effects row 14 "End Turn: Burn +25% Max HP"
local TAINTED_MP_PCT       = 0.10  -- terrain_effects row 16 "10% Max MP"

local function groundEffectsApply(tileX, tileY)
	if GameConstants.GROUND_EFFECTS_CHASM_ONLY == false then return true end
	return GameConstants.IsChasmFloor and GameConstants.IsChasmFloor(tileX, tileY) or false
end

local _raceData = nil
local function isUndeadOrDemon(unit)
	if not unit or not unit.raceId then return false end
	if not _raceData then
		local ok, rd = pcall(function()
			return require(game:GetService("ReplicatedStorage"):WaitForChild("Content"):WaitForChild("RaceData"))
		end)
		_raceData = ok and rd or {}
	end
	local entry = _raceData.GetRace and _raceData.GetRace(unit.raceId) or nil
	if entry and entry.tags then
		for _, tag in ipairs(entry.tags) do
			if tag == "Undead" or tag == "Demon" then return true end
		end
	end
	return false
end

local function applyTaintedStartTurn(unit)
	if GameConstants.GetTerrainId(unit.tileX, unit.tileY) ~= "Tainted Ground" then return end
	if not groundEffectsApply(unit.tileX, unit.tileY) then return end
	local maxMp = unit.maxMp or 0
	local amt = math.round(maxMp * TAINTED_MP_PCT)
	if amt <= 0 then return end
	local before = unit.currentMp or 0
	if isUndeadOrDemon(unit) then
		unit.currentMp = math.min(maxMp, before + amt)
	else
		unit.currentMp = math.max(0, before - amt)
	end
	print(string.format("[TileEffectService] Tainted Ground: %s MP %d -> %d at (%d,%d)",
		unit.name, before, unit.currentMp, unit.tileX, unit.tileY))
end

local function applyMoltenEndTurn(unit)
	if GameConstants.GetTerrainId(unit.tileX, unit.tileY) ~= "Molten" then return end
	if not groundEffectsApply(unit.tileX, unit.tileY) then return end
	local dmg = math.round((unit.maxHp or 0) * MOLTEN_END_TURN_PCT)
	if dmg <= 0 then return end
	unit.currentHp = math.max(0, unit.currentHp - dmg)
	if unit.currentHp <= 0 then unit.isAlive = false end
	print(string.format("[TileEffectService] Molten: %s ends turn on lava, takes %d Fire damage | HP: %d/%d",
		unit.name, dmg, unit.currentHp, unit.maxHp))
	if _bvb and _bvb.DotDamage then
		_bvb.DotDamage(unit, "Molten", dmg)
	end
end

-- Occupy effect: applied at start of unit's turn
function TileEffectService.OnUnitStartTurn(unit)
	if not unit.isAlive then return end
	applyTaintedStartTurn(unit)
	local eff = effects[tileKey(unit.tileX, unit.tileY)]
	if not eff then return end

	local def = GameConstants.TILE_EFFECTS[eff.id]
	if not def then return end

	-- Occupy effects: inflict status
	if def.occupyEffect and _statusService then
		_statusService.ApplyStatus(unit, def.occupyEffect, eff.ownerId or "tile")
		print(string.format(
			"[TileEffectService] Occupy effect: %s on %s (standing on %s at %d,%d)",
			def.occupyEffect, unit.name, eff.id, unit.tileX, unit.tileY
		))
	end
end

--------------------------------------------------
-- BURNING SPREAD (DB spec rows 40-43)
-- Every `spread.cadenceCt` (500 CT), each Burning source may ignite
-- orthogonally-adjacent Flammable BASE terrain within |elevDelta| <= 1.
-- New tiles start at full duration. Base terrain is NOT transformed.
-- TRG-012: each source spreads at most once per interval; tiles ignited
-- this interval cannot spread again until the next interval (no same-tick chain).
--------------------------------------------------

local SPREAD_DIRS = { {0,1}, {0,-1}, {1,0}, {-1,0} }  -- orthogonal only

function TileEffectService.ProcessSpread(ctElapsed)
	-- Snapshot current Burning sources eligible to spread this call.
	-- Accumulate per-source spread timer; only fire when cadence reached.
	local newIgnitions = {}   -- collected first, applied after (no same-tick chain)

	for key, eff in pairs(effects) do
		if eff.id == "Burning" then
			local def = GameConstants.TILE_EFFECTS.Burning
			local spread = def and def.spread
			if spread then
				eff.spreadAccum = (eff.spreadAccum or 0) + ctElapsed
				if eff.spreadAccum >= spread.cadenceCt then
					eff.spreadAccum = eff.spreadAccum - spread.cadenceCt
					local srcElev = GameConstants.GetElevation(eff.tileX, eff.tileY)
					for _, d in ipairs(SPREAD_DIRS) do
						local nx, ny = eff.tileX + d[1], eff.tileY + d[2]
						if nx >= 1 and nx <= _mapWidth and ny >= 1 and ny <= _mapHeight then
							local tgtKey = tileKey(nx, ny)
							-- Skip if already has ANY effect (already-Burning or incompatible)
							if not effects[tgtKey] then
								-- Target must be Flammable BASE terrain
								local terrainId = GameConstants.GetTerrainId(nx, ny)
								local terrainDef = GameConstants.TERRAIN_TYPES[terrainId]
								local isFlammable = false
								if terrainDef and terrainDef.tags then
									for _, t in ipairs(terrainDef.tags) do
										if t == spread.targetTag then isFlammable = true; break end
									end
								end
								if isFlammable then
									local tgtElev = GameConstants.GetElevation(nx, ny)
									if math.abs(srcElev - tgtElev) <= spread.elevDelta then
										newIgnitions[tgtKey] = { x = nx, y = ny, owner = eff.ownerId }
									end
								end
							end
						end
					end
				end
			end
		end
	end

	-- Apply collected ignitions (deterministic; new tiles get full duration).
	for _, ig in pairs(newIgnitions) do
		if not effects[tileKey(ig.x, ig.y)] then
			print(string.format("[TileEffectService] Burning SPREAD → (%d,%d)", ig.x, ig.y))
			TileEffectService.ApplyTileEffect(ig.x, ig.y, "Burning", ig.owner)
		end
	end
end

--------------------------------------------------
-- EXPLOSION (DB spec rows 47-52)
-- Instantaneous AOE tile EVENT. Diamond radius 1 (origin + 4 orthogonal),
-- elevation clamp +/-2. Intrinsic effects: LOWER affected tiles + trigger
-- terrain chains. HP damage is PER-SOURCE (damagePayload; nil = none).
-- Chains: any Oily/Poison Cloud in the AOE is queued as a secondary
-- explosion (depth+1), damage = payload * chainReductionFactor^depth,
-- bounded by maxChainDepth. Queue-based (TRG-011), no recursion.
--------------------------------------------------

local EXPLOSION_DIRS_DIAMOND = { {0,0}, {0,1}, {0,-1}, {1,0}, {-1,0} }  -- diamond r1 incl. origin
local EXPLOSION_DIRS_BOX = {  -- 3x3 box r1 (Chebyshev radius 1 = 9 tiles) incl. origin
	{0,0}, {0,1}, {0,-1}, {1,0}, {-1,0}, {1,1}, {1,-1}, {-1,1}, {-1,-1},
}

-- Collapse a Cracked Ground tile (DB: Cracked Ground triggerEffect="Collapse").
-- Drops the tile -3 elevation (floor-clamped) and, if an alive unit rides the drop,
-- adds the +50 RT delay to that occupant. Fall damage is NOT applied here — it is
-- handled by the existing fall-damage system (GameConstants.CalcFallDamage) when a
-- unit is carried down by a forced drop. NO flat collapse payload (per spec).
local function collapseTile(tx, ty, allUnits)
	local drop = GameConstants.LowerElevation(tx, ty, 3)
	print(string.format("[TileEffectService] Cracked Ground COLLAPSE at (%d,%d) | drop %d elevation", tx, ty, drop))
	if allUnits and drop > 0 then
		for _, u in ipairs(allUnits) do
			if u.isAlive and u.tileX == tx and u.tileY == ty then
				u.remainingRt = (u.remainingRt or 0) + 50
				print(string.format("[TileEffectService] %s rides collapse: +50 RT (now %d)", u.name, u.remainingRt))
				-- Fall damage: existing fall-damage rule applies when the drop is a
				-- forced downward displacement of >= FALL_DAMAGE_MIN_HEIGHT.
				local fall = GameConstants.CalcFallDamage(u.maxHp, drop)
				if fall > 0 then
					u.currentHp = math.max(0, u.currentHp - fall)
					if u.currentHp <= 0 then u.isAlive = false end
					print(string.format("[TileEffectService] %s takes %d fall damage from collapse | HP: %d/%d",
						u.name, fall, u.currentHp, u.maxHp))
					if _bvb and _bvb.DotDamage then
						_bvb.DotDamage(u, "Collapse", fall)
					end
				end
			end
		end
	end
end

-- Apply the explosion's intrinsic terrain effect to one tile:
--   1. Lower the tile by 1 elevation (floor-clamped to 1).
--   2. Rocky @ Elev >= 8  -> transform to Cracked Ground (crack, no drop yet).
--   3. Cracked Ground     -> trigger Collapse (-3 drop + occupant +50 RT + fall dmg).
-- NOTE: elevation is read BEFORE the -1 lowering for the Rocky>=8 threshold test so
-- the crack fires on terrain that was Rocky at >=8 at the moment of the blast.
local function applyExplosionTerrain(tx, ty, allUnits)
	-- Protected bridge spans (map_gen_rules row 60 points 2-3): no lowering, no
	-- Rocky -> Cracked Ground crack, therefore no collapse. HP payload still applies.
	if GameConstants.IsProtectedSpan(tx, ty) then
		print(string.format("[TileEffectService] Explosion on PROTECTED span (%d,%d): terrain/elevation unchanged", tx, ty))
		return
	end
	local terrainId = GameConstants.GetTerrainId(tx, ty)
	local elevBefore = GameConstants.GetElevation(tx, ty)

	-- 1. Lower the tile by 1 (floor clamp = 1).
	GameConstants.LowerElevation(tx, ty, 1)

	-- 2/3. Terrain chain.
	if terrainId == "Rocky" and elevBefore >= 8 then
		GameConstants.SetTerrainId(tx, ty, "Cracked Ground")
		print(string.format("[TileEffectService] Rocky@%d CRACKED -> Cracked Ground at (%d,%d)", elevBefore, tx, ty))
	elseif terrainId == "Cracked Ground" then
		collapseTile(tx, ty, allUnits)
	end
end

-- Internal: process a SINGLE explosion event. Returns a list of chained
-- explosive sources discovered in the AOE (to be appended to the drain queue
-- by the caller). Never calls itself — chaining is queue-driven (TRG-011).
local function processOneExplosion(x, y, depth, ownerId, damagePayload, allUnits, pattern, reduction)
	local dirs = (pattern == "box") and EXPLOSION_DIRS_BOX or EXPLOSION_DIRS_DIAMOND
	local originElev = GameConstants.GetElevation(x, y)
	local chained = {}

	print(string.format("[TileEffectService] EXPLOSION at (%d,%d) depth %d | payload=%s | pattern=%s",
		x, y, depth, tostring(damagePayload), pattern or "diamond"))

	for _, d in ipairs(dirs) do
		local tx, ty = x + d[1], y + d[2]
		if tx >= 1 and tx <= _mapWidth and ty >= 1 and ty <= _mapHeight then
			local tElev = GameConstants.GetElevation(tx, ty)
			if math.abs(tElev - originElev) <= 2 then
				-- Intrinsic effect 1: lower the tile + trigger terrain chains
				-- (Rocky@>=8 -> Cracked Ground, Cracked Ground -> Collapse).
				applyExplosionTerrain(tx, ty, allUnits)

				-- Intrinsic effect 2: per-source HP damage. damagePayload is a FRACTION
				-- of Max HP (e.g. 0.25 for Barrel Bomb / Land Mine). nil/0 = none
				-- (reaction-triggered explosions carry no HP damage). Boss resistance is
				-- applied DOWNSTREAM by the damage pipeline — not special-cased here.
				if damagePayload and damagePayload > 0 and allUnits then
					local payloadPct = damagePayload * (reduction ^ depth)
					for _, u in ipairs(allUnits) do
						if u.isAlive and u.tileX == tx and u.tileY == ty then
							local dmg = math.round(u.maxHp * payloadPct)
							if dmg > 0 then
								u.currentHp = math.max(0, u.currentHp - dmg)
								if u.currentHp <= 0 then u.isAlive = false end
								print(string.format(
									"[TileEffectService] EXPLOSION: %s takes %d Fire damage at (%d,%d) | HP: %d/%d",
									u.name, dmg, tx, ty, u.currentHp, u.maxHp))
								if _bvb and _bvb.ExplosionDamage then
									_bvb.ExplosionDamage(tx, ty, dmg)
								elseif _bvb and _bvb.DotDamage then
									_bvb.DotDamage(u, "Explosion", dmg)
								end
							end
						end
					end
				end

				-- Chain: a secondary explosive source in the AOE is COLLECTED (not
				-- recursed). The caller appends it to the persisted drain queue.
				local eff = effects[tileKey(tx, ty)]
				if eff and (eff.id == "Oily" or eff.id == "Poison Cloud") and not (tx == x and ty == y) then
					TileEffectService.RemoveTileEffect(tx, ty)  -- source consumed once
					table.insert(chained, { x = tx, y = ty, depth = depth + 1 })
				end
			end
		end
	end

	return chained
end

-- Public: resolve an explosion and its full chain via a TRUE append-to-queue
-- structure with iterative drain (TRG-011). No call-stack recursion. Hard cap
-- of 128 explosion events per action; cooperative yield every 32 events.
function TileEffectService.QueueExplosion(x, y, depth, ownerId, damagePayload, allUnits, pattern)
	allUnits = allUnits or _allUnits
	local def = GameConstants.TILE_EFFECTS.Oily and GameConstants.TILE_EFFECTS.Oily.explosion
	local maxDepth = (def and def.maxChainDepth) or 4
	local reduction = (def and def.chainReductionFactor) or 0.5

	-- Persisted FIFO queue of pending explosion events (TRG-011).
	local queue = { { x = x, y = y, depth = depth or 0 } }
	local head = 1
	local processed = 0
	local EVENT_CAP = 128   -- TRG-011 hard cap per action
	local YIELD_EVERY = 32  -- cooperative yield cadence

	while head <= #queue do
		local ev = queue[head]
		head = head + 1

		if ev.depth > maxDepth then
			print(string.format("[TileEffectService] Explosion chain terminated at depth %d (cap)", ev.depth))
		else
			local chained = processOneExplosion(
				ev.x, ev.y, ev.depth, ownerId, damagePayload, allUnits, pattern, reduction
			)
			-- Append discovered chained sources to the tail of the queue.
			for _, c in ipairs(chained) do
				table.insert(queue, c)
			end

			processed = processed + 1
			if processed >= EVENT_CAP then
				print(string.format(
					"[TileEffectService] Explosion event cap (%d) reached — chain halted", EVENT_CAP))
				break
			end
			if processed % YIELD_EVERY == 0 then
				task.wait()  -- cooperative yield every 32 events (TRG-011)
			end
		end
	end
end

--------------------------------------------------
-- TAR PIT PETRIFY (DB spec rows 44-46)
-- OnUnitEndTurn: if the unit ends its turn on ANY Tar Pit tile, increment
-- unit.tarPitTurns; at threshold (2) apply Petrify. If the unit ends its
-- turn NOT on a Tar Pit, reset the counter to 0 (move off & back resets).
--------------------------------------------------

function TileEffectService.OnUnitEndTurn(unit)
	if not unit or not unit.isAlive then return end
	-- Molten chasm floor: end-of-own-turn burn (terrain_effects row 14).
	applyMoltenEndTurn(unit)
	if not unit.isAlive then return end
	local eff = effects[tileKey(unit.tileX, unit.tileY)]
	local onTarPit = eff and eff.id == "Tar Pit"

	if onTarPit then
		local def = GameConstants.TILE_EFFECTS["Tar Pit"]
		local threshold = (def and def.petrifyOnConsecutiveTurns) or 2
		unit.tarPitTurns = (unit.tarPitTurns or 0) + 1
		print(string.format("[TileEffectService] %s ends turn on Tar Pit (%d/%d)",
			unit.name, unit.tarPitTurns, threshold))
		if unit.tarPitTurns >= threshold and _statusService then
			_statusService.ApplyStatus(unit, "Petrify", eff.ownerId or "tile")
			print(string.format("[TileEffectService] %s PETRIFIED by Tar Pit", unit.name))
			unit.tarPitTurns = 0  -- reset after applying
		end
	else
		-- Not on Tar Pit at turn-end → reset counter
		if unit.tarPitTurns and unit.tarPitTurns > 0 then
			unit.tarPitTurns = 0
		end
	end
end

return TileEffectService
