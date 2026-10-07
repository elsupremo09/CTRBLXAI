--!strict
-- CurrencyService.lua
-- CTRBLXAI | Slice 6 — Currency & Materials Store (foundation for Base Mgmt)
--
-- OWNS (per service_boundaries 'Currency Service', LOCKED):
--   The player's running gold balance and the 5 material tier counters
--   (T1..T5). Atomic credit/debit transactions.
--
-- READS:
--   economy_framework (gold sources/sinks — amounts are passed IN by callers),
--   materials_system (counters, drop grants), save_data_contract Key 2.
--
-- WRITES:
--   Updated gold + material counts handed to the EXISTING persistence path
--   (SaveService Key 2 — Inventory + Currencies). It does NOT create a second
--   save store; Main.server.lua folds Export() into the Slice 4 Save call and
--   feeds the saved sub-table back via Import() on load — the same pattern
--   GuildService uses for Key 3.
--
-- MUST NOT OWN:
--   Reward generation, item generation, combat, or pricing formulas. This
--   service READS the amounts to charge from its callers; it never defines a
--   price, a drop amount, or a recipe.
--
-- PRIMARY INTERFACE (LOCKED):
--   GetBalance(playerId)                      -> { gold = n, materials = {1..5=n} }
--   CanAfford(playerId, cost)                 -> boolean
--   Credit(playerId, grant)                   -> newBalance        (add gold/materials)
--   Debit(playerId, cost)                     -> boolean, reason?  (atomic multi-cost)
--
--   `cost` / `grant` shape (either field optional):
--     { gold = number?, materials = { [tier:number(1..5)] = qty:number }? }
--
-- FAILURE BOUNDARY (LOCKED):
--   Debit is ALL-OR-NOTHING. If gold is insufficient OR any required material
--   tier is insufficient, the ENTIRE charge is cancelled — no partial spend.
--   A balance is never allowed to go negative.
--
-- STARTING BALANCE (LOCKED 2026-10-05):
--   economy_framework 'Starting Gold' now LOCKS the new-player starting gold:
--   "New players begin with 500 gold" (enough for one early hire or a cheap
--   purchase so shop/blacksmith are usable on a fresh save; trivial against
--   lifetime income). Materials still start at 0 (always earned, never granted
--   at start). STARTING_GOLD below is the single source of this number — read
--   verbatim from economy_framework; do not scatter or re-tune it.
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

local MATERIAL_TIERS = 5 -- materials_system id29: T1..T5 (5 integer counters)

--------------------------------------------------
-- STATE STORAGE
--   balances[playerId] = { gold = int, materials = { [1]=int, .. [5]=int } }
-- All values are non-negative integers at all times (invariant).
--------------------------------------------------

local balances: { [string]: { gold: number, materials: { [number]: number } } } = {}

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

local function isValidTier(tier: any): boolean
	return type(tier) == "number" and tier >= 1 and tier <= MATERIAL_TIERS and math.floor(tier) == tier
end

local function freshState()
	local mats: { [number]: number } = {}
	for t = 1, MATERIAL_TIERS do
		mats[t] = 0
	end
	return { gold = STARTING_GOLD, materials = mats }
end

local function stateOf(playerId: string)
	local s = balances[playerId]
	if not s then
		s = freshState()
		balances[playerId] = s
	end
	-- Defensive: ensure all 5 counters exist even if an old import was partial.
	for t = 1, MATERIAL_TIERS do
		if type(s.materials[t]) ~= "number" then
			s.materials[t] = 0
		end
	end
	return s
end

--------------------------------------------------
-- PLAYER LIFECYCLE
--------------------------------------------------

-- Called when a player joins (before Import). A brand-new player starts at
-- STARTING_GOLD and zero materials.
function CurrencyService.InitPlayer(playerId: string)
	assert(type(playerId) == "string", "CurrencyService.InitPlayer: playerId required")
	if not balances[playerId] then
		balances[playerId] = freshState()
		print(string.format("[CurrencyService] Init %s | gold %d (starting) | materials 0×%d",
			playerId, STARTING_GOLD, MATERIAL_TIERS))
	end
end

function CurrencyService.ClearPlayer(playerId: string)
	balances[playerId] = nil
end

