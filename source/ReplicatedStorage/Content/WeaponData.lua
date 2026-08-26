-- WeaponData.lua
-- CTRBLXAI | Slice 4A — Equipment Foundation
-- Auto-generated from CTRBLXAI.db weapons_equipment catalog.
-- Do not edit manually. Regenerate from database.
--
-- All stats are L99 endpoints. Use ItemLevelScale to get actual values.
-- Scale(L) = 0.30 + 0.70 * ((L - 1) / 98) ^ 0.55
-- Scaled properties: damage, wt, rtDelay, defense (sign preserved).
-- NOT scaled: range, pattern, projectileType, handClass, passives.

local WeaponData = {}

--------------------------------------------------
-- ITEM LEVEL SCALING
--------------------------------------------------

function WeaponData.GetScale(itemLevel)
	if itemLevel < 1 then itemLevel = 1 end
	if itemLevel == 99 then return 1.0 end
	return 0.30 + 0.70 * ((itemLevel - 1) / 98) ^ 0.55
end

function WeaponData.ScaleProperty(l99Value, itemLevel)
	if l99Value == 0 then return 0 end
	local scale = WeaponData.GetScale(itemLevel)
	return math.round(l99Value * scale)
end

--------------------------------------------------
-- ARCHETYPE CATALOG
-- numericId: compact save ID
-- Stats are L99 values. Zero stays zero. Negative retains sign.
--------------------------------------------------

