--!strict
-- DungeonLoading.lua
-- CTRBLXAI | Battle loading panel for dungeon rooms (user 2026-11-17 10:50 AM: "choosing a battle node
-- causes a weird blink and players can't tell if choice was acknowledged").
-- Shown the moment a dungeon battle is launched (battle / Elite / Boss room, a "?" that turns into a
-- fight, after a Boss pick) and kept up until the battle's deployment starts, so the guild-menu
-- hand-off and map build underneath are hidden. Text: the existing in-game embark phrases
-- ("Scouting the area..." etc., GuildMenu EMBARK_PHRASES) passed in by the caller. No new text.
-- Safety: hides itself after TIMEOUT seconds whatever happens.

local WAIT = 10
local Players = game:GetService("Players")
local uiFolder = script.Parent
local Theme: any = (require :: any)(uiFolder:WaitForChild("Theme", WAIT))
local GuildScreen: any = (require :: any)(uiFolder:WaitForChild("GuildScreen", WAIT))

local DungeonLoading = {}

local TIMEOUT = 30          -- seconds; matches GuildMenu DUNGEON_DEPART_TIMEOUT
local STEP = 1.1            -- seconds per phrase
local BACKDROP = 0.12       -- near-opaque: the map / guild hand-off under it doesn't flash

local gui: ScreenGui? = nil
local token = 0

local function ensureGui(): ScreenGui?
	if gui and gui.Parent then return gui end
	local player = Players.LocalPlayer
	local pg = player and player:FindFirstChild("PlayerGui")
	if not pg then return nil end
	local g = Instance.new("ScreenGui")
	g.Name = "DungeonLoading"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 95 -- above the guild menu, Dungeon screen and popups
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.Enabled = false
	g.Parent = pg
	gui = g
	return g
end

function DungeonLoading.IsShown(): boolean
	local g = gui
	return g ~= nil and g.Enabled
end

--- phrases: existing approved lines (shown with "..."); the first shows at once, then they rotate.
function DungeonLoading.Show(phrases: { string })
	local g = ensureGui()
	if not g then return end
	token += 1
	local my = token
	g:ClearAllChildren()
	local o, box = GuildScreen.MakeModalBox("Loading", { maxW = 360, widthScale = 0.6, pad = 16 })
	o.BackgroundTransparency = BACKDROP
	local lbl = Instance.new("TextLabel")
	lbl.Name = "Text"
	lbl.BackgroundTransparency = 1
	lbl.BorderSizePixel = 0
	lbl.Font = Theme.Font.PrimaryBold
	lbl.TextSize = math.max(12, Theme.Text.Body())
	lbl.TextColor3 = Theme.Colors.TextGold
	lbl.TextWrapped = true
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	lbl.Size = UDim2.new(1, 0, 0, 44)
	lbl.ZIndex = 22
	lbl.Text = (phrases[1] or "") .. "..."
	lbl.Parent = box
	o.Parent = g -- parent last (NET-004)
	g.Enabled = true
	if #phrases > 1 then
		task.spawn(function()
			local i = 1
			while my == token and g.Enabled do
				task.wait(STEP)
				if my ~= token then return end
				i = (i % #phrases) + 1
				lbl.Text = phrases[i] .. "..."
			end
		end)
	end
	task.delay(TIMEOUT, function()
		if my == token then
			warn(`[DungeonLoading] still loading after {TIMEOUT} s -- panel closed`)
			DungeonLoading.Hide()
		end
	end)
end

function DungeonLoading.Hide()
	token += 1
	local g = gui
	if g then
		g.Enabled = false
		g:ClearAllChildren()
	end
end

return table.freeze(DungeonLoading)
