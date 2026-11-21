--!strict
-- BlacksmithScreen.lua
-- CTRBLXAI | Blacksmith full screen (v2 build step 3, 2026-11-01). Same model as the Merchant
-- screen (user decision: Merchant layout, +/- sets the target level, plus a Max button).
--
-- Layout (GuildScreen):
--   LEFT   item tile grid
--   RIGHT  [Upgrade][Dismantle] sub-tabs, one info line (cost or yield), the item inspector
--   BOTTOM ONE row, lower right:
--          Upgrade tab:   [-] [+] [Max] [check] [X] [Back]   (- below the current level = downgrade)
--          Dismantle tab: [+/-] [check] [X] [Back]
--          check and X open a prompt that needs a second confirmation.
-- Rules shown here come from the server (guild_facilities 47, 51-52); the client never sends a
-- price or a yield (SEC-002). Pending changes live in the guild menu basket (context).
-- Display + input only (ARC-001). Context is nil-safe (ARC-006).

local WAIT = 10

local uiFolder = script.Parent
local themeModule = uiFolder:WaitForChild("Theme", WAIT)
local guildScreenModule = uiFolder:WaitForChild("GuildScreen", WAIT)
local inspectorModule = uiFolder:WaitForChild("MerchantInspector", WAIT)
if not themeModule or not guildScreenModule or not inspectorModule then
	error("[BlacksmithScreen] Theme / GuildScreen / MerchantInspector module not found")
end
-- Found at runtime via WaitForChild; the editor cannot follow that path (editor-only cast).
local Theme: any = (require :: any)(themeModule)
local GuildScreen: any = (require :: any)(guildScreenModule)
local MerchantInspector: any = (require :: any)(inspectorModule)
-- Search / Type / Rarity / Sort bar, same as the Loadout inventory (user request 2026-11-02).
local toolbarModule = uiFolder:WaitForChild("ItemListToolbar", WAIT)
local ItemListToolbar: any = if toolbarModule then (require :: any)(toolbarModule) else nil
if not toolbarModule then warn("[BlacksmithScreen] ItemListToolbar module missing; no filter bar") end
-- The Loadout's own bar and menus (user ruling 2026-11-08: Blacksmith matches the Loadout; the
-- 27 px phone bar from 2026-11-07 no longer applies): 24 px bar, compact icon menus, white text.
local toolbar: any = if ItemListToolbar then ItemListToolbar.new() else nil

local BlacksmithScreen = {}

--------------------------------------------------
-- TYPES / STATE
--------------------------------------------------

-- `it` is one row of the server's GetBlacksmithItems answer.
export type Context = {
	parent: Instance,                                   -- PlayerGui
	getItems: () -> any?,                               -- GetBlacksmithItems answer (cached)
	stagedLevel: (it: any) -> number,                   -- staged target level (= it.level when none)
	setTarget: (it: any, target: number) -> (),         -- stage a level change (target = it.level clears)
	maxAffordable: (it: any) -> number,                 -- highest level the mercury in hand allows
	isDismantleQueued: (instanceId: string) -> boolean,
	toggleDismantle: (it: any) -> (),
	pendingCount: () -> number,
	summary: () -> any,                                 -- { nUp, upGold, upMercury, nDown, nDis, gain }
	confirm: () -> (),
	discard: () -> (),
	requestBack: (close: () -> ()) -> (),
	onClosed: () -> (),
}

local BUTTON_ROWS = 1
local SUBTAB_H = 24
local SUBTAB_GAP = 6
local INFO_H = 58             -- info lines under the sub-tabs (cost / yield)

local ctx: Context? = nil
local screen: any = nil
local isOpen = false
local currentTab = "Upgrade"
local selectedKey: { [string]: any } = {}

--------------------------------------------------
-- SMALL HELPERS (properties before Parent, NET-004)
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
	local b = Theme.MakeIconButton(nil, kind, if enabled then onTap else nil, {
		name = name,
		size = UDim2.fromOffset(GuildScreen.ROW_H, GuildScreen.ROW_H),
		disabled = not enabled,
	})
	b.LayoutOrder = order
	b.Parent = row
end

-- "Max" has no icon art yet, so it uses the bar button style (same as the sub-tabs).
local function maxButton(row: Instance, order: number, enabled: boolean, onTap: () -> ())
	Theme.MakeTabButton(row, "Max", if enabled then "Inactive" else "Disabled", if enabled then onTap else function() end, {
		name = "Btn_Max",
		size = UDim2.fromOffset(GuildScreen.ROW_H + 20, GuildScreen.ROW_H),
		layoutOrder = order,
	})
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

