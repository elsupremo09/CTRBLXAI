import sqlite3, shutil, os, json, datetime
DB = r'D:\AI\Projects\CTRBLXAI\docs\CTRBLXAI.db'
stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
os.makedirs(r'D:\AI\Projects\CTRBLXAI\docs\backups', exist_ok=True)
shutil.copy2(DB, rf'D:\AI\Projects\CTRBLXAI\docs\backups\CTRBLXAI_pre_rulings_{stamp}.db')
c = sqlite3.connect(DB)
cur = c.cursor()
log = []      # (table, rowid, old_row_tuple, new_row_tuple) for xlsx sync
inserted = [] # (table, new_row_tuple)

def cols(t):
    return [r[1] for r in cur.execute(f"pragma table_info('{t}')")]

def get(t, rowid):
    return cur.execute(f"select * from '{t}' where rowid=?", (rowid,)).fetchone()

def upd(t, rowid, **kv):
    old = get(t, rowid)
    sets = ', '.join(f'"{k}"=?' for k in kv)
    cur.execute(f"update '{t}' set {sets} where rowid=?", list(kv.values()) + [rowid])
    assert cur.rowcount == 1, (t, rowid)
    log.append((t, rowid, old, get(t, rowid)))

def ins_mgr(title, rule, status):
    cur.execute("insert into map_gen_rules values (?,?,?,?,?,?,?,?,?)", (title, rule, status, None, None, None, None, None, None))
    inserted.append(('map_gen_rules', get('map_gen_rules', cur.lastrowid)))

def add_weight(pool, name, w):
    items = [x.strip() for x in pool.split(';') if x.strip()]
    assert not any(i.startswith(name) for i in items), (pool, name)
    out, placed = [], False
    for it in items:
        try: iw = int(it.rsplit(' ', 1)[1])
        except Exception: iw = 999
        if not placed and w > iw:
            out.append(f'{name} {w}'); placed = True
        out.append(it)
    if not placed: out.append(f'{name} {w}')
    return '; '.join(out)

# ================= RULING 1 — LUK Starting RT symmetric + Player Initiative Edge =================
upd('core_stats', 54,
    topic='Starting RT applies to ALL units (players and enemies) + Player Initiative Edge (10 RT)',
    rule=("LUK Initiative is SYMMETRIC: players and enemies use the SAME formula. "
          "STEP 1 (every unit, once, at initial deployment): LUK Starting RT = round(Base RT × (1 − 0.30 × LUK / (100 + LUK))). "
          "Base RT input: player units = standard 400; enemy units = their tier base RT (current: Grunt 400, Veteran 380, Elite 350). "
          "STEP 2 (PLAYER-ROSTER units only) — Player Initiative Edge: Starting RT = LUK Starting RT − 10 (minimum 1). "
          "The edge is applied LAST, after any percentage Starting-RT modifiers (e.g. traits such as Timeline Sovereign / Temporal Drag). "
          "It does NOT apply to enemies, neutrals, allied NPCs, summons, or mid-battle reinforcements. "
          "Examples at LUK 10: Player 400 → 389 → 379; Grunt 400 → 389; Veteran 380 → 370; Elite 350 → 340. "
          "At LUK 50: Player 400 → 360 → 350; Grunt 400 → 360; Elite 350 → 315."),
    notes=("USER RULING 2026-10-02 (revises the same-day Designer ruling that had full parity and no player edge): LUK initiative applies to enemies too, keeping only a MINIMAL player-only advantage. "
           "Designer-chosen edge = flat 10 RT. Why 10, and why flat: (1) 10 RT = 2.5% of a 400 RT turn, 1% of a 1000-CT round — at equal LUK and tier the player simply moves first, so mirror matchups open in the player's favour; "
           "(2) it never overturns enemy tier identity — a LUK-10 player (379) still acts after a LUK-10 Veteran (370) or Elite (340); "
           "(3) it is the same size at every LUK, so LUK is worth exactly the same to both sides (a stronger player-only LUK coefficient was rejected: zero edge for low-LUK players, and LUK would be worth more on players than enemies — re-creating the asymmetry); "
           "(4) it is worth only ~10 LUK at low LUK, so a slightly luckier enemy can still beat it. "
           "SUPERSEDES the Sep 28 2026 'flagged, undecided' asymmetry note and this row's earlier no-edge wording. "
           "DEV CHANGE PENDING (Dev agent): EnemyGenerator sets startingRt = tier.baseRt and ignores LUK — it must apply STEP 1 to enemies; the player deploy path must add STEP 2. Until then shipped code is asymmetric. Not Studio-tested."))

