# CTRBLXAI — Blacksmith + Runeforge v2 — DRAFT PROPOSAL (2026-11-01)

**Status: DRAFT for Simulator testing and user approval. Nothing here is in the database yet.**
**Updated 2026-11-01 with the user's answers (Q1-Q3, Q5-Q12, crystal steps, stacking, UI hint). Q4 is still OPEN. Previous version backed up as blacksmith_runeforge_v2_proposal_20261101_before_answers.md.**
The database, the spreadsheets and INDEX.txt were read only, never written. After the Simulator checks this and the user approves it, every row in Section 10 gets rewritten in one pass.

Sources read (read-only): guild_facilities 1-58, materials_system 1-42, economy_framework 1-49, equipment_schema 1-19, save_data_contract 1-15, service_boundaries 14-18, open_decisions 21-24/123, implementation_plan 53, item_rarity_framework, item_rarity_rules 1-25, bonus_numerical_attributes (117 rows), bonus_passives (55 rows), loot_progression 1-84, the bug registry (BUG-050, BUG-054), and, read only, the dispatch reward, recruit weapon and Black Market code.

---

## 0. One-screen summary

| Topic | v2 proposal |
|---|---|
| Blacksmith | Levels items only. Max level = Blacksmith level × 10 (L10 = 99). Gold discount stays 3% per level (L10 = −27%). |
| Upgrade cost | **1 mercury per level, every rarity.** Gold uses the same formula shape as today (economy_framework 19), but rounded on a running total (Section 4). |
| Downgrade | Free, unlimited (no Blacksmith-level reach rule). No refund. **The item loses the stored levelling gold of the levels it drops** (RESOLVED (USER) Q7, Section 4.2), so re-upgrading costs full price and downgrading always has a real cost. |
| Dismantle | Any item, from any source. Not allowed on equipped items. Mercury = ceil(level / 10). Crystals C0 / U1 / R2 / E3 / Ex4 / L6 / Unique 10. 1 rune gem per bonus line (Unique: none). Sulfur Ex1 / L2 / Unique 3. **Mythic 8 crystals + 3 sulfur, Transcendent 10 + 4** (RESOLVED (USER) Q1). Fortune lines also become gems (RESOLVED (USER) Q6). |
| Runeforge "forge" | Install 1 or more rune gems. Crystals: **every rarity step crossed is charged**: to Uncommon 3, to Rare 6, to Epic 12, so Common → Epic = 3 + 6 + 12 = **21** in one forge or in steps (RESOLVED (USER)). A forge that keeps the rarity on an Uncommon / Rare / Epic item = **2 / 4 / 8**. Replaced lines are destroyed. |
| Forge gold | **Forge fee** = slot value × new rarity multiplier (1H Epic = 400g; never depends on item level) **+ levelling catch-up** (the extra levelling gold the item's past levels would have cost at the new rarity). Both "same total" goals hold **exactly for items never downgraded**; a downgrade always adds a real cost (Q7). |
| Per-item saved number | **Levelling record**: the level the item arrived at plus a short list (at most 10 entries) of which Blacksmith discount each level was bought at. The levelling credit (gold paid, at "Common price", whole units) is calculated from it, so downgrades can remove exactly what the dropped levels added. It replaces starting_level and shop_bought. |
| Runeforge levels | Uncommon capacity at L1, **Rare at L4, Epic at L7**. Sulfur rerolls at L8-10. −3% per level on the forge fee only (RESOLVED (USER) Q8). |
| Rerolls (sulfur) | Each reroll offers N full attribute sets plus a "keep current" option (RESOLVED (USER) Q10). Exalted and Legendary 2 / 3 / 4 sets at L8 / 9 / 10 (RESOLVED (USER) Q3). Mythic 2 / 3 at L9 / 10. **Transcendent 2 at L10 only** (RESOLVED (USER) Q2). Fortune can appear (Q6). Sulfur per reroll: Exalted 1, Legendary 2, Mythic 3, Transcendent 4. |
| Elite / boss drops | Elite: 3 crystals, 50% chance of 1 gem, 25% chance of 1 sulfur at L60+. Boss: 5 crystals, 1 gem, 1 sulfur at L60+. Fortune never applies. |
| Mercury drops | About 1.5 per battle (was about 2.6 gear materials): kills 10%, elite 2, boss 3, chest 1, quests about 0.3, dispatch 1-2, daily event 5 mercury + 1 sulfur (RESOLVED (USER) Q12). |
| Selling resources | Mercury, crystals, gems and sulfur **cannot be sold**. That closes every gold loop. |
| Conversion / T5 rules | Obsolete (there is only one material now). Material conversion removed; the Blacksmith keeps its rarity-upgrade unlocks (RESOLVED (USER) Q5). Old T1-T5 balances become mercury 1:1. The 3 Essence counters are removed. |
| Fortune | Fortune lines become rune gems and can appear in rerolls (RESOLVED (USER) Q6, reverses this morning's "Fortune out of crafting" rule). Fortune still never changes material, crystal, gem or sulfur drop chances. The existing team Fortune caps limit it (×2.00 loot quality, ×1.50 gold). |
| Movement / Jump / Force-type stacking | **No cap** (RESOLVED (USER)). Gems can reach about +6 / +7 Movement on one unit. |
| Black Market | **Still OPEN (Q4).** The Simulator tests both the free version and a paid shop. |
| Epic step fee | Kept as an OPTIONAL setting, **default OFF**. If turned on: a fee that does not depend on item level (1H Common start = 1,000g). The Simulator decides. |

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

**Gold = forge fee + levelling catch-up (+ the optional Epic step fee):**
- **Forge fee** = floor(slot value × rarity multiplier of the result × (100 − Runeforge discount %) / 100). It does **not** depend on item level.

| Slot (value) | to / on Uncommon | Rare | Epic | Epic at Runeforge L10 (−27%) |
|---|---|---|---|---|
| 1H (100) | 150 | 250 | 400 | 292 |
| 2H (150) | 225 | 375 | 600 | 438 |
| Body (80) | 120 | 200 | 320 | 233 |
| Off-Hand / Head (60) | 90 | 150 | 240 | 175 |
| Accessory (70) | 105 | 175 | 280 | 204 |
| Gloves / Feet (50) | 75 | 125 | 200 | 146 |

- **Levelling catch-up** (only when the rarity rises) = the levelling gold the item has already been paid at its old rarity, re-priced at the new rarity, minus what was paid. The exact formula is in Section 4. This part **rises with item level**: it is 0 on a fresh drop, and up to 22,197g for a 1H Common → Epic levelled from L1 to 99. **No discount** ever applies to it (that would break the equality).
- **Optional Epic step fee (default OFF; the Simulator decides):** charged the first time an item becomes Epic. Fee = floor(0.5 × (L1 shop Epic price − L1 shop price at the starting rarity)). That is the old gf 57 idea, priced at level 1 so it does not depend on item level.
  - 1H: Common start 1,000 / Uncommon 900 / Rare 700g.
  - 2H: 1,500 / 1,350 / 1,050g.
  - Gloves: 500 / 450 / 350g.
  - No facility discount.
  - Recommendation: turn it ON only if the Simulator finds more crafted Epics at L50-80 than the range the user accepted on 2026-11-01 (free rusher up to 8, boosted 9-14).

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
- The cumulative cost to reach Epic capacity (L7) is 4,085g. Under the old design Epic came at L10 (8,919g), so crafted Epics come earlier → Simulator check T9.
- *Runeforge discount: −3% per level, **on the forge fee only** (RESOLVED (USER) Q8). Levels 2, 3, 5 and 6 still give something. It never applies to the catch-up, crystals, gems or sulfur.
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
| Normal kill | 20% → 1 | **10% → 1** (about 0.8 per battle) |
| Elite encounter | 75%, 2-3 | **2** (when rewarded) |
| Boss | 100%, 3-5 | **3** |
| Treasure chest | 1-2 | **1** |
| Quest reward | varies | **1-3, shown up front** (about 0.3 per battle) |
| Dispatch | 1-3, one tier below content | **1 per mission; 2 for tier 4-5 missions** |
| Daily event | T5 only | **5 mercury + 1 sulfur** (see the conflict in Section 8 #5) |
| Salvager's Cap | 30% → 1 | 30% → 1 (unchanged) |
| Crystal Golem | 5× material reward | 5× mercury reward |

- Battle drops come to about **1.47 per battle** (was about 2.6) → about **800 lifetime**.
- Dispatch was never counted in the old 2.6 figure. The Simulator must add it (rough guess about 0.6 per battle → about 330).
- **Dispatch change for the Dev:** DispatchService currently grants "matTier / matCount" (one tier below content, 1-3). In v2 the tier goes away and the count becomes the mercury amount above.
- **Mercury from dismantling:** about 5.45 per item on average (items drop at enemy level). At 0.40 equipment drops per battle (working estimate, loot_progression 24) → about 219 drops in a lifetime. Dismantling 75-100% of them gives **about 890-1,190 mercury**.
- **Lifetime mercury income:** about 1,700-2,300 → about **17-23 full L1-99 levellings**. Dismantling is now the biggest source (about 50-55%).
- **Lifetime need:** 98 per full levelling. The old "10 upgrades" scenario (670 gear materials with rarity multipliers) works out to roughly 300-450 mercury → comfortable.
- **New material wall:** about 17-23 items levelled fully (today 12-15), and it only matters for cheap gear, because gold runs out first for Rare and up (Epic 1H L1-99 = 29,596g).
  - Simulator target: a wall of **15-20** full levellings.
  - Tuning levers: kill chance (10% → 7% takes about 240 off the lifetime total) and the dispatch amount.
- **Sell price: none — mercury cannot be sold** (recommended). Even at the old T1 price (5g), shop → dismantle → sell loses gold. But "cannot be sold" is simpler and closes every route for good. It removes the small "emergency gold" use (materials_system 28), which is accepted.
- **T5 restriction (materials_system 6/18): obsolete.** There are no tiers, so daily events no longer have an exclusive material. In v2 sulfur is the "daily-paced" resource.
- **Conversion 3:1 (materials_system 25-27, gf 12/13 "Material Conversion at L3"): obsolete, delete.**
- **Migration:** the old balance T1 + T2 + T3 + T4 + T5 becomes mercury 1:1. The 3 Essence counters are removed; any test balance is dropped.

### 3.2 Crystals, rune gems, sulfur
**Elite and boss drops (separate from the equipment roll; Fortune never applies):**
| Source | Crystals | Rune gem | Sulfur |
|---|---|---|---|
| Elite encounter (each completed one) | **3** | **50%: 1 gem**, rolled as one line of a Rare item of the encounter level, random slot | content L60+: **25%: 1** |
| Boss (counts toward the 3-per-day boss reward limit, loot_progression 15) | **5** | **1 gem**, rolled as one line of an Epic item (Rare item below L40) | content L60+: **1** |

- Gems from drops are Epic tier at most, like all gems. Fortune gems can be rolled here like any other line, but Fortune never changes these drop chances.
- **Fortune and income (RESOLVED (USER) Q6):** a high-Fortune team finds better-rarity loot (team cap ×2.00 loot quality, ×1.50 gold), and dismantling better loot gives more crystals and sulfur. That is the same indirect effect already accepted for Essences (materials_system 19). Fortune gems make it easier to reach the cap, but cannot push past it. The Simulator measures it (T18).
- Optional levers (not proposed): quests may show crystals or gems up front; treasure chests 25% → 1 crystal.

**Working income estimate (lifetime, 547 battles, 0.40 drops per battle, elite and boss each about 0.034 per battle):**
| Resource | Dismantling 75-100% of drops | Elite + boss | Total |
|---|---|---|---|
| Crystals | 127-169 | 56 + 93 | **≈ 276-318** |
| Rune gems | 131-175 | 9 + 19 | **≈ 159-203** (spread over about 153 gem kinds) |
| Sulfur | 4.5-6 | 1.9 + 7.4 | **≈ 14-15**, plus 1 per daily event |

**Need for 7 units × 6-7 gear (about 45 items):**
- Crafting all 45 from Common to Epic = **945 crystals** (21 each; was 540 when charged once per forge).
- Natural Epic-and-up drops: about 19 lifetime (13 Epic).
- So a realistic roster crafts about 25 Epics plus about 20 swaps (160). With every step charged, the 25 Epics cost **300 (all started from Rare) to 525 (all from Common)**, so the total is about **460-685 crystals** (was about 460). Income is about 276-318 without shop dismantling, so **crystals are now likely to run short before gems** → see Section 8 #15 and test T11.
- **Gems:** about 2 gems per Epic craft is not the bottleneck in number. **Getting the specific gem you want is the bottleneck**, as the user intends: about 153 kinds (now including the 4 Fortune tiers), about 180 gems in a lifetime, so roughly 1-2 copies of any one kind.
- If the Simulator finds crystals limit players before gems do, raise the elite/boss crystals or turn on the chest crystal lever.

**Shop → dismantle prices (the gold gate; gold per resource):**
| Map level | Gloves Common → mercury | Gloves Uncommon → 1 crystal | Gloves Rare → 2 crystals | Gloves Epic → 3 crystals |
|---|---|---|---|---|
| 10 | 236g → 1 | 354g | 590g | 1,416g |
| 50 | 396g → 5 (79g each) | 594g | 990g | 2,376g |
| 91-99 | 560-592g → 10 (56-59g each) | 840-888g | 1,400-1,480g | 3,360-3,552g |

Each shop item also gives its gems, which is targeted gem hunting paid for with gold (allowed by the user).

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
- **Runeforge rarity raise R_old → R_new:** catch-up = `Paid(C, R_new) − Paid(C, R_old)`, plus the forge fee, plus the optional Epic step fee.
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
| Runeforge discount | The forge fee does not depend on item level, so equality holds **at the same Runeforge level**. Forging after a Runeforge upgrade is cheaper only through the facility level, not the item level. The discount never touches the catch-up. |
| Optional Epic step fee | Does not depend on level, so equality holds. |
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
- The Epic step fee is optional (above).

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
9. Fortune gems: Fortune never changes resource drop chances, and the team Fortune cap still applies. Any extra income from better loot is bounded by that cap (measured in T18).

---

## 7. Questions and answers (user answers 2026-11-01; only Q4 still OPEN)
| # | Question | Answer / recommendation |
|---|---|---|
| **Q1** | Crystals and sulfur from Mythic and Transcendent; should Unique be re-scaled? | **RESOLVED (USER):** Mythic 8 + 3, Transcendent 10 + 4, Unique stays 10 + 3 (no gems). Original reasoning: **Mythic 8 crystals / 3 sulfur; Transcendent 10 / 4.** This follows the budget curve (U1, R2, E3, Ex4, L6, M8, T10, roughly 1 crystal per 35 BP). **Keep Unique at 10 / 3**: it gives no gems, so the extra crystals make up for it, and its value multiplier (15) sits between Mythic (12) and Transcendent (20). |
| **Q2** | Mythic and Transcendent reroll sets per level | **RESOLVED (USER):** Mythic 2 at L9, 3 at L10. **Transcendent 2 at L10 only.** The proposed 1-set Transcendent reroll at L9 is removed: a single set is only "take it or keep yours". |
| **Q3** | When Exalted can be rerolled | **RESOLVED (USER):** from Runeforge L8, same sets as Legendary (2 / 3 / 4 at L8 / 9 / 10), 1 sulfur. |
| **Q4** | Black Market: 6 free Rare items (code) vs a paid shop (DB) | **STILL OPEN.** The Simulator tests both versions (T7). Designer recommendation unchanged: **make it the paid shop the DB describes**, at about 75% of the Merchant price (Simulator to tune). In v2 the free version gives 12 crystals + about 12 gems + 6 × ceil(L/10) mercury per object, which is about 4-5% of a lifetime's crystals each time. |
| Q5 | Keep the Blacksmith rarity-upgrade unlocks (gf 13)? | **RESOLVED (USER): keep them; material conversion removed.** It only removes "Material Conversion". Note: Transcendent and Unique cannot be levelled today (not in the list or the code); unchanged. |
| Q6 | Fortune lines: gem or not? | **RESOLVED (USER), REVERSED from the recommendation:** Fortune lines DO become gems and CAN appear in rerolls. This reverses this morning's "Fortune out of crafting" rule (materials_system 19 crafting part, old gf 58). Fortune still never changes material / crystal / gem / sulfur drop chances. The team Fortune caps (loot_progression 11 / 17 / 28: ×2.00 loot quality, ×1.50 gold) limit it. Simulator tests T18. |
| Q7 | Downgrades and levelling credit | **RESOLVED (USER), REVERSED from the recommendation:** the item LOSES the stored levelling gold of the dropped levels (exact rule in Section 4.2). Downgrade stays free, no refund, re-upgrading costs full price. The "same total" equalities hold only for items never downgraded; the user accepts that downgrading always has a real cost. Simulator test T3. |
| Q8 | Keep −3% per Runeforge level? | **RESOLVED (USER): keep, on the forge fee only.** |
| Q9 | Threshold passives stack | Movement Range +1, Jump +1, Force +1, Stability +1, Discovery +1 and the range +1 passives are "Additive" and allowed on any equipment. With targeted gems a unit could reach about +6 or +7 Move across its gear. **RESOLVED (USER): NO CAP.** Consequence accepted: gems can reach about +6 / +7 Movement on one unit. The Simulator reports the maximum reachable value per threshold stat, for information only (T17). |
| Q10 | Reroll "keep current" option | **RESOLVED (USER): yes** (sulfur is paid either way). |
| Q11 | A separate "Remove line" action | **RESOLVED (USER): none.** Swaps cover it. |
| Q12 | Daily event reward | **RESOLVED (USER): 5 mercury + 1 sulfur** (still needs the live_service_features 4 rewrite, Section 8 #5). |

---

## 8. Conflicts with locked rules outside the user's list
1. **item_rarity_rules 3** (and gf 56): "The Runeforge never adds Bonus Passives". v2 installs passive gems. Rewrite it: passive gems allowed, the passive slot limit is unchanged (1; 2H 2).
2. **Fortune** (gf 58, old E6, materials_system 19 crafting part): **RESOLVED (USER) Q6** — Fortune becomes gems and can appear in rerolls. Rewrite gf 58 and the crafting part of materials_system 19; the drop-rate part of materials_system 19 stays. loot_progression 11 / 12 / 16 / 17 / 28 (the caps) are unchanged and now also limit crafted Fortune.
3. **BUG-054:** passive-gem installs must reuse the generator's gear-type check (Section 2.2), never the free-text column. Regression check: no off-hand or gloves may accept PAS-016 to 021 or PAS-023 to 025.
4. **economy_framework 36** (Robux cannot buy materials, including Essences): change the list to mercury, crystals, rune gems and sulfur. Note: with shop → dismantle, Gold Boost (+25% gold) now also speeds up material income. That is the same kind of effect already accepted for enchanting; needs a confirm.
5. **live_service_features 4 / unit_progression 84:** daily events give "special resources not obtainable through normal loot". Sulfur and mercury can also come from loot. Rewrite, or give daily events a resource of their own.
6. **guild_facilities 12 / 13:** remove "Material Conversion at L3" (rarity unlocks → Q5).
7. **project_rules 109 / 111 / 112:** wording only (mercury; gem storage is also separate and has no cap). Downgrade still gives "no compensation".
8. **item_generation_steps 7 / 10:** 7: "Add refuses a family" → "a gem of an existing family replaces that line". 10: remove starting level and shop-bought; add levelling credit.
9. **objects_encounters 20** (Treasure Chest "gold, equipment, materials and **runes**"): the word "runes" now clashes with rune gems. Clarify that chests give no gems unless decided otherwise.
10. **objects_encounters 31** (Black Market) vs the code → Q4.
11. **battlefield_events 35** (Crystal Golem "5× material reward") → 5× mercury.
12. **loot_progression 15:** boss Runeforge drops count toward the 3-per-day limit. No conflict, just stated.
13. **Q9 threshold stacking: RESOLVED (USER), no cap.** This matches item_rarity_rules 15 / 20 ("overpowered combinations are acceptable"). No new rule. Recorded consequence: about +6 / +7 Movement on one unit from gems.
14. **gf 15 / economy_framework 14:** the note "Sells as Common (enchanted)" stays. No conflict.
15. **NEW — crystal supply vs "charge every step":** need for a realistic roster rises from about 460 to about 460-685 crystals, against about 276-318 income without shop dismantling. Test T11 says "crystals must not run out before gems"; that is now likely to fail. If it does, the levers are: more elite / boss crystals, the chest crystal lever (Section 3.2), or accepting shop dismantling as the main crystal source. Not changed here; the Simulator decides.
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
| starting_rarity | **KEEP** (sell value; optional Epic step fee). Old items = their current rarity. |
| reroll_count | **KEEP** (fixes the reroll sets). Old items = 0. |
| **levelling_record (new, replaces the single levelling_credit number)** | Free level F + at most 10 (item level, Blacksmith level) pairs (Section 4.1). The credit `C` is calculated from it. Old items: F = current level, no pairs (credit 0). New items: F = the level they arrive at. |

**Per profile (currencies, Key 2):**
- **mercury**, **crystals**, **sulfur**: 3 whole numbers.
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
- open_decisions **23, 123** (+ a new open_decisions row: Q1-Q3 and Q5-Q12 RESOLVED (USER) 2026-11-01, Q4 Black Market still OPEN)
- implementation_plan **53**

**Changed by the user answers of 2026-11-01**
- guild_facilities **47**: delete the reach rule and write the new downgrade rule (item loses the stored levelling gold of the dropped levels; Section 4.2).
- guild_facilities **48** / economy_framework **19**: "same total" wording limited to items never downgraded; remove the "Enchant before upgrading" hint.
- guild_facilities **44 / 58** and materials_system **19 (crafting part only)**: Fortune becomes gems and can appear in rerolls. The drop-rate exclusion in materials_system 19 stays.
- guild_facilities **43 / 55** (forge cost): crystals charged for every rarity step crossed; "charged once per forge" text removed.
- guild_facilities **13**: kept (Q5); only Material Conversion removed from 12 / 13.
- No new row for a threshold-passive cap (Q9: no cap).

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
| T7 | **Black Market — test BOTH versions (Q4 still OPEN)** | (a) **Free version** (today's code: 6 free Rare items per object): per object 12 crystals, about 12 gems, 6 × ceil(L/10) mercury free, or sold: 6 Rare 1H L50 = 738g. Report how often it spawns and its share of lifetime crystals (estimate 4-5% per object) — more important now that crystals are tighter (T11). (b) **Paid shop at about 75% of Merchant price**: every buy → dismantle / sell route loses gold; report crystals per gold vs the Merchant. Report both so the user can decide Q4. |
| T8 | Recruit weapon | L50 Standard hire 950g → 1 Common L50 weapon → 5 mercury (190g each). Must never beat the shop (Common Gloves L50 79g per mercury). |
| T9 | Crafted Epic supply (L50-80) vs natural drops (about 4) and the shop | Measure the free classic, crafter, rusher (Runeforge L7 early) and boosted players. Accepted range on 2026-11-01: rusher ≤ 8, boosted 9-14. If exceeded → turn on the optional Epic step fee and re-run. |
| T10 | Gem-transfer loops (forge → dismantle; swap; reroll → dismantle) | **CHANGED:** crystals per forge-then-dismantle cycle −2 (Common → Uncommon), −4 (Uncommon → Rare), −9 (Rare → Epic), **−18 (Common → Epic)**; gems never increase; sulfur −cost per reroll. |
| T11 | Crystal and gem income vs need, 7 units × 6-7 gear | **CHANGED:** crystals ≈ 276-318 lifetime (no shop dismantling). Need ≈ **460-685** (25 Epics at 12-21 each + 20 swaps at 8); crafting all 45 from Common = 945. Report the number of Epic crafts (target ≥ 20 from income alone, ≥ 30 with moderate shop dismantling) and the share of a target 45-gem build found by L99 (target 40-70%). Target "crystals must not run out before gems" is now **likely to fail**: report by how much and which lever (elite / boss crystals, chest crystals) closes it. |
| T12 | Mercury income vs need and the wall | Income ≈ 1,700-2,300 (drops ≈ 800 + dispatch + dismantling 890-1,190). Wall target 15-20 full L1-99 levellings. The old 10-item scenario ≈ 300-450 mercury. |
| T13 | Sulfur | ≈ 14-15 lifetime + 1 per daily event. Report rerolls per lifetime per rarity, with sets offered: Exalted / Legendary 2 / 3 / 4 at L8 / 9 / 10, Mythic 2 / 3 at L9 / 10, **Transcendent 2 at L10 only** (no L9 reroll). |
| T14 | Facility economy | Free player: 8/10 facilities, ≈ 106% spending pressure (±2 points); boosted ≈ 83-84%. Report the change from the catch-up, forge fees and shop dismantling. |
| T15 | Save size | Gem map ≤ **153** entries, ≤ 3 KB; items about +20 bytes typical, ≤ about +70 bytes worst (levelling record ≤ 10 pairs); total well under 4 MB. |
| T16 | Compatibility (BUG-054) | No off-hand or gloves accepts PAS-016 to 021 or PAS-023 to 025; no already-elemental weapon accepts a transformation; passive slot limit holds; one line per family. |
| T17 | Threshold stacking (Q9: **NO CAP, user decision** — information only, not pass/fail) | Report the maximum reachable value on one unit from gems + gear for each threshold stat: Movement, Jump, Force, Stability, Discovery and each range +1 passive. Expected about +6 / +7 Movement. |
| T18 | **NEW — Fortune gems (Q6)** | Compare a team AT the Fortune cap (normalized 1.75 → ×2.00 loot quality, ×1.50 gold) with a normal team: loot quality, gold income, crystal / gem / sulfur income (from dismantling only; drop chances must be identical). Check whether Fortune gems create a loot → dismantle → more Fortune gems feedback loop that goes beyond the cap (expected: no — the cap holds, and Fortune gems only make it faster to reach). Report how early in the game a team can reach the cap with gems. |
| T19 | **NEW — crystal steps** | Common → Epic = 21 crystals whether in one forge or in steps (3 / 9 / 21 / 18 / 12 for the routes in Section 2.3). A forge that swaps and raises rarity pays only the steps crossed (e.g. Rare swap + T4 → Epic = 12). A forge that keeps rarity = 2 / 4 / 8. |
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
- **Removed everywhere:** the old hint "Enchant before upgrading to pay less." It is no longer true (RESOLVED (USER) 2026-11-01). No screen, tooltip or prompt may show it.
