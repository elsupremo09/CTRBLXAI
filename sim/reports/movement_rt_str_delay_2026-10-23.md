# SIMULATION RUN — 2026-10-23
**Seed:** `movement_rt_str_delay_2026-10-23` (fully deterministic — no RNG used)
**Formulas loaded:** 10 (all from CTRBLXAI.db; see FORMULAS.md)
**Content entries simulated:** 38 weapon archetypes; AGI 10–300; STR 10–600; weapon levels 1–300
**Level/stat bands tested:** AGI {10,25,50,99,150,199,250,300}; STR {10,30,60,120,200,300,600}; weapon levels {1,25,50,99,150,199,250,300}
**Scope:** validation of the 3 movement/RT wiring fixes only. Source-verified reimplementation; Studio runtime still pending.

---

## --- SECTION 1: BLOCKERS ---
None. Every formula needed (Movement RT, STR Effective-WT, Basic Attack RT, Modified Base RT, STR RT-Delay Bonus, VIT RT-Delay Resistance, weapon-level scaling, Rest RT) is present in CTRBLXAI.db with clean provenance.

---

## --- SECTION 2: CRITICAL FINDINGS ---

### CRITICAL-1 — Movement is now cheaper than attacking at EVERY level band; the fix overcorrected the tempo gap it was meant to close.
- **Finding:** A 2-AP walk-walk turn now recurs ~20% sooner than a Sword attack-attack turn and ~38% sooner than a Greatsword turn, across all AGI bands.
- **Evidence (MBRT 400, STR 30):**
  - Move+Move full-range turn-cycle RT: **468** (AGI 10, 3 tiles) → **476** (AGI 300, 8 tiles).
  - Attack+Attack cycle: Sword **584**, Greatsword **767**.
  - A single full-range move adds only **29–38 RT** vs **92 RT** for one Sword basic attack — a full move costs roughly **½ of a single basic attack**.
  - The old 0.0625/no-AGI model gave a walk-walk cycle of 550–800 RT (which lapped attackers hard — the original 2026-09-30 complaint). The new model swings the other way: walkers now lap attackers instead.
- **Level band where it appears:** All. The effect is slightly *stronger* at high AGI (more tiles covered for the same ~9% of a turn).
- **Affected content:** All units; most punishing for heavy-weapon (high-WT) archetypes, whose attack cycles are longest while their move cost is identical per tile.
- **Severity rationale:** This is the exact failure mode the fix targeted, now inverted. A kiting/repositioning unit gets extra turns relative to a committed attacker. It is not an unbounded loop (movement never floors to 0 — min 5 RT/tile at AGI 300), so it is a tuning break, not a game-breaker — but it is a direct curve inversion of the design goal. **Designer should rule on the target ratio (see Section 3).**

> No unbounded loops, no effective immunity, no zero-cost actions found. Movement RT and RT-delay both stay finite and bounded across all tested bands.

---

## --- SECTION 3: CURVE ANALYSIS ---

### (a) NEW Movement RT — MBRT 400, unarmored
| AGI | 1t | 2t | 3t | 4t | 5t | 6t | MoveRange | Full-move cost (% of 400 turn) |
|----:|---:|---:|---:|---:|---:|---:|:---------:|:------------------------------:|
| 10  | 11 | 23 | 34 | 46 | 57 | 69 | 3 | 34 RT (8.5%) |
| 25  | 11 | 21 | 32 | 43 | 53 | 64 | 3 | 32 RT (8.0%) |
| 50  | 10 | 19 | 29 | 38 | 48 | 58 | 3 | 29 RT (7.2%) |
| 99  |  8 | 16 | 24 | 32 | 40 | 48 | 4 | 32 RT (8.0%) |
| 150 |  7 | 14 | 21 | 27 | 34 | 41 | 5 | 34 RT (8.5%) |
| 199 |  6 | 12 | 18 | 24 | 30 | 36 | 6 | 36 RT (9.0%) |
| 250 |  5 | 11 | 16 | 21 | 27 | 32 | 7 | 37 RT (9.2%) |
| 300 |  5 | 10 | 14 | 19 | 24 | 29 | 8 | 38 RT (9.5%) |

