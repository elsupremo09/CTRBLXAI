--!strict
-- WeatherService — applies the active battlefield weather/crisis condition during
-- combat (Slice: weather engine, 2026-10-04). Until now a condition was picked at
-- map-gen (mapState.battleCondition) but INERT; this makes it live.
--
-- MODEL (user-locked 2026-10-04): ONE combined exclusive slot holds EITHER a
-- weather OR a crisis per round. It RE-ROLLS every round (1000 CT) from the
-- biome's battleConditionWeights pool. The quest sets the STARTING condition.
-- All periodic effects fire every 300 CT. "Undispellable for the duration" = one
-- round (the slot re-rolls next round, clearing weather-sourced statuses).
-- Battlefield events are a SEPARATE system and are not touched here.
--
-- SERVER-ONLY. Server authority (ARC-001): all effects mutate authoritative state
-- here; the client only renders. Reuses built systems (StatusService, TileEffect,
-- MapRenderer.ReshapeTile, CombatResolver damage, GameConstants terrain maps).
--
-- Dependency injection (avoids cycles): BattleCoordinator calls Reroll/Tick;
-- TileEffectService + the broadcaster are injected; GameConstants is required
-- directly (no cycle). StatusService reads a weather-suppression flag that THIS
-- module pushes to it (SetWeatherBurnSuppressed), so StatusService need not require
-- WeatherService.

local WeatherService = {}

local GameConstants = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("CTRBLXAI"):WaitForChild("Shared"):WaitForChild("GameConstants")
)

-- Injected at runtime (nil-safe).
local _tileEffectService = nil
local _broadcaster = nil
local _statusService = nil
local _tileReshaper = nil  -- fn(x,y,terrain,elev) over the live mapFolder (from Main)

function WeatherService.SetTileEffectService(tes) _tileEffectService = tes end
function WeatherService.SetBroadcaster(b) _broadcaster = b end
function WeatherService.SetStatusService(ss) _statusService = ss end
function WeatherService.SetTileReshaper(fn) _tileReshaper = fn end

-- Active-condition state.
local _active = "Clear"          -- current condition id
local _biomePool = nil           -- biome.battleConditionWeights (set at battle start)
local _roundIndex = 0            -- floor(ct/1000); re-roll when it increments
local _periodicAccumCt = 0       -- accumulates ctPassed; fires periodic every 300

-- Battlefield-event hooks (BattlefieldEventService, 2026-10-04). Additive; inert
-- unless set. _blockedConditions[id]=true excludes a condition from the per-round
-- roll (Earth Elemental: "Earthquake Crisis can't occur while it exists").
-- _nextConditionOverride (Fortune Teller: "choose the upcoming Weather/Crisis")
-- replaces the NEXT round's roll once, then clears. Both reset in Init.
local _blockedConditions = {}
local _nextConditionOverride = nil

local PERIODIC_INTERVAL = 300

-- Conditions whose passive suppresses Burn application (user ruling 2026-10-04:
-- Rain and Snow Storm prevent Burn effects entirely while active).
local BURN_SUPPRESSORS = { Rain = true, ["Snow Storm"] = true }

-- Passive element-damage multipliers per condition (positive-only table; absent
-- element = 1.0). Read by CombatResolver via GetElementDamageMultiplier.
local PASSIVE_ELEMENT_MOD = {
	Rain         = { Fire = 0.75, Water = 1.25 },
	Heatwave     = { Fire = 1.20, Water = 0.80 },
	["Dark Eclipse"] = { Light = 0.75, Dark = 1.25 },
	["Holy Aurora"]  = { Light = 1.25, Dark = 0.75 },
	["Strong Wind"]  = { Wind = 1.25 },
}

--------------------------------------------------------------------
-- PUBLIC: element passive modifier (CombatResolver reads this).
--------------------------------------------------------------------
function WeatherService.GetElementDamageMultiplier(element)
	if not element then return 1.0 end
	local mods = PASSIVE_ELEMENT_MOD[_active]
	return (mods and mods[element]) or 1.0
