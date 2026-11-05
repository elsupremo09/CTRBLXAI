# SIMULATION RUN — 2026-11-01 — Daily systems lifetime check
Seed: 20261101 (expected-value model, no random draws). Run twice: results identical, including once after the Designer changed the DB mid-run.
DB: opened read-only. md5 4f91d76e… at the start and 7ea3fde2… at the end (the Designer was writing). All 54 provenance strings passed both times.
Formulas/rows loaded: 54 (35 from FORMULAS_v2.md + 19 new: materials_system 7/10-14/36/41/42, loot_progression 15/26/86, guild_facilities 17/38, unit_progression 77/94/95, game_flow 20/28, skills SKL-ICE-SPIKE, nonweapon_equipment 34).
Baseline check: the old R2 numbers come out exactly (1,553.5 / 1,848.9 mercury).
Files: daily_sim.py, results_daily.json, this report. All are in sim\daily_systems_2026-11-01\. source\ and docs\ were not touched.

## Assumptions (state them; none are in the DB unless a row is named)
| Item | Value used | Source |
|---|---|---|
| Battles per lifetime | 547 | materials_system 36 |
| **Win rate** | **90%** (80-100% tested) | **NEW GAP, not in DB.** Everything that is "victory only" is multiplied by it |
| Equipment drops | 0.40 per battle, victory only (chest and salvage gear are now held too) | G7, lp 24 |
| Dismantling | 75% / 100% of drops | as before |
| Kills | 5 enemies × 5% × win rate | ms 7, lp 86 |
| Quest mercury | 2/7 per battle × win rate | ms 11 |
| Chest | 0.2 per battle, 1 mercury, × win rate | lp 26, ms 10 |
| Dispatch | 0.3 per battle. Not victory-gated | G2, ms 12 |
| Elite | 0.034 per battle × win rate | lp 26 |
| Boss | **0.034 per battle × win rate** (base case). Other cases in Q4 | lp 26 |
| Salvager's Cap | not worn (base case) | — |
| Play days | G3 / 0.875 (the Designer's 85-90% completion) | design doc C |
| Quest Board L8 (boss quests) | earliest at battle 81: spare gold covers Guild Hall L1-3 + QB L1-8 = 4,260g | gf 17/30 |

## Q1 — Lifetime totals (win rate 90%; 75-100% dismantling)
| Daily contracts (G3) | Mercury | Full levellings | Crystals | Rune gems | Sulfur (daily part) |
|---|---|---|---|---|---|
| 30 | 1,558-1,823 | **15.9-18.6** | 248-286 | 160-204 | 22.4-23.7 (10) |
| 80 | 1,808-2,073 | **18.4-21.2** | 248-286 | 160-204 | 38.4-39.7 (26) |
| 180 | 2,308-2,573 | **23.6-26.3** | 248-286 | 160-204 | 72.4-73.7 (60) |

- Mercury at G3 = 80 and 100% dismantling (2,073): dismantling 1,063 · daily 400 · dispatch 164 · quests 141 · kills 123 · chests 99 · bosses 50 · elites 34.
- Win rate: at G3 = 80, 80% wins gives 17.0-19.5 levellings and 100% wins gives 19.9-22.9. The Designer's 20-23 is the all-wins case.

## Q2 — Levellings vs the 15-20 target
- G3 = 30: 15.9-18.6. **Inside.**
- G3 = 80: 18.4-21.2. **Over by up to 1.2 at 100% dismantling** (that is 114 mercury).
- G3 = 180: 23.6-26.3. **Over by 3.6-6.3.**
- The G3 range (30-180) is 750 mercury wide, which is 7.7 levellings. The whole target band is only 5 levellings wide. That makes the daily contract the term that decides whether the target holds.

## Q3 — One knob (levellings at 75% / 100% dismantling)
| Knob | G3 = 30 | G3 = 80 | G3 = 180 |
|---|---|---|---|
| Now (daily 5, dispatch 0.3) | 15.9 / 18.6 | 18.4 / **21.2** | **23.6 / 26.3** |
| **Daily 5 → 3** | 15.3 / 18.0 | 16.8 / 19.5 | 19.9 / **22.6** |
| Daily 5 → 4 | 15.6 / 18.3 | 17.6 / **20.3** | **21.7 / 24.4** |
| Dispatch 0.3 → 0.15 per battle | 15.1 / 17.8 | 17.6 / **20.3** | **22.7 / 25.4** |
| Dispatch → 0 | **14.2** / 16.9 | 16.8 / 19.5 | **21.9 / 24.6** |
| Quest 1 in 7 → 1 in 14 | 15.2 / 17.9 | 17.7 / **20.4** | **22.8 / 25.5** |
| Kill 5% → 3% (not allowed by ms 12) | 15.4 / 18.1 | 17.9 / **20.7** | **23.1 / 25.8** |

- Exact values that hit 20.0 at G3 = 80 / 100%:
  - daily 3.59 mercury
  - dispatch 0.094 per battle (−69%)
  - quest mercury 0.056 per battle (about 1 quest in 35)
  - kill chance 0.4%
- **Recommendation: daily contract 5 → 3 mercury** (keep 1 sulfur every 3rd).
  - It is the only knob that brings G3 = 80 inside the band and keeps G3 = 30 above 15.
  - It is also the only knob that shrinks with G3: G3 = 180 drops from 26.3 to 22.6.
  - Dispatch would have to go almost to 0, which pushes G3 = 30 / 75% below 15 (14.2) and still leaves G3 = 180 at 21.9-24.6.
- **Warning on dispatch:** 0.3 per battle is still gap G2.
  - At 0.6 per battle the wall is 20.1-22.8 before any change.
  - The rules allow up to 1.83 missions per battle. With mercury-optimal slots (tiers 1 + 2 + 4) that is 2.0 mercury per battle (27.9-30.7 levellings) for about 48k gold.
  - Re-check when G2 is measured.

## Q4 — Crystals, sulfur, exploits
**Runeforge Epics and sulfur at the base boss rate (0.034):** almost no change vs report_recheck_v2.
- Crystals are 248-286 against 275-318 before. They are slightly **lower**, because elite, boss and drop rewards are now victory-only.
- Epic crafts from income (after 20 swaps): 7.3-10.5 from Rare, or 4.2-6.0 from Common. Before: 5.5-13.
- Sulfur from loot is 12.4-13.7. The daily contract adds 10 / 26 / 60. At G3 = 80 that is 38-40 sulfur, so Legendary rerolls go from 7-8 to about 19-20. **Daily sulfur is 68% of all sulfur at G3 = 80.** That is the intended "daily-paced" role, but it is the biggest sulfur change.

**F1 — The boss rate, not the grant size, decides the economy (CRITICAL, design-level)**
- A boss card is 1 in 10, and the board has about 11 cards at QB L8 (69% chance of at least one boss per board).
- The 3-per-day cap only binds per real day. A player who takes every boss card hits it every day from battle 81 on.

| Boss case (G3 = 80) | Boss wins | Levellings | Crystals | Epic crafts (from Rare) | Sulfur |
|---|---|---|---|---|---|
| 0.034 estimate | 17 | 18.4-21.2 | 248-286 | 7-10 | 38-40 |
| Random card pick (10% of battles from battle 81) | 42 | 20.5-23.7 | 415-467 | 21-26 | 51-53 |
| Boss-seeker, cap 1 per day | 70 | 22.7-26.3 | 598-664 | 37-42 | 64-66 |
| **Boss-seeker, cap 3 per day (locked)** | **210** | **33.5-39.3** | **1,510-1,646** | **113-124** | **130-131** |

- With the locked rule, a boss-seeker ends with 5-6× the crystals and 3× the sulfur. The accepted crystal shortage (ms 38) disappears.
- With daily 3, the random-pick case is still 18.9-22.0.
- **The 0.034 boss estimate does not fit "1 card in 10 + the player chooses".** Nothing here is an unbounded loop: the cap does hold, at 3 × play days.

**F2 — Ice Spike + Salvager's Cap: no limit per battle (CRITICAL)**
- Salvager's Cap pays for "OBS blocker props (Ice Spike…)" and "placed items (Deployable)" (nonweapon_equipment 34).
- Conjure Ice Spike (SKL-ICE-SPIKE) places one for round(5 + 0.12 × (L−1)) MP: 11 MP at L50. A Fire hit breaks it in one hit.
- That makes 2 actions per salvage roll: 25g at L50, a 5% chance of 1 mercury and a 5% chance of a gear item.
- One caster at INT 100 has 20 spikes from a full MP pool at L50 (12 at L99), plus one more every 2,750 CT from regeneration. No turn limit was found in the DB, so leaving one enemy alive makes the farm open-ended.

| Spikes per won battle | Levellings (G3 = 80, 100%) | Crystals | Gems | Mercury from salvage alone |
|---|---|---|---|---|
| 0 | 21.2 | 286 | 204 | 0 |
| 10 | 37.2 | 476 | 429 | 246 |
| 30 | 69.4 | 855 | 877 | 738 |
| 60 | 117.6 | 1,425 | 1,549 | 1,477 |

- At 30 spikes per battle the gold is also about 370k, more than 2× the lifetime income.
- Your own Deployables do the same thing, but charges limit them (1-3 each, refilled only at base).
- Holding salvage loot until victory does not stop any of this.
- Even legitimate use (1-2 natural breaks per battle) adds +1.6 to +3.2 levellings.

**F3 — Elite fishing with a hidden roll per card (HIGH)**
- The roll is fixed on the card, but anyone can read it: accept the card, look at the departure briefing, then abandon it (50% of that card's quest gold, game_flow 28). Repeat for every card on the board.
- With 3 → 12 normal cards, an elite can be found on 23.5% of boards (×6.9 the intended rate). That gives 115 elites a lifetime, 655-730 crystals and 23.5-27.3 levellings. With the code's 3-card board it is about 10% (×2.9).
- **Returning to base without fighting.** Every route back to base in the DB is a battle end (game_flow 17/18/30). But **Escape** is a battle end that needs no fighting (unit_progression 95). Each return counts toward the board refresh (game_flow 20). Escape costs 100 Guild XP, but it **costs nothing at the Guild-level floor** (unit_progression 94).
  - So Escape → new board → new hidden rolls. In the worst case every won battle is an elite: 492 elites, 43-51 levellings, about 2,200-2,400 crystals.
  - Escaping only re-rolls if the board really refreshes on that return (game_flow 21 is still open) and if Escape is allowed at the very start of a battle (not defined).
- The same free Escape also speeds up dispatch: each Escape burns 1 dispatch day (unit_progression 77, "minimum 1 day per battle"). That is up to 2 mercury per Escape for about 88g of missions, about 44g per mercury, with no risk.

**F4 — Bosses up to 3 a day:** the cap cannot be beaten through the day boundary, because the check happens at battle end on the server day. Escape-refresh helps a player find boss cards, but it does not raise the cap. The real issue is F1 (the size of the cap). Saves held open on two servers and rollback are still Dev question 1.

**F5 — Retrying a lost daily: no exploit.** The 5 mercury and the sulfur progress are paid once, on the win. The map seed is fixed per day, so a retry replays the same map (learnable, but fine). A defeat pays out like any other loss. At most one contract can be pending at a time, so a player cannot bank them.

## Q5 — Holding chest loot until victory
- In numbers it is small. Chest mercury goes from 109 to 99 a lifetime (−0.1 levelling). Chest gold lost on defeats is about 270g of about 5,500g. Salvage and chest gear lost on defeats are about 10%, the same as other loot.
- In design terms it matters. It closes the "open chests, then Escape" farm. Under the old rule that farm was free at the Guild-XP floor (F3). It also gives one rule for kills, chests, salvage, Steal and the Treasure Hunter.
- **DB conflict:** materials_system 10 and 14 still say chest and salvage mercury is "kept even if the battle is lost". They need the locked wording (Designer).

## Outliers
| Entry | Class | Evidence |
|---|---|---|
| Salvager's Cap + Conjure Ice Spike | DOMINANT (combination) | 10 spikes per battle = +16 levellings, +190 crystals |
| Boss card (3/day cap) | DOMINANT (activity) | 1 boss = 3 mercury + 5 crystals + 1 gem + 1 sulfur + a Rare+ item, vs a normal battle at about 0.9 mercury |
| Daily contract | HEALTHY at 3 mercury; over at 5 when G3 ≥ 80 | Q3 |

## Healthy
- The kill, quest, chest and elite (base rate) mercury amounts are all small and victory-gated. The cap does limit bosses (no unbounded boss loop).
- Fortune still touches none of these (ms 19, lp 12).
- No gold loop through materials (they cannot be sold).

## Delta vs report_recheck_v2
- **New:**
  - The 90% win-rate assumption (victory-only payouts) cuts about 1.7 levellings at G3 = 80.
  - F1 (boss rate), F2 (Ice Spike salvage), F3 (elite fishing and Escape refresh), the dispatch fast-forward through Escape, and the ms 10/14 wording conflict.
- **Resolved:** G3 now has a working estimate (30/80/180).
- **Unchanged:** crystal shortage at the base boss rate. Sulfur from loot is 12.4-13.7.
- **DB:** the 54 asserted strings are present. The DB changed during the run (the Designer), and none of the rows used changed.

## Decisions for the developer
1. **Mercury knob (pick one):**
   - A: daily 5 → 3 *(recommended)*
   - B: daily 5 → 4 (20.3 at G3 = 80 / 100%, just over)
   - C: dispatch to about 0.1 per battle (needs a per-mission rule, for example mercury only from tier 3-5 missions; G2 is unmeasured)
   - D: keep it (accept 21 at the centre case)
2. **Salvager's Cap (F2):**
   - A: map-generated objects only, no skill- or item-placed objects of either side *(recommended)*
   - B: exclude only your own team's placed objects
   - C: at most N salvage rolls per battle
3. **Elite roll (F3):**
   - A: roll from the player's lifetime-**victory** count, so the next won normal battle is elite or not whichever card is picked; abandon and Escape cannot change it *(recommended)*
   - B: keep the per-card roll and reveal it only after battle start (still open to fishing through Escape)
   - C: keep it as is
4. **Escape:** decide whether it is allowed at battle start, and whether an Escape refreshes the board and burns dispatch days. Recommend: only a battle that reaches round 2, or a victory, counts toward the board refresh and dispatch.
5. **Boss rate (F1):** replace the 0.034 estimate.
   - A: accept boss-seeking (3/day, up to about 210 bosses)
   - B: 1 rewarded boss per day (about 70)
   - C: keep 3 per day for the item, but give the material grants on the first boss of the day only
   - Re-run the mercury knob after this decision.

VERDICT: 3 CRITICAL FINDINGS — highest priority: Salvager's Cap + Conjure Ice Spike gives mercury, gear and gold with no limit inside a battle (10 spikes per battle = +16 levellings). Also: the boss cap allows 6-12× the estimated boss income, and hidden elite rolls can be fished. Mercury at G3 = 80 is 18.4-21.2 levellings; daily 5 → 3 brings it to 16.8-19.5.

Files modified: sim\ only. Source and docs untouched.
