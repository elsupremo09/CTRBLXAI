-- AffixData.lua
-- CTRBLXAI | Item Affix Name Lookup
-- Auto-generated from CTRBLXAI.db item_affix_names table.
-- Do not edit manually. Regenerate from database.

local AffixData = {}

-- Numerical: family -> tier -> affix name
AffixData.Numerical = {
	["AGI Bonus"] = { [1] = "Nimble", [2] = "Swift", [3] = "Flickering", [4] = "Tempest", [5] = "Phantom", [6] = "Windborn" },
	["Collision Damage"] = { [1] = "Ramming", [2] = "Crushing", [3] = "Shattering", [4] = "Obliterating" },
	["Collision Resistance"] = { [1] = "Braced", [2] = "Anchored", [3] = "Immovable", [4] = "Unshakable" },
	["DEX Bonus"] = { [1] = "Precise", [2] = "Deft", [3] = "Masterwork", [4] = "Razortuned", [5] = "Flawless", [6] = "Sovereign" },
	["Debuff Resistance"] = { [1] = "Cleansing", [2] = "Purifying", [3] = "Sanctified", [4] = "Incorruptible" },
	["Equipment Defense"] = { [1] = "Plated", [2] = "Reinforced", [3] = "Bastion", [4] = "Impervious", [5] = "Adamantine" },
	["Evasiveness"] = { [1] = "Elusive", [2] = "Ghostly", [3] = "Shadowdancer's", [4] = "Untouchable" },
	["Fall Damage Decrease"] = { [1] = "Cushioned", [2] = "Catfall", [3] = "Featherfall", [4] = "Cloudwalker's" },
	["Fall Resistance"] = { [1] = "Grounded", [2] = "Steadfast", [3] = "Rootbound", [4] = "Earthlocked" },
	["Fortune"] = { [1] = "Prosperous", [2] = "Gilded", [3] = "Fateweaver's", [4] = "Miraculous" },
	["HP"] = { [1] = "Vital", [2] = "Enduring", [3] = "Lifebound", [4] = "Undying", [5] = "Immortal" },
	["Healing Output"] = { [1] = "Mending", [2] = "Restorative", [3] = "Lifegiver's", [4] = "Asclepian" },
	["INT Bonus"] = { [1] = "Keen", [2] = "Arcane", [3] = "Brilliant", [4] = "Sagefire", [5] = "Transcendent", [6] = "Omniscient" },
	["Item Direct Damage"] = { [1] = "Volatile", [2] = "Explosive", [3] = "Cataclysmic", [4] = "Ruinous" },
	["LUK Bonus"] = { [1] = "Lucky", [2] = "Fortunate", [3] = "Fateblessed", [4] = "Starborn", [5] = "Providence", [6] = "Destined" },
	["MP"] = { [1] = "Channeling", [2] = "Resonant", [3] = "Spellwoven", [4] = "Manaforged", [5] = "Infinite" },
	["Precision"] = { [1] = "True", [2] = "Marksman's", [3] = "Deadeye", [4] = "Unerring" },
	["RT Delay Resistance"] = { [1] = "Resolute", [2] = "Ironwilled", [3] = "Unfaltering", [4] = "Indomitable" },
	["STR Bonus"] = { [1] = "Sturdy", [2] = "Mighty", [3] = "Herculean", [4] = "Titanic", [5] = "Colossal", [6] = "Godslayer's" },
	["Skill Potency"] = { [1] = "Empowered", [2] = "Overcharged", [3] = "Cataclyst's", [4] = "Worldbreaker's" },
	["VIT Bonus"] = { [1] = "Hardy", [2] = "Stalwart", [3] = "Ironhide", [4] = "Unyielding", [5] = "Mountainborn", [6] = "Eternal" },
	["Weapon Attack"] = { [1] = "Honed", [2] = "Brutal", [3] = "Vicious", [4] = "Devastating", [5] = "Annihilating" },
	["Weapon Defense"] = { [1] = "Warding", [2] = "Deflecting", [3] = "Bulwark", [4] = "Fortress" },
	["Weapon RT Delay"] = { [1] = "Staggering", [2] = "Jarring", [3] = "Concussive", [4] = "Crippling" },
	["Weight Reduction"] = { [1] = "Light", [2] = "Featherweight", [3] = "Weightless", [4] = "Ethereal", [5] = "Void-Touched" },
}

-- Passive: passive_id -> affix name
AffixData.Passive = {
	["PAS-001"] = "Brutality",
	["PAS-002"] = "Swiftness",
	["PAS-003"] = "Reach",
	["PAS-004"] = "Sundering",
	["PAS-005"] = "Vampirism",
	["PAS-006"] = "Vengeance",
	["PAS-007"] = "the Tempest",
	["PAS-008"] = "Execution",
	["PAS-009"] = "Cleaving",
	["PAS-010"] = "Dominion",
	["PAS-011"] = "Affliction",
	["PAS-012"] = "Searing",
	["PAS-013"] = "Frost",
	["PAS-014"] = "Thunder",
	["PAS-015"] = "Silence",
	["PAS-016"] = "Binding",
	["PAS-017"] = "the Bulwark",
	["PAS-018"] = "the Fortress",
	["PAS-019"] = "Retribution",
	["PAS-020"] = "Endurance",
	["PAS-021"] = "the Phoenix",
	["PAS-022"] = "Momentum",
	["PAS-023"] = "Ambush",
	["PAS-024"] = "the Hawk",
	["PAS-025"] = "Siphoning",
	["PAS-026"] = "Channeling",
	["PAS-027"] = "Overflow",
	["PAS-028"] = "Displacement",
	["PAS-029"] = "the Colossus",
	["PAS-030"] = "Piercing",
	["PAS-031"] = "the Wind",
	["PAS-032"] = "the Sentinel",
	["PAS-033"] = "Shattering",
	["PAS-034"] = "the Mystic",
	["PAS-035"] = "Harvesting",
	["PAS-036"] = "the Warden",
}

return AffixData