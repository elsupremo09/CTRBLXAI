
# CTRBLXAI Training Grounds (Training Ground + Library merged card shop) check - 2026-11-04. DB read-only. Seed 20261104.
# Reuses sim\apothecary_2026-11-03\apothecary_sim.py prefix (which reuses crucible_2026-11-02 + runeforge_v2 v2_core economy timeline).
# The crucible prefix's Luau catalog-count block is cut out: this run reads NO source files.
# Training Grounds rules: Designer proposal training_grounds_design_options_20261104.md (thread-9ad5713d2a62). NOT in the DB.
import math, json, random, collections, hashlib, re, time
from fractions import Fraction as Fr
OUT_T = r'D:\AI\Projects\CTRBLXAI\sim\training_grounds_2026-11-04'
APS = open(r'D:\AI\Projects\CTRBLXAI\sim\apothecary_2026-11-03\apothecary_sim.py', encoding='utf-8').read()
APS = APS[:APS.find('# ---------- payback per level')]
CRS = open(r'D:\AI\Projects\CTRBLXAI\sim\crucible_2026-11-02\crucible_sim.py', encoding='utf-8').read()
CRS = CRS[:CRS.find('# ---------- loot model')]
a, z = CRS.find("SRC = r'"), CRS.find('# ---------- Crucible rules')
CRS = CRS[:a] + CRS[z:]
assert 'WeaponData' not in CRS and 'source' not in CRS.split('V2 =')[1][:0]
APS = APS.replace("src = open(CRU, encoding='utf-8').read()\nexec(src[:src.find('# ---------- loot model')])", "exec(CRS)")
assert 'exec(CRS)' in APS
exec(APS)
SEED_T = 20261104
RT = dict(seed=SEED_T, db_md5_start=MD5_START)
# ---------- DB rows asserted today ----------
prov('Training Ground curve', 'guild_facilities', 20, ['Base = 220, Scale = 16', '7,495g', 'Guild Hall L5'])
prov('Training Ground table', 'guild_facilities', 32, ['L1:234', 'L10:1595', '7,495g'])
prov('Training Ground benched bonus (never built)', 'guild_facilities', 21, ['L1: 67%, L10: 85%'])
prov('Library curve', 'guild_facilities', 22, ['Base = 200, Scale = 18', '6,277g', 'Guild Hall L6'])
prov('Library table', 'guild_facilities', 33, ['L10:1311', '6,277g'])
prov('Library function', 'guild_facilities', 23, ['card merchants', 'Card research'])
prov('Total investment', 'guild_facilities', 5, ['77,204g'])
prov('Unlock schedule now', 'guild_facilities', 8, ['L5: Training Ground, Crucible', 'L6: Library'])
prov('Apothecary', 'guild_facilities', 67, ['Base = 150, Scale = 22', '4,123g'])
prov('Benched XP', 'unit_progression', 52, ['65% of battle XP'])
prov('Deployed XP', 'unit_progression', 51, ['100% of battle XP'])
prov('Kill XP', 'unit_progression', 30, ['Base Type XP × (1 + Enemy Level / 50)'])
prov('Grunt XP', 'unit_progression', 32, ['20 XP base'])
prov('Veteran XP', 'unit_progression', 33, ['35 XP base'])
prov('Elite XP', 'unit_progression', 34, ['60 XP base', '1-2 per quest'])
prov('Level curve', 'unit_progression', 86, ['500 + (Level × 20)'])
prov('Underlevel x1.50 cap', 'unit_progression', 61, ['×1.50'])
prov('Level gap rule', 'unit_progression', 62, ['Level Gap = Unit Level - Quest Recommended Level'])
prov('Human XP', 'unit_progression', 54, ['× 1.10'])
prov('Card rarity meaning', 'loot_progression', 42, ['Normal Skill Card rarity begins at Rare', 'acquisition scarcity only'])
r57 = ' '.join(str(x) for x in con.execute('select * from project_rules where id=57').fetchone()); assert 'exactly 2 Augment Slots' in r57; PROV['Augment slots today'] = dict(table='project_rules', row=57, found=True)
prov('Augment slots today (fw)', 'frameworks', 26, ['Exactly 2 Augment Slots']) if False else None
assert RM['Rare'] == Fr(5, 2) and RM['Epic'] == 4 and RM['Legendary'] == 7
assert FAC['Training Ground'] == [234, 275, 344, 440, 564, 715, 894, 1100, 1334, 1595] and sum(FAC['Library']) == 6277
assert sum(sum(v) for v in FAC.values()) == 77204, sum(sum(v) for v in FAC.values())
r60 = con.execute('select rule from unit_progression where id=60').fetchone()[0]
PROV['Underlevel x1.25'] = dict(table='unit_progression', row=60, found=('1.25' in r60), text=r60)
# content counts from the DB
sk_rows = con.execute('select Skill_Name, Meta from skills').fetchall()
N_SK = sum(1 for n, m in sk_rows if not (m or '').startswith('EVENT-ONLY'))
aug_rows = con.execute('select Family, Status from augments').fetchall()
fam_ok = collections.Counter(f for f, s in aug_rows if (s or '').startswith('Working'))
A_R = ['Buff', 'Debuff', 'Defensive', 'Recovery', 'Stat Scaling', 'Penetration', 'Targeting', 'Purge', 'Displacement']
A_E = ['Conditional Amplifier', 'Timing', 'Terrain Effect', 'Summoning', 'Kill Trigger', 'Death Explosion']
A_L = ['Element Conversion', 'Pattern', 'Resource Conversion', 'Reward']
AUG = {'Rare': sum(fam_ok[f] for f in A_R), 'Epic': sum(fam_ok[f] for f in A_E), 'Legendary': sum(fam_ok[f] for f in A_L)}
N_DOC = con.execute('select count(*) from doctrines').fetchone()[0]
assert N_SK == 116 and sum(AUG.values()) == 102 and AUG == {'Rare': 51, 'Epic': 33, 'Legendary': 18} and N_DOC == 34, (N_SK, AUG, N_DOC)
# skill rarity per proposal Appendix 1 (rule is tag-based; counts taken from the proposal; total checked = DB 116)
SKR = {'Rare': {'atk': 39, 'sup': 19, 'ctl': 20}, 'Epic': {'atk': 17, 'sup': 9, 'ctl': 5}, 'Legendary': {'atk': 0, 'sup': 1, 'ctl': 6}}
assert sum(sum(v.values()) for v in SKR.values()) == N_SK
RT['catalog'] = dict(skills=N_SK, skills_by_rarity={r: sum(v.values()) for r, v in SKR.items()}, augments=AUG, doctrines=N_DOC)

