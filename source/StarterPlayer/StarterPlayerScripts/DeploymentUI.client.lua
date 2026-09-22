-- DeploymentUI.client.lua
-- CTRBLXAI | Phase D — Manual Unit Deployment
--
-- Standalone LocalScript. Listens for DeploymentPhase from server,
-- shows PD tile highlights + enemy tokens + unit roster sidebar.
-- Player places each unit on a highlighted tile, then clicks Start Battle.
-- Cleans up all 3D Parts and UI when deployment ends or BattleStarted fires.
--
-- Does NOT depend on BattleVisualClient. BVC handles battle phase;
-- this script handles deployment phase only.

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local BattleEvents = require(
	ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
		:WaitForChild("Remotes", 10):WaitForChild("BattleEvents", 10)
)
local GameConstants = require(
	ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
		:WaitForChild("Shared", 10):WaitForChild("GameConstants", 10)
)
local Theme = require(
	ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
		:WaitForChild("UI", 10):WaitForChild("Theme", 10)
)
local _sbOk, StyleBootstrap = pcall(require,
	ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
		:WaitForChild("Shared", 10):WaitForChild("StyleBootstrap", 10)
)
if not _sbOk then StyleBootstrap = nil end
local _thlOk, TileHL = pcall(require,
	ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
		:WaitForChild("Shared", 10):WaitForChild("TileHighlightManager", 10)
)
if not _thlOk then warn("[DeploymentUI] TileHighlightManager failed: " .. tostring(TileHL)); TileHL = nil end
local CameraController = require(
	player:WaitForChild("PlayerScripts")
		:WaitForChild("CameraController", 10)
)

--------------------------------------------------
-- CONSTANTS (must match BattleVisualClient / MapRenderer)
--------------------------------------------------
local TILE_SIZE        = 5
local TILE_BASE_HEIGHT = 0.6
local ELEVATION_STEP   = 2.5

--------------------------------------------------
-- STATE
--------------------------------------------------
local active         = false
local deployFolder   = nil   -- Folder in workspace for 3D deployment parts
local screenGui      = nil   -- ScreenGui for roster + title + start button
local mapWidth       = 0
local mapHeight      = 0
local MAP_OFFSET_X   = 0
local MAP_OFFSET_Z   = 0

local rosterEntries  = {}    -- array of { id, name, weaponName, deployed, button, stroke, statusLabel }
local selectedUnitId = nil
local pdHighlights   = {}    -- key "x_y" -> Part
local enemyTokens    = {}    -- array of Parts
local playerTokens   = {}    -- unitId -> Part
local startBattleBtn = nil
local inputConn      = nil

--------------------------------------------------
-- HELPERS
--------------------------------------------------
local function tileKey(x, y)
	return x .. "_" .. y
end

local function tileSurfaceY(tx, ty)
	local elev = GameConstants.GetElevation(tx, ty) or 1
	return TILE_BASE_HEIGHT + (elev - 1) * ELEVATION_STEP
end

local function tileToWorld(tx, ty)
	return Vector3.new(
		MAP_OFFSET_X + (tx - 0.5) * TILE_SIZE,
		tileSurfaceY(tx, ty) + 1,
		MAP_OFFSET_Z + (ty - 0.5) * TILE_SIZE
	)
end

--------------------------------------------------
-- CLEANUP
--------------------------------------------------
local function cleanup()
	active = false
	_G.CTRBLXAI_DeploymentActive = false
	if inputConn then inputConn:Disconnect(); inputConn = nil end
	if deployFolder then deployFolder:Destroy(); deployFolder = nil end
	if screenGui then screenGui:Destroy(); screenGui = nil end
	-- Re-enable DevOptions
	local dv = player.PlayerGui:FindFirstChild("DevOptions")
	if dv then dv.Enabled = true end
	if TileHL then TileHL.ClearGroup("deploy") end
	pdHighlights   = {}
	enemyTokens    = {}
	playerTokens   = {}
	rosterEntries  = {}
	selectedUnitId = nil
	startBattleBtn = nil
