--!strict
-- ApothecaryScreen.lua
-- CTRBLXAI | Apothecary full screen (USER DECISION 2026-11-03; DB guild_facilities 67-73).
-- Same frame as the Merchant / Crucible screens (GuildScreen + item tile grid).
--
-- Tabs (top of the right panel): BUY (the seeded shelf) | SELL (owned loose copies) | REFILL
--   BUY / SELL: tap a tile, then Confirm -> a prompt that needs a second confirmation; it
--   commits straight away (no basket, like the Crucible). One item per confirm.
--   REFILL: what the next refill costs, the auto-refill switch and a "Refill now" button.
-- The client sends shelf slots / ids only; the server prices everything (SEC-002).
-- Display + input only (ARC-001). Context is nil-safe (ARC-006). Tap-only input.

local WAIT = 10

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local uiFolder = script.Parent
local themeModule = uiFolder:WaitForChild("Theme", WAIT)
local guildScreenModule = uiFolder:WaitForChild("GuildScreen", WAIT)
local inspectorModule = uiFolder:WaitForChild("MerchantInspector", WAIT)
local contentFolder = ReplicatedStorage:WaitForChild("Content", WAIT)
local consumableModule = contentFolder and contentFolder:WaitForChild("ConsumableData", WAIT)
if not themeModule or not guildScreenModule or not inspectorModule or not consumableModule then
	error("[ApothecaryScreen] Theme / GuildScreen / MerchantInspector / ConsumableData not found")
end
local Theme: any = (require :: any)(themeModule)
local GuildScreen: any = (require :: any)(guildScreenModule)
local MerchantInspector: any = (require :: any)(inspectorModule)
local ConsumableData: any = (require :: any)(consumableModule)

local ApothecaryScreen = {}

export type Context = {
	parent: Instance,
	getState: () -> any?,                 -- GetApothecary answer (cached)
	commit: (cart: any) -> any?,          -- CommitApothecary answer, nil on error
	refill: (cmd: any) -> any?,           -- ApothecaryRefill answer, nil on error
	onChanged: () -> (),
	onClosed: () -> (),
}

local SUBTAB_H = 24
local STATE_RETRY_DELAY = 0.3
local STATE_RETRY_MAX = 3

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

local function itemName(id: string): string
	local def = ConsumableData.GetById(id)
	return def and def.name or id
end

local render: () -> ()

local function buildEntries(state: any): { any }
	local entries = {}
	if not state then return entries end
	if currentTab == "Buy" then
		for _, e in state.shelf or {} do
			local def = ConsumableData.GetById(e.id)
			table.insert(entries, {
				key = e.slot, id = e.id, name = itemName(e.id), level = nil,
				rarity = def and def.tier or "Common", price = if e.bought then nil else e.price,
				queued = e.bought == true, detail = { icon = def and def.icon or nil }, row = e,
			})
		end
	elseif currentTab == "Sell" then
		for _, o in state.owned or {} do
			local def = ConsumableData.GetById(o.id)
			table.insert(entries, {
				key = o.id, id = o.id, name = `{itemName(o.id)} x{o.count}`, level = nil,
				rarity = def and def.tier or "Common", price = o.sellPrice,
				queued = false, detail = { icon = def and def.icon or nil }, row = o,
			})
		end
	end
	return entries
end

local function fillDetail(parent: Instance, entry: any?)
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 3)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = parent
	if not entry then return end
	local def = ConsumableData.GetById(entry.id)
	if not def then return end
	makeNote(parent, def.name, 1, Theme.GetRarityColor(def.tier or "Common"), true)
	makeNote(parent, `{def.category} | {def.tier} | {def.maxCharges or 1} charge(s) | RT {def.rtCost or 0} | Range {def.range or 0}`, 2)
	makeNote(parent, def.displayText or def.effectFormula or "", 3, Theme.Colors.TextPrimary)
	if currentTab == "Buy" then
		if entry.row.bought then
			makeNote(parent, "Bought. The shelf restocks every 5 battles.", 4, Theme.Colors.TextDisabled)
		else
			makeNote(parent, `Price: {entry.row.price}g (list {entry.row.listPrice}g)`, 4, Theme.Colors.TextGold, true)
		end
	else
		makeNote(parent, `You own {entry.row.count}. Sells for {entry.row.sellPrice}g each.`, 4, Theme.Colors.TextGold, true)
	end
end

local function promptCommit(state: any, entry: any)
	local c = ctx
	if not c or not screen or busy then return end
	local text, cart
	if currentTab == "Buy" then
		text = `Buy {entry.name} for {entry.row.price} gold?`
		cart = { buys = { entry.key }, sells = {} }
	else
		text = `Sell 1 {itemName(entry.id)} for {entry.row.sellPrice} gold?`
		cart = { buys = {}, sells = { [entry.id] = 1 } }
	end
	screen.Prompt(text, "Confirm", "Primary", function()
		busy = true
		local res = c.commit(cart)
		busy = false
		if res then c.onChanged() end
		render()
	end)
end

