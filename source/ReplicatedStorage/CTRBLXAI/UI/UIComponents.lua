-- UIComponents.lua
-- CTRBLXAI | Slice 7A — Reusable UI Component Factories
--
-- Every function creates and returns a UI Instance ready to be parented.
-- Components receive display data as input parameters.
-- Components NEVER query gameplay state or access BattleEvents.
--
-- Icon Fallback Rule:
--   1. Use props.icon (asset ID string) if provided and valid
--   2. Use props.fallbackText (emoji or abbreviation)
--   3. Use "?" as final fallback
--
-- All colors and styling reference Theme.lua.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CTRBLXAI_UI = ReplicatedStorage:WaitForChild("CTRBLXAI", 10):WaitForChild("UI", 10)
local Theme = require(CTRBLXAI_UI:WaitForChild("Theme", 10))

local UIComponents = {}

--------------------------------------------------
-- INTERNAL HELPERS
--------------------------------------------------

local function applyCorner(instance, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or Theme.CornerRadius.md
	corner.Parent = instance
	return corner
end

local function applyStroke(instance, color, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Theme.Colors.Border
	stroke.Thickness = thickness or Theme.BorderThickness.Default
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = instance
	return stroke
end

local function applyPadding(instance, top, right, bottom, left)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, top or Theme.Spacing.md)
	pad.PaddingRight = UDim.new(0, right or Theme.Spacing.md)
	pad.PaddingBottom = UDim.new(0, bottom or Theme.Spacing.md)
	pad.PaddingLeft = UDim.new(0, left or Theme.Spacing.md)
	pad.Parent = instance
	return pad
end

--- Try to display an icon. Returns ImageLabel or TextLabel.
local function createIconOrFallback(parent, props, size)
	size = size or UDim2.fromOffset(20, 20)

	-- Attempt image icon
	if props.icon and type(props.icon) == "string" and props.icon ~= "" then
		local img = Instance.new("ImageLabel")
		img.Size = size
		img.BackgroundTransparency = 1
		img.Image = props.icon
		img.ScaleType = Enum.ScaleType.Fit
		img.Parent = parent
		return img
	end

	-- Fallback text
	local text = props.fallbackText or props.fallbackIcon or "?"
	local lbl = Instance.new("TextLabel")
	lbl.Size = size
	lbl.BackgroundTransparency = 1
	lbl.Font = Theme.Font.Primary
	lbl.TextSize = Theme.TextSize.md
	lbl.TextColor3 = Theme.Colors.TextSecondary
	lbl.Text = text
	lbl.Parent = parent
	return lbl
end

--------------------------------------------------
-- PANEL
-- A basic themed container frame.
--
-- props:
--   size       : UDim2 (required)
--   position   : UDim2 (optional)
--   anchorPoint: Vector2 (optional)
--   variant    : "default" | "raised" | "surface" (optional)
--   border     : boolean (optional, default true)
--   cornerRadius: UDim (optional)
--------------------------------------------------

function UIComponents.Panel(props)
	local variant = props.variant or "default"
	local bgColor = variant == "raised" and Theme.Colors.PanelRaised
		or variant == "surface" and Theme.Colors.Surface
		or Theme.Colors.Panel

	local frame = Instance.new("Frame")
	frame.Name = props.name or "Panel"
	frame.Size = props.size
	frame.Position = props.position or UDim2.new(0, 0, 0, 0)
	frame.AnchorPoint = props.anchorPoint or Vector2.new(0, 0)
	frame.BackgroundColor3 = bgColor
	frame.BackgroundTransparency = Theme.Transparency.PanelBg
	frame.BorderSizePixel = 0
	frame.Active = false

	applyCorner(frame, props.cornerRadius or Theme.CornerRadius.md)

	if props.border ~= false then
		applyStroke(frame, Theme.Colors.Border, Theme.BorderThickness.Default)
	end

	return frame
end

--------------------------------------------------
-- PRIMARY BUTTON
-- Prominent action button.
--
-- props:
--   text     : string
--   size     : UDim2 (optional)
--   position : UDim2 (optional)
--   icon     : string? (asset ID)
--   fallbackText: string? (icon fallback)
--   enabled  : boolean (default true)
--   color    : Color3? (override accent color)
--   onPress  : function?
--------------------------------------------------

function UIComponents.PrimaryButton(props)
	local enabled = props.enabled ~= false
	local accentColor = props.color or Theme.Colors.Player

	local btn = Instance.new("TextButton")
	btn.Name = props.name or "PrimaryBtn"
	btn.Size = props.size or UDim2.fromOffset(Theme.MinSize.ButtonWidth, Theme.MinSize.ButtonHeight)
	btn.Position = props.position or UDim2.new(0, 0, 0, 0)
	btn.AnchorPoint = props.anchorPoint or Vector2.new(0, 0)
	btn.BackgroundColor3 = enabled and accentColor or Theme.Colors.Surface
	btn.BackgroundTransparency = enabled and 0.1 or Theme.Transparency.ButtonDisabled
	btn.BorderSizePixel = 0
	btn.Font = Theme.Font.PrimaryBold
	btn.TextSize = Theme.TextSize.md
	btn.TextColor3 = enabled and Theme.Colors.TextPrimary or Theme.Colors.TextDisabled
	btn.Text = props.text or ""
	btn.AutoButtonColor = enabled
	btn.Active = enabled

	applyCorner(btn, Theme.CornerRadius.md)

	if enabled and props.onPress then
		btn.MouseButton1Click:Connect(props.onPress)
	end

	return btn
end

--------------------------------------------------
-- SECONDARY BUTTON
-- Less prominent than PrimaryButton.
--------------------------------------------------

function UIComponents.SecondaryButton(props)
	local enabled = props.enabled ~= false

	local btn = Instance.new("TextButton")
	btn.Name = props.name or "SecondaryBtn"
	btn.Size = props.size or UDim2.fromOffset(Theme.MinSize.ButtonWidth, Theme.MinSize.ButtonHeight)
	btn.Position = props.position or UDim2.new(0, 0, 0, 0)
	btn.AnchorPoint = props.anchorPoint or Vector2.new(0, 0)
	btn.BackgroundColor3 = Theme.Colors.Surface
	btn.BackgroundTransparency = enabled and 0.2 or Theme.Transparency.ButtonDisabled
	btn.BorderSizePixel = 0
	btn.Font = Theme.Font.Primary
	btn.TextSize = Theme.TextSize.sm
	btn.TextColor3 = enabled and Theme.Colors.TextSecondary or Theme.Colors.TextDisabled
	btn.Text = props.text or ""
	btn.AutoButtonColor = enabled
	btn.Active = enabled

	applyCorner(btn, Theme.CornerRadius.sm)
	applyStroke(btn, Theme.Colors.Border, Theme.BorderThickness.Default)

	if enabled and props.onPress then
		btn.MouseButton1Click:Connect(props.onPress)
	end

	return btn
end

--------------------------------------------------
-- ICON BUTTON
-- Square button showing an icon or fallback text.
--
-- props:
--   icon         : string? (asset ID)
--   fallbackText : string (emoji or short text)
--   size         : number? (square side, default 40)
--   enabled      : boolean
--   onPress      : function?
--   tooltipText  : string? (for future hover tooltip)
--------------------------------------------------

function UIComponents.IconButton(props)
	local enabled = props.enabled ~= false
	local side = props.size or Theme.MinSize.IconButton

	local btn = Instance.new("TextButton")
	btn.Name = props.name or "IconBtn"
	btn.Size = UDim2.fromOffset(side, side)
	btn.Position = props.position or UDim2.new(0, 0, 0, 0)
	btn.BackgroundColor3 = enabled and Theme.Colors.Surface or Theme.Colors.Panel
	btn.BackgroundTransparency = enabled and 0.15 or Theme.Transparency.ButtonDisabled
	btn.BorderSizePixel = 0
	btn.Text = ""
	btn.AutoButtonColor = enabled
	btn.Active = enabled

	applyCorner(btn, Theme.CornerRadius.sm)

	createIconOrFallback(btn, props, UDim2.fromScale(0.7, 0.7))

	if enabled and props.onPress then
		btn.MouseButton1Click:Connect(props.onPress)
	end

	return btn
end

--------------------------------------------------
-- ACTION BUTTON
-- Wide button used in the action bar (Attack, Move, Skill, etc.)
--
-- props:
--   text      : string (action name)
--   subtext   : string? (e.g. "MP:3 R:4")
--   icon      : string?
--   fallbackText: string?
--   color     : Color3? (accent override)
--   enabled   : boolean
--   selected  : boolean? (currently active mode)
--   onPress   : function?
--------------------------------------------------

function UIComponents.ActionButton(props)
	local enabled = props.enabled ~= false
	local selected = props.selected or false
	local baseColor = props.color or Theme.Colors.Surface

	local btn = Instance.new("TextButton")
	btn.Name = props.name or "ActionBtn"
	btn.Size = props.size or UDim2.fromOffset(100, 55)
	btn.BackgroundColor3 = enabled and baseColor or Theme.Colors.Panel
	btn.BackgroundTransparency = enabled and 0.1 or Theme.Transparency.ButtonDisabled
	btn.BorderSizePixel = 0
	btn.Font = Theme.Font.PrimaryBold
	btn.TextSize = Theme.TextSize.sm
	btn.TextColor3 = enabled and Theme.Colors.TextPrimary or Theme.Colors.TextDisabled
	btn.TextWrapped = true
	btn.AutoButtonColor = enabled
	btn.Active = enabled

	-- Build display text
	local displayText = props.text or ""
	if props.subtext and props.subtext ~= "" then
		displayText = displayText .. "\n" .. props.subtext
	end
	btn.Text = displayText

	applyCorner(btn, Theme.CornerRadius.md)

	-- Selected state: gold border
	if selected then
		applyStroke(btn, Theme.Colors.BorderFocused, Theme.BorderThickness.Selected)
	end

	if enabled and props.onPress then
		btn.MouseButton1Click:Connect(props.onPress)
	end

	return btn
end

--------------------------------------------------
-- RESOURCE BAR
-- Horizontal fill bar for HP, MP, etc.
--
-- props:
--   current   : number
--   max       : number
--   color     : Color3? (fill color, auto-selects HP color if nil)
--   size      : UDim2?
--   showText  : boolean? (show "120/200" label)
--   textSide  : "inside" | "right" (default "inside")
--   bgColor   : Color3? (background)
--   animate   : boolean? (tween to new value, default false in factory)
--------------------------------------------------

function UIComponents.ResourceBar(props)
	local max = props.max or 1
	local current = math.clamp(props.current or 0, 0, max)
	local ratio = max > 0 and (current / max) or 0
	local fillColor = props.color or Theme.GetHPColor(ratio)

	local container = Instance.new("Frame")
	container.Name = props.name or "ResourceBar"
	container.Size = props.size or UDim2.fromOffset(140, 14)
	container.Position = props.position or UDim2.new(0, 0, 0, 0)
	container.BackgroundColor3 = props.bgColor or Color3.fromRGB(25, 25, 35)
	container.BackgroundTransparency = 0
	container.BorderSizePixel = 0

	applyCorner(container, Theme.CornerRadius.sm)

	-- Fill frame
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(ratio, 1)
	fill.BackgroundColor3 = fillColor
	fill.BackgroundTransparency = 0
	fill.BorderSizePixel = 0
	fill.Parent = container
	applyCorner(fill, Theme.CornerRadius.sm)

	-- Text overlay
	if props.showText ~= false then
		local label = Instance.new("TextLabel")
		label.Name = "ValueLabel"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Theme.Font.PrimaryBold
		label.TextSize = math.min(Theme.TextSize.xs, (props.size and props.size.Y.Offset or 14) - 2)
		label.TextColor3 = Theme.Colors.TextPrimary
		label.TextStrokeTransparency = 0.5
		label.Text = string.format("%d/%d", current, max)
		label.Parent = container
	end

	return container
end

--------------------------------------------------
-- STAT ROW
-- Single line showing a stat label and value.
--
-- props:
--   label  : string
--   value  : string | number
--   suffix : string? (e.g. "%", "px")
--   color  : Color3?
--------------------------------------------------

function UIComponents.StatRow(props)
	local frame = Instance.new("Frame")
	frame.Name = "StatRow"
	frame.Size = props.size or UDim2.new(1, 0, 0, 18)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.55, 1)
	label.BackgroundTransparency = 1
	label.Font = Theme.Font.Primary
	label.TextSize = Theme.TextSize.sm
	label.TextColor3 = Theme.Colors.TextSecondary
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = "  " .. (props.label or "")
	label.Parent = frame

	local value = Instance.new("TextLabel")
	value.Size = UDim2.new(0.45, 0, 1, 0)
	value.Position = UDim2.fromScale(0.55, 0)
	value.BackgroundTransparency = 1
	value.Font = Theme.Font.PrimaryBold
	value.TextSize = Theme.TextSize.sm
	value.TextColor3 = props.color or Theme.Colors.TextPrimary
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.Text = tostring(props.value or "") .. (props.suffix or "")
	value.Parent = frame

	return frame