end

--------------------------------------------------
-- 3D PARTS: PD Tile Highlights
--------------------------------------------------
local function createPDHighlight(tx, ty)
	local key = tileKey(tx, ty)
	if pdHighlights[key] then return end

	if TileHL then
		TileHL.Add(tx, ty, "deploy", "deploy")
		pdHighlights[key] = true  -- track key for removal
	end
end

--------------------------------------------------
-- 3D PARTS: Enemy Tokens (red cylinders with name labels)
--------------------------------------------------
local function createEnemyToken(enemy)
	local part = Instance.new("Part")
	part.Name       = "EnemyDeploy_" .. enemy.id
	part.Shape      = Enum.PartType.Cylinder
	part.Size       = Vector3.new(1.8, 1.8, 1.8)
	part.CFrame     = CFrame.new(tileToWorld(enemy.tileX, enemy.tileY))
						* CFrame.Angles(0, 0, math.rad(90))
	part.Anchored   = true
	part.CanCollide = false
	part.CanQuery   = false
	part.Color      = Theme.Colors.Enemy
	part.Material   = Enum.Material.SmoothPlastic
	part.Parent     = deployFolder

	local bb = Instance.new("BillboardGui")
	bb.Size           = UDim2.new(0, 60, 0, 14)
	bb.StudsOffset    = Vector3.new(0, 1.5, 0)
	bb.AlwaysOnTop    = true
	bb.Parent         = part

	local lbl = Instance.new("TextLabel")
	lbl.Size                 = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3           = Theme.Colors.Enemy
	lbl.TextSize             = Theme.Text.Badge()
	lbl.Font                 = Theme.Font.PrimaryBold
	lbl.TextStrokeTransparency = 0.3
	lbl.Text                 = enemy.name
	lbl.Parent               = bb

	table.insert(enemyTokens, part)
end

--------------------------------------------------
-- 3D PARTS: Player Token (spawned when deployed)
--------------------------------------------------
local function createPlayerToken(unitId, unitName, tx, ty)
	-- If a server-spawned R15 model exists, skip the cylinder placeholder
	local umf = workspace:FindFirstChild("UnitModels")
	if umf and umf:FindFirstChild("Unit_" .. unitId) then
		playerTokens[unitId] = umf:FindFirstChild("Unit_" .. unitId)
		return
	end

	local part = Instance.new("Part")
	part.Name       = "PlayerDeploy_" .. unitId
	part.Shape      = Enum.PartType.Cylinder
	part.Size       = Vector3.new(0.1, 1.8, 1.8)  -- start tiny, tween in
	part.CFrame     = CFrame.new(tileToWorld(tx, ty))
						* CFrame.Angles(0, 0, math.rad(90))
	part.Anchored   = true
	part.CanCollide = false
	part.CanQuery   = false
	part.Color      = Theme.Colors.Player
	part.Material   = Enum.Material.SmoothPlastic
	part.Parent     = deployFolder

	-- Pop-in tween
	TweenService:Create(part, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = Vector3.new(1.8, 1.8, 1.8) }):Play()

	local bb = Instance.new("BillboardGui")
	bb.Size           = UDim2.new(0, 60, 0, 14)
	bb.StudsOffset    = Vector3.new(0, 1.5, 0)
	bb.AlwaysOnTop    = true
	bb.Parent         = part

	local lbl = Instance.new("TextLabel")
	lbl.Size                 = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3           = Theme.Colors.Player
	lbl.TextSize             = Theme.Text.Badge()
	lbl.Font                 = Theme.Font.PrimaryBold
	lbl.TextStrokeTransparency = 0.3
	lbl.Text                 = unitName
	lbl.Parent               = bb

	playerTokens[unitId] = part
end

