-- CTRBLXAI | LoadoutRequestHandlers  (extracted from Main.server.lua on 2026-10-12)
--
-- One-time setup: the ~18 roster/inventory/loadout RemoteFunction handlers that
-- the pre-battle management UI invokes (GetRosterData, equip/unequip, doctrine,
-- skill-card, augment, consumable, portrait/body, stat allocation, comparisons).
-- These are passive (only fire when the client invokes them), so Main connects
-- them once via Init() instead of running them inline.
--
-- DEPENDENCY INJECTION (roblox-best-practices-reference.md Section 18):
-- Luau modules do NOT share Main's locals, so Main must call
--   LoadoutRequestHandlers.Init({ playerUnits=, cardInventory=, doSave=, PLAYER_ID= })
-- AFTER the card-inventory restore block (so cardInventory is the final table).
-- All four are shared mutable state owned by Main; handlers mutate them in place.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Content           = ReplicatedStorage:WaitForChild("Content")
local Game              = script.Parent

-- Content data
local WeaponData     = require(Content:WaitForChild("WeaponData"))
local RaceData       = require(Content:WaitForChild("RaceData"))
local DoctrineData   = require(Content:WaitForChild("DoctrineData"))
local SkillData      = require(Content:WaitForChild("SkillData"))
local ArmorData      = require(Content:WaitForChild("ArmorData"))
local AugmentData    = require(Content:WaitForChild("AugmentData"))
local ConsumableData = require(Content:WaitForChild("ConsumableData"))
local PortraitData   = require(Content:WaitForChild("PortraitData"))

-- Shared / Remotes
local GameConstants = require(ReplicatedStorage:WaitForChild("CTRBLXAI"):WaitForChild("Shared"):WaitForChild("GameConstants"))
local BattleEvents  = require(ReplicatedStorage:WaitForChild("CTRBLXAI"):WaitForChild("Remotes"):WaitForChild("BattleEvents"))

-- Sibling services / modules (same Game folder)
local InventoryService       = require(Game:WaitForChild("InventoryService"))
local EquipmentService       = require(Game:WaitForChild("EquipmentService"))
local PersistentStateService = require(Game:WaitForChild("PersistentStateService"))
local CommandService         = require(Game:WaitForChild("CommandService"))
local ItemDisplay            = require(Game:WaitForChild("ItemDisplay"))

local LoadoutRequestHandlers = {}

-- Injected by Main.Init (nil until then).
local playerUnits
local cardInventory
local doSave
local PLAYER_ID

-- Co-located loadout-only helpers (were file-scope locals in Main).
local STATS_LIST = {"STR", "AGI", "INT", "VIT", "DEX", "LUK"}

local function getUnallocatedPoints(unit)
	-- USER RULING 2026-10-07: every unit gains 3 allocable stat points per level-up
	-- (on top of race growth, unit_progression 49). Humans (Adaptability) gain +1
	-- more on every 3rd level-up (4 instead of 3). Derived from level, never stored,
	-- so rejoins/level restores cannot double-grant. Level 1 = 0 level-ups.
	-- Formula lives in GameConstants.CalcAllocableStatPoints (shared with enemies).
	local basePoints = GameConstants.CalcAllocableStatPoints(unit.level, unit.raceId)
	-- Subtract already allocated
	local spent = 0
	local alloc = unit.statAllocation or {}
	for _, stat in ipairs(STATS_LIST) do
		spent = spent + (alloc[stat] or 0)
	end
	return math.max(0, basePoints - spent)
end

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

