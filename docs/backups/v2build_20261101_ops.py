# v2 build steps 4-6c + six user decisions + older UI/save records (2026-11-01). Ops only.
T = "LOCKED - USER DECISION 2026-11-01 (v2). NOT BUILT."
NOT6 = "LOCKED - USER DECISION 2026-11-01 (v2). NOT BUILT yet: battle mercury drops come in v2 build step 6 (the mercury currency itself is BUILT, step 1)."
B = "BUILT 2026-11-01 (source-verified by Tester; Studio test pending)"
UD = "USER DECISION 2026-11-01 (user accepted the Dev's defaults)"
def built(step): return "LOCKED - USER DECISION 2026-11-01 (v2). " + B + " - v2 step " + step + "."
HOLD = ("ON HOLD - NOT BUILT, deferred (" + UD + "): held until the 3-per-day boss reward limit (loot_progression 15) has a day counter; "
        "without that limit, boss replays would give unlimited crystals.")
NEEDS = "NOT BUILT - needs those systems first"

MS11_OLD = "1-3 mercury, shown upfront before acceptance (about 0.3 per battle)."
MS11_NEW = ("About 1 quest in 7 offers mercury: 1-3 mercury (rolled uniformly), shown on the quest list and the quest details before accepting. "
            "Paid on a qualifying victory only. Expected value 2/7 \u2248 0.29 mercury per quest, which keeps the total at about 0.3 per battle (" + UD + ").")
MS14_OLD = "30% chance with Salvager's Cap passive. 1 mercury (unchanged)."
MS14_NEW = ("ALWAYS with the Salvager's Cap passive: every qualifying destroyed object (objects breakable before rule 241 only - see the notes and "
            "nonweapon_equipment 34) gives the treasure reward roll AND 1 mercury (" + UD + "). The mercury is credited at once and kept even if the battle "
            "is later lost, like chest gold (DECIDED (DEV DEFAULT)).")
OE22_OLD = "Random treasure; inflicts Weakened (3000 CT)"
OE22_NEW = "Random treasure (1 mercury, the same as a Treasure Chest; no crystals and no rune gems); inflicts Weakened (3000 CT)"
OE31_OLD = "code change built later - today's code gives 6 free Rare items"
OE31_NEW = "code BUILT 2026-11-01, v2 step 6b"
IP_OLD1 = ("BUILD STATUS 2026-11-01: steps 1-3 BUILT (1 mercury switch, 2 Blacksmith rules, 3 Blacksmith screen; source-verified by Tester, Studio test pending); "
           "step 4 (Runeforge rules) IN PROGRESS; battle mercury drops = step 6")
IP_NEW1 = ("BUILD STATUS 2026-11-01: steps 1-6c BUILT (1 mercury switch, 2 Blacksmith rules, 3 Blacksmith screen, 4 Runeforge server rules, 5 Runeforge screen, "
           "6a battle mercury, 6b Black Market paid shop, 6c quest mercury + Runeforge over-budget rule; source-verified by Tester, Studio test pending). "
           "Boss resource grants are ON HOLD until the 3-per-day boss reward limit has a day counter (materials_system 9, 41; loot_progression 15); "
           "elite and daily-event rewards wait for those systems (materials_system 8, 13, 41)")
IP_OLD2 = "Steps 1-3 BUILT 2026-11-01 (source-verified by Tester; Studio test pending); step 4 in progress."
IP_NEW2 = "Steps 1-6c BUILT 2026-11-01 (source-verified by Tester; Studio test pending); boss grants on hold; elite / daily rewards wait for their systems."

GF44_ADD = (" Over-budget loot (" + UD + "): the points an item already has never count against it. Step (c) only raises the rarity when the new total is "
            "above BOTH the current rarity's budget AND the item's own total before this forge. Examples: a 1H Rare at 160 BP - a swap that keeps 160 stays "
            "Rare (4 crystals, needs Runeforge L4); going up to 170 makes it Epic. A 1H Epic at 215 - a swap that keeps 215 is allowed; 216 or more is refused. "
            "A 2H Uncommon at 205 - a swap stays Uncommon. The allowance is re-measured at each forge: an Epic forged down from 215 to 205 cannot later go back up to 215.")
GF54_OLD = "A forge result must fit the capacity rarity and BP."
GF54_NEW = ("A forge result must fit the capacity rarity and BP, except that a forge may keep the item's own total from before the forge even when it is "
            "above the capacity BP (over-budget loot, row 44, " + UD + "). Rarity-keeping swaps still need the capacity level for that rarity: "
            "Rare L4, Epic L7 (" + UD + "; confirms the current rule).")
