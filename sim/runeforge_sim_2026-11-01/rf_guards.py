# Checks H (guards), I (balance), J (save size) + exploit search over laundering. Requires rf_core.py.
import hashlib
H = {}
FAMS = [r[0] for r in con.execute('select distinct attribute_family from bonus_numerical_attributes')]

class Item:
    def __init__(self, iid, slot, rarity, level, lines, shop_bought=False, unique=False):
        self.iid = iid; self.slot = slot; self.rarity = rarity; self.level = level; self.lines = list(lines)  # [(family, tier)]
        self.starting_level = level; self.starting_rarity = rarity; self.shop_bought = shop_bought; self.reroll_count = 0; self.unique = unique
    def bp(self): return 50 * sum(t for _, t in self.lines)
    def save(self): return dict(iid=self.iid, slot=self.slot, r=self.rarity, l=self.level, lines=self.lines, sl=self.starting_level, sr=self.starting_rarity, sb=self.shop_bought, rc=self.reroll_count, u=self.unique)
    @staticmethod
    def load(d):
        it = Item(d['iid'], d['slot'], d['r'], d['l'], [tuple(x) for x in d['lines']], d['sb'], d['u'])
        it.starting_level = d['sl']; it.starting_rarity = d['sr']; it.reroll_count = d['rc']; return it

class Refused(Exception): pass

def rf_cap(rfl, two):
    base = 100 if rfl <= 4 else 150 if rfl <= 9 else 200
    return base * (2 if two else 1)
def above_epic(it): return RIDX[it.rarity] > RIDX['Epic']

def rf_add(it, fam, tier, rfl):
    if it.unique: raise Refused('Unique')
    if above_epic(it): raise Refused('above Epic: no Add (gf54)')
    if fam == 'Fortune': raise Refused('Fortune never offered (gf58)')
    if any(f == fam for f, _ in it.lines): raise Refused('family already on item (gf44)')
    maxt = 2 if rfl < 5 else 3 if rfl < 10 else 4
    if tier > maxt: raise Refused('tier locked')
    two = it.slot == '2H'
    if it.bp() + 50 * tier > rf_cap(rfl, two): raise Refused('capacity')
    it.lines.append((fam, tier))
    r = max(RIDX[it.rarity], RIDX[band_rarity(it.bp(), two)], max(RIDX[TIER_MINRAR[t]] for _, t in it.lines))
    it.rarity = RAR[r]

def reroll_options(it, line_idx, n=3):
    fam, tier = it.lines[line_idx]
    pool = sorted(f for f in FAMS if f != 'Fortune' and f not in [x for x, _ in it.lines])
    h = hashlib.sha256(f'{SEED}|{it.iid}|{it.reroll_count}|{line_idx}'.encode()).digest()
    idx = sorted(range(len(pool)), key=lambda i: hashlib.sha256(h + bytes([i])).digest())[:n]
    return [(pool[i], tier) for i in idx]

def rf_modify(it, idx, delta, rfl):
    if it.unique: raise Refused('Unique')
    if above_epic(it) and rfl < 10: raise Refused('above Epic: tune only at L10')
    fam, tier = it.lines[idx]
    if delta > 0 and fam == 'Fortune': raise Refused('Fortune never moved up (gf58)')
    nt = tier + delta
    if nt < 1: raise Refused('tier < 1')
    budget = (BUDGET.get(it.rarity, None) or {'Exalted': 225, 'Legendary': 250, 'Mythic': 300, 'Transcendent': 350}[it.rarity]) * (2 if it.slot == '2H' else 1)
    cap = budget if above_epic(it) else rf_cap(rfl, it.slot == '2H')
    if delta > 0 and it.bp() + 50 * delta > cap: raise Refused('capacity/own budget')
    it.lines[idx] = (fam, nt)

def dismantle(it, bsl):
    if it.unique: raise Refused('Unique')
    if it.shop_bought: return dict(mats=0, ess=0)
    spent = sum(QTY[it.rarity] for t in range(it.starting_level + 1, it.level + 1))
    mats = math.floor(Fr(BS_TABLE[bsl]['refund'], 100) * spent) + (1 if RIDX[it.rarity] >= RIDX['Rare'] else 0)
    return dict(mats=mats, ess=len(it.lines))

