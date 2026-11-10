
import os, json, time, shutil, re
ROOT=r"D:\AI\Projects\CTRBLXAI"
BK=ROOT+r"\_codebackup_lsptidy_20261109"
SESSION="Dev-lsptidy"
STATE=BK+r"\state.json"
EDITLOG=BK+r"\edit_log.md"
CLAIMS=ROOT+r"\_sessions\claims.json"
LOGMD=ROOT+r"\_sessions\log.md"
T_RECON=time.mktime((2026,11,9,20,38,0,0,0,-1))
def now_iso(): return time.strftime("%Y-%m-%dT%H:%M:%S+08:00")
def ap(f): return ROOT+"\\"+f.replace("/","\\")
def load_state():
    if os.path.exists(STATE): return json.load(open(STATE,encoding="utf-8"))
    return {"mtimes":{}}
def save_state(s):
    tmp=STATE+".tmp"; json.dump(s,open(tmp,"w",encoding="utf-8"),indent=1); os.replace(tmp,STATE)
def _wjson(p,d):
    tmp=BK+"\\claims.tmp"
    with open(tmp,"w",encoding="utf-8",newline="\n") as fh: fh.write(json.dumps(d,indent=2)+"\n")
    os.replace(tmp,p)
def claim(files,task):
    d=json.load(open(CLAIMS,encoding="utf-8"))
    ok=[];blocked=[]
    for f in files:
        h=[c for c in d.get("claims",[]) if c.get("session")!=SESSION and (f in c.get("files",[]))]
        if h: blocked.append((f,h[0].get("session"),h[0].get("started")))
        else: ok.append(f)
    if ok:
        d.setdefault("claims",[]).append({"session":SESSION,"task":"lsp tidy (no behaviour change)","files":ok,"started":now_iso(),"expires_hours":3})
        _wjson(CLAIMS,d)
        d2=json.load(open(CLAIMS,encoding="utf-8"))
        mine=set(x for c in d2["claims"] if c.get("session")==SESSION for x in c["files"])
        lost=[f for f in ok if f not in mine]
        if lost: raise RuntimeError("claim not confirmed for %s"%lost)
    others=[(c.get("session"),c.get("files"),c.get("started")) for c in d.get("claims",[]) if c.get("session")!=SESSION]
    print("CLAIMED",ok,"BLOCKED",blocked,"OTHER CLAIMS",others)
    return ok,blocked
def release(files):
    d=json.load(open(CLAIMS,encoding="utf-8"))
    for c in d.get("claims",[]):
        if c.get("session")==SESSION: c["files"]=[x for x in c["files"] if x not in files]
    d["claims"]=[c for c in d["claims"] if not (c.get("session")==SESSION and not c["files"])]
    _wjson(CLAIMS,d)
    print("RELEASED",files)
def logline(files,what):
    with open(LOGMD,"a",encoding="utf-8",newline="\n") as fh:
        fh.write("%s | %s | %s | %s\n"%(time.strftime("%Y-%m-%d %H:%M"),SESSION,", ".join(files),what))
def backup(f):
    dst=BK+"\\"+f.replace("/","\\")+".pre_lsptidy"
    if not os.path.exists(dst):
        os.makedirs(os.path.dirname(dst),exist_ok=True); shutil.copy2(ap(f),dst)
def _bal(s):
    s2=re.sub(r'--[^\n]*','',s)
    s2=re.sub(r'"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\'|`(?:\\.|[^`\\])*`','""',s2)
    kw=len(re.findall(r'\b(function|do|if|repeat)\b',s2))-len(re.findall(r'\b(end|until)\b',s2))
    return (s2.count("(")-s2.count(")"),s2.count("{")-s2.count("}"),s2.count("[")-s2.count("]"),kw)
class Stop(Exception): pass
def _crlf(f): return b"\r\n" in open(ap(f),"rb").read()
def _fix(f,old,new):
    if _crlf(f): return old.replace("\r\n","\n").replace("\n","\r\n"), new.replace("\r\n","\n").replace("\n","\r\n")
    return old,new