local function sideButton(parent: Instance, text: string, order: number, onTap: () -> ())
	local b = Theme.MakeButton(parent, text, "Primary")
	b.Size = UDim2.new(1, 0, 0, 32)
	b.LayoutOrder = order
	b.MouseButton1Click:Connect(onTap)
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
	screen.Clear()

	local locked = state == nil or state.lockedReason ~= nil
	if locked and currentTab ~= "Refill" then currentTab = "Refill" end -- refill works before it is built
	local entries = buildEntries(state)
	local selected = if #entries > 0 then MerchantInspector.ResolveSelected(entries, tappedKey) else nil
	tappedKey = if selected then selected.key else nil

	-- LEFT
	local main = screen.Main
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 4)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = main
	if state then
		if state.lockedReason then
			makeNote(main, tostring(state.lockedReason), 1, Theme.Colors.Warning, true)
			makeNote(main, `Until then, used consumables still refill automatically at base for {state.refillRate}% of their price.`, 2)
		else
			makeNote(main, `Apothecary L{state.level}: buy -{state.discountPct}%, refill {state.refillRate}% of list price.`, 1)
		end
	end
	if currentTab ~= "Refill" then
		if #entries == 0 then
			makeNote(main, if currentTab == "Buy" then "The shelf is empty." else "You don't own any loose consumables.", 2)
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

	-- RIGHT: sub-tabs + detail / refill panel
	local side = screen.Side
	local tabs = Instance.new("Frame")
	tabs.Name = "SubTabs"
	tabs.Size = UDim2.new(1, 0, 0, SUBTAB_H)
	tabs.BackgroundTransparency = 1
	local tl = Instance.new("UIListLayout")
	tl.FillDirection = Enum.FillDirection.Horizontal
	tl.Padding = UDim.new(0, 6)
	tl.Parent = tabs
	for i, name in { "Buy", "Sell", "Refill" } do
		local enabled = name == "Refill" or not locked
		local b = Theme.MakeTabButton(tabs, string.upper(name), if currentTab == name then "Active" else "Inactive", function()
			if not enabled or currentTab == name then return end
			currentTab = name
			tappedKey = nil
			render()
		end)
		b.Size = UDim2.new(1 / 3, -4, 1, 0)
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
	if currentTab == "Refill" then
		local blist = Instance.new("UIListLayout")
		blist.Padding = UDim.new(0, 4)
		blist.SortOrder = Enum.SortOrder.LayoutOrder
		blist.Parent = body
		local p = state and state.refillPreview
		if p then
			if (p.refilled or 0) == 0 and (p.skippedCharges or 0) == 0 then
				makeNote(body, "Every equipped consumable is full.", 1, Theme.Colors.TextPrimary, true)
			else
				makeNote(body, `Refill {p.refilled} charge(s) for {p.cost} gold ({p.rate}% of list price).`, 1, Theme.Colors.TextGold, true)
				if (p.skippedCharges or 0) > 0 then
					makeNote(body, `{p.skippedCharges} charge(s) can't be refilled - need {p.needGold} more gold.`, 2, Theme.Colors.Warning)
				end
			end
		end
		if state and not locked then
			makeNote(body, `Auto-refill on return to base: {if state.autoRefill then "ON" else "OFF"}`, 3)
			sideButton(body, if state.autoRefill then "TURN AUTO-REFILL OFF" else "TURN AUTO-REFILL ON", 4, function()
				if busy then return end
				busy = true
				local res = c.refill({ action = "SetAuto", on = not state.autoRefill })
				busy = false
				if res then c.onChanged() end
				render()
			end)
		else
			makeNote(body, "Auto-refill is always on until the Apothecary is built.", 3)
		end
		if p and (p.refilled or 0) > 0 then
			sideButton(body, `REFILL NOW ({p.cost}g)`, 5, function()
				if busy then return end
				busy = true
				local res = c.refill({ action = "RefillNow" })
				busy = false
				if res then c.onChanged() end
				render()
			end)
		end
	else
		fillDetail(body, selected)
	end
	body.Parent = side

	-- BOTTOM RIGHT: one row of icons
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
	local canCommit = not locked and not busy and currentTab ~= "Refill" and selected ~= nil
		and not (currentTab == "Buy" and selected.row.bought)
	iconButton(row, "Confirm", "Btn_Confirm", 1, canCommit, function()
		if selected then promptCommit(state, selected) end
	end)
	iconButton(row, "Back", "Btn_BACK", 10, true, function()
		ApothecaryScreen.Close()
	end)
end

function ApothecaryScreen.Init(c: Context)
	ctx = c
end

function ApothecaryScreen.IsOpen(): boolean
	return isOpen
end

function ApothecaryScreen.GetGui(): ScreenGui?
	return if isOpen and screen then screen.Gui else nil
end

function ApothecaryScreen.Open()
	local c = ctx
	if not c then
		warn("[ApothecaryScreen] Open called before Init")
		return
	end
	if not screen then
		screen = GuildScreen.Create({ name = "ApothecaryScreen", title = "APOTHECARY", parent = c.parent })
		screen.SetButtonRows(1)
	end
	currentTab = "Buy"
	tappedKey = nil
	stateRetries = STATE_RETRY_MAX
	isOpen = true
	screen.SetStatus("")
	screen.Show()
	render()
	print("[ApothecaryScreen] Opened")
end

function ApothecaryScreen.Close()
	if not isOpen then return end
	isOpen = false
	if screen then screen.Hide() end
	local c = ctx
	if c then c.onClosed() end
	print("[ApothecaryScreen] Closed")
end

function ApothecaryScreen.Hide()
	if not isOpen then return end
	isOpen = false
	if screen then screen.Hide() end
end

function ApothecaryScreen.Render()
	render()
end

function ApothecaryScreen.SetGold(text: string)
	if screen then screen.SetGold(text) end
end

function ApothecaryScreen.SetStatus(text: string, isError: boolean?)
	if screen then screen.SetStatus(text, isError) end
end

return table.freeze(ApothecaryScreen)
