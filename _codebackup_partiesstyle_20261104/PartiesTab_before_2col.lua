--!strict
-- PartiesTab.lua
-- CTRBLXAI | Loadout screen — PARTIES tab (USER DECISION 2026-11-04, Designer proposal
-- artifacts/parties_tab_design_options_20261104.md, approved as written incl. all text).
-- Its own module like the OUTFIT tab: LoadoutScreen only hosts the panel (full width,
-- unit header hidden) and calls Render / Unmount. Presentation only (ARC-001): every
-- change is a server request; the server validates, filters text and saves.
--
-- Layout
--   desktop: LEFT "My Parties x/5" list + CREATE PARTY | MIDDLE header (emblem, name, motto,
--            "..." menu, background) + leader portrait + 3x2 grid | RIGHT Party Details + Doctrines
--   phone  : LEFT emblem-only column + "+" | MIDDLE same | details slide in with the "i" button
-- Portraits keep the Loadout style: level badge top-left, doctrine icon top-right, name in two
-- rows at the bottom. Units on dispatch are greyed. Leader (slot 1) is display only.
-- Pick mode (opened from the Sortie): each party shows Select / Deploying.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local CTRBLXAI = ReplicatedStorage:WaitForChild("CTRBLXAI", 10) :: Instance
local UI = CTRBLXAI:WaitForChild("UI", 10) :: Instance
local Content = ReplicatedStorage:WaitForChild("Content", 10) :: Instance
local Theme = require(UI:WaitForChild("Theme", 10) :: ModuleScript) :: any
local UIComponents = require(UI:WaitForChild("UIComponents", 10) :: ModuleScript) :: any
local PartyArtData = require(Content:WaitForChild("PartyArtData", 10) :: ModuleScript) :: any
local GuildEvents = require(CTRBLXAI:WaitForChild("Remotes", 10):WaitForChild("GuildEvents", 10) :: ModuleScript) :: any
local BattleEvents = require(CTRBLXAI:WaitForChild("Remotes", 10):WaitForChild("BattleEvents", 10) :: ModuleScript) :: any

local PartiesTab = {}

local MAX_PARTIES = 5
local PHONE_W = 900 -- below this width the phone layout is used
local RETRY_DELAY = 0.35
local PORTRAIT_MAX = 110 -- px, largest side of a member portrait (leader is 1.6x)

local _main: GuiObject? = nil
local _state: any = nil
local _selectedId: string? = nil
local _detailsOpen = false
local _overlay: GuiObject? = nil
local _token = 0
local _pick: { active: boolean, onPick: ((id: string, name: string) -> ())?, onDone: (() -> ())? } = { active = false }
local _onViewLoadout: ((unitId: string) -> ())? = nil

--------------------------------------------------
-- HELPERS (properties before Parent, NET-004)
--------------------------------------------------

local function label(parent: Instance, text: string, props: any?): TextLabel
	local p = props or {}
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Size = p.size or UDim2.new(1, 0, 0, 16)
	l.Position = p.position or UDim2.new()
	l.Font = if p.bold then Theme.Font.PrimaryBold else Theme.Font.Primary
	l.TextSize = p.textSize or Theme.Text.Small()
	l.TextColor3 = p.color or Theme.Colors.TextPrimary
	l.TextXAlignment = p.align or Enum.TextXAlignment.Left
	l.TextYAlignment = p.alignY or Enum.TextYAlignment.Center
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.TextWrapped = p.wrap == true
	l.ZIndex = p.z or 2
	l.LayoutOrder = p.order or 0
	l.Text = text
	l.Parent = parent
	return l
end

