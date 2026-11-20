--!strict
-- DispatchService.lua
-- CTRBLXAI | Slice 6 — Base Management (Batch 2 of 3)
--
-- OWNS (per service_boundaries 'Dispatch Service'):
--   Dispatch mission OFFERS and the send/return RESOLUTION. Dispatch is a
--   quest-board activity that does NOT start a battle: the player sends units
--   away for N battles; the units are unavailable until N battles have been
--   completed, then they return with the computed XP and rewards.
--
-- READS:
--   unit_progression (Dispatch XP formula), materials_system 12 (Dispatch Reward:
--   1 mercury per mission, 2 for tier 4-5 — v2 2026-11-01), the current content/Map
--   Level and the player's completed-battle count (passed in). It READS the
--   roster through the existing persistence path — it does not own units.
--
-- WRITES:
--   On SEND: marks the chosen units unavailable (tracked ON the existing roster
--   /persistence path via an injected availability sink — NOT a new store).
--   On RETURN: awards the computed Dispatch XP through the existing unit-XP
--   grant path and credits reward materials through CurrencyService.Credit.
--
-- MUST NOT OWN:
--   The battle loop, the roster store, the currency store, item/loot generation.
--
-- PRIMARY INTERFACE:
--   OfferMissions(playerId, mapLevel, seed?)        -> { missions=[...] }
--   SendUnits(playerId, missionId, unitIds, battlesCompleted) -> ok, result|reason
--   ResolveReturns(playerId, battlesCompleted)      -> { returned=[...] }
--   GetActiveDispatches(playerId)                   -> [...]
--   IsUnitDispatched(playerId, unitId)              -> boolean
--   ComputeDispatchXp(difficultyTier, durationBattles) -> number   (LOCKED)
--
-- FAILURE BOUNDARY (LOCKED):
--   A unit already dispatched CANNOT be dispatched again (rejected before any
--   state change). Dispatched units are unavailable for deployment while away.
--   Sending is atomic: either all requested units are marked away or none are.
--
-- ────────────────────────────────────────────────────────────────────────────
-- LOCKED DATA — copied verbatim from CTRBLXAI.db. Do NOT invent or tune here.
-- ────────────────────────────────────────────────────────────────────────────
--
--   unit_progression (DispatchXP formula, Locked 2026-10-05):
--     Dispatch XP = (Dispatch Difficulty Tier × 60) × Duration (in battles).
--     Difficulty Tier 1-5. Duration = battles the unit is away.
--     (Pays roughly one battle's kills per battle of duration, minus a small
--      discount for zero risk / no player control.)
--   unit_progression / loot_progression (Dispatch mechanics, Locked direction):
--     Dispatch appears as a quest on the quest board but does NOT initiate a
--     battle. Minimum XP guaranteed on completion; enemies defeated add
--     additional XP (N/A here — dispatch has no battle, so only the guaranteed
--     formula XP applies).
--   loot_progression (Dispatch Reward, Locked):
--     Shown upfront. 1-3 materials, lower tier than current content.
--
-- ────────────────────────────────────────────────────────────────────────────
-- FLAGS — structure locked, exact mapping NOT in CTRBLXAI.db as of 2026-10-05.
-- Implemented as structure and surfaced for a Designer ruling (NOT invented).
--   FLAG-D1  DIFFICULTY-TIER → DURATION mapping. The XP formula multiplies tier
--            by duration, and tiers are 1-5, but the DB does not lock which
--            DURATION (battles-away) each offered tier uses, nor how many
--            missions are offered. OfferMissions therefore takes the duration
--            per mission as an input / caller-supplied field and, absent one,
--            uses duration = difficultyTier as a neutral placeholder. Designer
--            should lock the tier→duration table and the number of daily offers.
--   FLAG-D2  REWARD MATERIAL COUNT + TIER-BELOW rule. "1-3 materials, lower tier
--            than current content" locks the RANGE (1-3) and the DIRECTION
--            (one tier below the content tier) but not the exact count per tier
--            nor the content-level→material-tier mapping used to pick "current
--            content tier". We reuse the Blacksmith material-tier-by-level
--            bands (materials_system id=21: L1-20→T1 … L81-99→T5) to find the
--            content tier, then grant one tier below it, count rolled 1-3
--            deterministically. Designer should confirm the count rule.
--   FLAG-D3  UNIT-XP GRANT PATH NOT BUILT. As of this build there is no unit-XP
--            apply function in code (only GuildService references
--            unit_progression; RewardService documents the EXP grant path as
--            "designed-not-built"). DispatchService therefore awards unit XP
--            through an INJECTED unit-XP sink. If none is wired, the computed XP
--            is reported and logged but NOT silently dropped or invented — the
--            return is still recorded so the amount is auditable when the grant
--            path lands.

local DispatchService = {}

-- Real-time Dispatch (build step 2, 2026-11-19): numbers + pure math live in DispatchRtRules (DAT-003),
-- time comes from the server clock only (ServerTime, step 1).
local Rules = require(script.Parent:WaitForChild("DispatchRtRules"))
local ServerTime = require(script.Parent:WaitForChild("ServerTime"))

--------------------------------------------------
-- LOCKED CONSTANTS (mirror of DB — see header)
--------------------------------------------------

local DISPATCH_XP_TIER_FACTOR = 60   -- unit_progression: (Tier × 60) × Duration
local MIN_TIER, MAX_TIER = 1, 5      -- Difficulty Tier 1-5 (Locked)

-- MATERIAL-SPECIFIC MISSIONS (USER RULING 2026-11-12 1:42 PM, materials_system 12 /
-- unit_progression 99). Each mission pays ONE material, paid once per mission. Per tier: the
-- materials it may roll, the amount, and the draw weight. One table, frozen (DAT-001/DAT-002).
--   mercury   tiers 1-5, 1/1/1/2/2, weight 1
--   gems      tiers 3-5, 1 Rare-level rune gem (kind rolled on return), weight 1
--   crystals  tiers 4-5, 1, weight 0.25
--   sulfur    tier 5,    1, weight 0.06
local DISPATCH_REWARDS = table.freeze({
	[1] = table.freeze({ table.freeze({ material = "mercury", amount = 1, weight = 1 }) }),
	[2] = table.freeze({ table.freeze({ material = "mercury", amount = 1, weight = 1 }) }),
	[3] = table.freeze({
		table.freeze({ material = "mercury", amount = 1, weight = 1 }),
		table.freeze({ material = "gems", amount = 1, weight = 1 }),
	}),
	[4] = table.freeze({
		table.freeze({ material = "mercury", amount = 2, weight = 1 }),
		table.freeze({ material = "gems", amount = 1, weight = 1 }),
		table.freeze({ material = "crystals", amount = 1, weight = 0.25 }),
	}),
	[5] = table.freeze({
		table.freeze({ material = "mercury", amount = 2, weight = 1 }),
		table.freeze({ material = "gems", amount = 1, weight = 1 }),
		table.freeze({ material = "crystals", amount = 1, weight = 0.25 }),
		table.freeze({ material = "sulfur", amount = 1, weight = 0.06 }),
	}),
})
local REWARD_MATERIALS = table.freeze({ mercury = true, crystals = true, sulfur = true, gems = true })
DispatchService.REWARDS = DISPATCH_REWARDS -- read-only (tests / tools)

-- Mercury amount for a tier, read from the single table above (2026-11-12 leftover fix: no second
-- copy of the numbers). Used by Import for old saves whose record has no mercury amount.
local function rewardMercuryFor(tier: number): number
	for _, o in DISPATCH_REWARDS[math.clamp(tier, MIN_TIER, MAX_TIER)] do
		if o.material == "mercury" then return o.amount end
	end
	return 0
end

