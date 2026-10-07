# 2026-10-04 USER RULINGS: WEATHER / CRISIS DESIGN REWORK (Designer agent).
# DB = single source of truth. Updates objects_encounters BATTLE CONDITIONS, adds Snow Storm,
# unifies periodic intervals to 300 CT, adds the combined weather/crisis slot + per-round re-roll
# model to map_gen_rules, defines new Wind reactions (Burning accel / Poison Cloud spread) and
# Heatwave transforms in terrain_effects, adjusts biome condition pools, and records resolutions
# in open_decisions. Then regenerates the affected Game_Rules.xlsx sheets.
import sqlite3, shutil, os, json, datetime

DOCS = r'D:\AI\Projects\CTRBLXAI\docs'
DB = os.path.join(DOCS, 'CTRBLXAI.db')
XLSX = os.path.join(DOCS, 'CTRBLXAI_Game_Rules.xlsx')
BK = os.path.join(DOCS, 'backups')
stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
os.makedirs(BK, exist_ok=True)

# ---------- BACKUP (sqlite online-backup API, then verify) ----------
bk_db = os.path.join(BK, f'CTRBLXAI_pre_weather_{stamp}.db')
src = sqlite3.connect(DB); dst = sqlite3.connect(bk_db); src.backup(dst); dst.close(); src.close()
chk = sqlite3.connect(bk_db)
assert chk.execute('pragma integrity_check').fetchone()[0] == 'ok'
TRACK = ('objects_encounters', 'terrain_effects', 'elements_statuses', 'biomes',
         'map_gen_rules', 'open_decisions', 'project_rules')
bk_counts = {t: chk.execute(f'select count(*) from "{t}"').fetchone()[0] for t in TRACK}
chk.close()
bk_xlsx = os.path.join(BK, f'CTRBLXAI_Game_Rules_pre_weather_{stamp}.xlsx')
shutil.copy2(XLSX, bk_xlsx)
bk_index = os.path.join(BK, f'INDEX_pre_weather_{stamp}.txt')
shutil.copy2(os.path.join(DOCS, 'INDEX.txt'), bk_index)

c = sqlite3.connect(DB)
cur = c.cursor()
log = []; inserted = []

def get(t, rowid):
    return cur.execute(f'select * from "{t}" where rowid=?', (rowid,)).fetchone()

def upd(t, rowid, **kv):
    old = get(t, rowid)
    sets = ', '.join(f'"{k}"=?' for k in kv)
    cur.execute(f'update "{t}" set {sets} where rowid=?', list(kv.values()) + [rowid])
    assert cur.rowcount == 1, (t, rowid)
    log.append((t, rowid, old, get(t, rowid)))

# ---------- FRESH-RUN GUARDS ----------
assert get('objects_encounters', 48)[0] == 'Battle Condition', 'condition header moved'
assert get('objects_encounters', 50)[0] == 'Rain'
assert get('objects_encounters', 62)[0] == 'Hunger Virus'
assert get('objects_encounters', 63)[0] == 'ENCOUNTER RULES'
# not already applied: Rain periodic must still be the OLD Burning->Steam text
assert 'Burning effects become Steam' in get('objects_encounters', 50)[3], 'Rain already reworked?'
assert cur.execute("select count(*) from objects_encounters where MAP_OBJECT_CATALOG='Snow Storm'").fetchone()[0] == 0
assert get('map_gen_rules', 69)[0].startswith('Template Rotation'), 'map_gen_rules tail moved'
assert get('terrain_effects', 23)[0] == 'Burning' and get('terrain_effects', 27)[0] == 'Poison Cloud'
assert cur.execute('select max(rowid) from open_decisions').fetchone()[0] == 78

DEV = (' DEV CHANGE PENDING: the weather/crisis-application engine is being built separately in '
       'parallel (Dev side); these are DESIGN/DB rulings only. Not Studio-tested.')

# =====================================================================================
# 1. BATTLE CONDITIONS rework (objects_encounters col map:
#    MAP_OBJECT_CATALOG=name, col_2=Description, col_3=Passive, col_4=Periodic,
#    col_5=Interval, col_6=Notes, col_7=Status)
# =====================================================================================

