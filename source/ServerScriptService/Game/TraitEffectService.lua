-- TraitEffectService.lua
-- CTRBLXAI | Perks & Flaws PHASE 2 -- simple-numeric trait effects
--
-- Centralized query interface for unit-trait (perk / flaw) numeric modifiers.
-- Mirrors RacePassiveService's public-modifier shape and is folded in at the SAME
-- call sites the race modifiers already use (EquipmentService.RebuildUnitStats,
-- CombatResolver Resolve*, CommandService MP cost / Basic Attack RT / Guard,
-- TargetingService movement / jump, StatusService DoT tick).
--
-- Traits live on unit.perkIds / unit.drawbackIds (Phase 1, TraitRoller). Every
-- lookup is BY trait_id via TraitData.GetTrait(id) -- NEVER by name (duplicate
-- names exist: 'Clumsy' x2, 'Sluggish' x2).
--
-- A unit with no traits (nil / empty perkIds + drawbackIds) gets NEUTRAL values
-- from every getter (multiplier 1.0 / offset 0 / nil stat table). Unknown or
-- Phase-3 trait ids are simply absent from EFFECTS and are no-ops.
--
-- PHASE 2 SCOPE: only static / unconditional numeric effects (see EFFECTS). Every
-- conditional or triggered trait (below-X%-HP, per-enemy, on-hit, on-kill, turn
-- start/end, positional, revive, RT-cost family, etc.) is deliberately ABSENT and
-- deferred to Phase 3.
--
-- "Level-Scaled" (unit_traits.scaling): the DB does not define a level-scaling
-- formula anywhere, so every value is applied at its face (authored) value.
--
-- Break (project_rules 35/47: Break disables Inherent Unit Perk / Drawback): the
-- COMBAT-TIME getters (damage dealt/received, DoT, healing, MP cost, Basic Attack
-- WT, Guard, movement, jump) return neutral while a "Break" status instance is on
-- the unit (mirrors DoctrinePassiveService.isBroken). The REBUILD-TIME getters
-- (stats, armor, weapon, max HP/MP, force/stability) are static per unit and are
-- not re-evaluated mid-battle (same limitation as RacePassiveService stat folds).
--
-- Modifier field semantics inside EFFECTS[traitId]:
--   statPct        { STAT = offset }   effectiveStats: round(total * (1 + sum offsets))
--   hpFromVit      offset              Max HP VIT term: VIT*4*(1 + sum)
--   mpFromInt      offset              Max MP INT term: INT*2*(1 + sum)
--   armorSlotMult  { Slot = mult }     armor piece in Slot: Defense/HP/MP + its primary-stat
--                                      bonus lines x mult (WT NOT scaled -- see note)
--   armorDefense   offset              summed armor Defense x (1 + offset)
--   weaponSpec     { weapon, dmg, wt } MainHand archetype name == weapon: base dmg x(1+dmg), WT x(1+wt)
--   wtToDamage     fraction            base weapon damage += round(weapon WT x fraction)
--   basicWtMult    mult                Basic Attack weapon-WT RT term x mult (skills unaffected)
--   mpCost         offset              skill MP cost x (1 + offset)
--   jump / move    int                 Jump / Movement Range offset
--   force / stability int              derivedStats.force / .stability offset (floored at 0)
--   guardBonus     float               additive Guard mitigation (Golem precedent: +0.20)
--   dealtVsLower / dealtVsHigher offset  damage dealt when target.level < / > attacker.level
--   dealtElement   { Element = offset } damage dealt with an <Element>-tagged attack
--   dealtElemental offset              damage dealt with any non-Physical element
--   dealtSkill     offset              damage dealt by skills (not Basic Attacks)
--   dealtMelee     offset              damage dealt while wielding a melee weapon (no projectileType)
--   recvAll        offset              all direct damage received
--   recvElement    { Element = offset } damage received from an <Element>-tagged attack
--   recvElemental  offset              damage received from any non-Physical element
--   recvAOE        offset              AOE damage received
--   recvMelee      offset              damage received from an attacker wielding a melee weapon
--   recvRanged     offset              damage received from an attacker wielding a ranged weapon
--   dotAll         offset              every DoT tick received
--   dotStatus      { StatusId = offset } DoT tick of that status received
--   healRecv       offset              skill healing received (CombatResolver.ResolveHealing)
--   xpGain         offset              STUB -- no per-unit battle-XP hook exists yet (no caller)
-- Multiplicative effects from the perk and the flaw MULTIPLY together; stat
-- offsets and integer offsets SUM.

local TraitEffectService = {}

local TraitData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("TraitData")
)
local WeaponData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("WeaponData")
)

--------------------------------------------------
-- PHASE-2 EFFECT MAP (trait_id -> structured modifier)
-- Transcribed from CTRBLXAI.db unit_traits.effect (comment = authoritative text).
--------------------------------------------------