end

--------------------------------------------------
-- TIMELINE ENTRY
-- A single portrait slot in the turn order bar.
--
-- props:
--   name     : string
--   side     : "Player" | "Enemy"
--   isActive : boolean (gold border, larger)
--   isEvent  : boolean (channeling activation, round marker)
--   isRound  : boolean (round boundary)
--   size     : number? (slot width/height)
--------------------------------------------------

function UIComponents.TimelineEntry(props)
	local isActive = props.isActive or false
	local isEvent = props.isEvent or false
	local isRound = props.isRound or false
	local side = props.side or "Neutral"
	local slotSize = props.size or (isActive and 52 or 42)

	local portrait = Instance.new("Frame")
	portrait.Name = "TimelineSlot"
	portrait.Size = UDim2.fromOffset(slotSize, slotSize)
	portrait.BorderSizePixel = 0

	-- Background color based on type
	if isRound then
		portrait.BackgroundColor3 = Theme.Colors.Surface
		portrait.BackgroundTransparency = 0.4
	elseif isEvent then
		portrait.BackgroundColor3 = side == "Player"
			and Color3.fromRGB(50, 40, 100) or Color3.fromRGB(100, 50, 20)
		portrait.BackgroundTransparency = 0.15
	else
		portrait.BackgroundColor3 = Theme.GetSideColor(side)
		portrait.BackgroundTransparency = 0.2
	end

	applyCorner(portrait, Theme.CornerRadius.sm)

	-- Active: gold border
	if isActive then
		portrait.BackgroundTransparency = 0
		applyStroke(portrait, Theme.Colors.BorderFocused, Theme.BorderThickness.Active)
	end

	-- Name label (abbreviated)
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.fromScale(1, 0.65)
	nameLabel.Position = UDim2.new(0, 0, 0, 2)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Theme.Font.PrimaryBold
	nameLabel.TextSize = isActive and 14 or (isEvent and 9 or 11)
	nameLabel.TextColor3 = isEvent and Theme.Colors.TextGold or Theme.Colors.TextPrimary
	nameLabel.Text = isRound and (props.name or "")
		or string.sub(props.name or "?", 1, isActive and 4 or 3)
	nameLabel.Parent = portrait

	return portrait
