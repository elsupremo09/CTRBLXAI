# CTRBLXAI Terrain Fire-Reaction + Element Interactions migration (Designer, 2026-10-21)
# Authors LOCKED + DEFAULT design decisions A-I into CTRBLXAI.db, then regenerates the
# affected Game_Rules.xlsx sheets. Run on the device (byte-safe). Idempotent-guarded where easy.
# DB = single source of truth. Element naming = Holy (not Light). 'Nature' is NOT a tag.
import sqlite3, os, shutil, datetime, openpyxl
DOCS=r"D:\AI\Projects\CTRBLXAI\docs"; DB=os.path.join(DOCS,"CTRBLXAI.db")
XLSX=os.path.join(DOCS,"CTRBLXAI_Game_Rules.xlsx"); BK=os.path.join(DOCS,"backups")
stamp=datetime.datetime.now().strftime("%Y%m%d_%H%M%S"); os.makedirs(BK,exist_ok=True)
# fresh backups at run time
bkdb=os.path.join(BK,f"CTRBLXAI_pre_terrainfire_{stamp}.db")
s=sqlite3.connect(DB); d=sqlite3.connect(bkdb); s.backup(d); d.close(); s.close()
shutil.copy2(XLSX, os.path.join(BK,f"CTRBLXAI_Game_Rules_pre_terrainfire_{stamp}.xlsx"))
conn=sqlite3.connect(DB, timeout=30); c=conn.cursor(); conn.execute("BEGIN IMMEDIATE")

def t_set(name,col,val):
    rid=c.execute("SELECT rowid FROM terrain_effects WHERE TERRAIN_CATALOG=?",(name,)).fetchone()[0]
    c.execute(f"UPDATE terrain_effects SET {col}=? WHERE rowid=?",(val,rid))

# ---- B Holy restore ladder + C Earth Rocky + Tainted naming (base-terrain col_7) ----
t_set("Rocky","col_7","Explosion @ Elevation \u22658 \u2192 Cracked Ground; Holy \u2192 Clear; Earth \u2192 Cracked Ground")
t_set("Clear","col_7","Holy \u2192 Grassland")
t_set("Grassland","col_7","Fire \u2192 Sand; Dark \u2192 Tainted; Holy \u2192 Clover Field")
t_set("Sand","col_7","Fire \u2192 Molten; Holy \u2192 Grassland")
t_set("Swamp","col_7","Fire \u2192 Rocky; Holy \u2192 Grassland")
t_set("Tainted Ground","col_7","Holy \u2192 Grassland")
# F Wind: Shallow Water -> Mud (append to existing 'Ice Tag -> Ice Terrain; Earth -> Mud')
t_set("Shallow Water","col_7","Ice Tag \u2192 Ice Terrain; Earth \u2192 Mud; Wind \u2192 Mud")

# ---- Tile-effect element reactions (col_8) ----
# C Earth smother kit: Burning/Oily/Tar Pit + Earth -> Clear (append)
def t_append8(name, add):
    rid=c.execute("SELECT rowid FROM terrain_effects WHERE TERRAIN_CATALOG=?",(name,)).fetchone()[0]
    cur=c.execute("SELECT col_8 FROM terrain_effects WHERE rowid=?",(rid,)).fetchone()[0]
    if add not in (cur or ""):
        c.execute("UPDATE terrain_effects SET col_8=? WHERE rowid=?",((cur+"; "+add) if cur and cur!="\u2014" else add, rid))
t_append8("Burning","Earth \u2192 Clear (smother)")
t_append8("Oily","Earth \u2192 Clear (smother); Holy \u2192 Clear (purify)")
t_append8("Tar Pit","Earth \u2192 Clear (smother); Holy \u2192 Clear (purify)")
# D Holy purify kit: Poison Cloud + Holy -> Clear
t_append8("Poison Cloud","Holy \u2192 Clear (purify)")
# E Dark corrupt kit: Wet + Dark -> Tar Pit ; Steam + Dark -> Poison Cloud
t_append8("Wet","Dark \u2192 Tar Pit")
t_append8("Steam","Dark \u2192 Poison Cloud")

conn.commit(); conn.close()
print("DB edits committed. Backup:", bkdb)
