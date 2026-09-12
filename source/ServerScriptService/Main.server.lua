-- CTRBLXAI | Slice 3 — "Skills and Real Combat"
--
-- Player-controlled units wait for client input.
-- Enemy units use AI.
--
-- Player input flow:
--   1. Server sends PlayerTurnPrompt with available actions
--   2. Client shows Skill Cards + Move highlights + Attack option
--   3. Player clicks → client fires PlayerCommand
--   4. Server validates and commits
--   5. If AP remains, send another prompt. If AP=0, turn ends.

local ServerScriptService = game:GetService("ServerScriptService")
local Players             = game:GetService("Players")
local Game = ServerScriptService:WaitForChild("Game")

local UnitSchema              = require(Game:WaitForChild("UnitSchema"))
local BattleCoordinator       = require(Game:WaitForChild("BattleCoordinator"))
local CommandService          = require(Game:WaitForChild("CommandService"))
local TargetingService        = require(Game:WaitForChild("TargetingService"))
local BattleVisualBroadcaster = require(Game:WaitForChild("BattleVisualBroadcaster"))
local StatusService           = require(Game:WaitForChild("StatusService"))
local CombatResolver          = require(Game:WaitForChild("CombatResolver"))
local ItemGenerator           = require(Game:WaitForChild("ItemGenerator"))
local InventoryService        = require(Game:WaitForChild("InventoryService"))
local EquipmentService        = require(Game:WaitForChild("EquipmentService"))
local PersistentStateService  = require(Game:WaitForChild("PersistentStateService"))
local SaveService             = require(Game:WaitForChild("SaveService"))
local RewardService           = require(Game:WaitForChild("RewardService"))
local DisplacementService     = require(Game:WaitForChild("DisplacementService"))
local TileEffectService       = require(Game:WaitForChild("TileEffectService"))
local RacePassiveService      = require(Game:WaitForChild("RacePassiveService"))
local ArmorPassiveService     = require(Game:WaitForChild("ArmorPassiveService"))
local AugmentEffectService    = require(Game:WaitForChild("AugmentEffectService"))
local AIService               = require(Game:WaitForChild("AIService"))


local WeaponData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("WeaponData")
)
local RaceData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("RaceData")
)
local DoctrineData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("DoctrineData")
)
local SkillData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("SkillData")
)

local BonusData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("BonusData")
)
local ArmorData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("ArmorData")
)

local AugmentData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("AugmentData")
)

local GameConstants = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Shared")
		:WaitForChild("GameConstants")
)

local BattleEvents = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Remotes")
		:WaitForChild("BattleEvents")
)

--------------------------------------------------
-- TILE OCCUPANCY HELPERS
--------------------------------------------------

local mapFolder = workspace:WaitForChild("TemplateViewerMap")

local BATTLE_OFFSET_X = 11
local BATTLE_OFFSET_Y = 6

local function findTilePart(x, y)
	local templateX = x + BATTLE_OFFSET_X
	local templateY = y + BATTLE_OFFSET_Y
	for _, child in ipairs(mapFolder:GetChildren()) do
		if child:GetAttribute("X") == templateX and child:GetAttribute("Y") == templateY then
			return child
		end
	end
	return nil
end

local function setTileOccupant(x, y, name, category, impact)
	local tile = findTilePart(x, y)
	if not tile then return end
	tile:SetAttribute("ObjectName", name)
	tile:SetAttribute("ObjectCategory", category)
	tile:SetAttribute("ObjectPassabilityImpact", impact)
end

local function clearTileOccupant(x, y)
	setTileOccupant(x, y, "None", "None", "None")
end

--------------------------------------------------
-- MAP SETUP
--------------------------------------------------

local MAP_WIDTH  = 8
local MAP_HEIGHT = 8

CommandService.SetMapDimensions(MAP_WIDTH, MAP_HEIGHT)
DisplacementService.SetMapDimensions(MAP_WIDTH, MAP_HEIGHT)

-- TileEffectService init
TileEffectService.Init(MAP_WIDTH, MAP_HEIGHT)
TileEffectService.SetStatusService(StatusService)
TileEffectService.SetBroadcaster(BattleVisualBroadcaster)
BattleCoordinator.SetTileEffectService(TileEffectService)
CommandService.SetTileEffectService(TileEffectService)

-- AIService dependency injection
AIService.SetDependencies({
	TargetingService  = TargetingService,
	CommandService    = CommandService,
	CombatResolver    = CombatResolver,
	StatusService     = StatusService,
	UnitSchema        = UnitSchema,
	TileEffectService = TileEffectService,
})

--------------------------------------------------
-- SKILL REGISTRATION
--------------------------------------------------

for key, skillDef in pairs(GameConstants.SKILLS) do
	CommandService.RegisterSkill(skillDef)
	-- Legacy alias support: if this entry was iterated under an alias key
	-- (e.g. "skill_power_strike" → same table as "SKL-POWER-STRIKE"),
	-- RegisterSkill only stores under skillDef.id. Also store under the alias.
	if key ~= skillDef.id then
		CommandService.RegisterSkillAlias(key, skillDef)
	end
end

--------------------------------------------------
-- UNIT DEFINITIONS
-- Player units have controller = "Player" (waits for input)
-- Enemy units have controller = "AI"
--
-- Slice 4A: Units now get equipment via ItemGenerator + EquipmentService.
-- Player ID for inventory ownership:
--------------------------------------------------

local PLAYER_ID = "player_1"
InventoryService.InitPlayer(PLAYER_ID)

-- Attempt to load saved state (Slice 4C)
local loadedSave, loadErr = SaveService.Load(PLAYER_ID)
local hasSave = false
local savedEquipMap = {} -- unitId -> { MainHand = instanceId, OffHand = instanceId }
local savedRaceMap = {}  -- unitId -> { raceId, perkIds, drawbackIds }
local savedDoctrineMap = {}  -- unitId -> doctrineId
local savedDoctrineSkillMap = {} -- unitId -> selectedDoctrineSkill
local savedSkillLoadoutMap = {} -- unitId -> skillLoadout table
local savedCardInventory = {} -- { skillCards = {id=qty}, augmentCards = {id=qty} }
local savedStatAllocation = {} -- unitId -> { STR = N, AGI = N, ... }
local savedRecords = {} -- unitId -> { battlesParticipated = N, ... }
local savedConsumableSlots = {} -- unitId -> consumableSlots table
if loadedSave then
	hasSave = true
	print("[Main] Save loaded — restoring state")
	-- Restore roster persistent state
	PersistentStateService.ImportState(PLAYER_ID, loadedSave.roster or {})
	-- Restore inventory
	InventoryService.ImportInventory(PLAYER_ID, loadedSave.inventory or {})
	-- Extract saved equipment assignments
	for unitId, unitData in pairs(loadedSave.roster or {}) do
		if unitData.equipSlots then
			savedEquipMap[unitId] = unitData.equipSlots
		end
		-- Extract saved race/trait data (Slice 4F)
		if unitData.raceId then
			savedRaceMap[unitId] = {
				raceId = unitData.raceId,
				perkIds = unitData.perkIds or {},
				drawbackIds = unitData.drawbackIds or {},
			}
		end
		-- Extract saved doctrine
		if unitData.doctrineId and unitData.doctrineId ~= "none" then
			savedDoctrineMap[unitId] = unitData.doctrineId
		end
		if unitData.selectedDoctrineSkill then
			savedDoctrineSkillMap[unitId] = unitData.selectedDoctrineSkill
		end
		if unitData.skillLoadout then
			savedSkillLoadoutMap[unitId] = unitData.skillLoadout
		end
		if unitData.statAllocation then
			savedStatAllocation[unitId] = unitData.statAllocation
		end
		if unitData.records then
			savedRecords[unitId] = unitData.records
		end
		if unitData.consumableSlots then
			savedConsumableSlots[unitId] = unitData.consumableSlots
		end
	end
elseif loadErr then
	warn("[Main] Load failed: " .. loadErr .. " — starting fresh (retaining runtime state)")
else
	print("[Main] No save found — new session")
end

-- Helper: generate a weapon, add to inventory, equip on unit
local function equipGeneratedWeapon(unit, archetypeId, itemLevel, rarity, seed)
	-- If save was loaded, items are already in inventory — equip from there
	-- Priority: use saved slot assignment (instanceId), fall back to archetype match
	if hasSave then
		local slotMap = savedEquipMap[unit.id]
		if slotMap and slotMap.MainHand then
			local item = InventoryService.GetItem(PLAYER_ID, slotMap.MainHand)
			if item then
				EquipmentService.Equip(unit, item, "MainHand")
				print(string.format("[Main] Restored %s MainHand from save: %s", unit.name, slotMap.MainHand))
				-- Restore OffHand from save (if present)
				if slotMap and slotMap.OffHand then
					local offItem = InventoryService.GetItem(PLAYER_ID, slotMap.OffHand)
					if offItem then
						EquipmentService.Equip(unit, offItem, "OffHand")
						print("[Main] Restored " .. unit.name .. " OffHand from save: " .. slotMap.OffHand)
					end
				end
				return
			end
			warn(string.format("[Main] Saved MainHand item %s not found in inventory for %s — falling back to archetype", slotMap.MainHand, unit.name))
		end
		-- Fallback: match by archetype (legacy saves without equipSlots)
		local allItems = InventoryService.GetAllItems(PLAYER_ID)
		for _, item in ipairs(allItems) do
			if item.baseArchetypeId == archetypeId then
				EquipmentService.Equip(unit, item, "MainHand")
				return
			end
		end
		warn("[Main] No saved item found for archetype: " .. archetypeId)
	end
	local item = ItemGenerator.Generate({
		baseArchetypeId = archetypeId,
		itemLevel = itemLevel,
		rarity = rarity,
		seed = seed,
		sourceType = "Debug",
	})
	if not item then
		warn("[Main] Failed to generate weapon: " .. archetypeId)
		return
	end
	InventoryService.AddItem(PLAYER_ID, item)
	EquipmentService.Equip(unit, item, "MainHand")
end

local hero = UnitSchema.Create({
	id           = "unit_hero",
	name         = "Hero",
	level        = 25,
	raceId       = "RACE-HUMAN",
	side         = "Player",
	controller   = "Player",
	tileX        = 5,
	tileY        = 5,
	doctrineId   = "DOC-BERSERKER",
	skillIds     = { "skill_power_strike", "skill_sweeping_cut" },
})
equipGeneratedWeapon(hero, "WPN-SWORD", 5, "Uncommon", 1001)

-- Starter off-hand shield (inventory only, not equipped)
if not hasSave then
	local starterShield = ItemGenerator.Generate({
		baseArchetypeId = "OFF-SHIELD",
		itemLevel = 5,
		rarity = "Common",
		seed = 1004,
		sourceType = "Debug",
	})
	if starterShield then
		InventoryService.AddItem(PLAYER_ID, starterShield)
		print("[Main] Added starter Shield to inventory: " .. starterShield.instanceId)
	else
		warn("[Main] Failed to generate starter Shield (OFF-SHIELD)")
	end
end

-- Starter armor items (inventory only, not equipped) — Slice 4G
-- ItemGenerator doesn't handle armor yet (4G.5), so create catalog instances directly.
if not hasSave then
	local STARTER_ARMOR = {
		{ id = "HD-001", slot = "Head",      seed = 3001 },
		{ id = "BD-001", slot = "Body",      seed = 3002 },
		{ id = "GL-001", slot = "Gloves",    seed = 3003 },
		{ id = "FT-001", slot = "Feet",      seed = 3004 },
		{ id = "AC-001", slot = "Accessory", seed = 3005 },
	}
	for _, def in ipairs(STARTER_ARMOR) do
		local aArch = ArmorData.GetByArchetypeId(def.id)
		if aArch then
			local armorInstance = {
				instanceId = "armor_" .. def.seed .. "_1",
				baseArchetypeId = def.id,
				itemLevel = 5,
				rarityId = "Common",
				bonusLines = {},
				bonusPassiveIds = {},
				generatorVersion = 1,
				sourceType = "Starter",
			}
			InventoryService.AddItem(PLAYER_ID, armorInstance)
			print(string.format("[Main] Added starter %s (%s) to inventory: %s", aArch.name, def.slot, armorInstance.instanceId))
		else
			warn("[Main] Starter armor archetype not found: " .. def.id)
		end
	end
end

-- Starter cards moved after cardInventory declaration (see block near line 1060)

local mage = UnitSchema.Create({
	id           = "unit_mage",
	name         = "Mage",
	level        = 25,
	raceId       = "RACE-ELF",
	side         = "Player",
	controller   = "Player",
	tileX        = 1,
	tileY        = 4,
	doctrineId   = "DOC-ARCANIST",
	skillIds     = { "skill_fire_bolt", "skill_healing_light" },
})
equipGeneratedWeapon(mage, "WPN-WAND", 5, "Uncommon", 1002)

local ranger = UnitSchema.Create({
	id           = "unit_ranger",
	name         = "Ranger",
	level        = 25,
	raceId       = "RACE-SHADOW",
	side         = "Player",
	controller   = "Player",
	tileX        = 8,
	tileY        = 5,
	doctrineId   = "DOC-RANGER",
	skillIds     = { "skill_crippling_shot", "skill_venom_strike" },
})
equipGeneratedWeapon(ranger, "WPN-CROSSBOW", 5, "Uncommon", 1003)

-- TEST OVERRIDE: Ranger's Venom Strike uses weapon range instead of fixed 1
do
	local baseVenom = GameConstants.SKILLS["skill_venom_strike"]
	local rangerVenom = {}
	for k, v in pairs(baseVenom) do rangerVenom[k] = v end
	rangerVenom.id    = "skill_venom_strike_ranged"
	rangerVenom.range = ranger.weaponMaxRange or 1
	CommandService.RegisterSkill(rangerVenom)
	-- Swap in ranger's skill list
	for i, sid in ipairs(ranger.skillIds) do
		if sid == "skill_venom_strike" then ranger.skillIds[i] = "skill_venom_strike_ranged" end
	end
end

