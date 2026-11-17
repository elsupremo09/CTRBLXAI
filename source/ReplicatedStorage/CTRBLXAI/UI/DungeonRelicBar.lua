--!strict
-- DungeonRelicBar.lua
-- CTRBLXAI | Dungeon relics on the map screen (Dungeon build step 8, 2026-11-14; project_rules 271/275).
-- Display only: relic list comes from the server state (run.relics), nothing is sent back except
-- the AckRelic action when a "Relic found" popup closes. Only approved text (rule 275):
--   RL-UI-HEAD "Relics", RL-UI-NONE "No relics yet", RL-UI-RARITY "{rarity} relic", RL-UI-USED "Used",
--   RL-UI-FOUND-T "Relic found!", RL-UI-FOUND-1 "{name}", RL-UI-FOUND-2 "{effect}",
--   RL-UI-FOUND-3 "Lasts until this run ends.", Boss handover "The Boss's hoard glints. Relic found: {name}!",
--   RL-UI-END "Relics fade when you leave the dungeon."
-- Placeholder icons: a round gem coloured by rarity (Theme.GetRarityColor), no new art.

local uiFolder = script.Parent
local Theme: any = (require :: any)(uiFolder:WaitForChild("Theme", 10))

local Bar = {}

Bar.END_LINE = "Relics fade when you leave the dungeon." -- RL-UI-END


-- Bar.Draw (the map relic row) removed 2026-11-15: relics are listed in the Bag popup now (Tester A10).

--- "Relic found" popup for run.relicFound = { id, boss }. onClose sends AckRelic.
function Bar.ShowFound(found: any, relics: { any }?, deps: any, onClose: () -> ())
	local r: any = nil
	for _, x in relics or {} do if x.id == found.id then r = x end end
	if not r then onClose() return end
	local lines: { any }
	if found.boss then
		lines = {
			{ `The Boss's hoard glints. Relic found: {r.name}!`, Theme.Text.Heading(), Theme.Colors.TextGold, true },
			{ tostring(r.text) },
			{ "Lasts until this run ends.", nil, Theme.Colors.TextSecondary },                  -- RL-UI-FOUND-3
		}
	else
		lines = {
			{ "Relic found!", Theme.Text.Heading(), Theme.Colors.TextGold, true },             -- RL-UI-FOUND-T
			{ tostring(r.name), nil, Theme.GetRarityColor(r.rarity or "Common"), true },      -- RL-UI-FOUND-1
			{ `{r.rarity} relic`, nil, Theme.Colors.TextSecondary },                           -- RL-UI-RARITY
			{ tostring(r.text) },                                                            -- RL-UI-FOUND-2
			{ "Lasts until this run ends.", nil, Theme.Colors.TextSecondary },                 -- RL-UI-FOUND-3
		}
	end
	-- Curse paired with this relic (rule 271): its name + effect in red, after RF-CURSE (approved
	-- 2026-11-15 12:38 PM).
	if found.curse then
		for _, x in relics or {} do
			if x.id == found.curse then
				table.insert(lines, { `It came with a curse: {x.name}.`, nil, Theme.Colors.Danger }) -- RF-CURSE
				table.insert(lines, { tostring(x.name), nil, Theme.Colors.Danger, true })
				table.insert(lines, { tostring(x.text), nil, Theme.Colors.Danger })
			end
		end
	end
	deps.popup("RelicFound", lines, { { icon = "Back", onTap = function() deps.closeOverlay(); onClose() end } })
end

--- Cursed relic popup (relics v2, rule 271): a Major that rolled a random curse. offer = { name, rarity, text,
--- curseName, curseText }. onAnswer(true = Take both | false = Leave both). Text CP-* approved 2026-11-15 12:38 PM
--- (rule 275; source DRAFT_dungeon_curse_popup_text_20261115.md).
function Bar.ShowCurseOffer(offer: any, deps: any, onAnswer: (boolean) -> ())
	local lines: { any } = {
		{ "A cursed relic!", Theme.Text.Heading(), Theme.Colors.Danger, true },                                -- CP-T
		{ `{offer.name} comes with a curse: {offer.curseName}.` },                                             -- CP-1
		{ tostring(offer.name), nil, Theme.GetRarityColor(offer.rarity or "Common"), true },
		{ tostring(offer.text), nil, Theme.GetRarityColor(offer.rarity or "Common") },                          -- CP-2
		{ tostring(offer.curseName), nil, Theme.Colors.Danger, true },
		{ tostring(offer.curseText), nil, Theme.Colors.Danger },                                                -- CP-3
		{ "Curses can't be blocked or removed.", nil, Theme.Colors.TextSecondary },                             -- CP-4
	}
	deps.popup("CurseOffer", lines, {
		{ text = "Take both", style = "Primary", onTap = function() deps.closeOverlay(); onAnswer(true) end },  -- CP-TAKE
		{ text = "Leave both", style = "Secondary", onTap = function() deps.closeOverlay(); onAnswer(false) end }, -- CP-LEAVE
	})
