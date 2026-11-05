# Training Grounds write pass 2026-11-04. Run with DRY=True first.
import sqlite3, os, shutil, json, datetime, hashlib, openpyxl, copy
session = {}
D = r'D:\AI\Projects\CTRBLXAI\docs'
DB = os.path.join(D, 'CTRBLXAI.db')
TAG = 'RESOLVED (USER) 2026-11-04 (Training Grounds). NOT BUILT - the Dev is building it now.'
SUP = '[Superseded 2026-11-04 (Training Grounds): '
SIMNOTE = ("Simulator sim\\training_grounds_2026-11-04\\report.md: no change needed. Free players open slot 2 only if they rush the "
           "Training Grounds (slot 2 at battle 428 = unit L80, but only 3-7 of 10 facilities maxed instead of 6-8); normal build orders "
           "never reach Training Grounds L10. Buying cards (Designer basket) adds 12-14 points of spending. The user already accepted "
           "\"many free players may never open slot 2\".")
LOCK = 'slot 2 locked until Training Grounds L10 + unit L80, guild_facilities 79'

def ap(old, add):
    return add if not old else old + ' | ' + add

edits = []   # (table, keycol, keyval, col, new_value_func, must_contain)
def E(t, kc, kv, col, fn, must):
    edits.append((t, kc, kv, col, fn, must))

def repl(a, b):
    def f(o):
        assert o.count(a) == 1, (a, o[:80])
        return o.replace(a, b)
    return f
def setv(v):
    return lambda o: v
def suprule(colname='rule'):
    return None

# ---------------- guild_facilities superseded rows ----------------
for i in (20, 21, 22, 23, 32, 33):
    E('guild_facilities', 'id', i, 'rule', lambda o: '[SUPERSEDED 2026-11-04 - merged into the Training Grounds (rows 74-83); never built.] ' + o, 'Total' if i in (20, 22, 32, 33) else '')
    E('guild_facilities', 'id', i, 'notes', lambda o: ap(o, 'SUPERSEDED (USER) 2026-11-04 (Training Grounds): the Training Ground and the Library were never built; they merge into one building, the Training Grounds (rows 74-83). Row kept for the record.'), 'Locked')

# ---------------- guild_facilities rows edited in place ----------------
NEW = {}
NEW[('guild_facilities', 5)] = ("70,927g across all 10 facilities (the original 9 = 62,008g, minus the Library's 6,277g now that it is merged into the Training Grounds (2026-11-04), "
    "+ the Runeforge 8,919g + the Crucible 6,277g). Simulator 2026-11-04 (sim\\training_grounds_2026-11-04; normal refills; crafting from Rare / from Common): "
    "free player, classic build order, no cards bought: about 111.4 / 114.0% of lifetime gold, 6 of 10 maxed; selling every loot card: 106.0 / 108.5%; "
    "buying the Designer card basket adds 12-14 points. Boosted player: 86.2 / 88.0%, 10/10. Crucible merge fees, card buying (row 75) and paid refills are extra gold sinks.")
NEW[('guild_facilities', 8)] = "L1: Tavern. L2: Blacksmith, Merchant. L3: Quest Board. L4: Apothecary, Runeforge. L5: Training Grounds, Crucible. L6: no new building (the Library merged into the Training Grounds 2026-11-04; Guild Hall L6 still gives its quest and dispatch slots). L7: Trophy Hall."
NEW[('guild_facilities', 35)] = ("Simulator 2026-11-04 (10 facilities, 70,927g; normal refills; crafting from Rare / from Common): classic build order, no cards: maxes 6 of 10, about 111.4 / 114.0% of lifetime gold; "
    "selling every loot card: 106.0 / 108.5%, 8 / 7 of 10; buying the Designer card basket adds 12-14 points. Training Grounds rush (the only free route to the 2nd augment slot): "
    "slot 2 at battle 428 (unit L80), but only 3-7 of 10 maxed (2 of 10 if cards are bought too). Normal build orders never reach Training Grounds L10.")
NEW[('guild_facilities', 36)] = ("Simulator 2026-11-04 (10 facilities, 70,927g): maxes 10/10 at about 86.2 / 88.0% of lifetime gold with no cards bought (82.3 / 84.1% selling loot cards; "
    "94.5 / 96.5% with the Designer card basket + card sales). Slot 2 opens at battle 428-467 in the classic order.")
NEW[('guild_facilities', 37)] = ("Simulator 2026-11-04 (10 facilities): free player about 111.4 / 114.0% of lifetime gold with no cards (6 of 10 maxed), 106.0 / 108.5% selling loot cards, "
    "+12-14 points if the Designer card basket is bought; boosted about 86.2 / 88.0% (10/10). Keeps the intended 'can't do everything' pressure on luxury facilities for free players. "
    "Card buying is optional; in normal build orders free players barely use the card shop and never open slot 2 (accepted by the user).")
for i in (5, 8, 35, 36, 37):
    E('guild_facilities', 'id', i, 'rule', (lambda v: (lambda o: v))(NEW[('guild_facilities', i)]), '')
    E('guild_facilities', 'id', i, 'notes', None, '')   # filled with old rule below
