# CTRBLXAI — Action Pricing Simulation ("what is fair")
Date: 2026-09-30 · Run by: Quick (design session) · Status: STARTING DEFINITION, not locked

## Definition of fair
A skill is fair when a team using it does exactly as well as the same team using basic attacks,
in simulated fights. "Worth" and "payment" are both measured in % of one basic attack.

One basic attack's full cost = half the 400 base turn (each of the 2 AP carries 200) + its own wait
(flat 40 + weapon/armor weight). Reference unit (Grunt 5 in the 2026-09-30 log): 200 + 89 = 289 CT = 100%.

## What the simulation models (and doesn't)
- Models: turn timeline (base 400, 2 AP, wait added after actions), damage landing instantly, delayed
  effects landing later and being wasted if the target already died, focus fire and KO-first targeting
  on both sides, random HP 70-130 / damage 15-35 / attack wait 60-140, heals on allies below 50% HP.
- Does NOT model: the grid, movement, elevation, statuses, Guard, AI personalities, interrupts,
  or MP/HP carrying over between battles. Pure math; no Luau code was run.

## Key findings
1. Fight length matters most. In short fights (~3 turns each) big hits look far stronger than their %
   (+50% damage worth 110%), because the wait is paid after the damage lands and the last turn's wait is never
   paid. In long fights (~11 turns each, closer to the 3-vs-17 test battle) it's nearly a straight line.
   Long-fight curve used: worth = 1.1*f + 0.1*f^2  (+10% -> 11%, +25% -> 28%, +50% -> 58%, +100% -> 120%).
2. Delay (channel or cast) on target-locked damage is a WEAK payment in long fights: about 4% per 100 CT
   (+10% damage needs ~280 CT of delay to pay for itself). Channel and cast delay count the same here.
3. Delay on heals costs ~2.5-3x more: about 11% per 100 CT.
4. Healing: in long fights an instant heal on a wounded ally equals one basic attack when it heals about
   0.84x the healer's own attack damage (0.98x in short fights).
5. MP: from the game's own MP-restoring actions (Mana Surge, Meditate, Ether Cell), 1 MP costs about
   25 CT of time for a mid caster (Max MP ~50); 16 for a big pool (80), 44 for a small one (30).
   This is the price when a unit actually runs short and must restore. If MP never runs out, MP is nearly free.
6. Reach: each extra tile of reach saves one tile of walking = 15 CT (~5%).
7. Area: in the test battle a 3x3 centred on an enemy caught 1.94 enemies on average (best spot 3-4);
   players were caught 0.06 on average.
8. Dodging: 41 of 42 enemy turns away from players included a move. A long ground-targeted delay
   (e.g. Meteor 600 CT) will often see targets walk out. The AI has no rule yet for avoiding marked areas.

## Starting price list (% of one basic attack)
Worth (must be paid for): extra damage per curve above · heal per finding 4 · reach 5%/tile ·
area = damage on extra targets actually caught · statuses NOT priced yet.
Payment: extra wait 1% per ~3 CT · MP ~9% each (25 CT) · delay 4%/100 CT (damage) or 11%/100 CT (heals) ·
ground-targeted delays also lose the targets that walk out.

## Sample check (reference unit: weapon+armor weight 49, basic attack wait 89, skill level 10)
| Skill | Gets | Pays (MP=25) | Verdict | Pays (MP=12) | Verdict |
|---|---|---|---|---|---|
| Power Strike | 28% | 25% | about fair | 7% | too cheap |
| Fire Bolt (1-tile weapon) | 27% | 21% | too cheap | 3% | too cheap |
| Sweeping Cut | 12% | 38% | too expensive | 15% | about fair |
| Longshot | 34% | 46% | too expensive | 23% | too cheap |
| Execution Stroke (no finisher) | 46% | 87% | too expensive | 51% | about fair |
| Meteor, no one escapes | 168% | 114% | too cheap | 65% | too cheap |
| Meteor, half escape | 32% | 114% | too expensive | 65% | too expensive |
| Healing Light (Ranger) | 49% | 32% | too cheap | 9% | too cheap |

## Open questions before locking
1. MP price: 25 (you often run short and must restore) vs lower (you rarely run dry). Decides most verdicts.
2. Should enemies step out of marked areas? Decides whether Meteor-style skills are cheap or bad.
3. Status effects need their own price list.
4. Armor weight: whole turn (locked rule) or attacks/skills only (current code)? Changes every wait number.
