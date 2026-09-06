-- TileCrossEffectService.lua
-- CTRBLXAI | Slice 2 — Terrain Cross-Effect Resolution
--
-- Resolves what happens when a unit ENTERS a tile (voluntary movement
-- or forced displacement). This is the hook between movement/displacement
-- and terrain interaction.
--
-- DB source: terrain_effects col_5 (Cross Effect)
--   Clear, Grassland, Rocky, Wooden Floor = no cross effect
--   Sand, Shallow Water = +1 move cost (already in BFS, no cross effect)
--   Mud = +2 move cost (already in BFS, no cross effect)
--   Ice = Sliding Knockback (continue momentum in direction of entry)
--   Deep Water = +2 move cost + Apply Drowning (trigger_effect)
--   Quicksand = Movement prohibited (impassable) + Apply Sinking (if forced in)
--   Burning (tile effect) = Inflict Burn
--   Poison Cloud (tile effect) = Inflict Poison
--   Frozen (tile effect) = Sliding Knockback
--
-- Architecture:
--   OnTileEntered(unit, tileX, tileY, entryDirection, isForced, allUnits)
--   Returns a list of effects to apply: { {type="status", statusId="Drowning"}, {type="slide", dx=1, dy=0}, ... }
--   The CALLER applies these effects (CommandService for voluntary move,
--   DisplacementService for forced move). This module is pure resolution.

local GameConstants = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Shared")
		:WaitForChild("GameConstants")
)

local TileCrossEffectService = {}

--------------------------------------------------
-- Cross-effect definitions by terrain type.
-- Each entry returns a function(unit, tileX, tileY, entryDir, isForced)
-- that returns an array of effect descriptors.
--------------------------------------------------

local CROSS_EFFECTS = {
	-- Ice: Sliding Knockback — unit continues in the direction they entered.
	-- If the next tile is also Ice, they slide again (chain). Slide stops at
	-- non-Ice, blocker, occupied tile, map edge, or elevation change.
	-- DB: "Sliding Knockback" cross effect on Ice terrain.
	Ice = function(unit, tileX, tileY, entryDir, isForced)
		if not entryDir or (entryDir.dx == 0 and entryDir.dy == 0) then
			return {} -- no direction to slide
		end
		return {{
			type      = "slide",
			dx        = entryDir.dx,
			dy        = entryDir.dy,
			reason    = "Ice",
		}}
	end,

	-- Deep Water: Apply Drowning status on entry.
	-- DB: triggerEffect = "Drowning", cross_cost = +2 (handled in BFS).
	-- Drowning is a hazard condition — ticks every 500 CT while on Deep Water.
	["Deep Water"] = function(unit, tileX, tileY, entryDir, isForced)
		return {{
			type     = "status",
			statusId = "Drowning",
			reason   = "Deep Water",
		}}
	end,

	-- Quicksand: If a unit is FORCED onto Quicksand (displacement),
	-- apply Sinking. Voluntary movement is blocked by IsImpassableTerrain.
	Quicksand = function(unit, tileX, tileY, entryDir, isForced)
		if isForced then
			return {{
				type     = "status",
				statusId = "Sinking",
				reason   = "Quicksand",
			}}
		end
		return {} -- voluntary entry blocked at BFS level
	end,
}

--------------------------------------------------
-- Tile-effect cross effects (from TILE_EFFECTS in GameConstants).
-- These apply when a tile has an active tile effect (Burning, Frozen, etc.)
-- Not implemented yet — requires TileEffectService to track active effects.
-- Stub entries for architecture completeness.
--------------------------------------------------

local TILE_EFFECT_CROSS = {
	Burning = function(unit, tileX, tileY, entryDir, isForced)
		return {{ type = "status", statusId = "Burn", reason = "Burning tile" }}
	end,

	Frozen = function(unit, tileX, tileY, entryDir, isForced)
		if not entryDir or (entryDir.dx == 0 and entryDir.dy == 0) then
			return {}
		end
		return {{ type = "slide", dx = entryDir.dx, dy = entryDir.dy, reason = "Frozen tile" }}
	end,

	["Poison Cloud"] = function(unit, tileX, tileY, entryDir, isForced)
		return {{ type = "status", statusId = "Poison", reason = "Poison Cloud" }}
	end,
}

