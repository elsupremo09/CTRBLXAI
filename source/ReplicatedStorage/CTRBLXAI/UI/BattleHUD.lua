-- BattleHUD.lua
-- CTRBLXAI | Slice 7D — Percentage-Based Battle HUD (Complete Redesign)
--
-- Layout (all sizes in screen %):
--   Upper-Left:  Active Unit Panel     (20% W × 25% H)
--   Left:        Action Panel / Skill Detail  (20% W × 15% H)
--   Upper-Right: Inspector Panel       (20% W × 25% H)
--   Right:       Tile/Preview Panel    (20% W × 15% H)
--   Lower-Left:  Turn Order Bar        (45% W × 7% H)
--   Adjacent:    Round/Conditions      (auto)
--   Lower-Right: Battle Log            (25% W × 20% H)
--
-- Phases:
--   1: ActionSelection (action grid, browse map)
--   2: TargetSelection (action detail + back)
--   3: Preview (target + damage preview + confirm/back)
--   4: Resolving (visual effects + battle log)

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local player = Players.LocalPlayer

local CTRBLXAI_UI = ReplicatedStorage:WaitForChild("CTRBLXAI", 10):WaitForChild("UI", 10)
local Theme       = require(CTRBLXAI_UI:WaitForChild("Theme", 10))

local BattleHUD = {}

-- State
local currentState = "Idle"
local screenGui, rootFrame = nil, nil

-- Region frames (persistent, content swaps per state)
local activeUnitPanel   = nil  -- Upper-left (20% × 25%)
local actionPanel       = nil  -- Left below active (20% × 15%)
local inspectorPanel    = nil  -- Upper-right (20% × 25%)
local tilePreviewPanel  = nil  -- Right below inspector (20% × 15%)
local turnOrderBar      = nil  -- Lower-left (45% × 7%)
local conditionsPanel   = nil  -- Next to turn order
local battleLogPanel    = nil  -- Lower-right (25% × 20%)

-- Stored data
local actorData       = nil
local targetData      = nil
local skillData       = nil
local previewData     = nil
local tileData        = nil
local objectData      = nil
local battleLog       = {}

-- Padding constant
local PAD = 6

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function getPlayerGui()
	return player:WaitForChild("PlayerGui")
end

local function clearFrame(frame)
	if not frame then return end
	for _, child in ipairs(frame:GetChildren()) do
		if not child:IsA("UICorner") and not child:IsA("UIStroke") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function makePanel(name, size, position, anchor, parent, opts)
	opts = opts or {}
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = position
	f.AnchorPoint = anchor or Vector2.new(0, 0)
	f.BackgroundColor3 = Theme.Colors.Panel
	f.BackgroundTransparency = 0.04
	f.BorderSizePixel = 0
	f.Active = true  -- Blocks input from passing through to battlefield
	f.ClipsDescendants = not opts.autoY  -- don't clip if auto-sizing
	f.Parent = parent
	Instance.new("UICorner", f).CornerRadius = Theme.CornerRadius.md
	local s = Instance.new("UIStroke", f)
	s.Color = Theme.Colors.Border; s.Thickness = 1

	-- AutomaticSize + constraints
	if opts.autoY then
		f.AutomaticSize = Enum.AutomaticSize.Y
		local constraint = Instance.new("UISizeConstraint", f)
		constraint.MinSize = Vector2.new(opts.minW or 240, opts.minH or 60)
		constraint.MaxSize = Vector2.new(opts.maxW or 340, opts.maxH or 400)
	end
	return f
end

