--!strict
-- LoadoutItemCompare.lua
-- CTRBLXAI | Loadout screen: item comparison content (selected vs currently equipped) shown
-- inside the item detail overlay.
-- Split out of LoadoutScreen.lua (2026-11-10, ARC-005 file-size split, step 6). Behaviour unchanged.
-- Host helpers come in through `ctx` -- no require of LoadoutScreen (no circular dependency).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService       = game:GetService("TextService")
local CTRBLXAI_UI = ReplicatedStorage:WaitForChild("CTRBLXAI", 10):WaitForChild("UI", 10)
local MockData    = require(CTRBLXAI_UI:WaitForChild("MockLoadoutData", 10))
local Theme       = require(CTRBLXAI_UI:WaitForChild("Theme", 10))

local LoadoutItemCompare: any = {}

local ctx: any = nil
-- Host helpers, bound in Init (thin wrappers so a later reassignment in the host is seen).
local function findOtherHolder(...) return ctx.findOtherHolder(...) end
local function getRarityColor(...) return ctx.getRarityColor(...) end
local function makeDescCard(...) return ctx.makeDescCard(...) end
local function makeLabel(...) return ctx.makeLabel(...) end
local BONUS_STAT_ORDER: any = nil -- host table, set in Init (one definition)

local buildComparisonContent



-- COMPARISON CONTENT (reference image 2)
--------------------------------------------------

