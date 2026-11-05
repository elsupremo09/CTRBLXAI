# SIMULATION RUN — 2026-11-01 — Dismantle from ALL sources (design check only, nothing built)
Seed: 20261101 (deterministic; no random draws — expected-value stock, fixed enumerations)
Formulas loaded: 40 (first run) + 28 rule-text checks (16 from the re-check + 12 new: shop price/odds/shelf/refresh, material sell, trade-up, extraction table, dismantle rule + limits, hire fee, dismissal, rarity budgets, Black Market row)
Ruling modelled: USER RULING 2026-11-01 (not yet in the DB). Every dismantled item gives resources, whatever its source. This replaces "shop-bought gives nothing" (gf51/gf57). Every other dismantle rule is kept as locked.
Cases: 39,600 buy→dismantle · 755,040 buy→upgrade→dismantle · 5 lifetime purchase runs · 3 normal-use runs · Black Market at 4 assumed rates
Level bands: item level 1-99 (shop and dismantle content stop at 99)
Files modified: sim\runeforge_sim_2026-11-01\ only (new files). source\ was read only; docs\ was not touched.

## SECTION 1: BLOCKERS
- Black Market lifetime yield: the DB does not say how many objects a map has (open_decisions 48, "Object density / placement count", APPROVAL NEEDED). Results per event are exact. Lifetime results are shown at assumed rates of 0.02 / 0.05 / 0.10 / 0.25 events per battle.
- Normal shop gear spend is not split out in the DB (economy_framework 43 lumps shop with recruitment and other costs). Working estimate: 10k / 20k / 31k g over a lifetime (31k = what is left of necessities after Blacksmith, consumables and recruitment).

## SECTION 2: CRITICAL FINDINGS
Finding: the Black Market becomes the largest Essence source.
Evidence: in code it gives 6 FREE Rare items per object per battle (ObjectEffectService L2289-2298). Each event now dismantles into about 13.5 Essences (11.3 Uncommon + 2.2 Rare; up to 36 if all six are 2H) plus 6 gear materials of the item's level-band tier.
- At 0.02 events per battle (about 1 event every 50 battles), the drop share falls from 25.0% to 15.5%. Filling a 1H Epic drops from 11.5 to 7.0 battles (L50-80).
- At 0.05 events per battle: drops 9.9%; 1H Epic 4.4 battles.
- The drop share stays at 20% or more only if events are ≤0.008 per battle (about 1 per 120 battles).
Level band: all (worst at L61+, where each item also gives +1 T4).
Affected: Essence split target (materials_system 40/41), fill times, and the material wall (+0.5 to +2.6 items at 0.02-0.10 per battle).
Severity: the 25/75 target fails at any realistic Black Market rate. The exact rate is the open object-density decision. Separate DB/code mismatch for the Audit agent: the DB says "six fixed discounted high-tier items" (a paid shop), but the code gives them away free.