end

function WeatherService.GetActiveCondition()
	return _active
end

-- StatusService calls this (via its injected flag) to know whether to block Burn.
function WeatherService.IsBurnSuppressed()
	return BURN_SUPPRESSORS[_active] == true
end

--------------------------------------------------------------------
-- Push the Burn-suppression state to StatusService so IsImmune blocks Burn
-- application under Rain / Snow Storm without StatusService requiring this module.
--------------------------------------------------------------------
local function syncBurnSuppression()
	if _statusService and _statusService.SetWeatherBurnSuppressed then
		_statusService.SetWeatherBurnSuppressed(BURN_SUPPRESSORS[_active] == true)
	end
end

--------------------------------------------------------------------
-- Battle start: set the biome pool + the quest-chosen starting condition.
--------------------------------------------------------------------
function WeatherService.Init(biomePool, startingCondition, startCt)
	_biomePool = biomePool
	_active = startingCondition or "Clear"
	_roundIndex = math.floor((startCt or 0) / 1000)
	_periodicAccumCt = 0
	_blockedConditions = {}
	_nextConditionOverride = nil
	syncBurnSuppression()
	print(string.format("[WeatherService] Init | starting condition=%s", _active))
	if _broadcaster and _broadcaster.WeatherChanged then
		_broadcaster.WeatherChanged(_active)
	end
end

-- Convenience: load the biome's battleConditionWeights pool by biome id (so the
-- caller need not require BiomeData). Then Init with the quest's starting condition.
function WeatherService.InitFromBiome(biomeId, startingCondition, startCt)
	local pool = nil
	local ok, BiomeData = pcall(function()
		return require(
			game:GetService("ReplicatedStorage"):WaitForChild("Content"):WaitForChild("BiomeData"))
	end)
	if ok and BiomeData then
		local b = BiomeData[biomeId] or (BiomeData.Biomes and BiomeData.Biomes[biomeId])
		pool = b and b.battleConditionWeights or nil
	end
	WeatherService.Init(pool, startingCondition, startCt)
end

--------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------
-- Map dimensions. GameConstants has NO MAP_WIDTH/MAP_HEIGHT fields — the grid is
-- stored as TERRAIN_MAP[y][x] / ELEVATION_MAP[y][x], so height = #TERRAIN_MAP and
-- width = #TERRAIN_MAP[1]. Read live each call so tile reshapes never desync dims
-- (reshapes change contents, not grid size). Cycle-free (no injection needed).
local function gridDims()
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

-- Apply a WEATHER-SOURCED status that must persist, undispellable, for this round.
-- Tagged weatherLocked so RerollForNewRound can clear it and the Frozen hard-lock
-- can block the Fire->Wet reaction. Rebuild stats after (buff/debuff may be stat).
local function applyWeatherStatus(unit, statusId, hardLock)
	if not _statusService then return end
	_statusService.ApplyStatus(unit, statusId, "weather")
	-- Mark the freshly-applied instance.
	for _, inst in ipairs(unit.statusInstances) do
		if inst.id == statusId then
			inst.weatherLocked = true
			inst.undispellable = true
			if hardLock then inst.hardLock = true end  -- blocks Fire->Wet thaw (Snow Storm)
		end
	end
	if _broadcaster and _broadcaster.UnitStateChanged then
		_broadcaster.UnitStateChanged(unit)
	end
end

-- Remove all weather-sourced statuses from every unit (called on re-roll).
local function clearWeatherStatuses(state)
	for _, u in ipairs(state.units) do
		if u.statusInstances then
			for i = #u.statusInstances, 1, -1 do
				if u.statusInstances[i].weatherLocked then
					table.remove(u.statusInstances, i)
				end
			end
			if _broadcaster and _broadcaster.UnitStateChanged then
				_broadcaster.UnitStateChanged(u)
			end
		end
	end