**Curve note — a self-cancelling interaction worth flagging:** AGI *lowers* per-tile cost AND *raises* Movement Range (3 + floor(AGI/60)). The two nearly cancel: the cost to walk your *entire* range is almost flat (**~29–38 RT, 7–9.5% of a turn**) from AGI 10 to 300. This is actually healthy — high-AGI units cover more ground but don't get their full move for free. It does mean AGI's movement-RT discount is "spent" on reaching farther, not on acting sooner.

### (a) OLD vs NEW per-tile (MBRT 400)
| tiles | OLD/tile | NEW @AGI10 | NEW @AGI99 | NEW @AGI300 |
|------:|---------:|-----------:|-----------:|------------:|
| 1 | 25 | 11 | 8 | 5 |
| 3 | 75 | 34 | 24 | 14 |
| 6 | 150 | 69 | 48 | 29 |

The fix roughly **halves** base per-tile cost (25→12 at MBRT 400 before AGI), then AGI shaves a further 5–60% on top.

### (a) Armor-raised MBRT (armor raw WT 60, STR 60 → eff 46.2, MBRT 446)
Full-move cost stays ~7–10% of that unit's (larger) turn — armor correctly makes movement cost more in absolute RT but the *fraction of a turn* is unchanged. No break here. Heavy armor does **not** make movement disproportionately punishing.

### (b) STR RT-Delay Bonus multiplier
| STR | multiplier | note |
|----:|:----------:|------|
| 10 | 1.048 | |
| 30 | 1.130 | |
| 60 | 1.231 | |
| 120 | 1.375 | |
| 200 | 1.500 | |
| 300 | 1.600 | |
| 600 | **1.750** | cap (0.75) reached exactly at STR 600 |
| 1000 | 1.750 | capped |

Smooth, diminishing, well-behaved. The +0.75 cap binds only at STR 600 — reachable only deep into post-evolution bands (150+). For the design anchor (L99, typical STR 60–120) the bonus is a modest **+23% to +38%** to inflicted delay.

### (b) Inflicted RT Delay scales on TWO axes (STR × weapon level)
Hammer (L99 base delay 110), STR 120:
| WpnLvl | scale | scaled base | inflicted | % of 400 turn |
|-------:|:-----:|:-----------:|:---------:|:-------------:|
| 1 | 0.30 | 33 | 45 | 11% |
| 99 | 1.00 | 110 | 151 | 38% |
| 199 | 1.33 | 146 | 201 | 50% |
| 300 | 1.59 | 175 | 241 | 60% |

STR and weapon-level scaling **compound**. At L99 the STR buff is a reasonable tempo lever; by L250–300 a high-delay weapon with high STR pushes toward shifting a target half-to-most of a turn (see Section 2/Outliers). Curve accelerates with level but does not invert.

---

## --- SECTION 4: OUTLIERS ---

| Entry | Classification | Dimensions Won | Dimensions Lost | Evidence |
|---|---|---|---|---|
| **Movement (any unit)** | **DOMINANT (tempo)** | Fastest turn-recurrence of any 2-AP action | Deals no damage | Walk-walk cycle 464–476 RT vs Sword 584 / GS 767 — mover laps attackers |
| **Claws + Stagger (high STR, high lvl)** | **DOMINANT (control, high band only)** | Highest single-hit inflicted RT delay | Low damage, needs STR 600 + L250+ | 353 RT inflicted @ L250 (88% of a turn); 383 @ L300 (96%) before VIT |
| **Hammer / Chains (STR build)** | NICHE (healthy) | Strong single-target tempo denial | Slow, heavy | +45–61 RT added by STR at L99 vs VIT-0 target — meaningful but not oppressive |
| **Blowgun / zero-delay weapons** | unaffected | — | STR buff does nothing (base delay 0) | STR change is correctly inert where Base RT Delay = 0 |

