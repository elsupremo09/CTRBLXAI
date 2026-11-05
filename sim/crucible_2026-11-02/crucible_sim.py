# CTRBLXAI Crucible (gear merge) lifetime check - 2026-11-02. DB read-only. Seed 20261102.
# Reuses sim\runeforge_v2_2026-11-01\v2_core.py (DB values with prov() asserts) + v2_tests_b.py prefix (per_drop),
# and the daily_systems_2026-11-01 assumptions (547 battles, 0.40 drops/battle, 90% wins, B4 boss + daily 3).
# Crucible rules: design_snapshot_workshop_design_options_20261101.md (user-approved 2026-11-02; NOT in the DB yet).
import math, json, random, time, sqlite3, os, hashlib
V2 = r'D:\AI\Projects\CTRBLXAI\sim\runeforge_v2_2026-11-01'
OUTD = r'D:\AI\Projects\CTRBLXAI\sim\crucible_2026-11-02'
DBP = r'D:\AI\Projects\CTRBLXAI\docs\CTRBLXAI.db'
def md5(p): return hashlib.md5(open(p, 'rb').read()).hexdigest()
for attempt in range(20):                       # Designer may be writing: wait and retry on lock
    try:
        MD5_START = md5(DBP)
        exec(open(V2 + r'\v2_core.py', encoding='utf-8').read())
        tb = open(V2 + r'\v2_tests_b.py', encoding='utf-8').read(); exec(tb[:tb.find('def lifetime')])
        con.execute('select count(*) from loot_progression').fetchone()
        break
    except sqlite3.OperationalError as e:
        print('DB busy, retry', attempt, e); time.sleep(15)
SEED = 20261102
T0 = time.time()
# ---------- provenance for rows used today ----------
prov('Shelf composition', 'economy_framework', 48, ['5, 5, 6, 7, 7, 8, 9, 10, 10, 10', 'L10 C10 U30 R40 E15 Exalted 5', 'Item level rolls at the current Map Level ceiling', 'Deterministic from seed + battles-completed'])
prov('Shop stock / restock', 'economy_framework', 18, ['Shops sell items up to current Map Level', 'reroll every 5 completed battles', 'Nothing above Exalted is ever sold'])
prov('Inventory threshold', 'economy_framework', 24, ['50 items'])
prov('Maintenance cost', 'economy_framework', 25, ['min(Excess Items × 5, 200) gold per base visit'])
prov('Inventory expansion', 'economy_framework', 33, ['+25 item threshold per purchase'])
prov('Dismantle output', 'guild_facilities', 51, ['Mercury = ceil(item level / 10)', 'Exalted 4 / 1 per line / 1', 'Legendary 6 / 1 per line / 2'])
prov('Boss reward', 'loot_progression', 15, ['first 3 rewarded boss wins per day'])
prov('Boss loot Rare+', 'loot_progression', 25, ['One guaranteed Rare-or-better equipment reward'])
prov('Elite reward', 'loot_progression', 26, ['Base Elite Reward Chance = 75%'])
prov('Boss card weight 3', 'guild_facilities', 17, ['card weight 3', 'L8: Boss quests'])
prov('Unlock schedule', 'guild_facilities', 8, ['L5: Training Ground'])
prov('Tavern curve = Crucible curve', 'guild_facilities', 9, ['Base = 200, Scale = 18. Total cost: 6,277g'])
bm = ' '.join(str(x) for x in con.execute('select * from objects_encounters where rowid=31').fetchone())
assert all(s in bm for s in ['six items at 75% of the Merchant price', 'Rare 75% / Epic 25%', 'never Exalted', 'random slot']), 'BM row changed'
PROV['Black Market shop'] = dict(table='objects_encounters', row=31, found=True)
# archetype catalog (content counts) - DB rows vs code pools
wcat = [r[0] for r in con.execute("select section from weapons_equipment where id between 25 and 45 or id between 114 and 134") if r[0] and not r[0].startswith('---')]
offdb = [r[0] for r in con.execute("select section from weapons_equipment where id in (47,48) or id between 138 and 152")]
arm = {p: con.execute(f"select count(*) from nonweapon_equipment where section like '{p}-%'").fetchone()[0] for p in ('HD', 'BD', 'GL', 'FT', 'AC')}
SRC = r'D:\AI\Projects\CTRBLXAI\source\ReplicatedStorage\Content'
import re as _re
wd = open(SRC + r'\WeaponData.lua', encoding='utf-8').read(); ad = open(SRC + r'\ArmorData.lua', encoding='utf-8').read()
code_w = _re.findall(r'\["(WPN-[A-Z]+)"\]\s*=\s*\{', wd); code_o = _re.findall(r'\["(OFF-[A-Z]+)"\]\s*=\s*\{', wd)
code_a = {p: len(_re.findall(r'\["(' + p + r'-\d+)"\]\s*=\s*\{', ad)) for p in ('HD', 'BD', 'GL', 'FT', 'AC')}
CATALOG = dict(db=dict(weapons=len(wcat), offhands=len(offdb), armor=arm, total=len(wcat) + len(offdb) + sum(arm.values())),
               code=dict(weapons=len(code_w), offhands=len(code_o), offhand_ids=code_o, armor=code_a, total=len(code_w) + len(code_o) + sum(code_a.values())),
               db_offhands_missing_in_code=[o for o in offdb if 'OFF-' + o.replace(' ', '').replace('(revised)', '').upper() not in code_o])