--------------------------------------------------
-- UNIT SELECTION
--------------------------------------------------
local function selectUnit(unitId)
	selectedUnitId = unitId
	for _, entry in ipairs(rosterEntries) do
		if entry.deployed then
			-- Deployed: keep dimmed, thin border
			entry.stroke.Color = Theme.Colors.Border
			entry.stroke.Thickness = 1
		elseif entry.id == unitId then
			-- Selected: gold highlight
			entry.stroke.Color = Theme.Colors.BorderFocused
			entry.stroke.Thickness = 2
			entry.button.BackgroundTransparency = 0.1
		else
			-- Unselected: default
			entry.stroke.Color = Theme.Colors.Border
			entry.stroke.Thickness = 1
			entry.button.BackgroundTransparency = 0.15
		end
	end
end

local function selectNextUndeployed()
	for _, entry in ipairs(rosterEntries) do
		if not entry.deployed then
			selectUnit(entry.id)
			return
		end
	end
	selectedUnitId = nil
end

--------------------------------------------------
-- START BATTLE BUTTON
--------------------------------------------------
local function showStartBattleButton()
	if startBattleBtn then return end
	if not screenGui then return end

	-- Place the button at the right end of the deploy strip
	local strip = screenGui:FindFirstChild("DeployStrip")
	if not strip then return end

	startBattleBtn = Theme.MakeButton(screenGui, "START BATTLE", "Primary", nil, {
		width = 120,
		height = 40,
	})
	startBattleBtn.Position = UDim2.new(1, -12, 1, -12)
	startBattleBtn.AnchorPoint = Vector2.new(1, 1)

	startBattleBtn.MouseButton1Click:Connect(function()
		active = false
		BattleEvents.DeploymentReady:FireServer({})
		if startBattleBtn then startBattleBtn.Visible = false end
	end)
end

