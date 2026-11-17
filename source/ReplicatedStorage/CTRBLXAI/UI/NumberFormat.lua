--!strict
-- NumberFormat.lua
-- CTRBLXAI | Player-visible number formats (user 2026-11-17 12:00 PM / 1:50 PM, loadout_ui_spec 129):
-- no decimals in player text. Multipliers become percentages. Stats that are already percentages
-- keep ONE decimal only for a half step ("12.5%"); whole values show no ".0" ("12%").
-- Display only: never feed these strings back into game logic (AugmentEffectService parses the raw data).

local NumberFormat = {}

--- Half-step number: rounds to the nearest 0.5; "12" or "12.5" (never "12.0", never two decimals).
function NumberFormat.Half(v: any): string
	local r = math.round((tonumber(v) or 0) * 2) / 2
	if r == math.floor(r) then return tostring(math.floor(r)) end
	return string.format("%.1f", r)
end

--- Percent stat: "12%" or "12.5%".
function NumberFormat.Pct(v: any): string
	return NumberFormat.Half(v) .. "%"
end

--- Multiplier -> signed percent change: 1.20 -> "+20%", 0.90 -> "-10%", 1.00 -> "+0%".
function NumberFormat.MultPct(m: any): string
	local p = math.round(((tonumber(m) or 1) - 1) * 100)
	return (if p >= 0 then "+" else "-") .. tostring(math.abs(p)) .. "%"
end

--- Rewrites every "×1.20" / "x1.20" in a data string as a percent change:
--- "MP Cost ×1.20" -> "MP Cost +20%"; "Weapon Damage scaling ×0.90" -> "Weapon Damage scaling -10%".
function NumberFormat.CostText(s: string?): string
	local t = s or ""
	t = string.gsub(t, "\u{00D7}(%d+%.?%d*)", function(n: string) return NumberFormat.MultPct(n) end)
	t = string.gsub(t, "([%s%(])x(%d+%.%d+)", function(pre: string, n: string) return pre .. NumberFormat.MultPct(n) end)
	return t
end

--- First multiplier in a data string as a short percent ("+20%"), or "" when there is none.
function NumberFormat.CostShort(s: string?): string
	local t = s or ""
	local n = string.match(t, "\u{00D7}(%d+%.?%d*)") or string.match(t, "x(%d+%.%d+)")
	if not n then return "" end
	return NumberFormat.MultPct(n)
end

return NumberFormat
