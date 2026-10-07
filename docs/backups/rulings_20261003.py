# 2026-10-03 USER RULINGS: (1) Interact targeting, (2) counter trigger scope, (3) channeled/delayed counters.
# Designer agent. DB = single source of truth. Fresh run (prior attempt wrote nothing).
import sqlite3, shutil, os, json, datetime
DOCS = r'D:\AI\Projects\CTRBLXAI\docs'
DB = os.path.join(DOCS, 'CTRBLXAI.db')
BK = os.path.join(DOCS, 'backups')
stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
os.makedirs(BK, exist_ok=True)

# ---------- BACKUP (sqlite online-backup API, then verify) ----------
bk_db = os.path.join(BK, f'CTRBLXAI_pre_rulings_{stamp}.db')
src = sqlite3.connect(DB)
dst = sqlite3.connect(bk_db)
src.backup(dst)
dst.close(); src.close()
chk = sqlite3.connect(bk_db)
assert chk.execute('pragma integrity_check').fetchone()[0] == 'ok'
bk_counts = {t: chk.execute(f'select count(*) from "{t}"').fetchone()[0] for t in ('project_rules', 'skills', 'trigger_safety', 'open_decisions')}
chk.close()
bk_xlsx = os.path.join(BK, f'CTRBLXAI_Game_Rules_pre_rulings_{stamp}.xlsx')
shutil.copy2(os.path.join(DOCS, 'CTRBLXAI_Game_Rules.xlsx'), bk_xlsx)
bk_index = os.path.join(BK, f'INDEX_pre_rulings_{stamp}.txt')
shutil.copy2(os.path.join(DOCS, 'INDEX.txt'), bk_index)

c = sqlite3.connect(DB)
cur = c.cursor()
log = []; inserted = []

def get(t, rowid):
    return cur.execute(f'select * from "{t}" where rowid=?', (rowid,)).fetchone()

def upd(t, rowid, **kv):
    old = get(t, rowid)
    sets = ', '.join(f'"{k}"=?' for k in kv)
    cur.execute(f'update "{t}" set {sets} where rowid=?', list(kv.values()) + [rowid])
    assert cur.rowcount == 1, (t, rowid)
    log.append((t, rowid, old, get(t, rowid)))

def skill_rowid(sid):
    r = cur.execute('select rowid from skills where Skill_ID=?', (sid,)).fetchall()
    assert len(r) == 1, sid
    return r[0][0]

# ---------- FRESH-RUN GUARDS ----------
for i in (131, 133, 134, 135):
    assert '2026-10-03' not in (get('project_rules', i)[3] + (get('project_rules', i)[4] or '')), ('already applied?', i)
assert get('project_rules', 133)[2] == 'Native — Recruit Enemy'
assert get('project_rules', 134)[2] == "Native — Ally (not KO'd)"
assert get('project_rules', 135)[2] == "Native — KO'd Ally"
assert get('trigger_safety', 9)[0] == 'TRG-004'
assert get('open_decisions', 74)[0].startswith('Counter Stance / Riposte / Frenzy - Dev gaps')
assert cur.execute('select max(rowid) from open_decisions').fetchone()[0] == 76

# ================= RULING 1 — INTERACT TARGETING =================
NOTE_DEV1 = ' DEV CHANGE PENDING (Interact target filtering; no AP/RT charged when an Interact fails its checks). Not Studio-tested.'
r131 = get('project_rules', 131)
upd('project_rules', 131,
    rule=r131[3].rstrip() + (
        " TARGET-SIDE FILTER (USER RULING 2026-10-03): RECRUIT -> ENEMY units only (units hostile to the interacting unit). "
        "AID (living-ally RT boost) and REVIVE (KO'd-ally resuscitation) -> ALLIED units only. "
        "NEUTRAL units get NO native unit-Interact option - this includes NPC/neutral units AND any unit recruited this battle "
        "(a recruited unit becomes Neutral, so it cannot be Recruited again, Aided, or Revived). Map-object Interact is unaffected. "
        "Authored battlefield-event NPC interactions (battlefield_events, e.g. Merchant Caravan, Fortune Teller) are event-defined, "
        "not native Recruit/Aid/Revive, and are not changed by this filter. "
        "REJECT WITHOUT PAYMENT: an Interact that fails any of its checks (wrong side, enemy HP above the recruit threshold, "
        "ineligible unit type, etc.) is rejected BEFORE commitment - NO AP, RT, or other cost is spent "
        "(command_pipeline step 2 'Reject with no cost/state change'; validation_matrix 'Failed validation changes no AP/MP/HP/RT/state')."),
    notes='Locked — Design Session 2026-10-02; target-side filter + reject-without-payment added 2026-10-03 (USER RULING).' + NOTE_DEV1)

