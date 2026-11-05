# Checks D (Epic supply), E (facility economy), F (material wall), G (Essences)
# Requires rf_core.py exec'd first.  Deterministic.
prov('Kill gold', 'economy_framework', 2, ['Base Gold × (1 + Enemy Level / 100)'])
prov('Completion gold', 'economy_framework', 8, ['Base × (1 + Map Level / 50)', 'Normal = 30'])
prov('Quest gold', 'economy_framework', 9, ['Base × (1 + Recommended Level / 40)', 'Normal = 50'])
prov('Gold boost', 'economy_framework', 31, ['+25% battle gold'])
prov('Starting gold', 'economy_framework', 47, ['500 gold'])
prov('Shop stock odds', 'economy_framework', 48, ['L9 C15 U35 R35 Epic 15', 'L10 C10 U30 R40 E15 Exalted 5', 'every 5'.replace('every 5', 'Deterministic')])
prov('Merchant shelf', 'guild_facilities', 15, ['5, 5, 6, 7, 7, 8, 9, 10, 10, 10', 'L9 Epic'])
prov('Normal drop', 'loot_progression', 24, ['Base Drop Chance = 5% per enemy'])
prov('Enemies per battle', 'loot_progression', 86, ['Normal 5, Elite 6, Boss 4 + the boss'])

N_B = 547; INCOME = 175800; NEC = 127800; BS_SHARE = 0.43
def lvl_at(b):
    return 1 + b * 98 / N_B
def g_shape(L):
    return (4.4 * 8 + 0.6 * 14) * (1 + L / 100) + 30 * (1 + L / 50) + 50 * (1 + L / 40)
_gs = [g_shape(lvl_at(b)) for b in range(N_B)]
K_INC = INCOME / sum(_gs)
INC = [x * K_INC for x in _gs]
BS_TOT = BS_SHARE * INCOME; OTHER_TOT = NEC - BS_TOT
def bs_needed(t):
    return min(10, max(1, math.ceil(t / 10)))
def bs_profile(shape):
    if shape == 'A':
        w = INC[:]
    else:   # B: proportional to upgrade-cost growth (1 + L/25) per battle
        w = [1 + lvl_at(b) / 25 for b in range(N_B)]
    s = sum(w)
    return [BS_TOT * x / s for x in w]
OTHER = [OTHER_TOT * x / INCOME for x in INC]

FMAX = {k: len(v) for k, v in FAC.items()}
def fac_sim(groups, mult=1.0, discount=True, bs_shape='A', include=None):
    lv = {k: 0 for k in FAC}
    if include is not None:
        for k in list(lv):
            if k not in include: lv.pop(k)
    fund = 500.0; saved = 0.0; spent_fac = 0; bs_paid = 0.0; minfund = 1e9
    ev = {}; bsp = bs_profile(bs_shape)
    def can(f):
        if lv[f] >= FMAX[f]: return False
        if f == 'Guild Hall': return True
        return lv['Guild Hall'] >= max(UNLOCK_GH[f], lv[f] + 1)
    def buy(f, b):
        nonlocal fund, spent_fac
        c = FAC[f][lv[f]]; fund -= c; spent_fac += c; lv[f] += 1
        ev.setdefault(f, {})[lv[f]] = (b, round(lvl_at(b), 1))
    for b in range(N_B):
        L = lvl_at(b)
        d = BS_TABLE[lv['Blacksmith']]['disc'] / 100 if (discount and lv['Blacksmith'] >= 1) else 0.0
        bs_cost = bsp[b] * (1 - d); saved += bsp[b] * d; bs_paid += bs_cost
        fund += INC[b] * mult - OTHER[b] - bs_cost
        minfund = min(minfund, fund)
        while True:
            req = bs_needed(math.floor(L))
            pick = None
            if lv['Blacksmith'] < req:
                pick = 'Blacksmith' if can('Blacksmith') else 'Guild Hall'
            else:
                for grp in groups:
                    cands = [f for f in grp if f in lv and can(f)]
                    if any(f in lv and lv[f] < FMAX[f] for f in grp):
                        # GH is the gate for anything blocked in this group
                        blocked = [f for f in grp if f in lv and lv[f] < FMAX[f] and not can(f)]
                        if blocked and can('Guild Hall') and 'Guild Hall' not in cands:
                            cands.append('Guild Hall')
                        if cands:
                            pick = min(cands, key=lambda f: FAC[f][lv[f]])
                        break
            if pick is None or FAC[pick][lv[pick]] > fund:
                break
            buy(pick, b)
    maxed = [f for f in lv if lv[f] == FMAX[f]]
    return dict(levels=lv, maxed=len(maxed), n_fac=len(lv), leftover=round(fund), facility_spend=spent_fac,
                discount_saved=round(saved), blacksmith_paid=round(bs_paid), min_fund=round(minfund), events=ev,
                income=round(sum(INC) * mult))

