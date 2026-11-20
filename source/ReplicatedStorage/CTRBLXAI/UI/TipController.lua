--!strict
-- TipController.lua
-- CTRBLXAI | New-player tips, client side (new_player_tips SYS-01..10).
--
--   TipController.Trigger(id)  -- "the player just met this": queue the tip if it is unseen
--   TipController.Defer(id)    -- met it during a confirm step: hold it for the next calm moment
--   TipController.SetCalm(v)   -- SYS-04 gate: cards only show while calm
--   TipController.PlayerTurn() -- the player's own turn began (calm + TIP-BAT-01)
--   TipController.OpenLog()    -- Tips log (SYS-07) with the "Show tips" switch
--
-- One card at a time (SYS-03): triggers wait in a queue; the next shows after "Got it".
-- Seen once (SYS-05): the server keeps the real list (TipService); this copy only filters.
-- Calm (SYS-04): town is calm; in battle a card waits for the start of the player's own turn
-- (BattleVisualClient calls PlayerTurn after any cinematic) and stops once anything acts.
-- Server-known triggers (building unlocks) are pulled from State each time the guild menu opens.
-- One shared module instance per client: every screen requires this same ModuleScript.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local WAIT = 10

local uiFolder = script.Parent
local root = ReplicatedStorage:WaitForChild("CTRBLXAI", WAIT)
local themeModule = uiFolder:WaitForChild("Theme", WAIT)
local cardModule = uiFolder:WaitForChild("TipCard", WAIT)
local sharedFolder = root and root:WaitForChild("Shared", WAIT)
local remotesFolder = root and root:WaitForChild("Remotes", WAIT)
local dataModule = sharedFolder and sharedFolder:WaitForChild("TipData", WAIT)
if not themeModule or not cardModule or not dataModule or not remotesFolder then
	error("[TipController] Theme / TipCard / TipData / Remotes not found")
end
local Theme: any = (require :: any)(themeModule)
local TipCard: any = (require :: any)(cardModule)
local TipData: any = (require :: any)(dataModule)
local tipEventsModule = remotesFolder:WaitForChild("TipEvents", WAIT)
local battleEventsModule = remotesFolder:WaitForChild("BattleEvents", WAIT)
local guildEventsModule = remotesFolder:WaitForChild("GuildEvents", WAIT)
local TipEvents: any = if tipEventsModule then (require :: any)(tipEventsModule) else nil
local BattleEvents: any = if battleEventsModule then (require :: any)(battleEventsModule) else nil
local GuildEvents: any = if guildEventsModule then (require :: any)(guildEventsModule) else nil

local TipController = {}

local LOG_DISPLAY_ORDER = 240 -- just under the card (250)
local SEND_RETRIES = 3
local BUSY_RETRY_SECONDS = 0.3

local loaded = false
local off = false
local calm = true
local showing = false
local logOpen = false
local seen: { [string]: boolean } = {}
local buffer: { string } = {}        -- triggers before the state arrived
local queue: { string } = {}
local queued: { [string]: boolean } = {}
local held: { string } = {}          -- Defer: met during a preview/confirm step (SYS-04)
local logGui: ScreenGui? = nil

local function invoke(req: any): any?
	local remote = TipEvents and TipEvents.TipAction
	if not remote then return nil end
	local ok, res = pcall(function() return remote:InvokeServer(req) end)
	if not ok then
		warn("[TipController] TipAction failed: " .. tostring(res))
		return nil
	end
	return res
end

local function send(req: any)
	task.spawn(function()
		for _ = 1, SEND_RETRIES do
			local res = invoke(req)
			if not (type(res) == "table" and res.reason == "busy") then return end
			task.wait(BUSY_RETRY_SECONDS) -- SEC-001 rate limit: try again shortly
		end
	end)
end

local pump: () -> ()

local function enqueue(id: string)
	if off or seen[id] or queued[id] then return end
	queued[id] = true
	table.insert(queue, id)
end

