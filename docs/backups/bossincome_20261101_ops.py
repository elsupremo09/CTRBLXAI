# 2026-11-01 BOSS INCOME + DAILY SYSTEMS BUILD STATUS. Ops only.
# (table, rowid, column, mode, a, b)  mode: set (a = expected full old), rep (a -> b, a must occur exactly once in the cell), app (append b with separator a)
RU = "RESOLVED (USER) 2026-11-01 (boss income)"
DDU = "DECIDED (DEV DEFAULT) 2026-11-01 (the user skipped this question)"
DEVD = "DECIDED (DEV DEFAULT) 2026-11-01"
BLT = "BUILT 2026-11-01 (source-verified by Tester; Studio test pending)"
BLTR = "BUILT 2026-11-01; Tester source check running - not yet verified"
SUP = "[Superseded 2026-11-01 (boss income): "
SIMREF = "Simulator sim\\daily_systems_2026-11-01, report.md and report_options.md"
INPROG = "IN PROGRESS: the Dev is building this now (2026-11-01); it replaces the 2026-11-01 'chest loot listed on the defeat screen' change. Not yet verified."
INPROG_NEW = BLT + " - it replaces the 2026-11-01 'chest loot listed on the defeat screen' change. " + SUP + INPROG + "]"
RARITY = "the Elite-encounter rarity column limited to Rare and up, with normal Fortune weighting (about Rare 61% / Epic 23% / Exalted 8% / Legendary 7% / Mythic 0.3%)"

# ---------- PART 1: boss income ----------
LP15_NOTE = (RU + " (option B4 + daily 3; " + SIMREF + "): the Simulator found boss income far above plan. Bosses KEEP 3 boss rewards a day "
  "(this row and row 25 unchanged). Boss quest cards are made rarer: card weight 10 -> 3, about 1 card in 31 instead of 1 in 10 (guild_facilities 17). "
  "Daily Contract mercury 5 -> 3 (materials_system 13). ACCEPTED CONSEQUENCE (user; Simulator figures at 80 Daily Contracts, 90% wins, 75-100% dismantling): "
  "a player who picks cards at random gets about 16.7-19.4 levellings and 226-264 crystals, inside target; a player who hunts bosses gets about 33.5-39.7 "
  "levellings and 1,637-1,785 crystals, because the quest board re-rolls on every return to base (game_flow 21). Boss hunting is therefore a strong path; "
  "the user accepted this. Card weight and daily mercury: " + BLTR + ". Boss reward and the 3-a-day limit: " + BLT + ", including the quest board line "
  "'Boss rewards left today: N/3' - this replaces 'NOT BUILT' above. Guaranteed boss item rarity - " + DEVD + ": " + RARITY + ". "
  "A boss summoned by the Herald is still NOT BUILT (battlefield_events 12).")
LP25_NOTE = ("Boss income " + RU + ": 3 boss rewards a day kept (row 15). " + BLT + " - replaces 'NOT BUILT' above. Guaranteed item rarity - " + DEVD + ": " + RARITY + ".")

GF17_RULE_ADD = "Boss quest cards are rare: card weight 3 in the quest card mix, about 1 card in 31 (" + RU + "; was 10, about 1 in 10)."
GF17_OPEN_OLD = "(open for a user decision)"
GF17_OPEN_NEW = "(was open for a user decision - now DECIDED (DEV DEFAULT) 2026-11-01, see below)"
GF17_NOTE = ("Boss quest unlock - " + DDU + ": boss quests unlock at Quest Board L8, kept as written. The code gate is added when facility buying is built (Slice 8); "
  "until then boss quests are open from the start for testing. Boss card weight 10 -> 3 (about 1 card in 31; the Simulator modelled about 1 in 33): " + RU
  + " (option B4; loot_progression 15); " + BLTR + ". " + SUP + "notes (part): " + GF17_OPEN_OLD + "]")
UP72_NOTE = "Boss quest cards: card weight 3, about 1 card in 31; they unlock at Quest Board L8 (guild_facilities 17; " + RU + ")."

