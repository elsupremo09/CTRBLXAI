-- CTRBLXAI game_flow migration — gameplay-loop decisions locked 2026-10-12
-- CORRECTED VERSION (supersedes gameflow_migration_2026-10-12.sql for the id-4 row only).
-- Target: D:\AI\Projects\CTRBLXAI\docs\CTRBLXAI.db  (canonical docs/ copy; NOT the root-folder stub)
--
-- WHAT CHANGED vs. the original staged script:
--   * id 4 (party management): the original staged UPDATE set the party to "EXACTLY 7 fixed slots".
--     Per the USER CORRECTION of 2026-10-12 that is WRONG and must NOT be applied.
--     The correct rule: a party holds UP TO 7 units — 7 is the MAXIMUM/ceiling, NOT a required/fixed count.
--     A player with fewer units (e.g. 3) still forms a valid party and can quest; the per-quest deploy
--     cap (id 16, playerSlots 5–7) limits how many actually deploy, resolved at the deployment phase.
--   * id 32 note tweaked: "Enabled by the UP-TO-7-unit party" (not "fixed 7-unit party"), to stay
--     consistent with the corrected id 4. (Combination bonuses remain an OPEN design item regardless.)
--   * Everything else (id 9, id 16, id 27, 28, 29, 30, 31, 33) is applied EXACTLY as staged/approved.
--
-- VALIDATED on a working copy: 26 rows -> 33 rows; PRAGMA integrity_check = ok; no duplicate (stage,step) pairs.
-- game_flow has NO xlsx export sheet in CTRBLXAI_Game_Rules.xlsx, so NO sheet regeneration is needed.
-- MAKE A .bak OF docs\CTRBLXAI.db FIRST. Run exactly once.

BEGIN TRANSACTION;

-- === UPDATES to existing (previously Locked 2026-10-07) rows ===

-- id 4  party management: CLARIFIED — 7 is a MAXIMUM ceiling, not a fixed/required count (user correction 2026-10-12).
UPDATE game_flow SET topic='HQ: Party management', rule='Saved parties (Party A, B, C...) each with a name and logo. A saved party holds UP TO 7 units (7 = the maximum deployment ceiling, NOT a required or fixed count): a player with fewer units (e.g. 3) still forms a valid party and can go on quests, fielding what they have. The per-quest deployable cap (see Deployment) limits how many of the party actually deploy, resolved at the deployment phase. Units away on dispatch show greyed out and cannot be picked.', owner_slice='8', notes='Locked 2026-10-12 (clarified from ''holds up to 7 units (max deployment)'' Locked 2026-10-07; made explicit that 7 is a MAXIMUM ceiling, not a fixed/required count — a smaller party is valid. NOTE: staged migration''s ''EXACTLY 7 fixed slots'' was rejected per user correction 2026-10-12).' WHERE id=4;

-- id 9  quest selection = base/guild action; ACCEPTANCE = commit point (map gen + asset load). Refinement, same semantics.
UPDATE game_flow SET topic='Accept quest at the guild', rule='Quest selection is an out-of-battle action taken at the base, from the Adventurer''s Guild / quest board tab (RPG-standard) — it is not the first thing a session presents. ACCEPTING a quest is the commit point: it triggers map generation and background asset (UGC model) loading while the player prepares. (Supersedes the earlier ''Choose quest'' wording; map-generated-on-accept and no map pre-generation are unchanged.)', owner_slice='5/6', notes='Locked 2026-10-12 (was id9 ''Choose quest'' Locked 2026-10-07; refined — same commit-on-pick semantics, now named as a base/guild action with acceptance as the explicit commit point)' WHERE id=9;

-- id 16 deployment: add per-quest deploy cap resolved at deployment (feeds x1.5 tiles + enemy-count scaling). Extension.
UPDATE game_flow SET topic='Deployment', rule='Deployment starts as it does now. Each quest defines its own MAXIMUM deployable unit count, which may be fewer than the party''s 7. The cap does NOT resize the party: at the deployment phase the player chooses which of their 7 to field, and the deployment screen states the cap. The quest''s deployable number (the cap, not a flat 7) is the value already fed into deployable-tile scaling (x1.5, rounded up) and enemy-count scaling — this keeps parties fixed for bonuses while preserving per-quest difficulty variation.', owner_slice='4', notes='Locked 2026-10-12 (was ''Deployment starts as it does now.'' Locked 2026-10-07; EXTENDED with per-quest deploy cap resolved at deployment)' WHERE id=16;

