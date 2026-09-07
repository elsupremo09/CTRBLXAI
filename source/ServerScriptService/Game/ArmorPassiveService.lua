-- ArmorPassiveService.lua
-- CTRBLXAI | Armor Passive Functions (all 101 armor passives)
--
-- Centralized query interface for armor passive effects.
-- Other services call these to apply armor-based modifiers.
-- Units without armor in a given slot receive neutral (no-op) values.
--
-- Slot → Action Ownership:
--   Head      → Interact  (20 passives: HD-001 … HD-020)
--   Body      → Guard     (20 passives: BD-001 … BD-020)
--   Gloves    → Push      (21 passives: GL-001 … GL-021)
--   Feet      → Move      (20 passives: FT-001 … FT-020)
--   Accessory → Item      (20 passives: AC-001 … AC-020)
--
-- Per-battle state uses _armor* prefix on unit table.
-- OnBattleStart MUST be called at battle start.
-- OnTurnStart MUST be called at start of each unit turn.
--
-- Hook sites:
--   CommandService     → Interact, Guard, Push, Move, Item resolution
--   CombatResolver     → damage modifiers, collision, on-hit, lethal survive
--   TargetingService   → range / movement / jump modifiers
--   BattleCoordinator  → OnBattleStart, OnTurnStart, OnMoveCompleted, etc.

local ArmorPassiveService = {}

local ArmorData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("ArmorData")
)

--------------------------------------------------
-- PRIVATE HELPERS
--------------------------------------------------

--- Returns the archetype definition for armor in the given slot, or nil.
local function getArmorInSlot(unit, slot)
	if not unit or not unit.equipmentSlots then return nil end
	local item = unit.equipmentSlots[slot]
	if not item then return nil end
	return ArmorData.GetByArchetypeId(item.baseArchetypeId)
end

--- Returns the passiveName string for armor in the given slot, or nil.
local function getPassiveInSlot(unit, slot)
	local arch = getArmorInSlot(unit, slot)
	return arch and arch.passiveName or nil
end

--- Chebyshev distance (game standard for all range checks).
local function chebyshevDist(a, b)
	if not a or not b then return math.huge end
	if not a.tileX or not a.tileY or not b.tileX or not b.tileY then return math.huge end
	return math.max(math.abs(a.tileX - b.tileX), math.abs(a.tileY - b.tileY))
end

--- Returns true if at least one standing ally is within Chebyshev range.
local function hasAllyInRange(unit, allUnits, range)
	if not allUnits then return false end
	for _, other in ipairs(allUnits) do
		if other ~= unit
			and other.isAlive
			and other.side == unit.side
			and chebyshevDist(unit, other) <= range
		then
			return true
		end
	end
	return false
end

--------------------------------------------------
-- GENERAL PUBLIC HELPERS
--------------------------------------------------

--- Returns the armor archetype for a given slot, or nil.
function ArmorPassiveService.GetArmorInSlot(unit, slot)
	return getArmorInSlot(unit, slot)
end

--- Returns true if any equipped armor piece has the given passiveName.
function ArmorPassiveService.HasPassive(unit, passiveName)
	if not unit or not unit.equipmentSlots then return false end
	for _, slot in ipairs({"Head", "Body", "Gloves", "Feet", "Accessory"}) do
		local arch = getArmorInSlot(unit, slot)
		if arch and arch.passiveName == passiveName then
			return true
		end
	end
	return false
end

--- Reset per-battle flags. Call once at battle start for every unit.
function ArmorPassiveService.OnBattleStart(unit)
	if not unit then return end
	unit._armorLethalSurviveUsed = false   -- BD-020 Unyielding Aegis
	unit._armorReprisalStored    = 0       -- BD-009 Reprisal Coat
	unit._armorLayeredHitCount   = 0       -- BD-006 Layered Lamellar
	unit._armorAlchemistBaCount  = 0       -- AC-018 Field Alchemist Emblem
	unit._armorQmPartnerId       = nil     -- AC-019 Quartermaster Badge
end

--- Reset per-turn flags. Call at start of each unit turn.
function ArmorPassiveService.OnTurnStart(unit)
	if not unit then return end
	-- Guard
	unit._armorAutoGuardUsed       = false  -- BD-005 Reactive Cuirass
	unit._armorLayeredHitCount     = 0      -- BD-006 reset per guard session
	-- Push
	unit._armorFreePushUsed        = false  -- GL-021 Initiator's Grips
	unit._armorTilesMovedThisTurn  = 0      -- GL-018 Momentum Bracers
	-- Move
	unit._armorFirstMoveUsed       = false  -- FT-011 Sprinter Boots
	unit._armorMoveCountThisTurn   = 0      -- FT-012 Relay Boots
	unit._armorPathCostThisTurn    = 0      -- FT-008 Skirmisher Greaves
	unit._armorRetreatBonusActive  = false  -- FT-009 Retreat Boots
	unit._armorVanguardDrActive    = false  -- FT-010 Vanguard Greaves
	unit._armorPursuerUsed         = false  -- FT-017 Pursuer Greaves
	unit._armorMarchStabilityBonus = 0      -- FT-003 Heavy March Boots
	-- Item
	unit._armorAutoHealUsed        = false  -- AC-015 Emergency Locket
	unit._armorManualItemCount     = 0      -- AC-017 Conservation Charm
	unit._armorConservationUsed    = false  -- AC-017 Conservation Charm
	unit._armorBundleUsed          = false  -- AC-020 Masterwork Toolchain
end

--==========================================================
--  HEAD  ·  INTERACT  (20 passives: HD-001 … HD-020)
--==========================================================

--------------------------------------------------
-- HD-001  Quickhand Hood
-- "Interact RT ×0.75"
--------------------------------------------------
--- Returns the RT multiplier for the Interact action.
--- Default 1.0 (no change). HD-001 → 0.75.
function ArmorPassiveService.GetInteractRtModifier(unit)
	local p = getPassiveInSlot(unit, "Head")
	if p == "Interact RT \xc3\x970.75" then return 0.75 end
	return 1.0
end

--------------------------------------------------
-- HD-002  Surveyor Visor
-- "Interact Maximum Range +2"
--------------------------------------------------
--- Returns an integer offset added to Interact maximum range.
function ArmorPassiveService.GetInteractRangeModifier(unit)
	local p = getPassiveInSlot(unit, "Head")
	if p == "Interact Maximum Range +2" then return 2 end
	return 0
end

--------------------------------------------------
-- HD-003  Field Medic Coif         → revive at 15% HP
-- HD-016  Signal Officer Beret     → revive at 25% HP if ally within 2
-- HD-017  Rescue Marshal Helm      → revive at 20% HP + relocate to user
--------------------------------------------------
--- Returns a revive config table when Interact targets a KO'd ally, or nil.
--- Config: { hpPercent, requireAllyRange, relocateToUser }
--- Caller checks conditions and applies the revive.
function ArmorPassiveService.GetInteractReviveConfig(unit, target, allUnits)
	local p = getPassiveInSlot(unit, "Head")
	if not p then return nil end

	-- HD-003
	if p == "Interact revives KO'd ally at 15% HP" then
		return { hpPercent = 0.15, requireAllyRange = 0, relocateToUser = false }
	end

	-- HD-016: requires another ally within 2 tiles of the user
	if p == "Interact on KO'd ally: revive at 25% HP if within 2 tiles of another ally" then
		if hasAllyInRange(unit, allUnits, 2) then
			return { hpPercent = 0.25, requireAllyRange = 2, relocateToUser = false }
		end
		return nil -- condition not met
	end

	-- HD-017: revive + relocate target to user's tile
	if p == "Interact on KO'd ally: revive at 20% HP and immediately relocate to user's tile" then
		return { hpPercent = 0.20, requireAllyRange = 0, relocateToUser = true }
	end

	return nil