MS13_A_OLD = "5 mercury per completed daily event"
MS13_A_NEW = "3 mercury per completed daily event (" + RU + "; was 5)"
MS13_B_OLD = "about +400 mercury and +27 sulfur"
MS13_B_NEW = "about +240 mercury and +27 sulfur"
MS13_C_OLD = "budget per 10 events: +50 mercury, +3.3 sulfur"
MS13_C_NEW = "budget per 10 events: +30 mercury, +3.3 sulfur"
MS13_NOTE = (RU + ": the locked Daily Contract mercury changed 5 -> 3 to keep lifetime levelling inside the 15-20 target (Simulator: a random card picker gets about "
  "16.7-19.4 levellings at 80 contracts). The every-3rd-sulfur rule is unchanged. Day counter and Daily Contract: " + BLT + " - replaces 'NOT BUILT' above; "
  "the 3-mercury value: " + BLTR + ". " + SUP + "rule (part): " + MS13_A_OLD + " | " + MS13_B_OLD + " | " + MS13_C_OLD + "]")
MS36_NOTE = ("Boss income " + RU + ": Daily Contract mercury is now 3, so about 80 contracts add about +240 mercury (range +90 to +540); the sulfur figures are unchanged. "
  "Simulator 2026-11-01 (90% wins, boss card weight 3): random card picker about 16.7-19.4 levellings and 226-264 crystals at 80 contracts; boss hunter about "
  "33.5-39.7 levellings and 1,637-1,785 crystals (accepted, loot_progression 15). This replaces the 'about +400 mercury' and '20-23 levellings' figures above.")
GF38_OLD = "Daily events add +50 mercury per 10 events; with 100% dismantling the total passes 20 levellings after about 22-23 events (about 82 with 75% dismantling)."
GF38_NEW = ("Daily events add +30 mercury per 10 events (3 mercury each, " + RU + "); straight scaling of the old figures: with 100% dismantling the total passes "
  "20 levellings after about 37-38 events (about 137 with 75% dismantling). Simulator 2026-11-01 (90% wins, boss card weight 3): a random card picker gets about "
  "16.7-19.4 levellings at 80 Daily Contracts (inside target); a boss hunter about 33.5-39.7 (accepted, loot_progression 15).")
GF38_NOTE = SUP + "rule (part): " + GF38_OLD + "]"

LSF11_A_OLD = "+ 5 mercury"
LSF11_A_NEW = "+ 3 mercury (" + RU + "; was 5)"
LSF11_B_OLD = "the 5 mercury and the sulfur progress"
LSF11_B_NEW = "the 3 mercury and the sulfur progress"
LSF11_NOTE = ("Day counter and Daily Contract: " + BLT + ", including the clock-back fix (if the server's day reads earlier than the saved day, nothing resets) - "
  "replaces 'NOT BUILT' above. Daily mercury 5 -> 3: " + RU + "; " + BLTR + ". " + SUP + "rule (part): " + LSF11_A_OLD + " | notes (part): " + LSF11_B_OLD + "]")
DE_OLD = "Daily events give 5 mercury each"
DE_NEW = "Daily events give 3 mercury each (" + RU + "; was 5)"
DE_NOTE = "Daily mercury 5 -> 3: " + RU + "; " + BLTR + ". Daily Contract " + BLT + " - replaces 'NOT BUILT' above. " + SUP + "rule (part): " + DE_OLD + "]"

# ---------- PART 2: dev defaults ----------
LP69_OLD = ("when the quest board makes each NORMAL quest card, it rolls a hidden 3.4% chance for that card to be an elite encounter; the result is fixed on the card "
  "and revealed at the departure briefing ('Scouts report an elite war band!'); backing out does not re-roll it.")
LP69_NEW = ("one hidden 3.4% roll per normal battle, tied to the player's completed-battle count - not a separate roll per card (" + DDU + "). Every normal quest card "
  "shares that result; it is fixed when a card is selected and revealed at the departure briefing ('Scouts report an elite war band!'); backing out or abandoning "
  "cannot change it. Fortune is not used.")
