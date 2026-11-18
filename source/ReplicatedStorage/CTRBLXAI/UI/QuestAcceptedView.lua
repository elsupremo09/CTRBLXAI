--!strict
-- QuestAcceptedView.lua
-- CTRBLXAI | Quest Board "Quest accepted" view (Quest Board redesign step 3, 2026-11-18).
-- Rules: docs\CTRBLXAI.db game_flow 34-39; plan PLAN_questboard_redesign_20261117.md sections 2/6.
-- Replaces the guild menu's old sortie text pages (overview / Quest details / Sortie).
--
-- Layout (GuildScreen, framed header like the Board view): crest + "QUEST BOARD" | status | currencies.
--   Main : the quest's biome background (Theme.DungeonBiomeBackgrounds[q.biome]) with the quest name.
--   Side : "Quest accepted", level / biome / Battle Field Condition, deploy limit, goal, elite note,
--          rewards (gold, mercury, Renown, promised gear), the party line.
--   Buttons (2 rows, lower right): Choose party | Cancel — {fee} gold
--                                  Embark | Back
--
-- Display + input only (ARC-001 / SEC-002): every action goes through the guild menu (ctx), which
-- keeps the existing server calls unchanged: Choose party -> Loadout PARTIES pick mode (step 4 builds
-- the new Choose Party view), Embark -> StartBattle or the existing deferred embark (game_flow 37:
-- no loading bar; Embark is blocked until the map is ready, existing "Departing when ready..."),
-- Cancel -> AbandonQuest after a confirm prompt.
--
-- Text: ONLY approved lines, used verbatim:
--   game_flow 39: "Quest accepted" (8), "Cancel — {fee} gold" (9), "Choose party" (10),
--     "Level {a} – {b}" / "Level {n}" (2), "Biome: {biome}" (3), "Rewards" (4),
--     promised gear "{Rarity} {gear type}" (5).
--   game_flow 41: the goal label / sentence (QuestGoalText, the one place for them).
--   rule 275 (11:39 AM): "Battle Field Condition: {condition}".
--   Existing sortie / quest lines (old guild-menu pages): "QUEST BOARD", "Embark", "Party: {name}",
--     "your party", "Departing when ready...", the embark phrases + "...", "Deploy up to {n} units",
--     the elite war band note, "{g} gold + kills" / "{a}-{b} gold", " + {n} mercury",
--     "+{n} Renown" / " (too easy)", "Abandoning forfeits half the posted gold." (confirm prompt),
--     "Abandon quest" (only when the server sent no cancel fee).

local WAIT = 10

local uiFolder = script.Parent
local themeModule = uiFolder:WaitForChild("Theme", WAIT)
local guildScreenModule = uiFolder:WaitForChild("GuildScreen", WAIT)
local goalTextModule = uiFolder:WaitForChild("QuestGoalText", WAIT)
if not themeModule or not guildScreenModule then
	error("[QuestAcceptedView] Theme / GuildScreen module not found")
end
-- Found at runtime via WaitForChild; the editor cannot follow that path (editor-only cast).
local Theme: any = (require :: any)(themeModule)
local GuildScreen: any = (require :: any)(guildScreenModule)
local QuestGoalText: any = if goalTextModule then (require :: any)(goalTextModule) else nil
if not QuestGoalText then warn("[QuestAcceptedView] QuestGoalText missing -- no goal lines") end

-- Gear names for the promised gear line (same lookup as the Board view). Missing -> line hidden.
local WeaponData: any, ArmorData: any = nil, nil
do
	local rs = game:GetService("ReplicatedStorage")
	local content = rs:WaitForChild("Content", WAIT)
	if content then
		local w = content:WaitForChild("WeaponData", WAIT)
		local a = content:WaitForChild("ArmorData", WAIT)
		local okW, W = pcall(function() return if w then (require :: any)(w) else nil end)
		local okA, A = pcall(function() return if a then (require :: any)(a) else nil end)
		WeaponData = if okW then W else nil
		ArmorData = if okA then A else nil
	end
	if not WeaponData or not ArmorData then
		warn("[QuestAcceptedView] WeaponData / ArmorData missing -- promised gear line hidden")
	end