r133 = get('project_rules', 133)
new133 = r133[3]
old_a = 'Interact on an enemy whose current HP is <=5% of max recruits it.'
old_b = 'Recruited unit becomes a controllable NEUTRAL for the rest of the battle.'
old_c = 'Cannot recruit: bosses, veterans, elites, or any unit whose race is not playable.'
for frag in (old_a, old_b, old_c):
    assert frag in new133, frag
new133 = (new133
    .replace(old_a, "Interact on an ENEMY unit whose current HP is <=5% of max recruits it. "
                    "TARGETS: ENEMIES ONLY (USER RULING 2026-10-03) - NPC/Neutral units are NOT recruitable.")
    .replace(old_b, "Recruited unit becomes a controllable NEUTRAL for the rest of the battle. Because it is now Neutral it is "
                    "NO LONGER a valid recruit target (it drops off the recruit list), and it cannot receive Aid or Revive either "
                    "(those are allies-only - see the Ally / KO'd Ally rows): a recruited Neutral gets NO Interact options. "
                    "Consequence: a recruited Neutral that is KO'd cannot be Revived, so it is not 'still alive at battle end' and is not added to the roster.")
    .replace(old_c, "Cannot recruit: bosses, veterans, elites, Neutral/NPC units (including units already recruited), or any unit whose race is not playable."))
upd('project_rules', 133, rule=new133,
    notes='Locked — Design Session 2026-10-02; target scope revised 2026-10-03 (USER RULING: enemies only; Neutral/NPC excluded; recruited unit becomes Neutral and drops off the recruit list).' + NOTE_DEV1)

r134 = get('project_rules', 134)
assert r134[3].startswith("Interact on a living ally reduces")
upd('project_rules', 134,
    rule="AID - Interact on a living ALLIED unit" + r134[3][len("Interact on a living ally"):].rstrip() +
         " TARGETS: ALLIED units ONLY (USER RULING 2026-10-03) - not Neutrals, not recruited Neutrals, not enemies.",
    notes="Locked — Design Session 2026-10-02; allies-only target scope added 2026-10-03 (USER RULING) - RESOLVES the open item 'do recruited Neutrals get Aid/Revive?' = NO, allies only (open_decisions row 77)." + NOTE_DEV1)

r135 = get('project_rules', 135)
assert r135[3].startswith("Interact on a KO'd ally resuscitates")
upd('project_rules', 135,
    rule="REVIVE - Interact on a KO'd ALLIED unit" + r135[3][len("Interact on a KO'd ally"):].rstrip() +
         " TARGETS: KO'd ALLIED units ONLY (USER RULING 2026-10-03) - not Neutrals, not recruited Neutrals, not enemies.",
    notes="Locked — Design Session 2026-10-02; allies-only target scope added 2026-10-03 (USER RULING) - RESOLVES the open item 'do recruited Neutrals get Aid/Revive?' = NO, allies only (open_decisions row 77)." + NOTE_DEV1)

