# CTRBLXAI Runeforge + Blacksmith RE-CHECK after the 2026-11-01 Simulator fixes (design verification, nothing built)
# Reuses rf_core.py / rf_econ.py / rf_supply.py (first-run files untouched). Writes results_recheck.json only.
import os, json, math, hashlib, sqlite3, random
from fractions import Fraction as Fr
OUT = r'D:\AI\Projects\CTRBLXAI\sim\runeforge_sim_2026-11-01'
R = {}
exec(open(OUT + r'\rf_core.py', encoding='utf-8').read())
exec(open(OUT + r'\rf_econ.py', encoding='utf-8').read())
_sup = '\n'.join(l for l in open(OUT + r'\rf_supply.py', encoding='utf-8').read().splitlines() if 'results.json' not in l)
exec(_sup)
RC = {}

# ---------- provenance: RULE column only (first-run checks also matched stale "Old:" text in notes) ----------
PROV2 = {}
def prov2(name, table, rid, must, col='rule'):
    if table == 'equipment_schema':
        t = con.execute('select Meaning from equipment_schema where Field=?', (rid,)).fetchone()[0]
    else:
        t = con.execute(f'select {col} from {table} where id=?', (rid,)).fetchone()[0] or ''
    ok = all(m in t for m in must)
    PROV2[name] = dict(table=table, row=rid, col=col, found=ok)
    if not ok:
        raise RuntimeError(f'PROVENANCE FAIL {name}: {table} {rid} {col} missing {[m for m in must if m not in t]}')
    return t
prov2('Dismantle per tier', 'guild_facilities', 51, ['TIER BY TIER', 'paid in that same tier', 'The T5 part (levels 81-99) is paid as the same number of T4, never T5',
      'STARTING rarity is Rare or higher', 'L61-99 T4', 'refund 9 T1 / 10 T2 / 10 T3 / 0 T4', 'enchanting an item up to Rare never earns the +1', 'Shop-bought items give nothing'])
prov2('Refund summary', 'materials_system', 42, ['each tier comes back in its own tier', 'the T5 part comes back as T4 (never T5)', 'STARTING rarity is Rare and up'])
prov2('Catch-up discount by level', 'guild_facilities', 48, ['3% x (ceil(level / 10) - 1)', "NOT the player's current discount", "Each level's cost is rounded down to whole gold first",
      '1H 22,201g, 2H 33,299g, Body 17,763g'])
prov2('Fixed Add offers / per-line reroll / round down', 'guild_facilities', 55, ['Add offers are FIXED', "one fixed order of eligible attributes, worked out from the item's saved ID",
      'a higher Runeforge level only adds choices to the end of the same list', 'Options are PER LINE', "Every paid reroll raises the item's reroll count by 1, also when the player keeps the old line",
      'every Runeforge and Blacksmith gold fee rounds DOWN to a whole gold piece'])
prov2('Reroll count field', 'equipment_schema', 'reroll_count', ['every paid reroll counts, also when the old line is kept'])
prov2('Epic fee round down', 'guild_facilities', 57, ['rounded down to whole gold', 'Off-Hand Rare L2 428.5 -> 428g'])
prov2('Blacksmith gold round down', 'economy_framework', 19, ['every Blacksmith gold cost rounds down to whole gold'], col='notes')
prov2('Wall benchmark', 'guild_facilities', 38, ['break at 12 items', '~286 per tier', '10 upgrades = 89%', '12 = 107%'])
prov2('Material income', 'materials_system', 36, ['T1: ~286', 'T5: ~312'])
prov2('Drops estimate', 'loot_progression', 24, ['about 0.40 equipment drops per battle'], col='notes')
prov2('Elite estimate', 'loot_progression', 26, ['elite encounters about 0.034 per battle'], col='notes')
prov2('Elite estimate 69', 'loot_progression', 69, ['about 0.034 elite encounters per battle'], col='notes')
prov2('Essence estimate', 'materials_system', 41, ['elite rate about 0.034 per battle', 'about 0.40 equipment drops per battle'], col='notes')
prov2('Facility total', 'guild_facilities', 5, ['70,927g across all 10 facilities'])
prov2('Downgrade free', 'economy_framework', 21, ['Free'])
prov2('Conversion one-way', 'materials_system', 25, ['3× lower tier → 1× next tier', 'One-way'])
t53 = con.execute('select rule from guild_facilities where id=53').fetchone()[0]
CHOICES = {}
for m in re.finditer(r'L(\d+): [^.]*?/ (\d+|full list) / (\d+)%', t53):
    CHOICES[int(m.group(1))] = None if m.group(2) == 'full list' else int(m.group(2))
