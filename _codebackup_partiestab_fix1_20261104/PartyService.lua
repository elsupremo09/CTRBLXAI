--!strict
-- PartyService.lua
-- CTRBLXAI | Saved party storage (Parties tab, USER DECISION 2026-11-04; DB guild_facilities /
-- game_flow 4/10/27 superseded).
--
-- Up to 5 parties, created and deleted by the player. Each: id, name, motto, emblem key,
-- background key, created/edited dates, and up to 7 member units (7 = deployment ceiling,
-- not a required count). Member slot 1 is the LEADER (display only). A unit MAY belong to
-- more than one party. Parties keep their creation order.
--
-- OWNS: the saved party records only. The CALLER (GuildMenuService) validates unit
-- ownership and filters text (TextService) before calling in (ARC-001/SEC-001). No external
-- requires (DAT-003). Persisted via Export/Import in Save Key 3 (progression).
--
-- Old saves (A/B/C slots) load as parties 1-3 with their names and members (D1).
-- Party ids are short strings ("p1".."p9"); the old ids "A"/"B"/"C" are kept for migrated
-- parties so the sortie selection made in an old session still resolves.

local PartyService = {}

local MAX_PARTY_SIZE = 7
local MAX_PARTIES = 5
local MAX_NAME_LEN = 24   -- characters (utf8), not bytes
local MAX_MOTTO_LEN = 80
local MAX_KEY_LEN = 32
local LEGACY_SLOTS = table.freeze({ "A", "B", "C" })

export type Party = {
	id: string,
	name: string,
	motto: string,
	emblem: string?,
	background: string?,
	created: number,
	edited: number,
	members: { string },
}

-- parties[playerId] = ordered list of Party
local parties: { [string]: { Party } } = {}

local function now(): number
	return os.time()
end

-- Copy a member array (defensive — never hand out or store a shared reference).
local function copyMembers(src: any): { string }
	local out = {}
	if type(src) == "table" then
		local seen = {}
		for _, uid in ipairs(src) do
			if type(uid) == "string" and #uid <= 64 and not seen[uid] then
				seen[uid] = true
				table.insert(out, uid)
				if #out >= MAX_PARTY_SIZE then break end
			end
		end
	end
	return out
end

local function clampText(s: any, maxLen: number): string
	if type(s) ~= "string" or utf8.len(s) == nil then return "" end
	s = s:gsub("^%s+", ""):gsub("%s+$", "")
	s = s:gsub("[%c]", " ") -- no line breaks / control characters
	if (utf8.len(s) or 0) > maxLen then
		local cut = utf8.offset(s, maxLen + 1)
		if cut then s = s:sub(1, cut - 1) end
	end
	return s
end

local function cleanKey(k: any): string?
	if type(k) ~= "string" or #k == 0 or #k > MAX_KEY_LEN then return nil end
	if not k:match("^[%w_%-]+$") then return nil end
	return k
end

local function list(playerId: string): { Party }
	local p = parties[playerId]
	if not p then
		p = {}
		parties[playerId] = p
	end
	return p
end

local function find(playerId: string, id: any): (Party?, number?)
	if type(id) ~= "string" then return nil, nil end
	for i, rec in list(playerId) do
		if rec.id == id then return rec, i end
	end
	return nil, nil
end

-- Lowest unused "Party N" number (1-5) for the default name.
local function nextDefaultNumber(playerId: string): number
	local used: { [number]: boolean } = {}
	for _, rec in list(playerId) do
		local n = tonumber(rec.name:match("^Party (%d)$"))
		if n then used[n] = true end
	end
	for n = 1, MAX_PARTIES do
		if not used[n] then return n end
	end
	return #list(playerId) + 1
end

local function newId(playerId: string): string
	local taken: { [string]: boolean } = {}
	for _, rec in list(playerId) do taken[rec.id] = true end
	for n = 1, 99 do
		local id = `p{n}`
		if not taken[id] then return id end
	end
	return `p{now()}`