local EFFECTS = {
	-- ===== PHASE 2b: derived-stat / RT modifiers (wired 2026-10-04 inline) =====
	-- Precision (feeds Hit Quality = 1 + Precision - Evasiveness). Additive to precision fraction.
	["TRAIT-P-036"] = { precision = 0.10 },   -- Keen Aim
	["TRAIT-F-036"] = { precision = -0.10 },  -- Clumsy (Precision)
	["TRAIT-P-094"] = { precision = 0.15 },   -- Keen Aim (Greater)
	["TRAIT-F-094"] = { precision = -0.15 },  -- Clumsy (Greater)
	-- Evasiveness (feeds Hit Quality). Additive to evasiveness fraction.
	["TRAIT-P-095"] = { evasiveness = 0.10 },  -- Light Step
	["TRAIT-F-095"] = { evasiveness = -0.10 }, -- Heavy-Footed
	["TRAIT-P-137"] = { evasiveness = 0.12 },  -- Light Step (Greater)
	["TRAIT-F-137"] = { evasiveness = -0.12 }, -- Heavy-Footed (Greater)
	-- Hit Quality flat +/-0.05, gated by attack type (melee vs ranged).
	["TRAIT-P-063"] = { hqMelee = 0.05 },   -- Clean Fighter
	["TRAIT-F-063"] = { hqMelee = -0.05 },  -- Sloppy Fighter
	["TRAIT-P-117"] = { hqRanged = 0.05 },  -- Steady Aim
	["TRAIT-F-117"] = { hqRanged = -0.05 }, -- Shaky Aim
	-- Fortune: feeds LUK (Combat Fortune is relational on LUK delta). statPct LUK.
	["TRAIT-P-037"] = { statPct = { LUK = 0.10 } },  -- Lucky
	["TRAIT-F-037"] = { statPct = { LUK = -0.10 } }, -- Unlucky
	["TRAIT-P-099"] = { statPct = { LUK = 0.15 } },  -- Lucky (Greater)
	["TRAIT-F-099"] = { statPct = { LUK = -0.15 } }, -- Unlucky (Greater)
	-- Base RT multiplier (Quick/Sluggish). Lower base RT = acts sooner.
	["TRAIT-P-164"] = { baseRtMult = -0.10 },  -- Quick: 10% lower base RT
	["TRAIT-F-164"] = { baseRtMult = 0.10 },   -- Sluggish: 10% higher base RT
	-- Timeline Sovereign / Temporal Drag: base RT + starting RT (+ rt-delay inflicted for Sovereign).
	["TRAIT-P-178"] = { baseRtMult = -0.10, startRtMult = -0.12, rtDelayInflictMult = 0.10 }, -- Timeline Sovereign
	["TRAIT-F-178"] = { baseRtMult = 0.08, startRtMult = 0.15 },  -- Temporal Drag
	-- Channel time (Channeler/Slow Channeler): +/-25% of skill channel RT.
	["TRAIT-P-060"] = { channelMult = -0.25 }, -- Channeler
	["TRAIT-F-060"] = { channelMult = 0.25 },  -- Slow Channeler
	-- Skill activation/delay time (Flash-Caster/Laggy Caster): +/-25%.
	["TRAIT-P-079"] = { skillDelayMult = -0.25 }, -- Flash-Caster
	["TRAIT-F-079"] = { skillDelayMult = 0.25 },  -- Laggy Caster
	-- RT Delay inflicted on targets (Time Locker/Time Freed): +/-25%.
	["TRAIT-P-149"] = { rtDelayInflictMult = 0.25 },  -- Time Locker
	["TRAIT-F-149"] = { rtDelayInflictMult = -0.25 }, -- Time Freed
	-- Movement RT cost (Fleet Runner/Plodding): -/+25%.
	["TRAIT-P-080"] = { moveRtMult = -0.25 }, -- Fleet Runner
	["TRAIT-F-080"] = { moveRtMult = 0.25 },  -- Plodding
	-- Discovery radius (Far/Near-Sighted): integer-ish offset.
	["TRAIT-P-075"] = { discoveryRadius = 1 },    -- Far-Sighted
	["TRAIT-F-075"] = { discoveryRadius = -1 },   -- Near-Sighted
	["TRAIT-P-135"] = { discoveryRadius = 1.2 },  -- Far-Sighted (Greater)
	["TRAIT-F-135"] = { discoveryRadius = -1.2 }, -- Near-Sighted (Greater)
	-- Interact range (Long/Short Reach): integer offset.
	["TRAIT-P-096"] = { interactRange = 1 },  -- Long Reach
	["TRAIT-F-096"] = { interactRange = -1 }, -- Short Reach
	["TRAIT-P-138"] = { interactRange = 2 },  -- Long Reach (Greater)
	["TRAIT-F-138"] = { interactRange = -2 }, -- Short Reach (Greater)
	-- Terrain movement cost (Pathfinder ignore / Bogged Down +50%).
	["TRAIT-P-142"] = { terrainCostIgnore = true }, -- Pathfinder
	["TRAIT-F-142"] = { terrainCostMult = 0.50 },   -- Bogged Down
	-- Arcane Prodigy: skill potency +/-% and skill RT cost -/+%.
	["TRAIT-P-168"] = { skillPotencyPct = 0.12, skillRtMult = -0.08 }, -- Arcane Prodigy (perk)
	["TRAIT-F-168"] = { skillPotencyPct = -0.12, skillRtMult = 0.08 }, -- Arcane Prodigy (flaw)
	-- NOTE: Dual Strike (TRAIT-P-171 / TRAIT-F-171) is DEFERRED to Phase 3 (double-resolve trigger).
	-- Accessory Specialist (perk): Double the numerical Base and Bonus stats from Accessory armor (Passive effects excluded).
	["TRAIT-P-001"] = { armorSlotMult = { Accessory = 2.0 } },
	-- Accessory Klutz (flaw): Halve the numerical Base and Bonus stats from Accessory armor (Passive effects excluded).
	["TRAIT-F-001"] = { armorSlotMult = { Accessory = 0.5 } },
	-- Antivenom Blood (perk): Venom damage received -50%.
	["TRAIT-P-003"] = { dotStatus = { Venom = -0.5 } },
	-- Thin Blood (flaw): Venom damage received +50%.
	["TRAIT-F-003"] = { dotStatus = { Venom = 0.5 } },
	-- Basics (perk): Basic Attack use only 60% of weapon WT. Does not affect skills
	["TRAIT-P-005"] = { basicWtMult = 0.6 },
	-- Heavy Basics (flaw): Basic Attack costs 30% more weapon WT. Does not affect skills.
	["TRAIT-F-005"] = { basicWtMult = 1.3 },
	-- Blessed Recovery (perk): healing received +25%
	["TRAIT-P-007"] = { healRecv = 0.25 },
	-- Cursed Wounds (flaw): Healing received -25%
	["TRAIT-F-007"] = { healRecv = -0.25 },
	-- Body Specialist (perk): Double the numerical Base and Bonus stats from Body armor (Passive effects excluded).
	["TRAIT-P-008"] = { armorSlotMult = { Body = 2.0 } },
	-- Body Klutz (flaw): Halve the numerical Base and Bonus stats from Body armor (Passive effects excluded).
	["TRAIT-F-008"] = { armorSlotMult = { Body = 0.5 } },
	-- Brawny (perk): STR +15%
	["TRAIT-P-009"] = { statPct = { STR = 0.15 } },
	-- Weak (flaw): STR -15%
	["TRAIT-F-009"] = { statPct = { STR = -0.15 } },
	-- Bright (perk): INT +15%
	["TRAIT-P-010"] = { statPct = { INT = 0.15 } },
	-- Dim (flaw): INT -15%
	["TRAIT-F-010"] = { statPct = { INT = -0.15 } },
	-- Bully (perk): Damage inflicted to lower level targets +10%
	["TRAIT-P-011"] = { dealtVsLower = 0.1 },
	-- Underdog (flaw): Damage inflicted to lower level targets -10%
	["TRAIT-F-011"] = { dealtVsLower = -0.1 },
	-- Charmed (perk): LUK +15%
	["TRAIT-P-012"] = { statPct = { LUK = 0.15 } },
	-- Jinxed (flaw): LUK -15%
	["TRAIT-F-012"] = { statPct = { LUK = -0.15 } },
	-- Dark Affinity (perk): Takes 50% reduced damage from Dark-tagged attacks.
	["TRAIT-P-014"] = { recvElement = { Dark = -0.5 } },
	-- Dark Weakness (flaw): Takes 50% increased damage from Dark-tagged attacks.
	["TRAIT-F-014"] = { recvElement = { Dark = 0.5 } },
	-- Deep Well (perk): 20% more max MP from INT
	["TRAIT-P-015"] = { mpFromInt = 0.2 },
	-- Shallow Well (flaw): 20% less max MP from INT
	["TRAIT-F-015"] = { mpFromInt = -0.2 },
	-- Defensive (perk): Defense from armor increased by 20%
	["TRAIT-P-016"] = { armorDefense = 0.2 },
	-- Exposed Armor (flaw): Defense from armor decreased by 20%
	["TRAIT-F-016"] = { armorDefense = -0.2 },
	-- Deft (perk): DEX +15%
	["TRAIT-P-017"] = { statPct = { DEX = 0.15 } },
	-- Clumsy (flaw): DEX -15%
	["TRAIT-F-017"] = { statPct = { DEX = -0.15 } },
	-- Economist (perk): Skill MP cost is reduced by 20%
	["TRAIT-P-018"] = { mpCost = -0.2 },
	-- Spendthrift (flaw): Skill MP cost increased by 20%
	["TRAIT-F-018"] = { mpCost = 0.2 },
	-- Electric Affinity (perk): Takes 50% reduced damage from Electric-tagged attacks.
	["TRAIT-P-019"] = { recvElement = { Electric = -0.5 } },
	-- Electric Weakness (flaw): Takes 50% increased damage from Electric-tagged attacks.
	["TRAIT-F-019"] = { recvElement = { Electric = 0.5 } },
	-- Fast Learner (perk): Gains more 10% XP from battles than normal.
	["TRAIT-P-020"] = { xpGain = 0.1 },
	-- Slow Learner (flaw): Gains 10% less XP from battles than normal.
	["TRAIT-F-020"] = { xpGain = -0.1 },
	-- Feet Specialist (perk): Double the numerical Base and Bonus stats from Feet armor (Passive effects excluded).
	["TRAIT-P-021"] = { armorSlotMult = { Feet = 2.0 } },
	-- Feet Klutz (flaw): Halve the numerical Base and Bonus stats from Feet armor (Passive effects excluded).
	["TRAIT-F-021"] = { armorSlotMult = { Feet = 0.5 } },
	-- Fire Affinity (perk): Takes 50% reduced damage from Fire-tagged attacks.
	["TRAIT-P-022"] = { recvElement = { Fire = -0.5 } },
	-- Fire Weakness (flaw): Takes 50% increased damage from Fire-tagged attacks.
	["TRAIT-F-022"] = { recvElement = { Fire = 0.5 } },
	-- Fire-Hardened (perk): Burn damage received -50%.
	["TRAIT-P-023"] = { dotStatus = { Burn = -0.5 } },
	-- Flammable (flaw): Burn damage received +50%.
	["TRAIT-F-023"] = { dotStatus = { Burn = 0.5 } },
	-- Gloves Specialist (perk): Double the numerical Base and Bonus stats from Gloves armor (Passive effects excluded).
	["TRAIT-P-024"] = { armorSlotMult = { Gloves = 2.0 } },
	-- Gloves Klutz (flaw): Halve the numerical Base and Bonus stats from Gloves armor (Passive effects excluded).
	["TRAIT-F-024"] = { armorSlotMult = { Gloves = 0.5 } },
	-- Hardy (perk): 20% more max HP from VIT
	["TRAIT-P-025"] = { hpFromVit = 0.2 },
	-- Frail (flaw): 20% less max HP from VIT
	["TRAIT-F-025"] = { hpFromVit = -0.2 },
	-- Head Specialist (perk): Double the numerical Base and Bonus stats from Head armor (Passive effects excluded).
	["TRAIT-P-026"] = { armorSlotMult = { Head = 2.0 } },
	-- Head Klutz (flaw): Halve the numerical Base and Bonus stats from Head armor (Passive effects excluded).
	["TRAIT-F-026"] = { armorSlotMult = { Head = 0.5 } },
	-- Hearty (perk): VIT +15%
	["TRAIT-P-027"] = { statPct = { VIT = 0.15 } },
	-- Sickly (flaw): VIT -15%
	["TRAIT-F-027"] = { statPct = { VIT = -0.15 } },
	-- Heavy Hitter (perk): 20% of weapon WT is added as base weapon damage
	["TRAIT-P-028"] = { wtToDamage = 0.2 },
	-- Feather Strikes (flaw): 20% of weapon WT is subtracted from base weapon damage
	["TRAIT-F-028"] = { wtToDamage = -0.2 },
	-- High Jumper (perk): +1 Jump
	["TRAIT-P-029"] = { jump = 1 },
	-- Stubby Legs (flaw): -1 Jump
	["TRAIT-F-029"] = { jump = -1 },
	-- Holy Affinity (perk): Takes 50% reduced damage from Holy-tagged attacks.
	["TRAIT-P-030"] = { recvElement = { Holy = -0.5 } },
	-- Holy Weakness (flaw): Takes 50% increased damage from Holy-tagged attacks.
	["TRAIT-F-030"] = { recvElement = { Holy = 0.5 } },
	-- Ice Affinity (perk): Takes 50% reduced damage from Ice-tagged attacks.
	["TRAIT-P-031"] = { recvElement = { Ice = -0.5 } },
	-- Ice Weakness (flaw): Takes 50% increased damage from Ice-tagged attacks.
	["TRAIT-F-031"] = { recvElement = { Ice = 0.5 } },
	-- Iron Stomach (perk): Poison damage received -50%.
	["TRAIT-P-032"] = { dotStatus = { Poison = -0.5 } },
	-- Weak Stomach (flaw): Poison damage received +50%.
	["TRAIT-F-032"] = { dotStatus = { Poison = 0.5 } },
	-- Nimble (perk): AGI +15%
	["TRAIT-P-038"] = { statPct = { AGI = 0.15 } },
	-- Sluggish (flaw): AGI -15%
	["TRAIT-F-038"] = { statPct = { AGI = -0.15 } },
	-- Quick Clotting (perk): Bleed damage received -50%.
	["TRAIT-P-040"] = { dotStatus = { Bleed = -0.5 } },
	-- Hemophiliac (flaw): Bleed damage received +50%.
	["TRAIT-F-040"] = { dotStatus = { Bleed = 0.5 } },
	-- Tough Skin (perk): Takes 10% less damage.
	["TRAIT-P-046"] = { recvAll = -0.1 },
	-- Thin Skin (flaw): Takes 10% more damage.
	["TRAIT-F-046"] = { recvAll = 0.1 },
	-- Water Affinity (perk): Takes 50% reduced damage from Water-tagged attacks.
	["TRAIT-P-047"] = { recvElement = { Water = -0.5 } },
	-- Water Weakness (flaw): Takes 50% increased damage from Water-tagged attacks.
	["TRAIT-F-047"] = { recvElement = { Water = 0.5 } },
	-- Alert (perk): AGI +10%, LUK +10%
	["TRAIT-P-049"] = { statPct = { AGI = 0.1, LUK = 0.1 } },
	-- Dull (flaw): AGI -10%, LUK -10%
	["TRAIT-F-049"] = { statPct = { AGI = -0.1, LUK = -0.1 } },
	-- Antivenom Blood (Greater) (perk): Venom damage received -60%.
	["TRAIT-P-051"] = { dotStatus = { Venom = -0.6 } },
	-- Thin Blood (Greater) (flaw): Venom damage received +60%.
	["TRAIT-F-051"] = { dotStatus = { Venom = 0.6 } },
	-- Bazooka Specialist (perk): When wielding a Bazooka: weapon base damage +25% and weapon WT -25%.
	["TRAIT-P-054"] = { weaponSpec = { dmg = 0.25, weapon = "Bazooka", wt = -0.25 } },
	-- Bazooka Klutz (flaw): When wielding a Bazooka: weapon base damage -25% and weapon WT +25%.
	["TRAIT-F-054"] = { weaponSpec = { dmg = -0.25, weapon = "Bazooka", wt = 0.25 } },
	-- Blessed Recovery (Greater) (perk): healing received +35%
	["TRAIT-P-055"] = { healRecv = 0.35 },
	-- Cursed Wounds (Greater) (flaw): Healing received -35%
	["TRAIT-F-055"] = { healRecv = -0.35 },
	-- Blowgun Specialist (perk): When wielding a Blowgun: weapon base damage +25% and weapon WT -25%.
	["TRAIT-P-056"] = { weaponSpec = { dmg = 0.25, weapon = "Blowgun", wt = -0.25 } },
	-- Blowgun Klutz (flaw): When wielding a Blowgun: weapon base damage -25% and weapon WT +25%.
	["TRAIT-F-056"] = { weaponSpec = { dmg = -0.25, weapon = "Blowgun", wt = 0.25 } },
	-- Brawny (Greater) (perk): STR +18%
	["TRAIT-P-057"] = { statPct = { STR = 0.18 } },
	-- Weak (Greater) (flaw): STR -18%
	["TRAIT-F-057"] = { statPct = { STR = -0.18 } },
	-- Bright (Greater) (perk): INT +18%
	["TRAIT-P-058"] = { statPct = { INT = 0.18 } },
	-- Dim (Greater) (flaw): INT -18%
	["TRAIT-F-058"] = { statPct = { INT = -0.18 } },
	-- Bully (Greater) (perk): Damage inflicted to lower level targets +12%
	["TRAIT-P-059"] = { dealtVsLower = 0.12 },
	-- Underdog (Greater) (flaw): Damage inflicted to lower level targets -12%
	["TRAIT-F-059"] = { dealtVsLower = -0.12 },
	-- Charmed (Greater) (perk): LUK +18%
	["TRAIT-P-061"] = { statPct = { LUK = 0.18 } },
	-- Jinxed (Greater) (flaw): LUK -18%
	["TRAIT-F-061"] = { statPct = { LUK = -0.18 } },
	-- Claws Specialist (perk): When wielding a Claws: weapon base damage +25% and weapon WT -25%.
	["TRAIT-P-062"] = { weaponSpec = { dmg = 0.25, weapon = "Claws", wt = -0.25 } },
	-- Claws Klutz (flaw): When wielding a Claws: weapon base damage -25% and weapon WT +25%.
	["TRAIT-F-062"] = { weaponSpec = { dmg = -0.25, weapon = "Claws", wt = 0.25 } },
	-- Clever (perk): INT +10%, DEX +10%
	["TRAIT-P-064"] = { statPct = { DEX = 0.1, INT = 0.1 } },
	-- Muddled (flaw): INT -10%, DEX -10%
	["TRAIT-F-064"] = { statPct = { DEX = -0.1, INT = -0.1 } },
	-- Club Specialist (perk): When wielding a Club: weapon base damage +25% and weapon WT -25%.
	["TRAIT-P-065"] = { weaponSpec = { dmg = 0.25, weapon = "Club", wt = -0.25 } },
	-- Club Klutz (flaw): When wielding a Club: weapon base damage -25% and weapon WT +25%.
	["TRAIT-F-065"] = { weaponSpec = { dmg = -0.25, weapon = "Club", wt = 0.25 } },
	-- Crossbow Specialist (perk): When wielding a Crossbow: weapon base damage +25% and weapon WT -25%.
	["TRAIT-P-066"] = { weaponSpec = { dmg = 0.25, weapon = "Crossbow", wt = -0.25 } },
	-- Crossbow Klutz (flaw): When wielding a Crossbow: weapon base damage -25% and weapon WT +25%.
	["TRAIT-F-066"] = { weaponSpec = { dmg = -0.25, weapon = "Crossbow", wt = 0.25 } },
	-- Dagger Specialist (perk): When wielding a Dagger: weapon base damage +25% and weapon WT -25%.
	["TRAIT-P-068"] = { weaponSpec = { dmg = 0.25, weapon = "Dagger", wt = -0.25 } },
	-- Dagger Klutz (flaw): When wielding a Dagger: weapon base damage -25% and weapon WT +25%.
	["TRAIT-F-068"] = { weaponSpec = { dmg = -0.25, weapon = "Dagger", wt = 0.25 } },
	-- Dark Attunement (perk): Deals 20% more damage when attacking with Dark-tagged attacks.
	["TRAIT-P-069"] = { dealtElement = { Dark = 0.2 } },
	-- Dark Disharmony (flaw): Deals 20% less damage when attacking with Dark-tagged attacks.
	["TRAIT-F-069"] = { dealtElement = { Dark = -0.2 } },
	-- Deep Well (Greater) (perk): 25% more max MP from INT
	["TRAIT-P-070"] = { mpFromInt = 0.25 },
	-- Shallow Well (Greater) (flaw): 25% less max MP from INT
	["TRAIT-F-070"] = { mpFromInt = -0.25 },
	-- Defensive (Greater) (perk): Defense from armor increased by 24%
	["TRAIT-P-071"] = { armorDefense = 0.24 },
	-- Exposed Armor (Greater) (flaw): Defense from armor decreased by 24%
	["TRAIT-F-071"] = { armorDefense = -0.24 },
	-- Deft (Greater) (perk): DEX +18%
	["TRAIT-P-072"] = { statPct = { DEX = 0.18 } },
	-- Clumsy (Greater) (flaw): DEX -18%
	["TRAIT-F-072"] = { statPct = { DEX = -0.18 } },
	-- Economist (Greater) (perk): Skill MP cost is reduced by 24%
	["TRAIT-P-073"] = { mpCost = -0.24 },
	-- Spendthrift (Greater) (flaw): Skill MP cost increased by 24%
	["TRAIT-F-073"] = { mpCost = 0.24 },
	-- Electric Attunement (perk): Deals 20% more damage when attacking with Electric-tagged attacks.
	["TRAIT-P-074"] = { dealtElement = { Electric = 0.2 } },
	-- Electric Disharmony (flaw): Deals 20% less damage when attacking with Electric-tagged attacks.
	["TRAIT-F-074"] = { dealtElement = { Electric = -0.2 } },
	-- Fast Learner (Greater) (perk): Gains more 15% XP from battles than normal.
	["TRAIT-P-076"] = { xpGain = 0.15 },
	-- Slow Learner (Greater) (flaw): Gains 15% less XP from battles than normal.
	["TRAIT-F-076"] = { xpGain = -0.15 },
	-- Fire Attunement (perk): Deals 20% more damage when attacking with Fire-tagged attacks.
	["TRAIT-P-077"] = { dealtElement = { Fire = 0.2 } },
	-- Fire Disharmony (flaw): Deals 20% less damage when attacking with Fire-tagged attacks.
	["TRAIT-F-077"] = { dealtElement = { Fire = -0.2 } },
	-- Fire-Hardened (Greater) (perk): Burn damage received -60%.
	["TRAIT-P-078"] = { dotStatus = { Burn = -0.6 } },
	-- Flammable (Greater) (flaw): Burn damage received +60%.
	["TRAIT-F-078"] = { dotStatus = { Burn = 0.6 } },
	-- Focused (perk): DEX +10%, INT +10%
	["TRAIT-P-081"] = { statPct = { DEX = 0.1, INT = 0.1 } },
	-- Distracted (flaw): DEX -10%, INT -10%
	["TRAIT-F-081"] = { statPct = { DEX = -0.1, INT = -0.1 } },
	-- Great Bow Specialist (perk): When wielding a Great Bow: weapon base damage +25% and weapon WT -25%.
	["TRAIT-P-082"] = { weaponSpec = { dmg = 0.25, weapon = "Great Bow", wt = -0.25 } },
	-- Great Bow Klutz (flaw): When wielding a Great Bow: weapon base damage -25% and weapon WT +25%.
	["TRAIT-F-082"] = { weaponSpec = { dmg = -0.25, weapon = "Great Bow", wt = 0.25 } },
	-- Greatsword Specialist (perk): When wielding a Greatsword: weapon base damage +25% and weapon WT -25%.
	["TRAIT-P-083"] = { weaponSpec = { dmg = 0.25, weapon = "Greatsword", wt = -0.25 } },
	-- Greatsword Klutz (flaw): When wielding a Greatsword: weapon base damage -25% and weapon WT +25%.
	["TRAIT-F-083"] = { weaponSpec = { dmg = -0.25, weapon = "Greatsword", wt = 0.25 } },
	-- Hammer Specialist (perk): When wielding a Hammer: weapon base damage +25% and weapon WT -25%.
	["TRAIT-P-084"] = { weaponSpec = { dmg = 0.25, weapon = "Hammer", wt = -0.25 } },
	-- Hammer Klutz (flaw): When wielding a Hammer: weapon base damage -25% and weapon WT +25%.
	["TRAIT-F-084"] = { weaponSpec = { dmg = -0.25, weapon = "Hammer", wt = 0.25 } },
	-- Hearty (Greater) (perk): VIT +18%
	["TRAIT-P-085"] = { statPct = { VIT = 0.18 } },
	-- Sickly (Greater) (flaw): VIT -18%
	["TRAIT-F-085"] = { statPct = { VIT = -0.18 } },
	-- Heavy Hitter (Greater) (perk): 25% of weapon WT is added as base weapon damage
	["TRAIT-P-086"] = { wtToDamage = 0.25 },
	-- Feather Strikes (Greater) (flaw): 25% of weapon WT is subtracted from base weapon damage
	["TRAIT-F-086"] = { wtToDamage = -0.25 },
	-- High Jumper (Greater) (perk): +2 Jump
	["TRAIT-P-088"] = { jump = 2 },
	-- Stubby Legs (Greater) (flaw): -2 Jump
	["TRAIT-F-088"] = { jump = -2 },
	-- Holy Attunement (perk): Deals 20% more damage when attacking with Holy-tagged attacks.
	["TRAIT-P-089"] = { dealtElement = { Holy = 0.2 } },
	-- Holy Disharmony (flaw): Deals 20% less damage when attacking with Holy-tagged attacks.
	["TRAIT-F-089"] = { dealtElement = { Holy = -0.2 } },
	-- Ice Attunement (perk): Deals 20% more damage when attacking with Ice-tagged attacks.
	["TRAIT-P-090"] = { dealtElement = { Ice = 0.2 } },
	-- Ice Disharmony (flaw): Deals 20% less damage when attacking with Ice-tagged attacks.
	["TRAIT-F-090"] = { dealtElement = { Ice = -0.2 } },
	-- Iron Stomach (Greater) (perk): Poison damage received -60%.
	["TRAIT-P-091"] = { dotStatus = { Poison = -0.6 } },
	-- Weak Stomach (Greater) (flaw): Poison damage received +60%.
	["TRAIT-F-091"] = { dotStatus = { Poison = 0.6 } },
	-- Long Strider (perk): +1 movement range.
	["TRAIT-P-097"] = { move = 1 },
	-- Short Strider (flaw): -1 movement range.
	["TRAIT-F-097"] = { move = -1 },
	-- Longbow Specialist (perk): When wielding a Longbow: weapon base damage +25% and weapon WT -25%.
	["TRAIT-P-098"] = { weaponSpec = { dmg = 0.25, weapon = "Longbow", wt = -0.25 } },
	-- Longbow Klutz (flaw): When wielding a Longbow: weapon base damage -25% and weapon WT +25%.
	["TRAIT-F-098"] = { weaponSpec = { dmg = -0.25, weapon = "Longbow", wt = 0.25 } },
	-- Lucky Star (perk): LUK +10%, VIT +10%
	["TRAIT-P-100"] = { statPct = { LUK = 0.1, VIT = 0.1 } },
	-- Doomed (flaw): LUK -10%, VIT -10%
	["TRAIT-F-100"] = { statPct = { LUK = -0.1, VIT = -0.1 } },
	-- Nimble (Greater) (perk): AGI +18%
	["TRAIT-P-102"] = { statPct = { AGI = 0.18 } },
	-- Sluggish (Greater) (flaw): AGI -18%
	["TRAIT-F-102"] = { statPct = { AGI = -0.18 } },
	-- Pistol Specialist (perk): When wielding a Pistol: weapon base damage +25% and weapon WT -25%.
	["TRAIT-P-104"] = { weaponSpec = { dmg = 0.25, weapon = "Pistol", wt = -0.25 } },
	-- Pistol Klutz (flaw): When wielding a Pistol: weapon base damage -25% and weapon WT +25%.
	["TRAIT-F-104"] = { weaponSpec = { dmg = -0.25, weapon = "Pistol", wt = 0.25 } },
	-- Powerful Build (perk): +1 force
	["TRAIT-P-105"] = { force = 1 },
	-- Frail Arms (flaw): -1 force
	["TRAIT-F-105"] = { force = -1 },
	-- Pride (perk): Damage inflicted to higher level targets +10%
	["TRAIT-P-106"] = { dealtVsHigher = 0.1 },
	-- Humble (flaw): Damage inflicted to higher level targets -10%
	["TRAIT-F-106"] = { dealtVsHigher = -0.1 },
	-- Quick Clotting (Greater) (perk): Bleed damage received -60%.
	["TRAIT-P-108"] = { dotStatus = { Bleed = -0.6 } },
	-- Hemophiliac (Greater) (flaw): Bleed damage received +60%.
	["TRAIT-F-108"] = { dotStatus = { Bleed = 0.6 } },
	-- Rooted (perk): +1 stability
	["TRAIT-P-110"] = { stability = 1 },
	-- Toppling (flaw): -1 stability
	["TRAIT-F-110"] = { stability = -1 },
	-- Spear Specialist (perk): When wielding a Spear: weapon base damage +25% and weapon WT -25%.
	["TRAIT-P-113"] = { weaponSpec = { dmg = 0.25, weapon = "Spear", wt = -0.25 } },
	-- Spear Klutz (flaw): When wielding a Spear: weapon base damage -25% and weapon WT +25%.
	["TRAIT-F-113"] = { weaponSpec = { dmg = -0.25, weapon = "Spear", wt = 0.25 } },
	-- Staff Specialist (perk): When wielding a Staff: weapon base damage +25% and weapon WT -25%.
	["TRAIT-P-115"] = { weaponSpec = { dmg = 0.25, weapon = "Staff", wt = -0.25 } },
	-- Staff Klutz (flaw): When wielding a Staff: weapon base damage -25% and weapon WT +25%.
	["TRAIT-F-115"] = { weaponSpec = { dmg = -0.25, weapon = "Staff", wt = 0.25 } },
	-- Stalwart (perk): VIT +10%, STR +10%
	["TRAIT-P-116"] = { statPct = { STR = 0.1, VIT = 0.1 } },
	-- Weakened Core (flaw): VIT -10%, STR -10%
	["TRAIT-F-116"] = { statPct = { STR = -0.1, VIT = -0.1 } },
	-- Sword Breaker Specialist (perk): When wielding a Sword Breaker: weapon base damage +25% and weapon WT -25%.
	["TRAIT-P-119"] = { weaponSpec = { dmg = 0.25, weapon = "Sword Breaker", wt = -0.25 } },
	-- Sword Breaker Klutz (flaw): When wielding a Sword Breaker: weapon base damage -25% and weapon WT +25%.
	["TRAIT-F-119"] = { weaponSpec = { dmg = -0.25, weapon = "Sword Breaker", wt = 0.25 } },
	-- Sword Specialist (perk): When wielding a Sword: weapon base damage +25% and weapon WT -25%.
	["TRAIT-P-120"] = { weaponSpec = { dmg = 0.25, weapon = "Sword", wt = -0.25 } },
	-- Sword Klutz (flaw): When wielding a Sword: weapon base damage -25% and weapon WT +25%.
	["TRAIT-F-120"] = { weaponSpec = { dmg = -0.25, weapon = "Sword", wt = 0.25 } },
	-- Tough Skin (Greater) (perk): Takes 15% less damage.
	["TRAIT-P-121"] = { recvAll = -0.15 },
	-- Thin Skin (Greater) (flaw): Takes 15% more damage.
	["TRAIT-F-121"] = { recvAll = 0.15 },
	-- Wand Specialist (perk): When wielding a Wand: weapon base damage +25% and weapon WT -25%.
	["TRAIT-P-123"] = { weaponSpec = { dmg = 0.25, weapon = "Wand", wt = -0.25 } },
	-- Wand Klutz (flaw): When wielding a Wand: weapon base damage -25% and weapon WT +25%.
	["TRAIT-F-123"] = { weaponSpec = { dmg = -0.25, weapon = "Wand", wt = 0.25 } },
	-- War Axe Specialist (perk): When wielding a War Axe: weapon base damage +25% and weapon WT -25%.
	["TRAIT-P-124"] = { weaponSpec = { dmg = 0.25, weapon = "War Axe", wt = -0.25 } },
	-- War Axe Klutz (flaw): When wielding a War Axe: weapon base damage -25% and weapon WT +25%.
	["TRAIT-F-124"] = { weaponSpec = { dmg = -0.25, weapon = "War Axe", wt = 0.25 } },
	-- Water Attunement (perk): Deals 20% more damage when attacking with Water-tagged attacks.
	["TRAIT-P-125"] = { dealtElement = { Water = 0.2 } },
	-- Water Disharmony (flaw): Deals 20% less damage when attacking with Water-tagged attacks.
	["TRAIT-F-125"] = { dealtElement = { Water = -0.2 } },
	-- Whip Specialist (perk): When wielding a Whip: weapon base damage +25% and weapon WT -25%.
	["TRAIT-P-126"] = { weaponSpec = { dmg = 0.25, weapon = "Whip", wt = -0.25 } },
	-- Whip Klutz (flaw): When wielding a Whip: weapon base damage -25% and weapon WT +25%.
	["TRAIT-F-126"] = { weaponSpec = { dmg = -0.25, weapon = "Whip", wt = 0.25 } },
	-- Wiry (perk): STR +10%, AGI +10%
	["TRAIT-P-127"] = { statPct = { AGI = 0.1, STR = 0.1 } },
	-- Scrawny (flaw): STR -10%, AGI -10%
	["TRAIT-F-127"] = { statPct = { AGI = -0.1, STR = -0.1 } },
	-- Adept (perk): Skill damage +15%
	["TRAIT-P-128"] = { dealtSkill = 0.15 },
	-- Inept (flaw): Skill damage -15%
	["TRAIT-F-128"] = { dealtSkill = -0.15 },
	-- Air Guard (perk): Damage received enemies equiped with ranged weapons reduced by 25%
	["TRAIT-P-129"] = { recvRanged = -0.25 },
	-- Exposed to Range (flaw): Damage received from enemies equipped with ranged weapons increased by 25%
	["TRAIT-F-129"] = { recvRanged = 0.25 },
	-- Diffuser (perk): received half damage from AOE attacks
	["TRAIT-P-133"] = { recvAOE = -0.5 },
	-- Fragile to Blasts (flaw): Receives 50% more damage from AOE attacks.
	["TRAIT-F-133"] = { recvAOE = 0.5 },
	-- Long Strider (Greater) (perk): +2 movement range.
	["TRAIT-P-139"] = { move = 2 },
	-- Short Strider (Greater) (flaw): -2 movement range.
	["TRAIT-F-139"] = { move = -2 },
	-- Melee Specialist (perk): Damage inflicted with melee weapon increased by 15%, damage received from melee weapon reduced by 15%
	["TRAIT-P-140"] = { dealtMelee = 0.15, recvMelee = -0.15 },
	-- Melee Clumsy (flaw): Damage inflicted with melee weapon reduced by 15%, damage received from melee weapon increased by 15%
	["TRAIT-F-140"] = { dealtMelee = -0.15, recvMelee = 0.15 },
	-- Powerful Build (Greater) (perk): +2 force
	["TRAIT-P-143"] = { force = 2 },
	-- Frail Arms (Greater) (flaw): -2 force
	["TRAIT-F-143"] = { force = -2 },
	-- Pride (Greater) (perk): Damage inflicted to higher level targets +12%
	["TRAIT-P-144"] = { dealtVsHigher = 0.12 },
	-- Humble (Greater) (flaw): Damage inflicted to higher level targets -12%
	["TRAIT-F-144"] = { dealtVsHigher = -0.12 },
	-- Rooted (Greater) (perk): +2 stability
	["TRAIT-P-146"] = { stability = 2 },
	-- Toppling (Greater) (flaw): -2 stability
	["TRAIT-F-146"] = { stability = -2 },
	-- Toxin Filter (perk): DOT damage reduced by half
	["TRAIT-P-150"] = { dotAll = -0.5 },
	-- Festering (flaw): DOT damage received is doubled.
	["TRAIT-F-150"] = { dotAll = 1.0 },
	-- Adept (Greater) (perk): Skill damage +18%
	["TRAIT-P-153"] = { dealtSkill = 0.18 },
	-- Inept (Greater) (flaw): Skill damage -18%
	["TRAIT-F-153"] = { dealtSkill = -0.18 },
	-- Guard Specialist (perk): Damage Reduction from guard +10%
	["TRAIT-P-159"] = { guardBonus = 0.1 },
	-- Guard Klutz (flaw): Damage Reduction from guard -10%
	["TRAIT-F-159"] = { guardBonus = -0.1 },
	-- Melee Specialist (Greater) (perk): Damage inflicted with melee weapon increased by 18%, damage received from melee weapon reduced by 15%
	["TRAIT-P-161"] = { dealtMelee = 0.18, recvMelee = -0.15 },
	-- Melee Clumsy (Greater) (flaw): Damage inflicted with melee weapon reduced by 18%, damage received from melee weapon increased by 15%
	["TRAIT-F-161"] = { dealtMelee = -0.18, recvMelee = 0.15 },
	-- Elemental Mastery (perk): All elemental damage dealt +18%, elemental damage received -8%
	["TRAIT-P-172"] = { dealtElemental = 0.18, recvElemental = -0.08 },
	-- Elemental Mastery (flaw) (flaw): All elemental damage received +20%
	["TRAIT-F-172"] = { recvElemental = 0.2 },
	-- Guard Specialist (Greater) (perk): Damage Reduction from guard +12%
	["TRAIT-P-173"] = { guardBonus = 0.12 },
	-- Guard Klutz (Greater) (flaw): Damage Reduction from guard -12%
	["TRAIT-F-173"] = { guardBonus = -0.12 },
	-- Overwhelming Force (flaw) (flaw): Force -3
	["TRAIT-F-176"] = { force = -3 },
	-- Overwhelming Force (perk): Force +2 (melee Basic Attack Knockback handled in Phase 3)
	["TRAIT-P-176"] = { force = 2 },
	-- Ironhide (perk): 20% of total non-weapon WT added as base armor
	["TRAIT-P-034"] = { armorFromWtFrac = 0.20 },
	-- Brittle Plating (flaw): 20% of total non-weapon WT subtracted from base armor
	["TRAIT-F-034"] = { armorFromWtFrac = -0.20 },
	-- Ironhide (Greater) (perk): 25% of total non-weapon WT added as base armor
	["TRAIT-P-092"] = { armorFromWtFrac = 0.25 },
	-- Brittle Plating (Greater) (flaw): 25% of total non-weapon WT subtracted from base armor
	["TRAIT-F-092"] = { armorFromWtFrac = -0.25 },
	-- Strong Back (perk): Gear WT reduced by 20%, that amount added to STR bonus
	["TRAIT-P-043"] = { gearWtStrFrac = 0.20 },
	-- Weak Grip (flaw): Gear WT increased by 20%, that amount subtracted from STR bonus
	["TRAIT-F-043"] = { gearWtStrFrac = -0.20 },
	-- Strong Back (Greater) (perk): Gear WT reduced by 25%, that amount added to STR bonus
	["TRAIT-P-118"] = { gearWtStrFrac = 0.25 },
	-- Weak Grip (Greater) (flaw): Gear WT increased by 25%, that amount subtracted from STR bonus
	["TRAIT-F-118"] = { gearWtStrFrac = -0.25 },
	-- ===== Phase 3: conditional dealt-damage traits (applied via ctx in GetDamageDealtModifier) =====
	-- Adrenaline / Glass Nerves: +/- damage while below half HP.
	["TRAIT-P-002"] = { dealtBelowHp = 0.15, dealtBelowHpThresh = 0.5 },
	["TRAIT-F-002"] = { dealtBelowHp = -0.15, dealtBelowHpThresh = 0.5 },
	["TRAIT-P-048"] = { dealtBelowHp = 0.20, dealtBelowHpThresh = 0.5 },
	["TRAIT-F-048"] = { dealtBelowHp = -0.20, dealtBelowHpThresh = 0.5 },
	-- Berserker Blood / Meek Blood: final damage +/-20% below 30% (Greater 36%).
	["TRAIT-P-154"] = { dealtBelowHp = 0.20, dealtBelowHpThresh = 0.30 },
	["TRAIT-F-154"] = { dealtBelowHp = -0.20, dealtBelowHpThresh = 0.30 },
	["TRAIT-P-169"] = { dealtBelowHp = 0.20, dealtBelowHpThresh = 0.36 },
	["TRAIT-F-169"] = { dealtBelowHp = -0.20, dealtBelowHpThresh = 0.36 },
	-- Backstabber / Scrupulous: +/- damage attacking from side or behind.
	["TRAIT-P-004"] = { dealtSideBack = 0.15 },
	["TRAIT-F-004"] = { dealtSideBack = -0.15 },
	["TRAIT-P-052"] = { dealtSideBack = 0.20 },
	["TRAIT-F-052"] = { dealtSideBack = -0.20 },
	-- Ambusher / Exposed: +/- per elevation level when TARGET is higher.
	["TRAIT-P-050"] = { dealtPerElevTargetHigher = 0.08 },
	["TRAIT-F-050"] = { dealtPerElevTargetHigher = -0.08 },
	["TRAIT-P-130"] = { dealtPerElevTargetHigher = 0.11 },
	["TRAIT-F-130"] = { dealtPerElevTargetHigher = -0.11 },
	-- High Ground / Downhill Struggle: +/- per elevation level when TARGET is lower.
	["TRAIT-P-087"] = { dealtPerElevTargetLower = 0.05 },
	["TRAIT-F-087"] = { dealtPerElevTargetLower = -0.05 },
	["TRAIT-P-136"] = { dealtPerElevTargetLower = 0.07 },
	["TRAIT-F-136"] = { dealtPerElevTargetLower = -0.07 },
	-- Opportunist / Merciful: +/- damage vs targets suffering a debuff (DB: 10%, Greater 12%).
	["TRAIT-P-039"] = { dealtVsDebuffed = 0.10 },
	["TRAIT-F-039"] = { dealtVsDebuffed = -0.10 },
	["TRAIT-P-103"] = { dealtVsDebuffed = 0.12 },
	["TRAIT-F-103"] = { dealtVsDebuffed = -0.12 },
	-- Crowd Fighter / Claustrophobic: +/- per enemy within 2 range.
	["TRAIT-P-013"] = { dealtPerEnemyNear = 0.05 },
	["TRAIT-F-013"] = { dealtPerEnemyNear = -0.05 },
	["TRAIT-P-067"] = { dealtPerEnemyNear = 0.07 },
	["TRAIT-F-067"] = { dealtPerEnemyNear = -0.07 },
	-- Slayer / Pacifist: +/- per enemy killed this battle.
	["TRAIT-P-111"] = { dealtPerKill = 0.05 },
	["TRAIT-F-111"] = { dealtPerKill = -0.05 },
	["TRAIT-P-147"] = { dealtPerKill = 0.06 },
	["TRAIT-F-147"] = { dealtPerKill = -0.06 },
	-- Determined / Coward: Defense +/-30% while below 30% HP (Greater 36%).
	["TRAIT-P-158"] = { defBelowHp = 0.30, defBelowHpThresh = 0.30 },
	["TRAIT-F-158"] = { defBelowHp = -0.30, defBelowHpThresh = 0.30 },
	["TRAIT-P-170"] = { defBelowHp = 0.30, defBelowHpThresh = 0.36 },
	["TRAIT-F-170"] = { defBelowHp = -0.30, defBelowHpThresh = 0.36 },
	-- Lifesteal (perk) / Lifeless (flaw): heal / recoil as fraction of direct damage dealt.
	-- Lifeless recoil = half the paired Lifesteal, applied non-lethally by the caller.
	["TRAIT-P-160"] = { lifestealFrac = 0.08 },
	["TRAIT-F-160"] = { recoilFrac = 0.04 },
	["TRAIT-P-174"] = { lifestealFrac = 0.096 },
	["TRAIT-F-174"] = { recoilFrac = 0.048 },
	-- On-KO-of-enemy (killer side). Fractions of killer MAX HP/MP; mpLossFrac of CURRENT MP.
	-- Bloodbath: heal 15%/18% maxHP. Soul Charge: restore 15%/18% maxMP. Soul Harvest:
	-- heal 12% + 8% MP. Momentum: +1 AP (once/turn). Mana Leak (flaw): lose 15%/18% MP.
	["TRAIT-P-131"] = { koHealFrac = 0.15 },
	["TRAIT-P-156"] = { koHealFrac = 0.18 },
	["TRAIT-P-148"] = { koMpFrac = 0.15 },
	["TRAIT-P-165"] = { koMpFrac = 0.18 },
	["TRAIT-P-177"] = { koHealFrac = 0.12, koMpFrac = 0.08 },
	["TRAIT-P-162"] = { koApGain = 1 },
	["TRAIT-F-148"] = { koMpLossFrac = 0.15 },
	["TRAIT-F-165"] = { koMpLossFrac = 0.18 },
	-- Battle Focus (perk) / Mana-Starved (flaw): +/- MP = frac of maxMP per remaining AP at end of turn.
	["TRAIT-P-006"] = { endTurnMpPerApFrac = 0.05 },
	["TRAIT-F-006"] = { endTurnMpPerApFrac = -0.05 },
	["TRAIT-P-053"] = { endTurnMpPerApFrac = 0.10 },
	["TRAIT-F-053"] = { endTurnMpPerApFrac = -0.10 },
	-- Iron Will (perk) / Susceptible (flaw): debuff duration -1 / +1 turn (or ∓400 CT).
	["TRAIT-P-033"] = { debuffDurationTurns = -1 },
	["TRAIT-F-033"] = { debuffDurationTurns = 1 },
	-- On-hit-received / on-KO debuff traits (random debuff from a curated pool).
	-- Defenseless (flaw): when attacked, inflict 1 random debuff on SELF.
	["TRAIT-F-145"] = { selfDebuffOnHit = true },
	-- Lingering Curse (flaw): being attacked applies 1 random debuff to SELF (same hook).
	["TRAIT-F-132"] = { selfDebuffOnHit = true },
	-- Retaliator (perk): when attacked, inflict a debuff on the ATTACKER (rolled per unit).
	["TRAIT-P-145"] = { debuffAttackerOnHit = true },
	-- Cleanse (perk): on KO of an enemy, remove 1 random active debuff from SELF.
	["TRAIT-P-132"] = { cleanseOnKill = true },
	-- Wrathful (perk) / Meek (flaw): each time attacked, accumulate a damage-dealt
	-- +/- % that stacks and clears at end of the unit's NEXT turn. Per-attack step:
	["TRAIT-P-152"] = { combatStackPerHit = 0.10 },
	["TRAIT-F-152"] = { combatStackPerHit = -0.05 },
	["TRAIT-P-167"] = { combatStackPerHit = 0.12 },
	["TRAIT-F-167"] = { combatStackPerHit = -0.06 },
}
TraitEffectService.EFFECTS = EFFECTS

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local STATS = { "STR", "AGI", "INT", "VIT", "DEX", "LUK" }

