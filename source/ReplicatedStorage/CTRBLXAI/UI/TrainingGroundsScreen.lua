--!strict
-- TrainingGroundsScreen.lua
-- CTRBLXAI | Training Grounds full screen: card shop (USER DECISION 2026-11-04).
-- Same frame as the Apothecary / Crucible screens (GuildScreen + item tile grid).
-- Tabs: BUY (seeded shelf) | SELL (owned loose cards). One card per Confirm prompt, which
-- commits straight away (no basket). The client sends a slot / card id only; the server
-- prices everything (SEC-002). Display + input only (ARC-001). Tap-only input.

local WAIT = 10

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local uiFolder = script.Parent
local themeModule = uiFolder:WaitForChild("Theme", WAIT)
local guildScreenModule = uiFolder:WaitForChild("GuildScreen", WAIT)
local inspectorModule = uiFolder:WaitForChild("MerchantInspector", WAIT)
local contentFolder = ReplicatedStorage:WaitForChild("Content", WAIT)
if not themeModule or not guildScreenModule or not inspectorModule or not contentFolder then
	error("[TrainingGroundsScreen] Theme / GuildScreen / MerchantInspector / Content not found")
end
local Theme: any = (require :: any)(themeModule)
local GuildScreen: any = (require :: any)(guildScreenModule)
local MerchantInspector: any = (require :: any)(inspectorModule)
local SkillData: any = (require :: any)(contentFolder:WaitForChild("SkillData", WAIT))
local AugmentData: any = (require :: any)(contentFolder:WaitForChild("AugmentData", WAIT))
local DoctrineData: any = (require :: any)(contentFolder:WaitForChild("DoctrineData", WAIT))

local TrainingGroundsScreen = {}

export type Context = {
	parent: Instance,
	getState: () -> any?,
	action: (cmd: any) -> any?,
	onChanged: () -> (),
	onClosed: () -> (),
}

local SUBTAB_H = 24
local STATE_RETRY_DELAY = 0.3
local STATE_RETRY_MAX = 3
-- Tile accent: the shop rarity (doctrines use the Epic colour band).
local RARITY_COLOR_KEY = { Rare = "Rare", Epic = "Epic", Legendary = "Legendary", Doctrine = "Epic" }

local ctx: Context? = nil
local screen: any = nil
local isOpen = false
local currentTab = "Buy"
local tappedKey: any = nil
local busy = false
local renderSeq = 0
local stateRetries = 0

local function makeNote(parent: Instance, text: string, order: number, color: Color3?, bold: boolean?)
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.BorderSizePixel = 0
	lbl.Font = if bold then Theme.Font.PrimaryBold else Theme.Font.Primary
	lbl.TextSize = Theme.Text.Small()
	lbl.TextColor3 = color or Theme.Colors.TextSecondary
	lbl.TextWrapped = true
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Size = UDim2.new(1, 0, 0, 0)
	lbl.AutomaticSize = Enum.AutomaticSize.Y
	lbl.LayoutOrder = order
	lbl.Text = text
	lbl.Parent = parent
end

local function iconButton(row: Instance, kind: string, name: string, order: number, enabled: boolean, onTap: () -> ())
	local b = Theme.MakeIconButton(nil, kind, if enabled then onTap else nil, {
		name = name,
		size = UDim2.fromOffset(GuildScreen.ROW_H, GuildScreen.ROW_H),
		disabled = not enabled,
	})
	b.LayoutOrder = order
	b.Parent = row
end

local function cardDef(kind: string, id: string): any
	if kind == "Skill" then return SkillData[id] end
	if kind == "Augment" then return AugmentData[id] end
	return DoctrineData[id]
end

local function cardName(kind: string, id: string): string
	local d = cardDef(kind, id)
	return (d and d.name) or id
end

local render: () -> ()

