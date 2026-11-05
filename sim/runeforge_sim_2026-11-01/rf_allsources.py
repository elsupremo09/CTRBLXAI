# CTRBLXAI - ALL-SOURCES DISMANTLE impact check (2026-11-01, design verification only, nothing built)
# New user ruling (not yet in DB): every dismantled item gives resources, whatever its source
# (Shop, Black Market, Starter, Recruit, Loot, Debug). Replaces gf51/gf57 "shop-bought -> nothing".
# Reuses rf_core / rf_econ / rf_supply and the provenance block of rf_recheck (first-run files untouched).
# Writes results_allsources.json only.
import os, json, math, itertools
from fractions import Fraction as Fr
OUT = r'D:\AI\Projects\CTRBLXAI\sim\runeforge_sim_2026-11-01'
_src = open(OUT + r'\rf_recheck.py', encoding='utf-8').read()
# DB wording changed after the re-check (logged in results): match the current rule text
TEXT_CHANGES = [("'the T5 part comes back as T4 (never T5)'", "'the T5 part comes back as T4 (never T5'", 'materials_system 42: "(never T5)" -> "(never T5; kept by USER DECISION 2026-11-01)"')]
for a_, b_, _n in TEXT_CHANGES:
    assert a_ in _src
    _src = _src.replace(a_, b_)
exec(_src.split('# ===================== X2 upgrade -> dismantle -> sell =====================')[0])   # core + econ + supply + 16 rule checks + DB delta + dis2 (no file writes)
RCJ = json.load(open(OUT + r'\results_recheck.json'))
PRE = {}
for slot in BASE:
    for rar in RAR:
        for b in range(1, 11):
            p = [0] * 100
            for t in range(2, 100): p[t] = p[t - 1] + ugb(slot, rar, t, b)
            PRE[(slot, rar, b)] = p
A = {}
def provA(name, table, rid, must, col='rule'):
    t = con.execute(f'select {col} from {table} where id=?', (rid,)).fetchone()[0] or ''
    ok = all(m in t for m in must)
    PROV2[name] = dict(table=table, row=rid, col=col, found=ok)
    if not ok: raise RuntimeError(f'PROVENANCE FAIL {name}: {table} {rid} missing {[m for m in must if m not in t]}')
    return t
provA('Shop markup', 'economy_framework', 15, ['round(Base Value', '×4.0 for Common, Uncommon and Rare', '×6.0 for Epic and Exalted'])
provA('Shop odds', 'economy_framework', 48, ['5, 5, 6, 7, 7, 8, 9, 10, 10, 10', 'L9 C15 U35 R35 Epic 15', 'L10 C10 U30 R40 E15 Exalted 5', 'Item level rolls at the current Map Level ceiling'])
provA('Shelf refresh', 'guild_facilities', 15, ['Stock refreshes every 5 completed battles', 'L2 Uncommon, L5 Rare, L9 Epic, L10 Exalted'])
provA('Material sell', 'materials_system', 28, ['T1 = 5g, T2 = 15g, T3 = 40g, T4 = 100g, T5 = 250g', 'Essences cannot be sold'])
provA('Trade-up', 'guild_facilities', 53, ['L6: Essence trade-up (3 lower -> 1 higher)'])
provA('BS extraction table', 'guild_facilities', 50, ['L1: 10 / 10 / 0% / Uncommon / 25%', 'L4: 40 / 40 / 9% / Rare / 30%', 'L7: 70 / 70 / 18% / Epic / 40%'])
provA('Dismantle rule (shop clause REPLACED by ruling)', 'guild_facilities', 51, ['Essences = 1 per bonus line', 'tiers 1-2 Uncommon, tier 3 Rare, tier 4+ Epic', 'Shop-bought items give nothing'])
provA('Dismantle limits', 'guild_facilities', 52, ['Cannot dismantle: equipped items', 'Unique items', 'keep-a-weapon rule is never at risk'])
provA('Hire fee', 'economy_framework', 22, ['200 + (Unit Level × 15) + Quality Premium', 'Quality = +300, Elite = +800'])
provA('Dismissal', 'economy_framework', 49, ['5 × recruitment cost', 'unequipped back to inventory first'])
provA('Rarity budgets', 'item_rarity_rules', 2, ['Uncommon 100; Rare 150; Epic 200; Exalted 225'], col='rule_value') if False else None
_t = con.execute("select rule_value from item_rarity_rules where id=2").fetchone()[0]
assert 'Uncommon 100; Rare 150; Epic 200; Exalted 225' in _t and 'Uncommon 200 / Rare 300 / Epic 400 / Exalted 450' in _t
PROV2['Rarity budgets'] = dict(table='item_rarity_rules', row=2, col='rule_value', found=True)
BANDS = {r[0]: r[1] for r in con.execute('select rarity, valid_band from item_rarity_framework')}
_bm = con.execute('select col_7, col_9 from objects_encounters where rowid=31').fetchone()
assert 'six fixed discounted high-tier items' in _bm[0]
PROV2['Black Market (DB)'] = dict(table='objects_encounters', row=31, col='col_7', found=True)
_od = con.execute("select * from open_decisions where rowid=48").fetchone()
A['_blocker_object_density'] = ' | '.join(str(x) for x in _od if x)[:300]

