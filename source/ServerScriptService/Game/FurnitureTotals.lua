--!strict
-- FurnitureTotals.lua
-- CTRBLXAI | Furniture room spots + totals (legacy block-1 and V4), split out of FurnitureService.lua
-- (furniture v5 build step A, 2026-11-16). Step 1 (2026-11-16): V4 totals drive unit stats (BonusTable).
-- OWNS: nothing. The caller passes its placement (spotKey -> uid) and instances (uid -> Inst).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FurnitureData = require(ReplicatedStorage:WaitForChild("Content"):WaitForChild("FurnitureData"))
local V4: any = FurnitureData.V4

local FurnitureTotals = {}

type Line = { kind: string, value: number, points: number, enemy: boolean?, threshold: boolean?, signature: boolean? }
type Inst = { uid: string, id: string, rarity: string, lines: { Line }, fixed: boolean?, looks: boolean?, src: string?, welcome: boolean? }

type Spot = { key: string, room: string, roomName: string, wall: boolean, accepts: { string }? }

--- Open spots for a Guild Hall level: floor spots first (room order), then wall spots.
local function spotsFor(gh: number): ({ Spot }, { Spot })
	local floor, wall = {}, {}
	for _, r in V4.RoomsFor(gh) do
		for i, acc in r.floor do
			table.insert(floor, { key = `{r.id}/f{i}`, room = r.id, roomName = r.name, wall = false, accepts = acc })
		end
		for i = 1, (r.wall or 0) do
			table.insert(wall, { key = `{r.id}/w{i}`, room = r.id, roomName = r.name, wall = true })
		end
	end
	return floor, wall
end

local function fits(inst: Inst, spot: Spot): boolean
	local p = V4.Get(inst.id)
	if not p then return false end
	if spot.wall then return p.category == "Wall" end
	return spot.accepts ~= nil and table.find(spot.accepts, p.category) ~= nil
end

--------------------------------------------------
-- TOTALS
--------------------------------------------------

local MULTIPLIER_KEYS: { [string]: boolean } = { rtDelayResist = true, collision = true }

local function orderedPlaced(gh: number, placement: { [string]: string }, instances: { [string]: Inst }): { { spot: Spot, inst: Inst } }
	local floor, wall = spotsFor(gh)
	local out = {}
	for _, list in { floor, wall } do
		for _, s in list do
			local u = placement[s.key]
			local inst = u and instances[u] or nil
			if inst then table.insert(out, { spot = s, inst = inst }) end
		end
	end
	return out
end

-- Legacy totals (block 1): what units get TODAY. Same logic as before the rebuild.
local function recomputeLegacy(gh: number, placement: { [string]: string }, instances: { [string]: Inst }): ({ [string]: number }, { [string]: string }, number)
	local cap = FurnitureData.CapFor(gh)
	local out: { [string]: number } = {}
	local status: { [string]: string } = {}
	local fam: { [string]: number } = {}
	local seen: { [string]: boolean } = {}
	local used = 0
	for _, e in orderedPlaced(gh, placement, instances) do
		local p = FurnitureData.Get(e.inst.id)
		local key = e.spot.key
		if not p then
			status[key] = "ok" -- v4-only piece (no legacy effect yet)
		elseif seen[p.id] or p.looksOnly then
			status[key] = if p.looksOnly then "ok" else "invalid"
		else
			seen[p.id] = true
			local famKey: string? = nil
			for k in p.effect do famKey = k break end
			local okFit = true
			if p.points > 0 then
				if used + p.points > cap then okFit = false end
				if famKey and (fam[famKey] or 0) + p.points > FurnitureData.FamilyCap then okFit = false end
			end
			if okFit then
				for k, v in p.effect do
					if MULTIPLIER_KEYS[k] then out[k] = (out[k] or 1) * v else out[k] = (out[k] or 0) + v end
				end
				if p.points > 0 then
					used += p.points
					if famKey then fam[famKey] = (fam[famKey] or 0) + p.points end
				end
				status[key] = "ok"
			else
				status[key] = "capped"
			end
		end
	end
	return out, status, used
