--!strict
-- RuneforgeGemCraft.lua
-- CTRBLXAI | Runeforge "Gem Craft" tab (USER RULING 2026-11-12 1:54 PM). Split out of
-- RuneforgeScreen for file size (ARC-005); the screen injects its own helpers through Init
-- (no require of RuneforgeScreen, no circular dependency, ARC-004).
--
--   LEFT   owned rune gems (stat gems; passives in Mix Passives), the same gem tiles and the
--          same Gems bar as the Forge tab. A gem that can't be used now is dimmed with the
--          approved reason.
--   RIGHT  PINNED (never scrolls, 2026-11-12 2:19 PM phone fix): [Upgrade][Break Down][Mix]
--          [Mix Passives] and one row of the action buttons. BELOW, in the scrolling panel: the
--          picked gem name / greyed reason, and the Mix picks.
--   BOTTOM [?] (screen) [- / + = Craft xN count, or - = remove last pick] [X = clear] [Back].
-- Every action opens the approved confirm prompt; the server prices, checks and rolls
-- (SEC-002). A random result is shown in the bonus inspector (no extra text on screen).
-- Display + input only (ARC-001). Tap-only.

local WAIT = 10

local uiFolder = script.Parent
local themeModule = uiFolder:WaitForChild("Theme", WAIT)
local sharedFolder = uiFolder.Parent and uiFolder.Parent:WaitForChild("Shared", WAIT)
local rulesModule = sharedFolder and sharedFolder:WaitForChild("GemCraftRules", WAIT)
if not themeModule or not rulesModule then
	error("[RuneforgeGemCraft] Theme / GemCraftRules module not found")
end
-- Found at runtime via WaitForChild; the editor cannot follow that path (editor-only cast).
local Theme: any = (require :: any)(themeModule)
local Rules: any = (require :: any)(rulesModule)

local RuneforgeGemCraft = {}

local REASONS = Rules.REASONS

-- Approved wording (PROPOSAL_gem_crafting_20261112.md section 6, approved as written).
local TEXT = table.freeze({
	tab = "Gem Craft",
	modes = table.freeze({ Upgrade = "Upgrade", BreakDown = "Break Down", Mix = "Mix", MixPassives = "Mix Passives" }),
	upgrade = "Upgrade (3 \u{2192} 1)",
	breakDown = "Break Down (1 \u{2192} 2)",
	mix = "Mix 5",
	craftN = "Craft \u{00D7}%d",
	craftAll = "Craft All",
	help = "Turn spare gems into better ones. Upgrade: 3 of the same gem make 1 a tier higher. Break Down: 1 gem makes 2 a tier lower (you lose a little). Mix: 5 stat gems of the same tier make 1 random stat gem a tier higher. Mix Passives: 5 passive gems of the same rarity make 1 random passive of that rarity. Costs gold only; the Runeforge level makes it cheaper.",
})

RuneforgeGemCraft.TAB = TEXT.tab
RuneforgeGemCraft.GRID_KEY = "Gem Craft|Gems"
RuneforgeGemCraft.HELP_HEADING = TEXT.tab
RuneforgeGemCraft.HELP_BODY = TEXT.help

local MODE_ORDER = { "Upgrade", "BreakDown", "Mix", "MixPassives" }
local MODE_GAP = 6
local MODE_H = 44 -- touch target
local ACTION_GAP = 4
-- Height of the pinned block (2x2 mode grid + one action row). RuneforgeScreen places the
-- scrolling panel below it, so the action buttons are always on screen (phone 750x382).
RuneforgeGemCraft.PINNED_H = MODE_H * 2 + MODE_GAP + ACTION_GAP + MODE_H