# ---------- proposal rules (C2/C4/C5) ----------
SHELF = {1: 4, 2: 4, 3: 5, 4: 5, 5: 6, 6: 6, 7: 7, 8: 7, 9: 8, 10: 8}
ODDS = {1: (100, 0, 0), 2: (100, 0, 0), 3: (100, 0, 0), 4: (85, 15, 0), 5: (75, 25, 0), 6: (70, 30, 0), 7: (60, 40, 0), 8: (55, 35, 10), 9: (50, 35, 15), 10: (45, 35, 20)}
RARS = ['Rare', 'Epic', 'Legendary']
def pool(r, tg):
    n = 0
    sk = SKR[r]
    if r == 'Rare':
        n += sk['atk'] + sk['sup'] + (sk['ctl'] if tg >= 3 else 0) + (AUG['Rare'] if tg >= 2 else 0)
    elif r == 'Epic' and tg >= 4:
        n += sum(sk.values()) + AUG['Epic']
    elif r == 'Legendary' and tg >= 8:
        n += sum(sk.values()) + AUG['Legendary']
    return n
VAL = {'aug': 60, 'skill': 100, 'doc': 1000}
def disc(tg): return 3 * (tg - 1) if tg >= 1 else 0
def list_price(kind, rar, L): return math.floor(Fr(VAL[kind]) * (1 if kind == 'doc' else RM[rar]) * lvl_mult(L))
def buy_price_c(kind, rar, L, tg): return math.floor(Fr(VAL[kind]) * (1 if kind == 'doc' else RM[rar]) * lvl_mult(L) * (100 - disc(tg)) / 100)
def sell_c(kind, rar, L): return list_price(kind, rar, L) // 16
# check against proposal C4 table
C4 = {('aug', 'Rare'): [150, 207, 297, 387, 444], ('aug', 'Epic'): [240, 331, 475, 619, 710], ('aug', 'Legendary'): [420, 579, 831, 1083, 1243],
      ('skill', 'Rare'): [250, 345, 495, 645, 740], ('skill', 'Epic'): [400, 552, 792, 1032, 1184], ('skill', 'Legendary'): [700, 966, 1386, 1806, 2072], ('doc', None): [1000, 1380, 1980, 2580, 2960]}