local function plural(n: number, one: string, many: string): string
	return if n == 1 then one else many
end

-- Gold + mercury for raising `it` from its level to `target` (sum of the server's curve).
local function costTo(it: any, target: number): (number, number)
	local gold, mercury = 0, 0
	for _, step in it.upgradeCurve or {} do
		if step.toLevel <= target then
			gold += step.gold or 0
			mercury += step.mercury or 1
		end
	end
	return gold, mercury
end

local function maxLevelOf(it: any): number
	return (it.level or 1) + #(it.upgradeCurve or {})
end

-- "2 mercury, 2 crystals, 1 sulfur, 3 rune gems" (zero parts left out).
local function yieldText(y: any): string
	local parts = { `{y.mercury or 0} mercury` }
	if (y.crystals or 0) > 0 then table.insert(parts, `{y.crystals} {plural(y.crystals, "crystal", "crystals")}`) end
	if (y.sulfur or 0) > 0 then table.insert(parts, `{y.sulfur} sulfur`) end
	local g = y.gemCount or y.gems or 0
	if type(g) == "number" and g > 0 then table.insert(parts, `{g} rune {plural(g, "gem", "gems")}`) end
	return table.concat(parts, ", ")
end

--------------------------------------------------
-- RENDER
--------------------------------------------------

local render: () -> () -- forward declaration (button callbacks re-render)

local function buildEntries(res: any, isUpgrade: boolean): { any }
	local c = ctx
	local entries = {}
	if not c or not res then return entries end
	for _, it in res.items or {} do
		if isUpgrade or it.canDismantle then
			local queued = if isUpgrade then c.stagedLevel(it) ~= it.level else c.isDismantleQueued(it.instanceId)
			table.insert(entries, {
				key = it.instanceId, detail = it.detail, name = it.name, level = it.level,
				rarity = it.rarity, price = nil, queued = queued, row = it,
			})
		end
	end
	return entries
end

local function buildMain(res: any, isUpgrade: boolean, entries: { any }, selected: any?)
	local main = screen.Main
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 4)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = main

	if res then
		local bl = res.blacksmithLevel or 1
		if isUpgrade then
			makeNote(main, `Blacksmith L{bl}: levels items up to L{if bl >= 10 then 99 else bl * 10}. Each level costs 1 mercury plus gold. Lowering a level is free but refunds nothing.`, 1)
		else
			makeNote(main, "Dismantling destroys an item for mercury, crystals and rune gems (sulfur from Exalted and above). It gives no gold. Equipped items are not listed.", 1)
		end
		if toolbar then toolbar.Build(main, 2, function() screen.ResetScroll(); render() end) end
		if #entries == 0 then
			makeNote(main, if toolbar and toolbar.IsFiltering() then "No items match the search or filters."
				elseif isUpgrade then "No items." else "Nothing to dismantle. Unequip an item first.", 3)
		end
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
	local flex = Instance.new("UIFlexItem")
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

-- One or more short lines about the selected item: cost / free downgrade / yield / blocked.
local function infoText(selected: any?, isUpgrade: boolean): string
	local c = ctx
	if not selected or not c then return "" end
	local it = selected.row
	if isUpgrade then
		local staged = c.stagedLevel(it)
		if staged > it.level then
			local g, m = costTo(it, staged)
			return `Level {it.level} -> {staged}: {g}g + {m} mercury`
		elseif staged < it.level then
			return `Level {it.level} -> {staged}: free. Gold and mercury spent on those levels are not refunded.`
		elseif #(it.upgradeCurve or {}) > 0 then
			local s = it.upgradeCurve[1]
			local capNote = if c.maxAffordable(it) <= it.level then "\nNeed more mercury to level up." else ""
			return `Next level (Lv{s.toLevel}): {s.gold}g + {s.mercury or 1} mercury{capNote}`
		end
		return if it.upgradeBlockedReason then tostring(it.upgradeBlockedReason) else "At max level"
	end
	local y = it.dismantle
	if not y then return tostring(it.dismantleBlockedReason or "Cannot be dismantled") end
	local lines = { `Dismantle gives: {yieldText(y)}` }
	if (y.cappedLines or 0) > 0 then
		table.insert(lines, `{y.cappedLines} {plural(y.cappedLines, "stat becomes an Epic-tier gem", "stats become Epic-tier gems")}`)
	end
	if #(y.lostPassives or {}) > 0 then
		table.insert(lines, `No rune gem: {table.concat(y.lostPassives, ", ")}`)
	end
	if y.unique then table.insert(lines, "Unique items give no rune gems.") end
	return table.concat(lines, "\n")
