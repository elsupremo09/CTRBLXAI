# Rebuild report  -  2026-11-10 17:27

Output (review only): `D:\AI\Projects\CTRBLXAI\docs\CTRBLXAI_Game_Rules.rebuilt.xlsx`

## Integrity checks
- Live xlsx SHA-256 before: `7cbf5921edc694ec6557a664ac10027b5045ecad1453a51258787c2c6a9b1521`
- Live xlsx SHA-256 after : `7cbf5921edc694ec6557a664ac10027b5045ecad1453a51258787c2c6a9b1521`  ->  **IDENTICAL**
- DB SHA-256 before: `cdfb1d65068e66cf1e716132102c134033d1d8d33fbbff945918acdc1cdac585`
- DB SHA-256 after : `cdfb1d65068e66cf1e716132102c134033d1d8d33fbbff945918acdc1cdac585`  ->  **IDENTICAL**

## Per-sheet summary

| Sheet | DB table | DB rows | xlsx rows | Cell diffs | Condensed-in-xlsx | Status |
|---|---|---:|---:|---:|---:|---|
| 01 Project Identity | project_rules | 255 | 256 | 0 | 0 | FULLY REGENERATED from project_rules (id order) |
| 02 Core Stats Formulas | core_stats | 53 | 54 | 0 | 0 | REBUILT from core_stats (matched 53/53 DB rows) |
| 03 Movement Targeting | movement_targeting | 81 | 82 | 0 | 0 | REBUILT from movement_targeting (matched 81/81 DB rows) |
| 04 Elements Statuses | elements_statuses | 89 | 90 | 0 | 0 | REBUILT from elements_statuses (matched 89/89 DB rows) |
| 05 Skills Framework | frameworks [system='Skills'] | 65 | 68 | 0 | 0 | REBUILT from frameworks (matched 65/65 DB rows) |
| 05b Skill Catalog | skills | 117 | 118 | 0 | 0 | REBUILT from skills (matched 117/117 DB rows) |
| 06 Augments Framework | frameworks [system='Augments'] | 14 | 15 | 0 | 0 | REBUILT from frameworks (matched 14/14 DB rows) |
| 06b Augment Catalog | augments | 111 | 112 | 0 | 0 | REBUILT from augments (matched 111/111 DB rows) |
| 07 Doctrines | doctrines | 34 | 35 | 0 | 0 | REBUILT from doctrines (matched 34/34 DB rows) |
| 08 Races | races | 25 | 40 | 0 | 0 | REBUILT from races (matched 25/25 DB rows); 13 cell(s) xlsx-text-where-DB-empty kept |
| 09 Weapons Equipment | weapons_equipment | - | 104 | 0 | 0 | NOT REBUILT: Composite sheet (rules block + 15-weapon archetype table + extra blocks); DB table has 158 free-form rows incl. section markers that are not laid out like the sheet. |
| 10 Loot Progression | loot_progression | 84 | 85 | 0 | 0 | REBUILT from loot_progression (matched 84/84 DB rows) |
| 11 Trigger Safety | trigger_safety | 21 | 22 | 0 | 0 | REBUILT from trigger_safety (matched 21/21 DB rows) |
| 12 Map Gen Rules | map_gen_rules | 96 | 97 | 0 | 0 | REBUILT from map_gen_rules (matched 96/96 DB rows) |
| 13 Map Templates | map_templates | 34 | 36 | 0 | 0 | REBUILT from map_templates (matched 34/34 DB rows) |
| 14 Biomes | biomes | 28 | 28 | 0 | 0 | REBUILT from biomes (matched 28/28 DB rows) |
| 15 Regions | regions | 23 | 25 | 0 | 0 | REBUILT from regions (matched 23/23 DB rows) |
| 16 Terrain Effects | terrain_effects | 78 | 78 | 0 | 0 | REBUILT from terrain_effects (matched 78/78 DB rows) |
| 17 Objects Encounters | objects_encounters | 130 | 130 | 0 | 0 | REBUILT from objects_encounters (matched 130/130 DB rows) |
| 18 Open Decisions | open_decisions | 152 | 152 | 0 | 0 | REBUILT from open_decisions (matched 152/152 DB rows); 1 cell(s) xlsx-text-where-DB-empty kept |
| 19 Persistent HP MP | persistent_hp_mp_rules | 25 | 30 | 0 | 0 | REBUILT from persistent_hp_mp_rules (matched 25/25 DB rows) |
| 20 Item Affix Names | item_affix_names | 153 | 165 | 0 | 0 | REBUILT from item_affix_names (matched 153/153 DB rows) |
| 21 Unit Progression | unit_progression | 74 | 75 | 0 | 0 | REBUILT from unit_progression (matched 74/74 DB rows) |
| 22 Economy Framework | economy_framework | 49 | 50 | 0 | 0 | REBUILT from economy_framework (matched 49/49 DB rows) |
| 23 Materials System | materials_system | 42 | 43 | 0 | 0 | REBUILT from materials_system (matched 42/42 DB rows) |
| 24 Consumable Prices | consumable_items | - | 138 | 0 | 0 | NOT REBUILT: Computed price view (Shop Price / Cost-Use are derived, not DB columns); cannot be rebuilt from raw table without the pricing formula. |
| 25 Guild Facilities | guild_facilities | 84 | 85 | 0 | 0 | REBUILT from guild_facilities (matched 84/84 DB rows) |
| 26 Enemy AI Personalities | enemy_ai_personalities | 31 | 32 | 0 | 0 | REBUILT from enemy_ai_personalities (matched 31/31 DB rows) |
| 27 Non-Weapon Equipment | nonweapon_equipment | 140 | 141 | 0 | 0 | REBUILT from nonweapon_equipment (matched 140/140 DB rows); 2 cell(s) xlsx-text-where-DB-empty kept |
| 29 UGC Rental Ownership | ugc_rules | 58 | 59 | 0 | 0 | REBUILT from ugc_rules (matched 58/58 DB rows) |
| 30 Loadout UI Spec | loadout_ui_spec | 120 | 121 | 0 | 0 | REBUILT from loadout_ui_spec (matched 120/120 DB rows) |
| 31 UGC Catalog | ugc_catalog | 83 | 84 | 0 | 0 | REBUILT from ugc_catalog (matched 83/83 DB rows) |
| T01 Frontline | template_grids[T01] 30x20 | 20 | 20 | 0 | 0 | COPIED UNCHANGED (grid diagram; 0 cell(s) differ from DB grid) |
| T02 Split | template_grids[T02] 30x19 | 19 | 19 | 0 | 0 | COPIED UNCHANGED (grid diagram; 0 cell(s) differ from DB grid) |
| T03 Crossing | template_grids[T03] 30x20 | 20 | 20 | 0 | 0 | COPIED UNCHANGED (grid diagram; 0 cell(s) differ from DB grid) |
| T04 Boss Ring | template_grids[T04] 20x20 | 20 | 20 | 0 | 0 | COPIED UNCHANGED (grid diagram; 0 cell(s) differ from DB grid) |
| T05 Defense | template_grids[T05] 30x20 | 20 | 20 | 0 | 0 | COPIED UNCHANGED (grid diagram; 0 cell(s) differ from DB grid) |
| T06 Advantage | template_grids[T06] 30x20 | 20 | 20 | 0 | 0 | COPIED UNCHANGED (grid diagram; 0 cell(s) differ from DB grid) |
| T07 Wave | template_grids[T07] 30x30 | 30 | 30 | 0 | 0 | COPIED UNCHANGED (grid diagram; 0 cell(s) differ from DB grid) |
| T08 Ambush | template_grids[T08] 29x18 | 18 | 18 | 0 | 0 | COPIED UNCHANGED (grid diagram; 0 cell(s) differ from DB grid) |
| T09 Hazard | template_grids[T09] 31x18 | 18 | 18 | 0 | 0 | COPIED UNCHANGED (grid diagram; 0 cell(s) differ from DB grid) |
| T10 Obstacle | template_grids[T10] 25x20 | 20 | 20 | 0 | 0 | COPIED UNCHANGED (grid diagram; 0 cell(s) differ from DB grid) |
| T11 Objective | template_grids[T11] 20x20 | 20 | 20 | 0 | 0 | COPIED UNCHANGED (grid diagram; 0 cell(s) differ from DB grid) |
| T12 Elevated | template_grids[T12] 20x20 | 20 | 20 | 0 | 0 | COPIED UNCHANGED (grid diagram; 0 cell(s) differ from DB grid) |
| T13 Highland | template_grids[T13] 20x20 | 20 | 20 | 0 | 0 | COPIED UNCHANGED (grid diagram; 0 cell(s) differ from DB grid) |
| T14 Broken Hi | template_grids[T14] 20x20 | 20 | 20 | 0 | 0 | COPIED UNCHANGED (grid diagram; 0 cell(s) differ from DB grid) |
| T15 Siege | template_grids[T15] 20x20 | 20 | 20 | 0 | 0 | COPIED UNCHANGED (grid diagram; 0 cell(s) differ from DB grid) |
| T16 Treasure | template_grids[T16] 20x20 | 20 | 20 | 0 | 0 | COPIED UNCHANGED (grid diagram; 0 cell(s) differ from DB grid) |
| T17 Wide Hzd | template_grids[T17] 30x20 | 20 | 20 | 0 | 0 | COPIED UNCHANGED (grid diagram; 0 cell(s) differ from DB grid) |
| T18 Wetland | template_grids[T18] 27x24 | 24 | 24 | 0 | 0 | COPIED UNCHANGED (grid diagram; 0 cell(s) differ from DB grid) |
| T19 Divide | template_grids[T19] 27x32 | 32 | 32 | 0 | 0 | COPIED UNCHANGED (grid diagram; 0 cell(s) differ from DB grid) |
| T20 River | template_grids[T20] 21x28 | 28 | 28 | 0 | 0 | COPIED UNCHANGED (grid diagram; 0 cell(s) differ from DB grid) |

