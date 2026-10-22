# CTRBLXAI — SKILL BALANCE AUDIT

**Run date:** 2026-10-21  
**Seed:** 42 (deterministic — game has no combat RNG)  
**Formulas loaded:** 34 economy (prior) + 28 combat (this run, see FORMULAS.md)  
**Content simulated:** 110 skills total; 50 priced on the standard damage model; reference unit Human + Sword (1H) vs a median medium-armor defensive baseline  
**Level bands tested:** 1, 25, 50, 99, 150, 199, 250, 300

All formulas were taken from CTRBLXAI.db (core_stats id 2–35 for combat math; each skill's authored Power/MP/RT/Channel/Activation fields from the `skills` table). No Luau source was read. The metric below is **efficiency ratio** = a skill's damage per 1000 CT divided by a basic attack's damage per 1000 CT for the same unit. 1.00 means the skill is exactly as time-efficient as auto-attacking; below 1.00 means auto-attacking does more. RT/Channel/Activation and MP are all included in the time cost.

---
## SECTION 1 — BLOCKERS

These prevented complete simulation and need a database value before the skill can be priced:

**7 skills have NULL Channel_Time / Activation_Time** (the field is empty, not 0 — so the real cast cost is unknown). They were simulated as if 0/0, which flatters them; treat their ratios as upper bounds:
- `SKL-EMPOWERING-AURA` (Channel=None, Activation=None)
- `SKL-SKYFALL-LANCE` (Channel=None, Activation=None)
- `SKL-DRAGON-DIVE` (Channel=None, Activation=1)
- `SKL-HOLY-SMITE` (Channel=None, Activation=None)
- `SKL-SANCTIFY` (Channel=None, Activation=None)
- `SKL-BARRAGE` (Channel=None, Activation=None)
- `SKL-NATURES-GRASP` (Channel=None, Activation=None)

**6 damage-tagged skills use non-standard Power formulas** not on the `Weapon Attack Power × N × Skill Potency` model, so they are reported but not given a comparable ratio: `SKL-DARK-RESTORATION`, `SKL-LUCKY-STRIKE`, `DOC-TWINBLADE-01`, `DOC-TWINBLADE-02`, `SKL-RETRIBUTION-SHELL`, `SKL-SUMMON-TURRET`. These need a separate pricing pass (dual-wield and summon models especially).

---
## SECTION 2 — CRITICAL FINDINGS

### C1. Blood Price — highest single-target damage AND zero MP
**Finding:** `SKL-BLOOD-PRICE` is the single strongest damage skill in the game (ratio 2.25 — 2.25× a basic attack) and costs **0 MP**, so it has no resource gate at all. Its only cost is 15% current-HP self-damage.  
**Evidence:** ratio across bands 1.92 | 2.03 | 2.06 | 2.25 | 2.47 | 2.60 | 2.77 | 2.88 (L1→L300). 0 MP means it is repeatable every turn within AP limits; damage scales up with level while the HP cost is a flat %.  
**Level band:** all bands; worst at high level where lifesteal/healing can refund the HP cost.  
**Severity:** With any healing or Vampirism-style sustain, the self-cost is neutralized and this becomes a no-drawback 2.25× nuke. Highest-priority review.

### C2. Channeled single-target nukes are dominated by instant ones (the Longshot problem you flagged)
**Finding:** `SKL-LONGSHOT` pays **185 CT** of channel+activation for ratio 1.10, while `SKL-FIRE-BOLT` pays **0 CT** for ratio 1.44. The instant skill does ~30% more effective damage AND is interrupt-proof AND frees the caster sooner. The channel is pure downside.  
**Evidence:** Longshot 0.90 | 0.95 | 0.98 | 1.10 | 1.22 | 1.31 | 1.38 | 1.45 vs Fire Bolt 1.17 | 1.31 | 1.33 | 1.44 | 1.59 | 1.69 | 1.78 | 1.87 (L1→L300). The gap never closes.  
**Level band:** all bands.  
**Severity:** This is systemic, not one skill — see Section 3. Channel/Activation time is currently charged with no compensating power premium, so every channeled skill is strictly worse than an instant one of equal or lower multiplier.

---
## SECTION 3 — CURVE ANALYSIS

Efficiency ratio vs basic attack, per band. Columns: L1 | L25 | L50 | L99 | L150 | L199 | L250 | L300

| Skill | mult | L1 | L25 | L50 | L99 | L150 | L199 | L250 | L300 | class |
|---|---|---|---|---|---|---|---|---|---|---|
| SKL-IGNITE-GROUND | 0.50 | 0.19 | 0.18 | 0.20 | 0.22 | 0.24 | 0.27 | 0.28 | 0.30 | AOE x9 |
| SKL-TIDAL-CRASH | 0.70 | 0.21 | 0.27 | 0.28 | 0.32 | 0.35 | 0.37 | 0.39 | 0.43 | AOE x5 |
| SKL-SIPHON-PULSE | 0.60 | 0.30 | 0.28 | 0.28 | 0.33 | 0.36 | 0.41 | 0.43 | 0.46 | AOE x8 |
| SKL-PRECISE-DISARM | 0.60 | 0.32 | 0.31 | 0.31 | 0.37 | 0.40 | 0.45 | 0.47 | 0.51 | single |
| SKL-FISSURE-LINE | 0.75 | 0.31 | 0.33 | 0.33 | 0.38 | 0.42 | 0.44 | 0.47 | 0.48 | AOE x4 |
| SKL-TOXIC-NEEDLE | 0.50 | 0.34 | 0.32 | 0.35 | 0.38 | 0.43 | 0.47 | 0.51 | 0.54 | single |
| SKL-GLACIAL-WAVE | 0.75 | 0.34 | 0.37 | 0.36 | 0.42 | 0.47 | 0.50 | 0.54 | 0.55 | AOE x3 |
| SKL-RAPID-ASSAULT | 0.45 | 0.46 | 0.43 | 0.40 | 0.46 | 0.49 | 0.56 | 0.57 | 0.63 | single |
| SKL-PYROCLASM | 0.85 | 0.38 | 0.41 | 0.41 | 0.49 | 0.52 | 0.56 | 0.60 | 0.63 | AOE x5 |
| SKL-THUNDERCLAP | 0.75 | 0.41 | 0.43 | 0.43 | 0.50 | 0.56 | 0.60 | 0.65 | 0.68 | AOE x9 |
| SKL-HEMORRHAGE | 0.60 | 0.49 | 0.45 | 0.43 | 0.51 | 0.54 | 0.60 | 0.63 | 0.68 | single |
| SKL-FROSTBIND | 0.70 | 0.38 | 0.49 | 0.50 | 0.57 | 0.62 | 0.67 | 0.71 | 0.77 | single |
| DOC-THIEF-01 | 0.75 | 0.49 | 0.52 | 0.51 | 0.60 | 0.67 | 0.71 | 0.77 | 0.80 | single |
| SKL-VENOM-BURST | 0.70 | 0.46 | 0.56 | 0.55 | 0.61 | 0.66 | 0.71 | 0.75 | 0.82 | AOE x8 |
| SKL-MANA-SCORCH | 0.80 | 0.47 | 0.56 | 0.57 | 0.63 | 0.70 | 0.76 | 0.81 | 0.86 | single |
| SKL-STORM-BARRAGE | 0.45 | 0.61 | 0.58 | 0.53 | 0.63 | 0.66 | 0.76 | 0.78 | 0.86 | single |
| SKL-HAMSTRING | 0.65 | 0.53 | 0.58 | 0.60 | 0.65 | 0.72 | 0.74 | 0.80 | 0.85 | single |
| SKL-CHAIN-SPARK | 0.80 | 0.49 | 0.58 | 0.60 | 0.66 | 0.73 | 0.79 | 0.85 | 0.90 | AOE x3 |
| SKL-SHATTER-POINT | 1.00 | 0.53 | 0.60 | 0.63 | 0.72 | 0.80 | 0.86 | 0.93 | 0.97 | single |
| DOC-RANGER-01 | 0.75 | 0.67 | 0.69 | 0.67 | 0.76 | 0.85 | 0.90 | 0.97 | 1.00 | single |
| SKL-GALE-THRUST | 0.80 | 0.62 | 0.70 | 0.71 | 0.76 | 0.84 | 0.91 | 0.97 | 1.02 | AOE x6 |
| SKL-VOLTAIC-CHAIN | 0.90 | 0.60 | 0.68 | 0.71 | 0.80 | 0.88 | 0.94 | 1.01 | 1.07 | AOE x3 |
| SKL-METEOR-MARKER | 1.50 | 0.60 | 0.70 | 0.72 | 0.81 | 0.89 | 0.94 | 1.00 | 1.04 | AOE x9 |
| SKL-RECOIL-SHOT | 0.80 | 0.65 | 0.75 | 0.76 | 0.82 | 0.90 | 0.97 | 1.04 | 1.09 | single |
| SKL-CRIPPLING-SHOT | 0.80 | 0.67 | 0.77 | 0.78 | 0.84 | 0.93 | 1.00 | 1.07 | 1.12 | single |
| SKL-BARRAGE | 0.40 | 0.60 | 0.81 | 0.78 | 0.84 | 0.90 | 1.09 | 1.13 | 1.17 | single |
| SKL-SHADOW-RAKE | 0.85 | 0.77 | 0.77 | 0.76 | 0.87 | 0.94 | 1.00 | 1.09 | 1.13 | AOE x3 |
| SKL-SWEEPING-CUT | 0.90 | 0.75 | 0.81 | 0.83 | 0.91 | 1.00 | 1.06 | 1.13 | 1.20 | AOE x3 |
| SKL-FLURRY-OF-BLADES | 0.40 | 0.64 | 0.88 | 0.84 | 0.91 | 0.98 | 1.17 | 1.22 | 1.26 | single |
| SKL-EXECUTION-STROKE | 1.40 | 0.73 | 0.80 | 0.82 | 0.92 | 1.01 | 1.07 | 1.15 | 1.21 | single |
| SKL-EARTHEN-LANCE | 1.00 | 0.72 | 0.80 | 0.83 | 0.95 | 1.05 | 1.12 | 1.21 | 1.26 | single |
| SKL-NULL-STRIKE | 0.90 | 0.81 | 0.89 | 0.91 | 1.00 | 1.10 | 1.16 | 1.24 | 1.31 | single |
| SKL-CRUSHING-ADVANCE | 1.10 | 0.79 | 0.90 | 0.92 | 1.01 | 1.13 | 1.20 | 1.27 | 1.36 | single |
| SKL-RENDING-SLASH | 0.95 | 0.98 | 0.97 | 0.97 | 1.09 | 1.22 | 1.27 | 1.38 | 1.44 | single |
| SKL-LONGSHOT | 1.30 | 0.90 | 0.95 | 0.98 | 1.10 | 1.22 | 1.31 | 1.38 | 1.45 | single |
| SKL-TWIN-FANGS | 0.65 | 0.94 | 1.00 | 1.03 | 1.10 | 1.23 | 1.27 | 1.37 | 1.45 | single |
| SKL-SHATTER-BLOW | 1.00 | 0.94 | 1.00 | 1.03 | 1.14 | 1.26 | 1.33 | 1.43 | 1.48 | single |
| SKL-LUNGE | 1.00 | 0.96 | 1.02 | 1.05 | 1.17 | 1.29 | 1.37 | 1.47 | 1.52 | single |
| SKL-DRAGON-DIVE | 1.10 | 1.03 | 1.12 | 1.14 | 1.22 | 1.35 | 1.44 | 1.52 | 1.61 | AOE x5 |
| SKL-TORRENT-SPEAR | 1.10 | 0.97 | 1.10 | 1.13 | 1.23 | 1.37 | 1.46 | 1.54 | 1.63 | single |
| DOC-SPELLBLADE-01 | 1.00 | 1.00 | 1.08 | 1.11 | 1.24 | 1.37 | 1.45 | 1.55 | 1.60 | single |
| SKL-IGNITION-LANCE | 1.40 | 0.99 | 1.08 | 1.11 | 1.25 | 1.39 | 1.47 | 1.59 | 1.67 | single |
| DOC-JUGGERNAUT-01 | 1.75 | 1.14 | 1.20 | 1.23 | 1.39 | 1.52 | 1.62 | 1.73 | 1.81 | single |
| SKL-FIRE-BOLT | 1.10 | 1.17 | 1.31 | 1.33 | 1.44 | 1.59 | 1.69 | 1.78 | 1.87 | single |
| DOC-BERSERKER-01 | 1.20 | 1.35 | 1.29 | 1.31 | 1.46 | 1.58 | 1.69 | 1.81 | 1.89 | single |
| SKL-HOLY-SMITE | 1.15 | 1.28 | 1.31 | 1.32 | 1.47 | 1.61 | 1.70 | 1.83 | 1.89 | single |
| SKL-DECIMATING-SWING | 1.50 | 1.33 | 1.45 | 1.47 | 1.62 | 1.80 | 1.90 | 2.05 | 2.15 | AOE x3 |
| SKL-POWER-STRIKE | 1.25 | 1.42 | 1.51 | 1.51 | 1.64 | 1.79 | 1.93 | 2.05 | 2.12 | single |
| SKL-SKYFALL-LANCE | 1.30 | 1.53 | 1.53 | 1.55 | 1.68 | 1.85 | 1.98 | 2.09 | 2.18 | single |
| SKL-BLOOD-PRICE | 1.40 | 1.92 | 2.03 | 2.06 | 2.25 | 2.47 | 2.60 | 2.77 | 2.88 | single |

**Trend:** no curve inverts or breaks — every skill holds or *rises* vs basic attack as level climbs (mean ratio L1=0.74 → L99=0.90 → L300=1.19). Skills drift up ~32% by L300 because Skill Potency (INT) keeps growing while basic attacks don't benefit from it. This is mild and uniform, not a break, but it means skills slowly out-scale auto-attacking — watch it if INT growth is ever raised.

**Channeling/Activation tax (L99), worst first:** the skills below pay large non-RT time with no power offset — this is the single clearest mispricing pattern:
- `SKL-METEOR-MARKER` +580 CT → ratio 0.81 (AOE ×9)
- `SKL-TIDAL-CRASH` +335 CT → ratio 0.32 (AOE ×5)
- `SKL-EXECUTION-STROKE` +330 CT → ratio 0.92 (single-target)
- `SKL-FISSURE-LINE` +300 CT → ratio 0.38 (AOE ×4)
- `SKL-PYROCLASM` +290 CT → ratio 0.49 (AOE ×5)
- `DOC-JUGGERNAUT-01` +280 CT → ratio 1.39 (single-target)
- `SKL-GLACIAL-WAVE` +240 CT → ratio 0.42 (AOE ×3)
- `SKL-IGNITE-GROUND` +200 CT → ratio 0.22 (AOE ×9)
- `SKL-LONGSHOT` +185 CT → ratio 1.10 (single-target)
- `SKL-IGNITION-LANCE` +180 CT → ratio 1.25 (single-target)

---
## SECTION 4 — OUTLIERS

Judged by simulated combat outcome, never by BP. AOE skills are judged on *filled* value (ratio × nominal max targets); a low per-target ratio is correct design for a wide skill, so those are NOT weak.

| Skill | Class | Wins on | Loses on | Evidence (L99) |
|---|---|---|---|---|
| SKL-BLOOD-PRICE | **DOMINANT** | single-target DPS + 0 MP | self-HP cost (refundable) | ratio 2.25, 0 MP |
| SKL-SKYFALL-LANCE | DOMINANT (single) | raw single-target | NULL cast cost (blocker C/§1) | ratio 1.68, cost unknown |
| SKL-POWER-STRIKE | strong (single) | reliable instant nuke | nothing significant | ratio 1.64, 0 channel |
| SKL-METEOR-MARKER | DOMINANT (AOE) | 9-tile fill = 7.3× | 580 CT cast, telegraphed | ratio 0.81 ×9 |
| SKL-DRAGON-DIVE | strong (AOE) | 5-tile fill = 6.1× + gap-close | NULL-ish cast (act=1) | ratio 1.22 ×5 |
| SKL-RAPID-ASSAULT | **TRASH** | nothing at Human AGI | worst single-target in game | ratio 0.46 |
| SKL-HEMORRHAGE | **TRASH** (cond.) | only if target pre-Bleed | no Bleed = 0.51 | ratio 0.51 |
| SKL-STORM-BARRAGE | **TRASH** | 3-hit flavor | 0.45/hit too low, single-target | ratio 0.63 |
| DOC-THIEF-01 | NICHE | the Steal rider | damage is 0.60 | ratio 0.60 + steal |
| SKL-TOXIC-NEEDLE / FROSTBIND / PRECISE-DISARM | NICHE (control) | the debuff/disable | low raw damage by design | 0.38 / 0.57 / 0.37 |

**Weak (genuine, single-target pure damage under 0.70 with no AOE or control to justify it):** `SKL-RAPID-ASSAULT` (0.46), `SKL-HEMORRHAGE` (0.51), `DOC-THIEF-01` (0.60), `SKL-STORM-BARRAGE` (0.63). `SKL-RAPID-ASSAULT` is the clearest trash-tier: at Human AGI it lands only 2 hits at 0.45× each; it needs AGI ≥ 200 (4 hits) just to approach parity, so it is only ever playable on the fastest races.

**Dominant:** `SKL-BLOOD-PRICE` (see C1). On the AOE side `SKL-METEOR-MARKER` reaches 7.3× filled but pays 580 CT and is telegraphed, which is acceptable counterplay — monitor, don't panic.

**Redundant:** the single-target Physical nukes form one long unbroken ladder from 0.46 to 1.68 in ~0.1 steps (20+ skills). Many are mechanically identical except for a different debuff rider; `SKL-TWIN-FANGS` (1.10) and `SKL-LONGSHOT` (1.10) are numerically identical in output, as are `SKL-NULL-STRIKE` (1.00)/`SKL-CRUSHING-ADVANCE` (1.01). This is healthy *if* the debuff riders differentiate them; it is redundant where they don't.

---
## SECTION 5 — COMBINATIONS / ECONOMY

**MP economy:** Max MP = 20 + INT×2; MP Regen = 2 + floor(INT/40) per 1000 CT. Even at L300 (INT 99) regen is only 4 MP / 1000 CT while a mid-cost skill is 5–8 MP per cast. **MP is a per-battle budget, not a renewable resource** — in-battle regen never sustains skill-spam. Implication: the balance lever on repeatable skills is RT + Channel, not MP. That makes the three **0-MP skills** the ones to watch: `DOC-ARCANIST-01`, `DOC-ASCETIC-01` (both MP-refuel utilities) and `SKL-BLOOD-PRICE` (a damage skill — see C1).

**Action economy:** 2 AP/turn, all skills 1 AP, no cooldowns (core_stats id 16). The only gates are RT, MP and Channel. Blood Price defeats two of the three (0 MP, no channel), leaving only RT — which is why it tops the chart. No unbounded loop was found among priced skills, but Blood Price + any lifesteal is the closest thing to one and should be checked once summon/lifesteal systems are wired.

---
## SECTION 6 — HEALTHY (do not spend time here)

- **Instant single-target Physical nukes** cluster sensibly around 1.0–1.7 (`SKL-POWER-STRIKE` 1.64, `SKL-SHATTER-BLOW` 1.14, `SKL-LUNGE` 1.17, `SKL-RENDING-SLASH` 1.09). These are correctly priced.
- **AOE per-target discounts** are appropriate: wide skills sit at 0.3–0.6 per target and reach 2–5× filled, which is the intended trade (`SKL-PYROCLASM`, `SKL-FISSURE-LINE`, `SKL-SHADOW-RAKE`, `SKL-GALE-THRUST`).
- **Curves are stable** across all 8 bands — nothing explodes or collapses between L99 and L300.
- **MP curve** behaves as a clean per-battle budget at every band.

---
## SECTION 7 — DELTA

First dedicated **skill** balance audit. Prior reports covered economy/XP/action-pricing only; FORMULAS.md previously held no combat formulas. This run registers 28 combat formulas with provenance.
- **Resolved:** n/a (baseline)
- **New:** C1 (Blood Price 0-MP nuke), C2 (channeling tax / Longshot), Rapid Assault trash-tier, Wind content gap (below)
- **Values changed in DB since last run:** not compared (no prior skill snapshot)

### Content gap you flagged — Wind
Confirmed from the `skills` table tag census: **0 skills carry a Wind tag.** Element coverage is Fire 6, Ice 4, Water 4, Electric 5, Earth 5, Holy 8, Dark 8, Poison 6, Physical 30 — Wind **0**. Wind is defined as an element but has no skill (and per prior notes, no player access anywhere). This is a design/content gap, not a balance break — flagging it for the Designer; I don't author content.

---
## VERDICT

**2 CRITICAL FINDINGS** — highest priority: `SKL-BLOOD-PRICE` is a 0-MP, no-channel, 2.25× single-target nuke whose only cost (15% HP) is refundable by any healing; and channel/activation time is charged with no power premium, making every channeled skill (Longshot the clearest case) strictly worse than an instant one.

Plus: 7 skills blocked on NULL cast-cost data, 6 on non-standard formulas; Rapid Assault is trash-tier for non-fast races; Wind has zero skills.

*Files written: `sim\reports\` and `sim\FORMULAS.md` only. Source and docs untouched.*