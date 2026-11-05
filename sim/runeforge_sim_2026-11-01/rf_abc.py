# Checks A (catch-up fee), B (Epic step fee), C (sell loops)
exec(open(OUT + r'\rf_core.py', encoding='utf-8').read()) if 'OUT' in dir() else None
R = {}

# ---------------- A ----------------
A = {}
def A_case(name, slot, s, e, bsl, exp_fee, exp_c=None, exp_e=None):
    c = route(slot, 'Common', s, e, bsl); ep = route(slot, 'Epic', s, e, bsl)
    fee = catchup(slot, 'Common', 'Epic', s, e, bsl)
    A[name] = dict(common=c[0], epic=ep[0], fee=fee[0], fee_mats=fee[1], exp_fee=exp_fee, exp_common=exp_c, exp_epic=exp_e,
                   route_equal=(c[0] + fee[0] == ep[0] and [a + b for a, b in zip(c[1], fee[1])] == ep[1]),
                   pass_=(fee[0] == exp_fee and (exp_c is None or c[0] == exp_c) and (exp_e is None or ep[0] == exp_e)))
A_case('1H L1-99 0%', '1H', 1, 99, 1, 26637, 8839, 35476)
A_case('1H L1-99 27%', '1H', 1, 99, 10, 19441, 6431, 25872)
A_case('2H L1-99 0%', '2H', 1, 99, 1, 39954, 13276, 53230)
A_case('2H L1-99 27%', '2H', 1, 99, 10, 29166, 9673, 38839)
A_case('1H L1-50 0%', '1H', 1, 50, 1, 8997)
A_case('1H L50-99 0%', '1H', 50, 99, 1, 17640)
A_case('Body L1-99 0%', 'Body', 1, 99, 1, 21309, 7056, 28365)
ur = catchup('1H', 'Uncommon', 'Rare', 1, 50, 1)
A['1H Unc->Rare L1-50'] = dict(fee=ur[0], fee_mats=ur[1], exp_fee=3015, exp_mats=49, pass_=(ur[0] == 3015 and sum(ur[1]) == 49))

# exhaustive route-equality: every slot, rarity pair up to Epic, every s<e, every Blacksmith level (prefix sums)
pairs = [(a, b) for a in ['Common', 'Uncommon', 'Rare', 'Epic'] for b in ['Common', 'Uncommon', 'Rare', 'Epic'] if RIDX[b] > RIDX[a]]
n_cases = 0; n_bad = 0; n_bad_tele = 0; float_diff_levels = 0; float_diff_examples = []
for slot in BASE:
    for bsl in range(1, 11):
        pre = {r: [0] * 100 for r in ['Common', 'Uncommon', 'Rare', 'Epic']}
        for r in pre:
            for t in range(2, 100):
                ex = ug(slot, r, t, bsl, True); fl = ug(slot, r, t, bsl, False)
                if ex != fl:
                    float_diff_levels += 1
                    if len(float_diff_examples) < 8: float_diff_examples.append((slot, r, t, bsl, ex, fl))
                pre[r][t] = pre[r][t - 1] + ex
            pre[r][1] = 0
        for a, b in pairs:
            for s in range(1, 99):
                for e in range(s + 1, 100):
                    n_cases += 1
                    fee = (pre[b][e] - pre[b][s]) - (pre[a][e] - pre[a][s])
                    if (pre[a][e] - pre[a][s]) + fee != (pre[b][e] - pre[b][s]):
                        n_bad += 1
        # telescoping C->U->R->E == C->E (same discount)
        for s in range(1, 99):
            e = 99
            steps = sum((pre[y][e] - pre[y][s]) - (pre[x][e] - pre[x][s]) for x, y in [('Common', 'Uncommon'), ('Uncommon', 'Rare'), ('Rare', 'Epic')])
            if steps != (pre['Epic'][e] - pre['Epic'][s]) - (pre['Common'][e] - pre['Common'][s]):
                n_bad_tele += 1
A['exhaustive'] = dict(cases=n_cases, mismatches=n_bad, telescoping_mismatches=n_bad_tele,
                       naive_double_vs_exact_level_diffs=float_diff_levels, examples=float_diff_examples)

# timing gap: fee charged at CURRENT discount, honest route paid historical discounts
def bs_needed(t):
    return min(10, max(1, math.ceil(t / 10)))