end

--------------------------------------------------
-- STATUS ICON
-- Small indicator for a status effect.
--
-- props:
--   statusId       : string (e.g. "Poison")
--   remainingTurns : number?
--   size           : number? (default 22)
--   icon           : string? (asset ID)
--------------------------------------------------

function UIComponents.StatusIcon(props)
	local side = props.size or 22
	local statusId = props.statusId or "?"

	local frame = Instance.new("Frame")
	frame.Name = "Status_" .. statusId
	frame.Size = UDim2.fromOffset(side, side)
	frame.BackgroundColor3 = Theme.GetStatusColor(statusId)
	frame.BackgroundTransparency = 0.3
	frame.BorderSizePixel = 0

	applyCorner(frame, Theme.CornerRadius.sm)

	-- Icon or text abbreviation
	local abbrev = string.sub(statusId, 1, 3)
	createIconOrFallback(frame, {
		icon = props.icon,
		fallbackText = abbrev,
	}, UDim2.fromScale(0.85, 0.65))

	-- Duration badge (bottom-right corner)
	if props.remainingTurns and props.remainingTurns > 0 then
		local badge = Instance.new("TextLabel")
		badge.Size = UDim2.fromOffset(12, 10)
		badge.Position = UDim2.new(1, -12, 1, -10)
		badge.BackgroundColor3 = Theme.Colors.Background
		badge.BackgroundTransparency = 0.2
		badge.Font = Theme.Font.PrimaryBold
		badge.TextSize = 8
		badge.TextColor3 = Theme.Colors.TextPrimary
		badge.Text = tostring(props.remainingTurns)
		badge.BorderSizePixel = 0
		badge.Parent = frame
		applyCorner(badge, Theme.CornerRadius.sm)
	end

	return frame
