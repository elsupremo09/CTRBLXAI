--!strict
-- CurrencyService.lua
-- CTRBLXAI | Slice 6 — Currency & Materials Store (foundation for Base Mgmt)
--
-- OWNS (per service_boundaries 'Currency Service', LOCKED; v2 USER DECISION 2026-11-01):
--   The player's gold, the 3 resource counters (mercury, crystals, sulfur), the rune gem
--   storage (count per gem ID) and the lifetime daily-event counter (materials_system
--   1-5, 29; save_data_contract 3). Atomic credit/debit transactions.
--
-- READS:
--   economy_framework (gold sources/sinks — amounts are passed IN by callers),
--   materials_system (resources), save_data_contract Key 2.
--
-- WRITES:
--   Updated balances handed to the EXISTING persistence path (SaveService Key 2 —
--   Inventory + Currencies). It does NOT create a second save store; Main.server.lua
--   folds Export() into the Save call and feeds the saved sub-table back via Import().
--
-- MUST NOT OWN:
--   Reward generation, item generation, combat, or pricing formulas. This service
--   READS the amounts to charge from its callers; it never defines a price, a drop
--   amount, or a recipe.
--
-- PRIMARY INTERFACE (LOCKED):
--   GetBalance(playerId) -> { gold, mercury, crystals, sulfur, gems = { [gemId] = n },
--                             dailyEventsCompleted }
--   CanAfford(playerId, cost)                 -> boolean
--   Credit(playerId, grant)                   -> newBalance
--   Debit(playerId, cost)                     -> boolean, reason?  (atomic multi-cost)
--
--   `cost` / `grant` shape (every field optional):
--     { gold = n?, mercury = n?, crystals = n?, sulfur = n?, gems = { [gemId] = n }? }
--   The old `materials` (T1-T5) and `essences` fields are REMOVED (v2): a cost that
--   still uses them is refused, a grant that uses them is ignored with a warning.
--
-- FAILURE BOUNDARY (LOCKED):
--   Debit is ALL-OR-NOTHING. If any part of the cost cannot be paid, NOTHING is
--   deducted. A balance is never allowed to go negative.
--
-- STARTING BALANCE (LOCKED 2026-10-05):
--   "New players begin with 500 gold". Resources start at 0 (always earned, never
--   granted at start). STARTING_GOLD below is the single source of this number.
--
-- ─────────────────────────────────────────────────────────────────────────
-- DEPENDENCIES ARE INJECTED (dependency injection, not require) so this module
-- never forms a circular require with the persistence layer. There are no hard
-- requires here at all — the store is self-contained in-memory state plus the
-- Export/Import hooks the orchestrator calls.

local CurrencyService = {}

--------------------------------------------------
-- CONSTANTS
--------------------------------------------------

-- LOCKED (economy_framework 'Starting Gold', 2026-10-05): new players begin
-- with 500 gold. Materials still start at 0 (materials_system id31: no cap,
-- always earned, never granted at start). This is the single source of the
-- number — do not scatter it.
local STARTING_GOLD = 500

-- Rune gem IDs are content IDs (a numeric attribute ID such as "NUM-WEAPONATTACK-1",
-- or a passive ID such as "PAS-049"); materials_system 4. Length guard only (SEC-001:
-- never trust a shape); content validity is checked where gems are used.
local MAX_GEM_ID_LEN = 64

-- materials_system 6 (v2): old saves stored 5 gear tiers; they convert to mercury 1:1.
local LEGACY_MATERIAL_TIERS = 5

--------------------------------------------------
-- STATE STORAGE
--   balances[playerId] = { gold, mercury, crystals, sulfur, gems = { [gemId] = int },
--                          dailyEventsCompleted }
-- All values are non-negative integers at all times (invariant).
--------------------------------------------------

type Balance = {
	gold: number,
	mercury: number,
	crystals: number,
	sulfur: number,
	gems: { [string]: number },
	dailyEventsCompleted: number,
}

local balances: { [string]: Balance } = {}

--------------------------------------------------
-- INTERNAL HELPERS
--------------------------------------------------

-- Coerce any numeric input to a non-negative integer. Guards against floats and
-- negatives being injected by a caller (NET/SEC: never trust the amount shape).
local function toNonNegInt(n: any): number
	if type(n) ~= "number" then
		return 0
	end
	if n ~= n then -- NaN
		return 0
	end
	local i = math.floor(n)
	if i < 0 then
		return 0
	end
	return i
end

local function isValidGemId(id: any): boolean
	return type(id) == "string" and #id > 0 and #id <= MAX_GEM_ID_LEN
end

local function usesRemovedFields(t: any): boolean
	return t.materials ~= nil or t.essences ~= nil
end

local function freshState(): Balance
	return { gold = STARTING_GOLD, mercury = 0, crystals = 0, sulfur = 0, gems = {}, dailyEventsCompleted = 0 }
end

local function stateOf(playerId: string): Balance
	local s = balances[playerId]
	if not s then
		s = freshState()
		balances[playerId] = s
	end
	return s
end

--------------------------------------------------
-- PLAYER LIFECYCLE
--------------------------------------------------