def edit(f,old,new,note):
    old,new=_fix(f,old,new)
    p=ap(f); st=load_state(); m=os.path.getmtime(p); exp=st["mtimes"].get(f)
    if exp is None:
        if m>T_RECON: raise Stop("%s changed since recon (mtime %s)"%(f,time.ctime(m)))
    elif abs(m-exp)>0.01: raise Stop("%s mtime changed under me (%s vs %s)"%(f,time.ctime(m),time.ctime(exp)))
    if _bal(old)!=_bal(new): raise Stop("balance delta in edit %s: %s vs %s"%(note,_bal(old),_bal(new)))
    backup(f)
    txt=open(p,encoding="utf-8",newline="").read()
    hay="\n"+txt; key="\n"+old
    c=hay.count(key)
    if c!=1: raise Stop("%s: expected 1 anchored match, found %d for %s"%(f,c,note))
    idx=hay.index(key)
    line=txt[:idx].count("\n")+1
    nt=txt[:idx]+new+txt[idx+len(old):]
    tmp=BK+"\\edit.tmp"
    with open(tmp,"w",encoding="utf-8",newline="") as fh: fh.write(nt)
    os.replace(tmp,p)
    back=open(p,encoding="utf-8",newline="").read()
    if back!=nt: raise Stop("readback mismatch "+f)
    st["mtimes"][f]=os.path.getmtime(p); save_state(st)
    with open(EDITLOG,"a",encoding="utf-8",newline="\n") as fh:
        fh.write("%s | %s | L%d | %s | -%d lines +%d lines\n"%(time.strftime("%H:%M:%S"),f,line,note,old.count("\n"),new.count("\n")))
    print("OK",f.split("/")[-1],"L%d"%line,note)
    return line
def absent(f,name):
    t=open(ap(f),encoding="utf-8").read()
    t=re.sub(r'--\[(=*)\[.*?\]\1\]','',t,flags=re.S); t=re.sub(r'--[^\n]*','',t)
    n=len(re.findall(r'(?<![\w.])%s\b'%re.escape(name),t))
    if n: raise Stop("%s still referenced %d times in %s"%(name,n,f))
def mt(f): return time.strftime("%H:%M:%S",time.localtime(os.path.getmtime(ap(f))))

def simulate(f,edits):
    txt=open(ap(f),encoding="utf-8",newline="").read()
    for old,new,note in edits:
        old,new=_fix(f,old,new)
        hay="\n"+txt; c=hay.count("\n"+old)
        if c!=1: raise Stop("SIM %s: %d anchored matches for [%s]"%(f.split("/")[-1],c,note))
        if _bal(old)!=_bal(new): raise Stop("SIM balance %s"%note)
        i=hay.index("\n"+old); txt=txt[:i]+new+txt[i+len(old):]
    return True
def run_batch(name,plan,checks=(),what=""):
    files=list(plan.keys())
    ok,blocked=claim(files,name)
    done={};skipped={}
    try:
        for f in files:
            if f not in ok: skipped[f]="claimed by other session"; continue
            try:
                simulate(f,plan[f])
                n=0
                for old,new,note in plan[f]:
                    edit(f,old,new,note); n+=1
                done[f]=n
            except Stop as e:
                skipped[f]=str(e); print("SKIP",f,e)
        for f,name_ in checks:
            if f in done: absent(f,name_)
    finally:
        release(ok)
    if done: logline([f.split("/")[-1] for f in done], "%s: %s"%(name,what))
    print("BATCH",name,"done",done,"skipped",skipped)
    for f in done: print("  mtime",f.split("/")[-1],mt(f))
    return done,skipped

def grab(f,first,n,last,trail_blank=True):
    L=open(ap(f),encoding="utf-8").read().split("\n")
    idx=[i for i,l in enumerate(L) if l==first]
    if len(idx)!=1: raise Stop("grab first not unique %s %d"%(first,len(idx)))
    i=idx[0]
    if L[i+n-1]!=last: raise Stop("grab last mismatch %r"%L[i+n-1])
    blk=L[i:i+n]
    if trail_blank and L[i+n]=="" : blk=blk+[""]
    return "\n".join(blk)+"\n"

def ln(f,rx,n=1):
    L=open(ap(f),encoding="utf-8").read().split("\n")
    idx=[i for i,l in enumerate(L) if re.fullmatch(rx,l)]
    if len(idx)!=1: raise Stop("ln not unique %s %d"%(rx,len(idx)))
    return "\n".join(L[idx[0]:idx[0]+n])+"\n"
