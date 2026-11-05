# rune-forged tag + stragglers + build status + gem count (2026-11-01). Ops only; executed by the Designer write step.
T = "LOCKED - USER DECISION 2026-11-01 (v2). NOT BUILT."
B = "BUILT 2026-11-01 (source-verified by Tester; Studio test pending)"
RULING = "USER RULING 2026-11-01 (rune-forged = normal loot)"

EF28_ORIG = "Long-term gold sink. Luxury progression. 10 facilities totaling 70,927g (original 9 = 62,008g + Runeforge = 8,919g). Gold-only (no materials). Free/boosted max counts PENDING re-simulation (old: free 6/9, boosted 9/9)."
EF28_NEW = "Long-term gold sink. Luxury progression. 10 facilities totaling 70,927g (original 9 = 62,008g + Runeforge = 8,919g). Gold-only (no materials). Simulator re-check 2026-11-01 (v2 fees, realistic crafting): free player maxes 5-7 of 10 facilities (about 109-112% of lifetime gold); boosted player maxes 10/10 (about 85-89%) (guild_facilities 5, 36, 37)."

EF14_OLD = 'Forged items (PLANNED, not built): an item whose rarity was raised by the Runeforge sells with this same formula using its starting rarity (equipment_schema 19) in place of its current rarity; item level and everything else stay as they are. Items never forged are unchanged (starting rarity = current rarity). Blacksmith level upgrades keep raising sell value as today. PLANNED UI rule: the Merchant sell view shows a short note on such items, e.g. "Sells as Common (enchanted)". (Kept in v2, draft Section 5.)'
EF14_NEW = 'Every item sells with this formula at its CURRENT rarity and item level, including items changed by the Runeforge: rune-forged items are treated as normal loot whatever they cost to make, and the sell view shows no extra label (USER RULING 2026-11-01; the tracking tag rune_forged, equipment_schema 21, has no price effect). Blacksmith level upgrades keep raising sell value as today.'

EF16_OLD = "Crafting (v2): forged items sell at their starting rarity (row 14), and mercury, crystals, rune gems and sulfur cannot be sold while dismantling gives no gold, so no route of buy / loot \u2192 forge / dismantle \u2192 sell makes gold (buy \u2192 dismantle \u2192 sell returns 0 gold)."
EF16_NEW = "Crafting (v2): mercury, crystals, rune gems and sulfur cannot be sold and dismantling gives no gold (buy \u2192 dismantle \u2192 sell returns 0 gold). Rune-forged items sell as normal loot at their CURRENT rarity (row 14, USER RULING 2026-11-01), so forge-then-sell can show a small gain. Dev check 2026-11-01 (every slot, item level 1-99, Runeforge discount 0-27%, every Common / Uncommon / Rare / Epic step): at most +4g (2H Uncommon \u2192 Epic at L99 with Runeforge L10); 29 positive cases, all at item L97-99 with the 27% discount; each costs 9-18 crystals plus the rune gems, and crystals cannot be bought. ACCEPTED - a consequence of the USER RULING 2026-11-01."

GF15_OLD = '2026-11-01 PLANNED UI rule (USER-APPROVED with option C, for when the Runeforge is built): the Merchant sell view shows a short note on items whose rarity was raised by the Runeforge, e.g. "Sells as Common (enchanted)" (economy_framework 14). NOT BUILT.'
GF15_NEW = '[Superseded 2026-11-01: ' + GF15_OLD + '] | ' + RULING + ': no "Sells as ..." label - rune-forged items sell as normal loot at their current rarity (economy_framework 14).'

OD123_OLD = 'enchanted items sell at their starting rarity (economy_framework 14/16, gf 57 guard 7); Merchant sell-view note "Sells as Common (enchanted)" = PLANNED UI rule (gf 15).'
OD123_NEW = '[superseded 2026-11-01 by ' + RULING + ': rune-forged items sell at their CURRENT rarity with no "Sells as" note (economy_framework 14/16, equipment_schema 21). Was: ' + OD123_OLD + ']'

