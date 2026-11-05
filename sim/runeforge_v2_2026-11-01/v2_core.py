# CTRBLXAI Blacksmith + Runeforge v2 - Simulator core (2026-11-01)
# DB is opened READ-ONLY. Existing-economy values come from DB rows (prov()).
# v2 rules come from the draft snapshot in this folder (section refs in FORMULAS_v2.md).
# Deterministic: random.Random(SEED) only.
import sqlite3, re, math, json, random
from fractions import Fraction as Fr

DB = r'D:\AI\Projects\CTRBLXAI\docs\CTRBLXAI.db'
OUT = r'D:\AI\Projects\CTRBLXAI\sim\runeforge_v2_2026-11-01'
SEED = 20261101
con = sqlite3.connect('file:' + DB + '?mode=ro', uri=True)

def row(table, rid):
    if table == 'item_rarity_rules':
        return con.execute('select rule_name, rule_value from item_rarity_rules where id=?', (rid,)).fetchone()[1] + ' || '
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

# ---------------- existing DB values ----------------
t11 = prov('Base value by slot', 'economy_framework', 11, ['1H = 100', '2H = 150', 'Body = 80', 'Gloves = 50'])
BASE = {k: int(v) for k, v in re.findall(r'(1H|2H|Off-Hand|Body|Head|Gloves|Feet|Accessory) = (\d+)', t11)}
t12 = prov('Rarity multiplier', 'economy_framework', 12, ['Common = 1.0', 'Epic = 4.0', 'Transcendent = 20.0'])
RM = {k: Fr(v) for k, v in re.findall(r'(Common|Uncommon|Rare|Epic|Exalted|Legendary|Mythic|Transcendent|Unique) = (\d+(?:\.\d+)?)', t12)}
R10 = {k: int(v * 10) for k, v in RM.items()}          # draft 4.2: R = rarity multiplier x 10
prov('Level multiplier', 'economy_framework', 13, ['1 + (Item Level - 1) × 0.02'])
prov('Sell value', 'economy_framework', 14, ['floor(Base Value × Rarity Mult × Level Mult × 0.25)', 'starting rarity'])
prov('Shop price', 'economy_framework', 15, ['round(Base Value × Rarity Mult × Level Mult × Shop Markup)', '×4.0 for Common, Uncommon and Rare', '×6.0 for Epic and Exalted'])
prov('Upgrade gold', 'economy_framework', 19, ['Base Value × Rarity Mult × 0.30 × (1 + Target Level / 25) × (1 − 0.03 × (Blacksmith Level − 1))'])
prov('Recruit fee', 'economy_framework', 22, ['200 + (Unit Level × 15) + Quality Premium'])
prov('Dispatch cost', 'economy_framework', 26, ['50 gold per dispatch mission', 'Base 3 concurrent slots'])
prov('Lifetime income', 'economy_framework', 42, ['~175,800g'])
prov('Necessities', 'economy_framework', 43, ['~127,800g'])
prov('Blacksmith share', 'economy_framework', 20, ['~43% of lifetime income'])
prov('Shop odds', 'economy_framework', 48, ['L10 C10 U30 R40 E15 Exalted 5', '5, 5, 6, 7, 7, 8, 9, 10, 10, 10'])
t13 = prov('BS rarity unlocks', 'guild_facilities', 13, ['L1: Common/Uncommon upgrades', 'L3: Rare', 'L5: Epic upgrades', 'L6: Exalted upgrades', 'L7: Legendary upgrades', 'L9: Mythic upgrades'])
BS_UNLOCK = {'Common': 1, 'Uncommon': 1, 'Rare': 3, 'Epic': 5, 'Exalted': 6, 'Legendary': 7, 'Mythic': 9}   # Transcendent/Unique: not levellable (draft Q5 note)
prov('Facility cost formula', 'guild_facilities', 2, ['round(Base × (1 + Level² / Scale))'])
prov('GH gatekeeper', 'guild_facilities', 3, ['cannot exceed the Guild Hall level'])
prov('GH unlocks', 'guild_facilities', 8, ['L4: Workshop, Runeforge', 'L7: Trophy Hall'])
FAC = {}
for rid, name in [(26, 'Guild Hall'), (27, 'Tavern'), (28, 'Blacksmith'), (29, 'Merchant'), (30, 'Quest Board'), (31, 'Workshop'), (32, 'Training Ground'), (33, 'Library'), (34, 'Trophy Hall'), (49, 'Runeforge')]:
    FAC[name] = [int(x) for x in re.findall(r'L\d+:(\d+)', row('guild_facilities', rid).split('||')[0])]
