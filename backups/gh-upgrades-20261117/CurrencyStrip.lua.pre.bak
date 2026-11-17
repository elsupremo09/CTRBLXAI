--!strict
-- CurrencyStrip.lua
-- CTRBLXAI | Header currency strip: icon + number per currency, right-aligned (one builder for
-- every header; user 2026-11-17: the dungeon header uses the same look as the guild home).
-- Moved from GuildMenu.client.lua (user rulings 2026-11-13 12:40 AM / 12:42 AM): one row when
-- everything fits; else the numbers step down (never below the 10 px floor), the icons shrink to
-- 16 px and the gaps to 6 px; if it still does not fit, TWO rows (opts.bottomKeys go below). A row
-- that still overflows caps each cell and ends its number with "...". The strip clips, so it never
-- spills over what sits left of it. A key with no Theme.GuildIcons art shows its text only.
-- Display only: callers set each value's text (numbers with thousands separators, or approved text).

local TextService = game:GetService("TextService")

local uiFolder = script.Parent
local Theme: any = (require :: any)(uiFolder:WaitForChild("Theme", 10))

local CurrencyStrip = {}

local CURRENCY_GAP, CURRENCY_ICON_GAP = 10, 4

--- "40224" -> "40,224" (same as the guild header).
function CurrencyStrip.WithCommas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function makeValue(parent: Instance): TextLabel
	local num = Instance.new("TextLabel")
	num.Name = "Value"
	num.BackgroundTransparency = 1
	num.BorderSizePixel = 0
	num.Font = Theme.Font.PrimaryBold
	num.TextSize = Theme.Text.Body()
	num.TextColor3 = Theme.Colors.TextPrimary
	num.TextXAlignment = Enum.TextXAlignment.Left
	num.TextYAlignment = Enum.TextYAlignment.Center
	num.TextWrapped = false
	num.AutomaticSize = Enum.AutomaticSize.X
	num.Size = UDim2.fromScale(0, 1)
	num.LayoutOrder = 2
	num.Text = ""
	num.Parent = parent
	return num
end

