--!strict
-- DungeonPartyPanel.lua
-- CTRBLXAI | Dungeon "Edit party" panel at Rest rooms (Dungeon build step 7b, 2026-11-14; project_rules
-- 258 cap, 265 party lock, 267 Rest). Own module so DungeonScreen.lua stays under 1000 lines.
--
-- Display + input only (ARC-001 / SEC-002): the client sends { op = "send" | "bring", unitId }; the
-- server checks the cap, 1 bring-in per Rest, keep >= 1, and that home units are free, then answers
-- with fresh state. Units sent home are unlocked at once; brought-in units join at their current HP.
--
-- TEXT: all strings approved (project_rules 275, user 2026-11-14 10:32 AM; DG-EDIT-*).

local uiFolder = script.Parent
local Theme: any = (require :: any)(uiFolder:WaitForChild("Theme", 10))
local GuildScreen: any = (require :: any)(uiFolder:WaitForChild("GuildScreen", 10))

local DungeonPartyPanel = {}

export type Ctx = {
	gui: Instance,                               -- the screen's ScreenGui (overlay parent)
	act: (data: { [string]: any }) -> any?,      -- DungeonScreen act(): server call + state update
	getUnits: () -> any?,                        -- GetGuildUnits (fresh)
	onDone: () -> (),                            -- back to the Rest panel / map
}

local overlay: Instance? = nil
local lastCtx: Ctx? = nil

local function close()
	if overlay then
		overlay:Destroy()
		overlay = nil
	end
end

local function text(parent: Instance?, s: string, size: number, color: Color3, bold: boolean?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Font = if bold then Theme.Font.PrimaryBold else Theme.Font.Primary
	l.TextSize = math.max(10, size) -- 10 px phone floor
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = s
	l.ZIndex = 22
	l.Parent = parent
	return l
end

local render: (run: any, units: any) -> () = function() end

local function call(data: { [string]: any })
	local c = lastCtx
	if not c then return end
	local res = c.act(data)
	if res and res.run then
		render(res.run, c.getUnits())
	end
end

local function column(box: Instance, x: number, heading: string, y: number): ScrollingFrame
	local h = text(box, heading, Theme.Text.Small(), Theme.Colors.TextGold, true)
	h.Position = UDim2.new(x, if x > 0 then 6 else 0, 0, y)
	h.Size = UDim2.new(0.5, -6, 0, 18)
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.new(x, if x > 0 then 6 else 0, 0, y + 20)
	list.Size = UDim2.new(0.5, -6, 1, -(y + 20) - GuildScreen.ROW_H - 26)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ZIndex = 22
	local ll = Instance.new("UIListLayout")
	ll.Padding = UDim.new(0, 4)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = list
	list.Parent = box
	return list
end

local function unitRow(list: Instance, i: number, u: any, btnText: string?, onTap: (() -> ())?, tag: string?)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -6, 0, 44) -- 44 px touch row
	row.BackgroundColor3 = Theme.Colors.Panel
	row.BorderSizePixel = 0
	row.LayoutOrder = i
	row.ZIndex = 22
	local nm = text(row, `{u.name or "?"}  Lv.{u.unitLevel or "?"}`, Theme.Text.Small(), Theme.Colors.TextPrimary, true) -- party tile text (APPROVED)
	nm.Position = UDim2.fromOffset(6, 2)
	nm.Size = UDim2.new(1, -100, 0, 20)
	local hp = text(row, `HP {u.hp or 0}/{u.maxHp or 0}`, Theme.Text.Small(), Theme.Colors.TextSecondary) -- APPROVED
	hp.Font = Theme.Font.Mono
	hp.Position = UDim2.fromOffset(6, 22)
	hp.Size = UDim2.new(1, -100, 0, 18)
	if btnText and onTap then
		local b = Theme.MakeBarButton(nil, btnText, "Secondary", onTap, { name = "Btn_" .. tostring(u.id), minHeight = 40 })
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -4, 0.5, 0)
		b.ZIndex = 23
		b.Parent = row
	elseif tag then
		local t = text(row, tag, Theme.Text.Small(), Theme.Colors.TextSecondary, true) -- "AWAY" / "Exploring a dungeon" (APPROVED)
		t.AnchorPoint = Vector2.new(1, 0)
		t.Position = UDim2.new(1, -6, 0, 0)
		t.Size = UDim2.new(0, 90, 1, 0)
		t.TextXAlignment = Enum.TextXAlignment.Right
	end
	row.Parent = list
end

