# CTRBLXAI boss options follow-up (2026-11-01). DB read-only. Seed 20261101 (expected-value model + exact per-day DP; no random draws).
import math, json
OUTD = r'D:\AI\Projects\CTRBLXAI\sim\daily_systems_2026-11-01'
src = open(OUTD + r'\daily_sim.py', encoding='utf-8').read()
exec(src[:src.find('R = dict(seed=SEED')])          # same DB values, prov() assertions, per_drop model, B8
assert B8 == 81, B8
SEED = 20261101
N_CARDS = 11                                         # board size at QB L8, as in report.md

def binom(n, p):
    return [math.comb(n, k) * p**k * (1-p)**(n-k) for k in range(n+1)]

def day_rates(n, mode, q, cap, w, offer):
    """per-day expected (boss battles, boss wins rewarded) for integer n battles"""
    if mode == 'random':                     # takes a random card; boss with prob q; rewarded wins capped
        pb = binom(n, q * w)
        win_r = sum(min(k, cap) * p for k, p in enumerate(pb))
        return n * q, win_r
    # hunter: takes a boss whenever offered and rewards are left today (cap counts wins)
    st = {0: 1.0}; bb = 0.0; wr = 0.0
    for _ in range(n):
        ns = {}
        for k, p in st.items():
            if k < cap:
                bb += p * offer; wr += p * offer * w
                ns[k+1] = ns.get(k+1, 0) + p * offer * w
                ns[k] = ns.get(k, 0) + p * (1 - offer * w)
            else:
                ns[k] = ns.get(k, 0) + p
        st = ns
    return bb, wr

def per_battle(bpd, **kw):
    lo = math.floor(bpd); hi = lo + 1; f = bpd - lo
    a = day_rates(lo, **kw) if lo > 0 else (0, 0); b = day_rates(hi, **kw)
    bb = (1-f) * a[0] + f * b[0]; wr = (1-f) * a[1] + f * b[1]
    return bb / bpd, wr / bpd               # boss-battle share, rewarded boss wins per battle

def life2(G3, d, player, weight=0.10, cap=3, boss_cry=5, reroll=True, daily_m=5, w=0.90):
    days = G3 / 0.875; bpd = N_B / days
    offer = 1.0 if reroll else 1 - (1 - weight) ** N_CARDS
    if player == 'random': share, eb = per_battle(bpd, mode='random', q=weight, cap=cap, w=w, offer=None)
    else:                  share, eb = per_battle(bpd, mode='hunter', q=weight, cap=cap, w=w, offer=offer)
    t = dict(m_kill=0, m_quest=0, m_chest=0, m_disp=0, m_elite=0, m_boss=0, m_dis=0, m_daily=daily_m * G3,
             c_dis=0, c_elite=0, c_boss=0, bosses=0, elites=0)
    for b in range(N_B):
        L = lvl_at(b); Li = max(1, math.floor(L))
        bs, rb = (share, eb) if b >= B8 else (0.0, 0.0)
        ee = 0.034 * (1 - bs) * w            # elite = 0.034 of normal-quest battles (fixed roll), paid on a win
        t['bosses'] += rb; t['elites'] += ee
        n = (0.25 + REST) * w * d
        nx = (max(0, rb - 0.034 * w) + 0.75 * max(0, ee - 0.034 * w)) * d
        t['m_kill'] += 0.25 * w; t['m_quest'] += 2/7 * w; t['m_chest'] += 0.2 * w; t['m_disp'] += 0.3
        t['m_elite'] += 2 * ee; t['m_boss'] += 3 * rb
        t['m_dis'] += (n + nx) * dis_merc(Li)
        t['c_dis'] += n * PD['crystals'] + nx * 2; t['c_elite'] += 3 * ee; t['c_boss'] += boss_cry * rb
    t['mercury'] = sum(v for k, v in t.items() if k.startswith('m_'))
    t['crystals'] = sum(v for k, v in t.items() if k.startswith('c_'))
    t['levellings'] = t['mercury'] / 98
    return {k: round(v, 2) for k, v in t.items()}

OPTS = {
 'B1': dict(), 'B2': dict(cap=1), 'B3': dict(boss_cry=2), 'B4': dict(weight=0.03), 'B5': dict(cap=1, weight=0.03),
 'B6': dict(reroll=False),
 # extra combinations used only for the alternatives
 'B2+B3': dict(cap=1, boss_cry=2), 'B5+B3': dict(cap=1, weight=0.03, boss_cry=2), 'B5+B6': dict(cap=1, weight=0.03, reroll=False),
 'B4+B6': dict(weight=0.03, reroll=False), 'B5+B3+B6': dict(cap=1, weight=0.03, boss_cry=2, reroll=False),
}
R = dict(seed=SEED, B8=B8, n_cards=N_CARDS, win=0.90, results={})
for o, kw in OPTS.items():
    for pl in ('random', 'hunter'):
        for G3 in (30, 80, 180):
            for dm in (5, 4, 3):
                lo = life2(G3, 0.75, pl, daily_m=dm, **kw); hi = life2(G3, 1.0, pl, daily_m=dm, **kw)
                R['results'][f'{o}|{pl}|G{G3}|m{dm}'] = dict(lev=(lo['levellings'], hi['levellings']), cry=(lo['crystals'], hi['crystals']),
                                                         bosses=hi['bosses'], elites=hi['elites'])
# baseline check vs report.md (0.034 boss estimate, G80, daily 5): life() from daily_sim
R['check_report_G80'] = (life(G3=80, d=0.75)['levellings'], life(G3=80, d=1.0)['levellings'], life(G3=80, d=0.75)['crystals'], life(G3=80, d=1.0)['crystals'])
json.dump(R, open(OUTD + r'\results_options.json', 'w', encoding='utf-8'), indent=1, default=str)
print('ok', R['check_report_G80'])
