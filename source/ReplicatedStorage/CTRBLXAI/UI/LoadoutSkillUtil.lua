--!strict
-- LoadoutSkillUtil.lua
-- CTRBLXAI | Loadout screen: pure skill helpers (type/element classification, colours,
-- pattern/range/description/effects text). Shared by the Skills grid, loadout and detail modules.
-- Split out of LoadoutScreen.lua (2026-11-10, ARC-005 file-size split, step 3). Behaviour unchanged.
-- Pure helpers: no host state, no Init.


local LoadoutSkillUtil: any = {}


-- SKILL TYPE classification helper
local function getSkillType(tags)
	if not tags then return "Utility" end
	for _, t in ipairs(tags) do
		if t == "Direct Damage" then return "Damage" end
	end
	for _, t in ipairs(tags) do
		if t == "Healing" then return "Heal" end
	end
	for _, t in ipairs(tags) do
		if t == "Buff" or t == "Shield" then return "Buff" end
	end
	for _, t in ipairs(tags) do
		if t == "Debuff" then return "Debuff" end
	end
	return "Utility"
end

-- Skill-type colour table
local STYPE_COLORS = {
	Damage  = { bg = Color3.fromRGB(74, 26, 26), icon = Color3.fromRGB(248, 113, 113) },
	Heal    = { bg = Color3.fromRGB(26, 58, 26), icon = Color3.fromRGB(74, 222, 128)  },
	Buff    = { bg = Color3.fromRGB(26, 42, 74), icon = Color3.fromRGB(96, 165, 250)  },
	Debuff  = { bg = Color3.fromRGB(42, 26, 74), icon = Color3.fromRGB(192, 132, 252) },
	Utility = { bg = Color3.fromRGB(42, 42, 42), icon = Color3.fromRGB(226, 232, 240) },
}

-- Skill-type emoji icons
-- Helper: simplify pattern text for display
local function simplifyPattern(raw)
	if not raw then return "-" end
	local low = raw:lower()
	if low:find("inherit weapon") or low:find("weapon pattern") then
		return "Weapon"
	end
	-- Strip "Authored " prefix
	local simplified = raw:gsub("^Authored%s+", "")
	return simplified
end

-- Helper: simplify targeting range text for display
local function simplifyRange(raw)
	if not raw then return "-" end
	local low = raw:lower()
	-- Check for weapon range inheritance
	if low:find("inherit") and low:find("weapon range") then
		-- Extract bonus skill range %
		local pct = raw:match("(%d+)%%.-[Bb]onus [Ss]kill [Rr]ange")
		if pct then
			return "Weapon + " .. pct .. "% Bonus Skill Range"
		end
		return "Weapon Range"
	end
	-- Fixed range: "Fixed 4; add 100% inherited Bonus Skill Range"
	local fixedVal = raw:match("[Ff]ixed%s+(%d+)")
	local bonusPct = raw:match("(%d+)%%.-[Bb]onus [Ss]kill [Rr]ange")
	if fixedVal then
		if bonusPct and bonusPct ~= "0" then
			return fixedVal .. " + " .. bonusPct .. "% Bonus Skill Range"
		end
		return fixedVal
	end
	-- Authored range formula
	local formula = raw:match("[Aa]uthored [Rr]ange [Ff]ormula:%s*(.-)%;")
	if formula then
		local inheritance = raw:match("Inheritance%s*=%s*(%d+)%%")
		if inheritance and inheritance ~= "0" then
			return formula .. " + " .. inheritance .. "% Bonus Skill Range"
		end
		return formula
	end
	-- Self range
	if low:find("^self") then return "Self" end
	-- Fallback: return first line only, trimmed
	local firstLine = raw:match("^([^\n]+)")
	if firstLine and #firstLine > 50 then
		return firstLine:sub(1, 47) .. "..."
	end
	return firstLine or raw
end

