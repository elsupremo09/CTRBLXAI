# T9, T14 (facility economy), T18 (Fortune), T15 (save), T16, T17, T20.  exec v2_core.py + v2_tests_b.py first.
RC = {}
prov('Lux / free benchmark', 'economy_framework', 45, ['Maxes 6/9 facilities'])
BS_TOT = BS_SHARE * INCOME; OTHER_TOT = NEC - BS_TOT
def bs_profile():
    s = sum(INC); return [BS_TOT * x / s for x in INC]
OTHER = [OTHER_TOT * x / INCOME for x in INC]
FMAX = {k: len(v) for k, v in FAC.items()}
CORE6 = ['Guild Hall', 'Tavern', 'Blacksmith', 'Merchant', 'Quest Board', 'Workshop']
STRATS = {
    'classic': [CORE6, ['Runeforge'], ['Training Ground'], ['Library'], ['Trophy Hall']],
    'crafter': [CORE6 + ['Runeforge'], ['Training Ground'], ['Library'], ['Trophy Hall']],
    'rusher': [['Guild Hall', 'Runeforge'], CORE6, ['Training Ground'], ['Library'], ['Trophy Hall']],
}
def fac_sim(groups, mult=1.0, extra=None):
    """same purchase logic as runeforge_sim rf_econ.fac_sim (Blacksmith discount on); extra = per-battle extra spend list"""
    lv = {k: 0 for k in FAC}
    fund = 500.0; saved = 0.0; ev = {}; bsp = bs_profile(); spent = 0
    def can(f):
        if lv[f] >= FMAX[f]: return False
        if f == 'Guild Hall': return True
        return lv['Guild Hall'] >= max(UNLOCK_GH[f], lv[f] + 1)
    for b in range(N_B):
        L = lvl_at(b)
        d = (3 * (lv['Blacksmith'] - 1)) / 100 if lv['Blacksmith'] >= 1 else 0.0
        bs_cost = bsp[b] * (1 - d); saved += bsp[b] * d
        fund += INC[b] * mult - OTHER[b] - bs_cost - (extra[b] if extra else 0)
        while True:
            req = min(10, max(1, math.ceil(math.floor(L) / 10)))
            pick = None
            if lv['Blacksmith'] < req:
                pick = 'Blacksmith' if can('Blacksmith') else 'Guild Hall'
            else:
                for grp in groups:
                    if any(lv[f] < FMAX[f] for f in grp):
                        cands = [f for f in grp if can(f)]
                        blocked = [f for f in grp if lv[f] < FMAX[f] and not can(f)]
                        if blocked and can('Guild Hall') and 'Guild Hall' not in cands: cands.append('Guild Hall')
                        if cands: pick = min(cands, key=lambda f: FAC[f][lv[f]])
                        break
            if pick is None or FAC[pick][lv[pick]] > fund: break
            fund -= FAC[pick][lv[pick]]; spent += FAC[pick][lv[pick]]; lv[pick] += 1
            ev.setdefault(pick, {})[lv[pick]] = round(lvl_at(b), 1)
    inc = INCOME * mult
    xs = sum(extra) if extra else 0
    return dict(levels=lv, maxed=sum(1 for f in lv if lv[f] == FMAX[f]), leftover=round(fund), discount_saved=round(saved),
                spending_pressure_pct=round(100 * (NEC - saved + 70927 + xs) / inc, 1), rf7_at_level=ev.get('Runeforge', {}).get(7), rf10_at_level=ev.get('Runeforge', {}).get(10),
                gh7_at_level=ev.get('Guild Hall', {}).get(7))
# crafting gold scenarios (spread over L40-99 battles)
AVG_SLOT = sum(BASE.values()) / 8
def craft_extra(total):
    idx = [b for b in range(N_B) if lvl_at(b) >= 40]
    return [total / len(idx) if b in idx else 0 for b in range(N_B)]
fee_epic = AVG_SLOT * 4 * 0.82        # RF L7 discount 18%
SCEN = {
    'no crafting': 0,
    'realistic: 25 Epic forges + 20 Epic-keep swaps (fees only)': 45 * fee_epic,
    '+ Epic step fee ON (avg 850g x 25)': 45 * fee_epic + 25 * 850,
    '+ crafted Epics levelled 20 levels at Epic instead of Uncommon price (upper sensitivity)': 45 * fee_epic + 25 * 20 * AVG_SLOT * (4.0 - 1.5) * 0.30 * (1 + 65 / 25) * 0.79,
}
T14 = {}
for nm, x in SCEN.items():
    for who, mult in (('free', 1.0), ('boosted', 1.25)):
        r = {s: fac_sim(g, mult, craft_extra(x) if x else None) for s, g in STRATS.items()}
        T14[f'{who} | {nm}'] = dict(extra_gold=round(x), maxed={s: f"{v['maxed']}/10" for s, v in r.items()},
                                    spending_pressure_pct={s: v['spending_pressure_pct'] for s, v in r.items()},
                                    rf7_at={s: v['rf7_at_level'] for s, v in r.items()}, rf10_at={s: v['rf10_at_level'] for s, v in r.items()})
