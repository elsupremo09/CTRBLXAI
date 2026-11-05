import sqlite3, openpyxl, os, shutil, json, copy
D = r'D:\AI\Projects\CTRBLXAI\docs'
STAMP = '20261104_010726'
OLD = sqlite3.connect('file:' + os.path.join(D, f'CTRBLXAI.db.bak_{STAMP}_traininggrounds') + '?mode=ro', uri=True)
NEWDB = sqlite3.connect('file:' + os.path.join(D, 'CTRBLXAI.db') + '?mode=ro', uri=True)
FILES = ['CTRBLXAI_Game_Rules.xlsx', 'CTRBLXAI_Build_Plan.xlsx', 'CTRBLXAI_Weapons_Equipment.xlsx']  # main exports only; archive copies never touched
log = json.load(open(os.path.join(D, 'backups', f'traininggrounds_{STAMP}_changes.json'), encoding='utf-8'))

def norm(v):
    if v is None: return None
    if isinstance(v, float) and v.is_integer(): v = int(v)
    s = str(v)
    return None if s == '' else s

def fullrow(con, t, kc, kv):
    cur = con.execute(f'select * from "{t}" where "{kc}"=?', (kv,))
    cols = [d[0] for d in cur.description]
    return cols, cur.fetchone()

KEYCOL = {'guild_facilities': 'id', 'economy_framework': 'id', 'game_flow': 'id', 'development_slices': 'slice', 'project_rules': 'id',
          'frameworks': 'id', 'weapons_equipment': 'id', 'loadout_ui_spec': 'id', 'save_data_contract': 'Record',
          'skill_augment_schemas': '05_—_Skill_&_Augment_Runtime_Schemas', 'validation_matrix': 'Area', 'loot_progression': 'id',
          'open_decisions': 'rowid', 'doctrines': 'Doctrine_ID'}

def run(DRY):
    wbs = {f: openpyxl.load_workbook(os.path.join(D, f)) for f in FILES}
    index = {}
    for f, wb in wbs.items():
        for ws in wb.worksheets:
            for row in ws.iter_rows():
                cells = [c for c in row if norm(c.value) is not None]
                if not cells: continue
                index.setdefault(tuple(norm(c.value) for c in cells), []).append((f, ws.title, cells))
    out = []; nomatch = []
    for e in log['edits']:
        t, kv = e['table'], e['key']
        kc = KEYCOL[t]
        if kc == 'rowid':
            cols, oldr = fullrow(OLD, t, 'rowid', kv); cols2, newr = fullrow(NEWDB, t, 'rowid', kv)
        else:
            cols, oldr = fullrow(OLD, t, kc, kv); cols2, newr = fullrow(NEWDB, t, kc, kv)
        pairs = [(c, norm(v)) for c, v in zip(cols, oldr) if norm(v) is not None]
        found = []
        for variant in (pairs, pairs[1:]):
            key = tuple(v for c, v in variant)
            for hit in index.get(key, []):
                found.append((hit, variant))
        files_hit = [h[0][0] for h in found]
        if not found or len(set(files_hit)) != len(files_hit):
            nomatch.append((t, kv, len(found), [(h[0][0], h[0][1], h[0][2][0].row) for h in found])); continue
        for (f, sheet, cells), variant in found:
          colcell = {c: cells[i] for i, (c, v) in enumerate(variant)}
          newd = dict(zip(cols2, newr))
          ws_ = wbs[f][sheet]
          start = cells[0].column - cols.index(variant[0][0])
          contiguous = all(cells[i].column == start + cols.index(c) for i, (c, v) in enumerate(variant))
          for c in e['after']:
            if c not in colcell:
                if contiguous and ws_.cell(row=cells[0].row, column=start + cols.index(c)).value is None:
                    colcell[c] = ws_.cell(row=cells[0].row, column=start + cols.index(c))
                else:
                    nomatch.append((t, kv, 'col not in sheet', c)); continue
            cell = colcell[c]
            assert norm(cell.value) == norm(dict(zip(cols, oldr))[c])
            out.append((f, sheet, cell.coordinate, c, newd[c]))
            if not DRY: cell.value = newd[c]
    # new rows
    newrows = []
    ws = wbs['CTRBLXAI_Game_Rules.xlsx']['25 Guild Facilities']
    last = [norm(c.value) for c in ws[74]]
    assert last == [norm(v) for v in fullrow(NEWDB, 'guild_facilities', 'id', 73)[1]], last
    assert all(c.value is None for c in ws[75])
    for k, rid in enumerate(range(74, 84)):
        r = fullrow(NEWDB, 'guild_facilities', 'id', rid)[1]
        newrows.append(('CTRBLXAI_Game_Rules.xlsx', '25 Guild Facilities', 75 + k, r[0]))
        if not DRY:
            for j, v in enumerate(r):
                cell = ws.cell(row=75 + k, column=j + 1, value=v)
                src = ws.cell(row=74, column=j + 1)
                if src.has_style: cell._style = copy.copy(src._style)
    ws = wbs['CTRBLXAI_Game_Rules.xlsx']['18 Open Decisions']
    r127 = NEWDB.execute('select * from open_decisions where rowid=127').fetchone()
    assert [norm(c.value) for c in ws[126]][:3] == [norm(v) for v in r127][:3]
    assert all(c.value is None for c in ws[127])
    r = NEWDB.execute('select * from open_decisions where rowid=128').fetchone()
    newrows.append(('CTRBLXAI_Game_Rules.xlsx', '18 Open Decisions', 127, 'rowid 128'))
    if not DRY:
        for j, v in enumerate(r):
            cell = ws.cell(row=127, column=j + 1, value=v)
            src = ws.cell(row=126, column=j + 1)
            if src.has_style: cell._style = copy.copy(src._style)
    touched = sorted(set(o[0] for o in out) | {'CTRBLXAI_Game_Rules.xlsx'})
    if not DRY:
        for f in touched:
            p = os.path.join(D, f); b = p + f'.bak_{STAMP}_traininggrounds'
            shutil.copy2(p, b); print('backup', b)
            wbs[f].save(p)
        # read back
        bad = 0
        for f in touched:
            wb = openpyxl.load_workbook(os.path.join(D, f))
            for (ff, sh, coord, c, v) in out:
                if ff == f and wb[sh][coord].value != v: bad += 1; print('XLSX MISMATCH', f, sh, coord)
            if f == 'CTRBLXAI_Game_Rules.xlsx':
                for (ff, sh, rr, rid) in newrows:
                    if rid == 'rowid 128':
                        vals = list(NEWDB.execute('select * from open_decisions where rowid=128').fetchone())
                    else:
                        vals = list(fullrow(NEWDB, 'guild_facilities', 'id', rid)[1])
                    got = [wb[sh].cell(row=rr, column=j + 1).value for j in range(len(vals))]
                    if [norm(x) for x in got] != [norm(x) for x in vals]: bad += 1; print('NEWROW MISMATCH', sh, rr)
        print('xlsx readback mismatches:', bad)
        json.dump({'cells': out, 'new_rows': newrows, 'not_changed': nomatch}, open(os.path.join(D, 'backups', f'traininggrounds_{STAMP}_xlsx.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1, default=str)
    return out, newrows, nomatch
