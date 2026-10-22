--!strict
-- DoctrineInventoryService.lua
-- CTRBLXAI | Doctrine Ownership Foundation (2026-10-20)
--
-- Server-authoritative ownership of Doctrine INSTANCES, modeled directly on
-- InventoryService (equipment). Doctrines are a loot/reward category per the
-- design DB (loot_progression id 30 "Doctrines are equippable. Duplicates remain
-- valid."; save_data_contract "DoctrineInstance" = instance ID + doctrine ID +
-- selected Skill ID). Each owned copy is a discrete instance.
--
-- MODEL
--   Each player has a flat map of DoctrineInstances keyed by instanceId:
--     { [instanceId] = { instanceId, doctrineId, selectedSkillId, boundUnitId } }
--   boundUnitId == nil  -> loose copy, available in the stash (pickable)
--   boundUnitId == <id> -> currently equipped on that unit (reserved)
--
--   Reservation mirrors equipment: an equipped instance is bound to exactly one
--   unit and is not available to others. Duplicates (same doctrineId, different
--   instanceId) remain valid and stack in the stash view by doctrineId.
--
-- Every combat-capable unit must ALWAYS have a bound Doctrine instance
-- (frameworks id 33 / unit_schema doctrine_instance_id "Required for normal
-- combat unit"). Minting + binding is centralized in Main's lifecycle choke
-- points (boot establishment + hire), which also migrates old saves that stored
-- only a content doctrineId with no instance.

local HttpService = game:GetService("HttpService")

local DoctrineInventoryService = {}

--------------------------------------------------
-- STATE
--------------------------------------------------

-- playerDoctrines[playerId] = { [instanceId] = doctrineInstance }
local playerDoctrines: { [string]: { [string]: any } } = {}

--------------------------------------------------
-- PLAYER LIFECYCLE
--------------------------------------------------

function DoctrineInventoryService.InitPlayer(playerId: string)
	if not playerDoctrines[playerId] then
		playerDoctrines[playerId] = {}
	end
end

function DoctrineInventoryService.GetInventory(playerId: string): { [string]: any }
	return playerDoctrines[playerId] or {}
end

function DoctrineInventoryService.ClearPlayer(playerId: string)
	playerDoctrines[playerId] = nil
end

--------------------------------------------------
-- INSTANCE MANAGEMENT
--------------------------------------------------

-- Generate a globally-unique instance id. GUID guarantees no collision across
-- sessions (equipment uses seeded ids; doctrines are minted at runtime, so a
-- GUID is the simplest safe choice).
function DoctrineInventoryService.NewInstanceId(): string
	return "doc_" .. HttpService:GenerateGUID(false)
end

function DoctrineInventoryService.AddInstance(playerId: string, inst: any): (boolean, string?)
	assert(type(inst) == "table", "AddInstance: inst must be a table.")
	assert(type(inst.instanceId) == "string", "AddInstance: instanceId required.")
	assert(type(inst.doctrineId) == "string", "AddInstance: doctrineId required.")
	assert(type(playerId) == "string", "AddInstance: playerId required.")

	DoctrineInventoryService.InitPlayer(playerId)
	local inv = playerDoctrines[playerId]

	if inv[inst.instanceId] then
		warn("[DoctrineInventoryService] Duplicate instance: " .. inst.instanceId)
		return false, "Duplicate instance ID"
	end

	inv[inst.instanceId] = inst
	return true
end

-- Mint a brand-new owned doctrine instance (optionally pre-bound to a unit).
-- Returns the instance table.
function DoctrineInventoryService.Mint(playerId: string, doctrineId: string, selectedSkillId: string?, boundUnitId: string?): any
	local inst = {
		instanceId = DoctrineInventoryService.NewInstanceId(),
		doctrineId = doctrineId,
		selectedSkillId = selectedSkillId,
		boundUnitId = boundUnitId,
	}
	DoctrineInventoryService.AddInstance(playerId, inst)
	return inst
end

function DoctrineInventoryService.RemoveInstance(playerId: string, instanceId: string): (boolean, string?)
	local inv = playerDoctrines[playerId]
	if not inv or not inv[instanceId] then
		return false, "Instance not found"
	end
	inv[instanceId] = nil
	return true
end

function DoctrineInventoryService.GetInstance(playerId: string, instanceId: string): any?
	local inv = playerDoctrines[playerId]
	if not inv then return nil end
	return inv[instanceId]
end

--------------------------------------------------
-- BINDING (equip / unequip reservation)
--------------------------------------------------

-- Bind an instance to a unit (reserve it). Does NOT touch the unit's derived
-- fields (caller mirrors doctrineId/selectedSkill onto the live unit).
function DoctrineInventoryService.Bind(playerId: string, instanceId: string, unitId: string): boolean
	local inst = DoctrineInventoryService.GetInstance(playerId, instanceId)
	if not inst then return false end
	inst.boundUnitId = unitId
	return true
end

-- Unbind an instance, returning it to the loose stash.
function DoctrineInventoryService.Unbind(playerId: string, instanceId: string): boolean
	local inst = DoctrineInventoryService.GetInstance(playerId, instanceId)
	if not inst then return false end
	inst.boundUnitId = nil
	return true
end

-- The instance currently bound to a unit (its equipped doctrine), or nil.
function DoctrineInventoryService.GetBoundInstance(playerId: string, unitId: string): any?
	local inv = playerDoctrines[playerId]
	if not inv then return nil end
	for _, inst in pairs(inv) do
		if inst.boundUnitId == unitId then
			return inst
		end
	end
	return nil
end

--------------------------------------------------
-- QUERY
--------------------------------------------------

-- All loose (unbound) instances — the pickable stash. Flat list.
function DoctrineInventoryService.GetLooseInstances(playerId: string): { any }
	local inv = playerDoctrines[playerId]
	if not inv then return {} end
	local out = {}
	for _, inst in pairs(inv) do
		if inst.boundUnitId == nil then
			table.insert(out, inst)
		end
	end
	return out
end

-- Loose stash grouped by doctrineId with a count and a representative instanceId
-- (consumables-style stacking for the picker). Returns:
--   { [doctrineId] = { count = N, instanceId = <one loose instanceId> } }
function DoctrineInventoryService.GetLooseStacks(playerId: string): { [string]: any }
	local stacks: { [string]: any } = {}
	for _, inst in ipairs(DoctrineInventoryService.GetLooseInstances(playerId)) do
		local s = stacks[inst.doctrineId]
		if s then
			s.count += 1
		else
			stacks[inst.doctrineId] = { count = 1, instanceId = inst.instanceId }
		end
	end
	return stacks
end

function DoctrineInventoryService.GetInstanceCount(playerId: string): number
	local inv = playerDoctrines[playerId]
	if not inv then return 0 end
	local count = 0
	for _ in pairs(inv) do
		count += 1
	end
	return count
end

--------------------------------------------------
-- LIFECYCLE: GUARANTEE A UNIT IS ALWAYS BOUND
--------------------------------------------------

-- Guarantee a unit has exactly one bound DoctrineInstance. Mints one from the unit's
-- content doctrineId if it has none — covers starters, recruits, and migration of
-- pre-instance saves (which stored only a content doctrineId). Idempotent: a valid
-- existing binding is left as-is, with its reverse link + selected skill refreshed
-- from the live unit. Called at Main's lifecycle choke points (boot establishment,
-- mid-session hire, post-battle refill).
function DoctrineInventoryService.EnsureUnitBound(playerId: string, unit: any)
	if type(unit) ~= "table" or type(unit.id) ~= "string" then return end
	local docId = unit.doctrineId
	if type(docId) ~= "string" then return end -- no doctrine to bind yet
	DoctrineInventoryService.InitPlayer(playerId)
	-- Already has a valid bound instance matching the unit's doctrine?
	local boundId = unit.doctrineInstanceId
	if type(boundId) == "string" then
		local inst = DoctrineInventoryService.GetInstance(playerId, boundId)
		if inst and inst.doctrineId == docId then
			inst.boundUnitId = unit.id
			if unit.selectedDoctrineSkill then inst.selectedSkillId = unit.selectedDoctrineSkill end
			return
		end
	end
	-- Adopt an instance already reverse-linked to this unit, if any.
	local existing = DoctrineInventoryService.GetBoundInstance(playerId, unit.id)
	if existing then
		existing.doctrineId = docId
		if unit.selectedDoctrineSkill then existing.selectedSkillId = unit.selectedDoctrineSkill end
		unit.doctrineInstanceId = existing.instanceId
		return
	end
	-- Mint a fresh bound instance (fresh unit / migration).
	local inst = DoctrineInventoryService.Mint(playerId, docId, unit.selectedDoctrineSkill, unit.id)
	unit.doctrineInstanceId = inst.instanceId
end

--------------------------------------------------
-- SERIALIZATION
--------------------------------------------------

function DoctrineInventoryService.ExportInventory(playerId: string): { [string]: any }
	return playerDoctrines[playerId] or {}
end

function DoctrineInventoryService.ImportInventory(playerId: string, data: any)
	DoctrineInventoryService.InitPlayer(playerId)
	playerDoctrines[playerId] = data or {}
end

return DoctrineInventoryService
