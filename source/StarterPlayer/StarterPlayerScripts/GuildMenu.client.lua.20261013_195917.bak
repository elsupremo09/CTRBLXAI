--!strict
-- GuildMenu.client.lua
-- CTRBLXAI | Slice 6 — TEMPORARY Guild menu (client screen)
--
-- game_flow id 23 "Town: first version": one button per building. Opens when the
-- server fires GuildEvents.GuildMenuOpened (before deployment and after a battle),
-- closes on GuildMenuClosed. Display + input only (AP-009 / ARC-001): every button
-- sends an id to the server and shows whatever the server answers. The client never
-- sends a price, cost or result (SEC-002).
--
-- Mobile-first: taps use .Activated only, sizes are Scale-based, lists use
-- UIListLayout, touch targets are >= 44 px tall. All client waits time out (LOAD-001).
-- UI text is ASCII only (project UI rule).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WAIT = 10

local CTRBLXAI = ReplicatedStorage:WaitForChild("CTRBLXAI", WAIT)
if not CTRBLXAI then warn("[GuildMenu] CTRBLXAI folder not found"); return end
local UIFolder = CTRBLXAI:WaitForChild("UI", WAIT)
local Remotes = CTRBLXAI:WaitForChild("Remotes", WAIT)
if not UIFolder or not Remotes then warn("[GuildMenu] UI/Remotes folder not found"); return end
local themeModule = UIFolder:WaitForChild("Theme", WAIT)
local guildModule = Remotes:WaitForChild("GuildEvents", WAIT)
local battleModule = Remotes:WaitForChild("BattleEvents", WAIT)
if not themeModule or not guildModule or not battleModule then
	warn("[GuildMenu] Theme / GuildEvents / BattleEvents module missing"); return
end

-- Modules found at runtime via WaitForChild; the editor cannot follow that path, so
-- require is called through `any` (editor-only; same module loads at runtime).
local Theme: any        = (require :: any)(themeModule)
local GuildEvents: any  = (require :: any)(guildModule)
local BattleEvents: any = (require :: any)(battleModule)
if not GuildEvents.GuildMenuOpened then
	warn("[GuildMenu] Guild remotes unavailable — menu disabled"); return
end

local player = Players.LocalPlayer :: Player
local playerGui = player:WaitForChild("PlayerGui", WAIT)
if not playerGui then warn("[GuildMenu] PlayerGui not found"); return end

--------------------------------------------------
-- CONSTANTS
--------------------------------------------------

local ROW_HEIGHT = 56      -- >= 44 px touch target with padding
local BUTTON_HEIGHT = 48
local BUILDINGS_DEV = { "GuildHall", "Tavern", "Merchant", "Blacksmith" }

--------------------------------------------------
-- STATE
--------------------------------------------------

local currentPhase = "PreBattle"
local currentPage = "Units"
local isBusy = false
local selectedMission: string? = nil
local selectedUnits: { [string]: boolean } = {}

--------------------------------------------------
-- UI CONSTRUCTION (one-time)
--------------------------------------------------

local function makeText(parent: Instance, text: string, size: number, color: Color3, bold: boolean?): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Font = bold and Theme.Font.PrimaryBold or Theme.Font.Primary
	lbl.TextSize = size
	lbl.TextColor3 = color
	lbl.TextWrapped = true
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Text = text
	lbl.Parent = parent
	return lbl
end

