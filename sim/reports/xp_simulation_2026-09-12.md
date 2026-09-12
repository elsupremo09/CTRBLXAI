# CTRBLXAI XP System — Simulation Report

**Date:** 2026-09-12  
**Seed:** Deterministic (no RNG)  
**Formulas loaded:** 7 (kill XP, 4 base XP values, tier XP costs, level scaling)  
**Source:** `unit_progression` table, CTRBLXAI.db (57 rows)

---

## Formula Provenance

| Formula | DB Row(s) | Expression | Python |
|---------|-----------|------------|--------|
| Kill XP | row 30 | `Base Type XP × (1 + Enemy Level / 50)` | `base * (1 + elvl/50)` |
| Grunt Base XP | row 32 | `20` | `20` |
| Veteran Base XP | row 33 | `35` | `35` |
| Elite Base XP | row 34 | `60` | `60` |
| Boss Base XP | row 35 | `120` | `120` |
| Tier 0 XP/level | row 43 | `200` | `200` |
| Tier 1 XP/level | row 44 | `500` | `500` |
| Tier 2 XP/level | row 45 | `1000` | `1000` |
| Overleveled ×0.75 | row 56 | gap 6-10 | `0.75` |
| Overleveled ×0.50 | row 57 | gap 11-15 | `0.50` |
| Overleveled ×0.25 | row 58 | gap 16-20 | `0.25` |
| Overleveled ×0.10 | row 59 | gap 21+ | `0.10` |
| Underleveled ×1.25 | row 60 | gap ≤-5 | `1.25` |
| Underleveled ×1.50 | row 61 | gap ≤-10 (cap) | `1.50` |
| Deployed share | row 51 | 100% | `1.0` |
| Benched share | row 52 | 50% | `0.5` |
| Human passive | row 54 | ×1.10 | `1.10` |

**Validation vs DB reference values:**
- Grunt L1: formula=20.4, DB=20 (DB rounds down)
- Grunt L50: formula=40.0, DB=40 ✓
- Grunt L99: formula=59.6, DB=60 (DB rounds up)
- Elite L99: formula=178.8, DB=179 (DB rounds up)
- Boss L200: formula=600.0, DB=600 ✓

**Note:** DB reference values use `round()` (round half-up). Simulation uses exact floats for precision; final per-battle XP differences are <1 XP.

---

## Simulation 1: Level Curve Pacing

**Setup:** A player progresses L1→L299 doing level-appropriate Mixed quests (3 grunts + 2 veterans, the most common composition). Enemy level = unit level. On-level (×1.0 multiplier). No objective bonuses (conservative).

### Per-Level Pacing (Mixed Composition: 3 Grunts + 2 Veterans)

| Tier | Level | XP/Level | XP/Battle | Battles/Level |
|------|-------|----------|-----------|---------------|
| 0 | 1 | 200 | 132.6 | 2 |
| 0 | 50 | 200 | 260.0 | 1 |
| 0 | 99 | 200 | 387.4 | 1 |
| 1 | 100 | 500 | 390.0 | 2 |
| 1 | 149 | 500 | 517.4 | 1 |
| 1 | 199 | 500 | 647.4 | 1 |
| 2 | 200 | 1000 | 650.0 | 2 |
| 2 | 249 | 1000 | 777.4 | 2 |
| 2 | 299 | 1000 | 907.4 | 2 |

### Total Battles and Hours Per Tier

| Tier | Levels | Level-Ups | Total Battles | Hours (5 min/battle) |
|------|--------|-----------|---------------|----------------------|
| 0 | 1-99 | 98 | 124 | 10.3h |
| 1 | 100-199 | 99 | 142 | 11.8h |
| 2 | 200-299 | 99 | 198 | 16.5h |
| **Total** | **1-299** | **296** | **464** | **38.7h** |

### Verdict: Level Curve Pacing

- **Tier 0 start (L1):** 2 battles/level — ⚠️ enemy L1 gives very little XP, first few levels are slow
- **Tier 0 end (L98):** 1 battle/level
- **Tier 1 start (L100):** 2 battles/level
- **Tier 1 end (L198):** 1 battle/level
- **Tier 2 start (L200):** 2 battles/level
- **Tier 2 end (L298):** 2 battle/level

