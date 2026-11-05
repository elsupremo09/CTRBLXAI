# Run every v2 check and write results_v2.json.  Seed 20261101.  DB read-only.
import json, time
D = r'D:\AI\Projects\CTRBLXAI\sim\runeforge_v2_2026-11-01'
t0 = time.time()
for f in ('v2_core.py', 'v2_tests_a.py', 'v2_tests_b.py', 'v2_tests_c.py', 'v2_tests_d.py'):
    exec(open(D + '\\' + f, encoding='utf-8').read())
ALL = dict(seed=SEED, db=DB, provenance=PROV, A=RES, B=RB, C=RC, D=RD, runtime_s=round(time.time() - t0, 1))
with open(D + r'\results_v2.json', 'w', encoding='utf-8') as fh:
    json.dump(ALL, fh, indent=1, default=str)
print('written', len(json.dumps(ALL, default=str)), 'bytes in', ALL['runtime_s'], 's; formulas/rows with provenance:', len(PROV))
