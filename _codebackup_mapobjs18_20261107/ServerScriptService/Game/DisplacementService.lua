-- DisplacementService.lua
-- CTRBLXAI | Slice 2 — Displacement Resolution Engine
--
-- Resolves forced movement (push, knockback). This module handles
-- the PHYSICS of what happens when a unit is displaced — tile-by-tile
-- resolution, wall collisions, fall damage, occupied-destination fallback.
--
-- It does NOT handle:
--   - Command validation, AP/RT costs (Slice 3 — CommandService)
--   - Broadcasting visual events (caller does that with the result)
--   - Action menu or UI (Slice 7)
--
-- Callers:
--   - Push global action (Slice 3 integration)
--   - Weapon knockback passives (Hammer/Club)
--   - Any future skill with authored displacement
--
-- DB sources:
--   movement_targeting.Elevation & Displacement (all displacement rules)
--   project_rules.Push Action (push-specific rules)
--   core_stats.STR → Force, core_stats.VIT → Stability

local GameConstants = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Shared")
		:WaitForChild("GameConstants")
)

local TileCrossEffectService = require(script.Parent.TileCrossEffectService)
-- Race passives (Feline Nine Lives fall immunity / collision +20%, 2026-10-02).
local RacePassiveService = require(script.Parent.RacePassiveService)
local StatusService = require(script.Parent.StatusService) -- status Stability buffs (2026-10-07)
local TraitEffectService = require(script.Parent.TraitEffectService) -- Perks & Flaws: fall/collision mults (2026-10-23)
local StatCalcService = require(script.Parent.StatCalcService) -- shared Stability calculation (2026-10-28)

local DisplacementService = {}

--------------------------------------------------
-- MAP DIMENSIONS (set by caller or default to 8×8)
--------------------------------------------------

local _mapWidth  = 8
local _mapHeight = 8

function DisplacementService.SetMapDimensions(width, height)
	_mapWidth  = width
	_mapHeight = height
end

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function isInsideMap(x, y)
	return x >= 1 and x <= _mapWidth and y >= 1 and y <= _mapHeight
end

-- Find the occupying unit at a tile (nil if empty).
local function getUnitAt(allUnits, tileX, tileY)
	for _, unit in ipairs(allUnits) do
		if unit.isAlive and unit.tileX == tileX and unit.tileY == tileY then
			return unit
		end
	end
	return nil
end

-- Get what type of collision object a blocker is.
-- Reads objectType from GameConstants.GetBlockerData.
local function getBlockerCollisionType(tileX, tileY)
	local data = GameConstants.GetBlockerData(tileX, tileY)
	if data and data.objectType then
		return data.objectType
	end
	return "StoneWall" -- fallback if no metadata
end

-- Find the nearest valid unoccupied tile to (tileX, tileY).
-- Used when a unit is pushed into an occupied tile and needs
-- to land somewhere nearby.
-- Searches in a spiral outward. Returns {tileX, tileY} or nil.
local function findNearestEmptyTile(allUnits, originX, originY, excludeUnit)
	local visited = {}
	local queue = {{ x = originX, y = originY }}
	visited[originX .. "," .. originY] = true

	local dirs = {
		{0,1}, {0,-1}, {1,0}, {-1,0},
		{1,1}, {1,-1}, {-1,1}, {-1,-1},
	}

	local head = 1
	while head <= #queue do
		local cur = queue[head]
		head = head + 1

		if isInsideMap(cur.x, cur.y)
			and not GameConstants.IsBlocked(cur.x, cur.y)
		then
			local occupant = getUnitAt(allUnits, cur.x, cur.y)
			if occupant == nil or occupant == excludeUnit then
				return { tileX = cur.x, tileY = cur.y }
			end
		end

		for _, d in ipairs(dirs) do
			local nx, ny = cur.x + d[1], cur.y + d[2]
			local key = nx .. "," .. ny
			if isInsideMap(nx, ny) and not visited[key] then
				visited[key] = true
				table.insert(queue, { x = nx, y = ny })
			end
		end
	end

	return nil
end