# --- Rain (row 50): Wet to BOTH units and tiles every 300 CT, undispellable for the round;
#     triggers Water/Wet-tag reactions. Keep Fire-25/Water+25 passive. ---
upd('objects_encounters', 50,
    col_3='Fire Damage -25%; Water Damage +25%.',
    col_4=("Every 300 CT, apply/refresh Wet on ALL units AND on all traversable tiles. This Wet is "
           "UNDISPELLABLE for the weather's duration (= this round, 1000 CT, since the weather/crisis "
           "slot re-rolls at the next round boundary): cleanse/dispel cannot remove it, but it is still "
           "subject to element REACTION removal (a Fire hit still converts Wet->Steam per terrain_effects "
           "'Wet'). Applying Wet to a tile triggers that tile's Water/Wet-tag reactions in the normal "
           "element-resolution order: Fire->Steam, Ice-tag->Frozen, Electric->Static Cloud (Wet is Conductive)."),
    col_5='300',
    col_6=("Promotes Water strategies. REWORK 2026-10-04 (USER RULING): the old 'Burning->Steam' periodic "
           "is REPLACED by battlefield-wide Wet application; Burning tiles still become Steam because the "
           "new Wet lands on them (Water->Steam / Fire-on-Wet->Steam), so no net loss. 'Undispellable for "
           "the duration' = for 1 round (1000 CT) per the combined-slot re-roll model (map_gen_rules "
           "'Weather / Crisis Combined Slot')." + DEV))

# --- Strong Wind (row 51): trigger all Wind-tag reactions every 300 CT; keep Wind +25% passive;
#     DESIGNER DEFINES Burning accel + Poison Cloud spread. ---
upd('objects_encounters', 51,
    col_3='Wind Damage +25%.',
    col_4=("Every 300 CT, trigger ALL Wind-tag reactions across the battlefield: Steam->Clear and "
           "Static Cloud->Clear (confirmed-existing; there is NO 'Fog' - Steam replaced Fog - and NO "
           "'Smoke'). DESIGNER-DEFINED NEW Wind reactions (2026-10-04 USER RULING, added to "
           "terrain_effects): (a) BURNING ACCELERATION - each Wind tick forces every Burning tile to run "
           "one extra Burning-spread pass THIS tick (normal cadence is 500 CT; Strong Wind makes it fire "
           "on the 300 CT Wind tick as well), using the existing orthogonal radius-1, +/-1 elevation, "
           "Flammable-only spread rules and TRG-012 guard (reach is NOT widened - only the cadence is "
           "accelerated, to prevent runaway). (b) POISON CLOUD SPREAD - each Wind tick, every Poison Cloud "
           "tile migrates: it attempts to create Poison Cloud on ONE deterministically-chosen (seeded) "
           "orthogonally-adjacent tile whose terrain is Airborne-compatible and not already reacting, cap "
           "one new tile per source per tick (TRG-012). Existing Poison Cloud duration is unchanged."),
    col_5='300',
    col_6=("Limits airborne hazards (Steam/Static Cloud) but SPREADS Burning and Poison Cloud. REWORK "
           "2026-10-04 (USER RULING): old 'remove one random Airborne Effect' replaced by 'trigger all "
           "Wind-tag reactions'. FLAG - the Burning-acceleration and Poison-Cloud-spread Wind reactions "
           "are NEW mechanics (did not exist before); authored here as Designer defaults, need Dev build "
           "and a balance pass (open_decisions 'Strong Wind Burning/Poison spread')." + DEV))

