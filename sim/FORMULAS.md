# CTRBLXAI Formula Registry — Simulator Provenance

Generated: 2026-08-27
Source: D:\AI\Projects\CTRBLXAI\docs\CTRBLXAI.db

Every formula implemented in the simulator is listed here with its database provenance.
If a formula is not documented in the database, the simulator CANNOT use it.

---

## 1. STAT CALCULATION

| Formula | DB Table | DB Row/Section | Expression (DB) | Python Implementation |
|---------|----------|----------------|-----------------|----------------------|
| Stat at Level | races + race_framework | growth_rates rule | start_stat + growth × (Level - 1) | `floor(start + growth * (level - 1))` |

**Provenance:** race_framework.rule = "Total growth equals exactly 2.00 per level. Growth rates may use decimals."
races table provides start_X and growth_X per race. Rounding: global rule says "do not round intermediate values" but stats are integer in-game. Using floor() for stat accumulation.

---

## 2. CORE STAT FORMULAS

| Formula | DB Table | DB Row ID | Expression (DB) | Python |
|---------|----------|-----------|-----------------|--------|
| Attack Power | core_stats | id=2 (STR) | Weapon Damage × (1 + STR / 200) | `wpn_dmg * (1 + STR / 200)` |
| Effective Equip WT (positive) | core_stats | id=2 | Equipment WT × (1 - STR / (200 + STR)) | `equip_wt * (1 - STR / (200 + STR))` |
| Effective Equip WT (negative) | core_stats | id=2 | Equipment WT × (1 + STR / (200 + STR)) | `equip_wt * (1 + STR / (200 + STR))` |
| RT Delay Bonus | core_stats | id=2 | Base RT Delay × (1 + min(STR / (200 + STR), 0.75)) | `base_rt_delay * (1 + min(STR / (200 + STR), 0.75))` |
| Force | core_stats | id=2 | 1 + floor(STR / 60) | `1 + STR // 60` |
| Movement Range | core_stats | id=3 (AGI) | 3 + floor(AGI / 60) + Bonuses - Penalties | `3 + AGI // 60` |
| Evasiveness | core_stats | id=3 | AGI / (AGI + 200) | `AGI / (AGI + 200)` |
| Skill Potency Multiplier | core_stats | id=4 (INT) | 1 + INT / (200 + INT) | `1 + INT / (200 + INT)` |
| Max MP | core_stats | id=4 | 20 + INT × 2 | `20 + INT * 2` |
| Bonus Skill Range | core_stats | id=4 | floor(INT / 75) | `INT // 75` |
| MP Regen | core_stats | id=49 | 2 + floor(INT / 40) MP per 1000 CT | `2 + INT // 40` |
| HP | core_stats | id=5 (VIT) | 50 + VIT × 4 | `50 + VIT * 4` |
| Healing Efficiency | core_stats | id=5 | Healing × (1 + VIT / 300) | `healing * (1 + VIT / 300)` |
| Defense Power | core_stats | id=5 | Defense × (1 + VIT / 300) | `defense * (1 + VIT / 300)` |
| Debuff Resistance Mult | core_stats | id=5 | 1 - VIT / (300 + VIT) | `1 - VIT / (300 + VIT)` |
| RT Delay Resistance | core_stats | id=5 | Incoming RT Delay × (1 - VIT / (300 + VIT)) | `rt_delay * (1 - VIT / (300 + VIT))` |
| Stability | core_stats | id=5 | 1 + floor(VIT / 60) | `1 + VIT // 60` |
| Precision | core_stats | id=6 (DEX) | DEX / (DEX + 200) | `DEX / (DEX + 200)` |
| Jump | core_stats | id=6 | 1 + floor(DEX / 60) | `1 + DEX // 60` |
| Channel Time | core_stats | id=6 | Base Channel × (1 - DEX / (300 + DEX)) | `base_channel * (1 - DEX / (300 + DEX))` |
| Combat Fortune Mod | core_stats | id=7 (LUK) | 0.40 × Delta LUK / (abs(Delta LUK) + 150) | `0.40 * delta_luk / (abs(delta_luk) + 150)` |
| Starting RT | core_stats | id=7 | round(Base RT × (1 - 0.30 × LUK / (100 + LUK))) | `round(base_rt * (1 - 0.30 * LUK / (100 + LUK)))` |
| Unit Fortune | core_stats | id=7 | LUK / (LUK + 200) | `LUK / (LUK + 200)` |

