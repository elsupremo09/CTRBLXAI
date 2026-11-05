# 2026-11-01 FOLLOW-UP: Dev answers to the 3 evening questions, BUG-074, and the 2026-10-31 to-record list. Ops only.
B = "BUILT 2026-11-01 (source-verified by Tester; Studio test pending)"
DD = "DECIDED (DEV DEFAULT) 2026-11-01"
U31 = "RESOLVED (USER) 2026-10-31, BUILT, Studio test pending"
L = "LOCKED - USER DECISION 2026-11-01 (v2)."
DEVQ2 = "Dev-confirmed 2026-11-01 (" + DD + ", follow-up question 2)"

# ---- Q1: budget cap vs ruling 5 ----
GF54_OLD = "A forge result must fit the capacity rarity and BP."
GF54_NEW = ("A forge result must fit the capacity rarity and BP, with the same allowance as row 44 (c): a forge is refused for going over the budget only when "
            "the new total is above both that budget and the item's own total before this forge, so an item may always stay at its own total "
            "(example: a 1H Epic at 215 can be swapped and stay at 215; 216 is refused).")
GF44_OLD = "The result must fit the Runeforge capacity rarity and BP (row 54)."
GF44_NEW = "The result must fit the Runeforge capacity rarity and BP (row 54; the same allowance applies there - an item may always stay at its own total)."
Q1_REASON = (DD + " (follow-up question 1, option A): ruling 5's allowance also applies to the capacity cap - an item may stay at its own total. "
             "Reason: this is what the code already does - the Runeforge refuses a forge for the Epic budget only when the new total is above the higher of the "
             "current rarity's budget and the item's own total. The Tester confirmed a 1H Epic at 215 can be swapped and stay at 215, and 216 is refused.")

# ---- Q2: step-4 rows still saying not built ----
ES18_OLD = "old items = 0; PLANNED \u2014 not built | LOCKED - USER DECISION 2026-11-01 (v2). NOT BUILT."
ES18_NEW = ("old items = 0 | " + L + " " + B + " - v2 step 1 (reroll counter saved on the item); used by the Runeforge sulfur reroll (step 4). " + DEVQ2 + ".")
ES19_OLD = "items saved before this is built get their current rarity; PLANNED \u2014 not built | LOCKED - USER DECISION 2026-11-01 (v2). NOT BUILT."
ES19_NEW = ("items saved before this is built get their current rarity | " + L + " " + B + " - v2 step 1 (starting rarity saved on the item); checked on load (step 4). " + DEVQ2 + ".")
SB18_SYS_OLD = "Runeforge Service (PLANNED \u2014 not built)"
SB18_SYS_NEW = "Runeforge Service (BUILT 2026-11-01, Studio test pending)"
SB18_FB_OLD = L + " NOT BUILT. [Superseded"
SB18_FB_NEW = (L + " " + B + " - v2 step 4 (" + DEVQ2 + "; the built service names its calls differently from Primary_Interface, e.g. PlanForge and CommitReroll). [Superseded")
SD3_PF_OLD = "authored roll data; PLANNED \u2014 not built (v2):"
SD3_PF_NEW = "authored roll data; " + B + " (v2; saved fields rf / rc / sr, steps 1 and 4; " + DEVQ2 + "):"
SD3_LV_OLD = "PLANNED \u2014 not built: forged items may hold"
SD3_LV_NEW = "starting rarity checked on load - " + B + " (v2 step 4); not yet confirmed as built: forged items may hold"
SD3_MR_OLD = "PLANNED \u2014 not built: after forging or rerolling"
SD3_MR_NEW = B + " (v2 steps 1 and 4; " + DEVQ2 + "): after forging or rerolling"
SD3_FB_OLD = "the other Runeforge parts of this row (reroll_count, forged-item load check) are not yet confirmed as built."
SD3_FB_NEW = ("reroll_count and starting_rarity " + B + " - v2 steps 1 and 4 (" + DEVQ2 + "); the forged-item budget check on load is not yet confirmed as built.")
GF49_NOTE = ("Follow-up 2026-11-01 (" + DD + ", question 2): the Runeforge's forging costs - crystals (row 43), forge / swap fee (row 55) and levelling catch-up (row 48) - are "
             + B + " (v2 step 4). This row is the gold price of the Runeforge's own levels: buying facility levels is Slice 8 (row 39), so this price table stays NOT BUILT; "
             "today the Runeforge level changes only through the Studio test controls.")

