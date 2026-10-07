--!strict
-- GuildService.lua
-- CTRBLXAI | Slice 6 — Base Management (Batch 1 of 3)
--
-- OWNS (per service_boundaries 'Guild Service'):
--   Account-wide Guild level and Guild XP accrual, unlock gating.
--
-- READS:
--   Completed battles/quests, Guild XP rules (loot_progression), content level
--   for the trivial-reduction bands.
--
-- WRITES:
--   Guild XP delta, Guild level, unlock state  —  serialized into the existing
--   SaveService Key 3 (Progression + guild + unlocks) via Export/Import. This
--   module keeps the authoritative in-memory copy; it does NOT open its own
--   DataStore (save_data_contract: 3 keys only).
--
-- MUST NOT OWN (locked exclusions, loot_progression id 76):
--   Unit combat stats, loot rarity, Expedition Fortune. This service only
--   REPORTS level-ups and what unlocked. It never mutates a unit, an item, or
--   a Fortune value.
--
-- PRIMARY INTERFACE:
--   AwardGuildXp(playerId, contentType, contentLevel, optionalBonusXp?)
--   GetUnlocks(playerId)
--   GetGuildLevel(playerId)
--
-- FAILURE BOUNDARY:
--   Guild XP is NEVER per-kill. Trivial content is reduced via the shared
--   unit-XP overleveled gap bands. No stat/loot side effect ever.
--
-- ─────────────────────────────────────────────────────────────────────────
-- LOCKED DATA — copied verbatim from CTRBLXAI.db. Do NOT invent or tune here.
-- The design DB is the single source of truth; it is read-only to this agent.
-- These constants mirror the DB because the DB is not queryable at runtime.
-- ─────────────────────────────────────────────────────────────────────────
--
--   loot_progression id=74 (Guild XP, Locked 2026-10-05):
--     Normal battle = 100, Quest = 250, Elite/Boss battle = 200.
--     Optional objectives may add bounded XP. NOT per enemy kill.
--
--   loot_progression id=80 (Low-level farming, Locked 2026-10-05):
--     Trivial-content reduction reuses the unit-XP overleveled bands by the
--     (Guild Level − content level) gap:
--       gap <= 5  -> x1.00 (full)
--       gap 6-10  -> x0.75 (reduced)   [unit_progression Level Scaling id=56]
--       gap 11-15 -> x0.50
--       gap 16-20 -> x0.25
--       gap 21+   -> x0.10
--
-- GUILD LEVEL CURVE + CAP (LOCKED 2026-10-05, loot_progression):
--   Guild Level Curve: "Guild XP to next level = 1,000 + (Guild Level x 500)".
--     Examples: L1->2 = 1,500; L2->3 = 2,000; L5->6 = 3,500; L10->11 = 6,000.
--   Guild Level Cap: "Guild level cap = 30 at launch".
--   Both read verbatim from loot_progression (Guild Level Curve / Guild Level
--   Cap rows). This service now computes Guild Level from accumulated Guild XP
--   using this built-in locked curve by DEFAULT (no external injection needed)
--   and clamps at level 30. AwardGuildXp advances the level automatically.
--   SetLevelCurve still works as an OVERRIDE if a Designer supplies a different
--   curve; absent an override, the locked curve above is the default behavior.
--   SetGuildLevel remains available for authored/migration paths. The constants
--   below are the single source of these numbers — do not scatter or re-tune.

local GuildService = {}

--------------------------------------------------
-- LOCKED CONSTANTS (mirror of DB — see header)
--------------------------------------------------

-- loot_progression id=74
local GUILD_XP_BY_CONTENT = table.freeze({
	Normal = 100,
	Quest  = 250,
	Elite  = 200,
	Boss   = 200,
})

-- loot_progression id=80 / unit_progression Level Scaling ids 55-59
-- Band lookup by (Guild Level − content level) gap. Trivial content only.
-- Underleveled (negative gap) gets no Guild-XP bonus — Guild XP is a flat
-- completion value, so we clamp the multiplier at x1.0 for gap <= 5 (incl.
-- negative gaps). This matches "no bonus gold/XP for underleveled content".
local function trivialMultiplier(gap: number): number
	if gap <= 5 then
		return 1.00
	elseif gap <= 10 then
		return 0.75
	elseif gap <= 15 then
		return 0.50
	elseif gap <= 20 then
		return 0.25
	else
		return 0.10
	end
end

local DEFAULT_GUILD_LEVEL = 1

-- Guild Level curve + cap (loot_progression, LOCKED 2026-10-05). These are the
-- single source of these numbers (read verbatim from the DB). guildXpToNext is
-- the XP required to go from `level` to `level + 1`.
local GUILD_LEVEL_CAP = 30                      -- loot_progression 'Guild Level Cap'
local function guildXpToNext(level: number): number
	-- loot_progression 'Guild Level Curve': Guild XP to next = 1,000 + (Guild Level x 500).
	return 1000 + (level * 500)