--------------------------------------------------
-- ROSTER UI
--------------------------------------------------
local function createRosterUI(playerUnits)
	screenGui = Instance.new("ScreenGui")
	screenGui.Name               = "DeploymentUI"
	screenGui.ResetOnSpawn       = false
	screenGui.ZIndexBehavior     = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder       = 15
	screenGui.IgnoreGuiInset     = true
	screenGui.Parent             = player.PlayerGui
	if StyleBootstrap and StyleBootstrap.Link then
		StyleBootstrap.Link(screenGui)
	end

	-- Hide DevOptions during deployment; BattleHUD stays for view mode tile inspection
	local devOptsGui = player.PlayerGui:FindFirstChild("DevOptions")
	if devOptsGui then devOptsGui.Enabled = false end

	-- ── Responsive sizing ───────────────────────────────────
	local cam = workspace.CurrentCamera
	local vw = cam and cam.ViewportSize.X or 1366
	local vh = cam and cam.ViewportSize.Y or 768
	if vw <= 0 then vw = 1366 end
	if vh <= 0 then vh = 768 end

	local unitCount = math.min(#playerUnits, 8)
	local cellSize = math.clamp(math.floor(vh * 0.13), 40, 64)
	local cellGap  = math.clamp(math.floor(vw * 0.004), 3, 6)
	local stripPad = 8
	local stripW   = unitCount * cellSize + (unitCount - 1) * cellGap + stripPad * 2
	local stripH   = cellSize + stripPad * 2

	-- ── Deploy strip (ornate frame, bottom-center) ──────────
	local strip = Theme.MakePanel("DeployStrip",
		UDim2.new(0, stripW, 0, stripH),
		nil, nil, screenGui)
	strip.Position    = UDim2.new(0.5, 0, 1, -10)
	strip.AnchorPoint = Vector2.new(0.5, 1)
	strip.ClipsDescendants = true

	local innerPad = Instance.new("UIPadding", strip)
	innerPad.PaddingTop    = UDim.new(0, stripPad)
	innerPad.PaddingBottom = UDim.new(0, stripPad)
	innerPad.PaddingLeft   = UDim.new(0, stripPad)
	innerPad.PaddingRight  = UDim.new(0, stripPad)

	-- Horizontal layout
	local layout = Instance.new("UIListLayout", strip)
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, cellGap)

	-- ── Header (above strip) ────────────────────────────────
	local header = Instance.new("TextLabel")
	header.Name = "DeployHeader"
	header.Size = UDim2.new(0, stripW, 0, 18)
	header.Position = UDim2.new(0.5, 0, 1, -10 - stripH - 4)
	header.AnchorPoint = Vector2.new(0.5, 1)
	header.BackgroundTransparency = 1
	header.Text = "DEPLOY YOUR UNITS"
	header.TextColor3 = Theme.Colors.TextGold
	header.TextSize = Theme.Text.Small()
	header.Font = Theme.Font.PrimaryBold
	header.TextXAlignment = Enum.TextXAlignment.Center
	header.TextStrokeTransparency = 0.4
	header.Parent = screenGui

	-- ── Build unit cells ────────────────────────────────────
	rosterEntries = {}
	for i, unitInfo in ipairs(playerUnits) do
		if i > 8 then break end

		local entry = {
			id         = unitInfo.id,
			name       = unitInfo.name,
			weaponName = unitInfo.weaponName or "Unarmed",
			deployed   = false,
		}

		-- Portrait cell (square)
		local cell = Instance.new("TextButton")
		cell.Name            = "Cell_" .. unitInfo.id
		cell.Size            = UDim2.new(0, cellSize, 0, cellSize)
		cell.LayoutOrder     = i
		cell.BackgroundColor3 = Theme.Colors.Player
		cell.BackgroundTransparency = 0.15
		cell.BorderSizePixel = 0
		cell.Text            = ""
		cell.AutoButtonColor = true
		cell.Parent          = strip
		Instance.new("UICorner", cell).CornerRadius = Theme.CornerRadius.sm

		local cellStroke = Instance.new("UIStroke", cell)
		cellStroke.Color     = Theme.Colors.Border
		cellStroke.Thickness = 1

		-- 2-char initials (centered)
		local initials = Instance.new("TextLabel")
		initials.Name = "Initials"
		initials.Size = UDim2.new(1, 0, 1, -12)
		initials.Position = UDim2.new(0, 0, 0, 0)
		initials.BackgroundTransparency = 1
		initials.Text = string.upper(string.sub(unitInfo.name, 1, 2))
		initials.TextColor3 = Theme.Colors.TextPrimary
		initials.TextSize = math.max(Theme.Text.Body(), math.floor(cellSize * 0.32))
		initials.Font = Theme.Font.PrimaryBold
		initials.TextStrokeTransparency = 0.3
		initials.Parent = cell

		-- Level badge (top-left)
		local lvl = unitInfo.level or 1
		local badge = Instance.new("Frame")
		badge.Name = "LvBadge"
		badge.Size = UDim2.new(0, math.floor(cellSize * 0.5), 0, 11)
		badge.Position = UDim2.new(0, 1, 0, 1)
		badge.BackgroundColor3 = Theme.Colors.BadgeBg
		badge.BackgroundTransparency = 0.25
		badge.BorderSizePixel = 0
		badge.ZIndex = 3
		badge.Parent = cell
		Instance.new("UICorner", badge).CornerRadius = Theme.CornerRadius.xs

		local lvText = Instance.new("TextLabel")
		lvText.Size = UDim2.fromScale(1, 1)
		lvText.BackgroundTransparency = 1
		lvText.Text = "Lv." .. lvl
		lvText.TextColor3 = Theme.Colors.TextPrimary
		lvText.TextSize = Theme.Text.Badge()
		lvText.Font = Theme.Font.Mono
		lvText.ZIndex = 3
		lvText.Parent = badge

		-- Name strip (bottom overlay)
		local nameStrip = Instance.new("Frame")
		nameStrip.Name = "NameStrip"
		nameStrip.Size = UDim2.new(1, 0, 0, 13)
		nameStrip.Position = UDim2.new(0, 0, 1, -13)
		nameStrip.BackgroundColor3 = Theme.Colors.BadgeBg
		nameStrip.BackgroundTransparency = 0.4
		nameStrip.BorderSizePixel = 0
		nameStrip.ZIndex = 3
		nameStrip.Parent = cell

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -4, 1, 0)
		nameLabel.Position = UDim2.new(0, 2, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = unitInfo.name
		nameLabel.TextColor3 = Theme.Colors.TextPrimary
		nameLabel.TextSize = Theme.Text.Badge()
		nameLabel.Font = Theme.Font.PrimaryBold
		nameLabel.TextXAlignment = Enum.TextXAlignment.Center
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.ZIndex = 3
		nameLabel.Parent = nameStrip

		-- Deployed check badge (top-right, hidden until deployed)
		local checkBadge = Instance.new("Frame")
		checkBadge.Name = "CheckBadge"
		checkBadge.Size = UDim2.new(0, 14, 0, 14)
		checkBadge.Position = UDim2.new(1, -15, 0, 1)
		checkBadge.BackgroundColor3 = Theme.Colors.Success
		checkBadge.BackgroundTransparency = 0.2
		checkBadge.BorderSizePixel = 0
		checkBadge.ZIndex = 4
		checkBadge.Visible = false
		checkBadge.Parent = cell
		Instance.new("UICorner", checkBadge).CornerRadius = UDim.new(0.5, 0)

		local checkText = Instance.new("TextLabel")
		checkText.Size = UDim2.fromScale(1, 1)
		checkText.BackgroundTransparency = 1
		checkText.Text = "OK"
		checkText.TextColor3 = Color3.new(1, 1, 1)
		checkText.TextSize = 7
		checkText.Font = Theme.Font.PrimaryBold
		checkText.ZIndex = 4
		checkText.Parent = checkBadge

		entry.button     = cell
		entry.stroke     = cellStroke
		entry.initials   = initials
		entry.nameStrip  = nameStrip
		entry.nameLabel  = nameLabel
		entry.checkBadge = checkBadge

		cell.MouseButton1Click:Connect(function()
			if not active then return end
			if entry.deployed then
				-- Undeploy: remove unit from the tile
				BattleEvents.UndeployUnit:FireServer({ unitId = entry.id })
			else
				selectUnit(entry.id)
			end
		end)

		table.insert(rosterEntries, entry)
	end

	-- Auto-select first unit
	if #rosterEntries > 0 then
		selectUnit(rosterEntries[1].id)
	end
end

--------------------------------------------------
-- MOUSE INPUT: Raycast → find Deploy_ part → fire event
--------------------------------------------------
local function onInputBegan(input, gameProcessed)
	-- DEBUG: log every click so we can see where it bails out
	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return  -- ignore non-click input silently
	end

	print(string.format("[DeploymentUI] Click detected — gameProcessed=%s active=%s selectedUnit=%s deployFolder=%s",
		tostring(gameProcessed), tostring(active), tostring(selectedUnitId),
		tostring(deployFolder and deployFolder.Name or "nil")))

	if gameProcessed then print("[DeploymentUI] BAIL: gameProcessed=true"); return end
	if not active then print("[DeploymentUI] BAIL: not active"); return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	if not selectedUnitId then print("[DeploymentUI] BAIL: no selectedUnitId"); return end
	if not deployFolder then print("[DeploymentUI] BAIL: no deployFolder"); return end

	local camera = workspace.CurrentCamera
	if not camera then print("[DeploymentUI] BAIL: no camera"); return end

	local pos = input.Position
	-- ScreenPointToRay accounts for the GUI inset (topbar); ViewportPointToRay does not.
	local unitRay = camera:ScreenPointToRay(pos.X, pos.Y)

	-- Click-pads first: thin invisible pads coincident with the deploy-tile
	-- highlights. They do not occlude neighbors like the tall terrain boxes,
	-- so the pad hit is the tile the player actually sees under the cursor.
	if TileHL then
		local padFolder = TileHL.GetPadFolder()
		if padFolder then
			local rpp = RaycastParams.new()
			rpp.FilterType = Enum.RaycastFilterType.Include
			rpp.FilterDescendantsInstances = { padFolder }
			local pres = workspace:Raycast(unitRay.Origin, unitRay.Direction * 500, rpp)
			if pres and pres.Instance then
				local px = pres.Instance:GetAttribute("X")
				local py = pres.Instance:GetAttribute("Y")
				if px and py then
					local pkey = px .. "_" .. py
					if pdHighlights[pkey] then
						BattleEvents.DeployUnit:FireServer({ unitId = selectedUnitId, tileX = px, tileY = py })
						return
					end
					print(string.format("[DeploymentUI] pad (%d,%d) not a deploy tile — falling back", px, py))
				end
			end
		end
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	-- Raycast against terrain tiles (thick, reliable) instead of thin overlays
	local mapF = workspace:FindFirstChild("TemplateViewerMap")
	rayParams.FilterDescendantsInstances = mapF and { mapF, deployFolder } or { deployFolder }

	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 500, rayParams)
	if not result or not result.Instance then
		print("[DeploymentUI] BAIL: raycast missed — no hit in deployFolder")
		return
	end

	local hitPart = result.Instance
	print(string.format("[DeploymentUI] Raycast hit: %s", hitPart.Name))

	-- Resolve tile coordinates: Deploy_ parts have TileX/TileY, terrain tiles have X/Y
	local tx = hitPart:GetAttribute("TileX") or hitPart:GetAttribute("X")
	local ty = hitPart:GetAttribute("TileY") or hitPart:GetAttribute("Y")
	if not tx or not ty then return end

	-- Only accept PD-highlighted tiles
	local key = tx .. "_" .. ty
	if not pdHighlights[key] then
		print(string.format("[DeploymentUI] BAIL: tile (%d,%d) is not a deploy tile", tx, ty))
		return
	end

	BattleEvents.DeployUnit:FireServer({
		unitId = selectedUnitId,
		tileX  = tx,
		tileY  = ty,
	})
