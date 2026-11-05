# CTRBLXAI Runeforge + Blacksmith expansion - Simulator core (2026-11-01)
# Read-only use of docs\CTRBLXAI.db. Every formula below is taken from a DB row
# (provenance in FORMULAS_addendum.md). Deterministic: no RNG except seeded hashes.
import sqlite3, re, math, json, itertools
from fractions import Fraction as Fr

DB = r'D:\AI\Projects\CTRBLXAI\docs\CTRBLXAI.db'
OUT = r'D:\AI\Projects\CTRBLXAI\sim\runeforge_sim_2026-11-01'
SEED = 20261101

con = sqlite3.connect('file:' + DB + '?mode=ro', uri=True)

def row(table, rid):
    r = con.execute(f'select rule, notes from {table} where id=?', (rid,)).fetchone()
    return (r[0] or '') + ' || ' + (r[1] or '')

PROV = {}
def prov(name, table, rid, must):
    t = row(table, rid)
    ok = all(m in t for m in must)
    PROV[name] = dict(table=table, row=rid, found=ok, must=must)
    if not ok:
        raise RuntimeError(f'PROVENANCE FAIL {name}: {table} {rid} missing {must}')
    return t

# ---------- formulas pulled from DB ----------
t11 = prov('Base value by slot', 'economy_framework', 11, ['1H = 100', '2H = 150', 'Body = 80', 'Gloves = 50'])
BASE = {k: int(v) for k, v in re.findall(r'(1H|2H|Off-Hand|Body|Head|Gloves|Feet|Accessory) = (\d+)', t11)}
t12 = prov('Rarity multiplier', 'economy_framework', 12, ['Common = 1.0', 'Epic = 4.0'])
RM = {k: Fr(v) for k, v in re.findall(r'(Common|Uncommon|Rare|Epic|Exalted|Legendary|Mythic|Transcendent|Unique) = (\d+(?:\.\d+)?)', t12)}
prov('Level multiplier', 'economy_framework', 13, ['1 + (Item Level - 1) × 0.02'])
prov('Sell value', 'economy_framework', 14, ['floor(Base Value × Rarity Mult × Level Mult × 0.25)', 'starting rarity'])
prov('Shop price', 'economy_framework', 15, ['round(Base Value × Rarity Mult × Level Mult × Shop Markup)', '×4.0 for Common, Uncommon and Rare', '×6.0 for Epic and Exalted'])
prov('Upgrade gold', 'economy_framework', 19, ['floor(Base Value × Rarity Mult × 0.30 × (1 + Target Level / 25) × (1 − 0.03 × (Blacksmith Level − 1)))'])
prov('Downgrade free', 'economy_framework', 21, ['Free'])
prov('Mat tier by target', 'materials_system', 21, ['Target L1-20: T1', 'Target L81-99: T5'])
t22 = prov('Mat qty by rarity', 'materials_system', 22, ['Common = 1/level', 'Epic = 3/level'])
QTY = {k: int(v) for k, v in re.findall(r'(Common|Uncommon|Rare|Epic|Exalted|Legendary|Mythic|Transcendent) = (\d)/level', t22)}
prov('Mat sell', 'materials_system', 28, ['T1 = 5g', 'T4 = 100g', 'Essences cannot be sold'])
prov('Conversion', 'materials_system', 25, ['3× lower tier → 1× next tier'])
prov('Facility cost', 'guild_facilities', 2, ['round(Base × (1 + Level² / Scale))'])
prov('Catch-up fee', 'guild_facilities', 48, ['for each level from the item\'s starting level to its current level', 'using the player\'s current Blacksmith gold discount', 'Downgrading an item below its starting level lowers the starting level'])
t50 = prov('Blacksmith level table', 'guild_facilities', 50, ['L1: 10 / 10 / 0% / Uncommon / 25%', 'L10: 99 / any / 27% / Epic / 50%'])
BS_TABLE = {}
for m in re.finditer(r'L(\d+): (\d+) / (\w+) / (\d+)% / (\w+) / (\d+)%', t50):
    BS_TABLE[int(m.group(1))] = dict(maxup=int(m.group(2)), disc=int(m.group(4)), extract=m.group(5), refund=int(m.group(6)))
