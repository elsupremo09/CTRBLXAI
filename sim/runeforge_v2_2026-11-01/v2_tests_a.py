# T1-T6, T10, T19 + gold-loop sweep.  exec(open(v2_core.py).read()) first.
RES = {}
rng = random.Random(SEED)
SLOTS4 = ['1H', '2H', 'Body', 'Gloves']

def straight_total(slot, purchases, final_rar, F=1):
    it = new_item(slot, 'Common', F)
    for to, b in purchases: it.upgrade(to, b)
    it.forge(final_rar)
    return it.gold

# ---------- T1 ----------
T1 = {}
need = [(t, bs_needed(t)) for t in range(2, 100)]
def compress(p):
    out = []
    for t, b in p:
        if out and out[-1][1] == b: out[-1] = (t, b)
        else: out.append((t, b))
    return out
P_need = compress(need); P_10 = [(99, 10)]
for slot in SLOTS4:
    r = {}
    for nm, P in (('needed', P_need), ('BS10', P_10)):
        totals = {}
        for when in ('early L1', 'mid L50', 'late L99'):
            it = new_item(slot, 'Common', 1)
            fl = {'early L1': 1, 'mid L50': 50, 'late L99': 99}[when]
            if fl == 1: it.forge('Epic')
            for to, b in P:
                if it.level < fl < to:
                    it.upgrade(fl, b); it.forge('Epic')
                it.upgrade(to, b)
                if it.level == fl and it.rar != 'Epic': it.forge('Epic')
            if it.rar != 'Epic': it.forge('Epic')
            totals[when] = it.gold
        r[nm] = totals
    it = new_item(slot, 'Common', 1)
    for to, b in P_need: it.upgrade(to, b)
    r['catchup_at_99_needed'] = paid(it.C(), 40) - paid(it.C(), 10)
    r['common_total_needed'] = it.gold
    r['forge_fee_epic_RF1'] = forge_fee(slot, 'Epic', 1)
    T1[slot] = r
T1['expected'] = {'needed': [29596, 44395, 23677, 14798], 'BS10': [25926, 38889, 20740, 12963], 'catchup_1H': 22197}
T1['PASS'] = all(len(set(T1[s][k].values())) == 1 for s in SLOTS4 for k in ('needed', 'BS10')) and \
    [T1[s]['needed']['early L1'] for s in SLOTS4] == T1['expected']['needed'] and \
    [T1[s]['BS10']['early L1'] for s in SLOTS4] == T1['expected']['BS10'] and T1['1H']['catchup_at_99_needed'] == 22197
# random equality: never-downgraded routes, BS level rising randomly, forge steps at random points
mism = 0; n = 0; maxdiff = 0
for k in range(6000):
    slot = rng.choice(list(BASE)); F = rng.randint(1, 60)
    # purchase plan
    lv = F; b = rng.randint(1, 10); plan = []
    while lv < 99:
        b = min(10, b + (1 if rng.random() < 0.3 else 0))
        to = min(99, lv + rng.randint(1, 15)); plan.append((to, b)); lv = to
    start = rng.choice(['Common', 'Uncommon', 'Rare'])
    path = RAR[RIDX[start] + 1: RIDX['Epic'] + 1]
    tots = set()
    for rep in range(4):
        it = new_item(slot, start, F)
        steps = list(path)
        pos = sorted(rng.randint(0, len(plan)) for _ in steps)
        for i, (to, bb) in enumerate(plan):
            while steps and pos[0] == i: it.forge(steps.pop(0)); pos.pop(0)
            it.upgrade(to, bb)
        while steps: it.forge(steps.pop(0))
        tots.add(it.gold)
    ref = new_item(slot, start, F)
    for to, bb in plan: ref.upgrade(to, bb)
    final_value = paid(ref.C(), 40) - 0   # never-downgraded: total = Paid(C, Epic) - Paid(0)
    n += 1
    if len(tots) != 1 or list(tots)[0] != final_value: mism += 1; maxdiff = max(maxdiff, max(abs(x - final_value) for x in tots))
T1['random_routes'] = dict(routes=n, orders_per_route=4, mismatches=mism, max_diff=maxdiff)
T1['PASS'] = T1['PASS'] and mism == 0
RES['T1'] = T1

