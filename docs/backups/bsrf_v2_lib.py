import json, sqlite3, openpyxl
D = 'D:\\AI\\Projects\\CTRBLXAI\\docs\\'
GR, BP, IR = 'CTRBLXAI_Game_Rules.xlsx', 'CTRBLXAI_Build_Plan.xlsx', 'CTRBLXAI_Item_Rarity_BP_Bonus_Attributes 3.xlsx'
SHEET = {
 'guild_facilities': (GR, '25 Guild Facilities', True),
 'materials_system': (GR, '23 Materials System', False),
 'economy_framework': (GR, '22 Economy Framework', True),
 'loot_progression': (GR, '10 Loot Progression', True),
 'objects_encounters': (GR, '17 Objects Encounters', False),
 'open_decisions': (GR, '18 Open Decisions', False),
 'unit_progression': (GR, '21 Unit Progression', True),
 'project_rules': (GR, '01 Project Identity', None),
 'bonus_numerical_attributes': (IR, '01 Numerical Attributes', False),
 'item_rarity_rules': (IR, '00 Framework', False),
 'item_generation_steps': (IR, '04 Generation Steps', False),
 'equipment_schema': (BP, '04 — Equipment Runtime Schema', False),
 'save_data_contract': (BP, '14 — Save Data Contract', False),
 'service_boundaries': (BP, '02 — Service Boundaries', False),
 'implementation_plan': (BP, '19 Implementation Plan', False),
}

def norm(v):
    if v is None: return ''
    if isinstance(v, float) and v.is_integer(): v = int(v)
    return str(v)

def dbcols(c, t):
    return [r[1] for r in c.execute(f'pragma table_info({t})')]

def sheet_values(t, cols, row):
    """row: dict col->value (DB). returns list of expected sheet cell values (in sheet column order)."""
    f, s, has_id = SHEET[t]
    if t == 'project_rules':
        return [f"{row['section']} — {row['topic']}", row['rule'], row['notes']]
    cs = [x for x in cols if has_id or x != 'id']
    return [row[x] for x in cs]

def sheet_colindex(t, cols, col):
    f, s, has_id = SHEET[t]
    if t == 'project_rules':
        return {'section': 1, 'topic': 1, 'rule': 2, 'notes': 3}[col]
    cs = [x for x in cols if has_id or x != 'id']
    return cs.index(col) + 1

def find_row(ws, expected):
    """best row whose cells match expected values; returns (row, matches, total)."""
    best = (None, -1)
    n = len(expected)
    exp = [norm(v) for v in expected]
    for r in range(1, ws.max_row + 1):
        m = sum(1 for i in range(n) if norm(ws.cell(r, i + 1).value) == exp[i])
        if m > best[1]: best = (r, m)
    return best[0], best[1], n
