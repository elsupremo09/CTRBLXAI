# -*- coding: utf-8 -*-
# CTRBLXAI Terrain Fire-Reaction + Element Interactions — FULL migration A–I (2026-10-21 RETRY)
import sqlite3, os, shutil, datetime, json, openpyxl
DOCS=r"D:\AI\Projects\CTRBLXAI\docs"
DB=os.path.join(DOCS,"CTRBLXAI.db")
XLSX=os.path.join(DOCS,"CTRBLXAI_Game_Rules.xlsx")
BK=os.path.join(DOCS,"backups")
stamp=datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
os.makedirs(BK,exist_ok=True)
AR="\u2192"   # →
GE="\u2265"   # ≥

# ---- fresh backups ----
bkdb=os.path.join(BK,f"CTRBLXAI_pre_terrainfire_{stamp}.db")
s=sqlite3.connect(DB); d=sqlite3.connect(bkdb); s.backup(d); d.close(); s.close()
bkx=os.path.join(BK,f"CTRBLXAI_Game_Rules_pre_terrainfire_{stamp}.xlsx")
shutil.copy2(XLSX,bkx)
# verify backup integrity
v=sqlite3.connect(bkdb); assert v.execute("PRAGMA integrity_check").fetchone()[0]=="ok"; v.close()

conn=sqlite3.connect(DB,timeout=30); c=conn.cursor()
conn.execute("BEGIN IMMEDIATE")
log=[]

def t_get(name,col):
    return c.execute(f"SELECT {col} FROM terrain_effects WHERE TERRAIN_CATALOG=?",(name,)).fetchone()[0]
def t_set(name,col,val):
    old=t_get(name,col)
    c.execute(f"UPDATE terrain_effects SET {col}=? WHERE TERRAIN_CATALOG=?",(val,name))
    log.append(("terrain_effects",name,col,old,val))

# =====================================================================
# B. HOLY RESTORE LADDER + C. EARTH Rocky->Cracked + Tainted naming fix
#    (base terrain Transformations = col_7)
# =====================================================================
# Rocky: keep explosion rule, add Holy->Clear and Earth->Cracked Ground
t_set("Rocky","col_7", f"Explosion @ Elevation {GE}8 {AR} Cracked Ground; Holy {AR} Clear; Earth {AR} Cracked Ground")
# Clear: Holy -> Grassland
t_set("Clear","col_7", f"Holy {AR} Grassland")
# Grassland: keep Fire/Dark, add Holy->Clover Field
t_set("Grassland","col_7", f"Fire {AR} Sand; Dark {AR} Tainted; Holy {AR} Clover Field")
# Sand: keep Fire->Molten, add Holy->Grassland
t_set("Sand","col_7", f"Fire {AR} Molten; Holy {AR} Grassland")
# Swamp: keep Fire->Rocky, add Holy->Grassland
t_set("Swamp","col_7", f"Fire {AR} Rocky; Holy {AR} Grassland")
# Tainted Ground: correct stale 'Light' -> 'Holy'
t_set("Tainted Ground","col_7", f"Holy {AR} Grassland")

# =====================================================================
# F. WIND — Shallow Water -> Wind -> Mud (append to existing col_7)
# =====================================================================
sw=t_get("Shallow Water","col_7")
t_set("Shallow Water","col_7", sw + f"; Wind {AR} Mud")

# =====================================================================
# C. EARTH smother kit + D. HOLY purify kit + E. DARK corrupt kit
#    (tile-effect Element Reactions = col_8)
# =====================================================================
def e_append(name, add):
    old=t_get(name,"col_8")
    base = "" if (old is None or old=="\u2014") else old
    new = (base + "; " + add) if base else add
    c.execute("UPDATE terrain_effects SET col_8=? WHERE TERRAIN_CATALOG=?",(new,name))
    log.append(("terrain_effects",name,"col_8",old,new))

# C Earth smother: Burning/Oily/Tar Pit + Earth -> Clear
e_append("Burning", f"Earth {AR} Clear (smother)")
# Oily: Earth smother + Holy purify
e_append("Oily", f"Earth {AR} Clear (smother); Holy {AR} Clear (purify)")
# Tar Pit: Earth smother + Holy purify
e_append("Tar Pit", f"Earth {AR} Clear (smother); Holy {AR} Clear (purify)")
# D Holy purify: Poison Cloud + Holy -> Clear
e_append("Poison Cloud", f"Holy {AR} Clear (purify)")
# E Dark corrupt: Wet + Dark -> Tar Pit ; Steam + Dark -> Poison Cloud
e_append("Wet", f"Dark {AR} Tar Pit")
e_append("Steam", f"Dark {AR} Poison Cloud")

conn.commit(); conn.close()
json.dump({"stamp":stamp,"backup_db":bkdb,"backup_xlsx":bkx,"terrain_edits":log},
          open(os.path.join(BK,f"terrainfire_{stamp}_part1.json"),"w",encoding="utf-8"),
          ensure_ascii=False, indent=1)
print("PART 1 (terrain_effects B/C/D/E/F) committed.")
print("Backup DB :", bkdb)
print("Backup XLS:", bkx)
print("terrain edits:", len(log))
for row in log:
    print("  ", row[1], row[2])
