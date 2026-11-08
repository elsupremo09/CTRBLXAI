# FORMULAS — Nov 8 batch review (sim\balance_review_2026-11-08)

All taken from CTRBLXAI.db (read-only snapshot 2026-11-08). No Luau read. Python in harness.py. All match ✅ unless noted.

| # | Formula | DB source | DB expression (short) |
|---|---|---|---|
| N1 | Stats per level | unit_progression 49, 100, 101, 104 | start + floor(growth×(L−1)); +3 allocable pts/level (+1 per 3 levels Human); enemies split evenly |
| N2 | Item scale | weapons_equipment 157 / nonweapon_equipment 11 | 0.30 + 0.70×((L−1)/98)^0.55, continuous past 99 |
| N3 | Weapons | weapons_equipment 25–45 | Sword 67/60/60/5, Hammer 80/130/110/5, Greatsword 65/165/28/10 (Dmg/WT/Dly/Def @L99) |
| N4 | Median armor | nonweapon_equipment (101 items, median per slot) | Def 89.5, WT 66, HP 109.5, MP 50.5 @L99 |
| N5 | Effective WT | core_stats 2 | WT×(1 − STR/(200+STR)) |
| N6 | Modified Base RT | weapons_equipment 7 | 400 (boss 300) + effective armor WT |
| N7 | Basic Attack RT / turn | weapons_equipment 8, 9 | round(MBRT×0.10)+effWpnWT; turn = MBRT + 2 actions |
| N8 | Skill RT | core_stats 20 | round((MBRT×0.10 + effWpnWT)×N); fixed formulas as authored |
| N9 | Channel | core_stats 6 | Channel × (1 − DEX/(300+DEX)) |
| N10 | RT delay dealt / taken | core_stats 2, 5 | base×(1+min(STR/(200+STR),0.75)); taken ×(1 − VIT/(300+VIT)) |
| N11 | Debuff duration | core_stats 5, 39 | ×(1 − VIT/(300+VIT)); boss ×0.5 ceil |
| N12 | Movement RT | movement_targeting 8 | round(MBRT×0.0375×tiles×(1 − AGI/(200+AGI))) |
| N13 | Movement Slow / Wet / Frozen | elements_statuses 130, 73, 74 | move RT ×1.50 / ×1.25 / all RT ×2 |
| N14 | Pinned | elements_statuses 66, project_rules 253 | 1000 CT; blocks Move + 5 leap/dash skills |
| N15 | Force / Stability / Push | core_stats 2, 5, 53 | 1+floor(STR/60); floor(VIT/60); push = max(0, Force−Stab) |
| N16 | Gale Thrust knockback | skills SKL-GALE-THRUST | max(0, floor(Force×0.5) − Stability) |
| N17 | Wall collision | movement_targeting 15–17 | MaxHP×0.04×blocked×(1+STR/200)×impact×(skill 0.5) |
| N18 | Damage | core_stats 31, 34, 35 | P − P·D/(P+D); P = WpnDmg×(1+STR/200)×mult×Potency; D = Def×(1+VIT/300); × Hit Quality |
| N19 | HP / MP / Potency / Heal eff. | core_stats 4, 5 | 50+4VIT; 20+2INT; 1+INT/(200+INT); ×(1+VIT/300) |
| N20 | Per-skill RT/MP/power/delay | skills rows for all 22 rule-252 skills + Blood Price, Life Link, Lunge, Recoil Shot, Sanctify, Consecrate, Bulwark Field, Healing Light | as authored |
| N21 | Lifesteal / Vitality Surge / Blood Harvest | augments 19, 89, 32 | 10% of damage / 5% max HP / 15% max HP on kill |
| N22 | Regeneration | elements_statuses 77 | every 300 CT round(round(MaxHP×0.05)×(1+VIT/300)) |
| N23 | Blessed / Blind | elements_statuses 80, 60 | Hit Quality +0.25 / Precision ×0.50 |

Assumptions (not DB gaps, modelling choices): STR delay bonus applied only to Weapon-RT-Delay formulas (Static Field / Blinding Flash fixed delays get no STR bonus); Hit Quality ≈ 1 (even DEX/AGI); one full move per turn under Movement Slow.

Missing from DB: none blocking. Open question (needs ruling, not a formula): whether rule 252 also spreads AUGMENT riders (e.g. Pinning Support) to every unit an area skill hits.