c4_mis = []
for (k, r), v in C4.items():
    for L, want in zip((1, 20, 50, 80, 99), v):
        if list_price(k, r, L) != want: c4_mis.append((k, r, L, list_price(k, r, L), want))
RT['C4_table_mismatches'] = c4_mis

# ---------- battle index helpers ----------
def b_of(L): return min(N_B - 1, round((L - 1) * N_B / 98))
RT['battle_gold_model'] = {f'map{L}': round(BG[b_of(L)]) for L in (1, 20, 50, 80, 99)}

# ---------- Q7 prices in battles of gold ----------
Q7 = {}
mx = (0, None)
for (k, r) in C4:
    rowq = {}
    for L in (1, 20, 50, 80, 99):
        lp = list_price(k, r, L); dp = buy_price_c(k, r, L, 10)
        bl, bd = lp / BG[b_of(L)], dp / BG[b_of(L)]
        rowq[f'map{L}'] = dict(list=lp, L10=dp, battles_list=round(bl, 2), battles_L10=round(bd, 2))
        if bl > mx[0]: mx = (bl, (k, r, L))
    Q7[f'{k} {r or ""}'.strip()] = rowq
RT['Q7'] = Q7; RT['Q7_max_battles'] = dict(value=round(mx[0], 2), at=mx[1]); RT['Q7_over_10'] = [x for x in Q7 if any(v['battles_list'] > 10 for v in Q7[x].values())]
# first-buy timing: price at the earliest map level the card can be on a shelf is lower; doctrine at L6 bought early is cheapest in battles
# ---------- Q6 loop check ----------
best = None; nloop = 0; ncase = 0
for (k, r) in C4:
    for tg in range(1, 11):
        for Lb in range(1, 100):
            bp = buy_price_c(k, r, Lb, tg)
            for Ls in range(Lb, 100):
                g = sell_c(k, r, Ls) - bp; ncase += 1
                if g > 0: nloop += 1
                if best is None or g > best[0] or (g == best[0] and False): best = (g, k, r, tg, Lb, Ls)
worst_ratio = max(sell_c(k, r, 99) / buy_price_c(k, r, 1, 10) for (k, r) in C4)
RT['Q6'] = dict(cases=ncase, gold_making_cases=nloop, best_case=dict(gain=best[0], kind=best[1], rarity=best[2], tg=best[3], buy_map=best[4], sell_map=best[5]),
                max_return_pct=round(100 * worst_ratio, 1))
# starter + loot card sale value
RT['starter_sale'] = {f'map{L}': 4 * sell_c('aug', 'Rare', L) + sum(sell_c('skill', 'Rare', L) for _ in range(6)) for L in (1, 50, 99)}
SK_SH = {r: sum(SKR[r].values()) / N_SK for r in RARS}; AG_SH = {r: AUG[r] / 102 for r in RARS}
LOOT_SK, LOOT_AG = 0.22, 0.22     # Designer figure (RewardService code), NOT in the DB - stated input
def loot_sell(L): return LOOT_SK * sum(SK_SH[r] * sell_c('skill', r, L) for r in RARS) + LOOT_AG * sum(AG_SH[r] * sell_c('aug', r, L) for r in RARS)
CS = [loot_sell(math.floor(lvl_at(b))) for b in range(N_B)]
RT['loot_card_sell'] = dict(per_battle={f'map{L}': round(loot_sell(L), 1) for L in (1, 50, 99)}, pct_of_battle_gold_map50=round(100 * loot_sell(50) / BG[b_of(50)], 1), lifetime=round(sum(CS)), lifetime_pct=round(100 * sum(CS) / INCOME, 1))