render = function(run: any, units: any)
	local c = lastCtx
	if not c or not run then return end
	close()
	-- Shared guild popup box filling the safe height below the Roblox top bar (2026-11-17 style fix).
	local o, box = GuildScreen.MakeModalBox("PartyPanel", { maxW = 640, widthScale = 0.9, fill = true })

	local inRun: { [string]: boolean } = {}
	for _, id in run.party or {} do inRun[id] = true end
	local cap = run.partyCap or 7
	local title = text(box, "Edit party", Theme.Text.Heading(), Theme.Colors.TextGold, true) -- DG-EDIT-T
	title.Size = UDim2.new(0.6, 0, 0, 22)
	local cnt = text(box, `{#(run.party or {})} / {cap} units`, Theme.Text.Body(), Theme.Colors.TextPrimary, true) -- DG-EDIT-COUNT
	cnt.AnchorPoint = Vector2.new(1, 0)
	cnt.Position = UDim2.fromScale(1, 0)
	cnt.Size = UDim2.new(0.4, 0, 0, 22)
	cnt.TextXAlignment = Enum.TextXAlignment.Right
	local deploy = text(box, "Up to 7 fight each battle. The rest wait on the bench.", Theme.Text.Small(), Theme.Colors.TextSecondary) -- DG-EDIT-DEPLOY
	deploy.Position = UDim2.fromOffset(0, 22)
	deploy.Size = UDim2.new(1, 0, 0, 16)

	local leftList = column(box, 0, "In the dungeon", 40) -- DG-EDIT-INRUN
	local rightList = column(box, 0.5, "At home", 40)       -- DG-EDIT-HOME
	local canBring = (run.restBroughtIn or 0) < 1 and #(run.party or {}) < cap
	local li, ri = 0, 0
	for _, u in (units and units.units) or {} do
		if inRun[u.id] then
			li += 1
			local id = u.id
			unitRow(leftList, li, u, "Send home", function() call({ action = "EditParty", op = "send", unitId = id }) end) -- DG-EDIT-SEND
		else
			ri += 1
			if u.away then
				unitRow(rightList, ri, u, nil, nil, if u.awayReason == "dungeon" then "Exploring a dungeon" else "AWAY")
			elseif canBring then
				local id = u.id
				unitRow(rightList, ri, u, "Bring in", function() call({ action = "EditParty", op = "bring", unitId = id }) end) -- DG-EDIT-BRING
			else
				unitRow(rightList, ri, u)
			end
		end
	end

	local notes = text(box, "Units join with the HP they have now.", Theme.Text.Small(), Theme.Colors.TextSecondary) -- DG-EDIT-HP
	notes.AnchorPoint = Vector2.new(0, 1)
	notes.Position = UDim2.new(0, 0, 1, -GuildScreen.ROW_H - 6)
	notes.Size = UDim2.new(1, 0, 0, 16)
	if not run.restUsed then
		local heal = text(box, "Sanctuary heals only units already in the party.", Theme.Text.Small(), Theme.Colors.TextSecondary) -- DG-EDIT-HEAL
		heal.AnchorPoint = Vector2.new(0, 1)
		heal.Position = UDim2.new(0, 0, 1, -GuildScreen.ROW_H - 22)
		heal.Size = UDim2.new(1, 0, 0, 16)
	end

	local btns = Instance.new("Frame")
	btns.Name = "Buttons"
	btns.AnchorPoint = Vector2.new(0, 1)
	btns.Position = UDim2.fromScale(0, 1)
	btns.Size = UDim2.new(1, 0, 0, GuildScreen.ROW_H)
	btns.BackgroundTransparency = 1
	btns.ZIndex = 22
	local bl = Instance.new("UIListLayout")
	bl.FillDirection = Enum.FillDirection.Horizontal
	bl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	bl.VerticalAlignment = Enum.VerticalAlignment.Center
	bl.Padding = UDim.new(0, 6)
	bl.Parent = btns
	-- 2026-11-18 user: shared check icon (was the "Done" bar).
	local done = Theme.MakeIconButton(nil, "Confirm", function() -- DG-EDIT-DONE
		close()
		c.onDone()
	end, { name = "Btn_Done", size = UDim2.fromOffset(GuildScreen.ROW_H, GuildScreen.ROW_H) })
	done.Parent = btns
	btns.Parent = box

	o.Parent = c.gui -- parent last (NET-004)
	overlay = o
end

--- Open the panel for the current Rest room. `run` is the latest state.run from the server.
function DungeonPartyPanel.Open(c: Ctx, run: any)
	lastCtx = c
	render(run, c.getUnits())
end

function DungeonPartyPanel.Close()
	close()
end

function DungeonPartyPanel.IsOpen(): boolean
	return overlay ~= nil
end


return table.freeze(DungeonPartyPanel)
