--!strict
-- QuestFlavor (2026-11-18): seeded quest lore for the Quest Board side panel.
-- Wording APPROVED by the user 2026-11-18 9:35 PM: the 40 lines of DRAFT_quest_flavor_text_20261118.md,
-- copied verbatim below (ids B1-B14, G15-G28, C29-C36, A37-A40), capped at 2 sentences
-- (biome opening + goal line) plus the condition line when the quest has one.
-- Deterministic: the seed is a hash of the quest's id + name. Both come from the saved board seed and
-- the quest index (QuestGenerator), so the same quest always shows the same lore, also after a rejoin.
-- Never uses math.random. Any line whose fill-in ({place}, {n}, {target}) is missing is skipped.
-- Mood lines (A37-A40) are NOT used: the draft adds them as an extra sentence, which the approved
-- 2-sentence cap leaves out. They are kept here so the wording stays in one place.
local QuestFlavor = {}

-- v2 lore grammar switch (2026-11-18). Approved by the user 11:08 PM and LIVE (TRUE).
-- FALSE would fall back to the old v1 lines below (kept only as a fallback; replaced in DB game_flow 39).
local LORE_GRAMMAR_ENABLED = true -- approved 2026-11-18 11:08 PM

-- B: biome openings ({place} = the quest's location, e.g. "the Deep Cavern").
local BIOME: { [string]: { string } } = {
	Plains = { "Smoke rises over {place}, and the farmers have fled.", "Travellers on {place} have stopped arriving." },
	Forest = { "Something stirs beneath the canopy of {place}.", "The woodcutters will not go near {place} any more." },
	-- Desert: old B5 "The sands of {place}..." replaced 2026-11-18 10:35 PM by user-approved variants 5A/5B/5C
	-- (DRAFT_quest_flavor_line5_20261118.md), all three in the pool, picked per quest by the seeded rng.
	Desert = { "The dunes around {place} have buried more than caravans.", "Caravans that cross {place} no longer reach the other side.",
		"Bones bleach in the sun at {place}, and not all of them are old.", "Heat shimmers over {place}, hiding what waits there." },
	Highlands = { "Wind howls through {place}, carrying distant war drums." },
	Tundra = { "Tracks in the snow near {place} lead nowhere good." },
	Volcano = { "The ground near {place} glows and cracks underfoot." },
	Castle = { "The banners over {place} have been torn down." },
	Ruins = { "Old stones at {place} whisper of a fallen order." },
	Swamp = { "Lanterns drift over {place}, and no one carries them." },
	Cave = { "Echoes from {place} do not sound like water." },
	Corrupted = { "The air around {place} tastes of rot and iron." },
}

-- G: goal bodies (keys = QuestGoalData ids).
local GOAL: { [string]: { string } } = {
	WipeOut = { "Clear every last one of them from the field.", "Leave none standing; the guild wants the area safe." },
	Slay = { "Thin their ranks before they grow too bold." },
	KillTarget = { "Their leader, {target}, must fall. The rest will scatter.", "A bounty hangs on {target}'s head." },
	Survive = { "Hold out until help arrives; more of them are coming.", "Stand your ground. Every turn you last buys the town time." },
	Reach = { "Break through and reach the marked ground." },
	Activate = { "An old mechanism lies here. Wake it before they stop you." },
	Destroy = { "Smash their {n} war machines before they can be used.", "Burn what they have built. Leave nothing standing." },
	Capture = { "Bring {target} back alive. The guild has questions." },
	Protect = { "A guild courier must get through. Keep them breathing." },
	Prevent = { "Runners carry word to their masters. Stop them at the edge." },
}

-- C: condition notes. Unknown conditions use line 36; Clear / None / Random show none.
local CONDITION: { [string]: string } = {
	["Rain"] = "Rain turns the ground to mud.",
	["Heatwave"] = "The heat saps strength from the unwary.",
	["Strong Wind"] = "Arrows will not fly true in this wind.",
	["Thunderstorm"] = "Lightning cracks overhead; mind the open ground.",
	["Meteor Storm"] = "Fire falls from the sky. Do not stand still.",
	["Volcanic Eruptions"] = "The mountain is waking.",
	["Holy Aurora"] = "A strange light blesses the field.",
}
local CONDITION_OTHER = "Visibility is poor; keep your scouts close."
local NO_CONDITION: { [string]: boolean } = { Clear = true, None = true, Random = true }

-- A: mood words (approved, currently unused; see the header).
QuestFlavor.Mood = table.freeze({
	Desperate = "Time is short.", Fierce = "Time is short.",
	Hidden = "Few know this job exists.", Silent = "Few know this job exists.",
	Sacred = "Old powers have an interest here.", Ancient = "Old powers have an interest here.",
	Dark = "The last party sent here did not return.", Burning = "The last party sent here did not return.",
	Frozen = "The last party sent here did not return.", Lost = "The last party sent here did not return.",
})

local function hash(s: string): number
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 2147483647
	end
	return h
end

-- "Desperate Skirmish at the Open Fields" / "Daily Contract: Lost Hunt at the Deep Cavern" -> location.
local function placeOf(name: string): string?
	local place: string? = nil
	local from = 1
	while true do
		local s, e = string.find(name, " at ", from, true)
		if not s then break end
		place = string.sub(name, (e :: number) + 1)
		from = (e :: number) + 1
	end
	if place and place ~= "" then return place end
	return nil
end

-- Fills {place} / {n} / {target}; returns nil when a needed value is missing.
local function fill(line: string, vals: { [string]: string? }): string?
	local missing = false
	local out = string.gsub(line, "{(%w+)}", function(k: string)
		local v = vals[k]
		if v == nil or v == "" then
			missing = true
			return ""
		end
		return v
	end)
	if missing then return nil end
	return out
end

local function pick(rng: Random, lines: { string }?, vals: { [string]: string? }): string?
	if not lines or #lines == 0 then return nil end
	local usable: { string } = {}
	for _, l in lines do
		local f = fill(l, vals)
		if f then table.insert(usable, f) end
	end
	if #usable == 0 then return nil end
	return usable[rng:NextInteger(1, #usable)]
end

-- ============================================================================================
-- v2 LORE GRAMMAR (2026-11-18 10:39 PM user request: lore must be procedurally generated from parts and
-- vary by biome AND condition AND goal type). APPROVED 2026-11-18 11:08 PM and live (DB game_flow 39 holds
-- every fragment verbatim with its id). Time-of-day leads (L1-L8) were dropped by the user and removed here.
-- Shape (cap = 2 sentences + condition sentence, user 9:35 PM):
--   opening   = "{Scene}, and {threat}." | "{Scene}."   (scene/threat keyed by biome; a scene that already
--               contains " and " always uses the bare form, so no sentence has two "and" clauses - user 11:17 PM)
--   goal      = [goal lead] + core(goal type; {target}/{n} variants) + tail(generic + quest-name mood)
--   condition = image(condition, biome override first) + joiner + consequence ("; " for orders)
-- Deterministic: same Random seed as v1 (hash of quest id + name). Re-draws (max 8) when any content word
-- of 4+ letters appears twice in the whole text, so no noun repeats; the last draw is kept otherwise.
-- ============================================================================================
local G_SCENES: { [string]: { string } } = {
	Plains = {
		"smoke rises over {place}",
		"the farmers near {place} bar their doors",
		"crows circle low over {place}",
		"fresh graves line the way to {place}",
		"the herds near {place} scatter in panic",
		"horns sound from the grass near {place}",
	},
	Forest = {
		"something moves beneath the canopy of {place}",
		"the woodcutters refuse to enter {place}",
		"birdsong falls silent in {place}",
		"strange marks appear on the trees of {place}",
		"torchlight flickers deep in {place}",
		"hunters who enter {place} do not come back",
	},
	Desert = {
		"the dunes around {place} shift to bury fresh tracks",
		"caravans that cross {place} never reach the other side",
		"bones bleach in the sun at {place}",
		"heat shimmers over {place} and hides what waits there",
		"vultures circle above {place}",
		"the wells near {place} run dry overnight",
	},
	Swamp = {
		"lanterns drift over {place} with no one to carry them",
		"the reeds of {place} rustle with no wind",
		"something drags travellers down into {place}",
		"the stink of {place} drifts far beyond its edge",
		"the frogs fall silent all across {place}",
		"boats sent into {place} come back empty",
	},
	Highlands = {
		"war drums echo across {place}",
		"rockslides block the trails to {place}",
		"great wings pass over {place}",
		"the shepherds flee from {place}",
		"signal fires burn on {place}",
		"the wind over {place} carries distant shouting",
	},
	Tundra = {
		"tracks in the snow near {place} lead nowhere good",
		"the ice of {place} groans under heavy feet",
		"a cold that is not natural grips {place}",
		"hunters vanish in the white of {place}",
		"howls carry across {place}",
		"frozen shapes stand like statues near {place}",
	},
	Volcano = {
		"the ground near {place} glows and cracks underfoot",
		"ash falls like snow around {place}",
		"fire creatures crawl out of {place}",
		"the rocks of {place} hiss and spit",
		"a red glow pulses deep in {place}",
		"the air near {place} burns the throat",
	},
	Castle = {
		"the banners over {place} lie torn and trampled",
		"no messenger returns from {place}",
		"torches burn on {place} with no garrison to light them",
		"the gates of {place} hang open",
		"armour clanks along {place} after dark",
		"strange orders ring out from {place}",
	},
	Ruins = {
		"old stones at {place} whisper of a fallen order",
		"the dead walk the halls of {place}",
		"grave robbers flee {place} in terror",
		"lights move deep within {place}",
		"carved guardians at {place} turn their heads",
		"dust rises from {place} as if something stirs",
	},
	Cave = {
		"echoes from {place} do not sound like water",
		"the miners refuse to go back into {place}",
		"a cold draught blows out of {place}",
		"pale eyes glint in the dark of {place}",
		"the walls of {place} drip with slime",
		"the lanterns of the last party lie broken in {place}",
	},
	Corrupted = {
		"the air around {place} tastes of rot and iron",
		"black roots spread out from {place}",
		"cultists chant without rest at {place}",
		"the beasts near {place} grow twisted and wild",
		"a violet light pulses over {place}",
		"nothing living grows within sight of {place}",
	},
}
local G_THREATS: { [string]: { string } } = {
	Plains = {
		"goblin scouts have been seen on the roads",
		"bandits watch the roads",
		"wild beasts roam unchecked",
		"raiders camp in the tall grass",
	},
	Forest = {
		"goblins lay traps among the roots",
		"witch-lights lure travellers off the path",
		"the beasts there have turned on people",
		"the forest spirits no longer welcome visitors",
	},
	Desert = {
		"nomad raiders strike at dusk",
		"bandits lie in wait behind the ridges",
		"the dead walk when the sun goes down",
		"sand beasts circle the camps",
	},
	Swamp = {
		"naga hunt in the shallows",
		"slimes creep up out of the water",
		"insect swarms darken the air",
		"the drowned do not stay down",
	},
	Highlands = {
		"mountain tribes gather for war",
		"a dragon has been seen nesting nearby",
		"gryphons strike at anything that moves",
		"beasts come down from the peaks",
	},
	Tundra = {
		"frost creatures stalk the drifts",
		"the dead rise frozen from the lake bed",
		"white beasts hunt in packs",
		"something stirs beneath the snow",
	},
	Volcano = {
		"demons gather at the edge of the fire",
		"a dragon wakes from its sleep",
		"fire creatures spill from the cracks",
		"cultists feed the flames with offerings",
	},
	Castle = {
		"deserters have taken the walls",
		"knights in black colours hold the gate",
		"the old constructs march again",
		"mercenaries guard every door",
	},
	Ruins = {
		"undead guardians keep their old watch",
		"mercenaries dig for buried relics",
		"stone constructs wake from long sleep",
		"something old is waking below",
	},
	Cave = {
		"slimes ooze from every crack",
		"cave dwellers drag off anyone who strays",
		"the dead walk in the dark",
		"beasts have made a lair there",
	},
	Corrupted = {
		"cultists gather in growing numbers",
		"demons answer their call",
		"corrupted beasts hunt anything clean",
		"the dead serve a new master",
	},
}
local G_GOALS: { [string]: { string } } = {
	WipeOut = {
		"clear every last one of them out",
		"leave none of them standing",
		"rout the whole warband",
		"drive them out to the last",
		"put down everything that fights back",
		"break their numbers completely",
	},
	Slay = {
		"thin their ranks",
		"cut down as many as you can",
		"break their strength",
		"strike hard and cull their numbers",
		"hunt down a good share of them",
		"bleed their numbers dry",
	},
	KillTarget = {
		"find {target} and end them",
		"cut down {target}",
		"make sure {target} does not leave alive",
		"collect the bounty on {target}",
		"strike down {target} and the rest will scatter",
		"end the reign of {target}",
	},
	KillTargetNoName = {
		"find their leader and end them",
		"cut down their leader",
		"strike down their leader and the rest will scatter",
		"collect the bounty on their leader",
	},
	Survive = {
		"hold out until help arrives",
		"stand your ground for as long as it takes",
		"keep the party alive until relief comes",
		"weather their attacks and hold the line",
		"survive the onslaught",
		"outlast every wave they send",
	},
	Reach = {
		"break through to the marked ground",
		"cut a path to the far side",
		"push through their lines to the guild's marker",
		"reach the signal point",
		"force a way past them",
		"fight your way to the marked spot",
	},
	Activate = {
		"wake the old mechanism",
		"start the ancient device",
		"bring the old machine back to life",
		"set the mechanism working",
		"turn the old wheels once more",
		"rouse the sleeping device",
	},
	Destroy = {
		"smash their {n} war machines",
		"wreck all {n} of their engines",
		"burn their {n} siege works",
	},
	DestroyNoN = {
		"smash their war machines",
		"burn what they have built",
		"leave none of their engines standing",
		"tear down everything they have built",
	},
	Capture = {
		"bring {target} back alive",
		"take {target} alive for the guild's questions",
		"capture {target} without killing them",
		"drag {target} back for questioning",
	},
	CaptureNoName = {
		"bring their leader back alive",
		"take their leader alive for the guild's questions",
		"capture their leader without killing them",
	},
	Protect = {
		"see the Guild Courier safely through",
		"keep the Guild Courier breathing",
		"guard the Guild Courier with your lives",
		"make sure the Guild Courier gets through",
		"shield the Guild Courier from harm",
	},
	Prevent = {
		"stop their runners at the edge",
		"let no runner slip away",
		"cut off their messengers",
		"keep word from reaching their masters",
		"catch every runner as they flee",
		"hold the edges so none get through",
	},
}
local G_GOAL_LEADS = { "", "Your orders: ", "The task is simple: ", "The contract is clear: ", "The guild asks one thing: " }
local G_TAILS_ACTION: { [string]: { string } } = {
	generic = {
		"",
		" before more of them arrive",
		" before the trail goes cold",
		" and report back to the guild",
		" while there is still light",
		" before word spreads",
	},
	urgent = {
		" before it is too late",
		" and do it quickly",
		" before nightfall",
		" with no time to spare",
	},
	covert = {
		" and keep it quiet",
		" without drawing attention",
		" before anyone notices",
	},
	sacred = {
		" before the old powers stir",
		" before the old seals break",
	},
	dread = {
		", and do not end like the last party",
		" where the last party failed",
	},
}
local G_TAILS_HOLD: { [string]: { string } } = {
	generic = {
		"",
		", whatever it costs",
		", no matter what comes",
		" and do not break",
	},
	urgent = {
		", and pray they tire first",
		" with everything you have",
	},
	covert = {
		" and keep your heads down",
	},
	sacred = {
		" beneath the eyes of old powers",
	},
	dread = {
		" where the last party fell",
		", and do not end like the last party",
	},
}
local G_HOLD: { [string]: boolean } = { Survive = true, Protect = true }
local G_MOOD: { [string]: string } = { Desperate = "urgent", Fierce = "urgent", Hidden = "covert", Silent = "covert", Sacred = "sacred", Ancient = "sacred", Dark = "dread", Burning = "dread", Frozen = "dread", Lost = "dread" }
local G_COND_IMG: { [string]: { string } } = {
	Rain = {
		"Rain lashes down",
		"A cold rain has not let up for days",
		"Heavy rain hangs over everything",
	},
	Heatwave = {
		"The heat is fierce today",
		"The sun beats down without mercy",
		"The air shimmers with heat",
	},
	["Strong Wind"] = {
		"A hard wind tears across the land",
		"Gusts howl without pause",
		"The wind will not settle",
	},
	Thunderstorm = {
		"Thunder rolls overhead",
		"A storm breaks overhead",
		"Lightning splits the sky",
	},
	["Meteor Storm"] = {
		"Fire falls from the sky",
		"Burning stones streak down from above",
		"The sky itself rains flame",
	},
	["Volcanic Eruptions"] = {
		"The mountain is waking",
		"Lava spills from fresh cracks",
		"The ground heaves and spits fire",
	},
	["Holy Aurora"] = {
		"A strange light blesses the field",
		"Bright ribbons of light dance overhead",
		"A holy glow lingers in the air",
	},
	["Wild Growth"] = {
		"Vines creep over everything",
		"The plants grow wild and fast",
		"Roots burst up from the ground",
	},
	["Hunger Virus"] = {
		"A sickness spreads through the area",
		"A hungry plague hangs in the air",
		"The sick wander in a daze",
	},
	Earthquake = {
		"The earth shakes without warning",
		"Tremors roll through the ground",
		"The ground splits and shifts",
	},
	["Snow Storm"] = {
		"Snow falls thick and fast",
		"A blizzard swallows everything",
		"Snow blinds anyone who looks up",
	},
	["Severe Hail"] = {
		"Hail hammers down from a black sky",
		"Hailstones the size of fists fall",
		"Hail rattles off every shield",
	},
	["Mana Storm"] = {
		"Wild magic crackles in the air",
		"The weave of magic is torn here",
		"Raw mana storms through the air",
	},
	["Dark Eclipse"] = {
		"The sun is swallowed by shadow",
		"A black eclipse darkens the land",
		"Darkness falls in the middle of the day",
	},
}
local G_COND_CON: { [string]: { string } } = {
	Rain = {
		"the ground turns to mud",
		"boots and bowstrings soak through",
		"footing will be poor",
	},
	Heatwave = {
		"the unwary will tire fast",
		"water will run short",
		"armour bakes those who wear it",
	},
	["Strong Wind"] = {
		"arrows will not fly true",
		"shouted orders are lost in the noise",
		"every banner strains at its pole",
	},
	Thunderstorm = {
		"mind the open ground",
		"metal draws the strikes",
		"the flashes blind the careless",
	},
	["Meteor Storm"] = {
		"do not stand still",
		"keep moving and keep apart",
		"no spot is safe for long",
	},
	["Volcanic Eruptions"] = {
		"watch where you step",
		"safe ground shrinks by the hour",
		"fire may cut off any path",
	},
	["Holy Aurora"] = {
		"some take it as a good omen",
		"the faithful take heart",
		"even the enemy seems uneasy",
	},
	["Wild Growth"] = {
		"paths close as you watch",
		"the green hides much",
		"nothing stays where you left it",
	},
	["Hunger Virus"] = {
		"keep your rations close",
		"do not let it reach your party",
		"the weak will falter first",
	},
	Earthquake = {
		"keep your footing",
		"the high ground may not hold",
		"loose rock falls at any moment",
	},
	["Snow Storm"] = {
		"the cold bites deep",
		"tracks vanish within moments",
		"the far side is lost from view",
	},
	["Severe Hail"] = {
		"find cover where you can",
		"even armour rings under it",
		"the ground is slick with ice",
	},
	["Mana Storm"] = {
		"spells may not behave",
		"casters feel it in their bones",
		"nothing magical is certain",
	},
	["Dark Eclipse"] = {
		"keep your scouts close",
		"shapes move at the edge of sight",
		"the dark favours the enemy",
	},
}
local G_COND_OTHER_IMG = { "Strange weather hangs over the area" }
local G_COND_OTHER_CON = { "keep your scouts close", "trust nothing you see" }
local G_COND_OVERRIDE: { [string]: { string } } = {
	["Heatwave|Tundra"] = {
		"A strange warmth melts the snow",
		"The ice sweats under an odd heat",
	},
	["Heatwave|Desert"] = {
		"Even for a desert, the heat is cruel",
	},
	["Earthquake|Cave"] = {
		"The cave roof groans and sheds stones",
	},
	["Snow Storm|Cave"] = {
		"Snow blows in through the cave mouths",
	},
	["Rain|Swamp"] = {
		"The marsh swells under heavy rain",
	},
	["Volcanic Eruptions|Volcano"] = {
		"The mountain is waking",
	},
}
local G_JOIN = { ", and ", "; " }
local G_IMPER: { [string]: boolean } = { ["do not let it reach your party"] = true, ["do not stand still"] = true, ["find cover where you can"] = true, ["keep moving and keep apart"] = true, ["keep your footing"] = true, ["keep your rations close"] = true, ["keep your scouts close"] = true, ["mind the open ground"] = true, ["trust nothing you see"] = true, ["watch where you step"] = true }
local G_STOP: { [string]: boolean } = {}
for _, w in { "about", "after", "again", "also", "been", "before", "could", "does", "down", "each", "even", "every", "from", "have", "into", "just", "many", "more", "most", "much", "once", "only", "onto", "other", "over", "should", "some", "still", "than", "that", "their", "them", "then", "there", "these", "they", "this", "those", "under", "until", "upon", "very", "were", "what", "when", "where", "which", "while", "will", "with", "would", "your" } do G_STOP[w] = true end

local function gCap(s: string): string
	return string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2)
end

local function gPick(rng: Random, list: { string }): string
	return list[rng:NextInteger(1, #list)]
end

-- True when a content word (4+ letters, not a stop word, crude plural fold) appears twice.
local function gHasRepeat(text: string): boolean
	local seen: { [string]: boolean } = {}
	for raw in string.gmatch(string.lower(text), "[%a']+") do
		local w = string.gsub(raw, "'s$", "")
		w = string.gsub(w, "'", "")
		if #w >= 4 and not G_STOP[w] then
			if #w > 4 and string.sub(w, -1) == "s" then w = string.sub(w, 1, -2) end
			if seen[w] then return true end
			seen[w] = true
		end
	end
	return false
end

local function gMoodOf(name: string): string?
	local n = string.gsub(name, "^Daily Contract:%s*", "")
	local first = string.match(n, "^(%a+)")
	return if first then G_MOOD[first] else nil
end

local function grammarGet(quest: any, placeOfFn: (string) -> string?, hashFn: (string) -> number): string
	if type(quest) ~= "table" then return "" end
	local name = if type(quest.name) == "string" then quest.name else ""
	local rng = Random.new(hashFn(tostring(quest.id or "") .. "|" .. name))
	local gp = if type(quest.goalParams) == "table" then quest.goalParams else {}
	local biome = tostring(quest.biome or "")
	local goal = tostring(quest.goal or "")
	local cond = if type(quest.condition) == "string" then quest.condition else ""
	local place = placeOfFn(name)
	local target = if type(gp.targetName) == "string" and gp.targetName ~= "" then gp.targetName else nil
	local n = tonumber(gp.objects)
	local mood = gMoodOf(name)
	local scenes = G_SCENES[biome]
	local text = ""
	for _ = 1, 8 do
		local parts: { string } = {}
		-- 1. Opening (needs a location and a known biome).
		if place and scenes then
			local sc = gPick(rng, scenes)
			local s = string.gsub(sc, "{place}", function() return place end)
			local forms = { "threat", "bare" } -- 2026-11-18 11:08 PM user: time-of-day leads dropped
			local form = gPick(rng, forms)
			-- 2026-11-18 11:17 PM user: a scene that already has " and " never takes a threat (no double "and").
			if string.find(sc, " and ", 1, true) then form = "bare" end
			if form == "threat" then
				table.insert(parts, gCap(s) .. ", and " .. gPick(rng, G_THREATS[biome]) .. ".")
			else
				table.insert(parts, gCap(s) .. ".")
			end
		end
		-- 2. Goal sentence.
		local key = goal
		if goal == "KillTarget" and not target then key = "KillTargetNoName" end
		if goal == "Capture" and not target then key = "CaptureNoName" end
		if goal == "Destroy" and not (n and n >= 2) then key = "DestroyNoN" end
		local cores = G_GOALS[key]
		if cores then
			local core = gPick(rng, cores)
			-- "all 2 of their engines" -> "both of their engines".
			if n and math.floor(n) == 2 then core = string.gsub(core, "all {n} of", "both of") end
			-- Cores that already end in a full clause ("... and the rest will scatter") take no tail.
			local noTail = string.find(core, "scatter", 1, true) ~= nil
			core = string.gsub(core, "{target}", function() return target or "" end)
			core = string.gsub(core, "{n}", function() return if n then tostring(math.floor(n)) else "" end)
			local lead = gPick(rng, G_GOAL_LEADS)
			local tails = if G_HOLD[goal] then G_TAILS_HOLD else G_TAILS_ACTION
			local pool: { string } = {}
			local hasAnd = string.find(core, " and ", 1, true) ~= nil
			local function addTails(list: { string }?)
				if not list then return end
				for _, t in list do
					local starts = string.match(t, "^[, ]*(%a+)")
					if not (hasAnd and starts == "and") then table.insert(pool, t) end
				end
			end
			if noTail then
				table.insert(pool, "")
			else
				addTails(tails.generic)
				if mood then addTails(tails[mood]) end
			end
			core ..= gPick(rng, pool)
			table.insert(parts, (if lead ~= "" then lead .. core else gCap(core)) .. ".")
		end
		-- 3. Condition sentence (Clear / None / Random show none; unknown -> "other").
		if cond ~= "" and not NO_CONDITION[cond] then
			local imgs: { string } = {}
			for _, x in G_COND_OVERRIDE[cond .. "|" .. biome] or {} do table.insert(imgs, x) end
			for _, x in G_COND_IMG[cond] or G_COND_OTHER_IMG do table.insert(imgs, x) end
			local img = gPick(rng, imgs)
			local con = gPick(rng, G_COND_CON[cond] or G_COND_OTHER_CON)
			local join = if G_IMPER[con] then "; " else gPick(rng, G_JOIN)
			table.insert(parts, img .. join .. con .. ".")
		end
		text = table.concat(parts, " ")
		if not gHasRepeat(text) then return text end
	end
	return text
end

-- Preview / dev only (Studio checks): the v2 text for a quest, whatever the switch says.
function QuestFlavor.GetGrammar(quest: any): string
	return grammarGet(quest, placeOf, hash)
end

function QuestFlavor.Get(quest: any): string
	if type(quest) ~= "table" then return "" end
	if LORE_GRAMMAR_ENABLED then return grammarGet(quest, placeOf, hash) end
	local name = if type(quest.name) == "string" then quest.name else ""
	local rng = Random.new(hash(tostring(quest.id or "") .. "|" .. name))
	local gp = if type(quest.goalParams) == "table" then quest.goalParams else {}
	local objs = tonumber(gp.objects)
	local vals: { [string]: string? } = {
		place = placeOf(name),
		n = if objs then tostring(objs) else nil,
		-- Kill target / Capture cards carry the target's name (QuestGenerator, 2026-11-18 9:50 PM; the
		-- battle unit gets the same name). Older boards / Boss cards have none: {target} lines skip.
		target = if type(gp.targetName) == "string" then gp.targetName else nil,
	}
	local parts: { string } = {}
	-- Always draw both rolls in the same order so each sentence stays stable on its own.
	local opening = pick(rng, BIOME[tostring(quest.biome or "")], vals)
	local goal = pick(rng, GOAL[tostring(quest.goal or "")], vals)
	if opening then table.insert(parts, opening) end
	if goal then table.insert(parts, goal) end
	local cond = if type(quest.condition) == "string" then quest.condition else ""
	if cond ~= "" and not NO_CONDITION[cond] then
		table.insert(parts, CONDITION[cond] or CONDITION_OTHER)
	end
	return table.concat(parts, " ")
end

return QuestFlavor