LP69_NOTE = ("Elite roll - " + DDU + ", a deviation from decision 10 (one roll per card). Reason: it stops elite fishing by abandoning cards; with a roll per card the "
  "Simulator found an elite on 23.5% of boards (about 6.9x the intended rate). Never on boss cards or the Daily Contract; Fortune is not used. Elite encounters "
  "(decisions 10-14): " + BLT + ", except the 200 Guild XP (row 74) - replaces 'NOT BUILT' above. " + SUP + "rule (part): " + LP69_OLD + "]")
PR38_A_OLD = "a hidden 3.4% roll on each normal quest card"
PR38_A_NEW = "one hidden 3.4% roll per normal battle, tied to the player's completed-battle count (DECIDED (DEV DEFAULT) 2026-11-01; replaces the roll per card)"
PR38_B_OLD = "NOT BUILT; loot_progression 69"
PR38_B_NEW = BLT + "; loot_progression 69"
PR38_NOTE = SUP + "rule (part): " + PR38_A_OLD + " | " + PR38_B_OLD + "]"
LP26_NOTE = "Elite roll - " + DDU + ": one hidden 3.4% roll per normal battle, not per card (row 69). Elite encounters " + BLT + " - replaces 'NOT BUILT' above."
LP70_A_OLD = "6 enemies (row 86) led by an Elite Leader (the existing Elite-tier build, at the quest's level)"
LP70_A_NEW = ("the card's normal enemy count + 1: any Elites on the card become Veterans, plus one Elite Leader (the existing Elite-tier build, at quest level + 2) "
  "(row 86; battle size and leader level " + DDU + ")")
LP70_B_OLD = "and 200 Guild XP (row 74)"
LP70_B_NEW = "and 200 Guild XP (row 74 - NOT BUILT: no quest battle awards Guild XP yet)"
LP70_NOTE = ("Reasons for the dev defaults: the '6 enemies' in the design is a planning value - real battles have 2-2.5x the deploy slots; the leader at quest level + 2 "
  "should stand out. 'Defeat the Elite' in an elite encounter counts only the leader; an Elite added by a battlefield event neither blocks nor completes it "
  "(unit_progression 64). Elite encounters " + BLT + ", except the Guild XP - replaces 'NOT BUILT' above. " + SUP + "notes (part): " + LP70_A_OLD + " | " + LP70_B_OLD + "]")
LP86_RULE_ADD = ("In the game an elite encounter has the card's normal enemy count + 1 (any Elites on the card become Veterans, plus one Elite Leader) - "
  + DEVD + " (loot_progression 70).")
LP86_NOTE = "Elite battle size - " + DDU + ". Reason: '6' is a planning value; real battles have 2-2.5x the deploy slots. " + BLT + "."
LP71_NOTE = "Elite reward rarity table used by elite encounters: " + BLT + " (decisions 10-14)."
UP64_NOTE = ("Elite encounters: 'Defeat the Elite' counts only the Elite Leader; an Elite added by a battlefield event neither blocks nor completes it (" + DEVD + "). "
  "Elite encounters " + BLT + " - replaces 'NOT BUILT' above.")
LP74_NOTE = "Elite Guild XP 200: NOT BUILT - no quest battle awards Guild XP yet (status 2026-11-01, boss income build)."
MS8_NOTE = "Elite mercury grant: " + BLT + " (elite encounters, loot_progression 69/70) - replaces 'NOT BUILT' above."
MS9_NOTE = "Boss mercury grant under the 3-a-day limit: " + BLT + " - replaces 'NOT BUILT' above. Boss income " + RU + ": 3 a day kept, boss cards rarer (loot_progression 15)."
MS41_NOTE = ("Status 2026-11-01 (boss income build): elite grants and boss grants (3-a-day limit) " + BLT + " - replaces the 'NOT BUILT' statuses above. "
  "Boss income " + RU + ": 3 boss rewards a day kept; boss cards about 1 in 31 (loot_progression 15).")