function LoadoutRequestHandlers.Init(deps)
	playerUnits   = deps.playerUnits
	cardInventory = deps.cardInventory
	doSave        = deps.doSave
	PLAYER_ID     = deps.PLAYER_ID

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
			-- Player-chosen 2D portrait asset ID (option B); nil = colored-box fallback.
			-- The loadout portrait picker reads this to highlight the current choice.
			portraitAssetId = unit.portraitAssetId or nil,
			-- Player-chosen body/skin tint {r,g,b}; nil = template colors.
			bodyColor = unit.bodyColor or nil,
			-- Unit records (Slice 4K)
			records = unit.records or {},
			-- Unspent stat points for the loadout header dot (2026-10-07).
			unallocatedPoints = getUnallocatedPoints and getUnallocatedPoints(unit) or 0,
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
		local entry = ItemDisplay.buildItemEntry(item)
		entry.equippedBy = equippedByMap[item.instanceId] and equippedByMap[item.instanceId].unitId or nil
		entry.equippedSlot = equippedByMap[item.instanceId] and equippedByMap[item.instanceId].slot or nil
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
	-- Validate augment compatibility with the target skill
	local targetSkillId
	if slotIndex == 1 then
		targetSkillId = unit.selectedDoctrineSkill
	else
		local slotKey2 = "slot" .. slotIndex
		local slotCheck = unit.skillLoadout and unit.skillLoadout[slotKey2]
		targetSkillId = slotCheck and slotCheck.skillId
	end
	if targetSkillId then
		local skillDef = CommandService.GetSkill(targetSkillId)
		if skillDef and augDef.requiredSkillTags then
			local skillTags = skillDef.tags or {}
			local hasMatch = false
			for _, reqTag in ipairs(augDef.requiredSkillTags) do
				for _, sTag in ipairs(skillTags) do
					if reqTag == sTag then hasMatch = true; break end
				end
				if hasMatch then break end
			end
			if not hasMatch then
				local needed = table.concat(augDef.requiredSkillTags, "/")
				return { ok = false, reason = augDef.name .. " requires [" .. needed .. "] skill — " .. (skillDef.name or targetSkillId) .. " is incompatible" }
			end
		end
	end
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

BattleEvents.RequestSetPortrait.OnServerInvoke = function(player, unitId, assetId)
	local unit = playerUnits[unitId]
	if not unit then return { ok = false, reason = "Unknown unit" } end
	-- Clear choice.
	if assetId == nil then
		unit.portraitAssetId = nil
		return { ok = true, cleared = true }
	end
	if type(assetId) ~= "number" then
		return { ok = false, reason = "Invalid portrait id" }
	end
	-- Must be in THIS unit's race pool.
	local pool = unit.raceId and PortraitData.GetPool(unit.raceId) or nil
	if not pool then return { ok = false, reason = "No portraits for this race" } end
	local inPool = false
	for _, id in ipairs(pool) do
		if id == assetId then inPool = true; break end
	end
	if not inPool then
		return { ok = false, reason = "Portrait not valid for this unit's race" }
	end
	unit.portraitAssetId = assetId
	print(string.format("[Portrait] %s set portrait %d (race %s)",
		unit.name, assetId, tostring(unit.raceId)))
	return { ok = true, assetId = assetId }
end

BattleEvents.RequestSetBodyColor.OnServerInvoke = function(player, unitId, r, g, b)
	local unit = playerUnits[unitId]
	if not unit then return { ok = false, reason = "Unknown unit" } end
	if r == nil then
		unit.bodyColor = nil
		return { ok = true, cleared = true }
	end
	if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
		return { ok = false, reason = "Invalid color" }
	end
	local function clamp255(v) return math.clamp(math.floor(v + 0.5), 0, 255) end
	unit.bodyColor = { clamp255(r), clamp255(g), clamp255(b) }
	print(string.format("[BodyColor] %s set body color (%d,%d,%d)",
		unit.name, unit.bodyColor[1], unit.bodyColor[2], unit.bodyColor[3]))
	return { ok = true, color = unit.bodyColor }
end

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
		-- Current player-chosen 2D portrait (nil = none). Lets the Info-tab picker
		-- highlight the selected face.
		portraitAssetId = unit.portraitAssetId or nil,
		-- Current player-chosen body tint {r,g,b} (nil = none) for the swatch picker.
		bodyColor = unit.bodyColor or nil,
		racePassiveName = raceEntry and raceEntry.passiveName or nil,
		racePassiveEffect = raceEntry and raceEntry.passiveEffect or nil,
		-- Doctrine
		doctrineId = unit.doctrineId,
		doctrineName = docEntry and docEntry.name or nil,
		doctrinePassiveName = docEntry and docEntry.passiveName or nil,
		doctrinePassiveEffect = docEntry and docEntry.passiveEffect or nil,
	}
end

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

end

return LoadoutRequestHandlers