end

-- Simple deterministic weighted pick over the biome condition pool.
local function rollCondition(rng)
	if not _biomePool then return "Clear" end
	local entries, total = {}, 0
	for k, w in pairs(_biomePool) do
		-- Blocked conditions (battlefield events) are excluded from the roll.
		if type(w) == "number" and w > 0 and not _blockedConditions[k] then
			total = total + w
			table.insert(entries, { key = k, w = w })
		end
	end
	if total == 0 then return "Clear" end
	table.sort(entries, function(a, b) return a.key < b.key end)
	local r = rng:NextNumber() * total
	local acc = 0
	for _, e in ipairs(entries) do
		acc = acc + e.w
		if r <= acc then return e.key end
	end
	return entries[#entries].key
end

-- Elevation grid helpers (tile reshape via injected reshaper + GameConstants maps).
local function reshapeTile(x, y, terrain, elev)
	if terrain then GameConstants.SetTerrainId(x, y, terrain) end
	if elev ~= nil and GameConstants.ELEVATION_MAP[y] then
		GameConstants.ELEVATION_MAP[y][x] = elev
	end
	if _tileReshaper then _tileReshaper(x, y, terrain, elev) end
end

--------------------------------------------------------------------
-- CONDITION ONSET (applied once when a condition becomes active) — the
-- "for the duration" statuses: Rain Wet, Snow Storm Frozen, Dark Eclipse Haste,
-- Holy Aurora Slow. These are weatherLocked (cleared next re-roll).
--------------------------------------------------------------------

-- Dark Eclipse / Holy Aurora target set: Undead-tag OR Undead status OR Werewolf
-- OR Vampire OR the Demon race (user-locked set, 2026-10-04; Demon is a race not a tag).
local function isNightAlignedUnit(unit)
	if not unit then return false end
	if unit.raceId == "RACE-WEREWOLF" or unit.raceId == "RACE-VAMPIRE"
		or unit.raceId == "RACE-DEMON" then
		return true
	end
	-- Undead race tag
	local RaceData = require(
		game:GetService("ReplicatedStorage"):WaitForChild("Content"):WaitForChild("RaceData"))
	local rd = unit.raceId and RaceData.GetRace(unit.raceId)
	if rd and rd.tags then
		for _, t in ipairs(rd.tags) do if t == "Undead" then return true end end
	end
	-- Temporary Undead STATUS
	if unit.statusInstances then
		for _, inst in ipairs(unit.statusInstances) do
			if inst.id == "Undead" then return true end
		end
	end
	return false
end

local function applyOnset(state)
	if _active == "Rain" then
		for _, u in ipairs(livingUnits(state)) do applyWeatherStatus(u, "Wet", false) end
	elseif _active == "Snow Storm" then
		for _, u in ipairs(livingUnits(state)) do applyWeatherStatus(u, "Frozen", true) end
	elseif _active == "Dark Eclipse" then
		for _, u in ipairs(livingUnits(state)) do
			if isNightAlignedUnit(u) then applyWeatherStatus(u, "Haste", false) end
		end
	elseif _active == "Holy Aurora" then
		for _, u in ipairs(livingUnits(state)) do
			if isNightAlignedUnit(u) then applyWeatherStatus(u, "Slow", false) end
		end
	end
end

--------------------------------------------------------------------
-- PERIODIC HANDLERS (every 300 CT). Keyed by condition id. ctx = {state, rng}.
--------------------------------------------------------------------
local Periodic = {}

Periodic["Rain"] = function(ctx)
	-- Re-assert Wet on units/tiles (undispellable); Wet reactions handled by TileEffect.
	for _, u in ipairs(livingUnits(ctx.state)) do applyWeatherStatus(u, "Wet", false) end
end

Periodic["Mana Storm"] = function(ctx)
	for _, u in ipairs(livingUnits(ctx.state)) do
		local maxMp = u.maxMp or 0
		u.currentMp = math.min(maxMp, (u.currentMp or 0) + math.floor(maxMp * 0.10))
		local dmg = math.floor((u.currentMp or 0) * 0.50)
		u.currentHp = math.max(0, (u.currentHp or 0) - dmg)
		if u.currentHp <= 0 then u.isAlive = false end
		if _broadcaster then _broadcaster.UnitStateChanged(u) end
	end
end

Periodic["Severe Hail"] = function(ctx)
	local units = livingUnits(ctx.state)
	-- Random half take 10% Max HP.
	local n = #units
	-- DB: round(active_units / 2) — rounds up on odd counts (not floor).
	local half = math.floor(n / 2 + 0.5)
	-- Deterministic shuffle via rng.
	for i = n, 2, -1 do
		local j = ctx.rng:NextInteger(1, i)
		units[i], units[j] = units[j], units[i]
	end
	for i = 1, half do
		local u = units[i]
		local dmg = math.floor((u.maxHp or 0) * 0.10)
		u.currentHp = math.max(0, (u.currentHp or 0) - dmg)
		if u.currentHp <= 0 then u.isAlive = false end
		if _broadcaster then _broadcaster.UnitStateChanged(u) end
	end
end

Periodic["Hunger Virus"] = function(ctx)
	for _, u in ipairs(livingUnits(ctx.state)) do
		local dmg = math.floor((u.maxHp or 0) * 0.05)
		u.currentHp = math.max(0, (u.currentHp or 0) - dmg)
		if u.currentHp <= 0 then u.isAlive = false end
		if _broadcaster then _broadcaster.UnitStateChanged(u) end
	end
	-- (Basic-attack lifesteal 20% is applied in CombatResolver when active; see hook.)
end

Periodic["Thunderstorm"] = function(ctx)
	-- Strike a random highest-elevation unit: 20% Max HP + lower that tile 1.
	local units = livingUnits(ctx.state)
	if #units == 0 then return end
	local best = -math.huge
	for _, u in ipairs(units) do
		local e = GameConstants.GetElevation(u.tileX, u.tileY)
		if e > best then best = e end
	end
	local top = {}
	for _, u in ipairs(units) do
		if GameConstants.GetElevation(u.tileX, u.tileY) == best then table.insert(top, u) end
	end
	local tgt = top[ctx.rng:NextInteger(1, #top)]
	local dmg = math.floor((tgt.maxHp or 0) * 0.20)
	tgt.currentHp = math.max(0, (tgt.currentHp or 0) - dmg)
	if tgt.currentHp <= 0 then tgt.isAlive = false end
	reshapeTile(tgt.tileX, tgt.tileY, nil, math.max(1, best - 1))
	if _broadcaster then _broadcaster.UnitStateChanged(tgt) end
end

Periodic["Earthquake"] = function(ctx)
	-- Alter 20-40% of tiles by -2..+2 elevation; units on changed tiles +150 RT.
	local w, h = gridDims()
	if w == 0 or h == 0 then return end
	local total = w * h
	local frac = 0.20 + ctx.rng:NextNumber() * 0.20
	local count = math.floor(total * frac)
	local occ = {}
	for _, u in ipairs(livingUnits(ctx.state)) do occ[u.tileX .. "," .. u.tileY] = u end
	for _ = 1, count do
		local x = ctx.rng:NextInteger(1, w)
		local y = ctx.rng:NextInteger(1, h)
		local cur = GameConstants.GetElevation(x, y)
		local delta = ctx.rng:NextInteger(-2, 2)
		local newE = math.max(1, cur + delta)
		if delta ~= 0 then
			reshapeTile(x, y, nil, newE)
			local u = occ[x .. "," .. y]
			if u then
				u.remainingRt = (u.remainingRt or 0) + 150
				if _broadcaster then _broadcaster.UnitStateChanged(u) end
			end
		end
	end
end

Periodic["Wild Growth"] = function(ctx)
	-- Apply Vines tile effect to 15-25% of vine-less terrain.
	if not _tileEffectService or not _tileEffectService.ApplyTileEffect then return end
	local w, h = gridDims()
	if w == 0 or h == 0 then return end
	local count = math.floor(w * h * (0.15 + ctx.rng:NextNumber() * 0.10))
	for _ = 1, count do
		local x = ctx.rng:NextInteger(1, w)
		local y = ctx.rng:NextInteger(1, h)
		_tileEffectService.ApplyTileEffect(x, y, "Vines", "weather", ctx.state.units)
	end
end

-- Mark-then-strike hazards (Meteor Storm, Volcanic Eruptions): mark tiles now,
-- resolve after a 300 CT delay. Pending marks live on module state.
local _pendingStrikes = {}  -- { {resolveCt, tiles={{x,y}}, kind} }

local function markStrike(ctx, kind, areaCount, areaFn)
	local w, h = gridDims()
	if w == 0 or h == 0 then return end
	local tiles = {}
	for _ = 1, areaCount do
		local cx = ctx.rng:NextInteger(1, w)
		local cy = ctx.rng:NextInteger(1, h)
		for _, t in ipairs(areaFn(cx, cy)) do table.insert(tiles, t) end
	end
	table.insert(_pendingStrikes, { resolveCt = ctx.nowCt + 300, tiles = tiles, kind = kind })
end

Periodic["Meteor Storm"] = function(ctx)
	-- Mark 1-3 occupied tiles; resolve after 300 CT.
	local units = livingUnits(ctx.state)
	local n = math.min(#units, ctx.rng:NextInteger(1, 3))
	local marks = {}
	for i = 1, n do
		local u = units[ctx.rng:NextInteger(1, #units)]
		if u then
			-- Center tile: 30% Fire + lower elevation 1 (isCenter). DB Meteor Storm
			-- also splashes 15% to the 8 adjacent tiles (no elevation change there).
			table.insert(marks, { x = u.tileX, y = u.tileY, pct = 0.30, isCenter = true })
			for dy = -1, 1 do
				for dx = -1, 1 do
					if not (dx == 0 and dy == 0) then
						table.insert(marks, { x = u.tileX + dx, y = u.tileY + dy, pct = 0.15 })
					end
				end
			end
		end
	end
	table.insert(_pendingStrikes, { resolveCt = ctx.nowCt + 300, tiles = marks, kind = "Meteor" })
end

Periodic["Volcanic Eruptions"] = function(ctx)
	markStrike(ctx, "Volcanic", ctx.rng:NextInteger(3, 5), function(cx, cy)
		return { {x=cx,y=cy},{x=cx+1,y=cy},{x=cx-1,y=cy},{x=cx,y=cy+1},{x=cx,y=cy-1} }
	end)
end

-- Resolve any pending strikes whose time has come.
local function resolvePendingStrikes(state, nowCt)
	for i = #_pendingStrikes, 1, -1 do
		local p = _pendingStrikes[i]
		if nowCt >= p.resolveCt then
			for _, t in ipairs(p.tiles) do
				for _, u in ipairs(livingUnits(state)) do
					if u.tileX == t.x and u.tileY == t.y then
						-- Per-tile pct when present (Meteor center 0.30 / splash 0.15);
						-- otherwise kind default (Volcanic 0.15).
						local pct = t.pct or ((p.kind == "Meteor") and 0.30 or 0.15)
						local dmg = math.floor((u.maxHp or 0) * pct)
						u.currentHp = math.max(0, (u.currentHp or 0) - dmg)
						if u.currentHp <= 0 then u.isAlive = false end
						if _broadcaster then _broadcaster.UnitStateChanged(u) end
					end
				end
				if p.kind == "Meteor" then
					-- Only the center tile drops elevation; splash tiles do not.
					if t.isCenter then
						local cur = GameConstants.GetElevation(t.x, t.y)
						reshapeTile(t.x, t.y, nil, math.max(1, cur - 1))
					end
				else
					local cur = GameConstants.GetElevation(t.x, t.y)
					reshapeTile(t.x, t.y, "Molten", cur + 1)
				end
			end
			table.remove(_pendingStrikes, i)
		end
	end
end

Periodic["Heatwave"] = function(ctx)
	-- Terrain transforms (DB Heatwave): water->Clear, Ice->Shallow Water (melt),
	-- Grassland/Clover->Burning, Swamp/Mud->Rocky. Each tile visited once per tick,
	-- so a melted Ice tile won't also evaporate to Clear this same round.
	local w, h = gridDims()
	for y = 1, h do
		for x = 1, w do
			local t = GameConstants.GetTerrainId(x, y)
			if t == "Shallow Water" or t == "Deep Water" then
				reshapeTile(x, y, "Clear", nil)
			elseif t == "Ice" then
				reshapeTile(x, y, "Shallow Water", nil)
			elseif t == "Swamp" or t == "Mud" then
				reshapeTile(x, y, "Rocky", nil)
			elseif (t == "Grassland" or t == "Clover Field")
				and _tileEffectService and _tileEffectService.ApplyTileEffect then
				_tileEffectService.ApplyTileEffect(x, y, "Burning", "weather", ctx.state.units)
			end
		end
	end
end

-- Strong Wind: remove Airborne effects (Steam/Static Cloud) via Wind reaction.
-- Burning-accel / Poison-spread are new mechanics (Designer-defined, cadence-only);
-- built as a cadence hook — the actual spread reuses TileEffect spread when wired.
Periodic["Strong Wind"] = function(ctx)
	if _tileEffectService and _tileEffectService.RemoveAirborneEffects then
		_tileEffectService.RemoveAirborneEffects(ctx.state.units)
	end
	-- Burning-accel / Poison-Cloud-spread: trigger an extra spread cadence if the
	-- TileEffectService exposes it (nil-safe; inert until that hook exists).
	if _tileEffectService and _tileEffectService.ProcessSpread then
		_tileEffectService.ProcessSpread(0)  -- cadence-only nudge; no reach widening
	end
end

--------------------------------------------------------------------
-- PUBLIC: per-round re-roll (called at each 1000-CT round boundary).
--------------------------------------------------------------------
function WeatherService.RerollForNewRound(state, rng, nowCt)
	local newRound = math.floor((nowCt or state.ct or 0) / 1000)
	if newRound == _roundIndex then return false end
	_roundIndex = newRound
	-- Clear last round's weather-sourced statuses, pick a new condition, apply onset.
	clearWeatherStatuses(state)
	_pendingStrikes = {}
	-- Fortune Teller override (battlefield event): the chosen condition replaces
	-- this round's roll once (unless it has since become blocked), then clears.
	if _nextConditionOverride and not _blockedConditions[_nextConditionOverride] then
		_active = _nextConditionOverride
		print(string.format("[WeatherService] Round %d uses chosen condition (Fortune Teller)", newRound))
	else
		_active = rollCondition(rng)
	end
	_nextConditionOverride = nil
	syncBurnSuppression()
	applyOnset(state)
	print(string.format("[WeatherService] Round %d -> condition=%s", _roundIndex, _active))
	if _broadcaster and _broadcaster.WeatherChanged then
		_broadcaster.WeatherChanged(_active)
	end
	return true
end

--------------------------------------------------------------------
-- PUBLIC: periodic tick (called from BattleCoordinator with elapsed CT).
--------------------------------------------------------------------
function WeatherService.Tick(state, ctPassed, rng, nowCt)
	-- Resolve any delayed strikes first.
	resolvePendingStrikes(state, nowCt or state.ct or 0)
	_periodicAccumCt = _periodicAccumCt + (ctPassed or 0)
	while _periodicAccumCt >= PERIODIC_INTERVAL do
		_periodicAccumCt = _periodicAccumCt - PERIODIC_INTERVAL
		local fn = Periodic[_active]
		if fn then
			local ok, err = pcall(fn, { state = state, rng = rng, nowCt = nowCt or state.ct or 0 })
			if not ok then
				warn("[WeatherService] periodic '" .. tostring(_active) .. "' error: " .. tostring(err))
			end
		end
	end
end

-- Apply onset for the STARTING condition at battle start (after Init).
function WeatherService.ApplyStartingOnset(state)
	applyOnset(state)
end

--------------------------------------------------------------------
-- DEV / TEST: force a specific condition immediately (Studio dev panel).
-- Clears the previous condition's weather-sourced statuses, sets the new
-- condition, syncs burn-suppression, applies onset, and broadcasts — the
-- same steps as a round re-roll, but with an explicit id and no round gate.
-- The next natural round boundary will still re-roll over this.
--------------------------------------------------------------------
function WeatherService.ForceCondition(conditionId, state)
	if type(conditionId) ~= "string" or conditionId == "" then
		warn("[WeatherService] ForceCondition: invalid id")
		return false
	end
	if state then
		clearWeatherStatuses(state)
	end
	_pendingStrikes = {}
	_active = conditionId
	syncBurnSuppression()
	if state then
		applyOnset(state)
	end
	print(string.format("[WeatherService] DEV ForceCondition -> %s", _active))
	if _broadcaster and _broadcaster.WeatherChanged then
		_broadcaster.WeatherChanged(_active)
	end
	return true
end

--------------------------------------------------------------------
-- BATTLEFIELD-EVENT HOOKS (BattlefieldEventService, 2026-10-04). Additive and
-- inert unless called. BattlefieldEventService receives WeatherService by
-- injection (no require either way -> cycle-free).
--------------------------------------------------------------------

-- Fortune Teller: choose the NEXT round's condition (consumed by the next
-- RerollForNewRound). Must be a condition id known to the biome pool or "Clear".
function WeatherService.SetNextCondition(conditionId)
	if type(conditionId) ~= "string" or conditionId == "" then return false end
	if conditionId ~= "Clear" and not (_biomePool and _biomePool[conditionId]) then
		warn("[WeatherService] SetNextCondition: '" .. conditionId .. "' not in biome pool")
		return false
	end
	_nextConditionOverride = conditionId
	print(string.format("[WeatherService] Next round condition chosen -> %s", conditionId))
	return true
end

function WeatherService.GetNextCondition()
	return _nextConditionOverride
end

-- Earth Elemental: block / unblock a condition from the per-round roll.
function WeatherService.SetConditionBlocked(conditionId, blocked)
	if type(conditionId) ~= "string" then return end
	_blockedConditions[conditionId] = blocked and true or nil
end

function WeatherService.IsConditionBlocked(conditionId)
	return _blockedConditions[conditionId] == true
end

-- Sorted list of condition ids this biome can roll (weight > 0, not blocked).
function WeatherService.GetConditionPool()
	local out = {}
	if _biomePool then
		for k, w in pairs(_biomePool) do
			if type(w) == "number" and w > 0 and not _blockedConditions[k] then
				table.insert(out, k)
			end
		end
	end
	table.sort(out)
	return out
end

-- Run ONE firing of a condition's periodic effect on demand, independent of the
-- active slot (Earth Elemental: "Triggers Earthquake Crisis effect every turn").
-- Reuses the exact Periodic handler (no duplicated logic). Returns true if fired.
function WeatherService.RunConditionEffect(conditionId, state, rng)
	local fn = Periodic[conditionId]
	if not fn or not state then return false end
	local ok, err = pcall(fn, {
		state = state,
		rng = rng or Random.new((state.ct or 0) + 24680),
		nowCt = state.ct or 0,
	})
	if not ok then
		warn("[WeatherService] RunConditionEffect '" .. tostring(conditionId) .. "' error: " .. tostring(err))
		return false
	end
	return true
end

return WeatherService
