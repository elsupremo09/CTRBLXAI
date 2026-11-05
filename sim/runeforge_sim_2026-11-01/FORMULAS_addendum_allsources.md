# FORMULAS addendum — ALL-SOURCES dismantle run (2026-11-01)
Root sim\FORMULAS.md not edited (task rule: new files only). Builds on FORMULAS_addendum.md + FORMULAS_addendum_recheck.md (R-01..R-24, R-01b..R-15b, all re-verified this run; ms42 check string updated to the current wording).

| ID | Formula / value | Source | Expression | Python (rf_allsources.py) | Match |
|---|---|---|---|---|---|
| R-15c | Dismantle, all sources | USER RULING 2026-11-01 (NOT yet in DB) + gf51/ms42 | gf51 per-tier refund, T5 as T4, +1 from STARTING rarity Rare+, 1 Essence per line capped by gf50, with "Shop-bought items give nothing" REMOVED | `dis2(..., shop=False)` for every source | user-stated |
| R-25 | Shelf size / rarity odds | economy_framework 48, gf15 | L1-10 slots 5,5,6,7,7,8,9,10,10,10; odds per level (L10 C10 U30 R40 E15 Ex5); item level = map level | `ODDS`, `SLOTS_M`, `shelf()` | yes |
| R-26 | Stock refresh | gf15 | every 5 completed battles | windows of 5 battles | yes |
| R-27 | Shop price | economy_framework 15 | round(Base × Rarity × LevelMult × 4 or 6) | `shop()` | yes |
| R-28 | Material sell / Essences unsellable | materials_system 28 | T1 5, T2 15, T3 40, T4 100, T5 250 | `SELLV` | yes |
| R-29 | Essence trade-up | gf53 | Runeforge L6: 3 lower → 1 higher | U=1, R=3, E=9 Uncommon-equivalents | yes |
| R-30 | Extraction cap | gf50 | L1-3 Uncommon, L4-6 Rare, L7-10 Epic | `capv()` | yes |
| R-31 | Line budgets / bands | item_rarity_rules 2, item_rarity_framework | U 100, R 150, E 200, Ex 225 (2H ×2); bands 95-105 … 214-236 | `comps()` (best case, ≤1 passive, 2H ≤2) | yes |
| R-32 | Tier / passive minimum rarity | bonus_numerical_attributes, bonus_passives | T1-2 Uncommon, T3 Rare, T4 Epic; passive BP 60-300 with min rarity | `TMIN`, `PAS` | yes |
| R-33 | Hire fee / dismissal | economy_framework 22 / 49 | 200 + 15L + premium (0/300/800); dismissal 5× | `REC` | yes |
| R-34 | Dismantle limits | gf52 | equipped, dispatched, staged, Unique refused | recruit check | yes |

How items are obtained (source read only — used for counts, never for formulas)
- MerchantService.GetStock L350-447: one uniform archetype pick from 146 archetypes (1H 18, 2H 20, Off-Hand 7, Gloves 21, Head 20, Body 20, Feet 20, Accessory 20); shelf per (5-battle window, map level, Merchant level).
- GuildMenuService L951-965: shelf rebuilt per map level; Main L1793: map level = active quest level (else 1). QuestGenerator: 3 quests per board.
- GuildMenuService L469-523: recruit weapon = Common at recruit level (sourceType "Recruit"); ItemGenerator L578-582: Common = no lines.
- ObjectEffectService L2289-2298: Black Market = 6 free Rare items at map level, once per object per battle.
- Main L642-754: starter Uncommon L5 weapons (Debug), Common L5 shield (Debug), 5 Common L5 armor (Starter).
- EquipmentService L234: a unit must keep a weapon (BUG-050).

Working assumptions (not in the DB, stated)
- Expected lines = uniform over legal tier partitions (as in the first run); "best case" = the player picks the item (lines are shown in the shop).
- Lifetime budgets and Merchant/Blacksmith levels come from the first-run facility runs (free/boost classic); purchases spread in proportion to income.
- Normal shop gear spend: 10k / 20k / 31k g (not in the DB). Black Market rate: 0.02-0.25 per battle (object density not decided, open_decisions 48).
