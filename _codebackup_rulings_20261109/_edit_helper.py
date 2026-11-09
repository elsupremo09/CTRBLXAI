
import os, json, time, hashlib
BK = r"D:\AI\Projects\CTRBLXAI\_codebackup_rulings_20261109"
SRC = r"D:\AI\Projects\CTRBLXAI\source"
MT = os.path.join(BK, "_mtimes.json")
LOG = os.path.join(BK, "_edits.log")
class StopEdit(Exception):
    pass
def _stop(msg):
    print(msg)
    raise StopEdit(msg)
def _load():
    if os.path.exists(MT): return json.load(open(MT))
    man = json.load(open(os.path.join(BK, "manifest.json")))
    return {k: v["mtime"] for k, v in man.items()}
def edit(rel, old, new, label):
    rel = os.path.normpath(rel)
    mt = _load()
    p = os.path.join(SRC, rel)
    cur = os.path.getmtime(p)
    if rel not in mt:
        _stop("STOP: no backup/mtime record for " + rel)
    if abs(cur - mt[rel]) > 0.001:
        _stop("STOP: %s changed on disk since last known state (%s vs %s)" % (rel, time.ctime(cur), time.ctime(mt[rel])))
    raw = open(p, "rb").read().decode("utf-8")
    crlf = "\r\n" in raw
    o = old.replace("\n", "\r\n") if crlf else old
    n = new.replace("\n", "\r\n") if crlf else new
    c = raw.count(o)
    if c != 1:
        _stop("STOP: old text found %d times in %s [%s]" % (c, rel, label))
    out = raw.replace(o, n, 1)
    tmp = p + ".rulings.tmp"
    with open(tmp, "wb") as fh:
        fh.write(out.encode("utf-8"))
    os.replace(tmp, p)
    back = open(p, "rb").read().decode("utf-8")
    okNew = back.count(n) == 1
    okOld = (o in n) or back.count(o) == 0
    okLen = len(back) == len(out)
    mt[rel] = os.path.getmtime(p)
    json.dump(mt, open(MT, "w"), indent=1)
    with open(LOG, "a") as fh:
        fh.write("%s | %s | %s | new x1=%s old gone=%s len ok=%s\n" % (time.ctime(), rel, label, okNew, okOld, okLen))
    print("EDIT", label, "->", rel, "| new present once:", okNew, "| old gone:", okOld, "| length ok:", okLen, "| mtime", time.ctime(mt[rel]))
    if not (okNew and okOld and okLen):
        _stop("VERIFY FAILED for " + label)
def check_all():
    mt = _load()
    for rel, m in mt.items():
        cur = os.path.getmtime(os.path.join(SRC, rel))
        if abs(cur - m) > 0.001:
            print("CHANGED:", rel, time.ctime(cur))
    print("check_all done")

import shutil
def backup(rel):
    rel = os.path.normpath(rel)
    mt = _load()
    p = os.path.join(SRC, rel)
    if abs(os.path.getmtime(p) - mt[rel]) > 0.001:
        _stop("STOP: %s changed since mtimes snapshot" % rel)
    dst = os.path.join(BK, rel + ".pre_rulings")
    if os.path.exists(dst):
        print("backup exists", dst); return
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(p, dst)
    with open(LOG, "a") as fh:
        fh.write("%s | %s | BACKUP .pre_rulings\n" % (time.ctime(), rel))
    print("backed up", rel)
def note(msg):
    with open(LOG, "a") as fh:
        fh.write("%s | %s\n" % (time.ctime(), msg))