# --- Heatwave (row 52): dry/burn transforms every 300 CT; keep Fire+20/Water-20 passive. ---
upd('objects_encounters', 52,
    col_3='Fire Damage +20%; Water Damage -20%.',
    col_4=("Every 300 CT, apply heat transforms in element-resolution order: all water terrain dries "
           "(Shallow Water->Clear, Deep Water->Clear; Ice terrain->Shallow Water, i.e. it melts); "
           "Grassland and Clover Field gain Burning (their own Fire->Sand terrain transform then resolves "
           "normally); the Vines tile effect->Burning (matches Vines 'Fire->Burning'); Swamp->Rocky and "
           "Mud->Rocky (match their 'Fire->Rocky'); Wet tiles->Steam (matches Wet 'Fire->Steam')."),
    col_5='300',
    col_6=("Promotes Fire strategies. REWORK 2026-10-04 (USER RULING): old 'reduce all Wet durations by "
           "300 CT' replaced by the dry/burn transform set. DESIGNER DECISIONS (recorded): Mud->Rocky YES, "
           "Wet tiles->Steam YES, Ice terrain->Shallow Water (melt). DEEP-WATER DROWNING EDGE: when Deep "
           "Water->Clear, the tile is now dry, so any non-Amphibious unit that was Drowning there stops "
           "Drowning (Clear creates no Drowning); Heatwave removes a drowning hazard rather than adding "
           "one. There is no separate 'Marsh' terrain - Swamp IS the marshland." + DEV))

# --- Dark Eclipse (row 53): ADD undispellable Haste to the dark/night-aligned set; keep passive. ---
RELATED = ("the DARK/NIGHT-ALIGNED SET = any unit carrying the Undead TAG (races Zombie and Vampire) OR "
           "under the Undead STATUS (elements_statuses id 75, which can be applied temporarily to any "
           "unit), PLUS Werewolf (Moonblood) and PLUS the Demon race")
upd('objects_encounters', 53,
    col_3='Light Damage -25%; Dark Damage +25%; Recruitment Chance -20%.',
    col_4=("For the weather's duration (= this round, 1000 CT), " + RELATED + " gain UNDISPELLABLE Haste "
           "(elements_statuses id 70; cleanse/dispel cannot remove it this round). Haste is refreshed each "
           "round the condition is Dark Eclipse. No periodic HP tick."),
    col_5='-',
    col_6=("Holy attacks are weakened; dark/night creatures surge. ADD 2026-10-04 (USER RULING): existing "
           "Light-25/Dark+25/Recruitment-20 passive KEPT; undispellable Haste ADDED. AUTHORITATIVE RELATED-"
           "RACES LIST (Designer, grounded in races table): Undead-tag races = Zombie, Vampire (Vampire "
           "tags confirmed = Undead); temporary Undead STATUS also qualifies; Werewolf and Demon added by "
           "race. EXCLUDED (not in the 25-race roster): Skeleton and Lich do NOT exist as races (candidate "
           "list only; Skeleton Transformer object was removed 2026-10-03). Demon is a RACE not a tag, so "
           "the engine needs an explicit Demon hook (same caveat as Tainted Ground's Demon clause). "
           "'Undispellable for the duration' = 1 round (1000 CT)." + DEV))

# --- Holy Aurora (row 54): ADD undispellable Slow to the SAME set; keep passive; KEEP 5% Light tick. ---
upd('objects_encounters', 54,
    col_3='Light Damage +25%; Dark Damage -25%.',
    col_4=("Every 300 CT, Undead-tag / Undead-status units take 5% Max HP Light Damage (KEPT). "
           "ADDITIONALLY, for the weather's duration (= this round, 1000 CT), " + RELATED + " gain "
           "UNDISPELLABLE Slow (elements_statuses id 71; cleanse/dispel cannot remove it this round), "
           "refreshed each round the condition is Holy Aurora."),
    col_5='300',
    col_6=("Strong anti-undead condition. ADD 2026-10-04 (USER RULING): existing Light+25/Dark-25 passive "
           "KEPT; undispellable Slow ADDED to the SAME dark/night-aligned set as Dark Eclipse. DESIGNER "
           "DECISION: the existing 300-CT Undead 5% Max HP Light tick is KEPT (it reinforces the anti-"
           "undead identity and pairs naturally with the new Slow). Same related-races list as Dark Eclipse "
           "(Zombie, Vampire, temporary Undead status, Werewolf, Demon). 'Undispellable for the duration' "
           "= 1 round (1000 CT)." + DEV))

# --- Wild Growth (row 55): unify 500 -> 300 CT. ---
upd('objects_encounters', 55,
    col_4='Every 300 CT, randomly apply Vines to 15-25% of battlefield terrain without vine.',
    col_5='300',
    col_6=('Existing Vines are unaffected. Interval unified 500->300 CT (2026-10-04 USER RULING: all '
           'periodic weather effects fire every 300 CT).' + DEV))