local function makeButton(parent: Instance, text: string, color: Color3, onTap: () -> (), enabled: boolean?): TextButton
	-- Loadout-screen look (2026-10-08 restyle): dark rounded button; the colour that used to
	-- fill the button is now its outline, so Hire/Buy/Sell/Up/Down keep their meaning.
	local isOn = enabled ~= false
	local btn = Instance.new("TextButton")
	btn.AutoButtonColor = isOn
	btn.Active = isOn
	btn.BackgroundColor3 = Theme.Colors.Surface
	btn.BackgroundTransparency = isOn and 0.1 or 0.5
	btn.BorderSizePixel = 0
	btn.Font = Theme.Font.PrimaryBold
	btn.TextSize = Theme.Text.Body()
	btn.TextColor3 = isOn and Theme.Colors.TextPrimary or Theme.Colors.TextDisabled
	btn.Text = text
	btn.TextWrapped = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius.md
	corner.Parent = btn
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Accent"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = isOn and color or Theme.Colors.Border
	stroke.Thickness = Theme.BorderThickness.Selected
	stroke.Transparency = isOn and 0 or 0.4
	stroke.Parent = btn
	btn.Parent = parent -- properties before Parent (NET-004)
	if isOn then
		btn.Activated:Connect(function() onTap() end) -- .Activated works for mouse, touch and gamepad
	end
	return btn
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GuildMenu"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = Theme.DisplayOrder.Modal -- below the Loadout screen (100)
screenGui.Enabled = false
screenGui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Root"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = Theme.FullScreen.BackgroundColor
root.BackgroundTransparency = Theme.FullScreen.BackgroundTransparency -- same opaque backdrop as the loadout
root.BorderSizePixel = 0
root.Parent = screenGui
if Theme.MakeScreenBorder then Theme.MakeScreenBorder(root) end