UNLOCK_GH = {'Guild Hall': 0, 'Tavern': 1, 'Blacksmith': 2, 'Merchant': 2, 'Quest Board': 3, 'Workshop': 4, 'Runeforge': 4, 'Training Ground': 5, 'Library': 6, 'Trophy Hall': 7}
prov('Normal drop', 'loot_progression', 13, ['min(95%, 5% x Fortune Multiplier)'])
prov('Elite reward', 'loot_progression', 14, ['min(95%, 75% x Fortune Multiplier)'])
prov('Unit Fortune', 'loot_progression', 9, ['LUK / (LUK + 200)'])
prov('Expedition Fortune', 'loot_progression', 10, ['Highest deployed Unit Fortune + 50% of second-highest + 25% of third-highest'])
prov('Normalized Fortune', 'loot_progression', 11, ['Expedition Fortune / 1.75', '2.00x'])
prov('Fortune quality', 'loot_progression', 16, ['Base Rarity Weight x (1 + Normalized Expedition Fortune x Rarity Sensitivity)'])
prov('Fortune gold', 'loot_progression', 17, ['1 + 0.50 x Normalized Expedition Fortune'])
prov('Enemies per battle', 'loot_progression', 86, ['Normal 5, Elite 6, Boss 4 + the boss'])
prov('Drops/battle working estimate', 'loot_progression', 24, ['about 0.40 equipment drops per battle'])
prov('Elite/boss/chest working estimate', 'loot_progression', 26, ['elite encounters about 0.034 per battle', 'bosses about 0.034', 'treasure chests about 0.2'])
prov('Old kill material', 'materials_system', 7, ['20% chance per kill', '~1.6 per battle from 8 enemies'])
prov('Fortune excl. materials', 'materials_system', 19, ['Fortune does NOT affect material drop rate'])
prov('Dispatch offers', 'unit_progression', 99, ['one dispatch mission offered per difficulty tier', 'Duration (DAYS away) = difficulty tier'])
prov('Item scale', 'item_rarity_rules', 7, ['Scale(L) = 0.30 + 0.70 × ((L − 1) / 98)^0.55'])
prov('Rarity budgets', 'item_rarity_rules', 2, ['Common 0; Uncommon 100; Rare 150; Epic 200; Exalted 225; Legendary 250; Mythic 300; Transcendent 350'])
prov('Passive limit', 'item_rarity_rules', 3, ['at most 1 Bonus Passive', 'A 2H weapon may spawn at most 2'])
prov('Movement', 'core_stats', 3, ['Movement Range = 3 + floor(AGI / 60)'])
PROV['Black Market'] = dict(table='objects_encounters', row=31, found=True, must=['six fixed discounted high-tier items (col_7)'])

LW_N = {}
for rid, r_ in [(48, 'Common'), (49, 'Uncommon'), (50, 'Rare'), (51, 'Epic'), (84, 'Exalted'), (52, 'Legendary'), (53, 'Mythic')]:
    rr = con.execute('select topic, rule, notes from loot_progression where id=?', (rid,)).fetchone()
    assert rr[0] == r_, (rid, rr)
    LW_N[r_] = (float(rr[1]), float(rr[2]))   # (normal, elite)
SENS = {}
for rid, r_ in [(59, 'Common'), (60, 'Uncommon'), (61, 'Rare'), (62, 'Epic'), (85, 'Exalted'), (63, 'Legendary'), (64, 'Mythic')]:
    rr = con.execute('select topic, rule from loot_progression where id=?', (rid,)).fetchone()
    assert rr[0] == r_
    SENS[r_] = float(rr[1])