end

--------------------------------------------------
-- STATE  (authoritative in-memory; mirrored into SaveService Key 3)
-- guildState[playerId] = { xp = n, level = n, unlocks = { [string]=true } }
--------------------------------------------------

local guildState: { [string]: { xp: number, level: number, unlocks: { [string]: boolean } } } = {}

-- Optional locked curve injection (nil until a Designer-locked curve exists).
-- Signature: function(totalXp: number) -> level: number
local _levelCurve: ((number) -> number)? = nil

function GuildService.SetLevelCurve(fn: ((number) -> number)?)
	_levelCurve = fn
end

--------------------------------------------------
-- PLAYER LIFECYCLE
--------------------------------------------------

function GuildService.InitPlayer(playerId: string)
	if not guildState[playerId] then
		guildState[playerId] = {
			xp = 0,
			level = DEFAULT_GUILD_LEVEL,
			unlocks = {},
		}
	end
end

local function stateOf(playerId: string)
	GuildService.InitPlayer(playerId)
	return guildState[playerId]
end

--------------------------------------------------
-- PRIMARY INTERFACE: AwardGuildXp
--
-- contentType: "Normal" | "Quest" | "Elite" | "Boss"
-- contentLevel: recommended/map level of the completed content (number)
-- optionalBonusXp: bounded extra XP from optional objectives (number, >= 0).
--                  Caller is responsible for bounding it (loot_progression
--                  id=74 "Optional objectives may add bounded XP"). We still
--                  clamp to >= 0 here as a safety guard.
--
-- Returns: {
--   awarded      = number (XP actually added, after trivial reduction),
--   base         = number (base content XP before reduction),
--   multiplier   = number (trivial-content band applied),
--   totalXp      = number (new running total),
--   level        = number (current stored level),
--   leveledUp    = boolean (true only if a locked curve advanced the level),
--   newUnlocks   = { string } (unlock keys that flipped on this award, if any)
-- }
--
-- NEVER per-kill: this is called once on completion, with a content TYPE —
-- there is no code path that takes an enemy or a kill count.
--------------------------------------------------

function GuildService.AwardGuildXp(playerId: string, contentType: string, contentLevel: number, optionalBonusXp: number?)
	assert(type(playerId) == "string", "GuildService.AwardGuildXp: playerId required")

	local base = GUILD_XP_BY_CONTENT[contentType]
	if not base then
		warn(`[GuildService] Unknown contentType '{tostring(contentType)}' — no Guild XP awarded`)
		return {
			awarded = 0, base = 0, multiplier = 0,
			totalXp = stateOf(playerId).xp, level = stateOf(playerId).level,
			leveledUp = false, newUnlocks = {},
		}
	end

	local state = stateOf(playerId)

	-- Trivial-content reduction: gap = Guild Level − content level.
	local lvl = type(contentLevel) == "number" and contentLevel or 0
	local gap = state.level - lvl
	local mult = trivialMultiplier(gap)

	-- Bounded optional objective XP (safety clamp; caller bounds the design cap).
	local bonus = math.max(0, optionalBonusXp or 0)

	-- Reduction applies to the completion value. Optional-objective XP is also
	-- reduced by the same band so trivial content cannot be farmed via objectives.
	local awarded = math.floor((base + bonus) * mult)

	local prevLevel = state.level
	state.xp = state.xp + awarded

	-- Level advancement. By DEFAULT we use the built-in LOCKED curve
	-- (guildXpToNext = 1,000 + level x 500), consuming XP thresholds and
	-- clamping at the LOCKED cap (30). If a Designer supplies an override via
	-- SetLevelCurve, that total-XP -> level mapping takes precedence instead.
	local leveledUp = false
	if _levelCurve then
		-- OVERRIDE path: external curve maps running total XP to a level.
		local newLevel = _levelCurve(state.xp)
		if type(newLevel) == "number" and newLevel > state.level then
			state.level = math.min(math.floor(newLevel), GUILD_LEVEL_CAP)
			leveledUp = true
		end
	else
		-- DEFAULT path: built-in locked curve. Spend XP against the per-level
		-- threshold, raising the level one step at a time, clamped at the cap.
		while state.level < GUILD_LEVEL_CAP do
			local need = guildXpToNext(state.level)
			if state.xp < need then
				break
			end
			state.xp -= need
			state.level += 1
			leveledUp = true
		end
		-- At cap: stop accruing overflow XP (hold at 0 toward "next").
		if state.level >= GUILD_LEVEL_CAP then
			state.level = GUILD_LEVEL_CAP
			state.xp = 0
		end
	end

	-- Record any unlocks that flipped on this level change. Unlock gating is a
	-- report of WHAT unlocked; this service does not apply any gameplay effect.
	local newUnlocks = {}
	if leveledUp then
		newUnlocks = GuildService._refreshUnlocks(playerId)
	end

	print(string.format(
		"[GuildService] %s +%d Guild XP (%s L%d, base %d x%.2f gap %d) -> total %d, level %d%s",
		playerId, awarded, tostring(contentType), lvl, base, mult, gap,
		state.xp, state.level, leveledUp and (" (LEVEL UP from " .. prevLevel .. ")") or ""
	))

	return {
		awarded = awarded,
		base = base,
		multiplier = mult,
		totalXp = state.xp,
		level = state.level,
		leveledUp = leveledUp,
		newUnlocks = newUnlocks,
	}
