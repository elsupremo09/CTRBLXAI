# Boss options follow-up — 2026-11-01
Seed 20261101 (expected-value model, plus an exact per-day calculation for the boss cap). Same model, assumptions and DB as report.md. The DB is read-only and its md5 is unchanged (7ea3fde2…). The baseline reproduces exactly: 18.4–21.2 levellings and 248–286 crystals at 80 contracts.
Files: boss_options_sim.py, results_options.json and this file. source\ and docs\ were not touched.

**Modelled as fixed:**
- Salvager's Cap: no salvage from conjured or placed objects. The salvage term is 0.
- Elite: exactly 0.034 per normal-quest battle, paid on a win.
- Escape: ignored.

**Assumptions used here:**
- **Win rate:** 90%.
- **Boss unlock:** boss cards appear from battle 81 (Quest Board L8), on an 11-card board.
- **Daily cap:** counts boss **wins**, so a lost boss can be retried that day.
- **Re-rolls (B1–B5):** a boss hunter always finds a boss card, because today the board re-rolls on every return to base (game_flow 21, Dev-confirmed). Under B6 a hunter gets one board per completed battle.

## Results
Levellings at 75–100% dismantling, by daily mercury **5 / 4 / 3**. Crystals and boss wins don't depend on daily mercury. ✅ = the random picker stays inside 15–20 at 80 contracts with daily 3.

| Option | Player | Levellings, 30 contracts | Levellings, 80 contracts | Levellings, 180 contracts | Crystals 30 / 80 / 180 | Boss wins 30 / 80 / 180 |
|---|---|---|---|---|---|---|
| B1 | Random | 17.8–20.9 / 17.5–20.6 / 17.2–20.3 | 20.5–23.6 / 19.7–22.8 / 18.8–22.0 | 25.6–28.7 / 23.8–26.9 / 21.9–25.1 | 399–450 / 411–462 / 411–463 | 40 / 42 / 42 |
| B1 | Hunter | 21.4–25.3 / 21.1–25.0 / 20.8–24.7 | 35.2–41.3 / 34.4–40.5 / 33.5–39.7 | 54.5–63.6 / 52.7–61.7 / 50.9–59.9 | 703–778 / 1637–1785 / 2826–3067 | 88 / 234 / 419 |
| B2 | Random | 16.4–19.3 / 16.1–19.0 / 15.8–18.7 | 19.8–22.9 / 19.0–22.0 / 18.2–21.2 | 25.3–28.4 / 23.5–26.6 / 21.7–24.8 | 286–328 / 357–404 / 390–440 | 23 / 34 / 39 |
| B2 | Hunter | 16.9–19.9 / 16.6–19.6 / 16.3–19.3 | 23.2–26.9 / 22.4–26.1 / 21.6–25.3 | 35.8–41.0 / 33.9–39.1 / 32.1–37.3 | 330–375 / 641–711 / 1259–1378 | 29 / 78 / 175 |
| B3 | Random | 17.8–20.9 / 17.5–20.6 / 17.2–20.3 | 20.5–23.6 / 19.7–22.8 / 18.8–22.0 | 25.6–28.7 / 23.8–26.9 / 21.9–25.1 | 279–330 / 285–337 / 285–337 | 40 / 42 / 42 |
| B3 | Hunter | 21.4–25.3 / 21.1–25.0 / 20.8–24.7 | 35.2–41.3 / 34.4–40.5 / 33.5–39.7 | 54.5–63.6 / 52.7–61.7 / 50.9–59.9 | 441–515 / 936–1084 / 1568–1808 | 88 / 234 / 419 |
| B4 | Random | 15.8–18.5 / 15.4–18.2 / 15.1–17.9 | 18.3–21.0 / 17.5–20.2 / 16.7–19.4 ✅ | 23.4–26.1 / 21.6–24.3 / 19.7–22.4 | 226–264 / 226–264 / 226–264 | 13 / 13 / 13 |
| B4 | Hunter | 21.4–25.3 / 21.1–25.0 / 20.8–24.7 | 35.2–41.3 / 34.4–40.5 / 33.5–39.7 | 54.5–63.6 / 52.7–61.7 / 50.9–59.9 | 703–778 / 1637–1785 / 2826–3067 | 88 / 234 / 419 |
| B5 | Random | 15.7–18.4 / 15.4–18.1 / 15.1–17.8 | 18.3–21.0 / 17.5–20.2 / 16.6–19.4 ✅ | 23.4–26.1 / 21.6–24.3 / 19.7–22.4 | 215–253 / 222–260 / 224–262 | 10 / 12 / 12 |
| B5 | Hunter | 16.9–19.9 / 16.6–19.6 / 16.3–19.3 | 23.2–26.9 / 22.4–26.1 / 21.6–25.3 | 35.8–41.0 / 33.9–39.1 / 32.1–37.3 | 330–375 / 641–711 / 1259–1378 | 29 / 78 / 175 |
| B6 | Random | 17.8–20.9 / 17.5–20.6 / 17.2–20.3 | 20.5–23.6 / 19.7–22.8 / 18.8–22.0 | 25.6–28.7 / 23.8–26.9 / 21.9–25.1 | 399–450 / 411–462 / 411–463 | 40 / 42 / 42 |
| B6 | Hunter | 21.4–25.3 / 21.1–25.0 / 20.8–24.7 | 34.0–39.9 / 33.2–39.1 / 32.4–38.3 | 44.4–51.4 / 42.6–49.6 / 40.8–47.7 | 703–778 / 1540–1680 / 1984–2159 | 88 / 218 / 288 |