local function makeLabel(parent, text, props)
	local lbl = Instance.new("TextLabel")
	lbl.Size = props.size or UDim2.new(1, 0, 0, 16)
	lbl.Position = props.pos or UDim2.new(0, 0, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.BorderSizePixel = 0
	lbl.Font = props.font or Theme.Font.Primary
	lbl.TextSize = props.textSize or 12
	lbl.TextColor3 = props.color or Theme.Colors.TextPrimary
	lbl.TextXAlignment = props.align or Enum.TextXAlignment.Left
	lbl.TextYAlignment = props.vAlign or Enum.TextYAlignment.Center
	lbl.TextWrapped = props.wrap or false
	lbl.Text = text or ""
	lbl.LayoutOrder = props.order or 0
	lbl.Parent = parent
	return lbl
end

local function makeButton(parent, text, props)
	local btn = Instance.new("TextButton")
	btn.Size = props.size or UDim2.new(0.5, -3, 0.5, -3)
	btn.Position = props.pos or UDim2.new(0, 0, 0, 0)
	btn.BackgroundColor3 = props.enabled ~= false and Theme.Colors.Surface or Theme.Colors.Panel
	btn.BackgroundTransparency = props.enabled ~= false and 0.3 or 0.7
	btn.BorderSizePixel = 0
	btn.Font = Theme.Font.Primary
	btn.TextSize = props.textSize or 11
	btn.TextColor3 = props.enabled ~= false and Theme.Colors.TextPrimary or Theme.Colors.TextDisabled
	btn.Text = text or ""
	btn.AutoButtonColor = props.enabled ~= false
	btn.Active = props.enabled ~= false
	btn.LayoutOrder = props.order or 0
	btn.Parent = parent
	Instance.new("UICorner", btn).CornerRadius = Theme.CornerRadius.sm
	if props.enabled ~= false and props.onPress then
		btn.MouseButton1Click:Connect(props.onPress)
	end
	return btn
end

--------------------------------------------------
-- ROOT CREATION
--------------------------------------------------

local function ensureRoot()
	if screenGui and screenGui.Parent then return end

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BattleHUD"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = Theme.DisplayOrder.HUD
	screenGui.IgnoreGuiInset = false
	screenGui.Parent = getPlayerGui()

	rootFrame = Instance.new("Frame")
	rootFrame.Name = "Root"
	rootFrame.Size = UDim2.fromScale(1, 1)
	rootFrame.BackgroundTransparency = 1
	rootFrame.Parent = screenGui

	-- UPPER-LEFT: Active Unit Panel (20% W × 25% H)
	activeUnitPanel = makePanel("ActiveUnit",
		UDim2.new(0.20, 0, 0, 0),  -- width=20% screen, height=auto
		UDim2.new(0, PAD, 0, PAD), Vector2.new(0, 0), rootFrame,
		{ autoY = true, minW = 240, maxW = 340, minH = 60, maxH = 220 })
	activeUnitPanel.Visible = false

	-- LEFT: Action Panel (20% W, height fits content) — below active unit
	actionPanel = makePanel("ActionPanel",
		UDim2.new(0.20, 0, 0, 0),  -- width=20%, height=auto
		UDim2.new(0, PAD, 0, 0), Vector2.new(0, 0), rootFrame,
		{ autoY = true, minW = 240, maxW = 340, minH = 50, maxH = 200 })
	actionPanel.Visible = false

	-- UPPER-RIGHT: Inspector Panel (20% W, height fits content)
	inspectorPanel = makePanel("Inspector",
		UDim2.new(0.20, 0, 0, 0),
		UDim2.new(1, -PAD, 0, PAD), Vector2.new(1, 0), rootFrame,
		{ autoY = true, minW = 240, maxW = 340, minH = 60, maxH = 220 })
	inspectorPanel.Visible = false

	-- RIGHT: Tile/Preview Panel (20% W, height fits content)
	tilePreviewPanel = makePanel("TilePreview",
		UDim2.new(0.20, 0, 0, 0),
		UDim2.new(1, -PAD, 0, 0), Vector2.new(1, 0), rootFrame,
		{ autoY = true, minW = 240, maxW = 340, minH = 50, maxH = 300 })
	tilePreviewPanel.Visible = false

	-- LOWER-LEFT: Turn Order Bar (45% W × 7% H)
	turnOrderBar = makePanel("TurnOrder",
		UDim2.fromScale(0.45, 0.07),
		UDim2.new(0, PAD, 1, -PAD), Vector2.new(0, 1), rootFrame)
	turnOrderBar.ClipsDescendants = true

	-- ADJACENT: Conditions Panel (small, next to turn order)
	conditionsPanel = makePanel("Conditions",
		UDim2.fromScale(0.12, 0.07),
		UDim2.new(0.45, PAD + 4, 1, -PAD), Vector2.new(0, 1), rootFrame)

	-- LOWER-RIGHT: Battle Log (25% W × 20% H)
	battleLogPanel = makePanel("BattleLog",
		UDim2.fromScale(0.25, 0.20),
		UDim2.new(1, -PAD, 1, -PAD), Vector2.new(1, 1), rootFrame)
	battleLogPanel.ClipsDescendants = true
end

--------------------------------------------------
-- ACTIVE UNIT PANEL (upper-left)
--------------------------------------------------

function BattleHUD._buildActiveUnit()
	if not activeUnitPanel then return end
	clearFrame(activeUnitPanel)
	activeUnitPanel.Visible = (actorData ~= nil)
	if not actorData then return end

	local d = actorData
	local pad = Instance.new("UIPadding", activeUnitPanel)
	pad.PaddingTop = UDim.new(0, 6); pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 6)

	local layout = Instance.new("UIListLayout", activeUnitPanel)
	layout.Padding = UDim.new(0, 2); layout.SortOrder = Enum.SortOrder.LayoutOrder

	-- Row 1: Portrait + Name/Doctrine/Level
	local topRow = Instance.new("Frame")
	topRow.Size = UDim2.new(1, 0, 0, 40); topRow.BackgroundTransparency = 1
	topRow.LayoutOrder = 1; topRow.Parent = activeUnitPanel

	-- Portrait (clickable)
	local portrait = Instance.new("TextButton")
	portrait.Size = UDim2.new(0, 36, 0, 36)
	portrait.Position = UDim2.new(0, 0, 0, 2)
	portrait.BackgroundColor3 = Theme.GetSideColor(d.side)
	portrait.BackgroundTransparency = 0.2
	portrait.Font = Theme.Font.PrimaryBold; portrait.TextSize = 14
	portrait.TextColor3 = Theme.Colors.TextPrimary
	portrait.Text = string.sub(d.name or "?", 1, 2)
	portrait.BorderSizePixel = 0; portrait.Parent = topRow
	Instance.new("UICorner", portrait).CornerRadius = Theme.CornerRadius.sm
	portrait.MouseButton1Click:Connect(function()
		if _G.CTRBLXAI_OpenInspectorPanel and d.id then
			_G.CTRBLXAI_OpenInspectorPanel(d.id)
		end
	end)

	-- Name
	makeLabel(topRow, d.name or "Unit", { pos = UDim2.new(0, 42, 0, 0),
		size = UDim2.new(1, -44, 0, 16), font = Theme.Font.PrimaryBold, textSize = 13,
		color = Theme.GetSideColor(d.side) })
	-- Doctrine + Level
	local docText = (d.doctrine or "") .. (d.level and ("  Lv." .. d.level) or "")
	makeLabel(topRow, docText, { pos = UDim2.new(0, 42, 0, 16),
		size = UDim2.new(1, -44, 0, 12), textSize = 9, color = Theme.Colors.TextSecondary })

	-- HP / MP values (no bars)
	local hpMpText = string.format("HP %d/%d    MP %d/%d",
		d.currentHp or 0, d.maxHp or 0, d.currentMp or 0, d.maxMp or 0)
	makeLabel(activeUnitPanel, hpMpText, { size = UDim2.new(1, 0, 0, 14),
		font = Theme.Font.Mono, textSize = 10, order = 2 })

	-- AP circles + RT
	local apText = "AP "
	for i = 1, math.min(d.currentAp or 0, 5) do apText = apText .. "●" end
	for i = (d.currentAp or 0) + 1, (d.maxAp or 2) do apText = apText .. "○" end
	apText = apText .. "    RT " .. (d.remainingRt or 0)
	makeLabel(activeUnitPanel, apText, { size = UDim2.new(1, 0, 0, 14),
		font = Theme.Font.Mono, textSize = 10, order = 3 })

	-- Statuses
	if d.statuses and #d.statuses > 0 then
		local statusText = ""
		for _, s in ipairs(d.statuses) do
			statusText = statusText .. "[" .. s.id .. "(" .. (s.remainingTurns or "?") .. ")] "
		end
		makeLabel(activeUnitPanel, statusText, { size = UDim2.new(1, 0, 0, 12),
			textSize = 9, color = Theme.Colors.Warning, order = 4 })
	end

	-- Tile info (bottom of panel)
	if d.tileX and d.tileY then
		local tileText = string.format("Tile (%d,%d)  Elev: %d", d.tileX, d.tileY, d.elevation or 1)
		makeLabel(activeUnitPanel, tileText, { size = UDim2.new(1, 0, 0, 12),
			textSize = 9, color = Theme.Colors.TextDisabled, order = 10 })
	end
