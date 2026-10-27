# Consumable Tag Update + Phantom Steps Fix — Handoff (2026-10-26)

## Status: READY, NOT YET SAVED to the live game database

All three changes below were worked out and double-checked on a safe copy of the
database. They could **not** be saved into the live `CTRBLXAI.db` this session
because the write-enabled tool was unavailable in this run. Everything is
captured in a ready-to-run script so it can be saved in one step.

**To save the changes** (back up the database first), run this once from the docs folder:

```
sqlite3 "D:\AI\Projects\CTRBLXAI\docs\CTRBLXAI.db" ".read consumable_tag_commit_20261026.sql"
```

The script is safe to run more than once. It does **not** touch any effect numbers.

A fully-updated copy of the database (with all three changes already applied and
checked) is also saved in the session's artifacts as `CTRBLXAI_tagged_20261026.db`,
in case you'd rather drop that copy in place of the live file.

---

## What changes

### A) New "Self Heal" label on the 10 potions a unit can use on itself
These are the healing items the Emergency Locket is allowed to auto-fire as a panic heal:

REC-001, REC-002, REC-003, REC-004, REC-005, REC-006, REC-007, REC-008, REC-015, REC-020

- REC-015 (Cooling Gel Applicator) **is included** per your decision — the Locket may
  spend it as a panic heal even though it also clears Burn.
- REC-014 (Trauma Kit) and REC-019 (Emergency Triage Pack) are **left out** — both can
  only be used on an ally, so the wearer's Locket could never fire them.

### B) Tidied-up labels so the game can look things up by label instead of reading text
Added the missing "Cleanse" label to the two cleanse items that didn't have the plain
label yet (Trauma Kit and Cooling Gel). A reference entry was also added to the
consumable rules so the developer has one clear list of what each label means.

### C) Phantom Steps boot wording
Changed the description from "+2 movement" to "+1 movement" when stepping through an
enemy, and noted that this extra cost is skipped while the wearer can fly — matching
what the game code already does.

---

## Developer tag contract (the labels to look up)

Each item keeps its old labels; these are the labels to read for one-line lookups:

| Label        | Meaning                                   | Items |
|--------------|-------------------------------------------|-------|
| Self Heal    | HP heal the unit can use on itself        | REC-001,002,003,004,005,006,007,008,015,020 |
| Healing      | any HP heal (self or ally)                | the above + 014,017,018,019 |
| MP Recovery  | restores MP                               | REC-009,010,011,012,020 |
| Cleanse      | removes a status/debuff                   | REC-013,014,015,016 |
| Revive       | revives a knocked-out ally                | REC-017,018 |
| Shield       | grants a shield                           | REC-019 |
| Regeneration | heals a little over time                  | REC-007,008 |

**Emergency Locket (AC-015):** look for an equipped consumable labelled **Self Heal**
with charges left, and use the one with the most charges. No text reading needed.

## Still to do after saving
- Regenerate `CTRBLXAI_Consumable_Item_Catalog.xlsx` from the database so the
  browsable copy matches. (Held until the database is saved, so the two never disagree.)
