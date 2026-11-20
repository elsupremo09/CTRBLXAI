--!strict
-- LoadoutInfo.lua
-- CTRBLXAI | Loadout screen INFO tab: stat panel (allocation basket, live preview, stat
-- explainer) and the Info tab content (stats / passives views, identity, dismiss).
-- Split out of LoadoutScreen.lua (2026-11-10, ARC-005 file-size split, step 2 of 10).
-- Behaviour unchanged. Host state (stat panel, info panel, root frame, Info sub-view, the
-- one open detail overlay, Refresh) is reached through `ctx` from LoadoutScreen -- no
-- require of LoadoutScreen, so no circular dependency (dependency injection).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local CTRBLXAI_UI = ReplicatedStorage:WaitForChild("CTRBLXAI", 10):WaitForChild("UI", 10)
local Theme       = require(CTRBLXAI_UI:WaitForChild("Theme", 10)); local NumberFormat = require(CTRBLXAI_UI:WaitForChild("NumberFormat", 10)) -- no decimals (loadout_ui_spec 129)
local MockData    = require(CTRBLXAI_UI:WaitForChild("MockLoadoutData", 10))
local BattleEvents = require(ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
	:WaitForChild("Remotes", 10):WaitForChild("BattleEvents", 10))
local GameConstants = require(ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
	:WaitForChild("Shared", 10):WaitForChild("GameConstants", 10))
local UIComponents = require(CTRBLXAI_UI:WaitForChild("UIComponents", 10))
local PortraitData = require(ReplicatedStorage:WaitForChild("Content", 10)
	:WaitForChild("PortraitData", 10))
local TipController: any = nil -- New-player tips (2026-11-19): guarded, a missing module never breaks this screen
do
	local okTip, tipMod = pcall(function() return (require :: any)(CTRBLXAI_UI:WaitForChild("TipController", 10)) end)
	if okTip then TipController = tipMod else warn("[LoadoutInfo] tips unavailable: " .. tostring(tipMod)) end
end

local LoadoutInfo: any = {}

local ctx: any = nil
local EQUIP_SLOTS: any = nil -- host table, set in Init (one definition, DAT-001)
local function clearChildren(...) return ctx.clearChildren(...) end
local function makeLabel(...) return ctx.makeLabel(...) end
local function pad(...) return ctx.pad(...) end
local function getPlayerGui() return ctx.getPlayerGui() end
local function closeDetail() return ctx.closeDetail() end

local buildStatPanel, buildInfoContent

-- STAT PANEL (right column, below unit header — always visible)
--------------------------------------------------

--------------------------------------------------
-- STAT ALLOCATION BASKET + INFO LIVE-PREVIEW + STAT EXPLAINER (2026-10-18)
-- Points are staged on the client (free +/-, minus only removes points added this
-- session). The server is touched only for a debounced read-only preview and once
-- on Confirm. Rows repaint in place (no teardown) so there is no per-click blink.
--------------------------------------------------
local pendingAlloc = {}        -- stat -> points staged this session (>= 0)
local pendingUnitId = nil      -- unit the current basket belongs to
local projEffective = nil      -- last server-previewed effective stats (nil = none)
local statsCache = nil         -- last GetUnitFullStats snapshot
local statRowRefs = {}         -- stat -> { valLabel, minusBtn, plusBtn }
local statHeaderLabel = nil
local statConfirmRow = nil
local statConfirmVisConn = nil -- syncs the below-panel Confirm row with ctx.getStatPanel().Visible
local infoDerivedRows = {}     -- derivedKey -> { label, fmt(derivedTable) -> string }
local infoResourceRows = {}    -- maxHp / maxMp -> label
local previewToken = nil
local STAT_ORDER = {"STR", "AGI", "INT", "VIT", "DEX", "LUK"}

local pendingTotalFn

-- Small stat icon left of a row name (user ruling 2026-11-12 9:51 / 10:07 PM). Icons come from
-- Theme (StatKeyIcons for INFO rows, Theme.Icons[stat] for STR..LUK). FitIconBox keeps per-icon
-- fits (MP 0.88). Properties first, Parent last (NET-004). nil icon -> nothing (blank gap).
local ROW_ICON_PX = 14
local ROW_ICON_GAP = ROW_ICON_PX + 4 -- left inset taken by the icon column
-- STR..LUK panel icons bigger (user 2026-11-16 1:50 AM: 14 px narrow art was unreadable). INFO rows keep 14.
local STAT_ICON_PX = 20
local STAT_ICON_GAP = STAT_ICON_PX + 4
-- STR..LUK +/- buttons (user ruling 2026-11-13 12:55 AM, replaces 44 px): 30x30, right edge,
-- small gap. Deliberately below the 44 px phone minimum (user design call).
local STAT_BTN_PX = 30
local STAT_BTN_GAP = 4      -- between "-" and "+"
local STAT_BTN_RIGHT = 4    -- "+" inset from the row's right edge
local STAT_ROW_H = STAT_BTN_PX -- row = button height so 6 rows + Confirm fit a phone (2026-11-13)
local STAT_BTNS_W = STAT_BTN_RIGHT + STAT_BTN_PX * 2 + STAT_BTN_GAP -- 68: right area kept clear
-- No points: short rows, no buttons (2026-11-12 11:02 PM). Values always ONE line (2026-11-13 1:00 AM).
local STAT_ROW_H_SHORT = 20
local STAT_PANEL_MIN_H, STAT_HEADER_H, STAT_LIST_GAP = 160, 16, 2 -- panel fits header + 6 rows, no scroll (2026-11-13 1:00 AM)
local function addRowIcon(row: Instance, icon: string?, px: number?)
	if not icon then return end
	local img = Instance.new("ImageLabel")
	img.Name = "StatIcon"
	img.BackgroundTransparency = 1
	img.ScaleType = Enum.ScaleType.Fit
	img.Image = icon
	local s = px or ROW_ICON_PX
	img.Size, img.Position = Theme.FitIconBox(icon, UDim2.fromOffset(s, s),
		UDim2.new(0, 2, 0.5, -s / 2))
	img.ZIndex = 2
	img.Parent = row
end
local refreshStatRowsInPlace
local applyStatPreview
local requestStatPreview
local openStatExplain

pendingTotalFn = function()
	local n = 0
	for _, s in ipairs(STAT_ORDER) do n += (pendingAlloc[s] or 0) end
	return n
end

