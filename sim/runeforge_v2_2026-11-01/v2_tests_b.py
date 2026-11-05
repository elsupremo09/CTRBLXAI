# Economy tests T7-T9, T11-T14, T18 (+ mercury lever, crystal levers). exec v2_core.py first.
RB = {}
rngb = random.Random(SEED + 7)
D0 = 0.40                # lp24 working estimate (equipment drops / battle)
KILL_EQ = 5 * 0.05       # lp86 Normal 5 enemies x lp13 5% = 0.25 of the 0.40
REST_EQ = D0 - KILL_EQ   # chests / boss / elite / quests (not Fortune-scaled for count)
ELITE, BOSS, CHEST = 0.034, 0.034, 0.2   # lp26 working estimates
SLOTS = list(BASE); TWO_SHARE = 1 / 8

def weights(normF=0.0):
    w = {r: LW_N[r][0] * (1 + normF * SENS[r]) for r in LW_N}
    s = sum(w.values()); return {r: v / s for r, v in w.items()}
MAXT = {'Uncommon': 2, 'Rare': 3, 'Epic': 4, 'Exalted': 4, 'Legendary': 5, 'Mythic': 6}
UNITS = {'Uncommon': 2, 'Rare': 3, 'Epic': 4, 'Exalted': 4, 'Legendary': 5, 'Mythic': 6}
def partitions(n, maxp):
    if n == 0: yield (); return
    for p in range(min(n, maxp), 0, -1):
        for rest in partitions(n - p, p): yield (p,) + rest
def line_tiers(rar, two):
    """uniform over legal tier partitions (assumption, same as runeforge_sim rf_econ): avg count per tier"""
    ps = list(partitions(UNITS[rar] * (2 if two else 1), MAXT[rar]))
    out = {t: 0.0 for t in range(1, 7)}
    for P in ps:
        for p in P: out[p] += 1 / len(ps)
    return out
LT = {r: {t: (1 - TWO_SHARE) * line_tiers(r, False)[t] + TWO_SHARE * line_tiers(r, True)[t] for t in range(1, 7)} for r in MAXT}
LINES = {r: sum(LT[r].values()) for r in LT}
def per_drop(normF=0.0):
    w = weights(normF)
    cry = sum(w[r] * DIS_CRY[r] for r in w); sul = sum(w[r] * DIS_SUL[r] for r in w)
    gems = sum(w[r] * LINES.get(r, 0) for r in w)
    gt = {t: sum(w[r] * LT[r][t] for r in LT) for t in range(1, 7)}
    gt4 = {1: gt[1], 2: gt[2], 3: gt[3], 4: gt[4] + gt[5] + gt[6]}    # Epic cap
    return dict(crystals=cry, sulfur=sul, gems=gems, gem_tiers=gt4, w=w)
PD0 = per_drop(0.0)
RB['per_drop_base'] = {k: (round(v, 4) if isinstance(v, float) else {kk: round(vv, 4) for kk, vv in v.items()}) for k, v in PD0.items()}
RB['lines_per_item'] = {r: round(v, 2) for r, v in LINES.items()}

