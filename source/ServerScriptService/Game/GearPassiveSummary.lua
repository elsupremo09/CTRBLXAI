--!strict
-- GearPassiveSummary.lua
-- CTRBLXAI | One combined list of every passive a unit's EQUIPPED GEAR gives (2026-10-29)
--
-- Built once on the server. The Loadout Info tab (GetUnitFullStats) and the battle
-- inspector (InspectUnitRequest) both send THIS list, so the two screens can't disagree.
-- Sources per equipped item:
--   * weapon / off-hand native passive   (WeaponData archetype nativePassiveId)
--   * armor / gloves / accessory passive (ArmorData archetype passiveName / passiveDesc)
--   * rolled bonus passives              (item.bonusPassiveIds -> BonusData.BonusPassives)
-- Copies of the same passive merge into one entry with a count. A rolled PAS id that
-- WeaponPassiveService maps to a native key (e.g. PAS-001 -> Brutal) merges with that native.
--
-- ACTIVE vs INACTIVE uses the same rules as WeaponPassiveService's combat collection:
--   * a WEAPON held in the off-hand delivers nothing unless unit.dualWieldActive
--   * weapon-stat passives (Brutal / Stagger / Bulwark) only work on a weapon
-- SCOPE: this reports what the gear SAYS. It cannot tell whether a passive's effect is
-- actually wired into combat yet.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Content = ReplicatedStorage:WaitForChild("Content")
local Game = script.Parent

local WeaponData = require(Content:WaitForChild("WeaponData"))
local ArmorData = require(Content:WaitForChild("ArmorData"))
local BonusData = require(Content:WaitForChild("BonusData"))
local WeaponPassiveService = require(Game:WaitForChild("WeaponPassiveService"))

local GearPassiveSummary = {}

local SLOT_ORDER = { "MainHand", "OffHand", "Head", "Body", "Gloves", "Feet", "Accessory" }
local REASON_OFFHAND = "inactive: off-hand weapon needs dual wield"
local REASON_WEAPON_ONLY = "inactive: only works on a weapon"

local PAS_ID_TO_KEY: { [string]: string } = WeaponPassiveService.PAS_ID_TO_KEY or {}
local WEAPON_STAT_KEYS: { [string]: boolean } = WeaponPassiveService.WEAPON_STAT_KEYS or {}

-- canonical key -> a PAS id that maps to it (so a native passive can borrow its name/stacking rule)
local KEY_TO_PAS: { [string]: string } = {}
for pid, key in PAS_ID_TO_KEY do
	if KEY_TO_PAS[key] == nil then KEY_TO_PAS[key] = pid end
end

-- "ArmorPierce" -> "Armor Pierce"
local function prettify(key: string): string
	return (string.gsub(key, "(%l)(%u)", "%1 %2"))
end

-- Player-facing name of a weapon / off-hand native passive. ONE source for every screen
-- (Info tab, Gears tab, battle inspector item popup, reward cards) so they can't disagree.
-- Borrows the BonusData name when a rolled PAS id maps to the key, else prettifies it. 2026-10-30.
function GearPassiveSummary.NativePassiveName(key: string?): string
	if key == nil or key == "" then return "" end
	local override = WeaponData.GetPassiveName and WeaponData.GetPassiveName(key) or nil
	if override then return override end
	local pid = KEY_TO_PAS[key]
	local bp = pid and BonusData.BonusPassives[pid] or nil
	return (bp and bp.name) or prettify(key)
end

-- Player-facing name + description of an armor / gloves / accessory archetype passive.
-- passiveName is the INTERNAL key (ArmorPassiveService and EquipmentService match on it,
-- so it must never change); passiveDisplayName / passiveDisplayText are display-only and
-- fall back to the internal text when not authored. ONE source for every screen. 2026-10-31.
function GearPassiveSummary.ArmorPassiveDisplay(aArch: any): (string?, string?)
	if not aArch or not aArch.passiveName or aArch.passiveName == "" then return nil, nil end
	local name = aArch.passiveDisplayName
	if name == nil or name == "" then name = aArch.passiveName end
	local desc = aArch.passiveDisplayText
	if desc == nil or desc == "" then desc = aArch.passiveDesc end
	return name, desc
end

local function stackNoteFor(rule: string?): string?
	if not rule or rule == "" then return nil end
	if string.find(rule, "^Strongest only") then return "doesn't stack (strongest only)" end
	if string.find(rule, "^Additive") then return "stacks" end
	return rule
end

-- Some armor passives store the same sentence as both name and description (one copy sometimes
-- a little longer). Show such text ONCE: keep the longer copy and drop the description.
-- Short names ("Range +1") are never merged into their description.
local function norm(t: string): string
	return string.lower((string.gsub(t, "[^%w]", "")))
