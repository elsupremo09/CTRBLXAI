# 2026-11-01 DAILY SYSTEMS (USER DECISION, locked). Ops only.
# (table, rowid, column, mode, a, b)  mode: set (a = expected full old), rep (a -> b exactly once), app (append b with separator a)
def R(n): return "RESOLVED (USER) 2026-11-01 (daily systems, decision " + n + ")"
NB = "NOT BUILT."
DEVC = "Dev-confirmed 2026-11-01 (daily systems)"
SUP = "[Superseded 2026-11-01 (daily systems): "
INPROG = "IN PROGRESS: the Dev is building this now (2026-11-01); it replaces the 2026-11-01 'chest loot listed on the defeat screen' change. Not yet verified."
HELD = ("chest and salvage loot is HELD until the battle ends, like stolen loot (project_rules 236). Items, cards and mercury are given only on a qualifying victory "
        "and are lost on a defeat or escape. Chest / salvage gold is added to the battle gold, so a defeat keeps 50% of it (unit_progression 92).")

# ---------- day, daily contract, save ----------
LSF11_OLD = "Post-launch feature. May integrate with Slice 8 quest board or as separate event system."
LSF11_NEW = ("Daily events = the Daily Contract (v2 build step 6). A 'day' is a real day that resets at 00:00 UTC, read from the server clock only (never the "
             "device clock); if the server's day reads earlier than the saved day, nothing resets (decision 1). One Daily Contract card a day, pinned to the "
             "quest board (it does not use a board slot): a normal battle at the board's usual level, made from a fixed daily seed, so refreshing the board "
             "cannot change it; never a boss or an elite. Winning it completes it (decision 4). One per day (decision 5). Reward: the normal quest rewards + "
             "5 mercury, and 1 sulfur on every 3rd completion (lifetime count, materials_system 13). A missed day is gone, with no penalty; a lost contract "
             "can be retried the same day (decision 6). The quest board shows a 'New day in Xh Ym' timer; the counters are saved with the currencies "
             "(decision 3, save_data_contract 3).")
LSF11_NOTE = ("RESOLVED (USER) 2026-11-01 (daily systems, decisions 1, 3, 4, 5, 6). " + NB + " Status refreshed (G6): no longer a post-launch feature - part of "
              "v2 build step 6. Standard details from the accepted proposal (DECIDED (DESIGNER DEFAULT) 2026-11-01): a contract accepted before the reset "
              "still counts for the day it was accepted; abandoning it follows the normal 50% rule (game_flow 28, quest gold only); the 5 mercury and the "
              "sulfur progress are paid only on completion; the reset is checked when the profile loads, on each return to base and at battle end - never "
              "in the middle of a battle; the reset time is shown in the player's local time (display only). " + SUP + "rule: " + LSF11_OLD + "]")
LSF10_NOTE = ("Status checked 2026-11-01 (daily systems, G6): seasonal events stay post-launch. Daily events are no longer post-launch (row 11, v2 build "
              "step 6); seasonal events should later reuse the same server-clock day (row 11).")
LSF12_OLD = "Item leveling: System design DEFERRED (not in Slice 6). Functional owner TBD. To be designed in a later pass; excluded from initial content expansion build."
LSF12_NEW = ("Item levelling: designed and LOCKED 2026-11-01 (Blacksmith + Runeforge v2: 1 mercury + gold per level, free downgrades; guild_facilities 40, "
             "41, 47). Owner: the Blacksmith. BUILT 2026-11-01 (v2 steps 2-3; source-verified by Tester; Studio test pending; implementation_plan 53).")
LSF12_NOTE = "Status refreshed 2026-11-01 (daily systems, G6). " + SUP + "rule: " + LSF12_OLD + "]"
LSF4_NOTE = R("4") + ": a daily event = one Daily Contract a day, pinned to the quest board (row 11). " + NB

