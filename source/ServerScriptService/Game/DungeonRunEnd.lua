--!strict
-- DungeonRunEnd.lua — split out of DungeonService.lua 2026-11-16 (furniture v5 / endless plan step B).
-- Run end: what each exit keeps (OUTCOME_KEEP, project_rules 264), ComputeOutcome, EndRun, PayPending.
-- Code moved word for word; behaviour unchanged. DungeonService binds its state + helpers (Bind) and
-- re-exports every function, so all callers still use DungeonService.EndRun etc. No require of
-- DungeonService (no cycle).

local DungeonRules = require(script.Parent:WaitForChild("DungeonRules"))
local DungeonLoadout = require(script.Parent:WaitForChild("DungeonLoadout"))
local DungeonSilver = require(script.Parent:WaitForChild("DungeonSilver"))
local DungeonBag = require(script.Parent:WaitForChild("DungeonBag"))
local DungeonCourier = require(script.Parent:WaitForChild("DungeonCourier"))
local DungeonFurniture = require(script.Parent:WaitForChild("DungeonFurniture"))
local D = DungeonRules.Data
local WIPEOUT_GOLD_KEEP = D.WipeoutGoldKeep

local M = {}

-- project_rules 264: what each way of ending a run keeps. EXP is always kept.
local OUTCOME_KEEP = table.freeze({
	Boss        = table.freeze({ gold = 1.0, normalMats = true, eliteMats = true, bossMats = true, gear = true, cards = true }),
	EscapeNode  = table.freeze({ gold = 1.0, normalMats = true, eliteMats = true, bossMats = true, gear = true, cards = true }),
	EarlyEscape = table.freeze({ gold = D.EarlyEscapeGoldKeep, normalMats = true, eliteMats = false, bossMats = false, gear = false, cards = false }),
	Wipeout     = table.freeze({ gold = WIPEOUT_GOLD_KEEP, normalMats = false, eliteMats = false, bossMats = false, gear = false, cards = false }),
})
M.OUTCOME_KEEP = OUTCOME_KEEP

-- Bound by DungeonService (step B): its state + helpers, read at call time.
local C: any = nil
local DungeonService: any = nil -- the service table; calls go through it exactly as before the split
local function stateOf(playerId: string): any return C.stateOf(playerId) end
local function copyBag(b: any): any return C.copyBag(b) end
local function nodeById(map: any, id: string): any return C.nodeById(map, id) end
local function effType(n: any): string? return C.effType(n) end
local function persist() C.persist() end
function M.Bind(ctx: any) C = ctx DungeonService = ctx.svc end

-- Build step 4 (2026-11-13). Optional / nil-safe; Main wires them via DungeonService.SetPayer / SetRunEndedHook.
local _payer: ((any) -> ())? = nil                       -- pays an ended run's kept loot to the player
local _onRunEnded: ((any) -> ())? = nil                  -- normal rules resume (KO -> 1 HP) for the party
function M.SetPayer(fn: ((any) -> ())?) _payer = fn end
function M.SetRunEndedHook(fn: ((any) -> ())?) _onRunEnded = fn end

--------------------------------------------------
-- RUN END (pure keep/lose; no rewards handed out yet — steps 3-4)
--------------------------------------------------

local function splitMap(t: { [string]: number }, keep: boolean): ({ [string]: number }, { [string]: number })
	local kept: { [string]: number }, lost: { [string]: number } = {}, {}
	for k, v in t do
		if keep then kept[k] = v else lost[k] = v end
	end
	return kept, lost
end

--- Pure: what a bag keeps / loses for an outcome kind (Boss | EscapeNode | EarlyEscape | Wipeout).
function M.ComputeOutcome(bag: any, kind: string): any
	local rule = OUTCOME_KEEP[kind]
	if not rule then return nil end
	local b = copyBag(bag)
	local keptGold = math.floor(b.gold * rule.gold)
	local kept = { gold = keptGold, unitXp = b.unitXp }
	local lost: any = { gold = b.gold - keptGold, unitXp = {} }
	kept.normalMats, lost.normalMats = splitMap(b.normalMats, rule.normalMats)
	kept.eliteMats, lost.eliteMats = splitMap(b.eliteMats, rule.eliteMats)
	kept.bossMats, lost.bossMats = splitMap(b.bossMats, rule.bossMats)
	kept.cards, lost.cards = splitMap(b.cards, rule.cards)
	if rule.gear then
		kept.gear, lost.gear = b.gear, {}
		kept.gearItems, lost.gearItems = b.gearItems, {}
	else
		kept.gear, lost.gear = {}, b.gear
		kept.gearItems, lost.gearItems = {}, b.gearItems
	end
	return { kind = kind, kept = kept, lost = lost }
