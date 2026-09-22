# CTRBLXAI Reference Games — Design Benchmark Catalog

## Purpose

This document catalogs 13 games (6 Roblox, 7 non-Roblox) whose designs most closely overlap with CTRBLXAI. Use it as a "don't reinvent the wheel" reference: when a design question arises, check how these successful games solved the same problem before theorizing from scratch.

**CTRBLXAI's core identity:** Medieval-fantasy tactical SRPG with CT timeline, grid-based combat, elevation, deterministic resolution (no hit/miss RNG), BP budget equipment system, procedural maps, status effects, weapon archetypes with passives, and unit customization via doctrines/augments.

---

## Roblox Reference Games

### 1. Deepwoken — Combat Depth & Equipment Mastery

**Visits:** 1.62 billion+ | **Peak CCU:** 62,422 | **Paid Access:** 150 Robux | **Award:** Best New Experience 2022

Hardcore action-RPG proving that complex, punishing games thrive on Roblox. Features a dual-bar system (Health + Posture), parry-based combat, and permadeath. [[1](https://www.rolimons.com/game/4111023553)]

**Key systems relevant to CTRBLXAI:**
- **Build budget concept:** Attribute/talent system creates meaningful trade-offs — analogous to BP allocation [[2](https://deepwoken.fandom.com/wiki/Combat_Mechanics)]
- **Diminishing returns:** 0.5→0.25 HP scaling beyond 50 Fortitude mirrors CTRBLXAI's stat curve philosophy
- **Equipment as identity:** Weapons define playstyle, not just stats
- **13 races with unique bonuses:** Validates CTRBLXAI's 15-race design [[3](https://roblox.fandom.com/wiki/Vows_by_the_Sea/Deepwoken)]

**When to reference:** Build budget trade-offs, stat curve design, equipment identity, hardcore audience viability on Roblox.

---

### 2. Arcane Odyssey — Build Diversity & Stat System

**Genre:** Open-world action RPG | **11 build archetypes from 4 stats**

Demonstrates how percentage-based stat investment creates distinct identities: 60%+ in one stat = pure build (Mage, Berserker, Warrior, Oracle); 40%+ in two = hybrid (Warlock, Conjurer, Warlord, etc.). [[4](https://roblox-arcane-odyssey.fandom.com/wiki/Stat_Builds)]

**Key systems relevant to CTRBLXAI:**
- **Stat-to-build identity mapping:** Continuous investment creating discrete archetypes — relevant to how BP allocation creates weapon identities
- **Imbuement system:** Combining elements produces emergent effects — parallels CTRBLXAI's status interaction design
- **Awakening locks:** Build commitment at level 120/250 prevents casual respeccing — meaningful choice
- **Enchantment scaling:** Strong (+0.5 power/10 levels), Powerful (+0.875/10 levels) [[5](http://roblox-arcane-odyssey.fandom.com/wiki/Gear_Stats)]

**When to reference:** Stat-to-archetype emergence, element/status interactions, build commitment mechanics, enchantment scaling curves.

---

### 3. Vesteria — Classic MMORPG Progression & Decline Lessons

**Launch:** 2018 (Roblox Incubator) | **Paid Access:** 800 Robux → Free 2021 | **Status:** Declining

Traditional MMORPG with classes (Hunter→Assassin/Ranger/Trickster, Warrior→Paladin/Berserker/Knight, Mage→Cleric/Sorcerer/Warlock), dungeons, trading economy. [[6](https://roblox.fandom.com/wiki/The_Vesteria_Team/Vesteria)]

**Key systems relevant to CTRBLXAI:**
- **Class→Subclass branching at level 30:** Proven progression hook — parallels weapon archetype + passive selection creating "build identity" moments
- **Player-driven trading economy:** Extended the game's life significantly
- **Subclass fantasy:** Players immediately understand Paladin vs. Berserker identity

**Critical warning — why it declined:**
- "With the lack of game content such as maps and weapons and a hella long RNG-based grind, which means profit is not equal to the effort, this game has dissuaded a lot of people from playing" [[7](https://vesteria.fandom.com/f/p/4400000000000119478)]

**When to reference:** Class identity design (positive), content velocity requirements (positive), RNG-grind pitfalls to avoid (cautionary).

---

### 4. Dungeon Leveling — Party-Based PvE & Class Roles

**Launch:** October 2024 | **Core:** 4-player cooperative dungeon crawling

6 classes (Tank, Warrior, Assassin, Wizard, Ranger, Healer) with forced party coordination. Proves Roblox players engage with team-composition thinking. [[8](https://dungeon-leveling.fandom.com/wiki/Dungeon_Leveling_Wiki)]

**Key systems relevant to CTRBLXAI:**
- **Forced cooperation validates unit-synergy design:** Players will think about team composition
- **Clear role communication:** Tank/Healer/DPS archetypes are instantly understood
- **Session length:** Successful Roblox dungeon games run 10-20 minutes — target for CTRBLXAI encounter length
- **PvE primary, PvP secondary:** Validates CTRBLXAI's design focus

**When to reference:** Party composition design, class role clarity, session length targeting, PvE viability on Roblox.

---

### 5. All Star Tower Defense — Tactical Placement & Meta Progression

**Genre:** Tower defense with tactical unit placement | **Status:** Consistently top Roblox game

Demonstrates how positional strategy and counter-based unit design creates deep theorycrafting communities on Roblox. Players pre-select loadouts and place units strategically to counter specific enemy types. [[9](https://allstartd.fandom.com/wiki/How_To_Play)]

**Key systems relevant to CTRBLXAI:**
- **Unit placement as strategy:** Roblox players enjoy positional thinking — validates grid-based positioning
- **Counter-based design:** Enemy types requiring specific counters mirrors weapon-vs-enemy philosophy
- **Loadout pre-selection:** Choosing which units to bring = pre-battle strategy — analogous to equipment/skill loadout decisions
- **Meta rotation through content additions:** New units/enemies keep strategy fresh without redesigning core systems
- **Accessibility gradient:** Easy→Hard scaling lets players self-select challenge

**When to reference:** Positional strategy engagement, counter/matchup design, loadout pre-selection UX, content rotation keeping meta fresh.

---

### 6. Noobs in Combat — Grid-Based Tactical Combat on Roblox

**Visits:** 219M+ | **Peak CCU:** 4,286 | **Genre:** Turn-based co-op grid tactics | **Developer:** WhyAnon

The closest existing Roblox game to CTRBLXAI's core genre — an actual grid-based, turn-based tactical game where players command military unit platoons on tiled maps. Units range from WW2 to Cold War era. Has a spin-off (Cold Front) with campaign objectives.

**Key systems relevant to CTRBLXAI:**
- **Grid-based terrain matters:** "In Noobs in Combat there are many types of Terrain for each tile. Terrain can reduce or increase damage taken, block sight, and affect the movement of units." — directly validates CTRBLXAI's terrain-affects-combat design
- **Unit perks/passives:** Units have passive properties (stealth = invisible unless adjacent, fuel dependency, armor types) — parallels weapon passives
- **Tech tree progression:** Research tab with tiered unit unlocks (Infantry→Rifle→Flamethrower, Vehicles branch) — proves Roblox players engage with progression trees
- **Map variety with objectives:** Capture villages, hold positions, escort — validates objective-based encounter design
- **Community map creation:** Official Map Template kit allows community contributions — demonstrates sustainable content pipeline
- **Co-op focus:** "Work together with other players to defeat the enemy in many different scenarios" — validates multiplayer PvE tactics on Roblox
- **Combined arms:** Infantry, vehicles (Light Tank, helicopters), support units — different unit categories with distinct roles on the same grid

**Critical insight — proves the genre works on Roblox:**
NiC demonstrates that Roblox players will engage with turn-based grid tactics (219M visits) despite the platform's reputation for action games. The 7-minute average session suggests battles are quick and replayable — relevant to CTRBLXAI's target encounter length.

**When to reference:** Grid terrain implementation on Roblox, turn-based UX patterns for Roblox audience, map design with objectives, unit progression trees, co-op tactical gameplay viability.

---

## Non-Roblox Reference Games

### 7. Final Fantasy Tactics (1997) — The CT System Ancestor

**Platform:** PS1, PSP, iOS/Android, PC (2025 Remaster) | **Sales:** 2.4M+ (PS1 alone)

The direct progenitor of CTRBLXAI's timeline system. Isometric grid combat with elevation, CT (Charge Time) governing turn order, and deep job/ability customization.

**CT system details:** "On each 'tick', each character gains CT equal to their speed. When it reaches 100, they take their turn." [[10](https://steamcommunity.com/app/1004640/discussions/0/595162055800079777/)]

**CT conservation:** "Having one action left over nets you 40 CT back to your bar, having 2 actions left over nets you 60 CT." [[11](https://ffhacktics.com/smf/index.php?topic=7261.0)]

**Key lessons for CTRBLXAI:**
- Speed manipulation is inherently the most powerful mechanic — needs careful BP cost balancing
- Cast times on powerful abilities create counterplay windows (telegraphed vulnerability)
- CT conservation rewards defensive play and creates decision tension
- Primary divergence: FFT uses hit% RNG which CTRBLXAI deliberately removes

**When to reference:** CT/timeline balancing, speed vs. power trade-offs, channeling/cast time design, action economy.

---

### 8. Into the Breach (2018) — Deterministic Combat Gold Standard

**Platform:** PC, Switch, iOS, Android | **Metacritic:** 89/100 | **Sales:** 1M+ copies

The definitive proof that deterministic tactical combat (zero RNG) works commercially. 8×8 grid, 3-unit squads, every attack deals fixed damage, enemies telegraph intent before player acts. [[12](https://www.rockpapershotgun.com/into-the-breach-details-preview)]

**Design philosophy:** "Crucially, Into the Breach is about clever use of positioning rather than simply overpowering the enemy." [[12](https://www.rockpapershotgun.com/into-the-breach-details-preview)]

**Key lessons for CTRBLXAI:**
- When you remove randomness, positioning becomes the primary skill expression — validates elevation mechanics
- Tight power budgets (reactor cores ≈ BP) force meaningful equipment choices
- Telegraphing enemy intent enables planning over reacting
- Every failure is the player's fault — creates satisfying accountability

**When to reference:** Deterministic combat justification, positioning-as-skill design, power budget philosophy, enemy telegraphing.

---

### 9. Tactics Ogre: Reborn (2022) — RT/Weight System & Elevation

**Platform:** PS4/5, Switch, PC | **Metacritic:** 81/100

The closest mechanical analog to CTRBLXAI's timeline-weight relationship. Uses Recovery Time (RT) where heavier equipment = slower turns, creating direct trade-offs between power and speed. [[13](https://www.gematsu.com/2022/08/tactics-ogre-reborn-details-tarot-cards-elements-branching-narrative-battle-system-more)]

**Key systems relevant to CTRBLXAI:**
- **Weight→RT pipeline:** Equipment weight directly affects turn order — validates BP budget affecting timeline position
- **Aggressive elevation:** Height advantage affects damage more aggressively than FFT
- **8-element system:** Fire/Water/Wind/Earth/Dark/Light/Lightning/Ice with strengths/weaknesses — validates status/element team composition
- **Deterministic crafting:** Reborn removed RNG from crafting (100% success rate) — aligns with CTRBLXAI's deterministic philosophy [[14](https://www.rpgsite.net/feature/13476-tactics-ogre-reborn-crafting-guide)]

**When to reference:** Equipment weight→speed trade-offs, elevation impact values, element/status typing, deterministic crafting.

---

### 10. Fell Seal: Arbiter's Mark (2019) — Unit Customization Depth

**Platform:** PC, PS4, Xbox, Switch | **Metacritic:** 82-86/100

The most relevant modern reference for CTRBLXAI's unit customization philosophy. 30+ classes, 300+ abilities, passive slot system, and deep status effects — proving indie SRPGs can succeed commercially with depth-first design. [[15](https://www.gog.com/en/game/fell_seal_arbiters_mark)]

**Key systems relevant to CTRBLXAI:**
- **Class/Sub-class/Passive layering:** Directly parallels weapon archetype + doctrine + augment system
- **Passive slots as primary build diversity axis:** More impactful than equipment alone
- **20+ status effects with clear interactions:** Each has a counter and clear matchup value
- **Counter/reaction abilities:** Conditional triggers (when attacked, when healed) — comparable to weapon passives
- **Commercial validation:** Proves deep customization systems succeed without AAA production values

**When to reference:** Doctrine/augment layering design, passive slot philosophy, status effect depth, indie scope validation.

---

### 11. Unicorn Overlord (2024) — Deterministic Preparation SRPG

**Platform:** PS4/5, Xbox Series, Switch | **Metacritic:** 85/100 | **Sales:** 1M+ (by September 2024)

Validates that deterministic resolution + deep pre-battle customization is commercially viable in 2024. Combat outcomes are entirely predictable based on player-authored unit AI priorities and squad composition. [[16](https://en.wikipedia.org/wiki/Unicorn_Overlord)]

**Design philosophy:** "Unicorn Overlord marks a triumphant return for one type of old-school strategy RPG that prizes preparation and clever tactics over quick decision-making in the midst of combat." [[17](https://www.inverse.com/gaming/unicorn-overlord-interview-vanillaware)]

**Key lessons for CTRBLXAI:**
- When combat is deterministic, the "game" becomes the loadout/composition puzzle — exactly CTRBLXAI's BP budget philosophy
- Passive/conditional ability systems create emergent complexity from simple rules
- Players accepted and praised deterministic approach — market demand exists beyond niche
- 1M+ sales proves the format works in 2024

**When to reference:** Market validation for deterministic combat, preparation-over-execution philosophy, conditional ability design.

---

### 12. Crawl Tactics (2022) — Procedural Tactical Roguelike

**Platform:** PC (Steam), iOS, Android | **Steam Reviews:** Very Positive (91% of 204 reviews)

Combines classic turn-based tactics with roguelike progression and procedurally generated dungeon maps. Party-based SRPG where each run generates new encounters and map layouts. Proves that tactical combat + procedural generation + deep customization can coexist successfully.

**Key systems relevant to CTRBLXAI:**
- **Procedural map generation for tactics:** Each run generates different battle maps — the primary reference for CTRBLXAI's Slice 5 (procedural maps). Proves the concept works without feeling random or unfair
- **Party-based grid tactics:** Manage a squad with class roles, positioning, and ability synergies on procedurally generated terrain
- **Environmental interaction:** "Use the environment to your advantage to conquer the dungeon" — terrain isn't just movement cost, it's an active tactical tool
- **Roguelike progression loop:** Fail, learn, unlock, try again — validates replayability through procedural variety rather than content volume
- **Quest Mode vs. Dungeon Mode:** Authored scenarios + procedural runs coexist — parallels CTRBLXAI having templates AND procedural generation
- **Mobile port success:** Complex tactics game working on mobile proves the UI/UX can be simplified without losing depth — relevant to Roblox's mobile player base

**When to reference:** Procedural map generation for tactical games, roguelike progression integration, environmental tactics, authored + procedural content coexistence, mobile-friendly tactical UX.

---

### 13. The Last Spell (2023) — Horde Defense Tactics & Loot Progression

**Platform:** PC, PS4/5, Switch, Xbox | **Steam Reviews:** Very Positive (83%) | **Metacritic:** ~80/100

Roguelite tactical RPG where heroes defend a bastion against nightly monster hordes on a grid, then rebuild/re-equip by day. 20 weapon types, 12 primary attributes, 18 secondary attributes, 8 perk trees across 5 tiers. Massive equipment variety with procedural loot.

**Key systems relevant to CTRBLXAI:**
- **Weapon-defines-skills model:** "All skills (except for the punch skill) have a limited amount of uses" — weapons grant specific skills rather than characters learning them independently. Each weapon type provides distinct action options — directly parallels CTRBLXAI's "all skills scale with equipped weapon" philosophy
- **Procedural loot with deterministic stats:** Equipment drops with randomized stat bonuses but effects are fully visible and deterministic in combat — no hidden RNG during use
- **Action Points + Move Points:** Separate resource pools for acting and moving — similar to CTRBLXAI's AP system
- **AOE as primary combat tool:** Horde mechanics force AOE prioritization — validates large pattern attacks (Cleave, Line, etc.) as satisfying primary actions
- **Weapon variation tiers:** Rusty→Steel→Silver→Mithril→Adamantium progressions for each weapon type — relevant to CTRBLXAI's item level scaling design
- **Perk trees (5 tiers, 8 trees):** "The Last Spell has 20 different weapons, 12 Primary Attributes, 18 Secondary Attributes, 8 Perk Trees in 5 different Tiers" — validates deep attribute/perk systems without overwhelming players
- **Day/Night cycle loop:** Night = combat, Day = rebuild/equip/upgrade — proves tactical games benefit from a clear preparation→execution rhythm
- **Grid defense with meaningful positioning:** Map layout directly determines survival — height, chokepoints, coverage zones all matter

**When to reference:** Weapon→skill binding design, procedural loot generation, item tier/variation scaling, AOE skill satisfaction, action economy (AP/MP split), preparation-execution loops, perk tree depth.

---

## Quick-Reference Matrix

| Feature | Deepwoken | Arcane Od. | Vesteria | Dungeon Lv. | ASTD | NiC | FFT | ItB | Tactics Ogre | Fell Seal | Unicorn OL | Crawl Tactics | The Last Spell | **CTRBLXAI** |
|---------|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| CT/Timeline | — | — | — | — | — | — | ✅ | — | ✅ | ⚠️ | ⚠️ | — | — | ✅ |
| Deterministic | — | — | — | — | — | — | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ |
| Grid Combat | — | — | — | — | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | — | ✅ | ✅ | ✅ |
| Elevation | — | — | — | — | — | — | ✅ | — | ✅ | ✅ | — | — | ⚠️ | ✅ |
| Equipment Budget | ✅ | ✅ | — | — | — | — | ⚠️ | ✅ | ✅ | ⚠️ | ⚠️ | ⚠️ | ✅ | ✅ |
| Status Effects | — | ✅ | — | — | — | — | ✅ | ⚠️ | ✅ | ✅ | ✅ | ⚠️ | ✅ | ✅ |
| Weapon Passives | ✅ | ✅ | — | — | — | ✅ | ⚠️ | ⚠️ | ⚠️ | ✅ | ✅ | ⚠️ | ✅ | ✅ |
| Procedural Maps | — | — | — | — | — | — | — | ✅ | — | — | — | ✅ | — | ✅ |
| Deep Customization | ✅ | ✅ | ⚠️ | — | — | ⚠️ | ✅ | — | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Weapon→Skill Binding | — | — | — | — | — | — | ⚠️ | — | — | — | — | — | ✅ | ✅ |
| Procedural Loot | — | — | — | — | — | — | — | — | — | — | — | ✅ | ✅ | ✅ |

---

## Design Decision Lookup

When facing a specific design question, consult:

| Design Question | Primary Reference | Secondary |
|---|---|---|
| How to balance speed vs. power? | FFT, Tactics Ogre | Deepwoken |
| Does deterministic combat work? | Into the Breach, Unicorn Overlord | — |
| How should elevation affect combat? | Tactics Ogre, FFT | Fell Seal |
| How to design equipment budgets? | Into the Breach (reactor cores), Deepwoken (attributes) | Tactics Ogre (weight) |
| How deep should customization go? | Fell Seal (30 classes, 300 abilities) | Arcane Odyssey (11 builds) |
| Will complex games work on Roblox? | Deepwoken (1.6B visits, paid access) | Arcane Odyssey |
| How long should battles be? | Dungeon Leveling (10-20 min), NiC (7 min avg) | Into the Breach (5-10 min) |
| How to handle loot/equipment drops? | The Last Spell (procedural + tiers), Vesteria (cautionary) | Deepwoken |
| How to make status effects meaningful? | Fell Seal (20+), Tactics Ogre (elements) | Arcane Odyssey (imbuement) |
| How to keep meta fresh long-term? | ASTD (content rotation), Deepwoken (updates) | Vesteria (cautionary) |
| How to communicate unit roles clearly? | Dungeon Leveling (Tank/Healer/DPS) | Fell Seal (class fantasy) |
| How to design weapon archetypes? | Deepwoken (playstyle identity) | Unicorn Overlord (conditional passives) |
| Procedural map generation? | Crawl Tactics (full procedural dungeons) | Into the Breach (semi-random, small) |
| Grid tactics UX on Roblox? | Noobs in Combat (219M visits, 7 min sessions) | — |
| Weapon→skill binding? | The Last Spell (weapon grants skills) | — |
| Item level scaling / tiers? | The Last Spell (Rusty→Adamantium) | Arcane Odyssey (enchant scaling) |
| Authored + procedural content mix? | Crawl Tactics (Quest Mode + Dungeon Mode) | — |

---

## CTRBLXAI's Unique Position

No single reference game combines ALL of CTRBLXAI's systems. The synthesis is genuinely novel:
- FFT has the timeline but uses hit% RNG
- Into the Breach is deterministic but lacks timeline and elevation
- Tactics Ogre has timeline + elevation but uses RNG
- Fell Seal has deep customization but simpler initiative
- Unicorn Overlord is deterministic but not grid-based turn-by-turn
- Crawl Tactics has procedural maps + tactics but no CT timeline or elevation
- The Last Spell has weapon→skill binding + procedural loot but is horde-defense, not positional SRPG
- Noobs in Combat proves grid tactics works on Roblox but lacks RPG depth (no equipment/stats/customization)

CTRBLXAI occupies an unserved niche with proven adjacent demand.

## References

\[1\] <a href="https://www.rolimons.com/game/4111023553">https://www.rolimons.com/game/4111023553</a>

\[2\] <a href="https://deepwoken.fandom.com/wiki/Combat_Mechanics">https://deepwoken.fandom.com/wiki/Combat_Mechanics</a>

\[3\] <a href="https://roblox.fandom.com/wiki/Vows_by_the_Sea/Deepwoken">https://roblox.fandom.com/wiki/Vows_by_the_Sea/Deepwoken</a>

\[4\] <a href="https://roblox-arcane-odyssey.fandom.com/wiki/Stat_Builds">https://roblox-arcane-odyssey.fandom.com/wiki/Stat_Builds</a>

\[5\] <a href="http://roblox-arcane-odyssey.fandom.com/wiki/Gear_Stats">http://roblox-arcane-odyssey.fandom.com/wiki/Gear_Stats</a>

\[6\] <a href="https://roblox.fandom.com/wiki/The_Vesteria_Team/Vesteria">https://roblox.fandom.com/wiki/The_Vesteria_Team/Vesteria</a>

\[7\] <a href="https://vesteria.fandom.com/f/p/4400000000000119478">https://vesteria.fandom.com/f/p/4400000000000119478</a>

\[8\] <a href="https://dungeon-leveling.fandom.com/wiki/Dungeon_Leveling_Wiki">https://dungeon-leveling.fandom.com/wiki/Dungeon_Leveling_Wiki</a>

\[9\] <a href="https://allstartd.fandom.com/wiki/How_To_Play">https://allstartd.fandom.com/wiki/How_To_Play</a>

\[10\] <a href="https://steamcommunity.com/app/1004640/discussions/0/595162055800079777/">https://steamcommunity.com/app/1004640/discussions/0/595162055800079777/</a>

\[11\] <a href="https://ffhacktics.com/smf/index.php?topic=7261.0">https://ffhacktics.com/smf/index.php?topic=7261.0</a>

\[12\] <a href="https://www.rockpapershotgun.com/into-the-breach-details-preview">https://www.rockpapershotgun.com/into-the-breach-details-preview</a>

\[13\] <a href="https://www.gematsu.com/2022/08/tactics-ogre-reborn-details-tarot-cards-elements-branching-narrative-battle-system-more">https://www.gematsu.com/2022/08/tactics-ogre-reborn-details-tarot-cards-elements-branching-narrative-battle-system-more</a>

\[14\] <a href="https://www.rpgsite.net/feature/13476-tactics-ogre-reborn-crafting-guide">https://www.rpgsite.net/feature/13476-tactics-ogre-reborn-crafting-guide</a>

\[15\] <a href="https://www.gog.com/en/game/fell_seal_arbiters_mark">https://www.gog.com/en/game/fell_seal_arbiters_mark</a>

\[16\] <a href="https://en.wikipedia.org/wiki/Unicorn_Overlord">https://en.wikipedia.org/wiki/Unicorn_Overlord</a>

\[17\] <a href="https://www.inverse.com/gaming/unicorn-overlord-interview-vanillaware">https://www.inverse.com/gaming/unicorn-overlord-interview-vanillaware</a>