end

--------------------------------------------------
-- TOOLTIP
-- Floating information panel.
--
-- props:
--   title    : string?
--   lines    : {string} (array of text lines)
--   position : UDim2?
--   maxWidth : number?
--------------------------------------------------

function UIComponents.Tooltip(props)
	local lines = props.lines or {}
	local lineCount = (props.title and 1 or 0) + #lines
	local height = math.max(40, lineCount * 16 + 16)
	local width = props.maxWidth or 200

	local frame = Instance.new("Frame")
	frame.Name = "Tooltip"
	frame.Size = UDim2.fromOffset(width, height)
	frame.Position = props.position or UDim2.new(0.5, 0, 0.8, 0)
	frame.AnchorPoint = props.anchorPoint or Vector2.new(0.5, 1)
	frame.BackgroundColor3 = Theme.Colors.PanelRaised
	frame.BackgroundTransparency = 0.05
	frame.BorderSizePixel = 0

	applyCorner(frame, Theme.CornerRadius.md)
	applyStroke(frame, Theme.Colors.Border, Theme.BorderThickness.Default)
	applyPadding(frame, Theme.Spacing.sm, Theme.Spacing.md, Theme.Spacing.sm, Theme.Spacing.md)

	-- Build text content
	local textParts = {}
	if props.title then
		table.insert(textParts, '<font color="rgb(255,220,80)"><b>' .. props.title .. '</b></font>')
	end
	for _, line in ipairs(lines) do
		table.insert(textParts, line)
	end

	local content = Instance.new("TextLabel")
	content.Size = UDim2.fromScale(1, 1)
	content.BackgroundTransparency = 1
	content.Font = Theme.Font.Primary
	content.TextSize = Theme.TextSize.sm
	content.TextColor3 = Theme.Colors.TextPrimary
	content.TextXAlignment = Enum.TextXAlignment.Left
	content.TextYAlignment = Enum.TextYAlignment.Top
	content.TextWrapped = true
	content.RichText = true
	content.Text = table.concat(textParts, "\n")
	content.Parent = frame

	return frame
