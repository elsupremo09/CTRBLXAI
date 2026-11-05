-- LoadoutController.client.lua
-- CTRBLXAI | Slice 7 — Entry point for Equipment Loadout Screen

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local CTRBLXAI = ReplicatedStorage:WaitForChild("CTRBLXAI", 30)
if not CTRBLXAI then warn("[LoadoutController] CTRBLXAI folder not found"); return end
local UI = CTRBLXAI:WaitForChild("UI", 30)
if not UI then warn("[LoadoutController] UI folder not found"); return end

-- Try LoadoutScreen
local loadoutModule = UI:FindFirstChild("LoadoutScreen")
if not loadoutModule then
	-- Also try WaitForChild with shorter timeout
	loadoutModule = UI:WaitForChild("LoadoutScreen", 5)
end

if not loadoutModule then
	-- Only list the UI folder when the module is actually missing (diagnostic, LOG-002).
	local names = {}
	for _, child in UI:GetChildren() do
		table.insert(names, `{child.Name} ({child.ClassName})`)
	end
	warn(`[LoadoutController] LoadoutScreen not found in UI folder. Contents: {table.concat(names, ", ")}`)
	return
end

local ok, LoadoutScreen = pcall(require, loadoutModule)
if not ok then warn("[LoadoutController] Failed to require LoadoutScreen:", LoadoutScreen); return end

_G.CTRBLXAI_OpenLoadout = function() LoadoutScreen.Show() end
_G.CTRBLXAI_CloseLoadout = function() LoadoutScreen.Hide() end
_G.CTRBLXAI_ToggleLoadout = function() LoadoutScreen.Toggle() end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.L then LoadoutScreen.Toggle() end
end)

print("[CTRBLXAI] LoadoutController initialized — press L to toggle loadout")
