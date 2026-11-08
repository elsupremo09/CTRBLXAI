--!strict
-- ItemListToolbar.lua
-- CTRBLXAI | Search + Type + Rarity + Sort bar for guild building item grids (2026-11-02, user
-- request: "a filter, sort and search option like in the Loadout screen" for the Blacksmith and
-- Runeforge). Same controls, order, labels and dropdown style as the Loadout inventory bar
-- (LoadoutScreen buildInventory), shared here so both screens behave the same.
--
-- Use:
--   local tb = ItemListToolbar.new()                 -- one state per screen (kept while open)
--   tb.Build(parentFrame, layoutOrder, onChanged)    -- draws the bar (24 px, the Loadout bar); onChanged re-renders
--   entries = tb.Apply(entries)                      -- filter + search + sort a grid entry list
--   tb.Reset()                                       -- back to All / All / Lv down / ""
-- Optional config (opt-in, 2026-11-07, Runeforge Gems tab; other screens pass nothing and get
-- the gear bar unchanged): ItemListToolbar.new({ typeFilters = {{id,label,icon}}, typeOf =
-- fn(entry) -> id, rarityOptions = {...}, sortOptions = {{label, compare = fn(a,b) -> bool?}},
-- searchPlaceholder = "...", toggle = { label = "Fits only", default = true } }).
-- tb.ToggleOn() reads the toggle (the screen applies it; Apply doesn't know what "fits").
-- 2026-11-08 (user: "Loadout screen is our model"; Blacksmith too): every bar is drawn with the
-- Loadout's OWN controls (InventoryControls: 24 px bar, the Loadout Type / Rarity / sort buttons,
-- its compact 22 px menu with icon rows), on every device. Button and menu text is white with a
-- black outline; the active state is the gold-tint background. The toggle is a Loadout-style
-- button with its full label. The old separate phone bar (44 px / Blacksmith 27 px) is gone.
-- (The loadoutStyle config key from 2026-11-08 is still accepted and has no effect.)
-- Entries are MerchantInspector grid entries: { key, name, level, rarity, detail = buildItemEntry }.
-- Display only (ARC-001). Tap-only (.Activated: touch, mouse and gamepad). Instances are children of
-- the parent, so screen.Clear() cleans them; the dropdown overlay is destroyed on every close.

local Players = game:GetService("Players")

local WAIT = 10
local themeModule = script.Parent:WaitForChild("Theme", WAIT)
if not themeModule then
	error("[ItemListToolbar] Theme module not found")
end
local Theme: any = (require :: any)(themeModule)
local controlsModule = script.Parent:WaitForChild("InventoryControls", WAIT)
if not controlsModule then
	error("[ItemListToolbar] InventoryControls module not found")
end
local InventoryControls: any = (require :: any)(controlsModule)

local ItemListToolbar = {}

-- Same types as the Loadout filter (gear only; consumables / doctrines are not items here).
-- Loadout names the armour slots Torso / Arms / Legs; items carry Body / Gloves / Feet.
local TYPE_FILTERS = {
	{ id = "All",       label = "All",   icon = Theme.Icons.AllTypes },
	{ id = "MainHand",  label = "Main",  icon = Theme.Icons.MainHand },
	{ id = "OffHand",   label = "Off",   icon = Theme.Icons.OffHand },
	{ id = "Head",      label = "Head",  icon = Theme.Icons.Head },
	{ id = "Body",      label = "Torso", icon = Theme.Icons.Torso },
	{ id = "Gloves",    label = "Arms",  icon = Theme.Icons.Arms },
	{ id = "Feet",      label = "Legs",  icon = Theme.Icons.Legs },
	{ id = "Accessory", label = "Acc",   icon = Theme.Icons.Accessory },
}
local RARITY_OPTIONS = { "All", "Common", "Uncommon", "Rare", "Epic", "Exalted", "Legendary", "Mythic", "Transcendent", "Unique" }
local RARITY_RANK = {
	Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Exalted = 5, Legendary = 6,
	Mythic = 7, Transcendent = 8, Unique = 9,
}
-- Loadout's sort list minus "New First/Last" (the guild item lists carry no "new" flag).
local SORT_OPTIONS = {
	{ label = "Lv \u{2193}", field = "level", desc = true },
	{ label = "Lv \u{2191}", field = "level", desc = false },
	{ label = "Name", field = "name", desc = false },
	{ label = "Rarity", field = "rarity", desc = true },
}