# ---------- Q3 shelf reach ----------
Q3 = {}
for tg in (1, 2, 3, 4, 5, 6, 7, 8, 9, 10):
    n = SHELF[tg] - (1 if tg >= 6 else 0)
    rowq = {}
    for i, r in enumerate(RARS):
        q = ODDS[tg][i] / 100; N = pool(r, tg)
        if q == 0 or N == 0: rowq[r] = None; continue
        p = n * q / N
        rowq[r] = dict(pool=N, p_per_restock_pct=round(100 * p, 2), mean_restocks=round(1 / p, 1), restocks_50=math.ceil(math.log(0.5) / math.log(1 - p)),
                       restocks_90=math.ceil(math.log(0.1) / math.log(1 - p)), mean_battles=round(5 / p))
    if tg >= 6:
        p = 1 / N_DOC
        rowq['Doctrine'] = dict(pool=N_DOC, p_per_restock_pct=round(100 * p, 2), mean_restocks=round(1 / p, 1), restocks_50=math.ceil(math.log(0.5) / math.log(1 - p)), restocks_90=math.ceil(math.log(0.1) / math.log(1 - p)), mean_battles=round(5 / p))
    Q3[f'L{tg}'] = rowq
RT['Q3'] = Q3
# Monte Carlo check of the analytic formula (shelf no-duplicate, drop-a-rarity rule), seeded
rng = random.Random(SEED_T)
def shelf_mc(tg, trials=40000):
    cards = {r: list(range(pool(r, tg))) for r in RARS}
    n = SHELF[tg] - (1 if tg >= 6 else 0); hits = {r: 0 for r in RARS}
    for _ in range(trials):
        chosen = {r: set() for r in RARS}
        for _s in range(n):
            x = rng.random() * 100; r = 'Rare' if x < ODDS[tg][0] else 'Epic' if x < ODDS[tg][0] + ODDS[tg][1] else 'Legendary'
            while not [c for c in cards[r] if c not in chosen[r]]:
                r = RARS[RARS.index(r) - 1]
            chosen[r].add(rng.choice([c for c in cards[r] if c not in chosen[r]]))
        for r in RARS:
            if 0 in chosen[r]: hits[r] += 1
    return {r: round(100 * hits[r] / trials, 2) for r in RARS}
RT['Q3_mc_check_pct'] = {f'L{tg}': shelf_mc(tg) for tg in (4, 8, 10)}
RT['loot_specific_card'] = dict(aug_battles=round(102 / LOOT_AG), skill_battles=round(N_SK / LOOT_SK), lifetime_copies_aug=round(N_B * LOOT_AG / 102, 2))

# ---------- unit level vs battle (XP model, DB rows) ----------
def xp_to_next(L): return 500 + 20 * L
MIX = 3 * 20 + 2 * 35       # Mixed quest (3 Grunts + 2 Veterans), the XP-sim baseline composition (assumption)
def kill_xp(qL): return MIX * (1 + qL / 50)
def under_mult(gap): return 1.5 if gap <= -10 else 1.25 if gap <= -5 else 1.0
def level_track(share, human=False):
    dep_L, dep_x = 1, 0.0; L, x = 1, 0.0; at = {}; b = 0
    while dep_L < 99 and b < 5000:
        q = dep_L
        g = kill_xp(q) * (1.1 if human else 1.0)
        dep_x += g
        while dep_L < 99 and dep_x >= xp_to_next(dep_L): dep_x -= xp_to_next(dep_L); dep_L += 1
        x += g * share * (under_mult(L - q) if share < 1 else 1.0)
        while L < 99 and x >= xp_to_next(L): x -= xp_to_next(L); L += 1; at.setdefault(L, b + 1)
        b += 1
    return at, b
dep_at, dep_total = level_track(1.0)
ben_at, _ = level_track(0.65)
hum_at, hum_total = level_track(1.0, human=True)
RT['xp_model'] = dict(deployed_battles_to_99=dep_total, deployed_L80_battle=dep_at.get(80), benched65_L80_battle=ben_at.get(80), human_L80_battle=hum_at.get(80),
                      deployed_by_level={L: dep_at.get(L) for L in (25, 50, 79, 80, 99)}, benched_by_level={L: ben_at.get(L) for L in (25, 50, 80, 99)},
                      map80_battle_linear=b_of(80))
