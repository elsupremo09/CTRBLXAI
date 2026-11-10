--!strict
-- MerchantScreen.lua
-- CTRBLXAI | Merchant full screen (2026-10-31, user ruling): its own screen like the Loadout
-- screen, opened from the guild menu today and by the Merchant NPC/structure later. Back
-- returns to whatever opened it.
--
-- Layout (GuildScreen), user rulings 2026-10-31:
--   LEFT   tile grid
--   RIGHT  [Buy][Sell] sub-tabs (Loadout sub-tab size, 24 px) on top of the item inspector;
--          the price is shown inside the inspector
--   BOTTOM ONE row of square icons, lower right:  [+/-] [check] [X] [Back]
--          +/- adds / removes the selected item; check and X open a prompt that needs a
--          second confirmation (Confirm all / Discard all)
-- The old 'Pending: ...' summary line is removed; the header gold shows the projected result.
--
-- Display + input only (ARC-001 / SEC-002). Pending buys/sells are owned by the caller
-- (guild menu basket, per-screen Confirm/Discard); this screen reads and toggles them through
-- the injected context and never sends a price to the server. Context is nil-safe (ARC-006).

local WAIT = 10

local uiFolder = script.Parent
local themeModule = uiFolder:WaitForChild("Theme", WAIT)
local guildScreenModule = uiFolder:WaitForChild("GuildScreen", WAIT)
local inspectorModule = uiFolder:WaitForChild("MerchantInspector", WAIT)
if not themeModule or not guildScreenModule or not inspectorModule then
	error("[MerchantScreen] Theme / GuildScreen / MerchantInspector module not found")
end
-- Found at runtime via WaitForChild; the editor cannot follow that path (editor-only cast).
local Theme: any = (require :: any)(themeModule)
local GuildScreen: any = (require :: any)(guildScreenModule)
local MerchantInspector: any = (require :: any)(inspectorModule)

local MerchantScreen = {}

--------------------------------------------------
-- TYPES / STATE
--------------------------------------------------

-- Injected by the opener (guild menu today). tab = "Buy" | "Sell".
export type Context = {
	parent: Instance,                                  -- PlayerGui
	getStock: () -> any?,                              -- GetMerchantStock answer (cached)
	isQueued: (tab: string, key: any) -> boolean,
	toggle: (tab: string, key: any, name: string, price: number?) -> (),
	pendingCount: () -> number,
	summary: () -> any,                                -- { nBuy, buyGold, nSell, sellGold }
	confirm: () -> (),                                 -- commit the pending list
	discard: () -> (),                                 -- revert the pending list
	requestBack: (close: () -> ()) -> (),              -- Confirm/Discard prompt, then close
	onClosed: () -> (),                                -- opener re-shows itself
}

local BUTTON_ROWS = 1
local SUBTAB_H = 24           -- Loadout sub-tab height (LoadoutScreen SUBTAB_H, user ruling 2026-10-08)
local SUBTAB_GAP = 6          -- Loadout sub-tab spacing

local ctx: Context? = nil
local screen: any = nil
local isOpen = false
local currentTab = "Buy"
local selectedKey: { [string]: any } = {}

--------------------------------------------------
-- BUILDERS
--------------------------------------------------

local function makeRow(parent: Instance, order: number): Frame
	local row = Instance.new("Frame")
	row.Name = `Row{order}`
	row.Size = UDim2.new(1, 0, 0, GuildScreen.ROW_H)
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, GuildScreen.ROW_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	row.Parent = parent
	return row
end

local function iconButton(row: Instance, kind: string, name: string, order: number, enabled: boolean, onTap: () -> ())
	-- Square icon art (Theme.MakeIconButton); disabled = faded and never fires.
	local b = Theme.MakeIconButton(nil, kind, if enabled then onTap else nil, {
		name = name,
		size = UDim2.fromOffset(GuildScreen.ROW_H, GuildScreen.ROW_H),
		disabled = not enabled,
	})
	b.LayoutOrder = order
	b.Parent = row
end

local function makeNote(parent: Instance, text: string, order: number)
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.BorderSizePixel = 0
	lbl.Font = Theme.Font.Primary
	lbl.TextSize = Theme.Text.Small()
	lbl.TextColor3 = Theme.Colors.TextSecondary
	lbl.TextWrapped = true
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Size = UDim2.new(1, 0, 0, 0)
	lbl.AutomaticSize = Enum.AutomaticSize.Y
	lbl.LayoutOrder = order
	lbl.Text = text
	lbl.Parent = parent