timing = {}
for slot in ['1H', '2H', 'Body', 'Gloves']:
    honest = sum(ug(slot, 'Epic', t, bs_needed(t)) for t in range(2, 100))
    commonp = sum(ug(slot, 'Common', t, bs_needed(t)) for t in range(2, 100))
    fee10 = catchup(slot, 'Common', 'Epic', 1, 99, 10)[0]
    timing[slot] = dict(honest_epic_progressive=honest, common_progressive=commonp, fee_at_BS10=fee10,
                        dodge_total=commonp + fee10, saving=honest - (commonp + fee10))
    # mid-game variant: Common to L60 at progressive BS, enchant at BS6 (needed for L60), continue Epic
    cp60 = sum(ug(slot, 'Common', t, bs_needed(t)) for t in range(2, 61))
    fee6 = catchup(slot, 'Common', 'Epic', 1, 60, 6)[0]
    ep60 = sum(ug(slot, 'Epic', t, bs_needed(t)) for t in range(2, 61))
    timing[slot]['saving_enchant_at_L60'] = ep60 - (cp60 + fee6)
A['timing_gap'] = timing

# edge: remove -> upgrade -> re-add  (rarity never drops => upgrades charged at held rarity)
def edge_remove_readd(slot, start_lvl, end_lvl):
    honest = route(slot, 'Uncommon', start_lvl, end_lvl, 1)[0]          # Common loot + T1 at start (fee 0), upgrade as Uncommon
    # trick: Remove line (rarity stays Uncommon per gf44) -> upgrade (charged Uncommon) -> re-add (no rarity change, no fee)
    trick = route(slot, 'Uncommon', start_lvl, end_lvl, 1)[0]
    # what it WOULD cost if rarity dropped on Remove (counterfactual, not the rule): Common upgrades + catch-up on re-add
    cf = route(slot, 'Common', start_lvl, end_lvl, 1)[0] + catchup(slot, 'Common', 'Uncommon', start_lvl, end_lvl, 1)[0]
    return dict(honest=honest, trick=trick, counterfactual_if_rarity_dropped_but_fee_on_readd=cf, saving=honest - trick)
A['edge_remove_readd'] = {f'{s} L{a}-{b}': edge_remove_readd(s, a, b) for s, a, b in [('1H', 20, 50), ('2H', 1, 99), ('Body', 30, 80)]}

# edge: downgrade below starting level, then enchant. Item dropped at s0 as Common, upgraded to cur as Common.
# Honest: enchant now (fee s0..cur). Trick: downgrade to d (free; start=min(s0,d)), enchant at d, re-upgrade d..cur as Epic.
def edge_downgrade(slot, s0, cur, bsl):
    sunk = route(slot, 'Common', s0, cur, bsl)
    honest = catchup(slot, 'Common', 'Epic', s0, cur, bsl)
    best = None
    for d in range(1, cur):
        st = min(s0, d)
        fee = catchup(slot, 'Common', 'Epic', st, d, bsl)
        reup = route(slot, 'Epic', d, cur, bsl)
        tot = fee[0] + reup[0]
        mats = sum(fee[1]) + sum(reup[1])
        if best is None or tot < best[0]:
            best = (tot, d, mats)
    return dict(honest_extra_gold=honest[0], honest_extra_mats=sum(honest[1]), best_trick_extra_gold=best[0], best_trick_d=best[1], best_trick_mats=best[2],
                saving=honest[0] - best[0])
dg = {}
worst = 0
for slot in ['1H', '2H', 'Gloves']:
    for s0, cur in [(1, 99), (20, 60), (50, 80), (61, 99), (1, 30)]:
        for bsl in (1, 10):
            r_ = edge_downgrade(slot, s0, cur, bsl)
            dg[f'{slot} {s0}->{cur} BS{bsl}'] = r_
            worst = max(worst, r_['saving'])
A['edge_downgrade'] = dict(cases=dg, max_saving=worst)
# existing items: starting_level = current level => zero levels => fee 0
A['edge_existing'] = dict(fee=[catchup(s, 'Common', 'Epic', L, L, 10)[0] for s in ['1H', '2H'] for L in (1, 50, 99)])
R['A'] = A

# ---------------- B ----------------
B = {}
exp = {('1H', 20): (1380, 1242, 966), ('1H', 50): (1980, 1782, 1386), ('1H', 99): (2960, 2664, 2072),
       ('2H', 20): (2070, 1863, 1449), ('2H', 50): (2970, 2673, 2079), ('2H', 99): (4440, 3996, 3108)}
tab = {}; allpass = True
for (slot, L), e in exp.items():
    got = tuple(epic_fee(slot, st, L) for st in ['Common', 'Uncommon', 'Rare'])
    ok = all(g == x for g, x in zip(got, e)); allpass &= ok
    tab[f'{slot} L{L}'] = dict(got=[str(g) for g in got], exp=e, pass_=ok)
B['table'] = tab; B['table_pass'] = allpass
# route invariance: fee depends on starting rarity only (the rule). Show what the old 'rarity before the step' rule would give
B['route'] = dict(straight=str(epic_fee('1H', 'Common', 50)), via_rare_new_rule=str(epic_fee('1H', 'Common', 50)),
                  via_rare_OLD_rule=str(epic_fee('1H', 'Rare', 50)))
