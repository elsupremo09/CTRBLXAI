
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

# ===== v2: approved model 2026-10-30 18:20 (authoritative per brief) =====
OPS['Hybrid (Human, Sword, STR/DEX/INT, Arcane Strike)']=('Human','Sword',{'STR':1,'DEX':1,'INT':1})
BANDS=[1,10,20,30,50,75,99]
def siege_power(L,a,helm=1.0): return (48+1.9*L)*(1+a['DEX']/(a['DEX']+200))*helm
def sdmg(P,a,t,df,height=1.0):   # power -> defense -> height -> fortune; NO hit quality
    DP=df*(1+t['VIT']/300); eff=P*DP/(P+DP) if P+DP>0 else 0
    return (P-eff)*height*fort(a,t)
SK={'STR':('Rending Slash',0.95),'DEX':('Crippling Shot',0.80),'Cas':('Fire Bolt',1.10),'Hyb':('Arcane Strike',1.00)}
out=[]
for op,(race,wpn,al) in OPS.items():
  key='STR' if op.startswith('STR') else 'DEX' if op.startswith('DEX') else 'Hyb' if op.startswith('Hyb') else 'Cas'
  for L in BANDS:
    a=stats(race,L,al); w=wd(op,L); pot=1+a['INT']/(200+a['INT'])
    a0=dict(a); a0['DEX']=stats(race,L,{k:v for k,v in al.items() if k!='DEX'} or 'even')['DEX'] if 'DEX' in al else a['DEX']
    for tk in TG:
      ts,df,hp=target(tk,L)
      r=dict(op=op,L=L,tgt=tk,DEX=a['DEX'],INT=a['INT'],tHP=round(hp))
      for helm in (1,1.25):
        for h in (1,1.30):
          d=round(sdmg(siege_power(L,a,helm),a,ts,df,h)); r[f'bal_h{helm}_x{h}']=d; r[f'cat_h{helm}_x{h}']=round(d*0.70)
      r['bal_noDEX']=round(sdmg(siege_power(L,a0),a0,ts,df))
      bap=w*(1+a['STR']/200); r['basic']=round(dmg(w,a,ts,df))
      nm,m=SK[key]; sp=bap*m*pot+(a['INT']/2 if key=='Hyb' else 0)
      r['skill_name']=nm; r['skill']=round(dmg(sp,a,ts,df,str_scale=False))
      out.append(r)
json.dump(out,open(r'D:\\AI\\Projects\\CTRBLXAI\\sim\\siege_review_2026-10-30\\v2'+r'\results_v2.json','w'),indent=1)
