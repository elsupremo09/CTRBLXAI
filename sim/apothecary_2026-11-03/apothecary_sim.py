# CTRBLXAI Apothecary (paid refills) economy check - 2026-11-03. DB read-only. Deterministic (no RNG used; seed stated 20261103).
# Reuses sim\crucible_2026-11-02\crucible_sim.py prefix (v2_core economy timeline, 11-facility purchase logic, DB prov() asserts).
# Apothecary rules: user decision 2026-11-03 + design doc apothecary_design_options_20261103.md (NOT in the DB yet).
import math, json, time, sqlite3, re, collections, hashlib
OUT_A = r'D:\AI\Projects\CTRBLXAI\sim\apothecary_2026-11-03'
CRU = r'D:\AI\Projects\CTRBLXAI\sim\crucible_2026-11-02\crucible_sim.py'
src = open(CRU, encoding='utf-8').read()
exec(src[:src.find('# ---------- loot model')])       # retries on DB lock are inside the prefix
SEED_A = 20261103
RA = dict(seed=SEED_A, db_md5_start=MD5_START)

# ---------- DB rows used today ----------
prov('Consumable pricing', 'consumable_framework', 30, ['round(Base Profile Price × Tier Multiplier / 5) × 5'])
prov('Profile base', 'consumable_framework', 31, ['Quick = 25g', 'Routine = 50g', 'Standard = 75g', 'Heavy = 110g', 'Battlefield = 160g'])
prov('Tier mult', 'consumable_framework', 32, ['Common = ×1.0', 'Uncommon = ×1.4', 'Rare = ×2.0', 'Epic = ×3.0'])
prov('Restock frequency', 'consumable_framework', 36, ['A Routine item (4 charges) lasts ~4 encounters', 'intermittent'])
prov('Consumable sell (old)', 'consumable_framework', 37, ['cannot be sold'])
prov('Consumable share', 'consumable_framework', 38, ['~10% of lifetime income'])
prov('Consumable direction', 'economy_framework', 27, ['~10% of lifetime income'])
prov('Lifetime income', 'economy_framework', 42, ['~165,000g', '~10,800g', '~175,800g'])
prov('Necessities', 'economy_framework', 43, ['~127,800g', 'consumables (~17,500g)'])
prov('Basics principle', 'economy_framework', 1, ['Basics always affordable'])
prov('Workshop curve', 'guild_facilities', 18, ['Base = 150, Scale = 22', '4,123g', 'Guild Hall L4'])
prov('Workshop table', 'guild_facilities', 31, ['L1:157 L2:177 L3:211 L4:259 L5:320 L6:395 L7:484 L8:586 L9:702 L10:832'])
prov('Base processing', 'game_flow', 20, ['refill item charges'])
prov('Post-battle recovery', 'persistent_hp_mp_rules', 3, ['ceil(Max HP × 0.35)'])
prov('Stalling allowed', 'persistent_hp_mp_rules', 15, ['Deliberate stalling is allowed'])
prov('MP regen', 'persistent_hp_mp_rules', 11, ['2 + floor(INT / 40)'])
assert FAC['Workshop'] == [157, 177, 211, 259, 320, 395, 484, 586, 702, 832]

PROF_BASE = {'Quick': 25, 'Routine': 50, 'Standard': 75, 'Heavy': 110, 'Battlefield': 160}
TIER_M = {'Common': 1.0, 'Uncommon': 1.4, 'Rare': 2.0, 'Epic': 3.0}
items = []
for iid, cat, prof, tier, mc, eco, st in con.execute('select Item_ID,Category,Profile,Tier,Max_Charges,Economy,Status from consumable_items'):
    p = int(re.search(r'(\d+)g', eco).group(1))
    assert p == round(PROF_BASE[prof] * TIER_M[tier] / 5) * 5, iid
    items.append(dict(id=iid, cat=cat, prof=prof, tier=tier, mc=mc, price=p, parked='PARKED' in (st or '')))
RA['catalog'] = dict(n=len(items), tiers=collections.Counter(i['tier'] for i in items), charges=collections.Counter(i['mc'] for i in items),
                     cats=collections.Counter(i['cat'] for i in items), parked=sum(i['parked'] for i in items),
                     price_mismatch=0, avg_price=round(sum(i['price'] for i in items) / len(items), 1),
                     avg_per_charge=round(sum(i['price'] / i['mc'] for i in items) / len(items), 1))