end

--------------------------------------------------
-- HD-004  Chronologist Monocle
-- "Interact on ally grants target -50 RT"
--------------------------------------------------
--- Returns the RT reduction applied to the target when Interact targets an ally.
--- 0 means no effect.
function ArmorPassiveService.GetInteractAllyRtBonus(unit)
	local p = getPassiveInSlot(unit, "Head")
	if p == "Interact on ally grants target -50 RT" then return -50 end
	return 0
end

--------------------------------------------------
-- HD-005  Recruiter's Circlet
-- "Interact on valid enemy attempts Recruitment with Success Rate +10%"
--------------------------------------------------
--- Returns the bonus percentage for recruitment success rate (0–1 float).
function ArmorPassiveService.GetInteractRecruitBonus(unit)
	local p = getPassiveInSlot(unit, "Head")
	if p == "Interact on valid enemy attempts Recruitment with Success Rate +10%" then
		return 0.10
	end
	return 0
end

--------------------------------------------------
-- HD-006  Diplomat's Veil
-- "Interact recruitment ignores hostility threshold"
--------------------------------------------------
function ArmorPassiveService.CanIgnoreRecruitHostility(unit)
	local p = getPassiveInSlot(unit, "Head")
	return p == "Interact recruitment ignores hostility threshold"
end

--------------------------------------------------
-- HD-007  Siege Gunner Helm
-- "Interact on siege/artillery object: damage ×1.5"
--------------------------------------------------
--- Returns the damage multiplier when interacting with siege/artillery objects.
function ArmorPassiveService.GetInteractSiegeDamageModifier(unit)
	local p = getPassiveInSlot(unit, "Head")
	if p == "Interact on siege/artillery object: damage \xc3\x971.5" then return 1.5 end
	return 1.0
end

--------------------------------------------------
-- HD-008  Artillerist Eyepiece
-- "Interact on siege/artillery object: range +2"
--------------------------------------------------
--- Returns the bonus range when operating siege/artillery objects.
function ArmorPassiveService.GetInteractSiegeRangeBonus(unit)
	local p = getPassiveInSlot(unit, "Head")
	if p == "Interact on siege/artillery object: range +2" then return 2 end
	return 0
end

--------------------------------------------------
-- HD-009  Demolition Mask
-- "Interact destroys breakable objects in 1 action regardless of HP"
--------------------------------------------------
function ArmorPassiveService.CanInteractBreakObjects(unit)
	local p = getPassiveInSlot(unit, "Head")
	return p == "Interact destroys breakable objects in 1 action regardless of HP"
end

--------------------------------------------------
-- HD-010  Trapfinder Goggles
-- "Interact disarms adjacent traps; reveals hidden traps within 3 tiles"
--------------------------------------------------
--- Returns a trap config or nil.
--- Config: { disarmRange = 1, revealRange = 3 }
function ArmorPassiveService.GetInteractTrapConfig(unit)
	local p = getPassiveInSlot(unit, "Head")
	if p == "Interact disarms adjacent traps; reveals hidden traps within 3 tiles" then
		return { disarmRange = 1, revealRange = 3 }
	end
	return nil
end

--------------------------------------------------
-- HD-011  Salvager's Cap
-- "Interact on destroyed objects yields bonus loot/materials"
--------------------------------------------------
function ArmorPassiveService.CanInteractBonusLoot(unit)
	local p = getPassiveInSlot(unit, "Head")
	return p == "Interact on destroyed objects yields bonus loot/materials"
end

--------------------------------------------------
-- HD-012  Locksmith Lens
-- "Interact opens locked containers without a key"
--------------------------------------------------
function ArmorPassiveService.CanInteractOpenLocks(unit)
	local p = getPassiveInSlot(unit, "Head")
	return p == "Interact opens locked containers without a key"
end

--------------------------------------------------
-- HD-013  Relic Reader Crown
-- "Interact on discovery objects reveals full information"
--------------------------------------------------
function ArmorPassiveService.CanInteractFullDiscovery(unit)
	local p = getPassiveInSlot(unit, "Head")
	return p == "Interact on discovery objects reveals full information"
end

--------------------------------------------------
-- HD-014  Hazard Warden Hood
-- "Interact on hazard tile neutralizes it permanently"
--------------------------------------------------
function ArmorPassiveService.CanInteractNeutralizeHazard(unit)
	local p = getPassiveInSlot(unit, "Head")
	return p == "Interact on hazard tile neutralizes it permanently"
end

--------------------------------------------------
-- HD-015  Mechanist Headgear
-- "Interact on allied objects/summons: restore 1 charge or +500 CT duration"
--------------------------------------------------
--- Returns a refresh config or nil.
--- Config: { chargeRestore = 1, durationBonus = 500 }
function ArmorPassiveService.GetInteractRefreshConfig(unit)
	local p = getPassiveInSlot(unit, "Head")
	if p == "Interact on allied objects/summons: restore 1 charge or +500 CT duration" then
		return { chargeRestore = 1, durationBonus = 500 }
	end
	return nil
end

--------------------------------------------------
-- HD-018  Merchant's Turban
-- "Interact on shop objects: all prices reduced by 20%"
--------------------------------------------------
--- Returns the shop discount percentage (0–1 float). 0 = no discount.
function ArmorPassiveService.GetInteractShopDiscount(unit)
	local p = getPassiveInSlot(unit, "Head")
	if p == "Interact on shop objects: all prices reduced by 20%" then return 0.20 end
	return 0
end

--------------------------------------------------
-- HD-019  Oracle Diadem
-- "Interact reveals enemy stats, skills, and AI behavior for 1000 CT"
--------------------------------------------------
--- Returns the scout reveal duration in CT, or 0.
function ArmorPassiveService.GetInteractScoutDuration(unit)
	local p = getPassiveInSlot(unit, "Head")
	if p == "Interact reveals enemy stats, skills, and AI behavior for 1000 CT" then
		return 1000
	end
	return 0
end

--------------------------------------------------
-- HD-020  Commandant Helm
-- "Interact on ally: target gains +20% damage for 500 CT"
--------------------------------------------------
--- Returns a damage-buff config when Interact targets an ally, or nil.
--- Config: { damageBonus = 0.20, durationCt = 500 }
function ArmorPassiveService.GetInteractDamageBuffConfig(unit)
	local p = getPassiveInSlot(unit, "Head")
	if p == "Interact on ally: target gains +20% damage for 500 CT" then
		return { damageBonus = 0.20, durationCt = 500 }
	end
	return nil
end

--==========================================================
--  BODY  ·  GUARD  (20 passives: BD-001 … BD-020)
--==========================================================

--------------------------------------------------
-- BD-001  Brigandine
-- "While Guarding: damage reduction 35%→45% (cap still 80%)"
--------------------------------------------------
--- Returns the bonus added to Guard damage reduction.
--- Base Guard DR is 35%; BD-001 raises it to 45% → bonus = 0.10.
function ArmorPassiveService.GetGuardMitigationBonus(unit)
	local p = getPassiveInSlot(unit, "Body")
	if not p then return 0 end

	if string.find(p, "damage reduction 35", 1, true) then
		return 0.10 -- 35% → 45%
	end

	return 0
end