# ---------- PART 3: build status ----------
SD3_PF_OLD = "(RESOLVED (USER) 2026-11-01 (daily systems, decision 3); NOT BUILT)"
SD3_PF_NEW = "(RESOLVED (USER) 2026-11-01 (daily systems, decision 3); " + BLT + ")"
SD3_LV_OLD = "daily counters (NOT BUILT, daily systems decision 1)"
SD3_LV_NEW = "daily counters (" + BLT + ", with the clock-back fix; daily systems decision 1)"
SD3_FB_ADD = SUP + "Persistent_Fields (part): " + SD3_PF_OLD + " | Load_Validation (part): " + SD3_LV_OLD + "]"
DISP_NOTE = "Dispatch wording 'battles': " + BLT + " - replaces 'NOT BUILT' above."
BE12_ADD = "[Status checked 2026-11-01 (boss income build): the Herald boss is still NOT BUILT - the feature does not exist yet.]"
PR227_OLD = "The Treasure Hunter holding the chest gold: NOT BUILT."
PR227_NEW = "The Treasure Hunter holding the chest gold: " + BLT + " - the gold is paid on a victory only."
PR227_NOTE = SUP + "notes (part): " + PR227_OLD + "]"
WORD_NOTE = ("Wording checked 2026-11-01 (Simulator note, report.md Q5): the live rule says chest / salvage mercury is held and lost on a defeat or escape; the old "
  "'kept even if the battle is lost' wording survives only as superseded history.")

NW34_RULE_ADD = ("[" + DEVD + " (Simulator critical finding, report.md F2: Conjure Ice Spike + Salvager's Cap was an unlimited salvage farm): only objects the map "
  "generated give a salvage roll; anything placed during the battle - a conjured Ice Spike, a Deployable, any object placed by either side - gives none. This narrows "
  "the USER RULING 2026-10-30 list above (Ice Spike and Blocker-Prop Cluster count only when the map generated them; Deployables no longer count). " + BLT + ". "
  + SUP + "restriction (part): Only objects that were breakable before 2026-10-30 (rule 241) | display_text: Destroying a breakable object gives a little gold, plus a 5% "
  "chance of 1 mercury and a 5% chance of a gear item.]]")
NW34_RES_OLD = "Only objects that were breakable before 2026-10-30 (rule 241)"
NW34_RES_NEW = "Only objects the map generated (nothing placed during the battle) that were breakable before 2026-10-30 (rule 241)"
NW34_DT_OLD = "Destroying a breakable object gives a little gold, plus a 5% chance of 1 mercury and a 5% chance of a gear item."
NW34_DT_NEW = "Destroying a breakable map object gives a little gold, plus a 5% chance of 1 mercury and a 5% chance of a gear item. Objects placed during the battle give nothing."
MS14_RULE_ADD = ("Only objects the map generated give a salvage roll; anything placed during the battle (a conjured Ice Spike, a Deployable, any object placed by either side) "
  "gives none (" + DEVD + ").")
MS14_NOTE = ("Salvager's Cap map-objects-only rule - " + DEVD + ". Reason: the Simulator's critical finding (report.md F2): Conjure Ice Spike costs about 11 MP and breaks "
  "in one Fire hit, so one caster could farm about 20 salvage rolls per battle (10 spikes per battle = about +16 levellings, +190 crystals). It narrows the 2026-10-30 "
  "user ruling, which listed Ice Spike and Deployables (nonweapon_equipment 34). " + BLT + ". " + WORD_NOTE)
GF21_NOTE = ("Boss income 2026-11-01: the elite roll is no longer fixed on each card - it is one roll per normal battle, tied to the completed-battle count "
  "(loot_progression 69, " + DEVD + "). Because the board re-rolls on every return to base, a boss hunter always finds a boss card; the user accepted boss hunting as a "
  "strong path (loot_progression 15, " + RU + ").")

