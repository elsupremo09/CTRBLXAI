# SIMULATION RUN — 2026-11-03 — Apothecary (paid refills) economy check
Seed: 20261103. The model is fully deterministic (no random rolls), so a re-run gives the same output.
DB: opened read-only, with retry-on-lock. md5 d2cda0a8… at both start and end. It changed since 2026-11-02 (ea957228…) because of parallel Designer work. Every row I asserted is still present.
Formulas/rows: the 2026-11-02 economy model was reused unchanged (54 rows + 10 Crucible rows), plus 16 new rows asserted today and the Apothecary rules from the user decision. The Apothecary is **not in the DB yet**. See FORMULAS_apothecary.md.
Content: all 137 consumables in consumable_items. All 137 prices match the formula in consumable_framework 30-32.
Bands: map levels 1-99 over the 547-battle run. Bands 150-300 don't apply, because consumable prices have no level.
Files: apothecary_sim.py, results_apothecary.json, FORMULAS_apothecary.md, this report (all in sim\apothecary_2026-11-03\), plus a pointer line in sim\FORMULAS.md. Nothing in source\ or docs\ was changed.

## Assumptions (stated plainly; none of these is a target)
- **Usage is not in the DB.** The DB has two anchors:
  - consumable_framework 36: a 4-charge item lasts about 4 battles.
  - economy_framework 27 and consumable_framework 38: consumables are about 10% of income.
- So I define usage as **the shop value of the charges used up in one battle**:
  - **Light** = 5% of that battle's gold.
  - **Normal** = 10% (the DB anchor).
  - **Heavy** = 20%.
- Two other versions are also run:
  - **Flat:** 30g or 60g of charges per battle, which weighs more in the early game.
  - **Stress case:** the design doc's example squad, 87.5g per battle.
- **Normal in item terms:** 30g a battle is about 2.4 Common Routine charges, or 1.2 Common Standard, or 0.6 Rare Standard.
- **Boosted players** use the same items as free players.
- **Buying:** the 17,500g already counted for buying consumables (economy_framework 43) stays, and the Apothecary buy discount reduces it.
- **Old model reproduced exactly:** free 112.5 / 115.0% and boosted 88.2 / 90.1% (crafting from Rare / from Common).
- **Battle gold** per battle: 160g at map 1, 229g at map 25, 302g at map 50, 444g at map 99 (average 302g).

## SECTION 1: BLOCKERS
None for the questions asked. One side item can't be measured: the DB has no consumable loot drop rate, so I can't put a number on gold from selling looted consumables at 20%.

## SECTION 2: CRITICAL FINDINGS
None.

## SECTION 3: RESULTS
### Q1. Refill gold per battle (average battle, 302g)
| User | Apothecary L0-1 (75%) | L5 (53%) | L10 (25%) |
|---|---|---|---|
| Light (5%) | 11g = 3.8% | 8g = 2.7% | 4g = 1.3% |
| Normal (10%) | 23g = 7.5% | 16g = 5.3% | 8g = 2.5% |
| Heavy (20%) | 45g = 15% | 32g = 10.6% | 15g = 5% |
| Stress case (87.5g flat) | 66g = 22% | 46g = 15% | 22g = 7% |

- **Share-based usage gives the same % at every map level.** That follows from how it is defined: usage is a share of battle gold.
- **Flat usage hits the early game hardest**, because consumable prices don't grow but battle gold does.
  - Flat normal (30g) at L0-1: 14% of a map-1 battle, 10% at map 25, 5% at map 99.
  - Stress case: 41% at map 1 and 29% at map 25.
- **Starter potions:** each Small Healing Potion or Ether Cell charge used (Common Routine, 50g, 4 charges) costs 9.4g to refill before the Apothecary exists. That is 5.9% of a map-1 battle.
- **When the Apothecary arrives (free player):**
  - Built in the normal order: L1 at map 16-28, L10 at map 75-98.
  - Built right after the Guild Hall allows it: L1 at map 7-14, L10 at map 40-56.

### Q2. Lifetime gold (share of lifetime income; Apothecary in the core six / built first)
| | Refill gold over the lifetime | Total spending | Facilities maxed |
|---|---|---|---|
| Free, old Workshop rules (repro) | 0 | 112.5% | 7/11 |
| Free, light | 2.6-3.3k (1.5-1.9%) | 111.9-112.6% | 7/11 |
| Free, normal | 5.4-6.8k (3.1-3.9%) | 113.6-115.0% | 6-7/11 |
| Free, heavy | 11.8-16.1k (6.7-9.2%) | 117.6-121.0% | 3-6/11 |
| Free, flat heavy 60g | 16.0-18.9k (9-11%) | 120.5-123.0% | 3-4/11 |
| Free, stress case | 35.9k (20%) | 138% | 0/11. Cash goes negative at map 24 |
| Boosted, light to heavy | 2.3-11.2k (1.1-5.1%) | 87.7-92.0% (repro 88.2%) | 11/11 |
| Boosted, stress case | 16.9-20.6k (7.7-9.4%) | 95-97% | 11/11 |