end

local QuestAcceptedView = {}

-- What the guild menu knows about the accepted quest right now.
export type State = {
	quest: any,               -- the accepted quest (chosenQuest / PreBattle payload)
	partyName: string?,       -- the saved party that will deploy (nil -> "your party")
	locked: boolean,          -- the map is still being built (sortieLocked)
	departPending: boolean,   -- Embark was tapped while locked; departs on MapBuildComplete
}

export type Context = {
	parent: Instance,                    -- PlayerGui
	isBusy: () -> boolean,
	getState: () -> State?,
	embarkLines: { string },             -- existing embark phrases (shown with "..." while locked)
	onChooseParty: () -> (),             -- opens the Loadout PARTIES tab in pick mode
	onEmbark: () -> (),                  -- StartBattle now, or the deferred embark when locked
	onCancelQuest: () -> (),             -- fires AbandonQuest (after the confirm prompt here)
	onBack: () -> (),                    -- back to the guild menu (the quest stays accepted)
}

local GAP = 8
local NAME_H = 34
local CYCLE_SECONDS = 2

-- Existing lines (old guild-menu sortie pages), verbatim.
local TXT_EMBARK = "Embark"
local TXT_DEPARTING = "Departing when ready..."
local TXT_PARTY_DEFAULT = "your party"
local TXT_ELITE = "Scouts report an elite war band! An Elite leads it, with one extra enemy. Win for extra rewards: mercury, crystals, maybe a rune gem, and a chance at better gear."
local TXT_ABANDON_NOTE = "Abandoning forfeits half the posted gold."
local TXT_ABANDON = "Abandon quest"

local ctx: Context? = nil
local screen: any = nil
local isOpen = false
local curGold: number? = nil
local curRes: any = nil
local cycleToken = 0
-- Cancel sent (Tester WARN-3, 2026-11-18): further Cancel taps are ignored until the server answers
-- (it re-opens the base, which hides this view) -- one AbandonQuest per confirm.
local cancelSent = false
local render: () -> () = function() end

--------------------------------------------------
-- TEXT (approved lines only; "" = hide the line)
--------------------------------------------------

local function levelText(q: any): string
	local lo = tonumber(q.levelMin)
	local hi = tonumber(q.levelMax)
	if lo and hi then
		if lo > hi then lo, hi = hi, lo end
		if lo == hi then return `Level {lo}` end
		return `Level {lo} – {hi}`
	end
	local one = tonumber(q.recommendedLvl)
	return if one then `Level {one}` else ""
end

local function biomeText(q: any): string
	return if type(q.biome) == "string" and q.biome ~= "" then `Biome: {q.biome}` else ""
end

local function conditionText(q: any): string
	return if type(q.condition) == "string" and q.condition ~= "" then `Condition: {q.condition}` else ""
end

local function goalLine(q: any): string
	if not QuestGoalText or not q.goal then return "" end
	return QuestGoalText.CardLine(q.goal)
end

local function goalSentence(q: any): string
	if not QuestGoalText or not q.goal then return "" end
	-- Capture / Kill target name their unit only in battle (same rule as the Board view).
	if q.goal == "Capture" or q.goal == "KillTarget" then return "" end
	local gp = q.goalParams or {}
	return QuestGoalText.Sentence({ id = q.goal, rounds = gp.rounds, total = gp.objects or gp.killTarget,
		lossAt = gp.lossAt })
end

local function goldText(q: any): string
	local g = q.rewards and q.rewards.gold
	if type(g) ~= "table" or g.min == nil then return "" end
	return if g.min == g.max then `{g.min} gold + kills` else `{g.min}-{g.max} gold`
end

local function mercuryOf(q: any): number
	return if q.rewards then (tonumber(q.rewards.mercury) or 0) else 0
end

local function renownText(q: any): string
	local rp = q.renownPreview
	if type(rp) ~= "table" or not tonumber(rp.amount) then return "" end
	return `+{rp.amount} Renown` .. (if rp.tooEasy then " (too easy)" else "")
end

