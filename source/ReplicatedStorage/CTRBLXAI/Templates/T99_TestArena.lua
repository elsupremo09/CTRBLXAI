-- T99_TestArena.lua
-- STUDIO TEST MAP (user request 2026-11-05). Not a design-DB template and not in any random
-- quest pool: used only by QuestGenerator.GenerateTestArena (Studio-only board quest).
-- 8x8: enemies on rows 1-3, players on rows 6-8, a 2-row lane between (user ruling 2026-11-05)
-- so the front rows are 3 apart and units can engage on turn 1. Weather is left random.
local Template = {}

Template.Id = "T99"
Template.Name = "Test Arena"
Template.Width = 8
Template.Height = 8

Template.Grid = {
	{ "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED" },
	{ "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED" },
	{ "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED" },
	{ "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN" },
	{ "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN" },
	{ "PD", "PD", "PD", "PD", "PD", "PD", "PD", "PD" },
	{ "PD", "PD", "PD", "PD", "PD", "PD", "PD", "PD" },
	{ "PD", "PD", "PD", "PD", "PD", "PD", "PD", "PD" },
}

return Template