refreshStatRowsInPlace = function()
	if not statsCache then return end
	local base = statsCache.baseStats or {}
	local committedEff = statsCache.effectiveStats or {}
	local pend = pendingTotalFn()
	local remaining = (statsCache.unallocatedPoints or 0) - pend
	if statHeaderLabel then
		if remaining > 0 or pend > 0 then
			statHeaderLabel.Text = "  STATS  [" .. remaining .. " pts]"
			statHeaderLabel.TextColor3 = remaining > 0 and Theme.Colors.TextGold or Theme.Colors.TextSecondary
		else
			statHeaderLabel.Text = "  STATS"
			statHeaderLabel.TextColor3 = Theme.Colors.TextSecondary
		end
	end
	for _, stat in ipairs(STAT_ORDER) do
		local ref = statRowRefs[stat]
		if ref and ref.valLabel then
			local p = pendingAlloc[stat] or 0
			local committedBase = base[stat] or 0
			local effVal = (projEffective and projEffective[stat]) or committedEff[stat] or committedBase
			-- Display (user ruling 2026-10-23): TOTAL first, then a parenthesised breakdown of
			-- committed base, any points STAGED this session (+N), and the net external modifier
			-- from gear/doctrine/race/status. Resting example: 53 (46 + 7); while staging 3 pts:
			-- 56 (46 +3 + 7); when nothing modifies the stat, just the number (no empty parens).
			local projBase = committedBase + p
			local mod = effVal - projBase
			local function signedMod(n) return (n >= 0) and (" + " .. n) or (" - " .. (-n)) end
			if p > 0 then
				local inner = committedBase .. " +" .. p .. (mod ~= 0 and signedMod(mod) or "")
				ref.valLabel.Text = string.format("%d (%s)", effVal, inner)
				ref.valLabel.TextColor3 = Theme.Colors.TextGold
			elseif mod ~= 0 then
				ref.valLabel.Text = string.format("%d (%d%s)", effVal, committedBase, signedMod(mod))
				ref.valLabel.TextColor3 = Theme.Colors.TextPrimary
			else
				ref.valLabel.Text = tostring(effVal)
				ref.valLabel.TextColor3 = Theme.Colors.TextPrimary
			end
			if ref.plusBtn then
				local canAdd = remaining > 0
				ref.plusBtn.Active = canAdd
				ref.plusBtn.AutoButtonColor = canAdd
				ref.plusBtn.ImageTransparency = canAdd and 0 or 0.6
			end
			if ref.minusBtn then
				local canSub = p > 0
				ref.minusBtn.Active = canSub
				ref.minusBtn.AutoButtonColor = canSub
				ref.minusBtn.ImageTransparency = canSub and 0 or 0.6
			end
		end
	end
	if statConfirmRow then statConfirmRow.Visible = pend > 0 and ctx.getStatPanel() ~= nil and ctx.getStatPanel().Visible end
end

applyStatPreview = function(derived, maxHp, maxMp, effective)
	for _, ref in pairs(infoDerivedRows) do
		if ref.label and ref.label.Parent and ref.fmt then
			ref.label.Text = ref.fmt(derived)
		end
	end
	if infoResourceRows.maxHp and infoResourceRows.maxHp.Parent then
		infoResourceRows.maxHp.Text = tostring(maxHp or (statsCache and statsCache.maxHp) or 0)
	end
	if infoResourceRows.maxMp and infoResourceRows.maxMp.Parent then
		infoResourceRows.maxMp.Text = tostring(maxMp or (statsCache and statsCache.maxMp) or 0)
	end
	projEffective = effective
	refreshStatRowsInPlace()
end

requestStatPreview = function()
	if pendingTotalFn() == 0 then
		if statsCache then
			applyStatPreview(statsCache.derivedStats or {}, statsCache.maxHp, statsCache.maxMp, statsCache.effectiveStats or {})
		end
		return
	end
	local myToken = {}
	previewToken = myToken
	task.delay(0.15, function()
		if previewToken ~= myToken then return end
		local unit = MockData.GetSelectedUnit()
		if not unit then return end
		local pend = {}
		for _, s in ipairs(STAT_ORDER) do pend[s] = pendingAlloc[s] or 0 end
		local ok, res = pcall(function()
			return BattleEvents.PreviewStatAllocation:InvokeServer(unit.id, pend)
		end)
		if previewToken ~= myToken then return end
		if ok and res and res.ok then
			projEffective = res.effectiveStats
			applyStatPreview(res.derivedStats or {}, res.maxHp, res.maxMp, res.effectiveStats or {})
		end
	end)
end

openStatExplain = function(key)
	closeDetail()
	if not statsCache then return end
	local META = GameConstants.STAT_META or {}
	local function isPrimary(k)
		for _, s in ipairs(STAT_ORDER) do if s == k then return true end end
		return false
	end
	local detailOverlay = Instance.new("ScreenGui"); ctx.setDetailOverlay(detailOverlay)
	detailOverlay.Name = "StatExplain"
	detailOverlay.DisplayOrder = 120
	detailOverlay.ResetOnSpawn = false
	detailOverlay.Parent = getPlayerGui()
	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.AutoButtonColor = false
	backdrop.Text = ""; backdrop.BorderSizePixel = 0
	backdrop.Parent = detailOverlay
	backdrop.Activated:Connect(closeDetail)
	local panel = Theme.MakePanel("StatExplain", UDim2.new(0, 300, 0, 220), UDim2.new(0.5, 0, 0.5, 0), Vector2.new(0.5, 0.5), detailOverlay)
	panel.ClipsDescendants = true
	pad(panel, 10, 12, 12, 10)
	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(1, 0, 1, -24)
	list.BackgroundTransparency = 1; list.BorderSizePixel = 0
	list.ScrollBarThickness = 3
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel
	local ll = Instance.new("UIListLayout", list)
	ll.Padding = UDim.new(0, 4); ll.SortOrder = Enum.SortOrder.LayoutOrder
	local lo = 0
	local function addLine(txt, color, bold, wrap)
		lo += 1
		local t = Instance.new("TextLabel")
		t.Size = UDim2.new(1, 0, 0, 16); t.AutomaticSize = Enum.AutomaticSize.Y
		t.BackgroundTransparency = 1
		t.Font = bold and Theme.Font.PrimaryBold or Theme.Font.Primary
		t.TextSize = bold and Theme.Text.Body() or Theme.Text.Small()
		t.TextColor3 = color or Theme.Colors.TextPrimary
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.TextWrapped = wrap ~= false
		t.Text = txt; t.LayoutOrder = lo; t.Parent = list
	end
	if isPrimary(key) then
		local base = (statsCache.baseStats or {})[key] or 0
		local p = pendingAlloc[key] or 0
		local projBase = base + p
		local eff = (projEffective and projEffective[key]) or (statsCache.effectiveStats or {})[key] or projBase
		addLine(key, Theme.Colors.TextGold, true)
		local pdesc = (GameConstants.PRIMARY_STAT_DESC or {})[key]
		if pdesc then addLine(pdesc, Theme.Colors.TextPrimary, false); addLine("", nil, false) end
		addLine("Base (race growth + allocated): " .. projBase .. (p > 0 and ("  (+" .. p .. " this session)") or ""), Theme.Colors.TextSecondary)
		addLine("Effective (after doctrine / gear / race): " .. eff, Theme.Colors.TextSecondary)
		addLine("", nil, false)
		addLine("Powers these stats:", Theme.Colors.TextPrimary, true)
		for dkey, meta in pairs(META) do
			if meta.parent == key then
				addLine("- " .. (meta.label or dkey) .. ":  " .. (meta.formula or ""), Theme.Colors.TextSecondary)
			end
		end
	else
		local meta = META[key]
		if not meta then
			addLine(key, Theme.Colors.TextGold, true)
			addLine("No breakdown available for this stat.", Theme.Colors.TextSecondary)
		else
			local parent = meta.parent
			local parentVal = parent and ((projEffective and projEffective[parent]) or (statsCache.effectiveStats or {})[parent]) or nil
			local curText = (infoDerivedRows[key] and infoDerivedRows[key].label and infoDerivedRows[key].label.Text) or (infoResourceRows[key] and infoResourceRows[key].Text) or "?"
			addLine(meta.label or key, Theme.Colors.TextGold, true)
			if meta.desc then addLine(meta.desc, Theme.Colors.TextPrimary, false); addLine("", nil, false) end
			addLine("Formula:  " .. (meta.formula or "-"), Theme.Colors.TextSecondary)
			if key == "baseRt" then
				local dd = statsCache.derivedStats or {}
				addLine("Own base (player unit):  400", Theme.Colors.TextSecondary)
				addLine("+ Effective Armor WT:  " .. (dd.baseRtArmorWt or 0), Theme.Colors.TextSecondary)
			end
			if parent then
				addLine("Depends on " .. parent .. (parentVal and ("  (currently " .. parentVal .. ")") or ""), Theme.Colors.TextSecondary)
			end
			addLine("Current value:  " .. curText, Theme.Colors.TextPrimary, true)
		end
	end
	Theme.MakeBarButton(panel, "Close", "Secondary", closeDetail, {
		name = "Btn_StatExplainClose", autoWidth = false, minHeight = 20,
		size = UDim2.new(0, 80, 0, 20), position = UDim2.new(1, -80, 1, -20),
	})