Target: 15–20 levellings, and 248–286 crystals.

- **What controls the random picker:** the boss card weight (B4/B5), not the cap. Under B1, B2, B3 and B6, daily 3 still gives over 20 at 80 contracts.
- **What controls the hunter:** the daily cap. Card weight barely matters, because re-rolls always find a boss. B6 only helps when the cap doesn't bind, which is mostly at 180 contracts.
- **What nothing tested fixes:** no option brings the hunter near 286 crystals. A daily cap pays per day played, so the hunter's income grows with contracts. Under B5 it goes from 330 to 1,378 crystals between 30 and 180 contracts.

## Decision — boss income
**Recommended: B5 (1 boss reward a day, boss card weight 3) + daily mercury 3.**
- **Random picker at 80 contracts:** 16.6–19.4 levellings (inside 15–20) and 222–260 crystals.
- **Hunter at 80 contracts:** 641–711 crystals and 21.6–25.3 levellings. This is the closest any listed option gets: B1, B4 and B6 sit at about 1,500–1,800, and B3 at about 940–1,080.

What it costs the player:
- **Fewer boss cards:** they drop from 1 in 10 to 1 in 33. A random picker wins about 12 bosses a lifetime instead of about 42.
- **Fewer boss rewards:** only 1 a day instead of 3. A hunter gets about 78 rewarded bosses instead of about 234.
- **Smaller daily contract:** it drops from 5 to 3 mercury, which is −160 mercury (−1.6 levellings) at 80 contracts.
- **Random picker's crystals fall below target:** 222–260, about 26 crystals under 248–286. The accepted crystal shortage gets slightly worse.
- **The hunter stays well above target:** 2.2–2.5× the crystals and up to 25 levellings at 80 contracts. At 180 contracts that grows to 1,259–1,378 crystals and 32–37 levellings (daily 3).

Alternatives:
1. **B5 + B3 (2 crystals) + daily 3:**
   - Hunter: 407–477 crystals at 80 contracts (closest to target).
   - Random picker: 186–224, about 62 under 248. Levellings are unchanged (16.6–19.4).
   - Choose this if you care most about the hunter's crystals.
2. **B5 + B6 + daily 3:**
   - Hunter: 556–619 crystals and 20.6–24.1 levellings. The random picker is the same as the recommended option.
   - It needs the Dev to keep the board until a battle is completed. Adding B3 as well brings the hunter to 362–426.
3. **B4 + daily 3 (keep 3 boss rewards a day):**
   - Random picker: the same as the recommended option (16.7–19.4 levellings, 226–264 crystals).
   - Hunter: 1637–1785 crystals and 33.5–39.7 levellings.
   - Choose this only if you are willing to accept boss-hunting as a main path.

Not tested: a cap below 1 a day (for example per week) is the only lever that would bring the hunter to target at every contract count.

Files modified: sim\ only. Source and docs untouched.