## SECTION 3: RESULTS
### PASS/FAIL (measured vs previous)
| # | Check | Previous | Measured now | Result |
|---|---|---|---|---|
| 1 | Buy from shop → dismantle → sell materials (all 8 slots × Common-Exalted × L1-99 × BS L1-10) | not possible (gave nothing) | 0 of 39,600 make gold. Best −200g (Common Gloves L1). Only the +1 (Rare+ start) comes back | PASS |
| 1 | Buy → upgrade → dismantle → sell (every start level, end level and BS level) | — | 0 of 755,040 make gold. Best −216g | PASS |
| 1 | Buy → upgrade → sell the item | ≤0 | best −204g | PASS |
| 1 | Enchant routes on shop items | X1 −11g, X2 −16g | the same routes plus the purchase price, so always lower | PASS |
| 1 | Black Market items → dismantle vs sell (free items, no gold goes in) | not a loop | Dismantling beats selling only at L61-99 for cheap slots (Rare Gloves/Feet: T4 worth 100g vs sell 68-92g, +8 to +32g per item). Otherwise selling pays more. No gold-in loop | PASS (faucet, not a loop) |
| 1 | Black Market made a paid shop (DB intent) | — | buy→dismantle→sell pays only above a 90.9% discount (Rare Gloves L61); buy→sell only above 93.75% | PASS if discount < 90% |
| 3 | Essence split, normal play (shop gear bought to use, 20k g) | 25 / 75 | drops 23.2% / loot dismantle 69.3% / shop gear 7.5% | PASS |
| 3 | Essence split, Black Market | 25 / 75 | drops 15.5% (0.02/battle) · 9.9% (0.05) · 6.1% (0.10) | **FAIL** |
| 3 | Essence split, deliberate buying | 25 / 75 | free, facilities first: 0 bought (86g spare) · boosted surplus (35-38k): drops 20.3%, bought 18.9% · all facility gold put into Essences: drops 13.0-16.3%, bought 34.8-48.3% | WATCH (player choice, costs facilities) |
| 3 | Battles to fill, L50-80, natural (1H Unc / Rare / Epic) | 5.6 / 8.4 / 11.2 (lifetime rate) | 5.8 / 8.6 / 11.5 (band rate, unchanged). Normal-use shop gear: 5.1 / 7.7 / 10.3. Boosted surplus bought: 4.8 / 7.2 / 9.6. Gold only at L65: 780 / 1,170 / 1,560g = 2.1 / 3.2 / 4.2 battles of income | PASS (shop) / FAIL with Black Market (7.0 at 0.02) |
| 3 | Crafted Epics L50-80 (rusher / boosted / normal) vs ~4 natural | 8.3 / 9.1-14.2 / 0 | 8.3 / 9.1-14.2 / 0. Gold is the limit everywhere, so buying Essences cannot add any. The Essence ceiling rises (rusher 14.5 → 16.2) but does not bind | PASS |
| 3 | Facilities, free / boosted | 8/10 · 10/10 with 35.0-37.6k left | unchanged. Buying Essences only uses gold the player chooses to divert | PASS |
| 3 | Spending pressure | ~106% / ~84% | 105.9-106.6% / 83.1-84.3% unchanged | PASS |
| 3 | Material wall | 12-15 (14-16 with conversion) | Shop: +1 material only. T3 costs 900g (Rare Feet L41), T4 costs 1,100g (Rare Feet L61; conversion would be 2,700g). One more item costs about 51,000g → free +0.0, boosted surplus +0.7, boosted all luxury +2.1. Black Market +0.5 / +1.3 / +2.6 items at 0.02 / 0.05 / 0.10 per battle | PASS (shop) / WATCH (Black Market) |
| 4 | Recruit: hire → dismantle gear | — | Weapon is Common, at the recruit's level, no lines → 0 materials, 0 Essences. Equipped → refused (gf52 + EquipmentService L234, BUG-050). Swap first: −hire 215-2,485g for nothing. Dismiss (returns gear): −1,290 to −14,910g | PASS (negative in every currency) |
| 5 | Starter/Debug gear | — | Once per save: Hero Sword / Mage Wand (1H Uncommon L5) + Ranger Crossbow (2H Uncommon L5) give about 6 Uncommon Essences (8 at most), 0 materials. Shield and 5 armor pieces (Common) give 0. The weapons must be swapped out first | PASS |

### Gold → Essence (net of the +1 material's sell value; best case means the player picks the item, and lines are shown in the shop)
| Level | Uncommon | Rare (best / numbers only / no trade-up) | Epic (best / numbers only / 9 Uncommon) | Whole-shelf average, Merchant L10, per Uncommon-equivalent |
|---|---|---|---|---|
| L20 | 207g (Uncommon Gloves/Feet 2×T1, 414g, Merchant L2+) | 514 / 621 / 685g | 1,541 / 1,651 / 1,863g | 441g |
| L50 | 297g (594g item) | 713 / 891 / 950g | 2,138 / 2,336 / 2,673g | 626g |
| L80 | 387g (774g item) | 893 / 1,161 / 1,190g | 2,678 / 2,996 / 3,483g | 805g |
- "Best" Rare/Epic = Rare Gloves with T1 + a 100-BP Rare passive (1 Uncommon + 1 Rare), traded up. "Numbers only" = 3 Uncommon → 1 Rare, or an Epic Gloves with one T4 line (Merchant L9+, Blacksmith L7+). Trade-up needs Runeforge L6; Rare Essences need Blacksmith L4+; Epic Essences need Blacksmith L7+.
- Stock: shelf 5-10 items (Merchant L1-L10), refreshed every 5 battles (MerchantService rerollKey, gf15). Shop items roll at the active quest's level (Main L1793), so every new quest level opens a new shelf in the same 5-battle window (up to 6 shelves per window).
- Per battle (Merchant L10): stock caps it at 3.9 Essences/battle with 1 shelf, or 23.4 with 6 shelves. Gold is the real limit: a whole L50 shelf costs 16,949g (53 battles of income). Putting ALL battle income into Uncommons gives about 0.9 per battle (2.5× natural 0.357).
- Lifetime: free player who buys facilities first: 0 (86g spare) · boosted surplus: 56 (46 U + 9 R) · all facility gold into Essences: 128 (free) / 224 (boosted). Natural income is 239 (60 drops + 179 loot dismantling).