pump = function()
	if showing or logOpen or not calm or off or not loaded then return end
	while #queue > 0 do
		local id = table.remove(queue, 1) :: string
		queued[id] = nil
		local tip = TipData.ById[id]
		if tip and not seen[id] then
			seen[id] = true
			send({ action = "Seen", id = id }) -- seen once shown (SYS-05)
			showing = true
			TipCard.Show(tip.title, tip.text, function()
				showing = false
				task.defer(pump)
			end)
			return
		end
	end
end

--- The player just met something. Unknown ids are ignored; seen ones never repeat.
function TipController.Trigger(id: string)
	if not TipData.IsKnown(id) then return end
	if not loaded then
		if not table.find(buffer, id) then table.insert(buffer, id) end
		return
	end
	enqueue(id)
	pump()
end

--- Met during a preview / confirm step (SYS-04: never over a confirm). The tip is held and
--- queued at the next calm moment: the player's next own turn or the guild menu opening.
function TipController.Defer(id: string)
	if not TipData.IsKnown(id) or seen[id] or queued[id] or table.find(held, id) then return end
	table.insert(held, id)
end

local function releaseHeld()
	if #held == 0 then return end
	local ids = held
	held = {}
	for _, id in ids do TipController.Trigger(id) end
end

function TipController.SetCalm(v: boolean)
	calm = v == true
	if calm then pump() end
end

function TipController.PlayerTurn()
	-- Hold the queue while the turn's tips are lined up, then open the gate once (one pump).
	calm = false
	releaseHeld()
	TipController.Trigger("TIP-BAT-01")
	TipController.SetCalm(true)
end

local function applyState(res: any)
	if type(res) ~= "table" or res.ok ~= true then return end
	for _, id in (type(res.seen) == "table" and res.seen or {}) do
		if type(id) == "string" then seen[id] = true end
	end
	off = res.off == true
	if not loaded then
		loaded = true
		local early = buffer
		buffer = {}
		for _, id in early do enqueue(id) end
	end
	for _, id in (type(res.pending) == "table" and res.pending or {}) do
		if type(id) == "string" then enqueue(id) end
	end
	pump()
end

local function refresh()
	task.spawn(function()
		applyState(invoke({ action = "State" }))
	end)
end

--------------------------------------------------
-- TIPS LOG (SYS-07): seen tips, rereadable, + the "Show tips" switch
--------------------------------------------------

local function closeLog()
	if logGui then logGui:Destroy(); logGui = nil end
	logOpen = false
	task.defer(pump)
end

local renderLog: () -> ()

local function makeText(parent: Instance, text: string, size: number, color: Color3, bold: boolean, order: number)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.Font = if bold then Theme.Font.PrimaryBold else Theme.Font.Primary
	l.TextSize = size
	l.TextColor3 = color
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.LayoutOrder = order
	l.Parent = parent
end