POOLS = {
    'code (146), slot first': {'1H': 18, '2H': 20, 'Off-Hand': len(code_o), 'Body': code_a['BD'], 'Head': code_a['HD'], 'Gloves': code_a['GL'], 'Feet': code_a['FT'], 'Accessory': code_a['AC']},
    'DB (156), slot first': {'1H': 18, '2H': 20, 'Off-Hand': len(offdb), 'Body': arm['BD'], 'Head': arm['HD'], 'Gloves': arm['GL'], 'Feet': arm['FT'], 'Accessory': arm['AC']},
}
# ---------- Crucible rules (design snapshot, user-approved 2026-11-02) ----------
def c_need(cl): return 5 if cl <= 3 else 4 if cl <= 7 else 3
def c_boost(cl): return {1: 0, 2: 0, 3: 1, 4: 1, 5: 2, 6: 2, 7: 3, 8: 3, 9: 4, 10: 5}[cl]
def c_maxout(cl): return 'Legendary' if cl >= 10 else 'Exalted' if cl >= 9 else 'Epic' if cl >= 7 else 'Rare' if cl >= 4 else 'Uncommon'
C_CRY = {'Uncommon': 2, 'Rare': 3, 'Epic': 6, 'Exalted': 8, 'Legendary': 12}
C_SUL = {'Exalted': 1, 'Legendary': 2}
def c_fee(slot, rar_out, L, cl): return math.floor(0.5 * BASE[slot] * float(RM[rar_out]) * (1 + (L - 1) * 0.02) * (1 - 0.03 * (cl - 1)))
FAC['Crucible'] = [round(200 * (1 + l * l / 18)) for l in range(1, 11)]
assert sum(FAC['Crucible']) == 6277
UNLOCK_GH['Crucible'] = 5
RF = ['Common', 'Uncommon', 'Rare', 'Epic', 'Exalted', 'Legendary']
STEP_NAMES = ['C>U', 'U>R', 'R>E', 'E>Ex', 'Ex>L']
# ---------- facility timeline (same purchase logic as v2_tests_c.fac_sim, + Crucible) ----------
BS_TOT = BS_SHARE * INCOME; OTHER_TOT = NEC - BS_TOT
OTHER = [OTHER_TOT * x / INCOME for x in INC]; BSP = [BS_TOT * x / sum(INC) for x in INC]
CORE6 = ['Guild Hall', 'Tavern', 'Blacksmith', 'Merchant', 'Quest Board', 'Workshop']
STRATS = {
    'classic (Crucible after Runeforge)': [CORE6, ['Runeforge'], ['Crucible'], ['Training Ground'], ['Library'], ['Trophy Hall']],
    'crafter (Runeforge + Crucible with core)': [CORE6 + ['Runeforge', 'Crucible'], ['Training Ground'], ['Library'], ['Trophy Hall']],
    'merge rusher (Guild Hall + Crucible first)': [['Guild Hall', 'Crucible'], CORE6, ['Runeforge'], ['Training Ground'], ['Library'], ['Trophy Hall']],
}
STRATS10 = {'classic': [CORE6, ['Runeforge'], ['Training Ground'], ['Library'], ['Trophy Hall']]}
def fac_sim(groups, mult=1.0, extra=None, facs=None, total=77204):
    facs = facs or list(FAC)
    FMAX = {k: len(FAC[k]) for k in facs}
    lv = {k: 0 for k in facs}; fund = 500.0; saved = 0.0; tl = []
    def can(f):
        if lv[f] >= FMAX[f]: return False
        if f == 'Guild Hall': return True
        return lv['Guild Hall'] >= max(UNLOCK_GH[f], lv[f] + 1)
    for b in range(N_B):
        L = lvl_at(b)
        d = (3 * (lv['Blacksmith'] - 1)) / 100 if lv['Blacksmith'] >= 1 else 0.0
        saved += BSP[b] * d
        fund += INC[b] * mult - OTHER[b] - BSP[b] * (1 - d) - (extra[b] if extra else 0)
        while True:
            req = min(10, max(1, math.ceil(math.floor(L) / 10))); pick = None
            if lv['Blacksmith'] < req: pick = 'Blacksmith' if can('Blacksmith') else 'Guild Hall'
            else:
                for grp in groups:
                    if any(lv[f] < FMAX[f] for f in grp):
                        cands = [f for f in grp if can(f)]
                        blocked = [f for f in grp if lv[f] < FMAX[f] and not can(f)]
                        if blocked and can('Guild Hall') and 'Guild Hall' not in cands: cands.append('Guild Hall')
                        if cands: pick = min(cands, key=lambda f: FAC[f][lv[f]])
                        break
            if pick is None or FAC[pick][lv[pick]] > fund: break
            fund -= FAC[pick][lv[pick]]; lv[pick] += 1
        tl.append(dict(lv))
    xs = sum(extra) if extra else 0
    return dict(levels=lv, maxed=f"{sum(1 for f in lv if lv[f] == FMAX[f])}/{len(facs)}", leftover=round(fund),
                pressure_pct=round(100 * (NEC - saved + total + xs) / (INCOME * mult), 1), tl=tl)