MS13_OLD = "Daily events per lifetime = WORKING ESTIMATE (gap G3); budget per 10 events: +50 mercury, +3.3 sulfur."
MS13_NEW = ("Daily events per lifetime = WORKING ESTIMATE (gap G3): about 80 Daily Contracts (range 30-180), about +400 mercury and +27 sulfur "
            "(" + R("7") + "); budget per 10 events: +50 mercury, +3.3 sulfur. A daily event = one Daily Contract a day (live_service_features 11).")
MS13_NOTE = ("RESOLVED (USER) 2026-11-01 (daily systems, decisions 4-7): one Daily Contract a day, missed days are gone; G3 working estimate about 80. "
             + NB + " " + SUP + "rule (part): " + MS13_OLD + "]")
MS36_NOTE = ("WORKING ESTIMATE (daily systems 2026-11-01, decision 7): about 80 Daily Contracts per lifetime (range 30-180) add about +400 mercury "
             "(range +150 to +900) and about +27 sulfur (range +10 to +60). Re-run PENDING (Simulator): lifetime mercury against the 15-20 levelling "
             "target (guild_facilities 38) - at 80 it comes out about 1,950-2,250 mercury, about 20-23 levellings.")
UP84_NOTE = R("4") + ": one Daily Contract a day (live_service_features 11). " + NB
OD124_OLD = "(2) daily events per lifetime (G3);"
OD124_NEW = "(2) daily events per lifetime (G3: about 80, range 30-180 - " + R("7") + ");"

SD3_PF_OLD = "daily_events_completed (lifetime count, never resets - every 3rd gives 1 sulfur)"
SD3_PF_NEW = (SD3_PF_OLD + "; daily counters (" + R("3") + "; " + NB[:-1] + "): last day processed (whole days since a fixed start date, server clock), "
              "today's Daily Contract (which card, done or not) and boss rewards used today (0-3). The lifetime count never resets")
SD3_LV_ADD = ("; daily counters (" + NB[:-1] + ", daily systems decision 1): only the server clock counts; if the server's day reads earlier than the "
              "saved last day, nothing resets")
SD3_FB_ADD = SUP + "Persistent_Fields (part): " + SD3_PF_OLD + "]"
SD1_FB_ADD = ("PRE-MULTIPLAYER SAFETY ITEM (" + DEVC + "): the save does NOT stop two servers loading the same player at once, and the 3 save slots are "
              "written one after another, not in one atomic step. Must be fixed before multiplayer / public launch (risk: duplicated or rolled-back "
              "rewards). This is why the daily counters sit in slot 2 next to the currencies they limit (save_data_contract 3). " + NB)

DISP = (R("2") + ": the player-facing wording says 'battles' instead of 'days' (for example 'Back after 3 battles'; a very long battle can count as 2). "
        "Only the wording changes: the 4000 CT rule and all dispatch numbers are unchanged. On screen, 'Day' / 'Daily' now means the real day "
        "(live_service_features 11). " + NB)
DISP_S = R("2") + ": the player-facing wording says 'battles' instead of 'days' - see unit_progression 77. " + NB

# ---------- boss limit ----------
MS9_OLD = ("ON HOLD - RESOLVED (USER) 2026-11-01 (ruling 1): not built until a daily boss reward limit system exists in the game (there is no day counter "
           "yet). Reason: without the limit, bosses could be replayed for unlimited crystals.")
MS9_NEW = ("Counts toward the 3-per-day boss reward limit (loot_progression 15): given only for the first 3 rewarded boss wins per day (" + R("8")
           + " - this lifts the ruling 1 hold).")
MS9N_OLD = "NOT BUILT - ON HOLD (RESOLVED (USER) 2026-11-01, ruling 1; see loot_progression 15)."
MS9N_NEW = "NOT BUILT (hold lifted 2026-11-01 by daily systems decision 8; see loot_progression 15)."
MS41_OLD = ("Boss - ON HOLD (RESOLVED (USER) 2026-11-01, ruling 1: not built until a daily boss reward limit system exists in the game - there is no day "
            "counter yet - because without the limit bosses could be replayed for unlimited crystals; once built it counts toward the 3-per-day boss "
            "reward limit, loot_progression 15):")
