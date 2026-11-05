# D supply window L50-80 + wall with the +1 trick. Requires core, econ, guards.
W = [b for b in range(N_B) if 50 <= lvl_at(b) < 80]
nb = len(W)
items_pb = 0.40
nat_epic = nb * items_pb * 0.0595; nat_epicplus = nb * items_pb * (0.0595 + 0.025 + 0.0012)
sup = {}
for nm in ['classic (Runeforge after core 6)', 'crafter (Runeforge inside core)', 'rush (Guild Hall + Runeforge first)']:
    for who, mult in (('free', 1.0), ('boost', 1.25)):
        s = E[f'{who} {nm} bsA']
        rf10 = s['events'].get('Runeforge', {}).get(10, (None, None))
        m9 = s['events'].get('Merchant', {}).get(9, (None, None))
        # luxury gold in window (income - necessities after discount), i.e. what facilities OR crafting can use
        lux = sum(INC[b] * mult - OTHER[b] - bs_profile('A')[b] * (1 - BS_TABLE[bs_needed(math.floor(lvl_at(b)))]['disc'] / 100) for b in W)
        craft_battles = [b for b in W if rf10[0] is not None and b >= rf10[0]]
        frac = len(craft_battles) / nb
        uU = G['base (0.40 items/battle, elite=boss=0.034)']['band_50_80']['U'] * frac
        gold_lim = lux * frac / 2600     # ~1H Common-start crafted Epic at L65 (2,240 L50 .. 2,944 L80)
        ess_lim = uU / 4                  # 4 x T1 route (Uncommon Essences)
        shop_battles = [b for b in W if m9[0] is not None and b >= m9[0]]
        shop_offers = len(shop_battles) / 5 * 10 * 0.15
        sup[f'{who} {nm}'] = dict(RF10_at_level=rf10[1], merchant9_at_level=m9[1], window_battles=nb, natural_epic=round(nat_epic, 1), natural_epic_or_better=round(nat_epicplus, 1),
                                  shop_epic_offers=round(shop_offers, 1), shop_epics_affordable_with_all_lux=round(lux * (len(shop_battles) / nb) / 5500, 1),
                                  crafted_gold_limited=round(gold_lim, 1), crafted_essence_limited=round(ess_lim, 1), crafted_max=round(min(gold_lim, ess_lim), 1),
                                  window_luxury_gold=round(lux))
R['D']['supply_L50_80'] = sup
# +1 trick supply (Uncommon loot -> 1 T1 Add -> Rare -> dismantle +1), and Common loot -> 3 T1 Adds
def band_items(lo, hi, share):
    return sum(1 for b in range(N_B) if lo <= lvl_at(b) <= hi) * items_pb * 0.9 * share
plus = dict(T3_from_uncommon=round(band_items(41, 60.99, 0.2429), 1), T3_from_common=round(band_items(41, 60.99, 0.55), 1),
            T4_from_uncommon=round(band_items(61, 99, 0.2429), 1), T4_from_common=round(band_items(61, 99, 0.55), 1))
R['F']['plus_one_supply'] = plus
inc_db = [286, 286, 286, 286]
def wall_extra(inc, e3, e4, r3=0, r4=0):
    for N in range(1, 80):
        if N * (25.5 - r3) > inc[2] + e3 or N * (25.5 - r4) > inc[3] + e4: return N
R['F']['wall_with_plus_one'] = dict(db_no_refund=wall_extra(inc_db, plus['T3_from_uncommon'] + plus['T3_from_common'], plus['T4_from_uncommon'] + plus['T4_from_common']),
                                    db_mid_band_refund=wall_extra(inc_db, plus['T3_from_uncommon'] + plus['T3_from_common'], plus['T4_from_uncommon'] + plus['T4_from_common'], 6, 6),
                                    sim0916_mid_band_refund=wall_extra([311] * 4, plus['T3_from_uncommon'] + plus['T3_from_common'], plus['T4_from_uncommon'] + plus['T4_from_common'], 6, 6))
G2 = G['base (0.40 items/battle, elite=boss=0.034)']['per_battle']
fill = {}
for nm, (u, r, e) in {'1H Uncommon (2U)': (2, 0, 0), '1H Rare (3U)': (3, 0, 0), '1H Rare via T3 (2R)': (0, 2, 0), '1H Epic (4U)': (4, 0, 0), '1H Epic via T4 (2E)': (0, 0, 2),
                       '2H Uncommon (4U)': (4, 0, 0), '2H Rare (6U)': (6, 0, 0), '2H Epic (8U)': (8, 0, 0), '2H Epic via 2xT4 (4E)': (0, 0, 4)}.items():
    b = max(u / G2['U'] if u else 0, r / G2['R'] if r else 0, e / G2['E'] if e else 0)
    # with 3:1 trade-up: everything paid in U-equivalents (R = 3U, E = 9U)
    ueq = u + 3 * r + 9 * e
    fill[nm] = dict(battles=round(b, 1), battles_with_tradeup_all_U=round(ueq / (G2['U'] + 3 * G2['R'] + 9 * G2['E']), 1))
R['G']['battles_to_fill'] = fill
R['G']['tradeup'] = dict(E_per_battle_no_tradeup=G2['E'], E_per_battle_if_all_U_traded=round(G2['E'] + G2['U'] / 9, 3), R_per_battle_if_all_U_traded=round(G2['R'] + G2['U'] / 3, 3))
json.dump(R, open(OUT + r'\results.json', 'w'), default=str, indent=1)
