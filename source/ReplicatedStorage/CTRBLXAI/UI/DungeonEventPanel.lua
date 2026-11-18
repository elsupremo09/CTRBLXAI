--!strict
-- DungeonEventPanel.lua
-- CTRBLXAI | Dungeon Event room panel (Dungeon build step 7a, 2026-11-14; project_rules 272 / 275).
-- Split out of DungeonScreen.lua (990 lines) so that file stays under 1000.
--
-- Display + input only (ARC-001 / SEC-002): the client sends a choice key, the server resolves and
-- applies it (DungeonAction EventState / EventChoose) and answers with fresh state + result lines.
-- TEXT: all strings approved (events approved 2026-11-14 10:19 AM, workspace DRAFT_dungeon_events_20261114.md;
-- shared EV-UI strings rule 275). Ids in comments.

local uiFolder = script.Parent
local Theme: any = (require :: any)(uiFolder:WaitForChild("Theme", 10))
local GuildScreen: any = (require :: any)(uiFolder:WaitForChild("GuildScreen", 10))

local DungeonEventPanel = {}

export type Ctx = {
	gui: Instance,
	act: (data: { [string]: any }) -> any?,
	onFight: () -> (),     -- the event turned into a fight: launch the room battle
	onDone: () -> (),      -- room cleared: close + re-render the map
	lastError: (() -> string?)?, -- step 7b (Tester W3): last server refusal text
	onCourier: ((ev: any) -> ())?, -- EV-17 "Send items home": open the Courier's Rest picker (DungeonBagPanel)
}