def first_battle(tl, fac, level):
    for b, s in enumerate(tl):
        if s.get(fac, 0) >= level: return b
    return None
def craft_extra(total, lo=40):
    idx = [b for b in range(N_B) if lvl_at(b) >= lo]
    return [total / len(idx) if b in idx else 0 for b in range(N_B)]
# ---------- loot model ----------
W = 0.90
def norm(d): s = sum(d.values()); return {k: v / s for k, v in d.items()}
TAB_N = norm({r: LW_N[r][0] for r in RF})                    # normal table (Mythic 0)
TAB_E = norm({r: LW_N[r][1] for r in RF + ['Mythic']})       # elite table
TAB_B = norm({r: LW_N[r][1] for r in ['Rare', 'Epic', 'Exalted', 'Legendary', 'Mythic']})   # boss: elite table, Rare or better (assumption)
LAM_N = (0.40 - 0.034 * 0.75 - 0.034) * W                    # normal-table items per battle (0.40 includes the base elite/boss item)
P_ELITE = 0.034 * W * 0.75
B8 = 81
BOSS_P = {'random picker (B4)': 13 / (N_B - B8), 'boss hunter (B4, 80 contracts)': 234 / (N_B - B8)}
def draw(rng, tab):
    x = rng.random(); a = 0.0
    for r, p in tab.items():
        a += p
        if x < a: return r
    return r
def poisson(rng, lam):
    L = math.exp(-lam); k = 0; p = 1.0
    while True:
        p *= rng.random()
        if p <= L: return k
        k += 1