--------------------------------------------------
-- PUBLIC: OnTileEntered
--
-- Called after a unit arrives at a new tile (from movement or displacement).
-- Returns an array of effect descriptors for the caller to apply.
--
-- Effect descriptor shapes:
--   { type = "status", statusId = "Drowning", reason = "Deep Water" }
--   { type = "slide",  dx = 1, dy = 0, reason = "Ice" }
--   { type = "damage", amount = N, damageType = "Fire", reason = "Burning tile" }
--
-- Parameters:
--   unit           — the unit entering the tile
--   tileX, tileY   — the tile being entered
--   entryDirection — { dx, dy } direction of travel (for slides); nil if teleport
--   isForced       — true if displacement, false if voluntary movement
--   allUnits       — all battle units (for occupancy during slide resolution)
--
-- IMPORTANT: The caller is responsible for applying the effects.
-- This function only determines WHAT should happen, not HOW.
--------------------------------------------------

function TileCrossEffectService.OnTileEntered(unit, tileX, tileY, entryDirection, isForced, allUnits)
	local effects = {}

	-- 1. Check terrain cross effect
	local terrainId = GameConstants.GetTerrainId(tileX, tileY)
	local crossFn = CROSS_EFFECTS[terrainId]
	if crossFn then
		local terrainEffects = crossFn(unit, tileX, tileY, entryDirection, isForced)
		for _, e in ipairs(terrainEffects) do
			table.insert(effects, e)
		end
	end

	-- 2. Check active tile effects (stub — needs TileEffectService)
	-- When TileEffectService exists, query active effects on this tile
	-- and apply their cross effects via TILE_EFFECT_CROSS.
	-- For now, this is a no-op.

	if #effects > 0 then
		local names = {}
		for _, e in ipairs(effects) do
			table.insert(names, e.type .. ":" .. (e.statusId or e.reason or "?"))
		end
		print(string.format(
			"[TileCrossEffect] %s entered (%d,%d) %s | Effects: %s",
			unit.name, tileX, tileY, terrainId,
			table.concat(names, ", ")
		))
	end

	return effects
end

--------------------------------------------------
-- PUBLIC: ResolveSlide
--
-- Resolves a sliding knockback (from Ice or Frozen tile effect).
-- The unit slides in the given direction until stopped by:
--   - Non-slippery tile (not Ice/Frozen)
--   - Blocker or map edge
--   - Occupied tile (collision)
--   - Elevation change (up or down)
--
-- Returns: { tilesSlid = N, finalTileX = X, finalTileY = Y, stoppedBy = reason }
--
-- Does NOT write to unit state — returns result for caller to apply.
-- Does NOT chain into further cross effects (caller handles recursion
-- via the event queue with finite cap).
--------------------------------------------------

function TileCrossEffectService.ResolveSlide(unit, startX, startY, dx, dy, allUnits, mapWidth, mapHeight)
	local currentX = startX
	local currentY = startY
	local currentElev = GameConstants.GetElevation(currentX, currentY)
	local tilesSlid = 0
	local stoppedBy = nil

	-- Slide up to a reasonable cap (prevent infinite loops)
	local MAX_SLIDE = 20

	for _ = 1, MAX_SLIDE do
		local nextX = currentX + dx
		local nextY = currentY + dy

		-- Bounds check
		if nextX < 1 or nextX > (mapWidth or 8) or nextY < 1 or nextY > (mapHeight or 8) then
			stoppedBy = "edge"
			break
		end

		-- Blocker check
		if GameConstants.IsBlocked(nextX, nextY) then
			stoppedBy = "blocker"
			break
		end

		-- Elevation check (any change stops the slide)
		local nextElev = GameConstants.GetElevation(nextX, nextY)
		if nextElev ~= currentElev then
			stoppedBy = "elevation"
			break
		end

		-- Occupancy check
		if allUnits then
			for _, u in ipairs(allUnits) do
				if u.isAlive and u ~= unit and u.tileX == nextX and u.tileY == nextY then
					stoppedBy = "unit"
					break
				end
			end
			if stoppedBy then break end
		end

		-- Check if next tile is still slippery (continues slide)
		local nextTerrain = GameConstants.GetTerrainData(nextX, nextY)
		local isSlippery = false
		if nextTerrain and nextTerrain.tags then
			for _, tag in ipairs(nextTerrain.tags) do
				if tag == "Slippery" then
					isSlippery = true
					break
				end
			end
		end

		-- Move to the next tile
		currentX = nextX
		currentY = nextY
		tilesSlid = tilesSlid + 1

		-- If the tile we landed on is NOT slippery, stop sliding
		if not isSlippery then
			stoppedBy = "terrain"
			break
		end
	end

	if tilesSlid > 0 then
		print(string.format(
			"[TileCrossEffect] %s SLID %d tiles to (%d,%d) | StoppedBy: %s",
			unit.name, tilesSlid, currentX, currentY, stoppedBy or "max"
		))
	end

	return {
		tilesSlid  = tilesSlid,
		finalTileX = currentX,
		finalTileY = currentY,
		stoppedBy  = stoppedBy,
	}
end

return TileCrossEffectService