end

local function snapshot(rec: Party): any
	return {
		id = rec.id, slot = rec.id, -- 'slot' kept for older client code
		name = rec.name, motto = rec.motto,
		emblem = rec.emblem, background = rec.background,
		created = rec.created, edited = rec.edited,
		members = copyMembers(rec.members),
	}
end

PartyService.MAX_PARTY_SIZE = MAX_PARTY_SIZE
PartyService.MAX_PARTIES = MAX_PARTIES
PartyService.MAX_NAME_LEN = MAX_NAME_LEN
PartyService.MAX_MOTTO_LEN = MAX_MOTTO_LEN

-- Read: every party in creation order (fresh copies).
function PartyService.GetParties(playerId: string): { any }
	local out = {}
	for _, rec in list(playerId) do table.insert(out, snapshot(rec)) end
	return out
end

function PartyService.Exists(playerId: string, id: any): boolean
	return (find(playerId, id)) ~= nil
end

function PartyService.Count(playerId: string): number
	return #list(playerId)
end

-- Create an empty "Party N". Returns the new id, or nil + reason at the cap.
function PartyService.Create(playerId: string): (string?, string?)
	local p = list(playerId)
	if #p >= MAX_PARTIES then return nil, `You can have up to {MAX_PARTIES} parties` end
	local t = now()
	local rec: Party = {
		id = newId(playerId), name = `Party {nextDefaultNumber(playerId)}`, motto = "",
		emblem = nil, background = nil, created = t, edited = t, members = {},
	}
	table.insert(p, rec)
	return rec.id, nil
end

-- Delete a party. Never touches units. The last party can't be deleted (D-rule).
function PartyService.Delete(playerId: string, id: any): (boolean, string?)
	local p = list(playerId)
	local _, i = find(playerId, id)
	if not i then return false, "Unknown party" end
	if #p <= 1 then return false, "You need at least one party" end
	table.remove(p, i)
	return true, nil
end

-- Name (already filtered by the caller). Empty falls back to the default name.
function PartyService.SetName(playerId: string, id: any, name: any): (boolean, string?)
	local rec = find(playerId, id)
	if not rec then return false, "Unknown party" end
	local s = clampText(name, MAX_NAME_LEN)
	if #s == 0 then s = `Party {nextDefaultNumber(playerId)}` end
	rec.name = s
	rec.edited = now()
	return true, nil
end

-- Motto (already filtered by the caller). Empty is allowed.
function PartyService.SetMotto(playerId: string, id: any, motto: any): (boolean, string?)
	local rec = find(playerId, id)
	if not rec then return false, "Unknown party" end
	rec.motto = clampText(motto, MAX_MOTTO_LEN)
	rec.edited = now()
	return true, nil
end

-- Emblem / background keys (the caller checks the key exists in PartyArtData).
function PartyService.SetArt(playerId: string, id: any, field: string, key: any): (boolean, string?)
	local rec = find(playerId, id)
	if not rec then return false, "Unknown party" end
	local k = if key == nil then nil else cleanKey(key)
	if key ~= nil and not k then return false, "Invalid choice" end
	if field == "emblem" then
		rec.emblem = k
	elseif field == "background" then
		rec.background = k
	else
		return false, "Invalid field"
	end
	rec.edited = now()
	return true, nil
end

-- Replace members (ownership-validated by the caller). Slot 1 = leader.
function PartyService.SetMembers(playerId: string, id: any, unitIds: any): (boolean, string?)
	local rec = find(playerId, id)
	if not rec then return false, "Unknown party" end
	if type(unitIds) ~= "table" then return false, "Invalid members" end
	rec.members = copyMembers(unitIds)
	rec.edited = now()
	return true, nil
end

