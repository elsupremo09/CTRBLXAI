# Balance Review: Nov 8 batch (rules 252 / 253 and the related skill builds)

**Run:** 2026-11-08 · **Seed:** `nov08_batch` (no randomness in the game) · **Formulas:** 23 (see FORMULAS_nov08.md) · **Content:** 30 skills/statuses + 3 weapons · **Levels:** 1, 25, 50, 99, 150, 199, 250, 300
**Test units:** Human, median armor. Attackers put 60% of their stat points into STR (or INT for casters). Enemies split their points evenly, which is the DB enemy rule. At L99 an enemy turn lasts about 620 CT.
**Status:** everything here is built and source-checked, but not yet Studio-tested. I priced the rules as the DB describes them.
**What the numbers can't see:** the RT figures don't include AP, positioning or friendly fire, so I covered those separately in the notes below.

---

## VERDICT: 1 CRITICAL FINDING
**Dragon Dive (and Decimating Swing, to a lesser degree) with a Hammer can now almost freeze a group of enemies in place.**

---

## Verdict per item

| Item | Verdict | Why (L99 unless stated) |
|---|---|---|
| **Dragon Dive** (area riders) | **CHANGE** | With a Hammer it adds 182 RT of delay to every unit in its 5-tile cross. That is 29% of an enemy turn each, with no wait before it lands. One Dragoon hitting 3 clustered enemies twice a turn cuts their speed to 52%. Two Dragoons cut it to **4%**, close to a full lock, for about 3 turns until MP runs out. At L199+ it reaches **0%**. Before rule 252 only one target took the delay. |
| **Decimating Swing** (area riders) | **CHANGE (milder)** | With a Hammer: 195 RT per target, 3 targets. Two users cut enemy speed to 14%. Its 100 CT interruptible channel and 2H-only rule soften it a little. |
| Other 18 area skills under rule 252 | OK | Their delay multipliers are 0.75× or lower, which works out to 3–9% of an enemy turn per target. Friendly fire limits them. |
| **Gale Thrust** knockback | OK up to L99, **WATCH** above L150 | Against normal enemies the formula gives 0 tiles at L99 (1 tile with 60% STR, 2 with all-in STR). Above L150, STR builds push the whole cone 2–5 tiles. Hitting a wall then costs each target 16–78% of its max HP. |
| Shadow Rake, Sweeping Cut, Thunderclap, Voltaic Chain (pins the last target only), Chain Spark, Pyroclasm, Meteor Marker, Tidal Crash, Venom Burst, Fissure Line, Siphon Pulse, Miasma Cloud, Rainfall Zone, Mending Rain, Flash Freeze | OK | Small riders, already priced into their area discounts. |
| Blinding Flash | OK, **watch at L250+** | Blind lowers enemy damage by about 15% at L99. It grows with enemy DEX, to about 28% by L300. |
| Glacial Wave (freezes Wet targets only) | OK for this batch | It now freezes fewer targets than the old code did. *Side note:* Frozen itself costs one unit about 2.3 turns for a two-cast setup of about 300 CT. With Rain weather the setup is free. That's the status's own strength, not something this batch caused. |
| Bulwark Field / Consecrate (allies only) | OK | Shield is about 54 and heal about 62 per ally, roughly 10–12% of ally HP. |
| **Sanctify** (allies only, turn delay removed) | **WATCH** | It lost both of its downsides. For 1 AP and 24 MP it gives up to 5 units Blessed, which is about +24% damage for 2 turns, plus a 136 heal. |
| **Static Field / Movement Slow** | **Not overtuned. It's weak.** Optional buff | Each enemy on the ring loses only about 31 RT of turn delay plus about 24 RT of slowed walking, about 9% of a turn. It needs **3.2+ enemies** on the ring just to pay back its own time cost, and it hits allies too. Movement Slow never shortens how far a unit can move. |
| **Blood Price** | **WATCH + user ruling** | The HP cost works now (the old game had none). It deals 153 damage for 84 HP (15%), 57 RT and 0 MP. Power Strike deals 131 for 89 RT and 11 MP. Blood Price still does about **1.8× Power Strike's damage per RT**, and you can cast it 5 times before you're locked out. Refunds: Lifesteal 15, Vitality Surge 28, Blood Harvest 84 on a kill. |
| **Life Link** | OK, no loop | A runaway loop can't happen: shared healing isn't a new heal event, so it never shares again. Lifesteal through the link gives only about 26 HP per link. The link pays off over just casting Healing Light on the ally (365) only if the caster receives 2+ Healing Lights within 2000 CT. One watch item: several links on one tank turn Consecrate's 62 heal into 186. |
| **Pinned / rule 253** | OK | A pin lasts about 1.2 enemy turns, 0.9 for VIT builds. It gets shorter with level, down to 0.5–0.85 at L300. Ways out still exist: Blink, Phantom Exchange, an ally's swap or push, Purge. Leap melee simply lost its exception from pins. *Watch:* Net Launcher pins 5 units for 1 AP. Venus Man-Trap (not built) pins for as long as the plant stands. |
| **Lunge** (exactly range 2, step then hit) | OK. Not better or worse, just different | Damage and cost are unchanged. Old game: you could hit from range 2 twice and stay out of reach (192). New: Lunge + Power Strike = 227, against 131 for Move + Power Strike, but you end up adjacent. It's also refused if the middle tile is blocked, the height step is too big, or the caster is Pinned. *Watch:* Skyfall Lance (1.3×, range 3, ignores height) beats it on everything except cost. |
| Recoil Shot (hop after the shot) | OK | The free 1-tile hop only matters when you're right at the edge of an enemy's reach (5 tiles at L99, 8 by L300), so it's worth less at higher levels. |
| Dragon Dive cancel + refund | OK | No balance effect. The wait is 1 CT, so it will almost never trigger. |
| Walking height / corner limits on step and hop | OK | Same as normal walking. |