def lifetime(d=1.0, enemies=5, kill_p=0.10, dispatch=0.6, M=1.0, elite_c=3, boss_c=5, chest_c=0.0, quests=0.3, drops=None):
    """expected lifetime resources (547 battles). M = Fortune multiplier (1..2). Fortune scales normal-kill equipment drops (lp13) only."""
    normF = M - 1
    pd = per_drop(normF)
    tot = dict(merc_kill=0, merc_elite=0, merc_boss=0, merc_chest=0, merc_quest=0, merc_dispatch=0, merc_dismantle=0,
               cry_dismantle=0, cry_elite=0, cry_boss=0, cry_chest=0, gem_dismantle=0, gem_elite=0, gem_boss=0,
               sul_dismantle=0, sul_elite=0, sul_boss=0, drops=0)
    for b in range(N_B):
        L = lvl_at(b)
        dr = (KILL_EQ * min(0.95 / 0.05, M) + REST_EQ) if drops is None else drops
        n = dr * d
        tot['drops'] += dr
        tot['merc_kill'] += enemies * kill_p; tot['merc_elite'] += ELITE * 2; tot['merc_boss'] += BOSS * 3
        tot['merc_chest'] += CHEST * 1; tot['merc_quest'] += quests; tot['merc_dispatch'] += dispatch
        tot['merc_dismantle'] += n * dis_merc(max(1, math.floor(L)))
        tot['cry_dismantle'] += n * pd['crystals']; tot['cry_elite'] += ELITE * elite_c; tot['cry_boss'] += BOSS * boss_c; tot['cry_chest'] += CHEST * chest_c
        tot['gem_dismantle'] += n * pd['gems']; tot['gem_elite'] += ELITE * 0.5; tot['gem_boss'] += BOSS * 1
        tot['sul_dismantle'] += n * pd['sulfur']
        if L >= 60: tot['sul_elite'] += ELITE * 0.25; tot['sul_boss'] += BOSS * 1
    tot['mercury'] = sum(v for k, v in tot.items() if k.startswith('merc_'))
    tot['crystals'] = sum(v for k, v in tot.items() if k.startswith('cry_'))
    tot['gems'] = sum(v for k, v in tot.items() if k.startswith('gem_'))
    tot['sulfur'] = sum(v for k, v in tot.items() if k.startswith('sul_'))
    return {k: round(v, 1) for k, v in tot.items()}

# ---------- T12 mercury ----------
T12 = {}
for nm, kw in {'DB 5 enemies, dismantle 75%': dict(d=0.75), 'DB 5 enemies, dismantle 100%': dict(d=1.0),
               'draft 8 enemies, 75%': dict(d=0.75, enemies=8), 'draft 8 enemies, 100%': dict(d=1.0, enemies=8)}.items():
    lt = lifetime(**kw)
    T12[nm] = dict(mercury=lt['mercury'], full_levellings=round(lt['mercury'] / 98, 1),
                   battle_drops=round(lt['merc_kill'] + lt['merc_elite'] + lt['merc_boss'] + lt['merc_chest'] + lt['merc_quest'], 1),
                   dispatch=lt['merc_dispatch'], dismantle=lt['merc_dismantle'], dismantle_share_pct=round(100 * lt['merc_dismantle'] / lt['mercury'], 1))
# dispatch range: DB unit_progression 99 (one offer per tier, duration = tier days, 3 base slots)
T12['dispatch_range_per_battle'] = dict(draft_guess=0.6, three_slots_tiers_1_2_3=round(1 + 1 / 2 + 1 / 3, 2), three_slots_tiers_3_4_5=round(1 / 3 + 2 / 4 + 2 / 5, 2),
                                        gold_per_mercury_tier1=50, note='offer refresh rate not in DB; missions cost 50g (ef26)')
T12['lifetime_dispatch_range'] = [round(0.3 * N_B), round(1.83 * N_B)]
T12['daily_event_per_10_events'] = dict(mercury=50, sulfur=10)
T12['old_10_item_scenario_mercury'] = dict(estimate=335, range=[305, 447], basis='ms37 670 materials / 1.5-2.2 materials per level')
# lever: kill chance that lands the wall at 15 / 17.5 / 20 (DB 5 enemies, dispatch 0.6, dismantle 75-100%)
lev = {}
for d in (0.75, 1.0):
    base = lifetime(d=d, kill_p=0.0)['mercury']
    for target in (15, 17.5, 20):
        p = (target * 98 - base) / (5 * N_B)
        lev[f'd{d} wall {target}'] = round(p * 100, 1)
T12['kill_chance_pct_for_wall'] = lev
for d in (0.75, 1.0):
    base = lifetime(d=d, kill_p=0.10, dispatch=0.0)['mercury']
    T12[f'dispatch_per_battle_for_wall_17.5_d{d}'] = round((17.5 * 98 - base) / N_B, 2)