MS41_NEW = ("Boss (counts toward the 3-per-day boss reward limit, loot_progression 15 - given only for the first 3 rewarded boss wins per day; "
            + R("8") + ", lifts the ruling 1 hold):")
MS41N_OLD = "boss part - ON HOLD (ruling 1)."
MS41N_NEW = "boss part - hold lifted (daily systems decision 8), NOT BUILT; elite encounters now defined (loot_progression 69, 70), still NOT BUILT."
LP15_OLD = "Default boss reward limit = first 3 rewarded boss completions per day."
LP15_NEW = ("Default boss reward limit = first 3 rewarded boss wins per day (real day, reset 00:00 UTC); it covers the guaranteed item and the boss "
            "grants (materials_system 9, 41).")
LP15_NOTE = ("RESOLVED (USER) 2026-11-01 (daily systems, decisions 1, 8, 9): a 'day' = a real day, reset at 00:00 UTC, server clock only. The first 3 "
             "rewarded boss WINS per day get the guaranteed item AND the boss grants (3 mercury, 5 crystals, 1 rune gem, 1 sulfur at L60+; "
             "materials_system 9, 41) - one combined 'boss reward', counted when the battle ends. After that, bosses stay playable (normal kill loot, "
             "gold, XP and quest rewards) without those rewards. Normal quest rewards are never limited. This lifts the ruling 1 hold. A boss summoned "
             "by the Herald event (battlefield_events 12) counts toward the 3 once that feature exists. The quest board shows 'Boss rewards left today: "
             "N/3'. " + NB + " " + SUP + "rule (part): " + LP15_OLD + "]")
LP25_OLD = "Default boss reward limit: first 3 rewarded boss completions per day."
LP25_NEW = "Default boss reward limit: first 3 rewarded boss wins per day (real day, reset 00:00 UTC; row 15)."
LP25_NOTE = R("8") + ". " + NB + " " + SUP + "rule (part): " + LP25_OLD + "]"
IP53_OLD = "boss grants (materials_system 9, 41, loot_progression 15 - ON HOLD until a daily boss reward limit exists)"
IP53_NEW = ("boss grants (materials_system 9, 41, loot_progression 15 - hold lifted 2026-11-01: they count toward the 3-per-day boss reward limit, "
            "which is NOT BUILT); daily systems (RESOLVED (USER) 2026-11-01: real-day clock, Daily Contract, boss reward limit, elite encounters - all "
            "NOT BUILT; chest / salvage loot held until the battle ends - IN PROGRESS, Dev building 2026-11-01)")

# ---------- elites ----------
PR38_OLD = "Locked / Appearance rate pending"
PR38_NEW = ("Locked / Appearance: a hidden 3.4% roll on each normal quest card, about 0.034 per battle = WORKING ESTIMATE (RESOLVED (USER) 2026-11-01, "
            "daily systems decisions 10-11; NOT BUILT; loot_progression 69)")
LP69_OLD = "Exact appearance rate remains pending unless defined elsewhere."
LP69_NEW = ("How they appear (" + R("10") + "): when the quest board makes each NORMAL quest card, it rolls a hidden 3.4% chance for that card to be an "
            "elite encounter; the result is fixed on the card and revealed at the departure briefing ('Scouts report an elite war band!'); backing out "
            "does not re-roll it. Not on boss cards, the Daily Contract, dispatch or arena; each battle of an Explore expedition rolls separately. Elites "
            "can appear from the start (no facility gate, decision 13). Rate about 0.034 per battle = WORKING ESTIMATE (decision 11). Never elite "
            "encounters (decision 14): the Elite Mimic (objects_encounters 21), the Champion event (battlefield_events 6) and elite-tier enemies inside "
            "normal quests.")
