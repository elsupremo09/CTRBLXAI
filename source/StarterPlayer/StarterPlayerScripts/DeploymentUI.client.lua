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
-- Battle unit-inspector panel + portrait helper, reused during deployment so the
-- deployment inspector behaves exactly like the battle one (user decision 2026-10-15).
local _bhOk, BattleHUD = pcall(require,
	ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
		:WaitForChild("UI", 10):WaitForChild("BattleHUD", 10)
)
if not _bhOk then warn("[DeploymentUI] BattleHUD failed: " .. tostring(BattleHUD)); BattleHUD = nil end
-- Shared portrait-overlay helper (ApplyPortrait) — same one the battle panels use.
local _uicOk, UIComponents = pcall(require,
	ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
		:WaitForChild("UI", 10):WaitForChild("UIComponents", 10)
)
if not _uicOk then warn("[DeploymentUI] UIComponents failed: " .. tostring(UIComponents)); UIComponents = nil end
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
local _trOk, TileResolver = pcall(require,
	ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
		:WaitForChild("Shared", 10):WaitForChild("TileResolver", 10)
)
if not _trOk then warn("[DeploymentUI] TileResolver failed: " .. tostring(TileResolver)); TileResolver = nil end

-- Tier star images (match the in-battle HP-bar star): gold = Elite, silver =
-- Veteran, nothing for Grunts. Shown on the deployment enemy billboard so the
-- player can read enemy tiers while sizing up the fight.
local TIER_STAR_IMAGE = {
	Elite   = "rbxassetid://134634995983546",  -- gold star
	Veteran = "rbxassetid://126540666012445",  -- silver star
}
local CameraController = require(
	player:WaitForChild("PlayerScripts")
		:WaitForChild("CameraController", 10)
)

--------------------------------------------------
-- CONSTANTS (must match BattleVisualClient / MapRenderer)
--------------------------------------------------
local TILE_SIZE        = 5
-- Must match server MapRenderer.ELEVATION_STEP (dev-locked 2026-09-24: 1.2 for the
-- expanded 1–20 elevation scale). Used by tileSurfaceY to seat deployment tile
-- surfaces on the rendered terrain. Keep in sync with server + BattleVisualClient.
local ELEVATION_STEP   = GameConstants.ELEVATION_STEP  -- single source of truth (2026-10-20)

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
-- Max units the player may deploy this battle (quest playerSlots, from the
-- DeploymentPhase payload). The deploy counter shows deployed / this. Falls
-- back to the roster size if the server didn't send it. (2026-10-18)
local deployLimit    = 0
-- Inspector support (2026-10-15): unitId -> compact display data (name/side/level/
-- portrait/weapon/tile). Enemies seeded at phase start (fixed tiles); player units
-- get their tile filled in on deploy and cleared on undeploy. Drives the shared
-- BattleHUD unit panel + the detailed inspector window (server reads allUnitsList).
local deployUnitData = {}    -- unitId -> { id, name, side, level, portraitAssetId, weaponName, tileX, tileY }

--------------------------------------------------
-- HELPERS
--------------------------------------------------
local function tileKey(x, y)
	return x .. "_" .. y
end

-- Update the deployment header's "deployed / max" counter. Counts roster entries
-- currently placed and shows it against deployLimit (quest playerSlots). Called
-- after the roster builds and on every deploy/undeploy. Safe no-op if the header
-- or screenGui isn't up yet. (2026-10-18)
local function updateDeployCounter()
	if not screenGui then return end
	local header = screenGui:FindFirstChild("DeployHeader")
	if not header then return end
	local placed = 0
	for _, entry in ipairs(rosterEntries) do
		if entry.deployed then placed = placed + 1 end
	end
	local maxN = (deployLimit and deployLimit > 0) and deployLimit or #rosterEntries
	header.Text = string.format("DEPLOY YOUR UNITS   %d / %d", placed, maxN)
end

