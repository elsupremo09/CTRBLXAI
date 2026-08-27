-- BattleHUD.lua
-- CTRBLXAI | Slice 7B — State-Machine-Driven Battle HUD
--
-- Architecture:
--   One ScreenGui → RootFrame with layout regions.
--   Explicit state machine controls panel visibility.
--   Left panel: actor + actions/skills + skill detail
--   Right panel: context OR target + damage preview
--   Top: timeline (centered)
--   Bottom: contextual confirm/back controls
--   Center: clear for battlefield
--
-- States:
--   Idle, ActionSelection, SkillSelection, TargetSelection, Preview, Resolving, BattleEnded

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local player = Players.LocalPlayer

local CTRBLXAI_UI  = ReplicatedStorage:WaitForChild("CTRBLXAI", 10):WaitForChild("UI", 10)
local Theme        = require(CTRBLXAI_UI:WaitForChild("Theme", 10))
local UIComponents = require(CTRBLXAI_UI:WaitForChild("UIComponents", 10))
local UIFormatting = require(CTRBLXAI_UI:WaitForChild("UIFormatting", 10))

local BattleHUD = {}

-- STATE ENUM
BattleHUD.States = {
	Idle = "Idle",
	ActionSelection = "ActionSelection",
	SkillSelection = "SkillSelection",
	TargetSelection = "TargetSelection",
	Preview = "Preview",
	Resolving = "Resolving",
	BattleEnded = "BattleEnded",
}

--------------------------------------------------
-- INTERNAL STATE
--------------------------------------------------

local currentState = "Idle"
local playerGui = nil

-- Layout instances (persistent across states)
local screenGui   = nil
local rootFrame   = nil
local leftRegion  = nil
local rightRegion = nil
local topRegion   = nil
local bottomRegion = nil

-- Sub-panels (created/destroyed per state)
local actorPanel       = nil
local stateIndicator   = nil
local actionListFrame  = nil
local skillDetailFrame = nil
local targetPanel      = nil
local contextPanel     = nil
local previewPanel     = nil
local timelineBar      = nil
local controlsFrame    = nil

-- Stored data for state transitions
local storedActorData  = nil
local storedTargetData = nil
local storedSkillData  = nil
local storedPreviewData = nil

--------------------------------------------------
-- RESPONSIVE LAYOUT
--------------------------------------------------

local LAYOUT_MODE = "Desktop" -- Desktop | Compact | Small

local LEFT_WIDTH = { Desktop = 280, Compact = 240, Small = 200 }
local RIGHT_WIDTH = { Desktop = 280, Compact = 250, Small = 200 }
local TIMELINE_HEIGHT = 56
local BOTTOM_HEIGHT = 52
local MARGIN = 12
local TOP_INSET = 36 -- Roblox top bar

local function getLayoutMode()
	local cam = workspace.CurrentCamera
	if not cam then return "Desktop" end
	local w = cam.ViewportSize.X
	if w < 900 then return "Small"
	elseif w < 1400 then return "Compact"
	end
	return "Desktop"
end

local function lw() return LEFT_WIDTH[LAYOUT_MODE] or 280 end
local function rw() return RIGHT_WIDTH[LAYOUT_MODE] or 280 end

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function getPlayerGui()
	if not playerGui then playerGui = player:WaitForChild("PlayerGui") end
	return playerGui
end