LP69_NOTE = ("RESOLVED (USER) 2026-11-01 (daily systems, decisions 10, 11, 13, 14). " + NB + " Build note (" + DEVC + "): today the quest board is "
             "regenerated on every return to base; backing out of a departure briefing must keep the same card, or an elite could be dodged by backing "
             "out. " + SUP + "rule (part): " + LP69_OLD + "]")
LP26_NOTE = ("RESOLVED (USER) 2026-11-01 (daily systems, decisions 10-12): elite encounters = a hidden 3.4% roll on each normal quest card (row 69); "
             "about 0.034 per battle stays the WORKING ESTIMATE. " + NB)
LP70_NOTE = ("RESOLVED (USER) 2026-11-01 (daily systems, decision 12): completed = winning the battle. Elite package: 6 enemies (row 86) led by an Elite "
             "Leader (the existing Elite-tier build, at the quest's level), the existing 'defeat the leader in N turns' objective (unit_progression 64), "
             "this elite reward chance (75% x Fortune, max 95%, Mythic-max table, row 71), the fixed grants (2 mercury, 3 crystals, 50% 1 rune gem, "
             "25% 1 sulfur at L60+; materials_system 8, 41) and 200 Guild XP (row 74). A defeat gives none of the elite rewards. " + NB)
LP86_NOTE = "Elite 6 confirmed for elite encounters (" + R("12") + "). " + NB
LP74_NOTE = "Elite = 200 Guild XP for a won elite encounter (" + R("12") + "). " + NB
UP64_NOTE = "Used by elite encounters: 'defeat the Elite Leader within N turns' (" + R("12") + "). " + NB
MS8_NOTE = ("RESOLVED (USER) 2026-11-01 (daily systems, decisions 10-12): elite encounters are now defined (loot_progression 69, 70); this grant is given "
            "when an elite encounter is won. Still " + NB)

GF17_OLD = "L5: Elite quests."
GF17_NEW = ("L5: Hard quests (more elite-tier enemies, normal loot table; not elite encounters - those can appear from the start, loot_progression 69).")
GF17_NOTE = (R("13") + ": 'Elite quests' renamed 'Hard quests'. " + NB + " " + DEVC + ": the code has no Quest Board level gate for boss quests - about "
             "1 card in 10 is a boss quest from the start; this does not match 'L8: Boss quests' (open for a user decision). " + SUP + "rule (part): "
             + GF17_OLD + "]")
UP71T_OLD = "Elite battle"
UP71T_NEW = "Hard battle"
UP71_OLD = "Contains elite enemies. Higher XP per kill."
UP71_NEW = ("Contains elite-tier enemies (taken from the quest difficulty roster). Higher XP per kill. Normal loot table. Unlocked at Quest Board L5 "
            "(guild_facilities 17). Not an elite encounter (loot_progression 69): gives no elite reward chance and no elite grants.")
UP71_NOTE = ("RESOLVED (USER) 2026-11-01 (daily systems, decisions 13-14): renamed from 'Elite battle'; elite-tier enemies inside normal quests never "
             "count as elite encounters. " + DEVC + ": elite-tier enemies inside normal quests come from the quest difficulty roster. " + NB + " "
             + SUP + "topic: " + UP71T_OLD + "; rule: " + UP71_OLD + "]")
OE21_ADD = R("14") + ": the Elite Mimic is not an elite encounter - it never gives the elite reward chance or the elite grants (loot_progression 69)."
BE6_ADD = "[" + R("14") + ": the Champion is not an elite encounter - it never gives the elite reward chance or the elite grants (loot_progression 69).]"
BE12_ADD = ("[" + DEVC + ": today the Herald never spawns its boss - the spawn-boss-on-death setting is stored but never read (unbuilt feature). "
            + R("9") + ": once built, a boss summoned this way counts toward the 3-per-day boss reward limit (loot_progression 15). " + NB + "]")

