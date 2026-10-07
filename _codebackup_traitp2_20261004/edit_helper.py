import os, hashlib
BK = r'D:\AI\Projects\CTRBLXAI\_codebackup_traitp2_20261004'
exec(open(os.path.join(BK, 'lua_balance.py'), encoding='utf-8').read())

def rd(p):
    b = open(p, 'rb').read()
    s = b.decode('utf-8')
    return s, ('\r\n' in s)

def bal(p):
    s, crlf = rd(p)
    r = lua_balance(s)
    return r

def surgical(p, old, new, marker, dry=False):
    """Exact-match single-occurrence replace. old/new written with LF; converted to the
    file's own line ending. marker must be absent before and present exactly once after."""
    s, crlf = rd(p)
    nl = '\r\n' if crlf else '\n'
    o = old.replace('\r\n', '\n')
    n = new.replace('\r\n', '\n')
    if crlf:
        o = o.replace('\n', '\r\n'); n = n.replace('\n', '\r\n')
    c = s.count(o)
    if c != 1:
        return 'ABORT: old-text count=%d (need 1)' % c
    if s.count(marker) != 0:
        return 'ABORT: marker already present %d (edit already landed?)' % s.count(marker)
    before = lua_balance(s)
    s2 = s.replace(o, n, 1)
    if s2.count(marker) != 1:
        return 'ABORT: marker count after replace = %d' % s2.count(marker)
    after = lua_balance(s2)
    if after['net'] != 0 or after['errs']:
        return 'ABORT: balance after edit %r (before %r)' % (after, before)
    if dry:
        return 'DRY OK len %d -> %d' % (len(s), len(s2))
    with open(p, 'w', encoding='utf-8', newline='') as f:
        f.write(s2)
    # verify landed
    s3, crlf3 = rd(p)
    ok = (s3 == s2) and (crlf3 == crlf)
    r3 = lua_balance(s3)
    return 'WROTE ok=%s len %d->%d marker=%d crlf=%s bal=%s' % (ok, len(s), len(s3), s3.count(marker), crlf3, {k: r3[k] for k in ('net', 'opens', 'closes')} | {'errs': r3['errs'][:3]})

def show(p, needle, before=3, after=12):
    s, _ = rd(p)
    L = s.replace('\r\n', '\n').split('\n')
    for i, l in enumerate(L):
        if needle in l:
            for j in range(max(0, i - before), min(len(L), i + after)):
                print(j + 1, L[j])
            print('-----')