# half-gold cases: gap odd -> fee x.5 (rounding not specified in gf57)
half = []
for slot in BASE:
    for st in ['Common', 'Uncommon', 'Rare']:
        for L in range(1, 100):
            f = epic_fee(slot, st, L)
            if f.denominator != 1:
                half.append((slot, st, L, str(f)))
B['half_gold_cases'] = len(half); B['half_gold_examples'] = half[:10]
B['half_gold_1H2H'] = len([h for h in half if h[0] in ('1H', '2H')])
R['B'] = B

# ---------------- C ----------------
C = {}
def sell_loop_enum(slots, discs, exact=True, old_rule=False):
    best = {}; overall = None; n = 0
    for slot in slots:
        two = slot == '2H'
        for start in ['Common', 'Uncommon', 'Rare']:
            bp0 = BUDGET[start] * (2 if two else 1)
            for target in ['Uncommon', 'Rare', 'Epic']:
                if RIDX[target] <= RIDX[start]: continue
                for L in range(1, 100):
                    for d in discs:
                        ca = cheapest_add(slot, start, target, bp0, L, d, exact)
                        if ca is None: continue
                        n += 1
                        gain = (sell(slot, target, L) - sell(slot, start, L)) if old_rule else 0
                        res = gain - ca[0] - (epic_fee(slot, start, L) if target == 'Epic' else 0)
                        k = (slot, start, target)
                        if k not in best or res > best[k][0]:
                            best[k] = (res, L, d, ca[1])
                        if overall is None or res > overall[0]:
                            overall = (res, slot, start, target, L, d, ca[1])
    return n, best, overall
n, best, overall = sell_loop_enum(['1H', '2H'], [0, 18, 21, 27])
C['cases_1H2H'] = n
C['best_by_route'] = {f'{k[0]} {k[1]}->{k[2]}': dict(result=str(v[0]), L=v[1], disc=v[2], adds=v[3]) for k, v in best.items()}
C['max_1H'] = max(float(v[0]) for k, v in best.items() if k[0] == '1H'); C['max_2H'] = max(float(v[0]) for k, v in best.items() if k[0] == '2H')
n2, best2, overall2 = sell_loop_enum(list(BASE), [0, 18, 21, 27])
C['cases_all_slots'] = n2; C['max_all_slots'] = (str(overall2[0]),) + overall2[1:]
n3, best3, overall3 = sell_loop_enum(['1H', '2H'], [0, 18, 21, 27], old_rule=True)
C['old_rule_max'] = (str(overall3[0]),) + overall3[1:]
# upgrade-then-sell: every slot, every rarity, every level, every Blacksmith level
ub = None; ub_n = 0
for slot in BASE:
    for rar in RAR:
        for t in range(2, 100):
            for bsl in range(1, 11):
                ub_n += 1
                r_ = sell(slot, rar, t) - sell(slot, rar, t - 1) - ug(slot, rar, t, bsl)
                if ub is None or r_ > ub[0]:
                    ub = (r_, slot, rar, t - 1, t, bsl)
C['upgrade_then_sell'] = dict(cases=ub_n, best=ub)
# enchanted item upgraded then sold (sells at starting rarity, pays current rarity)
ue = None
for slot in BASE:
    for st, cur in [('Common', 'Uncommon'), ('Common', 'Epic'), ('Rare', 'Epic')]:
        for t in range(2, 100):
            r_ = sell(slot, st, t) - sell(slot, st, t - 1) - ug(slot, cur, t, 10)
            if ue is None or r_ > ue[0]: ue = (r_, slot, st, cur, t)
C['enchanted_upgrade_then_sell_best'] = ue
# buy from shop -> enchant -> sell
bb = None; bb_n = 0
for slot in BASE:
    two = slot == '2H'
    for start in ['Common', 'Uncommon', 'Rare', 'Epic', 'Exalted']:
        for L in range(1, 100):
            # sell straight back
            r0 = sell(slot, start, L) - shop(slot, start, L)
            bb_n += 1
            if bb is None or r0 > bb[0]: bb = (r0, slot, start, 'no enchant', L)
            if start in ('Epic', 'Exalted'): continue
            for target in ['Uncommon', 'Rare', 'Epic']:
                if RIDX[target] <= RIDX[start]: continue
                ca = cheapest_add(slot, start, target, BUDGET[start] * (2 if two else 1), L, 27)
                if ca is None: continue
                bb_n += 1
                r_ = sell(slot, start, L) - shop(slot, start, L) - ca[0] - (epic_fee(slot, start, L) if target == 'Epic' else 0)
                if r_ > bb[0]: bb = (r_, slot, start, target, L)
C['buy_enchant_sell'] = dict(cases=bb_n, best=(str(bb[0]),) + bb[1:])
C['pass'] = (overall2[0] < 0 and ub[0] < 0 and bb[0] < 0)
R['C'] = C
