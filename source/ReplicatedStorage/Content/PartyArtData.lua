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

-- 63 emblems uploaded by the user 2026-11-05 (Image assets, creator El_Pi0818), keyed by their
-- sheet position r<row>c<col>. Keys are saved with parties: never rename them.
PartyArtData.Emblems = {
	em_r0c0 = { name = "Emblem 1", image = "rbxassetid://125140299517790" },
	em_r0c1 = { name = "Emblem 2", image = "rbxassetid://112702570758059" },
	em_r0c2 = { name = "Emblem 3", image = "rbxassetid://114643185148512" },
	em_r0c3 = { name = "Emblem 4", image = "rbxassetid://105657643325315" },
	em_r0c4 = { name = "Emblem 5", image = "rbxassetid://99435915263260" },
	em_r0c6 = { name = "Emblem 6", image = "rbxassetid://97231795949836" },
	em_r0c7 = { name = "Emblem 7", image = "rbxassetid://78245936457011" },
	em_r1c0 = { name = "Emblem 8", image = "rbxassetid://87659631495538" },
	em_r1c1 = { name = "Emblem 9", image = "rbxassetid://72687314174345" },
	em_r1c2 = { name = "Emblem 10", image = "rbxassetid://125985203270065" },
	em_r1c3 = { name = "Emblem 11", image = "rbxassetid://72073798198529" },
	em_r1c4 = { name = "Emblem 12", image = "rbxassetid://117572000198059" },
	em_r1c5 = { name = "Emblem 13", image = "rbxassetid://132609421476183" },
	em_r1c6 = { name = "Emblem 14", image = "rbxassetid://123691734863527" },
	em_r1c7 = { name = "Emblem 15", image = "rbxassetid://73784835276238" },
	em_r2c0 = { name = "Emblem 16", image = "rbxassetid://104447023007411" },
	em_r2c1 = { name = "Emblem 17", image = "rbxassetid://121826436297148" },
	em_r2c2 = { name = "Emblem 18", image = "rbxassetid://111190032765961" },
	em_r2c3 = { name = "Emblem 19", image = "rbxassetid://84146501564542" },
	em_r2c4 = { name = "Emblem 20", image = "rbxassetid://83551483763047" },
	em_r2c5 = { name = "Emblem 21", image = "rbxassetid://120072857238003" },
	em_r2c6 = { name = "Emblem 22", image = "rbxassetid://130777437722708" },
	em_r2c7 = { name = "Emblem 23", image = "rbxassetid://114630633376122" },
	em_r3c0 = { name = "Emblem 24", image = "rbxassetid://110104696448656" },
	em_r3c1 = { name = "Emblem 25", image = "rbxassetid://77909732997423" },
	em_r3c2 = { name = "Emblem 26", image = "rbxassetid://130508876977108" },
	em_r3c3 = { name = "Emblem 27", image = "rbxassetid://127466119091025" },
	em_r3c4 = { name = "Emblem 28", image = "rbxassetid://136830729062820" },
	em_r3c5 = { name = "Emblem 29", image = "rbxassetid://86518483140241" },
	em_r3c6 = { name = "Emblem 30", image = "rbxassetid://126828780134008" },
	em_r3c7 = { name = "Emblem 31", image = "rbxassetid://121331612293242" },
	em_r4c0 = { name = "Emblem 32", image = "rbxassetid://75316443020064" },
	em_r4c1 = { name = "Emblem 33", image = "rbxassetid://111533216690853" },
	em_r4c2 = { name = "Emblem 34", image = "rbxassetid://76128245064087" },
	em_r4c3 = { name = "Emblem 35", image = "rbxassetid://71773574169032" },
	em_r4c4 = { name = "Emblem 36", image = "rbxassetid://128565267514947" },
	em_r4c5 = { name = "Emblem 37", image = "rbxassetid://78298764760208" },
	em_r4c6 = { name = "Emblem 38", image = "rbxassetid://140490346535313" },
	em_r4c7 = { name = "Emblem 39", image = "rbxassetid://75320323182936" },
	em_r5c0 = { name = "Emblem 40", image = "rbxassetid://72741142301590" },
	em_r5c1 = { name = "Emblem 41", image = "rbxassetid://90017225690350" },
	em_r5c2 = { name = "Emblem 42", image = "rbxassetid://94682079768557" },
	em_r5c3 = { name = "Emblem 43", image = "rbxassetid://137795200822249" },
	em_r5c4 = { name = "Emblem 44", image = "rbxassetid://133430927526642" },
	em_r5c5 = { name = "Emblem 45", image = "rbxassetid://103478614023766" },
	em_r5c6 = { name = "Emblem 46", image = "rbxassetid://140630580061572" },
	em_r5c7 = { name = "Emblem 47", image = "rbxassetid://97246279143149" },
	em_r6c0 = { name = "Emblem 48", image = "rbxassetid://134405045764815" },
	em_r6c1 = { name = "Emblem 49", image = "rbxassetid://126292928015538" },
	em_r6c2 = { name = "Emblem 50", image = "rbxassetid://74367444776943" },
	em_r6c3 = { name = "Emblem 51", image = "rbxassetid://73895670423379" },
	em_r6c4 = { name = "Emblem 52", image = "rbxassetid://123612399133722" },
	em_r6c5 = { name = "Emblem 53", image = "rbxassetid://105606645525023" },
	em_r6c6 = { name = "Emblem 54", image = "rbxassetid://78390580171522" },
	em_r6c7 = { name = "Emblem 55", image = "rbxassetid://78494004533357" },
	em_r7c0 = { name = "Emblem 56", image = "rbxassetid://110775797646019" },
	em_r7c1 = { name = "Emblem 57", image = "rbxassetid://110276432490931" },
	em_r7c2 = { name = "Emblem 58", image = "rbxassetid://84591672564562" },
	em_r7c3 = { name = "Emblem 59", image = "rbxassetid://134661118883526" },
	em_r7c4 = { name = "Emblem 60", image = "rbxassetid://101822041611738" },
	em_r7c5 = { name = "Emblem 61", image = "rbxassetid://94637444074901" },
	em_r7c6 = { name = "Emblem 62", image = "rbxassetid://94211187292000" },
	em_r7c7 = { name = "Emblem 63", image = "rbxassetid://92077246275553" },
} :: { [string]: Art }
PartyArtData.EmblemOrder = {
	"em_r0c0",
	"em_r0c1",
	"em_r0c2",
	"em_r0c3",
	"em_r0c4",
	"em_r0c6",
	"em_r0c7",
	"em_r1c0",
	"em_r1c1",
	"em_r1c2",
	"em_r1c3",
	"em_r1c4",
	"em_r1c5",
	"em_r1c6",
	"em_r1c7",
	"em_r2c0",
	"em_r2c1",
	"em_r2c2",
	"em_r2c3",
	"em_r2c4",
	"em_r2c5",
	"em_r2c6",
	"em_r2c7",
	"em_r3c0",
	"em_r3c1",
	"em_r3c2",
	"em_r3c3",
	"em_r3c4",
	"em_r3c5",
	"em_r3c6",
	"em_r3c7",
	"em_r4c0",
	"em_r4c1",
	"em_r4c2",
	"em_r4c3",
	"em_r4c4",
	"em_r4c5",
	"em_r4c6",
	"em_r4c7",
	"em_r5c0",
	"em_r5c1",
	"em_r5c2",
	"em_r5c3",
	"em_r5c4",
	"em_r5c5",
	"em_r5c6",
	"em_r5c7",
	"em_r6c0",
	"em_r6c1",
	"em_r6c2",
	"em_r6c3",
	"em_r6c4",
	"em_r6c5",
	"em_r6c6",
	"em_r6c7",
	"em_r7c0",
	"em_r7c1",
	"em_r7c2",
	"em_r7c3",
	"em_r7c4",
	"em_r7c5",
	"em_r7c6",
	"em_r7c7",
} :: { string }

