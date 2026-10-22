
## 3. SKL-LONGSHOT — Longshot

**Changes (user, 2026-10-22):**
  1. `Targeting_Range`: **weapon + 200% × Bonus Skill Range** (was: inherit complete Weapon Range profile, incl.
     Max/Min Range, with no BSR). New range = full weapon range profile PLUS 200% of Bonus Skill Range
     (BSR = floor(INT/75), so +2×floor(INT/75) tiles on top of weapon Maximum Range).
  2. `Channel_Time`: **150 → 0**.  `Activation_Time`: **50 → 150** (replace the interruptible channel with a
     non-interruptible casting delay of 150).
  3. Multiplier (1.30×), RT Cost (×1.50), MP cost: UNCHANGED.

**Decided by:** user, 2026-10-22.

**Rationale (user):** Longshot's identity should be RANGE itself. Give it the longest reach in the game via
weapon range + 200% Bonus Skill Range, and swap the interruptible channel for a non-interruptible casting delay
so it resolves once committed.

**Context that drove this (Simulator):** Power Strike was found to ALSO inherit the complete weapon Max Range on a
projectile-compatible weapon (identical range wording), at 1.25× with 0 channel / 0 activation / RT ×1.00 — so the
old Longshot (1.30×, 150 channel + 50 activation, RT ×1.50) was strictly dominated by Power Strike on any bow.
The reach-identity reframe gives Longshot a role Power Strike does not have (weapon range + BSR extension).

**Simulator-measured effect (Human + Sword reference, ratio vs basic attack):**
  - L99: old 1.10 → new 1.17. L1: 0.90 → 1.00. L300: 1.45 → 1.49. Modest throughput gain (total cast time
    185→150 CT at L99 AND now interrupt-proof). Still below Fire Bolt (1.44) and Power Strike (1.76) on raw
    throughput — INTENDED: Longshot trades damage/tempo for reach, it is not a damage buff.
  - Reach identity (extra tiles on top of weapon Max Range, = 2×floor(INT/75)): scales with INT, so it lands on
    INT builds, not low-INT ones. Human: +0 until L250 (+2). Elf: +2 @L99, +8 @L300 (→ ~14-tile range on a
    Longbow). So Longshot becomes the archer-mage's long-range sniper — distinct from Power Strike's role.

**Simulator notes / cautions for Designer:**
  - Range form `weapon + 200% × Bonus Skill Range` is a NEW hybrid (weapon-derived base PLUS a BSR share). No
    existing skill combines weapon range with a BSR share — confirm the range parser supports this composition.
  - Channel→Activation swap has two real consequences beyond "interrupt-proof": (a) Activation Time is NOT reduced
    by DEX (Channel is), so high-DEX users lose the cast-time reduction they had — at very high DEX the new fixed
    150 can be slightly SLOWER than the old DEX-reduced channel; (b) non-interruptible removes the counterplay
    window the 150 channel gave enemies. Both are consistent with the "fire from max range, resolves once
    committed" identity, but they are design consequences worth noting.
  - Under the #2 terminology: this range is **variable** (computed: weapon + 200%×BSR), not fixed.

**Opened:** 2026-10-22
**Author:** Simulator CTRBLXAI (records decisions only — does not edit DB/source)
**Status:** IN PROGRESS — compiling. Do NOT hand over until the user says the review is complete.

These are user-decided change decisions from a skill-balance review session. Each entry gives the
current DB value, the decided new value, the rationale, and any Simulator note. The Designer agent
documents these in CTRBLXAI.db; the Simulator does not apply them.

---

## 1. SKL-BLOOD-PRICE — Blood Price

**Change:** `Targeting_Range` from **"Fixed 3; add 100% inherited Bonus Skill Range"** → **`range: 1` (fixed, literal — no Bonus Skill Range)**.

**Decided by:** user, 2026-10-22.

**Rationale (user):** Use range as a limitation and make the 15% Max HP self-cost a *real risk*. At range 1 the
caster must be adjacent to the target, so it pays the HP cost while exposed to melee retaliation and positioning
pressure, instead of being a safe ranged nuke.