end

--------------------------------------------------
-- ACTION PANEL (left, below active) — Phase 1: 4×2 grid
--------------------------------------------------

function BattleHUD._buildActionGrid()
	if not actionPanel then return end
	clearFrame(actionPanel)
	actionPanel.Visible = (currentState == "ActionSelection")
	if currentState ~= "ActionSelection" then return end
	if not actorData or not actorData.actions then return end

	local grid = Instance.new("UIGridLayout", actionPanel)
	grid.CellSize = UDim2.new(0.5, -4, 0.25, -3)
	grid.CellPadding = UDim2.new(0, 4, 0, 3)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.FillDirection = Enum.FillDirection.Horizontal

	local pad = Instance.new("UIPadding", actionPanel)
	pad.PaddingTop = UDim.new(0, 4); pad.PaddingLeft = UDim.new(0, 4)
	pad.PaddingRight = UDim.new(0, 4); pad.PaddingBottom = UDim.new(0, 4)

	for i, action in ipairs(actorData.actions) do
		makeButton(actionPanel, action.text, {
			size = nil, -- handled by grid
			enabled = action.enabled,
			onPress = action.onPress,
			order = i,
			textSize = 11,
		})
	end
end

--------------------------------------------------
-- ACTION PANEL — Phase 2: Skill/Action Detail + Back
--------------------------------------------------

