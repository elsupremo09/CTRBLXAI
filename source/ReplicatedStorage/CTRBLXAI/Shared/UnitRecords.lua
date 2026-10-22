-- UnitRecords.lua
-- CTRBLXAI | Shared client-side holder for the CURRENT MATCH's unit records.
--
-- WHY THIS EXISTS (2026-10-22, deployment->battle unification, Slice 1):
-- Deployment (DeploymentUI) and battle (BattleVisualClient) are two separate
-- client scripts that each kept their OWN copy of unit info and rebuilt it at
-- battle start. That split was the root cause of the "present in one phase,
-- missing in the other" bug class (facing, HP/MP, stats). A ModuleScript required
-- by multiple LocalScripts on the SAME client runs once and returns the SAME
-- cached table, so this module is a single shared place both scripts can read and
-- write -- "build once, carry across, update" instead of "wipe and rebuild".
--
-- SLICE STATUS: Slice 1 (this module) + Slice 2 (deployment writes here) are inert
-- setup -- nothing READS these records yet, so behavior is unchanged. Slice 3 (not
-- yet done) will switch battle start to UPDATE these records instead of wiping and
-- rebuilding unitData. Until Slice 3 lands, this holder is populated but unused.
--
-- Location: ReplicatedStorage/CTRBLXAI/Shared/UnitRecords

local UnitRecords = {}

-- [unitId] = record table (the per-unit client packet; shape = the server's
-- shared SerializeUnit output, optionally with client-only fields layered on).
local records = {}

-- Store (or replace) a unit's record.
function UnitRecords.Set(unitId, record)
	if unitId == nil then return end
	records[unitId] = record
end

-- Fetch one unit's record (nil if absent).
function UnitRecords.Get(unitId)
	if unitId == nil then return nil end
	return records[unitId]
end

-- The whole table (live reference; callers must not mutate structure casually).
function UnitRecords.GetAll()
	return records
end

-- Shallow-merge updates onto an existing record (creates it if missing). Used by
-- the future Slice 3 battle-start path to layer final battle values (turn order,
-- confirmed facing, etc.) onto the record carried over from deployment.
function UnitRecords.Update(unitId, fields)
	if unitId == nil or type(fields) ~= "table" then return end
	local rec = records[unitId]
	if not rec then rec = {}; records[unitId] = rec end
	for k, v in pairs(fields) do
		rec[k] = v
	end
end

-- Remove one unit (e.g. a benched unit that never entered battle).
function UnitRecords.Remove(unitId)
	if unitId ~= nil then records[unitId] = nil end
end

-- Clear everything (call when a match fully ends / before a fresh deployment).
function UnitRecords.Clear()
	table.clear(records)
end

return UnitRecords