WeaponData.Archetypes = {
	-- === 2H MELEE ===
	["WPN-GREATSWORD"] = {
		numericId = 1, name = "Greatsword", category = "Weapon",
		damage = 65, wt = 165, rtDelay = 28, defense = 10,
		handClass = "2H", minRange = 1, maxRange = 1,
		pattern = "Cleave", projectileType = nil,
		nativePassiveId = nil, nativePassiveBp = 0, totalBp = 1000,
	},
	["WPN-CLAWS"] = {
		numericId = 2, name = "Claws", category = "Weapon",
		damage = 45, wt = 25, rtDelay = 110, defense = -5,
		handClass = "2H", minRange = 1, maxRange = 1,
		pattern = "Single", projectileType = nil,
		nativePassiveId = "Stagger", nativePassiveBp = 100, totalBp = 988,
	},
	["WPN-WARAXE"] = {
		numericId = 3, name = "War Axe", category = "Weapon",
		damage = 97, wt = 107, rtDelay = 20, defense = -20,
		handClass = "2H", minRange = 1, maxRange = 1,
		pattern = "Single", projectileType = nil,
		nativePassiveId = "Brutal", nativePassiveBp = 100, totalBp = 1000,
	},
	["WPN-SPEAR"] = {
		numericId = 4, name = "Spear", category = "Weapon",
		damage = 42, wt = 90, rtDelay = 45, defense = 21,
		handClass = "2H", minRange = 1, maxRange = 2,
		pattern = "Line2", projectileType = nil,
		nativePassiveId = "Fortify", nativePassiveBp = 120, totalBp = 1011,
	},
	["WPN-HAMMER"] = {
		numericId = 5, name = "Hammer", category = "Weapon",
		damage = 80, wt = 130, rtDelay = 110, defense = 5,
		handClass = "2H", minRange = 1, maxRange = 1,
		pattern = "Single", projectileType = nil,
		nativePassiveId = "Knockback", nativePassiveBp = 150, totalBp = 1004,
	},
	-- === 1H MELEE ===
	["WPN-SWORD"] = {
		numericId = 6, name = "Sword", category = "Weapon",
		damage = 67, wt = 60, rtDelay = 60, defense = 5,
		handClass = "1H", minRange = 1, maxRange = 1,
		pattern = "Single", projectileType = nil,
		nativePassiveId = nil, nativePassiveBp = 0, totalBp = 1000,
	},
	["WPN-DAGGER"] = {
		numericId = 7, name = "Dagger", category = "Weapon",
		damage = 60, wt = 10, rtDelay = 20, defense = 6,
		handClass = "1H", minRange = 1, maxRange = 1,
		pattern = "Single", projectileType = nil,
		nativePassiveId = "PiercingEdge", nativePassiveBp = 120, totalBp = 996,
	},
	["WPN-WHIP"] = {
		numericId = 8, name = "Whip", category = "Weapon",
		damage = 52, wt = 80, rtDelay = 45, defense = 0,
		handClass = "1H", minRange = 1, maxRange = 3,
		pattern = "Single", projectileType = nil,
		nativePassiveId = nil, nativePassiveBp = 0, totalBp = 998,
	},
	["WPN-CLUB"] = {
		numericId = 9, name = "Club", category = "Weapon",
		damage = 37, wt = 70, rtDelay = 64, defense = 19,
		handClass = "1H", minRange = 1, maxRange = 1,
		pattern = "Single", projectileType = nil,
		nativePassiveId = "Knockback", nativePassiveBp = 150, totalBp = 997,
	},
	["WPN-SWORDBREAKER"] = {
		numericId = 10, name = "Sword Breaker", category = "Weapon",
		damage = 41, wt = 25, rtDelay = 53, defense = 44,
		handClass = "1H", minRange = 1, maxRange = 1,
		pattern = "Single", projectileType = nil,
		nativePassiveId = nil, nativePassiveBp = 0, totalBp = 993,
	},
	-- === 2H RANGED ===
	["WPN-CROSSBOW"] = {
		numericId = 11, name = "Crossbow", category = "Weapon",
		damage = 34, wt = 20, rtDelay = 64, defense = 0,
		handClass = "2H", minRange = 2, maxRange = 4,
		pattern = "Single", projectileType = "Direct",
		nativePassiveId = "ArmorPierce", nativePassiveBp = 130, totalBp = 995,
	},
	["WPN-STAFF"] = {
		numericId = 12, name = "Staff", category = "Weapon",
		damage = 58, wt = 60, rtDelay = 40, defense = 0,
		handClass = "2H", minRange = 2, maxRange = 4,
		pattern = "Single", projectileType = "Channeled",
		nativePassiveId = "ArcaneReach", nativePassiveBp = 120, totalBp = 1003,
	},
	["WPN-GREATBOW"] = {
		numericId = 13, name = "Great Bow", category = "Weapon",
		damage = 63, wt = 115, rtDelay = 71, defense = -5,
		handClass = "2H", minRange = 2, maxRange = 4,
		pattern = "Single", projectileType = "Arc",
		nativePassiveId = "HighGround", nativePassiveBp = 100, totalBp = 1001,
	},
	["WPN-LONGBOW"] = {
		numericId = 14, name = "Longbow", category = "Weapon",
		damage = 50, wt = 130, rtDelay = 20, defense = -5,
		handClass = "2H", minRange = 2, maxRange = 5,
		pattern = "Single", projectileType = "Arc",
		nativePassiveId = "Range+1", nativePassiveBp = 190, totalBp = 1000,
	},
	["WPN-BAZOOKA"] = {
		numericId = 15, name = "Bazooka", category = "Weapon",
		damage = 43, wt = 215, rtDelay = 20, defense = -5,
		handClass = "2H", minRange = 3, maxRange = 5,
		pattern = "ImpactSplash", projectileType = "Arc",
		nativePassiveId = nil, nativePassiveBp = 0, totalBp = 1002,
	},
	-- === 1H RANGED ===
	["WPN-PISTOL"] = {
		numericId = 16, name = "Pistol", category = "Weapon",
		damage = 20, wt = 70, rtDelay = 58, defense = 0,
		handClass = "1H", minRange = 2, maxRange = 4,
		pattern = "Single", projectileType = "Direct",
		nativePassiveId = nil, nativePassiveBp = 0, totalBp = 991,
	},
	["WPN-WAND"] = {
		numericId = 17, name = "Wand", category = "Weapon",
		damage = 25, wt = 50, rtDelay = 45, defense = 0,
		handClass = "1H", minRange = 2, maxRange = 3,
		pattern = "Single", projectileType = "Channeled",
		nativePassiveId = "ArcaneFlow", nativePassiveBp = 80, totalBp = 990,
	},
	["WPN-BLOWGUN"] = {
		numericId = 18, name = "Blowgun", category = "Weapon",
		damage = 15, wt = 60, rtDelay = 0, defense = 2,
		handClass = "1H", minRange = 2, maxRange = 4,
		pattern = "Single", projectileType = "Direct",
		nativePassiveId = "Venomous", nativePassiveBp = 200, totalBp = 1000,
	},
	-- === NEW 1H MELEE ===
	["WPN-RAPIER"] = {
		numericId = 19, name = "Rapier", category = "Weapon",
		damage = 66, wt = 33, rtDelay = 25, defense = 0,
		handClass = "1H", minRange = 1, maxRange = 1,
		pattern = "Single", projectileType = nil,
		nativePassiveId = "PrecisionStrike", nativePassiveBp = 130, totalBp = 1007,
	},
	["WPN-SICKLE"] = {
		numericId = 20, name = "Sickle", category = "Weapon",
		damage = 59, wt = 64, rtDelay = 53, defense = 0,
		handClass = "1H", minRange = 1, maxRange = 1,
		pattern = "Single", projectileType = nil,
		nativePassiveId = "Drain", nativePassiveBp = 120, totalBp = 1008,
	},
	["WPN-TORCH"] = {
		numericId = 21, name = "Torch", category = "Weapon",
		damage = 38, wt = 35, rtDelay = 54, defense = 9,
		handClass = "1H", minRange = 1, maxRange = 1,
		pattern = "Single", projectileType = nil,
		nativePassiveId = "Ignite", nativePassiveBp = 150, totalBp = 992,
	},
	["WPN-FAN"] = {
		numericId = 22, name = "Fan", category = "Weapon",
		damage = 57, wt = 75, rtDelay = 15, defense = -5,
		handClass = "1H", minRange = 1, maxRange = 1,
		pattern = "Adjacent", projectileType = nil,
		nativePassiveId = nil, nativePassiveBp = 0, totalBp = 1007,
	},
	["WPN-FLAIL"] = {
		numericId = 23, name = "Flail", category = "Weapon",
		damage = 59, wt = 61, rtDelay = 49, defense = -3,
		handClass = "1H", minRange = 1, maxRange = 1,
		pattern = "Single", projectileType = nil,
		nativePassiveId = "Bypass", nativePassiveBp = 140, totalBp = 1007,
	},
	["WPN-HATCHET"] = {
		numericId = 24, name = "Hatchet", category = "Weapon",
		damage = 64, wt = 35, rtDelay = 28, defense = 4,
		handClass = "1H", minRange = 1, maxRange = 1,
		pattern = "Single", projectileType = nil,
		nativePassiveId = "Executioner", nativePassiveBp = 110, totalBp = 993,
	},
	-- === NEW 1H RANGED ===
	["WPN-NEEDLE"] = {
		numericId = 25, name = "Needle", category = "Weapon",
		damage = 29, wt = 64, rtDelay = 54, defense = -3,
		handClass = "1H", minRange = 2, maxRange = 3,
		pattern = "Single", projectileType = "Direct",
		nativePassiveId = "TrueStrike", nativePassiveBp = 150, totalBp = 1008,
	},
	["WPN-BOOMERANG"] = {
		numericId = 26, name = "Boomerang", category = "Weapon",
		damage = 39, wt = 74, rtDelay = 42, defense = -3,
		handClass = "1H", minRange = 2, maxRange = 3,
		pattern = "Single", projectileType = "Arc",
		nativePassiveId = "Tricky", nativePassiveBp = 130, totalBp = 1008,
	},
	["WPN-THROWINGKNIFE"] = {
		numericId = 27, name = "Throwing Knife", category = "Weapon",
		damage = 47, wt = 40, rtDelay = 25, defense = -3,
		handClass = "1H", minRange = 2, maxRange = 3,
		pattern = "Single", projectileType = "Direct",
		nativePassiveId = "Backstab", nativePassiveBp = 120, totalBp = 1007,
	},
	["WPN-BELL"] = {
		numericId = 28, name = "Bell", category = "Weapon",
		damage = 5, wt = 30, rtDelay = 15, defense = 0,
		handClass = "1H", minRange = 2, maxRange = 3,
		pattern = "Single", projectileType = "Channeled",
		nativePassiveId = "Lullaby", nativePassiveBp = 250, totalBp = 993,
	},
	-- === NEW 2H MELEE ===
	["WPN-SCYTHE"] = {
		numericId = 29, name = "Scythe", category = "Weapon",
		damage = 64, wt = 177, rtDelay = 15, defense = -5,
		handClass = "2H", minRange = 1, maxRange = 1,
		pattern = "Cleave", projectileType = nil,
		nativePassiveId = "Reap", nativePassiveBp = 100, totalBp = 1008,
	},
	["WPN-LANCE"] = {
		numericId = 30, name = "Lance", category = "Weapon",
		damage = 91, wt = 100, rtDelay = 29, defense = 2,
		handClass = "2H", minRange = 1, maxRange = 1,
		pattern = "Single", projectileType = nil,
		nativePassiveId = "Charge", nativePassiveBp = 130, totalBp = 992,
	},
	["WPN-FLAMEBERGE"] = {
		numericId = 31, name = "Flameberge", category = "Weapon",
		damage = 87, wt = 100, rtDelay = 59, defense = 5,
		handClass = "2H", minRange = 1, maxRange = 1,
		pattern = "Single", projectileType = nil,
		nativePassiveId = "Lacerate", nativePassiveBp = 140, totalBp = 990,
	},
	["WPN-GREATSHIELD"] = {
		numericId = 32, name = "Greatshield", category = "Weapon",
		damage = 59, wt = 60, rtDelay = 79, defense = 54,
		handClass = "2H", minRange = 1, maxRange = 1,
		pattern = "Single", projectileType = nil,
		nativePassiveId = "Bulwark", nativePassiveBp = 150, totalBp = 1000,
	},
	["WPN-CHAINS"] = {
		numericId = 33, name = "Chains", category = "Weapon",
		damage = 50, wt = 50, rtDelay = 89, defense = 24,
		handClass = "2H", minRange = 1, maxRange = 2,
		pattern = "Single", projectileType = nil,
		nativePassiveId = "Pull", nativePassiveBp = 150, totalBp = 1000,
	},
	-- === NEW 2H RANGED ===
	["WPN-MORTAR"] = {
		numericId = 34, name = "Mortar", category = "Weapon",
		damage = 59, wt = 161, rtDelay = 15, defense = -8,
		handClass = "2H", minRange = 4, maxRange = 5,
		pattern = "ImpactSplash", projectileType = "Arc",
		nativePassiveId = nil, nativePassiveBp = 0, totalBp = 1010,
	},
	["WPN-BALLISTA"] = {
		numericId = 35, name = "Ballista", category = "Weapon",
		damage = 58, wt = 153, rtDelay = 15, defense = -8,
		handClass = "2H", minRange = 2, maxRange = 4,
		pattern = "Line2", projectileType = "Direct",
		nativePassiveId = nil, nativePassiveBp = 0, totalBp = 1010,
	},
	["WPN-JAVELIN"] = {
		numericId = 36, name = "Javelin", category = "Weapon",
		damage = 64, wt = 93, rtDelay = 54, defense = -5,
		handClass = "2H", minRange = 2, maxRange = 3,
		pattern = "Adjacent", projectileType = "Arc",
		nativePassiveId = nil, nativePassiveBp = 0, totalBp = 1007,
	},
	["WPN-FROSTROD"] = {
		numericId = 37, name = "Frost Rod", category = "Weapon",
		damage = 34, wt = 50, rtDelay = 54, defense = 1,
		handClass = "2H", minRange = 2, maxRange = 4,
		pattern = "Single", projectileType = "Channeled",
		nativePassiveId = "Freeze", nativePassiveBp = 180, totalBp = 992,
	},
	["WPN-WARHORN"] = {
		numericId = 38, name = "War Horn", category = "Weapon",
		damage = 5, wt = 68, rtDelay = 94, defense = 0,
		handClass = "2H", minRange = 1, maxRange = 2,
		pattern = "ImpactSplash", projectileType = "Channeled",
		nativePassiveId = nil, nativePassiveBp = 0, totalBp = 1011,
	},
	-- === OFF-HAND EQUIPMENT ===
	["OFF-SHIELD"] = {
		numericId = 50, name = "Shield", category = "OffHand",
		damage = 0, wt = 20, rtDelay = 0, defense = 57,
		handClass = "OffHand", minRange = 0, maxRange = 0,
		pattern = nil, projectileType = nil,
		nativePassiveId = "GuardBonus", nativePassiveBp = 120, totalBp = 348,
	},
	["OFF-ORB"] = {
		numericId = 51, name = "Orb", category = "OffHand",
		damage = 50, wt = 20, rtDelay = 0, defense = 0,
		handClass = "OffHand", minRange = 0, maxRange = 0,
		pattern = nil, projectileType = nil,
		nativePassiveId = "SkillPotency", nativePassiveBp = 100, totalBp = 350,
	},
	["OFF-BUCKLER"] = {
		numericId = 52, name = "Buckler", category = "OffHand",
		damage = 0, wt = 20, rtDelay = 10, defense = 55,
		handClass = "OffHand", minRange = 0, maxRange = 0,
		pattern = nil, projectileType = nil,
		nativePassiveId = "Deflect", nativePassiveBp = 130, totalBp = 350,
	},
	["OFF-TOME"] = {
		numericId = 53, name = "Tome", category = "OffHand",
		damage = 23, wt = 20, rtDelay = 0, defense = 28,
		handClass = "OffHand", minRange = 0, maxRange = 0,
		pattern = nil, projectileType = nil,
		nativePassiveId = "Lore", nativePassiveBp = 120, totalBp = 347,
	},
	["OFF-QUIVER"] = {
		numericId = 54, name = "Quiver", category = "OffHand",
		damage = 40, wt = 20, rtDelay = 0, defense = 0,
		handClass = "OffHand", minRange = 0, maxRange = 0,
		pattern = nil, projectileType = nil,
		nativePassiveId = "QuickDraw", nativePassiveBp = 300, totalBp = 350,
	},
	["OFF-PARRYINGDAGGER"] = {
		numericId = 55, name = "Parrying Dagger", category = "OffHand",
		damage = 33, wt = 20, rtDelay = 0, defense = 21,
		handClass = "OffHand", minRange = 0, maxRange = 0,
		pattern = nil, projectileType = nil,
		nativePassiveId = "Evasion", nativePassiveBp = 100, totalBp = 349,
	},
	["OFF-CRYSTAL"] = {
		numericId = 56, name = "Crystal", category = "OffHand",
		damage = 46, wt = 20, rtDelay = 0, defense = 0,
		handClass = "OffHand", minRange = 0, maxRange = 0,
		pattern = nil, projectileType = nil,
		nativePassiveId = "Attunement", nativePassiveBp = 120, totalBp = 350,
	},
}

