-- TraitRoller.lua
-- CTRBLXAI | Perks & Flaws Phase 1 — roll logic (data-only; no gameplay effect)
-- Rolls ONE perk + ONE flaw per unit. Perk and flaw tiers are rolled INDEPENDENTLY
-- (tier chances Common 40 / Uncommon 28 / Rare 18 / Epic 10 / Legendary 4), then a
-- uniform pick within the rolled tier's pool. All perk+flaw combinations allowed
-- (including same pair_id — independence is intended per design).
-- Lookups are BY trait_id (never by name — duplicate names exist).

local TraitData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("TraitData")
)

local TraitRoller = {}

-- Roll a tier using the weighted tier chances. Returns a tier string.
-- Falls back to the next populated tier if a rolled tier's pool is empty.
local function rollTier(rng, pools)
	local roll = rng:NextNumber() * 100
	local acc = 0
	for _, tc in ipairs(TraitData.TierChances) do
		acc = acc + tc.pct
		if roll <= acc then
			if pools[tc.tier] and #pools[tc.tier] > 0 then
				return tc.tier
			end
		end
	end
	-- Fallback: first tier with a non-empty pool (deterministic order)
	for _, tc in ipairs(TraitData.TierChances) do
		if pools[tc.tier] and #pools[tc.tier] > 0 then
			return tc.tier
		end
	end
	return nil
end

-- Pick a uniform-random trait_id from a tier pool.
local function pickFromPool(rng, pool)
	if not pool or #pool == 0 then return nil end
	return pool[rng:NextInteger(1, #pool)]
end

-- Roll a single perk trait_id. Optional seed for determinism.
function TraitRoller.RollPerk(rng)
	rng = rng or Random.new()
	local tier = rollTier(rng, TraitData.PerkPools)
	return pickFromPool(rng, TraitData.PerkPools[tier])
end

-- Roll a single flaw trait_id. Optional seed for determinism.
function TraitRoller.RollFlaw(rng)
	rng = rng or Random.new()
	local tier = rollTier(rng, TraitData.FlawPools)
	return pickFromPool(rng, TraitData.FlawPools[tier])
end

-- Roll one perk + one flaw (independent tiers). Returns perkId, flawId.
function TraitRoller.RollPair(rng)
	rng = rng or Random.new()
	return TraitRoller.RollPerk(rng), TraitRoller.RollFlaw(rng)
end

-- Assign a rolled perk+flaw onto a unit IF it has none yet (guard against re-roll).
-- Writes unit.perkIds = {perkId}, unit.drawbackIds = {flawId}. Returns perkId, flawId.
-- Never re-rolls a unit that already has traits (save-load / recruit / re-register safe).
function TraitRoller.AssignIfEmpty(unit, rng)
	if not unit then return nil, nil end
	local hasPerk = unit.perkIds and #unit.perkIds > 0
	local hasFlaw = unit.drawbackIds and #unit.drawbackIds > 0
	if hasPerk and hasFlaw then
		return unit.perkIds[1], unit.drawbackIds[1]
	end
	local perkId, flawId = TraitRoller.RollPair(rng)
	unit.perkIds = { perkId }
	unit.drawbackIds = { flawId }
	return perkId, flawId
end

return TraitRoller