r7 = get('core_stats', 7)
new7 = r7[4].split(' Starting RT applies to players AND enemies')[0] + (" Starting RT applies to players AND enemies with the SAME LUK formula (enemies use their tier Base RT); player-roster units then get a flat −10 RT Player Initiative Edge — user ruling 2026-10-02; see 'Starting RT applies to ALL units'.")
upd('core_stats', 7, notes=new7)

upd('loot_progression', 3, notes=("Calculated once at initial deployment. Does not alter later Base RT or action RT. "
     "Applies to ALL units, players and enemies (enemies use their tier Base RT); player-roster units then subtract a flat 10 RT Player Initiative Edge (core_stats 'Starting RT applies to ALL units', user ruling 2026-10-02)."))

upd('open_decisions', 67, col_3=("RESOLVED 2026-10-02 (USER RULING, refined by Designer): LUK Starting RT applies to enemies too, using their tier Base RT (Grunt 400 / Veteran 380 / Elite 350). "
     "Minimal player-only advantage = Player Initiative Edge, a flat −10 RT applied last to player-roster units' Starting RT. "
     "See core_stats 'Starting RT applies to ALL units'. Dev change pending in EnemyGenerator + player deploy path."))

# ================= RULING 2 — effect-bearing chasm floors =================
TABLE = """AUTHORITATIVE per-biome CHASM FLOOR mapping (REVISED 2026-10-02 by USER RULING: chasm/gap floors are SPECIAL effect-bearing terrain, not plain low drops). All ground effects come from the existing terrain_effects catalog — no new effect type was needed.
| Biome | Chasm floor (terrain + tile effect) | Ground effect on a unit that ends up there | Span type(s) | Gap chance | Max gaps | Width | Change |
| Plains | Grassland + Vines (overgrown ditch) | Pinned (Move disabled) while there | Plank Bridge | 25% | 1 | 1-2 | CHANGED (was Shallow Water) — Designer, under user's general rule |
| Forest | Grassland + Vines (bramble ravine) | Pinned while there; Fire burns the vines | Plank Bridge | 50% | 1 | 1-2 | CHANGED (was Shallow Water) — Designer, under user's general rule |
| Desert | Quicksand (sinking pit) | Sinking: Move disabled, Jump −1 per 500 CT, KO at −5 | Plank Bridge | 50% | 1 | 1-2 | CHANGED (was Sand) — USER |
| Swamp | Deep Water | Drowning (non-Amphibious) | Plank Bridge | 100% | 2 | 1-3 | unchanged |
| Highlands | Deep Water (gorge) | Drowning (non-Amphibious) | Plank Bridge or Rocky Causeway | 100% | 2 | 2-3 | unchanged — USER-confirmed |
| Tundra | Deep Water (open ice channel) | Drowning; Ice-tag attacks freeze it to Ice | Rocky Causeway | 50% | 1 | 1-2 | unchanged |
| Volcano | Molten (lava channel) | End of own turn: Burn +25% Max HP | Rocky Causeway | 80% | 2 | 1-3 | unchanged — USER-confirmed |
| Cave | Deep Water (underground pool) | Drowning (non-Amphibious) | Rocky Causeway or Plank Bridge | 60% | 1 | 1-2 | unchanged |
| Ruins | Cracked Ground (collapsed floor) | WT>15 unit or explosion collapses it a further −3 (+50 RT, fall damage) | Plank Bridge | 60% | 1 | 1-2 | unchanged |
| Castle | Rocky (stone moat bed) + Tar Pit ('pitch moat') | Move Cost 1.5; Petrify after 2 of the unit's own turn-ends on tar; Fire ignites it | Drawbridge | 80% | 1 | 1-2 | CHANGED (was Deep Water) — USER |
| Corrupted | Tainted Ground (tainted pit) | Non-undead lose 10% Max MP at turn start; Undead/Demons regain 10% | Plank Bridge | 50% | 1 | 1-2 | CHANGED (was Swamp) — Designer, under user's general rule |
LOCKED: chasm floor (terrain + effect) and span type. TUNABLE (balance, no design session needed): chance, max gaps, width. Depth (biome cliffDrop) is still what makes a gap impassable for ordinary walkers; the floor effect is the PENALTY for ending up in it. Rules: 'Chasm Floor = Effect-Bearing Terrain (general rule)', 'Desert Quicksand Chasm — span-crossing interaction', 'Chasm-Floor Effect Permanence'. SUPERSEDED: the earlier note 'Desert uses Sand, NOT Quicksand, on purpose' — overruled by the user; the no-counterplay concern is answered in the Desert Quicksand rule. Ruins Cracked Ground remains a deliberate exception to 'Cracked Ground only created from high-elevation Rocky/Ruins'. Tundra: freezing the floor to Ice does NOT create a crossing (still a trough)."""
upd('map_gen_rules', 59, col_2=TABLE,
    col_3=("REVISED 2026-10-02 by USER RULING (effect-bearing chasm floors). Desert / Castle / Highlands / Volcano floors user-specified; Plains / Forest / Corrupted changed by the Designer under the user's general rule (user may overrule); Swamp / Tundra / Cave / Ruins were already effect-bearing. "
           "DEV CHANGE PENDING: shipped FeaturePass / BIOME_ELEVATION.gapPolicy still uses the OLD floors (Plains+Forest Shallow Water, Desert Sand, Castle Deep Water, Corrupted Swamp) and does not yet place floor tile effects. Not Studio-tested."))

