# Gear Merging Facility ("Workshop" idea) — Design Proposal
*2026-11-01 · proposal only · nothing in the database, spreadsheets or code was changed*

> **2026-11-02: RESOLVED (USER), recorded in the database (guild_facilities 59-66).** Approved as the **Crucible** with one change: inputs must be the **same base item** (decision 2a, not 2b), so the "keeper" step in B1/decision 4 is not needed. Decision 12 was dropped (see the F2 correction). NOT BUILT; the Dev is building it.

**The user's idea:** "create a gear by merging 3-5 similar gears of same rarity to produce a gear of the next rarity. The level is the average of the 3 merged gears." Facility levels: "Decrease needed gears from 5 to 3, boost level of produced gears, decrease gold cost, increases the peak rarity possible up to legendary."

**What the database already says:** nothing about merging, fusing or combining gear. The only matches were combat rules (knockback distances adding together), so this would be a brand-new system. **But the name "Workshop" is already taken** by an existing facility (it manages consumables, unlocks at Guild Hall L4, and costs 4,123g in total; guild_facilities rows 18, 19, 31). See F1.

Example item used throughout: a one-hand weapon at item level 50 (base value 100; level multiplier ×1.98).

---

## A. Gaps in the wording

**A1. What counts as "similar"?** Options: (a) the exact same base item (3 Longswords): very restrictive, and players will rarely have enough copies. (b) The same slot group and hand type: any 1H weapon, any 2H weapon, any Body armour, Head, Gloves, Feet, Off-hand or Accessory. (c) Any gear at all: the price table breaks, because slots have different base values (2H 150 vs Gloves 50).
**Recommend (b).** It is easy to fill, and the price of everything is set by slot, so prices stay consistent.

**A2. "Average of the 3" when 5 are merged.** **Recommend: the average of all the items put in** (4 or 5 when that many are needed). Anything else would let you add low-level filler for free.

**A3. Rounding.** **Recommend rounding down**, the same as every other gold and level calculation in the game.

**A4. What "boost level" means.** Options: (a) +N levels on top of the average, limited only by 99. (b) +N, but never above the highest-level item put in: the boost does nothing when all the items are the same level. (c) +N, but never above the highest map level you have unlocked (the level a fresh drop could have) and never above 99.
**Recommend (c).** A fresh drop at that level is already free, so the boost never gives a level you couldn't get from loot. Not tied to the Blacksmith's ×10 limit, because that limit applies to paid upgrades, not to the level an item arrives at.

**A5. "Peak rarity up to Legendary".** **Recommend: the facility level sets the highest rarity that can come OUT.** Uncommon at L1, Rare at L4, Epic at L7 (the same steps as the Runeforge), Exalted at L9 and Legendary at L10. Inputs can be at most one step below that cap.

## B. The item that comes out

**B1. Base item.** Options: (a) random among the inputs; (b) **the player picks one input as the "keeper"**: the result has that item's base and built-in passive. **Recommend (b).** It is predictable, it is standard in fusion systems, and the other inputs are simply the fuel.

**B2. Bonus lines.** Options: (a) **a fresh roll at the new rarity by the normal loot rules** (the usual bonus point budget and passive chances); (b) keep the keeper's lines and top them up; (c) keep the best lines from all the inputs. Option (c) would be a better tool than the Runeforge for free, and (b) would copy the Runeforge's job. **Recommend (a).** The roll is fixed by the input items' IDs, so leaving and coming back never changes it. No preview of the lines: the preview shows only the base, rarity, level and cost. That stops players from trying swap after swap until they see a roll they like.

**B3. Passives.** The built-in passive comes from the keeper. A bonus passive can appear only through the fresh roll, with the normal limits (1, or 2 on 2H weapons) and the normal minimum-rarity checks.

**B4. Tags.** The result is a **new item**: "rune-forged" = no, starting rarity = the rarity that came out, reroll count = 0. It sells and dismantles like normal loot at its rarity. No new saved field is needed.

**B5. Levelling record / catch-up.** The result counts as arriving at its level: free level = its level, levelling credit 0, so it never owes the Runeforge catch-up fee. Any levelling paid on the inputs is lost.
*Cost-dodge check:* "level cheaply as Common, then raise the rarity" does NOT work here. You pay to level 3-5 items at the lower rate and get back one item. The rarity price steps are at most ×1.67 (Uncommon→Rare), much less than ×3, so levelling the inputs first always costs more than levelling the result. The only free levels are from the boost, and A4(c) caps them at what a fresh drop could have.

