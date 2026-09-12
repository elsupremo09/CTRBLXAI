-- MockLoadoutData.lua
-- CTRBLXAI | Slice 7 — Mock data provider for Loadout Screen
-- DEFERRED DEPENDENCY: Real data comes from Slice 4.
-- Every table here is a MOCK placeholder.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BattleEvents = require(
	ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
		:WaitForChild("Remotes", 10)
		:WaitForChild("BattleEvents", 10)
)

-- Content definition modules (full skill/augment data for UI lookups)
local SkillDataModule = require(
	ReplicatedStorage:WaitForChild("Content", 10)
		:WaitForChild("SkillData", 10)
)
local AugmentDataModule = require(
	ReplicatedStorage:WaitForChild("Content", 10)
		:WaitForChild("AugmentData", 10)
)
local DoctrineDataModule = require(
	ReplicatedStorage:WaitForChild("Content", 10)
		:WaitForChild("DoctrineData", 10)
)

local MockLoadoutData = {}

MockLoadoutData._useServerData = false
MockLoadoutData._useServerSkillData = false

-- Server skill data storage (populated by LoadSkillData)
MockLoadoutData.ServerSkillSlots = {}    -- [unitId] = slots array from server
MockLoadoutData.SkillCardInventory = {}  -- [skillId] = quantity
MockLoadoutData.AugmentCardInventory = {} -- [augmentId] = quantity