function BattleHUD._buildActionDetail()
	if not actionPanel then return end
	clearFrame(actionPanel)
	actionPanel.Visible = (currentState == "TargetSelection")
	if currentState ~= "TargetSelection" then return end

	local pad = Instance.new("UIPadding", actionPanel)
	pad.PaddingTop = UDim.new(0, 6); pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 6)

	local layout = Instance.new("UIListLayout", actionPanel)
	layout.Padding = UDim.new(0, 2); layout.SortOrder = Enum.SortOrder.LayoutOrder

	if skillData then
		makeLabel(actionPanel, skillData.name or "Action", { font = Theme.Font.PrimaryBold,
			textSize = 12, order = 1 })
		if skillData.tags and skillData.tags ~= "" then
			makeLabel(actionPanel, skillData.tags, { textSize = 9,
				color = Theme.Colors.TextSecondary, order = 2 })
		end
		local infoText = ""
		if (skillData.mpCost or 0) > 0 then infoText = infoText .. "MP:" .. skillData.mpCost .. "  " end
		infoText = infoText .. "RT:" .. (skillData.rtCost or 0)
		infoText = infoText .. "  Range:" .. (skillData.range or 1)
		infoText = infoText .. "  " .. (skillData.pattern or "Single")
		makeLabel(actionPanel, infoText, { font = Theme.Font.Mono, textSize = 9, order = 3 })
		if skillData.effects and skillData.effects ~= "" then
			makeLabel(actionPanel, skillData.effects, { textSize = 9, wrap = true,
				size = UDim2.new(1, 0, 0, 24), color = Theme.Colors.Success, order = 4 })
		end
	end

	-- Back button
	local backBtn = Instance.new("TextButton")
	backBtn.Size = UDim2.new(0.5, 0, 0, 24)
	backBtn.Position = UDim2.new(0.25, 0, 1, -28)
	backBtn.BackgroundColor3 = Theme.Colors.Surface
	backBtn.BackgroundTransparency = 0.2
	backBtn.Font = Theme.Font.PrimaryBold; backBtn.TextSize = 11
	backBtn.TextColor3 = Theme.Colors.TextSecondary
	backBtn.Text = "← Back"; backBtn.BorderSizePixel = 0
	backBtn.Parent = actionPanel
	Instance.new("UICorner", backBtn).CornerRadius = Theme.CornerRadius.sm
	if actorData and actorData.onBack then
		backBtn.MouseButton1Click:Connect(actorData.onBack)
	end
end

--------------------------------------------------
-- INSPECTOR PANEL (upper-right) — Unit or Object
--------------------------------------------------

function BattleHUD._buildInspector()
	if not inspectorPanel then return end
	clearFrame(inspectorPanel)

	local showUnit = targetData ~= nil
	local showObject = objectData ~= nil and not showUnit
	inspectorPanel.Visible = showUnit or showObject

	if not inspectorPanel.Visible then return end

	local pad = Instance.new("UIPadding", inspectorPanel)
	pad.PaddingTop = UDim.new(0, 6); pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 6)

	local layout = Instance.new("UIListLayout", inspectorPanel)
	layout.Padding = UDim.new(0, 2); layout.SortOrder = Enum.SortOrder.LayoutOrder

	if showUnit then
		local d = targetData
		-- Same format as active unit
		local topRow = Instance.new("Frame")
		topRow.Size = UDim2.new(1, 0, 0, 36); topRow.BackgroundTransparency = 1
		topRow.LayoutOrder = 1; topRow.Parent = inspectorPanel

		local portrait = Instance.new("TextButton")
		portrait.Size = UDim2.new(0, 32, 0, 32)
		portrait.BackgroundColor3 = Theme.GetSideColor(d.side)
		portrait.BackgroundTransparency = 0.2
		portrait.Font = Theme.Font.PrimaryBold; portrait.TextSize = 12
		portrait.TextColor3 = Theme.Colors.TextPrimary
		portrait.Text = string.sub(d.name or "?", 1, 2)
		portrait.BorderSizePixel = 0; portrait.Parent = topRow
		Instance.new("UICorner", portrait).CornerRadius = Theme.CornerRadius.sm
		portrait.MouseButton1Click:Connect(function()
			if _G.CTRBLXAI_OpenInspectorPanel and d.id then
				_G.CTRBLXAI_OpenInspectorPanel(d.id)
			end
		end)

		makeLabel(topRow, d.name or "Unit", { pos = UDim2.new(0, 38, 0, 0),
			size = UDim2.new(1, -40, 0, 14), font = Theme.Font.PrimaryBold, textSize = 12,
			color = Theme.GetSideColor(d.side) })
		makeLabel(topRow, d.side or "", { pos = UDim2.new(0, 38, 0, 14),
			size = UDim2.new(1, -40, 0, 12), textSize = 9, color = Theme.Colors.TextSecondary })

		local hpMpText = string.format("HP %d/%d    MP %d/%d",
			d.currentHp or 0, d.maxHp or 0, d.currentMp or 0, d.maxMp or 0)
		makeLabel(inspectorPanel, hpMpText, { font = Theme.Font.Mono, textSize = 10, order = 2 })

		local apText = string.format("AP %d    RT %d", d.currentAp or 0, d.remainingRt or 0)
		makeLabel(inspectorPanel, apText, { font = Theme.Font.Mono, textSize = 9,
			color = Theme.Colors.TextSecondary, order = 3 })

		if d.statuses and #d.statuses > 0 then
			local statusText = ""
			for _, s in ipairs(d.statuses) do
				statusText = statusText .. "[" .. s.id .. "(" .. (s.remainingTurns or "?") .. ")] "
			end
			makeLabel(inspectorPanel, statusText, { textSize = 9, color = Theme.Colors.Warning, order = 4 })
		end

	elseif showObject then
		local o = objectData
		makeLabel(inspectorPanel, o.name or "Object", { font = Theme.Font.PrimaryBold,
			textSize = 12, order = 1 })
		makeLabel(inspectorPanel, o.category or "", { textSize = 9,
			color = Theme.Colors.TextSecondary, order = 2 })
		if o.interaction then
			makeLabel(inspectorPanel, "Interact: " .. o.interaction, { textSize = 10,
				wrap = true, size = UDim2.new(1, 0, 0, 24), order = 3 })
		end
		if o.destructible then
			makeLabel(inspectorPanel, "Hits to destroy: " .. (o.hitsToDestroy or "?"), {
				textSize = 10, color = Theme.Colors.Warning, order = 4 })
		else
			makeLabel(inspectorPanel, "Indestructible", { textSize = 9,
				color = Theme.Colors.TextDisabled, order = 4 })
		end
		if o.tags then
			makeLabel(inspectorPanel, "Tags: " .. o.tags, { textSize = 9,
				color = Theme.Colors.TextSecondary, order = 5 })
		end
	end