-- Deterministic weighted pick of a tier's reward from a mission seed (same seed = same board,
-- so the v2 D-1 no-double-send rule still holds).
local function pickReward(tier: number, missionSeed: number): (string, number)
	local options = DISPATCH_REWARDS[tier] or DISPATCH_REWARDS[MIN_TIER]
	local total = 0
	for _, o in options do total += o.weight end
	local roll = Random.new(missionSeed):NextNumber() * total
	for _, o in options do
		roll -= o.weight
		if roll < 0 then return o.material, o.amount end
	end
	local last = options[#options]
	return last.material, last.amount
end

--------------------------------------------------
-- INJECTED DEPENDENCIES (dependency injection — no circular require)
--------------------------------------------------

local _currency: any = nil            -- CurrencyService.AsProvider() — Credit via grant table
local _currencyGrant: any = nil       -- CurrencyService.Credit(playerId, grant) direct (mercury)
local _unitXpSink: ((string, string, number) -> ())? = nil  -- (playerId, unitId, xp) FLAG-D3
local _availabilitySink: any = nil    -- marks/queries unit availability on the EXISTING roster path
local _rosterProvider: ((string) -> ({ string }?))? = nil   -- owned unit ids (read-only)
-- Rune-gem roller (USER RULING 2026-11-12): Main wires RewardService.RollRuneGem(level, "Rare"),
-- the same roll elite encounters use. (level) -> gemId?
local _gemRoller: ((number) -> string?)? = nil

function DispatchService.SetCurrencyProvider(svc: any) _currency = svc end
-- Direct Credit hook so the mercury reward is granted through CurrencyService.Credit.
function DispatchService.SetCurrencyCredit(fn: any) _currencyGrant = fn end
function DispatchService.SetUnitXpSink(fn: ((string, string, number) -> ())?) _unitXpSink = fn end
-- availability sink contract (lives on the roster/persistence owner, not here):
--   sink.MarkUnavailable(playerId, unitId, untilBattleCount)
--   sink.MarkAvailable(playerId, unitId)
--   sink.IsAvailable(playerId, unitId) -> boolean   (optional; we also track locally)
function DispatchService.SetAvailabilitySink(svc: any) _availabilitySink = svc end
function DispatchService.SetRosterProvider(fn: ((string) -> ({ string }?))?) _rosterProvider = fn end
function DispatchService.SetGemRoller(fn: ((number) -> string?)?) _gemRoller = fn end

--------------------------------------------------
-- SLOTS + FEE (USER RULING 2026-10-07; economy_framework 26: 50 gold per mission)
-- Concurrent mission slots come from the Renown Rank (USER RULING 2026-11-16 1:53 PM: 1 at
-- Rank 5, 2 at Rank 10, 3 at Rank 15; the Guild Hall no longer sets them). Base max 3 per
-- economy_framework 26/34. Robux +1 slots up to 6 (economy_framework 34) are NOT built yet.
--------------------------------------------------
local DISPATCH_FEE_GOLD = 50
local _slotProvider: ((string) -> number)? = nil
function DispatchService.SetSlotProvider(fn: ((string) -> number)?) _slotProvider = fn end

-- Robux slot (economy_framework 34, +1 from the start, user 2026-11-19 2:48 PM). Not built yet: the
-- provider is nil-safe (0) until the Robux purchase exists.
local _bonusSlotProvider: ((string) -> number)? = nil
function DispatchService.SetBonusSlotProvider(fn: ((string) -> number)?) _bonusSlotProvider = fn end

-- Slots = Renown Rank slots (1/2/3) + Dispatch level (+1 at L4, +1 at L10) + the Robux slot, code cap 6
-- (economy_framework 26, real-time Dispatch step 2 2026-11-19; was Rank only, cap 3).
function DispatchService.GetSlotCap(playerId: string): number
	local n = math.floor(tonumber(_slotProvider and _slotProvider(playerId) or 1) or 1)
	n += Rules.LevelSlots(DispatchService.GetLevel())
	if _bonusSlotProvider then
		local ok, b = pcall(_bonusSlotProvider, playerId)
		if ok then n += math.max(0, math.floor(tonumber(b) or 0)) end
	end
	return math.clamp(n, 0, Rules.SLOT_CAP)
end

-- Fee change from Guild Hall furniture (War Table Map -5g, guild_facilities 94; injected, nil-safe).
local _feeModifier: (() -> number)? = nil
function DispatchService.SetFeeModifier(fn: (() -> number)?) _feeModifier = fn end

-- Dispatch building level (guild_facilities 116/117, USER RULING 2026-11-18 11:28 AM, Package A).
-- Injected (GuildMenuService owns building levels); nil-safe = Level 1.
local DISPATCH_MAX_LEVEL = 10
local BASE_OFFERS = 5                -- one mission per tier 1-5
local EXTRA_OFFER_LEVELS = table.freeze({ 4, 7, 10 }) -- +1 offer each (5 -> 8)
local EXTRA_OFFER_MIN_TIER, EXTRA_OFFER_MAX_TIER = 3, 5 -- the extra offers are Tier 3-5
local _levelProvider: (() -> number)? = nil
function DispatchService.SetLevelProvider(fn: (() -> number)?) _levelProvider = fn end

local function clampLevel(level: any): number
	return math.clamp(math.floor(tonumber(level) or 1), 1, DISPATCH_MAX_LEVEL)
end

function DispatchService.GetLevel(): number
	if not _levelProvider then return 1 end
	local ok, l = pcall(_levelProvider)
	return if ok then clampLevel(l) else 1
end

local function feeDelta(): number
	if not _feeModifier then return 0 end
	local ok, d = pcall(_feeModifier)
	return if ok then math.floor(tonumber(d) or 0) else 0
end

--- Fee at a Dispatch level, before furniture: floor(50 x (100 - 3 x (level - 1)) / 100).
-- Real-time Dispatch (economy_framework 26, 2026-11-19): 50 gold at every level, the fee cut is dropped.
function DispatchService.BaseFeeForLevel(_level: number): number
	return DISPATCH_FEE_GOLD
end

--- Fee the player pays at a Dispatch level: level fee, then War Table furniture (-5), never below 0.
function DispatchService.FeeForLevel(level: number): number
	return math.max(0, DispatchService.BaseFeeForLevel(level) + feeDelta())
end

--- Missions offered at a Dispatch level: 5, +1 at L4, L7 and L10.
function DispatchService.OffersForLevel(level: number): number
	local l = clampLevel(level)
	local n = BASE_OFFERS
	for _, at in EXTRA_OFFER_LEVELS do
		if l >= at then n += 1 end
	end
	return n
end

--- Numbers for the Guild Hall next-level lines (guild_facilities 113).
-- Real-time Dispatch step 2 (2026-11-19): earnLimit (hours) and tierUnlock (tier newly unlocked at this
-- level, or nil) feed the approved next-level lines DISPATCH-RT-10 / RT-11 (unit_progression 99).
function DispatchService.LevelInfo(level: number): { fee: number, offers: number, earnLimit: number, tierUnlock: number? }
	return { fee = DispatchService.FeeForLevel(level), offers = DispatchService.OffersForLevel(level),
		earnLimit = Rules.EarnLimitHours(level), tierUnlock = Rules.TierUnlockedAt(level) }
end

function DispatchService.GetFeeGold(): number
	return DispatchService.FeeForLevel(DispatchService.GetLevel())
end

--------------------------------------------------
-- STATE
--   active[playerId] = {
--     [unitId] = { missionId, tier, duration, startBattle, returnBattle, xp, mercury,
--                  material, amount, gemLevel }   (material/amount: 2026-11-12)
--   }
-- This is the dispatch LEDGER (who is away, how much they will earn). It is
-- serialized through the EXISTING SaveService path via Export/Import (same
-- pattern as GuildService/CurrencyService) — it is NOT a second DataStore, and
-- it is NOT a second roster: the roster still lives in PersistentStateService;
-- this only records the "away" bookkeeping keyed by the existing unitIds.
--------------------------------------------------

local active: { [string]: { [string]: any } } = {}
-- Offered-but-unsent missions, cached per player from the last OfferMissions.
local offered: { [string]: { [string]: any } } = {}
-- Recalled mission ids (USER RULING 2026-11-12, Dispatch Recall): a recalled mission is not
-- offered again on the same board. Board mission ids carry the board seed
-- ("dispatch_<seed>_<i>"), so ids from an older board can never match a new one;
-- OfferMissions drops them when the board changes. Saved via Export so a restart that rebuilds
-- the same board from its seed still hides the mission.
local recalled: { [string]: { [string]: boolean } } = {}
-- Real-time Dispatch step 3 (2026-11-19): set once the old battle-count missions were cashed out (saved).
local legacyCashedOut: { [string]: boolean } = {}

local function activeOf(playerId: string)
	if not active[playerId] then active[playerId] = {} end
	return active[playerId]
end

-- REAL-TIME ledger (build step 2, 2026-11-19), one record per mission (see the REAL-TIME section).
-- Lives next to the old battle-count ledger until step 3 cashes the old missions out.
local rt: { [string]: { [string]: any } } = {}
local function rtOf(playerId: string)
	if not rt[playerId] then rt[playerId] = {} end
	return rt[playerId]
end
local function rtMissionOfUnit(playerId: string, unitId: string): string?
	for mid, rec in rtOf(playerId) do
		for _, u in rec.unitIds do
			if u == unitId then return mid end
		end
	end
	return nil
end

--------------------------------------------------
-- LOCKED XP FORMULA
--------------------------------------------------

-- Dispatch XP = (Dispatch Difficulty Tier × 60) × Duration (in battles)
function DispatchService.ComputeDispatchXp(difficultyTier: number, durationBattles: number): number
	local tier = math.clamp(math.floor(difficultyTier or MIN_TIER), MIN_TIER, MAX_TIER)
	local duration = math.max(1, math.floor(durationBattles or 1))
	return (tier * DISPATCH_XP_TIER_FACTOR) * duration
end

--------------------------------------------------
-- AVAILABILITY (tracked on the existing roster path, not a new store)
--------------------------------------------------

function DispatchService.IsUnitDispatched(playerId: string, unitId: string): boolean
	return activeOf(playerId)[unitId] ~= nil or rtMissionOfUnit(playerId, unitId) ~= nil
end

-- Days left on a unit's dispatch (nil = not dispatched). Each battle burns at least 1 day, so this is
-- the most battles until the unit is back (Quest Board Choose Party view, 2026-11-18).
function DispatchService.GetRemainingDays(playerId: string, unitId: string): number?
	local rec = activeOf(playerId)[unitId]
	if not rec then return nil end
	local d = rec.remainingDays
	if d == nil then d = math.max(1, math.floor(rec.duration or 1)) end
	return math.max(1, math.floor(d))
end

-- Number of concurrent missions in use (one slot per mission, not per unit).
function DispatchService.GetSlotsUsed(playerId: string): number
	local missions, n = {}, 0
	for _, rec in activeOf(playerId) do
		if rec.missionId and not missions[rec.missionId] then missions[rec.missionId] = true; n += 1 end
	end
	for _ in rtOf(playerId) do n += 1 end -- real-time missions (step 2) use slots too
	return n
end

local function markAway(playerId: string, unitId: string, returnBattle: number)
	-- Record locally (the ledger) AND notify the roster owner's availability
	-- sink if one is wired, so the deployment UI / battle start sees the unit as
	-- unavailable using the EXISTING roster state — no second availability store.
	if _availabilitySink and _availabilitySink.MarkUnavailable then
		_availabilitySink.MarkUnavailable(playerId, unitId, returnBattle)
	end
end

local function markBack(playerId: string, unitId: string)
	if _availabilitySink and _availabilitySink.MarkAvailable then
		_availabilitySink.MarkAvailable(playerId, unitId)
	end
end

--------------------------------------------------
-- PRIMARY INTERFACE: OfferMissions
--
-- Produces the quest-board dispatch offers. Deterministic given the seed. Each
-- mission carries a difficulty tier (1-5), a duration (battles away), the XP it
-- will pay (locked formula), and its mercury reward (materials_system 12).
--
-- A mission that is still away (sent earlier, units not back yet) is NOT offered
-- again. Offers are not saved, so after a restart with no battle in between the
-- same seed rebuilds the same mission IDs; without this the sent mission came back
-- on the board and could be sent twice (v2 D-1, 2026-11-01).
--
-- FLAG-D1: the DB does not lock how many missions to offer nor the tier→duration
-- table. We offer one mission per difficulty tier (5 total) with duration =
-- tier as a neutral placeholder, unless the caller supplies a `missionSpec`
-- override list of { tier, duration }.
--
-- Each mission pays ONE material (USER RULING 2026-11-12): rewardMaterial + rewardAmount,
-- picked from DISPATCH_REWARDS by the mission seed. rewardMercury = the amount when the material
-- is mercury, else 0 (compatibility).
--
-- Returns: { missions = { { missionId, tier, duration, xp, rewardMaterial, rewardAmount, rewardMercury } } }
--------------------------------------------------

function DispatchService.OfferMissions(playerId: string, mapLevel: number, seed: number?, missionSpec: { any }?)
	assert(type(playerId) == "string", "DispatchService.OfferMissions: playerId required")
	-- RETIRED (real-time Dispatch step 3, 2026-11-19): the battle-count board is gone; real-time missions
	-- are picked by tier + material (RtSend). The old screen gets an empty board until step 4 replaces it.
	do return { missions = {} } end
	local baseSeed = seed or 0
	local missions = {}

	local specs = missionSpec
	if type(specs) ~= "table" or #specs == 0 then
		-- FLAG-D1 placeholder: one mission per tier, duration = tier.
		specs = {}
		for tier = MIN_TIER, MAX_TIER do
			table.insert(specs, { tier = tier, duration = tier })
		end
		-- Dispatch level offers (guild_facilities 116): +1 Tier 3-5 mission at L4, L7, L10. The tier
		-- comes from the board seed, so the same board always shows the same extra missions.
		local extra = DispatchService.OffersForLevel(DispatchService.GetLevel()) - #specs
		local span = EXTRA_OFFER_MAX_TIER - EXTRA_OFFER_MIN_TIER + 1
		for k = 1, math.max(0, extra) do
			local tier = math.clamp(EXTRA_OFFER_MIN_TIER + (math.abs(math.floor(baseSeed)) + k * 104729) % span,
				MIN_TIER, MAX_TIER)
			table.insert(specs, { tier = tier, duration = tier })
		end
	end

	local awayMissions: { [string]: boolean } = {}
	for _, rec in activeOf(playerId) do
		if rec.missionId then awayMissions[rec.missionId] = true end
	end

	-- Recalled ids from an older board (different seed prefix) are stale: drop them.
	local boardPrefix = string.format("dispatch_%d_", baseSeed)
	local rset = recalled[playerId]
	if rset then
		for mid in rset do
			if string.sub(mid, 1, #boardPrefix) ~= boardPrefix then rset[mid] = nil end
		end
		if next(rset) == nil then recalled[playerId] = nil; rset = nil end
	end

	offered[playerId] = {}
	for i, spec in specs do
		local tier = math.clamp(math.floor(spec.tier or MIN_TIER), MIN_TIER, MAX_TIER)
		local duration = math.max(1, math.floor(spec.duration or tier))
		local xp = DispatchService.ComputeDispatchXp(tier, duration)
		local missionSeed = baseSeed + i * 7919
		local missionId = string.format("dispatch_%d_%d", baseSeed, i)
		if awayMissions[missionId] then
			continue -- already sent and still away
		end
		if rset and rset[missionId] then
			continue -- recalled from this board: not offered again until the next board
		end
		local material, amount = pickReward(tier, missionSeed)
		local m = {
			missionId = missionId,
			tier = tier,
			duration = duration,
			xp = xp,
			rewardMaterial = material,
			rewardAmount = amount,
			rewardMercury = if material == "mercury" then amount else 0,
			gemLevel = math.max(1, math.floor(mapLevel or 1)), -- rune-gem missions roll at this level
			seed = missionSeed,
		}
		offered[playerId][missionId] = m
		table.insert(missions, m)
	end

	print(string.format("[DispatchService] Offered %d mission(s) to %s | mapLevel %d",
		#missions, playerId, math.floor(mapLevel or 1)))
	return { missions = missions }
end

--------------------------------------------------
-- PRIMARY INTERFACE: SendUnits
--
-- Sends one or more owned, currently-available units on an offered mission.
-- Atomic (LOCKED): if ANY requested unit is already dispatched (or not owned),
-- the WHOLE send is rejected and no unit is marked away.
--
-- battlesCompleted = the player's current completed-battle count; the units
-- return once battlesCompleted has advanced by `duration`.
--
-- Returns: ok(boolean), result(table)|reason(string)
--------------------------------------------------

function DispatchService.SendUnits(playerId: string, missionId: string, unitIds: { string }, battlesCompleted: number)
	assert(type(playerId) == "string", "DispatchService.SendUnits: playerId required")
	-- RETIRED (real-time Dispatch step 3, 2026-11-19): use RtSend. Existing message, no new text.
	do return false, "That mission is no longer offered" end

	local mission = offered[playerId] and offered[playerId][missionId]
	if not mission then
		return false, "Unknown or expired mission"
	end
	if type(unitIds) ~= "table" or #unitIds == 0 then
		return false, "No units selected"
	end

	-- Validate ALL units first (atomic): owned (if roster provider wired) and
	-- not already dispatched. Nothing is changed until every check passes.
	local ownedSet: { [string]: boolean }? = nil
	if _rosterProvider then
		local roster = _rosterProvider(playerId)
		if type(roster) == "table" then
			ownedSet = {}
			for _, uid in roster do ownedSet[uid] = true end
		end
	end

	local a = activeOf(playerId)
	-- One send per mission (v2 D-1): the mission reward is paid once per mission ID.
	for _, rec in a do
		if rec.missionId == mission.missionId then
			return false, "This mission has already been sent"
		end
	end
	for _, unitId in unitIds do
		if type(unitId) ~= "string" then
			return false, "Invalid unit id in selection"
		end
		if a[unitId] then
			return false, string.format("Unit %s is already dispatched", unitId)
		end
		if ownedSet and not ownedSet[unitId] then
			return false, string.format("Unit %s is not on the roster", unitId)
		end
	end

	-- Slot + fee checks (nothing charged on refusal).
	local cap = DispatchService.GetSlotCap(playerId)
	local used = DispatchService.GetSlotsUsed(playerId)
	if used >= cap then
		return false, string.format("No free dispatch slot (%d/%d in use)", used, cap)
	end
	if not (_currency and _currency.GetGold and _currency.SpendGold) then
		return false, "Gold unavailable — dispatch not sent"
	end
	local gold = _currency.GetGold(playerId) or 0
	local fee = DispatchService.GetFeeGold() -- 50, minus furniture (War Table Map)
	if gold < fee then
		return false, string.format("Not enough gold: dispatch costs %d (you have %d)", fee, gold)
	end
	if fee > 0 and not _currency.SpendGold(playerId, fee) then
		return false, "Gold payment failed — dispatch not sent"
	end

	local startBattle = math.max(0, math.floor(battlesCompleted or 0))
	local returnBattle = startBattle + mission.duration

	-- Commit: mark every unit away.
	for _, unitId in unitIds do
		a[unitId] = {
			missionId = mission.missionId,
			tier = mission.tier,
			duration = mission.duration,
			startBattle = startBattle,
			returnBattle = returnBattle,  -- legacy (battle-count); kept for save back-compat
			remainingDays = mission.duration,  -- 2026-10-16: duration is now DAYS (1 day = 4000 CT)
			xp = mission.xp,
			mercury = mission.rewardMercury,
			material = mission.rewardMaterial,
			amount = mission.rewardAmount,
			gemLevel = mission.gemLevel,
		}
		markAway(playerId, unitId, returnBattle)
	end

	-- A sent mission is consumed from the offer board.
	offered[playerId][missionId] = nil

	print(string.format(
		"[DispatchService] SENT %d unit(s) on %s (tier %d, %d battle(s)) for %s | returns at battle %d | %d XP each",
		#unitIds, missionId, mission.tier, mission.duration, playerId, returnBattle, mission.xp))

	return true, {
		missionId = mission.missionId,
		unitIds = unitIds,
		returnBattle = returnBattle,
		xpEach = mission.xp,
		rewardMercury = mission.rewardMercury,
		rewardMaterial = mission.rewardMaterial,
		rewardAmount = mission.rewardAmount,
	}
end

--------------------------------------------------
-- PRIMARY INTERFACE: ResolveReturns
--
-- Call after each completed battle (with the new completed-battle count). Any
-- dispatched unit whose returnBattle has been reached comes home: it is marked
-- available again on the EXISTING roster path, awarded its locked Dispatch XP
-- through the injected unit-XP sink (FLAG-D3), and its reward materials are
-- credited through CurrencyService.Credit.
--
-- Returns: { returned = { { unitId, missionId, xp, mercury, xpGranted, material, amount, gemId } } }
-- (material/amount/gemId = what this unit's line paid; only the first unit of a mission pays.)
--------------------------------------------------

-- daysElapsed = days this battle was worth = ceil(elapsed CT / 4000), min 1 (2026-10-16,
-- unit_progression 77/78/99). Each completed battle burns down every active dispatch by that
-- many days; a unit returns when its remainingDays reaches 0. (Old callers passing only a
-- battle count still work: daysElapsed defaults to 1 = one day per battle.)
function DispatchService.ResolveReturns(playerId: string, daysElapsed: number?)
	assert(type(playerId) == "string", "DispatchService.ResolveReturns: playerId required")
	local burn = math.max(1, math.floor(tonumber(daysElapsed) or 1))
	local a = activeOf(playerId)
	local returned = {}
	local paidMissions: { [string]: boolean } = {}

	for unitId, rec in a do
		-- Back-compat: a record loaded from an old save may lack remainingDays; derive it from
		-- the stored duration so it still counts down instead of being stuck.
		if rec.remainingDays == nil then rec.remainingDays = math.max(1, math.floor(rec.duration or 1)) end
		rec.remainingDays = rec.remainingDays - burn
		if rec.remainingDays <= 0 then
			-- 1) Mark available again on the roster path.
			markBack(playerId, unitId)
			-- Remove the record BEFORE any grant (Tester WARN 1, 2026-11-19): if a corrupt old record
			-- errors part-way, a retry can never pay this unit a second time.
			a[unitId] = nil
			local recXp = math.max(0, math.floor(tonumber(rec.xp) or 0))
			local recMission = tostring(rec.missionId or "?")

			-- 2) Award unit XP (FLAG-D3: through the injected sink; if absent the
			--    amount is reported but not invented/dropped silently).
			local xpGranted = false
			if _unitXpSink then
				local okXp, errXp = pcall(_unitXpSink, playerId, unitId, recXp)
				if okXp then
					xpGranted = true
				else
					warn(string.format("[DispatchService] Dispatch XP grant failed for %s: %s", tostring(unitId), tostring(errXp)))
				end
			else
				warn(string.format(
					"[DispatchService] Unit-XP sink not wired — %s owed %d Dispatch XP (recorded, not granted; FLAG-D3)",
					tostring(unitId), recXp))
			end

			-- 3) The mission's ONE material through CurrencyService.Credit, ONCE per mission
			--    (materials_system 12, USER RULING 2026-11-12): the first returning unit carries it.
			--    Old records with no material pay mercury (rec.mercury, set on Import).
			local mercury = 0
			local paidMaterial: string? = nil
			local paidAmount = 0
			local gemId: string? = nil
			local missionKey = tostring(rec.missionId or unitId)
			if not paidMissions[missionKey] then
				paidMissions[missionKey] = true
				local mat = if type(rec.material) == "string" and REWARD_MATERIALS[rec.material] then rec.material else "mercury"
				local amount = if mat == "mercury" and rec.material == nil
					then math.max(0, math.floor(tonumber(rec.mercury) or 0))
					else math.max(0, math.floor(tonumber(rec.amount) or 0))
				if amount > 0 then
					local grant: any = nil
					if mat == "gems" then
						if _gemRoller then
							local okG, g = pcall(_gemRoller, math.max(1, math.floor(tonumber(rec.gemLevel) or 1)))
							if okG and type(g) == "string" then
								gemId = g
								grant = { gems = { [g] = amount } }
							else
								warn(string.format("[DispatchService] Rune gem roll failed for %s (%s) — gem not granted",
									tostring(rec.missionId), tostring(g)))
							end
						else
							warn("[DispatchService] No rune-gem roller wired — gem reward not granted (recorded)")
						end
					else
						grant = { [mat] = amount }
					end
					if grant then
						if _currencyGrant then
							local okC, errC = pcall(_currencyGrant, playerId, grant)
							if okC then
								paidMaterial = mat
								paidAmount = amount
								if mat == "mercury" then mercury = amount end
							else
								warn(string.format("[DispatchService] Dispatch %s grant failed for %s: %s", mat, recMission, tostring(errC)))
							end
						else
							-- No credit path injected: report it rather than invent one.
							warn(string.format("[DispatchService] No CurrencyService.Credit wired — %s reward not granted (recorded)", mat))
						end
					end
				end
			end

			table.insert(returned, {
				unitId = unitId,
				missionId = rec.missionId,
				xp = recXp,
				xpGranted = xpGranted,
				mercury = mercury,
				material = paidMaterial,
				amount = paidAmount,
				gemId = gemId,
			})

			print(string.format(
				"[DispatchService] RETURNED %s from %s | +%d XP%s | +%d %s%s",
				tostring(unitId), recMission, recXp, xpGranted and "" or " (not granted)", paidAmount,
				tostring(paidMaterial or "none"), if gemId then " (" .. gemId .. ")" else ""))
		end
	end

	return { returned = returned }
end

-- CASH-OUT (real-time Dispatch step 3, user ruling 2026-11-19 2:43 PM, unit_progression 77): every mission
-- still in the OLD battle-count ledger comes home now with its FULL recorded rewards, through the same
-- grant path as a normal return (XP sink, CurrencyService credit, rune-gem roll). The old ledger is then
-- empty, so running it again pays nothing (the empty ledger is the idempotency; the flag is saved as a record).
function DispatchService.CashOutLegacy(playerId: string)
	assert(type(playerId) == "string", "DispatchService.CashOutLegacy: playerId required")
	local result = DispatchService.ResolveReturns(playerId, 1e9) -- burns every remaining day at once
	legacyCashedOut[playerId] = true
	offered[playerId] = nil
	recalled[playerId] = nil
	print(string.format("[DispatchService] Old battle-count missions cashed out for %s | %d unit(s) home with full rewards",
		playerId, #(result.returned or {})))
	return result
end

function DispatchService.IsLegacyCashedOut(playerId: string): boolean
	return legacyCashedOut[playerId] == true
end

--------------------------------------------------
-- PRIMARY INTERFACE: RecallMission (USER RULING 2026-11-12, Dispatch Recall)
--
-- Ends an active mission early: every unit on it comes home now (same availability path as a
-- normal return). NO reward: no XP, no mercury, and the gold fee is NOT refunded. The mission
-- is not offered again on the current board. Callers (GuildMenuService) only allow this at the
-- guild base. Atomic: an unknown or non-active mission changes nothing.
--
-- Returns: ok(boolean), result { missionId, returnedUnitIds } | reason(string)
--------------------------------------------------

function DispatchService.RecallMission(playerId: string, missionId: string)
	assert(type(playerId) == "string", "DispatchService.RecallMission: playerId required")
	if type(missionId) ~= "string" or missionId == "" then
		return false, "Invalid mission"
	end
	local a = activeOf(playerId)
	local unitIds: { string } = {}
	for unitId, rec in a do
		if rec.missionId == missionId then table.insert(unitIds, unitId) end
	end
	if #unitIds == 0 then
		return false, "That mission is not out on dispatch"
	end
	table.sort(unitIds)
	for _, unitId in unitIds do
		a[unitId] = nil -- removed from the ledger, so Export no longer saves it
		markBack(playerId, unitId)
	end
	if not recalled[playerId] then recalled[playerId] = {} end
	recalled[playerId][missionId] = true
	print(string.format("[DispatchService] RECALLED %s for %s | %d unit(s) home: %s | no reward, fee not refunded",
		missionId, playerId, #unitIds, table.concat(unitIds, ", ")))
	return true, { missionId = missionId, returnedUnitIds = unitIds }
end

-- Is this mission id recalled on the current board? (Board filters; tests.)
function DispatchService.IsRecalled(playerId: string, missionId: string): boolean
	local rset = recalled[playerId]
	return rset ~= nil and rset[missionId] == true
end

--------------------------------------------------
-- QUERY
--------------------------------------------------

function DispatchService.GetActiveDispatches(playerId: string)
	local a = activeOf(playerId)
	local out = {}
	for unitId, rec in a do
		-- remainingDays drives the reward-screen countdown; derive it nil-safely for old
		-- saves that predate the field (same fallback ResolveReturns uses). (2026-10-23)
		local remainingDays = rec.remainingDays
		if remainingDays == nil then remainingDays = math.max(1, math.floor(rec.duration or 1)) end
		table.insert(out, {
			unitId = unitId,
			missionId = rec.missionId,
			tier = rec.tier,
			duration = rec.duration,
			returnBattle = rec.returnBattle,
			remainingDays = remainingDays,
			xp = rec.xp,
		})
	end
	return out
end

--------------------------------------------------
-- REAL-TIME DISPATCH (build step 2, 2026-11-19)
--   unit_progression 77/78/99/106, materials_system 12, guild_facilities 116, economy_framework 26.
--   Server logic only; the Dispatch screen switches to it in step 4, old battle-count missions are
--   cashed out in step 3. Until then both ledgers run side by side (IsUnitDispatched / GetSlotsUsed
--   count both).
--
--   rt[playerId][missionId] = { missionId, tier, material, unitIds, sentAt, lastCollectAt, levelAtSend,
--     gearLevel, seed, matFrac, xpFrac = { [unitId] = n }, collects }
--   * Time: SERVER clock only (ServerTime). Earned = seconds since lastCollectAt, up to the level's
--     earning limit (no daily cap, user 2026-11-20 12:53 AM). Rates per hour = Rules.RATE_TABLE.
--   * Earning uses the CURRENT Dispatch level (table cell, limit, item unlocks), so an upgrade
--     helps missions already out; levelAtSend is kept for the record. (Builder default 2026-11-19.)
--   * Collect: allowed once the tier's minimum time has passed (before that only Recall at 25% EXP,
--     so collect-then-recall cannot dodge the early-return rule). Banks EXP / material / items, the
--     meter restarts, the mission keeps going.
--   * Recall: ends the mission; after the minimum = a full collect, before = 25% EXP only.
--   * State is updated BEFORE anything is granted (no double pay if a grant errors); the caller saves
--     right after (grant then save, unit_progression 77).
--   * No Fortune, no reroll: items roll from the mission seed fixed at send + the collect count.
--------------------------------------------------

-- Injected (Main): unit level/XP + the game's EXP curve, and the item roller (commits the item).
--   SetProgressHooks({ getProgress = (pid, unitId) -> { level, xp }, xpToNext = (level) -> number, levelCap = 99 })
--   SetItemRoller((pid, kind, rarity, level, seed) -> { kind, id, name, rarity }?)   kind: consumable | card | gear
local _progress: any = nil
local _itemRoller: any = nil
function DispatchService.SetProgressHooks(h: any) _progress = h end
function DispatchService.SetItemRoller(fn: any) _itemRoller = fn end

local RT_ID_MAX = 64
local MAX_ITEMS_PER_KIND = 10 -- safety cap per collect (expected values are far below 1)
local rtCounter = 0

local function xpToNextFn(): (number) -> number
	if _progress and type(_progress.xpToNext) == "function" then return _progress.xpToNext end
	return function(level: number) return 500 + 20 * level end -- fallback only; Main wires ProgressionService.XpToNext
end

local function unitProgress(playerId: string, unitId: string): (number, number)
	if _progress and type(_progress.getProgress) == "function" then
		local ok, p = pcall(_progress.getProgress, playerId, unitId)
		if ok and type(p) == "table" then
			return math.max(1, math.floor(tonumber(p.level) or 1)), math.max(0, tonumber(p.xp) or 0)
		end
	end
	return 1, 0
end

local function levelCap(): number
	return math.max(1, math.floor(tonumber(_progress and _progress.levelCap) or 99))
end

local function rtUnitAway(playerId: string, unitId: string): boolean
	return activeOf(playerId)[unitId] ~= nil or rtMissionOfUnit(playerId, unitId) ~= nil
end

local function minSeconds(rec: any): number
	-- Current Dispatch level (2026-11-19 ruling: earnings use the current level); L8 shortens T4/T5 by 1 h.
	return Rules.MinHours(rec.tier, DispatchService.GetLevel()) * 3600
end

-- Earned seconds now (capped by the CURRENT level's limit) and that limit in seconds.
local function rtEarned(rec: any): (number, number)
	local limit = Rules.EarnLimitHours(DispatchService.GetLevel()) * 3600
	-- No daily cap (user 2026-11-20 12:53 AM): real time since the last collect, up to the level's limit.
	return ServerTime.Elapsed(rec.lastCollectAt, limit), limit
end

local rtSulfurWeek: { [string]: number } = {} -- last server week the weekly sulfur was paid (per player)

local function rtMaterialMissionOut(playerId: string): boolean
	for _, rec in rtOf(playerId) do
		if rec.material ~= Rules.NO_MATERIAL then return true end
	end
	return false
end

local function rtMinReached(rec: any): boolean
	return ServerTime.Elapsed(rec.sentAt) >= minSeconds(rec)
end

--- Numbers the Dispatch screen needs (step 4). Minimal (NET-003): tiers, limit, team size, slots, fee.
function DispatchService.RtConfig(playerId: string)
	local level = DispatchService.GetLevel()
	local tiers = {}
	for _, t in Rules.TIERS do
		local mats = {}
		for _, m in Rules.MATERIAL_ORDER do
			if Rules.MaterialAllowed(m, t.tier, level) then table.insert(mats, m) end
		end
		-- Display only (step 4 UI, 2026-11-19): what this tier earns per hour at this level. The server
		-- still works out every payout itself (NET-003: a few numbers per tier).
		local perHour: { [string]: number } = {}
		for _, m in mats do perHour[m] = Rules.MaterialRatePerHour(m, t.tier, level) end
		local cell = Rules.Cell(level, t.tier)
		table.insert(tiers, { tier = t.tier, minHours = Rules.MinHours(t.tier, level), unlock = t.unlock,
			unlocked = level >= t.unlock, materials = mats,
			materialPerHour = perHour, expFixed = cell and cell.fixed or 0, expPct = cell and cell.pct or 0 })
	end
	return {
		level = level,
		earnLimitHours = Rules.EarnLimitHours(level),
		unitsPerMission = Rules.UnitsPerMission(level),
		slotCap = DispatchService.GetSlotCap(playerId),
		slotsUsed = DispatchService.GetSlotsUsed(playerId),
		fee = DispatchService.GetFeeGold(),
		expMult = 1, -- the table already includes the level (2026-11-19 10:20 PM)
		materialMissionOut = rtMaterialMissionOut(playerId), -- one material mission at a time
		tiers = tiers,
	}
end

--- Real-time missions out now, for the screen (times as seconds, never absolute client time).
function DispatchService.RtList(playerId: string)
	local out = {}
	for _, rec in rtOf(playerId) do
		local secs, limit = rtEarned(rec)
		table.insert(out, {
			missionId = rec.missionId, tier = rec.tier, material = rec.material,
			noExp = rec.noExp == true, -- yield: material only (no EXP); old missions sent before 2026-11-20 pay both
			unitIds = table.clone(rec.unitIds),
			earnedSeconds = secs, limitSeconds = limit, full = secs >= limit,
			minSeconds = minSeconds(rec), sinceSentSeconds = ServerTime.Elapsed(rec.sentAt),
			minReached = rtMinReached(rec),
			-- Display only (2026-11-19 8:20 PM): carried material fraction + rate per hour at this level, so the
			-- screen can show "Next {Material} in …" instead of decimals. The server still works out every payout.
			matFrac = tonumber(rec.matFrac) or 0,
			matPerHour = Rules.MaterialRatePerHour(rec.material, rec.tier, DispatchService.GetLevel()),
		})
	end
	table.sort(out, function(a, b) return a.missionId < b.missionId end)
	return out
end

--- Send units on a real-time mission (unit_progression 99): any unlocked tier, any material that tier
--- allows, up to the level's team size. Atomic: every check passes before the fee is taken.
--- The caller (GuildMenuService) checks dungeon locks and keep-1-home, then saves.
function DispatchService.RtSend(playerId: string, tier: any, material: any, unitIds: any, gearLevel: any)
	assert(type(playerId) == "string", "DispatchService.RtSend: playerId required")
	local level = DispatchService.GetLevel()
	local t = Rules.Tier(tier)
	if not t then return false, "Invalid request" end
	if level < t.unlock then return false, string.format("Needs Dispatch level %d", t.unlock) end -- DISPATCH-RT-09
	if material ~= Rules.NO_MATERIAL then
		if not Rules.MaterialAllowed(material, t.tier, level) then return false, "Invalid request" end
		-- One material mission at a time (materials_system 12). Approved text RT-25 (user 2026-11-19 10:37 PM).
		if rtMaterialMissionOut(playerId) then return false, "Only one material mission at a time" end
	end
	local maxUnits = Rules.UnitsPerMission(level)
	if type(unitIds) ~= "table" or #unitIds < 1 or #unitIds > maxUnits then
		return false, string.format("Pick 1 to %d units", maxUnits)
	end
	local ownedSet: { [string]: boolean }? = nil
	if _rosterProvider then
		local roster = _rosterProvider(playerId)
		if type(roster) == "table" then
			ownedSet = {}
			for _, uid in roster do ownedSet[uid] = true end
		end
	end
	local seen: { [string]: boolean } = {}
	local clean: { string } = {}
	for _, uid in unitIds do
		if type(uid) ~= "string" or #uid > RT_ID_MAX or seen[uid] then return false, "Invalid unit selection" end
		if ownedSet and not ownedSet[uid] then return false, "That unit is not on your roster" end
		if rtUnitAway(playerId, uid) then return false, string.format("Unit %s is already dispatched", uid) end
		seen[uid] = true
		table.insert(clean, uid)
	end
	local cap = DispatchService.GetSlotCap(playerId)
	local used = DispatchService.GetSlotsUsed(playerId)
	if used >= cap then
		return false, string.format("No free dispatch slot (%d/%d in use)", used, cap)
	end
	if not (_currency and _currency.GetGold and _currency.SpendGold) then
		return false, "Gold unavailable — dispatch not sent"
	end
	local fee = DispatchService.GetFeeGold()
	local gold = _currency.GetGold(playerId) or 0
	if gold < fee then
		return false, string.format("Not enough gold: dispatch costs %d (you have %d)", fee, gold)
	end
	if fee > 0 and not _currency.SpendGold(playerId, fee) then
		return false, "Gold payment failed — dispatch not sent"
	end

	local now = ServerTime.Now()
	local book = rtOf(playerId)
	local missionId
	repeat
		rtCounter += 1
		missionId = string.format("rt_%d_%d", now, rtCounter)
	until book[missionId] == nil
	local xpFrac = {}
	for _, uid in clean do xpFrac[uid] = 0 end
	book[missionId] = {
		missionId = missionId, tier = t.tier, material = material, unitIds = clean,
		sentAt = now, lastCollectAt = now, levelAtSend = level,
		gearLevel = math.clamp(math.floor(tonumber(gearLevel) or 1), 1, 99),
		seed = (now * 7919 + rtCounter * 104729 + t.tier * 131) % 2147483647,
		matFrac = 0, xpFrac = xpFrac, collects = 0,
		-- Yield choice (user 2026-11-19 11:57 PM): a material mission pays material only, its units earn NO
		-- EXP; an EXP mission (material "none") pays EXP only. Items roll on every mission (2026-11-20 12:31 AM).
		noExp = material ~= Rules.NO_MATERIAL,
	}
	for _, uid in clean do markAway(playerId, uid, 0) end
	print(string.format("[DispatchService] RT SENT %s | %s | tier %d %s | %d unit(s) | L%d | fee %d",
		playerId, missionId, t.tier, tostring(material), #clean, level, fee))
	return true, { missionId = missionId, tier = t.tier, material = material, unitIds = clean, fee = fee,
		noExp = material ~= Rules.NO_MATERIAL }
end

-- Rolls and commits the item rewards for `hours` (from the mission seed + collect count, no Fortune).
local function rtRollItems(playerId: string, rec: any, level: number, hours: number): { any }
	local out = {}
	if hours <= 0 then return out end
	local expect = Rules.ItemExpectations(rec.tier, level, hours)
	local rng = Random.new(rec.seed + rec.collects * 104729)
	for _, it in Rules.ITEMS do -- fixed order, so the same seed always rolls the same way
		local e = expect[it.kind]
		if e and e > 0 then
			local n = math.floor(e)
			if rng:NextNumber() < e - n then n += 1 end
			n = math.min(n, MAX_ITEMS_PER_KIND)
			for _ = 1, n do
				local rarity
				if it.kind == "gear" then
					rarity = Rules.GEAR_RARITY_BY_TIER[rec.tier] or "Common"
					if rec.tier == Rules.MAX_TIER and level >= Rules.EPIC_GEAR_LEVEL and rng:NextNumber() < Rules.EPIC_GEAR_CHANCE then
						rarity = "Epic"
					end
				elseif it.kind == "card" then
					rarity = Rules.CARD_RARITY
				else
					rarity = Rules.CONSUMABLE_MAX_RARITY
				end
				local itemSeed = rng:NextInteger(1, 1073741823)
				if _itemRoller then
					local ok, item = pcall(_itemRoller, playerId, it.kind, rarity, rec.gearLevel, itemSeed)
					if ok and type(item) == "table" then
						table.insert(out, item)
					else
						warn(string.format("[DispatchService] RT item roll failed (%s %s): %s", it.kind, rarity, tostring(item)))
					end
				else
					warn("[DispatchService] No item roller wired — dispatch item not granted")
				end
			end
		end
	end
	return out
end

-- One payout. early = recall before the minimum (25% EXP, nothing else). Updates the record first,
-- then grants. Returns the summary.
local function rtPayout(playerId: string, rec: any, early: boolean)
	local level = DispatchService.GetLevel()
	local secs, limit = rtEarned(rec) -- 2026-11-20 fix: limit was dropped by the no-cap change (nil -> error at the log line)
	-- 2026-11-20 guard (user-approved): an old saved mission may lack these fields; default them so
	-- collect never errors on nil (rec.collects += 1, rec.xpFrac[...] writes below).
	if type(rec.xpFrac) ~= "table" then rec.xpFrac = {} end
	rec.collects = tonumber(rec.collects) or 0
	local hours = secs / 3600
	local cap, xtn = levelCap(), xpToNextFn()
	local xpMult = if early then Rules.EARLY_RECALL_XP_MULT else 1

	-- 1) Work everything out (reads only).
	local unitLines = {}
	for _, uid in rec.unitIds do
		local lvl, into = unitProgress(playerId, uid)
		-- Material missions pay no EXP (yield choice, 2026-11-19 11:57 PM). Early recall: EXP missions 25% EXP,
		-- material missions nothing (no EXP to take 25% of, and no material before the minimum).
		local raw = if rec.noExp == true then 0 else Rules.ExpForHours(rec.tier, level, hours, lvl, into, cap, xtn) * xpMult
		if not early and rec.noExp ~= true then raw += (rec.xpFrac[uid] or 0) end
		local whole = math.max(0, math.floor(raw))
		table.insert(unitLines, { unitId = uid, xp = whole, frac = if early then 0 else math.clamp(raw - whole, 0, 0.999999) })
	end
	local matWhole, matFrac = 0, rec.matFrac or 0
	if not early and rec.material ~= Rules.NO_MATERIAL then
		local m = Rules.MaterialForHours(rec.material, rec.tier, level, hours) + matFrac
		matWhole = math.max(0, math.floor(m))
		matFrac = math.clamp(m - matWhole, 0, 0.999999)
	end

	-- 2) Commit the record (so a second call right after pays nothing).
	local now = ServerTime.Now()
	rec.lastCollectAt = now
	rec.collects += 1
	-- Weekly sulfur (materials_system 12): 1 per week from Dispatch L7, on the first collect. The week
	-- starts Monday 00:00 Asia/Manila (user 2026-11-19 10:37 PM).
	local bonus: { [string]: number }? = nil
	local week = Rules.SulfurWeek(now)
	if not early and level >= Rules.SULFUR_WEEKLY_LEVEL and rtSulfurWeek[playerId] ~= week then
		rtSulfurWeek[playerId] = week
		bonus = { sulfur = Rules.SULFUR_WEEKLY_AMOUNT }
	end
	rec.matFrac = matFrac
	for _, line in unitLines do rec.xpFrac[line.unitId] = line.frac end

	-- 3) Grant.
	for _, line in unitLines do
		if line.xp > 0 then
			if _unitXpSink then
				local ok, err = pcall(_unitXpSink, playerId, line.unitId, line.xp)
				if not ok then warn("[DispatchService] RT EXP grant failed: " .. tostring(err)) end
			else
				warn(string.format("[DispatchService] Unit-XP sink not wired — %s owed %d EXP", line.unitId, line.xp))
			end
		end
	end
	local gemIds: { string } = {}
	if matWhole > 0 then
		local grant: any = nil
		if rec.material == "gems" then
			local gems: { [string]: number } = {}
			for _ = 1, matWhole do
				if _gemRoller then
					local okG, g = pcall(_gemRoller, rec.gearLevel)
					if okG and type(g) == "string" then
						gems[g] = (gems[g] or 0) + 1
						table.insert(gemIds, g)
					else
						warn("[DispatchService] RT rune gem roll failed: " .. tostring(g))
					end
				end
			end
			if next(gems) then grant = { gems = gems } end
		else
			grant = { [rec.material] = matWhole }
		end
		if grant then
			if _currencyGrant then
				local ok, err = pcall(_currencyGrant, playerId, grant)
				if not ok then warn("[DispatchService] RT material grant failed: " .. tostring(err)) end
			else
				warn("[DispatchService] No CurrencyService.Credit wired — dispatch material not granted")
			end
		end
	end
	if bonus then
		if _currencyGrant then
			local ok, err = pcall(_currencyGrant, playerId, bonus)
			if not ok then warn("[DispatchService] RT weekly sulfur grant failed: " .. tostring(err)) end
		else
			warn("[DispatchService] No CurrencyService.Credit wired — weekly sulfur not granted")
		end
	end
	local items = if early then {} else rtRollItems(playerId, rec, level, hours)

	print(string.format("[DispatchService] RT %s %s | %.2f h (limit %d h)%s | %d %s | %d item(s)",
		if early then "EARLY RECALL" else "COLLECT", rec.missionId, hours, math.floor(limit / 3600),
		if early then " | 25% EXP" else "", matWhole, tostring(rec.material), #items))
	return {
		missionId = rec.missionId, tier = rec.tier, hours = hours, full = secs >= limit, early = early,
		units = unitLines, material = rec.material, amount = matWhole, gemIds = gemIds, items = items,
		bonus = bonus,
	}
end

--- Collect one mission: bank what it earned, the meter restarts, the mission keeps going.
function DispatchService.RtCollect(playerId: string, missionId: any)
	if type(missionId) ~= "string" or #missionId == 0 or #missionId > RT_ID_MAX then return false, "Invalid mission" end
	local rec = rtOf(playerId)[missionId]
	if not rec then return false, "That mission is not out on dispatch" end
	if not rtMinReached(rec) then
		return false, string.format("Minimum %dh", math.floor(minSeconds(rec) / 3600)) -- DISPATCH-RT-05
	end
	return true, rtPayout(playerId, rec, false)
end

--- Collect every mission that is past its minimum and has earned something.
function DispatchService.RtCollectAll(playerId: string)
	local results = {}
	local ids = {}
	for mid in rtOf(playerId) do table.insert(ids, mid) end
	table.sort(ids)
	for _, mid in ids do
		local rec = rtOf(playerId)[mid]
		if rec and rtMinReached(rec) and (rtEarned(rec)) > 0 then
			table.insert(results, rtPayout(playerId, rec, false))
		end
	end
	return results
end

--- Recall: the mission ends, every unit comes home. After the minimum = full collect; before it =
--- 25% of the EXP earned, no materials, no items (unit_progression 106). The fee is never refunded.
function DispatchService.RtRecall(playerId: string, missionId: any)
	if type(missionId) ~= "string" or #missionId == 0 or #missionId > RT_ID_MAX then return false, "Invalid mission" end
	local book = rtOf(playerId)
	local rec = book[missionId]
	if not rec then return false, "That mission is not out on dispatch" end
	local early = not rtMinReached(rec)
	local summary = rtPayout(playerId, rec, early)
	book[missionId] = nil
	for _, uid in rec.unitIds do markBack(playerId, uid) end
	summary.returnedUnitIds = table.clone(rec.unitIds)
	print(string.format("[DispatchService] RT RECALLED %s | %d unit(s) home%s", missionId, #rec.unitIds,
		if early then " | before the minimum" else ""))
	return true, summary
end

local function rtExport(playerId: string)
	local out = {}
	for mid, rec in rtOf(playerId) do
		local xf = {}
		for uid, f in rec.xpFrac do xf[uid] = f end
		out[mid] = {
			missionId = rec.missionId, tier = rec.tier, material = rec.material, unitIds = table.clone(rec.unitIds),
			sentAt = rec.sentAt, lastCollectAt = rec.lastCollectAt, levelAtSend = rec.levelAtSend,
			gearLevel = rec.gearLevel, seed = rec.seed, matFrac = rec.matFrac, xpFrac = xf, collects = rec.collects,
			noExp = rec.noExp,
		}
	end
	return out
end

-- Old saves have no rt block (nothing to load). Every field is checked; a bad record is dropped.
local function rtImport(playerId: string, data: any)
	rt[playerId] = {}
	if type(data) ~= "table" then return end
	local book = rt[playerId]
	for mid, r in data do
		if type(mid) == "string" and #mid <= RT_ID_MAX and type(r) == "table" and type(r.unitIds) == "table" then
			local t = Rules.Tier(r.tier)
			-- Sulfur missions from before the daily cap (sulfur is now a weekly bonus) keep running as EXP
			-- missions; their tiny carried sulfur fraction is dropped (no double pay, no negative).
			local material = if r.material == Rules.NO_MATERIAL or r.material == "sulfur" then Rules.NO_MATERIAL
				elseif type(r.material) == "string" and Rules.MATERIALS[r.material] then r.material else nil
			local units: { string } = {}
			local seen: { [string]: boolean } = {}
			for _, uid in r.unitIds do
				if type(uid) == "string" and #uid <= RT_ID_MAX and not seen[uid] and not rtUnitAway(playerId, uid)
					and #units < 5 then
					seen[uid] = true
					table.insert(units, uid)
				end
			end
			if t and material and #units > 0 then
				local sentAt = ServerTime.Sanitize(r.sentAt)
				local last = math.max(sentAt, ServerTime.Sanitize(r.lastCollectAt))
				local xf = {}
				for _, uid in units do
					local f = type(r.xpFrac) == "table" and tonumber(r.xpFrac[uid]) or 0
					xf[uid] = if f and f == f then math.clamp(f, 0, 0.999999) else 0
				end
				local mf = if material == Rules.NO_MATERIAL then 0 else (tonumber(r.matFrac) or 0)
				-- Saves from the 2-hour daily cap build may still carry countDay / countUsed: ignored (no daily cap,
				-- 2026-11-20). lastCollectAt is kept, so a collect pays the time since it once, never twice.
				book[mid] = {
					missionId = mid, tier = t.tier, material = material, unitIds = units,
					sentAt = sentAt, lastCollectAt = last,
					levelAtSend = Rules.ClampLevel(r.levelAtSend),
					gearLevel = math.clamp(math.floor(tonumber(r.gearLevel) or 1), 1, 99),
					seed = math.floor(tonumber(r.seed) or 0) % 2147483647,
					matFrac = if mf == mf then math.clamp(mf, 0, 0.999999) else 0,
					xpFrac = xf,
					collects = math.max(0, math.floor(tonumber(r.collects) or 0)),
					-- Yield (2026-11-20): only a saved material mission marked noExp skips EXP. Missions saved before
					-- this change have no flag and keep paying as they were sent (EXP + material), no double pay.
					noExp = if r.noExp == true and material ~= Rules.NO_MATERIAL then true else nil,
				}
				for _, uid in units do markAway(playerId, uid, 0) end
			else
				warn("[DispatchService] Dropped a bad real-time dispatch record from the save: " .. mid)
			end
		end
	end
end

--------------------------------------------------
-- SAVE INTEGRATION (via the EXISTING SaveService path — Key 3 Progression)
--
-- The dispatch ledger (who is away + what they will earn) must survive a
-- rejoin, otherwise a sent unit would vanish or return for free. DispatchService
-- does NOT touch DataStore: Main.server.lua folds Export() into the Slice 4
-- Save payload (alongside GuildService/CurrencyService) and feeds it back via
-- Import() on load — the same pattern the batch-1 services use. No second store.
--------------------------------------------------

function DispatchService.Export(playerId: string)
	-- Compact copy of the active ledger. Offered (unsent) missions are NOT
	-- persisted — they are regenerated deterministically each session.
	local a = activeOf(playerId)
	local copy = {}
	for unitId, rec in a do
		copy[unitId] = {
			missionId = rec.missionId,
			tier = rec.tier,
			duration = rec.duration,
			startBattle = rec.startBattle,
			returnBattle = rec.returnBattle,
			remainingDays = rec.remainingDays,
			xp = rec.xp,
			mercury = rec.mercury,
			material = rec.material,
			amount = rec.amount,
			gemLevel = rec.gemLevel,
		}
	end
	-- Recalled ids of the current board (Dispatch Recall 2026-11-12); string list, save-safe.
	local rlist: { string } = {}
	for mid in recalled[playerId] or {} do table.insert(rlist, mid) end
	table.sort(rlist)
	return { active = copy, recalled = rlist, rt = rtExport(playerId), -- rt: real-time missions (step 2)
		rtSulfurWeek = rtSulfurWeek[playerId], -- weekly sulfur (daily cap build 2026-11-19)
		rtSulfurWeekV = if rtSulfurWeek[playerId] ~= nil then 2 else nil, -- 2 = Monday 00:00 Manila weeks
		legacyCashedOut = if legacyCashedOut[playerId] then true else nil } -- step 3 cash-out record
end

function DispatchService.Import(playerId: string, data: any)
	active[playerId] = {}
	recalled[playerId] = nil
	rt[playerId] = {}
	legacyCashedOut[playerId] = nil
	rtSulfurWeek[playerId] = nil
	if type(data) ~= "table" then return end
	if data.legacyCashedOut == true then legacyCashedOut[playerId] = true end
	local sw = tonumber(data.rtSulfurWeek)
	if sw and sw == sw and sw >= 0 then
		sw = math.floor(sw)
		if data.rtSulfurWeekV ~= 2 then
			-- Old week numbers (Thursday 00:00 UTC weeks, before 2026-11-19 10:37 PM) -> Monday 00:00 Manila
			-- weeks. Old week w overlaps new weeks w-1 and w; taking min(w, current week) never pays twice.
			sw = math.min(sw, Rules.SulfurWeek(ServerTime.Now()))
		end
		rtSulfurWeek[playerId] = sw
	end
	-- Real-time missions load after the old ledger (below), so a unit can never be on both.
	local rtData = data.rt
	if type(data.active) ~= "table" then
		rtImport(playerId, rtData)
		return
	end
	if type(data.recalled) == "table" then
		for _, mid in data.recalled do
			if type(mid) == "string" and #mid <= 64 then
				if not recalled[playerId] then recalled[playerId] = {} end
				recalled[playerId][mid] = true
			end
		end
	end
	for unitId, rec in data.active do
		if type(unitId) == "string" and type(rec) == "table" then
			local tier = math.clamp(math.floor(tonumber(rec.tier) or MIN_TIER), MIN_TIER, MAX_TIER)
			active[playerId][unitId] = {
				missionId = tostring(rec.missionId),
				tier = tier,
				duration = math.max(1, math.floor(tonumber(rec.duration) or 1)),
				startBattle = math.max(0, math.floor(tonumber(rec.startBattle) or 0)),
				returnBattle = math.max(0, math.floor(tonumber(rec.returnBattle) or 0)),
				xp = math.max(0, math.floor(tonumber(rec.xp) or 0)),
				-- Missions sent before v2 stored a material tier/count; they now pay mercury by
				-- the v2 rule for their tier (materials_system 12).
				mercury = if rec.mercury ~= nil then math.max(0, math.floor(tonumber(rec.mercury) or 0)) else rewardMercuryFor(tier),
				remainingDays = math.max(1, math.floor(tonumber(rec.remainingDays) or tonumber(rec.duration) or 1)),
				-- Material missions (2026-11-12). Saves before this have no material: they pay mercury
				-- (the mercury field above). An unknown material is dropped the same way.
				material = if type(rec.material) == "string" and REWARD_MATERIALS[rec.material] then rec.material else nil,
				amount = if type(rec.material) == "string" and REWARD_MATERIALS[rec.material]
					then math.max(0, math.floor(tonumber(rec.amount) or 0)) else nil,
				gemLevel = if rec.gemLevel ~= nil then math.max(1, math.floor(tonumber(rec.gemLevel) or 1)) else nil,
			}
			-- Re-assert unavailability on the roster path after load.
			markAway(playerId, unitId, active[playerId][unitId].returnBattle)
		end
	end
	rtImport(playerId, rtData)
end

function DispatchService.ClearPlayer(playerId: string)
	active[playerId] = nil
	rt[playerId] = nil
	offered[playerId] = nil
	recalled[playerId] = nil
	legacyCashedOut[playerId] = nil
	rtSulfurWeek[playerId] = nil
end

return DispatchService