# ---------- chest loot on defeat (G1-A) + chest gold (G2) ----------
OE20_A_OLD = "it is credited when the chest opens, so it is kept even if the battle is lost (same as chest gold)."
OE20_A_NEW = "it is HELD until the battle ends and given only on a qualifying victory (" + R("15") + ")."
BUG75_OLD = "Fix: cards are now committed at once, like chest equipment, so they are kept on a defeat."
BUG75_NEW = "Fix: cards are now given (since " + R("15") + ": held until the battle ends with the rest of the chest loot)."
OE22_A_OLD = "Mercury is credited when the chest opens, so it is kept even if the battle is lost."
OE22_A_NEW = "Mercury is HELD until the battle ends and given only on a qualifying victory (" + R("15") + ")."
OE_ADD = lambda a: (R("15") + " (G1-A): " + HELD + " " + INPROG + " " + SUP + "col_9 (part): " + a + " | col_9 (part): " + BUG75_OLD + "]")
MS10_OLD = "Chest mercury is credited when the chest opens, so it is kept even if the battle is lost (same as chest gold)."
MS10_NEW = ("Chest loot, including the mercury, is HELD until the battle ends: given only on a qualifying victory, lost on a defeat or escape; chest gold "
            "is added to the battle gold, so a defeat keeps 50% of it (" + R("15") + ").")
MS10_NOTE = R("15") + ". " + INPROG + " " + SUP + "rule (part): " + MS10_OLD + "]"
MS14_OLD = "Salvage mercury is kept even if the battle is lost (credited at once, like chest gold)."
MS14_NEW = ("Salvage loot (mercury and gear) is HELD until the battle ends: given only on a qualifying victory, lost on a defeat or escape; salvage gold is "
            "added to the battle gold, so a defeat keeps 50% of it (" + R("15") + ").")
MS14_NOTE = R("15") + ". " + INPROG + " " + SUP + "rule (part): " + MS14_OLD + "]"
UT_NOTE = ("RESOLVED (USER) 2026-11-01 (daily systems, decision 15): chest loot - including this trait's extra item and extra gold - is HELD until the "
           "battle ends; items, cards and mercury are lost on a defeat or escape; the chest gold joins the battle gold (a defeat keeps 50%). " + INPROG
           + " " + SUP + "notes (part): " + BUG75_OLD + "]")
UTF_NOTE = ("RESOLVED (USER) 2026-11-01 (daily systems, decisions 15-16): chests do give gold (code since 2026-10-24), so this flaw has something to "
            "reduce; the reduced chest gold joins the battle gold, which is held until the battle ends (a defeat keeps 50%). " + INPROG)
NW34_ADD = ("[" + R("15") + ": salvage loot is HELD until the battle ends - the mercury and the gear item are given only on a qualifying victory and are "
            "lost on a defeat or escape; the salvage gold joins the battle gold (a defeat keeps 50%). " + INPROG + "]")
UP92_OLD = "player keeps 50% of gold earned from enemy kills during the battle."
UP92_NEW = ("player keeps 50% of the gold earned during the battle (enemy kills, plus chest and salvage gold, which is added to the battle gold - "
            + R("15") + ").")
UP92_NOTE = R("15") + ". " + INPROG + " " + SUP + "rule (part): " + UP92_OLD + "]"
UP91_NOTE = (R("15") + ": this also covers chest and salvage loot - held until the battle ends, like stolen loot (project_rules 236), and lost on a "
             "defeat or escape. " + INPROG)
GF18_NOTE = (R("15") + ": chest and salvage loot count as 'other loot' (lost on a defeat); chest / salvage gold is inside the 50% gold kept. "
             "The 2026-11-01 'chest loot listed on the defeat screen' change is replaced by this. " + INPROG)
PR227_OLD = "It carries whatever that chest would normally give (items only - chests give no gold, per the 2026-10-24 ruling)."
PR227_NEW = ("It carries whatever that chest would normally give - its items AND its gold (chests do give gold, code since 2026-10-24; " + R("16")
             + "); the gold is held too and recovered only if the player wins (project_rules 232).")