RAR = ['Common', 'Uncommon', 'Rare', 'Epic', 'Exalted', 'Legendary', 'Mythic', 'Transcendent']
RIDX = {r: i for i, r in enumerate(RAR)}
BUDGET = {'Common': 0, 'Uncommon': 100, 'Rare': 150, 'Epic': 200, 'Exalted': 225, 'Legendary': 250, 'Mythic': 300, 'Transcendent': 350}

def lvl_mult(L): return 1 + Fr(L - 1) * Fr(2, 100)
def rnd(x): return math.floor(x + Fr(1, 2))
def shop(slot, rar, L):
    mk = Fr(6) if rar in ('Epic', 'Exalted') else Fr(4)
    return rnd(BASE[slot] * RM[rar] * lvl_mult(L) * mk)
def sell(slot, rar_start, L): return math.floor(BASE[slot] * RM[rar_start] * lvl_mult(L) * Fr(1, 4))
def bs_needed(t): return min(10, max(1, math.ceil(t / 10)))

# ---------------- v2 rules (draft) ----------------
# 4.1 credit(t, b) = slotValue x 3 x (25 + t) x (100 - 3 x (b - 1))
def credit(slot, t, b): return BASE[slot] * 3 * (25 + t) * (100 - 3 * (b - 1))
# 4.2 Paid(C, R) = floor(C x R / 250,000)
def paid(C, R): return C * R // 250000
# prefix sums per slot/b for fast C
_CUM = {}
for s in BASE:
    for b in range(1, 11):
        acc = [0] * 101
        for t in range(1, 100):
            acc[t] = acc[t - 1] + (credit(s, t, b) if t >= 2 else 0)
        _CUM[(s, b)] = acc
def seg(slot, b, lo, hi):   # credit of levels lo+1..hi at discount b
    a = _CUM[(slot, b)]
    return a[hi] - a[lo]
# 2.3 crystals
STEP = {'Uncommon': 3, 'Rare': 6, 'Epic': 12}
KEEP = {'Uncommon': 2, 'Rare': 4, 'Epic': 8}
def forge_crystals(old, new):
    if RIDX[new] == RIDX[old]:
        return KEEP.get(old, 0) if old != 'Common' else None   # Common keep-rarity forge impossible (0 lines)
    return sum(STEP[r] for r in RAR[RIDX[old] + 1: RIDX[new] + 1])
# 2.3 forge fee = floor(slot x RM(result) x (100 - RF discount%) / 100)
def forge_fee(slot, new, rf_level):
    d = 3 * (rf_level - 1)
    return math.floor(BASE[slot] * RM[new] * (100 - d) / 100)
def epic_step_fee(slot, start):   # optional, default OFF: floor(0.5 x (L1 shop Epic - L1 shop at start))
    if RIDX[start] >= RIDX['Epic']: return 0
    return math.floor(Fr(1, 2) * (shop(slot, 'Epic', 1) - shop(slot, start, 1)))
# 1.4 dismantle
DIS_CRY = {'Common': 0, 'Uncommon': 1, 'Rare': 2, 'Epic': 3, 'Exalted': 4, 'Legendary': 6, 'Mythic': 8, 'Transcendent': 10, 'Unique': 10}
DIS_SUL = {'Common': 0, 'Uncommon': 0, 'Rare': 0, 'Epic': 0, 'Exalted': 1, 'Legendary': 2, 'Mythic': 3, 'Transcendent': 4, 'Unique': 3}
def dis_merc(L): return math.ceil(L / 10)
# 2.4 runeforge capacity
RF_CAP = {1: 'Uncommon', 4: 'Rare', 7: 'Epic'}
def rf_capacity(rfl): return 'Epic' if rfl >= 7 else 'Rare' if rfl >= 4 else 'Uncommon'

