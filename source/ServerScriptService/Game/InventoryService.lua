-- InventoryService.lua
-- CTRBLXAI | Slice 4A — Equipment Foundation
--
-- In-memory item ownership. No DataStore yet (Slice 4C).
-- Server-authoritative: client cannot add/remove items.
--
-- Each player has a flat inventory of item instances keyed by instanceId.
-- Items may be "equipped" (assigned to a unit slot) or "unequipped" (loose).

local InventoryService = {}

--------------------------------------------------
-- STATE
--------------------------------------------------

-- playerInventories[playerId] = { [instanceId] = itemInstance }
local playerInventories = {}

--------------------------------------------------
-- PLAYER LIFECYCLE
--------------------------------------------------

function InventoryService.InitPlayer(playerId)
	if not playerInventories[playerId] then
		playerInventories[playerId] = {}
	end
end

function InventoryService.GetInventory(playerId)
	return playerInventories[playerId] or {}
end

function InventoryService.ClearPlayer(playerId)
	playerInventories[playerId] = nil
end

--------------------------------------------------
-- ITEM MANAGEMENT
--------------------------------------------------

function InventoryService.AddItem(playerId, itemInstance)
	assert(type(itemInstance) == "table", "AddItem: itemInstance must be a table.")
	assert(type(itemInstance.instanceId) == "string", "AddItem: instanceId required.")
	assert(type(playerId) == "string", "AddItem: playerId required.")

	InventoryService.InitPlayer(playerId)
	local inv = playerInventories[playerId]

	if inv[itemInstance.instanceId] then
		warn("[InventoryService] Duplicate instance: " .. itemInstance.instanceId)
		return false, "Duplicate instance ID"
	end

	inv[itemInstance.instanceId] = itemInstance
	print(string.format(
		"[InventoryService] Added %s to %s inventory (%d items)",
		itemInstance.instanceId, playerId, InventoryService.GetItemCount(playerId)
	))
	return true
end

function InventoryService.RemoveItem(playerId, instanceId)
	local inv = playerInventories[playerId]
	if not inv or not inv[instanceId] then
		return false, "Item not found"
	end
	inv[instanceId] = nil
	return true
end

function InventoryService.GetItem(playerId, instanceId)
	local inv = playerInventories[playerId]
	if not inv then return nil end
	return inv[instanceId]
end

function InventoryService.OwnsItem(playerId, instanceId)
	local inv = playerInventories[playerId]
	return inv and inv[instanceId] ~= nil
end

function InventoryService.GetItemCount(playerId)
	local inv = playerInventories[playerId]
	if not inv then return 0 end
	local count = 0
	for _ in pairs(inv) do
		count = count + 1
	end
	return count
end

--------------------------------------------------
-- QUERY
--------------------------------------------------

function InventoryService.GetUnequippedItems(playerId, unitLoadouts)
	-- Returns items not assigned to any unit's equipment slots
	local inv = playerInventories[playerId]
	if not inv then return {} end

	-- Build set of equipped instance IDs
	local equipped = {}
	if unitLoadouts then
		for _, loadout in pairs(unitLoadouts) do
			for _, slotItem in pairs(loadout) do
				if type(slotItem) == "table" and slotItem.instanceId then
					equipped[slotItem.instanceId] = true
				end
			end
		end
	end

	local unequipped = {}
	for instanceId, item in pairs(inv) do
		if not equipped[instanceId] then
			table.insert(unequipped, item)
		end
	end
	return unequipped
end

function InventoryService.GetAllItems(playerId)
	local inv = playerInventories[playerId]
	if not inv then return {} end
	local list = {}
	for _, item in pairs(inv) do
		table.insert(list, item)
	end
	return list
end

--------------------------------------------------
-- SERIALIZATION SUPPORT (for Slice 4C)
--------------------------------------------------

function InventoryService.ExportInventory(playerId)
	return playerInventories[playerId] or {}
end

function InventoryService.ImportInventory(playerId, data)
	InventoryService.InitPlayer(playerId)
	playerInventories[playerId] = data or {}
end

return InventoryService