local api: any = nil
local mode = "Upgrade"
local selectedGem: string? = nil -- Upgrade / Break Down
local picks: { string } = {}     -- Mix / Mix Passives: one entry per gem put in
local repeatN = 2                -- Craft xN (Upgrade (3 -> 1) is the x1 button)
local busy = false               -- a craft is waiting for the server
-- Bumped by Reset (screen Open / Close / Hide). A craft answer that arrives after a bump is
-- not shown: no redraw, no result inspector (2026-11-12 2:19 PM late-popup fix). The craft
-- itself already happened on the server, so the guild data is still refreshed.
local gen = 0

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function gemOf(state: any, id: string?): any?
	if not id then return nil end
	for _, g in state.gems or {} do
		if g.id == id then return g end
	end
	return nil
end

local function pickedCount(id: string): number
	local n = 0
	for _, p in picks do
		if p == id then n += 1 end
	end
	return n
end

local function isMixMode(): boolean
	return mode == "Mix" or mode == "MixPassives"
end

local function priceOf(state: any, base: number?): number
	return Rules.Price(base or 0, state.discountPct)
end

local function goldOf(state: any): number
	return tonumber(state.gold) or 0
end

local function tierOf(g: any): number
	return tonumber(g.tier) or 0
end

-- Name of the same family one tier up / down ("Fortune T2"), the DescribeGem name format.
local function shiftName(g: any, delta: number): string
	return `{tostring(g.family)} T{tierOf(g) + delta}`
end

local function pickTier(state: any): number?
	local g = gemOf(state, picks[1])
	return if g then tierOf(g) else nil
end

local function pickRarity(state: any): string?
	local g = gemOf(state, picks[1])
	return if g then g.minRarity else nil
end

-- Drop picks the player no longer owns (after a refresh), and a selected gem that is gone.
local function prune(state: any)
	if selectedGem then
		local g = gemOf(state, selectedGem)
		if not g or g.kind ~= "stat" or (tonumber(g.count) or 0) <= 0 then selectedGem = nil end
	end
	local keep: { string } = {}
	for _, id in picks do
		local g = gemOf(state, id)
		local want = if mode == "MixPassives" then "passive" else "stat"
		if g and g.kind == want then
			local used = 0
			for _, k in keep do if k == id then used += 1 end end
			if used < (tonumber(g.count) or 0) then table.insert(keep, id) end
		end
	end
	picks = keep
end

-- Upgrade: how many crafts the gems AND the gold allow right now (Craft All).
local function upgradeMax(state: any, g: any): number
	local each = priceOf(state, Rules.GOLD.Upgrade[tierOf(g)])
	local byGems = (tonumber(g.count) or 0) // Rules.UPGRADE_INPUTS
	local byGold = if each > 0 then goldOf(state) // each else byGems
	return math.clamp(math.min(byGems, byGold), 0, Rules.MAX_TIMES)
end

--------------------------------------------------
-- CRAFT (server call, then refresh)
--------------------------------------------------

local function doCraft(req: any, showResult: boolean)
	local c = api and api.getCtx()
	if not c or not c.craftGems or busy then return end
	local myGen = gen
	busy = true
	local res = c.craftGems(req)
	if myGen ~= gen then
		if res then c.onChanged() end -- data only; the screen was closed or reset meanwhile
		return
	end
	busy = false
	if res then
		if showResult then table.clear(picks) end
		c.onChanged()
	end
	api.render()
	-- A random result (Mix / Mix Passives) is shown in the bonus inspector.
	if res and showResult and type(res.gained) == "table" and res.gained[1] then
		api.inspectBonus(res.gained[1], false, nil)
	end
end

local function prompt(msg: string, onYes: () -> ())
	local screen = api and api.getScreen()
	if not screen then return end
	screen.Prompt(msg, "Confirm", "Primary", onYes)
end

local function promptUpgrade(state: any, g: any, times: number)
	if times < 1 then return end
	local gold = priceOf(state, Rules.GOLD.Upgrade[tierOf(g)]) * times
	local gid = g.id
	prompt(`Combine {Rules.UPGRADE_INPUTS * times} {g.name} into {times} {shiftName(g, 1)} for {gold} gold?`, function()
		doCraft({ action = "Upgrade", gem = gid, times = times }, false)
	end)
end