t51 = prov('Dismantle output', 'guild_facilities', 51, ['round down (refund %', 'at its current rarity), +1 extra for Rare and up', 'L81+ items give T4, never T5', 'Shop-bought items give nothing'])
t53 = prov('Runeforge level table', 'guild_facilities', 53, ['L1: Add + Remove / 100 / 200 (Uncommon) / T1-T2', 'L10: Tune above-Epic items / 200 / 400 (Epic) / T4'])
prov('Runeforge capacity', 'guild_facilities', 54, ['L1-4 Uncommon 100 BP, L5-9 Rare 150, L10 Epic 200', 'no Add, no rarity change', 'Unique items: never'])
prov('Runeforge action gold', 'guild_facilities', 55, ['floor(item base value x 0.30 x (1 + item level / 25) x factor x (1 - Runeforge discount))', 'T1 = 1 Uncommon, T2 = 2 Uncommon, T3 = 2 Rare, T4 = 2 Epic'])
prov('Epic step fee', 'guild_facilities', 57, ["0.5 x (the item's shop Epic price - its shop price at the item's STARTING rarity", 'No facility discount', '(7) Enchanted items sell at their STARTING rarity'])
prov('Add rule', 'guild_facilities', 44, ['Rarity never goes down', 'Uncommon 100 / Rare 150 / Epic 200; 2H doubled'])
prov('Names+Fortune', 'guild_facilities', 58, ['Fortune is never offered by Add, Reroll or Modify', 'never move it up'])
prov('Essence drops', 'materials_system', 41, ['Treasure chest: 25% chance of 1 Uncommon Essence', 'Elite encounter: 75% chance of 1 Rare Essence', 'Boss encounter: 100%, 1 Epic Essence (1 Rare Essence from bosses in content below L40)'])
prov('Avg mats/battle', 'materials_system', 15, ['chest 0.3', 'elite/boss 0.2'])
prov('Mat lifetime income', 'materials_system', 36, ['T1: ~286', 'T5: ~312'])
prov('Lifetime income', 'economy_framework', 42, ['~175,800g'])
prov('Necessities', 'economy_framework', 43, ['~127,800g'])
prov('Blacksmith share', 'economy_framework', 20, ['~43% of lifetime income'])
prov('Facility total', 'guild_facilities', 5, ['70,927g across all 10 facilities'])

# facility cost tables (parsed)
FAC = {}
for rid, name in [(26, 'Guild Hall'), (27, 'Tavern'), (28, 'Blacksmith'), (29, 'Merchant'), (30, 'Quest Board'), (31, 'Workshop'), (32, 'Training Ground'), (33, 'Library'), (34, 'Trophy Hall'), (49, 'Runeforge')]:
    t = row('guild_facilities', rid)
    FAC[name] = [int(x) for x in re.findall(r'L\d+:(\d+)', t.split('||')[0])]
UNLOCK_GH = {'Guild Hall': 0, 'Tavern': 1, 'Blacksmith': 2, 'Merchant': 2, 'Quest Board': 3, 'Workshop': 4, 'Runeforge': 4, 'Training Ground': 5, 'Library': 6, 'Trophy Hall': 7}
prov('GH unlock schedule', 'guild_facilities', 8, ['L4: Workshop, Runeforge', 'L7: Trophy Hall'])

RAR = ['Common', 'Uncommon', 'Rare', 'Epic', 'Exalted', 'Legendary', 'Mythic', 'Transcendent']
RIDX = {r: i for i, r in enumerate(RAR)}
BUDGET = {'Common': 0, 'Uncommon': 100, 'Rare': 150, 'Epic': 200}
TIER_MINRAR = {1: 'Uncommon', 2: 'Uncommon', 3: 'Rare', 4: 'Epic'}

def lvl_mult(L):
    return 1 + Fr(L - 1) * Fr('0.02')

