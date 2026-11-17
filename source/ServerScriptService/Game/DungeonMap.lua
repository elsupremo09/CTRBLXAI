--!strict
-- DungeonMap.lua
-- CTRBLXAI | Seeded Slay-the-Spire style dungeon map. (Build step 1, 2026-11-13)
--
-- Server-only, pure: Generate(seed, facilityLevel, floors?, layout?) -> map table. Same inputs = same map.
-- layout (card.mapLayout): 1 = old Rest-every-4 rows, 2 = mid-map gates, 3 = gates + extra Sanctuary rows +
-- gate rows never merge paths (2026-11-17). nil = 1 (runs saved before the gates).
-- Rules: project_rules 260 (shape), 261 (weights), 262 (placement). Numbers live in DungeonRules.
--
-- Map:  { seed, facilityLevel, floors, width, rows = { [row] = { [col] = node } }, boss = node,
--         starts = { node ids on row 1 } }
-- Node: { id = "r3c2", row, col, type, played, next = { ids } }   (Boss row = floors + 1)

local DungeonRules = require(script.Parent:WaitForChild("DungeonRules"))
local D = DungeonRules.Data

local DungeonMap = {}

local MAX_ATTEMPTS = 50

local function nid(r: number, c: number): string
	return "r" .. r .. "c" .. c
end

-- Draw MapPaths bottom-to-top paths. Each step goes to one of the 3 nearest rooms above;
-- edges never cross; the first two start rooms differ. Returns edges[r][c] = { [c2]=true }.
-- Fixed Rest rows (project_rules 260, USER RULING 2026-11-13 6:54 PM): the last row before the Boss,
-- plus row N-2 on maps with 6+ floors.
-- Stages ruling 2026-11-15 (rule 260): fixed Rest rows every 4 rows down from the boss (N, N-4, N-8 ...).
-- Layout 2 (USER RULING 2026-11-17 3:15 PM): pre-Boss Sanctuary row + mid-map gates (Sanctuary row, then a
-- full Elite row); layout 1 = the old cadence for runs saved before that. Rows live in DungeonRules.
local function isFixedRest(r: number, floors: number, layout: number): boolean
	return DungeonRules.IsFixedRestRow(r, floors, layout)
end
local function isGateElite(r: number, floors: number, layout: number): boolean
	return DungeonRules.IsGateEliteRow(r, floors, layout)
end

-- Treasure row = ceil(N/2), moved one row DOWN (toward row 1) if it lands on a fixed Rest row
-- (auto-accepted default 2026-11-15, rule 260).
-- Layout 2: also moved off a gate Elite row (keeps moving down until the row is free).
local function treasureRowFor(floors: number, layout: number): number
	local t = math.ceil(floors / 2)
	if layout < 2 then
		if isFixedRest(t, floors, layout) then t -= 1 end
		return math.max(2, t)
	end
	while t > 2 and (isFixedRest(t, floors, layout) or isGateElite(t, floors, layout)) do t -= 1 end
	return math.max(2, t)
end

local function drawPaths(rng: Random, floors: number, width: number, layout: number): ({ [number]: { [number]: { [number]: boolean } } }, { number })
	local edges: { [number]: { [number]: { [number]: boolean } } } = {}
	for r = 1, floors - 1 do
		edges[r] = {}
		for c = 1, width do edges[r][c] = {} end
	end
	local starts: { number } = {}
	local firstStart = 0
	-- landed[r][c2] = source col of the first edge into gate room (r, c2); -1 = two sources (merged)
	local landed: { [number]: { [number]: number } } = {}
	local noMerge = DungeonRules.GateNoMerge(layout)
	for p = 1, D.MapPaths do
		local c = rng:NextInteger(1, width)
		if p == 2 then
			while c == firstStart do c = rng:NextInteger(1, width) end
		end
		if p == 1 then firstStart = c end
		table.insert(starts, c)
		for r = 1, floors - 1 do
			local options: { number } = {}
			for dc = -1, 1 do
				local c2 = c + dc
				if c2 >= 1 and c2 <= width then
					-- crossing: moving c->c+1 crosses an existing (c+1)->c edge, and vice versa
					local crosses = (dc == 1 and edges[r][c + 1][c] == true)
						or (dc == -1 and edges[r][c - 1][c] == true)
					if not crosses then table.insert(options, c2) end
				end
			end
			local gate = noMerge and isGateElite(r + 1, floors, layout)
			if gate and #options > 0 then
				-- layout 3: don't lead into a gate room another room already leads into (paths stay separate)
				landed[r + 1] = landed[r + 1] or {}
				local free: { number } = {}
				for _, o in options do
					local src = landed[r + 1][o]
					if src == nil or src == c then table.insert(free, o) end
				end
				if #free > 0 then options = free end
			end
			local c2 = if #options > 0 then options[rng:NextInteger(1, #options)] else c
			if gate then
				local src = landed[r + 1][c2]
				if src == nil then landed[r + 1][c2] = c elseif src ~= c then landed[r + 1][c2] = -1 end
			end
			edges[r][c][c2] = true
			c = c2
		end
	end
	return edges, starts