T14['expected'] = 'free ~106% (+-2), 8/10; boosted ~83-84%'
T14['shop_dismantle_to_close_realistic_gap_pp'] = [round(100 * g / INCOME, 1) for g in RB['T11']['gold_to_cover_shortfall'][list(RB['T11']['gold_to_cover_shortfall'])[0]]]
RC['T14'] = T14

# ---------- T9 crafted Epic supply L50-80 ----------
T9 = {}
def crafted_epics(d, rf7_level, shop_gold=0):
    # saver: keeps every crystal from battle 0 until L80, crafts Epics only between max(50, RF7) and 80, best bases first
    cry = sum((D0 * d * PD0['crystals'] + ELITE * 3 + BOSS * 5) for b in range(N_B) if lvl_at(b) < 80)
    start = max(50, rf7_level or 99)
    if start >= 80: return 0, round(cry)
    win = [b for b in range(N_B) if start <= lvl_at(b) < 80]
    rare = D0 * PD0['w']['Rare'] * len(win); unc = D0 * PD0['w']['Uncommon'] * len(win)
    cry += shop_gold / 600
    n = 0
    k = min(rare, cry / 12); n += k; cry -= 12 * k
    k = min(unc, cry / 18); n += k; cry -= 18 * k
    n += cry / 21
    return round(n, 1), None
for who, mult in (('free', 1.0), ('boosted', 1.25)):
    for s, g in STRATS.items():
        r = fac_sim(g, mult)
        lo = crafted_epics(0.75, r['rf7_at_level'])[0]; hi = crafted_epics(1.0, r['rf7_at_level'])[0]
        row_ = dict(rf7_at_level=r['rf7_at_level'], crafted_epics_L50_80_saver=[lo, hi])
        if who == 'boosted':
            row_['with_shop_dismantle_of_leftover_gold'] = crafted_epics(1.0, r['rf7_at_level'], shop_gold=max(0, r['leftover']))[0]
        T9[f'{who} {s}'] = row_
T9['natural_epic_plus_L50_80'] = round(D0 * (PD0['w']['Epic'] + PD0['w']['Exalted'] + PD0['w']['Legendary']) * sum(1 for b in range(N_B) if 50 <= lvl_at(b) < 80), 1)
T9['gold_per_crafted_epic_1H_fresh_drop'] = dict(forge_fee_RF7=forge_fee('1H', 'Epic', 7), catch_up=0, epic_step_fee_if_on=dict(Rare=epic_step_fee('1H', 'Rare'), Uncommon=epic_step_fee('1H', 'Uncommon'), Common=epic_step_fee('1H', 'Common')),
                                               shop_epic_L50=shop('1H', 'Epic', 50), shop_epic_L80=shop('1H', 'Epic', 80))
T9['note'] = 'v2 crafted Epics are crystal-limited, not gold-limited: a fresh drop has credit 0, so catch-up = 0; gold = forge fee only'
RC['T9'] = T9

# ---------- T18 Fortune ----------
T18 = {}
def team_norm(unit_fortunes):
    u = sorted(unit_fortunes, reverse=True) + [0, 0, 0]
    return min(1.0, (u[0] + 0.5 * u[1] + 0.25 * u[2]) / 1.75)
for nm, M in (('normal team (LUK ~30 at L99, no Fortune lines)', 1 + team_norm([30 / 230] * 3)), ('Fortune cap', 2.0)):
    lt = lifetime(d=0.9, M=M)
    pd = per_drop(M - 1)
    T18[nm] = dict(multiplier=round(M, 3), drops_lifetime=lt['drops'], crystals=lt['crystals'], gems=lt['gems'], sulfur=lt['sulfur'], mercury=lt['mercury'],
                   epic_plus_share_pct=round(100 * (pd['w']['Epic'] + pd['w']['Exalted'] + pd['w']['Legendary']), 2),
                   battle_gold_mult=round(1 + 0.5 * (M - 1), 3))