end

--------------------------------------------------
-- TILE/PREVIEW PANEL (right, below inspector)
--------------------------------------------------

function BattleHUD._buildTilePreview()
	if not tilePreviewPanel then return end
	clearFrame(tilePreviewPanel)

	-- Phase 3: Show damage preview
	if currentState == "Preview" and previewData then
		tilePreviewPanel.Visible = true
		BattleHUD._renderDamagePreview()
		return
	end

	-- Otherwise show tile info
	tilePreviewPanel.Visible = (tileData ~= nil)
	if not tileData then return end

	local pad = Instance.new("UIPadding", tilePreviewPanel)
	pad.PaddingTop = UDim.new(0, 6); pad.PaddingLeft = UDim.new(0, 8)

	local layout = Instance.new("UIListLayout", tilePreviewPanel)
	layout.Padding = UDim.new(0, 2); layout.SortOrder = Enum.SortOrder.LayoutOrder

	makeLabel(tilePreviewPanel, tileData.terrainName or "Clear", {
		font = Theme.Font.PrimaryBold, textSize = 12, order = 1 })
	makeLabel(tilePreviewPanel, string.format("Elev: %d  Cost: %d",
		tileData.elevation or 1, tileData.moveCost or 1), {
		font = Theme.Font.Mono, textSize = 10, color = Theme.Colors.TextSecondary, order = 2 })
	if tileData.effect and tileData.effect ~= "None" then
		makeLabel(tilePreviewPanel, "Effect: " .. tileData.effect, {
			textSize = 10, color = Theme.Colors.Warning, order = 3 })
	end
	if tileData.coords then
		makeLabel(tilePreviewPanel, tileData.coords, { textSize = 9,
			color = Theme.Colors.TextDisabled, order = 5 })
	end
end

function BattleHUD._renderDamagePreview()
	if not tilePreviewPanel or not previewData then return end

	local pad = Instance.new("UIPadding", tilePreviewPanel)
	pad.PaddingTop = UDim.new(0, 6); pad.PaddingLeft = UDim.new(0, 8)

	local layout = Instance.new("UIListLayout", tilePreviewPanel)
	layout.Padding = UDim.new(0, 2); layout.SortOrder = Enum.SortOrder.LayoutOrder

	makeLabel(tilePreviewPanel, "DAMAGE PREVIEW", { font = Theme.Font.PrimaryBold,
		textSize = 10, color = Theme.Colors.TextSecondary, order = 1 })

	local isHeal = previewData.isHealing or false
	local dmgText = (isHeal and "+" or "-") .. tostring(previewData.estimatedDamage or 0)
	makeLabel(tilePreviewPanel, dmgText, { font = Theme.Font.PrimaryBold, textSize = 22,
		color = isHeal and Theme.Colors.Success or Theme.Colors.Danger, order = 2 })

	if previewData.hpAfter then
		makeLabel(tilePreviewPanel, "HP After: " .. previewData.hpAfter, { textSize = 10, order = 3 })
	end
	if previewData.statusEffect and previewData.statusEffect ~= "None" then
		makeLabel(tilePreviewPanel, "Effect: " .. previewData.statusEffect, {
			textSize = 10, color = Theme.Colors.Warning, order = 4 })
	end
	if previewData.mpSpent and previewData.mpSpent > 0 then
		makeLabel(tilePreviewPanel, "MP Spent: " .. previewData.mpSpent, {
			textSize = 9, color = Theme.Colors.MP, order = 5 })
	end

	-- Confirm + Back buttons
	local btnRow = Instance.new("Frame")
	btnRow.Size = UDim2.new(1, 0, 0, 26)
	btnRow.BackgroundTransparency = 1
	btnRow.LayoutOrder = 10; btnRow.Parent = tilePreviewPanel

	local confirmBtn = Instance.new("TextButton")
	confirmBtn.Size = UDim2.new(0.48, 0, 1, 0)
	confirmBtn.BackgroundColor3 = Theme.Colors.Success
	confirmBtn.BackgroundTransparency = 0.15
	confirmBtn.Font = Theme.Font.PrimaryBold; confirmBtn.TextSize = 11
	confirmBtn.TextColor3 = Theme.Colors.TextPrimary
	confirmBtn.Text = "Execute"; confirmBtn.BorderSizePixel = 0
	confirmBtn.Parent = btnRow
	Instance.new("UICorner", confirmBtn).CornerRadius = Theme.CornerRadius.sm
	if previewData.onConfirm then
		confirmBtn.MouseButton1Click:Connect(function()
			confirmBtn.Active = false; confirmBtn.BackgroundTransparency = 0.6
			previewData.onConfirm()
		end)
	end

	local backBtn = Instance.new("TextButton")
	backBtn.Size = UDim2.new(0.48, 0, 1, 0)
	backBtn.Position = UDim2.new(0.52, 0, 0, 0)
	backBtn.BackgroundColor3 = Theme.Colors.Surface
	backBtn.BackgroundTransparency = 0.2
	backBtn.Font = Theme.Font.PrimaryBold; backBtn.TextSize = 11
	backBtn.TextColor3 = Theme.Colors.TextSecondary
	backBtn.Text = "Back"; backBtn.BorderSizePixel = 0
	backBtn.Parent = btnRow
	Instance.new("UICorner", backBtn).CornerRadius = Theme.CornerRadius.sm
	if previewData.onBack then
		backBtn.MouseButton1Click:Connect(previewData.onBack)
	end