r56 = get('map_gen_rules', 56)[1]
r56n = (r56.replace("and given the biome's gap-floor terrain, so the gap is impassable BY DEPTH",
                    "and given the biome's EFFECT-BEARING chasm-floor terrain (user ruling 2026-10-02 — e.g. Quicksand, Molten, Deep Water, Tar Pit), so the gap is impassable BY DEPTH")
           .replace("the Stone Pillar 3-tile bridge (objects_encounters)", "the Stone Pillar 4-tile fallen span (objects_encounters, revised 2026-10-02)")
           .replace("can cross without the span — this rewards DEX/flight.",
                    "can cross without the span — this rewards DEX/flight. EXCEPTION: Desert's Quicksand floor cannot be entered voluntarily, so there only Flight / teleport-type effects bypass the span."))
assert r56n != r56 and r56n.count('2026-10-02') >= 2
upd('map_gen_rules', 56, col_2=r56n)

ins_mgr('Chasm Floor = Effect-Bearing Terrain — general rule (P0)',
 ("Every biome's chasm (gap) floor uses an EFFECT-BEARING terrain, or terrain + tile effect, that fits the biome (table: 'Gap Floor Terrain + Span Type per Biome') — never a plain drop. "
  "(1) The floor's normal ground effect applies to ANY unit that ends up on a chasm-floor tile, however it got there — forced displacement (push, knockback, shove), a voluntary downward drop, a collapse, or a teleport — at that effect's normal timing (Drowning / Sinking / Pinned on entry; Molten and the Tar Pit counter at the unit's own turn-end; Tainted at turn start). "
  "(2) Fall damage still applies on top when a FORCED drop is 3+ levels (cliffDrop 3 biomes Highlands / Volcano / Castle ≈ 4% Max HP; 2-level drops deal none). "
  "(3) Forced displacement INTO a chasm is allowed even when the floor forbids voluntary movement (Quicksand): 'Movement prohibited' blocks walking / path entry only, not being pushed in. "
  "(4) Depth is unchanged — the chasm is still impassable by depth for ordinary walkers; the effect is the penalty for being in it. "
  "(5) Spans are unchanged and stay PROTECTED ('Span Tile Protection'); a floor effect never spreads onto a span tile. "
  "(6) AI: chasm-floor tiles count as hazard tiles — high value as a push destination, avoided in the unit's own movement scoring. "
  "COUNTERPLAY (every floor has one): Vines (Plains/Forest) — Pinned stops only Move, not attacks/skills; Fire burns the vines off. "
  "Quicksand (Desert) — a Water-element hit turns it to Mud (existing transform) and ends Sinking; Flight; Blink / Phantom Exchange / teleport; Sinking KO takes 2500 CT (~5-6 turns) so allies have time. "
  "Deep Water — Amphibious immune; Flight; Ice-tag freezes it (Tundra); Drowning KO takes 2500 CT. "
  "Molten (Volcano) — Water turns it to Rocky (existing transform). "
  "Tar Pit (Castle) — Petrify needs 2 of the unit's own turn-ends on tar, so a unit that is pulled/teleported/flown out in time is safe; Fire ignites the tar (Burning replaces it while it burns). "
  "Tainted (Corrupted) — drains MP only, no HP loss; Light turns it to Grassland. "
  "Cracked Ground (Ruins) — only collapses for WT>15 units or explosions. "
  "After a transform (Mud / Rocky), a unit with Jump ≥ the biome cliffDrop can climb out."),
 "Locked 2026-10-02 (USER RULING, P0) — Designer-authored detail. DEV CHANGE PENDING. Not Studio-tested.")

