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
local GuiService        = game:GetService("GuiService")

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
-- Blacksmith is its own full screen too (v2 build step 3, 2026-11-01).
local blacksmithScreenModule = UIFolder:WaitForChild("BlacksmithScreen", WAIT)
if not blacksmithScreenModule then warn("[GuildMenu] BlacksmithScreen module missing") end
local BlacksmithScreen: any = if blacksmithScreenModule then (require :: any)(blacksmithScreenModule) else nil
-- Runeforge is its own full screen too (v2 build step 5, 2026-11-01).
local runeforgeScreenModule = UIFolder:WaitForChild("RuneforgeScreen", WAIT)
if not runeforgeScreenModule then warn("[GuildMenu] RuneforgeScreen module missing") end
local RuneforgeScreen: any = if runeforgeScreenModule then (require :: any)(runeforgeScreenModule) else nil
-- Crucible gear merging (2026-11-02): its own full screen too.
local crucibleScreenModule = UIFolder:WaitForChild("CrucibleScreen", WAIT)
if not crucibleScreenModule then warn("[GuildMenu] CrucibleScreen module missing") end
local CrucibleScreen: any = if crucibleScreenModule then (require :: any)(crucibleScreenModule) else nil
-- Apothecary consumables (2026-11-03): its own full screen too.
local apothecaryScreenModule = UIFolder:WaitForChild("ApothecaryScreen", WAIT)
if not apothecaryScreenModule then warn("[GuildMenu] ApothecaryScreen module missing") end
local ApothecaryScreen: any = if apothecaryScreenModule then (require :: any)(apothecaryScreenModule) else nil
-- Training Grounds card shop (2026-11-04): its own full screen too.
local tgScreenModule = UIFolder:WaitForChild("TrainingGroundsScreen", WAIT)
if not tgScreenModule then warn("[GuildMenu] TrainingGroundsScreen module missing") end
local TrainingGroundsScreen: any = if tgScreenModule then (require :: any)(tgScreenModule) else nil
-- Dispatch (2026-11-11, user-approved layout): its own full screen too.
local dispatchScreenModule = UIFolder:WaitForChild("DispatchScreen", WAIT)
if not dispatchScreenModule then warn("[GuildMenu] DispatchScreen module missing") end
local DispatchScreen: any = if dispatchScreenModule then (require :: any)(dispatchScreenModule) else nil
-- Units (2026-11-13, user): its own full screen too.
local unitsScreenModule = UIFolder:WaitForChild("UnitsScreen", WAIT)
if not unitsScreenModule then warn("[GuildMenu] UnitsScreen module missing") end
local UnitsScreen: any = if unitsScreenModule then (require :: any)(unitsScreenModule) else nil
-- Furnish tab + furniture craft list (furniture v5 step 4a, 2026-11-16): own module.
local furnishScreenModule = UIFolder:WaitForChild("FurnishScreen", WAIT)
if not furnishScreenModule then warn("[GuildMenu] FurnishScreen module missing") end
local FurnishScreen: any = if furnishScreenModule then (require :: any)(furnishScreenModule) else nil
-- Guild Hall (user 2026-11-17 4:40 PM): its own full screen (Buildings + Furnish tabs, item tiles).
local guildHallScreenModule = UIFolder:WaitForChild("GuildHallScreen", WAIT)
if not guildHallScreenModule then warn("[GuildMenu] GuildHallScreen module missing") end
local GuildHallScreen: any = if guildHallScreenModule then (require :: any)(guildHallScreenModule) else nil
-- Dungeon (build step 5, 2026-11-13): its own full screen.
local dungeonScreenModule = UIFolder:WaitForChild("DungeonScreen", WAIT)
if not dungeonScreenModule then warn("[GuildMenu] DungeonScreen module missing") end
local DungeonScreen: any = if dungeonScreenModule then (require :: any)(dungeonScreenModule) else nil
local _dlMod = UIFolder:WaitForChild("DungeonLoading", WAIT)
local DungeonLoading: any = if _dlMod then (require :: any)(_dlMod) else nil -- battle loading panel (2026-11-17 10:50 AM)
if not DungeonLoading then warn("[GuildMenu] DungeonLoading module missing -- no battle loading panel") end
-- Always-on dev panel (2026-10-31): shop refresh, building levels, gold, saves.
-- Shown in Studio, or when the server marks this player as an allow-listed owner (the
-- "DevAccess" attribute, 2026-11-06). Display only: the server re-checks every dev request.
local DevToolsPanel: any = nil
local function devPanelAllowed(): boolean
	return RunService:IsStudio() or (Players.LocalPlayer :: Player):GetAttribute("DevAccess") == true
end
local function loadDevToolsPanel(): any
	if DevToolsPanel then return DevToolsPanel end
	local devModule = script.Parent:WaitForChild("DevToolsPanel", WAIT)
	if devModule then
		DevToolsPanel = (require :: any)(devModule)
	else
		warn("[GuildMenu] DevToolsPanel module missing")
	end
	return DevToolsPanel
end
if devPanelAllowed() then loadDevToolsPanel() end
-- Guild Hall furniture catalogue (Slice 8 step 2, 2026-11-16): names + effect lines for the Furnish tab.
local FurnitureData: any = nil
do
	local contentFolder = ReplicatedStorage:WaitForChild("Content", WAIT)
	local furnModule = contentFolder and contentFolder:WaitForChild("FurnitureData", WAIT)
	if furnModule then FurnitureData = (require :: any)(furnModule) else warn("[GuildMenu] FurnitureData module missing") end
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
local NAV_ICON_PX = BUTTON_HEIGHT - 8 -- building icons, 40 px (2026-11-13)

--------------------------------------------------
-- STATE
--------------------------------------------------

local currentPhase = "PreBattle"
local currentPage = "Units"
local isBusy = false
local sortiePartySlot: string? = nil   -- party chosen for THIS sortie (shown on Continue)
local sortiePartyName: string? = nil
local updateSortieButton: () -> () = function() end  -- reassigned once leaveButton exists
-- ADVENTURER'S GUILD screen (2026-10-16): the guild quest board is now an in-menu page
-- (like Tavern/Merchant), not a separate screen. guildQuests holds the server's offered
-- quests; sortieMode flips the page from quest-selection to sortie controls after a quest
-- is accepted (phase PreBattle). Base stays persistent -- the menu is never torn down.
local guildQuests: { any }? = nil
local newDayAt: number? = nil -- os.clock() time of the next 00:00 UTC (server-sent countdown)
local bossRewardsText: string? = nil -- "Boss rewards left today: N/3" (loot_progression 15)
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
-- staged dismantles (instanceId -> preview yield from the server), v2 step 2/3
local cartDismantles: { [string]: { name: string, mercury: number, crystals: number, sulfur: number, gems: number } } = {}
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

-- Guild crest left of "GUILD" (user ruling 2026-11-13 12:40 AM): Adventurer's Guild icon,
-- a square the full header height (Theme.GuildIcons, the one place for these ids).
local headerCrest = Instance.new("ImageLabel")
headerCrest.Name = "Crest"
headerCrest.BackgroundTransparency = 1
headerCrest.ScaleType = Enum.ScaleType.Fit
headerCrest.Image = Theme.GuildIcons.AdventurersGuild
headerCrest.Size = UDim2.fromScale(1, 1)
do
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 1
	ar.DominantAxis = Enum.DominantAxis.Height
	ar.Parent = headerCrest
end
headerCrest.Parent = header -- properties before Parent (NET-004)

local titleLabel = makeText(header, "GUILD", Theme.Text.Title(), Theme.Colors.TextGold, true)
titleLabel.Size = UDim2.fromScale(0.4, 0.6)
titleLabel.Font = Theme.Font.Display

local phaseLabel = makeText(header, "", Theme.Text.Small(), Theme.Colors.TextSecondary)
phaseLabel.Size = UDim2.fromScale(0.6, 0.4)
phaseLabel.Position = UDim2.fromScale(0, 0.6)
-- Auto-fit (user ruling 2026-11-12 7:40 PM): shrink the status line so it fits the header,
-- never below the 10 px phone text floor; anything still too long ends with "...".
phaseLabel.TextScaled = true
phaseLabel.TextTruncate = Enum.TextTruncate.AtEnd
do
	local fit = Instance.new("UITextSizeConstraint")
	fit.MaxTextSize = Theme.Text.Small()
	fit.MinTextSize = 10
	fit.Parent = phaseLabel
end

local balanceLabel = makeText(header, "", Theme.Text.Body(), Theme.Colors.TextPrimary, true)
balanceLabel.Size = UDim2.fromScale(0.6, 1)
balanceLabel.Position = UDim2.fromScale(0.4, 0)
balanceLabel.TextXAlignment = Enum.TextXAlignment.Right
-- Hidden since 2026-11-13: the header shows icon + number per currency (currencyUI below).
-- Its Text is still built, because the building screens read it through SetGold().
balanceLabel.Visible = false

-- Currencies, right side of the header (user ruling 2026-11-13 12:40 AM): Gold, Mercury,
-- Crystal, Sulfur, each as its icon + number (thousands separators). If staged "a -> b" values
-- would not fit the right 60%, the numbers step down in size (never below the 10 px floor), then
-- wrap to two rows; the strip clips, so it can never spill left over the Rank block.
-- Builder moved to the shared CurrencyStrip module (2026-11-17) so the dungeon header uses the same look.
local currencyStripModule = UIFolder:WaitForChild("CurrencyStrip", WAIT)
local CurrencyStrip: any = if currencyStripModule then (require :: any)(currencyStripModule) else nil
local currencyUI: { [string]: TextLabel } = {}
local fitCurrencies: () -> () = function() end
if CurrencyStrip then
	local cs = CurrencyStrip.Create(header, {
		keys = { "Gold", "Mercury", "Crystal", "Sulfur" },
		bottomKeys = { Crystal = true, Sulfur = true },
		size = UDim2.fromScale(0.6, 1), position = UDim2.fromScale(0.4, 0),
	})
	currencyUI = cs.Labels
	fitCurrencies = cs.Fit
else
	warn("[GuildMenu] CurrencyStrip module missing; header currencies hidden")
end