end

local function plural(n: number): string
	return if n == 1 then "item" else "items"
end

--------------------------------------------------
-- RENDER
--------------------------------------------------

local render: () -> () -- forward declaration (button callbacks re-render)

local function buildEntries(res: any, isBuy: boolean): { any }
	local c = ctx
	local entries = {}
	if not c or not res then return entries end
	if isBuy then
		for _, o in res.stock or {} do
			table.insert(entries, {
				key = o.offerIndex, detail = o.detail, name = o.name, level = o.level,
				rarity = o.rarity, price = o.price, queued = c.isQueued("Buy", o.offerIndex),
			})
		end
	else
		for _, it in res.sellable or {} do
			table.insert(entries, {
				key = it.instanceId, detail = it.detail, name = it.name, level = it.level,
				rarity = it.rarity, price = it.price, queued = c.isQueued("Sell", it.instanceId),
			})
		end
	end
	return entries
end

local function buildMain(res: any, isBuy: boolean, entries: { any }, selected: any?)
	local main = screen.Main
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 4)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = main

	-- Existing notes, kept by user decision 2026-10-31.
	if res and isBuy then
		makeNote(main, `Merchant L{res.merchantLevel or 1}: {res.slots or #(res.stock or {})} items. Stock refreshes every 5 battles.`, 1)
		if #(res.stock or {}) == 0 then
			makeNote(main, if res.reason then tostring(res.reason) else "Sold out for now.", 2)
		end
	elseif res and #(res.sellable or {}) == 0 then
		makeNote(main, "Nothing to sell. Unequip an item first to sell it.", 1)
	end
	if #entries == 0 then return end

	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.Size = UDim2.fromScale(1, 0)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 4
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.LayoutOrder = 10
	local flex = Instance.new("UIFlexItem") -- grid fills the height left under the notes
	flex.FlexMode = Enum.UIFlexMode.Fill
	flex.Parent = grid
	MerchantInspector.BuildGrid(grid, {
		-- Loadout tile size from the grid's height (2026-11-10: same tiles on every guild screen).
		heightHint = MerchantInspector.GridHeightHint(main, list),
		entries = entries,
		selectedKey = if selected then selected.key else nil,
		width = math.max(240, main.AbsoluteSize.X - 6),
		onSelect = function(key: any)
			selectedKey[currentTab] = key
			render()
		end,
	})
	grid.Parent = main
end

