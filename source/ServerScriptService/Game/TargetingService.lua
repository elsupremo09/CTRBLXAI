
-- CTRBLXAI | Slice 3 (AOE Patterns + Ally Targeting)
--
-- Slice 3 additions:
--   - GetSkillCandidates: returns valid targets based on skill's targetRules
--   - GetCleaveTargets: given a primary target + caster, returns all units hit by Cleave
--   - Ally targeting: skills with "Ally Unit, Self" target rules can target allies or self

local GameConstants = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Shared")
		:WaitForChild("GameConstants")
)

local RacePassiveService = require(script.Parent.RacePassiveService)
local TraitEffectService = require(script.Parent.TraitEffectService) -- Perks & Flaws Phase 2
local ArmorPassiveService = require(script.Parent.ArmorPassiveService)
local StatusService = require(script.Parent.StatusService)


local RaceData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("RaceData")
)

-- Effective Elevation: tile elevation + 5 if unit has Flight status.
-- DB: "Flight treats unit as Tile Elevation + 5"
local function getEffectiveElevation(unit)
	local tileElev = GameConstants.GetElevation(unit.tileX, unit.tileY)
	if StatusService.HasStatus(unit, "Flight") then
		return tileElev + 5
	end
	return tileElev
end

-- Melee elevation restriction: melee attacks (range 1-2) limited to ±2 elevation.
-- Giant race tag overrides to ±5.
-- DB: "Melee attacks can only target units within +/-2 elevation levels of the attacker.
--      Giant race tag overrides this to +/-5."
local function isMeleeElevationLegal(actor, target, attackRange)
	if not attackRange or attackRange > 2 then return true end -- ranged, no limit
	local atkElev = getEffectiveElevation(actor)
	local defElev = GameConstants.GetElevation(target.tileX, target.tileY)
	local elevDiff = math.abs(atkElev - defElev)
	-- Giant: ±5
	local maxDiff = 2
	local raceEntry = actor.raceId and RaceData.GetRace(actor.raceId) or nil
	if raceEntry and raceEntry.tags then
		for _, tag in ipairs(raceEntry.tags) do
			if tag == "Giant" then maxDiff = 5; break end
		end
	end
	return elevDiff <= maxDiff
end

local TargetingService = {}

-- Optional: TileEffectService injected at runtime (DI, mirrors CommandService/
-- BattleCoordinator) so pathfinding can honor active tile-effect move-cost bonuses
-- (e.g. Tar Pit). Wired in Main.server.lua during init.
local _tileEffectService = nil
function TargetingService.SetTileEffectService(tes)
	_tileEffectService = tes
end

--------------------------------------------------
-- CONSTANTS
--------------------------------------------------

local BASE_MOVEMENT_RANGE = 3

local DIRECTIONS = {
	{ dx =  1, dy =  0, cost = 1.0 },
	{ dx = -1, dy =  0, cost = 1.0 },
	{ dx =  0, dy =  1, cost = 1.0 },
	{ dx =  0, dy = -1, cost = 1.0 },
	{ dx =  1, dy =  1, cost = 1.5 },
	{ dx = -1, dy =  1, cost = 1.5 },
	{ dx =  1, dy = -1, cost = 1.5 },
	{ dx = -1, dy = -1, cost = 1.5 },
}

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function getMovementRange(unit)
	local base = 0
	if unit.derivedStats and unit.derivedStats.movementRange then
		base = unit.derivedStats.movementRange
	else
		local agi = unit.effectiveStats and unit.effectiveStats.AGI or 10
		base = BASE_MOVEMENT_RANGE + math.floor(agi / 60)
	end
	local raceOffset = RacePassiveService.GetMovementRangeModifier(unit)
	local armorOffset = ArmorPassiveService.GetMovementRangeBonus(unit)
	-- Perks & Flaws Phase 2 (TRAIT-MOVE): Long Strider / Short Strider (0 for no trait).
	local traitOffset = TraitEffectService.GetMovementRangeModifier(unit)
	-- Status move buffs (2026-10-07): Coordinated Advance +2, Rush +3, Rally +1.
	-- StatusService.GetMovementRangeModifier existed but was never called here.
	local statusOffset = StatusService.GetMovementRangeModifier(unit)
	return math.max(1, base + raceOffset + armorOffset + traitOffset + statusOffset)
end

local function getJump(unit)
	-- BUGFIX 2026-10-03: derivedStats.jump is the BASE stat only
	-- (GameConstants: 1 + floor(DEX/60)); the old early-return skipped the
	-- racial (Elf +1) and armor (Climbing Boots +2) bonuses. Mirrors getMovementRange.
	local base
	if unit.derivedStats and unit.derivedStats.jump then
		base = unit.derivedStats.jump
	else
		local dex = unit.effectiveStats and unit.effectiveStats.DEX or 10
		base = 1 + math.floor(dex / 60)
	end
	local raceJump = RacePassiveService.GetJumpModifier(unit)
	local armorJump = ArmorPassiveService.GetJumpBonus(unit)
	-- Slice 5 buff: Rally (+1 Jump) via status jumpOffset.
	local statusJump = StatusService.GetJumpModifier(unit)
	-- Perks & Flaws Phase 2 (TRAIT-JUMP): High Jumper / Stubby Legs (0 for no trait).
	local traitJump = TraitEffectService.GetJumpModifier(unit)
	return base + raceJump + armorJump + statusJump + traitJump
end

local function getDownwardJump(unit)
	-- HALFLING — Nimble Steps (races row 'Halfling', 2026-10-02): Jump -1 when moving
	-- to a lower elevation. Only the voluntary-move BFS uses this (forced
	-- displacement never reads it), so it is voluntary downward movement only.
	return math.max(0, getJump(unit) + 2 + RacePassiveService.GetDownwardJumpModifier(unit))
end

local function buildOccupancyMap(units)
	local map = {}
	for _, unit in ipairs(units) do
		if unit.isAlive then
			local key = unit.tileX .. "," .. unit.tileY
			map[key] = unit
		end
	end
	return map
end

local function tileKey(x, y)
	return x .. "," .. y
end

local function isInsideMap(x, y, mapWidth, mapHeight)
	return x >= 1 and x <= mapWidth
		and y >= 1 and y <= mapHeight
end

local function chebyshevDistance(ax, ay, bx, by)
	return math.max(math.abs(ax - bx), math.abs(ay - by))
end

-- RABBIT FOLK — Hop Step gap tile (2026-10-02): a deliberate chasm / gap floor
-- (Slice 5 CHASM_FLOOR_MAP) or impassable pit terrain (Quicksand). Blockers
-- (walls / objects) are NOT gaps -- a hop never clears a wall.
local function isHopGapTile(x, y)
	if GameConstants.IsBlocked(x, y) then return false end
	if GameConstants.IsChasmFloor and GameConstants.IsChasmFloor(x, y) then return true end
	return GameConstants.IsImpassableTerrain(x, y)
end

--------------------------------------------------
-- MOVE CANDIDATES (unchanged from Slice 2)
--------------------------------------------------