- The table rows are for crafting from Rare. Crafting from Common adds about 2.5 points to every row.
- **The buy discount gives back 2.5-4.4k** over a lifetime. That is why the light user ends up even or slightly better off than under the old rules.
- **Do free players still afford the basics?** The DB rule is "Basics always affordable" (economy_framework 1).
  - **Yes for light, normal and heavy.** Necessities plus refills come to 65-77% of income, and cash never drops below 0.
  - **No only for the stress-case squad.** Necessities plus refills reach 91%, and cash goes negative at about map 24 (−722g). In the game that means the gold-short rule kicks in and refills are skipped.
  - What heavy users lose is luxury facilities, not basics. In the normal order, a heavy free user also leaves 3 of the core six unmaxed.
- **Payback (normal user):**
  - Each level pays back in 64 (L2) to 300 (L10) battles.
  - The full L1→10 investment pays back in 174 battles (light 255, heavy 106), out of 547.
  - L1 itself saves nothing, because the rate is already 75% before the building exists.

### Q3. Loop search (all 137 items × levels 0-10 × every charge count; both roundings; both readings of the L9 rule)
| Test | Best case | Loop? |
|---|---|---|
| Buy, then sell | −13g | No |
| Buy, use, refill, sell | −20g | No |
| Refill an owned empty item, then sell it | −1g (5-charge item at L9-10) | No |
| Sell a used item and buy a new one, instead of refilling | refill is always cheaper (by at least 6g) | No |
| Refill one charge at a time instead of all at once | never cheaper (0g) | No |
| Apothecary discount stacking | the buy discount doesn't touch refills. Merchant's Turban (HD-018) works only in battlefield shops. No other consumable price modifier exists in the DB | No |
| L9 charges + cheaper refill | see below | No (it's a discount, not a loop) |

- **The tightest margin is the 5-point gap** between the L10 refill rate (25%) and the sell rate (20%). Rounding keeps it at −1g or worse. Raising the sell rate to 25% or more, or lowering any refill rate to 20% or less, would open a loop.
- **L9 + cheaper refill:** the design says the extra charges are "paid like normal ones", which can be read two ways. For a 4-charge item, the cost per charge is:

  | Reading | L8 | L9 | L10 |
  |---|---|---|---|
  | Cost divided by the **new** max | 9.0% of price | 6.2% (−31%) | 5.0% |
  | Cost divided by the **base** max | 9.0% of price | 7.75% | — |

  This only affects the 25 items with 4-5 charges. The Designer should say which reading is intended.
- **Ways to skip paying for refills.** None of these makes gold; they only skip the bill:
  - **AC-009:** its battle-only extra charges are free. A unit using at most 1 charge per item per battle pays nothing. That saves 9-83g per item per battle at L0-1 (3-28g at L10). It was priced at 90 BP when refills were free.
  - **Restock skill** (3-11 MP) **+ stalling** (allowed by persistent_hp_mp_rules 15): the player tops up every item before the finishing blow. That saves about 56g per cast at L0-1 (3 Common Standard charges).
  - **AC-018, AC-008 and the Potion Desk** also refill for free in battle.
  - Whether AC-008, AC-009 and AC-018 are actually built in code was not checked; that is the Tester's job.

## SECTION 4: OUTLIERS
| Entry | Class | Evidence |
|---|---|---|
| Building the Apothecary first | Best build order (healthy, worth a tooltip) | Every usage level does better. Free normal: 113.6% vs 115.0%. Free heavy: 6/11 vs 3/11 maxed |
| AC-009 Reinforced Cartridge | Niche → stronger | It now also saves 9-83g of refill gold per item per battle |

## SECTION 5: COMBINATIONS
- **Lowest refill bill:** Apothecary L10, plus AC-009, plus Restock while stalling. The bill can reach 0g per battle; the only cost is time.
- **Highest refill bill:** the stress-case squad before the Apothecary exists, at 41% of a map-1 battle.
- **No absolutes:** no gold loop and no negative cost.

## SECTION 6: HEALTHY
- No loop through buy, sell or refill, for any item, level or charge count.
- Refilling is always cheaper than buying new, at every level.
- Building never makes refills cost more (L0 = L1 = 75%).
- Boosted players still max 11/11 at every usage level tested.
- Basics hold for light, normal and heavy users.

## SECTION 7: DELTA vs crucible_2026-11-02
- **New:** paid refills (+1.5 to +9.2% of lifetime gold for free players), the buy discount (−1.4 to −2.5%), and the build-order effect.
- **Unchanged:** the 11-facility total (77,204g); the old-rules numbers reproduce exactly.
- **DB:** md5 changed since the last run (Designer work); every row I asserted is still present.
- **Small DB mismatch:** consumable_items has 137 items (Rare 79, 38 one-charge, 31 three-charge), but consumable_framework 29 and the design doc say 140. The count of items L9 helps (25) is the same either way.

## Q4. Decision
**No change needed.** The DB's own rule (basics always affordable) holds for light, normal and heavy users. A normal free player pays about 3-4% of lifetime gold, minus 2-2.5% back from the buy discount. The only failure is the stress-case squad (87.5g of items per battle, from the design doc's example), which can't keep up before map 24.
- Two open points for the Designer (not knobs): which L9 reading applies, and whether AC-009's free charges are intended now that refills cost gold.

VERDICT: SIMULATION CLEAN — no critical findings across map levels 1-99. Highest-value note: building the Apothecary first is the best order for every player, and the only usage that breaks the basics is the stress case.

Files modified: sim\ only. Source and docs untouched.
