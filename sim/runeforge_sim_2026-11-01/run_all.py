# Runs every check. Usage (on Elmer-Desktop): python run_all.py   -> writes results.json
OUT = r'D:\AI\Projects\CTRBLXAI\sim\runeforge_sim_2026-11-01'
for f in ['rf_core.py', 'rf_abc.py']:
    exec(open(OUT + '\\' + f, encoding='utf-8').read())
for f in ['rf_econ.py', 'rf_guards.py', 'rf_supply.py']:
    exec(open(OUT + '\\' + f, encoding='utf-8').read())
R['_meta'] = dict(seed=SEED, formulas_loaded=len(PROV), provenance=PROV, db=DB)
json.dump(R, open(OUT + r'\results.json', 'w'), default=str, indent=1)