-- Approved event text (title, story, choice labels). {cost} is filled from the server quote.
-- Silver step 2: EV-03 / EV-04 / EV-08 / EV-13 g2m labels and the silver result lines are SB-35..39,
-- SB-04/05, SB-36 (approved 2026-11-15 9:09 PM, rule 275).
local EVENTS = {
	["EV-01"] = { "Forgotten Cache", "A rotted crate hides under the rubble. Something still glints inside.",
		{ open = "Open it", leave = "Leave it" }, { "open", "leave" } },
	["EV-02"] = { "Healing Spring", "Clear water bubbles from the stone. It feels warm to the touch.",
		{ drink = "Drink", flask = "Fill a flask", move = "Move on" }, { "drink", "flask", "move" } },
	["EV-03"] = { "Wandering Peddler", "A hooded peddler waves you over. \"Charges, fresh charges. Cheap.\"",
		{ buy = "Buy refills ({cost} silver)", no = "No thanks" }, { "buy", "no" } },
	["EV-04"] = { "Fallen Adventurer", "A long-dead adventurer clutches a coin pouch. No one will miss it now.",
		{ pouch = "Take the pouch (+30 silver)", bury = "Bury them" }, { "pouch", "bury" } },
	["EV-05"] = { "Lucky Shrine", "A tiny shrine to a forgotten god of fortune. Coins cover the altar.",
		{ offer = "Leave an offering (100g)", walk = "Walk away" }, { "offer", "walk" } },
	["EV-06"] = { "Blood Altar", "A stained altar hums with dark power. It asks for blood.",
		{ offer = "Offer blood", refuse = "Refuse" }, { "offer", "refuse" } },
	["EV-07"] = { "Sealed Door", "A heavy door, sealed with old chains. Something moves behind it.",
		{ ["break"] = "Break the seal", leave = "Leave it shut" }, { "break", "leave" } },
	["EV-08"] = { "Gambler's Table", "A grinning skeleton shuffles cards. \"One game, traveler?\"",
		{ bet = "Bet 20 silver", walk = "Walk away" }, { "bet", "walk" } },
	["EV-09"] = { "Collapsing Tunnel", "The ceiling groans. Rocks start falling all around you.",
		{ run = "Run for it", shield = "Shield the weakest" }, { "run", "shield" } },
	["EV-10"] = { "Cutpurse Ambush", "Shadows close in. \"Your bag, or your blood.\"",
		{ hand = "Hand over loot", fight = "Fight" }, { "hand", "fight" } },
	-- EV-11..16 (approved 2026-11-15 1:42 AM, rule 275; workspace DRAFT_dungeon_stages_events_relics_20261115.md).
	["EV-11"] = { "Kindred Shrine", "A shrine carved for your kin. Its keeper bows to those who share the old blood.",
		{ pray = "Pray", move = "Move on" }, { "pray", "move" } },
	["EV-12"] = { "Smith's Wager", "A wandering smith eyes your gear. 'Leave me one, and I'll forge you better by the next fork.'",
		{ hand = "Hand over gear", keep = "Keep it" }, { "hand", "keep" } },
	["EV-13"] = { "Barter Post", "A trader with full packs. She takes any coin or stone, at her price.",
		{ m2c = "Mercury → Crystals", c2m = "Crystals → Mercury", g2m = "40 silver → 1 Mercury", leave = "Move on" }, { "m2c", "c2m", "g2m", "leave" } },
	["EV-14"] = { "Campfire", "Embers still warm. Someone camped here not long ago.",
		{ rest = "Rest a while", search = "Search the camp" }, { "rest", "search" } },
	["EV-15"] = { "Forge of Chance", "An anvil hums with old magic. It can raise a weapon's worth, but never as it was.",
		{ reforge = "Reforge", leave = "Leave it" }, { "reforge", "leave" } },
	-- EV-16 Altar of Change (text approved 2026-11-15 10:17 AM; replaces Shifting Hall).
	["EV-16"] = { "Altar of Change", "A cracked altar hums with old magic. It can reshape one of your units, for better or worse.",
		{ reshape = "Reshape a unit", leave = "Leave" }, { "reshape", "leave" } },
	-- EV-17 Courier's Rest (SB-26..SB-29, approved 2026-11-15 9:09 PM, rule 275).
	["EV-17"] = { "Courier's Rest", "A guild courier rests by the path. \"I can carry a few things home for you — for a fee.\"",
		{ send = "Send items home", move = "Move on" }, { "send", "move" } },
}
-- EV-12 / EV-15 open a gear pick from the run bag first (approved lines below).
local GEAR_PICK = { ["EV-12"] = { key = "hand", title = "Choose a gear to hand over" }, ["EV-15"] = { key = "reforge", title = "Choose a gear to reforge" } }
-- Barter resource names, capitalised (approved 2026-11-15 10:08 AM): "Traded 10 Mercury for 1 Crystals"
-- Rule 275 approves Crystal/Crystals: 1 reads "Crystal", 2+ "Crystals" (2026-11-15).
local RES_NAME = { gold = "Gold", mercury = "Mercury", crystals = "Crystals", silver = "Silver" } -- silver: approved Barter format (rule 275)
local function resWord(id: string, n: number): string
	if id == "crystals" and n == 1 then return "Crystal" end
	return RES_NAME[id] or id
end

local MAT_NAME = { mercury = "Mercury" }

local overlay: Instance? = nil
local lastCtx: Ctx? = nil

local function close()
	if overlay then
		overlay:Destroy()
		overlay = nil
	end
end