-- Content definition lookups
MockLoadoutData.SkillDefs = SkillDataModule
MockLoadoutData.AugmentDefs = AugmentDataModule

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
	{ id = "w001", name = "Iron Longsword", cat = "MainHand", sub = "1H Sword", hands = "One-Handed", lv = 12, rarity = "Common", icon = "⚔", qty = 1, acqOrder = 1, isWeapon = true, tags = {}, baseStats = {Attack=34,Range="1-1",Defense=3,WT=31,RTDelay=31}, passives = {{name="Power Strike",icon="⚔",desc="Unleash a heavy melee blow that increases your Force on the first attack each round."}}, bonusStats = {STR=6,VIT=3}, bonusPassives = {}, flavor = "A soldier's blade, forged in the capital armory." },
	{ id = "w002", name = "Steel Greatsword", cat = "MainHand", sub = "2H Sword", hands = "Two-Handed", lv = 18, rarity = "Uncommon", icon = "⚔", qty = 1, acqOrder = 5, isWeapon = true, tags = {}, baseStats = {Attack=37,Range="1-1",Defense=6,WT=16,RTDelay=94}, passives = {{name="Cleave",icon="⚔",desc="Basic attacks hit adjacent tiles in a sweeping arc."}}, bonusStats = {STR=8,VIT=5}, bonusPassives = {}, flavor = "Heavy and true. Each swing carves through armor like parchment." },
	{ id = "w003", name = "Oak Staff", cat = "MainHand", sub = "2H Staff", hands = "Two-Handed", lv = 15, rarity = "Common", icon = "🏑", qty = 1, acqOrder = 3, isWeapon = true, tags = {}, baseStats = {Attack=31,Range="2-4",Defense=0,WT=22,RTDelay=32}, passives = {{name="Arcane Reach",icon="✨",desc="Skills that inherit weapon range gain +1 bonus Maximum Range."}}, bonusStats = {INT=7}, bonusPassives = {}, flavor = "Cut from an ancient oak in the Whispering Forest." },
	{ id = "w004", name = "Flame Rapier", cat = "MainHand", sub = "1H Sword", hands = "One-Handed", lv = 22, rarity = "Rare", icon = "⚔", qty = 1, acqOrder = 18, isWeapon = true, tags = {}, baseStats = {Attack=40,Range="1-1",Defense=0,WT=15,RTDelay=20}, passives = {{name="Precision Strike",icon="🎯",desc="+15% Hit Quality on Basic Attacks."}}, bonusStats = {DEX=9,AGI=4}, bonusPassives = {{name="Flame Touch",icon="🔥",desc="Basic attacks apply Burn for 2 rounds (10% weapon damage per tick)."}}, flavor = "A duelist's dream — fast, precise, and wreathed in flame." },
	{ id = "w005", name = "Crossbow", cat = "MainHand", sub = "2H Ranged", hands = "Two-Handed", lv = 20, rarity = "Rare", icon = "🏹", qty = 1, acqOrder = 20, isWeapon = true, tags = {}, baseStats = {Attack=20,Range="2-4",Defense=0,WT=37,RTDelay=12}, passives = {{name="Armor Pierce",icon="🏹",desc="Reduce effective target Defense by 30% before damage resolution."}}, bonusStats = {DEX=9,AGI=4}, bonusPassives = {{name="Steady Aim",icon="🎯",desc="When you do not move during a round, increases Accuracy by 15%."},{name="Light Frame",icon="🪶",desc="Reduces Weapon Weight penalty by 10% when your DEX is 30 or higher."}}, flavor = "A hunter's crossbow, forged in a border outpost where survival depends on precision and patience." },
	{ id = "w006", name = "Hunter Bow", cat = "MainHand", sub = "2H Ranged", hands = "Two-Handed", lv = 20, rarity = "Uncommon", icon = "🏹", qty = 1, acqOrder = 12, isWeapon = true, tags = {}, baseStats = {Attack=37,Range="2-4",Defense=-3,WT=41,RTDelay=67}, passives = {{name="High Ground",icon="⬆",desc="When attacking from higher elevation, increase elevation damage bonus by 35%."}}, bonusStats = {DEX=7,AGI=3}, bonusPassives = {}, flavor = "Carved from mountain ash. Favors those who take the high ground." },
	{ id = "w007", name = "Battle Axe", cat = "MainHand", sub = "2H Axe", hands = "Two-Handed", lv = 19, rarity = "Uncommon", icon = "🪓", qty = 1, acqOrder = 15, isWeapon = true, tags = {}, baseStats = {Attack=46,Range="1-1",Defense=0,WT=64,RTDelay=76}, passives = {{name="Knockback",icon="💥",desc="Basic attacks push the target 1 tile away if Force exceeds their Stability."}}, bonusStats = {STR=8,VIT=4}, bonusPassives = {}, flavor = "Built to cleave through shield walls. Subtlety is not its purpose." },
	{ id = "w008", name = "Mage Staff", cat = "MainHand", sub = "2H Staff", hands = "Two-Handed", lv = 16, rarity = "Common", icon = "🏑", qty = 1, acqOrder = 4, isWeapon = true, tags = {}, baseStats = {Attack=32,Range="2-4",Defense=0,WT=23,RTDelay=34}, passives = {{name="Arcane Reach",icon="✨",desc="Skills that inherit weapon range gain +1 bonus Maximum Range."}}, bonusStats = {INT=6,LUK=2}, bonusPassives = {}, flavor = "Standard-issue from the Arcanum. Reliable, if uninspiring." },
	-- Off-Hand
	{ id = "s001", name = "Wooden Buckler", cat = "OffHand", sub = "Shield", hands = "Off-Hand", lv = 10, rarity = "Common", icon = "🛡", qty = 1, acqOrder = 2, isWeapon = false, tags = {}, baseStats = {Defense=28,HP=0,MP=0,WT=10}, passives = {{name="Deflect",icon="🛡",desc="On Guard, reflect 20% of mitigated damage back to the attacker."}}, bonusStats = {VIT=3}, bonusPassives = {}, flavor = "Splinters easily, but better than bare skin." },
	{ id = "s002", name = "Steel Shield", cat = "OffHand", sub = "Shield", hands = "Off-Hand", lv = 18, rarity = "Uncommon", icon = "🛡", qty = 1, acqOrder = 11, isWeapon = false, tags = {}, baseStats = {Defense=42,HP=0,MP=0,WT=18}, passives = {{name="Deflect",icon="🛡",desc="On Guard, reflect 20% of mitigated damage back to the attacker."}}, bonusStats = {VIT=5,STR=3}, bonusPassives = {}, flavor = "Forged in bulk for the frontier garrisons." },
	-- Head
	{ id = "h001", name = "Leather Cap", cat = "Head", sub = "Light", hands = nil, lv = 8, rarity = "Common", icon = "🪖", qty = 1, acqOrder = 6, isWeapon = false, tags = {}, baseStats = {Defense=6,HP=0,MP=0,WT=4}, passives = {}, bonusStats = {}, bonusPassives = {}, flavor = "Thin leather, but it keeps the rain off." },
	{ id = "h002", name = "Iron Helm", cat = "Head", sub = "Heavy", hands = nil, lv = 16, rarity = "Uncommon", icon = "🪖", qty = 1, acqOrder = 10, isWeapon = false, tags = {}, baseStats = {Defense=14,HP=0,MP=0,WT=12}, passives = {}, bonusStats = {VIT=3}, bonusPassives = {}, flavor = "Dented but sturdy. A veteran's helm." },
	{ id = "h003", name = "Leather Helm", cat = "Head", sub = "Light", hands = nil, lv = 20, rarity = "Uncommon", icon = "🪖", qty = 1, acqOrder = 14, isWeapon = false, tags = {}, baseStats = {Defense=10,HP=0,MP=0,WT=6}, passives = {}, bonusStats = {AGI=2}, bonusPassives = {}, flavor = "Flexible hide, stitched for scouts and rangers." },
	-- Torso
	{ id = "t001", name = "Chain Mail", cat = "Torso", sub = "Medium", hands = nil, lv = 14, rarity = "Common", icon = "🦺", qty = 1, acqOrder = 7, isWeapon = false, tags = {}, baseStats = {Defense=18,HP=0,MP=0,WT=20}, passives = {}, bonusStats = {VIT=4}, bonusPassives = {}, flavor = "Standard chain links. Stops slashes, not arrows." },
	{ id = "t002", name = "Mithril Plate", cat = "Torso", sub = "Heavy", hands = nil, lv = 24, rarity = "Rare", icon = "🦺", qty = 1, acqOrder = 19, isWeapon = false, tags = {}, baseStats = {Defense=36,HP=0,MP=0,WT=28}, passives = {}, bonusStats = {VIT=7,STR=4}, bonusPassives = {{name="Fortified",icon="🛡",desc="Reduce incoming critical bonus damage by 15%."}}, flavor = "Light as silk, hard as diamond. The smith's masterpiece." },
	{ id = "t003", name = "Leather Armor", cat = "Torso", sub = "Light", hands = nil, lv = 17, rarity = "Common", icon = "🦺", qty = 1, acqOrder = 9, isWeapon = false, tags = {}, baseStats = {Defense=12,HP=0,MP=0,WT=10}, passives = {}, bonusStats = {AGI=3}, bonusPassives = {}, flavor = "Supple tanned hide. Comfortable for long marches." },
	-- Arms
	{ id = "a001", name = "Leather Gloves", cat = "Arms", sub = "Light", hands = nil, lv = 8, rarity = "Common", icon = "🧤", qty = 1, acqOrder = 8, isWeapon = false, tags = {}, baseStats = {Defense=4,HP=0,MP=0,WT=3}, passives = {}, bonusStats = {DEX=2}, bonusPassives = {}, flavor = "Thin enough to thread a needle." },
	{ id = "a002", name = "Iron Gauntlets", cat = "Arms", sub = "Heavy", hands = nil, lv = 16, rarity = "Uncommon", icon = "🧤", qty = 1, acqOrder = 13, isWeapon = false, tags = {}, baseStats = {Defense=10,HP=0,MP=0,WT=10}, passives = {}, bonusStats = {STR=3,VIT=2}, bonusPassives = {}, flavor = "Reinforced knuckles. Punching is inadvisable but possible." },
	-- Legs
	{ id = "l001", name = "Iron Greaves", cat = "Legs", sub = "Heavy", hands = nil, lv = 12, rarity = "Common", icon = "🥾", qty = 1, acqOrder = 16, isWeapon = false, tags = {}, baseStats = {Defense=8,HP=0,MP=0,WT=8}, passives = {}, bonusStats = {VIT=2}, bonusPassives = {}, flavor = "Clanks with every step. Your enemies hear you coming." },
	{ id = "l002", name = "Boots", cat = "Legs", sub = "Light", hands = nil, lv = 14, rarity = "Common", icon = "🥾", qty = 1, acqOrder = 17, isWeapon = false, tags = {}, baseStats = {Defense=5,HP=0,MP=0,WT=4}, passives = {}, bonusStats = {AGI=3}, bonusPassives = {}, flavor = "Soft leather soles. Silent on stone." },
	-- Accessory
	{ id = "ac001", name = "Silver Ring", cat = "Accessory", sub = "Ring", hands = nil, lv = 10, rarity = "Uncommon", icon = "💍", qty = 1, acqOrder = 21, isWeapon = false, tags = {}, baseStats = {Defense=0,HP=0,MP=0,WT=0}, passives = {}, bonusStats = {LUK=5}, bonusPassives = {}, flavor = "A lucky charm from a market stall." },
	{ id = "ac002", name = "Warrior's Pendant", cat = "Accessory", sub = "Necklace", hands = nil, lv = 18, rarity = "Rare", icon = "💍", qty = 1, acqOrder = 22, isWeapon = false, tags = {}, baseStats = {Defense=0,HP=0,MP=0,WT=0}, passives = {}, bonusStats = {STR=6,VIT=4}, bonusPassives = {{name="Battle Fury",icon="🔥",desc="After defeating an enemy, gain +10% Force for the rest of the battle."}}, flavor = "Worn by a captain who never lost a siege." },
	{ id = "ac003", name = "Power Ring", cat = "Accessory", sub = "Ring", hands = nil, lv = 16, rarity = "Uncommon", icon = "💍", qty = 1, acqOrder = 23, isWeapon = false, tags = {}, baseStats = {Defense=0,HP=0,MP=0,WT=0}, passives = {}, bonusStats = {STR=5,DEX=3}, bonusPassives = {}, flavor = "Warm to the touch. The gem pulses faintly." },
	{ id = "ac004", name = "Wind Charm", cat = "Accessory", sub = "Charm", hands = nil, lv = 15, rarity = "Uncommon", icon = "💎", qty = 1, acqOrder = 24, isWeapon = false, tags = {}, baseStats = {Defense=0,HP=0,MP=0,WT=0}, passives = {}, bonusStats = {AGI=6}, bonusPassives = {{name="Tailwind",icon="💨",desc="Movement range +1 on the first round of each battle."}}, flavor = "Swirls of trapped breeze inside polished crystal." },
	{ id = "ac005", name = "Bracelet", cat = "Accessory", sub = "Bracelet", hands = nil, lv = 18, rarity = "Common", icon = "💍", qty = 1, acqOrder = 25, isWeapon = false, tags = {}, baseStats = {Defense=0,HP=0,MP=0,WT=0}, passives = {}, bonusStats = {VIT=3}, bonusPassives = {}, flavor = "Plain iron links. Functional." },
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
	if eq and eq[slot] then
		-- Consumable slots store full item tables, equipment stores IDs
		if type(eq[slot]) == "table" then return eq[slot] end
		return MockLoadoutData.GetItem(eq[slot])
	end
	return nil
