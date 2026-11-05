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
local RunService        = game:GetService("RunService")

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
-- Merchant is its own full screen (2026-10-31, user ruling): opened from here, Back returns here.
local merchantScreenModule = UIFolder:WaitForChild("MerchantScreen", WAIT)
if not merchantScreenModule then warn("[GuildMenu] MerchantScreen module missing") end

-- Modules found at runtime via WaitForChild; the editor cannot follow that path, so
-- require is called through `any` (editor-only; same module loads at runtime).
local Theme: any        = (require :: any)(themeModule)
local GuildEvents: any  = (require :: any)(guildModule)
local BattleEvents: any = (require :: any)(battleModule)
local MerchantScreen: any = if merchantScreenModule then (require :: any)(merchantScreenModule) else nil
-- Tavern is its own full screen too (2026-10-31, same design as the Merchant).
local tavernScreenModule = UIFolder:WaitForChild("TavernScreen", WAIT)
if not tavernScreenModule then warn("[GuildMenu] TavernScreen module missing") end
local TavernScreen: any = if tavernScreenModule then (require :: any)(tavernScreenModule) else nil
-- Always-on Studio dev panel (2026-10-31): shop refresh, building levels, gold, saves.
local DevToolsPanel: any = nil
if RunService:IsStudio() then
	local devModule = script.Parent:WaitForChild("DevToolsPanel", WAIT)
	if devModule then
		DevToolsPanel = (require :: any)(devModule)
	else
		warn("[GuildMenu] DevToolsPanel module missing")
	end
end
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

--------------------------------------------------
-- STATE
--------------------------------------------------

local currentPhase = "PreBattle"
local currentPage = "Units"
local isBusy = false
local selectedMission: string? = nil
local selectedUnits: { [string]: boolean } = {}
local selectedParty: string? = nil
local partyEdit: { [string]: boolean } = {}
local sortiePartySlot: string? = nil   -- party chosen for THIS sortie (shown on Continue)
local sortiePartyName: string? = nil
local updateSortieButton: () -> () = function() end  -- reassigned once leaveButton exists
-- ADVENTURER'S GUILD screen (2026-10-16): the guild quest board is now an in-menu page
-- (like Tavern/Merchant), not a separate screen. guildQuests holds the server's offered
-- quests; sortieMode flips the page from quest-selection to sortie controls after a quest
-- is accepted (phase PreBattle). Base stays persistent -- the menu is never torn down.
local guildQuests: { any }? = nil
local sortieMode = false
-- Adventurer's Guild in-page step machine (2026-10-16): the guild screen walks
-- board -> chosen (details/abandon/sortie) -> sortie (party + embark). chosenQuest is the
-- picked quest (kept client-side for the details view); guildSortieStep is the sub-step
-- while a quest is accepted ("overview" | "details" | "sortie"); departPending means the
-- player tapped Embark before the map finished -- StartBattle fires automatically on
-- MapBuildComplete. This replaces the deprecated nav 'Continue - Party X' + 'Change party'.
local chosenQuest: any = nil
local guildSortieStep = "overview"
local departPending = false
local sortieLocked = false  -- moved above its readers (L894/L1043); a Luau local is invisible above its old decl point
local cartBuys: { [number]: { name: string, price: number } } = {}  -- staged buys (offerIndex -> info)
local cartSells: { [string]: { name: string, price: number } } = {}  -- staged sells (instanceId -> info)
local cartHires: { [string]: { name: string, price: number } } = {}  -- staged hires (candidateId -> info), 2026-10-31
local cartUpgrades: { [string]: { name: string, fromLevel: number, toLevel: number, gold: number, mercury: number } } = {}  -- staged blacksmith upgrades (may span several levels)
local cartDowngrades: { [string]: { name: string, toLevel: number } } = {}  -- staged blacksmith downgrades
local cartDispatches: { { missionId: string, unitIds: { string }, fee: number } } = {}  -- staged dispatches
-- Last server overview snapshot (gold + resources), refreshed by refreshOverview(). Lets
-- the header show a LIVE projected balance as items are staged, with no server round-trip
-- per toggle. (2026-10-14; v2 resources 2026-11-01)
local lastOverview: { gold: number, resources: { [string]: number } } = { gold = 0, resources = {} }

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
	-- Mirror into an open building screen (the guild menu, and this line, are hidden then).
	if MerchantScreen then MerchantScreen.SetStatus(text, isError) end
	if TavernScreen then TavernScreen.SetStatus(text, isError) end
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

-- Resource counters shown in the header. Only mercury for now: crystals and sulfur
-- have no source until dismantling arrives (v2 build step 2).
local function resourcesText(res: any): string
	if type(res) ~= "table" then return "" end
	return `Mercury {res.mercury or 0}`
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

-- RENDER CACHE (2026-10-14): showPage() destroys and rebuilds the whole tab on every
-- click, and each page builder re-queries the server; that round-trip leaves the panel
-- empty for a frame = the "black flash" per click. Client-only changes (cart toggles,
-- dispatch mission/unit selection) do NOT change server state, so they rebuild from the
-- last server response instead of re-fetching -- same frame, no flash. The cache is
-- invalidated whenever server state actually changes (a live action, a Finalize commit,
-- or reopening the menu), so displayed data is never stale.
local pageDataCache: { [string]: any } = {}
local function invalidatePageCache()
	table.clear(pageDataCache)
end
local function cachedCall(key: string, remote: RemoteFunction?, ...: any): any?
	if pageDataCache[key] ~= nil then return pageDataCache[key] end
	local res = call(remote, ...)
	if res ~= nil then pageDataCache[key] = res end
	return res
end

local showPage: (string) -> () -- forward declaration

-- Live header balance. With nothing staged it shows the real gold + materials; once a
-- screen has staged changes it shows the PROJECTED balance (gold after sells/buys/upgrade
-- cost/dispatch fees, plus the materials that will be spent) so the player sees the result
-- before committing. Pure client math over the cart tables + lastOverview; no server call.
local function updateBalanceLabel()
	local realGold = lastOverview.gold or 0
	local realRes = lastOverview.resources or {}
	local goldDelta = 0
	for _, v in cartSells do goldDelta += v.price end
	for _, v in cartBuys do goldDelta -= v.price end
	for _, v in cartUpgrades do goldDelta -= (v.gold or 0) end
	for _, d in cartDispatches do goldDelta -= (d.fee or 0) end
	for _, v in cartHires do goldDelta -= v.price end
	local mercurySpend = 0
	for _, v in cartUpgrades do mercurySpend += (v.mercury or 0) end
	local staged = goldDelta ~= 0 or mercurySpend > 0
		or next(cartSells) ~= nil or next(cartBuys) ~= nil
		or next(cartUpgrades) ~= nil or next(cartDowngrades) ~= nil
		or #cartDispatches > 0 or next(cartHires) ~= nil
	if not staged then
		balanceLabel.Text = `Gold {realGold}   |   {resourcesText(realRes)}`
		if MerchantScreen then MerchantScreen.SetGold(balanceLabel.Text) end
		if TavernScreen then TavernScreen.SetGold(balanceLabel.Text) end
		return
	end
	local projGold = realGold + goldDelta
	local goldStr = (goldDelta ~= 0) and `Gold {realGold} -> {projGold}` or `Gold {realGold}`
	local matStr = (mercurySpend > 0) and `   |   spend {mercurySpend} mercury` or ""
	balanceLabel.Text = goldStr .. matStr
	if MerchantScreen then MerchantScreen.SetGold(balanceLabel.Text) end
	if TavernScreen then TavernScreen.SetGold(balanceLabel.Text) end
