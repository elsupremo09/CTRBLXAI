# FORMULAS addendum — Runeforge / Blacksmith expansion run (2026-11-01)

The root `sim\FORMULAS.md` was NOT edited (task rule: write only to this dated folder). Merge these entries into it when allowed.
Every entry below is read from `docs\CTRBLXAI.db` at run time by `rf_core.py` / `rf_econ.py`. The run stops if the quoted text is missing (`prov()` check). 40 formulas/values loaded. Seed 20261101 (no RNG used; reroll options use a SHA-256 hash of seed + item + reroll count).

| ID | Formula | DB row | Expression in DB | Python | Match |
|---|---|---|---|---|---|
| R-01 | Upgrade gold / level | economy_framework 19 | floor(Base Value × Rarity Mult × 0.30 × (1 + Target Level / 25) × (1 − 0.03 × (Blacksmith Level − 1))) | `ug()` exact rational (Fraction) + naive double variant | yes |
| R-02 | Base value by slot | economy_framework 11 | 1H 100, 2H 150, Off-Hand 60, Body 80, Head 60, Gloves 50, Feet 50, Accessory 70 | parsed | yes |
| R-03 | Rarity multiplier | economy_framework 12 | Common 1.0 … Epic 4.0, Exalted 5.5 … | parsed | yes |
| R-04 | Level multiplier | economy_framework 13 | 1 + (Item Level − 1) × 0.02 | `lvl_mult()` | yes |
| R-05 | Sell value | economy_framework 14 | floor(Base × Rarity × Level Mult × 0.25); enchanted items use starting rarity | `sell(slot, starting_rarity, L)` | yes |
| R-06 | Shop price | economy_framework 15 | round(Base × Rarity × Level Mult × Markup); ×4 C/U/R, ×6 Epic/Exalted | `shop()` (round half up) | yes |
| R-07 | Material tier by target level | materials_system 21 | 1-20 T1 … 81-99 T5 | `mtier()` | yes |
| R-08 | Material quantity by rarity | materials_system 22 | C 1, U 1, R 2, E 3, Ex 3, L 4, M 5, T 6 per level | parsed | yes |
| R-09 | Catch-up fee | guild_facilities 48 | Σ per level (cost at new rarity − cost at old rarity), gold + materials, current Blacksmith discount; downgrade below start lowers start | `catchup()` | yes |
| R-10 | Epic step fee | guild_facilities 57 | 0.5 × (shop Epic − shop at STARTING rarity), no discount | `epic_fee()` (kept as exact fraction; DB gives no rounding) | yes |
| R-11 | Runeforge action gold | guild_facilities 55 | floor(base × 0.30 × (1 + L/25) × factor × (1 − Runeforge discount)); Add = tier, Reroll 1, Modify-down 0.5, Remove 0.5 | `rf_gold()` | yes |
| R-12 | Rarity after Add | guild_facilities 44 | max(rarest line's min rarity, BP band 100/150/200, 2H ×2); never goes down | `band_rarity()`, `rf_add()` | yes |
| R-13 | Runeforge capacity / tiers | guild_facilities 53, 54 | L1-4 100, L5-9 150, L10 200 (2H ×2); T1-T2, T3 at L5, T4 at L10; above Epic tune only at L10; Unique never | `rf_cap()`, `rf_add()`, `rf_modify()` | yes |
| R-14 | Blacksmith level table | guild_facilities 50 | max up / reach / discount / extract / refund per level | parsed `BS_TABLE` | yes |
| R-15 | Dismantle output | guild_facilities 51 | floor(refund% × materials of the normal recipe start→current at current rarity) + 1 if Rare+; tier = current level band, L81+ → T4; 1 Essence per line capped by extraction; shop-bought → nothing | `dismantle()`, `launder()` | yes |
| R-16 | Essence drops | materials_system 41 | chest 25% U, elite 75% R, boss 100% E (R below L40), Fortune never | `essence_sim()` | yes |
| R-17 | Facility cost | guild_facilities 2 + tables 26-34, 49 | round(Base × (1 + L²/Scale)) | parsed tables (Workshop table ≠ formula, see report) | partly |
| R-18 | Unlock schedule | guild_facilities 8 | L4 Workshop + Runeforge … | `UNLOCK_GH` | yes |
| R-19 | Income sources | economy_framework 2, 8, 9, 42 | kill / completion / quest gold; lifetime ~175,800g | shape scaled to 175,800 over 547 battles | yes |
| R-20 | Necessities / Blacksmith share | economy_framework 43, 20 | 127,800g; ~43% of income | constants | yes |
| R-21 | Material conversion | materials_system 25 | 3 lower → 1 higher | used in wall check | yes |
| R-22 | Material sell | materials_system 28 | T1 5, T2 15, T3 40, T4 100, T5 250; Essences unsellable | used in loop checks | yes |
| R-23 | Loot rarity weights | loot_progression 48-56, 84 | Normal: C .55 U .2429 R .1214 E .0595 Ex .025 L .0012 | `LW` | yes |
| R-24 | Normal drop chance | loot_progression 24 | 5% per enemy | context only | yes |

## Simulator assumptions (NOT in the DB — stated, not hidden)
- 547 battles spread evenly over L1-99; income shape from R-19 scaled to 175,800g.
- Necessities spent each battle in proportion to income; Blacksmith 43% of it, either proportional to income (shape A) or to (1 + L/25) (shape B).
- Blacksmith level is bought when needed (level ≥ ceil(item level / 10)), as the max-upgrade rule forces.
- Elite encounter rate is PENDING in the DB (loot_progression 26/69). Elite/boss/chest rates are back-derived from materials_system 15 (chest 0.2/battle; elite and boss 0.034/battle each; alternatives tested).
- Equipment drops: 0.40 items/battle (back-derived from the 10,800g lifetime sell income), 10% kept; 1.0/battle tested as the high case.
- Natural line mix: uniform over legal tier partitions of the rarity budget (no passives).