---

## 3. TIMELINE / RT FORMULAS

| Formula | DB Table | Row | Expression (DB) | Python |
|---------|----------|-----|-----------------|--------|
| Standard Base RT | core_stats | id=12 | 400 | `400` |
| Boss Base RT | core_stats | id=13 | 300 | `300` |
| Rest RT | core_stats | id=14 | round(Modified Base RT × 0.75) | `round(mod_base_rt * 0.75)` |
| Modified Base RT | weapons_equipment | row 7 | Base RT + Effective Armor WT | `base_rt + eff_armor_wt` |
| Basic Attack RT | weapons_equipment | row 8 | round(Modified Base RT × 0.10) + Effective Weapon WT | `round(mod_base_rt * 0.10) + eff_wpn_wt` |
| Two-Attack Cycle RT | weapons_equipment | row 9 | Modified Base RT + 2 × Basic Attack RT | `mod_base_rt + 2 * basic_attack_rt` |
| Attacks per 1000 CT | weapons_equipment | row 10 | 2000 / Two-Attack Cycle RT | `2000 / two_attack_cycle_rt` |
| Guard RT | core_stats | id=22 | round(Modified Base RT × 0.10) + round(Effective Armor Off-Hand WT × 0.50) | `round(mod_base_rt * 0.10) + round(eff_offhand_wt * 0.50)` |
| 2H Guard RT (exception) | core_stats | id=48 | Armor Off-Hand WT = 0 if 2H weapon | offhand WT = 0 |
| Movement RT | movement_targeting | Movement RT row | round(Modified Base RT × 0.0625 × Tiles × (1 - AGI/(200+AGI))) | `round(mod_base_rt * 0.0625 * tiles * (1 - AGI/(200+AGI)))` |

---

## 4. COMBAT RESOLUTION

| Formula | DB Table | Row | Expression (DB) | Python |
|---------|----------|-----|-----------------|--------|
| Effective Defense | core_stats | id=31 | (Attack Power × Defense Power) / (Attack Power + Defense Power) | `(atk * def_p) / (atk + def_p)` |
| Raw Damage | core_stats | id=31 | Attack Power - Effective Defense | `atk_power - eff_defense` |
| Hit Quality | core_stats | id=35 | 1 + (Precision - Evasiveness) | `1 + (precision - evasiveness)` |
| Damage Sequence | core_stats | id=34 | 1.AtkPow 2.Def 3.OutDmgCat 4.HitQual 5.Positional 6.Element 7.Fortune 8.Guard 9.Round | (sequential) |
| Guard Mitigation | elements_statuses | Guard row | 35% base, +passive bonuses, cap 80% | `min(0.35 + bonus, 0.80)` |

---

## 5. WEAPON LEVEL SCALING

| Formula | DB Table | Row | Expression (DB) | Python |
|---------|----------|-----|-----------------|--------|
| Weapon Scale | weapons_equipment | WEAPON LEVEL SCALING row | 0.30 + 0.70 × ((Item Level - 1) / 98)^0.55 | `0.30 + 0.70 * ((item_level - 1) / 98) ** 0.55` |
| Scaled Property | weapons_equipment | same | Level 99 Base × Weapon Scale | `l99_base * weapon_scale` |

**Rules:** Level 1 = 30%. Level 99 = 100%. Zero stays zero. Negative preserves sign, increases magnitude. Range/Pattern/Projectile/Hands/passive% NOT scaled.

---

## 6. EQUIPMENT LEVEL SCALING (NON-WEAPON)

| Formula | DB Table | Row | Expression (DB) | Python |
|---------|----------|-----|-----------------|--------|
| Equipment Scale | nonweapon_equipment | Level scaling row | 0.30 + 0.70 × ((Item Level - 1) / 98)^0.55 | `0.30 + 0.70 * ((item_level - 1) / 98) ** 0.55` |

Same formula as weapons. Applied to Defense, Weight, HP, MP.

---

## 7. MP REGEN (PERSISTENT SYSTEM)

