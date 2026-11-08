# Follow-up: 7:14 PM rulings (Dragon Dive / Decimating split, Blood Price, augment add-ons on area skills)

**Run:** 2026-11-08 · **Seed:** `followup_1114` (no randomness in the game) · **Formulas:** 23 from the last run + 16 new = 39 (see FORMULAS_followup.md) · **Content:** 11 area skills × 3 weapons × 8 augments, plus Blood Price · **Levels:** 1, 25, 50, 99, 150, 199, 250, 300 (tables show 99 / 199 / 300)
**Test units:** Humans with median armor. Attackers put 60% of their points into STR (or INT). Enemies split their points evenly. An enemy turn lasts about 620 CT at every level.
**"Speed"** means the share of its normal turns an enemy still gets. 100% = unaffected, 0% = frozen.
**Note:** the DB rows for the 7:14 PM rulings are still tagged "NOT BUILT (queued)", but you told me they're built. The Designer should update those tags. I priced the rules as the DB describes them.

---

## VERDICT: 2 CRITICAL FINDINGS
1. **The near-freeze is only partly fixed.** It's fixed at L99 with a Hammer. **With Claws it still happens,** and at L199+ it happens with a Hammer too. I only tested Hammer last time, so I missed the Claws case.
2. **New:** Silencing Support (+ Disarming Support) on an area skill **locks a whole group out of skills and basic attacks.**

---

## 1. Dragoon / Decimating near-freeze: confirmed?
Setup: 2 users, 3 bunched enemies, each user casts twice a turn, and the main target rotates between the 3 enemies.

| Speed of the 3 enemies | L99 | L199 | L300 |
|---|---|---|---|
| Hammer Dragon Dive: before → **now** | 5% → **37%** | 0% → **21%** | 0% → **15%** |
| **Claws** Dragon Dive: before → **now** | 0% → **20%** | 0% → **3%** | 0% → **0%** |
| Hammer Decimating Swing: before → **now** | 15% → **43%** | 0% → **27%** | 0% → **20%** |
| **Claws** Decimating Swing: before → **now** | 0% → **31%** | 0% → **13%** | 0% → **6%** |
| 1 Hammer Dragoon (for scale) | 68% | 60% | 57% |
| Sword, Greatsword, War Axe (2 users) | 60%+ | 51%+ | 48%+ |

- **Why Claws:** Claws apply the same turn delay as a Hammer (110) but weigh 25 instead of 130. The user acts about 20% more often, so the delay piles up faster.
- **Why it gets worse with level:** the delay per hit grows from 29% to 37% of an enemy turn between L99 and L300, while the length of an enemy turn stays flat.
- **If both users always land on the same enemy,** that one enemy drops to **5% / 0% / 0%**. That single-target lock existed before rule 252 and isn't caused by this batch.
- **Limit:** MP runs out after about 3 turns of double-casting. Three turns of an almost-frozen group is still usually enough to win the fight.

**Verdict: CHANGE.** The split did its job for Hammer at L99. It doesn't stop Claws, and it doesn't hold above L150.

## 2. Area skills + augment add-ons (L99 unless stated)

| Add-on | Verdict | What it does on an area skill |
|---|---|---|
| **Silencing Support** (+ Disarming Support in slot 2) | **CHANGE (critical)** | Silence lasts about 2.5 enemy turns at L99 (1.7 at L300). Disarmed lasts about 3.7. One cast every 2 turns keeps every unit hit unable to use skills, and with Disarm unable to basic attack either. Venom Burst with both add-ons costs 24 MP, so an INT caster can cast it about 22 times, enough for the whole battle. Enemies can roll these add-ons too. Allies standing in the area also get locked. |
| **Pinning Support** (Thunderclap and other big areas) | **CHANGE** | One caster casting once a turn keeps **every unit in the area pinned 100% of the time** at L99. That holds for Thunderclap (up to 24 tiles), Venom Burst, Sweeping Cut, Gale Thrust, Dragon Dive and Chain Spark. At L300 it drops to 81–93% for STR casters. MP lasts about 4 casts for a STR caster, but **15 (Thunderclap) to 26 (Venom Burst) for an INT caster.** Pinned units can still attack and cast, so this locks movement, not turns. Melee enemies 2–3 tiles away become useless. Your own allies in the area get pinned too. |
| Crippling Support | WATCH | One cast halves the movement range of everyone hit for about 3.9 turns. |
| **Vitality Surge** (if it counts every unit hit) | **CHANGE / ruling** | It heals 5% of the caster's max HP per unit hit. Thunderclap on 4 enemies + 1 ally heals **25% per cast**. A full Venom Burst (9 units) heals 45%. Two Sweeping Cuts on 3 units heal 30% a turn, while an enemy basic attack takes about 9%. **Hitting your own allies also heals you.** The DB row still says "once per supported resolution", which conflicts with the new rule. |
| Lifesteal | OK | It's already based on total damage dealt, so it heals about 3–9% of max HP per cast. |
| Delay Strike | OK alone, WATCH stacked | It adds about 11% of a turn per target per round. Each user takes off about 7 points of enemy speed (Thunderclap: 94% → 87%). Added to 3 Claws Dragoons it takes the group from 36% → 16% (L99) and 19% → 4% (L300). |
| Sluggish Blow | OK (weak) | Slow costs about 8.5% of one turn, even on an area skill. |
| Interrupt | **REDUNDANT** | On an area skill it breaks every channel in the area. Silencing Support does that too, because Silence breaks channels. Silencing also lasts 2000 CT and costs less MP (×1.25 vs ×1.40). Nothing picks Interrupt. |
| Scatter / Vortex Strike | OK | Each moves every unit hit by exactly 1 tile, allies included. They only move units onto free tiles, so there's no wall damage, and being Pinned doesn't stop the move. Vortex keeps groups bunched for the next area skill, which feeds finding 1. Scatter on Thunderclap pushes enemies at 3 tiles out to 4. |