end

--- Boss pick 1 of 2 (rule 271, relics v2). pick = { a = relic view (Boss relic), b = relic view (normal) }.
--- onPick("a" | "b"). Text BP-* approved 2026-11-15 12:38 PM (rule 275).
function Bar.ShowBossPick(pick: any, deps: any, onPick: (string) -> ())
	local lines: { any } = {
		{ "The Boss guards two relics. Take one.", Theme.Text.Heading(), Theme.Colors.TextGold, true }, -- BP-T
	}
	local buttons: { any } = {}
	for _, k in { "a", "b" } do
		local r = pick[k]
		if r then
			table.insert(lines, { tostring(r.name), nil, Theme.GetRarityColor(r.rarity or "Common"), true })
			table.insert(lines, { `{r.rarity} relic`, nil, Theme.Colors.TextSecondary })            -- RL-UI-RARITY
			table.insert(lines, { tostring(r.text) })
			if r.curseName then -- W2: paired curse in red (existing relic strings only)
				table.insert(lines, { tostring(r.curseName), nil, Theme.Colors.Danger, true })
				if r.curseText then table.insert(lines, { tostring(r.curseText), nil, Theme.Colors.Danger }) end
			end
			table.insert(buttons, { text = `Take {r.name}`, style = if k == "a" then "Primary" else "Secondary", -- BP-TAKE
				onTap = function() deps.closeOverlay(); onPick(k) end })
		end
	end
	deps.popup("BossPick", lines, buttons)
end

--- Depth curse pick (endless step 6, rule 281): offer = { i, n, a, b } (relic views). onPick("a" | "b").
--- Text: DG-CURSE-PICK-TITLE / DG-CURSE-PICK-BODY (approved 2026-11-16 8:07 PM), RL-61..68 names + texts
--- (rule 282), "Take {name}" (BP-TAKE). Back closes it: Go home stays possible (agent default).
function Bar.ShowDepthCurse(offer: any, deps: any, onPick: (string) -> ())
	local lines: { any } = {
		{ "The depths demand a price", Theme.Text.Heading(), Theme.Colors.Danger, true },        -- DG-CURSE-PICK-TITLE
		{ `Choose a curse to carry ({offer.i or 1} of {offer.n or 1}).` },                     -- DG-CURSE-PICK-BODY
	}
	local buttons: { any } = {}
	for _, k in { "a", "b" } do
		local r = offer[k]
		if r then
			local held = tonumber(r.stacks) or 0
			table.insert(lines, { if held > 0 then `{r.name} ×{held + 1}` else tostring(r.name), nil, Theme.Colors.Danger, true })
			table.insert(lines, { tostring(r.text), nil, Theme.Colors.Danger })
			table.insert(buttons, { text = `Take {r.name}`, style = "Secondary", onTap = function() deps.closeOverlay(); onPick(k) end }) -- BP-TAKE
		end
	end
	table.insert(buttons, { icon = "Back", onTap = deps.closeOverlay })
	deps.popup("DepthCurse", lines, buttons)
end

--- Every forced pick in turn (one DepthCurse call each), then onDone() (Go deeper). act = the screen's
--- action call; it returns the new state (state.run.depthOffer = the next pair, or done).
function Bar.DepthPicks(offer: any, deps: any, act: (any) -> any, onDone: () -> ())
	if type(offer) ~= "table" or offer.done or not (offer.a and offer.b) then onDone() return end
	Bar.ShowDepthCurse(offer, deps, function(which)
		local res = act({ action = "DepthCurse", which = which })
		if res and res.ok ~= false then
			Bar.DepthPicks(res.run and res.run.depthOffer, deps, act, onDone)
		end
	end)
end

return table.freeze(Bar)