# ================= RULINGS 2 + 3 — COUNTER TRIGGER SCOPE + CHANNELED =================
TRIG = ("TRIGGER (USER RULING 2026-10-03 - replaces the old 'DIRECT (primary) target of a Basic Attack or single-target damaging Skill only; "
        "AOE/splash does not trigger' wording): counters ANY ENEMY attack that DEALS DIRECT DAMAGE to the stance holder - an AP-consuming "
        "Basic Attack OR a damaging Skill of ANY pattern (Single, AOE, Cleave, Chain, Cone, Ring, Circle, Adjacent, Line, Impact Splash, "
        "InheritWeapon), whether the holder is the primary target or is caught by a splash/secondary hit. The gate is DAMAGE DEALT > 0 to "
        "the stance holder, NOT the number of targets. Damage dealt = final direct damage of at least 1 after Defense/Guard/mitigation; "
        "damage soaked by a Shield still counts; a hit fully negated or absorbed to 0 does not. Zero-damage / pure-status / debuff-only "
        "Skills (e.g. Steal, Seal of Silence, Mind Fracture, Wither, Stone Prison) do NOT trigger a counter; a damaging Skill that also "
        "applies a status DOES. Still required: the attacker is an ENEMY of the stance holder (an ally's friendly fire never provokes); "
        "the attacker is inside the holder's equipped-weapon Basic Attack reach; the holder is still standing after the hit; at most ONE "
        "counter per stance holder per attacking action (a multi-hit or multi-jump action that hits the holder several times provokes "
        "once - TRG-004). Passive follow-ups, DoT/status ticks, terrain, hazard, collision, fall and map-object damage, and other "
        "reactions do NOT trigger a counter.")
CHAN = ("CHANNELED / DELAYED SKILLS (USER RULING 2026-10-03): an enemy Skill with Channel Time and/or Activation Time that deals direct "
        "damage DOES provoke a counter, but the check is made AT SKILL EXECUTION (when it activates/resolves and deals its damage), NOT "
        "when the enemy commits or starts channeling. At execution every condition is re-checked: the holder still has the CounterStance "
        "status, is still in the Skill's area and actually takes direct damage > 0, is still standing, and the attacker is still inside "
        "the holder's weapon reach with legal LoS/elevation for the holder's Basic Attack. If the holder moved out, was KO'd, lost LoS, "
        "or the attacker is now out of reach, NO counter fires. (Same rule the other way: a stance raised after the enemy committed but "
        "before execution does count.)")
REACH_OLD = "Basic Attack reach at trigger time"
REACH_NEW = "Basic Attack reach at trigger time (= when the attack's damage resolves; for channeled/delayed Skills = at Skill execution, not commit)"
SR_ADD = (" Canon rev 2026-10-03 (USER RULINGS): trigger = any enemy attack dealing direct damage > 0, any pattern (AOE/splash included; "
          "zero-damage/status-only Skills excluded); channeled/delayed Skills checked at execution with validity/range re-check. "
          "Player-facing SkillData.lua text must be updated by the Dev to match. Not Studio-tested.")
META_ADD = "; Rev 2026-10-03 user rulings (damage>0 any-pattern trigger; execution-time check for channeled/delayed)"

rid = skill_rowid('DOC-DUELIST-01')
row = get('skills', rid)
cols = [r[1] for r in cur.execute('pragma table_info(skills)')]
d = dict(zip(cols, row))
assert 'single-target damaging Skill' in d['Effects'] and REACH_OLD in d['Targeting_Range']
upd('skills', rid,
    Effects=("Reaction (Riposte). " + TRIG + " " + CHAN + " COUNTER: resolves as the caster's Basic Attack at 85% Basic Attack Power "
             "with the full weapon pattern (Cleave/Adjacent/Line2/Impact Splash secondary hits at their normal splash rates) and applies "
             "50% main-hand Weapon RT Delay to the attacker. FRIENDLY FIRE APPLIES: pattern hits land on every unit in the area, including "
             "allies. A counter never triggers another counter (TRG-005)."),
    Targeting_Range=d['Targeting_Range'].replace(REACH_OLD, REACH_NEW),
    Special_Rules=d['Special_Rules'].rstrip() + SR_ADD,
    Meta=d['Meta'].rstrip() + META_ADD)

rid = skill_rowid('SKL-COUNTER-STANCE')
d = dict(zip(cols, get('skills', rid)))
assert 'single-target damaging Skill' in d['Effects'] and REACH_OLD in d['Targeting_Range']
upd('skills', rid,
    Effects=("Apply Counter Stance buff (1000 CT). While active the caster counters every qualifying hit. " + TRIG + " " + CHAN +
             " COUNTER: resolves as the caster's Basic Attack with the full weapon pattern (Cleave/Adjacent/Line2/Impact Splash secondary "
             "hits at their normal splash rates). FRIENDLY FIRE APPLIES: pattern hits land on every unit in the area, including allies. "
             "Counter power 0.60x; attacker also takes round(Weapon RT Delay x 0.30). Each counter adds the caster's Basic Attack RT to its "
             "next turn. A counter never triggers another counter (TRG-005). First general-pool reaction-eligible skill."),
    Targeting_Range=d['Targeting_Range'].replace(REACH_OLD, REACH_NEW),
    Special_Rules=d['Special_Rules'].rstrip() + SR_ADD,
    Meta=d['Meta'].rstrip() + META_ADD)

