
╔══════════════════════════════════════════════════════════════════════╗
║            CTRBLXAI ECONOMY BALANCE SIMULATION REPORT              ║
║                     2026-09-16 — Seed: N/A (deterministic)         ║
╚══════════════════════════════════════════════════════════════════════╝

FORMULAS LOADED: 14
  Kill Gold, Battle Completion Gold, Quest Reward Gold, Kill XP,
  XP to Next Level, Overleveled Penalty, Sell Value, Shop Price,
  Blacksmith Gold/Level, Recruitment Fee, Inventory Maintenance,
  Consumable Price, Material Tier Assignment, Fortune Gold Multiplier

CONTENT ENTRIES: 140 consumable items, 9 proposed facilities
TABLES QUERIED: economy_framework (46r), materials_system (39r),
  consumable_framework (38r), consumable_items (140r),
  unit_progression (66r), loot_progression (81r)

════════════════════════════════════════════════════════════════
 SECTION 1: BLOCKERS
════════════════════════════════════════════════════════════════

None. All formulas needed for economy simulation are present in the
database. The facility cost formula is user-proposed (not yet in DB)
but was provided explicitly for validation.

NOTE: The overleveled gold penalty scope is ambiguous. The DB says
"same bands as XP" but does not specify whether it applies to kill
gold only, or also to completion and quest gold. This matters for
anti-farming behavior. Recommend: clarify in economy_framework.

════════════════════════════════════════════════════════════════
 SECTION 2: CRITICAL FINDINGS
════════════════════════════════════════════════════════════════

None. No formula produces degenerate values. No unbounded loops.
No immunity-equivalent gold exploits. Buy/sell ratio is a clean 16:1
at all levels with no arbitrage. Curves scale monotonically.

════════════════════════════════════════════════════════════════
 SECTION 3: PER-CHECK RESULTS
════════════════════════════════════════════════════════════════

