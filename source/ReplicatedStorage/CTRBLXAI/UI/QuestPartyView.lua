--!strict
-- QuestPartyView.lua
-- CTRBLXAI | Quest Board "Choose party" view (Quest Board redesign step 4, 2026-11-18).
-- Rules: docs\CTRBLXAI.db game_flow 34-39; plan PLAN_questboard_redesign_20261117.md sections 2/6.
-- Opened from the Quest accepted view's "Choose party" (optional step: Embark also works from there).
--
-- Layout (GuildScreen, fullMain, framed header like the Board view): crest + "QUEST BOARD" | currencies.
--   Main  : "Choose party", then one row per saved party (max 5, scrolls): emblem, name,
--           "{n}/{m} available", up to 7 portrait tiles (Lv badge, HP / MP bars, status:
--           "Ready" | Dispatch icon + "Back in {n} battles" | "Exploring a dungeon").
--           Footer: "Away units stay behind. Everyone else deploys." + "Deploying {n} units".
--   Buttons (lower right): Open Parties | Embark | Back
--
-- Display + input only (ARC-001 / SEC-002): the party list comes from the existing GetParties remote;
-- a row tap goes through the guild menu (ctx.onPick), which fires the existing SelectSortieParty with
-- the party id -- the same remote and payload the Loadout PARTIES pick mode uses. The server checks
-- the party is usable (Main.server partyUsable) before it is set.
--
-- Text: ONLY approved lines, verbatim:
--   game_flow 39: "Choose party" (10), "{n}/{m} available" (11), "Ready" (12), "Back in {n} battles"
--     (13), "Away units stay behind. Everyone else deploys." (14), "Deploying {n} units" (15),
--     "Open Parties" (16).
--   Existing lines: "QUEST BOARD", "Embark", "Departing when ready...", the embark phrases + "...",
--     "Exploring a dungeon" (2026-11-13 8:24 PM), "Lv.{n}" (Units screen badge), server error text.
--   Agent default (vetoable): "Back in {n} battles" uses the dispatch's days left. Each battle burns at
--   least one day, so n is the most battles until the unit is back.

local WAIT = 10

local uiFolder = script.Parent
local themeModule = uiFolder:WaitForChild("Theme", WAIT)
local guildScreenModule = uiFolder:WaitForChild("GuildScreen", WAIT)
if not themeModule or not guildScreenModule then
	error("[QuestPartyView] Theme / GuildScreen module not found")
end
-- Found at runtime via WaitForChild; the editor cannot follow that path (editor-only cast).
local Theme: any = (require :: any)(themeModule)
local GuildScreen: any = (require :: any)(guildScreenModule)
local uiCompModule = uiFolder:WaitForChild("UIComponents", WAIT)
local UIComponents: any = if uiCompModule then (require :: any)(uiCompModule) else nil

local GuildEvents: any, PartyArtData: any = nil, nil
do
	local rs = game:GetService("ReplicatedStorage")
	local root = rs:WaitForChild("CTRBLXAI", WAIT)
	local remotes = root and root:WaitForChild("Remotes", WAIT)
	local ge = remotes and remotes:WaitForChild("GuildEvents", WAIT)
	local okG, G = pcall(function() return if ge then (require :: any)(ge) else nil end)
	GuildEvents = if okG then G else nil
	local content = rs:WaitForChild("Content", WAIT)
	local pa = content and content:WaitForChild("PartyArtData", WAIT)
	local okP, P = pcall(function() return if pa then (require :: any)(pa) else nil end)
	PartyArtData = if okP then P else nil
	if not GuildEvents then warn("[QuestPartyView] GuildEvents missing -- no party list") end
end

local QuestPartyView = {}

export type State = {
	quest: any,               -- the accepted quest (playerSlots = deploy limit)
	partyId: string?,         -- the party set to deploy (sortiePartySlot)
	locked: boolean,          -- the map is still being built (sortieLocked)
	departPending: boolean,   -- Embark was tapped while locked
}

export type Context = {
	parent: Instance,
	isBusy: () -> boolean,
	getState: () -> State?,
	embarkLines: { string },
	onPick: (id: string, name: string) -> (),  -- fires SelectSortieParty (guild menu)
	onEmbark: () -> (),                        -- same as the Quest accepted view's Embark
	onOpenParties: () -> (),                   -- Loadout PARTIES tab (edit parties)
	onBack: () -> (),                          -- back to the Quest accepted view
}

local MAX_TILES = 7
local GAP = 4
local LEFT_W = 132
local CYCLE_SECONDS = 2