-- Called when a player joins (before Import). A brand-new player starts at
-- STARTING_GOLD and zero resources.
function CurrencyService.InitPlayer(playerId: string)
	assert(type(playerId) == "string", "CurrencyService.InitPlayer: playerId required")
	if not balances[playerId] then
		balances[playerId] = freshState()
		print(string.format("[CurrencyService] Init %s | gold %d (starting) | mercury 0 | crystals 0 | sulfur 0",
			playerId, STARTING_GOLD))
	end
end

function CurrencyService.ClearPlayer(playerId: string)
	balances[playerId] = nil
end

--------------------------------------------------
-- PRIMARY INTERFACE: GetBalance
-- Returns a COPY (callers cannot mutate internal state by holding it).
--------------------------------------------------

function CurrencyService.GetBalance(playerId: string)
	local s = stateOf(playerId)
	return {
		gold = s.gold,
		mercury = s.mercury,
		crystals = s.crystals,
		sulfur = s.sulfur,
		gems = table.clone(s.gems),
		dailyEventsCompleted = s.dailyEventsCompleted,
	}
end

--------------------------------------------------
-- PRIMARY INTERFACE: CanAfford
-- Read-only. True only if EVERY part of `cost` can be paid. Charges nothing.
--------------------------------------------------

function CurrencyService.CanAfford(playerId: string, cost: any): boolean
	if type(cost) ~= "table" then
		return false
	end
	if usesRemovedFields(cost) then
		warn(`[CurrencyService] CanAfford refused a cost using removed fields (materials/essences) for {playerId}`)
		return false
	end
	local s = stateOf(playerId)
	if s.gold < toNonNegInt(cost.gold) then return false end
	if s.mercury < toNonNegInt(cost.mercury) then return false end
	if s.crystals < toNonNegInt(cost.crystals) then return false end
	if s.sulfur < toNonNegInt(cost.sulfur) then return false end
	if type(cost.gems) == "table" then
		for id, qty in cost.gems do
			if not isValidGemId(id) then
				return false
			end
			if (s.gems[id] or 0) < toNonNegInt(qty) then
				return false
			end
		end
	end
	return true
end

--------------------------------------------------
-- PRIMARY INTERFACE: Credit
-- Adds gold and/or resources. Always safe (no negative result possible). The amount
-- comes from the caller — this service does not decide how much to grant.
-- Returns the new balance (same shape as GetBalance).
--------------------------------------------------

function CurrencyService.Credit(playerId: string, grant: any)
	local s = stateOf(playerId)
	if type(grant) ~= "table" then
		return CurrencyService.GetBalance(playerId)
	end
	if usesRemovedFields(grant) then
		warn(`[CurrencyService] Credit ignored removed fields (materials/essences) for {playerId}`)
	end
	-- materials_system 31: no cap on any resource.
	s.gold += toNonNegInt(grant.gold)
	s.mercury += toNonNegInt(grant.mercury)
	s.crystals += toNonNegInt(grant.crystals)
	s.sulfur += toNonNegInt(grant.sulfur)
	if type(grant.gems) == "table" then
		for id, qty in grant.gems do
			if isValidGemId(id) then
				local add = toNonNegInt(qty)
				if add > 0 then
					s.gems[id] = (s.gems[id] or 0) + add
				end
			else
				warn(`[CurrencyService] Credit ignored an invalid rune gem id {tostring(id)} for {playerId}`)
			end
		end
	end
	return CurrencyService.GetBalance(playerId)
end

--------------------------------------------------
-- PRIMARY INTERFACE: Debit  (atomic multi-cost — LOCKED failure boundary)
-- Charges every part together, all-or-nothing.
-- Returns: ok(boolean), reason(string|nil)
--------------------------------------------------

function CurrencyService.Debit(playerId: string, cost: any): (boolean, string?)
	if type(cost) ~= "table" or usesRemovedFields(cost) then
		return false, "Invalid cost"
	end

	-- Check EVERYTHING first (atomic): if any line fails, charge nothing.
	local s = stateOf(playerId)
	if not CurrencyService.CanAfford(playerId, cost) then
		if s.gold < toNonNegInt(cost.gold) then return false, "Insufficient gold" end
		if s.mercury < toNonNegInt(cost.mercury) then return false, "Not enough mercury" end
		if s.crystals < toNonNegInt(cost.crystals) then return false, "Not enough crystals" end
		if s.sulfur < toNonNegInt(cost.sulfur) then return false, "Not enough sulfur" end
		return false, "Not enough rune gems"
	end

	s.gold = math.max(0, s.gold - toNonNegInt(cost.gold))
	s.mercury = math.max(0, s.mercury - toNonNegInt(cost.mercury))
	s.crystals = math.max(0, s.crystals - toNonNegInt(cost.crystals))
	s.sulfur = math.max(0, s.sulfur - toNonNegInt(cost.sulfur))
	if type(cost.gems) == "table" then
		for id, qty in cost.gems do
			local left = (s.gems[id] or 0) - toNonNegInt(qty)
			s.gems[id] = if left > 0 then left else nil
		end
	end
	return true, nil
end