end

-- RIGHT column: sub-tabs, info lines, inspector.
local function buildSide(selected: any?, isUpgrade: boolean)
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
	for i, tab in { "Upgrade", "Dismantle" } do
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

	local info = Instance.new("TextLabel")
	info.Name = "Info"
	info.Size = UDim2.new(1, 0, 0, INFO_H)
	info.Position = UDim2.fromOffset(0, SUBTAB_H + SUBTAB_GAP)
	info.BackgroundTransparency = 1
	info.BorderSizePixel = 0
	info.Font = Theme.Font.PrimaryBold
	info.TextSize = Theme.Text.Small()
	info.TextColor3 = Theme.Colors.TextGold
	info.TextWrapped = true
	info.TextXAlignment = Enum.TextXAlignment.Left
	info.TextYAlignment = Enum.TextYAlignment.Top
	info.Text = infoText(selected, isUpgrade)
	info.Parent = side

	local top = SUBTAB_H + SUBTAB_GAP + INFO_H + 4
	local holder = Instance.new("Frame")
	holder.Name = "DetailHolder"
	holder.Size = UDim2.new(1, 0, 1, -top)
	holder.Position = UDim2.fromOffset(0, top)
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Parent = side
	MerchantInspector.BuildDetail(holder, selected)
end

-- Check button: totals, then a second confirmation.
local function promptConfirm()
	local c = ctx
	if not c or not screen then return end
	local s = c.summary()
	local lines = {}
	if s.nUp > 0 then
		table.insert(lines, `Level up {s.nUp} {plural(s.nUp, "item", "items")}: -{s.upGold} gold, -{s.upMercury} mercury`)
	end
	if s.nDown > 0 then
		table.insert(lines, `Lower {s.nDown} {plural(s.nDown, "item", "items")}: free, nothing refunded`)
	end
	if s.nDis > 0 then
		table.insert(lines, `Dismantle {s.nDis} {plural(s.nDis, "item", "items")}: +{yieldText(s.gain)}`)
		table.insert(lines, "Dismantling can't be undone.")
	end
	if #lines == 0 then table.insert(lines, "Confirm all pending changes?") end
	screen.Prompt(table.concat(lines, "\n"), "Confirm", "Primary", function()
		c.confirm()
		render()
	end)
end

local function promptDiscard()
	local c = ctx
	if not c or not screen then return end
	screen.Prompt("Discard all pending changes?", "Discard", "Tertiary", function()
		c.discard()
		render()
	end)
end

-- Stage a level for the selected item. Going below the current level shows the
-- "not refunded" prompt once (guild_facilities 47).
local function stageLevel(it: any, target: number)
	local c = ctx
	if not c then return end
	local current = c.stagedLevel(it)
	if target < it.level and current >= it.level then
		screen.Prompt(`Lower {it.name} to Lv{target}? It is free, but the gold and mercury spent on those levels are not refunded. Raising it again costs full price.`,
			"Confirm", "Primary", function()
				c.setTarget(it, target)
				render()
			end)
		return
	end
	c.setTarget(it, target)
	render()
end

-- Queue / unqueue the selected item for dismantling. Above-Epic and Unique items show a
-- prompt before they are queued (guild_facilities 52).
local function toggleDismantle(it: any)
	local c = ctx
	if not c then return end
	local y = it.dismantle
	if c.isDismantleQueued(it.instanceId) or not y or not (y.aboveEpic or y.unique) then
		c.toggleDismantle(it)
		render()
		return
	end
	local msg
	if y.unique then
		msg = `{it.name} is Unique. Dismantling gives {yieldText(y)} and no rune gems. This can't be undone. Add it to the dismantle list?`
	else
		local lost = if #(y.lostPassives or {}) > 0 then ` Its {it.rarity} passives ({table.concat(y.lostPassives, ", ")}) can't be transferred and give no rune gem.` else ""
		local capped = y.cappedLines or 0
		local stats = if capped > 0 then ` {capped} {plural(capped, "bonus stat is", "bonus stats are")} stronger than Epic and will become Epic-tier rune gems.` else ""
		msg = `Dismantle this {it.rarity} item? Gives {yieldText(y)}.{stats}{lost} This can't be undone.`
	end
	screen.Prompt(msg, "Confirm", "Primary", function()
		c.toggleDismantle(it)
		render()
	end)