end

--------------------------------------------------
-- WARNING PANEL
-- Highlighted notification/warning box.
--
-- props:
--   text     : string
--   severity : "info" | "warning" | "danger" (default "warning")
--   size     : UDim2?
--------------------------------------------------

function UIComponents.WarningPanel(props)
	local severity = props.severity or "warning"
	local color = severity == "danger" and Theme.Colors.Danger
		or severity == "info" and Theme.Colors.Info
		or Theme.Colors.Warning

	local frame = Instance.new("Frame")
	frame.Name = "WarningPanel"
	frame.Size = props.size or UDim2.new(1, 0, 0, 40)
	frame.BackgroundColor3 = Theme.Colors.Panel
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0

	applyCorner(frame, Theme.CornerRadius.sm)
	applyStroke(frame, color, Theme.BorderThickness.Selected)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -12, 1, -4)
	label.Position = UDim2.new(0, 6, 0, 2)
	label.BackgroundTransparency = 1
	label.Font = Theme.Font.Primary
	label.TextSize = Theme.TextSize.sm
	label.TextColor3 = color
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Text = props.text or ""
	label.Parent = frame

	return frame
end

--------------------------------------------------
-- MODAL PANEL
-- Centered overlay with title and content area.
--
-- props:
--   title    : string
--   size     : UDim2?
--   onClose  : function?
--------------------------------------------------