local function text(parent: Instance?, s: string, size: number, color: Color3, bold: boolean?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Font = if bold then Theme.Font.PrimaryBold else Theme.Font.Primary
	l.TextSize = math.max(10, size) -- 10 px phone floor
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.Text = s
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.ZIndex = 22
	l.Parent = parent
	return l
end

-- Result line text (EV-UI-*). Returns nil for a line kind with no text.
local function lineText(l: any): string?
	if l.k == "bagGold" then
		return if l.n >= 0 then `+{l.n} gold (in your bag)` else `−{-l.n} gold`  -- EV-UI-GOLD
	elseif l.k == "realGold" then
		return if l.n >= 0 then `+{l.n} gold` else `−{-l.n} gold`                  -- EV-UI-GOLD-REAL
	elseif l.k == "silver" then -- SB-04 / SB-05
		return if l.n >= 0 then `+{l.n} silver` else `−{-l.n} silver`
	elseif l.k == "silverLost" then -- EV-10 Cutpurse: SB-36
		return `The cutpurse took {l.n or 0} silver.`
	elseif l.k == "gear" then
		return `Found {l.name or "an item"}! It's in your bag.`                     -- EV-UI-GEAR
	elseif l.k == "mat" then
		return `+{l.n} {MAT_NAME[l.id] or tostring(l.id)} (in your bag)`            -- EV-UI-MAT
	elseif l.k == "heal" then
		return `Your party heals {l.n}%.`                                           -- EV-UI-HEAL
	elseif l.k == "hurt" then
		return `Your party loses {l.n}% HP.`                                        -- EV-UI-HURT
	elseif l.k == "revive" then
		return `{l.name or "?"} is back on their feet.`                             -- EV-UI-REVIVE
	elseif l.k == "loot" then
		return `Loot +{math.floor(((tonumber(l.mult) or 1) - 1) * 100 + 0.5)}%` -- EV-UI-LOOT, percent not decimal (user 2026-11-17 12:00 PM)
	elseif l.k == "fight" then
		return "Enemies attack!"                                                     -- EV-UI-FIGHT
	elseif l.k == "nothing" then
		return "Nothing happens."                                                    -- EV-UI-NOTHING
	elseif l.k == "trade" then -- EV-13 "Traded {n} {From} for {m} {To}" (approved 2026-11-15 10:08 AM)
		return `Traded {l.giveN} {resWord(l.give, l.giveN)} for {l.getN} {resWord(l.get, l.getN)}`
	elseif l.k == "kinHeal" then -- EV-11 race shrine (approved 2026-11-15 10:08 AM)
		return `Your {l.race or "?"}s heal {l.n}%.`
	elseif l.k == "buff" then -- EV-11 doctrine shrine (approved 2026-11-15 10:08 AM)
		return `The shrine blesses your {l.doctrine or "?"}s.`
	elseif l.k == "refilled" then -- EV-14 Campfire "Search the camp" (approved 2026-11-15 10:08 AM)
		return "All consumables are refilled — even the ones in your bag." -- SB-43 (approved 2026-11-15 9:09 PM)
	elseif l.k == "altar" then -- EV-16 Altar of Change result (approved 2026-11-15 10:17 AM)
		return `{l.unit or "?"}'s {l.old or "?"} became {l.new or "?"}.`
	elseif l.k == "smith" then
		return "The smith will find you at the next Event, Sanctuary or boss."             -- approved 2026-11-15 2:05 AM
	elseif l.k == "courier" then -- EV-17 result (SB-33)
		return "Sent home! They'll be waiting for you."
	elseif l.k == "forged" then -- EV-15: the reforged item is in the bag (reuses EV-UI-GEAR)
		return `Found {l.name or "an item"}! It's in your bag.`
	end
	return nil
end

local function shell(name: string): (Instance, Frame)
	close()
	-- Shared guild popup box, below the Roblox top bar (2026-11-17 style fix).
	local o, box = GuildScreen.MakeModalBox(name, { maxW = 480, widthScale = 0.8, pad = 14 })
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = box
	return o, box
end

local function buttonRow(box: Frame, order: number): Frame
	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.Size = UDim2.new(1, 0, 0, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	local rl = Instance.new("UIListLayout")
	rl.FillDirection = Enum.FillDirection.Horizontal
	rl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	rl.Wraps = true
	rl.Padding = UDim.new(0, 6)
	rl.SortOrder = Enum.SortOrder.LayoutOrder
	rl.Parent = row
	row.Parent = box
	return row
end

local renderResult: (ev: any, res: any) -> () = function() end
local renderGearPick: (ev: any, gp: any) -> () = function() end

local renderChoices: (ev: any, note: string?) -> () -- forward declaration (EV-13 re-open after a trade)
local renderAltar: (ev: any) -> () = function() end
local function choose(ev: any, key: string, gearId: string?)
	local c = lastCtx
	if not c then return end
	local res = c.act({ action = "EventChoose", choice = key, gearId = gearId })
	if res and res.eventResult then
		if ev.id == "EV-13" and key ~= "leave" and not res.eventResult.done then
			local st = c.act({ action = "EventState" })
			local nev = st and st.eventRoom
			if nev and not nev.done then
				local first = res.eventResult.lines and res.eventResult.lines[1]
				renderChoices(nev, if first then lineText(first) else nil) -- the trade line above the remaining trades
				return
			end
		end
		renderResult(ev, res.eventResult) return
	end
	-- Tester 7a W3: refused (e.g. "Not enough gold") -> show the approved server message in the panel.
	if not res and c.lastError then
		local msg = c.lastError()
		if type(msg) == "string" and msg ~= "" and overlay then
			local box = overlay:FindFirstChild("Box")
			local old = box and box:FindFirstChild("Refusal")
			if old then old:Destroy() end
			if box then
				local lbl = text(box, msg, Theme.Text.Body(), Theme.Colors.Danger or Theme.Colors.TextPrimary, true)
				lbl.Name = "Refusal"
				lbl.LayoutOrder = 99
			end
		end
	end
end

function renderChoices(ev: any, note: string?)
	local c = lastCtx
	if not c then return end
	local def = EVENTS[ev.id]
	if not def then return end
	local o, box = shell("EventPanel")
	-- EV-11 doctrine variant uses the approved title "Hall of the {doctrine}".
	local title = if ev.id == "EV-11" and ev.kin and ev.kin.kind == "doctrine" then `Hall of the {ev.kin.name or "?"}` else def[1]
	local t = text(box, title, Theme.Text.Heading(), Theme.Colors.TextGold, true)  -- EV-UI-TITLE
	t.LayoutOrder = 1
	local s = text(box, def[2], Theme.Text.Body(), Theme.Colors.TextPrimary)
	s.LayoutOrder = 2
	if note then -- EV-13: the last trade's result line (approved text)
		local nl2 = text(box, note, Theme.Text.Body(), Theme.Colors.TextGold, true)
		nl2.LayoutOrder = 2
	end
	if ev.id == "EV-11" and ev.kin and ev.kin.kind == "race" then
		local k = text(box, `Only those of the {ev.kin.name or "?"} bloodline may pray here.`, Theme.Text.Body(), Theme.Colors.TextSecondary or Theme.Colors.TextPrimary)
		k.LayoutOrder = 2
	end
	local row = buttonRow(box, 3)
	for i, key in def[4] do
		if key == "flask" and not ev.hasKO then continue end -- shown only if a unit is KO'd (draft)
		if ev.traded and ev.traded[key] then continue end -- EV-13: each trade once per room (2026-11-15)
		local label = def[3][key]
		if key == "buy" then
			local q = ev.refill
			if not q or (q.missing or 0) <= 0 then continue end -- nothing to refill: no buy choice
			label = string.gsub(label, "{cost}", tostring(if (q.cost or 0) > 0 then q.cost else (q.need or 0)))
		end
		local style = if i == 1 then "Primary" else "Secondary"
		local gp = GEAR_PICK[ev.id]
		if gp and key == gp.key then -- EV-12 / EV-15: no usable gear in the bag -> no choice
			local any = false
			for _, g in ev.bagGear or {} do if g.ok then any = true end end
			if not any then continue end
		end
		if key == "reshape" and #(ev.altarUnits or {}) == 0 then continue end -- EV-16: no unit with a trait
		local b = Theme.MakeBarButton(nil, label, style, function()
			if gp and key == gp.key then renderGearPick(ev, gp)
			elseif key == "reshape" then renderAltar(ev)
			elseif key == "send" and ev.id == "EV-17" then if c.onCourier then close() c.onCourier(ev) end
			else choose(ev, key) end
		end, {
			name = "Btn_" .. key, minHeight = GuildScreen.ROW_H })
		b.LayoutOrder = i
		b.Parent = row
	end
	o.Parent = c.gui -- parent last (NET-004)
	overlay = o
end

-- EV-12 / EV-15: pick one gear from the run bag (approved title; rows = item names; Back = the event).
renderGearPick = function(ev: any, gp: any)
	local c = lastCtx
	if not c then return end
	local o, box = shell("EventGearPick")
	local t = text(box, gp.title, Theme.Text.Heading(), Theme.Colors.TextGold, true)
	t.LayoutOrder = 1
	local list = Instance.new("ScrollingFrame")
	list.Name = "Gear"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.new(1, 0, 0, 150)
	list.ScrollBarThickness = 3
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.LayoutOrder = 2
	list.ZIndex = 22
	local ll = Instance.new("UIListLayout")
	ll.Padding = UDim.new(0, 4)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = list
	for i, g in ev.bagGear or {} do
		local label = `{g.name}  Lv.{g.level or "?"}` -- DGM-GEAR-NAME (approved)
		local style = if g.ok then "Secondary" else "Disabled"
		local btn = Theme.MakeBarButton(nil, label, style, function()
			if g.ok then choose(ev, gp.key, g.id) end
		end, { name = "Btn_Gear" .. i, minHeight = GuildScreen.ROW_H })
		btn.LayoutOrder = i
		btn.Parent = list
		if not g.ok then
			local note = text(list, "Can't reforge this rarity", Theme.Text.Small and Theme.Text.Small() or 12, Theme.Colors.TextSecondary or Theme.Colors.TextPrimary)
			note.LayoutOrder = i
		end
	end
	list.Parent = box
	local row = buttonRow(box, 100)
	local back = Theme.MakeIconButton(nil, "Back", function() renderChoices(ev) end, {
		name = "Btn_Back", size = UDim2.fromOffset(GuildScreen.ROW_H, GuildScreen.ROW_H) })
	back.Parent = row
	o.Parent = c.gui -- parent last (NET-004)
	overlay = o
end

-- EV-16 Altar of Change (text approved 2026-11-15 10:17 AM; flow per rule 272): pick a unit -> pick its
-- perk or flaw -> pick one of 3 seeded replacements -> confirm. The server rolls and applies (ids only).
local function listBox(box: Frame, order: number): ScrollingFrame
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.new(1, 0, 0, 150)
	list.ScrollBarThickness = 3
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.LayoutOrder = order
	list.ZIndex = 22
	local ll = Instance.new("UIListLayout")
	ll.Padding = UDim.new(0, 4)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = list
	return list
end

local function rowButton(parent: Instance, label: string, order: number, onTap: () -> ())
	local btn = Theme.MakeBarButton(nil, label, "Secondary", onTap, { name = "Btn_Row" .. order, minHeight = GuildScreen.ROW_H })
	btn.LayoutOrder = order
	btn.Parent = parent
end

local function backRow(box: Frame, onBack: () -> ())
	local row = buttonRow(box, 100)
	local back = Theme.MakeIconButton(nil, "Back", onBack, { name = "Btn_Back", size = UDim2.fromOffset(GuildScreen.ROW_H, GuildScreen.ROW_H) })
	back.Parent = row
end

local function traitRow(t: any, kind: string): string
	local tier = tostring(t.tier or "?")
	return `{string.upper(string.sub(tier, 1, 1)) .. string.sub(tier, 2)} {kind}: {t.name or "?"}` -- "Rare perk: Iron Will"
end

local function altarConfirm(ev: any, u: any, kind: string, cur: any, pick: any, index: number)
	local c = lastCtx
	if not c then return end
	local o, box = shell("AltarConfirm")
	local t = text(box, `Replace {cur.name or "?"} with {pick.name or "?"}?`, Theme.Text.Heading(), Theme.Colors.TextGold, true)
	t.LayoutOrder = 1
	local w = text(box, "This change is permanent. The new tier may be lower.", Theme.Text.Body(), Theme.Colors.TextPrimary)
	w.LayoutOrder = 2
	local row = buttonRow(box, 3)
	-- 2026-11-18 user: shared Back + check icons (were the "Stay" / "Replace" bars).
	local stay = Theme.MakeIconButton(nil, "Back", function() renderAltar(ev) end, { name = "Btn_Stay", size = UDim2.fromOffset(GuildScreen.ROW_H, GuildScreen.ROW_H) })
	stay.LayoutOrder = 1
	stay.Parent = row
	local rep2 = Theme.MakeIconButton(nil, "Confirm", function()
		local res = c.act({ action = "AltarChoose", unitId = u.id, kind = kind, index = index })
		if res and res.eventResult then renderResult(ev, res.eventResult) end
	end, { name = "Btn_Replace", size = UDim2.fromOffset(GuildScreen.ROW_H, GuildScreen.ROW_H) })
	rep2.LayoutOrder = 2
	rep2.Parent = row
	o.Parent = c.gui -- parent last (NET-004)
	overlay = o
end

local function altarOptions(ev: any, u: any, kind: string)
	local c = lastCtx
	if not c then return end
	local res = c.act({ action = "AltarOptions", unitId = u.id, kind = kind })
	local a = res and res.altar
	if not a then return end
	local o, box = shell("AltarOptions")
	local t = text(box, "Pick its replacement", Theme.Text.Heading(), Theme.Colors.TextGold, true)
	t.LayoutOrder = 1
	local w = text(box, "This change is permanent. The new tier may be lower.", Theme.Text.Body(), Theme.Colors.TextPrimary)
	w.LayoutOrder = 2
	local list = listBox(box, 3)
	for i, opt in a.options or {} do
		rowButton(list, traitRow(opt, kind), i, function() altarConfirm(ev, u, kind, a.current, opt, i) end)
	end
	list.Parent = box
	backRow(box, function() renderAltar(ev) end)
	o.Parent = c.gui
	overlay = o
end

local function altarTraits(ev: any, u: any)
	local c = lastCtx
	if not c then return end
	local o, box = shell("AltarTraits")
	local t = text(box, "Pick a perk or flaw", Theme.Text.Heading(), Theme.Colors.TextGold, true)
	t.LayoutOrder = 1
	local list = listBox(box, 2)
	local n = 0
	for _, kind in { "perk", "flaw" } do
		local cur = u[kind]
		if cur then
			n += 1
			rowButton(list, traitRow(cur, kind), n, function() altarOptions(ev, u, kind) end)
		end
	end
	list.Parent = box
	backRow(box, function() renderAltar(ev) end)
	o.Parent = c.gui
	overlay = o
end

renderAltar = function(ev: any)
	local c = lastCtx
	if not c then return end
	local o, box = shell("AltarUnits")
	local t = text(box, "Pick a unit", Theme.Text.Heading(), Theme.Colors.TextGold, true)
	t.LayoutOrder = 1
	local list = listBox(box, 2)
	for i, u in ev.altarUnits or {} do
		rowButton(list, `{u.name or "?"}  Lv.{u.level or "?"}`, i, function() altarTraits(ev, u) end) -- approved unit row
	end
	list.Parent = box
	backRow(box, function() renderChoices(ev) end)
	o.Parent = c.gui
	overlay = o
end

renderResult = function(ev: any, res: any)
	local c = lastCtx
	if not c then return end
	local def = EVENTS[ev.id] or { "", "" }
	local o, box = shell("EventResult")
	local t = text(box, def[1], Theme.Text.Heading(), Theme.Colors.TextGold, true)
	t.LayoutOrder = 1
	local n = 2
	for _, l in (res and res.lines) or {} do
		local s = lineText(l)
		if s then
			local lbl = text(box, s, Theme.Text.Body(), Theme.Colors.TextPrimary)
			lbl.LayoutOrder = n
			n += 1
		end
	end
	local row = buttonRow(box, 100)
	local fight = res and res.fight
	-- 2026-11-18 user: "Continue" is a Confirm label (Theme ICON_FOR_TEXT) -> shared check icon.
	local b = Theme.MakeIconButton(nil, "Confirm", function()               -- EV-UI-CONT
		close()
		if fight then c.onFight() else c.onDone() end
	end, { name = "Btn_Continue", size = UDim2.fromOffset(GuildScreen.ROW_H, GuildScreen.ROW_H) })
	b.Parent = row
	o.Parent = c.gui
	overlay = o
end

--- Open the Event panel for the current room. Shows the choices, or the saved result if already chosen.
function DungeonEventPanel.Open(ctx: Ctx)
	lastCtx = ctx
	local res = ctx.act({ action = "EventState" })
	local ev = res and res.eventRoom
	if not ev then return end
	if ev.done then
		renderResult(ev, { lines = ev.result or {}, fight = ev.fight })
	else
		renderChoices(ev)
	end
end

DungeonEventPanel.Close = close

function DungeonEventPanel.IsOpen(): boolean
	return overlay ~= nil
end


return table.freeze(DungeonEventPanel)
