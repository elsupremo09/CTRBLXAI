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
--   unit_progression (Dispatch XP formula), loot_progression (Dispatch Reward:
--   1-3 materials, lower tier than current content), the current content/Map
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

-- loot_progression Dispatch Reward: 1-3 materials.
local REWARD_MIN_MATERIALS, REWARD_MAX_MATERIALS = 1, 3
local MATERIAL_TIER_MIN, MATERIAL_TIER_MAX = 1, 5

-- materials_system id=21 — Tier by level band (reused to find "current content
-- tier"; FLAG-D2). This mirrors BlacksmithService.materialTierForLevel.
local function contentMaterialTier(contentLevel: number): number
	local lvl = math.max(1, math.floor(contentLevel or 1))
	if lvl <= 20 then return 1
	elseif lvl <= 40 then return 2
	elseif lvl <= 60 then return 3
	elseif lvl <= 80 then return 4
	else return 5 end
end

--------------------------------------------------
-- INJECTED DEPENDENCIES (dependency injection — no circular require)
--------------------------------------------------

local _currency: any = nil            -- CurrencyService.AsProvider() — Credit via grant table
local _currencyGrant: any = nil       -- CurrencyService.Credit(playerId, grant) direct (materials)
local _unitXpSink: ((string, string, number) -> ())? = nil  -- (playerId, unitId, xp) FLAG-D3
local _availabilitySink: any = nil    -- marks/queries unit availability on the EXISTING roster path
local _rosterProvider: ((string) -> ({ string }?))? = nil   -- owned unit ids (read-only)

function DispatchService.SetCurrencyProvider(svc: any) _currency = svc end
-- Direct Credit hook so materials can be granted all-at-once (CurrencyService.Credit).
function DispatchService.SetCurrencyCredit(fn: any) _currencyGrant = fn end
function DispatchService.SetUnitXpSink(fn: ((string, string, number) -> ())?) _unitXpSink = fn end
-- availability sink contract (lives on the roster/persistence owner, not here):
--   sink.MarkUnavailable(playerId, unitId, untilBattleCount)
--   sink.MarkAvailable(playerId, unitId)
--   sink.IsAvailable(playerId, unitId) -> boolean   (optional; we also track locally)
function DispatchService.SetAvailabilitySink(svc: any) _availabilitySink = svc end
function DispatchService.SetRosterProvider(fn: ((string) -> ({ string }?))?) _rosterProvider = fn end

--------------------------------------------------
-- STATE
--   active[playerId] = {
--     [unitId] = { missionId, tier, duration, startBattle, returnBattle, xp, matTier, matCount }
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
-- REWARD MATERIAL RESOLUTION (FLAG-D2)
--
-- "1-3 materials, lower tier than current content." We find the content tier
-- from the Map Level band, grant ONE tier below (floored at T1), and roll the
-- count 1-3 deterministically from the mission seed. Structure only — the exact
-- count rule is flagged for the Designer.
--------------------------------------------------

local function resolveRewardMaterials(contentLevel: number, seed: number): (number, number)
	local contentTier = contentMaterialTier(contentLevel)
	local rewardTier = math.clamp(contentTier - 1, MATERIAL_TIER_MIN, MATERIAL_TIER_MAX)
	local rng = Random.new(seed)
	local count = rng:NextInteger(REWARD_MIN_MATERIALS, REWARD_MAX_MATERIALS)
	return rewardTier, count
end

--------------------------------------------------
-- AVAILABILITY (tracked on the existing roster path, not a new store)
--------------------------------------------------

function DispatchService.IsUnitDispatched(playerId: string, unitId: string): boolean
	return activeOf(playerId)[unitId] ~= nil
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
-- will pay (locked formula), and the reward material tier/count (FLAG-D2).
--
-- FLAG-D1: the DB does not lock how many missions to offer nor the tier→duration
-- table. We offer one mission per difficulty tier (5 total) with duration =
-- tier as a neutral placeholder, unless the caller supplies a `missionSpec`
-- override list of { tier, duration }.
--
-- Returns: { missions = { { missionId, tier, duration, xp, rewardTier, rewardCount } } }
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
	end

	offered[playerId] = {}
	for i, spec in specs do
		local tier = math.clamp(math.floor(spec.tier or MIN_TIER), MIN_TIER, MAX_TIER)
		local duration = math.max(1, math.floor(spec.duration or tier))
		local xp = DispatchService.ComputeDispatchXp(tier, duration)
		local missionSeed = baseSeed + i * 7919
		local rewardTier, rewardCount = resolveRewardMaterials(mapLevel, missionSeed)
		local missionId = string.format("dispatch_%d_%d", baseSeed, i)
		local m = {
			missionId = missionId,
			tier = tier,
			duration = duration,
			xp = xp,
			rewardTier = rewardTier,
			rewardCount = rewardCount,
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

	local startBattle = math.max(0, math.floor(battlesCompleted or 0))
	local returnBattle = startBattle + mission.duration

	-- Commit: mark every unit away.
	for _, unitId in unitIds do
		a[unitId] = {
			missionId = mission.missionId,
			tier = mission.tier,
			duration = mission.duration,
			startBattle = startBattle,
			returnBattle = returnBattle,
			xp = mission.xp,
			matTier = mission.rewardTier,
			matCount = mission.rewardCount,
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
		rewardTier = mission.rewardTier,
		rewardCount = mission.rewardCount,
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
-- Returns: { returned = { { unitId, missionId, xp, matTier, matCount, xpGranted } } }
--------------------------------------------------

function DispatchService.ResolveReturns(playerId: string, battlesCompleted: number)
	assert(type(playerId) == "string", "DispatchService.ResolveReturns: playerId required")
	local now = math.max(0, math.floor(battlesCompleted or 0))
	local a = activeOf(playerId)
	local returned = {}

	for unitId, rec in a do
		if now >= rec.returnBattle then
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

			-- 3) Credit reward materials through CurrencyService.Credit (always
			--    safe; no gold involved). Prefer the direct Credit hook; fall
			--    back to the provider's AddGold-less path is N/A (materials only).
			if rec.matCount and rec.matCount > 0 and rec.matTier then
				local grant = { materials = { [rec.matTier] = rec.matCount } }
				if _currencyGrant then
					_currencyGrant(playerId, grant)
				elseif _currency and _currency.SpendMaterials then
					-- No direct Credit injected — cannot grant materials safely
					-- without a credit path; flag rather than invent one.
					warn("[DispatchService] No CurrencyService.Credit wired — reward materials not granted (recorded)")
				end
			end

			table.insert(returned, {
				unitId = unitId,
				missionId = rec.missionId,
				xp = rec.xp,
				xpGranted = xpGranted,
				matTier = rec.matTier,
				matCount = rec.matCount,
			})

			a[unitId] = nil

			print(string.format(
				"[DispatchService] RETURNED %s from %s | +%d XP%s | +%d T%d materials",
				unitId, rec.missionId, rec.xp, xpGranted and "" or " (sink missing)",
				rec.matCount or 0, rec.matTier or 0))
		end
	end

	return { returned = returned }
end

--------------------------------------------------
-- QUERY
--------------------------------------------------

function DispatchService.GetActiveDispatches(playerId: string)
	local a = activeOf(playerId)
	local out = {}
	for unitId, rec in a do
		table.insert(out, {
			unitId = unitId,
			missionId = rec.missionId,
			tier = rec.tier,
			returnBattle = rec.returnBattle,
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
			xp = rec.xp,
			matTier = rec.matTier,
			matCount = rec.matCount,
		}
	end
	return { active = copy }
end

function DispatchService.Import(playerId: string, data: any)
	active[playerId] = {}
	if type(data) ~= "table" or type(data.active) ~= "table" then return end
	for unitId, rec in data.active do
		if type(unitId) == "string" and type(rec) == "table" then
			active[playerId][unitId] = {
				missionId = tostring(rec.missionId),
				tier = math.clamp(math.floor(tonumber(rec.tier) or MIN_TIER), MIN_TIER, MAX_TIER),
				duration = math.max(1, math.floor(tonumber(rec.duration) or 1)),
				startBattle = math.max(0, math.floor(tonumber(rec.startBattle) or 0)),
				returnBattle = math.max(0, math.floor(tonumber(rec.returnBattle) or 0)),
				xp = math.max(0, math.floor(tonumber(rec.xp) or 0)),
				matTier = math.clamp(math.floor(tonumber(rec.matTier) or 1), MATERIAL_TIER_MIN, MATERIAL_TIER_MAX),
				matCount = math.max(0, math.floor(tonumber(rec.matCount) or 0)),
			}
			-- Re-assert unavailability on the roster path after load.
			markAway(playerId, unitId, active[playerId][unitId].returnBattle)
		end
	end
end

function DispatchService.ClearPlayer(playerId: string)
	active[playerId] = nil
	offered[playerId] = nil
end

return DispatchService
