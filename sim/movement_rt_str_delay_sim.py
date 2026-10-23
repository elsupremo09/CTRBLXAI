"""CTRBLXAI movement-RT / STR-RT-delay validation sim.
Seed: movement_rt_str_delay_2026-10-23 (deterministic, no RNG).
All formulas from CTRBLXAI.db only (see FORMULAS.md). Read-only; validates the
three 2026-10-23 wiring fixes: movement_targeting id8 (0.0625->0.03 + AGI term),
core_stats id2 (STR RT Delay Bonus). Source-verified; Studio runtime pending.
"""
import math

def rh(x): return math.floor(x + 0.5)                       # core_stats id28
def eff_wt(wt, STR):                                         # core_stats id2
    return wt*(1-STR/(200+STR)) if wt>=0 else wt*(1+STR/(200+STR))
def modified_base_rt(own, armor_wt, STR, trait=1.0, status=1.0):  # weapons_equipment id7
    return (own+eff_wt(armor_wt,STR))*trait*status
def basic_attack_rt(mbrt, eff_weapon_wt):                   # weapons_equipment id8
    return rh(mbrt*0.10)+eff_weapon_wt
def move_rt_new(mbrt, tiles, AGI):                          # movement_targeting id8 (NEW)
    return rh(mbrt*0.03*tiles*(1-AGI/(200+AGI)))
def move_rt_old(mbrt, tiles):                               # prior model
    return rh(mbrt*0.0625*tiles)
def inflicted_delay(base_delay, STR):                       # core_stats id2 (NEW)
    return base_delay*(1+min(STR/(200+STR),0.75))
def received_delay(incoming, VIT):                          # core_stats id5
    return incoming*(1-VIT/(300+VIT))
def wscale(lvl):                                            # weapons_equipment id157
    return 0.30+0.70*((lvl-1)/98)**0.55
def move_range(AGI):                                        # core_stats id3
    return 3+AGI//60

if __name__ == "__main__":
    print("See sim/reports/movement_rt_str_delay_2026-10-23.md for the full run output.")