**Note:** Under the clarified "fixed" definition (see #2), `range: 1` means literally 1 — no Bonus Skill Range is
added, so INT cannot extend it. True adjacency.

**Simulator note:** Range does NOT change the per-cast damage — Blood Price stays at ratio ~2.25 vs a basic
attack (L99). This change addresses the *risk/exposure* dimension only, not the per-cast damage dominance.

**Per-cast damage dominance — CLOSED, no change (user, 2026-10-22):** The user judged the HP cost + forced
adjacency a sufficient, self-enforcing limitation and declined any damage-lever change (multiplier / RT / MP stay
as-is). Rationale (user): a skill that costs HP AND requires short range is a serious cost; at 2 AP, casting it
twice in a turn already spends 30% Max HP. The per-cast ratio (~2.25) ignores this HP economy — solo, the 15%
Max HP cost self-caps throughput to ~3 turns before lockout (cannot cast below 15% HP). Combined with Dark tag
(heals Undead enemies) and range 1, the drawbacks are adequate. NO further Blood Price changes.

**Net for Designer: Blood Price has exactly ONE change — Targeting_Range → `range: 1` (fixed). Nothing else.**

---

## 2. "Fixed" range label — terminology clarification only (NO formula changes)

**Change:** Terminology/labeling only. The user's SOLE concern: a range termed "Fixed" must be literally fixed.
The current DB phrasing "Fixed N; add X% inherited Bonus Skill Range" is self-contradictory — it is not fixed if
Bonus Skill Range is added.

**Decided by:** user, 2026-10-22.

**Clarified meaning of the label (no range VALUES change — purely how each is termed):**
  - **fixed** — a literal, unmodifiable number, nothing added. Example: `range: 1`.
  - Entries that currently say "Fixed N; add X% inherited Bonus Skill Range" are NOT fixed — they are a computed
    range and should be written transparently, e.g. `range: 4 + 100% × Bonus Skill Range`.
  - **weapon** — range derived from the equipped weapon's range profile (the "inherit weapon range" / "normal
    legal reach" entries).

**Explicit scope limit (user, 2026-10-22):** "no need to change any these formulas. my only concern was 'fixed'
being treated is not really fixed." → Do NOT change any range values or formulas. Do NOT reclassify stat-formula
ranges (Blink, Fated Escape, Opportunist's Step) or self/caster-origin skills as part of this — those were raised
by the Simulator and are NOT being decided. The only deliverable is: stop labeling BSR-adding ranges as "fixed."

**Simulator note:** This is a labeling/documentation fix. If the live range-parsing code keys off the word
"Fixed", the Designer should confirm the rename does not change how any range is computed — values stay identical.

---
*(more skills to be appended as the review continues)*

## 13. HEALS & SHIELDS — reviewed, NO CHANGE (+ Sanctify flag corrected)

**Heals (output as % of target Max HP, Human+Sword ref, L99):** Healing Light 26% and Field Dressing 26%
(single-target); Consecrate 13% and Mending Rain 12% (AOE, ~half per-head — correct AOE discount); Purge 7%
(cleanse — heal is a conditional bonus per debuff removed, not the point). All scale gently and stably across
L1–L300. HEALTHY, no change. (A dedicated INT/VIT healer race shifts these up materially; Sword is a mid ref.)

**Shields (shield HP as % of target Max HP, L99):** Vital Barrier 23% (VIT-scaling, strongest single-target,
→35% by L300); Arcane Barrier 20%; Weapon Ward 19%; Bastion 16%; Bulwark (AOE) 13%; Retribution (reactive
thorns) 13%. Sensible single-target > AOE/reactive split. HEALTHY, no change.

**SANCTIFY (SKL-SANCTIFY) — earlier "broken-low heal" flag CORRECTED, NO CHANGE.** The agent first flagged
Sanctify as the weakest heal (INT×0.30 → only ~4% Max HP at L99, highest MP at 10). That was the WRONG LENS
(rule 3): Sanctify is a TEAM OFFENSIVE BUFF, not a heal. Its payload is Blessed (elements_statuses id 80 =
Final Hit Quality +0.25 ≈ +25% final damage per hit) applied to ALL allies in its 3×3 Impact pattern for 2
turns, plus a small heal and Undead damage (50% of heal). The 4% heal is a correct side-effect, not a defect.
Instant cast, 10 MP, must cluster allies near caster → reasonably priced. NO CHANGE.

**Watch (not a flag): Sanctify vs Benediction overlap.** Benediction also applies Blessed — for the full 4
turns AND Enlightened (+10% all stats, id 82) — so it is the stronger buff-bundle; Sanctify's distinction is
instant + heal + Undead damage + its 2-turn Blessed. Real differentiation, but whether 2-turn Blessed + 4% heal
justifies Sanctify's slot next to Benediction is worth the Designer's eye. Benediction full cost not pulled;
not called here. (Note: Sanctify is a NULL-cast skill = instant, legitimate per rule #9a, not a blocker.)

**Design-vs-code caveat (rule 4):** heal/shield POWER values here are DESIGN intent. Known history — shield
skills were at one point miscalculated as attacks (KG, 2026-10-05) and the Power_Formula evaluator is a
confirmed gap — means correct in-game EVALUATION is a Tester/Auditor matter, separate from these design verdicts.

## 12. MP ECONOMY — loop-risk test — NO CHANGE (no unbounded loop)

**Skills:** DOC-ARCANIST-01 (Mana Surge), DOC-ASCETIC-01 (Meditate), SKL-ARCANE-RENEWAL (Arcane Renewal),
plus checked: SKL-SIPHON-PULSE, SKL-MANA-SCORCH, SKL-SEAL-OF-SILENCE. Tested per the mandate's unbounded-value area.

**Verdict (Simulator, 2026-10-22): NO infinite-MP loop. MP economy is healthy. NO change.**

**Raw MP is net-positive but that is NOT the loop:** Arcane Renewal nets ~+25% Max MP per cast (restores ~30%,
costs ~5%), Mana Surge +20% (0 cost), Meditate +15% (0 cost). BUT each is a STANDALONE cast consuming 1 AP + RT +
channel and doing nothing else. "Infinite MP" is therefore paid in ACTIONS — a turn refilling is a turn not
attacking — so sustained casting caps offensive tempo. Infinite MP ≠ infinite DPS; the AP opportunity cost is the
limiter (same action-economy lever as the knockback/counter findings).

**Two hard ceilings close it:** (1) refunds cannot exceed Max MP (no overflow banking); (2) NO skill refunds MP as
a free rider on a damage action — every MP restore is a standalone cast. Siphon Pulse drains HP (not MP) from its
damage; Mana Scorch / Seal of Silence attack the ENEMY's MP, they do not refuel the caster. So no damage+refuel
single-action engine exists.

**Design note (watch, not fix):** Arcane Renewal is the strongest pure sustain (more net MP than Meditate; its
restore spreads over 1200 CT so it can be cast once and left running). Mana Surge (adds Skill Potency +10% buff)
and Meditate (ally-targetable + Debuff Resistance) justify themselves via riders, so not pure redundancy — but if
those riders are ever judged too weak, the three could converge to "just cast Arcane Renewal." Monitor; no change now.

## 11. COUNTER STANCES — loop-risk test — NO CHANGE (design sound)

**Skills:** SKL-COUNTER-STANCE (Counter Stance, general-pool), DOC-DUELIST-01 (Riposte Stance, Duelist),
DOC-TRICKSTER-01 (Misdirection). Tested per the core mandate's "highest-risk: unbounded value / loops."

**Verdict (Simulator, 2026-10-22): NOT unbounded, RT balancer works, NO balance change recommended.**

**Loop is closed (from DB records):**
  - TRG-005: a counter never triggers another counter → no infinite recursion.
  - TRG-004: at most ONE counter per attacking action (multi-hit / AOE provokes once) → no multi-hit abuse.
  - Duration 1000 CT, does not stack with itself or the other stance → bounded window.
  - Trigger gate: enemy attack dealing direct damage >0 to the holder, attacker in holder's weapon reach,
    holder still standing; zero-damage/status-only skills do NOT provoke.

**The "no count limit" RT balancer is mathematically sound (the key finding):** each counter adds a full
Basic Attack RT to the holder's own timeline — the same RT a normal basic attack costs — but deals only
0.60× (Counter Stance) / 0.85× (Riposte) of a basic attack. So per unit of timeline, countering yields
~40% (Counter) / ~76% (Riposte) of a normal attack's damage-per-RT (consistent across all level bands L1–L300).
Countering is therefore RT-INEFFICIENT vs just attacking — the reactive "free" damage is paid for at a premium
by the RT pushback. This correctly makes the stance a defensive/reactive posture (punish aggression without
spending AP or positioning), not a damage engine. The old hard count-cap was unnecessary; RT self-limits it.

**Premium-vs-budget split is clean:** Riposte 0.85× + 50% Weapon RT Delay, Duelist-only, RT 60+0.25L / MP 5+;
Counter Stance 0.60× + 30% Weapon RT Delay, general-pool, cheaper (RT 50+0.15L / MP 3+). Intended.
Misdirection: single trigger, consumed on first eligible redirect, cannot redirect AOE/reactions → trivially bounded, fine.

**Caveat (NOT the Simulator's lane):** this verdict is about the DESIGN. Correct CODE implementation of the
RT-add balancer and trigger gates has a contested history (counter trigger-scope defect B2-1; Fix-3 regression,
early Oct 2026) that is the Tester/Auditor's domain and has had UAT passes. Not re-opened here.

## 10. SKL-POWER-STRIKE — Power Strike — reviewed, NO CHANGE (agent self-correction)

**Decision (user + agent, 2026-10-22):** No change. Power Strike is the reliable baseline single-target nuke
(1.25×, instant, weapon-range/pattern inheritance, ratio 1.64 @L99) and is correctly priced.

**Agent self-correction:** The agent initially flagged Power Strike as the one top-ratio skill with "no hidden
cost" / possibly "quietly dominant." That was WRONG on two counts, caught by the user:
  1. It DOES pay MP — MP_Cost_Formula round(3 + 0.08×(L-1)) = 3 MP @L1 → 27 @L300, ~12–14% of max MP per cast
     (cheapest MP tier, same as Fire Bolt/Hamstring/Blink). Since in-battle MP regen never sustains skill-spam
     (per-battle budget), this self-limits Power Strike to ~7–8 casts per battle — a real cost.
  2. MP was never "hidden" from the ratio metric — the ratio-vs-basic-attack throughput ALREADY includes MP. So
     its 1.64 already reflects the MP cost. (HP cost and positioning are the only off-metric currencies; MP is on-metric.)
  Conclusion: Power Strike pays RT ×1.25 AND a real MP budget, both reflected in its ratio. No dominance problem.

**Clears the top-ratio group:** with the cost taxonomy (#9b) applied correctly, every high-ratio single-target
skill pays for its output — on-metric (Power Strike RT+MP) or deliberate off-metric substitution (Blood Price HP,
Skyfall Lance positioning + RT ×1.40, Reckless Charge current-HP + RT ×1.50, Decimating Swing 2H + channel).
None flagged as overpowered.

## 9. COST-MODEL CLARIFICATIONS (user principles, 2026-10-22) + Skyfall Lance / Holy Smite

**9a. NULL Channel/Activation is NOT a blocker (corrects the 2026-10-21 audit).** User principle: not all
skills are meant to have channel time or cast delay — especially gap-closers, which SHOULD be instant. A blank
(NULL) Channel_Time / Activation_Time = "no channel / no cast delay" = instant, a legitimate design state. The
2026-10-21 audit's Section 1 listed 7 NULL-cast skills (Empowering Aura, Skyfall Lance, Dragon Dive, Holy Smite,
Sanctify, Barrage, Nature's Grasp) as "blockers … ratios are upper bounds" — that framing was TOO STRONG. The
simulation already modeled them as instant (0/0), so those ratios are ACCURATE for any skill meant to be instant.
NULL cannot by itself distinguish "designed instant" from "never filled in" — that is a per-skill Designer call —
but it is not a simulation blocker and does not inflate the ratio.

**9b. Cost taxonomy — a high damage ratio is not automatically overpowered.** User principle: skill cost comes
in various forms; the most common are RT cost, MP, channel time, and cast delay. A skill with 0 MP / 0 channel is
NOT undercosted if it pays another way. Blood Price pays with HP (15% Max HP) precisely because it forgoes the
usual costs. IMPORTANT for the Simulator's method: the ratio-vs-basic-attack metric sees ONLY RT, MP, and cast
time — it is BLIND to HP cost, self-damage, and positioning/exposure cost. Weigh those separately; do not flag a
skill as OP on ratio alone when it pays in a currency the metric cannot see.

**9c. Skyfall Lance (SKL-SKYFALL-LANCE) — reviewed, NO CHANGE.** Instant by design (gap-closer; NULL cast is
correct). Ratio 1.68 (L99) is accurate, not an upper bound. It is NOT undercosted: pays via RT ×1.40 (high),
Melee/Jump-only, requires a valid unoccupied adjacent landing tile (fails at validation otherwise), and the +20%
elevation bonus is conditional on terrain. A priced gap-closer, not a dominance problem.

**9d. Holy Smite (SKL-HOLY-SMITE) — reviewed, NO CHANGE.** Instant ranged Holy nuke, moderate 1.15× (ratio 1.47
accurate). Value is Holy element interaction (2× vs Undead, Templar passive), not raw damage. Range already
written transparently as "Weapon Range + Bonus Skill Range" (already matches the #2 terminology convention). Not
flagged.

## 8. WIND ELEMENT — 5 CLONE-DONOR SKILLS (input to the ongoing Wind design)

**Decision (user, 2026-10-22):** Keep the recommended Wind clone slate below. Create 5 Wind skills by cloning
existing elemental donor skills and retagging to Wind, rather than inventing from scratch.

**Coordination note (IMPORTANT):** Wind is already being designed in ANOTHER chat session, where its identity is
confirmed as a DISPLACEMENT element with a guaranteed ≥1 tile knockback. This slate is INPUT to that work, NOT a
competing spec. The Designer should reconcile these clones with the Wind identity being authored there, so there
is only ONE Wind definition. (Wind is NOT yet a defined element in elements_statuses as of this session — roster
is Physical, Fire, Water, Ice, Poison, Dark, Holy, Electric; the other session is adding it.)

**The 5 donor skills (clone → retag Wind; knockback comes from the element identity, not a per-skill rider):**
  1. **Fire Bolt** → clean instant single-target Wind nuke (range 4, 1.10×). Reliable single-target shove (ranged
     knockback floor keeps ≥1 tile).
  2. **Pyroclasm** → Line 5 AOE gust; pushes the whole line back.
  3. **Thunderclap** → caster-origin Circle r3 burst; shoves all surrounding enemies outward (signature Wind combo
     with hazards/edges).
  4. **Gale Thrust** → PRIORITY / near-free conversion: it is ALREADY a Physical Cone 3 with Force-based knockback
     and literally "Gale" in its name. Designer should decide RETAG-IN-PLACE vs clone. Most natural Wind skill in
     the catalog.
  5. **Static Field** → Ring r2 movement-hampering zone (movement-RT slow); already wind-like, optional ≥1 push.

  Slate covers a full element kit: single-target nuke, line AOE, caster-burst AOE, melee cone, control/zone.
  Deliberately avoided chain skills (not thematically wind) and Earth/Petrify donors (off-theme).

**CRITICAL pricing input — action-economy value of knockback (Simulator, corrected 2026-10-22):**
  A guaranteed 1-tile knockback on an in-range STANDARD enemy (2 AP, no cooldowns) is NOT a minor RT tax (~5%);
  it DENIES ~50% of that enemy's turn. Baseline in-range enemy = 2 attacks (2 AP). Pushed 1 tile, it must spend
  1 AP to re-approach + 1 AP to attack = only 1 attack → one full attack denied (~50% offense). If it had already
  spent an AP, the forced move eats its last AP → 100% denied that turn. Per FFT-lesson (reference_games.md),
  action/turn denial is the STRONGEST lever in a CT system — stronger than raw damage.
  Mitigations that keep it fair (natural counters, not nerfs): reach-2 (spear) or ranged targets stay in range
  after a 1-tile push (pay only ~5% RT, no AP); bosses (3 AP) lose 33% not 50% and have knockback resistance;
  positioning (walls/edges/max-reach) counters it.
  DESIGN IMPLICATION for the Wind clones: price GUARANTEED knockback as a premium CONTROL effect, not a free
  damage rider. Keep per-hit / repeatable pushers low-damage and/or higher-RT so the tempo denial IS the payment;
  reserve multi-target push (Pyroclasm/Thunderclap clones) for higher-cost skills. Avoid cheap + guaranteed +
  repeatable displacement — that is where Wind tips into overpowered.

**Boundary:** Simulator picked donors and quantified the tempo value (analysis). DEFINING Wind and AUTHORING these
into the DB is the Designer's job, coordinated with the other session's Wind work.

## 7. SKL-CRUSHING-ADVANCE — Crushing Advance — CONFIRMED, NO CHANGE

**Decision (user, 2026-10-22):** Leave as-is. Although it reads borderline on the raw damage ratio (1.01 vs basic
attack at L99, channel 100 + RT ×1.50 for a 1.10× hit), its Knockback rider is NOT a weak add-on. Rationale
(user): knockback is a serious effect in CTRBLXAI — it combos with the environment (hazard tiles, collisions)
and can trigger fall damage (forced downward displacement of 3+ elevation). The damage ratio does not price that
positioning/tempo value. No change.

## 6. MULTI-HIT SKILLS — DECISION DEFERRED (blocked on a code fix)

**Status:** NO design decision made. Deferred — do NOT hand a multi-hit rebalance to the Designer yet.

**Skills in scope:** SKL-STORM-BARRAGE, SKL-TWIN-FANGS, SKL-FLURRY-OF-BLADES, SKL-BARRAGE,
SKL-RAPID-ASSAULT, DOC-TWINBLADE-02 (any "N sequential hits" skill).

**Why deferred — two confirmed CODE gaps (Tester CTRBLXAI, re-verified 2026-10-22, UNWIRED; thread
thread-d84dd532a3d6; handoff at workspace/artifacts/UAT_weapon_native_passive_rechECK_2026-10-22.md):**
  1. NO PER-HIT LOOP. Runtime GameConstants.SKILLS entries carry only a single `power` multiplier and NO
     hit-count field. Multi-hit skills currently resolve as ONE ResolveSkill→ApplyOutcome call at the PER-HIT
     multiplier. The hit counts live only in SkillData prose. So in-game each "multi-hit" skill lands ONE hit.
  2. NO NATIVE-PASSIVE PROC. A weapon's native on-hit passive (Venomous/Backstab/Ignite/Piercing Edge) is data
     only — never triggered on a basic attack or on skill hits. The per-hit proc that is supposed to justify the
     multi-hit archetype does not exist.

**Simulator-measured CURRENT in-game effect (Human+Sword ref, ratio vs basic attack, L99):**
  Storm Barrage 0.21 (design intent 0.63) · Flurry 0.24 (intent 0.96) · Barrage 0.24 (intent 0.96) ·
  Twin Fangs 0.60 (intent 1.20) · Rapid Assault 0.23 (intent 0.46). Live skills are 2–4× WORSE than the
  original audit's "weak" ratios because only one hit of N actually lands. This is a CODE DEFECT, not a balance
  state — it belongs to the Dev/Coder handoff (Tester already produced it), NOT to this Designer rebalance log.

**Decision sequence (user to confirm):** (1) Dev builds the per-hit loop + native-passive trigger; (2) THEN the
Simulator re-runs the multi-hit defense-penalty analysis on skills that actually multi-hit; (3) THEN decide the
design fix (candidates were: per-skill multiplier compensation / defense-once-on-total + renormalize / per-hit
defense discount). Deciding now would tune numbers against behavior that is about to change. NO multiplier or
formula change recorded.

**Related (earlier in this log):** the per-hit defense penalty itself (harmonic Effective Defense subtracted per
hit → multi-hit loses 40–63% of nominal damage) is a real DESIGN question, but it only becomes testable once the
per-hit loop exists. Hemorrhage (#5) is unaffected — it is single-hit and already confirmed no-change.

## 5. SKL-HEMORRHAGE — Hemorrhage — CONFIRMED, NO CHANGE

**Decision (user, 2026-10-22):** Leave as-is. Hemorrhage is a correctly-designed CONDITIONAL skill, not a weak
outlier. Base 0.60× is intentionally low; it is a Bleed-exploiter — vs a Bleeding target it deals 0.90× AND
triggers Bleed's own bonus-damage proc, and it is cheap (3+ MP), instant (ch0/act0), fast (RT ×1.10), melee,
spammable. Pairs with Rending Slash (Bleed applier). The flat ratio 0.51 vs basic attack is the wrong lens — it
is a combo piece. No change.

## 4. SKL-EARTHEN-LANCE — Earthen Lance

**Changes (user, 2026-10-22):**
  1. `RT_Cost_Formula`: reduce RT cost by **50%** — multiplier **×1.10 → ×0.55**
     (new: `round((Modified Base RT × 0.10 + Effective Weapon WT) × 0.55)`).
  2. `Effects`: ADD **Crippled** debuff application (per elements_statuses id 67: Movement Range −max(2, 50%
     current MR) min 1, Jump −max(1, 50% current Jump) min 0, 5 turns, refresh-duration on reapply).
  3. Multiplier (1.00×), Channel (100), Activation (0), MP, range (Fixed 5 + 100% BSR, min 2, LoS): UNCHANGED.

**Decided by:** user, 2026-10-22.

**Rationale:** Earthen Lance was flagged as mispriced (clean 1.00× ranged nuke paying channel + RT with no rider,
dominated by instant Fire Bolt at 1.44). The RT cut + Crippled rider gives it a distinct ranged-control identity
(kite: strike from range 5, cut target movement, repeat).

**Simulator-measured effect (Human + Sword reference, ratio vs basic attack):**
  - L99: 0.95 → 1.09 (skill RT 107 → 53). At/above parity from L99 up (L300 1.26 → 1.43). Still below Fire Bolt
    (1.44) on PURE damage — but the Crippled rider is control, which the damage ratio does NOT price, so true
    value is higher. Becomes a ranged control-nuke, not a flat damage skill.

**Simulator cautions for Designer:**
  - HAMSTRING IS NOT OVERSHADOWED (corrected 2026-10-22 per user): an earlier draft flagged Earthen Lance as
    power-creeping Hamstring. That was WRONG. Hamstring (SKL-HAMSTRING) and Earthen Lance occupy distinct roles:
    Hamstring is INSTANT (Channel 0 / Activation 0), 0.65×, RT ×0.75, cheapest MP (3+), and WEAPON-ADAPTIVE range
    (inherits the equipped weapon's reach — melee on a melee weapon, full ranged profile on a projectile weapon),
    and can hit adjacent. Earthen Lance is CHANNELED (100 CT, interruptible), 1.00×, RT ×0.55, Earth element,
    Fixed 5 range with MINIMUM range 2 + LoS (cannot hit adjacent). Different delivery, different damage, different
    range class — both are valid Crippled applicators for different builds. No Hamstring change needed.
  - Channel 100 is UNCHANGED (still interruptible) — intentional per user scope (RT + Cripple only). Asymmetric
    with the Longshot decision (#3) which swapped channel→non-interruptible activation. Keeping Earthen Lance
    interruptible preserves counterplay on the cripple.
  - Was already at 0% further rider before; now carries a control debuff. Confirm Crippled duration uses standard
    Debuff Resistance / boss handling (boss control resistance applies).