E('guild_facilities', 'id', 59, 'rule', lambda o: o.replace('(the same curve as the Tavern, Merchant and Library)', '(the same curve as the Tavern and Merchant; the Library that shared it merged into the Training Grounds 2026-11-04)').replace('(shared with the Training Ground)', '(shared with the Training Grounds)'), '(shared with the Training Ground)')
E('guild_facilities', 'id', 59, 'notes', None, '')
E('guild_facilities', 'id', 67, 'rule', repl('so there are still 11 facilities and the 77,204g total does not change.', 'so the facility count and total did not change (11 facilities, 77,204g at the time; 10 facilities, 70,927g since the 2026-11-04 Training Grounds merge).'), '')
E('guild_facilities', 'id', 67, 'notes', None, '')
E('guild_facilities', 'id', 39, 'rule', lambda o: o.replace(' Old saves without it', ' PLANNED (RESOLVED (USER) 2026-11-04, NOT BUILT): the Training Grounds level is saved the same way, in buildingLevels next to the other buildings; its effective level is 0 until Guild Hall L5 and is capped at the Guild Hall level; like the Merchant and Apothecary it needs a per-shelf bought record so each shelf item can be bought once. Old saves without it', 1), ' Old saves without it')
E('guild_facilities', 'id', 39, 'notes', None, '')

# ---------------- economy_framework ----------------
EF = {
 28: ("Long-term gold sink. Luxury progression. 10 facilities totaling 70,927g (original 9 = 62,008g, minus the Library 6,277g merged into the Training Grounds 2026-11-04, + Runeforge 8,919g + Crucible 6,277g). "
      "Gold-only (no materials). Simulator 2026-11-04: free player about 111.4 / 114.0% of lifetime gold, 6 of 10 maxed (no cards bought); boosted 86.2 / 88.0%, 10/10 (guild_facilities 5, 35-37). "
      "Crucible merge fees, card buying at the Training Grounds (guild_facilities 75) and paid refills are extra gold sinks; selling loot cards gives back about 4.5% of lifetime income."),
 29: "round(Base × (1 + Level² / Scale)). Each facility has its own Base and Scale. Total 70,927g across 10 facilities (max L10 each, Trophy Hall L5). Gold ONLY — no materials.",
 44: ("~70,900g across 10 facilities (the Training Ground and Library merged into the Training Grounds 2026-11-04; ~62,000g for the original 9). Gold-only costs. "
      "Simulator 2026-11-04: a free player maxes about 6 of 10 (classic order, no cards) — creates endgame engagement."),
 45: ("Covers all basics. Simulator 2026-11-04 (10 facilities): about 111.4 / 114.0% of lifetime gold, 6 of 10 maxed with no cards; 106.0 / 108.5% selling loot cards; "
      "buying the Designer card basket adds 12-14 points. Opens the 2nd augment slot only by rushing the Training Grounds (accepted by the user)."),
 46: "Covers basics + all 10 facilities maxed (Simulator 2026-11-04: about 86.2 / 88.0% of lifetime gold with no cards, 94.5 / 96.5% with the Designer card basket + card sales).",
}
for i, v in EF.items():
    E('economy_framework', 'id', i, 'rule', (lambda v: (lambda o: v))(v), '')
    E('economy_framework', 'id', i, 'notes', None, '')

# ---------------- game_flow / development_slices ----------------
E('game_flow', 'id', 8, 'rule', repl('Library (skill and augment cards), Training Ground (benched XP, practice battles)', 'Training Grounds (buy and sell skill cards, augment cards and doctrines; 2nd augment slot at L10 for units L80+; the old Training Ground and Library merged into it, RESOLVED (USER) 2026-11-04, NOT BUILT)'), '')
E('game_flow', 'id', 8, 'notes', None, '')
E('development_slices', 'slice', 8, 'description', lambda o: o.replace('Apothecary, Training Ground, Trophy Hall', 'Apothecary, Training Grounds, Trophy Hall', 1).replace(' [Superseded 2026-11-03: Workshop]', ' Training Grounds (the Training Ground and Library merged into one card shop; 10 facilities, 70,927g) RESOLVED (USER) 2026-11-04, NOT BUILT. [Superseded 2026-11-03: Workshop]', 1) + ' ' + SUP + 'Training Ground]', 'Apothecary, Training Ground, Trophy Hall')

# ---------------- augment slot rows ----------------
E('project_rules', 'id', 48, 'topic', repl('have exactly 2 Augment Slots.', 'have 2 Augment Slots (' + LOCK + ').'), '')
E('project_rules', 'id', 65, 'topic', repl('have exactly 2 Augment Slots.', 'have 2 Augment Slots (' + LOCK + ').'), '')
E('project_rules', 'id', 55, 'topic', setv("Every representative Skill and every future Skill Card has 2 Augment Slots. Slot 1 is always open; slot 2 opens only when the owner's Training Grounds is at effective level 10 AND the unit is level 80+ (USER RULING 2026-11-04, guild_facilities 79). This includes Doctrine-provided Skills and Steal. Slot count does not vary by Skill type, rarity, source, tags, power, complexity, costs, timing, inheritance, projectile behavior, Pattern, AOE behavior, or acquisition source."), '')
E('project_rules', 'id', 57, 'topic', setv("All Skill Cards have 2 Augment Slots: slot 1 always open, slot 2 locked until the owner's Training Grounds is at effective level 10 and the unit is level 80+ (USER RULING 2026-11-04, guild_facilities 79). Doctrine-provided Skills use the same rule. Skill rarity and source do not modify Augment Slot count."), '')
for i in (48, 65, 55, 57):
    E('project_rules', 'id', i, 'notes', None, 'topic')
E('project_rules', 'id', 52, 'notes', lambda o: ap(o, '2026-11-04 (Training Grounds): items 5-7 partly answered - skill cards, augment cards and doctrines can now be bought and sold at the Training Grounds (guild_facilities 74-83); loot rates unchanged, doctrine loot still display-only.'), '')