local function buildEntries(state: any): { any }
	local entries = {}
	if not state then return entries end
	local list = if currentTab == "Buy" then state.shelf else state.owned
	for _, e in list or {} do
		local d = cardDef(e.kind, e.id)
		local key = if currentTab == "Buy" then e.slot else `{e.kind}|{e.id}`
		table.insert(entries, {
			key = key, kind = e.kind, id = e.id,
			name = if currentTab == "Sell" then `{cardName(e.kind, e.id)} x{e.count}` else cardName(e.kind, e.id),
			rarity = RARITY_COLOR_KEY[e.rarity or "Rare"] or "Rare",
			price = if currentTab == "Buy" then (if e.bought then nil else e.price) else e.sellPrice,
			queued = currentTab == "Buy" and e.bought == true,
			detail = { icon = d and d.icon or nil }, row = e,
		})
	end
	return entries
end

local function fillDetail(parent: Instance, entry: any?)
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 3)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = parent
	if not entry then return end
	local d = cardDef(entry.kind, entry.id)
	if not d then return end
	local kindText = if entry.kind == "Skill" then "Skill card" elseif entry.kind == "Augment" then "Augment card" else "Doctrine"
	makeNote(parent, d.name or entry.id, 1, Theme.GetRarityColor(RARITY_COLOR_KEY[entry.row.rarity] or "Rare"), true)
	makeNote(parent, if entry.kind == "Doctrine" then kindText else `{kindText} | {entry.row.rarity}`, 2)
	makeNote(parent, d.description or d.passiveEffect or "", 3, Theme.Colors.TextPrimary)
	if currentTab == "Buy" then
		if entry.row.bought then
			makeNote(parent, "Bought. The shelf restocks every 5 battles.", 4, Theme.Colors.TextDisabled)
		else
			makeNote(parent, `Price: {entry.row.price}g (list {entry.row.listPrice}g)`, 4, Theme.Colors.TextGold, true)
		end
	else
		makeNote(parent, `You own {entry.row.count} loose. Sells for {entry.row.sellPrice}g each.`, 4, Theme.Colors.TextGold, true)
	end
end

local function promptCommit(entry: any)
	local c = ctx
	if not c or not screen or busy then return end
	local text, cmd
	if currentTab == "Buy" then
		text = `Buy {cardName(entry.kind, entry.id)} for {entry.row.price} gold?`
		cmd = { action = "Buy", slot = entry.key }
	else
		text = `Sell 1 {cardName(entry.kind, entry.id)} for {entry.row.sellPrice} gold?`
		cmd = { action = "Sell", kind = entry.kind, id = entry.id }
	end
	screen.Prompt(text, "Confirm", "Primary", function()
		busy = true
		local res = c.action(cmd)
		busy = false
		if res then c.onChanged() end
		render()
	end)
end