local GAP = 3
local FIXED_BTNS_W = 195 -- Type + Rarity + sort (62 each) + their three 3 px gaps

local function slotOf(entry: any): string?
	local d = entry.detail
	return d and d.slot or nil
end

function ItemListToolbar.new(config: any?)
	local self: any = {}
	local cfg: any = config or {}
	local typeFilters = cfg.typeFilters or TYPE_FILTERS
	local rarityOptions = cfg.rarityOptions or RARITY_OPTIONS
	local sortOptions = cfg.sortOptions or SORT_OPTIONS
	local typeOf = cfg.typeOf or slotOf
	local toggleCfg = cfg.toggle
	local toggleDefault = if toggleCfg then toggleCfg.default ~= false else false
	local toggleOn = toggleDefault
	local function typeLabelOf(id: string): string
		for _, f in typeFilters do
			if f.id == id then return f.label end
		end
		return id
	end
	local typeFilter = "All"
	local rarityFilter = "All"
	local sortIndex = 1
	local searchText = ""
	local dropdown: ScreenGui? = nil

	local function closeDropdown()
		if dropdown then
			dropdown:Destroy()
			dropdown = nil
		end
	end

	-- Same dropdown as LoadoutScreen.showDropdown: a menu under the button, outside tap closes it.
	local function showDropdown(anchor: GuiObject, options: { any }, onSelect: (any) -> ())
		closeDropdown()
		local player = Players.LocalPlayer
		local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
		if not playerGui then return end
		-- The Loadout's own menu; above the guild screens (100) and their prompts.
		dropdown = InventoryControls.ShowMenu(playerGui, anchor, options, function(v: any)
			onSelect(v)
		end, closeDropdown, 205)
	end

	local function makeButton(row: Instance, text: string, order: number, active: boolean, icon: string?): TextButton
		return InventoryControls.MakeFilterButton(row, text, order, active, icon)
	end

	-- Draws the bar into `parent` (a list layout child at `order`). onChanged re-renders the screen.
	local function toggleLabel(): string
		if not toggleCfg then return "" end
		return toggleCfg.label or "Toggle"
	end
	local function toggleWidth(): number
		if not toggleCfg then return 0 end
		local tw = Theme.MeasureText(toggleLabel(), Theme.Text.Small(), Theme.Font.Primary).X
		return math.max(62, math.ceil(tw) + 25)
	end

	function self.Build(parent: Instance, order: number, onChanged: () -> ())
		closeDropdown()
		local row = Instance.new("Frame")
		row.Name = "Toolbar"
		row.Size = UDim2.new(1, 0, 0, InventoryControls.BarHeight)
		row.BackgroundTransparency = 1
		row.BorderSizePixel = 0
		row.LayoutOrder = order
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.Padding = UDim.new(0, GAP)
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = row

		local search = Instance.new("TextBox")
		-- The optional toggle is sized to its own label (icon 19 px + text + 6 px) so it never
		-- truncates; the search box gives up that width plus one 3 px gap.
		local toggleW = toggleWidth()
		local reserved = FIXED_BTNS_W + (if toggleCfg then GAP + toggleW else 0)
		search.Size = UDim2.new(1, -reserved, 1, 0)
		search.BackgroundColor3 = Theme.Colors.Surface
		search.BackgroundTransparency = 0.2
		search.BorderSizePixel = 0
		search.Font = Theme.Font.Primary
		search.TextSize = Theme.Text.Small()
		search.TextColor3 = Theme.Colors.TextPrimary
		search.PlaceholderText = cfg.searchPlaceholder or "Search items..."
		search.PlaceholderColor3 = Theme.Colors.TextDisabled
		search.Text = searchText
		search.ClearTextOnFocus = false
		search.LayoutOrder = 1
		local sc = Instance.new("UICorner")
		sc.CornerRadius = UDim.new(0, 3)
		sc.Parent = search
		search.FocusLost:Connect(function()
			if search.Text ~= searchText then
				searchText = search.Text
				onChanged()
			end
		end)
		search.Parent = row

		local typeBtn = makeButton(row, if typeFilter == "All" then "Type" else typeLabelOf(typeFilter), 2,
			typeFilter ~= "All", Theme.Icons.Filter)
		typeBtn.Activated:Connect(function()
			local opts = {}
			for _, f in typeFilters do
				-- The Loadout Type menu has icon rows.
				table.insert(opts, { label = f.label, value = f.id, active = typeFilter == f.id, icon = f.icon })
			end
			showDropdown(typeBtn, opts, function(v: any)
				typeFilter = v
				if v == "All" then rarityFilter = "All" end -- full reset, as in the Loadout
				onChanged()
			end)
		end)

		local rarityBtn = makeButton(row, if rarityFilter == "All" then "Rarity" else rarityFilter, 3,
			rarityFilter ~= "All", Theme.Icons.Filter)
		rarityBtn.Activated:Connect(function()
			local opts = {}
			for _, r in rarityOptions do
				-- Same as the Loadout Rarity menu: plain rows (no rarity colours).
				table.insert(opts, { label = if r == "All" then "All Rarities" else r, value = r, active = rarityFilter == r })
			end
			showDropdown(rarityBtn, opts, function(v: any)
				rarityFilter = v
				onChanged()
			end)
		end)

		local sortBtn = makeButton(row, (sortOptions[sortIndex] or sortOptions[1]).label, 4, false, Theme.Icons.Sort)
		sortBtn.Activated:Connect(function()
			local opts = {}
			for i, s in sortOptions do
				table.insert(opts, { label = s.label, value = i, active = sortIndex == i })
			end
			showDropdown(sortBtn, opts, function(v: any)
				sortIndex = v
				onChanged()
			end)
		end)

		-- Optional on/off toggle (opt-in), same button art as the others; gold-tint when on.
		if toggleCfg then
			local tb2 = makeButton(row, toggleLabel(), 5, toggleOn, Theme.Icons.Filter)
			tb2.Size = UDim2.new(0, toggleW, 1, 0)
			tb2.Activated:Connect(function()
				toggleOn = not toggleOn
				onChanged()
			end)
		end

		row.Parent = parent
	end

	-- Filters (type, rarity, search on the name) and sorts a grid entry list. Returns a new list.
	function self.Apply(entries: { any }): { any }
		local q = string.lower(searchText)
		local out = {}
		for _, e in entries do
			local ok = true
			if typeFilter ~= "All" and typeOf(e) ~= typeFilter then ok = false end
			if ok and rarityFilter ~= "All" and e.rarity ~= rarityFilter then ok = false end
			if ok and q ~= "" and not string.find(string.lower(tostring(e.name or "")), q, 1, true) then ok = false end
			if ok then table.insert(out, e) end
		end
		local s = sortOptions[sortIndex] or sortOptions[1]
		table.sort(out, function(a: any, b: any): boolean
			local an, bn = tostring(a.name or ""), tostring(b.name or "")
			if s.compare then
				local r = s.compare(a, b)
				if r ~= nil then return r end
			elseif s.field == "level" then
				local la, lb = tonumber(a.level) or 0, tonumber(b.level) or 0
				if la ~= lb then return if s.desc then la > lb else la < lb end
			elseif s.field == "rarity" then
				local ra, rb = RARITY_RANK[a.rarity] or 0, RARITY_RANK[b.rarity] or 0
				if ra ~= rb then return if s.desc then ra > rb else ra < rb end
			end
			if an ~= bn then return an < bn end
			return tostring(a.key) < tostring(b.key) -- stable order for equal items
		end)
		return out
	end

	function self.IsFiltering(): boolean
		return typeFilter ~= "All" or rarityFilter ~= "All" or searchText ~= ""
	end

	function self.ToggleOn(): boolean
		return toggleOn
	end

	function self.Reset()
		closeDropdown()
		typeFilter, rarityFilter, sortIndex, searchText = "All", "All", 1, ""
		toggleOn = toggleDefault
	end

	function self.Close()
		closeDropdown()
	end

	return self
end

return table.freeze(ItemListToolbar)