CORE6 = ['Guild Hall', 'Tavern', 'Blacksmith', 'Merchant', 'Quest Board', 'Workshop']
OLD9 = [k for k in FAC if k != 'Runeforge']
E = {}
E['income_check'] = dict(total=round(sum(INC)), L1=round(INC[0], 1), L50=round(INC[min(range(N_B), key=lambda b: abs(lvl_at(b) - 50))], 1),
                         L99=round(INC[-1], 1), epic1H_L50_battles=round(4752 / INC[min(range(N_B), key=lambda b: abs(lvl_at(b) - 50))], 1))
E['old9_free_nodisc'] = fac_sim([CORE6, ['Training Ground'], ['Library'], ['Trophy Hall']], 1.0, False, include=OLD9)
E['old9_boost_nodisc'] = fac_sim([CORE6, ['Training Ground'], ['Library'], ['Trophy Hall']], 1.25, False, include=OLD9)
STRATS = {
    'classic (Runeforge after core 6)': [CORE6, ['Runeforge'], ['Training Ground'], ['Library'], ['Trophy Hall']],
    'crafter (Runeforge inside core)': [CORE6 + ['Runeforge'], ['Training Ground'], ['Library'], ['Trophy Hall']],
    'rush (Guild Hall + Runeforge first)': [['Guild Hall', 'Runeforge'], CORE6, ['Training Ground'], ['Library'], ['Trophy Hall']],
}
for nm, gr in STRATS.items():
    for shape in ('A', 'B'):
        E[f'free {nm} bs{shape}'] = fac_sim(gr, 1.0, True, shape)
        E[f'boost {nm} bs{shape}'] = fac_sim(gr, 1.25, True, shape)
    E[f'free {nm} NO discount'] = fac_sim(gr, 1.0, False, 'A')
# boost on battle gold only (EF31 literal): sell income ~10,800 not boosted
E['boost_battle_gold_only_budget'] = round(165000 * 1.25 + 10800 - NEC)
for nm in STRATS:
    for who, mult in (('free', 1.0), ('boost', 1.25)):
        r_ = E[f'{who} {nm} bsA']
        bs_after = BS_TOT - r_['discount_saved']
        inc = INCOME * mult
        r_['blacksmith_share_pct'] = round(100 * bs_after / inc, 1)
        r_['expense_ratio_pct'] = round(100 * (NEC - r_['discount_saved'] + 70927) / inc, 1)
        r_['necessities_pct'] = round(100 * (NEC - r_['discount_saved']) / inc, 1)
R['E'] = E

# ---------------- D: Epic supply L50-80 ----------------
D = {}
D['crafted_gold'] = {}
for slot in ['1H', '2H']:
    for L in (20, 50, 80, 99):
        for st in ['Common', 'Uncommon', 'Rare']:
            for disc in (0, 27):
                ca = cheapest_add(slot, st, 'Epic', BUDGET[st] * (2 if slot == '2H' else 1), L, disc)
                D['crafted_gold'][f'{slot} L{L} {st} -{disc}%'] = dict(add=ca[0], adds=ca[1], fee=str(epic_fee(slot, st, L)), total=str(ca[0] + epic_fee(slot, st, L)),
                                                                     shop_epic=shop(slot, 'Epic', L), pct_of_shop=round(100 * float(ca[0] + epic_fee(slot, st, L)) / shop(slot, 'Epic', L), 1))
D['t4_add_2H'] = {f'L{L}': (rf_gold('2H', L, 4, 0), rf_gold('2H', L, 4, 27)) for L in (20, 50, 99)}
D['t4_add_2H_expected'] = {'L20': (324, 236), 'L50': (540, 394), 'L99': (892, 651)}
R['D'] = D

# ---------------- G: Essence economy ----------------
LW = [(r_, float(w)) for r_, w in [('Common', 0.55), ('Uncommon', 0.2429), ('Rare', 0.1214), ('Epic', 0.0595), ('Exalted', 0.025), ('Legendary', 0.0012)]]
prov('Normal rarity weights', 'loot_progression', 49, ['0.2429'])
MAXTIER = {'Uncommon': 2, 'Rare': 3, 'Epic': 4, 'Exalted': 4, 'Legendary': 5}
UNITS = {'Uncommon': 2, 'Rare': 3, 'Epic': 4, 'Exalted': 4, 'Legendary': 5}   # Exalted 225 -> closest valid lower 200 (no passives)
def partitions(n, maxp):
    if n == 0: yield (); return
    for p in range(min(n, maxp), 0, -1):
        for rest in partitions(n - p, p):
            yield (p,) + rest