end

local function refreshOverview()
	local res = call(GuildEvents.GetGuildOverview)
	if not res then return end
	lastOverview = { gold = res.gold or 0, resources = res.resources or {} }
	updateBalanceLabel()
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
	invalidatePageCache()  -- server state changed; next render re-fetches fresh
	refreshOverview()
	showPage(currentPage)
end

-- SMARTER SAVE / CART (2026-10-13): buy & sell are staged on the client and only
-- committed when the player presses Finalize (one server call, one save). Nothing is
-- spent or sold until then, so a mis-tap can't lose a prized item.
local function cartCount(): number
	local n = 0
	for _ in cartBuys do n += 1 end
	for _ in cartSells do n += 1 end
	for _ in cartUpgrades do n += 1 end
	for _ in cartDowngrades do n += 1 end
	n += #cartDispatches  -- staged dispatches (array)
	for _ in cartHires do n += 1 end
	return n
end

local function finalizeCart()
	if isBusy then return end
	local buys: { number } = {}
	local sells: { string } = {}
	local upgrades: { [string]: number } = {}
	local downgrades: { [string]: number } = {}
	local dispatches: { any } = {}
	local hires: { string } = {}
	for idx in cartBuys do table.insert(buys, idx) end
	for cid in cartHires do table.insert(hires, cid) end
	for iid in cartSells do table.insert(sells, iid) end
	for iid, v in cartUpgrades do upgrades[iid] = v.toLevel end
	for iid, v in cartDowngrades do downgrades[iid] = v.toLevel end
	for _, d in cartDispatches do table.insert(dispatches, { missionId = d.missionId, unitIds = d.unitIds }) end
	if #buys == 0 and #sells == 0 and next(upgrades) == nil and next(downgrades) == nil and #dispatches == 0 and #hires == 0 then
	setStatus("Nothing pending") return
	end
	isBusy = true
	local res = call(GuildEvents.FinalizeCart, { buys = buys, sells = sells, upgrades = upgrades, downgrades = downgrades, dispatches = dispatches, hires = hires })
	isBusy = false
	if res then
		cartBuys = {}
		cartSells = {}
		cartUpgrades = {}
		cartDowngrades = {}
		cartDispatches = {}
		cartHires = {}
		-- Failed buys / sells are reported, not silent (2026-10-31). Server detail goes to Output.
		local failParts: { string } = {}
		local buyFailed = tonumber(res.buyFailed) or 0
		local sellFailed = tonumber(res.sellFailed) or 0
		if buyFailed > 0 then table.insert(failParts, `{buyFailed} could not be bought`) end
		if sellFailed > 0 then table.insert(failParts, `{sellFailed} could not be sold`) end
		local otherFailed = #(res.problems or {}) - buyFailed - sellFailed
		if otherFailed > 0 then table.insert(failParts, `{otherFailed} other change(s) failed`) end
		for _, why in res.problems or {} do
			warn(`[GuildMenu] Not completed: {tostring(why)}`)
		end
		local doneText = `Done -- bought {res.boughtCount or 0}, sold {res.soldCount or 0}, upgraded {res.upgradedCount or 0}, downgraded {res.downgradedCount or 0}, dispatched {res.dispatchedCount or 0}, hired {res.hiredCount or 0}. Gold {res.gold or 0}`
		if #failParts > 0 then
			setStatus(`{doneText} | {table.concat(failParts, ", ")}`, true)
		else
			setStatus(doneText)
		end
	end
	invalidatePageCache()  -- server state changed; next render re-fetches fresh
	refreshOverview()
	showPage(currentPage)
end

local function clearCart()
	cartBuys = {}
	cartSells = {}
	cartUpgrades = {}
	cartDowngrades = {}
	cartDispatches = {}
	cartHires = {}
	setStatus("Pending changes discarded")
	showPage(currentPage)
end

-- Unified cart summary (buy/sell/upgrade/downgrade), shown at the top of the Merchant and
-- Blacksmith tabs so the player can review and commit from either. Net gold = sells minus
-- buys minus upgrade gold. Per-item material cost is shown on each Blacksmith row (exact
-- tiers); this one-line summary is a glance, Finalize commits the whole batch.
local function addCartSummaryRow()
	local nBuy, buyGold = 0, 0
	for _, v in cartBuys do nBuy += 1; buyGold += v.price end
	local nSell, sellGold = 0, 0
	for _, v in cartSells do nSell += 1; sellGold += v.price end
	local nUp, upGold = 0, 0
	for _, v in cartUpgrades do nUp += 1; upGold += v.gold end
	local nDown = 0
	for _ in cartDowngrades do nDown += 1 end
	local nDisp, dispFee = 0, 0
	for _, d in cartDispatches do nDisp += 1; dispFee += (d.fee or 0) end
	if nBuy + nSell + nUp + nDown + nDisp == 0 then return end
	local parts = {}
	if nBuy > 0 then table.insert(parts, `buy {nBuy}`) end
	if nSell > 0 then table.insert(parts, `sell {nSell}`) end
	if nUp > 0 then table.insert(parts, `upgrade {nUp}`) end
	if nDown > 0 then table.insert(parts, `downgrade {nDown}`) end
	if nDisp > 0 then table.insert(parts, `dispatch {nDisp}`) end
	local netGold = sellGold - buyGold - upGold - dispFee
	-- Player-facing wording: no shop/dev jargon ("Cart"/"Finalize"/"Clear").
	-- Confirm/Discard model, "Pending" for queued changes. (2026-10-17)
	addRow(`Pending: {table.concat(parts, ", ")}  |  net {netGold}g`, {
		{ text = "Confirm", color = Theme.Colors.Success, style = "Primary", onTap = finalizeCart },
		{ text = "Discard", color = Theme.Colors.Warning, style = "Tertiary", onTap = clearCart },
	})
end

local leaveDialog: TextButton? = nil
local function closeLeaveDialog()
	if leaveDialog then
		leaveDialog:Destroy()
		leaveDialog = nil
	end
end