PR227_NOTE = (R("16") + ": wording fixed - chests give gold (" + DEVC + "). The Treasure Hunter holding the chest gold: " + NB + " " + SUP
              + "rule (part): " + PR227_OLD + "]")
GF21_NOTE = ("Daily systems 2026-11-01 (G7): stays OPEN; the daily systems design does not depend on it (the Daily Contract uses a fixed daily seed and "
             "the elite roll is fixed on each card). " + DEVC + ": today the board is regenerated on every return to base, seeded with the current "
             "server time.")

OPS = [
 ('live_service_features', 11, 'rule', 'set', LSF11_OLD, LSF11_NEW),
 ('live_service_features', 11, 'notes', 'app', ' | ', LSF11_NOTE),
 ('live_service_features', 10, 'notes', 'app', ' | ', LSF10_NOTE),
 ('live_service_features', 12, 'rule', 'set', LSF12_OLD, LSF12_NEW),
 ('live_service_features', 12, 'notes', 'app', ' | ', LSF12_NOTE),
 ('live_service_features', 4, 'notes', 'app', ' | ', LSF4_NOTE),
 ('materials_system', 13, 'rule', 'rep', MS13_OLD, MS13_NEW),
 ('materials_system', 13, 'notes', 'app', ' | ', MS13_NOTE),
 ('materials_system', 36, 'notes', 'app', ' | ', MS36_NOTE),
 ('unit_progression', 84, 'notes', 'app', ' | ', UP84_NOTE),
 ('open_decisions', 124, 'col_3', 'rep', OD124_OLD, OD124_NEW),
 ('open_decisions', 124, 'col_3', 'app', ' ', SUP + "(part): " + OD124_OLD + "]"),
 ('save_data_contract', 3, 'Persistent_Fields', 'rep', SD3_PF_OLD, SD3_PF_NEW),
 ('save_data_contract', 3, 'Load_Validation', 'app', '', SD3_LV_ADD),
 ('save_data_contract', 3, 'Failure_Behavior', 'app', ' ', SD3_FB_ADD),
 ('save_data_contract', 1, 'Failure_Behavior', 'app', ' ', SD1_FB_ADD),
 ('unit_progression', 77, 'notes', 'app', ' | ', DISP),
 ('unit_progression', 78, 'notes', 'app', ' | ', DISP_S),
 ('unit_progression', 99, 'notes', 'app', ' | ', DISP_S),

 ('materials_system', 9, 'rule', 'rep', MS9_OLD, MS9_NEW),
 ('materials_system', 9, 'notes', 'rep', MS9N_OLD, MS9N_NEW),
 ('materials_system', 9, 'notes', 'app', ' ', SUP + "rule (part): " + MS9_OLD + " | notes (part): " + MS9N_OLD + "]"),
 ('materials_system', 41, 'rule', 'rep', MS41_OLD, MS41_NEW),
 ('materials_system', 41, 'notes', 'rep', MS41N_OLD, MS41N_NEW),
 ('materials_system', 41, 'notes', 'app', ' ', SUP + "rule (part): " + MS41_OLD + " | notes (part): " + MS41N_OLD + "]"),
 ('loot_progression', 15, 'rule', 'rep', LP15_OLD, LP15_NEW),
 ('loot_progression', 15, 'notes', 'app', ' | ', LP15_NOTE),
 ('loot_progression', 25, 'rule', 'rep', LP25_OLD, LP25_NEW),
 ('loot_progression', 25, 'notes', 'app', ' | ', LP25_NOTE),
 ('implementation_plan', 53, 'col_2', 'rep', IP53_OLD, IP53_NEW),
 ('implementation_plan', 53, 'col_2', 'app', ' ', SUP + "(part): " + IP53_OLD + "]"),

 ('project_rules', 38, 'rule', 'set', PR38_OLD, PR38_NEW),
 ('project_rules', 38, 'notes', 'app', ' | ', SUP + "rule: " + PR38_OLD + "]"),
 ('loot_progression', 69, 'rule', 'rep', LP69_OLD, LP69_NEW),
 ('loot_progression', 69, 'notes', 'app', ' | ', LP69_NOTE),
 ('loot_progression', 26, 'notes', 'app', ' | ', LP26_NOTE),
 ('loot_progression', 70, 'notes', 'app', ' | ', LP70_NOTE),
 ('loot_progression', 86, 'notes', 'app', ' | ', LP86_NOTE),
 ('loot_progression', 74, 'notes', 'app', ' | ', LP74_NOTE),
 ('unit_progression', 64, 'notes', 'app', ' | ', UP64_NOTE),
 ('materials_system', 8, 'notes', 'app', ' | ', MS8_NOTE),
 ('guild_facilities', 17, 'rule', 'rep', GF17_OLD, GF17_NEW),
 ('guild_facilities', 17, 'notes', 'app', ' | ', GF17_NOTE),
 ('unit_progression', 71, 'topic', 'set', UP71T_OLD, UP71T_NEW),
 ('unit_progression', 71, 'rule', 'set', UP71_OLD, UP71_NEW),
 ('unit_progression', 71, 'notes', 'app', ' | ', UP71_NOTE),
 ('objects_encounters', 21, 'col_9', 'app', ' | ', OE21_ADD),
 ('battlefield_events', 6, 'behavior_effect', 'app', ' ', BE6_ADD),
 ('battlefield_events', 12, 'behavior_effect', 'app', ' ', BE12_ADD),

 ('objects_encounters', 20, 'col_9', 'rep', OE20_A_OLD, OE20_A_NEW),
 ('objects_encounters', 20, 'col_9', 'rep', BUG75_OLD, BUG75_NEW),
 ('objects_encounters', 20, 'col_9', 'app', ' | ', OE_ADD(OE20_A_OLD)),
 ('objects_encounters', 22, 'col_9', 'rep', OE22_A_OLD, OE22_A_NEW),
 ('objects_encounters', 22, 'col_9', 'rep', BUG75_OLD, BUG75_NEW),
 ('objects_encounters', 22, 'col_9', 'app', ' | ', OE_ADD(OE22_A_OLD)),
 ('materials_system', 10, 'rule', 'rep', MS10_OLD, MS10_NEW),
 ('materials_system', 10, 'notes', 'app', ' | ', MS10_NOTE),
 ('materials_system', 14, 'rule', 'rep', MS14_OLD, MS14_NEW),
 ('materials_system', 14, 'notes', 'app', ' | ', MS14_NOTE),
 ('unit_traits', 243, 'notes', 'rep', BUG75_OLD, BUG75_NEW),
 ('unit_traits', 243, 'notes', 'app', ' | ', UT_NOTE),
 ('unit_traits', 301, 'notes', 'rep', BUG75_OLD, BUG75_NEW),
 ('unit_traits', 301, 'notes', 'app', ' | ', UT_NOTE),
 ('unit_traits', 244, 'notes', 'app', ' | ', UTF_NOTE),
 ('unit_traits', 302, 'notes', 'app', ' | ', UTF_NOTE),
 ('nonweapon_equipment', 34, 'rule', 'app', ' ', NW34_ADD),
 ('unit_progression', 92, 'rule', 'rep', UP92_OLD, UP92_NEW),
 ('unit_progression', 92, 'notes', 'app', ' | ', UP92_NOTE),
 ('unit_progression', 91, 'notes', 'app', ' | ', UP91_NOTE),
 ('game_flow', 18, 'notes', 'app', ' | ', GF18_NOTE),
 ('project_rules', 227, 'rule', 'rep', PR227_OLD, PR227_NEW),
 ('project_rules', 227, 'notes', 'app', ' | ', PR227_NOTE),
 ('game_flow', 21, 'notes', 'app', ' | ', GF21_NOTE),
]