end

-- Build a virtual item for the equipped doctrine (not a real inventory item)
function MockLoadoutData.GetEquippedDoctrine(unitId)
	local docId = MockLoadoutData.GetUnitDoctrineId(unitId)
	if not docId then return nil end
	local doc = DoctrineDataModule[docId]
	if not doc or type(doc) ~= "table" or not doc.name then return nil end
	return {
		id = docId,
		name = doc.name,
		cat = "Doctrine",
		sub = "Doctrine",
		hands = nil,
		lv = 0,
		rarity = "Legendary",
		icon = doc.icon or "[D]",
		qty = 1,
		isWeapon = false,
		isDoctrine = true,
		tags = { "Doctrine" },
		baseStats = {},
		passives = doc.passiveName and {{
			name = doc.passiveName,
			icon = "[*]",
			desc = doc.passiveEffect or "",
		}} or {},
		bonusStats = doc.statPackage or {},
		bonusPassives = {},
		flavor = doc.identity or "",
	}
end

function MockLoadoutData.IsEquipped(itemId, unitId)
	local eq = MockLoadoutData.Equipped[unitId]
	if not eq then return false end
	for _, eqId in pairs(eq) do
		if eqId == itemId then return true end
	end
	return false
end

function MockLoadoutData.IsEquippedByAny(itemId)
	for unitId, eq in pairs(MockLoadoutData.Equipped) do
		for _, eqId in pairs(eq) do
			if eqId == itemId then return true, unitId end
		end
	end
	return false, nil
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
	if MockLoadoutData._useServerData then
		local ok, result = pcall(function()
			return BattleEvents.RequestEquip:InvokeServer(unitId, itemId)
		end)
		if ok then
			print("[LoadoutData] Server equip:", unitId, slot, itemId)
			MockLoadoutData.LoadFromServer()  -- refresh
			return
		end
	end
	eq[slot] = itemId
	print("[Mock] Equipped", itemId, "to", slot, "on", unitId)
