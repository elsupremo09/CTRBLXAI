--!strict
-- FurnishScreen.lua
-- CTRBLXAI | Guild Hall "Furnish" tab (step 4b: rooms screen) + furniture craft list, moved out of GuildMenu.client.lua
-- (furniture v5 build step 4a, 2026-11-16). Step 4b (2026-11-16): the Furnish tab is now the ROOMS screen
-- (rooms + spots, piece picker / swap popup, storage list); the craft list scrolls (row 110 recipes).
-- GuildMenu still owns the page content and its row helpers; it passes them in through Init.
-- Display + input only: the server prices and checks everything (FurnitureService, SEC-001).

local FurnishScreen = {}

type RowButton = { text: string, color: Color3, onTap: () -> (), enabled: boolean?, style: string? }

local C: any = nil
local Theme: any = nil
local GuildEvents: any = nil
local FurnitureData: any = nil
local call: (remote: RemoteFunction?, ...any) -> any? = function() return nil end
local clearContent: () -> () = function() end
local addHeading: (text: string) -> () = function() end
local addNote: (text: string) -> () = function() end
local addRow: (text: string, buttons: { RowButton }?, dim: boolean?) -> Frame = function() return nil :: any end
local guildHallHeader: () -> () = function() end
local invalidatePageCache: () -> () = function() end
local refreshOverview: () -> () = function() end
local setStatus: (text: string, isError: boolean?) -> () = function() end
local function busy(): boolean return C ~= nil and C.isBusy() == true end
local function setBusy(v: boolean) if C then C.setBusy(v) end end

local renderFurnish: (res: any) -> () = function() end

local pickGui: ScreenGui = nil :: any -- step 4b: piece picker / swap popup (created in Init)
local function closePick()
	if pickGui and pickGui.Enabled then
		pickGui.Enabled = false
		pickGui:ClearAllChildren()
	end
end

local function furnitureCall(cmd: any)
	if busy() then return end
	setBusy(true)
	local r = call(GuildEvents.FurnitureAction, cmd)
	setBusy(false)
	closePick()
	if r then
		invalidatePageCache()
		refreshOverview()
		renderFurnish(r)
	end
end

--------------------------------------------------
-- Step 4b (2026-11-16): Furnish ROOMS screen. Only approved text: guild_facilities 98 (v3 lines 1-23,
-- v4 lines 24-39, buttons), 112 (v5) and the 5 lines approved 11:02 PM (DRAFT_furnish_rooms_text_20261116.md).
--------------------------------------------------