local function promptBreakDown(state: any, g: any)
	local gold = priceOf(state, Rules.GOLD.BreakDown[tierOf(g)])
	local gid = g.id
	prompt(`Break 1 {g.name} into {Rules.BREAK_DOWN_OUTPUTS} {shiftName(g, -1)} for {gold} gold? You get back less than it took to make.`, function()
		doCraft({ action = "BreakDown", gem = gid, times = 1 }, false)
	end)
end

local function promptMix(state: any)
	if #picks ~= Rules.MIX_INPUTS then return end
	local list = table.clone(picks)
	if mode == "Mix" then
		local t = pickTier(state) or 0
		local gold = priceOf(state, Rules.GOLD.Mix[t])
		prompt(`Mix these 5 T{t} gems into 1 random T{t + 1} stat gem for {gold} gold? The result is random and can't be undone.`, function()
			doCraft({ action = "Mix", gems = list }, true)
		end)
	else
		local r = tostring(pickRarity(state))
		local gold = priceOf(state, Rules.GOLD.MixPassives)
		prompt(`Mix these 5 {r} passive gems into 1 random {r} passive gem for {gold} gold? The result is random.`, function()
			doCraft({ action = "MixPassives", gems = list }, true)
		end)
	end
end

--------------------------------------------------
-- LEFT: gem tiles
--------------------------------------------------

local function cellsFor(state: any): { any }
	local locked = state.lockedReason ~= nil
	local want = if mode == "MixPassives" then "passive" else "stat"
	local list = {}
	for _, g in state.gems or {} do
		if g.kind == want then
			local left = (tonumber(g.count) or 0) - (if isMixMode() then pickedCount(g.id) else 0)
			table.insert(list, api.gemEntry(g, left))
		end
	end
	local fitsOnly = api.fitsOnlyOn()
	local pt, pr = pickTier(state), pickRarity(state)
	local full = #picks >= Rules.MIX_INPUTS
	local cells = {}
	for _, e in api.applyGemBar(list) do
		local g, left = e.g, e.count
		local tier = tierOf(g)
		local reason: string? = nil
		local blocked = locked
		if mode == "Upgrade" then
			if tier >= Rules.MAX_TIER then reason = REASONS.TopTier
			elseif left < Rules.UPGRADE_INPUTS then reason = REASONS.NeedThree end
		elseif mode == "BreakDown" then
			if tier <= 1 then reason = REASONS.NoBreakT1 end
		elseif mode == "Mix" then
			if tier >= Rules.MAX_TIER then reason = REASONS.TopTier
			elseif pt and tier ~= pt then reason = REASONS.SameTier
			elseif left <= 0 then reason = api.noneLeft
			elseif full then blocked = true end
		else
			if pr and g.minRarity ~= pr then reason = REASONS.SameRarity
			elseif left <= 0 then reason = api.noneLeft
			elseif full then blocked = true end
		end
		local enabled = reason == nil and not blocked
		if enabled or not fitsOnly then
			local cell = api.gemCell(g, left)
			cell.enabled = enabled
			cell.reason = reason
			if enabled then
				local gid = g.id
				cell.onTap = function()
					if busy then return end
					if isMixMode() then
						if #picks < Rules.MIX_INPUTS then table.insert(picks, gid) end
					else
						selectedGem = gid
						repeatN = 2
					end
					api.render()
				end
			end
			table.insert(cells, cell)
		end
	end
	return cells
end

--------------------------------------------------
-- RIGHT: mode buttons, picks, actions
--------------------------------------------------

local function modeButtons(parent: Instance, order: number)
	local holder = Instance.new("Frame")
	holder.Name = "GemCraftModes"
	holder.Size = UDim2.new(1, 0, 0, MODE_H * 2 + MODE_GAP)
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.LayoutOrder = order
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -MODE_GAP // 2, 0, MODE_H)
	grid.CellPadding = UDim2.fromOffset(MODE_GAP, MODE_GAP)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = holder
	for i, id in MODE_ORDER do
		Theme.MakeTabButton(holder, TEXT.modes[id], if mode == id then "Active" else "Inactive", function()
			RuneforgeGemCraft.SetMode(id)
		end, { name = `GemCraftMode_{id}`, layoutOrder = i })
	end
	holder.Parent = parent
