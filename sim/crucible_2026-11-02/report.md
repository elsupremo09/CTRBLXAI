# SIMULATION RUN — 2026-11-02 — Crucible (gear merging) lifetime check
Seed: 20261102 (Monte Carlo, 300 lifetimes per case, fixed seeds). A re-run of one case gave an identical result.
DB: opened read-only. md5 ea957228… at the start and at the end (no write during the run; the DB has changed since the 2026-11-01 run, 7ea3fde2…). All asserted rows passed.
Formulas/rows loaded: 54 from the 2026-11-01 runs + 10 new DB rows + 8 Crucible rules from the design snapshot (the Crucible is **not in the DB yet**). See FORMULAS_crucible.md.
Content simulated: 146 equipment archetypes (code pools), and 156 (DB catalog) as a sensitivity check.
Level bands: item levels 1-99 along the 547-battle timeline. Bands 150-300 are not applicable, because item and map level stop at 99.
Files: crucible_sim.py, crucible_extra.py, results_crucible.json, results_extra.json, FORMULAS_crucible.md, design_snapshot_…md, this report. All are in sim\crucible_2026-11-02\. sim\FORMULAS.md got a pointer. source\ and docs\ were not changed.

## Model (reused from daily_systems_2026-11-01)
- **Battles and wins:** 547 battles, 90% wins.
- **Drops:** 0.40 drops per battle, on wins only. The normal loot table includes Exalted at 2.5% (loot_progression 84).
- **Elites:** 0.034 per battle, 75% chance of an item.
- **Bosses (B4 + daily 3):** card weight 3, 3 rewards a day, boss quests from battle 81. Two players:
  - **Random picker:** 13 boss wins in a lifetime.
  - **Boss hunter:** 234 boss wins (80 contracts).
  - Boss items use the elite table, Rare or better (assumption).
- **Merchant:** shelf and odds by Merchant level (economy_framework 48), restocked every 5 battles.
- **Black Market:** 3% of battles, 6 items, 75% Rare / 25% Epic, 75% of the Merchant price.
- **Facility levels over time:** the same buying logic as the v2 re-check, with the Crucible added. It reproduces the 10-facility results exactly: 108.9 / 111.4% free and 85.4 / 87.2% boosted.
- **Which base item drops:** a slot first (8 slot groups, equal chance), then an archetype within the slot. This is NOT in the DB; it is the same slot model as earlier runs.
- **Archetypes:**
  - The code pools hold **146**: 38 weapons (18 one-handed, 20 two-handed), 7 off-hands and 101 armour pieces.
  - The DB lists **156**. Ten DB off-hands are not in WeaponData: Lantern, Totem, Banner, Talisman, Prism, Kite, Skull, Net, Sheath, Wind Vane. This is for the audit agent.
  - Odds that two drops are the same base item: 1/144 (1H), 1/160 (2H), 1/56 (off-hand), 1/160-1/168 (armour).
- **Inventory assumption:** there is no hard cap. Up to 50 items are free; above that the cost is min(5 × extra items, 200g) per base visit.
  - Tested: **30 spare slots** (the 50 free slots minus about 20 kept items) and **55 spare slots** (one +25 expansion).
  - When full, the player throws out the least promising group first.
  - Unlimited spares were also tested, but they cost 69-85k gold in fees over a lifetime, so nobody would do it.
- **Buying policy:** the player buys a shop or Black Market item only if it matches a group they already hold.
  - **Free player:** no spare gold (spending is above 100%).
  - **Boosted player:** can spend their spare gold, 11.8% of income (about 25.9k over a lifetime).

## SECTION 1: BLOCKERS
None. The open points below are working assumptions and are listed in FORMULAS_crucible.md:
- how the base item is picked;
- the boss item rarity table;
- whether more than one shelf can be seen per restock window;
- the Crucible rows themselves (not in the DB yet).

## SECTION 2: CRITICAL FINDINGS
None.