--------------------------------------------------
-- BD-002  Fortress Plate
-- "While Guarding: incoming displacement/push is negated"
--------------------------------------------------
function ArmorPassiveService.CanGuardNegatePush(unit)
	local p = getPassiveInSlot(unit, "Body")
	return p ~= nil and string.find(p, "incoming displacement/push is negated", 1, true) ~= nil
end

--------------------------------------------------
-- BD-003  Duelist Jerkin
-- "Guard RT ×0.60 (faster Guard recovery)"
--------------------------------------------------
--- Returns the RT multiplier for the Guard action. Default 1.0.
function ArmorPassiveService.GetGuardRtModifier(unit)
	local p = getPassiveInSlot(unit, "Body")
	if p and string.find(p, "Guard RT", 1, true) then
		if string.find(p, "0.60", 1, true) then return 0.60 end
	end
	return 1.0
end

--------------------------------------------------
-- BD-004  Anchor Mail
-- "While Guarding: Stability +3"
--------------------------------------------------
--- Returns the Stability bonus while Guarding.
function ArmorPassiveService.GetGuardStabilityBonus(unit)
	local p = getPassiveInSlot(unit, "Body")
	if p == "While Guarding: Stability +3" then return 3 end
	return 0
end

--------------------------------------------------
-- BD-005  Reactive Cuirass
-- "First hit received each turn triggers auto-Guard at no AP"
--------------------------------------------------
--- Returns true if auto-Guard should trigger for first hit this turn.
--- Caller must set unit._armorAutoGuardUsed = true after triggering.
function ArmorPassiveService.CanAutoGuard(unit)
	local p = getPassiveInSlot(unit, "Body")
	if p ~= nil and string.find(p, "First hit received each turn triggers auto-Guard", 1, true) then
		return not unit._armorAutoGuardUsed
	end
	return false
end

--------------------------------------------------
-- BD-006  Layered Lamellar
-- "While Guarding: each successive hit in same Guard reduces damage by
--  additional 5% (stacks to +20%)"
--------------------------------------------------
--- Returns the stacking DR bonus for the current Guard session.
--- Caller must increment unit._armorLayeredHitCount after each hit.
function ArmorPassiveService.GetGuardLayeredBonus(unit)
	local p = getPassiveInSlot(unit, "Body")
	if p and string.find(p, "successive hit in same Guard", 1, true) then
		local count = unit._armorLayeredHitCount or 0
		return math.min(count * 0.05, 0.20)
	end
	return 0
end

--------------------------------------------------
-- BD-007  Mirror Mail
-- "While Guarding: projectile attacks are reflected back at 30% damage"
--------------------------------------------------
--- Returns the reflect config or nil.
--- Config: { reflectPercent = 0.30 }
function ArmorPassiveService.GetGuardProjectileReflect(unit)
	local p = getPassiveInSlot(unit, "Body")
	if p and string.find(p, "projectile attacks are reflected back", 1, true) then
		return { reflectPercent = 0.30 }
	end
	return nil
end

--------------------------------------------------
-- BD-008  Grounding Harness
-- "Forced displacement distance reduced by 2 (always active)"
--------------------------------------------------
--- Returns the displacement distance reduction (always active, not Guard-only).
function ArmorPassiveService.GetDisplacementReduction(unit)
	local p = getPassiveInSlot(unit, "Body")
	if p and string.find(p, "Forced displacement distance reduced by 2", 1, true) then
		return 2
	end
	return 0
end

--------------------------------------------------
-- BD-009  Reprisal Coat
-- "While Guarding: store 40% of damage mitigated; next Basic Attack adds
--  stored damage"
--------------------------------------------------
--- Returns the store config or nil.
--- Config: { storePercent = 0.40 }
--- Stored damage lives in unit._armorReprisalStored.
--- Caller adds stored damage to next BA, then zeroes the field.
function ArmorPassiveService.GetGuardReprisalConfig(unit)
	local p = getPassiveInSlot(unit, "Body")
	if p and string.find(p, "store 40%% of damage mitigated", 1, true) then
		return { storePercent = 0.40 }
	end
	return nil
end

--- Returns stored reprisal damage and resets it.
function ArmorPassiveService.ConsumeReprisalDamage(unit)
	local stored = unit._armorReprisalStored or 0
	unit._armorReprisalStored = 0
	return stored
end

--------------------------------------------------
-- BD-010  Wardweave Robe
-- "While Guarding: immune to new debuff application"
--------------------------------------------------
function ArmorPassiveService.CanGuardImmuneDebuff(unit)
	local p = getPassiveInSlot(unit, "Body")
	return p ~= nil and string.find(p, "immune to new debuff application", 1, true) ~= nil
end

--------------------------------------------------
-- BD-011  Hazard Suit
-- "While Guarding: immune to terrain/hazard/weather damage"
--------------------------------------------------
function ArmorPassiveService.CanGuardImmuneHazard(unit)
	local p = getPassiveInSlot(unit, "Body")
	return p ~= nil and string.find(p, "immune to terrain/hazard/weather damage", 1, true) ~= nil
end

--------------------------------------------------
-- BD-012  Collision Padding
-- "Collision and fall damage reduced by 50%"
--------------------------------------------------
--- Returns the collision/fall damage multiplier. Always active (not Guard-only).
function ArmorPassiveService.GetCollisionFallDamageModifier(unit)
	local p = getPassiveInSlot(unit, "Body")
	if p and string.find(p, "Collision and fall damage reduced by 50", 1, true) then
		return 0.50 -- multiplier: take 50% damage
	end
	return 1.0
end

--------------------------------------------------
-- BD-013  Feather Armor
-- "Reduce effective fall height by 2 while Guarding"
--------------------------------------------------
--- Returns the fall height reduction while Guarding.
function ArmorPassiveService.GetGuardFallHeightReduction(unit)
	local p = getPassiveInSlot(unit, "Body")
	if p and string.find(p, "Reduce effective fall height by 2", 1, true) then
		return 2
	end
	return 0
end

--------------------------------------------------
-- BD-014  Guardian Mantle
-- "While Guarding: adjacent allies also receive 50% of Guard damage reduction"
--------------------------------------------------
--- Returns the ally protection config or nil.
--- Config: { radius = 1, drShare = 0.50 }
function ArmorPassiveService.GetGuardAllyProtection(unit)
	local p = getPassiveInSlot(unit, "Body")
	if p and string.find(p, "adjacent allies also receive 50", 1, true) then
		return { radius = 1, drShare = 0.50 }
	end
	return nil
end

--------------------------------------------------
-- BD-015  Sentinel Carapace
-- "While Guarding: enemies that end Move adjacent to this unit lose 2
--  Movement Range next turn"
--------------------------------------------------
--- Returns the movement penalty config or nil.
--- Config: { radius = 1, movePenalty = 2 }
function ArmorPassiveService.GetGuardMovementPenaltyAura(unit)
	local p = getPassiveInSlot(unit, "Body")
	if p and string.find(p, "enemies that end Move adjacent", 1, true) then
		return { radius = 1, movePenalty = 2 }
	end
	return nil
end

--------------------------------------------------
-- BD-016  Spiked Plate
-- "While Guarding: attackers take 20% of their own damage as retaliation"
--------------------------------------------------
--- Returns the retaliation percentage (0–1). 0 = none.
function ArmorPassiveService.GetGuardRetaliationPercent(unit)
	local p = getPassiveInSlot(unit, "Body")
	if p and string.find(p, "attackers take 20", 1, true) then
		return 0.20
	end
	return 0
end

