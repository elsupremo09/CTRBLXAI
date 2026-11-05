# FORMULAS — Apothecary paid-refill check, 2026-11-03
Economy base unchanged: sim\runeforge_v2_2026-11-01\FORMULAS_v2.md and sim\crucible_2026-11-02\FORMULAS_crucible.md (reused by exec, all prov() asserts passed).
DB md5 this run: d2cda0a8… (start = end). Not the same as 2026-11-02 (ea957228…), so a Designer wrote to the DB in between. Every row asserted below was still present.

## DB rows asserted (prov), matched by text
| Name | Table / row | Expression in DB | Python | Match |
|---|---|---|---|---|
| Consumable price | consumable_framework 30-32 | round(Base Profile × Tier / 5) × 5; Quick 25 / Routine 50 / Standard 75 / Heavy 110 / Battlefield 160; ×1.0/1.4/2.0/3.0 | `round(PROF_BASE[p]*TIER_M[t]/5)*5` | ✅ all 137 items |
| Usage anchor | consumable_framework 36, 38; economy_framework 27 | Routine (4 ch) lasts about 4 encounters; consumables are about 10% of lifetime income | used as the "normal" usage assumption | ✅ |
| Old sell rule | consumable_framework 37 | cannot be sold | replaced by the user rule below | ✅ (being changed) |
| Lifetime income | economy_framework 42 | battle 165,000 + sell 10,800 = 175,800, about 547 battles | `BG = INC × 165000/175800` | ✅ |
| Necessities | economy_framework 43 | about 127,800g, including consumables of about 17,500g | NEC; buying line CB spread like income | ✅ |
| Basics principle | economy_framework 1 | Basics always affordable | check: necessities + refills < 100%, cash never below 0 | ✅ |
| Workshop curve | guild_facilities 18, 31 | Base 150 / Scale 22; L1-L10 157…832; total 4,123; Guild Hall L4 | `FAC['Workshop']`, reused as the Apothecary | ✅ |
| Refill step | game_flow 20 | refill item charges on return to base | refill charged once per battle | ✅ |
| Stalling | persistent_hp_mp_rules 15, 11 | stalling allowed; MP Regen = 2 + floor(INT/40) per 1000 CT | used for the bypass check | ✅ |
| Restock | skills 109 | MP round(3 + 0.08×(L−1)); +1 charge to every equipped item | bypass check | ✅ |
| AC-009 / AC-008 / AC-018 | nonweapon_equipment 116 / 115 / 125 | +20% charges (min +1) at battle setup / +1 charge when hit / +1 charge every 2 basic attacks | bypass check | ✅ (DB text only, in-code status not checked) |

## Apothecary rules (user decision 2026-11-03 + design doc; NOT in the DB yet)
- Refill = ceil(list × missing ÷ max × RATE[L]); RATE L0 and L1 = 75%, then 69/64/58/53/47/42/36/31/25. Check: `75 − round(50(L−1)/9)` ✅
- Buy = list × (1 − 0.03 × (L−1)); tested with both round and floor.
- Sell = floor(list × 20% × charges left ÷ max).
- L9: max = floor(max × 1.25). Tested both ways: refill divided by the new max, and by the base max.
- Shelf 4→8 and the L10 +1 slot: no gold effect, so not modelled.

## Assumptions (NOT in the DB)
- Usage = list value of the charges used per battle. Light / normal / heavy = 5 / 10 / 20% of that battle's gold. Flat versions: 30g and 60g per battle. Stress case: the design doc's example squad, 87.5g per battle.
- Boosted players use the same items as free players (Gold Boost does not raise usage).
- The 17,500g consumable buying in economy_framework 43 stays, and the buy discount reduces it.
- No consumable loot drop rate exists in the DB, so gold from selling looted consumables is not measured.