--------------------------------------------------
-- PRIMARY INTERFACE: GetBalance
--
-- Returns a COPY of the player's balance (callers cannot mutate internal
-- state by holding the returned table).
--   { gold = n, materials = { [1]=n, [2]=n, [3]=n, [4]=n, [5]=n } }
--------------------------------------------------

function CurrencyService.GetBalance(playerId: string)
	local s = stateOf(playerId)
	local matsCopy: { [number]: number } = {}
	for t = 1, MATERIAL_TIERS do
		matsCopy[t] = s.materials[t]
	end
	return { gold = s.gold, materials = matsCopy }
end

--------------------------------------------------
-- PRIMARY INTERFACE: CanAfford
--
-- Read-only. Returns true only if EVERY component of `cost` is satisfied:
-- the gold line AND every material tier line. Charges nothing.
--   cost = { gold = number?, materials = { [tier] = qty }? }
--------------------------------------------------

function CurrencyService.CanAfford(playerId: string, cost: any): boolean
	if type(cost) ~= "table" then
		return false
	end
	local s = stateOf(playerId)

	-- Gold line.
	local needGold = toNonNegInt(cost.gold)
	if s.gold < needGold then
		return false
	end

	-- Material lines (all tiers must be satisfied).
	if type(cost.materials) == "table" then
		for tier, qty in cost.materials do
			if not isValidTier(tier) then
				-- Unknown tier requested — cannot be satisfied.
				return false
			end
			local need = toNonNegInt(qty)
			if s.materials[tier] < need then
				return false
			end
		end
	end

	return true
end

--------------------------------------------------
-- PRIMARY INTERFACE: Credit
--
-- Adds gold and/or materials. Credit is always safe (no negative result
-- possible). Amounts are coerced to non-negative integers. The amount comes
-- from the caller (e.g. the reward grant path) — this service does not decide
-- how much to grant.
--   grant = { gold = number?, materials = { [tier] = qty }? }
-- Returns the new balance (same shape as GetBalance).
--------------------------------------------------

function CurrencyService.Credit(playerId: string, grant: any)
	local s = stateOf(playerId)
	if type(grant) ~= "table" then
		return CurrencyService.GetBalance(playerId)
	end

	local addGold = toNonNegInt(grant.gold)
	if addGold > 0 then
		s.gold += addGold
	end

	if type(grant.materials) == "table" then
		for tier, qty in grant.materials do
			if isValidTier(tier) then
				local add = toNonNegInt(qty)
				if add > 0 then
					s.materials[tier] += add -- materials_system id31: no cap
				end
			else
				warn(string.format("[CurrencyService] Credit ignored unknown material tier %s for %s",
					tostring(tier), playerId))
			end
		end
	end

	return CurrencyService.GetBalance(playerId)
end

--------------------------------------------------
-- PRIMARY INTERFACE: Debit  (atomic multi-cost — LOCKED failure boundary)
--
-- Charges gold AND materials together, all-or-nothing. If the full cost cannot
-- be met, NOTHING is deducted and the balance is unchanged (no partial spend;
-- balance never goes negative).
--   cost = { gold = number?, materials = { [tier] = qty }? }
-- Returns: ok(boolean), reason(string|nil)
--------------------------------------------------

function CurrencyService.Debit(playerId: string, cost: any): (boolean, string?)
	if type(cost) ~= "table" then
		return false, "Invalid cost"
	end

	-- Check EVERYTHING first (atomic): if any line fails, charge nothing.
	if not CurrencyService.CanAfford(playerId, cost) then
		-- Distinguish the reason for logging/UX without leaking partial state.
		local s = stateOf(playerId)
		local needGold = toNonNegInt(cost.gold)
		if s.gold < needGold then
			return false, "Insufficient gold"
		end
		return false, "Insufficient materials"
	end

	local s = stateOf(playerId)

	-- Apply gold.
	local spendGold = toNonNegInt(cost.gold)
	if spendGold > 0 then
		s.gold -= spendGold
		if s.gold < 0 then
			-- Should be impossible after CanAfford, but enforce the invariant.
			s.gold = 0
		end
	end

	-- Apply materials.
	if type(cost.materials) == "table" then
		for tier, qty in cost.materials do
			if isValidTier(tier) then
				local spend = toNonNegInt(qty)
				if spend > 0 then
					s.materials[tier] -= spend
					if s.materials[tier] < 0 then
						s.materials[tier] = 0
					end
				end
			end
		end
	end

	return true, nil
