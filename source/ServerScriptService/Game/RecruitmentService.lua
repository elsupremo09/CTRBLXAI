--!strict
-- RecruitmentService.lua
-- CTRBLXAI | Slice 6 — Base Management (Batch 1 of 3)
--
-- OWNS (per service_boundaries 'Recruitment Service'):
--   Recruit pool generation, hire eligibility, hire cost resolution.
--
-- READS:
--   Guild level (GuildService), recruitment costs (economy_framework),
--   roster capacity, region/unlock gates (loot_progression / Tavern facility).
--
-- WRITES:
--   Hire request -> new unit handed to the EXISTING persistence/roster path
--   (PersistentStateService.RegisterNewUnit, same path Main.server.lua already
--   uses). It does NOT create a second roster store.
--
-- MUST NOT OWN:
--   Unit storage/roster persistence, combat, loot generation.
--
-- PRIMARY INTERFACE:
--   GenerateRecruitPool(playerId, seed, context?)
--   ValidateHire(playerId, candidate)
--   CommitHire(playerId, candidate)
--
-- FAILURE BOUNDARY:
--   No gold charged on a failed hire (insufficient gold / roster full).
--   Pool reroll is bounded. Charging and roster-registration are atomic:
--   gold is debited only after RegisterNewUnit succeeds.
--
-- ─────────────────────────────────────────────────────────────────────────
-- LOCKED DATA — copied verbatim from CTRBLXAI.db. Do NOT invent or tune here.
-- ─────────────────────────────────────────────────────────────────────────
--
--   economy_framework id=22 (Recruitment Fee Formula, Locked):
--     Fee = 200 + (Unit Level × 15) + Quality Premium.
--     Standard = +0, Quality = +300, Elite = +800.
--
--   guild_facilities Tavern id=9/10 (Locked):
--     Max Level 10. Each level: +1 recruit pool size.
--     L5: Quality recruits available. L8: Elite recruits available.
--     (Tavern FACILITY purchasing is Slice 8; this service only READS the
--      Tavern level to gate pool size and quality tiers.)
--
-- DEPENDENCIES ARE INJECTED (dependency injection, not require) so this module
-- never forms a circular require with the persistence/currency layer. All
-- injected deps are nil-checked before use (ARC pattern).

local RecruitmentService = {}

--------------------------------------------------
-- LOCKED CONSTANTS (mirror of DB — see header)
--------------------------------------------------

local FEE_BASE = 200            -- economy_framework id=22
local FEE_PER_LEVEL = 15        -- economy_framework id=22
local QUALITY_PREMIUM = table.freeze({  -- economy_framework id=22
	Standard = 0,
	Quality  = 300,
	Elite    = 800,
})

-- guild_facilities Tavern id=10: quality-tier unlock by Tavern level.
local TAVERN_QUALITY_LEVEL = 5  -- Quality recruits available at Tavern L5
local TAVERN_ELITE_LEVEL = 8    -- Elite recruits available at Tavern L8
local TAVERN_MAX_LEVEL = 10
-- Pool size = Tavern level (each level +1 recruit pool size). A Tavern level
-- of 0 (facility not built — Slice 8) yields an empty pool, which is correct:
-- recruitment requires the Tavern.

local REROLL_MAX_POOL_SIZE = TAVERN_MAX_LEVEL  -- hard upper bound on pool size

--------------------------------------------------
-- INJECTED DEPENDENCIES
--------------------------------------------------

local _guildService: any = nil           -- GetGuildLevel(playerId)
local _persistentState: any = nil        -- RegisterNewUnit(playerId, unitId, maxHp, maxMp)
local _currency: any = nil               -- { GetGold, SpendGold } — see note below
local _unitFactory: any = nil            -- function(candidate) -> unitDef{ id, maxHp, maxMp, ... }
local _tavernLevelProvider: ((string) -> number)? = nil  -- returns Tavern facility level

function RecruitmentService.SetGuildService(svc: any) _guildService = svc end
function RecruitmentService.SetPersistentStateService(svc: any) _persistentState = svc end
function RecruitmentService.SetCurrencyProvider(svc: any) _currency = svc end
function RecruitmentService.SetUnitFactory(fn: any) _unitFactory = fn end
function RecruitmentService.SetTavernLevelProvider(fn: ((string) -> number)?) _tavernLevelProvider = fn end

--------------------------------------------------
-- CURRENCY NOTE
--
-- As of Slice 6 Batch 1 there is NO gold balance store in the codebase
-- (RewardService documents that the gold/material/EXP grant paths are designed
-- in the DB but not yet built). RecruitmentService therefore reads/charges gold
-- through an INJECTED currency provider with this minimal contract:
--     currency.GetGold(playerId) -> number
--     currency.SpendGold(playerId, amount) -> boolean  (false if insufficient)
-- When the currency layer lands, wire it here. If no provider is injected,
-- ValidateHire reports the hire as blocked ("currency unavailable") and
-- CommitHire refuses — it NEVER silently hires for free.
--------------------------------------------------

