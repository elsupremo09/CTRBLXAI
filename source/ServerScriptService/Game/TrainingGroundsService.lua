--!strict
-- TrainingGroundsService.lua
-- CTRBLXAI | Training Grounds facility (USER DECISION 2026-11-04): the old Training Ground and
-- Library merged into one card shop. This module owns the max-level effect:
--   * 2nd augment slot on every skill row opens only at Training Grounds L10 AND unit level 80+
--   * enemies level 80+ may carry a 2nd augment only once the quest owner's Training Grounds is
--     L10: Elite 100%, Veteran 50%, Grunt 25%
-- (The card shop is added in a later step.)
--
-- The facility level is INJECTED (ARC-004 / ARC-006, nil-safe; 0 = not built). Requires no
-- game service, so anything may require it without a cycle (AP-013).

local TrainingGroundsService = {}

local MAX_LEVEL = 10
local SLOT2_UNIT_LEVEL = 80
local ENEMY_SLOT2_LEVEL = 80
local ENEMY_SLOT2_CHANCE = table.freeze({ Elite = 100, Veteran = 50, Grunt = 25 })

-- Approved player-facing text (user 2026-11-04).
TrainingGroundsService.LOCKED_SLOT_TEXT = "Unlocks at Training Grounds Lv 10 and unit Lv 80."

local _getLevel: (() -> number)? = nil
local pendingMoved = 0 -- augments moved to storage, waiting to be told to the player

function TrainingGroundsService.SetLevelProvider(fn: () -> number)
	_getLevel = fn
end

function TrainingGroundsService.GetLevel(): number
	local l = _getLevel and _getLevel() or 0
	return math.clamp(math.floor(tonumber(l) or 0), 0, MAX_LEVEL)
end

function TrainingGroundsService.IsMaxed(): boolean
	return TrainingGroundsService.GetLevel() >= MAX_LEVEL
end

-- Is augment slot 2 open for this player unit?
function TrainingGroundsService.IsSlot2Open(unit: any): boolean
	if type(unit) ~= "table" then return false end
	return TrainingGroundsService.IsMaxed() and (tonumber(unit.level) or 0) >= SLOT2_UNIT_LEVEL
end

-- Chance (0-100) that a generated enemy's skill row gets a 2nd augment.
function TrainingGroundsService.EnemySlot2Chance(enemyType: string, level: number): number
	if not TrainingGroundsService.IsMaxed() or level < ENEMY_SLOT2_LEVEL then return 0 end
	return ENEMY_SLOT2_CHANCE[enemyType] or 0
end

-- Load notice (approved wording). Counts accumulate until shown once.
function TrainingGroundsService.AddMoved(n: number)
	if n > 0 then pendingMoved += n end
end

function TrainingGroundsService.TakeNotice(): string?
	if pendingMoved <= 0 then return nil end
	local n = pendingMoved
	pendingMoved = 0
	return `2nd augment slots are locked until your Training Grounds is fully upgraded and the unit reaches level 80. {n} augment(s) were moved to storage.`
end


-- Guild Hall next-level info (USER RULING 2026-11-17 5:18 PM, guild_facilities 113): this level's
-- numbers, read from the tables above (DAT-001). Display only; BuildingService builds the lines.
function TrainingGroundsService.Slot2Level(): number
	return MAX_LEVEL -- the 2nd augment slot opens at max level (and unit Lv 80)
end
return table.freeze(TrainingGroundsService)