class Item:
    """Levelling record per draft 4.1 / 4.2 (exact rule) with variant switch for controls."""
    def __init__(self, slot, rar, F, variant='exact'):
        self.slot, self.rar, self.F, self.pairs, self.variant = slot, rar, F, [], variant
        self.Cv = 0           # stored C for variants 'reset' and 'D2'
        self.gold = 0; self.merc = 0; self.lost = 0; self.max_pairs = 0
        self.shadow = []      # true purchase record (for straight-route comparison in variants)
    @property
    def level(self): return self.pairs[-1][0] if self.pairs else self.F
    def _C_of(self, F, pairs):
        c = 0; lo = F
        for hi, b in pairs:
            c += seg(self.slot, b, lo, hi); lo = hi
        return c
    def C(self):
        return self._C_of(self.F, self.pairs) if self.variant == 'exact' else self.Cv
    def C_true(self):
        F, p = self.shadow_state()
        return self._C_of(F, p)
    def shadow_state(self):
        return (self.F, self.pairs) if self.variant == 'exact' else self._sh
    def upgrade(self, to, b):
        L = self.level; assert to > L
        if self.pairs: assert b >= self.pairs[-1][1], 'discount must not fall'
        c0 = self.C()
        if self.pairs and self.pairs[-1][1] == b: self.pairs[-1] = (to, b)
        else: self.pairs.append((to, b))
        if self.variant != 'exact':
            self.Cv += seg(self.slot, b, L, to)
            Fs, ps = self._sh
            ps = list(ps)
            if ps and ps[-1][1] == b: ps[-1] = (to, b)
            else: ps.append((to, b))
            self._sh = (Fs, ps)
        g = paid(self.C(), R10[self.rar]) - paid(c0, R10[self.rar])
        self.gold += g; self.merc += to - L
        self.max_pairs = max(self.max_pairs, len(self.pairs))
        return g
    @staticmethod
    def _cut(F, pairs, B):
        np_ = []
        for hi, b in pairs:
            if hi <= B: np_.append((hi, b))
            else:
                if (np_[-1][0] if np_ else F) < B: np_.append((B, b))
                break
        if B < F: F = B
        return F, np_
    def downgrade(self, B, b_now=None):
        assert 1 <= B <= self.level
        c0 = self.C(); L = self.level
        if self.variant == 'exact':
            self.F, self.pairs = self._cut(self.F, self.pairs, B)
        else:
            Fs, ps = self._sh
            self._sh = self._cut(Fs, ps, B)
            if self.variant == 'reset':
                self.Cv = 0
            elif self.variant == 'D2':      # remove dropped levels at TODAY's discount
                rem = sum(credit(self.slot, t, b_now) for t in range(max(B, self.F) + 1, L + 1))
                self.Cv = max(0, self.Cv - rem)
            self.F, self.pairs = self._cut(self.F, self.pairs, B)
        self.lost += paid(c0, R10[self.rar]) - paid(self.C(), R10[self.rar])
    def forge(self, new):
        assert RIDX[new] >= RIDX[self.rar]
        c = self.C()
        g = paid(c, R10[new]) - paid(c, R10[self.rar])
        self.gold += g; self.rar = new
        return g
def new_item(slot, rar, F, variant='exact'):
    it = Item(slot, rar, F, variant)
    it._sh = (F, [])
    return it

# ---------- economy timeline (same shape as sim\runeforge_sim_2026-11-01\rf_econ.py) ----------
N_B = 547; INCOME = 175800; NEC = 127800; BS_SHARE = 0.43
def lvl_at(b): return 1 + b * 98 / N_B
def g_shape(L): return (4.4 * 8 + 0.6 * 14) * (1 + L / 100) + 30 * (1 + L / 50) + 50 * (1 + L / 40)
_gs = [g_shape(lvl_at(b)) for b in range(N_B)]
K_INC = INCOME / sum(_gs)
INC = [x * K_INC for x in _gs]

def save(name, obj):
    with open(OUT + '\\' + name, 'w', encoding='utf-8') as f:
        json.dump(obj, f, indent=1, default=str)