local function clearChildren(frame)
	if not frame then return end
	for _, child in ipairs(frame:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding")
			and not child:IsA("UICorner") and not child:IsA("UIStroke")
			and not child:IsA("UISizeConstraint") then
			child:Destroy()
		end
	end
end

local function makeLabel(props)
	local lbl = Instance.new("TextLabel")
	lbl.Size = props.size or UDim2.new(1, 0, 0, 16)
	lbl.BackgroundTransparency = 1
	lbl.BorderSizePixel = 0
	lbl.Font = props.font or Theme.Font.Primary
	lbl.TextSize = props.textSize or Theme.TextSize.sm
	lbl.TextColor3 = props.color or Theme.Colors.TextPrimary
	lbl.TextXAlignment = props.align or Enum.TextXAlignment.Left
	lbl.TextYAlignment = props.vAlign or Enum.TextYAlignment.Center
	lbl.TextWrapped = props.wrap or false
	lbl.RichText = props.rich or false
	lbl.Text = props.text or ""
	lbl.LayoutOrder = props.order or 0
	if props.parent then lbl.Parent = props.parent end
	return lbl
end

local function makeBar(parent, current, max, barColor, height, order)
	local ratio = (max and max > 0) and math.clamp((current or 0) / max, 0, 1) or 0
	local container = Instance.new("Frame")
	container.Size = UDim2.new(1, 0, 0, height or 12)
	container.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	container.BorderSizePixel = 0
	container.LayoutOrder = order or 0
	container.Parent = parent
	Instance.new("UICorner", container).CornerRadius = UDim.new(0, 3)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(ratio, 1)
	fill.BackgroundColor3 = barColor or Theme.Colors.HP
	fill.BorderSizePixel = 0
	fill.Parent = container
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 3)

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Theme.Font.PrimaryBold
	text.TextSize = math.max(height - 3, 9)
	text.TextColor3 = Theme.Colors.TextPrimary
	text.TextStrokeTransparency = 0.3
	text.Text = string.format("%d / %d", current or 0, max or 0)
	text.Parent = container

	return container
end

--------------------------------------------------
-- ROOT STRUCTURE CREATION
--------------------------------------------------

local function ensureRoot()
	if screenGui and screenGui.Parent then return end

	LAYOUT_MODE = getLayoutMode()

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BattleHUD"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = Theme.DisplayOrder.HUD
	screenGui.IgnoreGuiInset = false -- Use Roblox inset handling
	screenGui.Parent = getPlayerGui()

	rootFrame = Instance.new("Frame")
	rootFrame.Name = "Root"
	rootFrame.Size = UDim2.fromScale(1, 1)
	rootFrame.BackgroundTransparency = 1
	rootFrame.Parent = screenGui

	-- LEFT REGION
	leftRegion = Instance.new("Frame")
	leftRegion.Name = "LeftRegion"
	leftRegion.Size = UDim2.new(0, lw(), 1, -(TIMELINE_HEIGHT + BOTTOM_HEIGHT + MARGIN * 2))
	leftRegion.Position = UDim2.new(0, MARGIN, 0, TIMELINE_HEIGHT + MARGIN)
	leftRegion.BackgroundColor3 = Theme.Colors.Panel
	leftRegion.BackgroundTransparency = 0.03
	leftRegion.BorderSizePixel = 0
	leftRegion.ClipsDescendants = true
	leftRegion.Visible = false
	leftRegion.Parent = rootFrame
	Instance.new("UICorner", leftRegion).CornerRadius = Theme.CornerRadius.md
	local ls = Instance.new("UIStroke", leftRegion)
	ls.Color = Theme.Colors.Border; ls.Thickness = 1

	-- RIGHT REGION
	rightRegion = Instance.new("Frame")
	rightRegion.Name = "RightRegion"
	rightRegion.Size = UDim2.new(0, rw(), 1, -(TIMELINE_HEIGHT + BOTTOM_HEIGHT + MARGIN * 2))
	rightRegion.Position = UDim2.new(1, -(rw() + MARGIN), 0, TIMELINE_HEIGHT + MARGIN)
	rightRegion.BackgroundColor3 = Theme.Colors.Panel
	rightRegion.BackgroundTransparency = 0.03
	rightRegion.BorderSizePixel = 0
	rightRegion.ClipsDescendants = true
	rightRegion.Visible = false
	rightRegion.Parent = rootFrame
	Instance.new("UICorner", rightRegion).CornerRadius = Theme.CornerRadius.md
	local rs = Instance.new("UIStroke", rightRegion)
	rs.Color = Theme.Colors.Border; rs.Thickness = 1

	-- TOP REGION (timeline)
	topRegion = Instance.new("Frame")
	topRegion.Name = "TopRegion"
	topRegion.Size = UDim2.new(0.42, 0, 0, TIMELINE_HEIGHT)
	topRegion.Position = UDim2.new(0.5, 0, 0, 4)
	topRegion.AnchorPoint = Vector2.new(0.5, 0)
	topRegion.BackgroundTransparency = 1
	topRegion.Parent = rootFrame

	-- BOTTOM REGION (controls)
	bottomRegion = Instance.new("Frame")
	bottomRegion.Name = "BottomRegion"
	bottomRegion.Size = UDim2.new(0, 320, 0, BOTTOM_HEIGHT)
	bottomRegion.Position = UDim2.new(0.5, 0, 1, -(MARGIN + 4))
	bottomRegion.AnchorPoint = Vector2.new(0.5, 1)
	bottomRegion.BackgroundTransparency = 1
	bottomRegion.Visible = false
	bottomRegion.Parent = rootFrame
