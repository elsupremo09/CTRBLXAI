# Supplement to crucible_sim.py (same seed, same model): knob options + Exalted-only shelf exploit + determinism check.
import json, hashlib
OUTD = r'D:\AI\Projects\CTRBLXAI\sim\crucible_2026-11-02'
src = open(OUTD + r'\crucible_sim.py', encoding='utf-8').read()
G = {'TR_OVERRIDE': 300}
exec(src[:src.find('# ---------- 2. Monte Carlo supply')], G)
run, TL, POOLS, BOSS_P = G['run'], G['TL'], G['POOLS'], G['BOSS_P']
POOL = POOLS['code (146), slot first']
prev = json.load(open(OUTD + r'\results_crucible.json', encoding='utf-8'))
SP = prev['spare_frac_boosted']
tlb = TL[('boosted', 'classic (Crucible after Runeforge)')]
tlf = TL[('free', 'crafter (Runeforge + Crucible with core)')]
X = dict(seed=G['SEED'], spare=SP)
# determinism: re-run one scenario of the main file
X['determinism_rerun_equal'] = run(300, POOL, 'random picker (B4)', 'loot', 30, TL[('free', 'classic (Crucible after Runeforge)')], seed_off=1) == prev['mc']['free | random picker (B4) | loot | spare cap 30']
# Exalted-only buying with many shelves (shelf per map level exploit, gold-limited)
for boss in BOSS_P:
    for K in (1, 10):
        X[f'Exalted-only x{K} shelves | {boss} | spare gold'] = run(300, POOL, boss, 'targeted', 55, tlb, mult=1.25, seed_off=90 + K, shelves_per_restock=K, budget_frac=SP, buy_rar=['Exalted'])
    X[f'Exalted-only x10 shelves | {boss} | 30% of income diverted'] = run(300, POOL, boss, 'targeted', 55, tlb, mult=1.25, seed_off=95, shelves_per_restock=10, budget_frac=0.30, buy_rar=['Exalted'])
# Knob option A: 'similar' = same slot group and hand type (8 groups) instead of the same base item
GROUP = {s: 1 for s in POOL}
# Knob option B: 3 inputs at every Crucible level (same base item)
for nm, pool, need3 in (('A slot-group matching', GROUP, False), ('B same base, 3 inputs at all levels', POOL, True)):
    if need3: G['c_need'] = lambda cl: 3
    else: G['c_need'] = lambda cl: 5 if cl <= 3 else 4 if cl <= 7 else 3
    for boss in BOSS_P:
        X[f'{nm} | boosted | {boss} | loot | cap 30'] = run(300, pool, boss, 'loot', 30, tlb, seed_off=100)
        X[f'{nm} | boosted | {boss} | buying spare gold | cap 30'] = run(300, pool, boss, 'targeted', 30, tlb, mult=1.25, seed_off=101, budget_frac=SP)
        X[f'{nm} | free crafter | {boss} | loot | cap 30'] = run(300, pool, boss, 'loot', 30, tlf, seed_off=102)
    # A + Legendary merges off (stop at Exalted)
    G['c_maxout'] = lambda cl: 'Exalted' if cl >= 9 else 'Epic' if cl >= 7 else 'Rare' if cl >= 4 else 'Uncommon'
    for boss in BOSS_P:
        X[f'{nm} + stop at Exalted | boosted | {boss} | buying spare gold | cap 30'] = run(300, pool, boss, 'targeted', 30, tlb, mult=1.25, seed_off=101, budget_frac=SP)
    G['c_maxout'] = lambda cl: 'Legendary' if cl >= 10 else 'Exalted' if cl >= 9 else 'Epic' if cl >= 7 else 'Rare' if cl >= 4 else 'Uncommon'
json.dump(X, open(OUTD + r'\results_extra.json', 'w', encoding='utf-8'), indent=1, default=str)
print('ok', X['determinism_rerun_equal'])