local function getGold(playerId: string): number?
	if _currency and _currency.GetGold then
		return _currency.GetGold(playerId)
	end
	return nil
end

local function tavernLevel(playerId: string): number
	if _tavernLevelProvider then
		local lvl = _tavernLevelProvider(playerId)
		if type(lvl) == "number" then
			return math.clamp(math.floor(lvl), 0, TAVERN_MAX_LEVEL)
		end
	end
	return 0
end

--------------------------------------------------
-- COST RESOLUTION  (economy_framework id=22 — LOCKED)
--------------------------------------------------

function RecruitmentService.ResolveHireCost(unitLevel: number, quality: string): number
	local premium = QUALITY_PREMIUM[quality]
	if not premium then
		premium = QUALITY_PREMIUM.Standard
	end
	local lvl = math.max(1, math.floor(unitLevel or 1))
	return FEE_BASE + (lvl * FEE_PER_LEVEL) + premium
end

--------------------------------------------------
-- QUALITY TIER GATING (Tavern level — guild_facilities id=10)
--------------------------------------------------

local function allowedQualities(playerId: string): { string }
	local tl = tavernLevel(playerId)
	local list = { "Standard" }
	if tl >= TAVERN_QUALITY_LEVEL then
		table.insert(list, "Quality")
	end
	if tl >= TAVERN_ELITE_LEVEL then
		table.insert(list, "Elite")
	end
	return list
end

--------------------------------------------------
-- PRIMARY INTERFACE: GenerateRecruitPool
--
-- Deterministic given the same seed (combat is deterministic; generation uses
-- Roblox Random.new(seed) like ItemGenerator). Pool size = Tavern level,
-- bounded by REROLL_MAX_POOL_SIZE. Quality tiers available are gated by Tavern
-- level. Candidate attributes beyond quality/level (race, doctrine seed) are
-- produced by the injected unit factory later at hire time; the pool entry here
-- carries the fields needed for cost + eligibility: { candidateId, level,
-- quality, cost, seed }.
--
-- `context` (optional): { recommendedLevel? = number } used to center the
-- generated candidate levels on current content. If absent, falls back to the
-- player's Guild level as a reasonable, locked-value-free center.
--------------------------------------------------

