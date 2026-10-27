-- CTRBLXAI consumable-tag + Phantom Steps commit (USER DECISIONS 2026-10-26)
-- Apply against D:\AI\Projects\CTRBLXAI\docs\CTRBLXAI.db
-- To apply:  sqlite3 "D:\AI\Projects\CTRBLXAI\docs\CTRBLXAI.db" ".read consumable_tag_commit_20261026.sql"
-- Idempotent: safe to re-run. effectFormula values are NOT changed. Back up the .db first.
BEGIN;

-- PART A: add 'Self Heal' tag to the 10 self-usable HP-restore items
UPDATE consumable_items SET Secondary_Tags='Healing, Self Heal'                 WHERE Item_ID='REC-001';
UPDATE consumable_items SET Secondary_Tags='Healing, Self Heal'                 WHERE Item_ID='REC-002';
UPDATE consumable_items SET Secondary_Tags='Healing, Self Heal'                 WHERE Item_ID='REC-003';
UPDATE consumable_items SET Secondary_Tags='Healing, Self Heal'                 WHERE Item_ID='REC-004';
UPDATE consumable_items SET Secondary_Tags='Healing, Self Heal'                 WHERE Item_ID='REC-005';
UPDATE consumable_items SET Secondary_Tags='Healing, Self Heal'                 WHERE Item_ID='REC-006';
UPDATE consumable_items SET Secondary_Tags='Healing, Regeneration, Self Heal'   WHERE Item_ID='REC-007';
UPDATE consumable_items SET Secondary_Tags='Healing, Regeneration, Self Heal'   WHERE Item_ID='REC-008';
UPDATE consumable_items SET Secondary_Tags='Healing, Burn Cleanse, Self Heal, Cleanse' WHERE Item_ID='REC-015';
UPDATE consumable_items SET Secondary_Tags='Healing, MP Recovery, Self Heal'    WHERE Item_ID='REC-020';

-- PART B: unify 'Cleanse' class tag on the two cleanse items that lacked it
UPDATE consumable_items SET Secondary_Tags='Healing, Wound Cleanse, Cleanse'    WHERE Item_ID='REC-014';
-- (REC-015 already handled above; REC-013 'Cleanse, Poison' and REC-016 'Cleanse' already carry Cleanse)

-- PART B doc: Dev tag contract row
INSERT INTO consumable_framework (section, topic, rule, notes) VALUES (
 'Tag Contract',
 'Recovery functional-class tags',
 'Dev tag contract for Recovery consumables (added 2026-10-26, USER DECISIONS). Replace effect-text parsing with Secondary_Tags lookups. Canonical functional-class tags (each item keeps its existing broad/specific labels; these are ADDED alongside): [Self Heal] = self-usable HP restore (REC-001,002,003,004,005,006,007,008,015,020 = 10 items). The AC-015 Emergency Locket reads ''Self Heal'': find an equipped consumable tagged Self Heal with charges>0 and auto-fire the one with the most charges. [Healing] = any HP restore, self or ally (14 items incl. ally-only 014,017,018,019). [MP Recovery] = MP restore (REC-009,010,011,012,020). [Cleanse] = removes a status/debuff (REC-013,014,015,016). [Revive] = revives a KO''d ally (REC-017,018). [Shield] = grants a Shield value (REC-019). [Regeneration] = HP-over-time ticks (REC-007,008). EXCLUDED from Self Heal: REC-014 Trauma Kit and REC-019 Emergency Triage Pack (both target ''Ally'' only, cannot be used on self). effectFormula values were NOT changed.',
 'USER DECISIONS 2026-10-26. Self Heal set = 10 items. Dev wires one-line tag lookups.'
);

-- PART C: Phantom Steps FT-020 through-enemy move cost +2 -> +1 (waived under Flight; code authoritative)
UPDATE nonweapon_equipment
   SET rule='May move through enemy-occupied tiles. Each enemy tile costs +1 movement and triggers compatible reactions; the through-enemy move cost is waived while the wearer has Flight. (90 BP)'
 WHERE id=106;

COMMIT;
