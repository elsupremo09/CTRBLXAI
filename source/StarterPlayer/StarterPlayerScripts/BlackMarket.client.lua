--!strict
-- BlackMarket.client.lua
-- CTRBLXAI | Black Market shop screen during a battle (v2 build step 6b, 2026-11-01).
--
-- Opens when the server fires BlackMarketOpened (a player unit interacted with a Black Market).
-- Same frame as the Merchant screen: item tiles on the left, the inspector (with the price) on
-- the right, ONE button row lower right: [Confirm = buy the selected item] [Back].
-- Buying always asks a second time. The client sends only (objectId, slot); the server checks
-- everything and sets the price (SEC-002). Display + input only (ARC-001). Tap-only input.
-- Closes itself when the battle ends.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WAIT = 10

local CTRBLXAI = ReplicatedStorage:WaitForChild("CTRBLXAI", WAIT)
if not CTRBLXAI then
	warn("[BlackMarket] CTRBLXAI folder not found")
	return
end
local uiFolder = CTRBLXAI:WaitForChild("UI", WAIT)
local remotesFolder = CTRBLXAI:WaitForChild("Remotes", WAIT)
local themeModule = uiFolder and uiFolder:WaitForChild("Theme", WAIT)
local guildScreenModule = uiFolder and uiFolder:WaitForChild("GuildScreen", WAIT)
local inspectorModule = uiFolder and uiFolder:WaitForChild("MerchantInspector", WAIT)
local battleEventsModule = remotesFolder and remotesFolder:WaitForChild("BattleEvents", WAIT)
if not (themeModule and guildScreenModule and inspectorModule and battleEventsModule) then
	warn("[BlackMarket] UI or remote modules not found; Black Market screen disabled")
	return
end
-- Found at runtime via WaitForChild; the editor cannot follow that path (editor-only cast).
local Theme: any = (require :: any)(themeModule)
local GuildScreen: any = (require :: any)(guildScreenModule)
local MerchantInspector: any = (require :: any)(inspectorModule)
local BattleEvents: any = (require :: any)(battleEventsModule)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--------------------------------------------------
-- STATE
--------------------------------------------------

local screen: any = nil
local isOpen = false
local shop: any = nil              -- last payload: { objectId, items = {...}, gold }
local selectedSlot: number? = nil
local busy = false                 -- a buy is waiting for the server

--------------------------------------------------
-- HELPERS (properties before Parent, NET-004)
--------------------------------------------------

local function makeNote(parent: Instance, text: string, order: number, color: Color3?)
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.BorderSizePixel = 0
	lbl.Font = Theme.Font.Primary
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

local function findItem(slot: number?): any?
	if not shop or not slot then return nil end
	for _, it in shop.items or {} do
		if it.slot == slot then return it end
	end
	return nil
end

local function setGold(gold: number)
	if shop then shop.gold = gold end
	if screen then screen.SetGold(`Gold {gold}`) end
end

--------------------------------------------------
-- RENDER
--------------------------------------------------

local render: () -> () -- forward declaration

local function buildEntries(): { any }
	local entries = {}
	for _, it in (shop and shop.items) or {} do
		table.insert(entries, {
			key = it.slot, detail = it.detail, name = it.name, level = it.level, rarity = it.rarity,
			price = if it.bought then nil else it.price,
			queued = it.bought == true, -- bought items stay on the shelf, dimmed
		})
	end
	return entries
end

local function closeScreen()
	if not isOpen then return end
	isOpen = false
	busy = false
	if screen then
		screen.ClosePrompt()
		screen.Hide()
	end
	print("[BlackMarket] Closed")
end

local function promptBuy(it: any)
	if not screen or not shop or busy then return end
	local objectId: string = shop.objectId
	local slot: number = it.slot
	screen.Prompt(`Buy {it.name} (Lv{it.level} {it.rarity}) for {it.price} gold?\nItems can't be returned.`, "Confirm", "Primary", function()
		busy = true
		local ok, res = pcall(function()
			return BattleEvents.BlackMarketBuy:InvokeServer(objectId, slot)
		end)
		busy = false
		if not isOpen then return end
		if ok and type(res) == "table" and res.ok then
			it.bought = true
			setGold(res.gold or 0)
			screen.SetStatus(`Bought {res.name or it.name}. It is in your inventory.`)
		else
			local msg = if ok and type(res) == "table" and res.error then tostring(res.error) else "Could not buy it"
			screen.SetStatus(msg, true)
		end
		render()
	end)
end

render = function()
	if not screen or not isOpen then return end
	screen.Clear()
	local entries = buildEntries()
	local selected = MerchantInspector.ResolveSelected(entries, selectedSlot)
	selectedSlot = if selected then selected.key else nil

	-- LEFT: note + tile grid
	local main = screen.Main
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 4)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = main
	makeNote(main, "25% off Merchant prices. Each item can be bought once.", 1)
	if #entries == 0 then
		makeNote(main, "Nothing for sale.", 2)
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
			selectedKey = selectedSlot,
			width = math.max(240, main.AbsoluteSize.X - 6),
			onSelect = function(key: any)
				selectedSlot = key
				-- A-1 (2026-11-01): a new selection clears the old message ("Not enough gold",
				-- "Bought ..."); render sets "Not enough gold" again if this item is too dear.
				if screen then screen.SetStatus("") end
				render()
			end,
		})
		grid.Parent = main
	end

	-- RIGHT: inspector (shows the price for an item still for sale)
	local holder = Instance.new("Frame")
	holder.Name = "DetailHolder"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Parent = screen.Side
	MerchantInspector.BuildDetail(holder, selected)

	-- BOTTOM RIGHT: [Confirm] [Back]
	local row = Instance.new("Frame")
	row.Name = "Row1"
	row.Size = UDim2.new(1, 0, 0, GuildScreen.ROW_H)
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.LayoutOrder = 1
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, GuildScreen.ROW_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	row.Parent = screen.Buttons

	local it = findItem(selectedSlot)
	local canBuy = it ~= nil and not it.bought and not busy and (shop.gold or 0) >= (it.price or math.huge)
	iconButton(row, "Confirm", "Btn_Buy", 1, canBuy, function()
		if it then promptBuy(it) end
	end)
	iconButton(row, "Back", "Btn_BACK", 2, true, closeScreen)

	if it and not it.bought and (shop.gold or 0) < (it.price or 0) then
		screen.SetStatus("Not enough gold", true)
	end
end

--------------------------------------------------
-- OPEN / CLOSE
--------------------------------------------------

local function openScreen(payload: any)
	if type(payload) ~= "table" or type(payload.items) ~= "table" or type(payload.objectId) ~= "string" then
		warn("[BlackMarket] Bad shop payload")
		return
	end
	if not screen then
		screen = GuildScreen.Create({ name = "BlackMarketScreen", title = "BLACK MARKET", parent = playerGui })
		screen.SetButtonRows(1)
	end
	if not (shop and shop.objectId == payload.objectId) then
		selectedSlot = nil
	end
	shop = payload
	busy = false
	isOpen = true
	screen.SetStatus("")
	setGold(tonumber(payload.gold) or 0)
	screen.Show()
	render()
	print(`[BlackMarket] Opened {payload.objectId} ({#payload.items} items)`)
end

BattleEvents.BlackMarketOpened.OnClientEvent:Connect(openScreen)
BattleEvents.BattleEnded.OnClientEvent:Connect(function()
	closeScreen()
	shop = nil
	selectedSlot = nil
end)