base = lifetime(d=0.9, M=1.0)
cap = lifetime(d=0.9, M=2.0)
T18['cap_vs_zero_fortune'] = {k: round(cap[k] / base[k], 2) for k in ('drops', 'crystals', 'gems', 'sulfur', 'mercury')}
T18['direct_drop_chances_identical'] = dict(elite_crystals=cap['cry_elite'] == base['cry_elite'], boss_crystals=cap['cry_boss'] == base['cry_boss'], kill_mercury=cap['merc_kill'] == base['merc_kill'],
                                            note='true for direct resource drops; dismantle income rises because lp13 Fortune raises ordinary equipment drop chance (x2 at cap) and lp16 raises rarity')
# reaching the cap with Fortune lines (interpretation A: +5/10/15/20 percentage points added to Unit Fortune)
need_per_unit = {L: round(1 - L / (L + 200), 3) for L in (10, 30, 60, 100)}
T18['Fortune_points_needed_per_unit_for_cap (A: additive points)'] = need_per_unit
T18['max_Fortune_from_gear_per_unit'] = dict(items=7, T4_each=0.20, total=1.40, note='one line per family per item')
# Fortune gem/line supply: share of numeric lines that are Fortune (1 of ~22 eligible numeric families, uniform assumption)
fort_share = 1 / 22
gl = cap['gem_dismantle'] + cap['gem_elite'] + cap['gem_boss']
gb = base['gem_dismantle'] + base['gem_elite'] + base['gem_boss']
avg_pts = sum(PD0['gem_tiers'][t] * 0.05 * t for t in (1, 2, 3, 4)) / sum(PD0['gem_tiers'].values())
T18['fortune_gems_lifetime'] = dict(base_team=round(gb * fort_share * 0.9, 1), capped_team=round(gl * fort_share * 0.9, 1), avg_points_per_gem=round(avg_pts, 3),
                                    lifetime_points_base=round(gb * fort_share * 0.9 * avg_pts, 2))
# feedback loop (expected values, A interpretation): install every Fortune gem on the top-3 units
def loop(shop_per_battle=0.0, interp='A'):
    pts = [0.0, 0.0, 0.0]; hist = []; reached = None
    for b in range(N_B):
        L = lvl_at(b); luk = 1 + 0.3 * (L - 1)
        uf = [min(1.0, luk / (luk + 200) + p) if interp == 'A' else luk / (luk + 200) * (1 + p) for p in pts]
        nF = team_norm(uf); M = 1 + nF
        if nF >= 0.999 and reached is None: reached = round(L, 1)
        drops = KILL_EQ * M + REST_EQ
        g = (drops * 0.9 + shop_per_battle) * PD0['gems'] + ELITE * 0.5 + BOSS
        add = g * fort_share * avg_pts
        i = min(range(3), key=lambda k: pts[k]); pts[i] = min(1.40, pts[i] + add)
        if b % 91 == 0 or b == N_B - 1: hist.append((round(L), round(M, 3)))
    return dict(cap_reached_at_level=reached, M_by_level=hist, final_points=[round(p, 2) for p in pts])
T18['loop_A_natural'] = loop(0.0, 'A')
T18['loop_A_shop_dismantle_2_items_per_battle'] = loop(2.0, 'A')
T18['loop_B_multiplicative'] = loop(0.0, 'B')
T18['PASS'] = T18['loop_A_shop_dismantle_2_items_per_battle']['M_by_level'][-1][1] <= 2.0 and all(m <= 2.0 for _, m in T18['loop_A_natural']['M_by_level'])
RC['T18'] = T18

# ---------- T15 save size ----------
T15 = {}
num_ids = [f'NUM-X-{i}' for i in range(100)]
gem_num = {str(1000 + i): 999 for i in range(153)}
gem_txt = {}
for r_ in con.execute('select attribute_id from bonus_numerical_attributes where tier<=4'): gem_txt[r_[0]] = 999
for r_ in con.execute("select passive_id from bonus_passives where minimum_rarity not in ('Legendary','Mythic','Transcendent','Exalted')"): gem_txt[r_[0]] = 999
T15['gem_kinds'] = len(gem_txt)
T15['gem_map_bytes'] = dict(numeric_ids=len(json.dumps(gem_num, separators=(',', ':'))), text_ids=len(json.dumps(gem_txt, separators=(',', ':'))))
rec_typ = [12, [[40, 4], [99, 10]], 3, 2]           # F, pairs, reroll_count, starting_rarity
rec_worst = [1, [[10 * i, i] for i in range(1, 10)] + [[99, 10]], 999, 7]
T15['record_bytes'] = dict(typical=len(json.dumps(rec_typ, separators=(',', ':'))), worst=len(json.dumps(rec_worst, separators=(',', ':'))))
LIMIT = 4 * 1024 * 1024
for n in (100, 1000, 5000, 20000):
    tot = len(json.dumps(gem_txt, separators=(',', ':'))) + n * (60 + T15['record_bytes']['worst'])
    T15[f'{n} items worst (60B Rare+ item + worst record) + text gem map'] = dict(bytes=tot, pct_of_4MB=round(100 * tot / LIMIT, 2))