function UIComponents.ModalPanel(props)
	-- Backdrop
	local backdrop = Instance.new("Frame")
	backdrop.Name = "ModalBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.Overlay
	backdrop.BackgroundTransparency = Theme.Transparency.Overlay
	backdrop.BorderSizePixel = 0

	-- Panel
	local panel = Instance.new("Frame")
	panel.Name = "ModalPanel"
	panel.Size = props.size or UDim2.fromOffset(320, 200)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = Theme.Colors.Panel
	panel.BackgroundTransparency = 0
	panel.BorderSizePixel = 0
	panel.Parent = backdrop

	applyCorner(panel, Theme.CornerRadius.lg)
	applyStroke(panel, Theme.Colors.Border, Theme.BorderThickness.Default)

	-- Title bar
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -40, 0, 30)
	title.Position = UDim2.new(0, 12, 0, 6)
	title.BackgroundTransparency = 1
	title.Font = Theme.Font.PrimaryBold
	title.TextSize = Theme.TextSize.md
	title.TextColor3 = Theme.Colors.TextGold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = props.title or "Dialog"
	title.Parent = panel

	-- Close button
	if props.onClose then
		local closeBtn = Instance.new("TextButton")
		closeBtn.Size = UDim2.fromOffset(28, 28)
		closeBtn.Position = UDim2.new(1, -34, 0, 4)
		closeBtn.BackgroundColor3 = Theme.Colors.Danger
		closeBtn.BackgroundTransparency = 0.6
		closeBtn.Font = Theme.Font.PrimaryBold
		closeBtn.TextSize = Theme.TextSize.md
		closeBtn.TextColor3 = Theme.Colors.TextPrimary
		closeBtn.Text = "X"
		closeBtn.BorderSizePixel = 0
		closeBtn.Parent = panel
		applyCorner(closeBtn, Theme.CornerRadius.sm)
		closeBtn.MouseButton1Click:Connect(props.onClose)
	end

	-- Content area (caller adds children to this)
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -16, 1, -44)
	content.Position = UDim2.new(0, 8, 0, 38)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Parent = panel

	return backdrop
end

--------------------------------------------------
-- RARITY BORDER
-- Wraps a child element with a colored UIStroke.
--
-- props:
--   rarity : string (e.g. "Rare", "Epic")
--   child  : Instance (the element to wrap)
--------------------------------------------------

function UIComponents.RarityBorder(props)
	local child = props.child
	if not child then return nil end

	local color = Theme.GetRarityColor(props.rarity)
	applyStroke(child, color, Theme.BorderThickness.Selected)
	return child
end

--------------------------------------------------
-- LOADING STATE
-- Placeholder shown while content loads.
--
-- props:
--   text : string? (default "Loading...")
--   size : UDim2?
--------------------------------------------------