end

local function reasonNote(parent: Instance, reason: string?, order: number)
	if reason then api.makeNote(parent, reason, order, Theme.Colors.Warning) end
end

-- The action buttons for the current mode + the greyed reason (nil = all fine) + the
-- selected gem. Upgrade / Break Down buttons show (greyed) before a gem is picked, so the
-- pinned row keeps the same height. Also clamps the Craft xN count to what is affordable.
local function actionsFor(state: any): ({ any }, string?, any?)
	local canAct = state.lockedReason == nil and not busy
	if not isMixMode() then
		local g = gemOf(state, selectedGem)
		local count = if g then tonumber(g.count) or 0 else 0
		local tier = if g then tierOf(g) else 0
		local reason: string? = nil
		if mode == "Upgrade" then
			if g then
				reason = if tier >= Rules.MAX_TIER then REASONS.TopTier
					elseif count < Rules.UPGRADE_INPUTS then REASONS.NeedThree else nil
				if reason == nil and goldOf(state) < priceOf(state, Rules.GOLD.Upgrade[tier]) then reason = REASONS.Gold end
			end
			local ok = g ~= nil and reason == nil and canAct
			local maxAll = if ok and g then upgradeMax(state, g) else 0
			repeatN = math.clamp(repeatN, 2, math.max(2, maxAll))
			local n = repeatN
			return {
				{ text = TEXT.upgrade, enabled = ok, onTap = function() if g then promptUpgrade(state, g, 1) end end },
				{ text = string.format(TEXT.craftN, n), enabled = ok and maxAll >= n,
					onTap = function() if g then promptUpgrade(state, g, n) end end },
				{ text = TEXT.craftAll, enabled = ok and maxAll >= 1,
					onTap = function() if g then promptUpgrade(state, g, upgradeMax(state, g)) end end },
			}, reason, g
		end
		if g then
			reason = if tier <= 1 then REASONS.NoBreakT1 else nil
			if reason == nil and goldOf(state) < priceOf(state, Rules.GOLD.BreakDown[tier]) then reason = REASONS.Gold end
		end
		return {
			{ text = TEXT.breakDown, enabled = g ~= nil and reason == nil and canAct,
				onTap = function() if g then promptBreakDown(state, g) end end },
		}, reason, g
	end
	local full = #picks == Rules.MIX_INPUTS
	local reason: string? = nil
	local base: number? = nil
	if mode == "Mix" then
		if not full then reason = REASONS.SameTier else base = Rules.GOLD.Mix[pickTier(state) or 0] end
	else
		if not full then reason = REASONS.SameRarity else base = Rules.GOLD.MixPassives end
	end
	if reason == nil and goldOf(state) < priceOf(state, base) then reason = REASONS.Gold end
	return {
		{ text = TEXT.mix, enabled = reason == nil and canAct, onTap = function() promptMix(state) end },
	}, reason, nil
end

-- PINNED block (RuneforgeScreen gives a frame PINNED_H tall above the scrolling panel): the
-- 2x2 mode grid, then ONE row with the action button(s), each a >= 44 px touch target.
function RuneforgeGemCraft.BuildPinned(parent: Instance, state: any)
	if not api or not state then return end
	prune(state)
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, ACTION_GAP)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = parent
	modeButtons(parent, 1)
	local acts = actionsFor(state)
	local row = Instance.new("Frame")
	row.Name = "GemCraftActions"
	row.Size = UDim2.new(1, 0, 0, MODE_H)
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.LayoutOrder = 2
	local n = #acts
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(1 / n, -math.ceil(ACTION_GAP * (n - 1) / n), 0, MODE_H)
	grid.CellPadding = UDim2.fromOffset(ACTION_GAP, 0)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = row
	for i, a in acts do
		api.listButton(row, a.text, i, false, a.enabled, a.onTap)
	end
	-- The grid cell sets the size; stop the list-row auto height from growing past the row.
	for _, ch in row:GetChildren() do
		if ch:IsA("TextButton") then ch.AutomaticSize = Enum.AutomaticSize.None end
	end
	row.Parent = parent