# H1 shop-bought -> nothing
shop_rare = Item('S1', 'Gloves', 'Rare', 70, [('HP', 3)], shop_bought=True)
H['shop_bought_dismantle'] = dismantle(shop_rare, 10)
# H2 reroll determinism across save/load (leave + rejoin)
it = Item('X42', '1H', 'Rare', 50, [('STR Bonus', 2), ('HP', 1)])
o1 = reroll_options(it, 0); o2 = reroll_options(Item.load(json.loads(json.dumps(it.save()))), 0)
it.reroll_count += 1; o3 = reroll_options(it, 0)
H['reroll_fixed_after_rejoin'] = dict(same=o1 == o2, changes_after_paid_reroll=o1 != o3, fortune_in_any_option=any(f == 'Fortune' for f, _ in o1 + o3))
# H3 Fortune: Add refused, Modify-up refused, Modify-down / Remove allowed
fo = Item('F1', 'Accessory', 'Rare', 50, [('Fortune', 2)])
res = {}
for nm, fn in [('add', lambda: rf_add(Item('F2', 'Accessory', 'Common', 50, []), 'Fortune', 1, 10)),
               ('modify_up', lambda: rf_modify(fo, 0, +1, 10)), ('modify_down', lambda: rf_modify(fo, 0, -1, 10))]:
    try: fn(); res[nm] = 'allowed'
    except Refused as e: res[nm] = 'refused: ' + str(e)
# exhaustive: no reroll option set for any item/line/count contains Fortune
bad = 0
for k in range(300):
    t = Item(f'I{k}', '1H', 'Epic', 50, [('STR Bonus', 2), ('HP', 1), ('Fortune', 1)])
    t.reroll_count = k % 7
    for li in range(3):
        bad += sum(1 for f, _ in reroll_options(t, li, 5) if f == 'Fortune')
res['reroll_offers_fortune_count'] = bad
H['fortune'] = res
# H4 above Epic: no Add, no rarity change; tune only at L10
ex = Item('E1', '1H', 'Exalted', 80, [('STR Bonus', 2), ('HP', 2)])
r4 = {}
try: rf_add(ex, 'AGI Bonus', 1, 10); r4['add'] = 'allowed'
except Refused as e: r4['add'] = 'refused: ' + str(e)
try: rf_modify(ex, 0, +1, 9); r4['modify_at_L9'] = 'allowed'
except Refused as e: r4['modify_at_L9'] = 'refused: ' + str(e)
try: rf_modify(ex, 0, -1, 10); r4['modify_down_L10'] = 'allowed'
except Refused as e: r4['modify_down_L10'] = 'refused: ' + str(e)
r4['rarity_after'] = ex.rarity
H['above_epic'] = r4
# H5 Unique refused everywhere
un = Item('U1', '1H', 'Epic', 50, [('STR Bonus', 4)], unique=True); r5 = {}
for nm, fn in [('add', lambda: rf_add(un, 'HP', 1, 10)), ('modify', lambda: rf_modify(un, 0, -1, 10)), ('dismantle', lambda: dismantle(un, 10))]:
    try: fn(); r5[nm] = 'allowed'
    except Refused as e: r5[nm] = 'refused'
H['unique'] = r5
# H6 gaps found while modelling
H['gaps'] = [
    'Add offers (gf53/55: 3-6 choices below L10) are NOT stated to be fixed by item + counter. Remove (0.5x gold) + Add can be re-rolled by leaving and rejoining, which is the rejoin-farm the Reroll rule blocks.',
    'gf55 does not say whether reroll_count rises when the player keeps the old line (cost is paid either way). If it does not rise, options never change; if it does, fine. Needs one sentence.',
    'gf55 does not say whether reroll options are per line or per item (the hash key). Needs one word.',
    'Epic step fee (gf57) can be a half gold piece on 158 slot/level/start combinations (all non-1H/2H slots, e.g. Off-Hand Rare L2 = 428.5g). Rounding rule missing.',
    "Dismantle '+1 for Rare and up' (gf51) reads the CURRENT rarity, so Runeforge-raising an item to Rare earns the +1 (see exploit X1).",
]
R['H'] = H

# ---------------- I: balance ----------------
I = {}
nat = {}
for rar in ['Epic']:
    for two in (False, True):
        n = UNITS[rar] * (2 if two else 1)
        ps = list(partitions(n, MAXTIER[rar]))
        nat[f'{rar}{" 2H" if two else ""}'] = dict(partitions=len(ps), p_has_T4=round(sum(1 for P in ps if 4 in P) / len(ps), 3), bp=50 * n)