### Black Market per event (6 free Rare items; Blacksmith extraction Rare+)
| Item level | Essences | Materials | Sell all 6 instead |
|---|---|---|---|
| L20 | 11.3 U + 2.2 R (max 18 1H-type, 36 all 2H) | 6 T1 (30g) | 405g |
| L50 | same | 6 T3 (240g) | 580g |
| L80 | same | 6 T4 (600g) | 757g |
Lifetime at 0.02 / 0.05 / 0.10 / 0.25 events per battle: 148 / 369 / 738 / 1,846 Essences, 66 / 164 / 328 / 820 materials (natural income 239 Essences).

## SECTION 4: OUTLIERS
| Entry | Class | Wins | Loses | Evidence |
|---|---|---|---|---|
| Black Market | DOMINANT Essence source | Essences per event, free, plus materials | none | 13.5 Essences + 6 materials per event for 0g |
| Uncommon Gloves/Feet in the shop | NICHE (best gold → Essence) | gold per Uncommon | only 2 lines | 207-387g per Uncommon, about 0.08 per battle in stock |

## SECTION 5: MITIGATIONS (needed for the Black Market only; nothing chosen or changed)
1. Black Market items give no Essences (gear materials and the +1 only). Black Market share 0%, drops 25.0%. The wall still gets +0.5 items at 0.02 per battle.
2. Black Market items give at most 1 Essence each (6 per event). At 0.02 per battle: 66 lifetime, drops 19.7%. At 0.05: 164, drops 14.9%.
3. Build the DB version, a paid "discounted" shop (any discount below 90%). Example: 50% off → about 170-250g per Uncommon-equivalent at L50 (Gloves pick / average item), and gold limits it like the shop. With the free player's spare gold (~0g) it adds about 0.
4. Lock object density so Black Market events stay ≤0.008 per battle (keeps drops ≥20%) or ≤0.004 (keeps ≥22.5%).
Optional for deliberate shop buying (WATCH, not FAIL): shop items give no Essences (shop share 0, drops back to 25.0%; normal play loses about 19 Essences per lifetime), or at most 1 Essence per shop item (boosted all-in: about 120 instead of 224).

## SECTION 6: HEALTHY
- No gold loop from any source: shop, upgrade, enchant, recruit, Black Market (paid at <90% discount) or starter gear.
- Recruit gear yields nothing (Common, never upgraded) and the weapon is protected (BUG-050 guard).
- Crafted-Epic supply, facilities, spending pressure and the wall (from shop buying) are unchanged, because gold binds first.
- Starter/Debug gear: about 6 Essences once per save.
- Note: the starter weapon is regenerated if the saved MainHand item is missing (Main L642-686). It cannot be reached while equipped items are refused for dismantling (gf52). Keep that guard.

## SECTION 7: DELTA
- Resolved: none (new check).
- New: the Black Market Essence faucet (critical); gold → Essence at 207-387g per Uncommon (watch); buyable T3/T4 via the shop +1 (900 / 1,100g, harmless).
- Unchanged: every gold-loop result, crafted Epics, facilities, pressure, wall from shop buying.
- DB changes since the re-check (docs\backups\recheck_rulings_20261101_112336_changes.json): wording/record updates only (gf38, 48, 51, 55; ms41, 42; lp24; equipment_schema reroll_count; open_decisions 23/123; implementation_plan 53). No number or formula used here changed. One check string was updated to the new ms42 wording "(never T5; kept by USER DECISION ...)".

## VERDICT
1 CRITICAL FINDING — highest priority: free Black Market items now dismantle into ~13.5 Essences + 6 materials per event, which breaks the 25/75 Essence split at any event rate above ~0.008 per battle.