end

--------------------------------------------------
-- UNLOCK STATE
--
-- Unlock gating reports which account-wide gates are open at the current Guild
-- level. Per loot_progression id=75, Guild Level gates "quest tiers, expedition
-- access, merchants, recruitment, blacksmithing, facilities, and content
-- breadth". The CONTENT of each gate (which quest tiers, which facilities) is
-- owned by those systems; GuildService only tracks the open/closed flags keyed
-- by a stable string. Facility purchasing itself is Slice 8 (guild_facilities).
--
-- We expose SetUnlock so an authored/Designer path can declare a gate open at a
-- given Guild level without this service inventing an unlock schedule (none is
-- locked in the DB for Guild LEVEL -> gate mapping as of 2026-10-05).
--------------------------------------------------

function GuildService.SetUnlock(playerId: string, unlockKey: string, isOpen: boolean)
	local state = stateOf(playerId)
	state.unlocks[unlockKey] = isOpen and true or nil
end

-- Internal: recompute unlock flags from the level curve hook if one is wired.
-- Default: no-op (returns empty list) because no locked level->gate map exists.
function GuildService._refreshUnlocks(_playerId: string): { string }
	return {}
end

function GuildService.GetUnlocks(playerId: string): { [string]: boolean }
	local state = stateOf(playerId)
	-- Return a shallow copy so callers cannot mutate authoritative state.
	local out = {}
	for k, v in state.unlocks do
		out[k] = v
	end
	return out
end

function GuildService.IsUnlocked(playerId: string, unlockKey: string): boolean
	return stateOf(playerId).unlocks[unlockKey] == true
end

--------------------------------------------------
-- PRIMARY INTERFACE: GetGuildLevel
--------------------------------------------------

function GuildService.GetGuildLevel(playerId: string): number
	return stateOf(playerId).level
end

function GuildService.GetGuildXp(playerId: string): number
	return stateOf(playerId).xp
end

-- Authored/Designer path to set the Guild level directly (e.g. when a locked
-- curve or a migration determines it). Guarded to forward direction only is NOT
-- enforced here — a migration may legitimately correct a level downward.
function GuildService.SetGuildLevel(playerId: string, level: number)
	assert(type(level) == "number" and level >= 1, "GuildService.SetGuildLevel: level must be >= 1")
	-- Clamp to the LOCKED cap (loot_progression 'Guild Level Cap' = 30) so no
	-- path (authored or migration) can push Guild Level past the launch cap.
	stateOf(playerId).level = math.clamp(math.floor(level), 1, GUILD_LEVEL_CAP)
end

--------------------------------------------------
-- SAVE INTEGRATION (SaveService Key 3 — Progression + guild + unlocks)
--
-- GuildService does NOT touch DataStore. Main.server.lua folds Export() into
-- the `progression` table passed to SaveService.Save, and feeds the saved
-- sub-table back via Import() on load. This reuses the Slice 4 contract rather
-- than creating a second store.
--------------------------------------------------

function GuildService.Export(playerId: string)
	local state = stateOf(playerId)
	-- Compact: only persistent fields (xp, level, unlock flags).
	local unlocks = {}
	for k, v in state.unlocks do
		if v then unlocks[k] = true end
	end
	return {
		xp = state.xp,
		level = state.level,
		unlocks = unlocks,
	}
end

function GuildService.Import(playerId: string, data: any)
	GuildService.InitPlayer(playerId)
	if type(data) ~= "table" then return end
	local state = guildState[playerId]
	if type(data.xp) == "number" and data.xp >= 0 then
		state.xp = data.xp
	end
	if type(data.level) == "number" and data.level >= 1 then
		state.level = math.clamp(math.floor(data.level), 1, GUILD_LEVEL_CAP)
	end
	if type(data.unlocks) == "table" then
		state.unlocks = {}
		for k, v in data.unlocks do
			if v then state.unlocks[k] = true end
		end
	end
end

function GuildService.ClearPlayer(playerId: string)
	guildState[playerId] = nil
end

return GuildService