assert sorted(CHOICES) == list(range(1, 11)), CHOICES
RC['_choices_by_RF_level'] = CHOICES

# ---------- DB delta vs the pre-fix backup ----------
BK = r'D:\AI\Projects\CTRBLXAI\docs\backups\CTRBLXAI_before_simfix_20261101_100613.db'
delta = {}
if os.path.exists(BK):
    bk = sqlite3.connect('file:' + BK + '?mode=ro', uri=True)
    for t in ['guild_facilities', 'materials_system', 'economy_framework', 'loot_progression', 'item_rarity_framework']:
        try:
            a = {r[0]: r[1:] for r in bk.execute(f'select id, rule, notes from {t}')}
            b = {r[0]: r[1:] for r in con.execute(f'select id, rule, notes from {t}')}
        except Exception as e:
            continue
        ch = sorted(k for k in set(a) | set(b) if a.get(k) != b.get(k))
        rule_ch = sorted(k for k in ch if (a.get(k) or (None,))[0] != (b.get(k) or (None,))[0])
        if ch: delta[t] = dict(rows_changed=ch, rule_text_changed=rule_ch)
    a = {r[0]: r for r in bk.execute('select * from equipment_schema')}; b = {r[0]: r for r in con.execute('select * from equipment_schema')}
    delta['equipment_schema'] = sorted(k for k in set(a) | set(b) if a.get(k) != b.get(k))
RC['db_delta_vs_prefix_backup'] = delta

SELLV = [5, 15, 40, 100, 250]
def needed_bs(t): return min(10, max(1, math.ceil(t / 10)))
def d_needed_pct(t): return 3 * (math.ceil(t / 10) - 1)
# whole-number upgrade cost (EF19), checked against the exact rational version below
RM10 = {r: int(RM[r] * 10) for r in RAR}
assert all(RM[r] * 10 == RM10[r] for r in RAR)
def ugi(slot, rar, t, dpct):
    return (BASE[slot] * RM10[rar] * 3 * (25 + t) * (100 - dpct)) // (10 * 10 * 25 * 100)
def ugb(slot, rar, t, bsl): return ugi(slot, rar, t, 3 * (bsl - 1))
def band_tier(L): return 1 if L <= 20 else 2 if L <= 40 else 3 if L <= 60 else 4
# per-tier level counts prefix
CNT = [[0] * 100 for _ in range(6)]
for t in range(1, 100):
    for k in range(1, 6): CNT[k][t] = CNT[k][t - 1] + (1 if (t >= 2 and mtier(t) == k) else 0)
def tier_levels(s, e): return [CNT[k][e] - CNT[k][s] for k in range(1, 6)]

# ===================== whole-number check (5) =====================
mis_exact = 0; mis_float = 0
for slot in BASE:
    for rar in RAR:
        for t in range(2, 100):
            for b in range(1, 11):
                ex = ug(slot, rar, t, b, True); it = ugb(slot, rar, t, b); fl = ug(slot, rar, t, b, False)
                mis_exact += ex != it; mis_float += fl != it
def route_i(slot, rar, s, e, bsl): return sum(ugb(slot, rar, t, bsl) for t in range(s + 1, e + 1))
RND = dict(int_vs_exact_mismatches=mis_exact, float_vs_int_level_mismatches=mis_float,
           twoH_common_L1_99_0pct=route_i('2H', 'Common', 1, 99, 1), twoH_epic_L1_99_0pct=route_i('2H', 'Epic', 1, 99, 1),
           oneH_unc_to_rare_L1_50_0pct=route_i('1H', 'Rare', 1, 50, 1) - route_i('1H', 'Uncommon', 1, 50, 1))
# Epic step fee rounding
def epic_fee_f(slot, start, L):
    return math.floor(epic_fee(slot, start, L))
half = []
for slot in BASE:
    for st in ['Common', 'Uncommon', 'Rare']:
        for L in range(1, 100):
            f = epic_fee(slot, st, L)
            if f.denominator != 1: half.append((slot, st, L, str(f), epic_fee_f(slot, st, L)))
