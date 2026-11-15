--!strict
-- GemCraftRules.lua
-- CTRBLXAI | Rune gem crafting rules: the Runeforge "Gem Craft" tab (USER RULING 2026-11-12
-- 1:54 PM; PROPOSAL_gem_crafting_20261112.md recommended defaults, approved as written).
-- ONE frozen table (DAT-001 / DAT-002). The server (GemCraftService) is the authority; the
-- Runeforge screen reads the same values for display only (greyed reasons, prompt prices).
--
--   Upgrade      3 gems of the same kind + tier -> 1 of that kind one tier up. T4 is the top.
--   Break Down   1 gem -> 2 of the same kind one tier down (loses value). Not from T1.
--   Mix          5 stat gems of the same tier (any kinds) -> 1 random stat gem one tier up,
--                equal odds over the 20 in-game stat families. Not from T4.
--   Mix Passives 5 passive gems of the same rarity -> 1 random passive gem of that rarity.
--   Gold only. Runeforge level discount: 3% per level above L1 (RuneforgeService), rounded down.

local GemCraftRules = {}

GemCraftRules.MAX_TIER = 4             -- rune gems are T4 at most (materials_system 4)
GemCraftRules.UPGRADE_INPUTS = 3
GemCraftRules.BREAK_DOWN_OUTPUTS = 2
GemCraftRules.MIX_INPUTS = 5
GemCraftRules.MAX_TIMES = 999          -- request bound for Craft xN / Craft All (SEC-001)

-- Base gold BEFORE the discount, keyed by the INPUT gem's tier (one craft).
GemCraftRules.GOLD = table.freeze({
	Upgrade = table.freeze({ [1] = 40, [2] = 100, [3] = 250 }),
	BreakDown = table.freeze({ [2] = 10, [3] = 25, [4] = 60 }),
	Mix = table.freeze({ [1] = 30, [2] = 75, [3] = 180 }),
	MixPassives = 150,
})

GemCraftRules.ACTIONS = table.freeze({ Upgrade = true, BreakDown = true, Mix = true, MixPassives = true })

-- Approved greyed-out reasons, word for word. The server refuses with the same text.
GemCraftRules.REASONS = table.freeze({
	NeedThree = "Need 3 of the same gem",
	TopTier = "T4 is the highest tier",
	NoBreakT1 = "T1 can't be broken down",
	SameTier = "Pick 5 gems of the same tier",
	SameRarity = "Pick 5 passives of the same rarity",
	Gold = "Not enough gold",
})

-- Gold for ONE craft after the Runeforge discount (discountPct comes from RuneforgeService,
-- not worked out here). Rounded down, like the forge and swap fees.
function GemCraftRules.Price(baseGold: number, discountPct: number?): number
	local d = math.clamp(math.floor(tonumber(discountPct) or 0), 0, 100)
	return (math.floor(baseGold) * (100 - d)) // 100
end

return table.freeze(GemCraftRules)