-- Confirm/discard when leaving with a staged cart (user choice 2026-10-13).
local function confirmLeaveWithCart(proceed: () -> ())
	if cartCount() == 0 then proceed() return end
	closeLeaveDialog()
	local nBuy, nSell, nUp, nDown, nDisp, nHire = 0, 0, 0, 0, 0, 0
	for _ in cartHires do nHire += 1 end
	for _ in cartBuys do nBuy += 1 end
	for _ in cartSells do nSell += 1 end
	for _ in cartUpgrades do nUp += 1 end
	for _ in cartDowngrades do nDown += 1 end
	for _ in cartDispatches do nDisp += 1 end
	local overlay = Instance.new("TextButton")
	overlay.Text = ""
	overlay.AutoButtonColor = false
	overlay.Modal = true
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.4
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 10
	-- Host the prompt on an open building screen (the guild menu is hidden while one is up).
	local host: Instance? = (MerchantScreen and MerchantScreen.GetGui()) or (TavernScreen and TavernScreen.GetGui()) or nil
	overlay.Parent = host or screenGui
	overlay.Activated:Connect(function() end)  -- absorb background taps
	leaveDialog = overlay
	local box = Instance.new("Frame")
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.new(0.5, 0, 0.5, 0)
	box.Size = UDim2.new(0, 340, 0, 160)
	box.BackgroundColor3 = Theme.Colors.PanelRaised
	box.BorderSizePixel = 0
	box.ZIndex = 10
	box.Parent = overlay
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius.md
	corner.Parent = box
	local msg = makeText(box, `Unsaved changes -- buy {nBuy}, sell {nSell}, hire {nHire}, upgrade {nUp}, downgrade {nDown}, dispatch {nDisp}. Confirm or discard?`, Theme.Text.Body(), Theme.Colors.TextPrimary, true)
	msg.Size = UDim2.new(1, -24, 0, 70)
	msg.Position = UDim2.new(0, 12, 0, 10)
	msg.ZIndex = 11
	local function mk(txt: string, color: Color3, slot: number, cb: () -> ())
		local b = makeButton(box, txt, color, cb)
		b.Size = UDim2.new(0.3, -8, 0, BUTTON_HEIGHT)
		b.AnchorPoint = Vector2.new(0, 0.5)
		b.Position = UDim2.new(0.035 + 0.323 * slot, 0, 1, -BUTTON_HEIGHT * 0.5 - 12)
		b.ZIndex = 11  -- above box (ZIndex 10); Global ZIndexBehavior otherwise hides children
	end
	mk("Confirm", Theme.Colors.Success, 0, function()
		closeLeaveDialog()
		finalizeCart()
		if cartCount() == 0 then proceed() end
	end)
	mk("Discard", Theme.Colors.Warning, 1, function()
		cartBuys = {}
		cartSells = {}
		cartUpgrades = {}
		cartDowngrades = {}
		cartDispatches = {}
		cartHires = {}
		closeLeaveDialog()
		proceed()
	end)
	mk("Cancel", Theme.Colors.Info, 2, function()
		closeLeaveDialog()
	end)
end

-- Tavern page moved to its own screen (TavernScreen, 2026-10-31).

-- MERCHANT SCREEN (2026-10-31, user ruling): the Merchant is its own full screen
-- (MerchantScreen + shared GuildScreen frame), like the Loadout. This menu hides while it is
-- up; Back (after the Confirm/Discard prompt) brings the menu back. The pending buy/sell list
-- stays here (per-screen basket); the screen only reads / toggles it, and Confirm still sends
-- only offer indexes / instance ids (SEC-002).
local function openTavern()
	if not TavernScreen then
		setStatus("Tavern screen not loaded", true)
		return
	end
	screenGui.Enabled = false
	TavernScreen.Open()
	updateBalanceLabel() -- fill the screen's gold line
end

local function openMerchant()
	if not MerchantScreen then
		setStatus("Merchant screen not loaded", true)
		return
	end
	screenGui.Enabled = false
	MerchantScreen.Open()
	updateBalanceLabel() -- fill the screen's gold line
end

if MerchantScreen then
	MerchantScreen.Init({
		parent = playerGui,
		getStock = function(): any?
			return cachedCall("Merchant", GuildEvents.GetMerchantStock)
		end,
		isQueued = function(tab: string, key: any): boolean
			if tab == "Buy" then return cartBuys[key] ~= nil end
			return cartSells[key] ~= nil
		end,
		toggle = function(tab: string, key: any, name: string, price: number?)
			if tab == "Buy" then
				if cartBuys[key] then
					cartBuys[key] = nil
				elseif price ~= nil then
					cartBuys[key] = { name = name, price = price }
				end
			else
				if cartSells[key] then
					cartSells[key] = nil
				elseif price ~= nil then
					cartSells[key] = { name = name, price = price }
				end
			end
			updateBalanceLabel()
		end,
		pendingCount = cartCount,
		-- Totals for the Merchant's Confirm-all / Discard-all prompts (client display only).
		summary = function(): any
			local s = { nBuy = 0, buyGold = 0, nSell = 0, sellGold = 0 }
			for _, v in cartBuys do
				s.nBuy += 1
				s.buyGold += v.price
			end
			for _, v in cartSells do
				s.nSell += 1
				s.sellGold += v.price
			end
			return s
		end,
		confirm = finalizeCart,
		discard = clearCart,
		requestBack = confirmLeaveWithCart,
		onClosed = function()
			screenGui.Enabled = true
			-- Status is NOT cleared here, so a "Done -- bought ..." result from the Back
			-- prompt's Confirm stays visible on the guild menu (Tester note 2026-10-31).
			updateBalanceLabel()
			showPage(currentPage)
		end,
	})
end

-- TAVERN SCREEN (2026-10-31): same model as the Merchant. Pending hires stay in this menu's
-- basket (cartHires); Confirm sends only candidate ids, the server re-validates and prices.
if TavernScreen then
	TavernScreen.Init({
		parent = playerGui,
		getPool = function(): any?
			return cachedCall("Tavern", GuildEvents.GetTavernPool)
		end,
		isQueued = function(key: string): boolean
			return cartHires[key] ~= nil
		end,
		toggle = function(key: string, name: string, price: number?)
			if cartHires[key] then
				cartHires[key] = nil
			elseif price ~= nil then
				cartHires[key] = { name = name, price = price }
			end
			updateBalanceLabel()
		end,
		pendingCount = cartCount,
		summary = function(): any
			local s = { nHire = 0, hireGold = 0 }
			for _, v in cartHires do
				s.nHire += 1
				s.hireGold += v.price
			end
			return s
		end,
		confirm = finalizeCart,
		discard = clearCart,
		requestBack = confirmLeaveWithCart,
		onClosed = function()
			screenGui.Enabled = true
			updateBalanceLabel()
			showPage(currentPage)
		end,
	})
end