end

function MockLoadoutData.MockUnequip(unitId, slot)
	local eq = MockLoadoutData.Equipped[unitId]
	if not eq then return end
	if MockLoadoutData._useServerData then
		local ok, result = pcall(function()
			return BattleEvents.RequestUnequip:InvokeServer(unitId, slot)
		end)
		if ok then
			print("[LoadoutData] Server unequip:", unitId, slot)
			MockLoadoutData.LoadFromServer()  -- refresh
			return
		end
	end
	local prev = eq[slot]
	eq[slot] = nil
	print("[Mock] Unequipped", prev, "from", slot, "on", unitId)
end

--------------------------------------------------
-- SERVER DATA LOADING
--------------------------------------------------

-- Passive ID → display name lookup (lightweight, no full descriptions)
local PASSIVE_NAMES = {
	ArmorPierce = "Armor Pierce", Cleave = "Cleave", PowerStrike = "Power Strike",
	Knockback = "Knockback", Fortify = "Fortify", ArcaneFlow = "Arcane Flow",
	ArcaneReach = "Arcane Reach", HighGround = "High Ground", PiercingEdge = "Piercing Edge",
	RangePlus1 = "Range +1", Stagger = "Stagger", Brutal = "Brutal", Deflect = "Deflect",
	Venomous = "Venomous", Riposte = "Riposte", Tempo = "Tempo",
}

