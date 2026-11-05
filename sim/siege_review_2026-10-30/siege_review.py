
import sqlite3,re,math,json
c=sqlite3.connect(r'file:D:\AI\Projects\CTRBLXAI\docs\CTRBLXAI.db?mode=ro',uri=True)
R={r[0]:r[1:] for r in c.execute("select name,start_str,start_agi,start_int,start_vit,start_dex,start_luk,growth_str,growth_agi,growth_int,growth_vit,growth_dex,growth_luk from races")}
S=['STR','AGI','INT','VIT','DEX','LUK']
def scale(L): return 0.30+0.70*((L-1)/98)**0.55   # weapons_equipment 157 / nonweapon 11
def stats(race,L,alloc):  # unit_progression 49,100,104
    st,gr=R[race][:6],R[race][6:]
    pts=(L-1)*3
    out={}
    for i,k in enumerate(S): out[k]=st[i]+math.floor(gr[i]*(L-1))
    if alloc=='even':
        q,r=divmod(pts,6)
        for i,k in enumerate(S): out[k]+=q+(1 if i<r else 0)
    else:
        tot=sum(alloc.values()); given=0
        ks=list(alloc)
        for k in ks[:-1]:
            v=round(pts*alloc[k]/tot); out[k]+=v; given+=v
        out[ks[-1]]+=pts-given
    return out
rows=c.execute("select section,topic from nonweapon_equipment").fetchall()
gear={}
for a,b in rows:
    m=re.search(r'Def:(-?\d+) / WT:(-?\d+) / HP:(-?\d+)',b or '')
    if a and m and a[:2] in('HD','BD','GL','FT','AC'): gear.setdefault(a[:2],[]).append(tuple(map(int,m.groups())))
def kit(kind):
    d=h=0
    for s,l in gear.items():
        if kind=='light': x=min(l,key=lambda t:t[0])
        elif kind=='heavy': x=max(l,key=lambda t:t[0])
        else: x=(sum(t[0] for t in l)/len(l),0,sum(t[2] for t in l)/len(l))
        d+=x[0]; h+=x[2]
    return d,h
W={'Sword':67,'Longbow':50,'Wand':25,'Bell':5,'War Axe':97}
WDEF={'light':0,'medium':5,'heavy':44}
OPS={'STR melee (Orc, Sword)':('Orc','Sword',{'STR':2,'VIT':1}),
     'DEX ranged (Feline, Longbow)':('Feline','Longbow',{'AGI':1,'DEX':2}),
     'Caster (Elf, Wand)':('Elf','Wand',{'VIT':1,'INT':2}),
     'Caster worst (Elf, Bell)':('Elf','Bell',{'VIT':1,'INT':2})}
TG={'light':('Feline','light'),'medium':('Human','medium'),'heavy':('Dwarf','heavy')}
def target(k,L):
    race,kd=TG[k]; s=stats(race,L,'even'); d,h=kit(kd); sc=scale(L)
    df=(d+WDEF[kd])*sc; hp=50+s['VIT']*4+h*sc
    return s,df,hp
def hitq(a,t,extra=0): return 1+(a['DEX']/(a['DEX']+200)-t['AGI']/(t['AGI']+200))+extra
def fort(a,t):
    dl=a['LUK']-t['LUK']; return 1+0.40*dl/(abs(dl)+150)
def dmg(power,a,t,df,hq_extra=0,pos=1.0,str_scale=True):
    AP=power*(1+a['STR']/200) if str_scale else power
    DP=df*(1+t['VIT']/300)
    raw=AP-AP*DP/(AP+DP) if AP+DP>0 else 0
    return raw*hitq(a,t,hq_extra)*pos*fort(a,t)
def wd(op,L): return round(W[OPS[op][1]]*scale(L))
BANDS=[1,10,20,30,50,99]
res=[]
for op,(race,wpn,al) in OPS.items():
  for L in BANDS:
    a=stats(race,L,al); w=wd(op,L); pot=1+a['INT']/(200+a['INT'])
    for tk in TG:
      ts,df,hp=target(tk,L)
      row=dict(op=op,L=L,tgt=tk,W=w,STR=a['STR'],DEX=a['DEX'],INT=a['INT'],tDef=round(df,1),tHP=round(hp))
      for helm in (1.0,1.5):
        bal=math.floor(w*2.5*helm)+L; bal0=math.floor(w*2.5*helm); cat=math.floor(w*2.0*helm)
        sfx='' if helm==1 else '_helm'
        row['bal'+sfx]=round(dmg(bal,a,ts,df)); row['bal_nolvl'+sfx]=round(dmg(bal0,a,ts,df)); row['cat'+sfx]=round(dmg(cat,a,ts,df))
      row['bal_worst']=round(dmg(math.floor(w*3.75)+L,a,ts,df,0.5,1.30))
      row['cat_worst']=round(dmg(math.floor(w*3.0),a,ts,df,0.5,1.30))
      row['basic']=round(dmg(w,a,ts,df))
      skm=1.25 if 'STR' in op else (1.30 if 'DEX' in op else 1.10)
      # skill power = Weapon Attack Power x mult x potency (already STR-scaled)
      row['skill']=round(dmg(w*(1+a['STR']/200)*skm*pot,a,ts,df,str_scale=False))
      res.append(row)
json.dump(res,open(r'D:\AI\Projects\CTRBLXAI\sim\siege_review_2026-10-30\results.json','w'),indent=1)