# ---------- T2 ----------
T2 = {}
P_mix = [(50, 5), (99, 10)]
for slot in SLOTS4:
    vals = {}
    for fl in (1, 50, 99):
        it = new_item(slot, 'Common', 1)
        if fl == 1: it.forge('Epic')
        it.upgrade(50, 5)
        if fl == 50: it.forge('Epic')
        it.upgrade(99, 10)
        if fl == 99: it.forge('Epic')
        vals[f'forge L{fl}'] = it.gold
    # step-by-step Common->Uncommon->Rare->Epic at L10/L40/L80
    it = new_item(slot, 'Common', 1)
    it.upgrade(10, 1); it.forge('Uncommon'); it.upgrade(40, 4); it.forge('Rare'); it.upgrade(50, 5); it.upgrade(80, 10); it.forge('Epic'); it.upgrade(99, 10)
    vals['steps C>U@10 >R@40 >E@80 (BS1,4,5,10)'] = it.gold
    ref = new_item(slot, 'Common', 1); ref.upgrade(10, 1); ref.upgrade(40, 4); ref.upgrade(50, 5); ref.upgrade(99, 10); ref.forge('Epic')
    vals['same purchases, forge at end'] = ref.gold
    T2[slot] = vals
T2['expected_1H_mixed'] = 27725
T2['PASS'] = T2['1H']['forge L1'] == T2['1H']['forge L50'] == T2['1H']['forge L99'] == 27725 and \
    all(T2[s]['steps C>U@10 >R@40 >E@80 (BS1,4,5,10)'] == T2[s]['same purchases, forge at end'] for s in SLOTS4) and \
    all(len({T2[s]['forge L1'], T2[s]['forge L50'], T2[s]['forge L99']}) == 1 for s in SLOTS4)
# gf13 note: an Epic can only be levelled at Blacksmith >= L5, so "enchant at L1, level at needed discount" is not playable
it = new_item('1H', 'Epic', 1)
for to, b in P_need: it.upgrade(to, max(b, BS_UNLOCK['Epic']))
T2['note_epic_early_with_gf13_BS5_minimum'] = it.gold
RES['T2'] = T2

# ---------- T3 ----------
T3 = {}
def ex(variant, mode):
    it = new_item('1H', 'Common', 1, variant)
    if mode == 'early': it.forge('Epic')
    it.upgrade(60, 6); it.downgrade(30, 6)
    if mode == 'middle': it.forge('Epic')
    it.upgrade(60, 10)
    if mode == 'late': it.forge('Epic')
    return it.gold, it.merc
st = new_item('1H', 'Common', 1); st.upgrade(30, 6); st.upgrade(60, 10); st.forge('Epic')
T3['example'] = {m: ex('exact', m) for m in ('early', 'middle', 'late')}
T3['example']['straight'] = (st.gold, st.merc)
T3['example']['D2 (old)'] = {m: ex('D2', m) for m in ('early', 'middle', 'late')}
T3['example']['reset (control)'] = {m: ex('reset', m) for m in ('early', 'middle', 'late')}
T3['expected'] = dict(early=20891, middle=14420, late=14420, straight=12262, D2_late=15333, reset_up_to=-13500)

def random_route(variant, r):
    slot = r.choice(list(BASE)); start = r.choice(['Common', 'Uncommon', 'Rare', 'Epic'])
    F = r.choice([1, 1, 1, r.randint(1, 80)])
    it = new_item(slot, start, F, variant)
    bsl = r.randint(1, 10); downs = 0
    for _ in range(r.randint(3, 30)):
        op = r.random()
        cap = 99 if bsl == 10 else bsl * 10
        if op < 0.15 and bsl < 10: bsl += 1
        elif op < 0.55:
            if it.level < cap and bsl >= BS_UNLOCK[it.rar]:
                it.upgrade(r.randint(it.level + 1, cap), bsl)
        elif op < 0.80:
            if it.level > 1:
                it.downgrade(r.randint(1, it.level - 1), bsl); downs += 1
        else:
            if it.rar != 'Epic':
                it.forge(RAR[r.randint(RIDX[it.rar] + 1, RIDX['Epic'])])
    # straight route: same final record (held levels at their purchase discounts), same rarity, no downgrade
    Fs, ps = it.shadow_state()
    C_final = it._C_of(Fs, ps)
    straight_same_record = paid(C_final, R10[it.rar])
    # straight route from the ORIGINAL arrival level (levels below F_orig free)
    ps2 = []; lo = F
    for hi, b in ps:
        if hi > F: ps2.append((hi, b))
    C2 = it._C_of(F, ps2) if it.level >= F else 0
    straight_orig = paid(C2, R10[it.rar])
    merc_straight = it.level - Fs
    return dict(gap=it.gold - straight_same_record, gap_orig=it.gold - straight_orig, merc_gap=it.merc - merc_straight,
                downs=downs, pairs=it.max_pairs, slot=slot, F_ok=(Fs <= F))
