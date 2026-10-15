--!strict
-- PartyService.lua
-- CTRBLXAI | Base Building (Slice 8) — SAVED PARTY STORAGE.
--
-- game_flow id 4 / 10 / 27 (Designer-owned design, read-only): the HQ keeps saved
-- parties "Party A/B/C", each with a name, a logo (reserved; name-only for now by
-- user decision 2026-10-14), and UP TO 7 member units (7 = the deployment ceiling,
-- NOT a required count — a 3-unit party is valid). Activity-agnostic (user decision
-- 2026-10-14): any activity (battle deploy, and later dungeon/raid/PvP) asks for a
-- party and applies its OWN cap/rules; this module just stores the selection. A unit
-- MAY belong to more than one party (locked design, confirmed 2026-10-14).
--
-- OWNS: the saved party records only. MUST NOT OWN: the roster/unit store, currency,
-- deployment rules, or dispatch availability. The CALLER (GuildMenuService) validates
-- unit ownership against the live roster before SetMembers (ARC-001/SEC-001); this
-- module is a pure data domain (DAT-003) with no external requires, and enforces slot
-- validity, de-duplication, and the hard <=7 cap. Persisted via Export/Import folded
-- into Save Key 3 (progression) exactly like DispatchService — no second DataStore.

local PartyService = {}

local MAX_PARTY_SIZE = 7
local SLOTS = table.freeze({ "A", "B", "C" })
local DEFAULT_NAMES = table.freeze({ A = "Party A", B = "Party B", C = "Party C" })
local MAX_NAME_LEN = 24

-- parties[playerId] = { A = { name, logoId, members = { unitId } }, B = ..., C = ... }
local parties: { [string]: { [string]: any } } = {}

local function isSlot(slot: any): boolean
	return slot == "A" or slot == "B" or slot == "C"
end

local function blank(slot: string): any
	return { name = DEFAULT_NAMES[slot] or ("Party " .. slot), logoId = nil, members = {} }
end

local function ensure(playerId: string): { [string]: any }
	local p = parties[playerId]
	if not p then
		p = {}
		for _, s in SLOTS do p[s] = blank(s) end
		parties[playerId] = p
	end
	return p
end

-- Copy a member array (defensive — never hand out or store a shared reference).
local function copyMembers(src: any): { string }
	local out = {}
	if type(src) == "table" then
		local seen = {}
		for _, uid in ipairs(src) do
			if type(uid) == "string" and not seen[uid] then
				seen[uid] = true
				table.insert(out, uid)
				if #out >= MAX_PARTY_SIZE then break end
			end
		end
	end
	return out
end

PartyService.MAX_PARTY_SIZE = MAX_PARTY_SIZE
PartyService.SLOTS = SLOTS

-- Read: the three parties as a plain list (fresh copies — safe for the caller to
-- annotate and send). Order follows SLOTS (A, B, C).
function PartyService.GetParties(playerId: string): { any }
	local p = ensure(playerId)
	local out = {}
	for _, s in SLOTS do
		local rec = p[s]
		table.insert(out, { slot = s, name = rec.name, logoId = rec.logoId, members = copyMembers(rec.members) })
	end
	return out
end

-- Rename a slot. Trimmed, length-capped; empty falls back to the default name.
function PartyService.SetName(playerId: string, slot: string, name: any): (boolean, string?)
	if not isSlot(slot) then return false, "Invalid party slot" end
	local p = ensure(playerId)
	local s = (type(name) == "string") and name or ""
	s = s:gsub("^%s+", ""):gsub("%s+$", "")
	if #s == 0 then s = DEFAULT_NAMES[slot] end
	if utf8.len(s) == nil then s = DEFAULT_NAMES[slot] end  -- reject malformed strings
	if #s > MAX_NAME_LEN then s = s:sub(1, MAX_NAME_LEN) end
	p[slot].name = s
	return true, nil
end

-- Replace a slot's members. The caller passes an ownership-validated id list; this
-- de-duplicates and enforces the hard <=7 cap.
function PartyService.SetMembers(playerId: string, slot: string, unitIds: any): (boolean, string?)
	if not isSlot(slot) then return false, "Invalid party slot" end
	if type(unitIds) ~= "table" then return false, "Invalid members" end
	local p = ensure(playerId)
	p[slot].members = copyMembers(unitIds)
	return true, nil
end

-- Reserved for the later logo art-pass (name-only for now).
function PartyService.SetLogo(playerId: string, slot: string, logoId: any): (boolean, string?)
	if not isSlot(slot) then return false, "Invalid party slot" end
	local p = ensure(playerId)
	if type(logoId) == "string" or type(logoId) == "number" then
		p[slot].logoId = logoId
	else
		p[slot].logoId = nil
	end
	return true, nil
end

-- Drop any member id not in ownedSet (a unit sold/lost since the last edit silently
-- leaves every party). ownedSet = { [unitId] = true }.
function PartyService.PruneToOwned(playerId: string, ownedSet: { [string]: boolean })
	local p = parties[playerId]
	if not p then return end
	for _, s in SLOTS do
		local kept = {}
		for _, uid in ipairs(p[s].members) do
			if ownedSet[uid] then table.insert(kept, uid) end
		end
		p[s].members = kept
	end
end

-- Is every slot empty (no members)? Decides the first-run auto-seed.
function PartyService.AllEmpty(playerId: string): boolean
	local p = ensure(playerId)
	for _, s in SLOTS do
		if #p[s].members > 0 then return false end
	end
	return true
end

-- First-run convenience: if the player has NO populated party yet, fill Party A with
-- the given unit ids (capped <=7 via copyMembers). Returns the seeded slot, or nil if a
-- party already existed (never overwrites a player-built party) or no ids were supplied.
-- Caller passes the current available (non-dispatched) owned unit ids.
function PartyService.AutoSeedIfEmpty(playerId: string, unitIds: any): string?
	if not PartyService.AllEmpty(playerId) then return nil end
	if type(unitIds) ~= "table" then return nil end
	local p = ensure(playerId)
	p["A"].members = copyMembers(unitIds)
	if #p["A"].members == 0 then return nil end
	return "A"
end

-- Members of one slot (defensive copy). Used by the deployment filter at sortie.
function PartyService.GetMembers(playerId: string, slot: string): { string }
	if not isSlot(slot) then return {} end
	local p = ensure(playerId)
	return copyMembers(p[slot].members)
end

-- SAVE (Key 3 progression). Compact per slot: { n = name, l = logoId, m = { unitId } }.
function PartyService.Export(playerId: string): any
	local p = ensure(playerId)
	local out = {}
	for _, s in SLOTS do
		out[s] = { n = p[s].name, l = p[s].logoId, m = copyMembers(p[s].members) }
	end
	return out
end

function PartyService.Import(playerId: string, data: any)
	local p = {}
	for _, s in SLOTS do p[s] = blank(s) end
	parties[playerId] = p
	if type(data) ~= "table" then return end
	for _, s in SLOTS do
		local rec = data[s]
		if type(rec) == "table" then
			if type(rec.n) == "string" and #rec.n > 0 then
				p[s].name = (#rec.n > MAX_NAME_LEN) and rec.n:sub(1, MAX_NAME_LEN) or rec.n
			end
			if type(rec.l) == "string" or type(rec.l) == "number" then p[s].logoId = rec.l end
			p[s].members = copyMembers(rec.m)
		end
	end
end

function PartyService.ClearPlayer(playerId: string)
	parties[playerId] = nil
end

return PartyService