T12['PASS'] = 15 <= T12['DB 5 enemies, dismantle 75%']['full_levellings'] <= 20 and 15 <= T12['DB 5 enemies, dismantle 100%']['full_levellings'] <= 20
RB['T12'] = T12

# ---------- T11 crystals ----------
T11 = {}
LT75, LT100 = lifetime(d=0.75), lifetime(d=1.0)
inc = (LT75['crystals'], LT100['crystals'])
T11['income'] = dict(d75=LT75['crystals'], d100=LT100['crystals'], dismantle=(LT75['cry_dismantle'], LT100['cry_dismantle']), elite=LT75['cry_elite'], boss=LT75['cry_boss'])
T11['per_battle'] = (round(inc[0] / N_B, 3), round(inc[1] / N_B, 3))
need_real = (25 * 12 + 20 * 8, 25 * 21 + 20 * 8)
T11['need_realistic'] = need_real
T11['shortfall_realistic'] = [need_real[0] - inc[1], need_real[1] - inc[0]]
natural_epic_plus = round(D0 * N_B * (PD0['w']['Epic'] + PD0['w']['Exalted'] + PD0['w']['Legendary']), 1)
T11['natural_epic_plus_lifetime'] = natural_epic_plus
full = {}
for tgt, per in (('Uncommon', 3), ('Rare', 9), ('Epic', 21)):
    need = 45 * per
    full[tgt] = dict(crystals=need, battles=[round(need / (inc[1] / N_B)), round(need / (inc[0] / N_B))], lifetimes=[round(need / inc[1], 2), round(need / inc[0], 2)])
full['Epic net of 19 natural Epic+'] = dict(crystals=26 * 21, battles=[round(26 * 21 / (inc[1] / N_B)), round(26 * 21 / (inc[0] / N_B))])
T11['full_team_45'] = full
# Epic crafts from income alone (after 20 swaps), and with shop dismantling
crafts = {}
for nm, c in (('d75', inc[0]), ('d100', inc[1])):
    left = c - 160
    crafts[nm] = dict(after_20_swaps_from_Rare=round(left / 12, 1), after_20_swaps_from_Common=round(left / 21, 1), no_swaps_from_Rare=round(c / 12, 1), no_swaps_from_Common=round(c / 21, 1))
T11['epic_crafts_income_only'] = crafts
# gold per crystal from the shop (Merchant L10; Rare is the cheapest per crystal: 5 x slot x LM)
gpc = {}
for L in (10, 30, 50, 70, 99):
    opts = {f'{s} {r}': shop(s, r, L) / DIS_CRY[r] for s in SLOTS for r in ('Uncommon', 'Rare', 'Epic', 'Exalted')}
    best = min(opts, key=opts.get)
    avg_rare = sum(shop(s, 'Rare', L) for s in SLOTS) / len(SLOTS) / 2
    gpc[f'L{L}'] = dict(cheapest=best, g_per_crystal=round(opts[best]), avg_slot_rare_g_per_crystal=round(avg_rare))
T11['shop_gold_per_crystal'] = gpc
# shelf capacity: Merchant L10 = 10 slots x 40% Rare per refresh (every 5 battles)
T11['shop_supply_crystals_per_battle_max'] = dict(rare_only=round(10 * 0.40 * 2 / 5, 2), rare_gloves_feet_only=round(10 * 0.40 * 2 * 2 / 8 / 5, 2))
def gold_cover(cry):
    # buy cheapest first along the timeline: Gloves/Feet Rare then other slots, at the level when bought (spread over L50-99)
    lv = [50 + i * 49 / 99 for i in range(100)]
    g_lo = sum(5 * 50 * float(lvl_mult(round(l))) for l in lv) / len(lv)
    g_avg = sum(5 * (sum(BASE.values()) / 8) * float(lvl_mult(round(l))) for l in lv) / len(lv)
    return [round(cry * g_lo), round(cry * g_avg)]
