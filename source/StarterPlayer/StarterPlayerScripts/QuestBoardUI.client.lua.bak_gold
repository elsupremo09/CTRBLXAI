-- QuestBoardUI.lua
-- CTRBLXAI | Phase B — Quest Board Client UI
--
-- Listens for QuestBoardOpen from server, displays 3 quest cards.
-- Player selects one → fires QuestSelected back to server.
-- UI is created once and shown/hidden.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local CTRBLXAI = ReplicatedStorage:WaitForChild("CTRBLXAI", 30)
if not CTRBLXAI then warn("[QuestBoardUI] CTRBLXAI folder not found"); return end

local Theme = require(CTRBLXAI:WaitForChild("UI"):WaitForChild("Theme"))
local _sbOk, StyleBootstrap = pcall(require,
	CTRBLXAI:WaitForChild("Shared", 5):WaitForChild("StyleBootstrap", 5)
)
if not _sbOk then StyleBootstrap = nil end

local BattleEvents = require(
	CTRBLXAI:WaitForChild("Remotes"):WaitForChild("BattleEvents", 10)
)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--------------------------------------------------
-- UI CONSTANTS
--------------------------------------------------

local TITLE_HEIGHT  = 60
local CARD_PADDING  = 14

-- Responsive card sizing: fits 3 cards + gaps within 90% of viewport width
local function computeCardDimensions()
	local cam = workspace.CurrentCamera
	local vs = cam and cam.ViewportSize or Vector2.new(1366, 768)
	local vw = vs.X > 0 and vs.X or 1366
	local vh = vs.Y > 0 and vs.Y or 768
	-- Card width: 90% of viewport / 3 cards, minus gaps, clamped 160-320
	local availW = vw * 0.90
	local gap = math.clamp(math.floor(vw * 0.015), 8, 24)
	local cw = math.clamp(math.floor((availW - gap * 2) / 3), 160, 320)
	-- Card height: aspect ratio ~1.4:1, capped at 60% viewport height
	local maxH = math.max(240, math.floor(vh * 0.60))
	local ch = math.clamp(math.floor(cw * 1.4), 240, maxH)
	return cw, ch, gap
end

local CARD_WIDTH, CARD_HEIGHT, CARD_GAP = computeCardDimensions()

--------------------------------------------------
-- UI CONSTRUCTION (one-time)
--------------------------------------------------

-- ScreenGui
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "QuestBoardScreen"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = Theme.DisplayOrder.Modal
screenGui.IgnoreGuiInset = false
screenGui.Enabled = false
screenGui.Parent = playerGui

-- Link StyleSheet tokens to this ScreenGui
if StyleBootstrap and StyleBootstrap.Link then
	StyleBootstrap.Link(screenGui)
end

-- Viewport change listener: recompute card sizes on resize
local _cam = workspace.CurrentCamera
if _cam then
	_cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		CARD_WIDTH, CARD_HEIGHT, CARD_GAP = computeCardDimensions()
	end)
end

-- Dark overlay (full screen)
local overlay = Instance.new("Frame")
overlay.Name = "Overlay"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Theme.Colors.Background
overlay.BackgroundTransparency = 0.1
overlay.BorderSizePixel = 0
overlay.Parent = screenGui

-- Decorative screen border
Theme.MakeScreenBorder(overlay)

-- Title: "QUEST BOARD"
local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Size = UDim2.new(1, 0, 0, TITLE_HEIGHT)
titleLabel.Position = UDim2.new(0, 0, 0, 20)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Theme.Font.Display
titleLabel.TextSize = math.floor(Theme.Text.Title() * 1.5)
titleLabel.TextColor3 = Theme.Colors.TextGold
titleLabel.Text = "QUEST BOARD"
titleLabel.TextXAlignment = Enum.TextXAlignment.Center
titleLabel.TextYAlignment = Enum.TextYAlignment.Center
titleLabel.Parent = overlay

-- Subtitle
local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.Name = "Subtitle"
subtitleLabel.Size = UDim2.new(1, 0, 0, 24)
subtitleLabel.Position = UDim2.new(0, 0, 0, TITLE_HEIGHT + 20)
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.Font = Theme.Font.Primary
subtitleLabel.TextSize = math.min(Theme.Text.Body(), 14)
subtitleLabel.TextColor3 = Theme.Colors.TextSecondary
subtitleLabel.Text = "Choose a quest to embark on"
subtitleLabel.TextXAlignment = Enum.TextXAlignment.Center
subtitleLabel.Parent = overlay

