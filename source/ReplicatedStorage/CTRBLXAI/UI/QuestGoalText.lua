--!strict
-- QuestGoalText (quest goals build step 8, 2026-11-17): the ONE place for the quest main-goal
-- player text (DAT-001). Every line here is APPROVED text from docs\CTRBLXAI.db game_flow 41
-- ("23 text lines verbatim", USER 2026-11-17 7:25 PM; list in DRAFT_quest_goals_20261117.md
-- section 5) and game_flow 39 line 17 ("Goal: {goal}" with the 1-word labels). Do not add
-- wording here without a user approval.
--
-- Input is the data table QuestGoalService.Describe sends (Map Details / QuestGoalUpdate /
-- RewardScreen): { id, round, rounds, progress, total, targetName, npcName, reached, lossAt,
-- verdict, ... }. Every function is nil-safe and returns "" when it has nothing to say.

local QuestGoalText = {}

-- Approved object name shown to players for the Activate goal object (game_flow 41 line 22).
-- The build reuses the Obelisk model / data; players never see "Obelisk" for it.
QuestGoalText.ActivateObjectName = "Ancient Mechanism"
-- Approved Protect NPC name (line 21) and the tag over the Capture target / Protect NPC (line 20).
QuestGoalText.ProtectNpcName = "Guild Courier"
QuestGoalText.TargetTag = "Target"

-- 1-word card labels (line 23 / game_flow 39 line 17). Goal ids are QuestGoalData ids.
local LABELS: { [string]: string } = {
	WipeOut = "Wipe out",
	Survive = "Survive",
	Capture = "Capture",
	Destroy = "Destroy",
	Slay = "Slay",
	KillTarget = "Assassinate",
	Protect = "Protect",
	Reach = "Reach",
	Prevent = "Hold the line",
	Activate = "Activate",
}

local function num(v: any): number?
	local n = tonumber(v)
	return n
end

local function str(v: any, fallback: string): string
	if type(v) == "string" and v ~= "" then return v end
	return fallback
end

function QuestGoalText.Label(goalId: any): string
	if type(goalId) ~= "string" then return "" end
	return LABELS[goalId] or ""
end

-- Card / briefing line: "Goal: {goal}" (game_flow 39 line 17, line 1 of row 41).
function QuestGoalText.CardLine(goalId: any): string
	local label = QuestGoalText.Label(goalId)
	if label == "" then return "" end
	return "Goal: " .. label
end

-- Goal sentence (row 41 lines 2-11). Returns "" when a needed name / number is missing, so no
-- unapproved filler word ever shows (the tracker then stays hidden).
function QuestGoalText.Sentence(d: any): string
	if type(d) ~= "table" or type(d.id) ~= "string" then return "" end
	local id = d.id
	local function n(v: any): string? local x = num(v); return if x then tostring(x) else nil end
	local function s(v: any): string? return if type(v) == "string" and v ~= "" then v else nil end
	if id == "WipeOut" then
		return "Defeat all enemies."
	elseif id == "Survive" then
		local r = n(d.rounds); return if r then `Survive {r} rounds.` else ""
	elseif id == "Capture" then
		local nm = s(d.targetName); return if nm then `Capture {nm}. Bring it to 1 HP, then use Interact.` else ""
	elseif id == "Destroy" then
		local c = n(d.total); return if c then `Destroy the {c} marked objects.` else ""
	elseif id == "Slay" then
		local c = n(d.total); return if c then `Defeat {c} enemies.` else ""
	elseif id == "KillTarget" then
		local nm = s(d.targetName); return if nm then `Defeat {nm}.` else ""
	elseif id == "Protect" then
		return `Protect {str(d.npcName, QuestGoalText.ProtectNpcName)}. If they fall, the quest fails.`
	elseif id == "Reach" then
		local r = n(d.rounds); return if r then `Reach the marked area within {r} rounds.` else ""
	elseif id == "Prevent" then
		local c = n(d.lossAt); return if c then `Stop the runners. If {c} reach the marked area, the quest fails.` else ""
	elseif id == "Activate" then
		local r = n(d.rounds); return if r then `Activate the {QuestGoalText.ActivateObjectName} within {r} rounds.` else ""
	end
	return ""
end

-- Live tracker progress (row 41 lines 12-15). "" for goals without a counter.
function QuestGoalText.Progress(d: any): string
	if type(d) ~= "table" then return "" end
	local id = d.id
	if id == "Survive" or id == "Reach" or id == "Activate" then
		local n = num(d.rounds)
		if not n then return "" end
		local a = math.clamp(num(d.round) or 1, 1, n)
		return `Round {a} / {n}`
	elseif id == "Destroy" then
		local n = num(d.total)
		if not n or n <= 0 then return "" end
		return `{num(d.progress) or 0} / {n} destroyed`
	elseif id == "Slay" then
		local n = num(d.total)
		if not n then return "" end
		return `{math.min(num(d.progress) or 0, n)} / {n} defeated`
	elseif id == "Prevent" then
		local n = num(d.lossAt)
		if not n then return "" end
		return `Runners through: {num(d.reached) or 0} / {n}`
	end
	return ""
end

-- Defeat-screen line when the GOAL caused the loss (row 41 lines 17-19). "" when the loss was
-- the normal all-units-down rule or the goal has no loss line of its own.
function QuestGoalText.LossLine(d: any): string
	if type(d) ~= "table" or d.verdict ~= "Loss" then return "" end
	local id = d.id
	if id == "Protect" then
		return `{str(d.npcName, QuestGoalText.ProtectNpcName)} has fallen.`
	elseif id == "Reach" or id == "Activate" then
		return "Time ran out."
	elseif id == "Prevent" then
		return "Too many runners got through."
	end
	return ""
end

return QuestGoalText
