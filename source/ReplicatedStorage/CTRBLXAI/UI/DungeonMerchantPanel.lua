--!strict
-- DungeonMerchantPanel.lua
-- CTRBLXAI | Dungeon Merchant room panel (Dungeon build step 6, 2026-11-14; project_rules 268, Q9/Q10).
-- Split out of DungeonScreen.lua (989 lines) so that file stays under 1000.
--
-- Display + input only (ARC-001 / SEC-002): the client sends a slot number, the server prices and
-- validates everything (DungeonAction MerchantState / MerchantBuy / MerchantRefill) and answers with
-- fresh state. Silver step 2 (rules 268 / 278): prices are in SILVER; bought items go into the run Bag
-- (lost on a failed run like any Bag item, USER RULING 2026-11-16 7:22 PM).
--
-- TEXT: approved (project_rules 275, user 2026-11-14 10:11 AM; silver lines SB-01/07/08/19 approved
-- 2026-11-15 9:09 PM).

local uiFolder = script.Parent
local Theme: any = (require :: any)(uiFolder:WaitForChild("Theme", 10))
local GuildScreen: any = (require :: any)(uiFolder:WaitForChild("GuildScreen", 10))
-- 2026-11-16 (user 7:14 PM): same tile grid + item inspector as the normal Merchant screen.
local MerchantInspector: any = (require :: any)(uiFolder:WaitForChild("MerchantInspector", 10))

local DungeonMerchantPanel = {}

export type Ctx = {
	gui: Instance,                               -- the screen's ScreenGui (overlay parent)
	act: (data: { [string]: any }) -> any?,      -- DungeonScreen act(): server call + state update
	onLeave: () -> (),                           -- Continue (move on) + re-render
	setStatus: (text: string, isError: boolean?) -> (),
}

local overlay: Instance? = nil
local lastCtx: Ctx? = nil
local selectedSlot: number? = nil -- the stock slot shown in the inspector
local lastM: any = nil -- the stock last drawn (Select re-draws it)

local function close()
	if overlay then
		overlay:Destroy()
		overlay = nil
	end
end

