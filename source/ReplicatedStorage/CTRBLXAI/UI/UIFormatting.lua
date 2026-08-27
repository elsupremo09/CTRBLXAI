-- UIFormatting.lua
-- CTRBLXAI | Slice 7A — Text and Number Formatting Utilities
--
-- Pure display-only formatting. No gameplay calculations.
-- These functions convert authoritative values into display strings.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(
	ReplicatedStorage
		:WaitForChild("CTRBLXAI", 10)
		:WaitForChild("UI", 10)
		:WaitForChild("Theme", 10)
)

local UIFormatting = {}

--------------------------------------------------
-- NUMBER FORMATTING
--------------------------------------------------

--- Format HP for display: "120 / 200"
function UIFormatting.FormatHP(current, max)
	return string.format("%d / %d", current or 0, max or 0)
end

--- Format MP for display: "15 / 40"
function UIFormatting.FormatMP(current, max)
	return string.format("%d / %d", current or 0, max or 0)
end

--- Format a percentage (0-1 ratio): "65%"
function UIFormatting.FormatPercent(ratio)
	return string.format("%d%%", math.round((ratio or 0) * 100))
end

--- Format RT value: "RT 340"
function UIFormatting.FormatRT(rt)
	return string.format("RT %d", rt or 0)
end

--- Format CT value: "CT 100"
function UIFormatting.FormatCT(ct)
	return string.format("CT %d", ct or 0)
end

--- Format AP: "2 AP"
function UIFormatting.FormatAP(ap)
	return string.format("%d AP", ap or 0)
end

--- Format MP cost: "MP 3"
function UIFormatting.FormatMPCost(cost)
	return string.format("MP %d", cost or 0)
end

--- Format damage number: "-45"
function UIFormatting.FormatDamage(amount)
	return string.format("-%d", amount or 0)
end

--- Format healing number: "+30"
function UIFormatting.FormatHealing(amount)
	return string.format("+%d", amount or 0)
end

--- Format stat with optional bonus: "STR 24 (+4)"
function UIFormatting.FormatStat(name, total, bonus)
	if bonus and bonus ~= 0 then
		local sign = bonus > 0 and "+" or ""
		return string.format("%s %d (%s%d)", name, total or 0, sign, bonus)
	end
	return string.format("%s %d", name, total or 0)
end

--------------------------------------------------
-- TEXT FORMATTING
--------------------------------------------------

--- Truncate text to maxLen characters, appending "…" if cut
function UIFormatting.Truncate(text, maxLen)
	if not text then return "" end
	maxLen = maxLen or 20
	if #text <= maxLen then return text end
	return string.sub(text, 1, maxLen - 1) .. "…"
end

--- Capitalize first letter of a string
function UIFormatting.Capitalize(text)
	if not text or #text == 0 then return "" end
	return string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
end

--- Convert skill_id format to display name: "skill_power_strike" → "Power Strike"
function UIFormatting.SkillIdToName(skillId)
	if not skillId then return "Unknown" end
	local name = string.gsub(skillId, "^skill_", "")
	name = string.gsub(name, "_", " ")
	-- Capitalize each word
	name = string.gsub(name, "(%a)([%w]*)", function(first, rest)
		return string.upper(first) .. rest
	end)
	return name
end

--- Format range display: "Range 3" or "Melee"
function UIFormatting.FormatRange(range)
	if not range or range <= 1 then
		return "Melee"
	end
	return string.format("Range %d", range)
end

--- Format duration: "3 turns"
function UIFormatting.FormatDuration(turns)
	if not turns or turns <= 0 then return "" end
	if turns == 1 then return "1 turn" end
	return string.format("%d turns", turns)
end

--------------------------------------------------
-- COLOR HELPERS (display-only ratios)
--------------------------------------------------

--- Calculate HP bar fill ratio (display only — does NOT determine actual HP)
function UIFormatting.HPRatio(current, max)
	if not max or max <= 0 then return 0 end
	return math.clamp((current or 0) / max, 0, 1)
end

--- Calculate MP bar fill ratio (display only)
function UIFormatting.MPRatio(current, max)
	if not max or max <= 0 then return 0 end
	return math.clamp((current or 0) / max, 0, 1)
end

--------------------------------------------------
-- RARITY HELPERS
--------------------------------------------------

--- Get rarity display name with color tag (RichText)
function UIFormatting.RarityRichText(rarity)
	local color = Theme.GetRarityColor(rarity)
	local r = math.round(color.R * 255)
	local g = math.round(color.G * 255)
	local b = math.round(color.B * 255)
	return string.format('<font color="rgb(%d,%d,%d)">%s</font>', r, g, b, rarity or "Common")
end

--- Get side/faction display with color tag (RichText)
function UIFormatting.SideRichText(side)
	local color = Theme.GetSideColor(side)
	local r = math.round(color.R * 255)
	local g = math.round(color.G * 255)
	local b = math.round(color.B * 255)
	return string.format('<font color="rgb(%d,%d,%d)">%s</font>', r, g, b, side or "Unknown")
end

return UIFormatting