# ---- Q3 + PART 2: Salvager's Cap ----
BUG074 = ("BUG-074 fixed 2026-11-01, Studio test pending: chest and salvage gear rewards (Treasure Chest, Cursed Chest, Salvager's Cap) could silently not be granted in a "
          "later battle of the same Play session - the reward id used the map object id, which restarts on every map, and the reward service refuses ids it has already "
          "seen. Fix: a session-wide counter. Tester re-check running.")
NW34_ST_OLD = "code written 2026-11-01, Tester source check running.]"
NW34_ST_NEW = "code written 2026-11-01; the Tester source check found BUG-074 (fixed 2026-11-01, Studio test pending); Tester re-check running.]"
Q3 = ("Salvager's Cap BP stays 50 - " + DD + " (follow-up question 3): recheck it in the next balance pass (Simulator). Reason: the reward is smaller than the old "
      "full chest roll, but the passive also adds a reason to break objects; a BP change belongs in a balance pass, not a guess.")
MS14_OLD = "New Salvager's Cap reward (ruling 4): code written 2026-11-01, Tester source check running - not yet verified."
MS14_NEW = ("New Salvager's Cap reward (ruling 4): code written 2026-11-01; the Tester source check found BUG-074 (salvage gear could silently not be granted in a later "
            "battle of the same Play session) - fixed 2026-11-01, Studio test pending; Tester re-check running - not yet verified.")
IP53_OLD = "Salvager's Cap new reward (materials_system 14): code written, Tester source check running."
IP53_NEW = ("Salvager's Cap new reward (materials_system 14): code written; BUG-074 (chest and salvage gear rewards could be silently skipped in a later battle of the "
            "same Play session) fixed 2026-11-01, Studio test pending; Tester re-check running.")

# ---- PART 3: 2026-10-31 user rulings ----
LU84_ADD = ("Exception (" + U31 + "): on the Merchant, Tavern, Blacksmith and Runeforge screens the + / \u2212 (add / remove) buttons are square icon buttons instead of bar buttons.")
LU85_ADD = ("Scope note (" + U31 + "): the square + / \u2212 icon buttons on the Merchant, Tavern, Blacksmith and Runeforge screens (id 84) are icon buttons, not bar buttons.")
LU75_ADD = ("Guild building screens (" + U31 + "): Back sits at the lower right, in one row with all the other buttons - unlike the Loadout screen's top-right Back.")
LU32_ADD = ("Armor HP and MP are shown on both the Loadout and the Merchant item inspector (" + U31 + ").")
SD1_ADD = ("Guild menu records saved with the guild progression (next to the building levels, guild_facilities 39) - " + U31 + ": "
           "guildMenu.merchantBought (per-shelf Merchant purchase records, newest 12 shelves; BUG-064); "
           "guildMenu.devShopRefresh (Studio-only dev shop refresh number); "
           "guildMenu.tavernHired (hired recruits remembered per Tavern seed; BUG-067).")

