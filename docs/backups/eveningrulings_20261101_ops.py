# 2026-11-01 evening rulings + v2 steps 4-6 build status. Ops only; executed by the Designer write step.
B = "BUILT 2026-11-01 (source-verified by Tester; Studio test pending)"
U = "RESOLVED (USER) 2026-11-01"
DD = "DECIDED (DEV DEFAULT)"
L = "LOCKED - USER DECISION 2026-11-01 (v2)."
T = L + " NOT BUILT."
NOT6 = L + " NOT BUILT yet: battle mercury drops come in v2 build step 6 (the mercury currency itself is BUILT, step 1)."
def built(step): return L + " " + B + " - v2 step " + step + "."

MS11_OLD = "1-3 mercury, shown upfront before acceptance (about 0.3 per battle)."
MS11_NEW = ("About 1 quest in 7 offers 1-3 mercury, shown on the quest board before accepting. Paid on a qualifying victory only. "
            "Expected value 2/7 \u2248 0.29 mercury per quest, which keeps the about-0.3-per-battle total (" + U + ").")

MS14_OLD = "30% chance with Salvager's Cap passive. 1 mercury (unchanged)."
MS14_NEW = ("Salvager's Cap (nonweapon_equipment 34; " + U + ", ruling 4 - replaces the treasure-chest reward roll): EVERY time the wearer destroys a qualifying object "
            "it gives gold = round(12.5 \u00d7 (1 + Map Level / 50)) - half a chest's base gold (L1 13 / L50 25 / L99 37) - then the normal gold multipliers (RewardService.ApplyGold); "
            "plus a separate fixed 5% chance of 1 mercury; plus a separate fixed 5% chance of one equipment item, rolled like normal loot. Fortune does not raise either chance. "
            "Only objects that were breakable before rule 241; it never counts as a chest opened; Treasure Seeker does not apply. "
            "Salvage mercury is kept even if the battle is lost (credited at once, like chest gold). Reward details: " + DD + ".")

MS41_OLD = "Boss (counts toward the 3-per-day boss reward limit, loot_progression 15):"
MS41_NEW = ("Boss - ON HOLD (" + U + ", ruling 1: not built until a daily boss reward limit system exists in the game - there is no day counter yet - "
            "because without the limit bosses could be replayed for unlimited crystals; once built it counts toward the 3-per-day boss reward limit, loot_progression 15):")

NW34_OLD = "Destroying a breakable object yields one treasure reward roll. (50 BP)"
NW34_NEW = ("Destroying a breakable object gives a little gold - round(12.5 \u00d7 (1 + Map Level / 50)), half a chest's base gold (L1 13 / L50 25 / L99 37), then the normal gold multipliers - "
            "plus a separate fixed 5% chance of 1 mercury and a separate fixed 5% chance of one equipment item rolled like normal loot. Triggers every time; Fortune does not raise the chances; "
            "never counts as a chest opened; Treasure Seeker does not apply (materials_system 14). (50 BP)")
NW34_RES_OLD = "Once per object; no roll if the object has no salvage table, for objects made breakable on 2026-10-30, or for a Bomb Barrel that explodes."
NW34_RES_NEW = "Once per object. Only objects that were breakable before 2026-10-30 (rule 241); nothing for objects made breakable on 2026-10-30 or for a Bomb Barrel that explodes."
NW34_TXT_OLD = "Destroying a breakable object gives one treasure reward roll."
NW34_TXT_NEW = "Destroying a breakable object gives a little gold, plus a 5% chance of 1 mercury and a 5% chance of a gear item."

OE22_OLD = "Random treasure; inflicts Weakened (3000 CT)"
OE22_NEW = "Random treasure (including 1 mercury, same as a Treasure Chest); inflicts Weakened (3000 CT)"

GF44_OLD = "(c) the lowest rarity whose normal budget holds the total BP (Uncommon 100 / Rare 150 / Epic 200; 2H doubled)."
GF44_NEW = ("(c) the budget check: bonus points the item already has never count against it. The check raises the rarity only when the new total is above BOTH the current rarity's "
            "normal budget (Uncommon 100 / Rare 150 / Epic 200; 2H doubled) AND the item's own total before this forge; then the new rarity is the lowest one whose budget holds the new total. "
            "An Epic over 200 can be forged as long as its total does not rise above its own total (" + U + ").")