┌────────────────────────────────────────────────────────────────────┐
│ CHECK 1: Lifetime Gold Income Reproduction                 PASS   │
├────────────────────────────────────────────────────────────────────┤
│ Simulated: 178,685g from 547 battles (DB: ~175,800g from ~547)    │
│ Battle gold: 168,109g (+1.9%). Sell income: 10,576g (-2.1%).      │
│ Model: 6 Grunts + 0.6 Veterans, quest gold every battle.         │
│ Income curve scales smoothly: 163g/battle at L1 → 437g at L98.   │
│ All level bands contribute proportionally.                        │
└────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────┐
│ CHECK 2: Gold Sink Balance / Free Player Deficit           WARN   │
├────────────────────────────────────────────────────────────────────┤
│ Using DB necessities (127,800g) + proposed facilities (55,724g):  │
│ Total expenses: 183,524g → deficit of 4,839g (102.7% of income).  │
│                                                                    │
│ Free player can max 8 of 9 facilities (not 7 as claimed).         │
│ All facilities except Blacksmith (24,420g) are affordable.        │
│ Remaining 19,581g covers Blacksmith to L13 of 15.                 │
│                                                                    │
│ The "~7,700g deficit" claim appears to use the DB's slightly      │
│ lower income figure (175,800g). With that: deficit = 7,524g,      │
│ but free player still maxes 8/9 (budget = 48,000g > 31,304g      │
│ for 8 cheapest).                                                   │
│                                                                    │
│ ⚠ If the intent is 7/9, necessities need to be ~3,000-4,000g     │
│   higher, or one facility needs to cost ~4,000-5,000g more.       │
│                                                                    │
│ The proposed 55,724g total is 29% LOWER than the DB's old         │
│ placeholder of 77,500g. With old costs: 115% expense ratio,       │
│ confirming the 113% claim. New costs feel too light for the       │
│ "luxury progression" role.                                         │
└────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────┐
│ CHECK 3: Material Income vs Spend                          PASS   │
├────────────────────────────────────────────────────────────────────┤
│ T3/T4 at 89% usage: CONFIRMED against DB's income distribution.   │
│ Against simulation income (slightly different distribution): 82%.  │
│ All tiers have positive surplus at 10 upgrades.                    │
│ T1 massively surplus (237 excess) → conversion safety net.        │
│ T5 comfortable (226 surplus, daily-gated).                        │
└────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────┐
│ CHECK 4: Material Stress Test (12/15 upgrades)             WARN   │
├────────────────────────────────────────────────────────────────────┤
│ 10 upgrades: All surplus. T3/T4 at 82% used.              PASS   │
│ 12 upgrades: All surplus. T3/T4 at 98% — razor thin.      PASS*  │
│ 13 upgrades: T3/T4 exceed income — FIRST DEFICIT.         BREAK  │
│ 15 upgrades: T3 deficit 70, T4 deficit 70.                        │
│   Conversion covers T3 (surplus T1+T2 cascade).                   │
│   T4 deficit of 70 requires ~27 targeted battles.          WARN   │
│ 18 upgrades: Severe T3/T4 deficit. 45-57 extra battles.   FAIL   │
│                                                                    │
│ Break point: 13 upgrades (×1.3 of baseline).                      │
│ Players upgrading more than 12 items will need targeted farming   │
│ in the L41-80 range. This is a soft wall, not a hard one.         │
└────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────┐
│ CHECK 5: Consumable Pricing vs Battle Income               PASS   │
├────────────────────────────────────────────────────────────────────┤
│ All 140 item prices match the formula exactly.                     │
│ Range: 25g (Common Quick) to 480g (Epic Battlefield). ✓            │
│                                                                    │
│ Affordability by level:                                            │
│   Common Quick (25g): 5.7-15.3% of one battle. Always trivial.   │
│   Rare Standard (150g): 34-92% of one battle. Meaningful choice.  │
│   Epic Battlefield (480g): 109-295% of one battle. Luxury item.   │
│                                                                    │
│ Purchasing power improves with level (gold/battle grows faster    │
│ than flat consumable prices). No consumable becomes unaffordable.  │
│                                                                    │
│ ~10% of lifetime income claim is plausible at ~100 purchases      │
│ across 6 units × 3 slots × ~5-6 upgrade cycles.                  │
└────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────┐
│ CHECK 6: Facility Cost Curve                               WARN   │
├────────────────────────────────────────────────────────────────────┤
│ Early levels (L1): ALL facilities < 1.8 battles. Feels good.  ✓  │
│ Late levels: MIXED.                                                │
│   Blacksmith L15: 10.4 battles — meaningful and earned.        ✓  │
│   Guild Hall L10: 3.1 battles — appropriately weighted.        ✓  │
│   Tavern/Merchant L10: 1.9 battles — TOO CHEAP at endgame.    ⚠  │
│   Quest Board/Workshop L10: 1.1-1.3 battles — TOO CHEAP.      ⚠  │
│                                                                    │
│ Four facilities (Tavern, Merchant, Quest Board, Workshop) have    │
│ max-level costs that feel trivial at endgame. Their combined      │
│ max-level costs (520+433+750+750 = 2,453g) equal ~6 battles.     │
│ Consider raising scale denominators or max levels for these.      │
│                                                                    │
│ Growth ratio: 3.2x (Trophy) to 15.0x (Blacksmith). The           │
│ Blacksmith's 15-level range creates good escalation. Other        │
│ facilities with only 10 levels and large scale values feel flat.  │
└────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────┐
│ CHECK 7: Robux Gold Boost (+25%)                           PASS   │
├────────────────────────────────────────────────────────────────────┤
│ Free income: 178,685g. Boosted: 220,713g (+23.5%).                │
│ Boosted surplus: +37,189g after all 9 facilities.          ✓      │
│ Boosted player CAN max all 9 facilities.                   ✓      │
│ Expense ratio: 102.7% (free) → 83.2% (boosted).                  │
│                                                                    │
│ With old facility costs (77,500g): 115% → 93%. Matches DB claim. │
│ The proposed lower facility costs make the boost MORE powerful    │
│ than intended — surplus is comfortable rather than tight.         │
│                                                                    │
│ ⚠ Fortune (LUK=200) gives the same +25% as Robux boost.          │
│ Stacked: ×1.25 × ×1.25 = ×1.5625 (+56% gold).                   │
│ This is within Fortune's capped design (max ×1.50), so the       │
│ multiplicative stacking is acceptable but worth monitoring.       │
└────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────┐
│ CHECK 8: Edge Cases                                        PASS   │
├────────────────────────────────────────────────────────────────────┤
│ L1 values: All non-zero, all proportional. Buy/sell 16:1.     ✓  │
│ L99 values: No overflow, no degeneracy.                        ✓  │
│ 0 enemies: Completion + quest gold still awarded. No exploit.  ✓  │
│ Max Fortune: Capped at ×1.50. Curve is asymptotic and smooth.  ✓  │
│ Purchasing power: 2.45-2.69 battles per Common weapon.         ✓  │
│   (DB claims 2.5-2.7; L1 is 2.45 — technically outside range) │
│ Broken items: Sell for 1-2g. Correct (penalty rarity).         ✓  │
│ Transcendent BS: 44% of lifetime income for L80-99. Prohibitive│
│   as intended (event-exclusive rarity).                        ✓  │
│ Facility formula at L0/-1: produces valid-looking but wrong       │
│   values. Implementation must clamp level to [1, max].         ⚠  │
│ Overleveled penalty scope: ambiguous for completion/quest gold. ⚠  │
└────────────────────────────────────────────────────────────────────┘