def line_profile(rar, two):
    """uniform over legal tier partitions (assumption): returns avg lines and avg Essences by line rarity (uncapped)"""
    n = UNITS[rar] * (2 if two else 1)
    ps = list(partitions(n, MAXTIER[rar]))
    u = sum(sum(1 for p in P if p <= 2) for P in ps) / len(ps)
    r = sum(sum(1 for p in P if p == 3) for P in ps) / len(ps)
    e = sum(sum(1 for p in P if p >= 4) for P in ps) / len(ps)
    return u, r, e
def cap_ess(u, r, e, cap):
    if cap == 'Uncommon': return u + r + e, 0, 0
    if cap == 'Rare': return u, r + e, 0
    return u, r, e
def essence_sim(items_per_battle=0.40, keep=0.10, elite=0.034, boss=0.034, chest=0.2, two_share=1 / 8):
    tot = dict(drop_U=0, drop_R=0, drop_E=0, dis_U=0, dis_R=0, dis_E=0, lost_sell=0, dismantled=0)
    band = {}
    for b in range(N_B):
        L = lvl_at(b); cap = BS_TABLE[bs_needed(math.floor(L))]['extract']
        dU = 0.25 * chest; dR = 0.75 * elite + (boss if L < 40 else 0); dE = boss if L >= 40 else 0
        n_dis = items_per_battle * (1 - keep)
        uu = rr = ee = 0; ls = 0
        for rar, w in LW:
            if rar == 'Common': continue
            for two, sh in ((True, two_share), (False, 1 - two_share)):
                u, r, e = cap_ess(*line_profile(rar, two), cap)
                uu += n_dis * w * sh * u; rr += n_dis * w * sh * r; ee += n_dis * w * sh * e
            ls += n_dis * w * sum(float(sell(s, rar, max(1, math.floor(L)))) for s in BASE) / 8
        for k, v in (('drop_U', dU), ('drop_R', dR), ('drop_E', dE), ('dis_U', uu), ('dis_R', rr), ('dis_E', ee), ('lost_sell', ls), ('dismantled', n_dis * (1 - 0.55))):
            tot[k] += v
        bk = '50-80' if 50 <= L < 80 else None
        if bk:
            bd = band.setdefault(bk, dict(U=0, R=0, E=0, battles=0))
            bd['U'] += dU + uu; bd['R'] += dR + rr; bd['E'] += dE + ee; bd['battles'] += 1
    drops = tot['drop_U'] + tot['drop_R'] + tot['drop_E']; dis = tot['dis_U'] + tot['dis_R'] + tot['dis_E']
    out = {k: round(v, 1) for k, v in tot.items()}
    out['drop_share_pct'] = round(100 * drops / (drops + dis), 1)
    out['per_battle'] = dict(U=round((tot['drop_U'] + tot['dis_U']) / N_B, 3), R=round((tot['drop_R'] + tot['dis_R']) / N_B, 3), E=round((tot['drop_E'] + tot['dis_E']) / N_B, 3))
    out['band_50_80'] = {k: (round(v, 1) if k != 'battles' else v) for k, v in band['50-80'].items()}
    return out
G = {}
for nm, kw in {'base (0.40 items/battle, elite=boss=0.034)': {},
               'all elite (0.107/battle)': dict(elite=0.1067, boss=0.0),
               'all boss (0.05/battle)': dict(elite=0.0, boss=0.05),
               'high loot (1.0 items/battle, design-doc figure)': dict(items_per_battle=1.0)}.items():
    G[nm] = essence_sim(**kw)
G['line_profiles'] = {f'{r_}{" 2H" if t else ""}': tuple(round(x, 2) for x in line_profile(r_, t)) for r_ in MAXTIER for t in (False, True)}
R['G'] = G

# ---------------- F: material wall ----------------
F = {}
INC_T = {'db': [286, 286, 286, 286, 312], 'sim0916': [311, 311, 311, 311, 312]}
PER_ITEM = [0.5, 10, 25.5, 25.5, 5.5]     # materials_system 37 / 10 items
prov('Realistic spend', 'materials_system', 37, ['T1: 5, T2: 100, T3: 255, T4: 255, T5: 55'])
def wall(inc, refund_t3=0.0, refund_t4=0.0):
    """first N where T3 or T4 spend minus usable refunds exceeds income (no conversion)"""
    for N in range(1, 60):
        if N * (PER_ITEM[2] - refund_t3) > inc[2] or N * (PER_ITEM[3] - refund_t4) > inc[3]:
            return N