# --- Mana Storm (row 56): new regen-then-50%-current-MP HP damage; replaces +10% + Mana Burn. ---
upd('objects_encounters', 56,
    col_4=("Every 300 CT, ALL units first restore 10% Max MP, THEN take HP damage equal to 50% of their "
           "CURRENT (post-regen) MP. (Replaces the old +10% Max MP + Mana Burn periodic.)"),
    col_5='300',
    col_6=("High-MP units are punished; spending MP before each tick reduces the self-damage. REWORK "
           "2026-10-04 (USER RULING): old '+10% Max MP and gain Mana Burn' replaced by 'restore 10% Max MP "
           "THEN lose HP = 50% of current MP'. The Mana Burn status (elements_statuses id 68) is NO LONGER "
           "used by this condition. Interval unified 500->300 CT. Damage order is strict: regen first, "
           "then the 50%-of-current-MP HP hit." + DEV))

# --- Thunderstorm / Meteor Storm / Volcanic Eruptions / Earthquake: unify 500 -> 300 CT only. ---
for rid in (57, 58, 59, 60):
    row = get('objects_encounters', rid)
    new_periodic = row[3].replace('Every 500 CT', 'Every 300 CT')
    assert new_periodic != row[3], ('500 not found', rid)
    upd('objects_encounters', rid, col_4=new_periodic, col_5='300',
        col_6=(row[5] + ' Interval unified 500->300 CT (2026-10-04 USER RULING).' + DEV))

# --- Severe Hail (row 61): random half of active units take 10% Max HP each 300 CT. ---
upd('objects_encounters', 61,
    col_4=("Every 300 CT, a random half of all active units take HP damage equal to 10% of their Max HP."),
    col_5='300',
    col_6=("Chip damage spread across the field. REWORK 2026-10-04 (USER RULING): replaces the old "
           "'Liquid->Ice / others gain Frozen tile + 15% Water damage to occupants' version with a flat "
           "'random half of active units take 10% Max HP'. 'Random half' = round(active_units / 2) chosen "
           "by the seeded RNG each tick; HP%-based so boss resistance applies downstream." + DEV))

print('BATTLE CONDITIONS updated.')
print('BATTLE CONDITIONS phase done (uncommitted).')

# =====================================================================================
# 2. ADD Snow Storm condition. objects_encounters is a plain TEXT table ordered by rowid;
#    rebuild it so Snow Storm sits right AFTER Hunger Virus (row 62) and BEFORE the
#    'ENCOUNTER RULES' header (was row 63).
# =====================================================================================
SNOW_NOTES = ("NEW CONDITION 2026-10-04 (USER RULING). Added to biome condition pools (Tundra primary; also "
              "Highlands and Cave - see biomes 'Battle Condition Weights'). FROZEN / FIRE INTERACTION while "
              "undispellable (DESIGNER DECISION, FLAG): 'undispellable' blocks cleanse/dispel, but Fire is a "
              "REACTION removal, not a dispel - a Fire hit on an individual unit still removes that unit's "
              "Frozen (elements_statuses id 74: 'Fire damage x0.50 then removes Frozen'), preserving Fire "
              "counterplay. Snow Storm re-applies Frozen to all units at the next round boundary anyway. The "
              "Ice TERRAIN created here is not itself undispellable (terrain, not a unit status): "
              "Fire->Shallow Water per terrain_effects 'Ice'. 'Undispellable for the duration' = 1 round "
              "(1000 CT)." + DEV)
SNOW = ('Snow Storm',
        'A freezing blizzard entombs the battlefield.',
        'None.',
        ("For the weather's duration (= this round, 1000 CT), ALL units are UNDISPELLABLE Frozen "
         "(elements_statuses id 74; cleanse/dispel cannot remove it this round), refreshed each round "
         "the condition is Snow Storm. All water terrain freezes: Shallow Water->Ice and Deep Water->Ice."),
        '-',
        SNOW_NOTES,
        'SOURCE',
        None, None)

