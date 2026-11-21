--!strict
-- CrucibleScreen.lua
-- CTRBLXAI | Crucible full screen: merge identical gear into the next rarity (2026-11-02).
-- Same frame as the Merchant / Blacksmith / Runeforge screens (GuildScreen + item tile grid).
--
-- Layout:
--   LEFT   item tile grid. Before anything is picked: every item that can be merged. Once one is
--          picked: only items of the SAME base item and rarity (the only ones that can join it).
--          Picked items show dimmed.
--   RIGHT  the tapped item's inspector, then the merge panel: picked N / needed, and (when enough
--          are picked) the server's preview: result rarity, level and cost. The new bonus lines
--          are never shown before confirming (USER DECISION 2026-11-02).
--   BOTTOM ONE row, lower right: [Plus/Minus = pick / unpick the tapped item] [Confirm] [X = clear] [Back]
--   Confirm always opens a prompt that needs a second confirmation. Merges commit straight away
--   (no basket). The client sends instance IDs only; the server prices everything (SEC-002).
-- Display + input only (ARC-001). Context is nil-safe (ARC-006). Tap-only input.

local WAIT = 10

local uiFolder = script.Parent
local themeModule = uiFolder:WaitForChild("Theme", WAIT)
local guildScreenModule = uiFolder:WaitForChild("GuildScreen", WAIT)
local inspectorModule = uiFolder:WaitForChild("MerchantInspector", WAIT)
if not themeModule or not guildScreenModule or not inspectorModule then
	error("[CrucibleScreen] Theme / GuildScreen / MerchantInspector module not found")
end
-- Found at runtime via WaitForChild; the editor cannot follow that path (editor-only cast).
local Theme: any = (require :: any)(themeModule)
local GuildScreen: any = (require :: any)(guildScreenModule)
local MerchantInspector: any = (require :: any)(inspectorModule)

local CrucibleScreen = {}

--------------------------------------------------
-- TYPES / STATE
--------------------------------------------------

export type Context = {
	parent: Instance,                          -- PlayerGui
	getState: () -> any?,                      -- GetCrucible answer (cached)
	preview: (ids: { string }) -> any?,        -- PreviewMerge answer, nil on error
	commit: (ids: { string }) -> any?,         -- CommitMerge answer, nil on error
	onChanged: () -> (),                       -- server state changed: refresh caches
	onClosed: () -> (),
}

local PREVIEW_DELAY = 0.35   -- s; coalesces fast taps (server rate limit is 0.2 s)
local STATE_RETRY_DELAY = 0.3
local STATE_RETRY_MAX = 3

local ctx: Context? = nil
local screen: any = nil
local isOpen = false
local tappedKey: string? = nil
local picks: { string } = {}          -- picked instance IDs, in pick order
local previewRes: any = nil
local previewToken = 0
local previewBusy = false
local commitBusy = false
local renderSeq = 0
local stateRetries = 0

--------------------------------------------------
-- HELPERS (properties before Parent, NET-004)
--------------------------------------------------

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

local function isPicked(id: string): boolean
	for _, p in picks do
		if p == id then return true end
	end
	return false
end

local function findItem(state: any, id: string?): any?
	if not state or not id then return nil end
	for _, it in state.items or {} do
		if it.instanceId == id then return it end
	end
	return nil
end

local function resetPicks()
	table.clear(picks)
	previewRes = nil
	previewToken += 1
	previewBusy = false
end

local render: () -> () -- forward declaration

-- Ask the server for the result + cost once enough items are picked (coalesced).
local function schedulePreview(state: any)
	local c = ctx
	previewToken += 1
	local token = previewToken
	previewRes = nil
	local needed = state and state.needed
	if not c or not needed or #picks ~= needed then
		previewBusy = false
		return
	end
	previewBusy = true
	local ids = table.clone(picks)
	task.delay(PREVIEW_DELAY, function()
		if token ~= previewToken or not isOpen then return end
		local res = c.preview(ids)
		if token ~= previewToken then return end
		previewRes = res
		previewBusy = false
		if isOpen then render() end
	end)
end

--------------------------------------------------
-- RENDER
--------------------------------------------------

