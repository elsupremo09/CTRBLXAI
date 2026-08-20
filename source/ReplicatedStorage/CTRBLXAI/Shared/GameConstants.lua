-- GameConstants.lua
-- CTRBLXAI | Shared numeric constants
--
-- Single source of truth for constants that are used by more than one
-- server module. Require this module instead of defining local copies.
--
-- Location: ReplicatedStorage/CTRBLXAI/Shared/GameConstants
-- (ReplicatedStorage so both server and future client modules can access it)

local GameConstants = {}

--------------------------------------------------
-- TIMELINE  (from DB: core_stats — Timeline AP RT)
--------------------------------------------------

-- Base RT for a standard unit. All action RT costs are additive on top of this.
-- Full turn RT = BASE_RT_STANDARD + sum of action costs.
-- Rest RT (no voluntary action) = round(BASE_RT_STANDARD × 0.75).
GameConstants.BASE_RT_STANDARD = 400

-- AP granted to a standard unit at the start of each turn.
GameConstants.AP_PER_TURN_STANDARD = 2

-- Boss unit overrides (not used in Slice 1, reserved for later).
GameConstants.BASE_RT_BOSS        = 300
GameConstants.AP_PER_TURN_BOSS    = 3

-- Rest RT multiplier (no action taken this turn).
GameConstants.REST_RT_MULTIPLIER  = 0.75

--------------------------------------------------
-- ACTION RT COST MULTIPLIERS
-- (additive on top of BASE_RT_STANDARD per turn)
--------------------------------------------------

-- Move RT per tile = BASE_RT_STANDARD × this factor.
GameConstants.MOVE_RT_FACTOR          = 0.0625

-- Basic Attack base RT = round(BASE_RT_STANDARD × this factor) + Weapon WT.
GameConstants.BASIC_ATTACK_RT_FACTOR  = 0.10

return GameConstants