end

--------------------------------------------------
-- TURN ORDER BAR (lower-left)
--------------------------------------------------

function BattleHUD.UpdateTimeline(entries)
	ensureRoot()
	if not turnOrderBar then return end
	clearFrame(turnOrderBar)
	if not entries or #entries == 0 then return end

	local layout = Instance.new("UIListLayout", turnOrderBar)
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 2)

	local pad = Instance.new("UIPadding", turnOrderBar)
	pad.PaddingLeft = UDim.new(0, 4); pad.PaddingRight = UDim.new(0, 4)

	local slotCount = #entries
	for i, entry in ipairs(entries) do
		local isActive = entry.isActive or false
		local isRound = entry.isRound or false
		local isEvent = entry.isEvent or false
		local slotW = isActive and 44 or (isRound and 18 or 34)

		local portrait = Instance.new("TextButton")
		portrait.Size = UDim2.new(0, slotW, 0.85, 0)
		portrait.BorderSizePixel = 0; portrait.Text = ""
		portrait.AutoButtonColor = false
		portrait.LayoutOrder = i; portrait.Parent = turnOrderBar

		if isRound then
			portrait.BackgroundColor3 = Color3.fromRGB(50, 50, 30)
			portrait.BackgroundTransparency = 0.4
		elseif isEvent then
			portrait.BackgroundColor3 = Color3.fromRGB(60, 40, 100)
			portrait.BackgroundTransparency = 0.15
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

		local nameL = Instance.new("TextLabel")
		nameL.Size = UDim2.fromScale(1, 0.6)
		nameL.Position = UDim2.new(0, 0, 0, 1)
		nameL.BackgroundTransparency = 1
		nameL.Font = Theme.Font.PrimaryBold
		nameL.TextSize = isActive and 10 or 8
		nameL.TextColor3 = isEvent and Theme.Colors.TextGold or Theme.Colors.TextPrimary
		nameL.Text = isRound and (entry.name or "") or string.sub(entry.name or "?", 1, isActive and 5 or 3)
		nameL.Parent = portrait

		local bottomL = Instance.new("TextLabel")
		bottomL.Size = UDim2.new(1, 0, 0, 9)
		bottomL.Position = UDim2.new(0, 0, 1, -9)
		bottomL.BackgroundTransparency = 1
		bottomL.Font = Theme.Font.Primary; bottomL.TextSize = 7
		bottomL.TextColor3 = Theme.Colors.TextSecondary
		bottomL.Text = isActive and "NOW" or (isEvent and "ACT" or (entry.rt and tostring(entry.rt) or ""))
		bottomL.Parent = portrait

		if entry.onClick and not isRound then
			portrait.MouseButton1Click:Connect(entry.onClick)
		end
	end
end

--------------------------------------------------
-- BATTLE LOG (lower-right)
--------------------------------------------------

function BattleHUD.AddLogEntry(text)
	table.insert(battleLog, text)
	if #battleLog > 20 then table.remove(battleLog, 1) end
	BattleHUD._buildBattleLog()
end

function BattleHUD._buildBattleLog()
	if not battleLogPanel then return end
	clearFrame(battleLogPanel)

	local pad = Instance.new("UIPadding", battleLogPanel)
	pad.PaddingTop = UDim.new(0, 4); pad.PaddingLeft = UDim.new(0, 6)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 2
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasPosition = Vector2.new(0, 99999)
	scroll.Parent = battleLogPanel

	local layout = Instance.new("UIListLayout", scroll)
	layout.Padding = UDim.new(0, 1)

	for i, entry in ipairs(battleLog) do
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, -8, 0, 12)
		lbl.BackgroundTransparency = 1
		lbl.Font = Theme.Font.Primary; lbl.TextSize = 9
		lbl.TextColor3 = Theme.Colors.TextSecondary
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.TextWrapped = true
		lbl.AutomaticSize = Enum.AutomaticSize.Y
		lbl.Text = entry; lbl.LayoutOrder = i
		lbl.Parent = scroll
	end
