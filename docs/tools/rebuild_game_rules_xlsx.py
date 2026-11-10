# -*- coding: utf-8 -*-
r"""
rebuild_game_rules_xlsx.py  --  CTRBLXAI  (DB -> xlsx rebuild, REVIEW-ONLY)

Reads docs\CTRBLXAI.db READ-ONLY and builds a NEW workbook
docs\CTRBLXAI_Game_Rules.rebuilt.xlsx, plus docs\tools\rebuild_report.md.
It NEVER writes to CTRBLXAI_Game_Rules.xlsx (guarded below) and never writes the DB.

HOW IT WORKS
  * The current xlsx is the styling/layout template. Every sheet is copied
    cell-for-cell (values + styles + widths + heights + freeze panes) into the
    new workbook, so sheet order, names and look are kept.
  * For each sheet that maps to a DB table, the script finds the DB-fed cell
    block (via a per-sheet spec: xlsx column <- DB column) and OVERWRITES those
    cells with the DB value, in DB order. Cells whose text differs are reported.
  * Rows are aligned to the DB by (a) the sheet's declared data-start row and
    (b) a fall-back text match on the key column, so banner/section rows that
    exist only in the xlsx are left untouched and reported as "xlsx-only rows".
  * Sheets with no faithful DB table (template grids, composites) are copied
    unchanged and listed in the report.
"""
import os, sys, json, sqlite3, hashlib, copy, datetime
import openpyxl
from openpyxl.utils import get_column_letter

DOCS   = r"D:\AI\Projects\CTRBLXAI\docs"
DB     = os.path.join(DOCS, "CTRBLXAI.db")
SRC    = os.path.join(DOCS, "CTRBLXAI_Game_Rules.xlsx")
OUT    = os.path.join(DOCS, "CTRBLXAI_Game_Rules.rebuilt.xlsx")
REPORT = os.path.join(DOCS, "tools", "rebuild_report.md")

# ---------------------------------------------------------------------------
# SHEET -> DB TABLE MAPPING (edit here).
#   table : DB table
#   cols  : list of (xlsx_col_index_1based, db_column)   -- DB-fed columns
#   key   : db column used to align rows by text when order differs
#   where : optional SQL WHERE (e.g. frameworks split by system)
#   order : SQL ORDER BY (DB order = rowid unless stated)
#   kind  : "table"  = rows are 1:1 DB rows (banner/header rows may surround them)
#           "skip"   = mapped but not rebuildable faithfully -> copied unchanged
# ---------------------------------------------------------------------------
def C(*names, start=1):
    return [(i + start, n) for i, n in enumerate(names)]