SHELF = [0, 5, 5, 6, 7, 7, 8, 9, 10, 10, 10]
ODDS = {1: {'Common': 100}, 2: {'Common': 90, 'Uncommon': 10}, 3: {'Common': 80, 'Uncommon': 20}, 4: {'Common': 70, 'Uncommon': 30},
        5: {'Common': 55, 'Uncommon': 40, 'Rare': 5}, 6: {'Common': 45, 'Uncommon': 45, 'Rare': 10}, 7: {'Common': 35, 'Uncommon': 45, 'Rare': 20},
        8: {'Common': 25, 'Uncommon': 45, 'Rare': 30}, 9: {'Common': 15, 'Uncommon': 35, 'Rare': 35, 'Epic': 15},
        10: {'Common': 10, 'Uncommon': 30, 'Rare': 40, 'Epic': 15, 'Exalted': 5}}
ODDS = {k: norm(v) for k, v in ODDS.items()}

def run(trials, pool, boss, policy, cap, tl, mult=1.0, shelves_per_restock=1, bm_rate=0.03, buy_rar=None, seed_off=0, uniform=False, budget_frac=None):
    """policy: 'loot' (loot only) | 'targeted' (also buys shop/BM items that match a held archetype+rarity group).
    buy_rar: rarities the player is willing to buy for merging (default all C..Ex).
    budget_frac: None = no gold limit; else the share of each battle's income (x mult) that may be spent on merge inputs and fees."""
    slots = list(pool); arch_n = pool; flat = [(s, k) for s in slots for k in range(pool[s])]
    buy_rar = buy_rar or RF[:5]
    agg = dict(merges={s: 0 for s in STEP_NAMES}, out={r: 0 for r in RF}, fee=0, cry=0, sul=0, merc_lost=0, cry_lost=0, sul_lost=0,
               buy_gold=0, bought=0, bought_by={r: 0 for r in RF}, loot={r: 0 for r in RF + ['Mythic']}, max_res_over_map=0, maint=0)
    per_trial_L = []; per_trial_Ex = []; per_trial_E = []
    for t in range(trials):
        rng = random.Random(SEED + seed_off * 100000 + t)
        P = {}          # (slot, k, rar) -> list of [level, age]
        n_items = 0; age = 0; mergedL = 0; mergedEx = 0; mergedE = 0; prev_cl = -1; dirty = set()
        fund = 0.0
        def add(slot, k, rar, L):
            nonlocal n_items, age
            age += 1; P.setdefault((slot, k, rar), []).append([L, age]); n_items += 1; dirty.add((slot, k, rar))
        def pick_arch():
            if uniform: return flat[rng.randrange(len(flat))]
            s = slots[rng.randrange(len(slots))]; return s, rng.randrange(arch_n[s])
        for b in range(N_B):
            L = max(1, math.floor(lvl_at(b))); st = tl[b]; cl = st.get('Crucible', 0); ml = st.get('Merchant', 0)
            if budget_frac is not None: fund += INC[b] * mult * budget_frac
            # loot
            for _ in range(poisson(rng, LAM_N)):
                r = draw(rng, TAB_N); s, k = pick_arch(); agg['loot'][r] += 1; add(s, k, r, L)
            if rng.random() < P_ELITE:
                r = draw(rng, TAB_E); s, k = pick_arch(); agg['loot'][r] += 1
                if r != 'Mythic': add(s, k, r, L)
            if b >= B8 and rng.random() < BOSS_P[boss]:
                r = draw(rng, TAB_B); s, k = pick_arch(); agg['loot'][r] += 1
                if r != 'Mythic': add(s, k, r, L)
            # shop / Black Market (targeted buying)
            if policy == 'targeted':
                offers = []
                if ml >= 1 and b % 5 == 4:
                    for _ in range(shelves_per_restock):
                        for _ in range(SHELF[ml]):
                            r = draw(rng, ODDS[ml]); s, k = pick_arch(); offers.append((s, k, r, 1.0))
                if rng.random() < bm_rate:
                    for _ in range(6):
                        r = 'Rare' if rng.random() < 0.75 else 'Epic'; s, k = pick_arch(); offers.append((s, k, r, 0.75))
                for s, k, r, f in offers:
                    if r in buy_rar and P.get((s, k, r)):
                        price = math.floor(shop(s, r, L) * f) if f < 1 else shop(s, r, L)
                        if budget_frac is not None:
                            if fund < price: continue
                            fund -= price
                        agg['buy_gold'] += price; agg['bought'] += 1; agg['bought_by'][r] += 1; add(s, k, r, L)
            # merges
            if cl >= 1:
                N = c_need(cl); mo = RF.index(c_maxout(cl)); again = True
                check = set(P.keys()) if cl != prev_cl else set(dirty)
                prev_cl = cl
                while again:
                    again = False
                    for key in list(check):
                        s, k, r = key; lst = P.get(key, [])
                        ri = RF.index(r)
                        if len(lst) >= N and ri + 1 <= mo:
                            lst.sort(key=lambda x: -x[0]); use = lst[:N]; P[key] = lst[N:]
                            if not P[key]: del P[key]
                            n_items -= N
                            out = RF[ri + 1]
                            raw = math.floor(sum(x[0] for x in use) / N) + c_boost(cl)
                            agg['max_res_over_map'] = max(agg['max_res_over_map'], raw - L)
                            rl = min(raw, L, 99)
                            agg['merges'][STEP_NAMES[ri]] += 1; agg['out'][out] += 1
                            agg['fee'] += c_fee(s, out, rl, cl); agg['cry'] += C_CRY[out]; agg['sul'] += C_SUL.get(out, 0)
                            agg['merc_lost'] += sum(dis_merc(x[0]) for x in use) - dis_merc(rl)
                            agg['cry_lost'] += N * DIS_CRY[r] - DIS_CRY[out]; agg['sul_lost'] += N * DIS_SUL[r] - DIS_SUL[out]
                            if out == 'Legendary': mergedL += 1
                            if out == 'Exalted': mergedEx += 1
                            if out == 'Epic': mergedE += 1
                            add(s, k, out, rl); again = True; check = set(check); check.add((s, k, out))
                            break
            dirty.clear()
            # inventory cap: discard lowest-value groups first (count x rarity multiplier), oldest first
            if cap is not None and n_items > cap:
                while n_items > cap:
                    key = min(P, key=lambda kk: (len(P[kk]) * float(RM[kk[2]]), min(x[1] for x in P[kk])))
                    P[key].sort(key=lambda x: x[1]); P[key].pop(0); n_items -= 1
                    if not P[key]: del P[key]
            elif cap is None:
                agg['maint'] += min(max(0, n_items - 50) * 5, 200)
        per_trial_L.append(mergedL); per_trial_Ex.append(mergedEx); per_trial_E.append(mergedE)
    n = trials
    res = {k: (round(v / n, 2) if isinstance(v, (int, float)) and k != 'max_res_over_map' else v) for k, v in agg.items() if not isinstance(v, dict)}
    for k in ('merges', 'out', 'bought_by', 'loot'): res[k] = {kk: round(vv / n, 2) for kk, vv in agg[k].items()}
    per_trial_L.sort()
    res['legendary_merges_p90'] = per_trial_L[int(0.9 * n)]; res['legendary_merges_max'] = per_trial_L[-1]
    res['P_at_least_1_legendary_merge'] = round(sum(1 for x in per_trial_L if x >= 1) / n, 3)
    return res