--------------------------------------------------
-- CORE: ResolvePush
--
-- Resolves a single forced-displacement event tile by tile.
--
-- Parameters:
--   pusher        — unit doing the pushing
--   target        — unit being pushed
--   force         — attacker's Force value (already computed)
--   direction     — { dx = ±1, dy = ±1 } unit vector away from pusher
--   sourceModifier — 1.0 for Global Action Push, 0.5 for Skill knockback
--   allUnits      — all units in the battle (for occupancy checks)
--
-- Returns a result table:
--   {
--     pushed         = true/false,
--     tilesDisplaced = N,
--     finalTileX     = X,
--     finalTileY     = Y,
--     wallCollision  = { damage = N, colliderType = "StoneWall" } or nil,
--     fallDamage     = N or nil,
--     blockedBy      = "unit"/"blocker"/"edge"/"elevation"/nil,
--     totalFallHeight = N or nil,
--     crossEffects   = { {type="slide", ...}, ... } or nil,
--   }
--
-- IMPORTANT: This function does NOT write to unit state. It only
-- reads positions and stats, then returns the result. The caller
-- applies the actual HP changes and position updates.
--------------------------------------------------

-- How many tiles a push of `force` would move `target`, before any player-chosen stop distance.
-- Shared by ResolvePush and the turn-prompt push preview (CommandService.GetPushPreview), so the
-- stop tiles a player can pick always match the push (2026-10-28). Returns distance, effective
-- Stability (after the pusher's stability ignore). Reads unit state only; never writes it.
-- ignoreGuard (2026-10-29): GL-012 Crushing Vambraces -- Guard-based push defences (BD-002 negate,
-- BD-004 +3 Stability) do not apply.
function DisplacementService.CalcPushDistance(target, force, isRanged, stabilityIgnore, ignoreGuard)
	-- Steadfast Strike augment: displacement-immune this round -> cannot be moved.
	if target._displacementImmune then
		return 0, 0
	end
	local targetStability = StatCalcService.GetStability(target, "battle", ignoreGuard)

	-- GL-001 Reinforced Gloves: the PUSHER may ignore up to N of the target's effective Stability
	-- (passed by the Push command via GetPushStabilityIgnore; nil/0 for all other push sources, so
	-- knockback/augment pushes are unaffected -- consistent with how GL push-force is Push-only).
	-- Applied AFTER all stability additions (VIT + status buffs + Anchor Mail Guard), floored at 0.
	if stabilityIgnore and stabilityIgnore > 0 then
		targetStability = math.max(0, targetStability - stabilityIgnore)
	end
	local pushDistance = math.max(0, force - targetStability)
	-- Armor (2026-10-24): BD-002 Fortress Plate negates incoming push entirely while Guarding;
	-- BD-008 Grounding Harness reduces forced displacement distance by 2 (always active). Deferred
	-- require avoids any load-time cycle.
	do
		local _aps = (require :: any)(script.Parent.ArmorPassiveService)
		if pushDistance > 0 and not ignoreGuard and StatusService.HasStatus(target, "Guard") and _aps.CanGuardNegatePush(target) then
			pushDistance = 0
		else
			local dispRed = _aps.GetDisplacementReduction(target)
			if dispRed > 0 then pushDistance = math.max(0, pushDistance - dispRed) end
		end
	end
	-- Ranged knockback penalty: knockback from a RANGED attack is reduced by 50%,
	-- rounded up (DB: ranged knockback distance x0.5, ceil). A nonzero knockback keeps
	-- at least 1 tile. Central hook — every ranged knockback source inherits this by
	-- passing isRanged=true. Melee/global-push sources pass false/nil (no reduction).
	if isRanged and pushDistance > 0 then
		pushDistance = math.ceil(pushDistance * 0.5)
	end
	return pushDistance, targetStability
end

-- preResolved (optional, 2026-10-28): requestedDistance is already the final distance (each hit of a
-- multi-hit attack checked Stability on its own and the results were summed), so Stability is not
-- applied a second time. Displacement immunity still applies.
function DisplacementService.ResolvePush(pusher, target, force, direction, sourceModifier, allUnits, requestedDistance, isRanged, stabilityIgnore, preResolved)
	assert(type(pusher) == "table", "ResolvePush: pusher must be a unit table.")
	assert(type(target) == "table", "ResolvePush: target must be a unit table.")
	assert(type(direction) == "table" and direction.dx and direction.dy,
		"ResolvePush: direction must be {dx, dy}.")

	-- Steadfast Strike augment (2026-10-24): a unit flagged displacement-immune this round
	-- cannot be pushed/pulled. Return the standard RESISTED shape (no movement) so every
	-- caller stays nil-safe. Flag is set in OnSkillComplete and cleared at the unit's EndTurn.
	if target._displacementImmune then
		return {
			pushed = false, tilesDisplaced = 0,
			finalTileX = target.tileX, finalTileY = target.tileY,
			wallCollision = nil, fallDamage = nil, blockedBy = nil, totalFallHeight = 0,
		}
	end

	sourceModifier = sourceModifier or 1.0

	-- Step 1: Calculate push distance.
	-- DB rule (Push Distance): Stability = floor(VIT/60). Default 0, no +1 offset,
	-- so this matches the Main pushTargets maxPushDistance preview exactly.
	-- Effective Stability: one shared calculation (StatCalcService.GetStability, 2026-10-28) --
	-- base (VIT + traits + PAS-014) + status buffs + BD-004 Anchor Mail while Guarding + FT-003
	-- Heavy March Boots. The push preview and the Info panels read the same function.
	-- Distance math moved to CalcPushDistance (2026-10-28) so the turn-prompt push preview uses
	-- the exact same numbers: Stability, GL-001 ignore, Fortress Plate, Grounding Harness, ranged x0.5.
	-- Push-action-only glove effects (checklist fix 2026-10-29): GL-009 Ram, GL-010 Edgefinder and
	-- GL-012 Crushing apply to the Push action (GlobalPush source), not to skill / weapon / item
	-- knockbacks the wearer causes (those pass SkillKnockback).
	local isGlobalPush = (sourceModifier == GameConstants.KNOCKBACK_SOURCE_MODIFIERS.GlobalPush)
	local _pushCfg = isGlobalPush and (require :: any)(script.Parent.ArmorPassiveService).GetPushCollisionConfig(pusher) or nil
	local crushIgnoreGuard = _pushCfg ~= nil and _pushCfg.type == "Crush" and _pushCfg.ignoreGuard == true
	local pushDistance, targetStability = DisplacementService.CalcPushDistance(target, force, isRanged, stabilityIgnore, crushIgnoreGuard)
	if preResolved and requestedDistance ~= nil then
		pushDistance = math.max(0, math.floor(requestedDistance))
		requestedDistance = nil
	end
	-- Distance control: pusher may request a shorter stop distance (fixed direction).
	-- nil = full distance (AI / legacy callers). Clamp to [0, maxDistance] (SEC-001).
	if requestedDistance ~= nil then
		pushDistance = math.min(pushDistance, math.max(0, math.floor(requestedDistance)))
	end

	if pushDistance == 0 then
		print(string.format(
			"[DisplacementService] Push RESISTED | %s (Force %d) -> %s (Stability %d) | Distance: 0",
			pusher.name, force, target.name, targetStability
		))
		return {
			pushed         = false,
			tilesDisplaced = 0,
			finalTileX     = target.tileX,
			finalTileY     = target.tileY,
			wallCollision  = nil,
			fallDamage     = nil,
			blockedBy      = nil,
			totalFallHeight = 0,
		}
	end

	-- Step 2: Resolve tile-by-tile displacement.
	local dx = direction.dx
	local dy = direction.dy
	local currentX = target.tileX
	local currentY = target.tileY
	local currentElev = GameConstants.GetElevation(currentX, currentY)

	local tilesDisplaced = 0
	local blockedBy = nil
	local wallCollisionResult = nil
	local totalFallHeight = 0
	local crossEffects = {}
	local tilesPath = {}   -- ordered tiles the target is dragged ONTO (excludes origin); for trap triggers
	local startElev = currentElev

	-- GL-015 Throwing Gloves, Push action only (user ruling 2026-10-29: "Push uses arc projectile
	-- rules" = the pushed unit FLIES OVER anything in its path and only stops where it lands). It lands
	-- on the farthest tile up to the push distance that is on the map, not blocked, not occupied by
	-- another unit and not higher than where it started. Tiles flown over are never entered (no
	-- collision, no traps, no tile effects there). No legal landing tile = it does not move.
	local _arcCfg = isGlobalPush and (require :: any)(script.Parent.ArmorPassiveService).GetPushArcConfig(pusher) or nil
	local arcPush = _arcCfg ~= nil and _arcCfg.arcProjectile == true
	if arcPush then
		-- A pull (Android / Butcher's Gloves) never flies the target past the puller: if the puller
		-- stands on the flight line, the farthest landing is the tile just before it (2026-10-29).
		local arcMax = pushDistance
		if pusher and pusher.tileX then
			for k = 1, pushDistance do
				if target.tileX + dx * k == pusher.tileX and target.tileY + dy * k == pusher.tileY then
					arcMax = k - 1
					break
				end
			end
		end
		for k = arcMax, 1, -1 do
			local lx, ly = target.tileX + dx * k, target.tileY + dy * k
			if isInsideMap(lx, ly) and not GameConstants.IsBlocked(lx, ly)
				and GameConstants.GetElevation(lx, ly) <= startElev then
				local occ = getUnitAt(allUnits, lx, ly)
				if occ == nil or occ == target then
					currentX, currentY = lx, ly
					currentElev = GameConstants.GetElevation(lx, ly)
					totalFallHeight = math.max(0, startElev - currentElev)
					tilesDisplaced = k
					table.insert(tilesPath, { x = lx, y = ly })
					for _, eff in ipairs(TileCrossEffectService.OnTileEntered(target, lx, ly, direction, true, allUnits)) do
						table.insert(crossEffects, eff)
					end
					break
				end
			end
		end
	end

	for step = 1, (arcPush and 0 or pushDistance) do
		local nextX = currentX + dx
		local nextY = currentY + dy

		-- Check 1: map bounds
		if not isInsideMap(nextX, nextY) then
			blockedBy = "edge"
			local blockedTiles = pushDistance - tilesDisplaced
			wallCollisionResult = {
				damage = GameConstants.CalcWallCollisionDamage(
					target.maxHp, blockedTiles, pusher.effectiveStats.STR,
					"StoneWall", sourceModifier
				),
				colliderType = "edge",
			}
			break
		end

		-- Check 2: blocker (impassable object)
		if GameConstants.IsBlocked(nextX, nextY) then
			blockedBy = "blocker"
			local blockerType = getBlockerCollisionType(nextX, nextY)
			local blockedTiles = pushDistance - tilesDisplaced
			wallCollisionResult = {
				damage = GameConstants.CalcWallCollisionDamage(
					target.maxHp, blockedTiles, pusher.effectiveStats.STR,
					blockerType, sourceModifier
				),
				colliderType = blockerType,
			}
			break
		end

		-- Check 3: elevation — forced upward is blocked
		local nextElev = GameConstants.GetElevation(nextX, nextY)
		if nextElev > currentElev then
			blockedBy = "elevation"
			local blockedTiles = pushDistance - tilesDisplaced
			wallCollisionResult = {
				damage = GameConstants.CalcWallCollisionDamage(
					target.maxHp, blockedTiles, pusher.effectiveStats.STR,
					"StoneWall", sourceModifier
				),
				colliderType = "elevation",
			}
			break
		end

		-- Check 4: occupancy — another unit on the tile. The PUSHER counts too (fix 2026-10-26,
		-- UAT thread-b4963227de5d): a PULL travels toward the pusher, and skipping it let the target
		-- land on or pass through the user. DB nonweapon_equipment edge-case rule (GL-005 Pull): if
		-- remaining Force exceeds the gap, "the target collides with the acting unit; normal collision
		-- damage to both" -- "Pull behaves identically to Push in terms of collision rules". A push
		-- moves AWAY from the pusher, so it can never reach the pusher's tile: pushes are unchanged.
		local occupant = getUnitAt(allUnits, nextX, nextY)
		if occupant and occupant ~= target then
			blockedBy = "unit"
			local blockedTiles = pushDistance - tilesDisplaced
			-- Pushed unit takes collision damage (uses pushed unit's MaxHP)
			wallCollisionResult = {
				damage = GameConstants.CalcWallCollisionDamage(
					target.maxHp, blockedTiles, pusher.effectiveStats.STR,
					"Unit", sourceModifier
				),
				colliderType = "Unit",
				collidedUnitId = occupant.id,
				-- Collided unit also takes collision damage (uses THEIR MaxHP).
				-- Same formula: both units absorb the same impact.
				collidedUnitDamage = GameConstants.CalcWallCollisionDamage(
					occupant.maxHp, blockedTiles, pusher.effectiveStats.STR,
					"Unit", sourceModifier
				),
			}
			break
		end

		-- Tile is clear — move target here.
		if nextElev < currentElev then
			totalFallHeight = totalFallHeight + (currentElev - nextElev)
		end

		currentX = nextX
		currentY = nextY
		currentElev = nextElev
		tilesDisplaced = tilesDisplaced + 1
		-- Record each tile crossed (forced-movement trap triggers walk this list).
		table.insert(tilesPath, { x = currentX, y = currentY })

		-- Resolve cross effects for the tile we just entered.
		local tileEffects = TileCrossEffectService.OnTileEntered(
			target, currentX, currentY, direction, true, allUnits
		)
		for _, eff in ipairs(tileEffects) do
			table.insert(crossEffects, eff)
		end
	end

	-- Step 2b: SLIDING KNOCKBACK (DB terrain_effects: Ice "Sliding Knockback"; Oily "Knockback
	-- continues until first non-Oily/non-Ice tile"; built 2026-10-29 -- the slide was never applied).
	-- A unit knocked onto a slippery tile without being stopped keeps going the same way until it
	-- lands on the first non-slippery tile, or stops before a blocker / unit / map edge / height
	-- change (TileCrossEffectService.ResolveSlide, no collision damage). Not for Throwing Gloves
	-- throws (they land), flying units, or a unit wearing FT-013 Ice Cleats.
	if not arcPush and tilesDisplaced > 0 and blockedBy == nil
		and TileCrossEffectService.IsSlipperyTile(currentX, currentY)
		and not StatusService.HasStatus(target, "Flight") then
		local _apsSlide = (require :: any)(script.Parent.ArmorPassiveService)
		if _apsSlide.CanAvoidIceSlide(target) then
			print(string.format("[DisplacementService] Ice Cleats: %s does not slide", target.name))
		else
			local savedX, savedY = target.tileX, target.tileY
			target.tileX, target.tileY = currentX, currentY  -- ResolveSlide skips the sliding unit by identity
			local slide = TileCrossEffectService.ResolveSlide(target, currentX, currentY, dx, dy, allUnits, _mapWidth, _mapHeight)
			target.tileX, target.tileY = savedX, savedY
			for _ = 1, (slide and slide.tilesSlid or 0) do
				currentX += dx
				currentY += dy
				tilesDisplaced += 1
				table.insert(tilesPath, { x = currentX, y = currentY })
				for _, eff in ipairs(TileCrossEffectService.OnTileEntered(target, currentX, currentY, direction, true, allUnits)) do
					table.insert(crossEffects, eff)
				end
			end
			currentElev = GameConstants.GetElevation(currentX, currentY)
		end
	end

	-- Step 3: If pushed into an occupied tile (unit collision),
	-- find the nearest valid empty tile for the target to land on.
	if blockedBy == "unit" then
		if tilesDisplaced == 0 then
			local fallback = findNearestEmptyTile(allUnits, currentX, currentY, target)
			if fallback then
				currentX = fallback.tileX
				currentY = fallback.tileY
			end
		end
	end

	-- Step 4: Calculate fall damage from cumulative forced downward drop.
	local fallDamage = 0
	-- Armor BD-013 Feather Armor (2026-10-24): while Guarding, reduce effective fall height by 2
	-- (fewer effective drop tiles -> less/no fall damage). Applied to the height before the calc.
	do
		local _aps = (require :: any)(script.Parent.ArmorPassiveService)
		if not crushIgnoreGuard and StatusService.HasStatus(target, "Guard") then
			local fhr = _aps.GetGuardFallHeightReduction(target)
			if fhr > 0 then totalFallHeight = math.max(0, totalFallHeight - fhr) end
		end
	end
	-- GL-010 Edgefinder Gloves (PUSHER): when the Push forces the target DOWNWARD (there is an actual
	-- drop), treat Fall Height as +1 for the damage formula. Pusher-keyed (the glove is on the unit
	-- doing the pushing); only applies when totalFallHeight > 0 so a flat push is unaffected. Deferred
	-- require mirrors the Feather Armor / Collision Padding idiom above.
	if totalFallHeight > 0 and isGlobalPush then
		local _apsPush = (require :: any)(script.Parent.ArmorPassiveService)
		local fhBonus = _apsPush.GetPushFallHeightBonus(pusher)
		if fhBonus > 0 then totalFallHeight = totalFallHeight + fhBonus end
	end
	if totalFallHeight >= GameConstants.FALL_DAMAGE_MIN_HEIGHT then
		fallDamage = GameConstants.CalcFallDamage(target.maxHp, totalFallHeight)
	end
	-- Perks & Flaws (2026-10-23): Acrophobic (x1.5) / Sure-Footed (x0.5) scale the BASE
	-- fall damage. CalcFallDamage has no VIT term, so its output IS the "base fall damage
	-- before VIT bonus" the DB refers to. Applied BEFORE Feline immunity so immunity still
	-- wins (zeroes any scaled value).
	if fallDamage > 0 then
		local fMult = TraitEffectService.GetFallDamageMultiplier(target)
		if fMult ~= 1 then
			fallDamage = math.round(fallDamage * fMult)
		end
	end
	-- Armor BD-012 Collision Padding (2026-10-24): collision AND fall damage x0.5 (always active).
	if fallDamage > 0 then
		local _aps = (require :: any)(script.Parent.ArmorPassiveService)
		local cfMult = _aps.GetCollisionFallDamageModifier(target)
		if cfMult ~= 1 then fallDamage = math.round(fallDamage * cfMult) end
	end
	-- FELINE — Nine Lives (races row 'Feline', 2026-10-02): immune to fall damage
	-- (any downward displacement, any height). ONLY the fall-damage term is zeroed;
	-- cross effects and landing-tile / chasm-floor ground effects resolve normally.
	if fallDamage > 0 and RacePassiveService.IsFallDamageImmune(target) then
		print(string.format("[DisplacementService] Feline Nine Lives: %s fall damage %d -> 0", target.name, fallDamage))
		fallDamage = 0
	end
	-- FELINE — Nine Lives: collision / knockback-impact damage received +20%, for the
	-- pushed unit (wallCollision.damage) and/or the unit it slammed into
	-- (collidedUnitDamage) -- whichever is Feline.
	-- Plus Perks & Flaws (2026-10-23): Squishy / Thorny. collisionRecv scales the damage
	-- THIS unit receives (race x trait); the collided-into unit's collisionInflict clause
	-- ("units colliding with this unit take X") scales the PUSHED unit's damage. The
	-- pushed unit is treated as the collider, so its own inflict clause does not apply
	-- while it is the one being pushed.
	if wallCollisionResult then
		-- Resolve the collided-into unit (if any) up front so both sides can read it.
		local collided = nil
		if wallCollisionResult.collidedUnitId then
			for _, u in ipairs(allUnits or {}) do
				if u.id == wallCollisionResult.collidedUnitId then collided = u; break end
			end
		end
		-- PUSHED unit (target) received collision damage.
		if wallCollisionResult.damage then
			local tMult = RacePassiveService.GetCollisionDamageMultiplier(target)
				* TraitEffectService.GetCollisionDamageReceivedMultiplier(target)
				* (require :: any)(script.Parent.ArmorPassiveService).GetCollisionFallDamageModifier(target)
			if collided then
				tMult = tMult * TraitEffectService.GetCollisionDamageInflictedMultiplier(collided)
			end
			-- GL-009 Ram Gauntlets (PUSHER): wall collision damage from this unit's Push gains x1.25.
			-- Pusher-keyed and applies to the pushed unit's wall-impact damage only (not the collided
			-- bystander). Config via GetPushCollisionConfig (type "Ram").
			do
				local ram = (require :: any)(script.Parent.ArmorPassiveService).GetPushCollisionConfig(pusher)
				if isGlobalPush and ram and ram.type == "Ram" and ram.wallDamageMultiplier and wallCollisionResult.colliderType ~= "Unit" then
					tMult = tMult * ram.wallDamageMultiplier
				end
			end
			-- Item collision multiplier (2026-10-26, DAM-016 Kinetic Ram "collision multiplier x1.25"):
			-- the item path stamps pusher._itemCollisionMult for the duration of its one push.
			if pusher and pusher._itemCollisionMult then
				tMult = tMult * pusher._itemCollisionMult
			end
			if tMult ~= 1 then
				wallCollisionResult.damage = math.round(wallCollisionResult.damage * tMult)
			end
		end
		-- COLLIDED-into unit received collision damage (its own receive-mult, race x trait).
		if collided and wallCollisionResult.collidedUnitDamage then
			local cMult = RacePassiveService.GetCollisionDamageMultiplier(collided)
				* TraitEffectService.GetCollisionDamageReceivedMultiplier(collided)
				* (require :: any)(script.Parent.ArmorPassiveService).GetCollisionFallDamageModifier(collided)
			if pusher and pusher._itemCollisionMult then
				cMult = cMult * pusher._itemCollisionMult  -- Kinetic Ram: the whole collision is harder
			end
			if cMult ~= 1 then
				wallCollisionResult.collidedUnitDamage = math.round(wallCollisionResult.collidedUnitDamage * cMult)
			end
		end
	end

	-- Build result.
	local result = {
		pushed          = tilesDisplaced > 0,
		tilesDisplaced  = tilesDisplaced,
		finalTileX      = currentX,
		finalTileY      = currentY,
		wallCollision   = wallCollisionResult,
		fallDamage      = fallDamage > 0 and fallDamage or nil,
		blockedBy       = blockedBy,
		totalFallHeight = totalFallHeight,
		crossEffects    = #crossEffects > 0 and crossEffects or nil,
		tilesPath       = tilesPath,
	}

	print(string.format(
		"[DisplacementService] Push | %s -> %s | Force:%d Stab:%d Dist:%d | Moved:%d to (%d,%d)%s%s%s",
		pusher.name, target.name,
		force, targetStability, pushDistance,
		tilesDisplaced, currentX, currentY,
		wallCollisionResult and string.format(
			" | WallDmg:%d (%s)%s",
			wallCollisionResult.damage,
			wallCollisionResult.colliderType,
			wallCollisionResult.collidedUnitDamage
				and string.format(" + CollidedDmg:%d", wallCollisionResult.collidedUnitDamage)
				or ""
		) or "",
		fallDamage > 0 and string.format(" | FallDmg:%d (drop %d)", fallDamage, totalFallHeight) or "",
		blockedBy and (" | BlockedBy:" .. blockedBy) or ""
	))

	return result
end

--------------------------------------------------
-- HELPER: Calculate push direction from pusher to target.
-- Returns {dx, dy} as a unit direction (each component is -1, 0, or 1).
-- Direction is AWAY from pusher (target moves further from pusher).
--------------------------------------------------

function DisplacementService.GetPushDirection(pusher, target)
	local rawDx = target.tileX - pusher.tileX
	local rawDy = target.tileY - pusher.tileY

	local dx = 0
	local dy = 0
	if rawDx > 0 then dx = 1 elseif rawDx < 0 then dx = -1 end
	if rawDy > 0 then dy = 1 elseif rawDy < 0 then dy = -1 end

	-- Edge case: pusher and target on the same tile (shouldn't happen).
	if dx == 0 and dy == 0 then
		dx = 1
	end

	return { dx = dx, dy = dy }
end

return DisplacementService