# (table, rowid, column, mode, a, b)   mode: set (a = expected full old), rep (a -> b exactly once), app (append b with separator a)
OPS = [
 ('guild_facilities', 54, 'rule', 'rep', GF54_OLD, GF54_NEW),
 ('guild_facilities', 54, 'notes', 'app', ' | ', Q1_REASON + ' [Superseded 2026-11-01 (follow-up): rule (part): ' + GF54_OLD + ']'),
 ('guild_facilities', 44, 'rule', 'rep', GF44_OLD, GF44_NEW),
 ('guild_facilities', 44, 'notes', 'app', ' | ', Q1_REASON + ' [Superseded 2026-11-01 (follow-up): rule (part): ' + GF44_OLD + ']'),

 ('equipment_schema', 18, 'Validation', 'rep', ES18_OLD, ES18_NEW),
 ('equipment_schema', 18, 'Validation', 'app', ' ', '[Superseded 2026-11-01 (follow-up build status): Validation (part): ' + ES18_OLD + ']'),
 ('equipment_schema', 19, 'Validation', 'rep', ES19_OLD, ES19_NEW),
 ('equipment_schema', 19, 'Validation', 'app', ' ', '[Superseded 2026-11-01 (follow-up build status): Validation (part): ' + ES19_OLD + ']'),
 ('service_boundaries', 18, 'System', 'set', SB18_SYS_OLD, SB18_SYS_NEW),
 ('service_boundaries', 18, 'Failure_Boundary', 'rep', SB18_FB_OLD, SB18_FB_NEW),
 ('service_boundaries', 18, 'Failure_Boundary', 'app', ' ', '[Superseded 2026-11-01 (follow-up build status): System: ' + SB18_SYS_OLD + '; Failure_Boundary (part): ' + L + ' NOT BUILT.]'),
 ('save_data_contract', 3, 'Persistent_Fields', 'rep', SD3_PF_OLD, SD3_PF_NEW),
 ('save_data_contract', 3, 'Load_Validation', 'rep', SD3_LV_OLD, SD3_LV_NEW),
 ('save_data_contract', 3, 'Migration_Rule', 'rep', SD3_MR_OLD, SD3_MR_NEW),
 ('save_data_contract', 3, 'Failure_Behavior', 'rep', SD3_FB_OLD, SD3_FB_NEW),
 ('save_data_contract', 3, 'Failure_Behavior', 'app', ' ', '[Superseded 2026-11-01 (follow-up build status): Persistent_Fields (part): ' + SD3_PF_OLD
     + ' | Load_Validation (part): ' + SD3_LV_OLD + ' | Migration_Rule (part): ' + SD3_MR_OLD + ' | Failure_Behavior (part): ' + SD3_FB_OLD + ']'),
 ('guild_facilities', 49, 'notes', 'app', ' | ', GF49_NOTE),

 ('nonweapon_equipment', 34, 'rule', 'rep', NW34_ST_OLD, NW34_ST_NEW),
 ('nonweapon_equipment', 34, 'rule', 'app', ' ', '[' + BUG074 + '] [' + Q3 + '] [Superseded 2026-11-01 (follow-up): ' + NW34_ST_OLD + ']'),
 ('objects_encounters', 20, 'col_9', 'app', ' | ', BUG074),
 ('objects_encounters', 22, 'col_9', 'app', ' | ', BUG074),
 ('materials_system', 14, 'notes', 'rep', MS14_OLD, MS14_NEW),
 ('materials_system', 14, 'notes', 'app', ' | ', Q3 + ' [Superseded 2026-11-01 (follow-up): ' + MS14_OLD + ']'),
 ('implementation_plan', 53, 'col_2', 'rep', IP53_OLD, IP53_NEW),
 ('implementation_plan', 53, 'col_2', 'app', ' ', '[Superseded 2026-11-01 (follow-up): ' + IP53_OLD + ']'),

 ('loadout_ui_spec', 84, 'rule', 'app', ' ', LU84_ADD),
 ('loadout_ui_spec', 84, 'notes', 'app', ' | ', U31 + ': square + / \u2212 icon buttons on the guild building screens (Merchant, Tavern, Blacksmith, Runeforge).'),
 ('loadout_ui_spec', 85, 'notes', 'app', ' | ', LU85_ADD),
 ('loadout_ui_spec', 75, 'rule', 'app', ' ', LU75_ADD),
 ('loadout_ui_spec', 75, 'notes', 'app', ' | ', U31 + ': guild building screens put Back lower-right with the other buttons (one row); the Loadout screen keeps its top-right Back.'),
 ('loadout_ui_spec', 32, 'rule', 'app', ' ', LU32_ADD),
 ('save_data_contract', 1, 'Persistent_Fields', 'app', '; ', SD1_ADD),
]