local function frame(parent: Instance, name: string, size: UDim2, pos: UDim2?, bg: Color3?, transp: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = pos or UDim2.new()
	f.BackgroundColor3 = bg or Theme.Colors.PanelRaised
	f.BackgroundTransparency = transp or 1
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function corner(f: Instance, r: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 4)
	c.Parent = f
end

local function call(remote: any, ...: any): any?
	if not remote then return nil end
	local args = table.pack(...)
	local ok, res = pcall(function() return remote:InvokeServer(table.unpack(args, 1, args.n)) end)
	if not ok then
		warn("[PartiesTab] remote failed: " .. tostring(res))
		return nil
	end
	return res
end

local function findParty(id: string?): any?
	if not _state or not id then return nil end
	for _, p in _state.parties or {} do
		if p.id == id then return p end
	end
	return nil
end

local function fmtDate(t: any): string
	if type(t) ~= "number" or t <= 0 then return "-" end
	local d = os.date("*t", t) :: any
	local months = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
	return `{months[d.month]} {d.day}, {d.year}`
end

-- Emblem: user art when it exists, else a navy tile with a bronze border and the number.
local function emblem(parent: Instance, party: any, index: number, size: number, pos: UDim2?): Frame
	local f = frame(parent, "Emblem", UDim2.fromOffset(size, size), pos, Color3.fromRGB(20, 28, 48), 0)
	corner(f, 6)
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(176, 128, 72)
	s.Thickness = 1.5
	s.Parent = f
	local art = PartyArtData.Resolve("emblem", party and party.emblem)
	if art then
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(1, 1)
		img.ScaleType = Enum.ScaleType.Fit
		img.Image = art.image
		img.ZIndex = 3
		img.Parent = f
	else
		label(f, tostring(index), { size = UDim2.fromScale(1, 1), bold = true, align = Enum.TextXAlignment.Center,
			textSize = math.floor(size * 0.45), color = Color3.fromRGB(205, 160, 95), z = 3 })
	end
	return f
end

local render: () -> ()

local function refresh()
	_token += 1
	local myToken = _token
	local res = call(GuildEvents.GetParties)
	if myToken ~= _token then return end
	if res and res.ok then
		_state = res
	elseif res and res.error == "Too fast — try again" then
		task.delay(RETRY_DELAY, function()
			if myToken == _token then refresh() end
		end)
		return
	end
	render()
end

local function closeOverlay()
	if _overlay then _overlay:Destroy() end
	_overlay = nil
end

local function setStatus(text: string, isError: boolean?)
	local main = _main
	if not main then return end
	local s = main:FindFirstChild("PartyStatus") :: TextLabel?
	if s then
		s.Text = text
		s.TextColor3 = if isError then Theme.Colors.Danger else Theme.Colors.TextSecondary
	end
end

-- Small modal panel on top of the tab (pickers, menus, delete prompt).
local function openOverlay(title: string, width: number, height: number): Frame?
	local main = _main
	if not main then return nil end
	closeOverlay()
	local back = Instance.new("TextButton")
	back.Name = "PartyOverlay"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Theme.Colors.Overlay
	back.BackgroundTransparency = 0.45
	back.Text = ""
	back.AutoButtonColor = false
	back.ZIndex = 20
	back.Parent = main
	back.Activated:Connect(closeOverlay)
	_overlay = back
	local box = Theme.MakePanel("Box", UDim2.fromOffset(width, height), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), nil)
	box.ZIndex = 21
	box.Active = true
	box.Parent = back
	label(box, title, { size = UDim2.new(1, -16, 0, 22), position = UDim2.fromOffset(8, 6), bold = true,
		color = Theme.Colors.TextGold, z = 22 })
	return box
end

