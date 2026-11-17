--!strict
-- FurnitureSaveV2.lua
-- CTRBLXAI | Furniture save format v2: export + strict import (W-C checks), split out of
-- FurnitureService.lua (furniture v5 build step A, 2026-11-16). Code moved word-for-word; no behaviour
-- change. Old v1 conversion stays in FurnitureService (it rolls new instances).
-- OWNS: nothing. Import fills the caller's (empty) instances / placement tables in place.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FurnitureData = require(ReplicatedStorage:WaitForChild("Content"):WaitForChild("FurnitureData"))
local FurnitureRoll = require(script.Parent:WaitForChild("FurnitureRoll"))
local V4: any = FurnitureData.V4

local FurnitureSaveV2 = {}

local SAVE_VERSION = 2
local MAX_INSTANCES = 2000 -- save sanity bound only (v5 step 3: was 400, which would have cut pieces off a big save)
local GRANT_LIMIT: number = V4.Sources.GrantLimit -- 400: no NEW piece is created at this count (row 111 deferred)
local STEP = FurnitureRoll.STEP
local isStepKind = FurnitureRoll.IsStepKind

type Line = { kind: string, value: number, points: number, enemy: boolean?, threshold: boolean?, signature: boolean? }
type Inst = { uid: string, id: string, rarity: string, lines: { Line }, fixed: boolean?, looks: boolean?, src: string?, welcome: boolean? }

--- Lines -> save form (shared by export and the dungeon run save).
local function exportLines(lines: { Line }): { any }
	local out = {}
	for _, l in lines do
		table.insert(out, { k = l.kind, v = l.value, p = l.points, e = l.enemy, t = l.threshold, s = l.signature })
	end
	return out
end

local function export(instances: { [string]: Inst }, placement: { [string]: string }, nextUid: number, noticePending: boolean, convSeed: number): any
	local list = {}
	for _, inst in instances do
		table.insert(list, { u = inst.uid, id = inst.id, r = inst.rarity, l = exportLines(inst.lines), f = inst.fixed, lo = inst.looks, src = inst.src, w = inst.welcome })
	end
	table.sort(list, function(a, b) return a.u < b.u end)
	local place = {}
	for k, u in placement do place[k] = u end
	return { v = SAVE_VERSION, instances = list, place = place, nextUid = nextUid, notice = noticePending,
		convSeed = convSeed, shop = {}, wv = 1 } -- wv = welcome pieces flagged (step 1, 2026-11-16)
end

local function validKind(k: any): boolean
	if type(k) ~= "string" or #k > 32 then return false end
	if V4.PointPrice[k] or V4.Enemy.PointPrice[k] then return true end
	if table.find(V4.Threshold.Kinds, k) or k == "range" then return true end
	return false
end

-- W-C: one saved line checked against its piece/rarity (row 101/107/108). Returns a clean Line or nil.
local function cleanLine(l: any, p: any, rar: string): Line?
	if type(l) ~= "table" or not validKind(l.k) or type(l.v) ~= "number" or l.v ~= l.v then return nil end
	local enemy = l.e == true
	if l.s == true then
		local sv = p.signature and p.signature[l.k]
		if type(sv) ~= "number" or enemy then return nil end
		local old = FurnitureData.Get(p.id)
		return { kind = l.k, value = sv, points = if old then old.points else (sv * (V4.PointPrice[l.k] or 0)), signature = true }
	end
	local r = V4.Rarities[rar]
	if not r then return nil end
	if l.t == true then
		if (r.threshold or 0) <= 0 then return nil end
		local pool = if enemy then V4.Enemy.Threshold[p.type] else V4.Types[p.type].threshold
		local ok = pool ~= nil and table.find(pool, l.k) ~= nil
		if not ok and not enemy and l.k == V4.Types[p.type].thresholdIfRangeOn and V4.Threshold.RangeEnabled then ok = true end
		if l.k == "range" and not V4.Threshold.RangeEnabled then ok = false end
		if not ok then return nil end
		return { kind = l.k, value = if enemy then -1 else 1, points = 0, threshold = true, enemy = if enemy then true else nil }
	end
	local price = if enemy then V4.Enemy.PointPrice[l.k] else V4.PointPrice[l.k]
	if type(price) ~= "number" or price <= 0 or l.v <= 0 then return nil end
	local value = l.v
	local cap = if enemy then V4.Enemy.Max[l.k] else V4.SecondaryMax[l.k]
	if type(cap) == "number" then value = math.min(value, cap) end
	value = math.min(value, r.pts[2] / price) -- clamp into the rarity's point range (top)
	if isStepKind(l.k) then value = math.floor(value / STEP + 1e-6) * STEP else value = math.floor(value + 1e-6) end
	if value <= 0 then return nil end
	return { kind = l.k, value = value, points = value * price, enemy = if enemy then true else nil }
