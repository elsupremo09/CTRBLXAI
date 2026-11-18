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
local DISPATCH_BASE_MAX_SLOTS = 3
local _slotProvider: ((string) -> number)? = nil
function DispatchService.SetSlotProvider(fn: ((string) -> number)?) _slotProvider = fn end

function DispatchService.GetSlotCap(playerId: string): number
	local n = _slotProvider and _slotProvider(playerId) or 1
	return math.clamp(math.floor(tonumber(n) or 1), 0, DISPATCH_BASE_MAX_SLOTS)
end

-- Fee change from Guild Hall furniture (War Table Map -5g, guild_facilities 94; injected, nil-safe).
local _feeModifier: (() -> number)? = nil
function DispatchService.SetFeeModifier(fn: (() -> number)?) _feeModifier = fn end

-- Dispatch building level (guild_facilities 116/117, USER RULING 2026-11-18 11:28 AM, Package A).
-- Injected (GuildMenuService owns building levels); nil-safe = Level 1.
local DISPATCH_MAX_LEVEL = 10
local FEE_DISCOUNT_PCT_PER_LEVEL = 3 -- -3% per level above L1 (50 -> 36 at L10)
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
function DispatchService.BaseFeeForLevel(level: number): number
	local l = clampLevel(level)
	return math.floor(DISPATCH_FEE_GOLD * (100 - FEE_DISCOUNT_PCT_PER_LEVEL * (l - 1)) / 100)
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
function DispatchService.LevelInfo(level: number): { fee: number, offers: number }
	return { fee = DispatchService.FeeForLevel(level), offers = DispatchService.OffersForLevel(level) }
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

local function activeOf(playerId: string)
	if not active[playerId] then active[playerId] = {} end
	return active[playerId]
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
	return activeOf(playerId)[unitId] ~= nil
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

			-- 2) Award unit XP (FLAG-D3: through the injected sink; if absent the
			--    amount is reported but not invented/dropped silently).
			local xpGranted = false
			if _unitXpSink then
				_unitXpSink(playerId, unitId, rec.xp)
				xpGranted = true
			else
				warn(string.format(
					"[DispatchService] Unit-XP sink not wired — %s owed %d Dispatch XP (recorded, not granted; FLAG-D3)",
					unitId, rec.xp))
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
							_currencyGrant(playerId, grant)
							paidMaterial = mat
							paidAmount = amount
							if mat == "mercury" then mercury = amount end
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
				xp = rec.xp,
				xpGranted = xpGranted,
				mercury = mercury,
				material = paidMaterial,
				amount = paidAmount,
				gemId = gemId,
			})

			a[unitId] = nil

			print(string.format(
				"[DispatchService] RETURNED %s from %s | +%d XP%s | +%d %s%s",
				unitId, rec.missionId, rec.xp, xpGranted and "" or " (sink missing)", paidAmount,
				tostring(paidMaterial or "none"), if gemId then " (" .. gemId .. ")" else ""))
		end
	end

	return { returned = returned }
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
	return { active = copy, recalled = rlist }
end

function DispatchService.Import(playerId: string, data: any)
	active[playerId] = {}
	recalled[playerId] = nil
	if type(data) ~= "table" or type(data.active) ~= "table" then return end
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
end

function DispatchService.ClearPlayer(playerId: string)
	active[playerId] = nil
	offered[playerId] = nil
	recalled[playerId] = nil
end

return DispatchService