# ---- TRG-004 ----
upd('trigger_safety', 9,
    col_3=("An ENEMY AP-consuming Basic Attack or Skill of ANY pattern (Single, AOE, Cleave, Chain, Cone, Ring, Circle, Adjacent, Line, "
           "Impact Splash, InheritWeapon) that DEALS DIRECT DAMAGE (> 0) to the reacting unit - as primary target or via a splash/secondary "
           "hit. Gate = damage dealt > 0, NOT target count or primary-target status. Channeled/delayed Skills: evaluated when the Skill "
           "EXECUTES (activation/resolution), never at commit."),
    col_4=("Attacker is an ENEMY of the reacting unit (friendly fire never provokes); reacting unit is standing and holds an active "
           "reaction status at evaluation time; the reaction's own range/reach requirement passes (Counter Stance / Riposte: attacker "
           "inside the reactor's equipped-weapon Basic Attack reach, legal LoS/elevation); direct damage dealt to the reactor > 0 "
           "(Shield-soaked damage counts; fully negated/absorbed = 0). For channeled/delayed Skills ALL of these are re-checked at "
           "execution - if the reactor moved out, was KO'd, lost LoS, or the attacker is out of reach, no reaction."),
    col_5=("Resolve the original action's damage stage (including all of its pattern hits); then queue at most one eligible reaction "
           "per reacting unit under authored timing"),
    col_6="Max 1 reaction per reacting unit per qualifying action (multi-hit / multi-jump actions still provoke once); further limits per authored reaction",
    col_7=("Zero-damage / pure-status / debuff-only Skills (e.g. Steal, Seal of Silence, Mind Fracture, Wither, Stone Prison), passive "
           "follow-ups, reactions (no reaction-to-reaction, TRG-005), DoT/status ticks, terrain, hazard, collision, fall and map-object "
           "damage do NOT provoke reactions. AOE/splash hits DO provoke if they deal direct damage > 0 to the reacting unit."),
    col_10="After the qualifying action's damage stage resolves (channeled/delayed Skills: at execution, never at commit)",
    col_11="Nonqualifying event (zero damage, non-enemy source, reactor out of reach/KO'd, or invalid at execution) produces no reaction",
    col_13=("Three passive follow-up attacks from one action do not create three counter-reactions. REVISED 2026-10-03 (USER RULING): "
            "was 'directly and actively targets reacting unit' + 'AOE ... do not independently provoke reactions'. Now AOE/splash DO provoke "
            "when they deal direct damage > 0 to the reactor; zero-damage effects never do; channeled/delayed Skills are checked at "
            "execution. Reconciled with skills SKL-COUNTER-STANCE + DOC-DUELIST-01 (same wording). Enemy-only and no-counter-triggers-a-"
            "counter (TRG-005) guards unchanged. DEV CHANGE PENDING. Not Studio-tested."))

