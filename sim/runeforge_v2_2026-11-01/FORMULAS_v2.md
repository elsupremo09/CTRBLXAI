# FORMULAS_v2 — Blacksmith + Runeforge v2 design check (2026-11-01)

Seed 20261101. DB opened read-only (`mode=ro`). Every DB string below is asserted in code by `prov()`; a missing string stops the run. v2 rules are not in the DB: their only source is the draft snapshot in this folder (`draft_snapshot_blacksmith_runeforge_v2_proposal_20261101.md`). Where the draft and the DB disagree on a v2 rule, the draft wins.

## A. Existing values (DB)
| Name | Table / row | DB text (asserted) | Python |
|---|---|---|---|
| Slot value | economy_framework 11 | 1H = 100, 2H = 150, Off-Hand = 60, Body = 80, Head = 60, Gloves = 50, Feet = 50, Accessory = 70 | `BASE` (parsed) |
| Rarity multiplier | economy_framework 12 | Common = 1.0 … Transcendent = 20.0, Unique = 15.0 | `RM`; `R10 = RM×10` |
| Level multiplier | economy_framework 13 | 1 + (Item Level - 1) × 0.02 | `lvl_mult` |
| Sell | economy_framework 14 | floor(Base × Rarity × Level × 0.25), starting rarity | `sell(slot, start_rarity, L)` |
| Shop | economy_framework 15 | round(Base × Rarity × Level × Markup), ×4 C/U/R, ×6 Epic/Exalted | `shop()` (round half up) |
| Upgrade gold shape | economy_framework 19 | Base × Rarity × 0.30 × (1 + Target/25) × (1 − 0.03 × (BS − 1)) | matches `credit×R/250000` (identity checked: 1H Common L1→2 = 32g) |
| Recruit fee | economy_framework 22 | 200 + Level × 15 + premium | T8 |
| Dispatch | economy_framework 26, unit_progression 99 | 50g / mission, 3 slots; one offer per tier; days = tier | T12 range |
| Income / necessities / BS share | economy_framework 42 / 43 / 20 | ~175,800g / ~127,800g / ~43% | facility sim |
| Merchant odds | economy_framework 48 | L10 C10 U30 R40 E15 Ex5; shelf 5…10 | T11 shop supply |
| BS rarity unlocks | guild_facilities 13 | Rare L3, Epic L5, Exalted L6, Legendary L7, Mythic L9 | `BS_UNLOCK` |
| Facility costs / gate | guild_facilities 2, 3, 8, 26-34, 49 | cost tables; Guild Hall gates level; Runeforge at GH L4 | `FAC`, `fac_sim` |
| Loot weights | loot_progression 48-53, 84 | Normal C .55 U .2429 R .1214 E .0595 Ex .025 L .0012 | `LW_N` |
| Fortune | loot_progression 9-13, 16, 17 | Unit Fortune LUK/(LUK+200); top+½+¼; /1.75; drop = min(95%, 5%×M); weights ×(1+F×sens); gold 1+0.5F | T18 |
| Fortune sensitivity | loot_progression 59-64, 85 | U .25 R .5 E .75 Ex .85 L 1 | `SENS` |
| Enemies / battle | loot_progression 86 | Normal 5, Elite 6, Boss 4 + boss | mercury from kills |
| Working estimates | loot_progression 24, 26 | 0.40 drops/battle; elite 0.034, boss 0.034, chest 0.2 per battle | economy |
| Fortune exclusion | materials_system 19 | Fortune does NOT affect material drop rate | T18 / T20 |
| Budgets / passive limit | item_rarity_rules 2, 3; item_rarity_framework | budgets and tolerance bands; 1 passive (2H 2) | T10/T17 |
| Item scale | item_rarity_rules 7 | 0.30 + 0.70 × ((L−1)/98)^0.55 | T17 |
| Movement | core_stats 3 | 3 + floor(AGI / 60) + bonuses | T17 |
| Gem kinds | bonus_numerical_attributes (T1-T4, 25 families) + bonus_passives (55 − PAS-027/028) | counted live: 153 | T15 |

## B. v2 rules (draft sections)
| Rule | Draft | Python |
|---|---|---|
| credit(t, b) = slot × 3 × (25 + t) × (100 − 3(b − 1)) | 4.1 | `credit` |
| Paid(C, R) = floor(C × R / 250,000) | 4.2 | `paid` |
| Upgrade gold = Paid(C_new) − Paid(C_old); +1 mercury/level | 4.2, 1.3 | `Item.upgrade` |
| Catch-up = Paid(C, R_new) − Paid(C, R_old) | 4.2 | `Item.forge` |
| Downgrade: cut record at B, F → B if below F, lose Paid difference, no refund | 4.2 (Q7) | `Item.downgrade` (`exact`) |
| Controls: D2 (remove at today's discount), reset-to-0 | 4.3 | variants `D2`, `reset` |
| Forge crystals: steps 3/6/12, keep 2/4/8 | 2.3 | `forge_crystals` |
| Forge fee = floor(slot × RM(result) × (100 − 3(RF−1))/100) | 2.3 | `forge_fee` |
| Epic step fee (optional, OFF) = floor(0.5 × (L1 shop Epic − L1 shop start)) | 2.3 | `epic_step_fee` |
| Dismantle: mercury ceil(L/10); crystals C0 U1 R2 E3 Ex4 L6 M8 T10 Uq10; sulfur Ex1 L2 M3 T4 Uq3; 1 gem per line (T5/T6 → T4) | 1.4 | `dis_*` |
| RF capacity Uncommon L1 / Rare L4 / Epic L7 | 2.4 | `rf_capacity` |
| Elite 3 crystals, 50% gem, 25% sulfur L60+; boss 5 / 1 / 1 | 3.2 | `lifetime()` |
| Mercury drops: kills 10%, elite 2, boss 3, chest 1, quests ~0.3, dispatch ~0.6 | 3.1 | `lifetime()` |

## C. Assumptions (not in DB or draft)
1. Bonus lines per dropped item: uniform over legal tier partitions (same model as runeforge_sim_2026-11-01): Uncommon 1.69, Rare 2.23, Epic 2.68, Legendary 3.16 lines.
2. Fortune scales only the ordinary-kill share of drops (5 × 5% = 0.25 of 0.40); the other 0.15 is fixed.
3. Gem families uniform; 10% of gem lines are passives (T11 coverage only).
4. Black Market spawn 1-5% of battles (not in DB).
5. Fortune line operation: A = adds 0.05-0.20 to Unit Fortune; B = multiplies it. Team value clamped at Normalized 1.0.
6. Daily-event count per lifetime not in DB: reported per 10 events.