-- Themed buttons (user 2026-11-04: use the game's usual buttons, not flat boxes).
-- "...", "i" and "+" use the square icon art; everything else the 9-slice bar button.
local ICON_FOR = { ["..."] = "Options", i = "Help", ["+"] = "Plus" }
local function textButton(parent: Instance, text: string, size: UDim2, pos: UDim2?, onTap: (() -> ())?, z: number?): GuiButton
	local icon = ICON_FOR[text]
	local b: any
	if icon then
		b = Theme.MakeIconButton(nil, icon, onTap, { size = size, position = pos or UDim2.new(), disabled = onTap == nil })
	else
		b = Theme.MakeBarButton(nil, text, if onTap then "Secondary" else "Disabled", onTap,
			{ size = size, position = pos or UDim2.new(), autoWidth = false, minHeight = 28 })
	end
	b.ZIndex = z or 2
	for _, d in b:GetDescendants() do
		if d:IsA("GuiObject") then d.ZIndex = (z or 2) + 1 end
	end
	b.Parent = parent
	return b
end

-- Bar-button look by state: "Secondary" normal, "Primary" picked / deploying (bright, bronze).
local function setBarStyle(b: any, style: string)
	if not (b:IsA("ImageButton") and Theme.BarAssets[style]) then return end
	b.Image = Theme.BarAssets[style]
	-- Undo / apply the Disabled fade too (MakeBarButton fades image + label + outline).
	local faded = style == "Disabled"
	b.ImageTransparency = if faded then 0.5 else 0
	for _, d in b:GetDescendants() do
		if d:IsA("TextLabel") then
			d.TextTransparency = if faded then 0.5 else 0
			d.TextStrokeTransparency = if faded then 0.5 else 0
		end
	end
end
local function labelOf(b: any): TextLabel?
	return b:FindFirstChildWhichIsA("TextLabel", true)
end

-- Ornate panel frame (Theme 9-slice) with inner padding, like every other loadout panel.
local function panelFrame(parent: Instance, name: string, size: UDim2, pos: UDim2?, z: number?, padPx: number?): Frame
	local f = Theme.MakePanel(name, size, pos or UDim2.new(), nil, nil)
	f.ZIndex = z or 1
	local pd = Instance.new("UIPadding")
	local v = UDim.new(0, padPx or 10)
	pd.PaddingTop, pd.PaddingBottom, pd.PaddingLeft, pd.PaddingRight = v, v, v, v
	pd.Parent = f
	f.Parent = parent
	return f
end

--------------------------------------------------
-- ACTIONS
--------------------------------------------------

local function doAction(cmd: any, okText: string?)
	local res = call(GuildEvents.PartyAction, cmd)
	if res and res.ok then
		if res.id then _selectedId = res.id end
		if okText then setStatus(okText) end
	elseif res then
		setStatus(tostring(res.error or ""), true)
	end
	refresh()
end

local function promptDelete(party: any)
	local box = openOverlay(`Delete {party.name}?`, 300, 120)
	if not box then return end
	label(box, "Its units stay in your guild.", { size = UDim2.new(1, -16, 0, 20), position = UDim2.fromOffset(8, 32), z = 22,
		color = Theme.Colors.TextSecondary })
	textButton(box, "Delete", UDim2.fromOffset(120, 32), UDim2.new(0, 16, 1, -44), function()
		closeOverlay()
		doAction({ action = "Delete", id = party.id })
		_selectedId = nil
	end, 22)
	textButton(box, "Cancel", UDim2.fromOffset(120, 32), UDim2.new(1, -136, 1, -44), closeOverlay, 22)
end

local function openArtPicker(party: any, kind: string)
	local order = if kind == "emblem" then PartyArtData.EmblemOrder else PartyArtData.BackgroundOrder
	local map = if kind == "emblem" then PartyArtData.Emblems else PartyArtData.Backgrounds
	local box = openOverlay(if kind == "emblem" then "Choose emblem" else "Choose background", 360, 260)
	if not box then return end
	local grid = Instance.new("ScrollingFrame")
	grid.Size = UDim2.new(1, -16, 1, -80)
	grid.Position = UDim2.fromOffset(8, 32)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 4
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.ZIndex = 22
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = if kind == "emblem" then UDim2.fromOffset(64, 64) else UDim2.fromOffset(104, 58)
	gl.CellPadding = UDim2.fromOffset(6, 6)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = grid
	grid.Parent = box
	for i, key in order do
		local art = map[key]
		if art then
			local b = Instance.new("ImageButton")
			b.BackgroundColor3 = Color3.fromRGB(20, 28, 48)
			b.BorderSizePixel = 0
			b.Image = art.image
			b.ScaleType = if kind == "emblem" then Enum.ScaleType.Fit else Enum.ScaleType.Crop
			b.LayoutOrder = i
			b.ZIndex = 23
			corner(b, 4)
			if (party[kind] or order[1]) == key then
				local s = Instance.new("UIStroke")
				s.Color = Theme.Colors.TextGold
				s.Thickness = 2
				s.Parent = b
			end
			b.Parent = grid
			b.Activated:Connect(function()
				closeOverlay()
				doAction({ action = "SetArt", id = party.id, field = kind, key = key })
			end)
		end
	end
	textButton(box, "Cancel", UDim2.fromOffset(120, 32), UDim2.new(1, -128, 1, -42), closeOverlay, 22)
end

local function openMoreMenu(party: any, canDelete: boolean, deleteReason: string?)
	local box = openOverlay(party.name, 240, 168)
	if not box then return end
	textButton(box, "Change emblem", UDim2.new(1, -16, 0, 34), UDim2.fromOffset(8, 34), function()
		openArtPicker(party, "emblem")
	end, 22)
	textButton(box, "Change background", UDim2.new(1, -16, 0, 34), UDim2.fromOffset(8, 74), function()
		openArtPicker(party, "background")
	end, 22)
	local del = textButton(box, "Delete party", UDim2.new(1, -16, 0, 34), UDim2.fromOffset(8, 114), function()
		if canDelete then
			promptDelete(party)
		else
			closeOverlay()
			setStatus(deleteReason or "", true)
		end
	end, 22)
	if not canDelete then
		setBarStyle(del, "Disabled")
		local l = labelOf(del)
		if l then l.TextTransparency = 0.5 end
	end
end

local function saveMembers(party: any, ids: { string })
	local res = call(GuildEvents.SetPartyMembers, party.id, ids)
	if res and not res.ok then setStatus(tostring(res.error or ""), true) end
	refresh()
end

local function openMemberMenu(party: any, index: number, mi: any)
	local box = openOverlay(mi.name, 240, 168)
	if not box then return end
	textButton(box, "View loadout", UDim2.new(1, -16, 0, 34), UDim2.fromOffset(8, 34), function()
		closeOverlay()
		if _onViewLoadout then _onViewLoadout(mi.id) end
	end, 22)
	if index > 1 then
		textButton(box, "Make leader", UDim2.new(1, -16, 0, 34), UDim2.fromOffset(8, 74), function()
			closeOverlay()
			local ids = table.clone(party.members)
			table.remove(ids, index)
			table.insert(ids, 1, mi.id)
			saveMembers(party, ids)
		end, 22)
	end
	textButton(box, "Remove", UDim2.new(1, -16, 0, 34), UDim2.fromOffset(8, if index > 1 then 114 else 74), function()
		closeOverlay()
		local ids = table.clone(party.members)
		table.remove(ids, index)
		saveMembers(party, ids)
	end, 22)
end

local function openAddUnits(party: any)
	local maxSize = (_state and _state.maxSize) or 7
	local picked: { [string]: boolean } = {}
	for _, uid in party.members do picked[uid] = true end
	local box = openOverlay("Add units", 340, 300)
	if not box then return end
	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(1, -16, 1, -84)
	list.Position = UDim2.fromOffset(8, 32)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ZIndex = 22
	local ll = Instance.new("UIListLayout")
	ll.Padding = UDim.new(0, 3)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = list
	list.Parent = box
	local order = table.clone(party.members)
	local function count(): number
		local n = 0
		for _ in picked do n += 1 end
		return n
	end
	for i, u in _state.roster or {} do
		local inParty = picked[u.id] == true
		local blocked = u.away and not inParty -- dispatched units can't be added
		local b = textButton(list, `{u.name}  Lv {u.unitLevel}`, UDim2.new(1, -6, 0, 28), nil, if blocked then nil else function() end, 23)
		b.LayoutOrder = i
		local function paint()
			if not blocked then setBarStyle(b, if picked[u.id] then "Primary" else "Secondary") end
		end
		paint()
		if not blocked then
			b.Activated:Connect(function()
				if picked[u.id] then
					picked[u.id] = nil
					for k, id in order do
						if id == u.id then table.remove(order, k) break end
					end
				elseif count() < maxSize then
					picked[u.id] = true
					table.insert(order, u.id)
				end
				paint()
			end)
		end
	end
	textButton(box, "Done", UDim2.fromOffset(120, 32), UDim2.new(0, 16, 1, -44), function()
		closeOverlay()
		saveMembers(party, order)
	end, 22)
	textButton(box, "Cancel", UDim2.fromOffset(120, 32), UDim2.new(1, -136, 1, -44), closeOverlay, 22)
end

-- In-place text edit (name / motto). Filtered on the server; the old text stays on refusal.
local function editBox(parent: Instance, text: string, placeholder: string, size: UDim2, pos: UDim2, textSize: number,
	bold: boolean, onCommit: (string) -> ()): TextBox
	local tb = Instance.new("TextBox")
	tb.Size = size
	tb.Position = pos
	tb.BackgroundColor3 = Theme.Colors.Surface
	tb.BackgroundTransparency = 0.4
	tb.BorderSizePixel = 0
	tb.ClearTextOnFocus = false
	tb.Font = if bold then Theme.Font.PrimaryBold else Theme.Font.Primary
	tb.TextSize = textSize
	tb.TextColor3 = Theme.Colors.TextPrimary
	tb.PlaceholderText = placeholder
	tb.Text = text
	tb.TextXAlignment = Enum.TextXAlignment.Left
	tb.TextTruncate = Enum.TextTruncate.AtEnd
	tb.ZIndex = 4
	corner(tb, 4)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 6)
	p.Parent = tb
	tb.Parent = parent
	tb.FocusLost:Connect(function()
		if tb.Text ~= text then onCommit(tb.Text) end
	end)
	tb:SetAttribute("Original", text)
	return tb