GF45_ADD = (" Rarity-keeping swaps also need the capacity level for the item's rarity: Rare L4, Epic L7 (" + UD + "; confirms the current rule, rows 53-54 - status / clarity note only).")
GF42_SCREEN = (" Screen (v2 step 5, BUILT 2026-11-01): the Runeforge is its own full screen in the Merchant style, with Forge and Reroll tabs. "
               "Forge tab: tap a line to mark it for replacement, tap the gems that fit, and a live server price preview shows the result rarity, gold, "
               "crystals, catch-up, destroyed lines and the new name. Reroll tab: the offered sets plus 'Keep current', and the sulfur cost. "
               "Confirm always asks a second time. Nav tab 'Runeforge'.")

OE31_ADD = (" | " + built('6b') + " Built as written: 6 items (Rare 75% / Epic 25%) at 75% of the Merchant price, each bought once, kept whatever the battle "
            "result, breaking the object ends buying, and the screen asks for confirmation. The old free-cache code never actually produced items. "
            "'Interacting stays free' means: across the engine, 'Interact (Free)' costs 0 RT but still 1 AP - existing behaviour, not new. "
            "DECIDED (DEV DEFAULT): the shop does not pause the battle, and buying works even during enemy turns. [Superseded 2026-11-01: col_9 (part): " + OE31_OLD + "]")

CREDIT = "credited when the chest opens and kept even if the battle is later lost, like chest gold (DECIDED (DEV DEFAULT))"