local function text(parent: Instance?, s: string, size: number, color: Color3, bold: boolean?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Font = if bold then Theme.Font.PrimaryBold else Theme.Font.Primary
	l.TextSize = math.max(10, size) -- 10 px phone floor
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = s
	l.ZIndex = 22
	l.Parent = parent
	return l
end

local render: (m: any) -> () = function() end

local function call(data: { [string]: any })
	local c = lastCtx
	if not c then return end
	local res = c.act(data)
	if res and res.merchant then
		render(res.merchant)
	end
end

render = function(m: any)
	local c = lastCtx
	if not c then return end
	lastM = m
	close()
	-- Same full-screen frame as the guild Merchant screen (2026-11-17 style fix): header title +
	-- silver, ornate grid / inspector panels, every button lower right (row 1 refill, row 2 Buy / leave).
	local view = GuildScreen.CreateView({ name = "MerchantPanel", title = "Merchant", buttonRows = 2 }) -- DG-ROOM-MERCHANT (APPROVED, rule 275)
	view.SetGold(`Silver {(m and m.silver) or 0}`) -- SB-01 (fallback text)
	-- Silver icon + number, the same look as the guild header currencies (user 2026-11-17 10:33 AM).
	if view.SetCurrencies then view.SetCurrencies({ { "Silver", tostring((m and m.silver) or 0) } }) end
	local o = view.Root
	o.Parent = c.gui
	overlay = o
	-- SB-19 "Bought — always kept" note removed (retired 2026-11-16 7:22 PM, rules 264 / 275).

	-- Entries: one per stock slot. Price in silver (SB-07) inside the inspector; sold slots dimmed + "Sold out".
	local entries = {}
	for _, e in (m and m.stock) or {} do
		table.insert(entries, {
			key = e.slot, detail = e.detail, name = tostring(e.name or (e.detail and e.detail.name) or e.id or ""),
			level = if e.kind == "gear" then e.itemLevel else nil, rarity = e.rarity or e.tier or "Common",
			price = e.price, priceUnit = "silver", noPriceBadge = true, queued = e.bought == true,
			tagText = if e.bought then "Sold out" else nil, tagColor = Theme.Colors.TextSecondary, -- DGM-SOLD (APPROVED)
			bought = e.bought == true,
		})
	end
	local sel = MerchantInspector.ResolveSelected(entries, selectedSlot)
	selectedSlot = sel and sel.key or nil

	local main = view.Main :: any
	local left = Instance.new("ScrollingFrame")
	left.Name = "Grid"
	left.Size = UDim2.fromScale(1, 1)
	left.BackgroundTransparency = 1
	left.BorderSizePixel = 0
	left.ScrollBarThickness = 4
	left.AutomaticCanvasSize = Enum.AutomaticSize.Y
	left.CanvasSize = UDim2.new()
	MerchantInspector.BuildGrid(left, {
		entries = entries, selectedKey = selectedSlot,
		width = math.max(240, main.AbsoluteSize.X - 6), heightHint = math.max(120, main.AbsoluteSize.Y),
		onSelect = function(key: any) selectedSlot = key render(m) end,
	})
	left.Parent = view.Main
	MerchantInspector.BuildDetail(view.Side, sel)

	-- Two right-aligned button rows in the Buttons group (refill or the full note / Buy + leave).
	local function btnRow(order: number): Frame
		local r = Instance.new("Frame")
		r.Name = "Row" .. order
		r.Position = UDim2.fromOffset(0, (order - 1) * (GuildScreen.ROW_H + GuildScreen.ROW_GAP))
		r.Size = UDim2.new(1, 0, 0, GuildScreen.ROW_H)
		r.BackgroundTransparency = 1
		local rl = Instance.new("UIListLayout")
		rl.FillDirection = Enum.FillDirection.Horizontal
		rl.HorizontalAlignment = Enum.HorizontalAlignment.Right
		rl.VerticalAlignment = Enum.VerticalAlignment.Center
		rl.Padding = UDim.new(0, 6)
		rl.SortOrder = Enum.SortOrder.LayoutOrder
		rl.Parent = r
		r.Parent = view.Buttons
		return r
	end
	local row1, btns = btnRow(1), btnRow(2)
	local rf = m and m.refill
	local missing = rf and (rf.missing or rf.charges or 0) or 0
	if missing > 0 then
		-- Charges missing: always offer the refill (SB-06 refusal comes from the server).
		local price = if (rf.cost or 0) > 0 then rf.cost else (rf.need or 0)
		local rb = Theme.MakeBarButton(nil, `Refill all ({price} silver)`, "Secondary", function() -- SB-08
			call({ action = "MerchantRefill" })
		end, { name = "Btn_Refill", minHeight = GuildScreen.ROW_H, layoutOrder = 1 })
		rb.Parent = row1
	else
		local full = text(row1, "Every equipped consumable is full.", Theme.Text.Small(), -- APPROVED (ApothecaryScreen)
			Theme.Colors.TextSecondary)
		full.Size = UDim2.new(1, 0, 1, 0)
		full.TextXAlignment = Enum.TextXAlignment.Right
		full.LayoutOrder = 1
	end
	if sel and not sel.bought then
		local slot = sel.key
		local b = Theme.MakeBarButton(nil, "Buy", "Primary", function() -- APPROVED ("Buy", Merchant/Apothecary screens)
			call({ action = "MerchantBuy", slot = slot })
		end, { name = "Btn_Buy", minHeight = GuildScreen.ROW_H, layoutOrder = 2 })
		b.Parent = btns
	end
	local leave = Theme.MakeBarButton(nil, "Keep exploring", "Primary", function() -- DG-ESCROOM-STAY (APPROVED, reused)
		close()
		selectedSlot = nil
		c.onLeave()
	end, { name = "Btn_Leave", minHeight = GuildScreen.ROW_H, layoutOrder = 3 })
	leave.Parent = btns
end

--- Open the panel for the current Merchant room (asks the server for the stock).
function DungeonMerchantPanel.Open(c: Ctx)
	lastCtx = c
	selectedSlot = nil
	local res = c.act({ action = "MerchantState" })
	if res and res.merchant then
		render(res.merchant)
	end
end

--- Treasure result (user 2026-11-16 7:14 PM): the found item as a tile (icon, rarity colour) next to the
--- same inspector as the Merchant. tr = DungeonAction Treasure answer { itemName, silver, detail }.
function DungeonMerchantPanel.ShowTreasure(gui: Instance, tr: any, onBack: () -> ())
	close()
	-- Same full-screen frame as the guild screens (2026-11-17 style fix): title in the header, the
	-- found line(s) + tile in the left panel, the item inspector in the right panel, Back lower right.
	local view = GuildScreen.CreateView({ name = "TreasurePanel", title = "Treasure" }) -- DG-TREASURE-T
	local o = view.Root
	o.Parent = gui
	overlay = o
	local box = view.Main
	local name = tostring(tr.itemName or "an item")
	local l1 = text(box, `You found {name}! It's in your bag.`, Theme.Text.Small(), Theme.Colors.TextPrimary) -- DG-TREASURE-1
	l1.Size = UDim2.new(1, 0, 0, 18)
	local silver = tonumber(tr.silver) or 0
	local TOP = 22
	if silver > 0 then
		local s = text(box, `+{silver} silver`, Theme.Text.Small(), Theme.Colors.TextGold, true) -- SB-04 (hidden at 0)
		s.Position = UDim2.fromOffset(0, 20)
		s.Size = UDim2.new(1, 0, 0, 18)
		TOP = 42
	end
	local d = tr.detail
	local entry = { key = 1, detail = d, name = tostring((d and d.name) or name), level = d and d.itemLevel or nil,
		rarity = (d and d.rarity) or "Common" }
	local main = view.Main :: any
	local left = Instance.new("ScrollingFrame")
	left.Name = "Grid"
	left.Position = UDim2.fromOffset(0, TOP)
	left.Size = UDim2.new(1, 0, 1, -TOP)
	left.BackgroundTransparency = 1
	left.BorderSizePixel = 0
	left.ScrollBarThickness = 0
	left.CanvasSize = UDim2.new()
	MerchantInspector.BuildGrid(left, { entries = { entry }, selectedKey = 1,
		width = math.max(240, main.AbsoluteSize.X - 6), heightHint = math.max(120, main.AbsoluteSize.Y - TOP), onSelect = function() end })
	left.Parent = box
	MerchantInspector.BuildDetail(view.Side, entry)
	local back = Theme.MakeIconButton(nil, "Back", function() close() onBack() end,
		{ name = "Btn_Back", size = UDim2.fromOffset(GuildScreen.ROW_H, GuildScreen.ROW_H) })
	back.AnchorPoint = Vector2.new(1, 1)
	back.Position = UDim2.fromScale(1, 1)
	back.Parent = view.Buttons
end

--- Show one stock slot in the inspector (the same path as tapping its tile; used by Studio tests).
function DungeonMerchantPanel.Select(slot: number)
	if not (overlay and lastM) then return end
	selectedSlot = slot
	render(lastM)
end

function DungeonMerchantPanel.Close()
	close()
end

function DungeonMerchantPanel.IsOpen(): boolean
	return overlay ~= nil
end


return table.freeze(DungeonMerchantPanel)