all_rows = cur.execute('select rowid, * from objects_encounters order by rowid').fetchall()
rows_only = [r[1:] for r in all_rows]
# find Hunger Virus index
hv_idx = next(i for i, r in enumerate(rows_only) if r[0] == 'Hunger Virus')
assert rows_only[hv_idx + 1][0] == 'ENCOUNTER RULES'
new_rows = rows_only[:hv_idx + 1] + [SNOW] + rows_only[hv_idx + 1:]
cur.execute('delete from objects_encounters')
cur.executemany('insert into objects_encounters values (?,?,?,?,?,?,?,?,?)', new_rows)
assert cur.execute("select count(*) from objects_encounters where MAP_OBJECT_CATALOG='Snow Storm'").fetchone()[0] == 1
assert get('objects_encounters', 63)[0] == 'Snow Storm' and get('objects_encounters', 64)[0] == 'ENCOUNTER RULES'
inserted.append(('objects_encounters', ['Snow Storm (battle condition)']))
print('Snow Storm inserted; objects_encounters rows:', len(new_rows))

# =====================================================================================
# 3. terrain_effects: define the NEW Wind reactions (Burning accel, Poison Cloud spread) and
#    record Heatwave transforms. (col map: col_8 = Element Reactions, col_9 = Notes)
# =====================================================================================
# Burning (row 23): add Wind reaction note to Element Reactions + notes.
b = get('terrain_effects', 23)
assert b[0] == 'Burning' and b[7] == 'Water → Steam'
upd('terrain_effects', 23,
    col_8='Water → Steam; Wind (Strong Wind) → forced extra spread pass this tick',
    col_9=(b[8] + ' WIND REACTION (NEW 2026-10-04, USER RULING): under Strong Wind, each 300 CT Wind tick '
           'forces one extra Burning-spread pass (normal cadence 500 CT) using the SAME orthogonal radius-1, '
           '+/-1 elevation, Flammable-only rules + TRG-012 guard; only the cadence accelerates, reach is not '
           'widened. FLAG: new mechanic, needs Dev build + balance pass (open_decisions).'))
# Poison Cloud (row 27): add Wind reaction.
p = get('terrain_effects', 27)
assert p[0] == 'Poison Cloud' and p[7] == 'Fire → Explosion'
upd('terrain_effects', 27,
    col_8='Fire → Explosion; Wind (Strong Wind) → migrate/spread to 1 adjacent compatible tile per tick',
    col_9=(p[8] + ' WIND REACTION (NEW 2026-10-04, USER RULING): under Strong Wind, each 300 CT Wind tick '
           'each Poison Cloud tile attempts to create Poison Cloud on ONE seeded orthogonally-adjacent '
           'Airborne-compatible, non-reacting tile (cap 1 new tile/source/tick, TRG-012). Existing duration '
           'unchanged. FLAG: new mechanic, needs Dev build + balance pass (open_decisions).'))
# Append a terrain_effects documentation row for the Heatwave transform set (as a HEATWAVE spec line).
te_tail = cur.execute('select max(rowid) from terrain_effects').fetchone()[0]
cur.execute('insert into terrain_effects values (?,?,?,?,?,?,?,?,?)', (
    'HEATWAVE TRANSFORM SET (weather, authored 2026-10-04)',
    'Transforms applied by the Heatwave battle condition every 300 CT (objects_encounters row Heatwave).',
    'Weather-driven terrain transform',
    '—', '—', '—',
    'Shallow Water→Clear; Deep Water→Clear; Ice→Shallow Water; Grassland→Burning; Clover Field→Burning; '
    'Vines effect→Burning; Swamp→Rocky; Mud→Rocky; Wet→Steam',
    'Resolved in element-resolution order. Deep Water→Clear ends Drowning on that tile (dry); no new '
    'drowning source. Consistent with each terrain/effect\'s own Fire transform. USER RULING 2026-10-04.',
    'SOURCE'))
inserted.append(('terrain_effects', ['HEATWAVE TRANSFORM SET']))
print('terrain_effects Wind reactions + Heatwave transform row added.')

# =====================================================================================
# 4. Biome condition pools (biomes col_6 = 'Battle Condition Weights'). Add Snow Storm to
#    Tundra (primary), Highlands, Cave. Keep each pool summing to 100.
# =====================================================================================
def set_cond(name, weights):
    rid = cur.execute('select rowid from biomes where BIOME_CATALOG=?', (name,)).fetchone()[0]
    total = sum(int(w.split()[-1]) for w in weights.split(';'))
    assert total == 100, (name, total)
    upd('biomes', rid, col_6=weights)

