# Formula / rule registry — Crucible check 2026-11-02
All DB rows below were asserted by text match at run time (prov() in v2_core.py / crucible_sim.py). DB opened read-only, md5 ea957228… at start and end.
Base registry for the economy model: sim\runeforge_v2_2026-11-01\FORMULAS_v2.md (35 rules) + sim\daily_systems_2026-11-01 (19 rows).

## New DB rows used today
| Rule | Table / row | Asserted text | Python | Match |
|---|---|---|---|---|
| Shelf slots + rarity odds | economy_framework 48 | "5, 5, 6, 7, 7, 8, 9, 10, 10, 10", "L10 C10 U30 R40 E15 Exalted 5", "Item level rolls at the current Map Level ceiling", "Deterministic from seed + battles-completed" | `SHELF`, `ODDS` | ✅ |
| Restock every 5 battles, nothing above Exalted in shops | economy_framework 18 | "reroll every 5 completed battles", "Nothing above Exalted is ever sold" | `b % 5 == 4` | ✅ |
| Inventory threshold / maintenance / expansion | economy_framework 24 / 25 / 33 | "50 items", "min(Excess Items × 5, 200) gold per base visit", "+25 item threshold per purchase" | `maint` | ✅ |
| Dismantle output | guild_facilities 51 | "Mercury = ceil(item level / 10)", "Exalted 4 / 1 per line / 1", "Legendary 6 / 1 per line / 2" | `dis_merc`, `DIS_CRY`, `DIS_SUL` | ✅ |
| Boss reward cap / Rare+ item | loot_progression 15 / 25 | "first 3 rewarded boss wins per day", "One guaranteed Rare-or-better equipment reward" | `BOSS_P`, `TAB_B` | ✅ |
| Elite reward 75% | loot_progression 26 | "Base Elite Reward Chance = 75%" | `P_ELITE` | ✅ |
| Boss card weight 3, QB L8 | guild_facilities 17 | "card weight 3", "L8: Boss quests" | B8 = 81 | ✅ |
| Black Market shop | objects_encounters rowid 31 | "six items at 75% of the Merchant price", "Rare 75% / Epic 25%", "never Exalted", "random slot" | BM offers | ✅ |
| Exalted loot weight | loot_progression 84 / 85 | 0.025 normal / 0.025 elite; sensitivity 0.85 | `LW_N['Exalted']` | ✅ |
| Tavern curve (= Crucible curve) | guild_facilities 9 | "Base = 200, Scale = 18. Total cost: 6,277g" | `FAC['Crucible']` (sum asserted 6,277) | ✅ |

## Crucible rules — NOT in the DB yet (source: design_snapshot_workshop_design_options_20261101.md, user-approved 2026-11-02)
| Rule | Snapshot section | Python |
|---|---|---|
| Same base item + same rarity → next rarity | user brief (overrides doc A1(b)) | group key = (slot, archetype, rarity) |
| Inputs 5 / 4 / 3 at Crucible L1-3 / 4-7 / 8-10 | E | `c_need` |
| Level = floor(avg of inputs) + boost, cap min(map level, 99); boost 0,0,1,1,2,2,3,3,4,5 | A4(c), E | `raw`, `rl = min(raw, L, 99)` |
| Highest rarity out U/R/E/Ex/L at L1/4/7/9/10 | A5, E | `c_maxout` |
| Crystals 2/3/6, Exalted 8 + 1 sulfur, Legendary 12 + 2 sulfur | D2, D3 | `C_CRY`, `C_SUL` |
| Gold = floor(0.5 × slot × rarity mult(result) × level mult(result) × (1 − 0.03 × (CL − 1))) | D1 | `c_fee` (1H L50 Epic 396g CL1 / 289g CL10 — matches the doc) |
| Unlock Guild Hall L5, 6,277g (Base 200, Scale 18) | E, user brief | `UNLOCK_GH['Crucible'] = 5` |
| Any source; equipped excluded; result = new item | C1, C3, B4, B5 | inputs from loot / shop / BM |

## Content counts (not formulas)
- DB catalog: 38 weapons (weapons_equipment 25-45, 114-134), 17 off-hands (47-48, 138-152), 101 armour (nonweapon_equipment HD 20 / BD 20 / GL 21 / FT 20 / AC 20) = **156**.
- Code pools (WeaponData.lua + ArmorData.lua, counted read-only, no formula read): 38 weapons, **7 off-hands**, 101 armour = **146**. Off-hands in the DB but not in the code: Lantern, Totem, Banner, Talisman, Prism, Kite, Skull, Net, Sheath, Wind Vane.

## Not in the DB — working assumptions (do not block)
1. How the base item is picked (item_generation_steps 1 says only "Select base item"). Used: slot first (8 groups, equal), then archetype equal — the same 1/8 slot model as the earlier sims. Sensitivity (no gold limit): equal over all 146 → about 10% fewer Rare→Epic merges; DB pool 156 → about 16% fewer, and Legendary merges 0.23 → 0.07.
2. Boss item rarity table: elite table limited to Rare+ (Rare 61%, Epic 23%, Exalted 8.4%, Legendary 6.8%).
3. Whether one restock window can show more than one shelf (per map level). DB row 48 implies one. Tested 1 / 3 / 10.
4. Spare inventory 30 (50-item threshold minus ~20 for kept gear) and 55 (one +25 expansion).