--------------------------------------------------
-- BD-017  Ablative Shell
-- "While Guarding: gain Shield equal to 15% of Max HP before damage"
--------------------------------------------------
--- Returns the Shield percentage of Max HP granted before Guard damage, or 0.
function ArmorPassiveService.GetGuardShieldPercent(unit)
	local p = getPassiveInSlot(unit, "Body")
	if p and string.find(p, "gain Shield equal to 15", 1, true) then
		return 0.15
	end
	return 0
end

--------------------------------------------------
-- BD-018  Interception Armor
-- "While Guarding: may intercept attacks targeting adjacent allies"
--------------------------------------------------
--- Returns true if this unit can intercept attacks on adjacent allies while Guarding.
function ArmorPassiveService.CanGuardIntercept(unit)
	local p = getPassiveInSlot(unit, "Body")
	return p ~= nil and string.find(p, "may intercept attacks targeting adjacent allies", 1, true) ~= nil
end

--------------------------------------------------
-- BD-019  Second-Wind Vest
-- "While Guarding: recover 10% of Max HP"
--------------------------------------------------
--- Returns the HP regen percentage applied when Guard is activated, or 0.
function ArmorPassiveService.GetGuardRegenPercent(unit)
	local p = getPassiveInSlot(unit, "Body")
	if p == "While Guarding: recover 10% of Max HP" then
		return 0.10
	end
	return 0
end

--------------------------------------------------
-- BD-020  Unyielding Aegis
-- "Once per battle: survive lethal direct damage at 1 HP"
--------------------------------------------------
--- Returns true if the unit should survive lethal direct damage.
--- Caller must set unit._armorLethalSurviveUsed = true after use.
function ArmorPassiveService.CanSurviveLethalDamage(unit)
	local p = getPassiveInSlot(unit, "Body")
	if p and string.find(p, "Once per battle: survive lethal", 1, true) then
		return not unit._armorLethalSurviveUsed
	end
	return false
end

--==========================================================
--  GLOVES  ·  PUSH  (21 passives: GL-001 … GL-021)
--==========================================================

--------------------------------------------------
-- PUSH FORCE BONUS
-- Multiple glove passives modify Push Force.
-- GL-001: +1 (plus stability ignore)
-- GL-002: +3
-- GL-006: +3 when targeting ally
-- GL-008: +3 when target is a movable object
-- GL-018: +0.5 per tile moved this turn (rounded down)
--
-- context: { isAlly = bool, isObject = bool }
--------------------------------------------------
function ArmorPassiveService.GetPushForceBonus(unit, context)
	local p = getPassiveInSlot(unit, "Gloves")
	if not p then return 0 end

	-- GL-001: Push Force +1. Ignore up to 2 enemy Stability
	if string.find(p, "Push Force +1", 1, true) then
		return 1
	end

	-- GL-002: Push Force +3
	if p == "Push Force +3" then
		return 3
	end

	-- GL-006: Push Force +3 when targeting ally
	if string.find(p, "Push Force +3 when targeting ally", 1, true) then
		if context and context.isAlly then return 3 end
		return 0
	end

	-- GL-008: Push Force +3 when target is a movable object
	if p == "Push Force +3 when target is a movable object" then
		if context and context.isObject then return 3 end
		return 0
	end

	-- GL-018: For each tile moved this turn, Push Force +0.5 (rounded down)
	if string.find(p, "Push Force +0.5", 1, true) then
		local tiles = unit._armorTilesMovedThisTurn or 0
		return math.floor(tiles * 0.5)
	end

	return 0
end

--------------------------------------------------
-- GL-001 Stability Ignore
-- "Push Force +1. Ignore up to 2 enemy Stability"
--------------------------------------------------
--- Returns the amount of enemy Stability to ignore during Push.
function ArmorPassiveService.GetPushStabilityIgnore(unit)
	local p = getPassiveInSlot(unit, "Gloves")
	if p and string.find(p, "Ignore up to 2 enemy Stability", 1, true) then
		return 2
	end
	return 0
end

--------------------------------------------------
-- PUSH RT MODIFIER
-- GL-003: Push RT Cost ×0.75
-- GL-006: RT ×0.50 when targeting ally
-- GL-021: RT Cost ×2 for the free push
--
-- context: { isAlly = bool, isFreePush = bool }
--------------------------------------------------
function ArmorPassiveService.GetPushRtModifier(unit, context)
	local p = getPassiveInSlot(unit, "Gloves")
	if not p then return 1.0 end

	-- GL-003
	if string.find(p, "Push RT Cost \xc3\x970.75", 1, true) then
		return 0.75
	end

	-- GL-006: ×0.50 for ally pushes
	if string.find(p, "Push Force +3 when targeting ally", 1, true) then
		if context and context.isAlly then return 0.50 end
		return 1.0
	end

	-- GL-021: ×2 for the free push
	if string.find(p, "first Push action does not cost AP", 1, true) then
		if context and context.isFreePush then return 2.0 end
		return 1.0
	end

	return 1.0
end

--------------------------------------------------
-- GL-004  Longarm Bracers
-- "Push Maximum Range +1"
--------------------------------------------------
function ArmorPassiveService.GetPushRangeBonus(unit)
	local p = getPassiveInSlot(unit, "Gloves")
	if p == "Push Maximum Range +1" then return 1 end
	return 0
end

--------------------------------------------------
-- GL-005  Butcher's Gloves  — Push becomes Pull
-- GL-017  Grappler's Wraps  — Swap then Push
--
-- Returns a conversion config or nil.
--------------------------------------------------
function ArmorPassiveService.GetPushConversionConfig(unit)
	local p = getPassiveInSlot(unit, "Gloves")
	if not p then return nil end

	-- GL-005: Pull
	if string.find(p, "Push becomes Pull instead", 1, true) then
		return {
			mode = "Pull",
			rangeBonus = 3,
			minRange = 2,
			reverseDirection = true,
			selfCollision = true,  -- user-target collision possible
		}
	end

	-- GL-017: Swap + Push
	if string.find(p, "Swap position with target", 1, true) then
		return {
			mode = "Swap",
			swapBeforePush = true,
			pushFromOriginalPos = true,
		}
	end

	return nil
end

--------------------------------------------------
-- GL-006  Ally Launcher
-- "Push Force +3 when targeting ally; RT ×0.50. Allied Push causes no
--  collision damage"
--------------------------------------------------
--- Returns the ally push config or nil.
function ArmorPassiveService.GetPushAllyConfig(unit)
	local p = getPassiveInSlot(unit, "Gloves")
	if p and string.find(p, "Push Force +3 when targeting ally", 1, true) then
		return {
			forceBonus = 3,
			rtMultiplier = 0.50,
			noCollisionDamage = true,
		}
	end
	return nil
end

--------------------------------------------------
-- GL-007  Demolition Mitts
-- "When Push causes a movable object to collide, the object detonates as
--  a Bomb Barrel: 3×3 explosion (30% Max HP damage)"
--------------------------------------------------
--- Returns the object detonation config or nil.
function ArmorPassiveService.GetPushObjectDetonation(unit)
	local p = getPassiveInSlot(unit, "Gloves")
	if p and string.find(p, "object detonates as a Bomb Barrel", 1, true) then
		return {
			aoeSize = 3,
			damagePercent = 0.30, -- 30% Max HP
			destroysBreakable = true,
		}
	end
	return nil
end