"Condensed in xlsx" = xlsx text is shorter than and different from the DB text; a rebuild REPLACES it with the full DB text.

## Details

### 02 Core Stats Formulas
- cell diffs: 0   |   condensed-in-xlsx: 0   |   DB rows not found in xlsx: 0   |   xlsx-only non-empty rows: 1

### 03 Movement Targeting
- cell diffs: 0   |   condensed-in-xlsx: 0   |   DB rows not found in xlsx: 0   |   xlsx-only non-empty rows: 1

### 04 Elements Statuses
- cell diffs: 0   |   condensed-in-xlsx: 0   |   DB rows not found in xlsx: 0   |   xlsx-only non-empty rows: 1

### 05 Skills Framework
- cell diffs: 0   |   condensed-in-xlsx: 0   |   DB rows not found in xlsx: 0   |   xlsx-only non-empty rows: 1

### 05b Skill Catalog
- cell diffs: 0   |   condensed-in-xlsx: 0   |   DB rows not found in xlsx: 0   |   xlsx-only non-empty rows: 1

### 06 Augments Framework
- cell diffs: 0   |   condensed-in-xlsx: 0   |   DB rows not found in xlsx: 0   |   xlsx-only non-empty rows: 1

### 06b Augment Catalog
- cell diffs: 0   |   condensed-in-xlsx: 0   |   DB rows not found in xlsx: 0   |   xlsx-only non-empty rows: 1