local function buildEntries(state: any): { any }
	local entries = {}
	if not state then return entries end
	-- USER REQUEST 2026-11-02: list only items that can actually be merged now, i.e. the player
	-- has at least the needed number of mergeable copies of the same base item AND rarity.
	local needed = tonumber(state.needed) or 0
	local copies: { [string]: number } = {}
	for _, it in state.items or {} do
		if it.blockedReason == nil then
			local k = `{tostring(it.archetypeId)}|{tostring(it.rarity)}`
			copies[k] = (copies[k] or 0) + 1
		end
	end
	local first = findItem(state, picks[1])
	for _, it in state.items or {} do
		local show = it.blockedReason == nil and needed > 0
			and (copies[`{tostring(it.archetypeId)}|{tostring(it.rarity)}`] or 0) >= needed
		if show and first then
			show = it.archetypeId == first.archetypeId and it.rarity == first.rarity
		end
		if show then
			table.insert(entries, {
				key = it.instanceId, detail = it.detail, name = it.name, level = it.level,
				rarity = it.rarity, price = nil, queued = isPicked(it.instanceId), row = it,
			})
		end
	end
	return entries
end

local function promptMerge(state: any)
	local c = ctx
	local p = previewRes
	if not c or not screen or not p or commitBusy then return end
	local ids = table.clone(picks)
	local lines = {
		`Merge {#ids} x {p.name} ({p.fromRarity}) into one {p.toRarity} {p.name}, level {p.toLevel}?`,
		`Costs {p.gold} gold + {p.crystals} crystals{if (p.sulfur or 0) > 0 then ` + {p.sulfur} sulfur` else ""}.`,
		"The merged items are destroyed. Its bonus lines are rolled when it is made. This can't be undone.",
	}
	screen.Prompt(table.concat(lines, "\n"), "Confirm", "Primary", function()
		commitBusy = true
		local res = c.commit(ids)
		commitBusy = false
		if res then
			resetPicks()
			tappedKey = res.instanceId
			c.onChanged()
		end
		render()
	end)
end