function RecruitmentService.GenerateRecruitPool(playerId: string, seed: number, context: any)
	assert(type(playerId) == "string", "GenerateRecruitPool: playerId required")
	local poolSize = math.min(tavernLevel(playerId), REROLL_MAX_POOL_SIZE)
	if poolSize <= 0 then
		-- Tavern not built (Slice 8) — no recruits. This is intended, not a fault.
		return { pool = {}, poolSize = 0, reason = "Tavern not available" }
	end

	local rng = Random.new(seed or 0)
	local qualities = allowedQualities(playerId)

	-- Center candidate levels on content/Guild level WITHOUT inventing a spread
	-- rule: use a modest +/-2 band around the center. This affects only the
	-- generated candidate level (which feeds the LOCKED fee formula); it is a
	-- generation detail, not a balance rule, and does not alter any DB value.
	local center = 1
	if context and type(context.recommendedLevel) == "number" then
		center = math.max(1, math.floor(context.recommendedLevel))
	elseif _guildService and _guildService.GetGuildLevel then
		center = math.max(1, _guildService.GetGuildLevel(playerId))
	end

	local pool = {}
	for i = 1, poolSize do
		local level = math.max(1, center + rng:NextInteger(-2, 2))
		local quality = qualities[rng:NextInteger(1, #qualities)]
		local cost = RecruitmentService.ResolveHireCost(level, quality)
		table.insert(pool, {
			candidateId = string.format("recruit_%d_%d", seed or 0, i),
			level = level,
			quality = quality,
			cost = cost,
			seed = (seed or 0) + i,  -- per-candidate seed for the unit factory
		})
	end

	print(string.format("[RecruitmentService] Generated pool for %s | size %d | tiers %s",
		playerId, poolSize, table.concat(qualities, "/")))
	return { pool = pool, poolSize = poolSize }
end

--------------------------------------------------
-- ROSTER CAPACITY
--
-- Roster capacity is read, not owned. There is no hard roster cap locked for
-- recruitment in the DB (inventory has a soft maintenance threshold, not a hard
-- cap; the Tavern governs POOL size, not roster size). Capacity is therefore
-- supplied by the roster owner via an injected provider. If none is injected,
-- capacity is treated as unbounded and the "roster full" failure cannot trip —
-- which is honest, because no roster cap rule exists to enforce.
--------------------------------------------------

local _rosterCapacityProvider: ((string) -> (number?, number?))? = nil
-- provider returns (currentCount, maxCapacity); maxCapacity nil = unbounded

function RecruitmentService.SetRosterCapacityProvider(fn: ((string) -> (number?, number?))?)
	_rosterCapacityProvider = fn
end

local function rosterFull(playerId: string): boolean
	if not _rosterCapacityProvider then return false end
	local current, maxCap = _rosterCapacityProvider(playerId)
	if type(maxCap) == "number" and type(current) == "number" then
		return current >= maxCap
	end
	return false
end

--------------------------------------------------
-- PRIMARY INTERFACE: ValidateHire
--
-- Returns: ok(boolean), reason(string|nil), cost(number)
-- Checks (in order): candidate shape, quality tier allowed by Tavern level,
-- roster capacity, currency availability, sufficient gold. Charges NOTHING.
--------------------------------------------------

function RecruitmentService.ValidateHire(playerId: string, candidate: any)
	if type(candidate) ~= "table" or type(candidate.level) ~= "number" or type(candidate.quality) ~= "string" then
		return false, "Invalid candidate", 0
	end

	-- Quality tier must be unlocked at the current Tavern level.
	local allowed = allowedQualities(playerId)
	local qualityOk = false
	for _, q in allowed do
		if q == candidate.quality then qualityOk = true break end
	end
	if not qualityOk then
		return false, "Quality tier locked (Tavern level too low)", 0
	end

	local cost = RecruitmentService.ResolveHireCost(candidate.level, candidate.quality)

	-- Roster capacity (read-only).
	if rosterFull(playerId) then
		return false, "Roster full", cost
	end

	-- Currency availability + sufficiency.
	local gold = getGold(playerId)
	if gold == nil then
		return false, "Currency unavailable (no gold store wired)", cost
	end
	if gold < cost then
		return false, "Insufficient gold", cost
	end

	return true, nil, cost
end

--------------------------------------------------
-- PRIMARY INTERFACE: CommitHire
--
-- Atomic hire. Order of operations (failure boundary: no gold on failed hire):
--   1. Re-run ValidateHire. If it fails, return the failure. NOTHING charged.
--   2. Build the unit via the injected unit factory.
--   3. Register the unit on the EXISTING roster path
--      (PersistentStateService.RegisterNewUnit). This is the single roster
--      store — no second store is created.
--   4. Only AFTER registration succeeds, debit gold via currency.SpendGold.
--      If SpendGold fails (race), we do NOT leave a half-charged state: the
--      unit was registered but gold not taken is strictly player-favorable and
--      logged; we never charge without a unit, and never charge on a failed
--      hire.
--
-- Returns: ok(boolean), result(table|string)
--   result on success = { unitId, cost, candidate }
--------------------------------------------------

function RecruitmentService.CommitHire(playerId: string, candidate: any)
	local ok, reason, cost = RecruitmentService.ValidateHire(playerId, candidate)
	if not ok then
		print(string.format("[RecruitmentService] Hire REJECTED for %s | %s | (no gold charged)", playerId, tostring(reason)))
		return false, reason or "Hire rejected"
	end

	if not _persistentState or not _persistentState.RegisterNewUnit then
		-- Cannot reach the roster path — refuse rather than charge.
		return false, "Persistence/roster path not wired"
	end
	if not _unitFactory then
		return false, "Unit factory not wired"
	end

	-- Build the unit definition (race/doctrine/stats) via the authored factory.
	local unitDef = _unitFactory(candidate)
	if type(unitDef) ~= "table" or type(unitDef.id) ~= "string"
		or type(unitDef.maxHp) ~= "number" or type(unitDef.maxMp) ~= "number" then
		return false, "Unit factory returned invalid unit"
	end

	-- Register on the EXISTING roster path (the one Main.server.lua already uses).
	_persistentState.RegisterNewUnit(playerId, unitDef.id, unitDef.maxHp, unitDef.maxMp)

	-- Charge gold ONLY after the unit exists (atomic, player-favorable on race).
	if _currency and _currency.SpendGold then
		local spent = _currency.SpendGold(playerId, cost)
		if not spent then
			warn(string.format(
				"[RecruitmentService] Unit %s registered but gold debit raced for %s — unit kept, not charged",
				unitDef.id, playerId))
		end
	else
		warn("[RecruitmentService] No SpendGold wired — unit registered, gold NOT charged")
	end

	print(string.format("[RecruitmentService] HIRED %s (L%d %s) for %s | cost %dg",
		unitDef.id, candidate.level, candidate.quality, playerId, cost))

	return true, { unitId = unitDef.id, cost = cost, candidate = candidate }
end

return RecruitmentService
