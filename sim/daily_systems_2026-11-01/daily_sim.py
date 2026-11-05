# CTRBLXAI daily systems lifetime check (2026-11-01). DB read-only. Seed 20261101 (model is expected-value; no random draws).
import math, json, sqlite3, re
V2 = r'D:\AI\Projects\CTRBLXAI\sim\runeforge_v2_2026-11-01'
OUTD = r'D:\AI\Projects\CTRBLXAI\sim\daily_systems_2026-11-01'
exec(open(V2 + r'\v2_core.py', encoding='utf-8').read())          # DB values with prov() assertions
tb = open(V2 + r'\v2_tests_b.py', encoding='utf-8').read()
exec(tb[:tb.find('def lifetime')])                                  # per_drop model (same as report_v2 / recheck)
SEED = 20261101
# ---- provenance for the rules used today (assert DB text) ----
prov('Kill mercury victory only', 'materials_system', 7, ['5% chance per enemy kill', 'Paid on a victory only'])
prov('Chest mercury', 'materials_system', 10, ['1 mercury'])
prov('Quest mercury', 'materials_system', 11, ['1 quest in 7 offers 1-3 mercury', 'victory only'])
prov('Dispatch mercury', 'materials_system', 12, ['1 mercury per mission; 2 for tier 4-5', '0.3 mercury per battle', 'lower the dispatch amount rather than the kill chance'])
prov('Daily event', 'materials_system', 13, ['5 mercury per completed daily event', 'every 3rd'])
prov('Salvage', 'materials_system', 14, ['5% chance of 1 mercury', '5% chance of one equipment item'])
prov('Lifetime battles', 'materials_system', 36, ['547 battles'])
prov('Elite/boss grants', 'materials_system', 41, ['3 crystals', '50% chance of 1 rune gem', '5 crystals, 1 rune gem'])
prov('Dismantle', 'materials_system', 42, ['ceil(level / 10)', 'Uncommon 1 / Rare 2 / Epic 3'])
prov('Boss limit', 'loot_progression', 15, ['first 3 rewarded boss completions per day'])
prov('Elite estimate', 'loot_progression', 26, ['0.034'])
prov('Enemies per battle', 'loot_progression', 86, ['Normal 5, Elite 6, Boss 4'])
prov('Wall target', 'guild_facilities', 38, ['target 15-20'])
prov('QB function', 'guild_facilities', 17, ['L8: Boss quests'])
prov('GXP floor', 'unit_progression', 94, ['cannot go below the current level'])
prov('Escape', 'unit_progression', 95, ['same reward rules as wipeout'])
prov('Dispatch burn', 'unit_progression', 77, ['minimum 1 day per battle'])
prov('Board refresh count', 'game_flow', 20, ['count the battle toward shop and quest board refresh'])
prov('Abandon', 'game_flow', 28, ['forfeits 50%'])
prov('Ice Spike skill', 'skills', None, []) if False else None
r = con.execute("select RT_Cost_Formula, MP_Cost_Formula, Effects from skills where Skill_ID='SKL-ICE-SPIKE'").fetchone()
assert 'Ice Spike' in r[2] and r[1] == 'round(5 + 0.12 × (L - 1))', r
nw = ' '.join(str(x) for x in con.execute("select * from nonweapon_equipment where id=34").fetchone())
assert 'Ice Spike' in nw and 'placed items (Deployable)' in nw
PROV['Ice Spike skill'] = dict(table='skills', row='SKL-ICE-SPIKE', found=True)
PROV['Salvager qualifying objects'] = dict(table='nonweapon_equipment', row=34, found=True)

PD = per_drop(0.0)
REST = 0.40 - 0.25
RARE_GEMS = LINES['Rare']
# Quest Board L8 earliest battle: spare income (income - necessities) covers Guild Hall L1-3 + Quest Board L1-8
need = sum(FAC['Guild Hall'][:3]) + sum(FAC['Quest Board'][:8])
acc, B8 = 0.0, None
for b in range(N_B):
    acc += INC[b] * (1 - NEC / INCOME)
    if acc >= need: B8 = b; break