end

--------------------------------------------------
-- PORTRAIT (Loadout style)
--------------------------------------------------

local function portrait(parent: Instance, mi: any?, size: UDim2, pos: UDim2, isLeader: boolean, onTap: (() -> ())?)
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = pos
	-- Fixed shape so portraits don't stretch to fill the screen (user 2026-11-04):
	-- leader 3:4, others square, never bigger than PORTRAIT_MAX.
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = if isLeader then 0.75 else 1
	ar.Parent = b
	-- (No separate size cap: the layout below already sizes every tile within PORTRAIT_MAX.)
	b.BackgroundColor3 = if mi then Theme.Colors.Player else Theme.Colors.EmptySlot
	b.BackgroundTransparency = if mi then 0.2 else 0.5
	b.BorderSizePixel = 0
	b.Text = ""
	b.AutoButtonColor = onTap ~= nil
	b.ZIndex = 2
	corner(b, 5)
	b.Parent = parent
	if onTap then b.Activated:Connect(onTap) end
	if isLeader then
		local s = Instance.new("UIStroke")
		s.Color = Theme.Colors.TextGold
		s.Thickness = 2
		s.Parent = b
	end
	if not mi then
		label(b, "+", { size = UDim2.fromScale(1, 1), align = Enum.TextXAlignment.Center, color = Theme.Colors.TextDisabled,
			textSize = Theme.Text.Title(), z = 3 })
		return
	end
	local initials = label(b, string.sub(mi.name or "?", 1, 2), { size = UDim2.fromScale(1, 0.7), bold = true,
		align = Enum.TextXAlignment.Center, textSize = Theme.Text.Title(), z = 3 })
	if mi.portraitAssetId and UIComponents.ApplyPortrait(b, mi.portraitAssetId) then initials.Text = "" end
	-- Level badge, top-left
	local lv = label(b, `Lv {mi.unitLevel or 1}`, { size = UDim2.fromOffset(40, 14), position = UDim2.fromOffset(2, 2),
		textSize = Theme.Text.Tiny(), z = 5 })
	lv.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	lv.BackgroundTransparency = 0.3
	lv.Font = Theme.Font.Mono
	-- Doctrine icon, top-right
	if mi.doctrineIcon then
		local ic = Instance.new("ImageLabel")
		ic.BackgroundTransparency = 1
		ic.Size = UDim2.fromOffset(18, 18)
		ic.Position = UDim2.new(1, -20, 0, 2)
		ic.Image = mi.doctrineIcon
		ic.ZIndex = 5
		ic.Parent = b
	end
	if isLeader then
		local banner = label(b, "LEADER", { size = UDim2.new(1, -48, 0, 16), position = UDim2.fromOffset(44, 2), bold = true,
			textSize = Theme.Text.Tiny(), color = Theme.Colors.TextGold, z = 5 })
		banner.TextXAlignment = Enum.TextXAlignment.Left
	end
	-- Name in two rows at the bottom
	local nameBand = frame(b, "NameBand", UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 1, -30), Color3.fromRGB(0, 0, 0), 0.35)
	nameBand.ZIndex = 4
	local nl = label(nameBand, mi.name or "?", { size = UDim2.new(1, -6, 1, 0), position = UDim2.fromOffset(3, 0),
		textSize = Theme.Text.Tiny(), bold = true, wrap = true, z = 5 })
	nl.TextTruncate = Enum.TextTruncate.AtEnd
	nl.TextYAlignment = Enum.TextYAlignment.Center
	-- Dispatch: greyed
	if mi.away then
		local grey = frame(b, "Away", UDim2.fromScale(1, 1), nil, Color3.fromRGB(0, 0, 0), 0.45)
		grey.ZIndex = 6
		-- Dispatch icon only (no new text): the shared status icon when Theme has one.
		local icon = Theme.GetStatusIcon and Theme.GetStatusIcon("Dispatch") or nil
		if type(icon) == "string" and icon ~= "" then
			local ic = Instance.new("ImageLabel")
			ic.BackgroundTransparency = 1
			ic.Size = UDim2.fromOffset(22, 22)
			ic.Position = UDim2.new(0.5, -11, 0.4, 0)
			ic.Image = icon
			ic.ZIndex = 7
			ic.Parent = grey
		end
	end
