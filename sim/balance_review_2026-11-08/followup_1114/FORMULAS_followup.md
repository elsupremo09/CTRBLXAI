# FORMULAS - follow-up 2026-11-08 7:14 PM rulings (sim\balance_review_2026-11-08\followup_1114)

Inherits N1-N23 from ..\FORMULAS_nov08.md (unchanged, re-used via harness_followup.py). All new rows below were read from CTRBLXAI.db (read-only, 2026-11-08). No Luau read. All match unless noted.

| # | Formula | DB source | DB expression (short) |
|---|---|---|---|
| F1 | Dragon Dive delay split | skills SKL-DRAGON-DIVE.RT_Delay_Formula | landing unit round(WpnDly x1.40); 4 side tiles round(WpnDly x0.70) |
| F2 | Decimating Swing delay split | skills SKL-DECIMATING-SWING.RT_Delay_Formula | main round(WpnDly x1.50); others round(WpnDly x0.75); Channel 100; 2H |
| F3 | Blood Price | skills SKL-BLOOD-PRICE | range Fixed 1, no Bonus Skill Range; Power WAP x1.40 x Potency (Potency still in formula); RT x0.80; 0 MP; 15% max HP |
| F4 | Area add-ons rule | project_rules 252 (7:14 PM extension) | augment add-ons apply to every unit an area skill damages, allies included |
| F5 | Pinning Support | augments AUG-PINNING-SUPPORT; elements_statuses 66 | Pinned "1 turn" (augment) / 1000 CT (status), refresh; MP x1.25 |
| F6 | Delay Strike | augments AUG-DELAY-STRIKE | +20% of target's CT for next turn; max 1 per target per round from this augment; MP x1.35 |
| F7 | Sluggish Blow / Slow | augments AUG-SLUGGISH-BLOW; elements_statuses 71 | Slow 1 turn: Modified Base RT x1.10; MP x1.25 |
| F8 | Interrupt | augments AUG-INTERRUPT | cancels a channel in progress; MP x1.40 |
| F9 | Vitality Surge | augments AUG-VITALITY-SURGE | heal 5% caster max HP; row says "once per supported resolution" |
| F10 | Lifesteal | augments AUG-LIFESTEAL | heal 10% of actual damage dealt (all targets summed) |
| F11 | Scatter / Vortex Strike | augments AUG-SCATTER-STRIKE / AUG-VORTEX-STRIKE | 1 tile away from / toward area centre, per target hit; valid/unoccupied tiles only; no chain displacement |
| F12 | Silencing / Disarming / Crippling Support | augments + elements_statuses 62, 65, 67 | Silence 2000 CT (no skills, breaks channels); Disarmed 3000 CT (no Basic Attack); Crippled 5 turns; MP x1.25 / x1.20 / x1.20 |
| F13 | Augment cost stacking / slots | frameworks 72, 26 | % multipliers multiply; 2 slots (slot 2 at unit L80+ and Training Grounds L10) |
| F14 | MP Regen | core_stats 49 | 2 + floor(INT/40) MP per 1000 CT |
| F15 | Round | map_gen_rules 72 | 1000 CT |
| F16 | Area skill rows | skills: Thunderclap, Tidal Crash, Meteor Marker, Venom Burst, Siphon Pulse, Gale Thrust, Sweeping Cut, Pyroclasm, Chain Spark | RT/MP/channel/power/delay as authored |

Modelling choices (not DB gaps):
- "Speed" = share of normal turns an enemy still gets = 1 - (turn delay received per CT).
- Delay Strike's "20% of CT for next turn" is modelled as 20% of the target's Modified Base RT. The DB doesn't say what the 20% is taken from.
- Casters use STR 60% (or INT 60%) builds; enemies have even stats (DB enemy rule). Both are Humans with median armor.

Missing from DB: nothing that blocks the run. The wording questions are listed in REPORT.md under "Needs a ruling".