-- All Phase-2 effect entries for this unit's traits (perk + flaw), by trait_id.
local function collect(unit)
	local out = {}
	if type(unit) ~= "table" then return out end
	local lists = { unit.perkIds, unit.drawbackIds }
	for li = 1, 2 do
		local list = lists[li]
		if type(list) == "table" then
			for _, tid in ipairs(list) do
				if TraitData.GetTrait(tid) then
					local eff = EFFECTS[tid]
					if eff then
						table.insert(out, eff)
					end
				end
			end
		end
	end
	return out
end

-- Break status disables inherent unit perks / drawbacks (combat-time getters only).
local function isBroken(unit)
	if type(unit) ~= "table" or type(unit.statusInstances) ~= "table" then return false end
	for _, inst in ipairs(unit.statusInstances) do
		if inst.id == "Break" then return true end
	end
	return false
end

local NONE = {}
local function active(unit)
	if isBroken(unit) then return NONE end
	return collect(unit)
end

local function isElemental(element)
	return element ~= nil and element ~= "Physical" and element ~= ""
end

-- Weapon class: ranged = the equipped weapon profile has a projectileType
-- (Direct / Arc / Channeled); melee = no projectileType (incl. unarmed).
local function wieldsRanged(unit)
	return type(unit) == "table" and unit.weaponProjectileType ~= nil