function UIComponents.LoadingState(props)
	local frame = Instance.new("Frame")
	frame.Name = "LoadingState"
	frame.Size = props.size or UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Theme.Font.Primary
	label.TextSize = Theme.TextSize.md
	label.TextColor3 = Theme.Colors.TextSecondary
	label.Text = props.text or "Loading..."
	label.Parent = frame

	return frame
end

--------------------------------------------------
-- EMPTY STATE
-- Placeholder when there's no content to display.
--
-- props:
--   text : string? (default "Nothing to display")
--   size : UDim2?
--------------------------------------------------

function UIComponents.EmptyState(props)
	local frame = Instance.new("Frame")
	frame.Name = "EmptyState"
	frame.Size = props.size or UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.8, 0.6)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Font = Theme.Font.Primary
	label.TextSize = Theme.TextSize.sm
	label.TextColor3 = Theme.Colors.TextDisabled
	label.Text = props.text or "Nothing to display"
	label.TextWrapped = true
	label.Parent = frame

	return frame
end

--------------------------------------------------
-- UNIT LIST ENTRY
-- A row showing unit name, side, HP bar, and status icons.
--
-- props:
--   name     : string
--   side     : "Player" | "Enemy"
--   currentHp: number
--   maxHp    : number
--   statuses : {{id: string, remainingTurns: number}}?
--   isAlive  : boolean?
--------------------------------------------------

function UIComponents.UnitListEntry(props)
	local frame = Instance.new("Frame")
	frame.Name = "UnitEntry"
	frame.Size = UDim2.new(1, 0, 0, 28)
	frame.BackgroundColor3 = Theme.Colors.Panel
	frame.BackgroundTransparency = 0.5
	frame.BorderSizePixel = 0

	applyCorner(frame, Theme.CornerRadius.sm)

	-- Side indicator stripe
	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(0, 3, 0.8, 0)
	stripe.Position = UDim2.new(0, 2, 0.1, 0)
	stripe.BackgroundColor3 = Theme.GetSideColor(props.side)
	stripe.BorderSizePixel = 0
	stripe.Parent = frame
	applyCorner(stripe, Theme.CornerRadius.sm)

	-- Name
	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(0.4, -8, 1, 0)
	name.Position = UDim2.new(0, 10, 0, 0)
	name.BackgroundTransparency = 1
	name.Font = Theme.Font.PrimaryBold
	name.TextSize = Theme.TextSize.xs
	name.TextColor3 = (props.isAlive ~= false)
		and Theme.Colors.TextPrimary or Theme.Colors.TextDisabled
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = props.name or "Unit"
	name.Parent = frame

	-- HP mini bar
	local hpBar = UIComponents.ResourceBar({
		current = props.currentHp or 0,
		max = props.maxHp or 1,
		size = UDim2.new(0.35, 0, 0, 8),
		showText = false,
	})
	hpBar.Position = UDim2.new(0.42, 0, 0.5, -4)
	hpBar.Parent = frame

	-- Status icons (compact)
	if props.statuses and #props.statuses > 0 then
		local statusFrame = Instance.new("Frame")
		statusFrame.Size = UDim2.new(0.2, 0, 1, -4)
		statusFrame.Position = UDim2.new(0.78, 0, 0, 2)
		statusFrame.BackgroundTransparency = 1
		statusFrame.Parent = frame

		local statusLayout = Instance.new("UIListLayout")
		statusLayout.FillDirection = Enum.FillDirection.Horizontal
		statusLayout.Padding = UDim.new(0, 2)
		statusLayout.Parent = statusFrame

		for i, s in ipairs(props.statuses) do
			if i > 3 then break end -- Max 3 visible in compact row
			local icon = UIComponents.StatusIcon({
				statusId = s.id,
				remainingTurns = s.remainingTurns,
				size = 16,
			})
			icon.Parent = statusFrame
		end
	end

	return frame
end

return UIComponents
