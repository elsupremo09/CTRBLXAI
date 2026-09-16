# CTRBLXAI Simulator — Formula Registry

**Last updated:** 2026-09-16
**Source:** `economy_framework`, `materials_system`, `consumable_framework`, `unit_progression`, `loot_progression` tables, CTRBLXAI.db

## Implemented Formulas — Economy Simulation

| # | Formula | DB Table | Row(s) | DB Expression | Python Implementation | Match |
|---|---------|----------|--------|---------------|----------------------|-------|
| 1 | XP to next level | unit_progression | 47, 86 | `500 + (Level × 20)` | `500 + level * 20` | ✓ |
| 2 | Kill XP | unit_progression | 30 | `Base Type XP × (1 + Enemy Level / 50)` | `base_xp * (1 + enemy_level / 50)` | ✓ |
| 3 | Grunt Base XP | unit_progression | 32 | `20` | `20` | ✓ |
| 4 | Veteran Base XP | unit_progression | 33 | `35` | `35` | ✓ |
| 5 | Elite Base XP | unit_progression | 34 | `60` | `60` | ✓ |
| 6 | Boss Base XP | unit_progression | 35 | `120` | `120` | ✓ |
| 7 | Kill Gold | economy_framework | 2 | `Base Gold × (1 + Enemy Level / 100)` | `base_gold * (1 + enemy_level / 100)` | ✓ |
| 8 | Grunt Base Gold | economy_framework | 3 | `8` | `8` | ✓ |
| 9 | Veteran Base Gold | economy_framework | 4 | `14` | `14` | ✓ |
| 10 | Elite Base Gold | economy_framework | 5 | `25` | `25` | ✓ |
| 11 | Boss Base Gold | economy_framework | 6 | `50` | `50` | ✓ |
| 12 | Battle Completion Gold | economy_framework | 8 | `Base × (1 + Map Level / 50)` | `base * (1 + map_level / 50)` | ✓ |
| 13 | Completion Bases | economy_framework | 8 | `Normal=30, Elite=50, Boss=100` | `{"Normal": 30, "Elite": 50, "Boss": 100}` | ✓ |
| 14 | Quest Reward Gold | economy_framework | 9 | `Base × (1 + Recommended Level / 40)` | `base * (1 + rec_level / 40)` | ✓ |
| 15 | Quest Bases | economy_framework | 9 | `Normal=50, Elite=80, Boss=150` | `{"Normal": 50, "Elite": 80, "Boss": 150}` | ✓ |
| 16 | Overleveled Gold Penalty | economy_framework | 7 | `gap ≤5 ×1.0, 6-10 ×0.75, 11-15 ×0.50, 16-20 ×0.25, 21+ ×0.10` | same bands | ✓ |
| 17 | Base Value by Slot | economy_framework | 11 | `1H=100, 2H=150, Off-Hand=60, Body=80, Head=60, Gloves=50, Feet=50, Accessory=70` | dict | ✓ |
| 18 | Rarity Multiplier | economy_framework | 12 | `Broken=0.1, Common=1.0, ... Transcendent=20.0` | dict | ✓ |
| 19 | Level Multiplier | economy_framework | 13 | `1 + (Item Level - 1) × 0.02` | `1 + (item_level - 1) * 0.02` | ✓ |
| 20 | Sell Value | economy_framework | 14 | `floor(Base Value × Rarity Mult × Level Mult × 0.25)` | `math.floor(bv * rm * lm * 0.25)` | ✓ |
| 21 | Shop Price | economy_framework | 15 | `round(Base Value × Rarity Mult × Level Mult × 4.0)` | `round(bv * rm * lm * 4.0)` | ✓ |
| 22 | Blacksmith Gold/Level | economy_framework | 19 | `floor(Base Value × Rarity Mult × 0.30 × (1 + Target Level / 25))` | `math.floor(bv * rm * 0.30 * (1 + tl / 25))` | ✓ |
| 23 | Recruitment Fee | economy_framework | 22 | `200 + (Unit Level × 15) + Quality Premium` | `200 + level * 15 + premium` | ✓ |
| 24 | Inventory Maintenance | economy_framework | 24-25 | `min(Excess × 5, 200). Threshold = 50` | `min(max(0, count - 50) * 5, 200)` | ✓ |
| 25 | Consumable Price | consumable_framework | 30-32 | `round(Base Profile Price × Tier Multiplier / 5) × 5` | `round(base * tier_mult / 5) * 5` | ✓ |
| 26 | Consumable Profile Bases | consumable_framework | 31 | `Quick=25, Routine=50, Standard=75, Heavy=110, Battlefield=160` | dict | ✓ |
| 27 | Consumable Tier Mults | consumable_framework | 32 | `Common=1.0, Uncommon=1.4, Rare=2.0, Epic=3.0` | dict | ✓ |
| 28 | Material Tier by Level | materials_system | 16, 21 | `L1-20→T1, L21-40→T2, L41-60→T3, L61-80→T4, L81-99→T5` | lookup | ✓ |
| 29 | Material Qty by Rarity | materials_system | 22 | `Common/Uncommon=1, Rare=2, Epic=3, Legendary=4, Mythic=5, Trans=6` | dict | ✓ |
| 30 | Material Conversion | materials_system | 25 | `3× lower → 1× next tier (one-way)` | `lower // 3` | ✓ |
| 31 | Fortune Gold Mult | loot_progression | 17 | `1 + 0.50 × Normalized Expedition Fortune` | `1 + 0.50 * norm_fortune` | ✓ |
| 32 | Unit Fortune | loot_progression | 9 | `LUK / (LUK + 200)` | `luk / (luk + 200)` | ✓ |
| 33 | Expedition Fortune | loot_progression | 10 | `Highest + 50% of 2nd + 25% of 3rd` | `uf + 0.5*uf2 + 0.25*uf3` | ✓ |
| 34 | Normalized Exp Fortune | loot_progression | 11 | `Expedition Fortune / 1.75` | `exp_fortune / 1.75` | ✓ |

## Proposed Formulas (NOT in DB)

| # | Formula | Source | Expression | Python | Status |
|---|---------|--------|------------|--------|--------|
| P1 | Facility Upgrade Cost | User-proposed | `round(Base × (1 + Level²/Scale))` | `round(base * (1 + level**2 / scale))` | Pending DB entry |

## Missing / Ambiguous

| Issue | Table | Note |
|-------|-------|------|
| Overleveled penalty scope | economy_framework | Row 7 says "same bands as XP" — unclear if this applies to completion/quest gold or kill gold only |
| Benched share (updated) | unit_progression | Row 52 updated from 50% to 65% — FORMULAS.md previously had 50% |
