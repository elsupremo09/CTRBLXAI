# Extra checks: D2 reproduction (downgrade after Blacksmith L10) and reroll line-count spread (sulfur -> gems).
import itertools
RD = {}
for variant in ('exact', 'D2'):
    r = {}
    for mode in ('early', 'middle', 'late'):
        it = new_item('1H', 'Common', 1, variant)
        if mode == 'early': it.forge('Epic')
        it.upgrade(60, 6); it.downgrade(30, 10)
        if mode == 'middle': it.forge('Epic')
        it.upgrade(60, 10)
        if mode == 'late': it.forge('Epic')
        r[mode] = it.gold
    RD['T3 example, downgrade done at Blacksmith L10: ' + variant] = r
pbps = sorted(set(r[0] for r in con.execute("select bp_cost from bonus_passives where minimum_rarity not in ('Legendary','Mythic')")))
tol = {r[0]: (r[1], r[2], r[3]) for r in con.execute('select rarity, normal_bonus_bp, two_hand_bonus_bp, tolerance from item_rarity_framework')}
res = {}
for rar in ('Exalted', 'Legendary', 'Mythic', 'Transcendent'):
    for two in (False, True):
        nb, tb, tl = tol[rar]; B = tb if two else nb; tl = float(tl) * (2 if two else 1)
        lo, hi = B - tl, B + tl
        maxtier = {'Exalted': 4, 'Legendary': 5, 'Mythic': 6, 'Transcendent': 6}[rar]
        combos = [()] + [(p,) for p in pbps] + ([c for c in itertools.combinations_with_replacement(pbps, 2)] if two else [])
        best = 0; worst = 99
        for pc in combos:
            a, bb = lo - sum(pc), hi - sum(pc)
            for k in range(0, 23):
                if a <= 50 * k <= bb: best = max(best, len(pc) + k)
            for k in range(0, 10):
                if any(a <= 50 * tot <= bb for tot in range(k, k * maxtier + 1)): worst = min(worst, len(pc) + k); break
        res[f"{rar}{' 2H' if two else ''}"] = dict(band=(lo, hi), min_lines=worst, max_lines=best, extra_gems_from_one_reroll_max=best - worst)
RD['reroll_lines_per_set'] = res