-- 16 backgrounds uploaded by the user 2026-11-05 (Image assets, creator El_Pi0818), in the user's
-- order. Keys are saved with parties: never rename them.
PartyArtData.Backgrounds = {
	["bg_volcanic-forge-hall"] = { name = "Volcanic Forge Hall", image = "rbxassetid://86437772289862" },
	["bg_haunted-graveyard"] = { name = "Haunted Graveyard", image = "rbxassetid://84537462958146" },
	["bg_595"] = { name = "Background 595", image = "rbxassetid://137846651507039" },
	["bg_650"] = { name = "Background 650", image = "rbxassetid://129620897833166" },
	["bg_swamp-witch-bog"] = { name = "Swamp Witch Bog", image = "rbxassetid://101815906572116" },
	["bg_bloodmoon-throne-room"] = { name = "Bloodmoon Throne Room", image = "rbxassetid://84081588917132" },
	["bg_elven-moonlit-glade"] = { name = "Elven Moonlit Glade", image = "rbxassetid://85777831710469" },
	["bg_desert-ruins-dusk"] = { name = "Desert Ruins Dusk", image = "rbxassetid://139099190881723" },
	["bg_sunken-temple"] = { name = "Sunken Temple", image = "rbxassetid://111988352594191" },
	["bg_mountain-pass-storm"] = { name = "Mountain Pass Storm", image = "rbxassetid://90398590308866" },
	["bg_abyssal-demon-gate"] = { name = "Abyssal Demon Gate", image = "rbxassetid://107777839416135" },
	["bg_frozen-glacier-cavern"] = { name = "Frozen Glacier Cavern", image = "rbxassetid://76377192748437" },
	["bg_471"] = { name = "Background 471", image = "rbxassetid://99244555169227" },
	["bg_128"] = { name = "Background 128", image = "rbxassetid://75667598784197" },
	["bg_438"] = { name = "Background 438", image = "rbxassetid://126039171620571" },
	["bg_16"] = { name = "Background 16", image = "rbxassetid://106503493263606" },
} :: { [string]: Art }
PartyArtData.BackgroundOrder = {
	"bg_volcanic-forge-hall",
	"bg_haunted-graveyard",
	"bg_595",
	"bg_650",
	"bg_swamp-witch-bog",
	"bg_bloodmoon-throne-room",
	"bg_elven-moonlit-glade",
	"bg_desert-ruins-dusk",
	"bg_sunken-temple",
	"bg_mountain-pass-storm",
	"bg_abyssal-demon-gate",
	"bg_frozen-glacier-cavern",
	"bg_471",
	"bg_128",
	"bg_438",
	"bg_16",
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