end

--------------------------------------------------
-- STATE MACHINE
--------------------------------------------------

local STATE_TITLES = {
	ActionSelection = { "SELECT ACTION", "Choose an action." },
	SkillSelection  = { "SELECT SKILL", "Choose a skill to use." },
	TargetSelection = { "SELECT TARGET", "Choose a valid target within range." },
	Preview         = { "PREVIEW", "Review the predicted result." },
	Resolving       = { "RESOLVING", "Action in progress." },
}

function BattleHUD.SetState(newState)
	currentState = newState
	ensureRoot()

	-- Visibility per state
	local showLeft = newState == "ActionSelection" or newState == "SkillSelection"
		or newState == "TargetSelection" or newState == "Preview"
	local showRight = newState == "TargetSelection" or newState == "Preview"
	local showBottom = newState == "TargetSelection" or newState == "Preview"

	leftRegion.Visible = showLeft
	rightRegion.Visible = showRight
	bottomRegion.Visible = showBottom

	-- Rebuild panels for this state
	BattleHUD._buildLeftPanel()
	BattleHUD._buildRightPanel()
	BattleHUD._buildBottomControls()
end

function BattleHUD.GetState()
	return currentState
end

--------------------------------------------------
-- LEFT PANEL BUILDER
--------------------------------------------------

function BattleHUD._buildLeftPanel()
	if not leftRegion then return end
	clearChildren(leftRegion)

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = leftRegion

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = leftRegion

	-- State indicator
	local titleData = STATE_TITLES[currentState]
	if titleData then
		makeLabel({ text = titleData[1], font = Theme.Font.PrimaryBold, textSize = 15,
			color = Theme.Colors.TextPrimary, order = 0, parent = leftRegion })
		makeLabel({ text = titleData[2], textSize = 10,
			color = Theme.Colors.TextSecondary, order = 1, parent = leftRegion })
	end

	-- Actor summary (always in left)
	if storedActorData then
		BattleHUD._renderActorSummary(leftRegion, 10)
	end

	-- State-specific content
	if currentState == "ActionSelection" then
		BattleHUD._renderActionMenu(leftRegion, 100)
	elseif currentState == "SkillSelection" then
		BattleHUD._renderSkillList(leftRegion, 100)
	elseif currentState == "TargetSelection" or currentState == "Preview" then
		BattleHUD._renderSkillInfo(leftRegion, 100)
	end
end

