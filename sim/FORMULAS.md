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

## Implemented Formulas — Combat / Skill Simulation (added 2026-10-21)

**Source:** `core_stats` table (ids per row) + per-skill authored fields in the `skills` table. No Luau read.

| # | Formula | DB Table | Row/id | DB Expression | Python | Match |
|---|---|---|---|---|---|---|
| C1 | Attack Power | core_stats | id2 | Weapon Damage x (1 + STR/200) | `w*(1+STR/200)` | OK |
| C2 | Effective Equipment WT (>=0) | core_stats | id2 | WT x (1 - STR/(200+STR)) | `wt*(1-STR/(200+STR))` | OK |
| C3 | Effective Equipment WT (<0) | core_stats | id2 | WT x (1 + STR/(200+STR)) | `wt*(1+STR/(200+STR))` | OK |
| C4 | Skill Potency Multiplier | core_stats | id4 | 1 + INT/(200+INT) | `1+INT/(200+INT)` | OK |
| C5 | Max MP | core_stats | id4 | 20 + INT*2 | `20+INT*2` | OK |
| C6 | MP Regen /1000CT | core_stats | id49 | 2 + floor(INT/40) | `2+INT//40` | OK |
| C7 | HP | core_stats | id5 | 50 + VIT*4 | `50+VIT*4` | OK |
| C8 | Defense Power | core_stats | id5 | Defense x (1 + VIT/300) | `d*(1+VIT/300)` | OK |
| C9 | Effective Defense | core_stats | id31 | (P*D)/(P+D) | `(ap*dp)/(ap+dp)` | OK |
| C10 | Raw Damage | core_stats | id31 | P - Effective Defense | `max(0,ap-eff_def)` | OK |
| C11 | Skill Power (standard) | skills.Power_Formula | per-skill | Weapon Attack Power x N x Skill Potency | `atkpwr*N*spm` | OK |
| C12 | Precision | core_stats | id35 | DEX/(DEX+200) | `DEX/(DEX+200)` | OK |
| C13 | Evasiveness | core_stats | id35 | AGI/(AGI+200) | `AGI/(AGI+200)` | OK |
| C14 | Hit Quality | core_stats | id35 | 1 + (Precision - Evasiveness) | `1+(prec-eva)` | OK |
| C15 | Channel Time (DEX) | core_stats | id6 | Base x (1 - DEX/(300+DEX)) | `b*(1-DEX/(300+DEX))` | OK |
| C16 | Standard Base RT / AP | core_stats | id12 | Base RT=400, AP=2 | `400 / 2` | OK |
| C17 | Modified Base RT | weapons_equipment | MBRT row | Base RT + Effective Armor WT | `SBR+earmwt` | OK |
| C18 | Basic Attack RT | core_stats | id19 | round(MBRT*0.10) + Eff Weapon WT | `round(mbrt*0.10)+ewwt` | OK |
| C19 | Skill RT (weapon-WT type) | core_stats | id20 | round((MBRT*0.10 + Eff Weapon WT) x N) | `round((mbrt*0.10+ewwt)*N)` | OK |
| C20 | Skill MP cost (standard) | skills.MP_Cost_Formula | per-skill | round(a + b*(L-1)) | `round(a+b*(L-1))` | OK |
| C21 | Skill RT (fixed type) | skills.RT_Cost_Formula | per-skill | round(a + b*L) | `round(a+b*L)` | OK |
| C22 | Weapon level scaling | weapons_equipment | scaling row | 0.30 + 0.70*((il-1)/98)^0.55 | `same` | OK |
| C23 | Rapid Assault hit count | skills.Power_Formula | SKL-RAPID-ASSAULT | min(4, 2 + floor(AGI/100)) | `min(4,2+AGI//100)` | OK |
| C24 | Chain falloff | skills.Effects | chain skills | 100/80/64/51.2% per jump | `declining` | OK |
| C25 | Lucky Strike LUK bonus | skills.Power_Formula | SKL-LUCKY-STRIKE | 0.75*LUK/(100+LUK) | `(reported, not ratio-priced)` | OK |
| C26 | Stat at level | races | growth cols | floor(start + growth*(L-1)) | `floor(s+g*(L-1))` | OK |
| C27 | Boss Base RT / AP | core_stats | id13 | Base RT=300, AP=3 | `(context only)` | OK |
| C28 | Rest RT | core_stats | id14 | round(MBRT*0.75) | `(context only)` | OK |

### Combat blockers found 2026-10-21
| Issue | Table | Note |
|---|---|---|
| 7 skills NULL Channel/Activation | skills | EMPOWERING-AURA, SKYFALL-LANCE, DRAGON-DIVE, HOLY-SMITE, SANCTIFY, BARRAGE, NATURES-GRASP - cast cost unknown, priced as 0/0 (upper bound) |
| 6 non-standard Power formulas | skills | DARK-RESTORATION, LUCKY-STRIKE, TWINBLADE-01/02, RETRIBUTION-SHELL, SUMMON-TURRET - need dual-wield/summon pricing model |
| Wind element has 0 skills | skills | content gap (Designer); not a balance break |
