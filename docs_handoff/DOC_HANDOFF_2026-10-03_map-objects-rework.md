# DOC HANDOFF — Map Object Catalog Rework
**Date:** 2026-10-03
**From:** Roblox Dev Expert (on behalf of Elmer)
**To:** Designer CTRBLXAI
**Target:** `CTRBLXAI.db` → `objects_encounters` table (+ `explosion tag` / Explosion Tag decision row). Regenerate `ObjectData.lua` export + INDEX.txt + xlsx after applying.
**Authority:** All values below are USER-APPROVED design decisions (confirmed in session 2026-10-03). Dev does NOT edit docs/DB — Designer applies.

---

## 0. GLOBAL RULES (apply catalog-wide)

- **G1 — Default Interact RT:** If a map object specifies NO explicit RT cost, its Interact uses the default Interact RT = `round(Modified Base RT × 0.10)` (the native map-object Interact cost). USER RULE 2026-10-03. Applies to every object below that doesn't state an RT.
- **G2 — Area → radius wording:** Convert ALL `N×N` area descriptions to radius form (Chebyshev/Circle): `3×3 → radius 1`, `5×5 → radius 2`. Apply everywhere in the table (effects AND notes).
- **G3 — Explosion elevation ownership:** The elevation drop on explosions belongs to the **explosion tag**, NOT to individual objects. Remove per-object "lowers elevation"/"Elevation −1" wording from Bomb Barrel and Land Mine. The explosion tag carries the elevation drop. Specific terrain that declares its own magnitude (e.g. Cracked Ground −3 collapse) SUPERSEDES the generic tag (does not stack) — this precedence is already how Cracked Ground is written; keep it. (Magnitude of the tag's generic drop: keep at the current −1 that Bomb Barrel/Land Mine used, unless Designer judgment says otherwise — flag back if changing.)

---

## 1. HAZARD

### Bomb Barrel  (MODIFY)
- Effect: `radius 1 Explosion (25% Max HP), destroys adjacent breakable bridges/walls` (was `3×3 Explosion …`)
- Notes: REMOVE "Explosion lowers elevation by 1" (now owned by explosion tag per G3). KEEP the "generated gap spans are NOT breakable bridges" clause.

### Land Mine  (MODIFY)
- Effect: `radius 1 Explosion (25% Max HP)` — REMOVE the `, Elevation −1` (now owned by explosion tag per G3). Keep "Chain reactions allowed" note.

### Oil Sluice  (MODIFY)
- Effect: `Creates Tar Pit in radius 2 area` (was 5×5)

### Steam Valve  (MODIFY)
- Effect: `Creates Steam in radius 2 area` (was 5×5)

(Bear Trap, Spike Trap, Snare Trap — unchanged.)

---

## 2. SIEGE

### Ballista  (MODIFY)
- Effect: `Fires a penetrating bolt (250% Weapon Damage) in a chosen CARDINAL direction` (restrict to 4 cardinal directions, was "chosen direction")
- Activation: Interact (Consumes Action), explicit **RT 100**
- Uses: **Once per turn** (was Unlimited) — NOTE: "once per turn" is a NEW per-unit-per-turn constraint type; previously objects were per-battle "Once" or "Unlimited". Flag for Slice 5 object-runtime (needs a per-turn usage tracker).
- Notes: keep "Uses operator stats".

### Catapult  (MODIFY)
- Effect: `Fires a projectile (200% Weapon Damage, Cross AOE) within Range 6` — AOE pattern 3×3 splash → **Cross** (radius-1 cross / plus-shape, 5 tiles). "Cross" is an existing AOE pattern (TargetingService.GetCrossTiles).
- Activation: Interact (Consumes Action), explicit **RT 100**
- Keep Range 6, 200% Weapon Damage, "Splash damages objects".

(Stone Pillar, Ice Spike — unchanged.)

---

## 3. AURA / BUFF OBJECTS

**Batch rule for activated timed-buff objects:** duration CT 900 → **1500 CT**, activation cost **RT 150** (these become Interact (Consumes Action) — no longer Free). Applies to Rally Flag + the 4 renamed guild objects below.

### Rally Flag  (MODIFY)
- Effect: `Allies gain +1 Move and +1 Jump for 1500 CT` (CT 900→1500)
- Activation: Interact, **RT 150**. Keep "Does not stack".

### Mage Guild → **Star Axis**  (RENAME + MODIFY)
- Effect: `Friendly units gain +20% Spell Damage for 1500 CT`
- Activation: Interact, **RT 150**. Does not stack. (Model "Star Axis" exists in ServerStorage.)

### Warrior Guild → **Burning Cauldron**  (RENAME + MODIFY)
- Effect: `Friendly units gain +20% Physical Damage for 1500 CT`
- Activation: Interact, **RT 150**. Does not stack. (Model "Burning Cauldron" exists.)

### Mercenary Camp → **War Horn**  (RENAME + MODIFY EFFECT)
- Effect CHANGED: `Friendly units gain −15% to base RT for 1500 CT` (−15% base RT = act FASTER; this is a BUFF. User-confirmed direction.)
- Activation: Interact, **RT 150**. Does not stack.
- NAME NOTE: "War Horn" also exists as a WEAPON archetype (ImpactSplash). User accepted reuse for this map object; different systems. Model "War Horn" exists in ServerStorage.

### Marletto Tower → **Runed Boulder**  (RENAME + MODIFY EFFECT)
- Effect CHANGED: `Friendly units gain +10% Attack and +10% Defense for 1500 CT` (was "take 20% less damage")
- Activation: Interact, **RT 150**. Does not stack. (Model "Runed Boulder" exists.)

### War Banner  (UNCHANGED — passive aura, +15% stats radius 3)

### Cursed Statue  (MODIFY EFFECT)
- Effect CHANGED: `Units within radius 3 suffer +20% to base RT` (was −15% all primary stats). +20% base RT = those units act SLOWER. Remains **Passive**, radius 3, "Removed if destroyed". (This is the hostile-area statue; slowing enemies in its radius.)

---

## 4. EXPLORATION

### Warrior's Tomb → **Cursed Chest**  (RENAME, effect unchanged)
- Effect: `Random treasure; inflicts Weakened (3000 CT)`. (Model "Cursed Chest" exists.)

### Arena → **Blood Fountain**  (RENAME + MODIFY EFFECT)
- Effect CHANGED: `Grant Regeneration to all allies (MAP-WIDE)` (was +20% highest stat)
- Activation: Interact, **RT 150**. (Model "Blood Fountain" exists.)
- "all allies" = MAP-WIDE (every allied unit regardless of distance). USER-CONFIRMED.
- Was flagged `parked`; new effect (Regeneration) is a live status — Designer: drop the parked flag unless Regeneration delivery to map-wide allies needs runtime work (then keep a Slice-5 note).

### Tree of Knowledge → **Astrolabe**  (RENAME + MODIFY EFFECT)
- Effect CHANGED: `Single use. Reduce current RT of all allied units (MAP-WIDE) by 200.`
- Activation: Interact, **RT 400**. Uses: Once.
- "all allied units" = MAP-WIDE. USER-CONFIRMED. (Model "Astrolabe" exists.)

### Scholar  (REMOVE)
- Delete from catalog entirely. (No model dependency — "Scholar" not in model list.)

### Library of Enlightenment  (REMOVE)
- Delete from catalog entirely. USER-CONFIRMED 2026-10-03 (was previously proposed as an Enlightened-buff rework; user chose removal instead). No model dependency.

### Cartographer → **Crystal Ball**  (RENAME, effect unchanged)
- Effect: `Reveals all Hidden Treasures`. Interact (Free), Unlimited. (Model "Crystal Ball" exists.)

### Eye of the Magi  (MODIFY EFFECT; model renamed to match catalog spelling "Eye of the Magi")
- Effect CHANGED: `Attacks two random opponents for 40% of their max HP each.` (was reveal hidden)
- Activation: Interact, **RT 150**. Uses: **Once per turn**. (Same new per-turn constraint as Ballista — flag for runtime.)
- NOTE: 40% of each target's OWN max HP (per-target). Model "Eye Of Magi" was renamed to "Eye of the Magi" on user's end (1:1).

### Black Market  (UNCHANGED)
### Healing Spring, Magic Spring, Campfire, Mimic, Treasure Chest  (UNCHANGED)

---

## 5. EVENT

### Trading Post  (REMOVE)
- Delete from catalog. (No model dependency.)

### Den of Thieves → **Mysterious Boulder**  (RENAME + MODIFY EFFECT)
- Effect CHANGED: `Single use. Roll a random debuff, then inflict it on ALL enemies.`
- Activation: Interact, **RT 200**. Uses: Once. (Model "Mysterious Boulder" exists.)

### Altar of Sacrifice → **Necro Tome Stand**  (RENAME + MODIFY EFFECT + ACTIVATION TYPE)
- Effect CHANGED: `Passive. Whenever a unit dies within radius 3, inflict dark damage to ALL opponents equal to 10% of the DYING unit's max HP.`
- Activation: **Passive** (was Interact). Uses: Passive/Unlimited.
- "10% of max HP" = the DYING unit's max HP (flat to all opponents in range). USER-CONFIRMED.
- "opponents" = enemies relative to the owner of the triggering death? Designer: interpret as "all units opposed to the dying unit's side" (a death on either side triggers damage to that unit's opponents). Flag if user means only player-side deaths.

### Refugee Camp  (REMOVE)
- Delete from catalog.

### Seer's Hut → **Chaos Statue**  (RENAME, effect unchanged)
- Effect: `Generates one optional quest`. Interact (Free), Once. (Model "Chaos Statue" exists.)
- NOTE: user briefly said "Obelisk" then corrected to **Chaos Statue**. The existing **Obelisk stays Obelisk** (see below). No collision.

### Skeleton Transformer  (REMOVE)
- Delete from catalog (was parked).

### Stables → **Angel Statue**  (RENAME, effect unchanged)
- Effect: `Grants Flight for 1500 CT`. Interact (Free), Once. (Model "Angel Statue" exists.)

### War Machine Factory → **Forge**  (RENAME + RT)
- Effect: `Summon one Ballista or Catapult on a chosen tile within radius 3 of the object` (unchanged)
- Activation: Interact, **RT 150**. (Model renamed `Forge_BLDG` → **Forge** on user's end; catalog name = "Forge", 1:1.)

### Obelisk  (UNCHANGED — keep name & effect: +300 RT Delay to all enemies)

### Fountain of Fortune  (MODIFY EFFECT)
- Effect CHANGED: `Fortune +50% to all allies (MAP-WIDE) for 1500 CT` (was "increased recruitment success")
- Activation: Interact, **RT 150**. (Model "Fountain of Fortune" exists.)
- "all allies" MAP-WIDE. USER-CONFIRMED.

### Idol of Fortune, Tavern, Cover of Darkness, Dragon Utopia  (UNCHANGED)

---

## 6. NEW OBJECTS (7)

All have ServerStorage models (confirmed in screenshot). Default Interact RT (G1) unless stated.

### Glow Crystal  (NEW — PARKED)
- Category: Event (Designer's call) | Activation: **Interact** (default Interact RT per G1) | Uses: Once
- Effect: `Double all experience gained at end of battle.`
- **PARKED:** depends on XP/leveling system (Slice 6, not built). Define now, mark parked/inert until XP exists.

### Pandora's Box  (NEW)
- Category: Event | Activation: Interact, explicit **RT 50** (flat, regardless of triggered effect) | Uses: Designer's call (suggest Once)
- Effect: `Triggers a random map object effect, drawn from the FULL pool including harmful effects (traps/explosions can backfire on the user's side).` USER-CONFIRMED: all effects, can backfire.
- Designer: define the roll pool (all object effects) + whether triggered effect centers on Pandora's Box tile. Flag any effects that can't sensibly be triggered this way.

### Cursed Statue  — NOTE: already handled under §3 (effect reworked to +20% base RT, passive). The screenshot's "Cursed Statue" model maps to this existing object. (The user's "New:" list re-stated Cursed Statue — it is a MODIFY of the existing object, not a second object.)

### Eye of the Magi — already handled under §4 (NOT new; the "New:" list re-stated it as a MODIFY).

### Fountain of Fortune — already handled under §5 (NOT new; MODIFY).

### Potion Desk  (NEW — PARKED)
- Category: Exploration or Event (Designer's call) | Activation: **Interact**, default Interact RT (G1 — user rule: no explicit cost → default) | Uses: Single use (Once)
- Effect: `Fully recharge all equipped consumables (of the interacting unit? or all allies?)` — ⚠️ AMBIGUITY: user said "fully recharge all equipped consumables" without specifying whose. Designer: default to the INTERACTING UNIT's consumables unless user clarifies map-wide. FLAG for user.
- **PARKED:** depends on consumable charge-refill (Slice 8 Guild Base). Define now, mark parked/inert until charge-refill exists.

### Swan Pond  (NEW)
- Category: Event | Activation: Interact, explicit **RT 150** | Uses: Single use (Once)
- Effect: `Remove all debuffs from all allies (MAP-WIDE).`
- "all allies" MAP-WIDE (consistent with the user's global map-wide ruling this session; FLAG if Swan Pond should be radius-limited instead).

---

## 7. REMOVALS SUMMARY (5)
Scholar, Trading Post, Refugee Camp, Skeleton Transformer, Library of Enlightenment — delete from `objects_encounters`.

## 8. RENAME SUMMARY (object catalog name changes)
| Old | New |
|-----|-----|
| Mage Guild | Star Axis |
| Warrior Guild | Burning Cauldron |
| Mercenary Camp | War Horn |
| Marletto Tower | Runed Boulder |
| Warrior's Tomb | Cursed Chest |
| Arena | Blood Fountain |
| Tree of Knowledge | Astrolabe |
| Cartographer | Crystal Ball |
| Den of Thieves | Mysterious Boulder |
| Altar of Sacrifice | Necro Tome Stand |
| Seer's Hut | Chaos Statue |
| Stables | Angel Statue |
| War Machine Factory | Forge |

## 9. MODELS WITH NO CATALOG USE YET (ignore this handoff)
Anvil, Bone Totem, Crystal Fountain, Cursed Mirror, Door of Light, Horror Gate, Magic Fountain — user: "no use yet, ignore." Do NOT create catalog rows.

## 10. RESOLVED DECISIONS (all confirmed by user 2026-10-03 — no open flags)
1. **Potion Desk scope** — RESOLVED (user): recharges the INTERACTING UNIT's equipped consumables only (not map-wide).
2. **Library of Enlightenment** — RESOLVED (user): REMOVE from catalog (see §4/§7). Not a rework.
3. **Passive aura sidedness (Necro Tome Stand + ALL passives)** — RESOLVED (user): ALL passive auras apply to BOTH sides. Necro Tome Stand: a death on either side within radius 3 inflicts dark damage = 10% of the DYING unit's max HP to that unit's opponents. (General rule: passive-aura objects affect every unit in range regardless of side, per the object's effect sign.)
4. **Explosion tag elevation magnitude** — RESOLVED (user): explosion tag carries −1 elevation drop; ownership moved from objects to the tag; magnitude unchanged. Cracked Ground's −3 collapse SUPERSEDES (does not stack).
5. **Swan Pond scope** — RESOLVED (user): MAP-WIDE (remove all debuffs from all allies everywhere).
6. **"Once per turn" semantics** (Ballista, Eye of the Magi) — RESOLVED (user): per-unit, per-turn — usage resets at the start of each of that unit's OWN turns (same as Guard's once-per-turn). Slice 5 object-runtime needs a per-unit-per-turn usage tracker.

## 11. POST-APPLY STEPS (Designer)
- Regenerate `ObjectData.lua` (ReplicatedStorage/Content) from the updated table.
- Regenerate INDEX.txt + xlsx exports; take DB backup first (per prior handoff pattern).
- Note in open_decisions: Glow Crystal (XP dep / Slice 6) and Potion Desk (charge-refill dep / Slice 8) are parked.
- Model-name reconciliation: catalog names now match ServerStorage model names for all renamed/new objects (user renamed Forge_BLDG→Forge and Eye Of Magi→Eye of the Magi on the model side).