end
local function wieldsMelee(unit)
	return type(unit) == "table" and unit.weaponProjectileType == nil
end

local function mainHandWeaponName(unit)
	local mh = type(unit) == "table" and unit.equipmentSlots and unit.equipmentSlots.MainHand
	if not mh then return nil end
	local arch = WeaponData.GetByArchetypeId(mh.baseArchetypeId)
	return arch and arch.name or nil
end

local function productOf(effs, field)
	local m = 1.0
	for _, e in ipairs(effs) do
		local v = e[field]
		if v then m = m * (1 + v) end
	end
	return m
end

local function sumOf(effs, field)
	local s = 0
	for _, e in ipairs(effs) do
		local v = e[field]
		if v then s = s + v end
	end
	return s
end

--------------------------------------------------
-- REBUILD-TIME (static) MODIFIERS -- EquipmentService.RebuildUnitStats
--------------------------------------------------

-- { STAT = offset } or nil. Applied as round(total * (1 + offset)) right after
-- the race stat fold (step 3b) in RebuildUnitStats.
function TraitEffectService.GetStatModifiers(unit)
	local effs = collect(unit)
	local mods, any = {}, false
	for _, e in ipairs(effs) do
		if e.statPct then
			for _, stat in ipairs(STATS) do
				local v = e.statPct[stat]
				if v then
					mods[stat] = (mods[stat] or 0) + v
					any = true
				end
			end
		end
	end
	return any and mods or nil