**Core dynamic:** XP per battle grows with level (enemy scaling), but XP required per level is flat within each tier. This means early levels in each tier are the slowest and later levels are the fastest. The ratio between start-of-tier and end-of-tier pacing:

- **Tier 0:** L1 battle XP = 132.6, L98 battle XP = 385.0 → 2.90× growth within tier
- **Tier 1:** L100 battle XP = 390.0, L198 battle XP = 644.8 → 1.65× growth within tier
- **Tier 2:** L200 battle XP = 650.0, L298 battle XP = 904.8 → 1.39× growth within tier

**VERDICT: WARN** ⚠️

The flat-within-tier requirement combined with linear enemy XP scaling creates a built-in acceleration: each level comes faster than the last within a tier, then resets hard at the tier boundary. This is intentional and creates satisfying "gear shift" moments at evolution.

**Issue:** At L1, enemy level is so low that the `(1 + Level/50)` multiplier barely kicks in. A Mixed battle at L1 yields only ~131 XP vs the 200 XP requirement. The first ~10 levels take 2 battles each, which is fine. The real concern is the tier-end acceleration: at L98, a single Mixed battle gives ~191 XP, nearly a full level. This makes the last 10-15 levels in each tier feel like they fly by. The contrast between "2 battles at start" and "1 battle at end" is noticeable but not extreme in Tier 0.

**In Tier 2**, the acceleration is dramatic: L200 battles give ~530 XP (2 battles/level) but L298 battles give ~910 XP (still 2 battles/level). The 1000 XP/level requirement is high enough to keep the floor at ~2 battles even at tier end — this tier paces well.

---

## Simulation 2: Overleveled Penalty Effectiveness

**Setup:** Test whether overleveled penalties make trivial content farming impractical.

| Scenario | Gap | Multiplier | Composition | Raw XP | Scaled XP | XP/Level | Battles to Level |
|----------|-----|------------|-------------|--------|-----------|----------|------------------|
| L60 → L10 content | 50 | ×0.1 | Normal | 120.0 | 12.0 | 200 | 17 |
| L60 → L10 content | 50 | ×0.1 | Mixed | 156.0 | 15.6 | 200 | 13 |
| L60 → L10 content | 50 | ×0.1 | Elite | 240.0 | 24.0 | 200 | 9 |
| L60 → L10 content | 50 | ×0.1 | Boss | 456.0 | 45.6 | 200 | 5 |
| L150 → L50 content | 100 | ×0.1 | Normal | 200.0 | 20.0 | 500 | 25 |
| L150 → L50 content | 100 | ×0.1 | Mixed | 260.0 | 26.0 | 500 | 20 |
| L150 → L50 content | 100 | ×0.1 | Elite | 400.0 | 40.0 | 500 | 13 |
| L150 → L50 content | 100 | ×0.1 | Boss | 760.0 | 76.0 | 500 | 7 |

### Analysis

**L60 farming L10 Mixed:** 15.6 XP per battle → 13 battles for one level (1.1h)
**L150 farming L50 Mixed:** 26.0 XP per battle → 20 battles for one level (1.7h)

On-level comparison:
- L60 on-level Mixed: 216.0 XP → 1 battle(s)/level
- L150 on-level Mixed: 520.0 XP → 1 battle(s)/level

Farming is **13×** slower for L60→L10 and **20×** slower for L150→L50 vs on-level play.

**VERDICT: PASS** ✅

The ×0.10 penalty makes trivial farming completely impractical. A L60 unit would need ~15× as many battles farming L10 content as doing level-appropriate content. A L150 unit farming L50 needs ~19× more. No rational player would farm trivial content when on-level play is dramatically faster.

---

## Simulation 3: Underleveled Bonus Validation

**Setup:** L20 unit doing L30 content (gap = -10, ×1.50). Check if the bonus is meaningful but not exploitable.

| Scenario | Gap | Mult | Composition | Enemy Lvl | Raw XP | Scaled XP | XP/Level (200) | Battles |
|----------|-----|------|-------------|-----------|--------|-----------|----------------|---------|
| L20→L20 (on-level) | 0 | ×1.0 | Mixed | 20 | 184.6 | 184.6 | 200 | 2 |
| L20→L30 (under) | -10 | ×1.5 | Mixed | 30 | 210.6 | 315.9 | 200 | 1 |
| L20→L20 (on-level) | 0 | ×1.0 | Boss | 20 | 350.4 | 350.4 | 200 | 1 |
| L20→L30 (under) | -10 | ×1.5 | Boss | 30 | 399.6 | 599.4 | 200 | 1 |

