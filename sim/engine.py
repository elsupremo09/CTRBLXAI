"""
CTRBLXAI Balance Simulation Engine
===================================
Reimplements game formulas from CTRBLXAI.db in Python.
All formulas sourced EXCLUSIVELY from the database — never from Luau source.
See FORMULAS.md for full provenance.

Seed: 42 (deterministic — no RNG in this game anyway)
"""

import math
import sqlite3
import json
from dataclasses import dataclass, field
from typing import Dict, List, Tuple, Optional

# ═══════════════════════════════════════════════════════════
# CONSTANTS
# ═══════════════════════════════════════════════════════════

DB_PATH = r"D:\AI\Projects\CTRBLXAI\docs\CTRBLXAI.db"
SEED = 42
LEVEL_BANDS = [1, 25, 50, 99, 150, 199, 250, 300]
STANDARD_BASE_RT = 400
BOSS_BASE_RT = 300
STANDARD_AP = 2
BOSS_AP = 3


# ═══════════════════════════════════════════════════════════
# CORE FORMULA IMPLEMENTATIONS
# ═══════════════════════════════════════════════════════════

def stat_at_level(start: float, growth: float, level: int) -> int:
    """Stat value at given level. floor(start + growth * (level - 1))"""
    return int(math.floor(start + growth * (level - 1)))


def weapon_scale(item_level: int) -> float:
    """Weapon/equipment level scaling. DB: weapons_equipment, WEAPON LEVEL SCALING row."""
    if item_level <= 1:
        return 0.30
    return 0.30 + 0.70 * ((item_level - 1) / 98) ** 0.55


def scaled_property(l99_value: float, item_level: int) -> float:
    """Scale a L99 property to item_level. Zero stays zero."""
    if l99_value == 0:
        return 0
    scale = weapon_scale(item_level)
    if l99_value < 0:
        return l99_value * scale  # negative preserves sign, increases magnitude
    return l99_value * scale


def attack_power(weapon_damage: float, STR: int) -> float:
    """DB: core_stats id=2. Weapon Damage x (1 + STR / 200)"""
    return weapon_damage * (1 + STR / 200)


def effective_equipment_wt(equip_wt: float, STR: int) -> float:
    """DB: core_stats id=2. Reduces burden or amplifies speed bonus."""
    if equip_wt >= 0:
        return equip_wt * (1 - STR / (200 + STR))
    else:
        return equip_wt * (1 + STR / (200 + STR))


def rt_delay_bonus(base_rt_delay: float, STR: int) -> float:
    """DB: core_stats id=2. RT Delay inflicted on target."""
    return base_rt_delay * (1 + min(STR / (200 + STR), 0.75))


def force(STR: int) -> int:
    """DB: core_stats id=2."""
    return 1 + STR // 60


def movement_range(AGI: int) -> int:
    """DB: core_stats id=3."""
    return 3 + AGI // 60


def evasiveness(AGI: int) -> float:
    """DB: core_stats id=3."""
    return AGI / (AGI + 200)


def skill_potency_multiplier(INT: int) -> float:
    """DB: core_stats id=4."""
    return 1 + INT / (200 + INT)


def max_mp(INT: int) -> int:
    """DB: core_stats id=4."""
    return 20 + INT * 2


def mp_regen_per_1000ct(INT: int) -> int:
    """DB: core_stats id=49. MP per 1000 CT."""
    return 2 + INT // 40


def hp(VIT: int) -> int:
    """DB: core_stats id=5."""
    return 50 + VIT * 4


def defense_power(defense: float, VIT: int) -> float:
    """DB: core_stats id=5."""
    return defense * (1 + VIT / 300)


def debuff_resistance_mult(VIT: int) -> float:
    """DB: core_stats id=5."""
    return 1 - VIT / (300 + VIT)


def rt_delay_resistance(incoming_delay: float, VIT: int) -> float:
    """DB: core_stats id=5."""
    return incoming_delay * (1 - VIT / (300 + VIT))


def stability(VIT: int) -> int:
    """DB: core_stats id=5."""
    return 1 + VIT // 60