local function promisedText(q: any): (string, string?)
	local pg = q.rewards and q.rewards.promisedGear
	if type(pg) ~= "table" or type(pg.archetypeId) ~= "string" or type(pg.rarity) ~= "string" then return "", nil end
	local def = (WeaponData and WeaponData.GetByArchetypeId and WeaponData.GetByArchetypeId(pg.archetypeId))
		or (ArmorData and ArmorData.GetByArchetypeId and ArmorData.GetByArchetypeId(pg.archetypeId))
	if type(def) ~= "table" or type(def.name) ~= "string" then return "", nil end
	return `{pg.rarity} {def.name}`, pg.rarity
end

local function rarityColor(r: string?): Color3
	if r and Theme.GetRarityColor then
		local ok, c = pcall(Theme.GetRarityColor, r)
		if ok and typeof(c) == "Color3" then return c end
	end
	return Theme.Colors.TextPrimary
end

-- Cancel button label: the approved "Cancel — {fee} gold" when the server sent the fee; otherwise
-- the existing "Abandon quest" (never a fee the client worked out itself).
local function cancelLabel(q: any): string
	local fee = tonumber(q.cancelFee)
	-- fee 0 / missing -> existing "Abandon quest" (user 2026-11-18 12:03 AM)
	return if fee and fee > 0 then `Cancel — {math.floor(fee)} gold` else TXT_ABANDON
end

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
	lbl.TextWrapped = true
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextYAlignment = Enum.TextYAlignment.Top
	lbl.Size = UDim2.new(1, 0, 0, 0)
	lbl.AutomaticSize = Enum.AutomaticSize.Y
	lbl.Text = text
	lbl.Parent = parent
	return lbl
end

local function makeInspector(): (ScrollingFrame, (text: string, size: number, color: Color3, bold: boolean?) -> ())
	local sc = Instance.new("ScrollingFrame")
	sc.Name = "Detail"
	sc.Size = UDim2.fromScale(1, 1)
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
	list.Padding = UDim.new(0, 3)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = sc
	local order = 0
	local function add(text: string, size: number, color: Color3, bold: boolean?)
		if text == "" then return end
		order += 1
		local l = makeText(sc, text, size, color, bold)
		l.LayoutOrder = order
	end
	return sc, add
end

local function makeRow(parent: Instance, order: number): Frame
	local row = Instance.new("Frame")
	row.Name = `Row{order}`
	row.Size = UDim2.new(1, 0, 0, GuildScreen.ROW_H)
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, GuildScreen.ROW_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	row.Parent = parent
	return row
end

local function setLabel(btn: Instance?, text: string)
	if not btn then return end
	local lbl = btn:FindFirstChild("Label")
	if lbl and lbl:IsA("TextLabel") then lbl.Text = text end
end

--------------------------------------------------
-- RENDER
--------------------------------------------------

local function renderScene(q: any)
	local main = screen.Main
	local art = Theme.DungeonBiomeBackgrounds and type(q.biome) == "string" and Theme.DungeonBiomeBackgrounds[q.biome]
	local bg = Instance.new("ImageLabel")
	bg.Name = "Scene"
	bg.BackgroundColor3 = Theme.Colors.Background
	bg.BackgroundTransparency = if art then 1 else 0
	bg.BorderSizePixel = 0
	bg.Image = if type(art) == "string" then art else ""
	bg.ScaleType = Enum.ScaleType.Crop
	bg.Size = UDim2.fromScale(1, 1)
	bg.ZIndex = 0
	bg.Parent = main

	-- Quest name over the art, bottom-left, dark outline so it reads on any biome.
	local name = Instance.new("TextLabel")
	name.Name = "QuestName"
	name.BackgroundTransparency = 1
	name.BorderSizePixel = 0
	name.Font = Theme.Font.PrimaryBold
	name.TextColor3 = Theme.Colors.TextGold
	name.TextStrokeColor3 = Color3.new(0, 0, 0)
	name.TextStrokeTransparency = 0.2
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextYAlignment = Enum.TextYAlignment.Bottom
	name.TextScaled = true
	name.TextWrapped = true
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = Theme.Text.Heading()
	cap.MinTextSize = 10
	cap.Parent = name
	name.AnchorPoint = Vector2.new(0, 1)
	name.Position = UDim2.new(0, GAP, 1, -GAP)
	name.Size = UDim2.new(1, -GAP * 2, 0, NAME_H)
	name.Text = tostring(q.name or "")
	name.ZIndex = 2
	name.Parent = main