end

local function pickWeighted(rng: Random, allowed: { [string]: boolean }): string
	local total = 0
	for _, w in D.NodeWeights do
		if allowed[w.type] then total += w.weight end
	end
	if total <= 0 then return "Battle" end
	local roll = rng:NextNumber() * total
	for _, w in D.NodeWeights do
		if allowed[w.type] then
			roll -= w.weight
			if roll < 0 then return w.type end
		end
	end
	return "Battle"
end

local function build(rng: Random, seed: number, facilityLevel: number, floors: number, layout: number): any
	local width = D.MapWidth
	local edges, starts = drawPaths(rng, floors, width, layout)

	-- rooms that are on a path
	local used: { [number]: { [number]: boolean } } = {}
	for r = 1, floors do used[r] = {} end
	for _, c in starts do used[1][c] = true end
	for r = 1, floors - 1 do
		for c = 1, width do
			for c2 in edges[r][c] do used[r + 1][c2] = true end
		end
	end
	-- parents[r][c] = list of cols on row r-1 leading here
	local parents: { [number]: { [number]: { number } } } = {}
	for r = 1, floors do
		parents[r] = {}
		for c = 1, width do parents[r][c] = {} end
	end
	for r = 1, floors - 1 do
		for c = 1, width do
			for c2 in edges[r][c] do table.insert(parents[r + 1][c2], c) end
		end
	end

	local types: { [number]: { [number]: string } } = {}
	local treasureRow = treasureRowFor(floors, layout)
	for r = 1, floors do
		types[r] = {}
		for c = 1, width do
			if used[r][c] then
				local t: string
				if r == 1 then
					t = "Battle"
				elseif r == treasureRow then
					t = "Treasure"
				elseif isFixedRest(r, floors, layout) then
					t = "Rest"
				elseif isGateElite(r, floors, layout) then
					t = "Elite" -- gate: the whole row is Elite, so every path meets one
				else
					local allowed: { [string]: boolean } = {}
					for _, w in D.NodeWeights do allowed[w.type] = true end
					if r <= 2 then allowed.Elite = false; allowed.Rest = false end
					if isFixedRest(r + 1, floors, layout) then allowed.Rest = false end -- no Rest just below a fixed Rest row
					local ps = parents[r][c]
					for _, pc in ps do
						local pt = types[r - 1][pc]
						if pt == "Elite" then allowed.Elite = false end
						if pt == "Rest" then allowed.Rest = false end
						if pt == "Merchant" then allowed.Merchant = false end
						if pt == "Mystery" then allowed.Mystery = false end -- project_rules 262
						-- rooms branching from the same parent must differ
						for c2 in edges[r - 1][pc] do
							if c2 < c and types[r][c2] then allowed[types[r][c2]] = false end
						end
					end
					t = pickWeighted(rng, allowed)
				end
				types[r][c] = t
			end
		end
	end

	local rows: { [number]: { [number]: any } } = {}
	for r = 1, floors do
		rows[r] = {}
		for c = 1, width do
			if used[r][c] then
				local nxt: { string } = {}
				if r < floors then
					for c2 = 1, width do
						if edges[r][c][c2] then table.insert(nxt, nid(r + 1, c2)) end
					end
				else
					nxt = { "boss" }
				end
				rows[r][c] = {
					id = nid(r, c), row = r, col = c, type = types[r][c],
					played = DungeonRules.PlayedType(types[r][c]), next = nxt,
				}
			end
		end
	end
	local startIds: { string } = {}
	for c = 1, width do
		if used[1][c] then table.insert(startIds, nid(1, c)) end
	end
	return {
		seed = seed, facilityLevel = facilityLevel, floors = floors, width = width, layout = layout,
		rows = rows, starts = startIds,
		boss = { id = "boss", row = floors + 1, col = 0, type = "Boss", played = "Boss", next = {} },
	}
end