-- opts: keys (display order), bottomKeys (set: keys that go to the second row),
--       size / position (UDim2; default the right 60% of the parent), name.
-- Returns { Strip, Labels = { [key]: TextLabel }, Set(key, text), Fit() }.
function CurrencyStrip.Create(parent: Instance, opts: { keys: { string }, bottomKeys: { [string]: boolean }?, size: UDim2?, position: UDim2?, name: string? }): any
	local keys = opts.keys
	local bottomKeys = opts.bottomKeys or {}
	local strip = Instance.new("Frame")
	strip.Name = opts.name or "Currencies"
	strip.BackgroundTransparency = 1
	strip.BorderSizePixel = 0
	strip.Size = opts.size or UDim2.fromScale(0.6, 1)
	strip.Position = opts.position or UDim2.fromScale(0.4, 0)
	strip.ClipsDescendants = true -- never spill left over what sits beside it
	local function makeRow(name: string): (Frame, UIListLayout)
		local r = Instance.new("Frame")
		r.Name = name
		r.BackgroundTransparency = 1
		r.BorderSizePixel = 0
		r.Size = UDim2.fromScale(1, 1)
		local l = Instance.new("UIListLayout")
		l.FillDirection = Enum.FillDirection.Horizontal
		l.HorizontalAlignment = Enum.HorizontalAlignment.Right
		l.VerticalAlignment = Enum.VerticalAlignment.Center
		l.SortOrder = Enum.SortOrder.LayoutOrder
		l.Padding = UDim.new(0, CURRENCY_GAP)
		l.Parent = r
		r.Parent = strip
		return r, l
	end
	local rowTop, layoutTop = makeRow("RowTop")
	local rowBottom, layoutBottom = makeRow("RowBottom")
	rowBottom.Visible = false
	local cells: { [string]: Frame } = {}
	local labels: { [string]: TextLabel } = {}
	local icons: { [string]: ImageLabel } = {}
	local topKeys: { string }, lowKeys: { string } = {}, {}
	for i, key in ipairs(keys) do
		if bottomKeys[key] then table.insert(lowKeys, key) else table.insert(topKeys, key) end
		local cell = Instance.new("Frame")
		cell.Name = key
		cell.BackgroundTransparency = 1
		cell.BorderSizePixel = 0
		cell.AutomaticSize = Enum.AutomaticSize.X
		cell.Size = UDim2.fromScale(0, 1)
		cell.LayoutOrder = i
		local cl = Instance.new("UIListLayout")
		cl.FillDirection = Enum.FillDirection.Horizontal
		cl.VerticalAlignment = Enum.VerticalAlignment.Center
		cl.SortOrder = Enum.SortOrder.LayoutOrder
		cl.Padding = UDim.new(0, CURRENCY_ICON_GAP)
		cl.Parent = cell
		local art = Theme.GuildIcons and Theme.GuildIcons[key]
		if art then
			local ico = Instance.new("ImageLabel")
			ico.Name = "Icon"
			ico.BackgroundTransparency = 1
			ico.ScaleType = Enum.ScaleType.Fit
			ico.Image = art
			ico.Size = UDim2.fromOffset(24, 24) -- re-sized to 70% of the header height in Fit
			ico.LayoutOrder = 1
			ico.Parent = cell
			icons[key] = ico
		end
		labels[key] = makeValue(cell)
		cell.Parent = rowTop
		cells[key] = cell
	end
	strip.Parent = parent -- properties and children before Parent (NET-004)

	-- Measured, not scaled: the largest number size (Body down to 10 px) whose total width
	-- (icons + gaps + text bounds from TextService) fits the strip. No feedback loop.
	local function fit()
		local w, h = strip.AbsoluteSize.X, strip.AbsoluteSize.Y
		if w <= 0 or h <= 0 or #keys == 0 then return end
		local font = labels[keys[1]].Font
		local function textW(k: string, size: number): number
			return math.ceil(TextService:GetTextSize(labels[k].Text, size, font, Vector2.new(4000, 200)).X)
		end
		local function totalWidth(list: { string }, size: number, px: number, gap: number): number
			local total = gap * math.max(0, #list - 1)
			for _, k in list do
				total += (if icons[k] then px + CURRENCY_ICON_GAP else 0) + textW(k, size)
			end
			return total
		end
		local px = math.max(16, math.floor(h * 0.7))
		local gap = CURRENCY_GAP
		local size = Theme.Text.Body()
		while size > 10 and totalWidth(keys, size, px, gap) > w do size -= 1 end
		while px > 16 and totalWidth(keys, size, px, gap) > w do px -= 1 end
		if totalWidth(keys, size, px, gap) > w then gap = 6 end
		local twoRows = #lowKeys > 0 and totalWidth(keys, size, px, gap) > w
		if twoRows then
			px, size, gap = 16, 10, 6
		end
		rowBottom.Visible = twoRows
		rowTop.Size = if twoRows then UDim2.fromScale(1, 0.5) else UDim2.fromScale(1, 1)
		rowBottom.Position = UDim2.fromScale(0, 0.5)
		rowBottom.Size = UDim2.fromScale(1, 0.5)
		for k, cell in cells do
			local want = if twoRows and bottomKeys[k] then rowBottom else rowTop
			if cell.Parent ~= want then cell.Parent = want end
		end
		for _, ico in icons do
			if ico.Size.X.Offset ~= px then ico.Size = UDim2.fromOffset(px, px) end
		end
		if layoutTop.Padding.Offset ~= gap then layoutTop.Padding = UDim.new(0, gap) end
		if layoutBottom.Padding.Offset ~= gap then layoutBottom.Padding = UDim.new(0, gap) end
		local capped: { [string]: number } = {}
		local rowLists = if twoRows then { topKeys, lowKeys } else { keys }
		for _, rowKeys in rowLists do
			if #rowKeys > 0 and totalWidth(rowKeys, size, px, gap) > w then
				local share = math.floor((w - gap * (#rowKeys - 1)) / #rowKeys)
				for _, k in rowKeys do
					local maxText = math.max(0, share - (if icons[k] then px + CURRENCY_ICON_GAP else 0))
					if textW(k, size) > maxText then capped[k] = maxText end
				end
			end
		end
		for _, k in keys do
			local lbl = labels[k]
			if lbl.TextSize ~= size then lbl.TextSize = size end
			local cap = capped[k]
			if cap then
				lbl.AutomaticSize = Enum.AutomaticSize.None
				lbl.Size = UDim2.new(0, cap, 1, 0)
				lbl.TextTruncate = Enum.TextTruncate.AtEnd
			elseif lbl.AutomaticSize ~= Enum.AutomaticSize.X then
				lbl.AutomaticSize = Enum.AutomaticSize.X
				lbl.Size = UDim2.fromScale(0, 1)
				lbl.TextTruncate = Enum.TextTruncate.None
			end
		end
	end
	strip:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	task.defer(fit)

	local self: any = { Strip = strip, Labels = labels }
	function self.Set(key: string, text: string)
		local lbl = labels[key]
		if not lbl then return end
		lbl.Text = text
		fit()
	end
	self.Fit = fit
	-- Width the visible icons + numbers take (right-aligned), so a header can give the rest to its
	-- text (dungeon header, user 2026-11-17 11:39 AM: same strip as the guild base, text fits the rest).
	function self.ContentWidth(): number
		local w = layoutTop.AbsoluteContentSize.X
		if rowBottom.Visible then w = math.max(w, layoutBottom.AbsoluteContentSize.X) end
		return w
	end
	function self.OnContentChanged(cb: () -> ())
		layoutTop:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(cb)
		layoutBottom:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(cb)
		rowBottom:GetPropertyChangedSignal("Visible"):Connect(cb)
	end
	return self
end

return table.freeze(CurrencyStrip)