## SECTION 3: RESULTS

### Q1. Lifetime merges per step (random picker unless marked)
| Player | C→U | U→R | R→E | E→Ex | Ex→L | Total |
|---|---|---|---|---|---|---|
| Free, normal build order (Crucible reaches L7 only at map 98; never built if crafting from Common), loot only, 30 / 55 spares | 0.2 / 0.6 | 0.05 / 0.1 | 0.04 | 0 | 0 | 0.3 / 0.8 |
| Free, Crucible bought early, loot only, 55 spares | 1.7 | 0.6 | 0.3 | 0.02 | 0 | 2.7 |
| Boosted, loot only, 30 / 55 spares | 0.5 / 1.8 | 0.3 / 0.6 | 0.3 / 0.4 | 0.05 | 0 | 1.1 / 2.8 |
| **Boosted, buys matching items with spare gold, 30 / 55 spares** | 1.4 / 4.6 | 2.6 / 4.4 | 3.4 / 3.2 | 0.3 / 0.07 | 0 | **7.7 / 12.3** |
| Boss hunter, boosted, loot only, 55 spares | 0 | 0.06 | 4.0 | 1.5 | 0.21 | 5.8 |
| Boss hunter, boosted, buys with spare gold, 55 spares | 0.5 | 0.8 | 6.8 | 2.4 | 0.22 | 10.6 |
| No limits at all (hunter, unlimited gold and inventory) | 20 | 21 | 72 | 25 | 2.7 | 140 (needs about 470k gold: not reachable) |

- **Copies are the limit, not the input count.**
  - With 3 inputs at every Crucible level, a boosted player doing loot only gets 1.0 merges instead of 1.1.
  - The reason: the boosted player buys Crucible L1 at map 63 and L10 at map 68, so the 5→3 input steps arrive almost together.

### Q2. Extra supply compared with normal loot
| | Epic | Exalted | Legendary |
|---|---|---|---|
| Normal loot, random picker | 13.9 | 5.6 | 1.34 |
| + Crucible, boosted, loot only | +0.4 (+3%) | +0.05 (+1%) | +0.00 |
| + Crucible, boosted, spare gold | +3.2-3.4 (+24%) | +0.07-0.30 (≤5%) | +0.00 (Exalted-only buying: +0.08-0.10) |
| Normal loot, boss hunter | 65.6 | 24.2 | **16.3** |
| + Crucible, hunter (loot only / spare gold / Exalted-only buying) | +4.0 / +6.8 | +1.5 / +2.4 | +0.21 / +0.22 / +0.72 |

- **Legendary: acceptable.** A normal player ends at about 1.4 Legendaries, inside the 2-4 target.
- The Crucible adds at most 0.1 for a normal player and 0.7 for a hunter (+4%).
- The hunter's 16 Legendaries come from boss rewards (6.8% Legendary on the assumed boss table). That existed before the Crucible.

### Q3. Crystals and sulfur
Crystal cost below = merge cost + the dismantle crystals the inputs would have given.

| Case | Crystals | Share of crystal income | Sulfur | Share of 38-40 sulfur |
|---|---|---|---|---|
| Random picker, loot only | about 8 | 3% of 226-264 | 0.06 | — |
| Random picker, spare gold | 42 + 11 = 53 | 20-23% | 0.07 | — |
| Hunter | 62-105 | 4-6% of 1,637-1,785 | 2-3 | 5-7% |

- **The Runeforge is not starved.** Per step, the crystal-equivalent cost is the same as the Runeforge:
  - Rare→Epic: 6 + 3×2 = 12 (Runeforge 12).
  - Uncommon→Rare: 3 + 3 = 6 (Runeforge 6).
  - Common→Uncommon is 1 crystal cheaper (2 vs 3).
- So a crystal spent on merging is one Runeforge Epic step not taken, by the player's own choice. There is no cheaper path.

