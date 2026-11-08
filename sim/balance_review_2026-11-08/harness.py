"""
CTRBLXAI balance review harness — Nov 8 batch (rules 252/253 + Static Field, Blood Price, Life Link, Lunge, Recoil Shot)
Seed: nov08_batch (deterministic; game has no combat RNG)
Every formula is taken from CTRBLXAI.db (see FORMULAS_nov08.md for provenance). No Luau read.
Read-only on the DB (opened mode=ro).
"""
import math, sqlite3, json, sys

DB = r"D:\AI\Projects\CTRBLXAI\docs\CTRBLXAI.db"
SEED = "nov08_batch"
BANDS = [1, 25, 50, 99, 150, 199, 250, 300]

def rnd(x):  # core_stats 28: .5 rounds up
    return math.floor(x + 0.5) if x >= 0 else -math.floor(-x + 0.5)

# ---------- stats (unit_progression 49, 100, 101, 104) ----------
HUMAN = dict(STR=(1, .33), AGI=(1, .33), INT=(1, .33), VIT=(2, .34), DEX=(1, .33), LUK=(2, .34))
def race_stat(stat, L):
    s, g = HUMAN[stat]; return s + math.floor(g * (L - 1))
def alloc_points(L, human=True):
    return 3 * (L - 1) + ((L - 1) // 3 if human else 0)
def build(L, split):
    """split: dict stat->fraction of allocable points (fractions sum to 1)."""
    pts = alloc_points(L)
    out = {k: race_stat(k, L) for k in HUMAN}
    given = 0
    for k, f in split.items():
        add = math.floor(pts * f); out[k] += add; given += add
    return out
EVEN = {k: 1/6 for k in HUMAN}
STR_FOCUS = dict(STR=.6, VIT=.2, DEX=.2)
VIT_FOCUS = dict(VIT=.6, STR=.2, DEX=.2)
INT_FOCUS = dict(INT=.6, VIT=.2, DEX=.2)

# ---------- scaling (weapons_equipment 157 / nonweapon_equipment 11) ----------
def scale(L): return 0.30 + 0.70 * ((max(L, 1) - 1) / 98) ** 0.55
WEAPONS = {  # weapons_equipment 25-45 (L99 Dmg/WT/Dly/Def)
    'Sword': (67, 60, 60, 5, '1H'), 'Greatsword': (65, 165, 28, 10, '2H'), 'Hammer': (80, 130, 110, 5, '2H'),
    'Claws': (45, 25, 110, -5, '2H'), 'War Axe': (97, 107, 20, -20, '2H'), 'Dagger': (60, 10, 20, 6, '1H'),
    'Whip': (44, 80, 80, 0, '1H'), 'Staff': (58, 60, 40, 0, '2H'), 'Spear': (42, 90, 45, 21, '2H'),
}
ARMOR_L99 = dict(Def=89.5, WT=66, HP=109.5, MP=50.5)  # median of each slot's 20 items, nonweapon_equipment

def eff_wt(wt, STR):  # core_stats 2
    r = STR / (200 + STR)
    return wt * (1 - r) if wt >= 0 else wt * (1 + r)

class Unit:
    def __init__(s, L, split, weapon='Sword', boss=False):
        s.L, s.S, s.wname = L, build(L, split), weapon
        d, wt, dly, wdef, hands = WEAPONS[weapon]; sc = scale(L)
        s.wdmg, s.wwt, s.wdly, s.wdef = d*sc, wt*sc, dly*sc, wdef*sc
        S = s.S
        s.armor_wt = eff_wt(ARMOR_L99['WT']*sc, S['STR'])
        s.mbrt = (300 if boss else 400) + s.armor_wt          # weapons_equipment 7
        s.ewwt = eff_wt(s.wwt, S['STR'])
        s.ba_rt = rnd(s.mbrt*0.10) + s.ewwt                   # weapons_equipment 8
        s.cycle = s.mbrt + 2*s.ba_rt                          # weapons_equipment 9 (2-action turn)
        s.hp = 50 + 4*S['VIT'] + ARMOR_L99['HP']*sc           # core_stats 5
        s.mp = 20 + 2*S['INT'] + ARMOR_L99['MP']*sc           # core_stats 4
        s.def_ = ARMOR_L99['Def']*sc + s.wdef
        s.defpow = s.def_*(1 + S['VIT']/300)                  # core_stats 5/31
        s.atk = s.wdmg*(1 + S['STR']/200)                     # core_stats 2/31
        s.pot = 1 + S['INT']/(200 + S['INT'])                 # core_stats 4
        s.force = 1 + S['STR']//60                            # core_stats 2
        s.stab = S['VIT']//60                                 # core_stats 5 / 53
        s.move_range = 3 + S['AGI']//60                       # core_stats 3
        s.jump = 1 + S['DEX']//60
        s.rtres = 1 - S['VIT']/(300 + S['VIT'])               # core_stats 5 (RT delay + debuff res)
        s.healeff = 1 + S['VIT']/300
        s.chan_mult = 1 - S['DEX']/(300 + S['DEX'])           # core_stats 6
    def skill_rt(s, N): return rnd((s.mbrt*0.10 + s.ewwt)*N)  # core_stats 20
    def inflict_dly(s, base): return base*(1 + min(s.S['STR']/(200 + s.S['STR']), 0.75))  # core_stats 2
    def move_rt(s, tiles, mult=1.0):                          # movement_targeting 8 (+ status mult)
        return rnd(s.mbrt*0.0375*tiles*(1 - s.S['AGI']/(200 + s.S['AGI']))*mult)

def dmg(att, tgt, mult, use_pot=True):  # core_stats 31/34/35 (Hit Quality ~1 at even DEX/AGI; no LUK delta)
    P = att.atk*mult*(att.pot if use_pot else 1)
    D = tgt.defpow
    raw = P - (P*D)/(P + D) if P + D > 0 else 0
    hq = 1 + (att.S['DEX']/(att.S['DEX']+200) - tgt.S['AGI']/(tgt.S['AGI']+200))
    return raw*hq

R = {}
# ---------------- 1. baseline turn length ----------------
R['turn'] = {L: dict(enemy_cycle=rnd(Unit(L, EVEN).cycle), enemy_mbrt=rnd(Unit(L, EVEN).mbrt),
                     enemy_VIT=Unit(L, EVEN).S['VIT'], enemy_AGI=Unit(L, EVEN).S['AGI'],
                     enemy_move_range=Unit(L, EVEN).move_range) for L in BANDS}

# ---------------- 2. Rule 252 area turn-delay value ----------------
# (skill, N for RT, delay-mult on weapon RT delay or fixed fn, channel, pattern max targets, weapon)
AREA = [
 ('Decimating Swing', 1.60, ('w', 1.50), 100, 3, 'Hammer'),
 ('Decimating Swing', 1.60, ('w', 1.50), 100, 3, 'Greatsword'),
 ('Dragon Dive',      1.60, ('w', 1.40),   0, 5, 'Sword'),
 ('Dragon Dive',      1.60, ('w', 1.40),   0, 5, 'Hammer'),
 ('Thunderclap',      1.40, ('w', 0.60), 150, 24, 'Sword'),
 ('Thunderclap',      1.40, ('w', 0.60), 150, 24, 'Hammer'),
 ('Sweeping Cut',     1.50, ('w', 0.75),   0, 3, 'Sword'),
 ('Gale Thrust',      1.35, ('w', 0.60),   0, 6, 'Sword'),
 ('Shadow Rake',      1.35, ('w', 0.60),   0, 3, 'Sword'),
 ('Pyroclasm',        1.30, ('w', 0.40), 100, 5, 'Sword'),
 ('Tidal Crash',      1.40, ('w', 0.50), 150, 13, 'Sword'),
 ('Venom Burst',      1.40, ('w', 0.50),   0, 9, 'Sword'),
 ('Fissure Line',     1.30, ('w', 0.40),   0, 4, 'Sword'),
 ('Glacial Wave',     1.25, ('w', 0.35), 100, 3, 'Sword'),
 ('Siphon Pulse',     1.50, ('w', 0.40), 150, 8, 'Sword'),
 ('Chain Spark',      1.00, ('w', 0.25), 100, 4, 'Sword'),
 ('Voltaic Chain',    1.10, ('w', 0.30), 100, 3, 'Sword'),
 ('Meteor Marker',    1.40, ('w', 0.50), 200, 9, 'Sword'),
 ('Static Field',     None, ('f', lambda L: rnd(30 + 0.10*L)), 100, 8, 'Sword'),
 ('Blinding Flash',   None, ('f', lambda L: rnd(20 + 0.08*L)),   0, 3, 'Sword'),
]
FIXED_RT = {'Static Field': lambda L: rnd(70 + 0.30*L), 'Blinding Flash': lambda L: rnd(70 + 0.25*L)}
R['area'] = []
for name, N, dl, chan, maxt, wpn in AREA:
    for L in BANDS:
        a = Unit(L, STR_FOCUS, wpn); e = Unit(L, EVEN)
        rt = a.skill_rt(N) if N else FIXED_RT[name](L)
        cost = rt + chan*a.chan_mult
        if dl[0] == 'w': per = a.inflict_dly(a.wdly*dl[1])*e.rtres
        else: per = dl[1](L)*e.rtres   # fixed formula: no STR bonus applied (assumption, see report)
        row = dict(skill=name, weapon=wpn, L=L, caster_cost_ct=rnd(cost), per_target_delay=rnd(per),
                   per_target_turn_pct=round(100*per/e.cycle, 1),
                   denial_ratio_1=round(per/cost, 2), denial_ratio_3=round(3*min(3, maxt)/3*per/cost, 2) if maxt >= 3 else None,
                   max_targets=maxt)
        R['area'].append(row)

# ---------------- 3. Gale Thrust knockback ----------------
R['gale'] = []
for L in BANDS:
    for an, asp in (('even', EVEN), ('STR60%', STR_FOCUS), ('STR100%', {'STR': 1.0})):
        a = Unit(L, asp)
        for dn, dsp in (('even', EVEN), ('VIT60%', VIT_FOCUS), ('lowVIT(0 alloc)', {'STR': .5, 'AGI': .5})):
            d = Unit(L, dsp)
            kb = max(0, a.force//2 - d.stab); push = max(0, a.force - d.stab)
            R['gale'].append(dict(L=L, attacker=an, defender=dn, force=a.force, stab=d.stab, gale_kb=kb, push_action=push))

# ---------------- 4. Static Field / Movement Slow ----------------
R['static'] = []
for L in BANDS:
    a = Unit(L, INT_FOCUS); e = Unit(L, EVEN)
    cost = FIXED_RT['Static Field'](L) + 100*a.chan_mult
    dly = rnd(30 + 0.10*L)*e.rtres
    slow_dur = 800*e.rtres
    turns_in_slow = slow_dur/e.cycle
    full_move = e.move_rt(e.move_range); extra_per_move = full_move*0.5
    slow_val = extra_per_move*max(1.0, turns_in_slow)  # assume 1 full move per turn under slow
    mp = rnd(5 + 0.16*(L-1))
    R['static'].append(dict(L=L, caster_cost_ct=rnd(cost), mp=mp, caster_maxmp=rnd(a.mp), delay_per_unit=rnd(dly),
                            slow_ct=rnd(slow_dur), full_move_rt=full_move, slow_extra_rt=rnd(slow_val),
                            per_enemy_total=rnd(dly + slow_val), enemy_turn=rnd(e.cycle),
                            per_enemy_turn_pct=round(100*(dly+slow_val)/e.cycle, 1),
                            breakeven_enemies=round(cost/(dly + slow_val), 1),
                            wet_extra_rt=rnd(full_move*0.25)))

# ---------------- 5. Pinned duration in turns ----------------
R['pin'] = []
for L in BANDS:
    for dn, dsp in (('even', EVEN), ('VIT60%', VIT_FOCUS)):
        e = Unit(L, dsp)
        d = 1000*e.rtres
        R['pin'].append(dict(L=L, target=dn, pinned_ct=rnd(d), turns=round(d/e.cycle, 2),
                             boss_ct=math.ceil(1000*0.5*e.rtres), boss_turns=round(math.ceil(1000*0.5*e.rtres)/Unit(L, dsp, boss=True).cycle, 2),
                             pinning_support_ct_est=rnd(e.cycle*e.rtres)))

# ---------------- 6. Blood Price ----------------
R['blood'] = []
for L in BANDS:
    a = Unit(L, STR_FOCUS); e = Unit(L, EVEN)
    hit = dmg(a, e, 1.40); ba = dmg(a, e, 1.0, use_pot=False)
    ps = dmg(a, e, 1.25)
    cost = rnd(a.hp*0.15)
    ls = 0.10*hit; vs = 0.05*a.hp; bh = 0.15*a.hp
    R['blood'].append(dict(L=L, caster_hp=rnd(a.hp), hp_cost=cost, dmg=rnd(hit), power_strike_dmg=rnd(ps), basic=rnd(ba),
                           enemy_hp=rnd(e.hp), casts_to_kill=math.ceil(e.hp/hit) if hit else None,
                           casts_before_lockout=sum(1 for _ in iter(int, 1)) if False else int((a.hp - cost) // cost) if cost else None,
                           lifesteal_refund=rnd(ls), vitality_surge_refund=rnd(vs), blood_harvest_refund=rnd(bh),
                           net_cost_with_VS_pct=15 - 5, refund_pct_lifesteal=round(100*ls/a.hp, 1),
                           rt=a.skill_rt(0.80), power_strike_rt=a.skill_rt(1.25), ps_mp=rnd(3 + 0.08*(L-1))))

# ---------------- 7. Life Link ----------------
R['link'] = []
for L in BANDS:
    c = Unit(L, VIT_FOCUS); h = Unit(L, INT_FOCUS); e = Unit(L, EVEN)
    hl = rnd((10 + 0.25*L + 0.35*h.S['INT'] + h.wdmg*0.30)*h.pot*c.healeff)  # Healing Light received by caster
    regen_tick = rnd(rnd(c.hp*0.05)*c.healeff); regen_2000 = regen_tick*(2000//300)
    ps_hit = dmg(c, e, 1.25)
    turns_2000 = 2000/c.cycle
    lifesteal_2000 = 0.10*ps_hit*2*turns_2000           # Lifesteal on Power Strike, 2 casts/turn (MP permitting)
    siphon = 0.30*3*dmg(c, e, 0.60)*c.healeff            # Siphon Pulse hitting 3 enemies
    cost_rt = rnd(70 + 0.25*L) + 100*c.chan_mult
    R['link'].append(dict(L=L, link_mp=rnd(5 + 0.16*(L-1)), link_cost_ct=rnd(cost_rt), healing_light_on_ally=rnd(hl),
                          hl_mp=rnd(4 + 0.12*(L-1)),
                          share_if_caster_gets_1_HL=rnd(hl*0.5), share_regen_full=rnd(regen_2000*0.5),
                          share_lifesteal_PS=rnd(lifesteal_2000*0.5), share_siphon_cast=rnd(siphon*0.5),
                          caster_maxhp=rnd(c.hp), ally_maxhp=rnd(e.hp)))

# ---------------- 8. Lunge / Recoil ----------------
R['lunge'] = []
for L in BANDS:
    a = Unit(L, STR_FOCUS); e = Unit(L, EVEN)
    lunge = dmg(a, e, 1.00); ba = dmg(a, e, 1.0, use_pot=False); ps = dmg(a, e, 1.25)
    R['lunge'].append(dict(L=L, lunge_dmg=rnd(lunge), lunge_rt=a.skill_rt(1.20), lunge_mp=rnd(3 + 0.08*(L-1)),
                           basic_dmg=rnd(ba), basic_rt=rnd(a.ba_rt), move2_rt=a.move_rt(1),
                           turn_dist2_old_or_new_lunge_PS=rnd(lunge + ps), turn_dist2_move_PS=rnd(ps),
                           recoil_dmg=rnd(dmg(a, e, 0.80)), recoil_rt=a.skill_rt(1.10), move1_rt=a.move_rt(1),
                           enemy_threat_range=e.move_range + 1))

# ---------------- 9. Glacial Wave freeze value ----------------
R['freeze'] = []
for L in BANDS:
    e = Unit(L, EVEN); a = Unit(L, INT_FOCUS)
    dur_turns = 3  # elements_statuses 74 (3 turns), Debuff Res shortens
    eff_turns = dur_turns*e.rtres
    extra = e.cycle*eff_turns     # each frozen turn costs double -> one extra turn-length of RT per frozen turn
    combo_cost = (rnd(70 + 0.30*L)) + a.skill_rt(1.25) + 100*a.chan_mult
    R['freeze'].append(dict(L=L, frozen_turns=round(eff_turns, 2), rt_lost_per_unit=rnd(extra),
                            turns_lost_per_unit=round(eff_turns, 2), combo_caster_cost_ct=rnd(combo_cost),
                            ratio_per_unit=round(extra/combo_cost, 2)))

json.dump(R, sys.stdout, default=str)
