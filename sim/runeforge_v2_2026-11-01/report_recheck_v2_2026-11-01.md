# SIMULATION RUN — 2026-11-01 — Blacksmith + Runeforge v2 RE-CHECK (R1-R5)
Seed: 20261101 · run twice in one session, results identical (body md5 f576a621…)
Source of truth: FINAL draft `artifacts/blacksmith_runeforge_v2_proposal_20261101.md` (Designer thread-82c673e2fa84)
DB: opened read-only (md5 4234bb43…). All 35 DB rows used last run still match word for word, so no DB value changed.
Code reused: v2_core.py, v2_tests_b.py, v2_tests_c.py (not changed). The re-check code is stored in `results_recheck_v2.json` → "code".
Files changed: only the 2 new files in this folder. source\ and docs\ were not touched.

## 1. PASS / FAIL
| # | Check | Measured | Expected | Result |
|---|---|---|---|---|
| R1a | Forge fee tables, 8 slots | All 32 values match the draft (1H 150 / 250 / 400, L10 292) | draft 2.3 | PASS |
| R1b | Steps vs one forge | 1H 150 + 100 + 150 = 400; at L10 109 + 73 + 110 = 292. 880 step paths (every slot, RF level and route): 0 mismatches | equal | PASS |
| R1c | Runeforge upgraded between steps | 1,760 cases. The total always sits between the one-forge price at the first and at the last RF level (0 outside) | between | PASS |
| R1d | Swap fee | 1H 75 / 125 / 200, at L10 54 / 91 / 146. All 32 slot values match | draft | PASS |
| R1e | T1/T2 "same total", never downgraded | 1H Common→Epic L1-99 = 29,996 (29,596 + 400) four ways (forge at L1, at L99, in steps, all at once); at RF10 29,888. 2H 44,995 · Body 23,997 · Gloves 14,998. Mixed discount 28,125 = 28,125. 24,000 random routes: 0 mismatches | exact | PASS |
| R1f | T3, no downgrade route cheaper | 15,754 random downgrade routes with fees, swaps and RF upgrades: 0 cheaper, smallest gap 0g, mercury gap ≥ 0, at most 6 record pairs. Example: 21,291 / 14,820 / 14,820 vs straight 12,662 (each +400 from the fee). Control "reset to 0": 215 routes cheaper, worst −14,697g, so it fails as it should | ≥ straight | PASS |
| R1g | Facility spending with crafting at the new fees | Free player 5-7 of 10 facilities maxed, 108.9-111.7% (was 4-6/10, ~113%). Boosted 10/10, 85.4-88.5% (was ~89%) | report | INFO (lower than before) |
| R2 | Mercury wall | 75% dismantled 15.85 · 100% dismantled 18.87 full levellings | 15.9-18.9 | PASS |
| R3 | Daily events | Table in Section 3. 100% dismantling passes 20 at **23 events** (exactly 20.0 at 22.2) | about 20 | PASS (estimate a bit low) |
| R4a | Black Market loops | 10,072 buy routes: best −344g (Rare Gloves L1 buy → sell). Mercury best 0, crystals −11 per cycle, gems never more, sulfur 0 | no loop | PASS |
| R4b | Boosted Epic supply L50-80 ≤ 20 | 75/25: up to 21.7 at 1%, 26.6-27.0 at 2-3%. Rare 100: 20.1 at 1%, 23.5 at 3% | ≤ 20 | **FAIL** (see note) |
| R5 | Fortune clamp | 300,000 random builds (gems, Lucky, Fountain, Idol, Thief, both readings): at most ×2.00 loot / ×1.50 gold, never below ×1.00. No loop past the cap | holds | PASS |

## 2. Loops
- **None found.** Gold only goes into items. The only way back to gold is selling, and a Black Market item sells for 8.3% (Rare) or 5.6% (Epic) of what it cost.
- Mercury, crystals, gems and sulfur still cannot be sold, so no route through them returns gold.
- **One condition for R5:** the Thief bonus (doctrines 11) is added "for that reward only", later than the team value. If the code clamps before it and not again after it, loot reaches ×2.79. The draft's "after EVERY bonus" covers this, but the Dev must re-clamp after Thief.

