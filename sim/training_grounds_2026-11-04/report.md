# SIMULATION RUN — 2026-11-04 — Training Grounds (Training Ground + Library merged into one card shop)
Seed: 20261104 (shelf Monte Carlo check uses 20261104; card baskets use 20261105). A re-run gives the same output.
DB: opened read-only. md5 c0e4afdf… at start and end (unchanged during the run). It changed since 2026-11-03 (d2cda0a8…) because of parallel Designer work. Every row I asserted is still present.
Model: the 2026-11-03 Apothecary economy model, reused unchanged (it reuses the 2026-11-02 Crucible and 2026-11-01 v2 economy timeline). **Reproduced exactly:** 11 facilities, normal refills: free 115.0 / 117.5%, boosted 89.0 / 90.9% (crafting from Rare / from Common).
The Luau catalog-count block of the old prefix was cut out. **This run read no source files.**
Proposal: training_grounds_design_options_20261104.md (Designer thread-9ad5713d2a62). **Not in the DB.** Its C4 price table matches the formula exactly (0 mismatches out of 35 cells).
Content: 116 skill cards (Raise Dead is event-only, so it is left out), 102 augments (status Working; 7 Rejected and 2 Parked left out), 34 doctrines. All counts come from the DB. The rarity split comes from the proposal: skills 78/31/7, augments 51/33/18 (the augment split was checked against the DB's family counts).
Bands: map levels 1-99 over the 547-battle run. Bands 150-300 are not tested, because nothing in this proposal applies past 99.
Files: tg_sim.py, results_tg.json, FORMULAS_tg.md, this report (all in sim\training_grounds_2026-11-04\). Nothing in source\ or docs\ was changed.

## Assumptions (plain; none of these is a target)
- **Card loot rate:** 0.22 skill cards + 0.22 augment cards per battle, each picked evenly. This is the Designer's figure taken from the game code. **It is not in the DB**, so I used it as given.
- **What players buy (not in the DB):**
  - **Designer basket:** 9 skills, 12 augments and 2 doctrines spread over the battles before L80. Then 24 augments over the 100 battles after slot 2 opens, but only if it opens.
  - **Double basket:** twice the Designer basket.
  - Card rarity follows the catalogue mix. A card waits until its rarity and type are unlocked.
  - Cards are bought **before** facilities. The "facilities first" order was also run; it changes little.
- **Selling loot cards:** run both ways, selling every loot card or none. Doctrine loot is display-only, so it gives 0.
- **Refills:** "normal" usage (10% of battle gold), the same as the 2026-11-03 run. A heavy (20%) version was also run.
- **Unit level:** from the DB XP rows. Mixed quests (3 Grunts + 2 Veterans), enemy level = unit level, no objective bonus.
  - This gives exactly **547 battles to L99**, matching economy_framework 42.
  - A deployed unit hits **L80 at battle 428**. A benched unit at 65% hits it at battle 488. Map L80 is battle 441.
- **Party:** 6 units × 4 skill rows (Designer figure). Enemy skill rows: 4 each (Designer figure).
- **Enemy augments:** "Elite = 2 per row today" and the enemy tier makeup come from the proposal and code. **They are not in the DB** (open_decisions 56: TIER_BUILD lives in code).
- **Spending %** = (necessities + facilities + crafting + refills + cards bought + cards wanted but not afforded − card sales) ÷ lifetime income. That is the same measure as before. Over 100% means a free player can't do everything.

## SECTION 1: BLOCKERS
- **No combat model of augments exists.** engine.py has no augments and no skills. So **win rates for Q4 and Q5 can't be measured.** I report augment counts instead.
- The loot card rate and the enemy tier makeup are not in the DB (see the assumptions above).

## SECTION 2: CRITICAL FINDINGS
None. No gold loop, no card above 10 battles of gold, and basics stay affordable. Cards are optional, the Library's cost goes away, and card sales add gold.

## SECTION 3: RESULTS
### Q1. Total spending and facilities maxed (10 facilities, 70,927g; crafting from Rare / from Common)
| Player, build order | No cards, no sales | No cards, sell loot cards | Designer basket + sell loot | Designer basket, no sales | Double basket + sell |
|---|---|---|---|---|---|
| Free, classic (Training Grounds after Runeforge + Crucible) | 111.4 / 114.0%, 6/10 | 106.0 / 108.5%, 8 / 7 of 10 | 117.9 / 122.1%, 8 / 7 of 10, **0 cards bought** | 125.0 / 127.5%, 6/10 | 129.7 / 133.7% |
| Free, Apothecary first | 110.1 / 112.4%, 7 / 6 of 10 | 105.1 / 107.4%, 8 / 7 of 10 | 117.0 / 121.0%, 8 / 7 of 10, 0-1.9k bought | 123.6 / 126.0% | 127.3 / 132.7% |
| Free, Training Grounds rush | 114.4 / 117.4%, 4 / 3 of 10 | 108.6 / 111.4%, 7/10 | 125.4 / 128.6%, **2/10**, 19.0-20.7k bought | 125.0 / 127.7%, 0-2 of 10 | 127.7 / 130.6%, 0/10 |
| Boosted, classic | 86.2 / 88.0%, 10/10 | 82.3 / 84.1%, 10/10 | 94.5 / 96.5%, 10/10, 26.8-27.2k bought | 98.8 / 101.1%, 10/10 | 106.4 / 108.4%, 10/10 |
| Boosted, Training Grounds rush | 88.1 / 90.0% | 84.2 / 86.0% | 95.0 / 96.9%, 10/10 | 99.1 / 101.1%, 10 / 9 of 10 | 104.8 / 107.1%, 8 / 7 of 10 |

- **Merging Library into Training Grounds:** −3.6 points for free players (115.0 → 111.4%) and −2.8 points for boosted players (89.0 → 86.2%).
- **Selling every loot card:** +7,948g over the lifetime (4.5% of income, 14.5g a battle at map 50), which is −5.4 points. The Designer estimated 7-8k; this confirms it.
- **Designer card basket:** +12 to +14 points if fully bought. The Designer estimated "a few points"; it is more than that.
- **In the classic order a free player owns the shop only at the very end** (Training Grounds L1 at battle 536, or never). They want those cards but can't buy them. That is why the 117.9% shows 0 cards bought.
- **Heavy refills** add about 3-7 points on top.

### Q2. Do free players reach Guild Hall 10 + Training Grounds 10 before their units hit L80 (battle 428)?
| Player, build order | Guild Hall 10 | Training Grounds 10 | Slot 2 opens |
|---|---|---|---|
| Free, classic | battle 386-474 | **never** (Training Grounds ends at L0-5) | **never** |
| Free, Apothecary first | 200-241 | **never** (ends at L0-7) | **never** |
| Free, Training Grounds rush, no cards | 268-364 | **300-385 (before L80)** | **428** (at L80). Cost: 3-7 of 10 maxed instead of 6-8 |
| Free, Training Grounds rush + Designer basket + sales | 438-484 | 468-497 (40-70 battles after L80) | 469-498. Only 2/10 maxed |
| Free, same, no card sales | – | never (ends at L8-9) | never |
| Boosted, classic | 242-262 | 389-466 | 428-467 |
| Boosted, rush | 145-209 | 157-272 | 428 |

- **Answer:** free players open slot 2 only if they rush the Training Grounds and skip most other facilities. In the normal orders they never do.
- When slot 2 does open at battle 428, it is used for the last 119 battles of the 1-99 run (22%), plus play after 99.

### Q3. Restocks (every 5 battles) to see one specific card
A specific card's chance per restock = card slots × rarity odds ÷ cards in that rarity pool. A seeded Monte Carlo check agrees to within 0.1 points.

| Training Grounds level | Rare | Epic | Legendary | Doctrine |
|---|---|---|---|---|
| L4 (Rare pool 129, Epic pool 64) | 3.3% per restock: about 30 restocks (152 battles); 50% chance by 21, 90% by 69 | 1.2%: about 85 restocks (427 battles); 50% by 59, 90% by 196 | – | – |
| L8 (Legendary pool 25) | 2.6%: about 39 (195 battles) | 3.3%: about 31 (152) | 2.4%: about 42 (208); 50% by 29, 90% by 95 | 2.9%: 34 (170) |
| L10 | 2.4%: about 41 (205 battles); 50% by 29, 90% by 94 | 3.8%: about 26 (131); 50% by 18 | 5.6%: about 18 (89); 50% by 13, 90% by 40 | 2.9%: 34 (170); 50% by 24, 90% by 78 |

- **Loot alone:** a specific augment drops about once every 464 battles (1.18 copies over a lifetime). A specific skill drops about once every 527 battles.
- **Rare gets harder to find at higher levels** (30 → 41 restocks), because Rare odds fall from 85% to 45% while the pool stays at 129.
- **Epic at L4-5 is very slow** (85 and 43 restocks).
- **Restocks left after Training Grounds 10:** a free rusher (battle 300-385) has about 32-49 restocks left. A boosted classic player (about battle 400) has about 29.

### Q4. Below L80: player 4 vs 8 augments, Elites 1 vs 2 (counts only; win rate can't be measured)
- **Player, loot only (6 units × 4 rows):**

  | Unit level (battle) | Augments owned | Equipped, new rule (cap 24) | Equipped, old rule (cap 48) |
  |---|---|---|---|
  | L25 (110) | 28 | 24 | 28 (−15% under the new rule) |
  | L50 (247) | 58 | 24 | 48 (−50%) |
  | L79 (421) | 97 | 24 | 48 (−50%) |

  - The new 24 cap is reached at battle 91 (about unit L22). The old 48 cap would be reached at battle 200 (about L42).
  - So **from about L42 to L79 a full team carries half the augments it would under today's rules.** The buying basket doesn't change this; the cap binds either way.
  - Fit rules are ignored, so real equipped counts are a little lower.
- **Enemies (rule off, every level):**

  | Battle | Enemy augments today | Enemy augments new | Change |
  |---|---|---|---|
  | Elite rows | 2 per row | 1 per row | −50% |
  | Elite encounter (1 Elite + 3 Grunts + 2 Veterans) | 28 | 24 | −14% |
  | Hard battle (2 Elites + 3 Grunts, assumed) | 28 | 20 | −29% |
  | Normal battle | 20 | 20 | 0% |

- **Augments per side, normal battle:** player : enemy goes from 48:20 to 24:20 once loot fills the slots. In elite battles it goes from 48:28 to 24:24.

### Q5. L80+ with the enemy rule (Elite 100%, Veteran 50%, Grunt 25%)
| Battle | Rule off | Rule on | Change | Player slots (off → on) |
|---|---|---|---|---|
| Normal | 20 | 27 | +35% | 24 → 48 (+100%) |
| Elite encounter | 24 | 35 | +46% | 24 → 48 |
| Hard (assumed) | 20 | 31 | +55% | 24 → 48 |

- **Augments per side, normal battle:** player : enemy goes from 24:20 (off) to 48:27 (on).
- **Edge case:** the rule follows the quest owner's Training Grounds, while slot 2 needs each unit to be L80. A benched unit (65% XP) hits L80 at battle 488, 60 battles after deployed units. During that window an under-80 unit carries 24 augments against 27-35 for the enemies.
- **Free players in the normal orders never turn the rule on.** For them, L80+ fights stay at the lower Elite count all game.

### Q6. Buy-then-sell loop (7 card rows × discount 0-27% × buy map 1-99 × sell map ≥ buy map = 346,500 cases)
- **0 cases make gold.** The best case is −82g: a Rare augment bought at Training Grounds L10 at map 1 and sold at map 95.
- The most you can get back is **25.3% of what you paid**. The Designer's 18.5% is measured against the list price; against the discounted price you actually pay, it is 25.3%. **Still always a loss.**
- **Starter cards** are free gold if sold: 126g at map 1, 384g at map 99. That's a one-time amount, not a loop.

### Q7. Card prices in battles of gold (model battle gold: 160 / 215 / 302 / 389 / 444g at map 1 / 20 / 50 / 80 / 99)
| Card | List price, in battles | At Training Grounds L10 (−27%) |
|---|---|---|
| Augment R / E / L | 0.94-1.0 / 1.5-1.6 / 2.6-2.8 | 0.7 / 1.1-1.2 / 1.9-2.0 |
| Skill R / E / L | 1.6-1.7 / 2.5-2.7 / 4.4-4.7 | 1.1-1.2 / 1.8-2.0 / 3.2-3.4 |
| Doctrine | 6.3-6.7 | 4.6-4.9 |

- **Nothing is above 10 battles.** The highest is a doctrine at map 99: 6.67 battles.
- The Designer used 248g per battle at map 50, a little below the model's 302g. Even on that figure the doctrine is about 8 battles, still under 10.

### Q8. Dropping the benched-XP bonus that was never built
- **No benchmark moves.** The bonus was never built, and no model (XP v2, economy, Apothecary, Crucible) ever used it.
- The locked 65% (unit_progression 52) stays as it is.
- **What it would have done:** at 85% a benched unit would reach L80 at battle 456 instead of 488, which is 32 battles sooner. At 67% it would be 2 battles sooner.

## SECTION 4: OUTLIERS
| Entry | Class | Evidence |
|---|---|---|
| Training Grounds rush (free) | Niche, the only free route to slot 2 | Slot 2 at battle 428, but 3-7 of 10 facilities maxed (2/10 if cards are bought too) |
| Epic shelf at Training Grounds L4-5 | Near-trash for targeted buying | 85 / 43 restocks for a specific Epic |
| Doctrine slot | Healthy | Same 170-battle average at every level from L6 |

## SECTION 5: COMBINATIONS
- **Cheapest card:** a Rare augment at Training Grounds L10, map 1: 109g.
- **Most expensive:** a doctrine at map 99: 2,960g (6.67 battles).
- **Fastest slot 2:** a boosted rusher gets Training Grounds 10 at battle 157-272, but slot 2 still waits for the unit (L80 = battle 428; 389 for a Human, who gets +10% XP).
- **No absolutes:** no loop, no zero price, no free card source apart from loot and starters.

## SECTION 6: HEALTHY
- No buy/sell loop in any case.
- Every price is under 10 battles.
- Boosted players still max 10/10 with the Designer basket (94.5-97.0%).
- Card sale income (4.5%) is in line with gear selling.
- The merge lowers facility spending by 6,277g.
- The benched-XP change moves nothing.

## SECTION 7: DELTA vs apothecary_2026-11-03
- **New:** 10 facilities (−3.6 points for free players), card selling (−5.4 points), card buying (+12 to +14 points with the Designer basket).
- **Unchanged:** the 11-facility numbers reproduce exactly.
- **DB:** md5 changed (Designer work). Every row I asserted is still present.
- **Proposal vs. this run:**
  - The proposal said spending rises "a few points"; it is +6.5 to +8 points net (sales included) over the 10-facility baseline with no cards.
  - The best sale return is 25.3% of the price paid, not 18.5%.

## Decision
**No change needed.** Nothing breaks.

One plain fact for the user to rule on (it's a design call, not a fix): with these numbers, free players open the 2nd augment slot only by rushing the Training Grounds. In the normal build order they never own more than a Training Grounds L0-7, so they also barely use the card shop.

VERDICT: SIMULATION CLEAN — no critical findings across map levels 1-99. Highest-value note: free players get slot 2 only through a Training Grounds rush (battle 428, at the cost of 3-7 facilities maxed instead of 6-8).

Files modified: sim\ only. Source and docs untouched.