# ---- open_decisions 74 (Dev gaps) ----
o74 = get('open_decisions', 74)[2]
intro_old = 'Found while verifying code for the 2026-10-02 canon sync.'
c_start = o74.index('(c) MULTI-PATTERN')
d_start = o74.index(' (d) NO HOSTILE')
f_start = o74.index('(f) SkillData.lua')
assert o74.startswith(intro_old) and c_start < d_start < f_start
new74 = (
    'Found while verifying code for the 2026-10-02 canon sync; UPDATED 2026-10-03 for USER RULINGS (counter trigger scope + channeled/delayed skills).'
    + o74[len(intro_old):c_start]
    + ("(c) TRIGGER SCOPE (REVISED 2026-10-03 - supersedes the earlier 'call the hook for the primary target' fix): the counter hook must run "
       "for EVERY enemy hit that deals direct damage > 0 to a stance holder - Basic Attack or damaging Skill of ANY pattern "
       "(Single/AOE/Cleave/Chain/Cone/Ring/Circle/Adjacent/Line/Impact Splash/InheritWeapon), primary OR splash/secondary victim - not only "
       "the Single-pattern Basic Attack branch and single-target Skill branch. Gate = damage dealt > 0 (Shield-soaked counts; fully negated "
       "= 0), NOT target count. Zero-damage / status-only Skills (Steal, Seal of Silence, Mind Fracture, Wither, Stone Prison) must NOT "
       "provoke. Max one counter per holder per attacking action.")
    + o74[d_start:f_start]
    + ("(f) PLAYER-FACING TEXT - the Dev must update SkillData.lua DOC-DUELIST-01 + SKL-COUNTER-STANCE description/effects/specialRules to "
       "match the skills table (any enemy attack that deals damage triggers, any pattern incl. AOE/splash; zero-damage/status-only skills do "
       "not; channeled/delayed skills are checked when they go off, and only if the holder is still a valid, in-reach target). Remove the "
       "'DB not yet synced' note from DOC-DUELIST-01 specialRules if still present. "
       "(g) NEW 2026-10-03 - CHANNELED/DELAYED EXECUTION-TIME HOOK: for Skills with Channel Time / Activation Time, evaluate the counter "
       "when the Skill EXECUTES, not at commit; re-check at execution: holder still has CounterStance, still in the area and took damage "
       "> 0, still standing, attacker still inside the holder's weapon reach with legal LoS/elevation - otherwise no counter. "
       "(h) OPTIONAL - AIService counter-stance avoidance only penalises attacking a stance holder directly; under the new scope an AOE "
       "Skill that catches a stance holder also provokes, so the AI penalty should consider every enemy stance holder inside the attack area. "
       "TRG-004 + skills rows updated 2026-10-03 to match. Not Studio-tested."))
upd('open_decisions', 74, col_3=new74)

# ---- open_decisions 77 (new resolved record for Ruling 1) ----
cur.execute('insert into open_decisions values (?,?,?,?,?,?,?)', (
    'Interact targeting - Recruit / Aid / Revive target sides; do recruited Neutrals get Aid/Revive? (2026-10-03)',
    'Resolved',
    ("RESOLVED 2026-10-03 (USER RULING). RECRUIT = ENEMIES ONLY (NPC/Neutral units are not recruitable; a recruited unit becomes Neutral, "
     "so it is no longer a valid recruit target and drops off the recruit list). AID + REVIVE = ALLIED units ONLY (not Neutrals, not "
     "recruited Neutrals, not enemies). NET: a recruited Neutral receives NO native Interact option (so a KO'd recruited Neutral cannot be "
     "Revived and is not added to the roster). This open item was raised in Dev/Designer review and had no row of its own; this row is "
     "its resolution record. Canon: project_rules 'Interact Command' ids 131, 133, 134, 135. DEV CHANGE PENDING: Interact target "
     "filtering + reject-without-payment (no AP/RT charged when an Interact fails its checks). Not Studio-tested."),
    None, None, None, None))
inserted.append(('open_decisions', get('open_decisions', cur.lastrowid)))
assert cur.lastrowid == 77

c.commit()
after_counts = {t: cur.execute(f'select count(*) from "{t}"').fetchone()[0] for t in bk_counts}
json.dump({'stamp': stamp, 'backup_db': bk_db, 'backup_xlsx': bk_xlsx, 'backup_index': bk_index,
           'counts_before': bk_counts, 'counts_after': after_counts,
           'log': [[t, r, list(o), list(n)] for t, r, o, n in log],
           'inserted': [[t, list(n)] for t, n in inserted]},
          open(os.path.join(BK, 'rulings_20261003_changes.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
c.close()
print('BACKUP DB   :', bk_db)
print('BACKUP XLSX :', bk_xlsx)
print('BACKUP INDEX:', bk_index)
print('counts before', bk_counts, 'after', after_counts)
print('updated rows:', [(t, r) for t, r, o, n in log], 'inserted:', [(t, n[0][:60]) for t, n in inserted])
