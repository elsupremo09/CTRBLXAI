--!strict
-- DungeonMapUse.lua
-- CTRBLXAI | Consumables usable on the dungeon map between rooms (rule 266, silver/Bag step 3, 2026-11-16).
-- One table for server (DungeonLoadout.UseItem) and client (Loadout "Use" button) - DAT-001.
-- Only heal / MP / revive items work on the map. Cleanse-only items (REC-013 Antidote Injector, REC-016
-- Purification Device) have nothing to remove there: statuses never carry between battles
-- (PersistentStateService keeps HP / MP / KO only), so they stay "Only usable in battle." (SB-24).
-- Agent defaults (2026-11-16, user may veto):
--   * over-time heals give their full total at once (REC-007 12+6+6 = 24%, REC-008 8% x5 = 40%);
--   * shields / RT parts are ignored on the map (REC-019 = 40% HP; REC-017 / REC-018 revive at their % HP);
--   * heal + cleanse items keep only the heal (REC-014 25%, REC-015 10%);
--   * REC-020 Field Restorative Array heals every party unit that isn't KO (its battle area = "each ally").
-- hp / mp = % of max, revive = % of max HP for a KO unit, party = every non-KO party unit.

export type Effect = { hp: number?, mp: number?, revive: number?, party: boolean? }

local M = {}

M.Effects = table.freeze({
	["REC-001"] = table.freeze({ hp = 30 }),
	["REC-002"] = table.freeze({ hp = 30 }),
	["REC-003"] = table.freeze({ hp = 50 }),
	["REC-004"] = table.freeze({ hp = 50 }),
	["REC-005"] = table.freeze({ hp = 75 }),
	["REC-006"] = table.freeze({ hp = 75 }),
	["REC-007"] = table.freeze({ hp = 24 }),
	["REC-008"] = table.freeze({ hp = 40 }),
	["REC-009"] = table.freeze({ mp = 25 }),
	["REC-010"] = table.freeze({ mp = 25 }),
	["REC-011"] = table.freeze({ mp = 50 }),
	["REC-012"] = table.freeze({ mp = 50 }),
	["REC-014"] = table.freeze({ hp = 25 }),
	["REC-015"] = table.freeze({ hp = 10 }),
	["REC-017"] = table.freeze({ revive = 25 }),
	["REC-018"] = table.freeze({ revive = 40 }),
	["REC-019"] = table.freeze({ hp = 40 }),
	["REC-020"] = table.freeze({ hp = 20, mp = 15, party = true }),
}) :: { [string]: Effect }

--- The map effect of a consumable, or nil when it is battle-only.
function M.Get(consumableId: any): Effect?
	if type(consumableId) ~= "string" then return nil end
	return M.Effects[consumableId]
end

return table.freeze(M)
