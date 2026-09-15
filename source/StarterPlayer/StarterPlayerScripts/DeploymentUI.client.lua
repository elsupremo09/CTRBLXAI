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
	if inputConn then inputConn:Disconnect(); inputConn = nil end
	if deployFolder then deployFolder:Destroy(); deployFolder = nil end
	if screenGui then screenGui:Destroy(); screenGui = nil end
	-- Re-enable BattleHUD (hidden during deployment to avoid timeline overlap)
	local battleHudGui = player.PlayerGui:FindFirstChild("BattleHUD")
	if battleHudGui then battleHudGui.Enabled = true end
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

	local surfaceY = tileSurfaceY(tx, ty) + 0.12

	local p = Instance.new("Part")
	p.Name         = "Deploy_" .. tx .. "_" .. ty
	-- Height must be thick enough for reliable raycast hits at 45° camera.
	-- 1.0 stud is visually acceptable (glowing blue slab) and always hittable.
	p.Size         = Vector3.new(TILE_SIZE * 0.92, 1.0, TILE_SIZE * 0.92)
	p.Position     = Vector3.new(
		MAP_OFFSET_X + (tx - 0.5) * TILE_SIZE,
		surfaceY + 0.5,  -- center of the 1-stud slab sits at surface + 0.5
		MAP_OFFSET_Z + (ty - 0.5) * TILE_SIZE
	)
	p.Anchored     = true
	p.CanCollide   = false
	p.CanQuery     = true
	p.Color        = Theme.Colors.Player      -- Muted blue
	p.Material     = Enum.Material.Neon
	p.Transparency = 0.50
	p:SetAttribute("TileX", tx)
	p:SetAttribute("TileY", ty)
	p.Parent       = deployFolder

	pdHighlights[key] = p
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
		if entry.id == unitId and not entry.deployed then
			entry.stroke.Color = Theme.Colors.BorderSelected
			entry.button.BackgroundColor3 = Theme.Colors.PanelRaised
		else
			entry.stroke.Color = Theme.Colors.Border
			entry.button.BackgroundColor3 = entry.deployed
				and Theme.Colors.Panel or Theme.Colors.Surface
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

	startBattleBtn = Instance.new("TextButton")
	startBattleBtn.Name            = "StartBattleBtn"
	startBattleBtn.Size            = UDim2.new(0, 240, 0, 54)
	startBattleBtn.Position        = UDim2.new(0.5, -120, 1, -80)
	startBattleBtn.BackgroundColor3 = Theme.Colors.Success
	startBattleBtn.Text            = "START BATTLE"
	startBattleBtn.TextColor3      = Theme.Colors.TextPrimary
	startBattleBtn.TextSize        = Theme.Text.Title()
	startBattleBtn.Font            = Theme.Font.Display
	startBattleBtn.BorderSizePixel = 0
	startBattleBtn.AutoButtonColor = true
	startBattleBtn.Parent          = screenGui
	Instance.new("UICorner", startBattleBtn).CornerRadius = UDim.new(0, 8)
	local stroke = Instance.new("UIStroke", startBattleBtn)
	stroke.Color     = Theme.Colors.Success
	stroke.Thickness = 2

	-- Pulse animation
	local pulse = TweenService:Create(startBattleBtn,
		TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ BackgroundColor3 = Theme.Colors.Success })
	pulse:Play()

	startBattleBtn.MouseButton1Click:Connect(function()
		active = false
		BattleEvents.DeploymentReady:FireServer({})
		-- Fade out UI while waiting for BattleStarted
		if startBattleBtn then
			startBattleBtn.Visible = false
		end
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
	screenGui.Parent             = player.PlayerGui
	-- Link StyleSheet tokens
	if StyleBootstrap and StyleBootstrap.Link then
		StyleBootstrap.Link(screenGui)
	end

	-- Title banner
	local title = Instance.new("TextLabel")
	title.Name                 = "Title"
	title.Size                 = UDim2.new(0, 340, 0, 36)
	title.Position             = UDim2.new(0.5, -170, 0, 12)
	title.BackgroundColor3     = Theme.Colors.Panel
	title.BackgroundTransparency = 0.3
	title.Text                 = "⚔  DEPLOY YOUR UNITS  ⚔"
	title.TextColor3           = Theme.Colors.TextGold
	title.TextSize             = Theme.Text.Title()
	title.Font                 = Theme.Font.Display
	title.TextStrokeTransparency = 0.4
	title.BorderSizePixel      = 0
	title.Parent               = screenGui
	Instance.new("UICorner", title).CornerRadius = UDim.new(0, 6)
	local titleStroke = Instance.new("UIStroke", title)
	titleStroke.Color     = Theme.Colors.BorderFocused
	titleStroke.Thickness = 1

	-- Instruction label
	local instruction = Instance.new("TextLabel")
	instruction.Name                 = "Instruction"
	instruction.Size                 = UDim2.new(0, 340, 0, 20)
	instruction.Position             = UDim2.new(0.5, -170, 0, 52)
	instruction.BackgroundTransparency = 1
	instruction.Text                 = "Select a unit, then click a blue tile to place it."
	instruction.TextColor3           = Theme.Colors.TextSecondary
	instruction.TextSize             = Theme.Text.Small()
	instruction.Font                 = Theme.Font.Primary
	instruction.Parent               = screenGui

	-- Roster panel (left side)
	local entryHeight = 54
	local padding     = 8
	local totalHeight = #playerUnits * entryHeight + (#playerUnits - 1) * padding + 2 * padding

	local panel = Instance.new("Frame")
	panel.Name                 = "RosterPanel"
	panel.Size                 = UDim2.new(0, 220, 0, totalHeight)
	panel.Position             = UDim2.new(0, 16, 0.5, 0)
	panel.AnchorPoint          = Vector2.new(0, 0.5)
	panel.BackgroundColor3     = Theme.Colors.Panel
	panel.BackgroundTransparency = 0.12
	panel.BorderSizePixel      = 0
	panel.Parent               = screenGui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 6)
	local panelStroke = Instance.new("UIStroke", panel)
	panelStroke.Color     = Theme.Colors.Border
	panelStroke.Thickness = 1

	rosterEntries = {}
	for i, unitInfo in ipairs(playerUnits) do
		local entry = {
			id         = unitInfo.id,
			name       = unitInfo.name,
			weaponName = unitInfo.weaponName or "Unarmed",
			deployed   = false,
		}

		local btn = Instance.new("TextButton")
		btn.Name            = "Unit_" .. unitInfo.id
		btn.Size            = UDim2.new(1, -2 * padding, 0, entryHeight)
		btn.Position        = UDim2.new(0, padding, 0, padding + (i - 1) * (entryHeight + padding))
		btn.BackgroundColor3 = Theme.Colors.Surface
		btn.BorderSizePixel = 0
		btn.Text            = ""
		btn.AutoButtonColor = false
		btn.Parent          = panel
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
		local btnStroke = Instance.new("UIStroke", btn)
		btnStroke.Color     = Theme.Colors.Border
		btnStroke.Thickness = 1

		-- Side color stripe (left edge)
		local stripe = Instance.new("Frame")
		stripe.Size             = UDim2.new(0, 4, 1, -6)
		stripe.Position         = UDim2.new(0, 3, 0, 3)
		stripe.BackgroundColor3 = Theme.Colors.Player
		stripe.BorderSizePixel  = 0
		stripe.Parent           = btn
		Instance.new("UICorner", stripe).CornerRadius = UDim.new(0, 2)

		-- Unit name
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size                 = UDim2.new(1, -42, 0, 20)
		nameLabel.Position             = UDim2.new(0, 16, 0, 5)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text                 = unitInfo.name
		nameLabel.TextColor3           = Theme.Colors.TextPrimary
		nameLabel.TextSize             = Theme.Text.Body()
		nameLabel.Font                 = Theme.Font.PrimaryBold
		nameLabel.TextXAlignment       = Enum.TextXAlignment.Left
		nameLabel.TextStrokeTransparency = 0.5
		nameLabel.Parent               = btn

		-- Weapon name
		local weaponLabel = Instance.new("TextLabel")
		weaponLabel.Size                 = UDim2.new(1, -42, 0, 16)
		weaponLabel.Position             = UDim2.new(0, 16, 0, 28)
		weaponLabel.BackgroundTransparency = 1
		weaponLabel.Text                 = entry.weaponName
		weaponLabel.TextColor3           = Theme.Colors.TextSecondary
		weaponLabel.TextSize             = Theme.Text.Tiny()
		weaponLabel.Font                 = Theme.Font.Primary
		weaponLabel.TextXAlignment       = Enum.TextXAlignment.Left
		weaponLabel.Parent               = btn

		-- Deploy status indicator (right side)
		local statusLbl = Instance.new("TextLabel")
		statusLbl.Name                 = "Status"
		statusLbl.Size                 = UDim2.new(0, 24, 0, 24)
		statusLbl.Position             = UDim2.new(1, -28, 0.5, -12)
		statusLbl.BackgroundTransparency = 1
		statusLbl.Text                 = ""
		statusLbl.TextColor3           = Theme.Colors.Success
		statusLbl.TextSize             = Theme.Text.Heading()
		statusLbl.Font                 = Theme.Font.PrimaryBold
		statusLbl.Parent               = btn

		entry.button      = btn
		entry.stroke      = btnStroke
		entry.statusLabel = statusLbl

		btn.MouseButton1Click:Connect(function()
			if not entry.deployed and active then
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

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { deployFolder }

	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 500, rayParams)
	if not result or not result.Instance then
		print("[DeploymentUI] BAIL: raycast missed — no hit in deployFolder")
		return
	end

	local hitPart = result.Instance
	print(string.format("[DeploymentUI] Raycast hit: %s", hitPart.Name))
	if hitPart.Name:sub(1, 7) ~= "Deploy_" then print("[DeploymentUI] BAIL: hit part not Deploy_"); return end

	local tx = hitPart:GetAttribute("TileX")
	local ty = hitPart:GetAttribute("TileY")
	if not tx or not ty then return end

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

	-- Hide BattleHUD during deployment — timeline bar overlaps Start Battle button
	local battleHudGui = player.PlayerGui:FindFirstChild("BattleHUD")
	if battleHudGui then battleHudGui.Enabled = false end

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
			entry.statusLabel.Text = "✓"
			entry.button.BackgroundColor3 = Theme.Colors.Panel
			entry.stroke.Color = Theme.Colors.Border
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
		pdHighlights[key]:Destroy()
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