local function tileSurfaceY(tx, ty)
	local elev = GameConstants.GetElevation(tx, ty) or 1
	return GameConstants.TileSurfaceY(elev)
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
	deployUnitData = {}
	-- Tear down the shared unit panel/inspector so nothing lingers into battle.
	if BattleHUD and BattleHUD.Cleanup then pcall(BattleHUD.Cleanup) end
	if _G.CTRBLXAI_CloseInspectorPanel then pcall(_G.CTRBLXAI_CloseInspectorPanel) end
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
-- Shared model lookup for BOTH enemy and player tokens (2026-10-21). The server
-- builds each unit's real model and it may arrive on the client a moment late,
-- so wait briefly for it (and its root) before giving up. Returns the model and
-- its root part, or nil if it never arrives (caller then draws the placeholder
-- cylinder). ONE routine for both sides, so a fix here covers every unit.
local function resolveServerUnitModel(unitId)
	local umf = workspace:FindFirstChild("UnitModels")
	if not umf then return nil end
	local model = umf:WaitForChild("Unit_" .. unitId, 5)
	if not model then return nil end
	local hrp = model.PrimaryPart or model:WaitForChild("HumanoidRootPart", 3)
	if not hrp then return nil end
	return model, hrp
end

local function createEnemyToken(enemy)
	-- If the server already built this enemy's R15 model (it does, during deployment),
	-- reuse it instead of drawing a red cylinder, so deployment shows real models like
	-- battle does. The name/tier label floats over the model via a BillboardGui whose
	-- Adornee is the model's HumanoidRootPart but whose Parent is deployFolder -- so the
	-- existing cleanup() (which Destroys deployFolder) removes the label and leaves the
	-- real model untouched for BattleVisualClient. Mirrors the player token's model reuse.
	-- A race with no model still falls through to the cylinder placeholder below.
	-- Resolve the server model via the shared helper (waits briefly for late
	-- replication). Same routine the player tokens use, so both behave identically.
	local serverModel, modelHrp = resolveServerUnitModel(enemy.id)
	if serverModel and modelHrp then
		-- Breathe during deployment, like battle (random desynced idle on the real model).
		if _G.CTRBLXAI_PlayDeployIdle then _G.CTRBLXAI_PlayDeployIdle(serverModel) end
		local mbb = Instance.new("BillboardGui")
		mbb.Name          = "EnemyDeployLabel_" .. enemy.id
		-- Fit the floating label to the name (2026-11-07: 10px phone badge text spilled out of 68px).
		local mStarW = (enemy.enemyType and TIER_STAR_IMAGE[enemy.enemyType]) and 14 or 0
		mbb.Size          = UDim2.new(0, math.min(160, Theme.BadgeFitW(tostring(enemy.name or ""), Theme.Font.PrimaryBold, 68 - mStarW) + mStarW),
			0, math.max(14, Theme.Text.Badge() + 4))
		mbb.StudsOffset   = Vector3.new(0, 3.2, 0)
		mbb.AlwaysOnTop   = true
		mbb.Adornee       = modelHrp
		mbb.Parent        = deployFolder
		local mTierImg = enemy.enemyType and TIER_STAR_IMAGE[enemy.enemyType] or nil
		local mNameOffsetX = 0
		if mTierImg then
			local star = Instance.new("ImageLabel")
			star.Name = "TierStar"
			star.BackgroundTransparency = 1
			star.AnchorPoint = Vector2.new(0, 0.5)
			star.Position = UDim2.new(0, 0, 0.5, 0)
			star.Size = UDim2.fromOffset(12, 12)
			star.ScaleType = Enum.ScaleType.Fit
			star.Image = mTierImg
			star.ZIndex = 3
			star.Parent = mbb
			mNameOffsetX = 14
		end
		local mlbl = Instance.new("TextLabel")
		mlbl.Size                 = UDim2.new(1, -mNameOffsetX, 1, 0)
		mlbl.Position             = UDim2.new(0, mNameOffsetX, 0, 0)
		mlbl.BackgroundTransparency = 1
		mlbl.TextColor3           = Theme.Colors.Enemy
		mlbl.TextSize             = Theme.Text.Badge()
		mlbl.Font                 = Theme.Font.PrimaryBold
		mlbl.TextStrokeTransparency = 0.3
		mlbl.Text                 = enemy.name
		mlbl.Parent               = mbb
		table.insert(enemyTokens, mbb)
		deployUnitData[enemy.id] = {
			id = enemy.id, name = enemy.name, side = enemy.side or "Enemy",
			level = enemy.level, portraitAssetId = enemy.portraitAssetId,
			weaponName = enemy.weaponName, enemyType = enemy.enemyType,
			tileX = enemy.tileX, tileY = enemy.tileY,
			currentHp = enemy.currentHp, maxHp = enemy.maxHp,
			currentMp = enemy.currentMp, maxMp = enemy.maxMp,
			currentAp = enemy.currentAp, remainingRt = enemy.remainingRt,
			doctrine = enemy.doctrine, race = enemy.race,
		}
		return
	end

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
	-- Fit the floating label to the name (2026-11-07: 10px phone badge text spilled out of 68px).
	local starW = (enemy.enemyType and TIER_STAR_IMAGE[enemy.enemyType]) and 14 or 0
	bb.Size           = UDim2.new(0, math.min(160, Theme.BadgeFitW(tostring(enemy.name or ""), Theme.Font.PrimaryBold, 68 - starW) + starW),
		0, math.max(14, Theme.Text.Badge() + 4))
	bb.StudsOffset    = Vector3.new(0, 1.5, 0)
	bb.AlwaysOnTop    = true
	bb.Parent         = part

	-- Tier star (gold Elite / silver Veteran) to the LEFT of the name. Hidden for
	-- Grunts. Same image assets as the in-battle HP-bar star for consistency.
	local tierImg = enemy.enemyType and TIER_STAR_IMAGE[enemy.enemyType] or nil
	local nameOffsetX = 0
	if tierImg then
		local star = Instance.new("ImageLabel")
		star.Name = "TierStar"
		star.BackgroundTransparency = 1
		star.AnchorPoint = Vector2.new(0, 0.5)
		star.Position = UDim2.new(0, 0, 0.5, 0)
		star.Size = UDim2.fromOffset(12, 12)
		star.ScaleType = Enum.ScaleType.Fit
		star.Image = tierImg
		star.ZIndex = 3
		star.Parent = bb
		nameOffsetX = 14  -- shift the name right so it doesn't overlap the star
	end

	local lbl = Instance.new("TextLabel")
	lbl.Size                 = UDim2.new(1, -nameOffsetX, 1, 0)
	lbl.Position             = UDim2.new(0, nameOffsetX, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3           = Theme.Colors.Enemy
	lbl.TextSize             = Theme.Text.Badge()
	lbl.Font                 = Theme.Font.PrimaryBold
	lbl.TextStrokeTransparency = 0.3
	lbl.Text                 = enemy.name
	lbl.Parent               = bb

	table.insert(enemyTokens, part)
	-- Record enemy display data for the inspector (fixed tile; enemies are pre-placed).
	deployUnitData[enemy.id] = {
		id = enemy.id, name = enemy.name, side = enemy.side or "Enemy",
		level = enemy.level, portraitAssetId = enemy.portraitAssetId,
		weaponName = enemy.weaponName, enemyType = enemy.enemyType,
		tileX = enemy.tileX, tileY = enemy.tileY,
		currentHp = enemy.currentHp, maxHp = enemy.maxHp,
		currentMp = enemy.currentMp, maxMp = enemy.maxMp,
		currentAp = enemy.currentAp, remainingRt = enemy.remainingRt,
		doctrine = enemy.doctrine, race = enemy.race,
	}
end

--------------------------------------------------
-- 3D PARTS: Player Token (spawned when deployed)
--------------------------------------------------
local function createPlayerToken(unitId, unitName, tx, ty)
	-- If a server-spawned R15 model exists, skip the cylinder placeholder
	-- Use the shared lookup (waits briefly for late replication) so player units
	-- get their real model instead of a blue cylinder when it arrives a moment late
	-- -- the same fix enemies already had. (2026-10-21)
	local serverModel = resolveServerUnitModel(unitId)
	if serverModel then
		playerTokens[unitId] = serverModel
		-- Breathe during deployment, like battle (random desynced idle on the real model).
		if _G.CTRBLXAI_PlayDeployIdle then _G.CTRBLXAI_PlayDeployIdle(serverModel) end
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
	-- Fit the floating label to the name (2026-11-07, 10px phone badge text).
	bb.Size           = UDim2.new(0, math.min(160, Theme.BadgeFitW(tostring(unitName or ""), Theme.Font.PrimaryBold, 60)),
		0, math.max(14, Theme.Text.Badge() + 4))
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
			if entry.nameLabel then entry.nameLabel.TextColor3 = Theme.Colors.TextPrimary end
		elseif entry.id == unitId then
			-- Selected: gold highlight
			entry.stroke.Color = Theme.Colors.BorderFocused
			entry.stroke.Thickness = 2
			entry.button.BackgroundTransparency = 0.1
			-- Bold yellow name so the player can see WHICH party unit is currently armed
			-- for placement (the portrait highlight alone was too subtle). Font is already
			-- PrimaryBold, so coloring it gold satisfies "yellow in bold". (2026-10-22)
			if entry.nameLabel then entry.nameLabel.TextColor3 = Theme.Colors.TextGold end
		else
			-- Unselected: default
			entry.stroke.Color = Theme.Colors.Border
			entry.stroke.Thickness = 1
			entry.button.BackgroundTransparency = 0.15
			if entry.nameLabel then entry.nameLabel.TextColor3 = Theme.Colors.TextPrimary end
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

	startBattleBtn.Activated:Connect(function()
		active = false
		BattleEvents.DeploymentReady:FireServer({})
		if startBattleBtn then startBattleBtn.Visible = false end
	end)
end

--------------------------------------------------
-- READINESS (persistent_hp_mp_rules 24, 2026-11-01)
-- Informs only, never blocks deployment. "Low" = below
-- GameConstants.DEPLOY_LOW_RESOURCE_FRACTION of max. KO and empty items cannot
-- occur here today (the base clears KO and refills charges, rules 9/17).
--------------------------------------------------
local function readinessFlags(unitInfo)
	local frac = GameConstants.DEPLOY_LOW_RESOURCE_FRACTION
	local maxHp = tonumber(unitInfo.maxHp) or 0
	local maxMp = tonumber(unitInfo.maxMp) or 0
	local curHp = tonumber(unitInfo.currentHp) or maxHp
	local curMp = tonumber(unitInfo.currentMp) or maxMp
	local lowHp = maxHp > 0 and curHp < maxHp * frac
	local lowMp = maxMp > 0 and curMp < maxMp * frac
	return lowHp, lowMp
end

--------------------------------------------------
-- ROSTER UI
--------------------------------------------------
local function createRosterUI(playerUnits, awayUnits)
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

	-- Dev options panel stays AVAILABLE during deployment (user request) so dev
	-- commands (view mode, regenerate, etc.) can be used while placing units.

	-- ── Responsive sizing ───────────────────────────────────
	local cam = workspace.CurrentCamera
	local vw = cam and cam.ViewportSize.X or 1366
	local vh = cam and cam.ViewportSize.Y or 768
	if vw <= 0 then vw = 1366 end
	if vh <= 0 then vh = 768 end

	-- Slice 6 Guild menu: units away on dispatch / benched are shown greyed out
	-- after the placeable units (display only; never added to rosterEntries).
	awayUnits = awayUnits or {}
	local unitCount = math.max(1, math.min(#playerUnits + #awayUnits, 8))
	local cellSize = math.clamp(math.floor(vh * 0.13), 40, 64)
	local cellGap  = math.clamp(math.floor(vw * 0.004), 3, 6)
	local stripPad = 8
	local stripW   = unitCount * cellSize + (unitCount - 1) * cellGap + stripPad * 2
	local stripH   = cellSize + stripPad * 2

	-- ── Deploy strip (ornate frame, bottom-LEFT — the turn-order bar's spot in battle) ──
	-- Moved from bottom-center to the bar's bottom-left corner (2026-10-23) so the shared
	-- tile inspector can sit flush to its right, exactly as it does beside the bar in battle.
	local strip = Theme.MakePanel("DeployStrip",
		UDim2.new(0, stripW, 0, stripH),
		nil, nil, screenGui)
	strip.Position    = UDim2.new(0, 6, 1, -10)
	strip.AnchorPoint = Vector2.new(0, 1)
	strip.ClipsDescendants = true
	-- Point the shared tile inspector at the strip so it anchors to it during deployment
	-- the same way it anchors to the turn-order bar in battle. (2026-10-23)
	if BattleHUD and BattleHUD.SetTileAnchor then BattleHUD.SetTileAnchor(strip) end

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
	local lowHpCount = 0
	local lowMpCount = 0
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

		-- Unit face overlay (same helper the battle panels use). When the unit has a
		-- portrait, the image fills the cell and the initials are hidden; otherwise the
		-- initials remain. The image sits at cell ZIndex+1 (=2), below the Lv badge and
		-- name strip (ZIndex 3), so those stay readable over the face. (2026-10-15)
		if UIComponents and UIComponents.ApplyPortrait then
			UIComponents.ApplyPortrait(cell, unitInfo.portraitAssetId, initials)
		end

		-- Level badge (top-left)
		local lvl = unitInfo.level or 1
		local badge = Instance.new("Frame")
		badge.Name = "LvBadge"
		-- Sized from the measured "Lv.N" text (2026-11-07): "Lv.10"+ overflowed at the 10px phone size.
		local lvBadgeW = Theme.BadgeFitW("Lv." .. lvl, Theme.Font.Mono, math.floor(cellSize * 0.5))
		local lvBadgeH = math.max(11, Theme.Text.Badge() + 2)
		badge.Size = UDim2.new(0, lvBadgeW, 0, lvBadgeH)
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
		-- Name band hugs the BOTTOM of the portrait (2026-10-23): the earlier 26px two-row
		-- band covered ~half the face. 18px sits low, covering much less, while still giving
		-- a long name room to wrap to a short second line. Face-visibility wins over fitting
		-- two full rows (user ruling 2026-10-23).
		-- 2026-11-07: height = two lines at the current badge text size (+2), never below the
		-- 18px of 2026-10-23. At the 10px phone floor 18px only held ONE line, so two-line names
		-- were cut to one line + "...". Desktop (7px text) keeps 18px.
		local nameStripH = math.max(18, Theme.Text.Badge() * 2 + 2)
		nameStrip.Size = UDim2.new(1, 0, 0, nameStripH)
		nameStrip.Position = UDim2.new(0, 0, 1, -nameStripH)
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
		-- Wrap to the second row before truncating, so two-line names show in full.
		nameLabel.TextWrapped = true
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.ZIndex = 3
		nameLabel.Parent = nameStrip

		-- Deployed check badge (top-right, hidden until deployed)
		local checkBadge = Instance.new("Frame")
		checkBadge.Name = "CheckBadge"
		-- 2026-11-07: a wide "Lv.NN" badge (10px phone text) can reach the top-right check. Then
		-- the check drops to just below the Lv row on the right (12px, above the name band), so
		-- both stay readable and the face is covered no more than before.
		if 1 + lvBadgeW + 1 > cellSize - 15 then
			checkBadge.Size = UDim2.new(0, 12, 0, 12)
			local belowLv = 1 + lvBadgeH + 1
			if belowLv + 12 <= cellSize - nameStripH then
				checkBadge.Position = UDim2.new(1, -13, 0, belowLv)
			else
				-- Tiny cells (40px, viewport height <= 307): no gap above the name band, so the
				-- check sits in the band's right end and the name keeps clear of it.
				checkBadge.Position = UDim2.new(1, -13, 1, -nameStripH + math.floor((nameStripH - 12) / 2))
				nameLabel.Size = UDim2.new(1, -16, 1, 0)
			end
		else
			checkBadge.Size = UDim2.new(0, 14, 0, 14)
			checkBadge.Position = UDim2.new(1, -15, 0, 1)
		end
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

		-- Readiness mark: a low unit's name band turns red. The corners are already used
		-- (Lv badge, deployed check) and cells can be 40 px, so the band carries the mark.
		local lowHp, lowMp = readinessFlags(unitInfo)
		if lowHp then lowHpCount += 1 end
		if lowMp then lowMpCount += 1 end
		if lowHp or lowMp then
			nameStrip.BackgroundColor3 = Theme.Colors.Danger
		end

		entry.button     = cell
		entry.stroke     = cellStroke
		entry.initials   = initials
		entry.nameStrip  = nameStrip
		entry.nameLabel  = nameLabel
		entry.checkBadge = checkBadge
		-- Inspector data for this player unit (tile filled in on deploy). (2026-10-15)
		deployUnitData[unitInfo.id] = {
			id = unitInfo.id, name = unitInfo.name, side = unitInfo.side or "Player",
			level = unitInfo.level, portraitAssetId = unitInfo.portraitAssetId,
			weaponName = unitInfo.weaponName, tileX = nil, tileY = nil,
			currentHp = unitInfo.currentHp, maxHp = unitInfo.maxHp,
			currentMp = unitInfo.currentMp, maxMp = unitInfo.maxMp,
			currentAp = unitInfo.currentAp, remainingRt = unitInfo.remainingRt,
			doctrine = unitInfo.doctrine, race = unitInfo.race,
		}

		cell.Activated:Connect(function()
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

	-- Readiness summary line, above where START BATTLE appears (bottom-right).
	if lowHpCount > 0 or lowMpCount > 0 then
		local parts = {}
		if lowHpCount > 0 then
			table.insert(parts, `{lowHpCount} unit{if lowHpCount == 1 then "" else "s"} low on HP`)
		end
		if lowMpCount > 0 then
			table.insert(parts, `{lowMpCount} unit{if lowMpCount == 1 then "" else "s"} low on MP`)
		end
		local warnLabel = Instance.new("TextLabel")
		warnLabel.Name = "DeployReadiness"
		warnLabel.Size = UDim2.new(0, 260, 0, 16)
		-- START BATTLE renders as a 44x44 icon button at (1,-12,1,-12) (Theme.MakeButton ignores
		-- the width/height passed in), so sit 6 px above its top edge.
		warnLabel.Position = UDim2.new(1, -12, 1, -12 - 44 - 6)
		warnLabel.AnchorPoint = Vector2.new(1, 1)
		warnLabel.BackgroundTransparency = 1
		warnLabel.Text = table.concat(parts, "  |  ")
		warnLabel.TextColor3 = Theme.Colors.Danger
		warnLabel.TextSize = Theme.Text.Small()
		warnLabel.Font = Theme.Font.PrimaryBold
		warnLabel.TextXAlignment = Enum.TextXAlignment.Right
		warnLabel.TextStrokeTransparency = 0.4
		warnLabel.Parent = screenGui
		print(`[DeploymentUI] Readiness: {warnLabel.Text}`)
	end

	-- Greyed, non-interactive cells for units that cannot deploy this battle.
	for j, awayInfo in ipairs(awayUnits) do
		if #playerUnits + j > 8 then break end
		local awayCell = Instance.new("Frame")
		awayCell.Name = "Away_" .. tostring(awayInfo.id)
		awayCell.Size = UDim2.new(0, cellSize, 0, cellSize)
		awayCell.LayoutOrder = #playerUnits + j
		awayCell.BackgroundColor3 = Theme.Colors.Defeated
		awayCell.BackgroundTransparency = 0.3
		awayCell.BorderSizePixel = 0
		Instance.new("UICorner", awayCell).CornerRadius = Theme.CornerRadius.sm
		local awayLabel = Instance.new("TextLabel")
		awayLabel.Size = UDim2.fromScale(1, 1)
		awayLabel.BackgroundTransparency = 1
		awayLabel.Text = string.upper(string.sub(tostring(awayInfo.name), 1, 2)) .. "\n" .. tostring(awayInfo.reason or "AWAY")
		awayLabel.TextColor3 = Theme.Colors.TextDisabled
		awayLabel.TextSize = Theme.Text.Badge()
		awayLabel.Font = Theme.Font.PrimaryBold
		awayLabel.Parent = awayCell
		awayCell.Parent = strip
	end

	-- Auto-select first unit
	if #rosterEntries > 0 then
		selectUnit(rosterEntries[1].id)
	end
end

--------------------------------------------------
-- MOUSE INPUT: Raycast → find Deploy_ part → fire event
--------------------------------------------------
-- (Inspection helpers removed 2026-10-23: unit/object/tile inspection is now owned by
--  BattleVisualClient's shared tap-handler in BOTH phases. DeploymentUI is placement-only.)

local function onInputBegan(input, gameProcessed)
	-- DEBUG: log every click so we can see where it bails out
	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return  -- ignore non-click input silently
	end


	if gameProcessed then return end
	if not active then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	-- INSPECTION IS NOT HANDLED HERE ANYMORE (MERGE 2026-10-23): BattleVisualClient's single
	-- tap-handler now drives unit/object/tile inspection in BOTH phases. DeploymentUI is
	-- placement-only -- it just places the selected unit on a deploy tile below. This removes
	-- the two rival inspect paths that used to fight and wipe the panel.
	if not selectedUnitId then return end
	if not deployFolder then return end

	local camera = workspace.CurrentCamera
	if not camera then return end

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
		return
	end

	local hitPart = result.Instance

	-- Resolve tile coordinates: Deploy_ parts have TileX/TileY, terrain tiles have X/Y
	local tx = hitPart:GetAttribute("TileX") or hitPart:GetAttribute("X")
	local ty = hitPart:GetAttribute("TileY") or hitPart:GetAttribute("Y")
	if not tx or not ty then return end

	-- Deploy path only: inspection is owned by BattleVisualClient now (MERGE 2026-10-23);
	-- this handler only places the selected unit. Only accept PD-highlighted tiles.
	local key = tx .. "_" .. ty
	if not pdHighlights[key] then
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
	-- Max deployable units for this battle (quest playerSlots). Used by the
	-- deploy counter; falls back to roster size in updateDeployCounter if 0.
	deployLimit = tonumber(data.playerDeployLimit) or 0

	-- Dev options panel stays AVAILABLE during deployment (user request).

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


	-- Create enemy tokens (red cylinders)
	-- Per-enemy in task.spawn so each can WaitForChild its (Persistent) server model
	-- without blocking the others or the rest of this handler (camera, roster UI).
	for _, enemy in ipairs(data.enemyUnits or {}) do
		task.spawn(createEnemyToken, enemy)
	end

	-- Create roster UI
	createRosterUI(data.playerUnits or {}, data.awayUnits or {})
	-- Initialize the deploy counter (0 / max) once the roster + header exist.
	updateDeployCounter()

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
		-- in task.spawn so the brief wait for the model never blocks this handler
		task.spawn(createPlayerToken, data.unitId, unitName, data.tileX, data.tileY)
	end
	-- Track the deployed tile for inspect-on-tap.
	if deployUnitData[data.unitId] then
		deployUnitData[data.unitId].tileX = data.tileX
		deployUnitData[data.unitId].tileY = data.tileY
	end

	-- Remove PD tile highlight (tile is now occupied)
	local key = tileKey(data.tileX, data.tileY)
	if pdHighlights[key] then
		if TileHL then TileHL.Remove(data.tileX, data.tileY) end
		pdHighlights[key] = nil
	end

	-- Start Battle is available as soon as ONE unit is deployed (user ruling 2026-10-07).
	showStartBattleButton()
	local allPlaced = true
	for _, entry in ipairs(rosterEntries) do
		if not entry.deployed then
			allPlaced = false
			break
		end
	end

	if allPlaced then
		selectedUnitId = nil
		-- Deselect all roster entries
		for _, entry in ipairs(rosterEntries) do
			entry.stroke.Color = Theme.Colors.Border
			-- Clear the gold selected-name tint too, so no unit looks "armed" when
			-- nothing is selected. (2026-10-22)
			if entry.nameLabel then entry.nameLabel.TextColor3 = Theme.Colors.TextPrimary end
		end
	else
		selectNextUndeployed()
	end
	updateDeployCounter()
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
	-- Clear the tracked tile so the now-empty tile is no longer inspectable there.
	if deployUnitData[data.unitId] then
		deployUnitData[data.unitId].tileX = nil
		deployUnitData[data.unitId].tileY = nil
	end

	-- Hide Start Battle only when NO unit is deployed any more.
	local anyDeployed = false
	for _, entry in ipairs(rosterEntries) do
		if entry.deployed then anyDeployed = true; break end
	end
	if not anyDeployed then
		if startBattleBtn then
			startBattleBtn:Destroy()
			local container = screenGui and screenGui:FindFirstChild("StartBattleBtnContainer")
			if container then container.Visible = false end
		end
		startBattleBtn = nil
	end

	-- Auto-select the undeployed unit
	selectUnit(data.unitId)

	updateDeployCounter()

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