--------------------------------------------------
-- PUSH COLLISION CONFIG
-- GL-009: Wall collision ×1.25, user follows target
-- GL-012: Double to Shields/barriers, ignores Guard
-- GL-014: Transfer remaining Force to collided target
-- GL-020: Cardinal adjacents displaced 1 tile away
--------------------------------------------------
function ArmorPassiveService.GetPushCollisionConfig(unit)
	local p = getPassiveInSlot(unit, "Gloves")
	if not p then return nil end

	-- GL-009 Ram Gauntlets
	if string.find(p, "Wall collision damage from Push gains", 1, true) then
		return {
			type = "Ram",
			wallDamageMultiplier = 1.25,
			userFollows = true,
		}
	end

	-- GL-012 Crushing Vambraces
	if string.find(p, "Push collision damage deals double to Shields", 1, true) then
		return {
			type = "Crush",
			doubleVsShields = true,
			ignoreGuard = true,
		}
	end

	-- GL-014 Chain-Push Bracers
	if string.find(p, "transfer remaining Force to collided target", 1, true) then
		return {
			type = "Chain",
			transferForce = true,
		}
	end

	-- GL-020 Shockwave Gauntlets
	if string.find(p, "cardinally adjacent to collision tile", 1, true) then
		return {
			type = "Shockwave",
			splashDisplacement = 1,
			cardinal = true,
		}
	end

	return nil
end

--------------------------------------------------
-- GL-010  Edgefinder Gloves
-- "When Push forces target downward, treat Fall Height as +1"
--------------------------------------------------
function ArmorPassiveService.GetPushFallHeightBonus(unit)
	local p = getPassiveInSlot(unit, "Gloves")
	if p and string.find(p, "treat Fall Height as +1", 1, true) then
		return 1
	end
	return 0
end

--------------------------------------------------
-- GL-011  Staggering Fists
-- "Push applies +75 RT Delay and −1 Movement Range on target's next turn"
--------------------------------------------------
--- Returns the debuff config applied to pushed target, or nil.
function ArmorPassiveService.GetPushDebuffConfig(unit)
	local p = getPassiveInSlot(unit, "Gloves")
	if p and string.find(p, "+75 RT Delay", 1, true) then
		return { rtDelay = 75, movePenalty = -1 }
	end
	return nil
end

--------------------------------------------------
-- GL-013  Vector Gloves
-- "For adjacent targets, choose any legal outward direction"
--------------------------------------------------
function ArmorPassiveService.CanPushChooseDirection(unit)
	local p = getPassiveInSlot(unit, "Gloves")
	return p ~= nil and string.find(p, "choose any legal outward direction", 1, true) ~= nil
end

--------------------------------------------------
-- GL-015  Throwing Gloves
-- "Decrease elevation of tile where pushed unit landed by 1. Push uses
--  arc projectile rules"
--------------------------------------------------
--- Returns the arc push config or nil.
function ArmorPassiveService.GetPushArcConfig(unit)
	local p = getPassiveInSlot(unit, "Gloves")
	if p and string.find(p, "Push uses arc projectile rules", 1, true) then
		return {
			elevationDecrease = 1,
			arcProjectile = true,
		}
	end
	return nil
end

--------------------------------------------------
-- GL-016  Fighter's Gauntlets
-- "Push deals 30% of base weapon damage and triggers weapon on-hit effects"
--------------------------------------------------
--- Returns the push damage config or nil.
function ArmorPassiveService.GetPushDamageConfig(unit)
	local p = getPassiveInSlot(unit, "Gloves")
	if p and string.find(p, "Push deals 30", 1, true) then
		return {
			weaponDamagePercent = 0.30,
			triggersOnHit = true,
		}
	end
	return nil
end

--------------------------------------------------
-- GL-019  Counterforce Gloves
-- "After successfully pushing a unit, trigger Guard at no additional AP"
--------------------------------------------------
function ArmorPassiveService.CanPushTriggerGuard(unit)
	local p = getPassiveInSlot(unit, "Gloves")
	return p ~= nil and string.find(p, "trigger Guard at no additional AP", 1, true) ~= nil
end

--------------------------------------------------
-- GL-021  Initiator's Grips
-- "Once per turn, the first Push action does not cost AP. That Push has
--  RT Cost ×2 and Force ×0.5 (rounded down, minimum Force 1)"
--------------------------------------------------
--- Returns the free push config or nil.
--- Caller must set unit._armorFreePushUsed = true after use.
function ArmorPassiveService.GetFreePushConfig(unit)
	local p = getPassiveInSlot(unit, "Gloves")
	if p and string.find(p, "first Push action does not cost AP", 1, true) then
		if not unit._armorFreePushUsed then
			return {
				freeAp = true,
				rtMultiplier = 2.0,
				forceMultiplier = 0.5,
				minForce = 1,
			}
		end
	end
	return nil
end

--==========================================================
--  FEET  ·  MOVE  (20 passives: FT-001 … FT-020)
--==========================================================

--------------------------------------------------
-- MOVEMENT RANGE BONUS
-- Multiple feet passives modify movement range.
-- Returns the net integer offset to add to base movement range.
-- FT-001: +2 (permanent)
-- FT-011: +3 first move each turn
-- FT-012: +2 second move same turn
-- FT-015: −2 (teleport trade-off)
-- FT-016: −1 (fire trail trade-off)
-- FT-018: −2 (rescue trade-off)
-- FT-019: −2 (kick trade-off)
--------------------------------------------------
function ArmorPassiveService.GetMovementRangeBonus(unit)
	local p = getPassiveInSlot(unit, "Feet")
	if not p then return 0 end

	-- FT-001: +2 permanent
	if p == "Movement Range +2 (permanent)" then return 2 end

	-- FT-011: first move +3
	if string.find(p, "First Move each turn gains Movement Range +3", 1, true) then
		if not unit._armorFirstMoveUsed then return 3 end
		return 0
	end

	-- FT-012: second move +2
	if string.find(p, "Second Move same turn", 1, true) then
		if (unit._armorMoveCountThisTurn or 0) >= 1 then return 2 end
		return 0
	end

	-- FT-015: teleport −2
	if string.find(p, "Movement type changes to teleport", 1, true) then
		return -2
	end

	-- FT-016: fire trail −1
	if string.find(p, "Tiles traversed this Move are set on fire", 1, true) then
		return -1
	end

	-- FT-018: rescue −2
	if string.find(p, "end Move on ally's tile", 1, true) then
		return -2
	end

	-- FT-019: kick −2
	if string.find(p, "end Move on enemy's tile", 1, true) then
		return -2
	end

	return 0
end

--------------------------------------------------
-- MOVEMENT RT MODIFIER
-- FT-002: Base Movement RT ×0.75
-- FT-012: second move RT ×0.50
-- FT-015: teleport RT ×2
-- FT-018: rescue RT ×2
-- FT-019: kick RT ×2
--------------------------------------------------
function ArmorPassiveService.GetMoveRtModifier(unit)
	local p = getPassiveInSlot(unit, "Feet")
	if not p then return 1.0 end

	-- FT-002
	if string.find(p, "Base Movement RT \xc3\x970.75", 1, true) then return 0.75 end

	-- FT-012: second move ×0.50
	if string.find(p, "Second Move same turn", 1, true) then
		if (unit._armorMoveCountThisTurn or 0) >= 1 then return 0.50 end
		return 1.0
	end

	-- FT-015: teleport ×2
	if string.find(p, "Movement type changes to teleport", 1, true) then
		return 2.0
	end

	-- FT-018: rescue ×2
	if string.find(p, "end Move on ally's tile", 1, true) then
		return 2.0
	end

	-- FT-019: kick ×2
	if string.find(p, "end Move on enemy's tile", 1, true) then
		return 2.0
	end

	return 1.0