function BattleHUD._renderActorSummary(parent, baseOrder)
	local d = storedActorData
	if not d then return end

	-- Divider
	local div = Instance.new("Frame")
	div.Size = UDim2.new(1, 0, 0, 1)
	div.BackgroundColor3 = Theme.Colors.Border
	div.BorderSizePixel = 0
	div.LayoutOrder = baseOrder
	div.Parent = parent

	-- Name + side
	makeLabel({ text = d.name or "Unit", font = Theme.Font.PrimaryBold, textSize = 14,
		color = Theme.GetSideColor(d.side), order = baseOrder + 1, parent = parent })

	-- HP bar
	makeBar(parent, d.currentHp, d.maxHp, Theme.GetHPColor(
		d.maxHp > 0 and d.currentHp / d.maxHp or 0), 13, baseOrder + 2)

	-- MP bar
	makeBar(parent, d.currentMp, d.maxMp, Theme.Colors.MP, 10, baseOrder + 3)

	-- AP + RT row
	makeLabel({ text = string.format("AP %d    RT %d", d.currentAp or 0, d.remainingRt or 0),
		font = Theme.Font.Mono, textSize = 10, color = Theme.Colors.TextSecondary,
		order = baseOrder + 4, parent = parent })

	-- View Full Stats button (opens 3-tab inspector)
	local viewBtn = Instance.new("TextButton")
	viewBtn.Size = UDim2.new(1, 0, 0, 20)
	viewBtn.BackgroundColor3 = Theme.Colors.Surface
	viewBtn.BackgroundTransparency = 0.4
	viewBtn.BorderSizePixel = 0
	viewBtn.Font = Theme.Font.Primary
	viewBtn.TextSize = 10
	viewBtn.TextColor3 = Theme.Colors.TextSecondary
	viewBtn.Text = "  View Full Stats"
	viewBtn.TextXAlignment = Enum.TextXAlignment.Left
	viewBtn.LayoutOrder = baseOrder + 5
	viewBtn.Parent = parent
	Instance.new("UICorner", viewBtn).CornerRadius = Theme.CornerRadius.sm
	viewBtn.MouseButton1Click:Connect(function()
		if _G.CTRBLXAI_OpenInspectorPanel and d.id then
			_G.CTRBLXAI_OpenInspectorPanel(d.id)
		end
	end)
end

function BattleHUD._renderActionMenu(parent, baseOrder)
	local actions = storedActorData and storedActorData.actions or {}
	for i, action in ipairs(actions) do
		local enabled = action.enabled ~= false
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 0, 28)
		btn.BackgroundColor3 = Theme.Colors.Surface
		btn.BackgroundTransparency = enabled and 0.4 or 0.7
		btn.BorderSizePixel = 0
		btn.Font = Theme.Font.Primary
		btn.TextSize = 13
		btn.TextColor3 = enabled and Theme.Colors.TextPrimary or Theme.Colors.TextDisabled
		btn.TextXAlignment = Enum.TextXAlignment.Left
		btn.Text = "  " .. (action.text or "?")
		btn.AutoButtonColor = enabled
		btn.Active = enabled
		btn.LayoutOrder = baseOrder + i
		btn.Parent = parent
		Instance.new("UICorner", btn).CornerRadius = Theme.CornerRadius.sm

		if enabled and action.onPress then
			btn.MouseButton1Click:Connect(action.onPress)
		end
	end
end

