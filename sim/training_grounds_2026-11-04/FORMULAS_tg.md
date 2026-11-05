# FORMULAS — Training Grounds check 2026-11-04 (addendum; base registry sim\FORMULAS.md + apothecary/crucible addenda)
| Formula | Source | Expression | Python | Match |
|---|---|---|---|---|
| Facility cost | guild_facilities 2, 20, 32 | round(Base × (1 + L²/Scale)), TG Base 220 Scale 16 = 7,495g | FAC['Training Ground'] from row 32, asserted | yes |
| Library removed | guild_facilities 22, 33 (6,277g) | proposal C1 | FAC10 = FAC minus Library, total asserted 70,927 | yes |
| Level multiplier | economy_framework 13 | 1 + (L − 1) × 0.02 | lvl_mult(L) | yes |
| Rarity multiplier | economy_framework 12 | Rare 2.5, Epic 4.0, Legendary 7.0 | RM, asserted | yes |
| Card buy price | PROPOSAL C4 (not in DB) | floor(value × rarity × level mult × (100 − 3(TG−1))/100); value aug 60 / skill 100 / doctrine 1,000 flat | buy_price_c | 35/35 C4 cells |
| Card sell | PROPOSAL C5 (not in DB) | floor(list / 16) | sell_c | – |
| Shelf / odds / unlocks | PROPOSAL C2 (not in DB) | table C2 | SHELF, ODDS, pool() | – |
| Kill XP | unit_progression 30, 32, 33 | Base × (1 + Enemy L / 50) | kill_xp | yes |
| Level curve | unit_progression 86 | 500 + 20 × L | xp_to_next | yes (547 battles to 99) |
| Benched share | unit_progression 52 | 65% | share 0.65 | yes |
| Underlevel mult | unit_progression 60-62 | ×1.25 at gap ≤ −5, ×1.50 at gap ≤ −10 | under_mult | yes |
| Loot card rate | NOT IN DB (Designer, from code) | 0.22 skill + 0.22 augment per battle | LOOT_SK/LOOT_AG | stated input |