# ---------- Apothecary rules (user 2026-11-03) ----------
RATE = {0: 0.75, 1: 0.75, 2: 0.69, 3: 0.64, 4: 0.58, 5: 0.53, 6: 0.47, 7: 0.42, 8: 0.36, 9: 0.31, 10: 0.25}
assert all(RATE[l] == round(75 - 50 * (l - 1) / 9) / 100 for l in range(1, 11))
def buy_disc(l): return 0.03 * (l - 1) if l >= 1 else 0.0
def refill_cost(price, missing, mx, l): return math.ceil(price * missing / mx * RATE[l])
def buy_price(price, l, rnd='round'): return (round if rnd == 'round' else math.floor)(price * (1 - buy_disc(l)))
def sell_price(price, left, mx): return math.floor(price * 0.20 * left / mx)
def l9_max(mc): return math.floor(mc * 1.25)

BG_SHARE = 165000 / 175800                      # battle gold share of INC (ef42: battle 165,000 + sell 10,800)
BG = [x * BG_SHARE for x in INC]
CONS_BUY = 17500                                 # ef43, buying line already inside NEC
CB = [CONS_BUY * x / sum(INC) for x in INC]       # same shape as OTHER (assumption, as before)
RA['battle_gold'] = {f'L{L}': round(BG[min(N_B - 1, round((L - 1) * N_B / 98))]) for L in (1, 25, 50, 75, 99)}
RA['battle_gold']['avg'] = round(sum(BG) / N_B)

# usage profiles: list-price value of charges used per battle (assumption anchored on cf38/ef27 ~10%)
PROFILES = {
    'light (5% of battle gold)': ('share', 0.05),
    'normal (10% of battle gold)': ('share', 0.10),
    'heavy (20% of battle gold)': ('share', 0.20),
    'flat normal (30g list/battle)': ('flat', 30.0),
    'flat heavy (60g list/battle)': ('flat', 60.0),
    'design-doc squad (87.5g list/battle)': ('flat', 87.5),
}
def used_value(prof, b):
    k, v = PROFILES[prof]; return v * BG[b] if k == 'share' else v

# ---------- Q1 per-battle table ----------
Q1 = {}
for prof in PROFILES:
    rowq = {}
    for l in (0, 1, 5, 10):
        avg_g = sum(used_value(prof, b) * RATE[l] for b in range(N_B)) / N_B
        rowq[f'L{l}'] = dict(gold_avg=round(avg_g, 1), pct_avg=round(100 * avg_g / (sum(BG) / N_B), 1),
                             by_level={f'map{L}': dict(g=round(used_value(prof, bb) * RATE[l], 1), pct=round(100 * used_value(prof, bb) * RATE[l] / BG[bb], 1))
                                       for L in (1, 25, 50, 99) for bb in [min(N_B - 1, round((L - 1) * N_B / 98))]})
    Q1[prof] = rowq
RA['Q1'] = Q1
# what the normal profile means in charges (examples, list price per charge)
RA['charge_examples_normal_avg'] = {n: round(30 / pc, 2) for n, pc in
    {'Common Routine 4ch (12.5g/ch)': 12.5, 'Common Standard 3ch (25g/ch)': 25, 'Rare Standard 3ch (50g/ch)': 50, 'Rare Heavy 2ch (110g/ch)': 110}.items()}

