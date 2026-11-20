--!strict
-- TipCard.lua
-- CTRBLXAI | New-player tips: the small dismissible card (new_player_tips SYS-02).
-- Title, 1-2 plain sentences, one "Got it" button. No spotlight, no dimming, tap only
-- (.Activated). Theme panel + colours. Built off-tree and parented last (NET-004).
-- Display only: TipController decides what to show and when.

local Players = game:GetService("Players")

local WAIT = 10

local uiFolder = script.Parent
local themeModule = uiFolder:WaitForChild("Theme", WAIT)
if not themeModule then error("[TipCard] Theme module not found") end
local Theme: any = (require :: any)(themeModule)

local TipCard = {}

local DISPLAY_ORDER = 250 -- above full screens (100), loadout popups (<=160); below UGC dropdowns (300)
local CARD_MAX_W = 420
local CARD_MIN_W = 260
local BUTTON_H = Theme.MinSize.TouchTarget -- 44 px touch target

local gui: ScreenGui? = nil
local current: GuiObject? = nil

local function ensureGui(): ScreenGui?
	if gui and gui.Parent then return gui end
	local player = Players.LocalPlayer
	local pg = player and player:WaitForChild("PlayerGui", WAIT)
	if not pg then
		warn("[TipCard] PlayerGui not found")
		return nil
	end
	local g = Instance.new("ScreenGui")
	g.Name = "TipCardGui"
	g.ResetOnSpawn = false
	g.DisplayOrder = DISPLAY_ORDER
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.Parent = pg
	gui = g
	return g
end

local function label(parent: Instance, text: string, size: number, color: Color3, bold: boolean, order: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = if bold then "Title" else "Body"
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.Font = if bold then Theme.Font.PrimaryBold else Theme.Font.Primary
	l.TextSize = size
	l.TextColor3 = color
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.Text = text
	l.LayoutOrder = order
	l.Parent = parent
	return l
end

function TipCard.Hide()
	if current then
		current:Destroy() -- connections die with the button (PRF-004)
		current = nil
	end
end

function TipCard.IsShowing(): boolean
	return current ~= nil
end

--- Shows one card. onDismiss runs once, when the player taps "Got it" (or the card cannot show).
function TipCard.Show(title: string, text: string, onDismiss: () -> ())
	TipCard.Hide()
	local g = ensureGui()
	if not g then
		onDismiss()
		return
	end
	local pad = Theme.Spacing.lg
	local panel = Theme.MakePanel("TipCard", UDim2.new(0.9, 0, 0, 0), UDim2.new(0.5, 0, 0, Theme.TopbarReserve + 8),
		Vector2.new(0.5, 0), nil, { autoY = true, minW = CARD_MIN_W, maxW = CARD_MAX_W, minH = 80, maxH = 360 })

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, pad)
	padding.PaddingBottom = UDim.new(0, pad)
	padding.PaddingLeft = UDim.new(0, pad)
	padding.PaddingRight = UDim.new(0, pad)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Theme.Spacing.md)
	layout.Parent = panel

	label(panel, title, Theme.Text.Heading(), Theme.Colors.TextGold, true, 1)
	label(panel, text, Theme.Text.Body(), Theme.Colors.TextPrimary, false, 2)

	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, BUTTON_H)
	row.LayoutOrder = 3
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Parent = row

	local done = false
	local function dismiss()
		if done then return end
		done = true
		TipCard.Hide()
		onDismiss()
	end
	Theme.MakeBarButton(row, "Got it", "Primary", dismiss, { name = "Btn_GotIt", minHeight = BUTTON_H })
	row.Parent = panel

	panel.Parent = g -- NET-004: everything set before the card enters the tree
	current = panel
end

return table.freeze(TipCard)