-- === NEW rows ===

INSERT INTO game_flow (id,stage,step,topic,rule,owner_slice,notes) VALUES (27,'2 Preparation',5,'Quest prep submenu','After a quest is ACCEPTED, the player enters a mostly-optional prep menu. OPTIONAL items: Manage Unit Loadout (existing loadout screen) and Edit Party Roster (assign units to a party). MANDATORY, ORDERED spine: Choose Party to deploy -> Sortie. ''Sortie'' is the final confirmation screen (it is the existing Depart briefing, id 11) showing the quest, the generated map, and battle details, with a go / back-out choice. Nothing in this menu is load-bearing for timing (asset availability is checked at server start, not here).','4/6/7','Locked 2026-10-12 — prep-submenu structure; Sortie = the existing Depart briefing (id 11)');
INSERT INTO game_flow (id,stage,step,topic,rule,owner_slice,notes) VALUES (28,'2 Preparation',6,'Abandon-quest penalty','Abandoning or re-picking a quest AFTER acceptance forfeits 50% of that quest''s posted reward. Rationale: acceptance kicks off map generation + asset downloads (real server/time work), so the penalty discourages needless map rebuilds. Applies from acceptance onward with NO ''free first pick'' exemption. Fairness is handled by WARNING the player, in-world at the moment of acceptance, that accepting begins preparations and abandoning afterward costs half the reward. Player-facing copy MUST be immersive/in-world (guild/quartermaster voice) and NEVER system language such as ''map build'' or ''assets''. (Consistent with id 12: guaranteed rewards are fixed at board refresh, so this penalty governs rebuild cost, not reward rerolling.) Final exact wording is a later polish pass — see open item.','6','Locked 2026-10-12 — 50% forfeit from acceptance; in-world warning at acceptance; exact wording open');
INSERT INTO game_flow (id,stage,step,topic,rule,owner_slice,notes) VALUES (29,'3 Battle start',5,'UGC outfit availability check','The enemy outfit (UGC) availability check runs at SERVER START, not during map prep. It was the slow (~38s at high item counts) step; moving it to server start means nothing in the prep menu is load-bearing for timing. Map generation + asset loading begin at quest acceptance; the server-start check confirms outfit availability before the battle opens.','6/8','Locked 2026-10-12 — moved outfit/UGC availability check off map-prep onto server start (performance)');
INSERT INTO game_flow (id,stage,step,topic,rule,owner_slice,notes) VALUES (30,'5 Return to base',2,'Loop restart','After base processing the base screen opens and the gameplay loop restarts from the base (session start). Victory returns here via the Victory path (id 17); Defeat returns here via the Defeat path (id 18). The loop always ends and restarts at the player''s home base.','4/6','Locked 2026-10-12 — explicit loop closure (Victory/Defeat -> base -> loop restarts)');
INSERT INTO game_flow (id,stage,step,topic,rule,owner_slice,notes) VALUES (31,'9 Open',3,'Unit roster storage cap','Total unit storage cap per player roster is not decided. (Distinct from the item inventory 50-item soft maintenance threshold.) Needed for recruitment/roster-capacity gating.','4/8','Open 2026-10-12');
INSERT INTO game_flow (id,stage,step,topic,rule,owner_slice,notes) VALUES (32,'9 Open',4,'Party combination bonuses','The actual party-combination bonus designs (which unit groupings grant what bonuses) are not decided. Enabled by the UP-TO-7-unit party (id 4). Designs pending.','4/6','Open 2026-10-12');
INSERT INTO game_flow (id,stage,step,topic,rule,owner_slice,notes) VALUES (33,'9 Open',5,'Abandon-penalty prompt wording','Final in-world wording of the acceptance-time abandon-penalty prompt is not decided. Must be immersive guild/quartermaster voice; never system language (''map build'', ''assets''). Polish pass. See Abandon-quest penalty.','7','Open 2026-10-12');

COMMIT;
