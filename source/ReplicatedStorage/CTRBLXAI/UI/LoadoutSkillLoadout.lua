--!strict
-- LoadoutSkillLoadout.lua
-- CTRBLXAI | Loadout screen SKILLS tab: the equipped skill loadout table (right column) and the
-- skill-slot / augment-slot / augment-for-slot picker popups.
-- Split out of LoadoutScreen.lua (2026-11-10, ARC-005 file-size split, step 4). Behaviour unchanged.
-- Host state (equipped panel, the one open detail overlay, the one open dropdown) is reached
-- through `ctx` -- no require of LoadoutScreen, so no circular dependency (dependency injection).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CTRBLXAI_UI = ReplicatedStorage:WaitForChild("CTRBLXAI", 10):WaitForChild("UI", 10)
local AugmentCompatibility = require(ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
	:WaitForChild("Shared", 10):WaitForChild("AugmentCompatibility", 10))
local MockData    = require(CTRBLXAI_UI:WaitForChild("MockLoadoutData", 10))
local Theme       = require(CTRBLXAI_UI:WaitForChild("Theme", 10))
local LoadoutSkillUtil = require(CTRBLXAI_UI:WaitForChild("LoadoutSkillUtil", 10))
local TipController: any = nil -- New-player tips (2026-11-19): guarded, a missing module never breaks this screen
do
	local okTip, tipMod = pcall(function() return (require :: any)(CTRBLXAI_UI:WaitForChild("TipController", 10)) end)
	if okTip then TipController = tipMod else warn("[LoadoutSkillLoadout] tips unavailable: " .. tostring(tipMod)) end
end

local LoadoutSkillLoadout: any = {}

local ctx: any = nil
-- Host helpers, bound in Init (thin wrappers so a later reassignment in the host is seen).
local function buildSkillsContent(...) return ctx.buildSkillsContent(...) end
local function clearChildren(...) return ctx.clearChildren(...) end
local function closeDetail(...) return ctx.closeDetail(...) end
local function getPlayerGui(...) return ctx.getPlayerGui(...) end
local function makeLabel(...) return ctx.makeLabel(...) end
local function openEquippedAugmentDetail(...) return ctx.openEquippedAugmentDetail(...) end
local function openEquippedSkillDetail(...) return ctx.openEquippedSkillDetail(...) end
local function openSkillCardDetail(...) return ctx.openSkillCardDetail(...) end
local function pad(...) return ctx.pad(...) end
local STYPE_COLORS = LoadoutSkillUtil.STYPE_COLORS
local STYPE_ICONS = LoadoutSkillUtil.STYPE_ICONS
local getSkillType = LoadoutSkillUtil.GetSkillType

local buildSkillLoadout, openAugmentPickerForSlot, openAugmentSlotPicker, openSkillSlotPicker



-- SKILLS TAB v3 Part 2: Loadout Table + Detail Overlays
-- =====================================================