| Formula | DB Table | Row | Expression (DB) | Python |
|---------|----------|-----|-----------------|--------|
| MP Regen Rate | core_stats | id=49 | 2 + floor(INT / 40) MP per 1000 CT | `2 + INT // 40` |
| Accumulator | persistent_hp_mp_rules | MP Regen section | Accumulator += CT_passed × MP_Regen / 1000; restore floor(Acc) when ≥1 | CT-based accumulator |

---

## 8. STATUS EFFECT FORMULAS

| Status | DB Table | Expression | Python |
|--------|----------|------------|--------|
| Poison (per turn) | elements_statuses (Poison) | round(Max HP × 0.15 × Debuff Resistance × Boss HP% Mod) | `round(max_hp * 0.15 * debuff_res * boss_mod)` |
| Venom (per turn) | elements_statuses (Venom) | round(Max HP × 0.03 × Venom Strength × Debuff Res × Boss Mod) | `round(max_hp * 0.03 * strength * debuff_res * boss_mod)` |
| Bleed (on phys hit) | elements_statuses (Bleed) | round(Max HP × 0.05 × Debuff Res × Boss Mod) | `round(max_hp * 0.05 * debuff_res * boss_mod)` |
| Raptured (per tile) | elements_statuses (Raptured) | round(Max HP × 0.02 × Debuff Res × Boss Mod) | `round(max_hp * 0.02 * debuff_res * boss_mod)` |
| Wounded (per AP action) | elements_statuses (Wounded) | round(Max HP × 0.15 × Debuff Res × Boss Mod) | `round(max_hp * 0.15 * debuff_res * boss_mod)` |
| Burn (per tick) | elements_statuses (Burn) | round(Total Stored Burn × Debuff Res) | `round(stored_burn * debuff_res)` |
| Burn (on apply) | elements_statuses (Burn) | round(Fire Damage Dealt × 0.20) | `round(fire_dmg * 0.20)` |
| Regeneration | elements_statuses (Regeneration) | round(round(Max HP × 0.05) × (1 + VIT / 300)) every 300 CT | `round(round(max_hp * 0.05) * (1 + VIT / 300))` |
| Confuse backlash | elements_statuses (Confuse) | round(Final Enemy HP Damage × 0.30 × Debuff Res) | `round(final_dmg * 0.30 * debuff_res)` |
| Mana Burn extra | elements_statuses (Mana Burn) | round(Max MP × 0.20) extra cost; Damage = round(Total MP × 0.50 × Debuff Res) | formula in code |

---

## 9. BOSS MODIFIERS

| Modifier | DB Table | Row | Value |
|----------|----------|-----|-------|
| Debuff duration | core_stats | id=39 | 50% effectiveness |
| HP%-based debuff damage | core_stats | id=40 | 25% effectiveness |
| HP%-based environmental | core_stats | id=41 | 25% effectiveness |
| RT delay effects | core_stats | id=42 | 25-50% effectiveness |
| Hard-control duration | core_stats | id=43 | 20% effectiveness |

---

## 10. MISSING FORMULAS / BLOCKERS

- **Stat rounding rule:** Database says "do not round intermediate values; calculate the full result first, then round once at the final output." For stats at level, no explicit rounding rule found for the growth calculation. ASSUMPTION: floor(start + growth * (level-1)) for integer stats. **NEEDS CONFIRMATION.**
- **Frenzy effect on Basic Attack tempo:** "Affects Basic Attack tempo only" — exact multiplier NOT specified in database. **BLOCKER.**
- **Haste/Slow on Modified Base RT:** Haste = Base RT × 0.90, Slow = Base RT × 1.10 — this modifies BASE RT before adding Armor WT. Confirmed in DB.
- **Elevation damage bonus:** Database mentions High Ground passive adds "+35% to elevation damage bonus" but the BASE elevation bonus percentage is not specified. **BLOCKER.**
- **Positional Modifier (backstab etc.):** The damage sequence lists "Positional Modifier" at step 5 but no universal formula for facing/rear attack is found. Only weapon-specific (Backstab passive = +50% from behind). **No universal positional modifier exists unless authored.** Not a blocker.
- **Off-hand Damage contribution:** Off-hands have Damage stats but no formula for how off-hand damage contributes to attacks. **NEEDS CLARIFICATION** — likely only relevant for off-hand-specific effects, not basic attacks.

---

*End of registry. Updated each simulation run.*