# (table, rowid, column, mode, a, b, pre_only)  mode: set / rep (a -> b, exactly once) / app (append b with separator a)
OPS = [
 # ---- PART 1 #1 boss grants on hold
 ('materials_system', 9, 'rule', 'app', ' ', 'ON HOLD (USER DECISION 2026-11-01): not given until the 3-per-day boss reward limit (loot_progression 15) has a day counter.', False),
 ('materials_system', 9, 'notes', 'rep', NOT6, "LOCKED - USER DECISION 2026-11-01 (v2). Boss mercury: " + HOLD, False),
 ('materials_system', 41, 'rule', 'app', ' ', 'The boss part (5 crystals, 1 rune gem, content L60+: 1 sulfur, plus the 3 mercury of row 9) is ON HOLD (USER DECISION 2026-11-01) until the 3-per-day boss reward limit has a day counter.', False),
 ('materials_system', 41, 'notes', 'rep', T, T + " Boss part: " + HOLD + " Elite part: " + NEEDS + " (elite encounters do not exist in the code yet).", False),
 ('loot_progression', 15, 'notes', 'app', ' | ', '2026-11-01: the boss resource grants (materials_system 9, 41) are ON HOLD until this limit has a day counter (' + UD + ').', False),
 # ---- PART 1 #2 quest mercury (step 6c)
 ('materials_system', 11, 'rule', 'set', MS11_OLD, MS11_NEW, False),
 ('materials_system', 11, 'notes', 'rep', NOT6, built('6c') + " Resolves the conflict where '1-3 per quest' would have meant about 2 per battle. [Superseded 2026-11-01: rule: " + MS11_OLD + "]", False),
 # ---- PART 1 #3 Cursed Chest
 ('objects_encounters', 22, 'col_7', 'set', OE22_OLD, OE22_NEW, False),
 ('objects_encounters', 22, 'col_9', 'app', ' | ', UD + ": the Cursed Chest gives 1 mercury, the same as a Treasure Chest (no crystals, no rune gems) - it is riskier (Weakened), so it should not pay less. " + B + " - v2 step 6a (shares the chest reward code); " + CREDIT + ". [Superseded 2026-11-01: col_7: " + OE22_OLD + "]", False),
 ('materials_system', 10, 'rule', 'app', ' ', 'Cursed Chest: the same 1 mercury, no crystals and no rune gems (' + UD + '). The mercury is ' + CREDIT + '.', False),
 ('materials_system', 10, 'notes', 'rep', NOT6, built('6a') + ' Cursed Chest added 2026-11-01 (objects_encounters 22).', False),
 ('objects_encounters', 20, 'col_9', 'rep', T, built('6a') + ' The mercury is ' + CREDIT + '.', False),
 # ---- PART 1 #4 Salvager's Cap
 ('materials_system', 14, 'rule', 'set', MS14_OLD, MS14_NEW, False),
 ('materials_system', 14, 'notes', 'rep', NOT6, built('6a') + " [Superseded 2026-11-01: rule: " + MS14_OLD + " ('30% chance' was stale wording)]", False),
 # ---- PART 1 #5/#6 + PART 2 step 4/5 Runeforge
 ('guild_facilities', 44, 'rule', 'app', '', GF44_ADD, False),
 ('guild_facilities', 44, 'notes', 'rep', T, built('4') + " Over-budget loot rule: v2 step 6c, " + B + ". [Before 2026-11-01: step (c) had no allowance for the points the item already had.]", False),
 ('guild_facilities', 54, 'rule', 'rep', GF54_OLD, GF54_NEW, False),
 ('guild_facilities', 54, 'notes', 'rep', T, built('4') + " [Superseded 2026-11-01: rule (part): " + GF54_OLD + "]", False),
 ('guild_facilities', 45, 'rule', 'app', '', GF45_ADD, False),
 ('guild_facilities', 45, 'notes', 'rep', T, built('4'), False),
 ('guild_facilities', 42, 'rule', 'app', '', GF42_SCREEN, False),
 ('guild_facilities', 42, 'notes', 'rep', T, built('4') + " Screen: v2 step 5, " + B + ".", False),
] + [
 ('guild_facilities', r, 'notes', 'rep', T, built('4'), False) for r in (43, 46, 53, 55, 56, 58)
] + [
 ('guild_facilities', 48, 'notes', 'rep', 'Runeforge catch-up: NOT BUILT (step 4).', 'Runeforge catch-up: ' + B + ' - v2 step 4.', False),
 ('guild_facilities', 57, 'notes', 'rep', T, "LOCKED - USER DECISION 2026-11-01 (v2). v2 guards " + B + " - v2 step 4. The Epic step fee stays OFF (not built, by design).", False),
 ('equipment_schema', 21, 'Validation', 'rep', 'PLANNED \u2014 not built (Runeforge build step 4)', B + ' - v2 step 4', False),
 ('save_data_contract', 3, 'Persistent_Fields', 'rep', '; PLANNED \u2014 not built, Runeforge step 4)', '; ' + B + ' - v2 step 4)', False),
 ('save_data_contract', 3, 'Failure_Behavior', 'rep', 'rune_forged and the Runeforge parts NOT BUILT.', 'rune_forged and the Runeforge level ' + B + ' - v2 step 4.', False),
 # ---- step 6a battle mercury
 ('materials_system', 7, 'rule', 'app', ' ', 'Paid on a qualifying victory only, like item loot (DECIDED (DEV DEFAULT)). The reward screen shows "+N MERCURY".', False),
 ('materials_system', 7, 'notes', 'rep', NOT6, built('6a') + " Victory only: the DB did not say whether a defeat counts, so the Dev default (victory only, like item loot) was used.", False),
 # ---- step 6b Black Market
 ('objects_encounters', 31, 'col_9', 'rep', OE31_OLD, OE31_NEW, False),
 ('objects_encounters', 31, 'col_9', 'rep', T, "LOCKED - USER DECISION 2026-11-01 (v2).", False),
 ('objects_encounters', 31, 'col_9', 'app', '', OE31_ADD, False),
 # ---- economy_framework 11
 ('economy_framework', 11, 'notes', 'app', ' | ', 'BUG-073 fixed 2026-11-01: Blacksmith and Merchant priced 2H weapons as 1H (100) since Slice 6; now 150 everywhere.', False),
 # ---- not built: elite / daily
 ('materials_system', 8, 'notes', 'rep', NOT6, "LOCKED - USER DECISION 2026-11-01 (v2). " + NEEDS + ": elite encounters do not exist in the code yet (the rest of battle mercury is BUILT, v2 step 6a).", False),
 ('materials_system', 13, 'notes', 'rep', T, T + " Still " + NEEDS + ": daily events do not exist in the code yet (2026-11-01).", False),
 # ---- implementation_plan 53
 ('implementation_plan', 53, 'col_2', 'rep', IP_OLD1, IP_NEW1, False),
 ('implementation_plan', 53, 'col_2', 'rep', IP_OLD2, IP_NEW2, False),
 ('implementation_plan', 53, 'col_2', 'app', ' ', '[Superseded 2026-11-01: ' + IP_OLD1 + ']', False),
 # ---- PART 3 older items
 ('loadout_ui_spec', 84, 'rule', 'app', ' ', 'Exception: the Merchant and Tavern screens use + / - icons instead of bar buttons.', False),
 ('loadout_ui_spec', 84, 'notes', 'app', ' | ', '2026-11-01: Merchant / Tavern + / - icon exception recorded (from the earlier build).', False),
 ('loadout_ui_spec', 85, 'notes', 'app', ' | ', '2026-11-01: the Merchant and Tavern + / - controls are icons, not bar buttons (id 84 exception).', False),
 ('loadout_ui_spec', 75, 'rule', 'app', ' ', 'Guild screens put Back in the LOWER RIGHT instead; the Loadout screen keeps it top right.', False),
 ('loadout_ui_spec', 75, 'notes', 'app', ' | ', '2026-11-01: guild-screen Back position (lower right) recorded (from the earlier build).', False),
 ('save_data_contract', 1, 'Persistent_Fields', 'app', '; ', 'guildMenu.merchantBought (per-shelf purchase records, BUG-064), guildMenu.devShopRefresh (Studio-only dev nonce), guildMenu.tavernHired ({seed, ids}, BUG-067) - recorded 2026-11-01', False),
]

NEW_LUS = (101, 'Structure', 'Armor HP/MP display', 'Armor HP and MP are shown on both the Loadout screen and the Merchant screen.', 'Recorded 2026-11-01 (from the earlier build).')
