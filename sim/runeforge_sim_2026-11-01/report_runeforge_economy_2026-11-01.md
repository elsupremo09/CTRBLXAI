# SIMULATION RUN — 2026-11-01 — Runeforge + Blacksmith expansion (design verification, nothing built)
Seed: 20261101 (deterministic; no random draws)
Formulas loaded: 40 (all from CTRBLXAI.db, provenance in FORMULAS_addendum.md)
Cases run: 2,328,480 catch-up route pairs · 19,008 enchant→sell · 62,720 upgrade→sell · 8,712 buy→enchant→sell · 10,720 upgrade→dismantle→sell-materials · 25 facility runs
Level bands: item level 1-99 (Runeforge / Blacksmith content tops out at 99)
Files modified: sim\runeforge_sim_2026-11-01\ only. source\ and docs\ untouched.

## SECTION 1: BLOCKERS
None hard. Two soft gaps (simulated with stated assumptions):
- Elite encounter rate is still "pending" (loot_progression 26/69). G's 25/75 split depends on it.
- No single "equipment drops per battle" number. 0.40/battle back-derived from the 10,800g sell income.

## SECTION 2: PASS/FAIL TABLE
| Check | Expected | Measured | Result |
|---|---|---|---|
| A 1H L1→99 | 26,637 / 19,441 (−27%), 196 mats 38/40/40/40/38 | 26,637 / 19,441, 38/40/40/40/38 | PASS |
| A 2H L1→99 | 39,954 / 29,166 | 39,954 / 29,166 | PASS (subtotals 13,279 / 53,233, not 13,276 / 53,230, see note 1) |
| A 1H L1→50 / L50→99 | 8,997 / 17,640 | 8,997 / 17,640 | PASS |
| A Body L1→99 | 21,309 | 21,309 | PASS |
| A 1H Unc→Rare L1→50 | 3,015 / 49 | 3,018 / 49 | PASS* (note 1) |
| A all routes, same discount | equal to the gold piece | 2,328,480 cases, 0 mismatches; C→U→R→E equals C→E | PASS |
| A remove → upgrade → re-add | no saving | 0 saving | PASS |
| A downgrade below start, then enchant | no saving | max saving 0 (30 cases) | PASS |
| A existing items | 0 | 0 | PASS |
| A upgrade over time, enchant late | equal | Common upgrades bought at the Blacksmith levels needed, enchanted at BS L10: saves 1H 2,760g, 2H 4,133g, Body 2,208g (~9%) | WARN |
| B fee table (18 values) | table | all 18 match | PASS |
| B C→R→E = C→E (1H L50) | 1,980 | 1,980 (old rule would give 1,386) | PASS |
| C enchant→sell, 1H/2H, 4,752 cases | max −22 / −34 | −22 / −34 | PASS |
| C all 8 slots | — | max −11 (Gloves C→U, L1, −27%) | PASS |
| C upgrade→sell | best −11 | −11 (Common Gloves; L1→2 and L2→3 tie) | PASS |
| C buy→enchant→sell | loses | best −188 (just buying and selling back) | PASS |
| C upgrade→dismantle→sell materials (not in the brief) | ≤0 | **+250g per cycle** (exploit X2) | FAIL |
| C enchant→dismantle→sell materials (not in the brief) | ≤0 | **+63g per item** (exploit X1) | FAIL |
| D crafted Epic L50 | ~2,240 (1H) / 3,364 (2H) | 2,240 (4×T1) / 3,364 (1×T4) | PASS |
| D 2H one T4 Add | 324/540/892; 236/394/651 | identical | PASS |
| D supply L50-80 | crafted Epics must not become the main source | free classic/crafter: Runeforge L10 at L88-90, so 0. **Free rush: L10 at L50, up to 8 crafted vs ~4 natural, 0 shop. Boosted: L10 at L30-61, 9-14 crafted** | FLAG |
| E free player | old 6/9 | model reproduces 6/9. New: **8/10** (classic, crafter), 7/10 (rush), <1.6k left | INFO |
| E boosted | old 9/9 + ~29,900 | old reproduced (30,441). New: 10/10 + 35.0-37.6k | PASS |
| E Runeforge L1/L5/L10 (free) | — | classic L81/L83/L90 · crafter L17/L33/L88 · rush L7/L16/L50 | INFO |
| E discount frees | 10-14k | free 11.4-12.6k (shape A), 12.1-14.3k (shape B) | PASS |
| E Blacksmith share | was 43% | ~36% free (27-28% boosted) | INFO |
| E expense ratio | was 108% / 83% | 105.9-106.6% free / 83.1-84.3% boosted | INFO (pressure eased, note 3) |
| F wall still exists | yes | DB income (286/tier): 12 with no dismantling → 12-15 with dismantling → 17 at most with X1. 2026-09-16 income (311): 13 → 13-16 → 18 | PASS |
| F 10 items | 89% | 89.2% (DB income) | PASS |
| F T5 income | unchanged | dismantling never gives T5 | PASS (catch-up fees now spend T5: 38 per 1H L80→99 C→E) |
| G drop share | ~25% | 25.0% base (sensitivity 11.8-28.4%) | PASS (conditional) |
| G Essences / battle | — | U 0.357 · R 0.057 · E 0.023 | INFO |
| G battles to fill 1H U / R / E | — | 5.6 / 8.4 / 11.2 (cheapest T1 lines). Power lines: T3 (2R) 35, T4 (2E) 87 | INFO |
| G 2H | — | 11.2 / 16.8 / 22.4; 2×T4 174 | INFO |
| G trade-up 3:1 | — | E supply 0.023 → up to 0.063 per battle (+170%), R 0.057 → 0.176; T4 drops from 87 to ~25 battles of all Essence income | INFO |
| H shop-bought dismantle | nothing | 0 materials, 0 Essences | PASS |
| H reroll fixed after rejoin | fixed | identical after save/load; changes only after a paid reroll | PASS (gaps) |
| H Fortune | never offered, never tiered up | Add refused, Modify-up refused, 0 of 4,500 reroll offers | PASS |
| H above Epic | tune only at L10 | Add refused, L9 refused, rarity unchanged | PASS |
| H Unique | refused | Add/Modify/Dismantle refused | PASS |
| I BP | 200 / 400 vs natural 190-210 | crafted cap 200/400, never above the natural 210 | PASS |
| I hand-picked lines | not the obvious best | T4 = 1.38× the value of 4×T1 (main stats, Weapon Attack, HP, MP). Natural 1H Epic holds a T4 in your chosen family 0.9% of the time | WARN |
| I Balance Audit benchmark | compare | no item-attribute benchmark exists (only skill audit 2026-10-21) | N/A |
| J save size | under 4 MB | +30 B/item (short keys) to +93 B (long names), +34 B counters. 1,000 items: 115 → 206 KB. 4 MB at ~19.9k items (was ~35.5k) | PASS |

