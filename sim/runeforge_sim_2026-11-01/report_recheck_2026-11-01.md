# SIMULATION RE-CHECK — 2026-11-01 — Runeforge + Blacksmith after the Simulator fixes (design only, nothing built)
Seed: 20261101 (deterministic; the only random draws are the seeded action sequences in X4)
Formulas loaded: 40 (first run) + 16 new rule-text checks on the changed rows (provenance: FORMULAS_addendum_recheck.md)
Cases run: 1,208,064 upgrade→dismantle · 953,568 enchant→dismantle · 331,968 move-then-dismantle · 25,872 catch-up per-level · 62,720 whole-number level costs · 24,000 Add/Reroll action steps · 25 facility runs
Level bands: item level 1-99 (Runeforge / Blacksmith content tops out at 99)
Files modified: sim\runeforge_sim_2026-11-01\ only (new files). First-run files untouched. source\ and docs\ untouched.

## SECTION 1: BLOCKERS
None. Drop rate (~0.40/battle) and elite rate (~0.034/battle) are WORKING ESTIMATES (loot_progression 24/26/69). Sensitivity is shown below.

## SECTION 2: PASS/FAIL
| # | Check | Expected | Measured | Result |
|---|---|---|---|---|
| 1 | X1 Uncommon Gloves/Feet L61-99 + one T1 Add (→Rare) → dismantle | no +1, gold loss | +1 earned 0 of 7,920 fresh cases. Best result −37g (only the Add gold is lost) | PASS |
| 1 | X1 all slots/levels, upgraded or fresh, any start→Uncommon/Rare/Epic | ≤0 | 953,568 cases, 0 profitable, best −11g | PASS |
| 2 | X2 Common Gloves L1→61 at BS L10, dismantle | 9/10/10/0 back, clear loss | 9 T1 / 10 T2 / 10 T3 / 0 T4. Paid 1,455g plus materials worth 1,295g; got back 595g. Net **−2,155g** | PASS |
| 2 | The 6 setups that made gold before | lose | Gloves/Feet L1→61/62/63: was +250/+112/+74g, now −2,155 to −2,331g | PASS |
| 2 | Epic L1→80 | ≤50% of T4 spent (was 119) | 60 T4 spent → 30 refunded (50%), +1 Rare-start bonus = 31 (51.7%) | PASS (only the designed +1 goes past 50%) |
| 2 | No T5 ever comes back | 0 | 0 of 1,208,064 cases | PASS |
| 2 | T5 part comes back as T4 | yes | Common 1H L80→99: 19 T5 spent → 9 T4 | PASS |
| 2 | Upgrade→dismantle→sell, all 8 slots × all 8 rarities × every level span × every BS level | ≤0 | 0 profitable, best −16g | PASS |
| 3 | X3 catch-up fee, Common→Epic L1-99 | 22,201 / 33,299 / 17,763 | 22,201 / 33,299 / 17,763 (+196 materials) | PASS |
| 3 | Upgrade as Common then enchant = enchant first | saves 0 | saving 0 in all 8 slots (1H 29,548g both ways). Per level: 25,872 cases, 0 savings. Downgrade-below-start trick: best −31g | PASS |
| 4 | X4 Add list fixed: rejoin / Remove+Add / reroll / upgrade | unchanged | 0 changes in 400 items × each action. 24,000 random action steps: the list always equals a fresh item with the same ID and the same lines | PASS |
| 4 | Higher Runeforge level only adds choices | prefix | 0 violations (3/3/4/4/4/5/5/6/6/full) | PASS |
| 4 | Reroll count rises when the old line is kept; each line has its own options | yes | options changed after 400/400 kept rerolls; 0 of 287 line pairs shared a list | PASS |
| 4 | No attribute-fishing route | none | No free action changes any list. See note A for a paid, non-random route | PASS |
| 5 | Epic fee half-gold cases | 158, round down | 158 found, all rounded down, 0 in 1H/2H, Off-Hand Rare L2 = 428g. 1H/2H table unchanged | PASS |
| 5 | Whole-number maths | 13,279 / 53,233 / 3,018 | 13,279 / 53,233 / 3,018 exact. Whole-number version = exact maths on all 62,720 level costs; floating point is off by 1g on 98 | PASS (note B) |
| 6 | Upgrade→dismantle→sell, enchant→dismantle→sell | ≤0 | best −16g / −11g | PASS |
| 6 | Enchant→sell | −22 (1H) / −34 (2H) | −22 / −34 (other slots −11 to −18) | PASS |
| 6 | Material wall | 12 items, no dismantling | breaks at 12 (13 with 3:1 conversion). With per-tier dismantling: 12-15 (14-16 with conversion). First run's 17 (X1) is gone | PASS |
| 6 | Essence drop share | ~25% | 25.0% | PASS (sensitive, note C) |
| 6 | Crafted Epics L50-80 | rusher 8 vs ~4, boosted 9-14, normal 0 | rusher 8.3 vs 4.0 natural · boosted 9.1-14.2 · classic/crafter free 0 | PASS |
| 6 | Free 8/10; boosted 10/10, 35.0-37.6k left | same | free classic/crafter 8/10 (rush 7/10, as in the first run) · boosted 10/10 with 34,978-37,598g | PASS |
| 6 | Spending pressure | ~106% / ~84% | 105.9-106.6% / 83.1-84.3% | PASS |
| 6 | Facility total | 70,927g | 70,927g (Workshop table now 177/211/484) | PASS |
| 7 | Change the +1 tier by downgrading/upgrading a Rare-start item first | no gain | Downgrade first: best gain 0g (never better). Upgrade first: best −54g | PASS |