end

--------------------------------------------------
-- EVENT: DeploymentPhase (server → client)
--------------------------------------------------
BattleEvents.DeploymentPhase.OnClientEvent:Connect(function(data)
	cleanup()
	active = true
	_G.CTRBLXAI_DeploymentActive = true

	-- Hide DevOptions during deployment (BattleHUD stays for view mode)
	local dv = player.PlayerGui:FindFirstChild("DevOptions")
	if dv then dv.Enabled = false end

	mapWidth  = data.mapWidth or 30
	mapHeight = data.mapHeight or 20
	MAP_OFFSET_X = -(mapWidth * TILE_SIZE) / 2
	MAP_OFFSET_Z = -(mapHeight * TILE_SIZE) / 2

	print(string.format("[DeploymentUI] Map dimensions: %dx%d  offsets: X=%.1f Z=%.1f",
		mapWidth, mapHeight, MAP_OFFSET_X, MAP_OFFSET_Z))

	-- Create workspace folder for deployment 3D parts
	deployFolder = Instance.new("Folder")
	deployFolder.Name   = "DeploymentParts"
	deployFolder.Parent = workspace

	-- Ensure TileHL is initialized for this map
	if TileHL and not TileHL.IsAvailable() then
		local mf = workspace:FindFirstChild("TemplateViewerMap")
		if mf then
			local mw = mf:GetAttribute("MapWidth") or 30
			local mh = mf:GetAttribute("MapHeight") or 20
			TileHL.Init({
				mapFolder    = mf,
				tileSize     = TILE_SIZE,
				mapOffsetX   = -(mw * TILE_SIZE) / 2,
				mapOffsetZ   = -(mh * TILE_SIZE) / 2,
				visualFolder = deployFolder,
			})
		end
	end

	-- Create PD tile highlights (blue)
	for _, anchor in ipairs(data.playerAnchors or {}) do
		createPDHighlight(anchor.x, anchor.y)
		local wx = MAP_OFFSET_X + (anchor.x - 0.5) * TILE_SIZE
		local wz = MAP_OFFSET_Z + (anchor.y - 0.5) * TILE_SIZE
		print(string.format("[DeploymentUI]   PD (%d,%d) → world (%.1f, %.1f)  elev=%d",
			anchor.x, anchor.y, wx, wz, GameConstants.GetElevation(anchor.x, anchor.y)))
	end

	-- DIAGNOSTIC: Compare DeploymentUI positions vs actual MapRenderer tile positions
	do
		local mf = workspace:FindFirstChild("TemplateViewerMap")
		if mf then
			print(string.format("[DIAG-POS] MapFolder found: %s (%d children)", mf.Name, #mf:GetChildren()))
			for _, anchor in ipairs(data.playerAnchors or {}) do
				local tileName = string.format("Tile_%02d_%02d", anchor.x, anchor.y)
				local tilePart = mf:FindFirstChild(tileName)
				local deployPart = deployFolder:FindFirstChild("Deploy_" .. anchor.x .. "_" .. anchor.y)
				if tilePart and deployPart then
					print(string.format("[DIAG-POS] Tile(%d,%d) MapRenderer=(%0.1f, %0.1f, %0.1f) Deploy=(%0.1f, %0.1f, %0.1f) DIFF=(%.1f, %.1f, %.1f)",
						anchor.x, anchor.y,
						tilePart.Position.X, tilePart.Position.Y, tilePart.Position.Z,
						deployPart.Position.X, deployPart.Position.Y, deployPart.Position.Z,
						deployPart.Position.X - tilePart.Position.X, deployPart.Position.Y - tilePart.Position.Y, deployPart.Position.Z - tilePart.Position.Z))
				else
					print(string.format("[DIAG-POS] Tile(%d,%d) tilePart=%s deployPart=%s", anchor.x, anchor.y, tostring(tilePart ~= nil), tostring(deployPart ~= nil)))
				end
			end
		else
			print("[DIAG-POS] WARNING: No TemplateViewerMap folder found in workspace!")
		end
	end

	-- Create enemy tokens (red cylinders)
	for _, enemy in ipairs(data.enemyUnits or {}) do
		createEnemyToken(enemy)
	end

	-- Create roster UI
	createRosterUI(data.playerUnits or {})

	-- Set camera to view the battlefield
	-- Focus camera on the PD deployment zone (average of PD anchor positions)
	-- so the player immediately sees where to place units.
	local anchors = data.playerAnchors or {}
	local centerX, centerZ
	if #anchors > 0 then
		local sumX, sumZ = 0, 0
		for _, a in ipairs(anchors) do
			sumX = sumX + (MAP_OFFSET_X + (a.x - 0.5) * TILE_SIZE)
			sumZ = sumZ + (MAP_OFFSET_Z + (a.y - 0.5) * TILE_SIZE)
		end
		centerX = sumX / #anchors
		centerZ = sumZ / #anchors
	else
		centerX = MAP_OFFSET_X + (mapWidth * TILE_SIZE) / 2
		centerZ = MAP_OFFSET_Z + (mapHeight * TILE_SIZE) / 2
	end
	CameraController.SetBattlefieldBounds({
		minX     = MAP_OFFSET_X,
		maxX     = MAP_OFFSET_X + mapWidth * TILE_SIZE,
		minZ     = MAP_OFFSET_Z,
		maxZ     = MAP_OFFSET_Z + mapHeight * TILE_SIZE,
		tileSize = TILE_SIZE,
		source   = "deployment",
	})
	CameraController.EnterBattle(Vector3.new(centerX, 0, centerZ))

	-- Collapse template inspector if open
	if type(_G.CTRBLXAI_SetInspectorCollapsed) == "function" then
		_G.CTRBLXAI_SetInspectorCollapsed(true)
	end

	-- Connect mouse input
	inputConn = UserInputService.InputBegan:Connect(onInputBegan)

	print(string.format("[DeploymentUI] Phase started — %d PD tiles, %d enemies, %d units to place",
		#(data.playerAnchors or {}), #(data.enemyUnits or {}), #(data.playerUnits or {})))
end)

--------------------------------------------------
-- EVENT: UnitDeployed (server → client confirmation)
--------------------------------------------------
BattleEvents.UnitDeployed.OnClientEvent:Connect(function(data)
	if not active then return end
	if not data or not data.unitId then return end

	-- Mark unit as deployed in roster
	local unitName = ""
	for _, entry in ipairs(rosterEntries) do
		if entry.id == data.unitId then
			entry.deployed = true
			-- Dim the cell
			entry.button.BackgroundTransparency = 0.65
			if entry.initials then entry.initials.TextTransparency = 0.5 end
			if entry.nameStrip then entry.nameStrip.BackgroundTransparency = 0.75 end
			if entry.nameLabel then entry.nameLabel.TextTransparency = 0.5 end
			-- Show small check badge (top-right)
			if entry.checkBadge then entry.checkBadge.Visible = true end
			entry.stroke.Color = Theme.Colors.Success
			entry.stroke.Thickness = 1
			entry.button.AutoButtonColor = false
			unitName = entry.name
			break
		end
	end

	-- Spawn player token at deployed position
	if unitName ~= "" then
		createPlayerToken(data.unitId, unitName, data.tileX, data.tileY)
	end

	-- Remove PD tile highlight (tile is now occupied)
	local key = tileKey(data.tileX, data.tileY)
	if pdHighlights[key] then
		if TileHL then TileHL.Remove(data.tileX, data.tileY) end
		pdHighlights[key] = nil
	end

	-- Check if all units deployed
	local allPlaced = true
	for _, entry in ipairs(rosterEntries) do
		if not entry.deployed then
			allPlaced = false
			break
		end
	end

	if allPlaced then
		showStartBattleButton()
		selectedUnitId = nil
		-- Deselect all roster entries
		for _, entry in ipairs(rosterEntries) do
			entry.stroke.Color = Theme.Colors.Border
		end
	else
		selectNextUndeployed()
	end
end)

BattleEvents.UnitUndeployed.OnClientEvent:Connect(function(data)
	if not data or not data.unitId then return end

	-- Restore cell visual state
	for _, entry in ipairs(rosterEntries) do
		if entry.id == data.unitId then
			entry.deployed = false
			entry.button.BackgroundTransparency = 0.15
			entry.button.AutoButtonColor = true
			if entry.initials then entry.initials.TextTransparency = 0 end
			if entry.nameStrip then entry.nameStrip.BackgroundTransparency = 0.4 end
			if entry.nameLabel then entry.nameLabel.TextTransparency = 0 end
			if entry.checkBadge then entry.checkBadge.Visible = false end
			entry.stroke.Color = Theme.Colors.Border
			entry.stroke.Thickness = 1
			break
		end
	end

	-- Remove player token from map
	if playerTokens[data.unitId] then
		-- Only destroy if it's a locally-created cylinder (not server R15 model)
		if playerTokens[data.unitId]:IsA("Part") then
			playerTokens[data.unitId]:Destroy()
		end
		-- Server handles R15 model removal via UnitUndeployed handler
		playerTokens[data.unitId] = nil
	end

	-- Restore PD tile highlight
	if data.tileX and data.tileY then
		createPDHighlight(data.tileX, data.tileY)
	end

	-- Hide Start Battle button (no longer all deployed)
	if startBattleBtn then
		startBattleBtn.Visible = false
		-- Also hide the container
		local container = screenGui and screenGui:FindFirstChild("StartBattleBtnContainer")
		if container then container.Visible = false end
	end
	startBattleBtn = nil

	-- Auto-select the undeployed unit
	selectUnit(data.unitId)

	print(string.format("[DeploymentUI] %s undeployed from (%d,%d)", data.unitId, data.tileX or 0, data.tileY or 0))
end)


--------------------------------------------------
-- EVENT: BattleStarted — clean up deployment UI
-- (BVC takes over with its own token rendering)
--------------------------------------------------
BattleEvents.BattleStarted.OnClientEvent:Connect(function()
	if deployFolder or screenGui then
		cleanup()
	end
end)

print("[CTRBLXAI] DeploymentUI initialized — waiting for DeploymentPhase event")