end

--------------------------------------------------
-- FT-003  Heavy March Boots
-- "Gain Stability +1 until next turn for each tile moved"
--------------------------------------------------
--- Returns the stability config or nil.
--- Caller tracks unit._armorMarchStabilityBonus.
function ArmorPassiveService.GetMoveStabilityConfig(unit)
	local p = getPassiveInSlot(unit, "Feet")
	if p and string.find(p, "Stability +1 until next turn for each tile moved", 1, true) then
		return { stabilityPerTile = 1 }
	end
	return nil
end

--------------------------------------------------
-- FT-004  Pathfinder Boots
-- "Ignore extra movement-cost penalties from terrain"
--------------------------------------------------
function ArmorPassiveService.CanIgnoreTerrainCost(unit)
	local p = getPassiveInSlot(unit, "Feet")
	return p ~= nil and string.find(p, "Ignore extra movement-cost penalties from terrain", 1, true) ~= nil
end

--------------------------------------------------
-- FT-005  Levitation Boots
-- "Ignore effects of Shallow Water, Deep Water, and Wet tile effects"
--------------------------------------------------
function ArmorPassiveService.CanIgnoreWaterEffects(unit)
	local p = getPassiveInSlot(unit, "Feet")
	return p ~= nil and string.find(p, "Ignore effects of Shallow Water", 1, true) ~= nil
end

--------------------------------------------------
-- FT-006  Climbing Boots
-- "Jump +2"
--------------------------------------------------
function ArmorPassiveService.GetJumpBonus(unit)
	local p = getPassiveInSlot(unit, "Feet")
	if p == "Jump +2" then return 2 end
	return 0
end

--------------------------------------------------
-- FT-007  Softstep Slippers
-- "Moving across trap tiles does not trigger them; ending on tile still
--  triggers"
--------------------------------------------------
function ArmorPassiveService.CanAvoidTrapsInPath(unit)
	local p = getPassiveInSlot(unit, "Feet")
	return p ~= nil and string.find(p, "Moving across trap tiles does not trigger them", 1, true) ~= nil
end

--------------------------------------------------
-- FT-008  Skirmisher Greaves
-- "After moving ≥3 path-cost, next direct damage action this turn gains
--  +15% final damage"
--------------------------------------------------
--- Returns the skirmish damage config or nil.
--- Caller tracks unit._armorPathCostThisTurn.
function ArmorPassiveService.GetMoveSkirmishDamageBonus(unit)
	local p = getPassiveInSlot(unit, "Feet")
	if p and string.find(p, "path-cost, next direct damage action", 1, true) then
		if (unit._armorPathCostThisTurn or 0) >= 3 then
			return 0.15
		end
	end
	return 0
end

--------------------------------------------------
-- FT-009  Retreat Boots
-- "If every step increased distance from nearest enemy, gain
--  Evasiveness +20% until next turn"
--------------------------------------------------
--- Returns the retreat config or nil.
--- Caller evaluates the path, then sets unit._armorRetreatBonusActive.
function ArmorPassiveService.GetMoveRetreatConfig(unit)
	local p = getPassiveInSlot(unit, "Feet")
	if p and string.find(p, "Evasiveness +20", 1, true) then
		return { evasivenessBonus = 0.20 }
	end
	return nil
end

--- Returns the active retreat evasiveness bonus for this unit.
function ArmorPassiveService.GetRetreatEvasivenessBonus(unit)
	if unit._armorRetreatBonusActive then return 0.20 end
	return 0
end

--------------------------------------------------
-- FT-010  Vanguard Greaves
-- "If Move ends adjacent to enemy, gain 15% direct final damage reduction
--  until next turn"
--------------------------------------------------
--- Returns the vanguard DR config or nil.
--- Caller sets unit._armorVanguardDrActive after Move.
function ArmorPassiveService.GetMoveVanguardConfig(unit)
	local p = getPassiveInSlot(unit, "Feet")
	if p and string.find(p, "gain 15%% direct final damage reduction", 1, true) then
		return { damageReduction = 0.15 }
	end
	return nil
end

--- Returns the active vanguard damage reduction.
function ArmorPassiveService.GetVanguardDamageReduction(unit)
	if unit._armorVanguardDrActive then return 0.15 end
	return 0
end

--------------------------------------------------
-- FT-013  Ice Cleats
-- "Does not slide from voluntary movement or end-of-move effects on
--  Ice/Oily tiles"
--------------------------------------------------
function ArmorPassiveService.CanAvoidIceSlide(unit)
	local p = getPassiveInSlot(unit, "Feet")
	return p ~= nil and string.find(p, "Does not slide from voluntary movement", 1, true) ~= nil
end

--------------------------------------------------
-- FT-014  Firewalker Sabatons
-- "Crossing Burning or Molten tiles does not apply their cross effect"
--------------------------------------------------
function ArmorPassiveService.CanAvoidFireTerrain(unit)
	local p = getPassiveInSlot(unit, "Feet")
	return p ~= nil and string.find(p, "Crossing Burning or Molten tiles", 1, true) ~= nil
end

--------------------------------------------------
-- FT-015  Portal Treads
-- "Movement type changes to teleport …"
--------------------------------------------------
function ArmorPassiveService.IsMoveTypeTeleport(unit)
	local p = getPassiveInSlot(unit, "Feet")
	return p ~= nil and string.find(p, "Movement type changes to teleport", 1, true) ~= nil
end

--------------------------------------------------
-- FT-016  Trailblazer Boots
-- "Tiles traversed this Move are set on fire. Does not burn unit's final
--  tile. Movement −1"
--------------------------------------------------
--- Returns the fire trail config or nil.
function ArmorPassiveService.GetMoveFireTrailConfig(unit)
	local p = getPassiveInSlot(unit, "Feet")
	if p and string.find(p, "Tiles traversed this Move are set on fire", 1, true) then
		return {
			setFire = true,
			burnFinalTile = false,
			movementPenalty = -1,
		}
	end
	return nil
end

--------------------------------------------------
-- FT-017  Pursuer Greaves
-- "If Move ends adjacent to enemy, apply 50 RT delay to all adjacent
--  enemies. Once per turn"
--------------------------------------------------
--- Returns the pursuer config or nil.
--- Caller must set unit._armorPursuerUsed = true after use.
function ArmorPassiveService.GetMovePursuerConfig(unit)
	local p = getPassiveInSlot(unit, "Feet")
	if p and string.find(p, "apply 50 RT delay to all adjacent enemies", 1, true) then
		if not unit._armorPursuerUsed then
			return { rtDelay = 50 }
		end
	end
	return nil
end

--------------------------------------------------
-- FT-018  Rescue Spurs
-- "May end Move on ally's tile; move ally to last tile crossed.
--  Movement −2, RT ×2"
--------------------------------------------------
--- Returns the rescue config or nil.
function ArmorPassiveService.GetMoveRescueConfig(unit)
	local p = getPassiveInSlot(unit, "Feet")
	if p and string.find(p, "end Move on ally's tile", 1, true) then
		return {
			canEndOnAllyTile = true,
			relocateAllyToLastTile = true,
			movementPenalty = -2,
			rtMultiplier = 2.0,
		}
	end
	return nil
end