IP53_OLD = ("BUILD STATUS 2026-11-01: steps 1-3 BUILT (1 mercury switch, 2 Blacksmith rules, 3 Blacksmith screen; source-verified by Tester, Studio test pending); "
            "step 4 (Runeforge rules) IN PROGRESS; battle mercury drops = step 6")
IP53_NEW = ("BUILD STATUS 2026-11-01 (evening): steps 1-6 BUILT (1 mercury switch, 2 Blacksmith rules, 3 Blacksmith screen, 4 Runeforge rules, 5 Runeforge screen, "
            "6a kill / chest / salvage mercury, 6b paid Black Market, 6c quest mercury + Runeforge over-budget rule; source-verified by Tester, Studio test pending); "
            "BUG-073 fixed (2H weapons were priced as 1H in the Blacksmith, Runeforge and Merchant since Slice 6); Salvager's Cap new reward (materials_system 14): code written, "
            "Tester source check running. NOT BUILT: elite encounter grants (materials_system 8, 41 - elite encounters do not exist in code), daily events (materials_system 13 - "
            "no daily event system), boss grants (materials_system 9, 41, loot_progression 15 - ON HOLD until a daily boss reward limit exists)")
IP53_TAIL_OLD = "Steps 1-3 BUILT 2026-11-01 (source-verified by Tester; Studio test pending); step 4 in progress."
IP53_TAIL_NEW = "Steps 1-6 BUILT 2026-11-01 (source-verified by Tester; Studio test pending), except the NOT BUILT items listed above."

BUG073 = ("BUG-073 FIXED 2026-11-01: since Slice 6 the Blacksmith, Runeforge and Merchant priced 2H weapons with the 1H base value (100 instead of 150); "
          "they now use 2H = 150 (economy_framework 15, 19; guild_facilities 55). " + B + ".")

TQ3 = ("INFORMATION (Tester step 4 question 3, recorded 2026-11-01): reroll sets depend on what the game's bonus content file (BonusData) holds, so regenerating it - "
       "for example adding the 5 DB-only families - changes every item's reroll offers")