---

## Recommended number changes (you decide)

1. **Dragon Dive turn delay:** full ×1.40 on the landing tile only, ×0.50 on the 4 side tiles. That matches the existing "impact = 100% / side = 50%" item rule (project_rules 210). Or use a flat ×0.70 everywhere.
   *Result:* two Hammer Dragoons would leave enemies at about 52% speed instead of 4%.
   *Trade-off:* the Dragoon keeps its single-target control and loses the crowd lock.
2. **Decimating Swing:** ×1.50 on the main target, ×0.75 on the others.
   *Trade-off:* 2H users lose some crowd control. The damage is unchanged.
3. **Optional system-wide safety net:** cap how much turn delay a unit can receive between two of its own turns (example: 50% of its Base RT). The DB has no cap today. Only a minimum exists (project_rules 19). This would stop any future area-delay stacking.
   *Trade-off:* it adds a new rule, and heavy-delay weapons like Hammer, Claws and Whip get weaker against single targets too.
4. **Gale Thrust:** cap the knockback at 2 tiles.
   *Trade-off:* it only affects L150+ STR builds. Nothing changes at L99 or below.
5. **Static Field (optional buff):** make Movement Slow also cost **−1 Movement Range**, or raise the delay to round(40 + 0.20 × L).
   *Trade-off:* friendly fire also hits allies harder.
6. **Life Link:** veto agent default (f) and allow **one incoming link per ally**.
   *Trade-off:* this only stops stacking several links on one tank.

## Needs a user ruling
- **A. Blood Price range.** On 2026-10-22 you decided Blood Price should be **range 1, with no INT bonus**. The DB still says *"Fixed 3; add 100% inherited Bonus Skill Range"*, and the card says *"at range"*. Should the range-1 change be applied, or was it reversed?
- **B. Augment riders on area skills.** Does rule 252 also spread augment riders to everyone an area skill hits? Example: Pinning Support on Thunderclap would pin every unit within 3 tiles. The DB doesn't say. Recommendation: no, augment riders hit the main target only. The Tester should check what the code does.
- **C. Items 1–6 above.**

## Side notes (outside this batch, one line each)
- **Push collision damage grows without limit for STR builds.** Pushing a target into a stone wall costs it 31% of its max HP at L99, 95–244% at L199, and up to **466% at L300**, which is a one-shot. Worth its own review.
- **Pins and debuffs shrink with level.** VIT resistance keeps growing while the 1000 CT duration stays flat.

## Delta from the last skill audit (2026-10-21)
- **New:** the Dragon Dive / Decimating Swing crowd lock, the weak Static Field, Sanctify becoming pure upside, the multi-link pile-on, and question B.
- **Changed:** Blood Price now really pays its HP cost (it was free in the game before). Its damage lead is still there.
- **Not done:** the Blood Price range-1 decision (question A).

Files written: sim\balance_review_2026-11-08\ only (harness.py, FORMULAS_nov08.md, REPORT.md). Nothing in source\ or docs\ was touched.