# Tundra: was 'Severe Hail 40; Strong Wind 20; Clear 15; Thunderstorm 10; Heatwave 5; Holy Aurora 10'
#   -> make room for Snow Storm 25 (its signature condition); trim Severe Hail 40->25, Strong Wind 20->15.
set_cond('Tundra',
         'Snow Storm 25; Severe Hail 25; Strong Wind 15; Clear 10; Thunderstorm 10; Heatwave 5; Holy Aurora 10')
# Highlands: was 'Strong Wind 30; Thunderstorm 25; Earthquake 20; Clear 15; Holy Aurora 10'
#   -> add Snow Storm 10 (cold peaks); trim Strong Wind 30->25, Earthquake 20->15.
set_cond('Highlands',
         'Strong Wind 25; Thunderstorm 25; Earthquake 15; Clear 15; Holy Aurora 10; Snow Storm 10')
# Cave: was 'Clear 55; Earthquake 25; Mana Storm 10; Dark Eclipse 10'
#   -> add Snow Storm 10 (cold underground); trim Clear 55->45.
set_cond('Cave', 'Clear 45; Earthquake 25; Mana Storm 10; Dark Eclipse 10; Snow Storm 10')
print('Biome condition pools updated (Tundra/Highlands/Cave now include Snow Storm).')

# =====================================================================================
# 5. map_gen_rules: combined weather/crisis slot + per-round re-roll + quest-set start +
#    unified-300 model. Append P0 rule rows (2-col shape: col1 = key, col_2 = content).
# =====================================================================================
def add_mgr(key, content):
    cur.execute('insert into map_gen_rules values (?,?,?,?,?,?,?,?,?)',
                (key, content, 'Locked 2026-10-04 (USER RULING, P0)', None, None, None, None, None, None))
    inserted.append(('map_gen_rules', [key]))

add_mgr('Weather / Crisis Combined Exclusive Slot (P0)',
    ("The battlefield has ONE combined exclusive condition slot: each round it holds EITHER one WEATHER "
     "OR one CRISIS, never both. Weather and crisis conditions share this single slot and are drawn from "
     "the SAME biome 'Battle Condition Weights' pool (biomes col 'Battle Condition Weights'). The 35 "
     "battlefield_events rows are a SEPARATE system that layers freely ON TOP of the weather/crisis slot "
     "and are UNCHANGED by this model. (In the current catalog the pooled conditions are the "
     "objects_encounters BATTLE CONDITIONS list: Clear, Rain, Strong Wind, Heatwave, Dark Eclipse, Holy "
     "Aurora, Wild Growth, Mana Storm, Thunderstorm, Meteor Storm, Volcanic Eruptions, Earthquake, Severe "
     "Hail, Snow Storm, Hunger Virus.) USER RULING 2026-10-04."))
add_mgr('Weather / Crisis Per-Round Re-Roll (P0)',
    ("At every 1000-CT round boundary the weather/crisis slot ALWAYS re-rolls from the biome's weighted "
     "pool to a new (possibly identical) condition. There is no persistence between rounds except by "
     "chance of re-rolling the same condition. Consequence: a condition's 'duration' = exactly ONE round "
     "(1000 CT); any effect described as 'undispellable for the duration' is undispellable for that one "
     "round only, after which the slot re-rolls. This supersedes generation Step 9 'select ONE condition' "
     "as a one-time pick: Step 9 now sets only the STARTING condition; the re-roll runs each round "
     "thereafter. USER RULING 2026-10-04."))
add_mgr('Weather / Crisis Quest Start + Time Cycle (P0)',
    ("The QUEST sets the STARTING weather/crisis condition AND the starting time phase; both then cycle "
     "every round. The time-of-day cycle (Dawn -> Day -> Dusk -> Night, one phase advance per round) is "
     "already built in code and is independent of the weather/crisis slot (they advance on the same 1000-CT "
     "round boundary). Werewolf/Vampire day-night passives read the time phase, not the weather slot. "
     "USER RULING 2026-10-04."))
