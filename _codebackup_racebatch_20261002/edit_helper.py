import re,os
def lua_balance(src):
    i=0;n=len(src);line=1;stack=[];errs=[];opens=0;closes=0;brk=[]
    pairs={')':'(',']':'[','}':'{'}
    def longbr(j):
        k=j+1;lv=0
        while k<n and src[k]=='=':lv+=1;k+=1
        if k<n and src[k]=='[': return lv,k+1
        return -1,j
    prev_sig=''
    while i<n:
        c=src[i]
        if c=='\n': line+=1;i+=1;continue
        if c in ' \t\r': i+=1;continue
        if src.startswith('--',i):
            if i+2<n and src[i+2]=='[':
                lv,k=longbr(i+2)
                if lv>=0:
                    close=']'+'='*lv+']';e=src.find(close,k)
                    if e<0: errs.append(('unterminated long comment',line));return dict(net=None,errs=errs)
                    line+=src.count('\n',i,e);i=e+len(close);continue
            e=src.find('\n',i);i=n if e<0 else e;continue
        if c=='[':
            lv,k=longbr(i)
            if lv>=0:
                close=']'+'='*lv+']';e=src.find(close,k)
                if e<0: errs.append(('unterminated long string',line));return dict(net=None,errs=errs)
                line+=src.count('\n',i,e);i=e+len(close);prev_sig='str';continue
        if c in '"\'`':
            q=c;j=i+1
            while j<n and src[j]!=q:
                if src[j]=='\\':
                    if j+1<n and src[j+1]=='\n': line+=1
                    j+=2;continue
                if src[j]=='\n':
                    if q!='`': errs.append(('newline in string',line))
                    line+=1
                j+=1
            if j>=n: errs.append(('unterminated string',line));return dict(net=None,errs=errs)
            i=j+1;prev_sig='str';continue
        if c.isalpha() or c=='_':
            m=re.compile(r'[A-Za-z_][A-Za-z0-9_]*').match(src,i);w=m.group(0)
            dotted = prev_sig in ('.',':')
            i=m.end()
            if not dotted:
                if w in('function','if','repeat'):
                    stack.append([w,line,False]);opens+=1
                elif w in('for','while'):
                    stack.append([w,line,True]);opens+=1
                elif w=='do':
                    if stack and stack[-1][0] in('for','while') and stack[-1][2]: stack[-1][2]=False
                    else: stack.append(['do',line,False]);opens+=1
                elif w=='end':
                    closes+=1
                    if not stack or stack[-1][0]=='repeat': errs.append(('stray end',line))
                    else:
                        t=stack.pop()
                        if t[2]: errs.append(('end before do for '+t[0],line))
                elif w=='until':
                    closes+=1
                    if not stack or stack[-1][0]!='repeat': errs.append(('stray until',line))
                    else: stack.pop()
                elif w in('elseif','else','then'):
                    if not stack or stack[-1][0]!='if': errs.append((w+' outside if',line))
            prev_sig='id';continue
        if c in '([{': brk.append((c,line))
        elif c in ')]}':
            if not brk or brk[-1][0]!=pairs[c]: errs.append(('bracket mismatch '+c,line))
            else: brk.pop()
        if c=='.' and src.startswith('..',i):
            prev_sig='..';i+=2;continue
        prev_sig=c;i+=1
    for t in stack: errs.append(('unclosed '+t[0],t[1]))
    for b in brk: errs.append(('unclosed '+b[0],b[1]))
    return dict(net=opens-closes,opens=opens,closes=closes,errs=errs)
ROOT=r'D:\AI\Projects\CTRBLXAI\source'
def P(f): return os.path.join(ROOT,f)
def edit(f, old, new, expect=1):
    p=P(f); t=open(p,encoding='utf-8',newline='').read()
    crlf='\r\n' in t
    o=old.replace('\r\n','\n'); n=new.replace('\r\n','\n')
    if crlf: o=o.replace('\n','\r\n'); n=n.replace('\n','\r\n')
    c=t.count(o)
    if c!=expect: return 'SKIP count=%d %s'%(c,f)
    t2=t.replace(o,n,1)
    r=lua_balance(t2)
    if r['net']!=0 or r['errs']: return 'BALANCE FAIL %s %s'%(f,r)
    open(p,'w',encoding='utf-8',newline='').write(t2)
    back=open(p,encoding='utf-8',newline='').read()
    return 'OK %s net=%s ok=%s crlf=%s'%(f,r['net'],back==t2,crlf)