### 07 Doctrines
- cell diffs: 0   |   condensed-in-xlsx: 0   |   DB rows not found in xlsx: 0   |   xlsx-only non-empty rows: 1

### 08 Races
- cell diffs: 0   |   condensed-in-xlsx: 0   |   DB rows not found in xlsx: 0   |   xlsx-only non-empty rows: 14

**xlsx has text where DB is empty (KEPT as-is in rebuild, not blanked):**

| Cell | xlsx (first 120) | DB |
|---|---|---|
| B26 | None | (empty) |
| B27 | None | (empty) |
| B29 | None | (empty) |
| B31 | None | (empty) |
| B32 | None | (empty) |
| B33 | None | (empty) |
| B34 | None | (empty) |
| B35 | None | (empty) |
| B36 | None | (empty) |
| B37 | None | (empty) |
| B38 | None | (empty) |
| B39 | None | (empty) |
| B40 | None | (empty) |

### 10 Loot Progression
- cell diffs: 0   |   condensed-in-xlsx: 0   |   DB rows not found in xlsx: 0   |   xlsx-only non-empty rows: 1

### 11 Trigger Safety
- cell diffs: 0   |   condensed-in-xlsx: 0   |   DB rows not found in xlsx: 0   |   xlsx-only non-empty rows: 1