T11['gold_to_cover_shortfall'] = {f'{x} crystals': gold_cover(x) for x in (T11['shortfall_realistic'][0], T11['shortfall_realistic'][1], 945 - inc[0])}
# levers
B_EB = round(N_B * (ELITE + BOSS), 1)
lev = {}
for nm, gap in (('realistic low gap', T11['shortfall_realistic'][0]), ('realistic high gap', T11['shortfall_realistic'][1]), ('mid gap', (T11['shortfall_realistic'][0] + T11['shortfall_realistic'][1]) / 2)):
    k = 1 + gap / (N_B * (ELITE * 3 + BOSS * 5))
    lev[nm] = dict(gap=round(gap), elite_boss_multiplier=round(k, 2), elite=round(3 * k, 1), boss=round(5 * k, 1),
                   chest_crystals_per_chest_at_100pct=round(gap / (N_B * CHEST), 2))
lev['chest 25% -> 1 (draft optional lever)'] = round(N_B * CHEST * 0.25)
lev['chest 100% -> 1'] = round(N_B * CHEST)
def need_with(steps, keep):
    up = steps[0] + steps[1] + steps[2]; rare_up = steps[2]
    return (25 * rare_up + 20 * keep[2], 25 * up + 20 * keep[2])
lev['step cost options (need for 25 Epics + 20 swaps)'] = {
    'draft 3/6/12 keep 2/4/8': need_with((3, 6, 12), (2, 4, 8)),
    '2/4/8 keep 1/2/4': need_with((2, 4, 8), (1, 2, 4)),
    '2/3/6 keep 1/2/4': need_with((2, 3, 6), (1, 2, 4)),
    '1/2/4 keep 1/1/2': need_with((1, 2, 4), (1, 1, 2)),
    'charge highest step once (old): 3/6/12 -> max 12, keep 8': (25 * 12 + 160, 25 * 12 + 160)}
lev['income_range'] = inc
T11['levers'] = lev
RB['T11'] = T11