## 3. R3 — daily events (5 mercury each, 1 sulfur per 3 completed)
| Events | Mercury wall, 75% / 100% dismantled | Lifetime sulfur, 75% / 100% | Legendary rerolls |
|---|---|---|---|
| 0 | 15.85 / 18.87 | 13.7 / 15.2 | 6.8 / 7.6 |
| 10 | 16.36 / 19.38 | 16.7 / 18.2 | 8.3 / 9.1 |
| 20 | 16.87 / 19.89 | 19.7 / 21.2 | 9.8 / 10.6 |
| 50 | 18.40 / 21.42 | 29.7 / 31.2 | 14.8 / 15.6 |

- Passes 20 levellings at **23 events** with 100% dismantling, and at **82 events** with 75%.
- The sulfur counter rounds down as intended: 2 events → 0, 3 → 1, 10 → 3, 50 → 16.

## 4. R4 — paid Black Market (price = Merchant × 75%, item level = map level)
**Gold per resource (average over the 8 slots)**
| Map level | BM 75/25: per crystal / per gem | BM Rare 100: per crystal / per gem | BM Epic slot: per crystal | Merchant Rare average / cheapest per crystal | Merchant cheapest per gem |
|---|---|---|---|---|---|
| 20 | 481 / 462 | 401 / 359 | 642 | 535 / 345 | 245 |
| 50 | 690 / 663 | 575 / 515 | 921 | 767 / 495 | 352 |
| 80 | 900 / 864 | 750 / 672 | 1,200 | 1,000 / 645 | 459 |
| 99 | 1,032 / 991 | 860 / 771 | 1,376 | 1,147 / 740 | 526 |

- Each object holds 13.5 crystals, 14.1 gems and 1.5 Epics (75/25 mix), or 12 crystals and 13.4 gems (Rare 100).
- Buying all 6 at L50 costs 9,321g (75/25) or 6,904g (Rare 100).
- Slot for slot, the Black Market is always 25% cheaper than the Merchant. For example, Rare Gloves at L50 cost 371g per crystal against 495g at the Merchant.

**Boosted Epic supply, L50-80** (crafter and rusher; the range is 75-100% dismantling; "buy" means every gold coin left over after facilities goes to the BM)
| Spawn per battle | 75/25, buy all | 75/25, buy Epics only | Rare 100, buy all |
|---|---|---|---|
| none | 15.0-16.9 | — | 15.0-16.9 |
| 1% | 19.8-21.7 (10/10 facilities) | 17.5-19.4 | 18.2-20.1 |
| 3% | 24.3-27.0 (8-9/10) | 22.1-24.1 (10/10) | 20.9-23.5 (8-9/10) |
| 5% | 24.3-27.0 (runs out of gold) | 26.5-28.8 (8-9/10) | 20.9-23.5 |

- **Note on the FAIL:** the 20 limit is already broken without any Black Market.
  - A boosted player who spends the same spare gold on Merchant Epics reaches **23.6-25.8** (8.6-8.9 bought, 8-9/10 facilities).
  - That route was not modelled last run.
  - So the Black Market's Epic slots are a 25% discount on Epics that can already be bought, not a new source.
- Ways to stay at 20 or below (maximum case, from the lever sweep):
  - only 3 items per object at 1% spawn: 18.5-19.4, whatever the mix
  - Rare 100 with 3 items at 2%: 20.1
  - Raising the price from 75% to 90% changes the result by 1.3 Epics at most, because spare gold is not the limit.

## 5. R5 — Fortune (cap: Expedition Fortune 0-1.75)
**Fortune lines needed to reach the cap** (fewest lines, split over 3 units; at most 7 per unit; normal L99 LUK ≈ 30)
| Setup | (a) flat +X to Unit Fortune | (b) Unit Fortune × (1 + X%) |
|---|---|---|
| Gear only, LUK 30 | **9 × T4** (7 + 1 + 1) · 14 × T3 · never with T1/T2 | **never**: at most ×1.31; it needs LUK ≥ 143 on all 3 units with 7 × T4 each |
| Gear only, LUK 100 | 6 × T4 on one unit · 9 × T3 · 19 × T2 | never (at most ×1.80) |
| + Lucky (Greater) on all 3 | 7 × T4 · 10 × T3 | never at LUK 30; 12 × T4 at LUK 100 |
| + Fountain or Idol of Fortune | **4 × T4** · 5 × T3 · 7 × T2 (LUK 30); 2 × T4 at LUK 100 | Idol: 14 × T4 at LUK 60, 5 × T4 at LUK 100; Fountain: never |