R = dict(seed=SEED, db_md5_start=MD5_START, catalog=CATALOG)
# ---------- 1. facility timelines ----------
TL = {}
fac = {}
for who, mult in (('free', 1.0), ('boosted', 1.25)):
    for crafted, x in (('crafting from Rare (4,919g)', 4919), ('crafting from Common (8,884g)', 8884)):
        base10 = fac_sim(STRATS10['classic'], mult, craft_extra(x), facs=[f for f in FAC if f != 'Crucible'], total=70927)
        row_ = {'10 facilities (repro)': dict(maxed=base10['maxed'], pressure=base10['pressure_pct'])}
        for sn, g in STRATS.items():
            r_ = fac_sim(g, mult, craft_extra(x))
            row_[sn] = dict(maxed=r_['maxed'], pressure=r_['pressure_pct'], crucible_final=r_['levels']['Crucible'],
                            crucible_L1_at_map_level=(lambda bb: round(lvl_at(bb), 1) if bb is not None else None)(first_battle(r_['tl'], 'Crucible', 1)),
                            crucible_L7_at=(lambda bb: round(lvl_at(bb), 1) if bb is not None else None)(first_battle(r_['tl'], 'Crucible', 7)),
                            crucible_L9_at=(lambda bb: round(lvl_at(bb), 1) if bb is not None else None)(first_battle(r_['tl'], 'Crucible', 9)),
                            crucible_L10_at=(lambda bb: round(lvl_at(bb), 1) if bb is not None else None)(first_battle(r_['tl'], 'Crucible', 10)),
                            merchant_L10_at=(lambda bb: round(lvl_at(bb), 1) if bb is not None else None)(first_battle(r_['tl'], 'Merchant', 10)))
            if crafted.startswith('crafting from Rare'): TL[(who, sn)] = r_['tl']
        fac[f'{who} | {crafted}'] = row_