end
local function dedupeText(name: string, desc: string?): (string, string)
	local d = desc or ""
	local a, b = norm(name), norm(d)
	if b == "" or a == b then return name, "" end
	if math.min(#a, #b) >= 24 then
		if string.find(b, a, 1, true) then return d, "" end
		if string.find(a, b, 1, true) then return name, "" end
		if string.sub(a, 1, 30) == string.sub(b, 1, 30) then
			if #d > #name then return d, "" end
			return name, ""
		end
	end
	return name, d
end

-- Returns an array of slot groups, in equipment-slot order, slots with nothing omitted:
--   { slot = "MainHand", passives = { { name, desc, count, active, reason?, note? } } }
-- (2026-10-29 user layout: slot name first, then one "Name - description" line per passive.)
-- count = copies on THIS item (native + rolled same passive). note = set on an active passive
-- that is equipped more than once across all gear, e.g. "x2 equipped, doesn't stack ...".
-- Nil-safe: no unit/gear -> {}.
function GearPassiveSummary.Build(unit: any): { any }
	local groups: { any } = {}
	if not (unit and type(unit.equipmentSlots) == "table") then return groups end

	local totals: { [string]: number } = {} -- canonical key -> ACTIVE copies across all gear
	local seq = 0

	-- fixed slot order first, then any other slot names, so the list is stable
	local slots: { string } = table.clone(SLOT_ORDER)
	for slot in unit.equipmentSlots do
		if not table.find(slots, slot) then table.insert(slots, slot) end
	end

	for _, slot in slots do
		local item = unit.equipmentSlots[slot]
		if item then
			local wArch = WeaponData.GetByArchetypeId(item.baseArchetypeId)
			local aArch = (not wArch) and ArmorData.GetByArchetypeId(item.baseArchetypeId) or nil
			local isHandWeapon = wArch ~= nil and wArch.category == "Weapon"
			local itemReason: string? = nil
			if slot == "OffHand" and isHandWeapon and unit.dualWieldActive ~= true then
				itemReason = REASON_OFFHAND
			end
			local function reasonFor(key: string): string?
				if itemReason then return itemReason end
				if WEAPON_STAT_KEYS[key] and not isHandWeapon then return REASON_WEAPON_ONLY end
				return nil
			end

			local entries: { any } = {}
			local byKey: { [string]: any } = {}
			local function add(key: string, name: string, desc: string?, reason: string?, rule: string?)
				local text, d = dedupeText(name, desc)
				local mk = key .. "|" .. (reason or "")
				local e = byKey[mk]
				if e then
					e.count += 1
					if e._rule == nil then e._rule = rule end
				else
					seq += 1
					e = { name = text, desc = d, count = 1, active = reason == nil, reason = reason,
						_key = key, _rule = rule, _seq = seq }
					byKey[mk] = e
					table.insert(entries, e)
				end
				if reason == nil then totals[key] = (totals[key] or 0) + 1 end
			end

			-- native weapon / off-hand passive
			if wArch and wArch.nativePassiveId then
				local key = wArch.nativePassiveId
				local pid = KEY_TO_PAS[key]
				local bp = pid and BonusData.BonusPassives[pid] or nil
				add(key, GearPassiveSummary.NativePassiveName(key), WeaponData.GetPassiveDesc(key),
					reasonFor(key), bp and bp.stacking or nil)
			end
			-- second native passive (Boomerang Rebound, weapons_equipment 164; 2026-11-21)
			if wArch and type(wArch.nativeExtraPassiveIds) == "table" then
				for _, key in ipairs(wArch.nativeExtraPassiveIds) do
					add(key, GearPassiveSummary.NativePassiveName(key), WeaponData.GetPassiveDesc(key),
						reasonFor(key), nil)
				end
			end

			-- armor / gloves / accessory archetype passive
			if aArch and aArch.passiveName and aArch.passiveName ~= "" then
				local dName, dDesc = GearPassiveSummary.ArmorPassiveDisplay(aArch)
				add("ARMOR:" .. aArch.passiveName, dName or aArch.passiveName, dDesc, itemReason, nil)
			end

			-- rolled bonus passives
			if type(item.bonusPassiveIds) == "table" then
				for _, pid in item.bonusPassiveIds do
					local bp = BonusData.BonusPassives[pid]
					local key = PAS_ID_TO_KEY[pid] or pid
					add(key, (bp and bp.name) or pid, bp and bp.desc or nil,
						reasonFor(key), bp and bp.stacking or nil)
				end
			end

			if #entries > 0 then
				table.sort(entries, function(x, y)
					if x.active ~= y.active then return x.active end
					return x._seq < y._seq
				end)
				table.insert(groups, { slot = slot, passives = entries })
			end
		end
	end

	for _, g in groups do
		for _, e in g.passives do
			local total = totals[e._key] or 0
			if e.active and total >= 2 then
				local sn = stackNoteFor(e._rule)
				e.note = "\u{00D7}" .. total .. " equipped" .. (sn and (", " .. sn) or "")
			end
			e._key = nil
			e._rule = nil
			e._seq = nil
		end
	end
	return groups
end

-- BUG-106 (2026-11-21): every built-in passive of a weapon / off-hand archetype, in order
-- (nativePassiveId, then nativeExtraPassiveIds), as { id, name, desc } for item popups. nil if none.
function GearPassiveSummary.NativePassiveList(arch: any): { any }?
	if type(arch) ~= "table" then return nil end
	local out = {}
	local function push(key)
		if key then
			table.insert(out, { id = key, name = GearPassiveSummary.NativePassiveName(key),
				desc = WeaponData.GetPassiveDesc(key) or "" })
		end
	end
	push(arch.nativePassiveId)
	if type(arch.nativeExtraPassiveIds) == "table" then
		for _, k in ipairs(arch.nativeExtraPassiveIds) do push(k) end
	end
	return if #out > 0 then out else nil
end

return GearPassiveSummary