FW = {
 26: "2 Augment Slots for every Skill Card: slot 1 always open; slot 2 locked until the owner's Training Grounds is at effective level 10 and the unit is level 80+ (USER RULING 2026-11-04, guild_facilities 79). Enemies carry 1 augment per skill, plus the level-80+ roll for a 2nd when the quest owner's Training Grounds is L10 (guild_facilities 79). This is universal and does not vary by Skill type, effect tags, Target Rules, rarity, source, Doctrine source, power, complexity, costs, timing, inheritance, projectile behavior, Pattern, AOE behavior, or acquisition source. Skill rarity does not add, remove, or modify Augment Slots.",
}
E('frameworks', 'id', 26, 'rule', lambda o: FW[26] + ' ' + SUP + o + ']', '')
E('frameworks', 'id', 32, 'rule', lambda o: o.replace('Every Skill Card has exactly 2 Augment Slots.', 'Every Skill Card has 2 Augment Slots (' + LOCK + ').') + ' ' + SUP + 'Every Skill Card has exactly 2 Augment Slots.]', 'Every Skill Card has exactly 2 Augment Slots.')
E('frameworks', 'id', 34, 'rule', lambda o: o.replace('Every Skill Card always has exactly 2 Augment Slots.', 'Every Skill Card always has 2 Augment Slots (' + LOCK + '). Each card also has one fixed shop rarity at the Training Grounds (guild_facilities 76-77), which is scarcity only.') + ' ' + SUP + 'Every Skill Card always has exactly 2 Augment Slots.]', 'Every Skill Card always has exactly 2 Augment Slots.')
E('frameworks', 'id', 68, 'rule', lambda o: o.replace('Every Skill Card has exactly 2 Augment Slots; zero, one, or two attached Augments are valid and filling both is optional.', "Every Skill Card has 2 Augment Slots; slot 2 is locked until the owner's Training Grounds is L10 and the unit is level 80+ (guild_facilities 79). Zero, one, or (when slot 2 is open) two attached Augments are valid and filling both is optional.") + ' ' + SUP + 'Every Skill Card has exactly 2 Augment Slots; zero, one, or two attached Augments are valid and filling both is optional.]', 'Every Skill Card has exactly 2 Augment Slots; zero, one, or two')

E('weapons_equipment', 'id', 59, 'topic', lambda o: o.replace('Every Skill Card has exactly 2 Augment Slots.', 'Every Skill Card has 2 Augment Slots (' + LOCK + ').') + ' Each card has one fixed shop rarity at the Training Grounds by these rules (guild_facilities 76-77).', 'Every Skill Card has exactly 2 Augment Slots.')
E('weapons_equipment', 'id', 60, 'topic', lambda o: o + ' Doctrines are sold at the Training Grounds at one flat price (card value 1,000, no rarity multiplier; guild_facilities 75). The doctrine skill row follows the same locked slot-2 rule as every skill (guild_facilities 79).', '')
for i in (59, 60):
    E('weapons_equipment', 'id', i, 'notes', None, 'topic')

E('loadout_ui_spec', 'id', 39, 'rule', repl('augment slot 1, augment slot 2.', 'augment slot 1, augment slot 2 (slot 2 shows a lock with the tooltip "Unlocks at Training Grounds Lv 10 and unit Lv 80." until it opens; guild_facilities 79, 83).'), '')
E('loadout_ui_spec', 'id', 40, 'rule', repl('Supports 2 Augment Cards.', 'Supports 2 Augment Cards (' + LOCK + ').'), '')
E('loadout_ui_spec', 'id', 41, 'rule', repl('Each has 2 Augment attachment slots.', 'Each has 2 Augment attachment slots (' + LOCK + ').'), '')
for i in (39, 40, 41):
    E('loadout_ui_spec', 'id', i, 'notes', None, '')

E('save_data_contract', 'Record', 'SkillInstance', 'Load_Validation', lambda o: '0..1 Augments, or 0..2 when slot 2 is open for that unit (Training Grounds L10 + unit L80, guild_facilities 79); compatibility and conflicts pass ' + SUP + o + ']', '0..2 Augments')
E('save_data_contract', 'Record', 'SkillInstance', 'Migration_Rule', lambda o: o + '; an augment in a locked slot 2 goes back to storage with the approved notice (guild_facilities 79, 83; RESOLVED (USER) 2026-11-04, NOT BUILT)', '')
E('save_data_contract', 'Record', 'ProfileSave', 'Persistent_Fields', lambda o: o + '; Training Grounds (RESOLVED (USER) 2026-11-04, NOT BUILT): its level saved in buildingLevels with the other buildings (replaces the never-built Training Ground and Library levels), plus a per-shelf bought record like guildMenu.merchantBought (guild_facilities 39).', '')
E('skill_augment_schemas', '05_—_Skill_&_Augment_Runtime_Schemas', 'attached_augment_ids', 'col_2', lambda o: '0..1 IDs, or 0..2 when slot 2 is open (guild_facilities 79) ' + SUP + o + ']', '0..2 IDs')
E('validation_matrix', 'Area', 'Augment attachment', 'Invariant', lambda o: '0..1, or 0..2 when slot 2 is open (Training Grounds L10 + unit L80, guild_facilities 79); all requirements pass; conflict groups unique; an augment in a locked slot 2 is refused ' + SUP + o + ']', '0..2;')

E('loot_progression', 'id', 42, 'notes', lambda o: ap(o, '2026-11-04 (Training Grounds, Dev default 18): the card loot label shows the card\'s fixed shop rarity (guild_facilities 76-77) instead of a random roll; cosmetic, nothing saved. RESOLVED (USER) 2026-11-04, NOT BUILT.'), '')