## 3. Blood Price: still a watch item?
**WATCH (low). No change needed.**
- At range 1 it loses its safe-distance edge. Standing next to an enemy, each enemy basic attack takes about 9% of the caster's HP.
- Last report's "1.8× Power Strike per RT" made it look stronger than it is, because a turn's base time is most of the turn. Over whole turns it deals **1.30× Power Strike's damage at every level**, for 0 MP and 15% HP per cast.
- Optional tweak: RT ×0.80 → ×1.00 brings the lead down to 1.24×.
- If "no INT bonus" was also meant to remove Skill Potency from its damage, the lead becomes 1.09× at L99 and 0.89× at L300. It would then fall behind Power Strike at high levels.

---

## Recommended changes (you decide)
1. **Turn-delay cap (system-wide). I now recommend this firmly.** A unit can receive at most **50% of its Modified Base RT** (about 223 CT) of turn delay between two of its own turns.
   *Result:* no enemy drops below about **74% speed** from delay, at any level, with any weapon or stack. That covers Claws, Hammer, focus-fire and Delay Strike stacking.
   *Trade-off:* heavy-delay weapons lose their stacking value. A single big hit (182–243 CT) mostly still fits under the cap. A softer 100% cap gives a floor of about 58%.
   *Narrower alternative:* Claws turn delay 110 → 70 (Claws Dive becomes 49% / 38% / 35%). Hammer stays at 37% / 21% / 15%, so L199+ isn't fixed.
2. **Control add-ons on area skills: a short immunity window.** When Silenced, Disarmed or Pinned that came from an augment ends, the same augment status can't land on that unit again until the end of its next turn. This works like the existing Sleep Immunity.
   *Result:* uptime drops to about 55–70%.
   *Cheaper alternative:* half duration for units other than the main target, which mirrors the Dragon Dive split. That's enough for Pinned (about 55–64% uptime) but **not** for Silence, which still holds with one cast per turn.
3. **Vitality Surge:** once per cast, as its row says, or count at most 3 units (15% max HP).
4. **Delay Strike:** the "1 per target per round" limit counts all copies together, not each caster separately.
5. **Interrupt (optional):** lower its MP cost to ×1.15 so it isn't strictly worse than Silencing Support.

## Needs a user ruling
- **A.** Recommendation 1: yes or no, and 50% or 100%?
- **B.** Recommendation 2: immunity window, half duration, or leave as is?
- **C.** Vitality Surge on area skills: once per unit hit, or once per cast? The DB row and rule 252 disagree.
- **D.** Delay Strike limit: per copy, or total?
- **E.** Blood Price "no INT bonus": range only (what the DB has now), or also remove Skill Potency from its damage?
- **F.** Pinning Support length: the augment says "1 turn" and the status says 1000 CT. Which one applies? (Results are the same at L99.)
- **G.** Scatter Strike: does a hazard tile (lava, deep water, chasm) count as a "valid" tile to push onto?

## Healthy (no need to spend time here)
- Sword, Greatsword and War Axe area delays: 2 users still leave enemies at 48%+ speed.
- Hammer Dragon Dive and Decimating Swing at L99 or below.
- Lifesteal and Sluggish Blow on area skills.
- Scatter and Vortex distances.
- Tidal Crash, Meteor Marker, Pyroclasm and Chain Spark delays: 84%+ speed with up to 3 users, without Delay Strike.

## Delta from the last report
- **Resolved:** the Hammer group freeze at L99. The Blood Price range question (now range 1).
- **Partly resolved:** the Hammer group freeze at L199+ (0% → 15–27%).
- **New:** the Claws group freeze; the Silence/Disarm area lock; the Pinning group movement lock; Vitality Surge counting every unit hit; Interrupt being outclassed.
- **DB values changed since the last run:** Dragon Dive and Decimating Swing delay splits; Blood Price range; the rule 252 add-on extension; the Pinning Support note.

Files written: sim\balance_review_2026-11-08\followup_1114\ only (harness_followup.py, results.json, FORMULAS_followup.md, REPORT.md). Nothing in source\ or docs\ was touched. The DB was opened read-only.
