# safeedit.py - exact-text edit helper for the 18 map objects build (2026-11-07).
# Rules: backup before first edit; refuse if the file changed since backup/last own edit;
# old text must appear exactly once; after write, re-read from disk and confirm.
import os, json, shutil, hashlib, time

ROOT = r'D:\AI\Projects\CTRBLXAI'
SRC = os.path.join(ROOT, 'source')
BK = os.path.join(ROOT, '_codebackup_mapobjs18_20261107')
MAN = os.path.join(BK, '_tools', 'manifest.json')
LOG = os.path.join(BK, '_tools', 'edits.log')

def _load():
    if os.path.exists(MAN):
        return json.load(open(MAN, encoding='utf-8'))
    return {}

def _save(m):
    json.dump(m, open(MAN, 'w', encoding='utf-8'), indent=1)

def _sha(p):
    return hashlib.sha256(open(p, 'rb').read()).hexdigest()

def _log(msg):
    with open(LOG, 'a', encoding='utf-8') as f:
        f.write(time.strftime('%Y-%m-%d %H:%M:%S') + ' ' + msg + '\n')

def backup(rels):
    m = _load()
    out = []
    for rel in rels:
        src = os.path.join(SRC, rel)
        if rel in m:
            out.append((rel, 'already backed up'))
            continue
        if not os.path.exists(src):
            m[rel] = {'new': True, 'mtime': None, 'sha': None}
            out.append((rel, 'NEW FILE (no backup needed)'))
            continue
        dst = os.path.join(BK, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)
        if _sha(src) != _sha(dst):
            raise RuntimeError('backup verify failed: ' + rel)
        st = os.stat(src)
        m[rel] = {'mtime': st.st_mtime, 'sha': _sha(src), 'orig_mtime': st.st_mtime}
        out.append((rel, 'backed up, mtime ' + time.strftime('%m-%d %H:%M:%S', time.localtime(st.st_mtime))))
        _log('BACKUP ' + rel)
    _save(m)
    return out

def check(rel):
    m = _load()
    if rel not in m:
        raise RuntimeError('NOT BACKED UP: ' + rel)
    p = os.path.join(SRC, rel)
    if m[rel].get('new') and m[rel].get('sha') is None:
        return True
    if _sha(p) != m[rel]['sha']:
        raise RuntimeError('CHANGED BY SOMEONE ELSE since backup/last own edit: ' + rel)
    return True

def read(rel):
    return open(os.path.join(SRC, rel), encoding='utf-8', newline='').read()

def edit(rel, old, new, label=''):
    check(rel)
    p = os.path.join(SRC, rel)
    s = read(rel)
    n_old = s.count(old)
    if n_old != 1:
        raise RuntimeError('old text found %d times (need 1) in %s [%s]' % (n_old, rel, label))
    if new and s.count(new) != 0 and old not in new:
        raise RuntimeError('new text already present in %s [%s]' % (rel, label))
    s2 = s.replace(old, new, 1)
    with open(p, 'w', encoding='utf-8', newline='') as f:
        f.write(s2)
    # re-read from disk and verify
    s3 = read(rel)
    if s3 != s2:
        raise RuntimeError('DISK CONTENT MISMATCH after write: ' + rel)
    if new and s3.count(new) != 1:
        raise RuntimeError('new text count %d after write in %s [%s]' % (s3.count(new), rel, label))
    m = _load()
    m[rel]['sha'] = _sha(p)
    m[rel]['mtime'] = os.stat(p).st_mtime
    _save(m)
    _log('EDIT %s [%s] +%d chars' % (rel, label, len(new) - len(old)))
    return 'OK %s [%s] lines now %d' % (rel, label, s3.count('\n'))

def create(rel, content, label=''):
    m = _load()
    p = os.path.join(SRC, rel)
    if os.path.exists(p):
        raise RuntimeError('create: file exists ' + rel)
    with open(p, 'w', encoding='utf-8', newline='') as f:
        f.write(content)
    if read(rel) != content:
        raise RuntimeError('create verify failed ' + rel)
    m[rel] = {'new': True, 'sha': _sha(p), 'mtime': os.stat(p).st_mtime}
    _save(m)
    _log('CREATE %s [%s]' % (rel, label))
    return 'CREATED ' + rel