SHOPR = ['Common', 'Uncommon', 'Rare', 'Epic', 'Exalted']
ODDS = {}
t48 = con.execute('select rule from economy_framework where id=48').fetchone()[0]
for lv, body in re.findall(r'L(\d+) ((?:(?:Common|Uncommon|Rare|Epic|Exalted|C|U|R|E)\s?\d+[, ]*)+)', t48):
    d = {}
    for k, v in re.findall(r'(Common|Uncommon|Rare|Epic|Exalted|C|U|R|E)\s?(\d+)', body):
        k = {'C': 'Common', 'U': 'Uncommon', 'R': 'Rare', 'E': 'Epic'}.get(k, k); d[k] = int(v) / 100
    ODDS[int(lv)] = d
assert sorted(ODDS) == list(range(1, 11)) and all(abs(sum(v.values()) - 1) < 1e-9 for v in ODDS.values()), ODDS
SLOTS_M = [5, 5, 6, 7, 7, 8, 9, 10, 10, 10]
# shop pool (MerchantService.GetStock L367-378: weapons + off-hands + armor archetypes, uniform pick; counts read from WeaponData/ArmorData)
POOL = {'1H': 18, '2H': 20, 'Off-Hand': 7, 'Gloves': 21, 'Head': 20, 'Body': 20, 'Feet': 20, 'Accessory': 20}
NPOOL = sum(POOL.values())
MAT_V = SELLV
def mlvl(L): return max(1, math.floor(L))
def plus1_val(rar, L): return MAT_V[band_tier(L) - 1] if RIDX[rar] >= RIDX['Rare'] else 0
CAPI = {'Uncommon': 0, 'Rare': 1, 'Epic': 2}
def capv(u, r, e, cap):
    if cap == 'Uncommon': return (u + r + e, 0, 0)
    if cap == 'Rare': return (u, r + e, 0)
    return (u, r, e)
def ueq(v): return v[0] + 3 * v[1] + 9 * v[2]

# ---------- legal line compositions (best case, incl. 1 passive / 2 on 2H) ----------
PAS = sorted(set(con.execute('select bp_cost, minimum_rarity from bonus_passives').fetchall()))
def band_of(rar, two):
    lo, hi = [int(x) for x in re.findall(r'\d+', BANDS[rar])]
    return (lo * 2, hi * 2) if two else (lo, hi)