-- ==================================================================
-- buildSkillLoadout: Renders the skill loadout in equippedPanel
-- ==================================================================
buildSkillLoadout = function()
	if not ctx.getEquippedPanel() then return end
	clearChildren(ctx.getEquippedPanel())
	pad(ctx.getEquippedPanel(), 6, 6, 6, 6)

	local unit = MockData.GetSelectedUnit()
	if not unit then return end

	local loadout = MockData.GetSkillLoadout(unit.id)
	local doctrineId = MockData.GetUnitDoctrineId(unit.id)

	-- (SKILLS / AUGMENTS column headers removed, user ruling 2026-10-08.)

	-- Scrollable slot container (4 slots visible, 5th by scroll)
	local SLOT_H = 50
	local SLOT_GAP = 3
	local AUG_SZ = 22

	local slotScroll = Instance.new("ScrollingFrame")
	slotScroll.Name = "SlotScroll"
	slotScroll.Size = UDim2.new(1, 0, 1, -2)
	slotScroll.Position = UDim2.new(0, 0, 0, 0)
	slotScroll.BackgroundTransparency = 1
	slotScroll.BorderSizePixel = 0
	slotScroll.ScrollBarThickness = 3
	slotScroll.ScrollBarImageColor3 = Theme.Colors.TextSecondary
	slotScroll.CanvasSize = UDim2.new(0, 0, 0, (SLOT_H + SLOT_GAP) * 5)
	slotScroll.ClipsDescendants = true
	slotScroll.Parent = ctx.getEquippedPanel()

	for slot = 1, 5 do
		local _slotData = nil
		local skillId = nil
		local skillName = nil
		local augments = {}

		-- Get slot data from server or mock
		if type(loadout) == "table" and loadout[slot] then
			local sd = loadout[slot]
			if type(sd) == "table" then
				_slotData = sd
				skillId = sd.skillId
				skillName = sd.skillName
				augments = sd.augments or {}
				if skillId == "none" then skillId = nil end
			else
				skillId = sd
				local sk = MockData.GetSkill(skillId)
				if sk then skillName = sk.name end
			end
		end

		local skillDef = skillId and MockData.GetSkillDef(skillId) or nil
		local mockSkill = skillId and MockData.GetSkill(skillId) or nil
		local tags = (skillDef and skillDef.tags) or (mockSkill and mockSkill.tags) or {}
		local name = (skillDef and skillDef.name) or skillName or (mockSkill and mockSkill.name) or nil

		local slotY = (slot - 1) * (SLOT_H + SLOT_GAP)

		-- Row container
		local rowF = Instance.new("Frame")
		rowF.Size = UDim2.new(1, 0, 0, SLOT_H)
		rowF.Position = UDim2.new(0, 0, 0, slotY)
		rowF.BackgroundColor3 = Theme.Colors.PanelRaised
		rowF.BackgroundTransparency = 0.3
		rowF.BorderSizePixel = 0
		rowF.Parent = slotScroll
		Instance.new("UICorner", rowF).CornerRadius = UDim.new(0, 4)

		-- ---- LOCKED SLOT 5 ----
		if slot == 5 then
			rowF.BackgroundTransparency = 0.6
			makeLabel(rowF, { Text = "[L] Locked - Race Evolution",
				Size = UDim2.new(1, -6, 1, 0),
				Position = UDim2.new(0, 3, 0, 0),
				TextSize = Theme.Text.Tiny(),
				TextColor3 = Theme.Colors.TextDisabled })

		elseif name then
			local stype = getSkillType(tags)
			local stc = STYPE_COLORS[stype] or STYPE_COLORS.Utility

			-- Skill icon (square, fills row height minus padding)
			local icoSz = SLOT_H - 4
			local sIco = Instance.new("TextButton")
			sIco.Name = "SkillIcon"
			sIco.Size = UDim2.new(0, icoSz, 0, icoSz)
			sIco.Position = UDim2.new(0, 2, 0, 2)
			sIco.BackgroundColor3 = stc.bg
			sIco.BackgroundTransparency = 0.15
			sIco.BorderSizePixel = 0
			sIco.Text = ""
			sIco.AutoButtonColor = false
			sIco.Parent = rowF
			Instance.new("UICorner", sIco).CornerRadius = UDim.new(0, 4)
			local slotDef = MockData.GetSkillDef(skillId)
			if slotDef and slotDef.icon and slotDef.icon ~= "" then
				local ico = Instance.new("ImageLabel")
				ico.Size = UDim2.new(1, -4, 1, -4)
				ico.Position = UDim2.new(0, 2, 0, 2)
				ico.BackgroundTransparency = 1
				ico.Image = slotDef.icon
				ico.ScaleType = Enum.ScaleType.Fit
				ico.Parent = sIco
			else
				makeLabel(sIco, { Text = STYPE_ICONS[stype] or "[*]",
					Size = UDim2.fromScale(1, 1), TextSize = Theme.Text.Heading(),
					TextColor3 = stc.icon, TextXAlignment = Enum.TextXAlignment.Center })
			end

			-- Click icon -> same detail view as inventory skill cards
			local capturedDef = MockData.GetSkillDef(skillId)
			local capturedMock = MockData.GetSkill(skillId)
			local capturedSk = {
				id = skillId,
				name = name,
				tags = tags,
				mpCost = capturedDef and capturedDef.mpCostFormula or (capturedMock and capturedMock.mpCost) or "?",
				rtCost = capturedDef and capturedDef.rtCostFormula or (capturedMock and capturedMock.rtCost) or "?",
				desc = capturedDef and capturedDef.effects or "",
				qty = 1,
				isSkill = true,
				def = capturedDef,
				mockSkill = capturedMock,
			}
			sIco.Activated:Connect(function()
				-- Equipped skill cards (slots 2-4) open the EQUIPPED detail (has UNEQUIP);
				-- slot 1 is the doctrine-granted skill (not unequippable) and keeps the
				-- read-only card detail. (2026-10-20)
				if slot >= 2 and slot <= 4 and skillId then
					openEquippedSkillDetail(slot, skillId, augments)
				else
					openSkillCardDetail(capturedSk)
				end
			end)

			-- Skill name only (no tags, no MP/RT)
			local nameX = icoSz + 6
			local augArea = (AUG_SZ + 2) * 2 + 4
			local _nameW = UDim2.new(1, -(nameX + augArea), 1, 0)

			if slot == 1 then
				-- Doctrine: name is clickable for dropdown, show "DOCTRINE" subtitle
				local nameBtn = Instance.new("TextButton")
				nameBtn.Size = UDim2.new(1, -(nameX + augArea), 0, SLOT_H - 12)
				nameBtn.Position = UDim2.new(0, nameX, 0, 0)
				nameBtn.BackgroundTransparency = 1
				nameBtn.Text = ""
				nameBtn.Parent = rowF
				makeLabel(nameBtn, { Text = name,
					Size = UDim2.new(1, 0, 0, 16),
					Position = UDim2.new(0, 0, 0, 2),
					Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Small(),
					TextColor3 = Theme.Colors.TextGold })
				makeLabel(nameBtn, { Text = "DOCTRINE v",
					Size = UDim2.new(1, 0, 0, Theme.Text.BadgeLineH()),
					Position = UDim2.new(0, 0, 1, -Theme.Text.BadgeLineH()),
					TextSize = Theme.Text.Badge(), Font = Theme.Font.PrimaryBold,
					TextColor3 = Theme.Colors.TextMuted or Theme.Colors.TextDisabled })

				-- Click name -> doctrine dropdown
				nameBtn.Activated:Connect(function()
					local choices = MockData.GetDoctrineChoices(doctrineId)
					local opts = {}
					for _, cid in ipairs(choices) do
						local cSkill = MockData.GetSkill(cid) or MockData.GetSkillDef(cid)
						if cSkill then
							table.insert(opts, {
								label = cSkill.name,
								value = cid,
								active = (cid == skillId),
							})
						end
					end
					if ctx.getActiveDropdown() then ctx.getActiveDropdown():Destroy(); ctx.setActiveDropdown(nil) end
					local function closeDD()
						if ctx.getActiveDropdown() then ctx.getActiveDropdown():Destroy(); ctx.setActiveDropdown(nil) end
					end
					local rowH2 = 24
					local menuH = #opts * rowH2 + 4
					ctx.setActiveDropdown(Instance.new("ScreenGui"))
					ctx.getActiveDropdown().Name = "DoctrineDropdown"
					ctx.getActiveDropdown().DisplayOrder = 105
					ctx.getActiveDropdown().ResetOnSpawn = false
					ctx.getActiveDropdown().Parent = getPlayerGui()
					local ddBack = Instance.new("TextButton")
					ddBack.Size = UDim2.fromScale(1, 1)
					ddBack.BackgroundTransparency = 1
					ddBack.Text = ""
					ddBack.Parent = ctx.getActiveDropdown()
					ddBack.Activated:Connect(closeDD)
					local mPanel = Instance.new("Frame")
					mPanel.Size = UDim2.new(0, 140, 0, menuH)
					mPanel.Position = UDim2.new(0,
						rowF.AbsolutePosition.X + icoSz + 4,
						0, rowF.AbsolutePosition.Y + rowF.AbsoluteSize.Y + 2)
					mPanel.BackgroundColor3 = Theme.Colors.Panel
					mPanel.BorderSizePixel = 0
					mPanel.ZIndex = 50
					mPanel.Parent = ctx.getActiveDropdown()
					Instance.new("UICorner", mPanel).CornerRadius = UDim.new(0, 4)
					Instance.new("UIStroke", mPanel).Color = Theme.Colors.Border
					pad(mPanel, 2, 2, 2, 2)
					local mLayout = Instance.new("UIListLayout", mPanel)
					mLayout.Padding = UDim.new(0, 0)
					mLayout.SortOrder = Enum.SortOrder.LayoutOrder
					for idx, opt in ipairs(opts) do
						local mRow = Instance.new("TextButton")
						mRow.Size = UDim2.new(1, 0, 0, rowH2)
						mRow.BackgroundColor3 = Theme.Colors.PanelRaised
						mRow.BackgroundTransparency = opt.active and 0.2 or 0.6
						mRow.Font = Theme.Font.Primary
						mRow.TextSize = Theme.Text.Small()
						mRow.TextColor3 = opt.active and Theme.Colors.TextGold or Theme.Colors.TextPrimary
						mRow.Text = opt.label
						mRow.BorderSizePixel = 0
						mRow.LayoutOrder = idx
						mRow.ZIndex = 51
						mRow.Parent = mPanel
						Instance.new("UICorner", mRow).CornerRadius = UDim.new(0, 3)
						mRow.Activated:Connect(function()
							closeDD()
							if MockData.ServerSelectDoctrineSkill then
								MockData.ServerSelectDoctrineSkill(unit.id, opt.value)
							else
								local sl = MockData.SkillLoadout[unit.id]
								if sl then sl[1] = opt.value end
							end
							MockData.LoadSkillData(unit.id)
							buildSkillsContent()
						end)
					end
				end)
			else
				-- Slots 2-4: just show full name
				makeLabel(rowF, { Text = name,
					Size = UDim2.new(1, -(nameX + augArea), 1, 0),
					Position = UDim2.new(0, nameX, 0, 0),
					Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Small(),
					TextColor3 = Theme.Colors.TextPrimary })
			end

			-- Augment icon slots (right side, 2 small squares)
			-- An equipped augment that no longer fits (e.g. after a weapon swap) is dimmed; it does
			-- nothing in battle until swapped (tags-only rule, 2026-10-26). Its detail says why.
			local slotWeapon = MockData.GetWeaponProfile(unit.id)
			for a = 1, 2 do
				local augId = augments[a]
				local augDef = augId and MockData.GetAugmentDef(augId)
				local augActive = (not augDef) or (AugmentCompatibility.Check(skillId, augId, slotWeapon)
					and not (a == 2 and AugmentCompatibility.ConflictsWith(augId, augments[1])))

				local augBtn = Instance.new("TextButton")
				augBtn.Size = UDim2.new(0, AUG_SZ, 0, AUG_SZ)
				augBtn.Position = UDim2.new(1, -(AUG_SZ + 2) * (3 - a), 0, (SLOT_H - AUG_SZ) / 2)
				augBtn.BackgroundColor3 = augDef and Color3.fromRGB(74, 53, 16) or Theme.Colors.Surface
				augBtn.BackgroundTransparency = (augDef and augActive) and 0.3 or 0.6
				augBtn.BorderSizePixel = 0
				augBtn.Text = ""
				augBtn.Parent = rowF
				Instance.new("UICorner", augBtn).CornerRadius = UDim.new(0, 3)

				if augDef then
					-- Show icon image or fallback
					if augDef.icon and augDef.icon ~= "" then
						local ico = Instance.new("ImageLabel")
						ico.Size = UDim2.new(1, -2, 1, -2)
						ico.Position = UDim2.new(0, 1, 0, 1)
						ico.BackgroundTransparency = 1
						ico.Image = augDef.icon
						ico.ImageTransparency = augActive and 0 or 0.6
						ico.ScaleType = Enum.ScaleType.Fit
						ico.Parent = augBtn
					else
						makeLabel(augBtn, { Text = "[o]",
							Size = UDim2.fromScale(1, 1),
							TextSize = Theme.Text.Body(), TextColor3 = Theme.Colors.TextGold,
							TextXAlignment = Enum.TextXAlignment.Center })
					end

					local cSlot = slot
					local cAug = a
					augBtn.Activated:Connect(function()
						openEquippedAugmentDetail(cSlot, cAug, augId)
					end)
				elseif a == 2 and not (MockData.Slot2Open or {})[unit.id] then
					-- Locked 2nd slot (2026-11-04): padlock look, tap shows the approved reason.
					makeLabel(augBtn, { Text = "X",
						Size = UDim2.fromScale(1, 1),
						TextSize = Theme.Text.Tiny(), TextColor3 = Theme.Colors.TextDisabled,
						TextXAlignment = Enum.TextXAlignment.Center })
					-- Tap shows the approved locked-slot text in the augment picker's locked row.
					local cSlot2 = slot
					augBtn.Activated:Connect(function()
						openAugmentPickerForSlot(unit.id, cSlot2, 2)
					end)
				else
					-- Empty augment slot — click opens augment card inventory detail
					makeLabel(augBtn, { Text = "+",
						Size = UDim2.fromScale(1, 1),
						TextSize = Theme.Text.Tiny(), TextColor3 = Theme.Colors.TextDisabled,
						TextXAlignment = Enum.TextXAlignment.Center })
					local cSlot = slot
					local cAug = a
					augBtn.Activated:Connect(function()
						-- Open a picker showing all augment cards to attach to this specific slot
						openAugmentPickerForSlot(unit.id, cSlot, cAug)
					end)
				end
			end

		else
			-- Empty skill slot
			makeLabel(rowF, { Text = "- Empty -",
				Size = UDim2.new(1, -6, 1, 0),
				Position = UDim2.new(0, 3, 0, 0),
				TextSize = Theme.Text.Small(),
				TextColor3 = Theme.Colors.TextDisabled })
		end
	end