OD95_OLD = "Design facts unchanged: Treasure Chest = random gold/equipment/materials/runes; Cursed Chest"
OD95_NEW = "Design facts: Treasure Chest = random gold, equipment and materials (1 mercury; no crystals and no rune gems - v2 2026-11-01, objects_encounters 20, materials_system 10) [Superseded 2026-11-01 (v2 wording): random gold/equipment/materials/runes]; Cursed Chest"

GF57_G1_OLD = "so no buy / dismantle / upgrade / forge chain turns into gold;"
GF57_G1_NEW = "so no buy / dismantle / upgrade / forge chain turns into gold (except the accepted forge-then-sell gain of at most +4g, guard 2);"
GF57_G2_OLD = "(2) forged items sell at their starting rarity (economy_framework 14);"
GF57_G2_NEW = "(2) rune-forged items sell as normal loot at their CURRENT rarity (economy_framework 14, USER RULING 2026-11-01); this allows forge-then-sell gains of at most +4g (2H Uncommon \u2192 Epic at L99, Runeforge L10; 9-18 crystals + gems each), ACCEPTED (economy_framework 16);"

ES19_OLD = "Used for the sell value of forged items (economy_framework 14); the Epic step fee is OFF (guild_facilities 57)"
ES19_NEW = "Tracking only (no price effect) - USER RULING 2026-11-01: items sell at their current rarity (economy_framework 14); the Epic step fee is OFF (guild_facilities 57)"

GEMS_FIX = "133 kinds in the game content (20 numeric families \u00d7 T1-T4 = 80, including Fortune, + 53 bonus passives). The DB lists 5 more numeric families that are not in the game content (BonusData): Collision Damage, Fall Damage Dealt, Collision Resistance, Fall Resistance, Item Direct Damage - DB-only until the content file is regenerated (kept, not deleted; Tester correction 2026-11-01)"

GF40_SCREEN = (" Screen (v2 step 3, BUILT 2026-11-01): the Blacksmith is its own full screen in the Merchant style, with Upgrade and Dismantle sub-tabs; "
               "\u2212 / + / Max set the target level; the check and X buttons each ask for confirmation; a free downgrade shows a 'not refunded' prompt; "
               "above-Epic and Unique dismantles show their own prompts; the header shows Mercury, Crystals and Sulfur.")

NOT6 = "LOCKED - USER DECISION 2026-11-01 (v2). NOT BUILT yet: battle mercury drops come in v2 build step 6 (the mercury currency itself is BUILT, step 1)."
def built(step): return "LOCKED - USER DECISION 2026-11-01 (v2). " + B + " - v2 step " + step + "."

