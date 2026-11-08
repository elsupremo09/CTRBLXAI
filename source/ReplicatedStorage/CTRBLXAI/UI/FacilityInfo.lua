--!strict
-- FacilityInfo.lua
-- CTRBLXAI | Shared "how this facility works" guide (2026-11-07, user request: one info (?)
-- button explains a facility, so the screen itself needs no helper text; mobile space).
-- Any guild screen can use it; the Runeforge is the first. Display only (ARC-001).
--
--   FacilityInfo.Open(gui, title, sections)   -- sections = { { heading, body }, ... }
--   FacilityInfo.Close()
--
-- A modal overlay: tap outside the box or the X to close. Tap-only (.Activated,
-- project_rules 243); phone sizes (project_rules 244): 44 px close button, text >= 10 px.

local WAIT = 10

local GuiService = game:GetService("GuiService")

local themeModule = script.Parent:WaitForChild("Theme", WAIT)
if not themeModule then
	error("[FacilityInfo] Theme module not found")
end
-- Found at runtime via WaitForChild; the editor cannot follow that path (editor-only cast).
local Theme: any = (require :: any)(themeModule)

local FacilityInfo = {}

export type Section = { heading: string, body: string }

-- Above the screen, below GuildScreen's confirm prompt (ZIndex 20, Sibling behaviour).
local ZINDEX = 19
local BOX_MAX = Vector2.new(560, 640)

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

function FacilityInfo.Close()
	local c = current
	current = nil
	if c then c:Destroy() end
end

function FacilityInfo.IsOpen(): boolean
	return current ~= nil
end

function FacilityInfo.Open(gui: Instance, title: string, sections: { Section })
	FacilityInfo.Close()
	local h = buttonH()

	local overlay = Instance.new("TextButton")
	overlay.Name = "FacilityInfo"
	overlay.Text = ""
	overlay.AutoButtonColor = false
	overlay.Modal = true
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.4
	overlay.BorderSizePixel = 0
	overlay.ZIndex = ZINDEX
	overlay.Activated:Connect(FacilityInfo.Close) -- tap outside the box closes

	-- A button so taps on the box don't fall through to the overlay (and close it).
	local box = Instance.new("TextButton")
	box.Name = "Box"
	box.Text = ""
	box.AutoButtonColor = false
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	-- The screen ignores the top-bar inset, so keep the box below Roblox's top buttons.
	local insetY = GuiService:GetGuiInset().Y
	box.Position = UDim2.new(0.5, 0, 0.5, insetY // 2)
	box.Size = UDim2.new(0.82, 0, 0.88, -insetY)
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

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Name = "Title"
	titleLbl.BackgroundTransparency = 1
	titleLbl.BorderSizePixel = 0
	titleLbl.Font = Theme.Font.PrimaryBold
	titleLbl.TextSize = Theme.Text.Body()
	titleLbl.TextColor3 = Theme.Colors.TextGold
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.TextTruncate = Enum.TextTruncate.AtEnd
	titleLbl.Size = UDim2.new(1, -(h + 24), 0, h)
	titleLbl.Position = UDim2.fromOffset(12, 6)
	titleLbl.Text = title
	titleLbl.Parent = box

	Theme.MakeIconButton(box, "X", FacilityInfo.Close, {
		name = "Btn_InfoClose",
		size = UDim2.fromOffset(h, h),
		position = UDim2.new(1, -(h + 6), 0, 6),
	})

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Body"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(12, h + 12)
	scroll.Size = UDim2.new(1, -18, 1, -(h + 20))
	scroll.ScrollBarThickness = 4
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	local pad = Instance.new("UIPadding")
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = scroll
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 3)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = scroll
	local order = 0
	for _, s in sections do
		order += 1
		local head = label(scroll, s.heading, true, Theme.Colors.TextGold, order)
		head.Name = "Heading"
		order += 1
		label(scroll, s.body, false, Theme.Colors.TextPrimary, order).Name = "Text"
	end
	scroll.Parent = box

	box.Parent = overlay
	overlay.Parent = gui -- parent last (NET-004)
	current = overlay
end

return table.freeze(FacilityInfo)