# ---------------- open_decisions (rowid) ----------------
E('open_decisions', 'rowid', 15, 'col_2', setv('Partly resolved (USER) 2026-11-04'), 'Parked')
E('open_decisions', 'rowid', 15, 'col_3', lambda o: 'Shop route decided: the Training Grounds buys and sells skill cards, augment cards and doctrines (guild_facilities 74-83). Card scarcity from loot stays as it is (parked). ' + SUP + 'col_2: Parked; col_3: ' + o + ']', 'Acquisition scarcity remains parked.')
E('open_decisions', 'rowid', 29, 'col_2', lambda o: o + ' 2026-11-04 (Training Grounds): items 5-7 partly answered - skill cards, augment cards and doctrines can now be bought and sold at the Training Grounds (guild_facilities 74-83); loot rates unchanged, doctrine loot still display-only.', '')
E('open_decisions', 'rowid', 34, 'col_2', setv('Resolved / Locked - UPDATED (USER) 2026-11-04'), 'Resolved / Locked')
E('open_decisions', 'rowid', 34, 'col_3', lambda o: "Every Skill Card has 2 Augment Slots, including Doctrine-provided Skills, regardless of type, rarity, source, tags, power, or complexity. Slot 2 is locked until the owner's Training Grounds is L10 and the unit is level 80+ (USER RULING 2026-11-04, guild_facilities 79). No per-Skill slot-count review remains. " + SUP + 'col_2: Resolved / Locked; col_3: ' + o + ']', 'exactly 2 Augment Slots')
E('open_decisions', 'rowid', 56, 'col_3', lambda o: o + ' USER RULING 2026-11-04 (Training Grounds): Elite augments per skill 2 -> 1; enemies at level 80+ roll a 2nd augment per skill row (Elite 100% / Veteran 50% / Grunt 25%, seeded) only when the quest owner\'s Training Grounds is L10 (guild_facilities 79). NOT BUILT - the Dev is building it now.', 'TIER_BUILD')

# ---------------- doctrines ----------------
DOC_OLD = {'Every Doctrine Skill has exactly 2 Augment Slots': 'Every Doctrine Skill has 2 Augment Slots (' + LOCK + ')',
           'Standard 2 Augment Slots': 'Standard 2 Augment Slots (' + LOCK + ')'}

