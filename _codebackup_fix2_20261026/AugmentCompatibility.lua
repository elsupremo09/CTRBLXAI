--!strict
-- AugmentCompatibility.lua
-- CTRBLXAI | The ONE rule for "does this augment fit this skill?" (shared: server + client).
--
-- User ruling 2026-10-26: compatibility relies ONLY on the tags printed on the skill and
-- augment cards, so a player can always see why an augment fits or doesn't. No hidden target
-- rules, pattern rules or free-text requirements are checked here.
--
--   * Skill tags come from Content.SkillData (generated from CTRBLXAI.db skills.Skill_Tags).
--   * Required tags come from Content.AugmentData requiredSkillTags (augments.Required_Skill_Tags).
--     Every entry must be satisfied (AND). One entry may list alternatives joined by " OR ".
--   * Weapon-derived tags: a skill whose shape or reach comes from its weapon carries
--     "Weapon Shape" / "Weapon Reach". Those resolve against the EQUIPPED weapon
--     (pattern Single/nil -> "Single", else "Area"; max range 1 -> "Melee", else "Ranged").
--     Without a weapon profile they resolve to nothing, so a requirement on them is unmet.
--
-- Used by: EnemyGenerator (enemy augment picks), LoadoutRequestHandlers (server attach gate),
-- LoadoutScreen (what the player sees), Main save-load cleanup (unequip no-longer-fitting).
-- Location: ReplicatedStorage/CTRBLXAI/Shared/AugmentCompatibility.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Content = ReplicatedStorage:WaitForChild("Content", 10)
assert(Content, "[AugmentCompatibility] ReplicatedStorage.Content did not replicate within 10s")
local SkillData = require(Content:WaitForChild("SkillData", 10) :: ModuleScript)
local AugmentData = require(Content:WaitForChild("AugmentData", 10) :: ModuleScript)

local WEAPON_SHAPE_TAG = "Weapon Shape"
local WEAPON_REACH_TAG = "Weapon Reach"
local OR_SEPARATOR = " OR "

export type WeaponProfile = {
	pattern: string?,
	maxRange: number?,
}

local AugmentCompatibility = {}

local function trim(text: string): string
	return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

--- Weapon profile from a battle/loadout unit (EquipmentService stamps these fields).
function AugmentCompatibility.WeaponProfileFromUnit(unit: any): WeaponProfile?
	if type(unit) ~= "table" then
		return nil
	end
	if unit.weaponPattern == nil and unit.weaponMaxRange == nil then
		return nil
	end
	return {
		pattern = unit.weaponPattern,
		maxRange = unit.weaponMaxRange,
	}
end

--- The skill's card tags as a set, with weapon-derived tags resolved for `weapon`.
function AugmentCompatibility.GetSkillTagSet(skillId: string?, weapon: WeaponProfile?): { [string]: boolean }
	local set: { [string]: boolean } = {}
	local def = skillId and (SkillData :: any)[skillId]
	if not def or type(def.tags) ~= "table" then
		return set
	end
	for _, tag in def.tags do
		if tag == WEAPON_SHAPE_TAG then
			if weapon then
				local pattern = weapon.pattern
				set[if pattern == nil or pattern == "Single" then "Single" else "Area"] = true
			end
		elseif tag == WEAPON_REACH_TAG then
			if weapon then
				set[if (weapon.maxRange or 1) <= 1 then "Melee" else "Ranged"] = true
			end
		else
			set[tag] = true
		end
	end
	return set
end

--- The augment's required tag entries (each entry may contain " OR " alternatives).
function AugmentCompatibility.GetRequiredTags(augmentId: string?): { string }
	local def = augmentId and (AugmentData :: any)[augmentId]
	if not def or type(def.requiredSkillTags) ~= "table" then
		return {}
	end
	return def.requiredSkillTags
end

local function entrySatisfied(tagSet: { [string]: boolean }, entry: string): boolean
	local remaining = entry
	while true do
		local sepStart, sepEnd = string.find(remaining, OR_SEPARATOR, 1, true)
		local option = trim(if sepStart then string.sub(remaining, 1, sepStart - 1) else remaining)
		if option ~= "" and tagSet[option] then
			return true
		end
		if not sepStart then
			return false
		end
		remaining = string.sub(remaining, (sepEnd :: number) + 1)
	end
end

--- Does `augmentId` fit `skillId`? Returns (fits, missingEntries). missingEntries lists the
--- required tag entries the skill does not show, so the UI can say exactly why.
function AugmentCompatibility.Check(skillId: string?, augmentId: string?, weapon: WeaponProfile?): (boolean, { string })
	local missing: { string } = {}
	if not skillId or not augmentId or (AugmentData :: any)[augmentId] == nil then
		return false, missing
	end
	local tagSet = AugmentCompatibility.GetSkillTagSet(skillId, weapon)
	for _, entry in AugmentCompatibility.GetRequiredTags(augmentId) do
		if not entrySatisfied(tagSet, entry) then
			table.insert(missing, entry)
		end
	end
	return #missing == 0, missing
end

--- Every augment that fits `skillId`, sorted by id so callers drawing from an RNG stay
--- deterministic (same seed = same enemy loadout).
function AugmentCompatibility.ListCompatible(skillId: string?, weapon: WeaponProfile?): { string }
	local out: { string } = {}
	if not skillId then
		return out
	end
	for augmentId in AugmentData :: any do
		if AugmentCompatibility.Check(skillId, augmentId, weapon) then
			table.insert(out, augmentId)
		end
	end
	table.sort(out)
	return out
end

return table.freeze(AugmentCompatibility)