--------------------------------------------------
-- CURRENCY-PROVIDER ADAPTER
--
-- Services that get an injected `_currency` object (Recruitment, Blacksmith, Merchant,
-- Dispatch, Explore) use these names:
--     GetGold(playerId)            -> number
--     SpendGold(playerId, amount)  -> boolean
--     AddGold(playerId, amount)    -> number (new gold)
--     GetMercury(playerId)         -> number
--     CanAfford(playerId, cost)    -> boolean          (full cost shape, see header)
--     Debit(playerId, cost)        -> boolean, reason? (atomic, see header)
--     Credit(playerId, grant)      -> new balance      (full grant shape, see header)
-- (GetMaterial / SpendMaterials were removed with the T1-T5 tiers, v2 2026-11-01.)
--------------------------------------------------

local _provider: any = nil

function CurrencyService.AsProvider()
	if _provider then
		return _provider
	end

	_provider = {
		GetGold = function(playerId: string): number
			return stateOf(playerId).gold
		end,

		SpendGold = function(playerId: string, amount: number): boolean
			local ok = CurrencyService.Debit(playerId, { gold = toNonNegInt(amount) })
			return ok
		end,

		AddGold = function(playerId: string, amount: number): number
			local bal = CurrencyService.Credit(playerId, { gold = toNonNegInt(amount) })
			return bal.gold
		end,

		GetMercury = function(playerId: string): number
			return stateOf(playerId).mercury
		end,

		CanAfford = function(playerId: string, cost: any): boolean
			return CurrencyService.CanAfford(playerId, cost)
		end,

		Debit = function(playerId: string, cost: any): (boolean, string?)
			return CurrencyService.Debit(playerId, cost)
		end,

		Credit = function(playerId: string, grant: any)
			return CurrencyService.Credit(playerId, grant)
		end,
	}

	return _provider
end

--------------------------------------------------
-- SAVE INTEGRATION (SaveService Key 2 — Inventory + Currencies)
--
-- Export shape (compact):
--   { gold = int, mer = int, cry = int, sul = int, gem = { [gemId] = int }, dec = int }
-- Saves from before v2 have `mats` (5 tier counts) and maybe `ess` (3 Essences) and no
-- `mer`: Import turns T1+T2+T3+T4+T5 into mercury 1:1 and drops the Essences
-- (materials_system 6, save_data_contract 3). The next save writes the new shape.
--------------------------------------------------

function CurrencyService.Export(playerId: string)
	local s = stateOf(playerId)
	local gems: { [string]: number } = {}
	for id, count in s.gems do
		if count > 0 then
			gems[id] = count
		end
	end
	return {
		gold = s.gold,
		mer = s.mercury,
		cry = s.crystals,
		sul = s.sulfur,
		gem = gems,
		dec = s.dailyEventsCompleted,
	}
end

function CurrencyService.Import(playerId: string, data: any)
	CurrencyService.InitPlayer(playerId)
	if type(data) ~= "table" then
		-- No saved currency section (e.g. new player): keep the starting balance.
		-- Do NOT invent values.
		return
	end
	local s = stateOf(playerId)

	-- Gold (nonnegative integer — save_data_contract Load_Validation).
	s.gold = toNonNegInt(data.gold)

	if data.mer ~= nil then
		s.mercury = toNonNegInt(data.mer)
	else
		local mats = data.mats or data.materials
		local total = 0
		if type(mats) == "table" then
			for t = 1, LEGACY_MATERIAL_TIERS do
				total += toNonNegInt(mats[t])
			end
		end
		s.mercury = total
		if total > 0 or type(data.ess) == "table" then
			print(`[CurrencyService] Converted old materials for {playerId}: T1-T5 total {total} -> {total} mercury; Essences removed`)
		end
	end
	s.crystals = toNonNegInt(data.cry)
	s.sulfur = toNonNegInt(data.sul)

	table.clear(s.gems)
	if type(data.gem) == "table" then
		for id, count in data.gem do
			if isValidGemId(id) then
				local c = toNonNegInt(count)
				if c > 0 then
					s.gems[id] = c
				end
			else
				warn(`[CurrencyService] Import dropped an invalid rune gem id {tostring(id)} for {playerId}`)
			end
		end
	end
	s.dailyEventsCompleted = toNonNegInt(data.dec)

	local kinds = 0
	for _ in s.gems do kinds += 1 end
	print(string.format("[CurrencyService] Imported %s | gold %d | mercury %d | crystals %d | sulfur %d | rune gem kinds %d | daily events %d",
		playerId, s.gold, s.mercury, s.crystals, s.sulfur, kinds, s.dailyEventsCompleted))
end

--------------------------------------------------
-- DEBUG
--------------------------------------------------

function CurrencyService.Describe(playerId: string): string
	local s = stateOf(playerId)
	local kinds = 0
	for _ in s.gems do kinds += 1 end
	return string.format("gold:%d mercury:%d crystals:%d sulfur:%d gemKinds:%d dailyEvents:%d",
		s.gold, s.mercury, s.crystals, s.sulfur, kinds, s.dailyEventsCompleted)
end

return CurrencyService