--------------------------------------------------
-- FT-019  Kick Boots
-- "May end Move on enemy's tile; trigger Knockback on enemy in enemy's
--  facing direction. Movement −2, RT ×2"
--------------------------------------------------
--- Returns the kick config or nil.
function ArmorPassiveService.GetMoveKickConfig(unit)
	local p = getPassiveInSlot(unit, "Feet")
	if p and string.find(p, "end Move on enemy's tile", 1, true) then
		return {
			canEndOnEnemyTile = true,
			knockbackDirection = "enemyFacing",
			movementPenalty = -2,
			rtMultiplier = 2.0,
		}
	end
	return nil
end

--------------------------------------------------
-- FT-020  Phantom Steps
-- "May move through enemy-occupied tiles. Each enemy tile costs +2
--  movement and triggers compatible reactions"
--------------------------------------------------
function ArmorPassiveService.CanMoveThroughEnemies(unit)
	local p = getPassiveInSlot(unit, "Feet")
	return p ~= nil and string.find(p, "May move through enemy-occupied tiles", 1, true) ~= nil
end

--- Returns the extra movement cost per enemy tile traversed, or 0.
function ArmorPassiveService.GetMoveThroughEnemyCost(unit)
	local p = getPassiveInSlot(unit, "Feet")
	if p and string.find(p, "May move through enemy-occupied tiles", 1, true) then
		return 2
	end
	return 0
end

--==========================================================
--  ACCESSORY  ·  ITEM  (20 passives: AC-001 … AC-020)
--==========================================================

--------------------------------------------------
-- AC-001  Utility Belt
-- "Equipped Item slot capacity +1"
--------------------------------------------------
function ArmorPassiveService.GetItemSlotBonus(unit)
	local p = getPassiveInSlot(unit, "Accessory")
	if p == "Equipped Item slot capacity +1" then return 1 end
	return 0
end

--------------------------------------------------
-- AC-002  Quickdraw Pouch — Item RT Cost ×0.75
-- AC-016  Courier's Seal  — Item RT +50% (×1.50)
-- AC-019  Quartermaster Badge — Item RT +20% (×1.20)
--------------------------------------------------
--- Returns the base RT multiplier for Item actions.
function ArmorPassiveService.GetItemRtModifier(unit)
	local p = getPassiveInSlot(unit, "Accessory")
	if not p then return 1.0 end

	-- AC-002
	if string.find(p, "Item RT Cost \xc3\x970.75", 1, true) then return 0.75 end

	-- AC-016
	if string.find(p, "Ally-targeted Item effects also apply to user", 1, true) then
		return 1.50
	end

	-- AC-019
	if string.find(p, "share Item charges", 1, true) then
		return 1.20
	end

	return 1.0
end

--------------------------------------------------
-- AC-003  Long-Throw Strap
-- "Item Maximum Range +2"
--------------------------------------------------
function ArmorPassiveService.GetItemRangeBonus(unit)
	local p = getPassiveInSlot(unit, "Accessory")
	if p == "Item Maximum Range +2" then return 2 end
	return 0
end

--------------------------------------------------
-- AC-004  Grenadier Satchel
-- "Damaging consumable Items gain +15% final damage"
--------------------------------------------------
--- Returns the damage bonus multiplier for damaging consumable Items.
function ArmorPassiveService.GetItemDamageBonus(unit)
	local p = getPassiveInSlot(unit, "Accessory")
	if p and string.find(p, "Damaging consumable Items gain +15", 1, true) then
		return 0.15
	end
	return 0
end

--------------------------------------------------
-- AC-005  Wide-Fuse Kit
-- "Single-target damage Items gain Impact Splash (adjacent tiles at 50%)"
--------------------------------------------------
--- Returns the splash config or nil.
function ArmorPassiveService.GetItemSplashConfig(unit)
	local p = getPassiveInSlot(unit, "Accessory")
	if p and string.find(p, "Impact Splash", 1, true) then
		return { splashPercent = 0.50, adjacentOnly = true }
	end
	return nil
end

--------------------------------------------------
-- AC-006  Medic's Case
-- "Items restore +50% HP/MP"
--------------------------------------------------
--- Returns the healing bonus multiplier for restore Items.
function ArmorPassiveService.GetItemHealBonus(unit)
	local p = getPassiveInSlot(unit, "Accessory")
	if p and string.find(p, "Items restore +50", 1, true) then
		return 0.50
	end
	return 0
end

--------------------------------------------------
-- AC-007  Overflowing Flask
-- "Restoring Items also grant regen equal to 7% of restored amount
--  per 100 CT for 500 CT"
--------------------------------------------------
--- Returns the regen config or nil.
function ArmorPassiveService.GetItemRegenConfig(unit)
	local p = getPassiveInSlot(unit, "Accessory")
	if p and string.find(p, "regen equal to 7", 1, true) then
		return {
			regenPercent = 0.07,  -- per 100 CT
			durationCt   = 500,
			tickCt       = 100,
		}
	end
	return nil
end

--------------------------------------------------
-- AC-008  Preservation Case
-- "When taking direct damage from enemy, recharge 1 item charge.
--  Cannot target items at max charge"
--------------------------------------------------
--- Returns the recharge-on-damage config or nil.
function ArmorPassiveService.GetItemRechargeOnDamageConfig(unit)
	local p = getPassiveInSlot(unit, "Accessory")
	if p and string.find(p, "recharge 1 item charge", 1, true) then
		return { chargeRestore = 1, skipMaxCharge = true }
	end
	return nil
end

--------------------------------------------------
-- AC-009  Reinforced Cartridge
-- "Increase equipped item use charges by 20%, min +1"
--------------------------------------------------
--- Returns the charge bonus config or nil.
function ArmorPassiveService.GetItemChargeBonus(unit)
	local p = getPassiveInSlot(unit, "Accessory")
	if p and string.find(p, "Increase equipped item use charges by 20", 1, true) then
		return { percent = 0.20, minBonus = 1 }
	end
	return nil
end

--------------------------------------------------
-- AC-010  Expiry Extender
-- "Item effect duration +500 CT"
--------------------------------------------------
function ArmorPassiveService.GetItemDurationBonus(unit)
	local p = getPassiveInSlot(unit, "Accessory")
	if p == "Item effect duration +500 CT" then return 500 end
	return 0
end

--------------------------------------------------
-- AC-011  Terraformer Token
-- "Item usage raises target tile elevation by 1"
--------------------------------------------------
--- Returns the tile elevation config or nil.
function ArmorPassiveService.GetItemTileElevationConfig(unit)
	local p = getPassiveInSlot(unit, "Accessory")
	if p and string.find(p, "raises target tile elevation by 1", 1, true) then
		return { elevationIncrease = 1 }
	end
	return nil
end

--------------------------------------------------
-- AC-012  Trapmaker's Roll
-- "Trap Items placed at Range +3 and remain active +500 CT"
--------------------------------------------------
--- Returns the trap config or nil.
function ArmorPassiveService.GetItemTrapConfig(unit)
	local p = getPassiveInSlot(unit, "Accessory")
	if p and string.find(p, "Trap Items placed at Range +3", 1, true) then
		return { rangeBonus = 3, durationBonus = 500 }
	end
	return nil
end

--------------------------------------------------
-- AC-013  Deployable Toolkit
-- "Summoned units gain +25% Max HP"
--------------------------------------------------
--- Returns the summon HP bonus multiplier, or 0.
function ArmorPassiveService.GetItemSummonHpBonus(unit)
	local p = getPassiveInSlot(unit, "Accessory")
	if p and string.find(p, "Summoned units gain +25", 1, true) then
		return 0.25
	end
	return 0
end