-- DEV PANEL wiring (Studio only, 2026-10-31). A dev change to the shops or a building level
-- drops pending buys and dispatches (their offer / mission ids may now point at a different
-- offer), then redraws whatever guild screen is showing.
local function onDevGuildChanged(what: string)
	local dropped = #cartDispatches
	for _ in cartBuys do dropped += 1 end
	for _ in cartHires do dropped += 1 end
	cartBuys = {}
	cartDispatches = {}
	cartHires = {} -- candidate ids change with the pool seed / Tavern level
	invalidatePageCache()
	refreshOverview()
	if MerchantScreen and MerchantScreen.IsOpen() then
		MerchantScreen.Render()
	elseif TavernScreen and TavernScreen.IsOpen() then
		TavernScreen.Render()
	elseif screenGui.Enabled then
		showPage(currentPage)
	end
	local note = if dropped > 0 then ` | {dropped} pending buy/hire/dispatch dropped` else ""
	setStatus(`Dev: {what}{note}`)
end

if DevToolsPanel then
	DevToolsPanel.Init({
		parent = playerGui,
		devGuild = GuildEvents.DevGuild,
		devCommand = BattleEvents.DevCommand,
		onShopsRefreshed = function() onDevGuildChanged("all shops refreshed") end,
		onLevelsChanged = function() onDevGuildChanged("building level changed") end,
		onGoldChanged = function() refreshOverview() end,
	})
end