end

--- One saved piece entry {id, r, l, ...} checked against its piece / rarity (W-C). Returns the clean
--- fields (no uid) or nil. Shared by the furniture save and the dungeon run's found pieces (v5 step 3).
local function cleanEntry(e: any): (string?, string?, { Line }?)
	local p = if type(e) == "table" then V4.Get(e.id) else nil
	if not p then return nil, nil, nil end
	local lines: { Line } = {}
	if p.looksOnly then return e.id, "None", lines end
	if p.fixed then return e.id, "Fixed", lines end
	local rar: string = if type(e.r) == "string" and V4.Rarities[e.r] then e.r else "Common"
	local r = V4.Rarities[rar]
	local nRolled, nThr, nSig = 0, 0, 0
	local maxSig = 0
	if p.signature then for _ in p.signature do maxSig += 1 end end
	for _, raw in (type(e.l) == "table" and e.l or {}) do
		local l = cleanLine(raw, p, rar)
		if l then
			if l.signature then
				if nSig < maxSig then nSig += 1 table.insert(lines, l) end
			elseif l.threshold then
				if nThr < (r.threshold or 0) then nThr += 1 table.insert(lines, l) end
			elseif nRolled < r.lines then
				nRolled += 1
				table.insert(lines, l)
			end
		end
	end
	return e.id, rar, lines
end

-- v5 step 3 (save safety): a save holding MORE than GrantLimit (400) pieces still loads in full up to
-- MAX_INSTANCES (sanity bound only); placed pieces load first, so nothing placed is ever dropped.
local function importV2(data: any, instances: { [string]: Inst }, placement: { [string]: string }): (number, boolean, number)
	local placedU: { [string]: boolean } = {}
	for _, u in (type(data.place) == "table" and data.place or {}) do
		if type(u) == "string" then placedU[u] = true end
	end
	local list = type(data.instances) == "table" and data.instances or {}
	local n, skipped = 0, 0
	for pass = 1, 2 do
		for _, e in list do
			local isPlaced = type(e) == "table" and type(e.u) == "string" and placedU[e.u] == true
			if (pass == 1) == isPlaced then
				if n >= MAX_INSTANCES then
					skipped += 1
				elseif type(e) == "table" and type(e.u) == "string" and #e.u <= 16 and not instances[e.u] then
					local id, rar, lines = cleanEntry(e)
					local p = id and V4.Get(id)
					if id and rar and lines and p then
						instances[e.u] = { uid = e.u, id = id, rarity = rar, lines = lines,
							fixed = if p.fixed then true else nil, looks = if p.looksOnly then true else nil,
							src = if type(e.src) == "string" and #e.src <= 16 then e.src else nil,
							welcome = if e.w == true and V4.WelcomeKinds[id] then true else nil }
						n += 1
					end
				end
			end
		end
	end
	if n > GRANT_LIMIT then warn(`[FurnitureSaveV2] Save holds {n} pieces (over the {GRANT_LIMIT} grant limit): all loaded, no new pieces until below it`) end
	if skipped > 0 then warn(`[FurnitureSaveV2] Save holds more than {MAX_INSTANCES} pieces: {skipped} unplaced piece(s) not loaded`) end
	local used: { [string]: boolean } = {}
	for k, u in (type(data.place) == "table" and data.place or {}) do
		if type(k) == "string" and #k <= 40 and string.find(k, "^%a+/[fw]%d+$") and type(u) == "string"
			and instances[u] and not used[u] then
			placement[k] = u
			used[u] = true
		end
	end
	local nextUid = math.max(1, math.floor(tonumber(data.nextUid) or 1))
	for u in instances do
		local num = tonumber(string.match(u, "^f(%d+)$"))
		if num and num >= nextUid then nextUid = num + 1 end
	end
	local noticePending = data.notice == true
	local convSeed = math.floor(tonumber(data.convSeed) or 0)
	return nextUid, noticePending, convSeed
end

FurnitureSaveV2.VERSION = SAVE_VERSION
FurnitureSaveV2.MAX_INSTANCES = MAX_INSTANCES
FurnitureSaveV2.Export = export
FurnitureSaveV2.CleanLine = cleanLine
FurnitureSaveV2.ImportV2 = importV2
FurnitureSaveV2.CleanEntry = cleanEntry -- v5 step 3
FurnitureSaveV2.ExportLines = exportLines -- v5 step 3
FurnitureSaveV2.GRANT_LIMIT = GRANT_LIMIT -- v5 step 3

return FurnitureSaveV2
