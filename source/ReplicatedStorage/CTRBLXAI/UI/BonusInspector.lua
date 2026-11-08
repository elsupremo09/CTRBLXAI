--!strict
-- BonusInspector.lua
-- CTRBLXAI | Shared bonus inspector (2026-11-07, user request): one small popup that explains
-- what a bonus does, for BOTH numeric attributes (stat bonuses) and bonus passives. Any screen
-- can use it; the Runeforge is the first (an item's current lines and the gem tiles).
-- Display only (ARC-001): every text comes from the server's description of the bonus
-- (RuneforgeService.DescribeGem + ItemDisplay.DescribeBonusEffect, i.e. BonusData); this
-- module writes no rule or value of its own.
--
--   BonusInspector.Open(gui, info, actions)   -- actions = { { text, style?, onTap }, ... }
--   BonusInspector.Close()
--
-- A modal overlay: tap outside the box or Close to close. An action button closes it, then
-- runs. Tap-only (.Activated, project_rules 243); phone sizes (project_rules 244).

local WAIT = 10

local GuiService = game:GetService("GuiService")

local themeModule = script.Parent:WaitForChild("Theme", WAIT)
if not themeModule then
	error("[BonusInspector] Theme module not found")
end
-- Found at runtime via WaitForChild; the editor cannot follow that path (editor-only cast).
local Theme: any = (require :: any)(themeModule)

local BonusInspector = {}

export type Info = {
	name: string,
	kind: string?,        -- "stat" | "passive"
	tier: number?,
	bp: number?,          -- bonus-point cost
	effect: string?,      -- what it does (stat: "STR  +7  +9%"; passive: its description)
	effectLevel: number?, -- the item level `effect` was worked out for
	effectScales: boolean?, -- true: the value grows with item level (else it is fixed)
	onItem: boolean?,     -- true: effectLevel is the inspected item's own level
	desc: string?,        -- passive description (used when effect is missing)
	family: string?,
	group: string?,       -- exclusive group: "transform" | "pattern"
	minRarity: string?,
}
export type Action = { text: string, style: string?, onTap: () -> () }

-- Same meaning as the server's one-per-item rule (RuneforgeService / ItemGenerator
-- EXCLUSIVE_GROUP); wording only.
local GROUP_TEXT: { [string]: string } = {
	transform = "Only one elemental change per item.",
	pattern = "Only one attack-shape change per item.",
}
-- Shared with the Runeforge (?) guide so the wording lives in one place (2026-11-07).
BonusInspector.GROUP_TEXT = table.freeze(GROUP_TEXT)

-- Above the screen and the facility guide, below GuildScreen's confirm prompt (ZIndex 20).
local ZINDEX = 18
local BOX_MAX = Vector2.new(440, 320)

local current: Instance? = nil

local function buttonH(): number
	return if Theme.GetMode() == "Mobile" then Theme.MinSize.TouchTarget else 32
end