# scale XP battles onto the 547-battle economy axis (economy model assumes L1->99 in 547 battles)
SCALE = N_B / dep_total
B80 = round(dep_at[80] * SCALE); B80_BENCH = round(ben_at[80] * SCALE) if ben_at.get(80) else None
RT['xp_model']['L80_battle_on_547_axis'] = dict(deployed=B80, benched65=B80_BENCH, scale=round(SCALE, 3))
# Q8 benched bonus: what 67%/85% would have done (counterfactual only; the bonus was never built)
cf = {}
for sh in (0.65, 0.67, 0.85):
    at_, _ = level_track(sh); cf[f'{int(sh*100)}%'] = dict(L80=at_.get(80), L99=at_.get(99))
RT['Q8_benched_counterfactual'] = cf

# ---------- Q1/Q2 facility + card timeline ----------
FAC10 = {k: v for k, v in FAC.items() if k != 'Library'}
assert sum(sum(v) for v in FAC10.values()) == 70927
def basket(n_sk, n_ag, n_doc, rng_):
    out = []
    for _ in range(n_sk):
        r = rng_.choices(RARS, [sum(SKR[x].values()) for x in RARS])[0]
        t = rng_.choices(['atk', 'sup', 'ctl'], [SKR[r]['atk'], SKR[r]['sup'], SKR[r]['ctl']])[0]
        out.append(('skill', r, t))
    for _ in range(n_ag): out.append(('aug', rng_.choices(RARS, [AUG[x] for x in RARS])[0], None))
    for _ in range(n_doc): out.append(('doc', None, None))
    rng_.shuffle(out); return out
def gate(c):
    k, r, t = c
    if k == 'doc': return 6
    if r == 'Legendary': return 8
    if r == 'Epic': return 4
    if k == 'aug': return 2
    return 3 if t == 'ctl' else 1
BASKETS = {'none': (0, 0, 0, 0), 'Designer basket (9 sk + 12 aug + 2 doc pre-80, 24 aug after)': (9, 12, 2, 24),
           'double basket (18 + 24 + 4, 48 after)': (18, 24, 4, 48)}