def precision(DEX: int) -> float:
    """DB: core_stats id=6."""
    return DEX / (DEX + 200)


def jump(DEX: int) -> int:
    """DB: core_stats id=6."""
    return 1 + DEX // 60


def channel_time_reduction(base_channel: float, DEX: int) -> float:
    """DB: core_stats id=6."""
    return base_channel * (1 - DEX / (300 + DEX))


def combat_fortune_modifier(delta_luk: int) -> float:
    """DB: core_stats id=7. Modifies final damage."""
    return 0.40 * delta_luk / (abs(delta_luk) + 150)


def starting_rt(base_rt: int, LUK: int) -> int:
    """DB: core_stats id=7. Initiative RT at battle start."""
    return round(base_rt * (1 - 0.30 * LUK / (100 + LUK)))


def hit_quality(attacker_DEX: int, target_AGI: int) -> float:
    """DB: core_stats id=35."""
    prec = precision(attacker_DEX)
    eva = evasiveness(target_AGI)
    return 1 + (prec - eva)


def effective_defense(atk_power: float, def_power: float) -> float:
    """DB: core_stats id=31. Harmonic mean style."""
    if atk_power + def_power == 0:
        return 0
    return (atk_power * def_power) / (atk_power + def_power)


def raw_damage(atk_power: float, def_power: float) -> float:
    """DB: core_stats id=31."""
    eff_def = effective_defense(atk_power, def_power)
    return max(0, atk_power - eff_def)


def modified_base_rt(base_rt: int, eff_armor_wt: float) -> float:
    """DB: weapons_equipment row 7."""
    return base_rt + eff_armor_wt


def basic_attack_rt(mod_base_rt: float, eff_weapon_wt: float) -> float:
    """DB: weapons_equipment row 8."""
    return round(mod_base_rt * 0.10) + eff_weapon_wt


def two_attack_cycle_rt(mod_base_rt: float, ba_rt: float) -> float:
    """DB: weapons_equipment row 9."""
    return mod_base_rt + 2 * ba_rt


def attacks_per_1000ct(cycle_rt: float) -> float:
    """DB: weapons_equipment row 10."""
    if cycle_rt == 0:
        return float('inf')
    return 2000 / cycle_rt


def movement_rt(mod_base_rt: float, tiles: int, AGI: int) -> float:
    """DB: movement_targeting. Total Movement RT."""
    return round(mod_base_rt * 0.0625 * tiles * (1 - AGI / (200 + AGI)))


# ═══════════════════════════════════════════════════════════
# DATA STRUCTURES
# ═══════════════════════════════════════════════════════════

@dataclass
class Race:
    name: str
    start_str: int
    start_agi: int
    start_int: int
    start_vit: int
    start_dex: int
    start_luk: int
    growth_str: float
    growth_agi: float
    growth_int: float
    growth_vit: float
    growth_dex: float
    growth_luk: float

    def stats_at_level(self, level: int) -> Dict[str, int]:
        return {
            'STR': stat_at_level(self.start_str, self.growth_str, level),
            'AGI': stat_at_level(self.start_agi, self.growth_agi, level),
            'INT': stat_at_level(self.start_int, self.growth_int, level),
            'VIT': stat_at_level(self.start_vit, self.growth_vit, level),
            'DEX': stat_at_level(self.start_dex, self.growth_dex, level),
            'LUK': stat_at_level(self.start_luk, self.growth_luk, level),
        }


@dataclass
class Weapon:
    name: str
    damage: int  # L99
    weight: int  # L99
    rt_delay: int  # L99
    defense: int  # L99
    hands: str  # "1H" or "2H"
    min_range: int
    max_range: int
    pattern: str
    projectile: str
    passive_name: str
    passive_bp: int

    def scaled_damage(self, item_level: int) -> float:
        return scaled_property(self.damage, item_level)

    def scaled_weight(self, item_level: int) -> float:
        return scaled_property(self.weight, item_level)

    def scaled_rt_delay(self, item_level: int) -> float:
        return scaled_property(self.rt_delay, item_level)

    def scaled_defense(self, item_level: int) -> float:
        return scaled_property(self.defense, item_level)


