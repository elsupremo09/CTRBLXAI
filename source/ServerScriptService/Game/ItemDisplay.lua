-- CTRBLXAI | ItemDisplay  (extracted from Main.server.lua on 2026-10-12)
-- Shared item -> UI entry builders used by the loadout screen (GetInventoryData)
-- and the battle inspector (InspectUnitRequest). Self-contained: requires only
-- content data modules, so NO dependency injection is needed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Content           = ReplicatedStorage:WaitForChild("Content")
local BonusData         = require(Content:WaitForChild("BonusData"))
local WeaponData        = require(Content:WaitForChild("WeaponData"))
local ArmorData         = require(Content:WaitForChild("ArmorData"))

local ItemDisplay = {}

local BONUS_DISPLAY_KEY = {
	STR = "STR", AGI = "AGI", INT = "INT", VIT = "VIT", DEX = "DEX", LUK = "LUK",
	damage = "Attack", defense = "Defense", rtDelay = "RT Delay", hp = "HP", mp = "MP", wt = "WT",
	precision = "Precision", evasiveness = "Evasiveness", fortune = "Fortune", skillPotency = "Skill Potency",
	healingOutput = "Healing", debuffResist = "Debuff Resist", rtDelayResist = "RT Delay Resist",
}

local function resolveItemBonuses(item)
	local stats = {}
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

	return stats, passives
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
			isWeapon = wArch.category == "Weapon",
			isArmor = false,
			icon = wArch.icon or nil,
			flavor = wArch.flavor or nil,
			nativePassiveId = wArch.nativePassiveId or nil,
			nativePassiveDesc = WeaponData.GetPassiveDesc(wArch.nativePassiveId) or nil,
			projectileType = wArch.projectileType or nil,
			element = WeaponData.GetElement(item.baseArchetypeId) or nil,
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
			passiveName = aArch.passiveName or nil,
			passiveDesc = aArch.passiveDesc or nil,
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
	entry.bonusStats, entry.bonusPassives = resolveItemBonuses(item)
	return entry
end

ItemDisplay.resolveItemBonuses = resolveItemBonuses
ItemDisplay.buildItemEntry     = buildItemEntry

return ItemDisplay