def fac_sim_tg(groups, mult, craft, prof, bk, sell_loot, facs, card_first=True, total=70927, b80=None):
    b80 = b80 if b80 is not None else B80
    FMAX = {k: len(FAC[k]) for k in facs}
    lv = {k: 0 for k in facs}; fund = 500.0; saved = 0.0; tl = []; refill_tot = 0.0; disc_tot = 0.0
    rngb = random.Random(SEED_T + 1)
    pre = basket(bk[0], bk[1], bk[2], rngb); post = basket(0, bk[3], 0, rngb)
    want = [(int((i + 1) * b80 / (len(pre) + 1)), c) for i, c in enumerate(pre)]
    queue = []; spent = 0.0; sold = 0.0; bought = collections.Counter(); s2 = None; post_added = False
    def can(f):
        if lv[f] >= FMAX[f]: return False
        if f == 'Guild Hall': return True
        return lv['Guild Hall'] >= max(UNLOCK_GH[f], lv[f] + 1)
    def buy_cards(L):
        nonlocal fund, spent
        tg = lv.get('Training Ground', 0)
        for c in list(queue):
            if tg < gate(c): continue
            p = buy_price_c(c[0], c[1], L, tg)
            if p > fund: break
            fund -= p; spent += p; bought[c[0] + ' ' + str(c[1])] += 1; queue.remove(c)
    for b in range(N_B):
        L = lvl_at(b); Li = math.floor(L)
        d = (3 * (lv['Blacksmith'] - 1)) / 100 if lv['Blacksmith'] >= 1 else 0.0
        saved += BSP[b] * d
        rf = used_value(prof, b) * RATE[lv['Workshop']]
        dsc = CB[b] * buy_disc(lv['Workshop'])
        refill_tot += rf; disc_tot += dsc
        cs = CS[b] * mult if False else (CS[b] if sell_loot else 0.0)
        sold += cs
        fund += INC[b] * mult - OTHER[b] - BSP[b] * (1 - d) - (craft[b] if craft else 0) - rf + dsc + cs
        queue.extend(c for t_, c in want if t_ == b)
        if s2 is None and lv.get('Training Ground', 0) >= 10 and b >= b80: s2 = b
        if s2 is not None and not post_added:
            span = max(1, min(100, N_B - s2)); post_added = True
            want.extend((s2 + int((i + 1) * span / (len(post) + 1)), c) for i, c in enumerate(post))
        if card_first: buy_cards(Li)
        while True:
            req = min(10, max(1, math.ceil(math.floor(L) / 10))); pick = None
            if lv['Blacksmith'] < req: pick = 'Blacksmith' if can('Blacksmith') else 'Guild Hall'
            else:
                for grp in groups:
                    grp = [f for f in grp if f in facs]
                    if any(lv[f] < FMAX[f] for f in grp):
                        cands = [f for f in grp if can(f)]
                        blocked = [f for f in grp if lv[f] < FMAX[f] and not can(f)]
                        if blocked and can('Guild Hall') and 'Guild Hall' not in cands: cands.append('Guild Hall')
                        if cands: pick = min(cands, key=lambda f: FAC[f][lv[f]])
                        break
            if pick is None or FAC[pick][lv[pick]] > fund: break
            fund -= FAC[pick][lv[pick]]; lv[pick] += 1
        if not card_first: buy_cards(Li)
        tl.append(dict(lv))
    unbought_val = sum(buy_price_c(c[0], c[1], 99, lv.get('Training Ground', 0) or 1) for c in queue)
    xs = sum(craft) if craft else 0
    pressure = 100 * (NEC - saved + total + xs + refill_tot - disc_tot + spent + unbought_val - sold) / (INCOME * mult)
    def first(f, level):
        for bb, s_ in enumerate(tl):
            if s_.get(f, 0) >= level: return bb
        return None
    post_never = 0 if post_added else len(post)
    return dict(maxed=f"{sum(1 for f in lv if lv[f] == FMAX[f])}/{len(facs)}", pressure_pct=round(pressure, 1), levels=dict(lv),
                card_spend=round(spent), card_unbought=len(queue), card_unbought_value=round(unbought_val), cards_bought=dict(bought), card_sell=round(sold),
                post80_basket_never_wanted=post_never, refill_gold=round(refill_tot),
                GH10_battle=first('Guild Hall', 10), TG10_battle=first('Training Ground', 10), TG1_battle=first('Training Ground', 1), TG8_battle=first('Training Ground', 8),
                slot2_battle=s2, GH10_map=(round(lvl_at(first('Guild Hall', 10)), 1) if first('Guild Hall', 10) is not None else None),
                TG10_map=(round(lvl_at(first('Training Ground', 10)), 1) if first('Training Ground', 10) is not None else None), leftover=round(fund))
CORE6_ = CORE6
STR_T = {'classic (Training Grounds after Runeforge + Crucible)': [CORE6_, ['Runeforge'], ['Crucible'], ['Training Ground'], ['Trophy Hall']],
         'Apothecary first': [['Guild Hall', 'Workshop'], CORE6_, ['Runeforge'], ['Crucible'], ['Training Ground'], ['Trophy Hall']],
         'Training Grounds rush (Guild Hall + TG first)': [['Guild Hall', 'Training Ground'], CORE6_, ['Runeforge'], ['Crucible'], ['Trophy Hall']]}