buildComparisonContent = function(panel, selectedItem, currentItem, unit)
	-- Compact header: two item cards side by side (persistent, not affected by toggle)
	local headerY = 0
	local cardH = 40
	local halfW = 0.46
	-- 'On <unit>' line on the SELECTED card (W2): Small text (>=10px on phone), wraps,
	-- and both cards grow so nothing below overlaps. Desktop never shrinks (min 40).
	local selHolder = findOtherHolder(selectedItem.id, unit and unit.id)
	local selLvText = "Lv." .. (selectedItem.lv or 0) .. (selHolder and ("  · On " .. selHolder) or "")
	local selLvSize = Theme.Text.Small()
	local selLvH = 12
	if selHolder then
		local panelW = panel.AbsoluteSize.X
		local lineW = (panelW > 0 and (panelW * halfW - 32)) or 120
		if lineW < 40 then lineW = 120 end
		local b = TextService:GetTextSize(selLvText, selLvSize, Theme.Font.Primary, Vector2.new(lineW, 10000))
		selLvH = math.max(12, math.ceil(b.Y))
		cardH = math.max(cardH, 18 + selLvH + 4)
	end

	-- CURRENT label + card (left)
	makeLabel(panel, { Text = "CURRENT", Size = UDim2.new(halfW, 0, 0, 12),
		Position = UDim2.new(0, 0, 0, headerY),
		TextSize = Theme.Text.Tiny(), TextColor3 = Theme.Colors.TextSecondary,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.Font.PrimaryBold })

	local curCard = Instance.new("Frame")
	curCard.Size = UDim2.new(halfW, 0, 0, cardH)
	curCard.Position = UDim2.new(0, 0, 0, headerY + 14)
	curCard.BackgroundColor3 = getRarityColor(currentItem.rarity)
	curCard.BackgroundTransparency = 0.75
	curCard.BorderSizePixel = 0
	curCard.Parent = panel
	Instance.new("UICorner", curCard).CornerRadius = UDim.new(0, 4)
	Instance.new("UIStroke", curCard).Color = getRarityColor(currentItem.rarity)
	makeLabel(curCard, { Text = currentItem.icon or "?", Size = UDim2.new(0, 28, 1, 0),
		TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center })
	makeLabel(curCard, { Text = currentItem.name,
		Size = UDim2.new(1, -32, 0, 14), Position = UDim2.new(0, 30, 0, 3),
		Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Small(),
		TextColor3 = Theme.Colors.TextPrimary })
	makeLabel(curCard, { Text = "Lv." .. (currentItem.lv or 0) .. "  (Equipped)",
		Size = UDim2.new(1, -32, 0, 12), Position = UDim2.new(0, 30, 0, 18),
		TextSize = Theme.Text.Tiny(), TextColor3 = Theme.Colors.TextSecondary })

	-- SELECTED label + card (right)
	makeLabel(panel, { Text = "SELECTED", Size = UDim2.new(halfW, 0, 0, 12),
		Position = UDim2.new(1 - halfW, 0, 0, headerY),
		TextSize = Theme.Text.Tiny(), TextColor3 = Theme.Colors.TextSecondary,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.Font.PrimaryBold })

	local selCard = Instance.new("Frame")
	selCard.Size = UDim2.new(halfW, 0, 0, cardH)
	selCard.Position = UDim2.new(1 - halfW, 0, 0, headerY + 14)
	selCard.BackgroundColor3 = getRarityColor(selectedItem.rarity)
	selCard.BackgroundTransparency = 0.75
	selCard.BorderSizePixel = 0
	selCard.Parent = panel
	Instance.new("UICorner", selCard).CornerRadius = UDim.new(0, 4)
	local selStroke = Instance.new("UIStroke", selCard)
	selStroke.Color = Theme.Colors.TextGold
	selStroke.Thickness = 2
	makeLabel(selCard, { Text = selectedItem.icon or "?", Size = UDim2.new(0, 28, 1, 0),
		TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center })
	makeLabel(selCard, { Text = selectedItem.name,
		Size = UDim2.new(1, -32, 0, 14), Position = UDim2.new(0, 30, 0, 3),
		Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Small(),
		TextColor3 = Theme.Colors.TextPrimary })
	local selLvLbl = makeLabel(selCard, { Text = selLvText,
		Size = UDim2.new(1, -32, 0, selLvH), Position = UDim2.new(0, 30, 0, 18),
		TextSize = selHolder and selLvSize or Theme.Text.Tiny(), TextColor3 = Theme.Colors.TextSecondary,
		TextWrapped = selHolder ~= nil })
	if selHolder then
		selLvLbl.TextTruncate = Enum.TextTruncate.None
		selLvLbl.TextYAlignment = Enum.TextYAlignment.Top
	end

	-- Divider
	local divY = headerY + 14 + cardH + 4
	local div = Instance.new("Frame")
	div.Size = UDim2.new(1, 0, 0, 1)
	div.Position = UDim2.new(0, 0, 0, divY)
	div.BackgroundColor3 = Theme.Colors.Border
	div.BorderSizePixel = 0
	div.Parent = panel

	-- Content container (switchable)
	local bodyY = divY + 4
	local contentFrame = Instance.new("Frame")
	contentFrame.Size = UDim2.new(1, 0, 1, -(bodyY + 30))
	contentFrame.Position = UDim2.new(0, 0, 0, bodyY)
	contentFrame.BackgroundTransparency = 1
	contentFrame.Parent = panel

	-- Re-measure the 'On <unit>' line at the label's REAL width once layout is known
	-- (build-time width can be 0 -> 120px guess; a narrow phone line is ~106px).
	-- Updates both cards, the divider and the content area together. The connection
	-- lives on the label, so it is cleaned up when the panel is cleared. Only acts when
	-- the measured height changes; height never feeds back into width, so no loop.
	if selHolder then
		local function relayout()
			local w = selLvLbl.AbsoluteSize.X
			if w <= 0 then return end
			local b = TextService:GetTextSize(selLvText, selLvSize, Theme.Font.Primary, Vector2.new(w, 10000))
			local h = math.max(12, math.ceil(b.Y))
			if h == selLvH then return end
			selLvH = h
			local newCardH = math.max(40, 18 + h + 4)
			if newCardH == cardH then
				selLvLbl.Size = UDim2.new(1, -32, 0, h)
				return
			end
			cardH = newCardH
			curCard.Size = UDim2.new(halfW, 0, 0, cardH)
			selCard.Size = UDim2.new(halfW, 0, 0, cardH)
			selLvLbl.Size = UDim2.new(1, -32, 0, h)
			divY = headerY + 14 + cardH + 4
			div.Position = UDim2.new(0, 0, 0, divY)
			bodyY = divY + 4
			contentFrame.Size = UDim2.new(1, 0, 1, -(bodyY + 30))
			contentFrame.Position = UDim2.new(0, 0, 0, bodyY)
		end
		selLvLbl:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
		relayout()
	end

	local showingBonus = false

	-- Helper: build a stat comparison row
	local COMPARE_STATS = { "Attack", "Range", "Defense", "WT", "RTDelay" }
	local COMPARE_LABELS = { Attack="Attack", Range="Range", Defense="Defense", WT="WT", RTDelay="RT Delay" }
	local LOWER_IS_BETTER = { WT = true, RTDelay = true }
	local _STAT_ORDER = { "STR", "INT", "DEX", "AGI", "VIT", "LUK" }

	local function addStatRow(parent, label, cvStr, svStr, delta, isGood, y)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 16)
		row.Position = UDim2.new(0, 0, 0, y)
		row.BackgroundTransparency = 1
		row.Parent = parent
		makeLabel(row, { Text = cvStr, Size = UDim2.new(0.18, 0, 1, 0),
			TextSize = Theme.Text.Body(), TextColor3 = Theme.Colors.TextPrimary,
			TextXAlignment = Enum.TextXAlignment.Center, Font = Theme.Font.PrimaryBold })
		makeLabel(row, { Text = label, Size = UDim2.new(0.24, 0, 1, 0),
			Position = UDim2.new(0.18, 0, 0, 0),
			TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextSecondary,
			TextXAlignment = Enum.TextXAlignment.Center })
		makeLabel(row, { Text = svStr, Size = UDim2.new(0.18, 0, 1, 0),
			Position = UDim2.new(0.54, 0, 0, 0),
			TextSize = Theme.Text.Body(), TextColor3 = Theme.Colors.TextPrimary,
			TextXAlignment = Enum.TextXAlignment.Center, Font = Theme.Font.PrimaryBold })
		if delta and delta ~= "" then
			makeLabel(row, { Text = delta, Size = UDim2.new(0.14, 0, 1, 0),
				Position = UDim2.new(0.78, 0, 0, 0),
				TextSize = Theme.Text.Small(), Font = Theme.Font.PrimaryBold,
				TextColor3 = isGood and Theme.Colors.Success or Theme.Colors.Danger,
				TextXAlignment = Enum.TextXAlignment.Center })
		end
	end

	-- Grow-to-fit passive card for the COMPARE view. Parented into a per-column
	-- UIListLayout container (built by the callers) so cards auto-stack and the
	-- description never clips — same shared makeDescCard the solo detail view uses.
	-- (2026-10-23: replaces the old fixed-36px absolutely-positioned card, which
	-- clipped long descriptions AND overlapped when an item had 2+ passives.)
	local function addPassiveCard(parent, name, desc, isLost, layoutOrder)
		local tagColor = isLost and Theme.Colors.Danger or Theme.Colors.Success
		local suffix = isLost and " (Lost)" or " (Gained)"
		return makeDescCard(parent, (name or "Passive") .. suffix, tagColor, desc or "",
			tagColor, 0.85, layoutOrder or 0)
	end

	-- Build a 0.48-wide auto-stacking passive column at vertical offset y.
	local function makePassiveCompareCol(parent, xScale, y)
		local colf = Instance.new("Frame")
		colf.Size = UDim2.new(0.48, 0, 0, 0)
		colf.AutomaticSize = Enum.AutomaticSize.Y
		colf.Position = UDim2.new(xScale, 0, 0, y)
		colf.BackgroundTransparency = 1
		colf.BorderSizePixel = 0
		colf.Parent = parent
		local ll = Instance.new("UIListLayout", colf)
		ll.SortOrder = Enum.SortOrder.LayoutOrder
		ll.Padding = UDim.new(0, 4)
		return colf
	end

	-- ============ BASE COMPARE VIEW ============
	local function buildBaseCompare()
		for _, child in ipairs(contentFrame:GetChildren()) do child:Destroy() end

		local curStats = currentItem.baseStats or {}
		local selStats = selectedItem.baseStats or {}
		local rowY = 0

		-- Doctrine comparison (2026-10-20): stat packages are %, so pull the real per-unit
		-- before/after/deltas from the server and show those, then the passive lost/gained.
		if selectedItem.isDoctrine then
			local cmp = (MockData.GetDoctrineComparison and unit)
				and MockData.GetDoctrineComparison(unit.id, selectedItem.doctrineId) or nil
			local STAT_ROWS = {
				{k="STR",l="STR"},{k="AGI",l="AGI"},{k="INT",l="INT"},
				{k="VIT",l="VIT"},{k="DEX",l="DEX"},{k="LUK",l="LUK"},
				{k="maxHp",l="Max HP"},{k="maxMp",l="Max MP"},
			}
			if cmp and cmp.before and cmp.after then
				for _, sr in ipairs(STAT_ROWS) do
					local bv, av = cmp.before[sr.k], cmp.after[sr.k]
					if bv ~= nil or av ~= nil then
						local delta, isGood = "", false
						local bn, an = tonumber(bv), tonumber(av)
						if bn and an then
							local diff = an - bn
							if diff ~= 0 then
								isGood = diff > 0
								delta = (diff > 0 and "+" or "") .. diff
							end
						end
						addStatRow(contentFrame, sr.l, tostring(bv or "—"), tostring(av or "—"), delta, isGood, rowY)
						rowY = rowY + 18
					end
				end
			else
				makeLabel(contentFrame, { Text = "Stat comparison unavailable",
					Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 0, rowY),
					TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextDisabled })
				rowY = rowY + 18
			end
			rowY = rowY + 4
			makeLabel(contentFrame, { Text = "PASSIVE", Size = UDim2.new(1, 0, 0, 12),
				Position = UDim2.new(0, 0, 0, rowY), Font = Theme.Font.PrimaryBold,
				TextSize = Theme.Text.Tiny(), TextColor3 = Theme.Colors.TextSecondary,
				TextXAlignment = Enum.TextXAlignment.Center })
			rowY = rowY + 14
			local lpc = makePassiveCompareCol(contentFrame, 0, rowY)
			local rpc = makePassiveCompareCol(contentFrame, 0.52, rowY)
			if currentItem.passives then
				for idx, p in ipairs(currentItem.passives) do
					addPassiveCard(lpc, p.name, p.desc, true, idx)
				end
			end
			if selectedItem.passives then
				for idx, p in ipairs(selectedItem.passives) do
					addPassiveCard(rpc, p.name, p.desc, false, idx)
				end
			end
			return
		end

		for _, key in ipairs(COMPARE_STATS) do
			local cv = curStats[key]
			local sv = selStats[key]
			if cv ~= nil or sv ~= nil then
				local delta = ""
				local isGood = false
				local cvNum = tonumber(cv)
				local svNum = tonumber(sv)
				if cvNum and svNum then
					local diff = svNum - cvNum
					if diff ~= 0 then
						local lowerBetter = LOWER_IS_BETTER[key]
						isGood = (lowerBetter and diff < 0) or (not lowerBetter and diff > 0)
						local sign = diff > 0 and "+" or ""
						delta = sign .. diff
					end
				elseif type(cv) == "string" and type(sv) == "string" and cv ~= sv then
					delta = "~"
				end
				addStatRow(contentFrame, COMPARE_LABELS[key] or key,
					tostring(cv or "—"), tostring(sv or "—"), delta, isGood, rowY)
				rowY = rowY + 18
			end
		end

		-- Archetype passive comparison
		rowY = rowY + 4
		makeLabel(contentFrame, { Text = "PASSIVES",
			Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 0, rowY),
			Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Tiny(),
			TextColor3 = Theme.Colors.TextSecondary,
			TextXAlignment = Enum.TextXAlignment.Center })
		rowY = rowY + 14

		local curPN = {}
		if currentItem.passives then for _, p in ipairs(currentItem.passives) do curPN[p.name] = p end end
		local selPN = {}
		if selectedItem.passives then for _, p in ipairs(selectedItem.passives) do selPN[p.name] = p end end

		local lpc2 = makePassiveCompareCol(contentFrame, 0, rowY)
		local rpc2 = makePassiveCompareCol(contentFrame, 0.52, rowY)
		if currentItem.passives then
			for idx, p in ipairs(currentItem.passives) do
				if not selPN[p.name] then
					addPassiveCard(lpc2, p.name, p.desc, true, idx)
				end
			end
		end
		if selectedItem.passives then
			for idx, p in ipairs(selectedItem.passives) do
				if not curPN[p.name] then
					addPassiveCard(rpc2, p.name, p.desc, false, idx)
				end
			end
		end
	end

	-- ============ BONUS COMPARE VIEW ============
	local function buildBonusCompare()
		for _, child in ipairs(contentFrame:GetChildren()) do child:Destroy() end

		-- Side-by-side: left = current item bonuses, right = selected item bonuses
		local leftCol = Instance.new("Frame")
		leftCol.Size = UDim2.new(0.48, 0, 1, 0)
		leftCol.Position = UDim2.new(0, 0, 0, 0)
		leftCol.BackgroundTransparency = 1
		leftCol.Parent = contentFrame

		local rightCol = Instance.new("Frame")
		rightCol.Size = UDim2.new(0.48, 0, 1, 0)
		rightCol.Position = UDim2.new(0.52, 0, 0, 0)
		rightCol.BackgroundTransparency = 1
		rightCol.Parent = contentFrame

		-- Helper: list bonus stats + passives for one item into a column
		local function fillBonusColumn(col, bonusStats, bonusPassives, bonusStatPcts)
			local y = 0

			-- Bonus numerical stats
			makeLabel(col, { Text = "BONUS STATS", Size = UDim2.new(1, 0, 0, 12),
				Position = UDim2.new(0, 0, 0, y),
				Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Tiny(),
				TextColor3 = Theme.Colors.TextSecondary })
			y = y + 14

			local bs = bonusStats or {}
			local pcts = bonusStatPcts or {}
			local hasStats = false
			for _, sn in ipairs(BONUS_STAT_ORDER) do
				local bv = bs[sn]
				if bv and bv ~= 0 then
					hasStats = true
					local bp = pcts[sn]
					local pctTxt = (bp and bp ~= 0) and ("  " .. (bp > 0 and "+" or "") .. bp .. "%") or ""
					local sign = bv > 0 and "+" or ""
					makeLabel(col, { Text = sn .. "  " .. sign .. bv .. pctTxt,
						Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 4, 0, y),
						TextSize = Theme.Text.Body(), TextColor3 = Theme.Colors.Success })
					y = y + 16
				end
			end
			if not hasStats then
				makeLabel(col, { Text = "None", Size = UDim2.new(1, 0, 0, 12),
					Position = UDim2.new(0, 4, 0, y),
					TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextDisabled })
				y = y + 14
			end

			-- Bonus passives
			y = y + 4
			makeLabel(col, { Text = "BONUS PASSIVES", Size = UDim2.new(1, 0, 0, 12),
				Position = UDim2.new(0, 0, 0, y),
				Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Tiny(),
				TextColor3 = Theme.Colors.TextSecondary })
			y = y + 14

			local bp = bonusPassives or {}
			if #bp > 0 then
				local pcol = Instance.new("Frame")
				pcol.Size = UDim2.new(1, 0, 0, 0)
				pcol.AutomaticSize = Enum.AutomaticSize.Y
				pcol.Position = UDim2.new(0, 0, 0, y)
				pcol.BackgroundTransparency = 1
				pcol.BorderSizePixel = 0
				pcol.Parent = col
				local plist = Instance.new("UIListLayout", pcol)
				plist.SortOrder = Enum.SortOrder.LayoutOrder
				plist.Padding = UDim.new(0, 4)
				for idx, p in ipairs(bp) do
					makeDescCard(pcol, p.name or "Passive", Theme.Colors.Info, p.desc or "",
						Theme.Colors.PanelRaised, 0.3, idx)
				end
			else
				makeLabel(col, { Text = "None", Size = UDim2.new(1, 0, 0, 12),
					Position = UDim2.new(0, 4, 0, y),
					TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextDisabled })
			end
		end

		fillBonusColumn(leftCol, currentItem.bonusStats, currentItem.bonusPassives, currentItem.bonusStatPcts)
		fillBonusColumn(rightCol, selectedItem.bonusStats, selectedItem.bonusPassives, selectedItem.bonusStatPcts)
	end


	-- Show base view initially
	buildBaseCompare()

	-- Toggle button (lower-left of panel). Hidden for doctrine compare (no bonus view).
	if not selectedItem.isDoctrine then
	local toggleBtn = Instance.new("TextButton")
	toggleBtn.Size = UDim2.new(0, 90, 0, 24)
	toggleBtn.Position = UDim2.new(0, 0, 1, -28)
	toggleBtn.BackgroundColor3 = Theme.Colors.Surface
	toggleBtn.BackgroundTransparency = 0.2
	toggleBtn.Font = Theme.Font.PrimaryBold
	toggleBtn.TextSize = Theme.Text.Small()
	toggleBtn.TextColor3 = Theme.Colors.TextSecondary
	toggleBtn.Text = "Show Bonus"
	toggleBtn.BorderSizePixel = 0
	toggleBtn.Parent = panel
	Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 4)
	local toggleIcon = Instance.new("ImageLabel")
	toggleIcon.Name = "ToggleIcon"
	toggleIcon.Size = UDim2.new(0, 12, 0, 12)
	toggleIcon.Position = UDim2.new(1, -16, 0.5, -6)
	toggleIcon.BackgroundTransparency = 1
	toggleIcon.Image = Theme.Icons.Expand
	toggleIcon.ScaleType = Enum.ScaleType.Fit
	toggleIcon.ImageColor3 = Theme.Colors.TextSecondary
	toggleIcon.Parent = toggleBtn
	toggleBtn.Activated:Connect(function()
		showingBonus = not showingBonus
		if showingBonus then
			buildBonusCompare()
			toggleBtn.Text = "Show Base"
			if toggleBtn:FindFirstChild("ToggleIcon") then toggleBtn.ToggleIcon.Image = Theme.Icons.Collapse end
		else
			buildBaseCompare()
			toggleBtn.Text = "Show Bonus"
			if toggleBtn:FindFirstChild("ToggleIcon") then toggleBtn.ToggleIcon.Image = Theme.Icons.Expand end
		end
	end)
	end
end



--------------------------------------------------


function LoadoutItemCompare.Init(c: any)
	ctx = c
	BONUS_STAT_ORDER = c.BONUS_STAT_ORDER
end
LoadoutItemCompare.BuildComparisonContent = function(...) return buildComparisonContent(...) end

return LoadoutItemCompare