ins_mgr('Desert Quicksand Chasm — span-crossing interaction (P0)',
 ("CONFIRMED: a Quicksand floor fits the 'span is the only crossing' model; only the floor terrain changes in the generator. "
  "(1) Generation / validation: gap tiles were already impassable by depth; Quicksand is ALSO a movement BLOCKER in the shipped move model, so a Desert gap is impassable twice over. validateGapSpans and the Gap Hard Invariant are unaffected because span tiles are Plank Bridge (Wooden Floor), not Quicksand. repairBridgePass must NOT 'repair' Quicksand chasm-floor tiles — they are not LAN tiles; only the span is. "
  "(2) Crossing: in other biomes a unit with Jump ≥ gap depth can climb down and out the far wall; in Desert it CANNOT, because Quicksand can't be entered voluntarily. For ground units the span is the ONLY crossing of a Desert chasm (shortcut gaps still keep their walk-around detour). Only Flight and Blink / teleport / swap effects bypass it. This makes Desert chokepoints the strictest in the game — a good fit for Desert's ranged / long-sightline identity and its low gap rate (50%, max 1 gap). "
  "(3) Being pushed in is allowed (general rule point 3). The unit gets Sinking: Move disabled, Jump −1 every 500 CT, KO at −5 (2500 CT). Rescue: a Water hit turns the tile to Mud and ends Sinking (the unit is then in a Mud trench and needs Jump ≥ 2 — Desert cliffDrop 2 — to climb out), Flight, Blink / Phantom Exchange / teleport. An upward PULL cannot extract it (forced upward displacement is illegal unless a skill says otherwise). "
  "(4) Plank Bridge spans can still burn, and units on them can be pushed off into the Quicksand — this is the intended Desert bridge threat."),
 "Confirmed 2026-10-02 (USER RULING, P0). Supersedes the earlier Sand-floor rationale. Dev to VERIFY repairBridgePass ignores off-span chasm-floor tiles. Not Studio-tested.")

ins_mgr('Chasm-Floor Effect Permanence (P0)',
 ("Tile EFFECTS that generation places on a chasm floor (Vines on Plains / Forest; Tar Pit on Castle) are PERMANENT floor effects: duration Unlimited, and if a reaction temporarily replaces them (Fire → Burning), the original floor effect RE-ESTABLISHES when the replacing effect expires — but only if the base terrain is still compatible (e.g. if a later Fire hit turns the Grassland floor into Sand, Vines do not return, because Vines need Organic ground). "
  "Why: a castle 'pitch moat' that can be set alight and still holds its tar afterwards is a classic siege beat, and one fire should not permanently erase a biome's chasm identity. "
  "Terrain TRANSFORMS of the floor (Quicksand → Mud, Molten → Rocky, Deep Water → Ice) are permanent and do NOT revert — they are the counterplay. "
  "Burning on a chasm floor cannot spread out of the chasm (spread needs elevation within ±1; chasm walls are 2-3 levels)."),
 "Designer rule 2026-10-02 implementing the USER RULING (P0). DEV CHANGE PENDING — needs a per-tile 'base floor effect' slot that is re-applied when the current effect expires. User may overrule. Not Studio-tested.")

bio = {16: "Rare. Occasional overgrown-ditch gap (Grassland + Vines floor) with a 1-2 tile Plank Bridge span; no deep chasms. (Revised 2026-10-02 — effect-bearing chasm floors; see map_gen_rules 'Gap Floor Terrain + Span Type per Biome'.)",
       17: "Occasional bramble-ravine gap (Grassland + Vines floor) crossed by a short Plank Bridge span; chokepoint bridges between clearings. (Revised 2026-10-02 — effect-bearing chasm floors.)",
       18: "Quicksand sinking-pit gaps between mesas, crossed by Plank Bridge spans; Quicksand cannot be entered, so the span is the only ground crossing. (Revised 2026-10-02 — user ruling.)",
       25: "Pitch-moat gaps (Rocky stone bed + Tar Pit) and courtyard drops crossed by Wooden Floor Drawbridge spans; wall-top high ground. (Revised 2026-10-02 — user ruling.)",
       26: "Tainted-pit gaps (Tainted Ground floor) crossed by short Plank Bridge spans; cursed-landmark high ground. (Revised 2026-10-02 — effect-bearing chasm floors.)"}