render = function()
	local c = ctx
	if not c or not screen or not isOpen then return end
	renderSeq += 1
	local mySeq = renderSeq
	local state = c.getState()
	if mySeq ~= renderSeq or not isOpen then return end
	if state == nil and stateRetries > 0 then
		stateRetries -= 1
		task.delay(STATE_RETRY_DELAY, function()
			if isOpen and mySeq == renderSeq then render() end
		end)
	elseif state ~= nil then
		stateRetries = STATE_RETRY_MAX
	end
	screen.Clear(currentTab) -- same tab keeps the grid's scroll position

	local locked = state == nil or state.lockedReason ~= nil
	local entries = if locked then {} else buildEntries(state)
	local selected = if #entries > 0 then MerchantInspector.ResolveSelected(entries, tappedKey) else nil
	tappedKey = if selected then selected.key else nil

	local main = screen.Main
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 4)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = main
	if state then
		if state.lockedReason then
			makeNote(main, tostring(state.lockedReason), 1, Theme.Colors.Warning, true)
		else
			makeNote(main, `Training Grounds L{state.level}: buy -{state.discountPct}%. Restocks every 5 battles.`, 1)
		end
	end
	if not locked then
		if #entries == 0 then
			makeNote(main, if currentTab == "Buy" then "The shelf is empty." else "You don't own any loose cards.", 2)
		else
			local grid = Instance.new("ScrollingFrame")
			grid.Name = "Grid"
			grid.Size = UDim2.fromScale(1, 0)
			grid.BackgroundTransparency = 1
			grid.BorderSizePixel = 0
			grid.ScrollBarThickness = 4
			grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
			grid.CanvasSize = UDim2.new()
			grid.LayoutOrder = 10
			local flex = Instance.new("UIFlexItem")
			flex.FlexMode = Enum.UIFlexMode.Fill
			flex.Parent = grid
			MerchantInspector.BuildGrid(grid, {
				-- Loadout tile size from the grid's height (2026-11-10: same tiles on every guild screen).
				heightHint = MerchantInspector.GridHeightHint(main, list),
				entries = entries,
				selectedKey = tappedKey,
				width = math.max(240, main.AbsoluteSize.X - 6),
				onSelect = function(key: any)
					tappedKey = key
					render()
				end,
			})
			grid.Parent = main
		end
	end

	local side = screen.Side
	local tabs = Instance.new("Frame")
	tabs.Name = "SubTabs"
	tabs.Size = UDim2.new(1, 0, 0, SUBTAB_H)
	tabs.BackgroundTransparency = 1
	local tl = Instance.new("UIListLayout")
	tl.FillDirection = Enum.FillDirection.Horizontal
	tl.Padding = UDim.new(0, 6)
	tl.Parent = tabs
	for i, name in { "Buy", "Sell" } do
		local b = Theme.MakeTabButton(tabs, string.upper(name), if currentTab == name then "Active" else "Inactive", function()
			if locked or currentTab == name then return end
			currentTab = name
			tappedKey = nil
			render()
		end)
		b.Size = UDim2.new(0.5, -3, 1, 0)
		b.LayoutOrder = i
	end
	tabs.Parent = side

	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.Size = UDim2.new(1, 0, 1, -(SUBTAB_H + 4))
	body.Position = UDim2.new(0, 0, 0, SUBTAB_H + 4)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.ScrollBarThickness = 4
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.CanvasSize = UDim2.new()
	fillDetail(body, selected)
	body.Parent = side

	local row = Instance.new("Frame")
	row.Name = "Row1"
	row.Size = UDim2.new(1, 0, 0, GuildScreen.ROW_H)
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, GuildScreen.ROW_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	row.Parent = screen.Buttons
	local canCommit = not locked and not busy and selected ~= nil
		and not (currentTab == "Buy" and selected.row.bought)
	iconButton(row, "Confirm", "Btn_Confirm", 1, canCommit, function()
		if selected then promptCommit(selected) end
	end)
	iconButton(row, "Back", "Btn_BACK", 10, true, function()
		TrainingGroundsScreen.Close()
	end)
end

function TrainingGroundsScreen.Init(c: Context)
	ctx = c
end

function TrainingGroundsScreen.IsOpen(): boolean
	return isOpen
end

function TrainingGroundsScreen.GetGui(): ScreenGui?
	return if isOpen and screen then screen.Gui else nil
end

function TrainingGroundsScreen.Open()
	local c = ctx
	if not c then
		warn("[TrainingGroundsScreen] Open called before Init")
		return
	end
	if not screen then
		screen = GuildScreen.Create({ name = "TrainingGroundsScreen", title = "TRAINING GROUNDS", parent = c.parent , crest = Theme.GuildIcons.TrainingGrounds, autoCurrencies = true }) -- 2026-11-20 user: nav button icon + currency icons
		screen.SetButtonRows(1)
	end
	currentTab = "Buy"
	tappedKey = nil
	stateRetries = STATE_RETRY_MAX
	isOpen = true
	screen.SetStatus("")
	screen.Show()
	render()
	print("[TrainingGroundsScreen] Opened")
end

function TrainingGroundsScreen.Close()
	if not isOpen then return end
	isOpen = false
	if screen then screen.Hide() end
	local c = ctx
	if c then c.onClosed() end
	print("[TrainingGroundsScreen] Closed")
end

function TrainingGroundsScreen.Hide()
	if not isOpen then return end
	isOpen = false
	if screen then screen.Hide() end
end

function TrainingGroundsScreen.Render()
	render()
end

function TrainingGroundsScreen.SetGold(text: string)
	if screen then screen.SetGold(text) end
end

function TrainingGroundsScreen.SetStatus(text: string, isError: boolean?)
	if screen then screen.SetStatus(text, isError) end
end

return table.freeze(TrainingGroundsScreen)