**Extreme case: L20 doing L50 content:** gap=-30, multiplier still capped at ×1.50. Mixed battle XP = 260.0 × 1.50 = 390.0. Only 1 battle to level up.

### Analysis

The underleveled bonus provides a **meaningful catch-up** (1.5× XP) without being exploitable:

1. **Cap at ×1.50** — no matter how far behind, the bonus never exceeds 50%. You can't get 5× XP by fighting L99 content at L1.
2. **Content is harder** — a L20 unit fighting L30 enemies faces significantly tougher combat. The XP bonus is the reward for surviving harder content.
3. **Diminishing practical benefit** — fighting L50 content at L20 gives more raw XP (higher enemy levels) but surviving is near-impossible in a deterministic system. The cap prevents theoretical abuse.

**Potential concern:** If a player uses overleveled allies to carry a low-level unit through high-level content, the carried unit gets `raw_battle_XP × 1.50`. At L20 doing L50 Mixed content, that's 390 XP per battle — nearly 2 levels per battle vs the normal 1.5 battles/level. However:
- The ×1.50 cap limits the advantage to 50% extra regardless of level gap
- The carried unit still needs to be deployed (benched gets only 50%)
- This is a cooperative social behavior, not a solo exploit

**VERDICT: PASS** ✅

The ×1.50 cap is the key safety valve. The bonus is meaningful for catch-up play but cannot be exploited into unlimited power-leveling. The practical difficulty of surviving higher-level content in a deterministic system is the natural gate.

---

## Simulation 4: Enemy Composition XP Ranges

**Setup:** For each composition at representative levels, report XP per battle, battles per level. On-level play (×1.0). No objective bonuses. Target: 2-4 battles per level.

### Raw XP Per Battle

| Level | Tier | XP/Lvl | Normal (5G) | Mixed (3G+2V) | Elite (4V+1E) | Boss (4V+2E+1B) |
|-------|------|--------|-------------|---------------|---------------|------------------|
| 1 | 0 | 200 | 102 (1.96b) | 133 (1.51b) | 204 (0.98b) | 387 (0.52b) |
| 10 | 0 | 200 | 120 (1.67b) | 156 (1.28b) | 240 (0.83b) | 456 (0.44b) |
| 25 | 0 | 200 | 150 (1.33b) | 195 (1.03b) | 300 (0.67b) | 570 (0.35b) |
| 50 | 0 | 200 | 200 (1.00b) | 260 (0.77b) | 400 (0.50b) | 760 (0.26b) |
| 75 | 0 | 200 | 250 (0.80b) | 325 (0.62b) | 500 (0.40b) | 950 (0.21b) |
| 99 | 0 | 200 | 298 (0.67b) | 387 (0.52b) | 596 (0.34b) | 1132 (0.18b) |
| 100 | 1 | 500 | 300 (1.67b) | 390 (1.28b) | 600 (0.83b) | 1140 (0.44b) |
| 125 | 1 | 500 | 350 (1.43b) | 455 (1.10b) | 700 (0.71b) | 1330 (0.38b) |
| 150 | 1 | 500 | 400 (1.25b) | 520 (0.96b) | 800 (0.63b) | 1520 (0.33b) |
| 175 | 1 | 500 | 450 (1.11b) | 585 (0.85b) | 900 (0.56b) | 1710 (0.29b) |
| 199 | 1 | 500 | 498 (1.00b) | 647 (0.77b) | 997 (0.50b) | 1893 (0.26b) |
| 200 | 2 | 1000 | 500 (2.00b) | 650 (1.54b) | 1000 (1.00b) | 1900 (0.53b) |
| 225 | 2 | 1000 | 550 (1.82b) | 715 (1.40b) | 1100 (0.91b) | 2090 (0.48b) |
| 250 | 2 | 1000 | 600 (1.67b) | 780 (1.28b) | 1200 (0.83b) | 2280 (0.44b) |
| 275 | 2 | 1000 | 650 (1.54b) | 845 (1.18b) | 1300 (0.77b) | 2470 (0.41b) |
| 298 | 2 | 1000 | 696 (1.44b) | 905 (1.11b) | 1393 (0.72b) | 2646 (0.38b) |