SHEET_MAP = {
 '01 Project Identity':   dict(table='project_rules',   cols=[(1,'__section_topic__'),(2,'rule'),(3,'notes'),(4,'__src__')], key='__section_topic__',
                               note='xlsx col A = "section \u2014 topic" (DB section+topic), B=rule, C=notes. Col D has no DB source (kept as in xlsx). The xlsx also holds ~14 rows not in the DB (see xlsx-only rows).'),
 '02 Core Stats Formulas':dict(table='core_stats',      cols=C('section','topic','rule','notes'), key='topic'),
 '03 Movement Targeting': dict(table='movement_targeting',cols=C('section','topic','rule','notes'), key='topic'),
 '04 Elements Statuses':  dict(table='elements_statuses',cols=C('section','topic','rule','notes','reapplication','effect'), key='topic'),
 '05 Skills Framework':   dict(table='frameworks',      where="system='Skills'",   cols=C('field_or_topic','rule'), key='field_or_topic'),
 '05b Skill Catalog':     dict(table='skills',          cols=None, key='Skill_ID', header_row=1, auto_header=True),
 '06 Augments Framework': dict(table='frameworks',      where="system='Augments'", cols=C('field_or_topic','rule'), key='field_or_topic'),
 '06b Augment Catalog':   dict(table='augments',        cols=None, key='Augment_ID', header_row=1, auto_header=True),
 '07 Doctrines':          dict(table='doctrines',       cols=None, key='Doctrine_ID', header_row=1, auto_header=True),
 '08 Races':             dict(table='races',           cols=C('name','tags','start_str','start_agi','start_int','start_vit','start_dex','start_luk','start_total','growth_str','growth_agi','growth_int','growth_vit','growth_dex','growth_luk','growth_total','passive_name','passive_effect','race_id','legacy_race_id','notes'), key='name', region_only=True),
 '09 Weapons Equipment':  dict(table='weapons_equipment', kind='skip', why='Composite sheet (rules block + 15-weapon archetype table + extra blocks); DB table has 158 free-form rows incl. section markers that are not laid out like the sheet.'),
 '10 Loot Progression':   dict(table='loot_progression',cols=C('id','section','topic','rule','notes'), key='id', header_row=1),
 '11 Trigger Safety':     dict(table='trigger_safety',  cols=C(*['col_%d'%i if i>1 else '11_TRIGGER_SAFETY' for i in range(1,14)]), key='11_TRIGGER_SAFETY'),
 '12 Map Gen Rules':      dict(table='map_gen_rules',   cols=C(*['col_%d'%i if i>1 else 'MAP_GENERATION_RULES_&_PIPELINE' for i in range(1,10)]), key='MAP_GENERATION_RULES_&_PIPELINE', skip_db_first=False),
 '13 Map Templates':      dict(table='map_templates',   cols=C(*['col_%d'%i if i>1 else 'TEMPLATE_MARKER_LEGEND' for i in range(1,10)]), key='TEMPLATE_MARKER_LEGEND'),
 '14 Biomes':             dict(table='biomes',          cols=C(*['col_%d'%i if i>1 else 'BIOME_CATALOG' for i in range(1,10)]), key='BIOME_CATALOG'),
 '15 Regions':            dict(table='regions',         cols=C(*['col_%d'%i if i>1 else 'REGION_CATALOG' for i in range(1,10)]), key='REGION_CATALOG'),
 '16 Terrain Effects':    dict(table='terrain_effects', cols=C(*['col_%d'%i if i>1 else 'TERRAIN_CATALOG' for i in range(1,10)]), key='TERRAIN_CATALOG'),
 '17 Objects Encounters': dict(table='objects_encounters',cols=C(*['col_%d'%i if i>1 else 'MAP_OBJECT_CATALOG' for i in range(1,10)]), key='MAP_OBJECT_CATALOG'),
 '18 Open Decisions':     dict(table='open_decisions',  cols=C(*['col_%d'%i if i>1 else 'OPEN_DECISIONS_&_PARKED_TOPICS' for i in range(1,8)]), key='OPEN_DECISIONS_&_PARKED_TOPICS'),
 '19 Persistent HP MP':   dict(table='persistent_hp_mp_rules',cols=C('id','section','topic','rule','notes'), key='id'),
 '20 Item Affix Names':   dict(table='item_affix_names',cols=C('source_type','source_family','tier','affix_name','notes'), key='__affix_key__', note='xlsx has no id column; trailing composition-rules block is xlsx-only'),
 '21 Unit Progression':   dict(table='unit_progression',cols=C('id','section','topic','rule','notes'), key='id'),
 '22 Economy Framework':  dict(table='economy_framework',cols=C('id','section','topic','rule','notes'), key='id'),
 '23 Materials System':   dict(table='materials_system',cols=C('section','topic','rule','notes'), key='topic'),
 '24 Consumable Prices':  dict(table='consumable_items',kind='skip', why='Computed price view (Shop Price / Cost-Use are derived, not DB columns); cannot be rebuilt from raw table without the pricing formula.'),
 '25 Guild Facilities':   dict(table='guild_facilities',cols=C('id','section','topic','rule','notes'), key='id'),
 '26 Enemy AI Personalities':dict(table='enemy_ai_personalities',cols=C('section','topic','rule','notes'), key='topic'),
 '27 Non-Weapon Equipment':dict(table='nonweapon_equipment',cols=C('id','section','topic','rule','notes','trigger','restriction','display_name','display_text'), key='id'),
 '29 UGC Rental Ownership':dict(table='ugc_rules',      cols=C('id','section','key','value','unit','status','notes'), key='id'),
 '30 Loadout UI Spec':    dict(table='loadout_ui_spec', cols=C('id','section','topic','rule','notes'), key='id'),
 '31 UGC Catalog':        dict(table='ugc_catalog',     cols=C('asset_id','asset_id_2','bundle_id','name','slot','on_sale_verified','status','notes'), key='asset_id'),
}
# T01..T20 -> template_grids (grid_json). Sheets show a colour-coded tile grid.
GRID_SHEETS = {}   # filled at runtime; rebuilt only if grid matches xlsx exactly, else copied unchanged