-- Card container (horizontal row, centered)
local cardContainer = Instance.new("Frame")
cardContainer.Name = "CardContainer"
local totalCardsWidth = CARD_WIDTH * 3 + CARD_GAP * 2
cardContainer.Size = UDim2.new(0, totalCardsWidth, 0, CARD_HEIGHT)
cardContainer.Position = UDim2.new(0.5, 0, 0.5, 10)
cardContainer.AnchorPoint = Vector2.new(0.5, 0.5)
cardContainer.BackgroundTransparency = 1
cardContainer.Parent = overlay

-- UIListLayout for horizontal cards
local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Horizontal
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
listLayout.Padding = UDim.new(0, CARD_GAP)
listLayout.Parent = cardContainer

--------------------------------------------------
-- CARD CREATION HELPERS
--------------------------------------------------

-- Store card frames for reuse
local cardFrames = {}

--- Build difficulty stars string (★★★☆☆)
local function difficultyStars(difficulty)
	local filled = string.rep("★", difficulty)
	local empty  = string.rep("☆", 5 - difficulty)
	return filled .. empty
end

--- Create a text row inside a card
local function makeRow(parent, name, text, opts)
	opts = opts or {}
	local row = Instance.new("TextLabel")
	row.Name = name
	row.Size = UDim2.new(1, -CARD_PADDING * 2, 0, opts.height or 20)
	row.BackgroundTransparency = 1
	row.Font = opts.font or Theme.Font.Primary
	row.TextSize = opts.textSize or Theme.Text.Body()
	row.TextColor3 = opts.color or Theme.Colors.TextPrimary
	row.TextXAlignment = opts.align or Enum.TextXAlignment.Left
	row.TextYAlignment = Enum.TextYAlignment.Center
	row.TextTruncate = Enum.TextTruncate.AtEnd
	row.Text = text
	row.Parent = parent
	return row
end

--- Create one quest card (empty — populated by populateCard)
local function createCardFrame(index)
	-- Outer panel using Theme.MakePanel
	local card = Theme.MakePanel(
		"QuestCard_" .. index,
		UDim2.new(0, CARD_WIDTH, 0, CARD_HEIGHT),
		nil,
		nil,
		cardContainer
	)

	-- Inner padding frame
	local inner = Instance.new("Frame")
	inner.Name = "Inner"
	inner.Size = UDim2.new(1, -CARD_PADDING * 2, 1, -CARD_PADDING * 2)
	inner.Position = UDim2.new(0, CARD_PADDING, 0, CARD_PADDING)
	inner.BackgroundTransparency = 1
	inner.Parent = card

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 4)
	layout.Parent = inner

	-- Quest name (bold, larger)
	local nameLabel = makeRow(inner, "QuestName", "", {
		font = Theme.Font.PrimaryBold,
		textSize = Theme.Text.Body(),
		color = Theme.Colors.TextGold,
		height = 24,
	})

	-- Location (smaller, secondary color)
	local locationLabel = makeRow(inner, "Location", "", {
		textSize = Theme.Text.Small(),
		color = Theme.Colors.TextSecondary,
		height = 18,
	})

	-- Spacer
	local spacer1 = Instance.new("Frame")
	spacer1.Name = "Spacer1"
	spacer1.Size = UDim2.new(1, 0, 0, 6)
	spacer1.BackgroundTransparency = 1
	spacer1.Parent = inner

	-- Biome + difficulty stars row
	local biomeRow = makeRow(inner, "BiomeRow", "", { height = 20 })

	-- Quest type + recommended level row
	local typeRow = makeRow(inner, "TypeRow", "", { height = 20 })

	-- Spacer
	local spacer2 = Instance.new("Frame")
	spacer2.Name = "Spacer2"
	spacer2.Size = UDim2.new(1, 0, 0, 6)
	spacer2.BackgroundTransparency = 1
	spacer2.Parent = inner

	-- Enemy count
	local enemyRow = makeRow(inner, "EnemyRow", "", { height = 20 })

	-- Gold range
	local goldRow = makeRow(inner, "GoldRow", "", { height = 20 })

	-- Drop category
	local dropRow = makeRow(inner, "DropRow", "", { height = 20 })

	-- Spacer
	local spacer3 = Instance.new("Frame")
	spacer3.Name = "Spacer3"
	spacer3.Size = UDim2.new(1, 0, 0, 6)
	spacer3.BackgroundTransparency = 1
	spacer3.Parent = inner

	-- Battle condition
	local conditionRow = makeRow(inner, "ConditionRow", "", { height = 20 })

	-- Deploy units
	local deployRow = makeRow(inner, "DeployRow", "", { height = 20 })

	-- Spacer before button
	local spacer4 = Instance.new("Frame")
	spacer4.Name = "Spacer4"
	spacer4.Size = UDim2.new(1, 0, 0, 8)
	spacer4.BackgroundTransparency = 1
	spacer4.Parent = inner

	-- SELECT button
	local selectBtn = Theme.MakeButton(inner, "Select", "Primary", nil, {
		name = "SelectBtn",
		size = UDim2.new(0.8, 0, 0, 38),
	})

	local cardData = {
		frame = card,
		inner = inner,
		nameLabel = nameLabel,
		locationLabel = locationLabel,
		biomeRow = biomeRow,
		typeRow = typeRow,
		enemyRow = enemyRow,
		goldRow = goldRow,
		dropRow = dropRow,
		conditionRow = conditionRow,
		deployRow = deployRow,
		selectBtn = selectBtn,
		questId = nil,
	}

	cardFrames[index] = cardData
	return cardData
