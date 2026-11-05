# FORMULAS addendum — RE-CHECK (2026-11-01, after Simulator fixes)
Root sim\FORMULAS.md not edited (task rule). These replace R-09, R-10, R-11, R-15 of FORMULAS_addendum.md. Checked against the RULE column only (rf_recheck.py prov2), because some first-run checks also matched quoted "Old:" text in the notes.

| ID | Formula | DB row | Expression in DB (rule column) | Python (rf_recheck.py) | Match |
|---|---|---|---|---|---|
| R-01b | Upgrade gold, whole numbers | economy_framework 19 (+notes: rounds down) | floor(Base × Rarity × 0.30 × (1 + T/25) × (1 − 0.03(B−1))) | `ugi()` = (Base·RM×10·3·(25+T)·(100−3(B−1))) // 250,000 | yes, 0 of 62,720 differ from exact |
| R-09b | Catch-up fee | guild_facilities 48 | per level: (cost at new − cost at old rarity), discount 3% × (ceil(level/10) − 1), each level rounded down first; gold + materials | `fee2()` | yes (22,201 / 33,299 / 17,763) |
| R-10b | Epic step fee | guild_facilities 57 | 0.5 × (shop Epic − shop at STARTING rarity), rounded down | `epic_fee_f()` | yes (Off-Hand Rare L2 = 428) |
| R-11b | Runeforge actions | guild_facilities 55, 53; equipment_schema reroll_count | Add list = first 3/3/4/4/4/5/5/6/6/full of a fixed order from the item ID, skipping attributes on the item; Reroll options per line from ID + line attribute + tier + reroll count; every paid reroll +1; all fees round down | `add_order()`, `add_list()`, `rr_opts()`, `rr()` | yes |
| R-15b | Dismantle | guild_facilities 51, materials_system 42 | per tier: floor(refund% × that tier's recipe materials start→current at current rarity), same tier; T5 part → same number of T4; +1 if STARTING rarity ≥ Rare, in the current level band tier (L61-99 T4); shop-bought → nothing | `dis2()` (T4 and T5 parts rounded separately; the other reading differs by ≤1) | yes (9/10/10/0 example) |

Working estimates used (not decisions): 0.40 equipment drops/battle (loot_progression 24), 0.034 elites/battle (loot_progression 26/69, materials_system 41).