-- Stat labels (the game's existing stat names, as on the INFO tab).
local LABEL: { [string]: string } = {
	STR = "STR", AGI = "AGI", DEX = "DEX", INT = "INT", VIT = "VIT", LUK = "LUK",
	maxHp = "Max HP", maxMp = "Max MP", attack = "Attack", defense = "Defense",
	precision = "Precision", evasion = "Evasion", skillPotency = "Skill Potency", healingOutput = "Healing Output",
	itemDamage = "Item Damage", collisionDamage = "Collision Damage", fallDamage = "Fall Damage",
	debuffResist = "Debuff Resistance", rtDelayResist = "RT Delay Resistance", collisionResist = "Collision Resistance",
	fallResist = "Fall Resistance", movement = "Movement", jump = "Jump", force = "Force", stability = "Stability",
	discoveryRadius = "Discovery Radius", interactRange = "Interact Range", itemRange = "Item Range", range = "Range",
}
local PCT: { [string]: boolean } = {
	precision = true, evasion = true, skillPotency = true, healingOutput = true, itemDamage = true,
	collisionDamage = true, fallDamage = true, debuffResist = true, rtDelayResist = true,
	collisionResist = true, fallResist = true,
}
local TOP_RARITY: { [string]: boolean } = { Mythic = true, Transcendent = true }

local function num(v: any): string
	local n = tonumber(v) or 0
	if n == math.floor(n) then return tostring(math.floor(n)) end
	return string.format("%.1f", n)
end

local function lineText(l: any): string
	local k = tostring(l.kind)
	local label = LABEL[k] or k
	local v = math.abs(tonumber(l.value) or 0)
	local unit = if PCT[k] then "%" else ""
	if l.enemy then
		if k == "hpLoss" then return `All enemies lose {num(v)} HP at the start of battle (can't go below 1).` end -- FUR-ENEMY-HPLOSS
		if k == "mpLoss" then return `All enemies lose {num(v)} MP at the start of battle.` end -- FUR-ENEMY-MPLOSS
		if l.threshold then return `Enemies: -1 {label}` end -- FUR-LINE-ENEMY
		return `Enemies: -{num(v)}{unit} {label}` -- FUR-LINE-ENEMY
	end
	if l.threshold then return `Special: {label} +1` end -- FUR-LINE-THRESHOLD
	if l.signature then return `Always: +{num(v)}{unit} {label}` end -- FUR-SIGNATURE
	return `+{num(v)}{unit} {label}` -- FUR-LINE
end

local function pieceName(inst: any): string
	local p = FurnitureData.V4.Get(inst.id)
	local name = p and p.name or tostring(inst.id)
	if inst.fixed or inst.looks or type(inst.rarity) ~= "string" or inst.rarity == "None" or inst.rarity == "Fixed" then
		return name
	end
	return `{inst.rarity} {name}` -- FUR-RARITY
end

-- Text block for one piece: name, its lines, then one status line (capped / counts once / top source).
local function pieceText(inst: any, spotStatus: string?, lineStatus: { string }?): (string, number)
	local p = FurnitureData.V4.Get(inst.id)
	local out: { string } = { pieceName(inst) }
	if inst.looks then
		table.insert(out, "Looks only — no bonus.") -- FUR-LOOKS-ONLY
	elseif inst.fixed then
		local old = FurnitureData.Get(inst.id)
		table.insert(out, old and old.text or "")
	else
		local parts: { string } = {}
		for _, l in (type(inst.lines) == "table" and inst.lines or {}) do table.insert(parts, lineText(l)) end
		if #parts > 0 then table.insert(out, table.concat(parts, "  ·  ")) end
	end
	if spotStatus == "capped" then
		table.insert(out, "Capped — this bonus is already at its limit.") -- FUR-CAPPED
	elseif spotStatus == "invalid" then
		table.insert(out, `Only one {p and p.name or "piece"} counts at a time.`) -- FUR-COUNTS-ONCE
	elseif type(lineStatus) == "table" then
		for i, st in lineStatus do
			local l = type(inst.lines) == "table" and inst.lines[i] or nil
			if st == "capped" and l then
				table.insert(out, if l.threshold then "Special bonus limit reached (2). This line does nothing." -- FUR-THRESHOLD-CAPPED
					else "Capped — this bonus is already at its limit.") -- FUR-CAPPED
				break
			end
		end
	end
	if TOP_RARITY[tostring(inst.rarity)] then table.insert(out, "Only found from deep dungeon bosses.") end -- FUR-DROP-SOURCE-TOP
	return table.concat(out, "\n"), #out
end

local function fitsSpot(inst: any, spot: any): boolean
	local p = FurnitureData.V4.Get(inst.id)
	if not p then return false end
	if spot.wall then return p.category == "Wall" end
	return type(spot.accepts) == "table" and table.find(spot.accepts, p.category) ~= nil
end

local RAR_ORDER: { [string]: number } = {}
local function sortStorage(list: { any })
	if next(RAR_ORDER) == nil then
		for i, r in FurnitureData.V4.RarityOrder do RAR_ORDER[r] = i end
	end
	table.sort(list, function(a, b)
		local ra, rb = RAR_ORDER[a.rarity] or 0, RAR_ORDER[b.rarity] or 0
		if ra ~= rb then return ra > rb end
		local na, nb = pieceName(a), pieceName(b)
		if na ~= nb then return na < nb end
		return tostring(a.uid) < tostring(b.uid)
	end)
end

local function sizeRow(row: Frame?, lines: number)
	if row then row.Size = UDim2.new(1, 0, 0, math.max(56, 14 + lines * 17)) end
end

-- Picker: storage pieces that fit one spot. Taken spot -> FUR-CAT-FULL confirm (Swap / Cancel).
local function openPick(spot: any, storage: { any }, locked: boolean)
	if not pickGui then return end
	pickGui:ClearAllChildren()
	local function makeDim()
		local dim = Instance.new("TextButton")
		dim.Name = "Dim"
		dim.Size = UDim2.fromScale(1, 1)
		dim.BackgroundColor3 = Color3.new(0, 0, 0)
		dim.BackgroundTransparency = 0.45
		dim.Text = ""
		dim.AutoButtonColor = false
		dim.Parent = pickGui
		dim.Activated:Connect(closePick)
	end
	makeDim()
	local list: { any } = {}
	for _, inst in storage do if fitsSpot(inst, spot) then table.insert(list, inst) end end
	local rowH = 64
	local panelH = math.min(56 + math.max(1, #list) * (rowH + 6) + 10, 340)
	local panel = Theme.MakePanel("FurniturePickPanel", UDim2.fromOffset(470, panelH),
		UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), pickGui)
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(16, 6)
	title.Size = UDim2.new(1, -80, 0, 40)
	title.Font = Theme.Font.PrimaryBold
	title.TextSize = Theme.Text.Body() + 2
	title.TextColor3 = Theme.Colors.TextGold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Text = tostring(spot.roomName or "")
	title.Parent = panel
	Theme.MakeIconButton(panel, "Back", closePick, { size = UDim2.fromOffset(44, 44), position = UDim2.new(1, -54, 0, 4) })
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(12, 52)
	scroll.Size = UDim2.new(1, -24, 1, -60)
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.fromOffset(0, #list * (rowH + 6))
	scroll.Parent = panel
	if #list == 0 then
		local none = Instance.new("TextLabel")
		none.BackgroundTransparency = 1
		none.Size = UDim2.new(1, 0, 0, 40)
		none.Font = Theme.Font.Primary
		none.TextSize = Theme.Text.Small()
		none.TextColor3 = Theme.Colors.TextSecondary
		none.Text = "No furniture in storage." -- FUR-STORAGE-EMPTY
		none.Parent = scroll
	end
	local function confirmSwap(inst: any)
		pickGui:ClearAllChildren()
		makeDim()
		local box = Theme.MakePanel("FurnitureSwapPanel", UDim2.fromOffset(420, 150), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), pickGui)
		local msg = Instance.new("TextLabel")
		msg.BackgroundTransparency = 1
		msg.Size = UDim2.new(1, -32, 0, 60)
		msg.Position = UDim2.fromOffset(16, 10)
		msg.TextWrapped = true
		msg.TextXAlignment = Enum.TextXAlignment.Left
		msg.TextColor3 = Theme.Colors.TextPrimary
		msg.Font = Theme.Font.Primary
		msg.TextSize = Theme.Text.Body()
		msg.Text = `This spot in the {spot.roomName} is taken. Swap it out?` -- FUR-CAT-FULL
		msg.Parent = box
		local yes = Theme.MakeTabButton(box, "Swap", "Inactive", function() -- FUR-CAT-FULL button
			furnitureCall({ action = "Place", piece = inst.uid, slot = spot.key })
		end, { name = "Swap", size = UDim2.fromOffset(170, 44) })
		yes.Position = UDim2.new(0, 16, 1, -58)
		local no = Theme.MakeTabButton(box, "Cancel", "Inactive", closePick, { name = "Cancel", size = UDim2.fromOffset(170, 44) })
		no.Position = UDim2.new(1, -186, 1, -58)
		pickGui.Enabled = true
	end
	for i, inst in list do
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Position = UDim2.fromOffset(0, (i - 1) * (rowH + 6))
		row.Size = UDim2.new(1, -8, 0, rowH)
		row.Parent = scroll
		local txt = pieceText(inst, nil, nil)
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Size = UDim2.new(1, -132, 1, 0)
		lbl.Font = Theme.Font.Primary
		lbl.TextSize = Theme.Text.Small()
		lbl.TextColor3 = Theme.Colors.TextPrimary
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.TextYAlignment = Enum.TextYAlignment.Center
		lbl.TextWrapped = true
		lbl.Text = txt
		lbl.Parent = row
		local btn = Theme.MakeTabButton(row, "Place", if locked then "Disabled" else "Inactive", function()
			if locked or busy() then return end
			if spot.uid then confirmSwap(inst) else furnitureCall({ action = "Place", piece = inst.uid, slot = spot.key }) end
		end, { name = "Place_" .. tostring(inst.uid), size = UDim2.fromOffset(120, 44) })
		btn.Position = UDim2.new(1, -120, 0.5, -22)
	end
	pickGui.Enabled = true
end

renderFurnish = function(res: any)
	if C.currentPage() ~= "GuildHall" or C.guildHallTab() ~= "Furnish" then return end
	local f = type(res) == "table" and res.furniture or nil
	clearContent()
	guildHallHeader()
	if type(f) ~= "table" or not FurnitureData then return end
	local v4 = type(f.v4) == "table" and f.v4 or {}
	local totals = type(v4.totals) == "table" and v4.totals or {}
	local spots: { any } = type(v4.spots) == "table" and v4.spots or {}
	local insts: { any } = type(v4.instances) == "table" and v4.instances or {}
	local gh = tonumber(f.guildHallLevel) or 1
	local locked = f.locked == true
	local byUid: { [string]: any } = {}
	local storage: { any } = {}
	local anyEnemy, anyThreshold = false, false
	for _, inst in insts do
		byUid[tostring(inst.uid)] = inst
		if inst.spot == nil then table.insert(storage, inst) end
	end
	sortStorage(storage)
	for _, sp in spots do
		local inst = sp.uid and byUid[tostring(sp.uid)]
		for _, l in (inst and type(inst.lines) == "table" and inst.lines or {}) do
			if l.enemy then anyEnemy = true end
			if l.threshold then anyThreshold = true end
		end
	end
	-- Top bar: Bonus x / cap (FUR-CAP, cap = 8 x Guild Hall level) + the special-bonus counter.
	addNote(`Bonus: {num(f.points or totals.points or 0)} / {num(f.cap or totals.cap or 0)}`) -- FUR-CAP
	if anyThreshold then
		local n = 0
		for _ in (type(totals.threshold) == "table" and totals.threshold or {}) do n += 1 end
		addNote(if anyEnemy then `Special bonuses (yours + enemy): {n}/2` else `Special bonuses: {n}/2`) -- FUR-THRESHOLD-SHARED / -COUNT
	end
	if locked then addNote("You can't change furniture during a battle or dungeon run.") end -- FUR-LOCKED-RUN
	-- Rooms in table order; open rooms list their spots, locked rooms are greyed.
	local lineStatusAll = type(totals.lineStatus) == "table" and totals.lineStatus or {}
	for _, room in FurnitureData.V4.Rooms do
		if room.gh > gh then
			sizeRow(addRow(`{room.name}\nUnlocks at Guild Hall level {room.gh}.`, nil, true), 2) -- FUR-ROOM-LOCKED
		else
			local mine: { any } = {}
			local fl, flMax, wl, wlMax = 0, 0, 0, 0
			for _, sp in spots do
				if sp.room == room.id then
					table.insert(mine, sp)
					if sp.wall then wlMax += 1 if sp.uid then wl += 1 end
					else flMax += 1 if sp.uid then fl += 1 end end
				end
			end
			addHeading(`{room.name} — Floor {fl}/{flMax} · Wall {wl}/{wlMax}`) -- FUR-CAT-COUNT
			for _, sp in mine do
				local inst = sp.uid and byUid[tostring(sp.uid)]
				local fitting = 0
				for _, s2 in storage do if fitsSpot(s2, sp) then fitting += 1 end end
				if inst then
					local txt, n = pieceText(inst, sp.status, lineStatusAll[tostring(inst.uid)])
					sizeRow(addRow(txt, { {
						text = "Remove", color = Theme.Colors.Danger, style = "Secondary", enabled = not locked,
						onTap = function() furnitureCall({ action = "Remove", slot = sp.key }) end,
					}, {
						text = "Swap", color = Theme.Colors.Success, style = "Primary", enabled = (not locked) and fitting > 0, -- FUR-SWAP button
						onTap = function() if not locked then openPick(sp, storage, locked) end end,
					} }, sp.status == "capped" or sp.status == "invalid"), n)
				else
					local empty = if sp.wall then "Wall decoration — empty" else "Empty slot"
					local fitsTxt = if sp.wall then "" else "\n" .. table.concat(type(sp.accepts) == "table" and sp.accepts or {}, ", ") -- FUR-SPOT-FITS
					sizeRow(addRow(empty .. fitsTxt, { {
						text = "Place", color = Theme.Colors.Success, style = "Primary", enabled = (not locked) and fitting > 0,
						onTap = function() if not locked then openPick(sp, storage, locked) end end,
					} }, true), if sp.wall then 1 else 2)
				end
			end
		end
	end
	-- Storage: every piece not placed. Place = first free spot that fits (server picks; FUR-NO-SPOT if none).
	addHeading(`Storage ({#storage})`) -- FUR-STORAGE-TITLE
	if #storage == 0 then
		addNote("No furniture in storage.") -- FUR-STORAGE-EMPTY
		addNote("Find furniture in the Dungeon, or craft it.") -- FUR-NO-SHOP
	end
	for _, inst in storage do
		local txt, n = pieceText(inst, nil, nil)
		sizeRow(addRow(txt, { {
			text = "Place", color = Theme.Colors.Success, style = "Primary", enabled = not locked,
			onTap = function() if not locked then furnitureCall({ action = "Place", piece = inst.uid, slot = "auto" }) end end,
		} }), n)
	end
	-- WARN-A: pieces left behind at the 400 limit (also shown on return to base).
	if type(f.leftBehind) == "table" and #f.leftBehind > 0 then
		setStatus(table.concat(f.leftBehind, "\n"), true) -- FUR-STORAGE-FULL
		task.spawn(function() pcall(function() GuildEvents.FurnitureAction:InvokeServer({ action = "AckLeftBehind" }) end) end)
	end
end

-- Furniture craft list (step 3; approved lines 1-4 + "Already owned" / "Not enough gold"). One small
-- modal per open; the server prices and checks everything (FurnitureService.Craft, SEC-001).
local furnGui: ScreenGui = nil :: any -- created in Init (needs PlayerGui)
local function makeFurnGui(playerGui: Instance)
	furnGui = Instance.new("ScreenGui")
	furnGui.Name = "FurnitureCraft"
	furnGui.ResetOnSpawn = false
	furnGui.DisplayOrder = 65
	furnGui.Enabled = false
	furnGui.Parent = playerGui -- NET-004
	pickGui = Instance.new("ScreenGui") -- step 4b: piece picker / swap popup (own gui: the craft list closes itself)
	pickGui.Name = "FurniturePick"
	pickGui.ResetOnSpawn = false
	pickGui.DisplayOrder = 66
	pickGui.Enabled = false
	pickGui.Parent = playerGui -- NET-004
end
local function closeFurnitureCraft()
	if not furnGui.Enabled then return end
	furnGui.Enabled = false
	furnGui:ClearAllChildren()
end
local function renderFurnitureCraft(building: string, rows: { any })
	furnGui:ClearAllChildren()
	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Parent = furnGui
	local rowH = 80 -- name, effect, then the reason line under both (full width)
	-- step 4b: up to 6 recipes per building now (row 110) -> capped height + scrolling list (phone 750x382)
	local panel = Theme.MakePanel("FurniturePanel", UDim2.fromOffset(470, math.min(70 + math.max(1, #rows) * (rowH + 6), 340)),
		UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), furnGui)
	local list = Instance.new("ScrollingFrame")
	list.Name = "Rows"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, 58)
	list.Size = UDim2.new(1, 0, 1, -64)
	list.ScrollBarThickness = 6
	list.CanvasSize = UDim2.fromOffset(0, #rows * (rowH + 6))
	list.Parent = panel
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -80, 0, 40)
	title.Font = Theme.Font.PrimaryBold
	title.TextSize = Theme.Text.Body() + 4
	title.TextColor3 = Theme.Colors.TextGold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Furniture" -- approved step 3 line 1
	title.Parent = panel
	Theme.MakeIconButton(panel, "Back", closeFurnitureCraft, { size = UDim2.fromOffset(44, 44), position = UDim2.new(1, -54, 0, 8) })
	for i, r in ipairs(rows) do
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Position = UDim2.fromOffset(16, (i - 1) * (rowH + 6))
		row.Size = UDim2.new(1, -32, 0, rowH)
		row.Parent = list
		local nameL = Instance.new("TextLabel")
		nameL.BackgroundTransparency = 1
		nameL.Size = UDim2.new(1, -228, 0, 26)
		nameL.Font = Theme.Font.PrimaryBold
		nameL.TextSize = Theme.Text.Body()
		nameL.TextColor3 = Theme.Colors.TextPrimary
		nameL.TextXAlignment = Enum.TextXAlignment.Left
		nameL.TextTruncate = Enum.TextTruncate.AtEnd
		nameL.Text = tostring(r.name)
		nameL.Parent = row
		local fx = nameL:Clone()
		fx.Position = UDim2.fromOffset(0, 26)
		fx.Font = Theme.Font.Primary
		fx.TextSize = Theme.Text.Small()
		fx.TextColor3 = Theme.Colors.TextSecondary
		fx.Text = tostring(r.text)
		fx.Parent = row
		if r.owned then
			local o = fx:Clone()
			o.Position = UDim2.new(1, -220, 0, 10)
			o.Size = UDim2.fromOffset(220, 30)
			o.TextXAlignment = Enum.TextXAlignment.Right
			o.Text = "Already owned"
			o.Parent = row
		else
			local label = `Craft — {tonumber(r.price) or 0} gold` .. (if r.matName then ` + {tonumber(r.matN) or 0} {r.matName}` else "") -- approved step 3 line 2
			local btn = Theme.MakeTabButton(row, label, if r.canCraft then "Inactive" else "Disabled", function()
				if not r.canCraft or busy() then return end
				setBusy(true)
				local res = call(GuildEvents.FurnitureAction, { action = "Craft", piece = r.id, building = building })
				setBusy(false)
				if res then
					if type(res.message) == "string" then setStatus(res.message) end -- approved step 3 line 4
					invalidatePageCache()
					refreshOverview()
					renderFurnitureCraft(building, type(res.craft) == "table" and res.craft or {})
				end
			end, { name = "Craft_" .. tostring(r.id), size = UDim2.fromOffset(220, 44) })
			btn.Position = UDim2.new(1, -220, 0, 0)
			if not r.canCraft and type(r.reason) == "string" then
				local why = fx:Clone()
				why.Position = UDim2.fromOffset(0, 56)
				why.Size = UDim2.new(1, 0, 0, 20)
				why.TextXAlignment = Enum.TextXAlignment.Right
				why.TextColor3 = Theme.Colors.Danger
				why.Text = r.reason -- approved step 3 line 3 / "Not enough gold (have / cost)"
				why.Parent = row
			end
		end
	end
	furnGui.Enabled = true
end
local function openFurnitureCraft(building: string)
	if busy() then return end
	setBusy(true)
	local res = call(GuildEvents.FurnitureAction, { action = "CraftRows", building = building })
	setBusy(false)
	if res and type(res.craft) == "table" then renderFurnitureCraft(building, res.craft) end
end

-- ctx: Theme, GuildEvents, FurnitureData, playerGui, call, clearContent, addHeading, addNote, addRow,
-- guildHallHeader, invalidatePageCache, refreshOverview, setStatus, isBusy(), setBusy(v),
-- currentPage(), guildHallTab().
function FurnishScreen.Init(ctx: any)
	C = ctx
	Theme = ctx.Theme
	GuildEvents = ctx.GuildEvents
	FurnitureData = ctx.FurnitureData
	call = ctx.call
	clearContent = ctx.clearContent
	addHeading = ctx.addHeading
	addNote = ctx.addNote
	addRow = ctx.addRow
	guildHallHeader = ctx.guildHallHeader
	invalidatePageCache = ctx.invalidatePageCache
	refreshOverview = ctx.refreshOverview
	setStatus = ctx.setStatus
	makeFurnGui(ctx.playerGui)
end

function FurnishScreen.Render(res: any) renderFurnish(res) end
function FurnishScreen.OpenCraft(building: string) openFurnitureCraft(building) end
function FurnishScreen.CloseCraft() if furnGui then closeFurnitureCraft() end end
function FurnishScreen.ClosePick() closePick() end

return FurnishScreen