end

--------------------------------------------------
-- STATE MACHINE
--------------------------------------------------

function BattleHUD.SetState(newState)
	currentState = newState
	ensureRoot()

	-- Position dependent panels below their parent after AutomaticSize resolves
	task.defer(function()
		-- Action panel below Active Unit panel
		if activeUnitPanel and actionPanel then
			local parentBottom = activeUnitPanel.AbsolutePosition.Y + activeUnitPanel.AbsoluteSize.Y
			local rootTop = rootFrame and rootFrame.AbsolutePosition.Y or 0
			actionPanel.Position = UDim2.new(0, PAD, 0, (parentBottom - rootTop) + 4)
		end
		-- TilePreview below Inspector panel
		if inspectorPanel and tilePreviewPanel then
			local parentBottom = inspectorPanel.AbsolutePosition.Y + inspectorPanel.AbsoluteSize.Y
			local rootTop = rootFrame and rootFrame.AbsolutePosition.Y or 0
			tilePreviewPanel.Position = UDim2.new(1, -PAD, 0, (parentBottom - rootTop) + 4)
		end
	end)

	-- Rebuild affected panels per state
	BattleHUD._buildActiveUnit()
	BattleHUD._buildInspector()
	BattleHUD._buildTilePreview()

	if newState == "ActionSelection" then
		BattleHUD._buildActionGrid()
		actionPanel.Visible = true
	elseif newState == "TargetSelection" then
		BattleHUD._buildActionDetail()
		actionPanel.Visible = true
	elseif newState == "Preview" then
		BattleHUD._buildActionDetail()
		actionPanel.Visible = true
	elseif newState == "Resolving" or newState == "BattleEnded" or newState == "Idle" then
		if actionPanel then actionPanel.Visible = false end
		if activeUnitPanel then activeUnitPanel.Visible = false end
	elseif newState == "SkillSelection" then
		-- Skill list shown in action panel
		BattleHUD._buildSkillList()
		actionPanel.Visible = true
	end
end

function BattleHUD.GetState() return currentState end

--------------------------------------------------
-- SKILL LIST (replaces action grid during SkillSelection)
--------------------------------------------------

function BattleHUD._buildSkillList()
	if not actionPanel then return end
	clearFrame(actionPanel)
	actionPanel.Visible = true
	if not actorData or not actorData.skillEntries then return end

	local pad = Instance.new("UIPadding", actionPanel)
	pad.PaddingTop = UDim.new(0, 4); pad.PaddingLeft = UDim.new(0, 4)
	pad.PaddingRight = UDim.new(0, 4)

	local layout = Instance.new("UIListLayout", actionPanel)
	layout.Padding = UDim.new(0, 2); layout.SortOrder = Enum.SortOrder.LayoutOrder

	-- Header
	makeLabel(actionPanel, "Skill            MP  RT", { font = Theme.Font.Mono,
		textSize = 9, color = Theme.Colors.TextSecondary, order = 0 })

	for i, skill in ipairs(actorData.skillEntries) do
		local enabled = skill.enabled ~= false
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 0, 22)
		btn.BackgroundColor3 = Theme.Colors.Surface
		btn.BackgroundTransparency = enabled and 0.5 or 0.8
		btn.BorderSizePixel = 0
		btn.Font = Theme.Font.Mono; btn.TextSize = 10
		btn.TextColor3 = enabled and Theme.Colors.TextPrimary or Theme.Colors.TextDisabled
		btn.TextXAlignment = Enum.TextXAlignment.Left
		btn.Text = string.format(" %-14s %2d  %2d",
			string.sub(skill.name or "?", 1, 13), skill.mpCost or 0, skill.rtCost or 0)
		btn.AutoButtonColor = enabled; btn.Active = enabled
		btn.LayoutOrder = i; btn.Parent = actionPanel
		Instance.new("UICorner", btn).CornerRadius = Theme.CornerRadius.sm
		if enabled and skill.onPress then btn.MouseButton1Click:Connect(skill.onPress) end
	end

	-- Back button
	local backBtn = Instance.new("TextButton")
	backBtn.Size = UDim2.new(0.5, 0, 0, 20)
	backBtn.BackgroundColor3 = Theme.Colors.Surface; backBtn.BackgroundTransparency = 0.3
	backBtn.Font = Theme.Font.Primary; backBtn.TextSize = 10
	backBtn.TextColor3 = Theme.Colors.TextSecondary
	backBtn.Text = "← Back"; backBtn.BorderSizePixel = 0
	backBtn.LayoutOrder = 100; backBtn.Parent = actionPanel
	Instance.new("UICorner", backBtn).CornerRadius = Theme.CornerRadius.sm
	if actorData and actorData.onBack then
		backBtn.MouseButton1Click:Connect(actorData.onBack)
	end