---

## --- SECTION 5: COMBINATIONS ---

- **Max single-hit inflicted RT Delay (curve-break probe):** Claws (base 110) × Stagger passive (×1.25) × STR cap (×1.75) × weapon-level scale.
  - L99: 241 RT (60% of a 400 turn)
  - L150: 284 RT (71%)
  - L250: 353 RT (88%)
  - L300: 383 RT (96%)
  - Against a VIT-0 target this nearly denies a full turn in one hit at the highest bands. **Bounded** (never exceeds a full turn in tested range; project_rules id 19 floors target RT at 0 and base delay at −150). VIT 300 halves it to ~44% of a turn.
- **Cheapest movement (near-free probe):** AGI 300 = 5 RT/tile (1.2% of a turn); full 8-tile move = 38 RT (9.5%). **Movement never approaches zero** — the (1 − AGI/(200+AGI)) term asymptotes, it does not collapse. No free-movement exploit.
- **Fastest action rate:** Move+Move (464 RT cycle) is the fastest repeatable 2-AP turn in the game under the new numbers — faster than any attack cycle. This is the Section-2 finding stated as a combination result.

---

## --- SECTION 6: HEALTHY (don't spend time here) ---
- **STR RT-Delay Bonus shape** — smooth diminishing returns, sensible cap at STR 600, modest at the L99 anchor. Well-designed lever.
- **AGI self-cancellation on movement** — per-tile discount vs range gain net to a near-flat full-move fraction (7–9.5%). Elegant; no action needed.
- **Armor interaction with movement RT** — scales proportionally; heavy units pay more absolute RT but the same fraction of their (longer) turn. No break.
- **Zero-delay weapons** correctly receive no STR benefit.
- **VIT RT-Delay Resistance** correctly tempers the new STR delay (halves it at VIT 300), giving defenders a counter-lever.

---

## --- SECTION 7: DELTA (vs prior movement model) ---
- **Resolved:** The 2026-09-30 complaint (walking at 0.0625 lapped double-attackers) — the raw per-tile cost is now ~half, so the *old* over-cost is gone.
- **New:** The correction **overshot** — walking is now cheaper than attacking at every band (CRITICAL-1). AGI now actively discounts movement RT (was inert) and now compounds with Movement Range gains.
- **New:** STR now amplifies inflicted RT delay (was inert); compounds with weapon-level scaling; cap binds at STR 600.
- **Unchanged:** Movement remains bounded (no free move); RT delay remains bounded (floors per project_rules id 19).
- **Values changed in DB since last run:** movement_targeting id 8 (per-tile 0.0375→0.03 + AGI term added); core_stats id 2 (STR RT-Delay Bonus term added). Both confirmed read this run.

---

## --- VERDICT ---
**2 CRITICAL FINDINGS** — highest priority: **movement now out-tempos attacking at every level band (the fix overcorrected; a walk-walk turn recurs ~20–38% sooner than an attack turn).** Second: high-STR + high-delay + high-level combos push single-hit RT delay toward a near-full-turn denial by L250–300 (bounded, VIT-counterable, lower urgency).

**Designer decisions requested:**
1. Target ratio for move-vs-attack tempo. Current full-move adds ~½ of one basic attack's RT. If the intent is "movement should cost *somewhat less* but not out-tempo attacking," the per-tile factor likely wants to land between the old 0.0625 and the new 0.03 — simulation suggests **~0.045–0.05** would make a walk-walk cycle roughly match a Sword attack cycle. (I do not change values — this is a reference point only.)
2. Whether to cap compounded RT-delay (STR × weapon-level × Stagger) at high bands, or accept 88–96%-of-a-turn single-hit denial at L250–300 as intended for a pure-control weapon.

**Files modified:** `sim\FORMULAS.md`, `sim\reports\movement_rt_str_delay_2026-10-23.md` only. Source and docs untouched. Source-verified; Studio runtime pending.