def life(G3=80, d=1.0, w=0.90, boss='est', elite=0.034, dispatch=0.3, salv=0.0, quest=2/7, chest=0.2, daily_m=5, b8=None, cap_days=None):
    b8 = B8 if b8 is None else b8
    days = cap_days if cap_days else (G3 / 0.875 if G3 else 80 / 0.875)
    bpd = N_B / days
    t = dict(m_kill=0, m_quest=0, m_chest=0, m_disp=0, m_salv=0, m_elite=0, m_boss=0, m_dis=0, m_daily=daily_m * G3,
             c_dis=0, c_elite=0, c_boss=0, g_dis=0, g_elite=0, g_boss=0, s_dis=0, s_elite=0, s_boss=0, s_daily=G3 // 3,
             bosses=0, elites=0)
    for b in range(N_B):
        L = lvl_at(b); Li = max(1, math.floor(L))
        if boss == 'est': bp = 0.034
        elif boss == 'card': bp = 0.10 if b >= b8 else 0.0
        elif boss == 'cap': bp = min(3 / bpd, 1 - 0.9 ** 11) if b >= b8 else 0.0
        else: bp = 0.0
        eb, ee = bp * w, elite * w
        t['bosses'] += eb; t['elites'] += ee
        dr = (0.25 + REST) * w + salv * 0.05 * w
        extra = max(0, eb - 0.034 * w) + 0.75 * max(0, ee - 0.034 * w)   # extra Rare-or-better items beyond the 0.40 base
        n = dr * d; nx = extra * d
        t['m_kill'] += 0.25 * w; t['m_quest'] += quest * w; t['m_chest'] += chest * w; t['m_disp'] += dispatch
        t['m_salv'] += salv * 0.05 * w; t['m_elite'] += 2 * ee; t['m_boss'] += 3 * eb
        t['m_dis'] += (n + nx) * dis_merc(Li)
        t['c_dis'] += n * PD['crystals'] + nx * 2; t['c_elite'] += 3 * ee; t['c_boss'] += 5 * eb
        t['g_dis'] += n * PD['gems'] + nx * RARE_GEMS; t['g_elite'] += 0.5 * ee; t['g_boss'] += eb
        t['s_dis'] += n * PD['sulfur']
        if L >= 60: t['s_elite'] += 0.25 * ee; t['s_boss'] += eb
    for k, p in (('mercury', 'm_'), ('crystals', 'c_'), ('gems', 'g_'), ('sulfur', 's_')):
        t[k] = sum(v for kk, v in t.items() if kk.startswith(p))
    t['levellings'] = t['mercury'] / 98
    return {k: round(v, 2) for k, v in t.items()}

R = dict(seed=SEED, B8=B8, qb8_need_gold=need)
# 0. reproduce recheck R2 (old: all wins, quests 0.3, no daily)
R['repro_R2'] = {f'd{int(d*100)}': life(G3=0, d=d, w=1.0, quest=0.3)['mercury'] for d in (0.75, 1.0)}
# 1. main table
main = {}
for G3 in (30, 80, 180):
    for d in (0.75, 1.0):
        for w in (0.80, 0.90, 1.00):
            main[f'G{G3} d{int(d*100)} w{int(w*100)}'] = life(G3=G3, d=d, w=w)
R['main'] = main
# boss scenarios
R['boss'] = {f'G{G3} d{int(d*100)} {bm}': life(G3=G3, d=d, boss=bm) for G3 in (30, 80, 180) for d in (0.75, 1.0) for bm in ('est', 'card', 'cap')}
# dispatch sensitivity
R['dispatch'] = {f'G80 d{int(d*100)} disp{x}': life(G3=80, d=d, dispatch=x)['levellings'] for d in (0.75, 1.0) for x in (0.0, 0.15, 0.3, 0.6, 1.0, 1.83, 2.0)}
# knob solving: value that brings G80, d100, w90 to exactly 20.0 levellings
def solve(fn, lo, hi):
    for _ in range(60):
        mid = (lo + hi) / 2
        if fn(mid) > 20.0: hi = mid
        else: lo = mid
    return round(lo, 3)
