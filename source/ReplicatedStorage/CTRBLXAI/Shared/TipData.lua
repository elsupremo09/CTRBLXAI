--!strict
-- TipData.lua
-- CTRBLXAI | New-player tips: the 31 approved tip cards (new_player_tips, USER RULING
-- 2026-11-19 1:45 PM). Text copied VERBATIM from CTRBLXAI.db -- change the DB first, then
-- this file (DAT: one source, frozen). `building` = the BuildingService name whose unlock
-- shows the tip (Town unlock tips). The save stores ids only (save_data_contract SAVE-01).

export type Tip = { id: string, group: string, title: string, text: string, building: string?, order: number }

local RAW = {
	{ id = "TIP-BASE-01", group = "Town", title = "Welcome to your Guild", text = "This is your base. Take quests from the Quest Board, hire at the Tavern, and buy gear at the Merchant." },
	{ id = "TIP-QB-01", group = "Town", title = "Quest Board", text = "Pick a quest to send your party into battle. Higher ranks open harder quests with better rewards." },
	{ id = "TIP-TAV-01", group = "Town", title = "Tavern", text = "Hire new units here. Each race and unit brings different strengths." },
	{ id = "TIP-MER-01", group = "Town", title = "Merchant", text = "Buy and sell gear. Stock changes over time." },
	{ id = "TIP-GH-01", group = "Town", title = "Guild Hall", text = "Upgrade all your buildings from here. Furnish the hall to make it your own." },
	{ id = "TIP-BS-01", group = "Town", title = "Blacksmith opened", text = "Level up your gear here. Higher Blacksmith levels let your gear reach higher levels.", building = "Blacksmith" },
	{ id = "TIP-DIS-01", group = "Town", title = "Dispatch opened", text = "Send idle units on timed jobs. Units on a job can't fight until they're back.", building = "Dispatch" },
	{ id = "TIP-APO-01", group = "Town", title = "Apothecary opened", text = "Buy consumables here. Used charges refill for gold each time you return to base.", building = "Apothecary" },
	{ id = "TIP-RUN-01", group = "Town", title = "Runeforge opened", text = "Add rune gems to your gear. Forging can raise it up to Epic rarity.", building = "Runeforge" },
	{ id = "TIP-TG-01", group = "Town", title = "Training Grounds opened", text = "Buy and sell skill, augment and doctrine cards.", building = "TrainingGrounds" },
	{ id = "TIP-CRU-01", group = "Town", title = "Crucible opened", text = "Combine copies of the same item to make one of the next rarity.", building = "Crucible" },
	{ id = "TIP-DUN-01", group = "Town", title = "Dungeon opened", text = "Run multi-floor dungeons. You can escape anytime, but beating a Boss or leaving from a Rest room keeps all loot.", building = "Dungeon" },
	{ id = "TIP-TRO-01", group = "Town", title = "Trophy Hall opened", text = "Show off the collections you've completed.", building = "TrophyHall" },
	{ id = "TIP-UNIT-01", group = "Unit", title = "Your units", text = "Info shows stats, Gears holds your gear, Skills holds skills. Tap a tab to switch." },
	{ id = "TIP-STAT-01", group = "Unit", title = "Stat points", text = "Your unit has points to spend. Put them into the stats that fit its role." },
	{ id = "TIP-EQP-01", group = "Unit", title = "Equipment", text = "Your weapon decides how hard your skills hit. Heavier gear makes your unit's turns come slower." },
	{ id = "TIP-SKL-01", group = "Unit", title = "Skills", text = "Slot 1 holds your doctrine's skill; slots 2-4 hold skill cards. Watch MP cost and how long each skill delays your next turn." },
	{ id = "TIP-AUG-01", group = "Unit", title = "Augments", text = "Augments attach to a skill and change how it works." },
	{ id = "TIP-DOC-01", group = "Unit", title = "Doctrines", text = "A doctrine shifts your unit's stats, gives a lasting passive, and offers 3 skills to pick from for slot 1." },
	{ id = "TIP-LOCK-01", group = "Unit", title = "Locked slot", text = "This slot opens later. Its card shows how to unlock it." },
	{ id = "TIP-PTY-01", group = "Unit", title = "Parties", text = "Save up to 5 parties of up to 7 units. A quest decides how many units take the field." },
	{ id = "TIP-CON-01", group = "Unit", title = "Consumables", text = "Consumables are used in battle. Used charges refill for gold when you return to base." },
	{ id = "TIP-BAT-01", group = "Battle", title = "Turn order", text = "Faster units act more often. The timeline shows who moves next." },
	{ id = "TIP-BAT-02", group = "Battle", title = "Moving", text = "Tap a highlighted tile to move. Terrain can slow you or protect you." },
	{ id = "TIP-BAT-03", group = "Battle", title = "No misses", text = "Attacks always land. The preview shows exactly what will happen." },
	{ id = "TIP-BAT-04", group = "Battle", title = "High ground", text = "Higher ground lets you see and shoot over more. Some weapons hit harder from above." },
	{ id = "TIP-BAT-05", group = "Battle", title = "Facing", text = "Choose where your unit faces. Some weapons and traits hit harder from behind." },
	{ id = "TIP-BAT-06", group = "Battle", title = "Status effects", text = "Some skills leave lasting effects. Tap a unit to see them." },
	{ id = "TIP-BAT-07", group = "Battle", title = "Charging skills", text = "Some skills take time to charge. Effects like Silence can cancel them, but plain hits can't." },
	{ id = "TIP-BAT-08", group = "Battle", title = "Victory", text = "Rewards go to your inventory. Check your units for new gear and levels." },
	{ id = "TIP-BAT-09", group = "Battle", title = "Unit down", text = "A defeated unit stays down until you return to base, then wakes with 1 HP. Revive skills can bring it back in battle." },
}

local list: { Tip } = {}
local byId: { [string]: Tip } = {}
for i, t in RAW do
	local tip: Tip = table.freeze({
		id = t.id, group = t.group, title = t.title, text = t.text,
		building = (t :: any).building, order = i,
	})
	table.insert(list, tip)
	byId[tip.id] = tip
end

local TipData = {
	List = table.freeze(list),
	ById = table.freeze(byId),
}

function TipData.IsKnown(id: any): boolean
	return type(id) == "string" and byId[id] ~= nil
end

return table.freeze(TipData)