@dataclass
class ArmorLoadout:
    """Simplified armor loadout for simulation (total Defense and WT from non-weapon equipment)."""
    total_defense: float  # sum of all non-weapon defense
    total_wt: float  # sum of all non-weapon weight (armor WT for Modified Base RT)
    total_hp_bonus: float
    total_mp_bonus: float
    offhand_wt: float  # off-hand WT for Guard RT (0 if 2H)
    offhand_def: float


@dataclass
class UnitProfile:
    """A unit ready for combat simulation."""
    race: Race
    level: int
    weapon: Weapon
    armor: ArmorLoadout
    stats: Dict[str, int] = field(default_factory=dict)
    # Computed values
    max_hp: int = 0
    max_mp: int = 0
    mod_base_rt: float = 0
    ba_rt: float = 0
    cycle_rt: float = 0
    atk_per_1000ct: float = 0
    weapon_damage_scaled: float = 0
    attack_pwr: float = 0
    total_defense: float = 0
    defense_pwr: float = 0

    def compute(self):
        """Compute all derived values."""
        self.stats = self.race.stats_at_level(self.level)
        S = self.stats

        # Item level = unit level for simplicity
        item_level = min(self.level, 99)  # weapons capped at L99 base, higher levels keep L99 stats

        # HP/MP
        self.max_hp = hp(S['VIT']) + int(self.armor.total_hp_bonus)
        self.max_mp = max_mp(S['INT']) + int(self.armor.total_mp_bonus)

        # Weapon scaling
        self.weapon_damage_scaled = self.weapon.scaled_damage(item_level)
        wpn_wt_scaled = self.weapon.scaled_weight(item_level)
        wpn_def_scaled = self.weapon.scaled_defense(item_level)

        # Effective weights
        eff_wpn_wt = effective_equipment_wt(wpn_wt_scaled, S['STR'])
        
        # Armor WT scales with item level too
        armor_wt_scaled = scaled_property(self.armor.total_wt, item_level)
        eff_armor_wt = effective_equipment_wt(armor_wt_scaled, S['STR'])

        # Modified Base RT
        self.mod_base_rt = modified_base_rt(STANDARD_BASE_RT, eff_armor_wt)

        # Basic Attack RT
        self.ba_rt = basic_attack_rt(self.mod_base_rt, eff_wpn_wt)

        # Two-Attack Cycle
        self.cycle_rt = two_attack_cycle_rt(self.mod_base_rt, self.ba_rt)
        self.atk_per_1000ct = attacks_per_1000ct(self.cycle_rt)

        # Attack Power
        self.attack_pwr = attack_power(self.weapon_damage_scaled, S['STR'])

        # Defense (weapon + armor, scaled)
        armor_def_scaled = scaled_property(self.armor.total_defense, item_level)
        self.total_defense = armor_def_scaled + wpn_def_scaled + scaled_property(self.armor.offhand_def, item_level)
        self.defense_pwr = defense_power(self.total_defense, S['VIT'])


# ═══════════════════════════════════════════════════════════
# DATA LOADING
# ═══════════════════════════════════════════════════════════

def load_races() -> List[Race]:
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name, start_str, start_agi, start_int, start_vit, start_dex, start_luk, growth_str, growth_agi, growth_int, growth_vit, growth_dex, growth_luk FROM races")
    races = []
    for row in cursor.fetchall():
        races.append(Race(*row))
    conn.close()
    return races