for k, inc in INC_T.items():
    F[f'R0 no dismantle ({k})'] = dict(wall=wall(inc), pct10=round(100 * 255 / inc[2], 1), pct12=round(100 * 306 / inc[2], 1))
    # R1: replaced at band end -> refund arrives after that tier's spending (no in-band relief)
    F[f'R1 band-end replacement ({k})'] = dict(wall=wall(inc), note='refund arrives after the tier is needed; only usable via 3:1 conversion')
    # R3: half the band spend sits on an item replaced mid-band (BS6 40% in T3 band, BS8 45% in T4 band), +1 Rare+
    r3 = math.floor(0.40 * PER_ITEM[2] / 2) + 1; r4 = math.floor(0.45 * PER_ITEM[3] / 2) + 1
    F[f'R3 mid-band replacement ({k})'] = dict(wall=wall(inc, r3, r4), usable_refund_per_item=(r3, r4))
    # R2: items carried from T3 band into T4 band and dismantled at ~L70 (BS7 40%): T3+half T4 spend refunded as T4
    r2 = math.floor(0.40 * (PER_ITEM[2] + PER_ITEM[3] / 2)) + 1
    F[f'R2 carried across band ({k})'] = dict(wall=wall(inc, 0, r2), usable_T4_refund_per_item=r2)
    F[f'R2+R3 ({k})'] = dict(wall=wall(inc, r3, r2))

# tier laundering loops: Common Gloves, downgrade (free) to L1 -> upgrade -> dismantle at band start
def launder(slot, rar, top, bsl):
    g, m = route(slot, rar, 1, top, bsl)
    spent = sum(m)
    ref = math.floor(Fr(BS_TABLE[bsl]['refund'], 100) * spent) + (1 if RIDX[rar] >= RIDX['Rare'] else 0)
    tier = min(4, mtier(top))
    sellv = [5, 15, 40, 100, 250]
    in_val = sum(a * b for a, b in zip(m, sellv)); out_val = ref * sellv[tier - 1]
    return dict(gold=g, spent=m, refund=ref, refund_tier=f'T{tier}', mat_sell_in=in_val, mat_sell_out=out_val, gold_profit_vs_selling_inputs=out_val - in_val - g)
F['launder'] = {f'{s} {r_} L1->{top} BS{bsl}': launder(s, r_, top, bsl) for s in ['Gloves', '1H'] for r_ in ['Common', 'Rare'] for top in (41, 61) for bsl in (7, 8, 10)}
# +1 trick: Uncommon loot -> Add one T1 (Rare, needs Runeforge L5+) -> dismantle -> +1 band material; Essences: pay 1U, get it back
def plus_one(slot, L, rfd):
    cost = rf_gold(slot, L, 1, rfd); tier = min(4, mtier(L)); v = [5, 15, 40, 100, 250][tier - 1]
    return dict(add_gold=cost, gets=f'1 T{tier}', t_sell=v, profit_if_sold=v - cost)
F['plus_one'] = {f'{s} L{L} RF-{d}%': plus_one(s, L, d) for s in ['Gloves', '1H', '2H'] for L in (41, 60, 61, 80, 81, 99) for d in (12, 27)}
# max items with laundering (continuous greedy, BS8 loop yields) vs conversion only
def max_items(inc, use_launder, bsl=8):
    p = BS_TABLE[bsl]['refund'] / 100
    A_ = dict(t1=-19, t2=-1 + math.floor(p * 20)); B_ = dict(t1=-19, t2=-20, t3=-1 + math.floor(p * 40)); C_ = dict(t1=-19, t2=-20, t3=-20, t4=-1 + math.floor(p * 60))
    best = 0
    for N in range(1, 200):
        t = [inc[i] - N * PER_ITEM[i] for i in range(4)]
        xC = max(0, -t[3]) / C_['t4'] if use_launder else 0
        if not use_launder and t[3] < 0:
            need3 = -t[3] * 3; t[2] -= need3; t[3] = 0
        t[0] += xC * C_['t1']; t[1] += xC * C_['t2']; t[2] += xC * C_['t3']; t[3] += xC * C_['t4']
        xB = max(0, -t[2]) / B_['t3'] if use_launder else 0
        if not use_launder and t[2] < 0:
            t[1] -= -t[2] * 3; t[2] = 0
        t[0] += xB * B_['t1']; t[1] += xB * B_['t2']; t[2] += xB * B_['t3']
        if t[1] < 0:
            if use_launder:
                xA = -t[1] / A_['t2']; t[0] += xA * A_['t1']; t[1] = 0
            else:
                t[0] -= -t[1] * 3; t[1] = 0
        if t[0] < 0: break
        best = N
        gold = None
    return best
F['max_items_conversion_only'] = {k: max_items(v, False) for k, v in INC_T.items()}
F['max_items_with_laundering'] = {k: max_items(v, True) for k, v in INC_T.items()}
F['t5'] = dict(dismantle_gives_T5=False, rule='gf51 + ms18: L81+ gives T4', catchup_fee_T5_per_L81_99_item_1H_C_to_E=catchup('1H', 'Common', 'Epic', 80, 99, 1)[1][4])
R['F'] = F