end

--------------------------------------------------
-- RENDER
--------------------------------------------------

render = function()
	local main = _main
	if not main then return end
	closeOverlay()
	for _, c in main:GetChildren() do
		if not c:IsA("UIPadding") and not c:IsA("UICorner") then c:Destroy() end
	end
	local st = _state
	if not st then
		label(main, "", { size = UDim2.new(1, 0, 0, 16) })
		return
	end
	local parties = st.parties or {}
	if not findParty(_selectedId) then _selectedId = parties[1] and parties[1].id or nil end
	local party = findParty(_selectedId)
	local maxParties = st.maxParties or MAX_PARTIES
	local phone = main.AbsoluteSize.X < PHONE_W
	-- User 2026-11-04: the full list (name + mini portraits) shows on phone too.
	local leftW = if phone then 204 else 230
	local rightW = if phone then 0 else 240

	local status = label(main, "", { size = UDim2.new(1, -leftW - 8, 0, 14), position = UDim2.new(0, leftW + 8, 1, -14),
		textSize = Theme.Text.Tiny(), color = Theme.Colors.TextSecondary, z = 3 })
	status.Name = "PartyStatus"

	-- LEFT: party list
	local left = Instance.new("ScrollingFrame")
	left.Name = "PartyList"
	left.Size = UDim2.new(0, leftW, 1, 0)
	left.BackgroundTransparency = 1
	left.BorderSizePixel = 0
	left.ScrollBarThickness = 3
	left.AutomaticCanvasSize = Enum.AutomaticSize.Y
	left.CanvasSize = UDim2.new()
	local ll = Instance.new("UIListLayout")
	ll.Padding = UDim.new(0, 4)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = left
	left.Parent = main
	do
		local hdr = label(left, `My Parties   {#parties}/{maxParties}`, { size = UDim2.new(1, 0, 0, 20), bold = true,
			color = Theme.Colors.TextGold, order = 0 })
		hdr.LayoutOrder = 0
	end
	for i, p in parties do
		local row = Instance.new("TextButton")
		row.Size = UDim2.new(1, -4, 0, if _pick.active then 108 else 62) -- 44 px Select (touch minimum)
		row.BackgroundColor3 = Theme.Colors.PanelRaised
		row.BackgroundTransparency = if p.id == _selectedId then 0.05 else 0.5
		row.BorderSizePixel = 0
		row.Text = ""
		row.LayoutOrder = i
		corner(row, 5)
		if p.id == _selectedId then
			local s = Instance.new("UIStroke")
			s.Color = Theme.Colors.TextGold
			s.Thickness = 1.5
			s.Parent = row
		end
		row.Parent = left
		row.Activated:Connect(function()
			_selectedId = p.id
			_detailsOpen = false
			render()
		end)
		local n = #(p.memberInfo or {})
		do
			emblem(row, p, i, 48, UDim2.fromOffset(6, 7))
			label(row, p.name, { size = UDim2.new(1, -64, 0, 18), position = UDim2.fromOffset(60, 6), bold = true, z = 3 })
			label(row, `{n}/7`, { size = UDim2.new(1, -64, 0, 14), position = UDim2.fromOffset(60, 24),
				textSize = Theme.Text.Tiny(), color = Theme.Colors.TextSecondary, z = 3 })
			for k, mi in p.memberInfo or {} do
				local face = frame(row, "Face", UDim2.fromOffset(18, 18), UDim2.fromOffset(60 + (k - 1) * 20, 40),
					Theme.Colors.Player, 0.3)
				face.ZIndex = 3
				corner(face, 3)
				if mi.portraitAssetId then UIComponents.ApplyPortrait(face, mi.portraitAssetId) end
			end
		end
		-- Sortie pick mode: Select / Deploying (phone: small strip under the emblem)
		if _pick.active then
			local isSel = st.sortiePartyId == p.id
			local usable = false
			for _, mi in p.memberInfo or {} do
				if not mi.away then usable = true break end
			end
			-- Own strip under the name + faces, so it covers nothing (Tester 2026-11-04).
			local pbSize = UDim2.new(1, -66, 0, 44)
			local pbPos = UDim2.fromOffset(60, 60)
			local pb = textButton(row, if isSel then "Deploying" else "Select", pbSize, pbPos,
				if (usable and not isSel) then function()
					BattleEvents.SelectSortieParty:FireServer(p.id)
					if _pick.onPick then _pick.onPick(p.id, p.name) end
					-- Approved: picking returns to the Sortie step.
					if _pick.onDone then _pick.onDone() end
				end else nil, 6)
			-- Deploying: bright bronze bar, not tappable (never the faded Disabled art).
			if isSel then
				setBarStyle(pb, "Primary")
				pb.Active = false
				local l = labelOf(pb)
				if l then l.TextTransparency = 0 end
			end
		end
	end
	local canCreate = #parties < maxParties
	local create = textButton(left, "CREATE PARTY", UDim2.new(1, -4, 0, 40), nil,
		if canCreate then function() doAction({ action = "Create" }) end else nil, 2)
	create.LayoutOrder = 100

	-- MIDDLE
	local mid = frame(main, "PartyMain", UDim2.new(1, -(leftW + 8 + (if rightW > 0 then rightW + 8 else 0)), 1, -16),
		UDim2.fromOffset(leftW + 8, 0))
	if not party then return end
	local idx = 1
	for i, p in parties do
		if p.id == party.id then idx = i end
	end
	local headH = if phone then 64 else 120
	-- Portrait block (leader + 3x2 grid): sized to fit; the header matches its width (user 2026-11-04).
	local GAP = 6
	local bodyH = math.max(80, mid.AbsoluteSize.Y - headH - 6)
	local bodyW = math.max(200, mid.AbsoluteSize.X)
	local byH = math.floor((bodyH - GAP) / 2)
	local byW = math.floor((bodyW - 3 * GAP - 0.75 * GAP) / 4.5)
	local tile = math.max(40, math.min(PORTRAIT_MAX, byH, byW))
	local leaderH = tile * 2 + GAP
	local leaderW = math.floor(leaderH * 0.75)
	local blockW = leaderW + GAP + 3 * tile + 2 * GAP
	local head = frame(mid, "Header", UDim2.fromOffset(blockW, headH), nil, Color3.fromRGB(16, 22, 38), 0)
	corner(head, 6)
	local bg = PartyArtData.Resolve("background", party.background)
	if bg then
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(1, 1)
		img.ScaleType = Enum.ScaleType.Crop
		img.Image = bg.image
		img.ImageTransparency = 0.35
		img.ZIndex = 2
		img.Parent = head
	end
	local eSize = headH - 12
	local em = emblem(head, party, idx, eSize, UDim2.fromOffset(6, 6))
	em.ZIndex = 3
	local emTap = Instance.new("TextButton")
	emTap.BackgroundTransparency = 1
	emTap.Size = UDim2.fromScale(1, 1)
	emTap.Text = ""
	emTap.ZIndex = 5
	emTap.Parent = em
	emTap.Activated:Connect(function() openArtPicker(party, "emblem") end)
	local tx = eSize + 14
	local nameH = if phone then 24 else 32
	local rightReserve = if phone then 104 else 56 -- "i" + "..." on phone, "..." on desktop
	editBox(head, party.name, "Party name", UDim2.new(1, -(tx + rightReserve), 0, nameH), UDim2.fromOffset(tx, 6),
		if phone then Theme.Text.Body() else Theme.Text.Title(), true, function(t)
			if (t:gsub("%s", "")) == "" then render() return end -- empty: keep the old name
			local res = call(GuildEvents.SetPartyName, party.id, t)
			if res and res.ok then setStatus("Party renamed") else setStatus(tostring(res and res.error or ""), true) end
			refresh()
		end)
	editBox(head, party.motto or "", "Add a motto", UDim2.new(1, -(tx + rightReserve), 0, if phone then 20 else 24),
		UDim2.fromOffset(tx, 6 + nameH + 4), Theme.Text.Small(), false, function(t)
			doAction({ action = "SetMotto", id = party.id, text = t })
		end)
	local isLast = #parties <= 1
	local isDeploying = st.sortiePartyId == party.id
	local reason = if isLast then "You need at least one party" elseif isDeploying then "This party is set to deploy" else nil
	local more = textButton(head, "...", UDim2.fromOffset(44, 44), UDim2.new(1, -48, 0, 6), function()
		openMoreMenu(party, reason == nil, reason)
	end, 12)
	more.ZIndex = 12
	if phone then
		local ib = textButton(head, "i", UDim2.fromOffset(44, 44), UDim2.new(1, -96, 0, 6), function()
			_detailsOpen = not _detailsOpen
			render()
		end, 12)
		ib.ZIndex = 12
	end

	-- Members: leader big on the left, 3x2 grid of the others
	local body = frame(mid, "Members", UDim2.new(1, 0, 1, -(headH + 6)), UDim2.fromOffset(0, headH + 6))
	local members = party.memberInfo or {}
	local function memberTap(i: number): (() -> ())
		return function()
			local mi = members[i]
			if mi then openMemberMenu(party, i, mi) else openAddUnits(party) end
		end
	end
	-- Leader on the left, then a 3x2 grid packed next to it (sizes worked out above).
	portrait(body, members[1], UDim2.fromOffset(leaderW, leaderH), UDim2.new(), true, memberTap(1))
	for k = 2, 7 do
		local col = (k - 2) % 3
		local rowI = (k - 2) // 3
		portrait(body, members[k], UDim2.fromOffset(tile, tile),
			UDim2.fromOffset(leaderW + GAP + col * (tile + GAP), rowI * (tile + GAP)), false, memberTap(k))
	end

	-- RIGHT: details (desktop always; phone when "i" is open)
	if rightW > 0 or _detailsOpen then
		local w = if rightW > 0 then rightW else 230
		local topY = if rightW > 0 then 0 else 56
		local right = panelFrame(main, "PartyDetails", UDim2.new(0, w, 1, -16 - topY), UDim2.new(1, -w, 0, topY), 10, 12)
		local rl = Instance.new("UIListLayout")
		rl.Padding = UDim.new(0, 4)
		rl.SortOrder = Enum.SortOrder.LayoutOrder
		rl.Parent = right
		label(right, "Party Details", { bold = true, color = Theme.Colors.TextGold, order = 1, z = 11 })
		local away = 0
		local docs: { [string]: number } = {}
		local docOrder: { string } = {}
		for _, mi in members do
			if mi.away then away += 1 end
			if mi.doctrineName then
				if not docs[mi.doctrineName] then table.insert(docOrder, mi.doctrineName) end
				docs[mi.doctrineName] = (docs[mi.doctrineName] or 0) + 1
			end
		end
		label(right, `Members   {#members}/7`, { order = 2, z = 11 })
		if away > 0 then label(right, `On dispatch   {away}`, { order = 3, z = 11 }) end
		-- User 2026-11-04: average level + races instead of the created/edited dates.
		local lvSum, races, raceOrder = 0, {} :: { [string]: number }, {} :: { string }
		for _, mi in members do
			lvSum += tonumber(mi.unitLevel) or 0
			local r = mi.race or "?"
			if not races[r] then table.insert(raceOrder, r) end
			races[r] = (races[r] or 0) + 1
		end
		local avg = if #members > 0 then math.floor(lvSum / #members + 0.5) else 0
		label(right, `Average level   {avg}`, { order = 4, z = 11 })
		label(right, "Races", { bold = true, color = Theme.Colors.TextGold, order = 10, z = 11 })
		for i, r in raceOrder do
			label(right, `{r} ×{races[r]}`, { order = 10 + i, z = 11 })
		end
		label(right, "Doctrines", { bold = true, color = Theme.Colors.TextGold, order = 30, z = 11 })
		for i, d in docOrder do
			label(right, `{d} ×{docs[d]}`, { order = 30 + i, z = 11 })
		end
	end
end

--------------------------------------------------
-- PUBLIC
--------------------------------------------------

-- opts: { pick = boolean, onPick = fn(id, name), onViewLoadout = fn(unitId) }
function PartiesTab.Configure(opts: any)
	_pick = { active = opts and opts.pick == true, onPick = opts and opts.onPick or nil, onDone = opts and opts.onDone or nil }
end

function PartiesTab.Render(main: GuiObject)
	_main = main
	render() -- draw cached state at once, then fetch fresh
	task.spawn(refresh)
end

function PartiesTab.SetViewLoadout(fn: (unitId: string) -> ())
	_onViewLoadout = fn
end

-- Pick mode ended (party chosen): leave the tab open but drop Select/Deploying.
function PartiesTab.EndPick()
	_pick = { active = false }
end

function PartiesTab.Unmount()
	_token += 1
	closeOverlay()
	_main = nil
	_detailsOpen = false
end

function PartiesTab.IsPickMode(): boolean
	return _pick.active
end

local _ = Players
return PartiesTab
