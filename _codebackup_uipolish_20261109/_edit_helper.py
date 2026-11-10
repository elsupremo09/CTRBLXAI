
import os, json, datetime
BK=r"D:\AI\Projects\CTRBLXAI\_codebackup_uipolish_20261109"
UI=r"D:\AI\Projects\CTRBLXAI\source\ReplicatedStorage\CTRBLXAI\UI"
def edit(name, old, new, note):
    p=rf"{UI}\{name}.lua"; st=BK+r"\mtimes.json"; m=json.load(open(st))
    if abs(os.path.getmtime(p)-m[name])>0.001:
        print("STOP: mtime changed externally", name); return False
    t=open(p,encoding="utf-8",newline="").read()
    n=t.count(old)
    if n!=1: print("STOP: old text count",n,name); return False
    t2=t.replace(old,new)
    open(p,"w",encoding="utf-8",newline="").write(t2)
    back=open(p,encoding="utf-8",newline="").read()
    ok = back==t2 and back.count(new)>=1
    line=t2[:t2.index(new)].count("\n")+1
    m[name]=os.path.getmtime(p); json.dump(m,open(st,"w"))
    open(BK+r"\edit_log.txt","a",encoding="utf-8").write(f"{datetime.datetime.now().isoformat(timespec='seconds')} | {name}.lua L{line} | {note} | verified={ok}\n")
    print(name,"edit ok" if ok else "VERIFY FAIL","at L",line, "lines", back.count("\n")+1)
    return ok