R['facilities'] = fac
# all-maxed timeline (upper bound for supply): Crucible L10 as early as possible
TL[('upper', 'merge rusher')] = fac_sim(STRATS['merge rusher (Guild Hall + Crucible first)'], 1.25)['tl']
# ---------- 2. Monte Carlo supply ----------
TR = globals().get('TR_OVERRIDE', 300)
MC = {}
POOL = POOLS['code (146), slot first']
for who in ('free', 'boosted'):
    tl = TL[(who, 'classic (Crucible after Runeforge)')]
    for boss in BOSS_P:
        for policy in ('loot', 'targeted'):
            for cap in (30, 55, None):
                MC[f'{who} | {boss} | {policy} | spare cap {cap}'] = run(TR, POOL, boss, policy, cap, tl, seed_off=1)
# sensitivities
tlb = TL[('boosted', 'classic (Crucible after Runeforge)')]
MC['SENS boosted | random | targeted | cap 55 | DB pool 156'] = run(TR, POOLS['DB (156), slot first'], 'random picker (B4)', 'targeted', 55, tlb, seed_off=2)
MC['SENS boosted | random | targeted | cap 55 | uniform over 146'] = run(TR, POOL, 'random picker (B4)', 'targeted', 55, tlb, seed_off=3, uniform=True)
MC['SENS boosted | random | targeted | cap 55 | merge rusher timeline'] = run(TR, POOL, 'random picker (B4)', 'targeted', 55, TL[('boosted', 'merge rusher (Guild Hall + Crucible first)')], seed_off=4)
MC['SENS boosted | random | targeted | cap 55 | BM 5%'] = run(TR, POOL, 'random picker (B4)', 'targeted', 55, tlb, seed_off=5, bm_rate=0.05)
for K in (3, 10):
    MC[f'EXPLOIT shelf per map level x{K} | boosted | random | targeted | cap 55'] = run(TR, POOL, 'random picker (B4)', 'targeted', 55, tlb, seed_off=6 + K, shelves_per_restock=K)
    MC[f'EXPLOIT shelf per map level x{K} | boosted | hunter | targeted | cap 55'] = run(TR, POOL, 'boss hunter (B4, 80 contracts)', 'targeted', 55, tlb, seed_off=20 + K, shelves_per_restock=K)