local TXT_TITLE = "Choose party"
local TXT_READY = "Ready"
local TXT_DUNGEON = "Exploring a dungeon"
local TXT_INFO = "Away units stay behind. Everyone else deploys."
local TXT_OPEN = "Open Parties"
local TXT_EMBARK = "Embark"
local TXT_DEPARTING = "Departing when ready..."

local ctx: Context? = nil
local screen: any = nil
local isOpen = false
local data: any = nil       -- GetParties answer
local fetchToken = 0
local cycleToken = 0
local curGold: number? = nil
local curRes: any = nil
local render: () -> () = function() end

--------------------------------------------------
-- HELPERS (properties before Parent, NET-004)
--------------------------------------------------

local function makeText(parent: Instance?, text: string, size: number, color: Color3, bold: boolean?): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.BorderSizePixel = 0
	lbl.Font = if bold then Theme.Font.PrimaryBold else Theme.Font.Primary
	lbl.TextSize = size
	lbl.TextColor3 = color
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextYAlignment = Enum.TextYAlignment.Center
	lbl.TextTruncate = Enum.TextTruncate.AtEnd
	lbl.Text = text
	lbl.Parent = parent
	return lbl
end

local function corner(f: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = f
end

local function setLabel(btn: Instance?, text: string)
	if not btn then return end
	local lbl = btn:FindFirstChild("Label")
	if lbl and lbl:IsA("TextLabel") then lbl.Text = text end
end

local function isAway(mi: any): boolean
	return type(mi) == "table" and mi.away == true
end

local function availableCount(p: any): (number, number)
	local n, m = 0, 0
	for _, mi in (p.memberInfo or {}) :: { any } do
		m += 1
		if not isAway(mi) then n += 1 end
	end
	return n, m
end

local function statusText(mi: any): (string, boolean)
	-- returns text, showDispatchIcon
	if mi.awayReason == "dungeon" then return TXT_DUNGEON, false end
	if isAway(mi) then
		local n = tonumber(mi.dispatchLeft)
		return (if n then `Back in {math.floor(n)} battles` else ""), true
	end
	return TXT_READY, false
end

-- Emblem: party art when it exists, else a navy tile with a bronze border and the party number
-- (same look as the Loadout PARTIES tab).
local function makeEmblem(parent: Instance, p: any, index: number, size: number)
	local f = Instance.new("Frame")
	f.Name = "Emblem"
	f.Size = UDim2.fromOffset(size, size)
	f.Position = UDim2.fromOffset(6, 6)
	f.BackgroundColor3 = Color3.fromRGB(20, 28, 48)
	f.BorderSizePixel = 0
	corner(f, 6)
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(176, 128, 72)
	s.Thickness = 1.5
	s.Parent = f
	local art = if PartyArtData and PartyArtData.Resolve then PartyArtData.Resolve("emblem", p.emblem) else nil
	if type(art) == "table" and art.image then
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(1, 1)
		img.ScaleType = Enum.ScaleType.Fit
		img.Image = art.image
		img.ZIndex = 3
		img.Parent = f
	else
		local l = makeText(f, tostring(index), math.floor(size * 0.45), Color3.fromRGB(205, 160, 95), true)
		l.Size = UDim2.fromScale(1, 1)
		l.TextXAlignment = Enum.TextXAlignment.Center
		l.ZIndex = 3
	end
	f.ZIndex = 2
	f.Parent = parent
end

local function makeBar(parent: Instance, y: number, w: number, cur: any, max: any, color: Color3)
	local bg = Instance.new("Frame")
	bg.Name = "Bar"
	bg.Size = UDim2.fromOffset(w, 3)
	bg.Position = UDim2.fromOffset(0, y)
	bg.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	bg.BorderSizePixel = 0
	bg.ZIndex = 3
	local c, m = tonumber(cur) or 0, tonumber(max) or 0
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(if m > 0 then math.clamp(c / m, 0, 1) else 0, 1)
	fill.ZIndex = 4
	fill.Parent = bg
	bg.Parent = parent
end

local function makeTile(parent: Instance, mi: any, x: number, t: number)
	local tile = Instance.new("Frame")
	tile.Name = "Unit_" .. tostring(mi.id)
	tile.BackgroundTransparency = 1
	tile.Position = UDim2.fromOffset(x, 6)
	tile.Size = UDim2.fromOffset(t, t + 30)
	tile.ZIndex = 2

	local face = Instance.new("Frame")
	face.Name = "Portrait"
	face.Size = UDim2.fromOffset(t, t)
	face.BackgroundColor3 = Theme.Colors.Player
	face.BackgroundTransparency = 0.2
	face.BorderSizePixel = 0
	face.ZIndex = 2
	corner(face, 4)
	local ini = makeText(face, string.sub(tostring(mi.name or "?"), 1, 2), Theme.Text.Small(), Theme.Colors.TextPrimary, true)
	ini.Size = UDim2.fromScale(1, 1)
	ini.TextXAlignment = Enum.TextXAlignment.Center
	ini.ZIndex = 3
	if UIComponents and UIComponents.ApplyPortrait and mi.portraitAssetId then
		pcall(UIComponents.ApplyPortrait, face, mi.portraitAssetId, ini)
	end
	local lv = `Lv.{tostring(mi.unitLevel or "?")}` -- Units screen badge format
	local badge = makeText(face, lv, math.max(10, Theme.Text.Tiny()), Theme.Colors.TextPrimary)
	badge.Font = Theme.Font.Mono
	badge.BackgroundColor3 = Color3.new(0, 0, 0)
	badge.BackgroundTransparency = 0.3
	badge.TextTruncate = Enum.TextTruncate.None
	badge.Size = UDim2.fromOffset(Theme.BadgeFitW and Theme.BadgeFitW(lv, Theme.Font.Mono, 26) or 30, math.max(10, Theme.Text.Tiny()) + 3)
	badge.ZIndex = 5
	if isAway(mi) then
		local dim = Instance.new("Frame")
		dim.Name = "Dim"
		dim.Size = UDim2.fromScale(1, 1)
		dim.BackgroundColor3 = Color3.new(0, 0, 0)
		dim.BackgroundTransparency = 0.45
		dim.BorderSizePixel = 0
		dim.ZIndex = 4
		corner(dim, 4)
		dim.Parent = face
	end
	face.Parent = tile

	makeBar(tile, t + 2, t, mi.hp, mi.maxHp, Theme.Colors.HP)
	makeBar(tile, t + 6, t, mi.mp, mi.maxMp, Theme.Colors.MP)

	local text, showIcon = statusText(mi)
	local iconW = 0
	if showIcon and Theme.GetStatusIcon then
		local id = Theme.GetStatusIcon("Dispatch")
		if type(id) == "string" then
			local ic = Instance.new("ImageLabel")
			ic.Name = "DispatchIcon"
			ic.BackgroundTransparency = 1
			ic.Image = id
			ic.ScaleType = Enum.ScaleType.Fit
			ic.Size = UDim2.fromOffset(12, 12)
			ic.Position = UDim2.fromOffset(0, t + 12)
			ic.ZIndex = 3
			ic.Parent = tile
			iconW = 14
		end
	end
	if text ~= "" then
		local st = makeText(tile, text, math.max(9, Theme.Text.Tiny()),
			if text == TXT_READY then Theme.Colors.Success or Theme.Colors.TextPrimary else Theme.Colors.TextSecondary)
		st.Name = "Status"
		st.TextWrapped = true
		st.TextTruncate = Enum.TextTruncate.None
		st.TextScaled = true
		local cap = Instance.new("UITextSizeConstraint")
		cap.MaxTextSize = math.max(9, Theme.Text.Tiny())
		cap.MinTextSize = 7
		cap.Parent = st
		st.TextYAlignment = Enum.TextYAlignment.Top
		st.Position = UDim2.fromOffset(iconW, t + 10)
		st.Size = UDim2.fromOffset(t - iconW, 20)
		st.ZIndex = 3
	end
	tile.Parent = parent
end

--------------------------------------------------
-- DATA
--------------------------------------------------

local function fetch()
	fetchToken += 1
	local my = fetchToken
	task.spawn(function()
		if not GuildEvents or not GuildEvents.GetParties then return end
		local ok, res = pcall(function() return GuildEvents.GetParties:InvokeServer() end)
		if my ~= fetchToken or not isOpen then return end
		if ok and type(res) == "table" and res.ok then
			data = res
			if screen then screen.SetStatus("") end
		elseif ok and type(res) == "table" and type(res.error) == "string" and screen then
			screen.SetStatus(res.error, true) -- server text, as in the Loadout PARTIES tab
		end
		render()
	end)
end

local function selectedId(st: State): string?
	return st.partyId or (data and data.sortiePartyId) or nil
end

--------------------------------------------------
-- RENDER
--------------------------------------------------

local function tileSize(): number
	local w = if screen and screen.Main then screen.Main.AbsoluteSize.X else 700
	local free = w - LEFT_W - 16 - (MAX_TILES - 1) * GAP
	return math.clamp(math.floor(free / MAX_TILES), 40, 64)
end

local function renderList(st: State)
	local main = screen.Main
	local footH = 36
	local sc = Instance.new("ScrollingFrame")
	sc.Name = "Grid" -- GuildScreen.Clear keeps the scroll position for "Grid"
	sc.Size = UDim2.new(1, 0, 1, -footH)
	sc.BackgroundTransparency = 1
	sc.BorderSizePixel = 0
	sc.ScrollBarThickness = 4
	sc.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sc.CanvasSize = UDim2.new()
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 4)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 2)
	pad.Parent = sc
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = sc

	local title = makeText(sc, TXT_TITLE, Theme.Text.Heading(), Theme.Colors.TextGold, true)
	title.Size = UDim2.new(1, 0, 0, Theme.Text.Heading() + 6)
	title.LayoutOrder = 0

	local t = tileSize()
	local sel = selectedId(st)
	for i, p in ((data and data.parties) or {}) :: { any } do
		local n, m = availableCount(p)
		local usable = n > 0
		local row = Instance.new("TextButton")
		row.Name = "Party_" .. tostring(p.id)
		row.Text = ""
		row.AutoButtonColor = false
		row.BackgroundColor3 = Theme.Colors.PanelRaised
		row.BackgroundTransparency = if p.id == sel then 0.05 else 0.45
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, -4, 0, math.max(GuildScreen.ROW_H, t + 42))
		row.LayoutOrder = i
		corner(row, 6)
		if p.id == sel then
			local s = Instance.new("UIStroke")
			s.Color = Theme.Colors.TextGold
			s.Thickness = 2
			s.Parent = row
		end
		makeEmblem(row, p, i, 40)
		local nm = makeText(row, tostring(p.name or ""), Theme.Text.Body(), Theme.Colors.TextGold, true)
		nm.Position = UDim2.fromOffset(6, 50)
		nm.Size = UDim2.fromOffset(LEFT_W - 10, 18)
		nm.ZIndex = 2
		local cnt = makeText(row, `{n}/{m} available`, Theme.Text.Small(),
			if usable then Theme.Colors.TextPrimary else Theme.Colors.TextSecondary)
		cnt.Position = UDim2.fromOffset(6, 68)
		cnt.Size = UDim2.fromOffset(LEFT_W - 10, 16)
		cnt.ZIndex = 2
		local k = 0
		for _, mi in (p.memberInfo or {}) :: { any } do
			k += 1
			if k > MAX_TILES then break end
			makeTile(row, mi, LEFT_W + (k - 1) * (t + GAP), t)
		end
		if not usable then
			row.BackgroundTransparency = 0.7
		end
		row.Parent = sc
		row.Activated:Connect(function()
			local c = ctx
			if not c or c.isBusy() or not usable or p.id == sel then return end
			c.onPick(p.id, tostring(p.name or ""))
			render()
		end)
	end
	sc.Parent = main

	-- Footer: info line + "Deploying {n} units" (available members of the chosen party, capped at
	-- the quest's deploy limit).
	local foot = Instance.new("Frame")
	foot.Name = "Footer"
	foot.BackgroundTransparency = 1
	foot.Position = UDim2.new(0, 4, 1, -footH)
	foot.Size = UDim2.new(1, -8, 0, footH)
	local info = makeText(foot, TXT_INFO, Theme.Text.Small(), Theme.Colors.TextSecondary)
	info.Size = UDim2.new(1, 0, 0, 16)
	local deploy = 0
	for _, p in ((data and data.parties) or {}) :: { any } do
		if p.id == sel then deploy = (availableCount(p)) end
	end
	local cap = tonumber(st.quest and st.quest.playerSlots)
	if cap then deploy = math.min(deploy, cap) end
	if sel and deploy > 0 then
		local d = makeText(foot, `Deploying {deploy} units`, Theme.Text.Body(), Theme.Colors.TextPrimary, true)
		d.Position = UDim2.fromOffset(0, 17)
		d.Size = UDim2.new(1, 0, 0, 18)
	end
	foot.Parent = main
end

local function embarkText(st: State, idx: number): string
	if not st.locked then return TXT_EMBARK end
	if st.departPending then return TXT_DEPARTING end
	local lines = if ctx then ctx.embarkLines else {}
	local line = lines[((idx - 1) % math.max(1, #lines)) + 1]
	return if line then line .. "..." else TXT_DEPARTING
end

local function renderButtons(st: State)
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
	Theme.MakeBarButton(row, TXT_OPEN, "Secondary", function()
		local c = ctx
		if not c or c.isBusy() then return end
		c.onOpenParties()
	end, { name = "Btn_OpenParties", minHeight = GuildScreen.ROW_H, layoutOrder = 1 })
	local embarkBtn = Theme.MakeBarButton(row, embarkText(st, 1), if st.departPending then "Disabled" else "Primary", function()
		local c = ctx
		if not c or c.isBusy() then return end
		local now = c.getState()
		if now and now.departPending then return end -- already deferred: departs once on MapBuildComplete
		c.onEmbark()
	end, { name = "Btn_Embark", minHeight = GuildScreen.ROW_H, layoutOrder = 2 })
	local back = Theme.MakeIconButton(nil, "Back", function()
		local c = ctx
		if c then c.onBack() end
	end, { name = "Btn_BACK", size = UDim2.fromOffset(GuildScreen.ROW_H, GuildScreen.ROW_H) })
	back.LayoutOrder = 99
	back.Parent = row
	row.Parent = screen.Buttons

	cycleToken += 1
	if st.locked and not st.departPending then
		local myTok = cycleToken
		task.spawn(function()
			local idx = 1
			while myTok == cycleToken and isOpen and embarkBtn and embarkBtn.Parent do
				local now = if ctx then ctx.getState() else nil
				if not now or not now.locked then break end
				setLabel(embarkBtn, embarkText(now, idx))
				idx += 1
				task.wait(CYCLE_SECONDS)
			end
		end)
	end
end

local function applyCurrencies()
	if not screen or curGold == nil or not screen.SetCurrencies then return end
	local okS, CurrencyStrip = pcall(function()
		local m = uiFolder:FindFirstChild("CurrencyStrip")
		return if m then (require :: any)(m) else nil
	end)
	local wc = if okS and CurrencyStrip and CurrencyStrip.WithCommas then CurrencyStrip.WithCommas
		else function(n: any): string return tostring(n) end
	local res = curRes or {}
	screen.SetCurrencies({
		{ "Gold", wc(curGold) },
		{ "Mercury", wc(res.mercury or 0) },
		{ "Crystal", wc(res.crystals or 0) },
		{ "Sulfur", wc(res.sulfur or 0) },
	}, { Crystal = true, Sulfur = true }) -- same keys / rows as the guild base header
end

render = function()
	local c = ctx
	if not c or not screen or not isOpen then return end
	screen.Clear("Party")
	local st = c.getState()
	if not st or type(st.quest) ~= "table" then return end
	renderList(st)
	renderButtons(st)
end

--------------------------------------------------
-- PUBLIC (same shape as the other guild screens)
--------------------------------------------------

function QuestPartyView.Init(c: Context)
	ctx = c
end

function QuestPartyView.IsOpen(): boolean
	return isOpen
end

function QuestPartyView.GetGui(): ScreenGui?
	return if isOpen and screen then screen.Gui else nil
end

function QuestPartyView.Open()
	local c = ctx
	if not c then
		warn("[QuestPartyView] Open called before Init")
		return
	end
	if not screen then
		screen = GuildScreen.Create({ name = "QuestPartyView", title = "QUEST BOARD", parent = c.parent,
			fullMain = true, crest = Theme.GuildIcons.AdventurersGuild })
		screen.SetButtonRows(1)
		screen.Main:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if isOpen then render() end
		end)
	end
	if not isOpen then
		isOpen = true
		screen.SetStatus("")
		screen.Show()
		applyCurrencies()
	end
	render()
	fetch()
end

-- Re-render with the current state (map ready, embark deferred); re-fetches the party list.
function QuestPartyView.Refresh()
	if not isOpen then return end
	render()
	fetch()
end

function QuestPartyView.Hide()
	if not isOpen then return end
	isOpen = false
	cycleToken += 1
	fetchToken += 1
	if screen then screen.ClosePrompt(); screen.Hide() end
end

function QuestPartyView.SetGold(text: string)
	if screen then screen.SetGold(text) end
end

function QuestPartyView.SetCurrencies(gold: number, res: any)
	curGold = gold
	curRes = res
	if isOpen then applyCurrencies() end
end

function QuestPartyView.SetStatus(text: string, isError: boolean?)
	if screen then screen.SetStatus(text, isError) end
end

return table.freeze(QuestPartyView)