IP53_OLD = ("NOT BUILT: elite encounter grants (materials_system 8, 41 - elite encounters do not exist in code), daily events (materials_system 13 - no daily event system), "
  "boss grants (materials_system 9, 41, loot_progression 15 - hold lifted 2026-11-01: they count toward the 3-per-day boss reward limit, which is NOT BUILT); daily systems "
  "(RESOLVED (USER) 2026-11-01: real-day clock, Daily Contract, boss reward limit, elite encounters - all NOT BUILT; chest / salvage loot held until the battle ends - "
  "IN PROGRESS, Dev building 2026-11-01)")
IP53_NEW = ("DAILY SYSTEMS " + BLT + ": day counter + Daily Contract with the clock-back fix (live_service_features 11; materials_system 13); boss reward + the 3-a-day "
  "limit with 'Boss rewards left today: N/3' (loot_progression 15, 25; materials_system 9, 41); elite encounters, except Guild XP (loot_progression 26, 69-71; "
  "materials_system 8, 41); chest / salvage loot held until the battle ends; the Treasure Hunter holds chest gold (victory only); dispatch wording 'battles'; "
  "Salvager's Cap - map-generated objects only (DEV DEFAULT). Boss income (" + RU + "): boss card weight 10 -> 3 and Daily Contract mercury 5 -> 3 - " + BLTR + ". "
  "NOT BUILT: elite Guild XP 200 (no quest battle awards Guild XP yet), the Herald boss (feature does not exist; battlefield_events 12), the Quest Board L8 gate "
  "for boss quests (added with facility buying, Slice 8; guild_facilities 17), 'Hard quests' at Quest Board L5")
IP53_ADD = SUP + "(part): " + IP53_OLD + "]"