function BattleHUD._renderSkillList(parent, baseOrder)
	local skills = storedActorData and storedActorData.skillEntries or {}

	-- Header row
	makeLabel({ text = "Skill                    MP   RT", font = Theme.Font.Mono,
		textSize = 10, color = Theme.Colors.TextSecondary, order = baseOrder, parent = parent })

	-- Scrollable container
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, 0, 1, -180) -- fill remaining
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 3
	scroll.ScrollBarImageColor3 = Theme.Colors.Border
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.LayoutOrder = baseOrder + 1
	scroll.Parent = parent

	local sLayout = Instance.new("UIListLayout")
	sLayout.Padding = UDim.new(0, 2)
	sLayout.Parent = scroll

	for i, skill in ipairs(skills) do
		local enabled = skill.enabled ~= false
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 0, 26)
		btn.BackgroundColor3 = Theme.Colors.Surface
		btn.BackgroundTransparency = enabled and 0.5 or 0.8
		btn.BorderSizePixel = 0
		btn.Font = Theme.Font.Primary
		btn.TextSize = 12
		btn.TextColor3 = enabled and Theme.Colors.TextPrimary or Theme.Colors.TextDisabled
		btn.TextXAlignment = Enum.TextXAlignment.Left
		btn.Text = string.format("  %-18s %3d  %3d",
			UIFormatting.Truncate(skill.name or "?", 16), skill.mpCost or 0, skill.rtCost or 0)
		btn.AutoButtonColor = enabled
		btn.Active = enabled
		btn.LayoutOrder = i
		btn.Parent = scroll
		Instance.new("UICorner", btn).CornerRadius = Theme.CornerRadius.sm

		if enabled and skill.onPress then
			btn.MouseButton1Click:Connect(skill.onPress)
		end
	end
end

function BattleHUD._renderSkillInfo(parent, baseOrder)
	local s = storedSkillData
	if not s then return end

	local div = Instance.new("Frame")
	div.Size = UDim2.new(1, 0, 0, 1)
	div.BackgroundColor3 = Theme.Colors.Border
	div.BorderSizePixel = 0
	div.LayoutOrder = baseOrder
	div.Parent = parent

	makeLabel({ text = s.name or "Skill", font = Theme.Font.PrimaryBold, textSize = 13,
		color = Theme.Colors.TextPrimary, order = baseOrder + 1, parent = parent })

	if s.tags then
		makeLabel({ text = s.tags, textSize = 9,
			color = Theme.Colors.TextSecondary, order = baseOrder + 2, parent = parent })
	end

	-- Stats grid
	local statsText = ""
	if (s.mpCost or 0) > 0 then statsText = statsText .. "MP Cost  " .. s.mpCost .. "\n" end
	statsText = statsText .. "RT Cost  " .. (s.rtCost or 0) .. "\n"
	statsText = statsText .. "Range    " .. (s.range or 1) .. "\n"
	statsText = statsText .. "Area     " .. (s.pattern or "Single")
	if s.channelTime and s.channelTime > 0 then
		statsText = statsText .. "\nChannel  " .. s.channelTime .. " CT"
	end

	makeLabel({ text = statsText, font = Theme.Font.Mono, textSize = 10,
		color = Theme.Colors.TextPrimary, size = UDim2.new(1, 0, 0, 56),
		vAlign = Enum.TextYAlignment.Top, wrap = true,
		order = baseOrder + 3, parent = parent })

	-- Description / effects
	if s.effects and s.effects ~= "" then
		makeLabel({ text = "EFFECT", font = Theme.Font.PrimaryBold, textSize = 9,
			color = Theme.Colors.Success, order = baseOrder + 4, parent = parent })
		makeLabel({ text = s.effects, textSize = 11, wrap = true,
			size = UDim2.new(1, 0, 0, 28), vAlign = Enum.TextYAlignment.Top,
			color = Theme.Colors.TextPrimary, order = baseOrder + 5, parent = parent })
	end
end

--------------------------------------------------
-- RIGHT PANEL BUILDER
--------------------------------------------------

function BattleHUD._buildRightPanel()
	if not rightRegion then return end
	clearChildren(rightRegion)

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = rightRegion

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = rightRegion

	if currentState == "TargetSelection" then
		BattleHUD._renderTargetInfo(rightRegion, 0)
	elseif currentState == "Preview" then
		BattleHUD._renderTargetInfo(rightRegion, 0)
		BattleHUD._renderDamagePreview(rightRegion, 50)
	end
end

