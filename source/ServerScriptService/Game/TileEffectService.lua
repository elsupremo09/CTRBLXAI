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

local function tileKey(x, y) return x .. "," .. y end

function TileEffectService.Init(mapWidth, mapHeight)
	_mapWidth = mapWidth
	_mapHeight = mapHeight
	effects = {}
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

function TileEffectService.ApplyTileEffect(tileX, tileY, effectId, ownerId)
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
			-- Remove existing
			TileEffectService.RemoveTileEffect(tileX, tileY)

			-- Apply result if not nil (nil = both cleared)
			if resultId and resultId ~= "Explosion" then
				TileEffectService.ApplyTileEffect(tileX, tileY, resultId, ownerId)
			end
			-- Explosion handling: would trigger TRG-011 explosion queue (future)
			if resultId == "Explosion" then
				print(string.format("[TileEffectService] Explosion at (%d,%d) — queue not yet implemented", tileX, tileY))
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
	GameConstants.TransformTerrain(tileX, tileY, def.element)

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
	local toRemove = {}

	for key, eff in pairs(effects) do
		local def = GameConstants.TILE_EFFECTS[eff.id]
		if not def then
			table.insert(toRemove, key)
		else
			-- Decrement duration
			eff.remainingCt = eff.remainingCt - ctElapsed
			if eff.remainingCt <= 0 then
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

-- Occupy effect: applied at start of unit's turn
function TileEffectService.OnUnitStartTurn(unit)
	if not unit.isAlive then return end
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

return TileEffectService