════════════════════════════════════════════════════════════════
 SECTION 4: SUMMARY VERDICTS
════════════════════════════════════════════════════════════════

  CHECK                                    VERDICT
  ─────────────────────────────────────── ─────────
  1. Lifetime income reproduction          PASS (+1.6%)
  2. Gold sink / free player deficit       WARN (8/9 not 7/9)
  3. Material income vs spend              PASS (89% confirmed)
  4. Material stress test 12/15            WARN (breaks at 13)
  5. Consumable pricing                    PASS (all correct)
  6. Facility cost curve                   WARN (4 facs too cheap)
  7. Robux Gold Boost                      PASS (boost works)
  8. Edge cases                            PASS (2 minor notes)

════════════════════════════════════════════════════════════════
 SECTION 5: RECOMMENDATIONS
════════════════════════════════════════════════════════════════

1. FACILITY COSTS TOO LOW: The proposed 55,724g is 29% below the
   DB's target of ~78,000g. This makes the free player deficit only
   ~5,000g instead of ~30,000g, undermining the "luxury cannot be
   completed" design goal. Either raise facility costs toward the
   original ~78,000g target, or accept that free players will max
   8/9 facilities.

2. FOUR CHEAP FACILITIES: Tavern, Merchant, Quest Board, and
   Workshop have trivial max-level costs (1.0-1.9 battles). Options:
   a) Reduce their scale denominators (e.g., 30→18 for Workshop)
   b) Increase their max levels to 12-15
   c) Both — this would also raise total facility costs toward ~78k

3. CLARIFY OVERLEVELED GOLD PENALTY SCOPE: Does the penalty apply
   to kill gold only, or also completion and quest gold? If only
   kills: a L99 player farming L1 content still earns ~88g/battle
   (mostly from completion + quest). If all gold: ~14g/battle.
   Recommend: penalty applies to ALL gold sources in the battle.

4. MATERIAL BREAK AT 13 ITEMS: Players upgrading more than 12 items
   will hit T3/T4 scarcity. This is probably acceptable — it creates
   a soft farming signal. But document it as an intentional wall.

5. FACILITY FORMULA GUARD: Clamp level input to [1, max_level] in
   implementation. The L²/scale formula produces valid-seeming
   outputs at L0 and negative levels.

════════════════════════════════════════════════════════════════
 VERDICT: 0 CRITICAL FINDINGS. 3 WARNINGS. ECONOMY IS SOUND.
════════════════════════════════════════════════════════════════

 Files modified: sim\ only. Source and docs untouched.
