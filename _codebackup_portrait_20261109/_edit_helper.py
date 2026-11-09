
import os,datetime
P=r"D:\AI\Projects\CTRBLXAI"
LOG=P+r"\_codebackup_portrait_20261109\edit_log.txt"
def edit(rel, old, new, expect_mtime=None, label=""):
    p=P+"\\"+rel
    m=os.path.getmtime(p)
    if expect_mtime is not None and abs(m-expect_mtime)>0.01:
        print("STOP mtime changed",rel,m,expect_mtime); return None
    t=open(p,encoding='utf-8',newline='').read()
    n=t.count(old)
    if n!=1: print("STOP count",n,rel); return None
    t2=t.replace(old,new)
    open(p,'w',encoding='utf-8',newline='').write(t2)
    r=open(p,encoding='utf-8',newline='').read()
    ok = r.count(new)==1 and r.count(old)==(1 if old in new else 0)
    ln=r[:r.index(new)].count('\n')+1
    nm=os.path.getmtime(p)
    with open(LOG,'a',encoding='utf-8') as f:
        f.write(f"{datetime.datetime.now().isoformat(timespec='seconds')} | {rel} | L{ln} | {label} | verified={ok}\n")
    print("OK" if ok else "VERIFY FAIL", rel, "line", ln, "mtime", nm)
    L=r.split('\n')
    for i in range(ln-2, ln+new.count('\n')+1): print(i+1, L[i])
    return nm