# ---------------- new rows ----------------
NOTE_NEW = TAG
DEV_DEFAULTS = (
"DEV DEFAULTS (20, recorded exactly as written in the proposal, section G): "
"1. Unlock at Guild Hall L5, max L10, old Training Ground curve (7,495g). Reason: same spot, cheapest change, total 70,927g. "
"2. Guild Hall L6 left with no new building. Reason: only the Library was there. "
"3. Buy discount 3%/level (L10 −27%). Reason: same as every other shop. "
"4. Shelf 4,4,5,5,6,6,7,7,8,8, restock every 5 completed battles, seeded, each item bought once, no duplicates. Reason: Apothecary/Merchant pattern. "
"5. Odds table C2 (Epic L4, Legendary L8), dropping a rarity if none are unlocked. Reason: Merchant style; Legendary is late because it holds the build-defining cards. "
"6. Type unlocks: Attack + Support skills L1, Basic augments L2, Control & Utility skills L3, Advanced augments L4, Doctrines L6. Reason: simple cards first; summons/conversions come late via Legendary odds. "
"7. One shelf slot is always a doctrine from L6. Reason: doctrines are a separate band; a reserved slot is easy to read. "
"8. Fixed shop rarity per card by the C3 rules. Reason: follows the existing scarcity rule (weapons_equipment 59); never changes power. "
"9. Prices C4 (augment 60 / skill 100 / doctrine 1,000 × rarity × level multiplier). Reason: equipment formula shape; keeps buying power steady. "
"10. Price uses the player's highest unlocked map level. Reason: cards have no level; same input the Crucible cap uses. "
"11. Sell = list / 16, not changed by level; equipped/bound/dispatched cards can't be sold. Reason: the Merchant's 16:1, no loop. "
"12. Old jobs per C6 (drop benched XP, training battles, storage and research; preview moves into the shop; buy/sell kept, trading dropped). Reason: none of them are built, and the benched bonus contradicts the locked 65%. "
"13. Slot 2 covers every row, including the doctrine skill and Steal. Reason: \"every skill\" in the ruling. "
"14. Locked-slot check runs on load and whenever the Training Grounds level changes. Reason: catches Studio test buttons too. "
"15. Enemy rates: Elite 100% / Veteran 50% / Grunt 25% per row, seeded. Bosses use the Elite rule only if their loadout is generated. Reason: gives Elites their original design back; \"some\" enemies, not all. "
"16. Co-op / quest: the enemy rule reads the quest owner's Training Grounds. Reason: battle state already stores the owner (ownerPlayerId). "
"17. Starter augments stay 2× each. Reason: still useful across units; nothing to migrate. "
"18. Card loot label shows the card's fixed rarity. Reason: the random label would clash with the shop's rarity. "
"19. Shop shows owned cards too (no \"already owned\" filter). Reason: duplicates are needed for several units. "
"20. One card per confirm prompt; tabs Buy / Sell. Reason: same as the Apothecary.")
RARITY_LISTS = (
"SHOP RARITY BY CARD (rules in row 76; from training_grounds_design_options_20261104.md Appendix 1). SKILLS: "
"Attack - Rare (39): Arcane Strike, Barrage, Blood Price, Crippling Shot, Crossing Blades, Crushing Advance, Dark Restoration, Earthen Lance, Execution Stroke, Feinting Flurry, Festering Wound, Fire Bolt, Flurry of Blades, Frostbind, Hamstring, Hemorrhage, Holy Smite, Hunter’s Mark, Ignition Lance, Longshot, Lucky Strike, Lunge, Mana Scorch, Mug, Null Strike, Overwhelming Blow, Power Strike, Precise Disarm, Rapid Assault, Reckless Charge, Recoil Shot, Rending Slash, Shatter Blow, Shatter Point, Skyfall Lance, Storm Barrage, Torrent Spear, Toxic Needle, Twin Fangs. "
"Attack - Epic (17): Chain Spark, Decimating Swing, Dragon Dive, Fissure Line, Gale Thrust, Glacial Wave, Ignite Ground, Meteor Marker, Pyroclasm, Retribution Shell, Shadow Rake, Siphon Pulse, Sweeping Cut, Thunderclap, Tidal Crash, Venom Burst, Voltaic Chain. "
"Support - Rare (19): Arcane Barrier, Arcane Renewal, Bastion Projection, Battle Fury, Battlefield Triage, Benediction, Coordinated Advance, Field Dressing, Guardian’s Projection, Healing Light, Hold the Line, Invigorate, Life Link, Mana Surge, Meditate, Purge, Purifying Form, Vital Barrier, Weapon Ward. "
"Support - Epic (9): Bulwark Field, Consecrate, Counter Stance, Empowering Aura, Mending Rain, Misdirection, Riposte Stance, Sanctify, War Cry. "
"Support - Legendary (1): Phoenix Rite. "
"Control & Utility - Rare (20): Blink, Conjure Ice Spike, Fated Escape, Mind Fracture, Nature's Grasp, Opportunist’s Step, Phantom Exchange, Poison Trap, Repair, Restock, Seal of Silence, Set Bear Trap, Set Land Mine, Set Snare Trap, Set Spike Trap, Steal, Stone Prison, Vanishing Step, Veil of Weakness, Wither. "
"Control & Utility - Epic (5): Blinding Flash, Flash Freeze, Miasma Cloud, Rainfall Zone, Static Field. "
"Control & Utility - Legendary (6): Conjure Mender, Conjure Sentinel, Conjure Wisp, Summon Decoy, Summon Turret, Summon Ward Totem. "
"AUGMENTS: Rare - Buff (7): Blessed Support, Enlighten Support, Frenzy Support, Haste Support, Recharge Support, Regeneration Support, Rush Support. "
"Rare - Debuff (16): Bleeding Edge Support, Blinding Support, Break Support, Burning Support, Confusing Support, Crippling Support, Cursing Support, Disarming Support, Mana Erosion Support, Mana Rupture Support, Muting Support, Pinning Support, Silencing Support, Venomous Support, Weakening Support, Wetting Support. "
"Rare - Defensive (7): Barrier on Hit, Draining Ward, Evasion Surge, Fortify on Kill, Retaliation Guard, Steadfast Strike, Threat Reduction. "
"Rare - Displacement (5): Forceful Strike, Pulling Strike, Scatter Strike, Swap Strike, Vortex Strike. "
"Rare - Penetration (1): Armor Piercing. Rare - Purge (4): Deep Purge, Mass Purge, Purging Strike, Self Cleanse. "
"Rare - Recovery (5): Lifesteal, Mana Leech, Overhealing Shield, Siphon Barrier, Vitality Surge. "
"Rare - Stat Scaling (5): AGI Scaling, DEX Scaling, INT Scaling, LUK Scaling, VIT Scaling. Rare - Targeting (1): Shared Resolve. "
"Epic - Conditional Amplifier (6): Desperation, Focused Finisher, Height Advantage, Predator Strike, Shatter Blow, Venom Burst. "
"Epic - Death Explosion (4): Explosive Death, Shattering Death, Terrifying Death, Toxic Death. "
"Epic - Kill Trigger (7): Blood Harvest, Chain Kill, Executioner, Overkill Splash, Purifying Kill, Soul Harvest, Triumphant Recovery. "
"Epic - Summoning (3): Decoy Spawn, Soul Echo, Turret Spawn. "
"Epic - Terrain Effect (7): Burning Ground, Darkened Ground, Electric Field, Frozen Ground, Holy Ground, Poison Cloud, Wet Ground. "
"Epic - Timing (6): Delay Strike, Interrupt, Momentum, Priority Surge, Quicken Self, Sluggish Blow. "
"Legendary - Element Conversion (7): Dark Conversion, Earth Conversion, Electric Conversion, Fire Conversion, Holy Conversion, Ice Conversion, Poison Conversion. "
"Legendary - Pattern (7): Bounce Shot, Chain Support, Concentrated Effect, Impact Splash, Line Projection, Piercing Shot, Wide Arc. "
"Legendary - Resource Conversion (2): Blood Casting, HP Casting. Legendary - Reward (2): Gold Harvest, Treasure Hunter. "
"DOCTRINES (one band, 34): Arcanist, Artificer, Ascetic, Assassin, Berserker, Chemist, Cleric, Conjurer, Dragoon, Duelist, Elementalist, Enchanter, Geomancer, Gunner, Juggernaut, Monk, Paladin, Plague Doctor, Ranger, Reaper, Sentinel, Shadowbinder, Shieldbearer, Skirmisher, Spellblade, Stormbringer, Tactician, Templar, Thief, Trickster, Twinblade, Vanguard, Warden, Warlord.")

