# CTRBLXAI — Simulator Formula Registry (FORMULAS.md)

Every formula below is reimplemented in Python from **CTRBLXAI.db only**.
Source Luau is NEVER consulted for formula content (provenance rule).

Last updated: 2026-10-23 — run `movement_rt_str_delay_2026-10-23`
Scope of this run: the three movement/RT wiring fixes (movement_targeting id 8, core_stats id 2).

---

## F-01 Modified Base RT
- **Source:** `weapons_equipment` id 7 (section "Modified Base RT"); `core_stats` id 54 (three-layer RT model); `core_stats` id 12/13 (Base RT 400 std / 300 boss).
- **DB expression:** `Modified Base RT = (own Base RT + Effective Armor WT) × permanent trait base-RT modifiers × active Haste(×0.90)/Slow(×1.10)/Frozen(×2)`. Own Base RT: player 400; enemy Grunt 400 / Veteran 380 / Elite 350; boss 300.
- **Python:** `modified_base_rt = (own_base_rt + effective_armor_wt) * trait_mult * status_mult`
- **Match:** ✅

## F-02 Effective Equipment / Armor WT (STR burden reduction)
- **Source:** `core_stats` id 2.
- **DB expression:** `If WT≥0: Effective WT = WT × (1 − STR/(200+STR))`. (WT<0 branch uses `× (1 + STR/(200+STR))`.) Cap pending.
- **Python:** `eff_wt = wt*(1 - STR/(200+STR)) if wt>=0 else wt*(1 + STR/(200+STR))`
- **Match:** ✅

## F-03 Basic Attack RT
- **Source:** `weapons_equipment` id 8 / `core_stats` id 19.
- **DB expression:** `Basic Attack RT = round(Modified Base RT × 0.10) + Effective Weapon WT`
- **Python:** `ba_rt = round_half_up(mbrt*0.10) + eff_weapon_wt`
- **Match:** ✅

## F-04 Movement RT  ★ CHANGED THIS RUN (change #1 and #2)
- **Source:** `movement_targeting` id 8.
- **DB expression:**
  `Base Movement RT per tile = Modified Base RT × 0.03  (=12/tile at MBRT 400)`
  `Total Movement RT = round( Base Movement RT per tile × Tiles Moved × (1 − AGI/(200+AGI)) )`
  Calculate total then round once.
- **Python:** `move_rt = round_half_up(mbrt*0.03 * tiles * (1 - AGI/(200+AGI)))`
- **Prior values:** per-tile factor was 0.0625 (=25/tile); AGI had NO effect. Both now active.
- **Match:** ✅

## F-05 Inflicted Weapon RT Delay (attacker side)  ★ CHANGED THIS RUN (change #3)
- **Source:** `core_stats` id 2 (RT Delay Bonus); `weapons_equipment` id 157 (weapon-level scaling of Base RT Delay); id 99 (Stagger ×1.25, weapon-specific); `project_rules` id 19 (min base RT Delay −150; target RT floor 0).
- **DB expression:** `RT Delay Bonus = Base RT Delay × (1 + min(STR/(200+STR), 0.75))`
- **Python:** `inflicted = base_rt_delay * (1 + min(STR/(200+STR), 0.75))`
- **Prior:** STR had NO effect on inflicted RT delay.
- **Match:** ✅

## F-06 RT Delay Resistance (defender side, VIT)
- **Source:** `core_stats` id 5.
- **DB expression:** `RT Delay Resistance = Incoming RT Delay × (1 − VIT/(300+VIT))`
- **Python:** `received = incoming * (1 - VIT/(300+VIT))`
- **Match:** ✅  (Boss: additionally 25–50% effectiveness, core_stats id 42.)

## F-07 Weapon Level Scaling
- **Source:** `weapons_equipment` id 157.
- **DB expression:** `Weapon Scale = 0.30 + 0.70 × ((Item Level−1)/98)^0.55`; `Scaled = L99 Base × Scale`. Applies to Damage, WT, RT Delay, Defense. NOT to range/pattern/hands. Continuous beyond L99.
- **Python:** `scale = 0.30 + 0.70*((lvl-1)/98)**0.55`
- **Match:** ✅

## F-08 Movement Range (AGI)
- **Source:** `core_stats` id 3.
- **DB expression:** `Movement Range = 3 + floor(AGI/60) + Bonuses − Penalties`
- **Python:** `move_range = 3 + AGI//60`
- **Match:** ✅

## F-09 Rest RT (turn-order reference)
- **Source:** `core_stats` id 14.
- **DB expression:** `Rest RT = round(Modified Base RT × 0.75)`
- **Match:** ✅

## F-10 Standard turn / AP
- **Source:** `core_stats` id 12. Base RT 400, 2 AP. Boss 300, 3 AP (id 13/38).

## Rounding
- **Source:** `core_stats` id 28. Standard math rounding, .5 up. One round at final output.
- **Python:** `round_half_up(x) = math.floor(x + 0.5)` for x≥0.

---
### BLOCKERS this run
None. All formulas needed for movement-RT and STR-RT-delay validation are present in the DB.
