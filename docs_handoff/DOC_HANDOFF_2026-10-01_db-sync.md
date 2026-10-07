# Documenter Hand-off — Code/DB Sync Items

**From:** CTRBLXAI dev session
**Date:** 2026-10-01
**Purpose:** Decisions made in a coding session that intentionally diverge from the game-rules DB (CTRBLXAI.db). Code was changed per the developer's explicit call; the DB (design canon) was NOT touched because docs are read-only outside design sessions. These need a design-session pass to bring canon back in sync with the shipped behavior.

> Note on file location: this hand-off is written OUTSIDE docs\ (docs\ is read-only in coding sessions). The documenter/designer should move or action it from a design session.

---

## ITEM 1 — Frenzy magnitude (DB is silent; code set a value)

- **What the DB says:** `elements_statuses` id 72 (Frenzy) — "Affects Basic Attack tempo only. Does not modify Skill Card RT Cost, MP Cost, Channel Time, or Activation Time..." **No magnitude is specified.**
- **What the code now does:** Frenzy reduces the **base-RT component** of a basic attack by **50%** (`GameConstants.STATUSES.Frenzy.basicAttackRtMult = 0.50`). It does **NOT** reduce the weapon-WT component — only the `round(ModifiedBaseRt × 0.10)` portion is halved; `Effective Weapon WT` is untouched. (Developer decision, 2026-09-26 / reaffirmed this session.)
- **Why it matters:** Because weapon WT is exempt, the real speed-up a unit feels scales with how light its weapon is — light weapons approach the full 50%, heavy weapons gain less. Distinct from Haste (Base RT ×0.90 across all actions).
- **Canon update needed:** Record in `elements_statuses` (Frenzy) that Frenzy reduces the basic-attack base-RT component by 50%, weapon WT exempt. Confirm the 50% is the intended balance value (it was a developer decision, not a DB transcription).

---

## ITEM 2 — Riposte Stance (DOC-DUELIST-01) reworked; DB spec now stale

- **What the DB says (now stale):**
  - Power_Formula: "For 1000 CT, **up to two** eligible Ripostes. Each deals **85% Basic Attack Power** and 50% main-hand Weapon RT Delay; no AP or action RT."
  - Reapplication_Stacking: "**Maximum two Ripostes**"
  - Targeting_Range: "Self; trigger attacker must remain in legal reach"
  - Effects/Special_Rules: "only AP-consuming actively targeted eligible **melee** attack/Skill; no reaction recursion"
- **What the code now does (developer decisions this session):**
  1. **No count limit** — counters EVERY eligible hit for the 1000 CT duration (removed the "max two").
  2. **New balancer replaces the count cap** — each counter ADDS the defender's basic-attack RT to its own `remainingRt` (pushes its next turn later). No AP, no action-RT.
  3. **Reach = equipped-weapon basic-attack range**, not melee-only — respects ranged weapons' min-range and extended reach (e.g. spear reach 2). Implemented by reusing the normal attack-reach check so it always matches a real basic attack.
  4. **Respects weapon pattern incl. Cleave**; **friendly fire applies** (cleave counter can hit allies) — developer confirmed friendly fire acceptable.
  5. Counter damage still **85% Basic Attack Power** (unchanged, transcribed from DB).
  6. **No reaction recursion** — a counter never triggers another counter (preserved from DB intent).
- **Code description already updated:** `SkillData.lua` DOC-DUELIST-01 description/powerFormula/effects/specialRules were rewritten to match the new behavior (developer explicitly asked for the in-code description update). The in-code specialRules carries a note that the DB is not yet synced.
- **Canon update needed:** Update `skills` DOC-DUELIST-01 — remove the "max two" cap, change melee-only → equipped-weapon reach (ranged/spear aware), add the "each counter adds basic-attack RT to the defender" balancer, note weapon-pattern/cleave + friendly fire. Keep 85% power and no-recursion.

---

## ITEM 3 — Counter Stance (SKL-COUNTER-STANCE) converged to the same model

- **What the DB says (now stale):** "Single-use counter (consumed on trigger)", "Counter attack: Weapon Attack Power × 0.60", "Only triggers on direct **melee** attacks from within reach — AOE, ranged, and indirect damage do not trigger."
- **What the code now does:** Same reworked counter mechanic as Riposte Stance (no limit, RT balancer, equipped-weapon reach, weapon pattern, friendly fire, no recursion) but at its **own 60% power** (transcribed from DB). Both skills share one `CounterStance` status; each stamps its own power multiplier (Riposte 0.85, Counter Stance 0.60).
- **Canon update needed:** Update `skills` SKL-COUNTER-STANCE to match the converged model — remove "single-use" and "melee-only", keep 60% power. Decide whether Counter Stance should remain distinct from Riposte in any way (currently only the power multiplier differs).

---

## Not a divergence (checked, no action)
- **Ranged-knockback ×0.5 rule** — the code (`DisplacementService`) already cites the DB formula; code and canon agree. Listed here only to confirm it was reviewed and is NOT a sync item.

---

## Summary table

| Item | DB currently says | Code now does | Canon action |
|------|-------------------|---------------|--------------|
| Frenzy | tempo only, no number | base-RT −50%, WT exempt | add 50% magnitude to elements_statuses |
| Riposte Stance | max 2, melee, 85% | unlimited, weapon-reach, RT balancer, cleave/FF, 85% | rewrite skills row |
| Counter Stance | single-use, melee, 60% | unlimited, weapon-reach, RT balancer, cleave/FF, 60% | rewrite skills row |


---
## STATUS: ACTIONED 2026-10-02 (Designer session)
Items 1-3 synced into CTRBLXAI.db + Game_Rules.xlsx. Record: docs\backups\counterfrenzy_20261002_changes.json. Code gaps found during verification: open_decisions row 74 (Dev Pending). Frenzy 0.50 still awaits user confirmation.