-- Renown Rank (step 2, USER RULING 2026-11-12, loot_progression 94): "Renown Rank 12" with a
-- progress bar "1,240 / 1,310 Renown", on the GUILD row, right of the title, inside the left 40%
-- (the gold line keeps the right 60%). Two stacked lines; the progress text sits on the bar.
-- Display only: the server sends rank / renown / need in the guild overview.
local renownUI = {}
do
	local block = Instance.new("Frame")
	block.Name = "Renown"
	block.BackgroundTransparency = 1
	block.BorderSizePixel = 0
	block.Size = UDim2.new(0.4, -60, 0.6, 0)
	block.Position = UDim2.fromOffset(56, 0)
	local function fitText(lbl: TextLabel)
		lbl.TextScaled = true
		lbl.TextTruncate = Enum.TextTruncate.AtEnd
		local c = Instance.new("UITextSizeConstraint")
		c.MaxTextSize = Theme.Text.Small()
		c.MinTextSize = 10 -- phone text floor (project_rules 244)
		c.Parent = lbl
	end
	local rankLabel = makeText(block, "", Theme.Text.Small(), Theme.Colors.TextGold, true)
	rankLabel.Name = "Rank"
	rankLabel.TextWrapped = false
	rankLabel.Size = UDim2.fromScale(1, 0.5)
	fitText(rankLabel)
	local track = Instance.new("Frame")
	track.Name = "Bar"
	track.BackgroundColor3 = Theme.Colors.Background
	track.BackgroundTransparency = 0.2
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Size = UDim2.new(1, 0, 0.5, -1)
	track.Position = UDim2.new(0, 0, 0.5, 1)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Theme.Colors.TextGold
	fill.BackgroundTransparency = 0.45
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = track
	local progressLabel = makeText(track, "", Theme.Text.Small(), Theme.Colors.TextPrimary, true)
	progressLabel.Name = "Progress"
	progressLabel.TextWrapped = false
	progressLabel.Size = UDim2.fromScale(1, 1)
	progressLabel.TextXAlignment = Enum.TextXAlignment.Center
	progressLabel.TextStrokeTransparency = 0.4
	progressLabel.ZIndex = 2
	fitText(progressLabel)
	track.Parent = block
	block.Visible = false -- until the first overview arrives
	block.Parent = header -- properties before Parent (NET-004)
	-- Keep the block just right of the "GUILD" text whatever its rendered width.
	-- Crest first, then "GUILD" and the status line right of it, then this block.
	local function place()
		local cw = headerCrest.AbsoluteSize.X + 6
		titleLabel.Position = UDim2.fromOffset(cw, 0)
		titleLabel.Size = UDim2.new(0.4, -cw, 0.6, 0)
		phaseLabel.Position = UDim2.new(0, cw, 0.6, 0)
		phaseLabel.Size = UDim2.new(0.4, -cw, 0.4, 0) -- left 40% only: the currencies own the right 60%
		local x = cw + titleLabel.TextBounds.X + 10
		block.Position = UDim2.fromOffset(x, 0)
		block.Size = UDim2.new(0.4, -(x + 4), 0.6, 0)
	end
	place()
	titleLabel:GetPropertyChangedSignal("TextBounds"):Connect(place)
	headerCrest:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	renownUI.block, renownUI.rank, renownUI.fill, renownUI.progress = block, rankLabel, fill, progressLabel
	-- Tap the Rank block = Renown help (user ruling 2026-11-13 3:01 PM; approved text, loot_progression 94).
	-- Tap anywhere on the popup to close it. One popup, created once; no per-tap connections.
	local help = Instance.new("TextButton")
	help.Name = "RenownHelp"
	help.Text = ""
	help.AutoButtonColor = false
	help.BackgroundColor3 = Color3.new(0, 0, 0)
	help.BackgroundTransparency = 0.45
	help.BorderSizePixel = 0
	help.Size = UDim2.fromScale(1, 1)
	help.ZIndex = 50
	help.Visible = false
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.new(0.6, 0, 0, 96)
	card.BackgroundColor3 = Theme.Colors.Surface
	card.BorderSizePixel = 0
	card.ZIndex = 51
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.TextGold
	stroke.Thickness = 2
	stroke.Parent = card
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
	pad.Parent = card
	local helpText = makeText(card, "Renown shows how well-known your guild is. Finish quests to earn it. A higher Rank brings harder quests, better gear upgrades and more room for recruits.", Theme.Text.Small(), Theme.Colors.TextPrimary)
	helpText.Name = "Text"
	helpText.Size = UDim2.fromScale(1, 1)
	helpText.TextWrapped = true
	helpText.TextXAlignment = Enum.TextXAlignment.Left
	helpText.TextYAlignment = Enum.TextYAlignment.Center
	helpText.ZIndex = 52
	do
		local c = Instance.new("UITextSizeConstraint")
		c.MaxTextSize = Theme.Text.Small(); c.MinTextSize = 10 -- phone text floor
		c.Parent = helpText
		helpText.TextScaled = true
	end
	card.Parent = help
	help.Parent = screenGui -- properties before Parent (NET-004)
	help.Activated:Connect(function() help.Visible = false end)
	local tap = Instance.new("TextButton")
	tap.Name = "RenownTap"
	tap.Text = ""
	tap.AutoButtonColor = false
	tap.BackgroundTransparency = 1
	tap.Size = UDim2.fromScale(1, 1)
	tap.ZIndex = 5
	tap.Parent = block
	tap.Activated:Connect(function() help.Visible = true end)
	renownUI.help = help
end

local function withCommas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function updateRenownHeader(r: any)
	if type(r) ~= "table" or type(r.rank) ~= "number" then
		renownUI.block.Visible = false
		return
	end
	local have = math.max(0, tonumber(r.renown) or 0)
	local need = math.max(1, tonumber(r.need) or 1)
	-- "Rank 12" / "1,240 / 1,310" (user ruling 2026-11-13 12:40 AM; was "Renown Rank 12" / "... Renown").
	renownUI.rank.Text = `Rank {r.rank}`
	renownUI.progress.Text = `{withCommas(have)} / {withCommas(need)}`
	renownUI.fill.Size = UDim2.fromScale(math.clamp(have / need, 0, 1), 1)
	renownUI.block.Visible = true
end

-- Roblox's top-left buttons (menu, chat, voice) always draw on top of game UI. Keep the header
-- clear of them, the same way the shared guild screens do (GuildScreen layout, TopbarInset).
-- Re-fit when the top bar changes (e.g. chat/voice buttons appear) and on every open.
local function fitHeaderToTopbar()
	local leftX = GuiService.TopbarInset.Min.X
	if leftX > 0 then leftX += Theme.TopbarReserve end -- Feedback button slot (2026-11-17)
	local gap = 8
	if leftX > 0 then
		header.Position = UDim2.new(0, leftX + gap, 0.02, 0)
		header.Size = UDim2.new(0.98, -(leftX + gap), 0.12, 0)
	else
		header.Position = UDim2.fromScale(0.02, 0.02)
		header.Size = UDim2.new(0.96, 0, 0.12, 0)
	end
end

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

-- Column fit (user 2026-11-13 1:25 PM): the right panel's left edge lines up with the header's
-- left edge (both edges match the header), and the nav takes the space to its left.
local function fitColumnsToHeader()
	local leftX = GuiService.TopbarInset.Min.X
	if leftX > 0 then leftX += Theme.TopbarReserve end -- same slot as fitHeaderToTopbar
	if leftX > 0 then
		local x = leftX + 8 -- header left edge (fitHeaderToTopbar)
		navFrame.Size = UDim2.new(-0.02, x - 8, 0.8, 0) -- nav starts at 0.02 scale, ends 8 px before the panel
		contentFrame.Position = UDim2.new(0, x, 0.16, 0)
		contentFrame.Size = UDim2.new(0.98, -x, 0.72, 0)
		statusLabel.Position = UDim2.new(0, x, 0.9, 0)
		statusLabel.Size = UDim2.new(0.98, -x, 0.07, 0)
	else
		navFrame.Size = UDim2.new(0.28, 0, 0.8, 0)
		contentFrame.Position = UDim2.fromScale(0.32, 0.16)
		contentFrame.Size = UDim2.new(0.66, 0, 0.72, 0)
		statusLabel.Position = UDim2.fromScale(0.32, 0.9)
		statusLabel.Size = UDim2.new(0.66, 0, 0.07, 0)
	end
end
local function fitLayoutToTopbar()
	fitHeaderToTopbar()
	fitColumnsToHeader()
end
fitLayoutToTopbar()
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(fitLayoutToTopbar)

local function setStatus(text: string, isError: boolean?)
	statusLabel.Text = text
	statusLabel.TextColor3 = isError and Theme.Colors.Danger or Theme.Colors.Success
	-- Mirror into an open building screen (the guild menu, and this line, are hidden then).
	if MerchantScreen then MerchantScreen.SetStatus(text, isError) end
	if TavernScreen then TavernScreen.SetStatus(text, isError) end
	if BlacksmithScreen then BlacksmithScreen.SetStatus(text, isError) end
	if RuneforgeScreen then RuneforgeScreen.SetStatus(text, isError) end
	if CrucibleScreen then CrucibleScreen.SetStatus(text, isError) end
	if ApothecaryScreen then ApothecaryScreen.SetStatus(text, isError) end
	if TrainingGroundsScreen then TrainingGroundsScreen.SetStatus(text, isError) end
	if DispatchScreen then DispatchScreen.SetStatus(text, isError) end
	if UnitsScreen then UnitsScreen.SetStatus(text, isError) end
	if DungeonScreen then DungeonScreen.SetStatus(text, isError) end
	if GuildHallScreen then GuildHallScreen.SetStatus(text, isError) end
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

-- Resource counters shown in the header (v2: dismantling gives crystals and sulfur).
local function resourcesText(res: any): string
	if type(res) ~= "table" then return "" end
	return `Mercury {res.mercury or 0}  Crystals {res.crystals or 0}  Sulfur {res.sulfur or 0}`
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
-- Header currency numbers (2026-11-13): "40,041", or "40,041 -> 39,991" while changes are staged.
local function setCurrency(key: string, now: number, delta: number)
	local lbl = currencyUI[key]
	if not lbl then return end
	lbl.Text = if delta ~= 0 then `{withCommas(now)} -> {withCommas(now + delta)}` else withCommas(now)
	fitCurrencies()
