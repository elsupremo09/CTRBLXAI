-- VFXRegistry.lua
-- CTRBLXAI | Maps combat events (skills, elements, statuses, attacks) to the
-- pre-made VFX asset NAMES in ReplicatedStorage/CTRBLXAI/VFX (created in Studio).
-- The client (VFXController.PlayAsset) clones the named asset and plays it.
--
-- Resolution order for a skill (VFXController.ResolveSkill):
--   1. BySkillId[skillId]        — explicit per-skill override (highest priority)
--   2. ByElement[<tag>]          — element tag from SkillData.tags (Fire/Ice/...)
--   3. ByProperty[<property>]    — melee vs ranged/projectile from SkillData
--   4. DefaultSkill              — catch-all
-- Names MUST match the Instance names in the VFX folder exactly (case-sensitive).
-- Unmapped/misspelled names fall back gracefully (VFXController keeps its
-- programmatic effect), so a wrong name never errors — it just won't show art.

local VFXRegistry = {}

-- Element tag (from SkillData.tags) -> VFX asset name.
VFXRegistry.ByElement = {
	Fire      = "Projectile Fire",
	Ice       = "Ice Blast",
	Electric  = "Lighting Strike",
	Lightning = "Lighting Strike",
	Holy      = "Ground Shiny",
	Dark      = "Corruption Gas",
	Poison    = "Poison Gas",
	Water     = "Splashing Water",
	Physical  = "Hit",
}

-- SkillData 'properties'/pattern hint -> VFX. Used when no element matches.
-- Keys are lowercase substrings checked against the skill's properties string.
VFXRegistry.ByProperty = {
	["projectile"] = "Projectile Orb",
	["melee"]      = "Multi-Slash",
	["line"]       = "Flamethrower-01",
	["burst"]      = "Bursty",
	["aoe"]        = "Erruption",
}

-- Explicit per-skill overrides (skillId -> VFX asset name). Highest priority.
-- Fill these in for signature skills whose element default isn't ideal.
VFXRegistry.BySkillId = {
	["SKL-FIRE-BOLT"]     = "Projectile Fire",
	["SKL-FROSTBIND"]     = "Ice Blast",
	["SKL-HEALING-LIGHT"] = "Heal",
	["SKL-METEOR-MARKER"] = "Nuke",
	["SKL-SWEEPING-CUT"]  = "Multi-Slash",
	["SKL-POWER-STRIKE"]  = "Punch-03",
	["SKL-LONGSHOT"]      = "Arrow Right",
	["SKL-SEAL-OF-SILENCE"] = "Hit Magic",
	["DOC-BERSERKER-01"]  = "Charge 1",
}

-- Status id -> VFX asset name (played on StatusApplied / persists per tick).
VFXRegistry.ByStatus = {
	Poison  = "Poison Gas",
	Venom   = "Poison Gas",
	Burn    = "Ground Flames",
	Bleed   = "Bleed",
	Blind   = "Blinded",
	Shocked = "Shocked",
	Frozen  = "Ice Blast",
	Stun    = "Shocked",
	Sleep   = "Zzz",
	Guard   = "Shield-01",
	Haste   = "Stats Up",
	Regeneration = "Heal",
	Cursed  = "Corruption Gas",
	Silence = "Hit Magic",
}

-- Attack/action-type fallbacks (no skill, or nothing else matched).
VFXRegistry.Melee      = "Multi-Slash"   -- close-range basic attack
VFXRegistry.Ranged     = "Projectile Orb" -- long-range basic attack
VFXRegistry.Impact     = "Hit"            -- generic hit spark at target
VFXRegistry.Heal       = "Heal"
VFXRegistry.KO         = "Black Hole"
VFXRegistry.GuardUp    = "Shield-01"
VFXRegistry.Channel    = "Channeling"
VFXRegistry.DefaultSkill = "Hit Magic"   -- skill with no element/property/override

return VFXRegistry