OPS = [
 ('loot_progression', 15, 'notes', 'app', ' | ', LP15_NOTE),
 ('loot_progression', 25, 'notes', 'app', ' | ', LP25_NOTE),
 ('guild_facilities', 17, 'rule', 'app', ' ', GF17_RULE_ADD),
 ('guild_facilities', 17, 'notes', 'rep', GF17_OPEN_OLD, GF17_OPEN_NEW),
 ('guild_facilities', 17, 'notes', 'app', ' | ', GF17_NOTE),
 ('unit_progression', 72, 'notes', 'app', ' | ', UP72_NOTE),
 ('materials_system', 13, 'rule', 'rep', MS13_A_OLD, MS13_A_NEW),
 ('materials_system', 13, 'rule', 'rep', MS13_B_OLD, MS13_B_NEW),
 ('materials_system', 13, 'rule', 'rep', MS13_C_OLD, MS13_C_NEW),
 ('materials_system', 13, 'notes', 'app', ' | ', MS13_NOTE),
 ('materials_system', 36, 'notes', 'app', ' | ', MS36_NOTE),
 ('guild_facilities', 38, 'rule', 'rep', GF38_OLD, GF38_NEW),
 ('guild_facilities', 38, 'notes', 'app', ' | ', GF38_NOTE),
 ('live_service_features', 11, 'rule', 'rep', LSF11_A_OLD, LSF11_A_NEW),
 ('live_service_features', 11, 'notes', 'rep', LSF11_B_OLD, LSF11_B_NEW),
 ('live_service_features', 11, 'notes', 'app', ' | ', LSF11_NOTE),
 ('live_service_features', 4, 'rule', 'rep', DE_OLD, DE_NEW),
 ('live_service_features', 4, 'notes', 'app', ' | ', DE_NOTE),
 ('unit_progression', 84, 'rule', 'rep', DE_OLD, DE_NEW),
 ('unit_progression', 84, 'notes', 'app', ' | ', DE_NOTE),

 ('loot_progression', 69, 'rule', 'rep', LP69_OLD, LP69_NEW),
 ('loot_progression', 69, 'notes', 'app', ' | ', LP69_NOTE),
 ('project_rules', 38, 'rule', 'rep', PR38_A_OLD, PR38_A_NEW),
 ('project_rules', 38, 'rule', 'rep', PR38_B_OLD, PR38_B_NEW),
 ('project_rules', 38, 'notes', 'app', ' ', PR38_NOTE),
 ('loot_progression', 26, 'notes', 'app', ' | ', LP26_NOTE),
 ('loot_progression', 70, 'notes', 'rep', LP70_A_OLD, LP70_A_NEW),
 ('loot_progression', 70, 'notes', 'rep', LP70_B_OLD, LP70_B_NEW),
 ('loot_progression', 70, 'notes', 'app', ' | ', LP70_NOTE),
 ('loot_progression', 86, 'rule', 'app', ' ', LP86_RULE_ADD),
 ('loot_progression', 86, 'notes', 'app', ' | ', LP86_NOTE),
 ('loot_progression', 71, 'notes', 'app', ' | ', LP71_NOTE),
 ('unit_progression', 64, 'notes', 'app', ' | ', UP64_NOTE),
 ('loot_progression', 74, 'notes', 'app', ' | ', LP74_NOTE),
 ('materials_system', 8, 'notes', 'app', ' | ', MS8_NOTE),
 ('materials_system', 9, 'notes', 'app', ' | ', MS9_NOTE),
 ('materials_system', 41, 'notes', 'app', ' | ', MS41_NOTE),

 ('save_data_contract', 3, 'Persistent_Fields', 'rep', SD3_PF_OLD, SD3_PF_NEW),
 ('save_data_contract', 3, 'Load_Validation', 'rep', SD3_LV_OLD, SD3_LV_NEW),
 ('save_data_contract', 3, 'Failure_Behavior', 'app', ' ', SD3_FB_ADD),
 ('unit_progression', 77, 'notes', 'app', ' | ', DISP_NOTE),
 ('unit_progression', 78, 'notes', 'app', ' | ', DISP_NOTE),
 ('unit_progression', 99, 'notes', 'app', ' | ', DISP_NOTE),
 ('battlefield_events', 12, 'behavior_effect', 'app', ' ', BE12_ADD),
 ('objects_encounters', 20, 'col_9', 'rep', INPROG, INPROG_NEW),
 ('objects_encounters', 22, 'col_9', 'rep', INPROG, INPROG_NEW),
 ('nonweapon_equipment', 34, 'rule', 'rep', INPROG, INPROG_NEW),
 ('unit_progression', 91, 'notes', 'rep', INPROG, INPROG_NEW),
 ('unit_progression', 92, 'notes', 'rep', INPROG, INPROG_NEW),
 ('materials_system', 10, 'notes', 'rep', INPROG, INPROG_NEW),
 ('materials_system', 10, 'notes', 'app', ' | ', WORD_NOTE),
 ('materials_system', 14, 'notes', 'rep', INPROG, INPROG_NEW),
 ('unit_traits', 243, 'notes', 'rep', INPROG, INPROG_NEW),
 ('unit_traits', 244, 'notes', 'rep', INPROG, INPROG_NEW),
 ('unit_traits', 301, 'notes', 'rep', INPROG, INPROG_NEW),
 ('unit_traits', 302, 'notes', 'rep', INPROG, INPROG_NEW),
 ('game_flow', 18, 'notes', 'rep', INPROG, INPROG_NEW),
 ('project_rules', 227, 'notes', 'rep', PR227_OLD, PR227_NEW),
 ('project_rules', 227, 'notes', 'app', ' ', PR227_NOTE),
 ('nonweapon_equipment', 34, 'rule', 'app', ' ', NW34_RULE_ADD),
 ('nonweapon_equipment', 34, 'restriction', 'rep', NW34_RES_OLD, NW34_RES_NEW),
 ('nonweapon_equipment', 34, 'display_text', 'set', NW34_DT_OLD, NW34_DT_NEW),
 ('materials_system', 14, 'rule', 'app', ' ', MS14_RULE_ADD),
 ('materials_system', 14, 'notes', 'app', ' | ', MS14_NOTE),
 ('game_flow', 21, 'notes', 'app', ' | ', GF21_NOTE),
 ('implementation_plan', 53, 'col_2', 'rep', IP53_OLD, IP53_NEW),
 ('implementation_plan', 53, 'col_2', 'app', ' ', IP53_ADD),
]