-- Gold-framed panel wrapper (the loadout screen's ornate 9-slice frame, Theme.MakePanel).
-- Same size/position the element had before; the element now fills the frame (styling only).
local function framePanel(name: string, size: UDim2, position: UDim2, padX: number, padY: number): ImageLabel
	local frame = Theme.MakePanel(name, size, position, nil, root)
	local framePad = Instance.new("UIPadding") -- one UIPadding per frame (Roblox honours only one)
	framePad.PaddingLeft = UDim.new(0, padX)
	framePad.PaddingRight = UDim.new(0, padX)
	framePad.PaddingTop = UDim.new(0, padY)
	framePad.PaddingBottom = UDim.new(0, padY)
	framePad.Parent = frame
	return frame
end

-- Header: title + balance
-- Wider side padding so the text clears the frame's corner ornaments.
local header = framePanel("Header", UDim2.new(0.96, 0, 0.12, 0), UDim2.fromScale(0.02, 0.02), 14, 4)

local titleLabel = makeText(header, "GUILD", Theme.Text.Title(), Theme.Colors.TextGold, true)
titleLabel.Size = UDim2.fromScale(0.4, 0.6)
titleLabel.Font = Theme.Font.Display

local phaseLabel = makeText(header, "", Theme.Text.Small(), Theme.Colors.TextSecondary)
phaseLabel.Size = UDim2.fromScale(0.6, 0.4)
phaseLabel.Position = UDim2.fromScale(0, 0.6)

local balanceLabel = makeText(header, "", Theme.Text.Body(), Theme.Colors.TextPrimary, true)
balanceLabel.Size = UDim2.fromScale(0.6, 1)
balanceLabel.Position = UDim2.fromScale(0.4, 0)
balanceLabel.TextXAlignment = Enum.TextXAlignment.Right

-- Left column: one button per building
local navFrame = framePanel("BuildingsFrame", UDim2.new(0.28, 0, 0.8, 0), UDim2.fromScale(0.02, 0.16), 10, 10)
local nav = Instance.new("ScrollingFrame")
nav.Name = "Buildings"
nav.Size = UDim2.fromScale(1, 1)
nav.Position = UDim2.fromScale(0, 0)
nav.BackgroundTransparency = 1
nav.BorderSizePixel = 0
nav.ScrollBarThickness = 4
nav.AutomaticCanvasSize = Enum.AutomaticSize.Y
nav.CanvasSize = UDim2.new()
nav.Parent = navFrame
local navLayout = Instance.new("UIListLayout")
navLayout.Padding = UDim.new(0, 6)
navLayout.SortOrder = Enum.SortOrder.LayoutOrder
navLayout.Parent = nav

-- Right: page content
local contentFrame = framePanel("ContentFrame", UDim2.new(0.66, 0, 0.72, 0), UDim2.fromScale(0.32, 0.16), 6, 6)
local content = Instance.new("ScrollingFrame")
content.Name = "Content"
content.Size = UDim2.fromScale(1, 1)
content.Position = UDim2.fromScale(0, 0)
content.BackgroundTransparency = 1 -- the gold frame supplies the panel background
content.BorderSizePixel = 0
content.ScrollBarThickness = 6
content.AutomaticCanvasSize = Enum.AutomaticSize.Y
content.CanvasSize = UDim2.new()
content.Parent = contentFrame
local contentPad = Instance.new("UIPadding")
contentPad.PaddingLeft = UDim.new(0, 8)
contentPad.PaddingRight = UDim.new(0, 8)
contentPad.PaddingTop = UDim.new(0, 8)
contentPad.PaddingBottom = UDim.new(0, 8)
contentPad.Parent = content
local contentLayout = Instance.new("UIListLayout")
contentLayout.Padding = UDim.new(0, 6)
contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
contentLayout.Parent = content

-- Bottom: status line (server answers / errors)
local statusLabel = makeText(root, "", Theme.Text.Small(), Theme.Colors.TextSecondary)
statusLabel.Size = UDim2.new(0.66, 0, 0.07, 0)
statusLabel.Position = UDim2.fromScale(0.32, 0.9)

local function setStatus(text: string, isError: boolean?)
	statusLabel.Text = text
	statusLabel.TextColor3 = isError and Theme.Colors.Danger or Theme.Colors.Success
end

--------------------------------------------------
-- CONTENT HELPERS
--------------------------------------------------

local rowOrder = 0

local function clearContent()
	for _, child in content:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	rowOrder = 0
end

local function addHeading(text: string)
	rowOrder += 1
	local lbl = makeText(content, text, Theme.Text.Heading(), Theme.Colors.TextGold, true)
	lbl.Size = UDim2.new(1, 0, 0, 30)
	lbl.LayoutOrder = rowOrder
end

local function addNote(text: string)
	rowOrder += 1
	local lbl = makeText(content, text, Theme.Text.Small(), Theme.Colors.TextSecondary)
	lbl.Size = UDim2.new(1, 0, 0, 0)
	lbl.AutomaticSize = Enum.AutomaticSize.Y
	lbl.LayoutOrder = rowOrder
end

-- style (2026-10-09): "Primary" | "Secondary" | "Tertiary" draws the bar art (Theme.MakeBarButton);
-- nil keeps the existing icon / text button. Merchant Buy and Sell use Primary.
type RowButton = { text: string, color: Color3, onTap: () -> (), enabled: boolean?, style: string? }

local function addRow(text: string, buttons: { RowButton }?, dim: boolean?): Frame
	rowOrder += 1
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundColor3 = Theme.Colors.PanelRaised
	row.BackgroundTransparency = dim and 0.6 or 0.2
	row.BorderSizePixel = 0
	row.LayoutOrder = rowOrder
	row.Parent = content
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius.md
	corner.Parent = row
	local rowStroke = Instance.new("UIStroke") -- loadout card edge
	rowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rowStroke.Color = Theme.Colors.Border
	rowStroke.Thickness = Theme.BorderThickness.Default
	rowStroke.Parent = row

	local count = buttons and #buttons or 0
	local btnShare = math.min(0.22 * count, 0.5)
	local lbl = makeText(row, text, Theme.Text.Small(), dim and Theme.Colors.TextDisabled or Theme.Colors.TextPrimary)
	lbl.Size = UDim2.new(1 - btnShare, -12, 1, 0)
	lbl.Position = UDim2.new(0, 8, 0, 0)

	if buttons then
		for i, b in buttons do
			local w = btnShare / count
			local iconKind = Theme.IconKindForText and Theme.IconKindForText(b.text)
			if b.style and Theme.MakeBarButton then
				Theme.MakeBarButton(row, b.text, if b.enabled == false then "Disabled" else b.style, b.onTap, {
					name = "Btn_" .. b.text,
					size = UDim2.new(w, -6, 0, BUTTON_HEIGHT - 4),
					position = UDim2.new(1 - btnShare + w * (i - 1), 0, 0.5, 0),
					anchor = Vector2.new(0, 0.5),
					autoWidth = false,
					minHeight = BUTTON_HEIGHT - 4,
				})
			elseif iconKind then
				-- Square icon art: same height, narrower; centred in its share of the row.
				Theme.MakeIconButton(row, iconKind, b.onTap, {
					name = "Btn_" .. b.text,
					size = UDim2.new(0, BUTTON_HEIGHT - 4, 0, BUTTON_HEIGHT - 4),
					position = UDim2.new(1 - btnShare + w * (i - 0.5), 0, 0.5, 0),
					anchor = Vector2.new(0.5, 0.5),
					disabled = (b.enabled == false),
				})
			else
				local btn = makeButton(row, b.text, b.color, b.onTap, b.enabled)
				btn.Size = UDim2.new(w, -6, 0, BUTTON_HEIGHT - 4)
				btn.AnchorPoint = Vector2.new(0, 0.5)
				btn.Position = UDim2.new(1 - btnShare + w * (i - 1), 0, 0.5, 0)
			end
		end
	end
	return row
end

local function matsText(mats: any): string
	if type(mats) ~= "table" then return "" end
	local parts = {}
	for t = 1, 5 do table.insert(parts, `T{t}:{mats[t] or 0}`) end
	return table.concat(parts, " ")
end

-- Server call with busy guard + error display. Returns the server's table or nil.
local function call(remote: RemoteFunction?, ...: any): any?
	if not remote then setStatus("Guild remote missing", true) return nil end
	local ok, res = pcall(remote.InvokeServer, remote, ...)
	if not ok then
		setStatus("Server did not answer: " .. tostring(res), true)
		return nil
	end
	if type(res) ~= "table" then setStatus("Unexpected server answer", true) return nil end
	if res.ok == false then setStatus(tostring(res.error), true) return nil end
	return res
end

--------------------------------------------------
-- PAGES
--------------------------------------------------

local showPage: (string) -> () -- forward declaration

local function refreshOverview()
	local res = call(GuildEvents.GetGuildOverview)
	if not res then return end
	balanceLabel.Text = `Gold {res.gold or 0}   |   {matsText(res.materials)}`
	local b = res.buildings or {}
	phaseLabel.Text = `{currentPhase == "PreBattle" and "Before battle" or "After battle"} | Battles done: {res.battlesCompleted or 0} | Tavern L{b.Tavern or 1}  Merchant L{b.Merchant or 1}  Blacksmith L{b.Blacksmith or 1} (temporary levels)`
end

-- Run an action, then refresh the balance and the current page.
local function act(remote: RemoteFunction?, okText: (any) -> string, ...: any)
	if isBusy then return end
	isBusy = true
	local res = call(remote, ...)
	if res then setStatus(okText(res)) end
	isBusy = false
	refreshOverview()
	showPage(currentPage)
end

local function pageTavern()
	addHeading("TAVERN - hire recruits")
	local res = call(GuildEvents.GetTavernPool)
	if not res then return end
	addNote(`Tavern L{res.tavernLevel or 1}: one recruit per Tavern level. The pool refreshes after each battle. Fee = 200 + 15 x level (+ quality premium).`)
	if #(res.pool or {}) == 0 then
		addNote(res.reason and tostring(res.reason) or "No recruits left until the next battle.")
		return
	end
	for _, c in res.pool do
		local id = c.candidateId
		addRow(`Level {c.level} {c.quality} recruit  |  {c.cost} gold`, {
			{ text = "Hire", color = Theme.Colors.Success, onTap = function()
				act(GuildEvents.RequestHire, function(r) return `Hired {r.unitName} for {r.cost} gold` end, id)
			end },
		})
	end
end

local function pageMerchant()
	addHeading("MERCHANT - buy")
	local res = call(GuildEvents.GetMerchantStock)
	if not res then return end
	addNote(`Merchant L{res.merchantLevel or 1}: one item per Merchant level. Stock refreshes every 5 battles.`)
	if #(res.stock or {}) == 0 then
		addNote(res.reason and tostring(res.reason) or "Sold out for now.")
	end
	for _, o in res.stock or {} do
		local idx = o.offerIndex
		addRow(`{o.name}  Lv{o.level} {o.rarity}  |  {o.price} gold`, {
			{ text = "Buy", color = Theme.Colors.Success, style = "Primary", onTap = function()
				act(GuildEvents.RequestBuy, function(r) return `Bought {r.name} for {r.price} gold` end, idx)
			end },
		})
	end
	addHeading("MERCHANT - sell (unequipped items)")
	if #(res.sellable or {}) == 0 then addNote("Nothing to sell. Unequip an item first to sell it.") end
	for _, it in res.sellable or {} do
		local iid = it.instanceId
		addRow(`{it.name}  Lv{it.level} {it.rarity}`, {
			{ text = `Sell {it.price or "?"}g`, color = Theme.Colors.Warning, enabled = it.price ~= nil, style = "Primary", onTap = function()
				act(GuildEvents.RequestSell, function(r) return `Sold for {r.payout} gold` end, iid)
			end },
		})
	end
end

local function pageBlacksmith()
	addHeading("BLACKSMITH - upgrade / downgrade")
	local res = call(GuildEvents.GetBlacksmithItems)
	if not res then return end
	addNote(`Blacksmith L{res.blacksmithLevel or 1}: upgrades items up to level {(res.blacksmithLevel or 1) * 10}. One level per tap. Downgrades are free.`)
	for _, it in res.items or {} do
		local iid = it.instanceId
		local costText = "max"
		if it.upgradeGold then
			local mats = {}
			for _, m in it.upgradeMaterials or {} do table.insert(mats, `T{m.tier} x{m.qty}`) end
			costText = `{it.upgradeGold}g + {table.concat(mats, ", ")}`
		end
		local who = it.equippedBy and ` (on {it.equippedBy})` or ""
		local why = (not it.canUpgrade and it.upgradeBlockedReason) and `  [{it.upgradeBlockedReason}]` or ""
		addRow(`{it.name}  Lv{it.level} {it.rarity}{who}\nNext level: {costText}{why}`, {
			{ text = "Up", color = Theme.Colors.Success, enabled = it.canUpgrade, onTap = function()
				act(GuildEvents.RequestUpgrade, function(r) return `Upgraded to Lv{r.toLevel}` end, iid)
			end },
			{ text = "Down", color = Theme.Colors.Info, enabled = it.canDowngrade, onTap = function()
				act(GuildEvents.RequestDowngrade, function(r) return `Downgraded to Lv{r.toLevel}` end, iid)
			end },
		})
	end
end

local function pageDispatch()
	addHeading("DISPATCH - send units on missions")
	local res = call(GuildEvents.GetDispatchBoard)
	if not res then return end
	addNote("Sent units miss battles until they return, then bring back XP and materials. At least one unit must stay home.")
	if not selectedMission then
		if #(res.missions or {}) == 0 then addNote("No missions left until the next battle.") end
		for _, m in res.missions or {} do
			local mid = m.missionId
			addRow(`Tier {m.tier}  |  away {m.duration} battle(s)  |  {m.xp} XP each  |  T{m.rewardTier} material x{m.rewardCount}`, {
				{ text = "Choose", color = Theme.Colors.Info, onTap = function()
					selectedMission = mid
					selectedUnits = {}
					showPage("Dispatch")
				end },
			})
		end
	else
		addNote("Tap units to select them, then Send.")
		for _, u in res.units or {} do
			local uid = u.id
			if u.away then
				addRow(`{u.name}  Lv{u.level}  |  AWAY (back after battle {u.returnBattle or "?"})`, nil, true)
			else
				local picked = selectedUnits[uid] == true
				addRow(`{u.name}  Lv{u.level}{picked and "  [SELECTED]" or ""}`, {
					{ text = picked and "Remove" or "Select", color = picked and Theme.Colors.Warning or Theme.Colors.Info, onTap = function()
						selectedUnits[uid] = not picked or nil
						showPage("Dispatch")
					end },
				})
			end
		end
		local ids = {}
		for id in selectedUnits do table.insert(ids, id) end
		local mid = selectedMission
		addRow(`{#ids} unit(s) selected`, {
			{ text = "Back", color = Theme.Colors.Surface, onTap = function()
				selectedMission = nil
				selectedUnits = {}
				showPage("Dispatch")
			end },
			{ text = "Send", color = Theme.Colors.Success, enabled = #ids > 0, onTap = function()
				selectedMission = nil
				selectedUnits = {}
				act(GuildEvents.RequestDispatch, function(r) return `Sent. Back after battle {r.returnBattle} with {r.xpEach} XP each.` end, mid, ids)
			end },
		})
	end
end

local function pageUnits()
	addHeading("UNITS")
	addRow("Equipment, skills, doctrine and stats", {
		{ text = "Open Loadout", color = Theme.Colors.Info, onTap = function()
			local open = (_G :: any).CTRBLXAI_OpenLoadout
			if type(open) == "function" then open() else setStatus("Loadout screen not loaded", true) end
		end },
	})
	local res = call(GuildEvents.GetGuildUnits)
	if not res then return end
	for _, u in res.units or {} do
		local xpText = u.atCap and "MAX" or `{u.xp}/{u.xpToNext} XP`
		local state = u.away and `  |  AWAY (back after battle {u.returnBattle or "?"})` or ""
		local tag = u.isRecruit and " (hired)" or ""
		local row = addRow(`{u.name}{tag}  Lv{u.unitLevel}  |  XP level {u.xpLevel}: {xpText}\n{u.race} {u.doctrine}  |  HP {u.hp}/{u.maxHp}{state}`, nil, u.away)
		-- XP progress bar along the bottom of the row
		local bar = Instance.new("Frame")
		bar.Size = UDim2.new(1, -16, 0, 4)
		bar.Position = UDim2.new(0, 8, 1, -6)
		bar.BackgroundColor3 = Theme.Colors.EmptySlot
		bar.BorderSizePixel = 0
		bar.Parent = row
		local fill = Instance.new("Frame")
		local ratio = (u.atCap and 1) or ((u.xpToNext or 0) > 0 and math.clamp((u.xp or 0) / u.xpToNext, 0, 1) or 0)
		fill.Size = UDim2.fromScale(ratio, 1)
		fill.BackgroundColor3 = Theme.Colors.Info
		fill.BorderSizePixel = 0
		fill.Parent = bar
	end
end

local function pageDev()
	addHeading("DEV - temporary building levels (Studio only, not saved)")
	local res = call(GuildEvents.GetGuildOverview)
	if not res then return end
	for _, name in BUILDINGS_DEV do
		local lvl = (res.buildings and res.buildings[name]) or 1
		addRow(`{name}  L{lvl}`, {
			{ text = "-", color = Theme.Colors.Warning, enabled = lvl > 1, onTap = function()
				BattleEvents.DevCommand:FireServer({ action = "SetBuildingLevel", building = name, level = lvl - 1 })
				task.wait(0.3)
				refreshOverview()
				showPage("Dev")
			end },
			{ text = "+", color = Theme.Colors.Success, enabled = lvl < 10, onTap = function()
				BattleEvents.DevCommand:FireServer({ action = "SetBuildingLevel", building = name, level = lvl + 1 })
				task.wait(0.3)
				refreshOverview()
				showPage("Dev")
			end },
		})
	end
end

local PAGES: { [string]: () -> () } = {
	Tavern = pageTavern,
	Merchant = pageMerchant,
	Blacksmith = pageBlacksmith,
	Dispatch = pageDispatch,
	Units = pageUnits,
	Dev = pageDev,
}

-- The building list is a tab bar: old 9-slice text bars (user ruling 2026-10-08),
-- the open building = Active (bronze), the others = Inactive (navy). Theme.MakeTabButton.
local navPageOf: { [GuiButton]: string } = {}

local function styleNav()
	for btn, page in navPageOf do
		Theme.SetTabState(btn, if page == currentPage then "Active" else "Inactive")
	end
end

local function registerNav(btn: GuiButton, page: string)
	navPageOf[btn] = page
end

showPage = function(name: string)
	currentPage = name
	clearContent()
	local fn = PAGES[name]
	if fn then fn() end
	styleNav()
end

--------------------------------------------------
-- BUILDING BUTTONS
--------------------------------------------------

local navButtons: { GuiButton } = {}
local leaveButton: TextButton? = nil
local advGuildButton: TextButton? = nil
local devButton: GuiButton? = nil

local function buildNav()
	for _, b in navButtons do b:Destroy() end
	navButtons = {}
	table.clear(navPageOf) -- destroyed buttons must not stay referenced (PRF-004)
	local entries = {
		{ "Tavern", "Tavern" }, { "Merchant", "Merchant" }, { "Blacksmith", "Blacksmith" },
		{ "Dispatch", "Dispatch" }, { "Units", "Units" },
	}
	for i, e in entries do
		local pageName = e[2]
		local btn: GuiButton = Theme.MakeTabButton(nav, e[1], "Inactive", function()
			selectedMission = nil
			setStatus("")
			showPage(pageName)
		end, { name = "Nav_" .. pageName, size = UDim2.new(1, 0, 0, BUTTON_HEIGHT), layoutOrder = i,
			textSize = Theme.Text.Body() })
		registerNav(btn, pageName)
		table.insert(navButtons, btn)
	end
	local dev: GuiButton = Theme.MakeTabButton(nav, "Dev: Levels", "Inactive", function() showPage("Dev") end,
		{ name = "Nav_Dev", size = UDim2.new(1, 0, 0, BUTTON_HEIGHT), layoutOrder = 50, textSize = Theme.Text.Body() })
	dev.Visible = false
	devButton = dev
	registerNav(dev, "Dev")
	table.insert(navButtons, dev)

	-- Adventurer's Guild: opens the quest board (2026-10-12). Fires OpenAdventurersGuild;
	-- the server is waiting at the guild base and responds by showing the quest board.
	local advGuild = makeButton(nav, "Adventurer's Guild", Theme.Colors.Accent or Theme.Colors.Success, function()
		if isBusy then return end
		BattleEvents.OpenAdventurersGuild:FireServer()
	end)
	advGuild.Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT)
	advGuild.LayoutOrder = 90
	advGuildButton = advGuild
	table.insert(navButtons, advGuild)

	local leave = makeButton(nav, "", Theme.Colors.Success, function()
		if isBusy then return end
		screenGui.Enabled = false
		-- Same intention the old Loadout Hub sent; the server continues from there.
		BattleEvents.StartBattle:FireServer()
	end)
	leave.Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT + 8)
	leave.LayoutOrder = 100
	leaveButton = leave
	table.insert(navButtons, leave)
	styleNav()