end

-- V4 totals (rows 92, 101, 102, 107, 108). Step 1 (v5 build, 2026-11-16): the PLAYER side now drives
-- unit stats (BonusTable below -> FurnitureService.BonusFor). Enemy lines are computed only (step 2).
-- Order = placement order (floor spots in room order, then wall spots). Rules:
--   * total cap 8 x GH checked per PIECE (a piece that doesn't fit is capped whole, row 92);
--   * 40 points per kind checked per LINE in order (the line that would pass 40 is dropped);
--   * every bed counts, other pieces once per name (D5);
--   * threshold lines: +2 total, +1 per kind, player and enemy lines share kinds and the total (row 107);
--     Movement only from Agility Course pieces; Range only if the switch is on;
--   * forbidden / unknown kinds never apply (row 107 forbid list);
--   * fixed pieces (Stone Hearth, Herbal Rack, Padded Wall, Lucky Coin Shrine, Gilded Chest, War Table)
--     go to their own `fixed` bucket (old point price toward the cap, W-F default);
--   * per-kind totals are clamped to V4.SecondaryMax (row 102).
local FORBIDDEN: { [string]: boolean } = {}
for _, k in V4.ForbiddenKinds do FORBIDDEN[k] = true end
local FIXED_PRODUCT: { [string]: boolean } = { rtDelayResist = true, collisionTaken = true }

local function thresholdAllowed(kind: string, p: any): boolean
	if kind == "range" then return V4.Threshold.RangeEnabled == true end
	if not table.find(V4.Threshold.Kinds, kind) then return false end
	if kind == "movement" and p.type ~= V4.Threshold.MovementOnlyFrom then return false end
	return true
end

local function recomputeV4(gh: number, placement: { [string]: string }, instances: { [string]: Inst }): any
	local cap = V4.CapFor(gh)
	local player: { [string]: number } = {}
	local enemy: { [string]: number } = {}
	local fixed: { [string]: number } = {}
	local thr: { [string]: number } = {}
	local kindPts: { [string]: number } = {}
	local status: { [string]: string } = {}
	local lineStatus: { [string]: { string } } = {}
	local seen: { [string]: boolean } = {}
	local used, thrTotal = 0, 0
	for _, e in orderedPlaced(gh, placement, instances) do
		local inst, key = e.inst, e.spot.key
		local p = V4.Get(inst.id)
		if not p or inst.looks then
			status[key] = "ok"
		elseif seen[inst.id] and p.category ~= "Bed" then
			status[key] = "invalid"
		else
			seen[inst.id] = true
			local pts = 0
			if inst.fixed then
				local old = FurnitureData.Get(inst.id)
				pts = old and old.points or 0
			else
				for _, l in inst.lines do pts += l.points end
			end
			if used + pts > cap then
				status[key] = "capped"
			else
				used += pts
				status[key] = "ok"
				if inst.fixed then
					for k, v in p.fixed do fixed[k] = if FIXED_PRODUCT[k] then (fixed[k] or 1) * v else (fixed[k] or 0) + v end
				else
					local ls: { string } = {}
					for i, l in inst.lines do
						local st = "ok"
						if l.threshold then
							local tk = l.kind
							if not thresholdAllowed(tk, p) then
								st = "invalid"
							elseif thrTotal < V4.Threshold.TotalCap and (thr[tk] or 0) == 0 then
								thr[tk] = l.value
								thrTotal += 1
							else
								st = "capped"
							end
						elseif FORBIDDEN[l.kind] or not (if l.enemy then V4.Enemy.PointPrice[l.kind] else V4.PointPrice[l.kind]) then
							st = "invalid"
						else
							local kk = (if l.enemy then "enemy:" else "") .. l.kind
							local kcap = if l.enemy then V4.Enemy.KindCap else V4.KindCap
							if (kindPts[kk] or 0) + l.points <= kcap then
								kindPts[kk] = (kindPts[kk] or 0) + l.points
								local bucket = if l.enemy then enemy else player
								bucket[l.kind] = (bucket[l.kind] or 0) + l.value
							else
								st = "capped"
							end
						end
						ls[i] = st
					end
					lineStatus[inst.uid] = ls
				end
			end
		end
	end
	for k, v in player do
		local mx = V4.SecondaryMax[k]
		if type(mx) == "number" and v > mx then player[k] = mx end
	end
	for k, v in enemy do
		local mx = V4.Enemy.Max[k]
		if type(mx) == "number" and v > mx then enemy[k] = mx end
	end
	return { player = player, enemy = enemy, fixed = fixed, threshold = thr, points = used, cap = cap,
		status = status, lineStatus = lineStatus }
end

-- Step 1: the PLAYER-side V4 totals as the bonus table unit-stat readers use (unit.furnitureBonus):
--   STR..LUK flat | hp, mp flat Max HP / Max MP | attack (weapon damage), defense (armor defense) flat
--   precision, evasiveness (fraction, 0.005 = +0.5 pp) | skillPotency, itemDamage (fraction added)
--   healingOutput (x mult) | debuffResist, rtDelayResist, collision, fallTaken (x mult, < 1 = less taken)
--   collisionDealt, fallDealt (x mult) | healRecv, fortune, battleGold (fraction) | dispatchFee (gold)
--   movementRange, jump, force, stability, discoveryRadius, interactRange, itemRange (threshold +1)
local THRESHOLD_KEY: { [string]: string } = {
	movement = "movementRange", jump = "jump", force = "force", stability = "stability",
	discoveryRadius = "discoveryRadius", interactRange = "interactRange", itemRange = "itemRange",
}
local function bonusTable(t: any): { [string]: number }
	local out: { [string]: number } = {}
	local P: { [string]: number } = (t and t.player) or {}
	local F: { [string]: number } = (t and t.fixed) or {}
	local T: { [string]: number } = (t and t.threshold) or {}
	local function put(k: string, v: number?) if v and v ~= 0 then out[k] = v end end
	for _, s in { "STR", "AGI", "DEX", "INT", "VIT", "LUK" } do put(s, P[s]) end
	put("hp", P.maxHp)
	put("mp", P.maxMp)
	put("attack", P.attack)
	put("defense", P.defense)
	if P.precision then put("precision", P.precision / 100) end
	if P.evasion then put("evasiveness", P.evasion / 100) end
	if P.skillPotency then put("skillPotency", P.skillPotency / 100) end
	if P.itemDamage then put("itemDamage", P.itemDamage / 100) end
	if P.healingOutput then put("healingOutput", 1 + P.healingOutput / 100) end
	if P.debuffResist then put("debuffResist", 1 - P.debuffResist / 100) end
	if P.collisionDamage then put("collisionDealt", 1 + P.collisionDamage / 100) end
	if P.fallDamage then put("fallDealt", 1 + P.fallDamage / 100) end
	if P.fallResist then put("fallTaken", 1 - P.fallResist / 100) end
	local rt = (1 - (P.rtDelayResist or 0) / 100) * (F.rtDelayResist or 1)
	if math.abs(rt - 1) > 1e-9 then out.rtDelayResist = rt end
	local col = (1 - (P.collisionResist or 0) / 100) * (F.collisionTaken or 1)
	if math.abs(col - 1) > 1e-9 then out.collision = col end
	put("healRecv", F.healingReceived)
	put("fortune", F.fortune)
	put("battleGold", F.battleGold)
	put("dispatchFee", F.dispatchFee)
	for k, v in T do
		local key = THRESHOLD_KEY[k]
		if key and v > 0 then out[key] = v end -- enemy (-1) lines are step 2
	end
	return out
end

FurnitureTotals.SpotsFor = spotsFor
FurnitureTotals.Fits = fits
FurnitureTotals.RecomputeLegacy = recomputeLegacy
FurnitureTotals.RecomputeV4 = recomputeV4
FurnitureTotals.BonusTable = bonusTable

return FurnitureTotals