function TargetingService.GetMoveCandidates(actor, allUnits, mapWidth, mapHeight)
	local range      = getMovementRange(actor)
	local jump       = getJump(actor)
	local downJump   = getDownwardJump(actor)
	local occupancy  = buildOccupancyMap(allUnits)
	local canHop     = RacePassiveService.CanHopGap(actor)  -- Rabbit Folk Hop Step
	-- Flight (DB status id 83): ignores climb/downward jump limits, terrain movement
	-- costs and tile bonuses/penalties, and may move OVER occupied tiles (but still
	-- cannot END on an occupied tile). Permanent for Flying-tag races (e.g. Avian).
	local hasFlight  = StatusService.HasStatus(actor, "Flight")
	-- Perks & Flaws (Phase 2b): Pathfinder ignores terrain move-cost (treat as 1.0);
	-- Bogged Down multiplies terrain cost by +50%. Computed once per pathfind.
	local traitTerrainIgnore, traitTerrainMult = TraitEffectService.GetTerrainCostModifier(actor)

	local visited    = {}
	local parent     = {}
	local candidates = {}

	local queue      = { { x = actor.tileX, y = actor.tileY, cost = 0 } }
	local startKey   = tileKey(actor.tileX, actor.tileY)
	visited[startKey] = 0

	local head = 1
	while head <= #queue do
		local current = queue[head]
		head = head + 1

		local currentElev = GameConstants.GetElevation(current.x, current.y)

		for _, dir in ipairs(DIRECTIONS) do
			local nx = current.x + dir.dx
			local ny = current.y + dir.dy

			if isInsideMap(nx, ny, mapWidth, mapHeight) then
				local key = tileKey(nx, ny)

				if GameConstants.IsBlocked(nx, ny) then
				-- skip
			elseif GameConstants.IsImpassableTerrain(nx, ny) then
				-- skip (Quicksand etc.)
				else
					local terrainCost = GameConstants.GetTerrainCost(nx, ny)
					-- Active tile-effect move-cost bonus (e.g. Tar Pit). crossCostBonus in the
					-- Tar Pit def stores the FULL effective cost (1.5, RESOLVED 2026-09-29), not
					-- an additive delta, so reconcile via max(base, bonus) → effective cost 1.5.
					if _tileEffectService and _tileEffectService.GetTileEffect then
						local teff = _tileEffectService.GetTileEffect(nx, ny)
						if teff then
							local edef = GameConstants.TILE_EFFECTS[teff.id]
							if edef and edef.crossCostBonus then
								terrainCost = math.max(terrainCost, edef.crossCostBonus)
							end
						end
					end
					-- Flight ignores terrain movement costs and tile bonuses/penalties (DB id 83).
					-- Perks & Flaws (Phase 2b): Pathfinder ignores terrain cost; Bogged Down +50%.
					if hasFlight then
						terrainCost = 1.0
					elseif traitTerrainIgnore then
						terrainCost = 1.0
					else
						terrainCost = terrainCost * traitTerrainMult
					end
					local stepCost = dir.cost * terrainCost
					local newCost  = current.cost + stepCost
					-- Terrain move costs may be fractional (e.g. Swamp/Deep Water 1.5 after the
					-- Sep 28 2026 halving). A tile is reachable when its EXACT accumulated path
					-- cost is within range — no per-tile or per-total rounding (user clarified
					-- Sep 28 2026: fractional costs must not inflate a tile's cost). e.g. range 3
					-- reaches two 1.5 tiles (3.0) OR one 1.5 + one 1.0 (2.5), etc.
					if newCost <= range
						and (visited[key] == nil or visited[key] > newCost)
					then
						local nextElev = GameConstants.GetElevation(nx, ny)
						local elevDiff = nextElev - currentElev

						local elevLegal = true
						if not hasFlight then
							-- Flight ignores climb/downward jump limits (DB id 83).
							if elevDiff > 0 then
								elevLegal = elevDiff <= jump
							elseif elevDiff < 0 then
								elevLegal = math.abs(elevDiff) <= downJump
							end
						end

						if elevLegal then
							local occupant = occupancy[key]
							-- Flight may move OVER any occupied tile (ally or enemy); normal units
							-- may only pass through same-side units. Ending on an occupied tile is
							-- still forbidden for everyone (candidate insert requires occupant==nil).
							local passable = (occupant == nil)
								or hasFlight
								or (occupant ~= actor and occupant.side == actor.side)

							if passable then
								visited[key] = newCost
								parent[key] = tileKey(current.x, current.y)

								if occupant == nil then
									table.insert(candidates, {
										tileX = nx, tileY = ny, pathCost = newCost
									})
								end

								table.insert(queue, { x = nx, y = ny, cost = newCost })
							end
						end
					end
				end
			end

			-- RABBIT FOLK — Hop Step (races row 'Rabbit Folk', 2026-10-02): hop a SINGLE
			-- gap/pit tile in a straight (cardinal) line, ignoring that tile's elevation,
			-- landing on the tile immediately past it. Guards that keep the Slice 5
			-- chasm / chokepoint system intact:
			--   * take-off tile must NOT itself be a gap tile (no chaining inside a chasm)
			--   * landing tile must NOT be a gap tile (gap wider than 1 tile -> no hop)
			--   * |landing elev - take-off elev| <= Jump (no free cliff-scaling)
			--   * landing tile not blocked / impassable; normal range + occupancy rules
			if canHop and (dir.dx == 0 or dir.dy == 0) and not isHopGapTile(current.x, current.y) then
				local gx, gy = current.x + dir.dx, current.y + dir.dy
				local lx, ly = current.x + 2 * dir.dx, current.y + 2 * dir.dy
				if isInsideMap(gx, gy, mapWidth, mapHeight)
					and isInsideMap(lx, ly, mapWidth, mapHeight)
					and isHopGapTile(gx, gy)
					and not isHopGapTile(lx, ly)
					and not GameConstants.IsBlocked(lx, ly)
					and not GameConstants.IsImpassableTerrain(lx, ly)
				then
					local landElev = GameConstants.GetElevation(lx, ly)
					local gapOcc = occupancy[tileKey(gx, gy)]
					local gapClear = (gapOcc == nil) or (gapOcc ~= actor and gapOcc.side == actor.side)
					if gapClear and math.abs(landElev - currentElev) <= jump then
						local hopCost = current.cost + 1.0 + GameConstants.GetTerrainCost(lx, ly)
						local lkey = tileKey(lx, ly)
						if hopCost <= range and (visited[lkey] == nil or visited[lkey] > hopCost) then
							local landOcc = occupancy[lkey]
							if (landOcc == nil) or (landOcc ~= actor and landOcc.side == actor.side) then
								visited[lkey] = hopCost
								parent[lkey] = tileKey(current.x, current.y)
								if landOcc == nil then
									table.insert(candidates, { tileX = lx, tileY = ly, pathCost = hopCost })
								end
								table.insert(queue, { x = lx, y = ly, cost = hopCost })
							end
						end
					end
				end
			end
		end
	end

	-- Reconstruct path for each candidate by tracing parent chain
	for _, cand in ipairs(candidates) do
		local path = {}
		local ck = tileKey(cand.tileX, cand.tileY)
		local pk = parent[ck]
		while pk and pk ~= startKey do
			local px, py = pk:match("^(%d+),(%d+)$")
			px, py = tonumber(px), tonumber(py)
			local terrain = GameConstants.GetTerrainId(px, py)
			table.insert(path, 1, { tileX = px, tileY = py, terrain = terrain or "Clear" })
			pk = parent[pk]
		end
		-- Add destination terrain
		cand.terrain = GameConstants.GetTerrainId(cand.tileX, cand.tileY) or "Clear"
		cand.path = path
	end

	return candidates
end

--------------------------------------------------
-- LINE OF SIGHT (Bresenham's line through grid)
--
-- Returns true if there is clear LoS from (x1,y1) to (x2,y2).
-- LoS is blocked if ANY tile along the line is a blocker.
-- The start and end tiles themselves do NOT block.
-- Range 1 (adjacent) always has LoS (melee can't be blocked).
-- projectileType: nil/"Direct"/"Channeled" = units block LoS.
--                 "Arc" = units do NOT block (arc clears over them),
--                         but terrain BlocksLoS still applies.
--------------------------------------------------

function TargetingService.HasLineOfSight(x1, y1, x2, y2, allUnits, attackerElevation, projectileType, attackerSide)
	-- Adjacent tiles always have LoS
	if chebyshevDistance(x1, y1, x2, y2) <= 1 then
		return true
	end

	-- Giant race tag: ranged attacks targeting a Giant ignore LoS and blockers.
	-- DB: "Ranged attacks targeting the Giant ignore LoS and blockers."
	if allUnits then
		for _, u in ipairs(allUnits) do
			if u.tileX == x2 and u.tileY == y2 and u.isAlive and u.raceId then
				local raceEntry = RaceData.GetRace(u.raceId)
				if raceEntry and raceEntry.tags then
					for _, tag in ipairs(raceEntry.tags) do
						if tag == "Giant" then return true end
					end
				end
			end
		end
	end

	-- Build a lookup of tiles occupied by standing units (block LoS).
	-- Arc projectiles use arc clearance instead of direct LoS:
	--   Arc Peak Elevation = Attacker Elevation + Arc Height (default 3)
	--   Clear if Arc Peak >= Blocker Elevation + 2
	local isArc = (projectileType == "Arc")
	-- Arc target-height gate (DB rule 46): an arc projectile cannot reach a target
	-- whose EFFECTIVE elevation is ABOVE the arc's peak. Arc Peak = attacker effective
	-- elevation + Arc Height (default 3; no per-projectile arcHeight exists in data).
	-- Purely an ADDITIONAL target-height gate — it does not alter arc's "ignores unit
	-- blockers / flies over terrain" behavior below. Applied once, for the destination.
	-- (Adjacency and Giant-bypass early-returns above are intentionally left intact.)
	if isArc then
		local ARC_HEIGHT = 3
		local atkElev = attackerElevation or GameConstants.GetElevation(x1, y1)
		local arcPeak = atkElev + ARC_HEIGHT
		local targetElev = GameConstants.GetElevation(x2, y2)
		if allUnits then
			for _, u in ipairs(allUnits) do
				if u.isAlive and u.tileX == x2 and u.tileY == y2 then
					targetElev = getEffectiveElevation(u)  -- flight-aware effective elevation
					break
				end
			end
		end
		if targetElev > arcPeak then
			return false
		end
	end
	-- Unit-blocking LoS policy (user override Sep 26 2026, supersedes locked DB rule):
	--   Direct/Channeled: only OPPOSITE-SIDE (enemy) units block. Allied units never block.
	--   Arc: NO unit blocks (ally or enemy) — arc flies over all units, keeping it
	--        meaningfully distinct from Direct. (Designer must update Projectile LoS rules
	--        38 'Unit blockers' and 45 'Arc blocker clearance' in the DB.)
	local unitOccupied = {}
	if allUnits then
		for _, u in ipairs(allUnits) do
			if u.isAlive then
				local key = u.tileX .. "," .. u.tileY
				unitOccupied[key] = { elev = GameConstants.GetElevation(u.tileX, u.tileY), side = u.side }
			end
		end
	end

	-- Bresenham's line algorithm
	local dx = math.abs(x2 - x1)
	local dy = math.abs(y2 - y1)
	local sx = x1 < x2 and 1 or -1
	local sy = y1 < y2 and 1 or -1
	local err = dx - dy
	local cx, cy = x1, y1

	while true do
		local e2 = 2 * err
		if e2 > -dy then err = err - dy; cx = cx + sx end
		if e2 < dx then err = err + dx; cy = cy + sy end

		-- If we've reached the destination, LoS is clear
		if cx == x2 and cy == y2 then return true end

		-- Check if this intermediate tile is a blocker
		-- Arc projectiles fly over terrain blockers; only Direct/Channeled are stopped
		if not isArc and GameConstants.IsBlocked(cx, cy) then
			return false
		end

		-- Check if a standing unit occupies this intermediate tile
		-- Arc projectiles are NEVER blocked by units (ally or enemy) — skip entirely.
		if allUnits and not isArc then
			local key = cx .. "," .. cy
			local blocker = unitOccupied[key]
			-- Direct/Channeled: only OPPOSITE-SIDE (enemy) units block LoS.
			-- Allied blockers (same side as attacker) never block. If attackerSide is
			-- unknown (nil), fall back to blocking (safe default preserves old behavior).
			if blocker and (attackerSide == nil or blocker.side ~= attackerSide) then
				local atkElev = attackerElevation or GameConstants.GetElevation(x1, y1)
				-- Bypass if attacker Effective Elevation >= 3 above blocker.
				if atkElev < blocker.elev + 3 then
					return false
				end
			end
		end
	end
end

--------------------------------------------------
-- ATTACK CANDIDATES (Chebyshev range, enemy only)
--------------------------------------------------

function TargetingService.GetAttackCandidates(actor, allUnits, range)
	range = range or 1
	range = range + RacePassiveService.GetRangeModifier(actor)
	-- Support minimum range (ranged weapons cannot hit adjacent targets)
	local minRange = actor.weaponMinRange or 1

	local candidates = {}

	for _, unit in ipairs(allUnits) do
		if unit.isAlive and unit.side ~= actor.side
			and not StatusService.HasStatus(unit, "Hide") then
			local dist = chebyshevDistance(actor.tileX, actor.tileY, unit.tileX, unit.tileY)
			if dist <= range
				and dist >= minRange
				and TargetingService.HasLineOfSight(actor.tileX, actor.tileY, unit.tileX, unit.tileY,
					allUnits, getEffectiveElevation(actor), actor.weaponProjectileType, actor.side)
				and isMeleeElevationLegal(actor, unit, range)
			then
				table.insert(candidates, unit)
			end
		end
	end

	return candidates
end

--------------------------------------------------
-- SKILL CANDIDATES (Slice 3)
-- Returns valid target units based on the skill's targetRules.
--   "Enemy Unit"       → enemies in range
--   "Ally Unit, Self"  → allies + self in range
--------------------------------------------------

function TargetingService.GetSkillCandidates(actor, allUnits, skillDef)
	-- 2026-10-07: range (max + weapon-only min + per-skill Bonus Skill Range share)
	-- comes from the ONE shared formula GameConstants.CalcSkillRange (DAT-001), also
	-- used by CommandService validation so prompt and validation never drift.
	-- HALFLING — Nimble Steps (2026-10-02): movement skills +1 range (race modifier).
	local range, minRange, baseRange, bonusRange = GameConstants.CalcSkillRange(
		actor, skillDef, RacePassiveService.GetSkillRangeModifier(actor, skillDef))
	print(string.format("[SkillCand] %s using %s | skillRange=%s baseRange=%d bonusRange=%d range=%d | weaponMaxRange=%s INT=%s derivedBSR=%s",
		actor.name, skillDef.name or skillDef.id, tostring(skillDef.range),
		baseRange, bonusRange, range, tostring(actor.weaponMaxRange),
		tostring(actor.effectiveStats and actor.effectiveStats.INT),
		tostring(actor.derivedStats and actor.derivedStats.bonusSkillRange)))
	local targetRules = skillDef.targetRules or "Enemy Unit"
	local candidates = {}

	-- ============================================================
	-- SELF-TARGETING: Self, Self (Aura), Ally Tile (centered on caster)
	-- No selection needed — caster is the only valid target
	-- "Self, Allies" with range=0 is also caster-origin AOE (Consecrate, Bulwark Field)
	-- ============================================================
	if targetRules == "Self" or targetRules == "Self (Aura)"
		or targetRules == "Ally Tile (centered on caster)"
		or (targetRules == "Self, Allies" and (skillDef.range or 0) == 0) then
		table.insert(candidates, actor) -- self is the "target"
		print(string.format("[SkillCand] %s → self-target (%s)", actor.name, targetRules))
		return candidates, range
	end

	-- ============================================================
	-- "Self, Allies" with range > 0 is GROUND-TARGETED AOE
	-- (e.g. Mending Rain: anchor range 3, Circle radius 2, allies only)
	-- ============================================================
	if targetRules == "Self, Allies" and (skillDef.range or 0) > 0 then
		table.insert(candidates, {
			id = "_ground_target",
			name = "Ground",
			tileX = actor.tileX,
			tileY = actor.tileY,
			isGroundTarget = true,
		})
		print(string.format("[SkillCand] %s → ground target (Self, Allies range=%d)", actor.name, range))
		return candidates, range
	end

	-- ============================================================
	-- TILE TARGETING: Ground / Enemy Tile / Empty Tile
	-- Return a special ground-target marker + range so the caller
	-- knows to accept tile clicks instead of unit clicks.
	-- ============================================================
	if targetRules == "Ground, including occupied Ground"
		or targetRules == "Enemy Tile"
		or targetRules == "Empty Tile" then
		-- Ground-targeting skill is always available if caster has MP
		-- Return a special marker entry so buildTurnPrompt sends groundTarget=true
		table.insert(candidates, {
			id = "_ground_target",
			name = "Ground",
			tileX = actor.tileX,
			tileY = actor.tileY,
			isGroundTarget = true,
		})
		print(string.format("[SkillCand] %s → ground target (%s) range=%d", actor.name, targetRules, range))
		return candidates, range
	end

	-- ============================================================
	-- UNIT TARGETING: iterate all units and filter by targetRules
	-- ============================================================
	local isAllyRule = targetRules == "Ally Unit, Self"
		or targetRules == "Self, Ally Unit"
	local isAllyOnlyRule = targetRules == "Ally Unit"
	local isIndiscriminate = targetRules == "Ally Unit, Enemy Unit, Self"

	for _, unit in ipairs(allUnits) do
		if not unit.isAlive then
			-- skip dead units
		elseif chebyshevDistance(actor.tileX, actor.tileY, unit.tileX, unit.tileY) > range then
			print(string.format("[SkillCand] %s REJECTED %s: out of range (dist=%d > range=%d)",
				actor.name, unit.name, chebyshevDistance(actor.tileX, actor.tileY, unit.tileX, unit.tileY), range))
		elseif chebyshevDistance(actor.tileX, actor.tileY, unit.tileX, unit.tileY) < minRange then
			print(string.format("[SkillCand] %s REJECTED %s: inside weapon min range (dist=%d < minRange=%d)",
				actor.name, unit.name, chebyshevDistance(actor.tileX, actor.tileY, unit.tileX, unit.tileY), minRange))
		else
			-- LoS check: ally/healing skills skip LoS
			local projType = skillDef.projectileType
			if not projType or projType == "Inherit" then
				projType = actor.weaponProjectileType
			end
			local skipLos = isAllyRule or isAllyOnlyRule or isIndiscriminate
			local hasLos = skipLos
				or TargetingService.HasLineOfSight(actor.tileX, actor.tileY, unit.tileX, unit.tileY,
					allUnits, getEffectiveElevation(actor), projType, actor.side)
			if not hasLos then
				print(string.format("[SkillCand] %s REJECTED %s: no LoS (proj=%s)", actor.name, unit.name, tostring(projType)))
			elseif not isMeleeElevationLegal(actor, unit, baseRange) then
				print(string.format("[SkillCand] %s REJECTED %s: elevation (baseRange=%d)", actor.name, unit.name, baseRange))
			else
				-- Allegiance filter
				if targetRules == "Enemy Unit" then
					if unit.side ~= actor.side and not StatusService.HasStatus(unit, "Hide") then
						table.insert(candidates, unit)
					elseif StatusService.HasStatus(unit, "Hide") then
						print(string.format("[SkillCand] %s REJECTED %s: hidden (Hide status)", actor.name, unit.name))
					elseif unit.side == actor.side then
						print(string.format("[SkillCand] %s REJECTED %s: same side", actor.name, unit.name))
					end
				elseif isAllyRule then
					-- Ally Unit, Self / Self, Allies / Self, Ally Unit
					if unit.side == actor.side then
						table.insert(candidates, unit)
					end
				elseif isAllyOnlyRule then
					-- Ally Unit (NOT self)
					if unit.side == actor.side and unit.id ~= actor.id then
						table.insert(candidates, unit)
					elseif unit.id == actor.id then
						print(string.format("[SkillCand] %s REJECTED %s: self excluded (Ally Unit only)", actor.name, unit.name))
					end
				elseif isIndiscriminate then
					-- Any alive unit in range
					table.insert(candidates, unit)
				else
					-- Unknown targetRules fallback: treat as enemy
					if unit.side ~= actor.side then
						table.insert(candidates, unit)
					end
				end
			end
		end
	end

	return candidates, range
end

--------------------------------------------------
-- CLEAVE TARGETS (Slice 3)
--
-- Cleave hits all enemies within range 1 of the caster that are
-- also within 1 tile of the primary target (forming a 3-tile arc).
-- The primary target is always included.
-- Returns a list of units (primary target first).
--------------------------------------------------

function TargetingService.GetCleaveTargets(actor, primaryTarget, allUnits)
	-- Cleave = primary target + up to 2 flanking units perpendicular to attack direction.
	-- Max 3 hits. Secondary tiles are adjacent to BOTH attacker AND target, on the sides.
	-- Elevation filter: secondary must be ±2 elevation from attacker.
	local targets = {}
	table.insert(targets, primaryTarget)

	-- Direction vector from attacker to target
	local dx = primaryTarget.tileX - actor.tileX
	local dy = primaryTarget.tileY - actor.tileY

	-- Perpendicular directions (the two flanking tiles)
	-- For cardinal: (1,0)→perps are (0,1),(0,-1). For diagonal: (1,1)→perps are (1,-1),(-1,1)
	local perp1X, perp1Y, perp2X, perp2Y
	if dx == 0 then     -- N or S attack
		perp1X, perp1Y = -1, dy
		perp2X, perp2Y = 1, dy
	elseif dy == 0 then -- E or W attack
		perp1X, perp1Y = dx, -1
		perp2X, perp2Y = dx, 1
	else                -- diagonal attack
		perp1X, perp1Y = dx, 0
		perp2X, perp2Y = 0, dy
	end

	local atkElev = getEffectiveElevation(actor)
	local flankTiles = {
		{ x = actor.tileX + perp1X, y = actor.tileY + perp1Y },
		{ x = actor.tileX + perp2X, y = actor.tileY + perp2Y },
	}

	for _, tile in ipairs(flankTiles) do
		local tileElev = GameConstants.GetElevation(tile.x, tile.y)
		if math.abs(tileElev - atkElev) <= 2 then
			for _, unit in ipairs(allUnits) do
				if unit.isAlive and unit.side ~= actor.side
					and unit.id ~= primaryTarget.id
					and unit.tileX == tile.x and unit.tileY == tile.y then
					table.insert(targets, unit)
				end
			end
		end
	end

	return targets
end

--------------------------------------------------
-- GET VALID SKILL TILES (Slice 3 — for client highlighting)
--
-- Returns all tile positions within skill range (for highlighting).
--------------------------------------------------

function TargetingService.GetSkillRangeTiles(actor, skillDef, mapWidth, mapHeight)
	-- Shared formula (DAT-001) so highlighting matches validation.
	local range = GameConstants.CalcSkillRange(
		actor, skillDef, RacePassiveService.GetSkillRangeModifier(actor, skillDef))
	local tiles = {}

	for dy = -range, range do
		for dx = -range, range do
			if math.max(math.abs(dx), math.abs(dy)) <= range then
				local tx = actor.tileX + dx
				local ty = actor.tileY + dy
				if isInsideMap(tx, ty, mapWidth, mapHeight) then
					table.insert(tiles, { tileX = tx, tileY = ty })
				end
			end
		end
	end

	return tiles
end

--------------------------------------------------
-- VALIDATE SELECTION (updated for Slice 3)
--------------------------------------------------

function TargetingService.ValidateSelection(
	actor,
	actionType,
	selection,
	allUnits,
	mapWidth,
	mapHeight
)
	if actionType == "Wait" then
		return true, nil
	end

	if actionType == "Move" then
		if type(selection) ~= "table"
			or type(selection.tileX) ~= "number"
			or type(selection.tileY) ~= "number"
		then
			return false, "Move selection must be a table with tileX and tileY."
		end

		local candidates = TargetingService.GetMoveCandidates(
			actor, allUnits, mapWidth, mapHeight
		)

		for _, c in ipairs(candidates) do
			if c.tileX == selection.tileX and c.tileY == selection.tileY then
				return true, nil
			end
		end

		return false, string.format(
			"Tile (%d,%d) is not reachable from (%d,%d) with range %d.",
			selection.tileX, selection.tileY,
			actor.tileX, actor.tileY,
			getMovementRange(actor)
		)
	end

	if actionType == "Attack" then
		if type(selection) ~= "table" or not selection.isAlive then
			return false, "Attack selection must be a living unit."
		end
		if selection.side == actor.side then
			return false, "Cannot attack an ally."
		end

		-- Use actor's equipped weapon range for validation
		local attackRange = (actor.weaponMaxRange or 1) + RacePassiveService.GetRangeModifier(actor)
		local candidates = TargetingService.GetAttackCandidates(actor, allUnits, attackRange)
		for _, c in ipairs(candidates) do
			if c == selection then
				return true, nil
			end
		end

		return false, string.format(
			"Target %s is out of basic attack range.", selection.name
		)
	end

	if actionType == "Skill" then
		if type(selection) ~= "table" then
			return false, "Skill selection must be a table with a target field."
		end

		local target     = selection.target
		local skillRange = selection.skillRange or 1
		-- BUGFIX 2026-10-06: weapon-range skills carry the weapon's min range (0 = none).
		local skillMinRange = selection.skillMinRange or 0
		local targetRules = selection.targetRules or "Enemy Unit"

		-- Ground targeting: validate tile coords + range only
		if target and target.isGroundTarget then
			local dist = chebyshevDistance(actor.tileX, actor.tileY, target.tileX, target.tileY)
			if dist > skillRange then
				return false, string.format(
					"Ground target (%d,%d) out of range (%d). Distance: %d.",
					target.tileX, target.tileY, skillRange, dist
				)
			end
			if dist < skillMinRange then
				return false, string.format(
					"Ground target (%d,%d) is inside weapon min range (%d). Distance: %d.",
					target.tileX, target.tileY, skillMinRange, dist
				)
			end
			return true, nil
		end

		-- Self-targeting: always valid (target is the caster)
		if targetRules == "Self" or targetRules == "Self (Aura)"
			or targetRules == "Ally Tile (centered on caster)"
			or targetRules == "Self, Allies" then
			return true, nil
		end

		if not target or not target.isAlive then
			return false, "Target is not alive."
		end

		-- Validate target allegiance based on skill target rules
		if targetRules == "Enemy Unit" then
			if target.side == actor.side then
				return false, "Cannot target an ally with this offensive skill."
			end
		elseif targetRules == "Ally Unit, Self" then
			if target.side ~= actor.side then
				return false, "Cannot target an enemy with this support skill."
			end
		elseif targetRules == "Ally Unit" then
			if target.side ~= actor.side or target.id == actor.id then
				return false, "Must target an ally (not self)."
			end
		elseif targetRules == "Ally Unit, Enemy Unit, Self" then
			-- Any unit is valid
		end

		-- Range check (Chebyshev)
		local dist = chebyshevDistance(actor.tileX, actor.tileY, target.tileX, target.tileY)
		if dist > skillRange then
			return false, string.format(
				"Target %s is out of skill range (%d). Distance: %d.",
				target.name, skillRange, dist
			)
		end
		if dist < skillMinRange then
			return false, string.format(
				"Target %s is inside weapon min range (%d). Distance: %d.",
				target.name, skillMinRange, dist
			)
		end

		return true, nil
	end

	return false, "Unknown actionType: " .. tostring(actionType)
end

--------------------------------------------------
-- AOE PATTERN TILE GENERATORS  (Slice 3)
--
-- Each function returns an array of {tileX, tileY} positions
-- that the pattern covers.  CommandService collects units on
-- those tiles, filters by targetRules, and resolves each hit.
--
-- DB rules:
--   - AOE elevation limit: ±2 from center/anchor (default)
--   - Center Spread AOE does not pass through BlocksAOE
--   - Selected Area AOE affects valid tiles directly
--   - Caster-origin patterns use caster's current tile
--
-- Elevation + BlocksAOE filtering is done by the caller,
-- not inside these generators (keeps them pure geometry).
--------------------------------------------------

-- Circle: all tiles within Chebyshev distance <= radius of center
function TargetingService.GetCircleTiles(centerX, centerY, radius, mapWidth, mapHeight)
	local tiles = {}
	for dy = -radius, radius do
		for dx = -radius, radius do
			if math.max(math.abs(dx), math.abs(dy)) <= radius then
				local tx, ty = centerX + dx, centerY + dy
				if isInsideMap(tx, ty, mapWidth, mapHeight) then
					table.insert(tiles, { tileX = tx, tileY = ty })
				end
			end
		end
	end
	return tiles
end

-- Ring: only the outer edge of a circle (distance == radius)
function TargetingService.GetRingTiles(centerX, centerY, radius, mapWidth, mapHeight)
	local tiles = {}
	for dy = -radius, radius do
		for dx = -radius, radius do
			if math.max(math.abs(dx), math.abs(dy)) == radius then
				local tx, ty = centerX + dx, centerY + dy
				if isInsideMap(tx, ty, mapWidth, mapHeight) then
					table.insert(tiles, { tileX = tx, tileY = ty })
				end
			end
		end
	end
	return tiles
end

-- Cross: cardinal lines of length N from center (+ center itself)
function TargetingService.GetCrossTiles(centerX, centerY, radius, mapWidth, mapHeight)
	local tiles = { { tileX = centerX, tileY = centerY } }
	local dirs = { {0,-1}, {0,1}, {-1,0}, {1,0} }
	for _, d in ipairs(dirs) do
		for i = 1, radius do
			local tx, ty = centerX + d[1]*i, centerY + d[2]*i
			if isInsideMap(tx, ty, mapWidth, mapHeight) then
				table.insert(tiles, { tileX = tx, tileY = ty })
			end
		end
	end
	return tiles
end

-- Line: N tiles in a direction from origin (exclusive of origin)
-- direction = {dx, dy} normalized to -1/0/1
function TargetingService.GetLineTiles(originX, originY, dx, dy, length, mapWidth, mapHeight)
	local tiles = {}
	for i = 1, length do
		local tx, ty = originX + dx*i, originY + dy*i
		if isInsideMap(tx, ty, mapWidth, mapHeight) then
			table.insert(tiles, { tileX = tx, tileY = ty })
		end
	end
	return tiles
end

-- Cone: expanding triangle in a direction, depth N
-- At distance d from origin, width = 2d-1 tiles perpendicular to direction
-- direction = {dx, dy} (cardinal or diagonal)
function TargetingService.GetConeTiles(originX, originY, dx, dy, depth, mapWidth, mapHeight)
	local tiles = {}
	-- Determine perpendicular direction
	local perpDx, perpDy
	if dx == 0 then
		perpDx, perpDy = 1, 0
	elseif dy == 0 then
		perpDx, perpDy = 0, 1
	else
		-- Diagonal: perpendicular is the two cardinals
		perpDx, perpDy = -dy, dx
	end

	for d = 1, depth do
		-- Center tile at distance d
		local cx, cy = originX + dx*d, originY + dy*d
		-- Width expands: at d=1 width=1, d=2 width=3, d=3 width=5
		local spread = d - 1
		for s = -spread, spread do
			local tx = cx + perpDx * s
			local ty = cy + perpDy * s
			if isInsideMap(tx, ty, mapWidth, mapHeight) then
				table.insert(tiles, { tileX = tx, tileY = ty })
			end
		end
	end
	return tiles
end

-- Adjacent Area: all 8 tiles around a center (not including center)
function TargetingService.GetAdjacentTiles(centerX, centerY, mapWidth, mapHeight)
	local tiles = {}
	for dy = -1, 1 do
		for dx = -1, 1 do
			if not (dx == 0 and dy == 0) then
				local tx, ty = centerX + dx, centerY + dy
				if isInsideMap(tx, ty, mapWidth, mapHeight) then
					table.insert(tiles, { tileX = tx, tileY = ty })
				end
			end
		end
	end
	return tiles
end

--------------------------------------------------
-- GetAOETargets: unified AOE resolution
--
-- Given an aoePattern string, origin, target/direction,
-- returns all affected {tileX, tileY} positions.
-- CommandService calls this then filters for units.
--------------------------------------------------

function TargetingService.GetAOETargetTiles(aoePattern, actor, targetTileX, targetTileY, mapWidth, mapHeight)
	-- Parse pattern type and parameter
	-- Supports: "Circle2", "Ring1", "Spread", "Spread3x3", "Impact1", etc.
	local patternType, param = aoePattern:match("^(%a+)(%d+)$")
	if not patternType then
		-- Handle formats like "Spread3x3" (NxN suffix) or bare names like "Spread"
		patternType, param = aoePattern:match("^(%a+)(%d+)x%d+$")
	end
	if not patternType then
		patternType = aoePattern:match("^(%a+)$")
	end
	param = tonumber(param) or 1

	if patternType == "Circle" then
		return TargetingService.GetCircleTiles(targetTileX, targetTileY, param, mapWidth, mapHeight)

	elseif patternType == "Ring" then
		return TargetingService.GetRingTiles(targetTileX, targetTileY, param, mapWidth, mapHeight)

	elseif patternType == "Cross" then
		return TargetingService.GetCrossTiles(targetTileX, targetTileY, param, mapWidth, mapHeight)

	elseif patternType == "Line" then
		-- Direction from actor toward target
		local ddx = targetTileX - actor.tileX
		local ddy = targetTileY - actor.tileY
		local dx = ddx ~= 0 and (ddx > 0 and 1 or -1) or 0
		local dy = ddy ~= 0 and (ddy > 0 and 1 or -1) or 0
		return TargetingService.GetLineTiles(actor.tileX, actor.tileY, dx, dy, param, mapWidth, mapHeight)

	elseif patternType == "Cone" then
		local ddx = targetTileX - actor.tileX
		local ddy = targetTileY - actor.tileY
		local dx = ddx ~= 0 and (ddx > 0 and 1 or -1) or 0
		local dy = ddy ~= 0 and (ddy > 0 and 1 or -1) or 0
		return TargetingService.GetConeTiles(actor.tileX, actor.tileY, dx, dy, param, mapWidth, mapHeight)

	elseif patternType == "Adjacent" then
		return TargetingService.GetAdjacentTiles(targetTileX, targetTileY, mapWidth, mapHeight)

	elseif patternType == "Spread" then
		-- 3x3 Center Spread = Circle radius 1
		return TargetingService.GetCircleTiles(targetTileX, targetTileY, 1, mapWidth, mapHeight)

	elseif patternType == "Impact" then
		-- Impact 1 = Cross radius 1 (3×3 cross)
		return TargetingService.GetCrossTiles(targetTileX, targetTileY, 1, mapWidth, mapHeight)

	elseif patternType == "Aura" then
		-- Aura is CASTER-ORIGIN: centered on the caster's own tile, radius = param
		-- (Chebyshev), not the selected target tile. Mirrors Circle but from the
		-- actor. Recipient side-filtering (allies vs enemies) is applied by the
		-- resolution loop in CommandService, not here.
		return TargetingService.GetCircleTiles(actor.tileX, actor.tileY, param, mapWidth, mapHeight)

	elseif patternType == "Cleave" then
		-- Cleave is handled separately via GetCleaveTargets (unit-based, not tile-based)
		return {}

	else
		print(string.format("[TargetingService] Unknown AOE pattern: %s", aoePattern))
		return {}
	end
end

--------------------------------------------------
-- AOE SPREAD BLOCKING
-- Center Spread AOE does not pass through BlocksAOE objects.
-- Uses Bresenham walk from center to tile; if any intermediate
-- tile has a BlocksAOE blocker, the target tile is blocked.
-- DB: "Walls, closed doors, sealed barriers, and solid map
-- objects tagged BlocksAOE block spread."
--------------------------------------------------

function TargetingService.IsAOEBlocked(centerX, centerY, targetX, targetY)
	-- Walk from center toward target, checking intermediate tiles
	local dx = targetX - centerX
	local dy = targetY - centerY
	local steps = math.max(math.abs(dx), math.abs(dy))
	if steps <= 1 then return false end  -- adjacent tiles never blocked

	for i = 1, steps - 1 do
		local t = i / steps
		local ix = centerX + math.floor(dx * t + 0.5)
		local iy = centerY + math.floor(dy * t + 0.5)
		if GameConstants.HasBlockerTag(ix, iy, "BlocksAOE") then
			return true
		end
	end

	-- Also blocked if the target tile itself is a BlocksAOE object
	if GameConstants.HasBlockerTag(targetX, targetY, "BlocksAOE") then
		return true
	end
	return false
end

--------------------------------------------------
-- Chain targeting: jumps from target to nearest
-- valid enemy within jumpRange, up to maxTargets.
-- Returns array of units in chain order.
--
-- DB: Chain skills select first target at commitment.
-- Jump distance default = 2 tiles (Chebyshev).
--------------------------------------------------

function TargetingService.GetChainTargets(firstTarget, allUnits, attackerSide, maxTargets, jumpRange)
	jumpRange = jumpRange or 2
	local chain = { firstTarget }
	local seen = { [firstTarget.id] = true }
	local current = firstTarget

	for _ = 2, maxTargets do
		local bestUnit = nil
		local bestDist = math.huge

		for _, u in ipairs(allUnits) do
			if u.isAlive and u.side ~= attackerSide and not seen[u.id] then
				local dist = chebyshevDistance(current.tileX, current.tileY, u.tileX, u.tileY)
				if dist <= jumpRange and dist < bestDist then
					bestDist = dist
					bestUnit = u
				end
			end
		end

		if not bestUnit then break end
		table.insert(chain, bestUnit)
		seen[bestUnit.id] = true
		current = bestUnit
	end

	return chain
end

--------------------------------------------------
-- GET IMPACT SPLASH TARGETS (Slice 4 — Weapon Pattern AOE)
--
-- DB rule: "Primary Target receives 100% damage; four cardinally
-- adjacent splash tiles receive 50% damage. Friendly fire applies."
--
-- Returns: { {unit=unit, dmgMult=1.0}, {unit=unit, dmgMult=0.5}, ... }
-- Primary target always first. Splash includes ALL alive units on
-- cardinal tiles (enemies AND allies — friendly fire per DB).
-- Elevation filter: splash tile must be ±2 from impact tile.
--------------------------------------------------

function TargetingService.GetImpactSplashTargets(actor, primaryTarget, allUnits)
	local results = {}
	table.insert(results, { unit = primaryTarget, dmgMult = 1.0 })

	local cx, cy = primaryTarget.tileX, primaryTarget.tileY
	local impactElev = getEffectiveElevation(primaryTarget)

	-- Four cardinal neighbors
	local cardinals = {
		{ x = cx, y = cy - 1 },
		{ x = cx, y = cy + 1 },
		{ x = cx - 1, y = cy },
		{ x = cx + 1, y = cy },
	}

	for _, tile in ipairs(cardinals) do
		local tileElev = GameConstants.GetElevation(tile.x, tile.y)
		if math.abs(tileElev - impactElev) <= 2 then
			for _, u in ipairs(allUnits) do
				if u.isAlive and u.id ~= primaryTarget.id and u.id ~= actor.id
					and u.tileX == tile.x and u.tileY == tile.y then
					table.insert(results, { unit = u, dmgMult = 0.5 })
				end
			end
		end
	end

	return results
end

--------------------------------------------------
-- GET LINE2 TARGETS (Slice 4 — Weapon Pattern AOE)
--
-- DB rule: Line 2 hits primary target + the tile directly
-- behind the target in the attack direction. Both at 100%.
-- Elevation filter: ±2 from primary target.
--
-- Returns: { {unit=unit, dmgMult=1.0}, ... }
--------------------------------------------------

function TargetingService.GetLine2Targets(actor, primaryTarget, allUnits)
	local results = {}
	table.insert(results, { unit = primaryTarget, dmgMult = 1.0 })

	-- Direction from attacker to target (normalized to -1/0/+1)
	local rawDx = primaryTarget.tileX - actor.tileX
	local rawDy = primaryTarget.tileY - actor.tileY
	local dx = rawDx == 0 and 0 or (rawDx > 0 and 1 or -1)
	local dy = rawDy == 0 and 0 or (rawDy > 0 and 1 or -1)

	-- Tile behind target = target + direction
	local behindX = primaryTarget.tileX + dx
	local behindY = primaryTarget.tileY + dy

	local primaryElev = getEffectiveElevation(primaryTarget)
	local behindElev = GameConstants.GetElevation(behindX, behindY)

	if math.abs(behindElev - primaryElev) <= 2 then
		for _, u in ipairs(allUnits) do
			if u.isAlive and u.id ~= primaryTarget.id and u.id ~= actor.id
				and u.tileX == behindX and u.tileY == behindY then
				table.insert(results, { unit = u, dmgMult = 1.0 })
			end
		end
	end

	return results
end

--------------------------------------------------
-- GET INTERACT CANDIDATES (Slice 4 — Interact Command framework)
--
-- Interact is the universal Head-slot action (1 AP). It has four NATIVE
-- target kinds (built-in; headgear only ENHANCES them, never enables):
--   "recruitEnemy"  — enemy at <= recruitThreshold of max HP (native 5%)
--   "allyRtHelp"    — living ally (not self): cuts the ally's current RT
--   "reviveAlly"    — KO'd ally: channeled resuscitate (native 200 CT)
--   "mapObject"     — a map object instance (PARKED — Slice 5 populates
--                     state.objects; no object candidates appear until then)
--
-- Each candidate is tagged with { interactKind, id/objectId, name, tileX,
-- tileY } so the client can label what the Interact will do and the server
-- can re-validate on commit. Reach uses the actor's native Interact range
-- (default 1, Chebyshev), extendable later by the HD-002 range hook.
--
-- Headgear ENHANCER hook points are nil-safe and default to the native
-- baseline — see InteractService / CommandService for the magnitude hooks.
-- Here we only need the recruit HP threshold and the interact reach, both
-- read through ArmorPassiveService with a native-baseline fallback.
--
-- Returns: array of candidate tables (possibly empty — button grays out).
--------------------------------------------------

function TargetingService.GetInteractCandidates(actor, allUnits, state)
	local candidates = {}
	if not actor or not actor.isAlive then
		return candidates
	end

	-- Interact reach: native 1 tile. HD-002 Surveyor Visor adds +2 (hook,
	-- nil-safe → 0 until headgear passives are wired).
	local reach = 1
	if ArmorPassiveService.GetInteractRangeBonus then
		reach = reach + (ArmorPassiveService.GetInteractRangeBonus(actor) or 0)
	end
	-- Perks & Flaws (Phase 2b): Long/Short Reach adjust interact range.
	reach = reach + TraitEffectService.GetInteractRangeModifier(actor)
	if reach < 1 then reach = 1 end

	-- Recruit HP threshold: native 0.05 of max HP. HD-005 Recruiter's Circlet
	-- raises it to 0.08 (hook, nil-safe → native until wired).
	local recruitThreshold = 0.05
	if ArmorPassiveService.GetRecruitThreshold then
		recruitThreshold = ArmorPassiveService.GetRecruitThreshold(actor) or 0.05
	end

	local actorElev = getEffectiveElevation(actor)

	-- UNIT-TARGET NATIVES (functional now) --------------------------------
	for _, u in ipairs(allUnits) do
		if u.id ~= actor.id then
			local dist = chebyshevDistance(actor.tileX, actor.tileY, u.tileX, u.tileY)
			if dist <= reach then
				-- Interact reach honors the ±2 melee elevation rule (treat
				-- like a reach-1/2 action; Giant tag widens via the helper).
				local elevOk = isMeleeElevationLegal(actor, u, reach)
				if elevOk then
					if u.isAlive and u.eventInteractable and actor.side == "Player" then
						-- BATTLEFIELD-EVENT NPC (2026-10-04): an authored event
						-- interaction (Fortune Teller, Wandering Scholar, Merchant
						-- Caravan, Wandering Bandits, ...). DB rule 131: these are
						-- event-defined, NOT native Recruit/Aid/Revive, and are not
						-- affected by the neutral filter. Only Player-side actors may
						-- use them; BattlefieldEventService clears eventInteractable
						-- once a one-time interaction is spent.
						table.insert(candidates, {
							interactKind = "eventNpc",
							id = u.id, name = u.name,
							tileX = u.tileX, tileY = u.tileY,
						})
					elseif not u.isAlive then
						-- KO'd unit: only ALLIES can be resuscitated. Neutral units
						-- (incl. recruited) are not allies and get no Interact (DB
						-- rule 131) — so both actor and target must be non-Neutral.
						if u.side == actor.side and actor.side ~= "Neutral" then
							table.insert(candidates, {
								interactKind = "reviveAlly",
								id = u.id, name = u.name,
								tileX = u.tileX, tileY = u.tileY,
							})
						end
					elseif u.side == actor.side and actor.side ~= "Neutral" then
						-- Living ally: RT-help. Neutral/recruited units get no Interact
						-- (DB rule 131), so a Neutral actor cannot Aid another Neutral.
						table.insert(candidates, {
							interactKind = "allyRtHelp",
							id = u.id, name = u.name,
							tileX = u.tileX, tileY = u.tileY,
						})
					elseif u.side ~= "Neutral" and not u.recruited then
						-- Living ENEMY (opposite side, not a Neutral/already-recruited
						-- unit): recruit if at/under the HP threshold AND
						-- tier-eligible. Native rule (CTRBLXAI.db "Native — Recruit
						-- Enemy"): "Cannot recruit bosses, veterans, elites, or any
						-- unit whose race is not playable." Enemy tier is carried on
						-- `enemyType` (set by EnemyGenerator: "Grunt"/"Veteran"/
						-- "Elite"; bosses are hand-crafted, never procedurally
						-- spawned). Only a Grunt is recruitable; Veteran/Elite and
						-- any untagged unit are excluded (unknown tier → not
						-- recruitable). The "non-playable race" clause has no field
						-- to check yet (RaceData has no `playable` flag and all races
						-- are currently playable) — a harmless no-op until a
						-- non-playable race is ever added.
						local maxHp = u.maxHp or 1
						local hpFrac = (u.currentHp or 0) / math.max(1, maxHp)
						local tierEligible = (u.enemyType == "Grunt")
						-- Recruit targets ENEMIES only: a recruited unit becomes
						-- Neutral and is no longer an enemy, so it can never be
						-- re-recruited (guarded above). Require genuine enemy side.
						local isEnemyOfActor = (u.side == "Enemy") or (actor.side == "Player" and u.side ~= "Player" and u.side ~= "Neutral")
						if hpFrac <= recruitThreshold and tierEligible and isEnemyOfActor then
							table.insert(candidates, {
								interactKind = "recruitEnemy",
								id = u.id, name = u.name,
								tileX = u.tileX, tileY = u.tileY,
							})
						end
					end
				end
			end
		end
	end

	-- MAP-OBJECT NATIVE (PARKED — Slice 5) --------------------------------
	-- state.objects holds the generator's placed instances, shape { id, type,
	-- x, y } (MapService.placeObjects). Read THAT shape here; emit candidate
	-- fields (objectId/archetypeId/tileX/tileY) that the CommandService Interact
	-- branch consumes. The command branch resolves activation + free/consumes-
	-- action from ObjectData.activation; this function only needs reach + existence.
	if state and state.objects then
		for _, obj in ipairs(state.objects) do
			if obj.x and obj.y then
				local dist = chebyshevDistance(actor.tileX, actor.tileY, obj.x, obj.y)
				if dist <= reach then
					table.insert(candidates, {
						interactKind = "mapObject",
						objectId = obj.id,
						archetypeId = obj.type,
						name = obj.type or obj.id or "Object",
						tileX = obj.x, tileY = obj.y,
					})
				end
			end
		end
	end

	return candidates
end

return TargetingService
