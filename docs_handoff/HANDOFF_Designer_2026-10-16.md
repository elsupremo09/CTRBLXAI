# Designer Handoff — 2026-10-16

**From:** Dev agent (Roblox Dev Expert)
**To:** Designer agent (owns `docs\CTRBLXAI.db`)
**Why this exists:** The Dev agent has read-only access to `docs\`. These three items require changes to the Designer-owned design database. Each is grounded in the exact current row text (copied verbatim below) so the change is precise, not paraphrased. For each item, the code side and the design (DB) side are both stated so the two never silently diverge.

All rows live in `docs\CTRBLXAI.db`. After editing, regenerate the affected xlsx export per the standing data workflow.

---

## ITEM 1 — Lift the dismissal exclusion + record the severance formula

**Status:** The dismissal feature is **already BUILT and Tester-passed in code** (GuildMenuService.lua, LoadoutScreen.lua, BattleEvents.lua), operating under the user's verbal lift of the exclusion on 2026-10-15. This DB change makes the design match the shipped code. **This is the sync gap the Tester flagged.**

### 1a. `loadout_ui_spec` id 56 — remove dismissal/retirement from the excluded list

**Current `rule` (verbatim):**
> Unit renaming, dismissal, retirement, locking/favorites, loadout presets, auto-equip recommendation, auto-skill recommendation, Clear All Augments, respec, race change, cosmetics, equipment upgrading, crafting, blacksmith, selling/disposing, recruitment, tavern, guild upgrades, formation, deployment selection beyond resource state.

**Change to (dismissal + retirement removed):**
> Unit renaming, locking/favorites, loadout presets, auto-equip recommendation, auto-skill recommendation, Clear All Augments, respec, race change, cosmetics, equipment upgrading, crafting, blacksmith, selling/disposing, recruitment, tavern, guild upgrades, formation, deployment selection beyond resource state.

**Append to `notes`:**
> Dismissal lifted + implemented 2026-10-15 (user decision): unit dismissal added to the Loadout Info tab with a gold severance cost (see economy_framework). Avatar cannot be dismissed (project_rules 114).

### 1b. `economy_framework` — add a new row for the severance cost (new id 49; current max id = 48)

The dismissal fee is an economy sink and belongs beside the recruitment fee (economy_framework id 22). Suggested new row:

- **section:** Dismissal
- **topic:** Separation Pay Formula
- **rule:** `Dismissal cost = 5 × recruitment cost = 5 × (200 + Unit Level × 15 + Quality Premium)`. Quality Premium: Standard +0, Quality +300, Elite +800 (same as recruitment, economy_framework id 22). Charged on dismissal; the unit's equipped gear is unequipped back to inventory first (not lost). The player avatar (Hero) can never be dismissed. Examples (Standard tier): L1 = 1,075g, L50 = 4,750g, L99 = 8,425g.
- **notes:** Locked by user 2026-10-15. A steep, intentional sink for permanent roster removal.

---

## ITEM 2 — Add the real `is_avatar` flag to the unit schema

**Status:** `project_rules` id 114 states the avatar is *"Flagged with is_avatar = true in unit schema"*, but **no such field exists** in the `unit_schema` table today. The dismissal code therefore hardcodes the Hero's unit id (`unit_hero`) as the avatar stand-in. Once the flag exists in the schema AND the Hero is actually flagged, the Dev agent will switch the code from the id stand-in to reading `is_avatar` — so the protection is data-driven, not hardcoded.

### `unit_schema` — add a new field row

The `unit_schema` table has columns: `Field | Type | Lifetime | Meaning | Validation`. Add:

- **Field:** `is_avatar`
- **Type:** boolean
- **Lifetime:** Persistent
- **Meaning:** Marks the single player avatar unit. The avatar is unique and cannot be dismissed or lost (project_rules 114).
- **Validation:** Optional; defaults false. At most one unit per player may be true. The starting Hero is the avatar.

**Also:** confirm the starting Hero unit is created/seeded with `is_avatar = true` wherever starter units are defined, so the flag is actually set on a real unit.

---

## ITEM 3 — Redefine dispatch duration: DAYS, not battles (1 day = 4000 CT)

**Status:** **NOT yet built in code.** This is a genuine design-rule change (duration is currently locked as "in battles"), so per the user's rules the DB must change first; then the Dev agent builds the code to match. Do NOT build code before this lands.

**User's rule (2026-10-16):** Dispatch duration is measured in **days**, where **1 day = 4000 CT** = one full Dawn→Day→Dusk→Night cycle (4 rounds of 1000 CT — this ties to the existing time-of-day system). Each completed battle reduces every active dispatch's remaining time by **ceil(battle elapsed CT ÷ 4000) days, minimum 1 day per battle**. Examples: a 2000 CT battle = 1 day; an 8100 CT battle = 3 days. The mission's tier number now means **days** away, not battles. The XP formula keeps its shape — `(Tier × 60) × Duration` — but Duration is now in days.

### 3a. `unit_progression` id 77 (System)

**Current:**
> Dispatched units earn flat XP based on dispatch difficulty × duration. Unit unavailable for N battles. Dispatch appears as a quest on the quest board but does NOT initiate a battle. Player selects units and sends them; they return after the specified duration with rewards.

**Change to:**
> Dispatched units earn flat XP based on dispatch difficulty × duration. Unit unavailable for the dispatch DURATION measured in DAYS (1 day = 4000 CT = one full Dawn→Day→Dusk→Night cycle). Each completed battle burns down remaining dispatch time by ceil(battle elapsed CT ÷ 4000) days, minimum 1 day per battle. Dispatch appears as a quest board activity but does NOT initiate a battle. Player selects units and sends them; they return once their day-duration has elapsed, with rewards.

### 3b. `unit_progression` id 78 (XP formula)

**Current:**
> Dispatch XP = (Dispatch Difficulty Tier × 60) × Duration (in battles). Difficulty Tier 1-5. Duration = battles the unit is away. Pays roughly one battle's kills per battle of duration, minus a small discount for zero risk / no player control.

**Change to:**
> Dispatch XP = (Dispatch Difficulty Tier × 60) × Duration (in DAYS). Difficulty Tier 1-5. Duration = days the unit is away. 1 day = 4000 CT; each completed battle contributes ceil(elapsed CT ÷ 4000) days, minimum 1. Pays roughly one battle's kills per day of duration, minus a small discount for zero risk / no player control.

### 3c. `unit_progression` id 99 (Mission Offers & Duration)

**Current:**
> Default: one dispatch mission offered per difficulty tier (tiers 1-5). Duration (battles away) = difficulty tier. Reward materials: one tier below current content, 1-3 count. XP = (Tier × 60) × Duration. Defaults — tunable later.

**Change to:**
> Default: one dispatch mission offered per difficulty tier (tiers 1-5). Duration (DAYS away) = difficulty tier. 1 day = 4000 CT (one day/night cycle); a completed battle reduces remaining dispatch by ceil(elapsed CT ÷ 4000) days, minimum 1. Reward materials: one tier below current content, 1-3 count. XP = (Tier × 60) × Duration (days). Defaults — tunable later.

### Code side (Dev agent, AFTER the DB lands)
- The battle must report its elapsed CT at battle end.
- `DispatchService` switches from a battle-count countdown (`returnBattle = startBattle + duration`) to a **day** countdown: each `OnBattleCompleted` subtracts `max(1, ceil(elapsedCT / 4000))` days from each active dispatch; a dispatch returns when its remaining days reach 0.
- Save fields: the active-dispatch ledger stores remaining days instead of (or alongside) `returnBattle`. Migration: existing saved dispatches treat their stored battle-count as days (1:1) — harmless for the prototype.

---

## Summary for the Designer

| # | Table / rows | Change | Code already built? |
|---|---|---|---|
| 1a | `loadout_ui_spec` 56 | Remove dismissal/retirement from excluded list; note the lift | Yes (code live under verbal lift) |
| 1b | `economy_framework` new id 49 | Add 5× recruitment severance formula | Yes |
| 2 | `unit_schema` new field + Hero seed | Add `is_avatar` boolean; flag the Hero | Partial (code uses `unit_hero` stand-in until flag exists) |
| 3a-c | `unit_progression` 77, 78, 99 | Duration = days (1 day = 4000 CT), not battles | No — build after DB lands |

After the DB edits, regenerate the affected xlsx exports (data workflow) so they stay in sync.