I['natural_epic_numeric_bp'] = nat
pas = [r[0] for r in con.execute("select bp_cost from bonus_passives where minimum_rarity in ('Uncommon','Rare','Epic')")]
I['natural_epic_with_passive_bp_range'] = (190, 210, 'band from item_rarity_framework; odd passive BP (e.g. 70/90/110/130/170/190) lets natural Epics land 190-210')
I['crafted_cap'] = dict(epic_1H=200, epic_2H=400, rule='gf54 capacity = normal budget (not the 210 maximum)')
eff = {}
for r_ in con.execute("select attribute_family, tier, fixed_pct_or_value, level_scaled_flat_l99 from bonus_numerical_attributes where tier in (1,4)"):
    eff.setdefault(r_[0], {})[r_[1]] = (r_[2], r_[3])
def pct(s):
    m = re.search(r'([\d.]+)', s or ''); return float(m.group(1)) if m else None
ratios = {}
for f, v in eff.items():
    if 1 in v and 4 in v:
        a, b = v[1][0], v[4][0]
        if '×' in a:  # multiplier
            x1 = abs(float(a.replace('×', '')) - 1); x4 = abs(float(b.replace('×', '')) - 1)
        else:
            x1 = pct(a); x4 = pct(b)
        if x1: ratios[f] = round(x4 / (4 * x1), 2)
I['T4_vs_4xT1_value_ratio'] = ratios
weap_fams = [r[0] for r in con.execute("select distinct attribute_family from bonus_numerical_attributes where eligible_equipment in ('Any equipment','Weapons','Weapons and off-hands')") if r[0] != 'Fortune']
I['weapon_families_eligible'] = len(weap_fams)
I['p_natural_epic_1H_has_T4_in_chosen_family_uniform'] = round(nat['Epic']['p_has_T4'] / len(weap_fams), 4)
I['balance_audit_benchmark_present'] = False
R['I'] = I

# ---------------- J: save size ----------------
def item_json(it, new=True):
    d = dict(id=it.iid, b='WPN-LONGSWORD-01', l=it.level, r=RIDX[it.rarity], a=[[i, t] for i, (_, t) in enumerate(it.lines)], p=[], g=3)
    if new: d.update(sl=it.starting_level, sb=1 if it.shop_bought else 0, rc=it.reroll_count, sr=RIDX[it.starting_rarity])
    return len(json.dumps(d, separators=(',', ':')))
sample = Item('3f2a9c1e-7b44-4c1d-9e0a-5b6d7e8f9a0b', '1H', 'Epic', 99, [('A', 2), ('B', 1), ('C', 1)])
sample.reroll_count = 12
old = item_json(sample, False); new = item_json(sample, True)
longnames = len(json.dumps(dict(starting_level=99, shop_bought=False, reroll_count=12, starting_rarity='Uncommon'))) - 2
J = dict(item_bytes_old=old, item_bytes_new_short_keys=new, added_short=new - old, added_long_key_names=longnames,
         counters_added_bytes=len(json.dumps(dict(eU=99999, eR=99999, eE=99999), separators=(',', ':'))))
for n in (200, 500, 1000, 5000):
    J[f'inv_{n}_items_kb_old'] = round(n * old / 1024, 1); J[f'inv_{n}_items_kb_new_worst'] = round(n * (old + longnames) / 1024, 1)
J['items_to_hit_4MB_old'] = int(4 * 1024 * 1024 / old); J['items_to_hit_4MB_new_worst'] = int(4 * 1024 * 1024 / (old + longnames))
prov('DataStore limit', 'roblox_platform', 4, ['4MB per key']) if False else None
R['J'] = J

# exploit search: best gold profit of upgrade->dismantle->sell materials over all slots/rarities/levels/BS levels
best = None; posi = 0; tot = 0
sellv = [5, 15, 40, 100, 250]
for slot in BASE:
    for rar in ['Common', 'Uncommon', 'Rare', 'Epic']:
        for start in (1,):
            for top in range(2, 100):
                g, m = route(slot, rar, start, top, 10)
                spent = sum(m)
                for bsl in (7, 8, 9, 10):
                    if bsl * 10 < top and bsl < 10: continue
                    gg = sum(ug(slot, rar, t, bsl) for t in range(start + 1, top + 1)) if bsl != 10 else g
                    ref = math.floor(Fr(BS_TABLE[bsl]['refund'], 100) * spent) + (1 if RIDX[rar] >= RIDX['Rare'] else 0)
                    tier = min(4, mtier(top))
                    prof = ref * sellv[tier - 1] - sum(a * b for a, b in zip(m, sellv)) - gg
                    tot += 1
                    if prof > 0: posi += 1
                    if best is None or prof > best[0]: best = (prof, slot, rar, start, top, bsl, ref, f'T{tier}', gg, m)
R['X_launder_search'] = dict(cases=tot, profitable_cases=posi, best=best)