add_mgr('Weather Periodic Interval = 300 CT (P0)',
    ("ALL periodic weather/crisis effects fire every 300 CT. The conditions that were previously on a "
     "500-CT cadence are now 300 CT: Wild Growth, Thunderstorm, Meteor Storm, Volcanic Eruptions, "
     "Earthquake (and Mana Storm, which was also reworked). Conditions already at 300 CT are unchanged. "
     "This is the single authoritative interval for weather periodics. USER RULING 2026-10-04."))
print('map_gen_rules weather/crisis model rows added.')

# =====================================================================================
# 6. open_decisions: record resolutions + flags (append; col map: col1=topic, col_2=status,
#    col_3=notes).
# =====================================================================================
def add_decision(topic, status, notes):
    cur.execute('insert into open_decisions values (?,?,?,?,?,?,?)',
                (topic, status, notes, None, None, None, None))
    inserted.append(('open_decisions', [topic]))

add_decision('Weather/Crisis rework - related-races list for Dark Eclipse Haste / Holy Aurora Slow (2026-10-04)',
    'Resolved',
    ("RESOLVED 2026-10-04 (USER deferred to Designer). AUTHORITATIVE set = any unit with the Undead TAG "
     "(races Zombie, Vampire) OR the Undead STATUS (elements_statuses id 75, temporary-applicable) PLUS "
     "Werewolf PLUS Demon (race). EXCLUDED: Skeleton and Lich (NOT in the 25-race roster; candidates only; "
     "Skeleton Transformer object removed 2026-10-03). CAVEAT: Demon is a RACE not a tag, so the engine "
     "needs an explicit Demon hook. Canon: objects_encounters Dark Eclipse + Holy Aurora."))
add_decision('Weather/Crisis rework - Strong Wind Burning acceleration + Poison Cloud spread (2026-10-04)',
    'Resolved (new mechanic - FLAG)',
    ("RESOLVED 2026-10-04 (USER deferred to Designer). Strong Wind now (a) accelerates Burning spread - one "
     "extra spread pass per 300 CT Wind tick, same orthogonal radius-1 / +/-1 elevation / Flammable rules + "
     "TRG-012 (reach NOT widened), and (b) spreads Poison Cloud - each tick each cloud migrates to 1 seeded "
     "adjacent compatible tile (cap 1/source/tick, TRG-012). FLAG: these Wind reactions did NOT exist "
     "before; authored as Designer defaults in terrain_effects (Burning, Poison Cloud). Needs Dev build and "
     "a balance pass (potential runaway fire / board-wide poison - the cadence cap + no-reach-widening are "
     "the balancer; add a hard active-tile cap if testing shows runaway)."))
add_decision('Weather/Crisis rework - Heatwave extra transforms (2026-10-04)',
    'Resolved',
    ("RESOLVED 2026-10-04 (USER deferred to Designer). Heatwave 300-CT transforms: Shallow Water->Clear, "
     "Deep Water->Clear, Ice terrain->Shallow Water (melt), Grassland/Clover Field->Burning, Vines->Burning, "
     "Swamp->Rocky, Mud->Rocky, Wet tiles->Steam. Deep Water->Clear ENDS Drowning on that tile (no new "
     "drowning source). No separate 'Marsh' terrain - Swamp is the marshland. Canon: terrain_effects "
     "'HEATWAVE TRANSFORM SET' + objects_encounters Heatwave."))
add_decision('Weather/Crisis rework - Snow Storm biome weights + Frozen/Fire interaction (2026-10-04)',
    'Resolved (Frozen/Fire = FLAG)',
    ("RESOLVED 2026-10-04 (USER deferred to Designer). Snow Storm added to Tundra (Snow Storm 25; Severe "
     "Hail trimmed 40->25, Strong Wind 20->15, Clear 15->10 to keep sum 100), Highlands (Snow Storm 10; "
     "Strong Wind 30->25, Earthquake 20->15), Cave (Snow Storm 10; Clear 55->45). All pools still sum to "
     "100. FROZEN/FIRE while undispellable (FLAG): 'undispellable' blocks cleanse/dispel only; a Fire hit "
     "still removes an individual unit's Frozen (reaction removal, elements_statuses id 74), preserving "
     "Fire counterplay; Snow Storm re-Frozens everyone next round boundary. Confirm this read in balance "
     "testing - alternative would be a true hard-lock that ignores Fire (rejected: violates 'every debuff "
     "has counterplay')."))