# ---------- gem coverage (T11 second part) - Monte Carlo, fixed seed ----------
def gem_coverage(trials=300):
    pd = PD0; lt = LT100
    tiers = pd['gem_tiers']; s = sum(tiers.values())
    num_fams = 25; pas_kinds = 53; PASSIVE_SHARE = 0.10   # assumption: 10% of gem lines are bonus passives
    kinds = [(f, t) for f in range(num_fams) for t in (1, 2, 3, 4)] + [('P', p) for p in range(pas_kinds)]
    wts = [(1 - PASSIVE_SHARE) * tiers[t] / s / num_fams for f in range(num_fams) for t in (1, 2, 3, 4)] + [PASSIVE_SHARE / pas_kinds] * pas_kinds
    strong = [i for i, k in enumerate(kinds) if k[0] == 'P' or k[1] >= 3]
    sw = [wts[i] for i in strong]
    out = []
    for tr in range(trials):
        r = random.Random(SEED + 1000 + tr)
        n = int(round(lt['gems']))
        got = {}
        for i in r.choices(range(len(kinds)), weights=wts, k=n): got[i] = got.get(i, 0) + 1
        target = r.choices(strong, weights=sw, k=45)
        need = {}
        for i in target: need[i] = need.get(i, 0) + 1
        out.append(sum(min(c, got.get(i, 0)) for i, c in need.items()) / 45)
    out.sort()
    return dict(gems_lifetime=lt['gems'], median=round(out[len(out) // 2] * 100, 1), p10=round(out[len(out) // 10] * 100, 1), p90=round(out[9 * len(out) // 10] * 100, 1),
                assumption='target = 45 gems drawn from T3/T4 numeric + passive kinds by their own drop weights; families uniform; 10% of lines are passives')
RB['T11_gem_coverage'] = gem_coverage()

# ---------- T13 sulfur ----------
T13 = {}
for d in (0.75, 1.0):
    lt = lifetime(d=d)
    T13[f'd{d}'] = dict(total=lt['sulfur'], dismantle=lt['sul_dismantle'], elite=lt['sul_elite'], boss=lt['sul_boss'])
s_lo = T13['d0.75']['total']; s_hi = T13['d1.0']['total']
T13['rerolls_if_all_spent_on'] = {r: [round(s_lo / c, 1), round(s_hi / c, 1)] for r, c in (('Exalted', 1), ('Legendary', 2), ('Mythic', 3), ('Transcendent', 4))}
T13['natural_items_lifetime'] = {r: round(D0 * N_B * PD0['w'][r], 1) for r in ('Exalted', 'Legendary', 'Mythic')}
T13['sets_offered'] = 'Exalted/Legendary 2/3/4 at RF L8/9/10; Mythic 2/3 at L9/10; Transcendent 2 at L10 only'
T13['daily_event_note'] = '+1 sulfur per daily event: 30 events = +30 (about 2x all loot sulfur)'
RB['T13'] = T13

# ---------- T7 Black Market ----------
T7 = {}
gem_rare = LINES['Rare']
for L in (20, 50, 80, 99):
    free = dict(crystals=12, gems=round(6 * gem_rare, 1), mercury=6 * dis_merc(L), sell_value_6_rare_1H=6 * sell('1H', 'Rare', L))
    avg_price = sum(shop(s, 'Rare', L) for s in SLOTS) / 8
    paid75 = dict(gold_for_6=round(6 * 0.75 * avg_price), g_per_crystal=round(0.75 * avg_price / 2), merchant_avg_g_per_crystal=round(avg_price / 2),
                  merchant_cheapest_g_per_crystal=round(min(shop(s, r, L) / DIS_CRY[r] for s in SLOTS for r in ('Uncommon', 'Rare', 'Epic'))))
    T7[f'L{L}'] = dict(free=free, paid75=paid75)
for p in (0.01, 0.03, 0.05):
    n = p * N_B
    T7[f'spawn {int(p*100)}%/battle'] = dict(objects=round(n, 1), free_crystals=round(12 * n), free_gems=round(6 * gem_rare * n), free_mercury=round(sum(6 * dis_merc(max(1, math.floor(lvl_at(b)))) * p for b in range(N_B))),
                                            free_share_of_crystal_income_pct=[round(100 * 12 * n / inc[1], 1), round(100 * 12 * n / inc[0], 1)],
                                            per_object_share_pct=[round(100 * 12 / inc[1], 1), round(100 * 12 / inc[0], 1)])
T7['spawn_assumption'] = 'NOT IN DB: Black Market only in 4 region lists (Village 3, Castle Courtyard 1, Dock 2, Town 3) + Castle biome 2; per-battle rate assumed 1-5% (centre 3%)'
RB['T7'] = T7

# ---------- T8 recruit ----------
T8 = {}
worst = None
for L in range(1, 100):
    for q, prem in (('Standard', 0), ('Quality', 300), ('Elite', 800)):
        fee = 200 + L * 15 + prem
        per = fee / dis_merc(L)
        shopb = min(shop(s, 'Common', L) for s in SLOTS) / dis_merc(L)
        if worst is None or per / shopb < worst[0]: worst = (per / shopb, L, q, round(per), round(shopb))
T8['L50 Standard'] = dict(fee=950, mercury=5, g_per_mercury=190, shop_gloves_common_g_per_mercury=round(shop('Gloves', 'Common', 50) / 5))
T8['closest_case'] = dict(ratio_recruit_over_shop=round(worst[0], 2), level=worst[1], quality=worst[2], recruit_g_per_m=worst[3], shop_g_per_m=worst[4])
T8['PASS'] = worst[0] > 1
RB['T8'] = T8
