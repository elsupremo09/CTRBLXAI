--!strict
-- Feedback.client.lua
-- CTRBLXAI | Always-on feedback / bug report button (user rulings 2026-11-17 4:01-4:38 PM).
--
-- One 44 px icon button in the Roblox top bar, right of Roblox's own top-left buttons, on every
-- screen (guild base, guild screens, dungeon, battle, Loadout). Guild headers leave this slot free
-- (Theme.TopbarReserve). It lives in its own ScreenGui above every game screen.
-- Tap -> gold-framed popup (GuildScreen.MakeModalBox): category, text box (500 characters),
-- Send / Back. The client only sends { category, text, context }; the server validates,
-- rate-limits (60 s) and stores the report (FeedbackService).
--
-- APPROVED TEXT (2026-11-17 4:38 PM, verbatim): "Send feedback", "Bug", "Suggestion", "Other",
-- "Tell us what happened…", "{n} / 500", "Send", "Thanks! Your report was sent.",
-- "Write something first.", "Please wait {n} s before sending another report.",
-- "Couldn't send your report. Try again later."

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local LogService = game:GetService("LogService")

local WAIT = 10
local MAX_TEXT = 500
local MAX_LOG_LINES = 5
local MAX_LOG_LEN = 200
local BTN = 44 -- touch target (Theme.MinSize.TouchTarget)
local DISPLAY_ORDER = 200 -- above every game screen (inspector 140-160, loadout 100)
local CLOSE_AFTER_SENT = 1.5 -- seconds the thank-you line stays before the popup closes

local CATEGORIES = { "Bug", "Suggestion", "Other" }
local TXT = {
	title = "Send feedback",
	hint = "Tell us what happened…",
	send = "Send",
	sent = "Thanks! Your report was sent.",
	empty = "Write something first.",
	failed = "Couldn't send your report. Try again later.",
}
local function countText(n: number): string return `{n} / {MAX_TEXT}` end
local function waitText(n: number): string return `Please wait {n} s before sending another report.` end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui", WAIT)
local root = ReplicatedStorage:WaitForChild("CTRBLXAI", WAIT)
local uiFolder = root and root:WaitForChild("UI", WAIT)
local remotes = root and root:WaitForChild("Remotes", WAIT)
local themeModule = uiFolder and uiFolder:WaitForChild("Theme", WAIT)
local guildScreenModule = uiFolder and uiFolder:WaitForChild("GuildScreen", WAIT)
local eventsModule = remotes and remotes:WaitForChild("FeedbackEvents", WAIT)
if not (playerGui and themeModule and guildScreenModule and eventsModule) then
	warn("[Feedback] Required modules missing; feedback button not shown")
	return
end
local Theme: any = (require :: any)(themeModule)
local GuildScreen: any = (require :: any)(guildScreenModule)
local FeedbackEvents: any = (require :: any)(eventsModule)

-- Recent client errors / warnings (context only, never shown) -----------------------------
local recentLogs: { string } = {}
LogService.MessageOut:Connect(function(message: string, kind: Enum.MessageType)
	if kind ~= Enum.MessageType.MessageError and kind ~= Enum.MessageType.MessageWarning then return end
	local line = (if kind == Enum.MessageType.MessageError then "E: " else "W: ") .. message
	if #line > MAX_LOG_LEN then line = string.sub(line, 1, MAX_LOG_LEN) end
	table.insert(recentLogs, line)
	if #recentLogs > MAX_LOG_LINES then table.remove(recentLogs, 1) end
end)

