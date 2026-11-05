import sqlite3, json, os
D = 'D:\\AI\\Projects\\CTRBLXAI\\docs\\'
exec(open(D + 'backups\\rftag_20261101_ops.py', encoding='utf-8').read())

def plan(c):
    cur = {}
    errs = []
    for (t, rid, col, mode, a, b, pre) in OPS:
        key = (t, rid, col)
        if key not in cur:
            r = c.execute(f'select "{col}" from {t} where rowid=?', (rid,)).fetchone()
            if r is None:
                errs.append(f'missing row {key}'); continue
            cur[key] = {'old': r[0], 'new': r[0]}
        v = cur[key]['new']
        if mode == 'set':
            if v != a: errs.append(f'SET mismatch {key}: {v[:120]!r}')
            else: cur[key]['new'] = b
        elif mode == 'rep':
            head, sep, tail = (v.partition('[Superseded') if pre else (v, '', ''))
            n = head.count(a)
            if n != 1: errs.append(f'REP count {n} {key}: {a[:70]!r}')
            else: cur[key]['new'] = head.replace(a, b) + sep + tail
        elif mode == 'app':
            cur[key]['new'] = (v or '') + a + b
    return cur, errs
