-- MockLoadoutData.lua
-- CTRBLXAI | Slice 7 — Mock data provider for Loadout Screen
-- DEFERRED DEPENDENCY: Real data comes from Slice 4.
-- Every table here is a MOCK placeholder.

local MockLoadoutData = {}

MockLoadoutData.Units = {
	{ id = "unit_hero", name = "Hero", level = 25, raceId = "RACE-HUMAN", raceName = "Human", side = "Player",
	  doctrineId = "DOC-BERSERKER", doctrineName = "Berserker",
	  stats = { STR = 42, INT = 18, DEX = 30, AGI = 28, VIT = 35, LUK = 22 } },
	{ id = "unit_ranger", name = "Ranger", level = 20, raceId = "RACE-ELF", raceName = "Elf", side = "Player",
	  doctrineId = "DOC-RANGER", doctrineName = "Ranger",
	  stats = { STR = 20, INT = 22, DEX = 38, AGI = 34, VIT = 18, LUK = 28 } },
	{ id = "unit_mage", name = "Mage", level = 22, raceId = "RACE-HUMAN", raceName = "Human", side = "Player",
	  doctrineId = "DOC-ARCANIST", doctrineName = "Arcanist",
	  stats = { STR = 12, INT = 44, DEX = 20, AGI = 18, VIT = 16, LUK = 30 } },
}

MockLoadoutData.SelectedUnitIndex = 1

function MockLoadoutData.GetSelectedUnit()
	return MockLoadoutData.Units[MockLoadoutData.SelectedUnitIndex]
end