function BattleHUD._renderTargetInfo(parent, baseOrder)
	local d = storedTargetData
	if not d then
		makeLabel({ text = "Select a target", color = Theme.Colors.TextDisabled,
			order = baseOrder, parent = parent })
		return
	end

	makeLabel({ text = d.name or "Target", font = Theme.Font.PrimaryBold, textSize = 14,
		color = Theme.GetSideColor(d.side), order = baseOrder, parent = parent })

	-- HP bar
	makeBar(parent, d.currentHp, d.maxHp, Theme.GetHPColor(
		d.maxHp > 0 and d.currentHp / d.maxHp or 0), 13, baseOrder + 1)

	-- MP bar
	if (d.maxMp or 0) > 0 then
		makeBar(parent, d.currentMp, d.maxMp, Theme.Colors.MP, 10, baseOrder + 2)
	end

	-- AP
	makeLabel({ text = string.format("AP %d    RT %d", d.currentAp or 0, d.remainingRt or 0),
		font = Theme.Font.Mono, textSize = 10, color = Theme.Colors.TextSecondary,
		order = baseOrder + 3, parent = parent })

	-- Statuses
	if d.statuses and #d.statuses > 0 then
		local statusText = "Status: "
		for _, s in ipairs(d.statuses) do
			statusText = statusText .. s.id .. "(" .. (s.remainingTurns or "?") .. ") "
		end
		makeLabel({ text = statusText, textSize = 9,
			color = Theme.Colors.Warning, order = baseOrder + 4, parent = parent })
	end
end

function BattleHUD._renderDamagePreview(parent, baseOrder)
	local d = storedPreviewData
	if not d then return end

	local div = Instance.new("Frame")
	div.Size = UDim2.new(1, 0, 0, 1)
	div.BackgroundColor3 = Theme.Colors.Border
	div.BorderSizePixel = 0
	div.LayoutOrder = baseOrder
	div.Parent = parent

	makeLabel({ text = "DAMAGE PREVIEW", font = Theme.Font.PrimaryBold, textSize = 10,
		color = Theme.Colors.TextSecondary, order = baseOrder + 1, parent = parent })

	-- Big damage number
	local isHeal = d.isHealing or false
	local dmgText = (isHeal and "+" or "-") .. tostring(d.estimatedDamage or 0)
	makeLabel({ text = dmgText, font = Theme.Font.PrimaryBold, textSize = 28,
		color = isHeal and Theme.Colors.Success or Theme.Colors.Danger,
		size = UDim2.new(1, 0, 0, 32), order = baseOrder + 2, parent = parent })

	-- HP after
	if d.hpAfter then
		makeLabel({ text = "HP After: " .. d.hpAfter, textSize = 11,
			color = Theme.Colors.TextPrimary, order = baseOrder + 3, parent = parent })
	end

	-- RT effect
	if d.rtDelay and d.rtDelay > 0 then
		makeLabel({ text = "RT Delay: +" .. d.rtDelay, textSize = 11,
			color = Theme.Colors.Warning, order = baseOrder + 4, parent = parent })
	end

	-- Status effect
	local statusText = d.statusEffect or "None"
	makeLabel({ text = "Status: " .. statusText, textSize = 11,
		color = Theme.Colors.TextPrimary, order = baseOrder + 5, parent = parent })

	-- MP spent by actor
	if d.mpSpent and d.mpSpent > 0 then
		makeLabel({ text = "MP Spent: " .. d.mpSpent, textSize = 10,
			color = Theme.Colors.MP, order = baseOrder + 6, parent = parent })
	end
end

--------------------------------------------------
-- BOTTOM CONTROLS
--------------------------------------------------

