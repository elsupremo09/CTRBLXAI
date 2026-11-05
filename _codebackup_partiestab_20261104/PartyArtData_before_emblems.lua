--!strict
-- PartyArtData.lua
-- CTRBLXAI | Party emblems and header backgrounds (Parties tab, USER DECISION 2026-11-04).
--
-- The user uploads the art to Roblox; add each one here as  key = { name, image }.
--   key   : short id saved with the party (letters, digits, _ or -; keep it forever)
--   name  : shown in the picker
--   image : "rbxassetid://<IMAGE asset id>" (use the Image id, not the Decal id)
-- The save stores only the key, so an image can be swapped later without breaking saves.
-- Order here = order in the picker. While a list is empty, parties show the plain default
-- (navy tile with the party number / plain navy background). A party that never chose
-- art uses the FIRST entry once art exists (Designer default).

export type Art = { name: string, image: string }

local PartyArtData = {}

PartyArtData.Emblems = {
	-- example: phoenix = { name = "Phoenix", image = "rbxassetid://0000000000" },
} :: { [string]: Art }
PartyArtData.EmblemOrder = {
	-- "phoenix",
} :: { string }

PartyArtData.Backgrounds = {
	-- example: castle_dusk = { name = "Castle at Dusk", image = "rbxassetid://0000000000" },
} :: { [string]: Art }
PartyArtData.BackgroundOrder = {
	-- "castle_dusk",
} :: { string }

-- The art for a saved key, or the first entry when the key is unset/unknown, or nil.
function PartyArtData.Resolve(kind: string, key: string?): Art?
	local map = if kind == "emblem" then PartyArtData.Emblems else PartyArtData.Backgrounds
	local order = if kind == "emblem" then PartyArtData.EmblemOrder else PartyArtData.BackgroundOrder
	if key and map[key] then return map[key] end
	local first = order[1]
	return if first then map[first] else nil
end

function PartyArtData.IsValid(kind: string, key: string): boolean
	local map = if kind == "emblem" then PartyArtData.Emblems else PartyArtData.Backgrounds
	return map[key] ~= nil
end

return PartyArtData