Notes
1. Exact math on the DB formula gives 13,279 / 53,233 / 3,018. The expected 13,276 / 53,230 / 3,015 come from a plain floating-point version: 150 × 1.0 × 0.30 × 2 lands just under 90 and floors to 89. 98 per-level Blacksmith costs and 13 Runeforge costs are 1g off this way. The fees match either way, because both routes use the same function.
2. The 25/75 split depends on the missing elite rate and the drop rate. At 1 item per battle (the design doc figure), drops fall to 12%.
3. The discount frees 11-14k, more than the Runeforge costs (8,919g). The free player ends richer than before: the deficit goes from ~14.0k to ~10.3-11.5k.

## SECTION 3: EXPLOITS FOUND
**X1. "+1 for Rare" from enchanting** (guild_facilities 51 reads the CURRENT rarity)
- Route: take an Uncommon loot Gloves/Feet at L61-99. Add one T1 line at the Runeforge (L5+), which makes it Rare. Dismantle it.
- You get +1 T4, and the 1 Uncommon Essence comes back.
- Profit: +45 to +63g per item (L61-80), +35 to +54g (L81-99). For 1H items, +8 to +25g at −27%. Gloves L41: +6 to +12g (T3).
- A Common item takes 3 T1 Adds. That costs 111-162g per T4, a loss in gold, but cheap T4.
- Supply in L61-99 is about 18 Uncommon + 42 Common items: up to ~60 extra T4, +21% of the T4 income. This moves the wall up by 1-2 items.