**B6. Rerolls.** Unchanged. Exalted and Legendary results can be rerolled with sulfur at Runeforge L8+, like any other item.

## C. Which items can go in

**C1. Blocked:** equipped items, items on units out on dispatch (keeps BUG-050 and the keep-a-weapon rule safe), items in the sell cart, and items in a staged upgrade or forge — the same rules as dismantling. All inputs must be the same rarity.
**C2. Allowed rarities:** Common to Exalted. Not allowed: Legendary, Mythic, Transcendent and Unique. Nothing goes above Legendary, and Unique items are authored.
**C3. Source does not matter:** shop, Black Market, recruit, starter and rune-forged items are all allowed, the same as dismantling. The gold price is the gate (the price math in F5 shows no loop).
**C4. Confirmation:** one confirm prompt; the inputs are destroyed; it cannot be undone; nothing is refunded. Recommend an extra warning when an input has more levels or a higher-cost bonus line than the keeper.

## D. Cost

**D1. Gold:** fee = slot base value × the result's rarity multiplier × level multiplier × 0.5, minus 3% per facility level above L1 (L10 = −27%, like the Blacksmith and Runeforge). Rounded down. Examples: 1H L50 → Epic = 396g (289g at L10); 1H L99 → Legendary = 1,036g (756g at L10). Small next to the value of the inputs; the inputs are the real cost.

**D2. Crystals: YES, at half the Runeforge step price.** To Uncommon 2, to Rare 3, to Epic 6. Never discounted.
*Why half:* putting in 3 Rares means giving up their dismantle value (3 × 2 = 6 crystals, plus about one rune gem per bonus line). Add 6 crystals for the merge and the total is 12, the same as the Runeforge's Rare→Epic step (12). So crystal scarcity holds whichever path is used, and neither path is free.
**D3. Above Epic:** to Exalted 8 crystals + 1 sulfur; to Legendary 12 crystals + 2 sulfur, matching the sulfur reroll prices for those rarities. No mercury: mercury is the levelling resource, and the boost is already capped.

## E. Facility levels L1-10

| Lvl | Items needed | Level boost | Gold discount | Highest rarity out | Level cost |
|---|---|---|---|---|---|
| 1 | 5 | +0 | 0% | Uncommon | 211 |
| 2 | 5 | +0 | 3% | Uncommon | 244 |
| 3 | 5 | +1 | 6% | Uncommon | 300 |
| 4 | 4 | +1 | 9% | Rare | 378 |
| 5 | 4 | +2 | 12% | Rare | 478 |
| 6 | 4 | +2 | 15% | Rare | 600 |
| 7 | 4 | +3 | 18% | Epic | 744 |
| 8 | 3 | +3 | 21% | Epic | 911 |
| 9 | 3 | +4 | 24% | Exalted | 1,100 |
| 10 | 3 | +5 | 27% | Legendary | 1,311 |

- **Cost curve:** Base 200, Scale 18 (the same curve as the Merchant and Tavern). Total **6,277g**.
- **Unlock:** Guild Hall L5 (one step after the Runeforge, so choosing your lines comes first). The facility can never be above the Guild Hall level, so Legendary merges need Guild Hall L10.
- **Effect on the economy rule for facilities (economy_framework 28):** 11 facilities, **77,204g** in total (70,927 + 6,277).
  - Free player: about 109-112% → **about 113-116% of lifetime gold**, likely maxing 5-6 of 11 facilities.
  - Boosted player: about 85-89% → **about 88-92%**, still 11/11.
  - Merge fees are an extra small gold sink on top. Simulator to confirm.

## F. Conflict check

**F1. Name clash: "Workshop" already exists** (consumables, rows 18/19/31, Guild Hall L4, 4,123g). It also appears in the town screen list and the Slice 8 facility list. Options:
- (a) Give the new facility another name. Suggested: **"Crucible"**, where gear is melted together. No existing entry uses it.
- (b) Add merging to the existing Workshop. No new cost, but one facility does two unrelated jobs, and its levels already mean "consumable slots".
- (c) Rename the old consumables Workshop (for example "Quartermaster").

**Recommend (a) Crucible.** It leaves the existing Workshop and its rows untouched. No doctrine is named Workshop.

