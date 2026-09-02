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

--------------------------------------------------
-- SKILL REGISTRATION
--------------------------------------------------

for _, skillDef in pairs(GameConstants.SKILLS) do
	CommandService.RegisterSkill(skillDef)
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
	tileX        = 4,
	tileY        = 4,
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

local mage = UnitSchema.Create({
	id           = "unit_mage",
	name         = "Mage",
	level        = 25,
	raceId       = "RACE-ELF",
	side         = "Player",
	controller   = "Player",
	tileX        = 3,
	tileY        = 1,
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
	tileX        = 5,
	tileY        = 3,
	skillIds     = { "skill_crippling_shot", "skill_venom_strike" },
})
equipGeneratedWeapon(ranger, "WPN-CROSSBOW", 5, "Uncommon", 1003)

-- TEST OVERRIDE: Ranger's Venom Strike uses weapon range instead of fixed 1
do
	local baseVenom = GameConstants.SKILLS.venom_strike
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

local grunt = UnitSchema.Create({
	id           = "unit_grunt",
	name         = "Grunt",
	side         = "Enemy",
	controller   = "AI",
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
			-- Race identity (Slice 4F)
			raceId = unit.raceId or "none",
			raceName = unit.raceId and RaceData.GetRace(unit.raceId) and RaceData.GetRace(unit.raceId).name or "none",
			racePassive = unit.raceId and RaceData.GetRace(unit.raceId) and RaceData.GetRace(unit.raceId).passiveName or "none",
			perkIds = unit.perkIds or {},
			drawbackIds = unit.drawbackIds or {},
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
		local archetype = WeaponData.GetByArchetypeId(item.baseArchetypeId)
		local profile = WeaponData.GetScaledProfile(item.baseArchetypeId, item.itemLevel)
		table.insert(result, {
			instanceId = item.instanceId,
			name = archetype and archetype.name or "Unknown",
			category = archetype and archetype.category or "Unknown",
			handClass = archetype and archetype.handClass or "1H",
			itemLevel = item.itemLevel,
			rarity = item.rarityId,
			damage = profile and profile.damage or 0,
			wt = profile and profile.wt or 0,
			defense = profile and profile.defense or 0,
			bonusCount = #item.bonusLines,
			passiveCount = #item.bonusPassiveIds,
			equippedBy = equippedByMap[item.instanceId] and equippedByMap[item.instanceId].unitId or nil,
			equippedSlot = equippedByMap[item.instanceId] and equippedByMap[item.instanceId].slot or nil,
		})
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
	local archetype = WeaponData.GetByArchetypeId(item.baseArchetypeId)
	if not archetype then
		warn(string.format("[Management] Equip FAILED: %s + %s — Unknown archetype", tostring(unitId), tostring(instanceId)))
		return { ok = false, reason = "Unknown archetype" }
	end
	local slot = (archetype.category == "OffHand") and "OffHand" or "MainHand"
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
				rtCost      = def.rtCost or 60,
				power       = def.power or 0,
				appliesStatus = def.appliesStatus or nil,
				description = def.isHealing and "Heals ally" or (def.appliesStatus and ("Applies " .. def.appliesStatus) or "Damages target"),
			})
		end
	end

	local moveTiles = TargetingService.GetMoveCandidates(unit, state.units, MAP_WIDTH, MAP_HEIGHT)
	local moveCandidates = {}
	for _, tile in ipairs(moveTiles) do
		table.insert(moveCandidates, { tileX = tile.tileX, tileY = tile.tileY, pathCost = tile.pathCost })
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
	local pushTargets = {}
	for _, c in ipairs(state.units) do
		if c.isAlive and c.side ~= unit.side then
			local dist = math.max(math.abs(c.tileX - unit.tileX), math.abs(c.tileY - unit.tileY))
			if dist == 1 then
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
		race     = unit.race or nil,
		doctrine = unit.doctrineId or "",
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

	local acted = false
	-- Track if we have a deferred channeling skill to use as last action
	local deferredChannel = nil

	-- 1. Heal if ally below 50%
	local healSkillDef = nil
	for _, sid in ipairs(unit.skillIds or {}) do
		local def = CommandService.GetSkill(sid)
		if def and def.isHealing then
			healSkillDef = def
			break
		end
	end

	if healSkillDef and UnitSchema.HasEnoughMp(unit, healSkillDef.mpCost or 0) then
		local lowestAlly, lowestPct = findLowestAlly(unit, allUnits)
		if lowestAlly and lowestPct < 0.50 then
			-- If channeling skill and AP > 1, defer it (do other actions first)
			local isChannel = (healSkillDef.channelTime or 0) > 0
			if isChannel and unit.currentAp > 1 then
				deferredChannel = { skillDef = healSkillDef, targetId = lowestAlly.id }
			else
				local candidates = TargetingService.GetSkillCandidates(unit, allUnits, healSkillDef)
				for _, c in ipairs(candidates) do
					if c.id == lowestAlly.id then
						local ok = tryCommit("Skill",
							{ target = c, skillId = healSkillDef.id },
							healSkillDef.name
						)
						if ok then acted = true; break end
					end
				end
			end
		end
	end

	-- 2. Offensive skills
	if not acted then
		for _, sid in ipairs(unit.skillIds or {}) do
			local def = CommandService.GetSkill(sid)
			if def and not def.isHealing and UnitSchema.HasEnoughMp(unit, def.mpCost or 0) then
				-- If channeling and AP > 1, defer
				local isChannel = (def.channelTime or 0) > 0
				if isChannel and unit.currentAp > 1 then
					if not deferredChannel then
						local candidates = TargetingService.GetSkillCandidates(unit, allUnits, def)
						if #candidates > 0 then
							deferredChannel = { skillDef = def, targetId = candidates[1].id }
						end
					end
				else
					local candidates = TargetingService.GetSkillCandidates(unit, allUnits, def)
					if #candidates > 0 then
						local ok = tryCommit("Skill",
							{ target = candidates[1], skillId = def.id }, def.name)
						if ok then acted = true; break end
					end
				end
			end
		end
	end

	-- Second action
	if acted and BattleCoordinator.GetPhase(state) == "TurnOpen" and unit.currentAp > 0 then
		local attackCandidates = TargetingService.GetAttackCandidates(unit, allUnits, unit.weaponMaxRange or 1)
		if #attackCandidates > 0 then
			tryCommit("Attack", attackCandidates[1], nil)
		end
	end

	-- 3. Basic attack
	if not acted then
		local attackCandidates = TargetingService.GetAttackCandidates(unit, allUnits, unit.weaponMaxRange or 1)
		if #attackCandidates > 0 then
			acted = true
			tryCommit("Attack", attackCandidates[1], nil)
			if BattleCoordinator.GetPhase(state) == "TurnOpen" and unit.currentAp > 0 then
				attackCandidates = TargetingService.GetAttackCandidates(unit, allUnits, unit.weaponMaxRange or 1)
				if #attackCandidates > 0 then
					tryCommit("Attack", attackCandidates[1], nil)
				end
			end
		end
	end

	-- 4. Move toward enemy
	if not acted then
		local nearestEnemy = nil
		local nearestDist  = math.huge
		for _, other in ipairs(allUnits) do
			if other.isAlive and other.side ~= unit.side then
				local d = math.max(
					math.abs(other.tileX - unit.tileX),
					math.abs(other.tileY - unit.tileY)
				)
				if d < nearestDist then
					nearestDist  = d
					nearestEnemy = other
				end
			end
		end

		if nearestEnemy then
			local moveCandidates = TargetingService.GetMoveCandidates(unit, allUnits, MAP_WIDTH, MAP_HEIGHT)
			local bestTile, bestDist = nil, math.huge
			for _, tile in ipairs(moveCandidates) do
				local d = math.max(
					math.abs(tile.tileX - nearestEnemy.tileX),
					math.abs(tile.tileY - nearestEnemy.tileY)
				)
				if d < bestDist then bestDist = d; bestTile = tile end
			end
			if bestTile then tryCommit("Move", bestTile, nil) end
		end

		if BattleCoordinator.GetPhase(state) == "TurnOpen" and unit.currentAp > 0 then
			local usedSkill = false
			for _, sid in ipairs(unit.skillIds or {}) do
				local def = CommandService.GetSkill(sid)
				if def and not def.isHealing and UnitSchema.HasEnoughMp(unit, def.mpCost or 0) then
					local candidates = TargetingService.GetSkillCandidates(unit, allUnits, def)
					if #candidates > 0 then
						tryCommit("Skill", { target = candidates[1], skillId = def.id }, def.name)
						usedSkill = true; break
					end
				end
			end
			if not usedSkill then
				local attackCandidates = TargetingService.GetAttackCandidates(unit, allUnits, unit.weaponMaxRange or 1)
				if #attackCandidates > 0 then tryCommit("Attack", attackCandidates[1], nil) end
			end
		end
	end

	-- 5. Execute deferred channeling skill (last action, so no AP is wasted)
	if deferredChannel and BattleCoordinator.GetPhase(state) == "TurnOpen" and unit.currentAp > 0 then
		local def = deferredChannel.skillDef
		local targetId = deferredChannel.targetId
		-- Find the target unit
		local target = nil
		for _, u in ipairs(allUnits) do
			if u.id == targetId and u.isAlive then target = u; break end
		end
		if target and UnitSchema.HasEnoughMp(unit, def.mpCost or 0) then
			local candidates = TargetingService.GetSkillCandidates(unit, allUnits, def)
			for _, c in ipairs(candidates) do
				if c.id == targetId then
					tryCommit("Skill", { target = c, skillId = def.id }, def.name)
					break
				end
			end
		end
	end

	-- 6. Guard if low HP and have AP remaining (defensive fallback)
	if BattleCoordinator.GetPhase(state) == "TurnOpen" and unit.currentAp > 0 then
		local hpPct = unit.currentHp / unit.maxHp
		if hpPct < 0.40 and not unit.guardUsedThisTurn then
			tryCommit("Guard", nil, nil)
			table.insert(actions, { actionType = "Guard", unit = unit })
		end
	end

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
			equipData[slotName] = {
				name      = itemInst.name or "Unknown",
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
				nativePassive = itemInst.nativePassive or nil,
				bonusPassive  = itemInst.bonusPassive or nil,
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
			rtCost       = regDef and regDef.rtCost or 0,
			channelTime  = regDef and regDef.channelTime or 0,
			power        = skillPower,
			isHealing    = regDef and regDef.isHealing or false,
			powerFormula = fullData and fullData.powerFormula or "",
			mpCostFormula = fullData and fullData.mpCostFormula or "",
			rtCostFormula = fullData and fullData.rtCostFormula or "",
			effects      = fullData and fullData.effects or "",
			specialRules = fullData and fullData.specialRules or "",
		})
		-- Attach estimated raw damage (presentation-only, before defense)
		local attackPower = unit.derivedStats and unit.derivedStats.attackPower or 0
		skillsData[#skillsData].estimatedDamage = math.round(attackPower * skillPower)
	end

	-- Build full response
	-- Build status summary
	local statusSummary = {}
	for _, inst in ipairs(unit.statusInstances or {}) do
		table.insert(statusSummary, {
			id = inst.statusId,
			remainingTurns = inst.remainingTurns,
			kind = GameConstants.STATUSES[inst.statusId] and GameConstants.STATUSES[inst.statusId].kind or "Debuff",
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
	if unit.raceId and RaceData and RaceData[unit.raceId] then
		response.racePassiveName = RaceData[unit.raceId].passive_name
		response.racePassiveEffect = RaceData[unit.raceId].passive_effect
	end

	BattleEvents.InspectUnitResponse:FireClient(playerObj, response)
end)

--------------------------------------------------
-- BATTLE LOOP
--------------------------------------------------

local MAX_TURNS = 200
local turnCount = 0

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
		if BattleCoordinator.GetPhase(state) == "BattleOver" then break end
		continue
	end

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
	-- AI actions: broadcast all at once after turn.
	-- Player actions: broadcast immediately per-action inside runPlayerTurn.
	-- Channeling activations: always broadcast here (player didn't trigger them manually).
	if activeUnit.controller ~= "Player" or wasChanneling then
		broadcastActions(actions, activeUnit)
	end

	-- Safety close
	if BattleCoordinator.GetPhase(state) == "TurnOpen" then
		CommandService.ValidateAndCommit(state, activeUnit.id, "Wait", nil)
	end

	BattleVisualBroadcaster.TurnEnded(activeUnit, activeUnit.remainingRt)
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

	local results, committedCount = RewardService.GenerateRewards(PLAYER_ID, MAP_LEVEL, opportunityId)

	if committedCount > 0 then
		rewardSummaries = RewardService.BuildRewardSummaries(results)
		print(string.format("[PostBattle] %d reward(s) committed to inventory", committedCount))
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