def disc_bs(bsl):
    return Fr(3, 100) * (bsl - 1)

# --- exact (rational) and naive double versions of the upgrade formula ---
def ug(slot, rar, t, bsl, exact=True):
    if exact:
        return math.floor(BASE[slot] * RM[rar] * Fr(3, 10) * (1 + Fr(t, 25)) * (1 - disc_bs(bsl)))
    return math.floor(BASE[slot] * float(RM[rar]) * 0.30 * (1 + t / 25) * (1 - 0.03 * (bsl - 1)))

def mtier(t):
    return 1 if t <= 20 else 2 if t <= 40 else 3 if t <= 60 else 4 if t <= 80 else 5

def route(slot, rar, s, e, bsl, exact=True):
    g = 0; m = [0] * 6
    for t in range(s + 1, e + 1):
        g += ug(slot, rar, t, bsl, exact); m[mtier(t)] += QTY[rar]
    return g, m[1:]

def catchup(slot, old, new, s, e, bsl, exact=True):
    g = 0; m = [0] * 6
    for t in range(s + 1, e + 1):
        g += ug(slot, new, t, bsl, exact) - ug(slot, old, t, bsl, exact)
        m[mtier(t)] += QTY[new] - QTY[old]
    return g, m[1:]

def sell(slot, rar, L):
    return math.floor(BASE[slot] * RM[rar] * lvl_mult(L) * Fr(1, 4))

def rnd(x):  # round half up for positive rationals (DB 'round')
    return math.floor(x + Fr(1, 2))

def shop(slot, rar, L):
    mk = Fr(6) if rar in ('Epic', 'Exalted') else Fr(4)
    return rnd(BASE[slot] * RM[rar] * lvl_mult(L) * mk)

def epic_fee(slot, start, L):
    if RIDX[start] >= RIDX['Epic']:
        return Fr(0)
    return Fr(1, 2) * (shop(slot, 'Epic', L) - shop(slot, start, L))

def rf_gold(slot, L, factor, rfdisc_pct, exact=True):
    if exact:
        return math.floor(BASE[slot] * Fr(3, 10) * (1 + Fr(L, 25)) * Fr(factor) * (1 - Fr(rfdisc_pct, 100)))
    return math.floor(BASE[slot] * 0.30 * (1 + L / 25) * factor * (1 - rfdisc_pct / 100))

def band_rarity(bp, two_h):
    k = 2 if two_h else 1
    for r in ['Common', 'Uncommon', 'Rare', 'Epic']:
        if bp <= BUDGET[r] * k:
            return r
    return 'ABOVE'

_COMBOS = [c for n in range(1, 9) for c in itertools.combinations_with_replacement([1, 2, 3, 4], n)]
_RFC = {}
def rf_gold_c(slot, L, k, d, exact=True):
    key = (slot, L, k, d, exact)
    if key not in _RFC:
        _RFC[key] = rf_gold(slot, L, k, d, exact)
    return _RFC[key]

_VALID = {}
def _valid_combos(two, start, target, bp0):
    key = (two, start, target, bp0)
    if key in _VALID:
        return _VALID[key]
    cap = BUDGET[target] * (2 if two else 1)
    out = []
    for combo in _COMBOS:
        bp = bp0 + 50 * sum(combo)
        if bp > cap:
            continue
        r = max(RIDX[start], RIDX[band_rarity(bp, two)], max(RIDX[TIER_MINRAR[k]] for k in combo))
        if RAR[r] == target:
            out.append(combo)
    _VALID[key] = out
    return out

def cheapest_add(slot, start, target, bp0, L, rfd, exact=True):
    """Min Add gold to move an item from start rarity (holding bp0 BP) to exactly
    'target' rarity, Adds of T1-T4 (tier unlocks ignored = safest), capacity = target budget."""
    best = None
    for combo in _valid_combos(slot == '2H', start, target, bp0):
        g = sum(rf_gold_c(slot, L, k, rfd, exact) for k in combo)
        if best is None or g < best[0]:
            best = (g, combo)
    return best
