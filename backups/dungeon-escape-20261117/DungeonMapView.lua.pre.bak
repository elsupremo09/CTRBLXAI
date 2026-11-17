--!strict
-- DungeonMapView.lua
-- CTRBLXAI | Dungeon map grid + map key, moved word for word out of DungeonScreen.buildMap
-- (Dungeon step 8, 2026-11-14: DungeonScreen was at 999 of 1000 lines). Display only.

local WAIT = 10
local uiFolder = script.Parent
local Theme: any = (require :: any)(uiFolder:WaitForChild("Theme", WAIT))

local DungeonMapView = {}

-- deps: makeText, corner, stroke, ts, isCleared, shownType, nodeOf, act, render, arrive,
-- getLegendOpen, setLegendOpen, consts { ROW_STEP, ROOM_D, BOSS_D, MAP_PAD, NODE_H }, ROOM_LABEL, KEY_ORDER.
function DungeonMapView.Draw(main: any, run: any, here: any, deps: any)
	local makeText, corner, stroke, ts = deps.makeText, deps.corner, deps.stroke, deps.ts
	local isCleared, shownType, nodeOf, act, render, arrive = deps.isCleared, deps.shownType, deps.nodeOf, deps.act, deps.render, deps.arrive
	local ROW_STEP, ROOM_D, BOSS_D, MAP_PAD, NODE_H = deps.ROW_STEP, deps.ROOM_D, deps.BOSS_D, deps.MAP_PAD, deps.NODE_H
	local ROOM_LABEL, KEY_ORDER = deps.ROOM_LABEL, deps.KEY_ORDER
	local legendOpen = deps.getLegendOpen()
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	local top = math.max(0, NODE_H + 2 + (deps.topExtra or 0)) -- 2026-11-15: no info/relic rows above the map
	grid.Position = UDim2.fromOffset(0, top)
	grid.Size = UDim2.new(1, 0, 1, -top)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 4
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	local rows = run.floors + 1
	local canvasH = (rows - 1) * ROW_STEP + BOSS_D + MAP_PAD * 2 -- top and bottom padding: no row cut off
	grid.CanvasSize = UDim2.fromOffset(0, canvasH)

	local W = math.max(240, main.AbsoluteSize.X - 8) -- fit the width; vertical scroll for the rest
	local width = run.width or 4
	local colW = W / width
	local d = math.max(44, math.min(ROOM_D, colW - 10))
	local legal: { [string]: boolean } = {}
	for _, id in run.next do legal[id] = true end
	local pos: { [string]: Vector2 } = {}
	for _, n in run.nodes do
		local x = if n.id == "boss" then W / 2 else (n.col - 0.5) * colW
		local y = MAP_PAD + BOSS_D / 2 + (rows - n.row) * ROW_STEP
		pos[n.id] = Vector2.new(x, y)
	end
	-- Paths first, at the lowest ZIndex, so they run BEHIND the rooms.
	for _, n in run.nodes do
		local a = pos[n.id]
		for _, nid in n.next do
			local q = pos[nid]
			if a and q then
				local dv = q - a
				local hot = n.id == run.at and legal[nid]
				local line = Instance.new("Frame")
				line.Name = "Path"
				line.AnchorPoint = Vector2.new(0.5, 0.5)
				line.Position = UDim2.fromOffset((a.X + q.X) / 2, (a.Y + q.Y) / 2)
				line.Size = UDim2.fromOffset(dv.Magnitude, if hot then 3 else 2)
				line.Rotation = math.deg(math.atan2(dv.Y, dv.X))
				line.BorderSizePixel = 0
				line.BackgroundColor3 = if hot then Theme.Colors.TextGold else Theme.Colors.Border
				line.BackgroundTransparency = if hot then 0 else 0.3
				line.ZIndex = 1
				line.Parent = grid
			end
		end
	end
	for _, n in run.nodes do
		local p = pos[n.id]
		local isHere = n.id == run.at
		local done = isCleared(n.id)
		local glow = legal[n.id] == true
		local t = shownType(n)
		local size = if n.id == "boss" then BOSS_D else d
		local col = Theme.DungeonRoomColors[t] or Theme.DungeonRoomColors.Battle
		local icon = Theme.DungeonRoomIcons[t] or ""
		local fade = done and not isHere
		local btn = Instance.new("TextButton")
		btn.Name = "Room_" .. n.id
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.AnchorPoint = Vector2.new(0.5, 0.5)
		btn.Position = UDim2.fromOffset(p.X, p.Y)
		btn.Size = UDim2.fromOffset(size, size)
		btn.BackgroundColor3 = if icon == "" then col else Theme.Colors.PanelRaised
		btn.BackgroundTransparency = if fade then 0.65 else (if icon == "" then 0.15 else 0.05)
		btn.BorderSizePixel = 0
		btn.ZIndex = 3
		corner(btn, UDim.new(0.5, 0))
		-- Ring: type colour; gold when you can go there; white on the room you're in.
		local ringCol = if glow then Theme.Colors.TextGold elseif isHere then Theme.Colors.TextPrimary else col
		local ring = Instance.new("UIStroke")
		ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ring.Color = ringCol
		ring.Thickness = if glow or isHere then 3 else 2
		ring.Transparency = if fade then 0.6 else 0
		ring.Parent = btn
		if icon ~= "" then
			local img = Instance.new("ImageLabel")
			img.Name = "Icon"
			img.BackgroundTransparency = 1
			img.AnchorPoint = Vector2.new(0.5, 0.5)
			img.Position = UDim2.fromScale(0.5, 0.5)
			img.Size = UDim2.fromScale(0.8, 0.8)
			img.Image = icon
			img.ScaleType = Enum.ScaleType.Fit
			img.ImageTransparency = if fade then 0.6 else 0
			img.ZIndex = 4
			img.Parent = btn
		else
			-- Fallback until the art is uploaded: coloured circle + the approved one-word label.
			local label = makeText(btn, ROOM_LABEL[t] or "?", 10, Theme.Colors.TextPrimary, true)
			label.TextXAlignment = Enum.TextXAlignment.Center
			label.TextWrapped = false
			label.AnchorPoint = Vector2.new(0.5, 0.5)
			label.Position = UDim2.fromScale(0.5, 0.5)
			label.Size = UDim2.new(1, -4, 0, 12)
			label.TextTransparency = if fade then 0.5 else 0
			label.ZIndex = 4
		end
		local sub = if isHere then "You are here" elseif done then "Cleared" else nil -- DG-HERE / DG-CLEARED
		if sub then
			local sl = makeText(grid, sub, 10, if isHere then Theme.Colors.TextGold else Theme.Colors.TextSecondary, isHere)
			sl.TextWrapped = false
			sl.AnchorPoint = Vector2.new(0, 0.5)
			sl.Position = UDim2.fromOffset(p.X + size / 2 + 3, p.Y)
			sl.Size = UDim2.fromOffset(math.max(40, colW / 2 - size / 2 - 4), 12)
			sl.ZIndex = 4
		end
		local nid = n.id
		btn.Activated:Connect(function()
			if isHere then
				arrive(nodeOf(nid)) -- re-open the room (e.g. a battle left unfinished)
			elseif deps.peek then
				deps.peek(nodeOf(nid)) -- 2026-11-15: quick peek card; its Go button moves (legal rooms only)
			elseif glow then
				if act({ action = "Move", nodeId = nid }) then
					render()
					arrive(nodeOf(nid))
				end
			end
		end)
		btn.Parent = grid
	end

	-- Map key (legend): toggled by a 44 px swatch button, no new text (labels = the approved names).
	local keyBtn = Instance.new("TextButton")
	keyBtn.Name = "KeyToggle"
	keyBtn.Text = ""
	keyBtn.AutoButtonColor = false
	keyBtn.AnchorPoint = Vector2.new(0, 1)
	keyBtn.Position = UDim2.new(0, 2, 1, -2)
	keyBtn.Size = UDim2.fromOffset(NODE_H, NODE_H)
	keyBtn.BackgroundColor3 = Theme.Colors.PanelRaised
	keyBtn.BackgroundTransparency = 0.1
	keyBtn.BorderSizePixel = 0
	keyBtn.ZIndex = 8
	corner(keyBtn)
	stroke(keyBtn, if legendOpen then Theme.Colors.TextGold else Theme.Colors.Border, 2)
	for i = 1, 4 do
		local sw = Instance.new("Frame")
		sw.Size = UDim2.fromOffset(12, 12)
		sw.Position = UDim2.fromOffset(if i % 2 == 1 then 8 else 24, if i <= 2 then 8 else 24)
		sw.BackgroundColor3 = Theme.DungeonRoomColors[KEY_ORDER[({ 1, 4, 6, 7 })[i]]]
		sw.BorderSizePixel = 0
		sw.ZIndex = 9
		corner(sw, UDim.new(0.5, 0))
		sw.Parent = keyBtn
	end
	keyBtn.Activated:Connect(function()
		deps.setLegendOpen(not legendOpen)
		render()
	end)
	keyBtn.Parent = main
	if legendOpen then
		local panel = Instance.new("Frame")
		panel.Name = "MapKey"
		panel.AnchorPoint = Vector2.new(0, 1)
		panel.Position = UDim2.new(0, NODE_H + 8, 1, -2)
		panel.Size = UDim2.fromOffset(2 * 104 + 12, 4 * 26 + 10)
		panel.BackgroundColor3 = Theme.Colors.PanelRaised
		panel.BackgroundTransparency = 0.05
		panel.BorderSizePixel = 0
		panel.ZIndex = 8
		corner(panel)
		stroke(panel, Theme.Colors.Border, 1)
		for i, kt in KEY_ORDER do
			local cx = 6 + ((i - 1) // 4) * 104
			local cy = 5 + ((i - 1) % 4) * 26
			local dot = Instance.new("Frame")
			dot.Size = UDim2.fromOffset(20, 20)
			dot.Position = UDim2.fromOffset(cx, cy + 2)
			dot.BackgroundColor3 = Theme.DungeonRoomColors[kt]
			dot.BorderSizePixel = 0
			dot.ZIndex = 9
			corner(dot, UDim.new(0.5, 0))
			local ic = Theme.DungeonRoomIcons[kt]
			if ic ~= "" then
				local img = Instance.new("ImageLabel")
				img.BackgroundTransparency = 1
				img.Size = UDim2.fromScale(1, 1)
				img.Image = ic
				img.ScaleType = Enum.ScaleType.Fit
				img.ZIndex = 10
				img.Parent = dot
			end
			dot.Parent = panel
			local kl = makeText(panel, ROOM_LABEL[kt], ts(), Theme.Colors.TextPrimary)
			kl.TextWrapped = false
			kl.Position = UDim2.fromOffset(cx + 24, cy)
			kl.Size = UDim2.fromOffset(76, 24)
			kl.ZIndex = 9
		end
		panel.Parent = main
	end
	-- Biome background behind the map (2026-11-15): image + dark overlay, below paths (ZIndex 0).
	-- Missing biome or id = no image, the plain background stays.
	local bgOld = main:FindFirstChild("BiomeBg")
	if bgOld then bgOld:Destroy() end
	local bgId = run.card and Theme.DungeonBiomeBackgrounds and Theme.DungeonBiomeBackgrounds[run.card.biome]
	if bgId and bgId ~= "" then
		local bg = Instance.new("ImageLabel")
		bg.Name = "BiomeBg"
		bg.Image = bgId
		bg.ScaleType = Enum.ScaleType.Crop
		bg.Size = UDim2.fromScale(1, 1)
		bg.BackgroundTransparency = 1
		bg.ImageTransparency = 0.15
		bg.ZIndex = 0
		local shade = Instance.new("Frame")
		shade.Name = "Shade"
		shade.Size = UDim2.fromScale(1, 1)
		shade.BackgroundColor3 = Color3.new(0, 0, 0)
		shade.BackgroundTransparency = 0.45
		shade.BorderSizePixel = 0
		shade.ZIndex = 0
		shade.Parent = bg
		bg.Parent = main
	end
	grid.Parent = main -- parent last (NET-004): rooms and paths are added before the grid goes live

	-- Redraw when the width changes (rotate / resize). The connection lives on the grid, which is
	-- destroyed by the next render, so nothing leaks.
	local drawnW = main.AbsoluteSize.X
	grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if math.abs(main.AbsoluteSize.X - drawnW) > 2 then
			drawnW = main.AbsoluteSize.X
			task.defer(render)
		end
	end)

	-- Scroll so the current floor sits in view.
	local focusY = if here then pos[here.id].Y else canvasH
	task.defer(function()
		if grid.Parent then
			grid.CanvasPosition = Vector2.new(0, math.clamp(focusY - grid.AbsoluteSize.Y * 0.6, 0, math.max(0, canvasH - grid.AbsoluteSize.Y)))
		end
	end)
end

return DungeonMapView