end

local function buildButtons(selected: any?, isUpgrade: boolean)
	local c = ctx
	if not c then return end
	local row = makeRow(screen.Buttons, 1)
	local hasPending = c.pendingCount() > 0
	local it = selected and selected.row or nil

	if isUpgrade then
		local staged = if it then c.stagedLevel(it) else 0
		local maxA = if it then math.min(c.maxAffordable(it), maxLevelOf(it)) else 0
		iconButton(row, "Minus", "Btn_LevelDown", 1, it ~= nil and staged > 1, function()
			if it then stageLevel(it, staged - 1) end
		end)
		iconButton(row, "Plus", "Btn_LevelUp", 2, it ~= nil and staged < maxA, function()
			if it then stageLevel(it, staged + 1) end
		end)
		maxButton(row, 3, it ~= nil and staged < maxA, function()
			if it then stageLevel(it, maxA) end
		end)
	else
		local queued = it ~= nil and c.isDismantleQueued(it.instanceId)
		iconButton(row, if queued then "Minus" else "Plus", "Btn_Toggle", 1, it ~= nil and (queued or it.canDismantle == true), function()
			if it then toggleDismantle(it) end
		end)
	end
	iconButton(row, "Confirm", "Btn_ConfirmAll", 10, hasPending, promptConfirm)
	iconButton(row, "X", "Btn_DiscardAll", 11, hasPending, promptDiscard)
	iconButton(row, "Back", "Btn_BACK", 12, true, function()
		c.requestBack(BlacksmithScreen.Close)
	end)
end

render = function()
	local c = ctx
	if not c or not screen or not isOpen then return end
	screen.Clear(currentTab) -- same tab keeps the grid's scroll position
	local isUpgrade = currentTab == "Upgrade"
	local res = c.getItems()
	local entries = buildEntries(res, isUpgrade)
	if toolbar then entries = toolbar.Apply(entries) end
	local selected = MerchantInspector.ResolveSelected(entries, selectedKey[currentTab])
	buildMain(res, isUpgrade, entries, selected)
	buildSide(selected, isUpgrade)
	buildButtons(selected, isUpgrade)
end

--------------------------------------------------
-- PUBLIC
--------------------------------------------------

function BlacksmithScreen.Init(c: Context)
	ctx = c
end

function BlacksmithScreen.IsOpen(): boolean
	return isOpen
end

function BlacksmithScreen.GetGui(): ScreenGui?
	return if isOpen and screen then screen.Gui else nil
end

function BlacksmithScreen.Open()
	local c = ctx
	if not c then
		warn("[BlacksmithScreen] Open called before Init")
		return
	end
	if not screen then
		screen = GuildScreen.Create({ name = "BlacksmithScreen", title = "BLACKSMITH", parent = c.parent , crest = Theme.GuildIcons.Blacksmith, autoCurrencies = true }) -- 2026-11-20 user: nav button icon + currency icons
		screen.SetButtonRows(BUTTON_ROWS)
	end
	currentTab = "Upgrade"
	if toolbar then toolbar.Reset() end -- each visit starts unfiltered
	isOpen = true
	screen.SetStatus("")
	screen.Show()
	render()
	print("[BlacksmithScreen] Opened")
end

function BlacksmithScreen.Close()
	if not isOpen then return end
	isOpen = false
	if toolbar then toolbar.Close() end
	if screen then screen.Hide() end
	local c = ctx
	if c then c.onClosed() end
	print("[BlacksmithScreen] Closed")
end

function BlacksmithScreen.Hide()
	if not isOpen then return end
	isOpen = false
	if toolbar then toolbar.Close() end
	if screen then screen.Hide() end
end

function BlacksmithScreen.Render()
	render()
end

function BlacksmithScreen.SetGold(text: string)
	if screen then screen.SetGold(text) end
end

function BlacksmithScreen.SetStatus(text: string, isError: boolean?)
	if screen then screen.SetStatus(text, isError) end
end

return table.freeze(BlacksmithScreen)