end

buildStatPanel = function()
	if not ctx.getStatPanel() then return end
	clearChildren(ctx.getStatPanel())
	-- The Confirm row sits OUTSIDE ctx.getStatPanel() (below it), so clearChildren does not remove it.
	if statConfirmVisConn then statConfirmVisConn:Disconnect(); statConfirmVisConn = nil end
	if statConfirmRow then statConfirmRow:Destroy(); statConfirmRow = nil end
	if not ctx.getStatPanel():FindFirstChildOfClass("UIPadding") then pad(ctx.getStatPanel(), 6, 8, 8, 6) end

	local unit = MockData.GetSelectedUnit()
	if not unit then return end

	-- One server fetch; thereafter rows repaint in place (no per-click refetch/teardown).
	local ok, statsData = pcall(function()
		return BattleEvents.GetUnitFullStats:InvokeServer(unit.id)
	end)
	if not ok or not statsData or not statsData.ok then
		statsData = { baseStats = {}, effectiveStats = {}, derivedStats = {}, unallocatedPoints = 0 }
	end
	statsCache = statsData

	-- Staging is per-unit: reset the basket when the inspected unit changes.
	if statsData.unitId ~= pendingUnitId then
		pendingAlloc = {}
		projEffective = nil
		pendingUnitId = statsData.unitId
	end
	statRowRefs = {}

	-- Scroll container so the Confirm/Discard row never overflows the fixed panel.
	local scroller = Instance.new("ScrollingFrame")
	scroller.Name = "StatScroll"
	scroller.Size = UDim2.new(1, 0, 1, 0)
	scroller.BackgroundTransparency = 1; scroller.BorderSizePixel = 0
	scroller.ScrollBarThickness = 3
	scroller.ScrollBarImageColor3 = Theme.Colors.Surface
	scroller.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.Parent = ctx.getStatPanel()

	local layout = Instance.new("UIListLayout", scroller)
	layout.Padding = UDim.new(0, STAT_LIST_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder

	-- Header (remaining allocation points)
	statHeaderLabel = Instance.new("TextLabel")
	statHeaderLabel.Size = UDim2.new(1, 0, 0, STAT_HEADER_H); statHeaderLabel.BackgroundTransparency = 0.3
	statHeaderLabel.BackgroundColor3 = Theme.Colors.PanelRaised; statHeaderLabel.BorderSizePixel = 0
	statHeaderLabel.Font = Theme.Font.PrimaryBold; statHeaderLabel.TextSize = Theme.Text.Small()
	statHeaderLabel.TextXAlignment = Enum.TextXAlignment.Left
	statHeaderLabel.LayoutOrder = 0; statHeaderLabel.Parent = scroller

	local hasPoints = (statsData.unallocatedPoints or 0) > 0
	if hasPoints and TipController then TipController.Trigger("TIP-STAT-01") end -- new-player tip (unspent points)
	local rightClear = if hasPoints then STAT_BTNS_W + 4 else 4
	do -- fit header + 6 rows (no scroll); set BEFORE the Confirm row, placed from Position + Size
		local panel, up = ctx.getStatPanel(), ctx.getStatPanel():FindFirstChildOfClass("UIPadding")
		local h = STAT_HEADER_H + #STAT_ORDER * ((if hasPoints then STAT_ROW_H else STAT_ROW_H_SHORT) + STAT_LIST_GAP)
			+ (if up then up.PaddingTop.Offset + up.PaddingBottom.Offset else 0)
		local colH = if panel.Parent then (panel.Parent :: any).AbsoluteSize.Y else 0; if colH > 0 then h = math.min(h, colH - panel.Position.Y.Offset - 32) end -- Confirm row (2+30) stays on screen
		panel.Size = UDim2.new(panel.Size.X.Scale, panel.Size.X.Offset, 0, math.max(STAT_PANEL_MIN_H, h))
	end
	for si, stat in ipairs(STAT_ORDER) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, if hasPoints then STAT_ROW_H else STAT_ROW_H_SHORT); row.BackgroundTransparency = 1
		row.BorderSizePixel = 0; row.LayoutOrder = si + 1; row.Parent = scroller

		addRowIcon(row, Theme.Icons[stat], STAT_ICON_PX)
		local statLbl = Instance.new("TextLabel")
		statLbl.Size = UDim2.new(0, 32, 1, 0); statLbl.Position = UDim2.fromOffset(STAT_ICON_GAP, 0)
		statLbl.BackgroundTransparency = 1
		statLbl.Font = Theme.Font.PrimaryBold; statLbl.TextSize = Theme.Text.Small()
		statLbl.TextColor3 = Theme.Colors.TextPrimary
		statLbl.TextXAlignment = Enum.TextXAlignment.Left
		statLbl.Text = stat; statLbl.ZIndex = 2; statLbl.Parent = row

		local valLbl = Instance.new("TextLabel")
		valLbl.Size = UDim2.new(1, -(STAT_ICON_GAP + 32 + rightClear), 1, 0) -- ends 4 px left of "-" (or the edge)
		valLbl.Position = UDim2.fromOffset(STAT_ICON_GAP + 32, 0)
		valLbl.BackgroundTransparency = 1
		valLbl.Font = Theme.Font.Mono; valLbl.TextSize = Theme.Text.Small()
		valLbl.TextColor3 = Theme.Colors.TextPrimary
		valLbl.TextXAlignment = Enum.TextXAlignment.Left
		valLbl.TextScaled = true; valLbl.TextWrapped = false; valLbl.TextTruncate = Enum.TextTruncate.AtEnd; do local fit = Instance.new("UITextSizeConstraint"); fit.MaxTextSize = Theme.Text.Small(); fit.MinTextSize = 10; fit.Parent = valLbl end -- long values shrink, min 10 px (2026-11-13)
		valLbl.ZIndex = 2; valLbl.Parent = row

		-- Tap target for the stat explainer; sits left of the +/- buttons.
		local tap = Instance.new("TextButton")
		tap.Size = UDim2.new(1, -rightClear, 1, 0); tap.Position = UDim2.fromOffset(0, 0)
		tap.BackgroundTransparency = 1; tap.Text = ""; tap.ZIndex = 1
		tap.Parent = row
		tap.Activated:Connect(function() openStatExplain(stat) end)

		local minusBtn, plusBtn
		if hasPoints then
			minusBtn = Theme.MakeButton(row, "-", "Primary", nil, { size = UDim2.fromOffset(STAT_BTN_PX, STAT_BTN_PX),
				position = UDim2.new(1, -STAT_BTNS_W, 0.5, -STAT_BTN_PX / 2) })
			minusBtn.ZIndex = 3
			minusBtn.Activated:Connect(function()
				if (pendingAlloc[stat] or 0) <= 0 then return end
				pendingAlloc[stat] = pendingAlloc[stat] - 1
				refreshStatRowsInPlace()
				requestStatPreview()
			end)
			plusBtn = Theme.MakeButton(row, "+", "Primary", nil, { size = UDim2.fromOffset(STAT_BTN_PX, STAT_BTN_PX),
				position = UDim2.new(1, -(STAT_BTN_RIGHT + STAT_BTN_PX), 0.5, -STAT_BTN_PX / 2) })
			plusBtn.ZIndex = 3
			plusBtn.Activated:Connect(function()
				local remaining = (statsCache.unallocatedPoints or 0) - pendingTotalFn()
				if remaining <= 0 then return end
				pendingAlloc[stat] = (pendingAlloc[stat] or 0) + 1
				refreshStatRowsInPlace()
				requestStatPreview()
			end)
		end

		statRowRefs[stat] = { valLabel = valLbl, minusBtn = minusBtn, plusBtn = plusBtn }
	end

	-- Confirm / Discard as check / X ICON buttons, still on the RIGHT (user ruling 2026-10-23,
	-- muscle memory). Shown only while points are staged.
	-- MOVED 2026-10-28 (user): they used to sit INSIDE the panel's lower-right corner, covering
	-- the DEX/LUK +/- buttons. They now sit DIRECTLY BELOW the stat panel. ctx.getStatPanel() clips
	-- its children, so the row is parented to the panel's parent (right column) and placed
	-- from ctx.getStatPanel()'s own Position/Size. Its X aligns X under the "-" column and the check
	-- under the "+" column. On the INFO tab the equipped panel is hidden, so nothing is covered.
	-- Visibility follows ctx.getStatPanel().Visible so staged points never leave it floating on other tabs.
	statConfirmRow = Instance.new("Frame")
	statConfirmRow.Name = "StatConfirmBelow"
	-- X directly under "-", check directly under "+": 30 px, same as the stat buttons (2026-11-13).
	-- 8 = the stat panel's inner side padding (scroller inset).
	statConfirmRow.Size = UDim2.fromOffset(STAT_BTN_PX * 2 + STAT_BTN_GAP, STAT_BTN_PX)
	statConfirmRow.AnchorPoint = Vector2.new(1, 0)
	statConfirmRow.Position = UDim2.new(1, -(8 + STAT_BTN_RIGHT), 0,
		ctx.getStatPanel().Position.Y.Offset + ctx.getStatPanel().Size.Y.Offset + 2)
	statConfirmRow.BackgroundTransparency = 1; statConfirmRow.BorderSizePixel = 0
	statConfirmRow.ZIndex = 10; statConfirmRow.Visible = false
	statConfirmRow.Parent = ctx.getStatPanel().Parent
	statConfirmVisConn = ctx.getStatPanel():GetPropertyChangedSignal("Visible"):Connect(function()
		if statConfirmRow then
			statConfirmRow.Visible = ctx.getStatPanel().Visible and pendingTotalFn() > 0
		end
	end)

	local function doStatConfirm()
		local u = MockData.GetSelectedUnit(); if not u then return end
		if pendingTotalFn() <= 0 then return end
		local pend = {}
		for _, s in ipairs(STAT_ORDER) do pend[s] = pendingAlloc[s] or 0 end
		local okC, res = pcall(function()
			return BattleEvents.CommitStatAllocation:InvokeServer(u.id, pend)
		end)
		if okC and res and res.ok then
			pendingAlloc = {}
			projEffective = nil
			previewToken = nil
			buildStatPanel()
			buildInfoContent()
		end
	end
	local function doStatDiscard()
		pendingAlloc = {}
		projEffective = nil
		previewToken = nil
		refreshStatRowsInPlace()
		if statsCache then
			applyStatPreview(statsCache.derivedStats or {}, statsCache.maxHp, statsCache.maxMp, statsCache.effectiveStats or {})
		end
	end
	-- X (discard) on the left, check (confirm) on the right -- matches the screen-wide
	-- back/confirm ordering. Theme icon kinds: "Confirm" = checkmark, "X" = cross.
	local discardIcon = Theme.MakeIconButton(statConfirmRow, "X", doStatDiscard, {
		name = "Btn_StatDiscard", size = UDim2.fromOffset(STAT_BTN_PX, STAT_BTN_PX), position = UDim2.new(0, 0, 0, 0),
	})
	discardIcon.ZIndex = 11
	local confirmIcon = Theme.MakeIconButton(statConfirmRow, "Confirm", doStatConfirm, {
		name = "Btn_StatConfirm", size = UDim2.fromOffset(STAT_BTN_PX, STAT_BTN_PX), position = UDim2.new(1, -STAT_BTN_PX, 0, 0),
	})
	confirmIcon.ZIndex = 11

	refreshStatRowsInPlace()
