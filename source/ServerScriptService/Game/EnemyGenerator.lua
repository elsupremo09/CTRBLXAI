--!strict
-- EnemyGenerator.lua
-- CTRBLXAI | Procedural Enemy Generation
--
-- Turns a quest's enemyTypes list ({type, level, count}) into real UnitSchema
-- enemy units, built like player units: random race + random doctrine + skills
-- (from the doctrine's pool) + augments + procedurally generated gear + consumables.
--
-- Dev-locked design (2026-09-26):
--   Grunt: doctrine skill + 2 pool skills (3 total), 1 augment each, 1-2 consumables,
--          3-5 gear pieces incl. weapon, gear rarity Common..Rare, base RT 400.
--   Elite: doctrine skill + 3 pool skills (4 total), 2 augments each, full consumables,
--          full gear set, gear rarity Uncommon..Epic, base RT 350.
--   Boss:  authored separately (NOT handled here).
--   Stats: from race + level only (no tier multiplier). Race is fully random
--          (biome->race mapping parked). Deterministic: same rng stream = same enemies.
--
-- Location: ServerScriptService/Game/EnemyGenerator.lua

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")

local Game    = ServerScriptService:WaitForChild("Game")
local Content = ReplicatedStorage:WaitForChild("Content")

-- Local (sibling) modules
local UnitSchema       = require(Game:WaitForChild("UnitSchema"))
local GameConstants    = require(ReplicatedStorage:WaitForChild("CTRBLXAI"):WaitForChild("Shared"):WaitForChild("GameConstants"))
local EquipmentService = require(Game:WaitForChild("EquipmentService"))
local StatusService    = require(Game:WaitForChild("StatusService"))
local TraitEffectService = require(Game:WaitForChild("TraitEffectService"))
local ItemGenerator    = require(Game:WaitForChild("ItemGenerator"))
local TraitRoller      = require(Game:WaitForChild("TraitRoller"))

-- Content registries
local RaceData       = require(Content:WaitForChild("RaceData"))
local DoctrineData   = require(Content:WaitForChild("DoctrineData"))
local AugmentData    = require(Content:WaitForChild("AugmentData"))
local SkillData      = require(Content:WaitForChild("SkillData"))
local ArmorData      = require(Content:WaitForChild("ArmorData"))
local ConsumableData = require(Content:WaitForChild("ConsumableData"))
local UnitNameData   = require(Content:WaitForChild("UnitNameData"))
local TraitData      = require(Content:WaitForChild("TraitData"))

local EnemyGenerator = {}

--------------------------------------------------
-- DOCTRINE SKILL POOLS (design data)
--------------------------------------------------

-- Auto-generated from Enemy_Doctrine_Skill_Loadouts.md (Designer) + DoctrineData/SkillData
-- (signature map authoritative from SkillData DOC-*-01 skills). Validated 2026-09-26:
-- 32 doctrines, all 320 pool skill IDs exist in SkillData, each pool exactly 10 skills.
-- 15 doctrines have a separate signature DOC-*-01; 17 use pool[1] as anchor (signature=nil).
local DOCTRINE_SKILL_POOLS = {
	["DOC-ARCANIST"] = {
		signature = "DOC-ARCANIST-01",
		pool = { "SKL-FIRE-BOLT", "SKL-METEOR-MARKER", "SKL-IGNITION-LANCE", "SKL-EARTHEN-LANCE", "SKL-CHAIN-SPARK", "SKL-FROSTBIND", "SKL-ARCANE-BARRIER", "SKL-ARCANE-RENEWAL", "SKL-MANA-SCORCH", "SKL-BLINK" },
	},
	["DOC-ASCETIC"] = {
		signature = "DOC-ASCETIC-01",
		pool = { "SKL-HEALING-LIGHT", "SKL-PURIFYING-FORM", "SKL-PURGE", "SKL-INVIGORATE", "SKL-ARCANE-RENEWAL", "SKL-FIELD-DRESSING", "SKL-LIFE-LINK", "SKL-SUMMON-WARD-TOTEM", "SKL-CONSECRATE", "SKL-VITAL-BARRIER" },
	},
	["DOC-ASSASSIN"] = {
		signature = nil,
		pool = { "SKL-LUNGE", "SKL-VANISHING-STEP", "SKL-TWIN-FANGS", "SKL-EXECUTION-STROKE", "SKL-POWER-STRIKE", "SKL-OPPORTUNIST-S-STEP", "SKL-BLINK", "SKL-HAMSTRING", "SKL-RAPID-ASSAULT", "SKL-LUCKY-STRIKE" },
	},
	["DOC-BERSERKER"] = {
		signature = "DOC-BERSERKER-01",
		pool = { "SKL-POWER-STRIKE", "SKL-EXECUTION-STROKE", "SKL-CRUSHING-ADVANCE", "SKL-BATTLE-FURY", "SKL-LUNGE", "SKL-GALE-THRUST", "SKL-RENDING-SLASH", "SKL-SWEEPING-CUT", "SKL-RAPID-ASSAULT", "SKL-SHATTER-BLOW" },
	},
	["DOC-CLERIC"] = {
		signature = nil,
		pool = { "SKL-CONSECRATE", "SKL-MENDING-RAIN", "SKL-LIFE-LINK", "SKL-HEALING-LIGHT", "SKL-FIELD-DRESSING", "SKL-PURGE", "SKL-INVIGORATE", "SKL-PURIFYING-FORM", "SKL-ARCANE-RENEWAL", "SKL-SANCTIFY" },
	},
	["DOC-CONJURER"] = {
		signature = "DOC-CONJURER-01",
		pool = { "SKL-SUMMON-TURRET", "SKL-SUMMON-WARD-TOTEM", "SKL-SUMMON-DECOY", "SKL-ARCANE-BARRIER", "SKL-ARCANE-RENEWAL", "SKL-FIRE-BOLT", "SKL-CHAIN-SPARK", "SKL-HEALING-LIGHT", "SKL-VITAL-BARRIER", "SKL-EARTHEN-LANCE" },
	},
	["DOC-DRAGOON"] = {
		signature = nil,
		pool = { "SKL-DRAGON-DIVE", "SKL-SKYFALL-LANCE", "SKL-DECIMATING-SWING", "SKL-LUNGE", "SKL-CRUSHING-ADVANCE", "SKL-POWER-STRIKE", "SKL-GALE-THRUST", "SKL-EXECUTION-STROKE", "SKL-SWEEPING-CUT", "SKL-BATTLE-FURY" },
	},
	["DOC-DUELIST"] = {
		signature = "DOC-DUELIST-01",
		pool = { "SKL-PRECISE-DISARM", "SKL-LUCKY-STRIKE", "SKL-COUNTER-STANCE", "SKL-EXECUTION-STROKE", "SKL-POWER-STRIKE", "SKL-LUNGE", "SKL-HAMSTRING", "SKL-NULL-STRIKE", "SKL-TWIN-FANGS", "SKL-RENDING-SLASH" },
	},
	["DOC-ELEMENTALIST"] = {
		signature = nil,
		pool = { "SKL-PYROCLASM", "SKL-GLACIAL-WAVE", "SKL-STORM-BARRAGE", "SKL-FIRE-BOLT", "SKL-CHAIN-SPARK", "SKL-EARTHEN-LANCE", "SKL-TORRENT-SPEAR", "SKL-IGNITION-LANCE", "SKL-METEOR-MARKER", "SKL-FROSTBIND" },
	},
	["DOC-ENCHANTER"] = {
		signature = nil,
		pool = { "SKL-INVIGORATE", "SKL-ARCANE-RENEWAL", "SKL-EMPOWERING-AURA", "SKL-BENEDICTION", "SKL-GUARDIAN-S-PROJECTION", "SKL-PURIFYING-FORM", "SKL-ARCANE-BARRIER", "SKL-VITAL-BARRIER", "SKL-SUMMON-WARD-TOTEM", "SKL-LIFE-LINK" },
	},
	["DOC-GEOMANCER"] = {
		signature = nil,
		pool = { "SKL-FISSURE-LINE", "SKL-IGNITE-GROUND", "SKL-FLASH-FREEZE", "SKL-STATIC-FIELD", "SKL-STONE-PRISON", "SKL-EARTHEN-LANCE", "SKL-SHATTER-POINT", "SKL-MIASMA-CLOUD", "SKL-RAINFALL-ZONE", "SKL-NATURES-GRASP" },
	},
	["DOC-GUNNER"] = {
		signature = nil,
		pool = { "SKL-STORM-BARRAGE", "SKL-CRIPPLING-SHOT", "SKL-RECOIL-SHOT", "SKL-LONGSHOT", "SKL-SUMMON-TURRET", "SKL-PRECISE-DISARM", "SKL-HAMSTRING", "SKL-TOXIC-NEEDLE", "SKL-POISON-TRAP", "SKL-POWER-STRIKE" },
	},
	["DOC-JUGGERNAUT"] = {
		signature = "DOC-JUGGERNAUT-01",
		pool = { "SKL-DECIMATING-SWING", "SKL-SWEEPING-CUT", "SKL-CRUSHING-ADVANCE", "SKL-POWER-STRIKE", "SKL-SHATTER-POINT", "SKL-SHATTER-BLOW", "SKL-GALE-THRUST", "SKL-EXECUTION-STROKE", "SKL-LUNGE", "SKL-BATTLE-FURY" },
	},
	["DOC-MONK"] = {
		signature = nil,
		pool = { "SKL-FLURRY-OF-BLADES", "SKL-GALE-THRUST", "SKL-BATTLE-FURY", "SKL-TWIN-FANGS", "SKL-RAPID-ASSAULT", "SKL-LUNGE", "SKL-POWER-STRIKE", "SKL-COUNTER-STANCE", "SKL-SHATTER-BLOW", "SKL-RENDING-SLASH" },
	},
	["DOC-PALADIN"] = {
		signature = nil,
		pool = { "SKL-BENEDICTION", "SKL-PURGE", "SKL-BLINDING-FLASH", "SKL-HEALING-LIGHT", "SKL-CONSECRATE", "SKL-HOLY-SMITE", "SKL-SANCTIFY", "SKL-GUARDIAN-S-PROJECTION", "SKL-VITAL-BARRIER", "SKL-SEAL-OF-SILENCE" },
	},
	["DOC-PLAGUE-DOCTOR"] = {
		signature = nil,
		pool = { "SKL-DARK-RESTORATION", "SKL-FESTERING-WOUND", "SKL-MIASMA-CLOUD", "SKL-TOXIC-NEEDLE", "SKL-VENOM-BURST", "SKL-POISON-TRAP", "SKL-WITHER", "SKL-MIND-FRACTURE", "SKL-FIELD-DRESSING", "SKL-PURGE" },
	},
	["DOC-RANGER"] = {
		signature = "DOC-RANGER-01",
		pool = { "SKL-LONGSHOT", "SKL-HAMSTRING", "SKL-CRIPPLING-SHOT", "SKL-RECOIL-SHOT", "SKL-STORM-BARRAGE", "SKL-PRECISE-DISARM", "SKL-TOXIC-NEEDLE", "SKL-POISON-TRAP", "SKL-BLINK", "SKL-POWER-STRIKE" },
	},
	["DOC-REAPER"] = {
		signature = nil,
		pool = { "SKL-BLOOD-PRICE", "SKL-SHADOW-RAKE", "SKL-SIPHON-PULSE", "SKL-DARK-RESTORATION", "SKL-MIND-FRACTURE", "SKL-EXECUTION-STROKE", "SKL-FESTERING-WOUND", "SKL-VANISHING-STEP", "SKL-RENDING-SLASH", "SKL-POWER-STRIKE" },
	},
	["DOC-SENTINEL"] = {
		signature = nil,
		pool = { "SKL-COUNTER-STANCE", "SKL-RETRIBUTION-SHELL", "SKL-SHATTER-BLOW", "SKL-POWER-STRIKE", "SKL-CRUSHING-ADVANCE", "SKL-BASTION-PROJECTION", "SKL-VITAL-BARRIER", "SKL-HEMORRHAGE", "SKL-RENDING-SLASH", "SKL-EXECUTION-STROKE" },
	},
	["DOC-SHADOWBINDER"] = {
		signature = "DOC-SHADOWBINDER-01",
		pool = { "SKL-STONE-PRISON", "SKL-FROSTBIND", "SKL-MIND-FRACTURE", "SKL-WITHER", "SKL-SEAL-OF-SILENCE", "SKL-FESTERING-WOUND", "SKL-MANA-SCORCH", "SKL-BLINDING-FLASH", "SKL-NULL-STRIKE", "SKL-SHATTER-POINT" },
	},
	["DOC-SHIELDBEARER"] = {
		signature = nil,
		pool = { "SKL-BULWARK-FIELD", "SKL-VITAL-BARRIER", "SKL-ARCANE-BARRIER", "SKL-WEAPON-WARD", "SKL-BASTION-PROJECTION", "SKL-RETRIBUTION-SHELL", "SKL-GUARDIAN-S-PROJECTION", "SKL-COUNTER-STANCE", "SKL-PURIFYING-FORM", "SKL-CRUSHING-ADVANCE" },
	},
	["DOC-SKIRMISHER"] = {
		signature = nil,
		pool = { "SKL-HEMORRHAGE", "SKL-RENDING-SLASH", "SKL-NULL-STRIKE", "SKL-LUNGE", "SKL-GALE-THRUST", "SKL-OPPORTUNIST-S-STEP", "SKL-TWIN-FANGS", "SKL-HAMSTRING", "SKL-RECOIL-SHOT", "SKL-POWER-STRIKE" },
	},
	["DOC-SPELLBLADE"] = {
		signature = "DOC-SPELLBLADE-01",
		pool = { "SKL-POWER-STRIKE", "SKL-LUCKY-STRIKE", "SKL-FIRE-BOLT", "SKL-FROSTBIND", "SKL-EARTHEN-LANCE", "SKL-CHAIN-SPARK", "SKL-RAPID-ASSAULT", "SKL-LUNGE", "SKL-ARCANE-BARRIER", "SKL-SHATTER-BLOW" },
	},
	["DOC-STORMBRINGER"] = {
		signature = nil,
		pool = { "SKL-CHAIN-SPARK", "SKL-VOLTAIC-CHAIN", "SKL-THUNDERCLAP", "SKL-STORM-BARRAGE", "SKL-STATIC-FIELD", "SKL-RAINFALL-ZONE", "SKL-FLASH-FREEZE", "SKL-TORRENT-SPEAR", "SKL-MANA-SCORCH", "SKL-GLACIAL-WAVE" },
	},
	["DOC-TACTICIAN"] = {
		signature = "DOC-TACTICIAN-01",
		pool = { "SKL-PHANTOM-EXCHANGE", "SKL-RAINFALL-ZONE", "SKL-STATIC-FIELD", "SKL-FISSURE-LINE", "SKL-INVIGORATE", "SKL-GUARDIAN-S-PROJECTION", "SKL-SUMMON-DECOY", "SKL-FLASH-FREEZE", "SKL-FATED-ESCAPE", "SKL-BLINDING-FLASH" },
	},
	["DOC-TEMPLAR"] = {
		signature = nil,
		pool = { "SKL-HOLY-SMITE", "SKL-SANCTIFY", "SKL-SEAL-OF-SILENCE", "SKL-BLINDING-FLASH", "SKL-BENEDICTION", "SKL-CONSECRATE", "SKL-PURGE", "SKL-HEALING-LIGHT", "SKL-POWER-STRIKE", "SKL-EXECUTION-STROKE" },
	},
	["DOC-THIEF"] = {
		signature = "DOC-THIEF-01",
		pool = { "SKL-STEAL", "SKL-POISON-TRAP", "SKL-TOXIC-NEEDLE", "SKL-HAMSTRING", "SKL-OPPORTUNIST-S-STEP", "SKL-VANISHING-STEP", "SKL-BLINK", "SKL-CRIPPLING-SHOT", "SKL-LUCKY-STRIKE", "SKL-PRECISE-DISARM" },
	},
	["DOC-TRICKSTER"] = {
		signature = "DOC-TRICKSTER-01",
		pool = { "SKL-BLINK", "SKL-FATED-ESCAPE", "SKL-PHANTOM-EXCHANGE", "SKL-VANISHING-STEP", "SKL-OPPORTUNIST-S-STEP", "SKL-SUMMON-DECOY", "SKL-MIND-FRACTURE", "SKL-POISON-TRAP", "SKL-HAMSTRING", "SKL-STATIC-FIELD" },
	},
	["DOC-TWINBLADE"] = {
		signature = "DOC-TWINBLADE-01",
		pool = { "SKL-FLURRY-OF-BLADES", "SKL-TWIN-FANGS", "SKL-RAPID-ASSAULT", "SKL-RENDING-SLASH", "SKL-HEMORRHAGE", "SKL-LUNGE", "SKL-BATTLE-FURY", "SKL-POWER-STRIKE", "SKL-LUCKY-STRIKE", "SKL-SHATTER-BLOW" },
	},
	["DOC-VANGUARD"] = {
		signature = "DOC-VANGUARD-01",
		pool = { "SKL-WEAPON-WARD", "SKL-BASTION-PROJECTION", "SKL-VITAL-BARRIER", "SKL-GUARDIAN-S-PROJECTION", "SKL-BULWARK-FIELD", "SKL-RETRIBUTION-SHELL", "SKL-COUNTER-STANCE", "SKL-CRUSHING-ADVANCE", "SKL-PURIFYING-FORM", "SKL-POWER-STRIKE" },
	},
	["DOC-WARDEN"] = {
		signature = nil,
		pool = { "SKL-EARTHEN-LANCE", "SKL-SHATTER-POINT", "SKL-NATURES-GRASP", "SKL-FISSURE-LINE", "SKL-STONE-PRISON", "SKL-VITAL-BARRIER", "SKL-BULWARK-FIELD", "SKL-CONSECRATE", "SKL-GUARDIAN-S-PROJECTION", "SKL-IGNITE-GROUND" },
	},
	["DOC-WARLORD"] = {
		signature = "DOC-WARLORD-01",
		pool = { "SKL-GUARDIAN-S-PROJECTION", "SKL-CRUSHING-ADVANCE", "SKL-EMPOWERING-AURA", "SKL-POWER-STRIKE", "SKL-SWEEPING-CUT", "SKL-GALE-THRUST", "SKL-BASTION-PROJECTION", "SKL-INVIGORATE", "SKL-BATTLE-FURY", "SKL-EXECUTION-STROKE" },
	},
}

--------------------------------------------------
-- TIER BUILD CONFIG (dev-locked 2026-09-26)
-- Marked so a later DB migration can replace it wholesale.
--------------------------------------------------

local TIER_BUILD = {
	Grunt = {
		baseRt        = 400,
		aiRole        = "Basic",
		normalSkills  = 2,           -- + doctrine/anchor skill = 3 total
		augmentsPer   = 1,
		gearMin       = 3,           -- includes weapon
		gearMax       = 5,
		gearRarities  = { "Common", "Uncommon", "Rare" },
		consumableMin = 1,
		consumableMax = 2,
	},
	Elite = {
		baseRt        = 350,
		aiRole        = "Elite",
		normalSkills  = 3,           -- + doctrine/anchor skill = 4 total
		augmentsPer   = 2,
		gearMin       = 7,           -- full set (weapon + offhand + 5 armor)
		gearMax       = 7,
		gearRarities  = { "Uncommon", "Rare", "Epic" },
		consumableMin = 3,
		consumableMax = 3,
	},
	-- Veteran uses Grunt-like build with a slightly better gear band.
	Veteran = {
		baseRt        = 380,
		aiRole        = "Basic",
		normalSkills  = 2,
		augmentsPer   = 1,
		gearMin       = 4,
		gearMax       = 6,
		gearRarities  = { "Uncommon", "Rare" },
		consumableMin = 1,
		consumableMax = 2,
	},
}

-- Map a quest enemyTypes "type" string to a TIER_BUILD key.
local TYPE_TO_TIER = {
	Grunt   = "Grunt",
	Veteran = "Veteran",
	Elite   = "Elite",
	-- Boss intentionally omitted: authored elsewhere.
}

--------------------------------------------------
-- GEAR ARCHETYPES
--------------------------------------------------

local WEAPON_ARCHETYPES = {
	"WPN-SWORD", "WPN-GREATSWORD", "WPN-RAPIER", "WPN-DAGGER", "WPN-SPEAR",
	"WPN-LANCE", "WPN-HAMMER", "WPN-WARAXE", "WPN-HATCHET", "WPN-CLUB",
	"WPN-FLAIL", "WPN-SCYTHE", "WPN-SICKLE", "WPN-WHIP", "WPN-CHAINS",
	"WPN-CLAWS", "WPN-FLAMEBERGE", "WPN-SWORDBREAKER", "WPN-JAVELIN",
	"WPN-BOOMERANG", "WPN-THROWINGKNIFE", "WPN-LONGBOW", "WPN-GREATBOW",
	"WPN-CROSSBOW", "WPN-BLOWGUN", "WPN-NEEDLE", "WPN-STAFF", "WPN-WAND",
	"WPN-FROSTROD", "WPN-TORCH", "WPN-FAN", "WPN-BELL", "WPN-WARHORN",
	"WPN-PISTOL", "WPN-BAZOOKA", "WPN-MORTAR", "WPN-BALLISTA", "WPN-TORRENT",
}

local OFFHAND_ARCHETYPES = {
	-- Real off-hand archetype ids (WeaponData). "OFF-HAND" was a bogus entry
	-- (a category label, not an archetype) → ItemGenerator failed to resolve it,
	-- logging "Failed to generate OFF-HAND" and leaving the slot empty.
	"OFF-SHIELD", "OFF-BUCKLER", "OFF-PARRYINGDAGGER", "OFF-QUIVER",
	"OFF-ORB", "OFF-CRYSTAL", "OFF-TOME",
}

local ARMOR_SLOTS = { "Head", "Body", "Gloves", "Feet", "Accessory" }

--------------------------------------------------
-- HELPERS
--------------------------------------------------

--- Pick a random element from an array using the provided RNG.
local function pick(rng: Random, list: {any}): any
	if #list == 0 then return nil end
	return list[rng:NextInteger(1, #list)]
end

--- Return a shuffled copy (Fisher-Yates) so we can take N distinct entries.
local function shuffledCopy(rng: Random, list: {any}): {any}
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = rng:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

--- Does a skill's tag set satisfy one augment requirement token?
--- Tokens may be compound with " OR " (e.g. "Direct Damage OR Support"); the
--- token is satisfied if the skill has ANY of the OR-separated options.
local function skillSatisfiesReq(skillTags: {[string]: boolean}, reqToken: string): boolean
	if reqToken == nil or reqToken == "" then return true end
	-- Split on " OR " and trim each option.
	local satisfied = false
	local remaining = reqToken
	while true do
		local sepStart, sepEnd = string.find(remaining, " OR ", 1, true)
		local option
		if sepStart then
			option = string.sub(remaining, 1, sepStart - 1)
			remaining = string.sub(remaining, sepEnd + 1)
		else
			option = remaining
		end
		option = string.gsub(option, "^%s*(.-)%s*$", "%1")
		if option ~= "" and skillTags[option] then
			satisfied = true
			break
		end
		if not sepStart then break end
	end
	return satisfied
end

--- Build a set of a skill's tags.
local function skillTagSet(skillId: string): {[string]: boolean}
	local set = {}
	local def = SkillData[skillId]
	if def and def.tags then
		for _, t in ipairs(def.tags) do set[t] = true end
	end
	return set
end

--- Return the list of augment IDs compatible with a given skill.
local function compatibleAugments(skillId: string): {string}
	local tags = skillTagSet(skillId)
	local out = {}
	for augId, augDef in pairs(AugmentData) do
		local reqs = augDef.requiredSkillTags
		local ok = true
		if reqs and #reqs > 0 then
			for _, reqToken in ipairs(reqs) do
				if not skillSatisfiesReq(tags, reqToken) then
					ok = false
					break
				end
			end
		end
		if ok then table.insert(out, augId) end
	end
	return out
end

--- Choose N distinct augments compatible with a skill (may return fewer if pool small).
local function pickAugmentsForSkill(rng: Random, skillId: string, count: number): {string}
	local compat = compatibleAugments(skillId)
	if #compat == 0 then return {} end
	local shuffled = shuffledCopy(rng, compat)
	local out = {}
	for i = 1, math.min(count, #shuffled) do
		out[i] = shuffled[i]
	end
	return out
end

--- Equip a freshly generated item into a slot (enemies bypass player inventory).
local function equipGenerated(unit: any, archetypeId: string, itemLevel: number, rarity: string, seed: number, slot: string)
	local item = ItemGenerator.Generate({
		baseArchetypeId = archetypeId,
		itemLevel       = itemLevel,
		rarity          = rarity,
		seed            = seed,
		sourceType      = "EnemyGen",
	})
	if not item then
		warn(string.format("[EnemyGenerator] Failed to generate %s (%s) for %s", archetypeId, rarity, unit.name or unit.id))
		return false
	end
	local ok = EquipmentService.Equip(unit, item, slot)
	return ok ~= false
end

--- Shared insertion tail: harden id against collision with a live unit, assign a
--- fresh stableOrderKey at the end of the roster, and insert into state.units so
--- the unit joins the RT/CT timeline naturally. Reused by BOTH SpawnReinforcement
--- and SpawnSummon so the spawner tail lives in ONE place (not duplicated).
--- SIDE is set by the caller BEFORE calling this; this helper never touches it.
local function insertUnitIntoBattle(unit, state)
	local baseId = unit.id
	local suffix = 0
	local existing = {}
	for _, u in ipairs(state.units) do existing[u.id] = true end
	while existing[unit.id] do
		suffix += 1
		unit.id = baseId .. "_s" .. suffix
	end
	unit.stableOrderKey = #state.units + 1
	table.insert(state.units, unit)
end

--------------------------------------------------
-- SINGLE ENEMY
--------------------------------------------------

--- Generate one enemy unit.
--- @param spec table   { type = "Grunt"|"Veteran"|"Elite", level = number }
--- @param index number 1-based index (for id/name/spawn)
--- @param spawn table  { x = number, y = number }
--- @param rng Random   deterministic stream
-- Enemy name = <first word from the RARER of perk/flaw> <word from doctrine>.
-- Tie on rarity -> flaw wins. Falls back to the old "Type N" name if pools are missing.
local function traitTierRank(traitId: string?): number
	if not traitId then return 0 end
	local def = TraitData[traitId] or (TraitData.Traits and TraitData.Traits[traitId])
	local tier = def and def.tier
	return (tier and UnitNameData.TierRank[tier]) or 0
end

local function buildEnemyName(rng, unit, fallback: string): string
	local perkId = unit.perkIds and unit.perkIds[1]
	local flawId = unit.drawbackIds and unit.drawbackIds[1]
	local chosen = flawId
	if traitTierRank(perkId) > traitTierRank(flawId) then chosen = perkId end
	local firstPool = chosen and UnitNameData.FirstWords[chosen]
	local docPool = UnitNameData.DoctrineWords[unit.doctrineId]
	if not firstPool or not docPool then
		warn(`[EnemyGenerator] Name pools missing (trait={tostring(chosen)}, doctrine={tostring(unit.doctrineId)}) - using fallback`)
		return fallback
	end
	return `{firstPool[rng:NextInteger(1, #firstPool)]} {docPool[rng:NextInteger(1, #docPool)]}`
end

function EnemyGenerator.GenerateEnemy(spec: {type: string, level: number}, index: number, spawn: {x: number, y: number}, rng: Random): any?
	local tierKey = TYPE_TO_TIER[spec.type]
	if not tierKey then
		warn("[EnemyGenerator] Unsupported enemy type (skipped): " .. tostring(spec.type))
		return nil
	end
	local tier = TIER_BUILD[tierKey]
	local level = math.max(1, spec.level or 1)

	-- 1. Random race.
	local raceIds = RaceData.GetAllIds()
	local raceId  = pick(rng, raceIds)

	-- 2. Random doctrine (of the 32 with authored skill pools).
	local doctrineIds = {}
	for did in pairs(DOCTRINE_SKILL_POOLS) do table.insert(doctrineIds, did) end
	table.sort(doctrineIds)  -- deterministic ordering before random pick
	local doctrineId = pick(rng, doctrineIds)
	local dp = DOCTRINE_SKILL_POOLS[doctrineId]

	-- 3. Skills: doctrine/anchor skill + N pool skills.
	local doctrineSkill = dp.signature
	local poolCopy = shuffledCopy(rng, dp.pool)
	local normalSkills = {}
	local needed = tier.normalSkills
	-- If this doctrine has no separate signature, the anchor is pool[1]; use it as
	-- the doctrine skill and draw the normal skills from the remaining pool.
	local drawFrom = poolCopy
	if not doctrineSkill then
		-- anchor = first pool entry (stable: dp.pool[1]); avoid duplicating it below
		doctrineSkill = dp.pool[1]
		drawFrom = {}
		for _, s in ipairs(poolCopy) do
			if s ~= doctrineSkill then table.insert(drawFrom, s) end
		end
	end
	for i = 1, math.min(needed, #drawFrom) do
		table.insert(normalSkills, drawFrom[i])
	end

	-- 4. Create the unit (stats from race + level; tier base RT).
	local unit = UnitSchema.Create({
		id         = string.format("enemy_%s_%d", string.lower(spec.type), index),
		name       = string.format("%s %d", spec.type, index),
		side       = "Enemy",
		controller = "AI",
		-- aiRole retired 2026-09-26: the AI brain now reads personality from the
		-- unit's doctrine (doctrines.AI_Personality), not a per-tier aiRole tag.
		-- Field left in TIER_BUILD as vestigial config; no longer passed to units.
		raceId     = raceId,
		level      = level,
		doctrineId = doctrineId,
		tileX      = spawn.x,
		tileY      = spawn.y,
		-- Starting RT is set in step 9 below (LUK formula on the TIER base RT,
		-- after gear/doctrine so the final effective LUK is used).
	})

	-- 5. Wire skills into the loadout structure the combat/AI systems read.
	unit.selectedDoctrineSkill = doctrineSkill
	-- Tier tag for client display (silver-star Veteran / gold-star Elite name prefix).
	unit.enemyType = spec.type
	-- Perks & Flaws Phase 1: roll 1 perk + 1 flaw at spawn (data only, no gameplay
	-- effect yet). AssignIfEmpty guards re-roll; recruited enemies retain these.
	TraitRoller.AssignIfEmpty(unit, rng)
	unit.name = buildEnemyName(rng, unit, unit.name)
	unit.doctrineAugments      = pickAugmentsForSkill(rng, doctrineSkill, tier.augmentsPer)
	unit.skillLoadout          = {}
	local slotNames = { "slot2", "slot3", "slot4" }
	for i, skillId in ipairs(normalSkills) do
		local slotKey = slotNames[i]
		if slotKey then
			unit.skillLoadout[slotKey] = {
				skillId  = skillId,
				augments = pickAugmentsForSkill(rng, skillId, tier.augmentsPer),
			}
		end
	end
	-- Keep skillIds in sync (some readers use the flat array).
	unit.skillIds = { doctrineSkill }
	for _, s in ipairs(normalSkills) do table.insert(unit.skillIds, s) end

	-- 6. Gear. Weapon is always slot 1; then offhand + armor up to the tier's gear count.
	local gearCount = rng:NextInteger(tier.gearMin, tier.gearMax)
	local itemLevel = level
	local function rarityRoll(): string
		return pick(rng, tier.gearRarities)
	end
	local seedBase = rng:NextInteger(1, 2147483647)

	-- Weapon (mandatory).
	equipGenerated(unit, pick(rng, WEAPON_ARCHETYPES), itemLevel, rarityRoll(), seedBase, "MainHand")
	local placed = 1

	-- Remaining gear: shuffle armor slots + offer offhand, fill until gearCount.
	local remainingSlots = shuffledCopy(rng, ARMOR_SLOTS)
	-- 50/50 chance to include an offhand first (skipped for 2H weapons by ValidateEquip).
	if placed < gearCount and rng:NextNumber() < 0.5 then
		if equipGenerated(unit, pick(rng, OFFHAND_ARCHETYPES), itemLevel, rarityRoll(), seedBase + placed, "OffHand") then
			placed += 1
		end
	end
	-- Armor pieces by slot.
	local armorIds = ArmorData.GetAllIds()
	-- Group armor archetypes by slot once.
	local armorBySlot: {[string]: {string}} = {}
	for _, aid in ipairs(armorIds) do
		local def = ArmorData.GetByArchetypeId(aid)
		if def and def.slot then
			armorBySlot[def.slot] = armorBySlot[def.slot] or {}
			table.insert(armorBySlot[def.slot], aid)
		end
	end
	for _, slot in ipairs(remainingSlots) do
		if placed >= gearCount then break end
		local pool = armorBySlot[slot]
		if pool and #pool > 0 then
			if equipGenerated(unit, pick(rng, pool), itemLevel, rarityRoll(), seedBase + placed, slot) then
				placed += 1
			end
		end
	end

	-- 7. Consumables.
	unit.consumableSlots     = {}
	unit.consumableSlotCount = 3
	unit.maxConsumableSlots  = 6
	local consIds = ConsumableData.GetAllIds()
	local consCount = rng:NextInteger(tier.consumableMin, tier.consumableMax)
	local consShuffled = shuffledCopy(rng, consIds)
	for i = 1, math.min(consCount, #consShuffled, unit.consumableSlotCount) do
		local cid = consShuffled[i]
		local cdef = ConsumableData.GetById(cid)
		unit.consumableSlots[i] = {
			consumableId   = cid,
			currentCharges = (cdef and cdef.charges) or 1,
		}
	end

	-- 8. Rebuild effective stats from doctrine + equipment.
	if EquipmentService.RebuildUnitStats then
		EquipmentService.RebuildUnitStats(unit)
	end

	-- Full HP on spawn. UnitSchema set currentHp from the unit's BARE maxHp
	-- (before armor/doctrine), and RebuildUnitStats raised maxHp but only clamps
	-- currentHp DOWN — leaving a freshly generated enemy below full. Top it up.
	-- (MP intentionally left as-is per design: enemies may spawn under full MP.)
	unit.currentHp = unit.maxHp

	-- 9. LUK Starting RT — DB core_stats id 54 STEP 1 (symmetric with players):
	--    Starting RT = round(Base RT x (1 - 0.30 x LUK / (100 + LUK))), where Base RT
	--    is the enemy's TIER base RT (Grunt 400 / Veteran 380 / Elite 350), NOT a flat
	--    400. Enemies do NOT get the Player Initiative Edge (STEP 2 is player-only).
	local lukNow = (unit.effectiveStats and unit.effectiveStats.LUK)
		or (unit.baseStats and unit.baseStats.LUK) or 10
	unit.initiativeBaseRt = tier.baseRt
	-- Starting RT (one-time) now derives from Modified Base RT so gear WT + permanent
	-- modifiers flow into the first turn too (initiativeBaseRt set above feeds it).
	-- Trait Starting-RT % (Timeline Sovereign/Temporal Drag) layers on the one-time
	-- reduction (symmetric with players; enemies get no Player Initiative Edge).
	-- Single rounding (DB core_stats 54): raw Modified Base RT × LUK factor × trait %.
	local egModBaseRt = StatusService.GetModifiedBaseRt(unit)
	local egLukFactor = 1 - 0.30 * lukNow / (100 + lukNow)
	unit.remainingRt = math.round(egModBaseRt * egLukFactor * TraitEffectService.GetStartingRtMultiplier(unit))

	print(string.format("[EnemyGenerator] %s (%s) L%d | race=%s doctrine=%s | skills=%d gear=%d/%d cons=%d | startRT=%d (tierBase %d, LUK %d)",
		unit.name, spec.type, level, tostring(raceId), doctrineId,
		#unit.skillIds, placed, gearCount, #consShuffled > 0 and math.min(consCount, unit.consumableSlotCount) or 0,
		unit.remainingRt, tier.baseRt, lukNow))

	return unit
end

--------------------------------------------------
-- FULL ROSTER
--------------------------------------------------

--- Expand a quest's enemyTypes into concrete enemy units placed on enemy spawns.
--- @param enemyTypes table  list of { type, level, count }
--- @param enemySpawns table list of { x, y } (from generatedMap.deploymentZones.enemy)
--- @param rng Random        deterministic stream (e.g. seedCtx.enemyRng)
--- @return {any}            list of created enemy units (Boss entries skipped)
function EnemyGenerator.GenerateEnemies(enemyTypes: {any}, enemySpawns: {any}, rng: Random): {any}
	local units = {}
	local spawnIdx = 1
	local created = 0
	for _, entry in ipairs(enemyTypes) do
		local count = entry.count or 1
		for _ = 1, count do
			local spawn = enemySpawns[spawnIdx] or enemySpawns[#enemySpawns] or { x = 1, y = 1 }
			local unit = EnemyGenerator.GenerateEnemy(
				{ type = entry.type, level = entry.level },
				created + 1, spawn, rng
			)
			if unit then
				table.insert(units, unit)
				created += 1
				spawnIdx += 1
			end
		end
	end
	print(string.format("[EnemyGenerator] Generated %d enemy unit(s) from %d type group(s).", created, #enemyTypes))
	return units
end

--------------------------------------------------
-- MID-BATTLE REINFORCEMENT
--------------------------------------------------
-- Counter for collision-free ids across all mid-battle spawns in a battle.
local _reinforcementCounter = 0

--- Spawn ONE new unit into a LIVE battle (map-object summons: Dragon Utopia,
--- Mimic, Refugee Camp). Reuses GenerateEnemy so the unit is identical in shape
--- to battle-start enemies (stats from race+level, tier base RT, full HP, gear,
--- skills). Then it is inserted into state.units with a fresh stableOrderKey so
--- it joins the RT timeline naturally (BattleCoordinator iterates state.units
--- live each loop; checkBattleEnd recounts live). The CALLER broadcasts
--- UnitSpawned (ObjectEffectService has BattleVisualBroadcaster; EnemyGenerator
--- deliberately does not, to keep its dependency surface unchanged / cycle-free).
---
--- @param spec table    { type = <tier string e.g. "Grunt"/"Elite">, level = n }
--- @param spawnTile table { x, y } tile to place the unit on
--- @param state table   the live battle state (has .units)
--- @param rng Random    deterministic stream
--- @param side string?  "Enemy" (default) or "Neutral" (Refugee Camp)
--- @param raceOverride string? optional raceId to force (e.g. Dragon = RACE-DRAGONKIN)
--- @return any?         the created unit, or nil on failure
function EnemyGenerator.SpawnReinforcement(spec, spawnTile, state, rng, side, raceOverride)
	if type(spec) ~= "table" or type(state) ~= "table" or not state.units then
		warn("[EnemyGenerator] SpawnReinforcement: bad spec/state")
		return nil
	end
	_reinforcementCounter += 1
	-- Index chosen to avoid id collision with battle-start enemies and with
	-- other reinforcements: base it on current roster size + the running counter.
	local index = #state.units + _reinforcementCounter + 1000

	local spawn = spawnTile or { x = 1, y = 1 }
	local unit = EnemyGenerator.GenerateEnemy(
		{ type = spec.type, level = spec.level or 1 },
		index, spawn, rng
	)
	if not unit then
		warn("[EnemyGenerator] SpawnReinforcement: GenerateEnemy returned nil")
		return nil
	end

	-- Side: Enemy by default; Neutral for friendly summons (Refugee Camp).
	if side == "Neutral" then
		unit.side = "Neutral"
	else
		unit.side = "Enemy"
	end

	-- Optional race override (Dragon Utopia -> Dragonkin). Rebuild stats so the
	-- race change is reflected, then top HP back to full (RebuildUnitStats only
	-- clamps down).
	if raceOverride and unit.raceId ~= raceOverride then
		unit.raceId = raceOverride
		if EquipmentService.RebuildUnitStats then
			EquipmentService.RebuildUnitStats(unit)
			unit.currentHp = unit.maxHp
		end
	end

	-- Shared insertion tail (id-uniqueness + timeline join + roster insert).
	insertUnitIntoBattle(unit, state)

	print(string.format(
		"[EnemyGenerator] SpawnReinforcement | %s (%s, side=%s) at (%d,%d) | id=%s | roster now %d",
		unit.name, spec.type, unit.side, spawn.x, spawn.y, unit.id, #state.units))
	return unit
end

--------------------------------------------------
-- SPAWN TILE SEARCH (shared by every spawner that has no authored target tile:
-- map-object summons, battlefield events). A tile is free when it is in bounds,
-- passable terrain, not a blocker (solid object), and not held by a LIVING unit.
-- KO'd units (isAlive == false) never block a spawn.
--------------------------------------------------
function EnemyGenerator.IsSpawnTileFree(state, x: number, y: number): boolean
	local grid = GameConstants.TERRAIN_MAP
	local h = grid and #grid or 0
	local w = (h > 0 and grid[1]) and #grid[1] or 0
	if x < 1 or y < 1 or x > w or y > h then return false end
	if GameConstants.IsImpassableTerrain and GameConstants.IsImpassableTerrain(x, y) then return false end
	if GameConstants.IsBlocked and GameConstants.IsBlocked(x, y) then return false end
	if state and state.units then
		for _, u in state.units do
			if u.isAlive and u.tileX == x and u.tileY == y then return false end
		end
	end
	return true
end

-- Nearest free tile to (cx,cy): Chebyshev rings outward to the whole map. All
-- free tiles in the NEAREST ring that has any are collected, and one is picked at
-- random with `rng` (user rule 2026-10-07). Pass a seeded Random to stay
-- deterministic; with no rng the first tile in scan order is used.
-- Returns { x, y } or nil if the map has no free tile.
function EnemyGenerator.FindNearestFreeSpawnTile(state, cx: number, cy: number, rng: Random?)
	local grid = GameConstants.TERRAIN_MAP
	local h = grid and #grid or 0
	local w = (h > 0 and grid[1]) and #grid[1] or 0
	for r = 0, math.max(w, h) do
		local candidates = {}
		for dx = -r, r do
			for dy = -r, r do
				if math.max(math.abs(dx), math.abs(dy)) == r then
					local x, y = cx + dx, cy + dy
					if EnemyGenerator.IsSpawnTileFree(state, x, y) then
						table.insert(candidates, { x = x, y = y })
					end
				end
			end
		end
		if #candidates > 0 then
			if rng and #candidates > 1 then
				return candidates[rng:NextInteger(1, #candidates)]
			end
			return candidates[1]
		end
	end
	return nil
end

--------------------------------------------------
-- SUMMON SPAWN (skill summons: Conjurer Sentinel/Wisp/Mender,
-- general-pool Decoy/Turret/Ward Totem)
--------------------------------------------------
-- Thin spawner that REUSES the shared insertion tail above but builds the unit
-- from AUTHORED caster-percentage stats (passed in by CommandService) instead of
-- GenerateEnemy's random race/gear. This is the one path that can express
-- "stats = X% of the caster" and allows side = the caster's side (including
-- "Player") — the two things SpawnReinforcement cannot do. All numbers are
-- authored (SkillData powerFormula); this function invents none.
--
-- @param summonSpec table   {
--     id, name, side ("Player"/"Enemy"/"Neutral"), level,
--     stats = { STR,AGI,INT,VIT,DEX,LUK },   -- already computed as % of caster
--     maxHp,                                 -- authored % of caster Max HP
--     weaponDamage, weaponMinRange, weaponMaxRange, weaponProjectileType,
--     summonType, summonOwnerId, summonProfile,
--     canMove (bool), isFlying (bool), auraSpec (table?), turretSnapshotDamage (n?),
--     skillIds ({string}?)                   -- e.g. Mender's heal skill
--   }
-- @param spawnTile table    { x, y } tile to place the unit on
-- @param state table        the live battle state (has .units)
-- @return any?              the created unit, or nil on failure
function EnemyGenerator.SpawnSummon(summonSpec, spawnTile, state)
	if type(summonSpec) ~= "table" or type(state) ~= "table" or not state.units then
		warn("[EnemyGenerator] SpawnSummon: bad summonSpec/state")
		return nil
	end
	local spawn = spawnTile or { x = 1, y = 1 }

	-- Build the summon via UnitSchema.Create from the AUTHORED stat table (legacy
	-- stats path). Summons carry NO equipment; weapon fields are passed flat so the
	-- existing AI/combat read them directly (Sentinel melee R1, Wisp/Turret ranged).
	local unit = UnitSchema.Create({
		id         = summonSpec.id or "summon",
		name       = summonSpec.name or "Summon",
		side       = summonSpec.side or "Enemy",
		-- Player-side summons are PLAYER-CONTROLLED (user ruling 2026-10-06,
		-- frameworks id 38); enemy-side summons stay AI-controlled.
		controller = ((summonSpec.side or "Enemy") == "Player") and "Player" or "AI",
		level      = summonSpec.level or 1,
		stats      = summonSpec.stats,
		tileX      = spawn.x,
		tileY      = spawn.y,
		maxMp      = 0,              -- summons spend no MP
		weaponDamage         = summonSpec.weaponDamage or 0,
		weaponWt             = 0,    -- no weapon weight (RT entry is authored, below)
		weaponMinRange       = summonSpec.weaponMinRange or 1,
		weaponMaxRange       = summonSpec.weaponMaxRange or 1,
		weaponProjectileType = summonSpec.weaponProjectileType or nil,
		skillIds   = summonSpec.skillIds or {},
		-- Authored summon fields (UnitSchema passes these through verbatim).
		isSummon           = true,
		summonType         = summonSpec.summonType,
		summonOwnerId      = summonSpec.summonOwnerId,
		summonProfile      = summonSpec.summonProfile,
		canMove            = summonSpec.canMove,
		isFlying           = summonSpec.isFlying,
		auraSpec           = summonSpec.auraSpec,
		turretSnapshotDamage = summonSpec.turretSnapshotDamage,
		rewardEligible     = false,
		killTriggerEligible = false,
	})
	if not unit then
		warn("[EnemyGenerator] SpawnSummon: UnitSchema.Create returned nil")
		return nil
	end

	-- Authored Max HP override (% of caster Max HP). Set after Create so it wins
	-- over the VIT-derived default; top currentHp to the authored max.
	if summonSpec.maxHp then
		unit.maxHp = math.max(1, math.round(summonSpec.maxHp))
		unit.currentHp = unit.maxHp
	end

	-- All summons enter the timeline at RT 400 (authored "standard summon rule").
	-- Summons wait a full Base RT before acting (frameworks id 38): 400 unless the
	-- summon's authored rule specifies its own Base RT.
	local summonBaseRt = tonumber(summonSpec.baseRt) or 400
	unit.remainingRt = summonBaseRt
	unit.initiativeBaseRt = summonBaseRt
	-- Tier tag nil (summons are not Grunt/Veteran/Elite; client shows no tier star).
	unit.enemyType = nil

	-- Shared insertion tail (id-uniqueness + timeline join + roster insert).
	insertUnitIntoBattle(unit, state)

	print(string.format(
		"[EnemyGenerator] SpawnSummon | %s (type=%s, side=%s) at (%d,%d) | id=%s | HP=%d | roster now %d",
		unit.name, tostring(summonSpec.summonType), unit.side, spawn.x, spawn.y,
		unit.id, unit.maxHp, #state.units))
	return unit
end

return EnemyGenerator