Notes
- A. Paid "walking" (not fishing). Adding a throwaway T1 line pushes one more attribute onto the Add list. Removing it afterwards brings back the original list. This reaches 1-2 positions past the shown count (RF L1: 4th choice; RF L8: 8th). Each extra position costs 1.5× the T1 Add gold (1H L50 RF L1: 135g) plus 1 Uncommon Essence that is not refunded. Nothing is re-drawn, so this is the rule working as written. It only holds if an item's ID never changes and the order is worked out on the server.
- B. With the new catch-up rule, 3,018 is the 0%-discount cost difference. The real fee for 1H Uncommon→Rare L1→50 is now 2,786g.
- C. Essence drop share by drops per battle (elite 0.017 / 0.034 / 0.068 per battle): 0.2 → 37-45% · 0.4 → 23-29% · 0.8 → 13-17% · 1.0 → 11-14%. The 25% target holds only near 0.40 drops per battle. Crafted Epics barely move with the drop rate (they are limited by gold), but natural Epics do: 2.0 / 4.0 / 7.9 at 0.2 / 0.4 / 0.8 drops. At 0.8 drops a free rusher's crafted Epics (8.3) only roughly equal the natural ones.

## SECTION 3: EXPLOITS
No gold exploit found. Every enchant/upgrade/move → dismantle/sell route loses gold in every case tested.

One new MATERIAL lever, not a gold exploit (the T5 part refunded as T4):
- Route: take any non-shop item. Downgrade it to L80 for free (its starting level becomes 80). Upgrade it L80→99, then dismantle at BS L10.
- Common Gloves: 19 T5 + 947g → 9 T4 (105g per T4). Rare Gloves: 38 T5 + 2,384g → 19 T4 (125g per T4).
- Gold-wise it always loses: you give up 4,797-9,984g of sell value per item.
- Before this, T5 could not become T4 (conversion only goes up). Now surplus T5 can. T5 income is 312 against ~66 spent at 12 items.
- Upper bound on the wall: 13 → 15 items with conversion, or 16 → 18 combined with normal dismantling.
- Condition: you need T5 in hand while T4 is still needed (L61-80). T5 comes from L80+ content and daily events, so the real effect is probably much smaller.

## SECTION 4: DESIGN NUMBERS / TEXT THAT STILL LOOK OFF (suggestions only, nothing changed)
1. guild_facilities 38 still says "re-check PENDING" and "15 = ~27 targeted battles (old ~311 basis)". Suggested record: "with per-tier dismantling, 12-15 items (14-16 with 3:1 conversion)". Drop the 27-battle line or re-derive it.
2. T5 part as T4 (gf51). If the 2-3 item wall lift above is unwanted, refund the T5 part at 1 T4 per 3 T5 spent (about 33% instead of 50%), or pay nothing for it. If T5 is normally only in hand after L80, keeping it as is is fine.
3. The catch-up fee now overcharges a player whose Blacksmith is ahead of the item. A boosted player at BS L10 all game pays 2,760g (1H) / 4,133g (2H) more by enchanting late than by enchanting first. The saving it used to give is now an equal-size penalty. It is safe (no exploit). Accept it, or tell players in the UI to "enchant before upgrading".
4. gf51 wording: "round down per tier, then add the T5 part as T4" can be read two ways (round the T4 and T5 parts separately, or together). The difference is at most 1 material. Suggest the text say "rounded separately".
5. Essence target (ms41): 25% drops only holds near 0.40 drops per battle (range 11-45%). Lock the real drop rate before tuning Essence drop chances.

## SECTION 5: HEALTHY
- Per-tier refund + starting-rarity +1 closes X1 and X2 completely, across every slot and rarity, including Exalted-Transcendent.
- The per-level discount closes X3 to the gold piece.
- Fixed Add order and per-line rerolls close X4.
- Round-down is consistent and integer-safe.
- Facility, supply and pressure numbers are unchanged from the first run.

## SECTION 6: DELTA vs first run (report_runeforge_economy_2026-11-01.md)
- Resolved: X1 (+63g → −37g), X2 (+250g → −2,155g; Epic L1→80 119 → 31 T4), X3 (−9% → 0), X4 (rule gap → fixed), Epic-fee rounding, the Workshop table (70,928 → 70,927).
- New: the T5→T4 material lever (Section 3); the late-enchant overcharge for players whose Blacksmith is ahead (Section 4 #3).
- Unchanged: enchant→sell −22/−34; Essence 25%; crafted-Epic supply (accepted by the user); facilities; pressure.
- DB rows changed since the first run (vs backups\CTRBLXAI_before_simfix_20261101_100613.db):
  - rule text: guild_facilities 31, 38, 48, 51, 55, 57; materials_system 42
  - notes only: guild_facilities 37, 41; materials_system 41; economy_framework 15, 19; loot_progression 24, 26, 69
  - equipment_schema: reroll_count

## VERDICT
SIMULATION CLEAN — all 26 checks pass and no gold exploit was found. One minor material lever (T5→T4 via dismantling, wall +2-3 items at most) and four text/number notes are left for the developer.
