# CTRBLXAI Simulator — Formula Registry

**Last updated:** 2026-09-13
**Source:** `unit_progression` table, CTRBLXAI.db

## Implemented Formulas

| # | Formula | DB Table | Row(s) | DB Expression | Python Implementation | Match |
|---|---------|----------|--------|---------------|----------------------|-------|
| 1 | XP to next level | unit_progression | 47, 86 | `500 + (Level × 20)` | `500 + level * 20` | ✓ |
| 2 | Kill XP | unit_progression | 30 | `Base Type XP × (1 + Enemy Level / 50)` | `base_xp * (1 + enemy_level / 50)` | ✓ (DB rounds) |
| 3 | Grunt Base XP | unit_progression | 32 | `20` | `20` | ✓ |
| 4 | Veteran Base XP | unit_progression | 33 | `35` | `35` | ✓ |
| 5 | Elite Base XP | unit_progression | 34 | `60` | `60` | ✓ |
| 6 | Boss Base XP | unit_progression | 35 | `120` | `120` | ✓ |
| 7 | Battle XP | unit_progression | 50 | `sum of kill XP for each enemy defeated` | `sum(kill_xp(base, elvl) for each enemy)` | ✓ |
| 8 | Deployed share | unit_progression | 51 | `100%` | `1.0` | ✓ |
| 9 | Benched share | unit_progression | 52 | `50%` | `0.5` | ✓ |
| 10 | Human passive | unit_progression | 54 | `total XP × 1.10` | `total * 1.10` | ✓ |
| 11 | On-level (gap ≤5) | unit_progression | 55 | `×1.0` | `1.0` | ✓ |
| 12 | Gap 6-10 | unit_progression | 56 | `×0.75` | `0.75` | ✓ |
| 13 | Gap 11-15 | unit_progression | 57 | `×0.50` | `0.50` | ✓ |
| 14 | Gap 16-20 | unit_progression | 58 | `×0.25` | `0.25` | ✓ |
| 15 | Gap 21+ | unit_progression | 59 | `×0.10` | `0.10` | ✓ |
| 16 | Underleveled ≤-5 | unit_progression | 60 | `×1.25` | `1.25` | ✓ |
| 17 | Underleveled ≤-10 | unit_progression | 61 | `×1.50 (cap)` | `1.50` | ✓ |
| 18 | Level Gap direction | unit_progression | 62 | `Unit Level - Quest Recommended Level` | `unit_level - quest_level` | ✓ |

## Change Log

### 2026-09-13
- **CHANGED:** Formula #1 — XP to next level updated from flat-per-tier (T0=200, T1=500, T2=1000) to linear ramp `500 + (Level × 20)`. DB rows 43-45 removed; replaced by rows 47 and 86.
- **CHANGED:** Level cap scope narrowed to 99 (launch only). Evolution tiers (T1, T2) are post-launch features with formulas TBD from live data.

### 2026-09-12
- Initial registry created. 20 formulas from `unit_progression` table.

## Validation Notes

- DB reference values (rows 36-42) use rounding: Grunt L1 = 20 (formula gives 20.4), Elite L99 = 179 (formula gives 178.8). Sim uses exact floats; differences are <1 XP per kill.
- DB row 86 provides explicit reference values for the new ramp formula: L1→520, L10→700, L25→1000, L50→1500, L75→2000, L98→2460. All match.
- DB row 87 states total XP L1→99 ≈ 145,000. Computed: 146,020. Match (within stated approximation).
- No Luau source code was read to derive any formula.
- All formulas come exclusively from the `unit_progression` table.

## Not Yet Implemented (Not Needed for XP Sim)

- Procedural objective bonus ranges (rows 64-69) — percentages documented but exact generation logic is procedural, not formula-based
- Dispatch XP (rows 77-78) — "exact values pending" per DB
- Stat gain formula (row 49) — implemented in RaceData.CalcBaseStats, not needed for XP sim