renderLog = function()
	if logGui then logGui:Destroy(); logGui = nil end
	local player = Players.LocalPlayer
	local pg = player and player:FindFirstChild("PlayerGui")
	if not pg then warn("[TipController] PlayerGui not found -- no Tips log"); return end
	local pad = Theme.Spacing.lg
	local touch = Theme.MinSize.TouchTarget

	local g = Instance.new("ScreenGui")
	g.Name = "TipsLogGui"
	g.ResetOnSpawn = false
	g.DisplayOrder = LOG_DISPLAY_ORDER
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local panel = Theme.MakePanel("TipsLog", UDim2.new(0.9, 0, 0.8, 0), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), nil)
	local sizeCap = Instance.new("UISizeConstraint")
	sizeCap.MaxSize = Vector2.new(560, 640)
	sizeCap.Parent = panel

	local head = Instance.new("Frame")
	head.Name = "Header"
	head.BackgroundTransparency = 1
	head.Position = UDim2.fromOffset(pad, pad)
	head.Size = UDim2.new(1, -2 * pad, 0, touch)
	local headLayout = Instance.new("UIListLayout")
	headLayout.FillDirection = Enum.FillDirection.Horizontal
	headLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	headLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	headLayout.SortOrder = Enum.SortOrder.LayoutOrder
	headLayout.Padding = UDim.new(0, Theme.Spacing.md)
	headLayout.Parent = head

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -(touch + 180), 1, 0)
	title.Font = Theme.Font.Display
	title.TextSize = Theme.Text.Title()
	title.TextColor3 = Theme.Colors.TextGold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Tips"
	title.LayoutOrder = 1
	title.Parent = head

	Theme.MakeBarButton(head, if off then "Show tips: Off" else "Show tips: On", "Secondary", function()
		local want = not off
		local res = invoke({ action = "SetOff", off = want })
		if type(res) == "table" and res.ok == true then
			off = res.off == true
			if off then table.clear(queue); table.clear(queued) end
		end
		renderLog()
	end, { name = "Btn_ShowTips", minHeight = touch, layoutOrder = 2 })
	local back = Theme.MakeIconButton(nil, "Back", closeLog, { name = "Btn_BACK", size = UDim2.fromOffset(touch, touch) })
	back.LayoutOrder = 3
	back.Parent = head
	head.Parent = panel

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(pad, pad + touch + Theme.Spacing.md)
	list.Size = UDim2.new(1, -2 * pad, 1, -(2 * pad + touch + Theme.Spacing.md))
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 6
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, Theme.Spacing.lg)
	listLayout.Parent = list

	local n = 0
	for _, tip in TipData.List do -- game order, not the order they were seen
		if seen[tip.id] then
			n += 1
			local entry = Instance.new("Frame")
			entry.Name = tip.id
			entry.BackgroundTransparency = 1
			entry.Size = UDim2.new(1, -8, 0, 0)
			entry.AutomaticSize = Enum.AutomaticSize.Y
			entry.LayoutOrder = tip.order
			local el = Instance.new("UIListLayout")
			el.SortOrder = Enum.SortOrder.LayoutOrder
			el.Padding = UDim.new(0, Theme.Spacing.xs)
			el.Parent = entry
			makeText(entry, tip.title, Theme.Text.Body(), Theme.Colors.TextGold, true, 1)
			makeText(entry, tip.text, Theme.Text.Small(), Theme.Colors.TextPrimary, false, 2)
			entry.Parent = list
		end
	end
	if n == 0 then
		makeText(list, "No tips yet.", Theme.Text.Body(), Theme.Colors.TextSecondary, false, 1)
	end
	list.Parent = panel
	if Theme.MakeDragScroll then pcall(Theme.MakeDragScroll, list) end

	panel.Parent = g
	g.Parent = pg -- NET-004: parent last
	logGui = g
end

function TipController.OpenLog()
	logOpen = true
	TipCard.Hide() -- a card on screen is already marked seen; it is in the log
	showing = false
	renderLog()
	refresh() -- pick up anything the server marked since
end

--------------------------------------------------
-- START (client only, once per client)
--------------------------------------------------

local function watch(ev: any, fn: (any) -> ())
	if ev and ev.OnClientEvent then
		ev.OnClientEvent:Connect(function(data: any)
			local ok, err = pcall(fn, data)
			if not ok then warn("[TipController] " .. tostring(err)) end
		end)
	end
end

if RunService:IsClient() then
	if GuildEvents then
		watch(GuildEvents.GuildMenuOpened, function()
			releaseHeld() -- anything held from the last battle
			TipController.Trigger("TIP-BASE-01")
			TipController.SetCalm(true)
			refresh() -- building-unlock tips (pending)
		end)
	end
	if BattleEvents then
		local function quiet(_: any) calm = false end -- something is acting: not the player's calm moment
		for _, name in { "BattleStarted", "TurnStarted", "UnitMoved", "UnitActed", "ActionAnnounced", "TurnEnded" } do
			watch(BattleEvents[name], quiet)
		end
		watch(BattleEvents.FacingPrompt, function()
			TipController.Defer("TIP-BAT-05") -- held, never over the facing choice (SYS-04)
			TipController.SetCalm(true) -- the player is choosing: their own moment
		end)
		watch(BattleEvents.StatusApplied, function() TipController.Trigger("TIP-BAT-06") end)
		watch(BattleEvents.ChannelStarted, function() TipController.Trigger("TIP-BAT-07") end)
		watch(BattleEvents.BattleEnded, function(data: any)
			calm = false -- result screen; the card waits for the guild menu
			if type(data) == "table" and data.winner == "Player" then TipController.Trigger("TIP-BAT-08") end
		end)
	end
	refresh()
end

return TipController
