# CTRBLXAI — Blacksmith + Runeforge v2 — DRAFT PROPOSAL (2026-11-01)

**Status: FINAL — ready for user approval. Nothing here is in the database yet.**
**Updated 2026-11-01 (third pass, final) with the user's decisions on the Simulator re-check (sim\runeforge_v2_2026-11-01\report_recheck_v2_2026-11-01.md, thread-417a41b18ebb) and the re-check fixes. Previous versions: ..._before_answers.md, ..._before_simcheck.md, ..._before_final.md (before this pass).**
The database, the spreadsheets and INDEX.txt were read only, never written. After the user approves this draft, every row in the "Approval write list" below is rewritten in one pass.

Sources read (read-only): guild_facilities 1-58, materials_system 1-42, economy_framework 1-49, equipment_schema 1-19, save_data_contract 1-15, service_boundaries 14-18, open_decisions 21-24/123, implementation_plan 53, item_rarity_framework, item_rarity_rules 1-25, bonus_numerical_attributes (117 rows), bonus_passives (55 rows), loot_progression 1-84, the bug registry (BUG-050, BUG-054), and, read only, the dispatch reward, recruit weapon and Black Market code.

---

## FINAL — ready for user approval (plain English)

**What the system does.** The Blacksmith only levels items now, at 1 mercury + gold per level. Any spare item can be broken down into mercury, crystals, rune gems (one per bonus line) and, for rare items, sulfur. The Runeforge puts rune gems onto Common-to-Epic items, which can raise their rarity; items above Epic are changed only by sulfur rerolls. None of the four resources can be sold, so there is no way to farm gold. The Simulator re-check found no loops, the Fortune cap holds, and "same total in any order" holds for items never downgraded.

**Key numbers:**
- **Crystals stay tight on purpose.** Steps cost 3 / 6 / 12 (to Uncommon / Rare / Epic); a same-rarity swap costs 2 / 4 / 8. A lifetime brings about **275-318** crystals; a full team wants **460-685**. Teams will be mixed rarity; hunting gems is the challenge.
- **Crafted Epics, L50-80:** up to about **15-17 (free) / 14-20 (boosted)**. Counting bought Epics too (Merchant + Black Market at 1-3% spawn), a boosted player can hold about **24-27**. That is accepted: the Merchant alone already allows 23.6-25.8.
- **Forge gold:** charged only on the rarity difference (1H Common→Epic **400g** in one forge or in steps). Same-rarity swap = half the rarity price (1H 75 / 125 / 200g). Epic step fee OFF.
- **Mercury:** 5% per kill. About **15.9-18.9 full L1→99 levellings** per lifetime before daily events. Daily events give 5 mercury, plus 1 sulfur every 3rd event; at 100% dismantling it passes 20 levellings after about **22-23 events**.
- **Black Market = paid shop at 75% of the Merchant price**, 6 items, each sold once, **75% Rare / 25% Epic, never Exalted or above**. About **575-690g per crystal** on average, always 25% below the same Merchant item. No loop.
- **Fortune:** a "+X% Fortune" gear line adds **+0.05 / +0.10 / +0.15 / +0.20** straight onto Unit Fortune (same as the Lucky trait). Team Fortune is capped after every bonus: never more than **×2.00 loot quality / ×1.50 gold**. To reach the cap, gear alone needs 9 top-tier lines over 3 units (7 with Lucky (Greater) on all 3, 4 with a Fountain or Idol of Fortune). Natural Fortune gems alone reach about ×1.53. At the cap, a lifetime gives crystals 466 vs 320, gems 386 vs 229, sulfur 23.0 vs 15.6, mercury 2,395 vs 1,818. No per-unit Fortune limit.
- **Robux:** cannot buy materials directly. Gold Boost can speed up materials indirectly (buy shop gear, dismantle it); accepted because it always loses gold and shop stock limits it.
- **Facility spending with realistic crafting:** free player 5-7 of 10 facilities maxed (about 109-112% of lifetime gold); boosted 10/10 (about 85-89%).
- **Real cost to unlock Epic crafting: 8,170g** (Runeforge L7 also needs Guild Hall L7).

**Nothing is left for the user to decide except final approval.** Five numbers stay as working estimates and do not block approval: Black Market spawn rate (part of the object-density decision, open_decisions 48), daily events per lifetime, dispatch frequency, gem drop weights, drops per battle.

**Approval write list (one pass; from Section 10).** DB rows, then the spreadsheet sheet that mirrors them:
| DB table | Rows | Spreadsheet sheet |
|---|---|---|
| guild_facilities | 1, 4, 5, 12, 13, 35-38, 40-58 (47 delete-and-replace, 57 mark OFF) | Game_Rules › 25 Guild Facilities |
| materials_system | 1-24, 25-27 (delete), 28-34, 36-42 | Game_Rules › 23 Materials System |
| economy_framework | 14, 15 (notes), 16, 19, 20, 21, 36, 43-46 | Game_Rules › 22 Economy Framework |
| loot_progression | 11, 17, 24, 26, 28, 69, 70 | Game_Rules › 10 Loot Progression |
| objects_encounters | 20, 31 | Game_Rules › 17 Objects Encounters |
| open_decisions | 21-24, 123 + 1 new row (48 NOT touched) | Game_Rules › 18 Open Decisions |
| unit_progression | 84, 99 | Game_Rules › 21 Unit Progression |
| project_rules | 109, 111, 112 | Game_Rules › 01 Project Identity |
| bonus_numerical_attributes | 70-73 (Fortune T1-T4 = flat +0.05 / +0.10 / +0.15 / +0.20 Unit Fortune) | Item_Rarity_BP_Bonus_Attributes 3 › 01 Numerical Attributes |
| item_rarity_rules | 3 | Item_Rarity_BP_Bonus_Attributes 3 › 00 Framework |
| item_generation_steps | 7, 10 | Item_Rarity_BP_Bonus_Attributes 3 › 04 Generation Steps |
| equipment_schema | 4, 5, 16 (delete), 17 (delete), 18, 19 + new row 20 | Build_Plan › 04 — Equipment Runtime Schema |
| save_data_contract | 3 | Build_Plan › 14 — Save Data Contract |
| service_boundaries | 15, 16, 18 | Build_Plan › 02 — Service Boundaries |
| implementation_plan | 53 (+ the Section 13 dev notes) | Build_Plan › 19 Implementation Plan |
| live_service_features | 4, 5 | none (DB only) |
| battlefield_events | 35 (Crystal Golem) | none (DB only) |

Not touched: open_decisions 48, unit_traits (Lucky rows stay as they are), objects_encounters 32 (Idol clamp already matches). INDEX.txt: update only if a new row/table changes what it points to.

---

## 0. One-screen summary