--------------------------------------------------
-- RESTORE ARMOR SLOTS FROM SAVE (Slice 4G)
-- After all weapons are equipped, restore armor slots
-- from savedEquipMap for each player unit.
--------------------------------------------------
if hasSave then
	local ARMOR_SLOT_NAMES = { "Head", "Body", "Gloves", "Feet", "Accessory" }
	for _, pUnit in ipairs({ hero, mage, ranger }) do
		local slotMap = savedEquipMap[pUnit.id]
		if slotMap then
			for _, armorSlot in ipairs(ARMOR_SLOT_NAMES) do
				local savedId = slotMap[armorSlot]
				if savedId then
					local armorItem = InventoryService.GetItem(PLAYER_ID, savedId)
					if armorItem then
						EquipmentService.Equip(pUnit, armorItem, armorSlot)
						print(string.format("[Main] Restored %s %s from save: %s", pUnit.name, armorSlot, savedId))
					else
						warn(string.format("[Main] Saved %s item %s not found for %s", armorSlot, savedId, pUnit.name))
					end
				end
			end
		end
	end
end

local grunt = UnitSchema.Create({
	id           = "unit_grunt",
	name         = "Grunt",
	side         = "Enemy",
	controller   = "AI",
	aiRole       = "Basic",
	tileX        = 5,
	tileY        = 7,
	stats        = { STR = 14, AGI = 10, INT = 6, VIT = 14, DEX = 8, LUK = 6 },
	skillIds     = { "skill_venom_strike", "skill_crippling_shot" },
	startingRt   = 420,
})
equipGeneratedWeapon(grunt, "WPN-SPEAR", 5, "Common", 2001)

local pyro = UnitSchema.Create({
	id           = "unit_pyro",
	name         = "Pyro",
	side         = "Enemy",
	controller   = "AI",
	aiRole       = "Elite",
	tileX        = 6,
	tileY        = 7,
	stats        = { STR = 8, AGI = 12, INT = 16, VIT = 10, DEX = 10, LUK = 8 },
	skillIds     = { "skill_fire_bolt", "skill_power_strike" },
	startingRt   = 420,
})
equipGeneratedWeapon(pyro, "WPN-STAFF", 5, "Common", 2002)

local shaman = UnitSchema.Create({
	id           = "unit_shaman",
	name         = "Shaman",
	side         = "Enemy",
	controller   = "AI",
	aiRole       = "Elite",
	tileX        = 4,
	tileY        = 8,
	stats        = { STR = 6, AGI = 8, INT = 18, VIT = 14, DEX = 12, LUK = 10 },
	skillIds     = { "skill_healing_light", "skill_crippling_shot" },
	startingRt   = 420,
})
equipGeneratedWeapon(shaman, "WPN-WAND", 5, "Common", 2003)

local allUnitsList = { hero, mage, ranger, grunt, pyro, shaman }
for _, u in ipairs(allUnitsList) do
	setTileOccupant(u.tileX, u.tileY, u.name, "Unit (" .. u.side .. ")", "Blocking")
end

-- Apply permanent Flight status to units with the Flying race tag
-- DB: "Flying: Grants permanent Flight using complete Manual Flight benefits and drawbacks"
do
	local RaceData = require(game:GetService("ReplicatedStorage"):WaitForChild("Content"):WaitForChild("RaceData"))
	for _, u in ipairs(allUnitsList) do
		if u.raceId then
			local raceEntry = RaceData[u.raceId]
			if raceEntry and raceEntry.tags then
				for _, tag in ipairs(raceEntry.tags) do
					if tag == "Flying" then
						StatusService.ApplyStatus(u, "Flight", "RaceTag")
						print(string.format("[Main] %s has Flying tag — Flight status applied", u.name))
						break
					end
				end
			end
		end
	end
end

-- Register persistent state for player units (Slice 4B)
PersistentStateService.InitPlayer(PLAYER_ID)
for _, u in ipairs(allUnitsList) do
	if u.side == "Player" then
		local ps = PersistentStateService.GetUnitState(PLAYER_ID, u.id)
		if not ps then
			-- Brand new unit — register at full
			PersistentStateService.RegisterNewUnit(PLAYER_ID, u.id, u.maxHp, u.maxMp)
		else
			-- Loaded from save — apply persistent HP/MP to runtime unit
			u.currentHp = math.min(ps.currentHp, u.maxHp)
			u.currentMp = math.min(ps.currentMp, u.maxMp)
			if ps.isKO then
				u.isAlive = false
				u.currentHp = 0
			end
			print(string.format("[Main] Loaded persistent state for %s: HP:%d/%d MP:%d/%d KO:%s",
				u.name, u.currentHp, u.maxHp, u.currentMp, u.maxMp, tostring(ps.isKO)))
		end
	end
end

-- Restore or assign doctrines for player units
for _, u in ipairs(allUnitsList) do
	if u.side == "Player" then
		local savedDoc = savedDoctrineMap[u.id]
		if savedDoc then
			u.doctrineId = savedDoc
		end
		-- Assign default doctrine if none set
		if not u.doctrineId then
			u.doctrineId = "DOC-BERSERKER"  -- placeholder default
		end
		-- Restore selected doctrine skill from save (Slice 4H)
		local savedSkill = savedDoctrineSkillMap[u.id]
		if savedSkill then
			u.selectedDoctrineSkill = savedSkill
		end
		-- Auto-select first skill choice if none set
		if not u.selectedDoctrineSkill then
			local doc = DoctrineData[u.doctrineId]
			if doc and doc.skillChoices and #doc.skillChoices > 0 then
				u.selectedDoctrineSkill = doc.skillChoices[1]
			end
		end
		print(string.format("[Main] %s doctrine: %s (skill: %s)",
			u.name, u.doctrineId, tostring(u.selectedDoctrineSkill)))

		-- Restore skill loadout from save (Slice 4I)
		local savedLoadout = savedSkillLoadoutMap[u.id]
		if savedLoadout then
			u.skillLoadout = savedLoadout
		end
		-- Initialize empty loadout if none exists
		if not u.skillLoadout then
			u.skillLoadout = { slot2 = nil, slot3 = nil, slot4 = nil }
		end

		-- Restore stat allocation from save (Slice 4J)
		local savedAlloc = savedStatAllocation[u.id]
		if savedAlloc then
			u.statAllocation = savedAlloc
			-- Apply allocation to baseStats
			for stat, pts in pairs(savedAlloc) do
				if u.baseStats[stat] then
					u.baseStats[stat] = u.baseStats[stat] + pts
				end
			end
			EquipmentService.RebuildUnitStats(u)
		end

		-- Restore or initialize unit records (Slice 4K)
		local savedRec = savedRecords[u.id]
		if savedRec then
			u.records = savedRec
		else
			u.records = {
				battlesParticipated = 0,
				victoriesParticipated = 0,
				enemiesDefeated = 0,
				totalDamageDealt = 0,
				totalHealingDone = 0,
				timesKO = 0,
			}
		end

		-- Initialize consumable slots (Slice 4G.4)
		-- 6 slots: 1-3 open, 4-6 locked (unlock via progression)
		local savedCons = savedConsumableSlots[u.id]
		if savedCons then
			u.consumableSlots = savedCons
		end
		if not u.consumableSlots then
			u.consumableSlots = {}
		end
		u.consumableSlotCount = 3  -- open slots (4-6 locked)
		u.maxConsumableSlots = 6

		-- Build skillIds from loadout (doctrine skill + equipped skill cards)
		u.skillIds = {}
		if u.selectedDoctrineSkill then
			table.insert(u.skillIds, u.selectedDoctrineSkill)
		end
		for _, slotKey in ipairs({"slot2", "slot3", "slot4"}) do
			local slotData = u.skillLoadout[slotKey]
			if slotData and slotData.skillId then
				table.insert(u.skillIds, slotData.skillId)
			end
		end
		print(string.format("[Main] %s skills: %s", u.name, table.concat(u.skillIds, ", ")))
	end
end

print("====================================")
print("CTRBLXAI — Slice 3: Skills and Real Combat")
print("====================================")
for _, u in ipairs(allUnitsList) do
	print(string.format("  %s", UnitSchema.Describe(u)))
end
print("====================================")

--------------------------------------------------
-- BATTLE STATE
--------------------------------------------------

--------------------------------------------------
-- PLAYER UNIT LOOKUP (needed by doSave and management handlers)
--------------------------------------------------
local playerUnits = {}
for _, u in ipairs(allUnitsList) do
	if u.side == "Player" then playerUnits[u.id] = u end
end

--------------------------------------------------
-- REUSABLE SAVE HELPER
--------------------------------------------------

local function doSave()
	local rosterState = PersistentStateService.ExportState(PLAYER_ID)
	local inventoryItems = InventoryService.ExportInventory(PLAYER_ID)
	-- Enrich roster with equipment slot assignments (instanceIds only)
	for unitId, unit in pairs(playerUnits) do
		if rosterState[unitId] and unit.equipmentSlots then
			local slots = {}
			for slot, item in pairs(unit.equipmentSlots) do
				slots[slot] = item.instanceId
			end
			rosterState[unitId].equipSlots = slots
		end
		-- Enrich with race and trait data (Slice 4F)
		if rosterState[unitId] and unit.raceId then
			rosterState[unitId].raceId = unit.raceId
			rosterState[unitId].perkIds = unit.perkIds or {}
			rosterState[unitId].drawbackIds = unit.drawbackIds or {}
		end
		-- Enrich with doctrine data (Slice 4H)
		if rosterState[unitId] then
			rosterState[unitId].doctrineId = unit.doctrineId or nil
			rosterState[unitId].selectedDoctrineSkill = unit.selectedDoctrineSkill or nil
			rosterState[unitId].skillLoadout = unit.skillLoadout or nil
			rosterState[unitId].statAllocation = unit.statAllocation or nil
			rosterState[unitId].records = unit.records or nil
			rosterState[unitId].consumableSlots = unit.consumableSlots or nil
		end
	end
	-- Diagnostic: log equipment slot assignments being saved
	for unitId, unitState in pairs(rosterState) do
		if unitState.equipSlots then
			local parts = {}
			for slot, iid in pairs(unitState.equipSlots) do
				table.insert(parts, slot .. ":" .. tostring(iid))
			end
			print(string.format("[Save] Equipment: %s=%s", unitId, table.concat(parts, ",")))
		end
	end
	local progression = {}
	local ok, err = SaveService.Save(PLAYER_ID, rosterState, inventoryItems, progression)
	if ok then
		print("[Save] Successful")
	else
		warn("[Save] FAILED: " .. (err or "unknown"))
	end
	return ok, err
end

--------------------------------------------------
-- MANAGEMENT REMOTEFUNCTIONS (Slice 4D)
-- Active throughout the session (pre-battle, post-battle, hub)
--------------------------------------------------


BattleEvents.GetRosterData.OnServerInvoke = function(player)
	local roster = {}
	for unitId, unit in pairs(playerUnits) do
		local pState = PersistentStateService.GetUnitState(PLAYER_ID, unitId)
		local loadout = EquipmentService.GetLoadout(unit)
		local mainItem = loadout and loadout.MainHand
		local offHandItem = loadout and loadout.OffHand
		local headItem = loadout and loadout.Head
		local bodyItem = loadout and loadout.Body
		local glovesItem = loadout and loadout.Gloves
		local feetItem = loadout and loadout.Feet
		local accessoryItem = loadout and loadout.Accessory
		roster[unitId] = {
			name = unit.name,
			level = unit.level or 1,
			currentHp = pState and pState.currentHp or unit.currentHp,
			maxHp = pState and pState.maxHp or unit.maxHp,
			currentMp = pState and pState.currentMp or unit.currentMp,
			maxMp = pState and pState.maxMp or unit.maxMp,
			isKO = pState and pState.isKO or false,
			equippedWeapon = mainItem and mainItem.instanceId or "none",
			equippedWeaponName = mainItem and (WeaponData.GetByArchetypeId(mainItem.baseArchetypeId) or {}).name or "none",
			equippedOffHandName = offHandItem and (WeaponData.GetByArchetypeId(offHandItem.baseArchetypeId) or {}).name or "none",
			doctrineId = unit.doctrineId or "none",
			-- Doctrine details (Slice 4H)
			doctrineName = unit.doctrineId and DoctrineData[unit.doctrineId] and DoctrineData[unit.doctrineId].name or "none",
			doctrinePassive = unit.doctrineId and DoctrineData[unit.doctrineId] and DoctrineData[unit.doctrineId].passiveName or "none",
			doctrinePassiveEffect = unit.doctrineId and DoctrineData[unit.doctrineId] and DoctrineData[unit.doctrineId].passiveEffect or "none",
			selectedDoctrineSkill = unit.selectedDoctrineSkill or "none",
			-- Race identity (Slice 4F)
			raceId = unit.raceId or "none",
			-- Armor equipment (Slice 4G)
			equippedHead = headItem and (ArmorData.GetByArchetypeId(headItem.baseArchetypeId) or {}).name or "none",
			equippedBody = bodyItem and (ArmorData.GetByArchetypeId(bodyItem.baseArchetypeId) or {}).name or "none",
			equippedGloves = glovesItem and (ArmorData.GetByArchetypeId(glovesItem.baseArchetypeId) or {}).name or "none",
			equippedFeet = feetItem and (ArmorData.GetByArchetypeId(feetItem.baseArchetypeId) or {}).name or "none",
			equippedAccessory = accessoryItem and (ArmorData.GetByArchetypeId(accessoryItem.baseArchetypeId) or {}).name or "none",
			raceName = unit.raceId and RaceData.GetRace(unit.raceId) and RaceData.GetRace(unit.raceId).name or "none",
			racePassive = unit.raceId and RaceData.GetRace(unit.raceId) and RaceData.GetRace(unit.raceId).passiveName or "none",
			perkIds = unit.perkIds or {},
			drawbackIds = unit.drawbackIds or {},
			-- Unit records (Slice 4K)
			records = unit.records or {},
			-- Consumable slots (Slice 4G.4)
			consumableSlots = (function()
				local slots = {}
				for idx = 1, unit.maxConsumableSlots or 6 do
					local slotData = unit.consumableSlots and unit.consumableSlots[idx]
					if slotData then
						local consDef = ConsumableData.GetById(slotData.consumableId)
						slots[idx] = { consumableId = slotData.consumableId, name = consDef and consDef.name or "Unknown", currentCharges = slotData.currentCharges, maxCharges = slotData.maxCharges, locked = (idx > (unit.consumableSlotCount or 3)) }
					else
						slots[idx] = { empty = true, locked = (idx > (unit.consumableSlotCount or 3)) }
					end
				end
				return slots
			end)(),
		}
	end
	-- Diagnostic: log roster summary
	local rosterParts = {}
	for unitId, rd in pairs(roster) do
		table.insert(rosterParts, string.format("%s(%s,Wpn:%s,Off:%s)", rd.name, rd.raceName, rd.equippedWeaponName, rd.equippedOffHandName))
	end
	local unitCount = #rosterParts
	print(string.format("[Roster] Returned %d units: %s", unitCount, table.concat(rosterParts, ", ")))

	return roster