function MockLoadoutData.NextUnit()
	MockLoadoutData.SelectedUnitIndex = (MockLoadoutData.SelectedUnitIndex % #MockLoadoutData.Units) + 1
	return MockLoadoutData.GetSelectedUnit()
end

function MockLoadoutData.PrevUnit()
	MockLoadoutData.SelectedUnitIndex = ((MockLoadoutData.SelectedUnitIndex - 2) % #MockLoadoutData.Units) + 1
	return MockLoadoutData.GetSelectedUnit()
end

-- Inventory items (shared pool)
MockLoadoutData.Inventory = {
	-- Weapons (MainHand)
	{ id = "w001", name = "Iron Longsword", cat = "MainHand", sub = "1H Sword", hands = "One-Handed", lv = 12, rarity = "Common", icon = "⚔", qty = 1, acqOrder = 1, tags = {"Melee","Slashing","One-Handed","Warrior"}, stats = {Damage=34,Range="1",WeaponWT=31,BasicAttackRT=431,Force=12,Stability=8}, bonusAttr = {STR=6,VIT=3}, passives = {{name="Power Strike",icon="⚔",desc="Unleash a heavy melee blow that increases your Force on the first attack each round."}}, pattern = {type="Single",desc="Single adjacent target"}, flavor = "A soldier's blade, forged in the capital armory." },
	{ id = "w002", name = "Steel Greatsword", cat = "MainHand", sub = "2H Sword", hands = "Two-Handed", lv = 18, rarity = "Uncommon", icon = "⚔", qty = 1, acqOrder = 5, tags = {"Melee","Slashing","Two-Handed","Warrior"}, stats = {Damage=37,Range="1",WeaponWT=16,BasicAttackRT=494,Force=18,Stability=12}, bonusAttr = {STR=8,VIT=5}, passives = {{name="Cleave",icon="⚔",desc="Basic attacks hit adjacent tiles in a sweeping arc."}}, pattern = {type="Cleave",desc="Sweeping arc, hits 3 tiles"}, flavor = "Heavy and true. Each swing carves through armor like parchment." },
	{ id = "w003", name = "Oak Staff", cat = "MainHand", sub = "2H Staff", hands = "Two-Handed", lv = 15, rarity = "Common", icon = "🏑", qty = 1, acqOrder = 3, tags = {"Ranged","Magical","Two-Handed","Mage"}, stats = {Damage=31,Range="2 - 4",WeaponWT=22,BasicAttackRT=432,Force=6,Stability=4}, bonusAttr = {INT=7}, passives = {{name="Arcane Reach",icon="✨",desc="Skills that inherit weapon range gain +1 bonus Maximum Range."}}, pattern = {type="Single",desc="Single target, channeled projectile"}, flavor = "Cut from an ancient oak in the Whispering Forest." },
	{ id = "w004", name = "Flame Rapier", cat = "MainHand", sub = "1H Sword", hands = "One-Handed", lv = 22, rarity = "Rare", icon = "⚔", qty = 1, acqOrder = 18, tags = {"Melee","Piercing","One-Handed","Duelist"}, stats = {Damage=40,Range="1",WeaponWT=15,BasicAttackRT=420,Force=10,Stability=6}, bonusAttr = {DEX=9,AGI=4}, passives = {{name="Precision Strike",icon="🎯",desc="+15% Hit Quality on Basic Attacks."},{name="Flame Touch",icon="🔥",desc="Basic attacks apply Burn for 2 rounds (10% weapon damage per tick)."}}, pattern = {type="Single",desc="Single adjacent target"}, flavor = "A duelist's dream — fast, precise, and wreathed in flame." },
	{ id = "w005", name = "Crossbow", cat = "MainHand", sub = "2H Ranged", hands = "Two-Handed", lv = 20, rarity = "Rare", icon = "🏹", qty = 1, acqOrder = 20, tags = {"Ranged","Piercing","Two-Handed","Ranger"}, stats = {Damage=92,Range="6 - 8",WeaponWT=70,BasicAttackRT=410,Force=12,Stability=8}, bonusAttr = {DEX=9,AGI=4}, passives = {{name="Piercing Shot",icon="🏹",desc="Fire a piercing projectile that passes through the first target and ignores 30% of the target's Stability."},{name="Steady Aim",icon="🎯",desc="When you do not move during a round, increases Accuracy by 15%."},{name="Light Frame",icon="🪶",desc="Reduces Weapon Weight penalty by 10% when your DEX is 30 or higher."}}, pattern = {type="Line",desc="Straight line, pierces first target"}, flavor = "A hunter's crossbow, forged in a border outpost where survival depends on precision and patience." },
	{ id = "w006", name = "Hunter Bow", cat = "MainHand", sub = "2H Ranged", hands = "Two-Handed", lv = 20, rarity = "Uncommon", icon = "🏹", qty = 1, acqOrder = 12, tags = {"Ranged","Piercing","Two-Handed","Ranger"}, stats = {Damage=37,Range="2 - 4",WeaponWT=41,BasicAttackRT=467,Force=10,Stability=6}, bonusAttr = {DEX=7,AGI=3}, passives = {{name="High Ground",icon="⬆",desc="When attacking from higher elevation, increase elevation damage bonus by 35%."}}, pattern = {type="Single",desc="Single target, arcing projectile"}, flavor = "Carved from mountain ash. Favors those who take the high ground." },
	{ id = "w007", name = "Battle Axe", cat = "MainHand", sub = "2H Axe", hands = "Two-Handed", lv = 19, rarity = "Uncommon", icon = "🪓", qty = 1, acqOrder = 15, tags = {"Melee","Slashing","Two-Handed","Warrior"}, stats = {Damage=46,Range="1",WeaponWT=64,BasicAttackRT=476,Force=20,Stability=10}, bonusAttr = {STR=8,VIT=4}, passives = {{name="Knockback",icon="💥",desc="Basic attacks push the target 1 tile away if Force exceeds their Stability."}}, pattern = {type="Single",desc="Single adjacent target"}, flavor = "Built to cleave through shield walls. Subtlety is not its purpose." },
	{ id = "w008", name = "Mage Staff", cat = "MainHand", sub = "2H Staff", hands = "Two-Handed", lv = 16, rarity = "Common", icon = "🏑", qty = 1, acqOrder = 4, tags = {"Ranged","Magical","Two-Handed","Mage"}, stats = {Damage=32,Range="2 - 4",WeaponWT=23,BasicAttackRT=434,Force=6,Stability=4}, bonusAttr = {INT=6,LUK=2}, passives = {{name="Arcane Reach",icon="✨",desc="Skills that inherit weapon range gain +1 bonus Maximum Range."}}, pattern = {type="Single",desc="Single target, channeled projectile"}, flavor = "Standard-issue from the Arcanum. Reliable, if uninspiring." },
	-- Off-Hand
	{ id = "s001", name = "Wooden Buckler", cat = "OffHand", sub = "Shield", hands = "Off-Hand", lv = 10, rarity = "Common", icon = "🛡", qty = 1, acqOrder = 2, tags = {"Off-Hand","Shield","Light"}, stats = {Defense=28,WeaponWT=10,Stability=6}, bonusAttr = {VIT=3}, passives = {{name="Deflect",icon="🛡",desc="On Guard, reflect 20% of mitigated damage back to the attacker."}}, flavor = "Splinters easily, but better than bare skin." },
	{ id = "s002", name = "Steel Shield", cat = "OffHand", sub = "Shield", hands = "Off-Hand", lv = 18, rarity = "Uncommon", icon = "🛡", qty = 1, acqOrder = 11, tags = {"Off-Hand","Shield","Heavy"}, stats = {Defense=42,WeaponWT=18,Stability=10}, bonusAttr = {VIT=5,STR=3}, passives = {{name="Deflect",icon="🛡",desc="On Guard, reflect 20% of mitigated damage back to the attacker."}}, flavor = "Forged in bulk for the frontier garrisons." },
	-- Head
	{ id = "h001", name = "Leather Cap", cat = "Head", sub = "Light", hands = nil, lv = 8, rarity = "Common", icon = "🪖", qty = 1, acqOrder = 6, tags = {"Head","Light","Armor"}, stats = {Defense=6,WeaponWT=4}, bonusAttr = {}, passives = {}, flavor = "Thin leather, but it keeps the rain off." },
	{ id = "h002", name = "Iron Helm", cat = "Head", sub = "Heavy", hands = nil, lv = 16, rarity = "Uncommon", icon = "🪖", qty = 1, acqOrder = 10, tags = {"Head","Heavy","Armor"}, stats = {Defense=14,WeaponWT=12}, bonusAttr = {VIT=3}, passives = {}, flavor = "Dented but sturdy. A veteran's helm." },
	{ id = "h003", name = "Leather Helm", cat = "Head", sub = "Light", hands = nil, lv = 20, rarity = "Uncommon", icon = "🪖", qty = 1, acqOrder = 14, tags = {"Head","Light","Armor"}, stats = {Defense=10,WeaponWT=6}, bonusAttr = {AGI=2}, passives = {}, flavor = "Flexible hide, stitched for scouts and rangers." },
	-- Torso
	{ id = "t001", name = "Chain Mail", cat = "Torso", sub = "Medium", hands = nil, lv = 14, rarity = "Common", icon = "🦺", qty = 1, acqOrder = 7, tags = {"Torso","Medium","Armor"}, stats = {Defense=18,WeaponWT=20}, bonusAttr = {VIT=4}, passives = {}, flavor = "Standard chain links. Stops slashes, not arrows." },
	{ id = "t002", name = "Mithril Plate", cat = "Torso", sub = "Heavy", hands = nil, lv = 24, rarity = "Rare", icon = "🦺", qty = 1, acqOrder = 19, tags = {"Torso","Heavy","Armor"}, stats = {Defense=36,WeaponWT=28}, bonusAttr = {VIT=7,STR=4}, passives = {{name="Fortified",icon="🛡",desc="Reduce incoming critical bonus damage by 15%."}}, flavor = "Light as silk, hard as diamond. The smith's masterpiece." },
	{ id = "t003", name = "Leather Armor", cat = "Torso", sub = "Light", hands = nil, lv = 17, rarity = "Common", icon = "🦺", qty = 1, acqOrder = 9, tags = {"Torso","Light","Armor"}, stats = {Defense=12,WeaponWT=10}, bonusAttr = {AGI=3}, passives = {}, flavor = "Supple tanned hide. Comfortable for long marches." },
	-- Arms
	{ id = "a001", name = "Leather Gloves", cat = "Arms", sub = "Light", hands = nil, lv = 8, rarity = "Common", icon = "🧤", qty = 1, acqOrder = 8, tags = {"Arms","Light","Armor"}, stats = {Defense=4,WeaponWT=3}, bonusAttr = {DEX=2}, passives = {}, flavor = "Thin enough to thread a needle." },
	{ id = "a002", name = "Iron Gauntlets", cat = "Arms", sub = "Heavy", hands = nil, lv = 16, rarity = "Uncommon", icon = "🧤", qty = 1, acqOrder = 13, tags = {"Arms","Heavy","Armor"}, stats = {Defense=10,WeaponWT=10}, bonusAttr = {STR=3,VIT=2}, passives = {}, flavor = "Reinforced knuckles. Punching is inadvisable but possible." },
	-- Legs
	{ id = "l001", name = "Iron Greaves", cat = "Legs", sub = "Heavy", hands = nil, lv = 12, rarity = "Common", icon = "🥾", qty = 1, acqOrder = 16, tags = {"Legs","Heavy","Armor"}, stats = {Defense=8,WeaponWT=8}, bonusAttr = {VIT=2}, passives = {}, flavor = "Clanks with every step. Your enemies hear you coming." },
	{ id = "l002", name = "Boots", cat = "Legs", sub = "Light", hands = nil, lv = 14, rarity = "Common", icon = "🥾", qty = 1, acqOrder = 17, tags = {"Legs","Light","Armor"}, stats = {Defense=5,WeaponWT=4}, bonusAttr = {AGI=3}, passives = {}, flavor = "Soft leather soles. Silent on stone." },
	-- Accessory
	{ id = "ac001", name = "Silver Ring", cat = "Accessory", sub = "Ring", hands = nil, lv = 10, rarity = "Uncommon", icon = "💍", qty = 1, acqOrder = 21, tags = {"Accessory","Ring"}, stats = {}, bonusAttr = {LUK=5}, passives = {}, flavor = "A lucky charm from a market stall." },
	{ id = "ac002", name = "Warrior's Pendant", cat = "Accessory", sub = "Necklace", hands = nil, lv = 18, rarity = "Rare", icon = "💍", qty = 1, acqOrder = 22, tags = {"Accessory","Necklace"}, stats = {}, bonusAttr = {STR=6,VIT=4}, passives = {{name="Battle Fury",icon="🔥",desc="After defeating an enemy, gain +10% Force for the rest of the battle."}}, flavor = "Worn by a captain who never lost a siege." },
	{ id = "ac003", name = "Power Ring", cat = "Accessory", sub = "Ring", hands = nil, lv = 16, rarity = "Uncommon", icon = "💍", qty = 1, acqOrder = 23, tags = {"Accessory","Ring"}, stats = {}, bonusAttr = {STR=5,DEX=3}, passives = {}, flavor = "Warm to the touch. The gem pulses faintly." },
	{ id = "ac004", name = "Wind Charm", cat = "Accessory", sub = "Charm", hands = nil, lv = 15, rarity = "Uncommon", icon = "💎", qty = 1, acqOrder = 24, tags = {"Accessory","Charm"}, stats = {}, bonusAttr = {AGI=6}, passives = {{name="Tailwind",icon="💨",desc="Movement range +1 on the first round of each battle."}}, flavor = "Swirls of trapped breeze inside polished crystal." },
	{ id = "ac005", name = "Bracelet", cat = "Accessory", sub = "Bracelet", hands = nil, lv = 18, rarity = "Common", icon = "💍", qty = 1, acqOrder = 25, tags = {"Accessory","Bracelet"}, stats = {}, bonusAttr = {VIT=3}, passives = {}, flavor = "Plain iron links. Functional." },
	-- Consumables
	{ id = "c001", name = "Health Potion", cat = "Consumable", sub = "Recovery", lv = 1, rarity = "Common", icon = "🧪", qty = 5, acqOrder = 26, effect = "Restore 30% Max HP" },
	{ id = "c002", name = "MP Potion", cat = "Consumable", sub = "Recovery", lv = 1, rarity = "Common", icon = "🧪", qty = 3, acqOrder = 27, effect = "Restore 25% Max MP" },
	{ id = "c003", name = "Antidote", cat = "Consumable", sub = "Recovery", lv = 1, rarity = "Uncommon", icon = "🧪", qty = 2, acqOrder = 28, effect = "Remove Poison and Venom" },
	-- Doctrines
	{ id = "d001", name = "Berserker", cat = "Doctrine", sub = "Melee", lv = 0, rarity = "Rare", icon = "📜", qty = 1, acqOrder = 29 },
	{ id = "d002", name = "Ranger", cat = "Doctrine", sub = "Ranged", lv = 0, rarity = "Rare", icon = "📜", qty = 1, acqOrder = 30 },
	{ id = "d003", name = "Arcanist", cat = "Doctrine", sub = "Magic", lv = 0, rarity = "Rare", icon = "📜", qty = 1, acqOrder = 31 },
	{ id = "d004", name = "Hunter's Focus", cat = "Doctrine", sub = "Hybrid", lv = 0, rarity = "Epic", icon = "📜", qty = 1, acqOrder = 32 },
}

-- Equipped per unit (unitId -> slot -> itemId)
MockLoadoutData.Equipped = {
	unit_hero = {
		MainHand = "w001", OffHand = "s001", Head = "h001", Torso = "t001",
		Arms = "a001", Legs = "l001", Accessory = "ac001", Doctrine = "d001",
		Cons1 = "c001", Cons2 = nil, Cons3 = nil, Cons4 = nil, Cons5 = nil, Cons6 = nil,
	},
	unit_ranger = {
		MainHand = "w006", OffHand = nil, Head = "h003", Torso = "t003",
		Arms = "a001", Legs = "l002", Accessory = "ac003", Doctrine = "d002",
		Cons1 = "c001", Cons2 = "c002", Cons3 = "c003", Cons4 = nil, Cons5 = nil, Cons6 = nil,
	},
	unit_mage = {
		MainHand = "w003", OffHand = nil, Head = "h002", Torso = "t001",
		Arms = "a002", Legs = "l001", Accessory = "ac004", Doctrine = "d003",
		Cons1 = "c002", Cons2 = nil, Cons3 = nil, Cons4 = nil, Cons5 = nil, Cons6 = nil,
	},
}

MockLoadoutData.ConsSlotLocked = { Cons1=false, Cons2=false, Cons3=false, Cons4=true, Cons5=true, Cons6=true }

function MockLoadoutData.GetItem(id)
	for _, item in ipairs(MockLoadoutData.Inventory) do
		if item.id == id then return item end
	end
	return nil
end

function MockLoadoutData.GetEquipped(unitId, slot)
	local eq = MockLoadoutData.Equipped[unitId]
	if eq and eq[slot] then return MockLoadoutData.GetItem(eq[slot]) end
	return nil
end

function MockLoadoutData.IsEquipped(itemId, unitId)
	local eq = MockLoadoutData.Equipped[unitId]
	if not eq then return false end
	for _, eqId in pairs(eq) do
		if eqId == itemId then return true end
	end
	return false
end

function MockLoadoutData.GetFilteredItems(category)
	if not category or category == "All" then return MockLoadoutData.Inventory end
	local r = {}
	for _, item in ipairs(MockLoadoutData.Inventory) do
		if item.cat == category then table.insert(r, item) end
	end
	return r
end

function MockLoadoutData.MockEquip(unitId, slot, itemId)
	local eq = MockLoadoutData.Equipped[unitId]
	if not eq then return end
	eq[slot] = itemId
	print("[Mock] Equipped", itemId, "to", slot, "on", unitId)
end

return MockLoadoutData