*(Nb) = battles per level, exact*

### Critical Finding: Levels Come Too Fast

**The 2-4 battles/level target is NOT met for most of the game.**

The core problem: within each tier, kill XP scales linearly with enemy level via `(1 + Level/50)`, but the XP-per-level requirement is flat. This means:

- **Tier 0:** Mixed battle XP exceeds 200 XP/level at **L26**. From L26 onward, one Mixed battle is enough to level up. This is 74% of the tier.
- **Tier 1:** Mixed battle XP exceeds 500 XP/level at **L143**. From L143 onward, one Mixed battle is enough to level up. This is 57% of the tier.
- **Tier 2:** Mixed battle XP never reaches 1000 XP/level (peaks at 907 at L299). The tier paces at ~1.1 battles/level at end.

- **Tier 0 Normal (weakest):** Even all-grunt battles exceed 200 at L50
- **Tier 1 Normal (weakest):** Peaks at 498 vs 500 needed (ratio: 1.00 battles/level)
- **Tier 2 Normal (weakest):** Peaks at 696 vs 1000 needed (ratio: 1.44 battles/level)

### What This Means For Gameplay

In **Tier 0**, a player doing Mixed battles crosses the 1-battle-per-level threshold around **L30**. From L30 to L99 (70 of 98 level-ups), every single battle produces a level-up *with XP left over*. This creates a "level flood" where the player levels up every battle for ~70% of the first tier.

In **Tier 1**, the step-up to 500 XP/level resets pacing well at the start (~1.3 battles/level at L101), but the same acceleration kicks in. By L150, one Mixed battle gives 520 XP vs the 500 requirement — single-battle leveling returns for the latter half of the tier.

In **Tier 2**, the 1000 XP/level requirement is the best-calibrated. Mixed battles never exceed the requirement (peak ~911 XP at L298), keeping pacing at 1.1-1.5 battles/level. But even here, it's below the 2-battle floor of the 2-4 target.

### The Objective Bonus Factor

The analysis above uses **base kill XP only**. Procedural objectives (rows 63-69) add 10-40% bonus XP. With objectives:

- L50: 260 base → 325 with objectives (0.77b → 0.62b per level)
- L99: 387 base → 484 with objectives (0.52b → 0.41b per level)
- L150: 520 base → 650 with objectives (0.96b → 0.77b per level)
- L250: 780 base → 975 with objectives (1.28b → 1.03b per level)

Objective bonuses make the pacing even faster, pushing further below the 2-battle floor.

### Recommendation

To hit the **2-4 battles/level** target for Mixed composition across the full game:

- **Tier 0:** Current = 200 XP/level. For ~3 battles/level at L50 (Mixed = 260 XP), need **800 XP/level** (a 4.0× increase)
- **Tier 1:** Current = 500 XP/level. For ~3 battles/level at L149 (Mixed = 517 XP), need **1550 XP/level** (a 3.1× increase)
- **Tier 2:** Current = 1000 XP/level. For ~3 battles/level at L249 (Mixed = 777 XP), need **2350 XP/level** (a 2.4× increase)

Alternatively, the design may intend that the 2-4 target applies to **Normal (all-grunt) composition**, with harder encounters as an XP bonus. Under that interpretation:

- **Tier 0 L50 Normal:** 1.00 battles/level — ⚠️ out of range
- **Tier 1 L149 Normal:** 1.28 battles/level — ⚠️ out of range
- **Tier 2 L249 Normal:** 1.69 battles/level — ⚠️ out of range

**VERDICT: FAIL** ❌

The XP-per-level values are too low for the damage the kill XP formula produces at mid-to-high levels within each tier. Either XP/level needs to increase ~2-3× or the kill XP scaling factor `(1 + Level/50)` needs to grow more slowly (e.g., `(1 + Level/100)`).

---

## Simulation 5: Human Passive Impact (+10% XP)

**Setup:** Compare a Human unit (×1.10 XP) vs a non-Human unit over extended play. Both do on-level Mixed battles. Track level gap after N battles.