MC['UPPER all-in: earliest Crucible, unlimited spares, buy every match, hunter'] = run(TR, POOL, 'boss hunter (B4, 80 contracts)', 'targeted', None, TL[('upper', 'merge rusher')], seed_off=40)
# gold-limited buying: a boosted player may spend only his spare gold (100% - spending pressure) on merge inputs
SPARE_B = round((100 - fac['boosted | crafting from Rare (4,919g)']['classic (Crucible after Runeforge)']['pressure']) / 100, 3)
R['spare_frac_boosted'] = SPARE_B
for boss in BOSS_P:
    for cap in (30, 55):
        MC[f'BUDGET boosted | {boss} | targeted | cap {cap} | spare {SPARE_B}'] = run(TR, POOL, boss, 'targeted', cap, tlb, mult=1.25, seed_off=50 + cap, budget_frac=SPARE_B)
    MC[f'BUDGET boosted | {boss} | targeted | cap 55 | spare {SPARE_B} | merge rusher'] = run(TR, POOL, boss, 'targeted', 55, TL[('boosted', 'merge rusher (Guild Hall + Crucible first)')], mult=1.25, seed_off=60, budget_frac=SPARE_B)
    MC[f'BUDGET boosted | {boss} | Exalted-only buying | cap 55 | spare {SPARE_B}'] = run(TR, POOL, boss, 'targeted', 55, tlb, mult=1.25, seed_off=61, budget_frac=SPARE_B, buy_rar=['Exalted'])
    for K in (3, 10):
        MC[f'BUDGET EXPLOIT shelf per map level x{K} | boosted | {boss} | cap 55'] = run(TR, POOL, boss, 'targeted', 55, tlb, mult=1.25, seed_off=70 + K, shelves_per_restock=K, budget_frac=SPARE_B)
    MC[f'BUDGET free crafter timeline | {boss} | loot only | cap 55'] = run(TR, POOL, boss, 'loot', 55, TL[('free', 'crafter (Runeforge + Crucible with core)')], seed_off=80)
    MC[f'BUDGET free merge rusher | {boss} | loot only | cap 55'] = run(TR, POOL, boss, 'loot', 55, TL[('free', 'merge rusher (Guild Hall + Crucible first)')], seed_off=81)
R['mc'] = MC
# natural loot reference (expected values, no Crucible)
nat = {}
for boss, p in BOSS_P.items():
    nb = p * (N_B - B8)
    nat[boss] = {r: round(N_B * (LAM_N * TAB_N.get(r, 0) + P_ELITE * TAB_E.get(r, 0)) + nb * TAB_B.get(r, 0), 2) for r in ['Common', 'Uncommon', 'Rare', 'Epic', 'Exalted', 'Legendary', 'Mythic']}
R['natural_loot'] = nat
# ---------- 3. shelf duplicate odds (Merchant L10, one restock) ----------
def shelf_dupes(trials=200000, pool=POOL):
    rng = random.Random(SEED + 9); slots = list(pool); c2 = c3 = 0; ex2 = 0
    for _ in range(trials):
        seen = {}
        for _ in range(10):
            r = draw(rng, ODDS[10]); s = slots[rng.randrange(len(slots))]; k = rng.randrange(pool[s])
            seen[(s, k, r)] = seen.get((s, k, r), 0) + 1
        m = max(seen.values()); c2 += m >= 2; c3 += m >= 3
        ex2 += any(v >= 2 and kk[2] == 'Exalted' for kk, v in seen.items())
    return dict(P_any_pair_same_arch_same_rarity=round(c2 / trials, 4), P_any_triple=round(c3 / trials, 6), P_exalted_pair=round(ex2 / trials, 6))
