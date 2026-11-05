# Siege v2 verification — 2026-10-30 (deterministic, no RNG; seed n/a)
Model: approved 18:20 rule (brief = authoritative). Script: siege_review_v2.py, data: results_v2.json.
Ops: Orc+Sword STR, Feline+Longbow DEX, Elf+Wand, Elf+Bell, Human+Sword STR/DEX/INT hybrid (Arcane Strike). Targets: Feline light / Human medium / Dwarf heavy, even stats, same level.
Caster skill: Fire Bolt = Weapon Attack Power x1.10 x Skill Potency (skills.Power_Formula). Weapon Attack Power taken = Basic Attack Power (core_stats 31) — DB never defines the term explicitly (gap).

V1 vs medium, plain shot: non-DEX 27-35% (L1 35, L10-99 27-32) PASS. DEX 32->49% at L99 PASS. Worst case (Helm+height): non-DEX 48-62% (L1 60-62%, over ~50 target); DEX L99 83% PASS.
V2 one-shots (all Helm x1.25 + height x1.30, light target only): DEX L50 (260/248), L75 (370/330), L99 (476/406); Hybrid L75 (338/330), L99 (437/406). None without Helm+height.
V3 casters: DB formula confirmed — Wand basic 2-6, Fire Bolt 2-14; Bell 0-1. Siege = 10-20x Wand Fire Bolt, ~100x+ Bell. Siege is the obvious every-turn caster pick. STR siege ~2.3x basic/skill at L99 medium; DEX ~12x basic, 16x Crippling Shot; Hybrid ~4x basic, 1.5x Arcane Strike.
V4 Catapult = 0.70x Ballista per target: 1 target Ballista wins; 2 targets Cat 1.4x; 3 targets 2.1x (vs Ballista hitting 1, or equal if Ballista line catches same count).
V5 DEX premium (medium): +0 L1, +3pts L10, +6 L20, +8 L30, +11 L50, +13 L75, +15 L99 (49 vs 34%). Non-DEX below 20%: heavy target at L99 (STR 14%, casters 16%); medium never below 27%.