function BattleHUD._buildBottomControls()
	if not bottomRegion then return end
	clearChildren(bottomRegion)
	bottomRegion.Visible = false

	if currentState ~= "SkillSelection" and currentState ~= "TargetSelection" and currentState ~= "Preview" then return end
	bottomRegion.Visible = true

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Theme.Colors.Panel
	frame.BackgroundTransparency = 0.05
	frame.BorderSizePixel = 0
	frame.Parent = bottomRegion
	Instance.new("UICorner", frame).CornerRadius = Theme.CornerRadius.md
	local s = Instance.new("UIStroke", frame)
	s.Color = Theme.Colors.Border; s.Thickness = 1

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 16)
	layout.Parent = frame

	if currentState == "Preview" and storedPreviewData and storedPreviewData.onConfirm then
		local confirmBtn = Instance.new("TextButton")
		confirmBtn.Size = UDim2.fromOffset(120, 36)
		confirmBtn.BackgroundColor3 = Theme.Colors.Success
		confirmBtn.BackgroundTransparency = 0.1
		confirmBtn.Font = Theme.Font.PrimaryBold
		confirmBtn.TextSize = 14
		confirmBtn.TextColor3 = Theme.Colors.TextPrimary
		confirmBtn.Text = "Confirm"
		confirmBtn.BorderSizePixel = 0
		confirmBtn.Parent = frame
		Instance.new("UICorner", confirmBtn).CornerRadius = Theme.CornerRadius.sm
		confirmBtn.MouseButton1Click:Connect(function()
			confirmBtn.Active = false
			confirmBtn.BackgroundTransparency = 0.5
			if storedPreviewData.onConfirm then storedPreviewData.onConfirm() end
		end)
	end

	if currentState == "SkillSelection" or currentState == "TargetSelection" or currentState == "Preview" then
		local backBtn = Instance.new("TextButton")
		backBtn.Size = UDim2.fromOffset(100, 36)
		backBtn.BackgroundColor3 = Theme.Colors.Surface
		backBtn.BackgroundTransparency = 0.2
		backBtn.Font = Theme.Font.PrimaryBold
		backBtn.TextSize = 14
		backBtn.TextColor3 = Theme.Colors.TextSecondary
		backBtn.Text = "Back"
		backBtn.BorderSizePixel = 0
		backBtn.Parent = frame
		Instance.new("UICorner", backBtn).CornerRadius = Theme.CornerRadius.sm
		if storedPreviewData and storedPreviewData.onBack then
			backBtn.MouseButton1Click:Connect(storedPreviewData.onBack)
		elseif storedActorData and storedActorData.onBack then
			backBtn.MouseButton1Click:Connect(storedActorData.onBack)
		end
	end
end

--------------------------------------------------
-- TIMELINE (top-center)
--------------------------------------------------

