-- TemplateViewer.server.lua
-- CTRBLXAI | Slice 5 Phase 4 — Renders MapService-generated battlefield
--
-- Uses MapRenderer module for tile creation. This script just calls
-- MapService.Generate() and MapRenderer.Render(), then parents the
-- result to workspace.
--
-- Architecture:
--   TemplateViewer calls MapService.Generate() with the same parameters
--   as Main.server.lua (deterministic — same seed = same map).
--   The mapFolder is parented to workspace AFTER all tiles are created
--   so Main's WaitForChild("TemplateViewerMap") blocks until rendering
--   is complete.

local ServerScriptService = game:GetService("ServerScriptService")

local Game = ServerScriptService:WaitForChild("Game")

local MapService = require(Game:WaitForChild("MapService"))
local MapRenderer = require(Game:WaitForChild("MapRenderer"))

--------------------------------------------------
-- SETTINGS
--------------------------------------------------

local BIOME_ID    = "Plains"
local TEMPLATE_ID = "T01"
local MAP_SEED    = nil  -- nil = random seed; first caller generates, second gets cache

local INITIAL_VIEW_MODE = "TERRAIN"

--------------------------------------------------
-- VALIDATE SETTINGS
--------------------------------------------------

assert(
	INITIAL_VIEW_MODE == "TERRAIN"
		or INITIAL_VIEW_MODE == "REGION"
		or INITIAL_VIEW_MODE == "TEMPLATE",
	'INITIAL_VIEW_MODE must be "TERRAIN", "REGION", or "TEMPLATE".'
)

--------------------------------------------------
-- CLEANUP
--------------------------------------------------

local oldMap = workspace:FindFirstChild("TemplateViewerMap")
if oldMap then
	oldMap:Destroy()
end

--------------------------------------------------
-- GENERATE MAP VIA MAPSERVICE
--------------------------------------------------

local generatedMap = MapService.Generate(
	BIOME_ID, TEMPLATE_ID, MAP_SEED
)

--------------------------------------------------
-- RENDER MAP VIA MAPRENDERER
--------------------------------------------------

local mapFolder = MapRenderer.Render(generatedMap, INITIAL_VIEW_MODE)

-- Parent LAST — Main.server.lua WaitForChild blocks
-- until this line, guaranteeing all tiles exist.
mapFolder.Parent = workspace

--------------------------------------------------
-- DEBUG OUTPUT
--------------------------------------------------

print("====================================")
print("CTRBLXAI Template Viewer Loaded")
print("====================================")

print(string.format("Template: %s", TEMPLATE_ID))
print(string.format("Size: %d x %d", generatedMap.width, generatedMap.height))
print(string.format("Biome: %s", BIOME_ID))
print(string.format("Seed: %d", generatedMap.seed))
print(string.format("Initial View: %s", INITIAL_VIEW_MODE))
print(string.format("Objects: %d", #generatedMap.objects))
print(string.format("Blockers: %d", #generatedMap.blockers))
print(string.format("Battle Condition: %s", generatedMap.battleCondition))

print(string.format(
	"[TemplateViewer] Rendered %d tiles with"
		.. " generated terrain and elevation.",
	generatedMap.width * generatedMap.height
))