for variant, N in (('exact', 20000), ('D2', 20000), ('reset', 20000)):
    r = random.Random(SEED + {'exact': 1, 'D2': 2, 'reset': 3}[variant])
    gaps = []; gaps_o = []; mg = []; maxp = 0; withdown = 0; fok = True
    for k in range(N):
        d = random_route(variant, r)
        if d['downs'] == 0: continue
        withdown += 1; gaps.append(d['gap']); gaps_o.append(d['gap_orig']); mg.append(d['merc_gap']); maxp = max(maxp, d['pairs']); fok &= d['F_ok']
    T3[f'random_{variant}'] = dict(routes=N, routes_with_downgrade=withdown, min_gold_gap_vs_same_record=min(gaps), min_gold_gap_vs_original_arrival=min(gaps_o),
                                  routes_cheaper=sum(1 for g in gaps if g < 0), min_merc_gap=min(mg), max_pairs=maxp, F_lowered_ok=fok)
# reset control: targeted worst case
best = 0; bestroute = None
for slot in SLOTS4:
    for top in (60, 80, 99):
        it = new_item(slot, 'Common', 1, 'reset'); it.upgrade(top, 10); it.downgrade(top - 1, 10); it.upgrade(top, 10); it.forge('Epic')
        stx = new_item(slot, 'Common', 1); stx.upgrade(top, 10); stx.forge('Epic')
        if stx.gold - it.gold > best: best = stx.gold - it.gold; bestroute = f'{slot} Common L1->{top} at BS10, down 1, up 1, forge Epic'
T3['reset_targeted'] = dict(saving=best, route=bestroute)
e = T3['example']
T3['PASS'] = (e['early'][0], e['middle'][0], e['late'][0], e['straight'][0]) == (20891, 14420, 14420, 12262) and \
    T3['random_exact']['routes_cheaper'] == 0 and T3['random_exact']['min_merc_gap'] >= 0 and T3['random_exact']['max_pairs'] <= 10 and \
    T3['random_D2']['routes_cheaper'] == 0 and T3['random_reset']['routes_cheaper'] > 0
RES['T3'] = T3

# ---------- T4 rounding ----------
T4 = {}
for slot in BASE:
    for rar in ('Common', 'Epic'):
        it = new_item(slot, rar, 1)
        per = 0
        for t, b in need:
            per += credit(slot, t, b) * R10[rar] // 250000
            it.upgrade(t, b)
        T4[f'{slot} {rar}'] = dict(running=it.gold, per_level=per, diff=it.gold - per)
T4['expected'] = {'1H Common': 52, '1H Epic': 48}
T4['PASS'] = T4['1H Common']['diff'] == 52 and T4['1H Epic']['diff'] == 48
RES['T4'] = T4

# ---------- T19 crystal steps ----------
T19 = {f'{a}->{b}': forge_crystals(a, b) for a, b in [('Common', 'Uncommon'), ('Common', 'Rare'), ('Common', 'Epic'), ('Uncommon', 'Epic'), ('Rare', 'Epic')]}
T19['steps C>U>R>E'] = forge_crystals('Common', 'Uncommon') + forge_crystals('Uncommon', 'Rare') + forge_crystals('Rare', 'Epic')
T19['Rare swap + T4 -> Epic'] = forge_crystals('Rare', 'Epic')
T19['keep U/R/E'] = [forge_crystals(r, r) for r in ('Uncommon', 'Rare', 'Epic')]
T19['PASS'] = [T19[k] for k in ['Common->Uncommon', 'Common->Rare', 'Common->Epic', 'Uncommon->Epic', 'Rare->Epic']] == [3, 9, 21, 18, 12] and \
    T19['steps C>U>R>E'] == 21 and T19['Rare swap + T4 -> Epic'] == 12 and T19['keep U/R/E'] == [2, 4, 8]
