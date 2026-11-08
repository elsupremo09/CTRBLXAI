r"""
CTRBLXAI follow-up harness - 2026-11-08 7:14 PM rulings (Dragon Dive / Decimating split, Blood Price range 1,
augment add-ons on every unit an area skill damages).
Seed: followup_1114 (deterministic; the game has no combat RNG).
Reuses the formula layer of ..\harness.py (FORMULAS_nov08.md, all from CTRBLXAI.db). No Luau read. DB read-only.
"""
import math, json, sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, "..", "harness.py"), encoding="utf-8").read()
exec(src.split("R = {}")[0])          # formula layer only (Unit, dmg, rnd, builds, weapons)
SEED = "followup_1114"
BANDS = [1, 25, 50, 99, 150, 199, 250, 300]
KEY = [99, 199, 300]
OUT = {}

def mp_cost(L, a0, b): return rnd(a0 + b*(L-1))
def regen(u, ct): return (2 + u.S['INT']//40) * ct / 1000.0          # core_stats 49
def per_hit_delay(att, tgt, mult):                                  # core_stats 2 / 5
    return att.inflict_dly(rnd(att.wdly*mult)) * tgt.rtres

# ---------- A. Dragon Dive / Decimating Swing group speed ----------
SK = {  # name: (RT N, channel, MP a0,b, main mult, side mult, OLD all-mult, hands-needed)
 'Dragon Dive':      (1.60,   0, 8, .14, 1.40, 0.70, 1.40, 'any'),
 'Decimating Swing': (1.60, 100, 5, .14, 1.50, 0.75, 1.50, '2H'),
}
A = []
for name, (N, ch, m0, mb, mm, sm, old, hands) in SK.items():
    for w in ['Hammer', 'Claws', 'Greatsword', 'Whip', 'Sword', 'War Axe']:
        if hands == '2H' and WEAPONS[w][4] != '2H': continue
        for L in BANDS:
            a = Unit(L, STR_FOCUS, w); e = Unit(L, EVEN)
            cast = a.skill_rt(N) + ch*a.chan_mult + (1 if name == 'Dragon Dive' else 0)
            cyc = a.mbrt + 2*cast                      # 2 AP, both on the skill
            dm, ds, do = per_hit_delay(a, e, mm), per_hit_delay(a, e, sm), per_hit_delay(a, e, old)
            rows = {}
            for users in (1, 2):
                k = users*2/cyc
                rows[users] = dict(
                    old=max(0, 1 - k*do),                       # everyone took full mult
                    rotate=max(0, 1 - k*(dm + 2*ds)/3),         # landing/main tile rotated across the 3
                    focus_main=max(0, 1 - k*dm),                # one enemy always the main target
                    focus_side=max(0, 1 - k*ds))                # the other two
            cost = mp_cost(L, m0, mb)
            net = 2*cost - regen(a, cyc)
            A.append(dict(skill=name, weapon=w, L=L, cast_ct=rnd(cast), user_cycle=rnd(cyc), enemy_cycle=rnd(e.cycle),
                          delay_main=rnd(dm), delay_side=rnd(ds), main_pct_turn=round(100*dm/e.cycle, 1),
                          side_pct_turn=round(100*ds/e.cycle, 1),
                          **{f"{u}u_{k2}": round(100*v) for u, r in rows.items() for k2, v in r.items()},
                          mp=rnd(a.mp), mp_per_cast=cost, turns_of_double_cast=round(a.mp/net, 1) if net > 0 else 99))
OUT['A'] = A

# ---------- B. Area skills + augment add-ons ----------
# skill: (N, channel, activation, MPa, MPb, power mult, delay mult, max tiles, realistic enemies, realistic allies)
AREA = {
 'Thunderclap':      (1.40, 150,   0, 7, .22, 0.75, 0.60, 24, 4, 1),
 'Tidal Crash':      (1.40, 150, 200, 7, .22, 0.70, 0.50, 13, 4, 0),
 'Meteor Marker':    (1.40, 200, 400, 8, .30, 0.75, 0.50,  9, 3, 0),   # avg of 1.50 centre / 0.75 secondary
 'Venom Burst':      (1.40,   0,   0, 4, .12, 0.70, 0.50,  9, 3, 0),
 'Siphon Pulse':     (1.50, 150,   0, 6, .18, 0.60, 0.40,  8, 3, 1),
 'Gale Thrust':      (1.35,   0,   0, 5, .14, 0.80, 0.60,  6, 3, 0),
 'Sweeping Cut':     (1.50,   0,   0, 4, .10, 0.90, 0.75,  3, 3, 0),
 'Pyroclasm':        (1.30, 100, 200, 6, .18, 0.85, 0.40,  5, 3, 0),
 'Chain Spark':      (1.00, 100,   0, 6, .20, 0.80, 0.25,  4, 4, 0),
 'Dragon Dive':      (1.60,   0,   1, 8, .14, 1.10, (1.40+0.70*2)/3, 5, 3, 0),
 'Decimating Swing': (1.60, 100,   0, 5, .14, 1.50, (1.50+0.75*2)/3, 3, 3, 0),
}
AUG_MP = {'none': 1.0, 'Pinning': 1.25, 'Delay Strike': 1.35, 'Sluggish': 1.25, 'Interrupt': 1.40,
          'Scatter': 1.25, 'Vortex': 1.25, 'Pin+Delay': 1.25*1.35}   # frameworks 72: multiplicative
B = []
for name, (N, ch, act, m0, mb, pm, dmult, tiles, ne, na) in AREA.items():
    for w in (['Sword', 'Hammer', 'Claws'] if name != 'Decimating Swing' else ['Hammer', 'Claws', 'Greatsword']):
        for L in BANDS:
            for build_name, bsp in (('STR', STR_FOCUS), ('INT', INT_FOCUS)):
                a = Unit(L, bsp, w); e = Unit(L, EVEN)
                cast = a.skill_rt(N) + ch*a.chan_mult + act
                cyc1 = a.mbrt + cast + a.ba_rt          # 1 skill + 1 other action (basic-attack-sized)
                cyc2 = a.mbrt + 2*cast
                hit = dmg(a, e, pm)
                d_skill = per_hit_delay(a, e, dmult)
                pin_ct = 1000*e.rtres                    # elements_statuses 66 (augment row says '1 turn')
                pin_1turn = e.cycle                      # alt reading: covers the target's next turn
                ds = 0.20*e.mbrt*e.rtres                 # Delay Strike: +20% of next-turn CT, 1x per target per 1000-CT round
                slow = 0.10*(e.mbrt - 400 + 400)*1.0     # Slow: Modified Base RT x1.10 -> ~+10% of MBRT for 1 turn
                slow += 0.10*40*2                        # + base component of 2 actions (4 x N, N~1)
                slow *= 1.0
                mp0 = mp_cost(L, m0, mb)
                vs = 0.05*a.hp; ls_per = 0.10*hit
                for aug, mpm in AUG_MP.items():
                    mpc = rnd(mp0*mpm)
                    net1 = mpc - regen(a, cyc1)
                    casts = a.mp/mpc if mpc else 99
                    for users in (1, 2, 3):
                        rate = users*(1/cyc1)*d_skill
                        if aug in ('Delay Strike', 'Pin+Delay'):
                            rate += min(users*1000/cyc1, users if True else 1)*ds/1000   # per-augment-instance reading
                        speed = max(0, 1-rate)
                        B.append(dict(skill=name, weapon=w, build=build_name, L=L, aug=aug, users=users,
                            cast_ct=rnd(cast), cycle_1cast=rnd(cyc1), cycle_2cast=rnd(cyc2), enemy_cycle=rnd(e.cycle),
                            mp_per_cast=mpc, caster_mp=rnd(a.mp), casts_in_tank=round(casts, 1),
                            dmg_per_target=rnd(hit), enemy_hp=rnd(e.hp), dmg_pct_enemy_hp=round(100*hit/e.hp, 1),
                            skill_delay_pct=round(100*d_skill/e.cycle, 1),
                            speed_pct_1cast_per_turn=round(100*speed),
                            pin_uptime_1cast=round(100*min(1, pin_ct/cyc1)), pin_uptime_alt=round(100*min(1, pin_1turn/cyc1)),
                            ds_pct_turn=round(100*ds/e.cycle, 1), slow_pct_turn=round(100*slow/e.cycle, 1),
                            vs_heal_per_unit=rnd(vs), vs_heal_realistic=rnd(vs*(ne+na)), vs_heal_max=rnd(vs*tiles),
                            vs_pct_realistic=round(100*(ne+na)*0.05), ls_heal_realistic=rnd(ls_per*(ne+na)),
                            caster_hp=rnd(a.hp)))
OUT['B'] = B

# ---------- C. Blood Price (range 1 now) ----------
C = []
for L in BANDS:
    a = Unit(L, STR_FOCUS); e = Unit(L, EVEN)
    bp = dmg(a, e, 1.40); bp_nopot = dmg(a, e, 1.40, use_pot=False); ps = dmg(a, e, 1.25)
    bprt, psrt = a.skill_rt(0.80), a.skill_rt(1.25)
    hpc = rnd(a.hp*0.15)
    e_hit = dmg(e, a, 1.0, use_pot=False)      # enemy basic attack on the caster (retaliation exposure)
    C.append(dict(L=L, bp_dmg=rnd(bp), bp_dmg_if_no_potency=rnd(bp_nopot), ps_dmg=rnd(ps), bp_rt=bprt, ps_rt=psrt,
                  bp_per_rt=round(bp/bprt, 2), ps_per_rt=round(ps/psrt, 2), ratio=round((bp/bprt)/(ps/psrt), 2),
                  ratio_no_pot=round((bp_nopot/bprt)/(ps/psrt), 2), hp_cost=hpc, caster_hp=rnd(a.hp),
                  ps_mp=mp_cost(L, 3, .08), caster_mp=rnd(a.mp), enemy_hp=rnd(e.hp),
                  two_bp_pct_enemy=round(100*2*bp/e.hp), enemy_basic_on_caster=rnd(e_hit),
                  enemy_basic_pct_caster=round(100*e_hit/a.hp, 1),
                  vs_refund=rnd(0.05*a.hp), ls_refund=rnd(0.10*bp), net_cost_vs_pct=10))
OUT['C'] = C
json.dump(dict(seed=SEED, **OUT), open(os.path.join(HERE, "results.json"), "w"), indent=1)
print("ok", len(A), len(B), len(C))