# ---------- Q2 facility timeline with refills ----------
def fac_sim_ap(groups, mult, craft, prof, refills=True, disc=True):
    facs = list(FAC); FMAX = {k: len(FAC[k]) for k in facs}
    lv = {k: 0 for k in facs}; fund = 500.0; saved = 0.0; tl = []; refill_tot = 0.0; disc_tot = 0.0
    cash = 500.0; cash_min = 500.0; cash_min_b = 0
    def can(f):
        if lv[f] >= FMAX[f]: return False
        if f == 'Guild Hall': return True
        return lv['Guild Hall'] >= max(UNLOCK_GH[f], lv[f] + 1)
    for b in range(N_B):
        L = lvl_at(b)
        d = (3 * (lv['Blacksmith'] - 1)) / 100 if lv['Blacksmith'] >= 1 else 0.0
        saved += BSP[b] * d
        rf = used_value(prof, b) * RATE[lv['Workshop']] * mult_use if refills else 0.0
        dsc = CB[b] * buy_disc(lv['Workshop']) if disc else 0.0
        refill_tot += rf; disc_tot += dsc
        flow = INC[b] * mult - OTHER[b] - BSP[b] * (1 - d) - (craft[b] if craft else 0) - rf + dsc
        fund += flow
        cash += INC[b] * mult - OTHER[b] - BSP[b] * (1 - d) - rf + dsc     # necessities + refills only, no facilities, no crafting
        if cash < cash_min: cash_min, cash_min_b = cash, b
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
    xs = sum(craft) if craft else 0
    pressure = 100 * (NEC - saved + 77204 + xs + refill_tot - disc_tot) / (INCOME * mult)
    nec_only = 100 * (NEC - saved + refill_tot - disc_tot) / (INCOME * mult)
    def first(level):
        for bb, s_ in enumerate(tl):
            if s_['Workshop'] >= level: return round(lvl_at(bb), 1)
        return None
    core_maxed = sum(1 for f in CORE6 if lv[f] == FMAX[f])
    return dict(maxed=f"{sum(1 for f in lv if lv[f] == FMAX[f])}/{len(facs)}", core6_maxed=f'{core_maxed}/6', pressure_pct=round(pressure, 1),
                necessities_plus_refills_pct=round(nec_only, 1), refill_gold=round(refill_tot), refill_pct=round(100 * refill_tot / (INCOME * mult), 1),
                buy_discount_saved=round(disc_tot), apoth_L1_map=first(1), apoth_L5_map=first(5), apoth_L10_map=first(10),
                apoth_final=lv['Workshop'], levels=dict(lv), cash_min=round(cash_min), cash_min_map=round(lvl_at(cash_min_b), 1))
mult_use = 1.0
STR_AP = {'classic (Apothecary in core 6)': STRATS['classic (Crucible after Runeforge)'],
          'Apothecary first after Guild Hall': [['Guild Hall', 'Workshop'], CORE6, ['Runeforge'], ['Crucible'], ['Training Ground'], ['Library'], ['Trophy Hall']]}
Q2 = {}
for who, mult in (('free', 1.0), ('boosted', 1.25)):
    for crafted, x in (('craft from Rare', 4919), ('craft from Common', 8884)):
        ce = craft_extra(x)
        base = fac_sim_ap(STR_AP['classic (Apothecary in core 6)'], mult, ce, 'normal (10% of battle gold)', refills=False, disc=False)
        rowq = {'repro 2026-11-02 (Workshop, free refills)': base,
                'free refills + 3%/level buy discount only': fac_sim_ap(STR_AP['classic (Apothecary in core 6)'], mult, ce, 'normal (10% of battle gold)', refills=False)}
        for sn, g in STR_AP.items():
            for prof in ('light (5% of battle gold)', 'normal (10% of battle gold)', 'heavy (20% of battle gold)', 'flat normal (30g list/battle)', 'flat heavy (60g list/battle)', 'design-doc squad (87.5g list/battle)'):
                rowq[f'{sn} | {prof}'] = fac_sim_ap(g, mult, ce, prof)
        Q2[f'{who} | {crafted}'] = rowq
RA['Q2'] = Q2
# boosted players: gold boost raises battle gold, consumable usage does not scale with gold (assumption) ->
# 'share' profiles for boosted are defined on UNBOOSTED battle gold (used_value uses BG, not mult). Correct as coded.

# ---------- payback per level (normal profile, average battle) ----------
avg_used = sum(used_value('normal (10% of battle gold)', b) for b in range(N_B)) / N_B
avg_cb = CONS_BUY / N_B
PB = {}
for l in range(1, 11):
    save_pb = avg_used * (RATE[l - 1] - RATE[l]) + avg_cb * (buy_disc(l) - buy_disc(l - 1))
    PB[f'L{l}'] = dict(cost=FAC['Workshop'][l - 1], save_per_battle=round(save_pb, 2), payback_battles=(round(FAC['Workshop'][l - 1] / save_pb) if save_pb > 0 else None))
RA['payback_normal'] = PB
for prof in ('light (5% of battle gold)', 'heavy (20% of battle gold)'):
    au = sum(used_value(prof, b) for b in range(N_B)) / N_B
    tot_save = au * (RATE[0] - RATE[10]) + avg_cb * buy_disc(10)
    RA[f'payback_full_L10_{prof}'] = round(4123 / tot_save)