NEW_ROWS = [
 (74, 'Training Grounds', 'Parameters',
  "Max Level 10. Base = 220, Scale = 16 (the old Training Ground curve). Total cost: 7,495g (cost table row 80). Unlock: Guild Hall L5 (shared with the Crucible). "
  "The Training Grounds MERGES the old Training Ground (rows 20, 21, 32) and the Library (rows 22, 23, 33), both never built and now superseded: 10 facilities, 70,927g in total (the Library's 6,277g is gone). "
  "Guild Hall L6 now unlocks no building (it still gives its quest and dispatch slots). The Training Grounds level can never be above the Guild Hall level (row 3), so L10 needs Guild Hall L10. "
  "Jobs: buy and sell skill cards, augment cards and doctrines (rows 75-77). Level table: row 78. Max-level effect (2nd augment slot) and the enemy rule: row 79. Old jobs: row 81. Dev defaults: row 82. Notices: row 83.",
  TAG + " User approved training_grounds_design_options_20261104.md (Designer thread-9ad5713d2a62): Training Ground + Library merged; 2nd augment slot locked to Training Grounds L10 + unit L80; enemy rule Elite 100% / Veteran 50% / Grunt 25%; notice wording approved (row 83); 20 Dev defaults (row 82). " + SIMNOTE),
 (75, 'Training Grounds', 'Buy + Sell',
  "Buy price = floor(card value × rarity multiplier × level multiplier × (100 − discount) / 100). Card value: augment 60, skill 100, doctrine 1,000 flat (doctrines have no rarity multiplier). "
  "Rarity multiplier (the equipment ones): Rare 2.5, Epic 4.0, Legendary 7.0. Level multiplier = 1 + (player's highest unlocked map level − 1) × 0.02 (same curve as equipment, economy_framework 13/17). "
  "Discount = 3% per Training Grounds level above L1 (L10 −27%). List prices at map L1 / 20 / 50 / 80 / 99: Rare augment 150 / 207 / 297 / 387 / 444; Epic augment 240 / 331 / 475 / 619 / 710; "
  "Legendary augment 420 / 579 / 831 / 1,083 / 1,243; Rare skill 250 / 345 / 495 / 645 / 740; Epic skill 400 / 552 / 792 / 1,032 / 1,184; Legendary skill 700 / 966 / 1,386 / 1,806 / 2,072; doctrine 1,000 / 1,380 / 1,980 / 2,580 / 2,960. "
  "Sell = floor(list price with no discount / 16) (the Merchant's 16:1), not changed by the Training Grounds level. Can't sell: augments attached to a skill, skill cards in a loadout, doctrines bound to a unit, or anything on a unit out on dispatch. "
  "Duplicates and starter cards can be sold. Every buy-then-sell route loses gold (Simulator 2026-11-04: 0 of 346,500 cases make gold; best case returns 25.3% of the price paid). Cards can't be turned into materials and nothing turns materials into cards. "
  "Every shelf card opens the existing card-details view (loadout_ui_spec 47) before buying.",
  TAG + " Prices checked by the Simulator (0 mismatches in 35 cells); nothing costs more than 10 battles of gold (highest: doctrine at map 99, about 6.7 battles). Selling every loot card gives about 7.9k gold over a lifetime (about 4.5% of income)."),
 (76, 'Training Grounds', 'Card Rarity (shop)',
  "Each card has ONE fixed shop rarity (shop only; it never changes power, weapons_equipment 59). Skills (116; Raise Dead is event-only and not sold): Legendary = summons + revive (7); Epic = area / stance / caster-radius (31); Rare = everything else (78). "
  "Augments (102 Working; Rejected and Parked augments are not sold): Rare = Buff, Debuff, Defensive, Recovery, Stat Scaling, Penetration, Targeting, Purge, Displacement families (51); Epic = Conditional Amplifier, Timing, Terrain Effect, Summoning, Kill Trigger, Death Explosion (33); "
  "Legendary = Element Conversion, Pattern, Resource Conversion, Reward (18). Doctrines (34): one band, one price. Shop types: Attack = skills with Direct Damage (56); Support = Healing / Buff / Shield without damage (29); "
  "Control & Utility = the rest, including summons and traps (31); Basic augments = the Rare families; Advanced augments = the Epic + Legendary families. Full per-card lists: row 77. "
  "The card loot label shows this fixed rarity instead of a random roll (Dev default 18).",
  TAG),
 (77, 'Training Grounds', 'Card Rarity Lists', RARITY_LISTS, TAG),
 (78, 'Training Grounds', 'Level Table',
  "Lvl: buy discount, shelf size, rarity odds per card slot (Rare-Epic-Legendary %), new types / effects. L1: 0%, 4, 100-0-0, Attack + Support skills. L2: 3%, 4, 100-0-0, Basic augments. L3: 6%, 5, 100-0-0, Control & Utility skills. "
  "L4: 9%, 5, 85-15-0, Epic unlocked + Advanced augments. L5: 12%, 6, 75-25-0. L6: 15%, 6, 70-30-0, Doctrines: 1 of the 6 slots is always a doctrine (from L6 on, 1 shelf slot is always a doctrine). L7: 18%, 7, 60-40-0. "
  "L8: 21%, 7, 55-35-10, Legendary unlocked. L9: 24%, 8, 50-35-15. L10: 27%, 8, 45-35-20, 2nd augment slot (units L80+) and the enemy rule turns on (row 79). "
  "Restock every 5 completed battles, like the Merchant and Apothecary (an escape before round 3 is not a completed battle). Same save and battle count = same shelf (its own seed). Each shelf item can be bought once. No card appears twice on one shelf. "
  "Filling a slot: roll the rarity from the odds, then pick a card evenly from the unlocked cards of that rarity; if none exist, drop one rarity. The doctrine slot picks evenly from all 34 doctrines. "
  "Upgrade screen (next level, Merchant style): \"+1 card\", \"Epic cards\", \"Legendary cards\", \"Doctrines\", \"2nd augment slot (Lv 80+ units)\".",
  TAG + " Simulator 2026-11-04: restocks to see one specific card - L4 Rare about 30 / Epic about 85; L8 Rare 39 / Epic 31 / Legendary 42 / doctrine 34; L10 Rare 41 / Epic 26 / Legendary 18 / doctrine 34 (Epic at L4-5 is very slow for targeted buying; recorded, no change)."),
 (79, 'Training Grounds', 'Max-Level Effect: 2nd Augment Slot + Enemy Rule',
  "2nd AUGMENT SLOT - LOCKED (USER RULING 2026-11-04): slot 2 of every skill row (including the doctrine skill row, Steal and every future skill) is open only when the unit's owner has Training Grounds effective level 10 "
  "(effective level = min(Training Grounds, Guild Hall), as for every facility) AND the unit is level 80+. Checked per unit; once both are true it opens by itself (neither goes back down in normal play). Slot 1 is always open. "
  "Equipping into a locked slot is refused; the slot shows a lock and the tooltip in row 83. A locked slot holding an augment (old saves, Studio test buttons that lower facility levels, anything else) sends the augment back to storage with the notice in row 83 "
  "(same pattern as frameworks 79); checked on load and whenever the Training Grounds level changes. "
  "ENEMY RULE (USER RULING 2026-11-04): only when the QUEST OWNER's Training Grounds effective level is 10 (checked when the battle is generated), each enemy at level 80+ rolls, deterministically from the battle seed, for each skill row, for a 2nd augment: "
  "Elite 100%, Veteran 50%, Grunt 25%. Before that, and for enemies below level 80, every enemy carries 1 augment per skill - Elites included (Elites carried 2 per skill at every level before this ruling; open_decisions 56). "
  "Bosses follow the Elite rule only if they use a generated loadout; authored loadouts stay as authored. Event units (Champion, mercenaries, etc.) use the tier they are mapped to. The 2nd augment uses the same fit and conflict checks (project_rules 221).",
  TAG + " Supersedes the old universal 2-slot rule (project_rules 48, 55, 57, 65; frameworks 26, 32, 34, 68; open_decisions 34; weapons_equipment 59, 60; loadout_ui_spec 39, 40, 41; save_data_contract SkillInstance; skill_augment_schemas attached_augment_ids; validation_matrix Augment attachment; doctrines Augment_Slot_Rule). "
  "Simulator 2026-11-04: below L80 a full team carries 24 augments instead of 48 (from about unit L42 on); normal L80+ battle about 20 -> 27 enemy augments with the rule on. A benched unit reaches L80 about 60 battles after deployed units and keeps 1 slot meanwhile. " + SIMNOTE),
 (80, 'Cost Table', 'Training Grounds', 'L1:234 L2:275 L3:344 L4:440 L5:564 L6:715 L7:894 L8:1100 L9:1334 L10:1595. Total: 7,495g.', TAG + ' Same table as the old Training Ground (row 32). Formula row 2 with Base 220 / Scale 16.'),
 (81, 'Training Grounds', 'Old Jobs (Training Ground + Library)',
  "Training Ground benched XP bonus (+2% per level): DROPPED - never built, contradicts the Simulator-tuned locked 65% benched rate (unit_progression 52); raising it would speed up levelling and the L80 gate. "
  "Training battles: DROPPED (kept as a future idea) - never designed; the Quest Board already covers practice. Skill / class preview: KEPT, moved into the shop - every shelf card opens the existing card-details view (loadout_ui_spec 47) before buying; no new system. "
  "Library +1 card storage per level: DROPPED - cards already stack with no limit and the project rule is no hard inventory cap. Library card merchants (buy/trade): KEPT as the main job (buy + sell); trading dropped (trading between players isn't designed). "
  "Library card research (slow free cards): DROPPED - restocks replace it; free cards would undercut card scarcity and the new shop.",
  TAG + " Simulator 2026-11-04: dropping the never-built benched-XP bonus moves no benchmark; the locked 65% stays."),
 (82, 'Training Grounds', 'Dev Defaults', DEV_DEFAULTS, TAG + ' DECIDED (DEV DEFAULT) - the user can overrule any of these. "C2", "C3", "C4" and "C6" mean rows 78, 76-77, 75 and 81.'),
 (83, 'Training Grounds', 'Notice Wording (APPROVED BY USER)',
  "APPROVED BY USER 2026-11-04 (standing rule: no new helper text without approval). Load / migration notice: \"2nd augment slots are locked until your Training Grounds is fully upgraded and the unit reaches level 80. {N} augment(s) were moved to storage.\" "
  "Short version: \"{N} augment(s) moved to storage: 2nd slots are locked.\" Locked slot tooltip: \"Unlocks at Training Grounds Lv 10 and unit Lv 80.\" "
  "Unlock notice (optional): \"{Unit} unlocked a 2nd augment slot on every skill!\" Upgrade screen (next level), Merchant style: \"+1 card\", \"Epic cards\", \"Legendary cards\", \"Doctrines\", \"2nd augment slot (Lv 80+ units)\".",
  TAG),
]
OD_NEW = ('Training Grounds - Training Ground + Library merged, 2nd augment slot locked (2026-11-04)',
  'RESOLVED (USER) 2026-11-04 - NOT BUILT (Dev building now)',
  "User approved training_grounds_design_options_20261104.md (Designer thread-9ad5713d2a62). The Training Ground and the Library (both never built) merge into the Training Grounds: Guild Hall L5, Base 220 / Scale 16 = 7,495g, 10 facilities, 70,927g; Guild Hall L6 unlocks no building. "
  "It buys and sells skill cards, augment cards and doctrines (price = floor(value x rarity x level multiplier x (100 - discount)/100); augment 60 / skill 100 / doctrine 1,000; Rare 2.5 / Epic 4.0 / Legendary 7.0; sell = list / 16). "
  "Shelf 4,4,5,5,6,6,7,7,8,8, restock every 5 battles; Epic L4, Legendary L8, doctrines L6. LOCKED: the 2nd augment slot opens at Training Grounds L10 for units level 80+. Enemy rule: level 80+ enemies get a 2nd augment only when the quest owner's Training Grounds is L10 (Elite 100% / Veteran 50% / Grunt 25%); before that Elites carry 1. "
  "Notice wording approved; 20 Dev defaults (guild_facilities 82). Simulator: no change needed; free players open slot 2 only by rushing the Training Grounds; card buying adds 12-14 points (accepted). "
  "Rows: guild_facilities 74-83 NEW, 20-23 / 32-33 superseded, 5, 8, 35-37, 39, 59, 67; economy_framework 28, 29, 44-46; game_flow 8; development_slices 8; project_rules 48, 52, 55, 57, 65; frameworks 26, 32, 34, 68; weapons_equipment 59, 60; loadout_ui_spec 39-41; "
  "save_data_contract SkillInstance + ProfileSave; skill_augment_schemas attached_augment_ids; validation_matrix Augment attachment; doctrines Augment_Slot_Rule (34); loot_progression 42; open_decisions 15, 29, 34, 56.",
  None, None, None, None)