local function label(parent: Instance, text: string, bold: boolean, color: Color3, order: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Font = if bold then Theme.Font.PrimaryBold else Theme.Font.Primary
	l.TextSize = Theme.Text.Small()
	l.TextColor3 = color
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.LayoutOrder = order
	l.Text = text
	l.Parent = parent
	return l
end

-- The text lines for a bonus (pure, so a test can check them without building UI).
function BonusInspector.Describe(info: Info): { { text: string, kind: string } }
	local out = {}
	local sub = {}
	if info.kind == "passive" then
		table.insert(sub, "Bonus passive")
	elseif info.kind == "stat" then
		table.insert(sub, "Stat bonus")
		if info.tier and info.tier > 0 then table.insert(sub, `Tier {info.tier}`) end
	end
	if type(info.bp) == "number" then table.insert(sub, `{info.bp} pts`) end
	if info.minRarity then table.insert(sub, `{info.minRarity}+`) end
	if #sub > 0 then table.insert(out, { text = table.concat(sub, "  ·  "), kind = "sub" }) end
	local effect = info.effect or info.desc
	if effect and effect ~= "" then
		if info.kind == "stat" and info.effectLevel and info.effectScales then
			effect ..= if info.onItem then `  (on this Lv{info.effectLevel} item)`
				else `  (at item Lv{info.effectLevel}; lower on lower-level gear)`
		end
		table.insert(out, { text = effect, kind = "effect" })
	else
		table.insert(out, { text = "No description available.", kind = "note" })
	end
	if info.kind == "stat" and info.family then
		table.insert(out, { text = `One {info.family} line per item.`, kind = "note" })
	end
	local g = info.group and GROUP_TEXT[info.group]
	if g then table.insert(out, { text = g, kind = "note" }) end
	return out
end

function BonusInspector.Close()
	local c = current
	current = nil
	if c then c:Destroy() end
end

function BonusInspector.IsOpen(): boolean
	return current ~= nil
end

function BonusInspector.Open(gui: Instance, info: Info, actions: { Action }?)
	BonusInspector.Close()
	local h = buttonH()

	local overlay = Instance.new("TextButton")
	overlay.Name = "BonusInspector"
	overlay.Text = ""
	overlay.AutoButtonColor = false
	overlay.Modal = true
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.5
	overlay.BorderSizePixel = 0
	overlay.ZIndex = ZINDEX
	overlay.Activated:Connect(BonusInspector.Close) -- tap outside the box closes

	-- A button so taps on the box don't fall through to the overlay (and close it).
	local box = Instance.new("TextButton")
	box.Name = "Box"
	box.Text = ""
	box.AutoButtonColor = false
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	-- The screen ignores the top-bar inset, so keep the box below Roblox's top buttons.
	local insetY = GuiService:GetGuiInset().Y
	box.Position = UDim2.new(0.5, 0, 0.5, insetY // 2)
	box.Size = UDim2.new(0.62, 0, 0.72, -insetY)
	box.BackgroundColor3 = Theme.Colors.PanelRaised
	box.BorderSizePixel = 0
	local cap = Instance.new("UISizeConstraint")
	cap.MaxSize = BOX_MAX
	cap.Parent = box
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius.md
	corner.Parent = box
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Theme.Colors.Border
	stroke.Thickness = Theme.BorderThickness.Default
	stroke.Parent = box

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.BorderSizePixel = 0
	title.Font = Theme.Font.PrimaryBold
	title.TextSize = Theme.Text.Body()
	title.TextColor3 = if info.minRarity then Theme.GetRarityColor(info.minRarity) else Theme.Colors.TextGold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Size = UDim2.new(1, -24, 0, 22)
	title.Position = UDim2.fromOffset(12, 8)
	title.Text = info.name
	title.Parent = box

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Body"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(12, 32)
	scroll.Size = UDim2.new(1, -18, 1, -(32 + h + 16))
	scroll.ScrollBarThickness = 4
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	local pad = Instance.new("UIPadding")
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = scroll
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 4)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = scroll
	for i, line in BonusInspector.Describe(info) do
		local color = if line.kind == "effect" then Theme.Colors.TextPrimary
			elseif line.kind == "sub" then Theme.Colors.TextSecondary else Theme.Colors.TextSecondary
		label(scroll, line.text, line.kind ~= "note", color, i).Name = `Line_{line.kind}`
	end
	scroll.Parent = box

	-- Buttons: the caller's actions, then Close. Bar buttons (white text, black outline).
	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.Size = UDim2.new(1, -24, 0, h)
	row.Position = UDim2.new(0, 12, 1, -(h + 8))
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	for i, a in actions or {} do
		local onTap = a.onTap
		Theme.MakeBarButton(row, a.text, a.style or "Primary", function()
			BonusInspector.Close()
			onTap()
		end, { name = `Btn_Inspect_{i}`, minHeight = h, layoutOrder = i })
	end
	Theme.MakeBarButton(row, "Close", "Secondary", BonusInspector.Close,
		{ name = "Btn_InspectClose", minHeight = h, layoutOrder = 100 })
	row.Parent = box

	box.Parent = overlay
	overlay.Parent = gui -- parent last (NET-004)
	current = overlay
end

return table.freeze(BonusInspector)
