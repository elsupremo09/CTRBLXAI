--!strict
-- ScreenOrientation.client.lua
-- Locks the game to landscape on phones and tablets (user request 2026-11-19).
-- LandscapeSensor = either landscape side, follows how the device is held; portrait is never used.
-- Desktop ignores this property. Studio's device emulator does not apply it either; test on a real phone.

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui", 10) :: PlayerGui?

if playerGui then
	playerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
else
	warn("[ScreenOrientation] PlayerGui not found; landscape lock not applied")
end