end

-- Hardy / Frail: multiplier on the VIT term of Max HP (50 + VIT*4*m + armor HP).
function TraitEffectService.GetHpFromVitMultiplier(unit)
	return math.max(0, 1 + sumOf(collect(unit), "hpFromVit"))
end

-- Deep Well / Shallow Well: multiplier on the INT term of Max MP (20 + INT*2*m + armor MP).
function TraitEffectService.GetMpFromIntMultiplier(unit)
	return math.max(0, 1 + sumOf(collect(unit), "mpFromInt"))
end

-- <Slot> Specialist (x2) / <Slot> Klutz (x0.5): multiplier on that armor piece's
-- numerical Base (Defense / HP / MP) and Bonus (primary-stat bonus lines) stats.
-- NOTE: armor WT is NOT scaled (WT is a burden, not a stat; doubling it would
-- turn the perk into a penalty) -- flagged for design confirmation.
function TraitEffectService.GetArmorSlotMultiplier(unit, slot)
	if not slot then return 1.0 end
	local m = 1.0
	for _, e in ipairs(collect(unit)) do
		local t = e.armorSlotMult
		if t and t[slot] then m = m * t[slot] end
	end
	return m
end

-- Defensive / Exposed Armor: multiplier on summed armor Defense.
function TraitEffectService.GetArmorDefenseMultiplier(unit)
	return math.max(0, productOf(collect(unit), "armorDefense"))