--------------------------------------------------
-- AC-014  Bomber Ring
-- "Completely REPLACES item effect/identity with bomb …"
--------------------------------------------------
--- Returns the bomber config or nil.
function ArmorPassiveService.GetItemBomberConfig(unit)
	local p = getPassiveInSlot(unit, "Accessory")
	if p and string.find(p, "REPLACES item effect/identity with bomb", 1, true) then
		return {
			range = 3,
			isAoe = true,
			rt = 110,
			-- Bomb_Damage = round((50 + Level × 4) × 0.18)
			getDamage = function(level)
				return math.round((50 + level * 4) * 0.18)
			end,
		}
	end
	return nil
end

--------------------------------------------------
-- AC-015  Emergency Locket
-- "Once per turn. When HP ≤25% outside unit turn, auto-use heal item …"
--------------------------------------------------
--- Returns the auto-heal config or nil.
--- Caller must set unit._armorAutoHealUsed = true after use.
function ArmorPassiveService.GetAutoHealConfig(unit)
	local p = getPassiveInSlot(unit, "Accessory")
	if p and string.find(p, "auto-use heal item", 1, true) then
		if not unit._armorAutoHealUsed then
			return {
				hpThreshold = 0.25,
				outsideTurnOnly = true,
				consumesCharge = true,
				noApCost = true,
				rtMultiplier = 2.0,
			}
		end
	end
	return nil
end

--------------------------------------------------
-- AC-016  Courier's Seal
-- "Ally-targeted Item effects also apply to user. Item RT +50%"
--------------------------------------------------
--- Returns the self-apply config or nil.
function ArmorPassiveService.GetItemSelfApplyConfig(unit)
	local p = getPassiveInSlot(unit, "Accessory")
	if p and string.find(p, "Ally-targeted Item effects also apply to user", 1, true) then
		return {
			selfApply = true,
			rtMultiplier = 1.50,
		}
	end
	return nil
end

--------------------------------------------------
-- AC-017  Conservation Charm
-- "Once per turn, when the user performs a second manually committed Item
--  action during the same turn, the primary Item used by that action does
--  not consume a charge. Double that primary Item's authored base RT …"
--------------------------------------------------
--- Returns the conservation config or nil.
--- Caller tracks unit._armorManualItemCount and _armorConservationUsed.
function ArmorPassiveService.GetItemConservationConfig(unit)
	local p = getPassiveInSlot(unit, "Accessory")
	if p and string.find(p, "second manually committed Item action", 1, true) then
		if not unit._armorConservationUsed and (unit._armorManualItemCount or 0) >= 1 then
			return {
				noChargeConsume = true,
				rtMultiplier = 2.0,
			}
		end
	end
	return nil
end

--------------------------------------------------
-- AC-018  Field Alchemist Emblem
-- "Every 2 basic attacks, recharge 1 item with least charges.
--  Cannot target max charge"
--------------------------------------------------
--- Returns the alchemist config or nil.
--- Caller tracks unit._armorAlchemistBaCount.
function ArmorPassiveService.GetItemAlchemistConfig(unit)
	local p = getPassiveInSlot(unit, "Accessory")
	if p and string.find(p, "Every 2 basic attacks", 1, true) then
		return {
			attackThreshold = 2,
			chargeRestore = 1,
			skipMaxCharge = true,
		}
	end
	return nil
end

--- Called after each Basic Attack. Returns true if a recharge should trigger.
function ArmorPassiveService.OnBasicAttackForAlchemist(unit)
	local config = ArmorPassiveService.GetItemAlchemistConfig(unit)
	if not config then return false end
	unit._armorAlchemistBaCount = (unit._armorAlchemistBaCount or 0) + 1
	if unit._armorAlchemistBaCount >= config.attackThreshold then
		unit._armorAlchemistBaCount = 0
		return true
	end
	return false
end

--------------------------------------------------
-- AC-019  Quartermaster Badge
-- "At battle start, choose 1 ally. User and chosen ally share Item
--  charges … Item RT +20%"
--------------------------------------------------
--- Returns the item-share config or nil.
--- unit._armorQmPartnerId is set during battle-start ally selection.
function ArmorPassiveService.GetItemShareConfig(unit)
	local p = getPassiveInSlot(unit, "Accessory")
	if p and string.find(p, "share Item charges", 1, true) then
		return {
			partnerId = unit._armorQmPartnerId,
			rtMultiplier = 1.20,
		}
	end
	return nil
end

--------------------------------------------------
-- AC-020  Masterwork Toolchain
-- "Once per turn, when the user commits an Item with an authored base RT
--  of 120 or less, the user may select a second equipped Item …"
--------------------------------------------------
--- Returns the bundle config or nil.
--- Caller must set unit._armorBundleUsed = true after use.
function ArmorPassiveService.GetItemBundleConfig(unit)
	local p = getPassiveInSlot(unit, "Accessory")
	if p and string.find(p, "may select a second equipped Item", 1, true) then
		if not unit._armorBundleUsed then
			return {
				maxBaseRt = 120,
				bundledRtMultiplier = 0.50,
				apCost = 1, -- single AP for both
				cannotBundle = {
					"Heavy", "Battlefield",
					"chargeRestoration", "itemCopy",
					"grantItemAction", "bundled", "triggered", "copied",
				},
			}
		end
	end
	return nil
end

--==========================================================
--  MOVE / PUSH TRACKING HOOKS
--  Called by BattleCoordinator / CommandService.
--==========================================================

--- Called after each Move completes to update per-turn tracking.
--- pathCost: the total movement-cost spent for this move.
--- tilesTraversed: integer count of tiles in the path.
function ArmorPassiveService.OnMoveCompleted(unit, pathCost, tilesTraversed)
	if not unit then return end
	unit._armorMoveCountThisTurn = (unit._armorMoveCountThisTurn or 0) + 1
	unit._armorPathCostThisTurn  = (unit._armorPathCostThisTurn  or 0) + (pathCost or 0)
	unit._armorTilesMovedThisTurn = (unit._armorTilesMovedThisTurn or 0) + (tilesTraversed or 0)

	-- FT-011: mark first move used
	if not unit._armorFirstMoveUsed then
		unit._armorFirstMoveUsed = true
	end

	-- FT-003: accumulate stability per tile
	local stabCfg = ArmorPassiveService.GetMoveStabilityConfig(unit)
	if stabCfg then
		unit._armorMarchStabilityBonus = (unit._armorMarchStabilityBonus or 0)
			+ (tilesTraversed or 0) * stabCfg.stabilityPerTile
	end
end

--- Returns the accumulated stability bonus from Heavy March Boots (FT-003).
function ArmorPassiveService.GetMarchStabilityBonus(unit)
	return unit and unit._armorMarchStabilityBonus or 0
end

--- Called after a Guard session ends to reset BD-006 hit counter.
function ArmorPassiveService.OnGuardEnd(unit)
	if not unit then return end
	unit._armorLayeredHitCount = 0
end

--- Called after each hit received during Guard for BD-006.
function ArmorPassiveService.OnGuardHitReceived(unit)
	if not unit then return end
	unit._armorLayeredHitCount = (unit._armorLayeredHitCount or 0) + 1
end

--- Called after Guard mitigates damage to accumulate BD-009 reprisal store.
function ArmorPassiveService.OnGuardDamageMitigated(unit, mitigatedAmount)
	if not unit then return end
	local cfg = ArmorPassiveService.GetGuardReprisalConfig(unit)
	if cfg then
		local stored = (unit._armorReprisalStored or 0) + math.round(mitigatedAmount * cfg.storePercent)
		unit._armorReprisalStored = stored
	end
end

return ArmorPassiveService