# ======================= run =======================
def run(DRY):
    log = {'edits': [], 'new': [], 'xlsx': []}
    j = [p for p in (DB + '-journal', DB + '-wal') if os.path.exists(p)]
    print('journal before:', j)
    assert not j
    con = sqlite3.connect(DB if not DRY else 'file:' + DB + '?mode=ro', uri=DRY)
    print('integrity before:', con.execute('pragma integrity_check').fetchone()[0])
    oldrows = {}   # (table,keyval) -> dict of full old row
    def getrow(t, kc, kv):
        cur = con.execute(f'select rowid,* from "{t}" where "{kc}"=?', (kv,))
        cols = ['rowid'] + [d[0] for d in cur.description][1:]
        rows = cur.fetchall(); assert len(rows) == 1, (t, kv, len(rows))
        return dict(zip(cols, rows[0]))
    changes = {}   # (t,kc,kv) -> {col: new}
    for (t, kc, kv, col, fn, must) in edits:
        key = (t, kc, kv)
        if key not in oldrows: oldrows[key] = getrow(t, kc, kv)
        cur = changes.setdefault(key, {})
        base = cur.get(col, oldrows[key][col])
        if fn is None:   # notes append with superseded old text of the main column
            maincol = must if must else ('rule' if t != 'development_slices' else 'description')
            oldmain = oldrows[key][maincol]
            new = ap(oldrows[key][col], TAG + ' ' + SUP + maincol + ': ' + oldmain + ']')
        else:
            if must and must not in ('topic',): assert must in oldrows[key][col] or must in base, ('drift', t, kv, col, must)
            new = fn(base)
        assert new != base or fn is None, ('nochange', t, kv, col)
        cur[col] = new
    # doctrines
    for r in con.execute('select Doctrine_ID, Augment_Slot_Rule, Notes from doctrines').fetchall():
        key = ('doctrines', 'Doctrine_ID', r[0])
        oldrows[key] = getrow(*key)
        assert r[1] in DOC_OLD, r
        changes[key] = {'Augment_Slot_Rule': DOC_OLD[r[1]], 'Notes': ap(r[2], TAG + ' ' + SUP + 'Augment_Slot_Rule: ' + r[1] + ']')}
    # new rows
    mx = con.execute('select max(id) from guild_facilities').fetchone()[0]; assert mx == 73, mx
    odmx = con.execute('select max(rowid) from open_decisions').fetchone()[0]; assert odmx == 127, odmx
    print('row edits:', len(changes), 'cells:', sum(len(v) for v in changes.values()))
    if not DRY:
        stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
        bdb = DB + f'.bak_{stamp}_traininggrounds'; shutil.copy2(DB, bdb); print('backup', bdb)
        with con:
            for (t, kc, kv), cols in changes.items():
                sets = ', '.join(f'"{c}"=?' for c in cols)
                con.execute(f'update "{t}" set {sets} where "{kc}"=?', list(cols.values()) + [kv])
            for r in NEW_ROWS:
                con.execute('insert into guild_facilities(id,section,topic,rule,notes) values (?,?,?,?,?)', r)
            con.execute('insert into open_decisions(rowid,"OPEN_DECISIONS_&_PARKED_TOPICS",col_2,col_3,col_4,col_5,col_6,col_7) values (128,?,?,?,?,?,?,?)', OD_NEW)
        # read back
        bad = 0
        for (t, kc, kv), cols in changes.items():
            now = getrow(t, kc, kv)
            for c, v in cols.items():
                if now[c] != v: bad += 1; print('MISMATCH', t, kv, c)
            for c in now:
                if c not in cols and now[c] != oldrows[(t, kc, kv)][c]: bad += 1; print('UNEXPECTED', t, kv, c)
            log['edits'].append({'table': t, 'key': kv, 'before': {c: oldrows[(t, kc, kv)][c] for c in cols}, 'after': cols})
        for r in NEW_ROWS:
            if tuple(con.execute('select * from guild_facilities where id=?', (r[0],)).fetchone()) != r: bad += 1; print('NEWROW MISMATCH', r[0])
        if tuple(con.execute('select * from open_decisions where rowid=128').fetchone()) != OD_NEW: bad += 1; print('OD MISMATCH')
        log['new'] = [r[0] for r in NEW_ROWS] + ['open_decisions rowid 128']
        print('readback mismatches:', bad)
        print('integrity after:', con.execute('pragma integrity_check').fetchone()[0])
        con.close()
        print('journal after:', [p for p in (DB + '-journal', DB + '-wal') if os.path.exists(p)])
        json.dump(log, open(os.path.join(D, 'backups', f'traininggrounds_{stamp}_changes.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
        session['stamp'] = stamp
    session['changes'] = changes; session['oldrows'] = oldrows
    return changes, oldrows