**F2. Above-Epic rarities have no crafting source today.** Facts from the database:
- The Runeforge stops at Epic; above Epic, only sulfur rerolls.
- Legendary is loot-only. Normal loot weight is 0.12% and elite is 2.0%: about 1-2 per lifetime.
- **CORRECTED 2026-11-02:** Exalted is NOT shop-only. It already drops as loot (weight 2.5%, loot_progression 84, and the game code uses it), and the Merchant at L10 also gives a 5% chance per shelf slot. The Black Market never sells Exalted. *(Old, wrong text: "Exalted is shop-only" and "Data gap: the loot weight table has no Exalted row at all".)*
- The loot ceilings (loot_progression 43-45) cover drops; they say nothing about crafting.

The merge would become the first way to make Exalted and Legendary items, and the only Legendary source outside loot (for example, 3 Merchant Exalted 1H L99 ≈ 29,300g → 1 Legendary).

Options:
- (a) Allow both, as the user asked, gated by L9/L10, crystals + sulfur, and Guild Hall L10.
- (b) Stop merging at Exalted, so Legendary stays loot-only.
- (c) Stop at Epic.

**Recommend (a).** About 29k gold, 3 Exalted items and 12 crystals + 2 sulfur per Legendary is a late-game goal comparable to levelling an Epic L1-99 (29,596g). Have the Simulator check the lifetime Legendary count. *(Old text "Separately, fix the missing Exalted loot row" withdrawn 2026-11-02: the row exists.)*

**F3. Crystal scarcity.** A merge without crystals would get around the crystal cost of the Runeforge, which was kept on purpose (3/6/12). The half-price crystals in D2 bring the total crystal cost to the same as the Runeforge. No change to locked crystal rules.

**F4. Runeforge vs merging. Does one make the other pointless?**
- **Runeforge:** keeps your item and its level, you choose the lines, it needs the right rune gems, and it stops at Epic.
- **Merge:** uses up 3-5 items, gives random new lines, needs no gems, and can go above Epic.

For the same crystal-equivalent cost, players use the Runeforge for a targeted item and merging to turn unwanted items into one random higher-rarity item. Both keep a job. With the free merge from the original wording, the Runeforge's Epic step would be pointless.

**F5. Merge vs dismantle and sell; buy → merge → sell loops** (1H L50; sell = ¼ of base × rarity × level):

| Route | Gives |
|---|---|
| Dismantle 3 Rares | 6 crystals, about 6 gems, 15 mercury |
| Sell 3 Rares | 369g |
| Merge 3 Rares → Epic (−6 crystals, −396g), then dismantle | 3 crystals, about 3 gems, 5 mercury |
| Merge 3 Rares → Epic, then sell | 198g |

Merging then dismantling or selling always loses. A merged item sells for at most ×1.67 of ONE input, while the inputs together sell for ×3.

Buying the inputs to merge:

| Bought inputs | Cost | Compared with |
|---|---|---|
| 3 Merchant Rares | 5,940g | Merchant Epic 4,752g |
| 3 Black Market Rares | 4,455g | Merchant Epic 4,752g (about 6% cheaper, but needs the rare Black Market and 6 crystals, and the result is random) |
| 3 Merchant Epics | 14,256g | Merchant Exalted 6,534g |

Buying the result directly is cheaper in every case except the Black Market one. Resources cannot be sold, so **there is no gold loop**. Recommend: accept the Black Market edge.

**F6. Item level vs map level (loot_progression 44).** A4(c) caps the result at the highest map level you have unlocked, so a merged item can never be above what a drop could be. No conflict.

**F7. Levelling record and catch-up.** Covered in B5: the result arrives as a new item (credit 0), and paying to level the inputs always costs more than levelling the result. No conflict with the Runeforge catch-up fee.

**F8. Bonus point budgets per rarity** (Uncommon 100 … Exalted 225, Legendary 250; 2H double). The fresh roll uses the normal ±5% budget band, so there are no over-budget items. One side effect: a merged Legendary can only be levelled from Blacksmith L7 (Legendary levelling unlock, row 13). This is accepted: the result can still be equipped at its arrival level.

**F9. Inventory.** Merging turns 3-5 items into 1, so it eases the 50-item soft-maintenance threshold. This is good, but it is another reason the Simulator should include it.

## G. Build impact and Simulator checks