-- Hand class → icon emoji mapping
local HAND_ICONS = {
	["1H"] = "⚔", ["2H"] = "⚔", ["Off-Hand"] = "🛡",
}

-- Map a server item to the UI format expected by LoadoutScreen
local function mapServerItem(si)
	local isWeapon = si.isWeapon or (si.category == "Weapon")
	local range = (si.minRange or 1) .. "-" .. (si.maxRange or 1)

	-- Determine slot category from handClass + category + armor slot
	local SLOT_MAP = { Body = "Torso", Gloves = "Arms", Feet = "Legs" }
	local cat = "MainHand"
	if si.handClass == "Off-Hand" then
		cat = "OffHand"
	elseif si.isArmor and si.slot then
		cat = SLOT_MAP[si.slot] or si.slot
	elseif not isWeapon then
		cat = si.category or "Accessory"
	end

	-- Build tags
	local tags = {}
	if si.handClass then table.insert(tags, si.handClass) end
	if si.isArmor and si.slot then
		table.insert(tags, si.slot)
	elseif si.category and si.category ~= "OffHand" and si.category ~= "Weapon" then
		table.insert(tags, si.category)
	end
	if si.projectileType then
		table.insert(tags, si.projectileType)
	elseif isWeapon and not si.handClass then
		table.insert(tags, "Melee")
	end
	if si.element then table.insert(tags, si.element) end

	-- Base stats
	local baseStats
	if isWeapon then
		baseStats = {
			Attack = si.damage or 0, Range = range,
			Defense = si.defense or 0, WT = si.wt or 0,
			RTDelay = si.rtDelay or 0,
		}
	else
		baseStats = {
			Defense = si.defense or 0, HP = 0, MP = 0, WT = si.wt or 0,
		}
	end

	-- Archetype passive
	local passives = {}
	if si.nativePassiveId then
		table.insert(passives, {
			name = PASSIVE_NAMES[si.nativePassiveId] or si.nativePassiveId,
			icon = "[*]",
			desc = si.nativePassiveDesc or "",
		})
	elseif si.passiveName and si.passiveName ~= "" then
		table.insert(passives, {
			name = si.passiveName,
			icon = "[*]",
			desc = si.passiveDesc or "",
		})
	end

	-- DIAG: log bonus stats + passives
	local hasBonusStats = si.bonusStats and next(si.bonusStats)
	local hasBonusPassives = si.bonusPassives and #si.bonusPassives > 0
	if hasBonusStats or hasBonusPassives then
		local parts = {}
		if hasBonusStats then
			for k, v in pairs(si.bonusStats) do table.insert(parts, k .. "=" .. tostring(v)) end
		end
		local passiveNames = {}
		if hasBonusPassives then
			for _, p in ipairs(si.bonusPassives) do table.insert(passiveNames, p.name or "?") end
		end
		print("[DIAG-Bonus] " .. (si.name or "?") .. " (" .. (si.rarity or "?") .. "): stats={" .. table.concat(parts, ", ") .. "} passives={" .. table.concat(passiveNames, ", ") .. "} (bonusCount=" .. tostring(si.bonusCount) .. " passiveCount=" .. tostring(si.passiveCount) .. ")")
	end

	return {
		id = si.instanceId,
		name = si.name or "Unknown",
		cat = cat,
		sub = si.handClass or "1H",
		hands = si.handClass,
		lv = si.itemLevel or 1,
		rarity = si.rarity or "Common",
		icon = si.icon or HAND_ICONS[si.handClass] or "[*]",
		qty = 1,
		isWeapon = isWeapon,
		isNew = si.isNew or false,
		tags = tags,
		baseStats = baseStats,
		passives = passives,
		bonusStats = si.bonusStats or {},
		bonusPassives = si.bonusPassives or {},
		flavor = si.flavor or "",
	}
end