# (table, rowid, column, mode, a, b)   mode: set (a = expected full old), rep (a -> b exactly once), app (append b with separator a)
OPS = [
 # ---- PART 1 rulings ----
 ('materials_system', 7, 'rule', 'app', ' ', 'Paid on a victory only, like item loot: a defeat gives no kill mercury.'),
 ('materials_system', 7, 'notes', 'rep', NOT6, built('6a') + ' Victory-only recorded 2026-11-01.'),
 ('materials_system', 8, 'notes', 'rep', NOT6, L + ' NOT BUILT (status 2026-11-01): elite encounters do not exist in the game code yet, so this grant has nothing to come from. The mercury currency itself is BUILT (step 1).'),
 ('materials_system', 9, 'rule', 'app', ' ', 'ON HOLD - ' + U + ' (ruling 1): not built until a daily boss reward limit system exists in the game (there is no day counter yet). Reason: without the limit, bosses could be replayed for unlimited crystals.'),
 ('materials_system', 9, 'notes', 'rep', NOT6, L + ' NOT BUILT - ON HOLD (' + U + ', ruling 1; see loot_progression 15).'),
 ('materials_system', 10, 'rule', 'app', ' ', 'Cursed Chest gives the same 1 mercury (' + U + ': it is riskier - it inflicts Weakened - so it should not pay less; objects_encounters Cursed Chest). Chest mercury is credited when the chest opens, so it is kept even if the battle is lost (same as chest gold).'),
 ('materials_system', 10, 'notes', 'rep', NOT6, built('6a') + ' Cursed Chest mercury (' + U + ') built in step 6a.'),
 ('materials_system', 11, 'rule', 'set', MS11_OLD, MS11_NEW),
 ('materials_system', 11, 'notes', 'rep', NOT6, built('6c')),
 ('materials_system', 11, 'notes', 'app', ' ', '[Superseded 2026-11-01 (ruling 2): rule: ' + MS11_OLD + ']'),
 ('materials_system', 13, 'notes', 'rep', T, L + ' NOT BUILT (status 2026-11-01): the game has no daily event system yet.'),
 ('materials_system', 14, 'rule', 'set', MS14_OLD, MS14_NEW),
 ('materials_system', 14, 'notes', 'rep', NOT6, L + ' Salvage mercury ' + B + ' - v2 step 6a. New Salvager\'s Cap reward (ruling 4): code written 2026-11-01, Tester source check running - not yet verified.'),
 ('materials_system', 14, 'notes', 'app', ' | ', U + " (ruling 4): resolves the conflict between this row ('30% chance') and nonweapon_equipment 34 ('always'): the reward triggers EVERY time, and the reward is the gold + 5% mercury + 5% gear above. [Superseded 2026-11-01: rule: " + MS14_OLD + ']'),
 ('materials_system', 41, 'rule', 'rep', MS41_OLD, MS41_NEW),
 ('materials_system', 41, 'notes', 'rep', T, L + ' NOT BUILT (status 2026-11-01): elite part - elite encounters do not exist in the game code yet; boss part - ON HOLD (ruling 1).'),
 ('materials_system', 41, 'notes', 'app', ' ', '[Superseded 2026-11-01 (ruling 1): rule (part): ' + MS41_OLD + ']'),
 ('materials_system', 4, 'notes', 'app', ' | ', TQ3 + ' (guild_facilities 54).'),
 ('loot_progression', 15, 'notes', 'app', ' | ', U + ' (ruling 1): this daily limit is not in the game yet (no day counter). Boss resource grants (materials_system 9, 41) are ON HOLD until it is built - without it bosses could be replayed for unlimited crystals.'),
 ('nonweapon_equipment', 34, 'rule', 'rep', NW34_OLD, NW34_NEW),
 ('nonweapon_equipment', 34, 'rule', 'app', ' ', '[USER RULING 2026-11-01 (ruling 4, ' + U + '; reward details ' + DD + '): replaces the treasure reward roll; code written 2026-11-01, Tester source check running.] [Superseded 2026-11-01: rule: Destroying a breakable object yields one treasure reward roll. | restriction: ' + NW34_RES_OLD + ' | display_text: ' + NW34_TXT_OLD + ']'),
 ('nonweapon_equipment', 34, 'restriction', 'set', NW34_RES_OLD, NW34_RES_NEW),
 ('nonweapon_equipment', 34, 'display_text', 'set', NW34_TXT_OLD, NW34_TXT_NEW),
 ('objects_encounters', 22, 'col_7', 'set', OE22_OLD, OE22_NEW),
 ('objects_encounters', 22, 'col_9', 'app', ' | ', U + ': 1 mercury, the same as a Treasure Chest (materials_system 10) - it is riskier (Weakened), so it should not pay less. ' + B + ' - v2 step 6a. Mercury is credited when the chest opens, so it is kept even if the battle is lost. [Superseded 2026-11-01: col_7: ' + OE22_OLD + ']'),
 ('objects_encounters', 20, 'col_9', 'rep', T + ' [Superseded', L + ' Chest mercury ' + B + ' - v2 step 6a; it is credited when the chest opens, so it is kept even if the battle is lost (same as chest gold). [Superseded'),
 ('objects_encounters', 31, 'col_9', 'rep', "code change built later - today's code gives 6 free Rare items", 'built 2026-11-01, v2 step 6b'),
 ('objects_encounters', 31, 'col_9', 'rep', T + ' [Superseded 2026-11-01 by v2:', L + ' Paid shop ' + B + " - v2 step 6b. Note: the old free cache never actually produced items. " + DD + " 2026-11-01: 'interacting stays free' means no RT but still 1 AP, as for every 'Interact (Free)' object; shopping is allowed during enemy turns - the shop does not pause the battle. [Superseded 2026-11-01 by v2:"),
 ('objects_encounters', 31, 'col_9', 'app', ' ', "[Superseded 2026-11-01 (build): code change built later - today's code gives 6 free Rare items]"),
 # ---- PART 1 Runeforge rulings ----
 ('guild_facilities', 44, 'rule', 'rep', GF44_OLD, GF44_NEW),
 ('guild_facilities', 44, 'notes', 'rep', T, L + ' ' + B + ' - v2 step 4; over-budget rule (c) v2 step 6c.'),
 ('guild_facilities', 44, 'notes', 'app', ' | ', U + ' (ruling 5). Tester note: the allowance is the item\'s total at EACH forge, so if a forge lowers an over-budget Epic from 215 to 205, a later forge back up to 215 is refused. [Superseded 2026-11-01 (ruling 5): rule ' + GF44_OLD + ']'),
 ('guild_facilities', 54, 'notes', 'rep', T, built('4')),
 ('guild_facilities', 54, 'notes', 'app', ' | ', U + ' (ruling 6, answers Tester step 4 question 2): confirmed as written - a forge that keeps the rarity (a swap) still needs the Runeforge level for that rarity: Rare L4, Epic L7. | ' + TQ3 + ' (materials_system 4).'),
 # ---- PART 2 build status ----
 ('guild_facilities', 42, 'notes', 'rep', T, built('4') + ' Runeforge screen: v2 step 5, ' + B + '.'),
] + [
 ('guild_facilities', r, 'notes', 'rep', T, built('4')) for r in (43, 45, 46, 53, 55, 56, 57, 58)
] + [
 ('guild_facilities', 48, 'notes', 'rep', 'Runeforge catch-up: NOT BUILT (step 4).', 'Runeforge catch-up: ' + B + ' - v2 step 4.'),
 ('guild_facilities', 55, 'notes', 'app', ' | ', 'BUG-073 FIXED 2026-11-01: 2H weapons had been priced as 1H (slot value 100 instead of 150, economy_framework 11) in the Blacksmith, Runeforge and Merchant since Slice 6; the 2H prices in this row are what the game now charges. ' + B + '.'),
 ('economy_framework', 11, 'notes', 'app', ' | ', BUG073),
 ('economy_framework', 15, 'notes', 'app', ' | ', 'BUG-073 FIXED 2026-11-01: Merchant prices for 2H weapons now use Base Value 150 (they were priced as 1H = 100 since Slice 6; economy_framework 11). ' + B + '.'),
 ('economy_framework', 19, 'notes', 'app', ' | ', 'BUG-073 FIXED 2026-11-01: Blacksmith upgrade gold for 2H weapons now uses Base Value 150 (it was priced as 1H = 100 since Slice 6; economy_framework 11). ' + B + '.'),
 ('equipment_schema', 21, 'Validation', 'rep', 'PLANNED \u2014 not built (Runeforge build step 4)', B + ' - v2 step 4'),
 ('save_data_contract', 3, 'Persistent_Fields', 'rep', 'PLANNED \u2014 not built, Runeforge step 4)', B + ' - v2 step 4)'),
 ('save_data_contract', 3, 'Failure_Behavior', 'rep', 'rune_forged and the Runeforge parts NOT BUILT.', 'rune_forged ' + B + ' - v2 step 4; the other Runeforge parts of this row (reroll_count, forged-item load check) are not yet confirmed as built.'),
 ('implementation_plan', 53, 'col_2', 'rep', IP53_OLD, IP53_NEW),
 ('implementation_plan', 53, 'col_2', 'rep', 'stock 75% Rare / 25% Epic.', 'stock 75% Rare / 25% Epic. DONE 2026-11-01 (step 6b).'),
 ('implementation_plan', 53, 'col_2', 'rep', IP53_TAIL_OLD, IP53_TAIL_NEW),
 ('implementation_plan', 53, 'col_2', 'app', ' ', '[Superseded 2026-11-01 (evening build status): ' + IP53_OLD + '; ' + IP53_TAIL_OLD + ']'),
]