end

--------------------------------------------------
-- BONUS DISPLAY RESOLVER
-- Converts raw bonusLines/bonusPassiveIds into UI-friendly format.
-- bonusStats: { STR = 1, VIT = 2 }  (scaled flat at item level)
-- bonusPassives: { { name = "Brutal", icon = "✦", desc = "" } }
--------------------------------------------------

local BONUS_DISPLAY_KEY = {
	STR = "STR", AGI = "AGI", INT = "INT", VIT = "VIT", DEX = "DEX", LUK = "LUK",
	damage = "Attack", defense = "Defense", rtDelay = "RT Delay", hp = "HP", mp = "MP", wt = "WT",
	precision = "Precision", evasiveness = "Evasiveness", fortune = "Fortune", skillPotency = "Skill Potency",
	healingOutput = "Healing", debuffResist = "Debuff Resist", rtDelayResist = "RT Delay Resist",
}

local function resolveItemBonuses(item)
	local stats = {}
	local passives = {}

	for _, line in ipairs(item.bonusLines or {}) do
		local attr = BonusData.NumericalAttributes[line.id]
		if attr then
			local key = BONUS_DISPLAY_KEY[attr.stat] or attr.family
			local value = 0

			if attr.operation == "PrimaryStat" or attr.operation == "BaseItemStat" then
				local scale = WeaponData.GetScale(item.itemLevel or 1)
				value = math.round((attr.l99Flat or 0) * scale)
			elseif attr.operation == "WeightReduce" then
				local scale = WeaponData.GetScale(item.itemLevel or 1)
				value = -math.round((attr.l99Flat or 0) * scale)
			elseif attr.operation == "Derived" then
				-- fixedValue is additive pct like 0.03 → display as 3
				value = math.round((attr.fixedValue or 0) * 100)
			elseif attr.operation == "DerivedMultiplier" then
				-- fixedValue is multiplier like 1.08 → +8, or 0.95 → -5
				value = math.round(((attr.fixedValue or 1) - 1) * 100)
			else
				-- Unknown operation — try l99Flat
				local scale = WeaponData.GetScale(item.itemLevel or 1)
				value = math.round((attr.l99Flat or 0) * scale)
			end

			if value ~= 0 then
				stats[key] = (stats[key] or 0) + value
			end
		end
	end

	for _, passiveId in ipairs(item.bonusPassiveIds or {}) do
		local passive = BonusData.BonusPassives[passiveId]
		if passive then
			table.insert(passives, { name = passive.name or passiveId, icon = "\xe2\x97\x86", desc = passive.desc or "" })
		end
	end

	-- DIAG: log resolved bonus stats
	local dbgParts = {}
	for k, v in pairs(stats) do table.insert(dbgParts, k .. "=" .. tostring(v)) end
	if #dbgParts > 0 then
		print("[DIAG-Resolve] " .. (item.baseArchetypeId or "?") .. " L" .. (item.itemLevel or 0) .. " " .. (item.rarityId or "?") .. ": " .. table.concat(dbgParts, ", ") .. " (" .. #(item.bonusLines or {}) .. " lines, " .. #(item.bonusPassiveIds or {}) .. " passives)")
	end

	return stats, passives
end

BattleEvents.GetInventoryData.OnServerInvoke = function(player)
	local items = InventoryService.GetAllItems(PLAYER_ID)
	local result = {}
	-- Build reverse lookup: instanceId -> unitId that has it equipped
	local equippedByMap = {}
	for unitId, unit in pairs(playerUnits) do
		if unit.equipmentSlots then
			for slot, eqItem in pairs(unit.equipmentSlots) do
				equippedByMap[eqItem.instanceId] = { unitId = unitId, slot = slot }
			end
		end
	end
	for _, item in ipairs(items) do
		local wArch = WeaponData.GetByArchetypeId(item.baseArchetypeId)
		local aArch = not wArch and ArmorData.GetByArchetypeId(item.baseArchetypeId) or nil
		local entry
		if wArch then
			local profile = WeaponData.GetScaledProfile(item.baseArchetypeId, item.itemLevel)
			entry = {
				instanceId = item.instanceId,
				name = item.displayName or wArch.name,
				category = wArch.category,
				handClass = wArch.handClass or "1H",
				slot = (wArch.category == "OffHand") and "OffHand" or "MainHand",
				itemLevel = item.itemLevel,
				rarity = item.rarityId,
				damage = profile and profile.damage or 0,
				wt = profile and profile.wt or 0,
				defense = profile and profile.defense or 0,
				rtDelay = profile and profile.rtDelay or 0,
				minRange = profile and profile.minRange or 1,
				maxRange = profile and profile.maxRange or 1,
				isWeapon = wArch.category == "Weapon",
				isArmor = false,
				icon = wArch.icon or nil,
				flavor = wArch.flavor or nil,
				nativePassiveId = wArch.nativePassiveId or nil,
				nativePassiveDesc = WeaponData.GetPassiveDesc(wArch.nativePassiveId) or nil,
				projectileType = wArch.projectileType or nil,
				element = WeaponData.GetElement(item.baseArchetypeId) or nil,
			}
		elseif aArch then
			local scaled = ArmorData.GetScaledProfile(item.baseArchetypeId, item.itemLevel)
			entry = {
				instanceId = item.instanceId,
				name = item.displayName or aArch.name,
				category = "Armor",
				slot = aArch.slot,
				itemLevel = item.itemLevel,
				rarity = item.rarityId,
				defense = scaled and scaled.defense or 0,
				wt = scaled and scaled.wt or 0,
				hp = scaled and scaled.hp or 0,
				mp = scaled and scaled.mp or 0,
				damage = 0,
				rtDelay = 0,
				minRange = 0,
				maxRange = 0,
				isWeapon = false,
				isArmor = true,
				icon = aArch.icon or nil,
				flavor = aArch.flavor or nil,
				passiveName = aArch.passiveName or nil,
				passiveDesc = aArch.passiveDesc or nil,
				actionOwnership = aArch.actionOwnership or nil,
			}
		else
			entry = {
				instanceId = item.instanceId,
				name = "Unknown",
				category = "Unknown",
				itemLevel = item.itemLevel,
				rarity = item.rarityId,
			}
		end
		-- Common fields
		entry.isNew = item.isNew or false
		entry.bonusCount = #(item.bonusLines or {})
		entry.passiveCount = #(item.bonusPassiveIds or {})
		entry.equippedBy = equippedByMap[item.instanceId] and equippedByMap[item.instanceId].unitId or nil
		entry.equippedSlot = equippedByMap[item.instanceId] and equippedByMap[item.instanceId].slot or nil
		entry.bonusStats, entry.bonusPassives = resolveItemBonuses(item)
		table.insert(result, entry)
	end
	-- Diagnostic: log inventory summary
	local equippedCount = 0
	for _, entry in ipairs(result) do
		if entry.equippedBy then
			equippedCount = equippedCount + 1
		end
	end
	print(string.format("[Inventory] Returned %d items, %d equipped", #result, equippedCount))
	for _, entry in ipairs(result) do
		if entry.equippedBy then
			print(string.format("[Inventory] %s [%s] → %s [%s]", entry.name, entry.instanceId, entry.equippedBy, entry.equippedSlot))
		end
	end

	return result
end

BattleEvents.RequestEquip.OnServerInvoke = function(player, unitId, instanceId)
	local unit = playerUnits[unitId]
	if not unit then
		warn(string.format("[Management] Equip FAILED: %s + %s — Unknown unit: %s", tostring(unitId), tostring(instanceId), tostring(unitId)))
		return { ok = false, reason = "Unknown unit: " .. tostring(unitId) }
	end
	local item = InventoryService.GetItem(PLAYER_ID, instanceId)
	if not item then
		warn(string.format("[Management] Equip FAILED: %s + %s — Item not found: %s", tostring(unitId), tostring(instanceId), tostring(instanceId)))
		return { ok = false, reason = "Item not found: " .. tostring(instanceId) }
	end
	if not InventoryService.OwnsItem(PLAYER_ID, instanceId) then
		warn(string.format("[Management] Equip FAILED: %s + %s — Not owned", tostring(unitId), tostring(instanceId)))
		return { ok = false, reason = "Not owned" }
	end
	-- Resolve archetype from WeaponData or ArmorData
	local archetype = WeaponData.GetByArchetypeId(item.baseArchetypeId)
	local isArmor = false
	if not archetype then
		archetype = ArmorData.GetByArchetypeId(item.baseArchetypeId)
		isArmor = true
	end
	if not archetype then
		warn(string.format("[Management] Equip FAILED: %s + %s — Unknown archetype", tostring(unitId), tostring(instanceId)))
		return { ok = false, reason = "Unknown archetype" }
	end
	-- Determine slot: armor uses archetype.slot, weapons use category
	local slot = isArmor and archetype.slot or ((archetype.category == "OffHand") and "OffHand" or "MainHand")
	-- Auto-unequip from previous holder if item is equipped elsewhere
	for prevId, prevUnit in pairs(playerUnits) do
		if prevId ~= unitId and prevUnit.equipmentSlots then
			for prevSlot, prevItem in pairs(prevUnit.equipmentSlots) do
				if prevItem.instanceId == instanceId then
					EquipmentService.Unequip(prevUnit, prevSlot)
					EquipmentService.RebuildUnitStats(prevUnit)
					print(string.format("[Management] Auto-unequipped %s from %s to equip on %s", archetype.name, prevUnit.name, unit.name))
				end
			end
		end
	end
	local ok, err = EquipmentService.Equip(unit, item, slot)
	if ok then
		EquipmentService.RebuildUnitStats(unit)
		print(string.format("[Management] %s equipped %s [%s] in %s", unit.name, archetype.name, instanceId, slot))
		return { ok = true, slot = slot, name = archetype.name }
	else
		warn(string.format("[Management] Equip FAILED: %s + %s — %s", tostring(unitId), tostring(instanceId), err or "Equip failed"))
		return { ok = false, reason = err or "Equip failed" }
	end
end

BattleEvents.RequestUnequip.OnServerInvoke = function(player, unitId, slot)
	local unit = playerUnits[unitId]
	if not unit then
		warn(string.format("[Management] Unequip FAILED: %s %s — Unknown unit: %s", tostring(unitId), tostring(slot or "MainHand"), tostring(unitId)))
		return { ok = false, reason = "Unknown unit: " .. tostring(unitId) }
	end
	local ok, err = EquipmentService.Unequip(unit, slot or "MainHand")
	if ok then
		EquipmentService.RebuildUnitStats(unit)
		print(string.format("[Management] %s unequipped %s", unit.name, slot or "MainHand"))
		return { ok = true }
	else
		warn(string.format("[Management] Unequip FAILED: %s %s — %s", tostring(unitId), tostring(slot or "MainHand"), err or "Unequip failed"))
		return { ok = false, reason = err or "Unequip failed" }
	end
end

--------------------------------------------------
-- DOCTRINE MANAGEMENT (Slice 4H)
--------------------------------------------------

-- GetDoctrineChoices: returns available doctrines and their skill choices
BattleEvents.GetDoctrineChoices.OnServerInvoke = function(player)
	local result = {}
	for docId, doc in pairs(DoctrineData) do
		if type(doc) == "table" and doc.name then
			table.insert(result, {
				doctrineId = docId,
				name = doc.name,
				identity = doc.identity or "",
				statPackage = doc.statPackage or {},
				passiveName = doc.passiveName or "",
				passiveEffect = doc.passiveEffect or "",
				skillChoices = doc.skillChoices or {},
			})
		end
	end
	table.sort(result, function(a, b) return a.doctrineId < b.doctrineId end)
	print(string.format("[Doctrine] Returned %d doctrine choices", #result))
	return result
end

-- RequestDoctrineChange: assign a doctrine to a unit
BattleEvents.RequestDoctrineChange.OnServerInvoke = function(player, unitId, doctrineId)
	local unit = playerUnits[unitId]
	if not unit then
		warn(string.format("[Doctrine] Change FAILED: %s — Unknown unit", tostring(unitId)))
		return { ok = false, reason = "Unknown unit: " .. tostring(unitId) }
	end
	-- Validate doctrine exists
	local doctrine = DoctrineData[doctrineId]
	if not doctrine or type(doctrine) ~= "table" or not doctrine.name then
		warn(string.format("[Doctrine] Change FAILED: %s — Unknown doctrine: %s", tostring(unitId), tostring(doctrineId)))
		return { ok = false, reason = "Unknown doctrine: " .. tostring(doctrineId) }
	end
	local oldDoc = unit.doctrineId
	unit.doctrineId = doctrineId
	-- Clear selected doctrine skill (new doctrine has different choices)
	unit.selectedDoctrineSkill = nil
	-- Auto-select first skill choice as default
	if doctrine.skillChoices and #doctrine.skillChoices > 0 then
		unit.selectedDoctrineSkill = doctrine.skillChoices[1]
	end
	-- Rebuild stats (doctrine stat package changed)
	EquipmentService.RebuildUnitStats(unit)
	print(string.format("[Doctrine] %s doctrine changed: %s → %s (skill: %s)",
		unit.name, tostring(oldDoc), doctrineId, tostring(unit.selectedDoctrineSkill)))
	return {
		ok = true,
		doctrineName = doctrine.name,
		selectedSkill = unit.selectedDoctrineSkill,
	}
end

-- RequestDoctrineSkillSelect: pick one of the 3 skill choices
BattleEvents.RequestDoctrineSkillSelect.OnServerInvoke = function(player, unitId, skillId)
	local unit = playerUnits[unitId]
	if not unit then
		warn(string.format("[Doctrine] Skill select FAILED: %s — Unknown unit", tostring(unitId)))
		return { ok = false, reason = "Unknown unit: " .. tostring(unitId) }
	end
	if not unit.doctrineId then
		warn(string.format("[Doctrine] Skill select FAILED: %s — No doctrine equipped", tostring(unitId)))
		return { ok = false, reason = "No doctrine equipped" }
	end
	local doctrine = DoctrineData[unit.doctrineId]
	if not doctrine then
		warn(string.format("[Doctrine] Skill select FAILED: %s — Doctrine data missing", unit.doctrineId))
		return { ok = false, reason = "Doctrine data missing" }
	end
	-- Validate skillId is one of the 3 choices
	local valid = false
	for _, choice in ipairs(doctrine.skillChoices or {}) do
		if choice == skillId then
			valid = true
			break
		end
	end
	if not valid then
		warn(string.format("[Doctrine] Skill select FAILED: %s not in %s choices", tostring(skillId), unit.doctrineId))
		return { ok = false, reason = skillId .. " is not a valid choice for " .. (doctrine.name or unit.doctrineId) }
	end
	local oldSkill = unit.selectedDoctrineSkill
	unit.selectedDoctrineSkill = skillId
	print(string.format("[Doctrine] %s skill changed: %s → %s", unit.name, tostring(oldSkill), skillId))
	return { ok = true, selectedSkill = skillId }
end

--------------------------------------------------
-- SKILL CARD & AUGMENT CARD MANAGEMENT (Slice 4I)
--------------------------------------------------

-- Card inventory: { skillCards = {[skillId] = qty}, augmentCards = {[augId] = qty} }
-- Stored per-player. For now, single player.
local cardInventory = { skillCards = {}, augmentCards = {} }

-- Restore from save (progression key — future use)
-- For now, cards are granted via starter block or rewards

-- Populate starter cards when inventory is empty
-- (Card persistence not yet in save pipeline)
do
	local hasAny = false
	for _ in pairs(cardInventory.skillCards) do hasAny = true; break end
	if not hasAny then
		for _ in pairs(cardInventory.augmentCards) do hasAny = true; break end
	end
	if not hasAny then
		cardInventory.skillCards = {
			["SKL-POWER-STRIKE"] = 1, ["SKL-SWEEPING-CUT"] = 1,
			["SKL-FIRE-BOLT"] = 1, ["SKL-HEALING-LIGHT"] = 1,
			["SKL-CRIPPLING-SHOT"] = 1, ["SKL-VENOM-STRIKE"] = 1,
		}
		cardInventory.augmentCards = {
			["AUG-BLEEDING-EDGE-SUPPORT"] = 2, ["AUG-VENOMOUS-SUPPORT"] = 2,
		}
		print("[Main] Starter cards loaded (6 skill, 4 augment)")
	end
end

-- Starter consumables: equip a healing potion on Hero if no consumables saved
do
	local heroUnit = nil
	for _, u in ipairs(allUnitsList) do
		if u.id == "unit_hero" then heroUnit = u; break end
	end
	if heroUnit and (not heroUnit.consumableSlots or not heroUnit.consumableSlots[1]) then
		heroUnit.consumableSlots = heroUnit.consumableSlots or {}
		heroUnit.consumableSlots[1] = {
			consumableId = "REC-001",  -- Emergency Small Healing Potion
			currentCharges = 1,
			maxCharges = 1,
		}
		print("[Main] Starter consumable equipped: REC-001 on Hero slot 1")
	end
end

-- Helper: rebuild unit.skillIds from loadout
local function rebuildSkillIds(unit)
	unit.skillIds = {}
	if unit.selectedDoctrineSkill then
		table.insert(unit.skillIds, unit.selectedDoctrineSkill)
	end
	for _, slotKey in ipairs({"slot2", "slot3", "slot4"}) do
		local slotData = unit.skillLoadout and unit.skillLoadout[slotKey]
		if slotData and slotData.skillId then
			table.insert(unit.skillIds, slotData.skillId)
		end
	end
end

-- GetSkillLoadout: returns unit's skill slots + card inventories
BattleEvents.GetSkillLoadout.OnServerInvoke = function(player, unitId)
	local unit = playerUnits[unitId]
	if not unit then
		return { ok = false, reason = "Unknown unit" }
	end
	local loadout = unit.skillLoadout or {}
	local slots = {}
	-- Slot 1: Doctrine skill
	local docSkill = unit.selectedDoctrineSkill
	local docDef = docSkill and SkillData[docSkill]
	slots[1] = {
		slotType = "Doctrine",
		skillId = docSkill or "none",
		skillName = docDef and docDef.name or "none",
		augments = unit.doctrineAugments or {},
		locked = false,
	}
	-- Slots 2-4: Skill cards
	for i = 2, 4 do
		local key = "slot" .. i
		local slotData = loadout[key]
		if slotData and slotData.skillId then
			local def = SkillData[slotData.skillId]
			slots[i] = {
				slotType = "SkillCard",
				skillId = slotData.skillId,
				skillName = def and def.name or slotData.skillId,
				augments = slotData.augments or {},
				locked = false,
			}
		else
			slots[i] = { slotType = "Empty", skillId = "none", augments = {}, locked = false }
		end
	end
	-- Slot 5: Locked
	slots[5] = { slotType = "Locked", skillId = "none", augments = {}, locked = true }
	-- Include doctrine choices so client doesn't rely on mock data
	local docChoices = {}
	if unit.doctrineId then
		local doctrine = DoctrineData[unit.doctrineId]
		if doctrine then
			docChoices = doctrine.skillChoices or {}
		end
	end

	return {
		ok = true,
		slots = slots,
		skillCards = cardInventory.skillCards,
		augmentCards = cardInventory.augmentCards,
		doctrineId = unit.doctrineId,
		doctrineChoices = docChoices,
	}
end

-- RequestEquipSkillCard: equip a skill card into slot 2/3/4
BattleEvents.RequestEquipSkillCard.OnServerInvoke = function(player, unitId, slotIndex, skillId)
	local unit = playerUnits[unitId]
	if not unit then
		warn("[SkillCard] Equip FAILED: Unknown unit " .. tostring(unitId))
		return { ok = false, reason = "Unknown unit" }
	end
	if slotIndex < 2 or slotIndex > 4 then
		return { ok = false, reason = "Invalid slot (must be 2-4)" }
	end
	-- Validate skill exists
	local skillDef = SkillData[skillId]
	if not skillDef then
		return { ok = false, reason = "Unknown skill: " .. tostring(skillId) }
	end
	-- Check card inventory
	local qty = cardInventory.skillCards[skillId] or 0
	if qty <= 0 then
		return { ok = false, reason = "No skill card: " .. (skillDef.name or skillId) }
	end
	-- Check not already equipped in another slot on this unit
	-- Check against doctrine skill (slot 1) — doctrines can offer regular skills
	if unit.selectedDoctrineSkill and unit.selectedDoctrineSkill == skillId then
		return { ok = false, reason = skillDef.name .. " already equipped as Doctrine Skill" }
	end
	-- Check against other skill card slots (2-4)
	local loadout = unit.skillLoadout or {}
	for _, key in ipairs({"slot2", "slot3", "slot4"}) do
		local slotData = loadout[key]
		if slotData and slotData.skillId == skillId then
			return { ok = false, reason = skillDef.name .. " already equipped in another slot" }
		end
	end
	-- Unequip existing card in target slot (return to inventory)
	local slotKey = "slot" .. slotIndex
	local existing = loadout[slotKey]
	if existing and existing.skillId then
		cardInventory.skillCards[existing.skillId] = (cardInventory.skillCards[existing.skillId] or 0) + 1
		-- Return augment cards too
		for _, augId in ipairs(existing.augments or {}) do
			if augId then
				cardInventory.augmentCards[augId] = (cardInventory.augmentCards[augId] or 0) + 1
			end
		end
	end
	-- Consume card from inventory
	cardInventory.skillCards[skillId] = qty - 1
	if cardInventory.skillCards[skillId] <= 0 then
		cardInventory.skillCards[skillId] = nil
	end
	-- Equip
	if not unit.skillLoadout then unit.skillLoadout = {} end
	unit.skillLoadout[slotKey] = { skillId = skillId, augments = {} }
	rebuildSkillIds(unit)
	print(string.format("[SkillCard] %s equipped %s in slot %d", unit.name, skillDef.name, slotIndex))
	return { ok = true, skillName = skillDef.name }
end

-- RequestUnequipSkillCard: remove a skill card from slot 2/3/4
BattleEvents.RequestUnequipSkillCard.OnServerInvoke = function(player, unitId, slotIndex)
	local unit = playerUnits[unitId]
	if not unit then return { ok = false, reason = "Unknown unit" } end
	if slotIndex < 2 or slotIndex > 4 then return { ok = false, reason = "Invalid slot" } end
	local slotKey = "slot" .. slotIndex
	local loadout = unit.skillLoadout or {}
	local existing = loadout[slotKey]
	if not existing or not existing.skillId then
		return { ok = false, reason = "Slot is empty" }
	end
	-- Return skill card to inventory
	cardInventory.skillCards[existing.skillId] = (cardInventory.skillCards[existing.skillId] or 0) + 1
	-- Return augment cards
	for _, augId in ipairs(existing.augments or {}) do
		if augId then
			cardInventory.augmentCards[augId] = (cardInventory.augmentCards[augId] or 0) + 1
		end
	end
	unit.skillLoadout[slotKey] = nil
	rebuildSkillIds(unit)
	print(string.format("[SkillCard] %s unequipped slot %d", unit.name, slotIndex))
	return { ok = true }
end

-- RequestAttachAugment: attach an augment card to a skill's augment slot
BattleEvents.RequestAttachAugment.OnServerInvoke = function(player, unitId, slotIndex, augSlotIndex, augmentId)
	local unit = playerUnits[unitId]
	if not unit then return { ok = false, reason = "Unknown unit" } end
	if slotIndex < 1 or slotIndex > 4 then return { ok = false, reason = "Invalid skill slot" } end
	if augSlotIndex < 1 or augSlotIndex > 2 then return { ok = false, reason = "Invalid augment slot (1 or 2)" } end
	-- Validate augment exists
	local augDef = AugmentData[augmentId]
	if not augDef then return { ok = false, reason = "Unknown augment" } end
	-- Check card inventory
	local qty = cardInventory.augmentCards[augmentId] or 0
	if qty <= 0 then return { ok = false, reason = "No augment card: " .. (augDef.name or augmentId) } end
	-- Find the skill slot data
	local slotKey = slotIndex == 1 and "_doctrine" or ("slot" .. slotIndex)
	local slotData
	if slotIndex == 1 then
		-- Doctrine skill augments stored separately
		if not unit.doctrineAugments then unit.doctrineAugments = {} end
		slotData = unit.doctrineAugments
	else
		local loadout = unit.skillLoadout or {}
		slotData = loadout[slotKey]
		if not slotData or not slotData.skillId then
			return { ok = false, reason = "No skill in slot " .. slotIndex }
		end
	end
	-- Initialize augments array
	if slotIndex == 1 then
		-- Doctrine augments: simple 2-slot array
		local existing = slotData[augSlotIndex]
		if existing then
			cardInventory.augmentCards[existing] = (cardInventory.augmentCards[existing] or 0) + 1
		end
		slotData[augSlotIndex] = augmentId
	else
		if not slotData.augments then slotData.augments = {} end
		local existing = slotData.augments[augSlotIndex]
		if existing then
			cardInventory.augmentCards[existing] = (cardInventory.augmentCards[existing] or 0) + 1
		end
		slotData.augments[augSlotIndex] = augmentId
	end
	cardInventory.augmentCards[augmentId] = qty - 1
	if cardInventory.augmentCards[augmentId] <= 0 then cardInventory.augmentCards[augmentId] = nil end
	print(string.format("[Augment] %s attached %s to slot %d aug %d", unit.name, augDef.name, slotIndex, augSlotIndex))
	return { ok = true, augmentName = augDef.name }
end

-- RequestDetachAugment: remove an augment from a skill's augment slot
BattleEvents.RequestDetachAugment.OnServerInvoke = function(player, unitId, slotIndex, augSlotIndex)
	local unit = playerUnits[unitId]
	if not unit then return { ok = false, reason = "Unknown unit" } end
	if augSlotIndex < 1 or augSlotIndex > 2 then return { ok = false, reason = "Invalid augment slot" } end
	local augId
	if slotIndex == 1 then
		if not unit.doctrineAugments then return { ok = false, reason = "No augments" } end
		augId = unit.doctrineAugments[augSlotIndex]
		unit.doctrineAugments[augSlotIndex] = nil
	else
		local loadout = unit.skillLoadout or {}
		local slotData = loadout["slot" .. slotIndex]
		if not slotData or not slotData.augments then return { ok = false, reason = "No augments" } end
		augId = slotData.augments[augSlotIndex]
		slotData.augments[augSlotIndex] = nil
	end
	if not augId then return { ok = false, reason = "Augment slot empty" } end
	cardInventory.augmentCards[augId] = (cardInventory.augmentCards[augId] or 0) + 1
	print(string.format("[Augment] %s detached aug from slot %d aug %d", unit.name, slotIndex, augSlotIndex))
	return { ok = true }
end

--------------------------------------------------
-- CONSUMABLE SLOT MANAGEMENT (Slice 4G.4)
--------------------------------------------------

local ConsumableData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("ConsumableData")
)

-- RequestEquipConsumable: assign a consumable to a slot (1-6)
BattleEvents.RequestEquipConsumable.OnServerInvoke = function(player, unitId, slotIndex, consumableId)
	local unit = playerUnits[unitId]
	if not unit then return { ok = false, reason = "Unknown unit" } end
	if slotIndex < 1 or slotIndex > 6 then return { ok = false, reason = "Invalid slot (1-6)" } end
	if slotIndex > (unit.consumableSlotCount or 3) then
		return { ok = false, reason = "Slot " .. slotIndex .. " is locked" }
	end
	-- Validate consumable exists
	local consDef = ConsumableData.GetById(consumableId)
	if not consDef then return { ok = false, reason = "Unknown consumable: " .. tostring(consumableId) } end
	-- Check not already in another slot on this unit
	for idx, existing in pairs(unit.consumableSlots or {}) do
		if existing.consumableId == consumableId and idx ~= slotIndex then
			return { ok = false, reason = consDef.name .. " already in slot " .. idx }
		end
	end
	-- Replace existing
	if not unit.consumableSlots then unit.consumableSlots = {} end
	unit.consumableSlots[slotIndex] = {
		consumableId = consumableId,
		currentCharges = consDef.maxCharges or 1,
		maxCharges = consDef.maxCharges or 1,
	}
	print(string.format("[Consumable] %s equipped %s in slot %d (charges: %d)",
		unit.name, consDef.name, slotIndex, consDef.maxCharges or 1))
	return { ok = true, name = consDef.name, charges = consDef.maxCharges or 1 }
end

-- RequestUnequipConsumable: remove consumable from slot
BattleEvents.RequestUnequipConsumable.OnServerInvoke = function(player, unitId, slotIndex)
	local unit = playerUnits[unitId]
	if not unit then return { ok = false, reason = "Unknown unit" } end
	if not unit.consumableSlots or not unit.consumableSlots[slotIndex] then
		return { ok = false, reason = "Slot is empty" }
	end
	local removed = unit.consumableSlots[slotIndex]
	unit.consumableSlots[slotIndex] = nil
	print(string.format("[Consumable] %s unequipped slot %d (%s)",
		unit.name, slotIndex, removed.consumableId))
	return { ok = true }
end

-- GetConsumableSlots: return all consumable slot data for all player units
BattleEvents.GetConsumableSlots.OnServerInvoke = function(player)
	local result = {}
	for unitId, unit in pairs(playerUnits) do
		local slots = {}
		local maxSlots = unit.maxConsumableSlots or 6
		local unlockedSlots = unit.consumableSlotCount or 3
		for idx = 1, maxSlots do
			local slotData = unit.consumableSlots and unit.consumableSlots[idx]
			if slotData then
				local consDef = ConsumableData.GetById(slotData.consumableId)
				slots[idx] = {
					consumableId = slotData.consumableId,
					name = consDef and consDef.name or "Unknown",
					currentCharges = slotData.currentCharges,
					maxCharges = slotData.maxCharges,
					locked = (idx > unlockedSlots),
				}
			else
				slots[idx] = { empty = true, locked = (idx > unlockedSlots) }
			end
		end
		result[unitId] = slots
	end
	return result
end

--------------------------------------------------
-- STAT ALLOCATION & COMPARISON (Slice 4J)
--------------------------------------------------

-- Stat allocation: units earn points through leveling (Slice 6).
-- Human race passive: +1 bonus point every 3 levels.
-- For now: no leveling = 0 base points. Infrastructure ready for when leveling arrives.

local STATS_LIST = {"STR", "AGI", "INT", "VIT", "DEX", "LUK"}

local function getUnallocatedPoints(unit)
	-- Base points from leveling (Slice 6 will provide this formula)
	local basePoints = 0  -- placeholder: 0 until leveling system exists
	-- Human race bonus: +1 per 3 levels
	if unit.raceId == "RACE-HUMAN" then
		basePoints = basePoints + math.floor((unit.level or 1) / 3)
	end
	-- Subtract already allocated
	local spent = 0
	local alloc = unit.statAllocation or {}
	for _, stat in ipairs(STATS_LIST) do
		spent = spent + (alloc[stat] or 0)
	end
	return math.max(0, basePoints - spent)
end

-- RequestAllocateStat: spend 1 unallocated point on a stat
BattleEvents.RequestAllocateStat.OnServerInvoke = function(player, unitId, stat)
	local unit = playerUnits[unitId]
	if not unit then return { ok = false, reason = "Unknown unit" } end
	-- Validate stat name
	local validStat = false
	for _, s in ipairs(STATS_LIST) do
		if s == stat then validStat = true; break end
	end
	if not validStat then return { ok = false, reason = "Invalid stat: " .. tostring(stat) } end
	-- Check points available
	local available = getUnallocatedPoints(unit)
	if available <= 0 then
		return { ok = false, reason = "No unallocated points" }
	end
	-- Allocate
	if not unit.statAllocation then unit.statAllocation = {} end
	unit.statAllocation[stat] = (unit.statAllocation[stat] or 0) + 1
	-- Rebuild stats (allocation feeds into baseStats)
	unit.baseStats[stat] = unit.baseStats[stat] + 1
	EquipmentService.RebuildUnitStats(unit)
	print(string.format("[StatAlloc] %s +1 %s (total alloc: %d, remaining: %d)",
		unit.name, stat, unit.statAllocation[stat], getUnallocatedPoints(unit)))
	return {
		ok = true,
		stat = stat,
		newValue = unit.effectiveStats[stat],
		remaining = getUnallocatedPoints(unit),
	}
end

-- GetUnitFullStats: returns complete stat breakdown for Info tab
BattleEvents.GetUnitFullStats.OnServerInvoke = function(player, unitId)
	local unit = playerUnits[unitId]
	if not unit then return { ok = false, reason = "Unknown unit" } end

	-- Race info
	local raceEntry = unit.raceId and RaceData and RaceData.GetRace(unit.raceId) or nil
	-- Doctrine info
	local docEntry = unit.doctrineId and DoctrineData[unit.doctrineId] or nil

	return {
		ok = true,
		unitId = unit.id,
		name = unit.name,
		level = unit.level or 1,
		-- Primary stats
		baseStats = {
			STR = unit.baseStats.STR, AGI = unit.baseStats.AGI,
			INT = unit.baseStats.INT, VIT = unit.baseStats.VIT,
			DEX = unit.baseStats.DEX, LUK = unit.baseStats.LUK,
		},
		effectiveStats = {
			STR = unit.effectiveStats.STR, AGI = unit.effectiveStats.AGI,
			INT = unit.effectiveStats.INT, VIT = unit.effectiveStats.VIT,
			DEX = unit.effectiveStats.DEX, LUK = unit.effectiveStats.LUK,
		},
		derivedStats = unit.derivedStats or {},
		statAllocation = unit.statAllocation or {},
		unallocatedPoints = getUnallocatedPoints(unit),
		-- Resources
		currentHp = unit.currentHp, maxHp = unit.maxHp,
		currentMp = unit.currentMp, maxMp = unit.maxMp,
		-- Race
		raceId = unit.raceId,
		raceName = raceEntry and raceEntry.name or nil,
		racePassiveName = raceEntry and raceEntry.passiveName or nil,
		racePassiveEffect = raceEntry and raceEntry.passiveEffect or nil,
		-- Doctrine
		doctrineId = unit.doctrineId,
		doctrineName = docEntry and docEntry.name or nil,
		doctrinePassiveName = docEntry and docEntry.passiveName or nil,
		doctrinePassiveEffect = docEntry and docEntry.passiveEffect or nil,
	}
end

-- GetEquipmentComparison: authoritative before/after deltas for equipping an item
BattleEvents.GetEquipmentComparison.OnServerInvoke = function(player, unitId, instanceId)
	local unit = playerUnits[unitId]
	if not unit then return { ok = false, reason = "Unknown unit" } end
	local item = InventoryService.GetItem(PLAYER_ID, instanceId)
	if not item then return { ok = false, reason = "Item not found" } end
	-- Snapshot current stats
	local before = {
		STR = unit.effectiveStats.STR, AGI = unit.effectiveStats.AGI,
		INT = unit.effectiveStats.INT, VIT = unit.effectiveStats.VIT,
		DEX = unit.effectiveStats.DEX, LUK = unit.effectiveStats.LUK,
		maxHp = unit.maxHp, maxMp = unit.maxMp,
		weaponDamage = unit.weaponDamage, weaponWt = unit.weaponWt,
		weaponDefense = unit.weaponDefense,
		armorDefense = unit.armorDefense or 0,
		armorWt = unit.armorWt or 0,
	}
	-- Determine target slot
	local slot = EquipmentService.DetermineSlot(item)
	if not slot then return { ok = false, reason = "Cannot determine slot" } end
	-- Save current equipped item in that slot
	local savedItem = unit.equipmentSlots and unit.equipmentSlots[slot] or nil
	-- Temporarily equip the new item
	if not unit.equipmentSlots then unit.equipmentSlots = {} end
	unit.equipmentSlots[slot] = item
	EquipmentService.RebuildUnitStats(unit)
	-- Snapshot after
	local after = {
		STR = unit.effectiveStats.STR, AGI = unit.effectiveStats.AGI,
		INT = unit.effectiveStats.INT, VIT = unit.effectiveStats.VIT,
		DEX = unit.effectiveStats.DEX, LUK = unit.effectiveStats.LUK,
		maxHp = unit.maxHp, maxMp = unit.maxMp,
		weaponDamage = unit.weaponDamage, weaponWt = unit.weaponWt,
		weaponDefense = unit.weaponDefense,
		armorDefense = unit.armorDefense or 0,
		armorWt = unit.armorWt or 0,
	}
	-- Restore original
	unit.equipmentSlots[slot] = savedItem
	EquipmentService.RebuildUnitStats(unit)
	-- Compute deltas
	local deltas = {}
	for key, val in pairs(after) do
		local diff = val - (before[key] or 0)
		if diff ~= 0 then
			deltas[key] = diff
		end
	end
	return { ok = true, slot = slot, before = before, after = after, deltas = deltas }
end

-- GetDoctrineComparison: authoritative before/after for swapping doctrine
BattleEvents.GetDoctrineComparison.OnServerInvoke = function(player, unitId, newDoctrineId)
	local unit = playerUnits[unitId]
	if not unit then return { ok = false, reason = "Unknown unit" } end
	local newDoc = DoctrineData[newDoctrineId]
	if not newDoc then return { ok = false, reason = "Unknown doctrine" } end
	-- Snapshot current
	local before = {
		STR = unit.effectiveStats.STR, AGI = unit.effectiveStats.AGI,
		INT = unit.effectiveStats.INT, VIT = unit.effectiveStats.VIT,
		DEX = unit.effectiveStats.DEX, LUK = unit.effectiveStats.LUK,
		maxHp = unit.maxHp, maxMp = unit.maxMp,
		doctrineName = unit.doctrineId and DoctrineData[unit.doctrineId] and DoctrineData[unit.doctrineId].name or "none",
	}
	-- Temporarily swap doctrine
	local savedDoc = unit.doctrineId
	unit.doctrineId = newDoctrineId
	EquipmentService.RebuildUnitStats(unit)
	local after = {
		STR = unit.effectiveStats.STR, AGI = unit.effectiveStats.AGI,
		INT = unit.effectiveStats.INT, VIT = unit.effectiveStats.VIT,
		DEX = unit.effectiveStats.DEX, LUK = unit.effectiveStats.LUK,
		maxHp = unit.maxHp, maxMp = unit.maxMp,
		doctrineName = newDoc.name,
	}
	-- Restore
	unit.doctrineId = savedDoc
	EquipmentService.RebuildUnitStats(unit)
	-- Deltas
	local deltas = {}
	for _, stat in ipairs(STATS_LIST) do
		local diff = after[stat] - before[stat]
		if diff ~= 0 then deltas[stat] = diff end
	end
	local hpDiff = after.maxHp - before.maxHp
	local mpDiff = after.maxMp - before.maxMp
	if hpDiff ~= 0 then deltas.maxHp = hpDiff end
	if mpDiff ~= 0 then deltas.maxMp = mpDiff end
	return { ok = true, before = before, after = after, deltas = deltas }
end

--------------------------------------------------
-- HUB + REWARD SCREEN HELPERS
--------------------------------------------------

local hubContinueSignal = Instance.new("BindableEvent")
local rewardContinueSignal = Instance.new("BindableEvent")

BattleEvents.StartBattle.OnServerEvent:Connect(function(player)
	print("[Hub] Player ready to start battle")
	hubContinueSignal:Fire()
end)

BattleEvents.RewardContinue.OnServerEvent:Connect(function(player)
	print("[Hub] Player acknowledged rewards")
	rewardContinueSignal:Fire()
end)





-- Forward declarations for DevCommand handler (needs state/pendingCommand/commandReceived)
local state
local pendingCommand
local commandReceived

--------------------------------------------------
-- DEV COMMANDS (Studio only -- instant win/lose/kill)
--------------------------------------------------

local devForceResult = nil -- "PlayerWin" or "PlayerLose"

if game:GetService("RunService"):IsStudio() then
	BattleEvents.DevCommand.OnServerEvent:Connect(function(player, cmd)
		if not cmd or type(cmd) ~= "table" then return end

		if cmd.action == "InstantWin" then
			print("[Dev] Instant Win triggered")
			for _, u in ipairs(allUnitsList) do
				if u.side == "Enemy" and u.isAlive then
					UnitSchema.Kill(u)
					clearTileOccupant(u.tileX, u.tileY)
					BattleEvents.UnitDefeated:FireAllClients({ unitId = u.id })
					print(string.format("[Dev] Killed %s", u.name))
				end
			end
			state.phase = "BattleOver"
			state.winner = "Player"
			pendingCommand = { actionType = "Wait" }
			commandReceived:Fire()

		elseif cmd.action == "InstantLose" then
			print("[Dev] Instant Lose triggered")
			for _, u in ipairs(allUnitsList) do
				if u.side == "Player" and u.isAlive then
					UnitSchema.Kill(u)
					clearTileOccupant(u.tileX, u.tileY)
					BattleEvents.UnitDefeated:FireAllClients({ unitId = u.id })
					print(string.format("[Dev] Killed %s", u.name))
				end
			end
			state.phase = "BattleOver"
			state.winner = "Enemy"
			pendingCommand = { actionType = "Wait" }
			commandReceived:Fire()

		elseif cmd.action == "KillAtTile" then
			local tx, ty = cmd.tileX, cmd.tileY
			if not tx or not ty then return end
			for _, u in ipairs(allUnitsList) do
				if u.tileX == tx and u.tileY == ty and u.isAlive then
					print(string.format("[Dev] Kill unit at (%d,%d): %s HP:%d->0", tx, ty, u.name, u.currentHp))
					UnitSchema.Kill(u)
					clearTileOccupant(u.tileX, u.tileY)
					BattleEvents.UnitDefeated:FireAllClients({ unitId = u.id })
				end
			end
		elseif cmd.action == "DeleteSave" then
			local ok, err = SaveService.Delete(PLAYER_ID)
			if ok then
				print("[Dev] Save deleted for " .. PLAYER_ID .. " -- restart to begin fresh")
			else
				warn("[Dev] Delete failed: " .. (err or "unknown"))
			end

		elseif cmd.action == "SaveNow" then
			local ok, err = doSave()
			if ok then
				print("[Dev] Manual save successful")
			else
				warn("[Dev] Manual save failed: " .. (err or "unknown"))
			end
		end
	end)
	print("[Dev] DevCommand handler active (Studio only)")
end

-- PRE-BATTLE LOADOUT HUB
print("[Hub] Opening pre-battle Loadout Hub")
BattleEvents.LoadoutHubOpen:FireAllClients({ phase = "PreBattle" })

-- Wait for player to press Start Battle
hubContinueSignal.Event:Wait()
print("[Hub] Player started battle")

state = BattleCoordinator.CreateBattleState(allUnitsList)

task.wait(2)
BattleVisualBroadcaster.BattleStarted(state.units)

--------------------------------------------------
-- CHANNEL INTERRUPT HOOK
--------------------------------------------------

local function checkChannelInterrupt(unit, statusId)
	if unit.isChanneling and StatusService.IsChannelDisruptor(statusId) then
		BattleCoordinator.InterruptChanneling(unit, statusId .. " applied")
		return true
	end
	return false
end

--------------------------------------------------
-- PLAYER TURN: Build prompt data
--
-- Sends the player all info needed to choose an action:
--   - Available skills (with MP check)
--   - Move candidates (tiles they can walk to)
--   - Attack candidates (enemies in melee range)
--------------------------------------------------

local function buildTurnPrompt(unit)
	-- Timeline data: all alive units sorted by remainingRt (who acts soonest)
	local timeline = {}
	for _, u in ipairs(state.units) do
		if u.isAlive then
			table.insert(timeline, {
				id          = u.id,
				name        = u.name,
				side        = u.side,
				remainingRt = u.remainingRt,
				currentHp   = u.currentHp,
				maxHp       = u.maxHp,
				isActive    = (u.id == unit.id), -- mark the actual active unit
				isChanneling = u.isChanneling or false,
				channelRt   = u.channelRt or 0,
				channeledSkillName = u.channelingData and u.channelingData.skillDef and u.channelingData.skillDef.name or nil,
			})
		end
	end
	table.sort(timeline, function(a, b) return a.remainingRt < b.remainingRt end)

	local skills = {}
	for _, sid in ipairs(unit.skillIds or {}) do
		local def = CommandService.GetSkill(sid)
		if def then
			local canUse = UnitSchema.HasEnoughMp(unit, def.mpCost or 0)
			local candidates = TargetingService.GetSkillCandidates(unit, state.units, def)
			local targetIds = {}
			for _, c in ipairs(candidates) do
				-- Pre-calculate predicted value for this target
				local predicted = 0
				local predType = "damage"
				if def.isHealing then
					local healResult = CombatResolver.ResolveHealing(unit, c, def)
					predicted = healResult.finalHealing or 0
					predType = "healing"
				else
					local dmgResult = CombatResolver.ResolveSkill(unit, c, def)
					predicted = dmgResult.finalDamage or 0
				end
				table.insert(targetIds, {
					id        = c.id,
					name      = c.name,
					tileX     = c.tileX,
					tileY     = c.tileY,
					predicted = predicted,
					predType  = predType,
				})
			end

			table.insert(skills, {
				id          = def.id,
				name        = def.name,
				willEndTurn = (def.channelTime or 0) > 0, -- warn player: channeling ends turn
				mpCost      = def.mpCost or 0,
				range       = def.range or 1,
				pattern     = def.pattern or "Single",
				targetRules = def.targetRules or "Enemy Unit",
				isHealing   = def.isHealing or false,
				channelTime = def.channelTime or 0,
				canUse      = canUse,
				targets     = targetIds,
				tags        = def.tags or {},
				rtCost      = def.rtMult
					and math.round(GameConstants.CalcEffectiveWt(
						unit.weaponWt or 10, (unit.effectiveStats or {}).STR or 10) * def.rtMult)
					or (def.rtCost or 60),
				power       = def.power or 0,
				appliesStatus = def.appliesStatus or nil,
				description = def.isHealing and "Heals ally" or (def.appliesStatus and ("Applies " .. def.appliesStatus) or "Damages target"),
			})
		end
	end

	local moveTiles = TargetingService.GetMoveCandidates(unit, state.units, MAP_WIDTH, MAP_HEIGHT)
	local moveCandidates = {}
	for _, tile in ipairs(moveTiles) do
		table.insert(moveCandidates, {
			tileX    = tile.tileX,
			tileY    = tile.tileY,
			pathCost = tile.pathCost,
			terrain  = tile.terrain,
			path     = tile.path,
		})
	end

	local attackCandidates = TargetingService.GetAttackCandidates(unit, state.units, unit.weaponMaxRange or 1)
	local attackTargets = {}
	for _, c in ipairs(attackCandidates) do
		-- Pre-calculate predicted basic attack damage for aim phase
		local atkResult = CombatResolver.ResolveBasicAttack(unit, c, unit.weaponDamage or 10)
		table.insert(attackTargets, {
			id        = c.id,
			name      = c.name,
			tileX     = c.tileX,
			tileY     = c.tileY,
			predicted = atkResult.finalDamage or 0,
		})
	end

	-- Push targets: adjacent enemies (range 1, Chebyshev)
	-- Android: extended range (up to 4), cannot target adjacent (minDistance 2)
	local pushOverride = RacePassiveService.GetPushOverride(unit)
	local pushMaxDist = pushOverride and pushOverride.maxDistance or 1
	local pushMinDist = pushOverride and pushOverride.minDistance or 1
	local pushTargets = {}
	for _, c in ipairs(state.units) do
		if c.isAlive and c.side ~= unit.side then
			local dist = math.max(math.abs(c.tileX - unit.tileX), math.abs(c.tileY - unit.tileY))
			if dist >= pushMinDist and dist <= pushMaxDist then
				table.insert(pushTargets, { id = c.id, name = c.name, tileX = c.tileX, tileY = c.tileY })
			end
		end
	end

	return {
		unitId         = unit.id,
		unitName       = unit.name,
		unitSide       = unit.side,
		currentAp      = unit.currentAp,
		currentMp      = unit.currentMp,
		maxMp          = unit.maxMp,
		currentHp      = unit.currentHp,
		maxHp          = unit.maxHp,
		guardUsed      = unit.guardUsedThisTurn or false,
		tileX          = unit.tileX,
		tileY          = unit.tileY,
		skills         = skills,
		moveCandidates = moveCandidates,
		attackTargets  = attackTargets,
		pushTargets    = pushTargets,
		pushRt         = math.round(StatusService.GetModifiedBaseRt(unit) * GameConstants.GUARD_RT_BASE_FACTOR),
		timeline       = timeline,
		currentCt      = state.ct,
		-- RT cost data so client can preview turn order shifts
		unitBaseRt = StatusService.GetModifiedBaseRt(unit),
		turnRtAccrued = state.turnRtAccrued or 0,
		attackRt   = math.round(
			StatusService.GetModifiedBaseRt(unit) * GameConstants.BASIC_ATTACK_RT_FACTOR
		) + math.round(GameConstants.CalcEffectiveWt(
			unit.weaponWt or 40, unit.effectiveStats and unit.effectiveStats.STR or 10
		)),
		waitRt     = math.round(
			StatusService.GetModifiedBaseRt(unit) * GameConstants.REST_RT_MULTIPLIER
		),
		weaponRtDelay = unit.weaponRtDelay or 0,
		weaponDamage  = unit.weaponDamage or 10,
		-- Unit identity (for active unit panel display)
		level    = unit.level or 1,
		race     = unit.raceId and RaceData.GetRace(unit.raceId)
			and RaceData.GetRace(unit.raceId).name or nil,
		doctrine = unit.doctrineId and DoctrineData[unit.doctrineId]
			and DoctrineData[unit.doctrineId].name or "",
		maxAp    = 2,
	}
end

--------------------------------------------------
-- PLAYER TURN: Wait for player command
--
-- Sends prompt, then yields until the client fires PlayerCommand.
-- Returns the command payload or nil on timeout.
--------------------------------------------------

local PLAYER_TURN_TIMEOUT = 120 -- seconds

pendingCommand = nil
commandReceived = Instance.new("BindableEvent")

BattleEvents.PlayerCommand.OnServerEvent:Connect(function(player, command)
	-- Accept commands from any connected player (single-player for now)
	pendingCommand = command
	commandReceived:Fire()
end)

local function waitForPlayerCommand(unit, playerObj)
	-- Send prompt to client
	local prompt = buildTurnPrompt(unit)
	print(string.format(
		"[Main] Sending PlayerTurnPrompt to %s for %s (AP:%d, Skills:%d, Moves:%d)",
		playerObj.Name, unit.name, unit.currentAp, #prompt.skills, #prompt.moveCandidates
	))
	BattleEvents.PlayerTurnPrompt:FireClient(playerObj, prompt)

	-- Wait for response
	pendingCommand = nil
	local startTime = tick()

	while not pendingCommand do
		local elapsed = tick() - startTime
		if elapsed > PLAYER_TURN_TIMEOUT then
			print("[Main] Player turn TIMEOUT — auto-waiting.")
			return { actionType = "Wait" }
		end
		commandReceived.Event:Wait()
	end

	local cmd = pendingCommand
	pendingCommand = nil
	return cmd
end

--------------------------------------------------
-- PLAYER TURN: Execute one player command
-- Returns: action table for broadcasting, or nil
--------------------------------------------------

local function executePlayerCommand(unit, command)
	local actionType = command.actionType

	if actionType == "Wait" then
		CommandService.ValidateAndCommit(state, unit.id, "Wait", nil)
		return { actionType = "Wait", unit = unit }
	end

	if actionType == "Guard" then
		local ok, reason = CommandService.ValidateAndCommit(state, unit.id, "Guard", nil)
		if ok then
			return { actionType = "Guard", unit = unit }
		else
			warn("[Main] Guard rejected: " .. (reason or "unknown"))
			return nil
		end
	end

	if actionType == "Push" then
		-- Find the target unit by ID
		local target = nil
		for _, u in ipairs(state.units) do
			if u.id == command.targetId then target = u; break end
		end
		if not target then
			warn("[Main] Push: target not found")
			return nil
		end
		local oldTargetX, oldTargetY = target.tileX, target.tileY
		local ok, reason = CommandService.ValidateAndCommit(state, unit.id, "Push", target)
		if ok then
			return { actionType = "Push", unit = unit, target = target,
				oldTargetX = oldTargetX, oldTargetY = oldTargetY }
		else
			warn("[Main] Push rejected: " .. (reason or "unknown"))
			return nil
		end
	end

	if actionType == "Move" then
		local selection = { tileX = command.tileX, tileY = command.tileY, pathCost = command.pathCost }
		local oldX, oldY = unit.tileX, unit.tileY
		local ok, reason = CommandService.ValidateAndCommit(state, unit.id, "Move", selection)
		if ok then
			return { actionType = "Move", unit = unit, oldTileX = oldX, oldTileY = oldY }
		else
			warn("[Main] Player move rejected: " .. (reason or "unknown"))
			return nil
		end
	end

	if actionType == "Attack" then
		-- Find the target unit by ID
		local target = nil
		for _, u in ipairs(state.units) do
			if u.id == command.targetId then
				target = u
				break
			end
		end
		if not target then
			warn("[Main] Player attack: target not found")
			return nil
		end

		local hpBefore = target.currentHp
		local rtBefore = target.remainingRt
		local statusesBefore = #target.statusInstances
		local ok, reason = CommandService.ValidateAndCommit(state, unit.id, "Attack", target)
		if ok then
			local newStatus = nil
			if #target.statusInstances > statusesBefore then
				newStatus = target.statusInstances[#target.statusInstances].id
			end
			local rtAdded = target.remainingRt - rtBefore
			return {
				actionType    = "Attack",
				unit          = unit,
				target        = target,
				damage        = hpBefore - target.currentHp,
				statusApplied = newStatus,
				rtDelay       = rtAdded > 0 and rtAdded or nil,
			}
		else
			warn("[Main] Player attack rejected: " .. (reason or "unknown"))
			return nil
		end
	end

	if actionType == "Skill" then
		-- Find the target unit by ID
		local target = nil
		for _, u in ipairs(state.units) do
			if u.id == command.targetId then
				target = u
				break
			end
		end
		if not target then
			warn("[Main] Player skill: target not found")
			return nil
		end

		local skillDef = CommandService.GetSkill(command.skillId)
		if not skillDef then
			warn("[Main] Player skill: unknown skill " .. tostring(command.skillId))
			return nil
		end

		-- Snapshot ALL units' HP/RT before commit (for AOE detection)
		local hpSnapshot = {}
		local rtSnapshot = {}
		local statusSnapshot = {}
		local burnSnapshot = {}
		for _, u in ipairs(state.units) do
			hpSnapshot[u.id] = u.currentHp
			rtSnapshot[u.id] = u.remainingRt
			statusSnapshot[u.id] = #u.statusInstances
			-- Snapshot burn stored value for accumulation detection
			local burnInst = StatusService.HasStatus(u, "Burn")
			burnSnapshot[u.id] = burnInst and burnInst.storedBurn or 0
		end

		local selection = { target = target, skillId = command.skillId }

		local ok, reason = CommandService.ValidateAndCommit(state, unit.id, "Skill", selection)
		if ok then
			-- Detect ALL units that were affected (for AOE skills)
			local results = {}
			for _, u in ipairs(state.units) do
				local prevHp = hpSnapshot[u.id] or u.currentHp
				local hpDiff = prevHp - u.currentHp
				local prevStatuses = statusSnapshot[u.id] or 0
				local newStatus = nil
				if #u.statusInstances > prevStatuses then
					newStatus = u.statusInstances[#u.statusInstances].id
				else
					-- Detect refreshed/accumulated statuses (instance count didn't change)
					if skillDef.appliesStatus and hpDiff > 0 then
						local inst = StatusService.HasStatus(u, skillDef.appliesStatus)
						if inst then
							newStatus = skillDef.appliesStatus
						end
					end
				end
				if hpDiff ~= 0 or newStatus then
					local rtAdded = u.remainingRt - (rtSnapshot[u.id] or 0)
					table.insert(results, {
						actionType    = "Skill",
						unit          = unit,
						target        = u,
						skillName     = skillDef.name,
						damage        = math.max(0, hpDiff),
						healing       = math.max(0, -hpDiff),
						statusApplied = newStatus,
						isChanneling  = unit.isChanneling,
						rtDelay       = rtAdded > 0 and rtAdded or nil,
					})
				end
			end

			-- Return first result (broadcastActions handles one at a time)
			-- But we need to return ALL results for AOE
			if #results == 1 then
				return results[1]
			elseif #results > 1 then
				-- Return a special multi-hit result
				return { actionType = "MultiHit", actions = results }
			else
				-- No visible change (e.g. channel commit)
				return {
					actionType   = "Skill",
					unit         = unit,
					target       = target,
					skillName    = skillDef.name,
					damage       = 0,
					healing      = 0,
					isChanneling = unit.isChanneling,
				}
			end
		else
			warn("[Main] Player skill rejected: " .. (reason or "unknown"))
			return nil
		end
	end

	warn("[Main] Unknown player command: " .. tostring(actionType))
	return nil
end

--------------------------------------------------
-- PLAYER TURN: Full loop (keeps prompting until AP=0 or Wait)
--------------------------------------------------

local function broadcastActions(actions, activeUnit)
	for _, action in ipairs(actions) do
		if action.actionType == "Move" then
			clearTileOccupant(action.oldTileX, action.oldTileY)
			local u = action.unit
			setTileOccupant(u.tileX, u.tileY, u.name, "Unit (" .. u.side .. ")", "Blocking")
			BattleVisualBroadcaster.UnitMoved(action.unit)

		elseif action.actionType == "Attack" or action.actionType == "Skill" then
			local target = action.target
			if target then
				if action.healing and action.healing > 0 then
					BattleVisualBroadcaster.HealingApplied(
						action.unit, target, action.healing, action.skillName
					)
				elseif action.isChanneling then
					-- Channel commit visual — no damage yet
				else
					local outcome = {
						finalDamage   = action.damage or 0,
						type          = "Damage",
						statusApplied = action.statusApplied,
						rtDelay       = action.rtDelay,
					}
					BattleVisualBroadcaster.UnitActed(
						action.unit, target, outcome, action.skillName
					)

					if not target.isAlive then
						clearTileOccupant(target.tileX, target.tileY)
					end

					if action.statusApplied then
						local statusInst = StatusService.HasStatus(target, action.statusApplied)
						if statusInst then
							BattleVisualBroadcaster.StatusApplied(
								target, action.statusApplied, statusInst.remainingTurns
							)
						end
						checkChannelInterrupt(target, action.statusApplied)
					end
				end
			end

		elseif action.actionType == "Guard" then
			-- Guard visual already broadcast by CommandService; nothing extra needed here

		elseif action.actionType == "Push" then
			-- Update tile occupancy for push displacement
			if action.target and action.oldTargetX then
				clearTileOccupant(action.oldTargetX, action.oldTargetY)
				local t = action.target
				if t.isAlive then
					setTileOccupant(t.tileX, t.tileY, t.name, "Unit (" .. t.side .. ")", "Blocking")
				end
			end
			-- Push visual already broadcast by CommandService
		end
	end

	-- After each broadcast batch, send updated timeline so client sees
	-- real-time turn order changes (especially during AI turns)
	local timelineUpdate = {}
	for _, u in ipairs(state.units) do
		if u.isAlive then
			table.insert(timelineUpdate, {
				id = u.id, name = u.name, side = u.side,
				remainingRt = u.remainingRt, isChanneling = u.isChanneling or false,
				channelRt = u.channelRt or 0,
				channeledSkillName = u.channelingData and u.channelingData.skillDef and u.channelingData.skillDef.name or nil,
			})
		end
	end
	BattleEvents.TurnOrderUpdate:FireAllClients({ units = timelineUpdate, currentCt = state.ct })
end


local function runPlayerTurn(unit)
	local actions = {}

	-- Find the first connected player (single-player game)
	local playerObj = Players:GetPlayers()[1]
	if not playerObj then
		warn("[Main] No player connected — AI fallback")
		CommandService.ValidateAndCommit(state, unit.id, "Wait", nil)
		return {}
	end

	while BattleCoordinator.GetPhase(state) == "TurnOpen" and unit.currentAp > 0 and unit.isAlive do
		local command = waitForPlayerCommand(unit, playerObj)
		local action = executePlayerCommand(unit, command)

		if action then
			-- Handle MultiHit (AOE) results
			if action.actionType == "MultiHit" then
				for _, subAction in ipairs(action.actions) do
					table.insert(actions, subAction)
				end
				broadcastActions(action.actions, unit)
			else
				table.insert(actions, action)
				broadcastActions({ action }, unit)
			end

			-- If it was Wait, turn ended inside CommandService
			if action.actionType == "Wait" then
				break
			end
		else
			-- Command rejected — send prompt again
		end
	end

	-- Close turn if still open
	if BattleCoordinator.GetPhase(state) == "TurnOpen" then
		CommandService.ValidateAndCommit(state, unit.id, "Wait", nil)
	end

	return actions
end

--------------------------------------------------
-- AI LOGIC (same as before)
--------------------------------------------------

local function findLowestAlly(unit, allUnits)
	local lowest = nil
	local lowestPct = 1.0
	for _, other in ipairs(allUnits) do
		if other.isAlive and other.side == unit.side then
			local pct = other.currentHp / other.maxHp
			if pct < lowestPct then
				lowestPct = pct
				lowest = other
			end
		end
	end
	return lowest, lowestPct
end

local function runAiTurn(unit)
	local allUnits = state.units
	local actions  = {}

	local function tryCommit(actionType, selection, skillName)
		if BattleCoordinator.GetPhase(state) ~= "TurnOpen" then
			return false
		end

		local targetUnit = nil
		if actionType == "Attack" then
			targetUnit = selection
		elseif actionType == "Skill" then
			targetUnit = selection and selection.target
		end
		local hpBefore = targetUnit and targetUnit.currentHp or 0
		local statusesBefore = targetUnit and #targetUnit.statusInstances or 0

		local oldTileX = unit.tileX
		local oldTileY = unit.tileY

		local ok, _ = CommandService.ValidateAndCommit(
			state, unit.id, actionType, selection
		)

		if ok and actionType ~= "Wait" then
			local damage = 0
			local healing = 0
			if targetUnit then
				local hpDiff = hpBefore - targetUnit.currentHp
				if hpDiff > 0 then
					damage = hpDiff
				elseif hpDiff < 0 then
					healing = -hpDiff
				end
			end

			local newStatus = nil
			if targetUnit and #targetUnit.statusInstances > statusesBefore then
				newStatus = targetUnit.statusInstances[#targetUnit.statusInstances].id
			else
				-- Detect refreshed/accumulated statuses (e.g. Burn accumulation)
				if targetUnit and actionType == "Skill" and selection and selection.skillId then
					local def = CommandService.GetSkill(selection.skillId)
					if def and def.appliesStatus and damage > 0 then
						local inst = StatusService.HasStatus(targetUnit, def.appliesStatus)
						if inst then newStatus = def.appliesStatus end
					end
				end
			end

			table.insert(actions, {
				actionType     = actionType,
				unit           = unit,
				oldTileX       = oldTileX,
				oldTileY       = oldTileY,
				target         = targetUnit,
				skillName      = skillName,
				damage         = damage,
				healing        = healing,
				statusApplied  = newStatus,
				isChanneling   = unit.isChanneling,
			})

			if newStatus and targetUnit then
				checkChannelInterrupt(targetUnit, newStatus)
			end
		end

		return ok
	end

	-- Use AIService to plan the turn (3-tier role-based scoring)
	local plan = AIService.PlanTurn(unit, allUnits, MAP_WIDTH, MAP_HEIGHT)

	-- Execute the plan step by step
	for _, step in ipairs(plan) do
		if BattleCoordinator.GetPhase(state) ~= "TurnOpen" then break end
		if unit.currentAp <= 0 and step.actionType ~= "Wait" then break end

		local ok = false
		if step.actionType == "Attack" then
			ok = tryCommit("Attack", step.selection, nil)
		elseif step.actionType == "Skill" then
			ok = tryCommit("Skill", step.selection, step.skillName)
		elseif step.actionType == "Move" then
			ok = tryCommit("Move", step.selection, nil)
		elseif step.actionType == "Guard" then
			ok = tryCommit("Guard", nil, nil)
		elseif step.actionType == "Push" then
			ok = tryCommit("Push", step.selection, nil)
		elseif step.actionType == "Wait" then
			-- Wait handled at end
			break
		end

		-- After a move, re-evaluate if plan requested it
		if ok and step.actionType == "Move" and plan.needsReeval
			and BattleCoordinator.GetPhase(state) == "TurnOpen" and unit.currentAp > 0 then
			-- Re-plan with remaining AP from new position
			local replan = AIService.PlanTurn(unit, allUnits, MAP_WIDTH, MAP_HEIGHT)
			for _, rstep in ipairs(replan) do
				if BattleCoordinator.GetPhase(state) ~= "TurnOpen" then break end
				if unit.currentAp <= 0 then break end
				if rstep.actionType == "Wait" then break end
				if rstep.actionType ~= "Move" then
					if rstep.actionType == "Attack" then
						tryCommit("Attack", rstep.selection, nil)
					elseif rstep.actionType == "Skill" then
						tryCommit("Skill", rstep.selection, rstep.skillName)
					elseif rstep.actionType == "Guard" then
						tryCommit("Guard", nil, nil)
					elseif rstep.actionType == "Push" then
						tryCommit("Push", rstep.selection, nil)
					end
					break  -- Only 1 action after re-eval
				end
			end
		end
	end

	-- AI consumable usage (Slice 4G): after plan execution, check if unit
	-- should use a consumable item (healing at low HP, status cure, etc.)
	if BattleCoordinator.GetPhase(state) == "TurnOpen" and unit.currentAp > 0 and unit.consumableSlots then
		local bestSlot = nil
		local bestPriority = 0
		for slotIdx = 1, (unit.consumableSlotCount or 3) do
			local slot = unit.consumableSlots[slotIdx]
			if slot and slot.consumableId and slot.currentCharges and slot.currentCharges > 0 then
				local consDef = ConsumableData.GetById(slot.consumableId)
				if consDef then
					local formula = consDef.effectFormula or ""
					local hpPct = unit.currentHp / math.max(1, unit.maxHp)
					local mpPct = unit.currentMp / math.max(1, unit.maxMp)
					local priority = 0
					-- HP recovery: use when HP ≤ 35%
					if formula:match("Restore%s+%d+%%%s+target%s+Max%s+HP") and hpPct <= 0.35 then
						priority = 10 + (1 - hpPct) * 10
					-- MP recovery: use when MP ≤ 20% and unit has skills
					elseif formula:match("Restore%s+%d+%%%s+target%s+Max%s+MP") and mpPct <= 0.20 and #(unit.skillIds or {}) > 0 then
						priority = 5
					-- Status cure: use when unit has a disabling status
					elseif formula:match("Remove") then
						for _, inst in ipairs(unit.statusInstances or {}) do
							if inst.id == "Poison" or inst.id == "Burn" or inst.id == "Silence" then
								priority = 7; break
							end
						end
					end
					-- Charge conservation: preserve last charge unless critical
					if priority > 0 and slot.currentCharges <= 1 and hpPct > 0.20 then
						priority = 0
					end
					if priority > bestPriority then bestPriority = priority; bestSlot = slotIdx end
				end
			end
		end
		if bestSlot then
			local target = { tileX = unit.tileX, tileY = unit.tileY }
			print(string.format("[AI] %s using consumable slot %d", unit.name, bestSlot))
			tryCommit("Item", { target = target, itemSlotIndex = bestSlot }, nil)
		end
	end

	-- Always end turn
	if BattleCoordinator.GetPhase(state) == "TurnOpen" then
		CommandService.ValidateAndCommit(state, unit.id, "Wait", nil)
	end

	return actions
end

--------------------------------------------------
-- HANDLE CHANNELING ACTIVATION
--------------------------------------------------

local function handleChannelingActivation(activeUnit)
	-- Grab skill name before activation clears channeling data
	local channeledSkillName = activeUnit.channelingData
		and activeUnit.channelingData.skillDef
		and (activeUnit.channelingData.skillDef.name or activeUnit.channelingData.skillDef.id)
		or "Unknown"

	local success, result = CommandService.ActivateChanneledSkill(state, activeUnit)
	local actions = {}

	if not success then
		-- Fizzle: target died, MP insufficient, etc.
		BattleVisualBroadcaster.ChannelFizzled(activeUnit, channeledSkillName, result or "fizzled")
	elseif result then
		if result.type == "Healing" then
			table.insert(actions, {
				actionType = "Skill", unit = activeUnit, target = result.target,
				skillName = result.skillName, healing = result.healing, damage = 0,
			})
		elseif result.type == "AOE" then
			for _, entry in ipairs(result.targets or {}) do
				table.insert(actions, {
					actionType = "Skill", unit = activeUnit, target = entry.target,
					skillName = result.skillName, damage = entry.outcome.finalDamage,
					healing = 0, statusApplied = entry.outcome.appliesStatus,
				})
			end
		elseif result.type == "Damage" then
			table.insert(actions, {
				actionType = "Skill", unit = activeUnit, target = result.target,
				skillName = result.skillName, damage = result.damage,
				healing = 0, statusApplied = result.statusApplied,
			})
		end
	end

	if BattleCoordinator.GetPhase(state) == "TurnOpen" then
		BattleCoordinator.EndTurn(state)
	end

	return actions
end

--------------------------------------------------
-- BROADCAST ACTIONS HELPER
--------------------------------------------------


--------------------------------------------------
-- UNIT INSPECT REQUEST (3-tab panel data)
--------------------------------------------------

BattleEvents.InspectUnitRequest.OnServerEvent:Connect(function(playerObj, unitId)
	-- Find the unit in state
	local unit = nil
	for _, u in ipairs(state.units) do
		if u.id == unitId then unit = u; break end
	end
	if not unit then return end

	-- Build equipment data
	local equipData = {}
	local slots = unit.equipmentSlots or {}
	for slotName, itemInst in pairs(slots) do
		if itemInst then
			local profile = EquipmentService.GetEffectiveWeaponProfile(itemInst)
			local _wArch = WeaponData.GetByArchetypeId(itemInst.baseArchetypeId)
			local _aArch = not _wArch and ArmorData.GetByArchetypeId(itemInst.baseArchetypeId) or nil
			local _icon = (_wArch and _wArch.icon) or (_aArch and _aArch.icon) or nil
			equipData[slotName] = {
				name      = (_wArch and _wArch.name) or (_aArch and _aArch.name) or "Unknown",
				rarity    = itemInst.rarity or "Common",
				itemLevel = itemInst.itemLevel or 1,
				archetype = itemInst.archetype or "Unknown",
				handClass = itemInst.handClass or "1H",
				damage    = profile and profile.damage or 0,
				wt        = profile and profile.wt or 0,
				rtDelay   = profile and profile.rtDelay or 0,
				defense   = profile and profile.defense or 0,
				minRange  = profile and profile.minRange or 1,
				maxRange  = profile and profile.maxRange or 1,
				pattern   = profile and profile.pattern or "Single",
				bonusLines = itemInst.bonusLines or {},
				resolvedBonus = (function() local s, p = resolveItemBonuses(itemInst); return {stats = s, passives = p} end)(),
				passiveName   = itemInst.nativePassiveId or nil,
				passiveDesc   = itemInst.nativePassiveId and WeaponData.GetPassiveDesc(itemInst.nativePassiveId) or nil,
				bonusPassive  = itemInst.bonusPassive or nil,
				flavor        = (_wArch and _wArch.flavor) or (_aArch and _aArch.flavor) or nil,
				icon          = _icon,
				displayName   = itemInst.displayName or nil,
			}
		end
	end

	-- Build skill data
	local skillsData = {}
	for _, sid in ipairs(unit.skillIds or {}) do
		local skillKey = string.upper(sid):gsub("SKILL_", "SKL-"):gsub("_", "-")
		local fullData = SkillData[skillKey]
		local regDef = CommandService.GetSkill(sid)
		local skillPower = regDef and regDef.power or 0
		table.insert(skillsData, {
			id           = sid,
			name         = regDef and regDef.name or (fullData and fullData.name or sid),
			tags         = fullData and fullData.tags or (regDef and regDef.tags or {}),
			targetRules  = fullData and fullData.targetRules or (regDef and regDef.targetRules or ""),
			range        = regDef and regDef.range or 1,
			pattern      = fullData and fullData.pattern or (regDef and regDef.pattern or "Single"),
			mpCost       = regDef and regDef.mpCost or 0,
			rtCost       = (regDef and regDef.rtMult)
				and math.round(GameConstants.CalcEffectiveWt(
					unit.weaponWt or 10, (unit.effectiveStats or {}).STR or 10) * regDef.rtMult)
				or (regDef and regDef.rtCost or 0),
			channelTime  = regDef and regDef.channelTime or 0,
			power        = skillPower,
			isHealing    = regDef and regDef.isHealing or false,
			powerFormula = fullData and fullData.powerFormula or "",
			mpCostFormula = fullData and fullData.mpCostFormula or "",
			rtCostFormula = fullData and fullData.rtCostFormula or "",
			effects      = fullData and fullData.effects or "",
			specialRules = fullData and fullData.specialRules or "",
			icon         = fullData and fullData.icon or nil,
			description  = fullData and fullData.description or nil,
		})
		-- Attach estimated raw damage (presentation-only, before defense)
		local attackPower = unit.derivedStats and unit.derivedStats.attackPower or 0
		skillsData[#skillsData].estimatedDamage = math.round(attackPower * skillPower)
	end

	-- Build full response
	-- Build status summary
	local rawSummary = StatusService.GetStatusSummary(unit)
	local statusSummary = {}
	for _, entry in ipairs(rawSummary) do
		local sid = entry.id
		local sDef = sid and GameConstants.STATUSES[sid] or nil
		local inst = nil
		for _, si in ipairs(unit.statusInstances or {}) do
			if si.id == sid then inst = si; break end
		end
		table.insert(statusSummary, {
			id = sid,
			remainingTurns = entry.remainingTurns or (sDef and sDef.duration),
			remainingCt = inst and inst.remainingCt or nil,
			kind = sDef and sDef.kind or "Debuff",
			stacks = inst and inst.stacks and inst.stacks > 1 and inst.stacks or nil,
			nextDamage = entry.nextDamage,
			storedBurn = entry.storedBurn,
		})
	end

	local response = {
		unitId       = unit.id,
		name         = unit.name,
		side         = unit.side,
		level        = unit.level or 1,
		raceId       = unit.raceId or nil,  -- placeholder: race system not yet implemented
		racePassiveName   = nil,  -- populated below if race assigned
		racePassiveEffect = nil,
		tileX        = unit.tileX,
		tileY        = unit.tileY,
		currentHp    = unit.currentHp,
		maxHp        = unit.maxHp,
		currentMp    = unit.currentMp,
		maxMp        = unit.maxMp,
		currentAp    = unit.currentAp or 0,
		remainingRt  = unit.remainingRt or 0,
		primaryStats = unit.primaryStats,
		derivedStats = unit.derivedStats,
		equipment    = equipData,
		skills       = skillsData,
		statuses     = statusSummary,
		doctrineId   = unit.doctrineId,
		doctrine     = unit.doctrineId and DoctrineData[unit.doctrineId] or nil,
	}

	-- Populate race passive if race is assigned
	local raceEntry = unit.raceId and RaceData and RaceData.GetRace(unit.raceId) or nil
	if raceEntry then
		response.raceName = raceEntry.name
		response.racePassiveName = raceEntry.passiveName
		response.racePassiveEffect = raceEntry.passiveEffect
	end

	BattleEvents.InspectUnitResponse:FireClient(playerObj, response)
end)

--------------------------------------------------
-- BATTLE LOOP
--------------------------------------------------

local MAX_TURNS = 200
local turnCount = 0

-- Initialize armor passives for all units at battle start (Slice 4G.9)
for _, unit in ipairs(state.units) do
	ArmorPassiveService.OnBattleStart(unit)
end

while BattleCoordinator.GetPhase(state) ~= "BattleOver" and turnCount < MAX_TURNS do
	local activeUnit = BattleCoordinator.AdvanceClock(state)
	if not activeUnit then break end

	turnCount = turnCount + 1

	-- Process DoT
	local dotEvents = state.dotEvents or {}
	state.dotEvents = nil

	for _, dot in ipairs(dotEvents) do
		if activeUnit.isAlive then
			local actual = UnitSchema.ApplyDamage(activeUnit, dot.damage)
			print(string.format(
				"[DoT] %s takes %d %s damage | HP: %d/%d%s",
				activeUnit.name, actual, dot.statusId,
				activeUnit.currentHp, activeUnit.maxHp,
				activeUnit.isAlive and "" or " | DEFEATED"
			))
			BattleVisualBroadcaster.DotDamage(activeUnit, dot.statusId, actual)
		end
	end

	-- If unit died to DoT
	if not activeUnit.isAlive then
		clearTileOccupant(activeUnit.tileX, activeUnit.tileY)
		if activeUnit.isChanneling then
			BattleCoordinator.InterruptChanneling(activeUnit, "death")
		end
		BattleCoordinator.EndTurn(state)
		BattleVisualBroadcaster.TurnEnded(activeUnit, 0)
	elseif StatusService.ShouldSkipTurn(activeUnit) then
		-- Turn skip: Sleep / Petrify / Stun / Knock-out
		local _, skipReason = StatusService.ShouldSkipTurn(activeUnit)
		print(string.format(
			"[TurnSkip] %s skipped (%s) | HP: %d/%d",
			activeUnit.name, skipReason,
			activeUnit.currentHp, activeUnit.maxHp
		))
		BattleVisualBroadcaster.TurnStarted(activeUnit, state.ct, state.units)
		StatusService.TickStatuses(activeUnit)
		BattleCoordinator.EndTurn(state)
		BattleVisualBroadcaster.TurnSkipped(activeUnit, skipReason)
		BattleVisualBroadcaster.TurnEnded(activeUnit, activeUnit.remainingRt)
	else
		-- Normal turn
		BattleVisualBroadcaster.TurnStarted(activeUnit, state.ct, state.units)

		-- Determine turn handler
		local actions
		local wasChanneling = BattleCoordinator.IsChanneling(activeUnit)
		if BattleCoordinator.IsChanneling(activeUnit) then
			actions = handleChannelingActivation(activeUnit)
		elseif activeUnit.controller == "Player" then
			actions = runPlayerTurn(activeUnit)
		else
			actions = runAiTurn(activeUnit)
		end

		-- Broadcast
		if activeUnit.controller ~= "Player" or wasChanneling then
			broadcastActions(actions, activeUnit)
		end

		-- Safety close
		if BattleCoordinator.GetPhase(state) == "TurnOpen" then
			CommandService.ValidateAndCommit(state, activeUnit.id, "Wait", nil)
		end

		BattleVisualBroadcaster.TurnEnded(activeUnit, activeUnit.remainingRt)
	end
end

--------------------------------------------------
-- RESULT
--------------------------------------------------

print("====================================")
local phase  = BattleCoordinator.GetPhase(state)
local winner = BattleCoordinator.GetWinner(state)

if phase == "BattleOver" then
	print(string.format("BATTLE OVER — %s wins! (%d turns)", winner, turnCount))
else
	print(string.format("BATTLE TIMED OUT after %d turns.", turnCount))
end
print("====================================")
for _, u in ipairs(allUnitsList) do
	print(string.format("  %s", UnitSchema.Describe(u)))
end
print("====================================")

BattleVisualBroadcaster.BattleEnded(winner or "None", state.units)

--------------------------------------------------
-- POST-BATTLE: PERSIST STATE + RECOVERY (Slice 4B)
--------------------------------------------------

local isQualifyingVictory = (winner == "Player")

--------------------------------------------------
-- POST-BATTLE: UPDATE UNIT RECORDS (Slice 4K)
--------------------------------------------------
for _, u in ipairs(allUnitsList) do
	if u.side == "Player" and u.records then
		u.records.battlesParticipated = (u.records.battlesParticipated or 0) + 1
		if isQualifyingVictory then
			u.records.victoriesParticipated = (u.records.victoriesParticipated or 0) + 1
		end
		if not u.isAlive then
			u.records.timesKO = (u.records.timesKO or 0) + 1
		end
	end
end
-- Enemy defeat tracking: count how many enemies each player unit killed
for _, u in ipairs(allUnitsList) do
	if u.side == "Enemy" and not u.isAlive and u._killedBy then
		local killer = playerUnits[u._killedBy]
		if killer and killer.records then
			killer.records.enemiesDefeated = (killer.records.enemiesDefeated or 0) + 1
		end
	end
end

-- Step 1: Persist final HP/MP for all player units
for _, u in ipairs(allUnitsList) do
	if u.side == "Player" then
		PersistentStateService.PersistBattleEnd(
			PLAYER_ID, u.id,
			u.currentHp, u.currentMp,
			u.maxHp, u.maxMp,
			not u.isAlive -- isKO
		)
	end
end

-- Step 2a: Clear KO on all player units (session rule — base not implemented)
PersistentStateService.ClearAllKO(PLAYER_ID)

-- Step 2b: Apply 35% recovery to all survivors (regardless of outcome)
print("[PostBattle] Applying 35% recovery to survivors")
local recovery = PersistentStateService.ApplyPostBattleRecovery(PLAYER_ID)
for unitId, result in pairs(recovery) do
	print(string.format("  %s: HP+%d MP+%d", unitId, result.hpRecovered, result.mpRecovered))
end

--------------------------------------------------
-- POST-BATTLE: GENERATE REWARDS (Slice 4D)
--------------------------------------------------

local rewardSummaries = {}

if isQualifyingVictory then
	-- Map Level placeholder: 1 until Slice 5 provides authoritative value
	local MAP_LEVEL = 1
	local opportunityId = string.format("battle_%s_%d", PLAYER_ID, os.clock())

	local results, equipCommitted = RewardService.GenerateRewards(PLAYER_ID, MAP_LEVEL, opportunityId)

	-- Commit non-equipment rewards to card inventories
	local cardCommitted = 0
	for _, result in ipairs(results) do
		if not result.committed and result.cardData then
			local cat = result.category
			local id = result.cardData.id
			if cat == "SkillCard" then
				cardInventory.skillCards[id] = (cardInventory.skillCards[id] or 0) + 1
				result.committed = true
				cardCommitted = cardCommitted + 1
			elseif cat == "AugmentCard" then
				cardInventory.augmentCards[id] = (cardInventory.augmentCards[id] or 0) + 1
				result.committed = true
				cardCommitted = cardCommitted + 1
			elseif cat == "Doctrine" or cat == "Consumable" then
				-- Tracked for display; ownership gating deferred
				result.committed = true
				cardCommitted = cardCommitted + 1
			end
		end
	end

	local totalCommitted = equipCommitted + cardCommitted
	if totalCommitted > 0 then
		rewardSummaries = RewardService.BuildRewardSummaries(results)
		print(string.format("[PostBattle] %d reward(s) committed (%d equip, %d cards)", totalCommitted, equipCommitted, cardCommitted))
	end

	-- Log any failures explicitly
	for i, result in ipairs(results) do
		if not result.committed then
			warn(string.format("[PostBattle] Reward %d failed: %s", i, result.error or "unknown"))
		end
	end
end

-- Step 3: Save to DataStore (now includes committed rewards)
doSave()

-- Step 4: Reward screen (if rewards earned)
-- Build recovery summary for client display
local recoverySummary = {}
for unitId, result in pairs(recovery) do
	local unitName = unitId
	for _, u in ipairs(state.units) do
		if u.id == unitId then unitName = u.name; break end
	end
	if result.hpRecovered > 0 or result.mpRecovered > 0 then
		table.insert(recoverySummary, {
			name = unitName, hpGain = result.hpRecovered, mpGain = result.mpRecovered,
		})
	end
end

if #rewardSummaries > 0 then
	print(string.format("[PostBattle] Sending %d reward(s) to client", #rewardSummaries))
	BattleEvents.RewardScreen:FireAllClients({ rewards = rewardSummaries, recovery = recoverySummary })
	rewardContinueSignal.Event:Wait()
	print("[PostBattle] Player acknowledged rewards")
end

-- Step 5: Post-battle Loadout Hub
print("[Hub] Opening post-battle Loadout Hub")
BattleEvents.LoadoutHubOpen:FireAllClients({ phase = "PostBattle" })

-- Step 6: Wait for player to close the hub, then auto-save
-- (Equipment changes via RequestEquip update the same unit objects
-- that doSave reads, so this save captures any post-battle equip changes.)
hubContinueSignal.Event:Wait()
print("[Hub] Post-battle hub closed — saving equipment changes")
doSave()

-- Keep script alive for management requests (SaveNow DevCommand also works here)
print("[Hub] Session active. Management requests available.")
while true do
	task.wait(1)
end