end

local function renderInspector(q: any, st: State)
	local sc, add = makeInspector()
	local small = Theme.Text.Small()
	local bodyT = Theme.Text.Body()
	add("Quest accepted", Theme.Text.Heading(), Theme.Colors.TextGold, true)
	add(levelText(q), bodyT, Theme.Colors.TextPrimary)
	add(biomeText(q), bodyT, Theme.Colors.TextPrimary)
	add(conditionText(q), bodyT, Theme.Colors.TextPrimary)
	if tonumber(q.playerSlots) then add(`Deploy up to {q.playerSlots} units`, bodyT, Theme.Colors.TextPrimary) end
	add(goalLine(q), bodyT, Theme.Colors.TextGold, true)
	add(goalSentence(q), bodyT, Theme.Colors.TextPrimary)
	if q.elite then add(TXT_ELITE, small, Theme.Colors.TextSecondary) end
	local gt = goldText(q)
	local merc = mercuryOf(q)
	local rt = renownText(q)
	local pText, pRarity = promisedText(q)
	if gt ~= "" or merc > 0 or rt ~= "" or pText ~= "" then
		add("Rewards", bodyT, Theme.Colors.TextGold, true)
		local reward = gt
		if merc > 0 then reward = if reward ~= "" then `{reward} + {merc} mercury` else `{merc} mercury` end
		add(reward, bodyT, Theme.Colors.TextPrimary)
		add(rt, bodyT, Theme.Colors.TextPrimary)
		add(pText, bodyT, rarityColor(pRarity), true)
	end
	add(`Party: {st.partyName or TXT_PARTY_DEFAULT}`, bodyT, Theme.Colors.TextPrimary, true)
	sc.Parent = screen.Side
end