RND['epic_fee_half_gold_cases'] = len(half)
RND['half_cases_rounded_down_correctly'] = all(h[4] == math.floor(Fr(h[3])) and h[4] < Fr(h[3]) for h in half)
RND['half_cases_in_1H_2H'] = sum(1 for h in half if h[0] in ('1H', '2H'))
RND['offhand_rare_L2'] = [h for h in half if h[0] == 'Off-Hand' and h[1] == 'Rare' and h[2] == 2]
RND['epic_fee_table_unchanged'] = {f'{s} L{L}': [epic_fee_f(s, st, L) for st in ('Common', 'Uncommon', 'Rare')] for s in ('1H', '2H') for L in (20, 50, 99)}
RC['rounding'] = RND

# ===================== X3 catch-up with per-level needed discount =====================
def fee2(slot, old, new, s, e):
    g = 0; m = [0] * 5
    for t in range(s + 1, e + 1):
        d = d_needed_pct(t)
        g += ugi(slot, new, t, d) - ugi(slot, old, t, d); m[mtier(t) - 1] += QTY[new] - QTY[old]
    return g, m
def prog_route(slot, rar, s, e, ahead=0):   # upgrades bought at the Blacksmith level needed (+ahead levels, capped 10)
    return sum(ugb(slot, rar, t, min(10, needed_bs(t) + ahead)) for t in range(s + 1, e + 1))
X3 = {}
exp3 = {'1H': 22201, '2H': 33299, 'Body': 17763}
for slot in BASE:
    f = fee2(slot, 'Common', 'Epic', 1, 99)
    honest = prog_route(slot, 'Epic', 1, 99); dodge = prog_route(slot, 'Common', 1, 99) + f[0]
    X3[slot] = dict(fee=f[0], fee_mats=f[1], expected=exp3.get(slot), honest_enchant_first=honest, upgrade_common_then_enchant=dodge, saving=honest - dodge,
                    old_fee_at_BS10=catchup(slot, 'Common', 'Epic', 1, 99, 10)[0])
# player ahead of the item (owns a higher Blacksmith than needed): late enchant can only cost MORE
pos = 0; mx = None; n = 0
for slot in BASE:
    for a, b in [(x, y) for x in ['Common', 'Uncommon', 'Rare', 'Epic'] for y in ['Common', 'Uncommon', 'Rare', 'Epic'] if RIDX[y] > RIDX[x]]:
        for t in range(2, 100):
            bn = needed_bs(t)
            for ba in range(bn, 11):
                n += 1
                sv = (ugb(slot, b, t, ba) - ugb(slot, a, t, ba)) - (ugi(slot, b, t, d_needed_pct(t)) - ugi(slot, a, t, d_needed_pct(t)))
                if sv > 0: pos += 1
                if mx is None or sv > mx[0]: mx = (sv, slot, a, b, t, ba)
X3['per_level_cases'] = n; X3['per_level_positive_savings'] = pos; X3['per_level_max_saving'] = mx
X3['boosted_late_enchant_extra_cost_1H'] = (prog_route('1H', 'Common', 1, 99, 9) + X3['1H']['fee']) - prog_route('1H', 'Epic', 1, 99, 9)
X3['boosted_late_enchant_extra_cost_2H'] = (prog_route('2H', 'Common', 1, 99, 9) + X3['2H']['fee']) - prog_route('2H', 'Epic', 1, 99, 9)
# downgrade-below-start trick with the new fee
worst = None
for slot in ['1H', '2H', 'Gloves', 'Body']:
    for s0, cur in [(1, 99), (20, 60), (50, 80), (61, 99), (1, 30), (35, 95)]:
        honest = fee2(slot, 'Common', 'Epic', s0, cur)[0]
        for d in range(1, cur):
            st = min(s0, d)
            trick = fee2(slot, 'Common', 'Epic', st, d)[0] + prog_route(slot, 'Epic', d, cur)
            sv = honest - trick
            if worst is None or sv > worst[0]: worst = (sv, slot, s0, cur, d)
X3['downgrade_trick_max_saving'] = worst
RC['X3'] = X3

# ===================== new dismantle =====================
def dis2(rar_cur, rar_start, s, e, bsl, shop=False):
    out = [0] * 5
    if shop: return out
    pct = BS_TABLE[bsl]['refund']; q = QTY[rar_cur]; c = tier_levels(s, e)
    for k in range(4): out[k] = (pct * c[k] * q) // 100
    out[3] += (pct * c[4] * q) // 100            # T5 part paid as the same number of T4
    if RIDX[rar_start] >= RIDX['Rare']: out[band_tier(e) - 1] += 1
    return out