end
buildNav()

--------------------------------------------------
-- SERVER FACTS
--------------------------------------------------

GuildEvents.GuildMenuOpened.OnClientEvent:Connect(function(data: any)
	currentPhase = (type(data) == "table" and type(data.phase) == "string") and data.phase or "PreBattle"
	-- Button visibility by phase (2026-10-13 fix for the "Continue to Deployment at the
	-- base" crash): at the Base hub the ONLY way to start something is the Adventurer's
	-- Guild (which launches the quest activity); there is no quest/map yet, so the deploy
	-- button must NOT appear. "Continue to Deployment" belongs only at the sortie briefing
	-- (PreBattle); "Save & Finish" only after a battle (PostBattle).
	local atBase = (currentPhase == "Base")
	if advGuildButton then
		advGuildButton.Visible = atBase
	end
	if leaveButton then
		leaveButton.Visible = not atBase
		if not atBase then
			leaveButton.Text = (currentPhase == "PostBattle") and "Save & Finish" or "Continue to Deployment"
		end
	end
	selectedMission = nil
	selectedUnits = {}
	setStatus("")
	screenGui.Enabled = true
	refreshOverview()
	local ov = call(GuildEvents.GetGuildOverview)
	if devButton then devButton.Visible = ov ~= nil and ov.isStudio == true end
	showPage("Units")
	print(`[GuildMenu] Opened ({currentPhase})`)
end)

GuildEvents.GuildMenuClosed.OnClientEvent:Connect(function()
	screenGui.Enabled = false
	print("[GuildMenu] Closed")
end)

print("[GuildMenu] Ready — waiting for GuildMenuOpened")