render = function()
	local c = ctx
	if not c or not screen or not isOpen then return end
	renderSeq += 1
	local mySeq = renderSeq
	-- getState may wait on the server (empty cache): fetch BEFORE clearing, and stop if a newer
	-- render started meanwhile, so two renders never both build the screen.
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
	screen.Clear("Main") -- keeps the grid's scroll position across rebuilds

	-- Drop picks that no longer exist (merged / sold elsewhere).
	if state then
		for i = #picks, 1, -1 do
			if not findItem(state, picks[i]) then table.remove(picks, i) end
		end
	end

	local entries = buildEntries(state)
	-- Drop picks that are no longer listed (e.g. their group fell below the needed count).
	if #picks > 0 then
		local listed: { [string]: boolean } = {}
		for _, e in entries do listed[e.key] = true end
		local before = #picks
		for i = #picks, 1, -1 do
			if not listed[picks[i]] then table.remove(picks, i) end
		end
		if #picks ~= before then
			previewRes = nil
			previewToken += 1
			previewBusy = false
			entries = buildEntries(state) -- the same-item filter may widen again
		end
	end
	local selected = MerchantInspector.ResolveSelected(entries, tappedKey)
	tappedKey = if selected then selected.key else nil

	-- LEFT: note + grid
	local main = screen.Main
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 4)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = main
	if state then
		if state.lockedReason then
			makeNote(main, tostring(state.lockedReason), 1, Theme.Colors.Warning, true)
		else
			makeNote(main, `Crucible L{state.level}: merge {state.needed} of the same item and rarity into the next rarity, up to {state.capacity or "Uncommon"}. Level bonus +{state.boost or 0}.`, 1)
		end
		if #entries == 0 then
			makeNote(main, `No items to merge. You need {state.needed or "?"} unequipped copies of the same item at the same rarity.`, 2)
		end
	end
	if #entries > 0 then
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

	-- RIGHT: inspector + merge panel
	local side = screen.Side
	local detailHolder = Instance.new("Frame")
	detailHolder.Name = "DetailHolder"
	detailHolder.Size = UDim2.new(1, 0, 0.55, 0)
	detailHolder.BackgroundTransparency = 1
	detailHolder.BorderSizePixel = 0
	detailHolder.Parent = side
	MerchantInspector.BuildDetail(detailHolder, selected)

	local panel = Instance.new("ScrollingFrame")
	panel.Name = "MergePanel"
	panel.Size = UDim2.new(1, 0, 0.45, -4)
	panel.Position = UDim2.new(0, 0, 0.55, 4)
	panel.BackgroundTransparency = 1
	panel.BorderSizePixel = 0
	panel.ScrollBarThickness = 4
	panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
	panel.CanvasSize = UDim2.new()
	local plist = Instance.new("UIListLayout")
	plist.Padding = UDim.new(0, 4)
	plist.SortOrder = Enum.SortOrder.LayoutOrder
	plist.Parent = panel
	local needed = (state and state.needed) or 0
	if state and not state.lockedReason then
		makeNote(panel, `PICKED {#picks} / {needed}`, 1, Theme.Colors.TextGold, true)
		if #picks == 0 then
			makeNote(panel, "Tap an item, then + to pick it. Only items of the same base item and rarity can be merged together.", 2)
		elseif #picks < needed then
			makeNote(panel, `Pick {needed - #picks} more of the same item and rarity.`, 2)
		elseif previewBusy then
			makeNote(panel, "Working out the result...", 2)
		elseif previewRes then
			local p = previewRes
			local parts = {
				`Result: {p.name}, {p.toRarity}, level {p.toLevel} (average {p.averageLevel})`,
				`Cost: {p.gold} gold + {p.crystals} crystals{if (p.sulfur or 0) > 0 then ` + {p.sulfur} sulfur` else ""}`,
				"Its bonus lines are rolled when it is made.",
			}
			if p.canAfford == false then table.insert(parts, "Not enough gold, crystals or sulfur.") end
			makeNote(panel, table.concat(parts, "\n"), 2, Theme.Colors.TextPrimary, true)
		else
			makeNote(panel, "These items can't be merged. See the message at the top.", 2, Theme.Colors.Warning)
		end
	end
	panel.Parent = side

	-- BOTTOM RIGHT: one row of icons
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

	local locked = state == nil or state.lockedReason ~= nil
	local tapped = tappedKey
	local tappedPicked = tapped ~= nil and isPicked(tapped)
	local canToggle = not locked and tapped ~= nil and (tappedPicked or #picks < needed)
	iconButton(row, if tappedPicked then "Minus" else "Plus", "Btn_Pick", 1, canToggle, function()
		if not tapped then return end
		if isPicked(tapped) then
			for i, p in picks do
				if p == tapped then table.remove(picks, i) break end
			end
		elseif #picks < needed then
			table.insert(picks, tapped)
		end
		schedulePreview(state)
		render()
	end)
	local canMerge = not locked and #picks == needed and needed > 0 and not previewBusy and previewRes ~= nil
		and previewRes.canAfford ~= false and not commitBusy
	iconButton(row, "Confirm", "Btn_Merge", 2, canMerge, function()
		promptMerge(state)
	end)
	iconButton(row, "X", "Btn_ClearPicks", 3, #picks > 0, function()
		resetPicks()
		render()
	end)
	iconButton(row, "Back", "Btn_BACK", 10, true, function()
		CrucibleScreen.Close()
	end)
end

--------------------------------------------------
-- PUBLIC
--------------------------------------------------

function CrucibleScreen.Init(c: Context)
	ctx = c
end

function CrucibleScreen.IsOpen(): boolean
	return isOpen
end

function CrucibleScreen.GetGui(): ScreenGui?
	return if isOpen and screen then screen.Gui else nil
end

function CrucibleScreen.Open()
	local c = ctx
	if not c then
		warn("[CrucibleScreen] Open called before Init")
		return
	end
	if not screen then
		screen = GuildScreen.Create({ name = "CrucibleScreen", title = "CRUCIBLE", parent = c.parent , crest = Theme.GuildIcons.Crucible, autoCurrencies = true }) -- 2026-11-20 user: nav button icon + currency icons
		screen.SetButtonRows(1)
	end
	resetPicks()
	tappedKey = nil
	stateRetries = STATE_RETRY_MAX
	isOpen = true
	screen.SetStatus("")
	screen.Show()
	render()
	print("[CrucibleScreen] Opened")
end

-- Picks are only a selection (nothing is charged until Confirm), so Back just closes.
function CrucibleScreen.Close()
	if not isOpen then return end
	isOpen = false
	resetPicks()
	if screen then screen.Hide() end
	local c = ctx
	if c then c.onClosed() end
	print("[CrucibleScreen] Closed")
end

function CrucibleScreen.Hide()
	if not isOpen then return end
	isOpen = false
	resetPicks()
	if screen then screen.Hide() end
end

function CrucibleScreen.Render()
	render()
end

function CrucibleScreen.SetGold(text: string)
	if screen then screen.SetGold(text) end
end

function CrucibleScreen.SetStatus(text: string, isError: boolean?)
	if screen then screen.SetStatus(text, isError) end
end

return table.freeze(CrucibleScreen)