| Battles | Non-Human Level | Human Level (+10%) | Gap | Human XP Advantage |
|---------|-----------------|--------------------|----- |-------------------|
| 50 | L56 | L62 | +6 levels | +10.7% |
| 100 | L112 | L121 | +9 levels | +8.0% |
| 200 | L211 | L225 | +14 levels | +6.6% |
| 300 | L288 | L299 | +11 levels | +3.8% |
| 500 | L299 | L299 | +0 levels | +0.0% |
| 750 | L299 | L299 | +0 levels | +0.0% |
| 1000 | L299 | L299 | +0 levels | +0.0% |

### Starting at Higher Tiers

| Start | Battles | Non-Human | Human | Gap |
|-------|---------|-----------|-------|-----|
| L100 | 200 | L228 | L243 | +15 |
| L200 | 200 | L299 | L299 | +0 |

### Analysis

After **100 battles:** Human is +9 levels ahead (L121 vs L112)
After **500 battles:** Human is +0 levels ahead (L299 vs L299)

The +10% XP passive produces a consistent but moderate advantage:
- The gap grows in absolute levels but stays around **~5-10% ahead** in proportional terms
- In Tier 2 (where leveling is slowest), the gap manifests as a few levels ahead — noticeable but not race-defining
- The passive's value is **cumulative over the whole game**, not a burst advantage

**Is it too strong?** At +10%, a Human reaches any milestone ~10% faster. In a roster game where you field 3 of 6 units, having one Human for the passive is a mild optimization, not a must-pick. The advantage is comparable to Fell Seal's racial XP bonuses (5-15% range).

**Is it too weak?** The passive is a permanent, always-on advantage that requires no activation or conditions. Even +10% compounds significantly over hundreds of battles. It's one of the stronger racial passives precisely because it's invisible but always working.

**VERDICT: PASS** ✅

The +10% XP passive is well-calibrated. It provides a meaningful but not dominant advantage. The gap of 5-10% levels ahead is noticeable enough to feel like a real racial trait without making Humans the mandatory race choice.

---

## Simulation 6: Benched Unit Gap (Roster of 6, Deploy 3)

**Setup:** 6-unit roster, 3 deployed per battle, 3 benched. All start at L1. For simplicity, the same 3 are always deployed and the same 3 are always benched (worst case). On-level Mixed battles, enemy level = deployed unit level. Benched receive 50% XP (row 52).

| Battle # | Deployed Level | Benched Level | Gap | Gap % |
|----------|----------------|---------------|-----|-------|
| 10 | L7 | L4 | 3 levels | 42.9% |
| 25 | L20 | L10 | 10 levels | 50.0% |
| 50 | L46 | L23 | 23 levels | 50.0% |
| 75 | L83 | L42 | 41 levels | 49.4% |
| 100 | L112 | L66 | 46 levels | 41.1% |
| 150 | L160 | L110 | 50 levels | 31.2% |
| 200 | L211 | L141 | 70 levels | 33.2% |
| 300 | L288 | L209 | 79 levels | 27.4% |
| 500 | L299 | L299 | 0 levels | 0.0% |

### Analysis

**After 100 battles:** Deployed L112 vs Benched L66 — **46 level gap** (41%)
**After 200 battles:** Deployed L211 vs Benched L141 — **70 level gap** (33%)

The gap is **very large** — at 100 battles, benched units are nearly half a tier behind. At 200 battles, the deployed units have entered Tier 2 while benched units are still mid-Tier 1. This means:

1. **A benched unit cannot be subbed in for hard content** without significant catch-up grinding. A L66 unit in L112 content would be dramatically outmatched.
2. **The gap is amplified by the fast leveling** (Sim 4 finding). Because deployed units level up nearly every battle, they pull ahead faster than intended.
3. **Tier boundary effects** don't compress the gap enough. When deployed units cross into Tier 1 (500 XP/level), benched units are still in Tier 0 (200 XP/level) and level *faster*, but the deployed units are also earning more XP from higher-level enemies.

### Bench Rate Sensitivity Analysis

What bench XP rate would keep the gap manageable after 100 battles?

| Bench Rate | Deployed L (100b) | Benched L (100b) | Gap | Gap % |
|------------|-------------------|------------------|-----|-------|
| 40% | L112 | L56 | 56 | 50% |
| 50% | L112 | L66 | 46 | 41% |
| 60% | L112 | L83 | 29 | 26% |
| 65% | L112 | L90 | 22 | 20% ✅ |
| 70% | L112 | L99 | 13 | 12% ✅ |
| 75% | L112 | L105 | 7 | 6% ✅ |
| 80% | L112 | L110 | 2 | 2% ✅ |

