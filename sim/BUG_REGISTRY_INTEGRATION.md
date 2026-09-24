# CTRBLXAI Bug Registry - Integration Spec

**Purpose:** Prevent reintroduction of known bugs at implementation time, before UAT in Studio.

**Registry:** D:\AI\Projects\CTRBLXAI\sim\bugs.db (SQLite). Separate from CTRBLXAI.db
(design canon, read-only in coding sessions) and roblox_best_practices.db (general Luau
standards). This DB is workflow memory and IS editable during coding sessions.

---

## The Gate Rule (hard stop)

When an implementation touches a source file that has bug history in the registry, the
developer/coder role MUST, BEFORE advising that UAT can proceed:

1. Look up every bug whose files overlap the touched files.
2. For each detectability='source' bug: read the current code and confirm the bug was NOT
   reintroduced, using its regression_check.
3. If a known bug was reintroduced -> FIX IT FIRST. Then re-verify. Only after it holds is
   the implementation cleared for UAT.
4. A reintroduced known bug is a HARD STOP - never passed to UAT with a disclosure or
   "proceed with warning." Fix, then advance.
5. For each detectability='runtime' bug: the code check cannot self-confirm. Surface the
   regression_check to the user as a Studio verification item - do not claim it is fixed.

The user should never be the one who discovers a resurfaced KNOWN bug in Studio.

---

## Which skills consult the registry

- ctrblxai-pre-impl-check   - before writing code: list bug history for every target file.
- ctrblxai-diff-impact      - after an edit: for every touched file (and files referencing
                              changed members), check bug history and run source regression checks.
- ctrblxai-post-impl-review - final gate before UAT: enforce the hard-stop rule above.
                              Output per touched-file-with-history: bug id, symptom,
                              regression check, and PASS / FIXED-NOW / STUDIO-NEEDED.

---

## Lookup query (by touched files)

    SELECT b.id, b.symptom, b.root_cause, b.regression_check, b.detectability,
           b.status, b.recurrence_count
    FROM bugs b
    JOIN bug_files bf ON bf.bug_id = b.id
    WHERE bf.file_path IN (:files)
    ORDER BY b.status DESC, b.recurrence_count DESC;

Recurring bugs (status='Recurring', high recurrence_count) are the worst offenders - surface first.

---

## File-rename rule (preserves the file-path link)

Source files are NEVER renamed or deleted as routine. The user does not rename files.
If an implementation genuinely requires a rename/delete, it must be strongly justified and
documented - AND in the same step, every affected bugs.files and bug_files.file_path entry
MUST be updated to the new path. A rename that skips the registry update silently breaks the
bug-history link and is treated as an error.

---

## Logging discipline (or the registry rots)

- No bug is "done" until it is logged. A fix without a registry entry loses its protection.
- Only log bugs worth catching: anything that recurred, or that touched load-bearing logic.
  A one-time typo does not earn an entry - noise makes the gate cry wolf.
- Increment recurrence_count when an already-logged bug comes back; set status='Recurring'.

---

## Detectability

- source  - confirmable by reading code. Must be checked pre-UAT and fixed if reintroduced.
- runtime - visual/timing bug, only observable in Studio. Registry surfaces the regression
            check for the user's Studio pass; it cannot self-confirm the fix.