end

--------------------------------------------------
-- PUBLIC SETTERS
--------------------------------------------------

function BattleHUD.SetActorData(data) actorData = data end
function BattleHUD.SetTargetData(data) targetData = data end
function BattleHUD.SetSkillData(data) skillData = data end
function BattleHUD.SetPreviewData(data) previewData = data end
function BattleHUD.SetTileData(data) tileData = data end
function BattleHUD.SetObjectData(data) objectData = data end

function BattleHUD.ShowActorCard(data) actorData = data end
function BattleHUD.HideActorCard() actorData = nil end
function BattleHUD.ShowTargetCard(data) targetData = data end
function BattleHUD.HideTargetCard() targetData = nil end
function BattleHUD.ShowInspectUnit(data) targetData = data; BattleHUD._buildInspector() end
function BattleHUD.ShowTileInfo(data) tileData = data; BattleHUD._buildTilePreview() end
function BattleHUD.HideTileInfo() tileData = nil; if tilePreviewPanel then tilePreviewPanel.Visible = false end end

function BattleHUD.GetInspectedUnitId() return actorData and actorData.id or nil end

-- Compatibility stubs
function BattleHUD.ShowActionMenu() end
function BattleHUD.HideActionMenu() end
function BattleHUD.ShowSkillList() end
function BattleHUD.HideSkillList() end
function BattleHUD.ShowSkillDetail() end
function BattleHUD.HideSkillDetail() end
function BattleHUD.ShowConfirmBar() end
function BattleHUD.HideConfirmBar() end
function BattleHUD.ShowDamagePreview(data) previewData = data end
function BattleHUD.HideDamagePreview() previewData = nil end
function BattleHUD.ShowPhase() end
function BattleHUD.HidePhase() end
function BattleHUD.HideActionBar() end
function BattleHUD.UpdateBattleState() end

--------------------------------------------------
-- TOOLTIP
--------------------------------------------------

local tooltipFrame = nil
local tooltipCloseConn = nil

function BattleHUD.ShowTooltip(props)
	BattleHUD.HideTooltip()
	ensureRoot()

	tooltipFrame = Instance.new("Frame")
	tooltipFrame.Name = "Tooltip"
	tooltipFrame.Size = UDim2.fromOffset(props.maxWidth or 180, 10)
	tooltipFrame.Position = props.position or UDim2.new(0.5, 0, 0.4, 0)
	tooltipFrame.AnchorPoint = props.anchorPoint or Vector2.new(0.5, 0)
	tooltipFrame.BackgroundColor3 = Theme.Colors.PanelRaised
	tooltipFrame.BackgroundTransparency = 0.02
	tooltipFrame.BorderSizePixel = 0
	tooltipFrame.AutomaticSize = Enum.AutomaticSize.Y
	tooltipFrame.ZIndex = 30
	tooltipFrame.Parent = rootFrame
	Instance.new("UICorner", tooltipFrame).CornerRadius = Theme.CornerRadius.md
	local s = Instance.new("UIStroke", tooltipFrame); s.Color = Theme.Colors.Border; s.Thickness = 1
	local p = Instance.new("UIPadding", tooltipFrame)
	p.PaddingTop = UDim.new(0,5); p.PaddingBottom = UDim.new(0,5)
	p.PaddingLeft = UDim.new(0,8); p.PaddingRight = UDim.new(0,8)
	Instance.new("UIListLayout", tooltipFrame).Padding = UDim.new(0,2)

	if props.title then
		makeLabel(tooltipFrame, props.title, { font = Theme.Font.PrimaryBold, textSize = 11,
			color = Theme.Colors.TextGold, order = 0 })
	end
	for i, line in ipairs(props.lines or {}) do
		if line then makeLabel(tooltipFrame, line, { textSize = 10, wrap = true, order = i }) end
	end

	task.defer(function()
		tooltipCloseConn = UserInputService.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				BattleHUD.HideTooltip()
			end
		end)
	end)
end

function BattleHUD.HideTooltip()
	if tooltipFrame then tooltipFrame:Destroy(); tooltipFrame = nil end
	if tooltipCloseConn then tooltipCloseConn:Disconnect(); tooltipCloseConn = nil end
end

--------------------------------------------------
-- CLEANUP
--------------------------------------------------

function BattleHUD.Cleanup()
	currentState = "Idle"
	actorData = nil; targetData = nil; skillData = nil
	previewData = nil; tileData = nil; objectData = nil
	battleLog = {}
	BattleHUD.HideTooltip()
	if screenGui then screenGui:Destroy(); screenGui = nil end
	rootFrame = nil
	activeUnitPanel = nil; actionPanel = nil
	inspectorPanel = nil; tilePreviewPanel = nil
	turnOrderBar = nil; conditionsPanel = nil; battleLogPanel = nil
end

return BattleHUD