end


-- ==================================================================
-- openSkillSlotPicker: Modal popup to choose which slot to equip to
-- ==================================================================
openSkillSlotPicker = function(sk)
	closeDetail()
	local unit = MockData.GetSelectedUnit()
	if not unit then return end
	local loadout = MockData.GetSkillLoadout(unit.id)

	local detailOverlay = Instance.new("ScreenGui"); ctx.setDetailOverlay(detailOverlay)
	detailOverlay.Name = "SlotPickerOverlay"
	detailOverlay.DisplayOrder = 115
	detailOverlay.ResetOnSpawn = false
	detailOverlay.Parent = getPlayerGui()

	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.Overlay
	backdrop.BackgroundTransparency = 0.5
	backdrop.Text = ""
	backdrop.BorderSizePixel = 0
	backdrop.Parent = detailOverlay
	backdrop.Activated:Connect(closeDetail)

	local popup = Theme.MakePanel("SlotPicker",
		UDim2.new(0, 280, 0, 240),
		UDim2.new(0.5, 0, 0.5, 0),
		Vector2.new(0.5, 0.5),
		detailOverlay)
	popup.ClipsDescendants = true
	pad(popup, 10, 10, 10, 10)

	makeLabel(popup, { Text = "> Equip " .. (sk.name or "?") .. " to:",
		Size = UDim2.new(1, 0, 0, 18),
		Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Body(),
		TextColor3 = Theme.Colors.TextPrimary })

	local rowY = 24
	for slot = 1, 5 do
		local disabled = false
		local slotLabel = "Slot " .. slot
		local occupant = "Empty"
		local slotColor = Theme.Colors.Player

		if slot == 1 then
			disabled = true
			slotLabel = "Doctrine Slot"
			occupant = "Doctrine only"
			slotColor = Theme.Colors.TextGold
		elseif slot == 5 then
			disabled = true
			slotLabel = "Slot 5"
			occupant = "Locked - Race Evolution"
			slotColor = Theme.Colors.TextDisabled
		else
			-- Check current occupant
			local sd = type(loadout) == "table" and loadout[slot]
			if sd then
				local occName
				if type(sd) == "table" then
					occName = sd.skillName
					if occName == "none" then occName = nil end
				else
					local ms = MockData.GetSkill(sd) or MockData.GetSkillDef(sd)
					if ms then occName = ms.name end
				end
				if occName then
					occupant = "Replace: " .. occName
				end
			end
		end

		local rowBtn = Instance.new("TextButton")
		rowBtn.Size = UDim2.new(1, 0, 0, 32)
		rowBtn.Position = UDim2.new(0, 0, 0, rowY)
		rowBtn.BackgroundColor3 = Theme.Colors.PanelRaised
		rowBtn.BackgroundTransparency = disabled and 0.6 or 0.2
		rowBtn.BorderSizePixel = 0
		rowBtn.Text = ""
		rowBtn.AutoButtonColor = not disabled
		rowBtn.Parent = popup
		Instance.new("UICorner", rowBtn).CornerRadius = UDim.new(0, 4)

		-- Badge
		local bF = Instance.new("Frame")
		bF.Size = UDim2.new(0, 20, 0, 20)
		bF.Position = UDim2.new(0, 6, 0.5, -10)
		bF.BackgroundColor3 = slotColor
		bF.BackgroundTransparency = disabled and 0.5 or 0
		bF.BorderSizePixel = 0
		bF.Parent = rowBtn
		Instance.new("UICorner", bF).CornerRadius = UDim.new(0.5, 0)
		makeLabel(bF, { Text = tostring(slot), Size = UDim2.fromScale(1, 1),
			TextSize = Theme.Text.Small(), Font = Theme.Font.PrimaryBold,
			TextColor3 = Color3.fromRGB(13, 15, 20),
			TextXAlignment = Enum.TextXAlignment.Center })

		makeLabel(rowBtn, { Text = slotLabel,
			Size = UDim2.new(0.4, -30, 1, 0),
			Position = UDim2.new(0, 32, 0, 0),
			Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Small(),
			TextColor3 = disabled and Theme.Colors.TextDisabled or Theme.Colors.TextPrimary })
		makeLabel(rowBtn, { Text = occupant,
			Size = UDim2.new(0.5, 0, 1, 0),
			Position = UDim2.new(0.48, 0, 0, 0),
			TextSize = Theme.Text.Tiny(),
			TextColor3 = disabled and Theme.Colors.TextDisabled or Theme.Colors.Warning,
			TextXAlignment = Enum.TextXAlignment.Right })

		if not disabled then
			local capturedSlot = slot
			rowBtn.Activated:Connect(function()
				closeDetail()
				-- Equip: server auto-handles unequip of existing + augment return
				if MockData.ServerEquipSkillCard then
					MockData.ServerEquipSkillCard(unit.id, capturedSlot, sk.id)
				else
					local sl = MockData.SkillLoadout[unit.id]
					if sl then sl[capturedSlot] = sk.id end
				end
				MockData.LoadSkillData(unit.id)
				buildSkillsContent()
			end)
		end

		rowY = rowY + 36
	end

	-- Cancel
	Theme.MakeIconButton(popup, "Back", closeDetail, {
		name = "Btn_Cancel",
		size = UDim2.new(0, 18, 0, 18),
		position = UDim2.new(0.5, 0, 1, -20),
		anchor = Vector2.new(0.5, 0),
	})
