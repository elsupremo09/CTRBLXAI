-- CTRBLXAI | ItemDisplay  (extracted from Main.server.lua on 2026-10-12)
-- Shared item -> UI entry builders used by the loadout screen (GetInventoryData)
-- and the battle inspector (InspectUnitRequest). Requires content data modules plus
-- GearPassiveSummary (passive display names); no require cycle, so NO dependency injection.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Content           = ReplicatedStorage:WaitForChild("Content")
local BonusData         = require(Content:WaitForChild("BonusData"))
local WeaponData        = require(Content:WaitForChild("WeaponData"))
local ArmorData         = require(Content:WaitForChild("ArmorData"))
-- One source for weapon/off-hand passive names on every screen (2026-10-30).
local GearPassiveSummary = require(script.Parent:WaitForChild("GearPassiveSummary"))

local ItemDisplay = {}

local BONUS_DISPLAY_KEY = {
	STR = "STR", AGI = "AGI", INT = "INT", VIT = "VIT", DEX = "DEX", LUK = "LUK",
	damage = "Attack", defense = "Defense", rtDelay = "RT Delay", hp = "HP", mp = "MP", wt = "WT",
	precision = "Precision", evasiveness = "Evasiveness", fortune = "Fortune", skillPotency = "Skill Potency",
	healingOutput = "Healing", debuffResist = "Debuff Resist", rtDelayResist = "RT Delay Resist",
}

local function resolveItemBonuses(item)
	local stats = {}
	local statPcts = {}
	local passives = {}

	for _, line in ipairs(item.bonusLines or {}) do
		local attr = BonusData.NumericalAttributes[line.id]
		if attr then
			local key = BONUS_DISPLAY_KEY[attr.stat] or attr.family
			local value = 0

			if attr.operation == "PrimaryStat" or attr.operation == "BaseItemStat" then
				local scale = WeaponData.GetScale(item.itemLevel or 1)
				value = math.round((attr.l99Flat or 0) * scale)
			elseif attr.operation == "WeightReduce" then
				local scale = WeaponData.GetScale(item.itemLevel or 1)
				value = -math.round((attr.l99Flat or 0) * scale)
			elseif attr.operation == "Derived" then
				-- fixedValue is additive pct like 0.03 → display as 3
				value = math.round((attr.fixedValue or 0) * 100)
			elseif attr.operation == "DerivedMultiplier" then
				-- fixedValue is multiplier like 1.08 → +8, or 0.95 → -5
				value = math.round(((attr.fixedValue or 1) - 1) * 100)
			else
				-- Unknown operation — try l99Flat
				local scale = WeaponData.GetScale(item.itemLevel or 1)
				value = math.round((attr.l99Flat or 0) * scale)
			end

			-- Two-part bonuses (PrimaryStat / BaseItemStat / WeightReduce) carry a
			-- percentage component alongside the scaled flat. Surface it so the UI
			-- can show BOTH halves (e.g. "LUK +2  +15%") instead of flat only.
			local pctRaw = tonumber(attr.pct) or 0
			if pctRaw ~= 0 and (attr.operation == "PrimaryStat"
				or attr.operation == "BaseItemStat"
				or attr.operation == "WeightReduce") then
				local pctDisplay = math.round(pctRaw * 100)
				if attr.operation == "WeightReduce" then pctDisplay = -pctDisplay end
				statPcts[key] = (statPcts[key] or 0) + pctDisplay
			end

			if value ~= 0 then
				stats[key] = (stats[key] or 0) + value
			end
		end
	end

	for _, passiveId in ipairs(item.bonusPassiveIds or {}) do
		local passive = BonusData.BonusPassives[passiveId]
		if passive then
			table.insert(passives, { name = passive.name or passiveId, icon = "\xe2\x97\x86", desc = passive.desc or "" })
		end
	end

	-- DIAG: log resolved bonus stats
	local dbgParts = {}
	for k, v in pairs(stats) do table.insert(dbgParts, k .. "=" .. tostring(v)) end
	if #dbgParts > 0 then
	end

	return stats, passives, statPcts
end