**X2. Tier laundering + free downgrade** (refunds are paid in the current band's tier)
- Route: take any non-shop Common Gloves/Feet. Downgrade it to L1 (free; the starting level becomes 1). Upgrade L1→61 at BS L10 for 1,455g + 19 T1, 20 T2, 20 T3, 1 T4. Dismantle: you get 30 T4.
- The materials put in sell for 1,295g. The 30 T4 sell for 3,000g. Net +250g per cycle.
- There are 6 profitable setups, all at BS L10 with Gloves/Feet. At BS L7-8 it loses gold, but it still swaps 20 T3 for ~26 net T4 (conversion gives 6.7).
- Limited by T3 supply (20 per cycle), so a few thousand gold over a lifetime. It is still a positive loop.
- Upgrading an Epic L1→80 and dismantling it returns 119 T4 after spending only 60 T4.

**X3. Late-enchant timing (minor)**
- The catch-up fee uses the current discount.
- Upgrading a Common through the game and enchanting at BS L10 saves ~9% against enchanting first (1H 2,760g, 2H 4,133g). You pay for it by using a Common item all game.

**X4. Add-offer farming (rule gap)**
- Below L10, Add shows 3-6 choices, but the rules don't say those choices are fixed.
- Remove + Add with leave/rejoin can fish for an exact family. This is the rejoin-farm the Reroll rule was written to block.

## SECTION 4: DESIGN NUMBERS / TEXT THAT LOOK WRONG (suggestions only, nothing changed)
1. Dismantle refund (gf51): refund each tier inside that tier, at 25-50% of what was spent in it. Pay the T5 part as T4 or as nothing. Base the "+1" on starting rarity, like the sell rule. This closes X1 and X2; every loop then loses.
2. Catch-up fee discount (gf48): per level, use the discount of the Blacksmith level needed to reach that level, 3% × (ceil(level/10) − 1), not the current discount. This closes X3 exactly.
3. Epic supply (gf53/57): a free rusher gets Epic crafting at L50, a boosted rusher at L30. Crafted Epics cost 30-50% of the shop Epic (Rare start 1,451g vs 4,752g at 1H L50). That undoes the ×6 markup's purpose in L50-80 for those players. If L50-80 should stay tight, either:
   - gate Runeforge L10 also on player/guild level ~70-80, or
   - set the step-fee factor at 0.75-1.0 instead of 0.5.
   Your call.
4. Blacksmith discount: −3%/level frees more gold than the Runeforge costs. −2%/level (~8k freed) keeps the old ~108% ratio. −1.5 to −2% if you want the old pressure back. Note: a player who dismantles all spare loot gives up ~7.9k of sell gold, which offsets about half of the discount.
5. Epic step fee rounding (gf57): the fee is a half gold piece in 158 slot/level/start cases (all off-hand/armor/accessory slots, e.g. Off-Hand Rare L2 = 428.5g). Add "round down".
6. Integer math: tell the Dev to compute R-01/R-11 in whole numbers. Floating point drops 1g at exact values (note 1).
7. Reroll text (gf55): say whether the reroll count goes up when the old line is kept, and whether options are keyed per line. Also make Add offers fixed (X4).
8. Wall benchmark (gf38 vs ms36): "13 items" and "12 = 98%" use ~311/tier. The DB income row says ~286, which gives a wall at 12 and 12 = 107%.
9. Workshop cost table (gf31): L2/L3/L7 = 178/212/483, but the formula gives 177/211/484. The table sums to 4,124 against a stated 4,123, so the 10-facility total is 70,928 vs 70,927. Older data bug.

## SECTION 5: DB vs DESIGN DOC CONFLICTS (DB used)
- Save fields: the doc Part 4-I lists 3 planned per-item numbers. The DB (equipment_schema 16-19, save_data_contract 3) has 4, including starting_rarity. Used 4.
- open_decisions 123 Q9 and the gf57 notes still contain "rarity before the enchant". The gf57 rule and UPDATE 3 say starting rarity. Used starting rarity; that text is stale.
- Doc Part 4 C says the free player can't reach facility L10 before ~L50-80. Measured: L50 when rushing, L88-90 otherwise.

## SECTION 6: HEALTHY
- Catch-up fee closes the dodge exactly at equal discount, in every slot, rarity, level range and Blacksmith level.
- The starting-rarity Epic fee makes every route pay the same.
- Option C closes every enchant/upgrade/buy → sell item loop.
- Every guard holds: shop-bought items, Fortune, above-Epic, Unique, rarity-never-drops, downgrade edge.
- T5 stays protected.
- Save size is far below 4 MB.
- The boosted player keeps a healthy surplus.

## SECTION 7: DELTA vs previous economy runs
- Resolved: the old +3g Uncommon→Rare sell loop is closed by option C.
- New: X1, X2 (positive gold loops through dismantling), X3 (minor), X4 (rule gap); Epic supply flag for rush/boosted players; the free player rises from 6/9 to 8/10.
- Unchanged: 16:1 / 24:1 buy-sell ratios; consumable costs; T5 income.
- DB changes since the last run: guild_facilities 1-58, materials_system 1-42, economy_framework 14-46, equipment_schema 16-19 (the Runeforge set).

## VERDICT
2 CRITICAL FINDINGS: dismantling has two positive gold/material loops (X1 +63g per Uncommon item, X2 +250g per cycle) because refunds use the current rarity and the current level band's tier. Plus 1 supply flag: crafted Epics become the main Epic source in L50-80 for rush and boosted players.
