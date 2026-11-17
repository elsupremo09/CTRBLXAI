--!strict
-- FurnishScreen.lua
-- CTRBLXAI | Furniture piece helpers + picker for the Guild Hall screen's Furnish tab (2026-11-17) + furniture craft list, moved out of GuildMenu.client.lua
-- (furniture v5 build step 4a, 2026-11-16). Step 4b (2026-11-16): the Furnish tab is now the ROOMS screen
-- (rooms + spots, piece picker / swap popup, storage list); the craft list scrolls (row 110 recipes).
-- GuildMenu still owns the page content and its row helpers; it passes them in through Init.
-- Display + input only: the server prices and checks everything (FurnitureService, SEC-001).

local FurnishScreen = {}

local C: any = nil
local Theme: any = nil
local GuildEvents: any = nil
local FurnitureData: any = nil
local call: (remote: RemoteFunction?, ...any) -> any? = function() return nil end
local invalidatePageCache: () -> () = function() end
local refreshOverview: () -> () = function() end
local setStatus: (text: string, isError: boolean?) -> () = function() end
local function busy(): boolean return C ~= nil and C.isBusy() == true end
local function setBusy(v: boolean) if C then C.setBusy(v) end end

-- Guild Hall screen (2026-11-17): it shows the Furnish tab and gets every FurnitureAction answer here.
local onResult: (res: any) -> () = function() end

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
		onResult(r)
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

-- No decimals in player text (loadout_ui_spec 129, user 2026-11-17 1:50 PM): flat kinds show whole
-- numbers; percent kinds keep one decimal only for a half step ("1.5%").
local function num(v: any, pct: boolean?): string
	local n = tonumber(v) or 0
	if not pct then return tostring(math.round(n)) end
	local r = math.round(n * 2) / 2
	if r == math.floor(r) then return tostring(math.floor(r)) end
	return string.format("%.1f", r)
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
		return `Enemies: -{num(v, PCT[k])}{unit} {label}` -- FUR-LINE-ENEMY
	end
	if l.threshold then return `Special: {label} +1` end -- FUR-LINE-THRESHOLD
	if l.signature then return `Always: +{num(v, PCT[k])}{unit} {label}` end -- FUR-SIGNATURE
	return `+{num(v, PCT[k])}{unit} {label}` -- FUR-LINE
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
	pickGui.DisplayOrder = Theme.FullScreen.DisplayOrder + 6 -- over the Guild Hall screen (2026-11-17)
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

-- ctx: Theme, GuildEvents, FurnitureData, playerGui, call, invalidatePageCache, refreshOverview,
-- setStatus, isBusy(), setBusy(v).
function FurnishScreen.Init(ctx: any)
	C = ctx
	Theme = ctx.Theme
	GuildEvents = ctx.GuildEvents
	FurnitureData = ctx.FurnitureData
	call = ctx.call
	invalidatePageCache = ctx.invalidatePageCache
	refreshOverview = ctx.refreshOverview
	setStatus = ctx.setStatus
	makeFurnGui(ctx.playerGui)
end

-- Shared piece helpers for the Guild Hall screen's Furnish tab (2026-11-17: the old row page moved
-- there as item tiles; the text builders stay here so the wording lives in one place).
function FurnishScreen.SetOnResult(fn: (res: any) -> ()) onResult = fn end
function FurnishScreen.Call(cmd: any) furnitureCall(cmd) end
function FurnishScreen.OpenPick(spot: any, storage: { any }, locked: boolean) openPick(spot, storage, locked) end
FurnishScreen.Num = num
FurnishScreen.LineText = lineText
FurnishScreen.PieceName = pieceName
FurnishScreen.PieceText = pieceText
FurnishScreen.FitsSpot = fitsSpot
FurnishScreen.SortStorage = sortStorage
function FurnishScreen.OpenCraft(building: string) openFurnitureCraft(building) end
function FurnishScreen.CloseCraft() if furnGui then closeFurnitureCraft() end end
function FurnishScreen.ClosePick() closePick() end

return FurnishScreen