-- One bonus line's effect as short UI text ("STR  +7  +9%"; a passive returns its description),
-- worked out with the SAME math as the item bonus view above (2026-11-07, Runeforge bonus
-- inspector). Display only. itemLevel: the item the line is on (gems: a reference level).
-- Second return: true when the value grows with item level (the same operations the bonus view
-- scales above: PrimaryStat / BaseItemStat / WeightReduce); fixed "Derived" values don't.
local LEVEL_SCALED_OPS = { PrimaryStat = true, BaseItemStat = true, WeightReduce = true }
function ItemDisplay.DescribeBonusEffect(lineId: string, itemLevel: number?): (string?, boolean)
	if type(lineId) ~= "string" then return nil, false end
	local passive = BonusData.BonusPassives[lineId]
	if passive then
		return (if passive.desc and passive.desc ~= "" then passive.desc else nil), false
	end
	local attr = BonusData.NumericalAttributes[lineId]
	if not attr then return nil, false end
	local scales = LEVEL_SCALED_OPS[attr.operation] == true
	local stats, _, pcts = resolveItemBonuses({ bonusLines = { { id = lineId } }, itemLevel = itemLevel or 1 })
	local keys = {}
	for k in stats do keys[k] = true end
	for k in pcts do keys[k] = true end
	local parts = {}
	for k in keys do
		local v, p = stats[k], pcts[k]
		local s = k
		if v and v ~= 0 then s ..= `  {if v > 0 then "+" else ""}{v}` end
		if p and p ~= 0 then s ..= `  {if p > 0 then "+" else ""}{p}%` end
		table.insert(parts, s)
	end
	table.sort(parts)
	return (if #parts > 0 then table.concat(parts, ", ") else nil), scales
end

-- Shared item -> UI entry builder. GetInventoryData AND InspectUnit both use it,
-- so the battle inspector's item detail always matches the loadout screen.
local function buildItemEntry(item)
	local wArch = WeaponData.GetByArchetypeId(item.baseArchetypeId)
	local aArch = not wArch and ArmorData.GetByArchetypeId(item.baseArchetypeId) or nil
	local entry
	if wArch then
		local profile = WeaponData.GetScaledProfile(item.baseArchetypeId, item.itemLevel)
		entry = {
			instanceId = item.instanceId,
			name = item.displayName or wArch.name,
			category = wArch.category,
			handClass = wArch.handClass or "1H",
			slot = (wArch.category == "OffHand") and "OffHand" or "MainHand",
			itemLevel = item.itemLevel,
			rarity = item.rarityId,
			damage = profile and profile.damage or 0,
			wt = profile and profile.wt or 0,
			defense = profile and profile.defense or 0,
			rtDelay = profile and profile.rtDelay or 0,
			minRange = profile and profile.minRange or 1,
			maxRange = profile and profile.maxRange or 1,
			-- Batch 8 (2026-11-22): the weapon's attack pattern label for the item popups (WeaponData
			-- pattern label, weapons_equipment 165 "Line 3"). nil for Single (no row). Display only.
			patternLabel = if profile and profile.pattern and profile.pattern ~= "Single" then WeaponData.GetPatternLabel(profile.pattern) else nil,
			isWeapon = wArch.category == "Weapon",
			isArmor = false,
			icon = wArch.icon or nil,
			flavor = wArch.flavor or nil,
			nativePassiveId = wArch.nativePassiveId or nil,
			nativePassiveName = wArch.nativePassiveId and GearPassiveSummary.NativePassiveName(wArch.nativePassiveId) or nil,
			nativePassiveDesc = WeaponData.GetPassiveDesc(wArch.nativePassiveId) or nil,
			-- BUG-106: every built-in passive (Boomerang: Tricky + Rebound), text from WeaponData.
			nativePassives = GearPassiveSummary.NativePassiveList(wArch),
			projectileType = wArch.projectileType or nil,
			element = WeaponData.GetInstanceElement(item) or nil,
		}
	elseif aArch then
		local scaled = ArmorData.GetScaledProfile(item.baseArchetypeId, item.itemLevel)
		entry = {
			instanceId = item.instanceId,
			name = item.displayName or aArch.name,
			category = "Armor",
			slot = aArch.slot,
			itemLevel = item.itemLevel,
			rarity = item.rarityId,
			defense = scaled and scaled.defense or 0,
			wt = scaled and scaled.wt or 0,
			hp = scaled and scaled.hp or 0,
			mp = scaled and scaled.mp or 0,
			damage = 0,
			rtDelay = 0,
			minRange = 0,
			maxRange = 0,
			isWeapon = false,
			isArmor = true,
			icon = aArch.icon or nil,
			flavor = aArch.flavor or nil,
			-- Display name/text (internal passiveName stays the rules key). 2026-10-31.
			passiveName = (GearPassiveSummary.ArmorPassiveDisplay(aArch)),
			passiveDesc = select(2, GearPassiveSummary.ArmorPassiveDisplay(aArch)),
			actionOwnership = aArch.actionOwnership or nil,
		}
	else
		entry = {
			instanceId = item.instanceId,
			name = "Unknown",
			category = "Unknown",
			itemLevel = item.itemLevel,
			rarity = item.rarityId,
		}
	end
	entry.isNew = item.isNew or false
	entry.bonusCount = #(item.bonusLines or {})
	entry.passiveCount = #(item.bonusPassiveIds or {})
	local bStats, bPassives, bPcts = resolveItemBonuses(item)
	entry.bonusStats = bStats
	entry.bonusPassives = bPassives
	entry.bonusStatPcts = bPcts
	return entry
end

ItemDisplay.resolveItemBonuses = resolveItemBonuses
ItemDisplay.buildItemEntry     = buildItemEntry

return ItemDisplay
