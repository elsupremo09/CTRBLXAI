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
		numericId = 1, name = "Greatsword",
		flavor = "Compensating for something? Good. Compensate harder.", category = "Weapon",
		icon = "rbxassetid://122604995355077",
		damage = 65, wt = 165, rtDelay = 28, defense = 10,
		handClass = "2H", minRange = 1, maxRange = 1,
		pattern = "Cleave", projectileType = nil,
		nativePassiveId = nil, nativePassiveBp = 0, totalBp = 1000,
	},
	["WPN-CLAWS"] = {
		numericId = 2, name = "Claws",
		flavor = "For when you want a hug to leave a lasting impression.", category = "Weapon",
		icon = "rbxassetid://139537105067108",
		damage = 45, wt = 25, rtDelay = 110, defense = -5,
		handClass = "2H", minRange = 1, maxRange = 1,
		pattern = "Single", projectileType = nil,
		nativePassiveId = "Stagger", nativePassiveBp = 100, totalBp = 988,
	},
	["WPN-WARAXE"] = {
		numericId = 3, name = "War Axe",
		flavor = "Subtlety died the day this was forged. No one mourned.", category = "Weapon",
		icon = "rbxassetid://91631095061220",
		damage = 97, wt = 107, rtDelay = 20, defense = -20,
		handClass = "2H", minRange = 1, maxRange = 1,
		pattern = "Single", projectileType = nil,
		nativePassiveId = "Brutal", nativePassiveBp = 100, totalBp = 1000,
	},
	["WPN-SPEAR"] = {
		numericId = 4, name = "Spear",
		flavor = "The original 'I'd rather not be near you' weapon.", category = "Weapon",
		icon = "rbxassetid://109619472503823",
		damage = 42, wt = 90, rtDelay = 45, defense = 21,
		handClass = "2H", minRange = 1, maxRange = 2,
		pattern = "Line2", projectileType = nil,
		nativePassiveId = "Fortify", nativePassiveBp = 120, totalBp = 1011,
	},
	["WPN-HAMMER"] = {
		numericId = 5, name = "Hammer",
		flavor = "Diplomacy, but louder.", category = "Weapon",
		icon = "rbxassetid://118677292434899",
		damage = 80, wt = 130, rtDelay = 110, defense = 5,
		handClass = "2H", minRange = 1, maxRange = 1,
		pattern = "Single", projectileType = nil,
		nativePassiveId = "Knockback", nativePassiveBp = 150, totalBp = 1004,
	},
	-- === 1H MELEE ===
	["WPN-SWORD"] = {
		numericId = 6, name = "Sword",
		flavor = "Standard issue. Standard dreams. Standard funeral.", category = "Weapon",
		icon = "rbxassetid://83622596767928",
		damage = 67, wt = 60, rtDelay = 60, defense = 5,
		handClass = "1H", minRange = 1, maxRange = 1,
		pattern = "Single", projectileType = nil,
		nativePassiveId = nil, nativePassiveBp = 0, totalBp = 1000,
	},
	["WPN-DAGGER"] = {
		numericId = 7, name = "Dagger",
		flavor = "Small, quiet, and full of bad intentions.", category = "Weapon",
		icon = "rbxassetid://76551934687501",
		damage = 60, wt = 10, rtDelay = 20, defense = 6,
		handClass = "1H", minRange = 1, maxRange = 1,
		pattern = "Single", projectileType = nil,
		nativePassiveId = "PiercingEdge", nativePassiveBp = 120, totalBp = 996,
	},
	["WPN-WHIP"] = {
		numericId = 8, name = "Whip",
		flavor = "Three tiles of questionable life choices.", category = "Weapon",
		icon = "rbxassetid://109633862483295",
		damage = 52, wt = 80, rtDelay = 45, defense = 0,
		handClass = "1H", minRange = 1, maxRange = 3,
		pattern = "Single", projectileType = nil,
		nativePassiveId = nil, nativePassiveBp = 0, totalBp = 998,
	},
	["WPN-CLUB"] = {
		numericId = 9, name = "Club",
		flavor = "It's a stick. Hit things with it. You'll be fine.", category = "Weapon",
		icon = "rbxassetid://126512797489617",
		damage = 37, wt = 70, rtDelay = 64, defense = 19,
		handClass = "1H", minRange = 1, maxRange = 1,
		pattern = "Single", projectileType = nil,
		nativePassiveId = "Knockback", nativePassiveBp = 150, totalBp = 997,
	},
	["WPN-SWORDBREAKER"] = {
		numericId = 10, name = "Sword Breaker",
		flavor = "Made to ruin someone's favorite sword. And their day.", category = "Weapon",
		icon = "rbxassetid://78246587290266",
		damage = 41, wt = 25, rtDelay = 53, defense = 44,
		handClass = "1H", minRange = 1, maxRange = 1,
		pattern = "Single", projectileType = nil,
		nativePassiveId = nil, nativePassiveBp = 0, totalBp = 993,
	},
	-- === 2H RANGED ===
	["WPN-CROSSBOW"] = {
		numericId = 11, name = "Crossbow",
		flavor = "Point-and-click adventure through someone's chestplate.", category = "Weapon",
		icon = "rbxassetid://121148894517091",
		damage = 34, wt = 20, rtDelay = 64, defense = 0,
		handClass = "2H", minRange = 2, maxRange = 4,
		pattern = "Single", projectileType = "Direct",
		nativePassiveId = "ArmorPierce", nativePassiveBp = 130, totalBp = 995,
	},
	["WPN-STAFF"] = {
		numericId = 12, name = "Staff",
		flavor = "A scholar's weapon. Scholars are terrifying.", category = "Weapon",
		icon = "rbxassetid://118293925403009",
		damage = 58, wt = 60, rtDelay = 40, defense = 0,
		handClass = "2H", minRange = 2, maxRange = 4,
		pattern = "Single", projectileType = "Channeled",
		nativePassiveId = "ArcaneReach", nativePassiveBp = 120, totalBp = 1003,
	},
	["WPN-GREATBOW"] = {
		numericId = 13, name = "Great Bow",
		flavor = "Height advantage sold separately. Worth every tile.", category = "Weapon",
		icon = "rbxassetid://108682570205799",
		damage = 63, wt = 115, rtDelay = 71, defense = -5,
		handClass = "2H", minRange = 2, maxRange = 4,
		pattern = "Single", projectileType = "Arc",
		nativePassiveId = "HighGround", nativePassiveBp = 100, totalBp = 1001,
	},
	["WPN-LONGBOW"] = {
		numericId = 14, name = "Longbow",
		flavor = "One more tile of range. One more tile of cowardice.", category = "Weapon",
		icon = "rbxassetid://115039672236376",
		damage = 50, wt = 130, rtDelay = 20, defense = -5,
		handClass = "2H", minRange = 2, maxRange = 5,
		pattern = "Single", projectileType = "Arc",
		nativePassiveId = "Range+1", nativePassiveBp = 190, totalBp = 1000,
	},
	["WPN-BAZOOKA"] = {
		numericId = 15, name = "Bazooka",
		flavor = "Historically inaccurate? Yes. Fun? Also yes.", category = "Weapon",
		icon = "rbxassetid://127227509368608",
		damage = 43, wt = 215, rtDelay = 20, defense = -5,
		handClass = "2H", minRange = 3, maxRange = 5,
		pattern = "ImpactSplash", projectileType = "Arc",
		nativePassiveId = nil, nativePassiveBp = 0, totalBp = 1002,
	},
	-- === 1H RANGED ===
	["WPN-PISTOL"] = {
		numericId = 16, name = "Pistol",
		flavor = "Point. Click. Medieval tech support.", category = "Weapon",
		icon = "rbxassetid://111287192347105",
		damage = 20, wt = 70, rtDelay = 58, defense = 0,
		handClass = "1H", minRange = 2, maxRange = 4,
		pattern = "Single", projectileType = "Direct",
		nativePassiveId = nil, nativePassiveBp = 0, totalBp = 991,
	},
	["WPN-WAND"] = {
		numericId = 17, name = "Wand",
		flavor = "It's a stick that hates you slightly less than a club.", category = "Weapon",
		icon = "rbxassetid://131226888529449",
		damage = 25, wt = 50, rtDelay = 45, defense = 0,
		handClass = "1H", minRange = 2, maxRange = 3,
		pattern = "Single", projectileType = "Channeled",
		nativePassiveId = "ArcaneFlow", nativePassiveBp = 80, totalBp = 990,
	},
	["WPN-BLOWGUN"] = {
		numericId = 18, name = "Blowgun",
		flavor = "One puff and your weekend plans change dramatically.", category = "Weapon",
		icon = "rbxassetid://76407740167748",
		damage = 15, wt = 60, rtDelay = 0, defense = 2,
		handClass = "1H", minRange = 2, maxRange = 4,
		pattern = "Single", projectileType = "Direct",
		nativePassiveId = "Venomous", nativePassiveBp = 200, totalBp = 1000,
	},
	-- === NEW 1H MELEE ===
	["WPN-RAPIER"] = {
		numericId = 19, name = "Rapier",
		flavor = "En garde! ...They don't know what that means here.", category = "Weapon",
		icon = "rbxassetid://79967882502489",
		damage = 66, wt = 33, rtDelay = 25, defense = 0,
		handClass = "1H", minRange = 1, maxRange = 1,
		pattern = "Single", projectileType = nil,
		nativePassiveId = "PrecisionStrike", nativePassiveBp = 130, totalBp = 1007,
	},
	["WPN-SICKLE"] = {
		numericId = 20, name = "Sickle",
		flavor = "Harvest wheat. Harvest HP. Same motion, really.", category = "Weapon",
		icon = "rbxassetid://77990199135866",
		damage = 59, wt = 64, rtDelay = 53, defense = 0,
		handClass = "1H", minRange = 1, maxRange = 1,
		pattern = "Single", projectileType = nil,
		nativePassiveId = "Drain", nativePassiveBp = 120, totalBp = 1008,
	},
	["WPN-TORCH"] = {
		numericId = 21, name = "Torch",
		flavor = "The solution to every problem is fire. Always fire.", category = "Weapon",
		icon = "rbxassetid://109405975213091",
		damage = 38, wt = 35, rtDelay = 54, defense = 9,
		handClass = "1H", minRange = 1, maxRange = 1,
		pattern = "Single", projectileType = nil,
		nativePassiveId = "Ignite", nativePassiveBp = 150, totalBp = 992,
	},
	["WPN-FAN"] = {
		numericId = 22, name = "Fan",
		flavor = "Elegant. Deadly. Absolutely useless in actual wind.", category = "Weapon",
		icon = "rbxassetid://113759500482323",
		damage = 57, wt = 75, rtDelay = 15, defense = -5,
		handClass = "1H", minRange = 1, maxRange = 1,
		pattern = "Adjacent", projectileType = nil,
		nativePassiveId = nil, nativePassiveBp = 0, totalBp = 1007,
	},
	["WPN-FLAIL"] = {
		numericId = 23, name = "Flail",
		flavor = "Even the wielder doesn't know where it's going.", category = "Weapon",
		icon = "rbxassetid://70750705494124",
		damage = 59, wt = 61, rtDelay = 49, defense = -3,
		handClass = "1H", minRange = 1, maxRange = 1,
		pattern = "Single", projectileType = nil,
		nativePassiveId = "Bypass", nativePassiveBp = 140, totalBp = 1007,
	},
	["WPN-HATCHET"] = {
		numericId = 24, name = "Hatchet",
		flavor = "For finishing what the first 80% of damage started.", category = "Weapon",
		icon = "rbxassetid://114121191862998",
		damage = 64, wt = 35, rtDelay = 28, defense = 4,
		handClass = "1H", minRange = 1, maxRange = 1,
		pattern = "Single", projectileType = nil,
		nativePassiveId = "Executioner", nativePassiveBp = 110, totalBp = 993,
	},
	-- === NEW 1H RANGED ===
	["WPN-NEEDLE"] = {
		numericId = 25, name = "Needle",
		flavor = "Armor? What armor? I don't see any armor.", category = "Weapon",
		icon = "rbxassetid://109267348834151",
		damage = 29, wt = 64, rtDelay = 54, defense = -3,
		handClass = "1H", minRange = 2, maxRange = 3,
		pattern = "Single", projectileType = "Direct",
		nativePassiveId = "TrueStrike", nativePassiveBp = 150, totalBp = 1008,
	},
	["WPN-BOOMERANG"] = {
		numericId = 26, name = "Boomerang",
		flavor = "Comes back every time. Like regret.", category = "Weapon",
		icon = "rbxassetid://74937236701523",
		damage = 39, wt = 74, rtDelay = 42, defense = -3,
		handClass = "1H", minRange = 2, maxRange = 3,
		pattern = "Single", projectileType = "Arc",
		nativePassiveId = "Tricky", nativePassiveBp = 130, totalBp = 1008,
	},
	["WPN-THROWINGKNIFE"] = {
		numericId = 27, name = "Throwing Knife",
		flavor = "Gone in one frame. Just like your HP.", category = "Weapon",
		icon = "rbxassetid://81642861704722",
		damage = 47, wt = 40, rtDelay = 25, defense = -3,
		handClass = "1H", minRange = 2, maxRange = 3,
		pattern = "Single", projectileType = "Direct",
		nativePassiveId = "Backstab", nativePassiveBp = 120, totalBp = 1007,
	},
	["WPN-BELL"] = {
		numericId = 28, name = "Bell",
		flavor = "Ding. Ding. Why are your eyes closing?", category = "Weapon",
		icon = "rbxassetid://101029559621843",
		damage = 5, wt = 30, rtDelay = 15, defense = 0,
		handClass = "1H", minRange = 2, maxRange = 3,
		pattern = "Single", projectileType = "Channeled",
		nativePassiveId = "Lullaby", nativePassiveBp = 250, totalBp = 993,
	},
	-- === NEW 2H MELEE ===
	["WPN-SCYTHE"] = {
		numericId = 29, name = "Scythe",
		flavor = "The edgelord starter kit. Comes with free backstory.", category = "Weapon",
		icon = "rbxassetid://112522569710001",
		damage = 64, wt = 177, rtDelay = 15, defense = -5,
		handClass = "2H", minRange = 1, maxRange = 1,
		pattern = "Cleave", projectileType = nil,
		nativePassiveId = "Reap", nativePassiveBp = 100, totalBp = 1008,
	},
	["WPN-LANCE"] = {
		numericId = 30, name = "Lance",
		flavor = "Run at them really fast. That's the whole plan.", category = "Weapon",
		icon = "rbxassetid://78236041653469",
		damage = 91, wt = 100, rtDelay = 29, defense = 2,
		handClass = "2H", minRange = 1, maxRange = 1,
		pattern = "Single", projectileType = nil,
		nativePassiveId = "Charge", nativePassiveBp = 130, totalBp = 992,
	},
	["WPN-FLAMEBERGE"] = {
		numericId = 31, name = "Flameberge",
		flavor = "Wavy blade. Wavy damage. Wavy ethics.", category = "Weapon",
		icon = "rbxassetid://85923390469142",
		damage = 87, wt = 100, rtDelay = 59, defense = 5,
		handClass = "2H", minRange = 1, maxRange = 1,
		pattern = "Single", projectileType = nil,
		nativePassiveId = "Lacerate", nativePassiveBp = 140, totalBp = 990,
	},
	["WPN-GREATSHIELD"] = {
		numericId = 32, name = "Greatshield",
		flavor = "Technically a weapon. We checked. Twice.", category = "Weapon",
		icon = "rbxassetid://77361921059074",
		damage = 59, wt = 60, rtDelay = 79, defense = 54,
		handClass = "2H", minRange = 1, maxRange = 1,
		pattern = "Single", projectileType = nil,
		nativePassiveId = "Bulwark", nativePassiveBp = 150, totalBp = 1000,
	},
	["WPN-CHAINS"] = {
		numericId = 33, name = "Chains",
		flavor = "Nothing says 'let's talk' like dragging them closer.", category = "Weapon",
		icon = "rbxassetid://128778016004052",
		damage = 50, wt = 50, rtDelay = 89, defense = 24,
		handClass = "2H", minRange = 1, maxRange = 2,
		pattern = "Single", projectileType = nil,
		nativePassiveId = "Pull", nativePassiveBp = 150, totalBp = 1000,
	},
	-- === NEW 2H RANGED ===
	["WPN-MORTAR"] = {
		numericId = 34, name = "Mortar",
		flavor = "Lob it. Forget it. Hear the screaming later.", category = "Weapon",
		icon = "rbxassetid://90803939512871",
		damage = 59, wt = 161, rtDelay = 15, defense = -8,
		handClass = "2H", minRange = 4, maxRange = 5,
		pattern = "ImpactSplash", projectileType = "Arc",
		nativePassiveId = nil, nativePassiveBp = 0, totalBp = 1010,
	},
	["WPN-BALLISTA"] = {
		numericId = 35, name = "Ballista",
		flavor = "A siege weapon is a valid personal choice.", category = "Weapon",
		icon = "rbxassetid://84334480824304",
		damage = 58, wt = 153, rtDelay = 15, defense = -8,
		handClass = "2H", minRange = 2, maxRange = 4,
		pattern = "Line2", projectileType = "Direct",
		nativePassiveId = nil, nativePassiveBp = 0, totalBp = 1010,
	},
	["WPN-JAVELIN"] = {
		numericId = 36, name = "Javelin",
		flavor = "Throw it. That's it. Don't overthink this.", category = "Weapon",
		icon = "rbxassetid://123876188718944",
		damage = 64, wt = 93, rtDelay = 54, defense = -5,
		handClass = "2H", minRange = 2, maxRange = 3,
		pattern = "Adjacent", projectileType = "Arc",
		nativePassiveId = nil, nativePassiveBp = 0, totalBp = 1007,
	},
	["WPN-FROSTROD"] = {
		numericId = 37, name = "Frost Rod",
		flavor = "Freeze now, apologize never.", category = "Weapon",
		icon = "rbxassetid://104447164199147",
		damage = 34, wt = 50, rtDelay = 54, defense = 1,
		handClass = "2H", minRange = 2, maxRange = 4,
		pattern = "Single", projectileType = "Channeled",
		nativePassiveId = "Freeze", nativePassiveBp = 180, totalBp = 992,
	},
	["WPN-WARHORN"] = {
		numericId = 38, name = "War Horn",
		flavor = "You don't hit them with it. That's the scary part.", category = "Weapon",
		icon = "rbxassetid://128189252119179",
		damage = 5, wt = 68, rtDelay = 94, defense = 0,
		handClass = "2H", minRange = 1, maxRange = 2,
		pattern = "ImpactSplash", projectileType = "Channeled",
		nativePassiveId = nil, nativePassiveBp = 0, totalBp = 1011,
	},
	-- === OFF-HAND EQUIPMENT ===
	["OFF-SHIELD"] = {
		numericId = 50, name = "Shield",
		flavor = "Hide behind it. No one's judging. Much.", category = "OffHand",
		icon = "rbxassetid://130630252450635",
		damage = 0, wt = 20, rtDelay = 0, defense = 57,
		handClass = "OffHand", minRange = 0, maxRange = 0,
		pattern = nil, projectileType = nil,
		nativePassiveId = "GuardBonus", nativePassiveBp = 120, totalBp = 348,
	},
	["OFF-ORB"] = {
		numericId = 51, name = "Orb",
		flavor = "Floaty, glowy, makes your spells hit different.", category = "OffHand",
		icon = "rbxassetid://84835752401831",
		damage = 50, wt = 20, rtDelay = 0, defense = 0,
		handClass = "OffHand", minRange = 0, maxRange = 0,
		pattern = nil, projectileType = nil,
		nativePassiveId = "SkillPotency", nativePassiveBp = 100, totalBp = 350,
	},
	["OFF-BUCKLER"] = {
		numericId = 52, name = "Buckler",
		flavor = "A shield for people who still want to stab things.", category = "OffHand",
		icon = "rbxassetid://91094733433191",
		damage = 0, wt = 20, rtDelay = 10, defense = 55,
		handClass = "OffHand", minRange = 0, maxRange = 0,
		pattern = nil, projectileType = nil,
		nativePassiveId = "Deflect", nativePassiveBp = 130, totalBp = 350,
	},
	["OFF-TOME"] = {
		numericId = 53, name = "Tome",
		flavor = "Knowledge is power. This one has both, literally.", category = "OffHand",
		icon = "rbxassetid://140273978942167",
		damage = 23, wt = 20, rtDelay = 0, defense = 28,
		handClass = "OffHand", minRange = 0, maxRange = 0,
		pattern = nil, projectileType = nil,
		nativePassiveId = "Lore", nativePassiveBp = 120, totalBp = 347,
	},
	["OFF-QUIVER"] = {
		numericId = 54, name = "Quiver",
		flavor = "More arrows than common sense. Perfect ratio.", category = "OffHand",
		icon = "rbxassetid://133565854493583",
		damage = 40, wt = 20, rtDelay = 0, defense = 0,
		handClass = "OffHand", minRange = 0, maxRange = 0,
		pattern = nil, projectileType = nil,
		nativePassiveId = "QuickDraw", nativePassiveBp = 300, totalBp = 350,
	},
	["OFF-PARRYINGDAGGER"] = {
		numericId = 55, name = "Parrying Dagger",
		flavor = "For when 'no' needs to be expressed with steel.", category = "OffHand",
		icon = "rbxassetid://104535230073639",
		damage = 33, wt = 20, rtDelay = 0, defense = 21,
		handClass = "OffHand", minRange = 0, maxRange = 0,
		pattern = nil, projectileType = nil,
		nativePassiveId = "Evasion", nativePassiveBp = 100, totalBp = 349,
	},
	["OFF-CRYSTAL"] = {
		numericId = 56, name = "Crystal",
		flavor = "It hums. You hum back. The bond is weird but real.", category = "OffHand",
		icon = "rbxassetid://120571767307728",
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

--------------------------------------------------
-- NATIVE PASSIVE DESCRIPTIONS (from CTRBLXAI.db)
--------------------------------------------------

local NATIVE_PASSIVE_DESC = {
	["ArcaneFlow"] = "Recover MP = 5 + floor(INT/20) on ready turn.",
	["ArcaneReach"] = "Skills inheriting weapon range gain +1 Maximum Range.",
	["ArmorPierce"] = "Reduce target Defense by 30% before damage.",
	["Attunement"] = "+25% elemental damage dealt.",
	["Backstab"] = "+50% damage when attacking from behind.",
	["Brutal"] = "Weapon Damage x1.20 before STR scaling.",
	["Bulwark"] = "+25% of base Weapon Defense added to Weapon Damage.",
	["Bypass"] = "Ignores target Guard mitigation.",
	["Charge"] = "+6% damage per tile moved this turn.",
	["Deflect"] = "On Guard, reflect 20% of mitigated damage.",
	["Drain"] = "Heal 5% of final damage dealt per hit.",
	["Evasion"] = "+15% final Evasiveness.",
	["Executioner"] = "+30% damage vs targets below 25% HP.",
	["Fortify"] = "On hit, gain +20% of Weapon Defense as flat Defense.",
	["Freeze"] = "Applies Freeze on hit.",
	["GuardBonus"] = "On Guard, +15% damage mitigation.",
	["HighGround"] = "+35% elevation damage bonus when attacking from above.",
	["Ignite"] = "Applies Burn DoT on hit.",
	["Knockback"] = "Push target floor(Force/2) tiles away on hit.",
	["Lacerate"] = "Applies Bleed on hit.",
	["Lore"] = "+30% applied status and buff duration.",
	["Lullaby"] = "Applies Sleep on hit (2 turns, damage wakes).",
	["PiercingEdge"] = "Pending definition.",
	["PrecisionStrike"] = "+15% Hit Quality on Basic Attacks.",
	["Pull"] = "Drag target floor(Force/2) tiles toward attacker.",
	["QuickDraw"] = "After 2 Basic Attacks, next attack costs 0 RT.",
	["Range+1"] = "+1 Maximum Range (Minimum unchanged).",
	["Reap"] = "Heal 5% of total Cleave damage dealt.",
	["SkillPotency"] = "+8% Skill damage dealt.",
	["Stagger"] = "Weapon RT Delay x1.25 on hit.",
	["Tricky"] = "Ignore 40% of target Evasiveness.",
	["TrueStrike"] = "Hit Quality cannot go below 100%.",
	["Venomous"] = "Applies Poison on hit.",
}

function WeaponData.GetPassiveDesc(passiveId)
	return NATIVE_PASSIVE_DESC[passiveId] or ""
end

--------------------------------------------------
-- ELEMENT TAG (derived from native passive)
--------------------------------------------------

local PASSIVE_ELEMENT = {
	Ignite = "Fire", Freeze = "Ice", Venomous = "Poison",
}

function WeaponData.GetElement(archetypeId)
	local def = WeaponData.Archetypes[archetypeId]
	if not def or not def.nativePassiveId then return nil end
	return PASSIVE_ELEMENT[def.nativePassiveId]
end

return WeaponData