end

-- INFO TAB CONTENT (placeholder)
--------------------------------------------------

buildInfoContent = function()
	if not ctx.getInfoPanel() then return end
	clearChildren(ctx.getInfoPanel())
	infoDerivedRows = {}
	infoResourceRows = {}

	local unit = MockData.GetSelectedUnit()
	if not unit then return end

	-- Fetch full stats from server
	local ok2, statsData = pcall(function()
		return BattleEvents.GetUnitFullStats:InvokeServer(unit.id)
	end)
	if not ok2 or not statsData or not statsData.ok then
		makeLabel(ctx.getInfoPanel(), { Text = "Failed to load unit stats.",
			Size = UDim2.new(1, 0, 0, 30), TextColor3 = Theme.Colors.Danger,
			TextSize = Theme.Text.Body() })
		return
	end

	-- =============================================
	-- LEFT COLUMN: Identity + Passives (scrollable)
	-- =============================================
	-- Inset both columns by the frame's drawn border so text never spills over it (2026-10-08).
	local pfB = math.ceil(Theme.PanelFrame.SliceCenter.Min.X * Theme.PanelFrame.SliceScale)

	-- STATS | PASSIVES switch (user decision 2026-10-29): splits the crowded Info panel into two
	-- views. Same 9-slice sub-tab buttons as the GEAR / CONSUMABLES switch. Info always opens
	-- on Stats (reset on tab tap + Show); toggling just rebuilds this panel.
	local VIEW_H = 24
	local viewTop = pfB + 4
	local colTop = viewTop + VIEW_H + 4
	local viewRow = Instance.new("Frame")
	viewRow.Name = "InfoViewSwitch"
	viewRow.Size = UDim2.new(1, -(pfB * 2 + 16), 0, VIEW_H)
	viewRow.Position = UDim2.new(0, pfB + 8, 0, viewTop)
	viewRow.BackgroundTransparency = 1; viewRow.BorderSizePixel = 0
	local viewLayout = Instance.new("UIListLayout")
	viewLayout.FillDirection = Enum.FillDirection.Horizontal
	viewLayout.Padding = UDim.new(0, 6)
	viewLayout.SortOrder = Enum.SortOrder.LayoutOrder
	viewLayout.Parent = viewRow
	for i, v in ipairs({ { id = "stats", label = "STATS" }, { id = "passives", label = "PASSIVES" } }) do
		Theme.MakeTabButton(viewRow, v.label, if v.id == ctx.getInfoView() then "Active" else "Inactive", function()
			if ctx.getInfoView() == v.id then return end
			ctx.setInfoView(v.id)
			buildInfoContent()
		end, { name = "InfoView_" .. v.label, size = UDim2.new(0, 110, 1, 0), layoutOrder = i })
	end
	viewRow.Parent = ctx.getInfoPanel() -- parent last (NET-004)

	local leftCol = Instance.new("ScrollingFrame")
	leftCol.Name = "InfoLeft"
	leftCol.Size = UDim2.new(0.50, -2 - pfB, 1, -(colTop + pfB))
	leftCol.Position = UDim2.new(0, pfB, 0, colTop)
	leftCol.BackgroundTransparency = 1; leftCol.BorderSizePixel = 0
	leftCol.ClipsDescendants = true
	leftCol.ScrollBarThickness = 3
	leftCol.ScrollBarImageColor3 = Theme.Colors.Surface
	leftCol.CanvasSize = UDim2.new(0, 0, 0, 0)
	leftCol.AutomaticCanvasSize = Enum.AutomaticSize.Y
	leftCol.Parent = ctx.getInfoPanel()

	local leftLayout = Instance.new("UIListLayout", leftCol)
	leftLayout.SortOrder = Enum.SortOrder.LayoutOrder
	leftLayout.Padding = UDim.new(0, 4)
	local leftPad = Instance.new("UIPadding", leftCol)
	leftPad.PaddingTop = UDim.new(0, 8); leftPad.PaddingLeft = UDim.new(0, 8)
	leftPad.PaddingRight = UDim.new(0, 4); leftPad.PaddingBottom = UDim.new(0, 12)

	local lOrder = 0
	local function nextL() lOrder = lOrder + 1; return lOrder end

	-- =============================================
	-- RIGHT COLUMN (Stats view: derived stats | Passives view: gear passives)
	-- =============================================
	local rightCol = Instance.new("ScrollingFrame")
	rightCol.Name = "InfoRight"
	rightCol.Size = UDim2.new(0.50, -2 - pfB, 1, -(colTop + pfB))
	rightCol.Position = UDim2.new(0.50, 2, 0, colTop)
	rightCol.BackgroundTransparency = 1; rightCol.BorderSizePixel = 0
	rightCol.ClipsDescendants = true
	rightCol.ScrollBarThickness = 3
	rightCol.ScrollBarImageColor3 = Theme.Colors.Surface
	rightCol.CanvasSize = UDim2.new(0, 0, 0, 0)
	rightCol.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rightCol.Parent = ctx.getInfoPanel()

	local rightLayout = Instance.new("UIListLayout", rightCol)
	rightLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rightLayout.Padding = UDim.new(0, 3)
	local rightPad = Instance.new("UIPadding", rightCol)
	rightPad.PaddingTop = UDim.new(0, 8); rightPad.PaddingLeft = UDim.new(0, 4)
	rightPad.PaddingRight = UDim.new(0, 8); rightPad.PaddingBottom = UDim.new(0, 12)

	local rOrder = 0
	local function nextR() rOrder = rOrder + 1; return rOrder end

	local function sectionHeader(parent, text, orderFn)
		local hdr = Instance.new("TextLabel")
		hdr.Size = UDim2.new(1, 0, 0, 20)
		hdr.BackgroundColor3 = Theme.Colors.PanelRaised
		hdr.BackgroundTransparency = 0.3
		hdr.Font = Theme.Font.PrimaryBold; hdr.TextSize = Theme.Text.Body()
		hdr.TextColor3 = Theme.Colors.TextSecondary
		hdr.TextXAlignment = Enum.TextXAlignment.Left
		hdr.Text = "  " .. text; hdr.BorderSizePixel = 0
		hdr.LayoutOrder = orderFn(); hdr.Parent = parent
		Instance.new("UIPadding", hdr).PaddingLeft = UDim.new(0, 4)
	end

	local function infoRow(parent, label, value, color, orderFn, statKey, fmtFn)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 16)
		row.BackgroundTransparency = 1; row.BorderSizePixel = 0
		row.LayoutOrder = orderFn(); row.Parent = parent
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Font = Theme.Font.Primary; lbl.TextSize = Theme.Text.Small()
		lbl.TextColor3 = Theme.Colors.TextSecondary
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		if statKey then
			-- Stat rows: icon column on the left (blank gap when the stat has no icon yet), so
			-- every name lines up. Name rows (perk / flaw / passives) keep the old layout.
			addRowIcon(row, Theme.StatKeyIcons[statKey])
			lbl.Size = UDim2.new(0.55, -ROW_ICON_GAP, 1, 0)
			lbl.Position = UDim2.fromOffset(ROW_ICON_GAP, 0)
			lbl.Text = label
		else
			lbl.Size = UDim2.new(0.55, 0, 1, 0)
			lbl.Text = "  " .. label
		end
		lbl.Parent = row
		local val = Instance.new("TextLabel")
		val.Size = UDim2.new(0.45, 0, 1, 0)
		val.Position = UDim2.new(0.55, 0, 0, 0)
		val.BackgroundTransparency = 1
		val.Font = Theme.Font.Mono; val.TextSize = Theme.Text.Small()
		val.TextColor3 = color or Theme.Colors.TextPrimary
		val.TextXAlignment = Enum.TextXAlignment.Left
		val.Text = tostring(value); val.Parent = row
		if statKey then
			infoDerivedRows[statKey] = { label = val, fmt = fmtFn }
			local tap = Instance.new("TextButton")
			tap.Size = UDim2.new(1, 0, 1, 0); tap.BackgroundTransparency = 1
			tap.Text = ""; tap.ZIndex = 2; tap.Parent = row
			tap.Activated:Connect(function() openStatExplain(statKey) end)
		end
		return val
	end

	local function descLabel(parent, text, orderFn)
		local d = Instance.new("TextLabel")
		d.Size = UDim2.new(1, 0, 0, 28); d.BackgroundTransparency = 1
		d.Font = Theme.Font.Primary; d.TextSize = Theme.Text.Small()
		d.TextColor3 = Theme.Colors.TextSecondary
		d.TextXAlignment = Enum.TextXAlignment.Left; d.TextWrapped = true
		d.Text = "  " .. text; d.BorderSizePixel = 0
		-- Grows past 28 px for long passive text instead of clipping (2026-11-01);
		-- with AutomaticSize the 28 px Size is the minimum, so short text is unchanged.
		d.AutomaticSize = Enum.AutomaticSize.Y
		d.LayoutOrder = orderFn(); d.Parent = parent
	end

	if ctx.getInfoView() == "stats" then -- identity block: Stats view only (2026-10-29)
	-- Unit identity row
	local identityRow = Instance.new("Frame")
	identityRow.Size = UDim2.new(1, 0, 0, 130)
	identityRow.BackgroundTransparency = 1; identityRow.BorderSizePixel = 0
	identityRow.LayoutOrder = nextL(); identityRow.Parent = leftCol

	local portrait = Instance.new("Frame")
	portrait.Size = UDim2.fromOffset(120, 120)
	portrait.Position = UDim2.fromOffset(0, 4)
	portrait.BackgroundColor3 = Theme.Colors.Player
	portrait.BackgroundTransparency = 0.2; portrait.BorderSizePixel = 0
	portrait.Parent = identityRow
	Instance.new("UICorner", portrait).CornerRadius = Theme.CornerRadius.md
	-- 2026-11-20 user: gold outline removed; the shared unit frame replaces it.
	local pLabel = Instance.new("TextLabel")
	pLabel.Size = UDim2.fromScale(1, 1); pLabel.BackgroundTransparency = 1
	pLabel.Font = Theme.Font.PrimaryBold; pLabel.TextSize = 40
	pLabel.TextColor3 = Theme.Colors.TextPrimary
	pLabel.Text = string.sub(statsData.name or "?", 1, 2)
	pLabel.Parent = portrait
	-- Current chosen 2D portrait overlays the initials box (player option B).
	-- nil → initials remain. The authoritative value comes from the server stats.
	if UIComponents.ApplyPortrait(portrait, statsData.portraitAssetId, pLabel) then
		pLabel.Visible = false
	end
	UIComponents.ApplyUnitFrame(portrait, { darkBg = true }) -- 2026-11-20 unit frame
	local lvBadge = Instance.new("Frame")
	lvBadge.Size = UDim2.fromOffset(Theme.BadgeFitW("Lv" .. tostring(statsData.level or 1), Theme.Font.PrimaryBold, 28), 16)  -- 2026-11-07: fits Lv100 at 10px
	lvBadge.Position = UDim2.fromOffset(0, 0)
	lvBadge.BackgroundColor3 = Theme.Colors.BadgeBg; lvBadge.BorderSizePixel = 0
	lvBadge.ZIndex = 3; lvBadge.Parent = portrait
	Instance.new("UICorner", lvBadge).CornerRadius = UDim.new(0, 3)
	local lvLbl = Instance.new("TextLabel")
	lvLbl.Size = UDim2.fromScale(1, 1); lvLbl.BackgroundTransparency = 1
	lvLbl.Font = Theme.Font.PrimaryBold; lvLbl.TextSize = Theme.Text.Badge()
	lvLbl.TextColor3 = Theme.Colors.TextPrimary; lvLbl.ZIndex = 3
	lvLbl.Text = "Lv" .. (statsData.level or 1); lvLbl.Parent = lvBadge

	local textX = 130
	local function identityLabel(text, yPos, font, size, color)
		local l = Instance.new("TextLabel")
		l.Size = UDim2.new(1, -textX, 0, 18)
		l.Position = UDim2.fromOffset(textX, yPos)
		l.BackgroundTransparency = 1
		l.Font = font or Theme.Font.Primary; l.TextSize = size or Theme.Text.Body()
		l.TextColor3 = color or Theme.Colors.TextPrimary
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Text = text; l.Parent = identityRow
	end

	-- Name always gets TWO rows (user 2026-10-29) so long names wrap instead of clipping.
	local NAME_H = 2 * (Theme.Text.Heading() + 2)
	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(1, -textX, 0, NAME_H)
	nameLbl.Position = UDim2.fromOffset(textX, 4)
	nameLbl.BackgroundTransparency = 1; nameLbl.BorderSizePixel = 0
	nameLbl.Font = Theme.Font.PrimaryBold; nameLbl.TextSize = Theme.Text.Heading()
	nameLbl.TextColor3 = Theme.Colors.Player
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.TextYAlignment = Enum.TextYAlignment.Top
	nameLbl.TextWrapped = true; nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
	nameLbl.Text = statsData.name or "Unit"
	nameLbl.Parent = identityRow -- parent last (NET-004)
	local idBelow = 4 + NAME_H + 2
	identityLabel(statsData.raceName or "Unknown Race", idBelow, nil, Theme.Text.Body(), Theme.Colors.TextSecondary)
	identityLabel(statsData.doctrineName or "No Doctrine", idBelow + 18, nil, Theme.Text.Body(), Theme.Colors.Info)
	-- HP and MP on separate lines (user 2026-10-29): the shared line was cut off.
	identityLabel(string.format("HP %d / %d", statsData.currentHp or 0, statsData.maxHp or 0),
		idBelow + 40, Theme.Font.Mono, Theme.Text.Body(), Theme.Colors.TextPrimary)
	identityLabel(string.format("MP %d / %d", statsData.currentMp or 0, statsData.maxMp or 0),
		idBelow + 58, Theme.Font.Mono, Theme.Text.Body(), Theme.Colors.TextPrimary)
	do -- EXP line + thin bar (user 2026-11-13 1:25 PM); same data as the old Units-screen XP line
		local ep = statsData.expProgress
		if type(ep) == "table" then
			identityLabel(if ep.atCap then "EXP MAX" else string.format("EXP %d / %d", ep.xp or 0, ep.xpToNext or 0),
				idBelow + 76, Theme.Font.Mono, Theme.Text.Body(), Theme.Colors.TextPrimary)
			local bar = Instance.new("Frame"); bar.Name = "ExpBar"
			bar.Size = UDim2.new(1, -(textX + 4), 0, 3); bar.Position = UDim2.fromOffset(textX, idBelow + 95)
			bar.BackgroundColor3 = Theme.Colors.EmptySlot; bar.BorderSizePixel = 0
			local fill = Instance.new("Frame"); fill.BorderSizePixel = 0; fill.BackgroundColor3 = Theme.Colors.Info
			fill.Size = UDim2.fromScale(if ep.atCap then 1 elseif (ep.xpToNext or 0) > 0 then math.clamp((ep.xp or 0) / ep.xpToNext, 0, 1) else 0, 1)
			fill.Parent = bar; bar.Parent = identityRow
			identityRow.Size = UDim2.new(1, 0, 0, math.max(130, idBelow + 95 + 3 + 4)) -- room for the EXP bar
		end
	end

	-- ---- 2D PORTRAIT PICKER (opens as a popup when the big portrait is tapped) ----
	-- User ruling 2026-10-23: the face grid no longer sits in the Info column; the large
	-- portrait is clickable and opens the picker as a pop-up overlay. The body-color swatch
	-- palette was removed entirely (it set a body tint that was never applied in-world).
	local function openPortraitPicker(pool)
		local overlay = Instance.new("ScreenGui")
		overlay.Name = "PortraitPicker"; overlay.DisplayOrder = 120
		overlay.ResetOnSpawn = false; overlay.Parent = getPlayerGui()
		local backdrop = Instance.new("TextButton")
		backdrop.Size = UDim2.fromScale(1, 1); backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
		backdrop.BackgroundTransparency = 0.5; backdrop.AutoButtonColor = false
		backdrop.Text = ""; backdrop.BorderSizePixel = 0; backdrop.Parent = overlay
		local function close() overlay:Destroy() end
		backdrop.Activated:Connect(close)
		local panel = Theme.MakePanel("PortraitPickerPanel", UDim2.new(0, 280, 0, 300), UDim2.new(0.5, 0, 0.5, 0), Vector2.new(0.5, 0.5), overlay)
		panel.ClipsDescendants = true
		pad(panel, 10, 12, 12, 10)
		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, 0, 0, 20); title.BackgroundTransparency = 1
		title.Font = Theme.Font.PrimaryBold; title.TextSize = Theme.Text.Body()
		title.TextColor3 = Theme.Colors.TextGold; title.TextXAlignment = Enum.TextXAlignment.Left
		title.Text = "Choose Portrait"; title.Parent = panel
		local list = Instance.new("ScrollingFrame")
		list.Size = UDim2.new(1, 0, 1, -48); list.Position = UDim2.fromOffset(0, 24)
		list.BackgroundTransparency = 1; list.BorderSizePixel = 0; list.ScrollBarThickness = 3
		list.ScrollBarImageColor3 = Theme.Colors.Surface
		list.CanvasSize = UDim2.new(0, 0, 0, 0); list.AutomaticCanvasSize = Enum.AutomaticSize.Y
		list.Parent = panel
		local g = Instance.new("UIGridLayout", list)
		g.CellSize = UDim2.fromOffset(56, 56); g.CellPadding = UDim2.fromOffset(6, 6)
		g.SortOrder = Enum.SortOrder.LayoutOrder
		local current = statsData.portraitAssetId
		for _, assetId in ipairs(pool) do
			local cell = Instance.new("ImageButton")
			cell.BackgroundColor3 = Theme.GetSideColor and Theme.GetSideColor("Player") or Theme.Colors.Player
			cell.BackgroundTransparency = 0.2; cell.BorderSizePixel = 0; cell.AutoButtonColor = true
			cell.Image = "rbxassetid://" .. tostring(assetId); cell.ScaleType = Enum.ScaleType.Crop
			cell.Parent = list
			Instance.new("UICorner", cell).CornerRadius = Theme.CornerRadius.sm
			if current == assetId then
				local st = Instance.new("UIStroke", cell); st.Color = Theme.Colors.TextGold; st.Thickness = 2
			end
			cell.Activated:Connect(function()
				-- Tapping the already-chosen portrait clears it (server treats nil as clear).
				local target = if current == assetId then nil else assetId
				local okP, res = pcall(function()
					return BattleEvents.RequestSetPortrait:InvokeServer(unit.id, target)
				end)
				-- Reload the cached roster first (same path as Dismiss) so the top bar and
				-- unit list show the new face / initials straight away. (2026-11-09)
				if okP and res and res.ok then close(); MockData.LoadFromServer(); ctx.refresh() end
			end)
		end
		Theme.MakeBarButton(panel, "Close", "Secondary", close, {
			name = "Btn_PortraitPickerClose", autoWidth = false, minHeight = 20,
			size = UDim2.new(0, 80, 0, 20), position = UDim2.new(1, -80, 1, -20),
		})
	end
	do
		local pool = statsData.raceId and PortraitData.GetPool(statsData.raceId) or nil
		if pool and #pool > 0 then
			local hit = Instance.new("TextButton")
			hit.Size = UDim2.fromScale(1, 1); hit.BackgroundTransparency = 1; hit.Text = ""
			hit.AutoButtonColor = false; hit.ZIndex = 5; hit.Parent = portrait
			hit.Activated:Connect(function() openPortraitPicker(pool) end)
		end
	end

	end -- identity block

	if ctx.getInfoView() == "passives" then -- own passives (left) + gear passives (right), Passives view only
	-- Personal perk (every unit rolls one — TraitRoller). Shown first per user ruling
	-- 2026-10-20: the Info screen lists 4 passives in order Perk, Flaw, Race, Doctrine.
	if statsData.perkName then
		sectionHeader(leftCol, "PERSONAL PERK", nextL)
		infoRow(leftCol, statsData.perkName, "", Theme.Colors.Success, nextL)
		if statsData.perkEffect then descLabel(leftCol, statsData.perkEffect, nextL) end
	end

	-- Personal flaw
	if statsData.flawName then
		sectionHeader(leftCol, "PERSONAL FLAW", nextL)
		infoRow(leftCol, statsData.flawName, "", Theme.Colors.Danger, nextL)
		if statsData.flawEffect then descLabel(leftCol, statsData.flawEffect, nextL) end
	end

	-- Race passive
	if statsData.racePassiveName then
		sectionHeader(leftCol, "RACE PASSIVE", nextL)
		infoRow(leftCol, statsData.racePassiveName, "", Theme.Colors.RarityEpic, nextL)
		if statsData.racePassiveEffect then descLabel(leftCol, statsData.racePassiveEffect, nextL) end
	end

	-- Doctrine passive
	if statsData.doctrinePassiveName then
		sectionHeader(leftCol, "DOCTRINE PASSIVE", nextL)
		infoRow(leftCol, statsData.doctrinePassiveName, "", Theme.Colors.Info, nextL)
		if statsData.doctrinePassiveEffect then descLabel(leftCol, statsData.doctrinePassiveEffect, nextL) end
	end

	-- Gear passives (2026-10-29): every passive the equipped gear gives, built by the server
	-- (GearPassiveSummary) so the battle inspector shows the same list. User layout: the SLOT name
	-- first, then one "Name - description" line per passive. Switched-off passives are dimmed
	-- with the reason; a passive equipped more than once notes the total and whether it stacks.
	sectionHeader(rightCol, "GEAR PASSIVES", nextR)
	do
		local function esc(t)
			return (string.gsub(tostring(t), "[&<>]", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;" }))
		end
		local function gpLabel(text, color, bold, rich)
			local t = Instance.new("TextLabel")
			t.Size = UDim2.new(1, 0, 0, 0); t.AutomaticSize = Enum.AutomaticSize.Y
			t.BackgroundTransparency = 1; t.BorderSizePixel = 0
			t.Font = bold and Theme.Font.PrimaryBold or Theme.Font.Primary
			t.TextSize = Theme.Text.Small(); t.TextColor3 = color
			t.TextXAlignment = Enum.TextXAlignment.Left; t.TextWrapped = true
			t.RichText = rich == true
			t.Text = "  " .. text
			t.LayoutOrder = nextR()
			t.Parent = rightCol -- parent last (NET-004)
		end
		local function slotLabel(serverSlot)
			local uiSlot = (MockData.SERVER_SLOT_TO_UI and MockData.SERVER_SLOT_TO_UI[serverSlot]) or serverSlot
			for _, def in ipairs(EQUIP_SLOTS) do
				if def.slot == uiSlot then return def.label end
			end
			return string.upper(tostring(serverSlot))
		end
		local groups = statsData.gearPassives
		if type(groups) ~= "table" or #groups == 0 then
			gpLabel("No passives from equipped gear", Theme.Colors.TextDisabled, false)
		else
			local nameHex = Theme.Colors.TextPrimary:ToHex()
			for _, g in ipairs(groups) do
				gpLabel(slotLabel(g.slot), Theme.Colors.TextGold, true)
				for _, p in ipairs(g.passives or {}) do
					local on = p.active == true
					local cnt = tonumber(p.count) or 1
					local nm = esc(p.name) .. (cnt > 1 and (" ×" .. cnt) or "")
					local line = on and ('<font color="#' .. nameHex .. '"><b>' .. nm .. "</b></font>") or ("<b>" .. nm .. "</b>")
					if p.desc and p.desc ~= "" then line = line .. " - " .. esc(p.desc) end
					if p.note then line = line .. "  ·  " .. esc(p.note) end
					if p.reason then line = line .. "  ·  " .. esc(p.reason) end
					gpLabel(line, on and Theme.Colors.TextSecondary or Theme.Colors.TextDisabled, false, true)
				end
			end
		end
	end

	end -- passives view

	-- DISMISS UNIT (Info tab, user decision 2026-10-15). Hidden for the Hero (protected
	-- avatar, project_rules 114). Tapping previews the exact severance fee from the server
	-- (5x recruitment cost), shows a Confirm dialog, then commits: equipped gear returns to
	-- inventory, the fee is charged, and the unit is removed from the roster + save.
	if ctx.getInfoView() == "stats" and unit.id ~= "unit_hero" then
		-- X icon + "Dismiss Unit" label (user 2026-10-29): the old themed button drew as the BACK
		-- arrow (Secondary style -> Back icon), easy to tap by mistake. Only the X is tappable;
		-- the label just names it. The confirm dialog below is unchanged.
		local dismissRow = Instance.new("Frame")
		dismissRow.Name = "DismissUnitRow"
		dismissRow.Size = UDim2.new(1, -16, 0, 36)
		dismissRow.BackgroundTransparency = 1; dismissRow.BorderSizePixel = 0
		dismissRow.LayoutOrder = 100000 -- always last in the left column
		local _dismissBtn = Theme.MakeIconButton(dismissRow, "X", function()
			local uid = unit.id
			local okP, prev = pcall(function() return BattleEvents.RequestDismissUnit:InvokeServer(uid) end)
			if not okP or type(prev) ~= "table" or not prev.ok then return end
			if prev.isAvatar then return end

			local overlay = Instance.new("Frame")
			overlay.Name = "DismissConfirm"
			overlay.Size = UDim2.fromScale(1, 1)
			overlay.BackgroundColor3 = Color3.new(0, 0, 0)
			overlay.BackgroundTransparency = 0.4
			overlay.ZIndex = 50
			overlay.Parent = ctx.getRootFrame()

			local box = Instance.new("Frame")
			box.Size = UDim2.new(0, 420, 0, 190)
			box.AnchorPoint = Vector2.new(0.5, 0.5)
			box.Position = UDim2.fromScale(0.5, 0.5)
			box.BackgroundColor3 = Theme.Colors.Panel or Color3.fromRGB(40, 40, 48)
			box.BorderSizePixel = 0
			box.ZIndex = 51
			box.Parent = overlay
			Instance.new("UICorner", box).CornerRadius = UDim.new(0, 8)

			local msg = makeLabel(box, {
				-- Free dismissal (2026-11-10): no separation pay line.
				Text = "Dismiss " .. (prev.name or "this unit") .. "?\nEquipped gear returns to your inventory. This cannot be undone.",
				Size = UDim2.new(1, -24, 0, 120),
				Position = UDim2.new(0, 12, 0, 12),
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Center,
			})
			msg.ZIndex = 52

			local function close() overlay:Destroy() end

			local cancelBtn = Theme.MakeButton(box, "Cancel", "Secondary", close, {
				size = UDim2.new(0, 120, 0, 40),
			})
			cancelBtn.Position = UDim2.new(0, 20, 1, -52)
			cancelBtn.ZIndex = 52

			if prev.canAfford then
				local confirmBtn = Theme.MakeButton(box, "Dismiss", "Primary", function()
					close()
					local okC, res = pcall(function() return BattleEvents.RequestDismissUnit:InvokeServer(uid, true) end)
					if okC and type(res) == "table" and res.done then
						MockData.SelectedUnitIndex = 1
						MockData.LoadFromServer()
						ctx.refresh()
					end
				end, { size = UDim2.new(0, 120, 0, 40) })
				confirmBtn.Position = UDim2.new(1, -140, 1, -52)
				confirmBtn.ZIndex = 52
			end
		end, { name = "Btn_DismissUnit", size = UDim2.fromOffset(32, 32), position = UDim2.fromOffset(0, 2) })
		local dismissLbl = Instance.new("TextLabel")
		dismissLbl.Name = "DismissUnitLabel"
		dismissLbl.Size = UDim2.new(1, -40, 1, 0)
		dismissLbl.Position = UDim2.fromOffset(40, 0)
		dismissLbl.BackgroundTransparency = 1; dismissLbl.BorderSizePixel = 0
		dismissLbl.Font = Theme.Font.PrimaryBold; dismissLbl.TextSize = Theme.Text.Body()
		dismissLbl.TextColor3 = Theme.Colors.TextPrimary
		dismissLbl.TextXAlignment = Enum.TextXAlignment.Left
		dismissLbl.Text = "Dismiss Unit"
		dismissLbl.Parent = dismissRow
		dismissRow.Parent = leftCol -- parent last (NET-004)
	end


	local d = statsData.derivedStats or {}

	-- Multiplier stats shown as signed % deviation from the 1.0 baseline (user ruling
	-- 2026-10-23): 0.830x -> -17.00%, 1.230x -> +23.00%. Baseline 1.0 = +0.00%.
	local function signedPct(v) return string.format("%+.2f%%", ((v or 1) - 1) * 100) end

	if ctx.getInfoView() == "stats" then -- derived stats: Stats view only
	sectionHeader(rightCol, "DEFENSE", nextR)
	infoRow(rightCol, "Defense Power", d.defensePower or 0, nil, nextR, "defensePower", function(dd) return tostring(dd.defensePower or 0) end)
	infoRow(rightCol, "Debuff Resist", signedPct(d.debuffResist), nil, nextR, "debuffResist", function(dd) return signedPct(dd.debuffResist) end)
	infoRow(rightCol, "RT Delay Resist", signedPct(d.rtDelayResist), nil, nextR, "rtDelayResist", function(dd) return signedPct(dd.rtDelayResist) end)
	infoRow(rightCol, "Stability", d.stability or 0, nil, nextR, "stability", function(dd) return tostring(dd.stability or 0) end)

	-- RESOURCES sits under the portrait in the left column (Stats view, 2026-10-29)
	sectionHeader(leftCol, "RESOURCES", nextL)
	infoResourceRows.maxHp = infoRow(leftCol, "Max HP", statsData.maxHp or 0, nil, nextL, "maxHp", nil)
	infoResourceRows.maxMp = infoRow(leftCol, "Max MP", statsData.maxMp or 0, nil, nextL, "maxMp", nil)
	infoRow(leftCol, "MP Regen", d.mpRegen or 0, nil, nextL, "mpRegen", function(dd) return tostring(dd.mpRegen or 0) end)

	-- COMBAT moved to the left column under RESOURCES (user 2026-10-29) to unpack the right side.
	sectionHeader(leftCol, "COMBAT", nextL)
	infoRow(leftCol, "Attack Power", d.attackPower or 0, nil, nextL, "attackPower", function(dd) return tostring(dd.attackPower or 0) end)
	infoRow(leftCol, "Effective WT", d.effectiveWt or 0, nil, nextL, "effectiveWt", function(dd) return tostring(dd.effectiveWt or 0) end)
	infoRow(leftCol, "Precision", NumberFormat.Pct(d.precision or 0), nil, nextL, "precision", function(dd) return NumberFormat.Pct(dd.precision or 0) end)
	infoRow(leftCol, "Evasiveness", NumberFormat.Pct(d.evasiveness or 0), nil, nextL, "evasiveness", function(dd) return NumberFormat.Pct(dd.evasiveness or 0) end)
	infoRow(leftCol, "Basic Attack RT", d.basicAttackRt or 0, nil, nextL, "basicAttackRt", function(dd) return tostring(dd.basicAttackRt or 0) end)

	sectionHeader(rightCol, "MOVEMENT", nextR)
	infoRow(rightCol, "Movement Range", d.movementRange or 0, nil, nextR, "movementRange", function(dd) return tostring(dd.movementRange or 0) end)
	infoRow(rightCol, "Jump", d.jump or 0, nil, nextR, "jump", function(dd) return tostring(dd.jump or 0) end)
	infoRow(rightCol, "Force", d.force or 0, nil, nextR, "force", function(dd) return tostring(dd.force or 0) end)

	sectionHeader(rightCol, "SKILLS", nextR)
	infoRow(rightCol, "Skill Potency", signedPct(d.skillPotency), nil, nextR, "skillPotency", function(dd) return signedPct(dd.skillPotency) end)
	infoRow(rightCol, "Bonus Skill Range", d.bonusSkillRange or 0, nil, nextR, "bonusSkillRange", function(dd) return tostring(dd.bonusSkillRange or 0) end)
	infoRow(rightCol, "Channel Speed", NumberFormat.Pct(d.channelReduction or 0), nil, nextR, "channelReduction", function(dd) return NumberFormat.Pct(dd.channelReduction or 0) end)
	infoRow(rightCol, "Heal Efficiency", signedPct(d.healEfficiency), nil, nextR, "healEfficiency", function(dd) return signedPct(dd.healEfficiency) end)

	sectionHeader(rightCol, "OTHER", nextR)
	infoRow(rightCol, "Discovery Radius", d.discoveryRadius or 0, nil, nextR, "discoveryRadius", function(dd) return tostring(dd.discoveryRadius or 0) end)
	infoRow(rightCol, "Unit Fortune", NumberFormat.Pct(d.unitFortune or 0), nil, nextR, "unitFortune", function(dd) return NumberFormat.Pct(dd.unitFortune or 0) end)
	infoRow(rightCol, "Base RT", d.baseRt or 0, nil, nextR, "baseRt", function(dd) return tostring(dd.baseRt or 0) end)
	infoRow(rightCol, "Starting RT", d.startingRt or 0, nil, nextR, "startingRt", function(dd) return tostring(dd.startingRt or 0) end)
	-- Rebuilt rows show committed values; if points are staged, re-apply the preview so the
	-- numbers match the stat panel after toggling back to Stats or returning to the tab.
	if pendingTotalFn() > 0 then requestStatPreview() end
	end -- stats view
end


function LoadoutInfo.Init(c: any)
	ctx = c
	EQUIP_SLOTS = c.EQUIP_SLOTS
end
LoadoutInfo.BuildStatPanel = function(...) return buildStatPanel(...) end
LoadoutInfo.BuildInfoContent = function(...) return buildInfoContent(...) end

return LoadoutInfo