end

--- Populate a card with quest data
local function populateCard(cardData, quest)
	cardData.questId = quest.id

	-- Extract location from name (after "at ")
	local nameText = quest.name
	local location = ""
	local atIdx = string.find(nameText, " at ")
	if atIdx then
		location = "at " .. string.sub(nameText, atIdx + 4)
		nameText = string.sub(nameText, 1, atIdx - 1)
	end

	cardData.nameLabel.Text     = nameText
	cardData.locationLabel.Text = location

	local stars = difficultyStars(quest.difficulty)
	cardData.biomeRow.Text     = quest.biome .. "    " .. stars
	cardData.typeRow.Text      = quest.questType .. "       Lv " .. quest.recommendedLvl

	cardData.enemyRow.Text     = quest.enemyCount .. " enemies"
	cardData.goldRow.Text      = quest.rewards.gold.min .. "–" .. quest.rewards.gold.max .. " gold"
	cardData.dropRow.Text      = quest.rewards.drops .. " drops"

	cardData.conditionRow.Text = quest.condition
	cardData.deployRow.Text    = "Deploy: " .. quest.playerSlots .. " units"
end

--------------------------------------------------
-- CREATE 3 CARD FRAMES
--------------------------------------------------

for i = 1, 3 do
	createCardFrame(i)
end

--------------------------------------------------
-- SHOW / HIDE
--------------------------------------------------

local function show(quests)
	-- Recompute card dimensions in case viewport changed since init
	CARD_WIDTH, CARD_HEIGHT, CARD_GAP = computeCardDimensions()
	local tw = CARD_WIDTH * 3 + CARD_GAP * 2
	cardContainer.Size = UDim2.new(0, tw, 0, CARD_HEIGHT)
	for _, cf in ipairs(cardFrames) do
		cf.frame.Size = UDim2.new(0, CARD_WIDTH, 0, CARD_HEIGHT)
	end
	local ll = cardContainer:FindFirstChildOfClass("UIListLayout")
	if ll then ll.Padding = UDim.new(0, CARD_GAP) end

	-- Populate cards
	for i = 1, 3 do
		if quests[i] then
			populateCard(cardFrames[i], quests[i])
			cardFrames[i].frame.Visible = true
		else
			cardFrames[i].frame.Visible = false
		end
	end

	screenGui.Enabled = true
	print("[QuestBoardUI] Showing quest board with " .. #quests .. " quests")
end

local function hide()
	screenGui.Enabled = false
	print("[QuestBoardUI] Quest board hidden")
end

--------------------------------------------------
-- BUTTON CLICK HANDLERS
--------------------------------------------------

for i = 1, 3 do
	local card = cardFrames[i]
	card.selectBtn.MouseButton1Click:Connect(function()
		if not card.questId then return end
		print("[QuestBoardUI] Selected quest: " .. card.questId)
		BattleEvents.QuestSelected:FireServer({ questId = card.questId })
		hide()
	end)
end

--------------------------------------------------
-- EVENT LISTENER
--------------------------------------------------

BattleEvents.QuestBoardOpen.OnClientEvent:Connect(function(data)
	if data and data.quests then
		show(data.quests)
	else
		warn("[QuestBoardUI] QuestBoardOpen received with no quest data")
	end
end)

print("[CTRBLXAI] QuestBoardUI initialized — waiting for QuestBoardOpen event")