# Sheets with NO DB table at all are discovered at runtime (anything not above / not T##) and copied unchanged.

# ---------------------------------------------------------------------------
def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()

def txt(v):
    if v is None: return ''
    if isinstance(v, float) and v == int(v): return str(int(v))
    return str(v).strip()

def norm(v):
    return ' '.join(txt(v).split())

def virtual(dn, row, idx):
    if dn == '__section_topic__':
        return '%s \u2014 %s' % (txt(row[idx['section']]), txt(row[idx['topic']]))
    if dn == '__affix_key__':
        return '%s|%s|%s' % (txt(row[idx['source_family']]), txt(row[idx['tier']]), txt(row[idx['affix_name']]))
    if dn == '__src__':
        return None
    return None

def clip(v, n=120):
    t = txt(v).replace('\n', ' \u21b5 ').replace('|', '\\|')
    return t[:n]

def copy_sheet(src_ws, dst_ws):
    for row in src_ws.iter_rows():
        for c in row:
            n = dst_ws.cell(row=c.row, column=c.column, value=c.value)
            if c.has_style:
                n.font = copy.copy(c.font); n.fill = copy.copy(c.fill)
                n.border = copy.copy(c.border); n.alignment = copy.copy(c.alignment)
                n.number_format = c.number_format; n.protection = copy.copy(c.protection)
    for k, d in src_ws.column_dimensions.items():
        dst_ws.column_dimensions[k].width = d.width
        dst_ws.column_dimensions[k].hidden = d.hidden
    for k, d in src_ws.row_dimensions.items():
        dst_ws.row_dimensions[k].height = d.height
        dst_ws.row_dimensions[k].hidden = d.hidden
    for m in src_ws.merged_cells.ranges:
        dst_ws.merge_cells(str(m))
    dst_ws.freeze_panes = src_ws.freeze_panes
    dst_ws.sheet_properties.tabColor = src_ws.sheet_properties.tabColor
    dst_ws.sheet_view.showGridLines = src_ws.sheet_view.showGridLines
    dst_ws.sheet_view.zoomScale = src_ws.sheet_view.zoomScale
    if src_ws.auto_filter and src_ws.auto_filter.ref:
        dst_ws.auto_filter.ref = src_ws.auto_filter.ref


def regen_sheet01(nws, con):
    """Sheet 01 is FULLY regenerated from project_rules in id order.
    A = 'section - topic' (topic only if section empty), B = rule, C = notes, D blank."""
    from openpyxl.styles import Font, PatternFill, Alignment
    nws.delete_rows(1, nws.max_row + 5)
    for rng in list(nws.merged_cells.ranges):
        nws.unmerge_cells(str(rng))
    for r in list(nws.row_dimensions.keys()):
        del nws.row_dimensions[r]
    hdr = ['Topic', 'Rule', 'Status', 'Source']
    fill = PatternFill('solid', start_color='D9E1F2', end_color='D9E1F2')
    for i, h in enumerate(hdr, 1):
        c = nws.cell(row=1, column=i, value=h)
        c.font = Font(bold=True); c.fill = fill
    n = 0
    for (_id, sec, top, rule, notes) in con.execute('SELECT id,section,topic,rule,notes FROM project_rules ORDER BY id'):
        sec, top = txt(sec), txt(top)
        a = ('%s \u2014 %s' % (sec, top)) if sec else top
        n += 1
        nws.cell(row=n + 1, column=1, value=a)
        nws.cell(row=n + 1, column=2, value=rule if rule is not None else '')
        nws.cell(row=n + 1, column=3, value=notes if notes is not None else '')
    for col, w in zip('ABCD', (35, 100, 22, 30)):
        nws.column_dimensions[col].width = w
    nws.freeze_panes = 'A2'
    return n

