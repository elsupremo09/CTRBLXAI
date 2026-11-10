--!strict
-- TileImageData.lua
-- CTRBLXAI | 2D images drawn flat on a tile top, over the terrain image (2026-11-10).
-- Traps: drawn by the SERVER (MapRenderer.spawnObjectModel) in place of a 3D model, so a
--   hidden trap is never drawn (hidden traps never reach the renderer).
-- Tile effects: drawn by the CLIENT (VFXController.SetTileEffectImage) while the effect is
--   active, from TileEffectApplied / TileEffectRemoved. Runs alongside any particle VFX.
-- Keys MUST match ObjectData.Objects keys / TileEffectService effect ids exactly.
-- Blank or missing key = no image (graceful). Use IMAGE asset ids, not Decal ids.
-- Uploaded by El_Pi0818.

local TileImageData = {}

TileImageData.Traps = table.freeze({
	["Bear Trap"]           = "rbxassetid://139815369298032",
	["Land Mine"]           = "rbxassetid://137132131826471",
	["Spike Trap"]          = "rbxassetid://97475337097659",  -- "Spike Trap (2)"; original upload: rbxassetid://73756183366360
	["Poison Trap"]         = "rbxassetid://91575234030575",
	["Snare Trap"]          = "rbxassetid://90256654230868",
	["Stasis Trap Emitter"] = "rbxassetid://124490878479743",
})

TileImageData.TileEffects = table.freeze({
	["Tar Pit"] = "rbxassetid://103230447493340",
	Oily        = "rbxassetid://97378096153981",
	Vines       = "rbxassetid://85768759320742",
	Frozen      = "rbxassetid://134017973926668",  -- uploaded as "Ice"; mapped to the Frozen effect
})

-- Height of the image plate above the tile top (studs). Trap sits above an effect.
TileImageData.EFFECT_LIFT = 0.06
TileImageData.TRAP_LIFT = 0.12
TileImageData.PIXELS_PER_STUD = 50
-- Trap image size as a fraction of the tile (1 = full tile). 0.7 = 30% smaller (2026-11-10).
TileImageData.TRAP_IMAGE_SCALE = 0.7

return table.freeze(TileImageData)