def spent(rar, s, e): return [x * QTY[rar] for x in tier_levels(s, e)]
def val(v): return sum(a * b for a, b in zip(v, SELLV))

# ===================== X2 upgrade -> dismantle -> sell =====================
X2 = {}
g = route('Gloves', 'Common', 1, 61, 10)
X2['common_gloves_L1_61_BS10'] = dict(gold=g[0], spent=g[1], refund=dis2('Common', 'Common', 1, 61, 10), expected_refund=[9, 10, 10, 0, 0],
                                      mats_in_sell=val(g[1]), refund_sell=val(dis2('Common', 'Common', 1, 61, 10)),
                                      net=val(dis2('Common', 'Common', 1, 61, 10)) - val(g[1]) - g[0])
# the 6 setups that made gold under the old rule
old6 = []
for slot in BASE:
    for rar in ['Common', 'Uncommon', 'Rare', 'Epic']:
        for top in range(2, 100):
            gg, m = route(slot, rar, 1, top, 10)
            for bsl in (7, 8, 9, 10):
                if bsl * 10 < top and bsl < 10: continue
                gb = sum(ug(slot, rar, t, bsl) for t in range(2, top + 1))
                ref = math.floor(Fr(BS_TABLE[bsl]['refund'], 100) * sum(m)) + (1 if RIDX[rar] >= RIDX['Rare'] else 0)
                prof = ref * SELLV[min(4, mtier(top)) - 1] - val(m) - gb
                if prof > 0:
                    newref = dis2(rar, rar, 1, top, bsl)
                    old6.append(dict(slot=slot, rarity=rar, L=f'1->{top}', BS=bsl, old_profit=prof, new_refund=newref, new_profit=val(newref) - val(m) - gb))
X2['old_profitable_setups'] = old6
e80 = dis2('Epic', 'Epic', 1, 80, 10); sp80 = spent('Epic', 1, 80)
X2['epic_L1_80_BS10'] = dict(T4_spent=sp80[3], T4_back=e80[3], T4_back_without_plus1=e80[3] - 1, pct_incl_plus1=round(100 * e80[3] / sp80[3], 1), old=119)
X2['t5_as_t4_example_common_1H_L80_99_BS10'] = dict(T5_spent=spent('Common', 80, 99)[4], refund=dis2('Common', 'Common', 80, 99, 10))
# exhaustive: every slot, every rarity (starting = current), every start/end level, every Blacksmith level able to reach it
best = None; posn = 0; n = 0; t5_back = 0; best_by_rar = {}
PRE = {}
for slot in BASE:
    for rar in RAR:
        for b in range(1, 11):
            p = [0] * 100
            for t in range(2, 100): p[t] = p[t - 1] + ugb(slot, rar, t, b)
            PRE[(slot, rar, b)] = p
for slot in BASE:
    for rar in RAR:
        for s in range(1, 99):
            for e in range(s + 1, 100):
                sp = spent(rar, s, e); vin = val(sp)
                for b in range(needed_bs(e), 11):
                    n += 1
                    ref = dis2(rar, rar, s, e, b)
                    if ref[4]: t5_back += 1
                    pr = val(ref) - vin - (PRE[(slot, rar, b)][e] - PRE[(slot, rar, b)][s])
                    if pr > 0: posn += 1
                    if best is None or pr > best[0]: best = (pr, slot, rar, s, e, b, ref)
                    k = rar
                    if k not in best_by_rar or pr > best_by_rar[k][0]: best_by_rar[k] = (pr, slot, s, e, b)