end

-- Ironhide / Brittle Plating: +/- fraction of total non-weapon (armor) WT added to
-- base armor defense. Returns a signed fraction (e.g. 0.20, 0.25, -0.20, -0.25);
-- the caller multiplies it by the summed armor WT and rounds. Neutral = 0.
function TraitEffectService.GetArmorFromWtFraction(unit)
	return sumOf(collect(unit), "armorFromWtFrac")
end

-- Strong Back / Weak Grip: Gear (weapon) WT changed by -/+ fraction, and the magnitude
-- of that WT change is added to / subtracted from STR. Returns a signed fraction:
--   Strong Back  +0.20/+0.25  -> weapon WT x(1 - frac), STR += round(rawWt * frac)
--   Weak Grip    -0.20/-0.25  -> weapon WT x(1 - frac) = x(1 + |frac|), STR -= round(rawWt * |frac|)
-- Caller applies both halves atomically. Neutral = 0.
function TraitEffectService.GetGearWtStrFraction(unit)
	return sumOf(collect(unit), "gearWtStrFrac")
end

-- <Weapon> Specialist / Klutz: (damageMult, wtMult) for the equipped MainHand.
local function weaponSpecMults(unit)
	local name = mainHandWeaponName(unit)
	if not name then return 1.0, 1.0 end
	local dm, wm = 1.0, 1.0
	for _, e in ipairs(collect(unit)) do
		local ws = e.weaponSpec
		if ws and ws.weapon == name then
			dm = dm * (1 + (ws.dmg or 0))
			wm = wm * (1 + (ws.wt or 0))
		end
	end
	return math.max(0, dm), math.max(0, wm)