| Topic | v2 proposal |
|---|---|
| Blacksmith | Levels items only. Max level = Blacksmith level × 10 (L10 = 99). Gold discount stays 3% per level (L10 = −27%). |
| Upgrade cost | **1 mercury per level, every rarity.** Gold uses the same formula shape as today (economy_framework 19), but rounded on a running total (Section 4). |
| Downgrade | Free, unlimited (no Blacksmith-level reach rule). No refund. **The item loses the stored levelling gold of the levels it drops** (RESOLVED (USER) Q7, Section 4.2), so re-upgrading costs full price and downgrading always has a real cost. |
| Dismantle | Any item, from any source. Not allowed on equipped items. Mercury = ceil(level / 10). Crystals C0 / U1 / R2 / E3 / Ex4 / L6 / Unique 10. 1 rune gem per bonus line (Unique: none). Sulfur Ex1 / L2 / Unique 3. **Mythic 8 crystals + 3 sulfur, Transcendent 10 + 4** (RESOLVED (USER) Q1). Fortune lines also become gems (RESOLVED (USER) Q6). |
| Runeforge "forge" | Install 1 or more rune gems. Crystals: **every rarity step crossed is charged**: to Uncommon 3, to Rare 6, to Epic 12, so Common → Epic = 3 + 6 + 12 = **21** in one forge or in steps (RESOLVED (USER)). A forge that keeps the rarity on an Uncommon / Rare / Epic item = **2 / 4 / 8**. Replaced lines are destroyed. **Costs STAY as they are even though crystals run short (RESOLVED (USER) 2026-11-01, sim check): mixed-rarity teams are intended.** |
| Forge gold | **Forge fee charged on the rarity difference** (DECIDED (DEV DEFAULT), G9): 1H Common → Epic = 400g in one forge or in steps. **Swap fee** when rarity stays = slot value × 0.5 × rarity multiplier (1H Epic 200g). Neither depends on item level. **+ levelling catch-up** (the extra levelling gold the item's past levels would have cost at the new rarity). Both "same total" goals hold **exactly for items never downgraded**; a downgrade always adds a real cost (Q7). |
| Per-item saved number | **Levelling record**: the level the item arrived at plus a short list (at most 10 entries) of which Blacksmith discount each level was bought at. The levelling credit (gold paid, at "Common price", whole units) is calculated from it, so downgrades can remove exactly what the dropped levels added. It replaces starting_level and shop_bought. |
| Runeforge levels | Uncommon capacity at L1, **Rare at L4, Epic at L7**. Sulfur rerolls at L8-10. −3% per level on the forge and swap fees only (RESOLVED (USER) Q8). Real gate for Epic: **8,170g** (Runeforge L7 needs Guild Hall L7). |
| Rerolls (sulfur) | Each reroll offers N full attribute sets plus a "keep current" option (RESOLVED (USER) Q10). Exalted and Legendary 2 / 3 / 4 sets at L8 / 9 / 10 (RESOLVED (USER) Q3). Mythic 2 / 3 at L9 / 10. **Transcendent 2 at L10 only** (RESOLVED (USER) Q2). Fortune can appear (Q6). Sulfur per reroll: Exalted 1, Legendary 2, Mythic 3, Transcendent 4. |
| Elite / boss drops | Elite: 3 crystals (always, WORKING ESTIMATE G10), 50% chance of 1 gem, 25% chance of 1 sulfur at L60+. Boss: 5 crystals, 1 gem, 1 sulfur at L60+. Fortune never applies. |
| Mercury drops | **Kills 5%** (DECIDED (DEV DEFAULT), 5 enemies per normal battle → 0.25 per battle), elite 2, boss 3, chest 1, quests about 0.3, dispatch 1-2 per mission (about 0.3 per battle, WORKING ESTIMATE). Daily event: 5 mercury, and **1 sulfur on every 3rd completed daily event** (RESOLVED (USER) 2026-11-01). Lifetime ≈ 15.9-18.9 full levellings before daily events. |
| Selling resources | Mercury, crystals, gems and sulfur **cannot be sold**. That closes every gold loop. |
| Conversion / T5 rules | Obsolete (there is only one material now). Material conversion removed; the Blacksmith keeps its rarity-upgrade unlocks (RESOLVED (USER) Q5). Old T1-T5 balances become mercury 1:1. The 3 Essence counters are removed. |
| Fortune | Fortune lines become rune gems and can appear in rerolls (RESOLVED (USER) Q6, reverses this morning's "Fortune out of crafting" rule). Fortune still never changes material, crystal, gem or sulfur drop chances. **The cap is now an explicit rule** (DECIDED (DEV DEFAULT), G5, Section 3.3): Expedition Fortune is clamped to 0-1.75 after every bonus (Thief included) → at most ×2.00 loot quality, ×1.50 gold. **"+X% Fortune" = flat +0.05 / +0.10 / +0.15 / +0.20 Unit Fortune** (RESOLVED (USER) 2026-11-01, same as the Lucky trait). No per-unit limit. |
| Movement / Jump / Force-type stacking | **No cap** (RESOLVED (USER)). Gems can reach about +6 / +7 Movement on one unit. |
| Black Market | **RESOLVED (USER) Q4: paid shop at 75% of the Merchant price**, 6 items, each sold once per object per battle, paid from the gold balance, items go to inventory. **Stock 75% Rare / 25% Epic, never Exalted or above** (RESOLVED (USER) 2026-11-01) (Section 3.4). Replaces today's code (6 free Rare items); code change built later. |
| Epic step fee | **OFF** (DECIDED (DEV DEFAULT)). Crystals already gate Epics. Not built. |

---

## 1. Blacksmith v2

### 1.1 Functions
- **Upgrade** (level up) an item. No "+1 enhancement" levels for now. A note for later: maybe for max-level gear, maybe Legendary only.
- **Downgrade**: free and unlimited. The item can go to any level from 1 up to its current level. This drops the old downgrade-reach rule (gf 47). Nothing is refunded, and **the item loses the stored levelling gold of the dropped levels** (RESOLVED (USER) Q7, exact rule in Section 4.2). Re-upgrading costs full price. A confirmation prompt appears (Section 12).
- **Dismantle** any unequipped item.

### 1.2 Level table
| Blacksmith level | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| Max upgrade level | 10 | 20 | 30 | 40 | 50 | 60 | 70 | 80 | 90 | 99 |
| Upgrade gold discount | 0% | 3% | 6% | 9% | 12% | 15% | 18% | 21% | 24% | 27% |

- Facility cost is unchanged: 12,625g (gf 11 / 28).
- Removed: Material Conversion at L3, the Essence extraction cap and the refund percentage per level (gf 50).
- The rarity-upgrade unlocks per level (gf 13: Rare at L3, Epic at L5, Exalted at L6, Legendary at L7, Mythic at L9) **stay as they are** (RESOLVED (USER) Q5). Only Material Conversion is removed.

### 1.3 Upgrade cost
- **Mercury: 1 per level, for every rarity.** Item L1 → L99 = **98 mercury**, whatever its rarity.
- **Gold: same formula shape and numbers as today** (economy_framework 19): slot value × rarity multiplier × 0.30 × (1 + target level / 25) × (1 − Blacksmith discount). The only change is how it is rounded (Section 4.2), which adds at most 1g per level. Over L1-99 that is +52g (1H Common) or +48g (1H Epic).
- Gold L1 → 99, 1H, using the discount of the Blacksmith level needed for each level: Common 7,399g, Epic 29,596g. 2H Epic 44,395g. Body Epic 23,677g. Gloves Epic 14,798g. An Epic 1H at 99 is about 17% of lifetime income, so **gold is the wall for high rarities** and mercury is the wall for cheap gear.

### 1.4 Dismantle yields (100% guaranteed, no randomness, Fortune never applies)
| Current rarity | Mercury | Crystals | Rune gems | Sulfur |
|---|---|---|---|---|
| Common | ceil(level / 10) | 0 | 0 (no lines) | 0 |
| Uncommon | ceil(level / 10) | 1 | 1 per bonus line | 0 |
| Rare | ″ | 2 | ″ | 0 |
| Epic | ″ | 3 | ″ | 0 |
| Exalted | ″ | 4 | ″ (see the Epic cap below) | 1 |
| Legendary | ″ | 6 | ″ | 2 |
| Mythic | ″ | **8** (RESOLVED (USER) Q1) | ″ | **3** |
| Transcendent | ″ | **10** (RESOLVED (USER) Q1) | ″ | **4** |
| Unique | ″ | 10 (unchanged, RESOLVED (USER) Q1) | **none** | 3 |

Mercury by level: L1-10 → 1, L11-20 → 2, … L81-90 → 9, L91-99 → 10.

**Gem rules**
- Numeric lines and bonus passives both become gems. Examples: Charge (PAS-049), Movement Range +1 (PAS-011), STR Bonus T2 (NUM-STRBONUS-2 style ID).
- **Epic cap:** a numeric line above Epic becomes the Epic-allowed tier, T4. That is T5 (Legendary) → T4 and T6 (Mythic) → T4. Lines at T1-T4 keep their tier.
- **Passives whose minimum rarity is above Epic give no gem and cannot be transferred.** Checked against bonus_passives: the list is only **PAS-027 Electric Negation (Legendary)** and **PAS-028 Electric Absorption (Mythic)**. No passive has Exalted as its minimum rarity. ✔ Verified.
- **Fortune lines (DER-FORTUNE-1..4, +5 / +10 / +15 / +20%) DO become gems** (RESOLVED (USER) Q6). All four tiers are Epic or lower, so the Epic cap never touches them. This reverses this morning's "Fortune out of crafting" rule (materials_system 19 crafting part, old gf 58). Fortune still never changes material, crystal, gem or sulfur drop chances; the team Fortune caps (loot_progression 11 / 17 / 28: at most ×2.00 loot quality, ×1.50 gold) limit how much it can do.
- The **native passive** of the base item (the weapon's own built-in passive) is not a bonus line, so it never becomes a gem.
- Crystals and sulfur use the item's **current** rarity. Crafting an item up and then dismantling it always loses crystals (Section 6).

### 1.5 Dismantle limits
- **Cannot dismantle:** equipped items, including items on units out on dispatch. This keeps BUG-050 and the keep-a-weapon rule safe. Also refused: items in the sell cart or in a staged upgrade.
- **Unique items CAN be dismantled**, after a confirmation (this replaces the gf 52 ban).
- **Above-Epic items** (Exalted, Legendary, Mythic, Transcendent) show a prompt first (Section 12).
- The source does not matter: shop, loot, Black Market, recruit weapon, starter. Buying from the shop to dismantle is allowed; the gold price is the gate.
- Dismantling gives no gold. Players choose between selling (gold) and dismantling (resources).

---

## 2. Runeforge v2

### 2.1 Forge (install rune gems)
- Pick 1 or more gems from storage and install them on a **Common, Uncommon, Rare or Epic** item. A gem can be a new line or can **replace** an existing line. The replaced line is **destroyed** and no gem comes back.
- One line per attribute family (item_generation_steps 7 still applies). Installing a gem of a family the item already has replaces that line.
- Bonus passive slots still apply: at most 1 bonus passive (2H: 2). A passive gem needs a free slot or replaces the existing bonus passive.
- **New rarity** = the highest of (a) the current rarity (rarity never goes down), (b) the minimum rarity of the rarest line, (c) the lowest rarity whose normal budget holds the total BP (Uncommon 100 / Rare 150 / Epic 200; 2H doubled).
  - Line rarity: T1 and T2 = Uncommon, T3 = Rare, T4 = Epic. A passive = its minimum rarity.
  - Example: Common sword + STR T2 (100) = Uncommon. + VIT T2 (total 200) = Epic. A single T4 gem makes any item Epic, 1H or 2H.
- **Capacity:** the result must fit the Runeforge's capacity rarity and BP (Section 2.4).
- **Items above Epic cannot take gems.** They change only by sulfur rerolls (Section 2.5). Unique items cannot be forged or rerolled.
- After every forge the item is renamed by the normal affix rule (item_rarity_rules 23).

### 2.2 Compatibility (unchanged; enforced the BUG-054 way)
- A gem can be installed **only if that attribute could have rolled on that item as loot.** The Runeforge must use the **same gear-type check the loot generator uses** (ItemGenerator step 4, rewritten for BUG-054), not the free-text eligibility column.
  - Numeric gems: bonus_numerical_attributes.eligible_equipment. "Any equipment" (20 families); "Weapons" (Weapon Attack); "Weapons and off-hands" (Weapon Defense, Weapon RT Delay); "Non-weapon equipment and off-hands" (Equipment Defense).
  - Passive gems: bonus_passives.eligible_item_types, using the generator's gear-type groups.
  - **BUG-054:** attack-shape passives are real-main-weapon only. That covers Fire / Water / Ice / Electric / Dark / Holy Transformation (PAS-016 to 021) and the pattern conversions (PAS-023 to 025).
    - They never go on off-hands or gloves.
    - Transformations never go on weapons that are already elemental (native Ignite / Freeze / Venomous).
    - Pattern conversions only go on matching single-target weapons.
    - Main-hand-only passives (Brutal, Stagger, Bulwark) only go on weapons.
- The Runeforge screen only lists gems that pass the check for the selected item.

### 2.3 Forge cost
**Crystals — every rarity step crossed is charged (RESOLVED (USER) 2026-11-01):**
| Step | to Uncommon | to Rare | to Epic |
|---|---|---|---|
| Crystals for each rarity step the forge crosses | 3 | 6 | 12 |
| Forge that keeps the rarity (swap or extra line) on an item that is… | 2 | 4 | 8 |

- A forge that raises rarity pays the sum of every step it crosses. The route does not matter:

| From → to | One forge | In steps |
|---|---|---|
| Common → Uncommon | 3 | 3 |
| Common → Rare | 9 | 3 + 6 = 9 |
| Common → Epic | 21 | 3 + 6 + 12 = 21 |
| Uncommon → Epic | 18 | 6 + 12 = 18 |
| Rare → Epic | 12 | 12 |

- **A forge that both swaps lines and raises rarity** pays only the rarity steps it crosses. The swap is included; the 2 / 4 / 8 "keep rarity" charge is **not** added on top. Example: a Rare item that swaps one line and adds a T4 gem (becomes Epic) pays 12 crystals.
- A forge that does not change rarity pays 2 / 4 / 8 by the item's rarity, however many gems it installs.
- **These crystal costs STAY (RESOLVED (USER) 2026-11-01, after the Simulator found the shortage).** The user knowingly accepts that income (about 275-318) is well below a full team's need (about 460-685). See Section 3.2.

**Gold = forge fee (or swap fee) + levelling catch-up:**
- **Forge fee — charged on the rarity difference (DECIDED (DEV DEFAULT), gap G9).** For this fee only, the "forge multiplier" is Common **0**, Uncommon 1.5, Rare 2.5, Epic 4.0. Common counts as 0 because a Common item has never been forged. That is what makes 1H Common → Epic 400g (with Common at 1.0 it would be 300g).
  - Let `P(M) = floor(slot value × M × (100 − Runeforge discount %) / 100)` (whole-number math: slot × M×10 × (100 − d) / 1000).
  - **Forge fee = P(new) − P(old)**, using today's Runeforge discount for both. It does **not** depend on item level.
  - Rounding is done on the running total (like levelling gold), so at the same Runeforge level the steps always add up exactly to one big forge. 1H Common → Epic: one forge 400g; steps 150 + 100 + 150 = 400g (not 800g). At Runeforge L10: 292g both ways (109 + 73 + 110).
  - If the Runeforge is upgraded between steps, each step uses the discount of its own day, so the total sits between the two one-forge prices. That is a facility-level effect only, never an item-level one.
- **Swap fee (forge that keeps the rarity) = floor(slot value × 0.5 × rarity multiplier × (100 − Runeforge discount %) / 100)** (DECIDED (DEV DEFAULT)), so swaps are not free in gold. Charged once per forge, however many gems are installed. A forge that swaps AND raises rarity pays only the forge fee (same as the crystal rule).
  - *Information (DECIDED (DEV DEFAULT), swap fee kept at × 0.5):* a forge that raises rarity costs less gold than a later swap at the new rarity (1H Uncommon→Rare 100g vs a Rare swap 125g; Rare→Epic 150g vs an Epic swap 200g). Crystals go the other way (6 vs 4, 12 vs 8), so it is not a loop. Recorded option, **not chosen**: swap fee × 0.375-0.40 instead of × 0.5.

One-forge price from Common (= the sum of the steps):

| Slot (value) | to Uncommon | to Rare | to Epic | to Epic at Runeforge L10 (−27%) |
|---|---|---|---|---|
| 1H (100) | 150 | 250 | 400 | 292 |
| 2H (150) | 225 | 375 | 600 | 438 |
| Body (80) | 120 | 200 | 320 | 233 |
| Off-Hand / Head (60) | 90 | 150 | 240 | 175 |
| Accessory (70) | 105 | 175 | 280 | 204 |
| Gloves / Feet (50) | 75 | 125 | 200 | 146 |

Step prices (1H): Common → Uncommon 150 · Uncommon → Rare 100 · Rare → Epic 150. Other slots scale by slot value.

Swap fee (rarity kept), no discount:

| Slot (value) | on Uncommon | on Rare | on Epic | on Epic at Runeforge L10 |
|---|---|---|---|---|
| 1H (100) | 75 | 125 | 200 | 146 |
| 2H (150) | 112 | 187 | 300 | 219 |
| Body (80) | 60 | 100 | 160 | 116 |
| Off-Hand / Head (60) | 45 | 75 | 120 | 87 |
| Accessory (70) | 52 | 87 | 140 | 102 |
| Gloves / Feet (50) | 37 | 62 | 100 | 73 |

- **Levelling catch-up** (only when the rarity rises) = the levelling gold the item has already been paid at its old rarity, re-priced at the new rarity, minus what was paid. The exact formula is in Section 4. This part **rises with item level**: it is 0 on a fresh drop, and up to 22,197g for a 1H Common → Epic levelled from L1 to 99. **No discount** ever applies to it (that would break the equality).
- **Epic step fee: OFF (DECIDED (DEV DEFAULT) 2026-11-01).** Crystals already gate Epics, and the Simulator showed the fee only adds gold pressure (+12 points for free players) without capping the Epic count. Not built. (For the record, the shelved formula was floor(0.5 × (L1 shop Epic price − L1 shop price at the starting rarity)), 1H Common start 1,000g.)
- **Crafted Epic supply L50-80 — DECIDED (DEV DEFAULT) 2026-11-01, restated after the re-check:** the target counts **CRAFTED Epics only**: up to about **15-17 (free) / 14-20 (boosted)**. This is the most possible, for a player who saves every crystal. It replaces this morning's accepted "rusher ≤ 8 / boosted 9-14" (economy_framework 15 notes).
  - *Information:* including bought Epics (Merchant + Black Market at 1-3% spawn), a boosted player can hold about **24-27**. The re-check FAIL (R4) came from counting bought Epics: a boosted player can already buy Merchant Epics and reach 23.6-25.8 in L50-80, and the Black Market only discounts Epics they can already buy by 25%. The 75/25 mix stays.

### 2.4 Runeforge level table (proposal)
| Level | Forge capacity (1H / 2H BP) | Sulfur rerolls unlocked (sets offered) | Forge fee discount* |
|---|---|---|---|
| 1 | Uncommon (100 / 200) | – | 0% |
| 2 | – | – | 3% |
| 3 | – | – | 6% |
| 4 | **Rare** (150 / 300) | – | 9% |
| 5 | – | – | 12% |
| 6 | – | – | 15% |
| 7 | **Epic** (200 / 400) | – | 18% |
| 8 | – | Legendary 2 · Exalted 2 | 21% |
| 9 | – | Legendary 3 · Mythic 2 · Exalted 3 | 24% |
| 10 | – | Legendary 4 · Mythic 3 · **Transcendent 2** · Exalted 4 | 27% |

- Facility cost unchanged: 8,919g (gf 46 / 49). Unlocks at Guild Hall L4, and the Runeforge level can never be above the Guild Hall level (gf 3).
- The cumulative Runeforge cost to reach Epic capacity (L7) is 4,085g, **but Runeforge L7 also needs Guild Hall L7 (gf 3), so the real gate is 8,170g** (Simulator 2026-11-01; the Guild Hall is bought anyway). Under the old design Epic came at Runeforge L10 (8,919g). Crafted Epic supply is accepted (Section 2.3).
- *Information (gap G8, not an exploit):* Epic items can only be levelled at Blacksmith L5+ (gf 13), so "enchant at L1, then level at the needed discount" cannot actually be played. The real early-Epic route costs 29,028g, 568g less than the 29,596g quoted in T1. This is a small cheaper real route, not a loop.
- *Runeforge discount: −3% per level, **on the forge fee and the swap fee only** (RESOLVED (USER) Q8). Levels 2, 3, 5 and 6 still give something. It never applies to the catch-up, crystals, gems or sulfur.
- Rerolls (RESOLVED (USER) Q2 / Q3): Exalted rerollable from L8 with the same sets as Legendary (2 / 3 / 4 at L8 / 9 / 10). Mythic 2 at L9, 3 at L10. **Transcendent 2 at L10 only.** There is no 1-set Transcendent reroll at L9: a single set is only "take it or keep yours".

### 2.5 Sulfur rerolls (items above Epic)
- Each reroll costs sulfur only (no gold, no crystals): **Exalted 1 · Legendary 2 · Mythic 3 · Transcendent 4.**
- Sets offered: Exalted / Legendary 2 / 3 / 4 at Runeforge L8 / 9 / 10; Mythic 2 / 3 at L9 / 10; Transcendent 2 at L10 only.
- It offers **N complete attribute sets**. Each set is made exactly like a loot item of that rarity, slot and level would be (normal ±5% budget band, normal eligibility including the BUG-054 rules). **Fortune can appear** like on loot (RESOLVED (USER) Q6).
- The player picks one set, and it **replaces ALL** of the item's bonus lines. A "Keep current" option is always shown (RESOLVED (USER) Q10). The sulfur is paid either way.
- The sets come from the item ID + reroll_count + set number. Every paid reroll adds 1 to reroll_count, so leaving and rejoining never changes the sets.
- Rarity never changes. The item is renamed by the affix rule. Unique: never.

---

## 3. Resource economy (working proposals for the Simulator to measure)

### 3.1 Mercury
**Drop table (Fortune never applies, existing materials_system 19):**
| Source | Today (gear materials) | v2 mercury |
|---|---|---|
| Normal kill | 20% → 1 | **5% → 1** per enemy kill (DECIDED (DEV DEFAULT); 5 enemies per normal battle, loot_progression 86 → 0.25 per battle) |
| Elite encounter | 75%, 2-3 | **2** (when rewarded) |
| Boss | 100%, 3-5 | **3** |
| Treasure chest | 1-2 | **1** |
| Quest reward | varies | **1-3, shown up front** (about 0.3 per battle) |
| Dispatch | 1-3, one tier below content | **1 per mission; 2 for tier 4-5 missions** (mission frequency ≈ 0.3 mercury per battle = WORKING ESTIMATE, gap G2) |
| Daily event | T5 only | **5 mercury each + 1 sulfur on every 3rd completed daily event** (RESOLVED (USER) 2026-11-01; see Section 3.2 and Section 8 #5) |
| Salvager's Cap | 30% → 1 | 30% → 1 (unchanged) |
| Crystal Golem | 5× material reward | 5× mercury reward |

- Battle drops come to about **0.92 per battle** (was about 2.6) → about **500 lifetime** (kills about 137 of that; the Simulator's 640 used 10%).
- Dispatch was never counted in the old 2.6 figure. **WORKING ESTIMATE (G2): about 0.3 per battle → about 164 lifetime.** The DB rules allow 0.3-1.83 per battle, so dispatch is the biggest unknown; if the real rate is higher, lower the dispatch amount rather than the kill chance.
- **Dispatch change for the Dev:** DispatchService currently grants "matTier / matCount" (one tier below content, 1-3). In v2 the tier goes away and the count becomes the mercury amount above.
- **Mercury from dismantling:** about 5.45 per item on average (items drop at enemy level). At 0.40 equipment drops per battle (working estimate, loot_progression 24) → about 219 drops in a lifetime. Dismantling 75-100% of them gives **about 890-1,190 mercury**.
- **Lifetime mercury income:** about 1,550-1,850 → about **15.9-18.9 full L1-99 levellings** (Simulator 2026-11-01 at kills 5% + dispatch 0.3, 75-100% dismantling), inside the 15-20 target. Dismantling is the biggest source (about 55-65%).
- **Daily events are on top:** +50 mercury (+0.5 levellings) per 10 events. The lifetime number of events is not defined (gap G3, Section 3.5). With 100% dismantling it passes 20 levellings after **about 22-23 events** (re-check R3: exactly 20.0 at 22.2, over at 23); with 75% dismantling, after about 82.
- **Lifetime need:** 98 per full levelling. The old "10 upgrades" scenario (670 gear materials with rarity multipliers) works out to roughly 300-450 mercury → comfortable.
- **New material wall:** about 16-19 items levelled fully (today 12-15), and it only matters for cheap gear, because gold runs out first for Rare and up (Epic 1H L1-99 = 29,596g).
  - Target: a wall of **15-20** full levellings (met before daily events).
  - Remaining tuning lever: the dispatch amount.
- **Sell price: none — mercury cannot be sold** (recommended). Even at the old T1 price (5g), shop → dismantle → sell loses gold. But "cannot be sold" is simpler and closes every route for good. It removes the small "emergency gold" use (materials_system 28), which is accepted.
- **T5 restriction (materials_system 6/18): obsolete.** There are no tiers, so daily events no longer have an exclusive material. In v2 sulfur is the "daily-paced" resource.
- **Conversion 3:1 (materials_system 25-27, gf 12/13 "Material Conversion at L3"): obsolete, delete.**
- **Migration:** the old balance T1 + T2 + T3 + T4 + T5 becomes mercury 1:1. The 3 Essence counters are removed; any test balance is dropped.

### 3.2 Crystals, rune gems, sulfur
**Elite and boss drops (separate from the equipment roll; Fortune never applies):**
| Source | Crystals | Rune gem | Sulfur |
|---|---|---|---|
| Elite encounter (each completed one; always given, Fortune never applies — WORKING ESTIMATE G10, see Section 3.5) | **3** | **50%: 1 gem**, rolled as one line of a Rare item of the encounter level, random slot | content L60+: **25%: 1** |
| Boss (counts toward the 3-per-day boss reward limit, loot_progression 15) | **5** | **1 gem**, rolled as one line of an Epic item (Rare item below L40) | content L60+: **1** |

- Gems from drops are Epic tier at most, like all gems. Fortune gems can be rolled here like any other line, but Fortune never changes these drop chances.
- **Fortune and income (RESOLVED (USER) Q6):** a high-Fortune team finds better-rarity loot (team cap ×2.00 loot quality, ×1.50 gold), and dismantling better loot gives more crystals and sulfur. That is the same indirect effect already accepted for Essences (materials_system 19). Fortune gems make it easier to reach the cap, but cannot push past it. The Simulator measures it (T18).
- **No extra crystal sources (RESOLVED (USER) 2026-11-01).** The levers the Simulator listed (more elite / boss crystals, chest crystals, smaller steps) are all **rejected**. Treasure chests give no crystals and no gems (DECIDED (DEV DEFAULT), Section 8 #9).

**Working income estimate (lifetime, 547 battles, 0.40 drops per battle, elite and boss each about 0.034 per battle):**
| Resource | Dismantling 75-100% of drops | Elite + boss | Total |
|---|---|---|---|
| Crystals | 127-169 | 56 + 93 | **≈ 276-318** |
| Rune gems | 131-175 | 9 + 19 | **≈ 159-203** (spread over about 153 gem kinds) |
| Sulfur | 4.5-6 | 1.9 + 7.4 | **≈ 13.7-15.2**, plus 1 per 3 completed daily events (about +3.3 per 10 events) |

**Need for 7 units × 6-7 gear (about 45 items):**
- Crafting all 45 from Common to Epic = **945 crystals** (21 each; was 540 when charged once per forge).
- Natural Epic-and-up drops: about 19 lifetime (13 Epic).
- So a realistic roster would like to craft about 25 Epics plus about 20 swaps (160). With every step charged, the 25 Epics cost **300 (all started from Rare) to 525 (all from Common)**, so the total is about **460-685 crystals**. Income is about **275-318** without shop dismantling (Simulator 2026-11-01), so crystals run short by about 142-410.
- **ACCEPTED SHORTAGE (RESOLVED (USER) 2026-11-01).** This is intentional. Teams will be **mixed rarity**, which fits "hunting gems is the challenge". Simulator timings for a full 45-item team from Common: to Uncommon about **0.5 lifetime**, to Rare about **1.4**, to Epic about **3**. Epic crafts from income alone: about 5.5-13. Median 45-gem build coverage by L99: about 31%.
- **Shop → dismantle is a costly gold supplement, not a full fix:** the cheapest crystal is Rare Gloves/Feet (295g at L10, 495g at L50, 740g at L99), the shelf caps it at about 1.6 crystals per battle, and closing the gap that way would cost 50-223% of lifetime income.
- **Gems:** about 2 gems per Epic craft is not the bottleneck in number. **Getting the specific gem you want is the bottleneck**, as the user intends: about 153 kinds (now including the 4 Fortune tiers), about 180 gems in a lifetime, so roughly 1-2 copies of any one kind.
- Crystals now limit players before gems do. That is accepted; no lever is pulled.

**Shop → dismantle prices (the gold gate; gold per resource):**
| Map level | Gloves Common → mercury | Gloves Uncommon → 1 crystal | Gloves Rare → 2 crystals | Gloves Epic → 3 crystals |
|---|---|---|---|---|
| 10 | 236g → 1 | 354g | 590g | 1,416g |
| 50 | 396g → 5 (79g each) | 594g | 990g | 2,376g |
| 91-99 | 560-592g → 10 (56-59g each) | 840-888g | 1,400-1,480g | 3,360-3,552g |

Each shop item also gives its gems, which is targeted gem hunting paid for with gold (allowed by the user).

### 3.3 Fortune cap and what a Fortune line adds to (gap G5)
**Explicit cap rule (DECIDED (DEV DEFAULT), user-visible):**
- **Unit Fortune** = LUK / (LUK + 200) plus flat bonuses (Lucky traits, gear Fortune lines). No per-unit limit (DECIDED (DEV DEFAULT), consistent with the user's no-cap stacking decision).
- **Expedition Fortune** = highest Unit Fortune + 50% of the 2nd + 25% of the 3rd.
- After every Fortune bonus is added (unit LUK, traits, gear lines, Fountain, Idol of Fortune, **and the Thief single-reward bonus, which comes last**), **Expedition Fortune is clamped to the range 0 to 1.75.** The clamp is applied again after each bonus (Section 13).
- So Normalized Expedition Fortune is at most 1.00, the Fortune Multiplier is at most **×2.00** (loot quality and normal drop chance, loot_progression 11 / 12 / 13), and the Gold Multiplier is at most **×1.50** (loot_progression 17 / 28).
- Why it must be written down: loot_progression 11 only calls ×2.00 the "theoretical maximum". That holds from LUK alone, because each Unit Fortune = LUK / (LUK + 200) is always below 1. But flat bonuses (the Lucky traits, unit_traits 73 / 197: "Unit Fortune +10% / +15% (flat)", and Fortune gems) can push a unit past 1. Only the Idol code clamps today (at 1.75, objects_encounters 32). The new rule makes that clamp general. The lower limit of 0 stops Unlucky traits from making drops worse than base.
- Fortune still never changes mercury, crystal, gem or sulfur drop chances (materials_system 19). Note from the Simulator: Fortune also raises the ordinary equipment drop chance (loot_progression 13), so dismantle income rises through drop count as well as rarity. Re-check (90% dismantling, lifetime), normal team vs at the cap: **crystals 466 vs 320, gems 386 vs 229, sulfur 23.0 vs 15.6, mercury 2,395 vs 1,818**. 300,000 random builds: never above ×2.00 loot / ×1.50 gold, never below ×1.00. No loop past the cap.

**What "+X% Fortune" on gear adds to — RESOLVED (USER) 2026-11-01:**
- It is a **flat addition to Unit Fortune**, the same as the Lucky trait (unit_traits TRAIT-P-037 "Unit Fortune +10% (flat)").
- DER-FORTUNE-1..4 (bonus_numerical_attributes 70-73): T1 **+0.05**, T2 **+0.10**, T3 **+0.15**, T4 **+0.20** Unit Fortune.
- Simulator re-check numbers (reading (a), LUK ≈ 30):
  - Gear alone needs **9 T4 lines across 3 units** to reach the cap (7 + 1 + 1). With Lucky (Greater) on all 3: **7 T4**. With the Fountain or Idol of Fortune: **4 T4**. T1/T2 lines alone never reach it.
  - Natural Fortune gems alone (about 12 per lifetime) take a team to about **×1.53** (top 10% ×1.73); they never reach the cap on their own.
  - Income at the cap vs a normal team: crystals 466 vs 320, gems 386 vs 229, sulfur 23.0 vs 15.6, mercury 2,395 vs 1,818.
- **No per-unit Fortune limit (DECIDED (DEV DEFAULT))**, consistent with the user's no-cap stacking decision (Q9). The Simulator's optional "1.0 per unit" limit (would need 15 T4) is not chosen. Fortune above the cap is simply wasted.

### 3.4 Black Market — paid shop (RESOLVED (USER) Q4, 2026-11-01)
Replaces today's code (6 free Rare items per object). The code change is built later. It works like the Merchant:
- **Stock:** 6 items per object, matching the DB's "six fixed discounted high-tier items" (objects_encounters 31). The stock is rolled **once per object per battle**, from the battle seed + object ID. It never refills, and **each item can be bought once**. Interacting stays free and repeatable, so a unit can come back for the rest of the stock.
- **Rarity mix — RESOLVED (USER) 2026-11-01:** each slot rolls **Rare 75% / Epic 25%**, never Exalted or above. Exalted and above never appear. Reasons: "high-tier" means at least Rare. Exalted would add a cheap sulfur source, and shops only sell Exalted at Merchant L10. Epic slots cost more per crystal than Rare (price ×2.4 for crystals ×1.5), so they do not undercut crystal hunting. Each object holds about 13.5 crystals, 14.1 gems and 1.5 Epics. Buying all 6 at L50 costs about 9,321g. Effect on Epic counts: see Section 2.3 (crafted target unchanged; bought Epics are information only).
- **Item level and slot:** like the Merchant: item level = the current Map Level ceiling, random slot, normal loot bonus lines.
- **Price = floor(Merchant price × 75 / 100)**, where Merchant price = round(Base Value × Rarity Mult × Level Mult × Shop Markup) (economy_framework 15: markup ×4.0 Rare, ×6.0 Epic). Merchant facility level, Fortune and Gold Boost never change it.
- **Payment:** gold comes straight from the player's balance during the battle. The Buy button is greyed out if the player cannot afford the item. There is no credit and no refund.
- **Delivery:** bought items go to the inventory at once and are kept whatever the battle result (the gold is already paid) (DECIDED (DEV DEFAULT)). Breaking the object (3 hits) ends any further buying.
- **Simulator re-check result:** gold per crystal when dismantled, L50: **575-690g on average (Rare-only 575g, 75/25 mix 690g), always 25% below the same Merchant item** (e.g. Rare Gloves 371g vs 495g at the Merchant). There is **no loop**: 10,072 buy routes, best result −344g; a Black Market item sells back for only 5.6-8.3% of its price. It is a gold sink and a convenience.
- **Spawn rate: WORKING ESTIMATE** (gap G4, does not block approval). It belongs to the object-density decision, open_decisions 48, which stays open separately. The DB only gives relative weights (e.g. Castle biome 2, Village 3, Town 3). The Simulator used 1-5% of battles.

### 3.5 Remaining Simulator gaps and the value used
| Gap | Value used | Status |
|---|---|---|
| G1 kill mercury | 5% per kill × 5 enemies per normal battle (loot_progression 86) | DECIDED (DEV DEFAULT) |
| G2 dispatch frequency | about 0.3 mercury per battle (range 0.3-1.83 allowed) | WORKING ESTIMATE |
| G3 daily events per lifetime | no lifetime count. Budget per 10 events: +50 mercury, +3.3 sulfur; 100% dismantling passes 20 levellings at about 22-23 events | WORKING ESTIMATE |
| G4 Black Market spawn rate | 1-5% of battles | WORKING ESTIMATE (open_decisions 48 stays open separately) |
| G5 Fortune cap / what +X% adds to | cap clamped after every bonus incl. Thief; +X% = flat Unit Fortune +0.05-0.20 | cap DECIDED (DEV DEFAULT); target **RESOLVED (USER)** |
| G6 gem drop weights | equal weights across gem families and tiers, 10% of gem rolls are passives | WORKING ESTIMATE |
| G7 equipment drops per battle | 0.40 (loot_progression 24) | WORKING ESTIMATE |
| G8 Epic levelling needs Blacksmith L5 | real early-Epic route 568g cheaper | INFORMATION, not an exploit |
| G9 forge fee per forge | fee on the rarity difference (Section 2.3) | DECIDED (DEV DEFAULT) |
| G10 elite crystals | 3 crystals on every completed elite, Fortune never applies | WORKING ESTIMATE |

**G10 against the DB elite rule:** loot_progression 26 / 70 give each completed elite **one reward opportunity at 75% × Fortune** (cap 95%). That rule covers the elite's **equipment / reward-category roll**. The 3 crystals are a **separate fixed grant**, like the mercury already listed for elites. So they do not contradict the DB, but the DB does not describe them yet: loot_progression 70 needs a note ("resource grants are separate, always given, Fortune never applies"). This also fits loot_progression 12 (Fortune cannot add reward slots).

**Daily event sulfur counter (RESOLVED (USER), how it counts):** the profile keeps one lifetime counter of completed daily events. Each completion adds 1, and **every time the counter reaches a multiple of 3 (3rd, 6th, 9th, …) the event also gives 1 sulfur**. The counter never resets, so nothing is lost to rounding across days. Mercury stays 5 per event.

---

## 4. Gold formula and the two "same total" goals

### 4.1 The saved number
Each item has a **levelling credit `C`**: a whole number, 0 for every new item (drop, shop, Black Market, recruit, starter, or migrated).

Each paid Blacksmith upgrade to target level t adds: `credit(t, b) = slotValue × 3 × (25 + t) × (100 − 3 × (b − 1))`, where b is the Blacksmith level at the moment of purchase.

**Why a level record is now needed (Q7 reversal):** to remove exactly what each dropped level added, the item must know which discount each held level was bought at. So each item saves a small **levelling record** instead of one number:
- **Free level F**: the level the item arrived at (drop level, shop level, recruit level, starter level; migrated items = their current level). Levels up to F were never paid for and carry 0 credit.
- **Breakpoints**: a list of (highest item level, Blacksmith level) pairs, in rising order. Example: `F = 12; (40, b4); (99, b10)` means levels 13-40 were bought at Blacksmith L4 and 41-99 at L10.
- **Why the list stays short:** the Blacksmith level never goes down, and every held level above another was bought at the same time or later, so the discount can only rise with item level. That means at most one pair per Blacksmith level: **at most 10 pairs**.
- `C` is calculated from the record: the sum of credit(t, b) over every held level above F. It does not need to be saved separately (it may be cached).

In plain words, `C` is the levelling gold paid, measured at Common price, in units of 1/250,000 of a gold piece × 10. It already includes the discount that applied when each level was bought. Largest possible value: 332,955,000 (2H, L1-99, no discount). That is a safe whole number in Roblox.

### 4.2 Charges (all whole-number math, multiply first, divide last; implementation_plan 53)
- `R` = rarity multiplier × 10 (Common 10, Uncommon 15, Rare 25, Epic 40, Exalted 55, Legendary 70, Mythic 120, Transcendent 200, Unique 150).
- `Paid(C, R) = floor(C × R / 250,000)`. This is the total levelling gold the item has absorbed at rarity R.
- **Blacksmith level t:** gold = `Paid(C_new, R) − Paid(C_old, R)`, plus 1 mercury.
  - This is today's per-level formula, rounded on the running total instead of each level. Check: 1H Common L1 → 2 = 32g, same as today.
- **Runeforge rarity raise R_old → R_new:** catch-up = `Paid(C, R_new) − Paid(C, R_old)`, plus the forge fee on the rarity difference (Section 2.3). (Epic step fee OFF.)
- **Downgrade (RESOLVED (USER) Q7 — exact rule):** downgrading from level A to level B is free and refunds nothing. **The item's stored levelling gold is reduced by exactly the credit each dropped level (A, A−1, … B+1) added when it was last bought, most recent first.** In the record: every breakpoint pair above B is removed, the pair that covers B is cut to end at B, and if B is below F then F becomes B.
  - In gold terms, the item loses `Paid(C_before, R) − Paid(C_after, R)`: the gold the dropped levels are worth at the item's current rarity (what was paid for them, including any catch-up already paid to bring them to this rarity).
  - Re-upgrading pays every level again at full price, at today's Blacksmith discount, and records the new discount.
  - Mercury: the 1 mercury per level spent on the dropped levels is lost as well.

### 4.3 Where equality holds or breaks (computed)
| Case | Result |
|---|---|
| Enchant at L1 then level to 99, vs level to 99 then enchant, vs enchant at L50 in between | **Exactly equal.** 1H Common → Epic: 29,596 / 29,596 / 29,596g (discount of the Blacksmith level needed for each level). Blacksmith L10 the whole time: 25,926 ×3. 2H 44,395 ×3. Body 23,677 ×3. Gloves 14,798 ×3. All plus the same forge fee. |
| Blacksmith discount changes between levels (e.g. L1-50 at −12%, L51-99 at −27%) | **Exactly equal** (27,725 = 27,725), because each level's discount is stored in `C` when it is bought. |
| Rounding | **Exact** (running-total rounding; any order lands on the same final total). |
| **Items that were downgraded (RESOLVED (USER) Q7 rule)** | **The "same total" equalities hold only for items that were never downgraded.** Downgrading always has a real cost, which the user accepts. Example, 1H Common → Epic: L1-60 at −15%, down to 30, back to 60 at −27%. Forge early (before levelling) 20,891g; forge in the middle (after the downgrade) 14,420g; forge late 14,420g. **Straight route** with the same end result and no downgrade (levels 2-30 at −15%, 31-60 at −27%, Epic) = **12,262g**. The early forger loses more (8,629g) because the dropped levels were already paid at Epic price; the late forger loses 2,158g (they were dropped at Common price). Both are always above the straight route. |
| **No downgrade route is ever cheaper than the straight route** | Proof in plain words: think of the item's "value" as `Paid(C, current rarity)`. Every upgrade and every catch-up raises that value by exactly the gold charged. A downgrade lowers it and refunds nothing. So total gold spent = final value + everything lost on downgrades. The straight route ends with the same held levels at the same discounts, so the same final value, with nothing lost. Downgrade routes therefore always cost the same or more, in gold and in mercury. Checked by the Designer on 20,000 random routes (upgrades, downgrades, forges, Blacksmith upgrades, all slots): **never cheaper**, smallest difference 0g. |
| Earlier options, superseded | D1 (keep `C` on downgrade) was not chosen. D2 (reduce `C` at today's discount) was the version that made late forging about 5,500g cheaper than early forging (15,333 vs 20,891g). A careless "reset credit to 0 on downgrade" version would be a real exploit (up to about 13,500g cheaper than the straight route in the Designer's random check). The exact rule above removes precisely what was added, so it cannot be gamed. |
| Runeforge discount | The forge and swap fees do not depend on item level, so equality holds **at the same Runeforge level**. Forging after a Runeforge upgrade is cheaper only through the facility level, not the item level. The discount never touches the catch-up. |
| **Forge fee on the rarity difference (G9, DECIDED (DEV DEFAULT))** | **T1 / T2 equality still holds.** The fee never depends on item level, and the catch-up is unchanged. Stepping up now costs the same as one big forge at the same Runeforge level (1H Common → Epic 400g both ways; 292g both ways at L10, thanks to running-total rounding). So "route does not matter" now holds for crystals **and** the fee. |
| Swap fee | Does not depend on level and never changes rarity, so it never touches the catch-up. Equality holds. |
| Epic step fee | OFF; no effect. |
| Items that exist before the build | `C` = 0, so they never owe catch-up for past levels (same as the side effect already accepted). |
| Old gf 48 hint "Enchant before upgrading to pay less." | **No longer true → remove it.** |

Proof in plain words: every level is paid once at the rarity the item has when it is bought, and the catch-up pays the difference up to the new rarity. So in the end every held level has been paid at the final rarity, at its own discount. Downgrades only add lost gold on top (rule above). No route can make it cheaper.

---

## 5. Approved defaults (as given)
- Rarity never goes down.
- Gems are counted storage, not inventory items: a count per attribute ID (numeric IDs already include the tier) or per passive ID.
- Gems above Epic are downgraded to Epic.
- Exalted / Mythic / Transcendent use the sulfur reroll.
- T1-T5 become mercury 1:1; the Essence counters are removed.
- Enchanted items still sell at their **starting** rarity (economy_framework 14).
- The Epic step fee is OFF (DECIDED (DEV DEFAULT) 2026-11-01).

---

## 6. Exploit guards and loops (expected results go in Section 11)
1. All four resources **cannot be sold**. Dismantling gives **no gold**. So no chain of buy, dismantle, upgrade and forge can turn into gold.
2. Forged items sell at their starting rarity. Blacksmith levels raise sell value, but always by less than they cost (economy_framework 16).
3. Mercury: upgrading costs 1 per level, and dismantling gains at most +1 per 10 levels. Best case is the step from level 10n to 10n+1: net 0 mercury, and the gold is lost.
4. Crystals: every forge-then-dismantle cycle loses crystals, now that every step is charged: Common → Uncommon −2 (3 − 1), Uncommon → Rare −4 (6 − 2), Rare → Epic −9 (12 − 3), Common → Epic −18 (21 − 3).
5. Gems: a gem goes into one item and comes back only when that item is destroyed. Swapping destroys the old line, so gems are never duplicated.
6. Sulfur: rerolling a Legendary and then dismantling it costs 2 and returns 2 whether or not you rerolled. Rerolling is pure cost.
7. Reroll sets are fixed by the item ID + reroll_count, so leaving and rejoining does nothing.
8. Downgrades: the item loses the stored levelling gold of the dropped levels (Section 4.2), so no downgrade-and-forge route is cheaper than the straight route, in gold or mercury.
9. Fortune gems: Fortune never changes resource drop chances, and the team Fortune cap still applies, now as an explicit clamp (Section 3.3). Any extra income from better loot is bounded by that cap (T18 PASS).
10. Black Market (paid): every buy → dismantle or buy → sell route loses gold (575-690g per crystal on average at L50, always 25% below the same Merchant item, no loop). The free version's resource faucet (21-119% of crystal income) is gone.
11. Forge fee on the difference: at one Runeforge level, steps and one big forge cost exactly the same, so splitting a forge saves nothing.

---

## 7. Questions and answers (user answers 2026-11-01; all Q1-Q12 RESOLVED)
| # | Question | Answer / recommendation |
|---|---|---|
| **Q1** | Crystals and sulfur from Mythic and Transcendent; should Unique be re-scaled? | **RESOLVED (USER):** Mythic 8 + 3, Transcendent 10 + 4, Unique stays 10 + 3 (no gems). Original reasoning: **Mythic 8 crystals / 3 sulfur; Transcendent 10 / 4.** This follows the budget curve (U1, R2, E3, Ex4, L6, M8, T10, roughly 1 crystal per 35 BP). **Keep Unique at 10 / 3**: it gives no gems, so the extra crystals make up for it, and its value multiplier (15) sits between Mythic (12) and Transcendent (20). |
| **Q2** | Mythic and Transcendent reroll sets per level | **RESOLVED (USER):** Mythic 2 at L9, 3 at L10. **Transcendent 2 at L10 only.** The proposed 1-set Transcendent reroll at L9 is removed: a single set is only "take it or keep yours". |
| **Q3** | When Exalted can be rerolled | **RESOLVED (USER):** from Runeforge L8, same sets as Legendary (2 / 3 / 4 at L8 / 9 / 10), 1 sulfur. |
| **Q4** | Black Market: 6 free Rare items (code) vs a paid shop (DB) | **RESOLVED (USER) 2026-11-01: PAID SHOP at 75% of the Merchant price.** 6 items, rolled once per object per battle, each bought once, gold from the in-battle balance, items to inventory. Full definition in Section 3.4. Simulator: 575-690g per crystal on average at L50, no loop. Stock 75% Rare / 25% Epic (RESOLVED (USER)). The free version (21-119% of crystal income depending on spawn rate) is retired; the code change comes later. |
| Q5 | Keep the Blacksmith rarity-upgrade unlocks (gf 13)? | **RESOLVED (USER): keep them; material conversion removed.** It only removes "Material Conversion". Note: Transcendent and Unique cannot be levelled today (not in the list or the code); unchanged. |
| Q6 | Fortune lines: gem or not? | **RESOLVED (USER), REVERSED from the recommendation:** Fortune lines DO become gems and CAN appear in rerolls. This reverses this morning's "Fortune out of crafting" rule (materials_system 19 crafting part, old gf 58). Fortune still never changes material / crystal / gem / sulfur drop chances. The team Fortune caps (loot_progression 11 / 17 / 28: ×2.00 loot quality, ×1.50 gold) limit it. Simulator tests T18. |
| Q7 | Downgrades and levelling credit | **RESOLVED (USER), REVERSED from the recommendation:** the item LOSES the stored levelling gold of the dropped levels (exact rule in Section 4.2). Downgrade stays free, no refund, re-upgrading costs full price. The "same total" equalities hold only for items never downgraded; the user accepts that downgrading always has a real cost. Simulator test T3. |
| Q8 | Keep −3% per Runeforge level? | **RESOLVED (USER): keep, on the forge fee only.** |
| Q9 | Threshold passives stack | Movement Range +1, Jump +1, Force +1, Stability +1, Discovery +1 and the range +1 passives are "Additive" and allowed on any equipment. With targeted gems a unit could reach about +6 or +7 Move across its gear. **RESOLVED (USER): NO CAP.** Consequence accepted: gems can reach about +6 / +7 Movement on one unit. The Simulator reports the maximum reachable value per threshold stat, for information only (T17). |
| Q10 | Reroll "keep current" option | **RESOLVED (USER): yes** (sulfur is paid either way). |
| Q11 | A separate "Remove line" action | **RESOLVED (USER): none.** Swaps cover it. |
| Q12 | Daily event reward | **RESOLVED (USER), revised 2026-11-01 after the Simulator:** 5 mercury per event, **1 sulfur per 3 completed events** (every 3rd completion, lifetime counter, Section 3.5). Was 1 sulfur per event, which the Simulator found would equal all loot sulfur after 15 events. Still needs the live_service_features 4 rewrite (Section 8 #5). |

### 7a. Decisions on the Simulator report (2026-11-01)
| # | Item | Status |
|---|---|---|
| S1 | Crystal steps stay 3 / 6 / 12, swaps 2 / 4 / 8; shortage accepted (income 275-318 vs need 460-685); no new crystal sources | **RESOLVED (USER)** |
| S2 | Crafted Epics L50-80 accepted up to about 15-17 (free crafter / rusher), 14-20 (boosted); upper bound | **RESOLVED (USER)** |
| S3 | Black Market = paid shop at 75% of Merchant (Q4) | **RESOLVED (USER)** |
| S4 | Daily event sulfur 1 per 3 events; mercury 5 per event | **RESOLVED (USER)** |
| S5 | Mercury from kills 5% (5 enemies per battle); dispatch amounts unchanged; dispatch frequency about 0.3 per battle | **DECIDED (DEV DEFAULT)**; frequency = WORKING ESTIMATE |
| S6 | Epic step fee OFF | **DECIDED (DEV DEFAULT)** |
| S7 | Forge fee on the rarity difference; swap fee = slot × 0.5 × rarity multiplier; Runeforge discount applies to both | **DECIDED (DEV DEFAULT)** |
| S8 | Fortune cap written as an explicit clamp (Expedition Fortune 0-1.75) | **DECIDED (DEV DEFAULT)** |
| S9 | G3 / G6 / G7 / G10 working values (Section 3.5) | **WORKING ESTIMATE** |
| S10 | G8 Epic-levelling route 568g cheaper | INFORMATION (not an exploit) |
| S11 | Real Epic-capacity gate 8,170g (Guild Hall L7) | INFORMATION (recorded) |

### 7a-2. Decisions on the Simulator re-check (2026-11-01, final pass)
| # | Item | Status |
|---|---|---|
| F1 | "+X% Fortune" = flat addition to Unit Fortune (like Lucky, TRAIT-P-037): T1-T4 +0.05 / +0.10 / +0.15 / +0.20. Unit Fortune = LUK/(LUK+200) + flat bonuses; Expedition = highest + 50% 2nd + 25% 3rd; clamp 0-1.75 after every bonus. Gear-only cap 9 T4 (7 with Lucky (Greater) ×3, 4 with Fountain/Idol); natural gems ≈ ×1.53; at-cap income crystals 466/320, gems 386/229, sulfur 23.0/15.6, mercury 2,395/1,818 | **RESOLVED (USER)** |
| F1b | No per-unit Fortune limit | **DECIDED (DEV DEFAULT)** |
| F2 | Black Market stock 75% Rare / 25% Epic, never Exalted or above | **RESOLVED (USER)** |
| F3 | economy_framework 36 → "Robux cannot buy materials DIRECTLY (mercury, crystals, rune gems, sulfur)". Gold Boost may speed up materials indirectly through buying shop gear to dismantle; accepted because it always loses gold and is limited by shop stock | **RESOLVED (USER)** |
| F4 | Crafted-Epic target restated: CRAFTED Epics L50-80 up to about 15-17 (free) / 14-20 (boosted). Information: with bought Epics (Merchant + Black Market at 1-3% spawn) a boosted player can hold about 24-27. The R4 FAIL is closed by this restatement; 75/25 kept | **DECIDED (DEV DEFAULT)** |
| F5 | Wording: Black Market 575-690g per crystal on average (Rare-only 575g, 75/25 690g), always 25% below the same Merchant item; daily events "about 22-23 events" to pass 20 levellings | **DECIDED (DEV DEFAULT)** |
| F6 | Swap fee stays slot × 0.5 × rarity multiplier. Quirk recorded (raise cheaper in gold than a later swap; crystals go the other way; no loop). Alternative × 0.375-0.40 recorded, not chosen | **DECIDED (DEV DEFAULT)** |
| F7 | Facility spending with realistic crafting at final fees: free 5-7 of 10 maxed, ≈ 109-112%; boosted 10/10, ≈ 85-89% | **DECIDED (DEV DEFAULT)** (recorded result) |
| F8 | Dev note: re-apply the Fortune clamp after the Thief single-reward bonus (otherwise ×2.79) | **DECIDED (DEV DEFAULT)** (Section 13) |

### 7b. Nothing open for the user — working estimates only (do NOT block approval)
All user questions are answered. These stay as WORKING ESTIMATES and can be tuned later without changing any rule in this draft:
1. **Black Market spawn rate** (G4, 1-5% of battles) — part of open_decisions 48 (object density), which stays open on its own.
2. **Daily events per lifetime** (G3) — planning number still to come.
3. **Dispatch frequency** (G2, about 0.3 mercury per battle).
4. **Gem drop weights** (G6, equal weights, 10% passives).
5. **Equipment drops per battle** (G7, 0.40).

---

## 8. Conflicts with locked rules outside the user's list
1. **item_rarity_rules 3** (and gf 56): "The Runeforge never adds Bonus Passives". v2 installs passive gems. Rewrite it: passive gems allowed, the passive slot limit is unchanged (1; 2H 2).
2. **Fortune** (gf 58, old E6, materials_system 19 crafting part): **RESOLVED (USER) Q6** — Fortune becomes gems and can appear in rerolls. Rewrite gf 58 and the crafting part of materials_system 19; the drop-rate part of materials_system 19 stays. loot_progression 11 / 12 / 16 / 17 / 28 (the caps) are unchanged and now also limit crafted Fortune.
3. **BUG-054:** passive-gem installs must reuse the generator's gear-type check (Section 2.2), never the free-text column. Regression check: no off-hand or gloves may accept PAS-016 to 021 or PAS-023 to 025.
4. **economy_framework 36** — **RESOLVED (USER) 2026-11-01.** Reword to: "Robux cannot buy materials **DIRECTLY** (mercury, crystals, rune gems, sulfur)." Record in the notes: Gold Boost (+25% gold) can speed up materials **indirectly**, by buying shop gear to dismantle. This is accepted because it always loses gold and is limited by shop stock. Superseded row (Section 10).
5. **live_service_features 4 / unit_progression 84:** daily events give "special resources not obtainable through normal loot". Sulfur and mercury can also come from loot. Rewrite to: "Daily events give 5 mercury each, and 1 sulfur on every 3rd completed daily event" (RESOLVED (USER) 2026-11-01).
6. **guild_facilities 12 / 13:** remove "Material Conversion at L3" (rarity unlocks → Q5).
7. **project_rules 109 / 111 / 112:** wording only (mercury; gem storage is also separate and has no cap). Downgrade still gives "no compensation".
8. **item_generation_steps 7 / 10:** 7: "Add refuses a family" → "a gem of an existing family replaces that line". 10: remove starting level and shop-bought; add levelling credit.
9. **objects_encounters 20** (Treasure Chest "gold, equipment, materials and **runes**"): the word "runes" now clashes with rune gems. **DECIDED (DEV DEFAULT):** chests give no rune gems and no crystals; reword "runes" (consistent with "no new crystal sources").
10. **objects_encounters 31** (Black Market) vs the code → **RESOLVED (USER) Q4: paid shop** (Section 3.4). Rewrite the row: price = 75% of Merchant, stock rolled once per object per battle, each item bought once; "Unlimited" uses now means repeat visits only. Code change for the Dev later (the current code gives 6 free Rares).
11. **battlefield_events 35** (Crystal Golem "5× material reward") → 5× mercury.
12. **loot_progression 15:** boss Runeforge drops count toward the 3-per-day limit. No conflict, just stated.
13. **Q9 threshold stacking: RESOLVED (USER), no cap.** This matches item_rarity_rules 15 / 20 ("overpowered combinations are acceptable"). No new rule. Recorded consequence: about +6 / +7 Movement on one unit from gems.
14. **gf 15 / economy_framework 14:** the note "Sells as Common (enchanted)" stays. No conflict.
15. **Crystal supply vs "charge every step" — RESOLVED (USER) 2026-11-01:** the Simulator confirmed the shortage (need 460-685, income 275-318). The user **keeps** 3 / 6 / 12 and 2 / 4 / 8 and adds no crystal sources. Mixed-rarity teams are the intended result. The old T11 target "crystals must not run out before gems" is dropped.
18. **NEW — economy_framework 15 notes:** the 2026-11-01 ruling "free rusher up to 8, boosted 9-14" is replaced by "CRAFTED Epics, L50-80: up to about 15-17 (free) / 14-20 (boosted)", plus the information line "including bought Epics (Merchant + Black Market at 1-3% spawn), a boosted player can hold about 24-27" (DECIDED (DEV DEFAULT)).
19. **NEW — Fortune cap:** loot_progression 11 says "theoretical maximum". It needs the explicit clamp (Section 3.3). The Idol of Fortune note (objects_encounters 32) already clamps at 1.75, so it stays consistent.
20. **NEW — gear Fortune target (RESOLVED (USER)):** bonus_numerical_attributes 70-73 get the missing target: flat +0.05 / +0.10 / +0.15 / +0.20 Unit Fortune, same as the Lucky trait. unit_traits rows are unchanged.
16. **NEW — Fortune reversal vs the morning's design:** the open_decisions 123 text and old gf 58 say Fortune is out of crafting. Both are in the superseded list (Section 10).
17. **NEW — "same total" wording:** gf 48 / economy_framework 19 wording that promises the same total in any order must now say "for items never downgraded".

No conflict found with trigger safety (TRG rules) or the stat order rules. Gems only allow lines that loot could already roll on that item, and they use the same stacking rules.

---

## 9. Save impact
**Per item (ItemInstance, DataStore Key 2):**
| Field | v2 |
|---|---|
| starting_level | **DROP** as a separate field (planned, never built). Its job moves into the levelling record as the free level F. |
| shop_bought | **DROP** (planned, never built). |
| starting_rarity | **KEEP** (sell value; Epic step fee is OFF, so only sell value now). Old items = their current rarity. |
| reroll_count | **KEEP** (fixes the reroll sets). Old items = 0. |
| **levelling_record (new, replaces the single levelling_credit number)** | Free level F + at most 10 (item level, Blacksmith level) pairs (Section 4.1). The credit `C` is calculated from it. Old items: F = current level, no pairs (credit 0). New items: F = the level they arrive at. |

**Per profile (currencies, Key 2):**
- **mercury**, **crystals**, **sulfur**: 3 whole numbers.
- **daily_events_completed** (new): 1 whole number, lifetime count, never resets. It drives the "every 3rd event gives 1 sulfur" rule.
- **rune gem map**: count per gem ID, at most about **153 kinds** (25 numeric families × T1-T4 = 100, now including Fortune per Q6, + 53 passives).
- Remove the T1-T5 counters (after the 1:1 merge) and the 3 Essence counters the Dev built this morning (not yet used).

**Size:**
- Gem map worst case about 1.2 KB with short number IDs (save_data_contract 9), about 3 KB with text IDs. The DataStore limit is 4 MB per key.
- Items: about +20 bytes each typically (1-3 record pairs, reroll count, starting rarity); worst case about +70 bytes (10 pairs). Even 1,000 items at worst case is about 70 KB.
- Gem map worst case is about the same as before (153 instead of 149 entries).

**Facility levels:** the Runeforge level is saved with the other buildings (gf 39, unchanged).

---

## 10. Locked DB rows this supersedes (rewrite in one pass after approval)
**User-listed**
- guild_facilities **40, 41, 42, 43, 44, 45, 46, 47 (delete), 48 (replace with the levelling record + downgrade rule), 49 (keep numbers), 50, 51, 52, 53, 54, 55, 56, 57, 58**
- materials_system **1, 6, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25 (delete), 26 (delete), 27 (delete), 28, 29, 30, 31, 32, 33, 36, 40, 41, 42**
- economy_framework **14, 16, 19**
- equipment_schema **16 (delete), 17 (delete), 18, 19** + new row 20 levelling_record
- save_data_contract **3**
- service_boundaries **15, 16, 18**
- open_decisions **23, 123** (+ a new open_decisions row: Q1-Q12 RESOLVED (USER) 2026-11-01; open items = Section 7b)
- implementation_plan **53**

**Changed by the user answers of 2026-11-01**
- guild_facilities **47**: delete the reach rule and write the new downgrade rule (item loses the stored levelling gold of the dropped levels; Section 4.2).
- guild_facilities **48** / economy_framework **19**: "same total" wording limited to items never downgraded; remove the "Enchant before upgrading" hint.
- guild_facilities **44 / 58** and materials_system **19 (crafting part only)**: Fortune becomes gems and can appear in rerolls. The drop-rate exclusion in materials_system 19 stays.
- guild_facilities **43 / 55** (forge cost): crystals charged for every rarity step crossed; "charged once per forge" text removed.
- guild_facilities **13**: kept (Q5); only Material Conversion removed from 12 / 13.
- No new row for a threshold-passive cap (Q9: no cap).

**Changed by the Simulator decisions of 2026-11-01 (this pass)**
- guild_facilities **43 / 55** (forge cost): forge fee charged on the rarity difference (Common = 0); new swap fee = slot × 0.5 × rarity multiplier; discount on both; Epic step fee removed (OFF). **gf 57** (old Epic step fee idea): mark superseded / OFF.
- guild_facilities **46 / 49** notes: real Epic-capacity gate 8,170g (Guild Hall L7).
- materials_system **7-14** (drop sources): kill mercury 5%; dispatch 1 / 2 per mission; daily event 5 mercury + 1 sulfur per 3 events.
- economy_framework **15** notes: crafted Epic range replaced (15-17 / 14-20, upper bound).
- objects_encounters **31**: Black Market becomes a paid shop (Section 3.4).
- loot_progression **11** (+ 17 / 28 wording): explicit Fortune clamp, Expedition Fortune 0-1.75.
- loot_progression **70** (+ 26): note that elite crystals / mercury are separate fixed grants, always given, Fortune never applies.
- loot_progression **24, 26, 69** notes: keep the working estimates (0.40 drops, 0.034 elites) and label the new G-values as WORKING ESTIMATE.
- live_service_features **4** / unit_progression **84**: daily event wording (5 mercury + 1 sulfur per 3 events).
- save_data_contract **3**: add daily_events_completed.
- **Not touched:** open_decisions **48** (object density) stays OPEN.

**Changed by the re-check decisions of 2026-11-01 (final pass)**
- bonus_numerical_attributes **70, 71, 72, 73**: Fortune T1-T4 = flat +0.05 / +0.10 / +0.15 / +0.20 Unit Fortune (like TRAIT-P-037).
- loot_progression **11** (+ 17 / 28): Unit Fortune formula with flat bonuses, Expedition formula, clamp 0-1.75 after every bonus including Thief, no per-unit limit, at-cap income numbers.
- economy_framework **36**: "Robux cannot buy materials DIRECTLY (mercury, crystals, rune gems, sulfur)" + Gold Boost indirect-speed note (accepted).
- economy_framework **15** notes: crafted-Epic target restated (crafted only) + bought-Epics information line (about 24-27).
- objects_encounters **31**: stock 75% Rare / 25% Epic, never Exalted+; 575-690g per crystal wording.
- guild_facilities **43 / 55**: swap-fee quirk note and the not-chosen × 0.375-0.40 option.
- guild_facilities **46 / 49** notes (or economy_framework 43-46): facility spending result (free 5-7/10, 109-112%; boosted 10/10, 85-89%).
- implementation_plan **53**: Section 13 dev notes (Thief re-clamp).
- open_decisions new row: all user items RESOLVED; only the five working estimates remain (Section 7b).

**Also affected (found by the Designer)**
- guild_facilities **1, 4, 5, 12, 13, 35, 36, 37, 38**
- materials_system **2, 3, 4, 5** (tier names), **7-14** (drop sources), **34** (preview text "10× Polished Core"), **37, 38, 39** (benchmarks)
- economy_framework **20, 21, 36, 43, 44, 45, 46**
- equipment_schema **4, 5** (wording)
- item_rarity_rules **3** (14 and 23 unchanged)
- item_generation_steps **7, 10** (8 unchanged)
- project_rules **109** (111 / 112 wording)
- open_decisions **21, 22, 24**
- live_service_features **4** (5 wording) · unit_progression **84, 99**
- objects_encounters **20, 31** · battlefield_events **35**
- loot_progression **24, 26** notes (working estimates referred to Essences)

---

## 11. Simulator test list (expected numbers)
| # | Test | Expected |
|---|---|---|
| T1 | Equality: enchant early vs late, **items never downgraded** (1H / 2H / Body / Gloves, Common → Epic, L1-99) | Identical totals: 29,596 / 44,395 / 23,677 / 14,798g (discount of the Blacksmith level needed); at Blacksmith L10 all game 25,926 / 38,889 / 20,740 / 12,963g; + the same forge fee. Catch-up at L99, 1H = 22,197g. (Unchanged.) |
| T2 | Equality: total levelling gold the same whether enchanted at L1, L50 or L99 (**never-downgraded items only**) | Same as T1. Also the mixed discount case (L1-50 −12%, L51-99 −27%): 27,725 = 27,725. Every order, every rarity step (Common → Uncommon → Rare → Epic) lands on the same final gold total. (Unchanged.) |
| T3 | **Downgrade rule (RESOLVED (USER) Q7, CHANGED):** no route using downgrades makes enchanting or levelling cheaper than the straight route, in gold or mercury | Example 1H Common → Epic, L1-60 at −15%, down to 30, back to 60 at −27%: early forge **20,891g**, middle **14,420g**, late **14,420g**; straight route (no downgrade, same end result) **12,262g**. Every downgrade route must be ≥ the straight route (Designer random check: 20,000 routes, never below, smallest gap 0g). Mercury: always ≥ straight (lost levels cost 1 each again). Also confirm the earlier "about 5,500g cheaper late" gap (D2: 15,333 vs 20,891) can never go below the straight route, and that a "reset to 0" version WOULD (control case, up to about −13,500g). Record check: at most 10 pairs; downgrade below the arrival level lowers F. |
| T4 | Rounding | Running-total vs per-level rounding: +52g (1H Common L1-99), +48g (1H Epic). Whole-number math only. |
| T5 | Buy → dismantle → sell | Gold back = 0 (nothing sellable). Always loses 100% of the price. |
| T6 | Buy → upgrade → dismantle | Mercury net ≤ 0 for every start/end level. Best case is the 10n → 10n+1 step at 0 net mercury, with gold lost. |
| T7 | **Black Market — PAID SHOP (Q4 RESOLVED (USER), CHANGED)** | 6 items rolled once per object per battle, each bought once; price = floor(Merchant price × 75 / 100); mix Rare 75% / Epic 25%, no Exalted (RESOLVED (USER)). Expected: every buy → dismantle / sell route loses gold; 575-690g per crystal on average at L50, always 25% below the same Merchant item (re-check PASS: 10,072 routes, best −344g); report the Epic slots' effect on L50-80 Epic supply and crystals per gold for Epic slots; report at 1 / 3 / 5% spawn (rate = WORKING ESTIMATE, open_decisions 48). |
| T8 | Recruit weapon | L50 Standard hire 950g → 1 Common L50 weapon → 5 mercury (190g each). Must never beat the shop (Common Gloves L50 79g per mercury). |
| T9 | Crafted Epic supply (L50-80) | **CRAFTED Epics only:** up to about 15-17 (free) / 14-20 (boosted). Information: with bought Epics (Merchant + Black Market 1-3%) boosted ≈ 24-27 (Merchant alone 23.6-25.8). Re-check R4 FAIL closed by this restatement. Epic step fee OFF. |
| T10 | Gem-transfer loops (forge → dismantle; swap; reroll → dismantle) | **CHANGED:** crystals per forge-then-dismantle cycle −2 (Common → Uncommon), −4 (Uncommon → Rare), −9 (Rare → Epic), **−18 (Common → Epic)**; gems never increase; sulfur −cost per reroll. |
| T11 | Crystal and gem income vs need | **ACCEPTED SHORTAGE (USER) 2026-11-01:** income 275-318 vs need 460-685; no levers. Information only: full team to Uncommon / Rare / Epic ≈ 0.5 / 1.4 / 3 lifetimes. No re-run needed unless other numbers change. |
| T12 | **Mercury income vs the wall (CHANGED: kills 5%)** | Kills 5% × 5 enemies (0.25 per battle), dispatch ≈ 0.3 per battle, 75-100% dismantling → **15.9-18.9** full L1-99 levellings (target 15-20). Also report with daily events at 0 / 10 / 20 / 50 events (+50 mercury per 10) and the event count where 100% dismantling passes 20. The old 10-item scenario ≈ 305-447 mercury. |
| T13 | **Sulfur (CHANGED: daily sulfur 1 per 3 events)** | 13.7-15.2 from loot + floor(events / 3) from daily events (every 3rd completion; lifetime counter never resets; e.g. 10 events → 3, 15 → 5). Report rerolls per lifetime per rarity at 0 / 10 / 20 / 50 events. Sets offered unchanged. |
| T14 | Facility economy | With realistic crafting at the final fees (re-check R1g): free player 5-7 of 10 facilities maxed, ≈ 109-112%; boosted 10/10, ≈ 85-89%. |
| T15 | Save size | Gem map ≤ **153** entries, ≤ 3 KB; items about +20 bytes typical, ≤ about +70 bytes worst (levelling record ≤ 10 pairs); total well under 4 MB. |
| T16 | Compatibility (BUG-054) | No off-hand or gloves accepts PAS-016 to 021 or PAS-023 to 025; no already-elemental weapon accepts a transformation; passive slot limit holds; one line per family. |
| T17 | Threshold stacking (Q9: **NO CAP, user decision** — information only, not pass/fail) | Report the maximum reachable value on one unit from gems + gear for each threshold stat: Movement, Jump, Force, Stability, Discovery and each range +1 passive. Expected about +6 / +7 Movement. |
| T18 | Fortune gems (Q6) | PASS (Simulator 2026-11-01), conditional on the clamp, which is now an explicit rule (Section 3.3: Expedition Fortune 0-1.75). Re-check PASS (R5, 300,000 builds): ≤ ×2.00 / ×1.50, ≥ ×1.00, provided the clamp is applied again after the Thief bonus (Section 13). |
| T19 | **NEW — crystal steps** | Common → Epic = 21 crystals whether in one forge or in steps (3 / 9 / 21 / 18 / 12 for the routes in Section 2.3). A forge that swaps and raises rarity pays only the steps crossed (e.g. Rare swap + T4 → Epic = 12). A forge that keeps rarity = 2 / 4 / 8. |
| T21 | **NEW — forge fee on the rarity difference + swap fee** | Forge fee = P(new) − P(old), P(M) = floor(slot × M × (100 − d) / 100), Common M = 0. 1H Common → Epic = **400g** in one forge and in steps (150 + 100 + 150); at Runeforge L10 292g both ways (109 + 73 + 110). Same for every slot (Section 2.3 tables). Swap fee 1H 75 / 125 / 200 (L10: 54 / 91 / 146). Swap + raise pays the forge fee only. T1 / T2 equality unchanged. Re-run T14 with crafting (fees: 25 Epic forges + 20 swaps at the new swap fee). |
| T20 | **NEW — Fortune in rerolls and compatibility** | Rerolls can offer Fortune lines at their normal loot weight; Fortune gems can be installed on any equipment (eligible_equipment "Any equipment"); Fortune drop-chance exclusion still holds for all resource drops. |

---

## 12. UI text list (draft wording)
- **Downgrade prompt:** "Lower **{item}** to level **{N}**? Downgrading is free, but the gold and mercury spent on those levels are **lost and not refunded**. Raising it again costs full price ({g} gold + {m} mercury at today's prices)." Buttons: **Downgrade** / **Cancel**.
- **Above-Epic dismantle prompt:** "Dismantle **{item}** ({rarity})? You get {M} mercury, {C} crystals and {S} sulfur. Its bonus stats become rune gems, but any stat stronger than Epic becomes an **Epic-tier** gem. Passives above Epic ({names}) give **no rune gem** and cannot be transferred. This cannot be undone." Buttons: **Dismantle** / **Cancel**.
- **Unique dismantle confirm:** "Dismantle **{item}**? Unique items give {M} mercury, 10 crystals and 3 sulfur, but **no rune gems**. Its unique effects are lost forever. This cannot be undone." Buttons: **Dismantle Unique** / **Cancel**.
- **Sell note:** "Sells as **{starting rarity}** (enchanted)"
- **Forge preview:** "Rarity: {old} → {new} · Cost: {g} gold + {c} crystals" / "Includes {x} gold to bring this item's past levels up to {new} price."
- **Swap warning:** "The old attribute **{name}** will be destroyed. No gem is returned."
- **Reroll:** "Choose a new set of attributes, or keep the current one. The sulfur is spent either way."
- **Forge crystal line:** "Crystals: {c} ({steps}: each rarity step costs 3 / 6 / 12)"
- **Swap fee line:** "Swap cost: {g} gold + {c} crystals (rarity stays {rarity})."
- **Black Market:** "Black Market — 25% off Merchant prices. Each item can be bought once. Gold: {balance}." Buy button greyed out with "Not enough gold" when the price is above the balance.
- **Removed everywhere:** the old hint "Enchant before upgrading to pay less." It is no longer true (RESOLVED (USER) 2026-11-01). No screen, tooltip or prompt may show it.

---

## 13. Implementation notes for the Dev (build later; not a design change)
- **Fortune clamp order (DECIDED (DEV DEFAULT), from re-check R5):** the Thief single-reward bonus (doctrines 11, "for that reward only") is applied **after** Expedition Fortune is worked out. The clamp to 0-1.75 **MUST be applied again after it**. Otherwise loot reaches ×2.79.
- Fortune order: Unit Fortune = LUK/(LUK+200) + flat bonuses (Lucky traits, gear Fortune lines +0.05-0.20), no per-unit limit → Expedition Fortune = highest + 50% of 2nd + 25% of 3rd → clamp → Fountain / Idol → clamp → Thief (per reward) → clamp.
- Black Market: replace the 6-free-Rares code with the paid shop (Section 3.4), stock 75% Rare / 25% Epic.
- Swap fee stays × 0.5; do not "fix" the raise-vs-swap quirk (Section 2.3).