# (table, rowid, column, mode, a, b, pre_only)   mode: set (a = expected full old), rep (a -> b once), app (append b with separator a)
OPS = [
 # PART 1 stragglers
 ('economy_framework', 28, 'rule', 'set', EF28_ORIG, EF28_NEW, False),
 ('economy_framework', 28, 'notes', 'app', ' | ', '2026-11-01: re-simulation result filled in (Simulator re-check, guild_facilities 5/36/37). [Superseded 2026-11-01: rule: ' + EF28_ORIG + ']', False),
 ('open_decisions', 95, 'col_3', 'rep', OD95_OLD, OD95_NEW, False),
 ('item_generation_steps', 8, 'important_rule', 'rep', 'enchanted items: 0 up to normal budget', 'rune-forged items: 0 up to normal budget', False),
 ('item_rarity_rules', 14, 'rule_value', 'rep', 'Player-enchanted items may hold', 'Rune-forged items may hold', False),
 ('item_rarity_rules', 23, 'rule_value', 'rep', 'Enchanted items are renamed automatically', 'Rune-forged items are renamed automatically', False),
 ('guild_facilities', 15, 'notes', 'rep', GF15_OLD, GF15_NEW, False),
 # PART 2 ruling
 ('economy_framework', 14, 'rule', 'rep', EF14_OLD, EF14_NEW, False),
 ('economy_framework', 14, 'notes', 'app', ' | ', RULING + ': the forged-item sell rule (sell at starting rarity) and the planned "Sells as ..." UI note are REMOVED; every item sells at its current rarity. [Superseded 2026-11-01: rule (part): ' + EF14_OLD + ']', False),
 ('economy_framework', 16, 'rule', 'rep', EF16_OLD, EF16_NEW, False),
 ('economy_framework', 16, 'notes', 'app', ' | ', RULING + ': forged-item sentence replaced by the Dev\'s measured result (max +4g, accepted). [Superseded 2026-11-01: rule (part): ' + EF16_OLD + ']', False),
 ('equipment_schema', 19, 'Meaning', 'rep', ES19_OLD, ES19_NEW, False),
 ('equipment_schema', 19, 'Validation', 'app', ' | ', '[Superseded 2026-11-01 by ' + RULING + ': Meaning (part): ' + ES19_OLD + ']', False),
 ('save_data_contract', 3, 'Persistent_Fields', 'rep', 'starting_rarity (rarity it dropped or was bought at, never changed - sell value)',
   'starting_rarity (rarity it dropped or was bought at, never changed - tracking only, no price effect, USER RULING 2026-11-01), rune_forged (true once the Runeforge changes the item - forge, swap or reroll; never cleared; tracking/filtering only, USER DECISION 2026-11-01; PLANNED \u2014 not built, Runeforge step 4)', False),
 ('save_data_contract', 3, 'Migration_Rule', 'rep', 'starting_rarity = current rarity.', 'starting_rarity = current rarity, rune_forged = false.', False),
 ('guild_facilities', 57, 'rule', 'rep', GF57_G1_OLD, GF57_G1_NEW, False),
 ('guild_facilities', 57, 'rule', 'rep', GF57_G2_OLD, GF57_G2_NEW, False),
 ('guild_facilities', 57, 'notes', 'app', ' | ', RULING + ': guard (7) of the old list and option C (enchanted / forged items sell at their STARTING rarity) are SUPERSEDED, and there is no "Sells as ..." note. [Superseded 2026-11-01: rule guard (2): ' + GF57_G2_OLD + ']', False),
 ('open_decisions', 123, 'col_3', 'rep', OD123_OLD, OD123_NEW, False),
 # PART 3 build status - step 1
 ('materials_system', 6, 'notes', 'rep', T, built('1'), False),
 ('materials_system', 12, 'rule', 'app', ' ', 'A mission that is away is not offered again and cannot be sent twice (fix D-1, 2026-11-01).', False),
 ('materials_system', 12, 'notes', 'rep', T, built('1') + ' D-1 fix (no re-offer / double-send of an away mission) 2026-11-01.', False),
 ('materials_system', 20, 'notes', 'rep', T, built('1'), False),
 ('materials_system', 29, 'notes', 'rep', T, built('1'), False),
 ('materials_system', 30, 'notes', 'rep', T, built('1'), False),
 ('economy_framework', 19, 'notes', 'rep', T, built('1') + ' (running-total gold + Blacksmith discount).', False),
 ('guild_facilities', 48, 'notes', 'rep', T, "LOCKED - USER DECISION 2026-11-01 (v2). Levelling record " + B + " - v2 step 1. Runeforge catch-up: NOT BUILT (step 4).", False),
 ('equipment_schema', 20, 'Validation', 'rep', 'LOCKED - USER DECISION 2026-11-01 (v2); PLANNED \u2014 not built', 'LOCKED - USER DECISION 2026-11-01 (v2); ' + B + ' - v2 step 1', False),
 ('save_data_contract', 3, 'Failure_Behavior', 'rep', T, "LOCKED - USER DECISION 2026-11-01 (v2). Profile currencies + levelling_record " + B + " - v2 step 1; rune_forged and the Runeforge parts NOT BUILT.", False),
 ('service_boundaries', 16, 'Owns', 'rep', '(v2 2026-11-01, PLANNED \u2014 not built; replaces', '(v2 2026-11-01, ' + B + ' - v2 step 1; replaces', False),
 ('service_boundaries', 16, 'Failure_Boundary', 'rep', T, built('1'), False),
] + [
 ('materials_system', r, 'notes', 'rep', T, NOT6, False) for r in (7, 8, 9, 10, 11, 14)
] + [
 # step 2 + 3
 ('guild_facilities', 40, 'rule', 'app', '', GF40_SCREEN, False),
 ('guild_facilities', 40, 'notes', 'rep', T, built('2') + ' Screen: v2 step 3, ' + B + '.', False),
] + [
 ('guild_facilities', r, 'notes', 'rep', T, built('2'), False) for r in (47, 50, 51, 52)
] + [
 ('service_boundaries', 15, 'Owns', 'rep', 'PLANNED \u2014 not built (v2):', 'BUILT 2026-11-01 (v2 step 2):', True),
 ('service_boundaries', 15, 'Reads', 'rep', 'PLANNED \u2014 not built:', 'BUILT 2026-11-01 (v2 step 2):', True),
 ('service_boundaries', 15, 'Writes', 'rep', 'PLANNED \u2014 not built:', 'BUILT 2026-11-01 (v2 step 2):', True),
 ('service_boundaries', 15, 'Failure_Boundary', 'rep', 'PLANNED \u2014 not built: dismantle is atomic', 'BUILT 2026-11-01 (v2 step 2): dismantle is atomic', True),
 ('service_boundaries', 15, 'Failure_Boundary', 'rep', T, built('2'), False),
 ('implementation_plan', 53, 'col_2', 'rep', 'Blacksmith + Runeforge v2 LOCKED - USER DECISION 2026-11-01 (v2), NOT BUILT; next: Dev build plan (user approval before code)',
   'Blacksmith + Runeforge v2 LOCKED - USER DECISION 2026-11-01 (v2). BUILD STATUS 2026-11-01: steps 1-3 BUILT (1 mercury switch, 2 Blacksmith rules, 3 Blacksmith screen; source-verified by Tester, Studio test pending); step 4 (Runeforge rules) IN PROGRESS; battle mercury drops = step 6', False),
 ('implementation_plan', 53, 'col_2', 'rep', T, "LOCKED - USER DECISION 2026-11-01 (v2). Steps 1-3 " + B + "; step 4 in progress.", False),
 # PART 4 gem count
 ('materials_system', 4, 'rule', 'rep', 'about 153 kinds (25 numeric families \u00d7 T1-T4 = 100, including Fortune, + 53 passives)', GEMS_FIX, False),
 ('materials_system', 4, 'notes', 'app', ' | ', 'CORRECTION 2026-11-01 (Tester): was "about 153 kinds (25 numeric families x T1-T4 = 100, including Fortune, + 53 passives)".', False),
 ('materials_system', 40, 'rule', 'app', ' ', 'Kinds: 133 in the game content (20 numeric families \u00d7 T1-T4 = 80 gems + 53 bonus passives), not ~153 / 25 families; Collision Damage, Fall Damage Dealt, Collision Resistance, Fall Resistance and Item Direct Damage are in the DB only (not in BonusData) until the content file is regenerated - kept, not deleted (Tester correction 2026-11-01).', False),
 ('materials_system', 29, 'rule', 'rep', 'at most about 153 kinds', 'at most 133 kinds in the game content, materials_system 4', False),
 ('materials_system', 39, 'rule', 'rep', 'about 153 kinds', '133 kinds (materials_system 4)', False),
 ('save_data_contract', 3, 'Persistent_Fields', 'rep', 'at most about 153 kinds', 'at most 133 kinds in the game content, materials_system 4', False),
]

NEW_ES = ('rune_forged', 'Boolean', 'Persistent',
          'Set once the Runeforge changes the item (forge, swap or reroll); never cleared. Tracking/filtering only \u2014 no effect on price, dismantle yield or anything else (USER DECISION 2026-11-01)',
          'old items = false; PLANNED \u2014 not built (Runeforge build step 4)')