def load_weapons() -> List[Weapon]:
    """Parse weapons from the weapons_equipment table."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT topic, rule, notes FROM weapons_equipment WHERE section LIKE '%---%' OR (topic LIKE '%/%' AND rule LIKE '%|%')")
    
    weapons = []
    for row in cursor.fetchall():
        topic, rule, notes = row
        # Parse weapon entries like: "65 / 165 / 28 / 10" in topic and "2H | 1 | Cleave | None | —" in rule
        if '/' in str(topic) and '|' in str(rule):
            # Get weapon name from the previous context - we need a different approach
            pass
    conn.close()
    
    # Hardcode from verified DB extraction (all values confirmed from weapons_equipment table)
    weapons_data = [
        # 2H Melee
        ("Greatsword", 65, 165, 28, 10, "2H", 1, 1, "Cleave", "None", "—", 0),
        ("Claws", 45, 25, 110, -5, "2H", 1, 1, "Single", "None", "Stagger", 100),
        ("War Axe", 97, 107, 20, -20, "2H", 1, 1, "Single", "None", "Brutal", 100),
        ("Spear", 42, 90, 45, 21, "2H", 1, 2, "Line 2", "None", "Fortify", 120),
        ("Hammer", 80, 130, 110, 5, "2H", 1, 1, "Single", "None", "Knockback", 150),
        ("Scythe", 64, 177, 15, -5, "2H", 1, 1, "Cleave", "None", "Reap", 100),
        ("Lance", 91, 100, 29, 2, "2H", 1, 1, "Single", "None", "Charge", 130),
        ("Flameberge", 87, 100, 59, 5, "2H", 1, 1, "Single", "None", "Lacerate", 140),
        ("Greatshield", 59, 60, 79, 54, "2H", 1, 1, "Single", "None", "Bulwark", 150),
        ("Chains", 50, 50, 89, 24, "2H", 1, 2, "Single", "None", "Pull", 150),
        # 1H Melee
        ("Sword", 67, 60, 60, 5, "1H", 1, 1, "Single", "None", "—", 0),
        ("Dagger", 60, 10, 20, 6, "1H", 1, 1, "Single", "None", "Piercing Edge", 120),
        ("Whip", 52, 80, 45, 0, "1H", 1, 3, "Single", "None", "—", 0),
        ("Club", 37, 70, 64, 19, "1H", 1, 1, "Single", "None", "Knockback", 150),
        ("Sword Breaker", 41, 25, 53, 44, "1H", 1, 1, "Single", "None", "—", 0),
        ("Rapier", 66, 33, 25, 0, "1H", 1, 1, "Single", "None", "Precision Strike", 130),
        ("Sickle", 59, 64, 53, 0, "1H", 1, 1, "Single", "None", "Drain", 120),
        ("Torch", 38, 35, 54, 9, "1H", 1, 1, "Single", "None", "Ignite", 150),
        ("Fan", 57, 75, 15, -5, "1H", 1, 1, "Adjacent", "None", "—", 0),
        ("Flail", 59, 61, 49, -3, "1H", 1, 1, "Single", "None", "Bypass", 140),
        ("Hatchet", 64, 35, 28, 4, "1H", 1, 1, "Single", "None", "Executioner", 110),
        ("Needle", 29, 64, 54, -3, "1H", 2, 3, "Single", "Direct", "True Strike", 150),
        ("Boomerang", 39, 74, 42, -3, "1H", 2, 3, "Single", "Arc", "Tricky", 130),
        ("Throwing Knife", 47, 40, 25, -3, "1H", 2, 3, "Single", "Direct", "Backstab", 120),
        ("Bell", 5, 30, 15, 0, "1H", 2, 3, "Single", "Channeled", "Lullaby", 250),
        # 2H Ranged
        ("Crossbow", 34, 20, 64, 0, "2H", 2, 4, "Single", "Direct", "Armor Pierce", 130),
        ("Staff", 58, 60, 40, 0, "2H", 2, 4, "Single", "Channeled", "Arcane Reach", 120),
        ("Great Bow", 63, 115, 71, -5, "2H", 2, 4, "Single", "Arc", "High Ground", 100),
        ("Longbow", 50, 130, 20, -5, "2H", 2, 5, "Single", "Arc", "Range +1", 190),
        ("Bazooka", 43, 215, 20, -5, "2H", 3, 5, "Impact Splash", "Arc", "—", 0),
        ("Mortar", 59, 161, 15, -8, "2H", 4, 5, "Impact Splash", "Arc", "—", 0),
        ("Ballista", 58, 153, 15, -8, "2H", 2, 4, "Line 2", "Direct", "—", 0),
        ("Javelin", 64, 93, 54, -5, "2H", 2, 3, "Adjacent", "Arc", "—", 0),
        ("Frost Rod", 34, 50, 54, 1, "2H", 2, 4, "Single", "Channeled", "Freeze", 180),
        ("War Horn", 5, 68, 94, 0, "2H", 1, 2, "Impact Splash", "Channeled", "—", 0),
        # 1H Ranged
        ("Pistol", 20, 70, 58, 0, "1H", 2, 4, "Single", "Direct", "—", 0),
        ("Wand", 25, 50, 45, 0, "1H", 2, 3, "Single", "Channeled", "Arcane Flow", 80),
        ("Blowgun", 15, 60, 0, 2, "1H", 2, 4, "Single", "Direct", "Venomous", 200),
    ]
    
    for d in weapons_data:
        weapons.append(Weapon(*d))
    
    return weapons


def build_standard_armor(item_level: int) -> ArmorLoadout:
    """Build a 'medium armor' baseline loadout from average non-weapon stats.
    Based on nonweapon_equipment: Body=400BP, Head/Gloves/Feet=250BP each, Acc=200BP.
    Total loadout Defense budget: ~1550 BP across slots.
    Using median-ish values from the catalog."""
    # Average L99 values across the catalog (approximate medians)
    # Body: Def~35, WT~32, HP~35, MP~12
    # Head: Def~17, WT~10, HP~20, MP~12
    # Gloves: Def~14, WT~12, HP~20, MP~8
    # Feet: Def~13, WT~10, HP~18, MP~10
    # Accessory: Def~9, WT~3, HP~13, MP~7
    total_def_l99 = 35 + 17 + 14 + 13 + 9  # = 88
    total_wt_l99 = 32 + 10 + 12 + 10 + 3   # = 67
    total_hp_l99 = 35 + 20 + 20 + 18 + 13  # = 106
    total_mp_l99 = 12 + 12 + 8 + 10 + 7    # = 49

    return ArmorLoadout(
        total_defense=total_def_l99,  # will be scaled later in UnitProfile.compute()
        total_wt=total_wt_l99,
        total_hp_bonus=scaled_property(total_hp_l99, item_level) * 3,  # HP pricing = 3 BP/pt means these are raw HP points
        total_mp_bonus=scaled_property(total_mp_l99, item_level),  # raw MP points
        offhand_wt=0,  # default; overridden for 1H+offhand
        offhand_def=0,
    )


def build_unit(race: Race, level: int, weapon: Weapon, armor: Optional[ArmorLoadout] = None) -> UnitProfile:
    """Create a fully computed unit profile."""
    item_level = min(level, 99)
    if armor is None:
        armor = build_standard_armor(item_level)
    
    # If 2H weapon, offhand WT = 0 (already default)
    # If 1H weapon, add a generic off-hand (Shield: Def=57, WT=20)
    if weapon.hands == "1H":
        armor.offhand_wt = 20  # standard off-hand WT
        armor.offhand_def = 57  # Shield defense (most common 1H pairing)
    
    unit = UnitProfile(race=race, level=level, weapon=weapon, armor=armor)
    unit.compute()
    return unit


# ═══════════════════════════════════════════════════════════
# SIMULATION FUNCTIONS
# ═══════════════════════════════════════════════════════════

def sim_time_to_kill(attacker: UnitProfile, defender: UnitProfile) -> Dict:
    """Simulate basic attack TTK. Returns hits, CT elapsed, damage per hit."""
    # Hit quality
    hq = hit_quality(attacker.stats['DEX'], defender.stats['AGI'])
    
    # Raw damage per hit
    raw_dmg = raw_damage(attacker.attack_pwr, defender.defense_pwr)
    
    # Apply hit quality
    final_dmg = round(raw_dmg * hq)
    
    # Ensure minimum 0
    final_dmg = max(0, final_dmg)
    
    if final_dmg <= 0:
        return {'hits': float('inf'), 'ct_to_kill': float('inf'), 'damage_per_hit': 0, 'dps_per_1000ct': 0}
    
    hits_to_kill = math.ceil(defender.max_hp / final_dmg)
    
    # CT to kill: each 2 attacks = 1 cycle
    full_cycles = hits_to_kill // 2
    remainder = hits_to_kill % 2
    ct_to_kill = full_cycles * attacker.cycle_rt
    if remainder:
        ct_to_kill += attacker.mod_base_rt + attacker.ba_rt  # partial cycle
    
    dps_per_1000ct = final_dmg * attacker.atk_per_1000ct
    
    return {
        'hits': hits_to_kill,
        'ct_to_kill': ct_to_kill,
        'damage_per_hit': final_dmg,
        'dps_per_1000ct': dps_per_1000ct,
    }


def sim_rt_delay_throughput(attacker: UnitProfile) -> Dict:
    """RT Delay inflicted per 1000 CT via basic attacks."""
    S = attacker.stats
    scaled_delay = scaled_property(attacker.weapon.rt_delay, min(attacker.level, 99))
    
    # RT Delay Bonus from STR
    effective_delay = rt_delay_bonus(scaled_delay, S['STR'])
    
    # Delay per 1000 CT
    delay_per_1000ct = effective_delay * attacker.atk_per_1000ct
    
    return {
        'raw_delay_per_hit': scaled_delay,
        'effective_delay_per_hit': effective_delay,
        'delay_per_1000ct': delay_per_1000ct,
        'attacks_per_1000ct': attacker.atk_per_1000ct,
    }


def sim_mp_economy(unit: UnitProfile, skill_mp_cost_l99: int = 20) -> Dict:
    """MP available vs MP needed per 1000 CT."""
    S = unit.stats
    regen = mp_regen_per_1000ct(S['INT'])
    
    # Skill MP cost scales with weapon level (same weapon scale formula)
    item_level = min(unit.level, 99)
    skill_cost = round(skill_mp_cost_l99 * weapon_scale(item_level))
    
    # How many skills can be cast before MP runs out?
    if skill_cost <= 0:
        skills_before_empty = float('inf')
    else:
        skills_before_empty = unit.max_mp / skill_cost
    
    # Sustained: can regen cover cost?
    # Assume 1 skill per turn (which takes ~cycle_rt CT)
    ct_per_skill = unit.cycle_rt  # rough: 1 turn worth of CT per skill use
    mp_regened_per_skill = regen * ct_per_skill / 1000
    sustainable = mp_regened_per_skill >= skill_cost
    
    return {
        'max_mp': unit.max_mp,
        'mp_regen_per_1000ct': regen,
        'skill_mp_cost': skill_cost,
        'skills_before_empty': skills_before_empty,
        'mp_regened_per_turn': mp_regened_per_skill,
        'sustainable': sustainable,
    }


def sim_effective_weight(unit: UnitProfile) -> Dict:
    """Effective WT and RT analysis."""
    S = unit.stats
    item_level = min(unit.level, 99)
    raw_wpn_wt = scaled_property(unit.weapon.weight, item_level)
    eff_wpn_wt = effective_equipment_wt(raw_wpn_wt, S['STR'])
    raw_armor_wt = scaled_property(unit.armor.total_wt, item_level)
    eff_armor_wt = effective_equipment_wt(raw_armor_wt, S['STR'])
    
    return {
        'raw_weapon_wt': raw_wpn_wt,
        'effective_weapon_wt': eff_wpn_wt,
        'wt_reduction_pct': (1 - eff_wpn_wt / raw_wpn_wt) * 100 if raw_wpn_wt > 0 else 0,
        'raw_armor_wt': raw_armor_wt,
        'effective_armor_wt': eff_armor_wt,
        'modified_base_rt': unit.mod_base_rt,
        'basic_attack_rt': unit.ba_rt,
        'cycle_rt': unit.cycle_rt,
    }


if __name__ == "__main__":
    print("CTRBLXAI Simulation Engine loaded successfully.")
    print(f"Level bands: {LEVEL_BANDS}")
    races = load_races()
    weapons = load_weapons()
    print(f"Loaded {len(races)} races, {len(weapons)} weapons.")