local function pageBlacksmith()
	addHeading("BLACKSMITH - upgrade / downgrade")
	local res = cachedCall("Blacksmith", GuildEvents.GetBlacksmithItems)
	if not res then return end
	addCartSummaryRow()
	addNote(`Blacksmith L{res.blacksmithLevel or 1}: upgrades items up to level {(res.blacksmithLevel or 1) * 10}. Queue several levels with +1 / Max; -1 removes one. Downgrades are free.`)
	for _, it in res.items or {} do
		local iid = it.instanceId
		local curve = it.upgradeCurve or {}
		local maxLevel = it.level + #curve  -- highest level reachable given the gated curve
		local staged = cartUpgrades[iid]
		local stagedTo = (staged and staged.toLevel) or it.level
		local downStaged = cartDowngrades[iid] ~= nil

		-- Sum curve steps (current+1 .. target) into gold + mercury. Summing the first N
		-- entries equals exactly what the server charges (it commits +1 at a time).
		local function costTo(target: number): (number, number)
			local gold, mercury = 0, 0
			for _, step in curve do
				if step.toLevel <= target then
					gold += step.gold
					mercury += step.mercury or 1
				end
			end
			return gold, mercury
		end

		local function stageTo(target: number)
			if target <= it.level then
				cartUpgrades[iid] = nil
			else
				local g, m = costTo(target)
				cartUpgrades[iid] = { name = it.name, fromLevel = it.level, toLevel = target, gold = g, mercury = m }
				cartDowngrades[iid] = nil
			end
			showPage(currentPage)
		end

		local who = it.equippedBy and ` (on {it.equippedBy})` or ""
		local titleLine = (stagedTo > it.level) and `{it.name}  Lv{it.level} -> Lv{stagedTo}  {it.rarity}` or `{it.name}  Lv{it.level} {it.rarity}`
		-- MERCURY AFFORDABILITY CAP (2026-10-16; mercury v2 2026-11-01): +1 / Max must not stage
		-- levels the player cannot pay mercury for. Mercury is a SHARED pool across every staged
		-- item, so subtract what OTHER items already reserve, then walk this item's curve.
		-- Gold is checked at commit; this guard is specifically mercury.
		local remainingMercury = (lastOverview.resources and lastOverview.resources.mercury) or 0
		for otherId, up in cartUpgrades do
			if otherId ~= iid then remainingMercury -= (up.mercury or 0) end
		end
		local maxAffordable = it.level
		do
			local run = 0
			for _, step in curve do
				run += step.mercury or 1
				if run <= remainingMercury then maxAffordable = step.toLevel else break end
			end
		end
		local matCapReached = (stagedTo < maxLevel) and (#curve > 0) and not downStaged and (stagedTo >= maxAffordable)
		local costLine
		if stagedTo > it.level then
			local g, m = costTo(stagedTo)
			costLine = `Upgrade cost: {g}g + {m} mercury`
		elseif #curve > 0 then
			local s = curve[1]
			costLine = `Next (Lv{s.toLevel}): {s.gold}g + {s.mercury or 1} mercury`
		else
			costLine = (it.upgradeBlockedReason and `[{it.upgradeBlockedReason}]`) or "At max level"
		end
		if matCapReached then
			costLine = costLine .. "\nNeed more mercury to upgrade further"
		end

		local canAdd = (stagedTo < maxLevel) and (#curve > 0) and not downStaged
		-- Can only add another level if the NEXT level up is still within the affordable cap.
		canAdd = canAdd and (stagedTo < maxAffordable)
		local btns = {}
		table.insert(btns, { text = "+1", color = Theme.Colors.Success, enabled = canAdd, onTap = function()
			stageTo(math.min(stagedTo + 1, maxAffordable))
		end })
		table.insert(btns, { text = "-1", color = Theme.Colors.Warning, enabled = stagedTo > it.level, onTap = function()
			stageTo(stagedTo - 1)
		end })
		table.insert(btns, { text = "Max", color = Theme.Colors.Info, enabled = canAdd, onTap = function()
			stageTo(maxAffordable)
		end })
		if stagedTo == it.level then
			table.insert(btns, { text = downStaged and "Down*" or "Down", color = Theme.Colors.Info,
			  enabled = it.canDowngrade or downStaged, onTap = function()
				if cartDowngrades[iid] then
					cartDowngrades[iid] = nil
				elseif it.canDowngrade then
					cartDowngrades[iid] = { name = it.name, toLevel = it.level - 1 }
					cartUpgrades[iid] = nil
				end
				showPage(currentPage)
			end })
		end

		addRow(`{titleLine}{who}\n{costLine}`, btns)
	end
end

local function pageDispatch()
	addHeading("DISPATCH - send units on missions")
	local res = cachedCall("Dispatch", GuildEvents.GetDispatchBoard)
	if not res then return end
	addCartSummaryRow()
	-- Staged-dispatch guards (2026-10-14): dispatch entries interact (one unit per mission,
	-- one mission per group, keep >=1 home, slot cap), so staged missions are hidden, staged
	-- units are greyed, and a stage that would empty the roster or exceed slots is blocked up
	-- front -- rather than letting the server silently refuse part of the batch at commit.
	local stagedUnits: { [string]: boolean } = {}
	local stagedMissions: { [string]: boolean } = {}
	local nStaged = 0
	for _, d in cartDispatches do
		nStaged += 1
		stagedMissions[d.missionId] = true
		for _, uid in d.unitIds do stagedUnits[uid] = true end
	end
	local slotsUsed = (res.slotsUsed or 0) + nStaged
	local slotCap = res.slotCap or 1
	local homeCount = 0
	for _, u in res.units or {} do
		if not u.away and not stagedUnits[u.id] then homeCount += 1 end
	end
	addNote(`Sent units miss battles until they return, then bring back XP and mercury. Fee {res.feeGold or 50}g per mission. Keep >=1 home. Slots {slotsUsed}/{slotCap}.`)
	if not selectedMission then
		local anyMission = false
		for _, m in res.missions or {} do
			if not stagedMissions[m.missionId] then
				anyMission = true
				local mid = m.missionId
				addRow(`Tier {m.tier}  |  away {m.duration} battle(s)  |  {m.xp} XP each  |  {m.rewardMercury or 1} mercury`, {
					{ text = "Select", color = Theme.Colors.Info, enabled = slotsUsed < slotCap, onTap = function()
						selectedMission = mid
						selectedUnits = {}
						showPage("Dispatch")
					end },
				})
			end
		end
		if not anyMission then addNote("No missions available (all queued, or none left until the next battle).") end
		if slotsUsed >= slotCap then addNote("All dispatch slots are in use (queued or active). Upgrade the Guild Hall for more.") end
	else
		addNote("Tap units to select them, then Queue dispatch. Units already queued or away cannot be picked.")
		for _, u in res.units or {} do
			local uid = u.id
			if u.away then
				addRow(`{u.name}  Lv{u.level}  |  AWAY (back after battle {u.returnBattle or "?"})`, nil, true)
			elseif stagedUnits[uid] then
		addRow(`{u.name}  Lv{u.level}  |  QUEUED`, nil, true)
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
		addRow(`{#ids} unit(s) selected  |  leaves {homeCount - #ids} home`, {
			{ text = "Back", color = Theme.Colors.Surface, onTap = function()
				selectedMission = nil
				selectedUnits = {}
				showPage("Dispatch")
			end },
			{ text = "Queue dispatch", color = Theme.Colors.Success, enabled = #ids > 0, onTap = function()
				if #ids < 1 then return end
				if homeCount - #ids < 1 then setStatus("Keep at least one unit home", true) return end
				if slotsUsed >= slotCap then setStatus("No free dispatch slot", true) return end
				table.insert(cartDispatches, { missionId = mid, unitIds = ids, fee = res.feeGold or 50 })
				selectedMission = nil
				selectedUnits = {}
				setStatus(`Dispatch queued ({#ids} unit(s)). Confirm to send.`)
				showPage("Dispatch")
			end },
		})
	end
end

local function pageUnits()
	addHeading("UNITS")
	addRow("Equipment, skills, doctrine and stats", {
		{ text = "Loadout", color = Theme.Colors.Info, onTap = function()
			local open = (_G :: any).CTRBLXAI_OpenLoadout
			if type(open) ~= "function" then setStatus("Loadout screen not loaded", true) return end
			-- The Loadout is a separate full-screen UI. Hide the guild menu while it is up, then
			-- restore the guild menu when Loadout closes -- otherwise opening Loadout mid-sortie
			-- left the player with no guild screen (no Sortie/Abandon). Client-only; watches the
			-- Loadout ScreenGui ("LoadoutScreen") in PlayerGui and re-shows + re-renders on close. (2026-10-16)
			local pg = player:FindFirstChild("PlayerGui")
			screenGui.Enabled = false
			open()
			task.spawn(function()
				local appeared = false
				for _ = 1, 100 do
					local ls = pg and pg:FindFirstChild("LoadoutScreen")
					if ls then appeared = true elseif appeared then break end
					task.wait(0.1)
				end
				-- Loadout closed (or never opened): bring the guild menu back and refresh the page.
				screenGui.Enabled = true
				invalidatePageCache()
				refreshOverview()
				showPage(currentPage)
			end)
		end },
	})
	local res = cachedCall("Units", GuildEvents.GetGuildUnits)
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

local function pageParty()
	addHeading("PARTIES")
	local res = cachedCall("Party", GuildEvents.GetParties)
	if not res then return end
	local maxSize = res.maxSize or 7
	if not selectedParty then
		for _, party in ipairs(res.parties or {}) do
			local slot = party.slot
			local names = {}
			for _, mi in ipairs(party.memberInfo or {}) do table.insert(names, mi.name) end
			local summary = (#names > 0) and table.concat(names, ", ") or "No units assigned"
			-- At the sortie (PreBattle), a non-empty party can be DEPLOYED (Choose Party ->
			-- go). Empty parties get no Deploy button -- they cannot be chosen (2026-10-15).
			local listBtns = {}
			if currentPhase == "PreBattle" and #names > 0 then
				local isSel = (sortiePartySlot == slot)
				table.insert(listBtns, { text = isSel and "Deploying" or "Select", color = isSel and Theme.Colors.Success or Theme.Colors.Info, enabled = not sortieLocked and not isSel, onTap = function()
					sortiePartySlot = slot
					sortiePartyName = party.name
					BattleEvents.SelectSortieParty:FireServer(slot)
					updateSortieButton()
					setStatus(`{party.name} will deploy`)
					-- Picking a party during a sortie returns to the Adventurer's Guild sortie step
					-- (where Embark is), not back to this list. (2026-10-16)
					if sortieMode then
						guildSortieStep = "sortie"
						showPage("Adventurers")
					else
						showPage("Party")
					end
				end })
			end
			table.insert(listBtns, { text = "Edit", color = Theme.Colors.Info, onTap = function()
				selectedParty = slot
				partyEdit = {}
				for _, uid in ipairs(party.members or {}) do partyEdit[uid] = true end
				showPage("Party")
			end })
			addRow(`{party.name}  |  {#names}/{maxSize}\n{summary}`, listBtns)
		end
		if sortieMode then
			addRow("", {
				{ text = "Back", color = Theme.Colors.Surface, onTap = function()
					guildSortieStep = "sortie"
					showPage("Adventurers")
				end },
			})
		end
	else
		local party = nil
		for _, p in ipairs(res.parties or {}) do
			if p.slot == selectedParty then party = p break end
		end
		if not party then selectedParty = nil showPage("Party") return end

		rowOrder += 1
		local nameBox = Instance.new("TextBox")
		nameBox.Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT)
		nameBox.BackgroundColor3 = Theme.Colors.Surface
		nameBox.BackgroundTransparency = 0.1
		nameBox.BorderSizePixel = 0
		nameBox.Font = Theme.Font.PrimaryBold
		nameBox.TextSize = Theme.Text.Body()
		nameBox.TextColor3 = Theme.Colors.TextPrimary
		nameBox.Text = party.name
		nameBox.PlaceholderText = "Party name"
		nameBox.ClearTextOnFocus = false
		nameBox.TextXAlignment = Enum.TextXAlignment.Left
		nameBox.LayoutOrder = rowOrder
		local nbCorner = Instance.new("UICorner")
		nbCorner.CornerRadius = Theme.CornerRadius.md
		nbCorner.Parent = nameBox
		local nbPad = Instance.new("UIPadding")
		nbPad.PaddingLeft = UDim.new(0, 8)
		nbPad.PaddingRight = UDim.new(0, 8)
		nbPad.Parent = nameBox
		nameBox.Parent = content
		nameBox.FocusLost:Connect(function()
			local r = call(GuildEvents.SetPartyName, selectedParty, nameBox.Text)
			if r then invalidatePageCache() setStatus("Party renamed") end
		end)

		local count = 0
		for _ in partyEdit do count += 1 end

		for _, u in ipairs(res.roster or {}) do
			local uid = u.id
			local inParty = partyEdit[uid] == true
			if u.away then
				addRow(`{u.name}  Lv{u.unitLevel}  |  AWAY`, nil, true)
			else
				addRow(`{u.name}  Lv{u.unitLevel}{inParty and "  [IN PARTY]" or ""}`, {
					{ text = inParty and "Remove" or "Add", color = inParty and Theme.Colors.Warning or Theme.Colors.Info,
					  enabled = inParty or count < maxSize, onTap = function()
						if inParty then
							partyEdit[uid] = nil
						elseif count < maxSize then
							partyEdit[uid] = true
						else
							setStatus(`A party holds up to {maxSize} units`, true)
							return
						end
						local ids = {}
						for id in partyEdit do table.insert(ids, id) end
						call(GuildEvents.SetPartyMembers, selectedParty, ids)
						showPage("Party")
					end },
				})
			end
		end

		addRow("", {
			{ text = "Back", color = Theme.Colors.Surface, onTap = function()
				selectedParty = nil
				invalidatePageCache()
				showPage("Party")
			end },
		})
	end
end

-- Embark button cycling-text machinery (reuses the scout-token pattern). The button lives
-- in the wiped-each-render content area, so the loop re-grabs the live button and self-cancels
-- when the token advances, the button is destroyed, or scouting finishes. (2026-10-16)
local embarkButton: TextButton? = nil
local embarkToken = 0
local EMBARK_PHRASES = { "Scouting the area", "Mapping the location", "Locating the target", "Scanning the terrain" }

local function pageAdventurersGuild()
	addHeading("ADVENTURER'S GUILD")
	embarkButton = nil  -- content was just wiped; drop any stale reference

	if sortieMode and chosenQuest then
		local q = chosenQuest

		if guildSortieStep == "details" then
			addNote(`{q.name}`)
			addNote(`Location: {q.biome}   Recommended Lv {q.recommendedLvl}`)
			addNote(`Enemies: {q.enemyCount}   Difficulty: {tostring(q.difficulty or "?")}`)
			local g = q.rewards and q.rewards.gold
			if g then
				addNote("Reward gold: " .. ((g.min == g.max) and (g.min .. " + kills") or (g.min .. "-" .. g.max)))
			end
			if q.rewards and q.rewards.drops then addNote(`Item drops: {q.rewards.drops}`) end
			if q.condition then addNote(`Condition: {q.condition}`) end
			addNote(`Deploy up to {q.playerSlots} units`)
			addRow("", {
				{ text = "Back", color = Theme.Colors.Surface, onTap = function()
					guildSortieStep = "overview"
					showPage("Adventurers")
				end },
			})
			return
		end

		if guildSortieStep == "sortie" then
			local pName = sortiePartyName or "your party"
			addRow(`Party: {pName}`, {
				{ text = "Change party", color = Theme.Colors.Info, onTap = function()
					showPage("Party")
				end },
			})
			-- Embark: clickable immediately. If the map is not ready (sortieLocked) the label cycles
			-- loading phrases and the tap defers -- MapBuildComplete fires StartBattle automatically.
			rowOrder += 1
			local btn = makeButton(content, sortieLocked and (EMBARK_PHRASES[1] .. "...") or "Embark", Theme.Colors.Success, function()
				if sortieLocked then
					departPending = true
					if embarkButton then embarkButton.Text = "Departing when ready..." end
					setStatus("The party will move out as soon as scouting is done.")
				else
					screenGui.Enabled = false
					BattleEvents.StartBattle:FireServer()
				end
			end)
			btn.Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT + 8)
			btn.LayoutOrder = rowOrder
			embarkButton = btn
			if sortieLocked then
				embarkToken += 1
				local myTok = embarkToken
				task.spawn(function()
					local idx = 1
					while myTok == embarkToken and sortieLocked and embarkButton == btn and btn.Parent do
						btn.Text = departPending and "Departing when ready..." or (EMBARK_PHRASES[idx] .. "...")
						idx = (idx % #EMBARK_PHRASES) + 1
						task.wait(2)
					end
				end)
			end
			addRow("", {
				{ text = "Back", color = Theme.Colors.Surface, onTap = function()
					guildSortieStep = "overview"
					showPage("Adventurers")
				end },
			})
			return
		end

		-- overview: details / sortie / abandon
		addNote(`Accepted: {q.name}. Prepare your party, then sortie when ready.`)
		addRow("See the full brief for this quest", {
			{ text = "Quest details", color = Theme.Colors.Info, onTap = function()
				guildSortieStep = "details"
				showPage("Adventurers")
			end },
		})
		addRow("Set out -- choose your party, then embark", {
			{ text = "Sortie", color = Theme.Colors.Success, onTap = function()
				guildSortieStep = "sortie"
				showPage("Adventurers")
			end },
		})
		addRow("Abandoning forfeits half the posted gold.", {
			{ text = "Abandon quest", color = Theme.Colors.Warning, onTap = function()
				BattleEvents.AbandonQuest:FireServer()
			end },
		})
		return
	end

	-- board: list the offered quests. Choosing one accepts it (fires QuestSelected -> the server
	-- starts building the map); the server re-opens the menu in PreBattle and we land on overview.
	if not guildQuests then
		addNote("Consulting the board for available quests...")
		return
	end
	addNote("Choose a quest to embark on, or head back to base.")
	for _, q in ipairs(guildQuests) do
		local quest = q
		local g = q.rewards and q.rewards.gold
		local goldText = ""
		if g then goldText = (g.min == g.max) and (`{g.min} gold + kills`) or (`{g.min}-{g.max} gold`) end
		local line = `{q.name}\n{q.biome}  Lv {q.recommendedLvl}  |  {q.enemyCount} enemies  |  {goldText}  |  Deploy {q.playerSlots}`
		addRow(line, {
			{ text = "Select", color = Theme.Colors.Success, onTap = function()
				chosenQuest = quest
				guildSortieStep = "overview"
				departPending = false
				BattleEvents.QuestSelected:FireServer({ questId = quest.id })
			end },
		})
	end
	addRow("Not today", {
		{ text = "Back", color = Theme.Colors.Surface, onTap = function()
			BattleEvents.QuestBoardCancel:FireServer()
			guildQuests = nil
			showPage("Units")
		end },
	})
end

local PAGES: { [string]: () -> () } = {
	-- Tavern and Merchant are their own screens (openTavern / openMerchant), 2026-10-31.
	-- Merchant is its own screen (openMerchant), not a page of this menu (2026-10-31).
	Blacksmith = pageBlacksmith,
	Dispatch = pageDispatch,
	Units = pageUnits,
	Party = pageParty,
	Adventurers = pageAdventurersGuild,
	-- Building levels moved to the always-on DEV TOOLS panel (2026-10-31).
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
	updateBalanceLabel()  -- reflect any staged changes in the header live (2026-10-14)
end

--------------------------------------------------
-- BUILDING BUTTONS
--------------------------------------------------

local navButtons: { GuiButton } = {}
local leaveButton: TextButton? = nil
local advGuildButton: TextButton? = nil
local changePartyButton: TextButton? = nil
local scoutToken = 0

local function buildNav()
	for _, b in navButtons do b:Destroy() end
	navButtons = {}
	table.clear(navPageOf) -- destroyed buttons must not stay referenced (PRF-004)
	local entries = {
		{ "Tavern", "Tavern" }, { "Merchant", "Merchant" }, { "Blacksmith", "Blacksmith" },
		{ "Dispatch", "Dispatch" }, { "Units", "Units" }, { "Party", "Party" },
	}
	for i, e in entries do
		local pageName = e[2]
		local btn: GuiButton = Theme.MakeTabButton(nav, e[1], "Inactive", function()
			-- PER-SCREEN KEEP/DISCARD (2026-10-14): switching screens with unsaved changes
			-- prompts Confirm/Discard FIRST, so changes can't pile across screens. Same-screen
			-- re-tap is a no-op (never prompts). Nothing pending -> switches instantly.
			if pageName == "Tavern" then
				-- Own full screen (2026-10-31): same keep/discard prompt first, then open it.
				confirmLeaveWithCart(function()
					setStatus("")
					openTavern()
				end)
				return
			end
			if pageName == "Merchant" then
				-- Own full screen (2026-10-31): same keep/discard prompt first, then open it.
				confirmLeaveWithCart(function()
					setStatus("")
					openMerchant()
				end)
				return
			end
			if currentPage == pageName then return end
			confirmLeaveWithCart(function()
				selectedMission = nil
				selectedParty = nil
				setStatus("")
				showPage(pageName)
			end)
		end, { name = "Nav_" .. pageName, size = UDim2.new(1, 0, 0, BUTTON_HEIGHT), layoutOrder = i,
			textSize = Theme.Text.Body() })
		registerNav(btn, pageName)
		table.insert(navButtons, btn)
	end
	-- Adventurer's Guild: opens the quest board (2026-10-12). Fires OpenAdventurersGuild;
	-- the server is waiting at the guild base and responds by showing the quest board.
	local advGuild = makeButton(nav, "Adventurer's Guild", Theme.Colors.Accent or Theme.Colors.Success, function()
		if isBusy then return end
		confirmLeaveWithCart(function()
			-- Open the in-menu Adventurer's Guild page. The server offers quests ONCE per base
			-- cycle (it stops listening for OpenAdventurersGuild after the first fire, then waits
			-- for the pick), so only REQUEST when we have no cached quests and are not mid-sortie.
			-- Re-tapping with quests already cached just re-renders them -- wiping + re-requesting
			-- would strand the page on "Consulting the board..." (2026-10-16 fix).
			if not sortieMode and guildQuests == nil then
				BattleEvents.OpenAdventurersGuild:FireServer()
			end
			showPage("Adventurers")
		end)
	end)
	advGuild.Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT)
	advGuild.LayoutOrder = 90
	advGuildButton = advGuild
	table.insert(navButtons, advGuild)

	-- Change party (sortie only): opens the Party tab to pick which saved party deploys.
	local changeParty = makeButton(nav, "Change party", Theme.Colors.Info, function()
		if isBusy then return end
		showPage("Party")
	end)
	changeParty.Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT)
	changeParty.LayoutOrder = 95
	changePartyButton = changeParty
	table.insert(navButtons, changeParty)

	local leave = makeButton(nav, "", Theme.Colors.Success, function()
		if isBusy or sortieLocked then return end
		confirmLeaveWithCart(function()
			screenGui.Enabled = false
			-- Same intention the old Loadout Hub sent; the server continues from there.
			BattleEvents.StartBattle:FireServer()
		end)
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

-- SCOUTING WAIT UX (2026-10-13): while the server builds the map after a quest pick, the
-- sortie button is locked and shows an animated "Scouting the battle map..." so the player
-- sees life instead of a frozen screen. Unlocks on BattleEvents.MapBuildComplete.
-- Resolve which saved party is selected for this sortie. Keeps the current pick if it
-- still has members; otherwise defaults to the first non-empty party (matches the
-- server's default). Pure client read of the cached GetParties response. (2026-10-15)
local function computeDefaultSortieParty()
	local res = cachedCall("Party", GuildEvents.GetParties)
	if not res then return end
	if sortiePartySlot then
		for _, p in ipairs(res.parties or {}) do
			if p.slot == sortiePartySlot then
				if #(p.members or {}) > 0 then sortiePartyName = p.name return end
				break
			end
		end
	end
	sortiePartySlot = nil
	sortiePartyName = nil
	for _, p in ipairs(res.parties or {}) do
		if #(p.members or {}) > 0 then
			sortiePartySlot = p.slot
			sortiePartyName = p.name
			return
		end
	end
end

local function stopScout()
	scoutToken += 1  -- invalidates any running animation loop
end

local function lockSortie()
	local lb = leaveButton
	if not lb then return end
	sortieLocked = true
	lb.AutoButtonColor = false
	lb.Active = false
	lb.BackgroundTransparency = 0.5
	lb.TextColor3 = Theme.Colors.TextDisabled
	local stroke = lb:FindFirstChild("Accent")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Color = Theme.Colors.Border
		stroke.Transparency = 0.4
	end
	scoutToken += 1
	local myToken = scoutToken
	task.spawn(function()
		local dots = 0
		while myToken == scoutToken do
			lb.Text = "Scouting the battle map" .. string.rep(".", dots)
			dots = (dots + 1) % 4
			task.wait(0.4)
		end
	end)
end

local function unlockSortie()
	local lb = leaveButton
	if not lb then return end
	sortieLocked = false
	stopScout()
	lb.AutoButtonColor = true
	lb.Active = true
	lb.BackgroundTransparency = 0.1
	lb.TextColor3 = Theme.Colors.TextPrimary
	local stroke = lb:FindFirstChild("Accent")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Color = Theme.Colors.Success
		stroke.Transparency = 0
	end
	updateSortieButton()
end

-- Reflect the chosen sortie party on the Continue button ("Continue - Party A"). Assigned
-- here, after leaveButton exists, into the forward-declared local. (2026-10-15)
updateSortieButton = function()
	local lb = leaveButton
	if not lb then return end
	if currentPhase == "PostBattle" then
		-- Battles auto-save (manual save step was removed), so the post-battle
		-- button just returns to the guild base — no "Save" wording. (2026-10-17)
		lb.Text = "Return to Base"
	else
		lb.Text = sortiePartyName and ("Continue - " .. sortiePartyName) or "Continue to Deployment"
	end
end

GuildEvents.GuildMenuOpened.OnClientEvent:Connect(function(data: any)
	-- A fresh menu open always starts on the menu itself, never inside a building screen.
	if MerchantScreen then MerchantScreen.Hide() end
	if TavernScreen then TavernScreen.Hide() end
	closeLeaveDialog() -- a leftover Confirm/Discard/Cancel prompt must not reappear later
	currentPhase = (type(data) == "table" and type(data.phase) == "string") and data.phase or "PreBattle"
	-- Button visibility by phase (2026-10-13 fix for the "Continue to Deployment at the
	-- base" crash): at the Base hub the ONLY way to start something is the Adventurer's
	-- Guild (which launches the quest activity); there is no quest/map yet, so the deploy
	-- button must NOT appear. "Continue to Deployment" belongs only at the sortie briefing
	-- (PreBattle); "Save & Finish" only after a battle (PostBattle).
	local atBase = (currentPhase == "Base")
	if advGuildButton then
		-- Visible at the base AND during the sortie (PreBattle), so after visiting another tab
		-- (Units/Tavern/etc.) the player can return to the Adventurer's Guild sortie screen.
		-- Hidden only PostBattle. (2026-10-16 fix: button vanished at sortie, stranding the
		-- player with no way back to Sortie/Abandon after leaving the screen.)
		advGuildButton.Visible = (currentPhase == "Base" or currentPhase == "PreBattle")
	end
	if leaveButton then
		-- Deprecated 2026-10-16: the sortie Depart control now lives IN the Adventurer's Guild
		-- page. leaveButton is kept only as the scout-lock state carrier (lockSortie/unlockSortie
		-- toggle sortieLocked through it), so it stays hidden but must keep existing.
		leaveButton.Visible = false
		if not atBase then
			local scouting = (type(data) == "table" and data.scouting == true)
			if scouting then
				lockSortie()   -- shows "Scouting the battle map..."; unlocks on MapBuildComplete
			else
				unlockSortie()
			end
		end
	end
	selectedMission = nil
	selectedUnits = {}
	selectedParty = nil
	setStatus("")
	screenGui.Enabled = true
	invalidatePageCache()  -- server state changed; next render re-fetches fresh
	refreshOverview()
	-- Sortie party display (2026-10-15): the Change-party button shows only at the sortie;
	-- entering PreBattle resets to the default party (first non-empty) so the Continue
	-- button reflects it once the map finishes scouting (unlockSortie -> updateSortieButton).
	if changePartyButton then
		-- Deprecated 2026-10-16: "Change party" now lives in the Adventurer's Guild sortie step.
		changePartyButton.Visible = false
	end
	if currentPhase == "PreBattle" then
		sortieMode = true
		-- Adopt the quest from the PreBattle payload if the client never captured it via a
		-- "Choose" tap (fallback pick / old path). Without this the sortie page guard
		-- (sortieMode and chosenQuest) failed and the screen fell through to an empty board
		-- = the "guild screen disappeared after choosing a quest" bug. (2026-10-16)
		if type(data) == "table" and type(data.quest) == "table" then
			chosenQuest = data.quest
		end
		if guildSortieStep ~= "sortie" and guildSortieStep ~= "details" then
			guildSortieStep = "overview"
		end
		sortiePartySlot = nil
		computeDefaultSortieParty()
		if not sortieLocked then updateSortieButton() end
	else
		sortieMode = false
	end
	if currentPhase == "Base" then
		-- Fresh base cycle: drop last cycle's quests so the next Adventurer's Guild tap
		-- re-requests from the server (which is back to listening at the activity wait).
		guildQuests = nil
	end
	-- Sortie lands on the in-screen Adventurer's Guild page (sortie controls); otherwise
	-- the base opens on Units. (2026-10-16)
	showPage(sortieMode and "Adventurers" or "Units")
	print(`[GuildMenu] Opened ({currentPhase})`)
end)

GuildEvents.GuildMenuClosed.OnClientEvent:Connect(function()
	stopScout()  -- end any running scouting animation
	if MerchantScreen then MerchantScreen.Hide() end -- the building screen closes with the menu
	if TavernScreen then TavernScreen.Hide() end
	closeLeaveDialog() -- and so does any open Confirm/Discard/Cancel prompt
	-- Pending changes never outlive the menu (Tester D-1, 2026-10-31).
	local pendingCount = cartCount()
	if pendingCount > 0 then
		warn(`[GuildMenu] Menu closed with {pendingCount} pending change(s) -- discarded`)
		cartBuys = {}
		cartSells = {}
		cartUpgrades = {}
		cartDowngrades = {}
		cartDispatches = {}
		cartHires = {}
	end
	screenGui.Enabled = false
	print("[GuildMenu] Closed")
end)

-- Battle prep finished on the server: end scouting, unlock the sortie button. Also refresh
-- the Adventurer's Guild page so its Depart button flips from "Scouting..." to live. (2026-10-16)
if BattleEvents.MapBuildComplete then
	BattleEvents.MapBuildComplete.OnClientEvent:Connect(function()
		unlockSortie()
		-- If the player already tapped Embark during scouting, depart now (deferred-embark).
		if departPending then
			departPending = false
			-- Deferred departure follows the same Confirm/Discard rule as every other exit
			-- (Tester D-1, 2026-10-31): changes made while scouting never ride into the battle.
			-- Cancel stays at the base; tapping Embark again leaves.
			if cartCount() > 0 and sortieMode and currentPage == "Adventurers" then
				showPage("Adventurers") -- Embark shows live again if the player cancels
			end
			confirmLeaveWithCart(function()
				if MerchantScreen then MerchantScreen.Hide() end
				if TavernScreen then TavernScreen.Hide() end
				screenGui.Enabled = false
				BattleEvents.StartBattle:FireServer()
			end)
			return
		end
		if sortieMode and currentPage == "Adventurers" then showPage("Adventurers") end
	end)
end

-- Quests offered by the server (QuestBoardOpen). The quest board is now an in-menu page,
-- so store the quests and re-render the Adventurer's Guild page if the player is on it
-- (quest-selection mode). The old standalone QuestBoardUI screen is retired. (2026-10-16)
BattleEvents.QuestBoardOpen.OnClientEvent:Connect(function(data)
	if data and data.quests then
		guildQuests = data.quests
		sortieMode = false
		if currentPage == "Adventurers" then showPage("Adventurers") end
	end
end)

print("[GuildMenu] Ready — waiting for GuildMenuOpened")