function BattleHUD.UpdateTimeline(entries)
	ensureRoot()
	clearChildren(topRegion)
	if not entries or #entries == 0 then return end

	local bar = Instance.new("Frame")
	bar.Name = "TimelineBar"
	bar.Size = UDim2.fromScale(1, 1)
	bar.BackgroundColor3 = Theme.Colors.Panel
	bar.BackgroundTransparency = 0.05
	bar.BorderSizePixel = 0
	bar.Parent = topRegion
	Instance.new("UICorner", bar).CornerRadius = Theme.CornerRadius.md
	local s = Instance.new("UIStroke", bar)
	s.Color = Theme.Colors.Border; s.Thickness = 1

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 3)
	layout.Parent = bar

	local slotCount = #entries
	for i, entry in ipairs(entries) do
		local isActive = entry.isActive or false
		local isRound = entry.isRound or false
		local slotW = isActive and 46 or (isRound and 20 or 36)
		local slotH = isActive and 42 or 34

		local portrait = Instance.new("TextButton")
		portrait.Size = UDim2.fromOffset(slotW, slotH)
		portrait.BorderSizePixel = 0
		portrait.Text = ""
		portrait.AutoButtonColor = false
		portrait.LayoutOrder = slotCount - i + 1
		portrait.Parent = bar

		if isRound then
			portrait.BackgroundColor3 = Color3.fromRGB(50, 50, 30)
			portrait.BackgroundTransparency = 0.4
		elseif isActive then
			portrait.BackgroundColor3 = Theme.GetSideColor(entry.side)
			portrait.BackgroundTransparency = 0
		else
			portrait.BackgroundColor3 = Theme.GetSideColor(entry.side)
			portrait.BackgroundTransparency = 0.4
		end
		Instance.new("UICorner", portrait).CornerRadius = Theme.CornerRadius.sm

		if isActive then
			local st = Instance.new("UIStroke", portrait)
			st.Color = Theme.Colors.BorderFocused; st.Thickness = 2
		end

		-- Name
		local nameL = Instance.new("TextLabel")
		nameL.Size = UDim2.fromScale(1, 0.6)
		nameL.Position = UDim2.new(0, 0, 0, 2)
		nameL.BackgroundTransparency = 1
		nameL.Font = Theme.Font.PrimaryBold
		nameL.TextSize = isActive and 11 or 9
		nameL.TextColor3 = Theme.Colors.TextPrimary
		nameL.Text = isRound and (entry.name or "") or string.sub(entry.name or "?", 1, isActive and 5 or 3)
		nameL.Parent = portrait

		-- Bottom RT
		local bottomL = Instance.new("TextLabel")
		bottomL.Size = UDim2.new(1, 0, 0, 10)
		bottomL.Position = UDim2.new(0, 0, 1, -11)
		bottomL.BackgroundTransparency = 1
		bottomL.Font = Theme.Font.Primary
		bottomL.TextSize = 8
		bottomL.TextColor3 = Theme.Colors.TextSecondary
		bottomL.Text = isActive and "NOW" or (entry.rt and tostring(entry.rt) or "")
		bottomL.Parent = portrait

		if entry.onClick and not isRound then
			portrait.MouseButton1Click:Connect(entry.onClick)
		end
	end
end

--------------------------------------------------
-- PUBLIC DATA SETTERS
--------------------------------------------------

function BattleHUD.SetActorData(data)
	storedActorData = data
end

function BattleHUD.SetTargetData(data)
	storedTargetData = data
end

function BattleHUD.SetSkillData(data)
	storedSkillData = data
end

function BattleHUD.SetPreviewData(data)
	storedPreviewData = data
end

--------------------------------------------------
-- CONVENIENCE API (called by BattleVisualClient)
--------------------------------------------------

function BattleHUD.ShowActorCard(data)
	storedActorData = data
end

function BattleHUD.HideActorCard()
	storedActorData = nil
end

function BattleHUD.ShowActionMenu() end -- handled by state
function BattleHUD.HideActionMenu() end
function BattleHUD.ShowSkillList() end
function BattleHUD.HideSkillList() end
function BattleHUD.ShowSkillDetail() end
function BattleHUD.HideSkillDetail() end
function BattleHUD.ShowTargetCard(data) storedTargetData = data end
function BattleHUD.HideTargetCard() storedTargetData = nil end
function BattleHUD.ShowConfirmBar() end
function BattleHUD.HideConfirmBar() end
function BattleHUD.ShowDamagePreview(data) storedPreviewData = data end
function BattleHUD.HideDamagePreview() storedPreviewData = nil end
function BattleHUD.ShowPhase() end
function BattleHUD.HidePhase() end
function BattleHUD.HideActionBar() end
function BattleHUD.HideTooltip() end
function BattleHUD.ShowTileInfo() end
function BattleHUD.HideTileInfo() end
function BattleHUD.UpdateBattleState() end

function BattleHUD.GetInspectedUnitId()
	return storedActorData and storedActorData.id or nil
end

--------------------------------------------------
-- CLEANUP
--------------------------------------------------

function BattleHUD.Cleanup()
	currentState = "Idle"
	storedActorData = nil
	storedTargetData = nil
	storedSkillData = nil
	storedPreviewData = nil
	if screenGui then screenGui:Destroy(); screenGui = nil end
	rootFrame = nil
	leftRegion = nil
	rightRegion = nil
	topRegion = nil
	bottomRegion = nil
end

return BattleHUD