X2['exhaustive'] = dict(cases=n, profitable=posn, best=best, any_T5_returned=t5_back, best_by_rarity=best_by_rar)
# alternative reading of the T5 part: floor(p x (T4+T5)) instead of floor(p x T4) + floor(p x T5)
dif = 0
for rar in RAR:
    for s in range(1, 99):
        for e in range(max(s + 1, 81), 100):
            c = tier_levels(s, e); q = QTY[rar]
            for b in range(1, 11):
                pct = BS_TABLE[b]['refund']
                dif = max(dif, (pct * (c[3] + c[4]) * q) // 100 - ((pct * c[3] * q) // 100 + (pct * c[4] * q) // 100))
X2['t4_t5_rounding_reading_max_diff'] = dif
RC['X2'] = X2

# ===================== X1 enchant -> dismantle (all slots, levels, upgraded or fresh) =====================
FEEPRE = {}
for slot in BASE:
    for a in ['Common', 'Uncommon', 'Rare']:
        for bb in ['Uncommon', 'Rare', 'Epic']:
            if RIDX[bb] <= RIDX[a]: continue
            p = [0] * 100
            for t in range(2, 100): p[t] = p[t - 1] + ugi(slot, bb, t, d_needed_pct(t)) - ugi(slot, a, t, d_needed_pct(t))
            FEEPRE[(slot, a, bb)] = p
X1 = {}; best = None; n = 0; plus_from_enchant = 0; pos = 0
spec = None
for slot in BASE:
    two = slot == '2H'
    for a in ['Common', 'Uncommon', 'Rare']:
        for bb in ['Uncommon', 'Rare', 'Epic']:
            if RIDX[bb] <= RIDX[a]: continue
            for L in range(1, 100):
                ca = cheapest_add(slot, a, bb, BUDGET[a] * (2 if two else 1), L, 27)
                if ca is None: continue
                cost0 = ca[0] + (epic_fee_f(slot, a, L) if bb == 'Epic' else 0)
                for s in range(1, L + 1):
                    feeg = FEEPRE[(slot, a, bb)][L] - FEEPRE[(slot, a, bb)][s]
                    feem = [x * (QTY[bb] - QTY[a]) for x in tier_levels(s, L)]
                    for b in (range(1, 11) if s == L else range(needed_bs(L), 11)):
                        n += 1
                        w = dis2(bb, a, s, L, b); wo = dis2(a, a, s, L, b)
                        if RIDX[a] < RIDX['Rare'] and (sum(w) - sum(wo)) > sum((x * (QTY[bb] - QTY[a]) * BS_TABLE[b]['refund']) // 100 + 1 for x in tier_levels(s, L)):
                            plus_from_enchant += 1
                        dlt = val(w) - val(wo) - cost0 - feeg - val(feem)
                        if dlt > 0: pos += 1
                        if best is None or dlt > best[0]: best = (dlt, slot, a, bb, L, s, b, ca[1])
                        if slot in ('Gloves', 'Feet') and a == 'Uncommon' and bb == 'Rare' and s == L and 61 <= L <= 99 and b == 10:
                            if spec is None or dlt > spec[0]: spec = (dlt, slot, L, ca[0], w, wo)
X1 = dict(cases=n, profitable=pos, best=best, uncommon_gloves_feet_L61_99_fresh_best=spec)
# direct +1 check: Uncommon -> one T1 Add -> Rare, fresh drop, every slot/level/BS level
p1 = 0; m1 = 0
for slot in BASE:
    for L in range(1, 100):
        for b in range(1, 11):
            m1 += 1; p1 += sum(dis2('Rare', 'Uncommon', L, L, b))
X1['uncommon_to_rare_fresh_plus1_count'] = (p1, m1)
RC['X1'] = X1

# ===================== exploit search 7: choose the +1 tier by moving a Rare-start item first =====================
LV7 = [1, 10, 19, 20, 21, 30, 39, 40, 41, 50, 59, 60, 61, 70, 79, 80, 81, 90, 98, 99]
ex7 = {}; best_up = None; best_dn = None; n = 0
for slot in BASE:
    for rar in RAR[2:]:
        for s in LV7:
            for cur in [c for c in LV7 if c >= s]:
                for b in range(needed_bs(cur) if cur > s else 1, 11):
                    base_v = val(dis2(rar, rar, s, cur, b))
                    # downgrade first (free) to any d < cur
                    for d in (1, 20, 21, 40, 41, 60, 61, cur - 1):
                        if d < 1 or d >= cur: continue
                        st = min(s, d)
                        v = val(dis2(rar, rar, st, d, b)); n += 1
                        if best_dn is None or v - base_v > best_dn[0]: best_dn = (v - base_v, slot, rar, s, cur, d, b)
                    # upgrade first to the next band start
                    for e in (20, 21, 40, 41, 60, 61, 81, 99):
                        if e <= cur or b < needed_bs(e): continue
                        cost = (PRE[(slot, rar, b)][e] - PRE[(slot, rar, b)][cur]) + val(spent(rar, cur, e))
                        v = val(dis2(rar, rar, s, e, b)) - cost; n += 1
                        if best_up is None or v - base_v > best_up[0]: best_up = (v - base_v, slot, rar, s, cur, e, b)
ex7['cases'] = n; ex7['best_downgrade_first_gain'] = best_dn; ex7['best_upgrade_first_gain'] = best_up
# material-only view (wall currency): T5 -> T4 through upgrade L80->99 then dismantle (the new "T5 part as T4" rule)
t54 = {}
for slot in ['Gloves', '1H', '2H']:
    for rar in ['Common', 'Rare', 'Epic']:
        gold = PRE[(slot, rar, 10)][99] - PRE[(slot, rar, 10)][80]
        sp5 = spent(rar, 80, 99)[4]; back4 = dis2(rar, 'Common', 80, 99, 10)[3]
        t54[f'{slot} {rar}'] = dict(T5_in=sp5, T4_out=back4, gold=gold, gold_per_T4=round(gold / back4, 1), sell_value_lost=sp5 * 250 - back4 * 100 + gold)
ex7['t5_to_t4_route'] = t54
RC['exploit_search_7'] = ex7

# ===================== X4 fixed Add offers / per-line rerolls =====================
FAMS2 = sorted({r[0] for r in con.execute('select distinct attribute_family from bonus_numerical_attributes')} - {'Fortune'})
def H(s): return hashlib.sha256(s.encode()).digest()
class It:
    def __init__(s, iid, lines): s.iid = iid; s.lines = list(lines); s.rc = 0; s.level = 50
    def present(s): return {f for f, _ in s.lines}
    def dump(s): return json.dumps(dict(i=s.iid, l=s.lines, r=s.rc, v=s.level))
    @staticmethod
    def load(d):
        d = json.loads(d); x = It(d['i'], [tuple(a) for a in d['l']]); x.rc = d['r']; x.level = d['v']; return x
def add_order(iid): return sorted(FAMS2, key=lambda f: H(f'{SEED}|ADD|{iid}|{f}'))
def add_list(it, rfl):
    lst = [f for f in add_order(it.iid) if f not in it.present()]
    return lst if CHOICES[rfl] is None else lst[:CHOICES[rfl]]
def rr_opts(it, idx, n=3):
    fam, tier = it.lines[idx]
    h = H(f'{SEED}|RR|{it.iid}|{fam}|{tier}|{it.rc}')
    return sorted([f for f in FAMS2 if f not in it.present()], key=lambda f: hashlib.sha256(h + f.encode()).digest())[:n]
def rr(it, idx, pick=None):
    o = rr_opts(it, idx); it.rc += 1
    if pick is not None: it.lines[idx] = (o[pick], it.lines[idx][1])
    return o
rng = random.Random(SEED)
X4 = dict(rejoin_changes=0, remove_add_changes=0, keep_reroll_add_changes=0, upgrade_changes=0, rf_level_not_prefix=0,
          history_mismatch=0, keep_reroll_same_options_after=0, lines_same_options=0, line_pairs=0, steps=0, rerolls=0)
for k in range(400):
    it = It(f'item-{k}', [(f, rng.randint(1, 2)) for f in rng.sample(FAMS2, rng.randint(1, 3))])
    for rfl in range(1, 10):
        a, b2 = add_list(it, rfl), add_list(it, rfl + 1)
        if b2[:len(a)] != a: X4['rf_level_not_prefix'] += 1
    L0 = {r: add_list(it, r) for r in range(1, 11)}
    if any(add_list(It.load(it.dump()), r) != L0[r] for r in L0): X4['rejoin_changes'] += 1
    x = It.load(it.dump()); f = add_list(x, 1)[0]; x.lines.append((f, 1)); x.lines.pop()
    if any(add_list(x, r) != L0[r] for r in L0): X4['remove_add_changes'] += 1
    x = It.load(it.dump()); f0 = x.lines[0]; x.lines.pop(0); x.lines.insert(0, f0)
    if any(add_list(x, r) != L0[r] for r in L0): X4['remove_add_changes'] += 1
    x = It.load(it.dump()); o1 = rr(x, 0); o2 = rr_opts(x, 0)
    if o1 == o2: X4['keep_reroll_same_options_after'] += 1
    if any(add_list(x, r) != L0[r] for r in L0): X4['keep_reroll_add_changes'] += 1
    X4['rerolls'] += 1
    x = It.load(it.dump()); x.level = 99
    if any(add_list(x, r) != L0[r] for r in L0): X4['upgrade_changes'] += 1
    if len(it.lines) >= 2:
        X4['line_pairs'] += 1
        if rr_opts(it, 0) == rr_opts(it, 1): X4['lines_same_options'] += 1
    # random action sequence: list must depend only on (item ID, attributes on item, Runeforge level)
    y = It.load(it.dump())
    for step in range(60):
        act = rng.choice(['rejoin', 'add', 'remove', 'reroll_keep', 'reroll_take', 'upgrade', 'downgrade'])
        if act == 'rejoin': y = It.load(y.dump())
        elif act == 'add' and len(y.lines) < 4: y.lines.append((add_list(y, rng.randint(1, 10))[0], 1))
        elif act == 'remove' and len(y.lines) > 1: y.lines.pop(rng.randrange(len(y.lines)))
        elif act == 'reroll_keep': rr(y, rng.randrange(len(y.lines)))
        elif act == 'reroll_take': rr(y, rng.randrange(len(y.lines)), 0)
        elif act == 'upgrade': y.level = min(99, y.level + 1)
        elif act == 'downgrade': y.level = max(1, y.level - 1)
        fresh = It(y.iid, list(y.lines))
        X4['steps'] += 1
        if any(add_list(y, r) != add_list(fresh, r) for r in range(1, 11)): X4['history_mismatch'] += 1
def rf_cap(rfl, two):
    return (100 if rfl <= 4 else 150 if rfl <= 9 else 200) * (2 if two else 1)
# paid "walking": deepest Add-order position a player can choose from by adding throwaway T1 lines then removing them
walk = {}
for rfl in range(1, 11):
    n_show = CHOICES[rfl]; cap = rf_cap(rfl, False) // 50
    walk[f'RF L{rfl}'] = 'full list' if n_show is None else dict(shown=n_show, deepest_reachable=n_show + max(0, cap - 1),
                                                                   cost_per_extra='1 T1 Add + 1 Remove (1.5x Add-T1 gold) + 1 Uncommon Essence, not refunded')
X4['paid_walk_1H_empty_item'] = walk
X4['walk_cost_1H_L50_RF_L1'] = rf_gold('1H', 50, 1, 0) + rf_gold('1H', 50, Fr(1, 2), 0)
RC['X4'] = X4

# ===================== 6: loops + supply =====================
L6 = {}
L6['upgrade_dismantle_sell_max'] = RC['X2']['exhaustive']['best'][0]
L6['enchant_dismantle_sell_max_marginal'] = RC['X1']['best'][0]
def sell_loop(slots, discs):
    bestr = {}
    for slot in slots:
        two = slot == '2H'
        for start in ['Common', 'Uncommon', 'Rare']:
            for target in ['Uncommon', 'Rare', 'Epic']:
                if RIDX[target] <= RIDX[start]: continue
                for L in range(1, 100):
                    for d in discs:
                        ca = cheapest_add(slot, start, target, BUDGET[start] * (2 if two else 1), L, d)
                        if ca is None: continue
                        res = -ca[0] - (epic_fee_f(slot, start, L) if target == 'Epic' else 0)
                        if slot not in bestr or res > bestr[slot][0]: bestr[slot] = (res, start, target, L, d)
    return bestr
L6['enchant_sell_best'] = sell_loop(list(BASE), [0, 18, 21, 27])
L6['facility_total'] = sum(sum(v) for v in FAC.values())
L6['workshop_table'] = FAC['Workshop']
fsum = {}
for nm in STRATS:
    for who in ('free', 'boost'):
        r_ = E[f'{who} {nm} bsA']
        fsum[f'{who} {nm}'] = dict(maxed=f"{r_['maxed']}/{r_['n_fac']}", leftover=r_['leftover'], expense_ratio_pct=r_['expense_ratio_pct'])
L6['facilities'] = fsum
L6['essence_drop_share_base'] = G['base (0.40 items/battle, elite=boss=0.034)']['drop_share_pct']
sens = {}
for x in (0.2, 0.4, 0.8, 1.0):
    for el in (0.017, 0.034, 0.068):
        sens[f'drops {x} / elite {el}'] = essence_sim(items_per_battle=x, elite=el)['drop_share_pct']
L6['essence_share_sensitivity'] = sens
sup = R['D']['supply_L50_80']
L6['epic_supply_L50_80'] = {k: dict(RF10_at=v['RF10_at_level'], crafted=v['crafted_max'], natural=v['natural_epic']) for k, v in sup.items()}
# supply sensitivity to the drop estimate (natural Epics scale with drops; crafted limited by gold or by dismantle Essences)
ss = {}
for x in (0.2, 0.4, 0.8):
    Gx = essence_sim(items_per_battle=x)['band_50_80']['U']
    row_ = {}
    for k in ('free rush (Guild Hall + Runeforge first)', 'boost rush (Guild Hall + Runeforge first)', 'boost classic (Runeforge after core 6)', 'boost crafter (Runeforge inside core)'):
        v = sup[k]; frac = (v['crafted_gold_limited'] * 2600 / v['window_luxury_gold']) if v['window_luxury_gold'] else 0
        row_[k] = dict(natural=round(nb * x * 0.0595, 1), crafted=round(min(v['crafted_gold_limited'], Gx * frac / 4), 1))
    ss[f'drops {x}'] = row_
L6['epic_supply_sensitivity'] = ss
# ---- material wall with the per-tier refund ----
INC = [286, 286, 286, 286, 312]; SP = [0.5, 10, 25.5, 25.5, 5.5]
def wall_n(early=(0, 0, 0, 0, 0), late=(0, 0, 0, 0, 0), conv=True, t5t4=False, maxN=80):
    last = 0
    for N in range(1, maxN):
        carry = 0.0; ok = True; used5 = 0.0
        for t in range(5):
            have = INC[t] + N * early[t] + carry - (used5 if t == 4 else 0); need = N * SP[t]
            if t == 3 and t5t4 and have < need:
                s5 = INC[4] + N * early[4] - N * SP[4]
                used5 = max(0.0, min(s5, 2 * (need - have))); have += used5 / 2
            if have < need: ok = False; break
            carry = (have - need + N * late[t]) / 3 if conv else 0.0
        if not ok: break
        last = N
    return last
fl = lambda x: math.floor(x)
W = {'_definition': 'breaks at = first item count that no longer fits (same as guild_facilities 38 "break at 12 items"); [no conversion, with 3:1 conversion]'}
def br(**kw): return [wall_n(conv=False, **kw) + 1, wall_n(conv=True, **kw) + 1]
W['R0 no dismantling'] = br()
# R1: every item dismantled after its tier is needed (BS6 40% for T1-T3 parts, BS8 45% T4 part): refunds only usable by converting up
W['R1 every item dismantled after its band (late refunds)'] = br(late=(fl(0.4 * 0.5), fl(0.4 * 10), fl(0.4 * 25.5), fl(0.45 * 25.5), 0))
# R3: half of each band's spend sits on an item replaced mid-band: in-tier refund usable
r3 = (0, fl(0.4 * 5), fl(0.40 * 12.75), fl(0.45 * 12.75), 0)
W['R3 mid-band replacement (refund usable in tier)'] = br(early=r3)
W['R3 + Rare-start +1 on every item'] = br(early=(0, r3[1], r3[2] + 1, r3[3] + 1, 0))
rp = 0.1214 + 0.0595 + 0.025 + 0.0012
x3 = band_items(41, 60.99, rp); x4 = band_items(61, 99, rp)
W['natural_RarePlus_plus1_supply'] = dict(T3=round(x3, 1), T4=round(x4, 1))
def wall_extra(early, e3, e4, conv=True):
    last = 0
    for N in range(1, 80):
        carry = 0.0; ok = True
        for t in range(5):
            have = INC[t] + N * early[t] + carry + (e3 if t == 2 else e4 if t == 3 else 0); need = N * SP[t]
            if have < need: ok = False; break
            carry = (have - need) / 3 if conv else 0.0
        if not ok: break
        last = N
    return last + 1
W['R3 + natural Rare+ loot dismantled (+1)'] = [wall_extra(r3, x3, x4, False), wall_extra(r3, x3, x4, True)]
W['pool upper bound (every refund 50%, usable in tier)'] = br(early=tuple(0.5 * s_ for s_ in SP[:3]) + (0.5 * (SP[3] + SP[4]), 0))
W['T5->T4 dismantle route only (upper bound: T5 must be in hand during L61-80)'] = br(t5t4=True)
W['R3 + T5->T4 route (upper bound)'] = br(early=r3, t5t4=True)
W['pct_of_T3T4_budget'] = {n_: round(100 * n_ * 25.5 / 286, 1) for n_ in (10, 12, 13, 15)}
W['first_run'] = dict(no_dismantle=12, with_dismantle='12-15', with_X1=17)
L6['wall'] = W
RC['L6'] = L6
RC['_meta'] = dict(seed=SEED, formulas_loaded_first_run=len(PROV), rule_checks_added=len(PROV2), provenance_recheck=PROV2, db=DB)
json.dump(RC, open(OUT + r'\results_recheck.json', 'w'), default=str, indent=1)
print('OK')