-- Helper: build a short skill description from its definition
local function buildSkillDescription(def)
	if not def then return "" end
	local parts = {}
	-- Range type
	local range = def.targetingRange or ""
	local rangeLow = range:lower()
	if rangeLow:find("self") then
		table.insert(parts, "Self-targeting")
	elseif rangeLow:find("fixed") then
		table.insert(parts, "Ranged")
	elseif rangeLow:find("weapon range") or rangeLow:find("inherit") then
		table.insert(parts, "Weapon-range")
	else
		table.insert(parts, "Targeted")
	end
	-- Element
	local tags = def.tags or {}
	local elements = { "Fire", "Ice", "Electric", "Holy", "Dark", "Poison", "Water", "Earth" }
	for _, el in ipairs(elements) do
		for _, t in ipairs(tags) do
			if t == el then
				table.insert(parts, el:lower())
				break
			end
		end
	end
	-- Pattern
	local pat = def.pattern or ""
	local patLow = pat:lower()
	if patLow:find("single") then
		table.insert(parts, "single-target")
	elseif patLow:find("cleave") or patLow:find("sweep") then
		table.insert(parts, "cleave")
	elseif patLow:find("line") then
		table.insert(parts, "line")
	elseif patLow:find("circle") or patLow:find("spread") then
		table.insert(parts, "area")
	elseif patLow:find("chain") then
		table.insert(parts, "chain")
	elseif patLow:find("weapon") or patLow:find("inherit") then
		table.insert(parts, "weapon-pattern")
	elseif patLow:find("self") then
		table.insert(parts, "self")
	end
	-- Projectile
	local props = def.properties or ""
	if props:lower():find("projectile") then
		table.insert(parts, "projectile")
	end
	-- Main action from tags
	local hasHeal = false
	local hasDamage = false
	local hasBuff = false
	local hasDebuff = false
	for _, t in ipairs(tags) do
		if t == "Healing" then hasHeal = true end
		if t == "Direct Damage" then hasDamage = true end
		if t == "Buff" or t == "Shield" then hasBuff = true end
		if t == "Debuff" then hasDebuff = true end
	end
	if hasDamage and hasDebuff then
		table.insert(parts, "attack with debuff")
	elseif hasDamage then
		table.insert(parts, "attack")
	elseif hasHeal then
		table.insert(parts, "heal")
	elseif hasBuff then
		table.insert(parts, "buff")
	elseif hasDebuff then
		table.insert(parts, "debuff")
	end
	return table.concat(parts, " ")
end

-- Helper: clean effects text — strip pattern/range/snapshot redundancy
local function cleanEffects(raw)
	if not raw then return "" end
	local text = raw
	-- Remove "Authored Single pattern; " or similar pattern mentions
	text = text:gsub("[Aa]uthored%s+%w+%s+pattern;?%s*", "")
	-- Remove "Inherit Weapon Pattern." type mentions
	text = text:gsub("[Ii]nherit%s+[Ww]eapon%s+[Pp]attern%.?%s*", "")
	-- Remove snapshot timing references
	text = text:gsub("[Ss]napshot%s+at%s+commitment[^%.]*%.?%s*", "")
	-- Remove "persistent/created effects..." noise
	text = text:gsub("persistent/created effects[^%.]*%.?%s*", "")
	-- Remove leading/trailing whitespace and semicolons
	text = text:gsub("^[;%s]+", ""):gsub("[;%s]+$", "")
	-- Capitalize first letter
	if text ~= "" then
		text = text:sub(1, 1):upper() .. text:sub(2)
	end
	return text
end

local STYPE_ICONS = {
	Damage  = "[X]",
	Heal    = "[+]",
	Buff    = "[^]",
	Debuff  = "[v]",
	Utility = "[*]",
}

-- Element colour lookup
local ELEM_COLORS = {
	Fire     = Color3.fromRGB(249, 115, 22),
	Ice      = Color3.fromRGB(56, 189, 248),
	Electric = Color3.fromRGB(250, 204, 21),
	Holy     = Color3.fromRGB(253, 230, 138),
	Dark     = Color3.fromRGB(167, 139, 250),
	Poison   = Color3.fromRGB(134, 239, 172),
	Physical = nil, -- uses TextSecondary
}

local function getElement(tags)
	if not tags then return nil end
	for _, t in ipairs(tags) do
		if ELEM_COLORS[t] then return t end
	end
	return nil
end


LoadoutSkillUtil.ELEM_COLORS = ELEM_COLORS
LoadoutSkillUtil.STYPE_COLORS = STYPE_COLORS
LoadoutSkillUtil.STYPE_ICONS = STYPE_ICONS
LoadoutSkillUtil.BuildSkillDescription = function(...) return buildSkillDescription(...) end
LoadoutSkillUtil.CleanEffects = function(...) return cleanEffects(...) end
LoadoutSkillUtil.GetElement = function(...) return getElement(...) end
LoadoutSkillUtil.GetSkillType = function(...) return getSkillType(...) end
LoadoutSkillUtil.SimplifyPattern = function(...) return simplifyPattern(...) end
LoadoutSkillUtil.SimplifyRange = function(...) return simplifyRange(...) end

return LoadoutSkillUtil