--------------------------------------------------
-- LOOKUP HELPERS
--------------------------------------------------

-- Reverse map: numericId -> archetypeId
WeaponData._byNumericId = {}
for archetypeId, def in pairs(WeaponData.Archetypes) do
	WeaponData._byNumericId[def.numericId] = archetypeId
end

function WeaponData.GetByArchetypeId(archetypeId)
	return WeaponData.Archetypes[archetypeId]
end

function WeaponData.GetByNumericId(numericId)
	local archetypeId = WeaponData._byNumericId[numericId]
	if archetypeId then
		return WeaponData.Archetypes[archetypeId], archetypeId
	end
	return nil, nil
end

function WeaponData.GetScaledProfile(archetypeId, itemLevel)
	local def = WeaponData.Archetypes[archetypeId]
	if not def then return nil end
	return {
		damage  = WeaponData.ScaleProperty(def.damage, itemLevel),
		wt      = WeaponData.ScaleProperty(def.wt, itemLevel),
		rtDelay = WeaponData.ScaleProperty(def.rtDelay, itemLevel),
		defense = WeaponData.ScaleProperty(def.defense, itemLevel),
		-- Structural (not scaled)
		handClass      = def.handClass,
		minRange       = def.minRange,
		maxRange       = def.maxRange,
		pattern        = def.pattern,
		projectileType = def.projectileType,
		nativePassiveId = def.nativePassiveId,
	}
end

function WeaponData.IsWeapon(archetypeId)
	local def = WeaponData.Archetypes[archetypeId]
	return def and def.category == "Weapon"
end

function WeaponData.IsOffHand(archetypeId)
	local def = WeaponData.Archetypes[archetypeId]
	return def and def.category == "OffHand"
end

return WeaponData