- **Build (later, Dev):**
  - a new facility screen (the same style as the Blacksmith and Runeforge);
  - a saved facility level next to the other buildings;
  - the merge rule, which reuses the loot item maker for the fresh roll and the dismantle input checks;
  - the cost table, the Guild Hall gate, and new items with fresh records.
  - The existing Blacksmith, Runeforge, dismantle and Black Market are untouched.
- **Simulator checks:**
  1. Lifetime Epic / Exalted / Legendary held, with merging vs the loot pace (target: Legendary about 2-4 per lifetime at most).
  2. Crystal and sulfur use, and whether merging drains crystals from the Runeforge.
  3. Gold: the 11-facility spend share for free and boosted players, plus merge fees.
  4. An exploit search: buy/Black Market → merge → sell or dismantle chains, downgrade-then-merge, boost stacking through repeated merges, and the fixed-roll fishing check.
  5. Effect on the inventory threshold and the mercury wall (less dismantling means less mercury).

---

## Decisions for the user

1. **Name.** "Workshop" is already the consumables facility. (a) new name **Crucible**; (b) add merging to the existing Workshop; (c) rename the old Workshop. **Recommend (a).**
2. **What counts as "similar".** (a) the exact same base item; (b) **the same slot group and hand type** (any 1H weapon, any Body armour, …); (c) anything. **Recommend (b).**
3. **Output level.** Average of ALL inputs, rounded down, + facility boost. Capped by (a) 99 only; (b) the highest input; (c) **your highest unlocked map level and 99**. **Recommend (c).**
4. **Base item and bonus lines.** (a) **the player picks the keeper's base and built-in passive, then a fresh normal-loot roll at the new rarity**, fixed by the inputs, with no preview of the lines; (b) a random base and a fresh roll; (c) keep the best lines. **Recommend (a).**
5. **Result counts as a new item** (no "rune-forged" tag, starting rarity = new rarity, no levelling credit, no catch-up, levelling paid on the inputs is lost). (a) yes; (b) carry over the inputs' levelling credit. **Recommend (a).**
6. **Allowed inputs.** Common-Exalted, all the same rarity. Not equipped, on dispatch, in the sell cart or staged. Any source (shop, Black Market, recruit, starter, rune-forged). Confirm prompt, cannot be undone. (a) yes; (b) also block shop and Black Market items. **Recommend (a)** (the price math shows no loop).
7. **Crystal cost.** (a) none, as in the original wording, which gets around the Runeforge crystal gate; (b) **half the Runeforge step: 2 / 3 / 6 to Uncommon / Rare / Epic**; (c) the full Runeforge price, 3 / 6 / 12. **Recommend (b).** With the inputs' lost dismantle value it equals the Runeforge cost.
8. **Above-Epic merges.** (a) **Exalted at L9 (8 crystals + 1 sulfur) and Legendary at L10 (12 crystals + 2 sulfur)**; (b) stop at Exalted, so Legendary stays loot-only; (c) stop at Epic. **Recommend (a)**, with a Simulator cap check.
9. **Gold fee.** (a) **½ × slot value × rarity multiplier × level multiplier, −3% per facility level** (1H L50 Epic 396g; L99 Legendary 1,036g); (b) a flat fee per rarity step, like the Runeforge forge fee (1H about 150g per step); (c) no gold fee. **Recommend (a).**
10. **Level table** (as in E). Items needed: 5 at L1-3, 4 at L4-7, 3 at L8-10. Boost: +0 / +1 / +2 / +3 / +4 / +5 at L1 / L3 / L5 / L7 / L9 / L10. Highest rarity out: Uncommon L1, Rare L4, Epic L7, Exalted L9, Legendary L10. (a) **accept**; (b) faster: 3 items from L6 and Epic at L5. **Recommend (a)**: it mirrors the Runeforge steps.
11. **Facility cost and unlock.** (a) **Base 200 / Scale 18 = 6,277g, unlock at Guild Hall L5**. The total becomes 77,204g for 11 facilities: free player about 113-116% (5-6 of 11), boosted about 88-92% (11/11). (b) The cheaper Workshop curve, 4,123g, unlock at Guild Hall L4. **Recommend (a)**, pending a Simulator re-run.
12. **Missing Exalted loot weight (found during the check, separate fix).** The loot table has no Exalted row, so today Exalted comes only from the Merchant at L10. (a) leave it as it is (Exalted = shop + merge only); (b) add an Exalted loot weight between Epic and Legendary (needs the Simulator). **Recommend (b)**, as a separate small decision.
