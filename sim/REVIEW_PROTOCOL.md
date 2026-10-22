# CTRBLXAI Content Examination Protocol

**Author:** Simulator CTRBLXAI · **Established:** 2026-10-22 (after a skill-balance session with 7 agent errors the user had to catch)

## When this applies (trigger — NOT limited to the word "review")

Load and follow this protocol whenever the task is **examining existing CTRBLXAI content against CTRBLXAI.db**,
no matter what the user calls it. Triggering phrasings include, but are NOT limited to:
"review", "audit", "balance check", "balance pass", "sanity check", "look at", "go over", "check",
"evaluate", "assess", "vet", "analyze", "is X balanced", "is X too strong/weak", "compare X and Y".

Applies to EVERY content type, present and future:
skills, weapons, gears/non-weapon equipment, augments, races, doctrines, consumables, enemies,
battlefield events, loot, map content, and any content type added later.

If in doubt whether a task counts: if it ends in a verdict about whether existing content is
balanced / strong / weak / redundant / correct, it counts. Follow the protocol.

## Why this exists

In the 2026-10-21/22 skill session the agent made ~7 errors the USER had to catch, wasting time and
shifting QA onto the user. Root causes (not 7 unrelated mistakes):
  A. Asserted from memory instead of querying (false superlatives: "only full-range skill", "cheapest",
     "no MP cost"; a backwards HP-cost comparison).
  B. Drew verdicts from a metric with known blind spots (ratio-vs-basic-attack sees RT/MP/cast only —
     blind to HP cost, positioning, and ACTION ECONOMY/AP; the knockback value was ~50% offense denial
     measured in AP, not the ~5% the agent first stated in RT).
  C. Scope creep + pricing unverified behavior (expanded a label fix into a full taxonomy; priced
     multi-hit skills before confirming the per-hit loop exists in code — it does not).

## The 5 rules

**1. Full record first.** Before discussing ANY entity, pull EVERY field/column of its DB row in one pass.
   No piecemeal field-by-field. (User standing preference, 2026-10-22: "when we review a [thing] i need
   100% of its info so we don't go back and forth.")

**2. No superlative/comparative without a query.** Any "only / cheapest / highest / fastest / lowest /
   best / worst / no X / unique" claim REQUIRES an enumerating query across the whole content table in the
   SAME turn. If not queried, do not make the claim — say "let me check" and query. This single rule would
   have prevented the Longshot, HP-comparison, and Power-Strike-MP errors.

**3. Enumerate every cost/benefit currency before any OP / weak / redundant / fine verdict — and name the
   blind spots.** Each content type trades in a different dimension set, and any quantitative metric sees
   only SOME of them. Before a verdict: (a) list the content type's full dimension set, (b) state which
   dimensions the metric cannot see, (c) account for those separately. A high/low number on one axis is
   NEVER a verdict until the axes it ignores are accounted for.
   Per-type dimension sets (seed list — fill out fully the first time each type is examined):
   - Skills: RT cost, MP, channel, cast delay (activation), HP/self-damage, positioning/exposure,
     action-economy (AP), element interaction, status/debuff riders, range/pattern.
     Ratio-vs-basic-attack metric SEES: RT, MP, cast time. BLIND TO: HP cost, positioning, AP, riders.
   - Weapons: damage, effective weight→RT, range, pattern, projectile, native passive, defense, BP.
   - Gears / non-weapon equipment: defense, weight→RT, HP/MP bonus, stat bonuses, slot cost, passive riders, BP.
   - Augments: effect magnitude, slot cost, stacking rules, eligibility, BP.
   - Races: starting stats, growth curves, passive upside, passive flaw (NOTE: user term is "flaws", not
     "drawbacks"), tags.
   - Doctrines: stat package, passives, granted skill, AI personality.
   KEY STANDING FACT: action/turn denial (displacement, stun, RT delay, AP loss) is the STRONGEST lever in
   a CT + AP system (FFT lesson). ALWAYS evaluate displacement/control in AP and turn tempo, never in RT alone.
   KEY STANDING FACT: cost comes in many forms (RT, MP, channel, cast delay, HP/self-damage, positioning).
   A skill with 0 MP / 0 channel is NOT undercosted if it pays another way (e.g. Blood Price pays HP).
   NULL channel/activation is NOT a blocker — it legitimately means instant (correct for gap-closers).

**4. Design vs. code separation.** Never price behavior not confirmed implemented. The DB gives INTENT;
   whether the code does it is the Tester/Auditor agent's lane. Route wiring questions there BEFORE
   simulating value. (Multi-hit lesson: per-hit loop + native-passive procs are UNWIRED as of 2026-10-22,
   so the multi-hit archetype's justification does not exist in-game yet.)

**5. Stay in the decided scope.** Log what the user decided. Flag adjacent ideas as one-line options; do
   not build them out uninvited.

## Honest limit
A checklist reduces recurrence; it does not guarantee zero errors. The user catching mistakes remains a
real backstop. But rules 1–3 would have prevented 5 of the 7 errors in the session that created this file.