function MockLoadoutData.LoadFromServer()
	print("[LoadoutData] Attempting to fetch inventory from server...")

	if not BattleEvents or not BattleEvents.GetInventoryData then
		warn("[LoadoutData] BattleEvents.GetInventoryData not available — using mock data")
		MockLoadoutData._useServerData = false
		return
	end

	local ok, serverItems = pcall(function()
		return BattleEvents.GetInventoryData:InvokeServer()
	end)
	if ok and serverItems and #serverItems > 0 then
		MockLoadoutData.Inventory = {}
		MockLoadoutData.Equipped = {}
		for _, si in ipairs(serverItems) do
			local uiItem = mapServerItem(si)
			table.insert(MockLoadoutData.Inventory, uiItem)
			-- Track equipped items
			if si.equippedBy then
				if not MockLoadoutData.Equipped[si.equippedBy] then
					MockLoadoutData.Equipped[si.equippedBy] = {}
				end
				-- Normalize server slot names to UI slot names
				local SLOT_MAP = { Body = "Torso", Gloves = "Arms", Feet = "Legs" }
				local rawSlot = si.equippedSlot or uiItem.cat
				local uiSlot = SLOT_MAP[rawSlot] or rawSlot
				MockLoadoutData.Equipped[si.equippedBy][uiSlot] = uiItem.id
			end
		end
		MockLoadoutData._useServerData = true
		print(string.format("[LoadoutData] Loaded %d items from server (%d equipped)",
			#MockLoadoutData.Inventory,
			#serverItems - #MockLoadoutData.Inventory + #MockLoadoutData.Inventory))

		-- Fetch consumable slots
		if BattleEvents and BattleEvents.GetConsumableSlots then
			local csOk, consSlots = pcall(function()
				return BattleEvents.GetConsumableSlots:InvokeServer()
			end)
			if csOk and consSlots then
				local totalCons = 0
				for unitId, slots in pairs(consSlots) do
					if not MockLoadoutData.Equipped[unitId] then
						MockLoadoutData.Equipped[unitId] = {}
					end
					-- Update slot lock state from server (same for all units)
					for idx, sd in pairs(slots) do
						MockLoadoutData.ConsSlotLocked["Cons" .. idx] = (sd.locked == true)
					end
					for idx, sd in pairs(slots) do
						local slotKey = "Cons" .. idx
						if sd.consumableId and not sd.empty then
							MockLoadoutData.Equipped[unitId][slotKey] = {
								id = sd.consumableId, consumableId = sd.consumableId,
								name = sd.name or sd.consumableId,
								cat = "Consumable", sub = "Consumable",
								icon = "?", qty = sd.currentCharges or 1,
							}
							totalCons = totalCons + 1
						end
					end
				end
				print(string.format("[LoadoutData] Loaded %d consumable slots", totalCons))
			else
				warn("[LoadoutData] Failed to load consumable slots: " .. tostring(consSlots))
			end
		end
	else
		warn("[LoadoutData] Server fetch failed — using mock data. ok=" .. tostring(ok)
			.. " result=" .. tostring(serverItems))
		MockLoadoutData._useServerData = false
	end
end


--------------------------------------------------
-- MOCK SKILL DATA (for Skills Tab)
--------------------------------------------------

-- Skills available in the game (simplified from SkillData.lua / GameConstants.SKILLS)
MockLoadoutData.SkillCatalog = {
	{ id = "skill_power_strike", name = "Power Strike", tags = {"Direct Damage","Physical"}, mpCost = 2, rtCost = 40, range = 1, pattern = "Single", desc = "A powerful melee strike dealing 1.20× weapon damage.", element = "Physical" },
	{ id = "skill_sweeping_cut", name = "Sweeping Cut", tags = {"Direct Damage","Physical","AOE"}, mpCost = 4, rtCost = 50, range = 1, pattern = "Cleave", desc = "Slash in a wide arc hitting adjacent enemies.", element = "Physical" },
	{ id = "skill_fire_bolt", name = "Fire Bolt", tags = {"Direct Damage","Fire"}, mpCost = 3, rtCost = 40, range = 4, pattern = "Single", desc = "Launch a bolt of fire at a distant enemy.", element = "Fire" },
	{ id = "skill_healing_light", name = "Healing Light", tags = {"Healing","Holy"}, mpCost = 4, rtCost = 20, range = 4, pattern = "Single", desc = "Restore HP to an ally.", element = "Holy" },
	{ id = "skill_crippling_shot", name = "Crippling Shot", tags = {"Direct Damage","Physical","Debuff"}, mpCost = 3, rtCost = 40, range = 3, pattern = "Single", desc = "A ranged shot that slows the target.", element = "Physical" },
	{ id = "skill_venom_strike", name = "Venom Strike", tags = {"Direct Damage","Physical","Debuff"}, mpCost = 3, rtCost = 35, range = 1, pattern = "Single", desc = "Melee attack that poisons the target.", element = "Physical" },
	{ id = "doc_berserker_01", name = "Raging Blow", tags = {"Direct Damage","Physical"}, mpCost = 5, rtCost = 60, range = 1, pattern = "Single", desc = "Berserker doctrine skill. Devastating blow that scales with missing HP.", element = "Physical", isDoctrine = true },
	{ id = "doc_ranger_01", name = "Eagle Eye", tags = {"Buff"}, mpCost = 3, rtCost = 30, range = 0, pattern = "Self", desc = "Ranger doctrine skill. Increases accuracy and range for 2 turns.", element = nil, isDoctrine = true },
	{ id = "doc_arcanist_01", name = "Arcane Surge", tags = {"Direct Damage","Arcane"}, mpCost = 6, rtCost = 50, range = 4, pattern = "Single", desc = "Arcanist doctrine skill. Pure arcane damage that ignores defense.", element = "Arcane", isDoctrine = true },
}

-- Doctrine → skill choices mapping (references SkillCatalog ids)
MockLoadoutData.DoctrineSkillChoices = {
	["DOC-BERSERKER"] = { "doc_berserker_01", "skill_power_strike", "skill_sweeping_cut" },
	["DOC-RANGER"] = { "doc_ranger_01", "skill_crippling_shot", "skill_venom_strike" },
	["DOC-ARCANIST"] = { "doc_arcanist_01", "skill_fire_bolt", "skill_healing_light" },
}

-- Equipped skills per unit (slot 1 = doctrine, slots 2-4 = normal, slot 5 = locked)
MockLoadoutData.SkillLoadout = {
	unit_hero = {
		[1] = "doc_berserker_01",  -- Doctrine Skill
		[2] = "skill_power_strike",
		[3] = "skill_sweeping_cut",
		[4] = nil,                  -- Empty slot
		[5] = nil,                  -- Locked
	},
	unit_ranger = {
		[1] = "doc_ranger_01",
		[2] = "skill_crippling_shot",
		[3] = "skill_venom_strike",
		[4] = nil,
		[5] = nil,
	},
	unit_mage = {
		[1] = "doc_arcanist_01",
		[2] = "skill_fire_bolt",
		[3] = "skill_healing_light",
		[4] = nil,
		[5] = nil,
	},
}

function MockLoadoutData.GetSkill(skillId)
	for _, sk in ipairs(MockLoadoutData.SkillCatalog) do
		if sk.id == skillId then return sk end
	end
	return nil
end

function MockLoadoutData.GetSkillLoadout(unitId)
	if MockLoadoutData.ServerSkillSlots[unitId] then
		return MockLoadoutData.ServerSkillSlots[unitId]
	end
	return MockLoadoutData.SkillLoadout[unitId] or {}
end

function MockLoadoutData.GetDoctrineChoices(doctrineId)
	return MockLoadoutData.DoctrineSkillChoices[doctrineId] or {}
end

function MockLoadoutData.GetUnitDoctrineId(unitId)
	if MockLoadoutData.ServerDoctrineId and MockLoadoutData.ServerDoctrineId[unitId] then
		return MockLoadoutData.ServerDoctrineId[unitId]
	end
	-- Fallback to mock unit data
	local unit = MockLoadoutData.GetSelectedUnit()
	return unit and unit.doctrineId or "DOC-BERSERKER"
end

--------------------------------------------------
-- CONTENT DEFINITION HELPERS
--------------------------------------------------

function MockLoadoutData.GetSkillDef(skillId)
	if not skillId then return nil end
	return MockLoadoutData.SkillDefs[skillId]
end

function MockLoadoutData.GetAugmentDef(augmentId)
	if not augmentId then return nil end
	return MockLoadoutData.AugmentDefs[augmentId]
end

--------------------------------------------------
-- SERVER SKILL DATA LOADING
--------------------------------------------------

--- Fetch skill loadout from server for a unit.
-- Stores result in ServerSkillSlots, SkillCardInventory, AugmentCardInventory.
-- Falls back silently on failure (mock data remains available).
function MockLoadoutData.LoadSkillData(unitId)
	print("[LoadoutData] Attempting to fetch skill loadout from server for:", unitId)

	if not BattleEvents or not BattleEvents.GetSkillLoadout then
		warn("[LoadoutData] BattleEvents.GetSkillLoadout not available — using mock skill data")
		MockLoadoutData._useServerSkillData = false
		return
	end

	local ok, result = pcall(function()
		return BattleEvents.GetSkillLoadout:InvokeServer(unitId)
	end)

	if ok and result and result.ok then
		-- Store slots for this unit
		MockLoadoutData.ServerSkillSlots[unitId] = result.slots or {}

		-- Store card inventories (shared across units)
		if result.skillCards then
			MockLoadoutData.SkillCardInventory = result.skillCards
		end
		if result.augmentCards then
			MockLoadoutData.AugmentCardInventory = result.augmentCards
		end

		-- Store doctrine choices from server (keyed by doctrineId)
		if result.doctrineId and result.doctrineChoices then
			MockLoadoutData.DoctrineSkillChoices[result.doctrineId] = result.doctrineChoices
		end
		-- Store the server-authoritative doctrineId for this unit
		if result.doctrineId then
			MockLoadoutData.ServerDoctrineId = MockLoadoutData.ServerDoctrineId or {}
			MockLoadoutData.ServerDoctrineId[unitId] = result.doctrineId
		end

		MockLoadoutData._useServerSkillData = true
		print(string.format(
			"[LoadoutData] Loaded skill data from server for %s: %d slots, %d skill cards, %d augment cards",
			unitId,
			#MockLoadoutData.ServerSkillSlots[unitId],
			(function()
				local n = 0
				for _ in pairs(MockLoadoutData.SkillCardInventory) do n = n + 1 end
				return n
			end)(),
			(function()
				local n = 0
				for _ in pairs(MockLoadoutData.AugmentCardInventory) do n = n + 1 end
				return n
			end)()
		))
	else
		warn("[LoadoutData] Server skill fetch failed — using mock data. ok="
			.. tostring(ok) .. " result=" .. tostring(result))
		MockLoadoutData._useServerSkillData = false
	end
end

--------------------------------------------------
-- SERVER SKILL/AUGMENT ACTION WRAPPERS
--------------------------------------------------

function MockLoadoutData.ServerEquipSkillCard(unitId, slotIndex, skillId)
	local ok, result = pcall(function()
		return BattleEvents.RequestEquipSkillCard:InvokeServer(unitId, slotIndex, skillId)
	end)
	if ok then
		print("[LoadoutData] Server equip skill card:", unitId, slotIndex, skillId)
		return result
	end
	warn("[LoadoutData] ServerEquipSkillCard failed:", result)
	return { ok = false, reason = "Server error" }
end

function MockLoadoutData.ServerUnequipSkillCard(unitId, slotIndex)
	local ok, result = pcall(function()
		return BattleEvents.RequestUnequipSkillCard:InvokeServer(unitId, slotIndex)
	end)
	if ok then
		print("[LoadoutData] Server unequip skill card:", unitId, slotIndex)
		return result
	end
	warn("[LoadoutData] ServerUnequipSkillCard failed:", result)
	return { ok = false, reason = "Server error" }
end

function MockLoadoutData.ServerAttachAugment(unitId, slotIndex, augSlotIndex, augmentId)
	local ok, result = pcall(function()
		return BattleEvents.RequestAttachAugment:InvokeServer(unitId, slotIndex, augSlotIndex, augmentId)
	end)
	if ok then
		print("[LoadoutData] Server attach augment:", unitId, slotIndex, augSlotIndex, augmentId)
		return result
	end
	warn("[LoadoutData] ServerAttachAugment failed:", result)
	return { ok = false, reason = "Server error" }
end

function MockLoadoutData.ServerDetachAugment(unitId, slotIndex, augSlotIndex)
	local ok, result = pcall(function()
		return BattleEvents.RequestDetachAugment:InvokeServer(unitId, slotIndex, augSlotIndex)
	end)
	if ok then
		print("[LoadoutData] Server detach augment:", unitId, slotIndex, augSlotIndex)
		return result
	end
	warn("[LoadoutData] ServerDetachAugment failed:", result)
	return { ok = false, reason = "Server error" }
end

function MockLoadoutData.ServerSelectDoctrineSkill(unitId, skillId)
	local ok, result = pcall(function()
		return BattleEvents.RequestDoctrineSkillSelect:InvokeServer(unitId, skillId)
	end)
	if ok then
		print("[LoadoutData] Server select doctrine skill:", unitId, skillId)
		return result
	end
	warn("[LoadoutData] ServerSelectDoctrineSkill failed:", result)
	return { ok = false, reason = "Server error" }
end

return MockLoadoutData