**Income, normal team vs cap** (90% dismantling, new mercury values)
| | Loot | Gold | Drops | Crystals | Gems | Sulfur | Mercury |
|---|---|---|---|---|---|---|---|
| Normal (LUK ~30, no lines) | ×1.13 | ×1.065 | 237 | 320 | 229 | 15.6 | 1,818 |
| At the cap | ×2.00 | ×1.50 | 356 | 466 | 386 | 23.0 | 2,395 |
| Ratio | — | ×1.41 | ×1.50 | ×1.46 | ×1.69 | ×1.47 | ×1.32 |

**Feedback loop** (100 runs; Fortune makes more drops, which give more Fortune gems)
| Scenario | (a) | (b) |
|---|---|---|
| Natural gems only (about 12 Fortune gems per lifetime) | never reaches the cap; ends at ×1.53 (p90 ×1.73) | ends at ×1.18 |
| + Lucky (Greater) on all 3 | 1% of runs reach the cap (L86) | ×1.40 |
| + 2 shop-dismantled items per battle | 65% of runs reach the cap (median L81) | ×1.25 |
| + both | 100% of runs reach the cap (median L60) | ×1.53 |
| Highest value ever | ×2.000 (×2.40 without the clamp) | ×1.58 |

- **No loop goes past the cap in either reading.**
- Reading (a): gear Fortune fills the cap fast (9 lines, or 4 with a shrine), and Fortune above the cap is wasted.
- Reading (b): gear Fortune is weak and only works with high LUK.

## 6. Numbers that look off (suggestions only, nothing changed)
| Item | Issue | Suggested |
|---|---|---|
| Draft 3.4 "Rare 1H at L50 ≈ 575g per crystal" | 575 is the 8-slot average for Rare 100. A 1H Rare is 742g, and the proposed 75/25 mix averages 690g. "Not cheaper than the cheapest Merchant" holds only when comparing the BM average with the Merchant's cheapest item | "575-690g per crystal on average; always 25% below the same Merchant item" |
| Draft 3.1 "above about 20 events" | It is 23 events (exact 20.0 at 22.2) | "about 22-23 events" |
| Accepted "boosted 14-20 Epics" | Only true for crafted Epics; spare gold on Merchant Epics already gives 23.6-25.8 | Restate as "crafted only", or about 24-27 counting bought Epics |
| Black Market 75/25 | Adds 2.4 / 7.1 / 11.9 Epics at 1 / 3 / 5% spawn | If the 20 limit matters: Rare 100 or Epic ≤ 10%, with 3 items or spawn ≤ 1-2% |
| Swap fee vs rarity raise (information) | A raise is cheaper in gold than a later swap (U→R 100g < Rare swap 125g; R→E 150g < Epic swap 200g). Crystals cost the other way (6 vs 4, 12 vs 8). Not a loop | Optional: swap ×0.375-0.40 instead of ×0.5 |
| Gear Fortune target (open Q) | (a) caps a team with 9 T4 lines; (b) almost never reaches it | If (a) and the cap should need a full Fortune team: limit Unit Fortune to 1.0 per unit → 15 × T4 (5 + 5 + 5) at LUK 30 |

## 7. Delta vs the previous run
- **Resolved:**
  - T12 now PASS (was 18.9-21.9).
  - T14 with crafting fell from ~113% to 109-112% (free) and from ~89% to 85-89% (boosted).
  - Draft G9 (the fee was charged per forge) is closed.
- **New:**
  - The R4 Epic supply is above 20.
  - Merchant Epic buying already breaks the 20 limit.
  - The Thief re-clamp condition.
- **Corrected from the last report:**
  - T18 mercury at the cap was 2,696 with the old kill and dispatch values; it is 2,395 now.
  - The natural Fortune loop under (a) was ×1.39; it is ×1.53 now. This run models gems one by one and puts no 1.0 limit on each unit, which matches the draft text.
- **Unchanged:** all DB values used.

VERDICT: SIMULATION CLEAN — no loops, no cap break, every equality holds. 1 target FAIL (R4: boosted Epic supply above 20 with the Black Market, and already above 20 through the Merchant) and 1 estimate slightly off (R3: 23 events, not ~20).

Files: `D:\AI\Projects\CTRBLXAI\sim\runeforge_v2_2026-11-01\report_recheck_v2_2026-11-01.md`, `…\results_recheck_v2.json`. Source and docs untouched.