-- Drop any member id not in ownedSet (a dismissed unit silently leaves every party).
function PartyService.PruneToOwned(playerId: string, ownedSet: { [string]: boolean })
	local p = parties[playerId]
	if not p then return end
	for _, rec in p do
		local kept = {}
		for _, uid in ipairs(rec.members) do
			if ownedSet[uid] then table.insert(kept, uid) end
		end
		rec.members = kept
	end
end

function PartyService.AllEmpty(playerId: string): boolean
	for _, rec in list(playerId) do
		if #rec.members > 0 then return false end
	end
	return true
end

-- First run: with no party at all, create Party 1; if every party is empty, fill the first
-- with the given unit ids. Returns the seeded id or nil. Never overwrites a built party.
function PartyService.AutoSeedIfEmpty(playerId: string, unitIds: any): string?
	local p = list(playerId)
	if #p == 0 then PartyService.Create(playerId) end
	if not PartyService.AllEmpty(playerId) then return nil end
	if type(unitIds) ~= "table" then return nil end
	local first = p[1]
	first.members = copyMembers(unitIds)
	if #first.members == 0 then return nil end
	first.edited = now()
	return first.id
end

-- Ordered ids (for the sortie default: first non-empty party).
function PartyService.GetIds(playerId: string): { string }
	local out = {}
	for _, rec in list(playerId) do table.insert(out, rec.id) end
	return out
end

-- Members of one party (defensive copy). Used by the deployment filter at sortie.
function PartyService.GetMembers(playerId: string, id: any): { string }
	local rec = find(playerId, id)
	if not rec then return {} end
	return copyMembers(rec.members)
end

--------------------------------------------------
-- SAVE (Key 3 progression)
-- v2 format: { v = 2, list = { { i = id, n = name, o = motto, e = emblem, b = background,
--              c = created, d = edited, m = { unitId } } } }
-- v1 (old) format: { A = { n, l, m }, B = ..., C = ... } -> parties 1-3 (D1).
--------------------------------------------------

function PartyService.Export(playerId: string): any
	local out = {}
	for _, rec in list(playerId) do
		table.insert(out, {
			i = rec.id, n = rec.name,
			o = if rec.motto ~= "" then rec.motto else nil,
			e = rec.emblem, b = rec.background,
			c = rec.created, d = rec.edited,
			m = copyMembers(rec.members),
		})
	end
	return { v = 2, list = out }
end

function PartyService.Import(playerId: string, data: any)
	local p: { Party } = {}
	parties[playerId] = p
	if type(data) ~= "table" then return end
	local t = now()
	if data.v == 2 and type(data.list) == "table" then
		local seenIds: { [string]: boolean } = {}
		for _, r in ipairs(data.list) do
			if #p >= MAX_PARTIES then break end
			if type(r) == "table" and type(r.i) == "string" and #r.i <= 16 and not seenIds[r.i] then
				seenIds[r.i] = true
				local name = clampText(r.n, MAX_NAME_LEN)
				table.insert(p, {
					id = r.i,
					name = if #name > 0 then name else `Party {#p + 1}`,
					motto = clampText(r.o, MAX_MOTTO_LEN),
					emblem = cleanKey(r.e), background = cleanKey(r.b),
					created = if type(r.c) == "number" then r.c else t,
					edited = if type(r.d) == "number" then r.d else t,
					members = copyMembers(r.m),
				})
			end
		end
		return
	end
	-- Legacy A/B/C: always 3 parties, ids kept, logo ignored (never used).
	for i, s in LEGACY_SLOTS do
		local rec = data[s]
		local name = type(rec) == "table" and clampText(rec.n, MAX_NAME_LEN) or ""
		table.insert(p, {
			id = s,
			name = if #name > 0 then name else `Party {i}`,
			motto = "", emblem = nil, background = nil,
			created = t, edited = t,
			members = type(rec) == "table" and copyMembers(rec.m) or {},
		})
	end
end

function PartyService.ClearPlayer(playerId: string)
	parties[playerId] = nil
end

return PartyService