-- RIGHT column: Buy / Sell sub-tabs on top, the item inspector below them.
local function buildSide(selected: any?)
	local side = screen.Side
	local tabs = Instance.new("Frame")
	tabs.Name = "SubTabs"
	tabs.Size = UDim2.new(1, 0, 0, SUBTAB_H)
	tabs.BackgroundTransparency = 1
	tabs.BorderSizePixel = 0
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, SUBTAB_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = tabs
	for i, tab in { "Buy", "Sell" } do
		-- Same call shape as the Loadout GEAR / CONSUMABLES sub-tabs (two halves, default text).
		Theme.MakeTabButton(tabs, tab, if currentTab == tab then "Active" else "Inactive", function()
			if currentTab == tab then return end
			currentTab = tab
			render()
		end, {
			name = `SubTab_{tab}`,
			size = UDim2.new(0.5, -SUBTAB_GAP // 2, 1, 0),
			layoutOrder = i,
		})
	end
	tabs.Parent = side

	local holder = Instance.new("Frame")
	holder.Name = "DetailHolder"
	holder.Size = UDim2.new(1, 0, 1, -(SUBTAB_H + SUBTAB_GAP))
	holder.Position = UDim2.fromOffset(0, SUBTAB_H + SUBTAB_GAP)
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Parent = side
	MerchantInspector.BuildDetail(holder, selected)
end

-- Check button: show the totals and ask for a second confirmation before committing.
local function promptConfirm()
	local c = ctx
	if not c or not screen then return end
	local s = c.summary()
	local lines = {}
	if s.nBuy > 0 then table.insert(lines, `Buy {s.nBuy} {plural(s.nBuy)}: -{s.buyGold} gold`) end
	if s.nSell > 0 then table.insert(lines, `Sell {s.nSell} {plural(s.nSell)}: +{s.sellGold} gold`) end
	local net = s.sellGold - s.buyGold
	table.insert(lines, `Net: {if net >= 0 then "+" else ""}{net} gold`)
	screen.Prompt(table.concat(lines, "\n"), "Confirm", "Primary", function()
		c.confirm()
		render()
	end)
end

-- X button: ask before throwing the pending list away.
local function promptDiscard()
	local c = ctx
	if not c or not screen then return end
	local s = c.summary()
	local parts = {}
	if s.nBuy > 0 then table.insert(parts, `buy {s.nBuy}`) end
	if s.nSell > 0 then table.insert(parts, `sell {s.nSell}`) end
	local detailText = if #parts > 0 then ` ({table.concat(parts, ", ")})` else ""
	screen.Prompt(`Discard all pending changes{detailText}?`, "Discard", "Tertiary", function()
		c.discard()
		render()
	end)
end

-- ONE row of square icons, lower right: [+/-] [check] [X] [Back].
local function buildButtons(selected: any?)
	local c = ctx
	if not c then return end
	local row = makeRow(screen.Buttons, 1)
	local hasPending = c.pendingCount() > 0

	-- + adds the selected item, - removes it (not sellable / nothing selected = faded).
	local isQueued = selected ~= nil and selected.queued
	local canToggle = selected ~= nil and (selected.queued or selected.price ~= nil)
	iconButton(row, if isQueued then "Minus" else "Plus", "Btn_Toggle", 1, canToggle, function()
		if not selected then return end
		selectedKey[currentTab] = selected.key
		c.toggle(currentTab, selected.key, selected.name, selected.price)
		render()
	end)
	iconButton(row, "Confirm", "Btn_ConfirmAll", 2, hasPending, promptConfirm)
	iconButton(row, "X", "Btn_DiscardAll", 3, hasPending, promptDiscard)
	iconButton(row, "Back", "Btn_BACK", 4, true, function()
		c.requestBack(MerchantScreen.Close)
	end)
end

render = function()
	local c = ctx
	if not c or not screen or not isOpen then return end
	screen.Clear(currentTab) -- same tab keeps the grid's scroll position
	local isBuy = currentTab == "Buy"
	local res = c.getStock() -- nil on a server error (the error is shown in the status line)
	local entries = buildEntries(res, isBuy)
	local selected = MerchantInspector.ResolveSelected(entries, selectedKey[currentTab])
	buildMain(res, isBuy, entries, selected)
	buildSide(selected)
	buildButtons(selected)
end

--------------------------------------------------
-- PUBLIC
--------------------------------------------------

function MerchantScreen.Init(c: Context)
	ctx = c
end

function MerchantScreen.IsOpen(): boolean
	return isOpen
end

-- ScreenGui while open (the opener parents its Confirm/Discard prompt here), else nil.
function MerchantScreen.GetGui(): ScreenGui?
	return if isOpen and screen then screen.Gui else nil
end

function MerchantScreen.Open()
	local c = ctx
	if not c then
		warn("[MerchantScreen] Open called before Init")
		return
	end
	if not screen then
		screen = GuildScreen.Create({ name = "MerchantScreen", title = "MERCHANT", parent = c.parent })
		screen.SetButtonRows(BUTTON_ROWS)
	end
	currentTab = "Buy"
	isOpen = true
	screen.SetStatus("")
	screen.Show()
	render()
	print("[MerchantScreen] Opened")
end

-- Back path: hide and hand control back to the opener.
function MerchantScreen.Close()
	if not isOpen then return end
	isOpen = false
	if screen then screen.Hide() end
	local c = ctx
	if c then c.onClosed() end
	print("[MerchantScreen] Closed")
end

-- Forced hide (menu closed by the server): no onClosed, the opener is going away too.
function MerchantScreen.Hide()
	if not isOpen then return end
	isOpen = false
	if screen then screen.Hide() end
end

-- Re-render while open (after a server answer changed the stock or the pending list).
function MerchantScreen.Render()
	render()
end

function MerchantScreen.SetGold(text: string)
	if screen then screen.SetGold(text) end
end

function MerchantScreen.SetStatus(text: string, isError: boolean?)
	if screen then screen.SetStatus(text, isError) end
end

return table.freeze(MerchantScreen)