end

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
		or #cartDispatches > 0 or next(cartHires) ~= nil or next(cartDismantles) ~= nil
	if not staged then
		setCurrency("Gold", realGold, 0)
		setCurrency("Mercury", realRes.mercury or 0, 0)
		setCurrency("Crystal", realRes.crystals or 0, 0)
		setCurrency("Sulfur", realRes.sulfur or 0, 0)
		balanceLabel.Text = `Gold {realGold}   |   {resourcesText(realRes)}`
		if MerchantScreen then MerchantScreen.SetGold(balanceLabel.Text) end
		if TavernScreen then TavernScreen.SetGold(balanceLabel.Text) end
		if BlacksmithScreen then BlacksmithScreen.SetGold(balanceLabel.Text) end
		if RuneforgeScreen then RuneforgeScreen.SetGold(balanceLabel.Text) end
		if CrucibleScreen then CrucibleScreen.SetGold(balanceLabel.Text) end
		if ApothecaryScreen then ApothecaryScreen.SetGold(balanceLabel.Text) end
		if TrainingGroundsScreen then TrainingGroundsScreen.SetGold(balanceLabel.Text) end
		if DispatchScreen then DispatchScreen.SetGold(balanceLabel.Text) end if UnitsScreen then UnitsScreen.SetGold(balanceLabel.Text) end if DungeonScreen then DungeonScreen.SetGold(balanceLabel.Text); if DungeonScreen.SetCurrencies then DungeonScreen.SetCurrencies(realGold, realRes) end end if GuildHallScreen then GuildHallScreen.SetGold(balanceLabel.Text) end
		return
	end
	local projGold = realGold + goldDelta
	local goldStr = (goldDelta ~= 0) and `Gold {realGold} -> {projGold}` or `Gold {realGold}`
	-- Projected resources: mercury spent on upgrades, plus what staged dismantles give.
	local gain = { mercury = 0, crystals = 0, sulfur = 0 }
	for _, v in cartDismantles do
		gain.mercury += v.mercury or 0
		gain.crystals += v.crystals or 0
		gain.sulfur += v.sulfur or 0
	end
	local function proj(label: string, now: number, delta: number): string
		return if delta ~= 0 then `{label} {now} -> {now + delta}` else `{label} {now}`
	end
	local matStr = `   |   {proj("Mercury", realRes.mercury or 0, gain.mercury - mercurySpend)}`
		.. `  {proj("Crystals", realRes.crystals or 0, gain.crystals)}  {proj("Sulfur", realRes.sulfur or 0, gain.sulfur)}`
	balanceLabel.Text = goldStr .. matStr
	setCurrency("Gold", realGold, goldDelta)
	setCurrency("Mercury", realRes.mercury or 0, gain.mercury - mercurySpend)
	setCurrency("Crystal", realRes.crystals or 0, gain.crystals)
	setCurrency("Sulfur", realRes.sulfur or 0, gain.sulfur)
	if MerchantScreen then MerchantScreen.SetGold(balanceLabel.Text) end
	if TavernScreen then TavernScreen.SetGold(balanceLabel.Text) end
	if BlacksmithScreen then BlacksmithScreen.SetGold(balanceLabel.Text) end
	if RuneforgeScreen then RuneforgeScreen.SetGold(balanceLabel.Text) end
	if CrucibleScreen then CrucibleScreen.SetGold(balanceLabel.Text) end
	if ApothecaryScreen then ApothecaryScreen.SetGold(balanceLabel.Text) end
	if TrainingGroundsScreen then TrainingGroundsScreen.SetGold(balanceLabel.Text) end
	if DispatchScreen then DispatchScreen.SetGold(balanceLabel.Text) end if UnitsScreen then UnitsScreen.SetGold(balanceLabel.Text) end if DungeonScreen then DungeonScreen.SetGold(balanceLabel.Text); if DungeonScreen.SetCurrencies then DungeonScreen.SetCurrencies(realGold, realRes) end end if GuildHallScreen then GuildHallScreen.SetGold(balanceLabel.Text) end
end

-- Renown Rank unlocks (Slice 8 step 1, 2026-11-16): nav pages whose building is not open yet.
-- Filled from the overview's openBuildings; applyNavLocks is set once the nav exists.
local lockedPages: { [string]: any } = {}
local applyNavLocks: ((any) -> ())? = nil
local showLockLine: (string) -> () = function(_page: string) end -- set once the nav exists
local onGuildHallLink: () -> () = function() end -- 'Upgrade at the Guild Hall' link (set below)
local shownRefillNote = false -- reset each time the menu opens after a battle
local function refreshOverview()
	local res = call(GuildEvents.GetGuildOverview)
	if not res then return end
	lastOverview = { gold = res.gold or 0, resources = res.resources or {} }
	updateBalanceLabel()
	updateRenownHeader(res.renown)
	-- Apothecary refill on return to base (2026-11-03, gf 69): say what was not refilled.
	-- Base notes (refill + locked augment slots) are joined so one never hides the other.
	local notes = {}
	local lr = res.lastRefill
	if type(lr) == "table" and (lr.skippedCharges or 0) > 0 and not shownRefillNote then
		shownRefillNote = true
		table.insert(notes, `{lr.skippedCharges} consumable charges not refilled - need {lr.needGold}g`)
	end
	if type(res.augmentNotice) == "string" then table.insert(notes, res.augmentNotice) end
	if #notes > 0 then setStatus(table.concat(notes, "\n"), true) end
	local b = res.buildings or {}
	phaseLabel.Text = `{currentPhase == "PreBattle" and "Before battle" or "After battle"} | Battles done: {res.battlesCompleted or 0} | Tavern L{b.Tavern or 1}  Merchant L{b.Merchant or 1}  Blacksmith L{b.Blacksmith or 1}`
	if applyNavLocks and type(res.openBuildings) == "table" then applyNavLocks(res.openBuildings) end
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
	for _ in cartDismantles do n += 1 end
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
	local dismantles: { string } = {}
	for iid in cartDismantles do table.insert(dismantles, iid) end
	for idx in cartBuys do table.insert(buys, idx) end
	for cid in cartHires do table.insert(hires, cid) end
	for iid in cartSells do table.insert(sells, iid) end
	for iid, v in cartUpgrades do upgrades[iid] = v.toLevel end
	for iid, v in cartDowngrades do downgrades[iid] = v.toLevel end
	for _, d in cartDispatches do table.insert(dispatches, { missionId = d.missionId, unitIds = d.unitIds }) end
	if #buys == 0 and #sells == 0 and next(upgrades) == nil and next(downgrades) == nil and #dispatches == 0 and #hires == 0
		and #dismantles == 0 then
	setStatus("Nothing pending") return
	end
	isBusy = true
	local res = call(GuildEvents.FinalizeCart, { buys = buys, sells = sells, upgrades = upgrades, downgrades = downgrades, dispatches = dispatches, hires = hires, dismantles = dismantles })
	isBusy = false
	if res then
		cartBuys = {}
		cartSells = {}
		cartUpgrades = {}
		cartDowngrades = {}
		cartDispatches = {}
		cartHires = {}
		cartDismantles = {}
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
		local doneText = `Done -- bought {res.boughtCount or 0}, sold {res.soldCount or 0}, upgraded {res.upgradedCount or 0}, downgraded {res.downgradedCount or 0}, dismantled {res.dismantledCount or 0}, dispatched {res.dispatchedCount or 0}, hired {res.hiredCount or 0}. Gold {res.gold or 0}`
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
	cartDismantles = {}
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
	local nDis = 0
	for _ in cartDismantles do nDis += 1 end
	if nBuy + nSell + nUp + nDown + nDisp + nDis == 0 then return end
	local parts = {}
	if nBuy > 0 then table.insert(parts, `buy {nBuy}`) end
	if nSell > 0 then table.insert(parts, `sell {nSell}`) end
	if nUp > 0 then table.insert(parts, `upgrade {nUp}`) end
	if nDown > 0 then table.insert(parts, `downgrade {nDown}`) end
	if nDisp > 0 then table.insert(parts, `dispatch {nDisp}`) end
	if nDis > 0 then table.insert(parts, `dismantle {nDis}`) end
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
	local nDis = 0
	for _ in cartDismantles do nDis += 1 end
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
	local host: Instance? = (MerchantScreen and MerchantScreen.GetGui()) or (TavernScreen and TavernScreen.GetGui())
		or (BlacksmithScreen and BlacksmithScreen.GetGui()) or (RuneforgeScreen and RuneforgeScreen.GetGui())
		or (CrucibleScreen and CrucibleScreen.GetGui())
		or (ApothecaryScreen and ApothecaryScreen.GetGui())
		or (TrainingGroundsScreen and TrainingGroundsScreen.GetGui())
		or (DispatchScreen and DispatchScreen.GetGui()) or (UnitsScreen and UnitsScreen.GetGui())
		or (DungeonScreen and DungeonScreen.GetGui()) or (GuildHallScreen and GuildHallScreen.GetGui()) or nil
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
	local msg = makeText(box, `Unsaved changes -- buy {nBuy}, sell {nSell}, hire {nHire}, upgrade {nUp}, downgrade {nDown}, dismantle {nDis}, dispatch {nDisp}. Confirm or discard?`, Theme.Text.Body(), Theme.Colors.TextPrimary, true)
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
		cartDismantles = {}
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
					cartDismantles[key] = nil -- sell OR dismantle, never both (guild_facilities 52)
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

-- BLACKSMITH SCREEN (v2 build step 3, 2026-11-01): same model as the Merchant. Staged level
-- changes and dismantles stay in this menu's basket (cartUpgrades / cartDowngrades /
-- cartDismantles); Confirm sends only instance ids and target levels, the server re-prices.
local function openBlacksmith()
	if not BlacksmithScreen then
		setStatus("Blacksmith screen not loaded", true)
		return
	end
	screenGui.Enabled = false
	BlacksmithScreen.Open()
	updateBalanceLabel()
end