T15['max_items_worst_case'] = (LIMIT - len(json.dumps(gem_txt, separators=(',', ':')))) // (60 + T15['record_bytes']['worst'])
T15['PASS'] = T15['gem_kinds'] == 153 and T15['gem_map_bytes']['text_ids'] <= 3 * 1024 + 900 and T15['record_bytes']['worst'] <= 90
RC['T15'] = T15

# ---------- T16 / T20 compatibility (design-level rule check on DB eligibility text) ----------
T16 = {}
pas = {r_[0]: dict(name=r_[1], min=r_[2], elig=r_[3]) for r_ in con.execute('select passive_id, passive_name, minimum_rarity, eligible_item_types from bonus_passives')}
attack_shape = [f'PAS-0{n}' for n in (16, 17, 18, 19, 20, 21, 23, 24, 25)]
T16['attack_shape_db_text'] = {p: pas[p]['elig'] for p in attack_shape}
T16['attack_shape_text_mentions_offhand_or_gloves'] = [p for p in attack_shape if re.search(r'(?i)glove|off-?hand|shield|any', pas[p]['elig'])]
T16['main_hand_only_db_text'] = {p: pas[p]['elig'] for p in ('PAS-001', 'PAS-002', 'PAS-046')}
T16['above_epic_passives_no_gem'] = sorted(p for p, v in pas.items() if v['min'] in ('Exalted', 'Legendary', 'Mythic', 'Transcendent'))
T16['exalted_min_passives'] = sorted(p for p, v in pas.items() if v['min'] == 'Exalted')
T16['free_text_needs_generator_groups'] = sorted(p for p, v in pas.items() if re.search(r'(?i)normally|approved|selected|very rare|rare elsewhere|low weight', v['elig']))
T16['PASS_design'] = T16['attack_shape_text_mentions_offhand_or_gloves'] == [] and T16['above_epic_passives_no_gem'] == ['PAS-027', 'PAS-028'] and T16['exalted_min_passives'] == []
RC['T16'] = T16
T20 = {}
fr = list(con.execute("select attribute_id, tier, minimum_rarity, eligible_equipment from bonus_numerical_attributes where attribute_family='Fortune'"))
T20['fortune_rows'] = fr
T20['PASS'] = len(fr) == 4 and all(x[3] == 'Any equipment' for x in fr) and max(x[1] for x in fr) == 4 and 'Fortune does NOT affect material drop rate' in row('materials_system', 19)
T20['note'] = 'Fortune has T1-T4 only, so an above-Epic reroll can offer Fortune T1-T4; roll weight for Fortune is text only ("low weight") - no number in DB'
RC['T20'] = T20

# ---------- T17 threshold maxima (one unit) ----------
T17 = {}
thr = {r_[0]: (r_[1], r_[2], r_[3]) for r_ in con.execute("select passive_id, passive_name, eligible_item_types, bp_cost from bonus_passives where passive_id in ('PAS-007','PAS-008','PAS-009','PAS-010','PAS-011','PAS-012','PAS-013','PAS-014','PAS-015')")}
for p, (nm, el, bp) in thr.items():
    any_eq = el.startswith('Any equipment')
    per = 2 if p in ('PAS-009', 'PAS-010') else 1
    T17[nm] = dict(eligible=el, bp=bp, items=7 if any_eq else 1, max_bonus=(7 if any_eq else 1) * per, with_2H=(6 if any_eq else 1) * per)
def scale(L): return 0.30 + 0.70 * ((L - 1) / 98) ** 0.55
for base_stat, lvl in ((81, 99), (242, 300)):
    flat4 = 7 * round(18 * scale(min(lvl, 99))); pct4 = 7 * 0.22
    tot = base_stat + round(base_stat * pct4) + flat4
    T17[f'stat line example base {base_stat} (L{lvl}), 7x T4 gem lines'] = dict(total_stat=tot, breakpoint_steps=tot // 60, vs_no_gear=base_stat // 60)
T17['Movement max one unit (base AGI 81, 7x Epic items: Movement +1 passive + AGI T1)'] = 3 + (81 + round(81 * 7 * 0.04) + 7 * 3) // 60 + 7
T17['Movement max one unit (base AGI 81, 7x AGI T4 lines on gear, Movement +1 on 7 items needs 150+200 BP > Epic 200)'] = 'cannot have both on one Epic item; best mix = 7 + floor(AGI/60)'
RC['T17'] = T17