RA['payback_full_L10_normal'] = round(4123 / (avg_used * 0.5 + avg_cb * 0.27))

# ---------- Q3 loop search: every item x level x charges ----------
loops = collections.Counter(); worst = {}
def note(k, g, ctx):
    if k not in worst or g > worst[k][0]: worst[k] = (g, ctx)
for it in items:
    p = it['price']; mc0 = it['mc']
    for l in range(0, 11):
        for l9 in ((False, True) if l >= 9 else (False,)):
            mxs = [mc0] if not l9 else [l9_max(mc0)]
            for mx in mxs:
                for rnd in ('round', 'floor'):
                    if l >= 1:
                        bp = buy_price(p, l, rnd)
                        note('buy -> sell full', sell_price(p, mx, mx) - bp, (it['id'], l, mx, rnd))
                        for u in range(1, mx + 1):
                            note('buy -> use u -> refill -> sell', sell_price(p, mx, mx) - bp - refill_cost(p, u, mx, l), (it['id'], l, mx, u))
                            # replace instead of refill: sell partly used + buy new, vs refill
                            note('sell-used+buy-new minus refill (gain if >0)', refill_cost(p, u, mx, l) - (bp - sell_price(p, mx - u, mx)), (it['id'], l, mx, u))
                for u in range(1, mx + 1):
                    note('refill u -> sell (owned empty item)', sell_price(p, mx, mx) - sell_price(p, mx - u, mx) - refill_cost(p, u, mx, l), (it['id'], l, mx, u))
                    # per-charge refill (one at a time, gold-short rule) vs batch
                    note('one-at-a-time refill saving vs batch', refill_cost(p, u, mx, l) - sum(refill_cost(p, 1, mx, l) for _ in range(u)), (it['id'], l, mx, u))
            if l9:
                # variant: refill divides by BASE max (extra charge paid on top) and sell uses BASE max (capped at 1.0 of value? no cap)
                mx = l9_max(mc0)
                if mx > mc0:
                    note('L9 variant: sell uses base max (uncapped)', math.floor(p * 0.2 * mx / mc0) - refill_cost(p, mx, mx, l), (it['id'], l, mx))
                    note('L9 variant: refill by base max, sell by new max', sell_price(p, mx, mx) - math.ceil(p * mx / mc0 * RATE[l]), (it['id'], l, mx))
RA['Q3_loops'] = {k: dict(max_gain=v[0], at=v[1]) for k, v in worst.items()}
# L9 effective per-charge refill change (4- and 5-charge items)
RA['L9_per_charge'] = {f'{mc}->{l9_max(mc)} ch': dict(L8_rate_per_charge_pct_list=round(100 * RATE[8] / mc, 2), L9_new_max=round(100 * RATE[9] / l9_max(mc), 2),
                       L9_if_base_max=round(100 * RATE[9] / mc, 2), L10_new_max=round(100 * RATE[10] / l9_max(mc), 2)) for mc in (4, 5)}
# AC-009 battle-only charges (free to refill): gold avoided per battle if each equipped item uses <=1 charge
ex = {'Common Routine 4ch 50g': (50, 4), 'Common Standard 3ch 75g': (75, 3), 'Rare Standard 3ch 150g': (150, 3), 'Rare Heavy 2ch 220g': (220, 2)}
RA['AC009_free_charge_value'] = {n: {f'L{l}': round(p / mc * RATE[l], 1) for l in (0, 5, 10)} for n, (p, mc) in ex.items()}
# Restock skill (skills 109): MP cost round(3 + 0.08 x (L-1)), +1 charge to each equipped item
RA['restock_mp_cost'] = {f'L{L}': round(3 + 0.08 * (L - 1)) for L in (1, 25, 50, 99)}
RA['restock_gold_saved_3_common_standard'] = {f'L{l}': round(3 * 25 * RATE[l], 1) for l in (0, 5, 10)}

RA['db_md5_end'] = md5(DBP)
with open(OUT_A + r'\results_apothecary.json', 'w', encoding='utf-8') as f:
    json.dump(RA, f, indent=1, default=str)
print(json.dumps(RA, default=str)[:200])
print('done', RA['db_md5_start'], RA['db_md5_end'])