add_decision('Weather/Crisis rework - kept passives/ticks on Rain / Dark Eclipse / Holy Aurora (2026-10-04)',
    'Resolved',
    ("RESOLVED 2026-10-04 (USER deferred to Designer). KEEP Rain Fire-25/Water+25 passive (periodic "
     "Burning->Steam replaced by battlefield-wide Wet, which still steams Burning tiles). KEEP Dark Eclipse "
     "Light-25/Dark+25/Recruitment-20 passive (Haste ADDED). KEEP Holy Aurora Light+25/Dark-25 passive AND "
     "the 300-CT Undead 5% Light tick (reinforces anti-undead identity; pairs with new Slow). Mana Storm "
     "no longer uses Mana Burn (elements_statuses id 68 remains defined but is now unused by weather)."))
print('open_decisions resolution rows added.')

# ---------- COMMIT DB ----------
c.commit()
after_counts = {t: cur.execute(f'select count(*) from "{t}"').fetchone()[0] for t in TRACK}
print('counts before:', bk_counts)
print('counts after :', after_counts)

# =====================================================================================
# 7. REGENERATE affected Game_Rules.xlsx sheets from the DB (surgical: only the sheets whose
#    source tables changed; all other sheets untouched). No full-workbook generator exists, so
#    we edit the workbook in place, mirroring the DB rows into the matching sheet.
#    Sheet<-table mapping (verified): '17 Objects Encounters'<-objects_encounters,
#    '16 Terrain Effects'<-terrain_effects, '14 Biomes'<-biomes, '12 Map Gen Rules'<-map_gen_rules,
#    '18 Open Decisions'<-open_decisions. (04/01 unchanged this run.)
# =====================================================================================
import openpyxl
from openpyxl.utils import get_column_letter
wb = openpyxl.load_workbook(XLSX)

def rewrite_sheet(sheet_name, table, ncols):
    """Replace the sheet body with the table rows (rowid order), preserving column width/geometry."""
    ws = wb[sheet_name]
    rows = cur.execute(f'select * from "{table}" order by rowid').fetchall()
    # clear existing cell values (keep sheet object/formatting defaults)
    max_r = ws.max_row; max_c = max(ws.max_column, ncols)
    for r in range(1, max_r + 1):
        for cc in range(1, max_c + 1):
            ws.cell(row=r, column=cc).value = None
    for i, row in enumerate(rows, start=1):
        for j in range(ncols):
            val = row[j] if j < len(row) else None
            ws.cell(row=i, column=j + 1).value = val
    return len(rows)
n1 = rewrite_sheet('17 Objects Encounters', 'objects_encounters', 9)
n2 = rewrite_sheet('16 Terrain Effects', 'terrain_effects', 9)
n3 = rewrite_sheet('14 Biomes', 'biomes', 9)
n4 = rewrite_sheet('12 Map Gen Rules', 'map_gen_rules', 9)
n5 = rewrite_sheet('18 Open Decisions', 'open_decisions', 7)
wb.save(XLSX)
print(f'xlsx regenerated: ObjEnc={n1} rows, Terrain={n2}, Biomes={n3}, MapGen={n4}, OpenDec={n5}')

# ---------- CHANGE LOG ----------
json.dump({'stamp': stamp, 'backup_db': bk_db, 'backup_xlsx': bk_xlsx, 'backup_index': bk_index,
           'counts_before': bk_counts, 'counts_after': after_counts,
           'updated_rows': [(t, r) for t, r, o, n in log],
           'inserted': inserted},
          open(os.path.join(BK, f'weather_{stamp}_changes.json'), 'w', encoding='utf-8'),
          ensure_ascii=False, indent=1)
c.close()
print('BACKUP DB   :', bk_db)
print('BACKUP XLSX :', bk_xlsx)
print('DONE. updated rows:', len(log), 'inserted groups:', len(inserted))