local gui = Instance.new("ScreenGui")
gui.Name = "FeedbackGui"
gui.DisplayOrder = DISPLAY_ORDER
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true -- positions use true screen coordinates (TopbarInset)
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- Context ---------------------------------------------------------------------------------
local function visibleScreens(): { string }
	local list: { { name: string, order: number } } = {}
	for _, g in playerGui:GetChildren() do
		if g:IsA("ScreenGui") and g ~= gui and g.Enabled then
			local shown = false
			for _, c in g:GetChildren() do
				if c:IsA("GuiObject") and c.Visible then shown = true break end
			end
			if shown then table.insert(list, { name = g.Name, order = g.DisplayOrder }) end
		end
	end
	table.sort(list, function(a, b) return a.order > b.order end)
	local names = {}
	for i = 1, math.min(#list, 8) do table.insert(names, list[i].name) end
	return names
end

local function collectContext(): { [string]: any }
	local screens = visibleScreens()
	local cam = workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.zero
	local device = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "Touch"
		elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then "Gamepad"
		else "Desktop"
	return {
		screen = screens[1],
		screens = screens,
		errors = table.clone(recentLogs),
		device = device,
		viewport = `{math.floor(vp.X)}x{math.floor(vp.Y)}`,
	}
end

-- Popup -------------------------------------------------------------------------------------
local overlay: any = nil
local busy = false

local function closePopup()
	if overlay then overlay:Destroy() end
	overlay = nil
	busy = false
end

local function label(parent: Instance, text: string, size: number, color: Color3, bold: boolean?, order: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size
	l.Font = if bold then Theme.Font.PrimaryBold else Theme.Font.Primary
	l.TextColor3 = color
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.LayoutOrder = order
	l.ZIndex = 22
	l.Parent = parent
	return l
end

local function hRow(parent: Instance, order: number, align: Enum.HorizontalAlignment): Frame
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0, BTN)
	row.LayoutOrder = order
	row.ZIndex = 22
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.HorizontalAlignment = align
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.Padding = UDim.new(0, 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = row
	row.Parent = parent
	return row
end

local function openPopup()
	if overlay then return end
	local ov, box = GuildScreen.MakeModalBox("FeedbackModal", { maxW = 480, widthScale = 0.82 })
	overlay = ov
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = box

	label(box, TXT.title, Theme.Text.Heading(), Theme.Colors.TextGold, true, 1)

	-- Category: the picked one is Primary, the others Secondary (rebuilt on tap).
	local category = CATEGORIES[1]
	local catRow = hRow(box, 2, Enum.HorizontalAlignment.Left)
	local function drawCategories()
		for _, c in catRow:GetChildren() do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		for i, name in CATEGORIES do
			Theme.MakeBarButton(catRow, name, if name == category then "Primary" else "Secondary", function()
				category = name
				drawCategories()
			end, { name = "Btn_Cat_" .. name, minHeight = BTN, layoutOrder = i })
		end
	end
	drawCategories()

	local cam = workspace.CurrentCamera
	local vh = if cam then cam.ViewportSize.Y else 382
	local input = Instance.new("TextBox")
	input.Name = "FeedbackText"
	input.MultiLine = true
	input.ClearTextOnFocus = false
	input.Text = ""
	input.PlaceholderText = TXT.hint
	input.PlaceholderColor3 = Theme.Colors.TextSecondary
	input.TextColor3 = Theme.Colors.TextPrimary
	input.Font = Theme.Font.Primary
	input.TextSize = Theme.Text.Body()
	input.TextWrapped = true
	input.TextXAlignment = Enum.TextXAlignment.Left
	input.TextYAlignment = Enum.TextYAlignment.Top
	input.BackgroundColor3 = Theme.Colors.Panel
	input.BackgroundTransparency = 0.1
	input.BorderSizePixel = 0
	input.Size = UDim2.new(1, 0, 0, if vh < 500 then 84 else 140) -- phone: keep Send on screen
	input.LayoutOrder = 3
	input.ZIndex = 22
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Border
	stroke.Thickness = 1
	stroke.Parent = input
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = input
	input.Parent = box

	local count = label(box, countText(0), Theme.Text.Small(), Theme.Colors.TextSecondary, false, 4)
	count.TextXAlignment = Enum.TextXAlignment.Right
	local status = label(box, "", Theme.Text.Small(), Theme.Colors.TextSecondary, false, 5)
	status.Visible = false

	input:GetPropertyChangedSignal("Text"):Connect(function()
		local t = input.Text
		local n = utf8.len(t) or #t
		if n > MAX_TEXT then
			local stop = utf8.offset(t, MAX_TEXT + 1)
			if stop then input.Text = string.sub(t, 1, stop - 1) end
			return -- the Text change above re-runs this handler
		end
		count.Text = countText(n)
	end)

	local function show(text: string, isError: boolean)
		status.Text = text
		status.TextColor3 = if isError then Theme.Colors.Danger else Theme.Colors.Success
		status.Visible = true
	end

	local function send()
		if busy then return end
		local text = (string.gsub((string.gsub(input.Text, "^%s+", "")), "%s+$", ""))
		if text == "" then show(TXT.empty, true) return end
		local remote = FeedbackEvents.SubmitFeedback
		if not remote then show(TXT.failed, true) return end
		busy = true
		local ok, res = pcall(function()
			return remote:InvokeServer({ category = category, text = text, context = collectContext() })
		end)
		if not overlay then return end -- closed while waiting
		busy = false
		local code = if ok and type(res) == "table" then res.code else nil
		if code == "ok" then
			show(TXT.sent, false)
			input.Text = ""
			local mine = overlay
			task.delay(CLOSE_AFTER_SENT, function()
				if overlay == mine then closePopup() end
			end)
		elseif code == "empty" then
			show(TXT.empty, true)
		elseif code == "cooldown" then
			show(waitText(if type(res.wait) == "number" then math.ceil(res.wait) else 60), true)
		else
			show(TXT.failed, true)
		end
	end

	local btnRow = hRow(box, 6, Enum.HorizontalAlignment.Right)
	-- 2026-11-18 user: popups confirm with the shared icon pair (Back, then the check), not a "Send" bar.
	Theme.MakeIconButton(btnRow, "Back", closePopup, { name = "Btn_FeedbackBack", size = UDim2.fromOffset(BTN, BTN) }).LayoutOrder = 1
	Theme.MakeIconButton(btnRow, "Confirm", send, { name = "Btn_FeedbackSend", size = UDim2.fromOffset(BTN, BTN) }).LayoutOrder = 2

	ov.Parent = gui
end

-- Button --------------------------------------------------------------------------------------
local button = Theme.MakeIconButton(nil, "Feedback", function()
	if overlay then closePopup() else openPopup() end
end, { name = "Btn_Feedback", size = UDim2.fromOffset(BTN, BTN) })
button.ZIndex = 5

-- Top bar slot right of Roblox's buttons (Theme.TopbarReserve keeps the guild headers clear).
local function place()
	local inset = GuiService.TopbarInset
	if inset.Min.X > 0 then
		local h = inset.Max.Y - inset.Min.Y
		local y = inset.Min.Y + math.max(0, math.floor((h - BTN) / 2))
		button.Position = UDim2.fromOffset(inset.Min.X + 4, y)
	else
		button.Position = UDim2.fromOffset(8, 8) -- no Roblox top bar (rare): top-left corner
	end
end
place()
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(place)

button.Parent = gui
gui.Parent = playerGui
print("[Feedback] Button ready")