base = dict(G3=80, d=1.0, w=0.9)
R['knob'] = dict(
    dispatch_pb=solve(lambda x: life(**base, dispatch=x)['levellings'], 0, 0.3),
    daily_mercury=solve(lambda x: life(**base, daily_m=x)['levellings'], 0, 5),
    quest_pb=solve(lambda x: life(**base, quest=x)['levellings'], 0, 2/7),
)
k = 0
for x in [i / 1000 for i in range(0, 51)]:
    if life(**base)['levellings'] - (0.05 - x) * 0 > 0: pass
# kill chance: m_kill = 5*p*w per battle
basek = life(**base)
R['knob']['kill_chance_pct'] = round(100 * max(0, 0.05 - (basek['levellings'] - 20) * 98 / (5 * 0.9 * N_B)), 2)
# candidate knob values, full grid
cands = {'now (daily 5, dispatch 0.3)': {}, 'daily 4': dict(daily_m=4), 'daily 3': dict(daily_m=3), 'dispatch 0.15': dict(dispatch=0.15),
         'dispatch 0': dict(dispatch=0.0), 'quest 1 in 14': dict(quest=1/7), 'kill 3%': dict()}
grid = {}
for nm, kw in cands.items():
    row_ = {}
    for G3 in (30, 80, 180):
        for d in (0.75, 1.0):
            r_ = life(G3=G3, d=d, **kw)
            if nm == 'kill 3%': r_['levellings'] = round(r_['levellings'] - 5 * 0.02 * 0.9 * N_B / 98, 2)
            row_[f'G{G3} d{int(d*100)}'] = r_['levellings']
    grid[nm] = row_
R['knob_grid'] = grid
# 2. elite fishing (abandon-scan each board; N normal cards grows 3 -> 12)
def Nb(b): return min(12, 3 + b // 50)
scan = sum(1 - 0.966 ** Nb(b) for b in range(N_B)) / N_B
R['elite_scan_rate'] = round(scan, 4)
R['elite_scan'] = {f'd{int(d*100)}': life(G3=80, d=d, elite=scan) for d in (0.75, 1.0)}
R['elite_every_win'] = {f'd{int(d*100)}': life(G3=80, d=d, elite=1.0) for d in (0.75, 1.0)}
# 3. salvage: natural (1 break/battle while worn) and Ice Spike farm
R['salv_natural'] = {f'breaks{x}': life(G3=80, d=1.0, salv=x)['levellings'] for x in (0.5, 1, 2)}
spk = {}
for L in (25, 50, 99):
    cost = round(5 + 0.12 * (L - 1)); rt = round(60 + 0.20 * L)
    for INT in (60, 100, 150):
        mp = 20 + 2 * INT; regen = 2 + INT // 40
        spk[f'L{L} INT{INT}'] = dict(mp_cost=cost, rt=rt, spikes_from_pool=mp // cost, ct_per_extra_spike=round(cost / regen * 1000))
R['ice_spike'] = spk
for n in (10, 30, 60):
    R[f'salv_spike_{n}_per_battle'] = life(G3=80, d=1.0, salv=n)
R['salv_gold_per_roll'] = {L: round(12.5 * (1 + L / 50)) for L in (1, 50, 99)}
# 5. chest held
R['chest_hold'] = dict(chest_merc_allwin=round(0.2 * N_B, 1), chest_merc_w90=round(0.2 * N_B * 0.9, 1),
                       chest_gold_lifetime_base=round(sum(0.2 * 25 * (1 + lvl_at(b) / 50) for b in range(N_B))),
                       chest_gold_lost_w90=round(sum(0.2 * 25 * (1 + lvl_at(b) / 50) for b in range(N_B)) * 0.1 * 0.5))
R['prov'] = PROV
json.dump(R, open(OUTD + r'\results_daily.json', 'w', encoding='utf-8'), indent=1, default=str)
print('ok')