end

--- End the active run. Boss needs the boss cleared; EscapeNode needs to stand on a Rest room
--- (Escape rooms removed 2026-11-13 11:36 PM; an old saved Escape room still counts); EarlyEscape and Wipeout are always allowed. Clears the run (unlocks the party).
function M.EndRun(playerId: string, kind: any): (boolean, any)
	local s = stateOf(playerId)
	local run = s.run
	if not run then return false, "No dungeon run in progress" end
	if type(kind) ~= "string" or not OUTCOME_KEEP[kind] then return false, "Invalid outcome" end
	if (kind == "EscapeNode" or kind == "EarlyEscape") and DungeonBag.Waiting(run) then return false, "You can't go there" end -- rule 279: the run waits for the full-Bag pick
	if kind == "Boss" and not (run.at == "boss" and run.cleared.boss) then
		return false, "The boss has not been beaten"
	end
	if kind == "EscapeNode" then
		-- USER RULING 2026-11-13 10:08 PM: leaving from a Rest room is a full escape too (rule 267).
		local n = run.at and nodeById(run.map, run.at) or nil
		if not n or (effType(n) ~= "Rest" and n.type ~= "Escape") then return false, "Not on a Rest room" end -- a "?" that became Rest counts (2026-11-15); "Escape" = old saved maps only
	end
	-- EV-12: an owed Smith's Wager gear comes home on any full-loot exit; lost on early escape / wipeout.
	if run.smithOwed and (kind == "Boss" or kind == "EscapeNode") and DungeonService.DeliverSmith then DungeonService.DeliverSmith(playerId) end
	local outcome = DungeonService.ComputeOutcome(run.bag, kind)
	DungeonLoadout.OnRunEnd(run, outcome, OUTCOME_KEEP[kind]) -- step 3: found items on units follow the loot rule
	DungeonSilver.KeepBought(run, outcome) -- no-op since 2026-11-16 7:22 PM: bought items follow the loot rule (rule 264)
	local heldLost = if kind == "Boss" or kind == "EscapeNode" then 0 else #(run.bagHeld or {}) -- W3: counted before held loot comes home
	local place = function(cid: string, ch: number) return DungeonLoadout.PlaceOpened(run, cid, ch) end
	DungeonBag.OnRunEnd(run, outcome, kind, place); DungeonCourier.OnRunEnd(run, outcome, place); DungeonFurniture.OnRunEnd(run, outcome, kind) -- steps 4-5: held loot on a full-loot exit (W1 charges kept), EV-17 sent items always
	outcome.card = table.clone(run.card)
	outcome.party = table.clone(run.party)
	outcome.battles = run.battles
	outcome.relicCount = #(run.relics or {}) -- step 8: relics are run-only and fade here
	outcome.silverLost, outcome.heldLost = DungeonSilver.Get(run), heldLost -- rules 278/279: unspent silver + held loot are lost
	s.run = nil
	-- The result is saved as pending, then paid out once (build step 4, DungeonService.PayPending).
	s.pending = outcome
	print(`[DungeonService] Run ended | {kind} | {run.card.id} | battles {run.battles} | gold kept {outcome.kept.gold}/{run.bag.gold} | silver lost {outcome.silverLost}`)
	if _onRunEnded then
		local okH, errH = pcall(_onRunEnded, outcome.party)
		if not okH then warn("[DungeonService] run-ended hook failed: " .. tostring(errH)) end
	end
	DungeonService.PayPending(playerId) -- pays now when the payer is wired; otherwise stays pending
	persist()
	return true, outcome
end

--- Pay an ended run's kept loot exactly once (build step 4, project_rules 264). The pending result
--- is taken BEFORE paying, so a second call (or a reload after the save) can't pay it again.
--- Unit EXP is not paid here: battle EXP is granted when each battle ends and is always kept.
function M.PayPending(playerId: string): any
	local s = stateOf(playerId)
	if not s.pending or not _payer then return nil end
	local p = s.pending
	s.pending = nil
	local ok, err = pcall(_payer, p)
	if not ok then warn("[DungeonService] payout failed (" .. tostring(p.kind) .. "): " .. tostring(err)) end
	print(`[DungeonService] Paid out | {tostring(p.kind)} | gold {p.kept and p.kept.gold or 0} | gear {p.kept and #(p.kept.gear or {}) or 0}`)
	return p
end

return M