end

--------------------------------------------------
-- CURRENCY-PROVIDER ADAPTER
--
-- The already-shipped batch-1 services (RecruitmentService, BlacksmithService)
-- expect an injected `_currency` object with the method names below. This
-- adapter exposes that exact contract on top of the locked interface above so
-- those services wire in with NO change to their code:
--     GetGold(playerId)                 -> number
--     SpendGold(playerId, amount)       -> boolean
--     AddGold(playerId, amount)         -> number (new gold)   [Blacksmith refund]
--     GetMaterial(playerId, tier)       -> number
--     SpendMaterials(playerId, {[tier]=qty}) -> boolean
--
-- Usage in Main.server.lua:
--     RecruitmentService.SetCurrencyProvider(CurrencyService.AsProvider())
--     BlacksmithService.SetCurrencyProvider(CurrencyService.AsProvider())
--------------------------------------------------

local _provider: any = nil

function CurrencyService.AsProvider()
	if _provider then
		return _provider
	end

	_provider = {
		GetGold = function(playerId: string): number
			return CurrencyService.GetBalance(playerId).gold
		end,

		SpendGold = function(playerId: string, amount: number): boolean
			local ok = CurrencyService.Debit(playerId, { gold = toNonNegInt(amount) })
			return ok
		end,

		AddGold = function(playerId: string, amount: number): number
			local bal = CurrencyService.Credit(playerId, { gold = toNonNegInt(amount) })
			return bal.gold
		end,

		GetMaterial = function(playerId: string, tier: number): number
			if not isValidTier(tier) then
				return 0
			end
			return CurrencyService.GetBalance(playerId).materials[tier]
		end,

		SpendMaterials = function(playerId: string, materials: { [number]: number }): boolean
			local ok = CurrencyService.Debit(playerId, { materials = materials })
			return ok
		end,
	}

	return _provider
end

--------------------------------------------------
-- SAVE INTEGRATION (SaveService Key 2 — Inventory + Currencies)
--
-- CurrencyService does NOT touch DataStore. Main.server.lua folds Export() into
-- the Slice 4 Save call (as the Key 2 `currencies` sub-table) and feeds the
-- saved sub-table back via Import() on load. This reuses the Slice 4 contract
-- rather than creating a second store (save_data_contract: 3 keys, Key 2 holds
-- currencies; materials_system id30: Key 2 alongside gold, 5 integers).
--
-- Export shape (compact — one int for gold, 5 ints for materials):
--   { gold = int, mats = { int, int, int, int, int } }   -- array index == tier
--------------------------------------------------

function CurrencyService.Export(playerId: string)
	local s = stateOf(playerId)
	local mats: { number } = {}
	for t = 1, MATERIAL_TIERS do
		mats[t] = s.materials[t]
	end
	return { gold = s.gold, mats = mats }
end

function CurrencyService.Import(playerId: string, data: any)
	CurrencyService.InitPlayer(playerId)
	if type(data) ~= "table" then
		-- No saved currency section (e.g. pre-currency save or new player):
		-- keep the freshly-initialised starting balance. Do NOT invent values.
		return
	end
	local s = balances[playerId]

	-- Gold (nonnegative integer — save_data_contract Load_Validation).
	s.gold = toNonNegInt(data.gold)

	-- Materials: accept the compact array ({ [1..5] = int }). Any missing tier
	-- stays 0. Tolerate a dictionary form too, for forward-compat.
	local mats = data.mats or data.materials
	if type(mats) == "table" then
		for t = 1, MATERIAL_TIERS do
			s.materials[t] = toNonNegInt(mats[t])
		end
	else
		for t = 1, MATERIAL_TIERS do
			s.materials[t] = 0
		end
	end

	print(string.format("[CurrencyService] Imported %s | gold %d | materials %d/%d/%d/%d/%d",
		playerId, s.gold, s.materials[1], s.materials[2], s.materials[3], s.materials[4], s.materials[5]))
end

--------------------------------------------------
-- DEBUG
--------------------------------------------------

function CurrencyService.Describe(playerId: string): string
	local s = stateOf(playerId)
	return string.format("gold:%d T1:%d T2:%d T3:%d T4:%d T5:%d",
		s.gold, s.materials[1], s.materials[2], s.materials[3], s.materials[4], s.materials[5])
end

return CurrencyService