TMIN = {1: 'Uncommon', 2: 'Uncommon', 3: 'Rare', 4: 'Epic'}
def comps(rar, two):
    lo, hi = band_of(rar, two); out = []
    tiers = [t for t in (1, 2, 3, 4) if RIDX[TMIN[t]] <= RIDX[rar]]
    pas = [p for p in PAS if p[1] in RIDX and RIDX[p[1]] <= RIDX[rar]]
    pas_sets = [()] + [(p,) for p in pas] + ([tuple(c) for c in itertools.combinations_with_replacement(pas, 2)] if two else [])
    for ps in pas_sets:
        pb = sum(p[0] for p in ps)
        for n in itertools.product(*[range(0, hi // (50 * t) + 1) for t in tiers]):
            nn = dict(zip(tiers, n)); bp = pb + sum(50 * t * k for t, k in nn.items())
            if not (lo <= bp <= hi) or sum(n) + len(ps) == 0 or sum(n) > 25: continue
            u = nn.get(1, 0) + nn.get(2, 0) + sum(1 for p in ps if p[1] == 'Uncommon')
            r = nn.get(3, 0) + sum(1 for p in ps if p[1] == 'Rare'); e = nn.get(4, 0) + sum(1 for p in ps if p[1] == 'Epic')
            out.append(((u, r, e), nn, ps, bp))
    if not out:   # closest valid lower total, numeric only (item_rarity_rules 14)
        best = None
        for n in itertools.product(*[range(0, hi // (50 * t) + 1) for t in tiers]):
            nn = dict(zip(tiers, n)); bp = sum(50 * t * k for t, k in nn.items())
            if bp <= hi and (best is None or bp > best): best = bp
        for n in itertools.product(*[range(0, hi // (50 * t) + 1) for t in tiers]):
            nn = dict(zip(tiers, n)); bp = sum(50 * t * k for t, k in nn.items())
            if bp == best: out.append(((nn.get(1, 0) + nn.get(2, 0), nn.get(3, 0), nn.get(4, 0)), nn, (), bp))
    return out
COMPS = {(r, two): comps(r, two) for r in SHOPR[1:] for two in (False, True)}
A['max_lines_per_item'] = {f'{r}{" 2H" if two else ""}': max(sum(c[0]) for c in COMPS[(r, two)]) for r in SHOPR[1:] for two in (False, True)}
# expected Essences per item (uniform over numeric tier partitions - same working assumption as the first run, line_profile)
def exp_lines(rar, two): return line_profile(rar, two) if rar != 'Common' else (0, 0, 0)

# ======================= 1. GOLD LOOPS =======================
L1 = {}
# 1a buy -> dismantle (never upgraded) -> sell materials ; and dismantle-vs-sell of the bought item
best = None; best_vs_sell = None; n = 0; pos = 0
for slot in BASE:
    for rar in SHOPR:
        for L in range(1, 100):
            for b in range(1, 11):
                d = dis2(rar, rar, L, L, b); v = val(d); n += 1
                pr = v - shop(slot, rar, L)
                if pr > 0: pos += 1
                if best is None or pr > best[0]: best = (pr, slot, rar, L, b, d)
                g = v - sell(slot, rar, L)
                if best_vs_sell is None or g > best_vs_sell[0]: best_vs_sell = (g, slot, rar, L, b, v, sell(slot, rar, L))
L1['buy_dismantle_sell'] = dict(cases=n, profitable=pos, best=best, best_dismantle_minus_sell_of_same_item=best_vs_sell)
# 1b buy -> upgrade (s->e) -> dismantle -> sell materials ; and buy -> upgrade -> sell item
DV = {}
for rar in SHOPR:
    for s in range(1, 99):
        for e in range(s + 1, 100):
            vin = val(spent(rar, s, e))
            for b in range(needed_bs(e), 11):
                DV[(rar, s, e, b)] = val(dis2(rar, rar, s, e, b)) - vin
best = None; pos = 0; n = 0; best_sell = None
for slot in BASE:
    for rar in SHOPR:
        pre = {b: PRE[(slot, rar, b)] for b in range(1, 11)}
        for s in range(1, 99):
            sp = shop(slot, rar, s)
            for e in range(s + 1, 100):
                vin = val(spent(rar, s, e))
                for b in range(needed_bs(e), 11):
                    gold = pre[b][e] - pre[b][s]; n += 1
                    pr = DV[(rar, s, e, b)] - gold - sp
                    if pr > 0: pos += 1
                    if best is None or pr > best[0]: best = (pr, slot, rar, s, e, b)
                    ps = sell(slot, rar, e) - sp - gold - vin
                    if best_sell is None or ps > best_sell[0]: best_sell = (ps, slot, rar, s, e, b)
L1['buy_upgrade_dismantle_sell'] = dict(cases=n, profitable=pos, best=best)
L1['buy_upgrade_sell_item'] = dict(best=best_sell)
# 1c Black Market (code: 6 FREE Rare items at map level, ObjectEffectService L2289-2298): dismantle vs sell, per item
bm = {}
for L in (20, 40, 41, 60, 61, 80, 99):
    row_ = {}
    for slot in BASE:
        row_[slot] = dict(sell=sell(slot, 'Rare', L), dismantle_gold=plus1_val('Rare', L), extra_by_dismantling=plus1_val('Rare', L) - sell(slot, 'Rare', L))
    bm[f'L{L}'] = row_
L1['black_market_dismantle_vs_sell_per_item'] = bm
# if the Black Market is made a PAID shop (DB intent "discounted"): smallest discount that makes buy->dismantle->sell or buy->sell pay
md = None; mds = None
for slot in BASE:
    for L in range(1, 100):
        p = shop(slot, 'Rare', L); v = plus1_val('Rare', L); sv = sell(slot, 'Rare', L)
        d1 = 1 - v / p; d2 = 1 - sv / p
        if md is None or d1 < md[0]: md = (d1, slot, L, p, v)
        if mds is None or d2 < mds[0]: mds = (d2, slot, L, p, sv)
L1['paid_black_market_breakeven_discount_pct'] = dict(dismantle_route=(round(md[0] * 100, 2),) + md[1:], sell_route=(round(mds[0] * 100, 2),) + mds[1:])
# 1d enchant routes: shop items now behave exactly like loot for dismantling (X1/X2/ex7 in the re-check covered every start
# rarity / level / BS level with no purchase price) -> adding the purchase price only lowers every result
L1['enchant_routes_note'] = dict(recheck_X1_best=RCJ['X1']['best'][0], recheck_X2_best=RCJ['X2']['exhaustive']['best'][0], recheck_ex7_best_gain=RCJ['exploit_search_7']['best_downgrade_first_gain'][0])
A['1_loops'] = L1

# ======================= 4. RECRUIT =======================
REC = {}
QP = {'Standard': 0, 'Quality': 300, 'Elite': 800}
for L in (1, 25, 50, 99):
    for q, prem in QP.items():
        fee = 200 + L * 15 + prem
        w = dis2('Common', 'Common', L, L, 10)
        best_slot_sell = max(sell(s, 'Common', L) for s in ('1H', '2H'))
        REC[f'L{L} {q}'] = dict(hire=fee, dismiss=5 * fee, weapon='Common, 0 lines, never upgraded', dismantle_mats=w, dismantle_essences=0,
                               hire_then_swap_weapon_then_dismantle=-fee, hire_dismiss_dismantle=-6 * fee, hire_dismiss_sell_weapon_best=best_slot_sell - 6 * fee)
A['4_recruit'] = REC

# ======================= 2. GOLD -> ESSENCE =======================
MREQ = {'Uncommon': 2, 'Rare': 5, 'Epic': 9, 'Exalted': 10}
def net_price(slot, rar, L): return shop(slot, rar, L) - plus1_val(rar, L)
GPE = {}
for L in (20, 50, 80):
    out = {}
    for tgt in ('Uncommon', 'Rare', 'Epic'):
        cands = []
        for slot in BASE:
            two = slot == '2H'
            for rar in SHOPR[1:]:
                for v, nn, ps, bp in COMPS[(rar, two)]:
                    eff = {'Uncommon': v[0], 'Rare': v[1] + v[0] / 3, 'Epic': v[2] + v[1] / 3 + v[0] / 9}[tgt]
                    if eff <= 0: continue
                    need_bs = 7 if v[2] else 4 if v[1] else 1
                    tu = (tgt == 'Rare' and v[0] > 0) or (tgt == 'Epic' and (v[0] or v[1]))
                    cands.append((round(net_price(slot, rar, L) / eff, 1), slot, rar, {f'T{k}': c for k, c in nn.items() if c}, [p[0] for p in ps], v,
                                  f'Merchant L{MREQ[rar]}+', f'Blacksmith L{need_bs}+', 'Runeforge L6 trade-up' if tu else 'no trade-up', shop(slot, rar, L), plus1_val(rar, L)))
        cands.sort(key=lambda c: c[0])
        direct = [c for c in cands if c[8] == 'no trade-up']
        num = [c for c in cands if not c[4]]
        out[tgt] = dict(cheapest=cands[0], cheapest_without_tradeup=direct[0] if direct else None, cheapest_numeric_only=num[0])
    GPE[f'L{L}'] = out
# whole-shelf average at Merchant L10 / L9 / L5 (buy every non-Common item; expected lines), gold per U-equivalent (U=1, R=3, E=9)
def shelf(L, M, cap='Epic', shelves=1):
    items = []
    k = SLOTS_M[M - 1] * shelves
    for slot, sh in POOL.items():
        two = slot == '2H'
        for rar, od in ODDS[M].items():
            cnt = k * sh / NPOOL * od
            if rar == 'Common' or cnt == 0:
                items.append((cnt, slot, rar, (0, 0, 0), net_price(slot, rar, L), shop(slot, rar, L))); continue
            if rar == 'Exalted':
                u, r, e = exp_lines('Exalted', two)
            else:
                u, r, e = exp_lines(rar, two)
            items.append((cnt, slot, rar, capv(u, r, e, cap), net_price(slot, rar, L), shop(slot, rar, L)))
    return items
AVG = {}
for L in (20, 50, 80):
    for M in (5, 9, 10):
        it = [x for x in shelf(L, M) if x[2] != 'Common']
        g = sum(x[0] * x[4] for x in it); q = sum(x[0] * ueq(x[3]) for x in it)
        AVG[f'L{L} M{M}'] = dict(items_per_window=round(sum(x[0] for x in it), 2), ueq_per_window=round(q, 2), gold_per_window=round(g), gold_per_ueq=round(g / q, 1))
GPE['_whole_shelf_average'] = AVG
A['2_gold_per_essence'] = GPE

# ---------- lifetime purchase simulation (greedy, expected stock, gold-limited) ----------
def lvl_at_b(b): return lvl_at(b)
def fac_level(ev, name, b):
    lv = 0
    for k, (bb, _) in ev.get(name, {}).items():
        if bb <= b: lv = max(lv, int(k))
    return lv
def buy_sim(sc, budget_total, spread='income', shelves=1, ess_per_gold_only=False, normal_use=False):
    ev = E[sc]['events']
    if spread == 'after_last_facility':
        last = max(bb for f in ev.values() for (bb, _) in f.values())
        w = [INC[b] if b > last else 0 for b in range(N_B)]
    else:
        w = INC[:]
    sw = sum(w); bud = [budget_total * x / sw for x in w] if sw else [0] * N_B
    tot = [0.0, 0.0, 0.0]; spent_g = 0.0; carry = 0.0; band = [0.0, 0.0, 0.0]; per_b = [None] * N_B; nitems = 0.0
    for w0 in range(0, N_B, 5):
        carry += sum(bud[w0:w0 + 5])
        M = fac_level(ev, 'Merchant', w0); bsl = max(1, fac_level(ev, 'Blacksmith', w0))
        if M == 0: continue
        L = mlvl(lvl_at(w0)); cap = BS_TABLE[bsl]['extract']
        items = shelf(L, M, cap, shelves)
        if normal_use:   # buys the average shelf item (gear bought to use, dismantled later)
            g = sum(x[0] * x[5] for x in items); q = [sum(x[0] * x[3][i] for x in items) for i in range(3)]
            n_ = sum(x[0] for x in items)
            if g <= 0: continue
            f = carry / g
            add = [qq * f for qq in q]; spent_g += carry; carry = 0.0; nitems += n_ * f
        else:
            items = sorted([x for x in items if ueq(x[3]) > 0], key=lambda x: x[4] / ueq(x[3]))
            add = [0.0, 0.0, 0.0]
            for cnt, slot, rar, v, np_, sp in items:
                if carry <= 0: break
                take = min(cnt, carry / sp)
                carry -= take * sp; spent_g += take * sp; nitems += take
                for i in range(3): add[i] += take * v[i]
        for i in range(3): tot[i] += add[i]
        if 50 <= lvl_at(w0) < 80:
            for i in range(3): band[i] += add[i]
    return dict(budget=round(budget_total), spent=round(spent_g), unspent=round(carry), items=round(nitems, 1), U=round(tot[0], 1), R=round(tot[1], 1), E=round(tot[2], 1),
                ueq=round(tot[0] + 3 * tot[1] + 9 * tot[2], 1), count=round(sum(tot), 1), band50_80=[round(x, 1) for x in band])
NAT = G['base (0.40 items/battle, elite=boss=0.034)']
nat_drop = NAT['drop_U'] + NAT['drop_R'] + NAT['drop_E']; nat_dis = NAT['dis_U'] + NAT['dis_R'] + NAT['dis_E']
nat_ueq = NAT['drop_U'] + NAT['dis_U'] + 3 * (NAT['drop_R'] + NAT['dis_R']) + 9 * (NAT['drop_E'] + NAT['dis_E'])
FC = 'free classic (Runeforge after core 6) bsA'; BC = 'boost classic (Runeforge after core 6) bsA'
SC = {}
SC['free, facilities first (spare = leftover)'] = buy_sim(FC, E[FC]['leftover'], 'after_last_facility')
SC['free, Essence-max (all facility gold -> Essences, upper bound)'] = buy_sim(FC, E[FC]['facility_spend'] + E[FC]['leftover'])
SC['boosted, facilities first (spare = leftover)'] = buy_sim(BC, E[BC]['leftover'], 'after_last_facility')
SC['boosted, Essence-max (upper bound)'] = buy_sim(BC, E[BC]['facility_spend'] + E[BC]['leftover'])
SC['boosted, Essence-max, 6 shelves per 5-battle window (quest-level switching)'] = buy_sim(BC, E[BC]['facility_spend'] + E[BC]['leftover'], shelves=6)
NU = {}
for S in (10000, 20000, 31000):
    NU[f'normal shop gear spend {S}g (bought to use, dismantled later)'] = buy_sim(FC, S, normal_use=True)
for k, v in list(SC.items()) + list(NU.items()):
    v['share_of_essence_count_pct'] = round(100 * v['count'] / (nat_drop + nat_dis + v['count']), 1)
    v['share_of_ueq_pct'] = round(100 * v['ueq'] / (nat_ueq + v['ueq']), 1)
A['2_lifetime_purchase'] = SC
A['2_normal_use_shop_dismantle'] = NU
A['natural_lifetime'] = dict(drops=round(nat_drop, 1), loot_dismantle=round(nat_dis, 1), ueq=round(nat_ueq, 1))
# per-battle maxima
PB = {}
for L, M in ((20, 6), (50, 10), (80, 10)):
    b = min(range(N_B), key=lambda x: abs(lvl_at(x) - L))
    it = [x for x in shelf(L, M) if x[2] != 'Common']
    q = sum(x[0] * ueq(x[3]) for x in it); g = sum(x[0] * x[4] for x in it); cnt = sum(x[0] * sum(x[3]) for x in it)
    cheapest = min(x[4] / ueq(x[3]) for x in it if ueq(x[3]) > 0)
    PB[f'L{L} (Merchant L{M})'] = dict(income_per_battle=round(INC[b]), stock_limited_essences_per_battle_1_shelf=round(cnt / 5, 2), stock_limited_ueq_per_battle=round(q / 5, 2),
        stock_limited_essences_per_battle_6_shelves=round(cnt * 6 / 5, 2), gold_to_buy_whole_shelf=round(g), whole_shelf_in_battles_of_income=round(g / INC[b], 1),
        gold_limited_U_per_battle_all_income_cheapest=round(INC[b] / cheapest, 2), natural_ess_per_battle=NAT['per_battle'])
A['2_per_battle'] = PB

# ======================= 3. LOCKED TARGETS =======================
T = {}
T['essence_split'] = dict(previous=dict(drops_pct=NAT['drop_share_pct'], dismantle_pct=round(100 - NAT['drop_share_pct'], 1)))
for k, v in list(NU.items())[1:2] + list(SC.items()):
    tot = nat_drop + nat_dis + v['count']
    T['essence_split'][k] = dict(drops_pct=round(100 * nat_drop / tot, 1), loot_dismantle_pct=round(100 * nat_dis / tot, 1), shop_pct=round(100 * v['count'] / tot, 1))
# drops vs ALL dismantling incl. normal-use shop gear (the locked 25/75 target counts dismantling of any item)
nu = list(NU.values())[1]
T['essence_split']['drops vs all dismantling (normal use 20k)'] = dict(drops_pct=round(100 * nat_drop / (nat_drop + nat_dis + nu['count']), 1))
# battles to fill, band L50-80
bd = NAT['band_50_80']; nb_ = bd['battles']
def fill(rU, rR, rE):
    o = {}
    for nm, (u, r, e) in {'1H Uncommon (2U)': (2, 0, 0), '1H Rare (3U)': (3, 0, 0), '1H Epic (4U)': (4, 0, 0), '1H Epic via T4 (2E)': (0, 0, 2), '2H Epic (8U)': (8, 0, 0)}.items():
        bb = max(u / rU if u else 0, r / rR if r else 0, e / rE if e else 0)
        o[nm] = dict(battles=round(bb, 1), with_tradeup=round((u + 3 * r + 9 * e) / (rU + 3 * rR + 9 * rE), 1))
    return o
T['fill_L50_80'] = {'natural only (= previous)': fill(bd['U'] / nb_, bd['R'] / nb_, bd['E'] / nb_)}
for k in ['boosted, facilities first (spare = leftover)', 'free, Essence-max (all facility gold -> Essences, upper bound)', 'boosted, Essence-max (upper bound)']:
    x = SC[k]['band50_80']
    T['fill_L50_80'][k] = fill((bd['U'] + x[0]) / nb_, (bd['R'] + x[1]) / nb_, (bd['E'] + x[2]) / nb_)
x = nu['band50_80']; T['fill_L50_80']['normal use 20k'] = fill((bd['U'] + x[0]) / nb_, (bd['R'] + x[1]) / nb_, (bd['E'] + x[2]) / nb_)
# gold-only fill: buy every Essence (cheapest net price at L65, Merchant L10, BS cap Epic)
it = [x for x in shelf(65, 10) if x[2] != 'Common' and ueq(x[3]) > 0]
gU65 = min(x[4] / ueq(x[3]) for x in it)
b65 = min(range(N_B), key=lambda x: abs(lvl_at(x) - 65))
T['fill_gold_only_L65'] = dict(gold_per_ueq=round(gU65, 1), income_per_battle=round(INC[b65]),
    **{nm: dict(gold=round(n_ * gU65), battles_of_income=round(n_ * gU65 / INC[b65], 1)) for nm, n_ in {'1H Uncommon (2U)': 2, '1H Rare (3U)': 3, '1H Epic (4U)': 4, '2H Epic (8U)': 8}.items()})
# crafted Epic supply L50-80: gold vs Essence limit, with normal-use shop Essences added and with bought Essences (gold competes)
sup2 = {}
for k, v in R['D']['supply_L50_80'].items():
    if 'free classic' not in k and 'free crafter' not in k and 'free rush' not in k and 'boost' not in k: continue
    frac = (v['crafted_essence_limited'] * 4) / NAT['band_50_80']['U'] if NAT['band_50_80']['U'] else 0
    ess_extra = nu['band50_80'][0] * frac / 4
    gold_lim = v['crafted_gold_limited']; ess_lim = v['crafted_essence_limited'] + ess_extra
    # buying Essences: each crafted Epic needs 4U; extra U bought at gU(L65) competes with the 2,600g craft gold
    lux = v['window_luxury_gold'] * (frac if frac else 0)
    Uav = v['crafted_essence_limited'] * 4 + ess_extra * 4
    best_n = 0.0
    if lux > 0:
        nmax = lux / 2600
        best_n = min(nmax, (lux + Uav * gU65) / (2600 + 4 * gU65)) if 4 * nmax > Uav else nmax
    sup2[k] = dict(previous=v['crafted_max'], gold_limited=gold_lim, essence_limited_now=round(ess_lim, 1), with_bought_essences=round(best_n, 1), natural=v['natural_epic'])
T['crafted_epic_L50_80'] = sup2
# facility economy / pressure: unchanged unless gold is diverted; normal-use dismantle swaps the item's sell value for its +1 material
T['facilities'] = {k: v for k, v in RCJ['L6']['facilities'].items()}
# material wall: buying Rare+ shop items for the +1 (T3 at L41-60, T4 at L61-99)
cheap = {}
for tier, Ls in ((1, range(1, 21)), (2, range(21, 41)), (3, range(41, 61)), (4, range(61, 100))):
    c = min((shop(s, r, L), s, r, L) for s in BASE for r in ('Rare', 'Epic', 'Exalted') for L in Ls)
    cheap[f'T{tier}'] = dict(gold=c[0], item=f'{c[2]} {c[1]} L{c[3]}', vs_conversion=None)
cheap['T4']['vs_conversion'] = f"3 T3 -> 1 T4 = {3 * cheap['T3']['gold']}g"
per_item = 25.5 * cheap['T3']['gold'] + 25.5 * cheap['T4']['gold']
T['wall'] = dict(previous=dict(no_dismantle=[12, 13], with_dismantle='12-15 (14-16 with conversion)'), gold_per_bought_material=cheap,
                 gold_per_extra_item_T3_T4=round(per_item), extra_items_boosted_leftover=[round(E[k]['leftover'] / per_item, 2) for k in (BC, 'boost rush (Guild Hall + Runeforge first) bsA')],
                 extra_items_free_leftover=round(E[FC]['leftover'] / per_item, 3), extra_items_boosted_all_luxury=round((E[BC]['facility_spend'] + E[BC]['leftover']) / per_item, 2))
A['3_targets'] = T

# ======================= 5. BLACK MARKET + STARTER/DEBUG =======================
BMk = {}
sh2 = POOL['2H'] / NPOOL
for L in (20, 50, 80):
    for cap in ('Uncommon', 'Rare', 'Epic'):
        u1, r1, e1 = capv(*exp_lines('Rare', False), cap); u2, r2, e2 = capv(*exp_lines('Rare', True), cap)
        eu = 6 * ((1 - sh2) * u1 + sh2 * u2); er = 6 * ((1 - sh2) * r1 + sh2 * r2)
        sellv = sum(POOL[s] / NPOOL * sell(s, 'Rare', L) for s in POOL) * 6
        matv = 6 * plus1_val('Rare', L)
        gold_best = sum(POOL[s] / NPOOL * max(sell(s, 'Rare', L), plus1_val('Rare', L)) for s in POOL) * 6
        BMk[f'L{L} BS-cap {cap}'] = dict(essences_U=round(eu, 1), essences_R=round(er, 1), max_essences_all_2H_6xT1=36 if cap != 'x' else None, max_1H_type=18,
                                          materials=f"6 x T{band_tier(L)}", materials_sell=matv, sell_all_6=round(sellv), best_gold_mixing=round(gold_best))
BMk['_note'] = 'code (ObjectEffectService L2289-2298): 6 FREE Rare items per Black Market object per battle, item level = map level, archetype pool nil; DB objects_encounters 31: "six fixed discounted high-tier items" (no discount number). Lifetime needs object density (open_decisions 48 - not decided).'
life = {}
avg_ess = sum(BMk[f'L{L} BS-cap Epic']['essences_U'] + BMk[f'L{L} BS-cap Epic']['essences_R'] for L in (20, 50, 80)) / 3
avg_ueq = sum(BMk[f'L{L} BS-cap Epic']['essences_U'] + 3 * BMk[f'L{L} BS-cap Epic']['essences_R'] for L in (20, 50, 80)) / 3
for rate in (0.02, 0.05, 0.1, 0.25):
    nE = rate * N_B
    life[f'{rate} events/battle'] = dict(events=round(nE, 1), essences=round(nE * avg_ess), ueq=round(nE * avg_ueq), materials=round(nE * 6),
                                         share_of_count_pct=round(100 * nE * avg_ess / (nat_drop + nat_dis + nE * avg_ess), 1))
BMk['lifetime_by_assumed_rate'] = life
# Black Market effect on the locked targets, by assumed event rate (object density not decided)
bmT = {}
e50 = BMk['L50 BS-cap Epic']; uB, rB = e50['essences_U'], e50['essences_R']
n41 = sum(1 for b in range(N_B) if 41 <= lvl_at(b) < 61); n61 = sum(1 for b in range(N_B) if lvl_at(b) >= 61)
for rate in (0.02, 0.05, 0.1, 0.25):
    life_cnt = life[f'{rate} events/battle']['essences']
    fl_ = fill((bd['U'] + uB * rate * nb_) / nb_, (bd['R'] + rB * rate * nb_) / nb_, bd['E'] / nb_)
    t3 = 6 * rate * n41; t4 = 6 * rate * n61
    bmT[f'{rate} events/battle'] = dict(drops_share_pct=round(100 * nat_drop / (nat_drop + nat_dis + life_cnt), 1), bm_share_pct=round(100 * life_cnt / (nat_drop + nat_dis + life_cnt), 1),
                                        fill_1H_Epic_4U=fl_['1H Epic (4U)']['battles'], fill_1H_Uncommon_2U=fl_['1H Uncommon (2U)']['battles'], fill_2H_Epic_8U=fl_['2H Epic (8U)']['battles'],
                                        extra_T3=round(t3, 1), extra_T4=round(t4, 1), wall_extra_items=round(min(t3, t4) / 25.5, 2),
                                        free_gold_if_sold=round(rate * N_B * sum(BMk[f'L{L} BS-cap Epic']['sell_all_6'] for L in (20, 50, 80)) / 3))
BMk['targets_by_assumed_rate'] = bmT
A['5_black_market'] = BMk
ST = {}
for nm, (two, eq) in {'Hero Sword 1H Uncommon L5 (Debug, equipped)': (False, True), 'Mage Wand 1H Uncommon L5 (Debug, equipped)': (False, True),
                      'Ranger Crossbow 2H Uncommon L5 (Debug, equipped)': (True, True), 'Shield Off-Hand Common L5 (Debug)': (None, False),
                      '5 armor pieces Common L5 (Starter)': (None, False)}.items():
    if two is None: ST[nm] = dict(essences=0, materials=0)
    else:
        u = exp_lines('Uncommon', two)[0]; ST[nm] = dict(essences_expected=round(u, 2), essences_max=4 if two else 2, materials=0, needs_replacement_weapon_first=eq)
ST['_total'] = dict(expected=round(2 * exp_lines('Uncommon', False)[0] + exp_lines('Uncommon', True)[0], 1), max=8, materials=0, once_per_save=True)
A['5_starter_debug'] = ST

A['db_delta_vs_prefix_backup'] = RC.get('db_delta_vs_prefix_backup')
A['db_text_changes_since_recheck'] = [x[2] for x in TEXT_CHANGES]
A['_meta'] = dict(seed=SEED, rule_checks=len(PROV2), provenance=PROV2, db=DB, first_run_formulas=len(PROV),
                  source_read=['MerchantService.lua (shelf, refresh, pool)', 'GuildMenuService.lua (merchantStock L951-965, rollRecruit/previewRecruit/BuildRecruitUnit L359-523)',
                               'RecruitmentService.lua (ResolveHireCost, pool levels)', 'ObjectEffectService.lua L2262-2303 (Black Market)', 'Main.server.lua L642-754, 1793, 3503 (starter/debug gear, shop map level)',
                               'EquipmentService.lua L219-235 (keep-a-weapon guard, BUG-050)', 'QuestGenerator.lua L188-193, 328-334 (3 quests, levels)', 'ItemGenerator.lua L578-582 (Common: no lines)'])
A['db_changes_since_recheck_run'] = 'docs\\backups\\recheck_rulings_20261101_112336_changes.json: wording/record updates only (gf38 rule+notes, gf48 rule+notes, gf51 rule+notes, gf55 notes, ms41 notes, ms42 rule+notes, lp24 notes, equipment_schema reroll_count, open_decisions 23/123, implementation_plan 53). No formula or number used here changed.'
json.dump(A, open(OUT + r'\results_allsources.json', 'w'), default=str, indent=1)
print('OK')