T19['note_fee_one_forge_vs_steps_1H_RF1'] = dict(one=forge_fee('1H', 'Epic', 1), steps=forge_fee('1H', 'Uncommon', 1) + forge_fee('1H', 'Rare', 1) + forge_fee('1H', 'Epic', 1))
RES['T19'] = T19

# ---------- T6 mercury ----------
best = None
for s in range(1, 99):
    for e2 in range(s + 1, 100):
        net = dis_merc(e2) - dis_merc(s) - (e2 - s)
        if best is None or net > best[0]: best = (net, s, e2)
RES['T6'] = dict(best_net_mercury=best[0], at=f'L{best[1]}->L{best[2]}', cases=sum(range(1, 99)), PASS=best[0] <= 0)

# ---------- gold-loop sweep (T5 + item 3) ----------
GL = {}
SHOP_RAR = ['Common', 'Uncommon', 'Rare', 'Epic', 'Exalted']
worst = dict(buy_dismantle=None, buy_sell=None, buy_up_sell=None, loot_up_sell=None, forge_sell=None)
def upd(k, v, d):
    if worst[k] is None or v > worst[k][0]: worst[k] = (v, d)
cases = 0
for slot in BASE:
    for rar in SHOP_RAR:
        for L in range(1, 100):
            p = shop(slot, rar, L)
            upd('buy_dismantle', -p, (slot, rar, L)); upd('buy_sell', sell(slot, rar, L) - p, (slot, rar, L)); cases += 2
    for rar in RAR[:7]:
        if rar not in BS_UNLOCK: continue
        for L in range(1, 99):
            for b in (BS_UNLOCK[rar], 10):
                cap = 99 if b == 10 else b * 10
                for e2 in (L + 1, min(cap, L + 10), cap):
                    if e2 <= L or e2 > cap: continue
                    it = new_item(slot, rar, L); g = it.upgrade(e2, b)
                    d = sell(slot, rar, e2) - sell(slot, rar, L) - g
                    upd('loot_up_sell', d, (slot, rar, L, e2, b)); cases += 1
                    if rar in SHOP_RAR:
                        upd('buy_up_sell', sell(slot, rar, e2) - g - shop(slot, rar, L), (slot, rar, L, e2, b)); cases += 1
    for st_ in ('Common', 'Uncommon', 'Rare'):
        for L in (1, 50, 99):
            for rfl in (1, 10):
                fee = forge_fee(slot, 'Epic', rfl)
                upd('forge_sell', -fee, (slot, st_, L, rfl)); cases += 1
GL['worst'] = worst; GL['cases'] = cases
GL['note'] = 'Mercury/crystals/gems/sulfur cannot be sold (draft 1.5, 3.1, 6.1); dismantle gives no gold; forged items sell at starting rarity (ef14).'
GL['PASS'] = all(v[0] < 0 for v in worst.values())
RES['GOLD_LOOPS'] = GL
RES['T5'] = dict(gold_back=0, worst_loss=worst['buy_dismantle'], PASS=worst['buy_dismantle'][0] < 0)

# ---------- T10 gem transfer ----------
T10 = {}
for a, b in [('Common', 'Uncommon'), ('Uncommon', 'Rare'), ('Rare', 'Epic'), ('Common', 'Epic')]:
    T10[f'{a}->{b} forge then dismantle (crystals)'] = DIS_CRY[b] - forge_crystals(a, b)
    T10[f'{a}->{b} vs dismantling unforged (crystals)'] = DIS_CRY[b] - forge_crystals(a, b) - DIS_CRY[a]
T10['gems'] = 'install k gems -> dismantle returns the same k (+ the item own lines); a swap destroys the replaced line: net gems <= 0 per cycle'
T10['sulfur_reroll_then_dismantle'] = {r: -c for r, c in {'Exalted': 1, 'Legendary': 2, 'Mythic': 3, 'Transcendent': 4}.items()}
T10['PASS'] = all(v < 0 for k, v in T10.items() if 'crystals' in k)
T10['expected'] = {'C>U': -2, 'U>R': -4, 'R>E': -9, 'C>E': -18}
RES['T10'] = T10