-- Embark label: "Embark" when the map is ready; otherwise the existing embark phrases with "..."
-- (cycling), or "Departing when ready..." once the tap is deferred.
local function embarkText(st: State, idx: number): string
	if not st.locked then return TXT_EMBARK end
	if st.departPending then return TXT_DEPARTING end
	local lines = if ctx then ctx.embarkLines else {}
	local line = lines[((idx - 1) % math.max(1, #lines)) + 1]
	return if line then line .. "..." else TXT_DEPARTING
end

local function renderButtons(q: any, st: State)
	local c = ctx
	if not c then return end
	local holder = Instance.new("Frame")
	holder.Name = "Rows"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	local vl = Instance.new("UIListLayout")
	vl.FillDirection = Enum.FillDirection.Vertical
	vl.Padding = UDim.new(0, GuildScreen.ROW_GAP)
	vl.SortOrder = Enum.SortOrder.LayoutOrder
	vl.Parent = holder
	local half = UDim2.new(0.5, -(GuildScreen.ROW_GAP // 2 + 1), 0, GuildScreen.ROW_H)

	-- Row 1: Choose party | Cancel — {fee} gold
	local r1 = makeRow(holder, 1)
	Theme.MakeBarButton(r1, "Choose party", "Secondary", function()
		local cc = ctx
		if not cc or cc.isBusy() then return end
		cc.onChooseParty()
	end, { name = "Btn_ChooseParty", minHeight = GuildScreen.ROW_H, size = half, autoWidth = false, layoutOrder = 1 })
	local cancelBtn = Theme.MakeBarButton(r1, cancelLabel(q), "Tertiary", function()
		local cc = ctx
		if not cc or cc.isBusy() or not screen or cancelSent then return end
		local label = cancelLabel(q)
		-- APPROVED 2026-11-18 12:03 AM: "Cancel this quest? You lose {fee} gold." + "Keep quest".
		-- Fee 0 / missing: no approved variant, so the existing note is kept.
		local fee = tonumber(q.cancelFee)
		local msg = if fee and fee > 0 then `Cancel this quest? You lose {math.floor(fee)} gold.` else TXT_ABANDON_NOTE
		screen.Prompt(msg, label, "Danger", function() -- 2026-11-18: destructive (darker check)
			local c2 = ctx
			if not c2 or cancelSent then return end
			cancelSent = true
			c2.onCancelQuest()
		end, "Keep quest")
	end, { name = "Btn_CancelQuest", minHeight = GuildScreen.ROW_H, size = half, autoWidth = false, layoutOrder = 2 })
	-- Red text marks the paid cancel (there is no red bar art; Tertiary + red label).
	local cl = cancelBtn and cancelBtn:FindFirstChild("Label")
	if cl and cl:IsA("TextLabel") then cl.TextColor3 = Theme.Colors.Danger end

	-- Row 2: Embark | Back
	local r2 = makeRow(holder, 2)
	local embarkW = UDim2.new(1, -(GuildScreen.ROW_H + GuildScreen.ROW_GAP), 0, GuildScreen.ROW_H)
	local embarkBtn = Theme.MakeBarButton(r2, embarkText(st, 1), if st.departPending then "Disabled" else "Primary", function()
		local cc = ctx
		if not cc or cc.isBusy() then return end
		local now = cc.getState()
		if now and now.departPending then return end -- already deferred: departs once on MapBuildComplete
		cc.onEmbark()
	end, { name = "Btn_Embark", minHeight = GuildScreen.ROW_H, size = embarkW, autoWidth = false, layoutOrder = 1 })
	local back = Theme.MakeIconButton(nil, "Back", function()
		local cc = ctx
		if cc then cc.onBack() end
	end, { name = "Btn_BACK", size = UDim2.fromOffset(GuildScreen.ROW_H, GuildScreen.ROW_H) })
	back.LayoutOrder = 99
	back.Parent = r2
	holder.Parent = screen.Buttons

	-- While the map is being built, cycle the existing embark phrases on the button (self-cancels
	-- when the view re-renders, closes, or the map is ready).
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
	screen.Clear("Accepted")
	local st = c.getState()
	if not st or type(st.quest) ~= "table" then return end
	renderScene(st.quest)
	renderInspector(st.quest, st)
	renderButtons(st.quest, st)
end

--------------------------------------------------
-- PUBLIC (same shape as the other guild screens)
--------------------------------------------------

function QuestAcceptedView.Init(c: Context)
	ctx = c
end

function QuestAcceptedView.IsOpen(): boolean
	return isOpen
end

function QuestAcceptedView.GetGui(): ScreenGui?
	return if isOpen and screen then screen.Gui else nil
end

-- Opens the view, or re-renders it when already open (party picked, map ready, embark deferred).
function QuestAcceptedView.Open()
	local c = ctx
	if not c then
		warn("[QuestAcceptedView] Open called before Init")
		return
	end
	if not screen then
		screen = GuildScreen.Create({ name = "QuestAcceptedView", title = "QUEST BOARD", parent = c.parent,
			crest = Theme.GuildIcons.AdventurersGuild }) -- same crest as the Board view
		screen.SetButtonRows(2)
	end
	if not isOpen then
		isOpen = true
		cancelSent = false
		screen.SetStatus("")
		screen.Show()
		applyCurrencies()
	end
	render()
end

function QuestAcceptedView.Refresh()
	if isOpen then render() end
end

-- Forced hide (menu re-opened / closed by the server, battle starting, back to the menu).
function QuestAcceptedView.Hide()
	if not isOpen then return end
	isOpen = false
	cancelSent = false
	cycleToken += 1
	if screen then screen.ClosePrompt(); screen.Hide() end
end

function QuestAcceptedView.SetGold(text: string)
	if screen then screen.SetGold(text) end
end

function QuestAcceptedView.SetCurrencies(gold: number, res: any)
	curGold = gold
	curRes = res
	if isOpen then applyCurrencies() end
end

function QuestAcceptedView.SetStatus(text: string, isError: boolean?)
	if screen then screen.SetStatus(text, isError) end
end

return table.freeze(QuestAcceptedView)