### 12 Map Gen Rules
- cell diffs: 0   |   condensed-in-xlsx: 0   |   DB rows not found in xlsx: 0   |   xlsx-only non-empty rows: 1

### 13 Map Templates
- cell diffs: 0   |   condensed-in-xlsx: 0   |   DB rows not found in xlsx: 0   |   xlsx-only non-empty rows: 1

### 14 Biomes
- cell diffs: 0   |   condensed-in-xlsx: 0   |   DB rows not found in xlsx: 0   |   xlsx-only non-empty rows: 0

### 15 Regions
- cell diffs: 0   |   condensed-in-xlsx: 0   |   DB rows not found in xlsx: 0   |   xlsx-only non-empty rows: 1

### 16 Terrain Effects
- cell diffs: 0   |   condensed-in-xlsx: 0   |   DB rows not found in xlsx: 0   |   xlsx-only non-empty rows: 0

### 17 Objects Encounters
- cell diffs: 0   |   condensed-in-xlsx: 0   |   DB rows not found in xlsx: 0   |   xlsx-only non-empty rows: 0

### 18 Open Decisions
- cell diffs: 0   |   condensed-in-xlsx: 0   |   DB rows not found in xlsx: 0   |   xlsx-only non-empty rows: 0

**xlsx has text where DB is empty (KEPT as-is in rebuild, not blanked):**

| Cell | xlsx (first 120) | DB |
|---|---|---|
| D110 | CONFIRMED no change: Thunderclap, Static Field, Venom Burst, Siphon Pulse stay 'Caster Area' (caster-centered, not aimab | (empty) |

### 19 Persistent HP MP
- cell diffs: 0   |   condensed-in-xlsx: 0   |   DB rows not found in xlsx: 0   |   xlsx-only non-empty rows: 4

### 20 Item Affix Names
_Note: xlsx has no id column; trailing composition-rules block is xlsx-only_
- cell diffs: 0   |   condensed-in-xlsx: 0   |   DB rows not found in xlsx: 0   |   xlsx-only non-empty rows: 9

### 21 Unit Progression
- cell diffs: 0   |   condensed-in-xlsx: 0   |   DB rows not found in xlsx: 0   |   xlsx-only non-empty rows: 1

### 22 Economy Framework
- cell diffs: 0   |   condensed-in-xlsx: 0   |   DB rows not found in xlsx: 0   |   xlsx-only non-empty rows: 1

### 23 Materials System
- cell diffs: 0   |   condensed-in-xlsx: 0   |   DB rows not found in xlsx: 0   |   xlsx-only non-empty rows: 1

### 25 Guild Facilities
- cell diffs: 0   |   condensed-in-xlsx: 0   |   DB rows not found in xlsx: 0   |   xlsx-only non-empty rows: 1

### 26 Enemy AI Personalities
- cell diffs: 0   |   condensed-in-xlsx: 0   |   DB rows not found in xlsx: 0   |   xlsx-only non-empty rows: 1

### 27 Non-Weapon Equipment
- cell diffs: 0   |   condensed-in-xlsx: 0   |   DB rows not found in xlsx: 0   |   xlsx-only non-empty rows: 1

**xlsx has text where DB is empty (KEPT as-is in rebuild, not blanked):**

| Cell | xlsx (first 120) | DB |
|---|---|---|
| F23 | Trigger | (empty) |
| G23 | Restriction | (empty) |

### 29 UGC Rental Ownership
- cell diffs: 0   |   condensed-in-xlsx: 0   |   DB rows not found in xlsx: 0   |   xlsx-only non-empty rows: 1

### 30 Loadout UI Spec
- cell diffs: 0   |   condensed-in-xlsx: 0   |   DB rows not found in xlsx: 0   |   xlsx-only non-empty rows: 1

### 31 UGC Catalog
- cell diffs: 0   |   condensed-in-xlsx: 0   |   DB rows not found in xlsx: 0   |   xlsx-only non-empty rows: 1