end

-- ==================================================================
-- openAugmentPickerForSlot: Show available augment cards to attach to a specific slot
-- Called when clicking an empty "+" augment slot in the loadout table
openAugmentPickerForSlot = function(unitId, slotNum, augSlotNum)
	closeDetail()
	local unit = MockData.GetSelectedUnit()
	if not unit then return end

	-- Bug-2 reverse-picker fix (2026-10-23): this picker lists augments FOR a chosen
	-- skill slot. Resolve that slot's skill tags so incompatible augments are greyed out
	-- here, instead of looking valid and silently failing on the server attach gate.
	-- Same " OR "-aware match as the server and the slot-picker direction.
	local slotLoadout = MockData.GetSkillLoadout(unitId)
	local slotSkillId = nil
	local slotAugs = {}  -- this skill's equipped augments (conflict rule, 2026-10-28)
	do
		local sd = type(slotLoadout) == "table" and slotLoadout[slotNum]
		if type(sd) == "table" then
			slotSkillId = sd.skillId
			slotAugs = sd.augments or {}
			if slotSkillId == "none" then slotSkillId = nil end
		elseif sd then
			slotSkillId = sd
		end
	end
	-- Shared tags-only rule (2026-10-26), resolved against this unit's equipped weapon.
	local slotWeapon = MockData.GetWeaponProfile(unitId)

	-- Build list of available augment cards
	local augCards = {}
	if MockData.AugmentCardInventory then
		for augId, qty in pairs(MockData.AugmentCardInventory) do
			if qty and qty > 0 then
				local def = MockData.GetAugmentDef(augId)
				if def then
					table.insert(augCards, { id = augId, name = def.name or augId, qty = qty, def = def })
				end
			end
		end
	end
	table.sort(augCards, function(a, b) return a.name < b.name end)

	local slot2Locked = augSlotNum == 2 and not (MockData.Slot2Open or {})[unitId]
	if #augCards == 0 and not slot2Locked then return end

	local detailOverlay = Instance.new("ScreenGui"); ctx.setDetailOverlay(detailOverlay)
	detailOverlay.Name = "AugPickerForSlot"
	detailOverlay.DisplayOrder = 115
	detailOverlay.ResetOnSpawn = false
	detailOverlay.Parent = getPlayerGui()

	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.Overlay
	backdrop.BackgroundTransparency = 0.5
	backdrop.Text = ""
	backdrop.BorderSizePixel = 0
	backdrop.Parent = detailOverlay
	backdrop.Activated:Connect(closeDetail)

	local popup = Theme.MakePanel("AugPickerForSlot",
		UDim2.new(0, 280, 0, 300),
		UDim2.new(0.5, 0, 0.5, 0),
		Vector2.new(0.5, 0.5),
		detailOverlay)
	popup.ClipsDescendants = true
	pad(popup, 10, 10, 10, 10)

	makeLabel(popup, { Text = "Attach augment to Slot " .. slotNum .. " Aug " .. augSlotNum .. ":",
		Size = UDim2.new(1, 0, 0, 18),
		Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Body(),
		TextColor3 = Theme.Colors.TextGold })
	-- Locked 2nd slot (2026-11-04): show only the approved reason, no augment list.
	if augSlotNum == 2 and not (MockData.Slot2Open or {})[unitId] then
		if TipController then TipController.Trigger("TIP-LOCK-01") end -- new-player tip (locked slot tap)
		makeLabel(popup, { Text = tostring(MockData.Slot2LockedText or "Locked"),
			Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, 24),
			TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextSecondary, TextWrapped = true })
		Theme.MakeIconButton(popup, "Back", closeDetail, {
			name = "Btn_Cancel", size = UDim2.new(0, 18, 0, 18),
		})
		return
	end

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, 0, 1, -44)
	scroll.Position = UDim2.new(0, 0, 0, 22)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 3
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = popup

	local sLayout = Instance.new("UIListLayout", scroll)
	sLayout.Padding = UDim.new(0, 3)
	sLayout.SortOrder = Enum.SortOrder.LayoutOrder

	for idx, ac in ipairs(augCards) do
		local fits, missingTags = AugmentCompatibility.Check(slotSkillId, ac.id, slotWeapon)
		-- Conflict rule (2026-10-28): can't share this skill with its other augment.
		local clashId = fits and AugmentCompatibility.FindConflict(ac.id, slotAugs, augSlotNum) or nil
		if clashId then
			fits = false
			local clashDef = MockData.GetAugmentDef(clashId)
			missingTags = {}
			ac.clashText = "Conflicts with " .. ((clashDef and clashDef.name) or clashId)
		else
			ac.clashText = nil
		end
		local rowBtn = Instance.new("TextButton")
		rowBtn.Size = UDim2.new(1, 0, 0, 28)
		rowBtn.BackgroundColor3 = Theme.Colors.PanelRaised
		rowBtn.BackgroundTransparency = fits and 0.2 or 0.6
		rowBtn.BorderSizePixel = 0
		rowBtn.Text = ""
		rowBtn.AutoButtonColor = fits
		rowBtn.LayoutOrder = idx
		rowBtn.Parent = scroll
		Instance.new("UICorner", rowBtn).CornerRadius = UDim.new(0, 4)

		-- Icon
		if ac.def and ac.def.icon and ac.def.icon ~= "" then
			local ico = Instance.new("ImageLabel")
			ico.Size = UDim2.new(0, 22, 0, 22)
			ico.Position = UDim2.new(0, 3, 0, 3)
			ico.BackgroundTransparency = 1
			ico.Image = ac.def.icon
			ico.ScaleType = Enum.ScaleType.Fit
			ico.Parent = rowBtn
		end

		makeLabel(rowBtn, { Text = ac.name,
			Size = UDim2.new(1, -128, 1, 0),
			Position = UDim2.new(0, 28, 0, 0),
			Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Small(),
			TextColor3 = fits and Theme.Colors.TextPrimary or Theme.Colors.TextDisabled })

		if fits then
			makeLabel(rowBtn, { Text = "x" .. ac.qty,
				Size = UDim2.new(0, 24, 1, 0),
				Position = UDim2.new(1, -26, 0, 0),
				TextSize = Theme.Text.Badge(), Font = Theme.Font.Mono,
				TextColor3 = Theme.Colors.TextSecondary,
				TextXAlignment = Enum.TextXAlignment.Right })
		else
			-- Say exactly which card tag the skill is missing (players see why, no hidden rules).
			local whyText = ac.clashText or ((#missingTags > 0) and ("Needs " .. table.concat(missingTags, ", ")))
				or "No skill equipped"
			makeLabel(rowBtn, { Text = whyText,
				Size = UDim2.new(0, 98, 1, 0),
				Position = UDim2.new(1, -100, 0, 0),
				TextSize = Theme.Text.Badge(), Font = Theme.Font.Primary,
				TextColor3 = Theme.Colors.TextDisabled,
				TextXAlignment = Enum.TextXAlignment.Right })
		end

		if fits then
			rowBtn.Activated:Connect(function()
				closeDetail()
				if MockData.ServerAttachAugment then
					local res = MockData.ServerAttachAugment(unitId, slotNum, augSlotNum, ac.id)
					if type(res) == "table" and res.ok == false then
						warn("[Loadout] Attach refused: " .. tostring(res.reason))
					end
				end
				MockData.LoadSkillData(unitId)
				buildSkillsContent()
			end)
		end
	end

	Theme.MakeIconButton(popup, "Back", closeDetail, {
		name = "Btn_Cancel",
		size = UDim2.new(0, 18, 0, 18),
		position = UDim2.new(0.5, 0, 1, -20),
		anchor = Vector2.new(0.5, 0),
	})
end

-- openAugmentSlotPicker: Show all 10 augment slots to choose from
-- ==================================================================
openAugmentSlotPicker = function(aug)
	closeDetail()
	local unit = MockData.GetSelectedUnit()
	if not unit then return end
	local loadout = MockData.GetSkillLoadout(unit.id)
	-- Bug-2 fix (2026-10-23): compatibility is checked UP FRONT so incompatible skill
	-- slots are greyed out here, instead of looking valid and silently failing on the
	-- server attach gate. Uses the same " OR "-aware match as the server.
	-- Shared tags-only rule (2026-10-26), resolved against this unit's equipped weapon.
	local pickerWeapon = MockData.GetWeaponProfile(unit.id)

	local detailOverlay = Instance.new("ScreenGui"); ctx.setDetailOverlay(detailOverlay)
	detailOverlay.Name = "AugSlotPickerOverlay"
	detailOverlay.DisplayOrder = 115
	detailOverlay.ResetOnSpawn = false
	detailOverlay.Parent = getPlayerGui()

	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.Overlay
	backdrop.BackgroundTransparency = 0.5
	backdrop.Text = ""
	backdrop.BorderSizePixel = 0
	backdrop.Parent = detailOverlay
	backdrop.Activated:Connect(closeDetail)

	local popup = Theme.MakePanel("AugSlotPicker",
		UDim2.new(0, 320, 0, 360),
		UDim2.new(0.5, 0, 0.5, 0),
		Vector2.new(0.5, 0.5),
		detailOverlay)
	popup.ClipsDescendants = true
	pad(popup, 10, 10, 10, 10)

	makeLabel(popup, { Text = "[o] Attach " .. (aug.name or "?") .. " to:",
		Size = UDim2.new(1, 0, 0, 18),
		Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Body(),
		TextColor3 = Theme.Colors.TextGold })

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, 0, 1, -44)
	scroll.Position = UDim2.new(0, 0, 0, 22)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 3
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = popup

	local sLayout = Instance.new("UIListLayout", scroll)
	sLayout.Padding = UDim.new(0, 3)
	sLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local rowOrder = 0

	for slot = 1, 5 do
		local sd = type(loadout) == "table" and loadout[slot]
		local skillName = nil
		local skillId = nil
		local augments = {}
		local disabled = (slot == 5)
		local disabledReason = nil

		if sd then
			if type(sd) == "table" then
				skillName = sd.skillName
				if skillName == "none" then skillName = nil end
				skillId = sd.skillId
				if skillId == "none" then skillId = nil end
				augments = sd.augments or {}
			else
				skillId = sd
				local ms = MockData.GetSkill(sd) or MockData.GetSkillDef(sd)
				if ms then skillName = ms.name end
			end
		end

		if slot == 5 then
			disabled = true; disabledReason = "Locked"
		elseif not skillName then
			disabled = true; disabledReason = "No skill equipped"
		else
			-- Skill present but missing a required card tag: say which one (no hidden rules).
			local fitsSkill, missingTags = AugmentCompatibility.Check(skillId, aug.id, pickerWeapon)
			if not fitsSkill then
				disabled = true
				disabledReason = "Needs " .. table.concat(missingTags, ", ")
			end
		end

		for augSlot = 1, 2 do
			local existingAug = augments[augSlot]
			local existingDef = existingAug and MockData.GetAugmentDef(existingAug)
			-- Conflict rule (2026-10-28): this row is off if the skill's OTHER augment conflicts.
			local slotDisabled, slotReason = disabled, disabledReason
			if not slotDisabled and augSlot == 2 and not (MockData.Slot2Open or {})[unit.id] then
				slotDisabled = true
				slotReason = MockData.Slot2LockedText or "Locked"
			end
			if not slotDisabled then
				local clashId = AugmentCompatibility.FindConflict(aug.id, augments, augSlot)
				if clashId then
					local clashDef = MockData.GetAugmentDef(clashId)
					slotDisabled = true
					slotReason = "Conflicts with " .. ((clashDef and clashDef.name) or clashId)
				end
			end
			local rowDisabled, rowDisabledReason = slotDisabled, slotReason

			local rowBtn = Instance.new("TextButton")
			rowBtn.Size = UDim2.new(1, 0, 0, 26)
			rowBtn.BackgroundColor3 = Theme.Colors.PanelRaised
			rowBtn.BackgroundTransparency = rowDisabled and 0.6 or 0.2
			rowBtn.BorderSizePixel = 0
			rowBtn.Text = ""
			rowBtn.AutoButtonColor = not rowDisabled
			rowBtn.LayoutOrder = rowOrder
			rowBtn.Parent = scroll
			Instance.new("UICorner", rowBtn).CornerRadius = UDim.new(0, 4)

			local slotLabel = "Slot " .. slot .. "  |  Aug " .. augSlot
			local occLabel = "Empty"
			if rowDisabled then
				occLabel = rowDisabledReason or "Unavailable"
			elseif existingDef then
				occLabel = "Replace: " .. existingDef.name
			end

			makeLabel(rowBtn, { Text = slotLabel,
				Size = UDim2.new(0.35, 0, 1, 0),
				Position = UDim2.new(0, 6, 0, 0),
				Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Tiny(),
				TextColor3 = rowDisabled and Theme.Colors.TextDisabled or Theme.Colors.TextPrimary })
			makeLabel(rowBtn, { Text = skillName or (slot == 5 and "Locked" or "-"),
				Size = UDim2.new(0.25, 0, 1, 0),
				Position = UDim2.new(0.35, 0, 0, 0),
				TextSize = Theme.Text.Tiny(), TextColor3 = Theme.Colors.TextSecondary })
			makeLabel(rowBtn, { Text = occLabel,
				Size = UDim2.new(0.35, -6, 1, 0),
				Position = UDim2.new(0.62, 0, 0, 0),
				TextSize = Theme.Text.Badge(), TextColor3 = rowDisabled and Theme.Colors.TextDisabled or Theme.Colors.Warning,
				TextXAlignment = Enum.TextXAlignment.Right })

			if not rowDisabled then
				local cSlot, cAug = slot, augSlot
				rowBtn.Activated:Connect(function()
					closeDetail()
					if MockData.ServerAttachAugment then
						-- Respect the server result; incompatible slots are already greyed out
						-- above, so this is a safety net against any edge the client missed.
						local res = MockData.ServerAttachAugment(unit.id, cSlot, cAug, aug.id)
						if type(res) == "table" and res.ok == false then
							warn("[Loadout] Attach refused: " .. tostring(res.reason))
						end
					end
					MockData.LoadSkillData(unit.id)
					buildSkillsContent()
				end)
			end

			rowOrder = rowOrder + 1
		end
	end

	Theme.MakeIconButton(popup, "Back", closeDetail, {
		name = "Btn_Cancel",
		size = UDim2.new(0, 18, 0, 18),
		position = UDim2.new(0.5, 0, 1, -20),
		anchor = Vector2.new(0.5, 0),
	})
end

-- ==================================================================


function LoadoutSkillLoadout.Init(c: any)
	ctx = c
end
LoadoutSkillLoadout.BuildSkillLoadout = function(...) return buildSkillLoadout(...) end
LoadoutSkillLoadout.OpenAugmentPickerForSlot = function(...) return openAugmentPickerForSlot(...) end
LoadoutSkillLoadout.OpenAugmentSlotPicker = function(...) return openAugmentSlotPicker(...) end
LoadoutSkillLoadout.OpenSkillSlotPicker = function(...) return openSkillSlotPicker(...) end

return LoadoutSkillLoadout
