-- LoadoutController.client.lua
-- CTRBLXAI | Slice 7 — Entry point for Equipment Loadout Screen

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local CTRBLXAI = ReplicatedStorage:WaitForChild("CTRBLXAI", 30)
if not CTRBLXAI then warn("[LoadoutController] CTRBLXAI folder not found"); return end
local UI = CTRBLXAI:WaitForChild("UI", 30)
if not UI then warn("[LoadoutController] UI folder not found"); return end

-- DEBUG: List all children of UI folder
print("[LoadoutController] UI folder children:")
for _, child in ipairs(UI:GetChildren()) do
	print("  ", child.Name, child.ClassName)
end

-- Try test module first
local testModule = UI:FindFirstChild("LoadoutScreenTest")
if testModule then
	print("[LoadoutController] TEST MODULE FOUND — Rojo syncs new files OK")
else
	print("[LoadoutController] TEST MODULE NOT FOUND — Rojo is NOT syncing new files")
end

-- Try LoadoutScreen
local loadoutModule = UI:FindFirstChild("LoadoutScreen")
if not loadoutModule then
	-- Also try WaitForChild with shorter timeout
	loadoutModule = UI:WaitForChild("LoadoutScreen", 5)
end

if not loadoutModule then
	warn("[LoadoutController] LoadoutScreen not found in UI folder. Contents listed above.")
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