### Q4. Gold with 11 facilities (share of lifetime income; crafting from Rare / from Common)

**Free player**
| Build order | Spending | Facilities maxed | Crucible |
|---|---|---|---|
| Normal order | 112.5 / 115.0% | 7/11 / 6/11 | Reaches L7, or is never built |
| Crucible bought early | 112.9 / 115.2% | 7/11 | L10 at map 46-47 |

**Boosted player**
| Case | Spending | Facilities maxed | Crucible |
|---|---|---|---|
| Normal order | 88.2 / 90.1% | 11/11 | L10 at map 68-69 |
| Crucible bought early | 89.4 / 91.2% | 11/11 | — |

- **Merge fees:** 74-1,386g a lifetime, which adds 0.0-0.8 points. This confirms the design doc's 113-116% / 88-92%.
- **Boosted player who buys inputs:** spends all spare gold, ending at 99.6-100.3% (10-11/11).

### Q5. Exploit search
1. **Merchant restock buy → merge → sell or dismantle: no loop.**
   - **Buying the inputs costs more than buying the result** (1H L99):
     - Common→Uncommon: 3,552g vs 1,776g
     - Uncommon→Rare: 5,328g vs 2,960g
     - Rare→Epic: 8,880g vs 7,104g
     - Epic→Exalted: 21,312g vs 9,768g
   - **Selling:** a merged item sells for less than its inputs (Rare→Epic: 296g vs 555g).
   - **Resources** cannot be sold.
   - **Black Market:** 3 Black Market Rares + the fee = 7,092g vs a Merchant Epic at 7,104g. That is 0.2% cheaper, not the 6% in the design doc, which left the fee out. It also needs 3 Black Market Rares of the same base item, which practically never happens.
   - **Copies from one shelf:** a Merchant L10 shelf shows a pair of the same base item at the same rarity on 9.6% of restocks, a triple on 0.08%, and an Exalted pair on 0.08%. So one shelf cannot supply many copies.
2. **A shelf per map level (if the build allows it):**
   - **General buying:** gold runs out first. With spare gold, 10 shelves add no high-tier merges; the gold goes on cheap matches.
   - **Buying only Exalteds:** Legendary merges rise from +0.08 to **+1.0** (random picker) and from +0.7 to +1.3 (hunter).
   - **Diverting 30% of income:** +2.0 / +3.8. The random picker would then hold about 3.4 Legendaries, at the top of the target.
   - DB row 48 ("seed + battles-completed") implies one shelf per window. → Decision 2.
3. **Downgrade, then merge: no gain.**
   - Lowering the inputs to L1 saves at most about 500g of fee (1H Legendary 756g → 255g).
   - But re-levelling that Legendary to 99 costs about 45,400g + 98 mercury.
   - Levelling the inputs first costs 1.8-3.9× more per result level than levelling the result.
4. **Boost stacking: holds.**
   - With Crucible L10, the raw result (average + boost) went up to 5 levels above the map level in every lifetime.
   - The min(map level, 99) cap clipped it every time, so chained merges never pass a fresh drop's level.
   - Tester check: the cap must be applied AFTER the boost, and against the map level, not the highest input.
5. **Buying Exalteds in the shop to merge into Legendaries: small.**
   - Cost: 3 × 9,768g + 756g + 12 crystals + 2 sulfur (1H L99). An off-hand costs 17,583g + 453g.
   - With spare gold: +0.08-0.10 Legendary for a random picker (an 8-10% chance of one in a lifetime) and +0.7 for a hunter (a 53% chance).
6. **Mercury: dismantling always gives more than merging.**
   - Each 3-input merge loses 2 × ceil(L/10) mercury (10 at L50, 20 at L99). The boost saves at most 5 levels.
   - Lifetime: −23 mercury (−0.2 levellings) loot only, −55 for a hunter, up to −120 when buying. The wall (16.7-19.4) stays inside 15-20.