--- Validate a map against project_rules 260/262. Returns ok, list of problems.
function DungeonMap.Validate(map: any): (boolean, { string })
	local problems: { string } = {}
	local function bad(s: string) table.insert(problems, s) end
	local floors = map.floors
	local layout = map.layout or 1
	local treasureRow = treasureRowFor(floors, layout)
	local byId: { [string]: any } = { boss = map.boss }
	for r = 1, floors do
		for _, n in map.rows[r] do byId[n.id] = n end
	end
	local parentsOf: { [string]: { any } } = {}
	for _, n in byId do
		for _, x in n.next do
			parentsOf[x] = parentsOf[x] or {}
			table.insert(parentsOf[x], n)
		end
	end
	for r = 1, floors do
		for _, n in map.rows[r] do
			local t = n.type
			if r == 1 and t ~= "Battle" then bad(n.id .. " row1 not Battle") end
			if r == treasureRow and t ~= "Treasure" then bad(n.id .. " treasure row") end
			if isFixedRest(r, floors, layout) and t ~= "Rest" then bad(n.id .. " rest row") end
			if isGateElite(r, floors, layout) and t ~= "Elite" then bad(n.id .. " gate Elite row") end
			if (t == "Elite" or t == "Rest") and r <= 2 then bad(n.id .. " " .. t .. " on row " .. r) end
			if t == "Rest" and not isFixedRest(r, floors, layout) and isFixedRest(r + 1, floors, layout) then bad(n.id .. " Rest before Rest row") end
			if (t == "Merchant" or t == "Mystery") and r == 1 then bad(n.id .. " " .. t .. " on row 1") end
			if t == "Mystery" and isFixedRest(r, floors, layout) then bad(n.id .. " Mystery on a Rest row") end
			if t == "Escape" then bad(n.id .. " Escape room (removed 2026-11-13 11:36 PM)") end
			if t == "Event" then bad(n.id .. " Event room (merged into the \"?\" room 2026-11-15 10:15 AM)") end
			for _, p in parentsOf[n.id] or {} do
				if t == p.type and (t == "Elite" or t == "Rest" or t == "Merchant" or t == "Mystery") then
					bad(n.id .. " " .. t .. " twice in a row")
				end
			end
			if #n.next == 0 then bad(n.id .. " dead end") end
			if r > 1 and not parentsOf[n.id] then bad(n.id .. " unreachable") end
		end
		-- siblings differ (random rows only; fixed rows are one type by design)
		if r < floors then
			for _, n in map.rows[r] do
				local seen: { [string]: boolean } = {}
				for _, x in n.next do
					local cn = byId[x]
					if cn and cn.row ~= 1 and cn.row ~= treasureRow and not isFixedRest(cn.row, floors, layout) and not isGateElite(cn.row, floors, layout) then
						if seen[cn.type] then bad(n.id .. " children share " .. cn.type) end
						seen[cn.type] = true
					end
				end
			end
		end
	end
	-- crossing edges
	for r = 1, floors - 1 do
		for c = 1, map.width do
			local n = map.rows[r][c]
			if n then
				for _, x in n.next do
					local c2 = byId[x].col
					if c2 == c + 1 then
						local m = map.rows[r][c + 1]
						if m then
							for _, y in m.next do
								if byId[y].col == c then bad(n.id .. " crossing edge") end
							end
						end
					end
				end
			end
		end
	end
	-- layout 3: a gate Elite row never merges paths (each gate room has one room below leading into it)
	if DungeonRules.GateNoMerge(layout) then
		for r = 2, floors do
			if isGateElite(r, floors, layout) then
				for _, n in map.rows[r] do
					local below = 0
					for _, p in parentsOf[n.id] or {} do
						if p.row == r - 1 then below += 1 end
					end
					if below > 1 then bad(n.id .. " gate room merges " .. below .. " paths") end
				end
			end
		end
	end
	local s = map.starts
	if #s < 2 then bad("fewer than 2 start rooms") end
	return #problems == 0, problems
end

--- Seeded map. floors = 8 / 12 / 15 by difficulty (stages ruling 2026-11-15); nil = 8.
--- Retries (same rng stream) until placement rules hold. layout: card.mapLayout (nil = 1, old saved runs).
function DungeonMap.Generate(seed: number, facilityLevel: number, floors: number?, layout: number?): any
	local rng = Random.new(seed)
	local f = if type(floors) == "number" and floors >= 3 and floors <= 30 then math.floor(floors) else 8
	local lay = if type(layout) == "number" then math.clamp(math.floor(layout), 1, D.MapLayout) else 1
	local map: any = nil
	for _ = 1, MAX_ATTEMPTS do
		map = build(rng, seed, facilityLevel, f, lay)
		local ok = DungeonMap.Validate(map)
		if ok then return map end
	end
	warn("[DungeonMap] no valid map after " .. MAX_ATTEMPTS .. " attempts (seed " .. seed .. ")")
	return map
end

return table.freeze(DungeonMap)
