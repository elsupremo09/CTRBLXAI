-- TemplateViewer.server.lua
-- CTRBLXAI | Slice 5
--
-- DISABLED: Map generation is now owned by the Quest System in Main.server.lua.
-- The quest flow is: Quest Board → quest selection → MapService.Generate(quest.biome, quest.template).
-- No map should exist in workspace before the player chooses a quest.
--
-- This script previously generated a Plains/T01 map at startup so Main could
-- WaitForChild("TemplateViewerMap"). That pattern is no longer needed.
-- Main now creates the map folder itself after quest selection.
--
-- The dev panel's REGENERATE MAP button (handled in Main) still works for testing
-- different biome/template combinations at runtime.

print("[TemplateViewer] Disabled — map generation owned by Quest System in Main.server.lua")