R['shelf_dupes_L10'] = shelf_dupes()
# ---------- 4. deterministic route values (exploit search) ----------
routes = {}
for L in (50, 99):
    for s in ('1H', '2H', 'Gloves', 'Off-Hand'):
        rr = {}
        for ri in range(4):            # C>U .. E>Ex with 3 inputs (L8-10), U>R 3, etc.; Ex>L separately
            rin, rout = RF[ri], RF[ri + 1]
            buy_in = 3 * shop(s, rin, L); fee = c_fee(s, rout, L, 10)
            direct = shop(s, rout, L)
            rr[f'{rin}>{rout}'] = dict(buy_3_inputs=buy_in, fee_L10=fee, buy_result_directly=direct,
                                       sell_result=sell(s, rout, L), sell_3_inputs=3 * sell(s, rin, L),
                                       crystals_merge_route=C_CRY[rout] + 3 * DIS_CRY[rin], crystals_runeforge_step=STEP.get(rout))
        rr['Exalted>Legendary'] = dict(buy_3_merchant_exalted=3 * shop(s, 'Exalted', L), fee_L10=c_fee(s, 'Legendary', L, 10),
                                      sell_result=sell(s, 'Legendary', L), dismantle_3_inputs='12 crystals + 3 sulfur', merge_cost='12 crystals + 2 sulfur, then Legendary dismantles to 6 + 2')
        rr['BM 3 Rares > Epic vs Merchant Epic'] = dict(bm_3_rares=3 * math.floor(shop(s, 'Rare', L) * 0.75) + c_fee(s, 'Epic', L, 10), merchant_epic=shop(s, 'Epic', L))
        routes[f'{s} L{L}'] = rr
R['routes'] = routes
# levelling inputs vs levelling result (B5 check): 1 level on an input moves the result by 1/N level
lv = {}
for N in (3, 4, 5):
    for rin in ('Common', 'Uncommon', 'Rare', 'Epic', 'Exalted'):
        rout = RF[RF.index(rin) + 1]
        lv[f'N{N} {rin}>{rout}'] = round(N * float(RM[rin]) / float(RM[rout]), 2)   # >1 = levelling inputs costs more per result level
R['level_inputs_cost_ratio'] = lv
# mercury per merge forgone (all inputs at map level, Crucible L10)
R['mercury_per_merge'] = {f'L{L}': dict(inputs_dismantle=3 * dis_merc(L), result_dismantle=dis_merc(L), net_lost=2 * dis_merc(L), boost_levels_saved_max=5) for L in (20, 50, 80, 99)}
# fee check: 1H L50 Epic at Crucible L1/L10, 1H L99 Legendary L10
R['fee_examples'] = {'1H L50 Epic CL1': c_fee('1H', 'Epic', 50, 1), '1H L50 Epic CL10': c_fee('1H', 'Epic', 50, 10), '1H L99 Legendary CL10': c_fee('1H', 'Legendary', 99, 10), '2H L99 Legendary CL10': c_fee('2H', 'Legendary', 99, 10)}
# ---------- 5. gold share with merge fees + targeted buying ----------
gold = {}
for boss in BOSS_P:
    cases = [('free', 1.0, 'loot-only merges (fees)', MC[f'free | {boss} | loot | spare cap 55']['fee']),
             ('free', 1.0, 'merge rusher, loot-only (fees)', MC[f'BUDGET free merge rusher | {boss} | loot only | cap 55']['fee']),
             ('boosted', 1.25, 'loot-only merges (fees)', MC[f'boosted | {boss} | loot | spare cap 55']['fee']),
             ('boosted', 1.25, 'buying with spare gold (fees + purchases)', MC[f'BUDGET boosted | {boss} | targeted | cap 55 | spare {SPARE_B}']['fee'] + MC[f'BUDGET boosted | {boss} | targeted | cap 55 | spare {SPARE_B}']['buy_gold'])]
    for who, mult, nm, extra_merge in cases:
        g = {}
        for sn in ('classic (Crucible after Runeforge)', 'merge rusher (Guild Hall + Crucible first)'):
            r_ = fac_sim(STRATS[sn], mult, craft_extra(4919 + extra_merge))
            g[sn] = dict(maxed=r_['maxed'], pressure=r_['pressure_pct'], crucible=r_['levels']['Crucible'])
        gold[f'{who} | {boss} | {nm} | +{round(extra_merge)}g'] = g
R['gold'] = gold
R['db_md5_end'] = md5(DBP); R['prov'] = PROV; R['runtime_s'] = round(time.time() - T0, 1)
json.dump(R, open(OUTD + r'\results_crucible.json', 'w', encoding='utf-8'), indent=1, default=str)
print('ok', R['runtime_s'], 's  md5', MD5_START[:8], R['db_md5_end'][:8])