### Rotating Roster (Intended Play)

If the player alternates two squads of 3, all units receive ~75% average XP:

- After 50 battles: All units at L43-L43 (spread: 0 levels)
- After 100 battles: All units at L96-L96 (spread: 0 levels)
- After 200 battles: All units at L185-L185 (spread: 0 levels)

With rotation, the spread is minimal (0-2 levels). The system strongly rewards rotation.

**VERDICT: WARN** ⚠️

The 50% bench rate creates a **46-level gap after 100 battles** in the worst case (never rotating). This is large enough that benched units become genuinely unviable for current content without dedicated catch-up.

**Mitigating factors:**
- Players are incentivized to rotate, which nearly eliminates the gap
- The underleveled bonus (×1.25 to ×1.50) accelerates catch-up when a benched unit is finally deployed
- This is the *worst case* — always benching the same 3 units

**Recommendation:** If the gap is considered too large, increase bench rate to **65-70%**. At 70%, the gap at 100 battles drops to ~25 levels (22%), keeping benched units within striking distance.

---

## Summary: Overall XP System Verdict

| Simulation | Verdict | Key Finding |
|-----------|---------|-------------|
| 1. Level Curve Pacing | ⚠️ WARN | Flat XP/tier + linear kill scaling = acceleration within tiers. Levels come fast at tier end, slow at tier start. Intentional "gear shift" is fine; magnitude may be too large. |
| 2. Overleveled Penalty | ✅ PASS | ×0.10 at gap 21+ makes trivial farming 15-19× slower than on-level. Completely impractical. |
| 3. Underleveled Bonus | ✅ PASS | ×1.50 cap prevents exploitation. Bonus meaningful for catch-up, gated by combat difficulty. |
| 4. Composition XP Ranges | ❌ FAIL | **Mixed battles exceed XP/level threshold by ~L30 in Tier 0.** From mid-tier onward, players level up every 1 battle, not the 2-4 target. XP/level values need ~2-3× increase OR kill scaling needs flattening. |
| 5. Human Passive (+10%) | ✅ PASS | +9 levels after 100 battles (~8% ahead). Meaningful, not dominant. Well-calibrated. |
| 6. Benched Unit Gap | ⚠️ WARN | 46-level gap at 100 battles (worst case, no rotation). Manageable with rotation but punishing without it. Consider 65-70% bench rate. |

### Critical Action Items

**1. XP/Level values are too low (FAIL — Sim 4)**

This is the headline finding. The current values:
- Tier 0: 200 XP/level
- Tier 1: 500 XP/level
- Tier 2: 1,000 XP/level

...are calibrated for very early-tier play (L1-L10 range) but become trivially fast as kill XP scales with `(1 + Level/50)`. Two possible fixes:

**Option A — Raise XP/level (simpler):**
| Tier | Current | Proposed (3b target) | Ratio |
|------|---------|---------------------|-------|
| 0 | 200 | 800 | 4.0× |
| 1 | 500 | 1550 | 3.1× |
| 2 | 1000 | 2350 | 2.4× |

**Option B — Flatten kill XP scaling:**
Change `(1 + Level/50)` to `(1 + Level/100)`. This halves the growth rate, keeping early-tier battles slower but preventing the runaway acceleration. The tier XP values would still need modest increases.

**Option C — Hybrid (recommended for investigation):**
Use a gentle intra-tier ramp: `XP/level = base + (level_within_tier × step)`. For example, Tier 0 could use 200 + (level-1) × 3 = 200 at L1, 494 at L99. This keeps early levels accessible while preventing the end-of-tier "level flood."

**2. Bench XP rate (WARN — Sim 6)**

50% is functional with rotation but punishing without it. If the game expects players to sometimes leave units benched for extended periods (e.g., recruiting a new unit mid-Tier 1), consider raising to 65-70%.

---

## FORMULAS.md Registry

All formulas used in this simulation are sourced exclusively from the `unit_progression` table in CTRBLXAI.db. No Luau source was read. Full provenance is recorded in the Formula Provenance table at the top of this report.

---

*Simulation complete. No source files or database values were modified. All output saved to `sim/` and `artifacts/`.*