-- Gold + mercury to raise `it` to `target` (sum of the server's per-level curve).
local function bsCostTo(it: any, target: number): (number, number)
	local gold, mercury = 0, 0
	for _, step in it.upgradeCurve or {} do
		if step.toLevel <= target then
			gold += step.gold or 0
			mercury += step.mercury or 1
		end
	end
	return gold, mercury
end

if BlacksmithScreen then
	BlacksmithScreen.Init({
		parent = playerGui,
		getItems = function(): any?
			return cachedCall("Blacksmith", GuildEvents.GetBlacksmithItems)
		end,
		stagedLevel = function(it: any): number
			local up = cartUpgrades[it.instanceId]
			if up then return up.toLevel end
			local down = cartDowngrades[it.instanceId]
			if down then return down.toLevel end
			return it.level
		end,
		setTarget = function(it: any, target: number)
			local iid = it.instanceId
			local maxLevel = it.level + #(it.upgradeCurve or {})
			local t = math.clamp(math.floor(target), 1, math.max(it.level, maxLevel))
			cartUpgrades[iid] = nil
			cartDowngrades[iid] = nil
			if t > it.level then
				local g, m = bsCostTo(it, t)
				cartUpgrades[iid] = { name = it.name, fromLevel = it.level, toLevel = t, gold = g, mercury = m }
				cartDismantles[iid] = nil
			elseif t < it.level then
				cartDowngrades[iid] = { name = it.name, toLevel = t }
				cartDismantles[iid] = nil
			end
			updateBalanceLabel()
		end,
		-- Mercury is a shared pool across staged items: subtract what OTHER items reserve.
		maxAffordable = function(it: any): number
			local remaining = (lastOverview.resources and lastOverview.resources.mercury) or 0
			for otherId, up in cartUpgrades do
				if otherId ~= it.instanceId then remaining -= (up.mercury or 0) end
			end
			local best, run = it.level, 0
			for _, step in it.upgradeCurve or {} do
				run += step.mercury or 1
				if run <= remaining then best = step.toLevel else break end
			end
			return best
		end,
		isDismantleQueued = function(instanceId: string): boolean
			return cartDismantles[instanceId] ~= nil
		end,
		toggleDismantle = function(it: any)
			local iid = it.instanceId
			if cartDismantles[iid] then
				cartDismantles[iid] = nil
			elseif it.canDismantle and it.dismantle then
				local y = it.dismantle
				cartDismantles[iid] = { name = it.name, mercury = y.mercury or 0, crystals = y.crystals or 0,
					sulfur = y.sulfur or 0, gems = y.gemCount or 0 }
				cartUpgrades[iid] = nil   -- one change per item (guild_facilities 52)
				cartDowngrades[iid] = nil
				cartSells[iid] = nil      -- sell OR dismantle, never both
			end
			updateBalanceLabel()
		end,
		pendingCount = cartCount,
		summary = function(): any
			local s = { nUp = 0, upGold = 0, upMercury = 0, nDown = 0, nDis = 0,
				gain = { mercury = 0, crystals = 0, sulfur = 0, gems = 0 } }
			for _, v in cartUpgrades do
				s.nUp += 1
				s.upGold += v.gold or 0
				s.upMercury += v.mercury or 0
			end
			for _ in cartDowngrades do s.nDown += 1 end
			for _, v in cartDismantles do
				s.nDis += 1
				s.gain.mercury += v.mercury
				s.gain.crystals += v.crystals
				s.gain.sulfur += v.sulfur
				s.gain.gems += v.gems
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

-- RUNEFORGE SCREEN (v2 build step 5, 2026-11-01). Forging and rerolling commit straight away
-- on the screen's Confirm prompt (no basket). The client sends ids only; the server prices.
local function openRuneforge()
	if not RuneforgeScreen then
		setStatus("Runeforge screen not loaded", true)
		return
	end
	screenGui.Enabled = false
	RuneforgeScreen.Open()
	updateBalanceLabel()
end

if RuneforgeScreen then
	RuneforgeScreen.Init({
		parent = playerGui,
		getState = function(): any?
			return cachedCall("Runeforge", GuildEvents.GetRuneforge)
		end,
		preview = function(instanceId: string, installs: { any }): any?
			return call(GuildEvents.PreviewForge, instanceId, installs)
		end,
		-- Quiet: a refused or failed check only means "don't grey anything out" (no red status).
		checkGems = function(instanceId: string, installs: { any }, candidates: { any }): any?
			local remote = GuildEvents.CheckForgeGems
			if not remote then return nil end
			local ok, res = pcall(remote.InvokeServer, remote, instanceId, installs, candidates)
			if not ok or type(res) ~= "table" or res.ok ~= true or type(res.fits) ~= "table" then return nil end
			-- fits = { [i] = true | reason }, over = { [i] = points over budget }, budget = { used, max }
			return { fits = res.fits, over = if type(res.over) == "table" then res.over else {},
				budget = if type(res.budget) == "table" then res.budget else nil }
		end,
		commitForge = function(instanceId: string, installs: { any }): any?
			local res = call(GuildEvents.CommitForge, instanceId, installs)
			if res then setStatus(`Forged: {res.name} is now {res.newRarity}`) end
			return res
		end,
		getRerollSets = function(instanceId: string): any?
			return call(GuildEvents.GetRerollSets, instanceId)
		end,
		-- Pay first (2026-11-07): the answer holds the new sets (same shape as getRerollSets).
		payReroll = function(instanceId: string): any?
			local res = call(GuildEvents.PayReroll, instanceId)
			if res then setStatus(`Paid {res.sulfur} sulfur: pick a new set or keep the current lines`) end
			return res
		end,
		commitReroll = function(instanceId: string, choice: number): any?
			local res = call(GuildEvents.CommitReroll, instanceId, choice)
			if res then
				setStatus(if res.choice == 0 then `Rerolled: kept the current lines of {res.name}` else `Rerolled: {res.name}`)
			end
			return res
		end,
		-- NEW badge (2026-11-08): server checks ownership and clears the flag; fire-and-forget.
		markSeen = function(instanceId: string)
			local remote = BattleEvents.MarkItemSeen
			if remote then remote:FireServer(instanceId) end
		end,
		-- Gem Craft tab (2026-11-12): ids + a count only; the server prices, checks and rolls.
		-- No success text (approved wording only); a refusal shows the server's reason.
		craftGems = function(req: any): any?
			return call(GuildEvents.CraftGems, req)
		end,
		onChanged = function()
			invalidatePageCache() -- forge / reroll changed items, gems and resources
			refreshOverview()
		end,
		onClosed = function()
			screenGui.Enabled = true
			updateBalanceLabel()
			showPage(currentPage)
		end,
	})
end

-- CRUCIBLE SCREEN (gear merging, 2026-11-02). Merges commit straight away on the screen's
-- Confirm prompt (no basket). The client sends instance IDs only; the server prices.
local function openCrucible()
	if not CrucibleScreen then
		setStatus("Crucible screen not loaded", true)
		return
	end
	screenGui.Enabled = false
	CrucibleScreen.Open()
	updateBalanceLabel()
end

if CrucibleScreen then
	CrucibleScreen.Init({
		parent = playerGui,
		getState = function(): any?
			return cachedCall("Crucible", GuildEvents.GetCrucible)
		end,
		preview = function(ids: { string }): any?
			return call(GuildEvents.PreviewMerge, ids)
		end,
		commit = function(ids: { string }): any?
			local res = call(GuildEvents.CommitMerge, ids)
			if res then setStatus(`Merged: {res.name} ({res.rarity}, level {res.level})`) end
			return res
		end,
		onChanged = function()
			invalidatePageCache() -- a merge changed items and resources
			refreshOverview()
		end,
		onClosed = function()
			screenGui.Enabled = true
			updateBalanceLabel()
			showPage(currentPage)
		end,
	})
end

-- APOTHECARY SCREEN (consumables, 2026-11-03). Buys/sells commit straight away on the screen's
-- Confirm prompt (no basket). The client sends slots / ids only; the server prices.
local function openApothecary()
	if not ApothecaryScreen then
		setStatus("Apothecary screen not loaded", true)
		return
	end
	screenGui.Enabled = false
	ApothecaryScreen.Open()
	updateBalanceLabel()
end

if ApothecaryScreen then
	ApothecaryScreen.Init({
		parent = playerGui,
		getState = function(): any?
			return cachedCall("Apothecary", GuildEvents.GetApothecary)
		end,
		commit = function(cart: any): any?
			local res = call(GuildEvents.CommitApothecary, cart)
			if res and res.result then
				local r = res.result
				setStatus(if r.bought > 0 then `Bought for {r.cost} gold` else `Sold for {r.gain} gold`)
			end
			return res
		end,
		refill = function(cmd: any): any?
			return call(GuildEvents.ApothecaryRefill, cmd)
		end,
		onChanged = function()
			invalidatePageCache() -- gold and owned consumables changed
			refreshOverview()
		end,
		onClosed = function()
			screenGui.Enabled = true
			updateBalanceLabel()
			showPage(currentPage)
		end,
	})
end

-- UGC MERCHANT (2026-11-05, user): opens the same screen as the Loadout Outfit tab shortcut.
local ugcMerchantModule = UIFolder:FindFirstChild("UGCMerchantScreen")
local okUgc, UGCMerchantScreen = false, nil :: any
if ugcMerchantModule then okUgc, UGCMerchantScreen = pcall(require, ugcMerchantModule) end
if not okUgc then
	warn("[GuildMenu] UGCMerchantScreen unavailable: " .. tostring(UGCMerchantScreen))
	UGCMerchantScreen = nil
end
local guildMenuIsOpen = true -- false between GuildMenuClosed and the next GuildMenuOpened
local function openUGCMerchant()
	if not UGCMerchantScreen then
		setStatus("UGC Merchant screen not loaded", true)
		return
	end
	screenGui.Enabled = false
	UGCMerchantScreen.Open({ onClose = function()
		if not guildMenuIsOpen then return end -- closed by the server meanwhile: stay hidden
		screenGui.Enabled = true
		refreshOverview()
		showPage(currentPage)
	end })
end

-- TRAINING GROUNDS SCREEN (card shop, 2026-11-04). One card per Confirm prompt (no basket).
local function openTrainingGrounds()
	if not TrainingGroundsScreen then
		setStatus("Training Grounds screen not loaded", true)
		return
	end
	screenGui.Enabled = false
	TrainingGroundsScreen.Open()
	updateBalanceLabel()
end

if TrainingGroundsScreen then
	TrainingGroundsScreen.Init({
		parent = playerGui,
		getState = function(): any?
			return cachedCall("TrainingGrounds", GuildEvents.GetCardShop)
		end,
		action = function(cmd: any): any?
			local res = call(GuildEvents.CardShopAction, cmd)
			if res and res.result then
				local r = res.result
				setStatus(if r.cost then `Bought for {r.cost} gold` else `Sold for {r.gain} gold`)
			end
			return res
		end,
		onChanged = function()
			invalidatePageCache() -- gold and cards changed
			refreshOverview()
		end,
		onClosed = function()
			screenGui.Enabled = true
			updateBalanceLabel()
			showPage(currentPage)
		end,
	})
end

-- DISPATCH SCREEN (2026-11-11, user-approved layout): same model as the Tavern. Staged
-- dispatches stay in this menu's basket (cartDispatches); Confirm sends only mission and unit
-- ids, and the server re-checks slots, units and the keep-one-home rule.
local function openDispatch()
	if not DispatchScreen then
		setStatus("Dispatch screen not loaded", true)
		return
	end
	screenGui.Enabled = false
	DispatchScreen.Open()
	updateBalanceLabel()
end

if DispatchScreen then
	DispatchScreen.Init({
		parent = playerGui,
		getBoard = function(): any?
			return cachedCall("Dispatch", GuildEvents.GetDispatchBoard)
		end,
		getStaged = function(): { any }
			return cartDispatches
		end,
		queue = function(missionId: string, unitIds: { string }, fee: number)
			table.insert(cartDispatches, { missionId = missionId, unitIds = unitIds, fee = fee })
			updateBalanceLabel()
		end,
		pendingCount = cartCount,
		-- Dispatch Recall (2026-11-12): a live action (not staged in the cart). Returns the
		-- server answer, or nil on refusal (call() already showed the error).
		recall = function(missionId: string): any?
			local res = call(GuildEvents.RecallDispatch, missionId)
			if res then invalidatePageCache() end -- units came home: re-fetch the board
			updateBalanceLabel()
			return res
		end,
		requestBack = confirmLeaveWithCart,
		onClosed = function()
			screenGui.Enabled = true
			updateBalanceLabel()
			showPage(currentPage)
		end,
		setStatus = setStatus,
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
	elseif BlacksmithScreen and BlacksmithScreen.IsOpen() then
		BlacksmithScreen.Render()
	elseif RuneforgeScreen and RuneforgeScreen.IsOpen() then
		RuneforgeScreen.Render()
	elseif CrucibleScreen and CrucibleScreen.IsOpen() then
		CrucibleScreen.Render()
	elseif ApothecaryScreen and ApothecaryScreen.IsOpen() then
		ApothecaryScreen.Render()
	elseif TrainingGroundsScreen and TrainingGroundsScreen.IsOpen() then
		TrainingGroundsScreen.Render()
	elseif DispatchScreen and DispatchScreen.IsOpen() then
		DispatchScreen.Render()
	elseif GuildHallScreen and GuildHallScreen.IsOpen() then
		GuildHallScreen.Render()
	elseif screenGui.Enabled then
		showPage(currentPage)
	end
	local note = if dropped > 0 then ` | {dropped} pending buy/hire/dispatch dropped` else ""
	setStatus(`Dev: {what}{note}`)
end

local devPanelInited = false
local function initDevPanel()
	if devPanelInited or not devPanelAllowed() then return end
	local panel = loadDevToolsPanel()
	if not panel then return end
	devPanelInited = true
	panel.Init({
		parent = playerGui,
		devGuild = GuildEvents.DevGuild,
		devCommand = BattleEvents.DevCommand,
		onShopsRefreshed = function() onDevGuildChanged("all shops refreshed") end,
		onLevelsChanged = function() onDevGuildChanged("building level changed") end,
		onGoldChanged = function() refreshOverview() end,
	})
end
initDevPanel()
-- The server's DevAccess attribute may arrive after this script starts (published game).
player:GetAttributeChangedSignal("DevAccess"):Connect(initDevPanel)

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

-- Dispatch page moved to its own screen (DispatchScreen, 2026-11-11).

-- UNITS is its own full screen (UnitsScreen, user 2026-11-13 1:41 PM): 3 unit cards per row,
-- tap a card = the Loadout on INFO with that unit selected (no Loadout button). The "Units"
-- page key stays only as the base landing page (empty panel); the nav button opens the screen.
local function pageUnits() end

local function openUnits()
	if not UnitsScreen then
		setStatus("Units screen not loaded", true)
		return
	end
	screenGui.Enabled = false
	UnitsScreen.Open()
	updateBalanceLabel()
end

if UnitsScreen then
	UnitsScreen.Init({
		parent = playerGui,
		getUnits = function(): any?
			return cachedCall("Units", GuildEvents.GetGuildUnits)
		end,
		-- Away units can open too: the Loadout has no dispatch rule (only Parties blocks adding them).
		openUnit = function(unitId: string)
			local open = (_G :: any).CTRBLXAI_OpenLoadoutTab
			if type(open) ~= "function" then setStatus("Loadout screen not loaded", true) return end
			local pg = player:FindFirstChild("PlayerGui")
			UnitsScreen.Hide()
			open("INFO", { unitId = unitId })
			-- Loadout closed (or never opened): back to the Units screen with fresh data.
			task.spawn(function()
				local appeared, waited = false, 0
				while true do
					local ls = pg and pg:FindFirstChild("LoadoutScreen")
					if ls then appeared = true elseif appeared then break end
					if not appeared and waited > 10 then break end
					task.wait(0.1)
					waited += 0.1
				end
				if not guildMenuIsOpen then return end -- menu closed meanwhile: stay hidden
				invalidatePageCache()
				refreshOverview()
				UnitsScreen.Open()
				updateBalanceLabel()
			end)
		end,
		requestBack = confirmLeaveWithCart,
		onClosed = function()
			screenGui.Enabled = true
			updateBalanceLabel()
			showPage(if currentPage == "Units" then "Adventurers" else currentPage) -- "Units" = empty landing key; Back shows the Quest Board
		end,
		setStatus = setStatus,
	})
end

-- DUNGEON (build step 5, 2026-11-13; project_rules 258-274). Its own full screen. A battle room is
-- played through the normal activity launch ({ activity = "dungeon" }); the server only listens for
-- it at the base wait, so if the quest board was already asked for this visit, it is cancelled first
-- and the launch is sent on the next base open. After the battle the base reopens on the Dungeon.
local dungeonLaunchPending = false
-- A dungeon room's battle starts from the Dungeon screen, never the Quest Board (user 2026-11-16
-- 9:54 AM): while the server scouts the room's map, the Dungeon screen stays up and the battle
-- departs on MapBuildComplete. No quest briefing, party pick or 'Abandon quest' for a room.
local dungeonDeparting = false
local dungeonDepartToken = 0 -- W3: bumped per dungeon departure; a stale 30 s timeout does nothing
local DUNGEON_DEPART_TIMEOUT = 30
-- Existing embark phrases (also the Embark button, EMBARK_PHRASES below); reused by the dungeon battle
-- loading panel so it needs no new text (2026-11-17 10:50 AM).
local EMBARK_LINES = { "Scouting the area", "Mapping the location", "Locating the target", "Scanning the terrain" }
local returnToDungeon = false
local DUNGEON_LOCKED_TEXT = "Reach Renown Rank 25 to open the Dungeon." -- DG-LOCKED (approved 2026-11-16, guild_facilities 98)

local function openDungeon()
	if not DungeonScreen then
		setStatus("Dungeon screen not loaded", true)
		return
	end
	local res = DungeonScreen.Refresh()
	if not res then return end
	if (res.level or 0) < 1 and not res.run then
		setStatus(DUNGEON_LOCKED_TEXT, true)
		return
	end
	screenGui.Enabled = false
	DungeonScreen.Open()
	updateBalanceLabel()
end

local function fireDungeonLaunch()
	dungeonLaunchPending = false
	returnToDungeon = true
	if DungeonScreen then DungeonScreen.Hide() end
	BattleEvents.OpenAdventurersGuild:FireServer({ activity = "dungeon" })
end

if DungeonScreen then
	DungeonScreen.Init({
		parent = playerGui,
		action = function(data: { [string]: any }): any?
			-- W1 (2026-11-16): while a room's battle is departing, only the read-only State refresh runs.
			if dungeonDeparting and not (type(data) == "table" and data.action == "State") then return nil end
			local res = call(GuildEvents.DungeonAction, data)
			if res then invalidatePageCache() end -- runs lock units / pay out: re-fetch other screens
			updateBalanceLabel()
			return res
		end,
		getUnits = function(): any?
			return call(GuildEvents.GetGuildUnits) -- fresh (away flags); the screen asks once per party view
		end,
		launchBattle = function()
			if isBusy or dungeonDeparting or currentPhase ~= "Base" then return end
			if DungeonLoading then DungeonLoading.Show(EMBARK_LINES) end -- tap acknowledged at once; hides at deployment
			if guildQuests ~= nil then
				-- The server is waiting on a quest pick, not at the base wait: back out first.
				dungeonLaunchPending = true
				guildQuests = nil
				if DungeonScreen then DungeonScreen.Hide() end
				BattleEvents.QuestBoardCancel:FireServer()
				return
			end
			fireDungeonLaunch()
		end,
		requestBack = function(...)
			if dungeonDeparting then return end -- leaving for the room's battle: no way back to the guild screen
			return confirmLeaveWithCart(...)
		end,
		onClosed = function()
			returnToDungeon = false
			screenGui.Enabled = true
			updateBalanceLabel()
			showPage(if currentPage == "Units" then "Adventurers" else currentPage)
		end,
		setStatus = setStatus,
		isLocked = function(): boolean return dungeonDeparting end, -- W1: Dungeon-screen taps do nothing while departing
	})
end

-- PARTIES moved into the Loadout screen as its 5th tab (USER DECISION 2026-11-04). This page
-- now just opens that tab; in a sortie it opens in pick mode and Back returns to the Sortie.
local function openPartiesTab()
	local open = (_G :: any).CTRBLXAI_OpenLoadoutTab
	if type(open) ~= "function" then setStatus("Loadout screen not loaded", true) return end
	local pg = player:FindFirstChild("PlayerGui")
	local pickMode = currentPhase == "PreBattle" and sortieMode
	screenGui.Enabled = false
	open("PARTIES", {
		pick = pickMode,
		onPick = function(id: string, name: string)
			sortiePartySlot = id
			sortiePartyName = name
			updateSortieButton()
			setStatus(`{name} will deploy`)
		end,
		onDone = function()
			local close = (_G :: any).CTRBLXAI_CloseLoadout
			if type(close) == "function" then close() end
		end,
	})
	task.spawn(function()
		local appeared = false
		local waited = 0
		while true do
			local ls = pg and pg:FindFirstChild("LoadoutScreen")
			if ls then appeared = true elseif appeared then break end
			if not appeared and waited > 10 then break end -- never opened
			task.wait(0.1)
			waited += 0.1
		end
		screenGui.Enabled = true
		invalidatePageCache()
		refreshOverview()
		if pickMode then guildSortieStep = "sortie" end
		showPage(if pickMode then "Adventurers" else (if currentPage == "Party" then "Units" else currentPage))
	end)
end

local function pageParty()
	openPartiesTab()
end

-- Embark button cycling-text machinery (reuses the scout-token pattern). The button lives
-- in the wiped-each-render content area, so the loop re-grabs the live button and self-cancels
-- when the token advances, the button is destroyed, or scouting finishes. (2026-10-16)
local embarkButton: TextButton? = nil
local embarkToken = 0
local EMBARK_PHRASES = EMBARK_LINES -- one list (defined with the dungeon launch code above)

local function pageAdventurersGuild()
	addHeading("QUEST BOARD") -- renamed from Adventurer's Guild (user 2026-11-13 1:25 PM)
	embarkButton = nil  -- content was just wiped; drop any stale reference

	if sortieMode and chosenQuest then
		local q = chosenQuest

		if guildSortieStep == "details" then
			addNote(`{q.name}`)
			if q.elite then addNote("Scouts report an elite war band! An Elite leads it, with one extra enemy. Win for extra rewards: mercury, crystals, maybe a rune gem, and a chance at better gear.") end
			addNote(`Location: {q.biome}   Recommended Lv {q.recommendedLvl}`)
			addNote(`Enemies: {q.enemyCount}   Difficulty: {tostring(q.difficulty or "?")}`)
			local g = q.rewards and q.rewards.gold
			if g then
				addNote("Reward gold: " .. ((g.min == g.max) and (g.min .. " + kills") or (g.min .. "-" .. g.max)))
			end
			if q.rewards and (tonumber(q.rewards.mercury) or 0) > 0 then
				addNote(`Reward mercury: {q.rewards.mercury}`)
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
		if q.elite then addNote("Scouts report an elite war band! An Elite leads it, with one extra enemy. Win for extra rewards: mercury, crystals, maybe a rune gem, and a chance at better gear.") end
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
	for _, q in guildQuests do
		if q.isDailyContract then
			addNote("Daily Contract (one a day): win it for 3 mercury. Every 3rd one also gives 1 sulfur.")
			break
		end
	end
	if newDayAt then
		local left = math.max(0, math.floor(newDayAt - os.clock()))
		addNote(`New day in {left // 3600}h {(left % 3600) // 60}m`)
	end
	if bossRewardsText then addNote(bossRewardsText) end
	for _, q in ipairs(guildQuests) do
		local quest = q
		local g = q.rewards and q.rewards.gold
		local goldText = ""
		if g then goldText = (g.min == g.max) and (`{g.min} gold + kills`) or (`{g.min}-{g.max} gold`) end
		if q.rewards and (tonumber(q.rewards.mercury) or 0) > 0 then
			goldText = `{goldText} + {q.rewards.mercury} mercury`
		end
		-- Renown preview (step 7, loot_progression 94): "+100 Renown" / "+50 Renown (too easy)".
		local rp = q.renownPreview
		local renownText = if type(rp) == "table" and tonumber(rp.amount)
			then `  |  +{rp.amount} Renown` .. (if rp.tooEasy then " (too easy)" else "") else ""
		local line = `{q.name}\n{q.biome}  Lv {q.recommendedLvl}  |  {q.enemyCount} enemies  |  {goldText}{renownText}  |  Deploy {q.playerSlots}`
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
			openUnits() -- base lands on the Units screen (user 2026-11-13 1:57 PM)
		end },
	})
end

-- GUILD HALL SCREEN (user 2026-11-17 4:40 PM): its own full screen, like the Merchant. The old
-- Guild Hall page (row list + Furnish rows) moved to UI/GuildHallScreen.lua; the server still builds
-- every row and checks every upgrade / furniture move (BuildingAction, FurnitureAction).
local function openGuildHall(startTab: string?)
	if not GuildHallScreen then
		setStatus("Guild Hall screen not loaded", true)
		return
	end
	screenGui.Enabled = false
	GuildHallScreen.Open(startTab)
	updateBalanceLabel()
end

-- Furniture picker / swap popup + craft list (FurnishScreen): server calls and shared wording.
if FurnishScreen then
	FurnishScreen.Init({
		Theme = Theme, GuildEvents = GuildEvents, FurnitureData = FurnitureData, playerGui = playerGui,
		call = call, invalidatePageCache = invalidatePageCache,
		refreshOverview = refreshOverview, setStatus = setStatus,
		isBusy = function(): boolean return isBusy end,
		setBusy = function(v: boolean) isBusy = v end,
	})
end

if GuildHallScreen then
	GuildHallScreen.Init({
		parent = playerGui, GuildEvents = GuildEvents, FurnitureData = FurnitureData, call = call,
		isBusy = function(): boolean return isBusy end,
		setBusy = function(v: boolean) isBusy = v end,
		invalidatePageCache = invalidatePageCache, refreshOverview = refreshOverview,
		requestBack = confirmLeaveWithCart,
		onClosed = function()
			screenGui.Enabled = true
			updateBalanceLabel()
			showPage(currentPage)
		end,
		setStatus = setStatus,
	})
end

-- One-time notice for saves made before Slice 8 (guild_facilities 97/98: MIGRATE-NOTICE + FUR-GIFT).
-- Own ScreenGui so it shows over the Units screen too. "Furnish" opens the Furnish tab; a tap on
-- the dark background just closes it. Either way the server is told it was seen (once).
local noticeShown = false
local function showFurnitureNotice()
	local ok, res = pcall(function() return GuildEvents.FurnitureAction:InvokeServer({ action = "State" }) end)
	-- Furniture step 4b (WARN-A): pieces left behind at the 400 limit, shown once on return to base.
	local lb = ok and type(res) == "table" and type(res.furniture) == "table" and res.furniture.leftBehind or nil
	if type(lb) == "table" and #lb > 0 then
		setStatus(table.concat(lb, "\n"), true) -- FUR-STORAGE-FULL (approved 2026-11-16 11:02 PM)
		pcall(function() GuildEvents.FurnitureAction:InvokeServer({ action = "AckLeftBehind" }) end)
	end
	if noticeShown then return end
	if not ok or type(res) ~= "table" or res.ok == false or type(res.furniture) ~= "table" or not res.furniture.notice then return end
	noticeShown = true
	local gui = Instance.new("ScreenGui")
	gui.Name = "FurnitureNotice"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 200
	local overlay = Instance.new("TextButton")
	overlay.Text = ""
	overlay.AutoButtonColor = false
	overlay.Modal = true
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.4
	overlay.BorderSizePixel = 0
	overlay.Parent = gui
	local box = Instance.new("Frame")
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.new(0.5, 0, 0.5, 0)
	box.Size = UDim2.new(0, 380, 0, 190)
	box.BackgroundColor3 = Theme.Colors.PanelRaised
	box.BorderSizePixel = 0
	box.Parent = overlay
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius.md
	corner.Parent = box
	local msg = makeText(box, "Buildings no longer wait on your Guild Hall. Some of your buildings got stronger. Your Guild Hall now holds furniture: check the Furnish tab!\n\nWelcome gift: Straw Cot and Scribe's Desk.", Theme.Text.Body(), Theme.Colors.TextPrimary) -- MIGRATE-NOTICE + FUR-GIFT
	msg.Size = UDim2.new(1, -24, 1, -(BUTTON_HEIGHT + 30))
	msg.Position = UDim2.new(0, 12, 0, 10)
	local function done(openFurnish: boolean)
		gui:Destroy()
		pcall(function() GuildEvents.FurnitureAction:InvokeServer({ action = "Seen" }) end)
		if openFurnish then
			if UnitsScreen and UnitsScreen.IsOpen() then UnitsScreen.Hide() end -- no onClosed: the Guild Hall opens instead
			openGuildHall("Furnish")
		end
	end
	overlay.Activated:Connect(function() done(false) end)
	local b = makeButton(box, "Furnish", Theme.Colors.Success, function() done(true) end) -- GH-TAB-FURNISH
	b.Size = UDim2.new(0.5, 0, 0, BUTTON_HEIGHT)
	b.AnchorPoint = Vector2.new(0.5, 1)
	b.Position = UDim2.new(0.5, 0, 1, -12)
	gui.Parent = playerGui -- NET-004: properties before Parent
end

local PAGES: { [string]: () -> () } = {
	-- Guild Hall is its own screen (openGuildHall, 2026-11-17).
	-- Tavern and Merchant are their own screens (openTavern / openMerchant), 2026-10-31.
	-- Merchant is its own screen (openMerchant), not a page of this menu (2026-10-31).
	Blacksmith = pageBlacksmith,
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
		Theme.SetTabState(btn, if lockedPages[page] then "Disabled" elseif page == currentPage then "Active" else "Inactive")
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

-- "Upgrade at the Guild Hall" link (guild_facilities 90, approved rank text 15; W3 2026-11-16).
-- One shared button, shown while any building screen is open; it closes that screen and opens the
-- Guild Hall upgrade list. Every building screen has the same header bar (title left, gold line
-- right); the link sits in the free gap between them, so it never covers a screen's own buttons.
-- Polled at 2 Hz (cheap IsOpen checks + a header lookup) so no screen module needs editing.
local GH_LINK_SCREENS: { [any]: string } = {}
for name, s in { TavernScreen = TavernScreen, MerchantScreen = MerchantScreen, BlacksmithScreen = BlacksmithScreen,
	RuneforgeScreen = RuneforgeScreen, CrucibleScreen = CrucibleScreen, ApothecaryScreen = ApothecaryScreen,
	TrainingGroundsScreen = TrainingGroundsScreen, DispatchScreen = DispatchScreen, DungeonScreen = DungeonScreen } do
	if s then GH_LINK_SCREENS[s] = name end
end
local GH_LINK_W, GH_LINK_H = 180, 44 -- 44 px touch target (rule 244)
local ghLinkGui = Instance.new("ScreenGui")
ghLinkGui.Name = "GuildHallLink"
ghLinkGui.ResetOnSpawn = false
ghLinkGui.IgnoreGuiInset = false -- same coordinate space as the building screens' headers
ghLinkGui.DisplayOrder = 60
ghLinkGui.Enabled = false
local function openLinkScreen(): (any, string?)
	for s, name in GH_LINK_SCREENS do
		local okO, isOpen = pcall(s.IsOpen)
		if okO and isOpen then return s, name end
	end
	return nil, nil
end
onGuildHallLink = function()
	if dungeonDeparting then return end
	local openScreen = openLinkScreen()
	if not openScreen then return end
	confirmLeaveWithCart(function()
		pcall(openScreen.Close)
		task.defer(function()
			openGuildHall("Buildings")
		end)
	end)
end
local ghLinkBtn: GuiButton = Theme.MakeTabButton(ghLinkGui, "Upgrade at the Guild Hall", "Inactive", function() onGuildHallLink() end,
	{ name = "GuildHallLinkButton", size = UDim2.fromOffset(GH_LINK_W, GH_LINK_H) })
-- Furniture craft button (furniture step 3, USER RULING 2026-11-16 3:40 PM; approved step 3 line 1).
-- Shown beside the Guild Hall link on the Blacksmith / Runeforge / Apothecary screens only.
local FURN_SCREENS: { [string]: string } = { BlacksmithScreen = "Blacksmith", RuneforgeScreen = "Runeforge", ApothecaryScreen = "Apothecary" }
local FURN_BTN_W = 76 -- "Furniture" fits at 12 px (measured 750x382)
local GH_LINK_W_CRAFT = 146 -- the link wraps to 2 lines (12 px) so both fit the header gap
local openFurnitureCraft: (building: string) -> () = function() end
local closeFurnitureCraftFn: () -> () = function() end -- set below; closes the list when no craft screen is open
local furnBuilding: string? = nil
local furnBtn: GuiButton = Theme.MakeTabButton(ghLinkGui, "Furniture", "Inactive", function()
	if furnBuilding and not dungeonDeparting then openFurnitureCraft(furnBuilding) end
end, { name = "FurnitureCraftButton", size = UDim2.fromOffset(FURN_BTN_W, GH_LINK_H) })
furnBtn.Visible = false
ghLinkGui.Parent = playerGui -- NET-004
-- Header gap of the open screen: the two header labels drawn above the safe area (title, gold).
local function placeLink(screenName: string): boolean
	local sg = playerGui:FindFirstChild(screenName)
	if not (sg and sg:IsA("ScreenGui")) then return false end
	local heads: { TextLabel } = {}
	for _, d in sg:GetDescendants() do
		if d:IsA("TextLabel") and d.Text ~= "" and d.AbsolutePosition.Y < 0 and d.AbsoluteSize.X > 40 then
			local vis = true
			local a: Instance? = d
			while a and a ~= sg do
				if a:IsA("GuiObject") and not a.Visible then vis = false break end
				a = a.Parent
			end
			if vis then table.insert(heads, d) end
		end
	end
	if #heads == 0 then return false end
	table.sort(heads, function(a: TextLabel, b: TextLabel) return a.AbsolutePosition.X < b.AbsolutePosition.X end)
	local title = heads[1]
	local left = title.AbsolutePosition.X + title.AbsoluteSize.X + 6
	local right = if heads[2] then heads[2].AbsolutePosition.X - 6 else workspace.CurrentCamera.ViewportSize.X - 6
	furnBuilding = FURN_SCREENS[screenName]
	local y = math.floor(title.AbsolutePosition.Y + (title.AbsoluteSize.Y - GH_LINK_H) / 2)
	if furnBuilding then
		-- Craft screens: measure from the end of the title TEXT (left-aligned) so the link (2 lines) and
		-- the Furniture button both fit; neither covers a screen button or the gold line.
		local l2 = title.AbsolutePosition.X + title.TextBounds.X + 6
		local need = GH_LINK_W_CRAFT + 6 + FURN_BTN_W
		if right - l2 >= need then
			local x = math.floor(l2 + (right - l2 - need) / 2)
			ghLinkBtn.Size = UDim2.fromOffset(GH_LINK_W_CRAFT, GH_LINK_H)
			ghLinkBtn.Position = UDim2.fromOffset(x, y)
			furnBtn.Position = UDim2.fromOffset(x + GH_LINK_W_CRAFT + 6, y)
			furnBtn.Visible = true
			return true
		end
		-- Header too narrow for both: Furniture just below the link's right edge (fallback).
		furnBtn.Visible = true
	else
		furnBtn.Visible = false
	end
	if right - left < GH_LINK_W then return false end
	local x = math.floor(left + (right - left - GH_LINK_W) / 2)
	ghLinkBtn.Size = UDim2.fromOffset(GH_LINK_W, GH_LINK_H)
	ghLinkBtn.Position = UDim2.fromOffset(x, y)
	if furnBuilding then furnBtn.Position = UDim2.fromOffset(x + GH_LINK_W - FURN_BTN_W, y + GH_LINK_H + 4) end
	return true
end
task.spawn(function()
	while ghLinkGui.Parent do
		local show = false
		if not dungeonDeparting then
			local s, name = openLinkScreen()
			if s and name then show = placeLink(name) end
		end
		ghLinkGui.Enabled = show
		if not show or not furnBuilding then closeFurnitureCraftFn() end
		task.wait(0.5)
	end
end)

-- Furniture craft list: moved to UI/FurnishScreen.lua (furniture v5 step 4a, 2026-11-16).
openFurnitureCraft = function(building: string)
	if FurnishScreen then FurnishScreen.OpenCraft(building) end
end
closeFurnitureCraftFn = function()
	if FurnishScreen then FurnishScreen.CloseCraft() end
end

-- "New" marks on the nav (Slice 8 step 1): page -> label; cleared on the server once opened.
local navNewLabels: { [string]: TextLabel } = {}
local NAV_BUILDING: { [string]: string } = {
	GuildHall = "GuildHall", Tavern = "Tavern", Merchant = "Merchant", Blacksmith = "Blacksmith",
	Runeforge = "Runeforge", Crucible = "Crucible", Apothecary = "Apothecary",
	TrainingGrounds = "TrainingGrounds", Dispatch = "Dispatch", Dungeon = "Dungeon",
}
local function clearNewMark(pageName: string)
	local lbl = navNewLabels[pageName]
	if not lbl then return end
	lbl:Destroy()
	navNewLabels[pageName] = nil
	local bName = NAV_BUILDING[pageName]
	if bName then
		task.spawn(function()
			pcall(function() GuildEvents.BuildingAction:InvokeServer({ action = "Seen", building = bName }) end)
		end)
	end
end

local function buildNav()
	for _, b in navButtons do b:Destroy() end
	navButtons = {}
	table.clear(navPageOf) -- destroyed buttons must not stay referenced (PRF-004)
	-- Third field = Theme.GuildIcons key (user ruling 2026-11-13 12:40 AM). Units has none:
	-- it keeps an empty icon column so its name lines up with the others.
	local entries = {
		{ "Guild Hall", "GuildHall", "Townhall" }, -- upgrade list (Slice 8 step 1, approved rank text 1)
		{ "Tavern", "Tavern", "Recruitment" }, { "Merchant", "Merchant", "GearMerchant" },
		{ "Blacksmith", "Blacksmith", "Blacksmith" },
		{ "Runeforge", "Runeforge", "Runeforge" }, { "Crucible", "Crucible", "Crucible" },
		{ "Apothecary", "Apothecary", "Apothecary" }, { "Training", "TrainingGrounds", "TrainingGrounds" },
		-- "Party" removed 2026-11-05 (user): parties live in the Loadout PARTIES tab. The Sortie's
		-- "Change party" still opens that tab through the "Party" page entry.
		{ "Dispatch", "Dispatch", "Dispatch" }, { "Units", "Units", "Units" },
		{ "UGC Merchant", "UGCMerchant", "UGCMarket" }, -- 2026-11-05 (user); the Outfit tab shortcut stays
		{ "Dungeon", "Dungeon", "Dungeon" }, -- build step 5 (2026-11-13), approved DG-NAV
	}
	for i, e in entries do
		local pageName = e[2]
		local btn: GuiButton = Theme.MakeTabButton(nav, e[1], "Inactive", function()
			if clearNewMark then clearNewMark(pageName) end -- "New" mark goes once the building is opened
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
			if pageName == "GuildHall" then
				-- Own full screen (2026-11-17): same keep/discard prompt first, then open it.
				confirmLeaveWithCart(function()
					setStatus("")
					openGuildHall()
				end)
				return
			end
			if pageName == "Dungeon" then
				confirmLeaveWithCart(function()
					setStatus("")
					openDungeon()
				end)
				return
			end
			if pageName == "Units" then
				-- Own full screen (2026-11-13): same keep/discard prompt first, then open it.
				confirmLeaveWithCart(function()
					setStatus("")
					openUnits()
				end)
				return
			end
			if pageName == "Dispatch" then
				-- Own full screen (2026-11-11): same keep/discard prompt first, then open it.
				confirmLeaveWithCart(function()
					setStatus("")
					openDispatch()
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
			if pageName == "UGCMerchant" then
				-- Same UGC merchant screen as the Outfit tab shortcut (its own full screen).
				confirmLeaveWithCart(function()
					setStatus("")
					openUGCMerchant()
				end)
				return
			end
			if pageName == "TrainingGrounds" then
				-- Own full screen (2026-11-04). It has no page fallback.
				confirmLeaveWithCart(function()
					setStatus("")
					openTrainingGrounds()
				end)
				return
			end
			if pageName == "Apothecary" then
				-- Own full screen (2026-11-03). It has no page fallback.
				confirmLeaveWithCart(function()
					setStatus("")
					openApothecary()
				end)
				return
			end
			if pageName == "Crucible" then
				-- Own full screen (2026-11-02). It has no page fallback.
				confirmLeaveWithCart(function()
					setStatus("")
					openCrucible()
				end)
				return
			end
			if pageName == "Runeforge" then
				-- Own full screen (v2 step 5, 2026-11-01). It has no page fallback.
				confirmLeaveWithCart(function()
					setStatus("")
					openRuneforge()
				end)
				return
			end
			if pageName == "Blacksmith" and BlacksmithScreen then
				-- Own full screen (v2 step 3, 2026-11-01); the old page stays only as a fallback.
				confirmLeaveWithCart(function()
					setStatus("")
					openBlacksmith()
				end)
				return
			end
			if currentPage == pageName then return end
			confirmLeaveWithCart(function()
				setStatus("")
				showPage(pageName)
			end)
		end, { name = "Nav_" .. pageName, size = UDim2.new(1, 0, 0, BUTTON_HEIGHT), layoutOrder = i,
			textSize = Theme.Text.Body(), icon = if e[3] then Theme.GuildIcons[e[3]] else nil,
			iconSize = NAV_ICON_PX, iconReserve = true, textAlign = Enum.TextXAlignment.Left })
		registerNav(btn, pageName)
		table.insert(navButtons, btn)
	end
	-- Adventurer's Guild: opens the quest board (2026-10-12). Fires OpenAdventurersGuild;
	-- the server is waiting at the guild base and responds by showing the quest board.
	local advGuild = makeButton(nav, "Quest Board", Theme.Colors.Accent or Theme.Colors.Success, function()
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
	-- Adventurer's Guild icon, same column as the building icons (2026-11-13).
	do
		local ico = Instance.new("ImageLabel")
		ico.Name = "Icon"
		ico.BackgroundTransparency = 1
		ico.ScaleType = Enum.ScaleType.Fit
		ico.Image = Theme.GuildIcons.AdventurersGuild
		ico.AnchorPoint = Vector2.new(0, 0.5)
		ico.Size = UDim2.fromOffset(NAV_ICON_PX, NAV_ICON_PX)
		-- UIPadding below also shifts children: -(icon + 4) puts it 10 px from the edge.
		ico.Position = UDim2.new(0, -(NAV_ICON_PX + 4), 0.5, 0)
		ico.Parent = advGuild
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 10 + NAV_ICON_PX + 4)
		pad.Parent = advGuild
		advGuild.TextXAlignment = Enum.TextXAlignment.Left
	end
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

-- Locked buildings (Slice 8 step 1): greyed (Disabled bar art); a tap explains how to open
-- them (approved rank text 12). Open buildings with a "New" mark show it (rank text 14).
-- Tapping a locked nav entry shows the approved lock line (rank text 12).
showLockLine = function(page: string)
	local info = lockedPages[page]
	if info then
		setStatus(`{info.display} unlocks at Renown Rank {info.unlockRank}. Complete quests to earn Renown.`, true)
	end
end
applyNavLocks = function(state: any)
	table.clear(lockedPages)
	for btn, page in navPageOf do
		local bName = NAV_BUILDING[page]
		local s = bName and state[bName] or nil
		local catcher = btn:FindFirstChild("LockCatcher")
		if type(s) == "table" and s.open == false then
			lockedPages[page] = s
			if not catcher then
				local c = Instance.new("TextButton")
				c.Name = "LockCatcher"
				c.Text = ""
				c.BackgroundTransparency = 1
				c.Size = UDim2.fromScale(1, 1)
				c.ZIndex = btn.ZIndex + 2
				c.Parent = btn
				c.Activated:Connect(function() showLockLine(page) end)
			end
		elseif catcher then
			catcher:Destroy()
		end
		local hasNew = type(s) == "table" and s.open == true and s.new == true
		if hasNew and not navNewLabels[page] then
			local n = Instance.new("TextLabel")
			n.Name = "NewMark"
			n.Text = "New"
			n.Font = Theme.Font.PrimaryBold
			n.TextSize = Theme.Text.Small()
			n.TextColor3 = Theme.Colors.TextGold
			n.BackgroundTransparency = 1
			n.AnchorPoint = Vector2.new(1, 0.5)
			n.Position = UDim2.new(1, -8, 0.5, 0)
			n.Size = UDim2.new(0, 34, 1, 0)
			n.TextXAlignment = Enum.TextXAlignment.Right
			n.ZIndex = btn.ZIndex + 1
			n.Parent = btn
			navNewLabels[page] = n
		elseif not hasNew and navNewLabels[page] then
			navNewLabels[page]:Destroy()
			navNewLabels[page] = nil
		end
	end
	styleNav()
end

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
	shownRefillNote = false -- show the refill note once per visit (2026-11-03)
	guildMenuIsOpen = true
	-- A fresh menu open always starts on the menu itself, never inside a building screen.
	if MerchantScreen then MerchantScreen.Hide() end
	if TavernScreen then TavernScreen.Hide() end
	if BlacksmithScreen then BlacksmithScreen.Hide() end
	if RuneforgeScreen then RuneforgeScreen.Hide() end
	if CrucibleScreen then CrucibleScreen.Hide() end
	if ApothecaryScreen then ApothecaryScreen.Hide() end
	if TrainingGroundsScreen then TrainingGroundsScreen.Hide() end
	if DispatchScreen then DispatchScreen.Hide() end if UnitsScreen then UnitsScreen.Hide() end if DungeonScreen then DungeonScreen.Hide() end if GuildHallScreen then GuildHallScreen.Hide() end
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
	local isDungeonSortie = currentPhase == "PreBattle" and type(data) == "table" and data.dungeon == true
	dungeonDeparting = isDungeonSortie
	if isDungeonSortie then
		sortieMode = false -- the dungeon party is fixed: no quest briefing, no party pick
		departPending = true -- depart on MapBuildComplete (same deferred-embark path as quests)
	elseif currentPhase == "PreBattle" then
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
	if isDungeonSortie then
		screenGui.Enabled = false
		if DungeonScreen then
			DungeonScreen.Open()
			DungeonScreen.SetStatus(EMBARK_PHRASES[1] .. "...") -- existing text "Scouting the area..."
		end
		if not sortieLocked and departPending then -- map already built: go now
			departPending = false
			if DungeonScreen then DungeonScreen.Hide() end
			BattleEvents.StartBattle:FireServer()
		end
		-- W3 (fixed 2026-11-16, Tester thread-f0e64b74e051): if MapBuildComplete is slow, only tell the
		-- player; keep departPending so a late map still departs exactly once. Do NOT send AbandonQuest
		-- here: the server only listens for it after MapBuildComplete, so it would be dropped. If the
		-- server skips the room (map Generate pcall), it closes the menu and the close handler resets.
		-- Unrecoverable (documented, not fixed): a server error after map generate stops the loop.
		dungeonDepartToken += 1
		local myToken = dungeonDepartToken
		local timeout = DUNGEON_DEPART_TIMEOUT
		task.delay(timeout, function()
			if myToken ~= dungeonDepartToken or not dungeonDeparting or not departPending then return end
			warn(`[GuildMenu] Dungeon room map not ready after {timeout} s -- still waiting`)
			if DungeonScreen then DungeonScreen.SetStatus("Something went wrong. Try again.", true) end -- existing generic text
		end)
		print("[GuildMenu] Opened (PreBattle, dungeon room) -- departing from the Dungeon screen")
		return
	end
	showPage(sortieMode and "Adventurers" or "Units")
	-- Back at the base without a pending relaunch (battle refused or finished): loading panel off.
	if currentPhase == "Base" and not dungeonLaunchPending and DungeonLoading then DungeonLoading.Hide() end
	if currentPhase == "Base" and dungeonLaunchPending then
		fireDungeonLaunch() -- quest board was backed out of: now the server listens for the room
	elseif currentPhase == "Base" and returnToDungeon and DungeonScreen then
		openDungeon() -- back from a dungeon room: the base reopens on the map
	elseif not sortieMode then
		openUnits() -- base lands on the Units screen (user 2026-11-13 1:57 PM)
	end
	if currentPhase == "Base" and not sortieMode then task.spawn(showFurnitureNotice) end -- old-save notice, once
	print(`[GuildMenu] Opened ({currentPhase})`)
end)

GuildEvents.GuildMenuClosed.OnClientEvent:Connect(function()
	guildMenuIsOpen = false
	-- The UGC merchant opened from the guild closes with the menu (2026-11-05).
	if UGCMerchantScreen and UGCMerchantScreen.IsOpen() then UGCMerchantScreen.Close() end
	stopScout()  -- end any running scouting animation
	if MerchantScreen then MerchantScreen.Hide() end -- the building screen closes with the menu
	if TavernScreen then TavernScreen.Hide() end
	if BlacksmithScreen then BlacksmithScreen.Hide() end
	if RuneforgeScreen then RuneforgeScreen.Hide() end
	if CrucibleScreen then CrucibleScreen.Hide() end
	if ApothecaryScreen then ApothecaryScreen.Hide() end
	if TrainingGroundsScreen then TrainingGroundsScreen.Hide() end
	if DispatchScreen then DispatchScreen.Hide() end if UnitsScreen then UnitsScreen.Hide() end if DungeonScreen then DungeonScreen.Hide() end if GuildHallScreen then GuildHallScreen.Hide() end
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
		cartDismantles = {} -- v2 step 3 D-1: a staged dismantle must never outlive the menu (BUG-065)
	end
	screenGui.Enabled = false
	dungeonDeparting = false
	dungeonDepartToken += 1 -- W3: cancel any pending timeout
	print("[GuildMenu] Closed")
end)

-- Battle prep finished on the server: end scouting, unlock the sortie button. Also refresh
-- the Adventurer's Guild page so its Depart button flips from "Scouting..." to live. (2026-10-16)
-- Dungeon battle loading panel ends when the battle's deployment (or the battle) starts.
for _, evName in { "DeploymentPhase", "BattleStarted" } do
	local ev = (BattleEvents :: any)[evName]
	if ev and DungeonLoading then ev.OnClientEvent:Connect(function() DungeonLoading.Hide() end) end
end

if BattleEvents.MapBuildComplete then
	BattleEvents.MapBuildComplete.OnClientEvent:Connect(function()
		unlockSortie()
		-- If the player already tapped Embark during scouting, depart now (deferred-embark).
		if departPending and dungeonDeparting then
			-- W2 (2026-11-16): a dungeon room departs from the Dungeon screen, which has no building cart;
			-- never wait on the Confirm/Discard prompt (Cancel would leave dungeonDeparting stuck).
			departPending = false
			dungeonDepartToken += 1 -- W3: map arrived, cancel the timeout
			local pendingCount = cartCount()
			if pendingCount > 0 then
				warn(`[GuildMenu] Dungeon departure with {pendingCount} pending change(s) -- discarded`)
				cartBuys = {}; cartSells = {}; cartUpgrades = {}; cartDowngrades = {}
				cartDispatches = {}; cartHires = {}; cartDismantles = {}
			end
			if DungeonScreen then DungeonScreen.Hide() end
			screenGui.Enabled = false
			BattleEvents.StartBattle:FireServer()
			return
		end
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
				if BlacksmithScreen then BlacksmithScreen.Hide() end
				if RuneforgeScreen then RuneforgeScreen.Hide() end
				if CrucibleScreen then CrucibleScreen.Hide() end
				if ApothecaryScreen then ApothecaryScreen.Hide() end
				if TrainingGroundsScreen then TrainingGroundsScreen.Hide() end
				if DispatchScreen then DispatchScreen.Hide() end if UnitsScreen then UnitsScreen.Hide() end if DungeonScreen then DungeonScreen.Hide() end if GuildHallScreen then GuildHallScreen.Hide() end
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
		newDayAt = if type(data.newDayIn) == "number" then os.clock() + data.newDayIn else nil
		bossRewardsText = if type(data.bossRewardsLeft) == "number"
			then `Boss rewards left today: {data.bossRewardsLeft}/{tonumber(data.bossRewardsPerDay) or 3}` else nil
		sortieMode = false
		if currentPage == "Adventurers" then showPage("Adventurers") end
	end
end)

print("[GuildMenu] Ready — waiting for GuildMenuOpened")
