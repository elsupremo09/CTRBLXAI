--!strict
-- DispatchRtRules.lua
-- CTRBLXAI | real-time Dispatch numbers + pure math (real-time Dispatch build step 2, 2026-11-19).
--
-- SERVER ONLY. Data copied from CTRBLXAI.db (one data domain per file, DAT-003; frozen, DAT-002):
--   unit_progression 77  earning limit by Dispatch level, earned time = min(now - lastCollectAt, limit)
--   unit_progression 78  EXP per unit per hour = [Fixed(T) + Pct(T) x EXP-to-next] x (1 + 3% per level above L1),
--                        worked out hour by hour as the unit levels up, never past level 99
--   unit_progression 99  tiers: minimum time / unlock level; units per mission; item rewards
--   unit_progression 106 recall before the minimum = 25% of the EXP earned, no materials, no items
--   materials_system 12  material per mission per hour; crystals from L5, sulfur from L7; L8 +25% incl. mercury
--   guild_facilities 116 the level ladder;  economy_framework 26 slots + 50 gold fee
-- Item chances (PROPOSAL_dispatch_realtime_v2_20261119.md section 3, approved 2026-11-19 2:43 PM):
--   consumables T x 0.4% per hour (L3+, up to Uncommon), skill cards T x 0.2% per hour (L6+, Rare),
--   gear T x 0.2% per hour (L9+; T3 Common, T4 Uncommon, T5 Rare, Epic possible from T5 at L10).
-- No Fortune anywhere in dispatch.
--
-- RATES (user rule 2026-11-19 9:21 PM; NO daily cap, user 2026-11-20 12:53 AM):
--   * A mission earns continuously in real time (online or offline) until the Dispatch level's
--     earning limit (3..24 h) is reached, then stops until collected. Collecting restarts it.
--     Earned seconds = min(now - lastCollectAt, earning limit). Nothing else limits hours.
--   * Anchor: battles = 2.5 Mercury and 25% of a level per hour. Dispatch earns 25% of that at
--     L1 T1 up to 75% at L10 T5: share = level multiplier (25% -> 50%, L1-L10) x tier
--     (T1 1.0, T2 1.1, T3 1.25, T4 1.4, T5 1.5). Table: SIM_dispatch_user_anchor_20261119.md.
--     Crystals / rune gems scale the same way from battle drops (0.543 crystals, 0.331 gems per
--     battle, materials_system 36; 4 battles per 2 h on the user's anchor).
--   * EXP per hour = fixed (5 x tier) + pct% of next level (pct = the cell's EXP % minus 1 point,
--     the "fixed + %" display shape from the same report).
--   * The table already includes the Dispatch level (no extra multiplier, no L8 material bonus).
--   * Sulfur is not a mission material: 1 sulfur per server week from Dispatch L7 (first collect).
--   * Material gating (guild_facilities 116): rune gems on T3-T5, crystals on T4-T5 (from L5).

local R = {}

R.MAX_LEVEL = 10
R.MIN_TIER, R.MAX_TIER = 1, 5
R.FEE_GOLD = 50                -- economy_framework 26 (no fee cut by level)
R.SLOT_CAP = 6                 -- Rank 3 + level 2 + the Robux slot 1 (economy_framework 26/34)
R.EARLY_RECALL_XP_MULT = 0.25  -- unit_progression 106
R.WEEK_SECONDS = 604800
-- Weekly sulfur week starts Monday 00:00 Asia/Manila = Sunday 16:00 UTC (user ruling 2026-11-19 10:37 PM).
-- os.time 0 is Thursday 1970-01-01 00:00 UTC; 1970-01-04 16:00 UTC = 3 days + 16 h = 316800 s.
R.SULFUR_WEEK_ANCHOR = 316800
-- L8 perk (agent default 2026-11-19, user may veto): T4 and T5 minimum times 1 hour shorter from L8.
R.MIN_SHORTER_LEVEL = 8
R.MIN_SHORTER_TIERS = table.freeze({ [4] = true, [5] = true })
R.MIN_SHORTER_HOURS = 1
R.SULFUR_WEEKLY_LEVEL = 7       -- materials_system 12: 1 sulfur per week from L7
R.SULFUR_WEEKLY_AMOUNT = 1
R.EPIC_GEAR_LEVEL = 10         -- T5 gear can be Epic from L10
-- Rare vs Epic split for that roll: the Elite-encounter table's Rare 0.18163636 vs Epic 0.06962727
-- (RewardService ELITE_RARITY_WEIGHTS), so Epic = 27.7%. Builder default 2026-11-19 (not in the DB).
R.EPIC_GEAR_CHANCE = 0.06962727 / (0.18163636 + 0.06962727)

-- Earning limit in hours by Dispatch level L1-L10 (unit_progression 77).
R.EARN_LIMIT_HOURS = table.freeze({ 3, 4, 5, 6, 8, 10, 12, 16, 20, 24 })

-- Tiers (unit_progression 78/99). minHours = minimum time out; unlock = Dispatch level.
R.TIERS = table.freeze({
	table.freeze({ tier = 1, minHours = 1,  unlock = 1 }),
	table.freeze({ tier = 2, minHours = 2,  unlock = 2 }),
	table.freeze({ tier = 3, minHours = 4,  unlock = 3 }),
	table.freeze({ tier = 4, minHours = 6,  unlock = 5 }),
	table.freeze({ tier = 5, minHours = 10, unlock = 7 }),
})

-- Approved table (materials_system 12), one cell per Dispatch level x unlocked tier:
--   share = % of battle income per hour; mercury / crystals / gems = minutes per whole unit;
--   fixed + pct = EXP per hour per unit ("fixed + pct% of next level").
local function cell(share: number, mercury: number, crystals: number, gems: number, fixed: number, pct: number)
	return table.freeze({ share = share, minutes = table.freeze({ mercury = mercury, crystals = crystals, gems = gems }),
		fixed = fixed, pct = pct / 100 })
end
R.RATE_TABLE = table.freeze({
	[1] = table.freeze({ [1] = cell(25, 96, 221, 363, 5, 5.3) }),
	[2] = table.freeze({ [1] = cell(28, 86, 199, 326, 5, 5.9), [2] = cell(31, 79, 181, 297, 10, 6.6) }),
	[3] = table.freeze({ [1] = cell(31, 79, 181, 297, 5, 6.6), [2] = cell(34, 71, 164, 270, 10, 7.4), [3] = cell(38, 63, 145, 237, 15, 8.6) }),
	[4] = table.freeze({ [1] = cell(33, 72, 166, 272, 5, 7.3), [2] = cell(37, 65, 151, 247, 10, 8.2), [3] = cell(42, 58, 133, 218, 15, 9.4) }),
	[5] = table.freeze({ [1] = cell(36, 66, 153, 251, 5, 8.0), [2] = cell(40, 60, 139, 228, 10, 8.9), [3] = cell(45, 53, 122, 201, 15, 10.3), [4] = cell(51, 47, 109, 179, 20, 11.6) }),
	[6] = table.freeze({ [1] = cell(39, 62, 142, 233, 5, 8.7), [2] = cell(43, 56, 129, 212, 10, 9.7), [3] = cell(49, 49, 114, 187, 15, 11.2), [4] = cell(54, 44, 101, 167, 20, 12.6) }),
	[7] = table.freeze({ [1] = cell(42, 58, 133, 218, 5, 9.4), [2] = cell(46, 52, 121, 198, 10, 10.5), [3] = cell(52, 46, 106, 174, 15, 12.0), [4] = cell(58, 41, 95, 155, 20, 13.6), [5] = cell(62, 38, 88, 145, 25, 14.6) }),
	[8] = table.freeze({ [1] = cell(44, 54, 124, 204, 5, 10.1), [2] = cell(49, 49, 113, 185, 10, 11.2), [3] = cell(56, 43, 99, 163, 15, 12.9), [4] = cell(62, 39, 89, 146, 20, 14.6), [5] = cell(67, 36, 83, 136, 25, 15.7) }),
	[9] = table.freeze({ [1] = cell(47, 51, 117, 192, 5, 10.8), [2] = cell(52, 46, 106, 175, 10, 12.0), [3] = cell(59, 41, 94, 154, 15, 13.8), [4] = cell(66, 36, 84, 137, 20, 15.5), [5] = cell(71, 34, 78, 128, 25, 16.7) }),
	[10] = table.freeze({ [1] = cell(50, 48, 111, 181, 5, 11.5), [2] = cell(55, 44, 100, 165, 10, 12.8), [3] = cell(62, 38, 88, 145, 15, 14.6), [4] = cell(70, 34, 79, 130, 20, 16.5), [5] = cell(75, 32, 74, 121, 25, 17.75) }),
})
-- Mission materials (materials_system 12): which tiers may run them, from which Dispatch level.
-- Rates are in RATE_TABLE. Sulfur is NOT a mission material any more (weekly bonus, see above).
R.MATERIALS = table.freeze({
	mercury  = table.freeze({ minLevel = 1, tiers = table.freeze({ [1] = true, [2] = true, [3] = true, [4] = true, [5] = true }) }),
	gems     = table.freeze({ minLevel = 1, tiers = table.freeze({ [3] = true, [4] = true, [5] = true }) }),
	crystals = table.freeze({ minLevel = 5, tiers = table.freeze({ [4] = true, [5] = true }) }),
})
R.NO_MATERIAL = "none" -- an EXP / item mission (one material mission at a time, materials_system 12)
R.MATERIAL_ORDER = table.freeze({ "mercury", "gems", "crystals" })

-- Item rewards: per hour chance = tier x perTier, from minLevel (see header).
R.ITEMS = table.freeze({
	table.freeze({ kind = "consumable", minLevel = 3, perTier = 0.004 }),
	table.freeze({ kind = "card",       minLevel = 6, perTier = 0.002 }),
	table.freeze({ kind = "gear",       minLevel = 9, perTier = 0.002 }),
})
R.CONSUMABLE_MAX_RARITY = "Uncommon"
R.CARD_RARITY = "Rare"
-- Gear rarity by tier (unit_progression 99: T3 Common, T4 Uncommon, T5 Rare). T1-T2 are not named in
-- the DB; builder default: Common (the lowest), 2026-11-19.
R.GEAR_RARITY_BY_TIER = table.freeze({ "Common", "Common", "Common", "Uncommon", "Rare" })

-- YIELD MULTIPLIER (user-approved 2026-11-21 11:27 AM, option N1; SIM_dispatch_team_level_20261121.md
-- section 1, proposed DB row materials_system 43). Applied as "today's payout x mult", so the rate table
-- above is NOT changed:
--   mult = teamSize(n) / teamSize(units per mission at send)  x  levelFactor  x  (1 + perkBonus)
--   teamSize(n): 1.00 / 1.25 / 1.45 / 1.60 / 1.70 (n = units sent; a full team pays exactly today's rate)
--   levelFactor = clamp(1 - 0.04 x deficit, 0.60, 1.00); deficit = average level of the player's top-n
--     owned units (away ones count) minus the sent team's average level. No bonus above 1.
--   perkBonus = sum of the sent units' dispatch perks, clamped -0.30..+0.30 (none exist yet).
R.TEAM_SIZE_STEPS = table.freeze({ 1.00, 1.25, 1.45, 1.60, 1.70 })
R.LEVEL_FACTOR_PER_LEVEL = 0.04
R.LEVEL_FACTOR_MIN, R.LEVEL_FACTOR_MAX = 0.60, 1.00
R.PERK_BONUS_MIN, R.PERK_BONUS_MAX = -0.30, 0.30
R.YIELD_MULT_MAX = 1.30 -- hard cap under N1 (full team x 1.00 x 1.30)

local function clampInt(n: any, lo: number, hi: number, fallback: number): number
	local v = tonumber(n)
	if v == nil or v ~= v then return fallback end
	return math.clamp(math.floor(v), lo, hi)
end

function R.ClampLevel(level: any): number
	return clampInt(level, 1, R.MAX_LEVEL, 1)
end

function R.Tier(tier: any): any?
	local t = tonumber(tier)
	if t == nil or t ~= math.floor(t) or t < R.MIN_TIER or t > R.MAX_TIER then return nil end
	return R.TIERS[t]
end

-- Minimum hours out for a tier at this Dispatch level (base minHours, minus 1 h on T4/T5 from L8).
function R.MinHours(tier: any, level: any): number
	local t = R.Tier(tier)
	if not t then return 1 end
	local h = t.minHours
	if R.ClampLevel(level) >= R.MIN_SHORTER_LEVEL and R.MIN_SHORTER_TIERS[t.tier] then
		h -= R.MIN_SHORTER_HOURS
	end
	return math.max(1, h)
end

-- Weekly sulfur week index (Monday 00:00 Asia/Manila boundary).
function R.SulfurWeek(now: number): number
	return (math.floor(tonumber(now) or 0) - R.SULFUR_WEEK_ANCHOR) // R.WEEK_SECONDS
end

function R.EarnLimitHours(level: any): number
	return R.EARN_LIMIT_HOURS[R.ClampLevel(level)]
end

-- Units per mission: 3 at L1, 4 at L5, 5 at L10 (guild_facilities 116).
function R.UnitsPerMission(level: any): number
	local l = R.ClampLevel(level)
	return if l >= 10 then 5 elseif l >= 5 then 4 else 3
end

-- Slots from the Dispatch level: +1 at L4, +1 at L10 (economy_framework 26).
function R.LevelSlots(level: any): number
	local l = R.ClampLevel(level)
	return (if l >= 4 then 1 else 0) + (if l >= 10 then 1 else 0)
end

function R.TierUnlocked(tier: any, level: any): boolean
	local t = R.Tier(tier)
	return t ~= nil and R.ClampLevel(level) >= t.unlock
end

-- Is this material allowed on this tier at this Dispatch level?
function R.MaterialAllowed(material: any, tier: any, level: any): boolean
	if type(material) ~= "string" then return false end
	local m = R.MATERIALS[material]
	local t = R.Tier(tier)
	if not m or not t then return false end
	return R.ClampLevel(level) >= m.minLevel and m.tiers[t.tier] == true
end

-- The tier newly unlocked AT this level (nil if none) -- next-level line DISPATCH-RT-11.
function R.TierUnlockedAt(level: any): number?
	local l = R.ClampLevel(level)
	for _, t in R.TIERS do
		if t.unlock == l and l > 1 then return t.tier end
	end
	return nil
end

-- The approved table cell for this Dispatch level and tier. A tier that is locked at this level (a
-- mission sent before the level was lowered with dev tools) uses its unlock level's cell.
function R.Cell(level: any, tier: any): any?
	local t = R.Tier(tier)
	if not t then return nil end
	local row = R.RATE_TABLE[R.ClampLevel(level)]
	return (row and row[t.tier]) or R.RATE_TABLE[t.unlock][t.tier]
end

-- Kept for callers/display: the table already includes the level, so there is no extra multiplier.
function R.XpMultiplier(_level: any): number
	return 1
end

-- EXP one unit earns over `hours` hours (unit_progression 78). Hour by hour: each hour
-- (or the last part hour) pays fixed + pct x EXP-to-next at the level the unit is on at the start of
-- that hour, so the rate follows its level. Stops at levelCap. Returns the EXP as a float.
function R.ExpForHours(tier: number, level: number, hours: number, unitLevel: number, xpInto: number,
	levelCap: number, xpToNext: (number) -> number): number
	local c = R.Cell(level, tier)
	if not c then return 0 end
	local cap = math.max(1, math.floor(tonumber(levelCap) or 99))
	local lvl = math.clamp(math.floor(tonumber(unitLevel) or 1), 1, cap)
	local into = math.max(0, tonumber(xpInto) or 0)
	local remaining = math.clamp(tonumber(hours) or 0, 0, R.EARN_LIMIT_HOURS[R.MAX_LEVEL])
	local total = 0
	local guard = 0
	while remaining > 1e-9 and lvl < cap and guard < 64 do
		guard += 1
		local h = math.min(1, remaining)
		local need = math.max(1, xpToNext(lvl))
		local gain = (c.fixed + c.pct * need) * h
		total += gain
		into += gain
		while lvl < cap do
			local n = math.max(1, xpToNext(lvl))
			if into < n then break end
			into -= n
			lvl += 1
		end
		remaining -= h
	end
	return total
end

-- Material per hour (60 / minutes per whole unit from the table). 0 if not allowed.
function R.MaterialRatePerHour(material: any, tier: any, level: any): number
	if not R.MaterialAllowed(material, tier, level) then return 0 end
	local c = R.Cell(level, tier)
	local mins = c and c.minutes[material]
	if not mins or mins <= 0 then return 0 end
	return 60 / mins
end

-- Material (float) one mission earns over `hours` hours. 0 if not allowed.
function R.MaterialForHours(material: string, tier: number, level: number, hours: number): number
	return R.MaterialRatePerHour(material, tier, level) * math.max(0, tonumber(hours) or 0)
end

-- Expected item count of each kind over `hours` (before the seeded roll). { kind = expected }.
function R.ItemExpectations(tier: number, level: number, hours: number): { [string]: number }
	local out = {}
	local l = R.ClampLevel(level)
	local h = math.max(0, tonumber(hours) or 0)
	for _, it in R.ITEMS do
		if l >= it.minLevel then out[it.kind] = tier * it.perTier * h end
	end
	return out
end

-- Team size value for n units sent (1..#TEAM_SIZE_STEPS).
function R.TeamSize(n: any): number
	return R.TEAM_SIZE_STEPS[clampInt(n, 1, #R.TEAM_SIZE_STEPS, 1)]
end

-- N1 normalisation: teamSize(n) / teamSize(units per mission). A full team = exactly 1 (x / x).
function R.TeamRel(n: any, maxUnits: any): number
	local maxN = clampInt(maxUnits, 1, #R.TEAM_SIZE_STEPS, 1)
	local k = math.min(clampInt(n, 1, #R.TEAM_SIZE_STEPS, 1), maxN)
	return R.TeamSize(k) / R.TeamSize(maxN)
end

-- Level factor from the average level deficit (>= 0). Deficit 0 = exactly 1.
function R.LevelFactor(deficit: any): number
	local d = tonumber(deficit) or 0
	if d ~= d or d < 0 then d = 0 end
	return math.clamp(1 - R.LEVEL_FACTOR_PER_LEVEL * d, R.LEVEL_FACTOR_MIN, R.LEVEL_FACTOR_MAX)
end

function R.ClampPerk(x: any): number
	local v = tonumber(x) or 0
	if v ~= v then v = 0 end
	return math.clamp(v, R.PERK_BONUS_MIN, R.PERK_BONUS_MAX)
end

-- The whole multiplier, kept between 0 and YIELD_MULT_MAX.
function R.YieldMult(teamRel: number, levelFactor: number, perk: any): number
	return math.clamp(teamRel * levelFactor * (1 + R.ClampPerk(perk)), 0, R.YIELD_MULT_MAX)
end

-- A stored multiplier read back (record / save): missing or bad = 1 (missions sent before 2026-11-21).
function R.SafeYield(x: any): number
	local v = tonumber(x)
	if v == nil or v ~= v then return 1 end
	return math.clamp(v, 0, R.YIELD_MULT_MAX)
end

return table.freeze(R)