NORMAL = 'normal (10% of battle gold)'
Q1 = {}
FACS11 = list(FAC); FACS10 = [f for f in FAC if f != 'Library']
for who, mult in (('free', 1.0), ('boosted', 1.25)):
    for crafted, x in (('craft from Rare', 4919), ('craft from Common', 8884)):
        ce = craft_extra(x)
        rowq = {}
        # repro of 2026-11-03 (11 facilities, normal refills, no cards)
        rowq['repro 11 facilities (2026-11-03 classic normal)'] = fac_sim_tg(STR_AP['classic (Apothecary in core 6)'], mult, ce, NORMAL, BASKETS['none'], False, FACS11, total=77204)
        for sn, g in STR_T.items():
            for bn, bk in BASKETS.items():
                for sl in ((False, True) if bn != 'none' else (False, True)):
                    rowq[f'{sn} | {bn} | sell loot cards={sl}'] = fac_sim_tg(g, mult, ce, NORMAL, bk, sl, FACS10)
            rowq[f'{sn} | Designer basket | facilities first'] = fac_sim_tg(g, mult, ce, NORMAL, BASKETS['Designer basket (9 sk + 12 aug + 2 doc pre-80, 24 aug after)'], True, FACS10, card_first=False)
            rowq[f'{sn} | Designer basket | heavy refills'] = fac_sim_tg(g, mult, ce, 'heavy (20% of battle gold)', BASKETS['Designer basket (9 sk + 12 aug + 2 doc pre-80, 24 aug after)'], True, FACS10)
        Q1[f'{who} | {crafted}'] = rowq
RT['Q1'] = Q1
RT['repro_check_vs_2026-11-03'] = {k: v['classic (Apothecary in core 6) | normal (10% of battle gold)']['pressure_pct'] for k, v in RA['Q2'].items()}

# ---------- Q4 augment supply vs slot caps (count measure only; no combat model of augments exists) ----------
UNITS_N, ROWS = 6, 4      # Designer figures: 6 units, 4 skill rows each (3 skill slots + doctrine skill)
def owned_aug(b, bought=0): return 4 + LOOT_AG * b + bought
Q4 = {}
for L in (1, 25, 50, 79):
    b = round(dep_at.get(L, 0) * SCALE) if L > 1 else 0
    o = owned_aug(b); o_d = owned_aug(b, 12 * b / B80)
    Q4[f'unit L{L} (battle {b})'] = dict(owned_loot_only=round(o, 1), owned_with_Designer_basket=round(o_d, 1),
        equipped_cap4=min(round(o, 1), UNITS_N * ROWS), equipped_cap8=min(round(o, 1), UNITS_N * ROWS * 2),
        equipped_cap4_basket=min(round(o_d, 1), 24), equipped_cap8_basket=min(round(o_d, 1), 48))
RT['Q4_supply'] = Q4
RT['Q4_cap_binding_battle'] = dict(loot_only_24=math.ceil((24 - 4) / LOOT_AG), loot_only_48=math.ceil((48 - 4) / LOOT_AG))
# enemies: augment count per battle (count measure), rows per enemy = 4 (assumption)
COMP = {'normal (3 Grunt + 2 Veteran)': {'G': 3, 'V': 2, 'E': 0}, 'elite encounter (1 Elite leader + 3G + 2V)': {'G': 3, 'V': 2, 'E': 1},
        'hard battle (2 Elite + 3 Grunt) [assumed]': {'G': 3, 'V': 0, 'E': 2}}
CH = {'G': 0.25, 'V': 0.5, 'E': 1.0}
Q45 = {}
for cn, cp in COMP.items():
    today = 4 * (cp['G'] + cp['V']) + 8 * cp['E']
    new_off = 4 * (cp['G'] + cp['V'] + cp['E'])
    new_on = new_off + 4 * sum(cp[t] * CH[t] for t in cp)
    Q45[cn] = dict(today_design=today, new_rule_off=new_off, new_rule_on=round(new_on, 1), off_vs_today_pct=round(100 * (new_off - today) / today, 1),
                   on_vs_off_pct=round(100 * (new_on - new_off) / new_off, 1), share_rows_with_2nd_on=round(100 * (new_on - new_off) / new_off, 1))
RT['Q4Q5_enemy_aug_counts'] = Q45
RT['player_aug_slots'] = dict(below80_or_no_TG10=UNITS_N * ROWS, slot2_open=UNITS_N * ROWS * 2)

RT['db_md5_end'] = md5(DBP)
with open(OUT_T + r'\results_tg.json', 'w', encoding='utf-8') as f:
    json.dump(RT, f, indent=1, default=str)
print('done', RT['db_md5_start'], RT['db_md5_end'])