end

-- Weapon WT multiplier (mirrors RacePassiveService.GetWeaponWtMultiplier).
function TraitEffectService.GetWeaponWtMultiplier(unit)
	local _, wm = weaponSpecMults(unit)
	return wm
end

-- Base weapon damage multiplier (weapon specialists).
function TraitEffectService.GetWeaponDamageMultiplier(unit)
	local dm = weaponSpecMults(unit)
	return dm
end

-- Heavy Hitter / Feather Strikes: fraction of weapon WT added to (or, negative,
-- subtracted from) base weapon damage.
function TraitEffectService.GetWeaponWtDamageFraction(unit)
	return sumOf(collect(unit), "wtToDamage")
end

-- Powerful Build / Frail Arms / Overwhelming Force (flaw): flat Force offset.
function TraitEffectService.GetForceModifier(unit)
	return sumOf(collect(unit), "force")
end

-- Rooted / Toppling: flat Stability offset.
function TraitEffectService.GetStabilityModifier(unit)
	return sumOf(collect(unit), "stability")
end

--------------------------------------------------
-- COMBAT-TIME MODIFIERS (Break-aware)
--------------------------------------------------

-- Multiplier on final damage dealt by this unit. Folded next to
-- RacePassiveService.GetDamageDealtModifier in CombatResolver.
--   element: attack element ("Physical" / nil = non-elemental)
--   isAOE:   AOE attack (unused by Phase-2 dealt traits; kept for signature parity)
--   targetUnit: defender (level compare)
--   isSkill: true for skills, false for Basic Attacks
function TraitEffectService.GetDamageDealtModifier(attacker, element, isAOE, targetUnit, isSkill, ctx)
	local effs = active(attacker)
	if #effs == 0 then return 1.0 end
	local mod = 1.0
	local aLvl = attacker.level
	local tLvl = type(targetUnit) == "table" and targetUnit.level or nil
	for _, e in ipairs(effs) do
		if e.dealtVsLower and aLvl and tLvl and tLvl < aLvl then
			mod = mod * (1 + e.dealtVsLower)
		end
		if e.dealtVsHigher and aLvl and tLvl and tLvl > aLvl then
			mod = mod * (1 + e.dealtVsHigher)
		end
		if e.dealtElement and element and e.dealtElement[element] then
			mod = mod * (1 + e.dealtElement[element])
		end
		if e.dealtElemental and isElemental(element) then
			mod = mod * (1 + e.dealtElemental)
		end
		if e.dealtSkill and isSkill then
			mod = mod * (1 + e.dealtSkill)
		end
		if e.dealtMelee and wieldsMelee(attacker) then
			mod = mod * (1 + e.dealtMelee)
		end
		-- Phase 3 conditional dealt-damage traits. ctx (optional) carries battlefield
		-- facts computed by the caller (CombatResolver): hpFrac (attacker HP fraction),
		-- facingSideBack (bool), elevDiff (target elev - attacker elev), targetDebuffed
		-- (bool), enemiesWithin2 (count), killCount (this unit's kills this battle).
		if ctx then
			-- Adrenaline / Glass Nerves, Berserker Blood / Meek Blood: below-X%-HP damage.
			if e.dealtBelowHp and ctx.hpFrac and ctx.hpFrac < (e.dealtBelowHpThresh or 0.5) then
				mod = mod * (1 + e.dealtBelowHp)
			end
			-- Backstabber / Scrupulous: side/back attacks.
			if e.dealtSideBack and ctx.facingSideBack then
				mod = mod * (1 + e.dealtSideBack)
			end
			-- Ambusher / Exposed (target higher): per-elevation-level when target above.
			if e.dealtPerElevTargetHigher and ctx.elevDiff and ctx.elevDiff > 0 then
				mod = mod * (1 + e.dealtPerElevTargetHigher * ctx.elevDiff)
			end
			-- High Ground / Downhill Struggle (target lower): per-level when target below.
			if e.dealtPerElevTargetLower and ctx.elevDiff and ctx.elevDiff < 0 then
				mod = mod * (1 + e.dealtPerElevTargetLower * (-ctx.elevDiff))
			end
			-- Opportunist / Merciful: target afflicted with a debuff.
			if e.dealtVsDebuffed and ctx.targetDebuffed then
				mod = mod * (1 + e.dealtVsDebuffed)
			end
			-- Crowd Fighter / Claustrophobic: per enemy within 2 range of attacker.
			if e.dealtPerEnemyNear and ctx.enemiesWithin2 and ctx.enemiesWithin2 > 0 then
				mod = mod * (1 + e.dealtPerEnemyNear * ctx.enemiesWithin2)
			end
			-- Slayer / Pacifist: per enemy this unit has killed this battle.
			if e.dealtPerKill and ctx.killCount and ctx.killCount > 0 then
				mod = mod * (1 + e.dealtPerKill * ctx.killCount)
			end
		end
	end
	-- Wrathful / Meek accumulated bonus: the running total built on-hit (combatStackPct)
	-- applies to all damage this unit deals until it decays at the unit's next turn end.
	if attacker.combatStackPct and attacker.combatStackPct ~= 0 then
		mod = mod * (1 + attacker.combatStackPct)
	end
	return math.max(0, mod)
end

-- Determined / Coward: Defense +/-30% while below a HP threshold (30%, Greater 36%).
-- Returns a multiplier on the defender's effective defense (NOT on damage), applied
-- alongside StatusService.GetDefenseMultiplier in the resolver. hpFrac is the
-- defender's current HP fraction (caller-supplied). Neutral 1.0.
function TraitEffectService.GetDefenseMultiplier(defender, hpFrac)
	local effs = active(defender)
	if #effs == 0 or not hpFrac then return 1.0 end
	local m = 1.0
	for _, e in ipairs(effs) do
		if e.defBelowHp and hpFrac < (e.defBelowHpThresh or 0.3) then
			m = m * (1 + e.defBelowHp)
		end
	end
	return math.max(0, m)
end

-- Multiplier on final direct damage received by this unit. Folded next to
-- RacePassiveService.GetDamageReceivedModifier in CombatResolver.
--   attacker (optional): source unit, for melee / ranged weapon-class traits.
function TraitEffectService.GetDamageReceivedModifier(defender, element, isAOE, isPhysical, attacker)
	local effs = active(defender)
	if #effs == 0 then return 1.0 end
	local mod = 1.0
	for _, e in ipairs(effs) do
		if e.recvAll then
			mod = mod * (1 + e.recvAll)
		end
		if e.recvElement and element and e.recvElement[element] then
			mod = mod * (1 + e.recvElement[element])
		end
		if e.recvElemental and isElemental(element) then
			mod = mod * (1 + e.recvElemental)
		end
		if e.recvAOE and isAOE then
			mod = mod * (1 + e.recvAOE)
		end
		if e.recvMelee and attacker and wieldsMelee(attacker) then
			mod = mod * (1 + e.recvMelee)
		end
		if e.recvRanged and attacker and wieldsRanged(attacker) then
			mod = mod * (1 + e.recvRanged)
		end
	end
	return math.max(0, mod)
end

-- Multiplier on a DoT tick of statusId received by this unit (StatusService.
-- ProcessStartOfTurn). Live today for Poison / Burn ticks; Venom / Bleed entries
-- are mapped but DORMANT until those statuses deal tick damage.
function TraitEffectService.GetDotDamageReceivedModifier(unit, statusId)
	local effs = active(unit)
	if #effs == 0 then return 1.0 end
	local mod = 1.0
	for _, e in ipairs(effs) do
		if e.dotAll then
			mod = mod * (1 + e.dotAll)
		end
		if e.dotStatus and statusId and e.dotStatus[statusId] then
			mod = mod * (1 + e.dotStatus[statusId])
		end
	end
	return math.max(0, mod)
end

-- Blessed Recovery / Cursed Wounds: multiplier on skill healing received.
function TraitEffectService.GetHealingReceivedModifier(unit)
	return math.max(0, productOf(active(unit), "healRecv"))
end

-- Economist / Spendthrift: multiplier on skill MP cost.
function TraitEffectService.GetMpCostModifier(unit)
	return math.max(0, productOf(active(unit), "mpCost"))
end

-- Basics / Heavy Basics: multiplier on the Basic Attack weapon-WT RT term.
function TraitEffectService.GetBasicAttackWtMultiplier(unit)
	local m = 1.0
	for _, e in ipairs(active(unit)) do
		if e.basicWtMult then m = m * e.basicWtMult end
	end
	return math.max(0, m)
end

-- Guard Specialist / Klutz: additive Guard mitigation bonus.
function TraitEffectService.GetGuardMitigationBonus(unit)
	return sumOf(active(unit), "guardBonus")
end

-- Long Strider / Short Strider: integer Movement Range offset.
function TraitEffectService.GetMovementRangeModifier(unit)
	return sumOf(active(unit), "move")
end

-- High Jumper / Stubby Legs: integer Jump offset.
function TraitEffectService.GetJumpModifier(unit)
	return sumOf(active(unit), "jump")
end

-- Fast Learner / Slow Learner: battle-XP multiplier.
-- STUB: no per-unit battle-XP award hook exists in source yet, so nothing calls
-- this. Nil-safe; returns 1.0 for units without these traits.
function TraitEffectService.GetXpGainMultiplier(unit)
	return math.max(0, productOf(collect(unit), "xpGain"))
end

-- ===== PHASE 2b getters (derived-stat / RT) =====

-- Precision additive offset (Keen Aim / Clumsy). Feeds Hit Quality.
function TraitEffectService.GetPrecisionModifier(unit)
	return sumOf(active(unit), "precision")
end

-- Evasiveness additive offset (Light Step / Heavy-Footed). Feeds Hit Quality.
function TraitEffectService.GetEvasivenessModifier(unit)
	return sumOf(active(unit), "evasiveness")
end

-- Hit Quality flat offset, gated by attack type. isRanged=true → ranged traits,
-- else melee traits. Returns an additive delta to the ~1.0-centered Hit Quality.
function TraitEffectService.GetHitQualityModifier(unit)
	-- Melee vs ranged is determined by the equipped weapon's projectile type
	-- (ranged = has a projectileType; melee = none), NOT by weapon reach — Spear/
	-- Whip/Chains have range >1 but are MELEE. Mirrors wieldsRanged/wieldsMelee used
	-- by the Phase-2 melee/ranged damage traits.
	local key = wieldsRanged(unit) and "hqRanged" or "hqMelee"
	return sumOf(active(unit), key)
end

-- Base RT multiplier (Quick/Sluggish/Timeline Sovereign/Temporal Drag).
-- Returns a multiplier: 1 + sum(baseRtMult). Lower = acts sooner.
function TraitEffectService.GetBaseRtMultiplier(unit)
	return 1 + sumOf(active(unit), "baseRtMult")
end

-- Starting RT multiplier (Timeline Sovereign/Temporal Drag). 1 + sum(startRtMult).
function TraitEffectService.GetStartingRtMultiplier(unit)
	return 1 + sumOf(active(unit), "startRtMult")
end

-- Channel-time multiplier (Channeler/Slow Channeler). 1 + sum(channelMult).
function TraitEffectService.GetChannelTimeMultiplier(unit)
	return math.max(0, 1 + sumOf(active(unit), "channelMult"))
end

-- Skill activation/delay multiplier (Flash-Caster/Laggy Caster). 1 + sum(skillDelayMult).
function TraitEffectService.GetSkillDelayMultiplier(unit)
	return math.max(0, 1 + sumOf(active(unit), "skillDelayMult"))
end

-- RT-delay-inflicted multiplier (Time Locker/Time Freed/Timeline Sovereign).
-- Applies to RT delay this unit inflicts on others. 1 + sum(rtDelayInflictMult).
function TraitEffectService.GetRtDelayInflictMultiplier(unit)
	return math.max(0, 1 + sumOf(active(unit), "rtDelayInflictMult"))
end

-- Movement RT multiplier (Fleet Runner/Plodding). 1 + sum(moveRtMult).
function TraitEffectService.GetMoveRtMultiplier(unit)
	return math.max(0, 1 + sumOf(active(unit), "moveRtMult"))
end

-- Discovery radius additive offset (Far/Near-Sighted). Floored to integer by caller if needed.
function TraitEffectService.GetDiscoveryRadiusModifier(unit)
	return sumOf(active(unit), "discoveryRadius")
end

-- Interact range additive offset (Long/Short Reach).
function TraitEffectService.GetInteractRangeModifier(unit)
	return sumOf(active(unit), "interactRange")
end

-- Terrain movement-cost handling (Pathfinder ignores +costs; Bogged Down +50%).
-- Returns (ignoreTerrainCost: bool, extraMult: number). extraMult is 1 + sum(terrainCostMult).
function TraitEffectService.GetTerrainCostModifier(unit)
	local list = active(unit)
	local ignore = false
	for _, e in ipairs(list) do
		if e.terrainCostIgnore then ignore = true end
	end
	return ignore, math.max(0, 1 + sumOf(list, "terrainCostMult"))
end

-- Skill RT cost multiplier (Arcane Prodigy). 1 + sum(skillRtMult).
function TraitEffectService.GetSkillRtMultiplier(unit)
	return math.max(0, 1 + sumOf(active(unit), "skillRtMult"))
end

-- Skill potency additive % (Arcane Prodigy). Additive to the skill-potency bonus.
function TraitEffectService.GetSkillPotencyModifier(unit)
	return sumOf(active(unit), "skillPotencyPct")
end

-- Lifesteal (perk): heal attacker for a fraction of direct damage dealt.
-- Returns the heal amount (rounded), or 0. Mirrors RacePassiveService lifesteal.
function TraitEffectService.GetLifestealAmount(attacker, actualDamage)
	if not actualDamage or actualDamage <= 0 then return 0 end
	local frac = sumOf(active(attacker), "lifestealFrac")
	if frac <= 0 then return 0 end
	return math.round(actualDamage * frac)
end

-- Lifeless (flaw): recoil self-damage = fraction of direct damage dealt. Returns the
-- recoil amount (rounded, non-negative). Caller MUST apply it non-lethally (never
-- below 1 HP). Half of the paired Lifesteal value (4% / 4.8%).
function TraitEffectService.GetRecoilAmount(attacker, actualDamage)
	if not actualDamage or actualDamage <= 0 then return 0 end
	local frac = sumOf(active(attacker), "recoilFrac")
	if frac <= 0 then return 0 end
	return math.round(actualDamage * frac)
end

-- On-KO-of-enemy effects (killer side). Returns a table of deltas to apply when THIS
-- unit kills an enemy: { healFrac, mpFrac, apGain, mpLossFrac }. Fractions are of the
-- killer's MAX HP/MP (mpLossFrac is of CURRENT MP). apGain is "once per turn" — caller
-- enforces the per-turn guard. Covers Bloodbath, Soul Charge, Soul Harvest, Momentum,
-- Mana Leak (flaw). Neutral = all zero.
function TraitEffectService.GetOnKillEffects(killer)
	local effs = active(killer)
	local out = { healFrac = 0, mpFrac = 0, apGain = 0, mpLossFrac = 0 }
	for _, e in ipairs(effs) do
		if e.koHealFrac then out.healFrac = out.healFrac + e.koHealFrac end
		if e.koMpFrac then out.mpFrac = out.mpFrac + e.koMpFrac end
		if e.koApGain then out.apGain = out.apGain + e.koApGain end
		if e.koMpLossFrac then out.mpLossFrac = out.mpLossFrac + e.koMpLossFrac end
	end
	return out
end

-- Battle Focus / Mana-Starved: at end of turn, recover / lose MP = fraction of MAX MP
-- per remaining AP. Returns the signed per-AP fraction (sum of all such traits).
-- Caller multiplies by remaining AP and by maxMp. Neutral = 0.
function TraitEffectService.GetEndTurnMpPerApFraction(unit)
	return sumOf(active(unit), "endTurnMpPerApFrac")
end

-- Iron Will / Susceptible: debuff duration reduced / increased by 1 turn (or 400 CT for
-- CT-based debuffs). Returns the signed turn offset (sum). Iron Will = -1, Susceptible
-- = +1. Caller applies it only to DEBUFF statuses, to turns or CT as appropriate.
-- Neutral = 0. Uses active() so a Broken unit's trait is suppressed (combat-time getter).
function TraitEffectService.GetDebuffDurationTurnOffset(unit)
	return sumOf(active(unit), "debuffDurationTurns")
end

-- Curated pool of "ailment" debuffs that are reasonable to inflict at random. Excludes
-- hard-CC / structural / environment-driven statuses (Petrify, Sleep, Stun, Break,
-- Drowning, Sinking, Wet, Frozen, Petrify, Mana Burn, Cursed Aura) so a random roll
-- can't hand out a turn-skip or passive-disable. Used by Defenseless / Lingering Curse
-- (self) and Retaliator (attacker).
local RANDOM_DEBUFF_POOL = {
	"Slow", "Poison", "Burn", "Bleed", "Blind",
	"Confuse", "Silence", "Disarmed", "Pinned", "Crippled", "Weakened",
}

-- Pick one random debuff id from the curated pool.
function TraitEffectService.RollRandomDebuff()
	return RANDOM_DEBUFF_POOL[math.random(1, #RANDOM_DEBUFF_POOL)]
end

-- Defenseless / Lingering Curse: true if the unit should take a random self-debuff
-- when attacked (damage received).
function TraitEffectService.HasSelfDebuffOnHit(unit)
	for _, e in ipairs(active(unit)) do
		if e.selfDebuffOnHit then return true end
	end
	return false
end

-- Retaliator: true if the unit inflicts a debuff on its attacker when hit. The specific
-- debuff is "rolled per unit" — cached on unit.retaliatorDebuff the first time (stable
-- for the unit's lifetime), rolled from the curated pool.
function TraitEffectService.HasDebuffAttackerOnHit(unit)
	for _, e in ipairs(active(unit)) do
		if e.debuffAttackerOnHit then return true end
	end
	return false
end

-- Cleanse: true if the unit removes 1 random active debuff from itself on killing an enemy.
function TraitEffectService.HasCleanseOnKill(unit)
	for _, e in ipairs(active(unit)) do
		if e.cleanseOnKill then return true end
	end
	return false
end

-- Wrathful / Meek: the per-attack damage-dealt step (summed; Wrathful +, Meek -). The
-- caller accumulates it onto unit.combatStackPct when the unit is attacked, applies the
-- running total as a damage-dealt multiplier, and decays it at the unit's next turn end.
function TraitEffectService.GetCombatStackPerHit(unit)
	return sumOf(active(unit), "combatStackPerHit")
end

return TraitEffectService
