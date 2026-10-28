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
--     An entry "Not X" means the skill must NOT show tag X.
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
		-- "Not X" (ruling 2026-10-26): the skill must NOT show tag X (e.g. Shared Resolve: Not Stance).
		local forbidden = string.match(entry, "^%s*Not%s+(.-)%s*$")
		if forbidden then
			if tagSet[forbidden] then
				table.insert(missing, entry)
			end
		elseif not entrySatisfied(tagSet, entry) then
			table.insert(missing, entry)
		end
	end
	return #missing == 0, missing
end

-- CONFLICTS (user ruling 2026-10-28): two augments from the same conflict group cannot share a
-- skill. Read from each augment's Conflicts text (DB augments.Conflicts):
--   "Conflicts with other <Family> Augments."      -> every augment of that family
--   "Cannot stack with <Augment> on the same Skill." -> that one augment
--   "Conflicts with <Augment>."                      -> that one augment
-- Conflicts work both ways. Built once from AugmentData (static content).
local conflictMap: { [string]: { [string]: boolean } }? = nil

local function buildConflictMap(): { [string]: { [string]: boolean } }
	local map: { [string]: { [string]: boolean } } = {}
	local byName: { [string]: string } = {}
	for id, def in AugmentData :: any do
		if type(def) == "table" and type(def.name) == "string" then
			byName[def.name] = id
		end
	end
	local function link(a: string, b: string)
		if a == b then
			return
		end
		map[a] = map[a] or {}
		map[b] = map[b] or {}
		map[a][b] = true
		map[b][a] = true
	end
	for id, def in AugmentData :: any do
		local text = type(def) == "table" and def.conflicts or nil
		if type(text) == "string" then
			local family = string.match(text, "Conflicts with other (.-) Augments")
			if family then
				for otherId, otherDef in AugmentData :: any do
					if type(otherDef) == "table" and otherDef.family == family then
						link(id, otherId)
					end
				end
			end
			for name in string.gmatch(text, "Cannot stack with (.-) on the same Skill") do
				if byName[name] then
					link(id, byName[name])
				end
			end
			local named = string.match(text, "^%s*Conflicts with (.-)%.")
			if named and byName[named] then
				link(id, byName[named])
			end
		end
	end
	return map
end

--- True when augments `a` and `b` may not be on the same skill.
function AugmentCompatibility.ConflictsWith(a: string?, b: string?): boolean
	if not a or not b or a == b then
		return false
	end
	if not conflictMap then
		conflictMap = buildConflictMap()
	end
	local set = (conflictMap :: any)[a]
	return set ~= nil and set[b] == true
end

--- The first augment in `others` (a skill's 2-slot list; nils allowed) that conflicts with
--- `augmentId`, skipping slot `skipIndex` (the slot being replaced). nil = no conflict.
function AugmentCompatibility.FindConflict(augmentId: string?, others: any, skipIndex: number?): string?
	if type(others) ~= "table" then
		return nil
	end
	for i = 1, 2 do
		local other = others[i]
		if i ~= skipIndex and type(other) == "string" and AugmentCompatibility.ConflictsWith(augmentId, other) then
			return other
		end
	end
	return nil
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
