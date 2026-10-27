# Hand-back: Support Consumable Buff/Debuff Statuses (2026-10-26)

Design + database task. 15 new statuses authored in CTRBLXAI.db (elements_statuses,
ids 107-121) and appended to CTRBLXAI_Game_Rules.xlsx sheet "04 Elements Statuses".
No source/ Luau files were touched. The Dev wires these in.

## What the Dev must add

For EACH status below, add an entry to GameConstants.STATUSES keyed by the Status Name,
and add the stat/effect modifier to the StatusService GetStatusStatModifiers mapping
(same mechanism Weakened / Banner Blessing / Guard already use). All percentage
modifiers are applied to the named stat the same way Weakened (-10% all stats) and
Banner Blessing (+15% all stats) already apply.

Durations are in CT (same convention as War Cry, Rune Ward, etc.). "Does not stack with
itself" = reapply refreshes duration only.

### Single-stat % BUFFS (model exactly like Banner Blessing's per-stat modifier)
| Status Name | Modifier | Duration | From item |
|---|---|---|---|
| Empowered | STR x1.15 | 1500 CT | SUP-001 |
| Focused   | INT x1.15 | 1500 CT | SUP-002 |
| Stoneskin | VIT x1.15 (SUP-008 applies same status at x1.12) | 1500 CT | SUP-003 / SUP-008 |
| Fleetfoot | AGI x1.15 AND Movement RT x0.95 | 1200 CT | SUP-004 |
| Precise   | DEX x1.15 | 1500 CT | SUP-005 |
| Fortunate | LUK x1.20 | 1500 CT | SUP-006 |

### Defense / damage BUFFS
| Status Name | Modifier | Duration | From item |
|---|---|---|---|
| Armored     | Equipment Defense x1.20 (before VIT Defense Power scaling) | 1500 CT | SUP-007 |
| Battle Fury | Direct final damage dealt x1.12 (separate from War Cry, stacks multiplicatively with it) | 1000 CT | SUP-010 |
| Rally Array | STR x1.10 + INT x1.10 + VIT x1.10 (ONE status, three mods) | 1000 CT | SUP-020 |

### Single-stat % / flat DEBUFFS (model like Weakened)
| Status Name | Modifier | Duration | From item |
|---|---|---|---|
| Enfeebled   | STR x0.80 | 1200 CT | SUP-012 |
| Addled      | INT x0.80 | 1200 CT | SUP-013 |
| Armor Break | Equipment Defense x0.80 (before VIT Defense Power scaling) | 1500 CT | SUP-014 |
| Unsteady    | Stability -2 (FLAT, floor at 0) | 1000 CT | SUP-015 |

### Special
| Status Name | Modifier | Duration | From item | Note |
|---|---|---|---|---|
| Elemental Ward | Incoming direct damage of a CHOSEN element tag x0.75 | 1500 CT | SUP-016 | Store chosen element per-instance; reapply replaces the element + refreshes. Applies in the element-modifier damage stage. |
| Warding        | Debuff Resistance Multiplier x0.80 | 1500 CT | SUP-019 | Lower multiplier = more resistant (core_stats scale). |

## Item wiring (which status each Support item applies)
SUP-001->Empowered, SUP-002->Focused, SUP-003->Stoneskin(+15%),
SUP-004->Fleetfoot, SUP-005->Precise, SUP-006->Fortunate, SUP-007->Armored,
SUP-008->Stoneskin(+12%, AOE), SUP-010->Battle Fury, SUP-012->Enfeebled,
SUP-013->Addled, SUP-014->Armor Break, SUP-015->Unsteady, SUP-016->Elemental Ward,
SUP-019->Warding, SUP-020->Rally Array.

## OPEN DESIGN QUESTIONS (need human ruling — do not guess in code)
1. Buff vs its debuff counterpart (Empowered vs Enfeebled, Armored vs Armor Break):
   do they CANCEL on application, or coexist and both multiply? (Recommend: coexist,
   both apply — simplest and matches how the game has no generic cancel rule.)
2. Same-stat % buff + Weakened/Enlightened/Banner Blessing/Giant Transformation all
   touch the same stat. Confirm they COMPOSE MULTIPLICATIVELY (x1.15 * x0.90 ...),
   not additively. (Recommend: multiplicative, consistent with existing % statuses.)
3. Warding (x0.80 Debuff Res Mult) composition with Debuff Res Up/Down is BLOCKED on
   the existing open_decisions item "Debuff Res Up/Down application (2026-10-08)":
   additive vs multiplicative on the Debuff Resistance Multiplier scale. Resolve that
   first; Warding follows the same rule.
4. Rally Array (+10% STR/INT/VIT) vs a single-stat Infuser on the same stat: coexist
   and multiply (both are separate statuses, so yes by default). Confirm acceptable.

## Items NOT in this task's scope (already covered or different effect type)
SUP-009 Shield, SUP-011 Guardian Standard (Guard+Stability aura), SUP-017 Command Relay,
SUP-018 Blessing Projector — these use shield/aura/duration-extension mechanics, not a
new stat-modifier status. Flagged for a separate pass if still blocked.


## Item devices data (2026-10-26, Designer)
- New consumable_items columns: Device_Hp_Formula, Device_Lifespan_Ct, Device_Aura_Radius, Device_Aura_Stability, Device_Aura_Teleport_Lock, Pulse_Amount_Formula, Pulse_Target_Mode, Pulse_Requires_LoS, Pulse_Anchor, Pulse_Recipients (NULL except 5 rows).
- Filled: DEP-001 Sentry Turret, DEP-019 Mender Drone, DEP-008 Decoy Totem, DEP-020 Gravity Pylon, DAM-019 Tesla Pylon. Deploy_Kind/Deploy_Ref unchanged; Effect_Formula unchanged.
- ConsumableData.lua regenerated with camelCase keys device*/pulse*; header documents them.
- project_rules: "Item devices" rule added. Open: Mender Drone 'mobile' not modelled.