7. **Sulfur and crystals:** merging Exalted→Legendary, then dismantling, loses 3 sulfur and 18 crystals. No loop.
8. **Fishing for a good roll:** the roll is fixed by the input IDs, with no preview. No exploit.

## SECTION 4: OUTLIERS
| Entry | Class | Evidence |
|---|---|---|
| Crucible (same-base rule) | TRASH-leaning NICHE | 6,277g for about 3 merges a lifetime from loot (boosted), and about 12 if all spare gold (about 26k) goes into it. A free player in the normal order never gets past L7. |
| Exalted→Legendary for boss hunters | NICHE (healthy) | +0.7 Legendary on top of 16.3 from boss rewards |
| Boss reward Legendaries (pre-existing, not the Crucible) | Watch | 16.3 per lifetime for a hunter, on the assumed boss table |

## SECTION 5: COMBINATIONS
- **Most Legendaries:** boss hunter + 10 shelves + 30% of income on Exalteds = 16.3 + 3.8, about **20**. Almost all of it comes from boss rewards.
- **Most crystals spent on merges:** the no-limits hunter, 762 + 355 crystals. That needs about 470k gold, which is not reachable.
- **Nothing reaches an absolute:** no gold, mercury, crystal or sulfur loop, and no level above the map cap.

## SECTION 6: HEALTHY
- No buy→merge→sell or →dismantle profit at any rarity, level or slot.
- The level cap holds through chained merges.
- Downgrade tricks don't pay.
- Per step, the merge crystal cost equals the Runeforge's.
- Sulfur use is at most 7%.
- Mercury wall effect is at most −1.2 levellings.
- Gold for 11 facilities matches the design estimate.

## SECTION 7: DELTA vs daily_systems_2026-11-01
- **New:** the Crucible lifetime model, the gold model with 11 facilities, the base-item supply model, and the code-vs-DB off-hand mismatch (7 vs 17).
- **Unchanged:** levellings 16.7-19.4 and crystals 226-264 (random picker, B4 + daily 3), apart from the small Crucible effects above.
- **DB:** the md5 changed since the last run (Designer work). All asserted rows are still present.
- **Design doc corrections:** the Exalted loot row it says is missing exists (loot_progression 84, 2.5%), and the "6% Black Market edge" is 0.2% once the fee is counted.

## Decisions for the developer (two knobs)
1. **What the Crucible is for.** With same-base matching, copies are rare.
   - **A (recommended): keep it as approved.** Nothing breaks: about +0.1 Legendary and about 3% of crystals for a normal player. Accept that it is a small, late "spare copies" facility.
   - **B: widen matching to the same slot group + hand type, and stop at Exalted.** Gives about 23 merges a lifetime from loot (Epic +4.5, Exalted +1.8, no Legendary), so the facility becomes worth its cost. It also costs about 3.2 levellings of mercury (the wall drops to about 13.5-16.2, below 15) and about 45% of crystal income. It would need a mercury and crystal retune and a new Simulator run. With Legendary merges left on, a hunter gets +5.3 Legendaries.
2. **Merchant shelf per restock window.**
   - **A (recommended): one shelf per 5-battle window**, whatever map level is chosen (matches economy_framework 48). Shop Exalted→Legendary stays at about +0.1 to +0.7 a lifetime.
   - **B: a separate shelf for each map level.** Accept up to +1.0 Legendary a lifetime from spare gold, or +2.0 to +3.8 when 30% of income is diverted. Needs a Dev check of MerchantService.

VERDICT: SIMULATION CLEAN — no critical findings across item levels 1-99.
- Biggest caveat: the same-base rule makes the Crucible very weak (about 3 merges a lifetime from loot, about 12 with all spare gold).
- Exploit to close: per-map-level shelves would allow up to about +1 to +4 Legendaries a lifetime from bought Exalteds.

Files modified: sim\ only. Source and docs untouched.
