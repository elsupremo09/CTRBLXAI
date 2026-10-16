-- CTRBLXAI | Shared Tile Resolver
-- Single source of truth for the question "a pointer/ray hit this instance -- which
-- map tile is it?" Used by BOTH BattleVisualClient (battle phase) and DeploymentUI
-- (deployment phase) so the two can never again drift on what counts as a tap on a
-- tile, a map object, or a blocker. Each phase keeps its OWN click handler and its own
-- coordinate reading (battle converts to battle-coords and scans live unitData;
-- deployment stays in template-coords with its own roster) -- ONLY this hit->tile
-- primitive is shared. Created 2026-10-16 as the BUG-047 follow-up: deployment had been
-- re-implementing this resolution inline and kept missing cases battle already handled
-- (unit tokens, then object models, then blockers). Converging onto one function stops
-- that class of bug.
--
-- Resolution handled (superset of both former inline resolvers):
--   * a template tile part itself   -- IsTemplateTile, carries X / Y          (also pads)
--   * a map-object model or its mesh -- MapObjModel_<name>_<key>, ObjTileX/ObjTileY
--   * a blocker part                 -- Blocker_<x>_<y>, tile encoded in the name
-- Returns the tile BasePart (named Tile_XX_YY). Callers read X / Y off it (deployment)
-- or convert via templateToBattle (battle) -- exactly as the battle client already did.
-- Tile naming + attribute keys verified against MapRenderer (Tile_%02d_%02d, X/Y,
-- IsTemplateTile, ObjTileX/ObjTileY) and TileHighlightManager (pad X/Y).

local TileResolver = {}

local MAX_WALK = 8  -- ancestor hops; bounded so a stray hierarchy can never spin forever

local function findTile(mapFolder: Instance, x: number, y: number): BasePart?
	local tp = mapFolder:FindFirstChild(string.format("Tile_%02d_%02d", x, y))
	if tp and tp:IsA("BasePart") then
		return tp
	end
	return nil
end

-- Resolve the map tile BasePart from an instance a pointer/ray landed on.
-- Returns nil when the hit does not belong to any tile/object/blocker (e.g. empty space,
-- decorative scenery props that carry no tile data). Pads are normally resolved by the
-- caller's pad-first pass before this runs, but a pad reaching here still resolves
-- correctly (it carries IsTemplateTile + X/Y like a tile).
function TileResolver.ResolveTilePart(hit: Instance?, mapFolder: Instance?): BasePart?
	if not (hit and mapFolder) then
		return nil
	end
	local node: Instance? = hit
	local hops = 0
	while node and node ~= workspace and hops <= MAX_WALK do
		-- 1) The node is a template tile (or a click pad) itself.
		if node:IsA("BasePart") and node:GetAttribute("IsTemplateTile") then
			local x, y = node:GetAttribute("X"), node:GetAttribute("Y")
			if x and y then
				return node
			end
		end
		-- 2) Map-object model: its tile is stored as ObjTileX / ObjTileY on the model.
		local ox, oy = node:GetAttribute("ObjTileX"), node:GetAttribute("ObjTileY")
		if ox and oy then
			local tp = findTile(mapFolder, ox, oy)
			if tp then
				return tp
			end
		end
		-- 3) Blocker part: tile encoded in the name Blocker_<x>_<y>.
		local bx, by = string.match(node.Name, "^Blocker_(%d+)_(%d+)$")
		if bx and by then
			local tp = findTile(mapFolder, tonumber(bx), tonumber(by))
			if tp then
				return tp
			end
		end
		node = node.Parent
		hops += 1
	end
	return nil
end

return table.freeze(TileResolver)