end

-- SCROLLING part under the pinned block: the picked gem + greyed reason, or the Mix picks
-- (tap one to take it back out).
function RuneforgeGemCraft.BuildSide(parent: Instance, state: any)
	if not api or not state then return end
	prune(state)
	local _, reason, g = actionsFor(state)
	if not isMixMode() then
		if not g then return end
		api.makeNote(parent, `{g.name}  x{tonumber(g.count) or 0}`, 10, Theme.GetRarityColor(g.minRarity or "Common"), true)
		reasonNote(parent, reason, 11)
		return
	end
	reasonNote(parent, reason, 5)
	for i, id in picks do
		local pg = gemOf(state, id)
		local idx = i
		api.listButton(parent, tostring(if pg then pg.name else id), 10 + i, false, not busy, function()
			table.remove(picks, idx)
			api.render()
		end)
	end
end

--------------------------------------------------
-- LEFT PANEL + BOTTOM ROW
--------------------------------------------------

function RuneforgeGemCraft.BuildMain(main: Instance, list: UIListLayout, state: any)
	if not api or not state then return end
	prune(state)
	api.buildGemBar(main, 3, function()
		api.resetGridScroll(RuneforgeGemCraft.GRID_KEY) -- new search / filter / sort: back to the top
		api.render()
	end)
	local cells = cellsFor(state)
	if #cells == 0 then
		if #(state.gems or {}) == 0 then api.makeNote(main, "No rune gems.", 4) end
		return
	end
	local grid, hint = api.makeGridFrame(main, list)
	api.buildGrid(grid, cells, hint)
	grid.Parent = main
end

function RuneforgeGemCraft.BuildButtons(row: Instance, state: any)
	if not api then return end
	if mode == "Upgrade" then
		local g = if state then gemOf(state, selectedGem) else nil
		local maxAll = if g and state then upgradeMax(state, g) else 0
		api.iconButton(row, "Minus", "Btn_CraftLess", 1, g ~= nil and repeatN > 2, function()
			repeatN -= 1
			api.render()
		end)
		api.iconButton(row, "Plus", "Btn_CraftMore", 2, g ~= nil and repeatN < maxAll, function()
			repeatN += 1
			api.render()
		end)
	elseif isMixMode() then
		api.iconButton(row, "Minus", "Btn_RemovePick", 1, #picks > 0 and not busy, function()
			table.remove(picks)
			api.render()
		end)
	end
	api.iconButton(row, "X", "Btn_ClearPicks", 3, (selectedGem ~= nil or #picks > 0) and not busy, function()
		selectedGem = nil
		table.clear(picks)
		repeatN = 2
		api.render()
	end)
end

--------------------------------------------------
-- PUBLIC
--------------------------------------------------

function RuneforgeGemCraft.Init(a: any)
	api = a
end

-- Switch Upgrade / BreakDown / Mix / MixPassives (the mode buttons call this). Clears the picks.
function RuneforgeGemCraft.SetMode(id: string)
	if mode == id or busy or not table.find(MODE_ORDER, id) then return end
	mode = id
	selectedGem = nil
	table.clear(picks)
	repeatN = 2
	if api then
		api.resetGridScroll(RuneforgeGemCraft.GRID_KEY)
		api.render()
	end
end

function RuneforgeGemCraft.Reset()
	mode = "Upgrade"
	selectedGem = nil
	table.clear(picks)
	repeatN = 2
	busy = false
	gen += 1 -- a craft answer still on its way is no longer shown
end

-- Studio smoke tests only: the current tab state.
function RuneforgeGemCraft.DebugState(): any
	return { mode = mode, selectedGem = selectedGem, picks = table.clone(picks), repeatN = repeatN, busy = busy }
end

return table.freeze(RuneforgeGemCraft)