for rid, txt in bio.items():
    upd('biomes', rid, col_6=txt)

def te_note(rowid, col, text, mode='set'):
    old = get('terrain_effects', rowid)[cols('terrain_effects').index(col)]
    new = text if mode == 'set' or old in (None, '—', '') else old.rstrip('.') + '. ' + text
    upd('terrain_effects', rowid, **{col: new})
te_note(18, 'col_8', "Desert chasm floor (map_gen_rules, 2026-10-02). 'Movement prohibited' = cannot be entered by walking / pathing; forced displacement CAN put a unit on it, which applies Sinking. Water → Mud ends Sinking.")
te_note(29, 'col_9', "Castle chasm floor 'pitch moat' on Rocky (map_gen_rules, 2026-10-02). On a chasm floor it is a permanent floor effect: Fire → Burning, and the Tar Pit re-establishes when Burning expires ('Chasm-Floor Effect Permanence').")
te_note(30, 'col_9', "Plains / Forest chasm floor on Grassland (2026-10-02); permanent floor effect there — re-establishes after Burning expires if the ground is still Organic.", mode='append')
te_note(14, 'col_8', "Volcano chasm floor (lava channel).", mode='append')
te_note(11, 'col_8', "Chasm floor for Swamp, Highlands, Tundra and Cave (2026-10-02).", mode='append')
te_note(16, 'col_8', "Corrupted chasm floor (2026-10-02).")

es = get('elements_statuses', 59)
upd('elements_statuses', 59, effect=es[6].rstrip('.') + ". Also removed if the tile stops being a sinking tile (e.g. a Water hit turns Quicksand → Mud). The Jump penalty is removed together with the status. Forced displacement onto Quicksand applies Sinking (Desert chasm floor, 2026-10-02).")

# ================= RULING 3 — Stone Pillar rework + spawn =================
upd('objects_encounters', 9,
    col_7=("Falls in the direction opposite the interacting unit and becomes a 4-TILE-LONG Rocky span (fallen pillar = 4 tiles long × 1 tile wide; the standing pillar is 4 elevation levels HIGH, which is why its fall reaches 4 tiles) or crushes units on the landing tiles (70% Max HP, +100 RT, Pinned)"),
    col_9=("Permanent terrain change. REVISED 2026-10-02 (user ruling): was a 3-tile bridge; now 4 long × 4 high. "
           "STANDING: Height 4 (4 elevation levels tall) — blocks movement and line of sight like a 4-high wall. "
           "FALLEN: 4 tiles long; span deck sits at the pillar's base-tile elevation; if a landing tile is 2+ levels higher than the base, the fall stops short there (the span ends on the previous tile; units on tiles it reached are still crushed). "
           "A 4-tile fall always reaches the far bank of any generated gap (max gap width 3). Crush unchanged: 70% Max HP (HP%-based, so boss HP% resistance applies), +100 RT, Pinned — now up to 4 tiles in a line instead of 3. "
           "The fallen span is NOT a protected generated span ('Span Tile Protection' does not apply). "
           "SPAWN (2026-10-02): highest share in Ruins (biome 8, region 8 — unchanged); also added to Castle biome 4, Corrupted biome 3, Castle Courtyard 4, Castle Interior 2, Village 3 (closest to 'big town'), Corrupted region 2 (closest to 'magic region')."))

for t, rid, col, w in [('biomes', 12, 'col_4', 4), ('biomes', 13, 'col_4', 3),
                       ('regions', 16, 'col_6', 4), ('regions', 17, 'col_6', 2),
                       ('regions', 5, 'col_6', 3), ('regions', 19, 'col_6', 2)]:
    old = get(t, rid)[cols(t).index(col)]
    upd(t, rid, **{col: add_weight(old, 'Stone Pillar', w)})

b28 = get('biomes', 28)
upd('biomes', 28, col_9=b28[8].replace('Stone Pillar 3-tile bridge (objects_encounters row 9)', 'Stone Pillar 4-tile fallen span (objects_encounters row 9; was 3-tile until 2026-10-02)'))

c.commit()
json.dump({'log': [[t, r, list(o), list(n)] for t, r, o, n in log], 'inserted': [[t, list(n)] for t, n in inserted]},
          open(r'D:\AI\Projects\CTRBLXAI\docs\backups\rulings_20261002_changes.json', 'w', encoding='utf-8'), ensure_ascii=False)
print('updated rows:', len(log), 'inserted:', len(inserted), 'backup stamp', stamp)
for t, r, o, n in log:
    print(t, r)
