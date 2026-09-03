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
	{ id = "w001", name = "Iron Longsword", cat = "MainHand", sub = "1H Sword", hands = "One-Handed", lv = 12, rarity = "Common", icon = "⚔", qty = 1, acqOrder = 1, isWeapon = true, tags = {"Melee","Slashing","One-Handed","Warrior"}, baseStats = {Attack=34,Range="1-1",Defense=3,WT=31,RTDelay=31}, passives = {{name="Power Strike",icon="⚔",desc="Unleash a heavy melee blow that increases your Force on the first attack each round."}}, bonusStats = {STR=6,VIT=3}, bonusPassives = {}, flavor = "A soldier's blade, forged in the capital armory." },
	{ id = "w002", name = "Steel Greatsword", cat = "MainHand", sub = "2H Sword", hands = "Two-Handed", lv = 18, rarity = "Uncommon", icon = "⚔", qty = 1, acqOrder = 5, isWeapon = true, tags = {"Melee","Slashing","Two-Handed","Warrior"}, baseStats = {Attack=37,Range="1-1",Defense=6,WT=16,RTDelay=94}, passives = {{name="Cleave",icon="⚔",desc="Basic attacks hit adjacent tiles in a sweeping arc."}}, bonusStats = {STR=8,VIT=5}, bonusPassives = {}, flavor = "Heavy and true. Each swing carves through armor like parchment." },
	{ id = "w003", name = "Oak Staff", cat = "MainHand", sub = "2H Staff", hands = "Two-Handed", lv = 15, rarity = "Common", icon = "🏑", qty = 1, acqOrder = 3, isWeapon = true, tags = {"Ranged","Magical","Two-Handed","Mage"}, baseStats = {Attack=31,Range="2-4",Defense=0,WT=22,RTDelay=32}, passives = {{name="Arcane Reach",icon="✨",desc="Skills that inherit weapon range gain +1 bonus Maximum Range."}}, bonusStats = {INT=7}, bonusPassives = {}, flavor = "Cut from an ancient oak in the Whispering Forest." },
	{ id = "w004", name = "Flame Rapier", cat = "MainHand", sub = "1H Sword", hands = "One-Handed", lv = 22, rarity = "Rare", icon = "⚔", qty = 1, acqOrder = 18, isWeapon = true, isNew = true, tags = {"Melee","Piercing","One-Handed","Duelist"}, baseStats = {Attack=40,Range="1-1",Defense=0,WT=15,RTDelay=20}, passives = {{name="Precision Strike",icon="🎯",desc="+15% Hit Quality on Basic Attacks."}}, bonusStats = {DEX=9,AGI=4}, bonusPassives = {{name="Flame Touch",icon="🔥",desc="Basic attacks apply Burn for 2 rounds (10% weapon damage per tick)."}}, flavor = "A duelist's dream — fast, precise, and wreathed in flame." },
	{ id = "w005", name = "Crossbow", cat = "MainHand", sub = "2H Ranged", hands = "Two-Handed", lv = 20, rarity = "Rare", icon = "🏹", qty = 1, acqOrder = 20, isWeapon = true, isNew = true, tags = {"Ranged","Piercing","Two-Handed","Ranger"}, baseStats = {Attack=20,Range="2-4",Defense=0,WT=37,RTDelay=12}, passives = {{name="Armor Pierce",icon="🏹",desc="Reduce effective target Defense by 30% before damage resolution."}}, bonusStats = {DEX=9,AGI=4}, bonusPassives = {{name="Steady Aim",icon="🎯",desc="When you do not move during a round, increases Accuracy by 15%."},{name="Light Frame",icon="🪶",desc="Reduces Weapon Weight penalty by 10% when your DEX is 30 or higher."}}, flavor = "A hunter's crossbow, forged in a border outpost where survival depends on precision and patience." },
	{ id = "w006", name = "Hunter Bow", cat = "MainHand", sub = "2H Ranged", hands = "Two-Handed", lv = 20, rarity = "Uncommon", icon = "🏹", qty = 1, acqOrder = 12, isWeapon = true, tags = {"Ranged","Piercing","Two-Handed","Ranger"}, baseStats = {Attack=37,Range="2-4",Defense=-3,WT=41,RTDelay=67}, passives = {{name="High Ground",icon="⬆",desc="When attacking from higher elevation, increase elevation damage bonus by 35%."}}, bonusStats = {DEX=7,AGI=3}, bonusPassives = {}, flavor = "Carved from mountain ash. Favors those who take the high ground." },
	{ id = "w007", name = "Battle Axe", cat = "MainHand", sub = "2H Axe", hands = "Two-Handed", lv = 19, rarity = "Uncommon", icon = "🪓", qty = 1, acqOrder = 15, isWeapon = true, tags = {"Melee","Slashing","Two-Handed","Warrior"}, baseStats = {Attack=46,Range="1-1",Defense=0,WT=64,RTDelay=76}, passives = {{name="Knockback",icon="💥",desc="Basic attacks push the target 1 tile away if Force exceeds their Stability."}}, bonusStats = {STR=8,VIT=4}, bonusPassives = {}, flavor = "Built to cleave through shield walls. Subtlety is not its purpose." },
	{ id = "w008", name = "Mage Staff", cat = "MainHand", sub = "2H Staff", hands = "Two-Handed", lv = 16, rarity = "Common", icon = "🏑", qty = 1, acqOrder = 4, isWeapon = true, tags = {"Ranged","Magical","Two-Handed","Mage"}, baseStats = {Attack=32,Range="2-4",Defense=0,WT=23,RTDelay=34}, passives = {{name="Arcane Reach",icon="✨",desc="Skills that inherit weapon range gain +1 bonus Maximum Range."}}, bonusStats = {INT=6,LUK=2}, bonusPassives = {}, flavor = "Standard-issue from the Arcanum. Reliable, if uninspiring." },
	-- Off-Hand
	{ id = "s001", name = "Wooden Buckler", cat = "OffHand", sub = "Shield", hands = "Off-Hand", lv = 10, rarity = "Common", icon = "🛡", qty = 1, acqOrder = 2, isWeapon = false, tags = {"Off-Hand","Shield","Light"}, baseStats = {Defense=28,HP=0,MP=0,WT=10}, passives = {{name="Deflect",icon="🛡",desc="On Guard, reflect 20% of mitigated damage back to the attacker."}}, bonusStats = {VIT=3}, bonusPassives = {}, flavor = "Splinters easily, but better than bare skin." },
	{ id = "s002", name = "Steel Shield", cat = "OffHand", sub = "Shield", hands = "Off-Hand", lv = 18, rarity = "Uncommon", icon = "🛡", qty = 1, acqOrder = 11, isWeapon = false, tags = {"Off-Hand","Shield","Heavy"}, baseStats = {Defense=42,HP=0,MP=0,WT=18}, passives = {{name="Deflect",icon="🛡",desc="On Guard, reflect 20% of mitigated damage back to the attacker."}}, bonusStats = {VIT=5,STR=3}, bonusPassives = {}, flavor = "Forged in bulk for the frontier garrisons." },
	-- Head
	{ id = "h001", name = "Leather Cap", cat = "Head", sub = "Light", hands = nil, lv = 8, rarity = "Common", icon = "🪖", qty = 1, acqOrder = 6, isWeapon = false, tags = {"Head","Light","Armor"}, baseStats = {Defense=6,HP=0,MP=0,WT=4}, passives = {}, bonusStats = {}, bonusPassives = {}, flavor = "Thin leather, but it keeps the rain off." },
	{ id = "h002", name = "Iron Helm", cat = "Head", sub = "Heavy", hands = nil, lv = 16, rarity = "Uncommon", icon = "🪖", qty = 1, acqOrder = 10, isWeapon = false, tags = {"Head","Heavy","Armor"}, baseStats = {Defense=14,HP=0,MP=0,WT=12}, passives = {}, bonusStats = {VIT=3}, bonusPassives = {}, flavor = "Dented but sturdy. A veteran's helm." },
	{ id = "h003", name = "Leather Helm", cat = "Head", sub = "Light", hands = nil, lv = 20, rarity = "Uncommon", icon = "🪖", qty = 1, acqOrder = 14, isWeapon = false, tags = {"Head","Light","Armor"}, baseStats = {Defense=10,HP=0,MP=0,WT=6}, passives = {}, bonusStats = {AGI=2}, bonusPassives = {}, flavor = "Flexible hide, stitched for scouts and rangers." },
	-- Torso
	{ id = "t001", name = "Chain Mail", cat = "Torso", sub = "Medium", hands = nil, lv = 14, rarity = "Common", icon = "🦺", qty = 1, acqOrder = 7, isWeapon = false, tags = {"Torso","Medium","Armor"}, baseStats = {Defense=18,HP=0,MP=0,WT=20}, passives = {}, bonusStats = {VIT=4}, bonusPassives = {}, flavor = "Standard chain links. Stops slashes, not arrows." },
	{ id = "t002", name = "Mithril Plate", cat = "Torso", sub = "Heavy", hands = nil, lv = 24, rarity = "Rare", icon = "🦺", qty = 1, acqOrder = 19, isWeapon = false, tags = {"Torso","Heavy","Armor"}, baseStats = {Defense=36,HP=0,MP=0,WT=28}, passives = {}, bonusStats = {VIT=7,STR=4}, bonusPassives = {{name="Fortified",icon="🛡",desc="Reduce incoming critical bonus damage by 15%."}}, flavor = "Light as silk, hard as diamond. The smith's masterpiece." },
	{ id = "t003", name = "Leather Armor", cat = "Torso", sub = "Light", hands = nil, lv = 17, rarity = "Common", icon = "🦺", qty = 1, acqOrder = 9, isWeapon = false, tags = {"Torso","Light","Armor"}, baseStats = {Defense=12,HP=0,MP=0,WT=10}, passives = {}, bonusStats = {AGI=3}, bonusPassives = {}, flavor = "Supple tanned hide. Comfortable for long marches." },
	-- Arms
	{ id = "a001", name = "Leather Gloves", cat = "Arms", sub = "Light", hands = nil, lv = 8, rarity = "Common", icon = "🧤", qty = 1, acqOrder = 8, isWeapon = false, tags = {"Arms","Light","Armor"}, baseStats = {Defense=4,HP=0,MP=0,WT=3}, passives = {}, bonusStats = {DEX=2}, bonusPassives = {}, flavor = "Thin enough to thread a needle." },
	{ id = "a002", name = "Iron Gauntlets", cat = "Arms", sub = "Heavy", hands = nil, lv = 16, rarity = "Uncommon", icon = "🧤", qty = 1, acqOrder = 13, isWeapon = false, tags = {"Arms","Heavy","Armor"}, baseStats = {Defense=10,HP=0,MP=0,WT=10}, passives = {}, bonusStats = {STR=3,VIT=2}, bonusPassives = {}, flavor = "Reinforced knuckles. Punching is inadvisable but possible." },
	-- Legs
	{ id = "l001", name = "Iron Greaves", cat = "Legs", sub = "Heavy", hands = nil, lv = 12, rarity = "Common", icon = "🥾", qty = 1, acqOrder = 16, isWeapon = false, tags = {"Legs","Heavy","Armor"}, baseStats = {Defense=8,HP=0,MP=0,WT=8}, passives = {}, bonusStats = {VIT=2}, bonusPassives = {}, flavor = "Clanks with every step. Your enemies hear you coming." },
	{ id = "l002", name = "Boots", cat = "Legs", sub = "Light", hands = nil, lv = 14, rarity = "Common", icon = "🥾", qty = 1, acqOrder = 17, isWeapon = false, tags = {"Legs","Light","Armor"}, baseStats = {Defense=5,HP=0,MP=0,WT=4}, passives = {}, bonusStats = {AGI=3}, bonusPassives = {}, flavor = "Soft leather soles. Silent on stone." },
	-- Accessory
	{ id = "ac001", name = "Silver Ring", cat = "Accessory", sub = "Ring", hands = nil, lv = 10, rarity = "Uncommon", icon = "💍", qty = 1, acqOrder = 21, isWeapon = false, tags = {"Accessory","Ring"}, baseStats = {Defense=0,HP=0,MP=0,WT=0}, passives = {}, bonusStats = {LUK=5}, bonusPassives = {}, flavor = "A lucky charm from a market stall." },
	{ id = "ac002", name = "Warrior's Pendant", cat = "Accessory", sub = "Necklace", hands = nil, lv = 18, rarity = "Rare", icon = "💍", qty = 1, acqOrder = 22, isWeapon = false, tags = {"Accessory","Necklace"}, baseStats = {Defense=0,HP=0,MP=0,WT=0}, passives = {}, bonusStats = {STR=6,VIT=4}, bonusPassives = {{name="Battle Fury",icon="🔥",desc="After defeating an enemy, gain +10% Force for the rest of the battle."}}, flavor = "Worn by a captain who never lost a siege." },
	{ id = "ac003", name = "Power Ring", cat = "Accessory", sub = "Ring", hands = nil, lv = 16, rarity = "Uncommon", icon = "💍", qty = 1, acqOrder = 23, isWeapon = false, tags = {"Accessory","Ring"}, baseStats = {Defense=0,HP=0,MP=0,WT=0}, passives = {}, bonusStats = {STR=5,DEX=3}, bonusPassives = {}, flavor = "Warm to the touch. The gem pulses faintly." },
	{ id = "ac004", name = "Wind Charm", cat = "Accessory", sub = "Charm", hands = nil, lv = 15, rarity = "Uncommon", icon = "💎", qty = 1, acqOrder = 24, isWeapon = false, tags = {"Accessory","Charm"}, baseStats = {Defense=0,HP=0,MP=0,WT=0}, passives = {}, bonusStats = {AGI=6}, bonusPassives = {{name="Tailwind",icon="💨",desc="Movement range +1 on the first round of each battle."}}, flavor = "Swirls of trapped breeze inside polished crystal." },
	{ id = "ac005", name = "Bracelet", cat = "Accessory", sub = "Bracelet", hands = nil, lv = 18, rarity = "Common", icon = "💍", qty = 1, acqOrder = 25, isWeapon = false, tags = {"Accessory","Bracelet"}, baseStats = {Defense=0,HP=0,MP=0,WT=0}, passives = {}, bonusStats = {VIT=3}, bonusPassives = {}, flavor = "Plain iron links. Functional." },
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

function MockLoadoutData.MockUnequip(unitId, slot)
	local eq = MockLoadoutData.Equipped[unitId]
	if not eq then return end
	local prev = eq[slot]
	eq[slot] = nil
	print("[Mock] Unequipped", prev, "from", slot, "on", unitId)
end

return MockLoadoutData