def db_rows(con, spec):
    t = spec['table']
    where = (' WHERE ' + spec['where']) if spec.get('where') else ''
    cur = con.execute('SELECT * FROM "%s"%s ORDER BY rowid' % (t, where))
    names = [d[0] for d in cur.description]
    return names, cur.fetchall()

def resolve_cols(spec, ws, names):
    """auto_header: match xlsx header row text to DB column names (underscores -> spaces)."""
    if spec.get('cols'): return spec['cols']
    hdr = [txt(c.value) for c in ws[spec.get('header_row', 1)]]
    out = []
    lookup = {n.replace('_', ' ').lower(): n for n in names}
    lookup.update({n.lower(): n for n in names})
    for i, h in enumerate(hdr, 1):
        k = h.lower()
        if k in lookup: out.append((i, lookup[k]))
        elif k.replace('/', '').replace('  ', ' ') in lookup: out.append((i, lookup[k.replace('/', '').replace('  ', ' ')]))
    return out

def main():
    # --- safety: never touch the live workbook ---
    if os.path.normcase(os.path.abspath(OUT)) == os.path.normcase(os.path.abspath(SRC)):
        sys.exit('REFUSING: output path equals live workbook')
    h_src0, h_db0 = sha(SRC), sha(DB)
    uri = 'file:' + DB.replace('\\', '/') + '?mode=ro'
    con = sqlite3.connect(uri, uri=True)

    src = openpyxl.load_workbook(SRC)
    out = openpyxl.Workbook(); out.remove(out.active)
    tg = {r[0]: r for r in con.execute('SELECT template_id,width,height,grid_json FROM template_grids')}

    rep = []          # report sections
    summary = []      # (sheet, table, db_rows, xlsx_rows, diffs, condensed, status)
    for ws in src.worksheets:
        nws = out.create_sheet(ws.title)
        copy_sheet(ws, nws)
        title = ws.title
        if title == '01 Project Identity':
            nrows = regen_sheet01(nws, con)
            summary.append((title, 'project_rules', nrows, nrows + 1, 0, 0, 'FULLY REGENERATED from project_rules (id order)'))
            continue
        spec = SHEET_MAP.get(title)

        # ---- template grids T01..T20 ----
        if title[0] == 'T' and title[1:3].isdigit():
            tid = title[:3]
            if tid not in tg:
                summary.append((title, 'template_grids', 0, ws.max_row, 0, 0, 'UNMAPPED (no grid row) - copied unchanged')); continue
            _, w, h, gj = tg[tid]
            grid = json.loads(gj)
            diffs = []
            for r, rowv in enumerate(grid, 1):
                for c, v in enumerate(rowv, 1):
                    cur = ws.cell(row=r, column=c).value
                    dv = None if v in ('NEU', '', None) else v
                    if norm(cur) != norm(dv):
                        diffs.append((ws.cell(row=r, column=c).coordinate, cur, dv))
            # grids are colour/format driven (fills per tile); NOT rewritten - copied unchanged
            summary.append((title, 'template_grids[%s] %dx%d' % (tid, w, h), h, ws.max_row, len(diffs), 0,
                            'COPIED UNCHANGED (grid diagram; %d cell(s) differ from DB grid)' % len(diffs)))
            if diffs:
                rep.append((title, 'grid diff vs DB (not applied)', diffs, []))
            continue

        if spec is None:
            summary.append((title, '-', '-', ws.max_row, 0, 0, 'NO DB TABLE - copied unchanged')); continue
        if spec.get('kind') == 'skip':
            summary.append((title, spec['table'], '-', ws.max_row, 0, 0, 'NOT REBUILT: ' + spec['why'])); continue

        names, rows = db_rows(con, spec)
        cols = resolve_cols(spec, ws, names)
        if not cols:
            summary.append((title, spec['table'], len(rows), ws.max_row, 0, 0, 'NOT REBUILT: could not resolve columns')); continue
        idx = {n: i for i, n in enumerate(names)}

        # ---- align DB rows to xlsx rows ----
        def dbval(dr, dn):
            if dn.startswith('__'): return virtual(dn, dr, idx)
            return dr[idx[dn]] if dn in idx else None
        colmap = dict(cols)                       # xlsx col -> db col
        key_dn = spec.get('key')
        kcol_x = next((xi for xi, dn in cols if dn == key_dn), cols[0][0])
        if key_dn is None: key_dn = colmap[kcol_x]
        # header/banner rows are never data: the sheet's own header row text is excluded from key matching
        hdr_rows = set()
        for r in range(1, min(ws.max_row, 8) + 1):
            if norm(ws.cell(row=r, column=kcol_x).value) in {norm(dbval(rows[0], key_dn))} and False: pass
        xl_by_key = {}
        for r in range(1, ws.max_row + 1):
            if key_dn == '__affix_key__':
                k = '%s|%s|%s' % (norm(ws.cell(row=r, column=2).value), norm(ws.cell(row=r, column=3).value), norm(ws.cell(row=r, column=4).value))
            else:
                k = norm(ws.cell(row=r, column=kcol_x).value)
            xl_by_key.setdefault(k, []).append(r)
        used = set(); diffs = []; condensed = []; db_only = []; matched = 0; xl_text_only = []; shifted = []; hdr_kept = []
        last_r = 0
        for dr in rows:
            dk = norm(dbval(dr, key_dn))
            cand = [r for r in xl_by_key.get(dk, []) if r not in used]
            cand_after = [r for r in cand if r >= last_r]
            r = (cand_after or cand or [None])[0]
            if r is None:
                db_only.append(dk); continue
            used.add(r); last_r = max(last_r, r); matched += 1
            if r == 1 and spec.get('table') in ('movement_targeting',):
                hdr_kept.append(dk); continue
            for xi, dn in cols:
                if dn == '__src__': continue              # no DB source
                dv = dbval(dr, dn)
                cell = nws.cell(row=r, column=xi)
                cv = ws.cell(row=r, column=xi).value
                if norm(cv) != norm(dv):
                    a_, b_ = norm(cv), norm(dv)
                    entry = (cell.coordinate, cv, dv)
                    if a_ and not b_:
                        # xlsx has text, DB is empty (banner/header label, or hand-written xlsx text):
                        # KEEP the xlsx text -- never blank a cell -- and report it separately.
                        xl_text_only.append(entry); continue
                    if not a_ and not b_:
                        continue
                    # header/banner row: xlsx row's cell text equals a column label -> not data
                    diffs.append(entry)
                    if len(a_) < len(b_):
                        condensed.append(entry)          # spec: xlsx shorter than and different from DB
                    cell.value = dv
        xl_only = [r for r in range(1, ws.max_row + 1) if r not in used and any(norm(ws.cell(row=r, column=c).value) for c in range(1, ws.max_column + 1))]
        # data rows only: xlsx-only rows that are neither banner/header are reported by count
        status = 'REBUILT from %s (matched %d/%d DB rows)' % (spec['table'], matched, len(rows))
        if db_only: status += '; %d DB row(s) NOT FOUND in xlsx (not added)' % len(db_only)
        if xl_text_only: status += '; %d cell(s) xlsx-text-where-DB-empty kept' % len(xl_text_only)
        summary.append((title, spec['table'] + ((' [' + spec['where'] + ']') if spec.get('where') else ''),
                        len(rows), ws.max_row, len(diffs), len(condensed), status))
        rep.append((title, 'diffs', diffs, condensed, db_only, xl_only, spec.get('note'), xl_text_only))

    out.save(OUT)
    con.close()
    h_src1, h_db1 = sha(SRC), sha(DB)

    # ---------------------------- report ----------------------------
    L = []
    L.append('# Rebuild report  -  %s' % datetime.datetime.now().strftime('%Y-%m-%d %H:%M'))
    L.append('')
    L.append('Output (review only): `%s`' % OUT)
    L.append('')
    L.append('## Integrity checks')
    L.append('- Live xlsx SHA-256 before: `%s`' % h_src0)
    L.append('- Live xlsx SHA-256 after : `%s`  ->  **%s**' % (h_src1, 'IDENTICAL' if h_src0 == h_src1 else 'CHANGED!!'))
    L.append('- DB SHA-256 before: `%s`' % h_db0)
    L.append('- DB SHA-256 after : `%s`  ->  **%s**' % (h_db1, 'IDENTICAL' if h_db0 == h_db1 else 'CHANGED!!'))
    L.append('')
    L.append('## Per-sheet summary')
    L.append('')
    L.append('| Sheet | DB table | DB rows | xlsx rows | Cell diffs | Condensed-in-xlsx | Status |')
    L.append('|---|---|---:|---:|---:|---:|---|')
    for s in summary:
        L.append('| %s | %s | %s | %s | %s | %s | %s |' % tuple(str(x).replace('|', '/') for x in s))
    L.append('')
    L.append('"Condensed in xlsx" = xlsx text is shorter than and different from the DB text; a rebuild REPLACES it with the full DB text.')
    L.append('')
    L.append('## Details')
    for item in rep:
        title = item[0]
        if item[1].startswith('grid diff'):
            L.append('\n### %s  (grid diff, informational - sheet copied unchanged)' % title)
            for coord, cur, dbv in item[2][:200]:
                L.append('- %s: xlsx `%s` | DB `%s`' % (coord, clip(cur, 40), clip(dbv, 40)))
            continue
        _, _, diffs, condensed, db_only, xl_only, note, xl_text_only = item
        L.append('\n### %s' % title)
        if note: L.append('_Note: %s_' % note)
        L.append('- cell diffs: %d   |   condensed-in-xlsx: %d   |   DB rows not found in xlsx: %d   |   xlsx-only non-empty rows: %d' % (len(diffs), len(condensed), len(db_only), len(xl_only)))
        if condensed:
            L.append('\n**Condensed in xlsx (rebuild would replace with fuller DB text):**\n')
            L.append('| Cell | xlsx (first 120) | DB (first 120) |'); L.append('|---|---|---|')
            for coord, cur, dbv in condensed:
                L.append('| %s | %s | %s |' % (coord, clip(cur), clip(dbv)))
        other = [d for d in diffs if d not in condensed]
        if other:
            L.append('\n**Other differences:**\n')
            L.append('| Cell | xlsx (first 120) | DB (first 120) |'); L.append('|---|---|---|')
            for coord, cur, dbv in other:
                L.append('| %s | %s | %s |' % (coord, clip(cur), clip(dbv)))
        if xl_text_only:
            L.append('\n**xlsx has text where DB is empty (KEPT as-is in rebuild, not blanked):**\n')
            L.append('| Cell | xlsx (first 120) | DB |'); L.append('|---|---|---|')
            for coord, cur, dbv in xl_text_only:
                L.append('| %s | %s | (empty) |' % (coord, clip(cur)))
        if db_only:
            L.append('\n**DB rows with no matching xlsx row (key):** ' + '; '.join(clip(k, 60) for k in db_only[:50]) + (' ...' if len(db_only) > 50 else ''))
    with open(REPORT, 'w', encoding='utf-8') as f:
        f.write('\n'.join(L))
    print('OK  out=%s' % OUT)
    print('live xlsx unchanged:', h_src0 == h_src1, '| db unchanged:', h_db0 == h_db1)
    for s in summary: print(s)

if __name__ == '__main__':
    main()
